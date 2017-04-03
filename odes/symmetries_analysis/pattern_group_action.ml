(**
   * pattern_group_action.ml
   * openkappa
   * Jérôme Feret & Ly Kim Quyen, projet Antique, INRIA Paris-Rocquencourt
   *
   * Creation: 2016, the 5th of December
   * Last modification: Time-stamp: <Apr 03 2017>
   *
   * Abstract domain to record relations between pair of sites in connected agents.
   *
   * Copyright 2010,2011,2012,2013,2014,2015,2016 Institut National de Recherche
   * en Informatique et en Automatique.
   * All rights reserved.  This file is distributed
   * under the terms of the GNU Library General Public License *)

let get_internal_state_partition a = a.Symmetries_sig.over_internal_states

let get_binding_state_partition a = a.Symmetries_sig.over_binding_states

let get_full_partition a = a.Symmetries_sig.over_full_states

(*
(int -> 'a -> 'b) ->
(int -> 'b -> 'a -> unit) ->
('b -> 'b -> int) -> int list -> 'a -> 'a
*)
let normalize_in_agent_gen
    (get:int -> 'a -> 'b)
    (set:int -> 'b -> 'a -> unit)
    (cmp: 'b -> 'b -> int)
    equiv_class agent =
  let asso = List.rev_map (fun x -> x, get x agent) equiv_class in
  let asso = List.sort (fun (_, x) (_, y) -> cmp x y) asso in
  let asso' = List.rev_map2 (fun k (_, value) -> (k, value)) equiv_class asso in
  let () = List.iter (fun (k, value) -> set k value agent) asso' in
  agent

(*
('a -> int) ->
(int -> 'a -> 'b) ->
(int -> 'b -> 'a -> unit) ->
('b -> 'b -> int) ->
('c -> int list list) -> 'c array -> 'a list -> 'a list
*)
let normalize_gen get_type get set cmp which symmetries raw_mixture =
  let raw_mixture =
    List.rev_map
      (fun agent ->
         let agent_type = get_type agent in
         let partition =
           try
             which (symmetries.(agent_type))
           with
             _ -> []
         in
         let agent =
           List.fold_left (fun agent equiv_class ->
               normalize_in_agent_gen get set cmp equiv_class agent
             ) agent partition
         in
         agent
      ) (List.rev raw_mixture)
  in
  raw_mixture

(*int Symmetries_sig.site_partition array ->
  Raw_mixture.agent list -> Raw_mixture.agent list*)

let normalize_internal_states equiv_class raw_mixture =
  normalize_gen
    (fun agent -> agent.Raw_mixture.a_type)
    (fun i agent -> agent.Raw_mixture.a_ints.(i))
    (fun i data agent -> agent.Raw_mixture.a_ints.(i) <- data)
    compare
    get_internal_state_partition
    equiv_class
    raw_mixture

let add i j map =
  let old =
    Mods.IntMap.find_default [] i map
  in
  Mods.IntMap.add i (j::old) map

let pop i map =
  match Mods.IntMap.find_option i map with
  | None ->
    raise
      (ExceptionDefn.Internal_Error ("Illegal map", Locality.dummy))
  | Some [a; b] -> Mods.IntMap.add i [b] map, a
  | Some [a] -> Mods.IntMap.remove i map,a
  | Some _ ->
    raise
      (ExceptionDefn.Internal_Error ("Illegal map", Locality.dummy))

(*
Raw_mixture.agent list ->
(Raw_mixture.agent * (int * int) option array) list
*)
let enrich_binding_state raw_mixture =
  let map =
    List.fold_left
      (fun map agent ->
         let agent_type = agent.Raw_mixture.a_type in
         let bonds = agent.Raw_mixture.a_ports in
         Tools.array_fold_lefti
           (fun site map port ->
              match port with
              | Raw_mixture.FREE -> map
              | Raw_mixture.VAL i -> add i (agent_type, site) map)
           map bonds
      ) Mods.IntMap.empty raw_mixture
  in
  let refined_raw_mixture_rev, map =
    List.fold_left
      (fun (list, map) agent ->
         let array = Array.make (Array.length agent.Raw_mixture.a_ports) None in
         let map =
           Tools.array_fold_lefti
             (fun site map port ->
                match port with
                | Raw_mixture.FREE -> map
                | Raw_mixture.VAL i ->
                  let map, binding_type = pop i map in
                  let () = array.(site) <- Some binding_type in
                  map) map agent.Raw_mixture.a_ports
         in
         ((agent, array) :: list, map))
      ([], map) raw_mixture
  in
  let () =
    if not (Mods.IntMap.is_empty map)
    then
      raise
        (ExceptionDefn.Internal_Error ("Illegal map", Locality.dummy))
  in
  List.rev refined_raw_mixture_rev

let remove_binding_state refined_raw_mixture =
  List.rev_map fst (List.rev refined_raw_mixture)

(*
int list -> 'a option array -> int list list -> int list list
*)
let refine_class equiv_class agent output =
  match equiv_class with
  | [] -> output
  | h :: t ->
    begin
      let rec aux ref_value to_do current_class output =
        match to_do with
        | [] ->
          begin
            match ref_value with
            | None -> output
            | Some _ -> current_class :: output
          end
        | h :: t ->
          if agent.(h) = ref_value
          then
            aux ref_value t (h :: current_class) output
          else
            match ref_value with
            | None -> aux (agent.(h)) t [h] output
            | Some _ -> aux (agent.(h)) t [h] (current_class :: output)
      in
      aux (agent.(h)) t [h] output
    end

(*
('a -> int list list) ->
'a array ->
(Raw_mixture.agent * 'b option array) list -> int list list list
*)
let refine_partition which symmetries refined_raw_mixture =
  List.rev_map (fun (agent, agent') ->
      let ag_type = agent.Raw_mixture.a_type in
      List.fold_left (fun output equiv_class ->
          refine_class equiv_class agent' output)
        [] (which symmetries.(ag_type))
    ) (List.rev refined_raw_mixture)

(*
('a -> 'b -> 'c) ->
('d -> 'c -> 'b -> unit) -> ('a * 'd) list -> 'b -> 'b
*)

let apply_permutation get set perm agent =
  let assign = List.rev_map (fun (i, j) -> (j, get i agent)) perm in
  let () = List.iter (fun (j, data) -> set j data agent) assign in
  agent

(*
('a -> 'b -> 'c) ->
('d -> 'c -> 'b -> unit) -> ('d * 'a) list -> 'b -> 'b
*)
let apply_permutation_inv get set perm agent =
  let perm_inv = List.rev_map (fun (a, b) -> (b, a)) perm in
  apply_permutation get set perm_inv agent

(*
(int -> 'a -> 'b) ->
(int -> 'b -> 'a -> unit) ->
('a -> 'c -> 'c) -> int list list -> 'a -> 'c -> 'c
*)
let rec fold_symmetries_over_agent get set f covering agent accu =
  match covering with
  | h :: t ->
    Tools.fold_over_permutations (fun perm accu ->
        let perm = List.rev_map2 (fun a b -> (a,b)) h perm in
        let agent = apply_permutation get set perm agent in
        let accu = fold_symmetries_over_agent get set f t agent accu in
        let _ = apply_permutation_inv get set perm agent in
        accu)
      h accu
  | [] -> f agent accu

(*
(int -> 'a -> 'b) ->
(int -> 'b -> 'a -> unit) ->
('a list -> 'c -> 'c) -> 'a list -> int list list list -> 'c -> 'c
*)
let fold_symmetries_over_raw_mixture get set f raw_mixture covering_list accu =
  let raw_mixture0 = raw_mixture in
  let rec aux get set f raw_mixture covering_list accu =
    match raw_mixture, covering_list with
    | [], [] -> f raw_mixture0 accu
    | _::_, [] | [], _::_ ->
      raise
        (ExceptionDefn.Internal_Error
           ("Arguments of fold_symmetries_over_rw_mixture shall have the same length",
            Locality.dummy))
    | h :: t, h' :: t' ->
      fold_symmetries_over_agent
        get set
        (fun agent accu -> aux get set f t t' accu)
        h' h accu
  in aux get set f raw_mixture covering_list accu

let copy raw_mixture =
  List.rev_map
    (fun agents ->
       {
         agents with
         Raw_mixture.a_ints = Array.copy agents.Raw_mixture.a_ints;
         Raw_mixture.a_ports = Array.copy agents.Raw_mixture.a_ports
       })
    (List.rev raw_mixture)

(*
(int ->
Raw_mixture.agent * (int * int) option array -> 'a) ->
(int -> 'a -> Raw_mixture.agent * (int * int) option array -> unit) ->
('a -> 'a -> int) ->
(int -> Raw_mixture.agent -> 'b) ->
(int -> 'b -> Raw_mixture.agent -> unit) ->
('c -> int list list) ->
LKappa_auto.cache ->
'c array ->
Raw_mixture.agent list ->
LKappa_auto.cache * Raw_mixture.agent list
*)
let normalize_with_binding_states get1 set1 cmp get2 set2 get_partition
    rule_cache symmetries raw_mixture =
  let refined_raw_mixture = enrich_binding_state raw_mixture in
  let refined_raw_mixture =
    normalize_gen
      (fun (agent, _) -> agent.Raw_mixture.a_type)
      get1 set1 cmp
      get_partition
      symmetries
      refined_raw_mixture
  in
  let covering_list =
    refine_partition
      get_partition
      symmetries
      refined_raw_mixture
  in
  let raw_mixture = remove_binding_state refined_raw_mixture in
  let rule_cache, hash =
    LKappa_auto.cannonic_form rule_cache
      (Patterns_extra.raw_mixture_to_lkappa_rule raw_mixture)
  in
  let rule_cache, (_, raw_mixture) =
    fold_symmetries_over_raw_mixture
      get2 set2
      (fun raw_mixture (rule_cache, (best_hash, best_raw_mixture)) ->
         let rule_cache, hash =
           LKappa_auto.cannonic_form
             rule_cache
             (Patterns_extra.raw_mixture_to_lkappa_rule raw_mixture)
         in
         if compare hash best_hash < 0
         then
           (rule_cache, (hash, copy raw_mixture))
         else
           (rule_cache, (best_hash, best_raw_mixture)))
      raw_mixture
      covering_list
      (rule_cache, (hash, copy raw_mixture))
  in
  rule_cache, raw_mixture

(*
LKappa_auto.cache ->
int Symmetries_sig.site_partition array ->
Raw_mixture.agent list ->
LKappa_auto.cache * Raw_mixture.agent list
*)
let normalize_binding_states rule_cache symmetries raw_mixture =
  normalize_with_binding_states
    (fun i (agent, agent') ->
       agent.Raw_mixture.a_ports.(i),
       agent'.(i))
    (fun i (data, data') (agent, agent') ->
       agent.Raw_mixture.a_ports.(i) <- data;
       agent'.(i) <- data')
    (fun (_, a) (_, b) -> compare a b)
    (fun i agent -> agent.Raw_mixture.a_ports.(i))
    (fun i data agent -> agent.Raw_mixture.a_ports.(i) <- data)
    get_binding_state_partition
    rule_cache symmetries raw_mixture

(*
LKappa_auto.cache ->
int Symmetries_sig.site_partition array ->
Raw_mixture.agent list ->
LKappa_auto.cache * Raw_mixture.agent list
*)
let normalize_full rule_cache symmetries raw_mixture =
  normalize_with_binding_states
    (fun i (agent, agent') ->
       (agent.Raw_mixture.a_ints.(i),
        agent.Raw_mixture.a_ports.(i)),
       agent'.(i))
    (fun i ((data_int, data_port), data') (agent, agent') ->
       agent.Raw_mixture.a_ints.(i) <- data_int;
       agent.Raw_mixture.a_ports.(i) <- data_port;
       agent'.(i) <- data')
    (fun ((a, _), a') ((b, _), b') -> compare (a, a') (b, b'))
    (fun i agent ->
       agent.Raw_mixture.a_ints.(i),
       agent.Raw_mixture.a_ports.(i))
    (fun i (data_int, data_port) agent ->
       agent.Raw_mixture.a_ints.(i) <- data_int;
       agent.Raw_mixture.a_ports.(i) <- data_port)
    get_full_partition
    rule_cache symmetries raw_mixture

(*
LKappa_auto.cache ->
int Symmetries_sig.site_partition array ->
Raw_mixture.agent list ->
LKappa_auto.cache * Raw_mixture.agent list
*)
let normalize_raw_mixture rule_cache symmetries raw_mixture =
  let rule_cache, raw_mixture =
    normalize_full rule_cache symmetries raw_mixture
  in
  let raw_mixture = normalize_internal_states symmetries raw_mixture in
  normalize_binding_states rule_cache symmetries raw_mixture

let normalize_species ?parameters signature rule_cache cache symmetries cc =
  match
    Patterns_extra.species_to_raw_mixture ?parameters signature cc
  with
  | Some (raw_mixture, unspec) ->
    let rule_cache, raw_mixture =
      normalize_raw_mixture rule_cache symmetries
        raw_mixture
    in
    let a, b, _ =
      Patterns_extra.raw_mixture_to_species
        ?parameters ~signature cache raw_mixture unspec
    in
    rule_cache, a, b
  | None -> rule_cache, cache, cc

(******************************************************)

let is_pattern_invariant_internal_states_permutation
    ~parameters ~env
    ~agent_type ~site1 ~site2
    id cache =
  let lkappa_rule =
    Patterns_extra.pattern_id_to_lkappa_rule parameters env id
  in
  LKappa_group_action.is_invariant_internal_states_permutation
    ~parameters
    ~env
    ~agent_type
    ~site1
    ~site2
    lkappa_rule
    cache

let is_pattern_invariant_binding_states_permutation
    ~parameters ~env
    ~agent_type ~site1 ~site2
    id cache =
  let lkappa_rule =
    Patterns_extra.pattern_id_to_lkappa_rule parameters env id
  in
  LKappa_group_action.is_invariant_binding_states_permutation
    ~parameters
    ~env
    ~agent_type
    ~site1
    ~site2
    lkappa_rule
    cache

let is_pattern_invariant_full_states_permutation
    ~parameters ~env
    ~agent_type ~site1 ~site2
    id cache =
  let lkappa_rule =
    Patterns_extra.pattern_id_to_lkappa_rule parameters env id
  in
  LKappa_group_action.is_invariant_full_states_permutation
    ~parameters
    ~env
    ~agent_type
    ~site1
    ~site2
    lkappa_rule
    cache

let equiv_class_of_a_species
    ~parameters ~env
    ~partitions_internal_states
    ~partitions_binding_states
    ~partitions_full_states
    cache
    preenv
    seen
    species =
  let rule =
    Patterns_extra.species_to_lkappa_rule
      parameters env species
  in
  let cache, seen, rule_class =
    LKappa_group_action.equiv_class
      ~parameters
      ~env
      cache seen rule
      ~partitions_internal_states
      ~partitions_binding_states
      ~partitions_full_states
  in
  let preenv, l =
    List.fold_left
      (fun (preenv,l) rule ->
         let preenv, species, _ =
           Patterns_extra.raw_mixture_to_species
             preenv rule.LKappa.r_created []
         in
         preenv,(species::l))
      (preenv, [])
      (List.rev rule_class)
  in
  cache, preenv, seen, l
