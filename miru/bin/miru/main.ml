let () =
  match Sys.argv with
  | [| _; filename |] ->
      let ch = open_in filename in
      let content = really_input_string ch (in_channel_length ch) in
      close_in ch;
      let forms = Reader.Core.read_all content in
      List.iter (fun f -> Format.printf "%a\n%!" Pp.pp_ast f) forms
  | _ ->
      if Unix.isatty Unix.stdin then Repl.run ()
      else begin
        let buf = Buffer.create 4096 in
        (try
           while true do
             Buffer.add_channel buf stdin 4096
           done
         with End_of_file -> ());
        let content = Buffer.contents buf in
        let forms = Reader.Core.read_all content in
        List.iter (fun f -> Format.printf "%a\n%!" Pp.pp_ast f) forms
      end
