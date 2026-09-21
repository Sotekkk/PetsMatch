-- ═══════════════════════════════════════════════════════════════════════════
-- Stories — légende avec mentions (@[Nom](profileId), même balisage que Pets
-- Social/Forum/Groupes) et quelques options de style (couleur/taille/gras).
-- Complète migration_stories.sql — à exécuter après (ou dans n'importe quel
-- ordre, les deux utilisent ADD COLUMN IF NOT EXISTS).
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.stories
  ADD COLUMN IF NOT EXISTS legende_couleur text DEFAULT '#FFFFFF',
  ADD COLUMN IF NOT EXISTS legende_taille  text DEFAULT 'm',   -- 's' | 'm' | 'l'
  ADD COLUMN IF NOT EXISTS legende_gras    boolean DEFAULT false;
