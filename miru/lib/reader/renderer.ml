module Ansi = struct
  type param = {enabled: bool; color: bool}

  let guess output =
    let no_color =
      match Sys.getenv_opt "NO_COLOR" with None | Some "" -> false | _ -> true
    in
    let rich_term =
      match Sys.getenv_opt "TERM" with
      | None | Some "" | Some "dumb" ->
          false
      | _ ->
          true
    in
    let is_tty o =
      try Unix.isatty (Unix.descr_of_out_channel o) with _ -> false
    in
    {enabled= rich_term && is_tty output; color= not no_color}

  let apply ~param codes s =
    if not param.enabled then s
    else
      let codes' =
        if param.color then codes
        else List.filter (fun c -> c = "1" || c = "2") codes
      in
      match codes' with
      | [] ->
          s
      | _ ->
          Printf.sprintf "\x1b[%sm%s\x1b[0m" (String.concat ";" codes') s

  let bold ~param s = apply ~param ["1"] s

  let faint ~param s = apply ~param ["2"] s

  let fringe ~param s = faint ~param s

  let note_color ~param s = apply ~param ["34"] s

  let hint_color ~param s = apply ~param ["32"] s

  let sev_codes ~param sev =
    if not param.color then ["1"]
    else
      match sev with
      | `Error ->
          ["1"; "31"]
      | `Warning ->
          ["1"; "33"]
      | `Hint | `Info ->
          ["1"; "34"]
      | `Bug ->
          ["1"; "35"]

  let primary ~param sev s = apply ~param (sev_codes ~param sev) s

  let secondary ~param s = apply ~param ["36"] s
end

module Tag = struct
  type t = Primary | Secondary of int

  let equal a b =
    match (a, b) with
    | Primary, Primary ->
        true
    | Secondary i, Secondary j ->
        i = j
    | _ ->
        false

  let priority = function Primary -> 0 | Secondary i -> i + 1

  let dump fmt = function
    | Primary ->
        Format.pp_print_string fmt "Primary"
    | Secondary i ->
        Format.fprintf fmt "Secondary(%d)" i
end

module Exp = Asai.Explicator.Make (Tag)

let sev_kind :
    Asai.Diagnostic.severity -> [`Error | `Warning | `Hint | `Info | `Bug] =
  function
  | Error ->
      `Error
  | Warning ->
      `Warning
  | Hint ->
      `Hint
  | Info ->
      `Info
  | Bug ->
      `Bug

let string_of_sev : Asai.Diagnostic.severity -> string = function
  | Error ->
      "error"
  | Warning ->
      "warning"
  | Hint ->
      "hint"
  | Info ->
      "info"
  | Bug ->
      "bug"

let text_to_string (text : Asai.Diagnostic.text) =
  let buf = Buffer.create 64 in
  let fmt = Format.formatter_of_buffer buf in
  Format.pp_set_margin fmt 10000 ;
  text fmt ;
  Format.pp_print_flush fmt () ;
  Buffer.contents buf

let display_width s =
  let w = ref 0 in
  String.iter
    (fun c ->
      let b = Char.code c in
      if b = 0x09 then w := !w + 4 else if b land 0xC0 <> 0x80 then incr w )
    s ;
  !w

let pp_line_gutter ~param ppf lnw n =
  Format.fprintf ppf " %s %s "
    (Ansi.fringe ~param (Printf.sprintf "%*d" lnw n))
    (Ansi.fringe ~param "|")

let pp_blank_gutter ~param ppf lnw =
  Format.fprintf ppf " %s %s\n"
    (Ansi.fringe ~param (String.make lnw ' '))
    (Ansi.fringe ~param "|")

let pp_ul_gutter ~param ppf lnw =
  Format.fprintf ppf " %s %s "
    (Ansi.fringe ~param (String.make lnw ' '))
    (Ansi.fringe ~param "|")

let render_explication ~param ~sev ~lnw ~tag_text ppf
    (explication : Tag.t Asai.Explication.t) =
  let sk = sev_kind sev in
  List.iter
    (fun Asai.Explication.{source; blocks} ->
      let title = Option.value ~default:"<unknown>" (Asai.Range.title source) in
      let locus_line, locus_col =
        match blocks with
        | [] ->
            (1, 1)
        | {Asai.Explication.begin_line_num; lines; _} :: _ ->
            let col =
              match lines with
              | [] ->
                  1
              | {Asai.Explication.segments; _} :: _ ->
                  let acc = ref 0 and found = ref false in
                  List.iter
                    (fun (tag_opt, seg) ->
                      if not !found then
                        if tag_opt = None then acc := !acc + display_width seg
                        else (
                          acc := !acc + 1 ;
                          found := true ) )
                    segments ;
                  if !found then !acc else 1
            in
            (begin_line_num, col)
      in
      Format.fprintf ppf " %s %s:%d:%d\n"
        (Ansi.fringe ~param (Printf.sprintf "%*s-->" lnw ""))
        title locus_line locus_col ;
      pp_blank_gutter ~param ppf lnw ;
      List.iter
        (fun Asai.Explication.{begin_line_num; lines; _} ->
          List.iteri
            (fun i Asai.Explication.{segments; tags} ->
              let line_num = begin_line_num + i in
              pp_line_gutter ~param ppf lnw line_num ;
              List.iter
                (fun (tag_opt, seg) ->
                  match tag_opt with
                  | None ->
                      print_string seg
                  | Some Tag.Primary ->
                      print_string (Ansi.primary ~param sk seg)
                  | Some (Tag.Secondary _) ->
                      print_string (Ansi.secondary ~param seg) )
                segments ;
              print_char '\n' ;
              if tags <> [] then begin
                pp_ul_gutter ~param ppf lnw ;
                let ul = Buffer.create 64 in
                let wrote = ref false in
                List.iter
                  (fun (tag_opt, seg) ->
                    let w = display_width seg in
                    match tag_opt with
                    | None ->
                        for _ = 1 to w do
                          Buffer.add_char ul ' '
                        done
                    | Some Tag.Primary ->
                        let w' = if w = 0 && not !wrote then 1 else w in
                        for _ = 1 to w' do
                          Buffer.add_char ul '^'
                        done ;
                        wrote := true
                    | Some (Tag.Secondary _) ->
                        let w' = if w = 0 && not !wrote then 1 else w in
                        for _ = 1 to w' do
                          Buffer.add_char ul '-'
                        done ;
                        wrote := true )
                  segments ;
                let best =
                  match List.find_opt (fun t -> t = Tag.Primary) tags with
                  | Some t ->
                      t
                  | None ->
                      List.hd tags
                in
                print_string
                  ( match best with
                  | Tag.Primary ->
                      Ansi.primary ~param sk (Buffer.contents ul)
                  | Tag.Secondary _ ->
                      Ansi.secondary ~param (Buffer.contents ul) ) ;
                ( match (best, List.assoc_opt best tag_text) with
                | Tag.Secondary _, Some lbl when lbl <> "" ->
                    print_char ' ' ;
                    print_string (Ansi.secondary ~param lbl)
                | _ ->
                    () ) ;
                print_char '\n'
              end )
            lines ;
          pp_blank_gutter ~param ppf lnw )
        blocks )
    explication

let display_string_diag ?(output = stdout) (d : string Asai.Diagnostic.t) =
  let param = Ansi.guess output in
  let ppf = Format.formatter_of_out_channel output in
  let sev = d.Asai.Diagnostic.severity in
  let sk = sev_kind sev in
  let code = d.Asai.Diagnostic.message in
  let explanation =
    text_to_string d.Asai.Diagnostic.explanation.Asai.Range.value
  in
  Format.fprintf ppf "%s: %s\n"
    (Ansi.primary ~param sk (string_of_sev sev ^ "[" ^ code ^ "]"))
    (Ansi.bold ~param explanation) ;
  let remarks = Bwd.Bwd.to_list d.Asai.Diagnostic.extra_remarks in
  let located, unlocated =
    List.partition_map
      (fun Asai.Range.{loc; value= txt} ->
        match loc with
        | Some r ->
            Either.Left (r, txt)
        | None ->
            Either.Right txt )
      remarks
  in
  let main_loc = d.Asai.Diagnostic.explanation.Asai.Range.loc in
  let tagged_ranges =
    (match main_loc with None -> [] | Some r -> [(Tag.Primary, r)])
    @ List.mapi (fun i (r, _) -> (Tag.Secondary i, r)) located
  in
  let tag_text : (Tag.t * string) list =
    List.mapi (fun i (_, txt) -> (Tag.Secondary i, text_to_string txt)) located
  in
  if tagged_ranges <> [] then begin
    let explication =
      Asai.SourceReader.run (fun () ->
          Exp.explicate ~block_splitting_threshold:5 tagged_ranges )
    in
    let max_ln =
      List.fold_left
        (fun acc Asai.Explication.{blocks; _} ->
          List.fold_left
            (fun acc b -> max acc b.Asai.Explication.end_line_num)
            acc blocks )
        1 explication
    in
    let lnw = String.length (string_of_int max_ln) in
    render_explication ~param ~sev ~lnw ~tag_text ppf explication
  end ;
  List.iter
    (fun txt ->
      let raw = text_to_string txt in
      let kind, body =
        match String.index_opt raw '\x00' with
        | None ->
            ("note", raw)
        | Some i ->
            ( String.sub raw 0 i
            , String.sub raw (i + 1) (String.length raw - i - 1) )
      in
      let label, color_fn =
        match kind with
        | "hint" ->
            ("hint", Ansi.hint_color)
        | _ ->
            ("note", Ansi.note_color)
      in
      Format.fprintf ppf " %s %s%s\n" (Ansi.fringe ~param "=")
        (color_fn ~param (label ^ ":"))
        (if body = "" then "" else " " ^ Ansi.bold ~param body) )
    unlocated ;
  Format.pp_print_newline ppf () ;
  Format.pp_print_flush ppf ()

let display (type msg) (module M : Asai.MinimumSigs.Message with type t = msg)
    ?(output = stdout) (d : msg Asai.Diagnostic.t) =
  display_string_diag ~output (Asai.Diagnostic.map M.short_code d)
