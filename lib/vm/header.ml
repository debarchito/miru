open Value

(* gc colors *)
let color_white = 0
let color_gray = 1
let color_black = 2
let color_promoted = 3

(* reserved tags *)
let no_scan_tag = 0xFA
let abstract_tag = 0xFB
let string_tag = 0xFC
let double_tag = 0xFD
let forward_tag = 0xFE
let free_tag = 0xFF

let[@inline] make ~size ~color ~tag : word =
  Int64.of_int ((size lsl 10) lor (color lsl 8) lor tag)

let[@inline] tag (h : word) = Int64.to_int h land 0xFF
let[@inline] color (h : word) = (Int64.to_int h lsr 8) land 0x3
let[@inline] size (h : word) = Int64.to_int (Int64.shift_right_logical h 10)

let[@inline] set_color (h : word) c : word =
  Int64.logor (Int64.logand h (Int64.lognot 0x300L)) (Int64.of_int (c lsl 8))

let[@inline] set_tag (h : word) t : word =
  Int64.logor (Int64.logand h (Int64.lognot 0xFFL)) (Int64.of_int t)

let[@inline] should_trace (h : word) = tag h < no_scan_tag
let[@inline] is_forward (h : word) = tag h = forward_tag
let[@inline] is_free (h : word) = tag h = free_tag
