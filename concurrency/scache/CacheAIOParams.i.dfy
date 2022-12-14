include "../framework/AIO.s.dfy"
include "rwlock/RwLock.i.dfy"
include "../framework/GlinearMap.s.dfy"

module CacheAIOParams refines AIOParams {
  import T = RwLockToken
  import opened CacheHandle
  import opened Cells
  import opened GlinearMap
  import opened Constants

  glinear datatype IOSlotAccess = IOSlotAccess(
    glinear iocb: Iocb,
    glinear iovec: PointsToArray<Iovec>)

  glinear datatype ReadG = ReadG(
    ghost key: Key,
    glinear cache_reading: CacheResources.CacheReading,
    glinear idx: CellContents<PageHandle>,
    glinear ro: T.Token,
    ghost slot_idx: nat,
    glinear iovec: PointsToArray<Iovec>
  )

  glinear datatype ReadvG = ReadvG(
    ghost keys: seq<Key>,
    glinear cache_reading: map<nat, CacheResources.CacheReading>,
    glinear idx: map<nat, CellContents<PageHandle>>,
    glinear ro: map<nat, T.Token>,
    ghost slot_idx: nat
  )

  glinear datatype WriteG = WriteG(
    ghost key: Key,
    glinear wbo: T.WritebackObtainedToken,
    ghost slot_idx: nat,
    glinear iovec: PointsToArray<Iovec>,
    ghost config: Config
  )

  glinear datatype WritevG = WritevG(
    ghost keys: seq<Key>,
    glinear wbos: map<nat, T.WritebackObtainedToken>,
    ghost slot_idx: nat,
    ghost config: Config
  )

  predicate is_read_perm(
      iocb_ptr: Ptr,
      iocb: Iocb,
      data: seq<byte>,
      g: WriteG)
  {
    && g.wbo.is_handle(g.key, g.config)
    && g.wbo.b.CacheEntryHandle?
    && g.wbo.b.data.s == data
    && iocb.IocbWrite?
    && g.wbo.b.data.ptr == iocb.buf
  }

  glinear method get_read_perm(
      ghost iocb_ptr: Ptr,
      gshared iocb: Iocb,
      ghost data: seq<byte>,
      gshared g: WriteG)
  returns (gshared ad: PointsToArray<byte>)
  //requires iocb.IocbWrite?
  //requires async_write_inv(iocb_ptr, iocb, data, g)
  ensures ad == PointsToArray(iocb.buf, data)
  {
    ad := T.borrow_wb(g.wbo.token).data;
  }

  /*predicate async_read_inv(
      iocb_ptr: Ptr,
      iocb: Iocb,
      wp: PointsToArray<byte>,
      g: ReadG)
  {
    && g.reading.CacheReadingHandle?
    && g.reading.is_handle(g.key)
  }*/

  predicate is_read_perm_v(
      iocb_ptr: Ptr,
      iocb: Iocb,
      iovec: PointsToArray<Iovec>,
      datas: seq<seq<byte>>,
      g: WritevG)
  {
    && |datas| == |g.keys| <= |iovec.s|
    && forall i | 0 <= i < |datas| ::
      && i in g.wbos
      && g.wbos[i].is_handle(g.keys[i], g.config)
      && g.wbos[i].b.CacheEntryHandle?
      && g.wbos[i].b.data.s == datas[i]
      && g.wbos[i].b.data.ptr == iovec.s[i].iov_base()
  }

  glinear method get_read_perm_v(
      ghost iocb_ptr: Ptr,
      gshared iocb: Iocb,
      gshared iovec: PointsToArray<Iovec>,
      ghost datas: seq<seq<byte>>,
      gshared g: WritevG,
      ghost i: nat)
  returns (gshared ad: PointsToArray<byte>)
  //requires iocb.IocbWritev?
  //requires is_read_perm_v(iocb_ptr, iocb, iovec, datas, g)
  //requires 0 <= i < |datas| == |iovec.s|
  ensures ad == PointsToArray(iovec.s[i].iov_base(), datas[i])
  {
    ad := T.borrow_wb(gmap_borrow(g.wbos, i).token).data;
  }
}
