-- ════════════════════════════════════════════════════════════════════════
-- Stockage — phase 2a : chacun ne liste / remplace / supprime QUE ses
-- propres fichiers.
--
-- ⚠ À appliquer APRÈS le redéploiement du site (le site en ligne au 30/09
--   n'envoie pas le jeton Firebase à Supabase) et avec une build appli
--   contenant les noms de fichiers uniques (groupes, morpho, balades).
--
-- Après la phase 1, tout utilisateur connecté pouvait encore :
--   • lister tous les fichiers de tous les buckets (ordonnances, radios,
--     KBIS, factures… servis ensuite par leur URL publique) ;
--   • écraser n'importe quel fichier existant (upsert), y compris les PDF
--     de factures archivés (inaltérabilité).
--
-- « Ses fichiers » =
--   • owner_id = uid Firebase : Supabase le renseigne tout seul au dépôt
--     depuis que l'appli (22/09) et le site envoient le jeton ;
--   • fichiers plus anciens sans owner_id : ceux dont un dossier du chemin
--     est son uid (profiles/<uid>/photo.jpg, documents/<uid>/kbis.pdf…),
--     pour que les remplacements à nom fixe continuent de marcher.
--
-- Inchangé :
--   • déposer un fichier NEUF : tout utilisateur connecté (les employés
--     déposent dans les dossiers de leur employeur) ;
--   • exceptions sans connexion de la phase 1 (contrat « Finaliser »,
--     photo d'inscription) ;
--   • affichage par URL publique.
-- Ajouté :
--   • suppression de ses propres fichiers (photos de balade, images de
--     chat qu'on a envoyées) : échouaient en silence faute de policy ;
--   • influencer-proofs : dépôt des preuves (aucune policy → cassé).
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.pm_storage_est_mon_fichier(p_owner_id text, p_name text)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path = ''
AS $$
  SELECT (auth.jwt() ->> 'sub') IS NOT NULL
     AND (
       p_owner_id = (auth.jwt() ->> 'sub')
       OR (coalesce(p_owner_id, '') = ''
           AND (auth.jwt() ->> 'sub') = ANY (storage.foldername(p_name)))
     );
$$;
GRANT EXECUTE ON FUNCTION public.pm_storage_est_mon_fichier(text, text) TO anon, authenticated;

-- Lecture via l'API (liste, upsert, remove) : ses fichiers.
DROP POLICY IF EXISTS storage_select_connecte ON storage.objects;
DROP POLICY IF EXISTS storage_select_mes_fichiers ON storage.objects;
CREATE POLICY storage_select_mes_fichiers ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (
    bucket_id IN ('documents', 'media', 'petsmatch', 'promenades-photos',
                  'social', 'stories', 'story_music', 'influencer-proofs')
    AND public.pm_storage_est_mon_fichier(owner_id, name)
  );

-- Dépôt d'un fichier neuf : connecté (+ influencer-proofs).
DROP POLICY IF EXISTS storage_insert_connecte ON storage.objects;
CREATE POLICY storage_insert_connecte ON storage.objects
  FOR INSERT TO anon, authenticated
  WITH CHECK (
    bucket_id IN ('documents', 'media', 'petsmatch', 'promenades-photos',
                  'social', 'stories', 'story_music', 'influencer-proofs')
    AND auth.jwt() ->> 'sub' IS NOT NULL
  );

-- Remplacement (upsert) : ses fichiers.
DROP POLICY IF EXISTS storage_update_connecte ON storage.objects;
DROP POLICY IF EXISTS storage_update_mes_fichiers ON storage.objects;
CREATE POLICY storage_update_mes_fichiers ON storage.objects
  FOR UPDATE TO anon, authenticated
  USING (
    bucket_id IN ('documents', 'media', 'petsmatch', 'social', 'influencer-proofs')
    AND public.pm_storage_est_mon_fichier(owner_id, name)
  )
  WITH CHECK (
    bucket_id IN ('documents', 'media', 'petsmatch', 'social', 'influencer-proofs')
    AND auth.jwt() ->> 'sub' IS NOT NULL
  );

-- Suppression : ses fichiers (en plus des stories par leur auteur).
DROP POLICY IF EXISTS storage_delete_mes_fichiers ON storage.objects;
CREATE POLICY storage_delete_mes_fichiers ON storage.objects
  FOR DELETE TO anon, authenticated
  USING (
    bucket_id IN ('documents', 'media', 'petsmatch', 'promenades-photos',
                  'social', 'influencer-proofs')
    AND public.pm_storage_est_mon_fichier(owner_id, name)
  );

-- contrats : la fenêtre « Finaliser » (lib/contrat-vente.ts) dépose
-- désormais avec le jeton de l'éleveur (demandé à la page elevage/contrat).
-- Fin de l'exception anonyme de la phase 1 ; noms de fichiers inchangés.
DROP POLICY IF EXISTS storage_insert_contrat_html ON storage.objects;
DROP POLICY IF EXISTS storage_select_contrat_recent ON storage.objects;
DROP POLICY IF EXISTS storage_update_contrat_recent ON storage.objects;
CREATE POLICY storage_insert_contrat_html ON storage.objects
  FOR INSERT TO anon, authenticated
  WITH CHECK (
    bucket_id = 'contrats'
    AND name ~ '^(contrat|certificat_cession)_[A-Za-z0-9-]+_[0-9]{13}\.html$'
    AND auth.jwt() ->> 'sub' IS NOT NULL
  );
DROP POLICY IF EXISTS storage_select_contrat_mes_fichiers ON storage.objects;
CREATE POLICY storage_select_contrat_mes_fichiers ON storage.objects
  FOR SELECT TO anon, authenticated
  USING (bucket_id = 'contrats' AND public.pm_storage_est_mon_fichier(owner_id, name));
DROP POLICY IF EXISTS storage_update_contrat_mes_fichiers ON storage.objects;
CREATE POLICY storage_update_contrat_mes_fichiers ON storage.objects
  FOR UPDATE TO anon, authenticated
  USING (bucket_id = 'contrats' AND public.pm_storage_est_mon_fichier(owner_id, name))
  WITH CHECK (bucket_id = 'contrats' AND auth.jwt() ->> 'sub' IS NOT NULL);

COMMIT;
