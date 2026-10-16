-- Photographe — formule Premium (19 €/mois, 190 €/an) : tout Essentiel +
-- galeries clients privées (aperçus protégés, partage, sélection, livraison
-- ZIP temporaire). Essentiel inchangé (9 € : portfolio illimité, mise en
-- avant, statistiques). Après exécution : ouvrir /admin → Tarification et
-- enregistrer la ligne Photographe Premium pour créer les prix Stripe.
-- Idempotent.
INSERT INTO plans_tarifaires (profil_type, plan_code, label, prix_mensuel, prix_annuel, max_annonces, duree_annonce_jours, auto_publish, features, actif)
VALUES
  ('photographe', 'premium', 'Premium', 19, 190, 0, 30, true,
   '{"maxPhotosPortfolio": -1, "hasMiseEnAvant": true, "hasStatistiques": true, "hasGaleriesClients": true}'::jsonb,
   true)
ON CONFLICT (profil_type, plan_code) DO UPDATE SET
  label         = EXCLUDED.label,
  prix_mensuel  = EXCLUDED.prix_mensuel,
  prix_annuel   = EXCLUDED.prix_annuel,
  features      = EXCLUDED.features,
  actif         = EXCLUDED.actif,
  updated_at    = now();
