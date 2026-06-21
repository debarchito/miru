let rec pp_ast fmt = function
  | Reader.Form.Unit -> Format.pp_print_string fmt "Unit"
  | Reader.Form.Bool v -> Format.fprintf fmt "(Bool %b)" v
  | Reader.Form.Int n -> Format.fprintf fmt "(Int %s)" (Int64.to_string n)
  | Reader.Form.Float f -> Format.fprintf fmt "(Float %s)" (string_of_float f)
  | Reader.Form.String s -> Format.fprintf fmt "(String %S)" s
  | Reader.Form.Symbol s -> Format.fprintf fmt "(Symbol %s)" s
  | Reader.Form.List fs ->
      Format.fprintf fmt "@[<v 2>(List";
      List.iter (fun f -> Format.fprintf fmt "@ %a" pp_ast f) fs;
      Format.fprintf fmt ")@]"
  | Reader.Form.Tuple fs ->
      Format.fprintf fmt "@[<v 2>(Tuple";
      List.iter (fun f -> Format.fprintf fmt "@ %a" pp_ast f) fs;
      Format.fprintf fmt ")@]"
  | Reader.Form.RecordExpression pairs ->
      Format.fprintf fmt "@[<v 2>(RecordExpression";
      List.iter
        (fun (k, v) -> Format.fprintf fmt "@ %a %a" pp_ast k pp_ast v)
        pairs;
      Format.fprintf fmt ")@]"
  | Reader.Form.Record (name, body) ->
      Format.fprintf fmt "@[<v 2>(Record %s@ %a)@]" name pp_ast body
  | Reader.Form.AbstractType (name, body) ->
      Format.fprintf fmt "@[<v 2>(AbstractType %s@ %a)@]" name pp_ast body
  | Reader.Form.Constructor (name, payload) -> (
      match payload with
      | None -> Format.fprintf fmt "(Constructor %s)" name
      | Some p ->
          Format.fprintf fmt "@[<v 2>(Constructor %s@ %a)@]" name pp_ast p)
  | Reader.Form.Variant (name, cases) ->
      Format.fprintf fmt "@[<v 2>(Variant %s" name;
      List.iter (fun c -> Format.fprintf fmt "@ %a" pp_ast c) cases;
      Format.fprintf fmt ")@]"
  | Reader.Form.Tag (name, body) ->
      Format.fprintf fmt "@[<v 2>(Tag %s@ %a)@]" name pp_ast body
  | Reader.Form.Fn fs ->
      Format.fprintf fmt "@[<v 2>(Fn";
      List.iter (fun f -> Format.fprintf fmt "@ %a" pp_ast f) fs;
      Format.fprintf fmt ")@]"
  | Reader.Form.Quote f -> Format.fprintf fmt "@[<v 2>(Quote@ %a)@]" pp_ast f
  | Reader.Form.Quasiquote f ->
      Format.fprintf fmt "@[<v 2>(Quasiquote@ %a)@]" pp_ast f
  | Reader.Form.Unquote f ->
      Format.fprintf fmt "@[<v 2>(Unquote@ %a)@]" pp_ast f
  | Reader.Form.Splice f -> Format.fprintf fmt "@[<v 2>(Splice@ %a)@]" pp_ast f
  | Reader.Form.Field s -> Format.fprintf fmt "(Field %s)" s
  | Reader.Form.MutableField s -> Format.fprintf fmt "(MutableField %s)" s
  | Reader.Form.TypeApplication (s, g) ->
      Format.fprintf fmt "@[<v 2>(TypeApplication %s@ %a)@]" s pp_ast g
  | Reader.Form.Type f -> (
      match f with
      | Reader.Form.Symbol s -> Format.fprintf fmt "(Type %s)" s
      | _ -> Format.fprintf fmt "@[<v 2>(Type@ %a)@]" pp_ast f)
