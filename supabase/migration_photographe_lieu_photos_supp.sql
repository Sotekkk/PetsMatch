-- Photographe — réservation et tarif à la photo.
--  • rdv.lieu_type : 'domicile' (adresse du client, rdv.adresse_depart) ou
--    'photographe' (plage, forêt, studio… : le photographe complète le lieu,
--    rdv.lieu garde le souhait éventuel du client).
--  • Tarif : le forfait (prestations_photographe.prix) inclut nb_photos ;
--    chaque photo supplémentaire choisie par le client coûte prix_photo_supp.
--    Même tarif quel que soit le nombre d'animaux (rdv.animaux_ids).
--  • albums_photo.prix_photo_supp : figé à la création de la galerie (le
--    client voit le supplément de sa sélection, la facture le reprend).
-- Idempotent.
ALTER TABLE public.rdv ADD COLUMN IF NOT EXISTS lieu_type TEXT;
ALTER TABLE public.prestations_photographe ADD COLUMN IF NOT EXISTS prix_photo_supp NUMERIC;
ALTER TABLE public.albums_photo ADD COLUMN IF NOT EXISTS prix_photo_supp NUMERIC;

NOTIFY pgrst, 'reload schema';
