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

(* --- standard macros --- *)

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
      Form.List [Form.Symbol "deref"; f]

and read_comment_macro rt s _ = Stream.skip_to_eol s ; read_form rt s

and read_string_macro _rt s _ = Lexer.read_string_body s

and read_list_macro rt s _ = read_type_form (read_forms_until rt s ')')

and read_type_form =
  let is_positional = function
    | (Form.Field (Form.Int _), _) :: _ ->
        true
    | _ ->
        false
  in
  let rec wrap_type = function
    | Form.RecordExpression pairs ->
        Form.RecordExpression (List.map (fun (k, v) -> (k, wrap_type v)) pairs)
    | Form.List items -> (
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
                  Form.Type (Form.List items) )
            base rest )
    | other ->
        Form.Type other
  in
  function
  | [Form.Symbol "type"; Form.Symbol name; Form.RecordExpression fields] ->
      if is_positional fields then
        Form.AbstractType
          ( name
          , Form.RecordExpression
              (List.map (fun (k, v) -> (k, wrap_type v)) fields) )
      else
        Form.Record
          ( name
          , Form.RecordExpression
              (List.map (fun (k, v) -> (k, wrap_type v)) fields) )
  | Form.Symbol "type" :: Form.Symbol name :: constructors -> (
    match constructors with
    | [single] -> (
      match single with
      | Form.List (Form.Symbol ctor :: payload) ->
          let payload_type =
            match payload with
            | [] ->
                None
            | [f] ->
                Some (wrap_type f)
            | fs ->
                Some (wrap_type (Form.List fs))
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
          | Form.List (Form.Symbol ctor :: payload) :: rest ->
              let payload_type =
                match payload with
                | [] ->
                    None
                | [f] ->
                    Some (wrap_type f)
                | fs ->
                    Some (wrap_type (Form.List fs))
              in
              process_ctors (Form.Constructor (ctor, payload_type) :: acc) rest
          | _ :: rest ->
              process_ctors acc rest
          | [] ->
              List.rev acc
        in
        Form.Variant (name, process_ctors [] constructors) )
  | forms ->
      Form.List forms

and read_tuple_macro rt s _ =
  let items = read_forms_until rt s ']' in
  Form.RecordExpression
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
        let cap = Stream.capture s in
        let span = Stream.captured_point_range s cap in
        match read_form rt s with
        | Form.Empty ->
            read_forms acc
        | f ->
            read_forms ((span, f) :: acc) )
  in
  let rec resolve_mutable = function
    | (_, Form.Symbol "mutable") :: (span, Form.Symbol x) :: rest ->
        (span, Form.MutableField x) :: resolve_mutable rest
    | (_, Form.Symbol "mutable") :: (span, Form.Int k) :: rest ->
        (span, Form.MutableField (Int64.to_string k)) :: resolve_mutable rest
    | (_, Form.Symbol "mutable") :: (span, Form.String _) :: _ ->
        raise
          (Err.Reader_error
             ( span
             , Err.Message.InvalidMutableFieldKey
             , "mutable field keys must be symbols or integers, got string" ) )
    | (_, Form.Symbol "mutable") :: (span, _) :: _ ->
        raise
          (Err.Reader_error
             ( span
             , Err.Message.InvalidMutableFieldKey
             , "mutable field keys must be symbols or integers, got other" ) )
    | (_, Form.Symbol "mutable") :: [] ->
        []
    | x :: rest ->
        x :: resolve_mutable rest
    | [] ->
        []
  in
  let forms = resolve_mutable (read_forms []) in
  let rec pair acc = function
    | [] ->
        Form.RecordExpression (List.rev acc)
    | [(_, Form.Symbol "mutable")] ->
        Form.RecordExpression (List.rev acc)
    | [(span, _)] ->
        raise
          (Err.Reader_error
             ( span
             , Err.Message.OddStructBody
             , "struct body has odd number of forms" ) )
    | (_, Form.Symbol k) :: (_, v) :: rest ->
        pair ((Form.Field (Form.Symbol k), v) :: acc) rest
    | (_, Form.Int k) :: (_, v) :: rest ->
        pair ((Form.Field (Form.Int k), v) :: acc) rest
    | (_, (Form.MutableField _ as k)) :: (_, v) :: rest ->
        pair ((k, v) :: acc) rest
    | (span, _) :: _ :: _ ->
        raise
          (Err.Reader_error
             ( span
             , Err.Message.InvalidFieldKey
             , "struct field keys must be symbols or integers" ) )
  in
  pair [] forms

and read_close_error s c =
  raise
    (Err.Reader_error
       ( Stream.current_point_range s
       , Err.Message.UnexpectedClose
       , Printf.sprintf "unexpected '%c'" c ) )

(* --- untagged dispatch bodies --- *)

and read_fn_dispatch rt s _ = Form.Fn (read_forms_until rt s ')')

and read_array_dispatch rt s _ =
  Form.List (Form.Symbol "array" :: read_forms_until rt s ']')

and read_set_dispatch rt s _ =
  Form.List (Form.Symbol "set" :: read_forms_until rt s '}')

(* --- '#' dispatch: untagged vs tagged --- *)

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
