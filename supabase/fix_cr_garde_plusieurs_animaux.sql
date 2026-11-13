-- Comptes rendus de garde déjà envoyés pour une garde de plusieurs animaux
-- (rdv.animaux_ids) : ils n'avaient été enregistrés que sur le 1er animal.
-- Copie chaque compte rendu (pension_updates lié au RDV) sur les autres
-- animaux de la garde, pour que leur fiche ait l'onglet « Pension & Garde ».
-- Idempotent : une copie n'est créée que si l'animal n'a pas déjà la même
-- nouvelle (même RDV, même note, même photo). À lancer une fois (13/11/2026).
BEGIN;
INSERT INTO public.pension_updates (animal_id, pro_uid, rdv_id, note, photo_url, video_url, incident, created_at)
SELECT a.aid, pu.pro_uid, pu.rdv_id, pu.note, pu.photo_url, pu.video_url, pu.incident, pu.created_at
FROM public.pension_updates pu
JOIN public.rdv r ON r.id = pu.rdv_id
CROSS JOIN LATERAL jsonb_array_elements_text(to_jsonb(r.animaux_ids)) AS a(aid)
WHERE pu.rdv_id IS NOT NULL
  AND jsonb_array_length(to_jsonb(r.animaux_ids)) > 1
  AND a.aid IS DISTINCT FROM pu.animal_id::text
  AND NOT EXISTS (
    SELECT 1 FROM public.pension_updates x
    WHERE x.rdv_id = pu.rdv_id AND x.animal_id::text = a.aid
      AND x.note IS NOT DISTINCT FROM pu.note AND x.photo_url IS NOT DISTINCT FROM pu.photo_url
  );
-- Vérifier le nombre de lignes ajoutées, puis COMMIT (ou ROLLBACK).
COMMIT;
