# PetsMatch — Cahier des charges fonctionnel

> **Comment lire ce fichier :**
> - ✅ = Implémenté (app + web sauf mention contraire)
> - 🔶 = Partiellement fait
> - ⬜ = À faire
> - `[App]` / `[Web]` = concerne un seul repo
> - Cases à cocher `- [ ]` = à compléter par l'équipe

---

## 0. Infrastructure & architecture

| Statut | Fonctionnalité |
|---|---|
| ✅ | Authentification Firebase Auth (email/password + Apple Sign In) |
| ✅ | Base de données Supabase PostgreSQL — toutes les données métier |
| ✅ | Firebase Storage pour photos et documents |
| ✅ | Supabase Edge Function `delete-user` (suppression compte complète, JWT verification désactivée) |
| ✅ | Schéma SQL avec CASCADE DELETE sur toutes les tables liées à `users` |
| ✅ | Tables Supabase : users, animaux, annonces, likes, favoris, notifications, registres, contrats, factures |
| 🔶 | Migration Firestore → Supabase : feed social (`post`), utilisateurs bloqués (`bloquer`) |
| 🔶 | Messagerie : conversations Firestore — à migrer ou adapter (temps réel) |
| ⬜ | - [ ] |

---

## 1. Inscription / Connexion

| Statut | Fonctionnalité |
|---|---|
| ✅ | Inscription email + mot de passe |
| ✅ | Connexion email + mot de passe |
| ✅ | Mot de passe oublié |
| ✅ | Vérification email |
| ✅ | Apple Sign In `[App]` |
| ✅ | Choix du type de profil (Particulier / Éleveur / Pro) |
| ✅ | Formulaire inscription multi-étapes (nom, adresse, téléphone, date naissance) |
| ✅ | Géolocalisation adresse → lat/lng sauvegardés |
| ⬜ | - [ ] |

---

## 2. Profil utilisateur

| Statut | Fonctionnalité |
|---|---|
| ✅ | Profil particulier (nom, prénom, adresse, téléphone, photo) |
| ✅ | Profil éleveur (nom élevage, SIRET, ACACED, adresse élevage, description, photo) |
| ✅ | Profil pro (profession, SIRET, TVA) |
| ✅ | Mise à jour lat/lng sur changement d'adresse (Firestore + Supabase) |
| ✅ | Fix ville = département corrigé (locality prioritaire) |
| ✅ | Upload photo de profil avec crop carré |
| ⬜ | - [ ] |

---

## 3. Panel admin

| Statut | Fonctionnalité |
|---|---|
| ✅ | Accès admin protégé (`isAdmin = true`) |
| ✅ | Liste utilisateurs avec filtres (Tous / Particulier / Éleveur / Pro / Admin) |
| ✅ | Recherche par nom ou email |
| ✅ | Fiche détail utilisateur (voir + modifier tous les champs) |
| ✅ | Activer/désactiver rôles (Admin, Éleveur, Pro, Validé) |
| ✅ | Suppression compte complète (Firebase Auth + Supabase cascade + Firestore) |
| ✅ | Double confirmation avant suppression (dialog + saisir "SUPPRIMER") |
| ✅ | Liste demandes de vérification éleveurs |
| ✅ | Valider / Rejeter une demande de vérification éleveur |
| ⬜ | - [ ] |

---

## 4. Mes animaux — Éleveur

### 4.1 Liste des animaux

| Statut | Fonctionnalité |
|---|---|
| ✅ | Liste animaux avec photo, nom, espèce, race, statut |
| ✅ | Filtres par espèce |
| ✅ | Sélection race depuis fichiers breeds JSON |
| ⬜ | - [ ] |

### 4.2 Fiche animal

| Statut | Fonctionnalité |
|---|---|
| ✅ | Informations de base (nom, espèce, race, sexe, couleur, identification) |
| ✅ | Photo avec crop carré |
| ✅ | Données physiques (taille, poids, type de poil, stérilisé) |
| ✅ | Passeport européen |
| ✅ | Section pedigree (type adapté par espèce : LOF/LOOF/Stud-book...) |
| ✅ | Upload document pedigree |
| ✅ | Champ importation_ref (visible si provenance = importation) |
| ✅ | Généalogie (nom/puce père et mère, date naissance mère) |
| ✅ | Registre entrée/sortie sur la fiche |
| ✅ | Carnet de santé (vaccins, antiparasitaires, vermifuges, actes vétérinaires) |
| ✅ | Upload documents (ADN, santé repro, filiation, hanches, autre) |
| ✅ | Catégories documents avec icônes |
| ⬜ | Onglet suivi repro (chaleurs, saillie, gestation) |
| ⬜ | Courbe de poids (croissance + adulte) |
| ⬜ | Transfert de propriété (vente → email acheteur) |
| ⬜ | - [ ] |

### 4.2b Fiche animal — améliorations UX `[App]`

| Statut | Fonctionnalité |
|---|---|
| ✅ | Prise de photo directe depuis la caméra (en plus de la galerie) pour les photos animal ET les documents |
| ✅ | Recherche dans la liste animaux par nom ou numéro de puce (barre de recherche avec loupe) |

### 4.3 Formulaire portée

| Statut | Fonctionnalité |
|---|---|
| ✅ | Création portée depuis fiche mère |
| ✅ | Sélection de la mère parmi les animaux de l'élevage |
| ✅ | Champs communs (date naissance, description) |
| ✅ | Par animal : nom, identification, sexe, couleur |
| ✅ | Par animal : type de poil (chien/chat), taille, poids |
| ✅ | Par animal : stérilisé, passeport européen, notes |
| ✅ | Par animal : photo avec crop carré |
| ✅ | Auto-fill registre entrée (provenance = élevage, nom + adresse éleveur) |
| ✅ | Pluriel "animaux" correct |
| ⬜ | - [ ] |

---

### 4.4 Suivi reproduction (éleveur)

| Statut | Fonctionnalité |
|---|---|
| ⬜ | Saisie chaleurs (date début, date fin) sur fiche femelle |
| ⬜ | Saisie saillie (sélection mâle de l'élevage ou saillie extérieure) |
| ⬜ | Saillie → gestation débutée automatique avec date de mise bas prévue calculée |
| ⬜ | Champ "Gestation confirmée" (oui/non/en attente) |
| ⬜ | Alerte push rappel de confirmation de gestation (délai selon espèce) |
| ⬜ | Saillie extérieure : l'éleveur du mâle peut partager accès aux infos (photo, nom, puce, race) |
| ⬜ | Gestation → visible et modifiable sur la fiche femelle |

---

## 5. Registre sanitaire

| Statut | Fonctionnalité |
|---|---|
| ✅ | Saisie actes sanitaires (date, type, animal, commentaire) |
| ✅ | Liste chronologique |
| ⬜ | Import Excel `[Web]` |
| ⬜ | - [ ] |

---

## 6. Registre entrée / sortie

> Note : auto-fill depuis portée déjà implémenté ✅

| Statut | Fonctionnalité |
|---|---|
| ✅ | Saisie entrée/sortie (date, motif, provenance/destination) |
| ✅ | Auto-fill depuis portée (provenance nom + adresse élevage) |
| ✅ | Auto-fill infos éleveur pour toute nouvelle entrée (provenance = élevage par défaut) |
| ✅ | Auto-fill infos mère depuis fiche animal si mère = animal de l'élevage |
| ⬜ | Import Excel `[Web]` |
| ⬜ | - [ ] |

---

## 6b. Mes animaux — recherche

| Statut | Fonctionnalité |
|---|---|
| ⬜ | Barre de recherche (loupe) dans la liste animaux éleveur — filtrer par nom ou numéro de puce |

---

## 7. Annonces

| Statut | Fonctionnalité |
|---|---|
| ✅ | Création annonce (éleveur) |
| ✅ | Feed annonces avec filtres |
| ✅ | Vue carte annonces |
| ✅ | Détail annonce |
| ✅ | Modification annonce |
| ✅ | Mes annonces |
| 🔶 | Fix onglet annonces profil éleveur (mauvaises annonces affichées) |
| ⬜ | Photo annonce : carrée à la création ✅ — format rectangle adapté + zoom centré sur l'animal dans le feed (sans rogner) |
| ✅ | Clic long sur annonce dans "mes dernières annonces" (accueil éleveur) → menu Supprimer avec confirmation |
| ⬜ | Likes sur annonce / sur bébé de portée |
| ⬜ | Notification éleveur lors d'un like |
| ⬜ | Favoris : voir les annonces likées |
| ⬜ | Visuel liste style "match" (photo bébé premier plan) `[Web]` |
| ⬜ | Champ description père/mère visible (particulier) |
| ⬜ | Identification mère obligatoire selon espèce |
| ⬜ | - [ ] |

---

## 7b. Admin — Validation & Modération

| Statut | Fonctionnalité |
|---|---|
| ✅ | Validation manuelle profil éleveur par admin |
| ⬜ | Algorithme pré-validation profil éleveur (SIRET valide, cohérence infos, détection doublons) |
| ⬜ | Algorithme modération annonces (cohérence espèce/race, prix anormal, contenu signalé) |
| ⬜ | Score de confiance affiché sur la fiche pro (basé sur complétude du profil + vérification) |
| ⬜ | Système de signalement annonce / profil par les utilisateurs |
| ⬜ | File de modération admin pour les signalements |

---

## 8. Animaux perdus

| Statut | Fonctionnalité |
|---|---|
| ⬜ | Page d'accueil : clic sur alerte animal perdu → ouvrir directement la gestion de l'alerte |
| ⬜ | Page d'accueil : clic long sur alerte → menu "Supprimer l'alerte" / "Animal retrouvé" (avec confirmation) |
| 🔶 | Formulaire déclarer animal perdu (champs de base) |
| ⬜ | Champ Nom : chercher dans mes animaux OU saisie manuelle |
| ⬜ | Race depuis fichiers breeds JSON |
| ⬜ | Date dernière localisation (≠ date disparition) |
| ⬜ | Contact : email ou téléphone |
| ⬜ | Champs obligatoires validés (nom, espèce, race, sexe, date, localisation, contact) |
| ⬜ | Depuis fiche animal → contact urgence pré-rempli |
| 🔶 | Liste animaux perdus |
| ⬜ | Filtres liste (espèce, race, pays, ville, région) |
| ⬜ | Affichage par défaut = région de l'utilisateur |
| ⬜ | Vue détail lisible |
| ⬜ | Contact via messagerie (objet auto = nom, espèce, race, sexe, réf) |
| 🔶 | Vue carte |
| ⬜ | Carte synchronisée avec filtres liste |
| ⬜ | Code couleur par espèce sur la carte |
| ⬜ | Notifications alertes (icône cloche, badge rouge) |
| ⬜ | Fix notifications iOS (alertes non reçues) `[App]` |
| ⬜ | - [ ] |

---

## 9. Messagerie

| Statut | Fonctionnalité |
|---|---|
| 🔶 | Messagerie temps réel (base Firestore) |
| ⬜ | Onglet "Messages" dans le menu principal (app + web) |
| ⬜ | Redesign liste conversations (cohérence web/app) |
| ⬜ | Types de conversations : Annonce / Animal perdu / Contact élevage / Discussion libre / Service pro |
| ⬜ | Appui long : Épingler / Archiver / Sourdine / Bloquer / Supprimer |
| ⬜ | - [ ] |

---

## 10. Facturation (éleveur)

| Statut | Fonctionnalité |
|---|---|
| ✅ | Génération factures PDF |
| ✅ | Liste factures |
| ⬜ | - [ ] |

---

## 11. Contrats (éleveur)

| Statut | Fonctionnalité |
|---|---|
| 🔶 | Contrat de base |
| ⬜ | Modèle de contrat modifiable |
| ⬜ | Contrat payant (offre future) |
| ⬜ | - [ ] |

---

## 12. Notifications

| Statut | Fonctionnalité |
|---|---|
| ✅ | Notifications push Firebase Messaging |
| ✅ | Notifications locales |
| ⬜ | Rappels vaccins / antiparasitaires (J-7, J-1, J) |
| ⬜ | Notification like sur annonce |
| ⬜ | Fix notifications iOS animaux perdus |
| ⬜ | - [ ] |

---

## 13. Élevages (annuaire public)

| Statut | Fonctionnalité |
|---|---|
| ✅ | Liste élevages |
| ✅ | Vue carte élevages |
| ✅ | Fiche publique élevage |
| ⬜ | - [ ] |

---

## 14. Services pro / Vétérinaires

| Statut | Fonctionnalité |
|---|---|
| ✅ | Page services |
| ✅ | Annuaire vétérinaires |
| ⬜ | - [ ] |

---

## 15. Abonnements / Paiement

| Statut | Fonctionnalité |
|---|---|
| ✅ | Intégration Stripe `[App]` |
| ✅ | Gestion `valid_until` |
| ✅ | Rappels J-15 et J-21 avant expiration |
| ⬜ | - [ ] |

---

## À compléter par l'équipe

> Ajouter ici les fonctionnalités non listées, les contraintes techniques, les spécificités métier.

### Fonctionnalités manquantes identifiées

- [ ] 
- [ ] 
- [ ] 

### Contraintes techniques à documenter

- [ ] 
- [ ] 

### Questions ouvertes

- [ ] 
- [ ] 
