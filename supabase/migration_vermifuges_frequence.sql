-- Vermifuges :
--  1. colonne « fréquence » (intervalle de rappel choisi dans le formulaire du
--     carnet). L'appli l'envoie déjà, mais seule la table antiparasitaires
--     l'avait → « Could not find the 'frequence' column of 'vermifuges' in the
--     schema cache » à l'enregistrement.
--  2. traitement sur plusieurs jours (ex. 3 jours) avec rappel à chaque prise,
--     comme les traitements : mêmes colonnes, même Cloud Function
--     (sendTraitementReminders, functions/sante.js).

ALTER TABLE public.vermifuges
  ADD COLUMN IF NOT EXISTS frequence              TEXT,
  ADD COLUMN IF NOT EXISTS duree_jours            INTEGER,   -- nombre de jours de prise (1 = prise unique)
  ADD COLUMN IF NOT EXISTS rappel_actif           BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS rappel_frequence_jours INTEGER,
  ADD COLUMN IF NOT EXISTS rappel_duree_jours     INTEGER,
  ADD COLUMN IF NOT EXISTS rappel_fin             DATE,
  ADD COLUMN IF NOT EXISTS rappel_heures          TEXT[];

CREATE INDEX IF NOT EXISTS idx_vermifuges_rappel_actif ON public.vermifuges (rappel_actif) WHERE rappel_actif = true;

NOTIFY pgrst, 'reload schema';
