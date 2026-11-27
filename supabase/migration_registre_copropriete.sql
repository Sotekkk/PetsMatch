-- ══════════════════════════════════════════════════════════════════════════
-- Registre ← carnet : copropriété (27/11/2026)
-- ══════════════════════════════════════════════════════════════════════════
-- Suite de migration_registre_depuis_carnet.sql. Un animal en copropriété
-- (animaux_proprietes : principal + secondaire) n'était inscrit qu'au
-- registre du propriétaire PRINCIPAL : un copropriétaire secondaire (ex.
-- Vaina) ne pouvait ni voir ses soins arriver dans son registre, ni les
-- rattraper. Désormais : le registre de la personne qui saisit / rattrape,
-- si elle est (co)propriétaire de l'animal ; sinon le principal, comme avant.
-- (Une ligne par soin : un soin déjà inscrit chez l'autre propriétaire n'est
-- pas recopié.)
-- ══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.pm_registre_soin_ecrire(
  p_source_table text, p_source_id text, p_animal_id text, p_date date,
  p_type text, p_intervenant text, p_description text, p_source text DEFAULT 'carnet')
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  o RECORD;
  a RECORD;
  v_inter text := nullif(trim(coalesce(p_intervenant, '')), '');
BEGIN
  IF p_animal_id IS NULL OR p_date IS NULL OR p_type IS NULL THEN RETURN false; END IF;
  SELECT ap.uid_proprio::text AS uid, ap.profile_id_proprio AS profile_id, up.profile_type
    INTO o
    FROM animaux_proprietes ap
    JOIN user_profiles up ON up.id::text = ap.profile_id_proprio::text
   WHERE ap.animal_id::text = p_animal_id AND ap.statut = 'actif' AND ap.date_fin IS NULL
     AND up.profile_type IN ('eleveur', 'association')
   -- Copropriété : le registre de celui qui saisit le soin s'il est propriétaire,
   -- sinon celui du propriétaire principal.
   ORDER BY (ap.uid_proprio::text = coalesce(auth.jwt() ->> 'sub', '')) DESC, (ap.role_proprio = 'principal') DESC, ap.date_debut NULLS LAST
   LIMIT 1;
  IF o.uid IS NULL THEN RETURN false; END IF;
  -- « Administré par » vide : la personne qui a saisi le soin.
  IF v_inter IS NULL AND (auth.jwt() ->> 'sub') IS NOT NULL THEN
    SELECT nullif(trim(concat_ws(' ', firstname, lastname)), '') INTO v_inter FROM users WHERE uid = auth.jwt() ->> 'sub';
  END IF;
  SELECT nom, espece, date_naissance, identification, sexe INTO a FROM animaux WHERE id::text = p_animal_id;
  INSERT INTO registre_sanitaire (id, uid_eleveur, eleveur_profile_id, animal_id, animal_nom, espece,
      date_naissance, identification, sexe, date_acte, type_acte, intervenant, description,
      ordonnance_num, profil_source, source, source_table, source_id)
  VALUES (gen_random_uuid()::text, o.uid, o.profile_id::uuid, p_animal_id, coalesce(a.nom, ''), coalesce(a.espece, ''),
      a.date_naissance, coalesce(a.identification, ''), coalesce(a.sexe, ''), p_date, p_type,
      coalesce(v_inter, ''), coalesce(p_description, ''), '', o.profile_type, p_source, p_source_table, p_source_id)
  ON CONFLICT (source_table, source_id) WHERE source_table IS NOT NULL AND source_id IS NOT NULL
  -- Ligne existante : reste au registre où elle a été inscrite.
  DO UPDATE SET animal_id = EXCLUDED.animal_id, animal_nom = EXCLUDED.animal_nom, espece = EXCLUDED.espece,
      date_naissance = EXCLUDED.date_naissance, identification = EXCLUDED.identification, sexe = EXCLUDED.sexe,
      date_acte = EXCLUDED.date_acte, type_acte = EXCLUDED.type_acte,
      intervenant = CASE WHEN EXCLUDED.intervenant <> '' THEN EXCLUDED.intervenant ELSE registre_sanitaire.intervenant END,
      description = EXCLUDED.description;
  RETURN true;
END;
$function$;

CREATE OR REPLACE FUNCTION public.pm_registre_completer(p_animal_ids text[], p_simuler boolean DEFAULT true)
 RETURNS TABLE (id_animal text, nb_a_ajouter integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_sub text := auth.jwt() ->> 'sub';
  v_id text;
  o RECORD;
  s RECORD;
  v_type text;
  v_inter text;
  v_desc text;
  v_cle text;
  n integer;
BEGIN
  IF v_sub IS NULL THEN RETURN; END IF;
  FOREACH v_id IN ARRAY coalesce(p_animal_ids, ARRAY[]::text[]) LOOP
    SELECT ap.uid_proprio::text AS uid, ap.profile_id_proprio AS profile_id INTO o
      FROM animaux_proprietes ap
      JOIN user_profiles up ON up.id::text = ap.profile_id_proprio::text
     WHERE ap.animal_id::text = v_id AND ap.statut = 'actif' AND ap.date_fin IS NULL
       AND up.profile_type IN ('eleveur', 'association')
     -- Copropriété : le registre du connecté s'il est (co)propriétaire.
     ORDER BY (ap.uid_proprio::text = v_sub) DESC, (ap.role_proprio = 'principal') DESC, ap.date_debut NULLS LAST
     LIMIT 1;
    CONTINUE WHEN o.uid IS NULL;
    CONTINUE WHEN NOT can_access_registre_sanitaire(o.uid, o.profile_id::uuid, v_sub, true);
    n := 0;
    FOR s IN
      SELECT 'vaccinations' AS t, x.id::text AS id, x.date, to_jsonb(x) AS j FROM vaccinations x WHERE x.animal_id::text = v_id
      UNION ALL SELECT 'vermifuges', x.id::text, x.date, to_jsonb(x) FROM vermifuges x WHERE x.animal_id::text = v_id
      UNION ALL SELECT 'antiparasitaires', x.id::text, x.date, to_jsonb(x) FROM antiparasitaires x WHERE x.animal_id::text = v_id
      UNION ALL SELECT 'traitements', x.id::text, x.date, to_jsonb(x) FROM traitements x WHERE x.animal_id::text = v_id
      UNION ALL SELECT 'visites', x.id::text, x.date, to_jsonb(x) FROM visites x WHERE x.animal_id::text = v_id
    LOOP
      CONTINUE WHEN s.date IS NULL;
      CONTINUE WHEN s.t = 'traitements' AND NOT pm_registre_traitement_premiere_etape(s.j);
      IF s.t = 'visites' THEN
        v_type := 'visite';
        v_inter := coalesce(s.j ->> 'veterinaire', '');
        v_desc := coalesce(nullif(trim(coalesce(s.j ->> 'motif', '')), ''), 'Visite vétérinaire')
            || coalesce(' — ' || nullif(trim(coalesce(s.j ->> 'diagnostic', '')), ''), '');
      ELSE
        SELECT x.type_acte, x.intervenant, x.description INTO v_type, v_inter, v_desc FROM pm_registre_soin_libelle(s.t, s.j) x;
      END IF;
      -- Déjà au registre : lié à ce soin, ou saisi à la main le même jour, même
      -- type, même produit (vaccin / produit / traitement / motif).
      v_cle := lower(trim(coalesce(s.j ->> 'vaccin', s.j ->> 'produit', s.j ->> 'nom', s.j ->> 'motif', '')));
      CONTINUE WHEN EXISTS (SELECT 1 FROM registre_sanitaire r WHERE r.source_table = s.t AND r.source_id = s.id);
      CONTINUE WHEN EXISTS (SELECT 1 FROM registre_sanitaire r
        WHERE r.animal_id = v_id AND r.type_acte = v_type AND r.date_acte = s.date AND r.source_table IS NULL
          AND (v_cle = '' OR lower(coalesce(r.description, '')) LIKE '%' || v_cle || '%'));
      IF NOT p_simuler THEN
        IF s.t = 'visites' THEN
          PERFORM pm_registre_visite_ecrire('visites', s.id, v_id, s.date, s.j ->> 'veterinaire', v_desc,
            coalesce(s.j ->> 'source', 'eleveur'), coalesce(trim(s.j ->> 'ordonnance_num'), ''));
        ELSE
          PERFORM pm_registre_soin_ecrire(s.t, s.id, v_id, s.date, v_type, v_inter, v_desc,
            coalesce(s.j ->> 'source', 'carnet'));
        END IF;
      END IF;
      n := n + 1;
    END LOOP;
    id_animal := v_id; nb_a_ajouter := n;
    RETURN NEXT;
  END LOOP;
END;
$function$;

REVOKE ALL ON FUNCTION public.pm_registre_soin_ecrire(text, text, text, date, text, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pm_registre_completer(text[], boolean) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
COMMIT;

-- Retour arrière : réexécuter les deux fonctions de migration_registre_depuis_carnet.sql.
