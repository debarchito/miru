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
    | InvalidMutableFieldKey

  let default_severity _ = Asai.Diagnostic.Error

  let short_code = function
    | UnterminatedString -> "E001"
    | UnterminatedStringEscape -> "E002"
    | InvalidHexEscape -> "E003"
    | UnexpectedCharacter -> "E004"
    | UnexpectedEOF -> "E005"
    | UnexpectedClose -> "E006"
    | UndefinedDispatch -> "E007"
    | OddStructBody -> "E008"
    | InvalidFieldKey -> "E009"
    | InvalidMutableFieldKey -> "E010"
end

include Asai.Reporter.Make (Message)

exception Reader_error of Span.t option * Message.t * string

let display_diagnostic d =
  let module Term = Asai.Tty.Make (Message) in
  Term.display d
