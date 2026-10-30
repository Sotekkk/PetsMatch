-- Signature manuscrite du praticien sur les PDF téléchargés par le
-- propriétaire (compte rendu vétérinaire, compte rendu de séance ostéo).
-- signatures_pro reste lisible par son seul propriétaire : ces fonctions
-- renvoient UNIQUEMENT la signature de l'auteur d'un document validé /
-- finalisé, et seulement au propriétaire (ou co-propriétaire actif) de
-- l'animal concerné, ou à l'auteur lui-même. Aucune copie de la signature.

CREATE OR REPLACE FUNCTION public.pm_peut_voir_signature_animal(p_animal_id text, p_auteur text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT coalesce(auth.jwt() ->> 'sub', '') <> '' AND (
    (auth.jwt() ->> 'sub') = p_auteur
    OR EXISTS (SELECT 1 FROM animaux a WHERE a.id = p_animal_id AND a.uid_proprietaire = (auth.jwt() ->> 'sub'))
    OR EXISTS (SELECT 1 FROM animaux_proprietes ap
               WHERE ap.animal_id = p_animal_id AND ap.uid_proprio = (auth.jwt() ->> 'sub')
                 AND coalesce(ap.statut, 'actif') = 'actif' AND ap.date_fin IS NULL)
  );
$$;
REVOKE ALL ON FUNCTION public.pm_peut_voir_signature_animal(text, text) FROM PUBLIC;

-- Compte rendu vétérinaire validé : signature du vétérinaire qui l'a validé
-- (à défaut le rédacteur, puis le titulaire).
CREATE OR REPLACE FUNCTION public.pm_signature_compte_rendu(p_cr_id uuid)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_animal text;
  v_auteur text;
BEGIN
  SELECT cr.animal_id, coalesce(cr.valide_par_uid, cr.redige_par_uid, cr.pro_uid)
    INTO v_animal, v_auteur
    FROM comptes_rendus cr
   WHERE cr.id = p_cr_id AND coalesce(cr.statut, 'valide') = 'valide';
  IF v_auteur IS NULL OR NOT public.pm_peut_voir_signature_animal(v_animal, v_auteur) THEN
    RETURN NULL;
  END IF;
  RETURN (SELECT s.signature FROM signatures_pro s WHERE s.uid = v_auteur);
END;
$$;

-- Compte rendu de séance (ostéo / kiné) finalisé : signature de son auteur.
CREATE OR REPLACE FUNCTION public.pm_signature_seance(p_suivi_id uuid)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_animal text;
  v_auteur text;
BEGIN
  SELECT sm.animal_id, sm.uid_auteur INTO v_animal, v_auteur
    FROM suivis_morpho sm
   -- statut lu via jsonb : colonne absente des bases pas encore migrées (= finalisé).
   WHERE sm.id = p_suivi_id AND coalesce(to_jsonb(sm) ->> 'statut', 'finalise') = 'finalise';
  IF v_auteur IS NULL OR v_animal IS NULL OR NOT public.pm_peut_voir_signature_animal(v_animal, v_auteur) THEN
    RETURN NULL;
  END IF;
  RETURN (SELECT s.signature FROM signatures_pro s WHERE s.uid = v_auteur);
END;
$$;

REVOKE ALL ON FUNCTION public.pm_signature_compte_rendu(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.pm_signature_seance(uuid) FROM PUBLIC;
-- Requêtes Firebase en rôle anon (jeton vérifié côté Supabase).
GRANT EXECUTE ON FUNCTION public.pm_signature_compte_rendu(uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pm_signature_seance(uuid) TO anon, authenticated;
