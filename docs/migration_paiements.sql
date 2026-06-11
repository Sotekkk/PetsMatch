-- ═══════════════════════════════════════════════════════════════════════════
-- Migration : Modèle économique PetsMatch — Abonnements, Boosts, Tarification
-- À exécuter dans Supabase SQL Editor (une seule fois)
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Plans tarifaires (éditables depuis l'admin sans déploiement) ─────────────
CREATE TABLE IF NOT EXISTS public.plans_tarifaires (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profil_type TEXT NOT NULL,
  plan_code TEXT NOT NULL,
  label TEXT NOT NULL,
  prix_mensuel NUMERIC DEFAULT 0,
  prix_annuel NUMERIC DEFAULT 0,
  max_annonces INTEGER DEFAULT 3,      -- -1 = illimité
  duree_annonce_jours INTEGER DEFAULT 30,
  auto_publish BOOLEAN DEFAULT false,   -- true = publication immédiate
  features JSONB,
  stripe_price_id_mensuel TEXT,
  stripe_price_id_annuel TEXT,
  actif BOOLEAN DEFAULT true,
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(profil_type, plan_code)
);

-- ── Produits ponctuels (boosts, éditables depuis l'admin) ───────────────────
CREATE TABLE IF NOT EXISTS public.produits_ponctuels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  label TEXT NOT NULL,
  prix NUMERIC NOT NULL,
  duree_heures INTEGER,
  description TEXT,
  stripe_price_id TEXT,
  actif BOOLEAN DEFAULT true,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ── Abonnements actifs ───────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.abonnements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid TEXT NOT NULL,
  profil_type TEXT NOT NULL DEFAULT 'eleveur',
  plan_code TEXT NOT NULL DEFAULT 'free',
  stripe_subscription_id TEXT UNIQUE,
  stripe_customer_id TEXT,
  periodicite TEXT DEFAULT 'mensuel',
  statut TEXT DEFAULT 'actif',         -- actif/grace/annule
  date_debut TIMESTAMPTZ DEFAULT now(),
  date_fin TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_abonnements_uid ON public.abonnements(uid);
CREATE INDEX IF NOT EXISTS idx_abonnements_stripe_sub ON public.abonnements(stripe_subscription_id);

-- ── Achats ponctuels (boosts) ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.achats_ponctuels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid TEXT NOT NULL,
  produit_id UUID REFERENCES public.produits_ponctuels(id),
  annonce_id TEXT,
  stripe_payment_intent_id TEXT,
  statut TEXT DEFAULT 'paye',
  date_achat TIMESTAMPTZ DEFAULT now(),
  date_expiration TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_achats_ponctuels_uid ON public.achats_ponctuels(uid);
CREATE INDEX IF NOT EXISTS idx_achats_ponctuels_annonce ON public.achats_ponctuels(annonce_id);

-- ── Colonne is_premium sur users (si pas encore ajoutée) ────────────────────
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_premium BOOLEAN DEFAULT false;
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS plan_code TEXT DEFAULT 'free';
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT;

-- ── Colonne expire_at sur annonces (si pas encore ajoutée) ──────────────────
ALTER TABLE public.annonces ADD COLUMN IF NOT EXISTS expire_at TIMESTAMPTZ;
ALTER TABLE public.annonces ADD COLUMN IF NOT EXISTS boost_until TIMESTAMPTZ;

-- ── RLS ──────────────────────────────────────────────────────────────────────
-- Note : le projet utilise Firebase Auth (pas Supabase Auth), donc auth.uid()
-- est toujours NULL côté client. La sécurité est assurée par la clé service_role
-- côté serveur (API routes) et la clé anon en lecture seule côté client.

-- Plans et produits : données publiques, lecture libre, écriture via service_role uniquement
ALTER TABLE public.plans_tarifaires ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.produits_ponctuels ENABLE ROW LEVEL SECURITY;
CREATE POLICY "plans_read" ON public.plans_tarifaires FOR SELECT USING (true);
CREATE POLICY "produits_read" ON public.produits_ponctuels FOR SELECT USING (true);

-- Abonnements et achats : lecture libre (uid filtré côté app), écriture via service_role
-- Pas de RLS sur ces tables — les writes passent tous par les API routes (service_role).
-- La clé anon est en lecture seule (pas de RLS INSERT/UPDATE/DELETE avec anon).

-- ════════════════════════════════════════════════════════════════════════════
-- SEED — Plans tarifaires éleveur
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO public.plans_tarifaires (profil_type, plan_code, label, prix_mensuel, prix_annuel, max_annonces, duree_annonce_jours, auto_publish, features)
VALUES
  ('eleveur', 'free',    'Gratuit',  0,  0,   3,  30, false,
   '["3 annonces actives","Durée 30 jours","Validation manuelle","Profil annuaire"]'),
  ('eleveur', 'pro',     'Pro',      15, 149, 10, 45, true,
   '["10 annonces actives","Durée 45 jours","Publication immédiate","Rappel J-5","1 boost/mois inclus","2 employés","Statistiques profil"]'),
  ('eleveur', 'premium', 'Premium',  25, 249, -1, 60, true,
   '["Annonces illimitées","Durée 60 jours","Publication immédiate","Auto-renouvellement","3 boosts/mois","Module facturation","Badge Premium"]')
ON CONFLICT (profil_type, plan_code) DO UPDATE SET
  label = EXCLUDED.label, prix_mensuel = EXCLUDED.prix_mensuel,
  prix_annuel = EXCLUDED.prix_annuel, max_annonces = EXCLUDED.max_annonces,
  duree_annonce_jours = EXCLUDED.duree_annonce_jours, auto_publish = EXCLUDED.auto_publish,
  features = EXCLUDED.features, updated_at = now();

-- ════════════════════════════════════════════════════════════════════════════
-- SEED — Produits ponctuels (boosts)
-- ════════════════════════════════════════════════════════════════════════════
INSERT INTO public.produits_ponctuels (code, label, prix, duree_heures, description)
VALUES
  ('boost_48h',      'Boost annonce 48h',       1.99, 48,   'Remontée en tête de feed pendant 48h'),
  ('mise_une',       'Mise à la une',            4.99, 168,  'Badge + position prioritaire pendant 7 jours'),
  ('remontee',       'Remontée instantanée',     0.99, NULL, 'Re-publication dans le feed (instantané)'),
  ('annonce_sup',    'Annonce supplémentaire',   2.99, NULL, 'Quota +1 annonce au-delà de votre plan'),
  ('pack_3boosts',   'Pack 3 boosts 48h',        4.99, NULL, '3 remontées 48h (économie vs 3 × 1,99€)')
ON CONFLICT (code) DO UPDATE SET
  label = EXCLUDED.label, prix = EXCLUDED.prix,
  duree_heures = EXCLUDED.duree_heures, description = EXCLUDED.description,
  updated_at = now();
