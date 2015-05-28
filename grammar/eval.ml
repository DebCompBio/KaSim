open Mods
open Tools
open Ast

type link = Closed | Semi of (int * int) Term.with_pos

type context =
    { pairing : link IntMap.t; curr_id : int;
      new_edges : (int * int) Int2Map.t }

let eval_intf ast_intf =
  let rec iter ast_intf map =
    match ast_intf with
    | p :: ast_interface ->
       let int_state_list = p.Ast.port_int
       and lnk_state = p.Ast.port_lnk
       in
       if StringMap.mem (fst p.Ast.port_nme) map then
	 raise
	   (ExceptionDefn.Malformed_Decl
	      ("Site '" ^ (fst p.Ast.port_nme) ^ "' is used multiple times",
	       snd p.Ast.port_nme))
       else
	 iter ast_interface
	      (StringMap.add
		 (fst p.Ast.port_nme)
		 (int_state_list, lnk_state, (snd p.Ast.port_nme))
		 map)
    | [] ->
       StringMap.add
	 "_" ([], Term.with_dummy_pos Ast.FREE,(Lexing.dummy_pos,Lexing.dummy_pos)) map
  in (*Adding default existential port*) iter ast_intf StringMap.empty

let initial_value_alg counter env (ast, _) =
  Expr_interpreter.value_alg
    counter
    ~get_alg:(fun i ->
	      fst (snd env.Environment.algs.NamedDecls.decls.(i)))
    ~get_mix:(fun _ -> Nbr.zero) ~get_tok:(fun _ -> Nbr.zero) ast

let tokenify algs tokens contact_map domain l =
  List.fold_right
    (fun (alg_expr,(nme,pos)) (domain,out) ->
     let id =
       try StringMap.find nme tokens
       with Not_found ->
	 raise (ExceptionDefn.Malformed_Decl
		  ("Token "^nme^" is undefined",pos))
     in
     let (domain',(alg,_pos)) =
       Expr.compile_alg algs tokens contact_map domain alg_expr in
     (domain',(alg,id)::out)
    ) l (domain,[])

let rules_of_ast algs tokens contact_map domain
		    label_opt (ast_rule,rule_pos) =
  let label = match label_opt with
    | None -> Term.with_dummy_pos ("%anonymous"^(string_of_float (Sys.time ())))
    | Some (lab,pos) -> (lab,pos) in
  let opposite (lab,pos) = (lab^"_op",pos) in
  let domain',rm_toks =
    tokenify algs tokens contact_map domain ast_rule.rm_token in
  let domain'',add_toks =
    tokenify algs tokens contact_map domain' ast_rule.add_token in
  let one_side label (domain,acc) rate lhs rhs rm add =
    let domain',(crate,_) =
      Expr.compile_alg algs tokens contact_map domain rate in
    let count = let x = ref 0 in fun (lab,pos) ->
				 incr x; (lab^"__"^string_of_int !x,pos) in
    let build (ccs,(neg,pos)) =
      {
	Primitives.rate = crate;
	Primitives.connected_components = ccs;
	Primitives.removed = neg;
	Primitives.inserted = pos;
	Primitives.consumed_tokens = rm;
	Primitives.injected_tokens = add;
      } in
    let domain'',rule_mixtures =
      Snip.connected_components_sum_of_ambiguous_rule
	contact_map domain' lhs rhs in
    domain'',
    match rule_mixtures with
    | [] -> acc
    | [ r ] -> (label, build r) :: acc
    | _ ->
       List.fold_left
	 (fun out r ->
	  (count label,build r)::out) acc rule_mixtures in
  let rev = match ast_rule.arrow, ast_rule.k_op with
    | RAR, None -> domain'',[]
    | LRAR, Some rate ->
       one_side (opposite label) (domain'',[]) rate
		ast_rule.rhs ast_rule.lhs add_toks rm_toks
    | (RAR, Some _ | LRAR, None) ->
       raise
	 (ExceptionDefn.Malformed_Decl
	    ("Incompatible arrow and kinectic rate for inverse definition",
	     rule_pos))
  in
  one_side label rev ast_rule.k_def ast_rule.lhs ast_rule.rhs rm_toks add_toks

let obs_of_result env domain res =
  let (domain',cont) =
    List.fold_left
      (fun (domain,cont) alg_expr ->
       let (domain',(alg_pos)) =
	 Expr.compile_alg env.Environment.algs.NamedDecls.finder
			  env.Environment.tokens.NamedDecls.finder
			  env.Environment.contact_map domain
			  alg_expr in
       domain',alg_pos :: cont)
      (domain,[]) res.observables in
  (env,domain',cont)

let compile_print_expr env domain ex =
  List.fold_right
    (fun (el,pos) (domain,out) ->
     match el with
     | Ast.Str_pexpr s -> (domain,(Ast.Str_pexpr s,pos)::out)
     | Ast.Alg_pexpr ast_alg ->
	let (domain', (alg,_pos)) =
	  Expr.compile_alg env.Environment.algs.NamedDecls.finder
			   env.Environment.tokens.NamedDecls.finder
			   env.Environment.contact_map domain
			   (ast_alg,pos) in
	(domain',(Ast.Alg_pexpr alg,pos)::out))
    ex (domain,[])

let effects_of_modif env domain ast_list =
  let rec iter rev_effects env domain ast_list =
    let rule_effect alg_expr ast_rule mix_pos =
      let (domain',alg_pos) =
	Expr.compile_alg env.Environment.algs.NamedDecls.finder
			 env.Environment.tokens.NamedDecls.finder
			 env.Environment.contact_map domain
			 alg_expr in
      let domain'',elem_rules =
	rules_of_ast env.Environment.algs.NamedDecls.finder
			env.Environment.tokens.NamedDecls.finder
			env.Environment.contact_map domain'
			None (ast_rule,mix_pos) in
      let elem_rule = match elem_rules with
	| [ _, r ] -> r
	| _ ->
	   raise
	     (ExceptionDefn.Malformed_Decl
		("Ambiguous rule in perturbation is impossible",mix_pos)) in
      (env,domain'',
       (Primitives.ITER_RULE (alg_pos, elem_rule))::rev_effects) in
    match ast_list with
    | [] -> (env,domain,List.rev rev_effects)
    | ast::tl ->
       let (env,domain,rev_effects) =
	 match ast with
	 | INTRO (alg_expr, (ast_mix,mix_pos)) ->
	    let ast_rule =
	      { add_token=[]; rm_token=[]; lhs = []; arrow = Ast.RAR;
		rhs = ast_mix; k_def=Term.with_dummy_pos (Ast.CONST Nbr.zero);
		k_un=None;k_op=None;
	      } in
	    rule_effect alg_expr ast_rule mix_pos
	 | DELETE (alg_expr, (ast_mix, mix_pos)) ->
	    let ast_rule =
	      { add_token=[]; rm_token=[]; lhs = ast_mix; arrow = Ast.RAR;
		rhs = [];
		k_def=Term.with_dummy_pos (Ast.CONST Nbr.zero);
		k_un=None;k_op=None;
	      } in
	    rule_effect alg_expr ast_rule mix_pos
	 | UPDATE ((nme, pos_rule), alg_expr) ->
	    let i,is_rule =
	      (try (Environment.num_of_rule nme env,true)
	       with
	       | Not_found ->
		  try
		    (Environment.num_of_alg nme env, false)
		  with Not_found ->
		    raise (ExceptionDefn.Malformed_Decl
			     ("Variable " ^ (nme ^ " is neither a constant nor a rule")
			     ,pos_rule))
	      ) in
	    let (domain', alg_pos) =
	      Expr.compile_alg env.Environment.algs.NamedDecls.finder
			       env.Environment.tokens.NamedDecls.finder
			       env.Environment.contact_map domain
			       alg_expr in
	    (env,domain',
	     (Primitives.UPDATE ((if is_rule then Term.RULE i
	      else Term.ALG i), alg_pos))::rev_effects)
	 | UPDATE_TOK ((tk_nme,tk_pos),alg_expr) ->
	    let ast_rule =
	      { add_token=[(alg_expr,(tk_nme,tk_pos))];
		rm_token=[Term.with_dummy_pos (Ast.TOKEN_ID tk_nme),
			  (tk_nme,tk_pos)];
		arrow = Ast.RAR; lhs=[]; rhs=[];
		k_def=Term.with_dummy_pos (Ast.CONST Nbr.zero);
		k_un=None; k_op= None; } in
	    rule_effect (Term.with_dummy_pos (Ast.CONST (Nbr.one)))
			ast_rule tk_pos
	 | SNAPSHOT (pexpr,_) ->
	    let (domain',pexpr') =
	      compile_print_expr env domain pexpr in
	    (*when specializing snapshots to particular mixtures, add variables below*)
	    (env,domain',
	     (Primitives.SNAPSHOT pexpr')::rev_effects)
	 | STOP (pexpr,_) ->
	    let (domain',pexpr') =
	      compile_print_expr env domain pexpr in
	    (env,domain',
	     (Primitives.STOP pexpr')::rev_effects)
	 | CFLOW ((lab,pos_lab),_) ->
	    let id =
	      try Environment.num_of_rule lab env
	      with Not_found ->
		try let var = Environment.num_of_alg lab env in
		    match env.Environment.algs.NamedDecls.decls.(var) with
		    |(_,(Expr.KAPPA_INSTANCE _,_)) -> -1 (* TODO Later *)
		    | (_,((Expr.CONST _ | Expr.BIN_ALG_OP _ | Expr.TOKEN_ID _ |
			   Expr.STATE_ALG_OP _ | Expr.UN_ALG_OP _ |
			   Expr.ALG_VAR _),_)) -> raise Not_found
		with Not_found ->
		  raise	(ExceptionDefn.Malformed_Decl
			   ("Label '" ^ lab ^ "' is neither a rule nor a Kappa expression"
			   ,pos_lab))
	    in
	    (env,domain,
	     (Primitives.CFLOW id)::rev_effects)
	 | CFLOWOFF ((lab,pos_lab),_) ->
	    let id =
	      try Environment.num_of_rule lab env
	      with Not_found ->
		try let var = Environment.num_of_alg lab env in
		    match env.Environment.algs.NamedDecls.decls.(var) with
		    |(_,(Expr.KAPPA_INSTANCE _,_)) -> -1 (* TODO Later *)
		    | (_,((Expr.CONST _ | Expr.BIN_ALG_OP _ | Expr.TOKEN_ID _ |
			   Expr.STATE_ALG_OP _ | Expr.UN_ALG_OP _ |
			   Expr.ALG_VAR _),_)) -> raise Not_found
		with Not_found ->
		  raise	(ExceptionDefn.Malformed_Decl
			   ("Label '" ^ lab ^ "' is neither a rule nor a Kappa expression"
			   ,pos_lab))
	    in
	    (env,domain,
	     (Primitives.CFLOWOFF id)::rev_effects)
	 | FLUX (pexpr,_) ->
	    let (domain',pexpr') = compile_print_expr env domain pexpr in
	    (env,domain',
	     (Primitives.FLUX pexpr')::rev_effects)
	 | FLUXOFF (pexpr,_) ->
	    let (domain',pexpr') = compile_print_expr env domain pexpr in
	    (env,domain',
	     (Primitives.FLUXOFF pexpr')::rev_effects)
	 | PRINT (pexpr,print,_) ->
	    let (domain',pexpr') = compile_print_expr env domain pexpr in
	    let (domain'',print') = compile_print_expr env domain' print in
	    (env,domain'',
	     (Primitives.PRINT (pexpr',print'))::rev_effects)
	 | PLOTENTRY ->
	    (env,domain,
	     (Primitives.PLOTENTRY)::rev_effects)
       in
       iter rev_effects env domain tl
  in
  iter [] env domain ast_list

let pert_of_result env domain res =
  let (env, domain, _, lpert, stop_times) =
    List.fold_left
      (fun (env, domain, p_id, lpert, stop_times)
	   ((pre_expr, modif_expr_list, opt_post),pos) ->
       let (domain',(pre,pos_pre)) =
	 Expr.compile_bool env.Environment.algs.NamedDecls.finder
			   env.Environment.tokens.NamedDecls.finder
			   env.Environment.contact_map domain pre_expr in
       let (dep, stopping_time) =
	 try Expr.deps_of_bool_expr pre
	 with ExceptionDefn.Unsatisfiable ->
	   raise
	     (ExceptionDefn.Malformed_Decl
		("Precondition of perturbation is using an invalid equality test on time, I was expecting a preconditon of the form [T]=n"
		,pos_pre))
       in
       let (env,domain, effects) =
	 effects_of_modif env domain' modif_expr_list in
       let env,domain,opt_abort =
	 match opt_post with
	 | None ->
	    (env,domain,None)
	 | Some post_expr ->
	    let (domain',(post,_pos)) =
	      Expr.compile_bool env.Environment.algs.NamedDecls.finder
				env.Environment.tokens.NamedDecls.finder
				env.Environment.contact_map domain post_expr in
	    let (dep,stopping_time') =
	      try Expr.deps_of_bool_expr post with
		ExceptionDefn.Unsatisfiable ->
		raise
		  (ExceptionDefn.Malformed_Decl
		     ("Precondition of perturbation is using an invalid equality test on time, I was expecting a preconditon of the form [T]=n"
		     ,pos))
	    in
	    (env,domain',Some (post,dep,stopping_time'))
       in
       let has_tracking = env.Environment.tracking_enabled
			  || List.exists
			       (function
				 | Primitives.CFLOW _ -> true
				 | (Primitives.CFLOWOFF _ | Primitives.PRINT _ |
				    Primitives.UPDATE _ | Primitives.SNAPSHOT _
				    | Primitives.FLUX _ | Primitives.FLUXOFF _ |
				    Primitives.PLOTENTRY | Primitives.STOP _ |
				    Primitives.ITER_RULE _) -> false) effects in
       let env =
	 Term.DepSet.fold
	   (fun dep -> Environment.add_dependencies dep (Term.PERT p_id))
	   dep
	   { env with Environment.tracking_enabled = has_tracking } in
       (*let env = List.fold_left (fun env (r_opt,effect) -> Environment.bind_pert_rule p_id r.r_id env) env effect_list in *)
       let opt,env,stopping_time =
	 match opt_abort with
	 | None -> (None,env,stopping_time)
	 | Some (post,dep,stopping_time') ->
	    let env =
	      Term.DepSet.fold
		(fun dep_type env ->
		 Environment.add_dependencies dep_type (Term.ABORT p_id) env
		)
		dep env
	    in
	    (Some post,env,stopping_time'@stopping_time)
       in
       let pert =
	 { Primitives.precondition = pre;
	   Primitives.effect = effects;
	   Primitives.abort = opt;
	   Primitives.stopping_time = stopping_time
	 }
       in
       (env, domain, succ p_id, pert::lpert,
	List.fold_left (fun acc el -> (el,p_id)::acc) stop_times stopping_time)
      )
      (env, domain, 0, [],[]) res.perturbations
  in
  (*making sure that perturbations containing a stopping time precondition are tested first*)
  let lpert = List.rev lpert in
  let pred = (fun p -> match p.Primitives.stopping_time with
			 [] -> false | _ :: _ -> true) in
  let lpert_stopping_time = List.filter pred lpert in
  let lpert_ineq = List.filter (fun p -> not (pred p)) lpert in
  let lpert = lpert_stopping_time@lpert_ineq in
  (env, domain, lpert,stop_times)

let init_graph_of_result counter env domain res =
  let domain',init_state =
    List.fold_left
      (fun (domain,state) (opt_vol,init_t,_) -> (*TODO dealing with volumes*)
       match init_t with
       | INIT_MIX (alg, (ast,mix_pos)) ->
	  let (domain',alg') =
	    Expr.compile_alg env.Environment.algs.NamedDecls.finder
			     env.Environment.tokens.NamedDecls.finder
			     env.Environment.contact_map domain alg in
	  let value = initial_value_alg counter env alg' in
	  let fake_rule =
	    { lhs = []; rm_token = []; arrow = RAR; rhs = ast; add_token = [];
	      k_def = Term.with_dummy_pos (CONST Nbr.zero);
	      k_un = None; k_op = None; } in
	  let domain'',state' =
	    match
	      rules_of_ast env.Environment.algs.NamedDecls.finder
			      env.Environment.tokens.NamedDecls.finder
			      env.Environment.contact_map domain' None
			      (fake_rule,mix_pos)
	    with
	    | domain'',[ _, compiled_rule ] ->
	       domain'',
	       Nbr.iteri
		 (fun _ s ->
		  fst
		    (Rule_interpreter.force_rule
		       ~get_alg:(fun i ->
				 fst (snd env.Environment.algs.NamedDecls.decls.(i)))
		       domain'' counter s compiled_rule))
		 state value
	    | domain'',[] -> domain'',state
	    | _,_ ->
	       raise (ExceptionDefn.Malformed_Decl
			(Format.asprintf
			   "initial mixture %a is partially defined"
			   Expr.print_ast_mix ast,mix_pos)) in
	  domain'',state'
       | INIT_TOK (alg, (tk_nme,pos_tk)) ->
	  let fake_rule =
	    { lhs = []; rm_token = []; arrow = RAR; rhs = [];
	      add_token = [(alg, (tk_nme,pos_tk))];
	      k_def = Term.with_dummy_pos (CONST Nbr.zero);
	      k_un = None; k_op = None; } in
	  let domain',state' =
	    match
	      rules_of_ast env.Environment.algs.NamedDecls.finder
			      env.Environment.tokens.NamedDecls.finder
			      env.Environment.contact_map domain None
			      (Term.with_dummy_pos fake_rule)
	    with
	    | domain'',[ _, compiled_rule ] ->
	       domain'',
	       fst (Rule_interpreter.force_rule
		      ~get_alg:(fun i ->
				fst (snd env.Environment.algs.NamedDecls.decls.(i)))
		      domain'' counter state compiled_rule)
	    | _,_ -> assert false in
	  domain',state'
      )	(domain,Rule_interpreter.empty env)
      res.Ast.init
  in
  (domain',init_state)

let configurations_of_result result =
  let raw_set_value pos_p param value_list f =
    match value_list with
    | (v,_) :: _ -> f v pos_p
    | [] -> ExceptionDefn.warning
	      ~pos:pos_p
	      (fun f -> Format.fprintf f "Empty value for parameter %s" param)
  in
  let set_value pos_p param value_list f ass =
    raw_set_value pos_p param value_list (fun x p -> ass := f x p) in
  List.iter
    (fun ((param,pos_p),value_list) ->
     match param with
     | "displayCompression" ->
	begin
	  let rec parse l =
	    match l with
	    | ("strong",_)::tl ->
	       (Parameter.strongCompression := true ; parse tl)
	    | ("weak",_)::tl -> (Parameter.weakCompression := true ; parse tl)
	    | ("none",_)::tl -> (Parameter.mazCompression := true ; parse tl)
	    | [] -> ()
	    | (error,_)::_ ->
	       raise (ExceptionDefn.Malformed_Decl
			("Unkown value "^error^" for compression mode", pos_p))
	  in
	  parse value_list
	end
     | "cflowFileName"	->
	raw_set_value pos_p param value_list (fun x _ -> Kappa_files.set_cflow x)
     | "progressBarSize" ->
	set_value pos_p param value_list
		  (fun v p ->
		   try int_of_string v
		   with _ ->
		     raise (ExceptionDefn.Malformed_Decl
			      ("Value "^v^" should be an integer", p))
		  ) Parameter.progressBarSize

     | "progressBarSymbol" ->
	set_value pos_p param value_list
		  (fun v p ->
		   try
		     String.unsafe_get v 0
		   with _ ->
		     raise (ExceptionDefn.Malformed_Decl
			      ("Value "^v^" should be a character",p))
		  ) Parameter.progressBarSymbol

     | "dumpIfDeadlocked" ->
	set_value pos_p param value_list
		  (fun value pos_v ->
		   match value with
		   | "true" | "yes" -> true
		   | "false" | "no" -> false
		   | _ as error ->
		      raise (ExceptionDefn.Malformed_Decl
			       ("Value "^error^" should be either \"yes\" or \"no\"", pos_v))
		  ) Parameter.dumpIfDeadlocked
     | "plotSepChar" ->
	set_value pos_p param value_list
		  (fun v _ ->
		   fun f ->  Format.fprintf f "%s" v
		  ) Parameter.plotSepChar
     | "maxConsecutiveClash" ->
	set_value pos_p param value_list
		  (fun v p ->
		   try int_of_string v
		   with _ ->
		     raise (ExceptionDefn.Malformed_Decl
			      ("Value "^v^" should be an integer",p))
		  ) Parameter.maxConsecutiveClash

     | "dotSnapshots" ->
	set_value pos_p param value_list
		  (fun value pos_v ->
		   match value with
		   | "true" | "yes" -> true
		   | "false" | "no" -> false
		   | _ as error ->
		      raise (ExceptionDefn.Malformed_Decl
			       ("Value "^error^" should be either \"yes\" or \"no\"", pos_v))
		  ) Parameter.dotOutput
     | "colorDot" ->
	set_value pos_p param value_list
		  (fun value pos_v ->
		   match value with
		   | "true" | "yes" -> true
		   | "false" | "no" -> false
		   | _ as error ->
		      raise (ExceptionDefn.Malformed_Decl
			       ("Value "^error^" should be either \"yes\" or \"no\"", pos_v))
		  ) Parameter.useColor
     | "dumpInfluenceMap" ->
	raw_set_value
	  pos_p param value_list
	  (fun v p ->
	   match v with
	   | "true" | "yes" -> Kappa_files.set_up_influence ()
	   | "false" | "no" -> Kappa_files.set_influence ""
	   | _ as error ->
	      raise (ExceptionDefn.Malformed_Decl
		       ("Value "^error^" should be either \"yes\" or \"no\"",p))
	     )
     | "influenceMapFileName" ->
	raw_set_value pos_p param value_list
		      (fun x _ -> Kappa_files.set_influence x)
     | "showIntroEvents" ->
	set_value pos_p param value_list
		  (fun v p -> match v with
				| "true" | "yes" -> true
				| "false" | "no" -> false
				| _ as error ->
				   raise (ExceptionDefn.Malformed_Decl
					    ("Value "^error^" should be either \"yes\" or \"no\"",p))
		  )
		  Parameter.showIntroEvents
     | _ as error ->
	raise (ExceptionDefn.Malformed_Decl ("Unkown parameter "^error, pos_p))
    ) result.configurations

let compile_alg_vars tokens contact_map domain overwrite vars =
  let alg_vars_over =
    Tools.list_rev_map_append
      (fun (x,v) -> (Term.with_dummy_pos x,
		     Term.with_dummy_pos (Ast.CONST v))) overwrite
      (List.filter
	 (fun ((x,_),_) ->
	  List.for_all (fun (x',_) -> x <> x') overwrite) vars) in
  let vars_nd = NamedDecls.create (Array.of_list alg_vars_over) in
  array_fold_left_mapi (fun i domain ((label,_ as lbl_pos),ast) ->
			let (domain',alg) =
			  Expr.compile_alg ~label vars_nd.NamedDecls.finder
					   tokens ~max_allowed_var:(pred i)
					   contact_map domain ast
			in (domain',(lbl_pos,alg))) domain
		       vars_nd.NamedDecls.decls

let compile_rules algs tokens contact_map domain rules =
  List.fold_left
    (fun (domain,acc) (rule_label,rule) ->
     let (domain',cr) =
       rules_of_ast algs tokens contact_map domain rule_label rule in
    domain',List.append cr acc)
    (domain,[]) rules

let initialize logger overwrite result =
  Debug.tag logger "+ Building initial simulation conditions...";
  let counter =
    Counter.create !Parameter.pointNumberValue
		   0.0 0 !Parameter.maxTimeValue !Parameter.maxEventValue in
  Debug.tag logger "+ Compiling..." ;
  Debug.tag logger "\t -simulation parameters" ;
  let _ = configurations_of_result result in

  Debug.tag logger "\t -agent signatures" ;
  let sigs_nd = Signature.create result.Ast.signatures in
  let () = Debug.global_sigs := sigs_nd in
  let tk_nd =
    NamedDecls.create (array_map_of_list (fun x -> (x,())) result.Ast.tokens) in

  let pre_kasa_state = Export_to_KaSim.Export_to_KaSim.init result in
  let _kasa_state,contact_map =
    Export_to_KaSim.Export_to_KaSim.get_contact_map pre_kasa_state in

  let domain = Connected_component.Env.empty sigs_nd in
  Debug.tag logger "\t -variable declarations";
  let domain',alg_a =
    compile_alg_vars tk_nd.NamedDecls.finder contact_map domain
		     overwrite result.Ast.variables in
  let alg_nd = NamedDecls.create alg_a in

  Debug.tag logger "\t -rules";
  let (domain',compiled_rules) =
    compile_rules alg_nd.NamedDecls.finder tk_nd.NamedDecls.finder contact_map
		  domain' result.Ast.rules in
  let rule_nd = NamedDecls.create (Array.of_list compiled_rules) in

  let env =
    Environment.init sigs_nd contact_map tk_nd alg_nd rule_nd in
  let () =
    if !Parameter.compileModeOn then
      Format.eprintf
	"@[<v>%a@]@."
	(Pp.list
	   Pp.space
	   (fun f (_,r) ->
	    Format.fprintf f "@[%a@]" (Kappa_printer.elementary_rule env) r))
	compiled_rules in

  Debug.tag logger "\t -observables";
  let env,domain,observables =
    obs_of_result env domain' result in
  Debug.tag logger "\t -perturbations" ;
  let (env, domain,pert,stops) =
    pert_of_result env domain result in

  let env = { env with
	      Environment.observables = Array.of_list (List.rev observables);
	      Environment.perturbations = Array.of_list pert;} in
  Debug.tag logger "\t -initial conditions";
  let domain,graph =
    init_graph_of_result counter env domain result in
  let () =
    if !Parameter.compileModeOn then
      Format.eprintf "@[<v>Domain:@,@[%a@]@,Intial graph;@,@]%a@."
		     Connected_component.Env.print domain
		     (Rule_interpreter.print env) graph in
  let state = State_interpreter.initial env counter graph stops in
  (Debug.tag logger "\t Done"; (env, domain, counter, graph, state))
