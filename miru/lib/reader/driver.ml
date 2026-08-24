let rec read_form rt s =
  Lexer.skip_whitespace s ;
  match Stream.peek s with
  | None ->
      raise Stream.End_of_input
  | Some ';' ->
      ignore (Stream.read s) ;
      Stream.skip_to_eol s ;
      read_form rt s
  | Some c -> (
    match Readtable.find_macro rt c with
    | Some fn ->
        ignore (Stream.read s) ;
        fn rt s c
    | None ->
        ignore (Stream.read s) ;
        Lexer.read_token s c )

and read_forms_until rt s close =
  Lexer.skip_whitespace s ;
  match Stream.peek s with
  | None ->
      Err.fatal
        ?loc:(Stream.current_eof_range s)
        Err.Message.UnexpectedEOF
        ~extra_remarks:
          [Err.hint "add a closing '%c' to match the opening delimiter" close]
        (Printf.sprintf "unexpected end of input while reading a '%c' form"
           close )
  | Some c when c = close ->
      ignore (Stream.read s) ;
      []
  | _ -> (
    match read_form rt s with
    | Form.Intermediate_empty ->
        read_forms_until rt s close
    | f ->
        f :: read_forms_until rt s close )

and read_deref_macro rt s _ =
  match read_form rt s with
  | Form.Intermediate_empty ->
      Form.Intermediate_empty
  | f ->
      Form.Call [Form.Symbol "deref"; f]

and read_comment_macro rt s _ = Stream.skip_to_eol s ; read_form rt s

and read_string_macro _rt s _ = Lexer.read_string_body s

and read_list_macro rt s _ = read_type_form (read_forms_until rt s ')')

and resolve_raw_record = function
  | Form.Intermediate_record_raw forms ->
      record_value_of_forms forms
  | other ->
      other

and record_value_of_forms forms =
  let rec pair acc = function
    | [] ->
        Form.Record_value (List.rev acc)
    | [_] ->
        Err.fatal Err.Message.OddStructBody
          ~extra_remarks:
            [ Err.hint
                "struct literals are key-value pairs — each key needs a \
                 matching value" ]
          "struct body has an odd number of forms"
    | Form.Call (Form.Symbol "=" :: _) :: _ ->
        Err.fatal Err.Message.InvalidFieldKey
          ~extra_remarks:
            [ Err.hint
                "use '(= src dst)' only inside a record match pattern, not \
                 when constructing a record value" ]
          "'(= ...)' is not valid as a record field key"
    | Form.Symbol k :: v :: rest ->
        pair ((Form.Field (Form.Symbol k), v) :: acc) rest
    | Form.Int (k, _) :: v :: rest ->
        pair
          ((Form.Field (Form.Int (k, Form.default_int_suffix)), v) :: acc)
          rest
    | k :: v :: rest ->
        pair ((k, v) :: acc) rest
  in
  pair [] forms

and record_match_of_forms forms =
  let rec pair acc = function
    | [] ->
        Form.Record_match (List.rev acc)
    | [Form.Symbol name] ->
        Form.Record_match
          (List.rev ((Form.Field (Form.Symbol name), Form.Symbol name) :: acc))
    | [Form.Call [Form.Symbol "="; Form.Symbol src; Form.Symbol dst]] ->
        Form.Record_match
          (List.rev ((Form.Field (Form.Symbol src), Form.Symbol dst) :: acc))
    | [_] ->
        Err.fatal Err.Message.OddStructBody
          ~extra_remarks:
            [ Err.hint
                "each field in a record match needs either a bare name or a \
                 '(= src dst)' rename" ]
          "record match has an odd number of forms"
    | Form.Symbol name :: rest ->
        pair ((Form.Field (Form.Symbol name), Form.Symbol name) :: acc) rest
    | Form.Call [Form.Symbol "="; Form.Symbol src; Form.Symbol dst] :: rest ->
        pair ((Form.Field (Form.Symbol src), Form.Symbol dst) :: acc) rest
    | k :: v :: rest ->
        pair ((k, v) :: acc) rest
  in
  pair [] forms

and curry_fn args body =
  match args with
  | [] ->
      body
  | [a] ->
      Form.Fn (a, body)
  | a :: rest ->
      Form.Fn (a, curry_fn rest body)

and build_fn_body = function
  | [] ->
      Form.Unit
  | [single] ->
      single
  | multiple ->
      Form.Intermediate_block_inline multiple

and extract_record_args = function
  | Form.Record_value fields ->
      List.map snd fields
  | Form.Intermediate_record_raw forms -> (
    match record_value_of_forms forms with
    | Form.Record_value fields ->
        List.map snd fields
    | _ ->
        [] )
  | _ ->
      []

and build_fn_let spec_opt name args body =
  let name_form =
    match spec_opt with
    | Some spec ->
        Form.Specifier (spec, Form.Symbol name)
    | None ->
        Form.Symbol name
  in
  Form.Let (name_form, curry_fn args (build_fn_body body))

and read_let_form = function
  | [Form.Symbol "let"; Form.Symbol name; value] ->
      Form.Let (Form.Symbol name, resolve_raw_record value)
  | Form.Symbol "let" :: Form.Symbol name :: args_form :: body ->
      let args = extract_record_args args_form in
      build_fn_let None name args body
  | Form.Symbol "let"
    :: Form.Specifier (spec, Form.Symbol name)
    :: args_form :: body ->
      let args = extract_record_args args_form in
      build_fn_let (Some spec) name args body
  | [Form.Symbol "let"; Form.Intermediate_record_raw forms; value] ->
      let pat = record_match_of_forms forms in
      Form.Let (pat, resolve_raw_record value)
  | [Form.Symbol "let"; Form.Record_match _; _] as l -> (
    match l with [_; pat; value] -> Form.Let (pat, value) | _ -> Form.Call l )
  | [Form.Symbol "let"; Form.Record_value pat_fields; value] ->
      Form.Let (Form.Record_match pat_fields, resolve_raw_record value)
  | Form.Symbol "let" :: Form.Record_value pat_fields :: value :: body ->
      Form.Let
        ( Form.Record_match pat_fields
        , build_fn_body (List.map resolve_raw_record (value :: body)) )
  | [Form.Symbol "let"; Form.Record_value fields] ->
      let pairs =
        let rec go = function
          | (_, name) :: (_, value) :: rest ->
              (name, value) :: go rest
          | [] ->
              []
          | _ ->
              Err.fatal Err.Message.InvalidForm
                ~extra_remarks:
                  [Err.hint "each binding name must be followed by its value"]
                "multi-binding let has an odd number of forms"
        in
        go fields
      in
      let bindings =
        List.map (fun (name, value) -> Form.Let (name, value)) pairs
      in
      Form.Intermediate_block_inline bindings
  | [Form.Symbol "let"; Form.Intermediate_record_raw forms] ->
      let bindings =
        let rec go = function
          | name :: value :: rest ->
              Form.Let (name, value) :: go rest
          | [] ->
              []
          | _ ->
              Err.fatal Err.Message.InvalidForm
                ~extra_remarks:
                  [Err.hint "each binding name must be followed by its value"]
                "multi-binding let has an odd number of forms"
        in
        go forms
      in
      Form.Intermediate_block_inline bindings
  | forms ->
      Err.fatal Err.Message.InvalidForm
        ~extra_remarks:
          [ Err.hint
              "valid forms: (let name value), (let name {args} body...), or \
               (let {n1 v1 n2 v2 ...})" ]
        (Printf.sprintf "invalid 'let' form: got %d argument(s)"
           (List.length forms - 1) )

and read_fn_form = function
  | Form.Symbol "fn" :: args_form :: body ->
      let args = extract_record_args args_form in
      curry_fn args (build_fn_body (List.map resolve_raw_record body))
  | _ ->
      Err.fatal Err.Message.InvalidForm
        ~extra_remarks:[Err.hint "expected: (fn {arg1 arg2 ...} body...)"]
        "invalid 'fn' form"

and read_type_form = function
  | [] ->
      Form.Unit
  | Form.Symbol "let" :: rest ->
      read_let_form (Form.Symbol "let" :: rest)
  | Form.Symbol "fn" :: _ as forms ->
      read_fn_form forms
  | Form.Symbol "begin" :: body ->
      Form.Block body
  | Form.Symbol spec :: arg :: rest when spec = "rec" || spec = "mut" ->
      let arg' = if spec = "mut" then Form.Field arg else arg in
      Form.Specifier (spec, arg')
  | forms ->
      Form.Call (List.map resolve_raw_record forms)

and read_tuple_macro rt s _ =
  let items = read_forms_until rt s ']' in
  Form.Record_value
    (List.mapi
       (fun i v ->
         (Form.Field (Form.Int (Z.of_int i, Form.default_int_suffix)), v) )
       items )

and read_struct_macro rt s _ =
  let rec read_forms acc =
    Lexer.skip_whitespace s ;
    match Stream.peek s with
    | None ->
        Err.fatal
          ?loc:(Stream.current_eof_range s)
          Err.Message.UnexpectedEOF
          ~extra_remarks:
            [Err.hint "add a closing '}' to terminate the struct literal"]
          "unexpected end of input inside a struct literal"
    | Some '}' ->
        ignore (Stream.read s) ;
        List.rev acc
    | Some _ -> (
      match read_form rt s with
      | Form.Intermediate_empty ->
          read_forms acc
      | f ->
          read_forms (f :: acc) )
  in
  let forms = read_forms [] in
  Form.Intermediate_record_raw forms

and read_close_error s c =
  Err.fatal ?loc:(Stream.last_char_range s) Err.Message.UnexpectedClose
    (Printf.sprintf "unexpected closing '%c' with no matching opener" c)

and read_fn_dispatch rt s _ =
  let forms = read_forms_until rt s ')' in
  match forms with
  | Form.Record_value fields :: body ->
      let args = List.map snd fields in
      curry_fn args (build_fn_body body)
  | _ ->
      Form.Fn (Form.Unit, build_fn_body forms)

and read_array_dispatch rt s _ =
  Form.Call (Form.Symbol "array" :: read_forms_until rt s ']')

and read_set_dispatch rt s _ =
  Form.Call (Form.Symbol "set" :: read_forms_until rt s '}')

and read_dispatch_macro rt s _ =
  match Stream.peek s with
  | None ->
      Err.fatal
        ?loc:(Stream.current_eof_range s)
        Err.Message.UnexpectedEOF
        ~extra_remarks:
          [ Err.hint
              "'#' must be followed by '(', '[', '{', or a tag name such as #_"
          ]
        "unexpected end of input after '#'"
  | Some c -> (
    match Readtable.find_untagged_dispatch rt c with
    | Some fn ->
        ignore (Stream.read s) ;
        fn rt s c
    | None ->
        if Lexer.is_symbol_start c then read_tag_dispatch rt s
        else
          Err.fatal
            ?loc:(Stream.current_point_range s)
            Err.Message.UndefinedDispatch
            ~extra_remarks:
              [ Err.hint
                  "valid characters after '#' are '(', '[', '{', or a tag name \
                   such as #_" ]
            (Printf.sprintf "undefined dispatch '#%c'" c) )

and read_tag_dispatch rt s =
  let cap = Stream.capture s in
  let first = Stream.read s in
  let tag = Lexer.read_symbol_name s first in
  match Readtable.find_tag rt tag with
  | None ->
      Err.fatal
        ?loc:(Stream.range_from_capture s cap)
        Err.Message.UndefinedDispatch
        (Printf.sprintf "unknown reader tag '#%s'" tag)
  | Some handler -> (
      let payload = read_form rt s in
      try handler rt payload
      with exn ->
        Err.fatal
          ?loc:(Stream.range_from_capture s cap)
          Err.Message.TagHandlerError
          (Printf.sprintf "reader tag '#%s' raised an unexpected error: %s" tag
             (Printexc.to_string exn) ) )

let discard_tag : Readtable.tag_handler =
 fun _rt _form -> Form.Intermediate_empty

let default_readtable () =
  let rt = Readtable.create () in
  Readtable.set_macro rt '@' read_deref_macro ;
  Readtable.set_macro rt '(' read_list_macro ;
  Readtable.set_macro rt '[' read_tuple_macro ;
  Readtable.set_macro rt '{' read_struct_macro ;
  Readtable.set_macro rt ')' (fun _ s c -> read_close_error s c) ;
  Readtable.set_macro rt ']' (fun _ s c -> read_close_error s c) ;
  Readtable.set_macro rt '}' (fun _ s c -> read_close_error s c) ;
  Readtable.set_macro rt '"' read_string_macro ;
  Readtable.set_macro rt ';' read_comment_macro ;
  Readtable.set_macro rt '#' read_dispatch_macro ;
  Readtable.set_untagged_dispatch rt '(' read_fn_dispatch ;
  Readtable.set_untagged_dispatch rt '[' read_array_dispatch ;
  Readtable.set_untagged_dispatch rt '{' read_set_dispatch ;
  Readtable.register_tag rt "_" discard_tag ;
  rt

let read_forms_in_stream rt s =
  let forms = ref [] in
  ( try
      while true do
        match read_form rt s with
        | Form.Intermediate_empty ->
            ()
        | f ->
            forms := f :: !forms
      done
    with Stream.End_of_input -> () ) ;
  List.rev !forms

let read_all ?(rt = default_readtable ()) ?title input =
  let source = Span.source_of_string ?source_title:title input in
  let s = Stream.from_string ~source input in
  Err.run ~emit:Err.display_diagnostic
    ~fatal:(fun d -> Err.display_diagnostic d ; exit 1)
    (fun () -> read_forms_in_stream rt s)

let read_all_interactive ?(rt = default_readtable ()) ?title input =
  let source = Span.source_of_string ?source_title:title input in
  let s = Stream.from_string ~source input in
  Err.run ~emit:Err.display_diagnostic
    ~fatal:(fun d -> Err.display_diagnostic d ; [])
    (fun () -> read_forms_in_stream rt s)

let read_all_reported ?(rt = default_readtable ()) ~title input =
  read_all ~rt ~title input
