-- ══════════════════════════════════════════════════════════════════════════
-- Pension : heure de l'essai choisie par le client (07/11/2026)
-- ══════════════════════════════════════════════════════════════════════════
-- pension_demandes.heure_essai ('HH:MM') : choisie parmi les créneaux
-- d'arrivée libres du jour de l'essai (horaires de la pension). À
-- l'acceptation, elle devient l'heure d'arrivée prévue du séjour d'essai
-- (pension_entrees.heure_arrivee_prevue). Facultatif : rien ne change pour
-- l'existant. Le réglage « essai facturé / prix » est dans
-- user_profiles.tarifs_pension.essai (pas de colonne).
-- ══════════════════════════════════════════════════════════════════════════

BEGIN;
ALTER TABLE public.pension_demandes ADD COLUMN IF NOT EXISTS heure_essai TEXT;
COMMIT;
