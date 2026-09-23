-- ══════════════════════════════════════════════════════════════════════════
-- RLS réelle — vague 18/N : pension / garde
--   pension_entrees, pension_factures, pension_updates, pension_nettoyages,
--   cles_clients, tarifs_clients_garde, garde_entraide
-- ══════════════════════════════════════════════════════════════════════════
-- (auth.jwt() ->> 'sub') reflète le vrai uid Firebase connecté (Third-Party
-- Auth actif côté Supabase).
--
-- pension_entrees avait déjà une policy nommée « pro_own_entrees » mais
-- écrite avec `auth.uid()` (le helper Supabase Auth natif, UUID) au lieu
-- de `auth.jwt() ->> 'sub'` — comme tous les comptes sont Firebase (Third-
-- Party Auth), `auth.uid()` ne correspond JAMAIS à un uid Firebase : cette
-- policy n'a jamais réellement fonctionné (ni protégé, ni laissé passer le
-- bon utilisateur — sans doute masqué par une autre policy plus permissive
-- ailleurs). Les 6 autres tables sont dans le classique `USING(true)`.
--
-- Modèle retenu :
--   - pension_entrees, pension_nettoyages, cles_clients,
--     tarifs_clients_garde : usage 100% interne au pro (jamais lus côté
--     client dans le code actuel) — pro (pro_uid/uid_eleveur) ou cogérant
--     actif uniquement.
--   - pension_updates (photos/vidéos envoyées pendant le séjour) : pro
--     (auteur) ou cogérant EN ÉCRITURE ; en LECTURE, également le
--     propriétaire de l'animal concerné s'il est lié (animal_id, lien
--     optionnel — lu par le client depuis sa fiche animal,
--     animal_fiche_particulier.dart / mes-animaux/[id]).
--   - pension_factures : même situation que `factures` (vague 15/N) — un
--     token permet à un client sans compte de consulter sa facture via
--     /facture-pension/[token]. Lecture laissée ouverte, écriture (dont
--     suppression, contrairement à `factures` — réellement utilisée ici)
--     réservée au pro/cogérant.
--   - garde_entraide (PetFriends, demande de garde informelle entre
--     particuliers) : aucune RLS dédiée jusqu'ici (commentaire du fichier
--     d'origine : « pas de RLS dédiée, lecture publique ») — modèle à
--     deux parties, comme rdv (vague 12/N) : demandeur ou récepteur.
--
-- ⚠️ À TESTER après exécution :
--   1. Le registre pension (entrées/sorties), le planning, les tâches et
--      les nettoyages s'affichent normalement pour le pro et un cogérant
--      actif.
--   2. Envoyer un update (photo/vidéo) pendant un séjour fonctionne ; le
--      propriétaire le voit bien depuis la fiche de son animal (si lié).
--   3. La facturation pension (créer/modifier/supprimer une facture)
--      fonctionne toujours pour le pro/cogérant ; le lien
--      /facture-pension/[token] envoyé au client continue de fonctionner.
--   4. Le suivi des clés clients et les tarifs personnalisés par client
--      s'affichent/s'éditent normalement pour le pro/cogérant.
--   5. Une demande d'entraide PetFriends s'affiche pour le demandeur ET le
--      récepteur, accepter/refuser fonctionne.
-- Si un de ces cas échoue, exécuter la section ROLLBACK tout en bas.
-- ══════════════════════════════════════════════════════════════════════════

-- ── Tables 100% internes au pro (pro_uid/uid_eleveur + cogérant) ──────────
DO $$
DECLARE
  t TEXT;
  pol RECORD;
BEGIN
  FOREACH t IN ARRAY ARRAY['pension_entrees','cles_clients','tarifs_clients_garde']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN CONTINUE; END IF;
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;

    EXECUTE format($f$
      CREATE POLICY "%1$s_pro_or_cogerant" ON public.%1$I
        FOR ALL USING (
          (auth.jwt() ->> 'sub') = pro_uid
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = %1$I.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
        WITH CHECK (
          (auth.jwt() ->> 'sub') = pro_uid
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = %1$I.pro_uid
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    $f$, t);
  END LOOP;

  -- pension_nettoyages utilise uid_eleveur (pas pro_uid) comme colonne pro.
  t := 'pension_nettoyages';
  IF to_regclass('public.' || t) IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    FOR pol IN EXECUTE format('SELECT policyname FROM pg_policies WHERE schemaname = ''public'' AND tablename = %L', t)
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, t);
    END LOOP;

    EXECUTE $f$
      CREATE POLICY "pension_nettoyages_pro_or_cogerant" ON public.pension_nettoyages
        FOR ALL USING (
          (auth.jwt() ->> 'sub') = uid_eleveur
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = pension_nettoyages.uid_eleveur
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
        WITH CHECK (
          (auth.jwt() ->> 'sub') = uid_eleveur
          OR EXISTS (
            SELECT 1 FROM elevage_cogerants c
            WHERE c.uid_gerant = pension_nettoyages.uid_eleveur
              AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
          )
        )
    $f$;
  END IF;
END $$;

-- ── pension_updates (pro/cogérant en écriture, + propriétaire en lecture) ─
ALTER TABLE pension_updates ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'pension_updates'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.pension_updates', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "pension_updates_select" ON pension_updates
  FOR SELECT USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = pension_updates.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
    OR (
      animal_id IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM animaux a
        WHERE a.id = pension_updates.animal_id
          AND (
            a.uid_eleveur = (auth.jwt() ->> 'sub') OR a.uid_proprietaire = (auth.jwt() ->> 'sub')
            OR EXISTS (
              SELECT 1 FROM elevage_cogerants c2
              WHERE c2.uid_gerant = a.uid_eleveur
                AND c2.uid_cogerant = (auth.jwt() ->> 'sub') AND c2.statut = 'actif' AND c2.date_fin IS NULL
            )
          )
      )
    )
  );

CREATE POLICY "pension_updates_insert" ON pension_updates
  FOR INSERT WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = pension_updates.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "pension_updates_update" ON pension_updates
  FOR UPDATE USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = pension_updates.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = pension_updates.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

CREATE POLICY "pension_updates_delete" ON pension_updates
  FOR DELETE USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = pension_updates.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );

-- ── pension_factures (écriture pro/cogérant — lecture laissée ouverte) ────
ALTER TABLE pension_factures ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol RECORD;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'pension_factures'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.pension_factures', pol.policyname);
  END LOOP;
END $$;

CREATE POLICY "pension_factures_select_all" ON pension_factures
  FOR SELECT USING (true);

CREATE POLICY "pension_factures_write" ON pension_factures
  FOR ALL USING (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = pension_factures.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  )
  WITH CHECK (
    (auth.jwt() ->> 'sub') = pro_uid
    OR EXISTS (
      SELECT 1 FROM elevage_cogerants c
      WHERE c.uid_gerant = pension_factures.pro_uid
        AND c.uid_cogerant = (auth.jwt() ->> 'sub') AND c.statut = 'actif' AND c.date_fin IS NULL
    )
  );
-- Le SELECT public ci-dessus rend cette policy FOR ALL redondante en
-- lecture (jamais plus restrictive que SELECT_all) mais bien effective
-- en écriture — Postgres combine les policies d'une même commande en OR,
-- donc SELECT reste ouvert, INSERT/UPDATE/DELETE passent par celle-ci.

-- ── garde_entraide (deux parties : demandeur / récepteur) ─────────────────
DO $$
BEGIN
  IF to_regclass('public.garde_entraide') IS NULL THEN RETURN; END IF;

  ALTER TABLE garde_entraide ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS "garde_entraide_related_select" ON garde_entraide;
  DROP POLICY IF EXISTS "garde_entraide_related_insert" ON garde_entraide;
  DROP POLICY IF EXISTS "garde_entraide_related_update" ON garde_entraide;
  DROP POLICY IF EXISTS "garde_entraide_related_delete" ON garde_entraide;

  CREATE POLICY "garde_entraide_related_select" ON garde_entraide
    FOR SELECT USING (
      (auth.jwt() ->> 'sub') = uid_demandeur OR (auth.jwt() ->> 'sub') = uid_recepteur
    );

  CREATE POLICY "garde_entraide_related_insert" ON garde_entraide
    FOR INSERT WITH CHECK ((auth.jwt() ->> 'sub') = uid_demandeur);

  CREATE POLICY "garde_entraide_related_update" ON garde_entraide
    FOR UPDATE USING (
      (auth.jwt() ->> 'sub') = uid_demandeur OR (auth.jwt() ->> 'sub') = uid_recepteur
    );

  CREATE POLICY "garde_entraide_related_delete" ON garde_entraide
    FOR DELETE USING (
      (auth.jwt() ->> 'sub') = uid_demandeur OR (auth.jwt() ->> 'sub') = uid_recepteur
    );
END $$;

-- Vérification
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE tablename IN ('pension_entrees','pension_factures','pension_updates','pension_nettoyages','cles_clients','tarifs_clients_garde','garde_entraide')
ORDER BY tablename, cmd;

-- ══════════════════════════════════════════════════════════════════════════
-- ROLLBACK — si un des tests ci-dessus échoue :
-- ══════════════════════════════════════════════════════════════════════════
-- DO $$
-- DECLARE pol RECORD;
-- BEGIN
--   FOR pol IN SELECT tablename, policyname FROM pg_policies WHERE schemaname = 'public'
--     AND tablename IN ('pension_entrees','pension_factures','pension_updates','pension_nettoyages','cles_clients','tarifs_clients_garde','garde_entraide')
--   LOOP
--     EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, pol.tablename);
--   END LOOP;
-- END $$;
-- CREATE POLICY "pro_own_entrees" ON pension_entrees FOR ALL USING (pro_uid = auth.uid()::text);
-- CREATE POLICY "Select cles_clients" ON cles_clients FOR SELECT USING (true);
-- CREATE POLICY "Insert cles_clients" ON cles_clients FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND pro_profile_id IS NOT NULL);
-- CREATE POLICY "Update cles_clients" ON cles_clients FOR UPDATE USING (true);
-- CREATE POLICY "Delete cles_clients" ON cles_clients FOR DELETE USING (true);
-- CREATE POLICY "Select tarifs_clients_garde" ON tarifs_clients_garde FOR SELECT USING (true);
-- CREATE POLICY "Insert tarifs_clients_garde" ON tarifs_clients_garde FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND pro_profile_id IS NOT NULL AND owner_profile_id IS NOT NULL);
-- CREATE POLICY "Update tarifs_clients_garde" ON tarifs_clients_garde FOR UPDATE USING (true);
-- CREATE POLICY "Delete tarifs_clients_garde" ON tarifs_clients_garde FOR DELETE USING (true);
-- CREATE POLICY "Select pension_nettoyages" ON pension_nettoyages FOR SELECT USING (true);
-- CREATE POLICY "Insert pension_nettoyages" ON pension_nettoyages FOR INSERT WITH CHECK (uid_eleveur IS NOT NULL AND length(uid_eleveur) > 0);
-- CREATE POLICY "Delete pension_nettoyages" ON pension_nettoyages FOR DELETE USING (true);
-- CREATE POLICY "Select pension_updates" ON pension_updates FOR SELECT USING (true);
-- CREATE POLICY "Insert pension_updates" ON pension_updates FOR INSERT WITH CHECK (pro_uid IS NOT NULL AND length(pro_uid) > 0);
-- CREATE POLICY "Delete pension_updates" ON pension_updates FOR DELETE USING (true);
-- CREATE POLICY "pension_factures_all" ON pension_factures FOR ALL USING (true);
-- ALTER TABLE garde_entraide DISABLE ROW LEVEL SECURITY;
