type key =
  | Char of char | Enter | Tab | Backspace | Delete
  | Left | Right | Up | Down
  | Home | End
  | Ctrl of char
  | Unknown

let fd = Unix.stdin

let saved = ref None

let enter_raw () =
  let t = Unix.tcgetattr fd in
  saved := Some t;
  Unix.tcsetattr fd Unix.TCSANOW
    { t with
      Unix.c_ignbrk = true; c_brkint = false;
      c_ixon = false; c_ixoff = false;
      c_icanon = false; c_echo = false;
      c_vmin = 1; c_vtime = 0
    }

let leave_raw () =
  match !saved with
  | Some t -> Unix.tcsetattr fd Unix.TCSANOW t; saved := None
  | None -> ()

let read_byte () =
  let buf = Bytes.create 1 in
  match Unix.read fd buf 0 1 with
  | 0 -> raise End_of_file
  | _ -> Char.code (Bytes.get buf 0)

let rec read_key () =
  match read_byte () with
  | 0x03 -> Ctrl 'C'
  | 0x04 -> Ctrl 'D'
  | 0x09 -> Tab
  | 0x0a -> Enter
  | 0x7f | 0x08 -> Backspace
  | 0x1b ->
    (match read_byte () with
     | 0x5b ->
       (match read_byte () with
        | 0x41 -> Up | 0x42 -> Down | 0x43 -> Right | 0x44 -> Left
        | 0x48 -> Home | 0x46 -> End
        | 0x33 -> ignore (read_byte ()); Delete
        | 0x31 -> ignore (read_byte ()); Home
        | 0x34 -> ignore (read_byte ()); End
        | _ -> Unknown)
     | _ -> Unknown)
  | n when n < 32 -> Ctrl (Char.chr (n + 64))
  | n -> Char (Char.chr n)

let write s =
  ignore (Unix.write_substring Unix.stdout s 0 (String.length s))

let clear_to_eol = "\027[K"
let clear_to_eos = "\027[J"

let move_to_col n = Printf.sprintf "\027[%dG" n

let save_cursor = "\027[s"
let restore_cursor = "\027[u"

let bold = "\027[1m"
let reset = "\027[0m"
let green = "\027[32m"
let cyan = "\027[36m"
let yellow = "\027[33m"
let dim = "\027[2m"
