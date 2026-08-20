type t =
  | Unit
  | Empty
  | Bool of bool
  | Int of int64
  | Float of float
  | String of string
  | Symbol of string
  | Call of t list
  | RawRecord of t list
  | RecordValue of (t * t) list
  | RecordMatch of (t * t) list
  | Record of string * t
  | Constructor of string * t option
  | Variant of string * t list
  | AbstractType of string * t
  | Tag of string * t
  | Fn of t * t
  | Quote of t
  | Quasiquote of t
  | Unquote of t
  | Splice of t
  | Field of t
  | Specifier of string * t
  | Type of t
  | TypeApplication of string * t
  | Let of {name: t; body: t}
  | Block of t list
  | Sequence of t list
[@@deriving show]
