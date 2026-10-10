-- ═══════════════════════════════════════════════════════════════════════════
-- Annonces publiées : modification et renouvellement PAYANTS (4,99 €)
-- ───────────────────────────────────────────────────────────────────────────
-- Annonces animaux (éleveur, cheval particulier…) ET matériel (annonces_objets).
-- Associations exemptées (adoption, sans abonnement).
--   • Gratuit : photos, statut (disponible / réservé / vendu / pause), statut et
--     photos des chiots d'une portée.
--   • Verrouillé après publication (annonces) : espèce, race, sexe, type,
--     parents, date de naissance — supprimés de toute modification.
--   • Payant : tout le reste (1 modification = 1 paiement) et le renouvellement.
-- Paiement WEB (Stripe) : /api/annonces/modifier enregistre la modification
-- en attente puis crée la session ; le webhook l'applique au paiement.
-- Le stripe_price_id des 2 produits se saisit dans /admin → Produits ponctuels.
-- Idempotent, relançable.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

INSERT INTO public.produits_ponctuels (code, label, prix, duree_heures, description, actif)
VALUES
  ('annonce_modification', 'Modification d''annonce', 4.99, NULL,
   'Modification d''une annonce publiée (hors photos et disponibilité, gratuites)', true),
  ('annonce_renouvellement', 'Renouvellement d''annonce', 4.99, 720,
   'Renouvellement d''une annonce pour 30 jours', true)
ON CONFLICT (code) DO NOTHING;

-- Modifications en attente de paiement (écrites et appliquées par le serveur).
CREATE TABLE IF NOT EXISTS public.annonces_modifications (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  table_source      text NOT NULL CHECK (table_source IN ('annonces', 'annonces_objets')),
  annonce_id        text NOT NULL,
  uid               text NOT NULL,
  action            text NOT NULL CHECK (action IN ('modification', 'renouvellement')),
  changements       jsonb NOT NULL DEFAULT '{}'::jsonb,
  statut            text NOT NULL DEFAULT 'attente' CHECK (statut IN ('attente', 'appliquee', 'annulee')),
  stripe_session_id text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  appliquee_le      timestamptz
);
CREATE INDEX IF NOT EXISTS annonces_modifications_annonce_idx ON public.annonces_modifications (annonce_id, created_at DESC);

ALTER TABLE public.annonces_modifications ENABLE ROW LEVEL SECURITY;
REVOKE INSERT, UPDATE, DELETE ON public.annonces_modifications FROM anon, authenticated;
GRANT SELECT ON public.annonces_modifications TO authenticated;
DROP POLICY IF EXISTS annonces_modifications_moi ON public.annonces_modifications;
CREATE POLICY annonces_modifications_moi ON public.annonces_modifications
  FOR SELECT USING (uid = (auth.jwt() ->> 'sub'));

-- Portée sans les champs libres des chiots (statut, photos).
CREATE OR REPLACE FUNCTION public.pm_portee_sans_libres(p jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(jsonb_agg((e - 'statut' - 'photos') ORDER BY i), '[]'::jsonb)
  FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p) = 'array' THEN p ELSE '[]'::jsonb END)
       WITH ORDINALITY AS t(e, i)
$$;

-- Garde-fou : un client (jeton Firebase) ne peut modifier directement qu'un
-- brouillon, ou les champs libres d'une annonce publiée. Le serveur
-- (service_role, sans jeton : webhook, API, crons) passe toujours.
CREATE OR REPLACE FUNCTION public.pm_annonce_garde_fou()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  n jsonb := to_jsonb(NEW);
  o jsonb := to_jsonb(OLD);
  k text;
  libres text[] := ARRAY['statut', 'photos', 'updated_at', 'vues', 'contacts',
                         'is_suspect', 'suspect_reasons', 'lat', 'lng', 'latitude', 'longitude'];
BEGIN
  IF (auth.jwt() ->> 'sub') IS NULL THEN RETURN NEW; END IF;
  IF coalesce(OLD.statut, '') = 'brouillon' THEN RETURN NEW; END IF;
  -- Associations (adoption, sans abonnement) : modification et renouvellement gratuits.
  IF (o ->> 'profil_source') = 'association' THEN RETURN NEW; END IF;

  IF n ? 'animaux_portee' AND n -> 'animaux_portee' IS DISTINCT FROM o -> 'animaux_portee'
     AND public.pm_portee_sans_libres(n -> 'animaux_portee')
         IS DISTINCT FROM public.pm_portee_sans_libres(o -> 'animaux_portee') THEN
    RAISE EXCEPTION 'Modification payante : utilisez « Modifier l''annonce »' USING ERRCODE = 'P0001';
  END IF;

  FOR k IN SELECT jsonb_object_keys(n) LOOP
    -- Champs « élevage » recopiés depuis le profil (nom, ville… _eleveur).
    CONTINUE WHEN k = ANY (libres) OR k = 'animaux_portee' OR k LIKE '%\_eleveur';
    IF n -> k IS DISTINCT FROM o -> k THEN
      RAISE EXCEPTION 'Modification payante (%) : utilisez « Modifier l''annonce »', k USING ERRCODE = 'P0001';
    END IF;
  END LOOP;

  -- Une annonce expirée ne se réactive qu'en la renouvelant.
  IF (o ->> 'expires_at') IS NOT NULL AND (o ->> 'expires_at')::timestamptz < now()
     AND NEW.statut IN ('disponible', 'reserve') AND NEW.statut IS DISTINCT FROM OLD.statut THEN
    RAISE EXCEPTION 'Annonce expirée : renouvelez-la pour la remettre en ligne' USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_annonce_garde_fou ON public.annonces;
CREATE TRIGGER trg_annonce_garde_fou BEFORE UPDATE ON public.annonces
  FOR EACH ROW EXECUTE FUNCTION public.pm_annonce_garde_fou();
DROP TRIGGER IF EXISTS trg_annonce_garde_fou ON public.annonces_objets;
CREATE TRIGGER trg_annonce_garde_fou BEFORE UPDATE ON public.annonces_objets
  FOR EACH ROW EXECUTE FUNCTION public.pm_annonce_garde_fou();


-- ── Chiots d'annonce ↔ fiches animal (animalId) : disponibilité synchronisée ──
--   annonce « réservé » → fiche « reserve » (si présente) ; « disponible » →
--   fiche « present » (si réservée). « vendu » ne touche pas la fiche (la
--   sortie passe par la cession).
--   fiche « reserve » → chiot « reserve » ; « present » → « disponible » ;
--   « sorti » (cédé) → « vendu ».
CREATE OR REPLACE FUNCTION public.pm_sync_chiots_vers_fiches()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE e jsonb; o jsonb; aid text; st text;
BEGIN
  IF pg_trigger_depth() > 1 THEN RETURN NEW; END IF;
  IF jsonb_typeof(NEW.animaux_portee) <> 'array' THEN RETURN NEW; END IF;
  FOR e IN SELECT * FROM jsonb_array_elements(NEW.animaux_portee) LOOP
    aid := e ->> 'animalId';
    st := e ->> 'statut';
    CONTINUE WHEN aid IS NULL OR st IS NULL;
    SELECT x INTO o FROM jsonb_array_elements(CASE WHEN TG_OP = 'UPDATE' AND jsonb_typeof(OLD.animaux_portee) = 'array'
                                                    THEN OLD.animaux_portee ELSE '[]'::jsonb END) x
      WHERE x ->> 'animalId' = aid LIMIT 1;
    CONTINUE WHEN o IS NOT NULL AND o ->> 'statut' IS NOT DISTINCT FROM st;
    IF st = 'reserve' THEN
      UPDATE animaux SET statut = 'reserve' WHERE id = aid AND statut = 'present';
    ELSIF st = 'disponible' THEN
      UPDATE animaux SET statut = 'present' WHERE id = aid AND statut = 'reserve';
    END IF;
  END LOOP;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_chiots_vers_fiches ON public.annonces;
CREATE TRIGGER trg_sync_chiots_vers_fiches AFTER INSERT OR UPDATE OF animaux_portee ON public.annonces
  FOR EACH ROW EXECUTE FUNCTION public.pm_sync_chiots_vers_fiches();

CREATE OR REPLACE FUNCTION public.pm_sync_fiche_vers_chiots()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE cible text;
BEGIN
  IF pg_trigger_depth() > 1 OR NEW.statut IS NOT DISTINCT FROM OLD.statut THEN RETURN NEW; END IF;
  cible := CASE NEW.statut WHEN 'reserve' THEN 'reserve' WHEN 'present' THEN 'disponible' WHEN 'sorti' THEN 'vendu' END;
  IF cible IS NULL THEN RETURN NEW; END IF;
  UPDATE annonces a SET animaux_portee = (
      SELECT jsonb_agg(CASE WHEN x ->> 'animalId' = NEW.id::text THEN jsonb_set(x, '{statut}', to_jsonb(cible)) ELSE x END ORDER BY i)
      FROM jsonb_array_elements(a.animaux_portee) WITH ORDINALITY t(x, i))
    WHERE jsonb_typeof(a.animaux_portee) = 'array'
      AND a.animaux_portee @> jsonb_build_array(jsonb_build_object('animalId', NEW.id::text))
      AND NOT a.animaux_portee @> jsonb_build_array(jsonb_build_object('animalId', NEW.id::text, 'statut', cible));
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_sync_fiche_vers_chiots ON public.animaux;
CREATE TRIGGER trg_sync_fiche_vers_chiots AFTER UPDATE OF statut ON public.animaux
  FOR EACH ROW EXECUTE FUNCTION public.pm_sync_fiche_vers_chiots();

NOTIFY pgrst, 'reload schema';

COMMIT;
