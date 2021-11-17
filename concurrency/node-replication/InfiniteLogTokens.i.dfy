include "InfiniteLog.i.dfy"
include "Constants.i.dfy"
include "../framework/GlinearMap.s.dfy"
include "../framework/Ptrs.s.dfy"

module InfiniteLogTokens(nrifc: NRIfc) {
  import opened RequestIds
  import opened Options
  import opened IL = InfiniteLogSSM(nrifc)
  import opened GhostLoc
  import opened ILT = TicketStubToken(nrifc, IL)
  import opened Constants
  import opened GlinearMap
  import opened Ptrs

  function loc() : Loc // XXX TODO(travis)

  /////////////////////
  // Token types. These represent the smallest discrete parts of the InfiniteLog state.
  // This is a way of dividing up the state into the pieces it will be convenient to
  // manipulate in our program.

  datatype {:glinear_fold} Readonly = Readonly(ghost rid: RequestId, ghost rs: ReadonlyState)
  {
    function defn(): ILT.Token {
      ILT.Tokens.Token(loc(),
        M(map[], None, map[], map[], None, map[rid := rs], map[], map[])
      )
    }
  }

  datatype {:glinear_fold} Update = Update(ghost rid: RequestId, ghost us: UpdateState)
  {
    function defn(): ILT.Token {
      ILT.Tokens.Token(loc(),
        M(map[], None, map[], map[], None, map[], map[rid := us], map[])
      )
    }
  }

  datatype {:glinear_fold} Ctail = Ctail(ghost ctail: nat)
  {
    function defn(): ILT.Token {
      ILT.Tokens.Token(loc(),
        M(map[], None, map[], map[], Some(ctail), map[], map[], map[])
      )
    }
  }

  datatype {:glinear_fold} LocalTail = LocalTail(ghost nodeId: nat, ghost localTail: nat)
  {
    function defn(): ILT.Token {
      ILT.Tokens.Token(loc(),
        M(map[], None, map[], map[nodeId := localTail], None, map[], map[], map[])
      )
    }
  }

  datatype {:glinear_fold} GlobalTail = GlobalTail(ghost tail: nat)
  {
    function defn(): ILT.Token {
      ILT.Tokens.Token(loc(),
        M(map[], Some(tail), map[], map[], None, map[], map[], map[])
      )
    }
  }

  datatype {:glinear_fold} Replica = Replica(ghost nodeId: nat, ghost state: nrifc.NRState)
  {
    function defn(): ILT.Token {
      ILT.Tokens.Token(loc(),
        M(map[], None, map[nodeId := state], map[], None, map[], map[], map[])
      )
    }
  }

  datatype {:glinear_fold} CombinerToken = CombinerToken(ghost nodeId: nat, ghost state: CombinerState)
  {
    function defn(): ILT.Token {
      ILT.Tokens.Token(loc(),
        M(map[], None, map[], map[], None, map[], map[], map[nodeId := state])
      )
    }
  }

  datatype {:glinear_fold} Log = Log(ghost idx: nat, ghost op: nrifc.UpdateOp, ghost node_id: nat)
  {
    function defn(): ILT.Token {
      ILT.Tokens.Token(loc(),
        M(map[idx := LogEntry(op, node_id)], None, map[], map[], None, map[], map[], map[])
      )
    }
  }

  /////////////////////
  // The transitions.
  // These let us transform ghost state into other ghost state to represent
  // InfiniteLog transitions.

  // This lets us perform the transition
  //
  //    Readonly(rid, ReadonlyInit(op))         , Ctail(ctail)
  //      -->
  //    Readonly(rid, ReadonlyCtail(op, ctail)) , Ctail(ctail)
  //
  // which is effectively the `TransitionReadonlyReadCtail` transition.
  //
  // Note that it takes a `glinear` Readonly object and returns a new `glinear` Readonly
  // object. Since we only read from `ctail`, we don't need to update it, so we pass in
  // a `gshared` Ctail object. (This can be thought of a a readonly borrowed reference
  // to the Ctail object).

  glinear method perform_TransitionReadonlyReadCtail(
      glinear readonly: Readonly,
      gshared ctail: Ctail)
  returns (glinear readonly': Readonly)
  requires readonly.rs.ReadonlyInit?
  ensures readonly' == Readonly(readonly.rid, ReadonlyCtail(readonly.rs.op, ctail.ctail))
  {
    // Unfold the inputs to get the raw tokens as defined by the `defn` functions.
    // (These are glinear methods auto-generated by the {:glinear_fold} attribute.)
    glinear var a_token := Readonly_unfold(readonly);
    gshared var s_token := Ctail_unfold_borrow(ctail); // use `borrow` for `gshared` types.

    // Compute the things we want to output (as ghost, _not_ glinear constructs)
    ghost var out_expect := Readonly(readonly.rid, ReadonlyCtail(readonly.rs.op, ctail.ctail));
    ghost var out_token_expect := Readonly_unfold(out_expect);

    // Explain what transition we're going to do
    assert IL.NextStep(
        IL.dot(s_token.val, a_token.val),
        IL.dot(s_token.val, out_token_expect.val),
        TransitionReadonlyReadCtail_Step(readonly.rid));

    // Perform the transition
    // 1_1_1 indicates:
    //    1 shared input (b)
    //    1 linear input (a)
    //    1 linear output (o)
    glinear var out_token := ILT.transition_1_1_1(s_token, a_token, out_token_expect.val);

    // Fold the raw token into the Readonly datatype
    // Readonly_fold is another auto-generated glinear method.
    readonly' := Readonly_fold(out_expect, out_token);
  }

  //    Readonly(rid, ReadonlyCtail(op, ctail))               , LocalTail(nodeId, ltail)
  //      -->
  //    Readonly(rid, ReadonlyReadyToRead(op, nodeId, ctail)) , LocalTail(nodeId, ltail)

  glinear method perform_TransitionReadonlyReadyToRead(
      glinear ticket: Readonly,
      gshared ltail: LocalTail)
  returns (glinear ticket': Readonly)
  requires ticket.rs.ReadonlyCtail?
  requires ltail.localTail >= ticket.rs.ctail
  ensures ticket' == Readonly(ticket.rid,
      ReadonlyReadyToRead(ticket.rs.op, ltail.nodeId, ticket.rs.ctail))
  {
    // Unfold the inputs to get the raw tokens as defined by the `defn` functions.
    // (These are glinear methods auto-generated by the {:glinear_fold} attribute.)
    glinear var a_token := Readonly_unfold(ticket);
    gshared var s_token := LocalTail_unfold_borrow(ltail); // use `borrow` for `gshared` types.

    // Compute the things we want to output (as ghost, _not_ glinear constructs)
    //     | ReadonlyReadyToRead(op: nrifc.ReadonlyOp, nodeId: nat, ctail: nat)

    ghost var out_expect := Readonly(ticket.rid, ReadonlyReadyToRead(ticket.rs.op, ltail.nodeId, ticket.rs.ctail));
    ghost var out_token_expect := Readonly_unfold(out_expect);

    // Explain what transition we're going to do
    assert IL.TransitionReadonlyReadyToRead(
        IL.dot(s_token.val, a_token.val),
        IL.dot(s_token.val, out_token_expect.val),
        ltail.nodeId, ticket.rid);
    assert IL.NextStep(
        IL.dot(s_token.val, a_token.val),
        IL.dot(s_token.val, out_token_expect.val),
        TransitionReadonlyReadyToRead_Step(ltail.nodeId, ticket.rid));

    // Perform the transition
    // 1_1_1 indicates:
    //    1 shared input (b)
    //    1 linear input (a)
    //    1 linear output (o)
    glinear var out_token := ILT.transition_1_1_1(s_token, a_token, out_token_expect.val);

    // Fold the raw token into the Readonly datatype
    // Readonly_fold is another auto-generated glinear method.
    ticket' := Readonly_fold(out_expect, out_token);
  }

  //    Readonly(rid, ReadonlyReadyToRead(op, nodeId, ctail)) , Replica(nodeId, state)
  //      -->
  //    Readonly(rid, ReadonlyDone(ret))                      , Replica(nodeId, state)

  glinear method sharedReplicaComb(
      gshared replica: Replica,
      gshared comb: CombinerToken)
  returns (gshared rc: ILT.Token)
  ensures rc.loc == loc()
  ensures rc.val == IL.dot(replica.defn().val, comb.defn().val)

  glinear method perform_ReadonlyDone(
      glinear readonly: Readonly,
      gshared replica: Replica,
      gshared comb: CombinerToken)
  returns (glinear readonly': Readonly)
  requires readonly.rs.ReadonlyReadyToRead?
  requires replica.nodeId == readonly.rs.nodeId == comb.nodeId
  requires comb.state.CombinerReady?
  ensures readonly'.rs.ReadonlyDone?
  ensures readonly'.rs.ret == nrifc.read(replica.state, readonly.rs.op)
  ensures readonly' == Readonly(readonly.rid,
      ReadonlyDone(readonly.rs.op, nrifc.read(replica.state, readonly.rs.op), readonly.rs.nodeId, readonly.rs.ctail))
  {
    // Unfold the inputs to get the raw tokens as defined by the `defn` functions.
    // (These are glinear methods auto-generated by the {:glinear_fold} attribute.)
    glinear var a_token := Readonly_unfold(readonly);
    gshared var s_token := sharedReplicaComb(replica, comb);

    ghost var out_expect := Readonly(readonly.rid,
      ReadonlyDone(readonly.rs.op, nrifc.read(replica.state, readonly.rs.op), readonly.rs.nodeId, readonly.rs.ctail));
    ghost var out_token_expect := Readonly_unfold(out_expect);

    // Explain what transition we're going to do
    assert IL.TransitionReadonlyDone(
        IL.dot(s_token.val, a_token.val),
        IL.dot(s_token.val, out_token_expect.val),
        replica.nodeId, readonly.rid);
    assert IL.NextStep(
        IL.dot(s_token.val, a_token.val),
        IL.dot(s_token.val, out_token_expect.val),
        TransitionReadonlyDone_Step(replica.nodeId, readonly.rid));

    glinear var out_token := ILT.transition_1_1_1(s_token, a_token, out_token_expect.val);

    readonly' := Readonly_fold(out_expect, out_token);
  }

  glinear method perform_TrivialStartCombining(
      glinear combiner: CombinerToken)
  returns (
      glinear combiner': CombinerToken
  )
  requires combiner.state.CombinerReady?
  ensures combiner' == CombinerToken(combiner.nodeId, CombinerPlaced([]))
  {
    glinear var a_token := CombinerToken_unfold(combiner);

    ghost var out_expect := CombinerToken(combiner.nodeId, CombinerPlaced([]));
    ghost var out_token_expect := CombinerToken_unfold(out_expect);

    assert IL.TrivialStart(
        a_token.val,
        out_token_expect.val,
        combiner.nodeId);
    assert IL.NextStep(
        a_token.val,
        out_token_expect.val,
        TrivialStart_Step(combiner.nodeId));

    glinear var out_token := ILT.transition_1_1(a_token, out_token_expect.val);

    combiner' := CombinerToken_fold(out_expect, out_token);
  }

  glinear method mapUpdate_to_raw(ghost requestIds: seq<nat>, glinear updates: map<nat, Update>)
  returns (glinear raw: ILT.Token)
  requires forall i | 0 <= i < |requestIds| ::
      i in updates && updates[i].rid == requestIds[i]
  ensures raw.loc == loc()
  ensures raw.val.M?
  ensures forall i | 0 <= i < |requestIds| ::
      requestIds[i] in raw.val.localUpdates
      && raw.val.localUpdates[requestIds[i]] == updates[i].us
  ensures seq_unique(requestIds)
  ensures raw.val.global_tail.None?
  ensures raw.val.combiner == map[]
  {
    glinear var updates' := updates;
    raw := ILT.Tokens.get_unit(loc());
    ghost var j := 0;
    while j < |requestIds|
    invariant 0 <= j <= |requestIds|
    invariant forall i | j <= i < |requestIds| ::
        i in updates' && updates'[i] == updates[i]
    invariant raw.val.M?
    invariant raw.loc == loc()
    invariant forall i | 0 <= i < j ::
        requestIds[i] in raw.val.localUpdates
        && raw.val.localUpdates[requestIds[i]] == updates[i].us
    invariant raw.val.global_tail.None?
    invariant raw.val.combiner == map[]
    invariant forall i, k | 0 <= i < j && 0 <= k < j && i != k :: requestIds[i] != requestIds[k]
    {
      glinear var upd;
      updates', upd := glmap_take(updates', j);
      glinear var u := Update_unfold(upd);
      raw := ILT.Tokens.join(raw, u);

      j := j + 1;
    }
    dispose_anything(updates');
  }

  glinear method raw_to_mapUpdate(ghost requestIds: seq<nat>, glinear raw: ILT.Token)
  returns (glinear raw': ILT.Token, glinear updates: map<nat, Update>)
  requires raw.loc == loc()
  requires raw.val.M?
  requires forall i | 0 <= i < |requestIds| ::
      requestIds[i] in raw.val.localUpdates
  requires seq_unique(requestIds)
  ensures forall i | 0 <= i < |requestIds| ::
      i in updates && updates[i].rid == requestIds[i]
      && raw.val.localUpdates[requestIds[i]] == updates[i].us
  ensures raw'.val.M?
  ensures raw'.loc == raw.loc && raw'.val.log == raw.val.log
  {
    raw' := raw;
    updates := glmap_empty();
    ghost var j := 0;
    while j < |requestIds|
    invariant raw'.loc == loc()
    invariant raw'.val.M?
    invariant forall i | j <= i < |requestIds| ::
        && requestIds[i] in raw'.val.localUpdates
        && raw'.val.localUpdates[requestIds[i]] == raw.val.localUpdates[requestIds[i]]
    invariant 0 <= j <= |requestIds|
    invariant forall i | 0 <= i < j ::
        i in updates && updates[i].rid == requestIds[i]
        && raw.val.localUpdates[requestIds[i]] == updates[i].us
    invariant raw'.val.M?
    invariant raw'.loc == raw.loc && raw'.val.log == raw.val.log
    {
      var expected_upd := Update(requestIds[j], 
          raw.val.localUpdates[requestIds[j]]);
      var x := expected_upd.defn().val;
      var y := raw'.val.(localUpdates := raw'.val.localUpdates - {requestIds[j]});

      glinear var xl;
      raw', xl := ILT.Tokens.split(raw', y, x);

      glinear var upd := Update_fold(expected_upd, xl);
      updates := glmap_insert(updates, j, upd);

      j := j + 1;
    }
  }

  glinear method raw_to_mapLogs(
    ghost mlog: map<nat, LogEntry>,
    ghost requestIds: seq<nat>,
    ghost nodeId: nat,
    ghost gtail: nat,
    ghost localUpdates: map<RequestId, UpdateState>,
    ghost ops: seq<nrifc.UpdateOp>,
    glinear raw: ILT.Token)
  returns (glinear logs': map<nat, Log>)
  requires raw.val.M?
  requires raw.loc == loc()
  requires |ops| == |requestIds|
  requires forall i | 0 <= i < |requestIds| ::
      requestIds[i] in localUpdates && localUpdates[requestIds[i]] == UpdateInit(ops[i])
  requires raw.val.log == map_update(mlog,
      ConstructNewLogEntries(requestIds, nodeId, gtail, localUpdates))
  //requires seq_unique(request_ids)

  ensures forall i | 0 <= i < |requestIds| ::
      i in logs'
        && logs'[i] == Log(gtail + i, ops[i], nodeId)
  {
    glinear var raw' := raw;
    logs' := glmap_empty();
    ghost var j := 0;

    forall i | gtail <= i < gtail + |requestIds|
    ensures i in raw.val.log
    ensures i in raw'.val.log
    ensures raw.val.log[i] == raw.val.log[i]
    {
      ConstructNewLogEntries_Get(requestIds, nodeId, gtail, localUpdates, 
          i - gtail);
    }

    while j < |requestIds|
    invariant 0 <= j <= |requestIds|
    invariant raw'.val.M?
    invariant raw'.loc == loc()
    invariant |ops| == |requestIds|
    invariant forall i | 0 <= i < |requestIds| ::
        requestIds[i] in localUpdates && localUpdates[requestIds[i]] == UpdateInit(ops[i])
    invariant forall i | gtail + j <= i < gtail + |requestIds| ::
        && i in raw.val.log
        && i in raw'.val.log
        && raw'.val.log[i] == raw.val.log[i]

    invariant forall i | 0 <= i < j ::
        i in logs'
          && logs'[i] == Log(gtail + i, ops[i], nodeId)
    {
      var j' := gtail + j;
      var expected_log := Log(j', ops[j], nodeId);
      var x := expected_log.defn().val;
      var y := raw'.val.(log := raw'.val.log - {j'});

      ConstructNewLogEntries_Get(requestIds, nodeId, gtail, localUpdates, j);
      assert j' in raw'.val.log;
      assert raw'.val.log[j'].op == ops[j];
      assert raw'.val.log[j'].node_id == nodeId;
      assert raw'.val.log[j'] == LogEntry(ops[j], nodeId);

      glinear var xl;
      raw', xl := ILT.Tokens.split(raw', y, x);

      glinear var upd := Log_fold(expected_log, xl);
      logs' := glmap_insert(logs', j, upd);

      j := j + 1;
    }
    dispose_anything(raw');
  }

  glinear method perform_AdvanceTail(
      glinear tail: GlobalTail,
      glinear updates: map<nat, Update>,
      glinear combiner: CombinerToken,
      ghost ops: seq<nrifc.UpdateOp>,
      ghost requestIds: seq<RequestId>,
      ghost nodeId: nat)
  returns (
      glinear tail': GlobalTail,
      glinear updates': map<nat, Update>,
      glinear combiner': CombinerToken,
      glinear logs': map<nat, Log>
  )
  requires |ops| == |requestIds|
  requires forall i | 0 <= i < |requestIds| ::
      i in updates && updates[i] == Update(requestIds[i], UpdateInit(ops[i]))
  requires combiner.nodeId == nodeId
  requires combiner.state == CombinerReady
  ensures tail' == GlobalTail(tail.tail + |ops|)
  ensures forall i | 0 <= i < |requestIds| ::
      i in updates'
        && updates'[i].us.UpdatePlaced?
        && updates'[i] == Update(requestIds[i], UpdatePlaced(nodeId, updates'[i].us.idx))
  ensures forall i | 0 <= i < |requestIds| ::
      i in logs'
        && logs'[i] == Log(tail.tail + i, ops[i], nodeId)
  ensures combiner'.nodeId == nodeId
  ensures combiner'.state == CombinerPlaced(requestIds)
  {
    glinear var a_token := GlobalTail_unfold(tail);
    glinear var b_token := mapUpdate_to_raw(requestIds, updates);
    glinear var c_token := CombinerToken_unfold(combiner);

    // Compute the things we want to output (as ghost, _not_ glinear constructs)
    ghost var out1_expect := GlobalTail(tail.tail + |ops|);
    ghost var out1_token_expect := GlobalTail_unfold(out1_expect);

    ghost var m := b_token.val;
    var updated_log := ConstructNewLogEntries(requestIds, combiner.nodeId, tail.tail, m.localUpdates);
    var local_updates_new := ConstructLocalUpdateMap(requestIds, combiner.nodeId, tail.tail);
    ghost var m' := m
        .(log := map_update(m.log, updated_log))
        .(localUpdates := map_update(m.localUpdates, local_updates_new));
    ghost var out2_token_expect := ILT.Tokens.Token(loc(), m');

    ghost var out3_expect := CombinerToken(nodeId, CombinerPlaced(requestIds));
    ghost var out3_token_expect := CombinerToken_unfold(out3_expect);

    // Explain what transition we're going to do
    assert AdvanceTail(
        IL.dot(IL.dot(a_token.val, m), c_token.val),
        IL.dot(IL.dot(out1_token_expect.val, m'), out3_token_expect.val),
        combiner.nodeId, requestIds);
    assert IL.NextStep(
        IL.dot(IL.dot(a_token.val, m), c_token.val),
        IL.dot(IL.dot(out1_token_expect.val, m'), out3_token_expect.val),
        AdvanceTail_Step(combiner.nodeId, requestIds));

    // Perform the transition
    glinear var out1_token, out2_token, out3_token :=
      ILT.transition_3_3(a_token, b_token, c_token,
        out1_token_expect.val, m', out3_token_expect.val);

    tail' := GlobalTail_fold(out1_expect, out1_token);
    combiner' := CombinerToken_fold(out3_expect, out3_token);

    out2_token, updates' := raw_to_mapUpdate(requestIds, out2_token);
    logs' := raw_to_mapLogs(m.log, requestIds, combiner.nodeId, tail.tail, m.localUpdates,
          ops, out2_token);

    forall i | 0 <= i < |requestIds|
    ensures i in updates'
    ensures updates'[i].us.UpdatePlaced?
    ensures updates'[i] == Update(requestIds[i], UpdatePlaced(nodeId, updates'[i].us.idx))
    {
      reveal_ConstructLocalUpdateMap();
    }
  }

  glinear method perform_ExecLoadLtail(
      glinear combiner: CombinerToken,
      gshared ltail: LocalTail)
  returns (glinear combiner': CombinerToken)
  requires ltail.nodeId == combiner.nodeId
  requires combiner.state.CombinerPlaced?
  ensures combiner' == combiner.(state :=
      CombinerLtail(combiner.state.queued_ops, ltail.localTail))
  {
    glinear var a_token := CombinerToken_unfold(combiner);
    gshared var s_token := LocalTail_unfold_borrow(ltail);

    ghost var out_expect := combiner.(state := CombinerLtail(combiner.state.queued_ops, ltail.localTail));
    ghost var out_token_expect := CombinerToken_unfold(out_expect);

    assert IL.NextStep(
        IL.dot(s_token.val, a_token.val),
        IL.dot(s_token.val, out_token_expect.val),
        ExecLoadLtail_Step(ltail.nodeId));

    glinear var out_token := ILT.transition_1_1_1(s_token, a_token, out_token_expect.val);

    combiner' := CombinerToken_fold(out_expect, out_token);
  }

  glinear method perform_ExecLoadGlobalTail(
      glinear combiner: CombinerToken,
      gshared globalTail: GlobalTail)
  returns (glinear combiner': CombinerToken)
  requires combiner.state.CombinerLtail?
  ensures combiner' == combiner.(state :=
      Combiner(combiner.state.queued_ops, 0, combiner.state.localTail, globalTail.tail))
  ensures combiner'.state.globalTail >= combiner'.state.localTail // follows from state machine invariant
  {
    glinear var a_token := CombinerToken_unfold(combiner);
    gshared var s_token := GlobalTail_unfold_borrow(globalTail);

    ghost var out_expect := combiner.(state :=
      Combiner(combiner.state.queued_ops, 0, combiner.state.localTail, globalTail.tail));
    ghost var out_token_expect := CombinerToken_unfold(out_expect);

    assert IL.NextStep(
        IL.dot(s_token.val, a_token.val),
        IL.dot(s_token.val, out_token_expect.val),
        ExecLoadGlobalTail_Step(combiner.nodeId));

    glinear var out_token := ILT.transition_1_1_1(s_token, a_token, out_token_expect.val);

    var rest := ILT.obtain_invariant_1_1(s_token, inout out_token);

    combiner' := CombinerToken_fold(out_expect, out_token);
  }

  glinear method perform_UpdateCompletedTail(
      glinear combiner: CombinerToken,
      glinear ctail: Ctail)
  returns (glinear combiner': CombinerToken, glinear ctail': Ctail)
  requires combiner.state.Combiner?
  requires combiner.state.localTail == combiner.state.globalTail
  ensures combiner' == combiner.(state :=
      CombinerUpdatedCtail(combiner.state.queued_ops, combiner.state.localTail))
  ensures ctail' == Ctail(if ctail.ctail > combiner.state.localTail
      then ctail.ctail else combiner.state.localTail)
  {
    glinear var a_token := CombinerToken_unfold(combiner);
    glinear var b_token := Ctail_unfold(ctail);

    // Compute the things we want to output (as ghost, _not_ glinear constructs)
    ghost var out1_expect := combiner.(state :=
      CombinerUpdatedCtail(combiner.state.queued_ops, combiner.state.localTail));
    ghost var out1_token_expect := CombinerToken_unfold(out1_expect);

    ghost var out2_expect := Ctail(if ctail.ctail > combiner.state.localTail
      then ctail.ctail else combiner.state.localTail);
    ghost var out2_token_expect := Ctail_unfold(out2_expect);

    // Explain what transition we're going to do
    assert UpdateCompletedTail(
        IL.dot(a_token.val, b_token.val),
        IL.dot(out1_token_expect.val, out2_token_expect.val),
        combiner.nodeId);
    assert IL.NextStep(
        IL.dot(a_token.val, b_token.val),
        IL.dot(out1_token_expect.val, out2_token_expect.val),
        UpdateCompletedTail_Step(combiner.nodeId));

    // Perform the transition
    glinear var out1_token, out2_token := ILT.transition_2_2(a_token, b_token,
        out1_token_expect.val,
        out2_token_expect.val);

    combiner' := CombinerToken_fold(out1_expect, out1_token);
    ctail' := Ctail_fold(out2_expect, out2_token);
  }

  glinear method perform_GoToCombinerReady(
      glinear combiner: CombinerToken,
      glinear localTail: LocalTail)
  returns (glinear combiner': CombinerToken, glinear localTail': LocalTail)
  requires combiner.state.CombinerUpdatedCtail?
  requires combiner.nodeId == localTail.nodeId
  ensures combiner' == combiner.(state := CombinerReady)
  ensures localTail' == localTail.(localTail := combiner.state.localAndGlobalTail)
  {
    glinear var a_token := CombinerToken_unfold(combiner);
    glinear var b_token := LocalTail_unfold(localTail);

    // Compute the things we want to output (as ghost, _not_ glinear constructs)
    ghost var out1_expect := combiner.(state := CombinerReady);
    ghost var out1_token_expect := CombinerToken_unfold(out1_expect);

    ghost var out2_expect := localTail.(localTail := combiner.state.localAndGlobalTail);
    ghost var out2_token_expect := LocalTail_unfold(out2_expect);

    // Explain what transition we're going to do
    assert GoToCombinerReady(
        IL.dot(a_token.val, b_token.val),
        IL.dot(out1_token_expect.val, out2_token_expect.val),
        localTail.nodeId);
    assert IL.NextStep(
        IL.dot(a_token.val, b_token.val),
        IL.dot(out1_token_expect.val, out2_token_expect.val),
        GoToCombinerReady_Step(localTail.nodeId));

    // Perform the transition
    glinear var out1_token, out2_token := ILT.transition_2_2(a_token, b_token,
        out1_token_expect.val,
        out2_token_expect.val);

    combiner' := CombinerToken_fold(out1_expect, out1_token);
    localTail' := LocalTail_fold(out2_expect, out2_token);
  }

  glinear method perform_ExecDispatchRemote(
      glinear combiner: CombinerToken,
      glinear replica: Replica,
      gshared log_entry: Log)
  returns (
      glinear combiner': CombinerToken,
      glinear replica': Replica
    )
  requires combiner.nodeId == replica.nodeId
  requires combiner.nodeId != log_entry.node_id
  requires combiner.state.Combiner?
  requires log_entry.idx == combiner.state.localTail
  requires combiner.state.localTail < combiner.state.globalTail
  ensures combiner' == combiner.(state := combiner.state.(localTail := combiner.state.localTail + 1))
  ensures replica' == replica.(state := nrifc.update(replica.state, log_entry.op).new_state)
  {
    glinear var a_token := CombinerToken_unfold(combiner);
    glinear var b_token := Replica_unfold(replica);
    gshared var s_token := Log_unfold_borrow(log_entry);

    // Compute the things we want to output (as ghost, _not_ glinear constructs)
    ghost var out1_expect := combiner.(state := combiner.state.(localTail := combiner.state.localTail + 1));
    ghost var out1_token_expect := CombinerToken_unfold(out1_expect);

    ghost var out2_expect := replica.(state := nrifc.update(replica.state, log_entry.op).new_state);
    ghost var out2_token_expect := Replica_unfold(out2_expect);

    // Explain what transition we're going to do
    assert ExecDispatchRemote(
        IL.dot(s_token.val, IL.dot(a_token.val, b_token.val)),
        IL.dot(s_token.val, IL.dot(out1_token_expect.val, out2_token_expect.val)),
        combiner.nodeId);
    assert IL.NextStep(
        IL.dot(s_token.val, IL.dot(a_token.val, b_token.val)),
        IL.dot(s_token.val, IL.dot(out1_token_expect.val, out2_token_expect.val)),
        ExecDispatchRemote_Step(combiner.nodeId));

    // Perform the transition
    glinear var out1_token, out2_token := ILT.transition_1_2_2(s_token, a_token, b_token,
        out1_token_expect.val,
        out2_token_expect.val);

    combiner' := CombinerToken_fold(out1_expect, out1_token);
    replica' := Replica_fold(out2_expect, out2_token);
  }

  glinear method queueIsFinishedAfterExec(
      glinear combiner: CombinerToken)
  returns (glinear combiner': CombinerToken)
  requires combiner.state.Combiner?
  requires combiner.state.localTail == combiner.state.globalTail
  ensures combiner' == combiner
  ensures combiner.state.queueIndex == |combiner.state.queued_ops| // follows from invariant
  {
    glinear var t1 := CombinerToken_unfold(combiner);
    ghost var rest := ILT.obtain_invariant_1(inout t1);
    combiner' := CombinerToken_fold(combiner, t1);
  }

  glinear method pre_ExecDispatchLocal(
      glinear combiner: CombinerToken,
      gshared log_entry: Log)
  returns (glinear combiner': CombinerToken)
  requires combiner.nodeId == log_entry.node_id  
  requires combiner.state.Combiner?
  requires combiner.state.localTail == log_entry.idx
  requires combiner.state.localTail < combiner.state.globalTail
  ensures 0 <= combiner.state.queueIndex < |combiner.state.queued_ops|
  ensures combiner' == combiner
  {
    glinear var t1 := CombinerToken_unfold(combiner);
    gshared var t2 := Log_unfold_borrow(log_entry);
    ghost var rest := ILT.obtain_invariant_1_1(t2, inout t1);
    combiner' := CombinerToken_fold(combiner, t1);
  }

  glinear method pre2_ExecDispatchLocal(
      glinear combiner: CombinerToken,
      gshared log_entry: Log,
      glinear upd: Update)
  returns (glinear combiner': CombinerToken, glinear upd': Update)
  requires combiner.nodeId == log_entry.node_id  
  requires combiner.state.Combiner?
  requires combiner.state.localTail == log_entry.idx
  requires combiner.state.localTail < combiner.state.globalTail
  requires 0 <= combiner.state.queueIndex < |combiner.state.queued_ops|
  requires combiner.state.queued_ops[combiner.state.queueIndex] == upd.rid
  requires upd.us.UpdatePlaced?
  ensures upd' == upd && combiner' == combiner
  ensures upd.us.idx == combiner.state.localTail
  {
    glinear var t1 := CombinerToken_unfold(combiner);
    gshared var t2 := Log_unfold_borrow(log_entry);
    glinear var t3 := Update_unfold(upd);
    ghost var rest := ILT.obtain_invariant_1_2(t2, inout t1, inout t3);
    combiner' := CombinerToken_fold(combiner, t1);
    upd' := Update_fold(upd, t3);
  }

  glinear method perform_ExecDispatchLocal(
      glinear combiner: CombinerToken,
      glinear replica: Replica,
      glinear update: Update,
      gshared log_entry: Log)
  returns (
      glinear combiner': CombinerToken,
      glinear replica': Replica,
      glinear update': Update
    )
  requires combiner.nodeId == replica.nodeId
  requires combiner.nodeId == log_entry.node_id
  requires combiner.state.Combiner?
  requires log_entry.idx == combiner.state.localTail
  requires 0 <= combiner.state.queueIndex < |combiner.state.queued_ops|
  requires combiner.state.queued_ops[combiner.state.queueIndex] == update.rid
  requires update.us.UpdatePlaced?
  requires combiner.state.localTail < combiner.state.globalTail
  ensures combiner' == combiner.(state := combiner.state.(localTail := combiner.state.localTail + 1).(queueIndex := combiner.state.queueIndex + 1))
  ensures replica' == replica.(state := nrifc.update(replica.state, log_entry.op).new_state)
  ensures update.us.idx == combiner.state.localTail // follows from state machine invariant
  ensures update' == update.(us := UpdateApplied(
      nrifc.update(replica.state, log_entry.op).return_value,
      update.us.idx))
  {
    glinear var combiner1, update1;
    combiner1, update1 := pre2_ExecDispatchLocal(combiner, log_entry, update);
    assert update.us.idx == combiner.state.localTail;

    glinear var a_token := CombinerToken_unfold(combiner1);
    glinear var b_token := Replica_unfold(replica);
    glinear var c_token := Update_unfold(update1);
    gshared var s_token := Log_unfold_borrow(log_entry);

    // Compute the things we want to output (as ghost, _not_ glinear constructs)
    ghost var out1_expect := combiner.(state := combiner.state.(localTail := combiner.state.localTail + 1).(queueIndex := combiner.state.queueIndex + 1));
    ghost var out1_token_expect := CombinerToken_unfold(out1_expect);

    ghost var out2_expect := replica.(state := nrifc.update(replica.state, log_entry.op).new_state);
    ghost var out2_token_expect := Replica_unfold(out2_expect);

    ghost var out3_expect := update.(us := UpdateApplied(nrifc.update(replica.state, log_entry.op).return_value, update.us.idx));
    ghost var out3_token_expect := Update_unfold(out3_expect);

    // Explain what transition we're going to do

    /*
    ghost var m := IL.dot(s_token.val, IL.dot(IL.dot(a_token.val, b_token.val), c_token.val));
    ghost var m1 := IL.dot(s_token.val, IL.dot(IL.dot(out1_token_expect.val, out2_token_expect.val),out3_token_expect.val));

    ghost var nodeId := combiner.nodeId;
    ghost var c := m.combiner[nodeId];
    ghost var UpdateResult(nr_state', ret) := nrifc.update(m.replicas[nodeId], m.log[c.localTail].op);
    ghost var queue_index := c.queueIndex;
    ghost var request_id := c.queued_ops[queue_index];
    ghost var idx := c.localTail;
    ghost var c_new := c.(localTail := c.localTail + 1).(queueIndex := c.queueIndex + 1);
    ghost var m' := m.(combiner := m.combiner[nodeId := c_new])
              .(replicas := m.replicas[nodeId := nr_state'])
              .(localUpdates := m.localUpdates[request_id := UpdateApplied(ret, idx)]);

    assert nrifc.update(replica.state, log_entry.op).return_value == ret;
    assert idx == update.us.idx;
    
    assert m'.combiner == m1.combiner;
    assert m'.replicas == m1.replicas;
    assert m'.localUpdates == m1.localUpdates;
    assert m' == m1;
    */

    assert ExecDispatchLocal(
        IL.dot(s_token.val, IL.dot(IL.dot(a_token.val, b_token.val), c_token.val)),
        IL.dot(s_token.val, IL.dot(IL.dot(out1_token_expect.val, out2_token_expect.val), out3_token_expect.val)),
        combiner.nodeId);
    assert IL.NextStep(
        IL.dot(s_token.val, IL.dot(IL.dot(a_token.val, b_token.val), c_token.val)),
        IL.dot(s_token.val, IL.dot(IL.dot(out1_token_expect.val, out2_token_expect.val), out3_token_expect.val)),
        ExecDispatchLocal_Step(combiner.nodeId));

    // Perform the transition
    glinear var out1_token, out2_token, out3_token := ILT.transition_1_3_3(s_token, a_token, b_token, c_token,
        out1_token_expect.val,
        out2_token_expect.val,
        out3_token_expect.val);

    combiner' := CombinerToken_fold(out1_expect, out1_token);
    replica' := Replica_fold(out2_expect, out2_token);
    update' := Update_fold(out3_expect, out3_token);
  }

  glinear method perform_UpdateDone(
      glinear update: Update,
      gshared ctail: Ctail)
  returns (
      glinear update': Update)
  requires update.us.UpdateApplied?
  requires update.us.idx < ctail.ctail
  ensures update' == update.(us := UpdateDone(update.us.ret, update.us.idx))
  {
    glinear var a_token := Update_unfold(update);
    gshared var s_token := Ctail_unfold_borrow(ctail); // use `borrow` for `gshared` types.

    ghost var out_expect := update.(us := UpdateDone(update.us.ret, update.us.idx));
    ghost var out_token_expect := Update_unfold(out_expect);

    // Explain what transition we're going to do
    assert IL.UpdateRequestDone(
        IL.dot(s_token.val, a_token.val),
        IL.dot(s_token.val, out_token_expect.val),
        update.rid);
    assert IL.NextStep(
        IL.dot(s_token.val, a_token.val),
        IL.dot(s_token.val, out_token_expect.val),
        UpdateRequestDone_Step(update.rid));

    glinear var out_token := ILT.transition_1_1_1(s_token, a_token, out_token_expect.val);

    update' := Update_fold(out_expect, out_token);
  }

  glinear method perform_UpdateDoneMultiple(
      ghost n: nat,
      glinear updates: map<nat, Update>,
      gshared ctail: Ctail)
  returns (
      glinear updates': map<nat, Update>)
  requires forall i | 0 <= i < n ::
    && i in updates
    && updates[i].us.UpdateApplied?
    && updates[i].us.idx < ctail.ctail
  ensures forall i | 0 <= i < n ::
    && i in updates'
    && updates'[i] == updates[i].(us := UpdateDone(updates[i].us.ret, updates[i].us.idx))
  {
    glinear var updates0 := updates;
    updates' := glmap_empty();

    ghost var j := 0;
    while j < n
    invariant 0 <= j <= n
    invariant forall i | j <= i < n ::
      && i in updates0
      && updates0[i] == updates[i]
    invariant forall i | 0 <= i < j ::
      && i in updates'
      && updates'[i] == updates[i].(us := UpdateDone(updates[i].us.ret, updates[i].us.idx))
    {
      glinear var update;
      updates0, update := glmap_take(updates0, j);
      glinear var update' := perform_UpdateDone(update, ctail);

      updates' := glmap_insert(updates', j, update');

      j := j + 1;
    }

    dispose_anything(updates0);
  }

  glinear method perform_Init(glinear token: ILT.Token)
  returns (
      glinear globalTail: GlobalTail,
      glinear replicas: map<nat, Replica>,
      glinear localTails: map<nat, LocalTail>,
      glinear ctail: Ctail,
      glinear combiners: map<nat, CombinerToken>
  )
  requires token.loc == loc()
  requires IL.Init(token.val)
  ensures globalTail.tail == 0
  ensures ctail.ctail == 0
  ensures forall i | 0 <= i < NUM_REPLICAS as int ::
      i in replicas && i in localTails && i in combiners
      && replicas[i] == Replica(i, nrifc.init_state())
      && localTails[i] == LocalTail(i, 0)
      && combiners[i] == CombinerToken(i, CombinerReady)
}
