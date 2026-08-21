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

let raise_error span msg detail =
  raise (Err.Reader_error (span, msg, detail))

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
        raise_error (Stream.captured_point_range s cap) Err.Message.InvalidHexEscape
          "invalid hex escape"
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
      raise_error (Stream.current_point_range s) Err.Message.UnterminatedStringEscape
        "unterminated string escape"

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
        raise_error (Stream.current_point_range s) Err.Message.UnterminatedString
          "unterminated string"
  in
  loop ()

let read_digits pred buf s =
  let rec go () =
    match Stream.peek s with
    | Some c when pred c ->
        Buffer.add_char buf (Stream.read s) ;
        go ()
    | _ ->
        ()
  in
  go ()

let read_int_suffix s =
  match Stream.peek s with
  | Some ('i' | 'u') as c ->
      let signed = c = Some 'i' in
      let _ = Stream.read s in
      let buf = Buffer.create 8 in
      read_digits is_digit buf s ;
      let contents = Buffer.contents buf in
      if String.length contents = 0 then
        raise_error (Stream.current_point_range s) Err.Message.InvalidFieldKey
          "expected digits after integer suffix" ;
      let bits = int_of_string contents in
      Some {Form.signed; bits}
  | _ ->
      None

let read_float_suffix s =
  match Stream.peek s with
  | Some 'f' ->
      let _ = Stream.read s in
      let buf = Buffer.create 3 in
      read_digits is_digit buf s ;
      let contents = Buffer.contents buf in
      if String.length contents = 0 then None
      else Some contents
  | _ ->
      None

let float_precision_of_string = function
  | "16" ->
      Some `F16
  | "32" ->
      Some `F32
  | "64" ->
      Some `F64
  | "128" ->
      Some `F128
  | _ ->
      None

let make_float prec s =
  match prec with
  | `F16 ->
      Form.Float (Floatml.AnyFloat.f16 (Floatml.F16.of_string s), 16)
  | `F32 ->
      Form.Float (Floatml.AnyFloat.f32 (Floatml.F32.of_string s), 32)
  | `F64 ->
      Form.Float (Floatml.AnyFloat.f64 (Floatml.F64.of_string s), 64)
  | `F128 ->
      Form.Float (Floatml.AnyFloat.f128 (Floatml.F128.of_string s), 128)

let make_int buf suffix =
  let z = Z.of_string (Buffer.contents buf) in
  Form.Int (z, suffix)

let read_int_with_suffix buf s =
  make_int buf (Option.value ~default:Form.default_int_suffix (read_int_suffix s))

let read_number s first =
  let buf = Buffer.create 16 in
  Buffer.add_char buf first ;
  let prefix =
    if first = '0' then
      match Stream.peek s with
      | Some ('x' | 'X') ->
          Buffer.add_char buf (Stream.read s) ;
          `Hex
      | Some ('o' | 'O') ->
          ignore (Stream.read s) ;
          `Oct
      | Some ('b' | 'B') ->
          ignore (Stream.read s) ;
          `Bin
      | _ ->
          `None
    else `None
  in
  match prefix with
  | `Hex ->
      read_digits is_hex_digit buf s ;
      read_int_with_suffix buf s
  | `Oct ->
      Buffer.add_string buf "o" ;
      read_digits is_oct_digit buf s ;
      read_int_with_suffix buf s
  | `Bin ->
      Buffer.add_string buf "b" ;
      read_digits is_bin_digit buf s ;
      read_int_with_suffix buf s
  | `None ->
      read_digits is_digit buf s ;
      let has_dot =
        match Stream.peek s with
        | Some '.' -> (
          match Stream.peek_next s with
          | Some c ->
              is_digit c || is_delimiter c || is_symbol_start c
          | None ->
              true )
        | _ ->
            false
      in
      if not has_dot then begin
        ( match Stream.peek s with
        | Some 'f' ->
            raise_error (Stream.current_point_range s) Err.Message.InvalidFieldKey
              "float suffix on integer (missing '.' for float)"
        | _ ->
            () ) ;
        read_int_with_suffix buf s
      end
      else begin
        ignore (Stream.read s) ;
        Buffer.add_char buf '.' ;
        read_digits is_digit buf s ;
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
          read_digits is_digit buf s
        end ;
        match Stream.peek s with
        | Some 'i' | Some 'u' ->
            raise_error (Stream.current_point_range s) Err.Message.InvalidFieldKey
              "integer suffix on float (remove suffix or use 'f' suffix)"
        | _ -> (
          match read_float_suffix s with
          | Some prec -> (
            match float_precision_of_string prec with
            | Some p ->
                make_float p (Buffer.contents buf)
            | None ->
                raise_error (Stream.current_point_range s)
                  Err.Message.InvalidFieldKey
                  (Printf.sprintf "invalid float precision: f%s" prec) )
          | None ->
              make_float `F64 (Buffer.contents buf) )
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
  else if is_symbol_start first then read_symbol s first
  else
    raise_error (Stream.current_point_range s) Err.Message.UnexpectedCharacter
      (Printf.sprintf "unexpected character '%c'" first)
