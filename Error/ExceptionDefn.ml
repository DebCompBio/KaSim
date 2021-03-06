(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

exception IntFound of int
exception StringFound of string
exception MapFound of (int Mods.IntMap.t)
exception False
exception True
exception Break of int

(* 0:unary rule with binary instance *)
(* 1:binary rule with unary instance *)
(* 2:clashing instance *)
(* 3:overapproximation clash *)
(* 4:invalid injection clash *)
(* 5: perturbation interrupting time*)
exception Null_event of int
exception StopReached of string

exception Syntax_Error of string Locality.annot
exception Malformed_Decl of string Locality.annot
exception Internal_Error of string Locality.annot
exception Unsatisfiable

let warning_buffer:
      (Locality.t option*(Format.formatter -> unit)) list ref = ref []

let warning ?pos msg =
  warning_buffer :=(pos,msg)::!warning_buffer

let deprecated ~pos entry msg =
  warning ~pos (fun f -> Format.fprintf f "Deprecated %s syntax:@ %t" entry msg)

let flush_warning f =
  let l = List.rev !warning_buffer in
  let () = warning_buffer := [] in
  List.iter (fun (pos,msg) ->
	     let pr f () = Format.fprintf f "Warning: @[%t@]" msg in
	     match pos with
	     | Some pos ->
		Format.fprintf f "@[<v>%a@]@." (Locality.print_annot pr) ((),pos)
	     | None -> Format.fprintf f "@[%a@]@." pr ()) l
