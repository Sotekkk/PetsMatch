# TASKS — PetsMatch

> Fichier de coordination entre développeurs.
> **Avant de toucher un fichier :** mettre son prénom + statut "en cours" ci-dessous.
> **Quand c'est terminé :** passer en "terminé" et déplacer dans l'historique.

---

## En cours

| # | Tâche | Repo | Fichiers touchés | Assigné | Statut | Notes |
|---|---|---|---|---|---|---|
| — | — | — | — | — | — | — |

---

## À faire — Backlog

### Tâches Angélique — Profil éleveur, particulier & Admin

| # | Tâche | Priorité | Repo | Fichiers probables |
|---|---|---|---|---|
| A02 | Animaux perdus — clic sur alerte page d'accueil → ouvrir la gestion de l'alerte directement | Haute | App + Web | `particulier_home.dart`, `eleveur_home.dart`, page d'accueil web |
| A03 | Animaux perdus — clic long sur alerte → menu "Supprimer" / "Animal retrouvé" (avec confirmation) | Haute | App + Web | `animaux_perdus_page.dart`, page web équivalente |
| A05 | Registre entrée/sortie — auto-fill provenance avec infos éleveur (nom + adresse) | Haute | App + Web | `registre_entree_sortie.dart`, `elevage/registre-entree-sortie/page.tsx` |

| A06 | Registre entrée/sortie — auto-fill infos mère depuis fiche animal si mère = animal de l'élevage | Haute | App + Web | `registre_entree_sortie.dart`, page web |
| A07 | Suivi repro — saillie → gestation automatique avec date de mise bas prévue | Haute | App + Web | À créer `suivi_repro.dart` + page web |
| A08 | Suivi repro — champ "Gestation confirmée" (oui/non) + alerte rappel confirmation selon espèce | Haute | App + Web | À créer `suivi_repro.dart` |
| A09 | Suivi repro — saillie extérieure : accès infos mâle (photo, nom, puce, race) depuis éleveur externe | Moyenne | App + Web | À créer `suivi_repro.dart` + table `saillie_acces` |
| A10 | Annonces — photo carrée à la création (déjà OK) + affichage rectangle adapté centré dans le feed sans rogner | Haute | App + Web | `annonces_feed_page.dart`, feed web |
| A12 | Admin — algorithme de validation automatique profils éleveurs (détection spam, cohérence données) | Haute | App + Web | `admin_panel.dart`, `verification_detail.dart` |
| A13 | Admin — algorithme modération annonces (filtre contenu, cohérence espèce/race/prix) | Haute | App + Web | Panel admin |

### App mobile + Web (synchronisés)

| # | Tâche | Priorité | Repo | Notes |
|---|---|---|---|---|
| T01 | Animaux perdus — formulaire complet (nom depuis mes animaux, race depuis JSON, dernière localisation) | Haute | App + Web | Voir SPEC §7, roadmap §I.A |
| T02 | Animaux perdus — filtres liste (espèce, race, ville, région) + vue détail | Haute | App + Web | Roadmap §I.B |
| T03 | Animaux perdus — contact via messagerie (objet auto) | Moyenne | App + Web | Roadmap §I.B |
| T04 | Messagerie — ajout au menu + redesign liste | Moyenne | App + Web | Roadmap §II |
| T05 | Messagerie — types de conversation (annonce, perdu, élevage, libre, pro) | Moyenne | App + Web | Roadmap §II |
| T06 | Fiche animal — onglet suivi repro éleveur (chaleurs, saillie, gestation) | Haute | App + Web | Roadmap §III.A.a |
| T07 | Carnet de santé — notifications vaccins/antiparasitaires (J-7, J-1, J) | Haute | App | Roadmap §III.A.b |
| T08 | Fiche animal — courbe de poids (croissance + adulte) | Moyenne | App + Web | Roadmap §III.A.b |
| T09 | Transfert de propriété animal (vente → email acheteur) | Haute | App + Web | Roadmap §III.A.c |
| T10 | Annonces — likes sur portée/bébé + notification éleveur + favoris | Haute | Web d'abord | Roadmap §VI |
| T11 | Annonces — visuel liste style "match" (photo bébé premier plan) | Moyenne | Web | Roadmap §VI |
| T12 | Annonces — fix onglet annonces profil éleveur | Haute | App + Web | Roadmap §VI |
| T13 | Registre sanitaire — import Excel | Basse | Web | Roadmap §V |
| T14 | Notifications animaux perdus — fix iOS (alertes non reçues) | Haute | App | Roadmap §I.C |
| T15 | Animaux perdus — carte synchronisée avec filtres liste | Moyenne | App + Web | Roadmap §I.B |

### Services & Communauté — **[prénom collègue]**
> Spec complète : `SPEC_PRO_SERVICES.md`

| # | Tâche | Priorité | App / Web | Fichiers de départ |
|---|---|---|---|---|
| S01 | Profil pro — enrichir champs (rayon, espèces, horaires, certifications) | Haute | App + Web | `settings/info_utilisateur.dart`, `profil/page.tsx` |
| S02 | Annuaire services — brancher les onTap "bientôt disponible" + créer pages détail | Haute | App + Web | `services/veterinaires_page.dart` → créer `service_detail_page.dart` |
| S03 | Page Services web (absente) — créer miroir de l'app | Haute | Web | `src/app/services/page.tsx` à créer + `Header.tsx` |
| S04 | Agenda RDV — tables BDD + UI pro + UI client | Haute | App + Web | Créer `lib/pages/pro/pro_agenda.dart` |
| S05 | Accès carnet santé animal (permissions pro) | Haute | App + Web | Créer table `animal_acces_pro` |
| S06 | Envoi ordonnances / comptes rendus | Moyenne | App + Web | Créer table `ordonnances` + `comptes_rendus` |
| S07 | Registre pension (entrée/sortie) | Moyenne | App + Web | Réutiliser logique `registre_entree_sortie` |
| S08 | Animal Friendly — carte + ajout lieu | Haute | App + Web | Créer `lib/pages/animal_friendly/` + `src/app/animal-friendly/` |
| S09 | Événements — création + inscription + rappels | Moyenne | App + Web | Créer `lib/pages/evenements/` + `src/app/evenements/` |
| S10 | Promenades collectives | Moyenne | App + Web | Créer `lib/pages/promenades/` + `src/app/promenades/` |
| S11 | Forum communauté | Basse | App + Web | Créer `lib/pages/communaute/` + `src/app/communaute/` |
| S12 | Groupes communauté | Basse | App + Web | Créer `lib/pages/communaute/` |

### App uniquement

| # | Tâche | Priorité | Fichiers probables | Notes |
|---|---|---|---|---|
| A01 | Contrats — modèle de base modifiable | Moyenne | `eleveur/admin/contrat_reservation.dart` | Roadmap §IV |

### Web uniquement

| # | Tâche | Priorité | Fichiers probables | Notes |
|---|---|---|---|---|
| W01 | Contrats — modèle de base modifiable | Moyenne | `elevage/contrats/page.tsx` (à créer) | Roadmap §IV |

---

## Terminé récemment

| Tâche | Date | Repo | Fichiers modifiés |
|---|---|---|---|
| A01 — Photo/document : bottom sheet caméra + galerie (animal, portée, alerte perdue) | 2026-05 | App | `animal_fiche.dart`, `portee_form_page.dart`, `alerte_perdu_form_page.dart` |
| A04 — Clic long mes annonces (accueil éleveur) → Supprimer avec confirmation | 2026-05 | App | `eleveur_home.dart` |
| A11 — Barre de recherche (nom + puce) dans mes animaux éleveur | 2026-05 | App + Web | `mes_animaux.dart`, `mes-animaux/page.tsx` |
| Fiche animal — section pedigree (type par espèce, document upload) | 2026-05 | App + Web | `animal_fiche.dart`, `mes-animaux/[id]/page.tsx` |
| Portée — champs par animal (type_poil, taille, poids, stérilisé, passeport, notes) | 2026-05 | App + Web | `portee_form_page.dart`, `mes-animaux/portee/page.tsx` |
| Portée — photo par animal avec crop | 2026-05 | App + Web | `portee_form_page.dart`, `mes-animaux/portee/page.tsx` |
| Portée — auto-fill registre (provenance nom + adresse élevage) | 2026-05 | App + Web | `portee_form_page.dart`, `mes-animaux/portee/page.tsx` |
| Admin — suppression profil complet (Firebase Auth + Supabase cascade) | 2026-05 | App + Supabase | `user_detail.dart`, `user_list.dart`, `supabase/functions/delete-user/index.ts` |
| Fix typo "animalaux" → "animaux" | 2026-05 | App + Web | `portee/page.tsx`, `portee_form_page.dart`, `race_selection_page.dart` |
| Fiche animal — champs importation_ref, date_naissance_mere, catégories documents | 2026-05 | Web | `mes-animaux/[id]/page.tsx` |

---

## Fichiers actuellement modifiés (verrou temporaire)

> Renseigner ici dès qu'on commence à travailler sur un fichier sensible.
> Effacer la ligne une fois le commit poussé.

| Fichier | Repo | Qui | Depuis |
|---|---|---|---|
| — | — | — | — |

---

## Notes techniques partagées

- **Architecture** : Firebase Auth = auth uniquement. Toutes les données métier = Supabase. Ne jamais écrire de nouvelles données dans Firestore.
- **Firestore résiduel** : `post` (feed social), `conversations` (messagerie), `likedPost`, `bloquer` — à migrer progressivement, ne pas y ajouter de nouvelles features
- **Annonces** : 100% Supabase (create, feed, map, detail, mes-annonces, likes, favoris)
- **Races** : toujours lire depuis `assets/dog_breeds.json`, `cat_breeds.json`, etc. (9 fichiers JSON par espèce)
- **Supabase Edge Function `delete-user`** : JWT verification désactivée dans le dashboard (clé anon = format `sb_publishable_` non-JWT)
- **Firebase Storage** : photos profil, animaux, documents — URL sauvegardée dans Supabase
- **Supabase URL** : `https://zyvpngcvzrkdytypjlyq.supabase.co`
