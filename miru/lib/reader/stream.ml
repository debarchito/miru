exception End_of_input

type t =
  { input: string
  ; len: int
  ; mutable pos: int
  ; mutable line: int
  ; mutable col: int
  ; mutable sol: int
  ; source: Span.source option }

type capture = int * int * int * int

let from_string ?source s =
  {input= s; len= String.length s; pos= 0; line= 1; col= 0; sol= 0; source}

let peek s = if s.pos >= s.len then None else Some (String.get s.input s.pos)

let peek_next s =
  let p = s.pos + 1 in
  if p >= s.len then None else Some (String.get s.input p)

let read s =
  if s.pos >= s.len then raise End_of_input
  else
    let c = String.get s.input s.pos in
    s.pos <- s.pos + 1 ;
    if c = '\n' then (
      s.line <- s.line + 1 ;
      s.col <- 0 ;
      s.sol <- s.pos )
    else s.col <- s.col + 1 ;
    c

let pos s = (s.pos, s.line, s.col)

let capture s = (s.pos, s.line, s.col, s.sol)

let point_range s ~offset ~line_num ~start_of_line =
  match s.source with
  | Some src ->
      let p = Span.make_position ~src ~offset ~line_num ~start_of_line in
      Some (Span.make_point_range p)
  | None ->
      None

let current_point_range s =
  point_range s ~offset:s.pos ~line_num:s.line ~start_of_line:s.sol

let captured_point_range s (pos, _, _, sol) =
  point_range s ~offset:pos ~line_num:s.line ~start_of_line:sol

let skip_while s f =
  let rec loop () =
    match peek s with
    | Some c when f c ->
        ignore (read s) ;
        loop ()
    | _ ->
        ()
  in
  loop ()

let skip_to_eol s =
  let rec loop () =
    match peek s with
    | None ->
        ()
    | Some '\n' ->
        ignore (read s)
    | Some _ ->
        ignore (read s) ;
        loop ()
  in
  loop ()
