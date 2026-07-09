type tag_handler = t -> Form.t -> Form.t

and t =
  { macro: (char, t -> Stream.t -> char -> Form.t) Hashtbl.t
  ; untagged: (char, t -> Stream.t -> char -> Form.t) Hashtbl.t
  ; tags: (string, tag_handler) Hashtbl.t }

exception Duplicate_tag of string

exception Reserved_tag of string

let create () =
  {macro= Hashtbl.create 16; untagged= Hashtbl.create 4; tags= Hashtbl.create 16}

let copy rt =
  { macro= Hashtbl.copy rt.macro
  ; untagged= Hashtbl.copy rt.untagged
  ; tags= Hashtbl.copy rt.tags }

let set_macro rt c fn = Hashtbl.replace rt.macro c fn

let find_macro rt c = Hashtbl.find_opt rt.macro c

let set_untagged_dispatch rt c fn = Hashtbl.replace rt.untagged c fn

let find_untagged_dispatch rt c = Hashtbl.find_opt rt.untagged c

let register_tag rt tag fn =
  if Hashtbl.mem rt.tags tag then raise (Duplicate_tag tag)
  else Hashtbl.replace rt.tags tag fn

let replace_tag rt tag fn = Hashtbl.replace rt.tags tag fn

let unregister_tag rt tag = Hashtbl.remove rt.tags tag

let find_tag rt tag = Hashtbl.find_opt rt.tags tag

let registered_tags rt = Hashtbl.fold (fun k _ acc -> k :: acc) rt.tags []

module type Extension = sig
  val name : string

  val tags : (string * tag_handler) list
end

let install rt (module Ext : Extension) =
  List.iter
    (fun (tag, fn) ->
      try register_tag rt tag fn
      with Duplicate_tag t ->
        raise
          (Duplicate_tag (Printf.sprintf "%s (from extension %S)" t Ext.name)) )
    Ext.tags
