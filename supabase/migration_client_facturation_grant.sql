-- ════════════════════════════════════════════════════════════════════════
-- pm_client_facturation : exécutable par le rôle anon.
--
-- Les requêtes de l'appli et du site (jeton Firebase) arrivent avec le rôle
-- « anon » ; l'identité vient de auth.jwt() ->> 'sub' (comme pour toutes les
-- autres fonctions du projet : pm_trouver_utilisateur, ceder_propriete_animal,
-- pm_employe_profil… accordées à anon, authenticated). Accordée à
-- authenticated seulement, la fonction était refusée → facture sans
-- coordonnées. Sécurité inchangée : sans sub, ou sans partage actif de
-- l'animal, elle renvoie NULL. Idempotent.
-- ════════════════════════════════════════════════════════════════════════
GRANT EXECUTE ON FUNCTION public.pm_client_facturation(TEXT, UUID) TO anon, authenticated;

NOTIFY pgrst, 'reload schema';
