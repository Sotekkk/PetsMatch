-- « Mes clients » : ajoute les pensionnaires (pension_entrees), qui n'y figuraient
-- que s'ils avaient un accès à la fiche ou un RDV. Coordonnées : celles saisies par
-- la pension sur le séjour, jamais les colonnes privées d'un compte.
-- Par profil : uniquement les séjours de CE profil. Idempotent.
-- Base : migration_mes_clients.sql (seul ajout, la 3e source de « lignes »).

CREATE OR REPLACE FUNCTION public.pm_mes_clients(p_profile uuid)
RETURNS TABLE (animal_id text, animal_nom text, espece text, identification text,
               client_nom text, telephone text, email text,
               client_uid text, client_profile_id uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_profile IS NULL OR NOT (public.pm_gere_clinique(p_profile)
      OR public.pm_employe_profil(p_profile, ARRAY['vet_patients', 'vet_agenda'])) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH suivis AS (
    SELECT a.id AS aid, a.nom AS anom, a.espece AS aesp, a.identification AS aident,
           coalesce(acp.client_id, a.client_clinique_id) AS cid,
           pr.uid_proprio AS ouid, pr.profile_id_proprio AS oprof,
           1 AS prio, now() AS quand
      FROM animal_access aa
      JOIN animaux a ON a.id = aa.animal_id
      LEFT JOIN animaux_clients_pro acp ON acp.animal_id = a.id AND acp.pro_profile_id = p_profile
      LEFT JOIN LATERAL (
        SELECT p.uid_proprio, p.profile_id_proprio FROM animaux_proprietes p
         WHERE p.animal_id = a.id AND p.role_proprio = 'principal' AND p.statut = 'actif' AND p.date_fin IS NULL
         LIMIT 1) pr ON true
     WHERE aa.pro_profile_id = p_profile AND aa.statut <> 'revoked'
  ),
  lignes AS (
    SELECT s.aid, s.anom, s.aesp, s.aident,
           CASE WHEN c.id IS NOT NULL THEN trim(coalesce(c.prenom, '') || ' ' || c.nom) END AS cnom,
           c.telephone AS ctel, c.email AS cmail,
           CASE WHEN c.id IS NULL THEN s.ouid END AS cuid,
           CASE WHEN c.id IS NULL THEN s.oprof END AS cprof,
           s.prio, s.quand
      FROM suivis s LEFT JOIN clients_clinique c ON c.id = s.cid
    UNION ALL
    SELECT r.animal_id, coalesce(a.nom, r.animal_nom_manuel), a.espece, a.identification,
           CASE WHEN r.client_uid IS NULL THEN r.client_nom_manuel END,
           CASE WHEN r.client_uid IS NULL THEN r.client_telephone_manuel END,
           CASE WHEN r.client_uid IS NULL THEN r.client_email_manuel END,
           r.client_uid, CASE WHEN r.client_uid IS NOT NULL THEN r.client_profile_id END,
           2, r.date_heure
      FROM rdv r LEFT JOIN animaux a ON a.id = r.animal_id
     WHERE r.pro_profile_id = p_profile::text AND r.statut NOT IN ('annule', 'refuse')
       AND (r.client_uid IS NOT NULL OR coalesce(trim(r.client_nom_manuel), '') <> '')
    UNION ALL
    SELECT pe.animal_id, pe.animal_nom, pe.espece, pe.puce,
           NULLIF(trim(pe.proprietaire_nom), ''), pe.proprietaire_contact, pe.proprietaire_email,
           NULL::text, NULL::uuid,
           3, pe.date_entree::timestamptz
      FROM pension_entrees pe
     WHERE pe.pro_profile_id = p_profile::text
       AND coalesce(trim(pe.animal_nom), '') <> ''
  ),
  uniques AS (
    SELECT DISTINCT ON (coalesce(l.aid,
             coalesce(l.cuid, lower(trim(l.cnom))) || '|' || lower(trim(coalesce(l.anom, '')))))
           l.*
      FROM lignes l
     ORDER BY coalesce(l.aid,
             coalesce(l.cuid, lower(trim(l.cnom))) || '|' || lower(trim(coalesce(l.anom, '')))),
              l.prio, l.quand DESC
  )
  SELECT u.aid, coalesce(u.anom, ''), coalesce(u.aesp, ''), coalesce(u.aident, ''),
         coalesce(NULLIF(u.cnom, ''),
                  NULLIF(trim(coalesce(up.firstname, '') || ' ' || coalesce(up.lastname, '')), ''),
                  NULLIF(trim(coalesce(us.firstname, '') || ' ' || coalesce(us.lastname, '')), ''),
                  NULLIF(trim(up.nom), ''), ''),
         coalesce(u.ctel, ''), coalesce(u.cmail, ''), u.cuid, u.cprof
    FROM uniques u
    LEFT JOIN user_profiles up ON up.id = u.cprof
    LEFT JOIN users us ON us.uid = u.cuid
   ORDER BY lower(coalesce(u.anom, '')), lower(coalesce(u.cnom, ''));
END $$;
GRANT EXECUTE ON FUNCTION public.pm_mes_clients(uuid) TO anon, authenticated;
NOTIFY pgrst, 'reload schema';
