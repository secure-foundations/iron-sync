// include "StateModel.i.dfy"
// include "IOModel.i.dfy"

// module CommitterInitModel {
//   import opened NativeTypes
//   import opened Options

//   import opened DiskLayout
//   import opened InterpretationDiskOps
//   import opened ViewOp
//   import JournalCache
//   import JournalBytes
//   import JournalRanges

//   import opened StateModel
//   import opened IOModel
//   import opened DiskOpModel

//   function {:opaque} PageInSuperblockReq(cm: CM, io: IO, which: uint64) : (res : (CM, IO))
//   requires which == 0 || which == 1
//   requires which == 0 ==> cm.superblock1.SuperblockUnfinished?
//   requires which == 1 ==> cm.superblock2.SuperblockUnfinished?
//   requires io.IOInit?
//   requires cm.status.StatusLoadingSuperblock?
//   {
//     if which == 0 then (
//       if cm.superblock1Read.None? then (
//         var loc := Superblock1Location();
//         var (id, io') := RequestRead(io, loc);
//         var cm' := cm.(superblock1Read := Some(id));
//         (cm', io')
//       ) else (
//         (cm, io)
//       )
//     ) else (
//       if cm.superblock2Read.None? then (
//         var loc := Superblock2Location();
//         var (id, io') := RequestRead(io, loc);
//         var cm' := cm.(superblock2Read := Some(id));
//         (cm', io')
//       ) else (
//         (cm, io)
//       )
//     )
//   }

//   lemma PageInSuperblockReqCorrect(cm: CM, io: IO, which: uint64)
//   requires CommitterModel.WF(cm)
//   requires PageInSuperblockReq.requires(cm, io, which)
//   ensures var (cm', io') := PageInSuperblockReq(cm, io, which);
//     && CommitterModel.WF(cm')
//     && ValidDiskOp(diskOp(io'))
//     && IDiskOp(diskOp(io')).bdop.NoDiskOp?
//     && JournalCache.Next(
//         CommitterModel.I(cm),
//         CommitterModel.I(cm'),
//         IDiskOp(diskOp(io')).jdop,
//         JournalInternalOp)
//   {
//     reveal_PageInSuperblockReq();
//     var (cm', io') := PageInSuperblockReq(cm, io, which);

//     var loc;
//     if which == 0 {
//       loc := Superblock1Location();
//     } else {
//       loc := Superblock2Location();
//     }
//     RequestReadCorrect(io, loc);

//     if (which == 0 && cm.superblock1Read.None?)
//       || (which == 1 && cm.superblock2Read.None?)
//     {
//       assert JournalCache.PageInSuperblockReq(
//           CommitterModel.I(cm),
//           CommitterModel.I(cm'),
//           IDiskOp(diskOp(io')).jdop,
//           JournalInternalOp, which as int);
//       assert JournalCache.NextStep(
//           CommitterModel.I(cm),
//           CommitterModel.I(cm'),
//           IDiskOp(diskOp(io')).jdop,
//           JournalInternalOp,
//           JournalCache.PageInSuperblockReqStep(which as int));
//     } else {
//       assert JournalCache.NoOp(
//           CommitterModel.I(cm),
//           CommitterModel.I(cm'),
//           IDiskOp(diskOp(io')).jdop,
//           JournalInternalOp);
//       assert JournalCache.NextStep(
//           CommitterModel.I(cm),
//           CommitterModel.I(cm'),
//           IDiskOp(diskOp(io')).jdop,
//           JournalInternalOp,
//           JournalCache.NoOpStep);
//     }
//   }

//   function {:opaque} FinishLoadingSuperblockPhase(cm: CM) : (cm' : CM)
//   requires cm.status.StatusLoadingSuperblock?
//   requires cm.superblock1.SuperblockSuccess?
//   requires cm.superblock2.SuperblockSuccess?
//   {
//     var idx := if JournalCache.increments1(
//         cm.superblock1.value.counter, cm.superblock2.value.counter)
//         then 1 else 0;

//     var sup := if idx == 1 then
//       cm.superblock2.value
//     else
//       cm.superblock1.value;

//     cm.(whichSuperblock := idx)
//       .(superblock := sup)
//       .(status := StatusLoadingOther)
//       .(journalFrontRead := None)
//       .(journalBackRead := None)
//   }

//   lemma FinishLoadingSuperblockPhaseCorrect(cm: CM)
//   requires cm.status.StatusLoadingSuperblock?
//   requires cm.superblock1.SuperblockSuccess?
//   requires cm.superblock2.SuperblockSuccess?
//   requires CommitterModel.WF(cm)
//   ensures var cm' := FinishLoadingSuperblockPhase(cm);
//     && CommitterModel.WF(cm')
//     && JournalCache.Next(
//         CommitterModel.I(cm),
//         CommitterModel.I(cm'),
//         JournalDisk.NoDiskOp,
//         SendPersistentLocOp(cm'.superblock.indirectionTableLoc))
//   {
//     var cm' := FinishLoadingSuperblockPhase(cm);
//     var vop := SendPersistentLocOp(cm'.superblock.indirectionTableLoc);
//     reveal_FinishLoadingSuperblockPhase();
//     assert JournalCache.FinishLoadingSuperblockPhase(
//         CommitterModel.I(cm),
//         CommitterModel.I(cm'),
//         JournalDisk.NoDiskOp,
//         vop);
//     assert JournalCache.NextStep(
//         CommitterModel.I(cm),
//         CommitterModel.I(cm'),
//         JournalDisk.NoDiskOp,
//         vop,
//         JournalCache.FinishLoadingSuperblockPhaseStep);
//   }

//   function {:opaque} FinishLoadingOtherPhase(cm: CM) : (cm' : CM)
//   requires cm.status.StatusLoadingOther?
//   requires CommitterModel.WF(cm)
//   {
//     var (journalist1, success) :=
//         JournalistModel.parseJournals(cm.journalist);
//     if success then (
//       var journalist2 := JournalistModel.setWrittenJournalLen(
//             journalist1, cm.superblock.journalLen);
//       cm.(status := StatusReady)
//         .(frozenLoc := None)
//         .(isFrozen := false)
//         .(frozenJournalPosition := 0)
//         .(superblockWrite := None)
//         .(outstandingJournalWrites := {})
//         .(newSuperblock := None)
//         .(commitStatus := JournalCache.CommitNone)
//         .(journalist := journalist2)
//     ) else (
//       cm.(journalist := journalist1)
//     )
//   }

//   lemma FinishLoadingOtherPhaseCorrect(cm: CM)
//   requires cm.status.StatusLoadingOther?
//   requires CommitterModel.Inv(cm)
//   requires JournalCache.JournalFrontIntervalOfSuperblock(cm.superblock).Some? ==>
//       JournalistModel.hasFront(cm.journalist)
//   requires JournalCache.JournalBackIntervalOfSuperblock(cm.superblock).Some? ==>
//       JournalistModel.hasBack(cm.journalist)
//   ensures var cm' := FinishLoadingOtherPhase(cm);
//     && CommitterModel.WF(cm')
//     && JournalCache.Next(
//         CommitterModel.I(cm),
//         CommitterModel.I(cm'),
//         JournalDisk.NoDiskOp,
//         JournalInternalOp)
//   {
//     var cm' := FinishLoadingOtherPhase(cm);
//     reveal_FinishLoadingOtherPhase();

//     var (journalist1, success) :=
//         JournalistModel.parseJournals(cm.journalist);

//     assert JournalCache.JournalFrontIntervalOfSuperblock(cm.superblock).Some? <==>
//         JournalistModel.hasFront(cm.journalist);
//     assert JournalCache.JournalBackIntervalOfSuperblock(cm.superblock).Some? <==>
//         JournalistModel.hasBack(cm.journalist);

//     if success {
//       var s := CommitterModel.I(cm);
//       var fullRange := (
//         if JournalCache.JournalBackIntervalOfSuperblock(s.superblock).Some? then
//           JournalRanges.JournalRangeConcat(s.journalFront.value, s.journalBack.value)
//         else if JournalCache.JournalFrontIntervalOfSuperblock(s.superblock).Some? then
//           s.journalFront.value
//         else
//           JournalRanges.JournalRangeEmpty()
//       );

//       var jm := cm.journalist;
//       assert fullRange ==
//         (if JournalistModel.I(jm).journalFront.Some? then JournalistModel.I(jm).journalFront.value
//             else []) +
//         (if JournalistModel.I(jm).journalBack.Some? then JournalistModel.I(jm).journalBack.value
//             else []);

//       assert JournalCache.FinishLoadingOtherPhase(
//           CommitterModel.I(cm),
//           CommitterModel.I(cm'),
//           JournalDisk.NoDiskOp,
//           JournalInternalOp);
//       assert JournalCache.NextStep(
//           CommitterModel.I(cm),
//           CommitterModel.I(cm'),
//           JournalDisk.NoDiskOp,
//           JournalInternalOp,
//           JournalCache.FinishLoadingOtherPhaseStep);
//     } else {
//       assert JournalCache.NoOp(
//           CommitterModel.I(cm),
//           CommitterModel.I(cm'),
//           JournalDisk.NoDiskOp,
//           JournalInternalOp);
//       assert JournalCache.NextStep(
//           CommitterModel.I(cm),
//           CommitterModel.I(cm'),
//           JournalDisk.NoDiskOp,
//           JournalInternalOp,
//           JournalCache.NoOpStep);
//     }
//   }

//   function isReplayEmpty(cm: CM) : bool
//   requires JournalistModel.Inv(cm.journalist)
//   {
//     JournalistModel.isReplayEmpty(cm.journalist)
//   }

//   function {:opaque} PageInJournalReqFront(cm: CM, io: IO)
//     : (CM, IO)
//   requires CommitterModel.WF(cm)
//   requires cm.status.StatusLoadingOther?
//   requires cm.superblock.journalLen > 0
//   requires io.IOInit?
//   {
//     var len :=
//       if cm.superblock.journalStart + cm.superblock.journalLen
//           >= NumJournalBlocks()
//       then
//         NumJournalBlocks() - cm.superblock.journalStart
//       else
//         cm.superblock.journalLen;
//     var loc := JournalRangeLocation(cm.superblock.journalStart, len);
//     var (id, io') := RequestRead(io, loc);
//     var cm' := cm.(journalFrontRead := Some(id))
//       .(journalBackRead :=
//         if cm.journalBackRead == Some(id)
//           then None else cm.journalBackRead);
//     (cm', io')
//   }

//   lemma PageInJournalReqFrontCorrect(cm: CM, io: IO)
//   requires CommitterModel.WF(cm)
//   requires cm.status.StatusLoadingOther?
//   requires cm.superblock.journalLen > 0
//   requires io.IOInit?
//   requires cm.journalFrontRead.None?
//   requires JournalistModel.I(cm.journalist).journalFront.None?

//   ensures var (cm', io') := PageInJournalReqFront(cm, io);
//     && CommitterModel.WF(cm')
//     && ValidDiskOp(diskOp(io'))
//     && IDiskOp(diskOp(io')).bdop.NoDiskOp?
//     && JournalCache.Next(
//         CommitterModel.I(cm),
//         CommitterModel.I(cm'),
//         IDiskOp(diskOp(io')).jdop,
//         JournalInternalOp)
//   {
//     reveal_PageInJournalReqFront();
//     var (cm', io') := PageInJournalReqFront(cm, io);

//     var len :=
//       if cm.superblock.journalStart + cm.superblock.journalLen
//           >= NumJournalBlocks()
//       then
//         NumJournalBlocks() - cm.superblock.journalStart
//       else
//         cm.superblock.journalLen;
//     var loc := JournalRangeLocation(cm.superblock.journalStart, len);
//     RequestReadCorrect(io, loc);

//     assert JournalCache.PageInJournalReq(
//         CommitterModel.I(cm),
//         CommitterModel.I(cm'),
//         IDiskOp(diskOp(io')).jdop,
//         JournalInternalOp,
//         0);
//     assert JournalCache.NextStep(
//         CommitterModel.I(cm),
//         CommitterModel.I(cm'),
//         IDiskOp(diskOp(io')).jdop,
//         JournalInternalOp,
//         JournalCache.PageInJournalReqStep(0));
//   }

//   function {:opaque} PageInJournalReqBack(cm: CM, io: IO)
//     : (CM, IO)
//   requires CommitterModel.WF(cm)
//   requires cm.status.StatusLoadingOther?
//   requires cm.superblock.journalLen > 0
//   requires io.IOInit?
//   requires cm.superblock.journalStart + cm.superblock.journalLen > NumJournalBlocks()
//   {
//     var len := cm.superblock.journalStart + cm.superblock.journalLen - NumJournalBlocks();
//     var loc := JournalRangeLocation(0, len);
//     var (id, io') := RequestRead(io, loc);
//     var cm' := cm.(journalBackRead := Some(id))
//       .(journalFrontRead :=
//         if cm.journalFrontRead == Some(id)
//           then None else cm.journalFrontRead);
//     (cm', io')
//   }

//   lemma PageInJournalReqBackCorrect(cm: CM, io: IO)
//   requires CommitterModel.WF(cm)
//   requires cm.status.StatusLoadingOther?
//   requires cm.superblock.journalLen > 0
//   requires io.IOInit?
//   requires cm.journalBackRead.None?
//   requires JournalistModel.I(cm.journalist).journalBack.None?
//   requires cm.superblock.journalStart + cm.superblock.journalLen > NumJournalBlocks()

//   ensures var (cm', io') := PageInJournalReqBack(cm, io);
//     && CommitterModel.WF(cm')
//     && ValidDiskOp(diskOp(io'))
//     && IDiskOp(diskOp(io')).bdop.NoDiskOp?
//     && JournalCache.Next(
//         CommitterModel.I(cm),
//         CommitterModel.I(cm'),
//         IDiskOp(diskOp(io')).jdop,
//         JournalInternalOp)
//   {
//     reveal_PageInJournalReqBack();
//     var (cm', io') := PageInJournalReqBack(cm, io);

//     var len := cm.superblock.journalStart + cm.superblock.journalLen - NumJournalBlocks();
//     var loc := JournalRangeLocation(0, len);
//     RequestReadCorrect(io, loc);

//     assert JournalCache.PageInJournalReq(
//         CommitterModel.I(cm),
//         CommitterModel.I(cm'),
//         IDiskOp(diskOp(io')).jdop,
//         JournalInternalOp,
//         1);
//     assert JournalCache.NextStep(
//         CommitterModel.I(cm),
//         CommitterModel.I(cm'),
//         IDiskOp(diskOp(io')).jdop,
//         JournalInternalOp,
//         JournalCache.PageInJournalReqStep(1));
//   }

//   function {:opaque} PageInJournalResp(cm: CM, io: IO)
//     : CM
//   requires CommitterModel.WF(cm)
//   requires cm.status.StatusLoadingOther?
//   requires diskOp(io).RespReadOp?
//   requires ValidDiskOp(diskOp(io))
//   requires ValidJournalLocation(LocOfRespRead(diskOp(io).respRead))
//   {
//     var id := io.id;
//     var jr := JournalBytes.JournalRangeOfByteSeq(io.respRead.bytes);
//     if jr.Some? then (
//       assert |jr.value| <= NumJournalBlocks() as int by {
//         reveal_ValidJournalLocation();
//       }

//       if cm.journalFrontRead == Some(id) then (
//         cm.(journalist := JournalistModel.setFront(cm.journalist, jr.value))
//           .(journalFrontRead := None)
//       ) else if cm.journalBackRead == Some(id) then (
//         cm.(journalist := JournalistModel.setBack(cm.journalist, jr.value))
//           .(journalBackRead := None)
//       ) else (
//         cm
//       )
//     ) else (
//       cm
//     )
//   }

//   lemma PageInJournalRespCorrect(cm: CM, io: IO)
//   requires PageInJournalResp.requires(cm, io)
//   requires CommitterModel.WF(cm)
//   ensures var cm' := PageInJournalResp(cm, io);
//     && CommitterModel.WF(cm')
//     && ValidDiskOp(diskOp(io))
//     && IDiskOp(diskOp(io)).bdop.NoDiskOp?
//     && JournalCache.Next(
//         CommitterModel.I(cm),
//         CommitterModel.I(cm'),
//         IDiskOp(diskOp(io)).jdop,
//         JournalInternalOp)
//   {
//     reveal_PageInJournalResp();
//     var jr := JournalBytes.JournalRangeOfByteSeq(io.respRead.bytes);
//     var cm' := PageInJournalResp(cm, io);
//     if jr.Some? {
//       assert |jr.value| <= NumJournalBlocks() as int by {
//         reveal_ValidJournalLocation();
//       }

//       if cm.journalFrontRead == Some(io.id) {
//         assert JournalCache.PageInJournalResp(
//             CommitterModel.I(cm),
//             CommitterModel.I(cm'),
//             IDiskOp(diskOp(io)).jdop,
//             JournalInternalOp,
//             0);
//         assert JournalCache.NextStep(
//             CommitterModel.I(cm),
//             CommitterModel.I(cm'),
//             IDiskOp(diskOp(io)).jdop,
//             JournalInternalOp,
//             JournalCache.PageInJournalRespStep(0));
//       } else if cm.journalBackRead == Some(io.id) {
//         assert JournalCache.PageInJournalResp(
//             CommitterModel.I(cm),
//             CommitterModel.I(cm'),
//             IDiskOp(diskOp(io)).jdop,
//             JournalInternalOp,
//             1);
//         assert JournalCache.NextStep(
//             CommitterModel.I(cm),
//             CommitterModel.I(cm'),
//             IDiskOp(diskOp(io)).jdop,
//             JournalInternalOp,
//             JournalCache.PageInJournalRespStep(1));
//       } else {
//         assert JournalCache.NoOp(
//             CommitterModel.I(cm),
//             CommitterModel.I(cm'),
//             IDiskOp(diskOp(io)).jdop,
//             JournalInternalOp);
//         assert JournalCache.NextStep(
//             CommitterModel.I(cm),
//             CommitterModel.I(cm'),
//             IDiskOp(diskOp(io)).jdop,
//             JournalInternalOp,
//             JournalCache.NoOpStep);
//       }
//     } else {
//       assert JournalCache.NoOp(
//           CommitterModel.I(cm),
//           CommitterModel.I(cm'),
//           IDiskOp(diskOp(io)).jdop,
//           JournalInternalOp);
//       assert JournalCache.NextStep(
//           CommitterModel.I(cm),
//           CommitterModel.I(cm'),
//           IDiskOp(diskOp(io)).jdop,
//           JournalInternalOp,
//           JournalCache.NoOpStep);
//     }
//   }

//   function {:opaque} tryFinishLoadingOtherPhase(cm: CM, io: IO) : (res: (CM, IO))
//   requires CommitterModel.Inv(cm)
//   requires cm.status.StatusLoadingOther?
//   requires io.IOInit?
//   {
//     var hasFront := JournalistModel.hasFront(cm.journalist);
//     var hasBack := JournalistModel.hasBack(cm.journalist);
//     if cm.superblock.journalLen > 0 && !cm.journalFrontRead.Some? && !hasFront then (
//       PageInJournalReqFront(cm, io)
//     ) else if cm.superblock.journalStart + cm.superblock.journalLen > NumJournalBlocks() && !cm.journalBackRead.Some? && !hasBack then (
//       PageInJournalReqBack(cm, io)
//     ) else if (cm.superblock.journalLen > 0 ==> hasFront)
//         && (cm.superblock.journalStart + cm.superblock.journalLen > NumJournalBlocks() ==> hasBack) then (
//       var cm' := FinishLoadingOtherPhase(cm);
//       (cm', io)
//     ) else (
//       (cm, io)
//     )
//   }

//   lemma tryFinishLoadingOtherPhaseCorrect(cm: CM, io: IO)
//   requires cm.status.StatusLoadingOther?
//   requires CommitterModel.Inv(cm)
//   requires io.IOInit?
//   ensures var (cm', io') := tryFinishLoadingOtherPhase(cm, io);
//     && CommitterModel.WF(cm')
//     && ValidDiskOp(diskOp(io'))
//     && IDiskOp(diskOp(io')).bdop.NoDiskOp?
//     && JournalCache.Next(
//         CommitterModel.I(cm),
//         CommitterModel.I(cm'),
//         IDiskOp(diskOp(io')).jdop,
//         JournalInternalOp)
//   {
//     reveal_tryFinishLoadingOtherPhase();
//     var (cm', io') := tryFinishLoadingOtherPhase(cm, io);
//     var hasFront := JournalistModel.hasFront(cm.journalist);
//     var hasBack := JournalistModel.hasBack(cm.journalist);
//     if cm.superblock.journalLen > 0 && !cm.journalFrontRead.Some? && !hasFront {
//       PageInJournalReqFrontCorrect(cm, io);
//     } else if cm.superblock.journalStart + cm.superblock.journalLen > NumJournalBlocks() && !cm.journalBackRead.Some? && !hasBack {
//       PageInJournalReqBackCorrect(cm, io);
//     } else if (cm.superblock.journalLen > 0 ==> hasFront)
//         && (cm.superblock.journalStart + cm.superblock.journalLen > NumJournalBlocks() ==> hasBack) {
//       FinishLoadingOtherPhaseCorrect(cm);
//     } else {
//       assert JournalCache.NoOp(
//           CommitterModel.I(cm),
//           CommitterModel.I(cm'),
//           IDiskOp(diskOp(io)).jdop,
//           JournalInternalOp);
//       assert JournalCache.NextStep(
//           CommitterModel.I(cm),
//           CommitterModel.I(cm'),
//           IDiskOp(diskOp(io)).jdop,
//           JournalInternalOp,
//           JournalCache.NoOpStep);
//     }
//   }
// }
