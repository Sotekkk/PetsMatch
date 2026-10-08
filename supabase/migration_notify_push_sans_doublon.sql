-- ════════════════════════════════════════════════════════════════════════
-- Push en double : le webhook « notify_push » (Database Webhook créé dans le
-- dashboard Supabase : AFTER INSERT ON notifications → Edge Function
-- send-push-notification) renvoyait un push pour CHAQUE notification, y
-- compris celles dont les Cloud Functions venaient d'envoyer le push
-- elles-mêmes (avec le profil en préfixe et le regroupement). D'où, sur le
-- téléphone : « Pomsky de la Luna · 🌸 Chaleurs probables — Aiko » ET
-- « 🌸 Chaleurs probables — Aiko » (08/10/2026).
--
-- Les Cloud Functions marquent désormais leurs requêtes avec l'en-tête
-- « x-pm-push: serveur » (functions/config.js) ; le webhook ne se déclenche
-- plus pour ces lignes. Les notifications créées par l'appli et le site
-- (sans cet en-tête) gardent leur push via le webhook.
--
-- La définition du webhook (URL + clé) est relue depuis la base et
-- réécrite avec une condition WHEN — rien de secret dans ce fichier.
-- Exception : copies aux co-propriétaires (data._copro_fanout = '1') —
-- personne d'autre ne leur envoie de push.
-- Idempotent.
-- ════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  d text;
BEGIN
  SELECT pg_get_triggerdef(t.oid) INTO d
    FROM pg_trigger t
   WHERE t.tgrelid = 'public.notifications'::regclass
     AND trim(t.tgname) = 'notify_push' AND NOT t.tgisinternal;
  IF d IS NULL THEN
    RAISE NOTICE 'Webhook notify_push absent : rien à faire.';
    RETURN;
  END IF;
  IF d LIKE '%x-pm-push%' THEN
    RAISE NOTICE 'Webhook notify_push déjà conditionné.';
    RETURN;
  END IF;
  d := replace(d, 'FOR EACH ROW EXECUTE',
    'FOR EACH ROW WHEN ((coalesce(nullif(current_setting(''request.headers'', true), ''''), ''{}'')::json ->> ''x-pm-push'') IS DISTINCT FROM ''serveur'''
    -- Copies aux co-propriétaires (trigger fanout, même requête) : leur
    -- push n'est envoyé par personne d'autre → toujours par le webhook.
    || ' OR (NEW.data ->> ''_copro_fanout'') = ''1'') EXECUTE');
  EXECUTE (SELECT format('DROP TRIGGER %I ON public.notifications', t.tgname)
             FROM pg_trigger t
            WHERE t.tgrelid = 'public.notifications'::regclass AND trim(t.tgname) = 'notify_push' AND NOT t.tgisinternal);
  EXECUTE d;
  RAISE NOTICE 'Webhook notify_push : condition ajoutée.';
END $$;
