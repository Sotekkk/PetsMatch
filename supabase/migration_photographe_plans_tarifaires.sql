-- ============================================================
-- PetsMatch — Formules d'abonnement Photographe animalier
-- (Découverte / Essentiel), Spec §8.1.
-- Alimente plans_tarifaires (déjà générique, éditable depuis l'admin
-- web sans déploiement — voir /admin onglet Tarification).
-- Différenciateur cœur : FREE = profil annuaire + 5 photos portfolio ;
-- Essentiel = portfolio illimité, mise en avant, statistiques de profil.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

INSERT INTO plans_tarifaires (profil_type, plan_code, label, prix_mensuel, prix_annuel, max_annonces, duree_annonce_jours, auto_publish, features, actif)
VALUES
  ('photographe', 'free', 'Découverte', 0, 0, 0, 30, true,
   '{"maxPhotosPortfolio": 5, "hasMiseEnAvant": false, "hasStatistiques": false}'::jsonb,
   true),
  ('photographe', 'essentiel', 'Essentiel', 9, 90, 0, 30, true,
   '{"maxPhotosPortfolio": -1, "hasMiseEnAvant": true, "hasStatistiques": true}'::jsonb,
   true)
ON CONFLICT (profil_type, plan_code) DO UPDATE SET
  label         = EXCLUDED.label,
  prix_mensuel  = EXCLUDED.prix_mensuel,
  prix_annuel   = EXCLUDED.prix_annuel,
  features      = EXCLUDED.features,
  actif         = EXCLUDED.actif,
  updated_at    = now();
