Require Import ADTSynthesis.Common Coq.Arith.Arith Coq.Bool.Bool Coq.Sets.Ensembles.

Class DecideableEnsemble {A} (P : Ensemble A) :=
  { dec : A -> bool;
    dec_decides_P : forall a, dec a = true <-> P a}.

Lemma Decides_false {A} :
  forall (P : Ensemble A)
         (P_dec : DecideableEnsemble P) a,
    dec a = false <-> ~ (P a).
Proof.
  split; unfold not; intros.
  + apply dec_decides_P in H0; congruence.
  + case_eq (dec a); intros; eauto.
    apply dec_decides_P in H0; intuition.
Qed.

Instance DecideableEnsemble_gt {A} (f f' : A -> nat)
  : DecideableEnsemble (fun a => f a > f' a) :=
  {| dec a := if le_lt_dec (f a) (f' a) then false else true |}.
Proof.
  intros; find_if_inside; intuition.
  exfalso; eapply gt_not_le; eassumption.
Defined.

Instance DecideableEnsemble_And
         {A : Type}
         {P P' : Ensemble A}
         {P_dec : DecideableEnsemble P}
         {P'_dec : DecideableEnsemble P'}
: DecideableEnsemble (fun a => P a /\ P' a) :=
  {| dec a := (@dec _ _ P_dec a) && (@dec _ _  P'_dec a) |}.
Proof.
  intros; rewrite <- (@dec_decides_P _ P),
          <- (@dec_decides_P _ P').
  setoid_rewrite andb_true_iff; reflexivity.
Defined.

(* Class used to overload equality test notation (==) in queries. *)
Class Query_eq (A : Type) :=
      {A_eq_dec : forall a a' : A, {a = a'} + {a <> a'}}.

Infix "==" := (A_eq_dec) (at level 1).

Instance DecideableEnsemble_NEqDec
         {A B : Type}
         {b_eq_dec : Query_eq B}
         (f f' : A -> B)
: DecideableEnsemble (fun a : A => f a <> f' a) :=
  {| dec a := if A_eq_dec (f a) (f' a) then false else true |}.
Proof.
  intros; find_if_inside; intuition.
Defined.
