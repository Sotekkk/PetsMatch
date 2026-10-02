-- ════════════════════════════════════════════════════════════════════════
-- Stockage — phase 2b : documents sensibles en PRIVÉ, liens temporaires.
--
-- Les buckets `documents` (ordonnances, cessions, radios, comptes rendus,
-- statuts / arrêtés / KBIS…) et `contrats` étaient publics : quiconque
-- avait (ou devinait) le lien lisait le fichier, sans compte.
-- Désormais privés : les liens enregistrés en base restent inchangés, mais
-- l'appli et le site les ouvrent via l'Edge Function `lien-document`, qui
-- vérifie que l'appelant voit une fiche référençant le document (mêmes
-- règles que les tables) puis renvoie un lien valable 10 minutes.
--
-- ⚠ Ordre : Edge Function lien-document déployée + appli / site qui
--   l'utilisent, PUIS cette migration (sinon les documents ne s'ouvrent
--   plus dans les anciennes versions).
-- Retour arrière : UPDATE storage.buckets SET public = true
--                  WHERE id IN ('documents','contrats');
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

-- Qui a déposé ce fichier ? (utilisé par lien-document, service uniquement)
CREATE OR REPLACE FUNCTION public.pm_proprio_fichier(p_bucket text, p_nom text)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT coalesce(nullif(o.owner_id, ''),
                  -- anciens fichiers sans owner_id : dossier = uid du déposant
                  (SELECT f FROM unnest(storage.foldername(o.name)) f
                   WHERE f ~ '^[A-Za-z0-9]{28}$' LIMIT 1))
  FROM storage.objects o
  WHERE o.bucket_id = p_bucket AND o.name = p_nom;
$$;
REVOKE EXECUTE ON FUNCTION public.pm_proprio_fichier(text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pm_proprio_fichier(text, text) TO service_role;

UPDATE storage.buckets SET public = false WHERE id IN ('documents', 'contrats');

COMMIT;
