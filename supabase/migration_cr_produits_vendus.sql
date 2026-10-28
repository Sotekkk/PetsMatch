-- ════════════════════════════════════════════════════════════════════════
-- Compte rendu vétérinaire : produits vendus pendant la consultation.
--
-- Produits délivrés au client sans être administrés (antiparasitaire à
-- appliquer à la maison, aliment, shampooing…) : pas inscrits au carnet,
-- ajoutés à la facture et décomptés du stock (inventaire_mouvements). Gardés
-- avec le compte rendu pour pouvoir le « Facturer » après coup.
-- Format (appli / site) : [{ nom, quantite, prix (TTC unitaire ou null), item_id }]
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════
ALTER TABLE public.comptes_rendus ADD COLUMN IF NOT EXISTS produits JSONB;

NOTIFY pgrst, 'reload schema';
