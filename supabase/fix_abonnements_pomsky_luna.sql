-- Pomsky de la Luna repassé en gratuit (09/11/2026).
-- Cause : un abonnement vétérinaire « clinique » (Stripe test sub_1UOayX…,
-- pris le 09/10 depuis le profil éleveur actif) enregistré en profil_type
-- 'eleveur' : plus récent que le Premium éleveur, il était lu comme formule
-- éleveur inconnue → gratuit. Et l'abonnement photographe (sub_1UR82A…) était
-- rattaché au profil éleveur.

-- 1. L'abonnement clinique va au profil vétérinaire (doublon de l'annuel : annulé).
UPDATE abonnements
SET profil_type = 'veterinaire',
    profile_id  = 'c6152d62-f8e5-472c-9fb7-743df89ed0b0',
    statut      = 'annule',
    updated_at  = now()
WHERE id = '6edf82ac-8d39-4034-ab24-7dc752451888'
  AND profil_type = 'eleveur' AND plan_code = 'clinique';

-- 2. L'abonnement photographe va au profil « Photographe Test ».
UPDATE abonnements
SET profile_id = 'e3a5c6ad-a7fe-4744-bfab-cb7764a18e43',
    updated_at = now()
WHERE id = '18722d76-b859-4478-8427-3254469219d9'
  AND profile_id = '47c2a0c7-6214-45cf-bd75-702cb0ebc8c3';

-- Vérification : il ne reste que le Premium éleveur actif.
SELECT plan_code, statut, profile_id, created_at
FROM abonnements
WHERE uid = 'xoRHVSob5uTWm3sbl6lKWFuIgKF2' AND profil_type = 'eleveur'
ORDER BY created_at DESC;
