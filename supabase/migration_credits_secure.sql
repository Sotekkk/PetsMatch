-- ═══════════════════════════════════════════════════════════════════════════
-- Sécurisation des crédits — dépense/crédit via RPC SECURITY DEFINER, plus
-- aucune écriture directe possible sur credit_wallets / credit_transactions.
-- À exécuter APRÈS docs/migration_credits.sql dans le SQL Editor.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Verrouillage RLS : on supprime les policies d'écriture ouvertes.
--     (lecture conservée : l'appli lit le solde directement)
DROP POLICY IF EXISTS "wallets_insert"      ON public.credit_wallets;
DROP POLICY IF EXISTS "wallets_update"      ON public.credit_wallets;
DROP POLICY IF EXISTS "transactions_insert" ON public.credit_transactions;

-- Plus aucune policy INSERT/UPDATE → anon/authenticated ne peuvent plus écrire.
-- Ceinture + bretelles : on retire aussi les privilèges table.
REVOKE INSERT, UPDATE, DELETE ON public.credit_wallets      FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.credit_transactions FROM anon, authenticated;

-- ── 2. RPC de dépense : atomique, contrôle du solde côté serveur.
--     Retourne { ok, solde } ; { ok:false, error:'insufficient_credits' } si
--     le solde est trop bas (ne lève pas d'exception pour ce cas nominal).
CREATE OR REPLACE FUNCTION public.credit_spend(
  p_uid    text,
  p_cost   integer,
  p_motif  text,
  p_ref_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_solde integer;
BEGIN
  IF p_uid IS NULL OR p_uid = '' THEN
    RAISE EXCEPTION 'uid requis';
  END IF;
  IF p_cost IS NULL OR p_cost <= 0 THEN
    RAISE EXCEPTION 'montant invalide';
  END IF;

  UPDATE public.credit_wallets
     SET solde         = solde - p_cost,
         total_utilise = total_utilise + p_cost,
         updated_at    = now()
   WHERE uid = p_uid AND solde >= p_cost
  RETURNING solde INTO v_solde;

  IF NOT FOUND THEN
    SELECT solde INTO v_solde FROM public.credit_wallets WHERE uid = p_uid;
    RETURN jsonb_build_object('ok', false, 'error', 'insufficient_credits',
                              'solde', COALESCE(v_solde, 0));
  END IF;

  INSERT INTO public.credit_transactions (uid, montant, motif, ref_id)
  VALUES (p_uid, -p_cost, COALESCE(NULLIF(TRIM(p_motif), ''), 'Dépense'), p_ref_id);

  RETURN jsonb_build_object('ok', true, 'solde', v_solde);
END;
$$;

-- ── 3. RPC de crédit (achat pack Stripe validé, geste commercial admin…).
--     RÉSERVÉE au service role — jamais appelable depuis le client.
CREATE OR REPLACE FUNCTION public.credit_grant(
  p_uid    text,
  p_amount integer,
  p_motif  text,
  p_ref_id text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_solde integer;
BEGIN
  IF p_uid IS NULL OR p_uid = '' THEN
    RAISE EXCEPTION 'uid requis';
  END IF;
  IF p_amount IS NULL OR p_amount = 0 THEN
    RAISE EXCEPTION 'montant invalide';
  END IF;

  INSERT INTO public.credit_wallets (uid, solde, total_achete, updated_at)
  VALUES (p_uid, GREATEST(p_amount, 0), GREATEST(p_amount, 0), now())
  ON CONFLICT (uid) DO UPDATE
     SET solde        = public.credit_wallets.solde + p_amount,
         total_achete = public.credit_wallets.total_achete + GREATEST(p_amount, 0),
         updated_at   = now()
  RETURNING solde INTO v_solde;

  INSERT INTO public.credit_transactions (uid, montant, motif, ref_id)
  VALUES (p_uid, p_amount, COALESCE(NULLIF(TRIM(p_motif), ''), 'Crédit'), p_ref_id);

  RETURN jsonb_build_object('ok', true, 'solde', v_solde);
END;
$$;

-- ── 4. Permissions d'exécution.
REVOKE ALL ON FUNCTION public.credit_spend(text, integer, text, text) FROM public;
GRANT  EXECUTE ON FUNCTION public.credit_spend(text, integer, text, text)
  TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.credit_grant(text, integer, text, text) FROM public;
REVOKE ALL ON FUNCTION public.credit_grant(text, integer, text, text) FROM anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.credit_grant(text, integer, text, text) TO service_role;
