# Specs PetsMatch — Fonctionnalités à implémenter
> Dernière mise à jour : 2026-06-11  
> Ce document est la référence fonctionnelle pour l'app Flutter (Android/iOS) et le site web Next.js.  
> **Règle absolue** : chaque feature est implémentée sur les **3 surfaces** (Android, iOS, Web) et dans le **panel Admin**.

---

## TABLE DES MATIÈRES

1. [Profil Association](#1-profil-association)
2. [Certificat d'Engagement et d'Information](#2-certificat-dengagement-et-dinformation)
3. [Annonces Association (feed séparé)](#3-annonces-association-feed-séparé)
4. [Planning Chenil / Hôtel](#4-planning-chenil--hôtel)
5. [Gestion des Employés](#5-gestion-des-employés)
6. [Schéma BDD — nouvelles tables Supabase](#6-schéma-bdd--nouvelles-tables-supabase)
7. [Priorités et dépendances](#7-priorités-et-dépendances)
8. [Modèle économique — Abonnements, Boosts & Marketplace](#8-modèle-économique--abonnements-boosts--marketplace)
9. [Validation automatique & Badges de confiance](#9-validation-automatique--badges-de-confiance)

---

## 1. Profil Association

### 1.1 Périmètre

Un profil Association est quasi-identique au profil Éleveur avec les différences suivantes :

| Fonctionnalité | Éleveur | Association |
|---|---|---|
| Animaux (fiche complète) | ✅ | ✅ |
| Généalogie / arbres | ✅ | ❌ (non pertinent) |
| Suivi repro (saillie, gestation…) | ✅ | ❌ |
| Portées | ✅ | ❌ |
| Annonces vente | ✅ | ❌ → Annonces adoption (feed séparé) |
| Certificat d'engagement | ✅ obligatoire | ✅ obligatoire |
| Contrats de cession | ✅ | ✅ (adapté adoption) |
| Gestion employés / bénévoles | ❌ | ✅ |
| Planning chenil/hôtel | ❌ | ✅ (si hébergement) |
| Registre entrées/sorties | ✅ | ✅ |
| Familles d'accueil (FA) | ❌ | ✅ (voir §1.5) |

### 1.2 Champs du profil

```
Nom de l'association        (obligatoire)
Numéro RNA                  (Répertoire National des Associations, ex: W751234567)
SIRET                       (si l'asso a une activité économique)
Numéro agrément préfectoral (si applicable — établissements pour animaux)
Adresse complète            (obligatoire)
Email de contact            (obligatoire)
Téléphone                   (obligatoire)
Site web / réseaux
Espèces accueillies         (liste multiple)
Capacité d'accueil          (nombre d'animaux max en simultané)
Description / présentation
Photo de l'association + bannière
Documents légaux            (statuts PDF, arrêté préfectoral…)
```

### 1.3 Inscription

- Nouveau type de compte lors de l'inscription : **Association**
- Même flux que l'éleveur mais champs spécifiques (RNA, agrément)
- Vérification manuelle par l'admin avant validation (badge "Vérifié" sur le profil)
- Table Supabase : `users` avec `is_association = true` + table `associations` pour les détails

### 1.4 Animaux en association

- Même structure que les animaux éleveur (table `animaux`)
- Statuts spécifiques : **en soin / disponible à l'adoption / adopté / en FA / décédé / transféré**
- Pas de champs généalogie affichés
- Fiche animal : onglets Identité · Santé · Alimentation · Propriétaire (FA ou adoptant)
- Identification obligatoire avant mise à l'adoption (puce ou tatouage)

### 1.5 Familles d'accueil (FA)

- Réseau de FA lié à l'association (table `familles_accueil`)
- FA = utilisateur PetsMatch avec profil FA rattaché à l'association
- L'association peut affecter un animal à une FA
- La FA voit les fiches des animaux qui lui sont confiés
- Suivi de l'animal pendant le placement (bilans, photos)
- L'animal reste propriété de l'association côté BDD jusqu'à l'adoption définitive

---

## 2. Certificat d'Engagement et d'Information

### 2.1 Base légale

**Loi n° 2021-1539 du 30 novembre 2021** (dite "Loi Lucie Castets") — Art. L. 214-8 Code Rural.

> Toute cession à titre onéreux ou gratuit d'un chien ou d'un chat doit être précédée de la remise d'un certificat d'engagement et d'information à l'acquéreur, qui dispose d'un **délai de réflexion de 7 jours** avant de signer.

**Espèces concernées et niveau d'obligation :**

| Espèce | Obligation |
|---|---|
| Chien | **Obligatoire** — délai réflexion 7 jours |
| Chat | **Obligatoire** — délai réflexion 7 jours |
| Lapin domestique | Recommandé (pas d'obligation légale stricte) |
| Cochon d'inde, hamster, rat… | Recommandé |
| Furet | Recommandé (CITES si concerné) |
| Perroquet / perruche | CITES + recommandé |
| Cheval / poney | Recommandé (contrat de vente habituel) |
| Ovin / caprin | Non applicable |

L'app gère les espèces **Chien et Chat comme obligatoires** ; pour les autres espèces le certificat est proposé et recommandé.

### 2.2 Contenu du certificat (template)

Le certificat généré par PetsMatch doit contenir :

**A — Identification du cédant**
- Nom / Raison sociale
- Adresse
- Téléphone / email
- N° SIRET ou RNA (pour associations)
- N° élevage (éleveurs) ou agrément préfectoral

**B — Identification de l'acquéreur**
- Nom, Prénom
- Adresse complète
- Téléphone
- Email

**C — Identification de l'animal**
- Espèce, Race, Sexe
- Date de naissance
- Couleur / signes distinctifs
- N° de puce électronique ou tatouage (obligatoire chiens/chats)
- N° LOF/LOOF si applicable

**D — Date et conditions de cession**
- Date de remise envisagée
- Modalités (vente / cession gratuite / adoption)
- Prix le cas échéant

**E — Engagements de l'acquéreur** (les 5 libertés + spécifiques)

> Je soussigné(e) _______, certifie avoir pris connaissance des besoins spécifiques de l'animal et m'engage à :
>
> 1. Répondre à ses **besoins physiologiques** (alimentation adaptée, eau fraîche, soins vétérinaires)
> 2. Permettre l'**expression de ses comportements naturels** (exercice, enrichissement, socialisation)
> 3. Le protéger de la **souffrance, de l'anxiété et de la peur**
> 4. Lui assurer un **environnement adapté** (espace, température, abri)
> 5. Veiller à sa **santé et son bien-être** tout au long de sa vie
> 6. Prendre en compte sa **durée de vie estimée** : chien X à Y ans, chat 12 à 20 ans selon race
> 7. Estimer et assumer les **coûts annuels** (alimentation, vétérinaire, assurance) : fourchette indicative par espèce
> 8. Vérifier la **compatibilité** avec ma situation (logement, mode de vie, enfants, autres animaux)
> 9. **Ne jamais abandonner** l'animal et contacter l'association/l'éleveur en cas de difficulté
> 10. Respecter la **législation** (identification obligatoire, vaccination antirabique si voyage…)

**F — Délai de réflexion (chiens/chats)**
> Pour les chiens et chats : l'acquéreur dispose de **7 jours calendaires** à compter de la remise de ce certificat avant de pouvoir signer le contrat de cession. Aucune somme ne peut être perçue pendant ce délai.

**G — Signatures**
- Date de remise du certificat
- Signature du cédant (numérique ou manuscrite scannée)
- Date de signature de l'acquéreur (après le délai légal)
- Signature de l'acquéreur

### 2.3 Flux utilisateur

```
Éleveur / Association
│
├── Crée une annonce (ou initie une cession directe)
│
├── Sélectionne un acquéreur intéressé
│
├── [App/Web] Génère le certificat d'engagement
│   └── Pré-remplit les champs depuis le profil + fiche animal
│
├── Envoie le certificat à l'acquéreur (email + notification in-app)
│
├── [Acquéreur] Reçoit, lit, et accuse réception (horodatage)
│   └── Début du délai de réflexion (chiens/chats)
│
├── [Après 7 jours] L'acquéreur peut signer numériquement
│   └── Ou refuser → cession annulée
│
├── [Éleveur/Asso] Voit le statut : Envoyé / Accepté / Signé / Refusé
│
└── [Signature double] → Contrat de cession disponible + PDF téléchargeable
```

### 2.4 Implémentation technique

**App Flutter :**
- Nouveau bouton "Générer certificat d'engagement" dans la fiche animal (statut "disponible")
- Formulaire pré-rempli + complétion manuelle des champs acquéreur
- Génération PDF côté serveur (Edge Function Supabase) ou côté client (package `pdf`)
- Signature numérique : dessin sur canvas ou case à cocher + OTP email
- Notification push à l'acquéreur

**Site web Next.js :**
- Même flux accessible depuis `/mes-animaux/[id]` et `/mes-annonces`
- PDF généré et téléchargeable directement
- Signature via lien email sécurisé (token 72h)

**Table Supabase :**
```sql
CREATE TABLE certificats_engagement (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  animal_id TEXT NOT NULL,
  cedant_uid TEXT NOT NULL,        -- éleveur ou association
  acquereur_uid TEXT,              -- si utilisateur PetsMatch
  acquereur_nom TEXT,
  acquereur_prenom TEXT,
  acquereur_adresse TEXT,
  acquereur_email TEXT NOT NULL,
  acquereur_telephone TEXT,
  date_remise TIMESTAMPTZ NOT NULL DEFAULT now(),
  date_signature_acquereur TIMESTAMPTZ,
  statut TEXT NOT NULL DEFAULT 'envoye',  -- envoye / lu / signe / refuse
  token_signature TEXT UNIQUE,     -- pour lien email
  pdf_url TEXT,                    -- URL Storage après génération
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

---

## 3. Annonces Association (feed séparé)

### 3.1 Principe

Les annonces d'associations **ne sont pas mélangées** aux annonces éleveurs/particuliers. Elles ont :
- Leur propre feed (`/annonces-association`)
- Leur propre section dans l'app (onglet dédié ou section dans Annonces)
- Badge "🏠 Association" visible sur chaque carte
- Visibles par tous sur le web sans compte

### 3.2 Types d'annonces association

| Type | Description |
|---|---|
| `adoption` | Animal disponible à l'adoption (principal) |
| `fa_recherchée` | Recherche une famille d'accueil |
| `parrainage` | Proposer de parrainer financièrement un animal |
| `collecte` | Appel aux dons (nourriture, matériel…) |
| `urgent` | Animal à sauver en urgence (badge rouge) |

### 3.3 Différences vs annonces éleveurs

| | Annonce éleveur | Annonce association |
|---|---|---|
| Prix | Prix de vente | Frais d'adoption (non obligatoire) |
| Processus | Achat direct | Candidature → étude dossier → visite → adoption |
| Formulaire réponse | Message simple | Formulaire de candidature structuré |
| Délai réflexion | 7 jours si chien/chat | 7 jours si chien/chat |
| Certificat engagement | ✅ | ✅ |
| Contrat cession | Contrat vente | Contrat adoption |

### 3.4 Formulaire de candidature d'adoption

L'acquéreur remplit un formulaire (in-app + web) :
- Présentation (profession, composition du foyer, enfants)
- Logement (maison/appt, surface, jardin, étage)
- Mode de vie (temps absent/jour, vacances, activité physique)
- Animaux actuels
- Expérience avec cette espèce / race
- Raisons de l'adoption
- Vétérinaire habituel (optionnel)
- Acceptation de visite de contrôle post-adoption

L'association reçoit la candidature, peut accepter/refuser/mettre en attente.

### 3.5 Schéma BDD

```sql
CREATE TABLE annonces_association (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  association_uid TEXT NOT NULL,
  animal_id TEXT,
  type TEXT NOT NULL DEFAULT 'adoption',  -- adoption/fa_recherchée/parrainage/collecte/urgent
  titre TEXT NOT NULL,
  description TEXT,
  frais_adoption NUMERIC,
  espece TEXT,
  race TEXT,
  age_mois INTEGER,
  sexe TEXT,
  sterilise BOOLEAN,
  vaccine BOOLEAN,
  identifie BOOLEAN,
  compatible_chiens BOOLEAN,
  compatible_chats BOOLEAN,
  compatible_enfants BOOLEAN,
  photos TEXT[],           -- URLs
  statut TEXT DEFAULT 'actif',  -- actif/en_cours/adopte/suspendu
  urgence BOOLEAN DEFAULT false,
  region TEXT,
  ville TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE candidatures_adoption (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  annonce_id UUID NOT NULL REFERENCES annonces_association(id),
  candidat_uid TEXT NOT NULL,
  reponses JSONB NOT NULL,      -- formulaire structuré
  statut TEXT DEFAULT 'en_attente',  -- en_attente/accepte/refuse/visite_planifiee/adopte
  notes_asso TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

---

## 4. Planning des Hébergements — Suivi opérationnel des lieux

### 4.1 Cible

- **Pension animaux de compagnie** (chenils, chatteries, cages NAC)
- **Pension équestre / Écuries** (boxes chevaux, paddocks, prés, carrières)
- **Association** (boxes chenil / chatterie / enclos)

La logique est la même dans tous les cas : tableau de bord temps réel pour les soigneurs. L'interface s'adapte au **mode** configuré par le pro (canin / équin / mixte).

### 4.2 Concept

Outil de **suivi en temps réel** pour le personnel. L'objectif est de savoir d'un coup d'œil :
- Quel animal est dans quel lieu en ce moment
- Quels lieux sont sales / à curer
- Quels lieux sont libres

Ce n'est **pas** un système de réservation hôtelière. C'est un tableau de bord opérationnel pour les soigneurs.

**Mode canin/NAC — vue tableau :**
```
Box 1    [🐕 Rex — M. Dupont]     [OCCUPÉ]     [🧹 À nettoyer]
Box 2    [— vide —]               [À NETTOYER] [✓ Marquer propre]
Box 3    [🐕 Luna — Mme Martin]  [OCCUPÉ]     [🧹 À nettoyer]
Box 4    [— vide —]               [LIBRE]      [+ Affecter un animal]
Box 5    [— vide —]               [HORS SERVICE]
Chatterie A  [🐈 Mimi]           [OCCUPÉ]
Enclos ext.  [🐕 Max + 🐕 Buddy] [OCCUPÉ — 2 animaux]
```

**Mode équin — vue tableau :**
```
               LIEU              ÉTAT LIEU       POSITION CHEVAL
Box 1     [🐴 Éclair — Mme Roy] [À CURER]       📍 Paddock A
Box 2     [🐴 Sultan — M. Petit][PROPRE]         📍 Box (présent)
Box 3     [🐴 Mistral]          [EN CURAGE]      📍 Paddock B
Box 4     [— vide —]            [LIBRE]          [+ Affecter]
Paddock A [🐴 Éclair]          [OCCUPÉ]
Paddock B [🐴 Mistral]         [OCCUPÉ]
Pré Nord  [🐴 Tornado + 🐴 Jazz][OCCUPÉ — 2]
Carrière  [— libre —]           [LIBRE]
```

### 4.3 États d'un lieu

| État | Couleur | Description | Mode |
|---|---|---|---|
| `libre` | 🟢 Vert | Vide et propre/curé, disponible | Tous |
| `occupe` | 🟠 Orange | Animal(aux) présent(s) | Tous |
| `a_nettoyer` | 🔴 Rouge | À nettoyer / désinfecter | Canin/NAC |
| `a_curer` | 🔴 Rouge | Fumier + litière à curer | Équin |
| `en_nettoyage` | 🟡 Jaune | Nettoyage/curage en cours | Tous |
| `hors_service` | ⚫ Gris | Indisponible (maintenance) | Tous |

### 4.4 Gestion des lieux

**Champs communs à tous les lieux :**
```
Nom / numéro          (ex: "Box 1", "Paddock A", "Pré Nord", "Carrière")
Type                  (selon mode, voir ci-dessous)
Espèces acceptées     (cheval / chien / chat / lapin / NAC…)
Capacité max          (nombre d'animaux simultanés)
Notes                 (précautions, incompatibilités, allergies litière…)
Actif / Hors service
```

**Types de lieux — Mode canin / NAC :**
| Type | Exemples |
|---|---|
| `box_individuel` | Box chien isolé |
| `enclos_collectif` | Enclos chiens compatibles |
| `chatterie` | Espace chats |
| `cage_nac` | Cage lapin, rongeur |
| `parc_exterieur` | Enclos extérieur |

**Types de lieux — Mode équin :**
| Type | Exemples |
|---|---|
| `box_cheval` | Box en écurie (≈ 9–16 m²) |
| `paddock` | Enclos extérieur individuel ou duo |
| `pre` | Prairie / pâture (plusieurs chevaux) |
| `carriere` | Carrière / manège (usage temporaire) |
| `couloir_lavage` | Wash-stall / couloir de soins |
| `box_veterinaire` | Box infirmerie / isolement |

**Champs supplémentaires — Mode équin uniquement :**
```
Type de litière       (paille / copeaux / caoutchouc / sans litière)
Surface (m²)          (info pour le soigneur)
Paddock associé       (lien vers le paddock habituel du cheval de ce box)
Abreuvoir automatique (oui / non)
```

### 4.5 Spécificités équines — Position du cheval dans la journée

Un cheval change de lieu plusieurs fois par jour (box la nuit → paddock / pré le matin pendant le curage → rentre le soir). L'interface gère deux niveaux distincts :

**Niveau 1 — État du lieu (box, paddock, pré…)**
- Indépendant de la position actuelle du cheval
- Suit le cycle de curage/nettoyage du box

**Niveau 2 — Position actuelle du cheval**
- "Où est ce cheval en ce moment" : box / paddock / pré / carrière / soins / sorti chez propriétaire
- Mis à jour par le soigneur lors de chaque déplacement
- Visible depuis la fiche animal + le tableau de bord

```
Tableau de bord vue cheval (alternative à la vue lieu) :

🐴 Éclair     → 📍 Paddock A     Box 1 [À CURER]
🐴 Sultan     → 📍 Box 2          Box 2 [PROPRE]
🐴 Mistral    → 📍 Paddock B     Box 3 [EN CURAGE]
🐴 Tornado    → 📍 Pré Nord
🐴 Jazz       → 📍 Pré Nord
```

### 4.6 Interface — Vue tableau de bord

**Onglets du planning :**
- **Vue lieux** (défaut) : une ligne par box/paddock/pré, état du lieu + animal présent
- **Vue chevaux** (mode équin) : une ligne par cheval, position actuelle + état du box attitré
- **Vue curage du jour** (mode équin) : liste des boxes à curer classés par priorité + soigneur assigné

**Actions rapides par état (vue lieux) :**
- `occupé` → "Animal parti" (devient `à_nettoyer` ou `à_curer`)
- `à_nettoyer / à_curer` → "Commencer" → `en_nettoyage` — puis "Terminé" → `libre`
- `libre` → "+ Affecter un animal"
- `hors_service` → "Remettre en service"
- `en_nettoyage` → "Terminé" → `libre`

**Actions rapides — spécifique équin :**
- "Sortir au paddock" → met à jour la position du cheval + libère le box pour curage
- "Rentrer au box" → remet le cheval dans son box (si propre)
- "Marquer curé" → box passe `libre`

**Filtres rapides :**
- Tous / Occupés / À nettoyer-curer / Libres / Hors service
- Par espèce / par type de lieu (boxes / paddocks / prés)

### 4.7 Workflow — Mode canin/NAC

```
Animal récupéré → soigneur tape "Animal parti"
→ Box passe en [À NETTOYER]

Soigneur commence → "En cours"
→ Box passe en [EN NETTOYAGE]

Nettoyage terminé → "Terminé"
→ Box passe en [LIBRE]
→ Notification manager si configuré
```

### 4.8 Workflow — Mode équin (curage)

```
Matin — soigneur sort le cheval :
→ "Sortir au paddock [Paddock A]"
→ Position cheval = Paddock A
→ Box passe en [À CURER] (cheval absent, box accessible)

Soigneur cure le box :
→ "Commencer curage" → Box passe en [EN CURAGE]
→ Fumier + litière retirés, nouvelle litière étendue

Curage terminé :
→ "Box prêt" → Box passe en [LIBRE / PROPRE]

Soir — soigneur rentre le cheval :
→ "Rentrer au box"
→ Position cheval = Box 1
→ Box passe en [OCCUPÉ]
```

### 4.9 Alertes et notifications

- Box en `à_nettoyer` / `à_curer` depuis + de 2h → rappel soigneur
- Box `hors_service` → visible en rouge partout
- Animal attendu aujourd'hui non encore affecté → alerte dashboard
- **Équin** : cheval au paddock depuis + de X heures (configurable) → rappel de rentrée
- **Équin** : box non curé avant 10h → alerte au manager

### 4.10 Schéma BDD

```sql
-- Définition des lieux (commun à tous les modes)
CREATE TABLE lieux_hebergement (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid TEXT NOT NULL,
  pro_profile_id UUID,
  nom TEXT NOT NULL,                      -- "Box 1", "Paddock A", "Pré Nord"
  type TEXT NOT NULL,                     -- box_individuel/enclos_collectif/chatterie/cage_nac/
                                          -- parc_exterieur/box_cheval/paddock/pre/carriere/
                                          -- couloir_lavage/box_veterinaire
  mode TEXT NOT NULL DEFAULT 'canin',     -- canin / equin / mixte
  especes_acceptees TEXT[],
  capacite INTEGER DEFAULT 1,
  surface_m2 NUMERIC,                    -- équin principalement
  type_litiere TEXT,                     -- paille/copeaux/caoutchouc (équin)
  paddock_associe_id UUID REFERENCES lieux_hebergement(id), -- box → paddock attitré (équin)
  abreuvoir_auto BOOLEAN DEFAULT false,  -- équin
  notes TEXT,
  actif BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- État courant de chaque lieu (1 ligne par lieu, temps réel)
CREATE TABLE etat_lieux_hebergement (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lieu_id UUID NOT NULL REFERENCES lieux_hebergement(id) ON DELETE CASCADE,
  statut TEXT NOT NULL DEFAULT 'libre',  -- libre/occupe/a_nettoyer/a_curer/en_nettoyage/hors_service
  animal_ids TEXT[],                     -- animaux présents dans ce lieu
  updated_at TIMESTAMPTZ DEFAULT now(),
  updated_by TEXT,
  notes TEXT,
  UNIQUE(lieu_id)
);

-- Position actuelle de chaque animal (équin — où est le cheval maintenant)
CREATE TABLE position_animaux (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  animal_id TEXT NOT NULL,
  pro_uid TEXT NOT NULL,
  lieu_actuel_id UUID REFERENCES lieux_hebergement(id),
  lieu_label TEXT,                       -- libellé libre si lieu hors écurie ("Soins véto", "Sorti")
  updated_at TIMESTAMPTZ DEFAULT now(),
  updated_by TEXT,
  UNIQUE(animal_id)
);

-- Historique des changements d'état (traçabilité)
CREATE TABLE historique_lieux_hebergement (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lieu_id UUID NOT NULL REFERENCES lieux_hebergement(id),
  statut_avant TEXT,
  statut_apres TEXT NOT NULL,
  animal_ids TEXT[],
  changed_by TEXT,
  changed_at TIMESTAMPTZ DEFAULT now(),
  notes TEXT
);
```

---

## 5. Gestion des Employés

### 5.1 Cible

- **Pension** : soigneurs, réceptionnistes, managers
- **Association** : bénévoles, salariés, responsables

### 5.2 Rôles et permissions

| Rôle | Consultation | Saisie | Planning | RDV | Finances | Admin |
|---|---|---|---|---|---|---|
| `admin` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| `manager` | ✅ | ✅ | ✅ | ✅ | Vue seule | ❌ |
| `soigneur` | Ses animaux | Fiches animaux | Son planning | ❌ | ❌ | ❌ |
| `benevole` | Ses animaux | Rapports basiques | Ses créneaux | ❌ | ❌ | ❌ |

### 5.3 Invitation et onboarding

- L'admin envoie une **invitation par email**
- L'employé crée son compte PetsMatch ou lie son compte existant
- Il est rattaché au profil de la structure avec son rôle
- Il voit un dashboard adapté à son rôle

### 5.4 Planning employés

- Chaque employé a ses **créneaux de travail** (type créneaux_pro mais pour les salariés)
- Vue planning hebdomadaire : qui est présent quel jour/heure
- Affectation : quel soigneur s'occupe de quel animal / quelle chambre
- Notifications aux soigneurs pour leurs tâches du jour

### 5.5 Schéma BDD

```sql
CREATE TABLE structure_employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid TEXT NOT NULL,           -- UID de la pension/association
  pro_profile_id UUID,
  employee_uid TEXT,               -- UID du compte PetsMatch de l'employé
  email TEXT NOT NULL,
  nom TEXT, prenom TEXT,
  role TEXT DEFAULT 'soigneur',    -- admin/manager/soigneur/benevole
  statut TEXT DEFAULT 'invite',    -- invite/actif/inactif/refuse
  invite_token TEXT UNIQUE,
  invite_expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE employee_plannings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES structure_employees(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  heure_debut TIME,
  heure_fin TIME,
  notes TEXT
);
```

---

## 6. Schéma BDD — nouvelles tables Supabase

Récapitulatif de toutes les migrations à exécuter :

```sql
-- 1. Flag association dans users
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_association BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS association_id UUID;

-- 2. Détails association
CREATE TABLE IF NOT EXISTS associations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid TEXT NOT NULL UNIQUE,           -- Firebase UID
  nom TEXT NOT NULL,
  rna TEXT,                           -- ex: W751234567
  siret TEXT,
  agrement_prefectoral TEXT,
  especes_accueillies TEXT[],
  capacite_accueil INTEGER,
  adresse TEXT, ville TEXT, code_postal TEXT, departement TEXT, region TEXT,
  email TEXT, telephone TEXT, site_web TEXT,
  description TEXT,
  logo_url TEXT, banniere_url TEXT,
  is_validated BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 3. Familles d'accueil
CREATE TABLE IF NOT EXISTS familles_accueil (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  association_uid TEXT NOT NULL,
  fa_uid TEXT NOT NULL,               -- compte PetsMatch de la FA
  statut TEXT DEFAULT 'actif',
  animaux_actuels INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 4. Certificats d'engagement
CREATE TABLE IF NOT EXISTS certificats_engagement (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  animal_id TEXT NOT NULL,
  cedant_uid TEXT NOT NULL,
  acquereur_uid TEXT,
  acquereur_nom TEXT, acquereur_prenom TEXT,
  acquereur_adresse TEXT, acquereur_email TEXT NOT NULL, acquereur_telephone TEXT,
  date_remise TIMESTAMPTZ NOT NULL DEFAULT now(),
  date_signature_acquereur TIMESTAMPTZ,
  statut TEXT NOT NULL DEFAULT 'envoye',
  token_signature TEXT UNIQUE,
  pdf_url TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 5. Annonces association
CREATE TABLE IF NOT EXISTS annonces_association (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  association_uid TEXT NOT NULL,
  animal_id TEXT,
  type TEXT NOT NULL DEFAULT 'adoption',
  titre TEXT NOT NULL,
  description TEXT,
  frais_adoption NUMERIC,
  espece TEXT, race TEXT, age_mois INTEGER, sexe TEXT,
  sterilise BOOLEAN, vaccine BOOLEAN, identifie BOOLEAN,
  compatible_chiens BOOLEAN, compatible_chats BOOLEAN, compatible_enfants BOOLEAN,
  photos TEXT[],
  statut TEXT DEFAULT 'actif',
  urgence BOOLEAN DEFAULT false,
  region TEXT, ville TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 6. Candidatures adoption
CREATE TABLE IF NOT EXISTS candidatures_adoption (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  annonce_id UUID NOT NULL REFERENCES annonces_association(id),
  candidat_uid TEXT NOT NULL,
  reponses JSONB NOT NULL,
  statut TEXT DEFAULT 'en_attente',
  notes_asso TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 7. Chambres pension / chenil
CREATE TABLE IF NOT EXISTS chambres_pension (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid TEXT NOT NULL,
  pro_profile_id UUID,
  nom TEXT NOT NULL,
  type TEXT DEFAULT 'individuel',
  especes_acceptees TEXT[],
  capacite INTEGER DEFAULT 1,
  taille TEXT,
  equipements TEXT[],
  photo_url TEXT,
  notes TEXT,
  tarif_nuit NUMERIC,
  actif BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 8. Réservations chenil
CREATE TABLE IF NOT EXISTS reservations_chenil (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chambre_id UUID NOT NULL REFERENCES chambres_pension(id) ON DELETE CASCADE,
  rdv_id UUID,
  animal_id TEXT,
  proprietaire_uid TEXT,
  date_debut DATE NOT NULL,
  date_fin DATE NOT NULL,
  statut TEXT DEFAULT 'reserve',
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 9. Employés / bénévoles
CREATE TABLE IF NOT EXISTS structure_employees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid TEXT NOT NULL,
  pro_profile_id UUID,
  employee_uid TEXT,
  email TEXT NOT NULL,
  nom TEXT, prenom TEXT,
  role TEXT DEFAULT 'soigneur',
  statut TEXT DEFAULT 'invite',
  invite_token TEXT UNIQUE,
  invite_expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- 10. Planning employés
CREATE TABLE IF NOT EXISTS employee_plannings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id UUID NOT NULL REFERENCES structure_employees(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  heure_debut TIME,
  heure_fin TIME,
  notes TEXT
);
```

---

## 7. Priorités et dépendances

### Ordre d'implémentation recommandé

```
Phase 1 — Fondations (pas de dépendances)
├── ASSO01 : Profil association (inscription + BDD)
├── ASSO02 : Animaux association (statuts, fiches sans généalogie)
└── EMP01  : Gestion employés (invitation, rôles)

Phase 2 — Dépend de Phase 1
├── CERT01 : Certificat d'engagement (éleveur + association)
├── ASSO03 : Annonces association + feed dédié
└── EMP02  : Planning employés

Phase 3 — Dépend de Phase 1 + 2
├── PLAN01 : Chambres pension (création, configuration)
├── PLAN02 : Planning chenil — vue semaine
├── PLAN03 : Liaison RDV ↔ chambre automatique
└── ASSO04 : Candidatures adoption + dossier acquéreur

Phase 4 — Améliorations
├── CERT02 : Signature numérique (canvas in-app)
├── PLAN04 : Vue mois + taux d'occupation + rapports
├── ASSO05 : Familles d'accueil (réseau FA)
└── EMP03  : Affectation soigneurs → chambres
```

### Surfaces à implémenter pour chaque feature

| Code | App Flutter | Site Web | Admin |
|---|---|---|---|
| ASSO01 | ✅ inscription + profil | ✅ `/association/profil` | ✅ validation |
| ASSO02 | ✅ fiche animal asso | ✅ `/mes-animaux` (asso) | ✅ |
| ASSO03 | ✅ feed + annonce | ✅ `/annonces-association` | ✅ modération |
| ASSO04 | ✅ candidature | ✅ formulaire web | ✅ suivi |
| ASSO05 | ✅ gestion FA | ✅ | ❌ (non critique) |
| CERT01 | ✅ génération + envoi | ✅ génération + lien | ✅ |
| CERT02 | ✅ signature canvas | ✅ lien email token | ❌ |
| PLAN01 | ✅ config chambres | ✅ `/pension/chambres` | ✅ |
| PLAN02 | ✅ planning vue semaine | ✅ vue hôtel | ✅ stats |
| PLAN03 | ✅ auto RDV→chambre | ✅ | ❌ |
| PLAN04 | ✅ stats basiques | ✅ rapports complets | ✅ |
| EMP01 | ✅ invitation + accès | ✅ `/equipe` | ✅ |
| EMP02 | ✅ planning soigneurs | ✅ | ❌ |
| EMP03 | ✅ affectation | ✅ | ❌ |

---

## 8. Modèle économique — Abonnements, Boosts & Marketplace

### 8.1 Grilles tarifaires par profil

> Les prix et features de chaque plan doivent être modifiables via le panel admin sans déploiement. Stocker dans une table Supabase `plans_tarifaires` (voir §8.4).

**Éleveurs**

| Plan | Mensuel | Annuel | Différenciation clé |
|---|---|---|---|
| FREE | 0€ | 0€ | 3 annonces, 30j, renouvellement manuel |
| PRO | 15€/mois | 149€/an | 10 annonces, 45j, rappel J-5, 1 boost/mois inclus, 2 employés |
| PREMIUM | 25€/mois | 249€/an | Illimité, 60j, auto-renouvellement, 3 boosts/mois, module facturation |

Note : PREMIUM = `pro+` dans le code legacy — harmoniser vers `plan = 'premium'`.

**Vétérinaires**

| Plan | Mensuel | Annuel | Différenciation clé |
|---|---|---|---|
| FREE | 0€ | 0€ | Annuaire basique, lecture via token 72h |
| Avancé | 29€/mois | 290€/an | Accès lecture permanent, écriture carnet santé, rappels push |
| Clinique | 49€/mois | 490€/an | Multi-praticiens (5 max), export CSV logiciels vétérinaires |

**Soins para-médicaux** (ostéo/kiné, maréchal-ferrant)

| Plan | Mensuel | Annuel | Différenciation clé |
|---|---|---|---|
| FREE | 0€ | 0€ | Annuaire basique, token 72h |
| Essentiel | 19€/mois | 190€/an | Accès lecture permanent, ajout séances carnet santé |
| Pro | 29€/mois | 290€/an | Facturation clients, multi-intervenants (3 max), export CSV |

**Pet sitter**

| Plan | Mensuel | Annuel | Différenciation clé |
|---|---|---|---|
| FREE | 0€ | 0€ | Annuaire basique |
| Essentiel | 12€/mois | 120€/an | Registre entrées/sorties, journal séjour, contrats PDF |
| Pro | 19€/mois | 190€/an | Facturation clients, statistiques activité |

**Promeneur**

| Plan | Mensuel | Annuel | Différenciation clé |
|---|---|---|---|
| FREE | 0€ | 0€ | Annuaire basique |
| Essentiel | 9€/mois | 90€/an | Rapports sortie, gestion groupes, contrats PDF |
| Pro | 15€/mois | 150€/an | Facturation, abonnements clients (packs sorties) |

**Éducateur & comportementaliste**

| Plan | Mensuel | Annuel | Différenciation clé |
|---|---|---|---|
| FREE | 0€ | 0€ | Annuaire basique, messagerie |
| Essentiel | 19€/mois | 190€/an | Carnet comportemental, suivi séances, rapports PDF |
| Pro | 29€/mois | 290€/an | Programmes personnalisés, facturation, partage inter-pros |

**Photographe animalier**

| Plan | Mensuel | Annuel | Différenciation clé |
|---|---|---|---|
| FREE | 0€ | 0€ | Profil annuaire, 5 photos portfolio |
| Essentiel | 9€/mois | 90€/an | Portfolio illimité, mis en avant, statistiques profil |

**Association**

| Plan | Mensuel | Différenciation clé |
|---|---|---|
| GRATUIT | 0€ | Accès complet permanent, aucune restriction, jamais de paiement demandé |

Fonctionnalités abonnement communes : upgrade, downgrade, annulation immédiate ou en fin de période, renouvellement automatique, 14 jours d'essai offerts via parrainage.

---

### 8.2 Achats ponctuels (boosts & annonces)

> Les prix et descriptions ci-dessous doivent être éditables par un admin depuis le panel sans déploiement (table `produits_ponctuels`, voir §8.4).

| Produit | Prix | Durée | Description |
|---|---|---|---|
| Boost annonce | 1,99€ | 48h | Remontée temporaire en tête de feed |
| Mise à la une | 4,99€ | 7 jours | Badge + position prioritaire |
| Remontée annonce | 0,99€ | Instantané | Re-publication dans le feed |
| Annonce supplémentaire | 2,99€ | Selon plan | Quota au-delà du plan |
| Pack 3 boosts 48h | 4,99€ | 3 × 48h | Bundle (économie vs 3 × 1,99€) |

---

### 8.3 Marketplace & partenaires — régie publicitaire ciblée

> **Modèle régie pub, pas transactionnel · Pas de panier ni de paiement in-app · Le partenaire paie pour être visible auprès d'une audience qualifiée · Le clic redirige vers son site externe**

PetsMatch monétise son audience (éleveurs, propriétaires, pros) via des formats publicitaires ciblés par espèce, race, région et profil. Aucune infrastructure e-commerce requise en V1.

#### Segments partenaires

| Segment | Exemples | Ciblage principal |
|---|---|---|
| Créateurs artisanaux | Colliers sur mesure, jouets, vêtements, accessoires | Espèce, race, région |
| Alimentation & friandises | Marques premium, cru, compléments alimentaires | Espèce, race, âge animal |
| Boutiques généralistes | Animaleries en ligne, distributeurs | Espèce, région |
| Assurances animaux | Santevet, Dalma, Lovys, April | Espèce, âge, statut chiot/adulte |

Les assurances sont le segment à CPL le plus élevé du marché animalier français (15–40€ par lead qualifié). Priorité commerciale en V2.

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

Minimum de facturation : 500€/mois par partenaire bannière. Ciblage disponible : espèce, race, région, type de profil (éleveur/particulier/pro).

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

#### UI partenaire — dashboard

**Vue "Ma campagne"** (app + web, réservée partenaires connectés)
- Métriques temps réel : impressions, clics, leads du mois
- CTR moyen et CPL effectif
- Répartition par espèce et région
- Facture mensuelle téléchargeable (PDF)
- Modifier ciblage et budget

#### Vue Marketplace utilisateur (in-app)

Section dédiée accessible depuis le menu principal.

**Architecture de la vue :**
- Header : "Nos partenaires sélectionnés" + filtre espèce (chien/chat/équidé/autre)
- Grille partenaires : carte logo + nom + catégorie + lien
- Section "Assurances" : cards dédiées avec CTA "Obtenir un devis"
- Badge "Partenaire vérifié PetsMatch" sur tous les listings
- Pas de publicité intrusive dans les écrans métier (carnet santé, registre) sauf bannière discrète bas de page

Règle éditoriale : tous les partenaires sont vérifiés manuellement avant activation (SIRET valide, site légitime, produits conformes réglementation animaux).

#### Tracking & facturation automatique

- Impressions comptées côté serveur (Cloud Function), pas côté client (anti-fraude, ad-blockers non impactants sur le CPM)
- Facture Stripe générée automatiquement en fin de mois selon les events réels
- Plafond de dépenses mensuel configurable par partenaire
- Rapport PDF mensuel envoyé automatiquement au partenaire

#### Conformité RGPD

- Aucune donnée personnelle utilisateur transmise aux partenaires
- Le ciblage est contextuel (espèce, région) et non nominatif
- Mentions légales "Publicité" affichées sur tous les formats bannière
- Opt-out publicité disponible dans les paramètres utilisateur (impact : bannières désactivées, listing annuaire toujours visible)

#### Évolutions V2+

- Ciblage comportemental avancé (historique carnet santé, races possédées)
- Self-service : onboarding partenaire autonome sans validation manuelle
- Intégration Google Ad Manager pour partenaires > 2 000€/mois de budget
- Affiliation créateurs artisanaux (commission sur ventes trackées par UTM)
- Programme "Partenaire éleveur" : éleveur recommande une marque → reçoit des boosts en échange

---

### 8.4 Tables Supabase — modèle économique

```sql
-- Plans tarifaires (éditables depuis l'admin sans déploiement)
CREATE TABLE plans_tarifaires (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profil_type TEXT NOT NULL,       -- eleveur/veterinaire/pension/education/petsitter/promeneur/photographe/para_medical
  plan_code TEXT NOT NULL,         -- free/essentiel/pro/premium/avance/clinique
  label TEXT NOT NULL,
  prix_mensuel NUMERIC DEFAULT 0,
  prix_annuel NUMERIC DEFAULT 0,
  features JSONB,                  -- liste des features incluses (pour affichage)
  actif BOOLEAN DEFAULT true,
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(profil_type, plan_code)
);

-- Produits ponctuels (boosts, éditables depuis l'admin)
CREATE TABLE produits_ponctuels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,       -- boost_48h/mise_une/remontee/annonce_sup/pack_3boosts
  label TEXT NOT NULL,
  prix NUMERIC NOT NULL,
  duree_heures INTEGER,            -- null = instantané
  description TEXT,
  actif BOOLEAN DEFAULT true,
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Abonnements actifs
CREATE TABLE abonnements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid TEXT NOT NULL,
  profil_type TEXT NOT NULL,
  plan_code TEXT NOT NULL,
  stripe_subscription_id TEXT,
  stripe_customer_id TEXT,
  periodicite TEXT DEFAULT 'mensuel',  -- mensuel/annuel
  statut TEXT DEFAULT 'actif',         -- actif/grace/lecture_seule/annule/archive
  date_debut TIMESTAMPTZ DEFAULT now(),
  date_fin TIMESTAMPTZ,
  date_fin_grace TIMESTAMPTZ,
  essai_gratuit BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Achats ponctuels (boosts)
CREATE TABLE achats_ponctuels (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid TEXT NOT NULL,
  produit_id UUID NOT NULL REFERENCES produits_ponctuels(id),
  annonce_id TEXT,
  stripe_payment_intent_id TEXT,
  statut TEXT DEFAULT 'paye',      -- paye/rembourse/echoue
  date_achat TIMESTAMPTZ DEFAULT now(),
  date_expiration TIMESTAMPTZ
);

-- Partenaires marketplace
CREATE TABLE marketplace_partners (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT,
  nom TEXT NOT NULL,
  logo_url TEXT,
  site_url TEXT,
  description TEXT,
  categorie TEXT,                  -- artisan/alimentation/boutique/assurance
  especes_cibles TEXT[],
  regions TEXT[],
  plan TEXT DEFAULT 'starter',     -- starter/visible/premium
  statut TEXT DEFAULT 'en_attente', -- en_attente/actif/suspendu
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Campagnes publicitaires
CREATE TABLE marketplace_ads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  partner_id UUID NOT NULL REFERENCES marketplace_partners(id),
  type TEXT NOT NULL,              -- listing/banniere/cpl
  placement TEXT,
  budget_mensuel NUMERIC,
  cpm NUMERIC,
  cpl NUMERIC,
  especes_cibles TEXT[],
  regions TEXT[],
  date_debut DATE,
  date_fin DATE,
  statut TEXT DEFAULT 'actif',     -- actif/pause/termine
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Events tracking (impressions, clics, leads)
CREATE TABLE marketplace_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ad_id UUID REFERENCES marketplace_ads(id),
  partner_id UUID REFERENCES marketplace_partners(id),
  user_id TEXT,
  event_type TEXT NOT NULL,        -- impression/clic/lead
  espece TEXT,
  race TEXT,
  region TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
```

RLS : `marketplace_partners` et `marketplace_ads` accessibles uniquement par le partenaire propriétaire et les admins. `marketplace_events` : insertion côté client, lecture réservée admin + partenaire propriétaire.

---

---

## 9. Validation automatique & Badges de confiance

> Surfaces : **App Flutter (Android + iOS) + Site Web Next.js + Panel Admin**

### 9.1 Validation automatique à l'inscription

Lors du dépôt de dossier (éleveur ou professionnel), des contrôles automatiques bloquent immédiatement les données manifestement incorrectes avant d'envoyer le dossier en queue admin.

#### Contrôles bloquants (rejet immédiat)

| Champ | Règle | Message utilisateur |
|---|---|---|
| SIRET | Introuvable via API `recherche-entreprises.api.gouv.fr` | "Ce numéro SIRET/SIREN est introuvable" |
| SIRET | Entreprise fermée (`etat_administratif = 'F'`) | "Cette entreprise est fermée ou radiée" |
| Nom entreprise | Nom déclaré ne correspond pas au nom API (comparaison normalisée) | "Le nom ne correspond pas au SIRET (trouvé : X) — www.petsmatch.com/contact" |
| RNA | Format non conforme (`W` + 9 chiffres) | "Format RNA invalide" |
| SIRET/SIREN | Format non conforme (9 ou 14 chiffres, chiffres uniquement) | "Format invalide" |

**Comportement si API indisponible** : le dossier passe en `en_attente` pour vérification manuelle admin. Ne jamais bloquer à cause d'une API tierce en panne.

#### ACACED (éleveurs)

- Le numéro ACACED n'est **pas standardisé** au niveau national → **format libre**, vérification manuelle uniquement.
- Champ optionnel à l'inscription (peut être fourni après).
- L'admin vérifie la conformité lors de la revue du dossier.
- Récapitulatif visible dans la fiche admin avec le document uploadé.

#### KBIS

- **Optionnel** — le SIRET vérifié par API est suffisant pour la validation.
- Si uploadé, constitue un « plus » visible dans le dossier admin et contribue au badge Premium.
- L'upload est toujours possible après l'inscription depuis le profil.

#### Code APE

- L'API retourne le code APE/NAF de l'entreprise.
- Un code non animal-related (hors `014x`, `0162Z`, `9609Z`, `7500Z`) est visible dans le dossier admin avec un indicateur visuel.
- **Ne génère pas de rejet automatique** (trop de faux positifs) — décision admin.

### 9.2 Flow de validation admin (VALID04)

```
Inscription éleveur/pro
    ↓
Checks automatiques
    ├─ ❌ Erreur → affichage immédiat dans le formulaire, dossier non créé
    └─ ✅ OK → statut_pro = 'en_attente', dossier créé dans Supabase
          ↓
     Panel admin → onglet Dossiers
          ├─ Sous-onglet "En attente" — cartes avec SIRET + ACACED + documents
          │       ├─ "✅ Valider" → statut_pro = 'actif', is_validate = true
          │       └─ "❌ Refuser" → motif obligatoire → statut_pro = 'refuse', rejection_reason
          └─ Sous-onglet "Rejetés" — cartes avec motif de refus
                  └─ "↩ Reconsidérer" → retour en 'en_attente'
```

**Page utilisateur `/en-attente-validation`** :
- Statut `en_attente` → message d'attente (48h ouvrées)
- Statut `refuse` → motif visible + lien vers `/contact`
- Statut `actif` → redirection vers accueil

**Email de rejet** : à implémenter dès qu'un provider email est configuré (Resend, SendGrid ou Supabase Edge Function). Le motif + lien `www.petsmatch.com/contact` doit apparaître dans l'email.

### 9.3 Badges de confiance

Trois niveaux visibles sur les fiches pro/éleveur, les cartes annonces et la liste des élevages.

| Badge | Code | Critères | Couleur | Icône |
|---|---|---|---|---|
| Aucun | `none` | Compte en attente ou non-validé | — | — |
| **Vérifié** | `verifie` | `statut_pro = 'actif'` + SIRET renseigné | Bleu `#2563eb` | ✓ |
| **Premium** | `premium` | `is_premium = true` (admin ou abonnement actif) | Or `#d97706` | ★ |

**Composant** : `VerificationBadge` (`src/components/VerificationBadge.tsx`) — tailles `sm` / `md` / `lg`, tooltip informatif.

**Fonction utilitaire** : `getBadgeLevel({ statutPro, siret, isPremium })` — calcul côté client, pas de requête supplémentaire.

#### Surfaces d'affichage

| Surface | Endroit | Badge |
|---|---|---|
| Web — liste élevages | Titre de la card | sm |
| Web — fiche pro | À côté du nom | md |
| Web — liste annonces | Card annonce (batch fetch eleveur) | sm |
| Web — détail annonce | Section éleveur | sm |
| App Flutter — liste élevages | Card éleveur (`_EleveurCard`) | sm |
| App Flutter — liste services | Card professionnel (`_ProCard`) | sm |
| App Flutter — feed annonces | Badge row sur la card | sm |
| Admin — ProfileModal | Section "Statut professionnel" | badge + bouton toggle |

**Composant Flutter** : `lib/widgets/verification_badge.dart` — `VerificationBadge` widget + `getVerificationLevel()` helper + `VerificationLevel` enum.

#### Attribution Premium

- **Temporaire (MVP)** : toggle manuel admin dans `ProfileModal` → `is_premium = true/false` dans `users`
- **Définitif** : Stripe webhook → `checkout.session.completed` avec `plan = 'premium'` → `is_premium = true` automatiquement
- Les **associations** ont un badge "Association" distinct (à définir, elles sont gratuites et validées manuellement)

#### SQL requis

```sql
-- Colonne is_premium (si pas encore ajoutée)
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS is_premium BOOLEAN DEFAULT false;

-- Table formulaire de contact
CREATE TABLE IF NOT EXISTS public.contact_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  email TEXT NOT NULL,
  subject TEXT,
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.contact_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can submit contact" ON public.contact_messages
  FOR INSERT WITH CHECK (true);
CREATE POLICY "Admins can read contacts" ON public.contact_messages
  FOR SELECT USING (auth.role() = 'service_role');
```

### 9.4 Vérification d'identité (CNI)

**Décision actuelle : ne pas implémenter en interne.**

Raisons :
- RGPD : stockage de CNI nécessite base légale explicite, durée limitée, chiffrement renforcé — complexité non justifiée au stade actuel
- Coût : services tiers (Stripe Identity, Ubble, Onfido) facturent ~1,50–2,50€/vérification
- Le SIRET (auto-entrepreneur au nom du gérant) constitue déjà une vérification indirecte d'identité

**Quand l'activer** : dès que les revenus abonnements couvrent le coût (~1,50€ × nb_éleveurs_par_mois).  
**Service recommandé** : Ubble (FR, RGPD natif) ou Stripe Identity (intégration simple si déjà sur Stripe).  
**Impact badge** : une vérification CNI validée passerait le badge de `verifie` à `premium` automatiquement.

### 9.5 Page de contact publique (`/contact`)

URL : `www.petsmatch.com/contact`

Champs :
- Nom / Prénom (obligatoire)
- Email (obligatoire)
- Objet : liste `['Réclamation dossier refusé', 'Problème technique', 'Signalement abusif', 'Question sur mon compte', 'Autre']`
- Message (obligatoire)

Stockage : table `contact_messages` (Supabase, RLS insert public / lecture service_role).  
Fallback : `mailto:support@petsmatch.com` affiché si Supabase indisponible.  
Lien dans les emails/messages de rejet : `www.petsmatch.com/contact`

---

---

## 9bis. Signature électronique — Contrats & Adoption (SIGN01–SIGN04)

> Collaboration style **YouSign** (service FR, certifié eIDAS, RGPD natif).  
> Concerne : éleveurs (contrat vente/réservation/saillie), associations (contrat adoption), pensions (contrat hébergement), vétérinaires (consentement soin).

### 9bis.1 Périmètre

| Profil | Types de contrats | Signature requise |
|--------|------------------|-------------------|
| Éleveur | Vente, réservation, saillie | Éleveur + acquéreur |
| Association | Adoption, FA, parrainage | Association + adoptant(s) |
| Pension | Hébergement, contrat de garde | Pension + propriétaire |
| Vétérinaire | Consentement soins | Vétérinaire + propriétaire |

### 9bis.2 Co-adoption (spécifique association)

Pour les dossiers d'adoption en couple ou en famille, prévoir **plusieurs signataires** sur le même contrat :
- Ajout de co-adoptant(s) : nom, prénom, email, lien (conjoint, parent, enfant majeur…)
- Chaque signataire reçoit un email avec lien de signature indépendant
- Contrat finalisé uniquement quand **tous les signataires** ont signé
- Statuts : `en_attente_signatures` → `partiellement_signé` → `signé` → `archivé`
- PDF final avec toutes les signatures horodatées

### 9bis.3 Intégration technique

**Option A — YouSign API** *(recommandée)*
- API REST, certifiée eIDAS niveau simple et avancé
- ~0,50–1€/signature selon volume
- SDK JS/Dart disponible
- Webhook sur completion → stocker PDF signé dans Firebase Storage

**Option B — Signature canvas in-app** *(sans coût, valeur légale limitée)*
- Déjà prévu dans les specs Certificat d'Engagement (CERT02)
- Suffisant pour contrats non-litigieux (réservation, hébergement)
- Pas de valeur légale eIDAS — risque si contesté

**Recommandation** : Option B pour la V1 (gratuit, déjà dans le périmètre CERT02), Option A pour la V2 quand les revenus le permettent.

### 9bis.4 Codes feature

| Code | Feature |
|------|---------|
| SIGN01 | Intégration YouSign API (V2) |
| SIGN02 | Multi-signataires / co-adoption |
| SIGN03 | Webhook completion → archivage PDF |
| SIGN04 | Portail signatures pour les pros (tableau de bord statuts) |

**Dépendance** : SIGN01 nécessite CERT02 (signature canvas) comme base.

---

## 10. Emails transactionnels — Abonnements & Relances

> **Prérequis** : choisir l'hébergement + domaine (`petsmatch.com`) avant d'implémenter.  
> Les emails partiront depuis `contact@petsmatch.com` ou `noreply@petsmatch.com`.  
> **Stack retenue** : nodemailer via Firebase Cloud Functions + SMTP de l'hébergeur (à configurer dans `firebase functions:config:set email.host=... email.user=... email.pass=...`).  
> Stripe envoie déjà automatiquement les reçus/factures — ces emails sont des communications métier complémentaires.

### 10.1 PAY01 — Confirmation d'activation d'abonnement

**Déclencheur** : appel à `/api/stripe/activate` (succès) — écriture dans collection Firestore `mail`  
**Destinataire** : email du compte Firebase Auth  
**Objet** : `🎉 Votre abonnement PetsMatch [Pro/Premium] est activé`  
**Contenu** :
- Nom du plan + prix
- Liste des fonctionnalités débloquées
- Date de prochain renouvellement
- Lien vers le portail de gestion (`/abonnement`)
- Lien résiliation via Stripe Portal

**Implémentation** :
```js
// functions/email.js — Cloud Function sendTransactionalEmail (callable)
// Lit credentials depuis functions.config().email
// Écrit dans Firestore `mail` collection (Trigger Email Extension) OU nodemailer direct
```

### 10.2 PAY02 — Rappel J-7 avant fin d'abonnement

**Déclencheur** : Cloud Function schedulée quotidiennement à 8h — vérifie `abonnements` avec `date_fin` entre aujourd'hui et +7 jours ET `statut = 'actif'`  
**Objet** : `⏰ Votre abonnement PetsMatch expire dans 7 jours`  
**Contenu** : rappel du plan, date d'expiration, bouton "Gérer mon abonnement"  
**Note** : Ne pas envoyer si `cancel_at_period_end = false` (renouvellement auto = pas besoin de rappel)

### 10.3 PAY03 — Rappel J-1 avant fin d'abonnement

**Déclencheur** : même Cloud Function schedulée, condition `date_fin` entre demain et +1 jour  
**Objet** : `⚠️ Dernier jour — votre abonnement PetsMatch expire demain`

### 10.4 PAY04 — Email post-résiliation

**Déclencheur** : webhook Stripe `customer.subscription.deleted` → écriture dans Firestore `mail`  
**Objet** : `Votre abonnement PetsMatch a été résilié`  
**Contenu** : confirmation résiliation, date d'accès jusqu'au, lien pour se réabonner

### 10.5 Codes feature & dépendances

| Code | Feature | Dépendance |
|------|---------|------------|
| PAY01 | Email confirmation activation | Hébergement + domaine email |
| PAY02 | Rappel J-7 | PAY01 (même stack) |
| PAY03 | Rappel J-1 | PAY01 |
| PAY04 | Email post-résiliation | PAY01 |
| HOST01 | Choix hébergement Next.js | — |
| HOST02 | Configuration domaine petsmatch.com | HOST01 |
| HOST03 | Mode accès privé pendant tests (middleware Next.js) | HOST01 |
| HOST04 | Configuration email SMTP sur hébergeur | HOST02 |

---

## 11. Hébergement & Infrastructure

> **Décision en attente** : passage de `.fr` à `.com` en cours.

### 11.1 Recommandation hébergement Next.js : Vercel

**Vercel** est l'hébergeur de référence pour Next.js (créé par la même équipe) :

| Critère | Vercel | Alternative OVH/VPS |
|---------|--------|---------------------|
| Compatibilité Next.js | Native (100% features) | Partielle (config manuelle) |
| API Routes / Stripe Webhooks | ✅ Serverless natif | ✅ mais config nginx |
| Variables d'environnement | Interface simple | Fichier `.env` sur serveur |
| Preview par branche git | ✅ Automatique | ❌ |
| Déploiement | Push git → live en 1 min | CI/CD à configurer |
| Certificat SSL | ✅ Auto Let's Encrypt | ✅ Auto Let's Encrypt |
| Plan gratuit | Hobby (suffisant pour tests) | Non |
| Passage en prod | Pro ~20$/mois | VPS ~10-30€/mois |
| Logs temps réel | ✅ | Via SSH |

**Recommandation** : Vercel Hobby (gratuit) pour les tests, Vercel Pro (~20$/mois) en production.

### 11.1b Comparatif tarifs production

> **Décision à prendre ce weekend avec les collaborateurs.**

| Hébergeur | Prix prod | Par membre | Bande passante | Next.js |
|-----------|-----------|------------|----------------|---------|
| **Vercel Pro** | 20$/mois | +20$/membre | 1 TB | ✅ Native |
| **Netlify Pro** | ~19$/mois | +19$/membre | 1 TB | ✅ Bonne |
| **Cloudflare Pages** | 0-20$/mois | Inclus | **Illimitée** | ⚠️ Adapter requis |
| **Railway Pro** | ~20$/mois | Inclus | 100 GB | ✅ Bonne |
| **Render** | ~7$/mois | Inclus | 100 GB | ✅ Bonne |

**Points clés :**
- Vercel & Netlify : modèle **par membre** — 1 seul compte suffit pour déployer (les autres travaillent via GitHub)
- Cloudflare : bande passante illimitée même gratuit, mais Next.js App Router nécessite un adaptateur (risque technique)
- **Stratégie recommandée** : Vercel Hobby gratuit pour les tests → Vercel Pro 20$/mois au lancement (1 membre) → rentabilisé dès le 1er abonné Pro (15€/mois)
- Compte à créer par **Sotekkk** (GitHub) — Angelique ajoutée comme membre si passage Pro

### 11.2 Accès privé pendant la phase de test (HOST03)

**Oui, c'est possible et simple.** Deux approches :

**Option A — Middleware Next.js avec mot de passe** *(recommandée, zéro coût)*
```ts
// middleware.ts à la racine du projet website/
// Vérifie un cookie "beta_access" → si absent, redirige vers /beta-login
// /beta-login : formulaire avec mot de passe → set cookie → redirect
// Le mot de passe est dans NEXT_PUBLIC_BETA_PASSWORD (env var Vercel)
```
- Avantage : fonctionne sur n'importe quel hébergeur, gratuit
- On partage juste un mot de passe aux testeurs
- Whitelister les routes publiques : `/api/stripe/webhook` (doit rester accessible à Stripe)

**Option B — Vercel Password Protection** *(Pro plan uniquement, 20$/mois)*
- Activé en 1 clic dans le dashboard Vercel
- Pas de code à écrire

**→ On part sur l'Option A** (middleware) : gratuit, fonctionne dès maintenant.

### 11.3 To-do hébergement (HOST01–HOST04)

- [ ] **HOST01** Créer compte Vercel + connecter repo GitHub `Sotekkk/PetsMatch`
- [ ] **HOST02** Acheter `petsmatch.com` + configurer DNS sur Vercel
- [ ] **HOST03** Implémenter middleware accès privé beta (mot de passe)
- [ ] **HOST04** Configurer SMTP hébergeur pour emails transactionnels
- [ ] Migrer variables `.env.local` → Variables d'environnement Vercel (dashboard)
- [ ] Vérifier webhook Stripe pointe sur `https://petsmatch.com/api/stripe/webhook`

---

*Document maintenu par l'équipe PetsMatch — toute modification fonctionnelle doit être reportée ici avant implémentation.*
