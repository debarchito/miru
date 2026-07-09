let is_whitespace = function
  | ' ' | '\t' | '\n' | '\r' | ',' ->
      true
  | _ ->
      false

let is_digit = function '0' .. '9' -> true | _ -> false

let is_hex_digit = function
  | '0' .. '9' | 'a' .. 'f' | 'A' .. 'F' ->
      true
  | _ ->
      false

let is_oct_digit = function '0' .. '7' -> true | _ -> false

let is_bin_digit = function '0' .. '1' -> true | _ -> false

let is_symbol_start = function
  | 'a' .. 'z'
  | 'A' .. 'Z'
  | '_'
  | ':'
  | '='
  | '>'
  | '<'
  | '!'
  | '?'
  | '*'
  | '%'
  | '&'
  | '|'
  | '^'
  | '$'
  | '/'
  | '+'
  | '-'
  | '.' ->
      true
  | _ ->
      false

let is_delimiter c =
  is_whitespace c
  ||
  match c with
  | '(' | ')' | '[' | ']' | '{' | '}' | '\'' | '`' | '~' | '@' | '#' | ';' | '"'
    ->
      true
  | _ ->
      false

let skip_whitespace s = Stream.skip_while s is_whitespace

let hex_val = function
  | '0' .. '9' as c ->
      Char.code c - Char.code '0'
  | 'a' .. 'f' as c ->
      Char.code c - Char.code 'a' + 10
  | 'A' .. 'F' as c ->
      Char.code c - Char.code 'A' + 10
  | _ ->
      assert false

let read_escape s =
  let hex_digit () =
    let cap = Stream.capture s in
    match Stream.read s with
    | c when is_hex_digit c ->
        hex_val c
    | _ ->
        raise
          (Err.Reader_error
             ( Stream.captured_point_range s cap
             , Err.Message.InvalidHexEscape
             , "invalid hex escape" ) )
  in
  match Stream.read s with
  | 'n' ->
      '\n'
  | 't' ->
      '\t'
  | 'r' ->
      '\r'
  | '\\' ->
      '\\'
  | '"' ->
      '"'
  | '\'' ->
      '\''
  | 'x' ->
      let c1 = hex_digit () in
      let c2 = hex_digit () in
      Char.chr ((c1 * 16) + c2)
  | c ->
      c
  | exception Stream.End_of_input ->
      raise
        (Err.Reader_error
           ( Stream.current_point_range s
           , Err.Message.UnterminatedStringEscape
           , "unterminated string escape" ) )

let read_string_body s =
  let buf = Buffer.create 64 in
  let rec loop () =
    match Stream.read s with
    | '"' ->
        Form.String (Buffer.contents buf)
    | '\\' ->
        Buffer.add_char buf (read_escape s) ;
        loop ()
    | c ->
        Buffer.add_char buf c ; loop ()
    | exception Stream.End_of_input ->
        raise
          (Err.Reader_error
             ( Stream.current_point_range s
             , Err.Message.UnterminatedString
             , "unterminated string" ) )
  in
  loop ()

let read_number s first =
  let buf = Buffer.create 16 in
  Buffer.add_char buf first ;
  let prefix =
    if first = '0' then
      match Stream.peek s with
      | Some ('x' | 'X') ->
          ignore (Stream.read s) ;
          Some `Hex
      | Some ('o' | 'O') ->
          ignore (Stream.read s) ;
          Some `Oct
      | Some ('b' | 'B') ->
          ignore (Stream.read s) ;
          Some `Bin
      | _ ->
          None
    else None
  in
  match prefix with
  | Some `Hex ->
      let rec go () =
        match Stream.peek s with
        | Some c when is_hex_digit c ->
            Buffer.add_char buf (Stream.read s) ;
            go ()
        | _ ->
            Form.Int (Int64.of_string ("0x" ^ Buffer.contents buf))
      in
      go ()
  | Some `Oct ->
      let rec go () =
        match Stream.peek s with
        | Some c when is_oct_digit c ->
            Buffer.add_char buf (Stream.read s) ;
            go ()
        | _ ->
            Form.Int (Int64.of_string ("0o" ^ Buffer.contents buf))
      in
      go ()
  | Some `Bin ->
      let rec go () =
        match Stream.peek s with
        | Some c when is_bin_digit c ->
            Buffer.add_char buf (Stream.read s) ;
            go ()
        | _ ->
            Form.Int (Int64.of_string ("0b" ^ Buffer.contents buf))
      in
      go ()
  | None ->
      let rec read_int_part () =
        match Stream.peek s with
        | Some c when is_digit c ->
            Buffer.add_char buf (Stream.read s) ;
            read_int_part ()
        | _ ->
            ()
      in
      read_int_part () ;
      let has_dot =
        match Stream.peek s with
        | Some '.' -> (
          match Stream.peek_next s with Some c -> is_digit c | None -> false )
        | _ ->
            false
      in
      if not has_dot then Form.Int (Int64.of_string (Buffer.contents buf))
      else begin
        ignore (Stream.read s) ;
        Buffer.add_char buf '.' ;
        let rec read_frac () =
          match Stream.peek s with
          | Some c when is_digit c ->
              Buffer.add_char buf (Stream.read s) ;
              read_frac ()
          | _ ->
              ()
        in
        read_frac () ;
        let has_exp =
          match Stream.peek s with Some ('e' | 'E') -> true | _ -> false
        in
        if has_exp then begin
          ignore (Stream.read s) ;
          Buffer.add_char buf 'E' ;
          ( match Stream.peek s with
          | Some ('+' | '-') ->
              Buffer.add_char buf (Stream.read s)
          | _ ->
              () ) ;
          let rec read_exp () =
            match Stream.peek s with
            | Some c when is_digit c ->
                Buffer.add_char buf (Stream.read s) ;
                read_exp ()
            | _ ->
                ()
          in
          read_exp ()
        end ;
        Form.Float (float_of_string (Buffer.contents buf))
      end

let read_symbol_name s first =
  let buf = Buffer.create 16 in
  Buffer.add_char buf first ;
  let rec go () =
    match Stream.peek s with
    | Some c when not (is_delimiter c) ->
        Buffer.add_char buf (Stream.read s) ;
        go ()
    | _ ->
        Buffer.contents buf
  in
  go ()

let read_symbol s first =
  match read_symbol_name s first with
  | "true" ->
      Form.Bool true
  | "false" ->
      Form.Bool false
  | "unit" ->
      Form.Unit
  | name ->
      Form.Symbol name

let read_token s first =
  let peek_digit =
    match Stream.peek s with Some c -> is_digit c | None -> false
  in
  if is_digit first then read_number s first
  else if (first = '-' || first = '+') && peek_digit then read_number s first
  else if first = '.' && peek_digit then read_number s first
  else if is_symbol_start first then read_symbol s first
  else
    raise
      (Err.Reader_error
         ( Stream.current_point_range s
         , Err.Message.UnexpectedCharacter
         , Printf.sprintf "unexpected character '%c'" first ) )
