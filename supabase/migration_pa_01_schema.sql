-- petsmatch-pa — Schéma de données fiscales (facturation électronique)
-- ============================================================================
-- Cahier des charges §11 : une facture électronique est d'abord un ensemble de
-- données STRUCTURÉES. Ces tables stockent la représentation EN 16931
-- normalisée, séparée de `public.factures` (le moteur commercial).
--
-- ⚠️ Destiné à MIGRER vers une base dédiée (UE + SecNumCloud) une fois la
--     décision infra prise. Donc :
--       - schéma `pa` isolé,
--       - AUCUNE clé étrangère vers `public.*` (lien par `source_facture_id`),
--       - accès réservé à service_role (le service petsmatch-pa), RLS active
--         sans policy permissive → rien depuis les clés anon/authenticated.
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS pa;

-- ── Cycle de vie (§18) ──────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'pa_invoice_status') THEN
    CREATE TYPE pa.pa_invoice_status AS ENUM (
      'brouillon',
      'validee',
      'emise',
      'transmise',
      'mise_a_disposition',
      'acceptee',
      'payee',
      -- cas d'erreur / fin de vie
      'rejetee',
      'refusee',
      'erreur_technique',
      'annulee'
    );
  END IF;
END $$;

-- ── Facture (en-tête + parties + totaux) ────────────────────────────────────
CREATE TABLE IF NOT EXISTS pa.invoices (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  -- Lien vers la facture commerciale d'origine (public.factures.id), sans FK.
  source_facture_id   TEXT NOT NULL,
  source_kind         TEXT NOT NULL DEFAULT 'factures'
                      CHECK (source_kind IN ('factures', 'pension_factures')),
  profil_source       TEXT,

  -- BT-1..BT-5
  number              TEXT NOT NULL,
  issue_date          DATE NOT NULL,
  type_code           TEXT NOT NULL CHECK (type_code IN ('380','381','384','386')),
  currency_code       TEXT NOT NULL DEFAULT 'EUR',
  due_date            DATE,
  service_date        DATE,
  buyer_reference     TEXT,                              -- BT-10
  preceding_invoice_number TEXT,                         -- BT-25

  is_b2c              BOOLEAN NOT NULL DEFAULT false,

  -- Vendeur (BG-4) — figé
  seller              JSONB NOT NULL,
  -- Acheteur (BG-7) — NULL en B2C
  buyer               JSONB,

  -- Totaux (BG-22)
  line_net_total      NUMERIC(14,2) NOT NULL DEFAULT 0,
  tax_exclusive_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
  tax_amount          NUMERIC(14,2) NOT NULL DEFAULT 0,
  tax_inclusive_amount NUMERIC(14,2) NOT NULL DEFAULT 0,
  paid_amount         NUMERIC(14,2),
  amount_due          NUMERIC(14,2) NOT NULL DEFAULT 0,

  -- Paiement (BG-16)
  payment             JSONB,
  note                TEXT,

  -- État
  status              pa.pa_invoice_status NOT NULL DEFAULT 'brouillon',
  status_changed_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- Résultat de validation pré-émission (§13)
  validation_ok       BOOLEAN,
  validation_issues   JSONB,
  validated_at        TIMESTAMPTZ,

  -- Factur-X figé (§12) — rempli à l'émission
  facturx_pdf_url     TEXT,
  facturx_xml         TEXT,
  facturx_hash        TEXT,          -- SHA-256 du PDF/A-3
  facturx_profile     TEXT,          -- 'EN16931' | 'BASIC' | ...
  emitted_at          TIMESTAMPTZ,

  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (source_kind, source_facture_id)
);

CREATE INDEX IF NOT EXISTS idx_pa_invoices_source ON pa.invoices (source_facture_id);
CREATE INDEX IF NOT EXISTS idx_pa_invoices_status ON pa.invoices (status);
CREATE INDEX IF NOT EXISTS idx_pa_invoices_b2c    ON pa.invoices (is_b2c) WHERE status <> 'brouillon';

-- ── Lignes (BG-25) ─────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pa.invoice_lines (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id     UUID NOT NULL REFERENCES pa.invoices(id) ON DELETE CASCADE,
  line_no        INTEGER NOT NULL,        -- BT-126
  name           TEXT NOT NULL,           -- BT-153
  description    TEXT,                    -- BT-154
  quantity       NUMERIC(14,4) NOT NULL,  -- BT-129
  unit_code      TEXT NOT NULL DEFAULT 'C62', -- BT-130
  net_price      NUMERIC(14,4) NOT NULL,  -- BT-146
  net_amount     NUMERIC(14,2) NOT NULL,  -- BT-131
  vat_category   TEXT NOT NULL,           -- BT-151
  vat_rate       NUMERIC(6,2) NOT NULL,   -- BT-152
  UNIQUE (invoice_id, line_no)
);
CREATE INDEX IF NOT EXISTS idx_pa_lines_invoice ON pa.invoice_lines (invoice_id);

-- ── Ventilation TVA (BG-23) ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pa.invoice_vat (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id            UUID NOT NULL REFERENCES pa.invoices(id) ON DELETE CASCADE,
  vat_category          TEXT NOT NULL,           -- BT-118
  vat_rate              NUMERIC(6,2) NOT NULL,   -- BT-119
  taxable_amount        NUMERIC(14,2) NOT NULL,  -- BT-116
  tax_amount            NUMERIC(14,2) NOT NULL,  -- BT-117
  exemption_reason_code TEXT,                    -- BT-121
  exemption_reason_text TEXT,                    -- BT-120
  UNIQUE (invoice_id, vat_category, vat_rate)
);

-- ── Journal de preuve (§22-23) — append only ──────────────────────────────
CREATE TABLE IF NOT EXISTS pa.invoice_events (
  id            BIGSERIAL PRIMARY KEY,
  invoice_id    UUID REFERENCES pa.invoices(id) ON DELETE CASCADE,
  source_facture_id TEXT,
  occurred_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  event         TEXT NOT NULL,        -- 'creation' | 'validation' | 'emission'
                                      -- | 'transition' | 'transmission' | ...
  from_status   pa.pa_invoice_status,
  to_status     pa.pa_invoice_status,
  actor_uid     TEXT,
  actor_kind    TEXT,                 -- 'user' | 'system' | 'pa'
  result        TEXT NOT NULL DEFAULT 'success' CHECK (result IN ('success','failure')),
  detail        JSONB,
  content_hash  TEXT,                 -- SHA-256 du contenu concerné (PDF, XML…)
  model_version TEXT                  -- version du modèle petsmatch-pa
);
CREATE INDEX IF NOT EXISTS idx_pa_events_invoice ON pa.invoice_events (invoice_id);
CREATE INDEX IF NOT EXISTS idx_pa_events_source  ON pa.invoice_events (source_facture_id);

-- ── File e-reporting (§19-20) : transactions B2C + paiements ───────────────
CREATE TABLE IF NOT EXISTS pa.ereporting_queue (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id    UUID REFERENCES pa.invoices(id) ON DELETE CASCADE,
  kind          TEXT NOT NULL CHECK (kind IN ('transaction', 'paiement')),
  period        TEXT,                 -- période de déclaration (AAAA-MM)
  payload       JSONB NOT NULL,       -- données structurées à transmettre
  status        TEXT NOT NULL DEFAULT 'a_transmettre'
                CHECK (status IN ('a_transmettre','transmis','erreur')),
  transmitted_at TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pa_ereporting_status ON pa.ereporting_queue (status);

-- ── Transmissions (§14, preuves) ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS pa.transmissions (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invoice_id     UUID NOT NULL REFERENCES pa.invoices(id) ON DELETE CASCADE,
  direction      TEXT NOT NULL CHECK (direction IN ('emission','reception')),
  channel        TEXT,                -- 'pdp_tiers:<nom>' | 'annuaire' | 'peppol' | ...
  recipient_eas  TEXT,                -- adresse électronique du destinataire
  attempted_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  result         TEXT NOT NULL DEFAULT 'pending'
                 CHECK (result IN ('pending','delivered','rejected','error')),
  proof          JSONB,               -- accusé, identifiants, horodatage externe
  content_hash   TEXT
);
CREATE INDEX IF NOT EXISTS idx_pa_transmissions_invoice ON pa.transmissions (invoice_id);

-- ── Verrouillage d'accès ─────────────────────────────────────────────────────
-- Le schéma `pa` n'est manipulé que par le service petsmatch-pa (service_role).
REVOKE ALL ON ALL TABLES IN SCHEMA pa FROM anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA pa FROM anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA pa REVOKE ALL ON TABLES FROM anon, authenticated;

DO $$
DECLARE t RECORD;
BEGIN
  FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'pa' LOOP
    EXECUTE format('ALTER TABLE pa.%I ENABLE ROW LEVEL SECURITY', t.tablename);
    EXECUTE format('ALTER TABLE pa.%I FORCE ROW LEVEL SECURITY', t.tablename);
  END LOOP;
END $$;
-- Aucune policy → seul service_role (qui outrepasse RLS) accède aux données.
