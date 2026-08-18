-- Type de vaccin sélectionné dans un menu déroulant (ex: "Rage",
-- "CHPPI (Carré, Hépatite, Parvovirose, Parainfluenza)"...), utilisé pour :
--   - proposer automatiquement les délais de rappel et de validité par
--     défaut selon le type de vaccin et l'espèce (modifiables) ;
--   - détecter si c'est la toute première injection de ce type pour
--     l'animal (délai légal de mise en validité, ex: rage = 21 jours)
--     ou un rappel (valide dès le jour même).
ALTER TABLE vaccinations
  ADD COLUMN IF NOT EXISTS categorie text;
