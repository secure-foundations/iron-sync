include "Main.dfy"
include "BetreeBlockCache.dfy"
include "ByteBetree.dfy"

module {:extern} Impl refines Main {
  import BC = BetreeGraphBlockCache
  import BetreeBC = BetreeBlockCache
  import BT = PivotBetreeSpec`Internal
  import M = BetreeBlockCache
  import Marshalling
  import Messages = ValueMessage

  type Variables = M.Variables
  type Constants = M.Constants

  class ImplHeapState {
    var s: Variables
    constructor()
    ensures BetreeBC.Init(BC.Constants(), s);
    {
      s := BC.Unready;
    }
  }
  type HeapState = ImplHeapState
  function HeapSet(hs: HeapState) : set<object> { {hs} }

  function Ik(k: Constants) : M.Constants { k }
  function I(k: Constants, hs: HeapState) : M.Variables { hs.s }

  predicate ValidSector(sector: Sector)
  {
    && Marshalling.parseSector(sector).Some?
  }

  function ISector(sector: Sector) : M.Sector
  {
    Marshalling.parseSector(sector).value
  }

  function ILBA(lba: LBA) : M.LBA { lba }

  predicate Inv(k: Constants, hs: HeapState)
  {
    BetreeBC.Inv(k, hs.s)
  }

  method InitState() returns (k: Constants, hs: HeapState)
  {
    k := BC.Constants();
    hs := new ImplHeapState();

    BetreeBC.InitImpliesInv(k, hs.s);
  }

  predicate WFSector(sector: M.Sector)
  {
    match sector {
      case SectorSuperblock(superblock) => BC.WFPersistentSuperblock(superblock)
      case SectorBlock(node) => BT.WFNode(node)
    }
  }

  method ReadSector(io: DiskIOHandler, lba: M.LBA)
  returns (sector: M.Sector)
  requires io.initialized()
  modifies io
  ensures IDiskOp(io.diskOp()) == D.ReadOp(lba, sector)
  ensures WFSector(sector)
  {
    var bytes := io.read(lba);
    var sectorOpt := Marshalling.ParseSector(bytes);
    sector := sectorOpt.value;
  }

  method PageInSuperblock(k: Constants, s: Variables, io: DiskIOHandler)
  returns (s': Variables)
  requires io.initialized();
  requires s.Unready?
  modifies io
  ensures M.Next(Ik(k), s, s', UI.NoOp, IDiskOp(io.diskOp()))
  {
    var sector := ReadSector(io, BC.SuperblockLBA());
    if (sector.SectorSuperblock?) {
      s' := BC.Ready(sector.superblock, sector.superblock, map[]);
    }
  }

  method PageIn(k: Constants, s: Variables, io: DiskIOHandler, ref: BC.Reference)
  returns (s': Variables)
  requires io.initialized();
  requires s.Ready?
  requires ref in s.ephemeralSuperblock.lbas
  requires ref !in s.cache
  modifies io
  ensures M.Next(Ik(k), s, s', UI.NoOp, IDiskOp(io.diskOp()))
  {
    var lba := s.ephemeralSuperblock.lbas[ref];
    var sector := ReadSector(io, lba);
    if (sector.SectorBlock?) {
      s' := s.(cache := s.cache[ref := sector.block]);
    }
  }

  method InsertKeyValue(k: Constants, s: Variables, key: MS.Key, value: MS.Value)
  returns (s': Variables)
  requires BetreeBC.Inv(k, s)
  requires s.Ready?
  requires BT.G.Root() in s.cache
  ensures M.Next(Ik(k), s, s', UI.PutOp(key, value), D.NoDiskOp)
  {
    var oldroot := s.cache[BT.G.Root()];
    var newroot := BT.AddMessageToNode(oldroot, key, Messages.Define(value));
    s' := s.(cache := s.cache[BT.G.Root() := newroot]);
  }

  method doStuff(k: Constants, s: Variables, io: DiskIOHandler)
  returns (s': Variables)
  requires io.initialized()
  modifies io
  ensures M.Next(Ik(k), s, s', UI.NoOp, IDiskOp(io.diskOp()))
  {
    if (s.Unready?) {
      s' := PageInSuperblock(k, s, io);
      assert M.NextStep(Ik(k), s, s', UI.NoOp, IDiskOp(io.diskOp()), M.BlockCacheMoveStep(BC.PageInSuperblockStep));
    } else {
      assume false;
    }
  }

  method query(k: Constants, s: Variables, io: DiskIOHandler, key: MS.Key)
  returns (s': Variables, res: Option<MS.Value>)
  requires io.initialized()
  modifies io
  ensures M.Next(Ik(k), s, s',
    if res.Some? then UI.GetOp(key, res.value) else UI.NoOp,
    IDiskOp(io.diskOp()))
    /*
  {
    if (s.Unready?) {
      s' := PageInSuperblock(k, s, io);
    } else {
      var ref := BT.G.Root();
      var msg := Messages.IdentityMessage();
      ghost var lookup := [];

      while !msg.Define?
      {
        if (ref !in s.cache) {
          s' := PageIn(k, s, io, ref);
          value := None;
          return;
        } else {
          var node := s.cache[ref];
          lookup := lookup + [BT.G.ReadOp(ref, node)];
          msg := Messages.MergeMessages(msg, 
        }
      }

      if msg.Define? {
        s' := s;
        value := msg.value;
      } else {
        s' := s;
        value := MS.ValueWithDefault.DefaultValue();
      }
    }
  }
  */

  method insert(k: Constants, s: Variables, io: DiskIOHandler, key: MS.Key, value: MS.Value)
  returns (s': Variables, success: bool)
  requires io.initialized()
  modifies io
  ensures M.Next(Ik(k), s, s',
    if success then UI.PutOp(key, value) else UI.NoOp,
    IDiskOp(io.diskOp()))
  {
    if (s.Unready?) {
      s' := PageInSuperblock(k, s, io);
      success := false;
      return;
    }

    if (BT.G.Root() !in s.cache) {
      s' := PageIn(k, s, io, BT.G.Root());
      success := false;
      return;
    }

    s' := InsertKeyValue(k, s, key, value);
    success := true;
  }

  ////////// Top-level handlers

  method handle(k: Constants, hs: HeapState, io: DiskIOHandler)
  {
    var s := hs.s;
    var s' := doStuff(k, s, io);
    hs.s := s';
  }

  method handleQuery(k: Constants, hs: HeapState, io: DiskIOHandler, key: MS.Key)
  returns (v: Option<MS.Value>)
  {
    var s := hs.s;
    var s', value := query(k, s, io, key);
    hs.s := s';
    v := value;
  }

  method handleInsert(k: Constants, hs: HeapState, io: DiskIOHandler, key: MS.Key, value: MS.Value)
  returns (success: bool)
  {
    var s := hs.s;
    var s', succ := insert(k, s, io, key, value);
    hs.s := s';
    success := succ;
  }

}
