include "StateBCModel.i.dfy"
include "../ByteBlockCacheSystem/ByteCache.i.dfy"
include "MarshallingModel.i.dfy"
include "DiskOpModel.i.dfy"

//
// IO functions used by various StateModel verbs.
// Updates data structures as defined in StateModel.
// Interacts with the disk via StateModel.IO, which abstracts
// MainDiskIOHandlers.s.dfy.
//
// Also, the code that reads in indirection tables and nodes.
//

module IOModel { 
  // import opened StateModel
  import opened DiskOpModel
  import opened NativeTypes
  import opened Options
  import opened Maps
  import opened Bounds
  import opened BucketWeights
  import opened ViewOp
  import IMM = MarshallingModel
  import Marshalling = Marshalling
  import opened DiskLayout
  import opened InterpretationDiskOps
  import BucketsLib
  import LruModel
  import M = ByteCache
  import BlockDisk
  import JournalDisk
  import BlockJournalDisk
  import UI
  // Misc utilities
  import BBC = BetreeCache
  import SSM = StateSectorModel
  import IndirectionTable

  import opened StateBCModel

  type Sector = SSM.Sector
  
  predicate stepsBetree(s: BBC.Variables, s': BBC.Variables, vop: VOp, step: BT.BetreeStep)
  {
    BBC.NextStep(s, s', BlockDisk.NoDiskOp, vop, BBC.BetreeMoveStep(step))
  }

  predicate stepsBC(s: BBC.Variables, s': BBC.Variables, vop: VOp, io: IO, step: BC.Step)
  {
    && ValidDiskOp(diskOp(io))
    && BBC.NextStep(s, s', IDiskOp(diskOp(io)).bdop, vop, BBC.BlockCacheMoveStep(step))
  }

  predicate noop(s: BBC.Variables, s': BBC.Variables)
  {
    BBC.NextStep(s, s', BlockDisk.NoDiskOp, StatesInternalOp, BBC.BlockCacheMoveStep(BC.NoOpStep))
  }

  // TODO(jonh): rename to indicate this is only nops.
  predicate betree_next(s: BBC.Variables, s': BBC.Variables)
  {
    || BBC.Next(s, s', BlockDisk.NoDiskOp, StatesInternalOp)
    || BBC.Next(s, s', BlockDisk.NoDiskOp, AdvanceOp(UI.NoOp, true))
  }

  predicate betree_next_dop(s: BBC.Variables, s': BBC.Variables, dop: BlockDisk.DiskOp)
  {
    || BBC.Next(s, s', dop, StatesInternalOp)
    || BBC.Next(s, s', dop, AdvanceOp(UI.NoOp, true))
  }

  // models of IO-related methods

  predicate LocAvailable(s: BCVariables, loc: Location, len: uint64)
  requires WFBCVars(s)
  {
    && s.Ready?
    && ValidNodeLocation(loc)
    && BC.ValidAllocation(IBlockCache(s), loc)
    && loc.len == len
  }

  function {:opaque} getFreeLoc(s: BCVariables, len: uint64)
  : (res : Option<Location>)
  requires s.Ready?
  requires WFBCVars(s)
  requires len <= NodeBlockSizeUint64()
  ensures res.Some? ==> 0 <= res.value.addr as int / NodeBlockSize() < NumBlocks()
  {
    var i := BlockAllocatorModel.Alloc(s.blockAllocator);
    if i.Some? then
      Some(DiskLayout.Location((i.value * NodeBlockSize()) as uint64, len))
    else
      None
  }

  lemma getFreeLocCorrect(s: BCVariables, len: uint64)
  requires getFreeLoc.requires(s, len);
  requires len <= NodeBlockSizeUint64()
  ensures var loc := getFreeLoc(s, len);
    && (loc.Some? ==> LocAvailable(s, loc.value, len))
  {
    reveal_getFreeLoc();
    reveal_ConsistentBitmap();
    DiskLayout.reveal_ValidNodeAddr();

    var loc := getFreeLoc(s, len);
    if loc.Some? {
      var i := BlockAllocatorModel.Alloc(s.blockAllocator);

      BlockAllocatorModel.LemmaAllocResult(s.blockAllocator);
      assert !IndirectionTable.IndirectionTable.IsLocAllocBitmap(s.blockAllocator.ephemeral, i.value);
      assert s.blockAllocator.frozen.Some? ==>
          !IndirectionTable.IndirectionTable.IsLocAllocBitmap(s.blockAllocator.frozen.value, i.value);
      assert !IndirectionTable.IndirectionTable.IsLocAllocBitmap(s.blockAllocator.persistent, i.value);
      assert !IndirectionTable.IndirectionTable.IsLocAllocBitmap(s.blockAllocator.outstanding, i.value);

      //assert BC.ValidNodeLocation(loc.value);
      //assert BC.ValidAllocation(IVars(s), loc.value);
    }
  }

  predicate {:opaque} RequestWrite(
      io: IO, loc: DiskLayout.Location, sector: Sector,
      id: D.ReqId, io': IO)
  {
    && var dop := diskOp(io');
    && dop.ReqWriteOp?
    && var bytes: seq<byte> := dop.reqWrite.bytes;
    && |bytes| == 4096
    && IMM.parseCheckedSector(bytes).Some?
    && SSM.WFSector(sector)
    // Note: we have to say this instead of just
    //     IMM.parseCheckedSector(bytes).value == sector
    // because the indirection table might not parse to an indirection table
    // with exactly the same internals.
    && SSM.ISector(IMM.parseCheckedSector(bytes).value) == SSM.ISector(sector)

    && |bytes| == loc.len as int
    && id == dop.id
    && dop == D.ReqWriteOp(id, D.ReqWrite(loc.addr, bytes))
    && io' == IOReqWrite(id, dop.reqWrite)
  }

  lemma RequestWriteCorrect(io: IO, loc: DiskLayout.Location, sector: Sector,
      id: D.ReqId, io': IO)
  requires SSM.WFSector(sector)
  requires sector.SectorNode? ==> BT.WFNode(SSM.INode(sector.node))
  requires DiskLayout.ValidLocation(loc)
  requires DiskLayout.ValidSuperblockLocation(loc)
  requires sector.SectorSuperblock?
  requires RequestWrite(io, loc, sector, id, io');
  ensures ValidDiskOp(diskOp(io'))
  ensures ValidSuperblock1Location(loc) ==>
    IDiskOp(diskOp(io')) == BlockJournalDisk.DiskOp(BlockDisk.NoDiskOp, JournalDisk.ReqWriteSuperblockOp(id, 0, JournalDisk.ReqWriteSuperblock(sector.superblock)))
  ensures ValidSuperblock2Location(loc) ==>
    IDiskOp(diskOp(io')) == BlockJournalDisk.DiskOp(BlockDisk.NoDiskOp, JournalDisk.ReqWriteSuperblockOp(id, 1, JournalDisk.ReqWriteSuperblock(sector.superblock)))
  {
    reveal_RequestWrite();
    IMM.reveal_parseCheckedSector();
    IMM.reveal_parseSector();
    Marshalling.reveal_parseSector();
    reveal_SectorOfBytes();
    reveal_ValidCheckedBytes();
    reveal_Parse();
    D.reveal_ChecksumChecksOut();
    Marshalling.reveal_parseSector();
  }

  predicate {:opaque} FindLocationAndRequestWrite(io: IO, s: BCVariables, sector: Sector,
      id: Option<D.ReqId>, loc: Option<DiskLayout.Location>, io': IO)
  requires s.Ready?
  requires WFBCVars(s)
  ensures FindLocationAndRequestWrite(io, s, sector, id, loc, io') ==>
      loc.Some? ==> 0 <= loc.value.addr as int / NodeBlockSize() < NumBlocks()
  {
    && var dop := diskOp(io');
    && (dop.NoDiskOp? || dop.ReqWriteOp?)
    && (dop.NoDiskOp? ==> (
      && id == None
      && loc == None
      && io' == io
    ))
    && (dop.ReqWriteOp? ==> (
      var bytes: seq<byte> := dop.reqWrite.bytes;
      && |bytes| <= NodeBlockSize() as int
      && 32 <= |bytes|
      && IMM.parseCheckedSector(bytes).Some?
      && SSM.WFSector(sector)
      && SSM.ISector(IMM.parseCheckedSector(bytes).value) == SSM.ISector(sector)

      && var len := |bytes| as uint64;
      && loc == getFreeLoc(s, len)
      && loc.Some?

      && id == Some(dop.id)
      && dop == D.ReqWriteOp(id.value, D.ReqWrite(loc.value.addr, bytes))
      && io' == IOReqWrite(id.value, dop.reqWrite)
    ))
  }

  // ========= temporary solution ===========
  predicate SimilarVariables(s: BCVariables, s': BCVariables)
  requires s.Ready?
  requires s'.Ready?
  {
    && s.persistentIndirectionTable == s'.persistentIndirectionTable
    && s.frozenIndirectionTable == s'.frozenIndirectionTable
    && s.ephemeralIndirectionTable == s'.ephemeralIndirectionTable
    && s.persistentIndirectionTableLoc == s'.persistentIndirectionTableLoc
    && s.frozenIndirectionTableLoc == s'.frozenIndirectionTableLoc
    && s.outstandingIndirectionTableWrite == s'.outstandingIndirectionTableWrite
    && s.outstandingBlockWrites == s'.outstandingBlockWrites
    && s.outstandingBlockReads == s'.outstandingBlockReads
    && s.cache.Keys == s'.cache.Keys
    && s.lru == s'.lru
    && s.blockAllocator == s'.blockAllocator
  }

  lemma SimilarVariablesGuarantees(io: IO, s: BCVariables, s': BCVariables, sector: Sector,
      id: Option<D.ReqId>, loc: Option<DiskLayout.Location>, io': IO)
  requires s.Ready?
  requires WFBCVars(s)
  requires FindLocationAndRequestWrite(io, s, sector, id, loc, io')
  requires s'.Ready?
  requires WFBCVars(s')
  requires SimilarVariables(s, s')
  ensures FindLocationAndRequestWrite(io, s', sector, id, loc, io')
  {
    reveal_FindLocationAndRequestWrite();
    var dop := diskOp(io');
    if dop.ReqWriteOp? {
      var bytes: seq<byte> := dop.reqWrite.bytes;
      var len := |bytes| as uint64;
      reveal_getFreeLoc();
      assert getFreeLoc(s, len) == getFreeLoc(s', len);
    }
  }
  // ===================================

  lemma FindLocationAndRequestWriteCorrect(io: IO, s: BCVariables, sector: Sector, id: Option<D.ReqId>, loc: Option<DiskLayout.Location>, io': IO)
  requires WFBCVars(s)
  requires s.Ready?
  requires SSM.WFSector(sector)
  requires sector.SectorNode?
  requires sector.SectorNode? ==> BT.WFNode(SSM.INode(sector.node))
  requires FindLocationAndRequestWrite(io, s, sector, id, loc, io')
  ensures ValidDiskOp(diskOp(io'))
  ensures id.Some? ==> loc.Some?
  ensures id.Some? ==> DiskLayout.ValidLocation(loc.value)
  ensures id.Some? ==> sector.SectorNode? ==> BC.ValidAllocation(IBlockCache(s), loc.value)
  ensures id.Some? ==> sector.SectorNode? ==> ValidNodeLocation(loc.value)
  //ensures id.Some? ==> sector.SectorIndirectionTable? ==> ValidIndirectionTableLocation(loc.value)
  ensures sector.SectorNode? ==> id.Some? ==> IDiskOp(diskOp(io')) == BlockJournalDisk.DiskOp(BlockDisk.ReqWriteNodeOp(id.value, BlockDisk.ReqWriteNode(loc.value, SSM.ISector(sector).node)), JournalDisk.NoDiskOp)
  //ensures sector.SectorIndirectionTable? ==> id.Some? ==> IDiskOp(diskOp(io')) == BlockJournalDisk.DiskOp(BlockDisk.ReqWriteIndirectionTableOp(id.value, BlockDisk.ReqWriteIndirectionTable(loc.value, SSM.ISector(sector).indirectionTable)), JournalDisk.NoDiskOp)
  ensures id.None? ==> io' == io
  {
    reveal_FindLocationAndRequestWrite();
    IMM.reveal_parseSector();
    IMM.reveal_parseCheckedSector();
    Marshalling.reveal_parseSector();
    reveal_SectorOfBytes();
    reveal_ValidCheckedBytes();
    reveal_Parse();
    D.reveal_ChecksumChecksOut();
    Marshalling.reveal_parseSector();

    var dop := diskOp(io');
    if dop.ReqWriteOp? {
      var bytes: seq<byte> := dop.reqWrite.bytes;
      var len := |bytes| as uint64;

      getFreeLocCorrect(s, len);
    }
  }

  predicate {:opaque} FindIndirectionTableLocationAndRequestWrite(io: IO, s: BCVariables, sector: Sector,
      id: Option<D.ReqId>, loc: Option<DiskLayout.Location>, io': IO)
  requires s.Ready?
  requires WFBCVars(s)
  ensures FindIndirectionTableLocationAndRequestWrite(io, s, sector, id, loc, io') ==>
      loc.Some? ==> 0 <= loc.value.addr as int / NodeBlockSize() < NumBlocks()
  {
    && var dop := diskOp(io');
    && (dop.NoDiskOp? || dop.ReqWriteOp?)
    && (dop.NoDiskOp? ==> (
      && id == None
      && loc == None
      && io' == io
    ))
    && (dop.ReqWriteOp? ==> (
      var bytes: seq<byte> := dop.reqWrite.bytes;
      && |bytes| <= IndirectionTableMaxLength() as int
      && 32 <= |bytes|
      && IMM.parseCheckedSector(bytes).Some?
      && SSM.WFSector(sector)
      && SSM.ISector(IMM.parseCheckedSector(bytes).value) == SSM.ISector(sector)

      && var len := |bytes| as uint64;
      && loc == Some(DiskLayout.Location(
        otherIndirectionTableAddr(s.persistentIndirectionTableLoc.addr),
        len))

      && id == Some(dop.id)
      && dop == D.ReqWriteOp(id.value, D.ReqWrite(loc.value.addr, bytes))
      && io' == IOReqWrite(id.value, dop.reqWrite)
    ))
  }

  lemma FindIndirectionTableLocationAndRequestWriteCorrect(io: IO, s: BCVariables, sector: Sector, id: Option<D.ReqId>, loc: Option<DiskLayout.Location>, io': IO)
  requires BCInv(s)
  requires s.Ready?
  requires SSM.WFSector(sector)
  requires sector.SectorIndirectionTable?
  requires FindIndirectionTableLocationAndRequestWrite(io, s, sector, id, loc, io')
  ensures ValidDiskOp(diskOp(io'))
  ensures id.Some? ==> loc.Some?
  ensures id.Some? ==> DiskLayout.ValidIndirectionTableLocation(loc.value)
  ensures id.Some? ==> IDiskOp(diskOp(io')) == BlockJournalDisk.DiskOp(BlockDisk.ReqWriteIndirectionTableOp(id.value, BlockDisk.ReqWriteIndirectionTable(loc.value, SSM.ISector(sector).indirectionTable)), JournalDisk.NoDiskOp)
  ensures loc.Some? ==> !overlap(loc.value, s.persistentIndirectionTableLoc)
  ensures id.None? ==> io' == io
  {
    reveal_FindIndirectionTableLocationAndRequestWrite();
    IMM.reveal_parseSector();
    IMM.reveal_parseCheckedSector();
    Marshalling.reveal_parseSector();
    reveal_SectorOfBytes();
    reveal_ValidCheckedBytes();
    reveal_Parse();
    D.reveal_ChecksumChecksOut();
    Marshalling.reveal_parseSector();

    var dop := diskOp(io');
    if dop.ReqWriteOp? {
      if overlap(loc.value, s.persistentIndirectionTableLoc) {
        overlappingIndirectionTablesSameAddr(
            loc.value, s.persistentIndirectionTableLoc);
        assert false;
      }

      var bytes: seq<byte> := dop.reqWrite.bytes;
      var len := |bytes| as uint64;
    }
  }

  function RequestRead(io: IO, loc: DiskLayout.Location)
  : (res : (D.ReqId, IO))
  requires io.IOInit?
  {
    (io.id, IOReqRead(io.id, D.ReqRead(loc.addr, loc.len)))
  }

  lemma RequestReadCorrect(io: IO, loc: DiskLayout.Location)
  requires io.IOInit?
  requires DiskLayout.ValidLocation(loc)
  ensures var (id, io') := RequestRead(io, loc);
    && ValidDiskOp(diskOp(io'))
    && (ValidNodeLocation(loc) ==> IDiskOp(diskOp(io')) == BlockJournalDisk.DiskOp(BlockDisk.ReqReadNodeOp(id, loc), JournalDisk.NoDiskOp))
    && (ValidIndirectionTableLocation(loc) ==> IDiskOp(diskOp(io')) == BlockJournalDisk.DiskOp(BlockDisk.ReqReadIndirectionTableOp(id, loc), JournalDisk.NoDiskOp))
    && (ValidSuperblock1Location(loc) ==> IDiskOp(diskOp(io')) == BlockJournalDisk.DiskOp(BlockDisk.NoDiskOp, JournalDisk.ReqReadSuperblockOp(id, 0)))
    && (ValidSuperblock2Location(loc) ==> IDiskOp(diskOp(io')) == BlockJournalDisk.DiskOp(BlockDisk.NoDiskOp, JournalDisk.ReqReadSuperblockOp(id, 1)))
  {
  }

  function {:opaque} PageInIndirectionTableReq(s: BCVariables, io: IO)
  : (res : (BCVariables, IO))
  requires io.IOInit?
  requires s.LoadingIndirectionTable?
  requires ValidIndirectionTableLocation(s.indirectionTableLoc)
  {
    if (s.indirectionTableRead.None?) then (
      var (id, io') := RequestRead(io, s.indirectionTableLoc);
      var s' := s.(indirectionTableRead := Some(id));
      (s', io')
    ) else (
      (s, io)
    )
  }

  lemma PageInIndirectionTableReqCorrect(s: BCVariables, io: IO)
  requires WFBCVars(s)
  requires io.IOInit?
  requires s.LoadingIndirectionTable?
  requires ValidIndirectionTableLocation(s.indirectionTableLoc)
  ensures var (s', io') := PageInIndirectionTableReq(s, io);
    && WFBCVars(s')
    && ValidDiskOp(diskOp(io'))
    && IDiskOp(diskOp(io')).jdop.NoDiskOp?
    && BBC.Next(IBlockCache(s), IBlockCache(s'), IDiskOp(diskOp(io')).bdop, StatesInternalOp)
  {
    reveal_PageInIndirectionTableReq();
    var (s', io') := PageInIndirectionTableReq(s, io);
    if (s.indirectionTableRead.None?) {
      RequestReadCorrect(io, s.indirectionTableLoc);
      //assert BC.PageInIndirectionTableReq(IVars(s), IVars(s'), IDiskOp(diskOp(io')));
      //assert BBC.BlockCacheMove(IVars(s), IVars(s'), UI.NoOp, IDiskOp(diskOp(io')), BC.PageInIndirectionTableReqStep);
      //assert BBC.NextStep(IVars(s), IVars(s'), UI.NoOp, IDiskOp(diskOp(io')), BBC.BlockCacheMoveStep(BC.PageInIndirectionTableReqStep));
      assert stepsBC(IBlockCache(s), IBlockCache(s'), StatesInternalOp, io', BC.PageInIndirectionTableReqStep);
    } else {
      assert noop(IBlockCache(s), IBlockCache(s'));
    }
  }

  function PageInNodeReq(s: BCVariables, io: IO, ref: BC.Reference)
  : (res : (BCVariables, IO))
  requires s.Ready?
  requires io.IOInit?
  requires ref in s.ephemeralIndirectionTable.I().locs;
  {
    if (BC.OutstandingRead(ref) in s.outstandingBlockReads.Values) then (
      (s, io)
    ) else (
      var loc := s.ephemeralIndirectionTable.locs[ref];
      var (id, io') := RequestRead(io, loc);
      var s' := s
        .(outstandingBlockReads := s.outstandingBlockReads[id := BC.OutstandingRead(ref)]);
      (s', io')
    )
  }

  lemma PageInNodeReqCorrect(s: BCVariables, io: IO, ref: BC.Reference)
  requires io.IOInit?
  requires s.Ready?
  requires WFBCVars(s)
  requires BBC.Inv(IBlockCache(s))
  requires ref in s.ephemeralIndirectionTable.locs;
  requires ref !in s.cache
  requires TotalCacheSize(s) <= MaxCacheSize() - 1
  ensures var (s', io') := PageInNodeReq(s, io, ref);
    && WFBCVars(s')
    && ValidDiskOp(diskOp(io'))
    && BBC.Next(IBlockCache(s), IBlockCache(s'), IDiskOp(diskOp(io')).bdop, StatesInternalOp)
  {
    if (BC.OutstandingRead(ref) in s.outstandingBlockReads.Values) {
      assert noop(IBlockCache(s), IBlockCache(s));
    } else {
      var loc := s.ephemeralIndirectionTable.locs[ref];
      assert ref in s.ephemeralIndirectionTable.I().locs;
      assert ValidNodeLocation(loc);
      var (id, io') := RequestRead(io, loc);
      var s' := s.(outstandingBlockReads := s.outstandingBlockReads[id := BC.OutstandingRead(ref)]);

      assert WFBCVars(s');

      assert BC.PageInNodeReq(IBlockCache(s), IBlockCache(s'), IDiskOp(diskOp(io')).bdop, StatesInternalOp, ref);
      assert stepsBC(IBlockCache(s), IBlockCache(s'), StatesInternalOp, io', BC.PageInNodeReqStep(ref));
    }
  }

  // == readResponse ==

  function ISectorOpt(sector: Option<Sector>) : Option<SectorType.Sector>
  requires sector.Some? ==> SSM.WFSector(sector.value)
  {
    match sector {
      case None => None
      case Some(sector) => Some(SSM.ISector(sector))
    }
  }

  function ReadSector(io: IO)
  : (res : (D.ReqId, Option<Sector>))
  requires diskOp(io).RespReadOp?
  {
    var id := io.id;
    var bytes := io.respRead.bytes;
    if |bytes| <= IndirectionTableBlockSize() then (
      var loc := DiskLayout.Location(io.respRead.addr, |io.respRead.bytes| as uint64);
      var sector := IMM.parseCheckedSector(bytes);
      if sector.Some? && (
        || (ValidNodeLocation(loc) && sector.value.SectorNode?)
        || (ValidSuperblockLocation(loc) && sector.value.SectorSuperblock?)
        || (ValidIndirectionTableLocation(loc) && sector.value.SectorIndirectionTable?)
      )
      then
        (id, sector)
      else
        (id, None)
    ) else (
      (id, None)
    )
  }

  lemma ReadSectorCorrect(io: IO)
  requires diskOp(io).RespReadOp?
  requires ValidDiskOp(diskOp(io))
  ensures var (id, sector) := ReadSector(io);
    && (sector.Some? ==> (
      && SSM.WFSector(sector.value)
      && ValidDiskOp(diskOp(io))
      && (sector.value.SectorNode? ==> IDiskOp(diskOp(io)) == BlockJournalDisk.DiskOp(BlockDisk.RespReadNodeOp(id, Some(SSM.INode(sector.value.node))), JournalDisk.NoDiskOp))
      && (sector.value.SectorIndirectionTable? ==> IDiskOp(diskOp(io)) == BlockJournalDisk.DiskOp(BlockDisk.RespReadIndirectionTableOp(id, Some(sector.value.indirectionTable.I())), JournalDisk.NoDiskOp))
      && (sector.value.SectorSuperblock? ==>
        && IDiskOp(diskOp(io)).bdop == BlockDisk.NoDiskOp
        && IDiskOp(diskOp(io)).jdop.RespReadSuperblockOp?
        && IDiskOp(diskOp(io)).jdop.id == id
        && IDiskOp(diskOp(io)).jdop.superblock == Some(sector.value.superblock)
      )
    ))
    && ((IDiskOp(diskOp(io)).jdop.RespReadSuperblockOp? && IDiskOp(diskOp(io)).jdop.superblock.Some?) ==> (
      && sector.Some?
      && sector.value.SectorSuperblock?
    ))
  {
    IMM.reveal_parseCheckedSector();
    Marshalling.reveal_parseSector();
    IMM.reveal_parseSector();
    reveal_SectorOfBytes();
    reveal_ValidCheckedBytes();
    reveal_Parse();
    D.reveal_ChecksumChecksOut();
  }

  function PageInIndirectionTableResp(s: BCVariables, io: IO)
  : (s' : BCVariables)
  requires diskOp(io).RespReadOp?
  requires s.LoadingIndirectionTable?
  {
    var (id, sector) := ReadSector(io);
    if (Some(id) == s.indirectionTableRead && sector.Some? && sector.value.SectorIndirectionTable?) then (
      var ephemeralIndirectionTable := sector.value.indirectionTable;
      var (succ, bm) := ephemeralIndirectionTable.initLocBitmap();
      if succ then (
        var blockAllocator := BlockAllocatorModel.InitBlockAllocator(bm);
        var persistentIndirectionTable := sector.value.indirectionTable.clone();
        Ready(persistentIndirectionTable, None, ephemeralIndirectionTable, s.indirectionTableLoc, None, None, map[], map[], map[], LruModel.Empty(), blockAllocator)
      ) else (
        s
      )
    ) else (
      s
    )
  }

  lemma PageInIndirectionTableRespCorrect(s: BCVariables, io: IO)
  requires BCInv(s)
  requires diskOp(io).RespReadOp?
  requires s.LoadingIndirectionTable?
  requires ValidDiskOp(diskOp(io))
  requires ValidIndirectionTableLocation(LocOfRespRead(diskOp(io).respRead))
  ensures var s' := PageInIndirectionTableResp(s, io);
    && WFBCVars(s')
    && ValidDiskOp(diskOp(io))
    && IDiskOp(diskOp(io)).jdop.NoDiskOp?
    && BBC.Next(IBlockCache(s), IBlockCache(s'), IDiskOp(diskOp(io)).bdop, StatesInternalOp)
  {
    var (id, sector) := ReadSector(io);
    ReadSectorCorrect(io);

    Marshalling.reveal_parseSector();
    reveal_SectorOfBytes();
    reveal_Parse();

    var s' := PageInIndirectionTableResp(s, io);
    if (Some(id) == s.indirectionTableRead && sector.Some? && sector.value.SectorIndirectionTable?) {
      var ephemeralIndirectionTable := sector.value.indirectionTable;
      var (succ, bm) := ephemeralIndirectionTable.initLocBitmap();
      if succ {
        WeightBucketEmpty();

        reveal_ConsistentBitmap();
        assert ConsistentBitmap(s'.ephemeralIndirectionTable.I(), MapOption(s'.frozenIndirectionTable, (x: IndirectionTable.IndirectionTable) => x.I()),
          s'.persistentIndirectionTable.I(), s'.outstandingBlockWrites, s'.blockAllocator);

        assert WFBCVars(s');
        assert stepsBC(IBlockCache(s), IBlockCache(s'), StatesInternalOp, io, BC.PageInIndirectionTableRespStep);
        assert BBC.Next(IBlockCache(s), IBlockCache(s'), IDiskOp(diskOp(io)).bdop, StatesInternalOp);

        return;
      }
    }

    assert s == s';
    assert ValidDiskOp(diskOp(io));
    assert BC.NoOp(IBlockCache(s), IBlockCache(s'), IDiskOp(diskOp(io)).bdop, StatesInternalOp);
    assert BBC.BlockCacheMove(IBlockCache(s), IBlockCache(s), IDiskOp(diskOp(io)).bdop, StatesInternalOp, BC.NoOpStep);
    assert BBC.NextStep(IBlockCache(s), IBlockCache(s), IDiskOp(diskOp(io)).bdop, StatesInternalOp, BBC.BlockCacheMoveStep(BC.NoOpStep));
    assert stepsBC(IBlockCache(s), IBlockCache(s), StatesInternalOp, io, BC.NoOpStep);
  }

  function PageInNodeResp(s: BCVariables, io: IO)
  : (s': BCVariables)
  requires diskOp(io).RespReadOp?
  requires s.Ready?
  requires s.ephemeralIndirectionTable.Inv()
  {
    var (id, sector) := ReadSector(io);

    if (id !in s.outstandingBlockReads) then (
      s
    ) else (
      // TODO we should probably remove the id from outstandingBlockReads
      // even in the case we don't do anything with it

      var ref := s.outstandingBlockReads[id].ref;

      var locGraph := s.ephemeralIndirectionTable.getEntry(ref);
      if (locGraph.None? || locGraph.value.loc.None? || ref in s.cache) then ( // ref !in I(s.ephemeralIndirectionTable).locs || ref in s.cache
        s
      ) else (
        var succs := locGraph.value.succs;
        if (sector.Some? && sector.value.SectorNode?) then (
          var node := sector.value.node;
          if (succs == (if node.children.Some? then node.children.value else [])
              && id in s.outstandingBlockReads) then (
            s.(cache := s.cache[ref := sector.value.node])
             .(outstandingBlockReads := MapRemove1(s.outstandingBlockReads, id))
             .(lru := LruModel.Use(s.lru, ref))
          ) else (
            s
          )
        ) else (
          s
        )
      )
    )
  }

  lemma PageInNodeRespCorrect(s: BCVariables, io: IO)
  requires diskOp(io).RespReadOp?
  requires ValidDiskOp(diskOp(io))
  requires s.Ready?
  requires WFBCVars(s)
  requires BBC.Inv(IBlockCache(s))
  ensures var s' := PageInNodeResp(s, io);
    && WFBCVars(s')
    && ValidDiskOp(diskOp(io))
    && BBC.Next(IBlockCache(s), IBlockCache(s'), IDiskOp(diskOp(io)).bdop, StatesInternalOp)
  {
    var s' := PageInNodeResp(s, io);

    var (id, sector) := ReadSector(io);
    ReadSectorCorrect(io);

    Marshalling.reveal_parseSector();
    reveal_SectorOfBytes();
    reveal_Parse();

    if (id !in s.outstandingBlockReads) {
      assert stepsBC(IBlockCache(s), IBlockCache(s'), StatesInternalOp, io, BC.NoOpStep);
      return;
    }

    var ref := s.outstandingBlockReads[id].ref;
    
    var locGraph := s.ephemeralIndirectionTable.getEntry(ref);
    if (locGraph.None? || locGraph.value.loc.None? || ref in s.cache) { // ref !in I(s.ephemeralIndirectionTable).locs || ref in s.cache
      assert stepsBC(IBlockCache(s), IBlockCache(s'), StatesInternalOp, io, BC.NoOpStep);
      return;
    }

    var succs := locGraph.value.succs;

    if (sector.Some? && sector.value.SectorNode?) {
      var node := sector.value.node;
      if (succs == (if node.children.Some? then node.children.value else [])
          && id in s.outstandingBlockReads) {
        WeightBucketEmpty();

        LruModel.LruUse(s.lru, ref);

        assert |s'.cache| == |s.cache| + 1;
        assert |s'.outstandingBlockReads| == |s.outstandingBlockReads| - 1;

        assert WFBCVars(s');
        assert BC.PageInNodeResp(IBlockCache(s), IBlockCache(s'), IDiskOp(diskOp(io)).bdop, StatesInternalOp);
        assert stepsBC(IBlockCache(s), IBlockCache(s'), StatesInternalOp, io, BC.PageInNodeRespStep);
      } else {
        assert stepsBC(IBlockCache(s), IBlockCache(s'), StatesInternalOp, io, BC.NoOpStep);
      }
    } else {
      assert stepsBC(IBlockCache(s), IBlockCache(s'), StatesInternalOp, io, BC.NoOpStep);
    }
  }

  // == writeResponse ==

  lemma lemmaOutstandingLocIndexValid(s: BCVariables, id: uint64)
  requires BCInv(s)
  requires s.Ready?
  requires id in s.outstandingBlockWrites
  ensures 0 <= s.outstandingBlockWrites[id].loc.addr as int / NodeBlockSize() < NumBlocks()
  {
    reveal_ConsistentBitmap();
    var i := s.outstandingBlockWrites[id].loc.addr as int / NodeBlockSize();
    DiskLayout.reveal_ValidNodeAddr();
    assert i * NodeBlockSize() == s.outstandingBlockWrites[id].loc.addr as int;
    assert IndirectionTable.IndirectionTable.IsLocAllocBitmap(s.blockAllocator.outstanding, i);
  }

  lemma lemmaBlockAllocatorFrozenSome(s: BCVariables)
  requires BCInv(s)
  requires s.Ready?
  ensures s.frozenIndirectionTable.Some?
      ==> s.blockAllocator.frozen.Some?
  {
    reveal_ConsistentBitmap();
  }

  function writeNodeResponse(s: BCVariables, io: IO)
    : BCVariables
  requires BCInv(s)
  requires ValidDiskOp(diskOp(io))
  requires diskOp(io).RespWriteOp?
  requires s.Ready? && io.id in s.outstandingBlockWrites
  {
    var id := io.id;

    lemmaOutstandingLocIndexValid(s, id);
    var s' := s.(outstandingBlockWrites := MapRemove1(s.outstandingBlockWrites, id))
     .(blockAllocator := BlockAllocatorModel.MarkFreeOutstanding(s.blockAllocator, s.outstandingBlockWrites[id].loc.addr as int / NodeBlockSize()));
    s'
  }

  lemma writeNodeResponseCorrect(s: BCVariables, io: IO)
  requires BCInv(s)
  requires diskOp(io).RespWriteOp?
  requires ValidDiskOp(diskOp(io))
  requires ValidNodeLocation(LocOfRespWrite(diskOp(io).respWrite))
  requires s.Ready? && io.id in s.outstandingBlockWrites
  ensures var s' := writeNodeResponse(s, io);
    && WFBCVars(s')
    && BBC.Next(IBlockCache(s), IBlockCache(s'), IDiskOp(diskOp(io)).bdop,
        StatesInternalOp)
  {
    reveal_ConsistentBitmap();
    var id := io.id;
    var s' := writeNodeResponse(s, io);

    var locIdx := s.outstandingBlockWrites[id].loc.addr as int / NodeBlockSize();
    lemmaOutstandingLocIndexValid(s, id);

    DiskLayout.reveal_ValidNodeAddr();
    assert locIdx * NodeBlockSize() == s.outstandingBlockWrites[id].loc.addr as int;

    BitmapModel.reveal_BitUnset();
    BitmapModel.reveal_IsSet();

    /*forall i | 0 <= i < NumBlocks()
    ensures Bitmap.IsSet(s'.blockAllocator.full, i) == (
        || Bitmap.IsSet(s'.blockAllocator.ephemeral, i)
        || (s'.blockAllocator.frozen.Some? && Bitmap.IsSet(s'.blockAllocator.frozen.value, i))
        || Bitmap.IsSet(s'.blockAllocator.persistent, i)
        || Bitmap.IsSet(s'.blockAllocator.full, i)
      )
    {
      if i == locIdx {
        assert Bitmap.IsSet(s'.blockAllocator.full, i) == (
            || Bitmap.IsSet(s'.blockAllocator.ephemeral, i)
            || (s'.blockAllocator.frozen.Some? && Bitmap.IsSet(s'.blockAllocator.frozen.value, i))
            || Bitmap.IsSet(s'.blockAllocator.persistent, i)
            || Bitmap.IsSet(s'.blockAllocator.full, i)
        );
      } else {
        assert Bitmap.IsSet(s'.blockAllocator.full, i) == Bitmap.IsSet(s.blockAllocator.full, i);
        assert Bitmap.IsSet(s'.blockAllocator.ephemeral, i) == Bitmap.IsSet(s.blockAllocator.ephemeral, i);
        assert s'.blockAllocator.frozen.Some? ==> Bitmap.IsSet(s'.blockAllocator.frozen.value, i) == Bitmap.IsSet(s.blockAllocator.frozen.value, i);
        assert Bitmap.IsSet(s'.blockAllocator.persistent, i) == Bitmap.IsSet(s.blockAllocator.persistent, i);
        assert Bitmap.IsSet(s'.blockAllocator.outstanding, i) == Bitmap.IsSet(s.blockAllocator.outstanding, i);
      }
    }*/

    forall i: int
    | IsLocAllocOutstanding(s'.outstandingBlockWrites, i)
    ensures IndirectionTable.IndirectionTable.IsLocAllocBitmap(s'.blockAllocator.outstanding, i)
    {
      if i != locIdx {
        assert IsLocAllocOutstanding(s.outstandingBlockWrites, i);
        assert IndirectionTable.IndirectionTable.IsLocAllocBitmap(s.blockAllocator.outstanding, i);
        assert IndirectionTable.IndirectionTable.IsLocAllocBitmap(s'.blockAllocator.outstanding, i);
      } else {
        var id1 :| id1 in s'.outstandingBlockWrites && s'.outstandingBlockWrites[id1].loc.addr as int == i * NodeBlockSize() as int;
        assert BC.OutstandingBlockWritesDontOverlap(s.outstandingBlockWrites, id, id1);
        /*assert s.outstandingBlockWrites[id1].loc.addr as int
            == s'.outstandingBlockWrites[id1].loc.addr as int
            == i * NodeBlockSize() as int;
        assert id == id1;
        assert id !in s'.outstandingBlockWrites;
        assert false;*/
      }
    }

    forall i: int
    | IndirectionTable.IndirectionTable.IsLocAllocBitmap(s'.blockAllocator.outstanding, i)
    ensures IsLocAllocOutstanding(s'.outstandingBlockWrites, i)
    {
      if i != locIdx {
        assert IndirectionTable.IndirectionTable.IsLocAllocBitmap(s.blockAllocator.outstanding, i);
        assert IsLocAllocOutstanding(s'.outstandingBlockWrites, i);
      } else {
        assert IsLocAllocOutstanding(s'.outstandingBlockWrites, i);
      }
    }

    assert WFBCVars(s');
    assert stepsBC(IBlockCache(s), IBlockCache(s'), StatesInternalOp, io, BC.WriteBackNodeRespStep);
  }

  function writeIndirectionTableResponse(s: BCVariables, io: IO)
    : (BCVariables, Location)
  requires BCInv(s)
  requires ValidDiskOp(diskOp(io))
  requires diskOp(io).RespWriteOp?
  requires s.Ready?
  requires s.frozenIndirectionTableLoc.Some?
  {
    var s' := s.(outstandingIndirectionTableWrite := None);
    (s', s.frozenIndirectionTableLoc.value)
  }

  lemma writeIndirectionTableResponseCorrect(s: BCVariables, io: IO)
  requires BCInv(s)
  requires diskOp(io).RespWriteOp?
  requires ValidDiskOp(diskOp(io))
  requires s.Ready? && s.outstandingIndirectionTableWrite == Some(io.id)
  requires ValidIndirectionTableLocation(LocOfRespWrite(diskOp(io).respWrite))
  ensures var (s', loc) := writeIndirectionTableResponse(s, io);
    && WFBCVars(s')
    && BBC.Next(IBlockCache(s), IBlockCache(s'), IDiskOp(diskOp(io)).bdop,
        SendFrozenLocOp(loc))
  {
    reveal_ConsistentBitmap();
    var id := io.id;
    var (s', loc) := writeIndirectionTableResponse(s, io);
    assert WFBCVars(s');
    assert BC.WriteBackIndirectionTableResp(IBlockCache(s), IBlockCache(s'), IDiskOp(diskOp(io)).bdop,
      SendFrozenLocOp(loc));
    assert BC.NextStep(IBlockCache(s), IBlockCache(s'), IDiskOp(diskOp(io)).bdop,
      SendFrozenLocOp(loc), BC.WriteBackIndirectionTableRespStep);
    assert BBC.NextStep(IBlockCache(s), IBlockCache(s'), IDiskOp(diskOp(io)).bdop,
      SendFrozenLocOp(loc), BBC.BlockCacheMoveStep(BC.WriteBackIndirectionTableRespStep));
    assert BBC.Next(IBlockCache(s), IBlockCache(s'), IDiskOp(diskOp(io)).bdop,
      SendFrozenLocOp(loc));
  }

  function cleanUp(s: BCVariables) : BCVariables
  requires BCInv(s)
  requires s.Ready?
  requires s.frozenIndirectionTable.Some?
  requires s.frozenIndirectionTableLoc.Some?
  {
    lemmaBlockAllocatorFrozenSome(s);
    var s' := s
           .(frozenIndirectionTable := None)
           .(frozenIndirectionTableLoc := None)
           .(persistentIndirectionTableLoc := s.frozenIndirectionTableLoc.value)
           .(persistentIndirectionTable := s.frozenIndirectionTable.value)
           .(blockAllocator := BlockAllocatorModel.MoveFrozenToPersistent(s.blockAllocator));
    s'
  }

  lemma cleanUpCorrect(s: BCVariables)
  requires BCInv(s)
  requires s.Ready?
  requires s.frozenIndirectionTable.Some?
  requires s.outstandingIndirectionTableWrite.None?
  requires s.frozenIndirectionTableLoc.Some?
  ensures var s' := cleanUp(s);
    && WFBCVars(s')
    && BBC.Next(IBlockCache(s), IBlockCache(s'), BlockDisk.NoDiskOp, CleanUpOp)
  {
    reveal_ConsistentBitmap();
    var s' := cleanUp(s);
    lemmaBlockAllocatorFrozenSome(s);
    assert WFBCVars(s');
    assert BC.CleanUp(IBlockCache(s), IBlockCache(s'), BlockDisk.NoDiskOp, CleanUpOp);
    assert BC.NextStep(IBlockCache(s), IBlockCache(s'), BlockDisk.NoDiskOp,
      CleanUpOp, BC.CleanUpStep);
    assert BBC.NextStep(IBlockCache(s), IBlockCache(s'), BlockDisk.NoDiskOp,
      CleanUpOp, BBC.BlockCacheMoveStep(BC.CleanUpStep));
    assert BBC.Next(IBlockCache(s), IBlockCache(s'), BlockDisk.NoDiskOp, CleanUpOp);
  }
}
