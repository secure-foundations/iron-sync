include "NRSpec.s.dfy"

module NRSimple(nrifc: NRIfc) refines StateMachine(AsyncIfc(nrifc)) {
  import opened RequestIds

  datatype ReadReq =
    | ReadInit( op: nrifc.ReadonlyOp)
    | ReadReq(ctail_at_start: nat, op: nrifc.ReadonlyOp)

  // TODO: maybe remove ret, compute ret instead of storing it here
  datatype UpdateResp = UpdateResp(idx_in_log: nat)

  datatype Variables = Variables(
    log: seq<nrifc.UpdateOp>,
    ctail: nat,
    readonly_reqs: map<RequestId, ReadReq>,
    update_reqs: map<RequestId, nrifc.UpdateOp>,
    update_resps: map<RequestId, UpdateResp>
  )

  predicate Init(s: Variables)
  {
    && s == Variables([], 0, map[], map[], map[])
  }

  // Given a log of ops and a version number, compute the state at that version
  function state_at_version(log: seq<nrifc.UpdateOp>, version: nat) : nrifc.NRState
  requires 0 <= version <= |log|
  {
    if version == 0 then
      nrifc.init_state()
    else
      nrifc.update(state_at_version(log, version - 1), log[version-1]).new_state
  }

  // ctail can increase at any moment

  predicate IncreaseCtail(s: Variables, s': Variables, new_ctail: nat)
  {
    && s.ctail <= new_ctail <= |s.log|
    && s' == s.(ctail := new_ctail)
  }

  // When a 'readonly' request begins record the ctail.
  // When it ends, we must return the answer at some version >= the recorded value.

  // Should correspond to point where we insert a ticket...
  predicate StartReadonly(s: Variables, s': Variables, rid: RequestId, op: nrifc.ReadonlyOp)
  {
    && rid !in s.update_reqs
    && rid !in s.update_resps
    && rid !in s.readonly_reqs
    && s' == s.(readonly_reqs := s.readonly_reqs[rid := ReadInit(op)])
  }

  predicate ReadCtail(s: Variables, s': Variables, rid: RequestId)
  {
    && rid in s.readonly_reqs
    && s.readonly_reqs[rid].ReadInit?
    && var op := s.readonly_reqs[rid].op;
    && s' == s.(readonly_reqs := s.readonly_reqs[rid := ReadReq(s.ctail, op)])
  }

  predicate FinishReadonly(s: Variables, s': Variables,
      rid: RequestId, version: nat, return_value: nrifc.ReturnType)
  {
    && rid in s.readonly_reqs
    && s.readonly_reqs[rid].ReadReq?
    && s.readonly_reqs[rid].ctail_at_start <= version <= |s.log|
    && version <= s.ctail
    && s' == s.(readonly_reqs := s.readonly_reqs - {rid})
    && return_value == nrifc.read(state_at_version(s.log, version), s.readonly_reqs[rid].op)
  }

  // For an 'update' request, we put it in the log at some point (giving the total
  // order on updates). However, to complete, the ctail must be > the index where we
  // put the op

  predicate StartUpdate(s: Variables, s': Variables, rid: RequestId, op: nrifc.UpdateOp)
  {
    && rid !in s.update_reqs
    && rid !in s.update_resps
    && rid !in s.readonly_reqs
    && s' == s.(update_reqs := s.update_reqs[rid := op])
  }




  function {:opaque} map_filter<K(!new), V>(m: map<K, V>, filter: seq<K>): map<K, V>
    ensures forall rid | rid in filter :: rid !in map_filter(m, filter)
  {
    map k | k in m.Keys && k !in filter :: m[k]
  }

  // combines two maps
  function {:opaque} map_update<K(!new), V>(m1: map<K, V>, m2: map<K, V>): map<K, V>
    ensures forall k | k in (m1.Keys + m2.Keys) :: k in map_update(m1, m2)
  {
    map k | k in (m1.Keys + m2.Keys) :: if k in m2 then m2[k] else m1[k]
  }

    // all elements in the sequence are unique
  predicate seq_unique<V>(rids: seq<V>) {
    forall i, j | 0 <= i < |rids| && 0 <= j < |rids| && i != j :: rids[i] != rids[j]
  }

  // predicate that the request ids are valid
  predicate RequestIdsValid(request_ids: seq<RequestId>, update_reqs: map<RequestId, nrifc.UpdateOp>)
  {
    forall rid | rid in request_ids :: rid in update_reqs
  }

  // construct the new log entries
  function ConstructNewLogEntries(request_ids: seq<RequestId>, update_reqs: map<RequestId, nrifc.UpdateOp>) : seq<nrifc.UpdateOp>
    requires RequestIdsValid(request_ids, update_reqs)
  {
    seq(|request_ids|, rid requires 0 <= rid < |request_ids| => update_reqs[request_ids[rid]])
  }

  // update the responses
  function ConstructUpdateResponses(request_ids: seq<RequestId>, idx : nat) : ( res: map<RequestId, UpdateResp>)
    ensures forall r | r in res ::res[r].idx_in_log < idx + |request_ids|
    ensures forall r | r in res ::res[r].idx_in_log >= idx
  {
    if request_ids == [] then
      map[]
    else
      ConstructUpdateResponses(request_ids[1..], idx + 1)[ request_ids[0] :=  UpdateResp(idx)]
  }


  lemma ConstructUpdateResponses_in_map(rids: seq<RequestId>, idx : nat, res: map<RequestId, UpdateResp>)
    requires seq_unique(rids)
    requires res == ConstructUpdateResponses(rids, idx)
    ensures forall r | r in rids :: r in res
    ensures forall r | r in res :: r in rids
    ensures forall r | r in res ::res[r].idx_in_log < idx + |rids|
    ensures forall r | r in res ::res[r].idx_in_log >= idx
    ensures forall i | 0 <= i < |rids| :: res[rids[i]].idx_in_log == idx + i
    decreases |rids|
  {
     if rids != [] {
       ConstructUpdateResponses_in_map(rids[1..], idx + 1, ConstructUpdateResponses(rids[1..], idx + 1));
     }
  }

  predicate AddUpdateToLog(s: Variables, s': Variables,  request_ids: seq<RequestId>)
  {
    && seq_unique(request_ids)
    && RequestIdsValid(request_ids, s.update_reqs)
    // construct the new log entries
    && var new_log_entries := ConstructNewLogEntries(request_ids, s.update_reqs);

    // construct the responses
    && var new_responses := ConstructUpdateResponses(request_ids, |s.log|);

    // update the state
    && s' == s.(log := s.log + new_log_entries)
              .(update_reqs := map_filter(s.update_reqs, request_ids))
              .(update_resps := map_update(s.update_resps, new_responses))
  }

  predicate EndUpdate(s: Variables, s': Variables,
      rid: RequestId, return_value: nrifc.ReturnType)
  {
    && rid in s.update_resps
    && var idx := s.update_resps[rid].idx_in_log;
    && s.ctail > idx
    && idx < |s.log|
    && s' == s.(update_resps := s.update_resps - {rid})
    && return_value == nrifc.update(state_at_version(s.log, idx), s.log[idx]).return_value
  }


  // the stepping throug the state machine

  datatype Step =
    | StartUpdate_Step(rid: RequestId, uop: nrifc.UpdateOp)
    | AddUpdateToLog_Step(request_ids: seq<RequestId>)
    | EndUpdate_Step(rid: RequestId, return_value: nrifc.ReturnType)
    | IncreaseCtail_Step(new_ctail: nat)
    | StartReadonly_Step(rid: RequestId, rop: nrifc.ReadonlyOp)
    | ReadCtail_Step(rid: RequestId)
    | FinishReadonly_Step(rid: RequestId, version: nat, return_value: nrifc.ReturnType)
    | Stutter_Step

  predicate NextStep(s: Variables, s': Variables, op: ifc.Op, step: Step) {
    match step {
      case StartUpdate_Step(rid: RequestId, update_op: nrifc.UpdateOp) =>
          && op == ifc.Start(rid, nrifc.UOp(update_op))
          && StartUpdate(s, s', rid, update_op)

      case AddUpdateToLog_Step(request_ids: seq<RequestId>) =>
          && op == ifc.InternalOp
          && AddUpdateToLog(s, s', request_ids)

      case EndUpdate_Step(rid: RequestId, return_value: nrifc.ReturnType) =>
          && op == ifc.End(rid, return_value)
          && EndUpdate(s, s', rid, return_value)

      case IncreaseCtail_Step(new_ctail: nat) =>
          && op == ifc.InternalOp
          && IncreaseCtail(s, s', new_ctail)

      case ReadCtail_Step(rid: RequestId) =>
          && op == ifc.InternalOp
          && ReadCtail(s, s', rid)

      case StartReadonly_Step(rid: RequestId, read_op: nrifc.ReadonlyOp) =>
          && op == ifc.Start(rid, nrifc.ROp(read_op))
          && StartReadonly(s, s', rid, read_op)

      case FinishReadonly_Step(rid: RequestId, version: nat, return_value: nrifc.ReturnType) =>
          && op == ifc.End(rid, return_value)
          && FinishReadonly(s, s', rid, version, return_value)

      case Stutter_Step =>
          && op == ifc.InternalOp
          && s' == s
    }
  }

  predicate Next(s: Variables, s': Variables, op: ifc.Op) {
    exists step :: NextStep(s, s', op, step)
  }

  // invariant
  predicate Inv(s: Variables) {
    && s.ctail <= |s.log|
    && (forall r | r in s.update_resps :: s.update_resps[r].idx_in_log < |s.log|)
    && (forall r | r in s.readonly_reqs && s.readonly_reqs[r].ReadReq? :: s.readonly_reqs[r].ctail_at_start <= s.ctail)
    && (forall r | r in s.readonly_reqs && s.readonly_reqs[r].ReadReq? :: s.readonly_reqs[r].ctail_at_start <= |s.log|)

  }


  lemma IncreaseCtail_PreservesInv(s: Variables, s': Variables, new_ctail: nat)
    requires Inv(s)
    requires IncreaseCtail(s, s', new_ctail)
    ensures Inv(s')
  {

  }


  lemma ReadCtail_PreservesInv(s: Variables, s': Variables, rid: RequestId)
    requires Inv(s)
    requires ReadCtail(s, s', rid)
    ensures Inv(s')
  {

  }

  lemma StartReadonly_PreservesInv(s: Variables, s': Variables, rid: RequestId, op: nrifc.ReadonlyOp)
    requires Inv(s)
    requires StartReadonly(s, s', rid, op)
    ensures Inv(s')
  {

  }

  lemma FinishReadonly_PreservesInv(s: Variables, s': Variables,
      rid: RequestId, version: nat, return_value: nrifc.ReturnType)
    requires Inv(s)
    requires FinishReadonly(s, s', rid, version, return_value)
    ensures Inv(s')
  {

  }

  lemma StartUpdate_PreservesInv(s: Variables, s': Variables, rid: RequestId, op: nrifc.UpdateOp)
    requires Inv(s)
    requires StartUpdate(s, s', rid, op)
    ensures Inv(s')
  {

  }

  lemma AddUpdateToLog_PreservesInv(s: Variables, s': Variables, rid: seq<RequestId>)
    requires Inv(s)
    requires AddUpdateToLog(s, s', rid)
    ensures Inv(s')
  {
    reveal_map_update();
  }

  lemma EndUpdate_PreservesInv(s: Variables, s': Variables, rid: RequestId, return_value: nrifc.ReturnType)
    requires Inv(s)
    requires EndUpdate(s, s', rid, return_value)
    ensures Inv(s')
  {

  }

  lemma NextStep_PreservesInv(s: Variables, s': Variables, op: ifc.Op, step: Step)
    requires Inv(s)
    requires NextStep(s, s', op, step)
    ensures Inv(s')
  {
    match step {
      case StartUpdate_Step(rid: RequestId, op: nrifc.UpdateOp) => StartUpdate_PreservesInv(s, s', rid, op);
      case AddUpdateToLog_Step(rid: seq<RequestId>) => AddUpdateToLog_PreservesInv(s, s', rid);
      case EndUpdate_Step(rid: RequestId, return_value: nrifc.ReturnType) => EndUpdate_PreservesInv(s, s', rid, return_value);
      case IncreaseCtail_Step(new_ctail: nat) => IncreaseCtail_PreservesInv(s, s', new_ctail);
      case StartReadonly_Step(rid: RequestId, op: nrifc.ReadonlyOp) => StartReadonly_PreservesInv(s, s', rid, op);
      case ReadCtail_Step(rid: RequestId) => ReadCtail_PreservesInv(s, s', rid);
      case FinishReadonly_Step(rid: RequestId, version: nat, return_value: nrifc.ReturnType) => FinishReadonly_PreservesInv(s, s', rid, version, return_value);
      case Stutter_Step => { }
    }
  }

  lemma Next_Implies_inv(s: Variables, s': Variables, op: ifc.Op)
    requires Inv(s)
    requires Next(s, s', op)
    ensures Inv(s')
  {
    var step :| NextStep(s, s', op, step);
    NextStep_PreservesInv(s, s', op, step);
  }

  /// invariance proofs
  lemma Init_Implies_Inv(s: Variables)
    requires Init(s)
    ensures Inv(s)
  {

  }
}
