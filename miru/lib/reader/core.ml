exception End_of_input
exception Discard

module Stream = struct
  type t = {
    input : string;
    len : int;
    mutable pos : int;
    mutable line : int;
    mutable col : int;
    mutable sol : int;
    source : Span.source option;
  }

  let from_string ?source s =
    {
      input = s;
      len = String.length s;
      pos = 0;
      line = 1;
      col = 0;
      sol = 0;
      source;
    }

  let peek s = if s.pos >= s.len then None else Some (String.get s.input s.pos)

  let peek_next s =
    let p = s.pos + 1 in
    if p >= s.len then None else Some (String.get s.input p)

  let read s =
    if s.pos >= s.len then raise End_of_input
    else
      let c = String.get s.input s.pos in
      s.pos <- s.pos + 1;
      if c = '\n' then (
        s.line <- s.line + 1;
        s.col <- 0;
        s.sol <- s.pos)
      else s.col <- s.col + 1;
      c

  let pos s = (s.pos, s.line, s.col)

  let capture s =
    (s.pos, s.line, s.col, s.sol)

  let point_range s ~offset ~line_num ~start_of_line =
    match s.source with
    | Some src ->
        let p : Asai.Range.position =
          { source = src; offset; line_num; start_of_line }
        in
        Some (Asai.Range.make (p, p))
    | None -> None

  let current_point_range s = point_range s ~offset:s.pos ~line_num:s.line ~start_of_line:s.sol

  let captured_point_range s (pos, _, _, sol) =
    point_range s ~offset:pos ~line_num:s.line ~start_of_line:sol

  let skip_while s f =
    let rec loop () =
      match peek s with
      | Some c when f c ->
          read s |> ignore;
          loop ()
      | _ -> ()
    in
    loop ()

  let skip_to_eol s =
    let rec loop () =
      match peek s with
      | None -> ()
      | Some '\n' -> ignore (read s)
      | Some _ ->
          ignore (read s);
          loop ()
    in
    loop ()
end

type reader_fn = readtable -> Stream.t -> char -> Form.t

and readtable = {
  macro : (char, reader_fn) Hashtbl.t;
  dispatch : (char, reader_fn) Hashtbl.t;
}

let is_whitespace = function
  | ' ' | '\t' | '\n' | '\r' | ',' -> true
  | _ -> false

let is_digit = function '0' .. '9' -> true | _ -> false

let is_hex_digit = function
  | '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' -> true
  | _ -> false

let is_oct_digit = function '0' .. '7' -> true | _ -> false
let is_bin_digit = function '0' .. '1' -> true | _ -> false

let is_symbol_start = function
  | 'a' .. 'z'
  | 'A' .. 'Z'
  | '_' | ':' | '=' | '>' | '<' | '!' | '?' | '*' | '%' | '&' | '|' | '^' | '$'
  | '/' | '+' | '-' | '.' ->
      true
  | _ -> false

let is_symbol_rest c = is_symbol_start c || is_digit c

let is_delimiter c =
  is_whitespace c
  ||
  match c with
  | '(' | ')' | '[' | ']' | '{' | '}' | '\'' | '`' | '~' | '@' | '#' | ';' | '"'
    ->
      true
  | _ -> false

let skip_whitespace s = Stream.skip_while s is_whitespace

let hex_val c =
  match c with
  | '0' .. '9' -> Char.code c - Char.code '0'
  | 'a' .. 'f' -> Char.code c - Char.code 'a' + 10
  | 'A' .. 'F' -> Char.code c - Char.code 'A' + 10
  | _ -> assert false

let read_escape s =
  match Stream.read s with
  | 'n' -> '\n'
  | 't' -> '\t'
  | 'r' -> '\r'
  | '\\' -> '\\'
  | '"' -> '"'
  | '\'' -> '\''
  | 'x' ->
      let c1 =
        let cap = Stream.capture s in
        match Stream.read s with
        | c when is_hex_digit c -> hex_val c
        | _ ->
            raise
              (Err.Reader_error
                 ( Stream.captured_point_range s cap,
                   Err.Message.InvalidHexEscape,
                   "invalid hex escape" ))
      in
      let c2 =
        let cap = Stream.capture s in
        match Stream.read s with
        | c when is_hex_digit c -> hex_val c
        | _ ->
            raise
              (Err.Reader_error
                 ( Stream.captured_point_range s cap,
                   Err.Message.InvalidHexEscape,
                   "invalid hex escape" ))
      in
      Char.chr ((c1 * 16) + c2)
  | c -> c
  | exception End_of_input ->
      raise
        (Err.Reader_error
           ( Stream.current_point_range s,
             Err.Message.UnterminatedStringEscape,
             "unterminated string escape" ))

let read_string_body s =
  let buf = Buffer.create 64 in
  let rec loop () =
    match Stream.read s with
    | '"' -> Form.String (Buffer.contents buf)
    | '\\' ->
        Buffer.add_char buf (read_escape s);
        loop ()
    | c ->
        Buffer.add_char buf c;
        loop ()
    | exception End_of_input ->
        raise
          (Err.Reader_error
             ( Stream.current_point_range s,
               Err.Message.UnterminatedString,
               "unterminated string" ))
  in
  loop ()

let read_number s first =
  let buf = Buffer.create 16 in
  Buffer.add_char buf first;

  let prefix =
    if first = '0' then
      match Stream.peek s with
      | Some ('x' | 'X') ->
          Stream.read s |> ignore;
          Some `Hex
      | Some ('o' | 'O') ->
          Stream.read s |> ignore;
          Some `Oct
      | Some ('b' | 'B') ->
          Stream.read s |> ignore;
          Some `Bin
      | _ -> None
    else None
  in

  match prefix with
  | Some `Hex ->
      let rec go () =
        match Stream.peek s with
        | Some c when is_hex_digit c ->
            Buffer.add_char buf (Stream.read s);
            go ()
        | _ -> Form.Int (Int64.of_string ("0x" ^ Buffer.contents buf))
      in
      go ()
  | Some `Oct ->
      let rec go () =
        match Stream.peek s with
        | Some c when is_oct_digit c ->
            Buffer.add_char buf (Stream.read s);
            go ()
        | _ -> Form.Int (Int64.of_string ("0o" ^ Buffer.contents buf))
      in
      go ()
  | Some `Bin ->
      let rec go () =
        match Stream.peek s with
        | Some c when is_bin_digit c ->
            Buffer.add_char buf (Stream.read s);
            go ()
        | _ -> Form.Int (Int64.of_string ("0b" ^ Buffer.contents buf))
      in
      go ()
  | None ->
      let rec read_int_part () =
        match Stream.peek s with
        | Some c when is_digit c ->
            Buffer.add_char buf (Stream.read s);
            read_int_part ()
        | _ -> ()
      in
      read_int_part ();
      let has_dot =
        match Stream.peek s with
        | Some '.' -> (
            match Stream.peek_next s with
            | Some c when is_digit c -> true
            | _ -> false)
        | _ -> false
      in
      if not has_dot then Form.Int (Int64.of_string (Buffer.contents buf))
      else begin
        Stream.read s |> ignore;
        Buffer.add_char buf '.';
        let rec read_frac () =
          match Stream.peek s with
          | Some c when is_digit c ->
              Buffer.add_char buf (Stream.read s);
              read_frac ()
          | _ -> ()
        in
        read_frac ();
        let has_exp =
          match Stream.peek s with Some ('e' | 'E') -> true | _ -> false
        in
        if has_exp then begin
          Stream.read s |> ignore;
          Buffer.add_char buf 'E';
          (match Stream.peek s with
          | Some ('+' | '-') -> Buffer.add_char buf (Stream.read s)
          | _ -> ());
          let rec read_exp () =
            match Stream.peek s with
            | Some c when is_digit c ->
                Buffer.add_char buf (Stream.read s);
                read_exp ()
            | _ -> ()
          in
          read_exp ()
        end;
        Form.Float (float_of_string (Buffer.contents buf))
      end

let read_symbol_name s first =
  let buf = Buffer.create 16 in
  Buffer.add_char buf first;
  let rec go () =
    match Stream.peek s with
    | Some c when not (is_delimiter c) ->
        Buffer.add_char buf (Stream.read s);
        go ()
    | _ -> Buffer.contents buf
  in
  go ()

let read_symbol s first =
  let name = read_symbol_name s first in
  match name with
  | "true" -> Form.Bool true
  | "false" -> Form.Bool false
  | "unit" -> Form.Unit
  | _ -> Form.Symbol name

let read_token s first =
  let peek_digit =
    match Stream.peek s with Some c when is_digit c -> true | _ -> false
  in
  if is_digit first then read_number s first
  else if (first = '-' || first = '+') && peek_digit then read_number s first
  else if first = '.' && peek_digit then read_number s first
  else if is_symbol_start first then read_symbol s first
  else
    raise
      (Err.Reader_error
         ( Stream.current_point_range s,
           Err.Message.UnexpectedCharacter,
           Printf.sprintf "unexpected character '%c'" first ))

let rec read_form rt s =
  skip_whitespace s;
  match Stream.peek s with
  | None -> raise End_of_input
  | Some ';' ->
      Stream.read s |> ignore;
      Stream.skip_to_eol s;
      read_form rt s
  | Some c ->
      begin match Hashtbl.find_opt rt.macro c with
      | Some fn ->
          Stream.read s |> ignore;
          fn rt s c
      | None ->
          Stream.read s |> ignore;
          read_token s c
      end

and read_forms_until rt s close =
  skip_whitespace s;
  match Stream.peek s with
  | None ->
      raise
        (Err.Reader_error
           ( Stream.current_point_range s,
             Err.Message.UnexpectedEOF,
             Printf.sprintf "unexpected EOF while reading form (expecting '%c')"
               close ))
  | Some c when c = close ->
      Stream.read s |> ignore;
      []
  | _ -> (
      try
        let f = read_form rt s in
        f :: read_forms_until rt s close
      with Discard -> read_forms_until rt s close)

and read_quote_macro rt s _ = Form.Quote (read_form rt s)
and read_quasiquote_macro rt s _ = Form.Quasiquote (read_form rt s)

and read_unquote_macro rt s _ =
  match Stream.peek s with
  | Some '@' ->
      Stream.read s |> ignore;
      Form.Splice (read_form rt s)
  | _ -> Form.Unquote (read_form rt s)

and read_deref_macro rt s _ = Form.List [ Form.Symbol "deref"; read_form rt s ]

and read_comment_macro rt s _ =
  Stream.skip_to_eol s;
  read_form rt s

and read_string_macro rt s _ = read_string_body s

and read_list_macro rt s _ =
  let forms = read_forms_until rt s ')' in
  read_type_form forms

and read_type_form =
  let is_positional = function
    | (Form.Field (Form.Int _), _) :: _ -> true
    | _ -> false
  in
  let rec wrap_type = function
    | Form.RecordExpression pairs ->
        Form.RecordExpression (List.map (fun (k, v) -> (k, wrap_type v)) pairs)
    | Form.List items -> (
        match List.map wrap_type items with
        | [] -> Form.Type Form.Unit
        | [ x ] -> x
        | base :: rest ->
            List.fold_left
              (fun acc t ->
                match t with
                | Form.Type (Form.Symbol s) -> Form.TypeApplication (s, acc)
                | _ -> Form.Type (Form.List items))
              base rest)
    | other -> Form.Type other
  in
  function
  | [ Form.Symbol "type"; Form.Symbol name; Form.RecordExpression fields ] ->
      if is_positional fields then
        Form.AbstractType
          ( name,
            Form.RecordExpression
              (List.map (fun (k, v) -> (k, wrap_type v)) fields) )
      else
        Form.Record
          ( name,
            Form.RecordExpression
              (List.map (fun (k, v) -> (k, wrap_type v)) fields) )
  | Form.Symbol "type" :: Form.Symbol name :: constructors -> (
      match constructors with
      | [ single ] -> (
          match single with
          | Form.List (Form.Symbol ctor :: payload) ->
              let payload_type =
                match payload with
                | [] -> None
                | [ f ] -> Some (wrap_type f)
                | fs -> Some (wrap_type (Form.List fs))
              in
              Form.Variant (name, [ Form.Constructor (ctor, payload_type) ])
          | _ -> Form.AbstractType (name, wrap_type single))
      | _ ->
          let rec process_ctors acc = function
            | Form.Symbol ctor :: rest -> (
                match rest with
                | [] -> process_ctors (Form.Constructor (ctor, None) :: acc) []
                | Form.Symbol _ :: _ ->
                    process_ctors (Form.Constructor (ctor, None) :: acc) rest
                | payload :: rest' ->
                    process_ctors
                      (Form.Constructor (ctor, Some (wrap_type payload)) :: acc)
                      rest')
            | Form.List (Form.Symbol ctor :: payload) :: rest ->
                let payload_type =
                  match payload with
                  | [] -> None
                  | [ f ] -> Some (wrap_type f)
                  | fs -> Some (wrap_type (Form.List fs))
                in
                process_ctors
                  (Form.Constructor (ctor, payload_type) :: acc)
                  rest
            | _ :: rest -> process_ctors acc rest
            | [] -> List.rev acc
          in
          Form.Variant (name, process_ctors [] constructors))
  | forms -> Form.List forms

and read_tuple_macro rt s _ =
  let items = read_forms_until rt s ']' in
  Form.RecordExpression
    (List.mapi
       (fun i v -> (Form.Field (Form.Int (Int64.of_int i)), v))
       items)

and read_struct_macro rt s _ =
  (* Read body forms with captured stream positions so error spans point to
     the offending key, not past the closing '}'. *)
  let rec read_forms acc =
    skip_whitespace s;
    match Stream.peek s with
    | None ->
        raise
          (Err.Reader_error
             ( Stream.current_point_range s,
               Err.Message.UnexpectedEOF,
               "unexpected EOF while reading struct body (expecting '}')" ))
    | Some '}' ->
        Stream.read s |> ignore;
        List.rev acc
    | Some _ ->
        let cap = Stream.capture s in
        let span = Stream.captured_point_range s cap in
        (match (try Some (read_form rt s) with Discard -> None) with
        | None -> read_forms acc
        | Some f -> read_forms ((span, f) :: acc))
  in
  let rec resolve_mutable = function
    | (_, Form.Symbol "mutable") :: (span, Form.Symbol x) :: rest ->
        (span, Form.MutableField x) :: resolve_mutable rest
    | (_, Form.Symbol "mutable") :: (span, Form.Int k) :: rest ->
        (span, Form.MutableField (Int64.to_string k)) :: resolve_mutable rest
    | (_, Form.Symbol "mutable") :: (span, Form.String _) :: _ ->
        raise
          (Err.Reader_error
             ( span,
               Err.Message.InvalidMutableFieldKey,
               "mutable field keys must be symbols or integers, got string" ))
    | (_, Form.Symbol "mutable") :: (span, _) :: _ ->
        raise
          (Err.Reader_error
             ( span,
               Err.Message.InvalidMutableFieldKey,
               "mutable field keys must be symbols or integers, got other" ))
    | (_, Form.Symbol "mutable") :: [] -> []
    | x :: rest -> x :: resolve_mutable rest
    | [] -> []
  in
  let forms = resolve_mutable (read_forms []) in
  let rec pair acc = function
    | [] -> Form.RecordExpression (List.rev acc)
    | [ (_, Form.Symbol "mutable") ] -> Form.RecordExpression (List.rev acc)
    | [ (span, _) ] ->
        raise
          (Err.Reader_error
             ( span,
               Err.Message.OddStructBody,
               "struct body has odd number of forms" ))
    | (_, Form.Symbol k) :: (_, v) :: rest ->
        pair ((Form.Field (Form.Symbol k), v) :: acc) rest
    | (_, Form.Int k) :: (_, v) :: rest ->
        pair ((Form.Field (Form.Int k), v) :: acc) rest
    | (_, (Form.MutableField _ as k)) :: (_, v) :: rest ->
        pair ((k, v) :: acc) rest
    | (span, _) :: _ :: _ ->
        raise
          (Err.Reader_error
             ( span,
               Err.Message.InvalidFieldKey,
               "struct field keys must be symbols or integers" ))
  in
  pair [] forms

and read_close_error s c =
  raise
    (Err.Reader_error
       ( Stream.current_point_range s,
         Err.Message.UnexpectedClose,
         Printf.sprintf "unexpected '%c'" c ))

and read_dispatch_macro rt s _ =
  match Stream.read s with
  | c ->
      begin match Hashtbl.find_opt rt.dispatch c with
      | Some fn -> fn rt s c
      | None ->
          raise
            (Err.Reader_error
               ( Stream.current_point_range s,
                 Err.Message.UndefinedDispatch,
                 Printf.sprintf "undefined # dispatch '%c'" c ))
      end

and read_fn_dispatch rt s _ = Form.Fn (read_forms_until rt s ')')

and read_array_dispatch rt s _ =
  let forms = read_forms_until rt s ']' in
  Form.List (Form.Symbol "array" :: forms)

and read_set_dispatch rt s _ =
  let forms = read_forms_until rt s '}' in
  Form.List (Form.Symbol "set" :: forms)

and read_discard_dispatch rt s _ =
  ignore (read_form rt s);
  raise Discard

let create () = { macro = Hashtbl.create 16; dispatch = Hashtbl.create 16 }
let set_macro rt c fn = Hashtbl.replace rt.macro c fn
let set_dispatch rt c fn = Hashtbl.replace rt.dispatch c fn

let copy rt =
  { macro = Hashtbl.copy rt.macro; dispatch = Hashtbl.copy rt.dispatch }

let default () =
  let rt = create () in
  set_macro rt '\'' read_quote_macro;
  set_macro rt '`' read_quasiquote_macro;
  set_macro rt '~' read_unquote_macro;
  set_macro rt '@' read_deref_macro;
  set_macro rt '(' read_list_macro;
  set_macro rt '[' read_tuple_macro;
  set_macro rt '{' read_struct_macro;
  set_macro rt ')' (fun _ s c -> read_close_error s c);
  set_macro rt ']' (fun _ s c -> read_close_error s c);
  set_macro rt '}' (fun _ s c -> read_close_error s c);
  set_macro rt '"' read_string_macro;
  set_macro rt ';' read_comment_macro;
  set_macro rt '#' read_dispatch_macro;
  set_dispatch rt '(' read_fn_dispatch;
  set_dispatch rt '[' read_array_dispatch;
  set_dispatch rt '{' read_set_dispatch;
  set_dispatch rt '_' read_discard_dispatch;
  rt

let read_all ?(rt = default ()) input =
  let s = Stream.from_string input in
  let forms = ref [] in
  (try
     while true do
       try forms := read_form rt s :: !forms with Discard -> ()
     done
   with End_of_input -> ());
  List.rev !forms

let read_all_reported ?(rt = default ()) ~title input =
  let source = Span.source_of_string ~source_title:title input in
  let s = Stream.from_string ~source input in
  let module Term = Asai.Tty.Make (Err.Message) in
  Err.run
    ~emit:Term.display
    ~fatal:(fun d -> Term.display d; exit 1)
    @@ fun () ->
    let forms = ref [] in
    (try
       while true do
         try forms := read_form rt s :: !forms with Discard -> ()
       done
     with End_of_input -> ()
     | Err.Reader_error (span_opt, msg, detail) ->
         Err.fatal ?loc:span_opt ~severity:Asai.Diagnostic.Error msg detail);
    List.rev !forms
