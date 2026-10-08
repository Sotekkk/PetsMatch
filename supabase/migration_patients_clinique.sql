-- ════════════════════════════════════════════════════════════════════════
-- Clinique vétérinaire — patients créés par la clinique (propriétaire hors
-- appli). ÉTAPE 1 : fichier clients + fiche patient.
--
-- Décisions (08/10/2026) :
--   • La clinique crée une fiche animal liée à un CLIENT de son fichier
--     (clients_clinique), même si le propriétaire n'a pas PetsMatch : même
--     fiche, mêmes onglets (carnet, CR, ordonnances…) que les autres patients.
--   • Anti-doublon avant création : n° de puce (pm_patient_existant) et
--     compte PetsMatch (pm_trouver_utilisateur, côté appli / site).
--   • L'animal appartient techniquement au compte de la clinique
--     (animaux.uid_eleveur NOT NULL), profil = profil clinique, statut
--     'patient_clinique' (exclu des listes d'animaux de l'éleveur) ; la
--     clinique y accède par animal_access (comme tout patient).
--   • Étape 2 (à venir) : quand le propriétaire arrive sur PetsMatch, il
--     valide lui-même le rattachement (clients_clinique.uid_lie).
--
-- Multi-profil : tout est scopé au profil clinique.
-- Idempotent. Staging d'abord.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.clients_clinique (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  clinique_profile_id  uuid NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  nom                  text NOT NULL,
  prenom               text,
  telephone            text,
  email                text,
  adresse              text,
  code_postal          text,
  ville                text,
  notes                text,
  -- Étape 2 : compte PetsMatch rattaché (validé par le propriétaire).
  uid_lie              text,
  profile_lie_id       uuid REFERENCES user_profiles(id) ON DELETE SET NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_clients_clinique_profil ON public.clients_clinique (clinique_profile_id, nom);
ALTER TABLE public.clients_clinique ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS clients_clinique_equipe ON public.clients_clinique;
CREATE POLICY clients_clinique_equipe ON public.clients_clinique
  FOR ALL TO anon, authenticated
  USING (public.pm_gere_clinique(clinique_profile_id)
    OR public.pm_employe_profil(clinique_profile_id, ARRAY['vet_patients', 'vet_agenda']))
  WITH CHECK (public.pm_gere_clinique(clinique_profile_id)
    OR public.pm_employe_profil(clinique_profile_id, ARRAY['vet_patients', 'vet_agenda']));

ALTER TABLE public.animaux ADD COLUMN IF NOT EXISTS client_clinique_id uuid REFERENCES clients_clinique(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS idx_animaux_client_clinique ON public.animaux (client_clinique_id);

-- ── Création d'un patient (client existant ou nouveau + animal) ──────────
-- p_client_id : client existant du fichier, sinon p_client crée le client.
-- p_animal : {nom, espece, race, sexe, date_naissance, identification, poids, couleur}
CREATE OR REPLACE FUNCTION public.pm_creer_patient_clinique(
  p_clinique uuid, p_client_id uuid, p_client jsonb, p_animal jsonb)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid_clinique text;
  v_client uuid := p_client_id;
  v_animal text := gen_random_uuid()::text;
BEGIN
  IF NOT (public.pm_gere_clinique(p_clinique)
          OR public.pm_employe_profil(p_clinique, ARRAY['vet_patients', 'vet_agenda'])) THEN
    RAISE EXCEPTION 'Accès refusé' USING ERRCODE = '42501';
  END IF;
  SELECT up.uid INTO v_uid_clinique FROM user_profiles up WHERE up.id = p_clinique;
  IF v_uid_clinique IS NULL THEN RAISE EXCEPTION 'Clinique introuvable'; END IF;
  IF coalesce(trim(p_animal ->> 'nom'), '') = '' THEN
    RAISE EXCEPTION 'Le nom de l''animal est obligatoire.' USING ERRCODE = 'P0001';
  END IF;

  IF v_client IS NULL THEN
    IF coalesce(trim(p_client ->> 'nom'), '') = '' THEN
      RAISE EXCEPTION 'Le nom du propriétaire est obligatoire.' USING ERRCODE = 'P0001';
    END IF;
    INSERT INTO clients_clinique (clinique_profile_id, nom, prenom, telephone, email, adresse, code_postal, ville, notes)
    VALUES (p_clinique, trim(p_client ->> 'nom'), nullif(trim(p_client ->> 'prenom'), ''),
            nullif(trim(p_client ->> 'telephone'), ''), nullif(lower(trim(p_client ->> 'email')), ''),
            nullif(trim(p_client ->> 'adresse'), ''), nullif(trim(p_client ->> 'code_postal'), ''),
            nullif(trim(p_client ->> 'ville'), ''), nullif(trim(p_client ->> 'notes'), ''))
    RETURNING id INTO v_client;
  ELSIF NOT EXISTS (SELECT 1 FROM clients_clinique c WHERE c.id = v_client AND c.clinique_profile_id = p_clinique) THEN
    RAISE EXCEPTION 'Client inconnu pour cette clinique.' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO animaux (id, uid_eleveur, profile_id, statut, client_clinique_id,
                       nom, espece, race, sexe, date_naissance, identification, poids, couleur)
  VALUES (v_animal, v_uid_clinique, p_clinique, 'patient_clinique', v_client,
          trim(p_animal ->> 'nom'), nullif(p_animal ->> 'espece', ''), nullif(trim(p_animal ->> 'race'), ''),
          nullif(p_animal ->> 'sexe', ''), nullif(p_animal ->> 'date_naissance', '')::date,
          nullif(trim(p_animal ->> 'identification'), ''), nullif(trim(p_animal ->> 'poids'), ''),
          nullif(trim(p_animal ->> 'couleur'), ''));

  INSERT INTO animal_access (animal_id, pro_profile_id, granted_by_profile_id, permissions, statut, granted_at)
  VALUES (v_animal, p_clinique, p_clinique, ARRAY['read_basic', 'read_health', 'write_health'], 'active', now())
  ON CONFLICT (animal_id, pro_profile_id) DO UPDATE SET statut = 'active';

  RETURN v_animal;
END;
$$;
GRANT EXECUTE ON FUNCTION public.pm_creer_patient_clinique(uuid, uuid, jsonb, jsonb) TO authenticated;

-- ── Anti-doublon : un animal porte-t-il déjà ce n° de puce / tatouage ? ──
-- Renvoie le strict nécessaire pour proposer une demande d'accès au carnet.
CREATE OR REPLACE FUNCTION public.pm_patient_existant(p_clinique uuid, p_identification text)
RETURNS TABLE (animal_id text, nom text, espece text, owner_uid text, deja_patient boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a.id, a.nom, a.espece, coalesce(a.uid_proprietaire, a.uid_eleveur),
         EXISTS (SELECT 1 FROM animal_access aa WHERE aa.animal_id = a.id
                   AND aa.pro_profile_id = p_clinique AND aa.statut <> 'revoked')
    FROM animaux a
   WHERE length(trim(coalesce(p_identification, ''))) >= 6
     AND upper(replace(a.identification, ' ', '')) = upper(replace(trim(p_identification), ' ', ''))
     AND (public.pm_gere_clinique(p_clinique)
          OR public.pm_employe_profil(p_clinique, ARRAY['vet_patients', 'vet_agenda']))
   LIMIT 3;
$$;
GRANT EXECUTE ON FUNCTION public.pm_patient_existant(uuid, text) TO authenticated;

COMMIT;
