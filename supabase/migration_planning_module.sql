-- Planning module — Phase 1
-- Templates réutilisables
CREATE TABLE IF NOT EXISTS plan_templates (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid_eleveur     TEXT NOT NULL,
  nom             TEXT NOT NULL,
  type            TEXT NOT NULL CHECK (type IN ('sanitaire','nettoyage','promenade','socialisation')),
  espece          TEXT,
  description     TEXT,
  -- Qui est ciblé par ce protocole
  cible_type      TEXT NOT NULL DEFAULT 'individuel'
                  CHECK (cible_type IN ('individuel','cheptel','males','femelles','gestantes','bebes')),
  -- Quel événement sert de J0
  reference_event TEXT NOT NULL DEFAULT 'manuel'
                  CHECK (reference_event IN ('manuel','saillie','mise_bas','naissance','age_semaines','date_fixe')),
  -- Lieu (pour type=nettoyage : lieu physique à nettoyer, ex: "Chatterie n°1")
  lieu            TEXT,
  created_at      TIMESTAMPTZ DEFAULT now()
);

-- Étapes d'un template
CREATE TABLE IF NOT EXISTS plan_template_etapes (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id      UUID REFERENCES plan_templates(id) ON DELETE CASCADE,
  -- Moment relatif à l'événement de référence
  offset_direction TEXT NOT NULL DEFAULT 'apres' CHECK (offset_direction IN ('avant','apres')),
  jour_offset      INTEGER NOT NULL DEFAULT 0,    -- nombre de jours (toujours positif, direction dans offset_direction)
  -- Pour les bébés/jeunes : à partir de quel âge (en semaines)
  age_min_semaines INTEGER,
  -- Type d'acte et produit
  type_acte        TEXT,
  produit          TEXT,
  dosage           TEXT,
  -- Fréquence / répétition
  frequence        TEXT NOT NULL DEFAULT 'ponctuel'
                   CHECK (frequence IN ('ponctuel','quotidien','hebdomadaire','mensuel')),
  nb_fois_semaine  INTEGER DEFAULT 1,   -- si frequence='hebdomadaire' : 1, 2 ou 3 fois/semaine
  duree_semaines   INTEGER DEFAULT 1,   -- si frequence répétée : durée totale en semaines
  duree_jours      INTEGER NOT NULL DEFAULT 1,  -- garde la compat pour 'ponctuel' multi-jours
  -- Récurrence sans fin (génère 52 semaines automatiquement)
  is_recurrent     BOOLEAN NOT NULL DEFAULT FALSE,
  -- Lieu (promenade, socialisation)
  lieu             TEXT,
  description      TEXT,
  ordre            INTEGER NOT NULL DEFAULT 0
);

-- Instances actives
CREATE TABLE IF NOT EXISTS plans_actifs (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id       UUID REFERENCES plan_templates(id),
  uid_eleveur       TEXT NOT NULL,
  type_declencheur  TEXT NOT NULL,
  reference_id      TEXT,
  reference_label   TEXT,
  date_reference    DATE NOT NULL,
  statut            TEXT NOT NULL DEFAULT 'actif' CHECK (statut IN ('actif','termine','annule')),
  created_at        TIMESTAMPTZ DEFAULT now()
);

-- Tâches individuelles générées
CREATE TABLE IF NOT EXISTS plan_taches (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id          UUID REFERENCES plans_actifs(id) ON DELETE CASCADE,
  etape_id         UUID REFERENCES plan_template_etapes(id),
  uid_eleveur      TEXT NOT NULL,
  animal_id        TEXT,
  portee_id        TEXT,
  box_id           TEXT,
  label            TEXT NOT NULL,
  type_acte        TEXT,
  date_prevue      DATE NOT NULL,
  jour_traitement  INTEGER NOT NULL DEFAULT 1,
  total_jours      INTEGER NOT NULL DEFAULT 1,
  lieu             TEXT,
  assigned_to      TEXT,
  statut           TEXT NOT NULL DEFAULT 'en_attente' CHECK (statut IN ('en_attente','fait','ignore','reporte')),
  valide_par       TEXT,
  valide_at        TIMESTAMPTZ,
  notes_validation TEXT,
  created_at       TIMESTAMPTZ DEFAULT now()
);

-- Index pour les requêtes fréquentes
CREATE INDEX IF NOT EXISTS idx_plan_templates_eleveur ON plan_templates(uid_eleveur);
CREATE INDEX IF NOT EXISTS idx_plans_actifs_eleveur ON plans_actifs(uid_eleveur, statut);
CREATE INDEX IF NOT EXISTS idx_plan_taches_date ON plan_taches(uid_eleveur, date_prevue, statut);
CREATE INDEX IF NOT EXISTS idx_plan_taches_plan ON plan_taches(plan_id);

-- RLS
ALTER TABLE plan_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE plan_template_etapes ENABLE ROW LEVEL SECURITY;
ALTER TABLE plans_actifs ENABLE ROW LEVEL SECURITY;
ALTER TABLE plan_taches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner_templates" ON plan_templates
  FOR ALL USING (uid_eleveur = auth.uid()::text);

CREATE POLICY "owner_etapes" ON plan_template_etapes
  FOR ALL USING (
    template_id IN (SELECT id FROM plan_templates WHERE uid_eleveur = auth.uid()::text)
  );

CREATE POLICY "owner_plans" ON plans_actifs
  FOR ALL USING (uid_eleveur = auth.uid()::text);

CREATE POLICY "owner_taches" ON plan_taches
  FOR ALL USING (uid_eleveur = auth.uid()::text);

-- Employés peuvent lire les tâches qui leur sont assignées
CREATE POLICY "employe_taches_read" ON plan_taches
  FOR SELECT USING (assigned_to = auth.uid()::text);
