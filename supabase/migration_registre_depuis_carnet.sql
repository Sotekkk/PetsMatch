-- ══════════════════════════════════════════════════════════════════════════
-- Registre sanitaire ← carnet de santé (27/11/2026)
-- ══════════════════════════════════════════════════════════════════════════
-- Demande : les carnets sont à jour mais pas le registre.
--   1) Chaque vaccin, vermifuge, antiparasitaire et traitement saisi au carnet
--      (quel que soit l'écran : fiche, portée, tâche de protocole, vétérinaire,
--      import…) est inscrit au registre du PROPRIÉTAIRE (profil élevage ou
--      association), comme les visites (migration_registre_visites_veto.sql).
--      Une ligne par soin (source_table, source_id : index unique existant),
--      mise à jour si le soin change, supprimée s'il est supprimé.
--      Traitement en plusieurs étapes : une seule ligne (la première étape).
--   2) pm_registre_completer(animaux, simuler) : rattrapage AU CHOIX des soins
--      déjà au carnet. Simulation = nombre de lignes qui seraient ajoutées par
--      animal. Pas de doublon : ni un soin déjà lié, ni une ligne saisie à la
--      main dans le registre le même jour, du même type et du même produit.
--      (Deux vaccins différents le même jour = deux lignes.)
-- Rien pour un animal de particulier. Idempotent.
-- À passer d'abord sur le staging.
-- ══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ── Écriture d'un soin au registre du propriétaire ──────────────────────────
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
   ORDER BY (ap.role_proprio = 'principal') DESC, ap.date_debut NULLS LAST
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

-- ── Libellé d'un soin (type, intervenant, description) — même texte que la fiche ─
CREATE OR REPLACE FUNCTION public.pm_registre_soin_libelle(p_table text, j jsonb,
  OUT type_acte text, OUT intervenant text, OUT description text)
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  f text;
BEGIN
  intervenant := coalesce(j ->> 'veterinaire', '');
  CASE p_table
    WHEN 'vaccinations' THEN
      type_acte := 'vaccination';
      f := nullif(trim(coalesce(j ->> 'lot', '')), '');
      description := 'Vaccin : ' || coalesce(j ->> 'vaccin', '') || coalesce(' (lot ' || f || ')', '');
    WHEN 'vermifuges' THEN
      type_acte := 'vermifuge';
      f := nullif(trim(coalesce(j ->> 'dosage', '')), '');
      description := coalesce(j ->> 'produit', '') || coalesce(' — ' || f, '');
    WHEN 'antiparasitaires' THEN
      type_acte := 'antiparasitaire';
      description := coalesce(j ->> 'produit', '');
    WHEN 'traitements' THEN
      type_acte := 'traitement';
      f := nullif(trim(coalesce(j ->> 'posologie', '')), '');
      description := coalesce(j ->> 'nom', '') || coalesce(' — ' || f, '');
    ELSE
      type_acte := NULL;
  END CASE;
END;
$function$;

-- Traitement en étapes (groupe_id) : seule la première étape va au registre.
CREATE OR REPLACE FUNCTION public.pm_registre_traitement_premiere_etape(j jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT nullif(j ->> 'groupe_id', '') IS NULL OR NOT EXISTS (
    SELECT 1 FROM traitements t
     WHERE to_jsonb(t) ->> 'groupe_id' = j ->> 'groupe_id' AND t.id <> j ->> 'id'
       AND (t.date < (j ->> 'date')::date OR (t.date = (j ->> 'date')::date AND t.id < j ->> 'id')));
$function$;

-- ── Déclencheur commun aux quatre tables du carnet ──────────────────────────
CREATE OR REPLACE FUNCTION public.pm_registre_depuis_soin()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  j jsonb;
  l RECORD;
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM registre_sanitaire WHERE source_table = TG_TABLE_NAME AND source_id = OLD.id::text;
    RETURN OLD;
  END IF;
  j := to_jsonb(NEW);
  IF TG_TABLE_NAME = 'traitements' AND NOT pm_registre_traitement_premiere_etape(j) THEN RETURN NEW; END IF;
  SELECT * INTO l FROM pm_registre_soin_libelle(TG_TABLE_NAME, j);
  IF NEW.date IS NULL THEN
    DELETE FROM registre_sanitaire WHERE source_table = TG_TABLE_NAME AND source_id = NEW.id::text;
    RETURN NEW;
  END IF;
  PERFORM pm_registre_soin_ecrire(TG_TABLE_NAME, NEW.id::text, NEW.animal_id::text, NEW.date,
    l.type_acte, l.intervenant, l.description, coalesce(j ->> 'source', 'carnet'));
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_registre_depuis_soin ON public.vaccinations;
CREATE TRIGGER trg_registre_depuis_soin AFTER INSERT OR UPDATE OR DELETE ON public.vaccinations
  FOR EACH ROW EXECUTE FUNCTION public.pm_registre_depuis_soin();
DROP TRIGGER IF EXISTS trg_registre_depuis_soin ON public.vermifuges;
CREATE TRIGGER trg_registre_depuis_soin AFTER INSERT OR UPDATE OR DELETE ON public.vermifuges
  FOR EACH ROW EXECUTE FUNCTION public.pm_registre_depuis_soin();
DROP TRIGGER IF EXISTS trg_registre_depuis_soin ON public.antiparasitaires;
CREATE TRIGGER trg_registre_depuis_soin AFTER INSERT OR UPDATE OR DELETE ON public.antiparasitaires
  FOR EACH ROW EXECUTE FUNCTION public.pm_registre_depuis_soin();
DROP TRIGGER IF EXISTS trg_registre_depuis_soin ON public.traitements;
CREATE TRIGGER trg_registre_depuis_soin AFTER INSERT OR UPDATE OR DELETE ON public.traitements
  FOR EACH ROW EXECUTE FUNCTION public.pm_registre_depuis_soin();

-- ── Rattrapage au choix ─────────────────────────────────────────────────────
-- Pour chaque animal demandé dont le connecté tient le registre (propriétaire,
-- cogérant, employé autorisé) : soins du carnet (et visites) pas encore au
-- registre. p_simuler = true : compte seulement.
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
     ORDER BY (ap.role_proprio = 'principal') DESC, ap.date_debut NULLS LAST
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

-- ── Vérification ───────────────────────────────────────────────────────────
SELECT tgname, tgrelid::regclass FROM pg_trigger WHERE tgname = 'trg_registre_depuis_soin';

-- ── Retour arrière ─────────────────────────────────────────────────────────
-- DROP TRIGGER IF EXISTS trg_registre_depuis_soin ON public.vaccinations;
-- DROP TRIGGER IF EXISTS trg_registre_depuis_soin ON public.vermifuges;
-- DROP TRIGGER IF EXISTS trg_registre_depuis_soin ON public.antiparasitaires;
-- DROP TRIGGER IF EXISTS trg_registre_depuis_soin ON public.traitements;
-- DROP FUNCTION IF EXISTS public.pm_registre_depuis_soin();
-- DROP FUNCTION IF EXISTS public.pm_registre_completer(text[], boolean);
-- DROP FUNCTION IF EXISTS public.pm_registre_traitement_premiere_etape(jsonb);
-- DROP FUNCTION IF EXISTS public.pm_registre_soin_libelle(text, jsonb);
-- DROP FUNCTION IF EXISTS public.pm_registre_soin_ecrire(text, text, text, date, text, text, text, text);
