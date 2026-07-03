# Specs PetsMatch — Fonctionnalités à implémenter
> Dernière mise à jour : 2026-07-03 — §19.4 espèces/filtres, dashboard disponibilité, clic-planning→réservation, fiche animal sans compte + lien de réclamation, journal de séjour  
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
16. [Lieux Pet-Friendly — Hôtels, Hébergements & Restaurants](#16-lieux-pet-friendly--hôtels-hébergements--restaurants)
17. [Promenades collectives — Améliorations](#17-promenades-collectives--améliorations)
18. [PetFriends — Réseau social propriétaires](#18-petfriends--réseau-social-propriétaires)
19. [Module Pension — État d'avancement](#19-module-pension--état-davancement-session-2026-07-02)

---

## 1. Profil Association

### 1.1 Périmètre

Un profil Association est quasi-identique au profil Éleveur avec les différences suivantes :

| Fonctionnalité | Éleveur | Association | Statut Web |
|---|---|---|---|
| Animaux (fiche complète) | ✅ | ✅ | ✅ `/association/animaux` (filtre `is_association`) — scanner puce intégré (filtre asso strict) |
| Généalogie / arbres | ✅ | ❌ | — |
| Suivi repro (saillie, gestation…) | ✅ | ❌ | — |
| Portées | ✅ | ❌ | — |
| Annonces vente | ✅ | ❌ → Annonces adoption | ✅ `/association/annonces` (filtre `profil_source='association'`) |
| Certificat d'engagement | ✅ obligatoire | ✅ obligatoire | ✅ `/association/certificat-engagement` (filtre `profil_source`) |
| Contrats d'adoption | ❌ | ✅ par espèce | ✅ `/association/contrat` (type `contrat_adoption`, participation auto) |
| Agenda | ✅ | ✅ | ✅ `/association/agenda` (filtre `profil_source`) |
| Planning / Protocoles | ✅ | ✅ | ✅ `/association/planning` (filtre `profil_source`) |
| Suivi sanitaire | ✅ | ✅ | ✅ `/association/registre-sanitaire` (filtre `profil_source`) |
| Registre entrées/sorties | ✅ | ✅ | ✅ `/association/registre-entree-sortie` (filtre `is_association`) |
| Gestion bénévoles + employés | ❌ | ✅ | ✅ `/association/equipe` — liste unifiée, badges 👔 Employé / 🤝 Bénévole, recherche PetsMatch, affectation tâches |
| Gestion employés | ✅ | ❌ | ✅ `/employes` (profil éleveur) |
| Chenil / Enclos | ❌ | ✅ | ✅ `/association/chenil` (table `enclos_chenil`) |
| Planning chenil semaine | ❌ | ✅ | ✅ onglet dans chenil page |
| Inventaire | ✅ | ✅ | ✅ `/association/inventaire` (re-export éleveur) |
| Facturation | ✅ | ✅ | ✅ `/association/facturation` (filtre Firestore `profilSource`) |
| RDV | ✅ | ✅ | ✅ `/mes-rdv` (filtre `pro_profile_id`) |
| Tâches assignées | ✅ | ✅ | ✅ `/mes-taches` (filtre `profil_source` via `useProfileSource`) |
| Familles d'accueil (FA) | ❌ | ✅ | ✅ `/association/familles-accueil` — recherche utilisateur PetsMatch, `fa_uid` lié, badge 🐾 PetsMatch |

### 1.2 Champs du profil

```
Nom de l'association        (obligatoire)    ← ✅ App + Web
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
Photo de l'association + bannière  ← ✅ App (profil_association_edit) + migration_user_profiles_banner.sql
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

### 1.5 Contrat d'adoption (ADOP01 — ✅ Web implémenté)

**Page :** `/association/contrat`

Contrat spécifique aux associations, distinct du contrat de vente éleveur.

**Participation aux frais par espèce (valeurs par défaut modifiables) :**

| Espèce | Participation défaut |
|---|---|
| Chien | 150 € |
| Chat | 100 € |
| Cheval | 500 € |
| Lapin | 50 € |
| Oiseau | 30 € |
| Ovin / Caprin / Porcin | 80 € |
| Autre | 50 € |

**Contenu du contrat (6 articles) :**
1. Parties (association + adoptant)
2. Identification de l'animal
3. Participation aux frais (montant)
4. Engagements de l'adoptant (bien-être, soins, non-revente…)
5. Droits de l'association (visite de contrôle, reprise en cas de manquement)
6. Retour de l'animal (procédure si l'adoptant ne peut plus garder l'animal)
7. Clause stérilisation (optionnelle, affichée si animal non stérilisé)

**Génération :** `src/lib/contrat-adoption.ts` → `generateContratAdoptionHTML()`  
**Stockage :** table `documents_animaux` avec `type = 'contrat_adoption'`  
**Signature :** via `/signer-contrat/[token]` (infrastructure commune)

**Recherche acquéreur :** champ adresse avec **autocomplete adresse.data.gouv.fr** + mini-carte OSM (voir §1.7)

### 1.6 Isolation multi-profil (MPRO01 — ✅ Web implémenté)

Un utilisateur peut avoir simultanément un profil éleveur (compte principal) et un profil association (profil secondaire `user_profiles`). Ils partagent le même `uid` Firebase.

**Mécanisme d'isolation :**

| Table | Colonne de distinction | Valeurs |
|---|---|---|
| `animaux` | `is_association` | `true` = asso, `false`/NULL = éleveur |
| `annonces` | `profil_source` | `'association'` ou absent |
| `taches_elevage` | `profil_source` | `'eleveur'` (défaut) ou `'association'` |
| `plan_templates` | `profil_source` | `'eleveur'` (défaut) ou `'association'` |
| `plans_actifs` | `profil_source` | `'eleveur'` (défaut) ou `'association'` |
| `plan_taches` | `profil_source` | `'eleveur'` (défaut) ou `'association'` |
| `certificats_engagement` | `profil_source` | `'eleveur'` (défaut) ou `'association'` |
| `registre_sanitaire` | `profil_source` | `'eleveur'` (défaut) ou `'association'` |
| `employes` | `type` | NULL/absent = employé, `'benevole'` = bénévole asso |
| Facturation (Firestore) | `profilSource` | `'eleveur'` ou `'association'` |
| `enclos_chenil` | `is_association` | `true` = asso |
| `documents_animaux` | `type` | `'contrat_adoption'` = asso, autres = éleveur |

**Migration SQL :** `supabase/migration_profil_source_multi.sql`

**Détection du contexte actif (web) :**
- Pages sous `/association/*` → `usePathname().startsWith('/association')` → `profilSource = 'association'`
- Page `/mes-taches` (globale) → hook `useProfileSource()` qui interroge `user_profiles` via `localStorage` (ID stocké par `useActiveProfile`)

**Redirect HomeDashboard :** si `activeProfile.profile_type === 'association'` → `/association`

### 1.7 Autocomplete adresse (ADDR01 — ✅ Web implémenté)

**Composant :** `src/components/AddressAutocomplete.tsx`

- API **adresse.data.gouv.fr** (gratuite, sans clé, France uniquement)
- Autocomplete dès 3 caractères, debounce 350 ms
- Mini-carte **OpenStreetMap** iframe inline après sélection (pin sur l'adresse)
- Composant contrôlé : pas de re-recherche quand l'adresse est pré-remplie depuis PetsMatch

**Utilisé dans :**
- `/elevage/contrat` — adresse acquéreur (saisie manuelle)
- `/elevage/certificat-engagement` — adresse acquéreur
- `/association/contrat` — adresse adoptant

**Auto-remplissage PetsMatch :** quand un utilisateur PetsMatch est sélectionné comme acquéreur :
- Priorité à l'adresse personnelle (`rue`, `code_postal`, `ville`)
- Fallback sur `rue_elevage` / `code_postal_elevage` / `ville_elevage` si champs personnels vides
- Cas d'usage : un éleveur peut adopter un chien pour usage privé (garde) → adresse personnelle utilisée, pas l'adresse d'élevage

### 1.8 Familles d'accueil (FA) — ✅ App + Web implémenté

**Table :** `familles_accueil` — colonnes : `association_uid`, `fa_uid` (nullable, UID PetsMatch), `prenom`, `nom`, `email`, `telephone`, `adresse`, `ville`, `code_postal`, `capacite_max`, `notes`, `actif`

**App Flutter :** `familles_accueil_page.dart` — liste FA avec animaux en cours, sheet ajout avec recherche PetsMatch (`fa_uid` auto-rempli + infos contact)  
**Web Next.js :** `/association/familles-accueil` — même logique, recherche dropdown PetsMatch, badge 🐾 sur les FA liées, compteur animaux/capacité

- Réseau de FA lié à l'association
- FA optionnellement liée à un utilisateur PetsMatch existant (`fa_uid`)
- L'association peut affecter un animal à une FA (champ `fa_id` sur `animaux`)
- Suivi de l'animal pendant le placement (bilans, photos)
- L'animal reste propriété de l'association côté BDD jusqu'à l'adoption définitive

**Implémenté (2026-06-20 → 2026-06-23) :**
- ✅ Vue FA : page dédiée `AnimauxEnAccueilPage` (Flutter) et `/mes-animaux-accueil` (Web) — visible uniquement si l'utilisateur est FA actif, bandeau + cartes animaux en accueil
- ✅ Menu "Animaux en accueil" conditionnel dans le drawer app et header web (vérifié via `familles_accueil.fa_uid`)
- ✅ Notification in-app (`animal_en_accueil`) envoyée lors du placement d'un animal dans une FA
- ✅ Modifier + Placer un animal : boutons sur les cartes FA (app + web)
- ✅ Retirer un animal d'une FA : chip cliquable → statut repasse en `en_soin`, `date_sortie` renseignée
- ✅ Adresse auto-remplie depuis le profil PetsMatch lors de la sélection d'un utilisateur (`rue`, `ville_elevage`, `code_postal_elevage`)

**À faire (v2) :**
- Bilans/photos depuis l'app de la FA
- Notifications FA lors des changements de statut de l'animal (retour, adoption)

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
- **CERT01** ✅ Implémenté web (éleveur + association)
- **CERT02** 🔜 V2 — Signature numérique canvas (app + web)

**V1 — CERT01 (implémenté)**

*Web Next.js :*
- Page `/elevage/certificat-engagement` : liste des certificats + création (éleveur)
- Page `/association/certificat-engagement` : idem, filtrée `profil_source='association'` + animaux `is_association=true`
- Formulaire pré-rempli (profil cédant + sélection animal depuis Supabase)
- **Autocomplete adresse** acquéreur (api-adresse.data.gouv.fr + mini-carte OSM) — voir §1.7
- **Auto-remplissage PetsMatch** : priorité adresse personnelle, fallback adresse élevage
- PDF généré via `window.print()` + CSS print (pas de dépendance supplémentaire)
- Token de signature unique (UUID) stocké en DB
- Lien de signature `/signer-contrat/[token]` (page commune à tous les types de documents)
- Page acquéreur : lecture + canvas signature double (cédant + acquéreur)
- Statuts : `envoye` → `lu` → `signe` / `refuse`
- Gating : Pro + Premium uniquement (éleveurs)
- **Isolation multi-profil** : colonne `profil_source` sur `certificats_engagement`

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

### 3.1 Principe — ✅ Isolation implémentée

Les annonces d'associations **ne sont pas mélangées** aux annonces éleveurs/particuliers. Elles ont :

> **Fix 2026-06-22 :** "Fil éleveurs" retiré du drawer association — les annonces d'élevage ne s'affichent plus dans le contexte association. Filtre `profil_source = 'association'` appliqué côté client dans `annonces_asso_feed_page.dart`.
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

**Permissions granulaires (table `employe_permissions`) — ✅ Implémenté (2026-06-29)**

Clés : `eleveur_profile_id` + `employe_profile_id` + `permission` (une ligne par permission accordée)

| Permission | Effet App | Effet Web |
|---|---|---|
| `write_animaux` | `readOnly: false` sur fiche animal | Bouton "Modifier" identité visible |
| `write_sante` | idem (inclus dans `write_animaux`) | Boutons `+` Carnet Santé actifs |
| `write_repro` | Onglet Repro éditable (`_tabReadOnly`) | Onglet Repro éditable |
| `write_planning` | Créer/modifier tâches | Créer/modifier tâches |
| `write_inventaire` | Gérer inventaire | Gérer inventaire |
| `write_notes` | Ajouter notes | Ajouter notes |

**UI d'attribution des permissions :**
- App mobile : bouton ⚙️ "Gérer les accès" sur chaque employé → bottom sheet avec toggles → écrit dans `employe_permissions`
- Web : à implémenter dans `/elevage/employes`

**Comportement implémenté :**
- Employé : tap sur un animal dans `MesEmployeurs` → `readOnly = !perms.contains('write_animaux')`
- Bénévole : animaux association dans `MesAssociations` → filtrés par `animaux_proprietes.profile_id_proprio = eleveur_profile_id`
- Cession/Adoption : **bloquée** pour employés et bénévoles (bouton masqué)
- Profil mixte : animaux élevage séparés des animaux association via `profile_id_proprio` dans `animaux_proprietes` (pas `is_association`)

### 5.3 Invitation et onboarding — ✅ Implémenté (in-app)

- ✅ **Ajout via recherche PetsMatch** : éleveur et association invitent un utilisateur existant (app + web)
- ✅ **Notification in-app** (`employee_invite`) envoyée immédiatement à l'ajout
- ✅ **Révocation** : désactivation `actif = false` + notification `employee_revoked` à l'employé/bénévole
- ✅ **Bénévole manuel** : saisie sans compte PetsMatch (pas de notification, pas de `uid_employe`)
- Invitation par email (HOST02 — bloqué en attendant hébergement prod)

### 5.4 Planning employés — ✅ Partiellement implémenté

- Chaque employé a ses **créneaux de travail** (type créneaux_pro mais pour les salariés)
- Vue planning hebdomadaire : qui est présent quel jour/heure
- Affectation : quel soigneur s'occupe de quel animal / quelle chambre
- ✅ **Notifications aux soigneurs** pour les tâches assignées : notification `tache` envoyée à l'assigné (app + web éleveur + web association)

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

> **Migrations exécutées :** `migration_chenil_enclos.sql`, `migration_profil_source_multi.sql`, `migration_annonces_profil_source.sql`  
> **Migrations en attente d'exécution dans Supabase Dashboard** : voir dossier `supabase/`

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

-- 9. Enclos / Chenil association (✅ migration_chenil_enclos.sql)
CREATE TABLE IF NOT EXISTS enclos_chenil (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  uid_eleveur TEXT NOT NULL,
  is_association BOOLEAN DEFAULT false,
  nom TEXT NOT NULL,
  type TEXT DEFAULT 'box',     -- box / enclos / chatterie / cage
  capacite INTEGER DEFAULT 1,
  dernier_nettoyage DATE,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
-- Lien animal → enclos
ALTER TABLE animaux ADD COLUMN IF NOT EXISTS enclos_id UUID REFERENCES enclos_chenil(id) ON DELETE SET NULL;

-- 10. Colonnes isolation multi-profil (✅ migration_profil_source_multi.sql)
ALTER TABLE taches_elevage         ADD COLUMN IF NOT EXISTS profil_source TEXT DEFAULT 'eleveur';
ALTER TABLE plan_templates         ADD COLUMN IF NOT EXISTS profil_source TEXT DEFAULT 'eleveur';
ALTER TABLE plans_actifs           ADD COLUMN IF NOT EXISTS profil_source TEXT DEFAULT 'eleveur';
ALTER TABLE plan_taches            ADD COLUMN IF NOT EXISTS profil_source TEXT DEFAULT 'eleveur';
ALTER TABLE certificats_engagement ADD COLUMN IF NOT EXISTS profil_source TEXT DEFAULT 'eleveur';
ALTER TABLE registre_sanitaire     ADD COLUMN IF NOT EXISTS profil_source TEXT DEFAULT 'eleveur';
-- Facturation : champ Firestore `profilSource` (pas de migration SQL)
-- Bénévoles : champ existant `type = 'benevole'` dans table `employes`

-- 11. Employés / bénévoles (table existante)
-- Employés éleveur : type IS NULL ou absent
-- Bénévoles asso  : type = 'benevole'
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

| Code | Description | App Flutter | Site Web | Admin |
|---|---|---|---|---|
| ASSO01 | Profil association | ✅ inscription + profil | ✅ `/association` (dashboard, layout) | 🔜 validation |
| ASSO02 | Animaux association | ✅ fiche animal asso | ✅ `/association/animaux` (filtre `is_association`) | 🔜 |
| ASSO03 | Annonces adoption | ✅ feed + annonce | ✅ `/association/annonces` (filtre `profil_source`) | 🔜 modération |
| ASSO04 | Candidatures adoption | 🔜 | 🔜 formulaire web | 🔜 |
| ASSO05 | Familles d'accueil | 🔜 | ✅ `/association/familles-accueil` | ❌ |
| ADOP01 | Contrat d'adoption | 🔜 | ✅ `/association/contrat` (6 articles, participation/espèce) | ❌ |
| CHEL01 | Gestion enclos/chenil | 🔜 | ✅ `/association/chenil` (table `enclos_chenil`) | ❌ |
| MPRO01 | Isolation multi-profil | 🔜 | ✅ colonne `profil_source` sur 6 tables | ❌ |
| ADDR01 | Autocomplete adresse | 🔜 | ✅ composant `AddressAutocomplete` (adresse.gouv.fr + OSM) | ❌ |
| CERT01 | Certificat engagement | 🔜 | ✅ éleveur + association (`profil_source`) | 🔜 |
| CERT02 | Signature numérique canvas | ✅ canvas app | ✅ `/signer-contrat/[token]` (canvas double) | ❌ |
| PLAN01 | Config enclos / lieux | 🔜 | ✅ via chenil page | 🔜 |
| PLAN02 | Planning chenil semaine | 🔜 | ✅ onglet chenil | 🔜 |
| PLAN03 | Auto RDV → chambre | 🔜 | 🔜 | ❌ |
| PLAN04 | Stats occupation | 🔜 | 🔜 | 🔜 |
| EMP01 | Invitation + permissions employés | ✅ `employes_page` + `_PermissionsSheet` (table `employe_permissions`) | ✅ `/mes-animaux/:id` (canWrite, canWriteSante, write_repro) | ❌ UI permissions web à faire |
| BEN01 | Gestion bénévoles | ✅ `mes_associations_benevole` (onglets animaux/tâches, tap readOnly) | ✅ `/mes-associations` (animaux cliquables → fiche) | ❌ |
| EMP02 | Planning soigneurs | 🔜 | 🔜 | ❌ |
| EMP03 | Affectation soigneurs | 🔜 | 🔜 | ❌ |
| **PFP01** | Migrations SQL — `petfriendly_places`, `petfriendly_reviews`, `place_likes`, `place_favoris` | 🔜 Backend | 🔜 | 🔜 |
| **PFP02** | RLS policies pet-friendly | 🔜 | 🔜 | 🔜 |
| **PFP03** | API geocoding (adresse → lat/lng) | 🔜 | 🔜 | ❌ |
| **PFP04** | API nearest places (rayon + filtres) | 🔜 | 🔜 | ❌ |
| **PFP05** | Trigger recalcul `note_moyenne` + `nb_avis` | 🔜 | 🔜 | ❌ |
| **PFP06–08** | Formulaire inscription pro 3 étapes | 🔜 | 🔜 | ❌ |
| **PFP09** | Choix plan + Stripe essai 14j | 🔜 | 🔜 | ❌ |
| **PFP10–11** | Validation admin + email confirmation | 🔜 | 🔜 | 🔜 |
| **PFP12** | Page "Mon établissement" édition post-validation | 🔜 | 🔜 | ❌ |
| **PFP13–17** | Page profil public établissement (bannière, horaires, infos pet-friendly) | 🔜 | 🔜 | ❌ |
| **PFP18–21** | Feed `/lieux-pet-friendly` + filtres + tri | 🔜 | 🔜 | ❌ |
| **PFP22** | Carte interactive (marqueurs) | 🔜 | 🔜 | ❌ |
| **PFP23–25** | Likes & favoris + vue "qui a liké" | 🔜 | 🔜 | ❌ |
| **PFP26–30** | Avis + réponse pro + contestation + admin | 🔜 | 🔜 | 🔜 |
| **PFP31–32** | Navigation GPS (Waze + Google Maps) | 🔜 | 🔜 | ❌ |
| **PFP33–35** | Paiement Stripe + gestion abonnement + expiration | 🔜 | 🔜 | ❌ |
| **PFP36–37** | Dashboard stats pro + notifications pro | 🔜 | 🔜 | ❌ |
| **PFP38–40** | Tarification admin — seed SQL + vue admin + lecture dynamique | 🔜 | 🔜 | 🔜 |

---

## 8. Modèle économique — Abonnements, Boosts & Marketplace

### 8.1 Grilles tarifaires par profil

> Les prix et features de chaque plan doivent être modifiables via le panel admin sans déploiement. Stocker dans une table Supabase `plans_tarifaires` (voir §8.4).
>
> **Plomberie de paiement générique (livrée 2026-07-03)** : `/api/stripe/checkout`, `/api/stripe/activate` et `/api/stripe/portal` sont profil_type-aware — le price ID Stripe est lu depuis `plans_tarifaires` (scopé `profil_type`+`plan_code`), et l'activation d'un abonnement n'affecte que les abonnements actifs du même `profil_type` (un compte peut avoir un abonnement éleveur ET un abonnement pension simultanément sans collision). Pour activer le paiement d'un nouveau type de profil (véto, éducateur, etc.) : seeder ses lignes dans `plans_tarifaires`, puis saisir le prix depuis `/admin` → Tarification — le produit et le prix Stripe sont créés automatiquement (`getOrCreatePlanProduct`), **plus besoin d'ouvrir le dashboard Stripe manuellement**. Aucun code à écrire.

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
  profil_type TEXT NOT NULL,       -- eleveur/veterinaire/pension/education/petsitter/promeneur/photographe/para_medical/petfriendly
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
| DOC07 | Contrats web depuis app + Mes Contrats particulier + clause stérilisation | App + Web | ✅ Livré 2026-06-20 |
| DOC08 | Cession — droits acquéreur + animal dans Mes Animaux + notifications | App + Web | ✅ Livré 2026-06-23 |

**Notes DOC01-DOC02 :**
- Web `/elevage/contrat/page.tsx` : migré Firestore → Supabase `documents_animaux`, sélecteur animal, génération dynamique via `generateContratHTML`, types vente/reservation/cession
- App `contrat_reservation.dart` : migré Firestore → Supabase `documents_animaux`, sélecteur animal, génération PDF via `genererContratPDF`, recherche acquéreur PetsMatch
- **MIGRATION SQL À APPLIQUER dans Supabase** : `supabase/migration_documents_animaux.sql`

**Notes DOC07 :**
- App Administratif/Contrats : suppression PDF non-éditable → "Créer & ouvrir sur le web" (save Supabase + token + ouverture navigateur), boutons Ouvrir/Copier lien sur cartes existantes, clause stérilisation optionnelle (Tranche 2) pour contrats de vente
- App fiche animal onglet Documents : boutons Ouvrir & Copier lien via `kSiteBaseUrl/signer-contrat/[token]`
- App menu particulier : nouvelle section Administratif → Mes Contrats (`MesContratsParticulierPage`) — filtre `metadata->>acquereur_email`, affiche statuts, bouton "Consulter & signer"
- Web `/mes-contrats` : page particulier, même logique filtre email, lien vers `/signer-contrat/[token]`
- Web Header particulier : section Administratif → Mes Contrats
- Web contrat de vente : checkbox clause stérilisation (Tranche 2) ; stockée en `metadata.avec_sterilisation` ; lue dans `/signer-contrat/[token]` pour affichage conditionnel Article 2
- Web `proxy.ts` : renommage de `middleware.ts` → `proxy.ts` (convention Next.js 16) ; `turbopack.root` conservé pour résoudre conflit lockfiles Flutter/Next.js
- Config app : `kSiteBaseUrl` dans `lib/config.dart` (IP locale tests → domaine production)

**Notes DOC08 — Cession acquéreur (2026-06-23) :**
- Après validation des deux signatures : `uid_acquereur` est renseigné dans `animaux`, `statut = 'sorti'`
- **Acquéreur** : animal visible dans **Mes Animaux** (pas de page séparée), droits d'écriture complets (`readOnly: false`)
- **Éleveur/asso cédant** : animal dans Sorties, fiche en lecture seule (`isCededByMe = uid_eleveur === user AND uid_acquereur != null AND statut = 'sorti'`)
- Notifications :
  - `cession_signature_demandee` → acquéreur reçoit lien `/signer-contrat/[token]` cliquable (app + web)
  - `cession_confirmee` → redirige vers Mes Animaux (app + web)
  - `contrat_signe_acquereur` / `cession_signe_acquereur` → éleveur voit "Confirmer la cession →" dans header web
- Web `isOwner = uid_eleveur === user OR uid_acquereur === user` — boutons Modifier/Céder accessibles à l'acquéreur
- Associations : cession/adoption désormais activée (bouton "Proposer à l'adoption" au lieu de "Céder")

**Règle saillie — réservée aux éleveurs professionnels (2026-06-23) :**
- `TrouverCompagnonPage` (app) : section "Saillies disponibles" masquée pour particuliers (`!User_Info.isElevage`) → bloc grisé cadenas + message réglementaire
- `annonces_feed_page.dart` : filtre "Saillie" grisé avec icône 🔒 ; tap → dialog "Accès restreint — réservé éleveurs pro"
- Si `typeFilter: 'saillie'` passé directement à non-éleveur : plein écran de restriction
- Web `annonces/page.tsx` : gate affiché à la place des résultats si `filtreType === 'saillie' && !isEleveur`
- Web `annonces/feed/page.tsx` : bouton Saillie `cursor-not-allowed` + `title` tooltip
- Web `annonces/carte/page.tsx` : même traitement sur les filtres de la carte

### 9bis.5 Intégration YouSign — Modèle économique & Quotas (SIGN01)

> ⛔ **AUCUN ABONNEMENT YOUSIGN SOUSCRIT À CE JOUR (2026-06-21)**  
> Ne pas souscrire pendant la phase de développement pour ne pas payer inutilement.  
> **À souscrire juste avant la release production** — bloquer cette étape comme prérequis de la mise en ligne.

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

## 9ter. Préparation YouSign — Audit complet & Roadmap

> **Objectif** : quand l'abonnement YouSign sera pris, il ne restera qu'à renseigner les clés API, implémenter `YouSignProvider`, configurer les webhooks et tester. Tout le reste doit déjà être en place.

### 9ter.1 — Ce qui existe déjà ✅

**Table `documents_animaux` (Supabase)**
| Champ | Type | Usage |
|-------|------|-------|
| `id` | UUID | Clé primaire |
| `animal_id` | TEXT FK | Lien vers l'animal |
| `uid_eleveur` | TEXT | Propriétaire du contrat |
| `type` | TEXT | contrat_vente / contrat_reservation / certificat_cession / certificat_engagement |
| `titre` | TEXT | Titre lisible |
| `token` | UUID unique | Lien de partage `/signer-contrat/[token]` |
| `statut` | TEXT | brouillon / en_attente / signe / archive |
| `url` | TEXT | URL Supabase Storage (PDF ou HTML signé uploadé) |
| `signe_le` | TIMESTAMPTZ | Date signature complète |
| `metadata` JSONB | — | acquereur_nom/email/tel/adresse, prix, date_cession, notes, signature_eleveur (base64), signature_acquereur (base64), signe_eleveur_le, signe_acquereur_le, avec_sterilisation |
| `created_at` | TIMESTAMPTZ | — |

**Génération de contrats**
- ✅ `generateContratHTML()` — contrat de vente (8 articles, adapté par espèce, clause stérilisation optionnelle)
- ✅ `generateContratReservationHTML()` — contrat de réservation
- ✅ `generateCertificatCessionHTML()` — certificat de cession
- ✅ `contrat_pdf.dart` — PDF Flutter pour impression (champs manuels)

**Signature canvas (SIGN00)**
- ✅ Page `/signer-contrat/[token]` — iframe contrat HTML + deux pads canvas (éleveur + acquéreur)
- ✅ Signatures sauvegardées en base64 dans `metadata`
- ✅ Horodatage par signataire (`signe_eleveur_le`, `signe_acquereur_le`)
- ✅ Statut automatique `signe` + `signe_le` quand les deux ont signé

**UI**
- ✅ Page `/mes-contrats` web (particuliers) — filtre `metadata->acquereur_email`
- ✅ `MesContratsParticulierPage` Flutter — même logique
- ✅ Page `/elevage/contrat` web éleveur — création + liste
- ✅ `contrat_reservation.dart` Flutter — création "Créer & ouvrir sur le web" + liste
- ✅ Fiche animal onglet Documents — boutons Ouvrir/Copier lien via token
- ✅ Statuts affichés : brouillon, en_attente, signe, archive
- ✅ Bandeau statut sur page signature

**Config**
- ✅ `kSiteBaseUrl` dans `lib/config.dart` — URL de base pour les liens app → web

---

### 9ter.2 — Ce qui doit être ajouté AVANT YouSign 🔨

#### A. Base de données

**Colonnes manquantes dans `documents_animaux` :**
```sql
ALTER TABLE documents_animaux
  ADD COLUMN IF NOT EXISTS expires_at        TIMESTAMPTZ,          -- expiration lien signature
  ADD COLUMN IF NOT EXISTS cancelled_at      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rejection_reason  TEXT,
  ADD COLUMN IF NOT EXISTS pdf_original_url  TEXT,                 -- PDF généré avant signatures
  ADD COLUMN IF NOT EXISTS pdf_signe_url     TEXT,                 -- PDF final avec signatures injectées
  ADD COLUMN IF NOT EXISTS yousign_id        TEXT;                 -- ID requête YouSign (future)
```

**Statuts manquants à supporter dans le code :**
- `partiellement_signe` — au moins un signataire a signé, pas tous
- `annule` — contrat annulé par l'éleveur
- `expire` — lien de signature expiré (ex. 30 jours)
- `refuse` — acquéreur a refusé

**Nouvelle table `contract_signers` (multi-signataires) :**
```sql
CREATE TABLE contract_signers (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  document_id  UUID REFERENCES documents_animaux(id) ON DELETE CASCADE,
  role         TEXT NOT NULL,    -- vendeur | acquereur | co_eleveur | temoin | veterinaire
  nom          TEXT NOT NULL,
  email        TEXT,
  ordre        INTEGER DEFAULT 1, -- ordre de signature si séquentiel
  statut       TEXT DEFAULT 'en_attente',  -- en_attente | signe | refuse
  signe_le     TIMESTAMPTZ,
  signature_b64 TEXT,            -- canvas base64 (SIGN00) ou null si YouSign
  yousign_signer_id TEXT,        -- ID signataire YouSign (future)
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
```

**Nouvelle table `contract_audit` (historique) :**
```sql
CREATE TABLE contract_audit (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  document_id  UUID REFERENCES documents_animaux(id) ON DELETE CASCADE,
  action       TEXT NOT NULL,    -- created | modified | sent | viewed | signed | refused | cancelled | downloaded | expired
  actor_uid    TEXT,             -- uid Firebase de l'acteur (null si acquéreur non-inscrit)
  actor_email  TEXT,
  actor_role   TEXT,             -- eleveur | acquereur | admin
  details      JSONB,            -- infos contextuelles (IP, user-agent, champ modifié...)
  created_at   TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX ON contract_audit(document_id, created_at DESC);
```

#### B. Architecture services (Web — TypeScript)

**`website/src/lib/signature/SignatureProvider.ts`** — interface abstraite :
```typescript
export interface SignatureProvider {
  createSignatureRequest(doc: ContractDoc): Promise<string>;   // returns requestId
  addSigner(requestId: string, signer: Signer): Promise<void>;
  sendSignatureRequest(requestId: string): Promise<void>;
  getSignatureStatus(requestId: string): Promise<SignatureStatus>;
  downloadSignedDocument(requestId: string): Promise<Blob>;
  cancelSignatureRequest(requestId: string): Promise<void>;
}

export type SignatureStatus = 'pending' | 'partial' | 'signed' | 'refused' | 'cancelled' | 'expired';
export interface Signer { nom: string; email: string; role: string; ordre?: number; }
export interface ContractDoc { id: string; titre: string; htmlContent: string; }
```

**`website/src/lib/signature/CanvasSignatureProvider.ts`** — encapsule le canvas actuel (SIGN00).

**`website/src/lib/signature/YouSignProvider.ts`** — stub vide prêt à implémenter :
```typescript
export class YouSignProvider implements SignatureProvider {
  constructor(private apiKey: string) {}
  async createSignatureRequest(_doc: ContractDoc): Promise<string> { throw new Error('YouSign non configuré'); }
  async addSigner(_requestId: string, _signer: Signer): Promise<void> { throw new Error('YouSign non configuré'); }
  async sendSignatureRequest(_requestId: string): Promise<void> { throw new Error('YouSign non configuré'); }
  async getSignatureStatus(_requestId: string): Promise<SignatureStatus> { throw new Error('YouSign non configuré'); }
  async downloadSignedDocument(_requestId: string): Promise<Blob> { throw new Error('YouSign non configuré'); }
  async cancelSignatureRequest(_requestId: string): Promise<void> { throw new Error('YouSign non configuré'); }
}
```

**`website/src/lib/ContractService.ts`** — logique métier centralisée (création, annulation, statut).

**`website/src/lib/ContractStorageService.ts`** — upload/download Supabase Storage.

#### C. API endpoints (stubs vides, à activer avec YouSign)

| Endpoint | Méthode | Usage |
|----------|---------|-------|
| `/api/contracts/[id]/cancel` | POST | Annuler un contrat |
| `/api/contracts/[id]/audit` | GET | Historique des actions |
| `/api/contracts/[id]/download-pdf` | GET | Télécharger PDF signé |
| `/api/yousign/create` | POST | **Stub vide** — créer requête YouSign |
| `/api/yousign/webhook` | POST | **Stub vide** — recevoir événements YouSign |

#### D. UI manquante

**Page signature `/signer-contrat/[token]`**
- [ ] Bouton "📥 Télécharger le contrat signé" (quand statut = `signe`)
- [ ] Bouton "❌ Refuser ce contrat" pour l'acquéreur + saisie motif
- [ ] Affichage de la date d'expiration du lien

**Pages contrats (éleveur web + app)**
- [ ] Statuts `partiellement_signe`, `annule`, `expire`, `refuse` dans les badges
- [ ] Bouton "Annuler" sur un contrat (met statut `annule`)
- [ ] Bouton "📥 Télécharger PDF signé" sur les contrats signés
- [ ] Onglet/section "Historique" par contrat (audit trail)

**Particulier — Mes Contrats (web + app)**
- [ ] Bouton "❌ Refuser" avec motif
- [ ] Affichage des contrats refusés/annulés/expirés

**Multi-signataires (V2)**
- [ ] Ajout co-éleveur ou témoin lors de la création
- [ ] Statut `partiellement_signe` quand 1 signataire sur N a signé
- [ ] Co-adoption pour associations (plusieurs acquéreurs)

#### E. PDF signé téléchargeable

Actuellement les signatures canvas sont stockées en base64 dans `metadata` mais il n'existe pas de PDF final téléchargeable avec les signatures injectées. À créer :
- Soit côté web : générer un PDF via `@react-pdf/renderer` ou `puppeteer` avec les canvas injectés
- Soit via un webhook : à l'activation YouSign, le PDF signé est retourné par YouSign directement

---

### 9ter.3 — Codes feature préparation YouSign

| Code | Feature | Surface | Statut |
|------|---------|---------|--------|
| PREP01 | Migration SQL — colonnes expires_at, pdf_signe_url, yousign_id | Backend | 🔨 À faire |
| PREP02 | Table `contract_signers` | Backend | 🔨 À faire |
| PREP03 | Table `contract_audit` | Backend | 🔨 À faire |
| PREP04 | `SignatureProvider` interface + `YouSignProvider` stub + `CanvasSignatureProvider` | Web | 🔨 À faire |
| PREP05 | `ContractService` + `ContractStorageService` centralisés | Web | 🔨 À faire |
| PREP06 | Endpoints stubs `/api/yousign/create` + `/api/yousign/webhook` | Web | 🔨 À faire |
| PREP07 | Bouton télécharger PDF signé (UI web + app) | App + Web | 🔨 À faire |
| PREP08 | Bouton Refuser + statuts annulé/expiré/refusé (UI) | App + Web | 🔨 À faire |
| PREP09 | Historique/audit par contrat (UI) | Web | 🔨 À faire |
| PREP10 | Multi-signataires (co-éleveur, témoin) dans le formulaire | App + Web | 🔜 V2 |

---

### 9ter.4 — Checklist d'activation YouSign (quand abonnement souscrit)

Une fois l'abonnement YouSign actif, **dans cet ordre** :

- [ ] **1.** Ajouter dans `.env.local` (et variables Netlify/Vercel) :
  ```
  YOUSIGN_API_KEY=ys_sandbox_...    # puis yp_prod_... en production
  YOUSIGN_WEBHOOK_SECRET=...
  STRIPE_CONTRACT_PRICE_ID=price_...
  ```
- [ ] **2.** Implémenter `YouSignProvider` (les méthodes sont déjà définies via PREP04)
- [ ] **3.** Activer `/api/yousign/create` — appelle `YouSignProvider.createSignatureRequest()` + `addSigner()` + `sendSignatureRequest()`
- [ ] **4.** Activer `/api/yousign/webhook` — valider signature HMAC, récupérer PDF signé, stocker dans Supabase Storage `pdf_signe_url`, mettre statut `signe`
- [ ] **5.** Configurer le webhook dans l'interface YouSign : URL = `https://petsmatchapp.com/api/yousign/webhook`
- [ ] **6.** Créer la table `contrats_yousign_usage` + activer le garde de quota dans `ContractService`
- [ ] **7.** Tester en sandbox YouSign (les `ys_sandbox_` keys permettent des requêtes test sans facturation)
- [ ] **8.** Passer en production YouSign (`yp_prod_` keys)
- [ ] **9.** Activer la facturation Stripe 2€/contrat au-delà du quota

> À ce stade, le canvas (SIGN00) peut rester comme fallback ou être retiré.

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
- Bannière + photo de profil + nom d'élevage + ville ✅
- Badge validation (Profil validé ✓ / En attente ⏳) ✅
- Espèces élevées + races ✅
- Description ✅
- Coordonnées (téléphone + adresse) ✅
- Certifications (SIRET ✓/✗, justificatif, ACACED ✓/✗, certificat) ✅
- **Réseaux sociaux** (Instagram, Facebook, Site web) ✅ — *2026-06-21*
- Bouton "Modifier mon profil" → `/profil` (formulaire complet) ✅
- Bouton "Voir mon profil public" → `/elevages/[uid]` (si validé) ✅

### 10.2b Edit profil éleveur — `/profil` ✅

**Fichier :** `website/src/app/profil/page.tsx` (2200+ lignes, gère aussi association + pro secondaire)

Champs couverts :
- Bannière (crop 16:9) + Avatar ✅ — *crop avatar 1:1 manquant, à ajouter*
- Identité (prénom, nom, date de naissance) ✅
- Élevage (nom, téléphone, description) ✅
- Adresse élevage avec Google Places autocomplete ✅
- Espèces élevées + races ✅
- Réseaux sociaux (Instagram, Facebook, Site web) ✅ — *2026-06-21*
- Administratif : SIRET, KBIS/attestation RNE, ACACED n°, date obtention, date renouvellement, certificat ✅
- Sauvegarde vers Supabase ET Firestore (sync double) ✅

**App Flutter :** `lib/pages/eleveur/profil_eleveur_edit.dart` — même champs ✅ (réseaux sociaux inclus *2026-06-21*)

### 10.3 Agenda éleveur — `/elevage/agenda` ✅ *2026-06-21*

**Vues :** Toggle Mois / Semaine / Jour (style Google Calendar)
- **Vue Mois** : calendrier avec dots colorés par type d'acte, détail du jour en dessous
- **Vue Semaine** : WeekStrip 7 jours (Lun→Dim), navigation sem. préc./suiv., dots par jour
- **Vue Jour** : zone all-day (protocoles + tâches sans heure) + timeline horaire 6h-21h, ligne heure actuelle

**Attribution employés :**
- Tâches manuelles (`taches_elevage`) : modal multi-sélection → `assignes_a TEXT[]` ✅
- Attribution globale protocole : assigner tous les animaux en un clic depuis la RoutineModal ✅ *2026-06-21*
- Protocoles (`plan_taches`) : dropdown par animal → `assigned_to` ✅

**Traçabilité :**
- `fait_par` / `fait_a` sur `taches_elevage` (qui a coché + quand) ✅
- `valide_par` / `valide_at` sur `plan_taches` ✅
- Affichage "✓ Fait par [nom]" sur les tâches complétées ✅

**Migration SQL à exécuter dans Supabase :**
- `supabase/migration_social_links.sql` — colonnes `instagram`, `facebook`, `site_web` sur `users`
- `supabase/migration_agenda_employes.sql` — colonnes `assignes_a`, `fait_par`, `fait_a` sur `taches_elevage`

### 10.4 À faire — Profil éleveur

- **PROF01** : Crop avatar 1:1 sur web `/profil` — la bannière a son modal crop 16:9, l'avatar est uploadé tel quel (à aligner avec `image_cropper` Flutter)
- **PROF02** : Champ TVA dans l'édition profil — actuellement capturé seulement à l'onboarding (`document_elevage.dart`), non modifiable ensuite
- **A40** : Onboarding pro (3-4 slides : profil pro, agenda/RDV, clients, documents)
- **A41** : Onboarding particulier (2-3 slides : mes animaux, alertes perdus, annonces)
- Onboarding web (animation côté web pour les mêmes profils au 1er login)

---

---

## 15. Messagerie & Paramètres utilisateur

> Dernière mise à jour : 2026-06-26  
> Surfaces : **App Flutter (Android/iOS) + Site Web Next.js**  
> **Migration complète Firestore → Supabase (2026-06-26)** : toute la messagerie (éleveur/particulier, PetFriends DM + groupes) est désormais stockée dans Supabase (`conversations` + `messages`). Firestore n'est plus utilisé pour les messages.

---

### 15.0 Architecture messagerie — Supabase

| Table | Rôle |
|---|---|
| `conversations` | Une ligne par conversation (DM ou groupe) |
| `messages` | Un message par ligne, lié à `conversation_id` |
| `bloquages` | Remplace `bloquer/$uid` Firestore — `{uid, blocked_uid}` |

**Colonnes clés `conversations` :**
- `participants` JSONB array de UIDs — filtré avec `@>` (opérateur `cs` côté client)
- `participant_ids` TEXT — join trié des UIDs (`[uid1,uid2]..sort().join('_')`) pour identifier les DMs
- `participants_info` JSONB — `{uid: {name, photo}}` pour l'affichage sans re-fetch
- `unread_count` JSONB — `{uid: n}` par participant
- `pinned_for`, `archived_for`, `muted_for`, `deleted_for` JSONB
- `type` TEXT — `'direct'` | `'groupe'`
- `categorie` TEXT — catégorie de la conversation

**Realtime :** abonnement via `supabase.channel().onPostgresChanges(INSERT, table: 'messages', filter: conversation_id=eq.X)` pour les messages en temps réel. Pour la liste des conversations : abonnement sans filtre + rechargement complet au changement (Supabase Realtime ne supporte pas les filtres JSONB).

**RLS :** politiques permissives (`USING(true)`) car Firebase Auth → `auth.uid()` est null côté Supabase.

**Helper Flutter :** `lib/utils/messaging_helper.dart` — `MessagingHelper.openOrCreateConversation({otherUid, categorie, alerteId, nomAnimal, myProfileId, otherProfileId})` — trouve ou crée une conversation Supabase depuis n'importe quelle page.

---

### 15.1 Messagerie — Catégories et organisation

Les conversations sont regroupées par catégorie affichée sous forme d'onglets horizontaux.

| Clé `categorie` | Label | Emoji | Couleur |
|---|---|---|---|
| `null` / non défini | Tous | — | — |
| `animaux-perdus` | Perdus/Trouvés | 🐾 | Orange |
| `annonces` | Annonces | 🏷️ | Teal |
| `communaute` | Communauté | 💬 | Violet |
| `contact-elevage` | Élevages | 🐕 | Teal foncé |
| `service-professionnel` | Services | 🔧 | Violet foncé |
| `__archived__` | Archivés | 📦 | Ardoise |

**Attribution de la catégorie :** définie côté créateur via `MessagingHelper.openOrCreateConversation(categorie: '...')`. Valeur stockée dans `conversations.categorie` (Supabase).

---

### 15.2 Messagerie — Actions sur une conversation (long-press)

**Flutter :** `showModalBottomSheet` au long-press sur une carte conversation.  
**Web :** menu contextuel (right-click / clic droit) avec overlay positionné aux coordonnées de la souris.

| Action | Champ Supabase | Comportement |
|---|---|---|
| **Épingler / Désépingler** | `pinned_for JSONB {uid: bool}` | Conversation remontée en tête de liste |
| **Archiver / Désarchiver** | `archived_for JSONB {uid: bool}` | Masquée des onglets, visible uniquement dans "Archivés" |
| **Sourdine 8h** | `muted_for JSONB {uid: epochMs}` | Icône 🔕 sur la carte, badge non-lu masqué |
| **Bloquer l'utilisateur** | `bloquages` table `{uid, blocked_uid}` | Conversation masquée définitivement |
| **Supprimer** | `deleted_for JSONB {uid: bool}` | Conversation masquée uniquement pour l'utilisateur courant |

**Ordre d'affichage :** épinglées en premier, puis par `updated_at` décroissant.  
**Filtrage :** les conversations supprimées, archivées (sauf onglet Archivés) et bloquées sont exclues.

---

### 15.3 Messagerie — Visuel des cartes

- Fond `#F0F9FF` + icône 📌 en haut à gauche du nom si conversation épinglée
- Icône 🔕 si sourdine active (`muted_for[uid] > Date.now()`)
- Badge rouge sur l'icône Messages de la bottom nav (widget `MsgBadge`) — somme de `unread_count[uid]` sur toutes les conversations directes, mis à jour en Realtime
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
| Catégories messagerie (7 onglets) | MSG01 | ✅ | ✅ | Supabase `conversations.categorie` |
| Actions long-press (5 actions) | MSG02 | ✅ | ✅ | Right-click web — JSONB Supabase |
| Épinglage / archivage / sourdine | MSG03 | ✅ | ✅ | `pinned_for`/`archived_for`/`muted_for` JSONB |
| Blocage utilisateurs | MSG04 | ✅ | ✅ | Table `bloquages` Supabase (ex-Firestore) |
| Badge non-lu icône Messages | MSG05 | ✅ | ✅ | `MsgBadge` Flutter / badge header web |
| Notification push nouveau message | MSG06 | ✅ | — | Trigger SQL → `notifications` → Edge Function FCM |
| Chat PetFriends (DM + groupes) | MSG07 | ✅ | ✅ | Supabase Realtime — `petfriend_chat_page.dart` |
| Paramètres — menu principal | SET01 | ✅ | ✅ (section /profil) | — |
| Paramètres — info utilisateur | SET02 | ✅ | — | Espèces → profil éleveur |
| Paramètres — connexion & sécurité | SET03 | ✅ | ✅ | Reset mdp Firebase |
| Paramètres — confidentialité | SET04 | ✅ | ✅ (lien CGU) | — |
| Paramètres — à propos | SET05 | ✅ | ✅ (`/a-propos`) | — |
| Export données RGPD | SET06 | ✅ | ❌ à faire | JSON via share_plus |

---

---

## 16. Lieux Pet-Friendly — Hôtels, Hébergements & Restaurants

> **Ajouté le 2026-06-23**  
> Module dédié aux établissements acceptant les animaux de compagnie. Les professionnels (hôtels, hébergements insolites, cafés, restaurants) créent un profil vérifié qui apparaît sur une carte interactive et dans un feed filtrable. Les utilisateurs (particuliers, éleveurs, associations) peuvent liker, mettre en favori et laisser des avis.

---

### 16.1 Vision & objectif

**Problème** : les propriétaires d'animaux manquent d'un outil centralisé et fiable pour trouver des établissements vraiment pet-friendly. Les mentions "animaux acceptés" sur les OTAs (Booking, TripAdvisor) sont génériques et ne précisent pas les conditions réelles.

**Solution PetsMatch** : un annuaire/feed communautaire de lieux certifiés pet-friendly, intégré à l'écosystème (profil animal, espèces, taille), alimenté par les professionnels eux-mêmes et validé par la communauté via les avis.

**Différenciation** :
- Filtres spécifiques animaux (espèce, poids, nombre d'animaux)
- Avis vérifiés par des utilisateurs PetsMatch (profil + animaux connus)
- Intégration directe GPS → Waze / Google Maps
- Feed avec photos au format Instagram (optimisé mobile)
- Contestation d'avis transparente (visible admin)

---

### 16.2 Types d'établissements & catégories

#### Catégorie A — Hôtels & Hébergements
Sous-catégories :
- `hotel` — Hôtel classique (1 à 5 étoiles)
- `hebergement_insolite` — Cabane, yourte, glamping, tiny house
- `gite` — Gîte rural, chambre d'hôtes
- `camping` — Camping, aire naturelle
- `villa_location` — Location saisonnière privée

#### Catégorie B — Cafés & Restaurants
Sous-catégories :
- `cafe` — Café, salon de thé
- `restaurant` — Restaurant toutes cuisines
- `bar` — Bar, brasserie
- `fast_food` — Restauration rapide avec espace outdoor
- `boulangerie` — Boulangerie/pâtisserie avec terrasse

#### Champs spécifiques par catégorie

**Hébergements** (en plus des champs communs) :
| Champ | Type | Obligatoire | Description |
|---|---|---|---|
| `animaux_dans_chambre` | boolean | ✅ | Animaux autorisés dans la chambre |
| `frais_animal` | integer | ❌ | Supplément par nuit (€) |
| `poids_max_kg` | integer | ❌ | Poids max de l'animal (0 = illimité) |
| `nb_animaux_max` | integer | ❌ | Nombre max d'animaux par séjour |
| `races_exclues` | text[] | ❌ | Races non acceptées |
| `equipements_fournis` | text[] | ❌ | Ex: gamelle, coussin, parc, litière |
| `espace_detente_animaux` | boolean | ❌ | Zone dédiée (parc, jardin clôturé) |

**Restaurants/Cafés** (en plus des champs communs) :
| Champ | Type | Obligatoire | Description |
|---|---|---|---|
| `terrasse` | boolean | ✅ | Terrasse disponible |
| `animaux_en_salle` | boolean | ✅ | Animaux acceptés en salle |
| `eau_fournie` | boolean | ❌ | Gamelle d'eau fournie |
| `friandises` | boolean | ❌ | Friandises proposées aux animaux |
| `pet_menu` | boolean | ❌ | Menu dédié aux animaux |
| `attache_velo_animaux` | boolean | ❌ | Anneau d'attache devant l'établissement |

---

### 16.3 Onboarding — Inscription & données obligatoires

#### Données d'identification (toutes catégories)
Ces données sont requises pour la **validation du profil** par l'admin avant publication.

| Champ | Obligatoire | Validation |
|---|---|---|
| Nom commercial de l'établissement | ✅ | Non vide, max 80 chars |
| SIRET | ✅ | 14 chiffres, vérification API INSEE |
| Adresse complète (rue, CP, ville) | ✅ | Geocodage via API (Google Maps / Nominatim) |
| Coordonnées GPS (lat, lng) | ✅ | Générées automatiquement à la validation adresse |
| Catégorie principale | ✅ | Sélection parmi les catégories §16.2 |
| Sous-catégorie | ✅ | Sélection filtrée selon catégorie |
| Téléphone professionnel | ✅ | Format international |
| Email professionnel | ✅ | Différent de l'email de connexion |
| Site web | ❌ | URL valide |
| Espèces acceptées | ✅ | Multi-sélection (chien, chat, lapin, NAC…) |
| Horaires d'ouverture | ✅ | Par jour de la semaine (HH:MM–HH:MM ou fermé) |
| Photo de profil (logo) | ✅ | Min 400×400px, max 5 Mo |
| Photo bannière | ✅ | Min 1200×400px, max 8 Mo |
| Description | ✅ | Min 50 chars, max 1000 chars |
| 5 photos du lieu | ✅ | Format 4:5 (feed), max 5 Mo chacune |
| Champs spécifiques catégorie | ✅ | Voir §16.2 |

#### Processus de validation
1. Pro remplit le formulaire d'inscription (app ou web)
2. Compte créé avec statut `en_attente_validation`
3. Admin reçoit notification → vérifie SIRET (API INSEE), cohérence adresse, photos acceptables
4. Admin valide → profil publié (`statut = 'actif'`) + email de confirmation au pro
5. Admin peut rejeter avec motif (email + notification in-app)
6. Pro peut republier après correction

**Durée cible de validation : 48h ouvrables**

---

### 16.4 Tarification

> Les plans sont configurables via la table `plans_tarifaires` (admin sans déploiement).

| Plan | Mensuel | Annuel | Fonctionnalités clés |
|---|---|---|---|
| **Découverte** | Gratuit | Gratuit | Profil basique, 1 photo, non affiché dans le feed, contact via messagerie uniquement. Validité 30j puis expiration. |
| **Essentiel** | **5 €/mois** | **50 €/an** | Profil complet, 5 photos, apparition dans le feed, likes & favoris, avis clients, navigation GPS, stats basiques (vues, clics) |
| **Premium** | **15 €/mois** | **150 €/an** | Tout Essentiel + mise en avant dans le feed (épinglage 3j/mois), badge "Recommandé", réponse aux avis, stats avancées (provenance, pic horaire), 1 story/semaine (V2) |

> **Note tarifaire** : tarification d'acquisition pour le lancement. L'objectif V1 est de recruter rapidement 50+ établissements pour rendre le feed utile aux utilisateurs. Les tarifs sont conçus pour être quasi-incontestables (5€ = "presque gratuit" pour un professionnel) puis pourront être relevés en V2 sur la base des témoignages ROI. À titre de comparaison : PagesJaunes débute à ~30€/mois, TripAdvisor Business à ~100€/mois — la marge de hausse future est réelle.

> **Note** : le plan Découverte permet de tester le formulaire et la validation sans engagement. Il disparaît du feed au bout de 30 jours mais le profil reste accessible via lien direct tant que le pro ne supprime pas son compte.

**TVA** : 20 % sur tous les plans (B2B, auto-facturation).  
**Paiement** : Stripe (même intégration que §10). Prélèvement mensuel ou annuel.  
**Essai** : 30 jours gratuits sur le plan Essentiel (1 essai par SIRET).

---

### 16.5 Profil établissement

#### Composants de la page profil (`/lieux/{id}`)
```
┌─────────────────────────────────────────────────────────┐
│  BANNIÈRE (1200×400) — photo immersive                  │
│  ┌──────┐  Nom de l'établissement   ⭐⭐⭐⭐½  (47 avis)  │
│  │ LOGO │  Catégorie · Ville · Ouvert maintenant       │
│  └──────┘  [⭐ Avis]  [❤️ J'aime]  [🔖 Favori]         │
├─────────────────────────────────────────────────────────┤
│  📍 Adresse  🕐 Horaires  📞 Téléphone  🌐 Site web      │
│  [🗺️ Obtenir l'itinéraire]  ← bouton principal GPS      │
├─────────────────────────────────────────────────────────┤
│  🐾 Animaux acceptés : 🐕 🐈 🐇                          │
│  Pet-friendly : animaux en chambre ✅ · Frais : 10€/nuit │
├─────────────────────────────────────────────────────────┤
│  📖 Description du lieu (max 1000 chars)                │
├─────────────────────────────────────────────────────────┤
│  📸 Photos (carrousel 5 photos, format 4:5)             │
├─────────────────────────────────────────────────────────┤
│  ⭐ Avis clients (liste, pagination, filtre note)        │
└─────────────────────────────────────────────────────────┘
```

#### Comportement du bouton "Obtenir l'itinéraire"
1. Détecte Waze installé → ouvre `waze://ul?ll={lat},{lng}&navigate=yes`
2. Fallback : Google Maps → `https://maps.google.com/?daddr={lat},{lng}`
3. Web : ouvre Google Maps dans un nouvel onglet

#### Statut "Ouvert maintenant"
Calculé côté client à partir des horaires stockés. Affiche :
- 🟢 **Ouvert** jusqu'à 22h00
- 🔴 **Fermé** · Ouvre lundi à 08h30
- 🟡 **Ferme bientôt** (moins de 30 min)

---

### 16.6 Feed des lieux pet-friendly

#### Accès
- App Flutter : onglet dédié dans la section "Services & Sorties" (entre Hebergements et Cafés dans le menu existant)
- Web : `/lieux-pet-friendly`
- Accessible à tous (connecté ou non)

#### Format des cartes dans le feed
```
┌──────────────────────────────┐
│  Photo 4:5  (ratio Instagram) │  ← tap → profil
│  🟢 Ouvert  [❤️ 24] [🔖]     │  ← like + favori inline
├──────────────────────────────┤
│  Nom établissement           │
│  📍 Ville · 2.3 km           │
│  ⭐ 4.5 (32 avis)  · 🐕🐈     │
└──────────────────────────────┘
```

#### Filtres disponibles
| Filtre | Type | Options |
|---|---|---|
| Catégorie | chips multi | Hébergements / Cafés & Restos / Tout |
| Espèce | chips multi | Chien / Chat / Lapin / NAC / Chevaux |
| Distance | slider | < 5 km / < 20 km / < 50 km / Tout |
| Note minimale | stars | ⭐⭐⭐+ / ⭐⭐⭐⭐+ |
| Animaux en chambre | toggle | (Hébergements uniquement) |
| Terrasse | toggle | (Restaurants uniquement) |
| Animaux en salle | toggle | (Restaurants uniquement) |
| Ouvert maintenant | toggle | Filtre en temps réel |

#### Tri disponible
- Par distance (défaut si géolocalisation autorisée)
- Par note (décroissant)
- Par récence (derniers ajoutés)
- Mis en avant (Recommandé en premier, plan Premium)

#### Pagination
Infinite scroll, 12 cartes par page. Skeleton loading pendant le chargement.

---

### 16.7 Système d'avis & contestation

#### Qui peut laisser un avis ?
Tout utilisateur PetsMatch connecté (particulier, éleveur, association) ayant au moins **un animal déclaré** dans son profil.  
→ Limite anti-spam : 1 avis par établissement et par compte.

#### Structure d'un avis
| Champ | Obligatoire | Contrainte |
|---|---|---|
| Note globale | ✅ | 1 à 5 étoiles (pas de demi-étoile en saisie) |
| Accueil des animaux | ✅ | 1 à 5 étoiles |
| Commentaire | ✅ | Min 20 chars, max 1000 chars |
| Photo(s) | ❌ | Max 3 photos, 5 Mo chacune |
| Animal concerné | ❌ | Sélection depuis profil (espèce + nom) |
| Date de visite | ✅ | Mois + année (pas au-delà de M en cours) |

#### Cycle de vie d'un avis
```
Avis soumis → Publié immédiatement (modération a posteriori)
                    ↓
             Pro conteste l'avis
                    ↓
          Admin reçoit contestation
         ↓                    ↓
  Admin supprime        Admin laisse l'avis
  (email auteur)        (email pro + note visible)
```

#### Contestation par le professionnel
- Bouton "Contester" visible uniquement par le pro connecté sur son profil
- Formulaire : motif (liste) + explication libre (max 500 chars)
- Motifs prédéfinis : `faux_sejour`, `contenu_diffamatoire`, `hors_sujet`, `spam`, `autre`
- La contestation est visible sur l'avis côté admin : `🚩 Contesté — Motif : faux_sejour`
- L'auteur de l'avis est notifié de la contestation (sans détails du motif)
- Délai de décision admin : 7 jours ouvrables

#### Réponse du pro à un avis (plan Premium)
Le pro peut répondre publiquement à un avis (200 chars max). La réponse apparaît sous l'avis avec le logo de l'établissement.

#### Calcul de la note globale
- Moyenne pondérée : 60% note globale + 40% accueil des animaux
- Affichée avec 1 décimale (ex : 4.3)
- Mise à jour en temps réel à chaque nouvel avis

---

### 16.8 Likes & Favoris

Réutilise la logique existante (tables `likes` / `favoris`) avec `place_id` comme identifiant cible.

| Action | Accessible à | Stockage |
|---|---|---|
| ❤️ J'aime | Utilisateurs connectés | `place_likes (user_uid, place_id, created_at)` |
| 🔖 Favori | Utilisateurs connectés | `place_favoris (user_uid, place_id, created_at)` |
| Voir qui a liké | Propriétaire seulement | Modal bottom sheet (comme §Annonces) |
| Voir qui a mis en favori | Propriétaire seulement | Modal bottom sheet |

Les lieux favoris sont accessibles dans le profil utilisateur sous un nouvel onglet "Mes lieux" (app + web).

---

### 16.9 Schéma BDD

```sql
-- Établissements pet-friendly
CREATE TABLE petfriendly_places (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid_pro               TEXT NOT NULL,         -- Firebase UID du pro
  nom                   TEXT NOT NULL,
  categorie             TEXT NOT NULL,         -- 'hebergement' | 'restauration'
  sous_categorie        TEXT NOT NULL,         -- hotel, gite, restaurant, cafe...
  description           TEXT,
  siret                 TEXT NOT NULL,
  adresse               TEXT NOT NULL,
  code_postal           TEXT NOT NULL,
  ville                 TEXT NOT NULL,
  pays                  TEXT DEFAULT 'FR',
  lat                   DOUBLE PRECISION NOT NULL,
  lng                   DOUBLE PRECISION NOT NULL,
  telephone             TEXT,
  email_contact         TEXT,
  site_web              TEXT,
  especes_acceptees     TEXT[] DEFAULT '{}',
  horaires              JSONB DEFAULT '{}',    -- { "lundi": "08:00-22:00", "dimanche": "fermé" }
  photo_profil_url      TEXT,
  banniere_url          TEXT,
  photos                TEXT[] DEFAULT '{}',   -- max 5 URLs
  -- Champs hébergement
  animaux_dans_chambre  BOOLEAN,
  frais_animal_nuit     INTEGER,               -- en €
  poids_max_kg          INTEGER,               -- 0 = illimité
  nb_animaux_max        INTEGER,
  races_exclues         TEXT[] DEFAULT '{}',
  equipements_fournis   TEXT[] DEFAULT '{}',
  espace_detente        BOOLEAN,
  -- Champs restauration
  terrasse              BOOLEAN,
  animaux_en_salle      BOOLEAN,
  eau_fournie           BOOLEAN,
  friandises            BOOLEAN,
  pet_menu              BOOLEAN,
  -- Gestion
  statut                TEXT DEFAULT 'en_attente_validation',  -- en_attente_validation | actif | suspendu | expire
  plan                  TEXT DEFAULT 'decouverte',             -- decouverte | essentiel | premium
  plan_expire_at        TIMESTAMPTZ,
  note_moyenne          NUMERIC(3,1) DEFAULT 0,
  nb_avis               INTEGER DEFAULT 0,
  nb_likes              INTEGER DEFAULT 0,
  nb_favoris            INTEGER DEFAULT 0,
  valide_par            TEXT,                  -- uid admin
  valide_at             TIMESTAMPTZ,
  created_at            TIMESTAMPTZ DEFAULT NOW(),
  updated_at            TIMESTAMPTZ DEFAULT NOW()
);

-- Index géographique pour les requêtes "near me"
CREATE EXTENSION IF NOT EXISTS postgis;
ALTER TABLE petfriendly_places ADD COLUMN geom GEOMETRY(POINT, 4326)
  GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint(lng, lat), 4326)) STORED;
CREATE INDEX idx_pfp_geom ON petfriendly_places USING GIST (geom);
CREATE INDEX idx_pfp_statut ON petfriendly_places (statut);
CREATE INDEX idx_pfp_categorie ON petfriendly_places (categorie, sous_categorie);
CREATE INDEX idx_pfp_uid_pro ON petfriendly_places (uid_pro);

-- Avis
CREATE TABLE petfriendly_reviews (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  place_id        UUID NOT NULL REFERENCES petfriendly_places(id) ON DELETE CASCADE,
  user_uid        TEXT NOT NULL,
  note            INTEGER NOT NULL CHECK (note BETWEEN 1 AND 5),
  note_accueil    INTEGER NOT NULL CHECK (note_accueil BETWEEN 1 AND 5),
  commentaire     TEXT NOT NULL,
  photos          TEXT[] DEFAULT '{}',
  animal_espece   TEXT,
  animal_nom      TEXT,
  date_visite     TEXT,                        -- "2026-04"
  statut          TEXT DEFAULT 'actif',        -- actif | supprime_admin | masque
  reponse_pro     TEXT,                        -- réponse du pro (plan Premium)
  reponse_pro_at  TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(place_id, user_uid)
);

-- Contestations d'avis
CREATE TABLE petfriendly_review_contests (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id       UUID NOT NULL REFERENCES petfriendly_reviews(id) ON DELETE CASCADE,
  place_id        UUID NOT NULL,
  uid_pro         TEXT NOT NULL,
  motif           TEXT NOT NULL,               -- faux_sejour | contenu_diffamatoire | hors_sujet | spam | autre
  explication     TEXT,
  decision_admin  TEXT,                        -- null | 'supprime' | 'maintenu'
  decide_par      TEXT,                        -- uid admin
  decide_at       TIMESTAMPTZ,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Likes sur les lieux
CREATE TABLE place_likes (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  place_id    UUID NOT NULL REFERENCES petfriendly_places(id) ON DELETE CASCADE,
  user_uid    TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(place_id, user_uid)
);

-- Favoris sur les lieux
CREATE TABLE place_favoris (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  place_id    UUID NOT NULL REFERENCES petfriendly_places(id) ON DELETE CASCADE,
  user_uid    TEXT NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(place_id, user_uid)
);
```

> **Note PostGIS** : si Supabase n'a pas l'extension `postgis` activée, utiliser la colonne `lat/lng` DOUBLE PRECISION avec un tri côté application (Haversine) pour la V1. Activer PostGIS pour la V2 avec les requêtes géographiques avancées.

> **Note plans tarifaires** : les plans lieux pet-friendly s'appuient sur la table `plans_tarifaires` existante (§8.4) avec `profil_type = 'petfriendly'`. Seed initial à insérer via migration SQL (PFP38). Les prix sont lus dynamiquement depuis la BDD — jamais hardcodés dans le code (PFP40).

---

### 16.10 Tickets (PFP01–PFP35)

#### BDD & Backend
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PFP01** | Migrations SQL — tables `petfriendly_places`, `petfriendly_reviews`, `petfriendly_review_contests`, `place_likes`, `place_favoris` | Backend Supabase | V1 |
| **PFP02** | RLS policies — SELECT public, INSERT/UPDATE/DELETE owner only, service role admin | Backend | V1 |
| **PFP03** | API geocoding — validation adresse + conversion lat/lng (Google Maps Geocoding API ou Nominatim) | Backend | V1 |
| **PFP04** | API nearest places — endpoint `/api/places?lat=&lng=&radius=&categorie=&espece=` retournant les lieux triés par distance | Backend | V1 |
| **PFP05** | Trigger Supabase — recalcul `note_moyenne` et `nb_avis` sur INSERT/UPDATE/DELETE dans `petfriendly_reviews` | Backend | V1 |

#### Onboarding & Profil Pro
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PFP06** | Formulaire d'inscription pro — étapes 1/3 (identité: nom, SIRET, catégorie, adresse + geocoding auto) | App + Web | V1 |
| **PFP07** | Formulaire d'inscription pro — étapes 2/3 (profil: logo, bannière, description, 5 photos, horaires) | App + Web | V1 |
| **PFP08** | Formulaire d'inscription pro — étapes 3/3 (champs spécifiques catégorie + espèces acceptées + contact) | App + Web | V1 |
| **PFP09** | Choix du plan tarifaire lors de l'inscription + intégration Stripe (essai 14j Essentiel) | App + Web | V1 |
| **PFP10** | Notification admin à la soumission d'un profil + interface admin de validation (approuver / rejeter avec motif) | Admin | V1 |
| **PFP11** | Email de confirmation de validation (ou rejet) envoyé au pro | Backend | V1 |
| **PFP12** | Page "Mon établissement" — édition du profil pro après validation (tous champs sauf SIRET) | App + Web | V1 |

#### Page Profil Établissement (vue publique)
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PFP13** | Page `/lieux/{id}` — bannière, logo, nom, catégorie, note, horaires, statut ouvert/fermé | Web | V1 |
| **PFP14** | Page profil Flutter — même contenu, bottom sheet horaires détaillés | App | V1 |
| **PFP15** | Bouton "Obtenir l'itinéraire" — deep link Waze + fallback Google Maps | App + Web | V1 |
| **PFP16** | Carrousel 5 photos (format 4:5) — tap → lightbox plein écran | App + Web | V1 |
| **PFP17** | Section infos pet-friendly — chips espèces, champs catégorie-spécifiques (animaux chambre, terrasse…) | App + Web | V1 |

#### Feed & Découverte
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PFP18** | Feed `/lieux-pet-friendly` — cartes format 4:5 avec photo principale, note, ville, espèces | Web | V1 |
| **PFP19** | Feed Flutter — onglet "Lieux" dans Services & Sorties, infinite scroll, skeleton loading | App | V1 |
| **PFP20** | Filtres feed — catégorie, espèce, distance, note min, ouvert maintenant, animaux en salle / en chambre | App + Web | V1 |
| **PFP21** | Tri feed — par distance (géolocalisation), par note, par récence, mis en avant (Premium en premier) | App + Web | V1 |
| **PFP22** | Carte interactive — marqueurs des lieux sur Google Maps / Mapbox, tap sur marqueur → carte profil | App + Web | V2 |

#### Likes & Favoris
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PFP23** | Like d'un lieu — bouton ❤️ sur card feed + page profil, table `place_likes` | App + Web | V1 |
| **PFP24** | Favori d'un lieu — bouton 🔖, table `place_favoris`, onglet "Mes lieux" dans profil utilisateur | App + Web | V1 |
| **PFP25** | Vue "Qui a liké / qui a mis en favori" — owner only, bottom sheet / modal (réutilise LikersModal §12) | App + Web | V1 |

#### Avis
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PFP26** | Formulaire de soumission d'avis — note, note accueil, commentaire, photos, animal, date visite | App + Web | V1 |
| **PFP27** | Affichage des avis sur la page profil — liste, pagination, tri (récent / note), note globale + étoiles | App + Web | V1 |
| **PFP28** | Réponse du pro à un avis (plan Premium uniquement) — formulaire 200 chars, affiché sous l'avis | App + Web | V1 |
| **PFP29** | Contestation d'avis — formulaire pro, table `petfriendly_review_contests`, notification admin | App + Web | V1 |
| **PFP30** | Interface admin — liste des contestations en attente, décision suppression/maintien, notification auteur + pro | Admin | V1 |

#### Navigation GPS
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PFP31** | Deep link Waze (`waze://ul?ll=…`) avec détection installation + fallback Google Maps | App | V1 |
| **PFP32** | Bouton "Itinéraire" web — ouvre Google Maps dans nouvel onglet avec coordonnées | Web | V1 |

#### Paiement & Abonnement Pro
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PFP33** | Intégration Stripe — création abonnement Essentiel/Premium pour les lieux pet-friendly (produit distinct des éleveurs) | Backend + Web | V1 |
| **PFP34** | Gestion plan — page "Mon abonnement" pour le pro, downgrade/upgrade, annulation | App + Web | V1 |
| **PFP35** | Expiration automatique — cron job Supabase ou Vercel cron → passe `statut = 'expire'` si `plan_expire_at < NOW()` + email pro | Backend | V1 |

#### Tableau de bord Pro (stats)
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PFP36** | Dashboard pro "Mon établissement" — vues profil (7j/30j), clics navigation, likes, favoris, note évolution | App + Web | V2 |
| **PFP37** | Notifications pro — nouveau like, nouveau avis, contestation résolue, renouvellement abonnement proche | App + Web | V1 |

#### Gestion tarifaire via l'admin
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PFP38** | Seed SQL initial — insérer les 3 plans (`decouverte`, `essentiel`, `premium`) dans `plans_tarifaires` avec `profil_type = 'petfriendly'` et les valeurs initiales (0€ / 5€ / 15€ mensuel, 0€ / 50€ / 150€ annuel) + champ `features` JSONB décrivant les fonctionnalités incluses dans chaque plan | Backend | V1 |
| **PFP39** | Vue admin "Tarifs lieux pet-friendly" — tableau des 3 plans avec édition inline prix mensuel/annuel, toggle `actif`, édition liste `features` (comme la vue existante pour les éleveurs). Modification persiste dans `plans_tarifaires`, propagation immédiate sans déploiement. | Admin web | V1 |
| **PFP40** | Lecture des tarifs côté pro depuis `plans_tarifaires` — la page de souscription (`/lieux/abonnement`) et l'écran Flutter affichent les prix depuis la base (pas hardcodés), se mettent à jour si l'admin change un tarif | App + Web | V1 |

---

### 16.11 Dépendances & ordre d'implémentation

```
Phase 1 — Infrastructure (sem 1)
  PFP01 → PFP02 → PFP03 → PFP04 → PFP05

Phase 2 — Onboarding pro (sem 2)
  PFP06 → PFP07 → PFP08 → PFP09 → PFP10 → PFP11

Phase 3 — Profil public + feed (sem 3)
  PFP12 → PFP13 → PFP14 → PFP15 → PFP16 → PFP17
  PFP18 → PFP19 → PFP20 → PFP21

Phase 4 — Social + avis (sem 4)
  PFP23 → PFP24 → PFP25
  PFP26 → PFP27 → PFP28 → PFP29 → PFP30

Phase 5 — GPS + Paiement + Notifs
  PFP31 → PFP32 → PFP33 → PFP34 → PFP35 → PFP37

Phase 6 — V2
  PFP22 (carte interactive)
  PFP36 (dashboard stats avancées)
```

---

---

## 17. Promenades collectives — Améliorations

> **Ajouté le 2026-06-23**  
> La page `PromenadePage` (Flutter) et la future page web `/promenades` existent partiellement. Ce §17 ajoute GPS/Waze, jauge participants, visibilité sélective et invitations. Dépend de §18 (PetFriends) pour la visibilité "amis uniquement".

---

### 17.1 État actuel (base de travail)

**Implémenté :**
- `lib/pages/promenades/promenades_page.dart` — liste, rejoindre/quitter, formulaire création
- Formulaire : titre, lieu (texte libre), date/heure, niveau, durée
- Table Supabase `promenades` + `promenades_participants` (définies dans SPEC_PRO_SERVICES)
- Champs `lat`, `lng`, `participants_max` présents dans le schéma mais **non utilisés dans l'UI**

**Manquant :**
- Geocodage de l'adresse → lat/lng enregistrés
- Bouton "Obtenir l'itinéraire" → Waze / Google Maps
- Affichage jauge X/Y participants + blocage quand complet
- Visibilité : publique / PetFriends / invitation uniquement
- Invitation nominative d'utilisateurs PetsMatch

---

### 17.2 Geocodage & GPS du point de rendez-vous

#### Formulaire de création (Flutter + Web)
- Le champ "Lieu de rendez-vous" devient un champ d'autocomplétion d'adresse
- API : Google Places Autocomplete (ou Nominatim/Photon si hors budget)
- À la sélection d'une suggestion : `lat` et `lng` sont remplis automatiquement et stockés avec l'annonce
- Affichage de confirmation sous le champ : `📍 Trouvé : Parking du Lac, Rennes (48.1035, -1.6747)`
- Si l'utilisateur tape une adresse libre sans valider une suggestion → warning "Adresse non géolocalisée — itinéraire indisponible"

#### Sur la carte de promenade
```
📍 Parking du Lac, Rennes
[🗺️ Y aller]  ← bouton visible si lat/lng présents
```

#### Bouton "Y aller" — deep link
1. Détecte Waze installé → `waze://ul?ll={lat},{lng}&navigate=yes`
2. Fallback Google Maps → `https://maps.google.com/?daddr={lat},{lng}`
3. Web : ouvre Google Maps dans un nouvel onglet

---

### 17.3 Nombre maximum de participants

#### Formulaire de création
- Nouveau champ optionnel "Nombre max de participants" (int, min 2, max 50 ; vide = illimité)
- Placeholder : "Illimité"

#### Affichage sur la carte
```
👥 3 / 8 participants   ← si max défini
👥 5 participants       ← si illimité
```

#### Règles métier
- Quand `nb_participants >= participants_max` :
  - Bouton "Rejoindre" → désactivé, label "Complet"
  - `statut` passe automatiquement à `'complet'` via trigger Supabase (ou client-side check)
- Si un participant se désinscrit depuis une promenade "complète" → `statut` repasse à `'ouvert'`
- L'organisateur peut modifier le max après création (dans une future page "Mes promenades")

---

### 17.4 Visibilité & partage sélectif

#### Options de visibilité (formulaire de création)
| Option | Icône | Comportement |
|---|---|---|
| `publique` | 🌍 | Visible par tous les utilisateurs PetsMatch (comportement actuel) |
| `petfriends` | 👥 | Visible uniquement par les PetFriends de l'organisateur (§18) |
| `invitation` | 🔒 | Visible uniquement par les personnes explicitement invitées |

Valeur par défaut : `publique`

#### Feed — filtrage selon visibilité
- Une promenade `petfriends` apparaît dans le feed d'un utilisateur **seulement s'il est PetFriend de l'organisateur**
- Une promenade `invitation` n'apparaît dans le feed que des invités + l'organisateur
- L'organisateur voit toujours ses promenades quelle que soit la visibilité

#### Tableau des modifications BDD
```sql
ALTER TABLE promenades ADD COLUMN IF NOT EXISTS
  visibilite TEXT DEFAULT 'publique';  -- publique | petfriends | invitation
```

---

### 17.5 Invitations nominatives

Disponible quand `visibilite = 'invitation'` (ou en complément de `petfriends`).

#### Flux d'invitation
1. Organisateur tape un prénom / pseudo dans un champ de recherche
2. Résultats : utilisateurs PetsMatch avec leur photo de profil + premier animal
3. Organisateur sélectionne 1 à N personnes → liste d'invités affichée sous le formulaire
4. À la création : notification push + in-app envoyée à chaque invité :
   > "🦮 [Prénom] t'invite à une promenade : *Balade au bord du lac* — Sam 28 juin à 9h30"

#### Table `promenades_invitations`
```sql
CREATE TABLE promenades_invitations (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  promenade_id   UUID NOT NULL REFERENCES promenades(id) ON DELETE CASCADE,
  inviteur_uid   TEXT NOT NULL,
  invite_uid     TEXT NOT NULL,
  statut         TEXT DEFAULT 'en_attente',  -- en_attente | accepte | refuse
  vu_at          TIMESTAMPTZ,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(promenade_id, invite_uid)
);
```

---

### 17.6 Tickets Promenades (PRO01–PRO18)

#### GPS & Navigation
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PRO01** | Migration SQL — `ALTER TABLE promenades ADD COLUMN visibilite`, `CREATE TABLE promenades_invitations` | Backend | V1 |
| **PRO02** | Formulaire création Flutter — champ adresse avec autocomplétion geocodage + sauvegarde lat/lng | App | V1 |
| **PRO03** | Formulaire création Web — même champ adresse autocomplétion | Web | V1 |
| **PRO04** | Bouton "Y aller" sur la carte Flutter — deep link Waze + fallback Google Maps | App | V1 |
| **PRO05** | Bouton "Y aller" sur la carte Web | Web | V1 |

#### Participants
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PRO06** | Formulaire création — champ "Nombre max de participants" (optionnel) | App + Web | V1 |
| **PRO07** | Carte promenade — affichage jauge "X / Y participants" (ou "X participants" si illimité) | App + Web | V1 |
| **PRO08** | Blocage bouton "Rejoindre" quand complet + label "Complet" + trigger statut automatique | App + Web | V1 |

#### Visibilité
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PRO09** | Formulaire création — sélecteur visibilité (🌍 Publique / 👥 PetFriends / 🔒 Invitation) | App + Web | V1 |
| **PRO10** | Feed — filtre les promenades selon visibilité + PetFriends du user connecté (dépend PFR) | App + Web | V1 |

#### Invitations
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PRO11** | Formulaire — recherche & sélection d'utilisateurs à inviter (si visibilité = invitation) | App + Web | V1 |
| **PRO12** | Notification push + in-app à l'invité lors de la création | App + Web | V1 |
| **PRO13** | Réponse invitation — accepter / refuser depuis la notification ou depuis la page promenade | App + Web | V1 |

#### Page détail & gestion
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PRO14** | Page détail promenade Flutter — infos complètes, liste participants avec avatars, bouton rejoindre | App | V1 |
| **PRO15** | Page détail promenade Web `/promenades/[id]` — même contenu | Web | V1 |
| **PRO16** | Page "Mes promenades" (organisées + rejointes) — modification/annulation pour l'organisateur | App + Web | V2 |
| **PRO17** | Notification rappel 2h avant la promenade aux participants inscrits | App + Web | V1 |
| **PRO18** | Chat de groupe promenade — canal dédié dans la messagerie (catégorie `promenade`) entre participants | App + Web | V2 |

---

## 18. PetFriends — Réseau social propriétaires

> **Ajouté le 2026-06-23**  
> Système d'amis entre utilisateurs particuliers (et éleveurs/associations) pour partager les animaux, les promenades et la messagerie directe. Inspiré du concept "amis" Facebook — bidirectionnel (demande + acceptation), pas un système de "follow" unilatéral.

---

### 18.1 Vision & concept

**Problème** : les utilisateurs PetsMatch ne peuvent actuellement pas se "retrouver" entre propriétaires d'animaux. La messagerie n'est accessible que dans le contexte d'une annonce ou d'un service. Il n'existe aucun lien social entre particuliers.

**Solution** : les **PetFriends** sont les amis PetsMatch d'un utilisateur. En devenant PetFriend :
- On voit les animaux partagés de son ami (ceux qu'il a marqués "visibles aux amis")
- On reçoit les promenades qu'il organise en mode "PetFriends uniquement"
- On peut lui écrire via la messagerie directement (sans passer par une annonce)

**Qui peut avoir des PetFriends ?** Tous les profils connectés (particulier, éleveur, association, pro).  
**Visibilité** : la liste de vos PetFriends est privée (non visible par les autres).

---

### 18.2 Système de demande d'amis

#### Flux
```
A trouve le profil de B (via promenade, fiche animal, suggestions)
       ↓
A appuie "Ajouter en PetFriend" 
       ↓
B reçoit notification : "🐾 [A] veut devenir ton PetFriend"
       ↓
B accepte → relation bidirectionnelle créée
B refuse → aucune notification à A, demande disparaît silencieusement
       ↓
A est notifié si B accepte : "✅ [B] a accepté ta demande de PetFriend !"
```

#### États d'une relation
| Statut | Description |
|---|---|
| `en_attente` | Demande envoyée, en attente de réponse |
| `accepte` | Amis — relation bidirectionnelle active |
| `refuse` | Refus silencieux (B ne recontacte pas A) |
| `bloque` | Bloqué (bloque aussi la messagerie) — utilise le système de blocage existant |

---

### 18.3 Profil public & animaux partagés

#### Page profil utilisateur `/profil/[uid]` (publique)
Accessible à tous les utilisateurs connectés (lien depuis une promenade, une annonce, etc.)

```
┌─────────────────────────────────────────────────────────┐
│  [Photo de profil]  Prénom Nom                          │
│  📍 Ville · 🐕 2 animaux                                │
│  [➕ Ajouter en PetFriend] / [✓ PetFriend] / [En attente]│
│  [💬 Message]  ← visible seulement si PetFriend         │
├─────────────────────────────────────────────────────────┤
│  🐾 Ses animaux (visibles aux amis)                     │
│  [Photo]  Rex — Labrador · 3 ans                        │
│  [Photo]  Luna — Berger Belge · 1 an                    │
│  ← Animaux marqués "visible aux PetFriends" uniquement  │
└─────────────────────────────────────────────────────────┘
```

**Règles de visibilité des animaux sur la page publique :**
- Animaux avec `visible_petfriends = true` → visibles si l'utilisateur connecté est PetFriend
- Animaux avec `visible_petfriends = false` → jamais visibles sur profil public
- Le nombre total d'animaux est toujours affiché ("2 animaux") mais pas les détails si non ami

#### Paramètre animal "visible aux PetFriends"
Ajout d'un toggle dans la fiche d'édition de l'animal :
- "🔒 Visible par mes PetFriends" (default: false)
- Concerne uniquement la visibilité sur le profil public — les annonces restent visibles normalement

---

### 18.4 Mes PetFriends — liste & découverte

#### Page "Mes PetFriends" (app + web)
Accessible depuis le menu profil.

```
┌────────────────────────┐
│  Mes PetFriends  (12)  │
│  [Demandes reçues (2)] │
├────────────────────────┤
│  [Avatar] Léa · 🐕🐈   │ → tap → profil de Léa
│  [Avatar] Marco · 🐕   │
│  [Avatar] Sophie · 🐇  │
│  ...                   │
├────────────────────────┤
│  Demandes envoyées (1) │
│  [Avatar] Tom — En attente │
└────────────────────────┘
```

#### Suggestions de PetFriends (V2)
- Basées sur : même ville, mêmes espèces, participation aux mêmes promenades
- Affichées en bas de la liste si < 5 PetFriends

---

### 18.5 Messagerie entre PetFriends

La messagerie Firestore existante est déjà multi-catégories (§15.1). On ajoute :
- Catégorie `petfriends` dans la messagerie
- Bouton "💬 Message" sur le profil public d'un PetFriend → ouvre ou crée la conversation
- Une conversation PetFriend ne nécessite **pas** de passer par une annonce/service

**Contrainte** : seuls les PetFriends (statut `accepte`) peuvent s'écrire. Si la relation est supprimée → la conversation reste accessible en lecture mais plus d'envoi possible.

---

### 18.6 Schéma BDD

```sql
-- Relations PetFriends
CREATE TABLE petfriends (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid_demandeur   TEXT NOT NULL,    -- qui envoie la demande
  uid_recepteur   TEXT NOT NULL,    -- qui reçoit
  statut          TEXT DEFAULT 'en_attente',  -- en_attente | accepte | refuse
  vu_at           TIMESTAMPTZ,      -- quand le récepteur a vu la demande
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(uid_demandeur, uid_recepteur)
);

-- Index pour requêtes rapides "mes amis" (dans les deux sens)
CREATE INDEX idx_pf_demandeur ON petfriends (uid_demandeur, statut);
CREATE INDEX idx_pf_recepteur ON petfriends (uid_recepteur, statut);

-- Visibilité animal côté PetFriends
-- Ajouter colonne sur la table animaux existante :
ALTER TABLE animaux ADD COLUMN IF NOT EXISTS visible_petfriends BOOLEAN DEFAULT false;

-- RLS : chaque user voit ses propres relations + les relations où il est récepteur
-- (service role pour les lectures croisées)
ALTER TABLE petfriends ENABLE ROW LEVEL SECURITY;
CREATE POLICY "pf_own_rows" ON petfriends FOR ALL
  USING (uid_demandeur = current_setting('app.uid', true)
      OR uid_recepteur = current_setting('app.uid', true));
```

> **Note RLS** : comme pour les autres tables, Firebase Auth ne fournit pas `auth.uid()`. Utiliser `service role` côté API ou des policies permissives avec filtrage applicatif (même pattern que les tables `notifications`, `likes`, etc.)

---

### 18.7 Tickets PetFriends (PFR01–PFR22)

#### BDD & Backend
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PFR01** | Migration SQL — table `petfriends` + index + `ALTER TABLE animaux ADD visible_petfriends` | Backend | V1 |
| **PFR02** | RLS policies `petfriends` — permissive (même pattern notifications) | Backend | V1 |
| **PFR03** | API helper `isFriend(uid_a, uid_b)` — vérifie statut `accepte` dans les deux sens | Backend | V1 |
| **PFR04** | API `getFriends(uid)` — liste des PetFriends acceptés avec leurs infos profil | Backend | V1 |

#### Demande d'amis
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PFR05** | Bouton "Ajouter en PetFriend" sur profil public + fiche animal — états : ➕ / ⏳ / ✓ PetFriend | App + Web | V1 |
| **PFR06** | Notification in-app + push à la demande reçue : "🐾 [Prénom] veut être ton PetFriend" | App + Web | V1 |
| **PFR07** | Interface "Demandes reçues" — accepter / refuser avec swipe (app) ou boutons (web) | App + Web | V1 |
| **PFR08** | Notification à l'envoyeur lors de l'acceptation | App + Web | V1 |
| **PFR09** | Supprimer un PetFriend — depuis la liste Mes PetFriends (action destructrice, confirmation requise) | App + Web | V2 |

#### Profil public
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PFR10** | Page profil public `/profil/[uid]` — photo, prénom, ville, nb animaux, bouton PetFriend + Message | Web | V1 |
| **PFR11** | Page profil public Flutter — même contenu, accessible via promenade / fiche animal | App | V1 |
| **PFR12** | Affichage des animaux "visible_petfriends" sur le profil d'un ami | App + Web | V1 |
| **PFR13** | Toggle "Visible par mes PetFriends" dans la fiche d'édition d'un animal | App + Web | V1 |

#### Liste & découverte
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PFR14** | Page "Mes PetFriends" — liste amis + demandes reçues (badge) + demandes envoyées | App + Web | V1 |
| **PFR15** | Recherche d'utilisateurs par prénom/pseudo pour envoyer une demande | App + Web | V1 |
| **PFR16** | Suggestions PetFriends — même ville + mêmes espèces (max 5 suggestions) | App + Web | V2 |

#### Messagerie
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PFR17** | Catégorie `petfriends` dans la messagerie Firestore | App + Web | V1 |
| **PFR18** | Bouton "💬 Message" sur le profil public d'un PetFriend → crée/ouvre conversation catégorie petfriends | App + Web | V1 |
| **PFR19** | Restriction envoi message : seuls les PetFriends (statut accepte) peuvent écrire | App + Web | V1 |

#### Intégration Promenades
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PFR20** | Feed promenades — filtrage visibilité `petfriends` (n'affiche que les promenades d'amis) (dépend PRO10) | App + Web | V1 |
| **PFR21** | Invitations promenade — champ de recherche limité aux PetFriends (en plus des autres users) | App + Web | V1 |

#### Admin
| Code | Intitulé | Surface | Priorité |
|---|---|---|---|
| **PFR22** | Stats admin — nb relations PetFriends créées par jour/semaine, taux d'acceptation | Admin | V2 |

---

### 18.8 Ordre d'implémentation

```
Phase 1 — BDD (PRO01, PFR01, PFR02)
Phase 2 — Promenades GPS + Waze (PRO02–PRO08) ← implémentable immédiatement
Phase 3 — Profil public PetFriends (PFR05, PFR10, PFR11)
Phase 4 — Demande d'amis + notifications (PFR06–PFR08, PFR14, PFR15)
Phase 5 — Messagerie PetFriends (PFR17–PFR19)
Phase 6 — Animaux partagés (PFR12, PFR13)
Phase 7 — Visibilité promenades (PRO09, PRO10, PFR20, PFR21)
Phase 8 — Invitations promenade (PRO11–PRO13, PRO17)
Phase 9 — V2 (PRO14–PRO18, PFR09, PFR16, PFR22)
```

---

## 19. Module Pension — État d'avancement (session 2026-07-02)

> Objectif exprimé : donner aux pensions un socle de gestion aussi complet que l'éleveur/association
> (au-delà des simples annonces) pour encourager leur inscription, plus une partie "profils avancés"
> (réservation intelligente, tarification automatisée, facturation, paiement en ligne) prévue mais
> phasée. Cette section liste ce qui est livré et ce qui reste, pour reprise ultérieure.

### 19.1 — Livré ✅ (app + web sauf mention contraire)

**Phase 1 — parité de gestion avec éleveur/association**
- Inventaire, Protocoles/Tâches, Employés (avec permissions granulaires `employe_permissions`) débloqués
  pour `cat_pro = 'pension'` — ces modules existaient déjà pour l'éleveur, seule la navigation était
  verrouillée (`if (!User_Info.isPro)`). Web : liens ajoutés dans `MENU_PENSION` (Header.tsx) vers les
  routes génériques déjà existantes (`/employes`, `/mes-taches`, `/elevage/inventaire`).
- **Logements / Chenil** (nouveau) : gestion des box/enclos/chatterie/cage avec capacité, assignation
  des animaux en pension. Réutilise `enclos_chenil` (déjà générique via `uid_eleveur`) + nouvelle colonne
  `pension_entrees.logement_id`. Pages : `lib/pages/pro/pension_chenil_page.dart`,
  `website/src/app/pension/chenil`. **Ne couvre pas encore** les états opérationnels détaillés du §4
  (à nettoyer / en nettoyage / hors service, mode équin) — c'est un MVP capacité+occupation uniquement.
- **Tarifs & arrhes** : champ tarif €/nuit par type de logement + % d'arrhes, configurables dans le
  profil pro (`user_profiles.tarifs_logements` JSONB, `arrhes_pourcentage`). Pas de variation automatique
  par saison ou par poids d'animal (voir 19.2).
- **Signature électronique des contrats d'hébergement** : nouveau type `contrat_hebergement` sur
  `documents_animaux` (`pension_entree_id` au lieu de `animal_id`), template
  `website/src/lib/contrat-pension.ts`, page `/pension/contrat`, bouton "Signature en ligne" dans
  `registre_pension_page.dart`. Réutilise le même mécanisme que les contrats éleveur/association
  (canvas manuscrit via `/signer-contrat/[token]`) — voir §9ter, le provider YouSign réel reste un stub
  pour tout le monde, pas seulement la pension.
- **Export factures CSV** : bouton d'export sur `FacturationPage` (app) et `/elevage/facturation` (web,
  déjà partagée par la pension) — base d'interopérabilité avec un logiciel comptable tiers. Pas d'alertes
  impayés ni d'export par plage de dates personnalisée (voir 19.2).
- **Tableau de bord** : cartes stats "Pensionnaires" (→ registre), "RDV aujourd'hui" (→ agenda vue jour),
  "Statut" (→ abonnement) rendues cliquables comme pour l'éleveur (`eleveur_home.dart`).
- **Fiches accessibles** : saisie manuelle du numéro de puce en secours si le scan échoue
  (`fiches_pension_page.dart`).
- **Correctif indépendant** : bug de reconnexion (déconnexion → reconnexion sans redémarrer l'app
  échouait) corrigé sur tous les profils, pas seulement pension — voir commit `c7ff69aa`.
- **Formules d'abonnement pension** (session 2026-07-03) : 3 formules livrées — Découverte (gratuit,
  1 logement, RDV, registre basique), Pro (14€/mois·140€/an — logements illimités, inventaire, 3
  employés, protocoles, contrats signature, export factures), Premium (24€/mois·240€/an — employés
  illimités, badge, accès prioritaire aux futures features). Seedées dans `plans_tarifaires`
  (`profil_type='pension'`), **éditables sans déploiement depuis `/admin` → onglet Tarification**
  (déjà générique côté données, l'UI affiche désormais le `profil_type` pour distinguer les plans).
  `PlanService.getPensionPlanCode()`/`getPensionPlansLive()` (app) et `usePensionPlan()` (web) lisent
  le plan actif — scopé par `profil_type`, indépendant du plan éleveur du même compte.
  `PensionAbonnementPage` (app) + `/pension/abonnement` (web) affichent les 3 formules avec prix à
  jour. Gating : Inventaire/Protocoles/Employés verrouillés en Découverte (icône grisée +
  redirection abonnement dans le drawer), 1 logement max appliqué dans `pension_chenil_page.dart`.
  **Paiement en ligne** : plomberie corrigée depuis (voir ligne Stripe ci-dessous, §19.2) — checkout
  réellement câblé sur la page, reste juste à saisir les prix dans `/admin` pour activer.
- **Planning d'occupation** (session 2026-07-03) : vue calendrier des séjours par logement façon
  planning hôtelier — logements en lignes (groupés par type), fenêtre glissante de 14 jours,
  barres colorées par statut (à venir/entrée aujourd'hui/en cours/sortie aujourd'hui/sortie en
  retard/sortie faite aujourd'hui/passé), dérivé des champs déjà existants de `pension_entrees`
  sans migration. Pas de statut "non confirmé" ni d'entrée/sortie réelle distincte de la date
  prévue (pas trackées aujourd'hui) — repoussé en V2 pour rester sur les données disponibles.
  App : `pension_planning_page.dart`. Web : `/pension/planning`.

### 19.2 — Reste à faire 🔨 (Phase 2 / profils avancés, explicitement différé)

| Item | Détail | Statut |
|---|---|---|
| Réservation intelligente | Algorithme d'allocation optimale entre logements de même catégorie selon les dates demandées | Non commencé |
| Tarification automatisée | Prix calculé automatiquement selon poids animal, individuel/collectif, arrivée/départ en début de journée, réductions séjour long | Non commencé |
| Alertes facturation | Notification si séjour non facturé ou client débiteur | Non commencé |
| Export facturation par plage de dates | Export CSV actuel = tout l'historique filtré par statut, pas de sélecteur de dates dédié | Non commencé |
| Paiement en ligne pension (Stripe) | Plomberie corrigée (2026-07-03, commits `a9a3152e`/`7c823f31`) : `/api/stripe/checkout`/`activate`/`portal` sont profil_type-aware, price ID lu depuis `plans_tarifaires`. **Plus besoin d'ouvrir le dashboard Stripe** : `/admin` → Tarification crée désormais automatiquement le produit + prix Stripe dès qu'un tarif > 0 est saisi et enregistré (`getOrCreatePlanProduct` dans `api/admin/tarification/route.ts`). Reste : aller dans `/admin` et saisir les prix pension pour déclencher la création | Prêt — reste juste à saisir les prix dans /admin |
| Paiement en ligne (lien email/SMS) | Explicitement V2 par l'utilisateur, avec frais de service/transaction optionnels | Non commencé |
| États de nettoyage des logements | à nettoyer / en nettoyage / hors service (mode canin, §4) — la vue planning (2026-07-03) couvre l'occupation/réservation, pas le nettoyage | Non commencé |
| Activation YouSign réelle | `YouSignProvider` reste un stub (toutes méthodes lèvent une erreur) tant qu'un abonnement YouSign + clé API n'est pas fourni — voir §9ter.2 pour la liste complète des prérequis restants, communs à tous les profils | Bloqué sur décision business |

### 19.4 — Livré (session 2026-07-03, suite retours utilisateur)

- **Espèces acceptées par logement + filtres** : colonne `especes` (TEXT[]) sur `enclos_chenil`, sélection
  multi-espèces à la création/édition d'un logement, filtre par espèce sur Logements/Chenil et Planning
  occupation (app+web). Liste réutilisée depuis `especes_acceptees` du profil pro.
- **Widget disponibilité tableau de bord** : bannière "X / Y places disponibles" (app `eleveur_home.dart`,
  web `ProDashboard.tsx`), calculée depuis `enclos_chenil.capacite` et les séjours actifs.
- **Clic sur créneau libre du planning → intègre un animal** : ouvre directement le formulaire d'ajout de
  séjour pré-rempli (logement + date). App : `PensionEntreeSheet` gagne `initialLogementId`/
  `initialDateEntree`. Web : formulaire extrait en composant partagé `PensionEntreeModal.tsx` (auparavant
  local à `pension/registre`), réutilisé dans `pension/planning`.
- **Fiche animal créée sans compte propriétaire + lien de réclamation** : quand un animal inconnu est ajouté
  en pension, sa fiche est créée immédiatement dans `animaux` (`uid_eleveur` = la pension, gestionnaire
  temporaire). Nouveau champ `owner_uid` (nullable) accueille le vrai propriétaire une fois réclamée via
  un lien à token envoyé par email (table `animal_claims`, page `/reclamer-animal/[token]`, réutilise
  l'infra nodemailer déjà en place pour les cessions). **SMS non disponible** — Twilio jamais implémenté
  dans ce projet (seulement prévu sur le papier), email uniquement pour l'instant.
- **Journal de séjour** : la pension poste des nouvelles (photo + note) pendant le séjour, visibles par le
  propriétaire sur la fiche de son animal une fois liée. App : `pension_journal_page.dart` (post, côté
  pension) + bouton "Nouvelles de la pension" en lecture seule dans `animal_fiche_particulier.dart`. Web :
  composant partagé `PensionJournal.tsx`. **Vidéo pas câblée** (colonne `video_url` prête en base, scope
  limité à photo/note pour ce tour — vidéo en fast-follow si besoin).
- **Correctifs indépendants découverts en testant** : `mapProfile()` (`auth-context.tsx`) plantait
  silencieusement sur les profils dont `especes_elevees` est stocké en tableau de chaînes plutôt qu'en
  objets `{espece, races}` — bloquait `userData` (donc toutes les pages pension) pour ces comptes ; nouveau
  hook `usePensionAccess()` remplace le check naïf `userData?.catPro==='pension'` sur 6 pages web pour
  gérer correctement les comptes multi-profils (ex : pension + particulier) ; redirection prématurée vers
  `/connexion` sur rechargement complet corrigée (attente de `authLoading` avant de décider).

### 19.3 — Migrations à exécuter (si pas déjà fait)

```
supabase/migration_pension_logements.sql        -- logement_id, tarifs_logements, arrhes_pourcentage
supabase/migration_pension_contrat.sql          -- pension_entree_id sur documents_animaux
supabase/migration_pension_plans_tarifaires.sql -- 3 formules pension dans plans_tarifaires
supabase/migration_enclos_chenil_especes.sql    -- especes sur enclos_chenil
supabase/migration_animaux_owner_uid_claims.sql -- owner_uid sur animaux + table animal_claims
supabase/migration_pension_updates.sql          -- table pension_updates (journal de séjour)
```

---

*Document maintenu par l'équipe PetsMatch — toute modification fonctionnelle doit être reportée ici avant implémentation.*
