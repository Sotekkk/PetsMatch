-- ============================================================
-- PetsMatch — Formules d'abonnement Toiletteur
-- (Gratuit / Pro / Premium), sur le modèle de
-- migration_sante_plans_tarifaires.sql. Grille dédiée (pas partagée avec
-- un autre profil_type).
-- Différenciateurs : GRATUIT = 1 employé, planning simple, prise de RDV.
-- PRO = employés illimités, facturation, stats, galerie, notifications,
-- export. PREMIUM = + planning multi-employés, contrat signé, paiement en
-- ligne, sync Google Agenda, mise en avant (2 dernières = affichées mais
-- non implémentées dans le code, hors scope fonctionnel actuel).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

INSERT INTO plans_tarifaires (profil_type, plan_code, label, prix_mensuel, prix_annuel, max_annonces, duree_annonce_jours, auto_publish, features, actif)
VALUES
  ('toilettage', 'free', 'Découverte', 0, 0, 0, 30, true,
   '{"hasEmployesIllimites": false, "maxEmployes": 1, "hasFacturation": false, "hasStatistiques": false, "hasGalerie": false, "hasNotifications": false, "hasExport": false, "hasPlanningEmployes": false, "hasContratSignature": false, "hasPaiementEnLigne": false, "hasSyncGoogleAgenda": false, "hasMiseEnAvant": false}'::jsonb,
   true),
  ('toilettage', 'pro', 'Pro', 15, 150, 0, 30, true,
   '{"hasEmployesIllimites": true, "maxEmployes": -1, "hasFacturation": true, "hasStatistiques": true, "hasGalerie": true, "hasNotifications": true, "hasExport": true, "hasPlanningEmployes": false, "hasContratSignature": false, "hasPaiementEnLigne": false, "hasSyncGoogleAgenda": false, "hasMiseEnAvant": false}'::jsonb,
   true),
  ('toilettage', 'premium', 'Premium', 25, 250, 0, 30, true,
   '{"hasEmployesIllimites": true, "maxEmployes": -1, "hasFacturation": true, "hasStatistiques": true, "hasGalerie": true, "hasNotifications": true, "hasExport": true, "hasPlanningEmployes": true, "hasContratSignature": true, "hasPaiementEnLigne": true, "hasSyncGoogleAgenda": true, "hasMiseEnAvant": true}'::jsonb,
   true)
ON CONFLICT (profil_type, plan_code) DO UPDATE SET
  label         = EXCLUDED.label,
  prix_mensuel  = EXCLUDED.prix_mensuel,
  prix_annuel   = EXCLUDED.prix_annuel,
  features      = EXCLUDED.features,
  actif         = EXCLUDED.actif,
  updated_at    = now();
