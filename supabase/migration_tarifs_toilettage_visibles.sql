-- Toiletteur : les tarifs viennent du catalogue de prestations
-- (prestations_toilettage, prix par espèce / gabarit) — le champ « Tarifs »
-- libre est retiré du profil. Le pro choisit d'afficher ou non les prix sur
-- sa fiche publique (sinon « Sur devis »). Par défaut : affichés, comme avant.
-- Idempotent.
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS tarifs_toilettage_visibles BOOLEAN NOT NULL DEFAULT true;

NOTIFY pgrst, 'reload schema';
