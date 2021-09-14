module GlinearSeq {
  type {:extern "predefined"} glseq<V>
  {
    function {:extern} len() : nat

    predicate {:extern} has(i: nat)
    requires i < len()

    function {:extern} get(i: nat) : V
    requires i < len() && has(i)

    gshared function method {:extern} borrow(ghost i: nat) : (gshared v': V)
    requires i < this.len()
    requires this.has(i)
    ensures v' == this.get(i)
  }

  glinear method {:extern} glseq_take<V>(glinear g: glseq<V>, ghost i: nat)
  returns (glinear g': glseq<V>, glinear v': V)
  requires i < g.len()
  requires g.has(i)
  ensures v' == g.get(i)
  ensures g'.len() == g.len()
  ensures forall j | 0 <= j < g.len() :: j != i ==> !g.has(j) ==> !g'.has(j)
  ensures forall j | 0 <= j < g.len() ::
      j != i ==> g.has(j) ==> g'.has(j) && g'.get(j) == g.get(j)

}
