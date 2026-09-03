-- ============================================================
-- PetsMatch — Migrations en attente à exécuter sur Supabase
-- ============================================================
-- Où l'exécuter : dashboard Supabase → SQL Editor → New query
-- → coller tout le contenu de ce fichier → Run.
-- Ce script est idempotent (IF NOT EXISTS partout), on peut le relancer
-- sans risque s'il a déjà tourné partiellement.
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 1. Suivi gestation — saillies multiples par chaleur
--    `saillies.dates` (jsonb) : toutes les dates de saillie d'un même
--       épisode (une chaleur), ex. ["2026-03-03","2026-03-05"].
--       `saillies.date` reste = 1re saillie (tri + compatibilité).
--    `gestations.date_prevue_fin` (date) : fin de la fenêtre de mise-bas.
--       date_prevue = 1re saillie + durée gestation (début de fenêtre)
--       date_prevue_fin = dernière saillie + durée gestation (fin)
--       Date la plus probable = milieu (calculée à l'affichage).
--    Sans cette migration : les saillies s'enregistrent quand même avec
--    une seule date et la gestation garde une date de mise-bas unique.
-- ────────────────────────────────────────────────────────────

ALTER TABLE saillies
  ADD COLUMN IF NOT EXISTS dates JSONB;

ALTER TABLE gestations
  ADD COLUMN IF NOT EXISTS date_prevue_fin DATE;


-- ────────────────────────────────────────────────────────────
-- 2. Suivi des chaleurs délégué à un employé
--    Quand l'éleveur confie le suivi des chaleurs d'une femelle à un
--    employé (fiche animale → onglet Chaleurs), ces colonnes portent le
--    destinataire des rappels « chaleurs » (fonction sendChaleursNotifications).
--    null = seul le propriétaire ; renseigné = propriétaire + employé.
--    Retirer l'attribution = remettre à null.
--    ⚠ Nécessite aussi un redéploiement des Cloud Functions.
-- ────────────────────────────────────────────────────────────

ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS chaleurs_responsable_uid        TEXT,
  ADD COLUMN IF NOT EXISTS chaleurs_responsable_profile_id UUID;


-- ────────────────────────────────────────────────────────────
-- 3. Cession — condition de stérilisation + suivi chiots cédés + anniversaires
--    À la cession, l'éleveur peut imposer une stérilisation avant un âge
--    donné (mois). Le propriétaire ET l'éleveur reçoivent des rappels
--    J-30 / J-7 / J-48h / J-0 puis quotidiens tant que la stérilisation
--    n'est pas déclarée faite (proprio, via animaux.sterilise) ET validée
--    (éleveur, via sterilisation_validee). Colonnes miroir sur `animaux`
--    car le web ne crée pas de ligne `cessions` et la fiche est transférée
--    à l'acquéreur à la confirmation.
--    `user_profiles.cession_anniv_auto` : envoi auto du message
--    d'anniversaire aux chiots cédés (sinon rappel + envoi 1 clic).
--    ⚠ Nécessite aussi un redéploiement des Cloud Functions
--    (sendSterilisationReminders, sendCessionBirthdayReminders).
-- ────────────────────────────────────────────────────────────

ALTER TABLE cessions
  ADD COLUMN IF NOT EXISTS prenom_acquereur         TEXT,
  ADD COLUMN IF NOT EXISTS sterilisation_requise    BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS sterilisation_age_mois   INTEGER,
  ADD COLUMN IF NOT EXISTS sterilisation_echeance   DATE,
  ADD COLUMN IF NOT EXISTS sterilisation_validee    BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS sterilisation_validee_at TIMESTAMPTZ;

ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS sterilisation_requise            BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS sterilisation_echeance           DATE,
  ADD COLUMN IF NOT EXISTS sterilisation_validee            BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS sterilisation_declaree_at        TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS sterilisation_eleveur_uid        TEXT,
  ADD COLUMN IF NOT EXISTS sterilisation_eleveur_profile_id UUID;

CREATE INDEX IF NOT EXISTS idx_animaux_sterilisation_suivi
  ON animaux(sterilisation_eleveur_uid)
  WHERE sterilisation_requise = TRUE;

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS cession_anniv_auto  BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS cession_anniv_texte TEXT;


-- ────────────────────────────────────────────────────────────
-- 4. Contrat de cession lié au profil de l'acquéreur
--    Le contrat/facture (documents_animaux) doit porter l'uid ET le profil
--    (particulier, pas le profil pro/pension) de l'acquéreur, pour :
--      - notifier la bonne personne quand l'éleveur signe,
--      - transférer l'animal sur le bon profil à la signature complète,
--      - retrouver l'acquéreur dans « Mes contrats ».
--    Sans cette migration : erreur « couldn't find uid_acquereur column of
--    documents_animaux » à la création d'un contrat de cession.
-- ────────────────────────────────────────────────────────────

ALTER TABLE documents_animaux
  ADD COLUMN IF NOT EXISTS uid_acquereur        TEXT,
  ADD COLUMN IF NOT EXISTS acquereur_profile_id UUID REFERENCES user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_docs_uid_acquereur     ON documents_animaux(uid_acquereur);
CREATE INDEX IF NOT EXISTS idx_docs_acquereur_profile ON documents_animaux(acquereur_profile_id);


-- ────────────────────────────────────────────────────────────
-- 5. Vitrine « Reproducteurs » sur le profil public de l'éleveur
--    - animaux.reproducteur_public : l'éleveur autorise l'affichage public
--      de CE reproducteur (candidats = animaux déjà marqués reproducteur=true)
--    - animaux.nom_pedigree : nom de pedigree / affixe complet (≠ nom d'usage)
--    - user_profiles.montre_reproducteurs : interrupteur maître de l'éleveur
--    La page publique n'affiche un repro que si les DEUX sont vrais.
-- ────────────────────────────────────────────────────────────

ALTER TABLE animaux
  ADD COLUMN IF NOT EXISTS reproducteur_public BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS nom_pedigree        TEXT;

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS montre_reproducteurs BOOLEAN DEFAULT FALSE;

CREATE INDEX IF NOT EXISTS idx_animaux_repro_public
  ON animaux(uid_eleveur) WHERE reproducteur_public = TRUE;


-- ────────────────────────────────────────────────────────────
-- 6. Description de la maladie sur un traitement (fiche santé particulier
--    et éleveur, appli + site web).
--    Sans cette migration : erreur « couldn't find the description_maladie
--    column of traitements » à l'ajout d'un traitement avec ce champ rempli.
-- ────────────────────────────────────────────────────────────

ALTER TABLE traitements
  ADD COLUMN IF NOT EXISTS description_maladie TEXT;


-- ────────────────────────────────────────────────────────────
-- 7. Commentaires libres sur un traitement (ex: impressions de tolérance),
--    fiche santé de tous les profils (particulier, éleveur, pro/vétérinaire),
--    appli + site web.
--    Sans cette migration : erreur « couldn't find the notes column of
--    traitements » à l'ajout d'un traitement avec ce champ rempli — bloquait
--    déjà silencieusement le formulaire vétérinaire (mes-patients) et celui
--    des associations, qui référençaient tous les deux ce champ.
-- ────────────────────────────────────────────────────────────

ALTER TABLE traitements
  ADD COLUMN IF NOT EXISTS notes TEXT;


-- ────────────────────────────────────────────────────────────
-- 8. Défaut manquant sur id (carnet de santé) — formulaire vétérinaire
--    (mes-patients) et association/animaux insèrent une ligne sans jamais
--    fournir d'id. Sans DEFAULT, id (TEXT PRIMARY KEY, NOT NULL) fait
--    échouer toute l'insertion, silencieusement dans ces deux pages
--    (erreur non affichée à l'utilisateur).
-- ────────────────────────────────────────────────────────────

ALTER TABLE vaccinations      ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE traitements       ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE visites           ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE vermifuges        ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE antiparasitaires  ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE allergies         ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;
ALTER TABLE poids             ALTER COLUMN id SET DEFAULT gen_random_uuid()::text;


-- ────────────────────────────────────────────────────────────
-- 9. Messagerie — thèmes de conversation, réactions emoji, signalement
--    (features livrées début septembre côté app ET site, jamais accompagnées
--    d'une migration à l'époque). Fichier séparé, trop volumineux pour être
--    dupliqué ici : voir supabase/migration_messaging_complete.sql
--    (idempotent, à coller tel quel dans le SQL Editor).
--    Sans cette migration : conversations.theme_id inexistant (le
--    sélecteur de thème ne sauvegarde rien), tables message_reactions et
--    conversation_reports inexistantes (réactions et signalement muets).
-- ────────────────────────────────────────────────────────────
