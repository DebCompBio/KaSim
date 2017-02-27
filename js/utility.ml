(******************************************************************************)
(*  _  __ * The Kappa Language                                                *)
(* | |/ / * Copyright 2010-2017 CNRS - Harvard Medical School - INRIA - IRIF  *)
(* | ' /  *********************************************************************)
(* | . \  * This file is distributed under the terms of the                   *)
(* |_|\_\ * GNU Lesser General Public License Version 3                       *)
(******************************************************************************)

let split (s : string) (delimiter : char) : (string * string option) =
  try
    let index = String.index s delimiter in
    let length = String.length s in
    (String.sub s 0 index,
     Some (String.sub
             s
             (index + 1)
             (length - index - 1) ))
  with Not_found -> (s,None)

let input_float_string (value : float) : string =
  let n = string_of_float value in
  let length = String.length n in
  if length > 0 && String.get n (length - 1) = '.' then
    n^"0"
  else
    n
