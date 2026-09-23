-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 27/N : petfriends, familles_accueil, animal_claims,
--   reservations_animaux, protocoles_chaleur_race
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- petfriends : demande d'ami entre particuliers, modèle à deux parties
-- (uid_demandeur/uid_recepteur), comme rdv/garde_entraide.
--
-- familles_accueil : AUCUNE RLS jusqu'ici — contient les coordonnées
-- (nom, email, tél, adresse) d'une famille d'accueil. Réservé à
-- l'association (association_uid) / cogérant, la famille d'accueil
-- (fa_uid) ayant seulement un accès en lecture à SA propre fiche
-- (mes-animaux-accueil / animaux_en_accueil_page.dart).
--
-- animal_claims : lien à token pour qu'un futur propriétaire réclame un
-- animal transféré depuis la pension (/reclamer-animal/[token]) — mais
-- vérifié : contrairement à cessions/devis, cette page EXIGE d'être
-- connecté avant de réclamer (`if (!user || !claim) return`), donc
-- claimed_by_uid = un vrai uid Firebase authentifié. Verrouillable sans
-- casser le flux, contrairement à cessions/devis (vague 22/N).
--
-- reservations_animaux : contient les coordonnées d'un potentiel
-- acquéreur (nom/email/tel/adresse) — jamais lu côté client, vérifié
-- (ReservationModal.tsx = insert par l'éleveur ; l'annulation dans
-- mes-animaux/[id] = aussi côté éleveur). Réservé à l'éleveur/cogérant,
-- pas de lecture publique.
--
-- protocoles_chaleur_race : SELECT déjà public (paramètres suggérés par
-- race, pas de PII) — laissé tel quel, écriture verrouillée
-- éleveur/cogérant.
--
-- ⚠️ À TESTER après exécution :
--   1. Demander/accepter un ami PetFriends fonctionne pour le demandeur
--      ET le récepteur.
--   2. La liste des familles d'accueil (association) et « Mes animaux en
--      accueil » (famille d'accueil elle-même) s'affichent normalement.
--   3. Le lien /reclamer-animal/[token] continue de fonctionner pour un
--      utilisateur connecté qui réclame un animal.
--   4. Créer/annuler une réservation d'animal fonctionne pour l'éleveur.
--   5. Les protocoles de chaleur par race s'affichent toujours
--      publiquement ; les modifier fonctionne pour l'éleveur/cogérant.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── petfriends (deux parties) ──────────────────────────────────────────────
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'petfriends'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.petfriends', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "petfriends_related_select" ON petfriends
  FOR SELECT USING ((auth.jwt() ->> 'sub') = uid_demandeur OR (auth.jwt() ->> 'sub') = uid_recepteur);

CREATE POLICY "petfriends_related_insert" ON petfriends
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = uid_demandeur);

CREATE POLICY "petfriends_related_update" ON petfriends
  FOR UPDATE USING ((auth.jwt() ->> 'sub') = uid_demandeur OR (auth.jwt() ->> 'sub') = uid_recepteur);

CREATE POLICY "petfriends_related_delete" ON petfriends
  FOR DELETE USING ((auth.jwt() ->> 'sub') = uid_demandeur OR (auth.jwt() ->> 'sub') = uid_recepteur);

-- ── familles_accueil (aucune RLS jusqu'ici) ────────────────────────────────
ALTER TABLE familles_accueil ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'familles_accueil'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.familles_accueil', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "familles_accueil_select" ON familles_accueil
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = association_uid
    OR (auth.jwt() ->> 'sub') = fa_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = familles_accueil.association_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "familles_accueil_insert" ON familles_accueil
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = association_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = familles_accueil.association_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "familles_accueil_update" ON familles_accueil
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = association_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = familles_accueil.association_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = association_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = familles_accueil.association_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "familles_accueil_delete" ON familles_accueil
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = association_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = familles_accueil.association_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- ── animal_claims ──────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Select animal_claims by token or owner" ON animal_claims;
DROP POLICY IF EXISTS "Insert animal_claims" ON animal_claims;
DROP POLICY IF EXISTS "Update animal_claims by token" ON animal_claims;

CREATE POLICY "animal_claims_select" ON animal_claims
  FOR SELECT USING (true);

CREATE POLICY "animal_claims_insert" ON animal_claims
  FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = created_by_uid);

CREATE POLICY "animal_claims_update" ON animal_claims
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = created_by_uid
    OR statut = 'en_attente'
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = created_by_uid
    OR (auth.jwt() ->> 'sub') = claimed_by_uid
  );

-- ── reservations_animaux (PII acquéreur, pas de lecture publique) ─────────
DROP POLICY IF EXISTS "Select reservations" ON reservations_animaux;
DROP POLICY IF EXISTS "Insert reservations" ON reservations_animaux;
DROP POLICY IF EXISTS "Update reservations" ON reservations_animaux;
DROP POLICY IF EXISTS "Delete reservations" ON reservations_animaux;

CREATE POLICY "reservations_animaux_select" ON reservations_animaux
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR (auth.jwt() ->> 'sub') = uid_acquereur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = reservations_animaux.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "reservations_animaux_insert" ON reservations_animaux
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = reservations_animaux.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "reservations_animaux_update" ON reservations_animaux
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = reservations_animaux.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = reservations_animaux.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "reservations_animaux_delete" ON reservations_animaux
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = reservations_animaux.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- ── protocoles_chaleur_race (SELECT public conservé) ──────────────────────
DROP POLICY IF EXISTS "protocoles_chaleur_race_insert" ON protocoles_chaleur_race;
DROP POLICY IF EXISTS "protocoles_chaleur_race_update" ON protocoles_chaleur_race;
DROP POLICY IF EXISTS "protocoles_chaleur_race_delete" ON protocoles_chaleur_race;

CREATE POLICY "protocoles_chaleur_race_insert" ON protocoles_chaleur_race
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = protocoles_chaleur_race.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "protocoles_chaleur_race_update" ON protocoles_chaleur_race
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = protocoles_chaleur_race.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = protocoles_chaleur_race.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "protocoles_chaleur_race_delete" ON protocoles_chaleur_race
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = uid_eleveur
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = protocoles_chaleur_race.uid_eleveur
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('petfriends','familles_accueil','animal_claims','reservations_animaux','protocoles_chaleur_race')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('petfriends','familles_accueil','animal_claims','reservations_animaux','protocoles_chaleur_race')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- CREATE POLICY "pf_select" ON petfriends FOR SELECT USING (true);
-- CREATE POLICY "pf_insert" ON petfriends FOR INSERT WITH CHECK (uid_demandeur IS NOT NULL);
-- CREATE POLICY "pf_update" ON petfriends FOR UPDATE USING (true);
-- CREATE POLICY "pf_delete" ON petfriends FOR DELETE USING (true);
-- ALTER TABLE familles_accueil DISABLE ROW LEVEL SECURITY;
-- CREATE POLICY "Select animal_claims by token or owner" ON animal_claims FOR SELECT USING (true);
-- CREATE POLICY "Insert animal_claims" ON animal_claims FOR INSERT WITH CHECK (created_by_uid IS NOT NULL AND length(created_by_uid) > 0);
-- CREATE POLICY "Update animal_claims by token" ON animal_claims FOR UPDATE USING (true) WITH CHECK (true);
-- CREATE POLICY "Select reservations" ON reservations_animaux FOR SELECT USING (true);
-- CREATE POLICY "Insert reservations" ON reservations_animaux FOR INSERT WITH CHECK (uid_eleveur IS NOT NULL AND length(uid_eleveur) > 0);
-- CREATE POLICY "protocoles_chaleur_race_insert" ON protocoles_chaleur_race FOR INSERT WITH CHECK (uid_eleveur IS NOT NULL);
-- CREATE POLICY "protocoles_chaleur_race_update" ON protocoles_chaleur_race FOR UPDATE USING (true);
-- CREATE POLICY "protocoles_chaleur_race_delete" ON protocoles_chaleur_race FOR DELETE USING (true);
