-- Mise à jour des price IDs Stripe TEST MODE dans produits_ponctuels
-- Produits créés automatiquement via API Stripe le 2026-06-11

UPDATE public.produits_ponctuels SET stripe_price_id = 'price_1ThCAw2MpEB6OUl54KX3llIX' WHERE code = 'annonce_sup';
UPDATE public.produits_ponctuels SET stripe_price_id = 'price_1ThCAx2MpEB6OUl5plnPZTtY' WHERE code = 'boost_48h';
UPDATE public.produits_ponctuels SET stripe_price_id = 'price_1ThCAx2MpEB6OUl5U2422Um2' WHERE code = 'mise_une';
UPDATE public.produits_ponctuels SET stripe_price_id = 'price_1ThCAy2MpEB6OUl52JTji4ld' WHERE code = 'remontee';
UPDATE public.produits_ponctuels SET stripe_price_id = 'price_1ThCAy2MpEB6OUl5IgKgDy8U' WHERE code = 'pack_3boosts';

-- Mise à jour des price IDs dans plans_tarifaires
UPDATE public.plans_tarifaires SET
  stripe_price_id_mensuel = 'price_1ThCA62MpEB6OUl5o9kp56Qz',
  stripe_price_id_annuel  = 'price_1ThCA72MpEB6OUl55NHMLVAP'
WHERE profil_type = 'eleveur' AND plan_code = 'pro';

UPDATE public.plans_tarifaires SET
  stripe_price_id_mensuel = 'price_1ThCAK2MpEB6OUl5u3B07u6b',
  stripe_price_id_annuel  = 'price_1ThCAK2MpEB6OUl5tJVNsjzB'
WHERE profil_type = 'eleveur' AND plan_code = 'premium';
