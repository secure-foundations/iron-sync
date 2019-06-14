include "../tla-tree/MissingLibrary.dfy"

abstract module MapSpec {
import opened MissingLibrary

type Key(!new,==)

// Users must provide a definition of EmptyValue
function EmptyValue<Value>() : Value

datatype Constants = Constants()
type View<Value> = imap<Key, Value>
datatype Variables<Value> = Variables(view:View<Value>)

predicate ViewComplete(view:View)
{
  forall k :: k in view
}

predicate WF(s:Variables)
{
    && ViewComplete(s.view)
}

// Dafny black magic: This name is here to give EmptyMap's forall something to
// trigger on. (Eliminates a /!\ Warning.)
predicate InDomain(k:Key)
{
    true
}

function EmptyMap<Value>() : (zmap : imap<Key,Value>)
    ensures ViewComplete(zmap)
{
    imap k | InDomain(k) :: EmptyValue()
}

predicate Init(k:Constants, s:Variables)
    ensures Init(k, s) ==> WF(s)
{
    s == Variables(EmptyMap())
}

predicate Query<Value>(k:Constants, s:Variables, s':Variables, key:Key, result:Value)
    requires WF(s)
{
    && result == s.view[key]
    && s' == s
}

predicate Write<Value>(k:Constants, s:Variables, s':Variables, key:Key, new_value:Value)
    requires WF(s)
    ensures Write(k, s, s', key, new_value) ==> WF(s')
{
    && WF(s')
    && s'.view == s.view[key := new_value]
}

predicate Stutter(k:Constants, s:Variables, s':Variables)
    requires WF(s)
{
    s' == s
}

datatype Step<Value> =
    | QueryStep(key:Key, result:Value)
    | WriteStep(key:Key, new_value:Value)
    | StutterStep

predicate NextStep(k:Constants, s:Variables, s':Variables, step:Step)
    requires WF(s)
{
    match step {
        case QueryStep(key, result) => Query(k, s, s', key, result)
        case WriteStep(key, new_value) => Write(k, s, s', key, new_value)
        case StutterStep() => Stutter(k, s, s')
    }
}

predicate Next<Value(!new)>(k:Constants, s:Variables, s':Variables)
    requires WF(s)
    ensures Next(k, s, s') ==> WF(s')
{
    exists step :: NextStep<Value>(k, s, s', step)
}

predicate Inv(k:Constants, s:Variables) { WF(s) }

lemma NextPreservesInv(k: Constants, s: Variables, s': Variables)
  requires Inv(k, s)
  requires Next(k, s, s')
  ensures Inv(k, s')
{
}

}
