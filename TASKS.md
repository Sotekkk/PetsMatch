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
| A09 | Suivi repro — saillie extérieure : accès infos mâle (photo, nom, puce, race) depuis éleveur externe | Moyenne | App + Web | À créer `suivi_repro.dart` + table `saillie_acces` |
| A12 | Admin — algorithme de validation automatique profils éleveurs (détection spam, cohérence données) | Haute | App + Web | `admin_panel.dart`, `verification_detail.dart` |
| A13 | Admin — algorithme modération annonces (filtre contenu, cohérence espèce/race/prix) | Haute | App + Web | Panel admin |
| A14 | Vue fiche animal pour particuliers — identique à la vue carte profil éleveur | Haute | App + Web | À créer dans profil particulier |
| A15 | Profil particulier — revoir mise en page (app) | Moyenne | App | `particulier_home.dart`, `info_utilisateur.dart` |
| A16 | Vue admin dans l'appli web | Haute | Web | `src/app/admin/` à créer |
| A18 | Espèce âne — ajouter partout (listes espèces, filtres, formulaires) + créer `donkey_breeds.json` | Haute | App + Web | Tous les sélecteurs d'espèce + assets |
| A19 | Feed — filtre race dynamique selon espèce (liste JSON par espèce) | Haute | App + Web | `annonces_feed_page.dart`, `annonces/feed/page.tsx` |
| A20 | Carte annonces compagnons — filtres par espèce, race, région, ville, pays, département | Haute | App | `annonces_map_page.dart` |
| A21 | Sécurité avant mise en prod — RLS Supabase propres (remplacer Firebase Auth UID par JWT custom ou service role), politique de confidentialité, CGU, suppression compte RGPD | Haute | App + Web + Supabase | Toutes tables Supabase |

### Animaux perdus / trouvés — Spec complète : `SPEC_ANIMAUX_PERDUS_TROUVES.md`

| # | Tâche | Priorité | Repo | Fichiers probables |
|---|---|---|---|---|
| ~~PT01~~ | ~~**[V1]** Vérifier complétude formulaire "Animal perdu"~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-29 |
| ~~PT02~~ | ~~**[V1]** Déclarer animal trouvé — formulaire complet~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-29 |
| ~~PT03~~ | ~~**[V1]** Table Supabase `animaux_trouves`~~ | ~~Haute~~ | ~~Supabase~~ | ✅ Terminé 2026-05-29 |
| PT04 | **[V1]** Carte animaux perdus/trouvés — onglet Perdu/Trouvé + code couleur (rouge/vert/orange/bleu) + filtres espèce, race, région, ville, distance | Haute | App + Web | `animaux_perdus_page.dart`, `animaux-perdus/page.tsx` |
| PT05 | **[V1]** Bouton global "J'ai trouvé un animal" — visible dans menu (drawer éleveur + particulier) + page d'accueil (action urgente) | Haute | App + Web | `eleveur_nav.dart`, `particulier_nav.dart`, `EleveurDashboard.tsx`, `ParticulierDashboard.tsx` |
| PT06 | **[V1]** Saisie manuelle numéro puce → recherche dans alertes perdus + animaux trouvés + animaux de l'élevage | Haute | App + Web | `animaux_perdus_page.dart`, `animaux-perdus/page.tsx` |
| PT07 | **[V1]** Notifications de proximité pour les animaux trouvés (< 10 km d'une alerte active) — Firebase Cloud Function `notifyNearFoundAnimal` | Haute | Firebase Functions | `functions/alertes.js` |
| PT08 | **[V1]** Messagerie automatique perdu/trouvé — conversation Firestore avec objet + message prérempli au contact | Moyenne | App + Web | Messagerie existante |
| PT09 | **[V2]** Matching automatique perdu ↔ trouvé — score pondéré (espèce+race+sexe+zone+date+couleur+puce) + notification si ≥ 90% | Haute | Firebase Functions + App + Web | Créer `matchLostFound` Cloud Function |
| PT10 | **[V2]** Table `alertes_correspondances` — stocker les paires matchées pour éviter doublons de notif | Moyenne | Supabase | Dashboard SQL Editor |
| PT11 | **[V2]** Lecteur puce Bluetooth — `ChipScannerService` (connect/disconnect/listen/parseChip/searchAnimal), protocoles BLE + ISO11784/11785. **3 contextes** : (1) élevage → ouvre fiche animal directement, (2) animal trouvé → ouvre alerte liée, (3) inconnu → propose créer/déclarer | Haute | App | Créer `lib/services/chip_scanner_service.dart` |
| PT12 | **[V2]** Statuts animaux trouvés — workflow (Trouvé → Pris en charge → Propriétaire contacté → Restitué → Clôturé) | Moyenne | App + Web | `animal_trouve_form_page.dart` |
| PT13 | **[V3]** IA rapprochement photos animaux perdus/trouvés | Basse | Backend | À évaluer |
| PT14 | **[V3]** Statistiques admin — animaux retrouvés, délai moyen, zones fréquentes, taux résolution | Basse | App + Web | Panel admin |

### Fiche animal — Gestion alimentation

| # | Tâche | Priorité | Repo | Fichiers probables |
|---|---|---|---|---|
| AL01 | **[V1]** Gestion alimentation — calcul ration journalière selon poids actuel + objectif de poids + type (croquettes, BARF, ration ménagère). Pour croquettes : saisie marque/référence + % protéines. Pour ration ménagère : calcul grammes par ingrédient + suggestions de recettes. Afficher ration dans fiche animal. | Haute | App + Web | `animal_fiche.dart`, `mes-animaux/[id]/page.tsx` |
| AL02 | **[V2]** Recettes ration ménagère — bibliothèque de recettes par espèce (chien, chat) avec ingrédients + quantités auto-adaptées au poids animal | Moyenne | App + Web | Créer `lib/pages/alimentation/` + `src/app/alimentation/` |

### App mobile + Web (synchronisés)

| # | Tâche | Priorité | Repo | Notes |
|---|---|---|---|---|
| T03 | Animaux perdus — contact via messagerie (objet auto) | Moyenne | App + Web | Roadmap §I.B |
| T07 | Carnet de santé — notifications vaccins/antiparasitaires (J-7, J-1, J) | Haute | App | Roadmap §III.A.b |
| T08 | Fiche animal — courbe de poids (croissance + adulte) | Moyenne | App + Web | Roadmap §III.A.b |
| T09 | Transfert de propriété animal (vente → email acheteur) | Haute | App + Web | Roadmap §III.A.c |
| T10 | Annonces — likes sur portée/bébé + notification éleveur + favoris | Haute | Web d'abord | Roadmap §VI |


---

## Terminé — Nabil (S01–S12 ✅ COMPLET)

| Tâche | Date | Repo | Fichiers modifiés |
|---|---|---|---|
| S01 — Profil pro : champs BDD + UI (rayon, espèces, horaires, certifications, réseaux, accept_new_clients) | 2026-05-27 | App | `lib/main.dart`, `lib/pages/pro/pro_profile_edit.dart`, `lib/pages/settings/main_settings.dart` |
| S02 — Annuaire services : brancher onTap + service_detail_page + service_list_page + stubs communauté | 2026-05-27 | App | `services/veterinaires_page.dart`, `service_detail_page.dart`, `service_list_page.dart`, stubs animal_friendly/evenements/promenades/forum/groupes |
| S03 — Page Services web + lien Header nav + drawers éleveur & particulier | 2026-05-27 | Web | `website/src/app/services/page.tsx`, `website/src/components/Header.tsx` |
| S04 — Agenda RDV : UI pro (pro_agenda.dart — 3 onglets demandes/à venir/historique + notes) + UI client (rdv_booking_page.dart — date/heure/animal/motif) + detail page profil pro (service_detail_page.dart) | 2026-05-27 | App | `pro_agenda.dart`, `rdv_booking_page.dart`, `service_detail_page.dart`, `service_list_page.dart` |
| Fix — Badge "Éleveur vérifié" → "Professionnel" pour pros ; navigation profil → ProProfileEditPage si isPro ; cat_pro + is_pro auto-inféré à la sauvegarde | 2026-05-27 | App | `eleveur_nav.dart`, `eleveur_home.dart`, `user_elevage_feed.dart`, `pro_profile_edit.dart` |
| S05 — Accès carnet santé animal : `animal_acces_page.dart` (demande + vue carnet), icône agenda RDV confirmé/terminé avec animal | 2026-05-28 | App | `animal_acces_page.dart`, `pro_agenda.dart` |
| S06 — CR & ordonnances : `compte_rendu_page.dart` (2 onglets texte/URL), icône agenda, sauvegarde `comptes_rendus` + `ordonnances` | 2026-05-28 | App | `compte_rendu_page.dart`, `pro_agenda.dart` |
| Fix — Nav pro : sections "Mon Élevage" et "Annonces" masquées pour les pros dans le drawer | 2026-05-28 | App | `eleveur_nav.dart` |
| Fix — Services page : bouton retour absent (automaticallyImplyLeading: false supprimé) | 2026-05-29 | App | `services_page.dart` |
| S09 — Événements : liste + filtres type + inscription "Je participe" + création | 2026-05-29 | App | `evenements_page.dart` |
| S10 — Promenades collectives : liste + niveau badge + rejoindre + création | 2026-05-29 | App | `promenades_page.dart` |
| S11 — Forum : catégories → sujets → réponses, création sujet, envoi réponse | 2026-05-29 | App | `forum_page.dart` |
| S12 — Groupes : liste tous/mes groupes, rejoindre/quitter, création, rôle admin | 2026-05-29 | App | `groupes_page.dart` |
| S07 — Registre pension : entrée/sortie animaux en pension (3 onglets, ajout via bottom sheet, marquer sorti) | 2026-05-29 | App | `registre_pension_page.dart`, `eleveur_nav.dart` |
| S08 — Animal Friendly : liste lieux Supabase + carte Google Maps + ajout lieu (app) + page web | 2026-05-29 | App + Web | `friendly_map_page.dart`, `website/src/app/animal-friendly/page.tsx`, `services/page.tsx` |

---

## Terminé récemment

| Tâche | Date | Repo | Fichiers modifiés |
|---|---|---|---|
| A10 — Feed immersif : layout full-screen, photo carrée BoxFit.contain + flou, header élevage, badge LOF/Non-LOF, description extensible, boutons d'action en colonne | 2026-05-28 | App + Web | `annonces_feed_page.dart`, `annonce_detail_page.dart`, `annonces/feed/page.tsx` |
| T01 — Animaux perdus : formulaire complet (nom depuis mes animaux, race depuis JSON, localisation) | 2026-05-28 | App + Web | `alerte_perdu_form_page.dart`, `animaux-perdus/declarer/page.tsx` |
| T02 — Animaux perdus : filtres liste (espèce, race, ville) + vue détail | 2026-05-28 | App + Web | `animaux_perdus_page.dart`, `animaux-perdus/page.tsx` |
| T04 — Messagerie : ajout au menu + redesign liste | 2026-05-28 | App + Web | Messagerie |
| T05 — Messagerie : types de conversation (annonce, perdu, élevage, libre, pro) | 2026-05-28 | App + Web | Messagerie |
| T11 — Feed annonces : visuel style "match" (photo premier plan, boutons like/favori) | 2026-05-28 | App + Web | `annonces_feed_page.dart` |
| T12 — Fix onglet annonces profil éleveur | 2026-05-28 | App + Web | Profil éleveur |
| T13 — Registre sanitaire : export (PDF/Excel) | 2026-05-28 | App + Web | Registre |
| T14 — Notifications animaux perdus : fix réception | 2026-05-28 | App | Notifications |
| T15 — Animaux perdus : carte synchronisée avec filtres liste | 2026-05-28 | App + Web | `animaux_perdus_page.dart`, `animaux-perdus/page.tsx` |
| A01 — Contrats : modèle de base modifiable | 2026-05-28 | App + Web | `contrat_reservation.dart`, `elevage/contrats/page.tsx` |
| Fix — Annonces saillie : section "Père" masquée dans le formulaire + section "Parents" masquée dans le détail | 2026-05-28 | App + Web | `create_annonce_page.dart`, `annonce_detail_page.dart`, `annonces/[id]/page.tsx` |
| Fix — Annonces saillie : prix non affiché (`saillie_prix` mal typé `numeric` → `float8` Supabase, parsing défensif, `_norm()` manquant dans mes-annonces) | 2026-05-28 | App + Web | `create_annonce_page.dart`, `annonces_feed_page.dart`, `annonce_detail_page.dart`, `mes_annonces_page.dart`, `annonces/page.tsx`, `annonces/feed/page.tsx`, `annonces/[id]/page.tsx`, `mes-annonces/page.tsx`, `annonces/creer/page.tsx`, `annonces/[id]/modifier/page.tsx` |
| A02 — Alerte page d'accueil → gestion directe (1 alerte → fiche, >1 → liste) | 2026-05-28 | App + Web | `particulier_home.dart`, `eleveur_home.dart`, `ParticulierDashboard.tsx`, `EleveurDashboard.tsx` |
| A03 — Clic long sur alerte → menu "Retrouvé" / "Supprimer" avec confirmation (+ actions propriétaire dans modale web) | 2026-05-28 | App + Web | `animaux_perdus_page.dart`, `animaux-perdus/page.tsx` |
| A07 — Saillie → gestation automatique avec date mise-bas prévue selon espèce | 2026-05-28 | App + Web | `animal_fiche.dart`, `mes-animaux/[id]/page.tsx` (petsmatch-web + website) |
| A08 — Gestation confirmée (switch + rappel écho/palpation selon espèce) + badge dans liste | 2026-05-28 | App + Web | `animal_fiche.dart`, `mes-animaux/[id]/page.tsx` (petsmatch-web + website) |
| Fix — Photos animaux perdus : object-contain + suppression render URL Supabase | 2026-05-28 | Web | `animaux-perdus/page.tsx` (petsmatch-web + website) |
| Inscription web — 3 étapes (rôle → infos perso + adresse Google Places → email/mdp) | 2026-05-28 | Web | `inscription/page.tsx` (petsmatch-web + website) |
| Fix warnings ListTile/DecoratedBox sur ExpansionTile | 2026-05-28 | App | `animal_fiche.dart`, `contrat_reservation.dart` |
| Registre E/S fiche animal — info mère (nom+puce) + auto-fill date_entrée + adresse élevage si naissance | 2026-05-28 | App | `animal_fiche.dart` |
| Registre E/S vue liste + PDF — colonne mère (nom+puce) quand provenance=naissance | 2026-05-28 | App | `registre_entree_sortie.dart` |
| Profile sync Flutter → Supabase — édition profil particulier (ville, cp, rue, tel) | 2026-05-28 | App | `info_utilisateur.dart` |
| Google Places autocomplete — ville correcte (locality, pas département) | 2026-05-28 | Web | `profil/page.tsx`, `mes-alertes/page.tsx`, `animaux-perdus/declarer/page.tsx` |
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
| A05 — Registre entrée/sortie : auto-fill provenance nom+adresse éleveur au choix "Naissance" | 2026-05 | App + Web | `registre_entree_sortie.dart`, `elevage/registre-entree-sortie/page.tsx` |
| A06 — Registre entrée/sortie : affichage infos mère (nom + puce) si animal né dans l'élevage | 2026-05 | App + Web | `registre_entree_sortie.dart`, `elevage/registre-entree-sortie/page.tsx` |
| A17 — Fix overflow cards annonces Trouver un compagnon (1 px) + animaux perdus home (7.4 px) | 2026-05-28 | App | `trouver_compagnon_page.dart`, `particulier_home.dart` |
| Feed v2 — Photo 4:5 style TikTok, header overlay foncé, dots ronds centrés, glassmorphism card bas, description extensible (DraggableScrollableSheet), "Animaux similaires" → AnnoncesPublicPage avec espèce+race pré-remplis | 2026-05-29 | App | `annonces_feed_page.dart`, `annonces_public_page.dart` |
| Push notifications likes — Firebase Cloud Function `sendLikeNotification` (Admin SDK, fcmToken Firestore), appelée depuis Flutter au moment du like + token FCM sauvegardé au login et sur onTokenRefresh | 2026-05-29 | App + Firebase Functions | `functions/alertes.js`, `functions/index.js`, `lib/main.dart`, `login_page.dart`, `annonces_feed_page.dart` |
| Fix cloche notifications — NotifBadge : polling 20s + Realtime sans filtre uid (DELETE sans REPLICA IDENTITY FULL) | 2026-05-29 | App | `notifications_page.dart` |
| Fix clic notif like → ouvre feed sur la bonne photo (initialAnnonceId + initialBebeIndex) | 2026-05-29 | App | `notifications_page.dart`, `annonces_feed_page.dart` |
| Fix déconnexion — pushAndRemoveUntil(WelcomePage) dans eleveur_nav + particulier_nav | 2026-05-29 | App | `eleveur_nav.dart`, `particulier_nav.dart` |
| Compteurs likes/favoris web — chargement global + mise à jour locale au clic | 2026-05-29 | Web | `website/src/app/annonces/feed/page.tsx` |
| Fix overflow "Dernières annonces" page Trouver un compagnon | 2026-05 | App | `trouver_compagnon_page.dart` |
| Fix affichage prix portée (tranches min/max) et saillie dans page liste annonces | 2026-05 | Web | `annonces/page.tsx` |
| Registre fiche animal — visible à la création + vue lecture seule (statut badge + tous champs) | 2026-05 | Web | `mes-animaux/[id]/page.tsx` |
| A05/A06 étendu fiche animal — auto-fill naissance + date_entree depuis date_naissance + puce/race mère visible | 2026-05 | Web | `mes-animaux/[id]/page.tsx` |
| Alerte perdue — photo de l'animal pré-remplie par défaut, texte "Changer" adaptatif | 2026-05 | Web | `animaux-perdus/declarer/page.tsx` |
| PT01 — Formulaire animal perdu : ajout pays, région, récompense, split contact (email + téléphone + messagerie toggle), pré-remplissage depuis contacts_urgence fiche animal, extraction pays/région depuis Google Places | 2026-05-29 | App + Web | `alerte_perdu_form_page.dart`, `animaux-perdus/declarer/page.tsx`, `supabase/migrations/add_alertes_perdus_fields.sql` |
| PT02 — Formulaire "Déclarer un animal trouvé" : espèce/race (autocomplete JSON), sexe, taille, couleur, puce, date, état de santé, comportement, description, adresse Google Places (rue + cp + ville + région + pays), multi-photos avec crop, contacts (email + tél + messagerie toggle), insert table `animaux_trouves` | 2026-05-29 | App + Web | `animal_trouve_form_page.dart`, `animaux-perdus/declarer-trouve/page.tsx`, `animaux_perdus_page.dart`, `eleveur_home.dart` |
| PT03 — Table Supabase `animaux_trouves` : création + RLS policies (select/insert/update/delete permissifs `USING (true)`) | 2026-05-29 | Supabase | SQL Editor |
| Suivi repro — vue détail (bottom sheet) sur clic chaleur/saillie/gestation : tous les champs affichés, badge "Confirmée" pour gestations confirmées, bouton "Confirmer la gestation" si non confirmée (app uniquement, web déjà OK) | 2026-05-29 | App | `animal_fiche.dart` |
| Sélecteur parent (père + mère) depuis mes animaux dans fiche animal | 2026-05 | App + Web | `animal_fiche.dart`, `mes-animaux/[id]/page.tsx` |
| Sélecteur mère — auto-fill race mère + date naissance mère depuis la fiche de la mère sélectionnée | 2026-05 | App + Web | `animal_fiche.dart`, `mes-animaux/[id]/page.tsx` |
| Registre vue lecture — affichage puce mère + race mère quand provenance = naissance | 2026-05 | Web | `mes-animaux/[id]/page.tsx` |

---

## Fichiers actuellement modifiés (verrou temporaire)

> Renseigner ici dès qu'on commence à travailler sur un fichier sensible.
> Effacer la ligne une fois le commit poussé.

| Fichier | Repo | Qui | Depuis |
|---|---|---|---|
| — | — | — | — |

---

## Notes techniques partagées

- **✅ Supabase migration faite (saillie_prix)** : colonne `saillie_prix float8` + `saillie_conditions text` ajoutées sur `annonces`. Utiliser `float8` (pas `numeric`) pour les colonnes prix — `numeric` est renvoyé en string par PostgREST.

- **✅ Supabase migration faite (A08)** : colonne `gestation_confirmee boolean DEFAULT false` ajoutée sur `gestations`. Le switch "Gestation confirmée" fonctionne.

- **Architecture** : Firebase Auth = auth uniquement. Toutes les données métier = Supabase. Ne jamais écrire de nouvelles données dans Firestore.
- **Firestore résiduel** : `post` (feed social), `conversations` (messagerie), `likedPost`, `bloquer` — à migrer progressivement, ne pas y ajouter de nouvelles features
- **Annonces** : 100% Supabase (create, feed, map, detail, mes-annonces, likes, favoris)
- **Races** : toujours lire depuis `assets/dog_breeds.json`, `cat_breeds.json`, etc. (9 fichiers JSON par espèce)
- **Supabase Edge Function `delete-user`** : JWT verification désactivée dans le dashboard (clé anon = format `sb_publishable_` non-JWT)
- **Firebase Storage** : photos profil, animaux, documents — URL sauvegardée dans Supabase
- **Supabase URL** : `https://zyvpngcvzrkdytypjlyq.supabase.co`

- **✅ RLS policies `animaux_trouves`** : table créée avec RLS activé. Policies permissives ajoutées (Firebase UID stocké en TEXT, pas Supabase auth.uid()) :
  ```sql
  ALTER TABLE animaux_trouves ENABLE ROW LEVEL SECURITY;
  CREATE POLICY "animaux_trouves_select_all" ON animaux_trouves FOR SELECT USING (true);
  CREATE POLICY "animaux_trouves_insert_own" ON animaux_trouves FOR INSERT WITH CHECK (true);
  CREATE POLICY "animaux_trouves_update_own" ON animaux_trouves FOR UPDATE USING (true);
  CREATE POLICY "animaux_trouves_delete_own" ON animaux_trouves FOR DELETE USING (true);
  ```
