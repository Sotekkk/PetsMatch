# Specs PetsMatch — Fonctionnalités à implémenter
> Dernière mise à jour : 2026-06-10  
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

## 4. Planning Chenil / Hôtel

### 4.1 Cible

- **Pension** (gardiennage + hébergement)
- **Association** (si elles disposent d'un chenil ou d'une chatterie)

### 4.2 Concept

Vue type **hôtel** : les lignes sont les chambres/boxes, les colonnes sont les jours. Chaque cellule représente l'état d'une chambre à une date donnée.

```
           Lun 9  Mar 10  Mer 11  Jeu 12  Ven 13
Box 1      [REF]  [OCCU]  [OCCU]  [NET]   [LIBRE]
Box 2      [LIBRE][LIBRE] [REF]   [REF]   [OCCU]
Suite A    [OCCU] [OCCU]  [LIBRE] [LIBRE] [LIBRE]
Collectif  [OCCU] [OCCU]  [OCCU]  [NET]   [LIBRE]
```

**États (code couleur) :**
| État | Couleur | Description |
|---|---|---|
| `libre` | Vert | Chambre disponible |
| `reserve` | Bleu | Réservé pour un animal (RDV confirme) |
| `occupe` | Orange | Animal présent |
| `nettoyage` | Gris | En cours de nettoyage/désinfection |
| `maintenance` | Rouge | Hors service |

### 4.3 Gestion des chambres/boxes

Chaque chambre a :
```
Nom / numéro          (ex: "Box 1", "Suite A", "Chatière 3")
Type                  (individuel / collectif / suite / enclos extérieur)
Espèces acceptées     (chien / chat / lapin / NAC…)
Capacité              (1 par défaut, plusieurs pour collectif)
Taille                (S/M/L/XL pour chiens)
Équipements           (caméra, climatisation, accès jardin…)
Photo                 (optionnel)
Notes                 (règles particulières)
Actif / Inactif       (hors service temporaire)
```

### 4.4 Réservations et liaison avec RDV

- Quand un RDV pension est **confirmé** avec dates d'arrivée + départ :
  - Proposition automatique d'affecter une chambre libre
  - Ou affectation manuelle depuis le planning
- Le planning se met à jour automatiquement

### 4.5 Vue Planning (interface)

**Vue Semaine (défaut) :**
- Navigation semaine par semaine (← →)
- Scroll horizontal si nombreuses chambres
- Clic sur une cellule :
  - Si `libre` → créer une réservation
  - Si `réservé/occupé` → voir fiche animal + propriétaire
  - Si `nettoyage` → marquer comme prêt

**Vue Mois :**
- Vue d'ensemble : taux de remplissage par jour (barre % colorée)
- Clic sur un jour → zoom vue journée

**Vue Liste des arrivées/départs du jour :**
- Animals qui arrivent aujourd'hui
- Animals qui partent aujourd'hui
- Chambres à préparer/nettoyer

### 4.6 Nettoyage et maintenance

- Quand un animal part (check-out) → la chambre passe automatiquement en `nettoyage`
- Le soigneur marque "Nettoyage terminé" → passe en `libre`
- Possible d'assigner le nettoyage à un employé (voir §5)
- Rappel si chambre en nettoyage > 2h (configurable)

### 4.7 Rapport d'occupation

- Taux de remplissage moyen (semaine / mois / trimestre)
- Chambres les plus/moins demandées
- Espèces les plus accueillies
- Revenus estimés (si tarifs renseignés par chambre)
- Export CSV (web uniquement)

### 4.8 Schéma BDD

```sql
-- Chambres / boxes
CREATE TABLE chambres_pension (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid TEXT NOT NULL,           -- UID du pro (pension ou association)
  pro_profile_id UUID,
  nom TEXT NOT NULL,               -- "Box 1", "Suite A"
  type TEXT DEFAULT 'individuel',  -- individuel/collectif/suite/enclos
  especes_acceptees TEXT[],        -- ['chien','chat']
  capacite INTEGER DEFAULT 1,
  taille TEXT,                     -- S/M/L/XL
  equipements TEXT[],
  photo_url TEXT,
  notes TEXT,
  tarif_nuit NUMERIC,              -- optionnel
  actif BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Réservations / occupation
CREATE TABLE reservations_chenil (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chambre_id UUID NOT NULL REFERENCES chambres_pension(id) ON DELETE CASCADE,
  rdv_id UUID REFERENCES rdv(id),           -- si lié à un RDV
  animal_id TEXT,
  proprietaire_uid TEXT,
  date_debut DATE NOT NULL,
  date_fin DATE NOT NULL,
  statut TEXT DEFAULT 'reserve',  -- reserve/occupe/nettoyage/maintenance
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  CONSTRAINT no_overlap EXCLUDE USING gist (
    chambre_id WITH =,
    daterange(date_debut, date_fin, '[)') WITH &&
  )
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

*Document maintenu par l'équipe PetsMatch — toute modification fonctionnelle doit être reportée ici avant implémentation.*
