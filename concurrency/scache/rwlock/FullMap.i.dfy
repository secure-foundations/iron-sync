include "MapSum.i.dfy"

module FullMaps {
  export S provides HasFiniteSupport, SumFilter, SumFilterSimp, UseZeroSum,
              lemma_zero_map_finite_support, lemma_unit_fn_finite_support,
              lemma_add_fns_finite_support //, lemma_sub_fns_finite_support
           reveals IsFull, FullMap, pre_FullMap, zero_map, unit_fn, add_fns, // sub_fns,
                  zero_map_internal, unit_fn_internal, add_fns_internal //, sub_fns_internal
  export extends S

  import MapSum

  predicate IsFull<K(!new), V>(m: imap<K, V>) {
    forall k :: k in m
  }

  predicate IsFiniteSupport<K(!new)>(m: imap<K, nat>, finite_map: map<K, nat>)
  {
    forall k ::
      && (k in finite_map ==> k in m && m[k] == finite_map[k])
      && (k in m && m[k] != 0 ==> k in finite_map)
  }

  predicate HasFiniteSupport<K(!new)>(m: imap<K, nat>)
  {
    exists finite_map :: IsFiniteSupport(m, finite_map)
  }

  datatype pre_FullMap<K(!new)> = FullMap(ghost m: imap<K, nat>)

  type FullMap<K(!new)> = m : pre_FullMap<K> | IsFull(m.m) && HasFiniteSupport(m.m)
    witness *

  function GetFiniteSupport<K(!new)>(m: FullMap<K>) : map<K, nat>
  requires HasFiniteSupport(m.m)
  {
    var finite_map :| IsFiniteSupport(m.m, finite_map); finite_map
  }

  function zero_map_internal<K(!new)>() : imap<K, nat> {
    imap k {:trigger} | true :: 0
  }

  lemma lemma_zero_map_finite_support<K(!new)>()
  ensures var k: imap<K, nat> := zero_map_internal();
    HasFiniteSupport(k);
  {
    var k: imap<K, nat> := zero_map_internal();
    assert IsFiniteSupport(k, map[]);
  }

  function zero_map<K(!new)>() : FullMap<K> {
    lemma_zero_map_finite_support<K>();
    FullMap(imap k {:trigger} | true :: 0)
  }

  function unit_fn_internal<K(!new)>(a: K) : imap<K, nat> {
    imap k {:trigger} | true :: (if k == a then 1 else 0)
  }

  lemma lemma_unit_fn_finite_support<K(!new)>(a: K)
  ensures HasFiniteSupport(unit_fn_internal(a))
  {
    assert IsFiniteSupport(unit_fn_internal(a), map[a := 1]);
  }

  function unit_fn<K(!new)>(a: K) : FullMap<K> {
    lemma_unit_fn_finite_support(a);
    FullMap(unit_fn_internal(a))
  }

  function add_fns_internal<K(!new)>(f: FullMap<K>, g: FullMap<K>) : imap<K, nat> {
    imap b | true :: f.m[b] + g.m[b]
  }

  lemma lemma_add_fns_finite_support<K(!new)>(f: FullMap<K>, g: FullMap<K>)
  ensures HasFiniteSupport(add_fns_internal(f, g))
  {
    var a := GetFiniteSupport(f);
    var b := GetFiniteSupport(g);

    assert IsFiniteSupport(add_fns_internal(f, g),
        map k | k in a.Keys + b.Keys :: add_fns_internal(f, g)[k]);
  }

  function add_fns<K(!new)>(f: FullMap<K>, g: FullMap<K>) : FullMap<K> {
    lemma_add_fns_finite_support(f, g);
    FullMap(add_fns_internal(f, g))
  }

  /*function sub_fns_internal<K(!new)>(f: FullMap<K>, g: FullMap<K>) : imap<K, nat>
  requires forall i :: f[i] >= g[i]
  {
    imap b | true :: f[b] - g[b]
  }

  lemma lemma_sub_fns_finite_support<K(!new)>(f: FullMap<K>, g: FullMap<K>)
  requires forall i :: f[i] >= g[i]
  ensures HasFiniteSupport(sub_fns_internal(f, g))
  {
    var a := GetFiniteSupport(f);
    var b := GetFiniteSupport(g);

    assert IsFiniteSupport(sub_fns_internal(f, g),
        map k | k in a.Keys + b.Keys :: sub_fns_internal(f, g)[k]);
  }

  function sub_fns<K(!new)>(f: FullMap<K>, g: FullMap<K>) : FullMap<K>
  requires forall i :: f[i] >= g[i]
  ensures add_fns(g, sub_fns(f, g)) == f
  {
    lemma_sub_fns_finite_support(f, g);
    sub_fns_internal(f, g)
  }*/

  function Filter<K(!new)>(fn: (K) -> bool, m: map<K, nat>) : map<K, nat> {
    map k | k in m.Keys && fn(k) :: m[k]
  }

  function SumFilter<K(!new)>(fn: (K) -> bool, f: FullMap<K>) : nat
  requires HasFiniteSupport(f.m)
  {
    MapSum.Sum(Filter(fn, GetFiniteSupport(f)))
  }

  lemma SumFilterAdditive<K(!new)>(fn: (K) -> bool, f: FullMap<K>, g: FullMap<K>)
  ensures SumFilter(fn, add_fns(f, g)) == SumFilter(fn, f) + SumFilter(fn, g)
  {
    MapSum.SumAdditive(Filter(fn, GetFiniteSupport(add_fns(f, g))),
        Filter(fn, GetFiniteSupport(f)),
        Filter(fn, GetFiniteSupport(g)));
  }

  lemma SumFilterSingle<K(!new)>(fn: (K) -> bool, x: K)
  ensures SumFilter(fn, unit_fn(x)) == (if fn(x) then 1 else 0)
  {
    var f := Filter(fn, GetFiniteSupport(unit_fn(x)));
    if fn(x) {
      var f1 := f - {x};
      assert f1[x := f[x]] == f;
      MapSum.SumAllZeroesIsZero(f1);
      MapSum.SumInduct(f1, x, f[x]);
    } else {
      MapSum.SumAllZeroesIsZero(f);
    }
  }

  lemma SumFilterSimp<K(!new)>()
  ensures forall fn: (K) -> bool, f: FullMap<K>, g: FullMap<K>
      {:trigger SumFilter(fn, add_fns(f, g)) } ::
      SumFilter(fn, add_fns(f, g)) == SumFilter(fn, f) + SumFilter(fn, g)

  ensures forall fn: (K) -> bool, x: K
      {:trigger SumFilter(fn, unit_fn(x)) } ::
      SumFilter(fn, unit_fn(x)) == (if fn(x) then 1 else 0)

  ensures forall fn: (K) -> bool
      {:trigger SumFilter(fn, zero_map()) } ::
      SumFilter(fn, zero_map()) == 0
  {
    forall fn: (K) -> bool, f: FullMap<K>, g: FullMap<K>
      ensures SumFilter(fn, add_fns(f, g)) == SumFilter(fn, f) + SumFilter(fn, g)
    {
      SumFilterAdditive(fn, f, g);
    }

    forall fn: (K) -> bool, x: K
    ensures SumFilter(fn, unit_fn(x)) == (if fn(x) then 1 else 0)
    {
      SumFilterSingle(fn, x);
    }

    forall fn: (K) -> bool
    ensures SumFilter(fn, zero_map()) == 0
    {
      var f := Filter(fn, GetFiniteSupport(zero_map()));
      MapSum.SumAllZeroesIsZero(f);
    }
  }

  lemma UseZeroSum<K(!new)>(fn: (K) -> bool, f: FullMap<K>)
  requires HasFiniteSupport(f.m)
  requires SumFilter(fn, f) == 0
  ensures forall x :: fn(x) ==> f.m[x] == 0
  {
    forall x | fn(x) && f.m[x] != 0 ensures false {
      var m := Filter(fn, GetFiniteSupport(f));
      var m1 := m - {x};
      assert m1[x := m[x]] == m;
      MapSum.SumInduct(m1, x, m[x]);
    }
  }
}
