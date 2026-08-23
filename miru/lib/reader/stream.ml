exception End_of_input

type t =
  { input: string
  ; len: int
  ; mutable pos: int
  ; mutable line: int
  ; mutable col: int
  ; mutable sol: int
  ; source: Span.source option }

type capture = {cp_pos: int; cp_line: int; cp_col: int; cp_sol: int}

let from_string ?source s =
  {input= s; len= String.length s; pos= 0; line= 1; col= 0; sol= 0; source}

let peek s =
  if s.pos >= s.len then None else Some (String.unsafe_get s.input s.pos)

let peek_next s =
  let p = s.pos + 1 in
  if p >= s.len then None else Some (String.unsafe_get s.input p)

let read s =
  if s.pos >= s.len then raise End_of_input
  else
    let c = String.unsafe_get s.input s.pos in
    s.pos <- s.pos + 1 ;
    if c = '\n' then (
      s.line <- s.line + 1 ;
      s.col <- 0 ;
      s.sol <- s.pos )
    else s.col <- s.col + 1 ;
    c

let pos s = (s.pos, s.line, s.col)

let capture s = {cp_pos= s.pos; cp_line= s.line; cp_col= s.col; cp_sol= s.sol}

let make_position s ~offset ~line_num ~start_of_line =
  match s.source with
  | Some src ->
      Some (Span.make_position ~src ~offset ~line_num ~start_of_line)
  | None ->
      None

let point_range s ~offset ~line_num ~start_of_line =
  match make_position s ~offset ~line_num ~start_of_line with
  | Some p ->
      Some (Span.make_point_range p)
  | None ->
      None

let current_point_range s =
  point_range s ~offset:s.pos ~line_num:s.line ~start_of_line:s.sol

let current_eof_range s =
  match s.source with
  | None ->
      None
  | Some src ->
      let p =
        Span.make_position ~src ~offset:s.pos ~line_num:s.line
          ~start_of_line:s.sol
      in
      Some (Span.make_eof_range p)

let captured_point_range s cap =
  point_range s ~offset:cap.cp_pos ~line_num:cap.cp_line
    ~start_of_line:cap.cp_sol

let last_char_range s =
  match s.source with
  | None ->
      None
  | Some src ->
      if s.pos = 0 then None
      else
        let offset = s.pos - 1 in
        let p_start =
          Span.make_position ~src ~offset ~line_num:s.line ~start_of_line:s.sol
        in
        let p_end =
          Span.make_position ~src ~offset:s.pos ~line_num:s.line
            ~start_of_line:s.sol
        in
        Some (Span.make_range p_start p_end)

let range_from_capture s cap =
  match s.source with
  | None ->
      None
  | Some src ->
      let start_pos =
        Span.make_position ~src ~offset:cap.cp_pos ~line_num:cap.cp_line
          ~start_of_line:cap.cp_sol
      in
      let end_pos =
        Span.make_position ~src ~offset:s.pos ~line_num:s.line
          ~start_of_line:s.sol
      in
      Some (Span.make_range start_pos end_pos)

let skip_while s f =
  let input = s.input and len = s.len in
  let rec loop pos =
    if pos >= len then s.pos <- len
    else
      let c = String.unsafe_get input pos in
      if f c then begin
        if c = '\n' then (
          s.line <- s.line + 1 ;
          s.col <- 0 ;
          s.sol <- pos + 1 )
        else s.col <- s.col + 1 ;
        loop (pos + 1)
      end
      else s.pos <- pos
  in
  loop s.pos

let skip_to_eol s =
  let input = s.input and len = s.len in
  let rec loop pos =
    if pos >= len then begin
      s.pos <- len
    end
    else
      let c = String.unsafe_get input pos in
      if c = '\n' then begin
        s.pos <- pos + 1 ;
        s.line <- s.line + 1 ;
        s.col <- 0 ;
        s.sol <- pos + 1
      end
      else begin
        s.col <- s.col + 1 ;
        loop (pos + 1)
      end
  in
  loop s.pos
