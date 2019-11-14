include "../lib/Base/Maps.s.dfy"
include "../lib/Base/sequences.i.dfy"
include "../lib/Base/Option.s.dfy"
include "../lib/Base/NativeTypes.s.dfy"
include "../lib/DataStructures/LRU.i.dfy"
include "../lib/DataStructures/MutableMapModel.i.dfy"
include "../lib/DataStructures/MutableMapImpl.i.dfy"
include "PivotBetreeSpec.i.dfy"
include "AsyncSectorDiskModel.i.dfy"
include "BlockCacheSystem.i.dfy"
include "../lib/Marshalling/GenericMarshalling.i.dfy"
include "../lib/DataStructures/Bitmap.i.dfy"
include "IndirectionTableModel.i.dfy"
//
// The heap-y implementation of IndirectionTableModel.
//

module IndirectionTableImpl {
  import opened Maps
  import opened Sets
  import opened Options
  import opened Sequences
  import opened NativeTypes
  import ReferenceType`Internal
  import BT = PivotBetreeSpec`Internal
  import BC = BetreeGraphBlockCache
  import LruModel
  import MutableMapModel
  import MutableMap
  import LBAType
  import opened GenericMarshalling
  import Bitmap
  import opened Bounds
  import IndirectionTableModel
  import MutableLru

  type HashMap = MutableMap.ResizingHashMap<IndirectionTableModel.Entry>

  // TODO move bitmap in here?
  class IndirectionTable {
    var t: HashMap;
    var garbageQueue: MutableLru.MutableLruQueue?;
    ghost var Repr: set<object>;

    protected predicate Inv()
    reads this, Repr
    ensures Inv() ==> this in Repr
    {
      && this in Repr
      && this.t in Repr
      && (this.garbageQueue != null ==> this.garbageQueue in Repr)
      && this.Repr == {this} + this.t.Repr + (if this.garbageQueue != null then this.garbageQueue.Repr else {})
      && this !in this.t.Repr
      && this.t.Inv()
      && (this.garbageQueue != null ==> this.garbageQueue.Inv())
      && (this.garbageQueue != null ==> this.garbageQueue.Repr !! this.t.Repr)
      && (this.garbageQueue != null ==> this !in this.garbageQueue.Repr)

      && var predCounts := IndirectionTableModel.PredCounts(this.t.I());
      && var graph := IndirectionTableModel.Graph(this.t.I());
      && IndirectionTableModel.ValidPredCounts(predCounts, graph)
      && BC.GraphClosed(graph)
      && (forall ref | ref in graph :: |graph[ref]| <= MaxNumChildren())
      && (this.garbageQueue != null ==> (
        && (forall ref | ref in this.t.I().contents && t.I().contents[ref].predCount == 0 :: ref in LruModel.I(garbageQueue.Queue))
        && (forall ref | ref in LruModel.I(garbageQueue.Queue) :: ref in t.I().contents && t.I().contents[ref].predCount == 0)
      ))
      && BT.G.Root() in t.I().contents
      && this.t.Count as int <= IndirectionTableModel.MaxSize()
    }

    protected function I() : IndirectionTableModel.IndirectionTable
    reads this, Repr
    requires Inv()
    ensures IndirectionTableModel.Inv(I())
    {
      var res := IndirectionTableModel.FromHashMap(t.I(), if garbageQueue != null then Some(garbageQueue.Queue) else None);
      IndirectionTableModel.reveal_Inv(res);
      res
    }

    // Dummy constructor only used when ImplVariables is in a state with no indirection
    // table. We could use a null indirection table instead, it's just slightly more
    // annoying to do that because we'd need additional invariants.
    constructor Empty()
    ensures Inv()
    ensures fresh(Repr)
    {
      this.t := new MutableMap.ResizingHashMap(128);
      new;
      // This is not important, but needed to satisfy the Inv:
      this.t.Insert(BT.G.Root(), IndirectionTableModel.Entry(None, [], 1));
      this.garbageQueue := null;
      Repr := {this} + this.t.Repr;
    }

    constructor(t: HashMap)
    ensures this.t == t
    ensures this.garbageQueue == null
    {
      this.t := t;
      this.garbageQueue := null;
    }

    method Clone()
    returns (table : IndirectionTable)
    requires Inv()
    ensures table.Inv()
    ensures fresh(table.Repr)
    ensures table.I() == IndirectionTableModel.clone(old(I()))
    {
      var t0 := this.t.Clone();
      table := new IndirectionTable(t0);

      table.Repr := {table} + table.t.Repr + (if table.garbageQueue != null then table.garbageQueue.Repr else {});
      IndirectionTableModel.reveal_clone();
    }

    method GetEntry(ref: BT.G.Reference) returns (e : Option<IndirectionTableModel.Entry>)
    requires Inv()
    ensures e == IndirectionTableModel.GetEntry(I(), ref)
    {
      IndirectionTableModel.reveal_GetEntry();
      e := this.t.Get(ref);
    }

    method HasEmptyLoc(ref: BT.G.Reference) returns (b: bool)
    requires Inv()
    ensures b == IndirectionTableModel.HasEmptyLoc(I(), ref)
    {
      var entry := this.t.Get(ref);
      b := entry.Some? && entry.value.loc.None?;
    }

    method RemoveLoc(ref: BT.G.Reference)
    returns (oldLoc: Option<BC.Location>)
    requires Inv()
    requires IndirectionTableModel.TrackingGarbage(I())
    requires ref in I().graph
    modifies Repr
    ensures Inv()
    ensures forall o | o in Repr :: fresh(o) || o in old(Repr)
    ensures (I(), oldLoc) == IndirectionTableModel.RemoveLoc(old(I()), ref)
    {
      IndirectionTableModel.reveal_RemoveLoc();

      var oldEntry := t.Get(ref);
      var predCount := oldEntry.value.predCount;
      var succs := oldEntry.value.succs;
      t.Insert(ref, IndirectionTableModel.Entry(None, succs, predCount));

      oldLoc := oldEntry.value.loc;

      Repr := {this} + this.t.Repr + (if this.garbageQueue != null then this.garbageQueue.Repr else {});
      ghost var _ := IndirectionTableModel.RemoveLoc(old(I()), ref);
    }

    method AddLocIfPresent(ref: BT.G.Reference, loc: BC.Location)
    returns (added : bool)
    requires Inv()
    modifies Repr
    ensures Inv()
    ensures forall o | o in Repr :: fresh(o) || o in old(Repr)
    ensures (I(), added) == IndirectionTableModel.AddLocIfPresent(old(I()), ref, loc)
    {
      IndirectionTableModel.reveal_AddLocIfPresent();

      assume this.t.Count as nat < 0x10000000000000000 / 8;
      var oldEntry := this.t.Get(ref);
      added := oldEntry.Some? && oldEntry.value.loc.None?;
      if added {
        this.t.Insert(ref, IndirectionTableModel.Entry(Some(loc), oldEntry.value.succs, oldEntry.value.predCount));
      }

      Repr := {this} + this.t.Repr + (if this.garbageQueue != null then this.garbageQueue.Repr else {});
      ghost var _ := IndirectionTableModel.AddLocIfPresent(old(I()), ref, loc);
    }

    method RemoveRef(ref: BT.G.Reference)
    returns (oldLoc : Option<BC.Location>)
    requires Inv()
    requires IndirectionTableModel.TrackingGarbage(I())
    requires IndirectionTableModel.deallocable(I(), ref)
    modifies Repr
    ensures Inv()
    ensures forall o | o in Repr :: fresh(o) || o in old(Repr)
    ensures (I(), oldLoc) == IndirectionTableModel.RemoveRef(old(I()), ref)
    {
      IndirectionTableModel.reveal_RemoveRef();

      IndirectionTableModel.lemma_count_eq_graph_size(I().t);
      IndirectionTableModel.LemmaRemoveRefStuff(I(), ref);

      var oldEntry := this.t.RemoveAndGet(ref);

      IndirectionTableModel.lemma_count_eq_graph_size(this.t.I());

      this.garbageQueue.Remove(ref);
      UpdatePredCounts(this.t, this.garbageQueue, ref, [], oldEntry.value.succs);

      IndirectionTableModel.lemma_count_eq_graph_size(this.t.I());

      oldLoc := if oldEntry.Some? then oldEntry.value.loc else None;

      Repr := {this} + this.t.Repr + (if this.garbageQueue != null then this.garbageQueue.Repr else {});
      ghost var _ := IndirectionTableModel.RemoveRef(old(I()), ref);
    }

    static method PredInc(t: HashMap, q: MutableLru.MutableLruQueue, ref: BT.G.Reference)
    requires t.Inv()
    requires q.Inv()
    requires t.Count as nat < 0x1_0000_0000_0000_0000 / 8
    requires ref in t.I().contents
    requires t.I().contents[ref].predCount < 0xffff_ffff_ffff_ffff
    requires t.Repr !! q.Repr
    modifies t.Repr
    modifies q.Repr
    ensures forall o | o in t.Repr :: o in old(t.Repr) || fresh(o)
    ensures forall o | o in q.Repr :: o in old(q.Repr) || fresh(o)
    ensures t.Repr !! q.Repr
    ensures t.Inv()
    ensures q.Inv()
    ensures (t.I(), q.Queue) == IndirectionTableModel.PredInc(old(t.I()), old(q.Queue), ref)
    {
      var oldEntryOpt := t.Get(ref);
      var oldEntry := oldEntryOpt.value;
      var newEntry := oldEntry.(predCount := oldEntry.predCount + 1);
      t.Insert(ref, newEntry);
      if oldEntry.predCount == 0 {
        q.Remove(ref);
      }
    }

    static method PredDec(t: HashMap, q: MutableLru.MutableLruQueue, ref: BT.G.Reference)
    requires t.Inv()
    requires q.Inv()
    requires t.Count as nat < 0x1_0000_0000_0000_0000 / 8
    requires ref in t.I().contents
    requires t.I().contents[ref].predCount > 0
    requires t.Repr !! q.Repr
    modifies t.Repr
    modifies q.Repr
    ensures forall o | o in t.Repr :: o in old(t.Repr) || fresh(o)
    ensures forall o | o in q.Repr :: o in old(q.Repr) || fresh(o)
    ensures t.Repr !! q.Repr
    ensures t.Inv()
    ensures q.Inv()
    ensures (t.I(), q.Queue) == IndirectionTableModel.PredDec(old(t.I()), old(q.Queue), ref)
    {
      var oldEntryOpt := t.Get(ref);
      var oldEntry := oldEntryOpt.value;
      var newEntry := oldEntry.(predCount := oldEntry.predCount - 1);
      t.Insert(ref, newEntry);
      if oldEntry.predCount == 1 {
        assume |LruModel.I(q.Queue)| <= 0x1_0000_0000;
        q.Use(ref);
      }
    }

    static method UpdatePredCounts(t: HashMap, q: MutableLru.MutableLruQueue, ghost changingRef: BT.G.Reference,
        newSuccs: seq<BT.G.Reference>, oldSuccs: seq<BT.G.Reference>)
    requires t.Inv()
    requires q.Inv()
    requires t.Repr !! q.Repr
    requires IndirectionTableModel.RefcountUpdateInv(t.I(), q.Queue, changingRef, newSuccs, oldSuccs, 0, 0)
    modifies t.Repr
    modifies q.Repr
    ensures forall o | o in t.Repr :: o in old(t.Repr) || fresh(o)
    ensures forall o | o in q.Repr :: o in old(q.Repr) || fresh(o)
    ensures t.Repr !! q.Repr
    ensures t.Inv()
    ensures q.Inv()
    ensures (t.I(), q.Queue) == IndirectionTableModel.UpdatePredCountsInc(old(t.I()), old(q.Queue), changingRef, newSuccs, oldSuccs, 0)
    {
      var idx: uint64 := 0;

      while idx < |newSuccs| as uint64
      invariant forall o | o in t.Repr :: o in old(t.Repr) || fresh(o)
      invariant forall o | o in q.Repr :: o in old(q.Repr) || fresh(o)
      invariant t.Repr !! q.Repr
      invariant t.Inv()
      invariant q.Inv()
      invariant IndirectionTableModel.RefcountUpdateInv(t.I(), q.Queue, changingRef, newSuccs, oldSuccs, idx as int, 0)
      invariant IndirectionTableModel.UpdatePredCountsInc(old(t.I()), old(q.Queue), changingRef, newSuccs, oldSuccs, 0)
             == IndirectionTableModel.UpdatePredCountsInc(t.I(), q.Queue, changingRef, newSuccs, oldSuccs, idx)
      decreases |newSuccs| - idx as int
      {
        IndirectionTableModel.LemmaUpdatePredCountsIncStuff(t.I(), q.Queue, changingRef, newSuccs, oldSuccs, idx as int);

        PredInc(t, q, newSuccs[idx]);
        idx := idx + 1;
      }

      var idx2: uint64 := 0;

      while idx2 < |oldSuccs| as uint64
      invariant forall o | o in t.Repr :: o in old(t.Repr) || fresh(o)
      invariant forall o | o in q.Repr :: o in old(q.Repr) || fresh(o)
      invariant t.Repr !! q.Repr
      invariant t.Inv()
      invariant q.Inv()
      invariant IndirectionTableModel.RefcountUpdateInv(t.I(), q.Queue, changingRef, newSuccs, oldSuccs, |newSuccs|, idx2 as int)
      invariant IndirectionTableModel.UpdatePredCountsInc(old(t.I()), old(q.Queue), changingRef, newSuccs, oldSuccs, 0)
             == IndirectionTableModel.UpdatePredCountsDec(t.I(), q.Queue, changingRef, newSuccs, oldSuccs, idx2)
      decreases |oldSuccs| - idx2 as int
      {
        IndirectionTableModel.LemmaUpdatePredCountsDecStuff(t.I(), q.Queue, changingRef, newSuccs, oldSuccs, idx2 as int);

        PredDec(t, q, oldSuccs[idx2]);
        idx2 := idx2 + 1;
      }
    }

    method UpdateAndRemoveLoc(ref: BT.G.Reference, succs: seq<BT.G.Reference>)
    returns (oldLoc : Option<BC.Location>)
    requires Inv()
    requires IndirectionTableModel.TrackingGarbage(I())
    requires |succs| <= MaxNumChildren()
    requires |I().graph| < IndirectionTableModel.MaxSize()
    requires IndirectionTableModel.SuccsValid(succs, I().graph)
    modifies Repr
    ensures Inv()
    ensures forall o | o in Repr :: fresh(o) || o in old(Repr)
    ensures (I(), oldLoc)  == IndirectionTableModel.UpdateAndRemoveLoc(old(I()), ref, succs)
    {
      IndirectionTableModel.reveal_UpdateAndRemoveLoc();

      IndirectionTableModel.lemma_count_eq_graph_size(I().t);
      IndirectionTableModel.LemmaUpdateAndRemoveLocStuff(I(), ref, succs);

      var oldEntry := this.t.Get(ref);
      var predCount := if oldEntry.Some? then oldEntry.value.predCount else 0;
      if oldEntry.None? {
        assume |LruModel.I(this.garbageQueue.Queue)| <= 0x1_0000_0000;
        this.garbageQueue.Use(ref);
      }
      this.t.Insert(ref, IndirectionTableModel.Entry(None, succs, predCount));

      IndirectionTableModel.lemma_count_eq_graph_size(this.t.I());

      UpdatePredCounts(this.t, this.garbageQueue, ref, succs,
          if oldEntry.Some? then oldEntry.value.succs else []);

      IndirectionTableModel.lemma_count_eq_graph_size(this.t.I());

      //IndirectionTableModel.LemmaValidPredCountsOfValidPredCountsIntermediate(IndirectionTableModel.PredCounts(this.t.I()), IndirectionTableModel.Graph(this.t.I()), succs, if oldEntry.Some? then oldEntry.value.succs else []);

      oldLoc := if oldEntry.Some? && oldEntry.value.loc.Some? then oldEntry.value.loc else None;

      Repr := {this} + this.t.Repr + (if this.garbageQueue != null then this.garbageQueue.Repr else {});
      ghost var _ := IndirectionTableModel.UpdateAndRemoveLoc(old(I()), ref, succs);
    }

    // Parsing and marshalling

    static method {:fuel ValInGrammar,3} ValToHashMap(a: seq<V>) returns (s : Option<HashMap>)
    requires IndirectionTableModel.valToHashMap.requires(a)
    ensures s.None? ==> IndirectionTableModel.valToHashMap(a).None?
    ensures s.Some? ==> s.value.Inv()
    ensures s.Some? ==> Some(s.value.I()) == IndirectionTableModel.valToHashMap(a)
    ensures s.Some? ==> s.value.Count as nat == |a|
    ensures s.Some? ==> s.value.Count as nat < 0x1_0000_0000_0000_0000 / 8
    ensures s.Some? ==> fresh(s.value) && fresh(s.value.Repr)
    {
      assume |a| < 0x1_0000_0000_0000_0000;
      if |a| as uint64 == 0 {
        var newHashMap := new MutableMap.ResizingHashMap<IndirectionTableModel.Entry>(1024); // TODO(alattuada) magic numbers
        s := Some(newHashMap);
        assume s.value.Count as nat == |a|;
      } else {
        var res := ValToHashMap(a[..|a| as uint64 - 1]);
        match res {
          case Some(mutMap) => {
            var tuple := a[|a| as uint64 - 1];
            var ref := tuple.t[0 as uint64].u;
            var lba := tuple.t[1 as uint64].u;
            var len := tuple.t[2 as uint64].u;
            var succs := Some(tuple.t[3 as uint64].ua);
            match succs {
              case None => {
                s := None;
              }
              case Some(succs) => {
                var graphRef := mutMap.Get(ref);
                var loc := LBAType.Location(lba, len);

                assume |succs| < 0x1_0000_0000_0000_0000; // should follow from ValidVal, just need to add that as precondition

                if graphRef.Some? || lba == 0 || !LBAType.ValidLocation(loc)
                    || |succs| as uint64 > MaxNumChildrenUint64() {
                  s := None;
                } else {
                  mutMap.Insert(ref, IndirectionTableModel.Entry(Some(loc), succs, 0));
                  s := Some(mutMap);
                  assume s.Some? ==> s.value.Count as nat < 0x10000000000000000 / 8; // TODO(alattuada) removing this results in trigger loop
                  assume s.value.Count as nat == |a|;
                }
              }
            }
          }
          case None => {
            s := None;
          }
        }
      }
    }

    static method ComputeRefCounts(t: HashMap)
    returns (t' : MutableMap.ResizingHashMap?<IndirectionTableModel.Entry>)
    requires t.Inv()
    requires forall ref | ref in t.I().contents :: t.I().contents[ref].predCount == 0
    requires forall ref | ref in t.I().contents :: |t.I().contents[ref].succs| <= MaxNumChildren()
    requires t.I().count as int <= IndirectionTableModel.MaxSize()
    requires BT.G.Root() in t.I().contents
    ensures t' == null ==> IndirectionTableModel.ComputeRefCounts(old(t.I())) == None
    ensures t' != null ==> t'.Inv()
    ensures t' != null ==> IndirectionTableModel.ComputeRefCounts(old(t.I())) == Some(t'.I())
    ensures t' != null ==> fresh(t'.Repr)
    {
      IndirectionTableModel.LemmaComputeRefCountsIterateInvInit(t.I());

      var copy := t;
      var t1 := t.Clone();

      var oldEntryOpt := t1.Get(BT.G.Root());
      var oldEntry := oldEntryOpt.value;
      t1.Insert(BT.G.Root(), oldEntry.(predCount := 1));

      var it := copy.IterStart();
      while it.next.Some?
      invariant t1.Inv()
      invariant copy.Inv()
      invariant copy.Repr !! t1.Repr
      invariant fresh(t1.Repr)

      invariant IndirectionTableModel.ComputeRefCountsIterateInv(t1.I(), copy.I(), it)
      invariant BT.G.Root() in t1.I().contents
      invariant IndirectionTableModel.ComputeRefCounts(old(t.I()))
             == IndirectionTableModel.ComputeRefCountsIterate(t1.I(), copy.I(), it)
      decreases it.decreaser
      {
        IndirectionTableModel.LemmaComputeRefCountsIterateStuff(t1.I(), copy.I(), it);
        IndirectionTableModel.LemmaComputeRefCountsIterateValidPredCounts(t1.I(), copy.I(), it);

        ghost var t0 := t1.I();

        var succs := it.next.value.1.succs;
        var i: uint64 := 0;
        while i < |succs| as uint64
        invariant t1.Inv()
        invariant copy.Inv()
        invariant copy.Repr !! t1.Repr
        invariant fresh(t1.Repr)

        invariant BT.G.Root() in t1.I().contents
        invariant 0 <= i as int <= |succs|
        invariant |succs| <= MaxNumChildren()
        invariant t1.I().count as int <= IndirectionTableModel.MaxSize()
        invariant forall ref | ref in t1.I().contents :: t1.I().contents[ref].predCount as int <= 0x1_0000_0000_0000 + i as int
        invariant IndirectionTableModel.ComputeRefCounts(old(t.I()))
               == IndirectionTableModel.ComputeRefCountsIterate(t0, copy.I(), it)
        invariant IndirectionTableModel.ComputeRefCountsEntryIterate(t0, succs, 0)
               == IndirectionTableModel.ComputeRefCountsEntryIterate(t1.I(), succs, i)
        decreases |succs| - i as int
        {
          var ref := succs[i];
          var oldEntry := t1.Get(ref);
          if oldEntry.Some? {
            var newEntry := oldEntry.value.(predCount := oldEntry.value.predCount + 1);
            t1.Insert(ref, newEntry);
            i := i + 1;
          } else {
            return null;
          }
        }

        it := copy.IterInc(it);
      }

      return t1;
    }

    static method MakeGarbageQueue(t: HashMap)
    returns (q : MutableLru.MutableLruQueue)
    requires t.Inv()
    ensures q.Inv()
    ensures fresh(q.Repr)
    ensures q.Queue == IndirectionTableModel.makeGarbageQueue(t.I())
    {
      IndirectionTableModel.reveal_makeGarbageQueue();

      q := new MutableLru.MutableLruQueue();
      var it := t.IterStart();
      while it.next.Some?
      invariant q.Inv()
      invariant fresh(q.Repr)
      invariant MutableMapModel.Inv(t.I())
      invariant MutableMapModel.WFIter(t.I(), it)
      invariant IndirectionTableModel.makeGarbageQueue(t.I())
             == IndirectionTableModel.makeGarbageQueueIterate(t.I(), q.Queue, it)
      decreases it.decreaser
      {
        if it.next.value.1.predCount == 0 {
          LruModel.LruUse(q.Queue, it.next.value.0);
          assume |LruModel.I(q.Queue)| <= 0x1_0000_0000;
          q.Use(it.next.value.0);
        }
        it := t.IterInc(it);
      }
    }

    static method ValToIndirectionTable(v: V)
    returns (s : IndirectionTable?)
    requires IndirectionTableModel.valToIndirectionTable.requires(v)
    ensures s != null ==> s.Inv()
    ensures s != null ==> fresh(s.Repr)
    ensures s == null ==> IndirectionTableModel.valToIndirectionTable(v).None?
    ensures s != null ==> IndirectionTableModel.valToIndirectionTable(v) == Some(s.I())
    {
      var res := ValToHashMap(v.a);
      match res {
        case Some(t) => {
          var rootRef := t.Get(BT.G.Root());
          if rootRef.Some? && t.Count <= IndirectionTableModel.MaxSizeUint64() {
            var t1 := ComputeRefCounts(t);
            if t1 != null {
              IndirectionTableModel.lemmaMakeGarbageQueueCorrect(t1.I());
              IndirectionTableModel.lemma_count_eq_graph_size(t.I());
              IndirectionTableModel.lemma_count_eq_graph_size(t1.I());

              var q := MakeGarbageQueue(t1);
              s := new IndirectionTable(t1);
              s.garbageQueue := q;
              s.Repr := {s} + s.t.Repr + s.garbageQueue.Repr;
            } else {
              s := null;
            }
          } else {
            s := null;
          }
        }
        case None => {
          s := null;
        }
      }
    }

    function MaxIndirectionTableByteSize() : int {
      8 + IndirectionTableModel.MaxSize() * (8 + 8 + 8 + (8 + MaxNumChildren() * 8))
    }

    lemma lemma_SeqSum_prefix_array(a: array<V>, i: int)
    requires 0 < i <= a.Length
    ensures SeqSum(a[..i-1]) + SizeOfV(a[i-1]) == SeqSum(a[..i])
    {
      lemma_SeqSum_prefix(a[..i-1], a[i-1]);
      assert a[..i-1] + [a[i-1]] == a[..i];
    }

    lemma {:fuel SizeOfV,5} lemma_tuple_size(a: uint64, b: uint64, c: uint64, succs: seq<BT.G.Reference>)
    requires|succs| <= MaxNumChildren()
    ensures SizeOfV(VTuple([VUint64(a), VUint64(b), VUint64(c), VUint64Array(succs)]))
         <= (8 + 8 + 8 + (8 + MaxNumChildren() * 8))
    {
    }

    lemma lemma_SeqSum_empty()
    ensures SeqSum([]) == 0;
    {
      reveal_SeqSum();
    }

    method indirectionTableToVal()
    returns (v : Option<V>)
    requires Inv()
    requires BC.WFCompleteIndirectionTable(IndirectionTableModel.I(I()))
    ensures v.Some? ==> ValInGrammar(v.value, IndirectionTableModel.IndirectionTableGrammar())
    ensures v.Some? ==> ValidVal(v.value)
    ensures v.Some? ==> IndirectionTableModel.valToIndirectionTable(v.value).Some?
    ensures v.Some? ==>
          IndirectionTableModel.I(IndirectionTableModel.valToIndirectionTable(v.value).value)
       == IndirectionTableModel.I(I())
    ensures v.Some? ==> SizeOfV(v.value) <= MaxIndirectionTableByteSize()
    {
      assert t.Count <= IndirectionTableModel.MaxSizeUint64();
      lemma_SeqSum_empty();
      var a: array<V> := new V[t.Count as uint64];
      var it := t.IterStart();
      var i: uint64 := 0;
      ghost var partial := map[];
      while it.next.Some?
      invariant Inv()
      invariant BC.WFCompleteIndirectionTable(IndirectionTableModel.I(I()))
      invariant 0 <= i as int <= a.Length
      invariant MutableMapModel.WFIter(t.I(), it);
      invariant forall j | 0 <= j < i :: ValidVal(a[j])
      invariant forall j | 0 <= j < i :: ValInGrammar(a[j], GTuple([GUint64, GUint64, GUint64, GUint64Array]))
      // NOALIAS/CONST table doesn't need to be mutable, if we could say so we wouldn't need this
      invariant IndirectionTableModel.valToHashMap(a[..i]).Some?
      invariant IndirectionTableModel.valToHashMap(a[..i]).value.contents == partial
      invariant |partial.Keys| == i as nat
      invariant partial.Keys == it.s
      invariant partial.Keys <= t.I().contents.Keys
      invariant forall r | r in partial :: r in t.I().contents
          && partial[r].loc == t.I().contents[r].loc
          && partial[r].succs == t.I().contents[r].succs
      // NOALIAS/CONST t doesn't need to be mutable, if we could say so we wouldn't need this
      invariant t.I().contents == old(t.I().contents)
      invariant SeqSum(a[..i]) <= |it.s| * (8 + 8 + 8 + (8 + MaxNumChildren() * 8))
      decreases it.decreaser
      {
        var (ref, locOptGraph: IndirectionTableModel.Entry) := it.next.value;
        assert ref in I().locs;
        // NOTE: deconstructing in two steps to work around c# translation bug
        var locOpt := locOptGraph.loc;
        var succs := locOptGraph.succs;
        var loc := locOpt.value;
        //ghost var predCount := locOptGraph.predCount;
        var childrenVal := VUint64Array(succs);

        assert |succs| <= MaxNumChildren();

        //assert I().locs[ref] == loc;
        //assert I().graph[ref] == succs;

        //assert IndirectionTableModel.I(I()).locs[ref] == loc;
        //assert IndirectionTableModel.I(I()).graph[ref] == succs;

        assert BC.ValidLocationForNode(loc);
        /*ghost var t0 := IndirectionTableModel.valToHashMap(a[..i]);
        assert ref !in t0.value.contents;
        assert loc.addr != 0;
        assert LBAType.ValidLocation(loc);*/

        MutableMapModel.LemmaIterIndexLtCount(t.I(), it);

        // TODO this probably warrants a new invariant, or may leverage the weights branch, see TODO in BlockCache
        assume |succs| < 0x1_0000_0000_0000_0000;
        assert ValidVal(VTuple([VUint64(ref), VUint64(loc.addr), VUint64(loc.len), childrenVal]));

        assert |MutableMapModel.IterInc(t.I(), it).s| == |it.s| + 1;

        var vi := VTuple([VUint64(ref), VUint64(loc.addr), VUint64(loc.len), childrenVal]);

        lemma_tuple_size(ref, loc.addr, loc.len, succs);
        //assert SizeOfV(vi) <= (8 + 8 + 8 + (8 + MaxNumChildren() * 8));

        // == mutation ==
        partial := partial[ref := IndirectionTableModel.Entry(locOpt, succs, 0)];
        a[i] := vi;
        i := i + 1;
        it := t.IterInc(it);
        // ==============

        assert a[..i-1] == DropLast(a[..i]); // observe

        lemma_SeqSum_prefix_array(a, i as int);

        assert SeqSum(a[..i])
            == SeqSum(a[..i-1]) + SizeOfV(a[i-1])
            == SeqSum(a[..i-1]) + SizeOfV(vi)
            <= (|it.s| - 1) * (8 + 8 + 8 + (8 + MaxNumChildren() * 8)) + SizeOfV(vi)
            <= |it.s| * (8 + 8 + 8 + (8 + MaxNumChildren() * 8));
      }

      /* (doc) assert |partial.Keys| == |t.I().contents.Keys|; */
      SetInclusionAndEqualCardinalityImpliesSetEquality(partial.Keys, t.I().contents.Keys);

      assert a[..i] == a[..]; // observe
      v := Some(VArray(a[..]));

      /*ghost var t0 := IndirectionTableModel.valToHashMap(v.value.a);
      assert t0.Some?;
      assert BT.G.Root() in t0.value.contents;
      assert t0.value.count <= MaxSizeUint64();
      ghost var t1 := IndirectionTableModel.ComputeRefCounts(t0.value);
      assert t1.Some?;*/

      assert |it.s| <= IndirectionTableModel.MaxSize();
    }

    // To bitmap

    method InitLocBitmap()
    returns (success: bool, bm: Bitmap.Bitmap)
    requires Inv()
    requires BC.WFCompleteIndirectionTable(IndirectionTableModel.I(I()))
    ensures bm.Inv()
    ensures (success, bm.I()) == IndirectionTableModel.InitLocBitmap(old(I()))
    ensures fresh(bm.Repr)
    {
      IndirectionTableModel.reveal_InitLocBitmap();

      bm := new Bitmap.Bitmap(NumBlocksUint64());
      bm.Set(0);
      var it := t.IterStart();
      while it.next.Some?
      invariant t.Inv()
      invariant BC.WFCompleteIndirectionTable(IndirectionTableModel.I(I()))
      invariant bm.Inv()
      invariant MutableMapModel.WFIter(t.I(), it)
      invariant Bitmap.Len(bm.I()) == NumBlocks()
      invariant IndirectionTableModel.InitLocBitmapIterate(I(), it, bm.I())
             == IndirectionTableModel.InitLocBitmap(I())
      invariant fresh(bm.Repr)
      decreases it.decreaser
      {
        var kv := it.next.value;

        assert kv.0 in IndirectionTableModel.I(I()).locs;

        var loc: uint64 := kv.1.loc.value.addr;
        var locIndex: uint64 := loc / BlockSizeUint64();
        if locIndex < NumBlocksUint64() {
          var isSet := bm.GetIsSet(locIndex);
          if !isSet {
            it := t.IterInc(it);
            bm.Set(locIndex);
          } else {
            success := false;
            return;
          }
        } else {
          success := false;
          return;
        }
      }

      success := true;
    }
    
    ///// Dealloc stuff

    method FindDeallocable() returns (ref: Option<BT.G.Reference>)
    requires Inv()
    requires IndirectionTableModel.TrackingGarbage(I())
    ensures ref == IndirectionTableModel.FindDeallocable(I())
    {
      IndirectionTableModel.reveal_FindDeallocable();
      ref := garbageQueue.NextOpt();
    }

    method GetSize()
    returns (size: uint64)
    requires Inv()
    ensures size as int == |I().graph|
    {
      IndirectionTableModel.lemma_count_eq_graph_size(I().t);
      return this.t.Count;
    }
  }
}