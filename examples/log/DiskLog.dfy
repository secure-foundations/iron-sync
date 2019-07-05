include "Disk.dfy"
include "LogSpec.dfy"

module LBAType {
  import LogSpec

  type Index = LogSpec.Index

  type LBA(==,!new) = int
  function method SuperblockLBA() : LBA { 0 }

  function method indexToLBA(idx: Index) : LBA
  {
    idx.idx + 1
  }

  export S provides Index, LBA, SuperblockLBA, indexToLBA
  export extends S
	export Internal reveals *
}

module DiskLog {
  import L = LogSpec

  import D = Disk
  import LBAType

  type Element

  datatype Constants = Constants()
  type Log = seq<Element>
  datatype Superblock = Superblock(length: int)
  datatype Variables = Variables(log: Log, persistent: Option<Superblock>, stagedLength: int)

  function method SuperblockLBA() : LBA { LBAType.SuperblockLBA() }

  datatype Sector = SuperblockSector(superblock: Superblock) | LogSector(element: Element)

  predicate Init(k:Constants, s:Variables)
      ensures Init(k, s) ==> WF(s)
  {
    s == Variables([], None, 0)
  }

  predicate Query(k: Constants, s: Variables, s': Variables, diskOp: DiskOp, idx: L.Index, result: Element)
  {
    && 0 <= idx.idx < |s.log|
    && result == s.log[idx.idx]
    && diskOp == D.NoDiskOp
    && s' == s
  }

  predicate FetchSuperblock(k: Constants, s: Variables, s': Variables, diskOp: DiskOp, length: int)
  {
    && s.persistent == None
    && diskOp == D.ReadOp(SuperblockLBA(), SuperblockSector(Superblock(length)))
    && s'.log == s.log
    && s'.persistent == Some(length)
    && s'.stagedLength == s.stagedLength
  }

  predicate FetchElement(k: Constants, s: Variables, s': Variables, diskOp: DiskOp, idx: L.Index, element: Element)
  {
    && s.persistent.Some?
    && idx.idx < s.persistent.length
    && |s.log| == idx.idx
    && diskOp == D.ReadOp(indexToLBA(idx), LogSector(element))
    && s'.log == s.log + [element]
    && s'.persistent == s.persistent
    && s'.stagedLength == s.stagedLength
  }

  predicate Append(k: Constants, s: Variables, s': Variables, diskOp: DiskOp, element: Element)
  {
    && s.persistent.Some?
    && s.persistent <= |s.log|
    && diskOp == D.NoDiskOp
    && s'.log == s.log + [element]
    && s'.persistent == s.persistent
    && s'.stagedLength == s.stagedLength
  }

  predicate StageElement(k: Constants, s: Variables, s': Variables, diskOp: DiskOp)
  {
    var stagingIndex := L.Index(s.stagedLength);

    && s.persistent.Some?
    && s.persistent <= |s.log|
    && diskOp == D.WriteOp(indexToLBA(stagingIndex), s.log[stagingIndex.idx])
    && s'.log == s.log
    && s'.persistent == s.persistent
    && s'.stagedLength == s.stagedLength + 1
  }

  predicate Flush(k: Constants, s: Variables, s': Variables, diskOp: DiskOp)
  {
    var newSuperblock := Superblock(s.stagedLength);

    && s.persistent.Some?
    && s.persistent <= |s.log|
    && diskOp == D.WriteOp(SuperblockLBA(), SuperblockSector(newSuperblock))
    && s'.log == s.log
    && s'.persistent == Some(newSuperblock)
    && s'.stagedLength == s.stagedLength + 1
  }

  predicate StutterStep(k: Constants, s: Variables, s': Variables, diskOp: DiskOp)
  {
    && diskOp == D.NoDiskOp
    && s' == s
  }

  datatype Step =
      | QueryStep(diskOp: DiskOp, idx: L.Index, result: Element)
      | FetchSuperblockStep(diskOp: DiskOp, length: int)
      | FetchElementStep(diskOp: DiskOp, idx: L.Index, element: Element)
      | AppendStep(diskOp: DiskOp, element: Element)
      | StageElementStep(diskOp: DiskOp)
      | FlushStep(diskOp: DiskOp)
      | StutterStep(diskOp: DiskOp)

  predicate NextStep(k:Constants, s:Variables, s':Variables, step:Step)
  {
      match step {
        case QueryStep(diskOp: DiskOp, idx: L.Index, result: Element) => Query(k, s, s', diskOp, idx, result)
        case FetchSuperblockStep(diskOp: DiskOp, length: int) => Fetch(k, s, s', diskOp, length)
        case FetchElementStep(diskOp: DiskOp, idx: L.Index, element: Element) => FetchElement(k, s, s', diskOp, idx, element)
        case AppendStep(diskOp: DiskOp, element: Element) => Append(k, s, s', diskOp, element)
        case StageElementStep(diskOp: DiskOp) => StageElement(k, s, s', diskOp)
        case FlushStep(diskOp: DiskOp) => Flush(k, s, s', diskOp)
        case StutterStep => Stutter(k, s, s', diskOp)
      }
  }

  predicate Next(k:Constants, s:Variables, s':Variables)
  {
      exists step :: NextStep(k, s, s', step)
  }
}
