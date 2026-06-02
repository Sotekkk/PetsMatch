# PetsMatch — Spécifications fonctionnelles complètes
**Dernière mise à jour : 2026-06-01**
**Branche active : `feature/v2-updates`**

---

## 1. Présentation du projet

PetsMatch est une plateforme dédiée aux éleveurs et propriétaires d'animaux, disponible sur **3 supports synchronisés** :

| Support | Technologie | Statut |
|---|---|---|
| App Android | Flutter | ✅ En production |
| App iOS | Flutter | 🔜 À publier |
| Site web | Next.js 14 (App Router) + TypeScript + Tailwind | ✅ En développement actif |

**Profils utilisateur :**
- **Éleveur** : gestion d'élevage complète (animaux, portées, annonces, registre, contrats, employés)
- **Particulier** : animaux personnels, recherche d'annonces, animaux perdus, agenda, messagerie
- **Professionnel** (vétérinaire, comportementaliste, pet sitter, etc.) : agenda RDV, zone d'intervention, messagerie clients, carnet santé partagé
- **Admin** : panel de validation et de gestion (app + web)

**Règle de développement :** toute fonctionnalité est déployée sur les 3 versions simultanément. Design et couleurs identiques (voir section 9).

---

## 2. Architecture technique

### Stack

| Composant | Solution | Notes |
|---|---|---|
| Authentification | Firebase Auth | UID = clé étrangère dans toutes les tables Supabase |
| Base de données | Supabase (PostgreSQL) | Migration Firestore → Supabase terminée en mai 2026 |
| Stockage fichiers | Firebase Storage | Photos animaux, documents, pedigrees |
| Push notifications | Firebase Cloud Messaging (FCM) | Alertes perdus, likes, rappels santé, mise-bas, retraite |
| App mobile | Flutter (Dart) | Android + iOS |
| Site web | Next.js 14 (App Router) + TypeScript + Tailwind CSS | |
| Cloud Functions | Firebase Cloud Functions (Node.js) | Notifications push planifiées |

**URL Supabase :** `https://zyvpngcvzrkdytypjlyq.supabase.co`

**RLS Supabase :** permissif (USING (true)) sur toutes les tables — à durcir avant lancement production.

**Firestore résiduel (ne plus y ajouter de features) :** conversations, messages, likedPost, bloquer, fcmToken.

**Architecture navigation Flutter :** `IndexedStack` + `GlobalKey<NavigatorState>` par onglet + `PopScope(canPop: false)` → bottom nav persistante dans toutes les sous-pages.

---

## 3. Tables Supabase principales

```
users                   profils utilisateurs (sync Firebase UID)
animaux                 fiches animaux
vaccinations            carnet santé — vaccins
traitements             carnet santé — antiparasitaires, vermifuges
visites                 carnet santé — visites vétérinaires
saillies                suivi repro
gestations              suivi repro (gestation_confirmee boolean)
alertes_perdus          animaux perdus (+ departement TEXT)
animaux_trouves         animaux trouvés (+ departement TEXT)
annonces                marketplace (croquettes, portées, saillies)
notifications           centre de notifications
agenda_events           agenda partagé éleveur/particulier/pro
conversations           messagerie (Firestore → à migrer)
messages                messagerie (Firestore → à migrer)
alimentations           données alimentation par animal
marques_aliments        base marques/gammes avec densité + doses JSONB
registre_entree_sortie  registre officiel éleveur
employes                comptes employés d'élevage
taches_elevage          planning tâches quotidiennes
cycles_chaleurs         suivi cycles chaleurs femelles
agenda_events           agenda RDV, mise-bas, rappels médicaments
creneaux_pro            créneaux disponibles/indisponibles pro (à créer)
partage_tokens          partage carnet santé temporaire (à créer)
alertes_correspondances matching perdu ↔ trouvé (à créer)
audit_logs              logs actions admin (à créer)
```

---

## 4. Fonctionnalités implémentées — V1 ✅

### 4.1 Authentification et profil

| Fonctionnalité | App | Web |
|---|---|---|
| Inscription en 3 étapes (rôle → infos perso → email/mdp) | ✅ | ✅ |
| Connexion / déconnexion | ✅ | ✅ |
| Profil éleveur (nom élevage, adresse, photos) | ✅ | ✅ |
| Profil particulier (prénom, nom, ville, téléphone) | ✅ | ✅ |
| Profil professionnel (vétérinaire, comportementaliste, etc.) | ✅ | ✅ |
| Synchronisation Firestore + Supabase à chaque édition | ✅ | ✅ |
| Géocodage adresse Google Places (lat/lng + locality) | ✅ | ✅ |
| Zone d'intervention pro (rayon sur carte Google Maps) | ✅ | ✅ |

### 4.2 Mes animaux — Fiche animal

**Onglet Identité**

| Fonctionnalité | App | Web |
|---|---|---|
| Espèce, race (autocomplete JSON), sexe, date naissance, couleur, poids | ✅ | ✅ |
| Photo principale + galerie (crop carré) | ✅ | ✅ |
| Numéro de puce / tatouage | ✅ | ✅ |
| Pedigree : type par espèce, upload PDF + photos | ✅ | ✅ |
| Généalogie : père et mère (nom, race, puce, date naissance) | ✅ | ✅ |
| Sélecteur père/mère depuis "mes animaux" (bottom sheet) | ✅ | ✅ |
| Registre Entrées/Sorties (provenance, destinataire, cause de sortie, département) | ✅ | ✅ |
| Auto-fill registre depuis généalogie (provenance = naissance) | ✅ | ✅ |
| Champs importation : référence, date naissance mère | ✅ | ✅ |

**Onglet Suivi Repro (éleveur)**

| Fonctionnalité | App | Web |
|---|---|---|
| Cycles de chaleurs (date début/fin, historique, intervalles) | ✅ | ✅ |
| Alerte chaleurs J-7 et J-1 (push FCM) | ✅ | — |
| Banner "Chaleurs prochaines" dans la fiche animal | ✅ | — |
| Saillies (partenaire interne, date, notes) | ✅ | ✅ |
| Gestation auto-créée depuis saillie (durée par espèce) | ✅ | ✅ |
| Gestation confirmée (switch + bannière rappel vétérinaire par espèce) | ✅ | ✅ |
| Notification mise-bas push FCM : J-7, J-3 et J-1 avant terme | ✅ | — |
| Alerte mise-bas → événement agenda automatique | ✅ | ✅ |
| Portées (fiches bébés, photos, poids, race, stérilisation, passeport) | ✅ | ✅ |
| Vue détail chaleur/saillie/gestation (bottom sheet) | ✅ | ✅ |

**Onglet Carnet Santé**

| Fonctionnalité | App | Web |
|---|---|---|
| Vaccinations (nom, date, date rappel) | ✅ | ✅ |
| Antiparasitaires / Vermifuges | ✅ | ✅ |
| Visites vétérinaires | ✅ | ✅ |
| Rappels push FCM (J-7, J-1, Jour J) pour vaccins + antiparasitaires | ✅ | — |
| Rappels → événements agenda automatiques | ✅ | — |
| Courbe de poids adulte | ✅ | ✅ |
| Courbe de poids croissance (juvénile) | ✅ | ✅ |
| Ajout/édition entrée poids depuis l'onglet courbe | ✅ | ✅ |
| Partage carnet santé avec pro via RDV (accès lecture vétérinaire) | ✅ | — |

**Onglet Alimentation** *(mai 2026)*

| Fonctionnalité | App | Web |
|---|---|---|
| Calcul DER : 70 × kg^0.75 × facteurs (activité, phase, stérilisation, repro, énergie race) | ✅ | ✅ |
| Types de ration : Croquettes, BARF, Ménagère, Mixte | ✅ | ✅ |
| Mixte — 3 options de 2e composant (Pâtée / BARF / Ménagère) | ✅ | ✅ |
| Option repas séparés (croquettes matin, pâtée soir) | ✅ | ✅ |
| Plan de repas journalier détaillé | ✅ | ✅ |
| Vue résumé : calories nécessaires, ration actuelle, calories apportées, indicateur ✅/⚠️ | ✅ | ✅ |
| Doses modifiables manuellement (override calculateur) | ✅ | ✅ |
| Densité énergétique manuelle (depuis le paquet) | ✅ | ✅ |
| Recette bottom sheet : ménagère (proportions par kg) + BARF (grammes/composant) | ✅ | ✅ |
| Recherche marque/gamme depuis base de données | ✅ | ✅ |
| Interpolation doses fabricant par poids | ✅ | ✅ |
| Vue calculateur accessible via "Recalculer la ration" | ✅ | ✅ |

**Vues "Mes animaux"**

| Fonctionnalité | App | Web |
|---|---|---|
| Liste animaux avec barre de recherche (nom + puce) | ✅ | ✅ |
| Vue "Reproducteurs" (filtre animaux reproducteurs) | ✅ | ✅ |
| Vue "Bébés" (regroupement par portée ou mois/année de naissance) | ✅ | ✅ |

**Alertes retraite reproductive** *(juin 2026)*

| Fonctionnalité | App | Web |
|---|---|---|
| Push FCM J-30 (orange) + J-0 (rouge) quand la femelle approche de l'âge de retraite | ✅ | — |
| Banner dans la fiche animal (par espèce : chien 7 ans, chat 8 ans, lapin 5 ans, etc.) | ✅ | — |

### 4.3 Base de données marques d'aliments

| Catégorie | Nb gammes |
|---|---|
| Croquettes chien adulte | 20 |
| Croquettes chat adulte | 10 |
| Pâtées chien adulte | 8 |
| Pâtées chat adulte | 12 |
| Granulés cheval adulte | 4 |
| Granulés lapin adulte | 6 |
| Croquettes chiot (puppy) | 14 |
| Pâtées chiot (puppy) | 3 |
| Croquettes chaton (kitten) | 7 |
| Pâtées chaton (kitten) | 7 |
| **Total** | **~91 gammes** |

Marques : Royal Canin, Hill's Science Plan, Purina (ONE + Pro Plan), Farmina N&D, Josera, Brit Care, Belcando, Taste of the Wild, Orijen, Animonda, Schesir, Almo Nature, True Instinct, Edgard & Cooper, Virbac HPM, Calibra, Advance, Oxbow, Versele-Laga, Cunipic, Cavalor, Spillers, Equifirst.

Doses calculées depuis formule DER (adulte × 1.6 chien / × 1.4 chat ; junior × 2.0 chiot / × 2.5 chaton).

> ⚠️ **Migrations à exécuter dans Supabase SQL Editor :**
> `migration_marques_v2.sql` puis `migration_marques_v3_junior.sql`

### 4.4 Annonces (marketplace)

| Fonctionnalité | App | Web |
|---|---|---|
| Création annonce (compagnon / portée / saillie) avec galerie crop | ✅ | ✅ |
| Liste "Mes annonces" + filtres statut (disponible / pause / archivée) | ✅ | ✅ |
| Modifier / Mettre en pause / Supprimer une annonce | ✅ | ✅ |
| Feed immersif style TikTok (photo 4:5, glassmorphism, description extensible) | ✅ | ✅ |
| Filtres : espèce, race (autocomplete JSON), type, distance | ✅ | ✅ |
| Badges : LOF/LOOF/Stud-book, âge en semaines/mois selon l'âge | ✅ | ✅ |
| Likes animaux + notification push éleveur (Firebase Cloud Function) | ✅ | ✅ |
| Compteurs likes/favoris temps réel | ✅ | ✅ |
| Favoris utilisateur | ✅ | ✅ |
| Clic notification like → annonce directe (initialAnnonceId + initialBebeIndex) | ✅ | — |
| "Animaux similaires" → liste filtrée avec espèce+race pré-remplis | ✅ | — |
| Badge espèce âne (+ `donkey_breeds.json`) | ✅ | ✅ |

### 4.5 Animaux perdus / trouvés

| Fonctionnalité | App | Web |
|---|---|---|
| Déclarer un animal perdu (formulaire complet : nom, race, puce, localisation, contact, récompense) | ✅ | ✅ |
| Déclarer un animal trouvé (formulaire complet : espèce, race, état santé, comportement, multi-photos) | ✅ | ✅ |
| Édition d'une déclaration trouvée après publication | ✅ | ✅ |
| Pré-remplissage photo depuis fiche animal | ✅ | ✅ |
| Saisie manuelle numéro puce → recherche dans perdus + trouvés + animaux élevage | ✅ | ✅ |
| Auto-fill département (Google Places) dans les 4 formulaires | ✅ | ✅ |
| Liste avec filtres (espèce, race, ville, région, département) + réinitialisation | ✅ | ✅ |
| Carte interactive (onglet Perdu/Trouvé, code couleur, filtres synchronisés) | ✅ | ✅ |
| Contact via messagerie interne (objet auto-généré) | ✅ | ✅ |
| Partager (génère message texte) | ✅ | ✅ |
| Notifications push FCM aux éleveurs proches (rayon 20 km) — perdus ET trouvés | ✅ | — |
| Appui long → menu "Retrouvé" / "Supprimer" avec confirmation | ✅ | ✅ |

### 4.6 Services professionnels

| Fonctionnalité | App | Web |
|---|---|---|
| **Pôle Santé** — Vétérinaires : carte + marqueurs + filtres espèce/distance + fiche détail | ✅ | ✅ |
| Pôle Santé — Ostéopathes & kinés | ✅ | ✅ |
| Pôle Santé — Naturopathes & médecines douces | ✅ | ✅ |
| Pôle Santé — Assurances animaux (stub) | ✅ | ✅ |
| **Pet sitters & promeneurs** : zone de travail sur carte, filtrage par zone | ✅ | ✅ |
| **Marketplace** : petfood / accessoires / créateurs | ✅ | ✅ |
| **Communauté — Adoption association** : annuaire pros (cat_pro: association) | ✅ | ✅ |
| **Sorties & Voyages** (ex-Animal Friendly) : lieux animal-friendly, carte Google Maps, ajout lieu | ✅ | ✅ |
| **Événements** : liste + filtres type + inscription "Je participe" + création | ✅ | — |
| **Promenades collectives** : liste + niveau badge + rejoindre + création | ✅ | — |
| **Forum** : catégories → sujets → réponses, création, réponse | ✅ | — |
| **Groupes** : liste tous/mes groupes, rejoindre/quitter, création, rôle admin | ✅ | — |
| Messagerie : "Contacter" fiche pro → conversation Firestore (cat: services) | ✅ | — |

### 4.7 Agenda RDV

| Fonctionnalité | App | Web |
|---|---|---|
| Structure agenda : vue mensuelle + vue liste, table `agenda_events` | ✅ | ✅ |
| Réservation RDV pro : date/heure/animal/motif | ✅ | ✅ |
| Pro : 3 onglets (demandes / à venir / historique) + notes | ✅ | ✅ |
| Sélection animal obligatoire à la réservation | ✅ | ✅ |
| RDV confirmé → `agenda_events` auto ; annulé → suppression | ✅ | ✅ |
| Rappels FCM 24h + 1h avant RDV (client + pro, avec nom animal) | ✅ | — |
| Alerte mise-bas → événement `type=mise_bas` dans agenda | ✅ | ✅ |
| Visite adoption éleveur ↔ particulier → 2 événements agenda | ✅ | — |
| Rappels médicaments / vaccins → `agenda_events type=medication` | ✅ | — |

### 4.8 Profils employés d'élevage *(juin 2026)*

| Fonctionnalité | App | Web |
|---|---|---|
| Éleveur crée des comptes employés rattachés à l'élevage | ✅ | ✅ |
| Employé : accès fiches animaux (lecture + modification) | ✅ | ✅ |
| Planning des tâches par animal/date (alimentation, soins, pesée, nettoyage) | ✅ | ✅ |
| Autorisations fines + révocation par l'éleveur | ✅ | ✅ |
| Tables Supabase : `employes` + `taches_elevage` | ✅ | ✅ |

### 4.9 Admin

| Fonctionnalité | App | Web |
|---|---|---|
| Gestion profils pro : liste, valider/refuser/suspendre, édition manuelle | ✅ | ✅ |
| Suppression profil complet (Firebase Auth + Supabase cascade + Storage) | ✅ | — |
| Tableau de bord stats (à compléter) | — | — |

### 4.10 Messagerie

| Fonctionnalité | App | Web |
|---|---|---|
| Liste conversations + flèche retour | ✅ | ✅ |
| Chat temps réel | ✅ | ✅ |
| Types : Annonce / Animal perdu / Contact élevage / Discussion libre / Services | ✅ | ✅ |
| Appui long → "Supprimer la conversation" (soft delete `deletedFor.{uid}`) | ✅ | — |

### 4.11 Élevages (annuaire)

| Fonctionnalité | App | Web |
|---|---|---|
| Liste élevages avec filtres (espèce, race, localisation) | ✅ | ✅ |
| Fiche élevage | ✅ | ✅ |
| Contacter l'éleveur | ✅ | ✅ |

### 4.12 Registre et documents (éleveur)

| Fonctionnalité | App | Web |
|---|---|---|
| Registre Entrées/Sorties (toutes espèces) | ✅ | ✅ |
| Suivi sanitaire (vaccins, traitements, visites) + export PDF | ✅ | ✅ |
| Contrats de réservation (modèle de base modifiable) | ✅ | ✅ |
| Registre pension (entrée/sortie animaux en pension) | ✅ | — |
| Comptes rendus & ordonnances vétérinaires | ✅ | — |
| Factures | ✅ | — |
| Export PDF (registre, contrats) | ✅ | — |

### 4.13 Notifications push (Firebase FCM)

| Type | Déclencheur | App | Web |
|---|---|---|---|
| Alertes animaux perdus | Nouvel animal perdu dans un rayon de 20 km | ✅ | — |
| Alertes animaux trouvés | Nouvel animal trouvé dans un rayon de 20 km | ✅ | — |
| Likes/favoris | Like sur une annonce de l'éleveur | ✅ | — |
| Rappels chaleurs | J-7 et J-1 avant la prochaine chaleur estimée | ✅ | — |
| Rappels mise-bas | J-7, J-3 et J-1 avant le terme de gestation confirmée | ✅ | — |
| Rappels carnet santé | J-7, J-1 et Jour J (vaccins, antiparasitaires) | ✅ | — |
| Rappels RDV | 24h et 1h avant le RDV (client + pro) | ✅ | — |
| Retraite reproductive | J-30 (orange) et Jour J (rouge) — femelles proches de l'âge de retraite | ✅ | — |
| Badge cloche | Realtime Supabase + polling 20s (fallback DELETE sans REPLICA IDENTITY) | ✅ | ✅ |

---

## 5. Fonctionnalités en cours / À faire — V2

### 5.1 Authentification et profil

| # | Fonctionnalité | Priorité | Support |
|---|---|---|---|
| A01b | CAPTCHA anti-robot sur connexion et inscription | Haute | App + Web |
| A01c | Connexion avec Google (OAuth) | Haute | App + Web |
| A14 | Vue fiche animal pour particuliers (identique à la vue éleveur) | Haute | App + Web |
| A15 | Profil particulier — revoir mise en page | Moyenne | App |
| A36 | Champs profil obligatoires (email, téléphone, adresse, ville/CP) + bannière "Complétez votre profil" | Haute | App + Web |
| A38 | Profil pro : masquer feed annonces et section annonces éleveur (un pro n'achète pas) | Moyenne | App + Web |
| A39 | Onboarding éleveur (3-5 slides au 1er login) | Haute | App + Web |
| A40 | Onboarding pro (agenda RDV, profil visible, messagerie, zone) | Haute | App + Web |
| A41 | Onboarding particulier (déclarer un animal, trouver un compagnon, alertes) | Haute | App + Web |

### 5.2 Annonces

| # | Fonctionnalité | Priorité | Support |
|---|---|---|---|
| A30 | Durée de vie configurable (30/60/90 jours) : expiration auto + badge "Expire dans X jours" + notification avant expiration + renouvellement | Haute | App + Web |
| — | Description père/mère visible sur fiche annonce (particulier) | Moyenne | App + Web |
| — | Identification mère obligatoire selon espèce | Moyenne | App + Web |
| A20 | Carte annonces compagnons avec filtres (espèce, race, région, ville, département) | Haute | App |

### 5.3 Animaux perdus / trouvés

| # | Fonctionnalité | Priorité | Support |
|---|---|---|---|
| PT00 | Widget tableau de bord suggérant alerte lors de doublon déclaration perdu/trouvé | Haute | App + Web |
| PT09 | Matching automatique perdu ↔ trouvé : score pondéré (espèce+race+sexe+zone+date+couleur+puce) + notification si ≥ 90% | Haute | Firebase Functions |
| PT10 | Table `alertes_correspondances` — stocker les paires matchées pour éviter doublons notif | Moyenne | Supabase |
| PT11 | Lecteur puce Bluetooth (BLE + ISO11784/11785) : 3 contextes (élevage / animal trouvé / inconnu) | Haute | App |
| PT12 | Statuts animaux trouvés — workflow : Trouvé → Pris en charge → Propriétaire contacté → Restitué → Clôturé | Moyenne | App + Web |
| PT13 | IA rapprochement photos animaux perdus/trouvés | Basse | Backend |
| PT14 | Stats admin : animaux retrouvés, délai moyen, zones fréquentes, taux résolution | Basse | Admin |

### 5.4 Suivi repro

| # | Fonctionnalité | Priorité | Support |
|---|---|---|---|
| A09 | Saillie extérieure : accès infos du mâle externe (photo, nom, puce, race) depuis éleveur externe | Moyenne | App + Web |
| — | Saillies croisées : MAJ automatique de la fiche partenaire (même élevage) | Moyenne | App + Web |

### 5.5 Fiche animal / Alimentation

| # | Fonctionnalité | Priorité | Support |
|---|---|---|---|
| A43 | Courbe de poids portée comparative : toutes les courbes d'une portée sur un même graphique + comparaison inter-portées | Haute | App + Web |
| — | Interface admin pour ajouter/modifier marques d'aliments sans code | Haute | Web admin |
| — | Historique changements d'alimentation (marque/gamme + date) | Moyenne | App + Web |
| — | Alertes prise/perte de poids rapide | Moyenne | App + Web |
| — | Ration gestante (+25% à partir de S5) et lactation (+50%) | Haute | App + Web |
| — | Chiots/chatons en sevrage (progression 4→8 semaines) | Moyenne | App + Web |
| AL02 | Recettes ration ménagère en base de données (admin) | Moyenne | App + Web |
| — | Transfert de propriété : lien email → fiche animal sur nouveau compte → historique propriétaires | Haute | App + Web |
| — | Animaux "Anciens" (post-transfert) : lecture seule | Moyenne | App + Web |

### 5.6 Agenda

| # | Fonctionnalité | Priorité | Support |
|---|---|---|---|
| AG08 | Pro — créneaux disponibles/indisponibles : définir horaires (table `creneaux_pro`), vue semaine, exclusion à la réservation | Haute | App + Web |

### 5.7 Services / Communauté

| # | Fonctionnalité | Priorité | Support |
|---|---|---|---|
| — | Événements, promenades, forum, groupes — miroir web | Moyenne | Web |

### 5.8 Admin

| # | Fonctionnalité | Priorité | Support |
|---|---|---|---|
| A12 | Validation automatique profils éleveur/pro : algorithme (SIRET, cohérence, doublons) + envoi à l'admin si suspect | Haute | App + Web |
| A13 | Validation automatique annonces : algorithme (cohérence espèce/race/prix, contenu signalé) | Haute | App + Web |
| A16 | Panel admin web complet (reflet admin app) | Haute | Web |
| A16b | Tableau de bord stats admin : annonces en ligne, animaux par espèce, utilisateurs | Haute | App + Web |

### 5.9 Contenu / Guides

| # | Fonctionnalité | Priorité | Support |
|---|---|---|---|
| CP01 | Guide "Adopter un chiot" : race, checklist, vaccination, socialisation, alimentation, éducation | Haute | App + Web |
| CP02 | Guide "Adopter un chaton" : litière, griffoir, socialisation, stérilisation, alimentation | Haute | App + Web |
| CP03 | Guide "Adopter un lapin" : cage, alimentation foin/légumes/granulés, stérilisation, signes santé | Haute | App + Web |

### 5.10 Registre et documents

| # | Fonctionnalité | Priorité | Support |
|---|---|---|---|
| — | Import Excel registre Entrées/Sorties | Moyenne | Web |
| — | Export PDF web (registre, contrats) | Moyenne | Web |
| — | Contrats payants (offre future) | Basse | App + Web |

---

## 6. Sécurité / Conformité RGPD

### V1 — Obligatoire avant lancement public

| # | Fonctionnalité | Priorité |
|---|---|---|
| RGPD01 | CGU + Politique de confidentialité — pages statiques web + lien depuis app | Haute |
| RGPD02 | Bannière cookies web — opt-in/opt-out RGPD (Google Analytics, Firebase), consentement localStorage | Haute |
| RGPD03 | Mentions légales — éditeur, hébergeur, responsable de traitement | Haute |
| RGPD04 | Registre des traitements RGPD — document interne (données collectées, base légale, durée, sous-traitants) | Haute |
| RGPD05 | Consentement explicite à l'inscription — case à cocher CGU (non pré-cochée), `cgu_accepted_at` Supabase | Haute |
| RGPD06 | Export données utilisateur (RGPD art. 20) — bouton "Télécharger mes données" → JSON complet | Haute |
| RGPD07 | Suppression compte + données (RGPD art. 17) — cascade Firebase Auth + Supabase + Storage | Haute |

### V2 — Sécurité avancée

| # | Fonctionnalité | Priorité |
|---|---|---|
| SEC01 | RLS Supabase durcies — remplacer `USING (true)` par politiques Firebase UID par table | Haute |
| SEC02 | 2FA opt-in — TOTP / SMS | Moyenne |
| SEC03 | Gestion rôles fins — admin / éleveur / particulier / pro / vétérinaire (middleware Next.js + Flutter) | Haute |
| SEC04 | Partage vétérinaire temporaire — lien token 72h → carnet santé en lecture seule | Haute |
| SEC05 | Logs d'accès admin — traçabilité 6 mois | Moyenne |
| SEC06 | Audit actions admin — `audit_logs` avec timestamp + uid admin + détail | Haute |
| SEC07 | Chiffrement données sensibles — puce + données santé (AES Edge Function) | Moyenne |
| SEC08 | Anonymisation stats admin (pas de PII) | Basse |
| SEC09 | Sauvegardes automatiques Supabase + test restauration trimestriel | Haute |

---

## 7. Fonctionnalités V3 — Planifiées

| Fonctionnalité | Complexité |
|---|---|
| iOS — publication App Store | Moyenne |
| iOS — fix notifications push (alertes perdus non reçues) | Haute |
| PT13 — IA rapprochement photos animaux perdus/trouvés | Très haute |
| Portées — suivi poids individuels chiots/chatons avec courbe de croissance comparative | Haute |
| Portées — sevrage progressif (4→8 semaines) | Moyenne |
| Partage vétérinaire temporaire (token 72h) | Haute |
| Lecteur puce Bluetooth (BLE + ISO11784/11785) | Très haute |
| Statistiques plateforme admin (animaux retrouvés, délai, zones, taux résolution) | Moyenne |
| Lien alimentation ↔ courbe de poids (alerte si objectif atteint) | Moyenne |
| Chiots/chatons en sevrage (progression alimentaire 4→8 semaines) | Moyenne |

---

## 8. Tâches en attente — par priorité

### Priorité immédiate
1. **Exécuter les migrations SQL** dans Supabase SQL Editor :
   - `supabase/migration_marques_v2.sql` (~50 gammes adultes chien/chat/cheval/lapin)
   - `supabase/migration_marques_v3_junior.sql` (~34 gammes junior/puppy/kitten)
2. **Migration SQL `gestations`** — ajouter colonnes `reminder_j7/j3/j1_sent` (requis par la Cloud Function mise-bas A37)

### Haute priorité
3. Durée de vie annonces (A30) — colonne `expires_at` + expiration auto + notification
4. RGPD V1 — 7 points obligatoires avant lancement public (RGPD01 à RGPD07)
5. Onboarding éleveur / particulier / pro (A39–A41)
6. Vue fiche animal pour particuliers (A14)
7. Champs profil obligatoires + bannière complétion (A36)
8. Validation automatique profils et annonces (A12, A13)
9. Carte annonces compagnons avec filtres (A20)

### Priorité moyenne
10. Interface admin web marques aliments
11. Transfert de propriété animal (A09 étendu)
12. Courbe de poids portée comparative (A43)
13. Ration gestante / lactation / sevrage
14. AG08 — Créneaux disponibles/indisponibles pro
15. Guides adopter (CP01–CP03)
16. Google OAuth connexion (A01c)
17. CAPTCHA (A01b)
18. Matching automatique perdu ↔ trouvé (PT09)

### Priorité basse / V3
19. Lecteur puce Bluetooth (PT11)
20. IA rapprochement photos (PT13)
21. Statuts workflow animaux trouvés (PT12)
22. iOS notifications push fix
23. Import Excel registre web

---

## 9. Design system

| Élément | Valeur |
|---|---|
| Couleur primaire (CTA) | `#6E9E57` (vert) |
| Couleur secondaire (nav, titres) | `#0C5C6C` (teal) |
| Couleur hover/actif | `#094F5D` |
| Fond général | `#F5F7F0` |
| Texte principal | `#1F2A2E` |
| Police | Galey (titres + UI) |
| Coins arrondis | `rounded-xl` (12px) / `rounded-2xl` (16px) |
| Photos | Crop carré — `image_cropper` (Flutter) |

---

## 10. Fichiers clés

| Fichier | Rôle |
|---|---|
| `lib/pages/eleveur/animaux/animal_fiche.dart` | Fiche animal (4 onglets : Identité, Repro, Santé, Alimentation) |
| `lib/pages/eleveur/nav/eleveur_nav.dart` | Navigation éleveur (bottom nav persistante) |
| `lib/pages/particulier/nav/particulier_nav.dart` | Navigation particulier |
| `lib/pages/annonces/annonces_feed_page.dart` | Feed annonces immersif TikTok |
| `lib/pages/animaux_perdus/animaux_perdus_page.dart` | Animaux perdus/trouvés (liste + carte) |
| `lib/pages/services/veterinaires_page.dart` | Pôle Santé (vétérinaires, ostéo, naturo) |
| `lib/pages/agenda/agenda_page.dart` | Agenda éleveur/particulier |
| `lib/pages/pro/pro_agenda.dart` | Agenda pro (demandes RDV, à venir, historique) |
| `functions/alertes.js` | Cloud Functions notifications perdus + likes |
| `functions/agenda.js` | Cloud Functions rappels RDV |
| `functions/retraite.js` | Cloud Functions alerte retraite reproductive |
| `supabase/schema.sql` | Schéma complet Supabase |
| `supabase/migration_marques_v2.sql` | Marques adultes (~50 gammes) — à exécuter |
| `supabase/migration_marques_v3_junior.sql` | Marques junior (~34 gammes) — à exécuter |
| `src/app/mes-animaux/[id]/page.tsx` | Fiche animal web (4 onglets) |
| `src/app/annonces/feed/page.tsx` | Feed annonces web |
| `src/app/mes-annonces/page.tsx` | Gestion annonces éleveur web |
| `src/app/admin/page.tsx` | Panel admin web |

---

## 11. Notes techniques

- **Ne jamais écrire dans Firestore** pour les nouvelles features — tout dans Supabase.
- **Races** : toujours lire depuis `assets/dog_breeds.json`, `cat_breeds.json`, etc. (9 fichiers JSON par espèce, dont âne).
- **Prix Supabase** : utiliser `float8`, pas `numeric` (numeric est renvoyé en string par PostgREST).
- **`saillie_prix float8` + `saillie_conditions text`** : ajoutés sur `annonces`.
- **`gestation_confirmee boolean DEFAULT false`** : ajouté sur `gestations`.
- **Supabase Edge Function `delete-user`** : JWT verification désactivée dans le dashboard.
- **FCM Token** : sauvegardé dans Firestore (`fcmToken`) ET Supabase (`fcm_token`) au login et sur `onTokenRefresh`.
- **Annonces** : 100% Supabase (create, feed, map, detail, mes-annonces, likes, favoris).
- **Photos** : Firebase Storage → URL sauvegardée dans Supabase.
