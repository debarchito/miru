open Value

type t = {
  mutable pc : int;
  regs : word array;
  instrs : Instr.t array;
  caller : t option;
  ret_reg : Instr.reg;
}

let create instrs caller ret_reg =
  { pc = 0; regs = Array.make 256 1L; instrs; caller; ret_reg }
