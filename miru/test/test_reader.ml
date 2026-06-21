module F = Reader.Form
module R = Reader.Core

let parse ?rt input = R.read_all ?rt input

let rec equal_form a b =
  match (a, b) with
  | F.Unit, F.Unit -> true
  | F.Bool a, F.Bool b -> a = b
  | F.Int a, F.Int b -> a = b
  | F.Float a, F.Float b -> a = b
  | F.String a, F.String b -> a = b
  | F.Symbol a, F.Symbol b -> a = b
  | F.List a, F.List b -> equal_lists a b
  | F.RecordExpression a, F.RecordExpression b ->
      List.length a = List.length b
      && List.for_all2
           (fun (k1, v1) (k2, v2) -> equal_form k1 k2 && equal_form v1 v2)
           a b
  | F.Field a, F.Field b -> equal_form a b
  | F.MutableField a, F.MutableField b -> a = b
  | F.Type a, F.Type b -> equal_form a b
  | F.TypeApplication (s1, a1), F.TypeApplication (s2, a2) ->
      s1 = s2 && equal_form a1 a2
  | F.Tag (a1, a2), F.Tag (b1, b2) -> a1 = b1 && equal_form a2 b2
  | F.Fn a, F.Fn b -> equal_lists a b
  | F.Quote a, F.Quote b -> equal_form a b
  | F.Quasiquote a, F.Quasiquote b -> equal_form a b
  | F.Unquote a, F.Unquote b -> equal_form a b
  | F.Splice a, F.Splice b -> equal_form a b
  | F.Record (n1, b1), F.Record (n2, b2) -> n1 = n2 && equal_form b1 b2
  | F.AbstractType (n1, b1), F.AbstractType (n2, b2) ->
      n1 = n2 && equal_form b1 b2
  | F.Constructor (n1, p1), F.Constructor (n2, p2) -> n1 = n2 && p1 = p2
  | F.Variant (n1, c1), F.Variant (n2, c2) -> n1 = n2 && equal_lists c1 c2
  | _ -> false

and equal_lists a b =
  List.length a = List.length b && List.for_all2 equal_form a b

let check_form name expected actual =
  Alcotest.(check bool) name true (equal_lists expected actual)

(* --- Literals --- *)

let test_unit () =
  let forms = parse "unit" in
  check_form "unit literal" [ F.Unit ] forms

let test_true () =
  let forms = parse "true" in
  check_form "true literal" [ F.Bool true ] forms

let test_false () =
  let forms = parse "false" in
  check_form "false literal" [ F.Bool false ] forms

let test_int_decimal () =
  let forms = parse "42" in
  check_form "decimal int" [ F.Int 42L ] forms

let test_int_negative () =
  let forms = parse "-7" in
  check_form "negative int" [ F.Int (-7L) ] forms

let test_int_hex () =
  let forms = parse "0xFF" in
  check_form "hex int" [ F.Int 255L ] forms

let test_int_oct () =
  let forms = parse "0o77" in
  check_form "octal int" [ F.Int 63L ] forms

let test_int_bin () =
  let forms = parse "0b1010" in
  check_form "binary int" [ F.Int 10L ] forms

let test_float_simple () =
  let forms = parse "3.14" in
  match forms with [ F.Float _ ] -> () | _ -> Alcotest.fail "expected Float"

let test_float_exp () =
  let forms = parse "1.5e10" in
  match forms with [ F.Float _ ] -> () | _ -> Alcotest.fail "expected Float"

let test_string () =
  let forms = parse "\"hello world\"" in
  check_form "string" [ F.String "hello world" ] forms

let test_string_escape () =
  let forms = parse "\"hello\\nworld\"" in
  check_form "string escape" [ F.String "hello\nworld" ] forms

let test_symbol_basic () =
  let forms = parse "hello" in
  check_form "basic symbol" [ F.Symbol "hello" ] forms

let test_symbol_dot () =
  let forms = parse ".id" in
  check_form "dot symbol" [ F.Symbol ".id" ] forms

let test_symbol_qualified () =
  let forms = parse "session.id" in
  check_form "qualified symbol" [ F.Symbol "session.id" ] forms

let test_symbol_namespace () =
  let forms = parse "namespace/name" in
  check_form "namespace symbol" [ F.Symbol "namespace/name" ] forms

let test_symbol_op () =
  let forms = parse ":=" in
  check_form "operator symbol" [ F.Symbol ":=" ] forms

let test_symbol_op2 () =
  let forms = parse ".>" in
  check_form "operator symbol" [ F.Symbol ".>" ] forms

let test_symbol_qmark () =
  let forms = parse "active?" in
  check_form "symbol with ?" [ F.Symbol "active?" ] forms

(* --- Lists --- *)

let test_list_empty () =
  let forms = parse "()" in
  check_form "empty list" [ F.List [] ] forms

let test_list_basic () =
  let forms = parse "(1 2 3)" in
  check_form "basic list" [ F.List [ F.Int 1L; F.Int 2L; F.Int 3L ] ] forms

let test_list_nested () =
  let forms = parse "(1 (2 3) 4)" in
  check_form "nested list"
    [ F.List [ F.Int 1L; F.List [ F.Int 2L; F.Int 3L ]; F.Int 4L ] ]
    forms

let test_list_symbols () =
  let forms = parse "(first ds)" in
  check_form "symbol list" [ F.List [ F.Symbol "first"; F.Symbol "ds" ] ] forms

(* --- Tuples --- *)

let test_tuple_empty () =
  let forms = parse "[]" in
  check_form "empty tuple" [ F.RecordExpression [] ] forms

let test_tuple_basic () =
  let forms = parse "[1 2 \"name\"]" in
  check_form "basic tuple"
    [ F.RecordExpression
        [ (F.Field (F.Int 0L), F.Int 1L);
          (F.Field (F.Int 1L), F.Int 2L);
          (F.Field (F.Int 2L), F.String "name") ] ]
    forms

(* --- Structs --- *)

let test_struct_empty () =
  let forms = parse "{}" in
  check_form "empty struct" [ F.RecordExpression [] ] forms

let test_struct_basic () =
  let forms = parse "{key1 \"value\" key2 \"value2\"}" in
  check_form "basic struct"
    [
      F.RecordExpression
        [
          (F.Field (F.Symbol "key1"), F.String "value"); (F.Field (F.Symbol "key2"), F.String "value2");
        ];
    ]
    forms

(* --- Quote --- *)

let test_quote_symbol () =
  let forms = parse "'x" in
  check_form "quote symbol" [ F.Quote (F.Symbol "x") ] forms

let test_quote_list () =
  let forms = parse "'(1 2 3)" in
  check_form "quote list"
    [ F.Quote (F.List [ F.Int 1L; F.Int 2L; F.Int 3L ]) ]
    forms

(* --- Quasiquote, Unquote, Splice, Deref --- *)

let test_quasiquote () =
  let forms = parse "`x" in
  check_form "quasiquote" [ F.Quasiquote (F.Symbol "x") ] forms

let test_unquote () =
  let forms = parse "~x" in
  check_form "unquote" [ F.Unquote (F.Symbol "x") ] forms

let test_splice () =
  let forms = parse "~@(foo)" in
  check_form "splice" [ F.Splice (F.List [ F.Symbol "foo" ]) ] forms

let test_deref () =
  let forms = parse "@x" in
  check_form "deref" [ F.List [ F.Symbol "deref"; F.Symbol "x" ] ] forms

(* --- Dispatch macros: #(...) --- *)

let test_anon_fn () =
  let forms = parse "#(+ % 1)" in
  check_form "anon fn" [ F.Fn [ F.Symbol "+"; F.Symbol "%"; F.Int 1L ] ] forms

let test_anon_fn_empty () =
  let forms = parse "#()" in
  check_form "empty anon fn" [ F.Fn [] ] forms

(* --- Discard: #_ --- *)

let test_discard_in_list () =
  let forms = parse "(1 #_ 2 3)" in
  check_form "discard in list" [ F.List [ F.Int 1L; F.Int 3L ] ] forms

let test_discard_in_tuple () =
  let forms = parse "[1 #_ 2 3]" in
  check_form "discard in tuple"
    [ F.RecordExpression
        [ (F.Field (F.Int 0L), F.Int 1L); (F.Field (F.Int 1L), F.Int 3L) ] ]
    forms

let test_discard_double_in_list () =
  let forms = parse "(1 #_ 2 #_ 3 4)" in
  check_form "discard double" [ F.List [ F.Int 1L; F.Int 4L ] ] forms

(* --- Undefined # dispatch errors --- *)

let test_undefined_dispatch () =
  try
    ignore (parse "#a[1 2 3]");
    Alcotest.fail "expected failure for undefined # dispatch"
  with Reader.Err.Reader_error _ -> ()

(* --- Invalid # dispatch errors --- *)

let test_array_dispatch () =
  let forms = parse "#[1 2 3]" in
  check_form "array dispatch"
    [ F.List [ F.Symbol "array"; F.Int 1L; F.Int 2L; F.Int 3L ] ]
    forms

let test_set_dispatch () =
  let forms = parse "#{1 2 3}" in
  check_form "set dispatch"
    [ F.List [ F.Symbol "set"; F.Int 1L; F.Int 2L; F.Int 3L ] ]
    forms

(* --- Comments --- *)

let test_comment_inline () =
  let forms = parse "42 ; this is a comment\n 43" in
  check_form "inline comment" [ F.Int 42L; F.Int 43L ] forms

let test_comment_standalone () =
  let forms = parse ";; standalone\n42" in
  check_form "standalone comment" [ F.Int 42L ] forms

(* --- Comma as whitespace --- *)

let test_comma_list () =
  let forms = parse "(1, 2, \"name\")" in
  check_form "comma in list"
    [ F.List [ F.Int 1L; F.Int 2L; F.String "name" ] ]
    forms

(* --- Multiple top-level forms --- *)

let test_multiple_forms () =
  let forms = parse "1 2 3" in
  check_form "multiple forms" [ F.Int 1L; F.Int 2L; F.Int 3L ] forms

(* --- Edge cases --- *)

let test_empty_input () =
  let forms = parse "" in
  check_form "empty input" [] forms

let test_whitespace_only () =
  let forms = parse "   \n  \t  " in
  check_form "whitespace only" [] forms

(* --- Custom dispatch reader --- *)

let test_custom_dispatch () =
  let rt = R.default () in
  R.set_dispatch rt 'u' (fun rt s _ ->
      let body = R.read_form rt s in
      F.Tag ("url", body));
  let forms = R.read_all ~rt "#u\"https://example.com\"" in
  check_form "custom dispatch"
    [ F.Tag ("url", F.String "https://example.com") ]
    forms

(* --- Error cases --- *)

let test_unclosed_paren () =
  try
    ignore (parse "(1 2");
    Alcotest.fail "expected failure for unclosed paren"
  with Reader.Err.Reader_error _ -> ()

let test_unclosed_string () =
  try
    ignore (parse "\"hello");
    Alcotest.fail "expected failure for unclosed string"
  with Reader.Err.Reader_error _ -> ()

let tests =
  [
    ("literals", `Quick, test_unit);
    ("bool true", `Quick, test_true);
    ("bool false", `Quick, test_false);
    ("decimal int", `Quick, test_int_decimal);
    ("negative int", `Quick, test_int_negative);
    ("hex int", `Quick, test_int_hex);
    ("octal int", `Quick, test_int_oct);
    ("binary int", `Quick, test_int_bin);
    ("float simple", `Quick, test_float_simple);
    ("float exp", `Quick, test_float_exp);
    ("string literal", `Quick, test_string);
    ("string escape", `Quick, test_string_escape);
    ("basic symbol", `Quick, test_symbol_basic);
    ("dot symbol", `Quick, test_symbol_dot);
    ("qualified symbol", `Quick, test_symbol_qualified);
    ("namespace symbol", `Quick, test_symbol_namespace);
    ("operator :=", `Quick, test_symbol_op);
    ("operator .>", `Quick, test_symbol_op2);
    ("symbol with ?", `Quick, test_symbol_qmark);
    ("empty list", `Quick, test_list_empty);
    ("basic list", `Quick, test_list_basic);
    ("nested list", `Quick, test_list_nested);
    ("symbol list", `Quick, test_list_symbols);
    ("empty tuple", `Quick, test_tuple_empty);
    ("basic tuple", `Quick, test_tuple_basic);
    ("empty struct", `Quick, test_struct_empty);
    ("basic struct", `Quick, test_struct_basic);
    ("quote symbol", `Quick, test_quote_symbol);
    ("quote list", `Quick, test_quote_list);
    ("quasiquote", `Quick, test_quasiquote);
    ("unquote", `Quick, test_unquote);
    ("splice", `Quick, test_splice);
    ("deref", `Quick, test_deref);
    ("anon fn", `Quick, test_anon_fn);
    ("empty anon fn", `Quick, test_anon_fn_empty);
    ("discard in list", `Quick, test_discard_in_list);
    ("discard in tuple", `Quick, test_discard_in_tuple);
    ("discard double", `Quick, test_discard_double_in_list);
    ("undefined dispatch error", `Quick, test_undefined_dispatch);
    ("array dispatch", `Quick, test_array_dispatch);
    ("set dispatch", `Quick, test_set_dispatch);
    ("inline comment", `Quick, test_comment_inline);
    ("standalone comment", `Quick, test_comment_standalone);
    ("comma in list", `Quick, test_comma_list);
    ("multiple forms", `Quick, test_multiple_forms);
    ("empty input", `Quick, test_empty_input);
    ("whitespace only", `Quick, test_whitespace_only);
    ("custom dispatch", `Quick, test_custom_dispatch);
    ("unclosed paren errors", `Quick, test_unclosed_paren);
    ("unclosed string errors", `Quick, test_unclosed_string);
  ]

let () = Alcotest.run "Reader" [ ("reader", tests) ]
