open Lwt
module Api_types = ApiTypes_j
open Api_types

let time_yield (seconds : float)
               (yield : (unit -> unit Lwt.t)) : (unit -> unit Lwt.t) =
  let lastyield = ref (Sys.time ()) in
  fun () -> let t = Sys.time () in
            if t -. !lastyield > seconds then
              let () = lastyield := t in
              yield ()
            else Lwt.return_unit

let () = Printexc.record_backtrace true

type runtime = < parse : Api_types.code -> Api_types.parse Api_types.result Lwt.t;
                 start : Api_types.parameter -> Api_types.token Api_types.result Lwt.t;
                 status : Api_types.token -> Api_types.state Api_types.result Lwt.t;
                 list : unit -> Api_types.catalog Api_types.result Lwt.t;
                 stop : Api_types.token -> unit Api_types.result Lwt.t >;;

module Base : sig
  class virtual runtime : object
                            method parse : Api_types.code -> Api_types.parse Api_types.result Lwt.t
                            method start : Api_types.parameter -> Api_types.token Api_types.result Lwt.t
                            method status : Api_types.token -> Api_types.state Api_types.result Lwt.t
                            method list : unit -> Api_types.catalog Api_types.result Lwt.t
                            method stop : Api_types.token -> unit Api_types.result Lwt.t
                            method virtual log : string -> unit Lwt.t
                            method virtual yield : unit -> unit Lwt.t
                          end;;
end = struct
  module IntMap = Map.Make(struct type t = int let compare = compare end)
  type simulator_state = { switch : Lwt_switch.t
                         ; counter : Counter.t
                         ; log_buffer : Buffer.t
                         ; plot : Api_types.plot ref
                         ; snapshots : Api_types.snapshot list ref
                         ; flux_maps : Api_types.flux_map list ref
                         ; files : Api_types.file_line list ref
                         ; error_messages : string list ref
                         }
  type context = { states : simulator_state IntMap.t
                  ; id : int }

  let format_error_message (message,linenumber) =
    Format.sprintf "Error at %s : %s"
                   (Location.to_string linenumber)
                   message
  let build_ast (code : string) success failure (log : string -> unit Lwt.t) =
    let lexbuf : Lexing.lexbuf = Lexing.from_string code in
    try
      let raw_ast =
        KappaParser.start_rule KappaLexer.token lexbuf Ast.empty_compil in
      let ast :
            Signature.s * unit NamedDecls.t *
              (Ast.agent, LKappa.rule_agent list, int, LKappa.rule) Ast.compil
        = LKappa.compil_of_ast [] raw_ast in
      let contact_map,_kasa_state =
        Eval.init_kasa Format.std_formatter raw_ast
      in success (ast,contact_map)
    with ExceptionDefn.Syntax_Error e ->
         failure (format_error_message e)
       | ExceptionDefn.Malformed_Decl e ->
         failure (format_error_message e)
       | e -> let () = Lwt.async (fun () -> (log (Printexc.to_string e))
                                            >>=
                                              (fun _ -> log (Printexc.get_backtrace ()))) in
              raise e

  class virtual runtime =
  object(self)
  method virtual log : string -> unit Lwt.t
  method virtual yield : unit -> unit Lwt.t
  val mutable context = { states = IntMap.empty
                         ; id = 0 }
    method parse (code : Api_types.code) : Api_types.parse Api_types.result Lwt.t =
      build_ast code
                (fun ((signature,_,ast),_) ->
                 let observables : string list =
                   List.map
                     (fun ((annotation : (LKappa.rule_agent list, int) Ast.ast_alg_expr),_) ->
                      let str = Format.asprintf "%a" (Ast.print_ast_alg (LKappa.print_rule_mixture signature)
                                                                        (Format.pp_print_int)
                                                                        (Format.pp_print_int))
                                                annotation
                      in str
                     )
                     (ast.Ast.observables : (LKappa.rule_agent list, int) Ast.ast_alg_expr Location.annot list)

                 in
                 Lwt.return (`Right { observables = observables } ))
                (fun e -> Lwt.return (`Left [e]))
                self#log
    method private new_id () : int =
      let result = context.id + 1 in
      let () = context <- { context with id = context.id + 1 } in
      result

    method start (parameter : Api_types.parameter) : Api_types.token Api_types.result Lwt.t =
      if parameter.nb_plot > 0 then
        catch
        (fun () ->
         match
           build_ast parameter.code
                     (fun ast -> `Right ast)
                     (fun e -> `Left [e])
                     self#log
         with
           `Right ((sig_nd,tk_nd,result),contact_map) ->
           let current_id = self#new_id () in
           let plot : Api_types.plot ref = ref { Api_types.legend = [];
                                                 Api_types.observables = [] } in
           let error_messages : string list ref = ref [] in
           let snapshots : Api_types.snapshot list ref = ref [] in
           let flux_maps : Api_types.flux_map list ref = ref [] in
           let files : Api_types.file_line list ref = ref [] in
           let outputs (data : Data.t) =
             match data with
               Data.Flux flux_map ->
               flux_maps := ((Api_data.api_flux_map flux_map)::!flux_maps)
             | Data.Plot (time,new_observables) ->
                let new_values : float list = List.map (fun nbr -> Nbr.to_float nbr) (Array.to_list new_observables) in
                plot := {!plot with Api_types.observables = { Api_types.time = time ; values = new_values }
                                                            :: !plot.Api_types.observables }
             | Data.Print file_line ->
                files := ((Api_data.api_file_line file_line)::!files)
             | Data.Snapshot snapshot ->
                snapshots := ((Api_data.api_snapshot snapshot)::!snapshots)
             | Data.UnaryDistances _ -> ()
           in
           let simulation = { switch = Lwt_switch.create ()
                            ; counter = Counter.create
                                          ~init_t:(0. : float)
                                          ~init_e:(0 : int)
                                          ?max_t:parameter.max_time
                                          ?max_e:parameter.max_events
                                          ~nb_points:(parameter.nb_plot : int)
                            ; log_buffer = Buffer.create 512
                            ; plot = plot
                            ; error_messages = error_messages
                            ; snapshots = snapshots
                            ; flux_maps = flux_maps
                            ; files = files
                            } in
           let () = context <- { context with states = IntMap.add current_id simulation context.states } in
           let log_form = Format.formatter_of_buffer simulation.log_buffer in
           let () = Counter.reinitialize simulation.counter in
           let () = Lwt.async
                      (fun () ->
                       (catch
                          (fun () ->
                           wrap6 (Eval.initialize ?rescale_init:None)
                                 log_form sig_nd tk_nd contact_map
                                 simulation.counter result
                           >>= (fun (env,domain,graph,state) ->
                                let legend = Environment.map_observables
                                               (Format.asprintf "%a" (Kappa_printer.alg_expr ~env))
                                               env
                                in
                                let () = plot := { !plot with legend = Array.to_list legend} in
				let rec iter graph state =
				  let (stop,graph',state') =
                                    State_interpreter.a_loop
                                      ~outputs:outputs log_form
				      env domain simulation.counter graph state in
				  if not (Lwt_switch.is_on simulation.switch) || stop then
				    let () = State_interpreter.end_of_simulation
                                      ~outputs:outputs log_form env simulation.counter graph state in
				    Lwt_switch.turn_off simulation.switch
				  else Lwt.bind (self#yield ()) (fun () -> iter graph' state') in
				iter graph state)
                          )
                          (function
                            | ExceptionDefn.Malformed_Decl error ->
                               let () = error_messages := [format_error_message error] in
                               Lwt.return_unit
                            | ExceptionDefn.Internal_Error error ->
                               let () = error_messages := [format_error_message error] in
                               Lwt.return_unit
                            | Invalid_argument error ->
                               let () = error_messages := [Format.sprintf "Runtime error %s" error] in
                               Lwt.return_unit
                            | e ->
                                    (self#log (Printexc.get_backtrace ()))
                                    >>=
                                      (fun _ ->
                                       let () = error_messages := [Printexc.to_string e] in
                                       self#log (Printexc.to_string e))
                                    >>=
                                      (fun _ -> Lwt.return_unit)
                          )
                       )
                      )
           in
           Lwt.return (`Right current_id)
         | `Left e ->  Lwt.return (`Left e)
        )
        (function
          | ExceptionDefn.Malformed_Decl error ->
             Lwt.return (`Left [format_error_message error])
          | ExceptionDefn.Internal_Error error ->
             Lwt.return (`Left [format_error_message error])
          | Invalid_argument error ->
             let message = Format.sprintf "Runtime error %s" error in
             Lwt.return (`Left [message])
          | Sys_error message ->
             Lwt.return (`Left [message])
          | e -> (self#log (Printexc.get_backtrace ()))
                 >>= (fun _ -> Lwt.return (`Left [Printexc.to_string e]))
        )
      else
        Lwt.return (`Left ["Plot observables must be greater than zero"])

    method status (token : Api_types.token) : Api_types.state Api_types.result Lwt.t =
      Lwt.catch
        (fun () ->
         let state : simulator_state = IntMap.find token context.states in
         let () = if Lwt_switch.is_on state.switch then
                    ()
                  else
                    context <- { context with states = IntMap.remove token context.states }
         in
         Lwt.return
           (match !(state.error_messages) with
             [] ->
             `Right ({ Api_types.plot = Some !(state.plot);
                       Api_types.time = Counter.time state.counter;
                       Api_types.time_percentage = Counter.time_percentage state.counter;
                       Api_types.event = Counter.event state.counter;
                       Api_types.event_percentage = Counter.event_percentage state.counter;
                       Api_types.tracked_events = Some (Counter.tracked_events state.counter);
                       Api_types.log_messages = [Buffer.contents state.log_buffer] ;
                       Api_types.snapshots = !(state.snapshots);
                       Api_types.flux_maps = !(state.flux_maps);
                       Api_types.files = !(state.files);
                       is_running = Lwt_switch.is_on state.switch
                    } : Api_types.state )
            | _ -> `Left !(state.error_messages))
        )
        (function Not_found -> Lwt.return (`Left ["token not found"])
                | e -> (self#log (Printexc.get_backtrace ()))
                       >>= (fun _ -> Lwt.return (`Left [Printexc.to_string e]))
        )
    method list () : Api_types.catalog Api_types.result Lwt.t =
      Lwt.return (`Right (List.map fst (IntMap.bindings context.states)))

    method stop (token : Api_types.token) : unit Api_types.result Lwt.t =
    catch
      (fun () ->
       let state : simulator_state = IntMap.find token context.states in
       if Lwt_switch.is_on state.switch then
         Lwt_switch.turn_off state.switch
         >>= (fun _ -> Lwt.return (`Right ()))
       else
         Lwt.return (`Left ["process not running"]))
      (function Not_found -> Lwt.return (`Left ["token not found"])
              | e -> Lwt.return (`Left [Printexc.to_string e])
      )
  end;;
end;;
