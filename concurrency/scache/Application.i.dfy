include "CacheOps.i.dfy"
include "CacheInit.i.dfy"

// Really simple application exercising the cache.

module Application(aio: AIO(CacheAIOParams, CacheIfc, CacheSSM)) {
  import opened CT = CacheTypes(aio)
  import opened NativeTypes
  import opened RequestIds
  import opened CacheOps = CacheOps(aio)
  import CacheSSM
  import CacheIfc
  import DiskIfc
  import opened Constants
  import T = DiskToken(CacheIfc, CacheSSM)
  import opened ClientCounter
  import RwLockToken
  import opened Ptrs
  import CacheResources
  import opened CacheHandle
  import opened LinearSequence_i
  import opened LinearSequence_s
  import CI = CacheInit(aio)
  import opened Cells

  method copy_seq_out(ptr: Ptr, gshared d: PointsToArray<byte>)
  returns (s: seq<byte>)
  requires |d.s| == 4096
  requires d.ptr == ptr
  ensures s == d.s
  {
    linear var sl := seq_alloc(4096, 0);
    var i: uint64 := 0;
    while i < 4096
    invariant 0 <= i <= 4096
    invariant |sl| == 4096
    invariant forall j | 0 <= j < i :: sl[j] == d.s[j]
    {
      var val := ptr.index_read(d, i);
      sl := seq_set(sl, i, val);
      i := i + 1;
    }
    assert sl == d.s;
    s := seq_unleash(sl);
  }

  method copy_seq_in(ptr: Ptr, inout glinear d: PointsToArray<byte>, data: seq<byte>)
  requires old_d.ptr == ptr
  requires |old_d.s| == 4096
  requires |data| == 4096
  ensures d == old_d.(s := data)
  {
    var i: uint64 := 0;
    while i < 4096
    invariant 0 <= i <= 4096
    invariant |d.s| == 4096
    invariant d.ptr == old_d.ptr
    invariant forall j | 0 <= j < i :: data[j] == d.s[j]
    {
      ptr.index_write(inout d, i, data[i]);
      i := i + 1;
    }
  }

  method init(glinear init_tok: T.Token, preConfig: PreConfig)
  returns (linear cache: Cache, glinear counter: Clients)
  requires preConfig.WF()
  requires CacheSSM.Init(init_tok.val)
  ensures cache.Inv()
  ensures counter.loc == cache.counter_loc && counter.n == 255
  {
    cache, counter := CI.init_cache(init_tok, preConfig);
  }

  method init_thread_local_state(ghost cache: Cache, t: uint64)
  returns (linear l: LocalState)
  requires cache.Inv()
  ensures l.WF(cache.config)
  {
    l := CI.init_thread_local_state(cache, t);
  }

  method read_block(
      shared cache: Cache,
      inout linear localState: LocalState,
      disk_idx: uint64,
      ghost rid: RequestId,
      glinear ticket: T.Token,
      glinear client: Client)
  returns (block: DiskIfc.Block, glinear stub: T.Token, glinear client': Client)
  requires cache.Inv()
  requires old_localState.WF(cache.config)
  requires 0 <= disk_idx as int < cache.config.num_disk_pages as int
  requires ticket.val == CacheSSM.Ticket(rid, CacheIfc.ReadInput(disk_idx as int))
  requires client.loc == cache.counter_loc
  ensures client'.loc == cache.counter_loc
  ensures localState.WF(cache.config)
  ensures stub.val == CacheSSM.Stub(rid, CacheIfc.ReadOutput(block))
  decreases *
  {
    var php;
    glinear var handle;
    php, handle := CacheOps.get(cache, inout localState, disk_idx, client);

    var ph := read_cell(lseq_peek(cache.status_idx_array, php.cache_idx as uint64).page_handle,
        RwLockToken.borrow_sot(handle.so).idx);
    var ptr := ph.data_ptr;

    block := copy_seq_out(ptr, RwLockToken.borrow_sot(handle.so).data);
    stub := CacheResources.app_read_block(
        rid, RwLockToken.borrow_sot(handle.so).cache_entry, ticket);

    client' := CacheOps.unget(cache, localState, php, disk_idx, handle);
  }

  method write_block(
      shared cache: Cache,
      inout linear localState: LocalState,
      disk_idx: uint64,
      data: DiskIfc.Block,
      ghost rid: RequestId,
      glinear ticket: T.Token,
      glinear client: Client)
  returns (glinear stub: T.Token, glinear client': Client)
  requires cache.Inv()
  requires old_localState.WF(cache.config)
  requires 0 <= disk_idx as int < cache.config.num_disk_pages as int
  requires ticket.val == CacheSSM.Ticket(rid, CacheIfc.WriteInput(disk_idx as int, data))
  requires client.loc == cache.counter_loc
  ensures client'.loc == cache.counter_loc
  ensures localState.WF(cache.config)
  ensures stub.val == CacheSSM.Stub(rid, CacheIfc.WriteOutput)
  decreases *
  {
    var php;
    glinear var write_handle;
    php, write_handle := CacheOps.get_claim_lock(cache, inout localState, disk_idx, client);

    write_handle := CacheOps.mark_dirty(cache, localState, php, disk_idx, write_handle);

    glinear var WriteablePageHandle(cache_idx, handle, status, eo) := write_handle;
    glinear var CacheEntryHandle(key, cache_entry, idx, pointsto) := handle;

    var ph := read_cell(lseq_peek(cache.status_idx_array, php.cache_idx as uint64).page_handle, idx);
    var ptr := ph.data_ptr;

    copy_seq_in(ptr, inout pointsto, data);
    cache_entry, stub := CacheResources.app_write_block(
        rid, data, cache_entry, ticket, status);

    handle := CacheEntryHandle(key, cache_entry, idx, pointsto);
    write_handle := WriteablePageHandle(cache_idx, handle, status, eo);

    glinear var claim_handle := CacheOps.unlock(cache, localState, php, disk_idx, write_handle);
    glinear var read_handle := CacheOps.unclaim(cache, localState, php, disk_idx, claim_handle);
    client' := CacheOps.unget(cache, localState, php, disk_idx, read_handle);
  }
}

// TODO move this to a .s file or something
module {:extern "InstantiatedDiskInterface"}
    TheAIO refines AIO(CacheAIOParams, CacheIfc, CacheSSM) { }

import App = Application(TheAIO)
