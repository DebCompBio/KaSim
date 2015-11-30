(**
 * utilities.ml 
 *      
 * Creation:                      <2015-03-28 feret>
 * Last modification: Time-stamp: <2015-11-20 21:41:49 feret>
 * 
 * API for causal compression
 * Jerome Feret, projet Abstraction, INRIA Paris-Rocquencourt
 * Jean Krivine, Université Paris-Diderot, CNRS   
 *  
 * Copyright 2015 Institut National de Recherche en Informatique  * et en Automatique.  All rights reserved.  
 * This file is distributed under the terms of the 
 * GNU Library General Public License *)

let debug_mode = false
		   
module D=Dag.Dag

type error_log =  D.S.PH.B.PB.CI.Po.K.H.error_channel
type parameter =  D.S.PH.B.PB.CI.Po.K.H.parameter
type kappa_handler = D.S.PH.B.PB.CI.Po.K.H.handler 
type profiling_info = D.S.PH.B.PB.CI.Po.K.P.log_info
type progress_bar = bool * int * int 

type step = D.S.PH.B.PB.CI.Po.K.refined_step				   
type step_with_side_effects = D.S.PH.B.PB.CI.Po.K.refined_step * D.S.PH.B.PB.CI.Po.K.side_effect										
type step_id = D.S.PH.B.PB.step_id

type trace =
  | Pretrace of step list
  | Compressed_trace of step list * step_with_side_effects list 

let get_pretrace trace =
  match
    trace
  with
  | Pretrace x | Compressed_trace (x,_) -> x 
let get_compressed_trace trace =
  match
    trace
  with
  | Pretrace x -> List.rev_map (fun x -> x,[]) (List.rev x) 					     
  | Compressed_trace (_,x) -> x

let is_compressed_trace trace =
  match
    trace
  with
  | Pretrace _ -> true
  | Compressed_trace _ -> false
			    
let trace_of_pretrace x = Pretrace x 
let get_log_step = D.S.PH.B.PB.CI.Po.K.H.get_log_step
let get_gebugging_mode = D.S.PH.B.PB.CI.Po.K.H.get_debugging_mode
let get_logger = D.S.PH.B.PB.CI.Po.K.H.get_logger
let dummy_log = fun p -> p

let extend_trace_with_dummy_side_effects l = List.rev_map (fun a -> a,[]) (List.rev l)
			   
let print_pretrace parameter handler =
      Format.fprintf
	(D.S.PH.B.PB.CI.Po.K.H.get_out_channel parameter)
	"@[<v>%a@]@."
	(Pp.list Pp.space (D.S.PH.B.PB.CI.Po.K.print_refined_step ~handler))

let print_trace parameter handler trace =
  match
    trace
  with
  | Pretrace x -> print_pretrace parameter handler x
  | Compressed_trace (x,y) ->
     let () = print_pretrace parameter handler x in
     let () = () (* to do, print y*)
     in () 
(** operations over traces *) 

	
let transform_trace_gen f log_message debug_message log =
  (fun parameters p kappa_handler profiling_info error trace ->
   if p parameters
   then 
     let bool =
       if
	 D.S.PH.B.PB.CI.Po.K.H.get_log_step parameters
       then
	 match log_message
	 with
	 | Some log_message ->
	    let () = Debug.tag_begin_n (D.S.PH.B.PB.CI.Po.K.H.get_logger parameters) log_message in
	    true
	 | None -> false
       else
	 false 
     in
     let pretrace = get_pretrace trace in 
     let error,(pretrace',n) = f parameters kappa_handler error pretrace in
     let () =
       if
	 bool
       then
	 Debug.tag_end_n (D.S.PH.B.PB.CI.Po.K.H.get_logger parameters) n
     in 
     let () =
       if
	 D.S.PH.B.PB.CI.Po.K.H.get_debugging_mode parameters
       then
	 let _ = Debug.tag (D.S.PH.B.PB.CI.Po.K.H.get_debugging_channel parameters) debug_message in 
	 print_pretrace parameters kappa_handler pretrace'
     in
     let profiling_info = log n profiling_info  in 
     error,profiling_info,Pretrace pretrace'
   else
     error,profiling_info,trace)

let monadic_lift f = (fun _ _ e t ->
		      let t' = f t in
		      e,(f t,List.length t - List.length t'))
let dummy_profiling = (fun _ p -> p)
			
let split_init =
  transform_trace_gen
    (monadic_lift D.S.PH.B.PB.CI.Po.K.split_init)
    (Some "\t - splitting initial events")
    "Trace after having split initial events:\n"
    dummy_profiling

let disambiguate =
  transform_trace_gen
    (monadic_lift D.S.PH.B.PB.CI.Po.K.disambiguate)
    (Some "\t - renaming agents to avoid conflicts after event removals")
    "Trace after having renames agents:\n"
    dummy_profiling
    
let cut =
  transform_trace_gen
    D.S.PH.B.PB.CI.Po.cut
    (Some "\t - cutting concurrent events")
    "Trace after having removed concurrent events:\n"
    D.S.PH.B.PB.CI.Po.K.P.set_global_cut
    
let fill_siphon =
  transform_trace_gen
    (monadic_lift D.S.PH.B.PB.CI.Po.K.fill_siphon)
    (Some "\t - detecting siphons")
    "Trace after having detected siphons:\n"
    dummy_profiling

let remove_events_after_last_obs =
  transform_trace_gen
    (monadic_lift ((List_utilities.remove_suffix_after_last_occurrence D.S.PH.B.PB.CI.Po.K.is_obs_of_refined_step)))
    (Some "\t - removing events occurring after the last observable:\n")
    "Trace after having removed the events after the last observable"
    dummy_profiling

let remove_pseudo_inverse_events =
  transform_trace_gen
    D.S.PH.B.PB.CI.cut
    (Some "\t - detecting pseudo inverse events")
    "Trace after having removed pseudo inverse events:\n"
    D.S.PH.B.PB.CI.Po.K.P.set_pseudo_inv
						
  		 
type cflow_grid = Causal.grid  
type enriched_cflow_grid = Causal.enriched_grid
type musical_grid =  D.S.PH.B.blackboard 
type transitive_closure_config = Graph_closure.config 
		       
(* dag: internal representation for cflows *)
type dag = D.graph
(* cannonical form for cflows (completely capture isomorphisms) *)
type canonical_form = D.canonical_form
(* prehashform for cflows, if two cflows are isomorphic, they have the same prehash form *) 
type hash = D.prehash 

(** For each hash form, the list of stories with that hash. 
    For each such stories: the grid and the graph.
    If necessessary the cannonical form.
    The pretrace (to apply further compression later on) 
    Some information about the corresponding observable hits *)	       
type story_list =
  hash * (cflow_grid * dag  * canonical_form option * step list  * profiling_info Mods.simulation_info list) list
		
	
type story_table =  
  { 
    story_counter:int;
    story_list: story_list list;
  }
    
let count_stories story_table = 
  List.fold_left 
    (fun n l -> n + List.length (snd l))
    0 
    story_table.story_list 
    
type observable_hit = 
  {
    list_of_actions: D.S.PH.update_order list ;
    list_of_events: step_id  list ; 
    runtime_info:  unit Mods.simulation_info option}

let get_event_list_from_observable_hit a = a.list_of_events 
let get_runtime_info_from_observable_hit a = a.runtime_info 
let get_list_order a = a.list_of_actions 

module Profiling = D.S.PH.B.PB.CI.Po.K.P

		     
let error_init = D.S.PH.B.PB.CI.Po.K.H.error_init
	    
let extract_observable_hits_from_musical_notation a b c d = 
  let error,l = D.S.PH.forced_events a b c d in 
  error,
  List.rev_map
    (fun (a,b,c) -> 
      {
      list_of_actions = a;
      list_of_events = b ;
      runtime_info = c
      })
    (List.rev l)

let extract_observable_hit_from_musical_notation string a b c d = 
  let error,l = D.S.PH.forced_events a b c d in 
  match l with [a,b,c] -> 
    error,{
      list_of_actions = a;
      list_of_events = b; 
      runtime_info = c}
  | [] -> failwith (string^" no story")
  | _::_ -> failwith (string^" several stories")
      
    
let causal_prefix_of_an_observable_hit string parameter handler error log_info blackboard (enriched_grid:enriched_cflow_grid) observable_id = 
  let eid = 
    match 
      get_event_list_from_observable_hit observable_id  
    with 
    | [a] -> a 
    | [] -> failwith ("no observable in that story"^string)
    | _ -> failwith  ("several observables in that story"^string)
  in 
  let event_id_list_rev = ((eid+1)::(enriched_grid.Causal.prec_star.(eid+1))) in 
  let event_id_list = List.rev_map pred (event_id_list_rev) in 
  let error,list_eid,_ = D.S.translate parameter handler error blackboard event_id_list in 
  error,trace_of_pretrace list_eid 



let export_musical_grid_to_xls = D.S.PH.B.export_blackboard_to_xls
  
let print_musical_grid = D.S.PH.B.print_blackboard 


let empty_story_table ()  = 
  { 
    story_counter=1;
    story_list=[];
  }  
  
let get_trace_of_story (_,_,_,y,_) = Pretrace y
let get_info_of_story (_,_,_,_,t) = t
let fold_story_list f (l:story_list) a =
  List.fold_left
    (fun a x -> f (get_trace_of_story x) (get_info_of_story x) a)
    a
    (snd l)

let tick_opt bar = 
  match 
    bar
  with 
  | None -> bar
  | Some (logger,n,bar) -> Some (logger,n,Mods.tick_stories logger n bar)
 
    
let fold_story_table_gen logger f l a =
  let n_stories_input = count_stories l in 
  let progress_bar = 
    match logger
    with None -> None
       | Some logger -> 
	  Some (logger,n_stories_input,Mods.tick_stories logger n_stories_input (false,0,0))
  in
  let g story info (progress_bar,a) =
    let a = f story info a in
    let progress_bar = tick_opt progress_bar in
    progress_bar,a
  in
  snd
    (List.fold_left
       (fun a x -> fold_story_list g x a)
       (progress_bar,a) (List.rev l.story_list))

let fold_story_table_with_progress_bar logger = fold_story_table_gen (Some logger) 
let fold_story_table_without_progress_bar a b c = fold_story_table_gen None a b c 


let get_counter story_list = story_list.story_counter 
let get_stories story_list = story_list.story_list 
let inc_counter story_list =
  {
    story_list with 
      story_counter = succ story_list.story_counter
  }


let store_trace (parameter:parameter) (handler:kappa_handler) (error:error_log) obs_info  computation_info trace  (story_table:story_table) = 
  let pretrace = get_pretrace trace in
  let trace2 = get_compressed_trace trace in 
  let bool = is_compressed_trace trace in 
  let grid = D.S.PH.B.PB.CI.Po.K.build_grid trace2 bool  handler in
  let computation_info  = D.S.PH.B.PB.CI.Po.K.P.set_grid_generation  computation_info in 
  let error,graph = D.graph_of_grid parameter handler error grid in 
  let error,prehash = D.prehash parameter handler error graph in 
  let computation_info = D.S.PH.B.PB.CI.Po.K.P.set_canonicalisation computation_info in 
  let story_info = 
    List.map 
      (Mods.update_profiling_info (D.S.PH.B.PB.CI.Po.K.P.copy computation_info))
      obs_info 
  in 
  let story_table = 
    {
       story_list = (prehash,[grid,graph,None,pretrace,story_info])::story_table.story_list ;
       story_counter = story_table.story_counter +1 								       
    }
  in
  error,story_table,computation_info 

let fold_left_with_progress_bar logger f a l =
  let n = List.length l in
  let progress_bar = Mods.tick_stories logger n (false,0,0) in
  snd
    (List.fold_left
       (fun (bar,a) x ->
	let a = f a x in
	let bar = Mods.tick_stories logger n bar in
	(bar,a))
       (progress_bar,a)
       l)
   
let flatten_story_table parameter handler error story_table = 
  let error,list = 
    D.hash_list parameter handler error 
      (List.rev story_table.story_list)
  in 
  error,
  {story_table
   with 
     story_list = list}

let always = (fun _ -> true) 


let compress logger parameter handler error log_info trace =
  match
    parameter.D.S.PH.B.PB.CI.Po.K.H.current_compression_mode
  with
  | None -> error,log_info,[trace] 
  | Some Parameter.Causal ->
     let error,log_info,trace = cut parameter always handler log_info error trace
     in error,log_info,[trace] 
  | Some Parameter.Weak | Some Parameter.Strong -> 
    let event_list = get_pretrace trace in 
    let error,log_info,blackboard = D.S.PH.B.import parameter handler error log_info event_list in 
    let error,list = D.S.PH.forced_events parameter handler error blackboard in     
    let list_order = 
      match list 
      with 
      | (list_order,_,_)::_ -> list_order
      | _ -> []
    in 
    let error,log_info,blackboard,output,list = 
      D.S.compress parameter handler error log_info blackboard list_order 
    in
    let list =
      List.rev_map
	(fun pretrace ->
	 let event_list = D.S.translate_result pretrace in 
	 let event_list = D.S.PH.B.PB.CI.Po.K.clean_events event_list in 
	 (Compressed_trace (event_list,pretrace)))
	list
    in 
    let log_info = D.S.PH.B.PB.CI.Po.K.P.set_story_research_time log_info in 
    let error = 
      if debug_mode
      then 
	let _ =  Debug.tag logger "\t\t * result"  in
	let _ =
          if D.S.PH.B.is_failed output 
          then 
            let _ = Format.fprintf parameter.D.S.PH.B.PB.CI.Po.K.H.out_channel_err "Fail_to_compress" in  error
          else 
            let _ = Format.fprintf parameter.D.S.PH.B.PB.CI.Po.K.H.out_channel_err "Succeed_to_compress" in 
            error
	in 
      error 
      else 
	error
    in error,log_info,list
			
let set_compression_mode p x =
  match
    x
  with
  | Parameter.Causal -> D.S.PH.B.PB.CI.Po.K.H.set_compression_none p
  | Parameter.Strong -> D.S.PH.B.PB.CI.Po.K.H.set_compression_strong p
  | Parameter.Weak -> D.S.PH.B.PB.CI.Po.K.H.set_compression_weak p
						       
let strongly_compress logger parameter = compress logger (set_compression_mode parameter Parameter.Strong)
let weakly_compress logger parameter = compress logger (set_compression_mode parameter Parameter.Weak)
								  
let convert_trace_into_grid_while_trusting_side_effects trace handler = 
  let refined_list = 
    List.rev_map (fun x -> (x,[])) (List.rev (get_pretrace trace))
  in 
  D.S.PH.B.PB.CI.Po.K.build_grid refined_list true handler 
    
let convert_trace_into_musical_notation p h e info x = D.S.PH.B.import p h e info (get_pretrace x)

let enrich_grid_with_transitive_closure = Causal.enrich_grid
let enrich_big_grid_with_transitive_closure f = Causal.enrich_grid f Graph_closure.config_init
let enrich_small_grid_with_transitive_closure f = Causal.enrich_grid f Graph_closure.config_intermediary
let enrich_std_grid_with_transitive_closure f = Causal.enrich_grid f Graph_closure.config_std
					    
let sort_story_list  = D.sort_list 
let export_story_table x = sort_story_list (get_stories x)
let has_obs x = List.exists D.S.PH.B.PB.CI.Po.K.is_obs_of_refined_step (get_pretrace x)
				   
