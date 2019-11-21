include "../lib/Base/KeyType.s.dfy"

module UI {
  //import Keyspace = Total_Order
  //import Keyspace = Lexicographic_Byte_Order

  import V = ValueWithDefault
  import K = KeyType

  type Value = V.Value
  type Key = K.Key

  datatype SuccResult = SuccNone | SuccKeyValue(key: Key, value: Value)

  datatype Op =
    | NoOp
    | SyncOp
    | CrashOp
    | PushSyncOp(ghost id: int)
    | PopSyncOp(ghost id: int)

    // TODO make these async? any value from it?
    | GetOp(key: Key, value: Value)
    | PutOp(key: Key, value: Value)

    // For a query of key, return the succKey such that
    // key < succKey, and succKey is the minimal such key.
    | SuccOp(key: Key, res: SuccResult)
}