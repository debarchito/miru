open Repr.Value

let max_i = Int64.to_int 0x3FFFFFFFFFFFFFFFL
let min_i = Int64.to_int (-0x4000000000000000L)
let edge_case_ints = [ 0; 1; -1; 42; -42; max_i; min_i; max_i - 1; min_i + 1 ]

let test_integer_round_convert () =
  List.iter
    (fun expected ->
      let word = word_of_int expected in
      Alcotest.(check bool) "is_int tag true" true (is_int word);
      Alcotest.(check bool) "is_ptr tag false" false (is_ptr word);
      let actual = int_of_word word in
      Alcotest.(check int) "value roundtrips perfectly" expected actual)
    edge_case_ints

let test_integer_arithmetic () =
  let pairs =
    [ (10, 20); (-10, 20); (100, -50); (-100, -200); (max_i / 2, 5) ]
  in
  List.iter
    (fun (a, b) ->
      let word_a = word_of_int a in
      let word_b = word_of_int b in

      let sum_native = int_of_word word_a + int_of_word word_b in
      let diff_native = int_of_word word_a - int_of_word word_b in
      Alcotest.(check int) "unbox add match" (a + b) sum_native;
      Alcotest.(check int) "unbox sub match" (a - b) diff_native;

      let raw_sum_word = Int64.sub (Int64.add word_a word_b) 1L in
      Alcotest.(check int)
        "tagged bitwise addition match" (a + b) (int_of_word raw_sum_word);
      let raw_diff_word = Int64.add (Int64.sub word_a word_b) 1L in
      Alcotest.(check int)
        "tagged bitwise subtraction match" (a - b)
        (int_of_word raw_diff_word))
    pairs

let test_integer_overflow_boundary () =
  let pairs = [ (max_i, 1); (min_i, -1); (max_i, max_i) ] in
  List.iter
    (fun (a, b) ->
      let word_a = word_of_int a in
      let word_b = word_of_int b in
      let expected_wrap_sum = a + b in
      let expected_wrap_diff = a - b in

      let raw_sum_word = Int64.sub (Int64.add word_a word_b) 1L in
      Alcotest.(check int)
        "tagged addition matches native 63-bit overflow wrap" expected_wrap_sum
        (int_of_word raw_sum_word);

      let raw_diff_word = Int64.add (Int64.sub word_a word_b) 1L in
      Alcotest.(check int)
        "tagged subtraction matches native 63-bit overflow wrap"
        expected_wrap_diff
        (int_of_word raw_diff_word))
    pairs

let test_pointer_round_convert () =
  let valid_ptrs =
    [ 0x0L; 0x1000L; 0x7FFFFFFFFFFFFFF0L; 0xFFFFFFFFFFFFFFF8L ]
  in
  List.iter
    (fun expected_ptr ->
      let word = word_of_ptr expected_ptr in
      Alcotest.(check bool) "is_ptr tag true" true (is_ptr word);
      Alcotest.(check bool) "is_int tag false" false (is_int word);
      let actual_ptr = ptr_of_word word in
      Alcotest.(check int64) "ptr identity matches" expected_ptr actual_ptr)
    valid_ptrs

let test_pointer_assertions () =
  try
    ignore (word_of_ptr 0x1001L);
    Alcotest.fail "Expected word_of_ptr to crash on unaligned address"
  with
  | Assert_failure _ -> ()
  | exn ->
      Alcotest.failf "Expected Assert_failure, got: %s" (Printexc.to_string exn)

let () =
  let open Alcotest in
  run "Memory.Value"
    [
      ( "int",
        [
          test_case "round_convert" `Quick test_integer_round_convert;
          test_case "arithmetic_ops" `Quick test_integer_arithmetic;
          test_case "overflow_boundary" `Quick test_integer_overflow_boundary;
        ] );
      ( "ptr",
        [
          test_case "round_convert" `Quick test_pointer_round_convert;
          test_case "assertions" `Quick test_pointer_assertions;
        ] );
    ]
