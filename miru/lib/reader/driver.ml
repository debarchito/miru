exception Discard

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
      raise
        (Err.Reader_error
           ( Stream.current_point_range s
           , Err.Message.UnexpectedEOF
           , Printf.sprintf "unexpected EOF while reading form (expecting '%c')"
               close ) )
  | Some c when c = close ->
      ignore (Stream.read s) ;
      []
  | _ -> (
    match read_form rt s with
    | Form.Empty ->
        read_forms_until rt s close
    | f ->
        f :: read_forms_until rt s close )

and read_quote_macro rt s _ =
  match read_form rt s with Form.Empty -> Form.Empty | f -> Form.Quote f

and read_quasiquote_macro rt s _ =
  match read_form rt s with Form.Empty -> Form.Empty | f -> Form.Quasiquote f

and read_unquote_macro rt s _ =
  match Stream.peek s with
  | Some '@' -> (
      ignore (Stream.read s) ;
      match read_form rt s with Form.Empty -> Form.Empty | f -> Form.Splice f )
  | _ -> (
    match read_form rt s with Form.Empty -> Form.Empty | f -> Form.Unquote f )

and read_deref_macro rt s _ =
  match read_form rt s with
  | Form.Empty ->
      Form.Empty
  | f ->
      Form.Call [Form.Symbol "deref"; f]

and read_comment_macro rt s _ = Stream.skip_to_eol s ; read_form rt s

and read_string_macro _rt s _ = Lexer.read_string_body s

and read_list_macro rt s _ = read_type_form (read_forms_until rt s ')')

and resolve_raw_record = function
  | Form.RawRecord forms ->
      record_value_of_forms forms
  | other ->
      other

and read_let_form = function
  | [Form.Symbol "let"; Form.Symbol name; value] ->
      Form.Let {name= Form.Symbol name; body= resolve_raw_record value}
  | Form.Symbol "let" :: Form.Symbol name :: Form.RecordValue fields :: body ->
      let args = List.map snd fields in
      let fn_body = curry_fn args (build_fn_body body) in
      Form.Let {name= Form.Symbol name; body= fn_body}
  | Form.Symbol "let" :: Form.Symbol name :: Form.RawRecord forms :: body ->
      let args =
        List.map snd
          ( match record_value_of_forms forms with
          | Form.RecordValue p ->
              p
          | _ ->
              [] )
      in
      let fn_body =
        curry_fn args (build_fn_body (List.map resolve_raw_record body))
      in
      Form.Let {name= Form.Symbol name; body= fn_body}
  | Form.Symbol "let"
    :: Form.Specifier (spec, Form.Symbol name)
    :: Form.RecordValue fields
    :: body ->
      let args = List.map snd fields in
      let fn_body = curry_fn args (build_fn_body body) in
      Form.Let
        { name= Form.Specifier (spec, Form.Symbol name)
        ; body= fn_body }
  | Form.Symbol "let"
    :: Form.Specifier (spec, Form.Symbol name)
    :: Form.RawRecord forms
    :: body ->
      let args =
        List.map snd
          ( match record_value_of_forms forms with
          | Form.RecordValue p ->
              p
          | _ ->
              [] )
      in
      let fn_body =
        curry_fn args (build_fn_body (List.map resolve_raw_record body))
      in
      Form.Let
        { name= Form.Specifier (spec, Form.Symbol name)
        ; body= fn_body }
  | [Form.Symbol "let"; Form.RawRecord forms; value] ->
      let pat = record_match_of_forms forms in
      Form.Let {name= pat; body= resolve_raw_record value}
  | [Form.Symbol "let"; Form.RecordMatch _; _] as l -> (
    match l with
    | [_; pat; value] ->
        Form.Let {name= pat; body= value}
    | _ ->
        Form.Call l )
  | [Form.Symbol "let"; Form.RecordValue pat_fields; value] ->
      Form.Let
        {name= Form.RecordMatch pat_fields; body= resolve_raw_record value}
  | Form.Symbol "let" :: Form.RecordValue pat_fields :: value :: body ->
      Form.Let
        { name= Form.RecordMatch pat_fields
        ; body= build_fn_body (List.map resolve_raw_record (value :: body)) }
  | [Form.Symbol "let"; Form.RecordValue fields] ->
      let pairs =
        let rec go = function
          | (_, name) :: (_, value) :: rest ->
              (name, value) :: go rest
          | [] ->
              []
          | _ ->
              failwith "multi-binding: odd number of forms"
        in
        go fields
      in
      let bindings =
        List.map (fun (name, value) -> Form.Let {name; body= value}) pairs
      in
      Form.Sequence bindings
  | [Form.Symbol "let"; Form.RawRecord forms] ->
      let bindings =
        let rec go = function
          | name :: value :: rest ->
              Form.Let {name; body= value} :: go rest
          | [] ->
              []
          | _ ->
              failwith "multi-binding: odd number of forms"
        in
        go forms
      in
      Form.Sequence bindings
  | forms ->
      raise
        (Err.Reader_error
           ( None
           , Err.Message.InvalidForm
           , Printf.sprintf "invalid 'let' form: %d arguments"
               (List.length forms) ) )

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
      Form.Sequence multiple

and read_fn_form = function
  | Form.Symbol "fn" :: Form.RecordValue fields :: body ->
      let args = List.map snd fields in
      curry_fn args (build_fn_body body)
  | Form.Symbol "fn" :: Form.RawRecord forms :: body ->
      let args =
        match record_value_of_forms forms with
        | Form.RecordValue fields ->
            List.map snd fields
        | _ ->
            []
      in
      curry_fn args (build_fn_body (List.map resolve_raw_record body))
  | _ ->
      failwith "invalid fn form"

and read_type_form =
  let is_positional = function
    | (Form.Field (Form.Int _), _) :: _ ->
        true
    | _ ->
        false
  in
  let rec wrap_type = function
    | Form.RecordValue pairs ->
        Form.RecordValue (List.map (fun (k, v) -> (k, wrap_type v)) pairs)
    | Form.RawRecord forms ->
        wrap_type (record_value_of_forms forms)
    | Form.Call items -> (
      match List.map wrap_type items with
      | [] ->
          Form.Type Form.Unit
      | [x] ->
          x
      | base :: rest ->
          List.fold_left
            (fun acc t ->
              match t with
              | Form.Type (Form.Symbol s) ->
                  Form.TypeApplication (s, acc)
              | _ ->
                  Form.Type (Form.Call items) )
            base rest )
    | other ->
        Form.Type other
  in
  function
  | Form.Symbol "let" :: rest ->
      read_let_form (Form.Symbol "let" :: rest)
  | Form.Symbol "fn" :: _ as forms ->
      read_fn_form forms
  | Form.Symbol "block" :: body ->
      Form.Block body
  | [Form.Symbol "type"; Form.Symbol name; Form.RecordValue fields] ->
      if is_positional fields then
        Form.AbstractType
          ( name
          , Form.RecordValue (List.map (fun (k, v) -> (k, wrap_type v)) fields)
          )
      else
        Form.Record
          ( name
          , Form.RecordValue (List.map (fun (k, v) -> (k, wrap_type v)) fields)
          )
  | [Form.Symbol "type"; Form.Symbol name; Form.RawRecord forms] ->
      let fields =
        match record_value_of_forms forms with
        | Form.RecordValue p ->
            p
        | _ ->
            []
      in
      if is_positional fields then
        Form.AbstractType
          ( name
          , Form.RecordValue (List.map (fun (k, v) -> (k, wrap_type v)) fields)
          )
      else
        Form.Record
          ( name
          , Form.RecordValue (List.map (fun (k, v) -> (k, wrap_type v)) fields)
          )
  | Form.Symbol "type" :: Form.Symbol name :: constructors -> (
    match constructors with
    | [single] -> (
      match single with
      | Form.Call (Form.Symbol ctor :: payload) ->
          let payload_type =
            match payload with
            | [] ->
                None
            | [f] ->
                Some (wrap_type f)
            | fs ->
                Some (wrap_type (Form.Call fs))
          in
          Form.Variant (name, [Form.Constructor (ctor, payload_type)])
      | _ ->
          Form.AbstractType (name, wrap_type single) )
    | _ ->
        let rec process_ctors acc = function
          | Form.Symbol ctor :: rest -> (
            match rest with
            | [] ->
                process_ctors (Form.Constructor (ctor, None) :: acc) []
            | Form.Symbol _ :: _ ->
                process_ctors (Form.Constructor (ctor, None) :: acc) rest
            | payload :: rest' ->
                process_ctors
                  (Form.Constructor (ctor, Some (wrap_type payload)) :: acc)
                  rest' )
          | Form.Call (Form.Symbol ctor :: payload) :: rest ->
              let payload_type =
                match payload with
                | [] ->
                    None
                | [f] ->
                    Some (wrap_type f)
                | fs ->
                    Some (wrap_type (Form.Call fs))
              in
              process_ctors (Form.Constructor (ctor, payload_type) :: acc) rest
          | _ :: rest ->
              process_ctors acc rest
          | [] ->
              List.rev acc
        in
        Form.Variant (name, process_ctors [] constructors) )
  | Form.Symbol spec :: arg :: rest when spec = "rec" || spec = "mut" ->
      let arg' = if spec = "mut" then Form.Field arg else arg in
      Form.Specifier (spec, arg')
  | forms ->
      Form.Call (List.map resolve_raw_record forms)

and read_tuple_macro rt s _ =
  let items = read_forms_until rt s ']' in
  Form.RecordValue
    (List.mapi (fun i v -> (Form.Field (Form.Int (Int64.of_int i)), v)) items)

and read_struct_macro rt s _ =
  let rec read_forms acc =
    Lexer.skip_whitespace s ;
    match Stream.peek s with
    | None ->
        raise
          (Err.Reader_error
             ( Stream.current_point_range s
             , Err.Message.UnexpectedEOF
             , "unexpected EOF while reading struct body (expecting '}')" ) )
    | Some '}' ->
        ignore (Stream.read s) ;
        List.rev acc
    | Some _ -> (
      match read_form rt s with
      | Form.Empty ->
          read_forms acc
      | f ->
          read_forms (f :: acc) )
  in
  let forms = read_forms [] in
  Form.RawRecord forms

and record_value_of_forms forms =
  let rec pair acc = function
    | [] ->
        Form.RecordValue (List.rev acc)
    | [f] ->
        raise
          (Err.Reader_error
             ( None
             , Err.Message.OddStructBody
             , "struct body has odd number of forms" ) )
    | Form.Call (Form.Symbol "=" :: _) :: _ ->
        raise
          (Err.Reader_error
             ( None
             , Err.Message.InvalidFieldKey
             , "(= x y) is only valid in record match, not record value" ) )
    | Form.Symbol k :: v :: rest ->
        pair ((Form.Field (Form.Symbol k), v) :: acc) rest
    | Form.Int k :: v :: rest ->
        pair ((Form.Field (Form.Int k), v) :: acc) rest
    | k :: v :: rest ->
        pair ((k, v) :: acc) rest
  in
  pair [] forms
and record_match_of_forms forms =
  let rec pair acc = function
    | [] ->
        Form.RecordMatch (List.rev acc)
    | [Form.Symbol name] ->
        Form.RecordMatch
          (List.rev ((Form.Field (Form.Symbol name), Form.Symbol name) :: acc))
    | [Form.Call [Form.Symbol "="; Form.Symbol src; Form.Symbol dst]] ->
        Form.RecordMatch
          (List.rev ((Form.Field (Form.Symbol src), Form.Symbol dst) :: acc))
    | [f] ->
        raise
          (Err.Reader_error
             ( None
             , Err.Message.OddStructBody
             , "match body has odd number of forms" ) )
    | Form.Symbol name :: rest ->
        pair
          ((Form.Field (Form.Symbol name), Form.Symbol name) :: acc)
          rest
    | (Form.Call [Form.Symbol "="; Form.Symbol src; Form.Symbol dst])
      :: rest ->
        pair ((Form.Field (Form.Symbol src), Form.Symbol dst) :: acc) rest
    | k :: v :: rest ->
        pair ((k, v) :: acc) rest
  in
  pair [] forms
and read_close_error s c =
  raise
    (Err.Reader_error
       ( Stream.current_point_range s
       , Err.Message.UnexpectedClose
       , Printf.sprintf "unexpected '%c'" c ) )

and read_fn_dispatch rt s _ =
  let forms = read_forms_until rt s ')' in
  match forms with
  | Form.RecordValue fields :: body ->
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
      raise
        (Err.Reader_error
           ( Stream.current_point_range s
           , Err.Message.UnexpectedEOF
           , "unexpected EOF after '#'" ) )
  | Some c -> (
    match Readtable.find_untagged_dispatch rt c with
    | Some fn ->
        ignore (Stream.read s) ;
        fn rt s c
    | None ->
        if Lexer.is_symbol_start c then read_tag_dispatch rt s
        else
          raise
            (Err.Reader_error
               ( Stream.current_point_range s
               , Err.Message.UndefinedDispatch
               , Printf.sprintf "undefined # dispatch '%c'" c ) ) )

and read_tag_dispatch rt s =
  let cap = Stream.capture s in
  let first = Stream.read s in
  let tag = Lexer.read_symbol_name s first in
  match Readtable.find_tag rt tag with
  | None ->
      raise
        (Err.Reader_error
           ( Stream.captured_point_range s cap
           , Err.Message.UndefinedDispatch
           , Printf.sprintf "undefined tag dispatch '#%s'" tag ) )
  | Some handler -> (
      let payload = read_form rt s in
      try handler rt payload with
      | Err.Reader_error _ as e ->
          raise e
      | exn ->
          raise
            (Err.Reader_error
               ( Stream.captured_point_range s cap
               , Err.Message.TagHandlerError
               , Printf.sprintf "tag '#%s' handler raised: %s" tag
                   (Printexc.to_string exn) ) ) )

and discard_tag : Readtable.tag_handler = fun _rt _form -> Form.Empty

let default_readtable () =
  let rt = Readtable.create () in
  Readtable.set_macro rt '\'' read_quote_macro ;
  Readtable.set_macro rt '`' read_quasiquote_macro ;
  Readtable.set_macro rt '~' read_unquote_macro ;
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

let read_all ?(rt = default_readtable ()) input =
  let s = Stream.from_string input in
  let forms = ref [] in
  ( try
      while true do
        match read_form rt s with Form.Empty -> () | f -> forms := f :: !forms
      done
    with Stream.End_of_input -> () ) ;
  List.rev !forms

let read_all_reported ?(rt = default_readtable ()) ~title input =
  let source = Span.source_of_string ~source_title:title input in
  let s = Stream.from_string ~source input in
  let module Term = Asai.Tty.Make (Err.Message) in
  Err.run ~emit:Term.display ~fatal:(fun d -> Term.display d ; exit 1)
  @@ fun () ->
  let forms = ref [] in
  ( try
      while true do
        match read_form rt s with Form.Empty -> () | f -> forms := f :: !forms
      done
    with
  | Stream.End_of_input ->
      ()
  | Err.Reader_error (span_opt, msg, detail) ->
      Err.fatal ?loc:span_opt ~severity:Asai.Diagnostic.Error msg detail ) ;
  List.rev !forms
