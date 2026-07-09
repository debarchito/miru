type t =
  | Unit
  | Empty
  | Bool of bool
  | Int of int64
  | Float of float
  | String of string
  | Symbol of string
  | List of t list
  | RecordExpression of (t * t) list
  | Record of string * t
  | Constructor of string * t option
  | Variant of string * t list
  | AbstractType of string * t
  | Tag of string * t
  | Fn of t list
  | Quote of t
  | Quasiquote of t
  | Unquote of t
  | Splice of t
  | Field of t
  | MutableField of string
  | Type of t
  | TypeApplication of string * t
