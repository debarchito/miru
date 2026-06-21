open Bigarray

(** This module defines a uniform representation model identical to OCaml. The
    least significant bit is used to differentiate between an int and a heap
    ptr. This as a consequence, makes all unboxed integers signed 63-bit. *)

(** TODO: In the future, I shall consider a layout-aware kind system for more
    unboxed value representations. Mode-driven unboxing and stack allocation is
    also something I'm very interested in. *)

type word = int64
type memory = (int64, int64_elt, c_layout) Array1.t

let[@inline] create_memory size : memory = Array1.create int64 c_layout size

(**)
let[@inline] is_ptr (w : word) = Int64.logand w 1L = 0L

let[@inline] word_of_ptr (p : int64) : word =
  assert (is_ptr p);
  p

let[@inline] ptr_of_word (w : word) : int64 = w

(**)
let[@inline] is_int (w : word) = Int64.logand w 1L = 1L

let[@inline] word_of_int n : word =
  Int64.logor (Int64.shift_left (Int64.of_int n) 1) 1L

let[@inline] int_of_word (w : word) = Int64.to_int (Int64.shift_right w 1)
