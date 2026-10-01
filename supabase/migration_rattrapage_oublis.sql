-- ════════════════════════════════════════════════════════════════════════
-- Rattrapage des migrations jamais (ou partiellement) passées en prod.
-- Inventaire du 01/10/2026 : 277 fichiers supabase/*.sql comparés à la base
-- prod (tables, colonnes, fonctions, vues, index, déclencheurs).
--
-- Repris ici (version sûre, compatible avec le durcissement RLS) :
-- 1. migration_pension_updates_reaction.sql — colonnes owner_liked /
--    owner_reply / owner_reply_at : le journal de pension du SITE plantait
--    (lecture de colonnes absentes) et le « J'aime » / la réponse du
--    propriétaire échouaient. + RPC pm_reagir_nouvelle_pension : le
--    propriétaire (mêmes droits que la lecture) ne peut modifier QUE sa
--    réaction, pas la nouvelle du pro.
-- 2. migration_restauration_pro.sql — UNIQUEMENT les 6 colonnes
--    user_profiles manquantes (inscription / tableau de bord restauration
--    cassés). Le reste du fichier N'EST PAS repris : il rouvrait
--    petfriendly_places et place_vues à tous (FOR ALL USING (true)) ; la
--    note des lieux est déjà tenue par trig_recalc_place_note ; place_vues
--    et les paliers de vues ne sont utilisés par aucun code.
-- 3. migration_expire_contracts_cron.sql — expiration quotidienne des
--    contrats non signés dans les délais (fonction appelée par
--    /api/contracts/expire, absente) ; pg_cron activé ; exécution
--    réservée au service (plus appelable par l'API publique).
-- 4. Index manquants (performances) d'anciennes migrations.
-- Non repris : schéma pa (facturation électronique, phase 4 en pause),
-- table pro_animal_access (inutilisée), idx_blf_uid / idx_xp_uid (colonne
-- user_uid inexistante — les tables utilisent d'autres colonnes).
-- ════════════════════════════════════════════════════════════════════════

CREATE EXTENSION IF NOT EXISTS pg_cron;

BEGIN;

-- ── 1. Réactions du propriétaire sur les nouvelles de pension ─────────────
ALTER TABLE public.pension_updates
  ADD COLUMN IF NOT EXISTS owner_liked BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS owner_reply TEXT,
  ADD COLUMN IF NOT EXISTS owner_reply_at TIMESTAMPTZ;

-- p_liked NULL = inchangé ; p_reply NULL = inchangé ('' = effacer)
CREATE OR REPLACE FUNCTION public.pm_reagir_nouvelle_pension(p_id uuid, p_liked boolean, p_reply text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub text := auth.jwt() ->> 'sub';
BEGIN
  IF v_sub IS NULL OR NOT EXISTS (
    SELECT 1 FROM pension_updates u
    WHERE u.id = p_id
      AND (v_sub = u.pro_uid
           OR EXISTS (SELECT 1 FROM elevage_cogerants c
                      WHERE c.uid_gerant = u.pro_uid AND c.uid_cogerant = v_sub
                        AND c.statut = 'actif' AND c.date_fin IS NULL)
           OR (u.animal_id IS NOT NULL AND is_animal_owner_or_cogerant(u.animal_id, v_sub)))
  ) THEN
    RAISE EXCEPTION 'Nouvelle introuvable ou accès refusé' USING ERRCODE = '42501';
  END IF;

  UPDATE pension_updates SET
    owner_liked    = coalesce(p_liked, owner_liked),
    owner_reply    = CASE WHEN p_reply IS NULL THEN owner_reply ELSE nullif(trim(p_reply), '') END,
    owner_reply_at = CASE WHEN p_reply IS NULL THEN owner_reply_at ELSE now() END
  WHERE id = p_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.pm_reagir_nouvelle_pension(uuid, boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pm_reagir_nouvelle_pension(uuid, boolean, text) TO anon, authenticated;

-- ── 2. Colonnes restauration (user_profiles) ──────────────────────────────
ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS type_restauration    TEXT,
  ADD COLUMN IF NOT EXISTS conditions_animaux   TEXT,
  ADD COLUMN IF NOT EXISTS equipements_animaux  JSONB DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS capacite_animaux     INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS adresse_pro          TEXT,
  ADD COLUMN IF NOT EXISTS cp_pro               TEXT;
-- vue masquée + droits colonne à jour (règle : après tout ajout de colonne)
SELECT public.pm_recreer_vues_perso();
SELECT public.pm_appliquer_droits_perso();

-- ── 3. Expiration automatique des contrats ────────────────────────────────
CREATE OR REPLACE FUNCTION public.expire_contracts()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r        RECORD;
  nb_total integer := 0;
BEGIN
  FOR r IN
    SELECT id, titre, token, uid_eleveur, metadata
    FROM   documents_animaux
    WHERE  expires_at IS NOT NULL
      AND  expires_at < now()
      AND  statut NOT IN ('signe', 'annule', 'expire', 'refuse')
  LOOP
    UPDATE documents_animaux SET statut = 'expire' WHERE id = r.id;

    INSERT INTO notifications (uid, type, title, body, data, profile_type, read)
    VALUES (r.uid_eleveur, 'contrat_expire', '⏰ Contrat expiré',
            'Le contrat « ' || COALESCE(r.titre, 'sans titre')
              || ' » a expiré — la signature n''est pas intervenue dans le délai prévu.',
            jsonb_build_object('token', r.token), '', false);

    INSERT INTO notifications (uid, type, title, body, data, profile_type, read)
    SELECT u.uid, 'contrat_expire', '⏰ Contrat expiré',
           'Le contrat « ' || COALESCE(r.titre, 'sans titre') || ' » a expiré.',
           jsonb_build_object('token', r.token), '', false
    FROM users u
    WHERE u.email = (r.metadata->>'acquereur_email')
    LIMIT 1;

    nb_total := nb_total + 1;
  END LOOP;
  RETURN nb_total;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.expire_contracts() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.expire_contracts() TO service_role;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'expire-contracts-daily') THEN
    PERFORM cron.unschedule('expire-contracts-daily');
  END IF;
END
$$;
SELECT cron.schedule('expire-contracts-daily', '0 2 * * *', 'SELECT public.expire_contracts()');

-- ── 4. Index manquants ────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_animaux_is_association ON public.animaux (is_association);
CREATE INDEX IF NOT EXISTS idx_inventaire_mouvements_elev ON public.inventaire_mouvements (uid_eleveur);
CREATE INDEX IF NOT EXISTS idx_prom_part_statut ON public.promenades_participants (promenade_id, statut);
CREATE INDEX IF NOT EXISTS idx_suivis_morpho_zones_suivi ON public.suivis_morpho_zones (suivi_id);
CREATE INDEX IF NOT EXISTS idx_annonces_boost_until ON public.annonces (boost_until) WHERE boost_until IS NOT NULL;

NOTIFY pgrst, 'reload schema';

COMMIT;
