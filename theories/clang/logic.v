(* Program Logic *)

From iris.algebra Require Export gmap agree auth frac excl.
From iris.base_logic.lib Require Export wsat fancy_updates namespaces.
From iris.program_logic Require Export weakestpre.
From iris_os.clang Require Export lang.
From iris.proofmode Require Export tactics.
Set Default Proof Using "Type".
Import uPred.

Instance equiv_type_function: Equiv function := (=).
Instance equiv_type_stack: Equiv stack := (=).

Definition textG := authR (gmapUR ident (agreeR (discreteC function))).
Definition stackG := prodR fracR (agreeR (discreteC stack)).

Class clangG Σ := ClangG {
  clangG_invG :> invG Σ;
  clangG_heapG :> gen_heapG addr byteval Σ;
  clangG_textG :> inG Σ textG;
  clangG_textG_name : gname;
  clangG_stackG :> inG Σ stackG;
  clangG_stackG_name : gname
}.

Section wp.
  Context `{clangG Σ}.

  Definition text_interp (f: ident) (x: function) :=
    own clangG_textG_name (◯ {[ f := to_agree (x : discreteC function) ]}).

  Definition stack_interp (s: stack) :=
    own clangG_stackG_name ((1/2)%Qp, (to_agree (s: discreteC stack))).

  Definition to_gen_text (t: text) := fmap (λ v, to_agree (v : leibnizC function)) t.

  Definition own_text (m: text) : iProp Σ :=
    own clangG_textG_name (● to_gen_text m).

  Definition to_gen_stack (s: stack) := ((1/2)%Qp, (to_agree (s: discreteC stack))).

  Definition own_stack (s: stack) : iProp Σ := own clangG_stackG_name (to_gen_stack s).

  Definition clang_state_interp (s: state) : iProp Σ:=
    (gen_heap_ctx (s_heap s) ∗ own_text (s_text s) ∗ own_stack (s_stack s))%I.

  Fixpoint mapstobytes l q bytes: iProp Σ :=
    let '(b, o) := l in
    (match bytes with
       | byte::bs' => mapsto l q byte ∗ mapstobytes (b, o + 1)%nat q bs'
       | _ => True
     end)%I.

  Definition mapstoval (l: addr) (q: Qp) (v: val) (t: type) : iProp Σ :=
    (⌜ typeof v t ⌝ ∗ mapstobytes l q (encode_val v))%I.

End wp.

Instance heapG_irisG `{clangG Σ}: irisG clang_lang Σ := {
  iris_invG := clangG_invG;
  state_interp := clang_state_interp
}.

Global Opaque iris_invG.

Notation "l ↦{ q } v @ t" := (mapstoval l q v t)%I
  (at level 20, q at level 50, format "l  ↦{ q }  v  @  t") : uPred_scope.
Notation "l ↦ v @ t" :=
  (mapstoval l 1%Qp v t)%I (at level 20) : uPred_scope.
Notation "l ↦{ q } - @ t" := (∃ v, l ↦{q} v @ t)%I
  (at level 20, q at level 50, format "l  ↦{ q }  -  @  t") : uPred_scope.
Notation "l ↦ - @ t" := (l ↦{1} - @ t)%I (at level 20) : uPred_scope.

Section rules.
  Context `{clangG Σ}.

  Lemma wp_bind' kes E e Φ :
    ⌜ is_jmp e = false ⌝ ∗
    WP e @ E {{ v, WP (fill_ectxs (Evalue v) kes) @ E {{ Φ }} }} ⊢ WP (fill_ectxs e kes) @ E {{ Φ }}.
  Proof.
    iIntros "H". iLöb as "IH" forall (E e Φ). rewrite wp_unfold /wp_pre.
    iDestruct "H" as "[% [Hv|[% H]]]".
    { iDestruct "Hv" as (v) "[Hev Hv]"; iDestruct "Hev" as % <-%of_to_val.
        by iApply fupd_wp. }
    rewrite wp_unfold /wp_pre. iRight; iSplit; eauto using fill_ectxs_not_val.
    iIntros (σ1) "Hσ". iMod ("H" $! _ with "Hσ") as "[% H]".
    iModIntro; iSplit.
    { iPureIntro. unfold reducible in *.
      destruct H2 as (cur'&σ'&?&?&?). eexists _, _, [].
      split; last done. apply CSbind=>//. }
    iNext. iIntros (e2 σ2 ? (Hstep & ?)).
    destruct (fill_step_inv e σ1 e2 σ2 kes) as (e2'&->&?&?); auto; subst.
    iMod ("H" $! _ _ _ with "[%]") as "($ & H & ?)"; eauto.
    { split; done. }
    iFrame "~".
    iApply "IH". iSplit=>//.
    iPureIntro. eapply cstep_preserves_not_jmp=>//.
  Qed.

  Lemma wp_bind kes E e Φ :
    is_jmp e = false →
    WP e @ E {{ v, WP (fill_ectxs (Evalue v) kes) @ E {{ Φ }} }} ⊢ WP (fill_ectxs e kes) @ E {{ Φ }}.
  Proof. iIntros (?) "?". iApply wp_bind'. iSplit; done. Qed.

  Definition reducible := @reducible clang_lang.

  Lemma wp_lift_step E Φ e1 :
    to_val e1 = None →
    (∀ σ1, state_interp σ1 ={E,∅}=∗
      ⌜ reducible e1 σ1⌝ ∗
      ▷ ∀ e2 σ2 efs, ⌜step e1 σ1 e2 σ2 efs⌝ ={∅,E}=∗
        state_interp σ2 ∗ WP e2 @ E {{ Φ }} ∗ [∗ list] ef ∈ efs, WP ef {{ _, True }})
    ⊢ WP e1 @ E {{ Φ }}.
  Proof. iIntros (?) "H". rewrite wp_unfold /wp_pre; auto. Qed.

  Lemma wp_lift_pure_step E Φ e1 :
    (∀ σ1, reducible e1 σ1) →
    (∀ σ1 σ2 cur2 efs, step e1 σ1 cur2 σ2 efs → σ1 = σ2) →
    (▷ ∀ cur2 σ1 σ2 efs, ⌜ step e1 σ1 cur2 σ2 efs ⌝ →
                WP cur2 @ E {{ Φ }} ∗ [∗ list] ef ∈ efs, WP ef {{ _, True }})
      ⊢ WP e1 @ E {{ Φ }}.
  Proof.
    iIntros (Hsafe ?) "H".
    iApply wp_lift_step.
    { eapply (@reducible_not_val clang_lang), (Hsafe inhabitant). }
    iIntros (σ1) "Hσ". iMod (fupd_intro_mask' E ∅) as "Hclose"; first set_solver.
    iModIntro. iSplit; [done|]; iNext; iIntros (e2 σ2 ? ?).
    iMod "Hclose"; iModIntro.
    destruct (H0 _ _ _ _ H1) as [? ?]. subst. iFrame.
    by iApply "H".
  Qed.

  Lemma stack_agree ks ks':
    stack_interp ks ∗ own_stack ks' ⊢ ⌜ ks = ks' ⌝.
  Proof.
    iIntros "[Hs' Hs]".
    rewrite /stack_interp /own_stack.
    iDestruct (own_valid_2 with "Hs Hs'") as "%".
    iPureIntro. destruct H0 as [? ?].
    simpl in H1. by apply to_agree_comp_valid in H1.
  Qed.

  Lemma stack_pop k k' ks ks':
    stack_interp (k::ks) ∗ own_stack (k'::ks') ==∗ stack_interp (ks) ∗ own_stack (ks') ∗ ⌜ k = k' ∧ ks = ks' ⌝.
  Proof.
    iIntros "[Hs Hs']".
    iDestruct (stack_agree with "[-]") as "%"; first iFrame.
    inversion H0. subst.
    rewrite /stack_interp /own_stack.
    iMod (own_update_2 with "Hs Hs'") as "[Hs Hs']"; last by iFrame.
    rewrite pair_op frac_op' Qp_div_2.
    apply cmra_update_exclusive.
    split; simpl.
    - by rewrite frac_op'.
    - by apply to_agree_comp_valid.
  Qed.

  Lemma stack_push k ks ks':
    stack_interp (ks) ∗ own_stack (ks') ==∗ stack_interp (k::ks) ∗ own_stack (k::ks') ∗ ⌜ ks = ks' ⌝.
  Proof.
    iIntros "[Hs Hs']".
    iDestruct (stack_agree with "[-]") as "%"; first iFrame.
    inversion H0. subst.
    rewrite /stack_interp /own_stack.
    iMod (own_update_2 with "Hs Hs'") as "[Hs Hs']"; last by iFrame.
    - rewrite pair_op frac_op' Qp_div_2.
      apply cmra_update_exclusive.
      split; simpl
      + by rewrite frac_op'.
      + done.
      + by apply to_agree_comp_valid.
  Qed.

  Lemma wp_ret k k' ks v E Φ:
    stack_interp (k'::ks) ∗
    (stack_interp ks -∗ WP fill_ectxs (Evalue v) k' @ E {{ Φ }})
    ⊢ WP fill_ectxs (Erete (Evalue v)) k @ E {{ Φ }}.
  Proof.
    iIntros "[Hs HΦ]". iApply wp_lift_step; eauto; first by apply fill_ectxs_not_val.
    iIntros (?) "[Hσ [HΓ Hstk]]".
    iMod (fupd_intro_mask' _ ∅) as "Hclose"; first set_solver.
    iModIntro. iSplit.
    { iDestruct (stack_agree with "[Hstk Hs]") as "%"; first iFrame.
      subst. iPureIntro. destruct a. eexists _, (State s_heap s_text _), [].
      split; last done. apply CSjstep. simpl in H0. subst. constructor.
      by apply cont_uninj. }
    iNext. iIntros (??? (? & ?)).
    inversion H0; subst.
    { by apply fill_estep_false in H2. }
    inversion H2; subst.
    - assert (Erete (Evalue v0) = Erete (Evalue v) ∧ k'0 = k) as (?&?).
      { apply cont_inj=>//. }
      inversion H3. subst. iMod (stack_pop with "[Hstk Hs]") as "(Hstk & Hs & %)"; first iFrame.
      destruct H5; subst.
      iFrame. iMod "Hclose" as "_".
      iModIntro. iSplitL; first by iApply "HΦ".
      by rewrite big_sepL_nil.
    - apply cont_inj in H1=>//.
      destruct H1 as [? ?]; done.
  Qed.

  Lemma wp_skip E Φ v s:
    ▷ WP s @ E {{ Φ }} ⊢ WP Eseq (Evalue v) s @ E {{ Φ }}.
  Proof.
    iIntros "Φ". iApply wp_lift_pure_step; eauto.
    - destruct σ1. eexists _, _, []. split; auto.
    - destruct 1.
      inversion H0=>//.
      + simplify_eq. inversion H2=>//. simplify_eq.
        exfalso. replace (Eseq (Evalue v) s) with (fill_ectxs (Eseq (Evalue v) s) []) in H1; last done.
        replace (fill_expr (fill_ectxs e kes) k)
        with (fill_ectxs e (k::kes)) in H1; last done.
        eapply (escape_false H4 H1). by simpl.
      + simplify_eq. inversion H2; subst.
        * unfold unfill in H4. rewrite H1 in H4.
          simpl in H4. done.
        * replace (Eseq (Evalue v) s) with (fill_ectxs (Eseq (Evalue v) s) []) in H1 =>//.
          apply cont_inj in H1=>//. by destruct H1.
    - iNext. iIntros (???? (?& ?)).
      inversion H0; subst.
      + inversion H2; subst.
        { iFrame. by rewrite big_sepL_nil. }
        { exfalso. by eapply (escape_false H4 H1). }
      + simplify_eq. inversion H2; subst.
        * by rewrite /unfill H1 /= in H4.
        * replace (Eseq (Evalue v) s) with (fill_ectxs (Eseq (Evalue v) s) []) in H1 =>//.
          apply cont_inj in H1=>//.
          by destruct H1.
  Qed.

  Lemma wp_seq E e1 e2 Φ:
    is_jmp e1 = false →
    WP e1 @ E {{ v, WP Eseq (Evalue v) e2 @ E {{ Φ }} }} ⊢ WP Eseq e1 e2 @ E {{ Φ }}.
  Proof. iIntros (?) "Hseq". iApply (wp_bind [EKseq e2])=>//. Qed.

  Lemma wp_lift_atomic_step {E Φ} s1 :
    to_val s1 = None →
    (∀ σ1, state_interp σ1 ={E}=∗
      ⌜reducible s1 σ1⌝ ∗
      ▷ ∀ s2 σ2, ⌜cstep s1 σ1 s2 σ2⌝ ={E}=∗
        state_interp σ2 ∗
        default False (to_val s2) Φ)
    ⊢ WP s1 @ E {{ Φ }}.
  Proof.
    iIntros (?) "H". iApply (wp_lift_step E _ s1)=>//; iIntros (σ1) "Hσ1".
    iMod ("H" $! σ1 with "Hσ1") as "[$ H]".
    iMod (fupd_intro_mask' E ∅) as "Hclose"; first set_solver.
    iModIntro; iNext; iIntros (s2 σ2 ? (? &?)). iMod "Hclose" as "_".
    iMod ("H" $! _ _ with "[#]") as "($ & H)"=>//.
    destruct (to_val s2) eqn:?; last by iExFalso.
    iSplitL; first by iApply wp_value.
    subst. by rewrite big_sepL_nil.
  Qed.

  Lemma gen_heap_update_bytes (σ: heap):
    ∀ bs l bs',
      length bs = length bs' →
      gen_heap_ctx σ -∗ mapstobytes l 1 bs ==∗
      (gen_heap_ctx (storebytes l bs' σ) ∗ mapstobytes l 1 bs').
  Proof.
    induction bs; destruct l.
    - intros []=>//. intros _. iIntros "$ _"=>//.
    - induction bs'=>//. simpl. intros [=].
      iIntros "Hσ [Ha Hbs]".
      iMod (IHbs with "Hσ Hbs") as "[Hσ' Hbs']"=>//.
      iMod (@gen_heap_update with "Hσ' Ha") as "[$ Ha']".
      by iFrame.
  Qed.

  Ltac absurd_jstep :=
    match goal with
      | [ HF: fill_ectxs _ _ = ?E |- _ ] =>
        replace E with (fill_ectxs E []) in HF=>//; apply cont_inj in HF=>//;
              by destruct HF
    end.

  Ltac atomic_step H :=
    inversion H; subst;
    [ match goal with
        | [ HE: estep _ _ _ _ |- _ ] =>
          inversion HE; subst;
            [ idtac | exfalso;
                match goal with
                  | [ HF: fill_expr (fill_ectxs ?E _) _ = _, HE2: estep ?E _ _ _ |- _ ] =>
                      by eapply (escape_false HE2 HF)
                end ]
      end
    | match goal with
        | [ HJ : jstep _ _ _ _ _ |- _ ] =>
          inversion HJ; subst;
          [ match goal with
              | [ HU: unfill _ _ , HF: fill_ectxs _ _ = _ |- _ ] =>
                  by rewrite /unfill HF /= in HU
            end
          | absurd_jstep ]
      end
    ].

  Lemma wp_assign {E l v v'} t t' Φ:
    typeof v' t' → assign_type_compatible t t' →
    ▷ l ↦ v @ t ∗ ▷ (l ↦ v' @ t -∗ Φ Vvoid)
    ⊢ WP Eassign (Evalue (Vptr l)) (Evalue v') @ E {{ Φ }}.
  Proof.
    iIntros (??) "[Hl HΦ]".
    iApply wp_lift_atomic_step=>//.
    iIntros (σ1) "[Hσ [HΓ ?]] !>".
    rewrite /mapstoval. iSplit; first eauto.
    { iPureIntro. destruct σ1. eexists _, _, []. split; auto. }
    iNext; iIntros (v2 σ2 Hstep).
    iDestruct "Hl" as "[% Hl]".
    iDestruct (gen_heap_update_bytes _ (encode_val v) _ (encode_val v') with "Hσ Hl") as "H".
    { rewrite -(typeof_preserves_size v t)=>//.
      rewrite -(typeof_preserves_size v' t')=>//.
      by apply assign_preserves_size. }
    atomic_step Hstep.
    iMod "H" as "[Hσ' Hv']".
    iModIntro. iFrame. iApply "HΦ".
    iSplit=>//. iPureIntro.
    by apply (assign_preserves_typeof t t').
  Qed.

  Lemma mapstobytes_prod b q:
    ∀ v1 o v2,
      mapstobytes (b, o) q (encode_val (Vpair v1 v2)) ⊣⊢
      mapstobytes (b, o) q (encode_val v1) ∗
      mapstobytes (b, o + length (encode_val v1))%nat q (encode_val v2).
  Proof.
    intro v1. simpl. induction (encode_val v1); intros; iSplit.
    - iIntros "?". simpl. iSplit; first done. by rewrite Nat.add_0_r.
    - simpl. iIntros "[_ ?]". by rewrite Nat.add_0_r.
    - simpl. iIntros "[$ ?]". replace (o + S (length l))%nat with ((o + 1) + length l)%nat; last omega.
      by iApply IHl.
    - simpl. iIntros "[[$ ?] ?]".
      replace (o + S (length l))%nat with ((o + 1) + length l)%nat; last omega.
      iApply IHl. iFrame.
  Qed.

  Lemma mapstoval_split b o q v1 v2 t1 t2:
    (b, o) ↦{q} Vpair v1 v2 @ Tprod t1 t2 ⊢
    (b, o) ↦{q} v1 @ t1 ∗ (b, o + sizeof t1)%nat ↦{q} v2 @ t2.
  Proof.
    iIntros "[% H]".
      match goal with [H : typeof _ _ |- _] => inversion H; subst end.
      iDestruct (mapstobytes_prod with "H") as "[H1 H2]".
      iSplitL "H1".
      + by iFrame.
      + rewrite (typeof_preserves_size v1 t1)//.
        by iFrame.
  Qed.

  Lemma mapstoval_join b o q v1 v2 t1 t2:
    (b, o) ↦{q} v1 @ t1 ∗ (b, o + sizeof t1)%nat ↦{q} v2 @ t2 ⊢
    (b, o) ↦{q} Vpair v1 v2 @ Tprod t1 t2.
  Proof.
    iIntros "[[% H1] [% H2]]".
    iDestruct (mapstobytes_prod with "[H1 H2]") as "?".
    { iFrame "H1". by rewrite -(typeof_preserves_size v1 t1). }
    iFrame. iPureIntro. by constructor.
  Qed.

  Lemma mapsto_readbytes q (σ: heap):
    ∀ bs l, mapstobytes l q bs ∗ gen_heap_ctx σ ⊢ ⌜ readbytes l bs σ ⌝.
  Proof.
    induction bs.
    - iIntros (?) "(Hp & Hσ)". done.
    - destruct l. simpl. iIntros "((Ha & Hp) & Hσ)".
      iDestruct (@gen_heap_valid with "Hσ Ha") as %?.
      iDestruct (IHbs with "[Hp Hσ]") as %?; first iFrame.
      iPureIntro. auto.
  Qed.

  Instance timeless_mapstobytes q bs p: TimelessP (mapstobytes p q bs)%I.
  Proof.
    generalize bs p.
    induction bs0; destruct p0; first apply _.
    simpl. assert (TimelessP (mapstobytes (b, (n + 1)%nat) q bs0)) as ?; first done.
    apply _.
  Qed.

  Instance timeless_mapstoval p q v t : TimelessP (p ↦{q} v @ t)%I.
  Proof. rewrite /mapstoval. apply _. Qed.

  Lemma wp_load {E} Φ p v t q:
    ▷ p ↦{q} v @ t ∗ ▷ (p ↦{q} v @ t -∗ Φ v)
    ⊢ WP Ederef_typed t (Evalue (Vptr p)) @ E {{ Φ }}.
  Proof.
    iIntros "[Hl HΦ]".
    iApply wp_lift_atomic_step=>//.
    iIntros (σ1) "[Hσ [HΓ Hs]]".
    unfold mapstoval.
    iDestruct "Hl" as "[>% >Hl]".
    iDestruct (mapsto_readbytes with "[Hσ Hl]") as "%"; first iFrame.
    iModIntro. iSplit; first eauto.
    { iPureIntro. destruct σ1. eexists _, _, []. simpl in H1. split; auto. by repeat constructor. }
    iNext; iIntros (s2 σ2 Hstep). iModIntro.
    atomic_step Hstep.
    simpl. iFrame.
    rewrite (same_type_encode_inj h' t v v0 p)=>//.
    iApply ("HΦ" with "[-]") ; first by iSplit=>//.
  Qed.

  Lemma wp_op E op v1 v2 v' Φ:
    evalbop op v1 v2 = Some v' →
    Φ v' ⊢ WP Ebinop op (Evalue v1) (Evalue v2) @ E {{ Φ }}.
  Proof.
    iIntros (?) "HΦ".
    iApply wp_lift_pure_step; first eauto.
    { destruct σ1. eexists _, _, _. by repeat constructor. }
    { destruct 1. atomic_step H1=>//. }
    iNext. iIntros (????(?&?)).
    atomic_step H1.
    rewrite H0 in H9. inversion H9. subst.
    iSplitL; first by iApply wp_value=>//.
    by rewrite big_sepL_nil.
  Qed.

  Lemma wp_while_true cond s Φ:
    ▷ WP Eseq s (Ewhile cond cond s) {{ Φ }}
    ⊢ WP Ewhile cond (Evalue vtrue) s {{ Φ }}.
  Proof.
    iIntros "Hnext".
    iApply wp_lift_pure_step; first eauto.
    { destruct σ1. eexists _, _, []. by repeat constructor. }
    { destruct 1. atomic_step H0=>//. }
    iNext. iIntros (???? (?&?)).
    atomic_step H0.
    iSplitL=>//.
    by rewrite big_sepL_nil.
  Qed.

  Lemma wp_while_false cond s Φ:
    ▷ Φ Vvoid
    ⊢ WP Ewhile cond (Evalue vfalse) s {{ Φ }}.
  Proof.
    iIntros "HΦ".
    iApply wp_lift_pure_step; first eauto.
    { destruct σ1. eexists _, _, []. by repeat constructor. }
    { destruct 1. atomic_step H0=>//. }
    iNext. iIntros (???? (?&?)).
    atomic_step H0.
    iSplitL; first by iApply wp_value.
    by rewrite big_sepL_nil.
  Qed.

  Lemma wp_while_inv I Q cond s:
    is_jmp s = false → is_jmp cond = false →
    □ (∀ Φ, (I ∗ (∀ v, ((⌜ v = vfalse ⌝ ∗ Q Vvoid) ∨ (⌜ v = vtrue ⌝ ∗ I)) -∗ Φ v) -∗ WP cond {{ Φ }})) ∗
    □ (∀ Φ, (I ∗ (I -∗ Φ Vvoid)) -∗ WP s {{ Φ }}) ∗ I
    ⊢ WP Ewhile cond cond s {{ Q }}.
  Proof.
    iIntros (??) "(#Hcond & #Hs & HI)".
    iLöb as "IH".
    iApply (wp_bind [EKwhile cond s])=>//.
    iApply "Hcond". iFrame.
    iIntros (v) "[[% HQ]|[% HI]]"; subst.
    - iApply wp_while_false. by iNext.
    - iApply wp_while_true. iNext.
      iApply wp_seq=>//. iApply "Hs". iFrame.
      iIntros "HI". iApply wp_skip.
      iApply "IH". by iNext.
  Qed.

  Lemma wp_fst v1 v2 Φ:
    ▷ Φ v1
    ⊢ WP Efst (Evalue (Vpair v1 v2)) {{ Φ }}.
  Proof.
    iIntros "HΦ".
    iApply wp_lift_pure_step; first eauto.
    { destruct σ1. eexists _, _, _. by repeat constructor. }
    { destruct 1. atomic_step H0=>//. }
    iNext. iIntros (???? (?&?)).
    atomic_step H0. iSplitL; first by iApply wp_value.
    by rewrite big_sepL_nil.
  Qed.

  Lemma wp_snd v1 v2 Φ:
    ▷ Φ v2
    ⊢ WP Esnd (Evalue (Vpair v1 v2)) {{ Φ }}.
  Proof.
    iIntros "HΦ".
    iApply wp_lift_pure_step; first eauto.
    { destruct σ1. eexists _, _, _. by repeat constructor. }
    { destruct 1. atomic_step H0=>//. }
    iNext. iIntros (????(?&?)).
    atomic_step H0. iSplitL; first by iApply wp_value.
    by rewrite big_sepL_nil.
  Qed.

  (* Freshness and memory allocation *)

  Definition fresh_block (σ: heap) : block :=
    let addrst : list addr := elements (dom _ σ : gset addr) in
    let blockset : gset block := foldr (λ l, ({[ l.1 ]} ∪)) ∅ addrst in
    fresh blockset.

  Lemma is_fresh_block σ i: σ !! (fresh_block σ, i) = None.
  Proof.
    assert (∀ (l: addr) ls (X : gset block),
              l ∈ ls → l.1 ∈ foldr (λ l, ({[ l.1 ]} ∪)) X ls) as help.
    { induction 1; set_solver. }
    rewrite /fresh_block /= -not_elem_of_dom -elem_of_elements.
    move=> /(help _ _ ∅) /=. apply is_fresh.
  Qed.

  Lemma alloc_fresh σ v t:
    let l := (fresh_block σ, 0)%nat in
    typeof v t →
    estep (Ealloc t (Evalue v)) σ (Evalue (Vptr l)) (storebytes l (encode_val v) σ).
  Proof.
    intros l ?. apply ESalloc. auto.
    intros o'. apply (is_fresh_block _ o').
  Qed.

  Lemma fresh_store σ1 b o bs:
    ∀ a : nat,
      a > 0 →
      σ1 !! (b, o) = None →
      storebytes (b, (o + a)%nat) bs σ1 !! (b, o) = None.
  Proof.
    induction bs=>//.
    intros. simpl.
    apply lookup_insert_None.
    split. rewrite -Nat.add_assoc.
    apply IHbs=>//. induction a0; crush.
    intros [=]. omega.
  Qed.

  Lemma gen_heap_update_block bs:
    ∀ σ1 b o,
      (∀ o' : offset, σ1 !! (b, o') = None) →
      gen_heap_ctx σ1 ⊢ |==> gen_heap_ctx (storebytes (b, o) bs σ1) ∗ mapstobytes (b, o) 1 bs.
  Proof.
    induction bs.
    - simpl. iIntros (????) "Hσ". eauto.
    - simpl. iIntros (????) "Hσ".
      iMod (IHbs with "Hσ") as "[Hσ' Hbo]"=>//.
      iFrame. iMod (gen_heap_alloc _ (b, o) with "Hσ'") as "[Hσ Hbo]".
      apply fresh_store=>//.
      by iFrame.
  Qed.

  Lemma wp_alloc E v t Φ:
    typeof v t →
    (∀ l, l ↦ v @ t -∗ Φ (Vptr l))
    ⊢ WP Ealloc t (Evalue v) @ E {{ Φ }}.
  Proof.
    iIntros (?) "HΦ".
    iApply wp_lift_atomic_step=>//.
    iIntros ((σ1&Γ) ks1) "[Hσ1 HΓ]".
    iModIntro. iSplit.
    { iPureIntro. eexists _, _, []. split; last done. apply CSestep. by apply alloc_fresh. }
    iNext. iIntros (e2 σ2 ?).
    atomic_step H1.
    iMod (gen_heap_update_block with "Hσ1") as "[? ?]"=>//.
    iFrame. iModIntro.
    iApply "HΦ". by iFrame.
  Qed.

  (* Call *)

  Fixpoint alloc_params (addrs: list (type * addr)) (vs: list val) :=
    (match addrs, vs with
       | (t, l)::params, v::vs => l ↦ v @ t ∗ alloc_params params vs
       | [], [] => True
       | _, _ => False
     end)%I.

  Lemma text_singleton_included (σ: text) l v :
    {[l := to_agree v]} ≼ (fmap (λ v, to_agree (v : leibnizC function)) σ) → σ !! l = Some v.
  Proof.
    rewrite singleton_included=> -[av []].
    rewrite lookup_fmap fmap_Some_equiv. intros [v' [Hl ->]].
    move=> /Some_included_total /to_agree_included /leibniz_equiv_iff -> //.
  Qed.

  Lemma lookup_text f x Γ:
    text_interp f x ∗ own_text Γ
    ⊢ ⌜ Γ !! f = Some x⌝.
  Proof.
    iIntros "[Hf HΓ]".
    rewrite /own_text /text_interp. iDestruct (own_valid_2 with "HΓ Hf")
      as %[Hl %text_singleton_included]%auth_valid_discrete_2.
    done.
  Qed.

  Lemma wp_call {E k ks es} ls params f_body f_body' f retty Φ:
    es = map (fun l => Evalue (Vptr l)) ls →
    instantiate_f_body (add_params_to_env (Env [] []) params ls) f_body = Some f_body' →
    text_interp f (Function retty params f_body) ∗
    stack_interp ks ∗
    ▷ (stack_interp (k::ks) -∗ WP f_body' @ E {{ Φ }})
    ⊢ WP fill_ectxs (Ecall f es) k @ E {{ Φ }}.
  Proof.
    iIntros (??) "[Hf [Hstk HΦ]]".
    iApply wp_lift_step=>//.
    { apply fill_ectxs_not_val. done. }
    iIntros ((σ1&Γ) ks1) "[Hσ1 [HΓ Hs]]". iMod (fupd_intro_mask' _ ∅) as "Hclose"; first set_solver.
    iDestruct (lookup_text with "[HΓ Hf]") as "%"; first iFrame=>//.
    simpl in H2.
    iModIntro. iSplit.
    { iPureIntro. eexists _, _, []. split; last done. apply CSjstep. eapply JScall=>//. }
    iNext. iIntros (e2 σ2 ? (?&?)).
    iMod "Hclose". inversion H3; subst.
    { apply fill_estep_false in H11=>//. }
    inversion H11; subst.
    + apply cont_inj in H0=>//.
      by destruct H0.
    + apply cont_inj in H0=>//.
      destruct H0. inversion H0. subst.
      iFrame. iDestruct (stack_agree with "[Hs Hstk]") as "%"; first iFrame.
      subst. iMod (stack_push with "[Hs Hstk]") as "(Hs & Hstk & %)"; first iFrame.
      iFrame.
      assert (ls0 = ls) as ?.
      { eapply map_inj=>//. simpl. intros. by inversion H6. }
      subst. clear H0 H9 H4.
      rewrite H5 in H2. inversion H2. subst. clear H2.
      rewrite H1 in H7. inversion H7.
      iSplitL; first by iApply "HΦ".
      by rewrite big_sepL_nil.
  Qed.

End rules.
