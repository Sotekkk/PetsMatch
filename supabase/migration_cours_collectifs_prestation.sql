-- Lien optionnel d'une séance de groupe vers la prestation éducation d'origine.
-- Sert de clé de rapprochement « find-or-create » quand un client réserve un
-- créneau collectif depuis le calendrier de réservation éducateur : on
-- cherche une séance existante pour le couple
-- (pro_profile_id, date_heure, prestation_id) avant d'en créer une nouvelle.
ALTER TABLE cours_collectifs
  ADD COLUMN IF NOT EXISTS prestation_id UUID
    REFERENCES prestations_education(id) ON DELETE SET NULL;
