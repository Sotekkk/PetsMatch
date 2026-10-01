-- ════════════════════════════════════════════════════════════════════════
-- Correctif des migrations RLS du 30/09 : triggers qui écrivent pour
-- QUELQU'UN D'AUTRE avec les droits de l'appelant.
--
-- Tant que les tables étaient ouvertes (USING true), ces triggers
-- fonctionnaient avec les droits de l'utilisateur. Depuis le 30/09 :
--   • sync_rdv_agenda (rdv) : le PRO qui confirme un RDV crée l'événement
--     dans l'agenda du CLIENT → refusé → TOUTE la confirmation échouait
--     (42501). Annulation : l'événement du client n'était plus retiré ;
--   • fn_update_pro_rating (avis_pro) : l'avis d'un client recalcule la
--     note du PRO → mise à jour refusée en silence, note figée ;
--   • fanout_notif_coproprietaires (notifications) : la recherche des
--     co-propriétaires passait par la RLS de l'appelant → copies perdues ;
--   • delete_promenade_notifications / delete_balade_ludique_notifications :
--     suppression d'une promenade → notifications des participants restées.
-- Ces fonctions ne font que des écritures dérivées et contrôlées par le
-- trigger (pas d'entrée libre de l'utilisateur) : SECURITY DEFINER.
-- ════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER FUNCTION public.sync_rdv_agenda() SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.fn_update_pro_rating() SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.fanout_notif_coproprietaires() SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.delete_promenade_notifications() SECURITY DEFINER SET search_path = public;
ALTER FUNCTION public.delete_balade_ludique_notifications() SECURITY DEFINER SET search_path = public;

COMMIT;
