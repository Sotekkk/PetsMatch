-- ============================================================
-- PetsMatch — Colonne manquante rdv.notes_annulation
-- Référencée dans pro_agenda.dart, agenda_page.dart, mes-rdv/page.tsx,
-- pension/rdv/page.tsx, agenda/page.tsx pour stocker le motif de
-- refus/annulation d'un RDV — jamais créée en base, ce qui faisait
-- échouer (erreur Postgres 42703 "column does not exist") toute
-- requête SELECT qui la nommait explicitement, cassant l'affichage
-- complet des listes de RDV ("Mes RDV" notamment).
-- Exécuter dans Supabase SQL Editor (idempotent)
-- ============================================================

ALTER TABLE rdv ADD COLUMN IF NOT EXISTS notes_annulation TEXT;
