# PetsMatch — Spécifications Projet

> Document de référence commun aux deux dépôts. À mettre à jour à chaque ajout de feature majeure.

---

## 1. Vue d'ensemble

PetsMatch est une plateforme de mise en relation pour l'élevage et l'adoption d'animaux de compagnie.

**Deux applications synchronisées :**
- **App mobile** Flutter (Android/iOS) → `C:\dev\PetsMatch`
- **Site web** Next.js → `C:\dev\petsmatch-web`

**Règle absolue :** toute feature se déploie sur les **deux versions** (app + web). Le design, les couleurs et les comportements doivent être identiques.

---

## 2. Architecture technique

```
Firebase Auth  ──────────────────────────────────────────────────────
  │  UID (clé primaire partout — Auth UNIQUEMENT, pas de données ici)
  │
  ├── Supabase PostgreSQL  (TOUTES les données métier)
  │     users, animaux, annonces, registres, santé, contrats,
  │     factures, alertes, likes, favoris, notifications
  │
  ├── Firestore  (résiduel — à migrer)
  │     • collection "post"        → vieux feed social + boost
  │     • collection "conversations" → messagerie temps réel
  │     • collection "likedPost"   → vieux système likes feed social
  │     • collection "bloquer"     → utilisateurs bloqués
  │
  └── Firebase Storage  (photos profil, photos animaux, documents)
```

> **Important :** Firebase Auth = authentification uniquement. Toutes les données
> doivent être dans Supabase. Les collections Firestore listées ci-dessus sont
> des résidus à migrer progressivement.

**Supabase Edge Functions** (Deno/TypeScript) — `supabase/functions/` :
- `delete-user` : suppression complète d'un compte (Firebase Auth + cascade Supabase)
  → JWT verification **désactivée** dans le dashboard (clé anon format `sb_publishable_` non-JWT)

---

## 3. Stack technique

### App Flutter (`C:\dev\PetsMatch`)

| Catégorie | Librairie | Usage |
|---|---|---|
| Auth | `firebase_auth` | Authentification |
| Base de données | `supabase_flutter` | Toutes les données métier |
| Base de données | `cloud_firestore` | Feed social + messagerie (résiduel, migration prévue) |
| Stockage | `firebase_storage` | Fichiers/photos |
| Cartes | `google_maps_flutter` | Carte élevages/annonces |
| Géocodage | `geocoding`, `geolocator` | Adresse ↔ coords |
| Photos | `image_picker`, `image_cropper` | Sélection + crop carré |
| Paiement | `flutter_stripe` | Abonnements |
| PDF | `pdf`, `printing` | Contrats, registres |
| Notifications | `firebase_messaging`, `flutter_local_notifications` | Push + local |
| UI | `carousel_slider`, `photo_view` | Galeries |

**Font principale :** `Galey` (déclarée dans `pubspec.yaml` → `assets/fonts/`)

### Site web (`C:\dev\petsmatch-web`)

| Catégorie | Librairie | Usage |
|---|---|---|
| Framework | Next.js 16 (App Router) | SSR/SSG |
| Auth | `firebase` (client SDK) | Authentification |
| Base de données | `@supabase/supabase-js` | Données |
| Cartes | `react-leaflet` + `leaflet` | Cartes |
| Style | Tailwind CSS v4 | UI |
| Crop image | `react-image-crop` | Upload photos |

**Contexte auth web :** `src/lib/auth-context.tsx` → hook `useAuth()` retourne `{ user, userData, loading }`

---

## 4. Structure des fichiers

### App Flutter — `lib/`

```
lib/
├── main.dart                        # Entrée app, init Firebase + Supabase
├── app_colors.dart                  # Palette couleurs
├── utils.dart                       # Fonctions utilitaires partagées
├── utils/                           # Helpers (upload, crop, etc.)
├── services/                        # Services métier (alertes, abonnements)
├── animation/                       # Composants animés
└── pages/
    ├── admin/
    │   ├── admin_panel.dart          # Onglets admin
    │   ├── user_list.dart            # Liste utilisateurs + filtres
    │   ├── user_detail.dart          # Détail + actions admin
    │   ├── verification_list.dart    # Demandes vérification éleveurs
    │   └── verification_detail.dart
    ├── eleveur/
    │   ├── eleveur_nav.dart          # Navigation bottom éleveur
    │   ├── animaux/
    │   │   ├── animal_fiche.dart     # Fiche complète animal
    │   │   ├── mes_animaux.dart      # Liste animaux éleveur
    │   │   └── portee_form_page.dart # Formulaire création portée
    │   ├── post/
    │   │   ├── create_annonce_page.dart
    │   │   ├── annonces_feed_page.dart
    │   │   └── mes_annonces_page.dart
    │   └── admin/                   # Gestion élevage
    │       ├── facturation.dart
    │       ├── registre_sanitaire.dart
    │       └── registre_entree_sortie.dart
    ├── particulier/
    │   ├── particulier_nav.dart
    │   ├── mes_animaux_page.dart
    │   └── animaux_perdus_page.dart
    └── settings/
```

### Site web — `src/`

```
src/
├── lib/
│   ├── auth-context.tsx    # useAuth() hook — source de vérité auth
│   ├── supabase.ts         # Client Supabase (import: createClient)
│   ├── firebase.ts         # Config Firebase
│   ├── breeds.ts           # Données races (miroir des JSON Flutter)
│   ├── french-geo.ts       # Villes/codes postaux France
│   ├── compress-image.ts   # Compression avant upload
│   └── upload-media.ts     # Upload vers Firebase Storage
├── components/
│   ├── Header.tsx / Footer.tsx
│   ├── ImageCropModal.tsx  # Crop carré réutilisable
│   └── animaux/HealthSection.tsx
└── app/
    ├── connexion/page.tsx
    ├── inscription/page.tsx
    ├── profil/page.tsx
    ├── mes-animaux/
    │   ├── page.tsx          # Liste animaux
    │   ├── [id]/page.tsx     # Fiche complète animal
    │   └── portee/page.tsx   # Création portée
    ├── annonces/
    │   ├── page.tsx / feed/  / carte/
    │   ├── creer/page.tsx
    │   └── [id]/page.tsx + [id]/modifier/page.tsx
    ├── elevages/page.tsx + [id]/page.tsx
    ├── elevage/              # Espace éleveur connecté
    │   ├── registre-sanitaire/page.tsx
    │   ├── registre-entree-sortie/page.tsx
    │   └── facturation/page.tsx
    ├── animaux-perdus/page.tsx + declarer/page.tsx
    └── messages/page.tsx
```

---

## 5. Base de données

### Supabase (PostgreSQL) — tables principales

| Table | Clé | Description |
|---|---|---|
| `users` | `uid` (Firebase UID) | Profil complet (source de vérité) |
| `animaux` | `id` | Animaux éleveur — `ON DELETE CASCADE` depuis users |
| `animaux_sante` | `animal_id` | Carnet de santé |
| `animaux_vaccins` | `animal_id` | Vaccinations |
| `animaux_poids` | `animal_id` | Courbe de poids |
| `annonces` | `id` | Annonces éleveur (feed, création, modification) |
| `likes` | — | Likes annonces + bébés portée |
| `favoris` | — | Annonces favorites |
| `notifications` | `id` | Notifications in-app |
| `alertes_perdus` | `id` | Animaux perdus |
| `registre_sanitaire` | `id` | Suivi sanitaire élevage |
| `registre_entree_sortie` | `id` | Entrées/sorties |
| `contrats` | `id` | Contrats de vente |
| `factures` | `id` | Facturation |

### Firestore — collections résiduelles (migration à prévoir)

| Collection | Usage actuel | Statut |
|---|---|---|
| `post` | Vieux feed social + boost | À migrer vers Supabase |
| `conversations` | Messagerie temps réel | À migrer (ou garder pour temps réel) |
| `likedPost` | Vieux système likes feed | À supprimer après migration `post` |
| `bloquer` | Utilisateurs bloqués | À migrer vers Supabase |

**Cascade delete :** supprimer `users.uid` supprime tout en cascade.

### Firestore — collections

| Collection | Usage |
|---|---|
| `users` | Miroir partiel du profil (auth + données feed) |
| `posts` | Annonces feed (filtres, like, géo) |
| `conversations` | Messagerie temps réel |

### Champs importants `animaux`

```sql
espece, race, sexe, nom, couleur, identification
type_poil, taille, poids, sterilise, passeport_europeen
pedigree (bool), club_registre, pedigree_lof, pedigree_url
date_naissance, date_entree, date_sortie, statut
provenance_type, provenance_nom, provenance_adresse
nom_pere, puce_pere, nom_mere, puce_mere, date_naissance_mere
importation_ref
photo_url, notes, description
uid_eleveur (FK → users.uid)
```

---

## 6. Design system

### Couleurs principales

| Nom | Hex | Usage |
|---|---|---|
| Vert principal | `#A7C79A` | Headers, boutons primaires |
| Vert foncé | `#6E9E57` | Chips sélectionnés, accents |
| Vert éleveur | `#0C5C6C` | Badge éleveur |
| Fond app | `#F8F8F6` | Background général |
| Fond cards | `#FFFFFF` | Cards |

### Typographie

- **App Flutter :** `Galey` (toujours préciser `fontFamily: 'Galey'` dans TextStyle)
- **Web :** CSS global — `font-family: 'Galey'` déclaré dans `globals.css`

### Composants réutilisables

**Flutter :**
- `_Chip` dans `user_list.dart` — badges colorés avec opacité 0.12
- `FilterChip` avec `selectedColor: Color(0xFF6E9E57)` — filtres standard

**Web :**
- `ImageCropModal` (`src/components/ImageCropModal.tsx`) — crop carré obligatoire sur tout upload photo
- `uploadBlob` dans `upload-media.ts` — upload vers Firebase Storage

---

## 7. Règles métier importantes

### Upload photos
- **Toujours** recadrer en carré avant upload (`image_cropper` app / `ImageCropModal` web)
- Compresser avant upload (`flutter_image_compress` app / `compress-image.ts` web)
- Stocker dans Firebase Storage, sauvegarder l'URL dans Supabase

### Races — fichiers JSON de référence

Les races sont chargées depuis les fichiers JSON dans `assets/` (Flutter) et `src/lib/breeds.ts` (web, miroir).

| Fichier | Espèce |
|---|---|
| `assets/dog_breeds.json` | Chien |
| `assets/cat_breeds.json` | Chat |
| `assets/horse_breeds.json` | Cheval |
| `assets/rabbit_breeds.json` | Lapin |
| `assets/bird_breeds.json` | Oiseau |
| `assets/sheep_breeds.json` | Ovin |
| `assets/goat_breeds.json` | Caprin |
| `assets/pig_breeds.json` | Porcin |
| `assets/nac_breeds.json` | NAC |

**Règle :** ne jamais saisir les races en dur dans le code — toujours lire depuis ces fichiers.

### Authentification
- Auth = Firebase Auth **uniquement**. L'`uid` Firebase est la clé primaire dans Supabase
- Toutes les données métier sont dans **Supabase** — ne pas écrire de nouvelles données dans Firestore
- Sur le web : `useAuth()` donne `user` (Firebase) + `userData` (Supabase)
- `userData.nameElevage`, `userData.rueElevage`, `userData.villeElevage` — infos élevage

### Pluriel "animaux"
- Toujours : `animal${count > 1 ? 'aux' : ''}` (jamais `animalx`)

### Pedigree par espèce
```
chien      → LOF / Non-LOF
chat       → LOOF / Non-LOOF
cheval     → Stud-book / Registre d'élevage / Non-inscrit
lapin      → Livre de race / Non-inscrit
oiseau     → Bagué fermé / Bagué ouvert / Non-bagué
ovin/caprin→ Livre généalogique / Non-inscrit
porcin     → Livre généalogique LG / Non-inscrit
nac        → Registre d'élevage / Non-inscrit
```

### Suivi reproduction — règles métier

**Durée gestation par espèce (pour calcul date de mise bas prévue) :**
```
chien    → 63 jours
chat     → 65 jours
lapin    → 31 jours
cheval   → 340 jours
ovin     → 150 jours
caprin   → 150 jours
porcin   → 114 jours
nac      → variable (à saisir manuellement)
```

**Délai confirmation gestation par espèce (alerte push) :**
```
chien    → J+28 après saillie (écho possible)
chat     → J+21 après saillie
lapin    → J+12 après saillie (palpation)
cheval   → J+14 après saillie (écho)
autres   → à saisir manuellement
```

**Tables BDD nécessaires :**
```sql
CREATE TABLE suivi_repro (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  animal_id       TEXT REFERENCES animaux(id) ON DELETE CASCADE,
  uid_eleveur     TEXT REFERENCES users(uid) ON DELETE CASCADE,
  type_evenement  TEXT NOT NULL,  -- 'chaleurs','saillie','gestation','mise_bas'
  date_debut      DATE,
  date_fin        DATE,           -- fin chaleurs ou date mise bas prévue/réelle
  male_id         TEXT REFERENCES animaux(id) ON DELETE SET NULL,  -- si mâle interne
  male_externe_nom  TEXT,         -- si saillie extérieure
  male_externe_puce TEXT,
  male_externe_race TEXT,
  male_externe_photo_url TEXT,
  male_externe_eleveur_uid TEXT REFERENCES users(uid) ON DELETE SET NULL,
  gestation_confirmee BOOLEAN,
  notes           TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Accès infos mâle entre éleveurs
CREATE TABLE saillie_acces (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  proprietaire_uid TEXT REFERENCES users(uid) ON DELETE CASCADE,  -- éleveur du mâle
  animal_id     TEXT REFERENCES animaux(id) ON DELETE CASCADE,    -- le mâle
  demandeur_uid TEXT REFERENCES users(uid) ON DELETE CASCADE,     -- éleveur demandeur
  statut        TEXT DEFAULT 'en_attente',  -- 'en_attente','accepte','refuse'
  created_at    TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(animal_id, demandeur_uid)
);
```

### Format photos annonces

- **Création/upload :** crop carré obligatoire (cohérence esthétique)
- **Feed :** affichage 4:3 ou 16:9 avec `BoxFit.cover` + `Alignment.center` pour centrer l'animal
- **Ne jamais** étirer ou déformer — utiliser cover + center uniquement
- **Web :** `object-fit: cover; object-position: center;` en CSS

### Prise de photo — règle UX

Sur toutes les pages qui acceptent une photo (fiche animal, portée, documents) :
- Proposer **deux options** : "Prendre une photo" (caméra) ET "Choisir depuis la galerie"
- Flutter : `ImageSource.camera` et `ImageSource.gallery` via `image_picker`
- Web : `<input type="file" accept="image/*" capture="environment">` pour mobile, input classique pour desktop

### Algorithme validation éleveurs — règles

**Score automatique calculé à la soumission :**
```
+20 pts  SIRET fourni et format valide (14 chiffres)
+20 pts  Document élevage uploadé (Kbis ou équivalent)
+15 pts  ACACED renseigné + document uploadé
+15 pts  Photo de l'élevage présente
+10 pts  Adresse complète (rue, ville, code postal)
+10 pts  Numéro d'élevage renseigné
+10 pts  Au moins une espèce élevée renseignée
= 100 pts max
```
- Score ≥ 80 → suggestion "Valider" affichée à l'admin
- Score 50-79 → "Vérification recommandée"
- Score < 50 → "Profil incomplet — demander compléments"

**Détection anomalies annonces :**
- Prix = 0 sur une annonce de vente → signalement automatique
- Race ne correspondant pas à l'espèce sélectionnée → blocage à la publication
- Même éleveur > 10 annonces actives simultanées → vérification admin
- Mots-clés sensibles dans description → file de modération

### Suppression compte (admin)
- Via Edge Function `delete-user` (JWT verification désactivée)
- Supprime : Firebase Auth + Supabase cascade + Firestore doc
- Double confirmation obligatoire (dialog + saisir "SUPPRIMER")

### Gestion des employés d'élevage (A46)

**Tables Supabase requises :**
```sql
CREATE TABLE IF NOT EXISTS employes (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  uid_employe TEXT NOT NULL,
  uid_eleveur TEXT NOT NULL,
  actif       BOOLEAN DEFAULT TRUE NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS taches_elevage (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  titre       TEXT NOT NULL,
  animal_id   TEXT,            -- pas de FK (animaux.id est TEXT)
  uid_eleveur TEXT NOT NULL,
  date        DATE NOT NULL,
  statut      TEXT DEFAULT 'a_faire' NOT NULL,  -- 'a_faire' | 'fait'
  assigne_a   TEXT,            -- uid de l'employé assigné
  notes       TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
```

**Vue éleveur — page "Mes Employés" :**
- Onglet **Employés** : liste des employés actifs avec bouton Révoquer. FAB → recherche et ajout d'un utilisateur (particulier, éleveur ou pro hors pôle santé).
- Onglet **Tâches** : liste des tâches de l'élevage, filtres À faire/Terminées. FAB → créer une tâche (titre*, date*, animal optionnel, assigné à optionnel, notes).
  - Chaque tâche est modifiable (icône crayon) et supprimable.
  - À la création, si une tâche est assignée : notification in-app (Supabase `notifications`) + push FCM via Cloud Function `notifyTacheAssignee`.

**Vue employé — page "Mes Employeurs" :**
- Liste des élevages pour lesquels l'utilisateur travaille (actif = true).
- Clic sur un élevage → `EmployeurDetailPage` avec 2 onglets :
  - **Mes Tâches** : tâches assignées à cet employé par cet éleveur. Bouton "Fait ✓" pour marquer terminée.
  - **Animaux** : liste read-only des animaux de l'élevage (nom, espèce, race, photo).
- Accessible depuis :
  - Menu particulier → "Mes Employeurs"
  - Menu éleveur (section Mon Élevage) → "Mes Employeurs"

**Notifications tâches :**
- `type = 'tache'` dans la table `notifications`
- `data = { eleveurUid: '...', tacheId: '...' }`
- Clic sur la notification → navigue vers `EmployeurDetailPage` de l'éleveur concerné

**Cloud Function `notifyTacheAssignee` :**
- Callable (`europe-west1`)
- Paramètres : `{ assigneUid, titre }`
- Lit le `fcmToken` depuis Firestore `users/{assigneUid}`
- Envoie FCM sur canal `taches`

**Permissions (v1 — à affiner) :**
- L'employé voit tous les animaux de l'éleveur (lecture seule)
- L'employé peut marquer ses tâches comme "fait"
- L'éleveur contrôle quelles sections sont accessibles (suivi repro, carnet santé, identité) — à implémenter en v2

### Portée → Registre entrée/sortie
- `provenance_type` = `'naissance'`
- `provenance_nom` = nom de l'élevage (`name_elevage`)
- `provenance_adresse` = adresse élevage (`rue_elevage` + `ville_elevage`)
- Mère = animal sélectionné dans le formulaire portée

---

## 8. Variables d'environnement / Config

### App Flutter (`lib/main.dart`)
- Supabase URL + anon key initialisés au démarrage
- Firebase options dans `firebase_options.dart` (généré par FlutterFire CLI)
- Clé Google Maps dans `android/app/src/main/AndroidManifest.xml`

### Web (`src/lib/`)
- `firebase.ts` — config Firebase client
- `supabase.ts` — URL + anon key Supabase
- Variables `.env.local` pour les clés sensibles (ne jamais committer)

### Supabase Edge Functions
- Secret `FIREBASE_SERVICE_ACCOUNT` : JSON du compte de service Firebase
- Configurer dans : Supabase Dashboard → Project Settings → Edge Functions → Secrets

---

## 9. Ce qu'il ne faut PAS faire

- ❌ Ne jamais exposer la Service Role Key Supabase côté client
- ❌ Ne jamais committer `.env.local` ou les fichiers de clés Firebase
- ❌ Ne jamais utiliser `setState` dans un `StatelessWidget` Flutter
- ❌ Ne jamais oublier le crop carré sur les photos
- ❌ Ne jamais implémenter une feature sur un seul repo sans prévoir l'autre
- ❌ Ne jamais utiliser `animalx` — toujours `animaux`
