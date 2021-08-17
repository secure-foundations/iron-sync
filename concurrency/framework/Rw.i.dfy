include "PCM.s.dfy"
include "PCMExt.s.dfy"
include "PCMWrap.s.dfy"
include "../../lib/Base/Option.s.dfy"

abstract module Rw {
  import opened Options

  type StoredType(!new)

  type M(!new)

  function dot(x: M, y: M) : M
  function unit() : M

  predicate Init(s: M)
  predicate Inv(x: M) 
  function I(x: M) : Option<StoredType> requires Inv(x)

  predicate transition(a: M, b: M) {
    forall p: M :: Inv(dot(a, p)) ==>
        && Inv(dot(b, p))
        && I(dot(a, p)) == I(dot(b, p))
  }

  predicate deposit(a: M, b: M, x: StoredType)
  {
    forall p: M :: Inv(dot(a, p)) ==>
        && Inv(dot(b, p))
        && I(dot(a, p)) == None
        && I(dot(b, p)) == Some(x)
  }

  predicate withdraw(a: M, b: M, x: StoredType)
  {
    forall p: M :: Inv(dot(a, p)) ==>
        && Inv(dot(b, p))
        && I(dot(a, p)) == Some(x)
        && I(dot(b, p)) == None
  }

  predicate borrow(a: M, x: StoredType)
  {
    forall p: M :: Inv(dot(a, p)) ==>
        && I(dot(a, p)) == Some(x)
  }

  lemma dot_unit(x: M)
  ensures dot(x, unit()) == x

  lemma commutative(x: M, y: M)
  ensures dot(x, y) == dot(y, x)

  lemma associative(x: M, y: M, z: M)
  ensures dot(x, dot(y, z)) == dot(dot(x, y), z)

  lemma InitImpliesInv(x: M)
  requires Init(x)
  ensures Inv(x)
  ensures I(x) == None

  // TODO(travis) I think this is probably unnecessary
  // For now, just add "or m == unit()" to your Invariant.
  lemma inv_unit()
  ensures Inv(unit())
  ensures I(unit()) == None
}

module Rw_PCMWrap(rw: Rw) refines PCMWrap {
  type G = rw.StoredType
}

module Rw_PCMExt(rw: Rw) refines PCMExt(Rw_PCMWrap(rw)) {
  import Wrap = Rw_PCMWrap(rw)

  type M = rw.M
  function dot(x: M, y: M) : M { rw.dot(x, y) }
  predicate valid(x: M) { exists y :: rw.Inv(dot(x, y)) }
  function unit() : M { rw.unit() }

  // Partial Commutative Monoid (PCM) axioms

  lemma dot_unit(x: M)
  ensures dot(x, unit()) == x
  {
    rw.dot_unit(x);
  }

  lemma valid_unit(x: M)
  ensures valid(unit())
  {
    rw.inv_unit();
    dot_unit(unit());
    assert rw.Inv(dot(unit(), unit()));
  }

  lemma commutative(x: M, y: M)
  ensures dot(x, y) == dot(y, x)
  {
    rw.commutative(x, y);
  }

  lemma associative(x: M, y: M, z: M)
  ensures dot(x, dot(y, z)) == dot(dot(x, y), z)
  {
    rw.associative(x, y, z);
  }

  predicate transition(a: M, b: M) {
    rw.transition(a, b)
  }

  lemma transition_is_refl(a: M)
  //requires transition(a, a)
  { }

  lemma transition_is_trans(a: M, b: M, c: M)
  //requires transition(a, b)
  //requires transition(b, c)
  //ensures transition(a, c)
  { }

  lemma transition_is_monotonic(a: M, b: M, c: M)
  //requires transition(a, b)
  //ensures transition(dot(a, c), dot(b, c))
  {
    forall p: M | rw.Inv(rw.dot(rw.dot(a, c), p))
    ensures rw.Inv(rw.dot(rw.dot(b, c), p)) && rw.I(rw.dot(rw.dot(a, c), p)) == rw.I(rw.dot(rw.dot(b, c), p))
    {
      associative(b, c, p);
      associative(a, c, p);
      assert rw.Inv(rw.dot(a, rw.dot(c, p)));
    }
    assert rw.transition(dot(a, c), dot(b, c));
    assert transition(dot(a, c), dot(b, c));
  }

  function I(f: F) : Option<B> {
    if rw.Inv(f) then (
      if rw.I(f).Some? then (
        Some(Wrap.one(rw.I(f).value))
      ) else (
        Some(Wrap.unit())
      )
    ) else (
      None
    )
  }

  lemma I_unit()
  ensures I(unit()) == Some(base.unit())
  {
    rw.inv_unit();
  }

  lemma I_respects_transitions(f: F, f': F)
  //requires transition(f, f')
  //requires I(f).Some?
  //ensures I(f').Some?
  //ensures base.transition(I(f).value, I(f').value)
  {
    assert rw.Inv(f);
    rw.dot_unit(f);
    rw.dot_unit(f');
    assert rw.Inv(rw.dot(f, unit()));
  }

  lemma I_valid(f: F)
  //requires I(f).Some?
  //ensures valid(f)
  {
    assert rw.Inv(f);
    rw.dot_unit(f);
    assert rw.Inv(dot(f, unit()));
  }
}

module RwTokens(rw: Rw) {
  import opened GhostLoc

  import Wrap = Rw_PCMWrap(rw)
  import T = Tokens(Rw_PCMExt(rw))
  
  type Token = t : T.Token | t.loc.ExtLoc? && t.loc.base_loc == Wrap.singleton_loc()
    witness *

  glinear method initialize(glinear m: rw.M)
  returns (glinear token: Token)
  requires rw.Init(m)
  ensures token.val == m

  glinear method obtain_invariant_2(
      glinear inout token1: Token,
      glinear inout token2: Token)
  returns (ghost rest: rw.M)
  requires old_token1.loc == old_token2.loc
  ensures token1 == old_token1
  ensures token2 == old_token2
  ensures rw.Inv(rw.dot(rw.dot(token1.val, token2.val), rest))

  glinear method obtain_invariant_3(
      glinear inout token1: Token,
      glinear inout token2: Token,
      glinear inout token3: Token)
  returns (ghost rest: rw.M)
  requires old_token1.loc == old_token2.loc == old_token3.loc
  ensures token1 == old_token1
  ensures token2 == old_token2
  ensures token3 == old_token3
  ensures rw.Inv(rw.dot(rw.dot(rw.dot(token1.val, token2.val), token3.val), rest))

  glinear method internal_transition(
      glinear token: Token,
      ghost expected_value: rw.M)
  returns (glinear token': Token)
  requires rw.transition(token.val, expected_value)
  ensures token' == T.Token(token.loc, expected_value)

  glinear method deposit(
      glinear token: Token,
      glinear stored_value: rw.StoredType,
      ghost expected_value: rw.M)
  returns (glinear token': Token)
  requires rw.deposit(token.val, expected_value, stored_value)
  ensures token' == T.Token(token.loc, expected_value)

  glinear method withdraw(
      glinear token: Token,
      ghost expected_value: rw.M,
      ghost expected_retrieved_value: rw.StoredType)
  returns (glinear token': Token, glinear retrieved_value: rw.StoredType)
  requires rw.withdraw(token.val, expected_value, expected_retrieved_value)
  ensures token' == T.Token(token.loc, expected_value)
  ensures retrieved_value == expected_retrieved_value

  // TODO borrow method

  /*
   * Helpers
   */

  glinear method internal_transition_1_2(
      glinear token1: Token,
      ghost expected_value1: rw.M,
      ghost expected_value2: rw.M)
  returns (glinear token1': Token, glinear token2': Token)
  requires rw.transition(
      token1.val,
      rw.dot(expected_value1, expected_value2))
  ensures token1' == T.Token(token1.loc, expected_value1)
  ensures token2' == T.Token(token1.loc, expected_value2)

  glinear method internal_transition_2_1(
      glinear token1: Token,
      glinear token2: Token,
      ghost expected_value1: rw.M)
  returns (glinear token1': Token)
  requires token1.loc == token2.loc
  requires rw.transition(
      rw.dot(token1.val, token2.val),
      expected_value1)
  ensures token1' == T.Token(token1.loc, expected_value1)

  glinear method internal_transition_2_2(
      glinear token1: Token,
      glinear token2: Token,
      ghost expected_value1: rw.M,
      ghost expected_value2: rw.M)
  returns (glinear token1': Token, glinear token2': Token)
  requires token1.loc == token2.loc
  requires rw.transition(
      rw.dot(token1.val, token2.val),
      rw.dot(expected_value1, expected_value2))
  ensures token1' == T.Token(token1.loc, expected_value1)
  ensures token2' == T.Token(token1.loc, expected_value2)

  glinear method internal_transition_3_2(
      glinear token1: Token,
      glinear token2: Token,
      glinear token3: Token,
      ghost expected_value1: rw.M,
      ghost expected_value2: rw.M)
  returns (glinear token1': Token, glinear token2': Token)
  requires token1.loc == token2.loc == token3.loc
  requires rw.transition(
      rw.dot(rw.dot(token1.val, token2.val), token3.val),
      rw.dot(expected_value1, expected_value2))
  ensures token1' == T.Token(token1.loc, expected_value1)
  ensures token2' == T.Token(token1.loc, expected_value2)

  glinear method internal_transition_3_3(
      glinear token1: Token,
      glinear token2: Token,
      glinear token3: Token,
      ghost expected_value1: rw.M,
      ghost expected_value2: rw.M,
      ghost expected_value3: rw.M)
  returns (glinear token1': Token, glinear token2': Token, glinear token3': Token)
  requires token1.loc == token2.loc == token3.loc
  requires rw.transition(
      rw.dot(rw.dot(token1.val, token2.val), token3.val),
      rw.dot(rw.dot(expected_value1, expected_value2), expected_value3))
  ensures token1' == T.Token(token1.loc, expected_value1)
  ensures token2' == T.Token(token1.loc, expected_value2)
  ensures token3' == T.Token(token1.loc, expected_value3)

  glinear method deposit_2_1(
      glinear token1: Token,
      glinear token2: Token,
      glinear stored_value: rw.StoredType,
      ghost expected_value1: rw.M)
  returns (glinear token1': Token)
  requires token1.loc == token2.loc
  requires rw.deposit(
    rw.dot(token1.val, token2.val),
    expected_value1,
    stored_value)
  ensures token1' == T.Token(token1.loc, expected_value1)

  glinear method deposit_2_2(
      glinear token1: Token,
      glinear token2: Token,
      glinear stored_value: rw.StoredType,
      ghost expected_value1: rw.M,
      ghost expected_value2: rw.M)
  returns (glinear token1': Token, glinear token2': Token)
  requires token1.loc == token2.loc
  requires rw.deposit(
    rw.dot(token1.val, token2.val),
    rw.dot(expected_value1, expected_value2),
    stored_value)
  ensures token1' == T.Token(token1.loc, expected_value1)
  ensures token2' == T.Token(token1.loc, expected_value2)

  glinear method deposit_3_2(
      glinear token1: Token,
      glinear token2: Token,
      glinear token3: Token,
      glinear stored_value: rw.StoredType,
      ghost expected_value1: rw.M,
      ghost expected_value2: rw.M)
  returns (glinear token1': Token, glinear token2': Token)
  requires token1.loc == token2.loc == token3.loc
  requires rw.deposit(
    rw.dot(rw.dot(token1.val, token2.val), token3.val),
    rw.dot(expected_value1, expected_value2),
    stored_value)
  ensures token1' == T.Token(token1.loc, expected_value1)
  ensures token2' == T.Token(token1.loc, expected_value2)

  glinear method deposit_3_3(
      glinear token1: Token,
      glinear token2: Token,
      glinear token3: Token,
      glinear stored_value: rw.StoredType,
      ghost expected_value1: rw.M,
      ghost expected_value2: rw.M,
      ghost expected_value3: rw.M)
  returns (glinear token1': Token, glinear token2': Token, glinear token3': Token)
  requires token1.loc == token2.loc == token3.loc
  requires rw.deposit(
    rw.dot(rw.dot(token1.val, token2.val), token3.val),
    rw.dot(rw.dot(expected_value1, expected_value2), expected_value3),
    stored_value)
  ensures token1' == T.Token(token1.loc, expected_value1)
  ensures token2' == T.Token(token1.loc, expected_value2)
  ensures token3' == T.Token(token1.loc, expected_value3)

  glinear method withdraw_1_1(
      glinear token1: Token,
      ghost expected_value1: rw.M,
      ghost expected_retrieved_value: rw.StoredType)
  returns (glinear token1': Token,
      glinear retrieved_value: rw.StoredType)
  requires rw.withdraw(
      token1.val,
      expected_value1,
      expected_retrieved_value)
  ensures token1' == T.Token(token1.loc, expected_value1)
  ensures retrieved_value == expected_retrieved_value

  glinear method withdraw_1_2(
      glinear token1: Token,
      ghost expected_value1: rw.M,
      ghost expected_value2: rw.M,
      ghost expected_retrieved_value: rw.StoredType)
  returns (glinear token1': Token, glinear token2': Token,
      glinear retrieved_value: rw.StoredType)
  requires rw.withdraw(
      token1.val,
      rw.dot(expected_value1, expected_value2),
      expected_retrieved_value)
  ensures token1' == T.Token(token1.loc, expected_value1)
  ensures token2' == T.Token(token1.loc, expected_value2)
  ensures retrieved_value == expected_retrieved_value

  glinear method withdraw_3_3(
      glinear token1: Token,
      glinear token2: Token,
      glinear token3: Token,
      ghost expected_value1: rw.M,
      ghost expected_value2: rw.M,
      ghost expected_value3: rw.M,
      ghost expected_retrieved_value: rw.StoredType)
  returns (glinear token1': Token, glinear token2': Token, glinear token3': Token,
      glinear retrieved_value: rw.StoredType)
  requires token1.loc == token2.loc == token3.loc
  requires rw.withdraw(
      rw.dot(rw.dot(token1.val, token2.val), token3.val),
      rw.dot(rw.dot(expected_value1, expected_value2), expected_value3),
      expected_retrieved_value)
  ensures token1' == T.Token(token1.loc, expected_value1)
  ensures token2' == T.Token(token1.loc, expected_value2)
  ensures token3' == T.Token(token1.loc, expected_value3)
  ensures retrieved_value == expected_retrieved_value

  glinear method get_unit(ghost loc: Loc)
  returns (glinear t: Token)
  requires loc.ExtLoc? && loc.base_loc == Wrap.singleton_loc()
  ensures t.loc == loc

  glinear method dispose(glinear t: Token)
}
