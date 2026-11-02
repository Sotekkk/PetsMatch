-- ════════════════════════════════════════════════════════════════════════
-- Ordonnances refaites — lot 2 des documents vétérinaires. 02/11/2026.
--
--   • contenu structuré (jsonb) : lignes (médicament, principe actif,
--     présentation, posologie, voie, durée, quantité à délivrer,
--     renouvellement, instructions, mentions réglementaires), poids,
--     remarques ; le PDF est produit à partir de ce contenu ;
--   • statut : brouillon → validee (sans signature manuscrite) ou signee
--     (signature apposée) → remplacee (version rectificative validée) ;
--   • l'ASV PRÉPARE (brouillon), seul un vétérinaire VALIDE : titulaire,
--     cogérant ou employé role_pro = 'veterinaire' avec vet_ordonnances ;
--   • numéro attribué à la validation, par compte pro et par année
--     (2026-00001…) ;
--   • une ordonnance validée ne se modifie plus (contenu, numéro, date,
--     animal, validateur figés ; le PDF ne se dépose qu'une fois) ; une
--     correction = nouvelle version (remplace_id), l'ancienne passe en
--     « remplacee » à la validation de la nouvelle ;
--   • le propriétaire ne voit pas les brouillons ;
--   • suppression : brouillons seulement (sauf suppression en cascade de
--     l'animal).
--
-- Les ordonnances existantes (PDF déjà produit) passent en « signee » ;
-- une ligne sans PDF (doc_url vide) redevient un brouillon à compléter.
-- Idempotent. Staging d'abord (tests par rôle), puis prod AVANT le
-- déploiement du site / de l'appli.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.ordonnances ALTER COLUMN doc_url DROP NOT NULL;

ALTER TABLE public.ordonnances
  ADD COLUMN IF NOT EXISTS statut                TEXT NOT NULL DEFAULT 'signee',
  ADD COLUMN IF NOT EXISTS numero                TEXT,
  ADD COLUMN IF NOT EXISTS contenu               JSONB,
  ADD COLUMN IF NOT EXISTS cr_id                 UUID REFERENCES public.comptes_rendus(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS redige_par_uid        TEXT,
  ADD COLUMN IF NOT EXISTS redige_par_profile_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS valide_par_uid        TEXT,
  ADD COLUMN IF NOT EXISTS valide_par_profile_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS valide_le             TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS version               INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS remplace_id           UUID REFERENCES public.ordonnances(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS remplacee_par         UUID REFERENCES public.ordonnances(id) ON DELETE SET NULL;

ALTER TABLE public.ordonnances DROP CONSTRAINT IF EXISTS ordonnances_statut_check;
ALTER TABLE public.ordonnances ADD CONSTRAINT ordonnances_statut_check
  CHECK (statut IN ('brouillon', 'validee', 'signee', 'remplacee'));

-- Lignes existantes sans PDF : brouillon à compléter (avant la pose du déclencheur).
UPDATE public.ordonnances SET statut = 'brouillon'
 WHERE coalesce(doc_url, '') = '' AND statut <> 'brouillon';

CREATE UNIQUE INDEX IF NOT EXISTS ordonnances_numero_uniq
  ON public.ordonnances (pro_uid, numero) WHERE numero IS NOT NULL;
CREATE INDEX IF NOT EXISTS ordonnances_animal_idx ON public.ordonnances (animal_id);
CREATE INDEX IF NOT EXISTS ordonnances_cr_idx ON public.ordonnances (cr_id) WHERE cr_id IS NOT NULL;

-- ── Compteur des numéros (par compte pro et par année) ───────────────────
CREATE TABLE IF NOT EXISTS public.ordonnance_compteurs (
  pro_uid TEXT    NOT NULL,
  annee   INTEGER NOT NULL,
  dernier INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (pro_uid, annee)
);
ALTER TABLE public.ordonnance_compteurs ENABLE ROW LEVEL SECURITY;
-- Aucune policy : écrit seulement par le déclencheur (SECURITY DEFINER).

-- ── Qui peut valider / signer une ordonnance ─────────────────────────────
CREATE OR REPLACE FUNCTION public.pm_peut_prescrire(p_uid_compte text, p_profile_id text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT (auth.jwt() ->> 'sub') IS NOT NULL AND p_uid_compte IS NOT NULL AND (
    p_uid_compte = (auth.jwt() ->> 'sub')
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = p_uid_compte AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
        AND (nullif(p_profile_id, '') IS NULL OR c.elevage_profile_id IS NULL
             OR c.elevage_profile_id::text = p_profile_id)
    )
    OR EXISTS (
      SELECT 1 FROM employes e
      JOIN employe_permissions ep
        ON ep.eleveur_profile_id = e.eleveur_profile_id
       AND ep.employe_profile_id = e.employe_profile_id
      WHERE e.uid_eleveur = p_uid_compte AND e.uid_employe = (auth.jwt() ->> 'sub')
        AND e.actif = true AND e.role_pro = 'veterinaire'
        AND ep.permission = 'vet_ordonnances'
        AND (nullif(p_profile_id, '') IS NULL OR e.eleveur_profile_id IS NULL
             OR e.eleveur_profile_id::text = p_profile_id)
    )
  );
$$;
GRANT EXECUTE ON FUNCTION public.pm_peut_prescrire(text, text) TO anon, authenticated;

-- ── Contrôle des écritures ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.pm_ordonnance_controle()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sub   text := auth.jwt() ->> 'sub';
  v_annee integer;
  v_n     integer;
  v_old   public.ordonnances%ROWTYPE;
BEGIN
  -- service_role / maintenance (pas de jeton) : inchangé.
  IF v_sub IS NULL THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;

  IF TG_OP = 'DELETE' THEN
    -- Suppression directe : brouillons seulement (la cascade de l'animal passe).
    IF OLD.statut <> 'brouillon' AND pg_trigger_depth() <= 1 THEN
      RAISE EXCEPTION 'Ordonnance validée : suppression impossible (faites une version rectificative)'
        USING ERRCODE = '42501';
    END IF;
    RETURN OLD;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.redige_par_uid := coalesce(NEW.redige_par_uid, v_sub);
    NEW.numero := NULL;
    NEW.remplacee_par := NULL;
    NEW.valide_par_uid := NULL;
    NEW.valide_le := NULL;
    IF NEW.remplace_id IS NOT NULL THEN
      SELECT * INTO v_old FROM public.ordonnances WHERE id = NEW.remplace_id;
      IF NOT FOUND OR v_old.statut NOT IN ('validee', 'signee') OR v_old.pro_uid IS DISTINCT FROM NEW.pro_uid
         OR v_old.animal_id IS DISTINCT FROM NEW.animal_id THEN
        RAISE EXCEPTION 'Version rectificative : ordonnance d''origine introuvable ou non validée'
          USING ERRCODE = '23514';
      END IF;
      NEW.version := v_old.version + 1;
    ELSE
      NEW.version := 1;
    END IF;
    IF NEW.statut = 'remplacee' THEN NEW.statut := 'brouillon'; END IF;
  ELSE
    -- UPDATE d'une ordonnance déjà validée : contenu figé.
    IF OLD.statut <> 'brouillon' THEN
      IF NEW.contenu IS DISTINCT FROM OLD.contenu OR NEW.numero IS DISTINCT FROM OLD.numero
         OR NEW.date_emit IS DISTINCT FROM OLD.date_emit OR NEW.animal_id IS DISTINCT FROM OLD.animal_id
         OR NEW.valide_par_uid IS DISTINCT FROM OLD.valide_par_uid OR NEW.valide_le IS DISTINCT FROM OLD.valide_le
         OR NEW.version IS DISTINCT FROM OLD.version OR NEW.remplace_id IS DISTINCT FROM OLD.remplace_id
         OR NEW.praticien_uid IS DISTINCT FROM OLD.praticien_uid OR NEW.notes IS DISTINCT FROM OLD.notes
         OR (NEW.doc_url IS DISTINCT FROM OLD.doc_url AND coalesce(OLD.doc_url, '') <> '')
         OR (NEW.statut IS DISTINCT FROM OLD.statut
             AND NOT (NEW.statut = 'remplacee' AND NEW.remplacee_par IS NOT NULL))
         OR (NEW.statut = 'brouillon') THEN
        RAISE EXCEPTION 'Ordonnance validée : modification impossible (faites une version rectificative)'
          USING ERRCODE = '42501';
      END IF;
      IF NEW.statut = 'remplacee' AND OLD.statut <> 'remplacee'
         AND NOT public.pm_peut_prescrire(NEW.pro_uid, coalesce(NEW.pro_profile_id::text, '')) THEN
        RAISE EXCEPTION 'Seul un vétérinaire remplace une ordonnance' USING ERRCODE = '42501';
      END IF;
      RETURN NEW;
    END IF;
    -- Brouillon : numéro / validateur jamais posés à la main.
    NEW.numero := NULL;
    NEW.valide_par_uid := NULL;
    NEW.valide_le := NULL;
    NEW.remplacee_par := NULL;
    IF NEW.remplace_id IS DISTINCT FROM OLD.remplace_id OR NEW.version IS DISTINCT FROM OLD.version THEN
      RAISE EXCEPTION 'Version rectificative : rattachement non modifiable' USING ERRCODE = '42501';
    END IF;
    IF NEW.statut = 'remplacee' THEN
      RAISE EXCEPTION 'Statut invalide pour un brouillon' USING ERRCODE = '23514';
    END IF;
  END IF;

  -- Validation (brouillon → validee / signee, ou insertion directement validée).
  IF NEW.statut IN ('validee', 'signee') THEN
    IF NOT public.pm_peut_prescrire(NEW.pro_uid, coalesce(NEW.pro_profile_id::text, '')) THEN
      RAISE EXCEPTION 'Seul un vétérinaire valide et signe une ordonnance' USING ERRCODE = '42501';
    END IF;
    NEW.valide_par_uid := v_sub;
    NEW.valide_le := clock_timestamp();
    NEW.praticien_uid := v_sub;
    NEW.date_emit := coalesce(NEW.date_emit, current_date);
    -- Numéro : ordonnance structurée seulement (un PDF chargé garde le sien).
    IF NEW.contenu IS NOT NULL THEN
      v_annee := extract(year FROM NEW.date_emit)::integer;
      INSERT INTO public.ordonnance_compteurs AS c (pro_uid, annee, dernier)
      VALUES (NEW.pro_uid, v_annee, 1)
      ON CONFLICT (pro_uid, annee) DO UPDATE SET dernier = c.dernier + 1
      RETURNING dernier INTO v_n;
      NEW.numero := v_annee::text || '-' || lpad(v_n::text, 5, '0');
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ordonnance_controle ON public.ordonnances;
CREATE TRIGGER trg_ordonnance_controle
  BEFORE INSERT OR UPDATE OR DELETE ON public.ordonnances
  FOR EACH ROW EXECUTE FUNCTION public.pm_ordonnance_controle();

-- Version rectificative validée : l'ordonnance d'origine passe en « remplacee ».
CREATE OR REPLACE FUNCTION public.pm_ordonnance_remplace()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.remplace_id IS NOT NULL AND NEW.statut IN ('validee', 'signee')
     AND (TG_OP = 'INSERT' OR OLD.statut = 'brouillon') THEN
    UPDATE public.ordonnances SET statut = 'remplacee', remplacee_par = NEW.id
     WHERE id = NEW.remplace_id AND statut IN ('validee', 'signee');
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_ordonnance_remplace ON public.ordonnances;
CREATE TRIGGER trg_ordonnance_remplace
  AFTER INSERT OR UPDATE OF statut ON public.ordonnances
  FOR EACH ROW EXECUTE FUNCTION public.pm_ordonnance_remplace();

-- ── RLS ──────────────────────────────────────────────────────────────────
-- Lecture : la clinique voit tout (brouillons compris) ; le propriétaire,
-- les ordonnances validées (et remplacées, pour l'historique).
DROP POLICY IF EXISTS ordonnances_select ON public.ordonnances;
CREATE POLICY ordonnances_select ON public.ordonnances
  FOR SELECT USING (
    public.pm_acces_compte(pro_uid, coalesce(pro_profile_id::text, ''),
      ARRAY['vet_patients', 'vet_ordonnances', 'vet_cr_rediger', 'vet_cr_valider'])
    OR (statut <> 'brouillon' AND public.can_access_pro_document(
      animal_id, owner_uid, owner_profile_id, pro_uid, pro_profile_id, (auth.jwt() ->> 'sub')))
  );
-- Écriture : préparer = droit ordonnances ou rédaction de CR (ASV) ; la
-- validation est contrôlée par le déclencheur (pm_peut_prescrire).
DROP POLICY IF EXISTS ordonnances_write ON public.ordonnances;
CREATE POLICY ordonnances_write ON public.ordonnances
  FOR ALL USING (public.pm_acces_compte(pro_uid, coalesce(pro_profile_id::text, ''),
    ARRAY['vet_ordonnances', 'vet_cr_rediger', 'vet_cr_valider']))
  WITH CHECK (public.pm_acces_compte(pro_uid, coalesce(pro_profile_id::text, ''),
    ARRAY['vet_ordonnances', 'vet_cr_rediger', 'vet_cr_valider']));

NOTIFY pgrst, 'reload schema';

COMMIT;
