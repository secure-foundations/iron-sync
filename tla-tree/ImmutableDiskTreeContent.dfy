include "ImmutableDiskTreeHeight.dfy"

module ImmutableDiskTreeContent {
import opened KVTypes
import opened TreeTypes
import opened ImmutableDiskTreeImpl
import opened ImmutableDiskTreeHeight // TODO not sure we need any of Height ... until GC
import opened MissingLibrary

datatype LookupView = LookupView(k:Constants, table:Table, view:View)

predicate ValidValueLookup(lv:LookupView, lookup:Lookup)
{
    && ValidLookupInView(lv.k, lv.table, lv.view, lookup)
    && TerminalSlot(lookup).Value?
}

function {:opaque} AllValueLookups(lv:LookupView) : iset<Datum>
{
    iset lookup | ValidValueLookup(lv, lookup) :: TerminalSlot(lookup).datum
}

function {:opaque} AllKeys(lv:LookupView) : (keys:iset<Key>)
    ensures forall key :: key in keys ==> exists datum:Datum :: datum in AllValueLookups(lv) && datum.key == key
{
    iset datum | datum in AllValueLookups(lv) :: datum.key
}

function ValueFor(lv:LookupView, key:Key) : Option<Value>
    requires key in AllKeys(lv)
{
    var datum :| datum in AllValueLookups(lv) && datum.key == key;
    Some(datum.value)
}

function {:opaque} ReachableValues(lv:LookupView) : (m:imap<Key, Option<Value>>)
    ensures m.Keys == AllKeys(lv)
{
    imap key | key in AllKeys(lv) :: ValueFor(lv, key)
}

predicate ViewsNest(k:Constants, cacheView:View, throughView:View)
{
    && cacheView.Keys <= throughView.Keys
    && (forall key :: key in cacheView ==> cacheView[key] == throughView[key])
}

lemma ValidLookupInNestedView(k:Constants, table:Table, cacheView:View, diskView:View, lookup:Lookup)
    requires ViewsNest(k, cacheView, diskView)
    requires ValidLookupInView(k, table, cacheView, lookup)
    ensures ValidLookupInView(k, table, diskView, lookup)
{
}

predicate CacheLbasFitOnDisk(k:Constants, s:Variables)
{
    forall lba :: lba in s.cache ==> 0 <= lba < DiskSize(k)
}

predicate DatumsUniqueInView(lv:LookupView, datum1:Datum, datum2:Datum)
{
    datum1 in AllValueLookups(lv) && datum2 in AllValueLookups(lv) && datum1.key == datum2.key
        ==> datum1 == datum2
}

predicate OneDatumPerKeyInv(lv:LookupView)
{
    forall datum1, datum2 :: DatumsUniqueInView(lv, datum1, datum2)
}

// Hidden because the triggers suck and I don't know how to make them better.
predicate {:opaque} LookupsAgreeToLen(l1:Lookup, l2:Lookup, len:nat)
    requires len <= |l1.layers|
    requires len <= |l2.layers|
{
    forall i :: 0<=i<len ==> l1.layers[i] == l2.layers[i]
}

lemma ExploitLookupsAgree(l1:Lookup, l2:Lookup, len:nat, i:nat)
    requires len <= |l1.layers|
    requires len <= |l2.layers|
    requires LookupsAgreeToLen(l1, l2, len)
    requires i < len
    ensures l1.layers[i] == l2.layers[i]
{
    reveal_LookupsAgreeToLen();
}

// l1 and l2 agree out to len,
// and either they disagree on the next element, or one or the other is only len long.
// (If both are len long, then l1==l2==greatest prefix.)
predicate IsGreatestCommonPrefix(l1:Lookup, l2:Lookup, len:nat)
{
    && len <= |l1.layers|
    && len <= |l2.layers|
    && LookupsAgreeToLen(l1, l2, len)
    && (len<|l1.layers| && len<|l2.layers| ==> l1.layers[len]!=l2.layers[len])
}

lemma IsGreatestCommonPrefixIsSymmetric(l1:Lookup, l2:Lookup, len:nat)
    requires IsGreatestCommonPrefix(l1, l2, len)
    ensures IsGreatestCommonPrefix(l2, l1, len)
{
    reveal_LookupsAgreeToLen();
}

function {:opaque} CommonPrefixOfLookups(l1:Lookup, l2:Lookup) : (len:nat)
    ensures IsGreatestCommonPrefix(l1, l2, len)
    decreases |l1.layers|
{
    reveal_LookupsAgreeToLen();
    
    if |l1.layers| == |l2.layers| == 0
    then 0
    else if |l1.layers| == 0 || |l2.layers| == 0
    then 0
    else if l1.layers[0] != l2.layers[0]
    then 0
    else
        CommonPrefixOfLookups(Lookup(l1.layers[1..]), Lookup(l2.layers[1..])) + 1

}

/*
lemma LookupsHonorRanges(lv:LookupView, lookup:Lookup)
    requires ValidValueLookup(lv.k, lv.table, lv.view, lookup)
    ensures 
    TerminalSlot
    ensures RangeBoundForSlotIdx(layer.node, NodeRangeAtLayer(lookup, i), layer.slot) == layer.slotRange
    LEFT OFF HERE
*/

} // module
