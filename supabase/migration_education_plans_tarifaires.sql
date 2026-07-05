-- ============================================================
-- PetsMatch — Formules d'abonnement éducateur/comportementaliste
-- (Découverte / Pro / Premium)
-- Alimente plans_tarifaires (déjà générique, éditable depuis l'admin
-- web sans déploiement — voir /admin onglet Tarification).
-- Les fonctionnalités "cœur" (planning, cours individuels/collectifs,
-- tarification, suivi de progression, réservation en ligne) restent
-- disponibles à tous les paliers — seuls les employés, l'export
-- facturation et les avantages de visibilité sont différenciés,
-- comme pour la pension.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

INSERT INTO plans_tarifaires (profil_type, plan_code, label, prix_mensuel, prix_annuel, max_annonces, duree_annonce_jours, auto_publish, features, actif)
VALUES
  ('education', 'free', 'Découverte', 0, 0, 0, 30, true,
   '{"hasEmployes": false, "maxEmployes": 0, "hasFactureExport": false, "hasBadgePremium": false, "hasAccesPrioritaire": false}'::jsonb,
   true),
  ('education', 'pro', 'Pro', 14, 140, 0, 30, true,
   '{"hasEmployes": true, "maxEmployes": 3, "hasFactureExport": true, "hasBadgePremium": false, "hasAccesPrioritaire": false}'::jsonb,
   true),
  ('education', 'premium', 'Premium', 24, 240, 0, 30, true,
   '{"hasEmployes": true, "maxEmployes": -1, "hasFactureExport": true, "hasBadgePremium": true, "hasAccesPrioritaire": true}'::jsonb,
   true)
ON CONFLICT (profil_type, plan_code) DO UPDATE SET
  label         = EXCLUDED.label,
  prix_mensuel  = EXCLUDED.prix_mensuel,
  prix_annuel   = EXCLUDED.prix_annuel,
  features      = EXCLUDED.features,
  actif         = EXCLUDED.actif,
  updated_at    = now();
