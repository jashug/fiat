Require Import AutoDB BagADT.
Require Import Coq.Vectors.Vector Ascii Bool Bvector List.

Section packet.
  (* TODO: Move this section into a seperate file for basic
     packet and DNS Record definitions. *)

  Definition name := list string.

  Definition beq_name (a b : name) : bool :=
    if (list_eq_dec string_dec a b) then true else false.

  Lemma beq_name_dec
  : forall (a b : name), beq_name a b = true <-> a = b.
  Proof.
    unfold beq_name; intros; find_if_inside; intuition; intros; congruence.
  Qed.

  Inductive RRecordType := A | CNAME | NS | MX.

  Definition beq_RRecordType (a b : RRecordType) :=
    match a, b with
      | A, A => true
      | CNAME, CNAME => true
      | NS, NS => true
      | MX, MX => true
      | _, _ => false
    end.

  Lemma RRecordType_dec
  : forall (a b : RRecordType), {a = b} + {a <> b}.
  Proof.
    destruct a; destruct b; simpl; intuition; intros;
    try first [right; discriminate | left; reflexivity].
  Qed.

  Lemma beq_RRecordType_sym :
    forall rrT rrT', beq_RRecordType rrT rrT' = beq_RRecordType rrT' rrT.
  Proof.
    destruct rrT; destruct rrT'; simpl; congruence.
  Qed.

  Lemma beq_RRecordType_dec :
    forall a b, ?[RRecordType_dec a b] = beq_RRecordType a b.
  Proof.
    intros; find_if_inside; subst.
    destruct b; simpl; reflexivity.
    destruct a; destruct b; simpl; congruence.
  Qed.

    (* Instances used in DecideableEnsemble. *)
  Global Instance Query_eq_RRecordType :
    Query_eq RRecordType := {| A_eq_dec := RRecordType_dec |}.

  Inductive RRecordClass := IN | CH | HS.

  Definition beq_RRecordClass (a b : RRecordClass) :=
    match a, b with
      | IN, IN => true
      | CH, CH => true
      | HS, HS => true
      | _, _ => false
    end.
  Lemma RRecordClass_dec
  : forall (a b : RRecordClass), {a = b} + {a <> b}.
  Proof.
    destruct a; destruct b; simpl; intuition; intros;
    try first [right; discriminate | left; reflexivity ].
  Qed.

  (* Instances used in DecideableEnsemble. *)
  Global Instance Query_eq_RRecordClass :
    Query_eq RRecordClass := {| A_eq_dec := RRecordClass_dec |}.

  Record question :=
    { qname : name;
      qtype : RRecordType;
      qclass : RRecordClass }.

  Record answer :=
    { aname : name;
      atype : RRecordType;
      aclass : RRecordClass;
      ttl : nat;
      rdata : string }.

  Record packet :=
    { id : Bvector 16;
      flags : Bvector 16;
      questions : question; (* `list question` in case we can have multiple questions? *)
      answers : list answer;
      authority : list answer;
      additional : list answer }.

  Lemma zero_lt_sixteen : lt 0 16. omega. Qed.
  Definition buildempty (p : packet) :=
    {| id := id p;
       flags := replace_order (flags p) zero_lt_sixteen true; (* set QR bit *)
       questions := questions p;
       answers := [ ];
       authority := [ ];
       additional := [ ] |}.

  Definition sCOLLECTIONS := "Collections".
  Definition sNAME := "Name".
  Definition sTTL := "TTL".
  Definition sCLASS := "Class".
  Definition sTYPE := "Type".
  Definition sDATA := "Data".

  (* DNS Resource Records. *)
  Definition DNSRRecord :=
    @Tuple <sNAME :: name,
            sTYPE :: RRecordType,
            sCLASS :: RRecordClass,
            sTTL :: nat,
            sDATA :: string>%Heading.

  Definition toAnswer (t: DNSRRecord) :=
    {| aname := t!sNAME;
       atype := t!sTYPE;
       aclass := t!sCLASS;
       ttl := t!sTTL;
       rdata := t!sDATA |}.

  Definition addan (p : packet) (t : DNSRRecord) :=
    {| id := id p;
       flags := flags p;
       questions := questions p;
       answers := (toAnswer t) :: answers p;
       authority := authority p;
       additional := additional p |}.

  Definition addns (p : packet) (t : DNSRRecord) :=
    {| id := id p;
       flags := flags p;
       questions := questions p;
       answers := answers p;
       authority := (toAnswer t) :: (authority p);
       additional := additional p |}.

End packet.

Definition DnsSchema :=
  Query Structure Schema
        [ relation sCOLLECTIONS has
                   schema <sNAME :: name,
                      sTYPE :: RRecordType,
                      sCLASS :: RRecordClass,
                      sTTL :: nat,
                      sDATA :: string>
            where (fun t t' => t!sNAME = t'!sNAME -> t!sTYPE <> CNAME)]
          enforcing [ ].

  Definition DnsSig : ADTSig :=
    ADTsignature {
        Constructor "Init" : unit -> rep,
        Method "AddData" : rep x DNSRRecord -> rep x bool,
        Method "Process" : rep x packet -> rep x packet
  }.

Definition prefixProp (p s : name) := exists ps, p ++ ps = s.
Fixpoint prefixBool (p s : name) :=
  match p, s with
    | [ ], _ => true
    | p' :: ps', s' :: ss' => if string_dec p' s' then prefixBool ps' ss' else false
    | _, _ => false
  end.

Lemma prefixBool_eq :
  forall (p s : name),
    prefixBool p s = true <-> prefixProp p s.
Proof.
  unfold prefixProp; split; revert s; induction p; intros s H.
  - eexists s; reflexivity.
  - destruct s; simpl in H.
    + discriminate.
    + find_if_inside; [subst | discriminate].
      apply_in_hyp IHp; destruct_ex; eexists; subst; reflexivity.
  - simpl; reflexivity.
  - destruct s; simpl in *; destruct H.
    + discriminate.
    + injections; find_if_inside; intuition eauto.
Qed.

Global Instance DecideablePrefix {n}
: DecideableEnsemble (fun tup => prefixProp tup n) :=
  {| dec n' :=  prefixBool n' n;
     dec_decides_P n' := prefixBool_eq n' n|}.

Definition upperbound (r : DNSRRecord) (rs : list DNSRRecord) :=
  forall r', List.In r' rs -> List.length r!sNAME >= List.length r'!sNAME.

Section FueledFix.
  (* TODO: Find a home for these more definitions in the Common folder. *)

  Variable A : Type. (* Argument Type *)
  Variable R : Type. (* Return Type *)

  Fixpoint FueledFix (fuel : nat) (base : R) (body : (A -> R) -> A -> R) (arg : A)
  : R :=
    match fuel with
      | O => base
      | S fuel' => body (FueledFix fuel' base body) arg
    end.
End FueledFix.

(* Can rewrite under Fueled Fix at the moment,
as the condition on the body is not a proper relation. :p *)
(* TODO: figure out a definition for pointwise_refine that is a
   proper (i.e. reflexive and transitive) relation.
 *)

(* Definition pointwise_refine {A R}
 (f g : (A -> Comp R) -> A -> Comp R) :=
  forall (rec rec' : A -> Comp R) (a : A),
    pointwise_relation A (@refine R) rec rec'
    -> refine (f rec a) (g rec' a).

Lemma reflexive_pR {A R : Type} :
  forall A R, Reflexive (@pointwise_refine A R).
Proof.
  unfold Reflexive, pointwise_refine, pointwise_relation.
  intros.
  (* Doesn't work if x is (fun rec a => {r | ~ rec ~> r} :p *)
Admitted.

Lemma transitive_pR {A R : Type} :
  forall A R, Transitive (@pointwise_refine A R).
Proof.
  unfold Transitive, pointwise_refine, pointwise_relation; intros.
  etransitivity.
  apply H; eauto.
  apply H0. reflexivity.
Qed. *)

(* Add Parametric Morphism A R i
: (@FueledFix A (Comp R) i)
    with signature
    ((@refine R)
       ==> (@pointwise_refine A R)
      ==> (@eq A)
      ==> (@refine R))
      as refineFix.
Proof.
  simpl; induction i; intros; simpl.
  - assumption.
  - unfold pointwise_refine, pointwise_relation, Proper, respectful in *.
    eapply H0.
    intros.
    generalize (IHi _ _ H _ _ H0 y1); clear.
    apply H; apply IHi; [ apply H | apply H0 ].
Qed. *)


(* TODO: Agree on a notation for our fueled fix function. *)
Notation "'Repeat' fuel 'initializing' a 'with' arg 'defaulting' rec 'with' base {{ bod }} " :=
  (FueledFix fuel base (fun rec a => bod) arg)
    (no associativity, at level 50,
     format "'Repeat' '[hv'  fuel  '/' 'initializing'  a  'with'  arg '/'  'defaulting'  rec  'with'  base  '/' {{ bod  }} ']' ").

Section FueledFixRefinements.
  (* TODO: Find a home for these refinements in the Computation folder. *)

  Variable A : Type. (* Argument Type *)
  Variable R : Type. (* Return Type *)

  (* TODO Lemmas for refining FueledFix. *)

  Lemma refine_FueledFix_Bind (B : Type) :
    forall fuel body (base : Comp R) (arg : A) (k k' : R -> Comp B),
      refine (r <- base; k r) (r <- base; k' r)
      -> (forall fuel',
            refine (a <- FueledFix fuel' base body arg; k a)
                   (a <- FueledFix fuel' base body arg; k' a)
            -> refine
                 (a <- FueledFix (S fuel') base body arg; k a)
                 (a <- FueledFix (S fuel') base body arg; k' a))
      ->  refine (a <- FueledFix fuel base body arg; k a)
                 (a <- FueledFix fuel base body arg; k' a).
  Proof.
    induction fuel; eauto.
  Qed.

End FueledFixRefinements.

Section FilteredList.
  (* TODO: Move FlattenComp to the Computation directory and find a
     home for this definition. *)
  Definition filtered_list {A}
             (xs : list A)
             (P : Ensemble A)
    := FlattenCompList.flatten_CompList (map (fun x => Where (P x) (Return x)) xs).

End FilteredList.

Notation "[ x 'in' xs | P ]" := (filtered_list xs (fun x => P)) (at level 70) : comp_scope.

(* Agree on this notation. *)
Notation "'unique' b , P ->> s 'otherwise' ->> s'" :=
  (b' <- {b' | forall b, b' = Some b <-> P};
   (match b' with
      | Some b => s
      | None => s'
    end)) (at level 70).

Definition DnsSpec : ADT DnsSig :=
  QueryADTRep DnsSchema {
    Def Constructor "Init" (_ : unit) : rep := empty,
    update "AddData" (t : DNSRRecord) : bool :=
      Insert t into sCOLLECTIONS,
    query "Process" (p : packet) : packet :=
      let t := qtype (questions p) in
      Repeat (*7 *) 1 initializing n with qname (questions p)
                                                (* setting this to 1 until we work out the setoid *)
                                                (* rewriting machinery *)
               defaulting rec with (ret (buildempty p))
         {{ rs <- For (r in sCOLLECTIONS)      (* Bind a list of all the DNS entries *)
                  Where (prefixProp n r!sNAME) (* prefixed with [n] to [rs] *)
                  Return r;
           bfrs <- [r in rs | upperbound r rs]; (* Find the best match (largest prefix) in [rs] *)
           b <- { b | decides b (forall r, List.In r bfrs -> n = r!sNAME) };
                            (* If there is an exact match *)
           if b
           then
             unique b, List.In b bfrs /\ b!sTYPE = CNAME /\ t <> CNAME ->> (* *)
             bfrs' <- [x in bfrs | x!sTYPE = t];
             p' <- rec b!sNAME;
             ret (List.fold_left addan bfrs' p')
           otherwise ->>
             ret (List.fold_left addan bfrs (buildempty p))
         else
           bfrs' <- [x in bfrs | x!sTYPE = NS];
           ret (List.fold_left addns bfrs' (buildempty p))
      }} }.

(* Search Terms are pairs of prefixes and filter functions. *)
Record PrefixSearchTerm := { pst_name : name;
                             pst_filter : DNSRRecord -> bool }.
Definition PrefixSearchTermMatcher (search_term : PrefixSearchTerm)
           (t : DnsSchema # sCOLLECTIONS) :=
  prefixBool (pst_name search_term) (t!sNAME) && pst_filter search_term t.

Definition DnsSearchUpdateTerm :=
  {| BagSearchTermType := PrefixSearchTerm;
     BagMatchSearchTerm := PrefixSearchTermMatcher;
     BagUpdateTermType := name;
     BagApplyUpdateTerm := fun _ x => x |}.

(* Parade of admitted refinement lemmas. Should go in a DNS Refinements file. *)

    Lemma foo1 :
      forall (n : DNSRRecord) (R : @IndexedEnsemble DNSRRecord),
        n!sTYPE <> CNAME
        -> refine {b |
                   decides b
                           (forall tup' : IndexedTuple,
                              R tup' ->
                              n!sNAME = (indexedElement tup')!sNAME -> n!sTYPE <> CNAME)}
                  (ret true).
    Proof.
    Admitted.

    Lemma foo2 :
      forall (n : DNSRRecord) (R : @IndexedEnsemble DNSRRecord),
        n!sTYPE = CNAME
        -> refine {b |
                   decides b
                           (forall tup' : IndexedTuple,
                              R tup' ->
                              n!sNAME = (indexedElement tup')!sNAME -> n!sTYPE <> CNAME)}
                  (b <- {b |
                   decides b
                           (exists tup' : IndexedTuple,
                              R tup' /\
                              n!sNAME = (indexedElement tup')!sNAME)};
                   ret (negb b)).
    Proof.
      intros; subst.
      intros v Comp_v; inversion_by computes_to_inv; subst.
      destruct x; simpl in *; econstructor; simpl.
      unfold not; intros.
      destruct_ex; intuition.
      eapply H0; eauto.
      unfold not; intros; apply H1.
      eexists; eauto.
    Qed.

    Lemma foo4 :
      forall (n : DNSRRecord) (R : @IndexedEnsemble DNSRRecord),
        refine {b |
                   decides b
                           (forall tup' : IndexedTuple,
                              R tup' ->
                              (indexedElement tup')!sNAME = n!sNAME
                              -> (indexedElement tup')!sTYPE <> CNAME)}
               (b <- {b |
                   decides b
                           (exists tup' : IndexedTuple,
                              R tup' /\
                              n!sNAME = (indexedElement tup')!sNAME
                              /\ (indexedElement tup')!sTYPE = CNAME)};
                ret (negb b)).
    Proof.
      intros; subst.
      intros v Comp_v; inversion_by computes_to_inv; subst.
      destruct x; simpl in *; econstructor; simpl.
      unfold not; intros.
      destruct_ex; intuition eauto.
      unfold not; intros; apply H0.
      eexists; eauto.
    Qed.

    Lemma foo3 :
      forall (n : DNSRRecord) (r : UnConstrQueryStructure DnsSchema),
        refine {b |
                decides b
                        (forall tup' : @IndexedTuple (GetHeading DnsSchema sCOLLECTIONS),
                           (r!sCOLLECTIONS)%QueryImpl tup' ->
                           n!sNAME = (indexedElement tup')!sNAME -> n!sTYPE <> CNAME)}
               (If (beq_RRecordType n!sTYPE CNAME)
                   Then count <- Count
                   For (UnConstrQuery_In r ``(sCOLLECTIONS)
                                         (fun tup : Tuple =>
                                            Where (n!sNAME = tup!sNAME)
                                                  Return tup ));
                ret (beq_nat count 0) Else ret true).
    Proof.
      intros; setoid_rewrite refine_pick_decides at 1;
      [ | apply foo2 | apply foo1 ].
      refine existence check into query.
      remember n!sTYPE; refine pick val (beq_RRecordType d CNAME); subst;
      [ | case_eq (beq_RRecordType n!sTYPE CNAME); intros;
          rewrite <- beq_RRecordType_dec in H; find_if_inside;
          unfold not; simpl in *; try congruence ].
      simplify with monad laws.
      f_equiv; simplify with monad laws.
      setoid_rewrite negb_involutive.
      f_equiv.
    Qed.

    Lemma foo5 :
      forall (n : DNSRRecord) (r : UnConstrQueryStructure DnsSchema),
        refine {b |
                decides b
                        (forall tup' : @IndexedTuple (GetHeading DnsSchema sCOLLECTIONS),
                           (r!sCOLLECTIONS)%QueryImpl tup' ->
                           (indexedElement tup')!sNAME = n!sNAME
                           -> (indexedElement tup')!sTYPE <> CNAME)}
               (count <- Count
                   For (UnConstrQuery_In r ``(sCOLLECTIONS)
                                         (fun tup : Tuple =>
                                            Where (n!sNAME = tup!sNAME
                                                   /\ tup!sTYPE = CNAME )
                                                  Return tup ));
                ret (beq_nat count 0)).
    Proof.
      intros; setoid_rewrite foo4.
      refine existence check into query.
      simplify with monad laws.
      setoid_rewrite negb_involutive; f_equiv.
    Qed.

    Lemma foo7 {heading}
    : forall (R : Ensemble (@IndexedTuple heading))
             (P : Ensemble Tuple)
             (l : list Tuple),
        For (QueryResultComp
               R
               (fun tup => Where (P tup)
                                 (Return tup))) ↝ l  ->
        forall (P' : Ensemble Tuple) (P'_dec : DecideableEnsemble P'),
        refine (For (QueryResultComp
                  R
                  (fun tup => Where (P tup /\ P' tup)
                                    (Return tup))))
               (ret (filter DecideableEnsembles.dec l)).
    Proof.
      admit.
    Qed.

    Lemma foo8 {A}
    : forall (c c' : bool) (t e e' : A),
        (c = true -> c' = true)
        -> (if c then (if c' then t else e) else e') = if c then t else e'.
    Proof.
      admit.
    Qed.

    Lemma foo9 {A}
    : forall (l : list A) (pred : A -> bool),
        beq_nat (Datatypes.length l) 0 = true
        ->  beq_nat (Datatypes.length (filter pred l)) 0 = true.
    Proof.
      induction l; simpl; intros.
      reflexivity.
      discriminate.
    Qed.

        Lemma foo10
        :
          forall (a n : DNSRRecord),
            ?[list_eq_dec string_dec n!sNAME a!sNAME] =
            PrefixSearchTermMatcher
              {|
                pst_name := n!sNAME;
                pst_filter := fun tup : DNSRRecord =>
                                ?[list_eq_dec string_dec n!sNAME tup!sNAME] |} a.
        Admitted.

        Lemma foo11 {heading}
        : forall l,
            map (ilist_hd (As:=cons heading nil ))
                (Build_single_Tuple_list l) = l.
        Proof.
          induction l; simpl; congruence.
        Qed.

          Lemma foo12 :
            forall l l' : name,
              prefixBool l l' = false ->
              ?[list_eq_dec string_dec l l'] = false.
          Proof.
            induction l; simpl; destruct l'; intros; eauto.
            repeat find_if_inside; eauto; injections.
            rewrite <- (IHl _ H).
            clear; induction l'; simpl; eauto.
            find_if_inside; congruence.
            congruence.
          Qed.



    Transparent FueledFix.

Theorem DnsManual :
  Sharpened DnsSpec.
Proof.
  unfold DnsSpec.
  start honing QueryStructure.

  (* Implement the constraint checks as queries. *)
  hone method "AddData".
  {
    setoid_rewrite foo3.
    setoid_rewrite foo5.
    simplify with monad laws.
    setoid_rewrite refine_If_Then_Else_Bind.
    setoid_rewrite Bind_refine_If_Then_Else.
    etransitivity.
    apply refine_If_Then_Else_if.
    - reflexivity.
    - simplify with monad laws.
      apply refine_under_bind; intros.
      setoid_rewrite refine_Count; simplify with monad laws.
      apply refine_under_bind; intros.
      (* remove duplicate check *)
      setoid_rewrite foo7; eauto.
      simplify with monad laws.
      rewrite foo8 by apply foo9.
      higher_order_1_reflexivity.
    - simplify with monad laws.
      reflexivity.
    - finish honing.
  }

  hone representation using (@DelegateToBag_AbsR DnsSchema (icons DnsSearchUpdateTerm (inil _))).
  (* TODO: We should define a 'make simple indexes' tactic notation variant for
     lists of SearchUpdateTerms. *)

  hone constructor "Init".
  {
    simplify with monad laws.
    rewrite refine_QSEmptySpec_Initialize_IndexedQueryStructure.
    finish honing.
  }

  hone method "AddData".
  {
    etransitivity.
    setoid_rewrite refine_If_Then_Else_Bind.
    etransitivity.
    - apply refine_If_Then_Else_if.
      + reflexivity.
      + simplify with monad laws.
        Focused_refine_Query'.
        implement_In.
        convert_Where_to_search_term.
        (* TODO: Create a tactic that builds the search term to use
           in lieu of this idtac. *)
        find_equivalent_search_term 0 ltac:(fun _ _ _ _ => idtac).
        { instantiate (1 := {| pst_name := n!sNAME;
                             pst_filter := fun tup => ?[list_eq_dec string_dec n!sNAME tup!sNAME] |}).
          intros; apply foo10.
        }

        convert_filter_to_find.
        Implement_Aggregates.

        setoid_rewrite foo11.
        reflexivity.

        simplify with monad laws.
        setoid_rewrite refineEquiv_swap_bind.

        setoid_rewrite refine_if_If.
        implement_Insert_branches.
        reflexivity.
      + simplify with monad laws.

        Focused_refine_Query'.
        implement_In.

        convert_Where_to_search_term.
        (* TODO: Reuse tactic from above to build this search term. *)
        instantiate (1 := fun a => PrefixSearchTermMatcher {| pst_name := n!sNAME;
                           pst_filter := fun tup => ?[list_eq_dec string_dec n!sNAME tup!sNAME]
                                                     && (?[CNAME == (tup!sTYPE)]) |} (ilist_hd a)).
        { intro; unfold PrefixSearchTermMatcher; simpl.
          match goal
          with |- context [ prefixBool ?l ?l' ] => case_eq (prefixBool l l');
                 simpl end.
          intros; f_equal.
          repeat find_if_inside; simpl; try congruence.

          intros; rewrite foo12; simpl; eauto.
        }

        convert_filter_to_find.
        Implement_Aggregates.
        setoid_rewrite foo11.
        reflexivity.

        simplify with monad laws.
        setoid_rewrite refineEquiv_swap_bind.

        setoid_rewrite refine_if_If.
        implement_Insert_branches.
        reflexivity.
      - reflexivity.
      - finish honing.
  }

  hone method "Process".
  {
    simplify with monad laws.
    Focused_refine_Query'.

    implement_In.
    idtac.

    Global Instance DecideablePrefix_sym {A} (f : A -> name) {n}
    : DecideableEnsemble (fun tup => prefixProp n (f tup)) :=
      {| dec n' :=  prefixBool n (f n');
         dec_decides_P n' := prefixBool_eq n (f n')|}.


    convert_Where_to_search_term.
        find_equivalent_search_term 0 ltac:(fun _ _ _ _ => idtac).
        { instantiate (1 := {| pst_name := qname (questions n);
                             pst_filter := fun tup => true |}).

          Lemma foo13 : forall l (a : DNSRRecord),
                          prefixBool l (a!sNAME) =
                          PrefixSearchTermMatcher
                            {|
                              pst_name := l;
                              pst_filter := fun _ : DNSRRecord => true |} a.
          Proof.
            admit.
          Qed.
          simpl.
          intros; apply foo13.
        }

        convert_filter_to_find.
        Implement_Aggregates.

        setoid_rewrite foo11.
        reflexivity.

        simplify with monad laws.

        setoid_rewrite refine_if_If.


        implement_Insert_branches.
        reflexivity.

    convert_Where_to_search_term.

    prefixProp


  }


      apply refine_bind; [ reflexivity
                         | unfold pointwise_relation; intros].


    setoid_rewrite refineEquiv_swap_bind.


    Ltac Implement_If_Then_Else :=
    match goal with
      | |- refine (Bind (If ?i Then ?t Else ?e) ?k) _ =>
        etransitivity;
          [ apply (refine_If_Then_Else_Bind i t e k)
          | etransitivity;
            [ apply refine_If_Then_Else_if;
              [ reflexivity | | ]
            | ]
          ]
      | |- refine (If_Then_Else ?i (ret ?t) (ret ?e)) _ =>
        etransitivity;
          [ apply (refine_If_Then_Else_ret i t e)
          | ]
    end.

    Implement_If_Then_Else.
    simplify with monad laws.


    idtac.

      Focus 2.
      setoid_rewrite r0.
      simpl in *.


      intuition eauto.
      pattern (indexedElement x).
      setoid_rewrite (r0 _ _ _).

      pose (refine_constraint_check_into_query' (c:=r)
                                                          (P':=fun tup' : @IndexedElement DNSRRecord =>
                                                                 n!sNAME = (indexedElement tup')!sNAME)).

      intros; apply foo1.
      apply foo2.
      eauto using foo1, foo2.
      cut (sigT (refine {b0 : bool |
                            decides b0
                                    (exists tup' : IndexedTuple,
                                       (r!sCOLLECTIONS)%QueryImpl tup' /\
                                       n!sNAME = (indexedElement tup')!sNAME)})).
      intros.
      destruct X.
      simpl in *.
      etransitivity.
      setoid_rewrite r0 at .
      eapply refine_bind.

      reflexivity.
      setoid_rewrite r0.
      simpl in *; unfold pointwise_relation; intros.
      rewrite r0.
      apply refine_If_Then_Else.
      apply r0.

      Add Parametric Morphism A (c : bool)
      : (If_Then_Else c)
          with signature
          (@refine A ==> @refine A ==> @refine A )
            as refine_If_Then_Else.
      Proof.
        unfold If_Then_Else; intros.
        destruct c; eassumption.
      Qed.

      cut (refine (ret true) (ret false)).
      intros.
      cut (refine {b : bool |
           decides b
             (exists tup' : IndexedTuple,
                (r!sCOLLECTIONS)%QueryImpl tup' /\
                n!sNAME = (indexedElement tup')!sNAME)}
          (ret true)); intros.
      rewrite H0.
      setoid_rewrite (refine_constraint_check_into_query' (c:=r)
                                                          (P':=fun tup' : @IndexedElement DNSRRecord =>
                                                                 n!sNAME = (indexedElement tup')!sNAME) _) at 1.

      cut (Proper (refine ==> flip impl)
                   (refine
                      (If a
                          Then {b : bool |
                                decides b
                                        (exists
                                            tup' : IndexedTuple,
                                                (r!sCOLLECTIONS)%QueryImpl
                                                  tup' /\
                                                n!sNAME =
                                                (indexedElement tup')!sNAME)}
                                      Else ret true))).
      intros.
      setoid_rewrite (refine_constraint_check_into_query' (c:=r)
                                                          (P':=fun tup' : @IndexedElement DNSRRecord =>
                                                                 n!sNAME = (indexedElement tup')!sNAME) _) at 1.

      unfold Proper; simpl.
      unfold respectful, flip, impl.
      econstructor.
      intros.


      setoid_rewrite (refine_constraint_check_into_query' (c:=r)
                                                          (P':=fun tup' : @IndexedElement DNSRRecord =>
                                                                 n!sNAME = (indexedElement tup')!sNAME) _) at 1.

      match goal with
          |- context[{b | decides b
                                  (exists tup : @IndexedTuple ?heading,
                                     (GetUnConstrRelation ?qs ?tbl tup /\ @?P tup))}]
          =>
          pose (@refine_constraint_check_into_query' _ tbl qs P)
      end.

      setoid_rewrite (H _ _ _).
      cut (DecideableEnsemble (fun tup' => n!sNAME = tup'!sNAME)).
      cut (Same_set IndexedElement
         (fun tup : IndexedElement =>
          (fun tup' : Tuple => n!sNAME = tup'!sNAME) (indexedElement tup))
         (fun tup' : IndexedTuple => n!sNAME = (indexedElement tup')!sNAME)).
      intros.
      pose (H _ X H0).
      setoid_rewrite r0.
      Check string_dec_bool_true_iff.
        simpl; econstructor; intros;
        try setoid_rewrite <- eq_nat_dec_bool_true_iff;
        try setoid_rewrite <- eq_N_dec_bool_true_iff;
        try setoid_rewrite <- eq_Z_dec_bool_true_iff;
        try setoid_rewrite <- string_dec_bool_true_iff;
        try setoid_rewrite and_True;
        repeat progress (
                 try setoid_rewrite <- andb_true_iff;
                 try setoid_rewrite not_true_iff_false;
                 try setoid_rewrite <- negb_true_iff).
        rewrite bool_equiv_true;
        reflexivity.
      prove_decidability_for_functional_dependencies.
      tauto_dec.
      econstructor 1 with (fun b => if string_dec a b then true else false).
      eauto with typeclass_instances.
      setoid_rewrite (H (fun tup' => n!sNAME = tup'!sNAME)).
      Focus 3.
      reflexivity.

    (Pick (fun (b : bool) =>
                   decides b
                           (exists tup2: @IndexedTuple _,
                              (GetUnConstrRelation c tbl tup2 /\ P (indexedTuple tup2)))))

        <-> ((n!sType = CNAME ->
             exists (tup' : IndexedTuple),
               (or!sCOLLECTIONS)%QueryImpl tup' /\
               n!sNAME = (indexedElement tup')!sNAME)
               /\ (n!sType <> CNAME -> True))

    Implement_Insert_Checks.
  }

  hone method "Process".
  {
    simplify with monad laws.
    implement_In.
  }

Defined.
  FullySharpenQueryStructure DnsSchema Index.
