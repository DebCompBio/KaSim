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
