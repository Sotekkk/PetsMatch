# PetsMatch — Spécifications : Services & Communauté

> Document dédié au développement de la section Services, Profils Pro,
> Animal Friendly, Événements et Communauté.
> **Assigné à :** [prénom collègue]
> **Ne pas toucher en parallèle :** voir §13 en bas de document.

---

## État actuel (point de départ)

La navigation est déjà en place — **ne pas la recréer**, juste la brancher.

### Fichiers existants à modifier/compléter

| Fichier | État | À faire |
|---|---|---|
| `lib/pages/services/services_page.dart` | ✅ Grille 6 catégories fonctionnelle | Ajouter badge "Pro" sur certaines catégories |
| `lib/pages/services/veterinaires_page.dart` | ✅ 6 sous-pages avec sections | Remplacer les `onTap → SnackBar "bientôt disponible"` par navigation réelle |

### Web — section Services absente ⚠️

**Aucune page `/services` n'existe sur le site web.** Toute la section est à créer.
Le collègue doit créer la structure web en miroir de l'app.
Ajouter aussi l'entrée "Services" dans `src/components/Header.tsx` (menu de navigation).

### Structure actuelle dans `veterinaires_page.dart` (app Flutter)

Toutes les sous-pages sont dans **un seul fichier** sous forme de classes :
- `VeterinairesPag` → Annuaire, Avis, Urgences
- `EducationPage` → Éducateurs, Pet sitter, Pension
- `SantePage` → Ostéo, Kiné, Naturo, Acupuncteur, Homéo...
- `LieuxSympasPage` → Parcs, Restos, Hôtels, Événements, Promenade collective
- `ProduitsPage` → Boutiques, Aliments, Créateurs
- `CommunautePage` → Forums, Groupes, Balades, Événements

**Chaque section affiche actuellement `'${section.title} — bientôt disponible'` en SnackBar.**
Le travail consiste à remplacer chaque `onTap` par une navigation vers une vraie page.

### Réutiliser le composant existant

Le widget `_ServiceSubPage` + `_SectionCard` dans `veterinaires_page.dart` est le shell de base.
Il peut être gardé pour la navigation de liste ou remplacé par des pages plus riches selon la section.

---

## 1. Types de professionnels

### Catégories et sous-catégories

```
Santé
  ├── Vétérinaire
  ├── Ostéopathe animalier
  ├── Kinésithérapeute animalier
  ├── Naturopathe animalier
  ├── Acupuncteur animalier
  ├── Homéopathe animalier
  └── Maréchal ferrant

Éducation & Garde
  ├── Éducateur comportementaliste
  ├── Maître-chien / Dresseur
  ├── Pet sitter (garde à domicile)
  ├── Promeneur de chiens
  └── Pension (hébergement)

Référencement (sans services avancés)
  ├── Boutique en ligne
  ├── Fournisseur d'aliments
  └── Créateur pour animaux (accessoires, vêtements, art...)
```

### Modèle freemium

| Tier | Profils concernés | Prix | Fonctionnalités |
|---|---|---|---|
| **Gratuit** | Boutique, Fournisseur, Créateur | 0 € | Fiche de référencement simple, visible dans l'annuaire, lien externe |
| **Essentiel** | Tous les pros santé, éduc, garde | ~X €/mois | Fiche enrichie, agenda RDV, notifications clients |
| **Avancé** | Vétérinaire, Santé, Éducation | ~X €/mois | Tout Essentiel + accès carnet santé animal, envoi ordonnances/CR, registre pension |

> 💡 Les prix sont à définir. Prévoir le champ `cat_pro` dans `users` (déjà présent en BDD) pour stocker la sous-catégorie exacte.

---

## 2. Profil professionnel

### Champs du profil (BDD `users` — colonnes existantes + à ajouter)

**Identité (déjà en BDD)**
- `firstname`, `lastname` — prénom et nom
- `name_elevage` → réutiliser comme `nom_structure` pour les pros
- `profile_picture_url` — photo de profil / logo
- `desc_entreprise` — description de l'activité
- `siret` — numéro SIRET
- `numero_tva` — N° TVA intracommunautaire
- `profession_pro` — intitulé exact de la profession
- `cat_pro` — catégorie (santé / garde / référencement / etc.)
- `rue`, `ville`, `code_postal`, `pays`, `lat`, `lng` — localisation

**Champs à ajouter en BDD**
```sql
ALTER TABLE users ADD COLUMN IF NOT EXISTS rayon_intervention   INTEGER;   -- km (pet sitter, promeneur)
ALTER TABLE users ADD COLUMN IF NOT EXISTS especes_acceptees     JSONB DEFAULT '[]'; -- espèces traitées/acceptées
ALTER TABLE users ADD COLUMN IF NOT EXISTS horaires              JSONB;     -- { lun: "9h-18h", ... }
ALTER TABLE users ADD COLUMN IF NOT EXISTS tarifs                TEXT;      -- description libre des tarifs
ALTER TABLE users ADD COLUMN IF NOT EXISTS site_web              TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS instagram             TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS facebook              TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS certifications        JSONB DEFAULT '[]'; -- [{ nom, numero, doc_url }]
ALTER TABLE users ADD COLUMN IF NOT EXISTS photos_galerie        JSONB DEFAULT '[]'; -- URLs galerie photos
ALTER TABLE users ADD COLUMN IF NOT EXISTS accept_new_clients    BOOLEAN DEFAULT TRUE;
```

### Vue publique du profil pro

- Photo + nom structure + profession
- Badge catégorie (Vétérinaire / Ostéo / Pension / etc.)
- Espèces acceptées (icônes)
- Localisation + distance depuis l'utilisateur courant
- Description
- Horaires d'ouverture
- Galerie photos
- Certifications affichées
- Bouton **Prendre RDV** (tier Essentiel+) ou **Contacter** ou **Visiter le site**
- Avis / notes (à prévoir pour V2)

---

## 3. Services avancés — Santé (Vétérinaire, Ostéo, Kiné…)

### 3.1 Agenda & Rendez-vous

**Nouvelle table `rdv`**
```sql
CREATE TABLE rdv (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid         TEXT REFERENCES users(uid) ON DELETE CASCADE,
  client_uid      TEXT REFERENCES users(uid) ON DELETE SET NULL,
  animal_id       TEXT REFERENCES animaux(id) ON DELETE SET NULL,
  date_heure      TIMESTAMPTZ NOT NULL,
  duree_minutes   INTEGER DEFAULT 30,
  motif           TEXT,
  statut          TEXT DEFAULT 'confirme',  -- 'confirme','annule','termine','no_show'
  notes_pro       TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);
```

**Fonctionnalités :**
- Pro : gestion de son agenda (créneaux disponibles, vue semaine/mois)
- Propriétaire : demande de RDV depuis la fiche pro ou la fiche animal
- Sélection de l'animal concerné lors de la prise de RDV
- Confirmation automatique ou validation manuelle par le pro
- **Rappels** : notification push 48h avant, 24h avant, 1h avant (au propriétaire)
- Annulation par l'une ou l'autre partie avec notification

### 3.2 Accès au carnet de santé animal

- Le propriétaire **autorise explicitement** un pro à accéder à la fiche de son animal
- Table de permissions :
```sql
CREATE TABLE animal_acces_pro (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  animal_id   TEXT REFERENCES animaux(id) ON DELETE CASCADE,
  pro_uid     TEXT REFERENCES users(uid) ON DELETE CASCADE,
  owner_uid   TEXT REFERENCES users(uid) ON DELETE CASCADE,
  granted_at  TIMESTAMPTZ DEFAULT NOW(),
  expires_at  TIMESTAMPTZ,           -- null = pas d'expiration
  UNIQUE(animal_id, pro_uid)
);
```
- Le pro voit : espèce, race, âge, poids, vaccins, actes vétérinaires, médicaments en cours
- Le pro ne voit **pas** : documents pedigree, registre entrée/sortie, infos financières

### 3.3 Envoi d'ordonnance numérique

**Nouvelle table `ordonnances`**
```sql
CREATE TABLE ordonnances (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid     TEXT REFERENCES users(uid) ON DELETE SET NULL,
  animal_id   TEXT REFERENCES animaux(id) ON DELETE CASCADE,
  owner_uid   TEXT REFERENCES users(uid) ON DELETE CASCADE,
  rdv_id      UUID REFERENCES rdv(id) ON DELETE SET NULL,
  doc_url     TEXT NOT NULL,
  date_emit   DATE DEFAULT CURRENT_DATE,
  notes       TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```
- Le pro upload un PDF (ou photo) depuis l'interface
- Le propriétaire reçoit une notification push + visible dans le carnet de santé de l'animal
- Visible dans l'onglet "Documents" de la fiche animal côté propriétaire

### 3.4 Compte rendu de consultation

**Nouvelle table `comptes_rendus`**
```sql
CREATE TABLE comptes_rendus (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid     TEXT REFERENCES users(uid) ON DELETE SET NULL,
  animal_id   TEXT REFERENCES animaux(id) ON DELETE CASCADE,
  owner_uid   TEXT REFERENCES users(uid) ON DELETE CASCADE,
  rdv_id      UUID REFERENCES rdv(id) ON DELETE SET NULL,
  contenu     TEXT,
  doc_url     TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

---

## 4. Services avancés — Pension / Garde

### 4.1 Registre entrée/sortie pension

- Réutiliser la logique du registre éleveur (`registre_entree_sortie`)
- Ajouter colonne `pension_pro_uid TEXT REFERENCES users(uid)` pour distinguer les entrées pension des entrées élevage
- Entrée pension : date arrivée, date départ prévue, animal, propriétaire, notes
- Sortie pension : date départ réelle, état de l'animal, rapport de séjour (texte + photos)
- Propriétaire reçoit une notification à l'arrivée et au départ
- **Rapport de séjour** : photos + texte envoyés au propriétaire via notification + visible dans messagerie

### 4.2 Fiche animal pendant le séjour

- La pension accède à la fiche de l'animal (via `animal_acces_pro`) pendant la durée du séjour
- Peut ajouter des notes au carnet de santé pendant le séjour

---

## 5. Services avancés — Éducation

### 5.1 Agenda de séances

- Même système que les RDV santé (table `rdv`, motif = type de séance)
- Types de séances : cours individuel, cours collectif, bilan comportemental, suivi

### 5.2 Fiche de progression par animal

**Nouvelle table `education_progression`**
```sql
CREATE TABLE education_progression (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  pro_uid     TEXT REFERENCES users(uid) ON DELETE SET NULL,
  animal_id   TEXT REFERENCES animaux(id) ON DELETE CASCADE,
  owner_uid   TEXT REFERENCES users(uid) ON DELETE CASCADE,
  date_seance DATE,
  contenu     TEXT,
  objectifs   JSONB DEFAULT '[]',   -- [{ label, atteint: bool }]
  doc_url     TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```
- Le pro renseigne après chaque séance
- Le propriétaire reçoit une notification + peut consulter depuis la fiche animal

---

## 6. Annuaire des professionnels

### Page principale (`/services` app + web)

- Carte + liste (onglets)
- Filtres : catégorie, espèce, ville/rayon, disponibilité
- Tri : distance, note, nom
- Carte : pin coloré par catégorie
  - Rouge = Santé
  - Bleu = Éducation/Garde
  - Orange = Référencement

### Fiche pro publique (`/services/[uid]` web / page dédiée app)

- Toutes les infos du §2
- Bouton RDV / Contact / Site web selon tier
- Onglets : Présentation | Services & Tarifs | Galerie | Avis (V2)

---

## 7. Animal Friendly — Lieux

### Concept

Carte collaborative des lieux accueillant les animaux. Visible publiquement, sur les profils éleveur et particulier.

### Catégories de lieux

| Catégorie | Icône | Description |
|---|---|---|
| Restaurant / Bar | 🍽️ | Terrasse dog-friendly |
| Hôtel / Hébergement | 🏨 | Accepte animaux |
| Plage / Plan d'eau | 🏖️ | Accès autorisé |
| Randonnée / Parc | 🌲 | Sentiers et espaces verts |
| Shopping / Commerce | 🛍️ | Animaux acceptés en magasin |
| Camping | ⛺ | Camping acceptant animaux |
| Transport | 🚌 | Compagnies acceptant animaux |
| Vétérinaire d'urgence | 🚨 | Clinique urgences 24h/24 |

### Table `lieux_friendly`

```sql
CREATE TABLE lieux_friendly (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ajout_uid    TEXT REFERENCES users(uid) ON DELETE SET NULL,
  nom          TEXT NOT NULL,
  categorie    TEXT NOT NULL,
  adresse      TEXT,
  ville        TEXT,
  code_postal  TEXT,
  pays         TEXT DEFAULT 'FR',
  lat          DOUBLE PRECISION,
  lng          DOUBLE PRECISION,
  especes      JSONB DEFAULT '[]',   -- espèces acceptées
  description  TEXT,
  photo_url    TEXT,
  site_web     TEXT,
  statut       TEXT DEFAULT 'en_attente',  -- 'en_attente','valide','rejete'
  valide_par   TEXT,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
```

### Fonctionnalités

**Utilisateur :**
- Voir la carte avec filtres (catégorie, espèce, ville)
- Voir la liste
- Proposer un lieu (formulaire simple : nom, catégorie, adresse, espèces, description, photo)
- Liker / sauvegarder un lieu
- Signaler une information incorrecte

**Pro (listing payant) :**
- Inscription directe, apparaît immédiatement après validation admin
- Badge "Établissement certifié PetsMatch"
- Fiche enrichie (galerie, horaires, description longue)

**Admin :**
- Validation des lieux proposés par les utilisateurs
- Gestion des signalements

---

## 8. Événements

### Concept

Espace pour créer et partager des événements liés aux animaux.

### Types d'événements

- Exposition / Concours (SCC, LOOF, etc.)
- Salon / Foire animalière
- Formation / Atelier
- Balade collective (voir §9)
- Rassemblement / Rencontre de race
- Vente de portée / Salon de l'élevage
- Autre

### Table `evenements`

```sql
CREATE TABLE evenements (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  createur_uid    TEXT REFERENCES users(uid) ON DELETE CASCADE,
  titre           TEXT NOT NULL,
  type            TEXT NOT NULL,
  description     TEXT,
  date_debut      TIMESTAMPTZ NOT NULL,
  date_fin        TIMESTAMPTZ,
  lieu            TEXT,
  ville           TEXT,
  code_postal     TEXT,
  pays            TEXT DEFAULT 'FR',
  lat             DOUBLE PRECISION,
  lng             DOUBLE PRECISION,
  especes         JSONB DEFAULT '[]',
  capacite_max    INTEGER,
  prix            NUMERIC(10,2) DEFAULT 0,
  photo_url       TEXT,
  lien_externe    TEXT,
  statut          TEXT DEFAULT 'publie',  -- 'publie','annule','termine'
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE evenements_inscrits (
  evenement_id  UUID REFERENCES evenements(id) ON DELETE CASCADE,
  user_uid      TEXT REFERENCES users(uid) ON DELETE CASCADE,
  inscrit_at    TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (evenement_id, user_uid)
);
```

### Fonctionnalités

- Créer un événement (éleveur, pro, particulier)
- Carte + liste des événements à venir
- Filtres : type, espèce, ville/rayon, date
- Inscription (bouton "Je participe") avec compteur de participants
- Notification de rappel J-7 et J-1 aux inscrits
- Annulation avec notification à tous les inscrits
- Partage sur le feed social

---

## 9. Promenades collectives

### Concept

Sortie organisée par un utilisateur (ou pro), rejoindre avec son/ses animal(aux).

### Table `promenades`

```sql
CREATE TABLE promenades (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organisateur_uid TEXT REFERENCES users(uid) ON DELETE CASCADE,
  titre           TEXT,
  description     TEXT,
  date_heure      TIMESTAMPTZ NOT NULL,
  lieu_rdv        TEXT NOT NULL,
  lat             DOUBLE PRECISION,
  lng             DOUBLE PRECISION,
  duree_minutes   INTEGER DEFAULT 60,
  distance_km     NUMERIC(5,2),
  niveau          TEXT DEFAULT 'facile',  -- 'facile','moyen','difficile'
  especes         JSONB DEFAULT '[]',
  participants_max INTEGER,
  statut          TEXT DEFAULT 'ouvert',
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE promenades_participants (
  promenade_id  UUID REFERENCES promenades(id) ON DELETE CASCADE,
  user_uid      TEXT REFERENCES users(uid) ON DELETE CASCADE,
  animaux       JSONB DEFAULT '[]',  -- IDs des animaux qui viennent
  rejoint_at    TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (promenade_id, user_uid)
);
```

### Fonctionnalités

- Créer une promenade (n'importe quel utilisateur)
- Carte des promenades à venir dans la région
- Rejoindre avec sélection de ses animaux
- Voir les participants et leurs animaux
- Notification de rappel 2h avant
- Chat de groupe dédié à la promenade (lié à la messagerie)

---

## 10. Communauté — Forum & Groupes

### Concept

Espace d'échange entre utilisateurs, organisé par thématiques.

### Structure

```
Communauté
  ├── Forum
  │   ├── Catégories : Santé, Alimentation, Éducation, Élevage, Général, etc.
  │   └── Sous-catégories par espèce
  └── Groupes
      ├── Par race (ex : "Bergers Allemands France")
      ├── Par région (ex : "Éleveurs Bretagne")
      └── Par centre d'intérêt (ex : "Agility", "Canicross")
```

### Tables

```sql
CREATE TABLE forum_categories (
  id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nom     TEXT NOT NULL,
  icone   TEXT,
  ordre   INTEGER DEFAULT 0
);

CREATE TABLE forum_sujets (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  categorie_id UUID REFERENCES forum_categories(id) ON DELETE CASCADE,
  auteur_uid   TEXT REFERENCES users(uid) ON DELETE SET NULL,
  titre        TEXT NOT NULL,
  contenu      TEXT NOT NULL,
  especes      JSONB DEFAULT '[]',
  photo_url    TEXT,
  vues         INTEGER DEFAULT 0,
  epingle      BOOLEAN DEFAULT FALSE,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE forum_reponses (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  sujet_id  UUID REFERENCES forum_sujets(id) ON DELETE CASCADE,
  auteur_uid TEXT REFERENCES users(uid) ON DELETE SET NULL,
  contenu   TEXT NOT NULL,
  photo_url TEXT,
  likes     INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE groupes (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  createur_uid TEXT REFERENCES users(uid) ON DELETE SET NULL,
  nom          TEXT NOT NULL,
  description  TEXT,
  type         TEXT,   -- 'race','region','loisir','autre'
  espece       TEXT,
  photo_url    TEXT,
  prive        BOOLEAN DEFAULT FALSE,
  created_at   TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE groupes_membres (
  groupe_id  UUID REFERENCES groupes(id) ON DELETE CASCADE,
  user_uid   TEXT REFERENCES users(uid) ON DELETE CASCADE,
  role       TEXT DEFAULT 'membre',   -- 'admin','moderateur','membre'
  rejoint_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (groupe_id, user_uid)
);
```

### Fonctionnalités Forum

- Lire avec compte (tous profil)
- Poster avec compte (tous profils)
- Système de réponses imbriquées (1 niveau)
- Likes sur les réponses
- Signalement de contenu
- Modération admin (épingler, supprimer)

### Fonctionnalités Groupes

- Créer un groupe (public ou privé)
- Rejoindre / Quitter
- Posts dans le groupe (texte + photos)
- Messagerie de groupe (via le système conversation existant)
- Notifications sur nouvelles publications

---

## 11. Récapitulatif BDD — nouvelles tables

| Table | Section | Priorité |
|---|---|---|
| `rdv` | Services santé/éduc | Haute |
| `animal_acces_pro` | Accès carnet santé | Haute |
| `ordonnances` | Santé vétérinaire | Haute |
| `comptes_rendus` | Santé / Éduc | Haute |
| `education_progression` | Éducation | Moyenne |
| `lieux_friendly` | Animal Friendly | Haute |
| `evenements` | Événements | Moyenne |
| `evenements_inscrits` | Événements | Moyenne |
| `promenades` | Promenades | Moyenne |
| `promenades_participants` | Promenades | Moyenne |
| `forum_categories` | Communauté | Basse |
| `forum_sujets` | Communauté | Basse |
| `forum_reponses` | Communauté | Basse |
| `groupes` | Communauté | Basse |
| `groupes_membres` | Communauté | Basse |

---

## 12. Pages à créer / modifier

### App Flutter

```
lib/pages/services/
├── services_page.dart           # ✅ EXISTE — grille 6 catégories (ne pas recréer)
├── veterinaires_page.dart       # ✅ EXISTE — 6 sous-pages placeholder (brancher les onTap)
├── service_detail_page.dart     # ⬜ À créer — fiche publique d'un professionnel
└── rdv_booking_page.dart        # ⬜ À créer — prise de RDV côté client

lib/pages/pro/                   # ⬜ Dossier entier à créer
├── pro_profile_edit.dart        # Modifier son profil pro (complète settings/info_utilisateur)
├── pro_agenda.dart              # Agenda RDV (vue pro)
├── pro_rdv_detail.dart          # Détail d'un RDV
├── pro_clients.dart             # Liste des animaux liés / clients
├── pro_carnet_acces.dart        # Consulter le carnet santé d'un animal (avec permission)
└── pro_pension_registre.dart    # Registre entrée/sortie pension (réutilise logique éleveur)

lib/pages/animal_friendly/       # ⬜ Dossier entier à créer
├── friendly_map_page.dart       # Carte lieux pet-friendly (brancher depuis LieuxSympasPage)
├── friendly_detail_page.dart    # Détail d'un lieu
└── friendly_add_page.dart       # Proposer un lieu

lib/pages/evenements/            # ⬜ Dossier entier à créer
├── evenements_page.dart         # Liste + carte (brancher depuis LieuxSympasPage + CommunautePage)
├── evenement_detail_page.dart   # Détail + inscription
└── evenement_create_page.dart   # Création d'événement

lib/pages/promenades/            # ⬜ Dossier entier à créer
├── promenades_page.dart         # (brancher depuis CommunautePage "Balade canine")
├── promenade_detail_page.dart
└── promenade_create_page.dart

lib/pages/communaute/            # ⬜ Dossier entier à créer
├── forum_page.dart              # (brancher depuis CommunautePage "Forums")
├── forum_sujet_page.dart
├── groupes_page.dart            # (brancher depuis CommunautePage "Groupes")
└── groupe_detail_page.dart
```

### Web Next.js — **section entière à créer** (absente du site)

```
src/app/
├── services/
│   ├── page.tsx                 # ⬜ À créer — grille des 6 catégories (miroir app)
│   └── [uid]/page.tsx           # ⬜ À créer — fiche publique pro
├── mon-espace-pro/
│   ├── page.tsx                 # ⬜ Dashboard pro connecté
│   ├── agenda/page.tsx          # ⬜ Agenda + RDV
│   ├── clients/page.tsx         # ⬜ Liste clients/animaux
│   └── pension/page.tsx         # ⬜ Registre pension
├── animal-friendly/
│   └── page.tsx                 # ⬜ Carte + liste lieux
├── evenements/
│   ├── page.tsx                 # ⬜ Liste + carte
│   ├── creer/page.tsx           # ⬜ Création
│   └── [id]/page.tsx            # ⬜ Détail + inscription
├── promenades/
│   ├── page.tsx                 # ⬜ Liste + carte
│   └── [id]/page.tsx            # ⬜ Détail
└── communaute/
    ├── page.tsx                 # ⬜ Hub communauté
    ├── forum/page.tsx           # ⬜ Forum
    └── groupes/page.tsx         # ⬜ Groupes

# Fichier à modifier
src/components/Header.tsx        # ⚠️ Ajouter "Services" dans le menu de navigation
```

---

## 13. Fichiers à ne PAS modifier (appartiennent à l'autre développeur)

```
# App Flutter
lib/pages/eleveur/          (tout le dossier)
lib/pages/admin/            (tout le dossier)
lib/pages/eleveur/animaux/  (tout le dossier)

# Web
src/app/mes-animaux/        (tout le dossier)
src/app/elevage/            (tout le dossier)
src/app/annonces/           (tout le dossier)
```

## Fichiers partagés — coordonner avant de modifier

```
lib/main.dart               # Navigation principale
lib/utils.dart              # Fonctions partagées
src/lib/auth-context.tsx    # Contexte auth web
src/components/Header.tsx   # Navigation web
```

---

## 14. Ordre de développement suggéré

### Phase 1 — Base pro (débloque tout le reste)
1. Enrichir le profil pro (nouveaux champs BDD + UI)
2. Page annuaire services (filtre catégorie + carte)
3. Fiche publique pro

### Phase 2 — Services santé & garde
4. Agenda RDV (pro + client)
5. Notifications rappel RDV
6. Accès carnet santé (permissions)
7. Envoi ordonnances
8. Registre pension

### Phase 3 — Animal Friendly & Événements
9. Carte Animal Friendly (ajout + consultation)
10. Événements (création + inscription)
11. Promenades collectives

### Phase 4 — Communauté
12. Forum (catégories + sujets + réponses)
13. Groupes
