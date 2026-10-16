-- Contrats de prestation photo déjà envoyés : le client ne les voyait pas dans
-- « Mes contrats » (metadata sans client_uid). Rattache chaque contrat au
-- client du rendez-vous (uid + profil destinataire). Les nouveaux contrats
-- portent ces champs dès leur création. Idempotent.
UPDATE public.documents_animaux d
SET metadata = COALESCE(d.metadata, '{}'::jsonb)
  || jsonb_strip_nulls(jsonb_build_object('client_uid', r.client_uid, 'client_profile_id', r.client_profile_id))
FROM public.rdv r
WHERE d.type = 'contrat_prestation_photo'
  AND d.rdv_id::text = r.id::text
  AND r.client_uid IS NOT NULL
  AND COALESCE(d.metadata->>'client_uid', '') = '';
