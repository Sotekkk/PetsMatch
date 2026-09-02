-- Commentaires libres sur un traitement (ex: impressions de tolérance —
-- effets secondaires observés, réaction de l'animal...), affichés sous le
-- reste des champs dans la fiche santé, app et site web, sur tous les
-- profils (particulier, éleveur, pro/vétérinaire).
-- Colonne alignée sur le nom déjà utilisé par les tables sœurs (visites,
-- vermifuges, antiparasitaires) et déjà référencée par certains formulaires
-- (site pro/vétérinaire, association) qui échouaient faute de colonne.
ALTER TABLE traitements
  ADD COLUMN IF NOT EXISTS notes TEXT;
