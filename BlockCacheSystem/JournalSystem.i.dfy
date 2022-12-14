include "../BlockCacheSystem/JournalCache.i.dfy"
include "../MapSpec/ThreeStateVersioned.s.dfy"
include "AsyncSectorDiskModelTypes.i.dfy"

//
// Attach a BlockCache to a Disk
//

module JournalSystem {
  import M = JournalCache
  import D = JournalDisk

  import opened Maps
  import opened Sequences
  import opened Options
  import opened AsyncSectorDiskModelTypes
  import opened NativeTypes
  import opened DiskLayout
  import opened SectorType
  import opened JournalRanges
  import opened JournalIntervals
  import opened Journal
  import opened ViewOp
  import opened ThreeStateTypes

// begin generated export
  export Spec
    provides *
    reveals RecordedReadJournalRequests, DiskHasSuperblock2, CorrectInflightJournalWrite, RecordedWriteJournalRequest, RecordedReadJournalRequest, Variables, SyncReqState, CorrectInflightJournalWrites, CorrectInflightSuperblockWrites, Init, FrozenLen, HasLocationUpdateOccurredUnacked, GammaLen, RecordedReadSuperblockRequests, DiskHasSuperblock1, ProcessWriteIsGraphUpdate, Superblock1OfDisk, RecordedWriteSuperblockRequests, DiskHasSuperblock, Superblock2OfDisk, CorrectInflightSuperblockReads, FrozenInterval, FrozenStartPos, GammaStartPos, Crash, RecordedWriteSuperblockRequest, Step, HasUpdateOccurredUnacked, SuperblockOfDisk, Machine, RecordedReadSuperblockRequest, GammaInterval, WriteJournalRequestsDontOverlap, RecordedWriteJournalRequests, CorrectInflightJournalReads, DiskOp, NextStep, ReadWritesJournalDontOverlap, Next, DiskInternal, WFDisk
  export extends Spec
// end generated export

  type DiskOp = M.DiskOp

  type Variables = AsyncSectorDiskModelVariables<M.Variables, D.Variables>

  predicate DiskHasSuperblock1(disk: D.Variables)
  {
    && disk.superblock1.Some?
    && M.WFSuperblock(disk.superblock1.value)
  }

  function Superblock1OfDisk(disk: D.Variables) : (su: Superblock)
  requires DiskHasSuperblock1(disk)
  {
    disk.superblock1.value
  }

  predicate DiskHasSuperblock2(disk: D.Variables)
  {
    && disk.superblock2.Some?
    && M.WFSuperblock(disk.superblock2.value)
  }

  function Superblock2OfDisk(disk: D.Variables) : (su: Superblock)
  requires DiskHasSuperblock2(disk)
  {
    disk.superblock2.value
  }

  predicate DiskHasSuperblock(disk: D.Variables)
  {
    && DiskHasSuperblock1(disk)
    && DiskHasSuperblock2(disk)
  }

  function SuperblockOfDisk(disk: D.Variables) : (su : Superblock)
  requires DiskHasSuperblock(disk)
  ensures M.WFSuperblock(su)
  {
    if DiskHasSuperblock1(disk) && DiskHasSuperblock2(disk) then
      M.SelectSuperblock(Superblock1OfDisk(disk), Superblock2OfDisk(disk))
    else if DiskHasSuperblock1(disk) then
      Superblock1OfDisk(disk)
    else
      Superblock2OfDisk(disk)
  }

  predicate WFDisk(disk: D.Variables)
  {
    && DiskHasSuperblock(disk)
  }

  /* protected */
  predicate WFPersistentJournal(s: Variables)
  {
    && DiskHasSuperblock(s.disk)
    && ValidJournalInterval(JournalInterval(
        SuperblockOfDisk(s.disk).journalStart as int,
        SuperblockOfDisk(s.disk).journalLen as int))
    && Disk_HasJournal(s.disk.journal, JournalInterval(
        SuperblockOfDisk(s.disk).journalStart as int,
        SuperblockOfDisk(s.disk).journalLen as int))
  }

  /* protected */
  function PersistentJournal(s: Variables) : seq<JournalEntry>
  requires WFPersistentJournal(s)
  {
    Disk_Journal(s.disk.journal, JournalInterval(
        SuperblockOfDisk(s.disk).journalStart as int,
        SuperblockOfDisk(s.disk).journalLen as int))
  }

  function FrozenStartPos(s: Variables) : int
  requires DiskHasSuperblock(s.disk)
  {
    if s.machine.Ready? then (
      if s.machine.isFrozen then
        JournalPosAdd(
          s.machine.superblock.journalStart as int,
          s.machine.frozenJournalPosition)
      else
        s.machine.superblock.journalStart as int
    ) else (
      SuperblockOfDisk(s.disk).journalStart as int
    )
  }

  function FrozenLen(s: Variables) : int
  requires DiskHasSuperblock(s.disk)
  {
    if s.machine.Ready? then (
      if s.machine.isFrozen then (
        s.machine.writtenJournalLen - s.machine.frozenJournalPosition
      ) else (
        s.machine.writtenJournalLen
      )
    ) else (
      SuperblockOfDisk(s.disk).journalLen as int
    )
  }

  function FrozenInterval(s: Variables) : JournalInterval
  requires DiskHasSuperblock(s.disk)
  {
    JournalInterval(FrozenStartPos(s), FrozenLen(s))
  }

  /* protected */
  predicate WFFrozenJournal(s: Variables)
  {
    && DiskHasSuperblock(s.disk)
    && ValidJournalInterval(FrozenInterval(s))
    && Disk_HasJournal(s.disk.journal, FrozenInterval(s))
  }

  /* protected */
  function FrozenJournal(s: Variables) : seq<JournalEntry>
  requires WFFrozenJournal(s)
  {
    Disk_Journal(s.disk.journal, FrozenInterval(s))
  }

  /* protected */
  predicate WFEphemeralJournal(s: Variables)
  {
    && WFPersistentJournal(s)
  }

  /* protected */
  function EphemeralJournal(s: Variables) : seq<JournalEntry>
  requires WFEphemeralJournal(s)
  {
    if s.machine.Ready? then (
      s.machine.replayJournal
    ) else (
      PersistentJournal(s)
    )
  }

  function GammaStartPos(s: Variables) : int
  requires DiskHasSuperblock(s.disk)
  {
    SuperblockOfDisk(s.disk).journalStart as int
  }

  predicate HasUpdateOccurredUnacked(s: Variables)
  {
    && s.machine.Ready?
    && s.machine.newSuperblock.Some? 
    && (s.machine.whichSuperblock == 1 ==>
      && s.disk.superblock1 == s.machine.newSuperblock
    )
    && (s.machine.whichSuperblock == 0 ==>
      && s.disk.superblock2 == s.machine.newSuperblock
    )
  }

  predicate HasLocationUpdateOccurredUnacked(s: Variables)
  {
    && HasUpdateOccurredUnacked(s)
    && s.machine.commitStatus.CommitAdvanceLocation?
  }

  function GammaLen(s: Variables) : int
  requires DiskHasSuperblock(s.disk)
  {
    if s.machine.Ready? then
      if HasLocationUpdateOccurredUnacked(s) then
        s.machine.writtenJournalLen - s.machine.frozenJournalPosition
      else
        s.machine.writtenJournalLen
    else
      SuperblockOfDisk(s.disk).journalLen as int
  }

  function GammaInterval(s: Variables) : JournalInterval
  requires DiskHasSuperblock(s.disk)
  {
    JournalInterval(GammaStartPos(s), GammaLen(s))
  }

  /* protected */
  predicate WFGammaJournal(s: Variables)
  {
    && DiskHasSuperblock(s.disk)
    && ValidJournalInterval(GammaInterval(s))
    && Disk_HasJournal(s.disk.journal, GammaInterval(s))
  }

  /* protected */
  function GammaJournal(s: Variables) : seq<JournalEntry>
  requires WFGammaJournal(s)
  {
    if s.machine.Ready? then (
      Disk_Journal(s.disk.journal, GammaInterval(s))
        + s.machine.inMemoryJournalFrozen
    ) else (
      Disk_Journal(s.disk.journal, GammaInterval(s))
    )
  }

  /* protected */
  function DeltaJournal(s: Variables) : seq<JournalEntry>
  {
    if s.machine.Ready? then (
      s.machine.inMemoryJournal
    ) else (
      []
    )
  }

  /* protected */
  predicate WFPersistentLoc(s: Variables)
  {
    && DiskHasSuperblock(s.disk)
  }

  /* protected */
  function PersistentLoc(s: Variables) : Location
  requires WFPersistentLoc(s)
  {
    SuperblockOfDisk(s.disk).indirectionTableLoc
  }

  /* protected */
  function FrozenLoc(s: Variables) : Option<Location>
  {
    if s.machine.Ready? then
      s.machine.frozenLoc
    else
      None
  }

  function SyncReqState(s: Variables, status: M.SyncReqStatus) : SyncReqStatus
  {
    match status {
      case State1 => ThreeStateTypes.State1
      case State2 => (
        // It's possible that the disk has written the superblock but the BlockCache
        // hasn't heard about it yet. In that case, we need to upgrade State2 to State1.
        if HasUpdateOccurredUnacked(s) then
          ThreeStateTypes.State1
        else
          ThreeStateTypes.State2
      )
      case State3 => ThreeStateTypes.State3
    }
  }

  /* protected */
  function SyncReqs(s: Variables) : map<int, SyncReqStatus>
  {
    map id | 0 <= id < 0x1_0000_0000_0000_0000 && id as uint64 in s.machine.syncReqs :: SyncReqState(s, s.machine.syncReqs[id as uint64])
  }

  ///// Init

  predicate Init(s: Variables, loc: Location)
  {
    && M.Init(s.machine)
    && D.Init(s.disk)
    && WFDisk(s.disk)
    && s.disk.superblock1.Some?
    && s.disk.superblock2.Some?
    && SuperblockOfDisk(s.disk).journalStart == 0
    && SuperblockOfDisk(s.disk).journalLen == 0
    && SuperblockOfDisk(s.disk).indirectionTableLoc == loc
  }

  ////// Next

  datatype Step =
    | MachineStep(ghost dop: DiskOp, ghost machineStep: M.Step)
    | DiskInternalStep(ghost step: D.InternalStep)
    | CrashStep
  
  predicate Machine(s: Variables, s': Variables, dop: DiskOp, vop: VOp, machineStep: M.Step)
  {
    && M.NextStep(s.machine, s'.machine, dop, vop, machineStep)
    && D.Next(s.disk, s'.disk, dop)
  }

  predicate DiskInternal(s: Variables, s': Variables, step: D.InternalStep, vop: VOp)
  {
    && s.machine == s'.machine
    && D.NextInternalStep(s.disk, s'.disk, step)
    && vop.JournalInternalOp?
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
      case DiskInternalStep(step) => DiskInternal(s, s', step, vop)
      case CrashStep => Crash(s, s', vop)
    }
  }

  predicate Next(s: Variables, s': Variables, vop: VOp) {
    exists step :: NextStep(s, s', vop, step)
  }

  ////// Invariants

  // Any outstanding read we have recorded should be consistent with
  // whatever is in the queue.

  predicate CorrectInflightJournalReads(s: Variables)
  requires s.machine.LoadingOther?
  requires WFDisk(s.disk)
  {
    && M.WFSuperblock(s.machine.superblock)
    && (s.machine.journalFrontRead.Some? ==> (
      && var reqId := s.machine.journalFrontRead.value;
      && M.JournalFrontIntervalOfSuperblock(s.machine.superblock).Some?
      && (reqId in s.disk.reqReadJournals ==>
          s.disk.reqReadJournals[reqId] == M.JournalFrontIntervalOfSuperblock(s.machine.superblock).value
      )
    ))
    && (s.machine.journalBackRead.Some? ==> (
      && var reqId := s.machine.journalBackRead.value;
      && M.JournalBackIntervalOfSuperblock(s.machine.superblock).Some?
      && (reqId in s.disk.reqReadJournals ==>
          s.disk.reqReadJournals[reqId] == M.JournalBackIntervalOfSuperblock(s.machine.superblock).value
      )
    ))
  }

  predicate CorrectInflightSuperblockReads(s: Variables)
  requires s.machine.LoadingSuperblock?
  {
    true
    /*&& (s.machine.outstandingSuperblock1Read.Some?
      && s.machine.outstandingSuperblock2Read.Some? ==>
        s.machine.outstandingSuperblock1Read.value !=
        s.machine.outstandingSuperblock2Read.value
    ) 
    && (s.machine.outstandingSuperblock1Read.Some? ==> (
      && var reqId := s.machine.outstandingSuperblock1Read.value;
      && s.disk.reqReadSuperblock1 == Some(reqId)
    ))
    && (s.machine.outstandingSuperblock2Read.Some? ==> (
      && var reqId := s.machine.outstandingSuperblock2Read.value;
      && s.disk.reqReadSuperblock2 == Some(reqId)
    ))*/
  }

  // Any outstanding write we have recorded should be consistent with
  // whatever is in the queue.

  predicate CorrectInflightJournalWrite(s: Variables, id: D.ReqId)
  requires s.machine.Ready?
  {
    && (id in s.disk.reqWriteJournals ==>
      && ValidJournalInterval(s.disk.reqWriteJournals[id])

      && s.machine.superblock.journalStart < NumJournalBlocks()
      && s.machine.superblock.journalLen <= NumJournalBlocks()
      && 0 <= s.machine.writtenJournalLen <= NumJournalBlocks() as int
      && 0 <= s.machine.superblock.journalLen <= s.machine.writtenJournalLen as uint64

      && subinterval(s.disk.reqWriteJournals[id],
          JournalInterval(
            JournalPosAdd(s.machine.superblock.journalStart as int,
                s.machine.superblock.journalLen as int),
            s.machine.writtenJournalLen
                - s.machine.superblock.journalLen as int))

      && s.machine.newSuperblock.None?
    )
  }

  predicate CorrectInflightJournalWrites(s: Variables)
  requires s.machine.Ready?
  {
    forall id | id in s.machine.outstandingJournalWrites ::
      CorrectInflightJournalWrite(s, id)
  }

  predicate CorrectInflightSuperblockWrites(s: Variables)
  requires s.machine.Ready?
  {
    s.machine.superblockWrite.Some? ==> (
      && s.machine.newSuperblock.Some?
      && (s.machine.whichSuperblock == 0 || s.machine.whichSuperblock == 1)
      && var reqId := s.machine.superblockWrite.value;
      && (s.machine.whichSuperblock == 0 ==>
        && s.disk.reqWriteSuperblock2 == Some(D.ReqWriteSuperblockId(reqId, D.ReqWriteSuperblock(s.machine.newSuperblock.value)))
      )
      && (s.machine.whichSuperblock == 1 ==>
        && s.disk.reqWriteSuperblock1 == Some(D.ReqWriteSuperblockId(reqId, D.ReqWriteSuperblock(s.machine.newSuperblock.value)))
      )
    )
  }

  // If there's a write in progress, then the in-memory state must know about it.

  predicate RecordedWriteSuperblockRequest(s: Variables, id: D.ReqId)
  {
    && s.machine.Ready?
    && s.machine.superblockWrite == Some(id)
  }

  predicate RecordedWriteJournalRequest(s: Variables, id: D.ReqId)
  {
    && s.machine.Ready?
    && id in s.machine.outstandingJournalWrites
  }

  predicate RecordedReadSuperblockRequest(s: Variables, id: D.ReqId)
  {
    && s.machine.LoadingSuperblock?
    && (
      || Some(id) == s.machine.outstandingSuperblock1Read
      || Some(id) == s.machine.outstandingSuperblock2Read
    )
  }

  predicate RecordedReadJournalRequest(s: Variables, id: D.ReqId)
  {
    && s.machine.LoadingOther?
    && (
      || Some(id) == s.machine.journalFrontRead
      || Some(id) == s.machine.journalBackRead
    )
  }

  predicate RecordedWriteSuperblockRequests(s: Variables)
  {
    && (s.disk.reqWriteSuperblock1.Some? ==>
      RecordedWriteSuperblockRequest(s, s.disk.reqWriteSuperblock1.value.id)
    )
    && (s.disk.reqWriteSuperblock2.Some? ==>
      RecordedWriteSuperblockRequest(s, s.disk.reqWriteSuperblock2.value.id)
    )
    && (s.disk.reqWriteSuperblock1.Some? ==>
        s.disk.reqWriteSuperblock2.Some? ==>
      s.disk.reqWriteSuperblock1.value.id !=
      s.disk.reqWriteSuperblock2.value.id
    )
  }

  predicate RecordedReadSuperblockRequests(s: Variables)
  {
    && (forall id | id in s.disk.reqReadSuperblock1 ::
      RecordedReadSuperblockRequest(s, id)
    )
    && (forall id | id in s.disk.reqReadSuperblock2 ::
      RecordedReadSuperblockRequest(s, id)
    )
    && s.disk.reqReadSuperblock1 !! s.disk.reqReadSuperblock2
  }

  predicate RecordedWriteJournalRequests(s: Variables)
  {
    forall id | id in s.disk.reqWriteJournals :: RecordedWriteJournalRequest(s, id)
  }

  predicate RecordedReadJournalRequests(s: Variables)
  {
    forall id | id in s.disk.reqReadJournals :: RecordedReadJournalRequest(s, id)
  }

  predicate WriteJournalRequestsDontOverlap(reqWrites: map<D.ReqId, JournalInterval>)
  {
    && (forall id | id in reqWrites :: ContiguousJournalInterval(reqWrites[id]))
    && (forall id1, id2 | id1 in reqWrites && id2 in reqWrites
        && journalIntervalOverlap(reqWrites[id1], reqWrites[id2]) :: id1 == id2)
  }

  predicate ReadWritesJournalDontOverlap(
      reqReads: map<D.ReqId, JournalInterval>,
      reqWrites: map<D.ReqId, JournalInterval>)
  {
    && (forall id | id in reqReads :: ContiguousJournalInterval(reqReads[id]))
    && (forall id | id in reqWrites :: ContiguousJournalInterval(reqWrites[id]))
    && (forall id1, id2 | id1 in reqReads && id2 in reqWrites ::
        !journalIntervalOverlap(reqReads[id1], reqWrites[id2]))
  }

  /* protected */
  predicate Inv(s: Variables)
  ensures Inv(s) ==>
    && WFPersistentJournal(s)
    && WFFrozenJournal(s)
    && WFEphemeralJournal(s)
    && WFGammaJournal(s)
    && WFPersistentLoc(s)
    && M.Inv(s.machine)
  {
    && M.Inv(s.machine)
    && WFDisk(s.disk)
    && s.disk.superblock1.Some?
    && s.disk.superblock2.Some?
    && (s.machine.Ready? ==>
      && (
        || s.machine.superblock == SuperblockOfDisk(s.disk)
        || s.machine.newSuperblock == Some(SuperblockOfDisk(s.disk))
      )
      && (s.machine.newSuperblock.Some? ==>
        && (s.machine.commitStatus.CommitAdvanceLocation? ==> (
          && s.machine.frozenLoc.Some?
          && s.machine.newSuperblock.value.indirectionTableLoc ==
                s.machine.frozenLoc.value
        ))
      )
      && CorrectInflightJournalWrites(s)
      && CorrectInflightSuperblockWrites(s)
      && (s.machine.whichSuperblock == 0 ==> (
        && s.disk.superblock1 == Some(s.machine.superblock)
      ))
      && (s.machine.whichSuperblock == 1 ==> (
        && s.disk.superblock2 == Some(s.machine.superblock)
      ))
    )
    && (s.machine.LoadingSuperblock? ==>
      && CorrectInflightSuperblockReads(s)
      && (s.machine.superblock1.SuperblockSuccess? ==>
        && DiskHasSuperblock1(s.disk)
        && s.machine.superblock1.value == Superblock1OfDisk(s.disk)
        && s.machine.outstandingSuperblock1Read.None?
      )
      && (s.machine.superblock2.SuperblockSuccess? ==>
        && DiskHasSuperblock2(s.disk)
        && s.machine.superblock2.value == Superblock2OfDisk(s.disk)
        && s.machine.outstandingSuperblock2Read.None?
      )
    )
    && (s.machine.LoadingOther? ==>
      && s.machine.superblock == SuperblockOfDisk(s.disk)
      && CorrectInflightJournalReads(s)
      && (s.machine.journalFrontRead.Some? && s.machine.journalBackRead.Some?
          ==> s.machine.journalFrontRead.value != s.machine.journalBackRead.value)
      && (s.machine.journalFront.Some? ==> (
        && s.machine.journalFrontRead.None?
        && M.JournalFrontIntervalOfSuperblock(s.machine.superblock).Some?
        && Disk_HasJournalRange(s.disk.journal, M.JournalFrontIntervalOfSuperblock(s.machine.superblock).value)
        && s.machine.journalFront == Some(Disk_JournalRange(s.disk.journal, M.JournalFrontIntervalOfSuperblock(s.machine.superblock).value))
      ))
      && (s.machine.journalBack.Some? ==> (
        && s.machine.journalBackRead.None?
        && M.JournalBackIntervalOfSuperblock(s.machine.superblock).Some?
        && Disk_HasJournalRange(s.disk.journal, M.JournalBackIntervalOfSuperblock(s.machine.superblock).value)
        && s.machine.journalBack == Some(Disk_JournalRange(s.disk.journal, M.JournalBackIntervalOfSuperblock(s.machine.superblock).value))
      ))
      && (M.JournalFrontIntervalOfSuperblock(s.machine.superblock).None? ==> (
        && s.machine.journalFrontRead.None?
        && s.machine.journalFront.None?
      ))
      && (M.JournalBackIntervalOfSuperblock(s.machine.superblock).None? ==> (
        && s.machine.journalBackRead.None?
        && s.machine.journalBack.None?
      ))
      && (s.machine.whichSuperblock == 0 ==> (
        && s.disk.superblock1 == Some(s.machine.superblock)
      ))
      && (s.machine.whichSuperblock == 1 ==> (
        && s.disk.superblock2 == Some(s.machine.superblock)
      ))
    )
    && WriteJournalRequestsDontOverlap(s.disk.reqWriteJournals)
    && ReadWritesJournalDontOverlap(s.disk.reqReadJournals, s.disk.reqWriteJournals)
    && RecordedWriteSuperblockRequests(s)
    && RecordedWriteJournalRequests(s)
    && RecordedReadSuperblockRequests(s)
    && RecordedReadJournalRequests(s)
    && WFPersistentJournal(s)
    && WFFrozenJournal(s)
    && WFEphemeralJournal(s)
    && WFGammaJournal(s)
    && |s.disk.journal| == NumJournalBlocks() as int
  }

  ////// Proofs

  ////////////////////////////////////////////////////
  ////////////////////// Init
  //////////////////////

  lemma InitJournals(s: Variables, loc: Location)
    requires Init(s, loc)
    ensures WFPersistentJournal(s)
    ensures WFFrozenJournal(s)
    ensures WFEphemeralJournal(s)
    ensures WFGammaJournal(s)
    ensures WFPersistentLoc(s)
    ensures PersistentJournal(s) == []
    ensures FrozenJournal(s) == []
    ensures EphemeralJournal(s) == []
    ensures DeltaJournal(s) == []
    ensures GammaJournal(s) == []
    ensures PersistentLoc(s) == loc
    ensures FrozenLoc(s) == None
    ensures SyncReqs(s) == map[]
  {
    Disk_Journal_empty(s.disk.journal, 0);
  }

  lemma InitImpliesInv(s: Variables, loc: Location)
    requires Init(s, loc)
    ensures Inv(s)
    ensures loc == PersistentLoc(s)
  {
    InitJournals(s, loc);
  }

  ////////////////////////////////////////////////////
  ////////////////////// WriteBackJournalReq
  //////////////////////

  lemma WriteBackJournalReqStep_WriteRequestsDontOverlap(s: Variables, s': Variables, dop: DiskOp, vop: VOp, jr: JournalRange)
    requires Inv(s)
    requires M.WriteBackJournalReq(s.machine, s'.machine, dop, vop, jr)
    requires D.RecvWriteJournal(s.disk, s'.disk, dop)
    ensures WriteJournalRequestsDontOverlap(s'.disk.reqWriteJournals)
  {
    /*var interval := JournalInterval(dop.reqWriteJournal.start, |dop.reqWriteJournal.journal|);

    assert ContiguousJournalInterval(s'.disk.reqWriteJournals[dop.id1]);
    forall id | id in s'.disk.reqWriteJournals
    //ensures s'.disk.reqWriteJournals[id] == s'.disk.reqWriteJournals[dop.id1] ==> id == dop.id1
    ensures journalIntervalOverlap(s'.disk.reqWriteJournals[id], s'.disk.reqWriteJournals[dop.id1])
        ==> id == dop.id1
    ensures dop.id2.Some? ==>
      journalIntervalOverlap(s'.disk.reqWriteJournals[id], s'.disk.reqWriteJournals[dop.id2.value])
        ==> id == dop.id2.value
    {
      /*if id in s.disk.reqWriteJournals {
        assert subinterval(s'.disk.reqWriteJournals[id],
            JournalInterval(
              JournalPosAdd(s.machine.superblock.journalStart as int,
                  s.machine.superblock.journalLen as int),
              s.machine.writtenJournalLen
                  - s.machine.superblock.journalLen as int));

        if interval.start + interval.len <= NumJournalBlocks() as int {
          assert !journalIntervalOverlap(s'.disk.reqWriteJournals[id], interval);
        } else {
          var interval1 := JournalInterval(interval.start, NumJournalBlocks() as int - interval.start);
          var interval2 := JournalInterval(0, interval.len - (NumJournalBlocks() as int - interval.start));
          assert !journalIntervalOverlap(s'.disk.reqWriteJournals[id], interval1);
          assert !journalIntervalOverlap(s'.disk.reqWriteJournals[id], interval2);
        }
      }*/
    }*/
  }

  lemma WriteBackJournalReqStepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp, jr: JournalRange)
    requires Inv(s)
    requires M.WriteBackJournalReq(s.machine, s'.machine, dop, vop, jr)
    requires D.RecvWriteJournal(s.disk, s'.disk, dop)

    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures !(s.machine.Ready? && s.machine.inMemoryJournalFrozen == []) ==> (
        && FrozenJournal(s') == FrozenJournal(s)
        && GammaJournal(s') == GammaJournal(s)
        && DeltaJournal(s') == DeltaJournal(s)
        && SyncReqs(s') == SyncReqs(s)
      )
    ensures (s.machine.Ready? && s.machine.inMemoryJournalFrozen == []) ==> (
        && FrozenJournal(s') == FrozenJournal(s) + DeltaJournal(s)
        && GammaJournal(s') == GammaJournal(s) + DeltaJournal(s)
        && DeltaJournal(s') == []
        && SyncReqs(s') == SyncReqs3to2(SyncReqs(s))
      )
    ensures EphemeralJournal(s') == EphemeralJournal(s)

    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == FrozenLoc(s)
  {
    assert HasUpdateOccurredUnacked(s)
        == HasUpdateOccurredUnacked(s');

    WriteBackJournalReqStep_WriteRequestsDontOverlap(s, s', dop, vop, jr);

    var interval := JournalInterval(dop.reqWriteJournal.start,
        |dop.reqWriteJournal.journal|);

    Disk_Journal_append(s.disk.journal, s'.disk.journal, FrozenInterval(s), interval, dop.reqWriteJournal.journal);
    assert SuperblockOfDisk(s.disk).journalStart
        == SuperblockOfDisk(s'.disk).journalStart;

    var persistentInterval := JournalInterval(
        SuperblockOfDisk(s.disk).journalStart as int,
        SuperblockOfDisk(s.disk).journalLen as int);
    Disk_Journal_preserves(s.disk.journal, s'.disk.journal, persistentInterval, interval, dop.reqWriteJournal.journal);

    //assert FrozenStartPos(s') == FrozenStartPos(s);
    //assert FrozenLen(s') == FrozenLen(s) + JournalRangeLen(jr);

    Disk_Journal_append(s.disk.journal, s'.disk.journal, GammaInterval(s), interval, dop.reqWriteJournal.journal);

    if s.machine.inMemoryJournalFrozen != [] {
      assert s.machine.isFrozen;
      assert s.machine.frozenJournalPosition
          == s.machine.writtenJournalLen;

      Disk_Journal_empty(s.disk.journal, FrozenStartPos(s));
      Disk_Journal_empty(s'.disk.journal, FrozenStartPos(s'));

      assert FrozenLen(s) == 0;
      assert FrozenLen(s') == 0;

      assert FrozenJournal(s') == FrozenJournal(s);
      assert GammaJournal(s') == GammaJournal(s);
      assert DeltaJournal(s') == DeltaJournal(s);
    } else {
      assert FrozenJournal(s') == FrozenJournal(s) + DeltaJournal(s);
      assert GammaJournal(s') == GammaJournal(s) + DeltaJournal(s);
      assert DeltaJournal(s') == [];
    }
  }

  lemma WriteBackJournalReqStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp, jr: JournalRange)
    requires Inv(s)
    requires M.WriteBackJournalReq(s.machine, s'.machine, dop, vop, jr)
    requires D.RecvWriteJournal(s.disk, s'.disk, dop)
    ensures Inv(s')
  {
    //assert s'.machine.superblockWrite == s.machine.superblockWrite;
    //assert s'.disk.reqWriteSuperblock1 == s.disk.reqWriteSuperblock1;
    //assert s'.disk.reqWriteSuperblock2 == s.disk.reqWriteSuperblock2;
    if s'.disk.reqWriteSuperblock2.Some? {
      assert RecordedWriteSuperblockRequest(s', s'.disk.reqWriteSuperblock2.value.id); // ???
    }

    WriteBackJournalReqStepPreservesJournals(s, s', dop, vop, jr);
    WriteBackJournalReqStep_WriteRequestsDontOverlap(s, s', dop, vop, jr);

    forall id1 | id1 in s'.disk.reqReadJournals
    ensures s'.disk.reqReadJournals[id1] != s'.disk.reqWriteJournals[dop.id]
    ensures !journalIntervalOverlap(s'.disk.reqReadJournals[id1], s'.disk.reqWriteJournals[dop.id])
    {
    }

    /*assert s.machine.superblock.journalStart < NumJournalBlocks();
    assert s.machine.superblock.journalLen <= NumJournalBlocks();
    assert 0 <= s.machine.writtenJournalLen <= NumJournalBlocks() as int;
    assert 0 <= s.machine.superblock.journalLen <= s.machine.writtenJournalLen as uint64;

    forall id | id in s'.machine.outstandingJournalWrites
    ensures CorrectInflightJournalWrite(s', id)
    {
      if id == dop.id {
        var startPos := JournalPosAdd(
          s.machine.superblock.journalStart as int,
          s.machine.writtenJournalLen);


        if JournalPosAdd(s.machine.superblock.journalStart as int,
                s.machine.superblock.journalLen as int) + 
              s.machine.writtenJournalLen + JournalRangeLen(jr)
                  - s.machine.superblock.journalLen as int
              <= NumJournalBlocks() as int {

          assert JournalPosAdd(s.machine.superblock.journalStart as int,
                    s.machine.writtenJournalLen) as uint64
              >= JournalPosAdd(s.machine.superblock.journalStart as int,
                    s.machine.superblock.journalLen as int) as uint64;

          assert JournalPoint(startPos as uint64) as uint64
              >= JournalPoint(JournalPosAdd(s.machine.superblock.journalStart as int,
                    s.machine.superblock.journalLen as int) as uint64);

          assert JournalRangeLocation(startPos as uint64, JournalRangeLen(jr) as uint64).addr
              >= JournalPoint(JournalPosAdd(s.machine.superblock.journalStart as int,
                    s.machine.superblock.journalLen as int) as uint64);
        }

        assert locContainedInCircularJournalRange(
            JournalRangeLocation(startPos as uint64, JournalRangeLen(jr) as uint64),
            JournalPosAdd(s.machine.superblock.journalStart as int,
                s.machine.superblock.journalLen as int) as uint64,
            s.machine.writtenJournalLen as uint64 + JournalRangeLen(jr) as uint64
                - s.machine.superblock.journalLen);

        assert locContainedInCircularJournalRange(
            JournalRangeLocation(startPos as uint64, JournalRangeLen(jr) as uint64),
            JournalPosAdd(s'.machine.superblock.journalStart as int,
                s'.machine.superblock.journalLen as int) as uint64,
            s'.machine.writtenJournalLen as uint64
                - s.machine.superblock.journalLen);


        assert CorrectInflightJournalWrite(s', id);
      } else {
        assert CorrectInflightJournalWrite(s', id);
      }
    }*/
  }

  ////////////////////////////////////////////////////
  ////////////////////// WriteBackJournalResp
  //////////////////////

  lemma WriteBackJournalRespStepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.WriteBackJournalResp(s.machine, s'.machine, dop, vop)
    requires D.AckWriteJournal(s.disk, s'.disk, dop);
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures FrozenJournal(s') == FrozenJournal(s)
    ensures EphemeralJournal(s') == EphemeralJournal(s)
    ensures GammaJournal(s') == GammaJournal(s)
    ensures DeltaJournal(s') == DeltaJournal(s)

    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures SyncReqs(s') == SyncReqs(s)
  {
  }

  lemma WriteBackJournalRespStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.WriteBackJournalResp(s.machine, s'.machine, dop, vop)
    requires D.AckWriteJournal(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    WriteBackJournalRespStepPreservesJournals(s, s', dop, vop);

    if s'.disk.reqWriteSuperblock2.Some? {
      assert RecordedWriteSuperblockRequest(s', s'.disk.reqWriteSuperblock2.value.id); // ???
    }
  }

  ////////////////////////////////////////////////////
  ////////////////////// WriteBackSuperblockReq_AdvanceLog
  //////////////////////

  lemma WriteBackSuperblockReq_AdvanceLog_StepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.WriteBackSuperblockReq_AdvanceLog(s.machine, s'.machine, dop, vop)
    requires D.RecvWriteSuperblock(s.disk, s'.disk, dop);
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures FrozenJournal(s') == FrozenJournal(s)
    ensures EphemeralJournal(s') == EphemeralJournal(s)
    ensures GammaJournal(s') == GammaJournal(s)
    ensures DeltaJournal(s') == DeltaJournal(s)

    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures SyncReqs(s') == SyncReqs(s)
  {
  }

  lemma WriteBackSuperblockReq_AdvanceLog_StepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.WriteBackSuperblockReq_AdvanceLog(s.machine, s'.machine, dop, vop)
    requires D.RecvWriteSuperblock(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    WriteBackSuperblockReq_AdvanceLog_StepPreservesJournals(s, s', dop, vop);
  }

  ////////////////////////////////////////////////////
  ////////////////////// WriteBackSuperblockReq_AdvanceLocation
  //////////////////////

  lemma WriteBackSuperblockReq_AdvanceLocation_StepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.WriteBackSuperblockReq_AdvanceLocation(s.machine, s'.machine, dop, vop)
    requires D.RecvWriteSuperblock(s.disk, s'.disk, dop);
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures FrozenJournal(s') == FrozenJournal(s)
    ensures EphemeralJournal(s') == EphemeralJournal(s)
    ensures GammaJournal(s') == GammaJournal(s)
    ensures DeltaJournal(s') == DeltaJournal(s)

    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures SyncReqs(s') == SyncReqs(s)
  {
  }

  lemma WriteBackSuperblockReq_AdvanceLocation_StepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.WriteBackSuperblockReq_AdvanceLocation(s.machine, s'.machine, dop, vop)
    requires D.RecvWriteSuperblock(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    WriteBackSuperblockReq_AdvanceLocation_StepPreservesJournals(s, s', dop, vop);
  }

  ////////////////////////////////////////////////////
  ////////////////////// WriteBackSuperblockResp
  //////////////////////

  lemma WriteBackSuperblockRespStepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
  requires Inv(s)
  requires M.WriteBackSuperblockResp(s.machine, s'.machine, dop, vop)
  requires D.AckWriteSuperblock(s.disk, s'.disk, dop);
  ensures WFPersistentJournal(s')
  ensures WFFrozenJournal(s')
  ensures WFEphemeralJournal(s')
  ensures WFGammaJournal(s')
  ensures PersistentJournal(s') == PersistentJournal(s)
  ensures FrozenJournal(s') == FrozenJournal(s)
  ensures EphemeralJournal(s') == EphemeralJournal(s)
  ensures GammaJournal(s') == GammaJournal(s)
  ensures DeltaJournal(s') == DeltaJournal(s)

  ensures WFPersistentLoc(s')
  ensures PersistentLoc(s') == PersistentLoc(s)
  ensures vop.CleanUpOp?         ==> FrozenLoc(s') == None && FrozenLoc(s) == Some(PersistentLoc(s))
  ensures vop.JournalInternalOp? ==> FrozenLoc(s') == FrozenLoc(s)
  ensures SyncReqs(s') == SyncReqs(s)
  {
    /*if s.machine.commitStatus.CommitAdvanceLocation? {
      if s.machine.whichSuperblock == 1 {
        if (s.disk.reqWriteSuperblock2.Some?) {
          assert RecordedWriteSuperblockRequest(s, s.disk.reqWriteSuperblock2.value.id);
        }
        assert s.disk.reqWriteSuperblock2.None?;
        assert dop.which == 0;
        assert s.disk.superblock1
            == Some(s.disk.reqWriteSuperblock1.value.req.superblock)
            == s.machine.newSuperblock;
      }
      assert HasLocationUpdateOccurredUnacked(s);
      assert !HasLocationUpdateOccurredUnacked(s');
      assert WFGammaJournal(s');
      assert GammaJournal(s') == GammaJournal(s);
    } else {
      assert WFGammaJournal(s');
      assert GammaJournal(s') == GammaJournal(s);
    }*/
  }

  lemma WriteBackSuperblockRespStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.WriteBackSuperblockResp(s.machine, s'.machine, dop, vop)
    requires D.AckWriteSuperblock(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    WriteBackSuperblockRespStepPreservesJournals(s, s', dop, vop);
    forall id | id in s'.machine.outstandingJournalWrites
    ensures CorrectInflightJournalWrite(s', id)
    {
      assert CorrectInflightJournalWrite(s, id);
    }
  }

  ////////////////////////////////////////////////////
  ////////////////////// PageInJournalReq
  //////////////////////

  lemma PageInJournalReqStepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp, which: int)
    requires Inv(s)
    requires M.PageInJournalReq(s.machine, s'.machine, dop, vop, which)
    requires D.RecvReadJournal(s.disk, s'.disk, dop);
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures FrozenJournal(s') == FrozenJournal(s)
    ensures EphemeralJournal(s') == EphemeralJournal(s)
    ensures GammaJournal(s') == GammaJournal(s)
    ensures DeltaJournal(s') == DeltaJournal(s)

    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures SyncReqs(s') == SyncReqs(s)
  {
  }

  lemma PageInJournalReqStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp, which: int)
    requires Inv(s)
    requires M.PageInJournalReq(s.machine, s'.machine, dop, vop, which)
    requires D.RecvReadJournal(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    if s'.disk.reqWriteSuperblock2.Some? {
      assert RecordedWriteSuperblockRequest(s', s'.disk.reqWriteSuperblock2.value.id); // ???
    }
    /*if s'.machine.journalFrontRead.Some?
      && s'.machine.journalBackRead.Some?
    {
      assert s'.machine.journalFrontRead.value
          != s'.machine.journalBackRead.value;
    }
    if which == 0 {
      if s'.machine.journalBackRead.Some? {
        var reqId := s'.machine.journalBackRead.value;
        if reqId in s'.disk.reqReadJournals {
          assert reqId in s.disk.reqReadJournals;
          assert s.disk.reqReadJournals[reqId]
              == s'.disk.reqReadJournals[reqId];
        }
      }
      assert CorrectInflightJournalReads(s');
    } else {
      assert CorrectInflightJournalReads(s');
    }*/
  }

  ////////////////////////////////////////////////////
  ////////////////////// PageInJournalResp
  //////////////////////

  lemma PageInJournalRespStepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp, which: int)
    requires Inv(s)
    requires M.PageInJournalResp(s.machine, s'.machine, dop, vop, which)
    requires D.AckReadJournal(s.disk, s'.disk, dop);
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures FrozenJournal(s') == FrozenJournal(s)
    ensures EphemeralJournal(s') == EphemeralJournal(s)
    ensures GammaJournal(s') == GammaJournal(s)
    ensures DeltaJournal(s') == DeltaJournal(s)
    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures SyncReqs(s') == SyncReqs(s)
  {
  }

  lemma PageInJournalRespStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp, which: int)
    requires Inv(s)
    requires M.PageInJournalResp(s.machine, s'.machine, dop, vop, which)
    requires D.AckReadJournal(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    if s'.disk.reqWriteSuperblock2.Some? {
      assert RecordedWriteSuperblockRequest(s', s'.disk.reqWriteSuperblock2.value.id); // ???
    }

    /*forall id | id in s'.disk.reqReads
    ensures RecordedReadRequest(s', id)
    {
      assert RecordedReadRequest(s, id);
      if which == 0 {
        if Some(id) == s.machine.indirectionTableRead {
          assert Some(id) == s'.machine.indirectionTableRead;
        } else if Some(id) == s.machine.journalFrontRead {
          assert id !in s'.disk.reqReads;
        } else if Some(id) == s.machine.journalBackRead {
          assert Some(id) == s'.machine.journalBackRead;
        } else {
          assert false;
        }
      } else {
        if Some(id) == s.machine.indirectionTableRead {
          assert Some(id) == s'.machine.indirectionTableRead;
        } else if Some(id) == s.machine.journalFrontRead {
          assert Some(id) == s'.machine.journalFrontRead;
        } else if Some(id) == s.machine.journalBackRead {
          assert id !in s'.disk.reqReads;
        } else {
          assert false;
        }
      }
    }*/
  }

  ////////////////////////////////////////////////////
  ////////////////////// PageInSuperblockReq
  //////////////////////

  lemma PageInSuperblockReqStepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp, which: int)
    requires Inv(s)
    requires M.PageInSuperblockReq(s.machine, s'.machine, dop, vop, which)
    requires D.RecvReadSuperblock(s.disk, s'.disk, dop);
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures FrozenJournal(s') == FrozenJournal(s)
    ensures EphemeralJournal(s') == EphemeralJournal(s)
    ensures GammaJournal(s') == GammaJournal(s)
    ensures DeltaJournal(s') == DeltaJournal(s)
    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures SyncReqs(s') == SyncReqs(s)
  {
  }

  lemma PageInSuperblockReqStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp, which: int)
    requires Inv(s)
    requires M.PageInSuperblockReq(s.machine, s'.machine, dop, vop, which)
    requires D.RecvReadSuperblock(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    if s'.disk.reqWriteSuperblock2.Some? {
      assert RecordedWriteSuperblockRequest(s', s'.disk.reqWriteSuperblock2.value.id); // ???
    }
  }

  ////////////////////////////////////////////////////
  ////////////////////// PageInSuperblockResp
  //////////////////////

  lemma PageInSuperblockRespStepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp, which: int)
    requires Inv(s)
    requires M.PageInSuperblockResp(s.machine, s'.machine, dop, vop, which)
    requires D.AckReadSuperblock(s.disk, s'.disk, dop);
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures FrozenJournal(s') == FrozenJournal(s)
    ensures EphemeralJournal(s') == EphemeralJournal(s)
    ensures GammaJournal(s') == GammaJournal(s)
    ensures DeltaJournal(s') == DeltaJournal(s)

    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures SyncReqs(s') == SyncReqs(s)
  {
  }

  lemma PageInSuperblockRespStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp, which: int)
    requires Inv(s)
    requires M.PageInSuperblockResp(s.machine, s'.machine, dop, vop, which)
    requires D.AckReadSuperblock(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    if s'.disk.reqWriteSuperblock2.Some? {
      assert RecordedWriteSuperblockRequest(s', s'.disk.reqWriteSuperblock2.value.id); // ???
    }
    forall id | id in s'.disk.reqReadSuperblock2
    ensures RecordedReadSuperblockRequest(s', id)
    {
    }
  }

  ////////////////////////////////////////////////////
  ////////////////////// FinishLoadingSuperblockPhase
  //////////////////////

  lemma FinishLoadingSuperblockPhaseStepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.FinishLoadingSuperblockPhase(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures FrozenJournal(s') == FrozenJournal(s)
    ensures EphemeralJournal(s') == EphemeralJournal(s)
    ensures GammaJournal(s') == GammaJournal(s)
    ensures DeltaJournal(s') == DeltaJournal(s)

    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures SyncReqs(s') == SyncReqs(s)

    ensures vop.loc == PersistentLoc(s)

  {
  }

  lemma FinishLoadingSuperblockPhaseStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.FinishLoadingSuperblockPhase(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    if s'.disk.reqWriteSuperblock2.Some? {
      assert RecordedWriteSuperblockRequest(s', s'.disk.reqWriteSuperblock2.value.id); // ???
    }
  }

  ////////////////////////////////////////////////////
  ////////////////////// FinishLoadingOtherPhase
  //////////////////////

  lemma FinishLoadingOtherPhaseStepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.FinishLoadingOtherPhase(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures FrozenJournal(s') == FrozenJournal(s)
    ensures EphemeralJournal(s') == EphemeralJournal(s)
    ensures GammaJournal(s') == GammaJournal(s)
    ensures DeltaJournal(s') == DeltaJournal(s)

    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures SyncReqs(s') == SyncReqs(s)
  {
    if M.JournalBackIntervalOfSuperblock(s.machine.superblock).Some? {
      Disk_Journal_Read2(s.disk.journal, JournalInterval(
          s.machine.superblock.journalStart as int,
          s.machine.superblock.journalLen as int));
      assert EphemeralJournal(s') == EphemeralJournal(s);
    } else if M.JournalFrontIntervalOfSuperblock(s.machine.superblock).Some? {
      Disk_Journal_Read(s.disk.journal, JournalInterval(
          s.machine.superblock.journalStart as int,
          s.machine.superblock.journalLen as int));
      assert EphemeralJournal(s') == EphemeralJournal(s);
    } else {
      parseJournalRangeEmpty();
      assert EphemeralJournal(s') == [];
      Disk_Journal_empty(s.disk.journal,
          s.machine.superblock.journalStart as int);
      assert EphemeralJournal(s) == [];
    }
  }

  lemma FinishLoadingOtherPhaseStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.FinishLoadingOtherPhase(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    if s'.disk.reqWriteSuperblock2.Some? {
      assert RecordedWriteSuperblockRequest(s', s'.disk.reqWriteSuperblock2.value.id); // ???
    }
  }

  ////////////////////////////////////////////////////
  ////////////////////// Freeze
  //////////////////////

  lemma FreezeStepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.Freeze(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures FrozenJournal(s') == EphemeralJournal(s)
    ensures EphemeralJournal(s') == EphemeralJournal(s)
    ensures GammaJournal(s')
        == GammaJournal(s) + DeltaJournal(s)
    ensures DeltaJournal(s') == []

    ensures FrozenLoc(s) != Some(PersistentLoc(s))

    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == None
    ensures SyncReqs(s') == SyncReqs3to2(SyncReqs(s))
  {
    Disk_Journal_empty(s'.disk.journal, FrozenStartPos(s'));

    /*calc {
      DiskQueue_Journal(s.disk.blocks, s.disk.reqWrites,
              GammaStartPos(s), GammaLen(s));

      DiskQueue_Journal(s'.disk.blocks, s'.disk.reqWrites,
            GammaStartPos(s'), GammaLen(s'));
    }

    calc {
      GammaJournal(s) + DeltaJournal(s);
      DiskQueue_Journal(s.disk.blocks, s.disk.reqWrites,
          GammaStartPos(s), GammaLen(s))
        + s.machine.inMemoryJournalFrozen
        + s.machine.inMemoryJournal;

      DiskQueue_Journal(s'.disk.blocks, s'.disk.reqWrites,
          GammaStartPos(s'), GammaLen(s'))
      + s'.machine.inMemoryJournalFrozen;

      GammaJournal(s');
    }*/
  }

  lemma FreezeStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.Freeze(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    M.FreezeStepPreservesInv(s.machine, s'.machine, dop, vop);
    FreezeStepPreservesJournals(s, s', dop, vop);

    if s'.disk.reqWriteSuperblock2.Some? {
      assert RecordedWriteSuperblockRequest(s', s'.disk.reqWriteSuperblock2.value.id); // ???
    }
  }

  ////////////////////////////////////////////////////
  ////////////////////// ReceiveFrozenLoc
  //////////////////////

  lemma ReceiveFrozenLocStepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.ReceiveFrozenLoc(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures FrozenJournal(s') == FrozenJournal(s)
    ensures EphemeralJournal(s') == EphemeralJournal(s)
    ensures GammaJournal(s') == GammaJournal(s)
    ensures DeltaJournal(s') == DeltaJournal(s)

    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == Some(vop.loc)
    ensures SyncReqs(s') == SyncReqs(s)
  {
  }

  lemma ReceiveFrozenLocStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.ReceiveFrozenLoc(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    ReceiveFrozenLocStepPreservesJournals(s, s', dop, vop);
    if s'.disk.reqWriteSuperblock2.Some? {
      assert RecordedWriteSuperblockRequest(s', s'.disk.reqWriteSuperblock2.value.id); // ???
    }
  }

  ////////////////////////////////////////////////////
  ////////////////////// Advance
  //////////////////////

  lemma AdvanceStepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.Advance(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures FrozenJournal(s') == FrozenJournal(s)
    ensures EphemeralJournal(s) == []
    ensures EphemeralJournal(s') == []
    ensures GammaJournal(s') == GammaJournal(s)
    ensures DeltaJournal(s') == DeltaJournal(s) + JournalEntriesForUIOp(vop.uiop)

    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures SyncReqs(s') == SyncReqs(s)
  {
  }

  lemma AdvanceStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.Advance(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    AdvanceStepPreservesJournals(s, s', dop, vop);
    if s'.disk.reqWriteSuperblock2.Some? {
      assert RecordedWriteSuperblockRequest(s', s'.disk.reqWriteSuperblock2.value.id); // ???
    }
  }

  ////////////////////////////////////////////////////
  ////////////////////// Replay
  //////////////////////

  lemma ReplayStepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.Replay(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures FrozenJournal(s') == FrozenJournal(s)
    ensures JournalEntriesForUIOp(vop.uiop) + EphemeralJournal(s') == EphemeralJournal(s)
    ensures GammaJournal(s') == GammaJournal(s)
    ensures DeltaJournal(s') == DeltaJournal(s)

    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures SyncReqs(s') == SyncReqs(s)
  {
  }

  lemma ReplayStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.Replay(s.machine, s'.machine, dop, vop)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    ReplayStepPreservesJournals(s, s', dop, vop);
    if s'.disk.reqWriteSuperblock2.Some? {
      assert RecordedWriteSuperblockRequest(s', s'.disk.reqWriteSuperblock2.value.id); // ???
    }
  }

  ////////////////////////////////////////////////////
  ////////////////////// PushSync
  //////////////////////

  lemma PushSyncReqStepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp, id: uint64)
    requires Inv(s)
    requires M.PushSyncReq(s.machine, s'.machine, dop, vop, id)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures FrozenJournal(s') == FrozenJournal(s)
    ensures EphemeralJournal(s') == EphemeralJournal(s)
    ensures GammaJournal(s') == GammaJournal(s)
    ensures DeltaJournal(s') == DeltaJournal(s)

    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures vop.id !in SyncReqs(s)
    ensures SyncReqs(s') == SyncReqs(s)[vop.id := ThreeStateTypes.State3]
  {
  }

  lemma PushSyncReqStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp, id: uint64)
    requires Inv(s)
    requires M.PushSyncReq(s.machine, s'.machine, dop, vop, id)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    if s'.disk.reqWriteSuperblock2.Some? {
      assert RecordedWriteSuperblockRequest(s', s'.disk.reqWriteSuperblock2.value.id); // ???
    }
  }

  ////////////////////////////////////////////////////
  ////////////////////// PopSync
  //////////////////////

  lemma PopSyncReqStepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp, id: uint64)
    requires Inv(s)
    requires M.PopSyncReq(s.machine, s'.machine, dop, vop, id)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures FrozenJournal(s') == FrozenJournal(s)
    ensures EphemeralJournal(s') == EphemeralJournal(s)
    ensures GammaJournal(s') == GammaJournal(s)
    ensures DeltaJournal(s') == DeltaJournal(s)

    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures vop.id in SyncReqs(s)
    ensures SyncReqs(s)[vop.id] == ThreeStateTypes.State1
    ensures SyncReqs(s') == MapRemove1(SyncReqs(s), vop.id)
  {
  }

  lemma PopSyncReqStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp, id: uint64)
    requires Inv(s)
    requires M.PopSyncReq(s.machine, s'.machine, dop, vop, id)
    requires D.Stutter(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    if s'.disk.reqWriteSuperblock2.Some? {
      assert RecordedWriteSuperblockRequest(s', s'.disk.reqWriteSuperblock2.value.id); // ???
    }
  }

  ////////////////////////////////////////////////////
  ////////////////////// No-Op
  //////////////////////

  lemma NoOpStepPreservesJournals(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.NoOp(s.machine, s'.machine, dop, vop)
    requires D.Next(s.disk, s'.disk, dop);
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures FrozenJournal(s') == FrozenJournal(s)
    ensures EphemeralJournal(s') == EphemeralJournal(s)
    ensures GammaJournal(s') == GammaJournal(s)
    ensures DeltaJournal(s') == DeltaJournal(s)

    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures SyncReqs(s') == SyncReqs(s)
  {
    /*if (dop.NoDiskOp?) {
      assert D.Stutter(s.disk, s'.disk, dop);
    } else if (dop.RespReadOp?) {
      assert D.AckRead(s.disk, s'.disk, dop);
    } else if (dop.RespWriteOp?) {
      assert D.AckWrite(s.disk, s'.disk, dop);
    } else {
      assert false;
    }*/
  }

  lemma NoOpStepPreservesInv(s: Variables, s': Variables, dop: DiskOp, vop: VOp)
    requires Inv(s)
    requires M.NoOp(s.machine, s'.machine, dop, vop)
    requires D.Next(s.disk, s'.disk, dop);
    ensures Inv(s')
  {
    NoOpStepPreservesJournals(s, s', dop, vop);
    if s'.disk.reqWriteSuperblock2.Some? {
      assert RecordedWriteSuperblockRequest(s', s'.disk.reqWriteSuperblock2.value.id);
    }
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
      case WriteBackJournalReqStep(jr) => WriteBackJournalReqStepPreservesInv(s, s', dop, vop, jr);
      case WriteBackJournalRespStep => WriteBackJournalRespStepPreservesInv(s, s', dop, vop);
      case WriteBackSuperblockReq_AdvanceLog_Step => WriteBackSuperblockReq_AdvanceLog_StepPreservesInv(s, s', dop, vop);
      case WriteBackSuperblockReq_AdvanceLocation_Step => WriteBackSuperblockReq_AdvanceLocation_StepPreservesInv(s, s', dop, vop);
      case WriteBackSuperblockRespStep => WriteBackSuperblockRespStepPreservesInv(s, s', dop, vop);
      case PageInJournalReqStep(which) => PageInJournalReqStepPreservesInv(s, s', dop, vop, which);
      case PageInJournalRespStep(which) => PageInJournalRespStepPreservesInv(s, s', dop, vop, which);
      case PageInSuperblockReqStep(which) => PageInSuperblockReqStepPreservesInv(s, s', dop, vop, which);
      case PageInSuperblockRespStep(which) => PageInSuperblockRespStepPreservesInv(s, s', dop, vop, which);
      case FinishLoadingSuperblockPhaseStep => FinishLoadingSuperblockPhaseStepPreservesInv(s, s', dop, vop);
      case FinishLoadingOtherPhaseStep => FinishLoadingOtherPhaseStepPreservesInv(s, s', dop, vop);
      case FreezeStep => FreezeStepPreservesInv(s, s', dop, vop);
      case ReceiveFrozenLocStep => ReceiveFrozenLocStepPreservesInv(s, s', dop, vop);
      case AdvanceStep => AdvanceStepPreservesInv(s, s', dop, vop);
      case ReplayStep => ReplayStepPreservesInv(s, s', dop, vop);
      case PushSyncReqStep(id) => PushSyncReqStepPreservesInv(s, s', dop, vop, id);
      case PopSyncReqStep(id) => PopSyncReqStepPreservesInv(s, s', dop, vop, id);
      case NoOpStep => { NoOpStepPreservesInv(s, s', dop, vop); }
    }
  }

  ////////////////////////////////////////////////////
  ////////////////////// ProcessWriteSuperblock
  //////////////////////

  predicate ProcessWriteIsGraphUpdate(s: Variables)
  {
    && s.machine.Ready?
    && s.machine.commitStatus.CommitAdvanceLocation?
  }

  lemma ProcessWriteSuperblockPreservesJournals(s: Variables, s': Variables, vop: VOp, which: int)
    requires Inv(s)
    requires s.machine == s'.machine
    requires D.ProcessWriteSuperblock(s.disk, s'.disk, which)
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures WFPersistentLoc(s')

    ensures FrozenJournal(s') == FrozenJournal(s)
    ensures EphemeralJournal(s') == EphemeralJournal(s)

    ensures 
        if ProcessWriteIsGraphUpdate(s) then (
          && GammaJournal(s') == FrozenJournal(s)
          && PersistentJournal(s') == FrozenJournal(s)
          && FrozenLoc(s).Some?
          && PersistentLoc(s') == FrozenLoc(s).value
        ) else (
          && GammaJournal(s') == GammaJournal(s)
          && PersistentJournal(s') == GammaJournal(s)
          && PersistentLoc(s') == PersistentLoc(s)
        )

    ensures DeltaJournal(s') == DeltaJournal(s)
    ensures FrozenLoc(s') == FrozenLoc(s)
    ensures SyncReqs(s') == SyncReqs2to1(SyncReqs(s))
  {
    assert s.machine.newSuperblock.Some?;
    /*if which == 0 {
      assert s.machine.whichSuperblock == 1;
      assert s.machine.superblock == s.disk.superblock2.value;
      assert SuperblockOfDisk(s'.disk)
          == s'.disk.superblock1.value
          == s.disk.reqWriteSuperblock1.value.req.superblock
          == s.machine.newSuperblock.value;
    } else {
      assert SuperblockOfDisk(s'.disk)
          == s'.disk.superblock2.value
          == s.disk.reqWriteSuperblock2.value.req.superblock
          == s.machine.newSuperblock.value;
    }*/
    assert SuperblockOfDisk(s'.disk)
        == s.machine.newSuperblock.value;
    if ProcessWriteIsGraphUpdate(s) {
      //locDisjointFromCircularJournalRangeOfNonJournalLoc(
      //    s.disk.reqWrites[id].loc,
      //    FrozenStartPos(s) as uint64,
      //    FrozenLen(s) as uint64);

      assert s.machine.newSuperblock.value.journalLen as int
          == s.machine.writtenJournalLen - s.machine.frozenJournalPosition
          == FrozenLen(s);

      assert SuperblockOfDisk(s'.disk).journalStart as int
          == FrozenStartPos(s);
      assert SuperblockOfDisk(s'.disk).journalLen as int
          == FrozenLen(s);
      assert WFPersistentJournal(s');
      assert PersistentJournal(s') == FrozenJournal(s);
    } else {
      assert s.machine.inMemoryJournalFrozen == [];

      assert s'.machine.newSuperblock.Some?;
      assert SuperblockOfDisk(s'.disk).journalStart as int
          == s'.machine.newSuperblock.value.journalStart as int
          == GammaStartPos(s);
      assert SuperblockOfDisk(s'.disk).journalLen as int
          == s'.machine.newSuperblock.value.journalLen as int
          == s.machine.writtenJournalLen
          == GammaLen(s);
      assert WFPersistentJournal(s');
      assert PersistentJournal(s') == GammaJournal(s);
    }
  }

  lemma ProcessWriteSuperblockPreservesInv(s: Variables, s': Variables, vop: VOp, which: int)
    requires Inv(s)
    requires s.machine == s'.machine
    requires D.ProcessWriteSuperblock(s.disk, s'.disk, which)
    ensures Inv(s')
  {
    ProcessWriteSuperblockPreservesJournals(s, s', vop, which);
  }

  ////////////////////////////////////////////////////
  ////////////////////// DiskInternal
  //////////////////////

  lemma DiskInternalStepPreservesInv(s: Variables, s': Variables, vop: VOp, step: D.InternalStep)
    requires Inv(s)
    requires DiskInternal(s, s', step, vop)
    ensures Inv(s')
  {
    match step {
      case ProcessWriteSuperblockStep(which) => ProcessWriteSuperblockPreservesInv(s, s', vop, which);
    }
  }

  ////////////////////////////////////////////////////
  ////////////////////// Crash
  //////////////////////

  lemma CrashPreservesJournals(s: Variables, s': Variables, vop: VOp)
    requires Inv(s)
    requires Crash(s, s', vop)
    ensures WFPersistentJournal(s')
    ensures WFFrozenJournal(s')
    ensures WFEphemeralJournal(s')
    ensures WFGammaJournal(s')
    ensures PersistentJournal(s') == PersistentJournal(s)
    ensures FrozenJournal(s') == PersistentJournal(s)
    ensures EphemeralJournal(s') == PersistentJournal(s)
    ensures GammaJournal(s') == PersistentJournal(s)
    ensures DeltaJournal(s') == []

    ensures WFPersistentLoc(s')
    ensures PersistentLoc(s') == PersistentLoc(s)
    ensures FrozenLoc(s') == None
    ensures SyncReqs(s') == map[]
  {
    assert SuperblockOfDisk(s.disk)
        == SuperblockOfDisk(s'.disk);

    var interval := JournalInterval(
        SuperblockOfDisk(s.disk).journalStart as int,
        SuperblockOfDisk(s.disk).journalLen as int);
    Disk_Journal_Preserves(s.disk.journal, s'.disk.journal, interval);
  }

  lemma CrashStepPreservesInv(s: Variables, s': Variables, vop: VOp)
    requires Inv(s)
    requires Crash(s, s', vop)
    ensures Inv(s')
  {
    CrashPreservesJournals(s, s', vop);
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
      case DiskInternalStep(step) => DiskInternalStepPreservesInv(s, s', vop, step);
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
  ////////////////////// Misc lemma
  //////////////////////

  // Used by ByteBetreeBlockCacheSystem.i.dfy

  /*lemma RequestsDontOverlap(s: Variables)
  requires Inv(s)
  ensures WriteJournalRequestsDontOverlap(s.disk.reqWriteJournals)
  ensures ReadWritesJournalDontOverlap(s.disk.reqReadJournals, s.disk.reqWriteJournals)
  {
  }*/

  lemma NewRequestReadJournalDoesntOverlap(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step, id: D.ReqId)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqReadJournalOp?
  requires id in s.disk.reqWriteJournals
  ensures !journalIntervalOverlap(dop.interval, s.disk.reqWriteJournals[id])
  {
    MachineStepPreservesInv(s, s', dop, vop, step);
    forall id | id in s.disk.reqWriteJournals
    ensures !journalIntervalOverlap(dop.interval, s.disk.reqWriteJournals[id]);
    {
      assert !journalIntervalOverlap(
          s'.disk.reqReadJournals[dop.id],
          s'.disk.reqWriteJournals[id]);
      assert !journalIntervalOverlap(
          dop.interval,
          s'.disk.reqWriteJournals[id]);
    }
  }

  lemma NewRequestWriteJournalDoesntOverlap(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step, id: D.ReqId)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqWriteJournalOp?
  requires var interval := JournalInterval(
          dop.reqWriteJournal.start, |dop.reqWriteJournal.journal|);
    && ContiguousJournalInterval(interval)
  requires id in s.disk.reqWriteJournals
  ensures var interval := JournalInterval(
          dop.reqWriteJournal.start, |dop.reqWriteJournal.journal|);
      !journalIntervalOverlap(interval, s.disk.reqWriteJournals[id])
  {
  }

  lemma NewRequestWrite2JournalDoesntOverlap(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step, id: D.ReqId)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqWriteJournalOp?
  requires var interval := JournalInterval(
          dop.reqWriteJournal.start, |dop.reqWriteJournal.journal|);
    && ValidJournalInterval(interval)
    && dop.reqWriteJournal.start + |dop.reqWriteJournal.journal| >= NumJournalBlocks() as int
  requires id in s.disk.reqWriteJournals
  ensures var interval1 := JournalInterval(
          dop.reqWriteJournal.start, NumJournalBlocks() as int - dop.reqWriteJournal.start);
      !journalIntervalOverlap(interval1, s.disk.reqWriteJournals[id])
  ensures var interval2 := JournalInterval(
          0, |dop.reqWriteJournal.journal| - (NumJournalBlocks() as int - dop.reqWriteJournal.start));
      !journalIntervalOverlap(interval2, s.disk.reqWriteJournals[id])
  {
  }

  lemma NewRequestWrite2JournalDoesntOverlapRead(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step, id: D.ReqId)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqWriteJournalOp?
  requires var interval := JournalInterval(
          dop.reqWriteJournal.start, |dop.reqWriteJournal.journal|);
    && ValidJournalInterval(interval)
    && dop.reqWriteJournal.start + |dop.reqWriteJournal.journal| >= NumJournalBlocks() as int
  requires id in s.disk.reqReadJournals
  ensures var interval1 := JournalInterval(
          dop.reqWriteJournal.start, NumJournalBlocks() as int - dop.reqWriteJournal.start);
      !journalIntervalOverlap(interval1, s.disk.reqReadJournals[id])
  ensures var interval2 := JournalInterval(
          0, |dop.reqWriteJournal.journal| - (NumJournalBlocks() as int - dop.reqWriteJournal.start));
      !journalIntervalOverlap(interval2, s.disk.reqReadJournals[id])
  {
  }

  lemma NewRequestReadSuperblockDoesntOverlap(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqReadSuperblockOp?
  ensures dop.which == 0 ==> s.disk.reqWriteSuperblock1.None?
  ensures dop.which == 1 ==> s.disk.reqWriteSuperblock2.None?
  {
    if s.disk.reqWriteSuperblock2.Some? {
      assert RecordedWriteSuperblockRequest(s, s.disk.reqWriteSuperblock2.value.id);
    }
  }

  lemma NewRequestWriteSuperblockDoesntOverlap(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqWriteSuperblockOp?
  ensures dop.which == 0 ==> s.disk.reqWriteSuperblock1.None?
  ensures dop.which == 1 ==> s.disk.reqWriteSuperblock2.None?
  {
    if s.disk.reqWriteSuperblock2.Some? {
      assert RecordedWriteSuperblockRequest(s, s.disk.reqWriteSuperblock2.value.id);
    }
  }

  lemma NewRequestReadJournalIsValid(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqReadJournalOp?
  ensures Disk_HasJournalRange(s.disk.journal, dop.interval)
  {
    HasJournalRange_of_containedIn(s.disk.journal,
        JournalInterval(
          SuperblockOfDisk(s.disk).journalStart as int,
          SuperblockOfDisk(s.disk).journalLen as int) ,
        dop.interval);
  }

  lemma NewRequestReadSuperblockIsValid(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqReadSuperblockOp?
  ensures dop.which == 0 ==> s.disk.superblock1.Some?
  ensures dop.which == 1 ==> s.disk.superblock2.Some?
  {
  }

  lemma NewRequestWriteJournalDoesntOverlapRead(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step, id: D.ReqId)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqWriteJournalOp?
  requires var interval := JournalInterval(
          dop.reqWriteJournal.start, |dop.reqWriteJournal.journal|);
    && ContiguousJournalInterval(interval)
  requires id in s.disk.reqReadJournals
  ensures var interval := JournalInterval(
          dop.reqWriteJournal.start, |dop.reqWriteJournal.journal|);
      !journalIntervalOverlap(interval, s.disk.reqReadJournals[id])
  {
  }

  lemma NewRequestWriteSuperblockDoesntOverlapRead(s: Variables, s': Variables, dop: DiskOp, vop: VOp, step: M.Step)
  requires Inv(s)
  requires M.NextStep(s.machine, s'.machine, dop, vop, step)
  requires dop.ReqWriteSuperblockOp?
  ensures dop.which == 0 ==> s.disk.reqReadSuperblock1 == {}
  ensures dop.which == 1 ==> s.disk.reqReadSuperblock2 == {}
  {
  }
}
