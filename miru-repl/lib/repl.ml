open Terminal

let history_file =
  let home = try Sys.getenv "HOME" with Not_found -> "." in
  home ^ "/.miru_history"

let history_max = 1000

type history = {
  mutable entries : string list;
  mutable index : int;
  mutable saved : string;
}

let load_history () =
  try
    let ch = open_in history_file in
    let lines = ref [] in
    (try
       while true do
         lines := input_line ch :: !lines
       done
     with End_of_file -> ());
    close_in ch;
    { entries = List.rev !lines; index = -1; saved = "" }
  with _ -> { entries = []; index = -1; saved = "" }

let save_history h =
  try
    let ch = open_out history_file in
    List.iter
      (fun l ->
        output_string ch l;
        output_char ch '\n')
      (List.rev h.entries);
    close_out ch
  with _ -> ()

let add_history h line =
  if line <> "" then begin
    let entries =
      if List.length h.entries >= history_max then
        List.rev (List.tl (List.rev h.entries))
      else h.entries
    in
    h.entries <- line :: entries
  end;
  h.index <- -1;
  h.saved <- ""

let is_balanced s =
  let level = ref 0 in
  let bracket = ref 0 in
  let brace = ref 0 in
  String.iter
    (function
      | '(' -> incr level
      | ')' -> decr level
      | '[' -> incr bracket
      | ']' -> decr bracket
      | '{' -> incr brace
      | '}' -> decr brace
      | _ -> ())
    s;
  !level = 0 && !bracket = 0 && !brace = 0

let read_line ~prompt ~prompt_len history =
  let buf = Buffer.create 128 in
  let pos = ref 0 in
  let redraw () =
    write "\r";
    write clear_to_eos;
    write prompt;
    write (Buffer.contents buf);
    write (move_to_col (prompt_len + !pos + 1))
  in
  let replace s =
    Buffer.clear buf;
    Buffer.add_string buf s;
    pos := String.length s;
    redraw ()
  in
  redraw ();
  let rec loop () =
    match read_key () with
    | Char c ->
        let s = Buffer.contents buf in
        let pre = String.sub s 0 !pos in
        let post = String.sub s !pos (String.length s - !pos) in
        Buffer.clear buf;
        Buffer.add_string buf pre;
        Buffer.add_char buf c;
        Buffer.add_string buf post;
        incr pos;
        redraw ();
        loop ()
    | Enter -> Buffer.contents buf
    | Backspace ->
        if !pos > 0 then begin
          let s = Buffer.contents buf in
          let pre = String.sub s 0 (!pos - 1) in
          let post = String.sub s !pos (String.length s - !pos) in
          Buffer.clear buf;
          Buffer.add_string buf pre;
          Buffer.add_string buf post;
          decr pos;
          redraw ()
        end;
        loop ()
    | Delete ->
        if !pos < Buffer.length buf then begin
          let s = Buffer.contents buf in
          let pre = String.sub s 0 !pos in
          let post = String.sub s (!pos + 1) (String.length s - !pos - 1) in
          Buffer.clear buf;
          Buffer.add_string buf pre;
          Buffer.add_string buf post;
          redraw ()
        end;
        loop ()
    | Left ->
        if !pos > 0 then decr pos;
        redraw ();
        loop ()
    | Right ->
        if !pos < Buffer.length buf then incr pos;
        redraw ();
        loop ()
    | Home ->
        pos := 0;
        redraw ();
        loop ()
    | End ->
        pos := Buffer.length buf;
        redraw ();
        loop ()
    | Up ->
        let next = history.index + 1 in
        if next < List.length history.entries then begin
          if history.index = -1 then history.saved <- Buffer.contents buf;
          history.index <- next;
          replace (List.nth history.entries next)
        end;
        loop ()
    | Down ->
        if history.index > 0 then begin
          history.index <- history.index - 1;
          replace (List.nth history.entries history.index)
        end
        else if history.index = 0 then begin
          history.index <- -1;
          replace history.saved
        end;
        loop ()
    | Ctrl 'C' -> raise Exit
    | Ctrl 'D' -> if Buffer.length buf = 0 then raise End_of_file else loop ()
    | _ -> loop ()
  in
  match loop () with
  | s -> s
  | exception End_of_file -> raise End_of_file
  | exception Exit -> raise Exit

let indent_of s =
  let depth = ref 0 in
  String.iter (function '(' -> incr depth | ')' -> decr depth | _ -> ()) s;
  if !depth <= 0 then 0 else 6 + ((!depth - 1) * 2)

let display_error (span_opt, msg, detail) =
  let module Term = Asai.Tty.Make (Reader.Err.Message) in
  let d = Asai.Diagnostic.make ?loc:span_opt Asai.Diagnostic.Error msg detail in
  Term.display d

let run () =
  let pp = Reader.Pp.pp_ast in
  if not (Unix.isatty Unix.stdin) then begin
    let buf = Buffer.create 4096 in
    (try
       while true do
         Buffer.add_channel buf stdin 4096
       done
     with End_of_file -> ());
    let content = Buffer.contents buf in
    let forms = Reader.Core.read_all_reported ~title:"stdin" content in
    List.iter (fun f -> Format.printf "%a\n\n%!" pp f) forms
  end
  else begin
    let history = load_history () in
    enter_raw ();
    (try
       let rec loop acc =
         let is_cont = acc <> "" in
         let indent = if is_cont then indent_of acc else 0 in
         let prompt_str =
           if is_cont then (
             let buf = Buffer.create 16 in
             Buffer.add_string buf "> ";
             for _ = 1 to indent do
               Buffer.add_char buf ' '
             done;
             Buffer.contents buf)
           else "miru> "
         in
         let prompt = green ^ prompt_str ^ reset in
         let prompt_len = String.length prompt_str in
         let line =
           try read_line ~prompt ~prompt_len history with Exit -> raise Exit
         in
         write "\n";
         let full = if is_cont then acc ^ "\n" ^ line else line in
         if is_balanced full then begin
           add_history history full;
           (try
              let forms = Reader.Core.read_all full in
              List.iter (fun f -> Format.printf "%a\n%!" pp f) forms
            with Reader.Err.Reader_error (span_opt, msg, detail) ->
              display_error (span_opt, msg, detail);
              write "\n");
           write "\n";
           loop ""
         end
         else loop full
       in
       loop ""
     with End_of_file | Exit -> write "\n");
    save_history history;
    leave_raw ()
  end
