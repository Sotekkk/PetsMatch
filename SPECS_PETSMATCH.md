# PetsMatch — Spécifications fonctionnelles complètes
**Dernière mise à jour : 2026-06-09**
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
| ~~A30~~ | ~~Durée de vie configurable (30/60/90 jours) : expiration auto + badge "Expire dans X jours" + notification avant expiration + renouvellement~~ | ✅ Terminé 2026-06-02 | App + Web + Firebase |
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
| AG08 | Pro — créneaux disponibles/indisponibles : définir horaires (table `creneaux_pro`), vue semaine, exclusion à la réservation | Haute | App + Web | ✅ Implémenté 2026-06-09 |

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

### 5.11 Facturation éleveur — Module métier indépendant

> **Profil éleveur · Abonnement PRO+ · Non couplé au billing PetsMatch**

Module métier permettant aux éleveurs de gérer leur facturation clients de manière autonome, réutilisable et compatible Web / Mobile.

#### Périmètre fonctionnel

**Création de facture**

- Informations vendeur (auto-remplies depuis profil élevage : SIRET, nom, adresse, logo)
- Informations acheteur (depuis table `breeder_customers` : nom, adresse, email, téléphone)
- Animal vendu : `animal_id`, `portee_id` (optionnel), `contrat_id` (optionnel)
- Prix HT, taux TVA (0%, 5.5%, 10%, 20%), total TTC
- Date de facturation, date d'échéance
- Conditions de vente, notes libres

**Liaison animal vendu**

- Association `animal_id` → historique ventes affiché dans la fiche animal
- `portee_id` optionnel (vente issue d'une portée)
- `contrat_id` optionnel (lien vers contrat de réservation existant)

**Gestion des paiements et statuts**

| Statut | Description |
|---|---|
| `brouillon` | Facture non envoyée — modifiable |
| `envoyée` | Envoyée au client (email/PDF) |
| `acompte` | Acompte reçu — reste à payer > 0 |
| `partiellement_payée` | Plusieurs règlements partiels |
| `payée` | Soldée intégralement |
| `annulée` | Annulation avec avoir optionnel |

**Gestion des acomptes**

- Montant acompte prévu
- Reste à payer calculé automatiquement
- Date de paiement prévue / réelle
- Historique règlements par facture (`breeder_payments`)

**Génération PDF**

- Logo élevage (depuis profil)
- Coordonnées élevage + coordonnées client
- Tableau détail animal (race, date naissance, puce, LOF)
- Prix HT + TVA + TTC
- Conditions de vente
- Zone signature optionnelle
- Numéro de facture auto-incrémenté (ex: `ELEVAGE-2026-0001`)

**Exports**

- PDF — facture unitaire téléchargeable
- Excel — liste de toutes les factures (CA, statuts, échéances)
- CSV — export comptabilité (compatible Quadratus, EBP, Sage)

**Tableau de bord élevage**

- CA total (année en cours + historique)
- Nombre de ventes par période
- Factures ouvertes (envoyées non payées)
- Acomptes reçus en attente de solde
- Montants en attente (total impayés)

#### Tables Supabase

| Table | Colonnes principales |
|---|---|
| `breeder_invoices` | `id UUID`, `uid_eleveur TEXT`, `customer_id UUID`, `animal_id TEXT`, `portee_id UUID?`, `contrat_id UUID?`, `numero TEXT`, `statut TEXT`, `date_facture DATE`, `date_echeance DATE?`, `prix_ht NUMERIC`, `taux_tva NUMERIC`, `total_ttc NUMERIC`, `conditions TEXT`, `notes TEXT`, `created_at TIMESTAMPTZ` |
| `breeder_invoice_items` | `id UUID`, `invoice_id UUID`, `description TEXT`, `quantite INT`, `prix_unitaire_ht NUMERIC`, `taux_tva NUMERIC` |
| `breeder_customers` | `id UUID`, `uid_eleveur TEXT`, `nom TEXT`, `prenom TEXT`, `email TEXT`, `telephone TEXT`, `adresse TEXT`, `cp TEXT`, `ville TEXT`, `pays TEXT` |
| `breeder_payments` | `id UUID`, `invoice_id UUID`, `montant NUMERIC`, `date_paiement DATE`, `mode TEXT` (virement/chèque/espèces/CB), `notes TEXT` |
| `breeder_invoice_animal_link` | `invoice_id UUID`, `animal_id TEXT`, `portee_id UUID?` |

RLS : toutes les tables filtrées par `uid_eleveur = auth.uid()` (données privées).

#### Permissions

- Profil éleveur uniquement
- Abonnement PRO+ requis (vérification `abonnement` Supabase)
- Données strictement privées (RLS par UID)

#### Évolutions futures (V3+)

- Facturation électronique (norme Chorus Pro)
- API comptabilité (Quadratus, EBP, Sage)
- Signature électronique (DocuSign / Yousign)
- Multi-TVA intracommunautaire

---

### 5.12 Facturation PetsMatch — Billing plateforme

> **Profils éleveur et pro uniquement · V1 = abonnements + achats ponctuels + factures PDF · Non couplé à la facturation éleveur**

Module léger, production-ready, scalable V2. Aucune dette technique. Pas de plateforme de facturation électronique.

#### Plans d'abonnement — Éleveur

| Plan | Prix mensuel | Prix annuel | Cible |
|---|---|---|---|
| FREE | 0€ | 0€ | Éleveurs débutants |
| PRO | 15€/mois | 149€/an | Éleveurs actifs |
| PREMIUM | 25€/mois | 249€/an | Éleveurs pro + module facturation |

Note : PREMIUM = PRO+ dans le code (champ `plan` Supabase = `'premium'`).

| Fonctionnalité | FREE | PRO | PREMIUM |
|---|---|---|---|
| Annonces actives | 3 | 10 | Illimité |
| Durée annonce | 30j | 45j | 60j |
| Renouvellement annonce | Manuel | Manuel + rappel J-5 | Auto-renouvellement |
| Boost inclus/mois | 0 | 1 | 3 |
| Gestion employés | ❌ | 2 max | Illimité |
| Registre + contrats PDF | Basique | Complet | Complet + export CSV/Excel |
| Module facturation éleveur (5.11) | ❌ | ❌ | ✅ |
| Badge élevage vérifié | ❌ | ✅ | ✅ |
| Statistiques annonces | ❌ | Basique | Avancées |

> **Contexte métier :** les chiots et chatons sont vendus entre 8 et 12 semaines. Une annonce de portée est publiée ~4 semaines avant la mise en vente. La durée maximale de 60 jours (PREMIUM) couvre l'ensemble du cycle de vente sans générer d'annonces obsolètes. Le renouvellement automatique (PREMIUM) est la vraie valeur différenciante, pas la durée brute.

Fonctionnalités abonnement : upgrade, downgrade, annulation immédiate ou en fin de période, renouvellement automatique.

#### Plans d'abonnement — Professionnel

Trois plans distincts pour les profils pro (vétérinaire, comportementaliste, pet sitter, pension).

| Plan | Prix mensuel | Cible |
|---|---|---|
| FREE | 0€ | Visibilité de base |
| PRO | 12€/mois | Agenda avancé + badge vérifié |
| PENSION | 19€/mois | Pet sitters et pensionnaires |

Note : vétérinaires et comportementalistes utilisent généralement leur propre logiciel métier — le plan PENSION ne leur est pas proposé par défaut.

| Fonctionnalité | FREE | PRO | PENSION |
|---|---|---|---|
| Annuaire visible | ✅ basique | ✅ mis en avant + badge vérifié | ✅ mis en avant + badge vérifié |
| Zone d'intervention carte | ✅ | ✅ | ✅ |
| Agenda RDV | ✅ | ✅ + créneaux avancés (AG08) | ✅ + créneaux avancés (AG08) |
| Messagerie prioritaire | ❌ | ✅ | ✅ |
| Registre pension (entrées/sorties) | ❌ | ❌ | ✅ |
| Fiche santé animaux en pension (lecture via token partage) | ❌ | ❌ | ✅ |
| Contrats pension PDF | ❌ | ❌ | ✅ |
| Facturation clients (module 5.11) | ❌ | ❌ | ✅ |

#### Achats ponctuels (boosts)

| Produit | Prix | Durée | Description |
|---|---|---|---|
| Boost annonce | 1,99€ | 48h | Remontée temporaire en tête de feed |
| Mise à la une | 4,99€ | 7 jours | Badge + position prioritaire |
| Remontée annonce | 0,99€ | Instantané | Re-publication dans le feed |
| Annonce supplémentaire | 2,99€ | Selon plan | Quota annonces au-delà du plan |
| Pack 3 boosts 48h | 4,99€ | 3 × 48h | Bundle (économie vs 3 × 1,99€) |

#### Architecture modules

```
billing/
  subscriptions/   — plans, upgrade/downgrade, annulation
  payments/        — paiements ponctuels + provider abstrait
  invoice/         — génération PDF, stockage, envoi
  admin_billing/   — tableau de bord admin revenus
```

Patterns : Repository, Providers séparés, DTO dédiés. L'UI ne connaît pas le provider de paiement.

#### PaymentService — Interface abstraite

- `createPayment(userId, type, amount, currency)` → `Payment`
- `verifyPayment(paymentId)` → `PaymentStatus`
- `cancelSubscription(subscriptionId)` → `bool`
- `refund(paymentId, amount?)` → `bool`

Implémentation par défaut : **Stripe** (Cloud Functions existantes `createStripePaymentIntent` / `createStripeSubscription`).

#### InvoiceService

- `generateInvoice(paymentId)` → PDF créé et stocké dans Supabase Storage `/invoices/PM-YYYY-NNNNNN.pdf`
- `downloadInvoice(invoiceId)` → URL signée
- `sendInvoice(invoiceId, email)` → envoi email

Numérotation automatique : `PM-YYYY-000001` (séquence Supabase).

#### Contenu PDF facture

- Logo PetsMatch
- Numéro de facture (`PM-YYYY-NNNNNN`)
- Date de facturation
- Nom et adresse client
- Détail produit / plan
- Montant HT + taux TVA (20%) + Montant TTC
- Conditions générales de vente (extrait)
- QR code optionnel (lien vérification)

#### Tables Supabase

| Table | Colonnes principales |
|---|---|
| `subscriptions` | `id UUID`, `user_id TEXT`, `plan TEXT`, `billing_cycle TEXT` (monthly/annual), `status TEXT`, `price NUMERIC`, `start_date DATE`, `end_date DATE`, `payment_provider_id TEXT`, `profile_type TEXT` (breeder/pro/pension), `created_at TIMESTAMPTZ` |
| `payments` | `id UUID`, `user_id TEXT`, `type TEXT` (subscription/boost/une/remontee/annonce_sup), `amount NUMERIC`, `currency TEXT`, `status TEXT` (pending/succeeded/failed/refunded), `provider_transaction_id TEXT`, `created_at TIMESTAMPTZ` |
| `invoices` | `id UUID`, `user_id TEXT`, `payment_id UUID`, `numero TEXT` UNIQUE, `pdf_url TEXT`, `montant_ht NUMERIC`, `taux_tva NUMERIC`, `montant_ttc NUMERIC`, `sent_at TIMESTAMPTZ`, `created_at TIMESTAMPTZ` |

RLS : toutes les tables filtrées par `user_id = auth.uid()` (lecture/écriture). Admin via service role.

#### UI utilisateur

**Mobile — Page abonnements**
- Affichage plans FREE / PRO / PREMIUM (éleveur) ou FREE / PRO / PENSION (pro) avec comparatif fonctionnalités
- Boutons upgrade / downgrade / annuler avec confirmation
- Badge "Plan actuel" + date renouvellement

**Mobile — Page "Mes paiements"**
- Onglets : Abonnements | Achats | Factures
- Téléchargement PDF par facture
- Statut visuels (payé ✓ / échec ✗ / remboursé ↩)

**Web — Billing page**
- Synchronisé avec mobile
- Téléchargement PDF depuis navigateur

#### Admin billing

- Liste tous paiements (filtre statut, plan, période)
- Liste abonnements actifs + churn
- Échecs de paiement (retry manuel)
- Remboursements
- Stats revenus : CA mensuel, MRR (Monthly Recurring Revenue), ARR

#### Évolutions V2+

- Facturation électronique (Chorus Pro)
- Multi-devises (CHF, GBP, USD)
- Factures TVA intracommunautaire
- API export comptabilité (Quadratus, Sage)

---

### 5.14 Profil vétérinaire — add-in carnet de santé

> **Profil pro sous-type vétérinaire · 3 niveaux · Positionné comme canal 
> de visibilité + gain de temps consultation, non comme logiciel vétérinaire**

Le vétérinaire utilise déjà son logiciel métier (Vétocom, Vetup, Covetrus...). 
PetsMatch lui apporte l'accès aux carnets santé déjà remplis par les éleveurs 
et propriétaires, sans double saisie, et une visibilité locale auprès d'une 
communauté d'éleveurs actifs.

---

#### Plans vétérinaire

| Plan | Prix | Cible |
|---|---|---|
| Basique | 0€ (inclus dans PRO Pro) | Visibilité annuaire + lecture via token |
| Avancé | 29€/mois | Cabinets indépendants 1-3 praticiens |
| Clinique | 49€/mois | Cliniques multi-praticiens |

---

#### Fonctionnalités par plan

| Fonctionnalité | Basique | Avancé | Clinique |
|---|---|---|---|
| **Annuaire & visibilité** | | | |
| Profil visible dans le pôle santé (carte + liste) | ✅ | ✅ | ✅ |
| Badge "Vétérinaire vérifié" (validation SIRET/RPPS) | ✅ | ✅ | ✅ |
| Fiche détaillée (spécialités, espèces, horaires, photos) | Basique | Complète | Complète |
| Position mise en avant dans les résultats | ❌ | ✅ | ✅ |
| **Carnet santé — lecture** | | | |
| Lecture via token 72h partagé par le propriétaire | ✅ | ✅ | ✅ |
| Accès lecture permanent si propriétaire l'autorise | ❌ | ✅ | ✅ |
| Vue consolidée multi-animaux d'un élevage (si éleveur autorise) | ❌ | ✅ | ✅ |
| **Carnet santé — écriture** | | | |
| Ajouter vaccinations depuis la consultation | ❌ | ✅ | ✅ |
| Ajouter antiparasitaires / vermifuges | ❌ | ✅ | ✅ |
| Ajouter compte-rendu visite (texte libre + date) | ❌ | ✅ | ✅ |
| Ajouter ordonnance (PDF uploadé) | ❌ | ✅ | ✅ |
| Rappels automatiques push au propriétaire (rappels vaccins ajoutés) | ❌ | ✅ | ✅ |
| **Agenda & RDV** | | | |
| Réception demandes RDV via PetsMatch | ✅ | ✅ | ✅ |
| Créneaux disponibles/indisponibles (AG08) | ❌ | ✅ | ✅ |
| **Multi-praticiens** | | | |
| Comptes praticiens multiples rattachés à la clinique | ❌ | ❌ | ✅ (5 max) |
| Historique des interventions par praticien | ❌ | ❌ | ✅ |
| **Exports** | | | |
| Export PDF historique animal (pour remise au propriétaire) | ❌ | ✅ | ✅ |
| Export CSV données patients (compatible logiciels vétérinaires) | ❌ | ❌ | ✅ |

---

#### Flux d'accès au carnet santé

**Accès temporaire (tous plans)**
1. Le propriétaire ou éleveur génère un lien token depuis la fiche animal
2. Le token est valide 72h (table `partage_tokens` — SEC04)
3. Le vétérinaire ouvre le lien → vue lecture seule du carnet santé complet
4. Aucune authentification requise pour la lecture via token

**Accès permanent (Avancé + Clinique)**
1. Le vétérinaire envoie une demande d'accès à l'éleveur/propriétaire depuis sa fiche
2. L'éleveur approuve depuis son app → stocké dans `vet_access_grants`
3. Le vétérinaire voit l'animal dans sa liste "Mes patients" 
4. L'éleveur peut révoquer l'accès à tout moment

**Écriture dans le carnet (Avancé + Clinique)** ✅ Implémenté 2026-06-09
- Chaque entrée créée par le vétérinaire est taguée `source: 'veterinaire'` + `vet_id`
- Le champ "Vétérinaire" est pré-rempli avec le nom du compte connecté et verrouillé
- L'éleveur/propriétaire reçoit une notification push à chaque ajout (`notifyOwnerVetEntry` Cloud Function)
- Les entrées vétérinaires sont en lecture seule pour l'éleveur (bouton supprimer masqué)
- Le vétérinaire peut supprimer ses propres entrées (uniquement les siennes)
- Chaque entrée vétérinaire est aussi inscrite dans le `registre_sanitaire` de l'éleveur (via `RegistreHelper`)
- Migration : `supabase/migration_vet06_health_source.sql` (colonnes `source`/`vet_id` sur 5 tables santé)

---

#### Tables Supabase à créer

| Table | Colonnes principales |
|---|---|
| `vet_access_grants` | `id UUID`, `vet_id TEXT`, `owner_id TEXT`, `animal_id TEXT`, `granted_at TIMESTAMPTZ`, `revoked_at TIMESTAMPTZ`, `status TEXT` (active/revoked) |
| `vet_consultations` | `id UUID`, `vet_id TEXT`, `animal_id TEXT`, `date DATE`, `motif TEXT`, `compte_rendu TEXT`, `ordonnance_url TEXT`, `created_at TIMESTAMPTZ` |
| `vet_praticiens` | `id UUID`, `clinique_id TEXT` (uid compte clinique), `nom TEXT`, `prenom TEXT`, `rpps TEXT`, `specialites TEXT[]`, `created_at TIMESTAMPTZ` |

Colonnes à ajouter sur tables existantes :
- `vaccinations` : `source TEXT DEFAULT 'owner'` (owner/veterinaire), `vet_id TEXT`
- `traitements` : `source TEXT DEFAULT 'owner'`, `vet_id TEXT`
- `visites` : `source TEXT DEFAULT 'owner'`, `vet_id TEXT`, `ordonnance_url TEXT`

RLS : `vet_access_grants` lisible par `vet_id = auth.uid()` ET `owner_id = auth.uid()`.
Écriture dans `vaccinations`/`traitements`/`visites` autorisée si `vet_access_grants` 
actif pour cet animal.

---

#### UI vétérinaire

**Dashboard vétérinaire (app + web)**
- Liste "Mes patients" : animaux avec accès permanent accordé
- Recherche patient par nom / puce / propriétaire
- Accès rapide "Scanner un token" (QR code ou saisie manuelle)
- Agenda RDV du jour en vue prioritaire

**Fiche animal — vue vétérinaire**
- Identité : espèce, race, sexe, âge, poids, puce (lecture seule)
- Onglet Carnet santé : vaccinations, traitements, visites (lecture + écriture selon plan)
- Onglet Généalogie : père/mère (lecture seule, utile pour races à risque génétique)
- Bouton "Ajouter une entrée" → bottom sheet avec type (vaccin / traitement / visite / ordonnance)
- Badge source sur chaque entrée : "Ajouté par Dr. Dupont" vs "Ajouté par l'éleveur"

**Onboarding vétérinaire**
- Étape 1 : Vérification RPPS (numéro 11 chiffres) ou SIRET cabinet
- Étape 2 : Profil cabinet (nom, adresse, espèces traitées, spécialités, photo)
- Étape 3 : Zone d'intervention sur carte
- Étape 4 : Choix du plan (Basique / Avancé / Clinique) avec 3 mois offerts Avancé
  au lancement si zone avec >10 éleveurs PetsMatch actifs

---

#### Stratégie de lancement

- Offrir 3 mois Avancé gratuits aux vétérinaires dans les zones avec ≥10 éleveurs 
  PetsMatch actifs → créer le cercle vertueux (éleveur voit son vet sur PetsMatch → 
  partage son carnet → vet voit la valeur → souscrit)
- Ne pas prospecter les vétérinaires sans éleveurs actifs dans leur zone d'abord
- Priorité : éleveurs canins (34% des chiens achetés chez éleveurs selon données ICAD)

---

#### Gestion des retards — alertes patients

> **Disponible dès le plan Avancé (vétérinaire) et Essentiel (para-médicaux)**
> **Déclenchement automatique · Notification push FCM + SMS optionnel**

Le professionnel signale un retard depuis son dashboard.
Tous les patients ayant un RDV dans les 3 heures suivantes
reçoivent une alerte automatique avec le délai estimé.

---

##### Fonctionnement côté professionnel

**Déclarer un retard :**
1. Depuis le dashboard → vue agenda du jour → bouton "Signaler un retard"
2. Saisie du délai estimé (curseur : 15 / 30 / 45 / 60 / 90+ min)
3. Message optionnel personnalisé (texte libre, 140 caractères max)
4. Confirmation → envoi automatique aux patients concernés

**Règles de déclenchement des alertes :**

| Délai déclaré | Action automatique |
|---|---|
| < 30 min | Aucune alerte envoyée (délai considéré acceptable) |
| ≥ 30 min | Notification push à tous les patients RDV dans les 3h |
| ≥ 60 min | Push + SMS (si numéro renseigné) + option report RDV proposée |
| ≥ 90 min | Push + SMS + report automatique proposé + flag admin |

**Mise à jour du retard :**
Le professionnel peut mettre à jour le délai estimé à tout moment.
Chaque mise à jour déclenche une nouvelle notification uniquement
si le délai augmente (pas de spam si le retard se réduit).

---

##### Fonctionnement côté patient (propriétaire / éleveur)

**Notification reçue (push FCM) :**
🕐 Dr. Martin a du retard
Votre RDV de 14h30 est décalé d'environ 45 min.
→ Confirmer ma présence  |  Reporter mon RDV

**Actions disponibles depuis la notification :**
- **Confirmer ma présence** : le patient confirme qu'il peut attendre
- **Reporter mon RDV** : ouvre le sélecteur de créneaux disponibles
  du praticien pour choisir une nouvelle date
- **Contacter le cabinet** : ouvre la messagerie in-app directement

**Si retard ≥ 60 min — option report automatique :**
Le patient reçoit une proposition de 3 créneaux alternatifs
(prochains disponibles dans l'agenda du praticien).
S'il ne répond pas dans les 30 min → RDV maintenu par défaut.

---

##### Tables Supabase

| Table | Colonnes principales |
|---|---|
| `agenda_retards` | `id UUID`, `pro_id TEXT`, `date DATE`, `declared_at TIMESTAMPTZ`, `delai_min INT`, `message TEXT`, `statut TEXT` (actif/resolu), `updated_at TIMESTAMPTZ` |
| `agenda_retard_responses` | `id UUID`, `retard_id UUID`, `event_id UUID` (RDV concerné), `patient_id TEXT`, `response TEXT` (confirme/reporte/nc), `responded_at TIMESTAMPTZ` |

Colonne à ajouter sur `agenda_events` :
- `retard_id UUID` (lien vers le retard actif s'il y en a un)
- `retard_delai_min INT` (délai communiqué au patient)

---

##### Cloud Function `onRetardDeclared`

Déclenchée à chaque INSERT ou UPDATE sur `agenda_retards`
où `delai_min >= 30` :

1. Récupère tous les `agenda_events` du pro pour les 3 prochaines heures
   avec `statut = 'confirmé'`
2. Pour chaque patient concerné :
   - Envoie notification push FCM avec deeplink vers son RDV
   - Si `delai_min >= 60` → envoie SMS via Twilio (si `phone` renseigné)
3. Si `delai_min >= 60` → génère 3 créneaux alternatifs et les joint
   à la notification
4. Si `delai_min >= 90` → crée une alerte dans le dashboard admin
   PetsMatch (suivi qualité)
5. Logge chaque envoi dans `agenda_retard_responses`
   avec `response = 'nc'` (en attente de réponse)

---

##### Résolution du retard

Quand le professionnel marque le retard comme résolu
(`statut = 'resolu'`) :
- Notification push envoyée aux patients n'ayant pas encore répondu :
  "Le retard est résorbé — votre RDV est maintenu à l'heure prévue"
- Les patients ayant demandé un report conservent leur nouveau créneau

---

##### UI dashboard pro — vue agenda enrichie

- Badge orange "En retard — 45 min" visible sur le RDV en cours
- Bandeau en haut du dashboard si retard actif déclaré
- Compteur temps réel : nb patients notifiés / nb confirmés / nb reports
- Bouton "Mettre à jour le délai" et "Retard résorbé" toujours accessibles

---

#### Évolutions V3+

- Intégration API sortante vers logiciels vétérinaires (Vétocom, Vetup) via webhook
- Signature électronique ordonnances (Yousign)
- Téléconsultation vétérinaire (lien vidéo depuis la fiche animal)
- Score de santé animal (indicateur synthétique basé sur historique carnet)

---

### 5.15 Profils soins & para-médicaux — ostéo/kiné et maréchal-ferrant

> **Groupe A — Soins · Architecture similaire au profil vétérinaire (5.14) dont ils héritent la base · Différenciés par leurs spécificités métier**

Ces profils interviennent physiquement sur l'animal. Ils ont besoin de lire le carnet santé et d'y ajouter leurs propres entrées. Le maréchal-ferrant est spécifique aux équidés et dispose en plus d'un onglet dédié dans la fiche animal.

---

#### Sous-profils concernés

| Sous-profil | Espèces cibles | Validation identité |
|---|---|---|
| Ostéopathe animalier | Toutes | Diplôme ostéopathie animale (upload PDF) |
| Kinésithérapeute animalier | Toutes | Diplôme kiné animale (upload PDF) |
| Maréchal-ferrant | Équidés uniquement (cheval, âne, poney) | Brevet professionnel maréchalerie (upload PDF) |

---

#### Plans tarifaires

| Plan | Prix | Fonctionnalités clés |
|---|---|---|
| FREE | 0€ | Annuaire basique, lecture via token 72h |
| Essentiel | 19€/mois | Accès lecture permanent, ajout entrées carnet santé, agenda avancé |
| Pro | 29€/mois | + Facturation clients, exports PDF/CSV, multi-intervenants (3 max) |

Réduction annuelle : Essentiel 190€/an · Pro 290€/an (2 mois offerts)

---

#### Fonctionnalités communes ostéo/kiné + maréchal

| Fonctionnalité | FREE | Essentiel | Pro |
|---|---|---|---|
| Profil annuaire (carte + liste + fiche détaillée) | Basique | Complet + mis en avant | Complet + mis en avant |
| Badge professionnel vérifié | ✅ | ✅ | ✅ |
| Zone d'intervention carte | ✅ | ✅ | ✅ |
| Agenda RDV (réception demandes) | ✅ | ✅ + créneaux avancés | ✅ + créneaux avancés |
| Messagerie clients | ✅ | ✅ | ✅ |
| Lecture carnet santé via token 72h | ✅ | ✅ | ✅ |
| Accès lecture permanent (si propriétaire autorise) | ❌ | ✅ | ✅ |
| Ajouter séance dans carnet santé (date, type, notes, compte-rendu) | ❌ | ✅ | ✅ |
| Notification push propriétaire à chaque ajout | ❌ | ✅ | ✅ |
| Export PDF compte-rendu séance | ❌ | ✅ | ✅ |
| Facturation clients (module 5.11 adapté) | ❌ | ❌ | ✅ |
| Export CSV données patients | ❌ | ❌ | ✅ |
| Comptes multi-intervenants (cabinet) | ❌ | ❌ | ✅ (3 max) |

---

#### Onglet équestre dédié — maréchal-ferrant uniquement

Onglet "Maréchalerie" ajouté dans la fiche animal pour les équidés uniquement (espèce = cheval / âne / poney). Visible par le propriétaire ET le maréchal si accès accordé.

**Données trackées par pied (ant. gauche / ant. droit / post. gauche / post. droit) :**

| Champ | Type |
|---|---|
| Date de passage | DATE |
| Type d'intervention | TEXT (parage / ferrure / déferrage / rééquilibrage) |
| Type de fer posé | TEXT (fer classique / plastique / orthopédique / déferré) |
| Prochain passage prévu | DATE |
| Observations (aplombs, pathologie) | TEXT |
| Photos (avant/après) | ARRAY url Firebase Storage |
| Maréchal intervenant | TEXT (vet_id → table `vet_praticiens` adaptée) |

**Rappel push FCM** : J-7 avant le prochain passage prévu → propriétaire ET maréchal.

**Tables Supabase à créer :**

| Table | Colonnes principales |
|---|---|
| `marechalerie_passages` | `id UUID`, `animal_id TEXT`, `marechal_id TEXT`, `date DATE`, `prochain_passage DATE`, `pied TEXT` (ant_gauche/ant_droit/post_gauche/post_droit), `type_intervention TEXT`, `type_fer TEXT`, `observations TEXT`, `photos TEXT[]`, `created_at TIMESTAMPTZ` |

Colonnes à ajouter sur `animaux` :
- `marechal_id TEXT` (maréchal habituel — accès permanent)
- `dernier_passage_marechal DATE`
- `prochain_passage_marechal DATE`

---

#### Accès carnet santé — règles identiques au vétérinaire (5.14)

Utilise les mêmes tables `vet_access_grants` et le même flux d'autorisation. Champ `pro_type TEXT` ajouté sur `vet_access_grants` : valeurs : 'veterinaire' / 'osteo' / 'kine' / 'marechal'

Les entrées carnet santé créées par ces profils sont taguées `source: 'pro_sante'` + `pro_id` + `pro_type`.

---

#### UI spécifique

**Dashboard ostéo/kiné**
- Liste "Mes patients" avec dernière séance + prochain RDV
- Vue agenda : séances du jour avec fiche animal accessible en 1 clic
- Bouton rapide "Ajouter séance" depuis la liste patients

**Dashboard maréchal-ferrant**
- Liste "Mes chevaux" triée par date prochain passage (les plus urgents en premier)
- Alerte rouge si prochain passage dépassé
- Vue carte : localisation géographique de ses clients (optimisation tournées)
- Bouton "Planifier tournée" → liste ordonnée par zone géographique

---

#### Gestion des retards — alertes patients

> **Disponible dès le plan Avancé (vétérinaire) et Essentiel (para-médicaux)**
> **Déclenchement automatique · Notification push FCM + SMS optionnel**

Le professionnel signale un retard depuis son dashboard.
Tous les patients ayant un RDV dans les 3 heures suivantes
reçoivent une alerte automatique avec le délai estimé.

---

##### Fonctionnement côté professionnel

**Déclarer un retard :**
1. Depuis le dashboard → vue agenda du jour → bouton "Signaler un retard"
2. Saisie du délai estimé (curseur : 15 / 30 / 45 / 60 / 90+ min)
3. Message optionnel personnalisé (texte libre, 140 caractères max)
4. Confirmation → envoi automatique aux patients concernés

**Règles de déclenchement des alertes :**

| Délai déclaré | Action automatique |
|---|---|
| < 30 min | Aucune alerte envoyée (délai considéré acceptable) |
| ≥ 30 min | Notification push à tous les patients RDV dans les 3h |
| ≥ 60 min | Push + SMS (si numéro renseigné) + option report RDV proposée |
| ≥ 90 min | Push + SMS + report automatique proposé + flag admin |

**Mise à jour du retard :**
Le professionnel peut mettre à jour le délai estimé à tout moment.
Chaque mise à jour déclenche une nouvelle notification uniquement
si le délai augmente (pas de spam si le retard se réduit).

---

##### Fonctionnement côté patient (propriétaire / éleveur)

**Notification reçue (push FCM) :**
🕐 Dr. Martin a du retard
Votre RDV de 14h30 est décalé d'environ 45 min.
→ Confirmer ma présence  |  Reporter mon RDV

**Actions disponibles depuis la notification :**
- **Confirmer ma présence** : le patient confirme qu'il peut attendre
- **Reporter mon RDV** : ouvre le sélecteur de créneaux disponibles
  du praticien pour choisir une nouvelle date
- **Contacter le cabinet** : ouvre la messagerie in-app directement

**Si retard ≥ 60 min — option report automatique :**
Le patient reçoit une proposition de 3 créneaux alternatifs
(prochains disponibles dans l'agenda du praticien).
S'il ne répond pas dans les 30 min → RDV maintenu par défaut.

---

##### Tables Supabase

| Table | Colonnes principales |
|---|---|
| `agenda_retards` | `id UUID`, `pro_id TEXT`, `date DATE`, `declared_at TIMESTAMPTZ`, `delai_min INT`, `message TEXT`, `statut TEXT` (actif/resolu), `updated_at TIMESTAMPTZ` |
| `agenda_retard_responses` | `id UUID`, `retard_id UUID`, `event_id UUID` (RDV concerné), `patient_id TEXT`, `response TEXT` (confirme/reporte/nc), `responded_at TIMESTAMPTZ` |

Colonne à ajouter sur `agenda_events` :
- `retard_id UUID` (lien vers le retard actif s'il y en a un)
- `retard_delai_min INT` (délai communiqué au patient)

---

##### Cloud Function `onRetardDeclared`

Déclenchée à chaque INSERT ou UPDATE sur `agenda_retards`
où `delai_min >= 30` :

1. Récupère tous les `agenda_events` du pro pour les 3 prochaines heures
   avec `statut = 'confirmé'`
2. Pour chaque patient concerné :
   - Envoie notification push FCM avec deeplink vers son RDV
   - Si `delai_min >= 60` → envoie SMS via Twilio (si `phone` renseigné)
3. Si `delai_min >= 60` → génère 3 créneaux alternatifs et les joint
   à la notification
4. Si `delai_min >= 90` → crée une alerte dans le dashboard admin
   PetsMatch (suivi qualité)
5. Logge chaque envoi dans `agenda_retard_responses`
   avec `response = 'nc'` (en attente de réponse)

---

##### Résolution du retard

Quand le professionnel marque le retard comme résolu
(`statut = 'resolu'`) :
- Notification push envoyée aux patients n'ayant pas encore répondu :
  "Le retard est résorbé — votre RDV est maintenu à l'heure prévue"
- Les patients ayant demandé un report conservent leur nouveau créneau

---

##### UI dashboard pro — vue agenda enrichie

- Badge orange "En retard — 45 min" visible sur le RDV en cours
- Bandeau en haut du dashboard si retard actif déclaré
- Compteur temps réel : nb patients notifiés / nb confirmés / nb reports
- Bouton "Mettre à jour le délai" et "Retard résorbé" toujours accessibles

---

#### Évolutions V3+

- Intégration agenda tournées maréchal (optimisation itinéraire multi-clients)
- Bilan ostéo/kiné avec schéma corporel annoté (zones travaillées)
- Partage compte-rendu ostéo avec le vétérinaire traitant (inter-pros)

---

### 5.16 Profils garde & mobilité — pet sitter et promeneur

> **Groupe B — Garde · Profils distincts · Partagent la base agenda + messagerie + zone intervention · Différenciés par leur logique métier**

Pet sitter et promeneur sont deux profils distincts dans l'app mais partagent la même architecture technique de base. Le pet sitter gère des séjours (entrée/sortie, hébergement), le promeneur gère des sorties ponctuelles (durée, groupe, notes). Tous deux peuvent cumuler les deux activités en activant les deux sous-profils depuis leurs paramètres.

---

#### Plans tarifaires

| Plan | Pet sitter | Promeneur |
|---|---|---|
| FREE | 0€ | 0€ |
| Essentiel | 12€/mois | 9€/mois |
| Pro | 19€/mois | 15€/mois |

Réduction annuelle : Pet sitter Essentiel 120€/an · Pro 190€/an — Promeneur Essentiel 90€/an · Pro 150€/an

---

#### Fonctionnalités pet sitter

| Fonctionnalité | FREE | Essentiel | Pro |
|---|---|---|---|
| Profil annuaire (carte, espèces acceptées, capacité max) | Basique | Complet + mis en avant | Complet + mis en avant |
| Badge vérifié + avis clients | ✅ | ✅ | ✅ |
| Zone d'intervention / rayon d'accueil | ✅ | ✅ | ✅ |
| Agenda réservations (vue calendrier) | ✅ | ✅ + créneaux avancés | ✅ + créneaux avancés |
| Messagerie clients | ✅ | ✅ | ✅ |
| Registre entrées/sorties animaux en pension | ❌ | ✅ | ✅ |
| Fiche animal en lecture seule pendant le séjour | ❌ | ✅ | ✅ |
| Accès carnet santé lecture (urgences vétérinaires) | ❌ | ✅ | ✅ |
| Journal de séjour (photos + notes quotidiennes envoyées au propriétaire) | ❌ | ✅ | ✅ |
| Contrats de garde PDF (modèle personnalisable) | ❌ | ✅ | ✅ |
| Facturation clients (module 5.11 adapté) | ❌ | ❌ | ✅ |
| Statistiques activité (taux remplissage, CA mensuel) | ❌ | ❌ | ✅ |

---

#### Fonctionnalités promeneur

| Fonctionnalité | FREE | Essentiel | Pro |
|---|---|---|---|
| Profil annuaire (carte, races acceptées, taille groupe max) | Basique | Complet + mis en avant | Complet + mis en avant |
| Badge vérifié + avis clients | ✅ | ✅ | ✅ |
| Zone de promenade (carte polygone) | ✅ | ✅ | ✅ |
| Agenda sorties (récurrentes + ponctuelles) | ✅ | ✅ + créneaux avancés | ✅ + créneaux avancés |
| Messagerie clients | ✅ | ✅ | ✅ |
| Fiche animal en lecture seule pendant la sortie | ❌ | ✅ | ✅ |
| Rapport de sortie (durée réelle, notes, photos) envoyé au propriétaire | ❌ | ✅ | ✅ |
| Gestion groupe (liste chiens, capacité max, liste d'attente) | ❌ | ✅ | ✅ |
| Contrats prestation PDF | ❌ | ✅ | ✅ |
| Facturation clients | ❌ | ❌ | ✅ |
| Abonnements clients (ex : 10 sorties/mois) | ❌ | ❌ | ✅ |

---

#### Tables Supabase à créer

| Table | Colonnes principales |
|---|---|
| `pension_sejours` | `id UUID`, `petsitter_id TEXT`, `animal_id TEXT`, `owner_id TEXT`, `date_entree TIMESTAMPTZ`, `date_sortie TIMESTAMPTZ`, `statut TEXT` (confirmé/en_cours/terminé), `notes TEXT`, `created_at TIMESTAMPTZ` |
| `pension_journal` | `id UUID`, `sejour_id UUID`, `date DATE`, `notes TEXT`, `photos TEXT[]`, `sent_to_owner BOOLEAN` |
| `promenade_sorties` | `id UUID`, `promeneur_id TEXT`, `date TIMESTAMPTZ`, `duree_min INT`, `animaux_ids TEXT[]`, `notes TEXT`, `photos TEXT[]`, `rapport_envoye BOOLEAN` |
| `promenade_groupes` | `id UUID`, `promeneur_id TEXT`, `nom TEXT`, `capacite_max INT`, `recurrence TEXT` (JSON), `animaux_inscrits TEXT[]` |

---

#### Liens avec propriétaires et éleveurs

- Le propriétaire reçoit une notification push à chaque rapport de sortie ou journal de séjour envoyé
- Le propriétaire peut donner accès lecture à la fiche animal + carnet santé pour la durée du séjour uniquement (accès révoqué automatiquement à `date_sortie` dans `pension_sejours`)
- L'éleveur peut référencer ses pet sitters/promeneurs habituels dans son profil élevage (recommandations)

---

#### Évolutions V3+

- Géolocalisation live pendant la promenade (opt-in propriétaire)
- Assurance responsabilité civile intégrée (partenariat assureur)
- Système d'avis vérifiés post-séjour

---

### 5.17 Profils éducation & comportement

> **Groupe C — Éducation · Profil unique avec deux sous-types · Spécificité : carnet comportemental distinct du carnet santé médical**

L'éducateur canin travaille sur l'obéissance et la socialisation. Le comportementaliste traite les troubles comportementaux (peurs, agressivité, TOC). Leurs outils sont similaires mais la profondeur du suivi diffère. Ils n'écrivent pas dans le carnet santé médical — ils ont leur propre "carnet comportemental" dans la fiche animal.

---

#### Sous-profils

| Sous-profil | Espèces principales | Validation |
|---|---|---|
| Éducateur canin | Chien | Attestation ACACED + certification éducation (upload) |
| Comportementaliste | Toutes espèces | Diplôme comportement animal (upload) |

---

#### Plans tarifaires

| Plan | Prix | Fonctionnalités clés |
|---|---|---|
| FREE | 0€ | Annuaire basique, messagerie |
| Essentiel | 19€/mois | Carnet comportemental, suivi séances, agenda avancé |
| Pro | 29€/mois | + Programmes personnalisés, facturation, contrats, rapports PDF |

---

#### Fonctionnalités

| Fonctionnalité | FREE | Essentiel | Pro |
|---|---|---|---|
| Profil annuaire (espèces, méthodes, zone) | Basique | Complet + mis en avant | Complet + mis en avant |
| Badge vérifié | ✅ | ✅ | ✅ |
| Agenda RDV + créneaux | ✅ | ✅ avancé | ✅ avancé |
| Messagerie clients | ✅ | ✅ | ✅ |
| Lecture carnet santé (contexte médical) | ❌ | ✅ lecture seule | ✅ lecture seule |
| Carnet comportemental — ajouter séance | ❌ | ✅ | ✅ |
| Carnet comportemental — évaluation initiale | ❌ | ✅ | ✅ |
| Programme d'entraînement personnalisé (étapes, objectifs) | ❌ | ❌ | ✅ |
| Suivi progression (scores par exercice, graphique) | ❌ | ❌ | ✅ |
| Rapport comportemental PDF (remis au propriétaire) | ❌ | ✅ basique | ✅ complet |
| Contrats de prestation PDF | ❌ | ✅ | ✅ |
| Facturation clients | ❌ | ❌ | ✅ |
| Partage rapport avec vétérinaire traitant | ❌ | ❌ | ✅ |

---

#### Carnet comportemental — structure

Onglet "Comportement" ajouté dans la fiche animal, visible par le propriétaire et les pros comportement ayant un accès accordé.

**Évaluation initiale :**
- Problèmes déclarés (multiselect : peurs / agressivité / destruction / fugue / aboiements / propreté / socialisation / autre)
- Contexte de vie (logement, temps seul, activité physique)
- Historique comportemental (texte libre)
- Score initial par axe (1-5) : sociabilité chiens / humains / calme / obéissance / gestion frustration

**Séance :**
- Date, durée, lieu (domicile / club / extérieur)
- Exercices travaillés (texte libre + tags)
- Observations du jour
- Score de progression par exercice (1-5)
- Devoirs pour le propriétaire

**Tables Supabase à créer :**

| Table | Colonnes principales |
|---|---|
| `comportement_evaluations` | `id UUID`, `animal_id TEXT`, `pro_id TEXT`, `date DATE`, `problemes TEXT[]`, `scores JSONB`, `contexte TEXT`, `historique TEXT`, `created_at TIMESTAMPTZ` |
| `comportement_seances` | `id UUID`, `animal_id TEXT`, `pro_id TEXT`, `date DATE`, `duree_min INT`, `lieu TEXT`, `exercices TEXT[]`, `observations TEXT`, `scores_progression JSONB`, `devoirs TEXT`, `created_at TIMESTAMPTZ` |
| `comportement_programmes` | `id UUID`, `animal_id TEXT`, `pro_id TEXT`, `titre TEXT`, `objectifs TEXT[]`, `etapes JSONB`, `statut TEXT` (actif/terminé), `created_at TIMESTAMPTZ` |

---

#### Liens avec propriétaires et éleveurs

- Le propriétaire reçoit les "devoirs" en notification push après chaque séance
- L'éleveur peut recommander un éducateur dans la fiche de son élevage (champ `educateur_recommande_id`)
- Le comportementaliste peut partager un rapport PDF directement au vétérinaire traitant si accès mutuellement accordé (inter-pros)
- À la vente d'un chiot, l'éleveur peut inclure un bon de réduction éducateur partenaire (futur : V3)

---

#### Évolutions V3+

- Vidéos courtes attachées aux séances (avant/après exercice)
- Programme d'entraînement partageable (éleveur → acheteur chiot)
- Mise en relation comportementaliste ↔ vétérinaire pour cas complexes

---

### 5.18 Profil photographe animalier

> **Groupe D — Créatif · Profil le plus simple · Valeur = visibilité et portfolio · Pas d'accès aux fiches animaux sauf partage volontaire**

Le photographe animalier n'intervient pas médicalement sur l'animal. Sa présence sur PetsMatch lui apporte une visibilité auprès d'une communauté de propriétaires et d'éleveurs (séances portées, séances famille, photos officielles pedigree). Il est accessible uniquement via l'annuaire.

---

#### Plans tarifaires

| Plan | Prix | Fonctionnalités clés |
|---|---|---|
| FREE | 0€ | Profil basique, 5 photos portfolio |
| Essentiel | 9€/mois | Portfolio complet, mis en avant, agenda |
| Pro | — | Non applicable |

Réduction annuelle : Essentiel 90€/an (1 mois offert)

---

#### Fonctionnalités

| Fonctionnalité | FREE | Essentiel |
|---|---|---|
| Profil annuaire (zone, espèces, style photographique) | Basique | Complet + mis en avant |
| Portfolio photos (galerie) | 5 photos max | Illimité |
| Badge vérifié (SIRET ou auto-entrepreneur) | ✅ | ✅ |
| Zone d'intervention carte | ✅ | ✅ |
| Agenda RDV (réception demandes de séance) | ✅ | ✅ + créneaux avancés |
| Messagerie clients | ✅ | ✅ |
| Accès fiche animal (si propriétaire partage) | Lecture seule race/couleur/nom | Lecture seule race/couleur/nom |
| Mise en avant dans les résultats de recherche | ❌ | ✅ |
| Statistiques profil (vues, demandes RDV) | ❌ | ✅ |

Note : le photographe ne peut jamais écrire dans le carnet santé ni accéder aux données médicales, même si le propriétaire lui accorde un accès.

---

#### Spécificité éleveurs

Les éleveurs peuvent référencer un photographe partenaire dans leur profil élevage pour les séances de portées. La photo principale d'une annonce peut être taguée "Photo professionnelle" si prise par un photographe PetsMatch vérifié, ce qui améliore la crédibilité de l'annonce.

---

#### Tables Supabase

Pas de nouvelles tables nécessaires. Utilise les tables existantes :
- `users` : `cat_pro = 'photographe'`, `portfolio_urls TEXT[]` (nouveau champ)
- `agenda_events` : séances photo comme tout autre RDV
- `creneaux_pro` : disponibilités AG08

Colonnes à ajouter sur `annonces` :
- `photo_pro_id TEXT` (uid du photographe si photo professionnelle)
- `photo_pro_verified BOOLEAN DEFAULT false`

---

#### PSN08 — Envoi facture au propriétaire + signature contrat

**Envoi facture (implémenté v2) :**
- Génération PDF en mémoire (bytes)
- Upload Firebase Storage : `factures/{pensionUid}/{invoiceNum}.pdf`
- Lookup propriétaire par email → Supabase `users.uid` + `fcm_token`
- Insertion `notifications` : `type = 'facture_pension'`, `data.url` = URL de téléchargement
- Push FCM : "Votre facture de séjour est disponible"

**Signature contrat — YouSign (V3+) :**
- Intégration API YouSign pour signature électronique du contrat de pension
- Flux : pension crée le contrat PDF → envoie lien YouSign au propriétaire → signature → PDF signé stocké dans Firebase Storage
- Statut de signature visible dans l'onglet Documents du profil pension
- Conforme RGPD + valeur juridique (eIDAS niveau simple)

---

### 5.19 Marketplace & partenaires — régie publicitaire ciblée

> **Modèle régie pub, pas transactionnel · Pas de panier ni de paiement in-app · Le partenaire paie pour être visible auprès d'une audience qualifiée · Le clic redirige vers son site externe**

PetsMatch monétise son audience (éleveurs, propriétaires, pros) via des formats publicitaires ciblés par espèce, race, région et profil. Aucune infrastructure e-commerce requise en V1.

---

#### Segments partenaires

| Segment | Exemples | Ciblage principal |
|---|---|---|
| Créateurs artisanaux | Colliers sur mesure, jouets, vêtements, accessoires | Espèce, race, région |
| Alimentation & friandises | Marques premium, cru, compléments alimentaires | Espèce, race, âge animal |
| Boutiques généralistes | Animaleries en ligne, distributeurs | Espèce, région |
| Assurances animaux | Santevet, Dalma, Lovys, April | Espèce, âge, statut chiot/adulte |

Les assurances sont le segment à CPL le plus élevé du marché animalier français (15–40€ par lead qualifié). Priorité commerciale en V2.

---

#### Formats & tarification

**Format 1 — Listing annuaire partenaire** (abonnement mensuel)

Le partenaire apparaît dans la vue Marketplace, filtrable par catégorie et espèce. Pas de ciblage comportemental, visibilité passive.

| Plan | Prix | Visibilité |
|---|---|---|
| Starter | 29€/mois | Logo + nom + lien site, listing basique |
| Visible | 59€/mois | Mise en avant catégorie + badge "Partenaire vérifié" + description |
| Premium | 99€/mois | Top catégorie + bannière profil + filtres race/espèce avancés |

Réduction annuelle : Starter 290€/an · Visible 590€/an · Premium 990€/an

**Format 2 — Bannières contextuelles in-app** (CPM)

Bannières natives affichées dans des écrans spécifiques selon le contexte de navigation. Facturées au CPM (coût pour mille affichages).

| Placement | CPM | Contexte & pertinence |
|---|---|---|
| Fiche animal (bas de page) | 8–12€/1000 | Ultra-ciblé espèce/race — idéal accessoires |
| Feed annonces (native card) | 6–10€/1000 | Ciblé espèce — alimentation, jouets |
| Carnet santé (post-visite vét) | 15–25€/1000 | Moment fort — idéal assurances |
| Dashboard éleveur | 10–15€/1000 | Audience pro, forte intention d'achat |
| Onboarding (ajout d'un animal) | 12–18€/1000 | Nouveau propriétaire — assurance, accessoires |

Minimum de facturation : 500€/mois par partenaire bannière.
Ciblage disponible : espèce, race, région, type de profil (éleveur/particulier/pro).

**Format 3 — Lead generation assurances** (CPL)

Uniquement pour les partenaires assureurs. Un CTA "Obtenir un devis" apparaît dans des moments clés du parcours utilisateur.

| Modèle | Prix | Déclencheur |
|---|---|---|
| CPC (coût par clic) | 0,80–1,50€ | Clic bannière assurance |
| CPL (coût par lead) | 12–20€ | Clic "Obtenir un devis" → redirection formulaire assureur |

Moments déclencheurs CPL :
- Ajout d'un nouvel animal dans l'app
- Enregistrement d'un chiot/chaton (date naissance < 4 mois)
- Première visite vétérinaire enregistrée dans le carnet santé
- Achat d'une annonce éleveur (nouveau propriétaire potentiel)

---

#### Tables Supabase à créer

| Table | Colonnes principales |
|---|---|
| `marketplace_partners` | `id UUID`, `user_id TEXT`, `nom TEXT`, `logo_url TEXT`, `site_url TEXT`, `description TEXT`, `categorie TEXT` (artisan/alimentation/boutique/assurance), `especes_cibles TEXT[]`, `regions TEXT[]`, `plan TEXT` (starter/visible/premium), `statut TEXT` (actif/suspendu/en_attente), `created_at TIMESTAMPTZ` |
| `marketplace_ads` | `id UUID`, `partner_id UUID`, `type TEXT` (listing/banniere/cpl), `placement TEXT`, `budget_mensuel NUMERIC`, `cpm NUMERIC`, `cpl NUMERIC`, `especes_cibles TEXT[]`, `regions TEXT[]`, `date_debut DATE`, `date_fin DATE`, `statut TEXT` (actif/pause/termine), `created_at TIMESTAMPTZ` |
| `marketplace_events` | `id UUID`, `ad_id UUID`, `partner_id UUID`, `user_id TEXT`, `event_type TEXT` (impression/clic/lead), `espece TEXT`, `race TEXT`, `region TEXT`, `created_at TIMESTAMPTZ` |

RLS : `marketplace_partners` et `marketplace_ads` accessibles uniquement par le partenaire propriétaire (`user_id = auth.uid()`) et les admins. `marketplace_events` : insertion côté client, lecture réservée admin + partenaire.

---

#### UI partenaire — dashboard statistiques

**Vue "Ma campagne"** (app + web, réservée partenaires connectés)
- Métriques temps réel : impressions, clics, leads du mois en cours
- CTR moyen, CPL effectif, coût total engagé
- Répartition par espèce, race, région (graphiques barres/camembert)
- Évolution temporelle (courbe 30 jours glissants)
- Facture mensuelle téléchargeable (PDF auto-généré)
- Modifier ciblage, budget et créatifs

**Dashboard admin PetsMatch**
- Vue globale toutes campagnes : revenus, impressions, clics, leads par partenaire
- Alertes : partenaire proche du plafond mensuel, taux de fraude (IP multiples), CTR anormal
- Export CSV mensuel complet
- Graphiques de performance par segment (assurances vs alimentation vs accessoires)

---

#### Vue Marketplace utilisateur (app + web)

Section dédiée accessible depuis le menu principal.

**Architecture de la vue :**
- Header : "Nos partenaires sélectionnés" + filtre espèce (chien/chat/équidé/autre)
- Grille partenaires : carte logo + nom + catégorie + lien externe
- Section "Assurances" : cards dédiées avec CTA "Obtenir un devis"
- Badge "Partenaire vérifié PetsMatch" sur tous les listings
- Pas de publicité intrusive dans les écrans métier (carnet santé, registre) sauf bannière discrète bas de page

Règle éditoriale : tous les partenaires sont vérifiés manuellement avant activation (SIRET valide, site légitime, produits conformes réglementation animaux).

---

#### Tracking & facturation automatique

- Impressions comptées côté serveur (Cloud Function), pas côté client (anti-fraude, ad-blockers non impactants sur le CPM)
- Facture Stripe générée automatiquement en fin de mois selon les events réels (`marketplace_events`)
- Plafond de dépenses mensuel configurable par partenaire
- Rapport PDF mensuel envoyé automatiquement au partenaire

---

#### Conformité RGPD

- Aucune donnée personnelle utilisateur transmise aux partenaires
- Le ciblage est contextuel (espèce, région) et non nominatif
- Mentions légales "Publicité" affichées sur tous les formats bannière
- Opt-out publicité disponible dans les paramètres utilisateur (impact : bannières désactivées, listing annuaire toujours visible)

---

#### Évolutions V2+

- Ciblage comportemental avancé (historique carnet santé, races possédées)
- Self-service : onboarding partenaire autonome sans validation manuelle
- Intégration Google Ad Manager pour partenaires >2 000€/mois de budget
- Affiliation créateurs artisanaux (commission sur ventes trackées par UTM)
- Programme "Partenaire éleveur" : éleveur recommande une marque → reçoit des boosts en échange (cross-fonctionnalité 5.13)

---

## 5.20 Signalement membres

> **Modération communautaire · Protège la plateforme contre les faux profils, arnaques et contenus inappropriés**

### Spec IDs : SIG01–SIG04

| ID | Fonctionnalité | Priorité | Support | Statut |
|---|---|---|---|---|
| SIG01 | Bouton "Signaler" sur profil utilisateur, annonce, profil pro | Haute | App + Web | ❌ |
| SIG02 | Formulaire de signalement : type (contenu_inapproprie / spam / faux_profil / maltraitance / autre) + description libre | Haute | App + Web | ❌ |
| SIG03 | Queue admin — liste des signalements avec statut (en_attente / traité / rejeté) + lien vers la ressource signalée | Haute | App + Web | ❌ |
| SIG04 | Actions admin : envoyer avertissement / suspendre compte / bannir + log dans `audit_logs` | Haute | App + Web | ❌ |

### Table Supabase

```sql
CREATE TABLE signalements (
  id            TEXT PRIMARY KEY,
  reporter_uid  TEXT NOT NULL,          -- qui signale
  target_type   TEXT NOT NULL,          -- 'user' | 'annonce' | 'profil_pro'
  target_id     TEXT NOT NULL,          -- uid ou id de la ressource
  raison        TEXT NOT NULL,          -- 'contenu_inapproprie' | 'spam' | 'faux_profil' | 'maltraitance' | 'autre'
  description   TEXT,
  statut        TEXT DEFAULT 'en_attente', -- 'en_attente' | 'traite' | 'rejete'
  admin_note    TEXT,
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  handled_at    TIMESTAMPTZ,
  handled_by    TEXT                    -- uid admin
);
```

### Règles
- Un utilisateur ne peut pas signaler deux fois la même ressource (UNIQUE sur `reporter_uid + target_type + target_id`)
- Le signalement est anonyme pour la cible (le signalé ne sait pas qui l'a signalé)
- L'admin voit tous les signalements avec filtre par statut / type
- Seuil d'alerte automatique : ≥ 3 signalements non traités sur une même ressource → badge rouge dans le panel admin

---

## 6. Sécurité / Conformité RGPD

### V1 — Obligatoire avant lancement public

| # | Fonctionnalité | Priorité |
|---|---|---|
| RGPD01 | CGU + Politique de confidentialité — pages statiques web + lien depuis app | Haute | ✅ Implémenté 2026-06-09 |
| RGPD02 | Bannière cookies web — opt-in/opt-out RGPD (Google Analytics, Firebase), consentement localStorage | Haute | ✅ Implémenté 2026-06-09 |
| RGPD03 | Mentions légales — éditeur, hébergeur, responsable de traitement | Haute | ✅ Implémenté 2026-06-09 |
| RGPD04 | Registre des traitements RGPD — document interne (données collectées, base légale, durée, sous-traitants) | Haute | ⏳ Document interne à rédiger |
| RGPD05 | Consentement explicite à l'inscription — case à cocher CGU (non pré-cochée), `cgu_accepted_at` Supabase | Haute | ✅ Implémenté 2026-06-09 |
| RGPD06 | Export données utilisateur (RGPD art. 20) — bouton "Télécharger mes données" → JSON complet | Haute | ❌ |
| RGPD07 | Suppression compte + données (RGPD art. 17) — cascade Firebase Auth + Supabase + Storage | Haute | ❌ |

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
3. ~~Durée de vie annonces (A30)~~ ✅ Terminé 2026-06-02
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

---

## 12. Architecture multi-profils (v2, 2026-06)

### Principe fondamental
- **1 `uid` Firebase** = 1 compte utilisateur (identifié par email). C'est le "parent ID".
- **Chaque profil** (principal ou secondaire) a son propre UUID unique :
  - Profil principal : `users.profile_id` (UUID ajouté via migration)
  - Profils secondaires : `user_profiles.id` (UUID, clé primaire existante)
- **`User_Info.activeProfileId`** = UUID du profil actif. Vide = profil principal.

### Règle : animaux & appartenance
Les **animaux** (`animaux.uid_eleveur`) restent liés au `uid` Firebase (compte parent).
Un animal appartient à un **utilisateur**, pas à un profil spécifique. Tous les profils du même compte voient les mêmes animaux.

### Règle : services, RDV, fiches
Les RDV, services et fiches pro sont liés au `uid` Firebase (`uid_pro`).
La colonne `pro_profile_id TEXT DEFAULT ''` est ajoutée aux tables `rdv`, `creneaux_pro`, `agenda_events`, `vet_access_grants`, `pension_acces`, `pension_entrees` pour distinguer quel profil gère chaque relation.

### Convention `pro_profile_id`
- **Profil principal** → `pro_profile_id = ''` (chaîne vide, jamais NULL)
- **Profil secondaire** → `pro_profile_id = user_profiles.id` (UUID)
- Les NULL existants sont migrés vers `''` via `supabase/migration_empty_string_profile.sql`
- Cette convention évite les collisions sur les contraintes UNIQUE PostgreSQL (NULL ≠ NULL)

### Validation profils secondaires
- Table `user_profiles` : colonne `statut_pro TEXT DEFAULT 'en_attente'`
- Valeurs : `'en_attente'` | `'actif'` | `'refuse'` | `'suspendu'`
- L'admin valide depuis le panel pro (badge violet "Secondaire")
- Un profil secondaire n'apparaît dans l'annuaire services qu'une fois `statut_pro = 'actif'`

### Rechargement automatique sur changement de profil
- `User_Info.profileNotifier` (`ValueNotifier<String>`) est notifié dans `applyProfile()` et `updateUserInfo()`
- `ProAgendaPage` écoute ce notifier → recharge RDVs + créneaux au changement de profil
- `AgendaPage` filtre les `agenda_events` par `pro_profile_id` (avec fallback si colonne absente)

### Table `user_profiles` — colonnes complètes
Chaque profil secondaire a les mêmes données qu'un profil principal :
`horaires`, `accept_new_clients`, `banner_url`, `tarifs`, `instagram`, `facebook`,
`certifications`, `durees_motifs`, `lat`, `lng`, `is_pro`, `desc_entreprise`,
`departement`, `region`, `ville_elevage`, `code_postal_elevage`, `rue_elevage`.
Migration : `supabase/migration_secondary_profile_complete.sql`.

### Table `users` — ajout `profile_id`
`ALTER TABLE users ADD COLUMN profile_id UUID DEFAULT gen_random_uuid();`
Permet d'identifier le profil principal par un UUID (comme les profils secondaires).

### Routing dans l'app
- `ServiceDetailPage(proUid, profileTableId?)` : charge depuis `user_profiles` si `profileTableId` est fourni, sinon depuis `users`.
- `ProProfileEditPage(secondaryProfileId?)` : charge/sauvegarde depuis `user_profiles` si fourni, sinon depuis `users`.
- Toutes les navigations vers `ProProfileEditPage` passent `User_Info.activeProfileId` (vide = édition profil principal).

### Types de profils
`particulier`, `eleveur`, `veterinaire`, `sante`, `education`, `garde`, `pension`, `toilettage`, `photographe`, `marechal_ferrant`

### Notifications
Les notifications sont partagées entre tous les profils d'un même compte.
Chaque notification porte un `profile_type` et `profile_id` pour indiquer à quel profil elle est destinée.
La cloche s'allume sur tous les profils. En cliquant sur une notif d'un autre profil, l'app propose de basculer.
