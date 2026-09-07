-- ═══════════════════════════════════════════════════════════════════════════
-- Migration : Système de crédits & micro-transactions — Pets Social
-- À exécuter dans Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════════════════

-- ── Portefeuille crédits (1 ligne par utilisateur) ───────────────────────
CREATE TABLE IF NOT EXISTS public.credit_wallets (
  uid          TEXT PRIMARY KEY,
  solde        INTEGER NOT NULL DEFAULT 0,
  total_achete INTEGER NOT NULL DEFAULT 0,
  total_utilise INTEGER NOT NULL DEFAULT 0,
  updated_at   TIMESTAMPTZ DEFAULT now()
);

-- ── Packs de crédits disponibles à l'achat ───────────────────────────────
CREATE TABLE IF NOT EXISTS public.credit_packs (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nom            TEXT NOT NULL,
  credits        INTEGER NOT NULL,
  prix_euros     NUMERIC(10,2) NOT NULL,
  tag            TEXT,                  -- ex: 'Le plus populaire'
  stripe_price_id TEXT,
  actif          BOOLEAN DEFAULT true,
  ordre          INTEGER DEFAULT 0
);

-- ── Historique de tous les mouvements de crédits ─────────────────────────
CREATE TABLE IF NOT EXISTS public.credit_transactions (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid        TEXT NOT NULL,
  montant    INTEGER NOT NULL,           -- positif = achat, négatif = dépense
  motif      TEXT NOT NULL,             -- 'Achat pack', 'Boost de post', etc.
  ref_id     TEXT,                      -- post_id, pack_id selon le contexte
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_credit_transactions_uid  ON public.credit_transactions(uid);
CREATE INDEX IF NOT EXISTS idx_credit_transactions_date ON public.credit_transactions(created_at DESC);

-- ── RLS ──────────────────────────────────────────────────────────────────
ALTER TABLE public.credit_wallets     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.credit_packs       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.credit_transactions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "wallets_read"        ON public.credit_wallets;
DROP POLICY IF EXISTS "wallets_insert"      ON public.credit_wallets;
DROP POLICY IF EXISTS "wallets_update"      ON public.credit_wallets;
DROP POLICY IF EXISTS "packs_read"          ON public.credit_packs;
DROP POLICY IF EXISTS "transactions_read"   ON public.credit_transactions;
DROP POLICY IF EXISTS "transactions_insert" ON public.credit_transactions;

CREATE POLICY "wallets_read"        ON public.credit_wallets     FOR SELECT USING (true);
CREATE POLICY "wallets_insert"      ON public.credit_wallets     FOR INSERT WITH CHECK (true);
CREATE POLICY "wallets_update"      ON public.credit_wallets     FOR UPDATE USING (true);
CREATE POLICY "packs_read"          ON public.credit_packs       FOR SELECT USING (true);
CREATE POLICY "transactions_read"   ON public.credit_transactions FOR SELECT USING (true);
CREATE POLICY "transactions_insert" ON public.credit_transactions FOR INSERT WITH CHECK (true);

-- ── SEED — Packs de crédits ───────────────────────────────────────────────
INSERT INTO public.credit_packs (nom, credits, prix_euros, tag, ordre)
VALUES
  ('Starter',   100,   0.99, NULL,                1),
  ('Populaire', 500,   3.99, 'Le plus populaire', 2),
  ('Pro',       1200,  7.99, 'Meilleure valeur',  3),
  ('Max',       3000, 17.99, NULL,                4);

-- ── Tarifs actions Pets Social (référence, pas stocké en base) ───────────
-- Boost de post       : 50 crédits
-- Cadeau virtuel      : 20 crédits
-- Badge exclusif      : 200 crédits
-- Cadre avatar animé  : 350 crédits
-- Pass 7 jours        : 100 crédits
