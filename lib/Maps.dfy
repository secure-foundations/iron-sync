module Maps {

  predicate IMapsTo<K,V>(m: imap<K, V>, k: K, v: V) {
    k in m && m[k] == v
  }
  
  predicate MapsTo<K,V>(m: map<K, V>, k: K, v: V) {
    k in m && m[k] == v
  }

  function {:opaque} MapRemove<K,V>(m:map<K,V>, ks:set<K>) : (m':map<K,V>)
    ensures m'.Keys == m.Keys - ks
    ensures forall j :: j in m' ==> m'[j] == m[j]
  {
    map j | j in m && j !in ks :: m[j]
  }
  
  function {:opaque} IMapRemove<K,V>(m:imap<K,V>, ks:iset<K>) : (m':imap<K,V>)
    ensures m'.Keys == m.Keys - ks
    ensures forall j :: j in m' ==> m'[j] == m[j]
  {
    imap j | j in m && j !in ks :: m[j]
  }
  
	// Requires disjoint domains and delivers predictable result.
	function method {:opaque} MapDisjointUnion<U,T>(mapa: map<U,T>, mapb: map<U,T>) : (mapc: map<U,T>)
		requires mapa.Keys !! mapb.Keys;
		ensures mapc.Keys == mapa.Keys + mapb.Keys;
		ensures forall k :: k in mapa.Keys ==> mapa[k] == mapc[k];
		ensures forall k :: k in mapb.Keys ==> mapb[k] == mapc[k];
	{
		map x : U | (x in mapa.Keys + mapb.Keys) :: if x in mapa then mapa[x] else mapb[x]
	}

	// Doesn't require disjoint domains, but guarantees to take A's
	// definition.
	function method {:opaque} MapUnionPreferA<U,T>(mapa: map<U,T>, mapb: map<U,T>) : (mapc:map<U,T>)
		ensures mapc.Keys == mapa.Keys + mapb.Keys;
    ensures forall k :: k in mapa.Keys ==> mapc[k] == mapa[k];
    ensures forall k :: k in mapb.Keys - mapa.Keys ==> mapc[k] == mapb[k];
    ensures forall k :: k in mapa.Keys && !(k in mapb.Keys) ==> mapc[k] == mapa[k]; // no-set-op translation is easier for Dafny
	{
		map x : U | (x in mapa.Keys + mapb.Keys) :: if x in mapa then mapa[x] else mapb[x]
	}

  function {:opaque} MapUnionPreferB<U,T>(mapa: map<U,T>, mapb: map<U,T>) : (mapc:map<U,T>)
    ensures mapc.Keys == mapa.Keys + mapb.Keys;
    ensures forall k :: k in mapb.Keys ==> mapc[k] == mapb[k];
    ensures forall k :: k in mapa.Keys - mapb.Keys ==> mapc[k] == mapa[k];
    ensures forall k :: k in mapa.Keys && !(k in mapb.Keys) ==> mapc[k] == mapa[k]; // no-set-op translation is easier for Dafny
  {
    map x : U | (x in mapa.Keys + mapb.Keys) :: if x in mapb then mapb[x] else mapa[x]
  }
  
	// Doesn't require disjoint domains, and makes no promises about
	// which it chooses on the intersection.
	function method {:opaque} MapUnion<U,T>(mapa: map<U,T>, mapb: map<U,T>) : (mapc: map<U,T>)
		ensures mapc.Keys == mapa.Keys + mapb.Keys;
		ensures forall k :: k in mapa.Keys -mapb.Keys ==> mapa[k] == mapc[k];
		ensures forall k :: k in mapb.Keys - mapa.Keys ==> mapb[k] == mapc[k];
		ensures forall k :: k in mapa.Keys * mapb.Keys ==>	mapb[k] == mapc[k] || mapa[k] == mapc[k];
	{
		MapUnionPreferA(mapa, mapb)
	}

  function {:opaque} IMapUnionPreferA<U,T>(mapa: imap<U,T>, mapb: imap<U,T>) : (mapc:imap<U,T>)
    ensures mapc.Keys == mapa.Keys + mapb.Keys;
    ensures forall k :: k in mapa.Keys ==> mapc[k] == mapa[k];
    ensures forall k :: k in mapb.Keys - mapa.Keys ==> mapc[k] == mapb[k];
    ensures forall k :: k in mapb.Keys && !(k in mapa.Keys) ==> mapc[k] == mapb[k]; // no-set-op translation is easier for Dafny
  {
    imap x : U | (x in mapa.Keys + mapb.Keys) :: if x in mapa then mapa[x] else mapb[x]
  }

  function {:opaque} IMapUnionPreferB<U,T>(mapa: imap<U,T>, mapb: imap<U,T>) : (mapc:imap<U,T>)
    ensures mapc.Keys == mapa.Keys + mapb.Keys;
    ensures forall k :: k in mapb.Keys ==> mapc[k] == mapb[k];
    ensures forall k :: k in mapa.Keys - mapb.Keys ==> mapc[k] == mapa[k];
    ensures forall k :: k in mapa.Keys && !(k in mapb.Keys) ==> mapc[k] == mapa[k]; // no-set-op translation is easier for Dafny
  {
    imap x : U | (x in mapa.Keys + mapb.Keys) :: if x in mapb then mapb[x] else mapa[x]
  }

	// Doesn't require disjoint domains, and makes no promises about
	// which it chooses on the intersection.
	function {:opaque} IMapUnion<U,T>(mapa: imap<U,T>, mapb: imap<U,T>) : (mapc: imap<U,T>)
		ensures mapc.Keys == mapa.Keys + mapb.Keys;
		ensures forall k :: k in mapa.Keys -mapb.Keys ==> mapa[k] == mapc[k];
		ensures forall k :: k in mapb.Keys - mapa.Keys ==> mapb[k] == mapc[k];
		ensures forall k :: k in mapa.Keys * mapb.Keys ==>	mapb[k] == mapc[k] || mapa[k] == mapc[k];
	{
		IMapUnionPreferA(mapa, mapb)
	}

	// Requires disjoint domains and delivers predictable result.
	function method {:opaque} MapDisjointUnion3<U,T>(mapa: map<U,T>, mapb: map<U,T>, mapc: map<U,T>) : map<U,T>
		requires mapa.Keys !! mapb.Keys !! mapc.Keys;
		ensures MapDisjointUnion3(mapa, mapb, mapc).Keys == mapa.Keys + mapb.Keys + mapc.Keys;
		ensures mapa.Keys != {} || mapb.Keys != {} || mapc.Keys != {} ==> MapDisjointUnion3(mapa, mapb, mapc).Keys != {};
		ensures forall k :: k in mapa.Keys ==> mapa[k] == MapDisjointUnion3(mapa, mapb, mapc)[k];
		ensures forall k :: k in mapb.Keys ==> mapb[k] == MapDisjointUnion3(mapa, mapb, mapc)[k];
		ensures forall k :: k in mapc.Keys ==> mapc[k] == MapDisjointUnion3(mapa, mapb, mapc)[k];
		ensures MapDisjointUnion3(mapa, mapb, mapc) == MapDisjointUnion(mapa, MapDisjointUnion(mapb, mapc))
			                                        == MapDisjointUnion(MapDisjointUnion(mapa, mapb), mapc);
	{
		map x : U | (x in mapa.Keys + mapb.Keys + mapc.Keys) ::
			if x in mapa then mapa[x]
			else if x in mapb then mapb[x]
			else mapc[x]
	}
}