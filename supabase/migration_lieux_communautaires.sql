-- ════════════════════════════════════════════════════════════════════════
-- Lieux pet-friendly : guide collaboratif (étape 1 — données, droits, modération)
--
-- Un même lieu (petfriendly_places, identifiant stable) peut être :
--   • ajouté par la communauté (origine = 'communaute', sans gestionnaire) ;
--   • géré par son établissement (gestionnaire uid_pro + verification) ;
--   • partenaire (formule payante : plan <> 'decouverte', inchangé).
-- Trois notions séparées : origine, vérification du gestionnaire, statut
-- commercial (déduit de plan, les abonnements ne sont pas touchés).
--
-- Statuts de modération (statut) : brouillon, en_attente_validation,
-- actif (= publié), a_corriger, refuse, masque, suspendu (existant).
--
-- Conditions d'accueil : booléens à 3 états — true = oui, false = non,
-- null = « je ne sais pas » / non renseigné (jamais transformé en oui).
--
-- Retour arrière : voir la section ROLLBACK en fin de fichier.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

-- ── 1. Colonnes de la fiche ─────────────────────────────────────────────
ALTER TABLE public.petfriendly_places
  ADD COLUMN IF NOT EXISTS origine                  text NOT NULL DEFAULT 'etablissement',
  ADD COLUMN IF NOT EXISTS verification             text NOT NULL DEFAULT 'non_verifie',
  ADD COLUMN IF NOT EXISTS ajoute_par_uid           text,
  ADD COLUMN IF NOT EXISTS ajoute_par_profile_id    uuid,
  ADD COLUMN IF NOT EXISTS source_conditions        text NOT NULL DEFAULT 'etablissement',
  ADD COLUMN IF NOT EXISTS derniere_confirmation_le date,
  ADD COLUMN IF NOT EXISTS restriction_taille       boolean,
  ADD COLUMN IF NOT EXISTS supplement_animal        boolean,
  ADD COLUMN IF NOT EXISTS conditions_particulieres text,
  ADD COLUMN IF NOT EXISTS recommandation           text,
  ADD COLUMN IF NOT EXISTS motif_moderation         text;

-- Un lieu communautaire n'a ni gestionnaire, ni SIRET, ni tarif.
ALTER TABLE public.petfriendly_places
  ALTER COLUMN uid_pro          DROP NOT NULL,
  ALTER COLUMN siret            DROP NOT NULL,
  ALTER COLUMN sous_categorie   DROP NOT NULL,
  ALTER COLUMN code_postal      DROP NOT NULL,
  ALTER COLUMN prix_nuit_defaut DROP NOT NULL;

-- Contraintes (remplacent un éventuel CHECK existant sur statut).
DO $$
DECLARE c RECORD;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
            WHERE conrelid = 'public.petfriendly_places'::regclass AND contype = 'c'
              AND pg_get_constraintdef(oid) ILIKE '%statut%'
  LOOP
    EXECUTE format('ALTER TABLE public.petfriendly_places DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;
ALTER TABLE public.petfriendly_places
  DROP CONSTRAINT IF EXISTS pf_statut_check,
  DROP CONSTRAINT IF EXISTS pf_origine_check,
  DROP CONSTRAINT IF EXISTS pf_verification_check,
  DROP CONSTRAINT IF EXISTS pf_source_check,
  ADD CONSTRAINT pf_statut_check CHECK (statut IN
    ('brouillon', 'en_attente_validation', 'actif', 'a_corriger', 'refuse', 'masque', 'suspendu')),
  ADD CONSTRAINT pf_origine_check CHECK (origine IN ('communaute', 'etablissement')),
  ADD CONSTRAINT pf_verification_check CHECK (verification IN ('non_verifie', 'en_cours', 'verifie')),
  ADD CONSTRAINT pf_source_check CHECK (source_conditions IN ('communaute', 'etablissement'));

CREATE INDEX IF NOT EXISTS idx_pf_statut_origine ON public.petfriendly_places (statut, origine);
CREATE INDEX IF NOT EXISTS idx_pf_ajoute_par ON public.petfriendly_places (ajoute_par_uid);

-- Données existantes : fiches créées par leur établissement. Une fiche déjà
-- validée par l'admin a un gestionnaire vérifié.
UPDATE public.petfriendly_places
   SET origine = 'etablissement', source_conditions = 'etablissement',
       verification = CASE WHEN statut IN ('actif', 'suspendu') OR valide_at IS NOT NULL THEN 'verifie' ELSE 'en_cours' END
 WHERE uid_pro IS NOT NULL;

-- ── 2. Garde-fou : ce que seul l'admin (clé service) peut changer ────────
-- Publication, vérification, gestionnaire, origine, formule : jamais par un
-- utilisateur (contributeur ou pro), seulement via l'API admin.
CREATE OR REPLACE FUNCTION public.pf_garde_moderation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_admin boolean := coalesce(auth.jwt() ->> 'role', '') = 'service_role';
BEGIN
  IF v_admin THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.statut NOT IN ('brouillon', 'en_attente_validation') THEN NEW.statut := 'en_attente_validation'; END IF;
    NEW.verification := CASE WHEN NEW.uid_pro IS NULL THEN 'non_verifie' ELSE 'en_cours' END;
    NEW.plan := 'decouverte';
    NEW.valide_at := NULL; NEW.valide_par := NULL;
    RETURN NEW;
  END IF;
  -- UPDATE : champs réservés figés.
  NEW.verification := OLD.verification;
  NEW.origine      := OLD.origine;
  NEW.uid_pro      := OLD.uid_pro;
  NEW.ajoute_par_uid := OLD.ajoute_par_uid;
  NEW.plan         := OLD.plan;
  NEW.plan_expire_at := OLD.plan_expire_at;
  NEW.valide_at    := OLD.valide_at;
  NEW.valide_par   := OLD.valide_par;
  NEW.motif_moderation := OLD.motif_moderation;
  -- Statut : le contributeur peut seulement (re)soumettre une fiche brouillon
  -- ou « à corriger » ; le pro garde son statut publié.
  IF NEW.statut IS DISTINCT FROM OLD.statut THEN
    IF NOT (OLD.statut IN ('brouillon', 'a_corriger') AND NEW.statut IN ('brouillon', 'en_attente_validation')) THEN
      NEW.statut := OLD.statut;
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_pf_garde_moderation ON public.petfriendly_places;
CREATE TRIGGER trg_pf_garde_moderation
  BEFORE INSERT OR UPDATE ON public.petfriendly_places
  FOR EACH ROW EXECUTE FUNCTION public.pf_garde_moderation();

-- ── 3. Droits (RLS) ──────────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'petfriendly_places'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.petfriendly_places', pol.policyname);
  END LOOP;
END $$;

-- Lecture : fiches publiées pour tous ; ses propres fiches (contributeur,
-- gestionnaire, cogérant) quel que soit leur statut.
CREATE POLICY pf_select ON public.petfriendly_places FOR SELECT USING (
  statut = 'actif'
  OR ajoute_par_uid = (auth.jwt() ->> 'sub')
  OR uid_pro = (auth.jwt() ->> 'sub')
  OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = petfriendly_places.uid_pro
             AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
);

-- Création : un pro pour son établissement (parcours existant) ; un membre
-- pour un lieu communautaire (sans gestionnaire).
CREATE POLICY pf_insert ON public.petfriendly_places FOR INSERT WITH CHECK (
  uid_pro = (auth.jwt() ->> 'sub')
  OR (origine = 'communaute' AND uid_pro IS NULL AND ajoute_par_uid = (auth.jwt() ->> 'sub'))
);

-- Modification : le gestionnaire / cogérant ; le contributeur tant que sa
-- fiche n'est pas publiée (brouillon, à corriger, en attente).
CREATE POLICY pf_update ON public.petfriendly_places FOR UPDATE USING (
  uid_pro = (auth.jwt() ->> 'sub')
  OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.uid_gerant = petfriendly_places.uid_pro
             AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL)
  OR (uid_pro IS NULL AND ajoute_par_uid = (auth.jwt() ->> 'sub')
      AND statut IN ('brouillon', 'a_corriger', 'en_attente_validation'))
);

-- Suppression : le gestionnaire seulement (un contributeur retire son brouillon).
CREATE POLICY pf_delete ON public.petfriendly_places FOR DELETE USING (
  uid_pro = (auth.jwt() ->> 'sub')
  OR (uid_pro IS NULL AND ajoute_par_uid = (auth.jwt() ->> 'sub') AND statut = 'brouillon')
);

-- ── 4. Revendications d'une fiche (gratuites, vérifiées par l'admin) ─────
CREATE TABLE IF NOT EXISTS public.petfriendly_revendications (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  place_id          uuid NOT NULL REFERENCES public.petfriendly_places(id) ON DELETE CASCADE,
  uid               text NOT NULL,
  profile_id        uuid,
  fonction          text NOT NULL,
  siret             text,
  methode           text NOT NULL CHECK (methode IN ('email_pro', 'justificatif')),
  email_pro         text,
  email_confirme    boolean NOT NULL DEFAULT false,
  justificatif_url  text,
  statut            text NOT NULL DEFAULT 'en_attente' CHECK (statut IN ('en_attente', 'validee', 'refusee')),
  motif             text,
  traite_par        text,
  traite_le         timestamptz,
  created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pf_rev_place ON public.petfriendly_revendications (place_id, statut);
ALTER TABLE public.petfriendly_revendications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pf_rev_select ON public.petfriendly_revendications;
DROP POLICY IF EXISTS pf_rev_insert ON public.petfriendly_revendications;
CREATE POLICY pf_rev_select ON public.petfriendly_revendications FOR SELECT USING (uid = (auth.jwt() ->> 'sub'));
CREATE POLICY pf_rev_insert ON public.petfriendly_revendications FOR INSERT WITH CHECK (
  uid = (auth.jwt() ->> 'sub') AND statut = 'en_attente' AND email_confirme = false
);

-- ── 5. Corrections proposées par les membres ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.petfriendly_corrections (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  place_id    uuid NOT NULL REFERENCES public.petfriendly_places(id) ON DELETE CASCADE,
  uid         text NOT NULL,
  profile_id  uuid,
  champs      jsonb NOT NULL DEFAULT '{}'::jsonb,   -- {colonne: nouvelle valeur}
  commentaire text,
  statut      text NOT NULL DEFAULT 'en_attente' CHECK (statut IN ('en_attente', 'appliquee', 'refusee')),
  motif       text,
  traite_par  text,
  traite_le   timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pf_corr_place ON public.petfriendly_corrections (place_id, statut);
ALTER TABLE public.petfriendly_corrections ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS pf_corr_select ON public.petfriendly_corrections;
DROP POLICY IF EXISTS pf_corr_insert ON public.petfriendly_corrections;
CREATE POLICY pf_corr_select ON public.petfriendly_corrections FOR SELECT USING (uid = (auth.jwt() ->> 'sub'));
CREATE POLICY pf_corr_insert ON public.petfriendly_corrections FOR INSERT WITH CHECK (
  uid = (auth.jwt() ->> 'sub') AND statut = 'en_attente'
);

-- ── 6. Historique des décisions de modération (admin seulement) ──────────
CREATE TABLE IF NOT EXISTS public.petfriendly_moderation_log (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  place_id    uuid REFERENCES public.petfriendly_places(id) ON DELETE SET NULL,
  objet       text NOT NULL,          -- fiche | correction | revendication | avis | signalement
  objet_id    text,
  action      text NOT NULL,          -- publier | a_corriger | refuser | masquer | fusionner | valider | appliquer…
  motif       text,
  admin_uid   text,
  details     jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pf_log_place ON public.petfriendly_moderation_log (place_id, created_at DESC);
ALTER TABLE public.petfriendly_moderation_log ENABLE ROW LEVEL SECURITY;
-- Aucune policy : lecture / écriture par la clé service (API admin) uniquement.

COMMIT;

-- ════════════════════════════════════════════════════════════════════════
-- ROLLBACK (à exécuter seulement pour revenir en arrière) :
-- BEGIN;
-- DROP TRIGGER IF EXISTS trg_pf_garde_moderation ON public.petfriendly_places;
-- DROP FUNCTION IF EXISTS public.pf_garde_moderation();
-- DROP TABLE IF EXISTS public.petfriendly_moderation_log, public.petfriendly_corrections, public.petfriendly_revendications;
-- DELETE FROM public.petfriendly_places WHERE origine = 'communaute';
-- ALTER TABLE public.petfriendly_places DROP CONSTRAINT IF EXISTS pf_statut_check,
--   DROP CONSTRAINT IF EXISTS pf_origine_check, DROP CONSTRAINT IF EXISTS pf_verification_check,
--   DROP CONSTRAINT IF EXISTS pf_source_check;
-- ALTER TABLE public.petfriendly_places DROP COLUMN IF EXISTS origine, DROP COLUMN IF EXISTS verification,
--   DROP COLUMN IF EXISTS ajoute_par_uid, DROP COLUMN IF EXISTS ajoute_par_profile_id,
--   DROP COLUMN IF EXISTS source_conditions, DROP COLUMN IF EXISTS derniere_confirmation_le,
--   DROP COLUMN IF EXISTS restriction_taille, DROP COLUMN IF EXISTS supplement_animal,
--   DROP COLUMN IF EXISTS conditions_particulieres, DROP COLUMN IF EXISTS recommandation,
--   DROP COLUMN IF EXISTS motif_moderation;
-- -- puis rejouer migration_rls_tighten_perdus_petfriendly.sql (section petfriendly_places)
-- COMMIT;
-- ════════════════════════════════════════════════════════════════════════
