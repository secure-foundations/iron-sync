include "CacheIO.i.dfy"
include "../framework/ThreadUtils.s.dfy"

module CacheWritebackBatch(aio: AIO(CacheAIOParams, CacheIfc, CacheSSM)) {
  import opened Constants
  import opened AtomicStatusImpl
  import opened CacheAIOParams
  import opened AtomicRefcountImpl
  import opened AtomicIndexLookupImpl
  import opened Atomics
  import opened GlinearOption
  import opened Ptrs
  import opened NativeTypes
  import opened Options
  import opened CIO = CacheIO(aio)
  import CacheResources
  import RwLock
  import opened T = RwLockToken
  import opened CT = CacheTypes(aio)
  import opened CacheHandle
  import opened CacheStatusType
  import opened BitOps
  import opened Cells
  import opened LinearSequence_i
  import opened ThreadUtils
  import opened PageSizeConstant
  import opened GlinearMap
  import Math
  import NonlinearLemmas
  import DT = DiskToken(CacheIfc, CacheSSM)
  import IocbStruct

  predicate ktw(cache: Cache, disk_idx: nat, key: Key, ticket: DT.Token,
      wbo: WritebackObtainedToken)
  {
    && 0 <= key.cache_idx < cache.config.cache_size as nat
    && |cache.data| == cache.config.cache_size as nat
    && |cache.status| == cache.config.cache_size as nat
    && |cache.page_handles| == cache.config.cache_size as nat
    && key == cache.key(key.cache_idx)
    && wbo.is_handle(key, cache.config)
    && wbo.b.CacheEntryHandle?
    && wbo.b.idx.v.disk_addr as nat == disk_idx * PageSize
    && ticket.val == CacheSSM.DiskWriteReq(disk_idx, wbo.b.data.s)
    && wbo.token.loc == cache.status[wbo.b.key.cache_idx as nat].rwlock_loc
  }

  predicate {:opaque} fwd_lists(cache: Cache, start: nat, end: nat,
      keys: seq<Key>,
      tickets: map<nat, DT.Token>,
      wbos: map<nat, WritebackObtainedToken>)
  {
    && |keys| == end - start
    && forall i | 0 <= i < |keys| ::
        && i in tickets
        && i in wbos
        && ktw(cache, start + i, keys[i], tickets[i], wbos[i])
  }

  glinear method make_empty(ghost cache: Cache, ghost disk_addr: nat)
  returns (
      ghost keys: seq<Key>,
      glinear tickets: map<nat, DT.Token>,
      glinear wbos: map<nat, WritebackObtainedToken>
     )
  ensures fwd_lists(cache, disk_addr, disk_addr, keys, tickets, wbos)
  {
    keys := [];
    tickets := glmap_empty();
    wbos := glmap_empty();
    reveal_fwd_lists();
  }

  glinear method {:fuel ktw,0} list_concat(
      ghost cache: Cache,
      ghost a: nat, ghost b: nat, ghost c: nat,
      ghost keys1: seq<Key>,
      glinear tickets1: map<nat, DT.Token>,
      glinear wbos1: map<nat, WritebackObtainedToken>,
      ghost keys2: seq<Key>,
      glinear tickets2: map<nat, DT.Token>,
      glinear wbos2: map<nat, WritebackObtainedToken>)
  returns (
      ghost keys: seq<Key>,
      glinear tickets: map<nat, DT.Token>,
      glinear wbos: map<nat, WritebackObtainedToken>)
  requires fwd_lists(cache, a, b, keys1, tickets1, wbos1)
  requires fwd_lists(cache, b, c, keys2, tickets2, wbos2)
  ensures fwd_lists(cache, a, c, keys, tickets, wbos)
  {
    keys := keys1 + keys2;
    tickets := tickets1;
    wbos := wbos1;

    reveal_fwd_lists();

    glinear var tickets' := tickets2;
    glinear var wbos' := wbos2;

    ghost var j := 0;
    while j < |keys2|
    invariant 0 <= j <= |keys2|
    invariant forall i | 0 <= i < |keys1| + j ::
        && i in tickets
        && i in wbos
        && ktw(cache, a + i, keys[i], tickets[i], wbos[i])
    invariant forall i | j <= i < |keys2| ::
        && i in tickets'
        && i in wbos'
        && ktw(cache, b + i, keys2[i], tickets'[i], wbos'[i])
    {
      glinear var ticket, wbo;
      tickets', ticket := glmap_take(tickets', j);
      wbos', wbo := glmap_take(wbos', j);

      tickets := glmap_insert(tickets, |keys1| + j, ticket);
      wbos := glmap_insert(wbos, |keys1| + j, wbo);

      j := j + 1;
    }
    dispose_anything(tickets');
    dispose_anything(wbos');
  }

  glinear method list_push_back(
      ghost cache: Cache,
      ghost start: nat,
      ghost end: nat,
      ghost keys: seq<Key>,
      glinear tickets: map<nat, DT.Token>,
      glinear wbos: map<nat, WritebackObtainedToken>,
      ghost key: Key,
      glinear ticket: DT.Token,
      glinear wbo: WritebackObtainedToken)
  returns (
      ghost keys': seq<Key>,
      glinear tickets': map<nat, DT.Token>,
      glinear wbos': map<nat, WritebackObtainedToken>
     )
  requires fwd_lists(cache, start, end, keys, tickets, wbos)
  requires ktw(cache, end, key, ticket, wbo)
  ensures fwd_lists(cache, start, end + 1, keys', tickets', wbos')
  {
    reveal_fwd_lists();
    keys' := keys + [key];
    tickets' := glmap_insert(tickets, |keys|, ticket);
    wbos' := glmap_insert(wbos, |keys|, wbo);
  }

  glinear method list_push_front(
      ghost cache: Cache,
      ghost start: nat,
      ghost end: nat,
      ghost keys: seq<Key>,
      glinear tickets: map<nat, DT.Token>,
      glinear wbos: map<nat, WritebackObtainedToken>,
      ghost key: Key,
      glinear ticket: DT.Token,
      glinear wbo: WritebackObtainedToken)
  returns (
      ghost keys': seq<Key>,
      glinear tickets': map<nat, DT.Token>,
      glinear wbos': map<nat, WritebackObtainedToken>
     )
  requires start > 0
  requires fwd_lists(cache, start, end, keys, tickets, wbos)
  requires ktw(cache, start - 1, key, ticket, wbo)
  ensures fwd_lists(cache, start - 1, end, keys', tickets', wbos')
  {
    ghost var keys1 := [key];
    glinear var tickets1 := glmap_empty();
    glinear var wbos1 := glmap_empty();
    tickets1 := glmap_insert(tickets1, 0, ticket);
    wbos1 := glmap_insert(wbos1, 0, wbo);
    reveal_fwd_lists();
    keys', tickets', wbos' := list_concat(cache, start - 1, start, end,
        keys1, tickets1, wbos1, keys, tickets, wbos);
  }

  predicate method pages_share_extent(shared cache: Cache, a: uint64, b: uint64)
  requires cache.config.WF()
  {
    Math.div_bound(a as int, cache.config.pages_per_extent as int);
    Math.div_bound(b as int, cache.config.pages_per_extent as int);
    a / cache.config.pages_per_extent == b / cache.config.pages_per_extent
  }

  method walk_forward(shared cache: Cache, inout linear local: LocalState,
        disk_addr: uint64, is_urgent: bool)
  returns (end_addr: uint64,
      ghost keys: seq<Key>,
      glinear tickets: map<nat, DT.Token>,
      glinear wbos: map<nat, WritebackObtainedToken>
     )
  decreases *
  requires cache.Inv()
  requires old_local.WF(cache.config)
  requires 0 <= disk_addr as int < cache.config.num_disk_pages as int
  ensures 0 <= disk_addr as int < end_addr as int <= cache.config.num_disk_pages as int
  ensures fwd_lists(cache, disk_addr as nat + 1, end_addr as nat, keys, tickets, wbos)
  ensures local.WF(cache.config)
  ensures pages_share_extent(cache, disk_addr, end_addr - 1)
  ensures local.t == old_local.t
  {
    ghost var t := local.t;

    end_addr := disk_addr + 1;
    var done := false;

    keys, tickets, wbos := make_empty(cache, disk_addr as nat + 1);

    while end_addr < cache.config.num_disk_pages && !done
    invariant disk_addr as int < end_addr as int <= cache.config.num_disk_pages as int
    invariant fwd_lists(cache, disk_addr as nat + 1, end_addr as nat, keys, tickets, wbos)
    invariant local.WF(cache.config)
    invariant pages_share_extent(cache, disk_addr, end_addr - 1)
    invariant local.t == t
    decreases cache.config.num_disk_pages as int - end_addr as int,
        if !done then 1 else 0
    {
      var next := end_addr;
      if !pages_share_extent(cache, next, disk_addr) {
        done := true;
      } else {
        var cache_idx := atomic_index_lookup_read(
            cache.cache_idx_of_page_atomic(next), next as nat, cache.config);
        if cache_idx == NOT_MAPPED {
          done := true;
        } else {
          glinear var write_back_r, ticket;
          var do_write_back;
          do_write_back, write_back_r, ticket :=
              cache.status_atomic(cache_idx as uint32).try_acquire_writeback(is_urgent);

          if !do_write_back {
            dispose_anything(write_back_r);
            dispose_anything(ticket);
            done := true;
          } else {
            var ph := read_cell(
                cache.page_handle_ptr(cache_idx),
                T.borrow_wb(write_back_r.value.token).idx);
            var disk_idx := ph.disk_addr / PageSize64() as int64;

            if disk_idx == next as int64 {
              keys, tickets, wbos := list_push_back(
                  cache, disk_addr as nat + 1, end_addr as nat,
                  keys, tickets, wbos,
                  cache.key(cache_idx as nat),
                  CacheResources.DiskWriteTicket_unfold(unwrap_value(ticket)),
                  unwrap_value(write_back_r));

              end_addr := next + 1;
            } else {
              // Presumably rare case.
              // Oops, this isn't the disk address we thought it was going to be!
              // Write this one on its own and stop trying to extend the page range.
              disk_writeback_async(
                  cache, inout local,
                  disk_idx as uint64,
                  cache_idx,
                  unwrap_value(write_back_r),
                  unwrap_value(ticket));
              
              done := true;
            }
          }
        }
      }
    }
  }

  method walk_backward(shared cache: Cache, inout linear local: LocalState,
        disk_addr: uint64, is_urgent: bool)
  returns (start_addr: uint64,
      ghost keys: seq<Key>,
      glinear tickets: map<nat, DT.Token>,
      glinear wbos: map<nat, WritebackObtainedToken>
     )
  decreases *
  requires cache.Inv()
  requires old_local.WF(cache.config)
  requires 0 <= disk_addr as int < cache.config.num_disk_pages as int
  ensures 0 <= start_addr <= disk_addr
  ensures fwd_lists(cache, start_addr as nat, disk_addr as nat, keys, tickets, wbos)
  ensures local.WF(cache.config)
  ensures pages_share_extent(cache, disk_addr, start_addr)
  ensures local.t == old_local.t
  {
    ghost var t: uint64 := local.t;

    start_addr := disk_addr;
    var done := false;

    keys, tickets, wbos := make_empty(cache, disk_addr as nat);

    while start_addr > 0 && !done
    invariant 0 <= start_addr <= disk_addr
    invariant fwd_lists(cache, start_addr as nat, disk_addr as nat, keys, tickets, wbos)
    invariant local.WF(cache.config)
    invariant pages_share_extent(cache, disk_addr, start_addr)
    invariant t == local.t
    decreases start_addr, if !done then 1 else 0
    {
      var next := start_addr - 1;
      if !pages_share_extent(cache, next, disk_addr) {
        done := true;
      } else {
        var cache_idx := atomic_index_lookup_read(
            cache.cache_idx_of_page_atomic(next), next as nat, cache.config);
        if cache_idx == NOT_MAPPED {
          done := true;
        } else {
          glinear var write_back_r, ticket;
          var do_write_back;
          do_write_back, write_back_r, ticket :=
              cache.status_atomic(cache_idx).try_acquire_writeback(is_urgent);

          if !do_write_back {
            dispose_anything(write_back_r);
            dispose_anything(ticket);
            done := true;
          } else {
            var ph := read_cell(
                cache.page_handle_ptr(cache_idx),
                T.borrow_wb(write_back_r.value.token).idx);
            var disk_idx := ph.disk_addr / PageSize64() as int64;

            if disk_idx == next as int64 {
              keys, tickets, wbos := list_push_front(
                  cache, start_addr as nat, disk_addr as nat,
                  keys, tickets, wbos,
                  cache.key(cache_idx as nat),
                  CacheResources.DiskWriteTicket_unfold(unwrap_value(ticket)),
                  unwrap_value(write_back_r));

              start_addr := next;
            } else {
              // Presumably rare case.
              // Oops, this isn't the disk address we thought it was going to be!
              // Write this one on its own and stop trying to extend the page range.
              disk_writeback_async(
                  cache, inout local,
                  disk_idx as uint64,
                  cache_idx,
                  unwrap_value(write_back_r),
                  unwrap_value(ticket));
              
              done := true;
            }
          }
        }
      }
    }
  }

  lemma inv_holds(cache: Cache,
      iocb_ptr: Ptr, iocb: IocbStruct.Iocb, iovec: PointsToArray<IocbStruct.Iovec>,
      datas: seq<seq<byte>>, g: WritevG)
  requires cache.Inv()
  requires WritevGInv(cache.io_slots, cache.data, cache.page_handles, cache.status,
      cache.config, iocb_ptr, iocb, iovec, datas, g)
  ensures cache.ioctx.async_writev_inv(iocb_ptr, iocb, iovec, datas, g)
  {
    // for some reason Dafny is able to prove this better when it is factored
    // into its own lemma
  }

  method vec_writeback_async(shared cache: Cache, inout linear local: LocalState,
        start_addr: uint64, end_addr: uint64,
        ghost keys: seq<Key>,
        glinear tickets: map<nat, DT.Token>,
        glinear wbos: map<nat, WritebackObtainedToken>)
  requires cache.Inv()
  requires old_local.WF(cache.config)
  requires start_addr as int < end_addr as int <= cache.config.num_disk_pages as int
  requires end_addr as int - start_addr as int <= cache.config.pages_per_extent as int
  requires fwd_lists(cache, start_addr as nat, end_addr as nat,
      keys, tickets, wbos)
  ensures local.WF(cache.config)
  ensures local.t == old_local.t
  decreases *
  {
    reveal_fwd_lists();

    var idx;
    glinear var access;
    idx, access := get_free_io_slot(cache, inout local);
    glinear var IOSlotAccess(iocb, iovec) := access;

    var iovec_ptr := lseq_peek(cache.io_slots, idx).iovec_ptr;

    IocbStruct.iocb_prepare_writev(
        lseq_peek(cache.io_slots, idx).iocb_ptr,
        inout iocb,
        start_addr as int64,
        iovec_ptr,
        end_addr - start_addr);

    ghost var datas := seq(end_addr as int - start_addr as int, (j) => []);
    var j: uint64 := 0;
    while j < end_addr - start_addr
    invariant local.WF(cache.config)
    invariant 0 <= j as int <= end_addr as int - start_addr as int
    invariant |datas| == end_addr as int - start_addr as int
    invariant |iovec.s| == cache.config.pages_per_extent as int
    invariant iovec.ptr == iovec_ptr
    invariant forall i: nat | 0 <= i < j as nat ::
        (i as int) in wbos && datas[i] == wbos[i as int].b.data.s
        && wbos[i].b.data.ptr == iovec.s[i].iov_base()
        && iovec.s[i].iov_len() as int == PageSize
    invariant forall i: nat | 0 <= i < j as nat :: (i as int) in wbos && 
        simpleWriteGInv(cache.io_slots, cache.data, cache.page_handles, cache.status,
            cache.config, iocb.offset + i, datas[i], keys[i], wbos[i])
    {
      var cache_idx := read_known_cache_idx(
          cache.cache_idx_of_page_atomic(start_addr + j),
          start_addr as int + j as int,
          cache.config,
          borrow_wb(gmap_borrow(wbos, j as int).token).cache_entry);
      var iov := IocbStruct.new_iovec(cache.data_ptr(cache_idx), 4096);
      iovec_ptr.index_write(inout iovec, j, iov);

      datas := datas[j := wbos[j as int].b.data.s];

      assert simpleWriteGInv(
          cache.io_slots, cache.data, cache.page_handles, cache.status, cache.config,
            iocb.offset + j as int, datas[j], keys[j as int], wbos[j as int]);

      j := j + 1;
    }

    glinear var writevg := WritevG(keys, wbos, idx as int, cache.config);
    forall i: int | 0 <= i < (end_addr - start_addr) as int
    ensures
      && i in wbos
      && wbos[i].is_handle(keys[i], cache.config)
      && wbos[i].b.CacheEntryHandle?
      && wbos[i].b.data.s == datas[i]
      && wbos[i].b.data.ptr == iovec.s[i].iov_base()
    {
    }

    var iocb_ptr := lseq_peek(cache.io_slots, idx).iocb_ptr;

    assert WritevGInv(
        cache.io_slots, cache.data, cache.page_handles, cache.status, cache.config,
        iocb_ptr,
        iocb, iovec, datas, writevg);

    forall i | 0 <= i < iocb.iovec_len
      ensures i in tickets
      ensures aio.writev_valid_i(iovec.s[i], datas[i], tickets[i], iocb.offset, i)
    {
    }

    inv_holds(cache,
        iocb_ptr, iocb, iovec, datas, writevg);

    aio.async_writev(
        cache.ioctx,
        iocb_ptr,
        iocb,
        iovec,
        datas,
        writevg,
        tickets);
  }

  method batch_start_writeback(shared cache: Cache, inout linear local: LocalState,
        batch_idx: uint32, is_urgent: bool)
  requires cache.Inv()
  requires old_local.WF(cache.config)
  requires 0 <= batch_idx as int < cache.config.batch_capacity as int
  ensures local.WF(cache.config)
  ensures local.t == old_local.t
  decreases *
  {
    var i: uint32 := 0;
    while i < ENTRIES_PER_BATCH_32()
    invariant local.WF(cache.config)
    invariant local.t == old_local.t
    {
      /*
      calc {
        batch_idx * ENTRIES_PER_BATCH_32() + i; <=
        (cache.config.batch_capacity - 1) * (cache.config.batch_capacity as uint32) + i; <
        { NonelinearLemmas.distributive_right_sub(cache.config.batch_capacity, 1, 
        cache.config.cache_size;
      }
      */

      var cache_idx := batch_idx * ENTRIES_PER_BATCH_32() + i;

      glinear var write_back_r, ticket;
      var do_write_back;
      do_write_back, write_back_r, ticket :=
          cache.status_atomic(cache_idx).try_acquire_writeback(is_urgent);

      if do_write_back {
        var ph := read_cell(
            cache.page_handle_ptr(cache_idx),
            T.borrow_wb(write_back_r.value.token).idx);
        var disk_idx := ph.disk_addr / PageSize64() as int64;
        assert disk_idx != -1;

        var start_addr, end_addr;
        ghost var keys1, keys2;
        glinear var tickets1, tickets2;
        glinear var wbos1, wbos2;
        start_addr, keys1, tickets1, wbos1 :=
            walk_backward(cache, inout local, disk_idx as uint64, is_urgent);
        end_addr, keys2, tickets2, wbos2 :=
            walk_forward(cache, inout local, disk_idx as uint64, is_urgent);

        keys1, tickets1, wbos1 := list_push_back(
            cache, start_addr as nat, disk_idx as nat,
            keys1, tickets1, wbos1,
            cache.key(cache_idx as int),
            CacheResources.DiskWriteTicket_unfold(unwrap_value(ticket)),
            unwrap_value(write_back_r));

        keys1, tickets1, wbos1 := list_concat(
            cache,
            start_addr as nat, disk_idx as nat + 1, end_addr as nat,
            keys1, tickets1, wbos1,
            keys2, tickets2, wbos2);

        assert end_addr as int - start_addr as int <= cache.config.pages_per_extent as int
        by {
          Math.mod_le_for_same_div(start_addr as int, end_addr as int,
              cache.config.pages_per_extent as int);
        }
        vec_writeback_async(cache, inout local, start_addr, end_addr,
            keys1, tickets1, wbos1);
      } else {
        dispose_glnone(write_back_r);
        dispose_glnone(ticket);
      }

      i := i + 1;
    }
  }
}
