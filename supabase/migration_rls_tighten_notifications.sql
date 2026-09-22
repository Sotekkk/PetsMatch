-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 2/N : notifications
-- ══════════════════════════════════════════════════════════════════════════
-- Même contexte que migration_rls_tighten_user_profiles.sql : Firebase est
-- maintenant configuré côté Supabase en Third-Party Auth, le token est
-- transmis à chaque requête, (auth.jwt() ->> 'sub') reflète le vrai uid
-- Firebase connecté (jamais auth.uid() : il caste en UUID, les uid Firebase
-- n'en sont pas).
--
-- Modèle retenu pour notifications :
--   - INSERT : INCHANGÉ (uid IS NOT NULL) — une notification est presque
--     toujours créée PAR quelqu'un D'AUTRE que son destinataire (éleveur
--     qui notifie un acquéreur, admin qui valide un profil, Cloud Functions
--     de rappel, trigger de fanout co-propriétaires...). La restreindre à
--     l'auteur casserait la quasi-totalité des flux de notification.
--   - SELECT / UPDATE (marquer lu) / DELETE : le destinataire (uid) OU un
--     cogérant actif de l'élevage à qui appartient ce uid — sans cette
--     clause, un cogérant ne verrait plus AUCUNE notification de l'élevage
--     qu'il co-gère (rappels mise-bas, cessions, stérilisation...), exactement
--     le bug corrigé cette semaine côté app/web (notifications_page.dart /
--     /api/notifications) mais qui resterait bloqué par une RLS trop stricte
--     si on oubliait cette exception ici.
--
-- ⚠️ À TESTER après exécution :
--   1. La cloche de notifications s'affiche normalement pour un compte normal.
--   2. Une notification se marque bien comme lue au clic / au tap.
--   3. Un cogérant actif voit les notifications de l'élevage qu'il co-gère
--      (badge + liste) sous son propre compte.
--   4. Une notification adressée à quelqu'un d'autre (ex. relance
--      stérilisation à un acquéreur) est toujours créée sans erreur.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "allow_update_own_notifications" ON notifications;
DROP POLICY IF EXISTS "allow_delete_notifications"      ON notifications;
DROP POLICY IF EXISTS "allow_select_notifications"      ON notifications;
DROP POLICY IF EXISTS "notifications_owner_or_cogerant_select" ON notifications;
DROP POLICY IF EXISTS "notifications_owner_or_cogerant_update" ON notifications;
DROP POLICY IF EXISTS "notifications_owner_or_cogerant_delete" ON notifications;

-- INSERT laissée telle quelle (allow_insert_notifications, déjà en place).

CREATE POLICY "notifications_owner_or_cogerant_select" ON notifications
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant   = notifications.uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut       = 'actif'
        AND c.date_fin IS NULL
    )
  );

CREATE POLICY "notifications_owner_or_cogerant_update" ON notifications
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant   = notifications.uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut       = 'actif'
        AND c.date_fin IS NULL
    )
  );

CREATE POLICY "notifications_owner_or_cogerant_delete" ON notifications
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant   = notifications.uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut       = 'actif'
        AND c.date_fin IS NULL
    )
  );

-- Vérification
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'notifications'
ORDER BY cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "notifications_owner_or_cogerant_select" ON notifications;
-- DROP POLICY IF EXISTS "notifications_owner_or_cogerant_update" ON notifications;
-- DROP POLICY IF EXISTS "notifications_owner_or_cogerant_delete" ON notifications;
-- CREATE POLICY "allow_select_notifications" ON notifications FOR SELECT USING (true);
-- CREATE POLICY "allow_update_own_notifications" ON notifications FOR UPDATE USING (true) WITH CHECK (true);
-- CREATE POLICY "allow_delete_notifications" ON notifications FOR DELETE USING (true);
