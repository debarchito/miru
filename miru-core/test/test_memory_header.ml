open Memory.Header

let max_size = 0x3FFFFFFFFFFFFFL
let max_size_int = Int64.to_int max_size

let test_header_round_convert () =
  let cases =
    [
      (* size, color, tag *)
      (0, color_white, 0);
      (42, color_gray, 100);
      (1000, color_black, tag_string);
      (max_size_int, color_blue, tag_custom);
    ]
  in
  List.iter
    (fun (s, c, t) ->
      let h = make ~size:s ~color:c ~tag:t in
      Alcotest.(check int) "extract tag matches" t (tag h);
      Alcotest.(check int) "extract color matches" c (color h);
      Alcotest.(check int) "extract size matches" s (size h))
    cases

let test_header_field_isolation () =
  let h = make ~size:100 ~color:color_white ~tag:42 in
  let h1 = set_color h color_black in
  Alcotest.(check int) "color updated" color_black (color h1);
  Alcotest.(check int) "tag preserved" 42 (tag h1);
  Alcotest.(check int) "size preserved" 100 (size h1);

  let h2 = set_tag h tag_string in
  Alcotest.(check int) "color preserved" color_white (color h2);
  Alcotest.(check int) "tag updated" tag_string (tag h2);
  Alcotest.(check int) "size preserved" 100 (size h2);

  let h3 = set_size h 9999 in
  Alcotest.(check int) "color preserved" color_white (color h3);
  Alcotest.(check int) "tag preserved" 42 (tag h3);
  Alcotest.(check int) "size updated" 9999 (size h3)

let test_header_boundaries () =
  let h_max = make ~size:max_size_int ~color:color_blue ~tag:255 in
  Alcotest.(check int) "max 54-bit size" max_size_int (size h_max);

  let overflow_size = max_size_int + 100 in
  let h_overflow = make ~size:overflow_size ~color:color_gray ~tag:10 in
  let expected_masked_size =
    Int64.to_int (Int64.logand (Int64.of_int overflow_size) max_size)
  in
  Alcotest.(check int)
    "size is safely masked" expected_masked_size (size h_overflow);
  Alcotest.(check int)
    "color uncorrupted by size overflow" color_gray (color h_overflow);
  Alcotest.(check int) "tag uncorrupted by size overflow" 10 (tag h_overflow)

let test_header_classification () =
  let check_pred name pred input expected =
    Alcotest.(check bool) name expected (pred input)
  in
  check_pred "tag 0 is not variant" is_variant_constructor 0 false;
  check_pred "tag 1 is variant" is_variant_constructor 1 true;
  check_pred "tag 245 is variant" is_variant_constructor 245 true;
  check_pred "tag 246 (lazy) is not variant" is_variant_constructor tag_lazy
    false;

  let h_forward = make ~size:0 ~color:color_white ~tag:tag_forward in
  let h_bytes = make ~size:0 ~color:color_white ~tag:tag_bytes in
  let h_tuple = make ~size:0 ~color:color_white ~tag:0 in

  check_pred "detects forward block" is_forward h_forward true;
  check_pred "tuple is not forward" is_forward h_tuple false;

  check_pred "bytes block is opaque" is_opaque h_bytes true;
  check_pred "forward block is not opaque" is_opaque h_forward false

let () =
  let open Alcotest in
  run "Memory.Header"
    [
      ( "packing",
        [
          test_case "round_convert" `Quick test_header_round_convert;
          test_case "field_isolation" `Quick test_header_field_isolation;
          test_case "boundaries_and_masks" `Quick test_header_boundaries;
        ] );
      ( "classification",
        [ test_case "predicates" `Quick test_header_classification ] );
    ]
