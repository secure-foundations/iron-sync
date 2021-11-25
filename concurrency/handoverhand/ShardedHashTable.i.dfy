include "../../lib/Lang/NativeTypes.s.dfy"
include "../../lib/Base/Option.s.dfy"
include "../disciplined/common/Limits.i.dfy"
include "../hashtable/MapSpec.s.dfy"

module ShardedHashTable refines TicketStubSSM(MapIfc) {
  import opened NativeTypes
  import opened Options
  import opened Limits
  import MapIfc

//////////////////////////////////////////////////////////////////////////////
// Data structure definitions & transitions
//////////////////////////////////////////////////////////////////////////////

  import opened KeyValueType

  datatype Request =
    | Request(rid: RequestId, input: MapIfc.Input)

  datatype Response =
    | Response(rid: RequestId, output: MapIfc.Output)

  predicate ValidHashIndex(h:int)
  {
    0 <= h as int < FixedSize()
  }

  function method hash(key: Key) : (h:uint32)
  ensures ValidHashIndex(h as int)

  datatype KV = KV(key: Key, val: Value)

  // This is the thing that's stored in the hash table at this row.
  datatype Entry =
    | Full(kv: KV)
    | Empty

  // This is what some thread's stack thinks we're doing at this row.
  // TODO rename ActiveOp or Underway or something
  // The information embedded in these state objects form a richer invariant
  // that paves over the temporary gaps in the "idle invariant" that should
  // apply when no threads are operating)
  datatype State =
    | Free
    | Inserting(rid: RequestId, kv: KV, initial_key: Key)
    | Removing(rid: RequestId, key: Key)
    | RemoveTidying(rid: RequestId, initial_key: Key, found_value: Value)

      // Why do we need to store query state to support an invariant over the
      // hash table interpretation, since query is a read-only operation?
      // Because the query's result is defined at the moment it begins (its
      // serialization point), which is to say the proof ghostily knows the
      // answer when the query begins. We need to show inductively that that
      // answer stays the same with each step of any thread, until the impl
      // gets far enough to discover the answer in the real data structure.
      // We're showing that we inductively preserve the value of the
      // interpretation of the *answer* to query #rid.
    | Querying(rid: RequestId, key: Key)

  // TODO rename
  datatype Info = Info(entry: Entry, state: State)

  datatype PreR =
      | M(table: seq<Option<Info>>,
          insert_capacity: nat,
          tickets: multiset<Request>,
          stubs: multiset<Response>)
      | Fail
        // The NextStep disjunct is complex, but we'll show that as long
        // as the impl obeys them, it'll never land in Fail.
        // The state is here to "leave slack" in the defenition of dot(),
        // so that we can push off the proof that we never end up failing
        // until UpdatePreservesValid. If we didn't do it this way, we'd
        // have to show that dot is complete, which would entail sucking
        // the definition of update and proof of UpdatePreservesValid all
        // into the definition of dot().
  type M = r: PreR | (r.M? ==> |r.table| == FixedSize()) witness Fail

  function unitTable(): seq<Option<Info>>
  {
    seq(FixedSize(), i => None)
  }

  function unit() : M
  {
    M(unitTable(), 0, multiset{}, multiset{})
  }

  function Ticket(rid: RequestId, input: IOIfc.Input) : M
  {
    unit().(tickets := multiset{Request(rid, input)})
  }

  function Stub(rid: RequestId, output: MapIfc.Output) : M
  {
    unit().(stubs := multiset{Response(rid, output)})
  }

  function output_stub(rid: RequestId, output: MapIfc.Output) : M
  {
    Stub(rid, output)
  }

  function oneRowTable(k: nat, info: Info) : seq<Option<Info>>
  requires 0 <= k < FixedSize()
  {
    seq(FixedSize(), i => if i == k then Some(info) else None)
  }

  function oneRowResource(k: nat, info: Info, cap: nat) : M
  requires 0 <= k < FixedSize()
  {
    M(oneRowTable(k, info), (cap), multiset{}, multiset{})
  }

  function twoRowsTable(k1: nat, info1: Info, k2: nat, info2: Info) : seq<Option<Info>>
  requires 0 <= k1 < FixedSize()
  requires 0 <= k2 < FixedSize()
  requires k1 != k2
  {
    seq(FixedSize(), i => if i == k1 then Some(info1) else if i == k2 then Some(info2) else None)
  }

  function twoRowsResource(k1: nat, info1: Info, k2: nat, info2: Info, cap: nat) : M 
  requires 0 <= k1 < FixedSize()
  requires 0 <= k2 < FixedSize()
  requires k1 != k2
  {
    M(twoRowsTable(k1, info1, k2, info2), (cap), multiset{}, multiset{})
  }

  predicate IsInputResource(in_r: M, rid: RequestId, input: MapIfc.Input)
  {
    && in_r.M?
    && in_r.table == unitTable()
    && in_r.insert_capacity == 0
    && in_r.tickets == multiset { Request(rid, input) }
    && in_r.stubs == multiset { }
  }

  predicate nonoverlapping<A>(a: seq<Option<A>>, b: seq<Option<A>>)
  requires |a| == FixedSize()
  requires |b| == FixedSize()
  {
    forall i | 0 <= i < FixedSize() :: !(a[i].Some? && b[i].Some?)
  }

  function fuse<A>(a: Option<A>, b: Option<A>) : Option<A>
  {
    if a.Some? then a else b
  }

  function fuse_seq<A>(a: seq<Option<A>>, b: seq<Option<A>>) : seq<Option<A>>
  requires |a| == FixedSize()
  requires |b| == FixedSize()
  requires nonoverlapping(a, b)
  {
    seq(FixedSize(), i requires 0 <= i < |a| => fuse(a[i], b[i]))
  }

  function dot(x: M, y: M) : M {
    if x.M? && y.M? && nonoverlapping(x.table, y.table) then (
      M(fuse_seq(x.table, y.table),
          x.insert_capacity + y.insert_capacity,
          x.tickets + y.tickets,
          x.stubs + y.stubs)
    ) else (
      Fail
    )
  }

  lemma dot_unit(x: M)
  ensures dot(x, unit()) == x
  {
  }

  lemma commutative(x: M, y: M)
  ensures dot(x, y) == dot(y, x)
  {
    if x.M? && y.M? && nonoverlapping(x.table, y.table) {
      /*assert nonoverlapping(y.table, x.table);
      forall i | 0 <= i < FixedSize()
      ensures dot(x,y).table[i] == dot(y,x).table[i]
      {
        assert fuse(x.table[i], y.table[i]) == fuse(y.table[i], x.table[i]);
      }*/
      assert fuse_seq(x.table, y.table) == fuse_seq(y.table, x.table);
      assert dot(x, y).tickets == dot(y, x).tickets;
      assert dot(x, y).stubs == dot(y, x).stubs;
    }
  }

  lemma associative(x: M, y: M, z: M)
  ensures dot(x, dot(y, z)) == dot(dot(x, y), z)
  {
    if x.M? && y.M? && z.M? && nonoverlapping(x.table, y.table)
        && nonoverlapping(fuse_seq(x.table, y.table), z.table)
    {
      /*forall i | 0 <= i < FixedSize()
      ensures dot(x, dot(y, z)).table[i] == dot(dot(x, y), z).table[i]
      {
      }
      //assert fuse_seq(fuse_seq(x.table, y.table), z.table)
      //    == fuse_seq(x.table, fuse_seq(y.table, z.table));
      assert dot(x, dot(y, z)).table == dot(dot(x, y), z).table;*/
      assert dot(x, dot(y, z)) == dot(dot(x, y), z);
    } else {
    }
  }

  function Init() : M
  {
    M(
      seq(FixedSize(), (i) => Some(Info(Empty, Free))),
      Capacity(),
      multiset{},
      multiset{}
    )
  }

  datatype Step =
    | ProcessInsertTicketStep(insert_ticket: Request)
    | InsertSkipStep(pos: nat)
    | InsertSwapStep(pos: nat)
    | InsertDoneStep(pos: nat)
    | InsertUpdateStep(pos: nat)

    | ProcessRemoveTicketStep(insert_ticket: Request)
    | RemoveSkipStep(pos: nat)
    | RemoveFoundItStep(pos: nat)
    | RemoveNotFoundStep(pos: nat)
    | RemoveTidyStep(pos: nat)
    | RemoveDoneStep(pos: nat)

    | ProcessQueryTicketStep(query_ticket: Request)
    | QuerySkipStep(pos: nat)
    | QueryDoneStep(pos: nat)
    | QueryNotFoundStep(pos: nat)

  function NextPos(pos: nat) : nat
  {
    if pos < FixedSize() - 1 then pos + 1 else 0
  }

  predicate ProcessInsertTicketEnable(s: M, insert_ticket: Request)
  {
    && !s.Fail?
    && insert_ticket.input.InsertInput?
    && insert_ticket in s.tickets
    && var key := insert_ticket.input.key;
    && var h: uint32 := hash(key);
    && 0 <= h as int < |s.table|
    && s.table[h].Some?
    && s.table[h].value.state.Free?
    && s.insert_capacity >= 1
  }

  function ProcessInsertTicketTransition(s: M, insert_ticket: Request): (s': M)
    requires ProcessInsertTicketEnable(s, insert_ticket)
  {
    var key := insert_ticket.input.key;
    var h: uint32 := hash(key);
    s.(tickets := s.tickets - multiset{insert_ticket})
      .(insert_capacity := (s.insert_capacity - 1))
      .(table := s.table[h := Some(
          s.table[h].value.(
              state := Inserting(insert_ticket.rid,
              KV(key, insert_ticket.input.value), key)))])
  }

  predicate ProcessInsertTicket(s: M, s': M, insert_ticket: Request)
  {
    && ProcessInsertTicketEnable(s, insert_ticket)
    && s' == ProcessInsertTicketTransition(s, insert_ticket)
  }

  predicate ProcessInsertTicketFail(s: M, s': M, insert_ticket: Request)
  {
    && !s.Fail?
    && insert_ticket.input.InsertInput?
    && insert_ticket in s.tickets
    && (s' == s
      .(tickets := s.tickets - multiset{insert_ticket})
      .(stubs := s.stubs + multiset{Response(insert_ticket.rid, MapIfc.InsertOutput(false))}))
  }

  // search_h: hash of the key we are trying to insert
  // slot_h: hash of the key at slot_idx
  // returns search_h should go before slot_h
  predicate ShouldHashGoBefore(search_h: int, slot_h: int, slot_idx: int)
  {
    || search_h < slot_h <= slot_idx // normal case
    || slot_h <= slot_idx < search_h // search_h wraps around the end of array
    || slot_idx < search_h < slot_h// search_h, slot_h wrap around the end of array
  }

  predicate InsertSkipEnable(s: M, pos: nat)
  {
    && !s.Fail?
    && 0 <= pos < FixedSize()
    && var pos' := NextPos(pos);
    && s.table[pos].Some?
    && s.table[pos'].Some?
    && s.table[pos].value.state.Inserting?
    && s.table[pos].value.entry.Full?
    // This isn't a matching key...
    && s.table[pos].value.state.kv.key
        != s.table[pos].value.entry.kv.key
    // ...and we need to keep searching because of the Robin Hood rule.
    && !ShouldHashGoBefore(
        hash(s.table[pos].value.state.kv.key) as int,
        hash(s.table[pos].value.entry.kv.key) as int, pos)
    && s.table[pos'].value.state.Free?
}

  function InsertSkipTransition(s: M, pos: nat): M
    requires InsertSkipEnable(s, pos)
  {
    var pos' := NextPos(pos);
    s.(table := s.table
        [pos := Some(s.table[pos].value.(state := Free))]
        [pos' := Some(s.table[pos'].value.(state := s.table[pos].value.state))])
  }

  // We're trying to insert new_item at pos j
  // where hash(new_item) >= hash(pos j)
  // we skip item i and move to i+1.
  predicate InsertSkip(s: M, s': M, pos: nat)
  {
    && InsertSkipEnable(s, pos)
    && s' == InsertSkipTransition(s, pos)
  }

  predicate InsertSwapEanble(s: M, pos: nat)
  {
    && !s.Fail?
    && 0 <= pos < FixedSize()
    && var pos' := NextPos(pos);
    && s.table[pos].Some?
    && s.table[pos'].Some?
    && var state := s.table[pos].value.state;
    && state.Inserting?
    && s.table[pos].value.entry.Full?
    && ShouldHashGoBefore(
        hash(state.kv.key) as int,
        hash(s.table[pos].value.entry.kv.key) as int, pos)
    && s.table[pos'].value.state.Free?
  }

  function InsertSwapTransition(s: M, pos: nat): M
    requires InsertSwapEanble(s, pos)
  {
    var pos' := NextPos(pos);
    var state := s.table[pos].value.state;
    s.(table := s.table
        [pos := Some(Info(Full(state.kv), Free))]
        [pos' := Some(s.table[pos'].value.(state :=
          Inserting(state.rid, s.table[pos].value.entry.kv, state.initial_key)))])
  }

  // We're trying to insert new_item at pos j
  // where hash(new_item) < hash(pos j)
  // in this case we do the swap and keep moving forward
  // with the swapped-out item.
  predicate InsertSwap(s: M, s': M, pos: nat)
  {
    && InsertSwapEanble(s, pos)
    && s' == InsertSwapTransition(s, pos)
  }

  predicate InsertDoneEnable(s: M, pos: nat)
  {
    && !s.Fail?
    && 0 <= pos < FixedSize()
    && s.table[pos].Some?
    && s.table[pos].value.state.Inserting?
    && s.table[pos].value.entry.Empty?
  }

  function InsertDoneTransition(s: M, pos: nat): M
    requires InsertDoneEnable(s, pos)
  {
    s.(table := s.table
        [pos := Some(Info(Full(s.table[pos].value.state.kv), Free))])
      .(stubs := s.stubs + multiset{Response(s.table[pos].value.state.rid, MapIfc.InsertOutput(true))})
  }

  // Slot is empty. Insert our element and finish.
  predicate InsertDone(s: M, s': M, pos: nat)
  {
    && InsertDoneEnable(s, pos)
    && s' == InsertDoneTransition(s, pos)
  }

  predicate InsertUpdateEnable(s: M, pos: nat)
  {
    && !s.Fail?
    && 0 <= pos < FixedSize()
    && s.table[pos].Some?
    && s.table[pos].value.state.Inserting?
    && s.table[pos].value.entry.Full?
    && s.table[pos].value.entry.kv.key == s.table[pos].value.state.kv.key
  }

  function InsertUpdateTransition(s: M, pos: nat): M
    requires InsertUpdateEnable(s, pos)
  {
    s.(table := s.table
        [pos := Some(Info(Full(s.table[pos].value.state.kv), Free))])
      // we reserved the capacity at the begining, but later discover we don't need it
      .(insert_capacity := (s.insert_capacity + 1)) 
      .(stubs := s.stubs + multiset{Response(s.table[pos].value.state.rid, MapIfc.InsertOutput(true))})
  }

  predicate InsertUpdate(s: M, s': M, pos: nat)
  {
    && InsertUpdateEnable(s, pos)
    && s' == InsertUpdateTransition(s, pos)
  }

  // Remove

  // We know about row h (our thread is working on it),
  // and we know that it's free (we're not already claiming to do something else with it).
  predicate KnowRowIsFree(s: M, h: int)
    requires !s.Fail?
    requires ValidHashIndex(h)  
  {
    && s.table[h].Some?
    && s.table[h].value.state.Free?
  }

  predicate ProcessRemoveTicketEnable(s: M, remove_ticket: Request)
  {
    && !s.Fail?
    && remove_ticket.input.RemoveInput?
    && remove_ticket in s.tickets
    && var h: uint32 := hash(remove_ticket.input.key);
    && KnowRowIsFree(s, h as int)
  }

  function ProcessRemoveTicketTransition(s: M, remove_ticket: Request): M
    requires ProcessRemoveTicketEnable(s, remove_ticket)
  {
    var h: uint32 := hash(remove_ticket.input.key);
    s.(tickets := s.tickets - multiset{remove_ticket})
      .(table := s.table[h :=
        Some(s.table[h].value.(state := Removing(remove_ticket.rid, remove_ticket.input.key)))])
  }

  predicate ProcessRemoveTicket(s: M, s': M, remove_ticket: Request)
  {
    && ProcessRemoveTicketEnable(s, remove_ticket)
    && s' == ProcessRemoveTicketTransition(s, remove_ticket)
  }

  predicate RemoveInspectEnable(s: M, pos: nat)
  {
    && !s.Fail?
    && 0 <= pos < FixedSize()
    // Know row pos, and it's the thing we're removing, and it's full...
    && s.table[pos].Some?
    && s.table[pos].value.state.Removing?
  }

  predicate RemoveSkipEnableCore(s: M, pos: nat)
  {
    && RemoveInspectEnable(s, pos)
    && s.table[pos].value.entry.Full?
    && var pos' := NextPos(pos);
    && KnowRowIsFree(s, pos')
    // ...and the key it's full of sorts before the thing we're looking to remove.
    && !ShouldHashGoBefore(
        hash(s.table[pos].value.state.key) as int,
        hash(s.table[pos].value.entry.kv.key) as int, pos)
  }

  predicate RemoveSkipEnable(s: M, pos: nat)
  {
    && RemoveSkipEnableCore(s, pos)
    // The hash is equal, but this isn't the key we're trying to remove.
    // Advance the pointer to the next row.
    && s.table[pos].value.entry.kv.key != s.table[pos].value.state.key
  }

  function RemoveSkipTransition(s: M, pos: nat): M
    requires RemoveSkipEnable(s, pos)
  {
    var pos' := NextPos(pos);
    s.(table := s.table
        [pos := Some(s.table[pos].value.(state := Free))]
        [pos' := Some(s.table[pos'].value.(state := s.table[pos].value.state))])
  }

  predicate RemoveSkip(s: M, s': M, pos: nat)
  {
    && RemoveSkipEnable(s, pos)
    && s' == RemoveSkipTransition(s, pos)
  }

  predicate RemoveNotFoundEnable(s: M, pos: nat)
  {
    && RemoveInspectEnable(s, pos)
    && (if s.table[pos].value.entry.Full? then // the key we are looking for goes before the one in the slot, so it must be absent
      && ShouldHashGoBefore(
        hash(s.table[pos].value.state.key) as int,
        hash(s.table[pos].value.entry.kv.key) as int, pos)
      && s.table[pos].value.entry.kv.key != s.table[pos].value.state.key
      else true // the key would have been in this empty spot
    )
  }

  function RemoveNotFoundTransition(s: M, pos: nat): M
    requires RemoveNotFoundEnable(s, pos)
  {
    s.(table := s.table[pos := Some(Info(s.table[pos].value.entry, Free))])
      .(stubs := s.stubs + multiset{Response(s.table[pos].value.state.rid, MapIfc.RemoveOutput(false))})
  }

  predicate RemoveNotFound(s: M, s': M, pos: nat)
  {
    && RemoveNotFoundEnable(s, pos)
    && s' == RemoveNotFoundTransition(s, pos)
  }

  predicate RemoveFoundItEnable(s: M, pos: nat)
  {
    && RemoveSkipEnableCore(s, pos)
    // This IS the key we want to remove!
    && var initial_key := s.table[pos].value.state.key;
    && s.table[pos].value.entry.kv.key == initial_key
  }

  function RemoveFoundItTransition(s: M, pos: nat): M
    requires RemoveFoundItEnable(s, pos)
  {
    var initial_key := s.table[pos].value.state.key;
    // Change the program counter into RemoveTidying mode
    var rid := s.table[pos].value.state.rid;
    // Note: it doesn't matter what we set the entry to here, since we're going
    // to overwrite it in the next step either way.
    // (Might be easier to leave the entry as it is rather than set it to Empty?)
    s.(table := s.table[pos := Some(Info(Empty,
        RemoveTidying(rid, initial_key, s.table[pos].value.entry.kv.val)))])
  }

  predicate RemoveFoundIt(s: M, s': M, pos: nat)
  {
    && RemoveFoundItEnable(s, pos)
    && s' == RemoveFoundItTransition(s, pos)
  }

  predicate TidyEnable(s: M, pos: nat)
  {
    && !s.Fail?
    && ValidHashIndex(pos)
    // The row that needs backfilling is known and we're pointing at it
    && s.table[pos].Some?
    && s.table[pos].value.state.RemoveTidying?
    && s.table[pos].value.entry.Empty?  // Should be an invariant, actually
    && (pos < FixedSize() - 1 ==> s.table[pos+1].Some?) // if a next row, we know it
  }

  predicate DoneTidying(s: M, pos: nat)
    requires TidyEnable(s, pos)
  {
    var pos' := NextPos(pos);
    && KnowRowIsFree(s, pos')
    && (
      || s.table[pos'].value.entry.Empty?                     // Next row is empty
      || pos' == hash(s.table[pos'].value.entry.kv.key) as nat  // Next row's key can't move back
    )
  }

  predicate RemoveTidyEnable(s: M, pos: nat)
  {
    && TidyEnable(s, pos)
    && !DoneTidying(s, pos)

    && var pos' := NextPos(pos);
    && KnowRowIsFree(s, pos')
  }

  function RemoveTidyTransition(s: M, pos: nat): M
    requires RemoveTidyEnable(s, pos)
  {
    var pos' := NextPos(pos);
    // Pull the entry back one slot, and push the state pointer forward one slot.
    s.(table := s.table
      [pos := Some(Info(s.table[pos'].value.entry, Free))]
      [pos' := Some(Info(Empty, s.table[pos].value.state))])
  }

  predicate RemoveTidy(s: M, s': M, pos: nat)
  {
    && RemoveTidyEnable(s, pos)
    && s' == RemoveTidyTransition(s, pos)
  }

  predicate RemoveDoneEnable(s: M, pos: nat)
  {
    && TidyEnable(s, pos)
    && DoneTidying(s, pos)
  }

  function RemoveDoneTransition(s: M, pos: nat): M
    requires RemoveDoneEnable(s, pos)
  {
    // Clear the pointer, return the stub.
    s.(table := s.table[pos := Some(Info(s.table[pos].value.entry, Free))])
      .(insert_capacity := (s.insert_capacity + 1))
      .(stubs := s.stubs + multiset{Response(s.table[pos].value.state.rid, MapIfc.RemoveOutput(true))})
  }

  predicate RemoveDone(s: M, s': M, pos: nat)
  {
    && RemoveDoneEnable(s, pos)
    && s' == RemoveDoneTransition(s, pos)
  }

  // Query

  predicate ProcessQueryTicketEnable(s: M, query_ticket: Request)
  {
    && !s.Fail?
    && query_ticket.input.QueryInput?
    && query_ticket in s.tickets
    && var h: uint32 := hash(query_ticket.input.key);
    && 0 <= h as int < FixedSize()
    && s.table[h].Some?
    && s.table[h].value.state.Free?
  }
  
  function ProcessQueryTicketTransition(s: M, query_ticket: Request): M
    requires ProcessQueryTicketEnable(s, query_ticket)
  {
    var h: uint32 := hash(query_ticket.input.key);
    s.(tickets := s.tickets - multiset{query_ticket})
      .(table := s.table[h :=
        Some(s.table[h].value.(state := Querying(query_ticket.rid, query_ticket.input.key)))])
  }

  predicate ProcessQueryTicket(s: M, s': M, query_ticket: Request)
  {
    && ProcessQueryTicketEnable(s, query_ticket)
    && s' == ProcessQueryTicketTransition(s, query_ticket)
  }

  predicate QuerySkipEnable(s: M, pos: nat)
  {
    && !s.Fail?
    && 0 <= pos < FixedSize()
    && s.table[pos].Some?
    && s.table[NextPos(pos)].Some?
    && s.table[pos].value.state.Querying?
    && s.table[pos].value.entry.Full?
    // Not the key we're looking for
    && s.table[pos].value.state.key != s.table[pos].value.entry.kv.key
    // But we haven't passed by the key we want yet (Robin Hood rule)
    && !ShouldHashGoBefore(
        hash(s.table[pos].value.state.key) as int,
        hash(s.table[pos].value.entry.kv.key) as int, pos)
    && s.table[NextPos(pos)].value.state.Free?
  }

  function QuerySkipTransition(s: M, pos: nat): M
    requires QuerySkipEnable(s, pos)
  {
    s.(table := s.table
        [pos := Some(s.table[pos].value.(state := Free))]
        [NextPos(pos) := Some(s.table[NextPos(pos)].value.(state := s.table[pos].value.state))])
  }

  predicate QuerySkip(s: M, s': M, pos: nat)
  {
    && QuerySkipEnable(s, pos)
    && s' == QuerySkipTransition(s, pos)
  }

  predicate QueryDoneEnable(s: M, pos: nat)
  {
    && !s.Fail?
    && 0 <= pos < FixedSize()
    && s.table[pos].Some?
    && s.table[pos].value.state.Querying?
    && s.table[pos].value.entry.Full?
    && s.table[pos].value.state.key == s.table[pos].value.entry.kv.key
  }

  function QueryDoneTransition(s: M, pos: nat): M
    requires QueryDoneEnable(s, pos)
  {
    var stub := Response(s.table[pos].value.state.rid, MapIfc.QueryOutput(Found(s.table[pos].value.entry.kv.val)));
    s.(table := s.table[pos := Some(s.table[pos].value.(state := Free))])
      .(stubs := s.stubs + multiset{stub})
  }

  predicate QueryDone(s: M, s': M, pos: nat)
  {
    && QueryDoneEnable(s, pos)
    && s' == QueryDoneTransition(s, pos)
  }

  predicate QueryNotFoundEnable(s: M, pos: nat)
  {
    && !s.Fail?
    && 0 <= pos < FixedSize()
    && s.table[pos].Some?
    && s.table[pos].value.state.Querying?
    // We're allowed to do this step if it's empty, or if the hash value we
    // find is bigger than the one we're looking for
    && (s.table[pos].value.entry.Full? ==>
      ShouldHashGoBefore(
        hash(s.table[pos].value.state.key) as int,
        hash(s.table[pos].value.entry.kv.key) as int, pos))
      // TODO: we have replaced the following predicate, so wrap around is considered
      // hash(s.table[pos].value.state.key) < hash(s.table[pos].value.entry.kv.key))
  }

  function QueryNotFoundTransition(s: M, pos: nat): M
    requires QueryNotFoundEnable(s, pos)
  {
    s.(table := s.table
        [pos := Some(s.table[pos].value.(state := Free))])
      .(stubs := s.stubs + multiset{Response(s.table[pos].value.state.rid, MapIfc.QueryOutput(NotFound))})
  }

  predicate QueryNotFound(s: M, s': M, pos: nat)
  {
    && QueryNotFoundEnable(s, pos)
    && s' == QueryNotFoundTransition(s, pos)
  }

  predicate NextStep(s: M, s': M, step: Step)
  {
    match step {
      case ProcessInsertTicketStep(insert_ticket) => ProcessInsertTicket(s, s', insert_ticket)
      case InsertSkipStep(pos) => InsertSkip(s, s', pos)
      case InsertSwapStep(pos) => InsertSwap(s, s', pos)
      case InsertDoneStep(pos) => InsertDone(s, s', pos)
      case InsertUpdateStep(pos) => InsertUpdate(s, s', pos)

      case ProcessRemoveTicketStep(remove_ticket) => ProcessRemoveTicket(s, s', remove_ticket)
      case RemoveSkipStep(pos) => RemoveSkip(s, s', pos)
      case RemoveFoundItStep(pos) => RemoveFoundIt(s, s', pos)
      case RemoveNotFoundStep(pos) => RemoveNotFound(s, s', pos)
      case RemoveTidyStep(pos) => RemoveTidy(s, s', pos)
      case RemoveDoneStep(pos) => RemoveDone(s, s', pos)

      case ProcessQueryTicketStep(query_ticket) => ProcessQueryTicket(s, s', query_ticket)
      case QuerySkipStep(pos) => QuerySkip(s, s', pos)
      case QueryDoneStep(pos) => QueryDone(s, s', pos)
      case QueryNotFoundStep(pos) => QueryNotFound(s, s', pos)
    }
  }

  predicate Next(s: M, s': M)
  {
    exists step :: NextStep(s, s', step)
  }

//////////////////////////////////////////////////////////////////////////////
// global-level Invariant proof
//////////////////////////////////////////////////////////////////////////////

  ////// Invariant

  predicate Complete(table: seq<Option<Info>>)
  {
    && (forall i | 0 <= i < |table| :: table[i].Some?)
  }

  // unwrapped_index
  function adjust(i: int, root: int) : int
  requires 0 <= i < FixedSize()
  requires 0 <= root < FixedSize()
  {
    if i <= root then FixedSize() + i else i
  }

  // Keys are unique, although we don't count entries being removed
  predicate KeysUnique(table: seq<Option<Info>>)
  requires Complete(table)
  {
    forall i, j | 0 <= i < |table| && 0 <= j < |table| && i != j
      && table[i].value.entry.Full? && table[j].value.entry.Full?
      && !table[i].value.state.RemoveTidying? && !table[j].value.state.RemoveTidying?
        :: table[i].value.entry.kv.key != table[j].value.entry.kv.key
  }

  predicate ValidHashInSlot(table: seq<Option<Info>>, e: int, i: int)
  requires |table| == FixedSize()
  requires Complete(table)
  requires 0 <= e < |table|
  requires 0 <= i < |table|
  {
    // No matter which empty pivot cell 'e' we choose, every entry is 'downstream'
    // of the place that it hashes to.
    // Likewise for insert pointers and others

    table[e].value.entry.Empty? && !table[e].value.state.RemoveTidying? ==> (
      && (table[i].value.entry.Full? ==> (
        var h := hash(table[i].value.entry.kv.key) as int;
        && adjust(h, e) <= adjust(i, e)
      ))
      && (table[i].value.state.Inserting? ==> (
        var h := hash(table[i].value.state.kv.key) as int;
        && adjust(h, e) <= adjust(i, e)
      ))
      && ((table[i].value.state.Removing? || table[i].value.state.Querying?) ==> (
        var h := hash(table[i].value.state.key) as int;
        && adjust(h, e) <= adjust(i, e)
      ))
    )
  }

  // 'Robin Hood' order
  // It's not enough to say that hash(entry[i]) <= hash(entry[i+1])
  // because of wraparound. We do a cyclic comparison 'rooted' at an
  // arbitrary empty element, given by e.
  predicate ValidHashOrdering(table: seq<Option<Info>>, e: int, j: int, k: int)
  requires |table| == FixedSize()
  requires Complete(table)
  requires 0 <= e < |table|
  requires 0 <= j < |table|
  requires 0 <= k < |table|
  {
    (table[e].value.entry.Empty? && !table[e].value.state.RemoveTidying? && table[j].value.entry.Full? && adjust(j, e) < adjust(k, e) ==> (
      var hj := hash(table[j].value.entry.kv.key) as int;

      && (table[k].value.entry.Full? ==> (
        var hk := hash(table[k].value.entry.kv.key) as int;
        && adjust(hj, e) <= adjust(hk, e)
      ))

      // If entry 'k' has an 'Inserting' action on it, then that action must have
      // gotten past entry 'j'.
      && (table[k].value.state.Inserting? ==> (
        var ha := hash(table[k].value.state.kv.key) as int;
        && adjust(hj, e) <= adjust(ha, e)
      ))

      && ((table[k].value.state.Removing? || table[k].value.state.Querying?) ==> (
        var ha := hash(table[k].value.state.key) as int;
        && adjust(hj, e) <= adjust(ha, e)
      ))
    ))
  }

  predicate ActionNotPastKey(table: seq<Option<Info>>, e: int, j: int, k: int)
  requires |table| == FixedSize()
  requires Complete(table)
  requires 0 <= e < |table|
  requires 0 <= j < |table|
  requires 0 <= k < |table|
  {
    (table[e].value.entry.Empty? && !table[e].value.state.RemoveTidying? && table[j].value.entry.Full? && adjust(j, e) < adjust(k, e) ==> (
      // If entry 'k' has an 'Inserting' action on it, then that action must not have
      // gotten past entry 'j'.
      && (table[k].value.state.Inserting? ==> (
        table[k].value.state.kv.key != table[j].value.entry.kv.key
      ))
      && ((table[k].value.state.Removing? || table[k].value.state.Querying?) ==> (
        table[k].value.state.key != table[j].value.entry.kv.key
      ))
    ))
  }

  /*predicate ExistsEmptyEntry(table: seq<Option<Info>>)
  {
    exists e :: 0 <= e < |table| && table[e].Some? && table[e].value.entry.Empty?
        && !table[e].value.state.RemoveTidying?
  }*/

  function InfoQuantity(s: Option<Info>) : nat {
    if s.None? then 0 else (
      (if s.value.state.Inserting? then 1 else 0) +
      (if s.value.state.RemoveTidying? || s.value.entry.Full? then 1 else 0)
    )
  }

  function {:opaque} TableQuantity(s: seq<Option<Info>>) : nat {
    if s == [] then 0 else TableQuantity(s[..|s|-1]) + InfoQuantity(s[|s| - 1])
  }

  predicate TableQuantityInv(s: M)
  {
    && s.M?
    && TableQuantity(s.table) + s.insert_capacity == Capacity()
  }

  predicate InvTable(table: seq<Option<Info>>)
  {
    && |table| == FixedSize()
    && Complete(table)
    //&& ExistsEmptyEntry(table)
    && KeysUnique(table)
    && (forall e, i | 0 <= e < |table| && 0 <= i < |table|
        :: ValidHashInSlot(table, e, i))
    && (forall e, j, k | 0 <= e < |table| && 0 <= j < |table| && 0 <= k < |table|
        :: ValidHashOrdering(table, e, j, k))
    && (forall e, j, k | 0 <= e < |table| && 0 <= j < |table| && 0 <= k < |table|
        :: ActionNotPastKey(table, e, j, k))
  }

  predicate Inv(s: M)
  {
    && s.M?
    && InvTable(s.table)
    && TableQuantityInv(s)
  }

  //////////////////////////////////////////////////////////////////////////////
  // Proof that Init && []Next maintains Inv
  //////////////////////////////////////////////////////////////////////////////


  lemma TableQuantity_replace1(s: seq<Option<Info>>, s': seq<Option<Info>>, i: int)
  requires 0 <= i < |s| == |s'|
  requires forall j | 0 <= j < |s| :: i != j ==> s[j] == s'[j]
  ensures TableQuantity(s') == TableQuantity(s) + InfoQuantity(s'[i]) - InfoQuantity(s[i])
  {
    reveal_TableQuantity();
    if i == |s| - 1 {
      assert s[..|s|-1] == s'[..|s|-1];
    } else {
      TableQuantity_replace1(s[..|s|-1], s'[..|s'|-1], i);
    }
  }

  lemma TableQuantity_replace2(s: seq<Option<Info>>, s': seq<Option<Info>>, i: int)
  requires 0 <= i < |s| == |s'|
  requires |s| > 1
  requires
      var i' := (if i == |s| - 1 then 0 else i + 1);
      forall j | 0 <= j < |s| :: i != j && i' != j ==> s[j] == s'[j]
  ensures
      var i' := (if i == |s| - 1 then 0 else i + 1);
    TableQuantity(s') == TableQuantity(s)
        + InfoQuantity(s'[i]) - InfoQuantity(s[i])
        + InfoQuantity(s'[i']) - InfoQuantity(s[i'])
  {
    var s0 := s[i := s'[i]];
    TableQuantity_replace1(s, s0, i);
    var i' := (if i == |s| - 1 then 0 else i + 1);
    TableQuantity_replace1(s0, s', i');
  }

  function {:opaque} get_empty_cell(table: seq<Option<Info>>) : (e: int)
  requires InvTable(table)
  requires TableQuantity(table) < |table|
  ensures 0 <= e < |table| && table[e].Some? && table[e].value.entry.Empty?
        && !table[e].value.state.RemoveTidying?
  {
    assert exists e' :: 0 <= e' < |table| && table[e'].Some? && table[e'].value.entry.Empty?
        && !table[e'].value.state.RemoveTidying? by {
      var t := get_empty_cell_other_than_insertion_cell_table(table);
    }
    var e' :| 0 <= e' < |table| && table[e'].Some? && table[e'].value.entry.Empty?
        && !table[e'].value.state.RemoveTidying?;
    e'
  }

  lemma get_empty_cell_other_than_insertion_cell_table(table: seq<Option<Info>>)
  returns (e: int)
  requires Complete(table)
  requires TableQuantity(table) < |table|
  ensures 0 <= e < |table| && table[e].Some? && table[e].value.entry.Empty?
        && !table[e].value.state.RemoveTidying?
        && !table[e].value.state.Inserting?
  {
    reveal_TableQuantity();
    e := |table| - 1;
    if table[e].value.entry.Empty?
        && !table[e].value.state.RemoveTidying?
        && !table[e].value.state.Inserting? {
      return;
    } else {
      e := get_empty_cell_other_than_insertion_cell_table(table[..|table| - 1]);
    }
  }

  lemma get_empty_cell_other_than_insertion_cell(s: M)
  returns (e: int)
  requires Inv(s)
  ensures 0 <= e < |s.table| && s.table[e].Some? && s.table[e].value.entry.Empty?
        && !s.table[e].value.state.RemoveTidying?
        && !s.table[e].value.state.Inserting?
  {
    e := get_empty_cell_other_than_insertion_cell_table(s.table);
  }

  lemma ProcessInsertTicket_PreservesInv(s: M, s': M, insert_ticket: Request)
  requires Inv(s)
  requires ProcessInsertTicket(s, s', insert_ticket)
  ensures Inv(s')
  {
    assert forall i | 0 <= i < |s'.table| :: s'.table[i].value.entry == s.table[i].value.entry;
    forall i, e | 0 <= i < |s'.table| && 0 <= e < |s'.table|
    ensures ValidHashInSlot(s'.table, e, i)
    {
      assert ValidHashInSlot(s.table, e, i);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ValidHashOrdering(s'.table, e, j, k)
    {
      assert ValidHashOrdering(s.table, e, j, k);
      assert ValidHashInSlot(s.table, e, j);
      assert ValidHashInSlot(s.table, e, k);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ActionNotPastKey(s'.table, e, j, k)
    {
      assert ActionNotPastKey(s.table, e, j, k);
      assert ValidHashInSlot(s.table, e, j);
    }

    var h := hash(insert_ticket.input.key) as int;
    TableQuantity_replace1(s.table, s'.table, h);
  }

  lemma InsertSkip_PreservesInv(s: M, s': M, pos: nat)
  requires Inv(s)
  requires InsertSkip(s, s', pos)
  ensures Inv(s')
  {
    assert forall i | 0 <= i < |s'.table| :: s'.table[i].value.entry == s.table[i].value.entry;
    forall e, i | 0 <= i < |s'.table| && 0 <= e < |s'.table|
    ensures ValidHashInSlot(s'.table, e, i)
    {
      assert ValidHashInSlot(s.table, e, i);

      var i' := if i > 0 then i - 1 else |s.table| - 1;
      assert ValidHashInSlot(s.table, e, i');
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ValidHashOrdering(s'.table, e, j, k)
    {
      assert ValidHashOrdering(s.table, e, j, k);
      assert ValidHashInSlot(s.table, e, j);
      assert ValidHashInSlot(s.table, e, k);

      //var k' := if k > 0 then k - 1 else |s.table| - 1;

      assert ValidHashInSlot(s.table, e, pos);
      assert ValidHashOrdering(s.table, e, j, pos);
      assert ValidHashOrdering(s.table, e, pos, k);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ActionNotPastKey(s'.table, e, j, k)
    {
      assert ActionNotPastKey(s.table, e, j, pos);

      assert ActionNotPastKey(s.table, e, j, k);
      assert ValidHashInSlot(s.table, e, j);
    }

    TableQuantity_replace2(s.table, s'.table, pos);
  }

  lemma InsertSwap_PreservesInv(s: M, s': M, pos: nat)
  requires Inv(s)
  requires InsertSwap(s, s', pos)
  ensures Inv(s')
  {
    assert forall i | 0 <= i < |s'.table| :: s.table[i].value.entry.Empty? ==> s'.table[i].value.entry.Empty?;
    forall e, i | 0 <= i < |s'.table| && 0 <= e < |s'.table|
    ensures ValidHashInSlot(s'.table, e, i)
    {
      assert ValidHashInSlot(s.table, e, i);

      var i' := if i > 0 then i - 1 else |s.table| - 1;
      assert ValidHashInSlot(s.table, e, i');
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ValidHashOrdering(s'.table, e, j, k)
    {
      assert ValidHashOrdering(s.table, e, j, k);
      assert ValidHashInSlot(s.table, e, j);
      assert ValidHashInSlot(s.table, e, k);

      var k' := if k > 0 then k - 1 else |s.table| - 1;

      assert ValidHashInSlot(s.table, e, pos);
      assert ValidHashOrdering(s.table, e, j, pos);
      assert ValidHashOrdering(s.table, e, pos, k);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ActionNotPastKey(s'.table, e, j, k)
    {
      assert ActionNotPastKey(s.table, e, j, pos);

      assert ActionNotPastKey(s.table, e, j, k);
      assert ValidHashInSlot(s.table, e, j);

      assert ValidHashOrdering(s.table, e, j, k);
      assert ValidHashInSlot(s.table, e, pos);
      assert ValidHashOrdering(s.table, e, j, pos);
    }

    forall i | 0 <= i < |s.table| && s.table[i].value.entry.Full?
    ensures s.table[i].value.entry.kv.key != s.table[pos].value.state.kv.key
    {
      //var e :| 0 <= e < |s.table| && s.table[e].value.entry.Empty?
      //  && !s.table[e].value.state.RemoveTidying?;
      var e := get_empty_cell_other_than_insertion_cell(s);
      assert ActionNotPastKey(s.table, e, i, pos);
      //assert ValidHashInSlot(s.table, e, i);
      assert ValidHashInSlot(s.table, e, pos);
      assert ValidHashOrdering(s.table, e, pos, i);
      //assert ValidHashOrdering(s.table, e, i, pos);
    }

    TableQuantity_replace2(s.table, s'.table, pos);
  }

  lemma InsertDone_PreservesInv(s: M, s': M, pos: nat)
  requires Inv(s)
  requires InsertDone(s, s', pos)
  ensures Inv(s')
  {
    forall e, i | 0 <= i < |s'.table| && 0 <= e < |s'.table|
    ensures ValidHashInSlot(s'.table, e, i)
    {
      assert ValidHashInSlot(s.table, e, i);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ValidHashOrdering(s'.table, e, j, k)
    {
      assert ValidHashOrdering(s.table, e, j, k);
      assert ValidHashInSlot(s.table, e, j);
      assert ValidHashInSlot(s.table, e, k);
      //assert ValidHashInSlot(s.table, e, pos);
      //assert ValidHashOrdering(s.table, e, j, pos);
      //assert ValidHashOrdering(s.table, e, pos, k);

      //assert ActionNotPastKey(s.table, e, j, pos);

      //assert ActionNotPastKey(s.table, pos, j, k);
      //assert ActionNotPastKey(s.table, pos, k, j);

      //assert ValidHashOrdering(s.table, pos, j, k);
      //assert ValidHashOrdering(s.table, pos, k, j);

      //assert ValidHashInSlot(s.table, pos, j);
      assert ValidHashInSlot(s.table, pos, k);
    }

    /*assert ExistsEmptyEntry(s'.table) by {
      var e' := get_empty_cell_other_than_insertion_cell(s);
      assert 0 <= e' < |s'.table| && s'.table[e'].Some? && s'.table[e'].value.entry.Empty?
            && !s'.table[e'].value.state.RemoveTidying?;
    }*/

    forall i | 0 <= i < |s.table| && s.table[i].value.entry.Full?
    ensures s.table[i].value.entry.kv.key != s.table[pos].value.state.kv.key
    {
      //var e :| 0 <= e < |s.table| && s'.table[e].value.entry.Empty?
        //&& !s.table[e].value.state.RemoveTidying?;
      var e := get_empty_cell_other_than_insertion_cell(s);
      assert ActionNotPastKey(s.table, e, i, pos);
      //assert ActionNotPastKey(s.table, e, pos, i);
      assert ValidHashInSlot(s.table, e, pos);
      //assert ValidHashInSlot(s.table, e, i);
      //assert ValidHashOrdering(s.table, e, pos, i);
      //assert ValidHashOrdering(s.table, e, i, pos);

      //assert ActionNotPastKey(s.table, pos, i, pos);
      //assert ActionNotPastKey(s.table, pos, pos, i);
      //assert ValidHashInSlot(s.table, pos, pos);
      assert ValidHashInSlot(s.table, pos, i);
      //assert ValidHashOrdering(s.table, pos, pos, i);
      //assert ValidHashOrdering(s.table, pos, i, pos);
    }

    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ActionNotPastKey(s'.table, e, j, k)
    {
      assert ActionNotPastKey(s.table, e, j, k);

      //assert ActionNotPastKey(s.table, e, j, pos);
      //assert ActionNotPastKey(s.table, e, k, pos);
      //assert ActionNotPastKey(s.table, e, pos, j);
      //assert ActionNotPastKey(s.table, e, pos, k);
      //assert ActionNotPastKey(s.table, e, j, k);
      //assert ActionNotPastKey(s.table, e, k, j);
      //assert ValidHashInSlot(s.table, e, pos);
      assert ValidHashInSlot(s.table, e, j);
      //assert ValidHashInSlot(s.table, e, k);
      //assert ValidHashOrdering(s.table, e, pos, j);
      //assert ValidHashOrdering(s.table, e, j, pos);
      //assert ValidHashOrdering(s.table, e, pos, k);
      //assert ValidHashOrdering(s.table, e, k, pos);
      //assert ValidHashOrdering(s.table, e, j, k);
      //assert ValidHashOrdering(s.table, e, k, j);

      //assert ActionNotPastKey(s.table, pos, j, pos);
      //assert ActionNotPastKey(s.table, pos, pos, j);
      //assert ActionNotPastKey(s.table, pos, k, pos);
      //assert ActionNotPastKey(s.table, pos, pos, k);
      //assert ActionNotPastKey(s.table, pos, k, j);
      //assert ActionNotPastKey(s.table, pos, j, k);
      //assert ValidHashInSlot(s.table, pos, pos);
      //assert ValidHashInSlot(s.table, pos, j);
      assert ValidHashInSlot(s.table, pos, k);
      //assert ValidHashOrdering(s.table, pos, pos, j);
      //assert ValidHashOrdering(s.table, pos, j, pos);
      //assert ValidHashOrdering(s.table, pos, pos, k);
      //assert ValidHashOrdering(s.table, pos, k, pos);
      //assert ValidHashOrdering(s.table, pos, j, k);
      //assert ValidHashOrdering(s.table, pos, k, j);

    }

    TableQuantity_replace1(s.table, s'.table, pos);
  }

  lemma InsertUpdate_PreservesInv(s: M, s': M, pos: nat)
  requires Inv(s)
  requires InsertUpdate(s, s', pos)
  ensures Inv(s')
  {
    assert forall i | 0 <= i < |s'.table| :: s.table[i].value.entry.Empty? ==> s'.table[i].value.entry.Empty?;

    forall e, i | 0 <= i < |s'.table| && 0 <= e < |s'.table|
    ensures ValidHashInSlot(s'.table, e, i)
    {
      assert ValidHashInSlot(s.table, e, i);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ValidHashOrdering(s'.table, e, j, k)
    {
      assert ValidHashOrdering(s.table, e, j, k);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ActionNotPastKey(s'.table, e, j, k)
    {
      assert ActionNotPastKey(s.table, e, j, k);
    }

    TableQuantity_replace1(s.table, s'.table, pos);
  }

  lemma ProcessQueryTicket_PreservesInv(s: M, s': M, query_ticket: Request)
  requires Inv(s)
  requires ProcessQueryTicket(s, s', query_ticket)
  ensures Inv(s')
  {
    assert forall i | 0 <= i < |s'.table| :: s'.table[i].value.entry == s.table[i].value.entry;

    forall i, e | 0 <= i < |s'.table| && 0 <= e < |s'.table|
    ensures ValidHashInSlot(s'.table, e, i)
    {
      assert ValidHashInSlot(s.table, e, i);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ValidHashOrdering(s'.table, e, j, k)
    {
      assert ValidHashOrdering(s.table, e, j, k);
      assert ValidHashInSlot(s.table, e, j);
      assert ValidHashInSlot(s.table, e, k);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ActionNotPastKey(s'.table, e, j, k)
    {
      assert ActionNotPastKey(s.table, e, j, k);
      assert ValidHashInSlot(s.table, e, j);
    }

    var h := hash(query_ticket.input.key) as int;
    TableQuantity_replace1(s.table, s'.table, h);
  }

  lemma QuerySkip_PreservesInv(s: M, s': M, pos: nat)
  requires Inv(s)
  requires QuerySkip(s, s', pos)
  ensures Inv(s')
  {
    assert forall i | 0 <= i < |s'.table| :: s'.table[i].value.entry == s.table[i].value.entry;

    forall i, e | 0 <= i < |s'.table| && 0 <= e < |s'.table|
    ensures ValidHashInSlot(s'.table, e, i)
    {
      assert ValidHashInSlot(s.table, e, i);

      var i' := if i > 0 then i - 1 else |s.table| - 1;
      assert ValidHashInSlot(s.table, e, i');
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ValidHashOrdering(s'.table, e, j, k)
    {
      assert ValidHashOrdering(s.table, e, j, k);
      assert ValidHashInSlot(s.table, e, j);
      assert ValidHashInSlot(s.table, e, k);
      assert ValidHashInSlot(s.table, e, pos);
      assert ValidHashOrdering(s.table, e, j, pos);
      assert ValidHashOrdering(s.table, e, pos, k);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ActionNotPastKey(s'.table, e, j, k)
    {
      assert ActionNotPastKey(s.table, e, j, pos);
      assert ActionNotPastKey(s.table, e, j, k);
      assert ValidHashInSlot(s.table, e, j);
    }

    TableQuantity_replace2(s.table, s'.table, pos);
  }

  lemma QueryDone_PreservesInv(s: M, s': M, pos: nat)
  requires Inv(s)
  requires QueryDone(s, s', pos)
  ensures Inv(s')
  {
    assert forall i | 0 <= i < |s'.table| :: s'.table[i].value.entry == s.table[i].value.entry;

    forall i, e | 0 <= i < |s'.table| && 0 <= e < |s'.table|
    ensures ValidHashInSlot(s'.table, e, i)
    {
      assert ValidHashInSlot(s.table, e, i);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ValidHashOrdering(s'.table, e, j, k)
    {
      assert ValidHashOrdering(s.table, e, j, k);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ActionNotPastKey(s'.table, e, j, k)
    {
      assert ActionNotPastKey(s.table, e, j, k);
    }

    TableQuantity_replace2(s.table, s'.table, pos);
  }

  lemma QueryNotFound_PreservesInv(s: M, s': M, pos: nat)
  requires Inv(s)
  requires QueryNotFound(s, s', pos)
  ensures Inv(s')
  {
    assert forall i | 0 <= i < |s'.table| :: s'.table[i].value.entry == s.table[i].value.entry;

    forall i, e | 0 <= i < |s'.table| && 0 <= e < |s'.table|
    ensures ValidHashInSlot(s'.table, e, i)
    {
      assert ValidHashInSlot(s.table, e, i);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ValidHashOrdering(s'.table, e, j, k)
    {
      assert ValidHashOrdering(s.table, e, j, k);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ActionNotPastKey(s'.table, e, j, k)
    {
      assert ActionNotPastKey(s.table, e, j, k);
    }

    TableQuantity_replace2(s.table, s'.table, pos);
  }

  lemma ProcessRemoveTicket_PreservesInv(s: M, s': M, remove_ticket: Request)
  requires Inv(s)
  requires ProcessRemoveTicket(s, s', remove_ticket)
  ensures Inv(s')
  {
    assert forall i | 0 <= i < |s'.table| :: s'.table[i].value.entry == s.table[i].value.entry;

    forall i, e | 0 <= i < |s'.table| && 0 <= e < |s'.table|
    ensures ValidHashInSlot(s'.table, e, i)
    {
      assert ValidHashInSlot(s.table, e, i);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ValidHashOrdering(s'.table, e, j, k)
    {
      assert ValidHashOrdering(s.table, e, j, k);
      assert ValidHashInSlot(s.table, e, j);
      assert ValidHashInSlot(s.table, e, k);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ActionNotPastKey(s'.table, e, j, k)
    {
      assert ActionNotPastKey(s.table, e, j, k);
      assert ValidHashInSlot(s.table, e, j);
    }

    var h := hash(remove_ticket.input.key) as int;
    TableQuantity_replace1(s.table, s'.table, h);
  }

  lemma RemoveSkip_PreservesInv(s: M, s': M, pos: nat)
  requires Inv(s)
  requires RemoveSkip(s, s', pos)
  ensures Inv(s')
  {
    assert forall i | 0 <= i < |s'.table| :: s'.table[i].value.entry == s.table[i].value.entry;

    forall i, e | 0 <= i < |s'.table| && 0 <= e < |s'.table|
    ensures ValidHashInSlot(s'.table, e, i)
    {
      assert ValidHashInSlot(s.table, e, i);

      var i' := if i > 0 then i - 1 else |s.table| - 1;
      assert ValidHashInSlot(s.table, e, i');
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ValidHashOrdering(s'.table, e, j, k)
    {
      assert ValidHashOrdering(s.table, e, j, k);
      assert ValidHashInSlot(s.table, e, j);
      assert ValidHashInSlot(s.table, e, k);
      assert ValidHashInSlot(s.table, e, pos);
      assert ValidHashOrdering(s.table, e, j, pos);
      assert ValidHashOrdering(s.table, e, pos, k);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ActionNotPastKey(s'.table, e, j, k)
    {
      assert ActionNotPastKey(s.table, e, j, pos);
      assert ActionNotPastKey(s.table, e, j, k);
      assert ValidHashInSlot(s.table, e, j);
    }

    TableQuantity_replace2(s.table, s'.table, pos);
  }

  lemma RemoveFoundIt_PreservesInv(s: M, s': M, pos: nat)
  requires Inv(s)
  requires RemoveFoundIt(s, s', pos)
  ensures Inv(s')
  {
    assert forall i | 0 <= i < |s'.table| :: i != pos ==> s'.table[i].value.entry == s.table[i].value.entry;

    forall i, e | 0 <= i < |s'.table| && 0 <= e < |s'.table|
    ensures ValidHashInSlot(s'.table, e, i)
    {
      assert ValidHashInSlot(s.table, e, i);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ValidHashOrdering(s'.table, e, j, k)
    {
      assert ValidHashOrdering(s.table, e, j, k);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ActionNotPastKey(s'.table, e, j, k)
    {
      assert ActionNotPastKey(s.table, e, j, k);
    }

    TableQuantity_replace2(s.table, s'.table, pos);
  }

  lemma RemoveNotFound_PreservesInv(s: M, s': M, pos: nat)
  requires Inv(s)
  requires RemoveNotFound(s, s', pos)
  ensures Inv(s')
  {
    assert forall i | 0 <= i < |s'.table| :: i != pos ==> s'.table[i].value.entry == s.table[i].value.entry;

    forall i, e | 0 <= i < |s'.table| && 0 <= e < |s'.table|
    ensures ValidHashInSlot(s'.table, e, i)
    {
      assert ValidHashInSlot(s.table, e, i);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ValidHashOrdering(s'.table, e, j, k)
    {
      assert ValidHashOrdering(s.table, e, j, k);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ActionNotPastKey(s'.table, e, j, k)
    {
      assert ActionNotPastKey(s.table, e, j, k);
    }

    TableQuantity_replace2(s.table, s'.table, pos);
  }

  lemma RemoveTidy_PreservesInv(s: M, s': M, pos: nat)
  requires Inv(s)
  requires RemoveTidy(s, s', pos)
  ensures Inv(s')
  {
    /*assert ExistsEmptyEntry(s'.table) by {
      var e :| 0 <= e < |s.table| && s.table[e].Some? && s.table[e].value.entry.Empty?
        && !s.table[e].value.state.RemoveTidying?;
      assert 0 <= e < |s'.table| && s'.table[e].Some? && s'.table[e].value.entry.Empty?
        && !s'.table[e].value.state.RemoveTidying?;
    }*/

    var pos' := if pos < |s.table| - 1 then pos + 1 else 0;

    forall i, e | 0 <= i < |s'.table| && 0 <= e < |s'.table|
    ensures ValidHashInSlot(s'.table, e, i)
    {
      assert ValidHashInSlot(s.table, e, i);
      assert ValidHashInSlot(s.table, e, pos');
      //assert ValidHashOrdering(s.table, e, pos, pos');
      /*if i == pos {
        if s'.table[e].value.entry.Empty? && !s'.table[e].value.state.RemoveTidying?
            && s'.table[i].value.entry.Full? && s.table[pos'].value.entry.Full? {
          var h := hash(s'.table[i].value.entry.kv.key) as int;
          assert h == hash(s.table[pos'].value.entry.kv.key) as int;

          assert e < h <= pos'
           || h <= pos' < e
           || pos' < e < h;

          assert h != pos';

          assert e < h <= pos
           || h <= pos < e
           || pos < e < h;

          assert ValidHashInSlot(s'.table, e, i);
        }

        assert ValidHashInSlot(s'.table, e, i);
      } else {
        assert ValidHashInSlot(s'.table, e, i);
      }*/
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ValidHashOrdering(s'.table, e, j, k)
    {
      assert ValidHashOrdering(s.table, e, j, k);
      assert ValidHashOrdering(s.table, e, pos', k);
      assert ValidHashOrdering(s.table, e, j, pos');
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ActionNotPastKey(s'.table, e, j, k)
    {
      assert ActionNotPastKey(s.table, e, j, k);
      assert ActionNotPastKey(s.table, e, pos', k);
      assert ActionNotPastKey(s.table, e, j, pos');
    }

    TableQuantity_replace2(s.table, s'.table, pos);
  }

  lemma RemoveDone_PreservesInv(s: M, s': M, pos: nat)
  requires Inv(s)
  requires RemoveDone(s, s', pos)
  ensures Inv(s')
  {
    assert forall i | 0 <= i < |s'.table| :: s'.table[i].value.entry == s.table[i].value.entry;

    var pos' := if pos < |s.table| - 1 then pos + 1 else 0;

    assert s'.table[pos].value.entry.Empty?;

    forall i, e | 0 <= i < |s'.table| && 0 <= e < |s'.table|
    ensures ValidHashInSlot(s'.table, e, i)
    {
      var e' := get_empty_cell(s.table);
      
      assert ValidHashInSlot(s.table, e, i);

      assert ValidHashInSlot(s.table, pos', i);
      assert ValidHashOrdering(s.table, e', pos', i);

      assert ValidHashInSlot(s.table, e', i);

      assert ValidHashInSlot(s.table, i, e');
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ValidHashOrdering(s'.table, e, j, k)
    {
      var e' := get_empty_cell(s.table);

      assert ValidHashOrdering(s.table, e, j, k);

      assert ValidHashOrdering(s.table, e', j, k);
      //assert ValidHashOrdering(s.table, e', k, j);

      assert ValidHashInSlot(s.table, pos', j);
      assert ValidHashOrdering(s.table, e', pos', j);
      //assert ValidHashInSlot(s.table, e', j);

      //assert ValidHashInSlot(s.table, pos', k);
      //assert ValidHashOrdering(s.table, e', pos', k);
      assert ValidHashInSlot(s.table, e', k);
    }
    forall e, j, k | 0 <= e < |s'.table| && 0 <= j < |s'.table| && 0 <= k < |s'.table|
    ensures ActionNotPastKey(s'.table, e, j, k)
    {
      var e' := get_empty_cell(s.table);

      assert ActionNotPastKey(s.table, e, j, k);

      //assert ValidHashOrdering(s.table, e, j, k);
      //assert ValidHashOrdering(s.table, e', j, k);
      assert ValidHashInSlot(s.table, pos', j);
      assert ValidHashOrdering(s.table, e', pos', j);
      assert ValidHashInSlot(s.table, e', k);

      //assert ActionNotPastKey(s.table, e, j, k);
      assert ActionNotPastKey(s.table, e', j, k);
      //assert ActionNotPastKey(s.table, e', pos', j);
    }

    TableQuantity_replace2(s.table, s'.table, pos);
  }

  lemma NextStep_PreservesInv(s: M, s': M, step: Step)
  requires Inv(s)
  requires NextStep(s, s', step)
  ensures Inv(s')
  {
    match step {
      case ProcessInsertTicketStep(insert_ticket) => ProcessInsertTicket_PreservesInv(s, s', insert_ticket);
      case InsertSkipStep(pos) => InsertSkip_PreservesInv(s, s', pos);
      case InsertSwapStep(pos) => InsertSwap_PreservesInv(s, s', pos);
      case InsertDoneStep(pos) => InsertDone_PreservesInv(s, s', pos);
      case InsertUpdateStep(pos) => InsertUpdate_PreservesInv(s, s', pos);

      case ProcessRemoveTicketStep(remove_ticket) => ProcessRemoveTicket_PreservesInv(s, s', remove_ticket);
      case RemoveSkipStep(pos) => RemoveSkip_PreservesInv(s, s', pos);
      case RemoveFoundItStep(pos) => RemoveFoundIt_PreservesInv(s, s', pos);
      case RemoveNotFoundStep(pos) => RemoveNotFound_PreservesInv(s, s', pos);
      case RemoveTidyStep(pos) => RemoveTidy_PreservesInv(s, s', pos);
      case RemoveDoneStep(pos) => RemoveDone_PreservesInv(s, s', pos);

      case ProcessQueryTicketStep(query_ticket) => ProcessQueryTicket_PreservesInv(s, s', query_ticket);
      case QuerySkipStep(pos) => QuerySkip_PreservesInv(s, s', pos);
      case QueryDoneStep(pos) => QueryDone_PreservesInv(s, s', pos);
      case QueryNotFoundStep(pos) => QueryNotFound_PreservesInv(s, s', pos);
    }
  }

  lemma Next_PreservesInv(s: M, s': M)
  requires Inv(s)
  requires Next(s, s')
  ensures Inv(s')
  {
    var step :| NextStep(s, s', step);
    NextStep_PreservesInv(s, s', step);
  }

//////////////////////////////////////////////////////////////////////////////
// fragment-level validity defined wrt Inv
//////////////////////////////////////////////////////////////////////////////
  predicate Valid(s: M)
    ensures Valid(s) ==> s.M?
  {
    && s.M?
    && exists t :: Inv(dot(s, t))
  }

  function {:opaque} GetRemainder(s: M): (t: M)
    requires Valid(s)
    ensures Inv(dot(s, t))
  {
    // reveal Valid();
    var t :| Inv(dot(s, t));
    t
  }

  lemma InvImpliesValid(s: M)
    requires Inv(s)
    ensures Valid(s)
  {
    // reveal Valid();
    dot_unit(s);
  }

  lemma valid_monotonic(x: M, y: M)
  requires Valid(dot(x, y))
  ensures Valid(x)
  {
    // reveal Valid();
    var xy' :| Inv(dot(dot(x, y), xy'));
    associative(x, y, xy');
    assert Inv(dot(x, dot(y, xy')));
  }

  lemma update_monotonic(x: M, y: M, z: M)
  requires Next(x, y)
  requires Valid(dot(x, z))
  ensures Next(dot(x, z), dot(y, z))
  {
    var step :| NextStep(x, y, step);
    assert NextStep(dot(x, z), dot(y, z), step);
  }

  lemma {:induction true} EmptyTableQuantityIsZero(infos: seq<Option<Info>>)
    requires (forall i | 0 <= i < |infos| :: infos[i] == Some(Info(Empty, Free)))
    ensures TableQuantity(infos) == 0
  {
    reveal_TableQuantity();
  }

  /*
  lemma InitImpliesValid(s: M)
  requires s == Init()
  ensures Valid(s)
  {
    EmptyTableQuantityIsZero(s.table);
    InvImpliesValid(s);
  }
  */

  /*
  lemma NextPreservesValid(s: M, s': M)
  requires Next(s, s')
  requires Valid(s)
  ensures Valid(s')
  {
    // reveal Valid();
    var t :| Inv(dot(s, t));
    InvImpliesValid(dot(s, t));
    update_monotonic(s, s', t);
    Next_PreservesInv(dot(s, t), dot(s', t));
  }
  */

  predicate TransitionEnable(s: M, step: Step)
  {
    match step {
      case ProcessInsertTicketStep(insert_ticket) => ProcessInsertTicketEnable(s, insert_ticket)
      case InsertSkipStep(pos) => InsertSkipEnable(s, pos)
      case InsertSwapStep(pos) => InsertSwapEanble(s, pos)
      case InsertDoneStep(pos) => InsertDoneEnable(s, pos)
      case InsertUpdateStep(pos) => InsertUpdateEnable(s, pos)

      case ProcessRemoveTicketStep(remove_ticket) => ProcessRemoveTicketEnable(s, remove_ticket)
      case RemoveSkipStep(pos) => RemoveSkipEnable(s, pos)
      case RemoveFoundItStep(pos) => RemoveFoundItEnable(s, pos)
      case RemoveNotFoundStep(pos) => RemoveNotFoundEnable(s, pos)
      case RemoveTidyStep(pos) => RemoveTidyEnable(s, pos)
      case RemoveDoneStep(pos) => RemoveDoneEnable(s, pos)

      case ProcessQueryTicketStep(query_ticket) => ProcessQueryTicketEnable(s, query_ticket)
      case QuerySkipStep(pos) => QuerySkipEnable(s, pos)
      case QueryDoneStep(pos) => QueryDoneEnable(s, pos)
      case QueryNotFoundStep(pos) => QueryNotFoundEnable(s, pos)
    }
  }

  function GetTransition(s: M, step: Step): (s': M)
    requires TransitionEnable(s, step)
    ensures NextStep(s, s', step);
  {
    match step {
      case ProcessInsertTicketStep(insert_ticket) => ProcessInsertTicketTransition(s, insert_ticket)
      case InsertSkipStep(pos) => InsertSkipTransition(s, pos)
      case InsertSwapStep(pos) => InsertSwapTransition(s, pos)
      case InsertDoneStep(pos) => InsertDoneTransition(s, pos)
      case InsertUpdateStep(pos) => InsertUpdateTransition(s, pos)

      case ProcessRemoveTicketStep(remove_ticket) => ProcessRemoveTicketTransition(s, remove_ticket)
      case RemoveSkipStep(pos) => RemoveSkipTransition(s, pos)
      case RemoveFoundItStep(pos) => RemoveFoundItTransition(s, pos)
      case RemoveNotFoundStep(pos) => RemoveNotFoundTransition(s, pos)
      case RemoveTidyStep(pos) => RemoveTidyTransition(s, pos)
      case RemoveDoneStep(pos) => RemoveDoneTransition(s, pos)

      case ProcessQueryTicketStep(query_ticket) => ProcessQueryTicketTransition(s, query_ticket)
      case QuerySkipStep(pos) => QuerySkipTransition(s, pos)
      case QueryDoneStep(pos) => QueryDoneTransition(s, pos)
      case QueryNotFoundStep(pos) => QueryNotFoundTransition(s, pos)
    }
  }

  // Reduce boilerplate by letting caller provide explicit step, which triggers a quantifier for generic Next()
  /*
  glinear method easy_transform_step(glinear b: M, ghost step: Step)
  returns (glinear c: M)
    requires TransitionEnable(b, step)
    ensures c == GetTransition(b, step)
  {
    var e := GetTransition(b, step);
    c := do_transform(b, e);
  }
  */

  /*
  lemma NewRequestPreservesValid(r: M, id: int, input: MapIfc.Input)
    //requires Valid(r)
    ensures Valid(dot(r, input_ticket(id, input)))
  {
    // reveal Valid();
    var ticket := input_ticket(id, input);
    var t :| Inv(dot(r, t));

    assert dot(dot(r, ticket), t).table == dot(r, t).table;
    assert dot(dot(r, ticket), t).insert_capacity == dot(r, t).insert_capacity;
  }
  */

  /*
  // Trusted composition tools. Not sure how to generate them.
  glinear method {:extern} enclose(glinear a: Count.M) returns (glinear h: M)
    requires Count.Valid(a)
    ensures h == unit().(insert_capacity := a)

  glinear method {:extern} declose(glinear h: M) returns (glinear a: Count.M)
    requires h.M?
    requires h.table == unitTable() // h is a unit() except for a
    requires h.tickets == multiset{}
    requires h.stubs == multiset{}
    ensures a == h.insert_capacity
    // ensures unit_r == unit()
  */

  predicate IsStub(rid: RequestId, output: IOIfc.Output, stub: M)
  {
    stub == Stub(rid, output)
  }

  // By returning a set of request ids "in use", we enforce that
  // there are only a finite number of them (i.e., it is always possible to find
  // a free one).
  function request_ids_in_use(m: M) : set<RequestId>
  {
    {}
  }

  predicate Internal(shard: M, shard': M) {
    Next(shard, shard')
  }

  lemma InitImpliesInv(s: M)
  //requires s == Init()
  ensures Inv(s)
  {
    EmptyTableQuantityIsZero(s.table);
  }

  lemma InternalPreservesInv(shard: M, shard': M, rest: M)
  //requires Inv(dot(shard, rest))
  //requires Internal(shard, shard')
  ensures Inv(dot(shard', rest))
  {
    InvImpliesValid(dot(shard, rest));
    update_monotonic(shard, shard', rest);
    Next_PreservesInv(dot(shard, rest), dot(shard', rest));
  }

  /*lemma fuse_seq_add(a: seq<Option<Info>>, b: seq<Option<Info>>)
  requires |a| == FixedSize()
  requires |b| == FixedSize()
  requires nonoverlapping(a, b)
  ensures TableQuantity(fuse_seq(a, b)) == TableQuantity(a) + TableQuantity(b)
  */

  lemma NewTicketPreservesInv(whole: M, whole': M, rid: RequestId, input: IOIfc.Input)
  //requires Inv(whole)
  //requires NewTicket(whole, whole', rid, input)
  ensures Inv(whole')
  {
    assert whole.table == whole'.table;
  }

  lemma ConsumeStubPreservesInv(whole: M, whole': M, rid: RequestId, output: IOIfc.Output, stub: M)
  //requires Inv(whole)
  //requires ConsumeStub(whole, whole', rid, output, stub)
  ensures Inv(whole')
  {
    assert whole.table == whole'.table;
  }

  lemma exists_inv_state()
  returns (s: M)
  ensures Inv(s)
  {
    s := Init();
    InitImpliesInv(s);
  }
}

