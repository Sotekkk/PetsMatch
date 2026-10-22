-- Lieux pet-friendly — étape 5 (avis) : critères adaptés, date de modification,
-- droits séparés auteur / établissement.
--   • 4 critères : appréciation générale (note), accueil des animaux
--     (note_accueil), conformité des conditions annoncées (note_conformite),
--     aménagements pour les animaux (note_amenagements) — les 2 derniers
--     facultatifs.
--   • modifie_le : affichée quand l'auteur modifie son avis.
--   • L'établissement (gestionnaire, abonné ou non) peut seulement répondre :
--     il ne peut ni modifier ni masquer un avis (contestation → modération).
-- À lancer après migration_lieux_communautaires.sql.
BEGIN;

ALTER TABLE public.petfriendly_reviews
  ADD COLUMN IF NOT EXISTS note_conformite   smallint CHECK (note_conformite BETWEEN 1 AND 5),
  ADD COLUMN IF NOT EXISTS note_amenagements smallint CHECK (note_amenagements BETWEEN 1 AND 5),
  ADD COLUMN IF NOT EXISTS modifie_le        timestamptz;

-- Auteur : son contenu ; établissement : sa réponse uniquement.
CREATE OR REPLACE FUNCTION public.pf_avis_garde()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
  v_sub text := auth.jwt() ->> 'sub';
  v_reponse text := NEW.reponse_pro;
BEGIN
  IF coalesce(auth.jwt() ->> 'role', '') = 'service_role' THEN RETURN NEW; END IF;
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

-- Note moyenne / nombre d'avis du lieu : seulement les avis publiés (un avis
-- masqué par la modération ne compte plus), et calculés avec les droits du
-- système — un membre n'a pas le droit de modifier la fiche du lieu, la mise à
-- jour lancée par son avis était donc ignorée sans erreur.
CREATE OR REPLACE FUNCTION public.fn_update_place_rating()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  pid uuid := COALESCE(NEW.place_id, OLD.place_id);
BEGIN
  UPDATE petfriendly_places SET
    nb_avis      = (SELECT COUNT(*) FROM petfriendly_reviews WHERE place_id = pid AND statut = 'actif'),
    note_moyenne = COALESCE((SELECT AVG(note) FROM petfriendly_reviews WHERE place_id = pid AND statut = 'actif'), 0)
  WHERE id = pid;
  RETURN NEW;
END $$;

-- Rattrapage des compteurs.
UPDATE petfriendly_places p SET
  nb_avis      = (SELECT COUNT(*) FROM petfriendly_reviews r WHERE r.place_id = p.id AND r.statut = 'actif'),
  note_moyenne = COALESCE((SELECT AVG(note) FROM petfriendly_reviews r WHERE r.place_id = p.id AND r.statut = 'actif'), 0);

DROP TRIGGER IF EXISTS trg_pf_avis_garde ON public.petfriendly_reviews;
CREATE TRIGGER trg_pf_avis_garde
  BEFORE UPDATE ON public.petfriendly_reviews
  FOR EACH ROW EXECUTE FUNCTION public.pf_avis_garde();

COMMIT;
