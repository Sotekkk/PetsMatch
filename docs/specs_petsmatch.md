# Specs PetsMatch — Fonctionnalités à implémenter
> Dernière mise à jour : 2026-06-17  
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

**Codes feature :**
- **CERT01** ✅ En cours — Génération + envoi (web)
- **CERT02** 🔜 V2 — Signature numérique canvas (app + web)

**V1 — CERT01 (implémenté)**

*Web Next.js :*
- Page `/elevage/certificat-engagement` : liste des certificats + création
- Formulaire pré-rempli (profil cédant + sélection animal depuis Supabase)
- PDF généré via `window.print()` + CSS print (pas de dépendance supplémentaire)
- Token de signature unique (UUID) stocké en DB
- Lien de signature `/certificat/[token]` partageable manuellement (email auto après HOST02)
- Page acquéreur `/certificat/[token]` : lecture + bouton Signer / Refuser
- Statuts : `envoye` → `lu` → `signe` / `refuse`
- Gating : Pro + Premium uniquement (éleveurs)

*App Flutter :*
- Bouton "Certificat d'engagement" dans fiche animal (statut disponible) — CERT01 app à faire

**V2 — CERT02**
- Signature canvas in-app (Flutter `Signature` package)
- Signature web : canvas HTML5 + sauvegarde image base64
- PDF final avec signature intégrée
- Dépendance SIGN01 (YouSign) pour valeur légale eIDAS

**Table Supabase :** voir migration `supabase/migration_certificats_engagement.sql`

**Flux :**
```
Éleveur → Génère certificat → Sélectionne animal + saisit acquéreur
→ PDF généré + token créé en DB
→ Partage lien /certificat/[token] à l'acquéreur (email auto après HOST02)
→ Acquéreur ouvre le lien → lit le certificat → clique Signer (après J+7 pour chien/chat)
→ Statut = signé → PDF téléchargeable pour les deux parties
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

### 9.0 Statut d'implémentation (2026-06-17)

| Feature | Code | Statut | Notes |
|---|---|---|---|
| Contrôle format SIRET (14 chiffres, pas de doublons) | A12 | ✅ App Flutter | Dans `profil_eleveur_edit._save()` + affiché dans `verification_detail.dart` |
| Détection annonces suspectes (prix + mots-clés) | A13 | ✅ App Flutter | Dans `create_annonce_page.dart`, table `annonces.is_suspect` / `suspect_reasons` |
| Onglet "Annonces" dans panel admin | A13 | ✅ App Flutter | `annonces_admin.dart` — 3 onglets : Suspectes / Toutes / Suspendues |
| Particuliers auto-validés à l'inscription | — | ✅ App Flutter + Web | `verifemail.dart` + `ValidationGuard.tsx` |
| Backfill CGU anciens comptes app | RGPD01 | ✅ Web | Silencieux dans `ValidationGuard.tsx` |
| Vérification SIRET via API `recherche-entreprises.api.gouv.fr` | 9.1 | 🔜 À faire | Nécessite Cloud Function / Edge Function |
| Badges de confiance dans les cards | 9.3 | ✅ Web | `VerificationBadge.tsx` + `getBadgeLevel()` |

**SQL à appliquer (non encore exécuté) :**
```sql
ALTER TABLE annonces ADD COLUMN IF NOT EXISTS is_suspect BOOLEAN DEFAULT false;
ALTER TABLE annonces ADD COLUMN IF NOT EXISTS suspect_reasons JSONB DEFAULT '[]';
UPDATE users SET cgu_accepted_at = created_at WHERE cgu_accepted_at IS NULL;
```

---

### 9.1 Validation automatique à l'inscription

Lors du dépôt de dossier (éleveur ou professionnel), des contrôles automatiques bloquent immédiatement les données manifestement incorrectes avant d'envoyer le dossier en queue admin.

#### Contrôles bloquants (rejet immédiat)

| Champ | Règle | Message utilisateur |
|---|---|---|
| SIRET | Introuvable via API `recherche-entreprises.api.gouv.fr` | "Ce numéro SIRET/SIREN est introuvable" |
| SIRET | Entreprise fermée (`etat_administratif = 'F'`) | "Cette entreprise est fermée ou radiée" |
| Nom entreprise | Nom déclaré ne correspond pas au nom API (comparaison normalisée) | "Le nom ne correspond pas au SIRET (trouvé : X) — www.petsmatchapp.com/contact" |
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

**Email de rejet** : à implémenter dès qu'un provider email est configuré (Resend, SendGrid ou Supabase Edge Function). Le motif + lien `www.petsmatchapp.com/contact` doit apparaître dans l'email.

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

URL : `www.petsmatchapp.com/contact`

Champs :
- Nom / Prénom (obligatoire)
- Email (obligatoire)
- Objet : liste `['Réclamation dossier refusé', 'Problème technique', 'Signalement abusif', 'Question sur mon compte', 'Autre']`
- Message (obligatoire)

Stockage : table `contact_messages` (Supabase, RLS insert public / lecture service_role).  
Fallback : `mailto:support@petsmatch.com` affiché si Supabase indisponible.  
Lien dans les emails/messages de rejet : `www.petsmatchapp.com/contact`

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
✅ **IMPLÉMENTÉ V1 (2026-06-19)**
- `lib/contrat-vente.ts` (web) : contrat 8 articles + attestation de cession adaptés par espèce, champs éditables `contenteditable`, deux pads de signature `signature_pad@4.1.7` (canvas HTML5)
- Bouton **"✅ Finaliser et enregistrer"** : injecte les signatures dans le HTML, upload dans Supabase Storage bucket `contrats`, met à jour `animaux.cession_contrat_url`, postMessage vers la modale parente
- `CessionModal.tsx` (web) : écoute `postMessage` type `contract_signed`, affiche statut "Contrat signé numériquement", lien de consultation
- `contrat_pdf.dart` (Flutter) : génère un PDF 2 pages (contrat + attestation) via package `pdf`/`printing` avec blocs de signature à remplir manuellement — pour le workflow impression + scan
- Sauts de page corrigés : `break-inside: avoid` sur chaque article, signatures, bannières
- Copie double : bannière "2 exemplaires originaux" + case à cocher "J'ai reçu mon exemplaire original" pour chaque partie
- Bouton "🖨️🖨️ Imprimer 2 exemplaires" dans la toolbar web
- Suffisant pour contrats non-litigieux (vente animaux) — pas de valeur légale eIDAS — risque si contesté

### 9bis.5 Architecture cible — Documents liés à l'animal (V1.5)

> **Décision 2026-06-19** : refonte de la gestion des documents pour centraliser dans la section Administratif et lier chaque document à l'animal.

**Principe** : tous les documents (contrats, certificats) sont créés depuis **Administratif**, stockés dans Supabase Storage et liés à l'animal via la table `documents_animaux`. Ils apparaissent dans la fiche animal et suivent l'animal lors d'une cession.

**Table `documents_animaux` :**
```sql
CREATE TABLE documents_animaux (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  animal_id   TEXT REFERENCES animaux(id) ON DELETE CASCADE,
  uid_eleveur TEXT NOT NULL,
  type        TEXT NOT NULL,  -- contrat_vente | contrat_reservation | certificat_engagement | certificat_cession
  url         TEXT,           -- Supabase Storage bucket 'contrats'
  statut      TEXT DEFAULT 'brouillon',  -- brouillon | signe | archive
  signe_le    TIMESTAMPTZ,
  metadata    JSONB,          -- { acquereur_nom, acquereur_email, prix, date_cession, ... }
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

**Flux par type de document :**

| Document | Créé depuis | Lié à | Requis avant |
|----------|------------|-------|--------------|
| Certificat d'engagement | Administratif > Certificats | Animal | Cession (7j délai chien/chat) |
| Contrat de réservation | Administratif > Contrats | Animal | Réservation |
| Contrat de vente | Administratif > Contrats | Animal | Cession |
| Certificat de cession | Administratif > Certificats | Animal | Cession (attestation finale) |

**Workflow :**
1. Éleveur ouvre Administratif > Contrats/Certificats
2. Sélectionne l'animal → pré-remplissage automatique (nom, espèce, race, puce, date naissance)
3. Saisit les infos acquéreur + prix + date
4. Signature électronique canvas (ou impression + scan)
5. Document stocké Supabase + lié à l'animal (`documents_animaux`)
6. Visible dans la fiche animal onglet Documents
7. Lors de la cession → le système trouve le contrat de vente signé lié à l'animal → l'attache automatiquement

**Codes feature :**

| Code | Feature | Surface | Priorité |
|------|---------|---------|---------|
| DOC01 | Table `documents_animaux` + migration SQL | Backend | ✅ Livré 2026-06-19 |
| DOC02 | Page Contrats dynamiques (sélecteur animal + génération PDF/web) | App + Web | ✅ Livré 2026-06-19 |
| DOC03 | Certificat d'engagement avec signature électronique | App + Web | ✅ Existant (`certificats_engagement`) |
| DOC04 | Fiche animal onglet Documents — affichage docs liés | App + Web | ✅ Livré 2026-06-19 |
| DOC05 | Cession — attach auto du contrat de vente signé existant | App + Web | ✅ Livré 2026-06-19 |
| DOC06 | Certificat de cession (attestation de transfert) | App + Web | ✅ Livré 2026-06-19 |

**Notes DOC01-DOC02 :**
- Web `/elevage/contrat/page.tsx` : migré Firestore → Supabase `documents_animaux`, sélecteur animal, génération dynamique via `generateContratHTML`, types vente/reservation/cession
- App `contrat_reservation.dart` : migré Firestore → Supabase `documents_animaux`, sélecteur animal, génération PDF via `genererContratPDF`, recherche acquéreur PetsMatch
- **MIGRATION SQL À APPLIQUER dans Supabase** : `supabase/migration_documents_animaux.sql`

### 9bis.5 Intégration YouSign — Modèle économique & Quotas (SIGN01)

> **Décision 2026-06-19** : intégrer YouSign pour les 3 contrats (vente, réservation, engagement). Accès conditionné au plan Premium, avec quota mensuel inclus et facturation à l'unité au-delà.

#### Pricing YouSign (coût PetsMatch)
- YouSign **Plan Standard** : ~15€/mois pour 20 enveloppes
- Au-delà : ~0,75€/enveloppe (une enveloppe = 1 contrat avec N signataires)
- Coût moyen estimé : **0,75€/contrat** pour PetsMatch

#### Tarification utilisateur
| Profil | Contrats YouSign inclus | Au-delà |
|--------|------------------------|---------|
| **Gratuit** | ❌ 0 — accès refusé | — |
| **Premium éleveur** | 3/mois inclus | **2€/contrat** via Stripe |
| **Pro (pension, véto, etc.)** | 5/mois inclus | **2€/contrat** via Stripe |

> Marge : ~1,25€/contrat au-delà du quota. Les 3/5 inclus sont absorbés dans le coût du plan.

#### Implémentation technique

**Table quota :**
```sql
-- Suivi utilisation contrats YouSign par utilisateur
CREATE TABLE contrats_yousign_usage (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  uid         TEXT NOT NULL,
  mois        TEXT NOT NULL,   -- 'YYYY-MM'
  nb_utilises INTEGER DEFAULT 0,
  nb_inclus   INTEGER DEFAULT 3,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(uid, mois)
);
```

**Flow création contrat :**
1. Éleveur initie → vérifier `contrats_yousign_usage` pour le mois en cours
2. Si `nb_utilises < nb_inclus` → créer gratuitement + incrémenter
3. Si quota dépassé → afficher "2€/contrat — Payer pour continuer"
   → Stripe Payment Intent one-time 2€ → succès → créer le contrat YouSign

**Flow YouSign API v3 :**
```
POST /v3/signature_requests  →  { name, delivery_mode: 'email' }
POST /v3/signature_requests/{id}/documents  →  upload PDF
POST /v3/signature_requests/{id}/signers    →  vendeur + acheteur (nom + email)
POST /v3/signature_requests/{id}/activate   →  envoi emails automatique
Webhook signature_request.done  →  stocker PDF signé dans Supabase Storage + màj documents_animaux
```

**Variables d'environnement à ajouter :**
```
YOUSIGN_API_KEY=...          # clé API YouSign (sandbox: ys_... / prod: yp_...)
YOUSIGN_WEBHOOK_SECRET=...   # pour valider les webhooks entrants
STRIPE_CONTRACT_PRICE_ID=... # price_id Stripe pour le 2€/contrat
```

**Contrats concernés :** contrat de vente, contrat de réservation, certificat d'engagement

### 9bis.6 Codes feature

| Code | Feature | Statut |
|------|---------|--------|
| SIGN00 | Signature canvas + stockage Supabase (fallback) | ✅ Livré 2026-06-19 |
| SIGN01 | Intégration YouSign API v3 — contrat vente + réservation | 🔚 Fin de projet |
| SIGN02 | YouSign — certificat d'engagement | 🔚 Fin de projet |
| SIGN03 | Webhook completion → PDF signé archivé dans documents_animaux | 🔚 Fin de projet |
| SIGN04 | Quota mensuel + paiement Stripe 2€/contrat au-delà | 🔚 Fin de projet |
| SIGN05 | Multi-signataires / co-adoption | 🔜 V2 |
| SIGN06 | Portail signatures (tableau de bord statuts) | 🔜 V2 |

> ⚠️ **SIGN01–SIGN04 à implémenter en toute fin de projet**, une fois toutes les autres fonctionnalités livrées. La signature canvas (SIGN00) reste active en attendant.

**Dépendances (quand on implémentera) :**
- SIGN01 → compte YouSign actif + `YOUSIGN_API_KEY` + endpoint `/api/yousign/create`
- SIGN03 → endpoint webhook `/api/yousign/webhook` + bucket Supabase `contrats`
- SIGN04 → `STRIPE_CONTRACT_PRICE_ID` + table `contrats_yousign_usage`
- Profils gratuits : bouton "Signer" masqué, message "Fonctionnalité Premium"

---

## 10. Emails transactionnels — Abonnements & Relances

> **Prérequis** : choisir l'hébergement + domaine (`petsmatchapp.com`) avant d'implémenter.  
> Les emails partiront depuis `contact@petsmatchapp.com` ou `noreply@petsmatchapp.com`.  
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
| HOST02 | Configuration domaine petsmatchapp.com | HOST01 |
| HOST03 | Mode accès privé pendant tests (middleware Next.js) | HOST01 |
| HOST04 | Configuration email SMTP sur hébergeur | HOST02 |

---

## 11. Hébergement & Infrastructure

> **Domaine retenu** : `www.petsmatchapp.com`

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
- [ ] **HOST02** Acheter `petsmatchapp.com` + configurer DNS sur Vercel
- [x] **HOST03** Implémenter middleware accès privé beta (mot de passe) — `website/src/middleware.ts` + `/beta-login` + `/api/beta-login`, env var `BETA_PASSWORD`
- [ ] **HOST04** Configurer SMTP hébergeur pour emails transactionnels
- [ ] Migrer variables `.env.local` → Variables d'environnement Vercel (dashboard)
- [ ] Vérifier webhook Stripe pointe sur `https://petsmatchapp.com/api/stripe/webhook`

---

## 12. Contrats Électroniques avec Signature Officielle

### 12.1 Contexte et objectif

PetsMatch doit proposer des **contrats légalement signés** via un prestataire de signature électronique reconnu eIDAS. Objectif : valeur probatoire complète, traçabilité, archivage 10 ans.

**Prestataire retenu : YouSign** ✅
- QTSP (Qualified Trust Service Provider) — niveau eIDAS le plus élevé, certifié ANSSI
- API REST documentée, intégration estimée à ~7 jours, 40 jours d'essai gratuit
- Signature Simple : identité par email (suffisant pour certificats et réservations)
- Signature Avancée : SMS OTP (pour les ventes > 300 €)
- Tarif : à partir de 9 €/mois + ~0,60–1,20 €/signature selon volume

**Pourquoi pas SignesExpert ?** SignesExpert (JeSignExpert) est développé par l'OEC pour les cabinets comptables. Pas d'API publique documentée, pas adapté à une marketplace. L'expert-comptable de l'équipe peut l'utiliser pour ses documents de cabinet, mais PetsMatch utilise YouSign pour ses propres contrats.

**Phase actuelle : système token maison conservé** — pas de valeur eIDAS mais suffisant pour les tests et le MVP. YouSign sera intégré en Phase 2 (CONT01+). Le système token restera pour la visualisation publique des documents.

### 12.2 Types de contrats concernés

| Contrat | Espèces | Délai légal | Niveau signature |
|---|---|---|---|
| Certificat d'Engagement et de Connaissance | Chien, chat, lapin, NAC | 7 j chien/chat | Simple |
| Contrat de Réservation | Toutes | Non | Simple |
| Contrat de Vente (avec ou sans LOF/LOOF) | Toutes | Non | Avancée si > 300 € |
| Contrat de Pension / Chenil / Hôtel | Services | Non | Simple |
| Contrat de Prestation de Service Pro | Services | Non | Avancée |

### 12.3 Principe des contrats adaptatifs (pro)

Le professionnel peut **personnaliser son contrat dans un cadre légal** prédéfini :
- Clauses obligatoires non modifiables (protections légales, mentions DGCCRF)
- Sections optionnelles activables (garanties spéciales, astreinte, assurance)
- Champs libres pour clauses maison (texte libre avec validation anti-abus)
- Modèles enregistrables par type d'animal/espèce

Le système génère un PDF à partir du template rempli, puis l'envoie à YouSign pour signature.

### 12.4 Workflow technique YouSign

```
1. Éleveur remplit le formulaire contrat (web ou app)
2. Backend génère PDF (puppeteer / react-pdf / @react-pdf/renderer)
3. API YouSign : POST /signature_requests → création de la demande
4. API YouSign : upload PDF + définition des zones de signature
5. API YouSign : ajout des signataires (cédant + acquéreur) avec emails
6. API YouSign : activation → emails automatiques envoyés par YouSign
7. Webhook YouSign → PetsMatch : mise à jour statut (signe/refuse)
8. PDF signé archivé dans Supabase Storage (10 ans)
```

### 12.5 Tickets à implémenter (CONT01–CONT08)

- [ ] **CONT01** Intégration YouSign API : service partagé (`lib/services/yousign_service.dart` + `website/src/lib/yousign.ts`)
- [ ] **CONT02** Générateur PDF côté serveur (`/api/pdf/certificat`, `/api/pdf/contrat-vente`, etc.) via `@react-pdf/renderer`
- [ ] **CONT03** Contrat de Réservation adaptatif (remplacement du contrat actuel en Firestore)
- [ ] **CONT04** Contrat de Vente adaptatif avec clauses éleveur + garanties légales
- [ ] **CONT05** Certificat d'Engagement → migration vers signature YouSign (remplace le token actuel)
- [ ] **CONT06** Contrat Pension / Chenil / Hôtel (lié au module Planning Chenil §4)
- [ ] **CONT07** Contrat de Prestation Pro (prestations de service, toilettage, dressage, etc.)
- [ ] **CONT08** Éditeur de templates adaptatifs (interface pro pour personnaliser ses clauses)

### 12.6 Schéma BDD — table `contrats`

```sql
CREATE TABLE contrats (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type              TEXT NOT NULL,      -- 'reservation'|'vente'|'certificat'|'pension'|'prestation'
  cedant_uid        TEXT NOT NULL,
  signataire_uid    TEXT,               -- uid PetsMatch si connu
  signataire_email  TEXT NOT NULL,
  signataire_nom    TEXT NOT NULL,
  animal_id         UUID REFERENCES animaux(id),
  pdf_url           TEXT,               -- URL Supabase Storage après signature
  yousign_request_id TEXT,              -- ID de la demande YouSign
  statut            TEXT DEFAULT 'brouillon',  -- brouillon/envoye/lu/signe/refuse/expire
  contenu_json      JSONB,              -- snapshot des données au moment de la création
  created_at        TIMESTAMPTZ DEFAULT now(),
  signed_at         TIMESTAMPTZ,
  expires_at        TIMESTAMPTZ
);
```

### 12.7 Migration progressive

Phase 1 (court terme) : conserver le système token actuel pour les certificats, ajouter un bouton "Envoyer pour signature officielle" optionnel qui déclenche le flow YouSign.

Phase 2 : YouSign devient le canal principal pour tous les contrats. Le token reste pour la visualisation publique, YouSign gère la signature légale.

---

---

## 13. Features livrées — session 2026-06-14

### 13.1 Soin portée en masse (App + Web)

**Objectif** : ajouter un acte de santé à tous les animaux d'une portée en une seule fois.

**Champs du formulaire :**
- Type de soin (vermifuge par défaut, vaccination, antiparasitaire, visite, ostéopathie, chirurgie, traitement, autre)
- Dosage / Fréquence (conditionnel — visible uniquement pour vermifuge et antiparasitaire)
- Date du soin
- Produit / description (obligatoire)
- Administré par (optionnel) — stocké dans `registre_sanitaire.intervenant`
- Notes (optionnel) — stocké dans la colonne `notes` des tables métier
- N° ordonnance (optionnel)

**Sélection animaux :** chaque animal de la portée est affiché sous forme de chip. Tap/clic pour le désélectionner (barré + grisé). Le compteur X/N se met à jour.

**Écriture BDD :** double write —
- Table métier (`vermifuges`, `vaccinations`, `antiparasitaires`, `visites`, `traitements`) selon le type → visible dans le carnet de santé de la fiche animal
- `registre_sanitaire` → visible dans le registre consolidé éleveur

**Mapping type → table :**
| Type | Table |
|---|---|
| vermifuge | vermifuges (dosage → colonne dosage) |
| vaccination | vaccinations (desc → vaccin, interv → veterinaire) |
| antiparasitaire | antiparasitaires (dosage → frequence) |
| visite | visites (motif=Consultation) |
| ostéopathie | visites (motif=Autre, diagnostic=Ostéopathie+desc) |
| traitement / autre | traitements (type=medicament/autre) |
| chirurgie | traitements (type=autre) |

### 13.2 Carnet de santé — améliorations fiche animal (App)

- **Sous-titre visible sur la carte** : dosage (vermifuge), posologie (traitement), diagnostic (visite), vétérinaire (vaccination), fréquence (antiparasitaire), notes (radios)
- **Bouton Modifier** : visible dans le détail de chaque acte saisi par l'éleveur (source=owner). Ouvre un sheet pré-rempli avec UPDATE Supabase. Non disponible pour les actes vétérinaires.
- Champ éditable par type : vermifuges (produit, dosage, notes), vaccinations (vaccin, lot, vétérinaire), antiparasitaires (produit, fréquence, notes), traitements (nom, posologie), visites (vétérinaire, diagnostic, notes)

---

---

## 14. Module Planning Élevage — Templates & Tâches

> Priorité : Phase 1 en cours d'implémentation (2026-06-15)

### 14.1 Vision globale

Un moteur unique **Template → Planning → Tâches** couvrant 4 types de planification :

| Type | Déclencheur | Cible |
|---|---|---|
| **Sanitaire** | Événement (saillie, naissance, sevrage) | Animal / Portée |
| **Nettoyage** | Hebdomadaire / récurrent | Box / Parc |
| **Promenade** | Quotidien | Groupe d'animaux |
| **Socialisation** | Âge des bébés (semaines) | Portée |

**Principe :** L'éleveur crée un template une fois → il l'applique à chaque événement → le système génère automatiquement les tâches datées → les employés voient "mes tâches du jour" et valident.

---

### 14.2 Schéma BDD

```sql
-- Templates réutilisables
CREATE TABLE plan_templates (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid_eleveur  TEXT NOT NULL,
  nom          TEXT NOT NULL,
  type         TEXT NOT NULL,  -- sanitaire | nettoyage | promenade | socialisation
  espece       TEXT,           -- null = toutes espèces
  description  TEXT,
  created_at   TIMESTAMPTZ DEFAULT now()
);

-- Étapes d'un template (une étape = une tâche récurrente)
CREATE TABLE plan_template_etapes (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id    UUID REFERENCES plan_templates(id) ON DELETE CASCADE,
  jour_offset    INTEGER NOT NULL, -- négatif = avant événement, positif = après
  type_acte      TEXT,             -- vermifuge | vaccination | desinfection | promenade_socialisation | alimentaire | toilettage | autre
                                   -- ✅ mis à jour 2026-06-19 (Natacha) : nettoyage→desinfection, promenade+socialisation fusionnés, ajout alimentaire+toilettage
  produit        TEXT,             -- ex: Milbemax®
  dosage         TEXT,             -- ex: 1 cp / 5 kg
  duree_jours    INTEGER DEFAULT 1, -- traitement sur N jours (génère N tâches consécutives)
  description    TEXT,
  ordre          INTEGER DEFAULT 0  -- ordre d'affichage si même jour_offset
);

-- Instances actives (template appliqué à un événement)
CREATE TABLE plans_actifs (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id       UUID REFERENCES plan_templates(id),
  uid_eleveur       TEXT NOT NULL,
  type_declencheur  TEXT NOT NULL,  -- saillie | naissance | hebdo | manuel
  reference_id      TEXT,           -- saillie_id | portee_id | animal_id | box_id
  reference_label   TEXT,           -- ex: "Portée Bella × Rex — 15/06/2026"
  date_reference    DATE NOT NULL,  -- date de l'événement déclencheur
  statut            TEXT DEFAULT 'actif',  -- actif | termine | annule
  created_at        TIMESTAMPTZ DEFAULT now()
);

-- Tâches individuelles générées
CREATE TABLE plan_taches (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  plan_id         UUID REFERENCES plans_actifs(id) ON DELETE CASCADE,
  etape_id        UUID REFERENCES plan_template_etapes(id),
  uid_eleveur     TEXT NOT NULL,
  animal_id       TEXT,   -- si tâche ciblée sur un animal
  portee_id       TEXT,   -- si tâche ciblée sur une portée entière
  box_id          TEXT,   -- si tâche nettoyage
  label           TEXT NOT NULL,  -- description lisible de la tâche
  date_prevue     DATE NOT NULL,
  jour_traitement INTEGER DEFAULT 1,   -- ex: "Jour 2/4" pour traitements multi-jours
  total_jours     INTEGER DEFAULT 1,
  assigned_to     TEXT,   -- uid employé assigné (nullable)
  statut          TEXT DEFAULT 'en_attente',  -- en_attente | fait | ignore | reporte
  valide_par      TEXT,   -- uid
  valide_at       TIMESTAMPTZ,
  notes_validation TEXT,
  created_at      TIMESTAMPTZ DEFAULT now()
);
```

---

### 14.3 Phase 1 — Protocoles sanitaires

#### 14.3.1 Création d'un template sanitaire

Champs :
- Nom du protocole (ex: "Vermifuge portée standard chien")
- Espèce cible
- Étapes : pour chaque étape → jour relatif à l'événement, type d'acte, produit, dosage, durée (1 à N jours)

Exemples de templates prédéfinis (fournis par défaut, modifiables) :
```
"Vermifuge chienne — autour de la mise-bas"
  J-15 mise-bas : vermifuge mère (Milbemax® — 1 cp/10kg) — 1 jour
  J0  naissance : vermifuge mère (rappel) — 1 jour
  J+15           : vermifuge mère + chiots si sevrés — 1 jour

"Vermifuge chiots"
  J+21 naissance : vermifuge (Panacur® — 0,5ml/kg/j) — 5 jours consécutifs
  J+42           : rappel — 5 jours
  J+56           : rappel — 3 jours
```

#### 14.3.2 Application sur un événement

- Lors d'une saillie → proposition "Appliquer un protocole sanitaire ?"
- Lors d'une naissance/portée → même proposition
- Sélection du/des templates applicables
- Ajustement possible des dates avant confirmation
- Génération automatique des tâches (1 ligne `plan_taches` par jour de traitement)

#### 14.3.3 Planning du jour

Vue dédiée "Planning" dans l'app :
- Liste des tâches du jour groupées par type (sanitaire / nettoyage / promenade)
- Pour chaque tâche : animal/portée concerné, produit, dosage, "Jour X/N" si multi-jours
- Bouton **Valider** → change statut → crée l'acte dans `registre_sanitaire` + table métier
- Bouton **Reporter** → propose J+1
- Notification push à 8h chaque matin pour les tâches du jour

#### 14.3.4 Traitement multi-jours

Quand `duree_jours > 1` sur une étape :
- Génération de N `plan_taches` consécutives (J, J+1, J+2…)
- Chaque tâche affiche "Jour X / N jours"
- Validation jour par jour — chaque validation crée une entrée dans le registre
- Si un jour est oublié : alerte "Traitement en cours non validé depuis 2 jours"

---

### 14.4 Phase 2 — Planning nettoyage boxes

- Template hebdomadaire : lundi désinfection box A+B, mercredi litière C+D, vendredi parc extérieur
- Lié aux `chenil_boxes` existants
- Assignation par box à un employé
- Checklist par tâche (produit utilisé, observations)
- Récurrence automatique (génère la semaine suivante quand la courante est terminée)

---

### 14.5 Phase 3 — Rondes & socialisation

**Promenades :**
- Groupes d'animaux configurables (max N animaux par ronde selon espèce)
- Rotation automatique entre groupes (chaque chien sort au moins 2×/jour)
- Assignation à un employé ou bénévole
- Durée estimée par groupe

**Socialisation bébés :**
- Protocole par semaine d'âge (S3-S4: manipulation, S5-S7: stimulation sonore, S8: bilan)
- Adapté par espèce et race (ex: races géantes = protocole étendu)
- Tâches quotidiennes avec durée (10 min manipulation, etc.)

---

### 14.6 Accès employés

- Les employés voient **uniquement leurs tâches assignées** + les protocoles en lecture seule
- L'éleveur voit tout + peut modifier/réassigner
- Historique des validations : qui a fait quoi, quand
- Export PDF hebdomadaire des tâches réalisées

---

### 14.7 Priorités d'implémentation

```
Phase 1 (maintenant)
├── BDD : 4 tables (plan_templates, plan_template_etapes, plans_actifs, plan_taches)
├── App Flutter : création template sanitaire
├── App Flutter : application sur saillie/naissance → génération tâches
├── App Flutter : vue "Planning du jour" + validation
├── App Flutter : notification push 8h matin
└── Traitement multi-jours : affichage "Jour X/N" + validation jour par jour

Phase 2 (semaine suivante)
├── Planning nettoyage boxes
├── Assignation employés
└── Web : miroir des vues Flutter

Phase 3 (suite)
├── Rondes promenade + rotation
└── Socialisation bébés par semaine d'âge
```

---

### 14.8 Vue Agenda / Calendrier mensuel (PLN01–PLN02)

> **✅ PLN01 Livré 2026-06-19 (Natacha)** : calendrier mois avec pastilles colorées par type de protocole sur app Flutter et web. Vue jour avec navigation prev/next. Bouton reporter sur tâches manuelles et protocoles.

> **Contexte** : la vue "Planning du jour" existe. Il faut une vue calendrier mensuelle qui montre d'un coup d'œil les jours chargés, et la possibilité de voir les tâches dans l'agenda natif du téléphone.

#### PLN01 — Vue calendrier mensuelle in-app

**Écran "Agenda"** accessible depuis la navigation principale du planning (onglet ou bouton bascule Jour/Mois).

**Vue mois :**
```
         Juin 2026
Lu Ma Me Je Ve Sa Di
         1  2  3  4  5  6  7
          •     ••    •
 8  9  10 11 12 13 14
••        •  •• •
15 16 17 18 19 20 21
•         •        ••
```
- Pastille colorée sous chaque jour avec tâches (couleur par type : 🟢 sanitaire, 🔵 nettoyage, 🟠 promenade)
- Tap sur un jour → slide vers la vue "Planning du jour" de ce jour
- Navigation mois précédent / suivant
- Badge rouge si tâches en retard (date_prevue < aujourd'hui et statut = en_attente)

**Données nécessaires :** requête Supabase des jours ayant des tâches pour le mois affiché :
```sql
SELECT date_prevue, type_acte, COUNT(*) as nb
FROM plan_taches
WHERE uid_eleveur = $uid
  AND date_prevue BETWEEN $debut_mois AND $fin_mois
  AND statut != 'fait'
GROUP BY date_prevue, type_acte
```

**Codes feature :**
- **PLN01** — Vue calendrier mensuelle Flutter (package `table_calendar` ou implémentation custom)
- **PLN02** — Vue calendrier web Next.js (même logique, `react-big-calendar` ou custom)

#### PLN02 — Synchronisation agenda natif (optionnel V2)

- Export des tâches récurrentes vers Google Calendar / Apple Calendar (iCal `.ics`)
- Format : événement par groupe de tâches, description = animaux concernés + protocole
- Déclencheur : bouton "Exporter vers mon agenda" dans les paramètres du planning
- Ne pas synchroniser les validations (sens unique : app → agenda)

---

### 14.9 Intégration Tâches ↔ Employés (PLN03–PLN04)

> **Contexte** : les tâches de protocole (`plan_taches`) et les tâches manuelles sont deux systèmes séparés. L'employé doit voir tout au même endroit.

#### PLN03 — Vue unifiée "Mes tâches" pour l'employé

**Principe :** l'employé voit dans un seul écran :
1. Ses tâches manuelles assignées (depuis le module tâches existant)
2. Ses tâches de protocole assignées (`plan_taches` avec `assigned_to = uid_employe`)

**Règles de fusion pour l'affichage :**
```
Regroupement par jour (comme la vue planning éleveur)
  → Pour chaque jour : tâches manuelles + tâches protocole, triées par tranche_horaire
  → Section "Matin", "Midi", "Après-midi", "Soir", puis "Sans horaire"
  → Carte commune : emoji + label + type + animal(s) si protocole
  → Bouton "Fait" unique quelle que soit la source
```

**Validation depuis la vue employé :**
- Tâche manuelle → update dans la table `taches` (ou équivalent existant)
- Tâche protocole → `PlanningService.validerTache()` comme actuellement

**Accès :** l'onglet "Planning" dans `EmployeurDetailPage` devient "Tâches" et affiche les deux sources fusionnées.

**Codes feature :**
- **PLN03** — Fusion tâches manuelles + protocole dans la vue employé (Flutter)
- **PLN04** — Même vue côté employé connecté à son propre compte (son dashboard personnel)

#### PLN04 — Notification employé pour tâche assignée

- Quand l'éleveur assigne une tâche de protocole → notification push à l'employé
- Rappel à 7h chaque matin pour les tâches du jour assignées
- Badge sur l'icône de l'app (nb de tâches en attente pour aujourd'hui)

---

### 14.10 Export & Impression des Protocoles (PLN05–PLN07)

> **Contexte** : en cas de contrôle sanitaire (DDPP, vétérinaire officiel), l'éleveur doit pouvoir présenter ses protocoles et ses registres de soins de manière lisible même sans téléphone.

#### PLN05 — Export PDF d'un protocole (template)

**Déclencheur :** bouton "Imprimer / Exporter" sur la page de détail d'un template.

**Contenu du PDF :**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PROTOCOLE : Vermifuge portée standard chien
Élevage : [Nom de l'élevage] — [Date d'export]
Espèce cible : Chien | Cible : Tout le cheptel
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

ÉTAPES DU PROTOCOLE
┌──────────────────┬────────────────────┬──────────┬──────────┐
│ Timing           │ Acte               │ Produit  │ Dosage   │
├──────────────────┼────────────────────┼──────────┼──────────┤
│ J+0              │ Vermifuge          │ Milbemax │ 1cp/5kg  │
│ J+21             │ Rappel Vermifuge   │ Milbemax │ 1cp/5kg  │
│ Chaque lundi     │ Promenade          │ —        │ —        │
│ (52 semaines)    │                    │          │          │
└──────────────────┴────────────────────┴──────────┴──────────┘

Créé le : 01/06/2026 | Dernière mise à jour : 15/06/2026
```

**Stack Flutter :** package `pdf` + `printing` (déjà largement utilisé dans l'écosystème Flutter).

```dart
// Exemple d'usage
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

final pdf = pw.Document();
pdf.addPage(pw.Page(build: (ctx) => pw.Column(children: [...])));
await Printing.layoutPdf(onLayout: (format) => pdf.save());
```

#### PLN06 — Export PDF du planning du jour / de la semaine

**Déclencheur :** bouton "Imprimer" dans la vue planning jour ou semaine.

**Contenu :**
```
PLANNING DU JOUR — Lundi 16 juin 2026
Élevage : [Nom]

🌅 MATIN
☐  🦮 Promenade — Rex, Fido, Utha, Bella
☐  💊 Vermifuge (Milbemax® 1cp/5kg) — Luna  Jour 1/4

☀️ MIDI
☐  🧹 Nettoyage Chenil n°1

🌙 SOIR
☐  🦮 Promenade — Rex, Fido, Utha, Bella

──────────────────────────────────────────────
Total : 4 tâches | Imprimé le 16/06/2026 07:45
Signature soigneur : ___________________
```

Cases à cocher imprimables → le soigneur coche manuellement si pas de téléphone.

**Vue semaine :** une page par jour, ou tableau 7 colonnes condensé.

#### PLN07 — Export PDF du registre de traitements (pour contrôle DDPP)

**Déclencheur :** bouton "Exporter le registre" dans la section planning ou registre sanitaire.

**Période sélectionnable :** ce mois / les 3 derniers mois / l'année en cours / période personnalisée.

**Contenu :**
```
REGISTRE DE TRAITEMENTS SANITAIRES
Élevage : [Nom] | SIRET : [XXX] | Période : 01/01/2026 – 15/06/2026

Date       Animal   Traitement        Produit      Dosage   Intervenant   Notes
──────────────────────────────────────────────────────────────────────────────
02/01/2026 Rex      Vermifuge         Milbemax®    1cp/5kg  A. Bégrand    —
02/01/2026 Fido     Vermifuge         Milbemax®    1cp/5kg  A. Bégrand    —
15/01/2026 Tous     Antiparasitaire   Frontline®   1 pipette A. Bégrand   —
…

Nombre d'actes : 47 | Document généré le 15/06/2026 à 10:23
```

Ce document est conforme au format attendu lors d'un contrôle DDPP (Direction Départementale de la Protection des Populations).

**SQL source :** table `registre_sanitaire` (déjà existante) + jointure `animaux`.

#### Codes feature résumé

| Code  | Feature | Surface | Priorité |
|-------|---------|---------|---------|
| PLN01 | Vue calendrier mensuelle | App Flutter | ✅ Livré 2026-06-19 |
| PLN02 | Sync agenda natif (iCal) | App Flutter | V2 |
| PLN03 | Vue unifiée tâches employé | App Flutter | V1 |
| PLN04 | Notifications tâches employé | App + Push | V1 |
| PLN05 | Export PDF protocole (template) | App + Web | V1 |
| PLN06 | Export PDF planning jour/semaine | App + Web | V1 |
| PLN07 | Export PDF registre DDPP | App + Web | V1 |

#### Dépendances

- PLN05/06/07 → package Flutter `pdf` + `printing` à ajouter dans `pubspec.yaml`
- PLN03 → nécessite d'identifier la table des tâches manuelles existantes
- PLN07 → données issues de `registre_sanitaire` (déjà alimenté par `validerTache`)
- PLN01 → peut utiliser `table_calendar` (pub.dev) ou un composant custom

---

---

## 10. Onboarding éleveur (A39) ✅

> Implémenté le 2026-06-17

### 10.1 Flutter — Première connexion

**Fichier :** `lib/pages/onboarding/onboarding_eleveur.dart`  
**Déclenchement :** `EleveurNav.initState()` via `SharedPreferences` (`onboarding_eleveur_done`)

5 slides (PageView) avec indicateur de points, bouton "Passer" + "Suivant" / "Commencer !" :

| Slide | Titre | Contenu |
|---|---|---|
| 1 | Bienvenue dans votre espace élevage | Vue d'ensemble dashboard |
| 2 | Vos animaux au complet | Carnet de santé, vaccinations, actes véto |
| 3 | Publiez vos annonces | Chiots, portées, saillies, pensions |
| 4 | Planning & Agenda | Routines, rappels, vue hebdomadaire |
| 5 | Documents & Certifications | Contrats, CEI, factures, registres |

**État :** `onboarding_eleveur_done: bool` dans SharedPreferences. Affiché une seule fois au premier login.

### 10.2 Web — Page profil élevage ✅

**URL :** `/elevage/profil`  
**Fichier :** `website/src/app/elevage/profil/page.tsx`

Page dédiée dans l'espace de gestion élevage (même niveau que `/elevage/agenda`, `/elevage/planning`). Accessible depuis :
- Header EleveurDashboard (avatar + bouton)
- Quick links dashboard (tuile "Mon profil élevage")

**Contenu :**
- Bannière + photo de profil + nom d'élevage + ville
- Badge validation (Profil validé ✓ / En attente ⏳)
- Espèces élevées + races
- Description
- Coordonnées (téléphone + adresse)
- Certifications (SIRET ✓/✗, justificatif, ACACED ✓/✗, certificat)
- Bouton "Modifier mon profil" → `/profil` (formulaire complet)
- Bouton "Voir mon profil public" → `/elevages/[uid]` (si validé)

### 10.3 À faire

- **A40** : Onboarding pro (3-4 slides : profil pro, agenda/RDV, clients, documents)
- **A41** : Onboarding particulier (2-3 slides : mes animaux, alertes perdus, annonces)
- Onboarding web (animation côté web pour les mêmes profils au 1er login)

---

---

## 15. Messagerie & Paramètres utilisateur

> Dernière mise à jour : 2026-06-18  
> Surfaces : **App Flutter (Android/iOS) + Site Web Next.js**

---

### 15.1 Messagerie — Catégories et organisation

Les conversations sont regroupées par catégorie affichée sous forme d'onglets horizontaux.

| Clé Firestore | Label | Emoji | Couleur |
|---|---|---|---|
| `null` / non défini | Tous | — | — |
| `animaux-perdus` | Perdus/Trouvés | 🐾 | Orange |
| `annonces` | Annonces | 🏷️ | Teal |
| `communaute` | Communauté | 💬 | Violet |
| `contact-elevage` | Élevages | 🐕 | Teal foncé |
| `service-professionnel` | Services | 🔧 | Violet foncé |
| `__archived__` | Archivés | 📦 | Ardoise |

**Attribution de la catégorie :** définie côté créateur de la conversation selon le contexte (annonce, profil éleveur, profil pro). La valeur est stockée dans le document Firestore `conversations/{id}.categorie`.

---

### 15.2 Messagerie — Actions sur une conversation (long-press)

**Flutter :** `showModalBottomSheet` au long-press sur une carte conversation.  
**Web :** menu contextuel (right-click / clic droit) avec overlay positionné aux coordonnées de la souris.

| Action | Champ Firestore | Comportement |
|---|---|---|
| **Épingler / Désépingler** | `pinnedFor.$uid: bool` | Conversation remontée en tête de liste |
| **Archiver / Désarchiver** | `archivedFor.$uid: bool` | Masquée des onglets, visible uniquement dans "Archivés" |
| **Sourdine 8h** | `mutedFor.$uid: epochMs` | Icône 🔕 sur la carte, notifications désactivées jusqu'à l'heure définie |
| **Bloquer l'utilisateur** | `bloquer/$uid` (doc Firestore) | Conversation masquée définitivement, expéditeur ne peut plus contacter |
| **Supprimer** | `deletedFor.$uid: bool` | Conversation masquée uniquement pour l'utilisateur courant |

**Ordre d'affichage :** épinglées en premier, puis par timestamp décroissant.  
**Filtrage :** les conversations supprimées, archivées (sauf onglet Archivés) et bloquées sont exclues.

---

### 15.3 Messagerie — Visuel des cartes

- Fond `#F0F9FF` + icône 📌 en haut à droite si conversation épinglée
- Icône 🔕 si sourdine active (`mutedFor.$uid > Date.now()`)
- Avatar + nom + dernière message + timestamp (format relatif)

---

### 15.4 Paramètres utilisateur — Pages Flutter

Accessible depuis le drawer de navigation (tous profils). Pages sous `lib/pages/settings/`.

| Page | Fichier | Contenu |
|---|---|---|
| **Menu principal** | `main_settings.dart` | Liens vers toutes les sous-pages + bouton déconnexion + suppression compte |
| **Information utilisateur** | `info_utilisateur.dart` | Identité (Prénom *, Nom *), Coordonnées (Téléphone *, Ville *, Code postal *), adresse. Les espèces élevées sont gérées dans le profil éleveur (`profil_eleveur_edit.dart`) |
| **Connexion & sécurité** | `connectionSecu.dart` | Email affiché (lecture seule), réinitialisation mot de passe (Firebase Auth), contact support (`mailto:`) |
| **Confidentialité** | `parametre_config.dart` | Droits RGPD, résumé CGU, lien vers petsmatchapp.com/cgu |
| **À propos** | `about_us.dart` | Informations légales éditeur, responsables, hébergement, données personnelles |
| **Utilisateurs bloqués** | `utilisateurs_bloques_page.dart` | Liste des comptes bloqués avec déblocage (suppression clé dans `bloquer/$uid`) |

**Design commun :** AppBar teal `#0C5C6C`, fond `#F8F8F8`, cartes blanches avec ombre, typographie Galey.

---

### 15.5 Paramètres utilisateur — Section Web (`/profil`)

Section "Sécurité & aide" ajoutée en bas de la page `/profil` :

| Tuile | Action |
|---|---|
| Réinitialiser mon mot de passe | `sendPasswordResetEmail(getAuth(), user.email)` — email Firebase Auth |
| Poser une question | `mailto:petsmatch.contact@gmail.com` avec objet/corps pré-remplis |
| Confidentialité & CGU | Lien externe `www.petsmatchapp.com/cgu` |
| À propos | Lien interne `/a-propos` |

Page `/a-propos` : informations légales éditeur (SIREN, SIRET, TVA, adresse), responsables (Présidente : Natacha Loisiel, DG : Nabil Ksouri), hébergement (Supabase + Firebase), propriété intellectuelle, données personnelles, litiges (tribunaux de Rennes).

Page `/profil/bloques` : liste des utilisateurs bloqués avec bouton de déblocage (même logique que Flutter).

---

### 15.6 Export des données (RGPD)

**Flutter uniquement** (pas de version web prévue en V1) — bouton "Exporter mes données" dans les paramètres.

**Données exportées :**
- Profil Supabase (`users`)
- Animaux Supabase (`animaux`)
- Annonces Supabase (`annonces`)
- Données complémentaires Firestore (`users/{uid}`)

**Format :** JSON indenté, nom de fichier horodaté. Partagé via `Share.shareXFiles` (share_plus).  
**Contrainte technique :** les `Timestamp` Firestore sont convertis en ISO 8601 avant sérialisation (conversion `_toJsonSafe`).

---

### 15.7 Statut d'implémentation

| Feature | Code | App Flutter | Web | Notes |
|---|---|---|---|---|
| Catégories messagerie (7 onglets) | MSG01 | ✅ | ✅ | Firestore `categorie` |
| Actions long-press (5 actions) | MSG02 | ✅ | ✅ | Right-click web |
| Épinglage / archivage / sourdine | MSG03 | ✅ | ✅ | Champs `pinnedFor` etc. |
| Blocage + page utilisateurs bloqués | MSG04 | ✅ | ✅ | `bloquer/$uid` Firestore |
| Paramètres — menu principal | SET01 | ✅ | ✅ (section /profil) | — |
| Paramètres — info utilisateur | SET02 | ✅ | — | Espèces → profil éleveur |
| Paramètres — connexion & sécurité | SET03 | ✅ | ✅ | Reset mdp Firebase |
| Paramètres — confidentialité | SET04 | ✅ | ✅ (lien CGU) | — |
| Paramètres — à propos | SET05 | ✅ | ✅ (`/a-propos`) | — |
| Export données RGPD | SET06 | ✅ | ❌ à faire | JSON via share_plus |

---

*Document maintenu par l'équipe PetsMatch — toute modification fonctionnelle doit être reportée ici avant implémentation.*
