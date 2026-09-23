-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 19/N : éducation / cours collectifs
--   cours_collectifs, cours_collectifs_participants, cours_collectifs_series,
--   exercices_bibliotheque, exercices_attribues, exercices_retours,
--   education_objectifs, education_attestations, forfaits_education,
--   partage_suivi_education
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- Modèle retenu :
--   - cours_collectifs : lu par le pro/cogérant OU tout participant inscrit
--     (cours_collectifs_participants.client_uid). Création laissée à tout
--     utilisateur connecté (pas seulement le pro) — la réservation d'un
--     créneau crée la ligne cours_collectifs elle-même si elle n'existe pas
--     encore (education_reservation_page.dart), le pro_uid renseigné n'est
--     alors pas forcément le uid de l'appelant. Modification/suppression :
--     pro/cogérant uniquement.
--   - cours_collectifs_participants : pro/cogérant (gère les inscriptions)
--     OU le client concerné (client_uid) pour voir/gérer sa propre
--     inscription.
--   - cours_collectifs_series : gestion pro/cogérant uniquement (récurrence
--     interne, jamais lue côté client).
--   - exercices_bibliotheque : bibliothèque perso du pro, pro/cogérant
--     uniquement.
--   - exercices_attribues, education_objectifs, education_attestations :
--     pro/cogérant (assignation) + propriétaire (owner_uid) en lecture ;
--     exercices_attribues aussi en écriture pour le propriétaire (mute des
--     rappels, seule action client sur cette table).
--   - exercices_retours (retours famille/éducateur sur un exercice) :
--     les deux parties de l'attribution parente (pro_uid, owner_uid),
--     lecture et création (chacun peut aussi répondre à l'autre).
--   - forfaits_education, partage_suivi_education : lecture publique
--     (forfaits affichés sur la fiche publique du pro ; partage_suivi a un
--     token pour un lien externe, même modèle que factures vague 15/N),
--     écriture pro/cogérant uniquement.
--
-- ⚠️ À TESTER après exécution :
--   1. Le planning éducateur (cours collectifs + inscriptions), la
--      bibliothèque d'exercices, les objectifs et attestations
--      s'affichent normalement pour le pro/cogérant.
--   2. Réserver un cours collectif (création + inscription) fonctionne
--      toujours côté client ; le client voit bien son inscription et le
--      cours dans son agenda.
--   3. Un client mute les rappels d'un exercice, envoie un retour
--      (photo/note) sur un exercice attribué : fonctionne toujours.
--   4. La fiche publique d'un éducateur affiche toujours ses forfaits.
--   5. Un lien de partage de suivi éducation (token) continue de
--      fonctionner pour un visiteur externe.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── cours_collectifs ───────────────────────────────────────────────────────
ALTER TABLE cours_collectifs ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'cours_collectifs'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.cours_collectifs', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "cours_collectifs_select" ON cours_collectifs
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = cours_collectifs.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR EXISTS (
      SELECT 1 FROM cours_collectifs_participants p
      WHERE p.cours_id = cours_collectifs.id AND p.client_uid = (auth.jwt() ->> 'sub')
    )
  );

CREATE POLICY "cours_collectifs_insert" ON cours_collectifs
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') IS NOT NULL);

CREATE POLICY "cours_collectifs_update" ON cours_collectifs
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = cours_collectifs.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = cours_collectifs.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "cours_collectifs_delete" ON cours_collectifs
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = cours_collectifs.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- ── cours_collectifs_participants ─────────────────────────────────────────
ALTER TABLE cours_collectifs_participants ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'cours_collectifs_participants'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.cours_collectifs_participants', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "cours_participants_select" ON cours_collectifs_participants
  FOR SELECT USING (
    client_uid = (auth.jwt() ->> 'sub')
    OR EXISTS (
      SELECT 1 FROM cours_collectifs cc
      WHERE cc.id = cours_collectifs_participants.cours_id
        AND (
          cc.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = cc.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  );

CREATE POLICY "cours_participants_insert" ON cours_collectifs_participants
  FOR INSERT WITH CHECK (
    client_uid = (auth.jwt() ->> 'sub')
    OR EXISTS (
      SELECT 1 FROM cours_collectifs cc
      WHERE cc.id = cours_collectifs_participants.cours_id
        AND (
          cc.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = cc.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  );

CREATE POLICY "cours_participants_update" ON cours_collectifs_participants
  FOR UPDATE USING (
    client_uid = (auth.jwt() ->> 'sub')
    OR EXISTS (
      SELECT 1 FROM cours_collectifs cc
      WHERE cc.id = cours_collectifs_participants.cours_id
        AND (
          cc.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = cc.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  )
  WITH CHECK (
    client_uid = (auth.jwt() ->> 'sub')
    OR EXISTS (
      SELECT 1 FROM cours_collectifs cc
      WHERE cc.id = cours_collectifs_participants.cours_id
        AND (
          cc.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = cc.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  );

CREATE POLICY "cours_participants_delete" ON cours_collectifs_participants
  FOR DELETE USING (
    client_uid = (auth.jwt() ->> 'sub')
    OR EXISTS (
      SELECT 1 FROM cours_collectifs cc
      WHERE cc.id = cours_collectifs_participants.cours_id
        AND (
          cc.pro_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = cc.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  );

-- ── Tables pro_uid direct, gestion pro/cogérant uniquement ────────────────
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['cours_collectifs_series','exercices_bibliotheque']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;

    EXECUTE format($f$
      CREATE POLICY "%1$s_pro_or_cogerant" ON public.%1$I
        FOR ALL USING (
          (auth.jwt() ->> 'sub') = pro_uid
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = %1$I.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
        WITH CHECK (
          (auth.jwt() ->> 'sub') = pro_uid
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = %1$I.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    $f$, t);
  END LOOP;
END $$;

-- ── Tables pro_uid + owner_uid (propriétaire en lecture) ──────────────────
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['education_objectifs','education_attestations']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;

    EXECUTE format($f$
      CREATE POLICY "%1$s_select" ON public.%1$I
        FOR SELECT USING (
          (auth.jwt() ->> 'sub') = pro_uid
          OR (auth.jwt() ->> 'sub') = owner_uid
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = %1$I.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    $f$, t);

    EXECUTE format($f$
      CREATE POLICY "%1$s_write" ON public.%1$I
        FOR ALL USING (
          (auth.jwt() ->> 'sub') = pro_uid
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = %1$I.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
        WITH CHECK (
          (auth.jwt() ->> 'sub') = pro_uid
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = %1$I.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    $f$, t);
  END LOOP;
END $$;

-- ── exercices_attribues (comme ci-dessus, + le propriétaire peut modifier
--    SA propre ligne — mute des rappels, seule action client ici) ─────────
ALTER TABLE exercices_attribues ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'exercices_attribues'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.exercices_attribues', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "exercices_attribues_select" ON exercices_attribues
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR (auth.jwt() ->> 'sub') = owner_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = exercices_attribues.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "exercices_attribues_insert" ON exercices_attribues
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = exercices_attribues.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "exercices_attribues_update" ON exercices_attribues
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR (auth.jwt() ->> 'sub') = owner_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = exercices_attribues.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR (auth.jwt() ->> 'sub') = owner_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = exercices_attribues.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "exercices_attribues_delete" ON exercices_attribues
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = exercices_attribues.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- ── exercices_retours (rattaché via attribution_id → exercices_attribues) ─
ALTER TABLE exercices_retours ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'exercices_retours'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.exercices_retours', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "exercices_retours_related" ON exercices_retours
  FOR ALL USING (
    EXISTS (
      SELECT 1 FROM exercices_attribues ea
      WHERE ea.id = exercices_retours.attribution_id
        AND (
          ea.pro_uid = (auth.jwt() ->> 'sub')
          OR ea.owner_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = ea.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM exercices_attribues ea
      WHERE ea.id = exercices_retours.attribution_id
        AND (
          ea.pro_uid = (auth.jwt() ->> 'sub')
          OR ea.owner_uid = (auth.jwt() ->> 'sub')
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = ea.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    )
  );

-- ── forfaits_education, partage_suivi_education (lecture publique) ────────
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['forfaits_education','partage_suivi_education']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;

    EXECUTE format($f$
      CREATE POLICY "%1$s_select_all" ON public.%1$I FOR SELECT USING (true)
    $f$, t);

    EXECUTE format($f$
      CREATE POLICY "%1$s_write" ON public.%1$I
        FOR ALL USING (
          (auth.jwt() ->> 'sub') = pro_uid
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = %1$I.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
        WITH CHECK (
          (auth.jwt() ->> 'sub') = pro_uid
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = %1$I.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    $f$, t);
  END LOOP;
END $$;

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('cours_collectifs','cours_collectifs_participants','cours_collectifs_series','exercices_bibliotheque','exercices_attribues','exercices_retours','education_objectifs','education_attestations','forfaits_education','partage_suivi_education')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('cours_collectifs','cours_collectifs_participants','cours_collectifs_series','exercices_bibliotheque','exercices_attribues','exercices_retours','education_objectifs','education_attestations','forfaits_education','partage_suivi_education')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- CREATE POLICY "cours_collectifs_allow_all" ON cours_collectifs FOR ALL USING (true) WITH CHECK (true);
-- CREATE POLICY "cours_participants_allow_all" ON cours_collectifs_participants FOR ALL USING (true) WITH CHECK (true);
-- CREATE POLICY "cours_collectifs_series_allow_all" ON cours_collectifs_series FOR ALL USING (true) WITH CHECK (true);
-- CREATE POLICY "exercices_bibliotheque_all" ON exercices_bibliotheque FOR ALL USING (true) WITH CHECK (true);
-- CREATE POLICY "education_objectifs_allow_all" ON education_objectifs FOR ALL USING (true) WITH CHECK (true);
-- CREATE POLICY "education_attestations_all" ON education_attestations FOR ALL USING (true) WITH CHECK (true);
-- CREATE POLICY "exercices_attribues_allow_all" ON exercices_attribues FOR ALL USING (true) WITH CHECK (true);
-- CREATE POLICY "exercices_retours_allow_all" ON exercices_retours FOR ALL USING (true) WITH CHECK (true);
-- CREATE POLICY "Select forfaits_education" ON forfaits_education FOR SELECT USING (true);
-- CREATE POLICY "forfaits_education_allow_write" ON forfaits_education FOR ALL USING (true) WITH CHECK (true);
-- CREATE POLICY "partage_suivi_education_all" ON partage_suivi_education FOR ALL USING (true) WITH CHECK (true);
