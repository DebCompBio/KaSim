(**
  * remanent_state.ml
  * openkappa
  * Jérôme Feret, projet Abstraction/Antique, INRIA Paris-Rocquencourt
  *
  * Creation: June, the 25th of 2016
  * Last modification: Time-stamp: <Aug 18 2017>
  * *
  *
  * Copyright 2010,2011 Institut National de Recherche en Informatique et
  * en Automatique.  All rights reserved.  This file is distributed
  * under the terms of the GNU Library General Public License *)

(**********************)
(* compilation result *)
(**********************)

type compilation = Ast.parsing_compil

type init =
  | Compil of compilation
  | Files of string list

type initial_state = (Alg_expr.t * Primitives.elementary_rule * Locality.t) list

type refined_compilation =
  (Ckappa_sig.agent, Ckappa_sig.mixture, Ckappa_sig.mixture, string,
   Ckappa_sig.direction * Ckappa_sig.mixture Ckappa_sig.rule,unit) Ast.compil

type quark_map = Quark_type.quarks

type rule_id = int
type var_id =  int

(**************)
(* JSon labels*)
(**************)

let accuracy_string = "accuracy"
let map = "map"
let site="site name"
let stateslist="states list"
let interface="interface"
let agent="agent name"
let contactmap="contact map"
let dead_rules = "dead rules"
let contactmaps="contact maps"
let influencemaps="influence maps"
let separating_transitions = "separating transitions"
let errors = "errors"



type dead_rules = Public_data.dead_rules

let info_to_rule (s1,loc,s2,id) =
  {
    Public_data.rule_id = Ckappa_sig.int_of_rule_id id ;
    Public_data.rule_position = loc;
    Public_data.rule_label = s1 ;
    Public_data.rule_ast=s2
  }

type dead_agents = Ckappa_sig.c_agent_name list

type separating_transitions =
  (string * Ckappa_sig.c_rule_id * string) list

let separating_transitions_to_json =
  JsonUtil.of_list
    (JsonUtil.of_triple
       ~lab1:"s1" ~lab2:"label" ~lab3:"s3"
       JsonUtil.of_string
       Ckappa_sig.rule_id_to_json
       JsonUtil.of_string)


(******************************************************************************)
(******************************************************************************)

(******************************************************************************)

(*********************)
(* refinement lemmas *)
(*********************)

type interface =
  (string option (* internal state *) *
   Ckappa_backend.Ckappa_backend.binding_state option (*binding state*) )
    Wrapped_modules.LoggedStringMap.t

let interface_to_json =
  Wrapped_modules.LoggedStringMap.to_json
    ~lab_key:site ~lab_value:stateslist
    JsonUtil.of_string
    (fun (internal_opt, binding_opt) ->
       JsonUtil.of_pair ~lab1:Public_data.prop ~lab2:Public_data.bind
         (fun internal_opt ->
            JsonUtil.of_option
              (fun internal_state ->
                JsonUtil.of_string internal_state
              ) internal_opt
         )
         (JsonUtil.of_option
            Ckappa_backend.Ckappa_backend.binding_state_to_json)
        (internal_opt, binding_opt)
    )

let interface_of_json
      =
      Wrapped_modules.LoggedStringMap.of_json
        ~lab_key:site ~lab_value:stateslist ~error_msg:interface
          (*json -> elt*)
        (fun json -> JsonUtil.to_string ~error_msg:site json)
          (*json -> 'value*)
        (JsonUtil.to_pair
           ~lab1:Public_data.prop ~lab2:Public_data.bind ~error_msg:"wrong binding state"
           (JsonUtil.to_option
              (JsonUtil.to_string ~error_msg:Public_data.prop)

           )
           (JsonUtil.to_option
              Ckappa_backend.Ckappa_backend.binding_state_of_json)
        )

type agent =
  string * (* agent name *)
  interface

let agent_to_json =
  JsonUtil.of_pair
    ~lab1:agent ~lab2:interface
    JsonUtil.of_string
    interface_to_json

let agent_of_json json = Public_data.agent_gen_of_json interface_of_json json

(***************************************************************************)

let pair_to_json (p: string * string): Yojson.Basic.json =
  JsonUtil.of_pair ~lab1:agent ~lab2:site
    (fun a ->  JsonUtil.of_string a)
    (fun b ->  JsonUtil.of_string b)
    p

let pair_of_json (json:Yojson.Basic.json) : string * string  =
  let (agent_name, site_name) =
    JsonUtil.to_pair ~lab1:agent ~lab2:site
      (fun json_a -> JsonUtil.to_string json_a)
      (fun json_b -> JsonUtil.to_string json_b)
      json
  in
  (agent_name,site_name)

type constraints_list = agent list Public_data.poly_constraints_list


let poly_constraints_list_to_json site_graph_to_json (constraints:constraints_list) =
  JsonUtil.of_list
    (JsonUtil.of_pair
       ~lab1:Public_data.domain_name ~lab2:Public_data.refinements_list
       JsonUtil.of_string
       (JsonUtil.of_list (Public_data.lemma_to_json site_graph_to_json))
    )
    constraints


let lemmas_list_to_json (constraints:constraints_list) =
  `Assoc
    [
      Public_data.refinement_lemmas,
      poly_constraints_list_to_json
        (JsonUtil.of_list agent_to_json) constraints
    ]

let lemmas_list_of_json_gen agent_of_json =
function
| `Assoc l as x ->
  begin
    try
      let json =
        List.assoc Public_data.refinement_lemmas l
      in
      Public_data.poly_constraints_list_of_json
        (JsonUtil.to_list ~error_msg:"site graph" agent_of_json)
        json
    with
    | _ ->
      raise
        (Yojson.Basic.Util.Type_error (JsonUtil.build_msg "refinement lemmas list",x))
  end
| x ->
  raise (Yojson.Basic.Util.Type_error (JsonUtil.build_msg "refinement lemmas list",x))

let lemmas_list_of_json json =
  lemmas_list_of_json_gen agent_of_json json

let lemmas_list_of_json_light json =
  lemmas_list_of_json_gen Public_data.agent_of_json json

(******************************************************************************)
(******************************************************************************)

(****************************)
(* Internal representations *)
(****************************)

type internal_influence_map =
  Ckappa_sig.c_rule_id list *
  Quark_type.Labels.label_set_couple Ckappa_sig.PairRule_setmap.Map.t * Quark_type.Labels.label_set_couple Ckappa_sig.PairRule_setmap.Map.t

type internal_contact_map =
  (Ckappa_sig.c_state list *
   (Ckappa_sig.c_agent_name * Ckappa_sig.c_site_name) list)
    Ckappa_sig.Site_map_and_set.Map.t Ckappa_sig.Agent_map_and_set.Map.t

type ('static, 'dynamic) reachability_result = 'static * 'dynamic

type subviews_info = unit

type flow =
  Ckappa_sig.Site_union_find.t
    Ckappa_sig.Agent_type_quick_nearly_Inf_Int_storage_Imperatif.t

type internal_constraints_list =
  Ckappa_backend.Ckappa_backend.t Public_data.poly_constraints_list

(*******************************************************************)
type symmetric_sites = Symmetries.symmetries option
(*******************************************************************)

type influence_edge = Quark_type.Labels.label_set_couple

type bidirectional_influence_map =
  {
    positive_influence_fwd:
      (Ckappa_sig.c_rule_id * influence_edge) list array;
    positive_influence_bwd:
      (Ckappa_sig.c_rule_id * influence_edge) list array;
    negative_influence_fwd:
      (Ckappa_sig.c_rule_id * influence_edge) list array;
    negative_influence_bwd:
      (Ckappa_sig.c_rule_id * influence_edge) list array;
  }

type distance =
  {
    fwd: int ;
    bwd: int ;
    total: int
  }

type local_influence_map_blackboard =
  {
    blackboard_distance: distance option array;
    blackboard_is_done: bool array;
    blackboard_to_be_explored: bool array
  }

type ('static,'dynamic) state =
  {
    parameters    : Remanent_parameters_sig.parameters ;
    log_info : StoryProfiling.StoryStats.log_info ;
    prehandler: Cckappa_sig.kappa_handler option ;
    handler       : Cckappa_sig.kappa_handler option ;
    init : init ;
    env : Model.t option option ;
    contact_map_int : Contact_map.t option option;
    init_state: initial_state option option ;
    compilation   : compilation option ;
    refined_compilation : refined_compilation option ;
    c_compil : Cckappa_sig.compil option ;
    quark_map: quark_map option ;
    internal_influence_map: internal_influence_map Public_data.AccuracyMap.t ;
    influence_map : Public_data.influence_map Public_data.AccuracyMap.t ;
    bidirectional_influence_map :
      bidirectional_influence_map Public_data.AccuracyMap.t ;
    local_influence_map_blackboard :
      local_influence_map_blackboard option ;
    internal_contact_map: internal_contact_map Public_data.AccuracyMap.t;
    contact_map   : Public_data.contact_map Public_data.AccuracyMap.t ;
    signature     : Signature.s option;
    bdu_handler: Mvbdu_wrapper.Mvbdu.handler ;
    reachability_state: ('static, 'dynamic) reachability_result option ;
    subviews_info: subviews_info option ;
    dead_rules:  dead_rules option ;
    dead_agents: dead_agents option ;
    ode_flow: Ode_fragmentation_type.ode_frag option ;
    ctmc_flow: flow option ;
    errors        : Exception.method_handler ;
    internal_constraints_list : internal_constraints_list option;
    constraints_list : constraints_list option;
    symmetric_sites : symmetric_sites Public_data.AccuracyMap.t;
    separating_transitions : separating_transitions option ;
    graph_scc : Graphs.node list option
  }

let get_graph_scc state =
  state.graph_scc

let set_graph_scc scc state =
  {state with graph_scc = Some scc }


let get_data state =
  state.handler, state.dead_rules, state.separating_transitions

let create_state ?errors ?env ?init_state ?reset parameters init =
  let error =
    match
      errors
    with
    | None -> Exception.empty_error_handler
    | Some error -> error
  in
  let error, handler_bdu =
    if Mvbdu_wrapper.Mvbdu.is_init ()
    then
      match reset with
      | Some true ->
        Mvbdu_wrapper.Mvbdu.reset parameters error
      | None | Some false ->
        Mvbdu_wrapper.Mvbdu.get_handler parameters error
    else
      Mvbdu_wrapper.Mvbdu.init parameters error
  in
  {
    parameters = parameters;
    log_info = StoryProfiling.StoryStats.init_log_info ();
    prehandler = None ;
    handler = None ;
    init = init ;
    env = env ;
    contact_map_int = None;
    init_state = init_state ;
    compilation = None ;
    refined_compilation = None ;
    c_compil = None ;
    quark_map = None ;
    internal_influence_map = Public_data.AccuracyMap.empty ;
    influence_map = Public_data.AccuracyMap.empty ;
    bidirectional_influence_map = Public_data.AccuracyMap.empty ;
    local_influence_map_blackboard = None ;
    internal_contact_map = Public_data.AccuracyMap.empty ;
    contact_map = Public_data.AccuracyMap.empty ;
    signature = None ;
    bdu_handler = handler_bdu ;
    ode_flow = None ;
    ctmc_flow = None ;
    reachability_state = None ;
    subviews_info = None ;
    dead_rules = None ;
    dead_agents = None ;
    errors = error ;
    internal_constraints_list = None;
    constraints_list = None;
    symmetric_sites = Public_data.AccuracyMap.empty;
    separating_transitions = None;
    graph_scc = None
  }

(**************)
(* JSON: main *)
(**************)

let add_to_json f state l =
  (f state) :: l

let annotate map =
  Public_data.AccuracyMap.fold
    (fun x y l -> (x,(x,y))::l)
    map
    []

let add_map get title label to_json state l =
  let map = get state in
  if Public_data.AccuracyMap.is_empty map then l
  else
    let y = annotate (get state) in
      (title, JsonUtil.of_list
         (JsonUtil.of_pair
            ~lab1:accuracy_string
            ~lab2:label
            Public_data.accuracy_to_json
            (fun x ->
               match to_json x with
               | `Assoc [s,m] when s = label -> m
               | x ->
                raise (Yojson.Basic.Util.Type_error (JsonUtil.build_msg title,x)))
         )
         (List.rev y))::l

let get_map empty add of_json label json =
  let l =
    JsonUtil.to_list
      (JsonUtil.to_pair
         ~lab1:accuracy_string
         ~lab2:label ~error_msg:"pair11"
         Public_data.accuracy_of_json
         (fun json ->
            of_json
              (`Assoc [label,json])))
      json
  in
  List.fold_left
    (fun map (x,y) -> add x (snd y) map)
    empty l

let get_contact_map_map state = state.contact_map
let get_influence_map_map state = state.influence_map
let get_constraints_list state = state.constraints_list
(*let get_separating_transitions state = state.separating_transitions*)
let add_errors state l =
  (errors, Exception_without_parameter.to_json state.errors)::l

let add_contact_map_to_json state l
     =
  add_map get_contact_map_map
    contactmaps contactmap Public_data.contact_map_to_json
    state l


let add_influence_map_to_json state l =
  add_map get_influence_map_map
    influencemaps Public_data.influencemap Public_data.influence_map_to_json
    state l


let add_dead_rules_to_json state l =
  match
    state.dead_rules
  with
  | None -> l
  | Some rules ->
    (dead_rules , Public_data.dead_rules_to_json rules)::l

let add_refinements_lemmas_to_json state l =
  match
    get_constraints_list state
  with
  | None -> l
  | Some constraints ->
    (
      Public_data.refinement_lemmas,
      lemmas_list_to_json constraints
    )::l

let get_separating_transitions state = state.separating_transitions
let set_separating_transitions l state =
  {state with separating_transitions = Some l}

let add_separating_transitions state l =
  match
    get_separating_transitions state
  with
  | None -> l
  | Some list ->
    (separating_transitions,
     separating_transitions_to_json list)::l

let to_json state =
  let l = [] in
  let l = add_errors state l in
  let l = add_refinements_lemmas_to_json state l in
  let l = add_dead_rules_to_json state l in
  let l = add_influence_map_to_json state l in
  let l = add_contact_map_to_json state l in
  let l = add_separating_transitions state l in
  ((`Assoc  l): Yojson.Basic.json)

let of_json =
  function
  | `Assoc l as json->
    let errors =
      try
        Exception_without_parameter.of_json (List.assoc errors l)
      with
      | Not_found ->
        raise (Yojson.Basic.Util.Type_error
                 (JsonUtil.build_msg "no error handler",json))
    in
    let contact_maps =
      try
        get_map Public_data.AccuracyMap.empty Public_data.AccuracyMap.add
          Public_data.contact_map_of_json
          contactmap
          (List.assoc contactmaps l)
      with
      | Not_found -> Public_data.AccuracyMap.empty
    in
    let influence_maps =
      try
        get_map Public_data.AccuracyMap.empty Public_data.AccuracyMap.add
          Public_data.influence_map_of_json
          Public_data.influencemap
          (List.assoc influencemaps l)
      with
      | Not_found -> Public_data.AccuracyMap.empty
    in
    let dead_rules =
      try
        Some (Public_data.dead_rules_of_json (List.assoc dead_rules l))
      with
      | Not_found -> None
    in
    let constraints =
      try
        Some (lemmas_list_of_json (List.assoc Public_data.refinement_lemmas l))
      with
      | Not_found -> None
    in
    let separating_transitions =
      try
        Some (Public_data.separating_transitions_of_json
                (List.assoc separating_transitions l))
      with
      | Not_found -> None
    in
    errors, contact_maps, influence_maps, dead_rules, constraints, separating_transitions
  | x ->
    raise (Yojson.Basic.Util.Type_error (JsonUtil.build_msg "remanent state",x))

let do_event_gen f phase n state =
  let error, log_info =
    f
      state.parameters
      state.errors
      phase
      n
      state.log_info
  in
  {state with errors = error ; log_info = log_info}

let add_event x y = do_event_gen StoryProfiling.StoryStats.add_event x y

let close_event x y = do_event_gen StoryProfiling.StoryStats.close_event x y

let set_parameters parameters state = {state with parameters = parameters}

let get_parameters state = state.parameters

let get_init state = state.init

let set_init_state init state = {state with init_state = Some init}

let get_init_state state = state.init_state

let set_env model state = {state with env = Some model}

let get_env state = state.env

(*contact map from kappa*)
let set_contact_map_int cm state =
  {state with contact_map_int = Some cm}

let get_contact_map_int state = state.contact_map_int

let set_compilation compilation state =
  {state with compilation = Some compilation}

let get_compilation state = state.compilation

let set_prehandler handler state = {state with prehandler = Some handler}

let get_prehandler state = state.prehandler

let set_handler handler state = {state with handler = Some handler}

let get_handler state = state.handler

let set_compil compil state = {state with compilation = compil}

let get_compil state = state.compilation

let set_c_compil c_compil state = {state with c_compil = Some c_compil}

let get_c_compil state = state.c_compil

let set_refined_compil refined_compil state =
  {state with refined_compilation = Some refined_compil}

let get_refined_compil state = state.refined_compilation

let set_errors errors state = {state with errors = errors }

let get_errors state = state.errors

let set_quark_map quark_map state =
  {state with quark_map = Some quark_map}

let get_quark_map state = state.quark_map

let set_contact_map accuracy map state =
  {state with contact_map =
                Public_data.AccuracyMap.add accuracy map state.contact_map}

let get_contact_map accuracy state =
  Public_data.AccuracyMap.find_option accuracy state.contact_map

let set_signature signature state = {state with signature = Some signature}

let get_signature state = state.signature

let set_influence_map accuracy map state =
  {state with influence_map =
                Public_data.AccuracyMap.add accuracy map state.influence_map}

let get_influence_map accuracy state =
  Public_data.AccuracyMap.find_option accuracy state.influence_map

let set_bidirectional_influence_map accuracy map state =
  {state with bidirectional_influence_map =
                Public_data.AccuracyMap.add accuracy map state.bidirectional_influence_map}

let get_bidirectional_influence_map accuracy state =
  Public_data.AccuracyMap.find_option accuracy state.bidirectional_influence_map


let set_local_influence_map_blackboard blackboard state =
  {state with local_influence_map_blackboard = Some blackboard}

let get_local_influence_map_blackboard state =
  state.local_influence_map_blackboard

let set_internal_influence_map accuracy map state =
  {state
   with internal_influence_map =
          Public_data.AccuracyMap.add accuracy map state.internal_influence_map}

let get_internal_influence_map accuracy state =
  Public_data.AccuracyMap.find_option accuracy state.internal_influence_map

let set_internal_contact_map accuracy int_contact_map state =
  {state
   with internal_contact_map =
          Public_data.AccuracyMap.add
            accuracy int_contact_map state.internal_contact_map}

let get_internal_contact_map accuracy state =
  Public_data.AccuracyMap.find_option accuracy state.internal_contact_map

let get_reachability_result state = state.reachability_state

let set_reachability_result reachability_state state =
  {state with reachability_state = Some reachability_state}

let get_dead_rules state = state.dead_rules

let set_dead_rules dead_rules state =
  {state with dead_rules = Some dead_rules}

let get_dead_agents state = state.dead_agents

let set_dead_agents dead_agents state =
  {state with dead_agents = Some dead_agents}

let get_subviews_info state = state.subviews_info

let set_subviews_info subviews state =
  {state with subviews_info = Some subviews}

let set_bdu_handler bdu_handler state =
  {state with bdu_handler = bdu_handler}

let get_bdu_handler state = state.bdu_handler

let set_ode_flow flow state = {state with ode_flow = Some flow}

let get_ode_flow state = state.ode_flow

let set_ctmc_flow flow state = {state with ctmc_flow = Some flow}

let get_ctmc_flow state = state.ctmc_flow

let get_influence_map_map state = state.influence_map

let get_internal_contact_map_map state = state.internal_contact_map

let get_internal_influence_map_map state = state.internal_influence_map

let get_log_info state = state.log_info

let set_log_info log state = {state with log_info = log}

let get_internal_constraints_list state =
  state.internal_constraints_list

let set_internal_constraints_list list state =
  {state with internal_constraints_list = Some list}

let get_constraints_list state = state.constraints_list

let set_constraints_list list state =
  {state with constraints_list = Some list}


let get_symmetries accuracy state =
  Public_data.AccuracyMap.find_option accuracy state.symmetric_sites

let set_symmetries accuracy partition state =
  {
    state
    with symmetric_sites =
           Public_data.AccuracyMap.add
             accuracy partition state.symmetric_sites
  }
