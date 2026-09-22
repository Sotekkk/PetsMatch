-- Co-gérance d'un élevage (deux comptes, un seul profil élevage)
-- ============================================================================
-- Un élevage géré à deux personnes distinctes (comptes PetsMatch séparés).
-- Contrairement aux co-propriétaires d'ANIMAL (animaux_proprietes, qui
-- dupliquent un lien par animal), ici on ne touche à AUCUNE table métier :
-- animaux / chaleurs / employes / agenda_events / taches / annonces /
-- contrats continuent tous de référencer le profile_id du gérant principal,
-- sans exception. Le cogérant obtient un accès complet en "empruntant" ce
-- profil élevage depuis son propre compte, exactement comme un profil
-- secondaire qu'il possèderait (ProfileService.loadProfiles le fusionne dans
-- son sélecteur de profil quand le lien est actif).
--
-- Cycle de vie : invite -> actif (accepté) ou refuse. Résiliation = on pose
-- date_fin (jamais de suppression : historique de qui a géré l'élevage et
-- quand, conservé). Une même personne peut être ré-invitée après résiliation
-- (nouvelle ligne), d'où l'index unique partiel sur les liens NON résiliés.
-- ============================================================================

CREATE TABLE IF NOT EXISTS elevage_cogerants (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  elevage_profile_id     UUID NOT NULL REFERENCES user_profiles(id) ON DELETE CASCADE,
  uid_gerant              TEXT NOT NULL,
  uid_cogerant            TEXT NOT NULL,
  profile_id_cogerant     UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  statut                  TEXT NOT NULL DEFAULT 'invite' CHECK (statut IN ('invite', 'actif', 'refuse')),
  invite_par_profile_id   UUID REFERENCES user_profiles(id) ON DELETE SET NULL,
  invite_le               TIMESTAMPTZ,
  accepte_le              TIMESTAMPTZ,
  date_debut              DATE,
  date_fin                DATE,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Un seul lien COURANT (non résilié) par paire élevage/cogérant.
CREATE UNIQUE INDEX IF NOT EXISTS idx_elevage_cogerants_courant
  ON elevage_cogerants (elevage_profile_id, uid_cogerant)
  WHERE date_fin IS NULL;

-- Lookup principal : "quels élevages est-ce que je cogère activement ?"
-- (ProfileService.loadProfiles, à chaque chargement du sélecteur de profil).
CREATE INDEX IF NOT EXISTS idx_elevage_cogerants_cogerant_actif
  ON elevage_cogerants (uid_cogerant)
  WHERE statut = 'actif' AND date_fin IS NULL;

CREATE INDEX IF NOT EXISTS idx_elevage_cogerants_elevage
  ON elevage_cogerants (elevage_profile_id);

-- RLS permissive (client Firebase Auth + clé anon Supabase — auth.uid() est
-- toujours NULL côté cette app, cf. migration_v2_04_fix_rls.sql : toute
-- policy basée sur auth.uid() bloquerait toutes les opérations).
ALTER TABLE elevage_cogerants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "firebase_allow_all" ON elevage_cogerants;
CREATE POLICY "firebase_allow_all" ON elevage_cogerants FOR ALL USING (true) WITH CHECK (true);
