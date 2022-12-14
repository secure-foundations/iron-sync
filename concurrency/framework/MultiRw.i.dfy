include "PCM.s.dfy"
include "PCMExt.s.dfy"
include "PCMWrap.s.dfy"
include "Ptrs.s.dfy"
include "../../lib/Base/Multisets.i.dfy"
include "../../lib/Base/Option.s.dfy"

include "GlinearMap.s.dfy"

abstract module MultiRw {
  type Key(!new,==)
  type StoredType(!new)

  type M(!new)

  function dot(x: M, y: M) : M
  function unit() : M

  predicate Inv(x: M) 
  function I(x: M) : map<Key, StoredType> requires Inv(x)

  predicate transition(a: M, b: M) {
    forall p: M :: Inv(dot(a, p)) ==> Inv(dot(b, p))
        && I(dot(a, p)) == I(dot(b, p))
  }

  predicate deposit(a: M, b: M, key: Key, x: StoredType)
  {
    forall p: M :: Inv(dot(a, p)) ==> Inv(dot(b, p))
        && key !in I(dot(a, p))
        && I(dot(b, p)) == I(dot(a, p))[key := x]
  }

  predicate withdraw(a: M, b: M, key: Key, x: StoredType)
  {
    forall p: M :: Inv(dot(a, p)) ==> Inv(dot(b, p))
        && I(dot(a, p)) == I(dot(b, p))[key := x]
        && key !in I(dot(b, p))
  }

  predicate withdraw_many(a: M, b: M, x: map<Key, StoredType>)
  {
    forall p: M :: Inv(dot(a, p)) ==> Inv(dot(b, p))
        && I(dot(b, p)).Keys !! x.Keys
        && I(dot(a, p)) == (
          map k | k in (I(dot(b, p)).Keys + x.Keys) ::
          if k in I(dot(b, p)).Keys then I(dot(b, p))[k] else x[k])
  }

  predicate guard(a: M, key: Key, x: StoredType)
  {
    forall p: M :: Inv(dot(a, p)) ==>
        && key in I(dot(a, p))
        && I(dot(a, p))[key] == x
  }

  lemma dot_unit(x: M)
  ensures dot(x, unit()) == x

  lemma commutative(x: M, y: M)
  ensures dot(x, y) == dot(y, x)

  lemma associative(x: M, y: M, z: M)
  ensures dot(x, dot(y, z)) == dot(dot(x, y), z)

  // TODO(travis) I think this is probably unnecessary
  // For now, just add "or m == unit()" to your Invariant.
  lemma inv_unit()
  ensures Inv(unit())
  ensures I(unit()) == map[]
}

module MultiRw_PCMWrap(rw: MultiRw) refines PCMWrap {
  type G = rw.StoredType
}

module MultiRw_PCMExt(rw: MultiRw) refines PCMExt(MultiRw_PCMWrap(rw)) {
  import Wrap = MultiRw_PCMWrap(rw)
  import opened Multisets

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
      Some(Wrap.M(ValueMultiset(rw.I(f))))
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

module MultiRwTokens(rw: MultiRw) {
  import opened GhostLoc

  import Wrap = MultiRw_PCMWrap(rw)
  import WrapT = PCMWrapTokens(MultiRw_PCMWrap(rw))
  import WrapPT = Tokens(MultiRw_PCMWrap(rw))
  import T = Tokens(MultiRw_PCMExt(rw))
  import ET = ExtTokens(MultiRw_PCMWrap(rw), MultiRw_PCMExt(rw))
  import pcm = MultiRw_PCMExt(rw)
  import Multisets
  import GlinearMap
  import Ptrs
  
  type Token = t : T.Token | t.loc.ExtLoc? && t.loc.base_loc == Wrap.singleton_loc()
    witness *

  glinear method map_to_multiset(glinear b: map<rw.Key, rw.StoredType>)
  returns (glinear y: WrapT.GToken)
  ensures y.val.m == Multisets.ValueMultiset(b)
  decreases |b|
  {
    ghost var ghost_b := b;
    if (ghost_b == map[]) {
      y := WrapPT.get_unit(Wrap.singleton_loc());
      Ptrs.dispose_anything(b);
    } else {
      ghost var k :| k in b;
      glinear var b0, x := GlinearMap.glmap_take(b, k);
      assert b == b0[k := b[k]];
      assert |b0| < |b|;
      glinear var y0 := map_to_multiset(b0);
      y := WrapPT.join(y0, WrapT.wrap(x));
      Multisets.ValueMultisetInduct(b0, k, b[k]);
    }
  }

  glinear method multiset_to_map(glinear y: WrapT.GToken, ghost b: map<rw.Key, rw.StoredType>)
  returns (glinear b': map<rw.Key, rw.StoredType>)
  requires y.val.m == Multisets.ValueMultiset(b)
  ensures b' == b
  decreases |b|
  {
    if b == map[] {
      b' := GlinearMap.glmap_empty();
      Ptrs.dispose_anything(y);
    } else {
      ghost var k :| k in b;
      ghost var b0 := b - {k};
      assert b == b0[k := b[k]];
      assert |b0| < |b|;
      Multisets.ValueMultisetInduct(b0, k, b[k]);
      glinear var y0, x := WrapPT.split(y,
          Wrap.M(Multisets.ValueMultiset(b0)), Wrap.one(b[k]));
      glinear var b0' := multiset_to_map(y0, b0);
      b' := GlinearMap.glmap_insert(b0', k, WrapT.unwrap(x));
    }
  }

  lemma multiset_union_maps<K,V>(a: map<K,V>, b: map<K, V>, c: map<K, V>)
  requires a.Keys !! b.Keys
  requires forall k | k in c :: k in a || k in b
  requires forall k | k in a :: k in c && c[k] == a[k]
  requires forall k | k in b :: k in c && c[k] == b[k]
  ensures Multisets.ValueMultiset(a) + Multisets.ValueMultiset(b) == Multisets.ValueMultiset(c)
  decreases |b|
  {
    if (b == map[]) {
      assert Multisets.ValueMultiset(b) == multiset{};
      assert a == c;
    } else {
      var k :| k in b.Keys;
      var b1 := b - {k};
      assert |b1| < |b| by {
        assert b == b1[k := b[k]];
        assert |b| == |b1| + 1;
      }
      var c1 := c - {k};
      calc {
        Multisets.ValueMultiset(a) + Multisets.ValueMultiset(b);
        {
          Multisets.ValueMultisetInduct(b1, k, b[k]);
          assert b == b1[k := b[k]];
          assert Multisets.ValueMultiset(b)
              == Multisets.ValueMultiset(b1) + multiset{b[k]};
        }
        Multisets.ValueMultiset(a) + Multisets.ValueMultiset(b1) + multiset{b[k]};
        {
          multiset_union_maps(a, b1, c1);
        }
        Multisets.ValueMultiset(c1) + multiset{b[k]};
        {
          Multisets.ValueMultisetInduct(c1, k, b[k]);
          assert c == c1[k := b[k]];
        }
        Multisets.ValueMultiset(c);
      }
    }
  }

  glinear method initialize_nonempty(glinear b: map<rw.Key, rw.StoredType>, ghost m: rw.M)
  returns (glinear token: Token)
  requires rw.Inv(m)
  requires rw.I(m) == b
  ensures token.val == m
  {
    glinear var wrapped := map_to_multiset(b);
    token := ET.ext_init(wrapped, m);
  }

  glinear method  split3(glinear sum: Token,
      ghost a: pcm.M, ghost b: pcm.M, ghost c: pcm.M)
  returns (glinear a': Token, glinear b': Token, glinear c': Token)
  requires sum.val == rw.dot(rw.dot(a, b), c)
  ensures a' == T.Token(sum.loc, a)
  ensures b' == T.Token(sum.loc, b)
  ensures c' == T.Token(sum.loc, c)
  {
    glinear var x;
    x, c' := T.split(sum, rw.dot(a, b), c);
    a', b' := T.split(x, a, b);
  }

  glinear method {:extern} split6(glinear sum: Token,
      ghost a: pcm.M, ghost b: pcm.M, ghost c: pcm.M, ghost d: pcm.M, ghost e: pcm.M, ghost f: pcm.M)
  returns (glinear a': Token, glinear b': Token, glinear c': Token, glinear d': Token, glinear e': Token, glinear f': Token)
  requires sum.val == rw.dot(rw.dot(rw.dot(rw.dot(rw.dot(a, b), c), d), e), f)
  ensures a' == T.Token(sum.loc, a)
  ensures b' == T.Token(sum.loc, b)
  ensures c' == T.Token(sum.loc, c)
  ensures d' == T.Token(sum.loc, d)
  ensures e' == T.Token(sum.loc, e)
  ensures f' == T.Token(sum.loc, f)
  {
    glinear var x;
    x, f' := T.split(sum, rw.dot(rw.dot(rw.dot(rw.dot(a, b), c), d), e), f);
    x, e' := T.split(x, rw.dot(rw.dot(rw.dot(a, b), c), d), e);
    x, d' := T.split(x, rw.dot(rw.dot(a, b), c), d);
    x, c' := T.split(x, rw.dot(a, b), c);
    a', b' := T.split(x, a, b);
  }

  function method {:opaque} update(
      glinear b: Token,
      ghost expected_out: rw.M)
    : (glinear c: Token)
  requires pcm.transition(b.val, expected_out)
  ensures c == T.Token(b.loc, expected_out)
  {
    rw.dot_unit(b.val);
    rw.dot_unit(expected_out);
    rw.commutative(b.val, rw.unit());
    rw.commutative(expected_out, rw.unit());
    T.transition_update(T.get_unit_shared(b.loc), b, expected_out)
  }

  glinear method internal_transition(
      glinear token: Token,
      ghost expected_value: rw.M)
  returns (glinear token': Token)
  requires rw.transition(token.val, expected_value)
  ensures token' == T.Token(token.loc, expected_value)
  {
    token' := update(token, expected_value);
  }

  glinear method deposit(
      glinear token: Token,
      ghost key: rw.Key,
      glinear stored_value: rw.StoredType,
      ghost expected_value: rw.M)
  returns (glinear token': Token)
  requires rw.deposit(token.val, expected_value, key, stored_value)
  ensures token' == T.Token(token.loc, expected_value)
  {
    glinear var m := WrapT.wrap(stored_value);
    ghost var m' := Wrap.unit();

    forall p |
          pcm.I(pcm.dot(token.val, p)).Some?
            && Wrap.valid(Wrap.dot(m.val, pcm.I(pcm.dot(token.val, p)).value))
    ensures pcm.I(pcm.dot(expected_value, p)).Some?
    ensures Wrap.transition(
              Wrap.dot(m.val, pcm.I(pcm.dot(token.val, p)).value),
              Wrap.dot(m', pcm.I(pcm.dot(expected_value, p)).value))
    {
      Multisets.ValueMultisetInduct(rw.I(rw.dot(token.val, p)), key, stored_value);
      /*
       calc {
         Wrap.dot(m.val, pcm.I(pcm.dot(token.val, p)).value);
         Wrap.dot(Wrap.M(multiset{stored_value}), pcm.I(pcm.dot(token.val, p)).value);
         pcm.I(pcm.dot(expected_value, p)).value;
         Wrap.dot(m', pcm.I(pcm.dot(expected_value, p)).value);
       }
       */
    }

    glinear var f, b := ET.ext_transfer(
        token, expected_value, m, Wrap.unit());
    WrapPT.dispose(b);
    token' := f;
  }

  glinear method withdraw(
      glinear token: Token,
      ghost expected_value: rw.M,
      ghost key: rw.Key,
      ghost expected_retrieved_value: rw.StoredType)
  returns (glinear token': Token, glinear retrieved_value: rw.StoredType)
  requires rw.withdraw(token.val, expected_value, key, expected_retrieved_value)
  ensures token' == T.Token(token.loc, expected_value)
  ensures retrieved_value == expected_retrieved_value
  {
    glinear var m := WrapPT.get_unit(Wrap.singleton_loc());
    ghost var m' := Wrap.one(expected_retrieved_value);

    forall p |
          pcm.I(pcm.dot(token.val, p)).Some?
            && Wrap.valid(Wrap.dot(m.val, pcm.I(pcm.dot(token.val, p)).value))
    ensures pcm.I(pcm.dot(expected_value, p)).Some?
    ensures Wrap.transition(
              Wrap.dot(m.val, pcm.I(pcm.dot(token.val, p)).value),
              Wrap.dot(m', pcm.I(pcm.dot(expected_value, p)).value))
    {
      Multisets.ValueMultisetInduct(rw.I(rw.dot(expected_value, p)), key,
          expected_retrieved_value);
    }

    glinear var f, b := ET.ext_transfer(
        token, expected_value,
        m, m');
    token' := f;
    retrieved_value := WrapT.unwrap(b);
  }

  glinear method withdraw_many_3_3(
      glinear token1: Token,
      glinear token2: Token,
      glinear token3: Token,
      ghost expected_value1: rw.M,
      ghost expected_value2: rw.M,
      ghost expected_value3: rw.M,
      ghost expected_retrieved_values: map<rw.Key, rw.StoredType>)
  returns (glinear token1': Token, glinear token2': Token, glinear token3': Token,
      glinear retrieved_values: map<rw.Key, rw.StoredType>)
  requires token1.loc == token2.loc == token3.loc
  requires rw.withdraw_many(
      rw.dot(rw.dot(token1.val, token2.val), token3.val),
      rw.dot(rw.dot(expected_value1, expected_value2), expected_value3),
      expected_retrieved_values)
  ensures token1' == T.Token(token1.loc, expected_value1)
  ensures token2' == T.Token(token1.loc, expected_value2)
  ensures token3' == T.Token(token1.loc, expected_value3)
  ensures retrieved_values == expected_retrieved_values
  {
    glinear var x := T.join(token1, token2);
    x := T.join(x, token3);
    glinear var y;
    y, retrieved_values := withdraw_many(x,
        rw.dot(rw.dot(expected_value1, expected_value2), expected_value3),
        expected_retrieved_values);
    token1', token2', token3' := split3(y, expected_value1, expected_value2, expected_value3);
  }

  glinear method withdraw_many(
      glinear token: Token,
      ghost expected_value: rw.M,
      ghost expected_retrieved_values: map<rw.Key, rw.StoredType>)
  returns (glinear token': Token, glinear retrieved_values: map<rw.Key, rw.StoredType>)
  requires rw.withdraw_many(token.val, expected_value, expected_retrieved_values)
  ensures token' == T.Token(token.loc, expected_value)
  ensures retrieved_values == expected_retrieved_values
  {
    glinear var m := WrapPT.get_unit(Wrap.singleton_loc());
    ghost var m' := Wrap.M(Multisets.ValueMultiset(expected_retrieved_values));

    forall p |
          pcm.I(pcm.dot(token.val, p)).Some?
            && Wrap.valid(Wrap.dot(m.val, pcm.I(pcm.dot(token.val, p)).value))
    ensures pcm.I(pcm.dot(expected_value, p)).Some?
    ensures Wrap.transition(
              Wrap.dot(m.val, pcm.I(pcm.dot(token.val, p)).value),
              Wrap.dot(m', pcm.I(pcm.dot(expected_value, p)).value))
    {
      multiset_union_maps(expected_retrieved_values,
          rw.I(pcm.dot(expected_value, p)),
          rw.I(pcm.dot(token.val, p)));
    }
    
    glinear var f, b := ET.ext_transfer(
        token, expected_value,
        m, m');
    token' := f;
    retrieved_values := multiset_to_map(b, expected_retrieved_values);
  }

  /*
   * Helpers
   */

  /*
  glinear method obtain_invariant_borrow(gshared token1: Token)
  returns (ghost rest: rw.M)
  ensures rw.Inv(rw.dot(token1.val, rest))
  {
    glinear var v := T.get_unit(token1.loc);
    T.is_valid(token1, inout v);
    Ptrs.dispose_anything(v);
    rest :| rw.Inv(rw.dot(rw.dot(token1.val, v.val), rest));
    rw.dot_unit(token1.val);
  }
  */

  glinear method obtain_invariant_1_1(
      gshared token1: Token,
      glinear inout token2: Token)
  returns (ghost rest: rw.M)
  requires old_token2.loc == token1.loc
  ensures (
    && old_token2 == token2
  )
  ensures rw.Inv(rw.dot(rw.dot(token1.val, token2.val), rest))
  {
    T.is_valid(token1, inout token2);
    rest :| rw.Inv(rw.dot(rw.dot(token1.val, token2.val), rest));
  }

  glinear method obtain_invariant_2_1(
      gshared token1: Token,
      gshared token2: Token,
      glinear inout token3: Token)
  returns (ghost rest: rw.M)
  requires forall r :: pcm.valid(r) && pcm.le(token1.val, r) && pcm.le(token2.val, r) ==> pcm.le(rw.dot(token1.val, token2.val), r)
  requires old_token3.loc == token2.loc == token1.loc
  ensures (
    && old_token3 == token3
  )
  ensures rw.Inv(rw.dot(rw.dot(rw.dot(token1.val, token2.val), token3.val), rest))
  {
    ghost var expected_x := rw.dot(token1.val, token2.val);
    gshared var x := T.join_shared(token1, token2, expected_x);
    T.is_valid(x, inout token3);
    rest :| rw.Inv(rw.dot(rw.dot(rw.dot(token1.val, token2.val), token3.val), rest));
  }

  glinear method obtain_invariant_1_2(
      gshared token1: Token,
      glinear inout token2: Token,
      glinear inout token3: Token)
  returns (ghost rest: rw.M)
  requires old_token3.loc == old_token2.loc == token1.loc
  ensures (
    && old_token2 == token2
    && old_token3 == token3
  )
  ensures rw.Inv(rw.dot(rw.dot(token1.val, rw.dot(token2.val, token3.val)), rest))
  {
    ghost var expected_x := rw.dot(token2.val, token3.val);
    glinear var x := T.join(token2, token3);
    T.is_valid(token1, inout x);
    token2, token3 := T.split(x, token2.val, token3.val);
    rest :| rw.Inv(rw.dot(rw.dot(token1.val, rw.dot(token2.val, token3.val)), rest));
  }

  glinear method obtain_invariant_2(
      glinear inout token1: Token,
      glinear inout token2: Token)
  returns (ghost rest: rw.M)
  requires old_token1.loc == old_token2.loc
  ensures (
    && old_token1 == token1
    && old_token2 == token2
  )
  ensures rw.Inv(rw.dot(rw.dot(token1.val, token2.val), rest))
  {
    T.is_valid(token1, inout token2);
    rest :| rw.Inv(rw.dot(rw.dot(token1.val, token2.val), rest));
  }

  glinear method obtain_invariant_3(
      glinear inout token1: Token,
      glinear inout token2: Token,
      glinear inout token3: Token)
  returns (ghost rest: rw.M)
  requires old_token1.loc == old_token2.loc == old_token3.loc
  ensures (
    && old_token1 == token1
    && old_token2 == token2
    && old_token3 == token3
  )
  ensures rw.Inv(rw.dot(rw.dot(rw.dot(token1.val, token2.val), token3.val), rest))
  {
    glinear var x := T.join(token1, token2);
    T.is_valid(x, inout token3);
    token1, token2 := T.split(x, token1.val, token2.val);
    rest :| rw.Inv(rw.dot(rw.dot(rw.dot(token1.val, token2.val), token3.val), rest));
  }

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
  {
    glinear var x := T.join(token1, token2);
    glinear var y := internal_transition(x,
        rw.dot(expected_value1, expected_value2));
    token1', token2' := T.split(y, expected_value1, expected_value2);
  }

  glinear method internal_transition_1_1_1(
      glinear token1: Token,
      gshared token2: Token,
      ghost expected_value1: rw.M)
  returns (glinear token1': Token)
  requires token1.loc == token2.loc
  requires rw.transition(
      rw.dot(token2.val, token1.val),
      rw.dot(token2.val, expected_value1))
  ensures token1' == T.Token(token1.loc, expected_value1)
  {
    token1' := T.transition_update(token2, token1, expected_value1);
  }

  glinear method internal_transition_2_1_1(
      gshared token1: Token,
      gshared token2: Token,
      glinear token3: Token,
      ghost expected_value3: rw.M)
  returns (glinear token3': Token)
  requires forall r :: pcm.valid(r) && pcm.le(token1.val, r) && pcm.le(token2.val, r) ==> pcm.le(rw.dot(token1.val, token2.val), r)
  requires token1.loc == token2.loc == token3.loc
  requires rw.transition(
      rw.dot(rw.dot(token1.val, token2.val), token3.val),
      rw.dot(rw.dot(token1.val, token2.val), expected_value3))
  ensures token3' == T.Token(token3.loc, expected_value3)
  {
    gshared var x := T.join_shared(token1, token2, rw.dot(token1.val, token2.val));
    token3' := T.transition_update(x, token3, expected_value3);
  }

  glinear method internal_transition_1_2_1(
      gshared token1: Token,
      glinear token2: Token,
      glinear token3: Token,
      ghost expected_value2: rw.M,
      ghost expected_value3: rw.M)
  returns (glinear token2': Token, glinear token3': Token)
  requires token1.loc == token2.loc == token3.loc
  requires rw.transition(
      rw.dot(token1.val, rw.dot(token2.val, token3.val)),
      rw.dot(token1.val, rw.dot(expected_value2, expected_value3)))
  ensures token2' == T.Token(token2.loc, expected_value2)
  ensures token3' == T.Token(token3.loc, expected_value3)
  {
    glinear var x := T.join(token2, token3);
    glinear var x' := T.transition_update(token1, x, rw.dot(expected_value2, expected_value3));
    token2', token3' := T.split(x', expected_value2, expected_value3);
  }

  glinear method deposit_2_2(
      glinear token1: Token,
      glinear token2: Token,
      ghost key: rw.Key,
      glinear stored_value: rw.StoredType,
      ghost expected_value1: rw.M,
      ghost expected_value2: rw.M)
  returns (glinear token1': Token, glinear token2': Token)
  requires token1.loc == token2.loc
  requires rw.deposit(
    rw.dot(token1.val, token2.val),
    rw.dot(expected_value1, expected_value2),
    key, stored_value)
  ensures token1' == T.Token(token1.loc, expected_value1)
  ensures token2' == T.Token(token1.loc, expected_value2)
  {
    glinear var x := T.join(token1, token2);
    glinear var y := deposit(x, key, stored_value, rw.dot(expected_value1, expected_value2));
    token1', token2' := T.split(y, expected_value1, expected_value2);
  }

  glinear method deposit_3_3(
      glinear token1: Token,
      glinear token2: Token,
      glinear token3: Token,
      ghost key: rw.Key,
      glinear stored_value: rw.StoredType,
      ghost expected_value1: rw.M,
      ghost expected_value2: rw.M,
      ghost expected_value3: rw.M)
  returns (glinear token1': Token, glinear token2': Token, glinear token3': Token)
  requires token1.loc == token2.loc == token3.loc
  requires rw.deposit(
    rw.dot(rw.dot(token1.val, token2.val), token3.val),
    rw.dot(rw.dot(expected_value1, expected_value2), expected_value3),
    key, stored_value)
  ensures token1' == T.Token(token1.loc, expected_value1)
  ensures token2' == T.Token(token1.loc, expected_value2)
  ensures token3' == T.Token(token1.loc, expected_value3)
  {
    glinear var x := T.join(token1, token2);
    x := T.join(x, token3);
    glinear var y := deposit(x, key, stored_value,
        rw.dot(rw.dot(expected_value1, expected_value2), expected_value3));
    token1', token2', token3' := split3(y,
        expected_value1, expected_value2, expected_value3);
  }

  glinear method withdraw_3_3(
      glinear token1: Token,
      glinear token2: Token,
      glinear token3: Token,
      ghost expected_value1: rw.M,
      ghost expected_value2: rw.M,
      ghost expected_value3: rw.M,
      ghost key: rw.Key,
      ghost expected_retrieved_value: rw.StoredType)
  returns (glinear token1': Token, glinear token2': Token, glinear token3': Token,
      glinear retrieved_value: rw.StoredType)
  requires token1.loc == token2.loc == token3.loc
  requires rw.withdraw(
      rw.dot(rw.dot(token1.val, token2.val), token3.val),
      rw.dot(rw.dot(expected_value1, expected_value2), expected_value3),
      key, expected_retrieved_value)
  ensures token1' == T.Token(token1.loc, expected_value1)
  ensures token2' == T.Token(token1.loc, expected_value2)
  ensures token3' == T.Token(token1.loc, expected_value3)
  ensures retrieved_value == expected_retrieved_value
  {
    glinear var x := T.join(token1, token2);
    x := T.join(x, token3);
    glinear var y;
    y, retrieved_value := withdraw(x,
        rw.dot(rw.dot(expected_value1, expected_value2), expected_value3),
        key, expected_retrieved_value);
    token1', token2', token3' := split3(y, expected_value1, expected_value2, expected_value3);
  }

  function method {:opaque} borrow_from_guard(gshared f: Token, ghost key: rw.Key, ghost expected: rw.StoredType)
      : (gshared s: rw.StoredType)
  requires rw.guard(f.val, key, expected)
  ensures s == expected
  {
    assert forall p ::
        pcm.I(pcm.dot(f.val, p)).Some? ==> Wrap.le(Wrap.one(expected), pcm.I(pcm.dot(f.val, p)).value)
    by {
      forall p | pcm.I(pcm.dot(f.val, p)).Some?
      ensures Wrap.le(Wrap.one(expected), pcm.I(pcm.dot(f.val, p)).value)
      {
        var sub := rw.I(pcm.dot(f.val, p)) - {key};
        Multisets.ValueMultisetInduct(sub, key, expected);
        assert rw.I(pcm.dot(f.val, p)) == sub[key := expected];
        assert multiset{expected} + Multisets.ValueMultiset(sub)
            == Multisets.ValueMultiset(rw.I(pcm.dot(f.val, p)));
        assert Wrap.dot(Wrap.one(expected), Wrap.M(Multisets.ValueMultiset(sub)))
            == pcm.I(pcm.dot(f.val, p)).value;
        Wrap.dot_unit(Wrap.one(expected));
      }
    }
    WrapT.unwrap_borrow(
      ET.borrow_back(f, Wrap.one(expected))
    )
  }

}
