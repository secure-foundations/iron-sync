include "PCM.s.dfy"
include "StateMachines.s.dfy"

abstract module TicketStubSSM(IOIfc: InputOutputIfc) {
  import opened RequestIds

  type M(!new)

  function dot(x: M, y: M) : M
  function unit() : M

  function Ticket(rid: RequestId, input: IOIfc.Input) : M
  predicate IsStub(rid: RequestId, output: IOIfc.Output, stub: M)

  // By returning a set of request ids "in use", we enforce that
  // there are only a finite number of them (i.e., it is always possible to find
  // a free one).
  function request_ids_in_use(m: M) : set<RequestId>

  function Init() : M
  predicate Internal(shard: M, shard': M)

  predicate NewTicket(whole: M, whole': M, rid: RequestId, input: IOIfc.Input) {
    && rid !in request_ids_in_use(whole)
    && whole' == dot(whole, Ticket(rid, input))
  }

  predicate ConsumeStub(whole: M, whole': M, rid: RequestId, output: IOIfc.Output, stub: M) {
    && IsStub(rid, output, stub)
    && whole == dot(whole', stub)
  }

  predicate Inv(s: M)

  lemma InitImpliesInv(s: M)
  requires s == Init()
  ensures Inv(s)

  lemma InternalPreservesInv(shard: M, shard': M, rest: M)
  requires Inv(dot(shard, rest))
  requires Internal(shard, shard')
  ensures Inv(dot(shard', rest))

  lemma NewTicketPreservesInv(whole: M, whole': M, rid: RequestId, input: IOIfc.Input)
  requires Inv(whole)
  requires NewTicket(whole, whole', rid, input)
  ensures Inv(whole')

  lemma ConsumeStubPreservesInv(whole: M, whole': M, rid: RequestId, output: IOIfc.Output, stub: M)
  requires Inv(whole)
  requires ConsumeStub(whole, whole', rid, output, stub)
  ensures Inv(whole')

  lemma dot_unit(x: M)
  ensures dot(x, unit()) == x

  lemma commutative(x: M, y: M)
  ensures dot(x, y) == dot(y, x)

  lemma associative(x: M, y: M, z: M)
  ensures dot(x, dot(y, z)) == dot(dot(x, y), z)

  lemma exists_inv_state()
  returns (s: M)
  ensures Inv(s)
}

module TicketStubStateMachine(IOIfc: InputOutputIfc, ssm: TicketStubSSM(IOIfc))
    refines StateMachine(AsyncIfc(IOIfc))
{
  import AsyncIfc = AsyncIfc(IOIfc)

  type Variables = ssm.M

  predicate Init(s: Variables) {
    s == ssm.Init()
  }

  predicate InternalNext(s: Variables, s': Variables,
      shard: Variables, shard': Variables, rest: Variables)
  {
    && s == ssm.dot(shard, rest)
    && s' == ssm.dot(shard', rest)
    && ssm.Internal(shard, shard')
  }

  predicate Next(s: Variables, s': Variables, op: ifc.Op) {
    match op {
      case Start(rid, input) => ssm.NewTicket(s, s', rid, input)
      case End(rid, output) => exists stub :: ssm.ConsumeStub(s, s', rid, output, stub)
      case InternalOp =>
        exists shard, shard', rest :: InternalNext(s, s', shard, shard', rest)
    }
  }
}

module Obligations(
    IOIfc: InputOutputIfc,
    ssm: TicketStubSSM(IOIfc),
    spec: StateMachine(IOIfc),
    ref: Refinement(
          AsyncIfc(IOIfc),
          TicketStubStateMachine(IOIfc, ssm),
          AsyncStateMachine(IOIfc, spec)
       )
  )
{ }

module TicketStubSingletonLoc {
  import opened GhostLoc
  function {:extern} loc(): Loc
}

module TicketStubPCM(IOIfc: InputOutputIfc,
  ssm: TicketStubSSM(IOIfc)) refines PCM {
  
  type M = ssm.M

  function dot(x: M, y: M) : M
  {
    ssm.dot(x, y)
  }

  predicate valid(x: M)
  {
    exists y: M :: ssm.Inv(dot(x, y))
  }

  function unit(): M
  {
    ssm.unit()
  }

  lemma dot_unit(x: M)
  {
    ssm.dot_unit(x);
  }

  lemma valid_unit(x: M)
  {
    var x := ssm.exists_inv_state();
    commutative(unit(), x);
    dot_unit(x);
    assert ssm.Inv(dot(unit(), x));
  }

  lemma commutative(x: M, y: M)
  //ensures dot(x, y) == dot(y, x)
  {
    ssm.commutative(x, y);
  }

  lemma associative(x: M, y: M, z: M)
  //ensures dot(x, dot(y, z)) == dot(dot(x, y), z)
  {
    ssm.associative(x, y, z);
  }

  predicate single_step_helper(a: M, b: M, a': M, b': M, c: M) {
    a == dot(a', c) && b == dot(b', c) && ssm.Internal(a', b')
  }

  predicate single_step(a: M, b: M) {
    exists a', b', c :: single_step_helper(a, b, a', b', c)
  }

  least predicate reachable(a: M, b: M) {
    a == b || (exists z :: reachable(a, z) && single_step(z, b))
  }

  predicate transition(a: M, b: M) {
    reachable(a, b)
  }

  lemma transition_is_refl(a: M)
  //requires transition(a, a)
  {
  }

  least lemma reachable_is_trans(a: M, b: M, c: M)
  requires reachable(b, c)
  requires transition(a, b)
  ensures reachable(a, c)
  {
    if b == c {
    } else {
      var z :| reachable(b, z) && single_step(z, c);
      reachable_is_trans(a, b, z);
    }
  }

  lemma transition_is_trans(a: M, b: M, c: M)
  //requires transition(a, b)
  //requires transition(b, c)
  ensures transition(a, c)
  {
    reachable_is_trans(a, b, c);
  }

  least lemma reachable_is_monotonic(a: M, b: M, c: M)
  requires reachable(a, b)
  ensures reachable(dot(a, c), dot(b, c))
  {
    if a == b {
    } else {
      var z :| reachable(a, z) && single_step(z, b);
      reachable_is_monotonic(a, z, c);
      var z', b', d :| single_step_helper(z, b, z', b', d);
      associative(z', d, c);
      associative(b', d, c);
      assert single_step_helper(dot(z, c), dot(b, c), z', b', dot(d, c));
      assert single_step(dot(z, c), dot(b, c));
    }
  }

  lemma transition_is_monotonic(a: M, b: M, c: M)
  //requires transition(a, b)
  ensures transition(dot(a, c), dot(b, c))
  {
    reachable_is_monotonic(a, b, c);
  }
}
