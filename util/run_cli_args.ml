(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

type t = {
  mutable minValue            : float option;
  mutable maxValue            : float option;
  mutable plotPeriod          : float option;
  mutable inputKappaFileNames : string list;
  mutable outputDataFile      : string option;
  mutable outputDirectory     : string;
  mutable batchmode           : bool;
  mutable interactive         : bool;
  mutable newSyntax          : bool;
}

type t_gui =
  {
    minValue_gui            : float option ref;
    maxValue_gui            : float option ref;
    plotPeriod_gui          : float option ref;
    inputKappaFileNames_gui : string list ref;
    (*  initialMix_gui          : string option ref;*)
    outputDataFile_gui      : string option ref;
    outputDirectory_gui     : string ref;
    newSyntax_gui           : bool ref;
    batchmode_gui           : string ref;
  }

let default : t = {
  minValue = None ;
  maxValue = None;
  plotPeriod = None;
  inputKappaFileNames = [];
  outputDataFile = None;
  outputDirectory = ".";
  newSyntax = false;
  batchmode = false;
  interactive = false;
}

let default_gui =
  {
    minValue_gui = ref (Some 0.);
    maxValue_gui = ref  (Some 1.);
    plotPeriod_gui = ref (Some 0.01);
    inputKappaFileNames_gui = ref [];
    (*  initialMix_gui = ref None;*)
    outputDataFile_gui = ref (Some "data.csv");
    outputDirectory_gui = ref ".";
    newSyntax_gui = ref false;
    batchmode_gui = ref "interactive";
  }

let rec aux l accu =
  match l with
  | (v,var_val)::tail ->
    aux tail
      ((v,
        (try Nbr.of_string var_val with
           Failure _ ->
           raise (Arg.Bad ("\""^var_val^"\" is not a valid value"))))   ::accu)
  | [] -> accu

let get_from_gui t_gui =
  {
    minValue = !(t_gui.minValue_gui);
    maxValue = !(t_gui.maxValue_gui);
    plotPeriod = !(t_gui.plotPeriod_gui);
    inputKappaFileNames = !(t_gui.inputKappaFileNames_gui);
    (*initialMix = !(t_gui.initialMix_gui);*)
    outputDataFile = !(t_gui.outputDataFile_gui);
    outputDirectory = !(t_gui.outputDirectory_gui);
    newSyntax = !(t_gui.newSyntax_gui);
    batchmode  = (Tools.lowercase (!(t_gui.batchmode_gui)))="batch" ;
    interactive = (Tools.lowercase (!(t_gui.batchmode_gui)))="interactive";
}

let copy_from_gui t_gui t =
  let t_tmp = get_from_gui t_gui in
  t.minValue <- t_tmp.minValue;
  t.maxValue <- t_tmp.maxValue;
  t.plotPeriod <- t_tmp.plotPeriod;
  t.inputKappaFileNames <- t_tmp.inputKappaFileNames;
  (*t.initialMix <- t_tmp.initialMix;*)
  t.outputDataFile <- t_tmp.outputDataFile;
  t.outputDirectory <- t_tmp.outputDirectory;
  t.newSyntax <- t_tmp.newSyntax ;
  t.batchmode <- t_tmp.batchmode ;
  t.interactive <- t_tmp.interactive

let options_gen (t :t) (t_gui :t_gui) : (string * Arg.spec * Superarg.spec * string * string list * Superarg.level) list = [
  ("-i",
   Arg.String (fun fic ->
       t.inputKappaFileNames <- fic::t.inputKappaFileNames),
   Superarg.String_list t_gui.inputKappaFileNames_gui,
   "name of a kappa file to use as input (can be used multiple times for multiple input files)",
  [],Superarg.Hidden);
  ("-initial",
   Arg.Float (fun time -> t.minValue <- Some time),
   (Superarg.Float_opt t_gui.minValue_gui),
   "Min time of simulation (arbitrary time unit)",
   ["0_model";"3_integration_settings"],Superarg.Normal);
  ("-l",
   Arg.Float(fun time -> t.maxValue <- Some time),
   (Superarg.Float_opt t_gui.maxValue_gui),
   "Limit of the simulation",
   ["0_model";"3_integration_settings"],Superarg.Normal);
  ("-t",
   Arg.Float (fun f ->
       raise (Arg.Bad ("Option '-t' has been replace by '[-u time] -l "^
                       string_of_float f^"'"))),
  (Superarg.Float_opt t_gui.maxValue_gui),
   "Deprecated option",
  [],Superarg.Hidden);
  ("-p",
   Arg.Float (fun pointNumberValue -> t.plotPeriod <- Some pointNumberValue),
   Superarg.Float_opt t_gui.plotPeriod_gui,
   "plot period: time interval between points in plot (default: 1.0)",
  ["0_model";"3_integration_settings"],Superarg.Normal);
  ("-o",
   Arg.String
     (fun outputDataFile -> t.outputDataFile <- Some outputDataFile),
   Superarg.String_opt t_gui.outputDataFile_gui,
   "file name for data output",
   ["0_model"; "3_integration_settings"], Superarg.Hidden) ;
  ("-d",
   Arg.String (fun outputDirectory -> t.outputDirectory <- outputDirectory),
   Superarg.String t_gui.outputDirectory_gui,
   "Specifies directory name where output file(s) should be stored",
   ["1_output"], Superarg.Normal) ;
   ("-mode",
    Arg.String
      (fun m -> if m = "batch" then t.batchmode <- true
        else if m = "interactive" then t.interactive <- true),
    Superarg.Choice
      (["batch","batch mode";"interactive","interactive mode"],[],t_gui.batchmode_gui),
    "either \"batch\" to never ask anything to the user or \"interactive\" to ask something before doing anything",
    [], Superarg.Hidden) ;
   ("--new-syntax",
    Arg.Unit (fun () -> t.newSyntax <- true),
    Superarg.Bool t_gui.newSyntax_gui,
    "Use explicit notation for free site",
    [], Superarg.Hidden);
]

let options t =
  List.rev_map
    (fun (a,b,_,c,_,_) -> a,b,c)
    (List.rev (options_gen t default_gui))

let options_gui t_gui =
  (List.rev_map
    (fun (a,_,b,c,d,e) -> a,b,c,d,e)
    (List.rev (options_gen default t_gui)))
  @[
    "--output-plot",
  Superarg.String_opt t_gui.outputDataFile_gui,
  "file name for data output",
  ["1_output";"2_semantics";"3_integration_settings"],Superarg.Normal;
  "--data-file",
  Superarg.String_opt t_gui.outputDataFile_gui,
  "file name for data output",
  ["1_output";"2_semantics";"3_integration_settings"],Superarg.Hidden;]
