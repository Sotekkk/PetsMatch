-- ══════════════════════════════════════════════════════════════════════════
-- Pet-sitter / promeneur : places comptées en ANIMAUX (06/11/2026)
-- ══════════════════════════════════════════════════════════════════════════
-- La réservation compte les places d'un créneau (creneaux_pro.capacite) en
-- nombre d'animaux : une demande pour 2 chiens prend 2 places. Le client ne
-- lit que SES rdv (RLS) ; cette fonction rend, pour un profil pro, les RDV
-- en cours (demande / confirmé) avec leur nombre d'animaux, sans donnée
-- personnelle (même principe que pm_plages_occupees).
-- Sans cette fonction, l'appli et le site comptent 1 animal par RDV.
-- ══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.pm_garde_occupation(p_pro_profile_id text, p_debut timestamptz, p_fin timestamptz)
RETURNS TABLE (date_heure timestamptz, duree_minutes integer, motif text, nb_animaux integer)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT r.date_heure, coalesce(r.duree_minutes, 30), r.motif,
         greatest(1, CASE WHEN jsonb_typeof(r.animaux_ids) = 'array' THEN jsonb_array_length(r.animaux_ids) ELSE 0 END)
    FROM rdv r
   WHERE r.pro_profile_id = p_pro_profile_id
     AND r.statut IN ('confirme', 'demande')
     AND r.date_heure < p_fin
     AND r.date_heure + make_interval(mins => coalesce(r.duree_minutes, 30)) > p_debut;
$$;

REVOKE ALL ON FUNCTION public.pm_garde_occupation(text, timestamptz, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pm_garde_occupation(text, timestamptz, timestamptz) TO anon, authenticated;

COMMIT;

-- Vérification : une ligne par RDV à venir du profil pro, avec nb_animaux.
-- SELECT * FROM pm_garde_occupation('<pro_profile_id>', now(), now() + interval '30 days');
