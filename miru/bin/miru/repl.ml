let run () =
  let pp = Pp.pp_ast in
  let rec loop () =
    Printf.printf "\nmiru> %!";
    match input_line stdin with
    | line ->
        (try
           let forms = Reader.Core.read_all line in
           List.iter (fun f -> Format.printf "%a\n%!" pp f) forms
         with e -> Printf.eprintf "Error: %s\n%!" (Printexc.to_string e));
        loop ()
    | exception End_of_file -> print_newline ()
  in
  Printf.eprintf "Miru REPL. Press Ctrl+D to exit.\n%!";
  loop ()
