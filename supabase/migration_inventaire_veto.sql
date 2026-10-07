-- ════════════════════════════════════════════════════════════════════════
-- Inventaire & pharmacie vétérinaire (formules Avancé et Clinique).
-- Réutilise inventaire_items / inventaire_mouvements (module élevage) avec
-- les informations qu'une clinique doit suivre :
--   • lot (traçabilité des médicaments délivrés) ;
--   • date de péremption (retrait des produits périmés, inventaire annuel) ;
--   • froid : conservation +2/+8 °C (vaccins) ;
--   • stupéfiant : registre des entrées / sorties obligatoire (mouvement
--     motivé, stock après mouvement, conservation 10 ans) — tenu à partir
--     de inventaire_mouvements ;
--   • prix de vente (produits vendus au comptoir : croquettes, antiparasitaires…).
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════

ALTER TABLE inventaire_items
  ADD COLUMN IF NOT EXISTS lot             text,
  ADD COLUMN IF NOT EXISTS date_peremption date,
  ADD COLUMN IF NOT EXISTS prix_vente      numeric,
  ADD COLUMN IF NOT EXISTS froid           boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS stupefiant      boolean NOT NULL DEFAULT false;

-- Stock restant après chaque mouvement (registre des stupéfiants).
ALTER TABLE inventaire_mouvements ADD COLUMN IF NOT EXISTS stock_apres numeric;

-- Grille des formules vétérinaires : nouveautés affichées dans « Mon abonnement ».
UPDATE plans_tarifaires
   SET features = coalesce(features, '{}'::jsonb) || '{"hasEquipeAsv": true, "hasInventaire": true}'::jsonb
 WHERE profil_type = 'veterinaire' AND plan_code = 'avance';
UPDATE plans_tarifaires
   SET features = coalesce(features, '{}'::jsonb) || '{"hasEquipeAsv": true, "hasInventaire": true, "hasSallesRdv": true}'::jsonb
 WHERE profil_type = 'veterinaire' AND plan_code = 'clinique';
