include "Interpretation.i.dfy"
include "../framework/StateMachines.s.dfy"

module ResourceStateMachine_Refines_AsyncMapSpec
  refines Refinement(
      AsyncIfc(MapIfc),
      TicketStubStateMachine(MapIfc, ShardedHashTable),
      AsyncStateMachineWithMultisets(MapIfc, MapSpec)
  )
{
  import HT = ShardedHashTable
  import opened Interpretation
  import opened RequestIds
  import Multisets
  import MapSpec
  import MapIfc
  import SummaryMonoid
  import opened KeyValueType

  function req_of_ticket(t: HT.Request) : B.Req {
    B.Req(t.rid, t.input)
  }

  function resp_of_stub(t: HT.Response) : B.Resp {
    B.Resp(t.rid, t.output)
  }

  function reqs_of_tickets(t: multiset<HT.Request>) : multiset<B.Req> {
    Multisets.Apply(req_of_ticket, t)
  }

  function resps_of_stubs(t: multiset<HT.Response>) : multiset<B.Resp> {
    Multisets.Apply(resp_of_stub, t)
  }

  function I(s: A.Variables) : B.Variables
  //requires Inv(s)
  {
    var t := interp(s.table);
    B.Variables(
      MapSpec.Variables(map_remove_nones(t.ops)),
      reqs_of_tickets(s.tickets),
      resps_of_stubs(s.stubs)
          + resps_of_stubs(t.stubs)
          + resps_of_stubs(apply_to_query_stub(t.queries))
          + resps_of_stubs(apply_to_remove_stub(t.removes))
    )
  }

  predicate Inv(s: A.Variables)
  {
    HT.Inv(s)
  }
 
  lemma Internal_RefinesMap(s: A.Variables, s': A.Variables)
    requires Inv(s)
    requires HT.Internal(s, s')
    ensures Inv(s')
    ensures B.Next(I(s), I(s'), ifc.InternalOp)
  {
    MultisetLemmas.MultisetSimplificationTriggers<HT.Request, B.Req>();
    MultisetLemmas.MultisetSimplificationTriggers<HT.Response, B.Resp>();
    MultisetLemmas.MultisetSimplificationTriggers<S.QueryRes, HT.Response>();

    var step :| HT.NextStep(s, s', step);
    match step {
      case InsertSkipStep(pos) => {
        InsertSkip_PreservesInterp(s, s', pos);
      }
      case InsertSwapStep(pos) => {
        InsertSwap_PreservesInterp(s, s', pos);
      }
      case InsertDoneStep(pos) => {
        InsertDone_PreservesInterp(s, s', pos);
        //assert I(s).resps == I(s').resps;
        //assert I(s) == I(s');
      }
      case InsertUpdateStep(pos) => {
        InsertUpdate_PreservesInterp(s, s', pos);
      }
      case RemoveSkipStep(pos) => {
        RemoveSkip_PreservesInterp(s, s', pos);
      }
      case RemoveFoundItStep(pos) => {
        RemoveFoundIt_PreservesInterp(s, s', pos);
      }
      case RemoveNotFoundStep(pos) => {
        RemoveNotFound_PreservesInterp(s, s', pos);
      }
      case RemoveTidyStep(pos) => {
        RemoveTidy_PreservesInterp(s, s', pos);
      }
      case RemoveDoneStep(pos) => {
        RemoveDone_PreservesInterp(s, s', pos);

        /*assert resps_of_stubs(s.stubs) + multiset{B.Resp(s.table[pos].value.state.rid, MapIfc.RemoveOutput(true))}
            == resps_of_stubs(s'.stubs);
        assert resps_of_stubs(apply_to_remove_stub(interp(s.table).removes))
            == resps_of_stubs(apply_to_remove_stub(interp(s'.table).removes)) + multiset{B.Resp(s.table[pos].value.state.rid, MapIfc.RemoveOutput(true))};
        assert resps_of_stubs(s.stubs)
                + resps_of_stubs(apply_to_remove_stub(interp(s.table).removes))
            == resps_of_stubs(s'.stubs)
                + resps_of_stubs(apply_to_remove_stub(interp(s'.table).removes));
        assert I(s).resps == I(s').resps;
        assert I(s) == I(s');*/
      }
      case QuerySkipStep(pos) => {
        QuerySkip_PreservesInterp(s, s', pos);
      }
      case QueryDoneStep(pos) => {
        QueryDone_PreservesInterp(s, s', pos);
      }
      case QueryNotFoundStep(pos) => {
        QueryNotFound_PreservesInterp(s, s', pos);
      }

      case ProcessInsertTicketStep(insert_ticket) => {
        ProcessInsertTicket_ChangesInterp(s, s', insert_ticket);
        var I_s := I(s);
        var I_s' := I(s');
        var rid := insert_ticket.rid;
        var input := insert_ticket.input;
        var output := MapIfc.InsertOutput(true);

        assert s.tickets == s'.tickets + multiset{insert_ticket};
        /*assert resps_of_stubs(interp(s'.table).stubs)
            == resps_of_stubs(interp(s.table).stubs) + multiset{B.Resp(rid, output)};
        assert B.Req(rid, input) in I_s.reqs;
        assert I_s.reqs == I_s'.reqs + multiset{B.Req(rid, input)};
        assert I_s'.resps == I_s.resps + multiset{B.Resp(rid, output)};
        assert MapSpec.Next(I_s.s, I_s'.s, MapIfc.Op(input, output));*/
        assert B.LinearizationPoint(I_s, I_s', rid, input, output);
      }
      case ProcessRemoveTicketStep(remove_ticket) => {
        ProcessRemoveTicket_ChangesInterp(s, s', remove_ticket);
        assert s.tickets == s'.tickets + multiset{remove_ticket};
        assert B.LinearizationPoint(I(s), I(s'), remove_ticket.rid, remove_ticket.input,
            MapIfc.RemoveOutput(remove_ticket.input.key in I(s).s.m));
      }
      case ProcessQueryTicketStep(query_ticket) => {
        ProcessQueryTicket_ChangesInterp(s, s', query_ticket);

        assert s.tickets == s'.tickets + multiset{query_ticket};

        if query_ticket.input.key in I(s).s.m {
          assert B.LinearizationPoint(I(s), I(s'), query_ticket.rid, query_ticket.input,
              MapIfc.QueryOutput(Found(I(s).s.m[query_ticket.input.key])));
        } else {
          assert B.LinearizationPoint(I(s), I(s'), query_ticket.rid, query_ticket.input,
              MapIfc.QueryOutput(NotFound));
        }
      }
    }
  }

  lemma NewTicket_RefinesMap(s: A.Variables, s': A.Variables, rid: RequestId, input: MapIfc.Input)
    requires Inv(s)
    requires HT.NewTicket(s, s', rid, input)
    ensures Inv(s')
    ensures B.Next(I(s), I(s'), ifc.Start(rid, input))
  {
    assert s'.table == s.table;
    assert s'.stubs == s.stubs;
    MultisetLemmas.MultisetSimplificationTriggers<HT.Request, B.Req>();
    //assert s'.tickets == s.tickets + multiset{HT.Request(rid, input)};
    //assert I(s').reqs == I(s).reqs + multiset{B.Req(rid, input)};
    //assert I(s').s == I(s).s;
  }

  lemma ConsumeStub_RefinesMap(s: A.Variables, s': A.Variables, rid: RequestId, output: MapIfc.Output)
     requires Inv(s)
     requires HT.ConsumeStub(s, s', rid, output, HT.output_stub(rid, output))
     ensures Inv(s')
     ensures B.Next(I(s), I(s'), ifc.End(rid, output))
   {
     assert s'.table == s.table;
     assert s'.tickets == s.tickets;
     assert s.stubs == s'.stubs + multiset{HT.Response(rid, output)};
     MultisetLemmas.MultisetSimplificationTriggers<HT.Response, B.Resp>();
     /*assert s.stubs == s'.stubs + multiset{HT.Response(rid, output)};
     assert I(s).resps == I(s').resps + multiset{B.Resp(rid, output)};
     assert I(s').resps == I(s).resps - multiset{B.Resp(rid, output)};
     assert I(s').s == I(s).s;
     assert I(s').reqs == I(s).reqs;
     assert B.Resp(rid, output) in I(s).resps;*/
  }

  lemma InitImpliesInv(s: A.Variables)
  //requires A.Init(s)
  ensures Inv(s)
  {
    HT.InitImpliesInv(s);
  }

  lemma NextPreservesInv(s: A.Variables, s': A.Variables, op: ifc.Op)
  //requires Inv(s)
  //requires A.Next(s, s', op)
  ensures Inv(s')
  {
    match op {
      case Start(rid, input) => {
        HT.NewTicketPreservesInv(s, s', rid, input);
      }
      case End(rid, output) => {
        var stub :| HT.ConsumeStub(s, s', rid, output, stub);
        HT.ConsumeStubPreservesInv(s, s', rid, output, stub);
      }
      case InternalOp => {
        var shard, shard', rest :| A.InternalNext(s, s', shard, shard', rest);
        HT.InternalPreservesInv(shard, shard', rest);
      }
    }
  }

  lemma InitRefinesInit(s: A.Variables)
  //requires A.Init(s)
  //requires Inv(s)
  ensures B.Init(I(s))
  {
    assert interp(s.table) == SummaryMonoid.unit()
    by {
      var e := HT.get_empty_cell(s.table);
      reveal_interp();
      reveal_interp_wrt();
      SummaryMonoid.concat_all_units(s.table[e+1..] + s.table[..e+1]);
    }
  }

  lemma NextRefinesNext(s: A.Variables, s': A.Variables, op: ifc.Op)
  //requires Inv(s)
  //requires Inv(s')
  //requires A.Next(s, s', op)
  ensures B.Next(I(s), I(s'), op)
  {
    match op {
      case Start(rid, input) => {
        NewTicket_RefinesMap(s, s', rid, input);
      }
      case End(rid, output) => {
        var stub :| HT.ConsumeStub(s, s', rid, output, stub);
        ConsumeStub_RefinesMap(s, s', rid, output);
      }
      case InternalOp => {
        var shard, shard', rest :| A.InternalNext(s, s', shard, shard', rest);
        HT.InternalPreservesInv(shard, shard', rest);
        HT.InvImpliesValid(HT.dot(shard, rest));
        HT.update_monotonic(shard, shard', rest);
        Internal_RefinesMap(HT.dot(shard, rest), HT.dot(shard', rest));
      }
    }
  }

}
