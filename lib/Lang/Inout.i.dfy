module Inout {
    method Replace<V>(linear inout v: V, linear newv: V)
    returns (linear replaced: V)
    ensures v == newv
    ensures replaced == old_v
    {
      linear var tmp := newv;
      replaced := v;
      v := tmp;
    }
}
