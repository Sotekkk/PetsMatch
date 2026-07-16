-- ============================================================
-- PetsMatch — Formules d'abonnement "Soins para-médicaux"
-- (Découverte / Essentiel / Pro) — profils santé (ostéo/kiné) et
-- maréchal-ferrant, regroupés sous la même grille tarifaire (Spec §8.1)
-- mais suivis comme des abonnements distincts par profil_type.
-- Alimente plans_tarifaires (déjà générique, éditable depuis l'admin
-- web sans déploiement — voir /admin onglet Tarification).
-- Différenciateur cœur : l'ajout de séances au carnet santé (schéma
-- anatomique) est réservé aux formules Essentiel et Pro — la formule
-- FREE reste à l'annuaire basique (lecture via token 72h), comme pour
-- le vétérinaire.
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

INSERT INTO plans_tarifaires (profil_type, plan_code, label, prix_mensuel, prix_annuel, max_annonces, duree_annonce_jours, auto_publish, features, actif)
VALUES
  ('sante', 'free', 'Découverte', 0, 0, 0, 30, true,
   '{"hasAjoutSeances": false, "hasFactureExport": false, "hasMultiIntervenants": false, "maxIntervenants": 1}'::jsonb,
   true),
  ('sante', 'essentiel', 'Essentiel', 19, 190, 0, 30, true,
   '{"hasAjoutSeances": true, "hasFactureExport": false, "hasMultiIntervenants": false, "maxIntervenants": 1}'::jsonb,
   true),
  ('sante', 'pro', 'Pro', 29, 290, 0, 30, true,
   '{"hasAjoutSeances": true, "hasFactureExport": true, "hasMultiIntervenants": true, "maxIntervenants": 3}'::jsonb,
   true),
  ('marechal_ferrant', 'free', 'Découverte', 0, 0, 0, 30, true,
   '{"hasAjoutSeances": false, "hasFactureExport": false, "hasMultiIntervenants": false, "maxIntervenants": 1}'::jsonb,
   true),
  ('marechal_ferrant', 'essentiel', 'Essentiel', 19, 190, 0, 30, true,
   '{"hasAjoutSeances": true, "hasFactureExport": false, "hasMultiIntervenants": false, "maxIntervenants": 1}'::jsonb,
   true),
  ('marechal_ferrant', 'pro', 'Pro', 29, 290, 0, 30, true,
   '{"hasAjoutSeances": true, "hasFactureExport": true, "hasMultiIntervenants": true, "maxIntervenants": 3}'::jsonb,
   true)
ON CONFLICT (profil_type, plan_code) DO UPDATE SET
  label         = EXCLUDED.label,
  prix_mensuel  = EXCLUDED.prix_mensuel,
  prix_annuel   = EXCLUDED.prix_annuel,
  features      = EXCLUDED.features,
  actif         = EXCLUDED.actif,
  updated_at    = now();
