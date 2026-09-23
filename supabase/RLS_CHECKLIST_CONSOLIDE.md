# Checklist de test consolidée — RLS réelle (vagues 1 à 12)

À tester avec au moins deux comptes : toi (gérante) + un compte cogérant actif
(Ambre) si possible, pour valider aussi les cas de cogérance.

## 1. user_profiles
- [ ] Ton profil (particulier/éleveur/pro) s'affiche normalement, modification OK.
- [ ] Un cogérant actif peut modifier le profil élevage qu'il co-gère.
- [ ] Impossible de modifier le profil d'un tiers (à vérifier via un 2ᵉ compte).

## 2. notifications
- [ ] Tu reçois et vois toutes tes notifications (badge, liste).
- [ ] Un cogérant actif voit les notifications du profil élevage co-géré.
- [ ] Marquer une notification comme lue fonctionne toujours.

## 3. messagerie (conversations, messages, bloquages, message_reactions)
- [ ] Toutes tes conversations existantes s'affichent, historique complet.
- [ ] Envoyer/recevoir un message fonctionne (app + site).
- [ ] Réagir à un message (emoji) fonctionne.
- [ ] Bloquer/débloquer un contact fonctionne.
- [ ] Un tiers ne voit pas une conversation à laquelle il ne participe pas.

## 4. employes + elevage_cogerants
- [ ] "Mes Employés" affiche bien la liste (élevage).
- [ ] Un employé voit ses propres accès ("Mes Employeurs").
- [ ] Ajouter/retirer un employé fonctionne.
- [ ] Inviter/accepter/retirer une cogérance fonctionne (les deux sens).

## 5. animaux + animaux_proprietes (le plus sensible)
- [ ] "Mes Animaux" affiche tous tes animaux (présents/cédés/décédés).
- [ ] Compteur animaux + annonces sur la page d'accueil correct.
- [ ] Un animal avec reproducteur_public=true reste visible publiquement.
- [ ] Un cogérant actif voit/modifie les animaux de l'élevage co-géré.
- [ ] Un employé actif voit les animaux (lecture) de l'élevage.
- [ ] Un co-propriétaire (animaux_proprietes) voit/modifie selon son rôle.
- [ ] Créer/modifier/céder/décéder un animal fonctionne toujours.
- [ ] Supprimer un animal : gérant/cogérant uniquement.

## 6. animal_access + likes + favoris
- [ ] Un pro (véto/toiletteur...) avec accès accordé voit l'animal concerné.
- [ ] Accorder/révoquer un accès pro fonctionne.
- [ ] Liker/mettre en favori une annonce ou un profil fonctionne (app + site).
- [ ] Tes favoris/likes restent visibles et privés (pas modifiables par un tiers).

## 7. taches_elevage + plan_taches
- [ ] Les tâches de l'élevage s'affichent (planning, agenda).
- [ ] Une tâche assignée à un employé lui reste visible/complétable.
- [ ] Un cogérant actif voit/gère les mêmes tâches.

## 8. agenda_events
- [ ] "Mon agenda" (particulier et pro) affiche tous les événements.
- [ ] RDV, rappels, tâches planifiées apparaissent toujours au bon endroit.
- [ ] Un cogérant actif voit l'agenda de l'élevage co-géré.

## 9. abonnements + achats_ponctuels
- [ ] Ton forfait/premium s'affiche correctement (badge, avantages débloqués).
- [ ] Un cogérant actif voit le même statut premium que le gérant.
- [ ] Un achat ponctuel récent apparaît toujours dans l'historique.

## 10. annonces (+ compteur de vues)
- [ ] Toutes tes annonces (élevage) s'affichent dans "Mes annonces".
- [ ] Les annonces publiques restent visibles par tous (recherche, accueil).
- [ ] Le compteur de vues s'incrémente quand quelqu'un d'autre consulte
      l'annonce (app ET site — nouveau sur le site).
- [ ] Créer/modifier/supprimer une annonce fonctionne (gérant + cogérant).

## 11. registre_mouvements + registre_sanitaire
- [ ] Le registre entrées/sorties s'affiche normalement.
- [ ] Le registre sanitaire (vaccins, traitements...) s'affiche normalement.
- [ ] Une cession confirmée crée bien les lignes de sortie/entrée.
- [ ] Un cogérant actif voit/modifie les mêmes registres (pas les employés).

## 12. rdv
- [ ] "Mes RDV" (particulier) et l'agenda pro affichent tous les RDV.
- [ ] Prendre un RDV, le confirmer côté pro, l'annuler côté client fonctionnent.
- [ ] Un cogérant actif voit/gère les RDV du profil pro co-géré.

---

## Points transverses à garder en tête
- Si un écran redevient vide d'un coup après une mise à jour : vérifier
  d'abord que l'app est à jour (le token Firebase doit être envoyé à
  Supabase — toute version antérieure au wiring RLS renverra des listes
  vides partout, ce n'est pas un bug de données).
- En cas de blocage brutal et généralisé sur un écran (erreur ou écran
  vide inattendu), c'est probablement une récursion RLS entre deux tables :
  prévenir immédiatement plutôt que de re-tester en boucle, le rollback
  est rapide.
