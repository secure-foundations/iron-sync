include "AtomicRefcount.i.dfy"
include "AtomicStatus.i.dfy"
include "AtomicIndexLookup.i.dfy"
include "../framework/Ptrs.s.dfy"
include "BasicLock.i.dfy"
include "../framework/AIO.s.dfy"
include "cache/CacheSM.i.dfy"
include "CacheAIOParams.i.dfy"
include "../../lib/Lang/LinearSequence.i.dfy"

module CacheTypes(aio: AIO(CacheAIOParams, CacheIfc, CacheSSM)) {
  import opened Ptrs
  import opened AtomicRefcountImpl
  import opened AtomicIndexLookupImpl
  import opened AtomicStatusImpl
  import opened Atomics
  import opened Constants
  import opened NativeTypes
  import opened BasicLockImpl
  import opened CacheHandle
  import opened IocbStruct
  import opened CacheAIOParams
  import opened GlinearSeq
  import opened LinearSequence_i
  import opened LinearSequence_s
  import RwLockToken
  import opened Cells

  linear datatype NullGhostType = NullGhostType

  linear datatype StatusIdx = StatusIdx(
    linear status: AtomicStatus,
    linear idx: Cell<int64>
  )

  linear datatype Cache = Cache(
    data_base_ptr: Ptr,
    linear read_refcounts_array: lseq<AtomicRefcount>,
    linear cache_idx_of_page_array: lseq<AtomicIndexLookup>,
    linear status_idx_array: lseq<StatusIdx>,

    ghost data: seq<Ptr>,
    ghost disk_idx_of_entry: seq<Cell<int64>>,
    ghost status: seq<AtomicStatus>,

    ghost read_refcounts: seq<seq<AtomicRefcount>>,

    ghost cache_idx_of_page: seq<AtomicIndexLookup>,

    linear global_clockpointer: Atomic<uint32, NullGhostType>,

    linear io_slots: lseq<IOSlot>,
    linear ioctx: aio.IOCtx
  )
  {
    function key(i: int) : Key
    requires 0 <= i < |this.data|
    requires 0 <= i < |this.disk_idx_of_entry|
    {
      Key(this.data[i], this.disk_idx_of_entry[i], i)
    }

    predicate Inv()
    {
      && |this.data| == CACHE_SIZE
      && |this.disk_idx_of_entry| == CACHE_SIZE
      && |this.status| == CACHE_SIZE
      && (forall i | 0 <= i < CACHE_SIZE ::
         && this.status[i].key == this.key(i)
         && this.status[i].inv()
        )
      && |this.read_refcounts| == RC_WIDTH
      && (forall j | 0 <= j < RC_WIDTH ::
          |this.read_refcounts[j]| == CACHE_SIZE)
      && (forall j, i | 0 <= j < RC_WIDTH && 0 <= i < CACHE_SIZE ::
          && this.read_refcounts[j][i].inv(j)
          && this.read_refcounts[j][i].rwlock_loc == this.status[i].rwlock_loc)
      && |this.cache_idx_of_page| == NUM_DISK_PAGES
      && (forall d | 0 <= d < NUM_DISK_PAGES ::
          atomic_index_lookup_inv(this.cache_idx_of_page[d], d))
      && |io_slots| == NUM_IO_SLOTS
      && (forall i | 0 <= i < |io_slots| :: lseq_has(io_slots)[i])
      && (forall i | 0 <= i < |io_slots| :: io_slots[i].WF())
      && (forall iocb_ptr, iocb, wp, g :: ioctx.async_read_inv(iocb_ptr, iocb, wp, g)
        <==> ReadGInv(this, iocb_ptr, iocb, wp, g))
      && (forall iocb_ptr, iocb, wp, g :: ioctx.async_write_inv(iocb_ptr, iocb, wp, g)
        <==> WriteGInv(this, iocb_ptr, iocb, wp, g))

      && (forall v, g :: atomic_inv(global_clockpointer, v, g) <==> true)

      && (forall i | 0 <= i < CACHE_SIZE ::
        this.data[i].aligned(PageSize))

      && this.data_base_ptr.as_nat() + PageSize * (CACHE_SIZE - 1) < 0x1_0000_0000_0000_0000
      && (forall i | 0 <= i < CACHE_SIZE ::
        && this.data[i] == ptr_add(this.data_base_ptr, (PageSize * i) as uint64))

      && |lseqs_raw(this.cache_idx_of_page_array)| == NUM_DISK_PAGES
      && (forall i | 0 <= i < NUM_DISK_PAGES :: lseq_has(this.cache_idx_of_page_array)[i]
          && lseq_peek(this.cache_idx_of_page_array, i as uint64) == this.cache_idx_of_page[i])

      && |lseqs_raw(this.read_refcounts_array)| == RC_WIDTH * CACHE_SIZE
      && (forall i | 0 <= i < RC_WIDTH * CACHE_SIZE :: lseq_has(this.read_refcounts_array)[i])
      && (forall j, i | 0 <= j < RC_WIDTH && 0 <= i < CACHE_SIZE ::
          lseq_peek(this.read_refcounts_array, (j * CACHE_SIZE + i) as uint64)
              == this.read_refcounts[j][i])

      && |lseqs_raw(this.status_idx_array)| == CACHE_SIZE
      && (forall i | 0 <= i < CACHE_SIZE :: lseq_has(this.status_idx_array)[i]
        && lseq_peek(this.status_idx_array, i as uint64)
            == StatusIdx(this.status[i], this.disk_idx_of_entry[i])
      )
      /*
      && this.read_refcounts_base_ptr.as_nat() + (RC_WIDTH-1) * CACHE_SIZE * (CACHE_SIZE-1) < 0x1_0000_0000_0000_0000
      && this.read_refcounts_gshared.len() == RC_WIDTH
      && (forall j | 0 <= j < RC_WIDTH ::
          && this.read_refcounts_gshared.has(j)
          && this.read_refcounts_gshared.get(j).len() == CACHE_SIZE)
      && (forall j, i | 0 <= j < RC_WIDTH && 0 <= i < CACHE_SIZE ::
          && this.read_refcounts[j][i].a.ptr ==
              ptr_add(this.read_refcounts_base_ptr, (j * CACHE_SIZE + i) as uint64)
          && this.read_refcounts_gshared.get(j).has(i)
          && this.read_refcounts[j][i].a.ga ==
              this.read_refcounts_gshared.get(j).get(i))
      */
    }

    shared function method data_ptr(i: uint64) : (p: Ptr)
    requires this.Inv()
    requires 0 <= i as int < CACHE_SIZE
    ensures p == this.data[i]
    {
      ptr_add(this.data_base_ptr, PageSize as uint64 * i)
    }

    shared function method status_atomic(i: uint64) : (shared at: AtomicStatus)
    requires this.Inv()
    requires 0 <= i as int < CACHE_SIZE
    ensures at == this.status[i]
    {
      lseq_peek(this.status_idx_array, i as uint64).status
    }

    shared function method disk_idx_of_entry_ptr(i: uint64) : (shared c: Cell<int64>)
    requires this.Inv()
    requires 0 <= i as int < CACHE_SIZE
    ensures c == this.disk_idx_of_entry[i]
    {
      lseq_peek(this.status_idx_array, i as uint64).idx
    }

    shared function method read_refcount_atomic(j: uint64, i: uint64) : (shared at: AtomicRefcount)
    requires this.Inv()
    requires 0 <= j as int < RC_WIDTH
    requires 0 <= i as int < CACHE_SIZE
    ensures at == this.read_refcounts[j][i]
    {
      lseq_peek(this.read_refcounts_array, j * (CACHE_SIZE as uint64) + i)
    }

    shared function method cache_idx_of_page_atomic(i: uint64) : (shared at: AtomicIndexLookup)
    requires this.Inv()
    requires 0 <= i as int < NUM_DISK_PAGES
    ensures at == this.cache_idx_of_page[i]
    {
      lseq_peek(this.cache_idx_of_page_array, i)
    }
  }

  datatype LocalState = LocalState(
    t: uint64,
    chunk_idx: uint64,
    io_slot_hand: uint64
  )
  {
    predicate WF()
    {
      && 0 <= this.chunk_idx as int < NUM_CHUNKS
      && 0 <= t as int < RC_WIDTH
      && 0 <= io_slot_hand as int < NUM_IO_SLOTS
    }
  }

  ////////////////////////////////////////
  //// IO stuff

  linear datatype IOSlot = IOSlot(
    iocb_ptr: Ptr,
    linear io_slot_info_cell: Cell<IOSlotInfo>,
    linear lock: BasicLock<IOSlotAccess>)
  {
    predicate WF()
    {
      && (forall slot_access: IOSlotAccess :: this.lock.inv(slot_access) <==>
        && slot_access.iocb.ptr == this.iocb_ptr
        && slot_access.io_slot_info.cell == this.io_slot_info_cell
      )
    }
  }

  predicate is_slot_access(io_slot: IOSlot, io_slot_access: IOSlotAccess)
  {
    && io_slot.iocb_ptr == io_slot_access.iocb.ptr
    && io_slot.io_slot_info_cell == io_slot_access.io_slot_info.cell
  }

  predicate ReadGInv(
      cache: Cache,
      iocb_ptr: Ptr,
      iocb: Iocb,
      data: PointsToArray<byte>,
      g: ReadG)
  {
    && iocb.IocbRead?
    && iocb.ptr == iocb_ptr
    && g.slot_idx < NUM_IO_SLOTS
    && |cache.io_slots| == NUM_IO_SLOTS
    && g.io_slot_info.cell == cache.io_slots[g.slot_idx].io_slot_info_cell
    && iocb_ptr == cache.io_slots[g.slot_idx].iocb_ptr
    && g.reading.CacheReadingHandle?
    && 0 <= g.key.cache_idx < CACHE_SIZE
    && |cache.data| == CACHE_SIZE
    && data.ptr == cache.data[g.key.cache_idx]
    && g.io_slot_info.v == IOSlotRead(g.key.cache_idx as uint64)
    && iocb.nbytes == PageSize
    && g.reading.is_handle(g.key)
    && g.reading.CacheReadingHandle?
    && g.reading.cache_reading.disk_idx == iocb.offset
  }

  predicate WriteGInv(
      cache: Cache,
      iocb_ptr: Ptr,
      iocb: Iocb,
      data: seq<byte>,
      g: WriteG)
  {
    && iocb.IocbWrite?
    && iocb.ptr == iocb_ptr
    && is_read_perm(iocb_ptr, iocb, data, g)
    && g.slot_idx < NUM_IO_SLOTS
    && |cache.io_slots| == NUM_IO_SLOTS
    && g.io_slot_info.cell == cache.io_slots[g.slot_idx].io_slot_info_cell
    && iocb_ptr == cache.io_slots[g.slot_idx].iocb_ptr
    && g.wbo.b.CacheEntryHandle?
    && 0 <= g.wbo.b.key.cache_idx < CACHE_SIZE
    && g.io_slot_info.v == IOSlotWrite(g.wbo.b.key.cache_idx as uint64)
    && g.wbo.is_handle(g.key)
    && |cache.data| == CACHE_SIZE
    && |cache.disk_idx_of_entry| == CACHE_SIZE
    && |cache.status| == CACHE_SIZE
    && g.key == cache.key(g.key.cache_idx)
    && g.wbo.token.loc == cache.status[g.wbo.b.key.cache_idx as nat].rwlock_loc
    && g.wbo.b.cache_entry.disk_idx == iocb.offset
  }
}
