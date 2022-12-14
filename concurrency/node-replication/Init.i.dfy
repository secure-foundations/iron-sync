include "Impl.i.dfy"
include "FlatCombiner.i.dfy"

module Init(nrifc: NRIfc) {
  import opened RequestIds
  import opened Atomics
  import opened ILT = InfiniteLogTokens(nrifc)
  import opened IL = InfiniteLogSSM(nrifc)
  import opened CBT = CyclicBufferTokens(nrifc)
  import FC = FlatCombiner
  import opened FlatCombinerTokens
  import opened LinearSequence_i
  import opened LinearSequence_s
  import opened LinearMaybe
  import opened NativeTypes
  import opened NodeReplicaApplied = NodeReplica(nrifc)
  import opened Rwi = RwLockImpl(NodeReplica(nrifc))
  import opened Runtime
  import opened ThreadUtils
  import opened Ptrs
  import opened GlinearMap
  import opened GlinearOption
  import opened Cells
  import LC = LinearCells
  import opened GhostLoc
  import opened Im = NRImpl(nrifc)
  import opened NRConstants
  import Tokens = TicketStubToken(nrifc, IL)
  import opened TicketStubSingletonLoc

  linear datatype NodeCreationToken = NodeCreationToken(
    nodeId: uint64,
    glinear combiner: CombinerToken,
    glinear cb: CBCombinerToken,
    glinear ghost_replica: Replica,
    ghost cb_loc_s: nat)
  {
    predicate WF(nr: NR)
    {
      && nr.cb_loc_s == cb_loc_s
      && 0 <= nodeId as int < NUM_REPLICAS as int
      && ghost_replica == Replica(nodeId as int, nrifc.init_state())
      && combiner == CombinerToken(nodeId as int, CombinerReady)
      && cb == CBCombinerToken(nodeId as int, CB.CombinerIdle, cb_loc_s)
    }
  }

  method initNode(ghost nr: NR, linear nct: NodeCreationToken)
  returns (linear node: Node, linear owned_contexts: lseq<ThreadOwnedContext>)
  requires nct.WF(nr)
  ensures node.WF(nr)
  ensures |owned_contexts| == MAX_THREADS_PER_REPLICA as int
  ensures forall i | 0 <= i < |owned_contexts| ::
    i in owned_contexts && owned_contexts[i].WF(node, nr)
  {
    linear var NodeCreationToken(nodeId, combiner, cb, ghost_replica, cb_loc_s) := nct;

    // initialize the flat_combiner ghost tokens

    glinear var fc_clients, fc_slots, fc_combiner := fc_initialize();
    ghost var fc_loc := fc_combiner.loc_s;

    // build stuff

    linear var actual_replica := nrifc.initialize();
    linear var nodeReplica := NodeReplica(
      actual_replica, ghost_replica, combiner, cb);
    linear var replica;
    glinear var client_counter_supply;
    replica, client_counter_supply := new_mutex(nodeReplica, (v: NodeReplica) => v.WF(nodeId as int, nr.cb_loc_s));
    // deleteme assert replica.InternalInv();

    // thread contexts

    linear var contexts := lseq_alloc<Context>(MAX_THREADS_PER_REPLICA);
    owned_contexts := lseq_alloc<ThreadOwnedContext>(MAX_THREADS_PER_REPLICA);
    var i := 0;
    while i < MAX_THREADS_PER_REPLICA
    invariant 0 <= i <= MAX_THREADS_PER_REPLICA
    invariant |contexts| == MAX_THREADS_PER_REPLICA as int
    invariant |owned_contexts| == MAX_THREADS_PER_REPLICA as int
    invariant forall j: nat | 0 <= j < i as int ::
        j in contexts && j in owned_contexts
    invariant forall j: nat | i as int <= j < MAX_THREADS_PER_REPLICA as int ::
        j !in contexts && j !in owned_contexts

    invariant forall j: nat | 0 <= j < i as int :: owned_contexts[j].tid as int == j
    invariant forall j: nat | 0 <= j < i as int :: owned_contexts[j].fc_client == FCClient(fc_loc, j, FC.FCClientIdle)
    invariant forall j: nat | 0 <= j < i as int :: owned_contexts[j].cell_contents.cell == contexts[j].cell.inner
    invariant forall j: nat | 0 <= j < i as int :: && owned_contexts[j].client_counter.loc == replica.client_counter_loc

    invariant forall j: nat | 0 <= j < i as int ::
        && owned_contexts[j].tid as int == j
        && owned_contexts[j].fc_client == FCClient(fc_loc, j, FC.FCClientIdle)
        && owned_contexts[j].cell_contents.cell == contexts[j].cell.inner
        && owned_contexts[j].client_counter.loc == replica.client_counter_loc
        && |owned_contexts[j].activeIdxs| == MAX_THREADS_PER_REPLICA as int
    invariant forall j: nat | 0 <= j < i as int ::
        contexts[j].WF(j, fc_loc)
    invariant forall j: nat | i as int <= j < MAX_THREADS_PER_REPLICA as int ::
        j in fc_slots && fc_slots[j] == FCSlot(fc_loc, j, FC.FCEmpty)
    invariant forall j: nat | i as int <= j < MAX_THREADS_PER_REPLICA as int ::
        j in fc_clients && fc_clients[j] == FCClient(fc_loc, j, FC.FCClientIdle)
    invariant client_counter_supply.loc == replica.client_counter_loc
    invariant client_counter_supply.n >= MAX_THREADS_PER_REPLICA as int - i as int
    {
      glinear var fc_client, fc_slot;
      fc_clients, fc_client := glmap_take(fc_clients, i as int);
      fc_slots, fc_slot := glmap_take(fc_slots, i as int);

      var dummy_op;
      var dummy_ret;
      linear var ctx_cell;
      glinear var ctx_cell_contents;
      ctx_cell, ctx_cell_contents := new_cell(OpResponse(dummy_op, dummy_ret));

      glinear var ctx_ghost := ContextGhost(glNone, fc_slot, glNone);
      linear var ctx_atomic := new_atomic(0, ctx_ghost,
          (v, g: ContextGhost) => g.inv(v, i as int, ctx_cell, fc_loc), 0);

      glinear var client_counter;
      // deleteme assert client_counter_supply.loc == replica.client_counter_loc;
      client_counter_supply, client_counter := ClientCounter.split(client_counter_supply);
      // deleteme assert client_counter.loc == replica.client_counter_loc;

      linear var toc := ThreadOwnedContext(i, seq_alloc(MAX_THREADS_PER_REPLICA, false),
            fc_client, ctx_cell_contents, client_counter);
      linear var c := Context(CachePadded(ctx_atomic), CachePadded(ctx_cell));

      // deleteme assert client_counter.loc == replica.client_counter_loc;

      lseq_give_inout(inout contexts, i, c);
      lseq_give_inout(inout owned_contexts, i, toc);

      i := i + 1;
    }

    dispose_anything(fc_clients); // this are now empty
    dispose_anything(fc_slots); // this are now empty

    // combiner stuff

    var dummy_op: nrifc.UpdateOp;
    var dummy_resp: nrifc.ReturnType;
    linear var ops, responses;
    glinear var opsContents, responsesContents;
    ops, opsContents := LC.new_lcell();
    opsContents := LC.give_lcell(ops, opsContents, seq_alloc(MAX_THREADS_PER_REPLICA, dummy_op));

    responses, responsesContents := LC.new_lcell();
    responsesContents := LC.give_lcell(responses, responsesContents, seq_alloc(MAX_THREADS_PER_REPLICA, dummy_resp));

    glinear var cls := CombinerLockState(fc_combiner, opsContents, responsesContents);

    linear var combiner_atomic := new_atomic(0, glSome(cls), (v, g) => CombinerLockInv(v, g, fc_loc, ops, responses), 0);

    node := Node(CachePadded(combiner_atomic), ops, responses, replica, contexts, nodeId, fc_loc);
//    assert node.CombinerLockInv(combiner_lock.
//    forall v, g
//      | atomic_inv(node.combiner_lock, v, g)
//      ensures node.CombinerLockInv(v, g)
//    {
//      if v==0 {
//        assert node.CombinerLockInv0(v, g);
//      } else {
//        assert g.glNone?;
//      }
//    }
//    forall v, g
//      | node.CombinerLockInv(v, g)
//      ensures atomic_inv(node.combiner_lock, v, g)
//    {
//    }
    assert node.WF(nr);

    dispose_anything(client_counter_supply);
  }

  method make_buffer_cells()
  returns (linear cells: lseq<Cell<CB.ConcreteLogEntry>>,
      glinear cell_contents: map<int, CB.StoredType>)
  ensures |cells| == LOG_SIZE as int
  ensures lseq_full(cells)
  ensures forall i | -(LOG_SIZE as int) <= i < 0 :: i in cell_contents
      && cell_contents[i].cellContents.cell == cells[i % LOG_SIZE as int]
  ensures forall i | i in cell_contents ::
      -(LOG_SIZE as int) <= i < 0
  {
    cells := lseq_alloc(LOG_SIZE);
    cell_contents := glmap_empty();

    var j := 0;
    while j < LOG_SIZE
    invariant 0 <= j <= LOG_SIZE
    invariant |cells| == LOG_SIZE as int
    invariant forall i | 0 <= i < j as int :: i in cells
    invariant forall i | j as int <= i < LOG_SIZE as int :: i !in cells
    invariant forall i | -(LOG_SIZE as int) <= i < -(LOG_SIZE as int) + j as int :: i in cell_contents
       && cell_contents[i].cellContents.cell == cells[i % LOG_SIZE as int]
    invariant forall i | i in cell_contents ::
       -(LOG_SIZE as int) <= i < -(LOG_SIZE as int) + j as int
    {
      var op;
      linear var cell;
      glinear var cell_cont;
      cell, cell_cont := new_cell(CB.ConcreteLogEntry(op, 0));
      cells := lseq_give(cells, j, cell);

      glinear var st := CB.StoredType(cell_cont, glNone);
      cell_contents := glmap_insert(cell_contents, -(LOG_SIZE as int) + j as int, st);

      j := j + 1;
    }
  }

  method make_buffer(
      linear cells: lseq<Cell<CB.ConcreteLogEntry>>, 
      glinear alive: map<nat, CBAliveBit>,
      ghost cb_loc_s: nat)
  returns (linear buffer: lseq<BufferEntry>)
  requires |cells| == LOG_SIZE as int
  requires forall i | 0 <= i < LOG_SIZE as int ::
      && i in cells
      && i in alive
      && alive[i] == CBAliveBit(i, false, cb_loc_s)
  ensures |buffer| == LOG_SIZE as int
  ensures forall i | 0 <= i < LOG_SIZE as int
    :: i in buffer && buffer[i].cell == cells[i]
        && buffer[i].WF(i, cb_loc_s)
  {
    buffer := lseq_alloc(LOG_SIZE);
    linear var cells' := cells;
    glinear var alive' := alive;

    var j := 0;
    while j < LOG_SIZE
    invariant 0 <= j <= LOG_SIZE
    invariant |buffer| == LOG_SIZE as int
    invariant forall i | 0 <= i < j as int
      :: i in buffer && buffer[i].cell == cells[i]
          && buffer[i].WF(i, alive[i].cb_loc_s)
    invariant forall i | j as int <= i < LOG_SIZE as int
      :: i !in buffer
    invariant |cells'| == LOG_SIZE as int
    invariant forall i | j as int <= i < LOG_SIZE as int ::
        && i in cells'
        && i in alive'
        && cells[i] == cells'[i]
        && alive[i] == alive'[i]
    invariant forall i | 0 <= i < j as int :: 
        && i !in cells'
        && i !in alive'
    {
      linear var cell;
      cells', cell := lseq_take(cells', j);

      glinear var aliveBit;
      alive', aliveBit := glmap_take(alive', j as int);

      linear var aliveAtomic := new_atomic(false, aliveBit,
          ((v, g) => g == CBAliveBit(j as int, v, alive[j as nat].cb_loc_s)),
          0);

      linear var bufferEntry := BufferEntry(cell, aliveAtomic);
      assert bufferEntry.WF(j as int, cb_loc_s);

      buffer := lseq_give(buffer, j, bufferEntry);

      j := j + 1;
    }

    assert j == LOG_SIZE;
    forall i:nat | i < |lseqs_raw(cells')| ensures !has(lseqs_raw(cells')[i])
    {
      assert i !in cells';
    }
    var _ := lseq_free_raw(cells');
    dispose_anything(alive');
  }

  method make_node_infos(
      glinear localTails: map<nat, LocalTail>,
      glinear cbLocalTails: map<nat, CBLocalTail>,
      ghost cb_loc_s: nat)
  returns (linear node_info: lseq<NodeInfo>)
  requires forall i | 0 <= i < NUM_REPLICAS as int ::
      && i in localTails
      && i in cbLocalTails
      && localTails[i] == LocalTail(i as int, 0)
      && cbLocalTails[i] == CBLocalTail(i as int, 0, cb_loc_s)
  ensures |node_info| == NUM_REPLICAS as int
  ensures forall i | 0 <= i < NUM_REPLICAS as int
      :: i in node_info && node_info[i].WF(i, cb_loc_s)
  {
    node_info := lseq_alloc(NUM_REPLICAS);

    glinear var localTails' := localTails;
    glinear var cbLocalTails' := cbLocalTails;

    var j := 0;
    while j < NUM_REPLICAS
    invariant 0 <= j <= NUM_REPLICAS
    invariant forall i | j as int <= i < NUM_REPLICAS as int ::
        && i in localTails'
        && i in cbLocalTails'
        && localTails'[i] == LocalTail(i as int, 0)
        && cbLocalTails'[i] == CBLocalTail(i as int, 0, cb_loc_s)
    invariant |node_info| == NUM_REPLICAS as int
    invariant forall i | 0 <= i < j as int
        :: i in node_info && node_info[i].WF(i, cb_loc_s)
    invariant forall i | j as int <= i < NUM_REPLICAS as int
        :: i !in node_info
    {
      glinear var localTail, cbLocalTail;
      localTails', localTail := glmap_take(localTails', j as int);
      cbLocalTails', cbLocalTail := glmap_take(cbLocalTails', j as int);

      linear var localTailAtomic := new_atomic(
          0,
          LocalTailTokens(localTail, cbLocalTail),
          ((v, g) => LocalTailInv(v, g, j as int, cb_loc_s)),
          0);

      linear var nodeInfo := NodeInfo(localTailAtomic);
      assert nodeInfo.WF(j as int, cb_loc_s);

      node_info := lseq_give(node_info, j, nodeInfo);

      j := j + 1;
    }

    dispose_anything(localTails');
    dispose_anything(cbLocalTails');
  }

  method make_node_creation_tokens(
      ghost nr: NR,
      glinear replicas: map<nat, Replica>,
      glinear combiners: map<nat, CombinerToken>,
      glinear readers: map<nat, CBCombinerToken>)
  returns (linear nodeCreationTokens: lseq<NodeCreationToken>)
  requires forall i | 0 <= i < NUM_REPLICAS as int ::
      && i in replicas
      && i in combiners
      && i in readers
      && replicas[i] == Replica(i, nrifc.init_state())
      && combiners[i] == CombinerToken(i, CombinerReady)
      && readers[i] == CBCombinerToken(i, CB.CombinerIdle, nr.cb_loc_s)
  ensures |nodeCreationTokens| == NUM_REPLICAS as int
  ensures forall i | 0 <= i < NUM_REPLICAS as int
      :: i in nodeCreationTokens && nodeCreationTokens[i].WF(nr)
  {
    nodeCreationTokens := lseq_alloc(NUM_REPLICAS);

    glinear var replicas' := replicas;
    glinear var combiners' := combiners;
    glinear var readers' := readers;

    var j := 0;
    while j < NUM_REPLICAS
    invariant 0 <= j <= NUM_REPLICAS
    invariant forall i | j as int <= i < NUM_REPLICAS as int ::
        && i in replicas'
        && i in combiners'
        && i in readers'
        && replicas[i] == replicas'[i]
        && combiners[i] == combiners'[i]
        && readers[i] == readers'[i]
    invariant |nodeCreationTokens| == NUM_REPLICAS as int
    invariant forall i | 0 <= i < j as int
        :: i in nodeCreationTokens && nodeCreationTokens[i].WF(nr)
    invariant forall i | j as int <= i < NUM_REPLICAS as int
        :: i !in nodeCreationTokens
    {
      glinear var replica, combiner, cb;
      replicas', replica := glmap_take(replicas', j as int);
      combiners', combiner := glmap_take(combiners', j as int);
      readers', cb := glmap_take(readers', j as int);

      linear var nct := NodeCreationToken(j, combiner, cb, replica, nr.cb_loc_s);
      assert nct.WF(nr);

      nodeCreationTokens := lseq_give(nodeCreationTokens, j, nct);

      j := j + 1;
    }

    dispose_anything(replicas');
    dispose_anything(combiners');
    dispose_anything(readers');
  }

  method initNR(glinear token: Tokens.Token)
  returns (
      linear nr: NR,
      linear nodeCreationTokens: lseq<NodeCreationToken>
      )
  requires token.loc == loc()
  requires token.val == IL.Init()
  ensures nr.WF()
  ensures |nodeCreationTokens| == NUM_REPLICAS as int
  ensures forall i | 0 <= i < |nodeCreationTokens| ::
      i in nodeCreationTokens && nodeCreationTokens[i].WF(nr)
  {
    linear var buffer_cells;
    glinear var buffer_cell_contents;
    buffer_cells, buffer_cell_contents := make_buffer_cells();

    glinear var globalTail, replicas, localTails, ctail, combiners := perform_Init(token);
    glinear var cbHead, cbGlobalTail, cbLocalTails, alive, cbContents, readers, cb_loc :=
        cyclic_buffer_init(buffer_cell_contents);
    ghost var cb_loc_s := cb_loc.s;

    linear var ctail_atomic: Atomic<uint64, Ctail> := new_atomic(
        0,
        ctail,
        (v, g) => g == Ctail(v as int),
        0);
    linear var head_atomic: Atomic<uint64, CBHead> := new_atomic(
        0,
        cbHead,
        (v, g) => g == CBHead(v as int, cb_loc_s),
        0);
    linear var globalTail_atomic: Atomic<uint64, GlobalTailTokens> := new_atomic(
          0,
          GlobalTailTokens(globalTail, cbGlobalTail),
          ((v, g) => GlobalTailInv(v, g, cb_loc_s)),
          0);

    linear var buffer: lseq<BufferEntry> := make_buffer(buffer_cells, alive, cb_loc_s);

    glinear var bufferContents: GhostAtomic<CBContents> := new_ghost_atomic(
        cbContents,
        (g) => ContentsInv(buffer, g, cb_loc_s),
        1);

    linear var node_infos: lseq<NodeInfo> := make_node_infos(localTails, cbLocalTails, cb_loc_s);

    nr := NR(CachePadded(ctail_atomic), CachePadded(head_atomic), CachePadded(globalTail_atomic), node_infos, buffer, bufferContents, cb_loc_s);

    nodeCreationTokens := make_node_creation_tokens(nr, replicas, combiners, readers);
  }
}
