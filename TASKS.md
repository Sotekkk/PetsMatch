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

### Tâches Angélique — Infrastructure, Profil, Admin

| # | Tâche | Priorité | Repo | Fichiers probables |
|---|---|---|---|---|
| A01b | CAPTCHA anti-robot sur les formulaires de connexion et d'inscription | Haute | App + Web | `login_page.dart`, `inscription/page.tsx` |
| A01c | Connexion avec Google (OAuth) | Haute | App + Web | `login_page.dart`, `inscription/page.tsx` |
| A09 | Suivi repro — saillie extérieure : accès infos mâle (photo, nom, puce, race) depuis éleveur externe | Moyenne | App + Web | À créer `suivi_repro.dart` + table `saillie_acces` |
| A12 | Admin — validation automatique profils éleveur/pro : algorithme (SIRET, cohérence, doublons) + envoi à l'admin si suspect | Haute | App + Web | `admin_panel.dart`, `verification_detail.dart` |
| A13 | Admin — validation automatique annonces : algorithme (cohérence espèce/race/prix, contenu signalé) + envoi à l'admin si suspect | Haute | App + Web | Panel admin |
| A14 | Vue fiche animal pour particuliers — identique à la vue profil éleveur | Haute | App + Web | ✅ Terminé 2026-06-02 (app + web) |
| A15 | Profil particulier — revoir mise en page (app) | Moyenne | App | `particulier_home.dart`, `info_utilisateur.dart` |
| A16 | Vue admin dans l'appli web | Haute | Web | `src/app/admin/` à créer |
| A16b | Panel admin — tableau de bord stats : nombre d'annonces en ligne, nombre d'animaux par espèce | Haute | App + Web | `admin_panel.dart`, `src/app/admin/page.tsx` |
| ~~A18~~ | ~~Espèce âne — ajouter partout (listes espèces, filtres, formulaires) + créer `donkey_breeds.json`~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-30 |
| ~~A19~~ | ~~Feed — filtre race dynamique selon espèce (liste JSON par espèce)~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-30 |
| A20 | Carte annonces compagnons — filtres par espèce, race, région, ville, pays, département | Haute | App | `annonces_map_page.dart` |
| A21 | ~~Sécurité avant mise en prod — voir section **Sécurité / Conformité RGPD** ci-dessous~~ → remplacé par RGPD01–RGPD07 + SEC01–SEC09 | Haute | App + Web + Supabase | Voir section dédiée |
| ~~A22~~ | ~~Mes animaux — Vue "Reproducteurs" (filtre animaux reproducteurs)~~ | ~~Moyenne~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |
| ~~A23~~ | ~~Mes animaux — Vue "Bébés" (regroupement par portée ou mois/année de naissance)~~ | ~~Moyenne~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |
| ~~A24~~ | ~~Fiche animal — courbe de poids adulte~~ | ~~Moyenne~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |
| ~~A25~~ | ~~Fiche animal — courbe de poids chiot/juvénile (courbe de croissance)~~ | ~~Moyenne~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |
| ~~A26~~ | ~~Messagerie — ajouter la flèche retour (tous les profils : éleveur, particulier, pro)~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |
| ~~A27~~ | ~~Fiche animal — modification du poids (ajouter/éditer une entrée poids) depuis l'onglet courbe de poids~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |
| ~~A28~~ | ~~Feed annonces — description manquante sur les fiches animaux individuels (hors portée)~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |
| ~~A29~~ | ~~Mes annonces — après création d'annonce, la liste ne se rafraîchit pas automatiquement au retour~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |
| ~~A30~~ | ~~Annonces — durée de vie configurable (ex. 30/60/90 jours) : expiration automatique + badge "Expire dans X jours" + notification éleveur avant expiration + possibilité de renouveler~~ | ~~Haute~~ | ~~App + Web + Firebase Functions~~ | ✅ Terminé 2026-06-02 |
| ~~A31~~ | ~~Annonces / Fiche animal — âge des bébés affiché en semaines si moins de 3 mois, en mois sinon (ex. "6 semaines" vs "4 mois")~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |
| ~~A32~~ | ~~Annonces — bouton "Pause" pour suspendre temporairement une annonce (statut `pause`), réactivation en un clic~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |
| ~~A36~~ | ~~Profil — rendre obligatoires les champs essentiels à la complétion du profil (adresse email, numéro de téléphone, adresse postale, ville/CP) : validation côté formulaire + message d'alerte si profil incomplet au login (bannière ou modal "Complétez votre profil"). App éleveur + particulier + pro.~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-06-03 — `User_Info.isProfileComplete()` + bannière ambre dans `eleveur_home` (éleveur+pro) et `particulier_home` + validation formulaire `info_utilisateur.dart` |
| ~~A37~~ | ~~Notification push mise-bas — rappel FCM J-7, J-3 et J-1 avant la date de terme estimée d'une gestation confirmée.~~ | ~~Haute~~ | ~~Firebase Functions~~ | ✅ Terminé 2026-05-31 — ⚠️ Migration SQL requise sur `gestations` (reminder_j7/j3/j1_sent) — ✅ Testé et validé |
| ~~A38~~ | ~~Profil pro — masquer le feed annonces (achat/adoption) et la section annonces éleveur. Un pro n'est pas acheteur. Garder uniquement : messagerie, services, agenda RDV, profil.~~ | ~~Moyenne~~ | ~~App~~ | ✅ Terminé 2026-06-03 — tiles "Mes Animaux" + "Mes Annonces" masqués, bannière "Trouver un compagnon" masquée, section "Dernières annonces" masquée, "Favoris" masqué dans le drawer |
| A39 | Onboarding éleveur — écrans de bienvenue (3-5 slides) au 1er login : présente les fonctions clés (mes animaux, portées, annonces, carnet santé, agenda). Mémorisé via `SharedPreferences` (`onboarding_eleveur_done`). | Haute | App + Web | Créer `lib/pages/onboarding/onboarding_eleveur.dart` + `src/app/onboarding/eleveur/page.tsx` |
| A40 | Onboarding pro — écrans de bienvenue au 1er login pro : profil visible, agenda RDV, messagerie clients, zone d'intervention. | Haute | App + Web | Créer `lib/pages/onboarding/onboarding_pro.dart` + `src/app/onboarding/pro/page.tsx` |
| A41 | Onboarding particulier — écrans de bienvenue au 1er login particulier : déclarer un animal, trouver un compagnon, alertes perdus/trouvés, messagerie. | Haute | App + Web | Créer `lib/pages/onboarding/onboarding_particulier.dart` + `src/app/onboarding/particulier/page.tsx` |
| ~~A42~~ | ~~Messagerie — supprimer une conversation complète (avec confirmation) : suppression de tous les messages Firestore de la conversation + la conversation elle-même, visible pour l'auteur uniquement (soft delete ou suppression réelle).~~ | ~~Haute~~ | ~~App~~ | ✅ Terminé 2026-05-31 — appui long → dialog confirmation → soft delete (`deletedFor.{uid}: true`). Restauration auto si nouveau message reçu. |
| ~~A43~~ | ~~Courbe de poids portée — graphique comparatif : afficher sur un même graphique les courbes de poids de tous les bébés d'une portée (une courbe par animal, couleur différente), avec l'âge en jours/semaines sur l'axe X.~~ | ~~Haute~~ | ~~App~~ | ✅ Terminé 2026-06-03 — `portee_poids_page.dart` créé (CustomPainter multi-séries, 8 couleurs, axe X en jours/semaines/mois). Icône 📊 dans le header de chaque portée dans `mes_animaux.dart`. |
| ~~A44~~ | ~~Fiche animal — pedigree : ajouter l'option photo (appareil photo + galerie) en plus du PDF existant pour uploader le document pedigree. Même crop/upload que les photos animaux.~~ | ~~Haute~~ | ~~App~~ | ✅ Terminé 2026-05-31 — bottom sheet caméra/galerie/PDF, viewer plein écran pour photos, viewer externe pour PDF. Tous les autres documents (santé, ADN…) ouvrent aussi en plein écran. |
| ~~A45~~ | ~~Alerte mise en retraite femelles — notification push + badge dans la fiche animal quand la femelle approche de l'âge de retraite reproductive selon l'espèce (ex. chienne : 7 ans, chatte : 8 ans), uniquement si non stérilisée. Cloud Function quotidienne similaire à `sendChaleursNotifications`.~~ | ~~Moyenne~~ | ~~Firebase Functions + App~~ | ✅ Terminé 2026-06-01 — `functions/retraite.js` : push J-30 (orange) + J-0 (rouge), dédup `notifs_sent`. Banner dans fiche animal. Âges : chien 7, chat 8, lapin 5, cheval 18, ovin/caprin 8, porcin 5, âne 15 ans. |
| ~~A46~~ | ~~Profils employés d'élevage — un éleveur peut créer des comptes employés rattachés à son élevage : accès aux fiches animaux (lecture + modification), planning des tâches à faire par animal/date (alimentation, soins, pesée, nettoyage), géré et révocable par l'éleveur. Table Supabase `employes` (`uid_employe`, `uid_eleveur`, `actif`) + `taches_elevage` (`titre`, `animal_id`, `date`, `statut`, `assigné_a`).~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-06-01 — Angélique |
| ~~A34~~ | ~~Suivi des chaleurs femelles — saisie de l'historique des cycles par animal (date dernière chaleur), calcul automatique de la prochaine selon l'espèce (chienne ≈ 6 mois, chatte ≈ 21 jours si non stérilisée, jument saisonnière…), rappel push + badge "Chaleurs prochaines" dans la fiche animal J-7 et J-1. Table Supabase `cycles_chaleurs` (`animal_id`, `date_debut`, `notes`).~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-06-01 — Angélique |
| ~~A33~~ | ~~Animaux trouvés — permettre à l'auteur d'éditer sa publication après déclaration (modifier description, photos, localisation, contact)~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |
| ~~A35~~ | ~~Feed annonces web — ajouter les mêmes badges que l'app : espèce (emoji + label), race, LOF/LOOF/Stud-book/Non-LOF (via `registre_type`), âge en semaines/mois/ans (via `date_naissance` / `date_naissance_animal`)~~ | ~~Haute~~ | ~~Web~~ | ✅ Terminé 2026-05-31 |

### Animaux perdus / trouvés — Spec complète : `SPEC_ANIMAUX_PERDUS_TROUVES.md`

| # | Tâche | Priorité | Repo | Fichiers probables |
|---|---|---|---|---|
| PT00 | **[V1]** "Alerte animale" — widget tableau de bord suggérant alerte lors de doublon déclaration perdu/trouvé | Haute | App + Web | `particulier_home.dart`, `eleveur_home.dart`, `ParticulierDashboard.tsx` |
| ~~PT01~~ | ~~**[V1]** Vérifier complétude formulaire "Animal perdu"~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-29 |
| ~~PT02~~ | ~~**[V1]** Déclarer animal trouvé — formulaire complet~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-29 |
| ~~PT03~~ | ~~**[V1]** Table Supabase `animaux_trouves`~~ | ~~Haute~~ | ~~Supabase~~ | ✅ Terminé 2026-05-29 |
| ~~PT04~~ | ~~**[V1]** Carte animaux perdus/trouvés — onglet Perdu/Trouvé + code couleur + filtres espèce, race, région, ville, distance~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-29 |
| ~~PT05~~ | ~~**[V1]** Bouton global "J'ai trouvé un animal" — drawer éleveur + particulier + Header web~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-29 |
| ~~PT06~~ | ~~**[V1]** Saisie manuelle numéro puce → recherche dans alertes perdus + animaux trouvés + animaux de l'élevage~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-30 |
| ~~PT07~~ | ~~**[V1]** Notifications de proximité pour les animaux trouvés (rayon 20 km d'une alerte active) — Firebase Cloud Function `notifyNearFoundAnimal`~~ | ~~Haute~~ | ~~Firebase Functions~~ | ✅ Terminé 2026-05-30 |
| ~~PT08~~ | ~~**[V1]** Messagerie automatique perdu/trouvé — conversation Firestore avec objet + message prérempli au contact~~ | ~~Moyenne~~ | ~~App + Web~~ | ✅ Terminé 2026-05-30 |
| PT09 | **[V2]** Matching automatique perdu ↔ trouvé — score pondéré (espèce+race+sexe+zone+date+couleur+puce) + notification si ≥ 90% | Haute | Firebase Functions + App + Web | Créer `matchLostFound` Cloud Function |
| PT10 | **[V2]** Table `alertes_correspondances` — stocker les paires matchées pour éviter doublons de notif | Moyenne | Supabase | Dashboard SQL Editor |
| PT11 | **[V2]** Lecteur puce Bluetooth — `ChipScannerService` (connect/disconnect/listen/parseChip/searchAnimal), protocoles BLE + ISO11784/11785. **3 contextes** : (1) élevage → ouvre fiche animal directement, (2) animal trouvé → ouvre alerte liée, (3) inconnu → propose créer/déclarer | Haute | App | Créer `lib/services/chip_scanner_service.dart` |
| PT12 | **[V2]** Statuts animaux trouvés — workflow (Trouvé → Pris en charge → Propriétaire contacté → Restitué → Clôturé) | Moyenne | App + Web | `animal_trouve_form_page.dart` |
| PT13 | **[V3]** IA rapprochement photos animaux perdus/trouvés | Basse | Backend | À évaluer |
| PT14 | **[V3]** Statistiques admin — animaux retrouvés, délai moyen, zones fréquentes, taux résolution | Basse | App + Web | Panel admin |

### Fiche animal — Gestion alimentation

| # | Tâche | Priorité | Repo | Fichiers probables |
|---|---|---|---|---|
| ~~AL01~~ | ~~**[V1]** Onglet alimentation — calcul ration journalière (croquettes marque/produit, BARF, ration ménagère) + objectif de poids~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-30 |
| AL02 | **[V2]** Recettes ration ménagère — bibliothèque par espèce (chien, chat) avec ingrédients + quantités auto-adaptées au poids | Moyenne | App + Web | Créer `lib/pages/alimentation/` + `src/app/alimentation/` |

### App mobile + Web (synchronisés)

| # | Tâche | Priorité | Repo | Notes |
|---|---|---|---|---|
| ~~T03~~ | ~~Animaux perdus — contact via messagerie (objet auto)~~ | ~~Moyenne~~ | ~~App + Web~~ | ✅ Terminé 2026-05-30 |
| ~~T07~~ | ~~Carnet de santé — notifications vaccins/antiparasitaires (J-7, J-1, J)~~ | ~~Haute~~ | ~~App~~ | ✅ Terminé 2026-06-02 — `functions/sante.js` : Cloud Function quotidienne 8h, 3 tables (vaccinations/vermifuges/antiparasitaires), paliers J-7/J-1/J-0, dédup notifs_sent | Roadmap §III.A.b |
| T08 | Fiche animal — courbe de poids (croissance + adulte) | Moyenne | App + Web | Roadmap §III.A.b |
| T09 | Transfert de propriété animal (vente → email acheteur) | Haute | App + Web | Roadmap §III.A.c |
| ~~T10~~ | ~~Annonces — likes sur portée/bébé + notification éleveur + favoris~~ | ~~Haute~~ | ~~Web d'abord~~ | ✅ Déjà terminé |

### Services — restructuration & nouvelles sections — **Nabil**

> **Nouvelle architecture Services** :
> Pôle Santé / Marketplace / Éducation & Garde / Communauté / Sorties & Voyages
> Animal Friendly est supprimé et absorbé dans Communauté + Sorties & Voyages.

| # | Tâche | Priorité | App / Web | Fichiers de départ |
|---|---|---|---|---|
| ~~S13~~ | ~~**Admin — gestion profils pro** : liste dans le panel admin, valider/refuser/suspendre, édition manuelle~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-27 |
| ~~S14~~ | ~~**Vue admin web** : reflet admin mobile (utilisateurs, filtres, fiche, validation pro, suppression)~~ | ~~Haute~~ | ~~Web~~ | ✅ Terminé 2026-05-27 |
| ~~S15~~ | ~~**Pôle Santé — vétérinaires carte** : marqueurs code couleur, filtres espèce/distance, fiche détail~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-27 |
| ~~S15b~~ | ~~**Pôle Santé — ostéopathes & kinés** : liste + carte + RDV~~ | ~~Moyenne~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |
| ~~S15c~~ | ~~**Pôle Santé — naturopathes & médecines douces**~~ | ~~Moyenne~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |
| ~~S15d~~ | ~~**Pôle Santé — assurances animaux** : section stub dans PoleSantePage~~ | ~~Basse~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |
| ~~S16~~ | ~~**Pet sitter & promeneurs — zone de travail** : rayon sur carte, filtrage annuaire par zone.~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-30 |
| ~~S17~~ | ~~**Marketplace** : renommage "Produits" → "Marketplace", sections petfood / accessoires / créateurs~~ | ~~Moyenne~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |
| ~~S18~~ | ~~**Communauté — Adoption association** : section branchée sur annuaire pros (cat_pro: association)~~ | ~~Moyenne~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |
| ~~S19~~ | ~~**Sorties & Voyages** : "Animal Friendly" renommé, architecture mise à jour app + web~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |
| ~~S20~~ | ~~**UI Services** — 5 catégories unifiées (fusion Vétos+Santé → Pôle Santé), police uniforme~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-31 |

### Agenda connecté — **Nabil** (tous les profils)
> Agenda partagé éleveur + particulier, multi-usages (RDV pros, véto, alimentation, médicaments, alerte mise-bas, visites adoption)

| # | Tâche | Priorité | App / Web | Notes |
|---|---|---|---|---|
| ~~AG01~~ | ~~**Agenda éleveur & particulier — structure de base** : pages agenda, table `agenda_events`, vue mensuelle + vue liste~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-30 |
| ~~AG02~~ | ~~**RDV pro → agenda automatique** : RDV confirmé → `agenda_events`, RDV annulé → suppression~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-30 |
| ~~AG03~~ | ~~**Notifications rappel RDV** : Cloud Function `sendRdvReminders` — rappels FCM 24h et 1h avant RDV~~ | ~~Haute~~ | ~~Firebase Functions~~ | ✅ Terminé 2026-05-30 |
| ~~AG04~~ | ~~**Alerte mise-bas** : gestation confirmée → événement `type=mise_bas` dans agenda~~ | ~~Haute~~ | ~~App + Web~~ | ✅ Terminé 2026-05-30 |
| ~~AG05~~ | ~~**Visite adoption éleveur ↔ particulier** : proposer visite depuis messagerie → 2 événements agenda~~ | ~~Moyenne~~ | ~~App + Web~~ | ✅ Terminé 2026-05-30 |
| ~~AG06~~ | ~~**Rappels médicaments & alimentation** : antiparasitaire/vaccin/visite → `agenda_events type=medication`~~ | ~~Moyenne~~ | ~~App~~ | ✅ Terminé 2026-05-30 |
| ~~AG07~~ | ~~**RDV pro — sélection animal obligatoire** : dans le formulaire de réservation, afficher clairement l'animal concerné (sélecteur prominent, nom affiché dans la liste RDV du pro et dans les notifications)~~ | ~~Haute~~ | ~~App~~ | ✅ Terminé 2026-05-31 |
| ~~AG08~~ | ~~**Agenda pro — créneaux disponibles/indisponibles** : permettre au professionnel de définir ses créneaux horaires (disponible / réservé / bloqué) depuis son agenda (`pro_agenda.dart`). Vue semaine avec cases cliquables. Stockage dans table Supabase `creneaux_pro` (`pro_uid`, `date`, `heure_debut`, `heure_fin`, `statut`). Les créneaux bloqués ne sont pas proposés lors de la réservation côté client.~~ | ~~Haute~~ | ~~App~~ | ✅ Terminé 2026-06-03 — onglet "Créneaux" dans pro_agenda (sélecteur semaine + grille 8h-19h, tap pour bloquer/débloquer, RDV visibles). Côté client rdv_booking_page filtre aussi les créneaux bloqués. ⚠️ **SQL requis** : `CREATE TABLE creneaux_pro (id uuid DEFAULT gen_random_uuid() PRIMARY KEY, pro_uid text NOT NULL, date date NOT NULL, heure_debut time NOT NULL, heure_fin time NOT NULL, statut text NOT NULL DEFAULT 'bloque', created_at timestamptz DEFAULT now(), UNIQUE(pro_uid, date, heure_debut));` |
### Conseils pratiques — **Angélique**

| # | Tâche | Priorité | Repo | Notes |
|---|---|---|---|---|
| CP01 | **Guide "Adopter un chiot"** : pages statiques ou dynamiques avec sections (choisir sa race, checklist arrivée, premiers jours, vaccination, socialisation, alimentation chiot, éducation de base). Accessible depuis l'accueil et la fiche race dans le feed. | Haute | App + Web | Créer `lib/pages/guides/` + `src/app/guides/chiot/page.tsx` |
| CP02 | **Guide "Adopter un chaton"** : même structure que CP01, adapté au chat (litière, griffoir, socialisation, stérilisation, alimentation chaton). | Haute | App + Web | `src/app/guides/chaton/page.tsx` |
| CP03 | **Guide "Adopter un lapin"** : bases de soins (cage, alimentation foin/légumes/granulés, socialisation, stérilisation, signes de santé). | Haute | App + Web | `src/app/guides/lapin/page.tsx` |

---

### Sécurité / Conformité RGPD

> **Conseil :** La base juridique doit être propre dès la V1. Avant lancement, le minimum obligatoire est : CGU + politique de confidentialité + bannière cookies + mentions légales + gestion consentements + export/suppression données + registre traitements RGPD.

#### 🔴 V1 — Obligatoire avant lancement

| # | Tâche | Priorité | Repo | Notes |
|---|---|---|---|---|
| RGPD01 | **CGU + Politique de confidentialité** — pages statiques web + lien depuis app (drawer / paramètres) | Haute | App + Web | `src/app/cgu/page.tsx`, `src/app/confidentialite/page.tsx` |
| RGPD02 | **Bannière cookies web** — opt-in/opt-out RGPD (Google Analytics, Firebase), sauvegarde consentement localStorage | Haute | Web | `src/components/CookieBanner.tsx` |
| RGPD03 | **Mentions légales** — page web (éditeur, hébergeur, responsable traitement) | Haute | Web | `src/app/mentions-legales/page.tsx` |
| RGPD04 | **Registre des traitements RGPD** — document interne listant toutes les données collectées, base légale, durée conservation, sous-traitants (Supabase, Firebase, Stripe, Google) | Haute | Interne | Document Word/Notion hors-code |
| RGPD05 | **Consentement explicite à l'inscription** — case à cocher CGU + politique confidentialité (non pré-cochée), stocké dans Supabase `users` (`cgu_accepted_at`) | Haute | App + Web | `inscription/page.tsx`, `login_page.dart` |
| RGPD06 | **Export données utilisateur** (RGPD art. 20) — bouton "Télécharger mes données" dans profil → JSON de toutes ses données Supabase (animaux, alertes, annonces, messages) | Haute | App + Web | `info_utilisateur.dart`, `profil/page.tsx` |
| RGPD07 | **Suppression compte + données** (RGPD art. 17) — bouton "Supprimer mon compte" → supprime Firebase Auth + toutes tables Supabase (cascade) + photos Storage | Haute | App + Web | `info_utilisateur.dart`, `profil/page.tsx`, Edge Function Supabase `delete-user` |

#### 🟠 V2 — Sécurité avancée

| # | Tâche | Priorité | Repo | Notes |
|---|---|---|---|---|
| SEC01 | **RLS Supabase — audit et durcissement** — revoir toutes les tables avec `USING (true)` (trop permissif), remplacer par `USING (auth.uid() = uid)` ou équivalent. Tables concernées : `animaux_trouves`, `notifications`, `messages`, `agenda_events` | Haute | Supabase | SQL Editor — policies par table |
| SEC02 | **Authentification forte (2FA)** — option opt-in : code SMS ou TOTP (Google Authenticator) à l'activation dans les paramètres | Moyenne | App + Web | Firebase Auth MFA ou Supabase Auth MFA |
| SEC03 | **Gestion rôles fins** — permissions par rôle (admin, éleveur, particulier, pro, vétérinaire) via colonne `role` Supabase + middleware Next.js + vérification Flutter | Haute | App + Web | `lib/main.dart`, `middleware.ts` |
| SEC04 | **Partage vétérinaire temporaire** — lien avec token court durée (72h) donnant accès en lecture seule au carnet de santé d'un animal | Haute | App + Web | Créer `lib/pages/partage_sante/` + table `partage_tokens` |
| SEC05 | **Logs d'accès admin** — traçabilité : qui s'est connecté, quelle fiche consultée, quelle action effectuée (archivage 6 mois) | Moyenne | App + Web | Table `audit_logs` Supabase + panel admin |
| SEC06 | **Audit actions admin** — toute action admin (valider profil, supprimer compte, modifier annonce) loggée dans `audit_logs` avec timestamp + uid admin + détail action | Haute | App + Web | `admin_panel.dart`, `src/app/admin/page.tsx` |
| SEC07 | **Chiffrement données sensibles** — numéros de puce (`identification`), données santé critiques : chiffrement AES côté serveur (Edge Function) avant stockage | Moyenne | Supabase | Edge Functions + colonne `encrypted_*` |
| SEC08 | **Anonymisation** — export stats anonymisées pour admin (pas de PII, agrégats uniquement) | Basse | App + Web | Panel admin — requêtes agrégées |
| SEC09 | **Sauvegardes automatiques** — vérifier activation snapshots Supabase (quotidien) + test restauration trimestriel | Haute | Supabase | Dashboard Supabase → Backups |

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
| A14 (app) — Fiche animal particulier : onglet Alimentation (calculateur DER/RER complet, BARF, plan repas, stérilisation), mode lecture/édition onglet Identité, passeport européen, type de poil, taille, poids, pedigree/registre adapté par espèce (LOF/LOOF/Stud-book…), stérilisation affichée dans l'onglet alimentation éleveur aussi. | 2026-06-02 | App | `animal_fiche_particulier.dart`, `mes_animaux_page.dart`, `user_feed.dart`, `animal_fiche.dart` |
| A14 (web) — Onglet Alimentation particulier web : calculateur DER/RER, BARF, plan repas, sélecteur marque Supabase, stérilisation, mode résumé dashboard. | 2026-06-02 | Web | `AlimentationTab.tsx`, `mes-animaux/[id]/page.tsx` |
| S15b/S15c/S15d/S17/S18/S19/S20 — Pôle Santé (ostéo, kiné, naturo, assurances), Marketplace, Adoption, Sorties & Voyages, UI uniforme 5 catégories | 2026-05-31 | App + Web | `veterinaires_page.dart`, `services_page.dart`, `src/app/services/page.tsx` |
| AG03 fix — rappels RDV : notif client + pro avec nom animal, colonnes `reminder_24h/1h_sent` ajoutées, déployé et testé | 2026-05-31 | Firebase Functions | `functions/agenda.js` |
| A30 — Annonces expiration : sélecteur durée 30/60/90j (app+web), badge "Expire dans Xj", bouton Renouveler, CF `sendAnnonceExpirationReminders` (expire auto + FCM J-7/J-1) | 2026-06-02 | App + Web + Firebase Functions | `create_annonce_page.dart`, `mes_annonces_page.dart`, `annonces/creer/page.tsx`, `mes-annonces/page.tsx`, `functions/annonces.js` |
| T07 — Santé rappels : Cloud Function quotidienne 8h, vaccinations + vermifuges + antiparasitaires, J-7/J-1/J-0, dédup notifs_sent | 2026-06-02 | Firebase Functions | `functions/sante.js`, `functions/index.js` |
| Fix — `_deptCtrl` manquant dans `animal_trouve_form_page.dart` (crash au lancement) | 2026-05-31 | App | `animal_trouve_form_page.dart` |
| S13 — Admin gestion profils pro : liste panel admin, valider/refuser/suspendre, édition manuelle | 2026-05-27 | App + Web | `admin_panel.dart`, `user_detail.dart`, `src/app/admin/page.tsx` |
| S14 — Vue admin web : reflet admin mobile (utilisateurs, filtres, fiche, validation pro, suppression) | 2026-05-27 | Web | `src/app/admin/page.tsx` |
| S15 — Pôle Santé vétérinaires : carte + marqueurs + filtres espèce/distance + fiche détail + zone intervention | 2026-05-27 | App + Web | `service_list_page.dart`, `service_detail_page.dart`, `src/app/services/carte/page.tsx` |
| S16 — Zone intervention pro : rayon sur carte Google Maps + filtre "Proche de moi" app+web | 2026-05-30 | App + Web | `pro_profile_edit.dart`, `pro_zone_page.dart`, `service_list_page.dart`, `src/app/services/carte/page.tsx` |
| AG01 — Agenda structure de base : page Flutter + web, table `agenda_events`, vue calendrier + liste | 2026-05-30 | App + Web | `lib/pages/agenda/agenda_page.dart`, `website/src/app/agenda/page.tsx` |
| AG02 — RDV pro → agenda automatique : confirmé → `agenda_events`, annulé/refusé → suppression | 2026-05-30 | App + Web | `pro_agenda.dart` |
| AG03 — Rappels RDV : Cloud Function `sendRdvReminders` (FCM 24h + 1h avant) | 2026-05-30 | Firebase Functions | `functions/agenda.js`, `functions/index.js` |
| AG04 — Alerte mise-bas : gestation confirmée → événement `type=mise_bas` dans agenda | 2026-05-30 | App | `animal_fiche.dart` |
| AG05 — Visite adoption : proposer visite depuis chat → 2 événements agenda (un par participant) | 2026-05-30 | App | `chatScreen.dart` |
| AG06 — Rappels médicaments : antiparasitaire/vaccin/visite → `agenda_events type=medication` | 2026-05-30 | App | `animal_fiche.dart` |
| Services — Messagerie : bouton "Contacter" fiche pro ouvre conversation Firestore (categorie: services) | 2026-05-30 | App | `service_detail_page.dart` |
| A18 — Espèce âne ajoutée partout (sélecteurs, filtres feed, formulaires) + `donkey_breeds.json` créé | 2026-05-30 | App + Web | `annonces_feed_page.dart`, `mes_animaux.dart`, `annonces/feed/page.tsx` |
| A19 — Feed filtres espèce + race : liste déroulante searchable (bottom sheet Flutter / dropdown web) | 2026-05-30 | App + Web | `annonces_feed_page.dart`, `annonces/feed/page.tsx` |
| A10 — Feed immersif : layout full-screen, photo carrée BoxFit.contain + flou, header élevage, badge LOF/Non-LOF, description extensible, boutons d'action en colonne | 2026-05-28 | App + Web | `annonces_feed_page.dart`, `annonce_detail_page.dart`, `annonces/feed/page.tsx` |
| T01 — Animaux perdus : formulaire complet (nom depuis mes animaux, race depuis JSON, localisation) | 2026-05-28 | App + Web | `alerte_perdu_form_page.dart`, `animaux-perdus/declarer/page.tsx` |
| PT-fixes — Animaux perdus/trouvés : correctifs filtres (race, région web, département), FAB supprimé du menu (ajouté en AppBar actions), champ `departement` dans les 2 tables + 4 formulaires (perdu/trouvé app+web), contact/partager fonctionnel pour trouvés (fix `user_uid` + `contact_messagerie`), bouton Réinitialiser filtres mobile | 2026-05-30 | App + Web | `animaux_perdus_page.dart`, `alerte_perdu_form_page.dart`, `animal_trouve_form_page.dart`, `animaux-perdus/page.tsx`, `animaux-perdus/declarer/page.tsx`, `animaux-perdus/declarer-trouve/page.tsx` |
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
