-- Catalogue d'aliments : un membre modifie / supprime les aliments qu'il a
-- ajoutés, tant que l'équipe PetsMatch ne les a pas repris. Une modification
-- par l'admin (/api/admin/aliments, PATCH) pose repris_admin_le ; l'aliment
-- n'est alors plus modifiable que par l'admin.
-- À passer AVANT le déploiement du site (la route admin écrit la colonne).

ALTER TABLE public.marques_aliments ADD COLUMN IF NOT EXISTS repris_admin_le timestamptz;

DROP POLICY IF EXISTS marques_aliments_update_auteur ON public.marques_aliments;
CREATE POLICY marques_aliments_update_auteur ON public.marques_aliments
  FOR UPDATE
  USING (
    (ajoute_par_uid IS NOT NULL AND ajoute_par_uid = (auth.jwt() ->> 'sub') AND repris_admin_le IS NULL)
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  )
  WITH CHECK (
    (ajoute_par_uid IS NOT NULL AND ajoute_par_uid = (auth.jwt() ->> 'sub') AND repris_admin_le IS NULL)
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );

DROP POLICY IF EXISTS marques_aliments_delete_auteur ON public.marques_aliments;
CREATE POLICY marques_aliments_delete_auteur ON public.marques_aliments
  FOR DELETE
  USING (
    (ajoute_par_uid IS NOT NULL AND ajoute_par_uid = (auth.jwt() ->> 'sub') AND repris_admin_le IS NULL)
    OR public.is_admin_uid((auth.jwt() ->> 'sub'))
  );
