(** This ISA is designed around the uniform value representation that the RTL implements. A total
    of 256 registers are split into 224 general-purpose registers (GPRs) and 32 floating-point
    registers (FPRs). Thus, floats get special treatment in this ISA which contains specialized
    instructions to operate directly on unboxed machine floats. Makes math fast and snappy :D *)

type reg = Reg of int [@@unboxed] [@@immediate64]

type float_reg = Float_reg of int [@@unboxed] [@@immediate64]

type func_id = Func_id of int [@@unboxed] [@@immediate64]

type prim_id = Prim_id of int [@@unboxed] [@@immediate64]

type t =
  (* load, move, constant pools and bridge tools *)
  | Load_int_imm of reg * int  (** dst, imm *)
  | Load_float_imm of float_reg * float  (** dst, imm *)
  | Load_const of reg * int  (** dst, constant_pool_index *)
  | Mov of reg * reg  (** dst, src *)
  | Mov_float of float_reg * float_reg  (** dst, src *)
  | Box_float of reg * float_reg  (** dst (GPR), src (FPR) *)
  | Unbox_float of float_reg * reg  (** dst (FPR), src (GPR) *)
  (* value casts between integers and floats with special cases for boxed floats *)
  | Cast_int_float of float_reg * reg  (** dst (FPR), src (GPR) *)
  | Cast_float_int of reg * float_reg  (** dst (GPR), src (FPR) *)
  | Cast_int_float_boxed of reg * reg  (** dst, src *)
  | Cast_float_boxed_int of reg * reg  (** dst, src *)
  (* integer arithmetic *)
  | Add_int of reg * reg * reg  (** dst, lhs, rhs *)
  | Add_int_imm of reg * reg * int  (** dst, src, imm *)
  | Sub_int of reg * reg * reg  (** dst, lhs, rhs *)
  | Rev_sub_int_imm of reg * reg * int  (** dst, src, imm *)
  | Mul_int of reg * reg * reg  (** dst, lhs, rhs *)
  | Mul_int_imm of reg * reg * int  (** dst, src, imm *)
  | Div_int of reg * reg * reg  (** dst, lhs, rhs *)
  | Rev_div_int_imm of reg * reg * int  (** dst, src, imm *)
  | Mod_int of reg * reg * reg  (** dst, lhs, rhs *)
  | Rev_mod_int_imm of reg * reg * int  (** dst, src, imm *)
  (* unboxed float arithmetic *)
  | Add_float of float_reg * float_reg * float_reg  (** dst, lhs, rhs *)
  | Add_float_imm of float_reg * float_reg * float  (** dst, src, imm *)
  | Sub_float of float_reg * float_reg * float_reg  (** dst, lhs, rhs *)
  | Sub_float_imm of float_reg * float_reg * float  (** dst, src, imm *)
  | Mul_float of float_reg * float_reg * float_reg  (** dst, lhs, rhs *)
  | Mul_float_imm of float_reg * float_reg * float  (** dst, src, imm *)
  | Div_float of float_reg * float_reg * float_reg  (** dst, lhs, rhs *)
  | Div_float_imm of float_reg * float_reg * float  (** dst, src, imm *)
  | Neg_float of float_reg * float_reg  (** dst, src *)
  (* integer comparison *)
  | Eq_int of reg * reg * reg  (** dst, lhs, rhs *)
  | Eq_int_imm of reg * reg * int  (** dst, src, imm *)
  | Ne_int of reg * reg * reg  (** dst, lhs, rhs *)
  | Ne_int_imm of reg * reg * int  (** dst, src, imm *)
  | Lt_int of reg * reg * reg  (** dst, lhs, rhs *)
  | Lt_int_imm of reg * reg * int  (** dst, src, imm *)
  | Rev_lt_int_imm of reg * reg * int  (** dst, src, imm *)
  | Le_int of reg * reg * reg  (** dst, lhs, rhs *)
  | Le_int_imm of reg * reg * int  (** dst, src, imm *)
  | Rev_le_int_imm of reg * reg * int  (** dst, src, imm *)
  (* unboxed float comparison *)
  | Eq_float of reg * float_reg * float_reg  (** dst, lhs, rhs *)
  | Ne_float of reg * float_reg * float_reg  (** dst, lhs, rhs *)
  | Lt_float of reg * float_reg * float_reg  (** dst, lhs, rhs *)
  | Le_float of reg * float_reg * float_reg  (** dst, lhs, rhs *)
  | Gt_float of reg * float_reg * float_reg  (** dst, lhs, rhs *)
  | Ge_float of reg * float_reg * float_reg  (** dst, lhs, rhs *)
  (* integer bitwise and shifts *)
  | And_int of reg * reg * reg  (** dst, lhs, rhs *)
  | And_int_imm of reg * reg * int  (** dst, src, imm *)
  | Or_int of reg * reg * reg  (** dst, lhs, rhs *)
  | Or_int_imm of reg * reg * int  (** dst, src, imm *)
  | Xor_int of reg * reg * reg  (** dst, lhs, rhs *)
  | Xor_int_imm of reg * reg * int  (** dst, src, imm *)
  | Lsl_int of reg * reg * reg  (** dst, lhs, rhs *)
  | Lsl_int_imm of reg * reg * int  (** dst, src, imm *)
  | Lsr_int of reg * reg * reg  (** dst, lhs, rhs *)
  | Lsr_int_imm of reg * reg * int  (** dst, src, imm *)
  | Asr_int of reg * reg * reg  (** dst, lhs, rhs *)
  | Asr_int_imm of reg * reg * int  (** dst, src, imm *)
  (* control flow and call layout *)
  | Jmp of int  (** offset *)
  | Jmp_table of reg * int  (** tag, table_size *)
  | Jmp_table_offset of int  (** offset *)
  | Jt of reg * int  (** cond, offset *)
  | Jf of reg * int  (** cond, offset *)
  | Call of reg * func_id * reg * int  (** dst, callee, args_base, nargs *)
  | Call_closure of reg * reg * reg * int  (** dst, callee, args_base, nargs *)
  | Call_prim of reg * prim_id * reg * int  (** dst, callee, args_base, nargs *)
  | Call_prim_managed of reg * prim_id * reg * int
      (** dst, callee, args_base, nargs *)
  | Tail_call of func_id * reg * int  (** callee, args_base, nargs *)
  | Tail_call_closure of reg * reg * int  (** callee, args_base, nargs *)
  | Ret of reg  (** src *)
  (* allocation and object creation *)
  | Alloc of reg * int  (** dst, nfields *)
  | Alloc_closure of reg * func_id * int  (** dst, callee, nfields *)
  | Alloc_array of reg * reg  (** dst, nfields_reg *)
  (* object property and closure metadata *)
  | Load_tag of reg * reg  (** dst, src *)
  | Store_tag of reg * int  (** base, tag *)
  | Load_upvar of reg * reg * int  (** dst, closure, i *)
  | Store_upvar of reg * reg * int  (** closure, src, i *)
  | Length of reg * reg  (** dst, src *)
  (* uniform memory and array access *)
  | Load_byte of reg * reg * reg  (** dst, base, i *)
  | Store_byte of reg * reg * reg  (** base, src, i *)
  | Load_field_int of reg * reg * int  (** dst, base, i *)
  | Load_field_float of float_reg * reg * int  (** dst (FPR), base (GPR), i *)
  | Load_field_ptr of reg * reg * int  (** dst, base, i *)
  | Load_array_int of reg * reg * reg  (** dst, base, i *)
  | Load_array_float of float_reg * reg * reg  (** dst (FPR), base (GPR), i *)
  | Load_array_ptr of reg * reg * reg  (** dst, base, i *)
  | Store_field_int of reg * reg * int  (** base, src, i *)
  | Store_field_float of reg * float_reg * int  (** base (GPR), src (FPR), i *)
  | Store_field_ptr of reg * reg * int  (** base, src, i  *)
  | Store_array_int of reg * reg * reg  (** base, src, i *)
  | Store_array_float of reg * float_reg * reg  (** base (GPR), src (FPR), i *)
  | Store_array_ptr of reg * reg * reg  (** base, src, i *)
    (* atomic operations (major heap) *)
  | Atomic_field_ptr_cas of reg * reg * reg * reg * int
      (** dst_success, base, expected_ptr, desired_ptr, i *)
  | Atomic_field_int_cas of reg * reg * reg * reg * int
      (** dst_success, base, expected_int, desired_int, i *)
  | Atomic_field_ptr_exch of reg * reg * reg * int
      (** dst_old_ptr, base, src_new_ptr, i *)
  | Atomic_field_int_exch of reg * reg * reg * int
      (** dst_old_int, base, src_new_int, i *)
  | Atomic_field_int_add of reg * reg * reg * int
      (** dst_old_int, base, src_increment_int, i *)
  | Atomic_array_ptr_cas of reg * reg * reg * reg * reg
      (** dst_success, base, expected_ptr, desired_ptr, index *)
  | Atomic_array_int_cas of reg * reg * reg * reg * reg
      (** dst_success, base, expected_int, desired_int, index *)
  | Atomic_array_ptr_exch of reg * reg * reg * reg
      (** dst_old_ptr, base, src_new_ptr, index *)
  | Atomic_array_int_exch of reg * reg * reg * reg
      (** dst_old_int, base, src_new_int, index *)
  | Atomic_array_int_add of reg * reg * reg * reg
      (** dst_old_int, base, src_increment_int, index *)
  | Fence
  | Domain_relax
  (* algebraic effects *)
  | Push_handler of int  (** handler_offset *)
  | Pop_handler
  | Perform of reg * reg  (** dst, effect_instance *)
  | Safepoint
  (* system operations *)
  | Nop
  | Halt
