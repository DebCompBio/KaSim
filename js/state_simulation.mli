(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

type t

val t_simulation_id : t -> Api_types_j.simulation_id
val t_simulation_info : t -> Api_types_j.simulation_info option

type model = t option

val dummy_model : model
val model : model React.signal
val model_simulation_info : model -> Api_types_j.simulation_info option
type model_state = STOPPED | INITALIZING | RUNNING | PAUSED
val model_state_to_string : model_state -> string
val model_simulation_state : t option -> model_state option

(* run on application init *)
val init : unit -> unit Lwt.t
(* to synch state of application with runtime *)
val sync : unit -> unit Api.result Lwt.t

val with_simulation :
  label:string ->
  (Api.manager -> Api_types_j.project_id -> t -> 'a  Api.result Lwt.t) ->
  'a  Api.result Lwt.t

val with_simulation_info :
  label:string ->
  ?stopped:(Api.manager ->
            Api_types_j.project_id ->
            Api_types_j.simulation_id -> unit Api.result Lwt.t) ->
  ?initializing:(Api.manager ->
                 Api_types_j.project_id ->
                 Api_types_j.simulation_id -> unit Api.result Lwt.t) ->
  ?ready:(Api.manager ->
          Api_types_j.project_id ->
          Api_types_j.simulation_id ->
          Api_types_j.simulation_info -> unit Api.result Lwt.t) ->
  unit -> unit Api.result Lwt.t

val when_ready :
  label:string ->
  ?handler:(unit Api.result -> unit Lwt.t) ->
  (Api.manager -> Api_types_j.project_id -> Api_types_j.simulation_id -> unit Api.result Lwt.t) ->
  unit

val continue_simulation : Api_types_j.simulation_parameter -> unit Api.result Lwt.t
val pause_simulation : unit -> unit Api.result Lwt.t
val stop_simulation : unit -> unit Api.result Lwt.t
val start_simulation : Api_types_j.simulation_parameter -> unit Api.result Lwt.t
val perturb_simulation : string -> unit Api.result Lwt.t
