include "../BlockCacheSystem/BlockCache.i.dfy"
include "../PivotBetree/PivotBetreeSpec.i.dfy"
include "../BlockCacheSystem/AsyncSectorDiskModelTypes.i.dfy"

//
// Attach a BlockCache to a Disk
//

module BlockSystem {
  import M = BlockCache
  import D = BlockDisk

  import opened Maps
  import opened Sequences
  import opened Options
  import opened AsyncSectorDiskModelTypes
  import opened NativeTypes
  import opened DiskLayout
  import opened SectorType
  import opened ViewOp

// begin generated export
  export Spec
    provides *
    reveals CleanCacheEntriesAreCorrect, Crash, CorrectInflightBlockReads, WFDiskGraph, Reference, CorrectInflightIndirectionTableReads, DiskGraph, Graph, RecordedReadRequestNode, disjointWritesFromIndirectionTable, Machine, WriteRequestsAreDistinct, ReadWritesDontOverlap, CorrectInflightBlockRead, ReadWritesAreDistinct, WFDiskGraphOfLoc, NoDanglingPointers, DiskOp, RecordedReadRequestIndirectionTable, DiskChangesPreservesPersistentAndFrozen, RecordedWriteRequestNode, DiskGraphOfLoc, WriteRequestsDontOverlap, Next, RecordedWriteRequestsIndirectionTable, Step, RecordedReadRequestsIndirectionTable, RecordedWriteRequestsNode, CorrectInflightNodeWrites, Node, Variables, RefMapOfDisk, SuccessorsAgree, RecordedWriteRequestIndirectionTable, DiskCacheLookup, CorrectInflightIndirectionTableWrites, WFIndirectionTableWrtDisk, CorrectInflightNodeWrite, Op, WFIndirectionTableRefWrtDisk, HasDiskCacheLookup, Init, WFDiskCacheGraph, RecordedReadRequestsNode, NextStep, DiskCacheGraph
  export extends Spec
// end generated export

  type DiskOp = M.DiskOp

  type Variables = AsyncSectorDiskModelVariables<M.Variables, D.Variables>

  type Reference = M.G.Reference
  type Node = M.G.Node
  type Op = M.Op

  predicate WFIndirectionTableRefWrtDisk(
      indirectionTable: IndirectionTable,
      blocks: imap<Location, Node>,
      ref: Reference)
  requires ref in indirectionTable.locs
  {
    && indirectionTable.locs[ref] in blocks
  }

  predicate WFIndirectionTableWrtDisk(indirectionTable: IndirectionTable, blocks: imap<Location, Node>)
  {
    forall ref | ref in indirectionTable.locs :: 
      indirectionTable.locs[ref] in blocks
  }

  predicate disjointWritesFromIndirectionTable(
      outstandingBlockWrites: map<D.ReqId, M.OutstandingWrite>,
      indirectionTable: IndirectionTable)
  {
    forall req, ref |
        && req in outstandingBlockWrites
        && ref in indirectionTable.locs ::
          outstandingBlockWrites[req].loc != indirectionTable.locs[ref]
  }

  function RefMapOfDisk(
      indirectionTable: IndirectionTable,
      blocks: imap<Location, Node>) : map<Reference, Node>
  requires WFIndirectionTableWrtDisk(indirectionTable, blocks)
  {
    map ref | ref in indirectionTable.locs :: blocks[indirectionTable.locs[ref]]
  }

  function Graph(refs: set<Reference>, refmap: map<Reference, Node>) : imap<Reference, Node>
  requires refs <= refmap.Keys
  {
    imap ref | ref in refs :: refmap[ref]
  }

  predicate WFDiskGraph(indirectionTable: IndirectionTable, blocks: imap<Location, Node>)
  {
    && M.WFCompleteIndirectionTable(indirectionTable)
    && WFIndirectionTableWrtDisk(indirectionTable, blocks)
  }

  function DiskGraph(indirectionTable: IndirectionTable, blocks: imap<Location, Node>) : imap<Reference, Node>
  requires WFDiskGraph(indirectionTable, blocks)
  {
    Graph(indirectionTable.graph.Keys, RefMapOfDisk(indirectionTable, blocks))
  }

  predicate HasDiskCacheLookup(indirectionTable: IndirectionTable, disk: D.Variables, cache: map<Reference, Node>, ref: Reference)
  {
    && WFIndirectionTableWrtDisk(indirectionTable, disk.nodes)
    && (ref !in cache ==>
      && ref in indirectionTable.locs
      && indirectionTable.locs[ref] in disk.nodes
    )
  }

  function DiskCacheLookup(indirectionTable: IndirectionTable, disk: D.Variables, cache: map<Reference, Node>, ref: Reference) : Node
  requires HasDiskCacheLookup(indirectionTable, disk, cache, ref)
  {
    if ref in indirectionTable.locs then
      disk.nodes[indirectionTable.locs[ref]]
    else
      cache[ref]
  }

  predicate WFDiskCacheGraph(indirectionTable: IndirectionTable, disk: D.Variables, cache: map<Reference, Node>)
  {
    && WFIndirectionTableWrtDisk(indirectionTable, disk.nodes)
    && (forall ref | ref in indirectionTable.graph ::
      HasDiskCacheLookup(indirectionTable, disk, cache, ref))
  }

  function DiskCacheGraph(indirectionTable: IndirectionTable, disk: D.Variables, cache: map<Reference, Node>) : imap<Reference, Node>
  requires WFDiskCacheGraph(indirectionTable, disk, cache)
  {
    imap ref | ref in indirectionTable.graph :: DiskCacheLookup(indirectionTable, disk, cache, ref)
  }

  predicate WFDiskGraphOfLoc(
      s: Variables,
      loc: Location)
  {
    && ValidIndirectionTableLocation(loc)
    && loc in s.disk.indirectionTables
    && M.WFCompleteIndirectionTable(
        s.disk.indirectionTables[loc])
    && WFIndirectionTableWrtDisk(
      s.disk.indirectionTables[loc],
      s.disk.nodes)
  }

  predicate NoDanglingPointers(graph: imap<Reference, Node>)
  {
    forall r1, r2 {:trigger r2 in M.G.Successors(graph[r1])}
      | r1 in graph && r2 in M.G.Successors(graph[r1])
      :: r2 in graph
  }

  predicate SuccessorsAgree(succGraph: map<Reference, seq<Reference>>, graph: imap<Reference, Node>)
  {
    && (forall key | key in succGraph :: key in graph)
    && (forall key | key in graph :: key in succGraph)
    && forall ref | ref in succGraph :: (iset r | r in succGraph[ref]) == M.G.Successors(graph[ref])
  }

  /* protected */
  predicate WFSuccs(s: Variables, loc: Location)
  {
    && WFDiskGraphOfLoc(s, loc)
    && SuccessorsAgree(
      s.disk.indirectionTables[loc].graph,
      DiskGraphOfLoc(s, loc))
    && NoDanglingPointers(DiskGraphOfLoc(s, loc))
  }

  function DiskGraphOfLoc(
      s: Variables,
      loc: Location) : imap<Reference, Node>
  requires WFDiskGraphOfLoc(s, loc)
  {
    DiskGraph(s.disk.indirectionTables[loc], s.disk.nodes)
  }

  /* protected */
  function DiskGraphMap(
      s: Variables) : imap<Location, imap<Reference, Node>>
  {
    imap loc | WFSuccs(s, loc)
        :: DiskGraphOfLoc(s, loc)
  }

  /* protected */
  function PersistentLoc(s: Variables) : Option<Location>
  {
    if s.machine.Ready? then 
      Some(s.machine.persistentIndirectionTableLoc)
    else if s.machine.LoadingIndirectionTable? then
      Some(s.machine.indirectionTableLoc)
    else
      None
  }

  /* protected */
  function FrozenLoc(s: Variables) : Option<Location>
  {
    if s.machine.Ready? && s.machine.frozenIndirectionTableLoc.Some?
        && s.machine.outstandingIndirectionTableWrite.None? then (
      s.machine.frozenIndirectionTableLoc
    ) else (
      None
    )
  }

  predicate DiskChangesPreservesPersistentAndFrozen(s: Variables, s': Variables)
  {
    && (PersistentLoc(s).None? ==>
      && forall loc | loc in DiskGraphMap(s) ::
          && loc in DiskGraphMap(s')
          && DiskGraphMap(s')[loc] == DiskGraphMap(s)[loc]
    )
    && (PersistentLoc(s).Some? ==>
      && PersistentLoc(s).value in DiskGraphMap(s)
      && PersistentLoc(s).value in DiskGraphMap(s')
      && DiskGraphMap(s')[PersistentLoc(s).value]
          == DiskGraphMap(s)[PersistentLoc(s).value]
    )
    && (FrozenLoc(s).Some? ==>
      && FrozenLoc(s).value in DiskGraphMap(s)
      && FrozenLoc(s).value in DiskGraphMap(s')
      && DiskGraphMap(s')[FrozenLoc(s).value]
          == DiskGraphMap(s)[FrozenLoc(s).value]
    )
  }

  /* protected */
  predicate WFFrozenGraph(s: Variables)
  {
    && s.machine.Ready?
    && s.machine.frozenIndirectionTable.Some?
    && WFDiskCacheGraph(s.machine.frozenIndirectionTable.value, s.disk, s.machine.cache)
  }

  /* protected */
  function FrozenGraph(s: Variables) : imap<Reference, Node>
  requires WFFrozenGraph(s)
  {
    DiskCacheGraph(s.machine.frozenIndirectionTable.value, s.disk, s.machine.cache)
  }

  /* protected */
  predicate UseFrozenGraph(s: Variables)
  {
    s.machine.Ready? && s.machine.frozenIndirectionTable.Some?
  }

  /* protected */
  function FrozenGraphOpt(s: Variables) : Option<imap<Reference, Node>>
  {
    if WFFrozenGraph(s) then
      Some(FrozenGraph(s))
    else
      None
  }

  /* protected */
  predicate WFLoadingGraph(s: Variables)
  {
    && s.machine.LoadingIndirectionTable?
    && WFDiskGraphOfLoc(s, s.machine.indirectionTableLoc)
  }

  /* protected */
  function LoadingGraph(s: Variables) : imap<Reference, Node>
  requires WFLoadingGraph(s)
  {
    DiskGraphOfLoc(s, s.machine.indirectionTableLoc)
  }

  /* protected */
  predicate WFEphemeralGraph(s: Variables)
  {
    && s.machine.Ready?
    && WFDiskCacheGraph(s.machine.ephemeralIndirectionTable, s.disk, s.machine.cache)
  }

  /* protected */
  function EphemeralGraph(s: Variables) : imap<Reference, Node>
  requires WFEphemeralGraph(s)
  {
    DiskCacheGraph(s.machine.ephemeralIndirectionTable, s.disk, s.machine.cache)
  }

  /* protected */
  function EphemeralGraphOpt(s: Variables) : Option<imap<Reference, Node>>
  {
    if WFEphemeralGraph(s) then
      Some(EphemeralGraph(s))
    else if WFLoadingGraph(s) then
      Some(LoadingGraph(s))
    else
      None
  }

  ///// Init

  predicate Init(s: Variables, loc: Location)
  {
    && M.Init(s.machine)
    && D.Init(s.disk)
    && WFDiskGraphOfLoc(s, loc)
    && SuccessorsAgree(s.disk.indirectionTables[loc].graph, DiskGraphOfLoc(s, loc))
    && NoDanglingPointers(DiskGraphOfLoc(s, loc))
    && DiskGraphOfLoc(s, loc).Keys == iset{M.G.Root()}
    && M.G.Successors(DiskGraphOfLoc(s, loc)[M.G.Root()]) == iset{}
  }

  ////// Next

  datatype Step =
    | MachineStep(dop: DiskOp, machineStep: M.Step)
    | CrashStep
  
  predicate Machine(s: Variables, s': Variables, dop: DiskOp, vop: VOp, machineStep: M.Step)
  {
    && M.NextStep(s.machine, s'.machine, dop, vop, machineStep)
    && D.Next(s.disk, s'.disk, dop)

    // The composite state machine of BlockSystem and JournalSystem
    // will need to provide this condition.
    && (vop.SendPersistentLocOp? ==>
          vop.loc in DiskGraphMap(s))
  }

  predicate Crash(s: Variables, s': Variables, vop: VOp)
  {
    && vop.CrashOp?
    && M.Init(s'.machine)
    && D.Crash(s.disk, s'.disk)
  }

  predicate NextStep(s: Variables, s': Variables, vop: VOp, step: Step)
  {
    match step {
      case MachineStep(dop, machineStep) => Machine(s, s', dop, vop, machineStep)
      case CrashStep => Crash(s, s', vop)
    }
  }

  predicate Next(s: Variables, s': Variables, vop: VOp) {
    exists step :: NextStep(s, s', vop, step)
  }

  ////// Invariants

  predicate CleanCacheEntriesAreCorrect(s: Variables)
  requires s.machine.Ready?
  requires M.WFIndirectionTable(s.machine.ephemeralIndirectionTable)
  requires WFIndirectionTableWrtDisk(s.machine.ephemeralIndirectionTable, s.disk.nodes)
  {
    forall ref | ref in s.machine.cache ::
      ref in s.machine.ephemeralIndirectionTable.locs ==>
        s.machine.cache[ref] == s.disk.nodes[s.machine.ephemeralIndirectionTable.locs[ref]]
  }

  // Any outstanding read we have recorded should be consistent with
  // whatever is in the queue.

  predicate CorrectInflightBlockRead(s: Variables, id: D.ReqId, ref: Reference)
  requires s.machine.Ready?
  {
    && ref !in s.machine.cache
    && ref in s.machine.ephemeralIndirectionTable.locs
    && var loc := s.machine.ephemeralIndirectionTable.locs[ref];
    && loc in s.disk.nodes
    && var sector := s.disk.nodes[loc];
    && (id in s.disk.reqReadNodes ==> s.disk.reqReadNodes[id] == loc)
  }

  predicate CorrectInflightBlockReads(s: Variables)
  requires s.machine.Ready?
  {
    forall id | id in s.machine.outstandingBlockReads ::
      CorrectInflightBlockRead(s, id, s.machine.outstandingBlockReads[id].ref)
  }

  predicate CorrectInflightIndirectionTableReads(s: Variables)
  requires s.machine.LoadingIndirectionTable?
  {
    s.machine.indirectionTableRead.Some? ==> (
      && var reqId := s.machine.indirectionTableRead.value;
      && (reqId in s.disk.reqReadIndirectionTables ==>
        && s.disk.reqReadIndirectionTables[reqId] == s.machine.indirectionTableLoc
      )
    )
  }

  // Any outstanding write we have recorded should be consistent with
  // whatever is in the queue.

  predicate CorrectInflightNodeWrite(s: Variables, id: D.ReqId, ref: Reference, loc: Location)
  requires s.machine.Ready?
  {
    && ValidNodeLocation(loc)
    && (forall r | r in s.machine.ephemeralIndirectionTable.locs ::
        s.machine.ephemeralIndirectionTable.locs[r].addr == loc.addr ==> r == ref)


    && (s.machine.frozenIndirectionTable.Some? ==>
        && (forall r | r in s.machine.frozenIndirectionTable.value.locs ::
          s.machine.frozenIndirectionTable.value.locs[r].addr == loc.addr ==> r == ref)
        && (s.machine.frozenIndirectionTableLoc.Some? ==>
          && (forall r | r in s.machine.frozenIndirectionTable.value.locs ::
            s.machine.frozenIndirectionTable.value.locs[r].addr != loc.addr)
        )
      )

    && (forall r | r in s.machine.persistentIndirectionTable.locs ::
        s.machine.persistentIndirectionTable.locs[r].addr != loc.addr)

    && (id in s.disk.reqWriteNodes ==>
      && s.disk.reqWriteNodes[id] == loc
    )
  }

  predicate CorrectInflightNodeWrites(s: Variables)
  requires s.machine.Ready?
  {
    forall id | id in s.machine.outstandingBlockWrites ::
      CorrectInflightNodeWrite(s, id, s.machine.outstandingBlockWrites[id].ref, s.machine.outstandingBlockWrites[id].loc)
  }

  predicate CorrectInflightIndirectionTableWrites(s: Variables)
  requires s.machine.Ready?
  {
    s.machine.outstandingIndirectionTableWrite.Some? ==> (
      && s.machine.frozenIndirectionTable.Some?
      && var reqId := s.machine.outstandingIndirectionTableWrite.value;
      && s.machine.frozenIndirectionTableLoc.Some?
      && (reqId in s.disk.reqWriteIndirectionTables ==>
          s.disk.reqWriteIndirectionTables[reqId] ==
            s.machine.frozenIndirectionTableLoc.value
      )
    )
  }

  // If there's a write in progress, then the in-memory state must know about it.

  predicate RecordedWriteRequestIndirectionTable(s: Variables, id: D.ReqId)
  {
    && s.machine.Ready?
    && s.machine.outstandingIndirectionTableWrite == Some(id)
  }

  predicate RecordedWriteRequestNode(s: Variables, id: D.ReqId)
  {
    && s.machine.Ready?
    && id in s.machine.outstandingBlockWrites
  }

  predicate RecordedReadRequestIndirectionTable(s: Variables, id: D.ReqId)
  {
    && s.machine.LoadingIndirectionTable?
    && Some(id) == s.machine.indirectionTableRead
  }

  predicate RecordedReadRequestNode(s: Variables, id: D.ReqId)
  {
    && s.machine.Ready?
    && id in s.machine.outstandingBlockReads
  }

  predicate RecordedWriteRequestsIndirectionTable(s: Variables)
  {
    forall id | id in s.disk.reqWriteIndirectionTables :: RecordedWriteRequestIndirectionTable(s, id)
  }

  predicate RecordedWriteRequestsNode(s: Variables)
  {
    forall id | id in s.disk.reqWriteNodes :: RecordedWriteRequestNode(s, id)
  }

  predicate RecordedReadRequestsNode(s: Variables)
  {
    forall id | id in s.disk.reqReadNodes :: RecordedReadRequestNode(s, id)
  }

  predicate RecordedReadRequestsIndirectionTable(s: Variables)
  {
    forall id | id in s.disk.reqReadIndirectionTables :: RecordedReadRequestIndirectionTable(s, id)
  }

  predicate WriteRequestsDontOverlap(reqWrites: map<D.ReqId, Location>)
  {
    forall id1, id2 | id1 in reqWrites && id2 in reqWrites && overlap(reqWrites[id1], reqWrites[id2]) :: id1 == id2
  }

  predicate WriteRequestsAreDistinct(reqWrites: map<D.ReqId, Location>)
  {
    forall id1, id2 | id1 in reqWrites && id2 in reqWrites && reqWrites[id1] == reqWrites[id2] :: id1 == id2
  }

  predicate ReadWritesDontOverlap(
      reqReads: map<D.ReqId, Location>,
      reqWrites: map<D.ReqId, Location>)
  {
    forall id1, id2 | id1 in reqReads && id2 in reqWrites ::
        !overlap(reqReads[id1], reqWrites[id2])
  }

  predicate ReadWritesAreDistinct(
      reqReads: map<D.ReqId, Location>,
      reqWrites: map<D.ReqId, Location>)
  {
    forall id1, id2 | id1 in reqReads && id2 in reqWrites ::
        reqReads[id1] != reqWrites[id2]
  }

  /* protected */
  predicate Inv(s: Variables)
  ensures Inv(s) ==>
    && (s.machine.Ready? ==> EphemeralGraphOpt(s).Some?)
    && M.Inv(s.machine)
  {
    && M.Inv(s.machine)
    && (s.machine.Ready? ==>
      && WFSuccs(s, s.machine.persistentIndirectionTableLoc)
      && (s.machine.frozenIndirectionTable.Some? ==>
        && WFIndirectionTableWrtDisk(s.machine.frozenIndirectionTable.value, s.disk.nodes)
        && SuccessorsAgree(s.machine.frozenIndirectionTable.value.graph, FrozenGraph(s))
      )
      && (s.machine.frozenIndirectionTableLoc.Some? ==>
        && s.machine.frozenIndirectionTable.Some?
        && M.WFCompleteIndirectionTable(s.machine.frozenIndirectionTable.value)
        && s.machine.frozenIndirectionTableLoc.value in s.disk.indirectionTables
        && s.machine.frozenIndirectionTable == Some(s.disk.indirectionTables[s.machine.frozenIndirectionTableLoc.value])
      )
      && s.machine.persistentIndirectionTableLoc in s.disk.indirectionTables
      && s.disk.indirectionTables[s.machine.persistentIndirectionTableLoc]
        == s.machine.persistentIndirectionTable
      && WFIndirectionTableWrtDisk(s.machine.ephemeralIndirectionTable, s.disk.nodes)
      && SuccessorsAgree(s.machine.ephemeralIndirectionTable.graph, EphemeralGraph(s))
      && NoDanglingPointers(EphemeralGraph(s))
      && CleanCacheEntriesAreCorrect(s)
      && CorrectInflightBlockReads(s)
      && CorrectInflightNodeWrites(s)
      && CorrectInflightIndirectionTableWrites(s)
    )
    && (s.machine.LoadingIndirectionTable? ==>
      && CorrectInflightIndirectionTableReads(s)
      && WFLoadingGraph(s)
      && WFSuccs(s, s.machine.indirectionTableLoc)
    )
    && WriteRequestsDontOverlap(s.disk.reqWriteNodes)
    && WriteRequestsAreDistinct(s.disk.reqWriteNodes)
    && ReadWritesDontOverlap(s.disk.reqReadNodes, s.disk.reqWriteNodes)
    && ReadWritesAreDistinct(s.disk.reqReadNodes, s.disk.reqWriteNodes)
    && WriteRequestsDontOverlap(s.disk.reqWriteIndirectionTables)
    && WriteRequestsAreDistinct(s.disk.reqWriteIndirectionTables)
    && ReadWritesDontOverlap(s.disk.reqReadIndirectionTables, s.disk.reqWriteIndirectionTables)
    && ReadWritesAreDistinct(s.disk.reqReadIndirectionTables, s.disk.reqWriteIndirectionTables)
    && RecordedWriteRequestsNode(s)
    && RecordedReadRequestsNode(s)
    && RecordedWriteRequestsIndirectionTable(s)
    && RecordedReadRequestsIndirectionTable(s)
  }

  ////// Proofs

  ////////////////////////////////////////////////////
  ////////////////////// Init
  //////////////////////

  lemma InitGraphs(s: Variables, loc: Location)
    requires Init(s, loc)
    ensures loc in DiskGraphMap(s)
    ensures PersistentLoc(s) == None
    ensures FrozenLoc(s) == None
    ensures EphemeralGraphOpt(s) == None
    ensures FrozenGraphOpt(s) == None
  {
  }
  
  lemma InitGraphsValue(s: Variables, loc: Location)
    requires Init(s, loc)
    ensures loc in DiskGraphMap(s)
    ensures PersistentLoc(s) == None
    ensures FrozenLoc(s) == None
    ensures EphemeralGraphOpt(s) == None
    ensures FrozenGraphOpt(s) == None
    ensures loc in s.disk.indirectionTables
    ensures M.G.Root() in s.disk.indirectionTables[loc].locs
    ensures s.disk.indirectionTables[loc].locs[M.G.Root()]
              in s.disk.nodes
    ensures DiskGraphMap(s)[loc]
        == imap[M.G.Root() :=
            s.disk.nodes[
              s.disk.indirectionTables[loc].locs[M.G.Root()]
            ]
           ]
  {
  }

  lemma InitImpliesInv(s: Variables, loc: Location)
    requires Init(s, loc)
    ensures Inv(s)
  {
    InitGraphs(s, loc);
  }

  ////////////////////////////////////////////////////
  ////////////////////// WriteBackNodeReq
  //////////////////////

  lemma WriteBackNodeReqStepUniqueLBAs(s: Variables, s': Variables, dop: DiskOp, vop: VOp, ref: Reference)
    requires Inv(s)
    requires M.WriteBackNodeReq(s.machine, s'.machine, dop, vop, ref)
    requires D.RecvWriteNode(s.disk, s'.disk, dop);
    ensures WriteRequestsDontOverlap(s'.disk.reqWriteNodes)
    ensures WriteRequestsAreDistinct(s'.disk.reqWriteNodes)
  {
    forall id1 | id1 in s'.disk.reqWriteNodes
    ensures s'.disk.reqWriteNodes[id1] == s'.disk.reqWriteNodes[dop.id]
        ==> id1 == dop.id
    ensures overlap(s'.disk.reqWriteNodes[id1], s'.disk.reqWriteNodes[dop.id])
        ==> id1 == dop.id
    {
      if s'.disk.reqWriteNodes[id1] == s'.disk.reqWriteNodes[dop.id] {
        assert s'.disk.reqWriteNodes[id1].addr == s'.disk.reqWriteNodes[dop.id].addr;
      }
      if overlap(s'.disk.reqWriteNodes[id1], s'.disk.reqWriteNodes[dop.id]) {
        overlappingLocsSameType(
            s'.disk.reqWriteNodes[id1],
            s'.disk.reqWriteNodes[dop.id]);
        overlappingNodesSameAddr(
            s'.disk.reqWriteNodes[id1],
            s'.disk.reqWriteNodes[dop.id]);
      }
    }
  }

  lemma WriteBackNodeReqStepPreservesDiskGraph(s: Variables, s': Variables, dop: DiskOp, vop: VOp, ref: Reference, indirectionTable: IndirectionTable)
    requires Inv(s)
    requires M.WriteBackNodeReq(s.machine, s'.machine, dop, vop, ref)
    requires D.RecvWriteNode(s.disk, s'.disk, dop);

    requires M.WFIndirectionTable(indirectionTable)
    requires WFIndirectionTableWrtDisk(indirectionTable, s.disk.nodes)
    requires dop.reqWriteNode.loc !in indirectionTable.locs.Values

    requires forall r | r in indirectionTable.locs ::
        indirectionTable.locs[r].addr != dop.reqWriteNode.loc.addr

    requires WFDiskGraph(indirectionTable, s.disk.nodes)

    ensures WFDiskGraph(indirectionTable, s'.disk.nodes)
    ensures DiskGraph(indirectionTable, s.disk.nodes)
         == DiskGraph(indirectionTable, s'.disk.nodes)
  {
    forall ref | ref in indirectionTable.locs
    ensures indirectionTable.locs[ref] in s'.disk.nodes
    ensures s.disk.nodes[indirectionTable.locs[ref]]
         == s'.disk.nodes[indirectionTable.locs[ref]]
    {
      if overlap(indirectionTable.locs[ref], dop.reqWriteNode.loc) {
        overlappingNodesSameAddr(indirectionTable.locs[ref], dop.reqWriteNode.loc);
        assert false;
      }
    }
  }

  lemma WriteBackNodeReqStepPreservesDiskCacheGraph(s: Variables, s': Variables, dop: DiskOp, vop: VOp, ref: Reference, indirectionTable: IndirectionTable, indirectionTable': IndirectionTable)
    requires Inv(s)
    requires M.WriteBackNodeReq(s.machine, s'.machine, dop, vop, ref)
    requires D.RecvWriteNode(s.disk, s'.disk, dop);

    requires M.WFIndirectionTable(indirectionTable)
    requires WFIndirectionTableWrtDisk(indirectionTable, s.disk.nodes)
    requires indirectionTable' == M.assignRefToLocation(indirectionTable, ref, dop.reqWriteNode.loc)
    requires M.IndirectionTableCacheConsistent(indirectionTable, s.machine.cache)
    requires dop.reqWriteNode.loc !in indirectionTable.locs.Values

    requires forall r | r in indirectionTable.locs ::
        indirectionTable.locs[r].addr != dop.reqWriteNode.loc.addr

    ensures M.WFIndirectionTable(indirectionTable')
    ensures WFIndirectionTableWrtDisk(indirectionTable', s'.disk.nodes)
    ensures DiskCacheGraph(indirectionTable, s.disk, s.machine.cache)
         == DiskCacheGraph(indirectionTable', s'.disk, s'.machine.cache)
  {
    assert dop.id !in s.disk.reqWriteNodes;

    WriteBackNodeReqStepUniqueLBAs(s, s', dop, vop, ref);

    forall r | r in indirectionTable'.locs
    ensures indirectionTable'.locs[r] in s'.disk.nodes
    {
      if (r == ref && ref !in indirectionTable.locs) {
        assert s'.disk.reqWriteNodes[dop.id] == dop.reqWriteNode.loc;
        assert indirectionTable'.locs[r] in s'.disk.nodes;
      } else {
        assert indirectionTable'.locs[r] in s.disk.nodes;
        if overlap(indirectionTable'.locs[r],
            dop.reqWriteNode.loc) {
          overlappingNodesSameAddr(
            indirectionTable'.locs[r],
            dop.reqWriteNode.loc);
          assert false;
        }
        assert indirectionTable'.locs[r] in s'.disk.nodes;
      }
    }

    forall r | r in indirectionTable.graph
    ensures DiskCacheLookup(indirectionTable, s.disk, s.machine.cache, r)
         == DiskCacheLookup(indirectionTable', s'.disk, s'.machine.cache, r)
    {
      if (r == ref) {
        if ref in indirectionTable'.locs && dop.reqWriteNode.loc == indirectionTable'.locs[ref] {
          //assert DiskMapUpdate(s.disk.nodes, s'.disk.nodes, dop.reqWriteNode.loc, dop.reqWriteNode.node);
          assert dop.reqWriteNode.node == s.machine.cache[ref];
          assert dop.reqWriteNode.loc == indirectionTable'.locs[ref];
          assert DiskCacheLookup(indirectionTable', s'.disk, s'.machine.cache, r)
              == s'.disk.nodes[indirectionTable'.locs[ref]]
              == s.machine.cache[ref]
              == DiskCacheLookup(indirectionTable, s.disk, s.machine.cache, r);
          assert DiskCacheLookup(indirectionTable, s.disk, s.machine.cache, r) == DiskCacheLookup(indirectionTable', s'.disk, s'.machine.cache, r);
        } else {
          if overlap(indirectionTable'.locs[r],
              dop.reqWriteNode.loc) {
            overlappingNodesSameAddr(
              indirectionTable'.locs[r],
              dop.reqWriteNode.loc);
            assert false;
          }

          assert DiskCacheLookup(indirectionTable, s.disk, s.machine.cache, r) == DiskCacheLookup(indirectionTable', s'.disk, s'.machine.cache, r);
        }
      } else if (r in indirectionTable.locs) {
        if overlap(indirectionTable'.locs[r],
            dop.reqWriteNode.loc) {
          overlappingNodesSameAddr(
            indirectionTable'.locs[r],
            dop.reqWriteNode.loc);
          assert false;
        }

        assert DiskCacheLookup(indirectionTable, s.disk, s.machine.cache, r) == DiskCacheLookup(indirectionTable', s'.disk, s'.machine.cache, r);
      } else {

        assert DiskCacheLookup(indirectionTable, s.disk, s.machine.cache, r) == DiskCacheLookup(indirectionTable', s'.disk, s'.machine.cache, r);
      }
    }
  }

  lemma WriteBackNodeReqStepPreservesGraphs(s: Variables, s': Variables, dop: DiskOp, vop: VOp, ref: Reference)
    requires Inv(s)
    requires M.WriteBackNodeReq(s.machine, s'.machine, dop, vop, ref)
    requires D.RecvWriteNode(s.disk, s'.disk, dop);

    ensures DiskChangesPreservesPersistentAndFrozen(s, s')
    ensures FrozenGraphOpt(s') == FrozenGraphOpt(s);
    ensures EphemeralGraphOpt(s') == EphemeralGraphOpt(s);
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures PersistentLoc(s') == PersistentLoc(s)
  {
    WriteBackNodeReqStepPreservesDiskGraph(s, s', dop, vop, ref, s.machine.persistentIndirectionTable);
    WriteBackNodeReqStepPreservesDiskCacheGraph(s, s', dop, vop, ref, s.machine.ephemeralIndirectionTable, s'.machine.ephemeralIndirectionTable);
    if s.machine.frozenIndirectionTable.Some? {
      WriteBackNodeReqStepPreservesDiskCacheGraph(s, s', dop, vop, ref, s.machine.frozenIndirectionTable.value, s'.machine.frozenIndirectionTable.value);
    }

    /*forall ref | ref in s.machine.persistentIndirectionTable.locs
    ensures s.machine.persistentIndirectionTable.locs[ref] in s'.disk.nodes
    {
      if overlap(s.machine.persistentIndirectionTable.locs[ref], dop.reqWriteNode.loc) {
        overlappingNodesSameAddr(s.machine.persistentIndirectionTable.locs[ref], dop.reqWriteNode.loc);
        assert false;
      }
    }*/

    //assert WFDiskGraphOfLoc(s',
    //    s.machine.persistentIndirectionTableLoc);
  }

  lemma WriteBackNodeReqStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp, ref: Reference)
    requires Inv(s)
    requires M.WriteBackNodeReq(s.machine, s'.machine, dop, vop, ref)
    requires D.RecvWriteNode(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    WriteBackNodeReqStepUniqueLBAs(s, s', dop, vop, ref);
    WriteBackNodeReqStepPreservesGraphs(s, s', dop, vop, ref);

    forall id1 | id1 in s'.disk.reqReadNodes
    ensures s'.disk.reqReadNodes[id1] != s'.disk.reqWriteNodes[dop.id]
    ensures !overlap(s'.disk.reqReadNodes[id1], s'.disk.reqWriteNodes[dop.id])
    {
      if overlap(s'.disk.reqReadNodes[id1], s'.disk.reqWriteNodes[dop.id]) {
        overlappingNodesSameAddr(
            s'.disk.reqReadNodes[id1],
            s'.disk.reqWriteNodes[dop.id]);
      }
    }

    forall r | r in s'.machine.cache &&
      r in s'.machine.ephemeralIndirectionTable.locs
    ensures s'.machine.cache[r]
        == s'.disk.nodes[s'.machine.ephemeralIndirectionTable.locs[r]]
    {
      if overlap(s'.machine.ephemeralIndirectionTable.locs[r], dop.reqWriteNode.loc) {
        overlappingNodesSameAddr(s'.machine.ephemeralIndirectionTable.locs[r], dop.reqWriteNode.loc);
      }
    }

  }

  ////////////////////////////////////////////////////
  ////////////////////// WriteBackNodeResp
  //////////////////////

  lemma WriteBackNodeRespStepPreservesGraphs(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.WriteBackNodeResp(s.machine, s'.machine, dop, vop)
    requires D.AckWriteNode(s.disk, s'.disk, dop);

    ensures DiskGraphMap(s') == DiskGraphMap(s)
    ensures FrozenGraphOpt(s') == FrozenGraphOpt(s);
    ensures EphemeralGraphOpt(s') == EphemeralGraphOpt(s);
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures PersistentLoc(s') == PersistentLoc(s)
  {
    if (s.machine.Ready?) {
      assert DiskCacheGraph(s.machine.ephemeralIndirectionTable, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.ephemeralIndirectionTable, s'.disk, s'.machine.cache);
    }
    if (UseFrozenGraph(s)) {
      assert DiskCacheGraph(s.machine.frozenIndirectionTable.value, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.frozenIndirectionTable.value, s'.disk, s'.machine.cache);
    }
  }

  lemma WriteBackNodeRespStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.WriteBackNodeResp(s.machine, s'.machine, dop, vop)
    requires D.AckWriteNode(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    WriteBackNodeRespStepPreservesGraphs(s, s', dop, vop);
  }

  ////////////////////////////////////////////////////
  ////////////////////// WriteBackIndirectionTableReq
  //////////////////////

  lemma WriteBackIndirectionTableReqStepPreservesGraphs(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.WriteBackIndirectionTableReq(s.machine, s'.machine, dop, vop)
    requires D.RecvWriteIndirectionTable(s.disk, s'.disk, dop);

    ensures DiskChangesPreservesPersistentAndFrozen(s, s')
    ensures FrozenGraphOpt(s') == FrozenGraphOpt(s);
    ensures EphemeralGraphOpt(s') == EphemeralGraphOpt(s);
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures PersistentLoc(s') == PersistentLoc(s)
  {
    assert forall id | id in s.disk.reqWriteIndirectionTables :: id in s'.disk.reqWriteIndirectionTables;

    assert WFIndirectionTableWrtDisk(s'.machine.ephemeralIndirectionTable, s'.disk.nodes);

    assert s'.machine.Ready? && s'.machine.frozenIndirectionTable.Some? ==> WFIndirectionTableWrtDisk(s'.machine.frozenIndirectionTable.value, s'.disk.nodes);

    if (s.machine.Ready?) {
      assert DiskCacheGraph(s.machine.ephemeralIndirectionTable, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.ephemeralIndirectionTable, s'.disk, s'.machine.cache);
    }
    if (UseFrozenGraph(s)) {
      assert DiskCacheGraph(s.machine.frozenIndirectionTable.value, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.frozenIndirectionTable.value, s'.disk, s'.machine.cache);
    }

    assert WFDiskGraphOfLoc(s', s'.machine.frozenIndirectionTableLoc.value);
  }

  lemma WriteBackIndirectionTableReqStep_WriteRequestsDontOverlap(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.WriteBackIndirectionTableReq(s.machine, s'.machine, dop, vop)
    requires D.RecvWriteIndirectionTable(s.disk, s'.disk, dop);
    ensures WriteRequestsDontOverlap(s'.disk.reqWriteIndirectionTables)
    ensures WriteRequestsAreDistinct(s'.disk.reqWriteIndirectionTables)
  {
    forall id1 | id1 in s'.disk.reqWriteIndirectionTables
    ensures s'.disk.reqWriteIndirectionTables[id1] == s'.disk.reqWriteIndirectionTables[dop.id]
        ==> id1 == dop.id
    ensures overlap(s'.disk.reqWriteIndirectionTables[id1], s'.disk.reqWriteIndirectionTables[dop.id])
        ==> id1 == dop.id
    {
      if s'.disk.reqWriteIndirectionTables[id1] == s'.disk.reqWriteIndirectionTables[dop.id] {
        assert s'.disk.reqWriteIndirectionTables[id1].addr == s'.disk.reqWriteIndirectionTables[dop.id].addr;
      }
      if overlap(s'.disk.reqWriteIndirectionTables[id1], s'.disk.reqWriteIndirectionTables[dop.id]) {
        overlappingIndirectionTablesSameAddr(
            s'.disk.reqWriteIndirectionTables[id1],
            s'.disk.reqWriteIndirectionTables[dop.id]);
      }
    }
  }

  lemma WriteBackIndirectionTableReqStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.WriteBackIndirectionTableReq(s.machine, s'.machine, dop, vop)
    requires D.RecvWriteIndirectionTable(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    WriteBackIndirectionTableReqStepPreservesGraphs(s, s', dop, vop);
    WriteBackIndirectionTableReqStep_WriteRequestsDontOverlap(s, s', dop, vop);

    forall id1 | id1 in s'.disk.reqReadIndirectionTables
    ensures s'.disk.reqReadIndirectionTables[id1] != s'.disk.reqWriteIndirectionTables[dop.id]
    ensures !overlap(s'.disk.reqReadIndirectionTables[id1], s'.disk.reqWriteIndirectionTables[dop.id])
    {
      assert ValidNodeLocation(s'.disk.reqReadIndirectionTables[id1]);
      if overlap(s'.disk.reqReadIndirectionTables[id1], s'.disk.reqWriteIndirectionTables[dop.id]) {
        overlappingIndirectionTablesSameAddr(
            s'.disk.reqReadIndirectionTables[id1],
            s'.disk.reqWriteIndirectionTables[dop.id]);
      }
    }
  }

  ////////////////////////////////////////////////////
  ////////////////////// WriteBackIndirectionTableResp
  //////////////////////

  lemma WriteBackIndirectionTableRespStepPreservesGraphs(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.WriteBackIndirectionTableResp(s.machine, s'.machine, dop, vop)
    requires D.AckWriteIndirectionTable(s.disk, s'.disk, dop);

    ensures FrozenLoc(s) == None
    ensures FrozenLoc(s') == Some(vop.loc)

    ensures FrozenGraphOpt(s).Some?
    ensures FrozenLoc(s').value in DiskGraphMap(s)
    ensures DiskGraphMap(s)[FrozenLoc(s').value] == FrozenGraphOpt(s).value

    ensures DiskGraphMap(s') == DiskGraphMap(s)
    ensures FrozenGraphOpt(s') == FrozenGraphOpt(s);
    ensures EphemeralGraphOpt(s') == EphemeralGraphOpt(s);
    ensures PersistentLoc(s') == PersistentLoc(s)
  {
    M.WriteBackIndirectionTableRespStepPreservesInv(s.machine, s'.machine, dop, vop);
    if (s.machine.Ready?) {
      assert DiskCacheGraph(s.machine.ephemeralIndirectionTable, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.ephemeralIndirectionTable, s'.disk, s'.machine.cache);
    }
    if (UseFrozenGraph(s)) {
      assert DiskCacheGraph(s.machine.frozenIndirectionTable.value, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.frozenIndirectionTable.value, s'.disk, s'.machine.cache);
    }
  }

  lemma WriteBackIndirectionTableRespStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.WriteBackIndirectionTableResp(s.machine, s'.machine, dop, vop)
    requires D.AckWriteIndirectionTable(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    M.WriteBackIndirectionTableRespStepPreservesInv(s.machine, s'.machine, dop, vop);
    WriteBackIndirectionTableRespStepPreservesGraphs(s, s', dop, vop);
  }

  ////////////////////////////////////////////////////
  ////////////////////// Dirty
  //////////////////////

  lemma DirtyStepUpdatesGraph(s: Variables, s': Variables, ref: Reference, block: Node)
    requires Inv(s)
    requires M.Dirty(s.machine, s'.machine, ref, block)
    requires s.disk == s'.disk

    ensures DiskGraphMap(s') == DiskGraphMap(s)
    ensures FrozenGraphOpt(s') == FrozenGraphOpt(s);
    ensures FrozenLoc(s') == FrozenLoc(s);
    ensures PersistentLoc(s') == PersistentLoc(s);

    ensures EphemeralGraphOpt(s).Some?
    ensures EphemeralGraphOpt(s').Some?
    ensures ref in EphemeralGraphOpt(s).value
    ensures EphemeralGraphOpt(s').value == EphemeralGraphOpt(s).value[ref := block]
    ensures forall key | key in M.G.Successors(block) ::
        key in EphemeralGraphOpt(s).value.Keys
  {
    if (UseFrozenGraph(s')) {
      assert DiskCacheGraph(s.machine.frozenIndirectionTable.value, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.frozenIndirectionTable.value, s'.disk, s'.machine.cache);
    }
  }

  lemma DirtyStepPreservesInv(s: Variables, s': Variables, ref: Reference, block: Node)
    requires Inv(s)
    requires M.Dirty(s.machine, s'.machine, ref, block)
    requires s.disk == s'.disk
    ensures Inv(s')
  {
  }

  ////////////////////////////////////////////////////
  ////////////////////// Alloc
  //////////////////////

  lemma AllocStepUpdatesGraph(s: Variables, s': Variables, ref: Reference, block: Node)
    requires Inv(s)
    requires M.Alloc(s.machine, s'.machine, ref, block)
    requires s.disk == s'.disk

    ensures DiskGraphMap(s') == DiskGraphMap(s)
    ensures FrozenGraphOpt(s') == FrozenGraphOpt(s);
    ensures FrozenLoc(s') == FrozenLoc(s);
    ensures PersistentLoc(s') == PersistentLoc(s);

    ensures EphemeralGraphOpt(s).Some?
    ensures ref !in EphemeralGraphOpt(s).value
    ensures EphemeralGraphOpt(s').value == EphemeralGraphOpt(s).value[ref := block]
    ensures forall key | key in M.G.Successors(block) ::
        key in EphemeralGraphOpt(s).value.Keys
  {
    if (UseFrozenGraph(s)) {
      assert DiskCacheGraph(s.machine.frozenIndirectionTable.value, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.frozenIndirectionTable.value, s'.disk, s'.machine.cache);
    }
  }

  lemma AllocStepPreservesInv(s: Variables, s': Variables, ref: Reference, block: Node)
    requires Inv(s)
    requires M.Alloc(s.machine, s'.machine, ref, block)
    requires s.disk == s'.disk
    ensures Inv(s')
  {
  }

  ////////////////////////////////////////////////////
  ////////////////////// Transaction
  //////////////////////

  lemma OpPreservesInv(s: Variables, s': Variables, op: Op)
    requires Inv(s)
    requires M.OpStep(s.machine, s'.machine, op)
    requires s.disk == s'.disk
    ensures Inv(s')
  {
    match op {
      case WriteOp(ref, block) => DirtyStepPreservesInv(s, s', ref, block);
      case AllocOp(ref, block) => AllocStepPreservesInv(s, s', ref, block);
    }
  }

  lemma OpTransactionPreservesInv(s: Variables, s': Variables, ops: seq<Op>)
    requires Inv(s)
    requires M.OpTransaction(s.machine, s'.machine, ops)
    requires s.disk == s'.disk
    ensures Inv(s')
    decreases |ops|
  {
    if |ops| == 0 {
    } else if |ops| == 1 {
      OpPreservesInv(s, s', ops[0]);
    } else {
      var ops1, smid, ops2 := M.SplitTransaction(s.machine, s'.machine, ops);
      OpTransactionPreservesInv(s, AsyncSectorDiskModelVariables(smid, s.disk), ops1);
      OpTransactionPreservesInv(AsyncSectorDiskModelVariables(smid, s.disk), s', ops2);
    }
  }

  lemma TransactionStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp, ops: seq<Op>)
    requires Inv(s)
    requires M.Transaction(s.machine, s'.machine, dop, vop, ops)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures Inv(s')
    decreases |ops|
  {
    OpTransactionPreservesInv(s, s', ops);
  }

  ////////////////////////////////////////////////////
  ////////////////////// Unalloc
  //////////////////////

  lemma UnallocStepUpdatesGraph(s: Variables, s': Variables, dop: DiskOp, vop: VOp, ref: Reference)
    requires Inv(s)
    requires M.Unalloc(s.machine, s'.machine, dop, vop, ref)
    requires D.Stutter(s.disk, s'.disk, dop);

    ensures DiskGraphMap(s') == DiskGraphMap(s)
    ensures FrozenGraphOpt(s') == FrozenGraphOpt(s);
    ensures PersistentLoc(s') == PersistentLoc(s);
    ensures FrozenLoc(s') == FrozenLoc(s);

    ensures EphemeralGraphOpt(s).Some?
    ensures EphemeralGraphOpt(s').Some?
    ensures EphemeralGraphOpt(s').value == IMapRemove1(EphemeralGraphOpt(s).value, ref)
    ensures ref in EphemeralGraphOpt(s).value
    ensures forall r | r in EphemeralGraphOpt(s).value ::
        ref !in M.G.Successors(EphemeralGraphOpt(s).value[r])
  {
    if (UseFrozenGraph(s)) {
      assert DiskCacheGraph(s.machine.frozenIndirectionTable.value, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.frozenIndirectionTable.value, s'.disk, s'.machine.cache);
    }
  }

  lemma UnallocStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp, ref: Reference)
    requires Inv(s)
    requires M.Unalloc(s.machine, s'.machine, dop, vop, ref)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    /*
    var graph := EphemeralGraph(s);
    var graph' := EphemeralGraph(s');
    var cache := s.machine.cache;
    var cache' := s'.machine.cache;
    */
  }

  ////////////////////////////////////////////////////
  ////////////////////// PageInReq
  //////////////////////

  lemma PageInNodeReqStepPreservesGraphs(s: Variables, s': Variables, dop: DiskOp, vop: VOp, ref: Reference)
    requires Inv(s)
    requires M.PageInNodeReq(s.machine, s'.machine, dop, vop, ref)
    requires D.RecvReadNode(s.disk, s'.disk, dop);

    ensures DiskGraphMap(s') == DiskGraphMap(s)
    ensures FrozenGraphOpt(s') == FrozenGraphOpt(s);
    ensures EphemeralGraphOpt(s') == EphemeralGraphOpt(s);
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures PersistentLoc(s') == PersistentLoc(s)
  {
    if (s.machine.Ready?) {
      assert DiskCacheGraph(s.machine.ephemeralIndirectionTable, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.ephemeralIndirectionTable, s'.disk, s'.machine.cache);
    }
    if (UseFrozenGraph(s)) {
      assert DiskCacheGraph(s.machine.frozenIndirectionTable.value, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.frozenIndirectionTable.value, s'.disk, s'.machine.cache);
    }
  }

  lemma PageInNodeReqStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp, ref: Reference)
    requires Inv(s)
    requires M.PageInNodeReq(s.machine, s'.machine, dop, vop, ref)
    requires D.RecvReadNode(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    PageInNodeReqStepPreservesGraphs(s, s', dop, vop, ref);

    forall id | id in s'.machine.outstandingBlockReads
    ensures CorrectInflightBlockRead(s', id, s'.machine.outstandingBlockReads[id].ref)
    {
    }

    forall id2 | id2 in s'.disk.reqWriteNodes
    ensures dop.loc != s'.disk.reqWriteNodes[id2]
    ensures !overlap(dop.loc, s'.disk.reqWriteNodes[id2])
    {
      if overlap(dop.loc, s'.disk.reqWriteNodes[id2]) {
        overlappingLocsSameType(dop.loc, s'.disk.reqWriteNodes[id2]);
        overlappingNodesSameAddr(dop.loc, s'.disk.reqWriteNodes[id2]);
      }
    }
  }

  ////////////////////////////////////////////////////
  ////////////////////// PageInNodeResp
  //////////////////////

  lemma PageInNodeRespStepPreservesGraphs(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.PageInNodeResp(s.machine, s'.machine, dop, vop)
    requires D.AckReadNode(s.disk, s'.disk, dop);

    ensures DiskGraphMap(s') == DiskGraphMap(s)
    ensures FrozenGraphOpt(s') == FrozenGraphOpt(s);
    ensures EphemeralGraphOpt(s') == EphemeralGraphOpt(s);
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures PersistentLoc(s') == PersistentLoc(s)
  {
    if (s.machine.Ready?) {
      assert DiskCacheGraph(s.machine.ephemeralIndirectionTable, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.ephemeralIndirectionTable, s'.disk, s'.machine.cache);
    }
    if (UseFrozenGraph(s)) {
      assert DiskCacheGraph(s.machine.frozenIndirectionTable.value, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.frozenIndirectionTable.value, s'.disk, s'.machine.cache);
    }
  }

  lemma PageInNodeRespStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.PageInNodeResp(s.machine, s'.machine, dop, vop)
    requires D.AckReadNode(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    PageInNodeRespStepPreservesGraphs(s, s', dop, vop);
  }

  ////////////////////////////////////////////////////
  ////////////////////// PageInIndirectionTableReq
  //////////////////////

  lemma PageInIndirectionTableReqStepPreservesGraphs(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.PageInIndirectionTableReq(s.machine, s'.machine, dop, vop)
    requires D.RecvReadIndirectionTable(s.disk, s'.disk, dop);

    ensures DiskGraphMap(s') == DiskGraphMap(s)
    ensures FrozenGraphOpt(s') == FrozenGraphOpt(s);
    ensures EphemeralGraphOpt(s') == EphemeralGraphOpt(s);
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures PersistentLoc(s') == PersistentLoc(s)
  {
    if (UseFrozenGraph(s)) {
      assert DiskCacheGraph(s.machine.frozenIndirectionTable.value, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.frozenIndirectionTable.value, s'.disk, s'.machine.cache);
    }
  }

  lemma PageInIndirectionTableReqStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.PageInIndirectionTableReq(s.machine, s'.machine, dop, vop)
    requires D.RecvReadIndirectionTable(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    PageInIndirectionTableReqStepPreservesGraphs(s, s', dop, vop);
  }

  ////////////////////////////////////////////////////
  ////////////////////// PageInIndirectionTableResp
  //////////////////////

  lemma PageInIndirectionTableRespStepPreservesGraphs(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.PageInIndirectionTableResp(s.machine, s'.machine, dop, vop)
    requires D.AckReadIndirectionTable(s.disk, s'.disk, dop);

    ensures DiskGraphMap(s') == DiskGraphMap(s)
    ensures FrozenGraphOpt(s') == FrozenGraphOpt(s);
    ensures EphemeralGraphOpt(s') == EphemeralGraphOpt(s);
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures PersistentLoc(s') == PersistentLoc(s)
  {
    assert LoadingGraph(s)
        == EphemeralGraph(s');
  }

  lemma PageInIndirectionTableRespStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.PageInIndirectionTableResp(s.machine, s'.machine, dop, vop)
    requires D.AckReadIndirectionTable(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    PageInIndirectionTableRespStepPreservesGraphs(s, s', dop, vop);
  }

  ////////////////////////////////////////////////////
  ////////////////////// ReceiveLoc
  //////////////////////

  lemma ReceiveLocStepPreservesGraphs(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.ReceiveLoc(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    requires vop.loc in DiskGraphMap(s)

    ensures PersistentLoc(s) == None
    ensures DiskGraphMap(s') == DiskGraphMap(s)
    ensures FrozenGraphOpt(s') == FrozenGraphOpt(s);
    ensures PersistentLoc(s') == Some(vop.loc)
    ensures vop.loc in DiskGraphMap(s)
    ensures EphemeralGraphOpt(s').Some?
    ensures EphemeralGraphOpt(s').value ==
        DiskGraphMap(s)[vop.loc]
    ensures FrozenLoc(s') == FrozenLoc(s)
  {
    assert WFSuccs(s, vop.loc);
    assert WFDiskGraphOfLoc(s, vop.loc);

    if (s.machine.Ready?) {
      assert DiskCacheGraph(s.machine.ephemeralIndirectionTable, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.ephemeralIndirectionTable, s'.disk, s'.machine.cache);
    }
    if (UseFrozenGraph(s)) {
      assert DiskCacheGraph(s.machine.frozenIndirectionTable.value, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.frozenIndirectionTable.value, s'.disk, s'.machine.cache);
    }
  }

  lemma ReceiveLocStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.ReceiveLoc(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    requires WFSuccs(s, vop.loc);
    ensures Inv(s')
  {
    ReceiveLocStepPreservesGraphs(s, s', dop, vop);
  }

  ////////////////////////////////////////////////////
  ////////////////////// Evict
  //////////////////////

  lemma EvictStepPreservesGraphs(s: Variables, s': Variables, dop: DiskOp, vop: VOp, ref: Reference)
    requires Inv(s)
    requires M.Evict(s.machine, s'.machine, dop, vop, ref)
    requires D.Stutter(s.disk, s'.disk, dop);

    ensures DiskGraphMap(s') == DiskGraphMap(s)
    ensures FrozenGraphOpt(s') == FrozenGraphOpt(s);
    ensures EphemeralGraphOpt(s') == EphemeralGraphOpt(s);
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures PersistentLoc(s') == PersistentLoc(s)
  {
    if (s.machine.Ready?) {
      assert DiskCacheGraph(s.machine.ephemeralIndirectionTable, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.ephemeralIndirectionTable, s'.disk, s'.machine.cache);
    }
    if (UseFrozenGraph(s)) {
      assert DiskCacheGraph(s.machine.frozenIndirectionTable.value, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.frozenIndirectionTable.value, s'.disk, s'.machine.cache);
    }
  }

  lemma EvictStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp, ref: Reference)
    requires Inv(s)
    requires M.Evict(s.machine, s'.machine, dop, vop, ref)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    EvictStepPreservesGraphs(s, s', dop, vop, ref);
  }

  ////////////////////////////////////////////////////
  ////////////////////// Freeze
  //////////////////////

  lemma FreezeStepPreservesGraphs(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.Freeze(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures M.Inv(s'.machine);

    ensures DiskGraphMap(s') == DiskGraphMap(s)
    ensures FrozenGraphOpt(s') == EphemeralGraphOpt(s);
    ensures EphemeralGraphOpt(s') == EphemeralGraphOpt(s);
    ensures FrozenLoc(s') == None
    ensures PersistentLoc(s') == PersistentLoc(s)
  {
    M.FreezeStepPreservesInv(s.machine, s'.machine, dop, vop);
  }

  lemma FreezeStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.Freeze(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    FreezeStepPreservesGraphs(s, s', dop, vop);
  }

  ////////////////////////////////////////////////////
  ////////////////////// CleanUp
  //////////////////////

  lemma CleanUpStepPreservesGraphs(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.CleanUp(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures M.Inv(s'.machine);

    ensures DiskGraphMap(s') == DiskGraphMap(s)
    ensures FrozenGraphOpt(s') == None
    ensures EphemeralGraphOpt(s') == EphemeralGraphOpt(s);
    ensures FrozenLoc(s') == None
    ensures PersistentLoc(s') == FrozenLoc(s)
  {
  }

  lemma CleanUpStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.CleanUp(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    M.CleanUpStepPreservesInv(s.machine, s'.machine, dop, vop);
    CleanUpStepPreservesGraphs(s, s', dop, vop);
  }

  ////////////////////////////////////////////////////
  ////////////////////// No-Op
  //////////////////////

  lemma NoOpStepPreservesGraphs(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.NoOp(s.machine, s'.machine, dop, vop)
    requires D.Next(s.disk, s'.disk, dop);

    ensures DiskGraphMap(s') == DiskGraphMap(s)
    ensures FrozenGraphOpt(s') == FrozenGraphOpt(s);
    ensures EphemeralGraphOpt(s') == EphemeralGraphOpt(s);
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures PersistentLoc(s') == PersistentLoc(s)
  {
    if (s.machine.Ready?) {
      assert DiskCacheGraph(s.machine.ephemeralIndirectionTable, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.ephemeralIndirectionTable, s'.disk, s'.machine.cache);
    }
    if (UseFrozenGraph(s)) {
      assert DiskCacheGraph(s.machine.frozenIndirectionTable.value, s.disk, s.machine.cache)
          == DiskCacheGraph(s'.machine.frozenIndirectionTable.value, s'.disk, s'.machine.cache);
    }
  }

  lemma NoOpStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.NoOp(s.machine, s'.machine, dop, vop)
    requires D.Next(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    NoOpStepPreservesGraphs(s, s', dop, vop);
  }

  ////////////////////////////////////////////////////
  ////////////////////// MachineStep
  //////////////////////

  lemma MachineStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp, machineStep: M.Step)
    requires Inv(s)
    requires Machine(s, s', dop, vop, machineStep)
    ensures Inv(s')
  {
    match machineStep {
      case WriteBackNodeReqStep(ref) => WriteBackNodeReqStepPreservesInv(s, s', dop, vop, ref);
      case WriteBackNodeRespStep => WriteBackNodeRespStepPreservesInv(s, s', dop, vop);
      case WriteBackIndirectionTableReqStep => WriteBackIndirectionTableReqStepPreservesInv(s, s', dop, vop);
      case WriteBackIndirectionTableRespStep => WriteBackIndirectionTableRespStepPreservesInv(s, s', dop, vop);
      case UnallocStep(ref) => UnallocStepPreservesInv(s, s', dop, vop, ref);
      case PageInNodeReqStep(ref) => PageInNodeReqStepPreservesInv(s, s', dop, vop, ref);
      case PageInNodeRespStep => PageInNodeRespStepPreservesInv(s, s', dop, vop);
      case PageInIndirectionTableReqStep => PageInIndirectionTableReqStepPreservesInv(s, s', dop, vop);
      case PageInIndirectionTableRespStep => PageInIndirectionTableRespStepPreservesInv(s, s', dop, vop);
      case ReceiveLocStep => ReceiveLocStepPreservesInv(s, s', dop, vop);
      case EvictStep(ref) => EvictStepPreservesInv(s, s', dop, vop, ref);
      case FreezeStep => FreezeStepPreservesInv(s, s', dop, vop);
      case CleanUpStep => CleanUpStepPreservesInv(s, s', dop, vop);
      case NoOpStep => { NoOpStepPreservesInv(s, s', dop, vop); }
      case TransactionStep(ops) => TransactionStepPreservesInv(s, s', dop, vop, ops);
    }
  }

  ////////////////////////////////////////////////////
  ////////////////////// Crash
  //////////////////////

  lemma CrashPreservesGraphs(s: Variables, s': Variables, vop: VOp)
    requires Inv(s)
    requires Crash(s, s', vop)

    ensures DiskChangesPreservesPersistentAndFrozen(s, s')
    ensures FrozenGraphOpt(s') == None
    ensures EphemeralGraphOpt(s') == None
    ensures FrozenLoc(s') == None
    ensures PersistentLoc(s') == None
  {
    if PersistentLoc(s).Some? {
      var persistentLoc := PersistentLoc(s).value;
      if !D.UntouchedLoc(persistentLoc, s.disk.reqWriteIndirectionTables) {
        var id :| id in s.disk.reqWriteIndirectionTables && overlap(persistentLoc, s.disk.reqWriteIndirectionTables[id]);
        overlappingIndirectionTablesSameAddr(
            persistentLoc, s.disk.reqWriteIndirectionTables[id]);
      }
      var indirectionTable := s.disk.indirectionTables[persistentLoc];
      //assert M.WFCompleteIndirectionTable(indirectionTable);
      forall ref | ref in indirectionTable.locs
      ensures indirectionTable.locs[ref] in s.disk.nodes
      ensures indirectionTable.locs[ref] in s'.disk.nodes
      ensures s.disk.nodes[indirectionTable.locs[ref]] == s'.disk.nodes[indirectionTable.locs[ref]]
      {
        var loc := indirectionTable.locs[ref];
        //assert loc in indirectionTable.locs.Values;
        //assert ValidNodeLocation(loc);
        if !D.UntouchedLoc(loc, s.disk.reqWriteNodes) {
          var id :| id in s.disk.reqWriteNodes && overlap(loc, s.disk.reqWriteNodes[id]);
          overlappingNodesSameAddr(
              loc, s.disk.reqWriteNodes[id]);
          assert false;
        }
        //assert loc in s'.disk.nodes;
        //assert s.disk.nodes[loc] == s'.disk.nodes[loc];
      }
    }
    if FrozenLoc(s).Some? {
      var frozenLoc := FrozenLoc(s).value;
      if !D.UntouchedLoc(frozenLoc, s.disk.reqWriteIndirectionTables) {
        var id :| id in s.disk.reqWriteIndirectionTables && overlap(frozenLoc, s.disk.reqWriteIndirectionTables[id]);
        overlappingIndirectionTablesSameAddr(
            frozenLoc, s.disk.reqWriteIndirectionTables[id]);
      }
      var indirectionTable := s.disk.indirectionTables[frozenLoc];
      //assert M.WFCompleteIndirectionTable(indirectionTable);
      forall ref | ref in indirectionTable.locs
      ensures indirectionTable.locs[ref] in s.disk.nodes
      ensures indirectionTable.locs[ref] in s'.disk.nodes
      ensures s.disk.nodes[indirectionTable.locs[ref]] == s'.disk.nodes[indirectionTable.locs[ref]]
      {
        var loc := indirectionTable.locs[ref];
        //assert loc in indirectionTable.locs.Values;
        //assert ValidNodeLocation(loc);
        if !D.UntouchedLoc(loc, s.disk.reqWriteNodes) {
          var id :| id in s.disk.reqWriteNodes && overlap(loc, s.disk.reqWriteNodes[id]);
          overlappingNodesSameAddr(
              loc, s.disk.reqWriteNodes[id]);
          assert false;
        }
        //assert loc in s'.disk.nodes;
        //assert s.disk.nodes[loc] == s'.disk.nodes[loc];
      }

    }
  }

  lemma CrashStepPreservesInv(s: Variables, s': Variables, vop: VOp)
    requires Inv(s)
    requires Crash(s, s', vop)
    ensures Inv(s')
  {
  }

  ////////////////////////////////////////////////////
  ////////////////////// NextStep
  //////////////////////

  lemma NextStepPreservesInv(s: Variables, s': Variables, vop: VOp, step: Step)
    requires Inv(s)
    requires NextStep(s, s', vop, step)
    ensures Inv(s')
  {
    match step {
      case MachineStep(dop, machineStep) => MachineStepPreservesInv(s, s', dop, vop, machineStep);
      case CrashStep => CrashStepPreservesInv(s, s', vop);
    }
  }

  lemma NextPreservesInv(s: Variables, s': Variables, vop: VOp)
    requires Inv(s)
    requires Next(s, s', vop)
    ensures Inv(s')
  {
    var step :| NextStep(s, s', vop, step);
    NextStepPreservesInv(s, s', vop, step);
  }

  /*lemma ReadReqIdIsValid(s: Variables, id: D.ReqId)
  requires Inv(s)
  requires id in s.disk.reqReads
  ensures s.disk.reqReads[id].loc in s.disk.blocks
  {
  }*/

  ////////////////////////////////////////////////////
  ////////////////////// Reads
  //////////////////////

  lemma EphemeralGraphRead(s: Variables, op: M.ReadOp)
  requires Inv(s)
  requires M.ReadStep(s.machine, op)
  ensures EphemeralGraphOpt(s).Some?
  ensures op.ref in EphemeralGraphOpt(s).value
  ensures EphemeralGraphOpt(s).value[op.ref] == op.node
  {
  }

  ////////////////////////////////////////////////////
  ////////////////////// Misc lemma
  //////////////////////

  /*lemma RequestsDontOverlap(s: Variables)
  requires Inv(s)
  ensures WriteRequestsDontOverlap(s.disk.reqWriteNodes)
  ensures ReadWritesDontOverlap(s.disk.reqReadNodes, s.disk.reqWriteNodes)
  ensures WriteRequestsDontOverlap(s.disk.reqWriteIndirectionTables)
  ensures ReadWritesDontOverlap(s.disk.reqReadIndirectionTables, s.disk.reqWriteIndirectionTables)
  {
  }*/

  lemma NewRequestReadNodeDoesntOverlap(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step, id: D.ReqId)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqReadNodeOp?
  requires id in s.disk.reqWriteNodes
  ensures !overlap(dop.loc, s.disk.reqWriteNodes[id])
  {
    if overlap(dop.loc, s.disk.reqWriteNodes[id]) {
      overlappingNodesSameAddr(dop.loc, s.disk.reqWriteNodes[id]);
    }
  }

  lemma NewRequestReadIndirectionTableDoesntOverlap(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step, id: D.ReqId)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqReadIndirectionTableOp?
  requires id in s.disk.reqWriteIndirectionTables
  ensures !overlap(dop.loc, s.disk.reqWriteIndirectionTables[id])
  {
    /*MachineStepPreservesInv(s, s', dop, vop, step);
    assert !overlap(
        s'.disk.reqReadIndirectionTables[dop.id],
        s'.disk.reqWriteIndirectionTables[id]);
    assert !overlap(dop.loc, s'.disk.reqWriteIndirectionTables[id]);*/
  }

  lemma NewRequestWriteNodeDoesntOverlap(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step, id: D.ReqId)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqWriteNodeOp?
  requires id in s.disk.reqWriteNodes
  ensures !overlap(dop.reqWriteNode.loc, s.disk.reqWriteNodes[id])
  {
    if overlap(dop.reqWriteNode.loc, s.disk.reqWriteNodes[id]) {
      overlappingNodesSameAddr(dop.reqWriteNode.loc, s.disk.reqWriteNodes[id]);
    }
  }

  lemma NewRequestWriteIndirectionTableDoesntOverlap(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step, id: D.ReqId)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqWriteIndirectionTableOp?
  requires id in s.disk.reqWriteIndirectionTables
  ensures !overlap(dop.reqWriteIndirectionTable.loc, s.disk.reqWriteIndirectionTables[id])
  {
    /*MachineStepPreservesInv(s, s', dop, vop, step);
    assert !overlap(
        s'.disk.reqWriteIndirectionTables[dop.id],
        s'.disk.reqWriteIndirectionTables[id]);
    assert !overlap(dop.reqWriteNode.loc, s'.disk.reqWriteIndirectionTables[id]);*/
  }

  lemma NewRequestWriteNodeDoesntOverlapRead(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step, id: D.ReqId)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqWriteNodeOp?
  requires id in s.disk.reqReadNodes
  ensures !overlap(dop.reqWriteNode.loc, s.disk.reqReadNodes[id])
  {
    if overlap(dop.reqWriteNode.loc, s.disk.reqReadNodes[id]) {
      overlappingNodesSameAddr(dop.reqWriteNode.loc, s.disk.reqReadNodes[id]);
    }
  }

  lemma NewRequestWriteIndirectionTableDoesntOverlapRead(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step, id: D.ReqId)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqWriteIndirectionTableOp?
  requires id in s.disk.reqReadIndirectionTables
  ensures !overlap(dop.reqWriteIndirectionTable.loc, s.disk.reqReadIndirectionTables[id])
  {
  }

  lemma NewRequestReadNodeIsValid(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqReadNodeOp?
  ensures dop.loc in s.disk.nodes
  {
  }

  lemma NewRequestReadIndirectionTableIsValid(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqReadIndirectionTableOp?
  ensures dop.loc in s.disk.indirectionTables
  {
  }

}
