-- Registre sanitaire ← visites vétérinaires (03/11/2026).
--
-- Les éleveurs et associations doivent tenir leurs visites vétérinaires au
-- registre sanitaire. Deux sources, inscrites automatiquement au registre du
-- propriétaire (profil élevage ou association) de l'animal :
--   • comptes_rendus validés par le vétérinaire (consultation faite sur
--     PetsMatch) — le vétérinaire n'a pas le droit d'écrire dans le registre
--     de l'élevage, d'où une fonction SECURITY DEFINER ;
--   • visites saisies au carnet (éleveur / association, ou vétérinaire).
-- N° des ordonnances validées de la consultation repris sur la ligne.
-- Une ligne par source (source_table, source_id : index unique existant) :
-- mise à jour si la source change, supprimée si la source est supprimée ou
-- si le compte rendu repasse en brouillon. Propriétaire = propriétaire actif
-- (principal d'abord) dont le profil est « eleveur » ou « association » ;
-- rien pour un particulier. Idempotent.

BEGIN;

-- N° d'ordonnance saisi avec la visite (carnet / registre).
ALTER TABLE public.visites ADD COLUMN IF NOT EXISTS ordonnance_num TEXT;

-- Signature changée (n° d'ordonnance) : ancienne version retirée.
DROP FUNCTION IF EXISTS public.pm_registre_visite_ecrire(text, text, text, date, text, text, text);

CREATE OR REPLACE FUNCTION public.pm_registre_visite_ecrire(
  p_source_table text, p_source_id text, p_animal_id text,
  p_date date, p_intervenant text, p_description text, p_source text, p_ordonnance text DEFAULT '')
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  o RECORD;
  a RECORD;
BEGIN
  IF p_animal_id IS NULL OR p_date IS NULL THEN RETURN; END IF;
  SELECT ap.uid_proprio::text AS uid, ap.profile_id_proprio AS profile_id, up.profile_type
    INTO o
    FROM animaux_proprietes ap
    JOIN user_profiles up ON up.id::text = ap.profile_id_proprio::text
   WHERE ap.animal_id::text = p_animal_id AND ap.statut = 'actif' AND ap.date_fin IS NULL
     AND up.profile_type IN ('eleveur', 'association')
   ORDER BY (ap.role_proprio = 'principal') DESC, ap.date_debut NULLS LAST
   LIMIT 1;
  -- Pas d'élevage / association propriétaire : rien (une ligne déjà au
  -- registre reste, c'est l'historique de l'ancien propriétaire).
  IF o.uid IS NULL THEN RETURN; END IF;
  SELECT nom, espece, date_naissance, identification, sexe INTO a FROM animaux WHERE id::text = p_animal_id;
  INSERT INTO registre_sanitaire (id, uid_eleveur, eleveur_profile_id, animal_id, animal_nom, espece,
      date_naissance, identification, sexe, date_acte, type_acte, intervenant, description,
      ordonnance_num, profil_source, source, source_table, source_id)
  VALUES (gen_random_uuid()::text, o.uid, o.profile_id::uuid, p_animal_id, coalesce(a.nom, ''), coalesce(a.espece, ''),
      a.date_naissance, coalesce(a.identification, ''), coalesce(a.sexe, ''), p_date, 'visite',
      coalesce(p_intervenant, ''), coalesce(p_description, 'Visite vétérinaire'), coalesce(p_ordonnance, ''),
      o.profile_type, p_source, p_source_table, p_source_id)
  ON CONFLICT (source_table, source_id) WHERE source_table IS NOT NULL AND source_id IS NOT NULL
  -- Ligne existante : le registre reste celui où elle a été inscrite
  -- (propriétaire au moment de l'acte, même après une cession).
  DO UPDATE SET animal_id = EXCLUDED.animal_id, animal_nom = EXCLUDED.animal_nom, espece = EXCLUDED.espece,
      date_naissance = EXCLUDED.date_naissance, identification = EXCLUDED.identification, sexe = EXCLUDED.sexe,
      date_acte = EXCLUDED.date_acte, type_acte = 'visite', intervenant = EXCLUDED.intervenant,
      description = EXCLUDED.description, ordonnance_num = EXCLUDED.ordonnance_num, source = EXCLUDED.source;
END;
$function$;

-- Compte rendu de consultation validé → visite au registre.
CREATE OR REPLACE FUNCTION public.pm_registre_cr_ecrire(p_cr_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  c RECORD;
  v_clinique text;
  v_praticien text;
  v_motif text;
  v_ordo text;
BEGIN
  SELECT * INTO c FROM comptes_rendus WHERE id = p_cr_id;
  IF c.id IS NULL OR c.statut IS DISTINCT FROM 'valide' THEN RETURN; END IF;
  SELECT nullif(trim(coalesce(nom, '')), '') INTO v_clinique FROM user_profiles_complet WHERE id = c.pro_profile_id;
  SELECT nullif(trim(coalesce(firstname, '') || ' ' || coalesce(lastname, '')), '') INTO v_praticien
    FROM user_profiles_complet WHERE id = coalesce(c.valide_par_profile_id, c.redige_par_profile_id);
  IF c.rdv_id IS NOT NULL THEN
    SELECT nullif(trim(coalesce(motif, '')), '') INTO v_motif FROM rdv WHERE id = c.rdv_id;
  END IF;
  v_motif := coalesce(v_motif, nullif(trim(split_part(coalesce(c.contenu, ''), chr(10), 1)), ''));
  -- N° des ordonnances validées de la consultation : liées au compte rendu,
  -- sinon au RDV, sinon même animal / même cabinet / même jour.
  SELECT string_agg(DISTINCT o.numero, ', ') INTO v_ordo
    FROM ordonnances o
   WHERE o.statut IN ('validee', 'signee') AND nullif(trim(coalesce(o.numero, '')), '') IS NOT NULL
     AND (o.cr_id = c.id
          OR (c.rdv_id IS NOT NULL AND o.rdv_id = c.rdv_id AND o.animal_id::text = c.animal_id::text)
          OR (o.cr_id IS NULL AND o.rdv_id IS NULL AND o.animal_id::text = c.animal_id::text
              AND o.pro_profile_id = c.pro_profile_id
              AND (o.created_at AT TIME ZONE 'Europe/Paris')::date = (c.created_at AT TIME ZONE 'Europe/Paris')::date));
  PERFORM pm_registre_visite_ecrire('comptes_rendus', c.id::text, c.animal_id::text,
    (coalesce(c.valide_le, c.created_at) AT TIME ZONE 'Europe/Paris')::date,
    concat_ws(' — ', v_praticien, CASE WHEN v_clinique IS DISTINCT FROM v_praticien THEN v_clinique END),
    'Consultation' || coalesce(' : ' || left(v_motif, 200), ''),
    'veterinaire', coalesce(v_ordo, ''));
END;
$function$;

CREATE OR REPLACE FUNCTION public.pm_registre_depuis_cr()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM registre_sanitaire WHERE source_table = 'comptes_rendus' AND source_id = OLD.id::text;
    RETURN OLD;
  END IF;
  IF NEW.statut IS DISTINCT FROM 'valide' THEN
    DELETE FROM registre_sanitaire WHERE source_table = 'comptes_rendus' AND source_id = NEW.id::text;
  ELSE
    PERFORM pm_registre_cr_ecrire(NEW.id);
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_registre_depuis_cr ON public.comptes_rendus;
CREATE TRIGGER trg_registre_depuis_cr
  AFTER INSERT OR UPDATE OF statut, contenu, valide_le, animal_id OR DELETE ON public.comptes_rendus
  FOR EACH ROW EXECUTE FUNCTION public.pm_registre_depuis_cr();

-- Ordonnance validée (souvent après le compte rendu) : n° repris sur la
-- ligne de la consultation.
CREATE OR REPLACE FUNCTION public.pm_registre_depuis_ordonnance()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  o RECORD;
  x RECORD;
BEGIN
  o := CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  FOR x IN
    SELECT c.id FROM comptes_rendus c
     WHERE c.statut = 'valide'
       AND (c.id = o.cr_id
            OR (o.rdv_id IS NOT NULL AND c.rdv_id = o.rdv_id AND c.animal_id::text = o.animal_id::text)
            OR (o.cr_id IS NULL AND o.rdv_id IS NULL AND c.animal_id::text = o.animal_id::text
                AND c.pro_profile_id = o.pro_profile_id
                AND (c.created_at AT TIME ZONE 'Europe/Paris')::date = (o.created_at AT TIME ZONE 'Europe/Paris')::date))
  LOOP
    PERFORM pm_registre_cr_ecrire(x.id);
  END LOOP;
  RETURN o;
END;
$function$;

DROP TRIGGER IF EXISTS trg_registre_depuis_ordonnance ON public.ordonnances;
CREATE TRIGGER trg_registre_depuis_ordonnance
  AFTER INSERT OR UPDATE OF statut, numero, cr_id, rdv_id OR DELETE ON public.ordonnances
  FOR EACH ROW EXECUTE FUNCTION public.pm_registre_depuis_ordonnance();

-- Visite saisie au carnet → visite au registre.
CREATE OR REPLACE FUNCTION public.pm_registre_depuis_visite()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_diag text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM registre_sanitaire WHERE source_table = 'visites' AND source_id = OLD.id::text;
    RETURN OLD;
  END IF;
  v_diag := nullif(trim(coalesce(NEW.diagnostic, '')), '');
  PERFORM pm_registre_visite_ecrire('visites', NEW.id::text, NEW.animal_id::text, NEW.date,
    NEW.veterinaire,
    coalesce(nullif(trim(coalesce(NEW.motif, '')), ''), 'Visite vétérinaire') || coalesce(' — ' || v_diag, ''),
    coalesce(NEW.source, 'eleveur'), coalesce(trim(NEW.ordonnance_num), ''));
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_registre_depuis_visite ON public.visites;
CREATE TRIGGER trg_registre_depuis_visite
  AFTER INSERT OR UPDATE OR DELETE ON public.visites
  FOR EACH ROW EXECUTE FUNCTION public.pm_registre_depuis_visite();

REVOKE ALL ON FUNCTION public.pm_registre_visite_ecrire(text, text, text, date, text, text, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pm_registre_cr_ecrire(uuid) FROM PUBLIC, anon, authenticated;

-- Reprise : comptes rendus validés et visites déjà saisies.
SELECT pm_registre_visite_ecrire('visites', v.id::text, v.animal_id::text, v.date, v.veterinaire,
    coalesce(nullif(trim(coalesce(v.motif, '')), ''), 'Visite vétérinaire') || coalesce(' — ' || nullif(trim(coalesce(v.diagnostic, '')), ''), ''),
    coalesce(v.source, 'eleveur'), coalesce(trim(v.ordonnance_num), ''))
  FROM visites v
 WHERE v.date IS NOT NULL
   -- déjà au registre (lien source, ou ancienne saisie sans lien le même jour)
   AND NOT EXISTS (SELECT 1 FROM registre_sanitaire r WHERE r.source_table = 'visites' AND r.source_id = v.id::text)
   AND NOT EXISTS (SELECT 1 FROM registre_sanitaire r WHERE r.animal_id = v.animal_id::text AND r.type_acte = 'visite' AND r.date_acte = v.date);
SELECT pm_registre_cr_ecrire(c.id) FROM comptes_rendus c WHERE c.statut = 'valide';

COMMIT;
