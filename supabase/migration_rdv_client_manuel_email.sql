-- Email du client sans compte, pour un RDV créé manuellement par le pro
-- (walk-in / appel téléphonique). Sert à l'email de confirmation et, plus
-- tard, aux rappels par email.

ALTER TABLE rdv ADD COLUMN IF NOT EXISTS client_email_manuel TEXT;

COMMENT ON COLUMN rdv.client_email_manuel IS
  'Email du client sans compte (RDV créé par le pro) — sert à la confirmation et aux rappels.';
