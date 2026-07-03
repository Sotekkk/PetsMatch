-- ============================================================
-- PetsMatch — Formules d'abonnement pension (Découverte / Pro / Premium)
-- Alimente plans_tarifaires (déjà générique, éditable depuis l'admin
-- web sans déploiement — voir /admin onglet Tarification).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

INSERT INTO plans_tarifaires (profil_type, plan_code, label, prix_mensuel, prix_annuel, max_annonces, duree_annonce_jours, auto_publish, features, actif)
VALUES
  ('pension', 'free', 'Découverte', 0, 0, 0, 30, true,
   '{"hasInventaire": false, "hasEmployes": false, "maxEmployes": 0, "logementsIllimites": false, "maxLogements": 1, "hasProtocoles": false, "hasContratSignature": false, "hasFactureExport": false, "hasBadgePremium": false, "hasAccesPrioritaire": false}'::jsonb,
   true),
  ('pension', 'pro', 'Pro', 14, 140, 0, 30, true,
   '{"hasInventaire": true, "hasEmployes": true, "maxEmployes": 3, "logementsIllimites": true, "maxLogements": -1, "hasProtocoles": true, "hasContratSignature": true, "hasFactureExport": true, "hasBadgePremium": false, "hasAccesPrioritaire": false}'::jsonb,
   true),
  ('pension', 'premium', 'Premium', 24, 240, 0, 30, true,
   '{"hasInventaire": true, "hasEmployes": true, "maxEmployes": -1, "logementsIllimites": true, "maxLogements": -1, "hasProtocoles": true, "hasContratSignature": true, "hasFactureExport": true, "hasBadgePremium": true, "hasAccesPrioritaire": true}'::jsonb,
   true)
ON CONFLICT (profil_type, plan_code) DO UPDATE SET
  label         = EXCLUDED.label,
  prix_mensuel  = EXCLUDED.prix_mensuel,
  prix_annuel   = EXCLUDED.prix_annuel,
  features      = EXCLUDED.features,
  actif         = EXCLUDED.actif,
  updated_at    = now();
