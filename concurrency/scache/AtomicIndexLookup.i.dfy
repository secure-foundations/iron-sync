include "../framework/Atomic.s.dfy"
include "../../lib/Lang/NativeTypes.s.dfy"
include "../framework/GlinearOption.i.dfy"
include "cache/CacheResources.i.dfy"
include "Constants.i.dfy"
include "../framework/Ptrs.s.dfy"

module AtomicIndexLookupImpl {
  import opened NativeTypes
  import opened Ptrs
  import opened Atomics
  import opened Constants
  import opened CacheResources
  import opened Options
  import opened GlinearOption
  import opened CacheStatusType

  type AtomicIndexLookup = Atomic<uint64, CacheResources.DiskPageMap>

  const NOT_MAPPED : uint64 := 0xffff_ffff_ffff_ffff;

  predicate state_inv(v: uint64, g: CacheResources.DiskPageMap, disk_idx: nat)
  {
    && (0 <= v as int < CACHE_SIZE as int || v == NOT_MAPPED)
    && g == CacheResources.DiskPageMap(disk_idx,
        (if v == NOT_MAPPED then None else Some(v as nat)))
  }

  predicate atomic_index_lookup_inv(a: AtomicIndexLookup, disk_idx: nat)
  {
    forall v, g :: atomic_inv(a, v, g) <==> state_inv(v, g, disk_idx)
  }

  method atomic_index_lookup_read(
      shared a: AtomicIndexLookup,
      ghost disk_idx: nat)
  returns (cache_idx: uint64)
  requires atomic_index_lookup_inv(a, disk_idx)
  ensures 0 <= cache_idx as int < CACHE_SIZE as int || cache_idx == NOT_MAPPED
  {
    atomic_block cache_idx := execute_atomic_load(a) { }
  }

  method atomic_index_lookup_clear_mapping(
      shared a: AtomicIndexLookup,
      ghost disk_idx: nat,
      glinear cache_entry: CacheResources.CacheEntry,
      glinear status: CacheResources.CacheStatus
  )
  returns (
      glinear cache_empty': CacheResources.CacheEmpty
  )
  requires atomic_index_lookup_inv(a, disk_idx)
  requires status.CacheStatus?
  requires status.status == Clean
  requires cache_entry.CacheEntry?
  requires cache_entry.cache_idx == status.cache_idx
  requires cache_entry.disk_idx == disk_idx
  ensures cache_empty' == CacheEmpty(cache_entry.cache_idx)
  {
    atomic_block var _ := execute_atomic_store(a, NOT_MAPPED) {
      ghost_acquire g;

      cache_empty', g := CacheResources.unassign_page(
          status.cache_idx, disk_idx,
          status, cache_entry, g);

      ghost_release g;
    }
  }

  method atomic_index_lookup_add_mapping(
      shared a: AtomicIndexLookup,
      disk_idx: uint64,
      cache_idx: uint64,
      glinear cache_empty: CacheResources.CacheEmpty)
  returns (
    success: bool,
    glinear cache_empty': glOption<CacheResources.CacheEmpty>,
    glinear cache_reading': glOption<CacheResources.CacheReading>,
    glinear read_ticket: glOption<CacheResources.DiskReadTicket>
  )
  requires atomic_index_lookup_inv(a, disk_idx as int)
  requires cache_empty.cache_idx == cache_idx as int
  requires 0 <= cache_idx as int < CACHE_SIZE as int
  ensures !success ==> cache_empty' == glSome(cache_empty)
  ensures !success ==> cache_reading' == glNone
  ensures !success ==> read_ticket == glNone

  ensures success ==> cache_empty' == glNone
  ensures success ==> cache_reading' ==
    glSome(CacheReading(cache_idx as nat, disk_idx as nat))
  ensures success ==>
      && read_ticket == glSome(DiskReadTicket(disk_idx as int))
  {
    atomic_block var did_set :=
      execute_atomic_compare_and_set_strong(a, NOT_MAPPED, cache_idx)
    {
      ghost_acquire old_g;
      glinear var new_g;

      if did_set {
        glinear var ticket, cr;
        cr, new_g, ticket := CacheResources.initiate_page_in(
            cache_idx as int, disk_idx as int, cache_empty, old_g);
        read_ticket := glSome(ticket);
        cache_reading' := glSome(cr);
        cache_empty' := glNone;
      } else {
        cache_empty' := glSome(cache_empty);
        cache_reading' := glNone;
        read_ticket := glNone;
        new_g := old_g;
      }
      assert state_inv(new_value, new_g, disk_idx as int);

      ghost_release new_g;
    }

    success := did_set;
  }
}
