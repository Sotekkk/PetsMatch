-- ════════════════════════════════════════════════════════════════════════
-- Compte rendu vétérinaire : brouillon repris plus tard.
--
-- Le vétérinaire peut « Enregistrer en brouillon » : la ligne comptes_rendus
-- est en statut 'brouillon' (jamais visible du propriétaire — policy
-- comptes_rendus_select : statut = 'valide' côté propriétaire), sans
-- notification, sans écriture au carnet ni facture. La saisie complète
-- (motif, poids, actes, texte, vaccins et traitements structurés) est gardée
-- dans `brouillon` pour être reprise et modifiée ; elle est vidée à la
-- validation (les actes partent alors au carnet).
-- Format commun appli / site :
--   { motif, poids, texte, diag, actes: [..],
--     vaccins: [{nom, lot, date 'AAAA-MM-JJ', rappel}],
--     traitements: [{nom, type, rappels, notes,
--                    phases: [{dose, prises: [..], frequenceJours, dureeJours, doses}]}] }
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════
ALTER TABLE public.comptes_rendus ADD COLUMN IF NOT EXISTS brouillon JSONB;

NOTIFY pgrst, 'reload schema';
