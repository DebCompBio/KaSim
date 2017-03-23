exception BadResponse of Mpi_message_j.response

val on_message : Api.manager -> (string -> unit Lwt.t) -> string -> unit Lwt.t

class type virtual manager_base_type =
  object
    method virtual message :
      Mpi_message_j.request ->
      Mpi_message_j.response Api.result Lwt.t

    inherit Api.manager
end

class virtual manager_base : unit -> manager_base_type

class type virtual manager_mpi_type =
  object
    method virtual post_message : string -> unit
    method virtual sleep : float -> unit Lwt.t
    method virtual post_message : string -> unit
    method message : Mpi_message_j.request -> Mpi_message_j.response Api.result Lwt.t
    method receive : string -> unit

    inherit Api.manager
  end

class virtual manager : unit -> manager_mpi_type

val default_message_delimter : char
