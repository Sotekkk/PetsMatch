-- ════════════════════════════════════════════════════════════════════════
-- factures.id sans valeur par défaut : les factures créées depuis une
-- CESSION (appli cession_sheet.dart, site CessionModal.tsx) n'envoient pas
-- d'id → le garde-fou de conformité (journal des factures, facture_id NOT
-- NULL) refusait l'insertion. Le PDF était bien généré et rattaché à
-- l'animal, mais la facture n'apparaissait jamais dans « Mes factures »
-- (4 cessions concernées en prod, depuis le 31/08/2026).
-- L'écran Facturation, lui, fournit son id : inchangé.
-- ════════════════════════════════════════════════════════════════════════
ALTER TABLE public.factures ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
