module Message = struct
  type t =
    | UnterminatedString
    | UnterminatedStringEscape
    | InvalidHexEscape
    | UnexpectedCharacter
    | UnexpectedEOF
    | UnexpectedClose
    | UndefinedDispatch
    | OddStructBody
    | InvalidFieldKey
    | InvalidForm
    | InvalidMutableFieldKey
    | TagHandlerError

  let default_severity _ = Asai.Diagnostic.Error

  let short_code = function
    | UnterminatedString ->
        "E001"
    | UnterminatedStringEscape ->
        "E002"
    | InvalidHexEscape ->
        "E003"
    | UnexpectedCharacter ->
        "E004"
    | UnexpectedEOF ->
        "E005"
    | UnexpectedClose ->
        "E006"
    | UndefinedDispatch ->
        "E007"
    | OddStructBody ->
        "E008"
    | InvalidFieldKey ->
        "E009"
    | InvalidForm ->
        "E010"
    | InvalidMutableFieldKey ->
        "E011"
    | TagHandlerError ->
        "E012"
end

include Asai.Reporter.Make (Message)

let remark_loctext kind ?loc fmt =
  Format.kdprintf
    (fun body ->
      let text ppf = Format.fprintf ppf "%s\x00%t" kind body in
      Asai.Range.locate_opt loc text )
    fmt

let note fmt = remark_loctext "note" fmt

let note_at loc fmt = remark_loctext "note" ~loc fmt

let hint fmt = remark_loctext "hint" fmt

let hint_at loc fmt = remark_loctext "hint" ~loc fmt

let display_diagnostic d = Renderer.display (module Message) d
