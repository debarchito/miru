open Value

(** This module defines a 64-bit metadata header. Bits 0-7 store an 8-bit
    semantic type tag, bits 8-9 track a 2-bit tricolor GC color, and the
    remaining 54-bits track allocation size (word size). *)

(* NOTE: tag 0 is the standard block tag for tuples, records and arrays. *)
(* NOTE: tag 1 through 245 are for variant constructors. *)

let tag_lazy = 246
let tag_closure = 247
let tag_infix = 248
let tag_forward = 249
let tag_no_scan = 250 (* >= 250 are treated as opaque objects by GC. *)
let tag_bytes = 251
let tag_string = 252 (* unlike OCaml, Miru strings are UTF-8 encoded. *)
let tag_float = 253
let tag_float_array = 254
let tag_custom = 255

(* these colors use the same OCaml convention *)
let color_white = 0
let color_black = 1
let color_gray = 2
let color_blue = 3

let[@inline] make ~size ~color ~tag : word =
  assert (tag land 0xFF = tag);
  assert (color land 0x3 = color);
  let tag = Int64.of_int tag in
  let color = Int64.of_int (color lsl 8) in
  let size = Int64.logand (Int64.of_int size) 0x3FFFFFFFFFFFFFL in
  let size_part = Int64.shift_left size 10 in
  Int64.logor (Int64.logor size_part color) tag

let[@inline] tag (h : word) = Int64.to_int (Int64.logand h 0xFFL)

let[@inline] color (h : word) =
  Int64.to_int (Int64.shift_right_logical (Int64.logand h 0x300L) 8)

let[@inline] size (h : word) = Int64.to_int (Int64.shift_right_logical h 10)

let[@inline] set_color (h : word) c : word =
  Int64.logor
    (Int64.logand h (Int64.lognot 0x300L))
    (Int64.shift_left (Int64.of_int (c land 0x3)) 8)

let[@inline] set_tag (h : word) t : word =
  Int64.logor (Int64.logand h (Int64.lognot 0xFFL)) (Int64.of_int (t land 0xFF))

let[@inline] set_size (h : word) (s : int) : word =
  Int64.logor (Int64.logand h 0x3FFL)
    (Int64.shift_left (Int64.logand (Int64.of_int s) 0x3FFFFFFFFFFFFFL) 10)

let[@inline] is_variant_constructor t = t >= 1 && t < tag_lazy
let[@inline] is_forward (h : word) = tag h = tag_forward
let[@inline] is_opaque (h : word) = tag h >= tag_no_scan
