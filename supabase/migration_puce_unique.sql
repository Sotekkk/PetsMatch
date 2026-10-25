-- ══════════════════════════════════════════════════════════════════════════
-- Une puce = un animal (fiche unique), y compris pour les fiches créées par
-- un professionnel pour un client sans appli
-- ══════════════════════════════════════════════════════════════════════════
-- Décision du 25/10/2026 :
--  • une puce / un tatouage ne peut identifier qu'une seule fiche ;
--  • un pro (vétérinaire, ostéo, éducateur, toiletteur, pension…) qui saisit
--    une puce déjà créée par un AUTRE pro est rattaché à cette fiche :
--    identité commune, ses propres documents, mais PAS le carnet de santé ni
--    les documents de l'autre pro tant que le propriétaire n'a pas validé
--    (secret professionnel) ;
--  • propriétaire ou éleveur sur PetsMatch : inchangé (demande d'accès).
--
-- 1. pm_puce_norm + index ; trigger : une 2e fiche avec la même puce est
--    refusée (insert, ou puce modifiée). Les doublons déjà en base ne sont
--    pas touchés (à fusionner à la main).
-- 2. animaux.cree_par_pro_profile_id : fiche créée par un pro (patient de
--    clinique, pensionnaire) — garde la trace après l'arrivée du
--    propriétaire. Rempli automatiquement pour statut 'patient_clinique'.
-- 3. pm_puce_existante(puce, profil) : qui détient la fiche
--    (vous / particulier / eleveur / pro) — nom et espèce seulement.
-- 4. animal_access.statut 'identite' + pm_rattacher_fiche_pro : le 2e pro
--    voit l'identité, écrit ses propres documents ; animaux_clients_pro :
--    son client (fichier clients) pour cet animal.
-- 5. Confidentialité (policies RESTRICTIVE) sur les documents des pros
--    (comptes rendus, ordonnances, radios, consultations, séances et points
--    d'ostéo, suivis morpho, éducation, exercices, nouvelles de pension) :
--    sur une fiche créée par un pro, chaque document n'est visible que de
--    l'équipe qui l'a écrit… et du vrai propriétaire une fois arrivé.
--
-- Idempotent. Staging d'abord.
-- ══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── 1. Puce normalisée + unicité ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.pm_puce_norm(p text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT nullif(upper(regexp_replace(coalesce(p, ''), '[^0-9A-Za-z]', '', 'g')), '');
$$;

CREATE INDEX IF NOT EXISTS idx_animaux_puce_norm ON public.animaux (public.pm_puce_norm(identification))
  WHERE length(public.pm_puce_norm(identification)) >= 6;

CREATE OR REPLACE FUNCTION public.pm_controler_puce_unique()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  k text := public.pm_puce_norm(NEW.identification);
BEGIN
  IF k IS NULL OR length(k) < 6 THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND public.pm_puce_norm(OLD.identification) IS NOT DISTINCT FROM k THEN RETURN NEW; END IF;
  IF EXISTS (
    SELECT 1 FROM animaux a
    WHERE length(public.pm_puce_norm(a.identification)) >= 6
      AND public.pm_puce_norm(a.identification) = k
      AND a.id <> NEW.id
  ) THEN
    RAISE EXCEPTION 'La puce % est déjà enregistrée sur PetsMatch pour un autre animal : retrouvez sa fiche plutôt que d''en créer une nouvelle.',
      trim(NEW.identification) USING ERRCODE = '23505', HINT = 'puce_existante';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_animaux_puce_unique ON public.animaux;
CREATE TRIGGER trg_animaux_puce_unique
  BEFORE INSERT OR UPDATE OF identification ON public.animaux
  FOR EACH ROW EXECUTE FUNCTION public.pm_controler_puce_unique();

-- ── 2. Fiche créée par un pro ────────────────────────────────────────────
ALTER TABLE public.animaux ADD COLUMN IF NOT EXISTS cree_par_pro_profile_id uuid REFERENCES user_profiles(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public.pm_marquer_fiche_pro()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.cree_par_pro_profile_id IS NULL AND NEW.statut = 'patient_clinique' THEN
    NEW.cree_par_pro_profile_id := NEW.profile_id;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_animaux_marquer_fiche_pro ON public.animaux;
CREATE TRIGGER trg_animaux_marquer_fiche_pro
  BEFORE INSERT ON public.animaux
  FOR EACH ROW EXECUTE FUNCTION public.pm_marquer_fiche_pro();

-- Rattrapage : patients de clinique, et pensionnaires créés par la pension
-- (uid_eleveur = la pension, sans propriétaire ni propriété de la pension).
UPDATE public.animaux a SET cree_par_pro_profile_id = a.profile_id
 WHERE a.cree_par_pro_profile_id IS NULL AND a.statut = 'patient_clinique' AND a.profile_id IS NOT NULL;
UPDATE public.animaux a SET cree_par_pro_profile_id = pe.pro_profile_id::uuid
  FROM public.pension_entrees pe
 WHERE a.cree_par_pro_profile_id IS NULL AND pe.animal_id = a.id AND pe.pro_uid = a.uid_eleveur
   AND pe.pro_profile_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   AND EXISTS (SELECT 1 FROM user_profiles up WHERE up.id = pe.pro_profile_id::uuid)
   AND a.portee_id IS NULL
   AND NOT EXISTS (SELECT 1 FROM animaux_proprietes p WHERE p.animal_id = a.id AND p.uid_proprio = a.uid_eleveur);

-- Même équipe : la personne elle-même, un cogérant actif ou un employé actif
-- (dans les deux sens).
CREATE OR REPLACE FUNCTION public.pm_meme_equipe(p_a text, p_b text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_a IS NOT NULL AND p_b IS NOT NULL AND (
    p_a = p_b
    OR EXISTS (SELECT 1 FROM elevage_cogerants c WHERE c.statut = 'actif' AND c.date_fin IS NULL
               AND ((c.uid_gerant = p_a AND c.uid_cogerant = p_b) OR (c.uid_gerant = p_b AND c.uid_cogerant = p_a)))
    OR EXISTS (SELECT 1 FROM employes e WHERE e.actif = true
               AND ((e.uid_eleveur = p_a AND e.uid_employe = p_b) OR (e.uid_eleveur = p_b AND e.uid_employe = p_a)))
  );
$$;

-- Vrai propriétaire (particulier, co-propriétaire) — pas le pro qui a créé
-- la fiche technique.
CREATE OR REPLACE FUNCTION public.pm_vrai_proprietaire(p_animal text, p_uid text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM animaux a WHERE a.id = p_animal AND (
      a.uid_proprietaire = p_uid
      OR EXISTS (SELECT 1 FROM animaux_proprietes p WHERE p.animal_id = a.id AND p.uid_proprio = p_uid
                 AND p.date_fin IS NULL AND p.uid_proprio IS DISTINCT FROM a.uid_eleveur)
    )
  );
$$;

-- Document d'un pro masqué pour p_uid : fiche créée par un pro, document
-- écrit par une autre équipe, et p_uid n'en est pas le vrai propriétaire.
CREATE OR REPLACE FUNCTION public.pm_doc_masque(p_animal text, p_auteur text, p_uid text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_animal IS NOT NULL AND p_auteur IS NOT NULL
    AND EXISTS (SELECT 1 FROM animaux a WHERE a.id = p_animal AND a.cree_par_pro_profile_id IS NOT NULL)
    AND NOT public.pm_meme_equipe(p_auteur, p_uid)
    AND NOT public.pm_vrai_proprietaire(p_animal, p_uid);
$$;

-- ── 3. Qui détient la fiche de cette puce ? ──────────────────────────────
CREATE OR REPLACE FUNCTION public.pm_detenteur_animal(p_animal text)
RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN a.uid_proprietaire IS NOT NULL
      OR EXISTS (SELECT 1 FROM animaux_proprietes p WHERE p.animal_id = a.id AND p.date_fin IS NULL
                 AND p.uid_proprio IS DISTINCT FROM a.uid_eleveur) THEN 'particulier'
    WHEN a.cree_par_pro_profile_id IS NOT NULL THEN 'pro'
    ELSE 'eleveur'
  END
  FROM animaux a WHERE a.id = p_animal;
$$;

-- owner_uid / owner_profile_id : à qui adresser une demande d'accès
-- (propriétaire ou éleveur ; vides pour une fiche créée par un pro).
DROP FUNCTION IF EXISTS public.pm_puce_existante(text, uuid);
CREATE OR REPLACE FUNCTION public.pm_puce_existante(p_identification text, p_profile uuid DEFAULT NULL)
RETURNS TABLE (animal_id text, nom text, espece text, detenteur text, a_vous boolean, deja_lie boolean,
               owner_uid text, owner_profile_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT a.id, a.nom, a.espece, public.pm_detenteur_animal(a.id),
         (public.is_animal_owner_or_related(a.id, auth.jwt() ->> 'sub')
            AND public.pm_detenteur_animal(a.id) <> 'pro')
           OR public.pm_vrai_proprietaire(a.id, auth.jwt() ->> 'sub'),
         p_profile IS NOT NULL AND public.pm_gere_clinique(p_profile) AND EXISTS (
           SELECT 1 FROM animal_access aa WHERE aa.animal_id = a.id AND aa.pro_profile_id = p_profile AND aa.statut <> 'revoked'),
         CASE WHEN public.pm_detenteur_animal(a.id) = 'pro' THEN NULL
              ELSE coalesce(pr.uid_proprio, a.uid_proprietaire, a.uid_eleveur) END,
         CASE WHEN public.pm_detenteur_animal(a.id) = 'pro' THEN NULL
              ELSE coalesce(pr.profile_id_proprio, a.profile_id) END
    FROM animaux a
    LEFT JOIN LATERAL (
      SELECT p.uid_proprio, p.profile_id_proprio FROM animaux_proprietes p
       WHERE p.animal_id = a.id AND p.date_fin IS NULL
       ORDER BY p.date_debut DESC NULLS LAST LIMIT 1
    ) pr ON true
   WHERE (auth.jwt() ->> 'sub') IS NOT NULL
     AND length(public.pm_puce_norm(p_identification)) >= 6
     AND length(public.pm_puce_norm(a.identification)) >= 6
     AND public.pm_puce_norm(a.identification) = public.pm_puce_norm(p_identification)
   LIMIT 3;
$$;
GRANT EXECUTE ON FUNCTION public.pm_puce_existante(text, uuid) TO anon, authenticated;

-- ── 4. Rattachement d'un 2e pro (identité seule) ─────────────────────────
ALTER TABLE public.animal_access DROP CONSTRAINT IF EXISTS animal_access_statut_check;
ALTER TABLE public.animal_access ADD CONSTRAINT animal_access_statut_check
  CHECK (statut = ANY (ARRAY['pending', 'active', 'active_write', 'write_requested', 'revoked', 'identite']));

CREATE TABLE IF NOT EXISTS public.animaux_clients_pro (
  animal_id      text NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  pro_profile_id uuid NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  client_id      uuid REFERENCES clients_clinique(id) ON DELETE SET NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (animal_id, pro_profile_id)
);
CREATE INDEX IF NOT EXISTS idx_animaux_clients_pro_client ON public.animaux_clients_pro (client_id);
ALTER TABLE public.animaux_clients_pro ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS animaux_clients_pro_equipe ON public.animaux_clients_pro;
CREATE POLICY animaux_clients_pro_equipe ON public.animaux_clients_pro
  FOR ALL TO anon, authenticated
  USING (public.pm_gere_clinique(pro_profile_id) OR public.pm_employe_profil(pro_profile_id, ARRAY['vet_patients', 'vet_agenda']))
  WITH CHECK (public.pm_gere_clinique(pro_profile_id) OR public.pm_employe_profil(pro_profile_id, ARRAY['vet_patients', 'vet_agenda']));
GRANT SELECT, INSERT, UPDATE, DELETE ON public.animaux_clients_pro TO anon, authenticated;

-- Accès « identité seule » (2e pro sur une fiche créée par un autre pro).
CREATE OR REPLACE FUNCTION public.pm_acces_identite(p_animal text, p_uid text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM animal_access aa JOIN user_profiles up ON up.id = aa.pro_profile_id
    WHERE aa.animal_id = p_animal AND aa.statut = 'identite'
      AND (up.uid = p_uid OR public.pm_meme_equipe(up.uid, p_uid))
  );
$$;

CREATE OR REPLACE FUNCTION public.pm_rattacher_fiche_pro(
  p_profile uuid, p_animal text, p_client_id uuid DEFAULT NULL, p_client jsonb DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_client uuid := p_client_id;
BEGIN
  IF NOT (public.pm_gere_clinique(p_profile) OR public.pm_employe_profil(p_profile, ARRAY['vet_patients', 'vet_agenda'])) THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM animaux WHERE id = p_animal) THEN
    RAISE EXCEPTION 'Animal introuvable.' USING ERRCODE = 'P0001';
  END IF;
  IF public.pm_detenteur_animal(p_animal) <> 'pro' THEN
    RAISE EXCEPTION 'Cet animal a un propriétaire sur PetsMatch : demandez-lui l''accès à son carnet.' USING ERRCODE = 'P0001';
  END IF;

  IF v_client IS NULL AND coalesce(trim(p_client ->> 'nom'), '') <> '' THEN
    INSERT INTO clients_clinique (clinique_profile_id, nom, prenom, telephone, email, adresse, code_postal, ville)
    VALUES (p_profile, trim(p_client ->> 'nom'), nullif(trim(p_client ->> 'prenom'), ''),
            nullif(trim(p_client ->> 'telephone'), ''), nullif(lower(trim(p_client ->> 'email')), ''),
            nullif(trim(p_client ->> 'adresse'), ''), nullif(trim(p_client ->> 'code_postal'), ''),
            nullif(trim(p_client ->> 'ville'), ''))
    RETURNING id INTO v_client;
  ELSIF v_client IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM clients_clinique c WHERE c.id = v_client AND c.clinique_profile_id = p_profile) THEN
    RAISE EXCEPTION 'Client inconnu pour ce professionnel.' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO animaux_clients_pro (animal_id, pro_profile_id, client_id)
  VALUES (p_animal, p_profile, v_client)
  ON CONFLICT (animal_id, pro_profile_id)
    DO UPDATE SET client_id = coalesce(EXCLUDED.client_id, animaux_clients_pro.client_id);

  INSERT INTO animal_access (animal_id, pro_profile_id, granted_by_profile_id, permissions, statut, granted_at)
  VALUES (p_animal, p_profile, p_profile, ARRAY['read_basic'], 'identite', now())
  ON CONFLICT (animal_id, pro_profile_id) DO UPDATE
    SET statut = CASE WHEN animal_access.statut IN ('active', 'active_write', 'write_requested') THEN animal_access.statut ELSE 'identite' END,
        revoked_at = NULL,
        granted_at = coalesce(animal_access.granted_at, now());
  RETURN p_animal;
END $$;
GRANT EXECUTE ON FUNCTION public.pm_rattacher_fiche_pro(uuid, text, uuid, jsonb) TO authenticated;

-- Le 2e pro lit la fiche (identité)…
DROP POLICY IF EXISTS animaux_select_identite ON public.animaux;
CREATE POLICY animaux_select_identite ON public.animaux
  FOR SELECT TO anon, authenticated USING (public.pm_acces_identite(id, auth.jwt() ->> 'sub'));

-- … et écrit ses propres séances d'ostéo / suivis morpho (pas le carnet :
-- has_animal_access ignore le statut 'identite').
CREATE OR REPLACE FUNCTION public.can_access_animal_morpho(p_animal_id text, p_uid text, p_require_write boolean DEFAULT false)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.is_animal_owner_or_cogerant(p_animal_id, p_uid)
    OR public.has_animal_access(p_animal_id, p_uid, p_require_write)
    OR public.pm_acces_identite(p_animal_id, p_uid);
$$;

-- Radios : l'auteur relit les siennes (il n'a pas l'accès au carnet).
DROP POLICY IF EXISTS radios_select_auteur ON public.radios;
CREATE POLICY radios_select_auteur ON public.radios
  FOR SELECT TO anon, authenticated USING (vet_id = (auth.jwt() ->> 'sub'));

-- ── 5. Confidentialité des documents des pros (RESTRICTIVE) ──────────────
DO $$
DECLARE
  t record;
BEGIN
  FOR t IN SELECT * FROM (VALUES
    ('comptes_rendus', 'pro_uid'), ('ordonnances', 'pro_uid'), ('radios', 'vet_id'),
    ('vet_consultations', 'vet_id'), ('seances_osteo', 'pro_uid'), ('points_osteo', 'pro_uid'),
    ('suivis_morpho', 'uid_auteur'), ('education_attestations', 'pro_uid'), ('education_objectifs', 'pro_uid'),
    ('education_progression', 'pro_uid'), ('exercices_attribues', 'pro_uid'), ('pension_updates', 'pro_uid')
  ) AS v(tab, auteur) LOOP
    IF to_regclass('public.' || t.tab) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t.tab || '_confidentiel_pro', t.tab);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I AS RESTRICTIVE FOR ALL TO anon, authenticated '
      'USING (NOT public.pm_doc_masque(animal_id, %I, auth.jwt() ->> ''sub'')) '
      'WITH CHECK (NOT public.pm_doc_masque(animal_id, %I, auth.jwt() ->> ''sub''))',
      t.tab || '_confidentiel_pro', t.tab, t.auteur, t.auteur);
  END LOOP;
END $$;

-- Le pro qui a créé la fiche ne voit pas que d'autres pros y sont rattachés.
DROP POLICY IF EXISTS animal_access_identite_confidentiel ON public.animal_access;
CREATE POLICY animal_access_identite_confidentiel ON public.animal_access
  AS RESTRICTIVE FOR SELECT TO anon, authenticated
  USING (
    statut <> 'identite'
    OR public.pm_vrai_proprietaire(animal_id, auth.jwt() ->> 'sub')
    OR EXISTS (SELECT 1 FROM user_profiles up WHERE up.id = pro_profile_id
               AND public.pm_meme_equipe(up.uid, auth.jwt() ->> 'sub'))
    OR public.pm_employe_profil(pro_profile_id, ARRAY['vet_patients'])
  );

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ══════════════════════════════════════════════════════════════════════════
-- Doublons existants (à fusionner à la main, rien n'est supprimé ici) :
--   SELECT public.pm_puce_norm(identification) AS puce, count(*), string_agg(id || ' ' || coalesce(nom, ''), ' | ')
--     FROM animaux WHERE length(public.pm_puce_norm(identification)) >= 6
--    GROUP BY 1 HAVING count(*) > 1;
-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK
-- ══════════════════════════════════════════════════════════════════════════
-- DROP TRIGGER IF EXISTS trg_animaux_puce_unique ON public.animaux;
-- DROP TRIGGER IF EXISTS trg_animaux_marquer_fiche_pro ON public.animaux;
-- DROP POLICY IF EXISTS animaux_select_identite ON public.animaux;
-- DROP POLICY IF EXISTS radios_select_auteur ON public.radios;
-- DROP POLICY IF EXISTS animal_access_identite_confidentiel ON public.animal_access;
-- (et les policies *_confidentiel_pro des 12 tables ; can_access_animal_morpho :
--  retirer « OR pm_acces_identite(...) » ; colonnes et table conservées)
