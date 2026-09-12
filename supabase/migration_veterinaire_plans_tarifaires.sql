-- ============================================================
-- PetsMatch — Formules d'abonnement Vétérinaire
-- (Découverte / Avancé / Clinique), Spec §8.1.
-- Alimente plans_tarifaires (déjà générique, éditable depuis l'admin
-- web sans déploiement — voir /admin onglet Tarification).
-- Différenciateur cœur : la formule FREE reste à l'annuaire basique
-- (lecture via token 72h) ; Avancé débloque l'accès lecture permanent
-- et l'écriture au carnet santé ; Clinique ajoute le multi-praticiens
-- (5 max) et l'export CSV pour les logiciels vétérinaires.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

INSERT INTO plans_tarifaires (profil_type, plan_code, label, prix_mensuel, prix_annuel, max_annonces, duree_annonce_jours, auto_publish, features, actif)
VALUES
  ('veterinaire', 'free', 'Découverte', 0, 0, 0, 30, true,
   '{"hasAccesPermanent": false, "hasEcritureCarnetSante": false, "hasRappelsPush": false, "hasMultiPraticiens": false, "maxPraticiens": 1, "hasExportCsv": false}'::jsonb,
   true),
  ('veterinaire', 'avance', 'Avancé', 29, 290, 0, 30, true,
   '{"hasAccesPermanent": true, "hasEcritureCarnetSante": true, "hasRappelsPush": true, "hasMultiPraticiens": false, "maxPraticiens": 1, "hasExportCsv": false}'::jsonb,
   true),
  ('veterinaire', 'clinique', 'Clinique', 49, 490, 0, 30, true,
   '{"hasAccesPermanent": true, "hasEcritureCarnetSante": true, "hasRappelsPush": true, "hasMultiPraticiens": true, "maxPraticiens": 5, "hasExportCsv": true}'::jsonb,
   true)
ON CONFLICT (profil_type, plan_code) DO UPDATE SET
  label         = EXCLUDED.label,
  prix_mensuel  = EXCLUDED.prix_mensuel,
  prix_annuel   = EXCLUDED.prix_annuel,
  features      = EXCLUDED.features,
  actif         = EXCLUDED.actif,
  updated_at    = now();
