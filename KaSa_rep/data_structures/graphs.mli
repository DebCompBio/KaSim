type node

val node_of_int: int -> node

module NodeMap: SetMap.Map with type elt = node

module Nodearray :
  Int_storage.Storage
    with type key = node
     and type dimension = int

type ('node_label,'edge_label) graph

val create:
  Remanent_parameters_sig.parameters ->
  Exception.method_handler ->
  (node -> 'node_label) -> node list ->
  (node * 'edge_label * node) list ->
  ('node_label, 'edge_label) graph

val add_bridges:
  ?low:int Nodearray.t ->
  ?pre:int Nodearray.t ->
  Remanent_parameters_sig.parameters ->
  Exception.method_handler ->
  ('a -> string) ->
  ('b -> string) ->
  ('a, 'b) graph ->
  ('a  * 'b * 'a) list ->
  Exception.method_handler *
  (int Nodearray.t * int Nodearray.t *
   ('a * 'b * 'a) list)
