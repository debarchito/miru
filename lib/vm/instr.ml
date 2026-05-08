type reg = int
type func_id = int

type t =
  | Add_int of reg * reg * reg
  | Sub_int of reg * reg * reg
  | Mul_int of reg * reg * reg
  | Div_int of reg * reg * reg
  | Mod_int of reg * reg * reg
  | Neg_int of reg * reg
  (**)
  | Add_float of reg * reg * reg
  | Sub_float of reg * reg * reg
  | Mul_float of reg * reg * reg
  | Div_float of reg * reg * reg
  | Neg_float of reg * reg
  (**)
  | Eq_int of reg * reg * reg
  | Ne_int of reg * reg * reg
  | Lt_int of reg * reg * reg
  | Le_int of reg * reg * reg
  | Gt_int of reg * reg * reg
  | Ge_int of reg * reg * reg
  (**)
  | Eq_float of reg * reg * reg
  | Ne_float of reg * reg * reg
  | Lt_float of reg * reg * reg
  | Le_float of reg * reg * reg
  | Gt_float of reg * reg * reg
  | Ge_float of reg * reg * reg
  (**)
  | And of reg * reg * reg
  | Or of reg * reg * reg
  | Not of reg * reg
  (**)
  | Cast_int_as_float of reg * reg
  | Cast_float_as_int of reg * reg
  (**)
  | Mov of reg * reg
  | Load_int of reg * int
  | Load_float of reg * float
  | Load_bool of reg * bool
  (**)
  | Jmp of int
  | Jt of reg * int
  | Jf of reg * int
  (**)
  | Call of func_id * reg list * reg
  | Tail_call of func_id * reg list
  | Ret of reg
  | Ret_unit
  (**)
  | Alloc of reg * int * int
  | Load_field of reg * reg * int
  | Store_field of reg * int * reg
  | Alloc_array of reg * reg * int
  | Load_array of reg * reg * reg
  | Store_array of reg * reg * reg
  | Length_array of reg * reg
  | Load_tag of reg * reg
  | Store_tag of reg * int
  (**)
  | Make_closure of reg * func_id * reg list
  | Call_closure of reg * reg list * reg
  | Load_upvar of reg * reg * int
  (**)
  | Trap of int
  | Pop_trap
  | Raise of reg
  (**)
  | Nop
  | Halt
