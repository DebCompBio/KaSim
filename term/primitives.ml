(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

module Transformation = struct
  type 'a t =
    | Agent of 'a
    | Freed of 'a Instantiation.site
    | Linked of 'a Instantiation.site * 'a Instantiation.site
    | NegativeWhatEver of 'a Instantiation.site
    | PositiveInternalized of
        'a * Instantiation.site_name * Instantiation.internal_state
    | NegativeInternalized of 'a Instantiation.site

  let to_yojson = function
    | Agent a -> `Assoc ["Agent", Matching.Agent.to_yojson a]
    | Freed (a,s) ->
       `Assoc ["Freed", `List [Matching.Agent.to_yojson a; `Int s]]
    | Linked ((a,s),(b,t)) ->
       `Assoc ["Linked",
               `List [Matching.Agent.to_yojson a;`Int s;
                      Matching.Agent.to_yojson b;`Int t]]
    | NegativeWhatEver (a,s) ->
       `Assoc ["NegativeWhatEver", `List [Matching.Agent.to_yojson a; `Int s]]
    | PositiveInternalized (a,s,i) ->
       `Assoc ["PositiveInternalized",
               `List [Matching.Agent.to_yojson a;`Int s;`Int i]]
    | NegativeInternalized (a,s) ->
       `Assoc ["NegativeInternalized",`List [Matching.Agent.to_yojson a;`Int s]]

  let of_yojson = function
    | `Assoc ["Agent", a] -> Agent (Matching.Agent.of_yojson a)
    | `Assoc ["Freed", `List [a;`Int s]] ->
       Freed ((Matching.Agent.of_yojson a),s)
    | `Assoc ["Linked",`List [a;(`Int s); b;(`Int t)]] ->
       Linked ((Matching.Agent.of_yojson a,s),(Matching.Agent.of_yojson b,t))
    | `Assoc ["NegativeWhatEver",`List [a;`Int s]] ->
       NegativeWhatEver (Matching.Agent.of_yojson a,s)
    | `Assoc ["PositiveInternalized",`List [a;`Int s;`Int i]] ->
       PositiveInternalized (Matching.Agent.of_yojson a,s,i)
    | `Assoc ["NegativeInternalized",`List [a;`Int s]] ->
       NegativeInternalized (Matching.Agent.of_yojson a,s)
    | x -> raise (Yojson.Basic.Util.Type_error ("Invalid agent",x))

  let rename id inj = function
    | Freed (p,s) as x ->
      let p' = Matching.Agent.rename id inj p in
      if p == p' then x else Freed (p',s)
    | NegativeWhatEver (p,s) as x ->
      let p' = Matching.Agent.rename id inj p in
      if p == p' then x else NegativeWhatEver (p',s)
    | Linked ((p1,s1),(p2,s2)) as x ->
      let p1' = Matching.Agent.rename id inj p1 in
      let p2' = Matching.Agent.rename id inj p2 in
      if p1 == p1' && p2 == p2' then x else Linked ((p1',s1),(p2',s2))
    | PositiveInternalized (p,s,i) as x ->
      let p' = Matching.Agent.rename id inj p in
      if p == p' then x else PositiveInternalized (p',s,i)
    | NegativeInternalized (p,s) as x ->
      let p' = Matching.Agent.rename id inj p in
      if p == p' then x else NegativeInternalized (p',s)
    | Agent p as x ->
      let p' = Matching.Agent.rename id inj p in
      if p == p' then x else Agent p'

  let concretize inj2graph = function
    | Agent n -> Agent (Matching.Agent.concretize inj2graph n)
    | Freed (n,s) -> Freed (Matching.Agent.concretize inj2graph n,s)
    | Linked ((n,s),(n',s')) ->
      Linked ((Matching.Agent.concretize inj2graph n,s),
              (Matching.Agent.concretize inj2graph n',s'))
    | NegativeWhatEver (n,s) ->
      NegativeWhatEver (Matching.Agent.concretize inj2graph n,s)
    | PositiveInternalized (n,s,i) ->
      PositiveInternalized (Matching.Agent.concretize inj2graph n,s,i)
    | NegativeInternalized (n,s) ->
      NegativeInternalized (Matching.Agent.concretize inj2graph n,s)

  let raw_mixture_of_fresh sigs l =
    let (_,fresh,mixte,existings) =
      List.fold_left
        (fun (fid,fr,mi,ex) -> function
           | (NegativeWhatEver _ | NegativeInternalized _ |
              Agent (Matching.Agent.Existing _) |
              Linked ((Matching.Agent.Existing _,_),(Matching.Agent.Existing _,_)) |
              PositiveInternalized (Matching.Agent.Existing _,_,_) |
              Freed (Matching.Agent.Existing _,_)  as x) -> (fid,fr,mi,x::ex)
           | Agent (Matching.Agent.Fresh (a_type,id)) ->
             let si = Signature.arity sigs a_type in
             let n = {
               Raw_mixture.a_type;
               Raw_mixture.a_ports = Array.make si Raw_mixture.FREE;
               Raw_mixture.a_ints = Array.make si None;
             } in
             (fid,Mods.IntMap.add id n fr,mi,ex)
           | PositiveInternalized (Matching.Agent.Fresh (_,id),s,i) ->
             let () = match Mods.IntMap.find_option id fr with
               | Some a -> a.Raw_mixture.a_ints.(s) <- Some i
               | None -> () in
             (fid,fr,mi,ex)
           | Freed (Matching.Agent.Fresh _,_) -> (fid,fr,mi,ex)
           | Linked ((Matching.Agent.Fresh (_,id),s1),
                      (Matching.Agent.Existing _ as a,s2)) |
             Linked ((Matching.Agent.Existing _ as a,s2),
                     (Matching.Agent.Fresh (_,id),s1)) ->
             let () = match Mods.IntMap.find_option id fr with
               | Some a -> a.Raw_mixture.a_ports.(s1) <- Raw_mixture.VAL fid
               | None -> () in
             (succ fid,fr,(a,s2,fid)::mi,ex)
           | Linked ((Matching.Agent.Fresh (_,id1),s1),
                     (Matching.Agent.Fresh (_,id2),s2)) ->
             let () = match Mods.IntMap.find_option id1 fr with
               | Some a -> a.Raw_mixture.a_ports.(s1) <- Raw_mixture.VAL fid
               | None -> () in
             let () = match Mods.IntMap.find_option id2 fr with
               | Some a -> a.Raw_mixture.a_ports.(s2) <- Raw_mixture.VAL fid
               | None -> () in
             (succ fid,fr,mi,ex)
        ) (1,Mods.IntMap.empty,[],[]) l in
    (Mods.IntMap.bindings fresh,mixte,List.rev existings)

  let print ?sigs f = function
    | Agent p ->
      Format.fprintf f "@[%a@]" (Matching.Agent.print ?sigs) p
    | Freed (p,s) ->
      Format.fprintf
        f "@[%a.%a = %t@]" (Matching.Agent.print ?sigs) p
        (Matching.Agent.print_site ?sigs p) s Pp.bottom
    | NegativeWhatEver (p,s) ->
      Format.fprintf
        f "@[%a.%a = ???@]" (Matching.Agent.print ?sigs) p
        (Matching.Agent.print_site ?sigs p) s
    | Linked ((p1,s1),(p2,s2)) ->
      Format.fprintf
        f "@[%a.%a = %a.%a@]"
        (Matching.Agent.print ?sigs) p1 (Matching.Agent.print_site ?sigs p1) s1
        (Matching.Agent.print ?sigs) p2 (Matching.Agent.print_site ?sigs p2) s2
    | PositiveInternalized (p,s,i) ->
      Format.fprintf
        f "@[%a.%a =@]" (Matching.Agent.print ?sigs) p
        (Matching.Agent.print_internal ?sigs p s) i
    | NegativeInternalized (p,s) ->
      Format.fprintf
        f "@[%a.%a~ =@]" (Matching.Agent.print ?sigs) p
        (Matching.Agent.print_site ?sigs p) s
end

type elementary_rule = {
  rate : Alg_expr.t Locality.annot;
  unary_rate : (Alg_expr.t Locality.annot * Alg_expr.t option) option;
  connected_components : Pattern.id array; (*id -> cc*)
  removed : Instantiation.abstract Transformation.t list;
  inserted : Instantiation.abstract Transformation.t list;
  delta_tokens : (Alg_expr.t Locality.annot * int) list;
  syntactic_rule : int;
  (** [0] means generated for perturbation. *)
  instantiations : Instantiation.abstract Instantiation.event;
}

let rule_to_yojson r =
  let alg_expr_to_json =
    Alg_expr.e_to_yojson
      (JsonUtil.of_list (JsonUtil.of_array Pattern.id_to_yojson))
      JsonUtil.of_int in
  `Assoc [
     "rate", Locality.annot_to_json alg_expr_to_json r.rate;
     "unary_rate",
     JsonUtil.of_option
       (JsonUtil.of_pair
          (Locality.annot_to_json alg_expr_to_json)
          (JsonUtil.of_option alg_expr_to_json))
       r.unary_rate;
      "connected_components",
      (JsonUtil.of_array Pattern.id_to_yojson) r.connected_components;
      "removed", JsonUtil.of_list Transformation.to_yojson r.removed;
      "inserted", JsonUtil.of_list Transformation.to_yojson r.inserted;
      "delta_tokens",
      JsonUtil.of_list
        (JsonUtil.of_pair ~lab1:"val" ~lab2:"tok"
                          (Locality.annot_to_json alg_expr_to_json)
                          JsonUtil.of_int)
        r.delta_tokens;
      "syntactic_rule", `Int r.syntactic_rule;
      "instantiations",
      Instantiation.event_to_json Matching.Agent.to_yojson r.instantiations;
   ]

let rule_of_yojson r =
  let alg_expr_of_json =
    Alg_expr.e_of_yojson
      (JsonUtil.to_list (JsonUtil.to_array Pattern.id_of_yojson))
      (JsonUtil.to_int ?error_msg:None) in
  match r with
  | ((`Assoc l):Yojson.Basic.json) as x ->
     begin
       try {
           rate = Locality.annot_of_json alg_expr_of_json (List.assoc "rate" l);
           unary_rate =
             (try
                JsonUtil.to_option
                  (JsonUtil.to_pair
                     (Locality.annot_of_json alg_expr_of_json)
                     (JsonUtil.to_option alg_expr_of_json))
                  (List.assoc "unary_rate" l)
              with Not_found -> None);
           connected_components =
             (match (List.assoc "connected_components" l) with
             |`List o ->
               Tools.array_map_of_list Pattern.id_of_yojson o
             | _ -> raise Not_found);
           removed =
             JsonUtil.to_list Transformation.of_yojson (List.assoc "removed" l);
           inserted =
             JsonUtil.to_list Transformation.of_yojson
                              (List.assoc "inserted" l);
           delta_tokens =
             JsonUtil.to_list
               (JsonUtil.to_pair ~lab1:"val" ~lab2:"tok"
                                 (Locality.annot_of_json alg_expr_of_json)
                                 (JsonUtil.to_int ?error_msg:None))
               (List.assoc "delta_tokens" l);
           syntactic_rule = JsonUtil.to_int (List.assoc "syntactic_rule" l);
           instantiations =
             Instantiation.event_of_json Matching.Agent.of_yojson
                                         (List.assoc "instantiations" l);
         }
       with Not_found ->
         raise (Yojson.Basic.Util.Type_error ("Not a correct elementary rule",x))
     end
  | x -> raise (Yojson.Basic.Util.Type_error ("Not a correct elementary rule",x))


type 'alg_expr print_expr =
    Str_pexpr of string Locality.annot
  | Alg_pexpr of 'alg_expr Locality.annot

let print_expr_to_yojson f_mix f_var = function
  | Str_pexpr s -> Locality.annot_to_json JsonUtil.of_string s
  | Alg_pexpr a -> Locality.annot_to_json (Alg_expr.e_to_yojson f_mix f_var) a

let print_expr_of_yojson f_mix f_var x =
  try Str_pexpr (Locality.annot_of_json (JsonUtil.to_string ?error_msg:None) x)
  with Yojson.Basic.Util.Type_error _ ->
  try Alg_pexpr (Locality.annot_of_json (Alg_expr.e_of_yojson f_mix f_var) x)
  with Yojson.Basic.Util.Type_error _ ->
    raise (Yojson.Basic.Util.Type_error ("Incorrect print expr",x))

let map_expr_print f x =
  List.map (function
      | Str_pexpr _ as x -> x
      | Alg_pexpr e -> Alg_pexpr (f e)) x

type flux_kind = ABSOLUTE | RELATIVE | PROBABILITY

let flux_kind_to_yojson = function
  | ABSOLUTE -> `String "ABSOLUTE"
  | RELATIVE -> `String "RELATIVE"
  | PROBABILITY -> `String "PROBABILITY"

let flux_kind_of_yojson = function
  | `String "ABSOLUTE" -> ABSOLUTE
  | `String "RELATIVE" -> RELATIVE
  | `String "PROBABILITY" -> PROBABILITY
  | x -> raise
           (Yojson.Basic.Util.Type_error ("Incorrect flux_kind",x))

type modification =
    ITER_RULE of Alg_expr.t Locality.annot * elementary_rule
  | UPDATE of int * Alg_expr.t Locality.annot
  | SNAPSHOT of Alg_expr.t print_expr list
  | STOP of Alg_expr.t print_expr list
  | CFLOW of string option * Pattern.id array *
             Instantiation.abstract Instantiation.test list list
  | FLUX of flux_kind * Alg_expr.t print_expr list
  | FLUXOFF of Alg_expr.t print_expr list
  | CFLOWOFF of Pattern.id array
  | PLOTENTRY
  | PRINT of Alg_expr.t print_expr list * Alg_expr.t print_expr list

type perturbation =
  { precondition:
      (Pattern.id array list,int) Alg_expr.bool Locality.annot;
    effect : modification list;
    abort : (Pattern.id array list,int)
      Alg_expr.bool Locality.annot option;
  }

let exists_modification check l =
  Array.fold_left (fun acc p -> acc || List.exists check p.effect) false l

let extract_connected_components_expr acc e =
  List.fold_left
    (List.fold_left (fun acc a -> List.rev_append (Array.to_list a) acc))
    acc (Alg_expr.extract_connected_components e)

let extract_connected_components_bool e =
  List.fold_left
    (List.fold_left (fun acc a -> List.rev_append (Array.to_list a) acc))
    [] (Alg_expr.extract_connected_components_bool e)

let extract_connected_components_rule acc r =
  let a =
    List.fold_left
      (fun acc (x,_) -> extract_connected_components_expr acc x)
      acc r.delta_tokens in
  let b = match r.unary_rate with
    | None -> a
    | Some (x,_) -> extract_connected_components_expr a x in
  let c = extract_connected_components_expr b r.rate in
  List.rev_append (Array.to_list r.connected_components) c

let extract_connected_components_print acc x =
  List.fold_left (fun acc -> function
      | Str_pexpr _ -> acc
      | Alg_pexpr e -> extract_connected_components_expr acc e)
    acc x

let extract_connected_components_modification acc = function
  | ITER_RULE (e,r) ->
    extract_connected_components_rule
      (extract_connected_components_expr acc e) r
  | UPDATE (_,e) -> extract_connected_components_expr acc e
  | SNAPSHOT p | STOP p
  | FLUX (_,p) | FLUXOFF p -> extract_connected_components_print acc p
  | PRINT (fn,p) ->
    extract_connected_components_print
      (extract_connected_components_print acc p) fn
  | CFLOW (_,x,_) | CFLOWOFF x -> List.rev_append (Array.to_list x) acc
  | PLOTENTRY -> acc

let extract_connected_components_modifications l =
  List.fold_left extract_connected_components_modification [] l

let map_expr_rule f x = {
  rate = f x.rate;
  unary_rate = Option_util.map (fun (x,d) -> (f x,d)) x.unary_rate;
  connected_components = x.connected_components;
  removed = x.removed;
  inserted = x.inserted;
  delta_tokens = List.map (fun (x,t) -> (f x,t)) x.delta_tokens;
  syntactic_rule = x.syntactic_rule;
  instantiations = x.instantiations;
}

let map_expr_modification f = function
  | ITER_RULE (e,r) -> ITER_RULE (f e, map_expr_rule f r)
  | UPDATE (i,e) -> UPDATE (i,f e)
  | SNAPSHOT p -> SNAPSHOT (map_expr_print f p)
  | STOP p -> STOP (map_expr_print f p)
  | PRINT (fn,p) -> PRINT (map_expr_print f fn, map_expr_print f p)
  | FLUX (b,p) -> FLUX (b,map_expr_print f p)
  | FLUXOFF p -> FLUXOFF (map_expr_print f p)
  | (CFLOW _ | CFLOWOFF _ | PLOTENTRY) as x -> x

let map_expr_perturbation f_alg f_bool x =
  { precondition = f_bool x.precondition;
    effect = List.map (map_expr_modification f_alg) x.effect;
    abort = Option_util.map f_bool x.abort;
  }

let stops_of_perturbation algs_deps x =
  let stopping_time =
    try Alg_expr.stops_of_bool algs_deps (fst x.precondition)
    with ExceptionDefn.Unsatisfiable ->
      raise
        (ExceptionDefn.Malformed_Decl
           ("Precondition of perturbation is using an invalid equality test on time, I was expecting a preconditon of the form [T]=n"
           ,snd x.precondition))
  in
  match x.abort with
  | None -> stopping_time
  | Some (x,pos) ->
    try stopping_time@Alg_expr.stops_of_bool algs_deps x
    with ExceptionDefn.Unsatisfiable ->
      raise
        (ExceptionDefn.Malformed_Decl
           ("Precondition of perturbation is using an invalid equality test on time, I was expecting a preconditon of the form [T]=n"
           ,pos))
