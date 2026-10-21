-- ══════════════════════════════════════════════════════════════════════════
-- Groupes — validation des nouveaux membres (comme Facebook)
-- ══════════════════════════════════════════════════════════════════════════
--   • groupes.validation_adhesion (par défaut OUI) : les demandes pour
--     rejoindre passent par l'admin, y compris pour un groupe PUBLIC. Un
--     groupe public reste lisible par tous ; tant que la demande n'est pas
--     acceptée, la personne ne peut ni publier ni commenter (RLS : membre
--     actif requis, cf. migration_rls_tighten_groupes.sql). Un groupe privé
--     exige toujours la validation.
--   • Demande reçue → notification aux admins et modérateurs du groupe ;
--     demande acceptée / refusée → notification à la personne.
--   • Faille fermée : un membre « en attente » ne peut plus passer lui-même
--     son statut à « actif » (seuls admins / modérateurs changent un statut).
-- Idempotent.
-- ══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.groupes ADD COLUMN IF NOT EXISTS validation_adhesion BOOLEAN NOT NULL DEFAULT true;

-- Adhésion directe (« active ») seulement si le groupe est public ET sans
-- validation. Le créateur du groupe s'inscrit lui-même admin à la création.
DROP POLICY IF EXISTS "groupes_membres_insert" ON groupes_membres;
CREATE POLICY "groupes_membres_insert" ON groupes_membres
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = user_uid
    AND (role = 'membre' OR (
      role = 'admin' AND statut = 'active'
      AND EXISTS (SELECT 1 FROM groupes g WHERE g.id = groupes_membres.groupe_id AND g.createur_uid = (auth.jwt() ->> 'sub'))
    ))
    AND (
      role = 'admin' OR
      statut = 'pending'
      OR (
        statut = 'active'
        AND NOT EXISTS (SELECT 1 FROM groupes g WHERE g.id = groupes_membres.groupe_id
                        AND (g.prive = true OR g.validation_adhesion = true))
      )
    )
  );

-- Seuls admins / modérateurs changent un statut (pas d'auto-validation).
CREATE OR REPLACE FUNCTION public.groupes_membres_statut_garde()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.statut IS DISTINCT FROM OLD.statut
     AND COALESCE(auth.jwt() ->> 'sub', '') <> ''
     AND NOT public.is_admin_or_moderateur_of_groupe(OLD.groupe_id, auth.jwt() ->> 'sub') THEN
    NEW.statut := OLD.statut;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_groupes_membres_statut_garde ON groupes_membres;
CREATE TRIGGER trg_groupes_membres_statut_garde BEFORE UPDATE ON groupes_membres
  FOR EACH ROW EXECUTE FUNCTION public.groupes_membres_statut_garde();

-- Nom affiché d'un membre (son profil, sinon son compte).
CREATE OR REPLACE FUNCTION public.groupes_nom_membre(p_uid TEXT, p_profile UUID)
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(
    (SELECT NULLIF(TRIM(CASE WHEN up.profile_type = 'particulier' OR COALESCE(up.nom, '') = ''
                             THEN COALESCE(up.firstname, '') || ' ' || COALESCE(up.lastname, '')
                             ELSE up.nom END), '')
       FROM user_profiles up WHERE up.id = p_profile),
    (SELECT NULLIF(TRIM(COALESCE(u.firstname, '') || ' ' || COALESCE(u.lastname, '')), '') FROM users u WHERE u.uid = p_uid),
    'Un membre');
$$;

CREATE OR REPLACE FUNCTION public.groupes_membres_notifier()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  g RECORD;
  equipe RECORD;
  qui TEXT;
BEGIN
  IF TG_OP = 'DELETE' THEN
    SELECT id, nom INTO g FROM groupes WHERE id = OLD.groupe_id;
  ELSE
    SELECT id, nom INTO g FROM groupes WHERE id = NEW.groupe_id;
  END IF;
  IF NOT FOUND THEN RETURN COALESCE(NEW, OLD); END IF;

  -- Nouvelle demande → admins et modérateurs.
  IF TG_OP = 'INSERT' AND NEW.statut = 'pending' THEN
    qui := public.groupes_nom_membre(NEW.user_uid, NEW.profile_id);
    FOR equipe IN
      SELECT DISTINCT ON (user_uid) user_uid, profile_id FROM (
        SELECT user_uid, profile_id, 0 AS ordre FROM groupes_membres
         WHERE groupe_id = NEW.groupe_id AND statut = 'active' AND role IN ('admin', 'moderateur')
        UNION ALL
        SELECT createur_uid, createur_profile_id, 1 FROM groupes WHERE id = NEW.groupe_id AND createur_uid IS NOT NULL
      ) e
       WHERE user_uid <> NEW.user_uid
       ORDER BY user_uid, ordre
    LOOP
      INSERT INTO notifications (uid, profile_id, type, title, body, data, read)
      VALUES (equipe.user_uid, equipe.profile_id::text, 'groupe_demande',
              'Demande pour rejoindre ' || COALESCE(g.nom, 'votre groupe'),
              qui || ' souhaite rejoindre le groupe.',
              jsonb_build_object('groupe_id', g.id, 'membre_uid', NEW.user_uid), false);
    END LOOP;

  -- Demande acceptée → la personne.
  ELSIF TG_OP = 'UPDATE' AND OLD.statut = 'pending' AND NEW.statut = 'active' THEN
    INSERT INTO notifications (uid, profile_id, type, title, body, data, read)
    VALUES (NEW.user_uid, NEW.profile_id::text, 'groupe_accepte',
            'Bienvenue dans ' || COALESCE(g.nom, 'le groupe'),
            'Votre demande a été acceptée : vous pouvez publier et commenter.',
            jsonb_build_object('groupe_id', g.id), false);

  -- Demande refusée (supprimée par l'équipe) → la personne.
  ELSIF TG_OP = 'DELETE' AND OLD.statut = 'pending'
        AND COALESCE(auth.jwt() ->> 'sub', '') <> OLD.user_uid THEN
    INSERT INTO notifications (uid, profile_id, type, title, body, data, read)
    VALUES (OLD.user_uid, OLD.profile_id::text, 'groupe_refuse',
            'Demande non retenue',
            'Votre demande pour rejoindre ' || COALESCE(g.nom, 'le groupe') || ' n''a pas été acceptée.',
            jsonb_build_object('groupe_id', g.id), false);
  END IF;
  RETURN COALESCE(NEW, OLD);
END $$;

DROP TRIGGER IF EXISTS trg_groupes_membres_notifier ON groupes_membres;
CREATE TRIGGER trg_groupes_membres_notifier AFTER INSERT OR UPDATE OR DELETE ON groupes_membres
  FOR EACH ROW EXECUTE FUNCTION public.groupes_membres_notifier();

NOTIFY pgrst, 'reload schema';
