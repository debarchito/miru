open Machine_stubs.Machine

let () =
  let input = 5L in
  let result = square input in
  Printf.printf "square(%Ld) = %Ld\n" input result
