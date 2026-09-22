-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 5/N (CORRIGÉ) : animaux, animaux_proprietes
-- ══════════════════════════════════════════════════════════════════════════
-- La table la plus délicate jusqu'ici : un animal peut être vu/modifié par
-- BEAUCOUP de rôles différents selon le type de profil (particulier,
-- éleveur, association...). (auth.jwt() ->> 'sub') reflète le vrai uid
-- Firebase connecté (Third-Party Auth actif côté Supabase).
--
-- ⚠️ CORRECTIF #1 (1ʳᵉ tentative) : la policy animaux_proprietes se
-- référençait elle-même (vérifier "suis-je le propriétaire PRINCIPAL de cet
-- animal ?" en reconsultant animaux_proprietes depuis sa propre policy).
-- Postgres détecte ça et lève "infinite recursion detected in policy for
-- relation animaux_proprietes" sur CHAQUE requête — ce qui avait fait
-- disparaître "Mes Animaux" ET, par ricochet, le compteur d'annonces de la
-- page d'accueil (les deux compteurs sont chargés dans le même Future.wait
-- côté app, qui échoue entièrement si une seule requête plante). Corrigé en
-- sortant cette vérification dans une fonction SECURITY DEFINER.
--
-- ⚠️ CORRECTIF #2 (2ᵉ tentative) : même famille de bug, mais CROISÉ entre
-- deux tables cette fois. La policy `animaux` vérifiait l'accès pro via un
-- EXISTS direct sur `animal_access`, et la policy `animal_access` (vague
-- 6/N) vérifie la propriété de l'animal via un EXISTS direct sur `animaux`
-- — chaque table dépend de l'autre, même erreur de récursion infinie,
-- cette fois déclenchée en ajoutant la vague 6/N (a cassé "Mes Patients"
-- d'un profil pro santé). Corrigé de la même façon : le check `animal_access`
-- dans la policy `animaux` passe maintenant par une fonction SECURITY
-- DEFINER (public.has_animal_access) au lieu d'un EXISTS direct — la
-- dépendance devient à sens unique (animal_access → animaux uniquement).
--
-- Rôles couverts pour `animaux` :
--   - Lecture publique si reproducteur_public = true (vitrine reproducteurs).
--   - Le propriétaire (uid_eleveur / uid_proprietaire particulier).
--   - Un cogérant actif de l'élevage propriétaire.
--   - Un employé actif de l'élevage propriétaire.
--   - Un co-propriétaire courant (animaux_proprietes, date_fin IS NULL).
--   - Un pro (véto, pension, garde, éducation...) avec un accès accordé
--     actif (animal_access, statut active/active_write).
--   - L'acquéreur pendant une cession en cours (uid_acquereur).
--
-- Écriture (INSERT/UPDATE) : mêmes rôles SAUF le pro à accès "active" simple
-- (lecture seule) — seul "active_write" donne l'écriture. Suppression :
-- réservée au propriétaire ou à un cogérant actif (action destructive).
--
-- Note de conception : RLS ne réplique PAS ici les permissions fines
-- appli (ex. employe_permissions.write_animaux précis) — elle garantit
-- seulement qu'une personne SANS AUCUNE relation légitime avec l'animal ne
-- peut rien lire/écrire. Le contrôle fin (quel employé a le droit de faire
-- quoi) reste, comme avant, appliqué côté code.
--
-- Rôles couverts pour `animaux_proprietes` (historique de propriété /
-- co-propriétaires) : le titulaire de la ligne (uid_proprio), un cogérant
-- actif de ce titulaire, OU le propriétaire PRINCIPAL courant du même
-- animal (pour gérer/révoquer ses co-propriétaires) et son cogérant actif.
--
-- ⚠️ À TESTER SOIGNEUSEMENT après exécution (c'est la table la plus utilisée
-- de l'appli) :
--   1. "Mes Animaux" ET la page d'accueil (compteurs animaux + annonces)
--      s'affichent normalement pour un compte particulier ET éleveur.
--   2. Un cogérant actif voit et peut modifier les animaux de l'élevage
--      qu'il co-gère (fiche animal, carnet de santé...).
--   3. Un employé actif voit les animaux de son employeur.
--   4. Un co-propriétaire (particulier) voit l'animal partagé, peut le
--      modifier ; le propriétaire principal peut gérer/retirer un
--      co-propriétaire.
--   5. Un pro avec accès accordé (véto, santé/ostéo, pension, garde,
--      éducation...) voit bien sa liste "Mes Patients" ET la fiche/carnet
--      de santé de chaque animal listé ; s'il a l'écriture (active_write),
--      il peut ajouter un acte.
--   6. La vitrine "Reproducteurs" publique (profil éleveur public) affiche
--      toujours les animaux marqués reproducteur_public.
--   7. Créer un nouvel animal, céder un animal, fonctionnent toujours.
--
-- ⚠️ Cette migration doit être réexécutée APRÈS avoir réappliqué la vague
-- 6/N (migration_rls_tighten_animalaccess_likes_favoris.sql), puisque les
-- deux se référencent désormais l'une l'autre sans risque de boucle
-- uniquement dans cet ordre (animaux d'abord, avec ses fonctions ; puis
-- animal_access). Si l'ordre exact importe peu en pratique (les policies
-- ne s'activent qu'une fois les DEUX présentes), le plus sûr reste de
-- rejouer les deux fichiers l'un après l'autre dans cet ordre.
-- Si un des tests ci-dessus échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── Fonction utilitaire (évite la self-référence RLS) ───────────────────
CREATE OR REPLACE FUNCTION public.is_principal_owner_or_cogerant(p_animal_id TEXT, p_uid TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM animaux_proprietes p2
    WHERE p2.animal_id = p_animal_id
      AND p2.role_proprio = 'principal' AND p2.date_fin IS NULL
      AND (
        p2.uid_proprio = p_uid
        OR EXISTS (
          SELECT 1 FROM elevage_cogerants c2
          WHERE c2.uid_gerant = p2.uid_proprio
            AND c2.uid_cogerant = p_uid
            AND c2.statut = 'actif' AND c2.date_fin IS NULL
        )
      )
  );
$$;
GRANT EXECUTE ON FUNCTION public.is_principal_owner_or_cogerant(TEXT, TEXT) TO anon, authenticated;

-- Casse la dépendance croisée animaux <-> animal_access (voir CORRECTIF #2
-- ci-dessus) : SECURITY DEFINER, donc sa requête interne sur animal_access
-- ne redéclenche pas l'évaluation de la policy animal_access.
CREATE OR REPLACE FUNCTION public.has_animal_access(p_animal_id TEXT, p_uid TEXT, p_require_write BOOLEAN DEFAULT false)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM animal_access aa
    JOIN user_profiles up ON up.id = aa.pro_profile_id
    WHERE aa.animal_id = p_animal_id
      AND up.uid = p_uid
      AND (
        (p_require_write AND aa.statut = 'active_write')
        OR (NOT p_require_write AND aa.statut IN ('active', 'active_write'))
      )
  );
$$;
GRANT EXECUTE ON FUNCTION public.has_animal_access(TEXT, TEXT, BOOLEAN) TO anon, authenticated;

-- ── animaux_proprietes (prérequis : la logique animaux en dépend) ────────
ALTER TABLE animaux_proprietes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "firebase_allow_all" ON animaux_proprietes;
DROP POLICY IF EXISTS "animaux_proprietes_select" ON animaux_proprietes;
DROP POLICY IF EXISTS "animaux_proprietes_insert" ON animaux_proprietes;
DROP POLICY IF EXISTS "animaux_proprietes_update" ON animaux_proprietes;
DROP POLICY IF EXISTS "ap_owner_or_cogerant_or_principal_select" ON animaux_proprietes;
DROP POLICY IF EXISTS "ap_owner_or_cogerant_or_principal_insert" ON animaux_proprietes;
DROP POLICY IF EXISTS "ap_owner_or_cogerant_or_principal_update" ON animaux_proprietes;
DROP POLICY IF EXISTS "ap_owner_or_cogerant_or_principal_delete" ON animaux_proprietes;

CREATE POLICY "ap_owner_or_cogerant_or_principal_select" ON animaux_proprietes
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = uid_proprio
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = animaux_proprietes.uid_proprio
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR public.is_principal_owner_or_cogerant(animaux_proprietes.animal_id, (auth.jwt() ->> 'sub'))
  );

CREATE POLICY "ap_owner_or_cogerant_or_principal_insert" ON animaux_proprietes
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_proprio
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = animaux_proprietes.uid_proprio
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR public.is_principal_owner_or_cogerant(animaux_proprietes.animal_id, (auth.jwt() ->> 'sub'))
  );

CREATE POLICY "ap_owner_or_cogerant_or_principal_update" ON animaux_proprietes
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = uid_proprio
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = animaux_proprietes.uid_proprio
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR public.is_principal_owner_or_cogerant(animaux_proprietes.animal_id, (auth.jwt() ->> 'sub'))
  );

CREATE POLICY "ap_owner_or_cogerant_or_principal_delete" ON animaux_proprietes
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = uid_proprio
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = animaux_proprietes.uid_proprio
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR public.is_principal_owner_or_cogerant(animaux_proprietes.animal_id, (auth.jwt() ->> 'sub'))
  );

-- ── animaux ────────────────────────────────────────────────────────────
ALTER TABLE animaux ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "firebase_allow_all" ON animaux;
DROP POLICY IF EXISTS "animaux_public_or_related_select" ON animaux;
DROP POLICY IF EXISTS "animaux_related_insert" ON animaux;
DROP POLICY IF EXISTS "animaux_related_update" ON animaux;
DROP POLICY IF EXISTS "animaux_owner_or_cogerant_delete" ON animaux;

CREATE POLICY "animaux_public_or_related_select" ON animaux
  FOR SELECT USING (
    reproducteur_public = true
    OR (auth.jwt() ->> 'sub') = uid_eleveur
    OR (auth.jwt() ->> 'sub') = uid_proprietaire
    OR (auth.jwt() ->> 'sub') = uid_acquereur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = animaux.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR EXISTS (
      SELECT 1 FROM employes e
      WHERE e.uid_eleveur = animaux.uid_eleveur
        AND e.uid_employe = (auth.jwt() ->> 'sub')
        AND e.actif = true
    )
    OR EXISTS (
      SELECT 1 FROM animaux_proprietes p
      WHERE p.animal_id = animaux.id
        AND p.uid_proprio = (auth.jwt() ->> 'sub')
        AND p.date_fin IS NULL
    )
    OR public.has_animal_access(animaux.id, (auth.jwt() ->> 'sub'), false)
  );

CREATE POLICY "animaux_related_insert" ON animaux
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR (auth.jwt() ->> 'sub') = uid_proprietaire
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = animaux.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "animaux_related_update" ON animaux
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR (auth.jwt() ->> 'sub') = uid_proprietaire
    OR (auth.jwt() ->> 'sub') = uid_acquereur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = animaux.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR EXISTS (
      SELECT 1 FROM employes e
      WHERE e.uid_eleveur = animaux.uid_eleveur
        AND e.uid_employe = (auth.jwt() ->> 'sub')
        AND e.actif = true
    )
    OR EXISTS (
      SELECT 1 FROM animaux_proprietes p
      WHERE p.animal_id = animaux.id
        AND p.uid_proprio = (auth.jwt() ->> 'sub')
        AND p.date_fin IS NULL
    )
    OR public.has_animal_access(animaux.id, (auth.jwt() ->> 'sub'), true)
  );

-- Suppression : réservée au propriétaire ou à un cogérant actif (action
-- destructive, pas ouverte aux employés/co-propriétaires/pros).
CREATE POLICY "animaux_owner_or_cogerant_delete" ON animaux
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR (auth.jwt() ->> 'sub') = uid_proprietaire
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = animaux.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub')
        AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- Vérification
SELECT tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename IN ('animaux','animaux_proprietes')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DROP POLICY IF EXISTS "ap_owner_or_cogerant_or_principal_select" ON animaux_proprietes;
-- DROP POLICY IF EXISTS "ap_owner_or_cogerant_or_principal_insert" ON animaux_proprietes;
-- DROP POLICY IF EXISTS "ap_owner_or_cogerant_or_principal_update" ON animaux_proprietes;
-- DROP POLICY IF EXISTS "ap_owner_or_cogerant_or_principal_delete" ON animaux_proprietes;
-- CREATE POLICY "firebase_allow_all" ON animaux_proprietes FOR ALL USING (true) WITH CHECK (true);
--
-- DROP POLICY IF EXISTS "animaux_public_or_related_select" ON animaux;
-- DROP POLICY IF EXISTS "animaux_related_insert" ON animaux;
-- DROP POLICY IF EXISTS "animaux_related_update" ON animaux;
-- DROP POLICY IF EXISTS "animaux_owner_or_cogerant_delete" ON animaux;
-- CREATE POLICY "firebase_allow_all" ON animaux FOR ALL USING (true) WITH CHECK (true);
--
-- DROP FUNCTION IF EXISTS public.is_principal_owner_or_cogerant(TEXT, TEXT);
-- DROP FUNCTION IF EXISTS public.has_animal_access(TEXT, TEXT, BOOLEAN);
