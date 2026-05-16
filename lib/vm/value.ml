open Bigarray

type word = int64
type memory = (int64, int64_elt, c_layout) Array1.t

let[@inline] create_memory size : memory = Array1.create int64 c_layout size
let[@inline] word_of_value n : word = Int64.of_int n
let[@inline] value_of_word (w : word) : int = Int64.to_int w
