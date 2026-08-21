type int_suffix =
  { signed: bool
  ; bits: int
  }
[@@deriving show]

let default_int_suffix = {signed= true; bits= 64}

let pp_int_suffix ppf s =
  Format.fprintf ppf "%c%d" (if s.signed then 'i' else 'u') s.bits

let show_int_suffix s =
  Printf.sprintf "%c%d" (if s.signed then 'i' else 'u') s.bits

type float_suffix = int

let pp_float_suffix ppf n = Format.fprintf ppf "f%d" n

let show_float_suffix n = Printf.sprintf "f%d" n

let default_float_suffix = 64

module Zt = struct
  type t = Z.t

  let pp ppf z = Format.fprintf ppf "%s" (Z.to_string z)

  let show z = Z.to_string z
end

module AnyFloatt = struct
  type t = Floatml.AnyFloat.t

  let pp = Floatml.AnyFloat.pp

  let show = Floatml.AnyFloat.show
end

type t =
  | Unit
  | Bool of bool
  | Int of Zt.t * int_suffix
  | Float of AnyFloatt.t * float_suffix
  | String of string
  | Symbol of string
  | Call of t list
  | Record_value of (t * t) list
  | Record_match of (t * t) list
  | Record of string * t
  | Fn of t * t
  | Let of t * t
  | Block of t list
  | Field of t
  | Specifier of string * t
  | Intermediate_empty
  | Intermediate_block_inline of t list
  | Intermediate_record_raw of t list
[@@deriving show]
