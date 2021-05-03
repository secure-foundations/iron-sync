include "../../lib/Lang/NativeTypes.s.dfy"
include "../../lib/Base/Option.s.dfy"
include "ConcurrencyModel.s.dfy"
include "AppSpec.s.dfy"

module ShardedSMTransitions  {
  // Extracted from 
}

module ShardedSMInvProof {
  // what was ResourceStateMachine
}

module UnifiedSM {
  // Reason about all the shards at once
}

module MonoidalSM {
  // Show the validity requirement from ApplicationResourcesSpec
}


module ShardedHashTable refines ShardedStateMachine {
  import opened NativeTypes
  import opened Options
  import MapIfc

//////////////////////////////////////////////////////////////////////////////
// Data structure definitions & transitions
//////////////////////////////////////////////////////////////////////////////

  import opened KeyValueType

  datatype Ticket =
    | Ticket(rid: int, input: MapIfc.Input)

  datatype Stub =
    | Stub(rid: int, output: MapIfc.Output)

  function FixedSize() : (n: nat)
  ensures n > 1

  function Capacity() : (n: nat)
  {
    FixedSize() - 1
  }

  function method FixedSizeImpl() : (n: uint32)
  ensures n as int == FixedSize()

  predicate ValidHashIndex(h:int) {
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
    | Inserting(rid: int, kv: KV, initial_key: Key)
    | Removing(rid: int, key: Key)
    | RemoveTidying(rid: int, initial_key: Key, found_value: Value)

      // Why do we need to store query state to support an invariant over the
      // hash table interpretation, since query is a read-only operation?
      // Because the query's result is defined at the moment it begins (its
      // serialization point), which is to say the proof ghostily knows the
      // answer when the query begins. We need to show inductively that that
      // answer stays the same with each step of any thread, until the impl
      // gets far enough to discover the answer in the real data structure.
      // We're showing that we inductively preserve the value of the
      // interpretation of the *answer* to query #rid.
    | Querying(rid: int, key: Key)

  // TODO rename
  datatype Info = Info(entry: Entry, state: State)

  datatype PreR =
      | Variables(table: seq<Option<Info>>,
          insert_capacity: nat,
          tickets: multiset<Ticket>,
          stubs: multiset<Stub>)
      | Fail
        // The NextStep disjunct is complex, but we'll show that as long
        // as the impl obeys them, it'll never land in Fail.
        // The state is here to "leave slack" in the defenition of add(),
        // so that we can push off the proof that we never end up failing
        // until UpdatePreservesValid. If we didn't do it this way, we'd
        // have to show that add is complete, which would entail sucking
        // the definition of update and proof of UpdatePreservesValid all
        // into the definition of add().
  type Variables = r: PreR | (r.Variables? ==> |r.table| == FixedSize()) witness Fail

  function unitTable(): seq<Option<Info>>
  {
    seq(FixedSize(), i => None)
  }

  function unit() : Variables {
    Variables(unitTable(), 0, multiset{}, multiset{})
  }

  function oneRowTable(k: nat, info: Info) : seq<Option<Info>>
    requires 0 <= k < FixedSize()
  {
    seq(FixedSize(), i => if i == k then Some(info) else None)
  }

  function oneRowResource(k: nat, info: Info, cap: nat) : Variables 
    requires 0 <= k < FixedSize()
  {
    Variables(oneRowTable(k, info), cap, multiset{}, multiset{})
  }

  // predicate resourceHasSingleRow(r: Variables, k: nat, info: Info)
  //   requires 0 <= k < FixedSize()
  // {
  //   && r.Variables?
  //   && (forall i:nat | i < FixedSize() :: if i == k then r.table[i].Some? else r.table[i].None?)
  //   && r.table[k].value == info
  //   && r.tickets == multiset{}
  //   && r.stubs == multiset{}
  // }

  function twoRowsTable(k1: nat, info1: Info, k2: nat, info2: Info) : seq<Option<Info>>
    requires 0 <= k1 < FixedSize()
    requires 0 <= k2 < FixedSize()
    requires k1 != k2
  {
    seq(FixedSize(), i => if i == k1 then Some(info1) else if i == k2 then Some(info2) else None)
  }

  function twoRowsResource(k1: nat, info1: Info, k2: nat, info2: Info, cap: nat) : Variables 
    requires 0 <= k1 < FixedSize()
    requires 0 <= k2 < FixedSize()
    requires k1 != k2
  {
    Variables(twoRowsTable(k1, info1, k2, info2), cap, multiset{}, multiset{})
  }

  predicate isInputResource(in_r: Variables, rid: int, input: Ifc.Input)
  {
    && in_r.Variables?
    && in_r.table == unitTable()
    && in_r.insert_capacity == 0
    && in_r.tickets == multiset { Ticket(rid, input) }
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

  function add(x: Variables, y: Variables) : Variables {
    if x.Variables? && y.Variables? && nonoverlapping(x.table, y.table) then (
      Variables(fuse_seq(x.table, y.table),
          x.insert_capacity + y.insert_capacity,
          x.tickets + y.tickets,
          x.stubs + y.stubs)
    ) else (
      Fail
    )
  }

  lemma add_unit(x: Variables)
  ensures add(x, unit()) == x
  {
  }

  lemma commutative(x: Variables, y: Variables)
  ensures add(x, y) == add(y, x)
  {
    if x.Variables? && y.Variables? && nonoverlapping(x.table, y.table) {
      /*assert nonoverlapping(y.table, x.table);
      forall i | 0 <= i < FixedSize()
      ensures add(x,y).table[i] == add(y,x).table[i]
      {
        assert fuse(x.table[i], y.table[i]) == fuse(y.table[i], x.table[i]);
      }*/
      assert fuse_seq(x.table, y.table) == fuse_seq(y.table, x.table);
      assert add(x, y).tickets == add(y, x).tickets;
      assert add(x, y).stubs == add(y, x).stubs;
    }
  }

  lemma associative(x: Variables, y: Variables, z: Variables)
  ensures add(x, add(y, z)) == add(add(x, y), z)
  {
    if x.Variables? && y.Variables? && z.Variables? && nonoverlapping(x.table, y.table)
        && nonoverlapping(fuse_seq(x.table, y.table), z.table)
    {
      /*forall i | 0 <= i < FixedSize()
      ensures add(x, add(y, z)).table[i] == add(add(x, y), z).table[i]
      {
      }
      //assert fuse_seq(fuse_seq(x.table, y.table), z.table)
      //    == fuse_seq(x.table, fuse_seq(y.table, z.table));
      assert add(x, add(y, z)).table == add(add(x, y), z).table;*/
      assert add(x, add(y, z)) == add(add(x, y), z);
    } else {
    }
  }

  predicate Init(s: Variables) {
    && s.Variables?
    && (forall i | 0 <= i < |s.table| :: s.table[i] == Some(Info(Empty, Free)))
    && s.insert_capacity == Capacity()
    && s.tickets == multiset{}
    && s.stubs == multiset{}
  }

  datatype Step =
    | ProcessInsertTicketStep(insert_ticket: Ticket)
    | InsertSkipStep(pos: nat)
    | InsertSwapStep(pos: nat)
    | InsertDoneStep(pos: nat)
    | InsertUpdateStep(pos: nat)

    | ProcessRemoveTicketStep(insert_ticket: Ticket)
    | RemoveSkipStep(pos: nat)
    | RemoveFoundItStep(pos: nat)
    | RemoveNotFoundStep(pos: nat)
    | RemoveTidyStep(pos: nat)
    | RemoveDoneStep(pos: nat)

    | ProcessQueryTicketStep(query_ticket: Ticket)
    | QuerySkipStep(pos: nat)
    | QueryDoneStep(pos: nat)
    | QueryNotFoundStep(pos: nat)

  predicate ProcessInsertTicket(s: Variables, s': Variables, insert_ticket: Ticket)
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
    && (s' == s
      .(tickets := s.tickets - multiset{insert_ticket})
      .(insert_capacity := s.insert_capacity - 1)
      .(table := s.table[h := Some(
          s.table[h].value.(
              state := Inserting(insert_ticket.rid,
              KV(key, insert_ticket.input.value),key)))]))
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
  requires 0 <= root <= FixedSize()
  {
    if i < root then FixedSize() + i else i
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
        && adjust(h, e+1) <= adjust(i, e+1)
      ))
      && (table[i].value.state.Inserting? ==> (
        var h := hash(table[i].value.state.kv.key) as int;
        && adjust(h, e+1) <= adjust(i, e+1)
      ))
      && ((table[i].value.state.Removing? || table[i].value.state.Querying?) ==> (
        var h := hash(table[i].value.state.key) as int;
        && adjust(h, e+1) <= adjust(i, e+1)
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
    (table[e].value.entry.Empty? && !table[e].value.state.RemoveTidying? && table[j].value.entry.Full? && adjust(j, e + 1) < adjust(k, e + 1) ==> (
      var hj := hash(table[j].value.entry.kv.key) as int;

      && (table[k].value.entry.Full? ==> (
        var hk := hash(table[k].value.entry.kv.key) as int;
        && adjust(hj, e + 1) <= adjust(hk, e + 1)
      ))

      // If entry 'k' has an 'Inserting' action on it, then that action must have
      // gotten past entry 'j'.
      && (table[k].value.state.Inserting? ==> (
        var ha := hash(table[k].value.state.kv.key) as int;
        && adjust(hj, e+1) <= adjust(ha, e+1)
      ))

      && ((table[k].value.state.Removing? || table[k].value.state.Querying?) ==> (
        var ha := hash(table[k].value.state.key) as int;
        && adjust(hj, e+1) <= adjust(ha, e+1)
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
    (table[e].value.entry.Empty? && !table[e].value.state.RemoveTidying? && table[j].value.entry.Full? && adjust(j, e + 1) < adjust(k, e + 1) ==> (
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

  predicate Inv(s: Variables)
  {
    && s.Variables?
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

  lemma get_empty_cell_other_than_insertion_cell(s: Variables)
  returns (e: int)
  requires Inv(s)
  ensures 0 <= e < |s.table| && s.table[e].Some? && s.table[e].value.entry.Empty?
        && !s.table[e].value.state.RemoveTidying?
        && !s.table[e].value.state.Inserting?
  {
    e := get_empty_cell_other_than_insertion_cell_table(s.table);
  }

  lemma ProcessInsertTicket_PreservesInv(s: Variables, s': Variables, insert_ticket: Ticket)
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

  lemma InsertSkip_PreservesInv(s: Variables, s': Variables, pos: nat)
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

      /*if j == pos && (pos == FixedSize() - 1 ==> k == 0) && (pos < FixedSize() - 1 ==> k == j + 1) {
        assert ValidHashOrdering(s'.table, e, j, k);
      } else if j == pos {
        assert ValidHashOrdering(s'.table, e, j, k);
      } else if (pos == FixedSize() - 1 ==> k == 0) && (pos < FixedSize() - 1 ==> k == pos + 1) {
        if s'.table[e].value.entry.Empty? && s'.table[j].value.entry.Full? && adjust(j, e) <= adjust(k, e) && s'.table[k].value.state.Inserting? {
          if j == k {
            assert ValidHashOrdering(s'.table, e, j, k);
          } else {
            assert hash(s.table[j].value.entry.kv.key)
                == hash(s'.table[j].value.entry.kv.key);
            assert hash(s.table[pos].value.state.kv.key)
                == hash(s'.table[k].value.state.kv.key);

            assert s.table[e].value.entry.Empty?;
            assert s.table[j].value.entry.Full?;
            assert adjust(j, e) <= adjust(pos, e);
            assert s.table[pos].value.state.Inserting?;

            assert ValidHashOrdering(s.table, e, j, pos);
            assert ValidHashOrdering(s'.table, e, j, k);
          }
        }
      } else {
        assert ValidHashOrdering(s'.table, e, j, k);
      }*/
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

  lemma InsertSwap_PreservesInv(s: Variables, s': Variables, pos: nat)
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

  lemma InsertDone_PreservesInv(s: Variables, s': Variables, pos: nat)
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

  lemma InsertUpdate_PreservesInv(s: Variables, s': Variables, pos: nat)
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

  lemma ProcessQueryTicket_PreservesInv(s: Variables, s': Variables, query_ticket: Ticket)
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

  lemma QuerySkip_PreservesInv(s: Variables, s': Variables, pos: nat)
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

  lemma QueryDone_PreservesInv(s: Variables, s': Variables, pos: nat)
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

  lemma QueryNotFound_PreservesInv(s: Variables, s': Variables, pos: nat)
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

  lemma ProcessRemoveTicket_PreservesInv(s: Variables, s': Variables, remove_ticket: Ticket)
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

  lemma RemoveSkip_PreservesInv(s: Variables, s': Variables, pos: nat)
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

  lemma RemoveFoundIt_PreservesInv(s: Variables, s': Variables, pos: nat)
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

  lemma RemoveNotFound_PreservesInv(s: Variables, s': Variables, pos: nat)
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

  lemma RemoveTidy_PreservesInv(s: Variables, s': Variables, pos: nat)
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

  lemma RemoveDone_PreservesInv(s: Variables, s': Variables, pos: nat)
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

      //assert ValidHashInSlot(s.table, e', pos');
      //assert ValidHashInSlot(s.table, pos', e');

      //assert ValidHashInSlot(s.table, i, e);
      //assert ValidHashOrdering(s.table, e', i, pos');
      //assert ValidHashInSlot(s.table, pos, i);
      //assert ValidHashOrdering(s.table, e', pos, i);
      //assert ValidHashOrdering(s.table, e', i, pos);

      /*var e1 := if e < |s.table| - 1 then e + 1 else 0;
 
      assert ValidHashInSlot(s.table, e1, i);

      assert ValidHashInSlot(s.table, pos', i);
      assert ValidHashOrdering(s.table, e1, pos', i);

      assert ValidHashInSlot(s.table, e1, i);

      assert ValidHashInSlot(s.table, i, e1);

      assert ValidHashInSlot(s.table, e1, pos');
      assert ValidHashInSlot(s.table, pos', e1);

      assert ValidHashInSlot(s.table, i, e);
      assert ValidHashOrdering(s.table, e1, i, pos');
      assert ValidHashInSlot(s.table, pos, i);
      assert ValidHashOrdering(s.table, e1, pos, i);
      assert ValidHashOrdering(s.table, e1, i, pos);

      assert ValidHashOrdering(s.table, e1, i, e);
      assert ValidHashOrdering(s.table, e1, e, i);
      assert ValidHashInSlot(s.table, e1, i);

      assert ValidHashOrdering(s.table, e', e, e1);

      assert ValidHashOrdering(s.table, e', e1, i);
      assert ValidHashInSlot(s.table, e', e1);

      assert ValidHashInSlot(s.table, e, e);
      assert ValidHashInSlot(s.table, e', e');
      assert ValidHashInSlot(s.table, e1, e1);

      assert ValidHashInSlot(s.table, e', i);

      assert ValidHashOrdering(s.table, e', e, i);*/


      /*if e == pos {
        if i == pos' {
          assert ValidHashInSlot(s'.table, e, i);
        } else {
          if s.table[pos'].value.entry.Full? {
            if adjust(i, pos) < adjust(e', pos) {
              assert ValidHashInSlot(s'.table, e, i);
            } else if i == e' {
              assert s.table[e1].value.entry.Full?  ==>
                  hash(s.table[e1].value.entry.kv.key) as int
                == e1;
              
              if s.table[e1].value.entry.Full? {
                if e == e' {
                  assert ValidHashInSlot(s'.table, e, i);
                } else {
                  assert ValidHashInSlot(s'.table, e, i);
                }
              } else {
                assert ValidHashInSlot(s'.table, e, i);
              }
            } else {
              assert ValidHashInSlot(s'.table, e, i);
            }
          } else {
            assert ValidHashInSlot(s'.table, e, i);
          }
        }
      } else {
        assert ValidHashInSlot(s'.table, e, i);
      }*/
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

  lemma NextStep_PreservesInv(s: Variables, s': Variables, step: Step)
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


  lemma Next_PreservesInv(s: Variables, s': Variables)
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

//////////////////////////////////////////////////////////////////////////////
// Old crap we need to organize
//////////////////////////////////////////////////////////////////////////////

  predicate ProcessInsertTicketFail(s: Variables, s': Variables, insert_ticket: Ticket)
  {
    && !s.Fail?
    && insert_ticket.input.InsertInput?
    && insert_ticket in s.tickets
    // && s.insert_capacity == 1
    && (s' == s
      .(tickets := s.tickets - multiset{insert_ticket})
      .(stubs := s.stubs + multiset{Stub(insert_ticket.rid, MapIfc.InsertOutput(false))}))
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

  // We're trying to insert new_item at pos j
  // where hash(new_item) >= hash(pos j)
  // we skip item i and move to i+1.
  predicate InsertSkip(s: Variables, s': Variables, pos: nat)
  {
    && !s.Fail?
    && s'.Variables?
    && 0 <= pos < FixedSize()
    && var pos' := (if pos < FixedSize() - 1 then pos + 1 else 0);
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

    && s' == s.(table := s.table
        [pos := Some(s.table[pos].value.(state := Free))]
        [pos' := Some(s.table[pos'].value.(state := s.table[pos].value.state))])
  }

  // We're trying to insert new_item at pos j
  // where hash(new_item) < hash(pos j)
  // in this case we do the swap and keep moving forward
  // with the swapped-out item.
  predicate InsertSwap(s: Variables, s': Variables, pos: nat)
  {
    && !s.Fail?
    && 0 <= pos < FixedSize()
    && var pos' := (if pos < FixedSize() - 1 then pos + 1 else 0);
    && s.table[pos].Some?
    && s.table[pos'].Some?
    && var state := s.table[pos].value.state;
    && state.Inserting?
    && s.table[pos].value.entry.Full?
    && ShouldHashGoBefore(
        hash(state.kv.key) as int,
        hash(s.table[pos].value.entry.kv.key) as int, pos)
    && s.table[pos'].value.state.Free?

    && s' == s.(table := s.table
        [pos := Some(Info(
          Full(state.kv),
          Free))]
        [pos' := Some(s.table[pos'].value.(state :=
          Inserting(
            state.rid,
            s.table[pos].value.entry.kv, state.initial_key)))])
  }

  // Slot is empty. Insert our element and finish.
  predicate InsertDone(s: Variables, s': Variables, pos: nat)
  {
    && !s.Fail?
    && 0 <= pos < FixedSize()
    && s.table[pos].Some?
    && s.table[pos].value.state.Inserting?
    && s.table[pos].value.entry.Empty?
    && s' == s
      .(table := s.table
        [pos := Some(Info(
            Full(s.table[pos].value.state.kv),
            Free))])
      .(stubs := s.stubs + multiset{Stub(s.table[pos].value.state.rid, MapIfc.InsertOutput(true))})
  }

  predicate InsertUpdate(s: Variables, s': Variables, pos: nat)
  {
    && !s.Fail?
    && 0 <= pos < FixedSize()
    && s.table[pos].Some?
    && s.table[pos].value.state.Inserting?
    && s.table[pos].value.entry.Full?
    && s.table[pos].value.entry.kv.key == s.table[pos].value.state.kv.key
    && s' == s
      .(table := s.table
        [pos := Some(Info(
            Full(s.table[pos].value.state.kv),
            Free))])
      .(insert_capacity := s.insert_capacity + 1) // we reserved the capacity at the begining, but later discover we don't need it
      .(stubs := s.stubs + multiset{Stub(s.table[pos].value.state.rid, MapIfc.InsertOutput(true))})
  }

  // Remove

  // We know about row h (our thread is working on it),
  // and we know that it's free (we're not already claiming to do something else with it).
  predicate KnowRowIsFree(s: Variables, h: int)
    requires !s.Fail?
    requires ValidHashIndex(h)
  {
    && s.table[h].Some?
    && s.table[h].value.state.Free?
  }

  predicate ProcessRemoveTicket(s: Variables, s': Variables, remove_ticket: Ticket)
  {
    && !s.Fail?
    && remove_ticket.input.RemoveInput?
    && remove_ticket in s.tickets
    && var h: uint32 := hash(remove_ticket.input.key);
    && KnowRowIsFree(s, h as int)
    && s' == s
      .(tickets := s.tickets - multiset{remove_ticket})
      .(table := s.table[h := Some(
          s.table[h].value.(state :=
            Removing(remove_ticket.rid,
              remove_ticket.input.key)))])
  }

  predicate RemoveInspectEnabled(s: Variables, pos: nat)
  {
    && !s.Fail?
    && 0 <= pos < FixedSize()
    // Know row pos, and it's the thing we're removing, and it's full...
    && s.table[pos].Some?
    && s.table[pos].value.state.Removing?
  }

  predicate RemoveSkipEnabled(s: Variables, pos: nat)
  {
    && RemoveInspectEnabled(s, pos)
    && s.table[pos].value.entry.Full?
    && var pos' := (if pos < FixedSize() - 1 then pos + 1 else 0);
    && KnowRowIsFree(s, pos')
    // ...and the key it's full of sorts before the thing we're looking to remove.
    && !ShouldHashGoBefore(
        hash(s.table[pos].value.state.key) as int,
        hash(s.table[pos].value.entry.kv.key) as int, pos)
  }

  predicate RemoveSkip(s: Variables, s': Variables, pos: nat)
  {
    && RemoveSkipEnabled(s, pos)
    // The hash is equal, but this isn't the key we're trying to remove.
    && s.table[pos].value.entry.kv.key != s.table[pos].value.state.key
    && var pos' := (if pos < FixedSize() - 1 then pos + 1 else 0);

    // Advance the pointer to the next row.
    && s' == s.(table := s.table
        [pos := Some(s.table[pos].value.(state := Free))]
        [pos' := Some(s.table[pos'].value.(state := s.table[pos].value.state))])
  }

  predicate RemoveNotFound(s: Variables, s': Variables, pos: nat)
  {
    && RemoveInspectEnabled(s, pos)
    && (if s.table[pos].value.entry.Full? then // the key we are looking for goes before the one in the slot, so it must be absent
      && ShouldHashGoBefore(
        hash(s.table[pos].value.state.key) as int,
        hash(s.table[pos].value.entry.kv.key) as int, pos)
      && s.table[pos].value.entry.kv.key != s.table[pos].value.state.key
      else true // the key would have been in this empty spot
    )
    && s' == s
      .(table := s.table[pos := Some(Info(s.table[pos].value.entry, Free))])
      .(stubs := s.stubs + multiset{Stub(s.table[pos].value.state.rid, MapIfc.RemoveOutput(false))})
  }

  predicate RemoveFoundIt(s: Variables, s': Variables, pos: nat)
  {
    && RemoveSkipEnabled(s, pos)
    // This IS the key we want to remove!
    && var initial_key := s.table[pos].value.state.key;
    && s.table[pos].value.entry.kv.key == initial_key

    // Change the program counter into RemoveTidying mode
    && var rid := s.table[pos].value.state.rid;
    // Note: it doesn't matter what we set the entry to here, since we're going
    // to overwrite it in the next step either way.
    // (Might be easier to leave the entry as it is rather than set it to Empty?)
    && s' == s.(table := s.table[pos := Some(Info(Empty,
        RemoveTidying(rid, initial_key, s.table[pos].value.entry.kv.val)))])
  }

  predicate TidyEnabled(s: Variables, pos: nat)
  {
    && !s.Fail?
    && ValidHashIndex(pos)
    // The row that needs backfilling is known and we're pointing at it
    && s.table[pos].Some?
    && s.table[pos].value.state.RemoveTidying?
    && s.table[pos].value.entry.Empty?  // Should be an invariant, actually
    && (pos < FixedSize() - 1 ==> s.table[pos+1].Some?) // if a next row, we know it
  }

  predicate DoneTidying(s: Variables, pos: nat)
    requires TidyEnabled(s, pos)
  {
    var pos' := (if pos < FixedSize() - 1 then pos + 1 else 0);
    && KnowRowIsFree(s, pos')
    && (
      || s.table[pos'].value.entry.Empty?                     // Next row is empty
      || pos' == hash(s.table[pos'].value.entry.kv.key) as nat  // Next row's key can't move back
    )
  }

  predicate RemoveTidy(s: Variables, s': Variables, pos: nat)
  {
    && TidyEnabled(s, pos)
    && !DoneTidying(s, pos)

    && var pos' := (if pos < FixedSize() - 1 then pos + 1 else 0);
    && KnowRowIsFree(s, pos')

    // Pull the entry back one slot, and push the state pointer forward one slot.
    && s' == s.(table := s.table
      [pos := Some(Info(s.table[pos'].value.entry, Free))]
      [pos' := Some(Info(Empty, s.table[pos].value.state))]
      )
  }

  predicate RemoveDone(s: Variables, s': Variables, pos: nat)
  {
    && TidyEnabled(s, pos)
    && DoneTidying(s, pos)
    && !s'.Fail?
    // Clear the pointer, return the stub.
    && s' == s
      .(table := s.table[pos := Some(Info(s.table[pos].value.entry, Free))])
      .(insert_capacity := s.insert_capacity + 1)
      .(stubs := s.stubs + multiset{Stub(s.table[pos].value.state.rid, MapIfc.RemoveOutput(true))})
  }

  // Query

  predicate ProcessQueryTicket(s: Variables, s': Variables, query_ticket: Ticket)
  {
    && !s.Fail?
    && query_ticket.input.QueryInput?
    && query_ticket in s.tickets
    && var h: uint32 := hash(query_ticket.input.key);
    && 0 <= h as int < FixedSize()
    && s.table[h].Some?
    && s.table[h].value.state.Free?
    && s' == s
      .(tickets := s.tickets - multiset{query_ticket})
      .(table := s.table[h := Some(
          s.table[h].value.(state :=
            Querying(query_ticket.rid, query_ticket.input.key)))])
  }

  function NextPos(pos: nat) : nat {
    if pos < FixedSize() - 1 then pos + 1 else 0
  }

  predicate QuerySkipEnabled(s: Variables, pos: nat)
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

  predicate QuerySkip(s: Variables, s': Variables, pos: nat)
  {
    && QuerySkipEnabled(s, pos)

    && s' == s.(table := s.table
        [pos := Some(s.table[pos].value.(state := Free))]
        [NextPos(pos) := Some(s.table[NextPos(pos)].value.(state := s.table[pos].value.state))])
  }

  predicate QueryDone(s: Variables, s': Variables, pos: nat)
  {
    && !s.Fail?
    && 0 <= pos < FixedSize()
    && s.table[pos].Some?
    && s.table[pos].value.state.Querying?
    && s.table[pos].value.entry.Full?
    && s.table[pos].value.state.key == s.table[pos].value.entry.kv.key
    && var stub := Stub(s.table[pos].value.state.rid, MapIfc.QueryOutput(Found(s.table[pos].value.entry.kv.val)));
    && s' == s
      .(table := s.table[pos := Some(s.table[pos].value.(state := Free))])
      .(stubs := s.stubs + multiset{stub})
  }

  predicate QueryNotFound(s: Variables, s': Variables, pos: nat)
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
    && s' == s
      .(table := s.table
        [pos := Some(s.table[pos].value.(state := Free))])
      .(stubs := s.stubs + multiset{
        Stub(s.table[pos].value.state.rid, MapIfc.QueryOutput(NotFound))
       })
  }

  predicate QueryFullHashTable(s: Variables, s': Variables, pos: nat)
  {
    && QuerySkipEnabled(s, pos)

    // And we've gone in an entire circle; another step would put us
    // back where we entered the hash table.
    && NextPos(pos) == hash(s.table[pos].value.state.key) as int

    && s' == s
      .(table := s.table
        [pos := Some(s.table[pos].value.(state := Free))])
      .(stubs := s.stubs + multiset{
        Stub(s.table[pos].value.state.rid, MapIfc.QueryOutput(NotFound))
       })
  }

  predicate NextStep(s: Variables, s': Variables, step: Step)
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

  predicate Next(s: Variables, s': Variables) {
    exists step :: NextStep(s, s', step)
  }

  function InfoQuantity(s: Option<Info>) : nat {
    if s.None? then 0 else (
      (if s.value.state.Inserting? then 1 else 0) +
      (if s.value.state.RemoveTidying? || s.value.entry.Full? then 1 else 0)
    )
  }

  function {:opaque} TableQuantity(s: seq<Option<Info>>) : nat {
    if s == [] then 0 else TableQuantity(s[..|s|-1]) + InfoQuantity(s[|s| - 1])
  }

  predicate TableQuantityInv(s: Variables)
  {
    && s.Variables?
    && TableQuantity(s.table) + s.insert_capacity == Capacity()
  }

  predicate Valid(s: Variables) {
    && s.Variables?
    && exists t :: Inv(add(s, t))
  }

  lemma valid_monotonic(x: Variables, y: Variables)
  //requires Valid(add(x, y))
  ensures Valid(x)
  {
    var xy' :| TableQuantityInv(add(add(x, y), xy'));
    associative(x, y, xy');
    assert TableQuantityInv(add(x, add(y, xy')));
  }

  lemma update_monotonic(x: Variables, y: Variables, z: Variables)
  //requires Next(x, y)
  //requires Valid(add(x, z))
  ensures Next(add(x, z), add(y, z))
  {
    var step :| NextStep(x, y, step);
    assert NextStep(add(x, z), add(y, z), step);
  }

  function input_ticket(id: int, input: Ifc.Input) : Variables
  {
    unit().(tickets := multiset{Ticket(id, input)})
  }

  function output_stub(id: int, output: Ifc.Output) : Variables
  {
    unit().(stubs := multiset{Stub(id, output)})
  }

  lemma NewTicketPreservesValid(r: Variables, id: int, input: Ifc.Input)
  //requires Valid(r)
  ensures Valid(add(r, input_ticket(id, input)))
  {
    var r' :| TableQuantityInv(add(r, r'));
    var out_r := add(r, input_ticket(id, input));
    assert out_r.table == r.table by { reveal_TableQuantity(); }
    assert add(out_r, r').table == add(r, r').table by { reveal_TableQuantity(); }
  }

  lemma EmptyTableQuantityIsZero(infos: seq<Option<Info>>)
    requires (forall i | 0 <= i < |infos| :: infos[i] == Some(Info(Empty, Free)))
    ensures TableQuantity(infos) == 0
  {
    reveal_TableQuantity();
  }

  lemma InitImpliesValid(s: Variables)
  //requires Init(s)
  //ensures Valid(s)
  {
    reveal_TableQuantity();
    EmptyTableQuantityIsZero(s.table);
    add_unit(s);
    assert TableQuantityInv(add(s, unit()));
  }

  lemma TableQuantityDistributive(xs: seq<Option<Info>>, ys: seq<Option<Info>>)
    ensures TableQuantity(xs + ys) == TableQuantity(xs) + TableQuantity(ys)
  {
    reveal_TableQuantity();
    if |ys| == 0 {
      assert xs + ys == xs;
    } else {
      var zs := xs + ys;
      var zs', z := zs[..|zs| - 1], zs[ |zs| - 1];
      var ys', y := ys[..|ys| - 1], ys[ |ys| - 1];

      calc {
        TableQuantity(zs);
        TableQuantity(zs') + InfoQuantity(z);
        TableQuantity(zs') + InfoQuantity(y);
          { assert zs' == xs + ys'; }
        TableQuantity(xs + ys') + InfoQuantity(y);
          { TableQuantityDistributive(xs, ys'); }
        TableQuantity(xs) +  TableQuantity(ys') + InfoQuantity(y);
        TableQuantity(xs) +  TableQuantity(ys);
      }
    }
  }

  lemma ResourceTableQuantityDistributive(x: Variables, y: Variables)
    requires add(x, y).Variables?
    ensures TableQuantity(add(x, y).table) == TableQuantity(x.table) + TableQuantity(y.table)
  {
    reveal_TableQuantity();
    var t := fuse_seq(x.table, y.table);
    var i := 0;
    while i < |x.table|
      invariant i <= |x.table|
      invariant TableQuantity(t[..i]) == TableQuantity(x.table[..i]) + TableQuantity(y.table[..i])
    {
      calc {
        TableQuantity(t[..i+1]);
        {
          assert t[..i] + t[i..i+1] == t[..i+1];
          TableQuantityDistributive(t[..i], t[i..i+1]); 
        }
        TableQuantity(t[..i]) + TableQuantity(t[i..i+1]);
        TableQuantity(x.table[..i]) + TableQuantity(y.table[..i]) + TableQuantity(t[i..i+1]);
        {
          assert TableQuantity(t[i..i+1]) == TableQuantity(x.table[i..i+1]) + TableQuantity(y.table[i..i+1]);
        }
        TableQuantity(x.table[..i]) + TableQuantity(y.table[..i]) + TableQuantity(x.table[i..i+1]) + TableQuantity(y.table[i..i+1]);
        {
          assert x.table[..i] + x.table[i..i+1] == x.table[..i+1];
          TableQuantityDistributive(x.table[..i], x.table[i..i+1]); 
        }
        TableQuantity(x.table[..i+1]) + TableQuantity(y.table[..i]) + TableQuantity(y.table[i..i+1]);
        {
          assert y.table[..i] + y.table[i..i+1] == y.table[..i+1];
          TableQuantityDistributive(y.table[..i], y.table[i..i+1]); 
        }
        TableQuantity(x.table[..i+1]) + TableQuantity(y.table[..i+1]);
      }
      i := i + 1;
    }
    assert t[..i] == add(x, y).table;
    assert x.table[..i] == x.table;
    assert y.table[..i] == y.table;
  }

  lemma ExtraResourcesNeverHurtNobody(s: Variables, s': Variables, t: Variables)
    requires Next(s, s')
    requires add(s,t).Variables?
    requires add(s',t).Variables?
    ensures Next(add(s,t), add(s',t))
  {
  }

  lemma NextPreservesValid(s: Variables, s': Variables)
  //requires Next(s, s')
  //requires Valid(s)
  ensures Valid(s')
  {
    var t :| Inv(add(s, t));
    assert Next(s, s');
    //assert Next(t, t);
    ExtraResourcesNeverHurtNobody(s, s', t);
    assert Next(add(s,t), add(s',t));
    Next_PreservesInv(add(s, t), add(s', t));
    assert Inv(add(s', t));
  }

  glinear method easy_transform(
      glinear b: Variables,
      ghost expected_out: Variables)
  returns (glinear c: Variables)
  requires Next(b, expected_out)
  ensures c == expected_out
  // travis promises to supply this

  // Reduce boilerplate by letting caller provide explicit step, which triggers a quantifier for generic Next()
  glinear method easy_transform_step(
      glinear b: Variables,
      ghost expected_out: Variables,
      ghost step: Step)
  returns (glinear c: Variables)
  requires NextStep(b, expected_out, step) 
  ensures c == expected_out
  {
    c := easy_transform(b, expected_out);
  }
}
