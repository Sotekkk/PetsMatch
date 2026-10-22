-- ════════════════════════════════════════════════════════════════════════
-- Lieux pet-friendly : garde-fous des fiches (pf_garde_moderation) et des avis
-- (pf_avis_garde) alignés sur migration_lieux_suppression_editeur_sql.sql.
--
-- Ils laissaient passer la clé service (API admin) mais annulaient en silence
-- une modification faite à la main dans l'éditeur SQL de Supabase (compte
-- postgres, sans jeton). Les comptes d'administration de la base passent
-- désormais aussi. Les utilisateurs de l'appli et du site (rôles anon /
-- authenticated) restent soumis aux mêmes contrôles.
--
-- À lancer après migration_lieux_communautaires.sql et
-- migration_lieux_avis_criteres.sql. Aucune donnée n'est lue ni modifiée.
-- Retour arrière : relancer les définitions de ces deux migrations.
-- ════════════════════════════════════════════════════════════════════════
BEGIN;

CREATE OR REPLACE FUNCTION public.pf_garde_moderation()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_admin boolean := coalesce(auth.jwt() ->> 'role', '') = 'service_role'
                     OR current_user IN ('postgres', 'supabase_admin');
BEGIN
  IF v_admin THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.statut NOT IN ('brouillon', 'en_attente_validation') THEN NEW.statut := 'en_attente_validation'; END IF;
    NEW.verification := CASE WHEN NEW.uid_pro IS NULL THEN 'non_verifie' ELSE 'en_cours' END;
    NEW.plan := 'decouverte';
    NEW.valide_at := NULL; NEW.valide_par := NULL;
    RETURN NEW;
  END IF;
  -- UPDATE : champs réservés figés.
  NEW.verification := OLD.verification;
  NEW.origine      := OLD.origine;
  NEW.uid_pro      := OLD.uid_pro;
  NEW.ajoute_par_uid := OLD.ajoute_par_uid;
  NEW.plan         := OLD.plan;
  NEW.plan_expire_at := OLD.plan_expire_at;
  NEW.valide_at    := OLD.valide_at;
  NEW.valide_par   := OLD.valide_par;
  NEW.motif_moderation := OLD.motif_moderation;
  -- Statut : le contributeur peut seulement (re)soumettre une fiche brouillon
  -- ou « à corriger » ; le pro garde son statut publié.
  IF NEW.statut IS DISTINCT FROM OLD.statut THEN
    IF NOT (OLD.statut IN ('brouillon', 'a_corriger') AND NEW.statut IN ('brouillon', 'en_attente_validation')) THEN
      NEW.statut := OLD.statut;
    END IF;
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.pf_avis_garde()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_sub text := auth.jwt() ->> 'sub';
  v_reponse text := NEW.reponse_pro;
BEGIN
  IF coalesce(auth.jwt() ->> 'role', '') = 'service_role'
     OR current_user IN ('postgres', 'supabase_admin') THEN RETURN NEW; END IF;
  IF v_sub = OLD.user_uid THEN
    NEW.reponse_pro := OLD.reponse_pro; NEW.reponse_pro_at := OLD.reponse_pro_at;
    NEW.statut := OLD.statut; NEW.place_id := OLD.place_id; NEW.user_uid := OLD.user_uid;
    IF (NEW.note, NEW.note_accueil, NEW.commentaire, NEW.note_conformite, NEW.note_amenagements, NEW.date_visite)
       IS DISTINCT FROM (OLD.note, OLD.note_accueil, OLD.commentaire, OLD.note_conformite, OLD.note_amenagements, OLD.date_visite) THEN
      NEW.modifie_le := now();
    END IF;
    RETURN NEW;
  END IF;
  -- Établissement (la policy d'UPDATE limite déjà au gestionnaire / cogérant).
  NEW := OLD;
  NEW.reponse_pro := nullif(trim(v_reponse), '');
  NEW.reponse_pro_at := CASE WHEN NEW.reponse_pro IS NULL THEN NULL ELSE now() END;
  RETURN NEW;
END $$;

COMMIT;
