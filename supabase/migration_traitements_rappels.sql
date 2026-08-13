-- Rappels récurrents pour la table traitements (ex: piqûre antibiotique
-- tous les 3 jours pendant 3 semaines, soin des pattes tous les jours).
-- rappel_heures stocke les heures libres saisies par l'utilisateur
-- ("HH:MM"), potentiellement plusieurs par jour (matin/midi/soir...).
ALTER TABLE traitements
  ADD COLUMN IF NOT EXISTS rappel_actif           BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS rappel_frequence_jours  INTEGER,   -- répéter tous les N jours (1 = quotidien)
  ADD COLUMN IF NOT EXISTS rappel_duree_jours      INTEGER,   -- durée totale du traitement en jours
  ADD COLUMN IF NOT EXISTS rappel_fin              DATE,      -- date = date_debut + rappel_duree_jours, calculée côté appli
  ADD COLUMN IF NOT EXISTS rappel_heures           TEXT[];    -- ex: ARRAY['08:00','20:00']

CREATE INDEX IF NOT EXISTS idx_traitements_rappel_actif ON traitements(rappel_actif) WHERE rappel_actif = true;
