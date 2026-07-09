let rec pp_ast fmt = function
  | Form.Unit ->
      Format.pp_print_string fmt "Unit"
  | Form.Empty ->
      Format.pp_print_string fmt "Empty"
  | Form.Bool v ->
      Format.fprintf fmt "(Bool %b)" v
  | Form.Int n ->
      Format.fprintf fmt "(Int %s)" (Int64.to_string n)
  | Form.Float f ->
      Format.fprintf fmt "(Float %s)" (string_of_float f)
  | Form.String s ->
      Format.fprintf fmt "(String %S)" s
  | Form.Symbol s ->
      Format.fprintf fmt "(Symbol %s)" s
  | Form.List fs ->
      Format.fprintf fmt "@[<v 2>(List" ;
      List.iter (fun f -> Format.fprintf fmt "@ %a" pp_ast f) fs ;
      Format.fprintf fmt ")@]"
  | Form.RecordExpression pairs ->
      Format.fprintf fmt "@[<v 2>(RecordExpression" ;
      List.iter
        (fun (k, v) -> Format.fprintf fmt "@ %a %a" pp_ast k pp_ast v)
        pairs ;
      Format.fprintf fmt ")@]"
  | Form.Record (name, body) ->
      Format.fprintf fmt "@[<v 2>(Record %s@ %a)@]" name pp_ast body
  | Form.AbstractType (name, body) ->
      Format.fprintf fmt "@[<v 2>(AbstractType %s@ %a)@]" name pp_ast body
  | Form.Constructor (name, payload) -> (
    match payload with
    | None ->
        Format.fprintf fmt "(Constructor %s)" name
    | Some p ->
        Format.fprintf fmt "@[<v 2>(Constructor %s@ %a)@]" name pp_ast p )
  | Form.Variant (name, cases) ->
      Format.fprintf fmt "@[<v 2>(Variant %s" name ;
      List.iter (fun c -> Format.fprintf fmt "@ %a" pp_ast c) cases ;
      Format.fprintf fmt ")@]"
  | Form.Tag (name, body) ->
      Format.fprintf fmt "@[<v 2>(Tag %s@ %a)@]" name pp_ast body
  | Form.Fn fs ->
      Format.fprintf fmt "@[<v 2>(Fn" ;
      List.iter (fun f -> Format.fprintf fmt "@ %a" pp_ast f) fs ;
      Format.fprintf fmt ")@]"
  | Form.Quote f ->
      Format.fprintf fmt "@[<v 2>(Quote@ %a)@]" pp_ast f
  | Form.Quasiquote f ->
      Format.fprintf fmt "@[<v 2>(Quasiquote@ %a)@]" pp_ast f
  | Form.Unquote f ->
      Format.fprintf fmt "@[<v 2>(Unquote@ %a)@]" pp_ast f
  | Form.Splice f ->
      Format.fprintf fmt "@[<v 2>(Splice@ %a)@]" pp_ast f
  | Form.Field f -> (
    match f with
    | Form.Symbol s ->
        Format.fprintf fmt "(Field %s)" s
    | Form.Int n ->
        Format.fprintf fmt "(Field %s)" (Int64.to_string n)
    | _ ->
        Format.fprintf fmt "@[<v 2>(Field@ %a)@]" pp_ast f )
  | Form.MutableField s ->
      Format.fprintf fmt "(MutableField %s)" s
  | Form.TypeApplication (s, g) ->
      Format.fprintf fmt "@[<v 2>(TypeApplication %s@ %a)@]" s pp_ast g
  | Form.Type f -> (
    match f with
    | Form.Symbol s ->
        Format.fprintf fmt "(Type %s)" s
    | _ ->
        Format.fprintf fmt "@[<v 2>(Type@ %a)@]" pp_ast f )
