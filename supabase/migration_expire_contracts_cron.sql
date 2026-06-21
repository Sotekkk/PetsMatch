-- Migration : expiration automatique des contrats via pg_cron
-- Prérequis : activer l'extension pg_cron dans Dashboard → Extensions

-- ─── 1. Fonction PL/pgSQL d'expiration ──────────────────────────────────────
CREATE OR REPLACE FUNCTION expire_contracts()
RETURNS integer   -- nombre de contrats expirés
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r        RECORD;
  nb_total integer := 0;
BEGIN
  FOR r IN
    SELECT id, titre, token, uid_eleveur, metadata
    FROM   documents_animaux
    WHERE  expires_at IS NOT NULL
      AND  expires_at < now()
      AND  statut NOT IN ('signe', 'annule', 'expire', 'refuse')
  LOOP
    -- Passer en expire
    UPDATE documents_animaux SET statut = 'expire' WHERE id = r.id;

    -- Notifier l'éleveur
    INSERT INTO notifications (uid, type, title, body, data, profile_type, read)
    VALUES (
      r.uid_eleveur,
      'contrat_expire',
      '⏰ Contrat expiré',
      'Le contrat « ' || COALESCE(r.titre, 'sans titre')
        || ' » a expiré — la signature n''est pas intervenue dans le délai prévu.',
      jsonb_build_object('token', r.token),
      '',
      false
    );

    -- Notifier l'acquéreur s'il a un compte PetsMatch
    INSERT INTO notifications (uid, type, title, body, data, profile_type, read)
    SELECT
      u.uid,
      'contrat_expire',
      '⏰ Contrat expiré',
      'Le contrat « ' || COALESCE(r.titre, 'sans titre') || ' » a expiré.',
      jsonb_build_object('token', r.token),
      '',
      false
    FROM users u
    WHERE u.email = (r.metadata->>'acquereur_email')
    LIMIT 1;

    nb_total := nb_total + 1;
  END LOOP;

  RETURN nb_total;
END;
$$;

-- ─── 2. Planification pg_cron — tous les jours à 2h00 UTC ───────────────────
-- Supprimer l'ancien job s'il existe (idempotent)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'expire-contracts-daily') THEN
    PERFORM cron.unschedule('expire-contracts-daily');
  END IF;
END
$$;

SELECT cron.schedule(
  'expire-contracts-daily',
  '0 2 * * *',
  'SELECT expire_contracts()'
);
