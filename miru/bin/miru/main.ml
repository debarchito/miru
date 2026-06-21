let () =
  let content =
    match Sys.argv with
    | [| _; filename |] ->
        let ch = open_in filename in
        let c = really_input_string ch (in_channel_length ch) in
        close_in ch;
        c
    | _ ->
        let buf = Buffer.create 4096 in
        (try
           while true do
             Buffer.add_channel buf stdin 4096
           done
         with End_of_file -> ());
        Buffer.contents buf
  in
  let title = match Sys.argv with [| _; f |] -> f | _ -> "<stdin>" in
  let forms = Reader.Core.read_all_reported ~title content in
  List.iter (fun f -> Format.printf "%a\n%!" Reader.Pp.pp_ast f) forms
