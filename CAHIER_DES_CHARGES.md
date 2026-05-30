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
| ⬜ | CAPTCHA anti-robot sur les formulaires de connexion et d'inscription |
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
| ⬜ | Connexion avec Google (OAuth) |
| ✅ | Choix du type de profil (Particulier / Éleveur / Pro) |
| ✅ | Formulaire inscription multi-étapes (nom, adresse, téléphone, date naissance) |
| ✅ | Géolocalisation adresse → lat/lng sauvegardés |
| ⬜ | - [ ] |

---

## 2. Profil utilisateur

| Statut | Fonctionnalité |
|---|---|
| ✅ | Profil particulier (nom, prénom, adresse, téléphone, photo) — pas de validation manuelle requise |
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
| ⬜ | Tableau de bord admin — statistiques : nombre d'annonces en ligne, nombre d'animaux par espèce |
| ⬜ | Validation automatique profils éleveur/pro (algorithme) — si suspect, soumis à révision admin |
| ⬜ | Validation automatique annonces éleveur (algorithme) — si suspect, soumis à révision admin |
| ⬜ | - [ ] |

---

## 4. Mes animaux — Éleveur

### 4.1 Liste des animaux

| Statut | Fonctionnalité |
|---|---|
| ✅ | Liste animaux avec photo, nom, espèce, race, statut |
| ✅ | Filtres par espèce |
| ✅ | Sélection race depuis fichiers breeds JSON |
| ✅ | Barre de recherche par nom ou numéro de puce |
| ⬜ | Vue "Reproducteurs" — filtrer uniquement les animaux reproducteurs |
| ⬜ | Vue "Bébés" — regroupement par portée ou par mois/année de naissance |
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
| ✅ | Onglet suivi repro (chaleurs, saillie, gestation, gestation confirmée) |
| ✅ | Onglet alimentation — calcul ration journalière selon poids/objectif (croquettes marque/produit, BARF, ration ménagère) `[V1]` |
| ⬜ | Courbe de poids adulte |
| ⬜ | Courbe de poids chiot / juvénile (croissance) |
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
| ✅ | Saisie chaleurs (date début, date fin) sur fiche femelle |
| ✅ | Saisie saillie (sélection mâle de l'élevage ou saillie extérieure) |
| ✅ | Saillie → gestation débutée automatique avec date de mise bas prévue calculée |
| ✅ | Champ "Gestation confirmée" (oui/non/en attente) |
| ✅ | Gestation → visible et modifiable sur la fiche femelle |
| ⬜ | Alerte push rappel de confirmation de gestation (délai selon espèce) |
| ⬜ | Saillie extérieure : l'éleveur du mâle peut partager accès aux infos (photo, nom, puce, race) |

---

## 5. Registre sanitaire

| Statut | Fonctionnalité |
|---|---|
| ✅ | Saisie actes sanitaires (date, type, animal, commentaire) |
| ✅ | Liste chronologique |
| ✅ | Import Excel `[Web]` |
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
| ✅ | Import Excel `[Web]` |
| ⬜ | - [ ] |

---

## 6b. Mes animaux — recherche

| Statut | Fonctionnalité |
|---|---|
| ✅ | Barre de recherche (loupe) dans la liste animaux éleveur — filtrer par nom ou numéro de puce |

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
| ✅ | Fix onglet annonces profil éleveur |
| ✅ | Photos annonces au format carré — format conservé |
| ✅ | Clic long sur annonce dans "mes dernières annonces" (accueil éleveur) → menu Supprimer avec confirmation |
| ⬜ | Likes sur annonce / sur bébé de portée |
| ⬜ | Notification éleveur lors d'un like |
| ⬜ | Favoris : voir les annonces likées |
| ✅ | Visuel liste style "match" (photo bébé premier plan) |
| ⬜ | Carte annonces compagnons — filtres espèce, race, région, ville, pays, département |
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
| ✅ | Page d'accueil : clic sur alerte animal perdu → ouvrir directement la gestion de l'alerte |
| ✅ | Page d'accueil : clic long sur alerte → menu "Animal retrouvé" / "Supprimer" (avec confirmation) |
| ✅ | Formulaire déclarer animal perdu complet (nom depuis mes animaux, race JSON, localisation, pays/région, récompense, contact) |
| ✅ | Formulaire "Déclarer un animal trouvé" complet (espèce/race, état de santé, comportement, multi-photos, contacts) |
| ✅ | Liste animaux perdus + filtres (espèce, race, ville) |
| ✅ | Vue détail alerte |
| ✅ | Carte animaux perdus/trouvés — onglet Perdu/Trouvé + code couleur + filtres synchronisés |
| ✅ | Bouton "J'ai trouvé un animal" dans le menu principal (app + web) |
| ⬜ | Suggestion "Alerte animale" lors de doublon déclaration perdu/trouvé — affichage tableau de bord |
| ⬜ | Affichage par défaut = région de l'utilisateur |
| ⬜ | Contact via messagerie (objet auto = nom, espèce, race, sexe, réf) |
| ⬜ | Saisie manuelle numéro de puce → recherche alertes perdus + animaux trouvés |
| ⬜ | Notifications de proximité (< 10 km d'une alerte active) |
| ⬜ | Matching automatique perdu ↔ trouvé (score pondéré ≥ 90% → notification) |
| ⬜ | Lecteur puce Bluetooth |
| ⬜ | Workflow statuts animaux trouvés (Trouvé → Pris en charge → Restitué → Clôturé) |
| 🔶 | Notifications alertes (icône cloche, badge) — fix iOS en cours |
| ⬜ | - [ ] |

---

## 9. Messagerie

| Statut | Fonctionnalité |
|---|---|
| ✅ | Messagerie temps réel (base Firestore) |
| ✅ | Onglet "Messages" dans le menu principal (app + web) |
| ✅ | Redesign liste conversations (cohérence web/app) |
| ✅ | Types de conversations : Annonce / Animal perdu / Contact élevage / Discussion libre / Service pro |
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
| ✅ | Notification like sur annonce |
| ⬜ | Rappels vaccins / antiparasitaires (J-7, J-1, J) |
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

## 14. Pôle Santé

> Vétérinaires et professionnels de santé animale regroupés dans un pôle dédié.

| Statut | Fonctionnalité |
|---|---|
| ✅ | Page Pôle Santé (accès depuis Services) |
| ✅ | Annuaire vétérinaires — liste + fiche détail + prise de RDV |
| ⬜ | Annuaire vétérinaires — vue carte (marqueurs code couleur, filtres espèce/distance) |
| ⬜ | Annuaire ostéopathes & kinésithérapeutes — liste + carte + RDV |
| ⬜ | Annuaire naturopathes & médecines douces (chiropracteurs, acupuncteurs…) — liste + carte + RDV |
| ⬜ | Assurances animaux — annuaire / comparateur de contrats |
| ⬜ | - [ ] |

---

## 14b. Marketplace

> Remplace la section "Produits". Espace commercial et partenaires.

| Statut | Fonctionnalité |
|---|---|
| ⬜ | Petfood — catalogue marques/produits |
| ⬜ | Accessoires — liste produits |
| ⬜ | Créateurs — annuaire artisans/créateurs pour animaux |
| ⬜ | Bons plans — espace publicitaire / partenariats / promotions |
| ⬜ | - [ ] |

---

## 14c. Éducation & Garde

| Statut | Fonctionnalité |
|---|---|
| ✅ | Éducateurs canins — liste + fiche + RDV |
| ✅ | Comportementalistes — liste + fiche + RDV |
| ✅ | Pet sitters — liste + fiche + RDV |
| ✅ | Promeneurs — liste + fiche + RDV |
| ✅ | Pensions — liste + fiche |
| ✅ | Registre pension (entrée/sortie animaux en pension) |
| ⬜ | Zone de travail géographique pet sitter & promeneurs (polygone ou rayon sur carte) |
| ⬜ | - [ ] |

---

## 14d. Communauté

> Fusion de l'ancienne section "Communauté" et "Animal Friendly". Animal Friendly est supprimé en tant que section séparée.

| Statut | Fonctionnalité |
|---|---|
| ✅ | Forum — catégories → sujets → réponses + création sujet |
| ✅ | Groupes — liste / rejoindre / quitter / créer / rôle admin |
| ✅ | Balades collectives — liste + niveau badge + rejoindre + créer |
| ✅ | Événements — liste + filtres type + inscription "Je participe" + création |
| ⬜ | Adoption association — annuaire associations + animaux à adopter |
| ⬜ | - [ ] |

---

## 14e. Sorties & Voyages

> Remplace "Animal Friendly". Lieux et séjours accueillant les animaux.

| Statut | Fonctionnalité |
|---|---|
| ⬜ | Parcs — liste + carte des parcs acceptant les animaux |
| ⬜ | Restaurants — liste + carte des restaurants pet-friendly |
| ⬜ | Séjours — hôtels / campings / locations saisonnières / Airbnb acceptant les animaux |
| ⬜ | Filtres par type d'hébergement, espèce acceptée, région |
| ⬜ | - [ ] |

> **Note UI** : Uniformiser la taille de police et l'alignement des titres de catégories sur la page Services.

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
