-- Migration : groupes communautaires — rôle modérateur + signalement des posts
-- À exécuter dans l'éditeur SQL Supabase.

-- ── 1. Rôle « moderateur » dans groupes_membres ───────────────────────────────
-- Facebook-style : plusieurs admins + plusieurs modérateurs + membres.
ALTER TABLE groupes_membres DROP CONSTRAINT IF EXISTS groupes_membres_role_check;
ALTER TABLE groupes_membres ADD CONSTRAINT groupes_membres_role_check
  CHECK (role IN ('admin', 'moderateur', 'membre'));

-- ── 2. Extension de signalements pour le contenu des groupes ───────────────────
ALTER TABLE signalements DROP CONSTRAINT IF EXISTS signalements_target_type_check;
ALTER TABLE signalements ADD CONSTRAINT signalements_target_type_check
  CHECK (target_type IN ('user', 'annonce', 'profil_pro', 'balade_ludique',
                         'groupe_post', 'groupe_commentaire'));

ALTER TABLE signalements DROP CONSTRAINT IF EXISTS signalements_raison_check;
ALTER TABLE signalements ADD CONSTRAINT signalements_raison_check
  CHECK (raison IN ('contenu_inapproprie', 'spam', 'faux_profil', 'maltraitance',
                    'vente_interdite', 'autre'));

-- groupe_id sur le signalement : permet aux admins/modérateurs du groupe de
-- voir les signalements qui concernent LEUR groupe (sans passer par le panel
-- admin global).
ALTER TABLE signalements
  ADD COLUMN IF NOT EXISTS groupe_id UUID REFERENCES groupes(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_sig_groupe ON signalements (groupe_id)
  WHERE groupe_id IS NOT NULL;

-- ── 3. Notification à l'auteur quand son post est bloqué / signalé ─────────────
-- (pas de trigger : géré côté client — insert direct dans notifications)

-- ── 4. Rappel : la règle « pas de vente » est ajoutée d'office côté client ─────
-- (bandeau fixe non modifiable au-dessus des règles perso, appli + web ;
--  aucune donnée à migrer).
