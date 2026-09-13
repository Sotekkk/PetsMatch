-- Élargit la contrainte type de plan_templates :
--   - 'alimentaire' et 'toilettage' sont déjà proposés dans le formulaire (app + site)
--     mais échouaient silencieusement à l'enregistrement (bug préexistant, corrigé au
--     passage puisqu'on touche cette contrainte) ;
--   - 'materiel' est une nouvelle catégorie pour les protocoles pet-sitter (garde) :
--     matériel à préparer/utiliser pendant un séjour.
ALTER TABLE plan_templates DROP CONSTRAINT IF EXISTS plan_templates_type_check;
ALTER TABLE plan_templates ADD CONSTRAINT plan_templates_type_check
  CHECK (type IN ('sanitaire', 'nettoyage', 'promenade', 'socialisation', 'alimentaire', 'toilettage', 'materiel'));
