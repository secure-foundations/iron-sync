include "MapSpec.dfy"
include "UIStateMachine.dfy"
include "../lib/Maps.dfy"

abstract module ThreeStateVersionedSystem {
  import SM : UIStateMachine

  import opened Maps
  import UI

  datatype SyncReqStatus = State1 | State2 | State3
  datatype Constants = Constants(k: SM.Constants)
  datatype Variables = Variables(
      s1: SM.Variables,
      s2: SM.Variables,
      s3: SM.Variables,
      outstandingSyncReqs: map<int, SyncReqStatus>
  )

  predicate Init(k: Constants, s: Variables)
  {
    && SM.Init(k.k, s.s1)
    && s.s2 == s.s1
    && s.s3 == s.s1
    && s.outstandingSyncReqs == map[]
  }

  datatype Step =
    | CrashStep
    | Move1to2Step
    | Move2to3Step
    | Move3Step
    | PushSyncStep(id: int)
    | PopSyncStep(id: int)

  predicate Crash(k: Constants, s: Variables, s': Variables, uiop: SM.UIOp)
  {
    && uiop.CrashOp?
    && s' == Variables(s.s1, s.s1, s.s1, map[])
  }

  predicate Move1to2(k: Constants, s: Variables, s': Variables, uiop: SM.UIOp)
  {
    && uiop.NoOp?
    && s' == Variables(s.s2, s.s2, s.s3,
      map id | id in s.outstandingSyncReqs :: (
        match s.outstandingSyncReqs[id] {
          case State1 => State1
          case State2 => State1
          case State3 => State3
        }
      ))
  }

  predicate Move2to3(k: Constants, s: Variables, s': Variables, uiop: SM.UIOp)
  {
    && uiop.NoOp?
    && s' == Variables(s.s1, s.s3, s.s3,
      map id | id in s.outstandingSyncReqs :: (
        match s.outstandingSyncReqs[id] {
          case State1 => State1
          case State2 => State2
          case State3 => State2
        }
      ))
  }

  predicate Move3(k: Constants, s: Variables, s': Variables, uiop: SM.UIOp)
  {
    && SM.Next(k.k, s.s3, s'.s3, uiop)
    && s' == Variables(s.s1, s.s3, s'.s3, s.outstandingSyncReqs)
  }

  predicate PushSync(k: Constants, s: Variables, s': Variables, uiop: SM.UIOp, id: int)
  {
    && uiop == UI.PushSyncOp(id)
    && id !in s.outstandingSyncReqs
    && s' == Variables(s.s1, s.s2, s.s3, s.outstandingSyncReqs[id := State3])
  }

  predicate PopSync(k: Constants, s: Variables, s': Variables, uiop: SM.UIOp, id: int)
  {
    && uiop == UI.PopSyncOp(id)
    && id in s.outstandingSyncReqs
    && s.outstandingSyncReqs[id] == State1
    && s' == Variables(s.s1, s.s2, s.s3, MapRemove1(s.outstandingSyncReqs, id))
  }

  predicate NextStep(k: Constants, s: Variables, s': Variables, uiop: SM.UIOp, step: Step)
  {
    match step {
      case CrashStep => Crash(k, s, s', uiop)
      case Move1to2Step => Move1to2(k, s, s', uiop)
      case Move2to3Step => Move2to3(k, s, s', uiop)
      case Move3Step => Move3(k, s, s', uiop)
      case PushSyncStep(id) => PushSync(k, s, s', uiop, id)
      case PopSyncStep(id) => PopSync(k, s, s', uiop, id)
    }
  }

  predicate Next(k: Constants, s: Variables, s': Variables, uiop: SM.UIOp) {
    exists step :: NextStep(k, s, s', uiop, step)
  }
}
