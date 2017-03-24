let get_file_id (file : Api_types_j.file) = file.Api_types_j.file_metadata.Api_types_j.file_metadata_id
let patch_file
    (file_patch : Api_types_j.file_patch)
    (content : string) : string =
  let max_length = String.length content in
  let start_position : int = 0 in
  let start_length : int =
    match file_patch.Api_types_j.file_patch_start with
    | None -> 0
    | Some file_patch_start -> file_patch_start
  in
  let end_position : int =
    match file_patch.Api_types_j.file_patch_end with
    | None -> max_length
    | Some file_patch_end -> file_patch_end
  in
  let end_length : int =
    match file_patch.Api_types_j.file_patch_end with
    | None -> 0
    | Some file_patch_end -> max_length - file_patch_end
  in
  let start_string = String.sub content start_position start_length in
  let end_string = String.sub content end_position end_length in
  start_string ^
  file_patch.Api_types_j.file_patch_content ^
  end_string

let update_file
    (file : Api_types_j.file)
    (file_modification : Api_types_j.file_modification) : unit =
  let () = file.Api_types_j.file_metadata.Api_types_j.file_metadata_compile <-
      (match file_modification.Api_types_j.
               file_modification_compile
       with
       | None ->
         file.Api_types_j.
           file_metadata.Api_types_j.
           file_metadata_compile
       | Some file_content -> file_content)
  in
  let () = file.Api_types_j.file_metadata.Api_types_j.file_metadata_hash <-
      (match file_modification.Api_types_j.
               file_modification_hash
       with
       | None ->
         file.Api_types_j.
           file_metadata.Api_types_j.
           file_metadata_hash
       | Some file_metadata_hash ->
         Some file_metadata_hash)
  in
  let () = file.Api_types_j.file_metadata.Api_types_j.file_metadata_id <-
      (match file_modification.
               Api_types_j.
               file_modification_id
       with
       | None ->
         file.Api_types_j.
           file_metadata.Api_types_j.
           file_metadata_id
       | Some file_modification_id ->
         file_modification_id)
  in
  let () = file.Api_types_j.file_metadata.Api_types_j.file_metadata_position <-
      (match file_modification.Api_types_j.
               file_modification_position
       with
       | None ->
         file.Api_types_j.
           file_metadata.Api_types_j.
           file_metadata_position
       | Some file_metadata_position ->
         file_metadata_position)
  in
  let () = file.Api_types_j.file_content <-
      match file_modification.
              Api_types_j.
              file_modification_patch
           with
           | None -> file.Api_types_j.file_content
           | Some patch ->
             patch_file
               patch
               file.Api_types_j.file_content;
  in
  let () = file.Api_types_j.file_metadata.Api_types_j.file_metadata_version <-
      File_version.merge
         file.Api_types_j.file_metadata.Api_types_j.file_metadata_version
         file_modification.Api_types_j.file_modification_version
  in
  ()

let update_text project new_files handler =
  let version : Api_types_j.project_version = project#set_files new_files in
   handler version

type file_index = { file_index_file_id : Api_types_j.file_id ;
                    file_index_line_offset : int ;
                    file_index_char_offset : int ;
                    file_line_count : int ; }

(* modified from : https://searchcode.com/file/1109908/commons/common.ml *)

class manager_file
    (environment : Api_environment.environment)
    (system_process : Kappa_facade.system_process)
  : [Api_types_j.project_parse] Api.manager_file =
  object
    method file_catalog
        (project_id : Api_types_j.project_id) :
      Api_types_j.file_catalog Api.result Lwt.t =
    Api_common.ProjectOperations.bind
      project_id
      environment
      (fun (project : Api_environment.project) ->
         let files : Api_types_j.file list = (project#get_files ()) in
         let file_catalog : Api_types_j.file_catalog =
           { Api_types_j.file_metadata_list =
               List.map (fun file -> file.Api_types_j.file_metadata) files }
         in
         Lwt.return (Api_common.result_ok file_catalog)
      )

    method file_create
        (project_id : Api_types_j.project_id)
        (file : Api_types_j.file) :
      Api_types_j.file_metadata Api.result Lwt.t =
      Api_common.ProjectOperations.bind
        project_id
        environment
        (fun (project : Api_environment.project) ->
           let file_list : Api_types_j.file list = (project#get_files ()) in
           let file_eq : Api_types_j.file -> bool =
             fun f -> (get_file_id file) = (get_file_id f) in
           if List.exists file_eq file_list then
             let message : string =
               Format.sprintf
                 "file id %s exists"
	         (Api_common.FileCollection.identifier file)
             in
             Lwt.return
               (Api_common.result_error_msg
                  ~result_code:`CONFLICT message)
           else
             let file_list : Api_types_j.file list = project#get_files () in
             let version =
               file.Api_types_j.file_metadata.Api_types_j.file_metadata_version in
             let file =
               { file with
                 Api_types_j.file_metadata =
                   { file.Api_types_j.file_metadata
                     with Api_types_j.file_metadata_version = version } } in
             update_text
               project
               (file::file_list)
               (fun
                 (project_version : Api_types_j.project_version) ->
                 Lwt.return
                   (Api_common.result_ok
                      file.Api_types_j.file_metadata)
               )
        )

    method file_get
      (project_id : Api_types_j.project_id)
      (file_id : Api_types_j.file_id) :
      Api_types_j.file Api.result Lwt.t =
      Api_common.bind_file
        environment
        project_id
        file_id
        (fun _ (file : Api_types_j.file) ->
           Lwt.return (Api_common.result_ok file))

    method file_update
      (project_id : Api_types_j.project_id)
      (file_id : Api_types_j.file_id)
      (file_modification : Api_types_j.file_modification) :
      Api_types_j.file_metadata Api.result Lwt.t =
      Api_common.bind_file
        environment
        project_id
        file_id
        (fun
          (project : Api_environment.project)
          (file : Api_types_j.file) ->
          let () = update_file file file_modification in
          let file_list : Api_types_j.file list = (project#get_files ()) in
          update_text
            project
            file_list
            (fun
              (project_version : Api_types_j.project_version) ->
              Lwt.return
                (Api_common.result_ok file.Api_types_j.file_metadata
                )
            )
        )

    method file_delete
        (project_id : Api_types_j.project_id)
        (file_id : Api_types_j.file_id) :
      unit Api.result Lwt.t =
      Api_common.bind_file
        environment
        project_id
        file_id
        (fun (project : Api_environment.project) _ ->
           let file_list : Api_types_j.file list = (project#get_files ()) in
           let file_ne : Api_types_j.file -> bool =
             fun file -> (get_file_id file) <> file_id in
           let updated_directory = List.filter file_ne file_list in
           update_text
             project
             updated_directory
             (fun
               (project_version : Api_types_j.project_version) ->
               Lwt.return (Api_common.result_ok ())
             )
        )

  end;;
