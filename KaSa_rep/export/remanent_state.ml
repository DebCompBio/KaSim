(**
  * remanent_state.ml
  * openkappa
  * Jérôme Feret, projet Abstraction/Antique, INRIA Paris-Rocquencourt
  *
  * Creation: June, the 25th of 2016
  * Last modification: Time-stamp: <Nov 27 2016>
  * *
  *
  * Copyright 2010,2011 Institut National de Recherche en Informatique et
  * en Automatique.  All rights reserved.  This file is distributed
  * under the terms of the GNU Library General Public License *)

(**********************)
(* compilation result *)
(**********************)

type compilation =
    ((string Location.annot) * Ast.port list, Ast.mixture, string, Ast.rule)
      Ast.compil

type init =
  | Compil of compilation
  | Files of string list

type refined_compilation =
  (Ckappa_sig.agent, Ckappa_sig.mixture, string,
   Ckappa_sig.direction * Ckappa_sig.mixture Ckappa_sig.rule) Ast.compil


(*******************)
(* Accuracy levels *)
(*******************)

type accuracy_level = Low | Medium | High | Full

let json_of_accuracy accuracy =
  JsonUtil.of_string
    (
      match
        accuracy
      with
      | Low -> "low"
      | Medium -> "medium"
      | High -> "high"
      | Full -> "full"
    )

let json_to_accuracy json =
  match
    JsonUtil.to_string json
  with
  | "low" -> Low
  | "medium" -> Medium
  | "high" -> High
  | "full" -> Full
  | _ ->
    raise
      (Yojson.Basic.Util.Type_error (JsonUtil.build_msg "accuracy level",json))

(******************************************************************)

module AccuracySetMap =
  SetMap.Make
    (struct
      type t = accuracy_level
      let compare a b =
        match a,b with
        | Low,Low -> 0
        | Low,_ -> -1
        | _,Low -> 1
        | Medium,Medium -> 0
        | Medium,_ -> -1
        | _,Medium -> 1
        | High, High -> 0
        | High,_ -> -1
        | _,High -> 1
        | Full,Full -> 0

      let print f = function
        | Full -> Format.fprintf f "Full"
        | High -> Format.fprintf f "High"
        | Medium -> Format.fprintf f "Medium"
        | Low -> Format.fprintf f "Low"
    end)

module AccuracyMap = AccuracySetMap.Map

(******************************************************************)


type quark_map = Quark_type.quarks

type rule_id = int
type var_id =  int


(**************)
(* JSon labels*)
(**************)

let wakeup = "wake-up map"
let inhibition = "inhibition map"
let source = "source"
let target_map = "target map"
let target = "target"
let location_pair_list = "location pair list"
let rhs = "RHS"
let lhs = "LHS"
let agent="agent name"
let interface="interface"
let site="site name"
let stateslist="states list"
let props="property states"
let binds="binding states"
let contactmap="contact map"
let contactmaps="contact maps"
let influencemap="influence map"
let influencemaps="influence maps"
let refinement_lemmas="refinement lemmas"
let map = "map"
let accuracy_string = "accuracy"
let variable = "variable"
let rule = "rule"
let direct = "direct"
let prop="property state"
let bind="binding state"
let side_effect = "side effect"
let hyp = "site graph"
let refinement = "site graph list"
let domain_name = "domain name"
let refinements_list = "refinements list"
let dead_rules = "dead rules"

(*****************)
(* Influence map *)
(*****************)

(* Influence Node *)
type influence_node =
  | Rule of rule_id
  | Var of var_id

let influence_node_to_json a =
  match a with
  | Var i ->
    `Assoc [variable,JsonUtil.of_int i]
  | Rule i  ->
    `Assoc [rule,JsonUtil.of_int i]

let influence_node_of_json
    ?error_msg:(error_msg="Not a correct influence node")
  =
  function
  | `Assoc [s,json] when s = variable ->
    Var (JsonUtil.to_int json)
  | `Assoc [s,json] when s = rule ->
    Rule (JsonUtil.to_int json)
  | x -> raise (Yojson.Basic.Util.Type_error (error_msg,x))

(* Location labels *)

type location =
  | Direct of int
  | Side_effect of int


let location_to_json a =
  match a with
  | Direct i -> `Assoc [direct,JsonUtil.of_int i]
  | Side_effect i  -> `Assoc [side_effect,JsonUtil.of_int i]

let location_of_json
    ?error_msg:(error_msg="Not a correct location")
  =
  function
  | `Assoc [s,json] when s=direct -> Direct (JsonUtil.to_int json)
  | `Assoc [s,json] when s=side_effect -> Side_effect (JsonUtil.to_int json)
  | x ->
    raise (Yojson.Basic.Util.Type_error (error_msg,x))


module InfluenceNodeSetMap =
  SetMap.Make
    (struct
      type t = influence_node
      let compare = compare
      let print f = function
        | Rule r -> Format.fprintf f "Rule %i" r
        | Var r -> Format.fprintf f "Var %i" r
    end)

module InfluenceNodeMap = InfluenceNodeSetMap.Map

(* Relations *)

type 'a pair = 'a * 'a

type half_influence_map =
  location pair list InfluenceNodeMap.t InfluenceNodeMap.t

let half_influence_map_to_json =
  InfluenceNodeMap.to_json
    ~lab_key:source ~lab_value:target_map
    influence_node_to_json
    (InfluenceNodeMap.to_json
       ~lab_key:target ~lab_value:location_pair_list
       influence_node_to_json
       (JsonUtil.of_list
          (JsonUtil.of_pair
             ~lab1:rhs ~lab2:lhs
             location_to_json
             location_to_json
          )
       )
    )

let half_influence_map_of_json =
  InfluenceNodeMap.of_json
    ~error_msg:(JsonUtil.build_msg "activation or inhibition map")
    ~lab_key:source ~lab_value:target_map
    (influence_node_of_json ~error_msg:(JsonUtil.build_msg "influence node"))
    (InfluenceNodeMap.of_json
       ~lab_key:target ~lab_value:location_pair_list
       ~error_msg:"map of lists of pairs of locations"
       (influence_node_of_json ~error_msg:(JsonUtil.build_msg "influence node"))
       (JsonUtil.to_list ~error_msg:"list of pair of locations"
          (JsonUtil.to_pair
             ~error_msg:""
             ~lab1:rhs ~lab2:lhs
             (location_of_json ~error_msg:(JsonUtil.build_msg "location"))
             (location_of_json ~error_msg:(JsonUtil.build_msg "location")))))

(* Influence map *)

type influence_map =
  {
    positive: half_influence_map ;
    negative: half_influence_map ;
  }

let influence_map_to_json influence_map =
`Assoc
  [influencemap,
   JsonUtil.of_pair
     ~lab1:accuracy_string ~lab2:map
     json_of_accuracy
     (fun influence_map ->
        `Assoc
          [
            wakeup,half_influence_map_to_json influence_map.positive;
            inhibition,half_influence_map_to_json
              influence_map.negative;]) influence_map]

let influence_map_of_json =
  function
  | `Assoc l as x ->
    begin
      try
        let json = List.assoc influencemap l in
        JsonUtil.to_pair
        ~lab1:accuracy_string ~lab2:map
        ~error_msg:(JsonUtil.build_msg "influence map1")
        json_to_accuracy
      (function
        | `Assoc l as x when List.length l = 2 ->
          begin
            try
              {positive =
                 half_influence_map_of_json (List.assoc wakeup l);
               negative =
                 half_influence_map_of_json (List.assoc inhibition l)}
            with Not_found ->
              raise
                (Yojson.Basic.Util.Type_error
                   (JsonUtil.build_msg "influence map",x))
          end
        | x ->
          raise
            (Yojson.Basic.Util.Type_error
               (JsonUtil.build_msg "influence map",x)))
      json
      with
      | _ ->
        raise
          (Yojson.Basic.Util.Type_error (JsonUtil.build_msg "influence map",x))
    end
  | x ->
    raise (Yojson.Basic.Util.Type_error (JsonUtil.build_msg "influence map",x))

(******************************************************************************)
(******************************************************************************)

(***************)
(* Contact map *)
(***************)

type contact_map =
      ((string list) * (string*string) list) Mods.StringMap.t Mods.StringMap.t

let contact_map_to_json contact_map=
  `Assoc
    [contactmap,
     JsonUtil.of_pair
       ~lab1:accuracy_string ~lab2:map
       json_of_accuracy
       (Mods.StringMap.to_json
       ~lab_key:agent ~lab_value:interface
       JsonUtil.of_string
       (Mods.StringMap.to_json
          ~lab_key:site ~lab_value:stateslist
          JsonUtil.of_string
          (JsonUtil.of_pair
             ~lab1:props ~lab2:binds
             (JsonUtil.of_list JsonUtil.of_string)
             (JsonUtil.of_list
                (JsonUtil.of_pair
                   ~lab1:agent ~lab2:site
                   JsonUtil.of_string
                   JsonUtil.of_string)
             )))) contact_map]

let contact_map_of_json =
  function
  | `Assoc l as x ->
    begin
      try
        let json = List.assoc contactmap l in
        JsonUtil.to_pair
          ~lab1:accuracy_string ~lab2:map
          ~error_msg:(JsonUtil.build_msg "contact map")
          json_to_accuracy
          (Mods.StringMap.of_json
             ~lab_key:agent ~lab_value:interface
             (JsonUtil.to_string ~error_msg:(JsonUtil.build_msg "agent name"))
             (Mods.StringMap.of_json
                ~error_msg:(JsonUtil.build_msg "interface")
                ~lab_key:site ~lab_value:stateslist
                (JsonUtil.to_string ~error_msg:(JsonUtil.build_msg "site name"))
                  (JsonUtil.to_pair
                     ~error_msg:(JsonUtil.build_msg "pair of lists of sites")
                     ~lab1:props ~lab2:binds
                     (JsonUtil.to_list
                        ~error_msg:(JsonUtil.build_msg "list of internal states")
                        (JsonUtil.to_string
                           ~error_msg:(JsonUtil.build_msg "internal state")))
                     (JsonUtil.to_list
                        ~error_msg:(JsonUtil.build_msg "list of binding states")
                        (JsonUtil.to_pair
                           ~error_msg:(JsonUtil.build_msg "binding type")
                           ~lab1:agent ~lab2:site
                           (JsonUtil.to_string ~error_msg:(JsonUtil.build_msg
                                                             "agent name"))
                           (JsonUtil.to_string ~error_msg:(JsonUtil.build_msg
                                                             "site")))))))
          json
      with
      | _ -> raise (Yojson.Basic.Util.Type_error (JsonUtil.build_msg "contact map",x))
    end
  | x -> raise (Yojson.Basic.Util.Type_error (JsonUtil.build_msg "contact map",x))

(******************************************************************************)
(******************************************************************************)

(**************)
(* dead rules *)
(**************)

type dead_rules = Ckappa_sig.c_rule_id list

let dead_rules_to_json json =
  `Assoc
    [dead_rules, JsonUtil.of_list Ckappa_sig.rule_id_to_json json]

let dead_rules_of_json =
  function
  | `Assoc l as x ->
    begin
      try
        let json = List.assoc dead_rules l in
        JsonUtil.to_list
          ~error_msg:"list of dead rules" Ckappa_sig.rule_id_of_json json
      with
      | _ ->
        raise
          (Yojson.Basic.Util.Type_error (JsonUtil.build_msg "dead  rules",x))
    end
  | x ->
    raise (Yojson.Basic.Util.Type_error (JsonUtil.build_msg "dead rules",x))

(***************)
(* dead agents *)
(***************)

type dead_agents = Ckappa_sig.c_agent_name list

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
       JsonUtil.of_pair ~lab1:prop ~lab2:bind
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
           ~lab1:prop ~lab2:bind ~error_msg:"wrong binding state"
           (JsonUtil.to_option
              (JsonUtil.to_string ~error_msg:prop)

           )
           (JsonUtil.to_option
              Ckappa_backend.Ckappa_backend.binding_state_of_json)
        )

type agent =
  (string * (* agent name *)
   (string option (* internal state *) *
    Ckappa_backend.Ckappa_backend.binding_state option (*binding state*) )
     Wrapped_modules.LoggedStringMap.t)

let agent_to_json =
  JsonUtil.of_pair
    ~lab1:agent ~lab2:interface
    JsonUtil.of_string
    interface_to_json

let agent_of_json =
  JsonUtil.to_pair
    ~lab1:agent ~lab2:interface ~error_msg:"agent"
    (JsonUtil.to_string ~error_msg:"agent name")
    interface_of_json
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



type 'site_graph lemma =
  {
    hyp : 'site_graph ;
    refinement : 'site_graph list
  }

let lemma_to_json site_graph_to_json json =
  JsonUtil.of_pair
    ~lab1:hyp ~lab2:refinement
    site_graph_to_json
    (JsonUtil.of_list site_graph_to_json)
    (json.hyp,json.refinement)

let lemma_of_json site_graph_of_json json =
  let a,b =
    JsonUtil.to_pair
    ~lab1:hyp ~lab2:refinement ~error_msg:"lemma"
    site_graph_of_json
    (JsonUtil.to_list  ~error_msg:"refinements list" site_graph_of_json)
    json
  in
  {
    hyp =  a;
    refinement =  b
  }

let get_hyp h = h.hyp

let get_refinement r = r.refinement

type 'site_graph poly_constraints_list =
  (string (*domain name*) * 'site_graph lemma list) list

let poly_constraints_list_to_json site_graph_to_json =
  JsonUtil.of_list
    (JsonUtil.of_pair
       ~lab1:domain_name ~lab2:refinements_list
       JsonUtil.of_string
       (JsonUtil.of_list (lemma_to_json site_graph_to_json))
    )

let poly_constraints_list_of_json site_graph_of_json =
  JsonUtil.to_list
    (JsonUtil.to_pair ~error_msg:"constraints list"
       ~lab1:domain_name ~lab2:refinements_list
       (JsonUtil.to_string ~error_msg:"abstract domain")
       (JsonUtil.to_list (lemma_of_json site_graph_of_json)))

type constraints_list = agent list poly_constraints_list

let lemmas_list_to_json constraints =
  `Assoc
    [
      refinement_lemmas,
      poly_constraints_list_to_json
        (JsonUtil.of_list agent_to_json) constraints
    ]
let lemmas_list_of_json =
function
| `Assoc l as x ->
  begin
    try
      let json =
        List.assoc refinement_lemmas l
      in
      poly_constraints_list_of_json
        (JsonUtil.to_list ~error_msg:"site graph" agent_of_json)
        json
    with
    | _ ->
      raise
        (Yojson.Basic.Util.Type_error (JsonUtil.build_msg "refinement lemmas list",x))
  end
| x ->
  raise (Yojson.Basic.Util.Type_error (JsonUtil.build_msg "refinement lemmas list",x))


(******************************************************************************)
(******************************************************************************)

(****************************)
(* Internal representations *)
(****************************)

type internal_influence_map =
    Quark_type.Labels.label_set_couple Ckappa_sig.PairRule_setmap.Map.t
    * Quark_type.Labels.label_set_couple Ckappa_sig.PairRule_setmap.Map.t

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
      Ckappa_backend.Ckappa_backend.t poly_constraints_list

(*******************************************************************)
(*******************************************************************)

type ('static,'dynamic) state =
  {
    parameters    : Remanent_parameters_sig.parameters ;
    log_info : StoryProfiling.StoryStats.log_info ;
    prehandler: Cckappa_sig.kappa_handler option ;
    handler       : Cckappa_sig.kappa_handler option ;
    init : init ;
    compilation   : compilation option ;
    refined_compilation : refined_compilation option ;
    c_compil : Cckappa_sig.compil option ;
    quark_map: quark_map option ;
    internal_influence_map: internal_influence_map AccuracyMap.t ;
    influence_map : influence_map AccuracyMap.t ;
    internal_contact_map: internal_contact_map AccuracyMap.t;
    contact_map   : contact_map AccuracyMap.t ;
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
  }

let create_state ?errors parameters init =
  let error =
    match
      errors
    with
    | None -> Exception.empty_error_handler
    | Some error -> error
  in
  let error, handler_bdu = Mvbdu_wrapper.Mvbdu.init parameters error in
  {
    parameters = parameters;
    log_info = StoryProfiling.StoryStats.init_log_info ();
    prehandler = None ;
    handler = None ;
    init = init ;
    compilation = None ;
    refined_compilation = None ;
    c_compil = None ;
    quark_map = None ;
    internal_influence_map = AccuracyMap.empty ;
    influence_map = AccuracyMap.empty ;
    internal_contact_map = AccuracyMap.empty ;
    contact_map = AccuracyMap.empty ;
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
    constraints_list = None
  }

(**************)
(* JSON: main *)
(**************)

let add_to_json f state l =
  (f state) :: l

let annotate map =
  AccuracyMap.fold
    (fun x y l -> (x,(x,y))::l)
    map
    []

let add_map get title label to_json state l =
  let map = get state in
  if AccuracyMap.is_empty map then l
  else
    let y = annotate (get state) in
      (title, JsonUtil.of_list
         (JsonUtil.of_pair
            ~lab1:accuracy_string
            ~lab2:label
            json_of_accuracy
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
         json_to_accuracy
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
let add_contact_map_to_json state l
     =
  add_map get_contact_map_map
    contactmaps contactmap contact_map_to_json
    state l


let add_influence_map_to_json state l =
  add_map get_influence_map_map
    influencemaps influencemap influence_map_to_json
    state l


let add_dead_rules_to_json state l =
  match
    state.dead_rules
  with
  | None -> l
  | Some rules ->
    (dead_rules , dead_rules_to_json rules)::l

let add_refinements_lemmas_to_json state l =
  match
    get_constraints_list state
  with
  | None -> l
  | Some constraints ->
    (
      refinement_lemmas,
      lemmas_list_to_json constraints)::l

let to_json state =
  let l = [] in
  let l = add_refinements_lemmas_to_json state l in
  let l = add_dead_rules_to_json state l in
  let l = add_influence_map_to_json state l in
  let l = add_contact_map_to_json state l in
  ((`Assoc  l): Yojson.Basic.json)

let of_json =
  function
  | `Assoc l ->
   let contact_maps =
      try
        get_map AccuracyMap.empty AccuracyMap.add
          contact_map_of_json
          contactmap
          (List.assoc contactmaps l)
      with
      | Not_found -> AccuracyMap.empty
   in
   let influence_maps =
     try
       get_map AccuracyMap.empty AccuracyMap.add
         influence_map_of_json
         influencemap
         (List.assoc influencemaps l)
     with
      | Not_found -> AccuracyMap.empty
   in
   let dead_rules =
     try
       Some (dead_rules_of_json (List.assoc dead_rules l))
     with
     | Not_found -> None
   in
   let constraints =
     try
       Some (lemmas_list_of_json (List.assoc refinement_lemmas l))
     with
     | Not_found -> None
   in
   contact_maps, influence_maps, dead_rules, constraints
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
  {state with contact_map = AccuracyMap.add accuracy map state.contact_map}

let get_contact_map accuracy state =
  AccuracyMap.find_option accuracy state.contact_map

let set_signature signature state = {state with signature = Some signature}

let get_signature state = state.signature

let set_influence_map accuracy map state =
  {state with influence_map = AccuracyMap.add accuracy map state.influence_map}

let get_influence_map accuracy state =
  AccuracyMap.find_option accuracy state.influence_map

let set_internal_influence_map accuracy map state =
  {state
   with internal_influence_map =
          AccuracyMap.add accuracy map state.internal_influence_map}

let get_internal_influence_map accuracy state =
  AccuracyMap.find_option accuracy state.internal_influence_map

let set_internal_contact_map accuracy int_contact_map state =
  {state
   with internal_contact_map = AccuracyMap.add accuracy int_contact_map state.internal_contact_map}

let get_internal_contact_map accuracy state =
  AccuracyMap.find_option accuracy state.internal_contact_map

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
