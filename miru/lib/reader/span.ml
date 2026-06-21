type source = Asai.Range.source

type position = Asai.Range.position

type t = Asai.Range.t

let source_of_file path = Asai.Range.(`File path)

let source_of_string ?source_title content =
  let ttl = source_title in
  Asai.Range.(`String { title = ttl; content })

let make_position ~src ~offset ~line_num ~start_of_line =
  Asai.Range.{ source = src; offset; line_num; start_of_line }

let make_range start_pos end_pos = Asai.Range.make (start_pos, end_pos)

let make_point_range pos = Asai.Range.make (pos, pos)

let source_of_range r = Asai.Range.source r

let begin_line_num r = Asai.Range.begin_line_num r

let end_line_num r = Asai.Range.end_line_num r

let begin_offset r = Asai.Range.begin_offset r

let end_offset r = Asai.Range.end_offset r

let dump_position fmt p = Asai.Range.dump_position fmt p

let dump_range fmt r = Asai.Range.dump fmt r

let dump_source fmt s = Asai.Range.dump_source fmt s
