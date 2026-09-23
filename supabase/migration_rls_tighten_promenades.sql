-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 35/N : promenades, promenades_participants,
--   promenades_messages, promenades_invitations, notifs_sent
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- promenades (sorties communautaires) : lecture publique (fil de découverte,
-- confirmé dans promenades_page.dart — pas de filtre "amis", la colonne
-- `visibilite` n'est lue nulle part dans le code, fonctionnalité pensée
-- comme un mur public façon Meetup). Écriture réservée à l'organisateur.
--
-- promenades_participants : lecture publique (liste des participants
-- affichée à tout visiteur de la fiche promenade). Écriture : rejoindre/
-- quitter = soi-même ; accepter/refuser une demande = l'organisateur
-- (confirmé dans promenade_detail_page.dart : _accept/_refuse modifient la
-- ligne du DEMANDEUR, pas de l'organisateur).
--
-- promenades_messages : chat de la sortie, lu sans condition de
-- participation dans promenade_detail_page.dart (mur ouvert, cohérent avec
-- la promenade elle-même publique) — lecture publique, écriture par tout
-- utilisateur connecté (aucune vérification de participation côté client
-- avant l'envoi, reflété tel quel).
--
-- promenades_invitations : AUCUNE référence dans le code actuel (flux
-- remplacé par la demande de participation directe sur
-- promenades_participants) — verrouillé par sécurité (inviteur/invité),
-- sans impact fonctionnel connu.
--
-- notifs_sent : journal de dédup générique (clé texte libre, ex.
-- "sante_vaccinations_muted_<id>"), sans colonne uid — utilisé par les
-- Cloud Functions (clé service_role, hors RLS) ET par le client pour
-- couper un rappel (animal_fiche.dart, upsert seul, jamais de lecture
-- côté client). Verrouillé : écriture (upsert) ouverte à tout utilisateur
-- connecté — pas de scoping possible par propriétaire (pas de colonne
-- dédiée) — lecture réservée au service_role (jamais lue par un client).
--
-- ⚠️ À TESTER après exécution :
--   1. Le fil des promenades reste visible publiquement ; créer/modifier/
--      annuler une promenade fonctionne pour son organisateur.
--   2. Rejoindre/quitter une promenade fonctionne ; accepter/refuser une
--      demande de participation fonctionne pour l'organisateur.
--   3. Le chat d'une promenade (texte + photo) fonctionne normalement.
--   4. « Ne plus me rappeler » sur un soin (carnet de santé) fonctionne
--      toujours.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── promenades ──────────────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE promenades ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'promenades'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.promenades', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "promenades_select" ON promenades FOR SELECT USING (true);
CREATE POLICY "promenades_write" ON promenades
  FOR ALL USING ((auth.jwt() ->> 'sub') = organisateur_uid)
  WITH CHECK ((auth.jwt() ->> 'sub') = organisateur_uid);

-- ── promenades_participants ────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE promenades_participants ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'promenades_participants'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.promenades_participants', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "promenades_participants_select" ON promenades_participants FOR SELECT USING (true);
CREATE POLICY "promenades_participants_insert" ON promenades_participants
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = user_uid);
CREATE POLICY "promenades_participants_update" ON promenades_participants
  FOR UPDATE USING (
    EXISTS (SELECT 1 FROM promenades p WHERE p.id = promenades_participants.promenade_id AND p.organisateur_uid = (auth.jwt() ->> 'sub'))
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM promenades p WHERE p.id = promenades_participants.promenade_id AND p.organisateur_uid = (auth.jwt() ->> 'sub'))
  );
CREATE POLICY "promenades_participants_delete" ON promenades_participants
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = user_uid
    OR EXISTS (SELECT 1 FROM promenades p WHERE p.id = promenades_participants.promenade_id AND p.organisateur_uid = (auth.jwt() ->> 'sub'))
  );

-- ── promenades_messages ─────────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE promenades_messages ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'promenades_messages'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.promenades_messages', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "promenades_messages_select" ON promenades_messages FOR SELECT USING (true);
CREATE POLICY "promenades_messages_insert" ON promenades_messages
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = user_uid);
CREATE POLICY "promenades_messages_delete" ON promenades_messages
  FOR DELETE USING ((auth.jwt() ->> 'sub') = user_uid);

-- ── promenades_invitations (aucune référence code actuelle) ──────────────
DO $$
DECLARE pol RECORD;
BEGIN
  IF to_regclass('public.promenades_invitations') IS NULL THEN RETURN; END IF;
  ALTER TABLE promenades_invitations ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'promenades_invitations'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.promenades_invitations', pol.policyname);
  END LOOP;
  EXECUTE $p$
    CREATE POLICY "promenades_invitations_parties" ON promenades_invitations
      FOR ALL USING (
        (auth.jwt() ->> 'sub') = inviteur_uid OR (auth.jwt() ->> 'sub') = invite_uid
      )
      WITH CHECK (
        (auth.jwt() ->> 'sub') = inviteur_uid OR (auth.jwt() ->> 'sub') = invite_uid
      )
  $p$;
END $$;

-- ── notifs_sent (dédup générique, sans colonne uid) ────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  ALTER TABLE notifs_sent ENABLE ROW LEVEL SECURITY;
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'notifs_sent'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.notifs_sent', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "notifs_sent_write" ON notifs_sent
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') IS NOT NULL);
CREATE POLICY "notifs_sent_update" ON notifs_sent
  FOR UPDATE USING ((auth.jwt() ->> 'sub') IS NOT NULL) WITH CHECK ((auth.jwt() ->> 'sub') IS NOT NULL);
-- Pas de policy SELECT : jamais lu côté client (seul le service_role, qui
-- contourne la RLS, en a besoin côté Cloud Functions).

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('promenades','promenades_participants','promenades_messages','promenades_invitations','notifs_sent')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('promenades','promenades_participants','promenades_messages','promenades_invitations','notifs_sent')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- ALTER TABLE promenades DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE promenades_participants DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE promenades_messages DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE promenades_invitations DISABLE ROW LEVEL SECURITY;
-- ALTER TABLE notifs_sent DISABLE ROW LEVEL SECURITY;
