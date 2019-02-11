include "ImmutableDiskTreeInv.dfy"

module ImmutableDiskTreeHeight {
import opened TreeTypes
import opened ImmutableDiskTree
import opened ImmutableDiskTreeInv
import opened MissingLibrary

// A view of a thing we expect to be a tree -- but at this point we're still proving it.
// So it's just a "graph" for now.
datatype GraphView = GraphView(k:Constants, table:Table, view:View)

predicate SaneTableInView(gv:GraphView)
{
    && PlausibleDiskSize(gv.k)
    && WFTable(gv.k, gv.table)
    && AllocatedNbasValid(gv.k, gv.table)
    && FullView(gv.k, gv.view)
    && TableBlocksTypeCorrect(gv.k, gv.view)
    && AllocatedNodeBlocksTypeCorrect(gv.k, gv.view, gv.table)
}

predicate SaneNodeInView(gv:GraphView, addr:TableAddress)
{
    && SaneTableInView(gv)
    && addr in AllocatedAddresses(gv.k, gv.table)
}

function NodeAt(gv:GraphView, addr:TableAddress) : Node
    requires SaneNodeInView(gv, addr)
{
    var nba := TableAt(gv.k, gv.table, addr);
    var lba := LbaForNba(gv.k, nba);
    var sector := gv.view[lba];
    sector.node
}

type Height = Option<int>
type AddrHeightMap = map<TableAddress,int>   // Maps from addresses to height of the tree at that address. Zero is an Unused addr.

predicate LeafNode(node:Node)
{
    forall idx :: ValidSlotIndex(node, idx) ==> !node.slots[idx].Pointer?
}

function HeightForSlot(slot:Slot, heightMap:AddrHeightMap) : (h:Height)
{
    match slot {
        case Empty => Some(1)
        case Value(datum) => Some(1)
        case Pointer(idx) => if idx in heightMap then Some(heightMap[idx]) else None
    }
}

predicate HeightAtMost(height:Height, bound:int)
{
    height.Some? && height.value <= bound
}

predicate AllSlotHeightsAtMost(node:Node, heightMap:AddrHeightMap, slotCount:int, bound:int)
    requires slotCount <= |node.slots|
{
    forall i :: 0<=i<slotCount ==> HeightAtMost(HeightForSlot(node.slots[i], heightMap), bound)
}

function CombineHeights(h1:Height, h2:Height) : Height
{
    if h1.Some? && h2.Some?
    then Some(max(h1.value, h2.value))
    else None
}

predicate WFHeightMap(heightMap:AddrHeightMap)
{
    forall addr :: addr in heightMap ==> 0 <= heightMap[addr]
}

predicate HeightMapNests(gv:GraphView, heightMap:AddrHeightMap)
    requires SaneTableInView(gv)
{
    forall addr, idx :: (
            && addr in AllocatedAddresses(gv.k, gv.table)
            && addr in heightMap
            && ValidSlotIndex(NodeAt(gv, addr), idx)
            && NodeAt(gv, addr).slots[idx].Pointer?
        ) ==> NodeAt(gv, addr).slots[idx].addr in heightMap
}

predicate HeightMapDecreases(gv:GraphView, heightMap:AddrHeightMap)
    requires SaneTableInView(gv)
    requires HeightMapNests(gv, heightMap)
{
    forall addr, idx :: (
            && addr in AllocatedAddresses(gv.k, gv.table)
            && addr in heightMap
            && ValidSlotIndex(NodeAt(gv, addr), idx)
            && NodeAt(gv, addr).slots[idx].Pointer?
        ) ==> heightMap[NodeAt(gv, addr).slots[idx].addr] < heightMap[addr]
}

function {:opaque} DefineHeightNonLeafPrefix(node:Node, heightMap:AddrHeightMap, slotCount:int) : (h:Height)
    requires 0<=slotCount<=|node.slots|
    ensures h.Some? ==> AllSlotHeightsAtMost(node, heightMap, slotCount, h.value)
    ensures h.Some? ==> 0<=h.value
    ensures h.Some? ==> forall slotIdx
        :: ValidSlotIndex(node, slotIdx) && slotIdx < slotCount && node.slots[slotIdx].Pointer?
        ==> node.slots[slotIdx].addr in heightMap
{
    if slotCount==0
    then Some(1)
    else
        CombineHeights(
            DefineHeightNonLeafPrefix(node, heightMap, slotCount-1),
            HeightForSlot(node.slots[slotCount-1], heightMap))
}

function IncrementHeight(h:Height) : Height
{
    match h {
        case None => None
        case Some(n) => Some(n+1)
    }
}

function DefineHeightAddr(gv:GraphView, heightMap:AddrHeightMap, addr:TableAddress) : (h:Height)
    requires SaneNodeInView(gv, addr)
    ensures h.Some? ==> 0<=h.value
{
    if TableAt(gv.k, gv.table, addr).Unused?
    then Some(0)
    else
        var node := NodeAt(gv, addr);
        IncrementHeight(DefineHeightNonLeafPrefix(node, heightMap, |node.slots|))
}

function {:opaque} NewHeights(gv:GraphView, subMap:AddrHeightMap) : (heightMap:AddrHeightMap)
    requires SaneTableInView(gv)
    ensures WFHeightMap(heightMap)
{
    // All the heights we can compute given the subMap below. Caller will
    // discard the duplicates.
    map addr | 
        && addr in AllocatedAddresses(gv.k, gv.table)
        && DefineHeightAddr(gv, subMap, addr).Some?
        :: DefineHeightAddr(gv, subMap, addr).value
}

function {:opaque} SlotHeightMapDef(gv:GraphView, maxHeight:int) : (heightMap:AddrHeightMap)
    requires 0<=maxHeight
    requires SaneTableInView(gv)
    ensures WFHeightMap(heightMap)
    ensures 0<maxHeight ==> SlotHeightMapDef(gv, maxHeight-1).Keys <= SlotHeightMapDef(gv, maxHeight).Keys
    ensures HeightMapNests(gv, heightMap)
    ensures HeightMapDecreases(gv, heightMap)
    decreases maxHeight
{
    reveal_NewHeights();
    if maxHeight == 0
    then
        map addr | addr in ValidAddresses(gv.k) && TableAt(gv.k, gv.table, addr).Unused? :: 0
    else
        var subMap := SlotHeightMapDef(gv, maxHeight-1);
        var unionMap := MapUnionPreferB(NewHeights(gv, subMap), subMap);
        unionMap
}

function SlotHeightMap(gv:GraphView) : AddrHeightMap
    requires SaneTableInView(gv)
{
    SlotHeightMapDef(gv, gv.k.tableEntries)
}

predicate HeightMapComplete(k:Constants, heightMap:AddrHeightMap)
{
    heightMap.Keys == ValidAddresses(k)
}

// If there are no cycles, then every address can be assigned a height.
predicate CycleFree(gv:GraphView, heightMap:AddrHeightMap)
{
    && WFHeightMap(heightMap)
    && SaneTableInView(gv)
    && HeightMapNests(gv, heightMap)
    && HeightMapDecreases(gv, heightMap)
    && HeightMapComplete(gv.k, heightMap)
}

} // module
