# PetsMatch — Specs Onboarding par profil + Module Anatomie 3D
**Version : 2026-08-06**

---

## TABLE DES MATIÈRES

1. [Principes généraux de l'onboarding](#1-principes-généraux)
2. [Architecture commune](#2-architecture-commune)
3. [Onboarding Éleveur](#3-onboarding-éleveur)
4. [Onboarding Association](#4-onboarding-association)
5. [Onboarding Particulier](#5-onboarding-particulier)
6. [Onboarding Vétérinaire](#6-onboarding-vétérinaire)
7. [Onboarding Pension](#7-onboarding-pension)
8. [Onboarding Pet sitter / Promeneur (Garde)](#8-onboarding-pet-sitter--promeneur-garde)
9. [Onboarding Éducateur / Comportementaliste](#9-onboarding-éducateur--comportementaliste)
10. [Onboarding Ostéopathe / Para-médical (Santé)](#10-onboarding-ostéopathe--para-médical-santé)
11. [Onboarding Toiletteur](#11-onboarding-toiletteur)
12. [Onboarding Photographe](#12-onboarding-photographe)
13. [Emails d'activation (séquence commune)](#13-emails-dactivation-séquence-commune)
14. [Module Anatomie 3D — Ostéopathe](#14-module-anatomie-3d--ostéopathe)

---

## 1. Principes généraux

### Philosophie

L'onboarding PetsMatch suit une règle simple : **l'utilisateur doit créer une vraie donnée avant de fermer l'app la première fois.** Un profil vide ne convertit pas. Un utilisateur qui a rentré son premier animal, son premier RDV ou son premier protocole a un engagement émotionnel — il ne repart pas facilement.

**Règle d'or : maximum 4 étapes par onboarding. Jamais plus.**

### Modèle d'essai (1 mois gratuit, sans CB)

- Accès complet à toutes les fonctionnalités du plan le plus élevé du profil pendant 30 jours
- Pas de carte bancaire à l'inscription
- Rappel à J+25 ("votre essai se termine dans 5 jours") avec récapitulatif des données créées
- À J+30 : downgrade automatique vers le plan FREE (données conservées, features pro masquées)

### Ce que l'onboarding doit accomplir

1. **Compléter le profil** (au moins les champs obligatoires)
2. **Créer une première donnée métier** (animal, logement, RDV selon profil)
3. **Déclencher la première valeur perçue** (ex : un protocole généré, un certificat pré-rempli)
4. **Montrer le chemin vers les features différenciantes**

### Règles d'affichage

- L'onboarding se lance automatiquement à la première connexion après inscription
- Il est ignorable via un bouton "Passer" visible mais discret
- En cas d'abandon, un bandeau "Finalisez votre profil — X étapes restantes" reste affiché en haut du dashboard jusqu'à complétion
- L'onboarding est accessible à tout moment depuis les paramètres ("Reprendre le guide")
- Sur web : modal plein écran avec navigation prev/next
- Sur app : stack de pages dédiées avec barre de progression

---

## 2. Architecture commune

### Étape 0 — Écran de bienvenue (identique tous profils)

Affiché immédiatement après la création du compte, avant les étapes métier.

**Contenu :**
```
🐾  Bienvenue sur PetsMatch, [Prénom] !

Votre essai gratuit de 30 jours commence aujourd'hui.
Accès complet à toutes les fonctionnalités — aucune CB requise.

[Commencer la configuration →]   [Passer pour l'instant]
```

**Design :** illustration de l'espèce principale (si connue à l'inscription) + palette PetsMatch (vert `#6E9E57`, teal `#0C5C6C`).

### Barre de progression

Présente sur toutes les étapes :
```
● ── ○ ── ○ ── ○
 1    2    3    4
```
Pastilles colorées en vert au fur et à mesure. Libellé sous chaque pastille (ex : "Profil", "Premier animal", "Protocole", "C'est parti !").

### Écran de fin (identique tous profils)

```
✅  Votre espace est prêt !

Vous avez créé :
• 1 profil vérifié
• [X] [animaux / logements / RDV]
• [Y] [protocoles / certificats / tâches]

Votre essai se termine le [date + 30j].

[Accéder à mon tableau de bord →]
```

---

## 3. Onboarding Éleveur

**Durée cible : 5-8 min**
**Objectif : profil complété + 1 animal créé + 1 certificat d'engagement découvert**

### Étape 1 — Compléter le profil élevage

Champs pré-remplis depuis l'inscription, à compléter :

| Champ | Obligatoire | Note |
|---|---|---|
| Nom de l'élevage | ✅ | |
| Photo de profil | — | Recommandé pour la confiance |
| Photo bannière | — | |
| SIRET | ✅ | Validation format |
| Numéro d'élevage (DDPP) | ✅ | |
| ACACED (numéro + justificatif) | ✅ | Upload PDF/image |
| Adresse complète | ✅ | Géocodage auto |
| Espèces élevées | ✅ | Multi-sélection |
| Races principales | ✅ | Autocomplete JSON |
| Téléphone professionnel | ✅ | |
| Description de l'élevage | Recommandé | Min 50 caractères |

**Action :** bouton "Enregistrer et continuer →"

### Étape 2 — Créer votre premier animal

Formulaire simplifié (pas tous les onglets, juste l'identité) :

| Champ | Obligatoire |
|---|---|
| Nom | ✅ |
| Espèce | ✅ |
| Race | ✅ |
| Sexe | ✅ |
| Date de naissance | ✅ |
| Photo | Recommandé |
| N° de puce / tatouage | ✅ |

Message de guidage : "Vous pourrez ajouter la généalogie, le suivi repro et le carnet santé depuis la fiche de votre animal."

**Action :** "Ajouter cet animal →" ou "Passer cette étape"

### Étape 3 — Découvrir le certificat d'engagement

Écran de présentation interactive (pas de formulaire à remplir) :

```
📄 Le certificat d'engagement est obligatoire depuis 2022
   pour toute cession de chien ou chat (Loi Lucie Castets).

   PetsMatch le génère automatiquement depuis la fiche de
   votre animal, pré-rempli avec vos informations.

   [Voir un exemple de certificat]   [Continuer →]
```

Si l'utilisateur clique "Voir un exemple" : PDF de démonstration s'ouvre.

### Étape 4 — Découvrir les protocoles sanitaires

```
🗓  Planifiez vos protocoles une fois, exécutez-les
    automatiquement pour chaque portée.

    Exemple : Protocole vermifuge chiots
    • J+21 naissance : Panacur® 5 jours
    • J+42 : Rappel 3 jours
    • J+56 : Rappel 3 jours

    Toutes les tâches sont générées et notifiées
    automatiquement.

    [Créer mon premier protocole →]   [Plus tard]
```

Si clic "Créer" → redirige vers la page de création de template (hors onboarding, étape terminée).

---

## 4. Onboarding Association

**Durée cible : 5-8 min**
**Objectif : profil complété + 1 animal en refuge créé + famille d'accueil ou chenil découvert**

### Étape 1 — Compléter le profil association

| Champ | Obligatoire |
|---|---|
| Nom de l'association | ✅ |
| Numéro RNA | ✅ |
| SIRET (si applicable) | — |
| Agrément préfectoral | Si applicable |
| Photo + bannière | Recommandé |
| Adresse complète | ✅ |
| Espèces accueillies | ✅ |
| Capacité d'accueil (nb animaux max) | ✅ |
| Description / présentation | Recommandé |
| Documents légaux (statuts PDF) | — |

Note affiché : "Votre profil sera vérifié par l'équipe PetsMatch sous 48h. Vous pouvez utiliser l'app pendant ce délai."

### Étape 2 — Ajouter un premier animal en refuge

Formulaire simplifié, statuts spécifiques association :

| Champ | Obligatoire |
|---|---|
| Nom | ✅ |
| Espèce | ✅ |
| Race (ou croisé) | ✅ |
| Sexe | ✅ |
| Âge estimé | ✅ |
| Photo | Recommandé |
| Statut | ✅ (en soin / disponible à l'adoption / en FA) |
| Identification (puce/tatouage) | Si disponible |

### Étape 3 — Chenil ou famille d'accueil ?

Écran de choix :

```
Comment gérez-vous vos animaux entre le refuge et les adoptants ?

  🏠  Familles d'accueil          🏢  Chenil / Enclos
  Placer des animaux chez         Gérer les logements
  des particuliers bénévoles      de votre refuge

  [Configurer mes FA →]           [Configurer mon chenil →]

  [Les deux]                      [Passer pour l'instant]
```

Selon le choix, redirige vers la page de configuration correspondante (hors onboarding).

### Étape 4 — Inviter votre premier bénévole

```
👥  Votre équipe peut accéder à PetsMatch

    Ajoutez un bénévole ou un employé pour qu'il
    puisse voir les animaux et valider ses tâches.

    [Rechercher un utilisateur PetsMatch →]
    [Inviter par email →]
    [Plus tard]
```

---

## 5. Onboarding Particulier

**Durée cible : 2-3 min**
**Objectif : profil complété + 1 animal personnel créé**

### Étape 1 — Compléter le profil

| Champ | Obligatoire |
|---|---|
| Prénom, Nom | ✅ |
| Ville / Code postal | ✅ |
| Téléphone | ✅ |
| Photo de profil | Recommandé |

### Étape 2 — Ajouter votre premier animal

```
🐾  Quel est votre compagnon ?

    [Chien]  [Chat]  [Lapin]  [Cheval]  [NAC]  [Autre]
```

Formulaire minimal selon espèce :
- Nom, race, date de naissance, photo, numéro de puce

### Étape 3 — Ce que vous pouvez faire

Écran vitrine des features particulier (pas d'action requise) :

```
Avec PetsMatch, vous pouvez :

🏥  Carnet de santé numérique
    Vaccins, antiparasitaires, visites vétérinaires
    → tout en un endroit

🔍  Animaux perdus / trouvés
    Signalez ou retrouvez un animal sur la carte

📅  Agenda & rappels
    Vaccins, RDV vétérinaires — jamais oublié

💬  Messagerie
    Contactez éleveurs et professionnels directement

[Accéder à mon espace →]
```

---

## 6. Onboarding Vétérinaire

**Durée cible : 5-7 min**
**Objectif : profil pro complété + zone d'intervention configurée + 1er RDV découvert**

### Étape 1 — Profil professionnel

| Champ | Obligatoire |
|---|---|
| Nom / Raison sociale | ✅ |
| N° Ordre des Vétérinaires | ✅ |
| SIRET | ✅ |
| Photo + bannière | Recommandé |
| Adresse cabinet | ✅ |
| Spécialités | ✅ (multi-sélection : NAC, équin, canin/félin, exotiques…) |
| Espèces traitées | ✅ |
| Téléphone pro | ✅ |
| Site web | — |
| Langues parlées | — |

### Étape 2 — Zone d'intervention

```
📍  Définissez votre zone d'intervention

    [Carte interactive]
    → Glissez le curseur pour ajuster le rayon (km)
    → Votre adresse est le centre

    Rayon actuel : [25 km]  ←──────●──────→

    Les propriétaires dans ce rayon verront votre profil
    en priorité.
```

### Étape 3 — Vos créneaux de disponibilité

Semainier simplifié :

```
Cochez vos jours et horaires habituels :

  Lun  [✓] 08:00 → 19:00
  Mar  [✓] 08:00 → 19:00
  Mer  [✓] 08:00 → 12:00
  Jeu  [✓] 08:00 → 19:00
  Ven  [✓] 08:00 → 18:00
  Sam  [✓] 09:00 → 12:00
  Dim  [ ]
```

Possibilité d'affiner plus tard depuis "Mes disponibilités".

### Étape 4 — Accès au carnet santé

```
🩺  Demandez l'accès aux fiches de vos patients

    Vos clients peuvent partager le carnet santé
    de leur animal avec vous via PetsMatch.

    Comment ça marche :
    1. Le client vous ajoute comme vétérinaire référent
    2. Vous recevez une demande d'accès
    3. Vous consultez le carnet santé en lecture,
       et pouvez y ajouter des soins (plan Avancé+)

    [Voir les demandes en attente]   [Compris →]
```

---

## 7. Onboarding Pension

**Durée cible : 6-8 min**
**Objectif : profil complété + 1 logement créé + planning découvert**

### Étape 1 — Profil pension

| Champ | Obligatoire |
|---|---|
| Nom de la pension | ✅ |
| SIRET | ✅ |
| Agrément DDPP | ✅ |
| ACACED (numéro + justificatif) | ✅ |
| Adresse | ✅ |
| Photo + bannière | Recommandé |
| Espèces accueillies | ✅ |
| Capacité totale | ✅ |
| Téléphone + email | ✅ |
| Tarifs (grille de base) | Recommandé |

### Étape 2 — Créer vos premiers logements

```
🏠  Ajoutez vos logements

    Comment appelez-vous vos espaces ?

    [Box individuel]  [Enclos collectif]
    [Chatterie]       [Cage NAC]
    [Suite haut de gamme]

    Nom du premier logement : [__________]
    Espèce(s) acceptée(s) : [Chien] [Chat] [NAC]
    Capacité : [1] animal(aux) max

    [Ajouter ce logement →]   [Passer →]
```

### Étape 3 — Le planning d'occupation

```
📅  Votre planning hôtelier en temps réel

    [Aperçu du planning sur 14 jours]
    → Chaque logement = une ligne
    → Barres colorées = séjours en cours et à venir
    → Clic sur une case libre = nouvelle entrée

    [Explorer le planning →]   [Continuer →]
```

### Étape 4 — Configurer vos tarifs

```
💶  Vos tarifs de base

    Ces tarifs seront automatiquement proposés à la facturation.

    Par espèce :
    Chien (< 10 kg)  [____] €/nuit
    Chien (10-25 kg) [____] €/nuit
    Chien (> 25 kg)  [____] €/nuit
    Chat             [____] €/nuit

    [Enregistrer →]   [Configurer plus tard]
```

---

## 8. Onboarding Pet sitter / Promeneur (Garde)

**Durée cible : 4-6 min**
**Objectif : profil complété + zone d'intervention + 1 service configuré**

### Étape 1 — Profil garde

| Champ | Obligatoire |
|---|---|
| Prénom, Nom / Nom commercial | ✅ |
| Sous-profession | ✅ (Pet sitter / Promeneur / Les deux) |
| SIRET ou statut | ✅ |
| ACACED (numéro + justificatif) | ✅ |
| Photo | ✅ |
| Adresse (centre de la zone) | ✅ |
| Espèces gardées | ✅ |
| Téléphone | ✅ |
| Description | Recommandé |

### Étape 2 — Zone d'intervention

Même composant que vétérinaire — carte + rayon en km.

### Étape 3 — Vos services

```
Quels services proposez-vous ?

  ✓  Garde à domicile (chez le client)
  ✓  Garde à mon domicile
  ✓  Promenade individuelle
  ✓  Promenade en groupe
  ✓  Visite quotidienne (chat / NAC)
  ✓  Garde de nuit

Pour chaque service actif, indiquez votre tarif de base :
  Visite quotidienne  [____] €
  Promenade           [____] €
  Journée garde       [____] €
  Nuit                [____] €
```

### Étape 4 — Vos disponibilités

Même semainier que vétérinaire + option "Disponible les jours fériés".

---

## 9. Onboarding Éducateur / Comportementaliste

**Durée cible : 5-7 min**

### Étape 1 — Profil éducateur

| Champ | Obligatoire |
|---|---|
| Nom / Nom commercial | ✅ |
| SIRET | ✅ |
| ACACED (numéro + justificatif) | ✅ |
| Certifications (CCPCC, CNECAD…) | ✅ si applicable |
| Méthodes pratiquées | ✅ (multi : positive, cognitive, mixte) |
| Espèces travaillées | ✅ |
| Photo + bannière | Recommandé |
| Adresse | ✅ |
| Zone d'intervention | ✅ |

### Étape 2 — Vos services

```
Quels types de séances proposez-vous ?

  ✓  Cours individuel (à domicile / en centre)
  ✓  Cours collectif
  ✓  Bilan comportemental
  ✓  Stage intensif
  ✓  Suivi à distance (visio)

Tarifs de base :
  Séance individuelle    [____] € / [____] min
  Cours collectif        [____] € / personne
  Bilan comportemental   [____] €
```

### Étape 3 — Zone d'intervention

Même carte + rayon.

### Étape 4 — Premier devis en 2 clics

```
💡  Avec PetsMatch, envoyez un devis en moins de 2 minutes.

    Sélectionnez un service → Choisissez un client →
    Le devis est pré-rempli et envoyé par email.

    [Créer un devis de démonstration →]   [Continuer →]
```

---

## 10. Onboarding Ostéopathe / Para-médical (Santé)

**Durée cible : 5-7 min**

### Étape 1 — Profil para-médical

| Champ | Obligatoire |
|---|---|
| Nom / Nom commercial | ✅ |
| Spécialité | ✅ (Ostéopathe / Kinésithérapeute / Acupuncteur / Naturopathe / Autre) |
| SIRET | ✅ |
| Diplôme / certification (upload) | ✅ |
| ACACED (numéro + justificatif) | ✅ |
| Photo | ✅ |
| Adresse cabinet | ✅ |
| Espèces traitées | ✅ |
| Zone d'intervention | ✅ |
| Téléphone | ✅ |

### Étape 2 — Vos séances

```
Quelles séances proposez-vous ?

  ✓  Consultation initiale (bilan)
  ✓  Séance de suivi
  ✓  Séance à domicile
  ✓  Séance en cabinet

Durées et tarifs :
  Bilan initial       [____] min   [____] €
  Séance de suivi     [____] min   [____] €
```

### Étape 3 — La vue anatomie (feature différenciante)

```
🦴  Un outil conçu pour votre pratique

    PetsMatch intègre une vue anatomique interactive
    pour noter et partager vos observations avec précision.

    → Sélectionnez une espèce et une zone sur le schéma
    → Annotez directement sur l'anatomie
    → L'annotation est enregistrée dans la fiche patient

    [Explorer la vue anatomie →]   [Plus tard]
```

Redirige vers le module anatomie (voir §14).

### Étape 4 — Accès aux fiches patients

Même logique que vétérinaire — demande d'accès, workflow propriétaire.

---

## 11. Onboarding Toiletteur

**Durée cible : 4-5 min**

### Étape 1 — Profil toilettage

| Champ | Obligatoire |
|---|---|
| Nom / Salon | ✅ |
| SIRET | ✅ |
| Certifications (BTM Toiletteur…) | Recommandé |
| Photo + bannière | ✅ |
| Adresse salon | ✅ |
| Service à domicile (oui/non) | ✅ |
| Zone si domicile | Si oui |
| Races travaillées | Recommandé |
| Téléphone | ✅ |

### Étape 2 — Vos prestations et tarifs

```
Prestations de base :

  Bain + séchage + brossage    [____] €
  Coupe + toilettage complet   [____] €
  Coupe seule                  [____] €
  Stripping                    [____] €
  Épilation                    [____] €

  Tarification : par [taille] ou par [race]
```

### Étape 3 — Vos disponibilités

Semainier + option liste d'attente activable.

### Étape 4 — Premier RDV

```
📅  Votre agenda est prêt

    Les clients peuvent prendre RDV directement
    depuis votre profil PetsMatch.

    [Voir mon agenda →]   [C'est parti →]
```

---

## 12. Onboarding Photographe

**Durée cible : 3-4 min**

### Étape 1 — Profil photographe

| Champ | Obligatoire |
|---|---|
| Nom / Studio | ✅ |
| SIRET | ✅ |
| Photo de profil | ✅ |
| 5 photos de portfolio | ✅ (minimum pour apparaître) |
| Bannière | ✅ |
| Adresse (zone géo) | ✅ |
| Zone d'intervention | ✅ |
| Espèces photographiées | ✅ |
| Style (reportage / studio / outdoor…) | Recommandé |

### Étape 2 — Vos tarifs et formules

```
Formules proposées :

  Séance 1h — [____] €    (nb photos livrées : [__])
  Séance 2h — [____] €    (nb photos livrées : [__])
  Reportage — [____] €    (durée : [__] h)
  Shooting en studio — [____] €
```

### Étape 3 — Vos disponibilités et contact

Semainier + bouton de contact direct.

---

## 13. Emails d'activation (séquence commune tous profils)

### Email J0 — Confirmation inscription

```
Sujet : Bienvenue sur PetsMatch, [Prénom] 🐾

Votre essai gratuit de 30 jours a commencé.

Accès complet à toutes les fonctionnalités — aucune
carte bancaire requise.

[Accéder à mon espace →]

Votre essai se termine le [date].
```

### Email J+3 — Nudge "première valeur"

Personnalisé par profil :

| Profil | Contenu |
|---|---|
| Éleveur | "Avez-vous créé votre premier certificat d'engagement ? En 2 min, il est pré-rempli depuis la fiche de votre animal." |
| Pension | "Votre planning d'occupation est prêt. Ajoutez votre premier séjour et testez la vue 14 jours." |
| Vétérinaire | "Un client peut partager le carnet santé de son animal avec vous. Voici comment activer cet accès." |
| Pet sitter | "Créez votre premier devis en 2 clics — et envoyez-le par email directement depuis l'app." |
| Particulier | "Le carnet santé de [animal] est vide. Ajoutez le dernier vaccin en 30 secondes." |

### Email J+7 — Feature découverte

Présentation d'une feature secondaire non utilisée (détectée automatiquement via données présentes en base).

### Email J+15 — Récapitulatif mi-parcours

```
Sujet : 15 jours d'essai — voici ce que vous avez créé

[Prénom],

En 15 jours sur PetsMatch :
✓ [N] animaux / logements / RDV
✓ [N] documents générés
✓ [N] tâches planifiées

Il vous reste 15 jours d'essai gratuit.
[Continuer à explorer →]
```

### Email J+25 — Alerte fin d'essai

```
Sujet : Votre essai se termine dans 5 jours

[Prénom], ne perdez pas vos données.

Vous avez créé [N] animaux, [N] documents et [N] tâches
sur PetsMatch. Sans abonnement, ces fonctionnalités
seront limitées au plan gratuit.

Plan Pro à partir de [X] €/mois — résiliable à tout moment.

[Choisir mon plan →]   [Voir les offres]
```

### Email J+30 — Downgrade

```
Sujet : Votre essai est terminé — vos données sont conservées

Votre compte est passé au plan gratuit.
Vos données sont intégralement conservées.

Ce que vous perdez sans abonnement : [liste courte features pro]

[Reprendre un abonnement Pro →]
```

### Trigger "non-actif" (si 0 connexion après J+5)

```
Sujet : Vous n'avez pas encore découvert [feature clé]

[Prénom], votre essai est en cours mais votre espace est vide.

Ça prend 2 minutes pour [action clé selon profil].

[Accéder maintenant →]
```

---

## 14. Module Anatomie 3D — Ostéopathe

> **Statut : Specs initiales — à affiner avec un développeur 3D avant implémentation**
> **Priorité : Phase 2 (après stabilisation du socle para-médical)**

### 14.1 Vision

Un outil de consultation et d'annotation anatomique directement intégré à la fiche patient, conçu pour les praticiens para-médicaux (ostéopathes, kinésithérapeutes, acupuncteurs, maréchaux-ferrants).

L'objectif est double :
- **Outil clinique** : visualiser l'anatomie en 3D pour préparer ou documenter une séance
- **Outil de communication** : partager des annotations avec le propriétaire et les autres praticiens autorisés

### 14.2 Fonctionnalités attendues

#### Visionneuse 3D

| Feature | Description |
|---|---|
| Modèle 3D par espèce | Chien, Chat, Cheval, Lapin — modèles distincts |
| Couches activables | Squelette seul / Muscles / Organes internes / Système nerveux / Tout |
| Rotation libre | Glisser pour faire pivoter (360° x + y), pinch-to-zoom |
| Vues prédéfinies | Face / Profil gauche / Profil droit / Dos / Ventrale / Craniale / Caudale |
| Transparence | Slider d'opacité par couche (squelette visible sous les muscles) |
| Mode comparaison | Animal sain (référence) vs animal en soin (côte à côte) |

#### Encyclopédie intégrée

- Clic sur une zone anatomique → fiche Wikipedia-style avec : nom (FR + latin), description, pathologies associées fréquentes, points d'acupuncture si applicable
- Recherche par nom ("L7", "processus épineux", "os naviculaire")
- Source : base propriétaire éditorisée (pas de lien externe — cohérence garantie)
- Disponible hors connexion (données bundlées dans l'app)

#### Annotations sur la fiche patient

- Depuis la vue 3D, l'ostéopathe peut **poser un pin** sur une zone
- Un pin = un commentaire textuel + date de séance + praticien
- Plusieurs pins possibles par séance, plusieurs séances conservées
- Historique des annotations visible dans la fiche patient (onglet dédié)
- Les pins sont codés par couleur : 🔴 zone douloureuse / 🟡 zone à surveiller / 🟢 zone traitée / 🔵 note générale
- Export PDF de la séance : vue 3D + pins annotés + commentaires = compte-rendu envoyable au propriétaire

#### Partage

- Le propriétaire peut voir les annotations (lecture seule) depuis sa propre fiche animal
- L'ostéopathe peut partager une séance annotée avec un autre praticien PetsMatch (avec accord du propriétaire)
- Compatible avec le système d'accès `animal_access` existant

### 14.3 Espèces et modèles — Phase 1 vs Phase 2

| Phase | Espèces | Couches |
|---|---|---|
| **Phase 1** | Chien, Chat | Squelette + Muscles + Organes principaux |
| **Phase 2** | Cheval, Lapin | + Système nerveux + Acupuncture |
| **Phase 3** | NAC (lapin, furet, oiseau) | + Points d'acupuncture indexés |

### 14.4 Architecture technique

#### Option A — Viewer 3D natif (recommandée)

- **Format modèles :** glTF 2.0 (standard ouvert, léger, supporté par toutes les lib 3D)
- **Flutter :** package `model_viewer_plus` (wrapper WebView du viewer Google) ou `three_dart` (port Three.js pour Flutter)
- **Web :** Three.js (déjà dans le stack PetsMatch pour les visualisations)
- **Stockage modèles :** Firebase Storage (téléchargement à la première utilisation, mis en cache)
- **Taille estimée par modèle :** 5-15 Mo (squelette + muscles + organes en glTF compressé)

#### Option B — Viewer WebGL embarqué

- Une page web hébergée sur le site PetsMatch, intégrée dans l'app via `WebView`
- Plus simple à maintenir (une seule codebase pour app + web)
- Légèrement moins performant que le natif Flutter pur
- **Recommandée si les modèles sont complexes** (équin notamment)

#### Schéma BDD — Annotations

```sql
CREATE TABLE anatomie_annotations (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  animal_id      UUID NOT NULL REFERENCES animaux(id) ON DELETE CASCADE,
  pro_profile_id UUID NOT NULL,          -- praticien qui annote
  seance_date    DATE NOT NULL,
  espece         TEXT NOT NULL,           -- chien / chat / cheval / lapin
  couche         TEXT NOT NULL,           -- squelette / muscles / organes
  position_x     FLOAT8 NOT NULL,        -- coordonnée 3D sur le modèle (0-1)
  position_y     FLOAT8 NOT NULL,
  position_z     FLOAT8 NOT NULL,
  zone_label     TEXT,                    -- nom de la zone cliquée (ex: "L4")
  couleur        TEXT NOT NULL DEFAULT 'rouge',  -- rouge/jaune/vert/bleu
  commentaire    TEXT,
  visible_owner  BOOLEAN DEFAULT true,    -- partagé avec le propriétaire
  created_at     TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_annotations_animal ON anatomie_annotations (animal_id, seance_date DESC);
```

#### Table encyclopédie

```sql
CREATE TABLE anatomie_encyclopedie (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  espece      TEXT NOT NULL,
  couche      TEXT NOT NULL,
  zone_id     TEXT NOT NULL UNIQUE,       -- ex: "chien_squelette_L4"
  nom_fr      TEXT NOT NULL,
  nom_latin   TEXT,
  description TEXT NOT NULL,
  pathologies TEXT[],                     -- ["hernie discale", "spondylarthrose"]
  points_acu  TEXT[],                     -- ["VB 30", "VE 36"] si applicable
  image_url   TEXT                        -- illustration 2D optionnelle
);
```

### 14.5 Acquisition des modèles 3D

C'est le point critique du projet. Trois options :

**Option 1 — Achat de modèles existants (recommandée pour la Phase 1)**

Sources vétérinaires professionnelles :
- Zygote Body (zygotebody.com) — modèles médicaux, licence commerciale disponible
- Anatomy.tv (Primal Pictures) — modèles vétérinaires, coûteux mais de référence
- TurboSquid / CGTrader — modèles 3D tiers, vérifier la précision anatomique

Budget estimé : 500-3 000€ pour chien + chat en glTF avec couches séparées.

**Option 2 — Modélisation sur mesure**

Faire modéliser par un studio spécialisé en anatomie vétérinaire.
Budget estimé : 5 000-15 000€ par espèce selon détail demandé.
Avantage : propriété des assets, précision garantie, couches sur mesure.

**Option 3 — Partenariat académique**

Écoles vétérinaires (Maisons-Alfort, Lyon, Nantes, Toulouse) ou laboratoires d'anatomie — échange de visibilité contre accès aux modèles existants.
À explorer avant de dépenser sur option 1 ou 2.

### 14.6 Roadmap recommandée

```
Phase 0 (décision) — J0 à J+30
  ├── Choisir les modèles (achat / modélisation / partenariat)
  ├── Tester le viewer sur un modèle test (package Flutter)
  └── Valider l'UX avec 2-3 ostéopathes utilisateurs réels

Phase 1 — Chien + Chat (socle)
  ├── Viewer 3D Flutter + Web (rotation, zoom, couches)
  ├── Vues prédéfinies (6 angles)
  ├── Encyclopédie chien + chat (squelette + organes principaux)
  ├── Annotations (pins + commentaires) sur fiche patient
  └── Export PDF séance

Phase 2 — Cheval + enrichissement
  ├── Modèle cheval (enjeu fort pour ostéopathes équins)
  ├── Points d'acupuncture indexés
  ├── Mode comparaison
  └── Partage inter-praticiens

Phase 3 — NAC + acupuncture
  ├── Lapin, furet
  └── Interface acupuncture dédiée (mapping des méridiens)
```

### 14.7 Maquette UX — Vue principale

```
┌────────────────────────────────────────────────────────────┐
│  🦴 Anatomie — [Nom de l'animal] (Labrador, 4 ans)         │
├─────────────┬──────────────────────────────────────────────┤
│             │                                              │
│  COUCHES    │         [VISIONNEUSE 3D]                    │
│  ─────────  │                                              │
│  ☑ Squelette│         🐕 modèle 3D rotatif                │
│  ☑ Muscles  │                                              │
│  ☐ Organes  │    🔴 L4        🟡 Bassin                  │
│  ☐ Nerfs    │                                              │
│             │                                              │
│  VUES       │                                              │
│  ─────────  │                                              │
│  [Face]     ├──────────────────────────────────────────────┤
│  [Profil G] │  SÉANCE DU [date]                           │
│  [Profil D] │  🔴 L4 — "Contracture paravertébrale gauche" │
│  [Dos]      │  🟡 Bassin — "Légère asymétrie à surveiller" │
│  [Ventrale] │  + Ajouter une note                         │
│             │                                              │
│  [Encyclop.]│  [Exporter PDF]  [Partager]                  │
└─────────────┴──────────────────────────────────────────────┘
```

---

*Document PetsMatch — Onboarding par profil + Module Anatomie 3D*
*À intégrer dans les specs principales (specs_petsmatch.md) une fois validé.*
