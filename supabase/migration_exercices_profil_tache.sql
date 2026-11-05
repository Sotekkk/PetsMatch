-- Exercices d'éducation : toujours rattachés au profil du propriétaire, et tâche du
-- jour dans « Mon quotidien » dès l'attribution (pas seulement au rappel du lendemain).
--   1. owner_profile_id renseigné à l'insertion s'il manque (site + appli) : profil de la
--      propriété en cours de l'animal, sinon profil principal du propriétaire.
--   2. Tâche du jour créée à l'attribution (notes « exercice:<id> », même forme que
--      sendExerciceReminders, qui ne la recrée pas). Fiche créée par un pro : jamais au pro.
--   3. Rattrapage des exercices en cours : profil, et tâche du jour manquante.
-- Idempotent.

CREATE OR REPLACE FUNCTION public.pm_exercice_profil_proprietaire(p_animal text, p_owner text)
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(
    (SELECT ap.profile_id_proprio FROM animaux_proprietes ap
      WHERE ap.animal_id = p_animal AND ap.uid_proprio = p_owner AND ap.date_fin IS NULL AND ap.statut = 'actif'
        AND ap.profile_id_proprio IS NOT NULL
      ORDER BY (ap.role_proprio = 'principal') DESC NULLS LAST LIMIT 1),
    (SELECT up.id FROM user_profiles up WHERE up.uid = p_owner AND up.is_main LIMIT 1));
$$;

-- Le pro qui a créé la fiche n'est pas le propriétaire (voir animal_destinataire.js).
CREATE OR REPLACE FUNCTION public.pm_exercice_vrai_proprietaire(p_animal text, p_owner text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_owner IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM animaux a
     WHERE a.id = p_animal AND a.uid_eleveur = p_owner
       AND (a.cree_par_pro_profile_id IS NOT NULL OR a.client_clinique_id IS NOT NULL));
$$;

CREATE OR REPLACE FUNCTION public.pm_exercice_tache_du_jour(p_ex public.exercices_attribues)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_jour date := (now() AT TIME ZONE 'Europe/Paris')::date;
BEGIN
  IF NOT p_ex.rappels_actifs OR p_ex.rappels_mutes OR p_ex.statut NOT IN ('a_faire', 'en_cours')
     OR (p_ex.echeance IS NOT NULL AND p_ex.echeance < v_jour)
     OR NOT public.pm_exercice_vrai_proprietaire(p_ex.animal_id, p_ex.owner_uid) THEN
    RETURN;
  END IF;
  IF EXISTS (SELECT 1 FROM taches_elevage t WHERE t.notes = 'exercice:' || p_ex.id::text AND t.date = v_jour) THEN
    RETURN;
  END IF;
  INSERT INTO taches_elevage (titre, animal_id, animal_nom, uid_eleveur, date, statut, profil_source, notes, profile_id)
  VALUES ('Exercice : ' || coalesce(NULLIF(p_ex.titre_snapshot, ''), 'un exercice'), p_ex.animal_id,
          (SELECT a.nom FROM animaux a WHERE a.id = p_ex.animal_id), p_ex.owner_uid, v_jour, 'a_faire', 'particulier',
          'exercice:' || p_ex.id::text, p_ex.owner_profile_id);
END $$;
REVOKE ALL ON FUNCTION public.pm_exercice_tache_du_jour(public.exercices_attribues) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.trg_exercice_profil() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.owner_profile_id IS NULL AND public.pm_exercice_vrai_proprietaire(NEW.animal_id, NEW.owner_uid) THEN
    NEW.owner_profile_id := public.pm_exercice_profil_proprietaire(NEW.animal_id, NEW.owner_uid);
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.trg_exercice_tache() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.pm_exercice_tache_du_jour(NEW);
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_exercice_profil ON public.exercices_attribues;
CREATE TRIGGER trg_exercice_profil BEFORE INSERT ON public.exercices_attribues
  FOR EACH ROW EXECUTE FUNCTION public.trg_exercice_profil();
DROP TRIGGER IF EXISTS trg_exercice_tache ON public.exercices_attribues;
CREATE TRIGGER trg_exercice_tache AFTER INSERT ON public.exercices_attribues
  FOR EACH ROW EXECUTE FUNCTION public.trg_exercice_tache();

-- Rattrapage : exercices en cours sans profil, puis tâche du jour manquante.
UPDATE public.exercices_attribues e
   SET owner_profile_id = public.pm_exercice_profil_proprietaire(e.animal_id, e.owner_uid)
 WHERE e.owner_profile_id IS NULL AND e.statut IN ('a_faire', 'en_cours')
   AND public.pm_exercice_vrai_proprietaire(e.animal_id, e.owner_uid);
DO $$
DECLARE r public.exercices_attribues;
BEGIN
  FOR r IN SELECT * FROM public.exercices_attribues WHERE statut IN ('a_faire', 'en_cours') LOOP
    PERFORM public.pm_exercice_tache_du_jour(r);
  END LOOP;
END $$;
-- Tâches d'exercice déjà créées sans profil : rattachées au profil de l'exercice.
UPDATE public.taches_elevage t SET profile_id = e.owner_profile_id
  FROM public.exercices_attribues e
 WHERE t.notes = 'exercice:' || e.id::text AND t.profile_id IS NULL AND e.owner_profile_id IS NOT NULL;
NOTIFY pgrst, 'reload schema';
