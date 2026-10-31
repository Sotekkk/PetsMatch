-- Éducateur / comportementaliste : « Prestations & tarifs » = source unique
-- des prix (réservation, fiche publique, devis). 31/10/2026.
--
-- 1. prestations_education : statut réservable (actif / en pause), visibilité
--    sur la fiche publique, exception au bilan préalable, conditions de
--    réservation. `actif` reste la suppression douce.
-- 2. Les prix de l'ancienne grille de Mon profil (user_profiles.tarifs_education :
--    cours_individuel, cours_collectif, evaluation, autre) deviennent des cours
--    EN PAUSE et MASQUÉS, à vérifier par le pro — sauf s'il existe déjà un cours
--    du même type au même prix. La grille n'est pas effacée (domicile_supplement
--    y reste : option tarifaire). Idempotent.

ALTER TABLE public.prestations_education
  ADD COLUMN IF NOT EXISTS reservable boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS affiche_public boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS sans_bilan_prealable boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS conditions text;

-- Série de cours collectifs : cours du catalogue, recopié sur chaque
-- occurrence générée (functions/agenda.js generateOccurrencesForSerie).
ALTER TABLE public.cours_collectifs_series
  ADD COLUMN IF NOT EXISTS prestation_id uuid;

COMMENT ON COLUMN public.prestations_education.reservable IS 'false = en pause : ni réservable ni affiché (actif=false = supprimé)';
COMMENT ON COLUMN public.prestations_education.affiche_public IS 'Prix affiché dans les tarifs de la fiche publique';
COMMENT ON COLUMN public.prestations_education.sans_bilan_prealable IS 'Réservable par un nouveau client même si le bilan préalable est obligatoire';
COMMENT ON COLUMN public.prestations_education.bilan_requis IS 'true = ce cours EST un bilan (seul proposé à un nouveau client si education_bilan_requis)';

WITH grille AS (
  SELECT p.id AS profile_id, p.uid, g.key AS cle, (g.value)::text AS valeur
  FROM public.user_profiles p,
       jsonb_each(CASE WHEN jsonb_typeof(p.tarifs_education::jsonb) = 'object' THEN p.tarifs_education::jsonb ELSE '{}'::jsonb END) g
  WHERE p.profile_type = 'education'
    AND g.key IN ('cours_individuel', 'cours_collectif', 'evaluation', 'autre')
    AND jsonb_typeof(g.value) = 'number'
), a_creer AS (
  SELECT g.*, (g.valeur)::numeric AS prix,
         CASE g.cle WHEN 'cours_collectif' THEN 'collectif' ELSE 'individuel' END AS type,
         (g.cle = 'evaluation') AS bilan,
         CASE g.cle WHEN 'cours_individuel' THEN 'Cours individuel'
                    WHEN 'cours_collectif' THEN 'Cours collectif'
                    WHEN 'evaluation' THEN 'Bilan comportemental'
                    ELSE 'Autre prestation' END AS nom,
         CASE g.cle WHEN 'cours_collectif' THEN 90 WHEN 'evaluation' THEN 45 ELSE 60 END AS duree
  FROM grille g
  WHERE (g.valeur)::numeric > 0
)
INSERT INTO public.prestations_education
  (pro_uid, pro_profile_id, nom, description, duree_minutes, prix, bilan_requis, domicile_ok,
   type, capacite_max, reservable, affiche_public, ordre)
SELECT c.uid, c.profile_id, c.nom,
       'Repris de votre ancienne grille de tarifs : vérifiez la durée et la description, puis activez-le.',
       c.duree, c.prix, c.bilan, true, c.type,
       CASE WHEN c.type = 'collectif' THEN 6 END, false, false, 100
FROM a_creer c
WHERE NOT EXISTS (
  SELECT 1 FROM public.prestations_education e
  WHERE e.pro_uid = c.uid
    AND (e.pro_profile_id = c.profile_id OR e.pro_profile_id IS NULL)
    AND e.actif
    AND e.type = c.type AND e.bilan_requis = c.bilan
    AND e.prix = c.prix
);
