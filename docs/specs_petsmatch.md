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
| Réservation intelligente | ✅ Livré (session 2026-07-09), app + web : bannière "animal(aux) à placer" sur les entrées "en_pension" sans logement, suggestion automatique du meilleur logement compatible (espèce acceptée, place disponible, best-fit — le plus petit logement qui convient en premier). Bouton "Tout placer auto" pour traiter plusieurs animaux d'un coup. Scope volontairement limité à l'allocation temps réel (pas de pré-réservation à dates futures, ce concept n'existe pas encore dans le modèle de données). | Livré |
| Tarification automatisée | ✅ Livré (session 2026-07-09), app uniquement (web = lecture seule sur l'abonnement, la facturation elle-même n'existe que côté app) : config par tranches de poids (prix seul/partagé) + réductions séjour long dans une nouvelle page "Tarifs" ; pré-remplit automatiquement le tarif/nuit à la facturation. | Livré |
| Alertes facturation | ✅ Livré (session 2026-07-09), app uniquement : nouvelle table `pension_factures` traçant chaque facture envoyée (avant : rien n'était persisté, PDF généré à la volée). Bandeau "séjours non facturés" + "factures impayées depuis >15j" en haut du registre, bouton "Marquer facturé (sans envoi)" pour les factures remises en main propre. | Livré |
| Export facturation par plage de dates | ✅ Livré (session 2026-07-09), app uniquement, dans la nouvelle page "Mes Factures" : sélecteur de plage de dates + export PDF (total facturé/payé/restant dû). | Livré |
| Paiement en ligne pension (Stripe) | Plomberie corrigée (2026-07-03, commits `a9a3152e`/`7c823f31`) : `/api/stripe/checkout`/`activate`/`portal` sont profil_type-aware, price ID lu depuis `plans_tarifaires`. **Plus besoin d'ouvrir le dashboard Stripe** : `/admin` → Tarification crée désormais automatiquement le produit + prix Stripe dès qu'un tarif > 0 est saisi et enregistré (`getOrCreatePlanProduct` dans `api/admin/tarification/route.ts`). Reste : aller dans `/admin` et saisir les prix pension pour déclencher la création | Prêt — reste juste à saisir les prix dans /admin |
| Paiement en ligne (lien email/SMS) | Explicitement V2 par l'utilisateur, avec frais de service/transaction optionnels | Non commencé |
| États de nettoyage des logements | ✅ Livré (session 2026-07-03) : suivi jour par jour via `pension_nettoyages`, ligne dédiée dans le planning. Reste : pas d'état "hors service" (logement indisponible temporairement, hors nettoyage) | Partiel — nettoyage fait, "hors service" restant |
| Activation YouSign réelle | `YouSignProvider` reste un stub (toutes méthodes lèvent une erreur) tant qu'un abonnement YouSign + clé API n'est pas fourni — voir §9ter.2 pour la liste complète des prérequis restants, communs à tous les profils | Bloqué sur décision business |
| Accès employés au planning + fiches | ✅ Livré (session 2026-07-03) — voir §19.4 | Livré |

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
  composant partagé `PensionJournal.tsx`.
- **Vidéo câblée dans le journal de séjour** (session 2026-07-04) : sélection vidéo (limite 50 Mo) via
  `image_picker`/input `type=file accept=video/*`, upload sur le bucket `media` (type MIME détecté :
  mp4/mov/webm/3gp), lecture via `video_player` (app, widget `_JournalVideo` avec lazy-init du contrôleur)
  et balise `<video controls>` (web).
- **Purge automatique à 60 jours (anti-saturation stockage)** : nouvelle table non requise — purge basée sur
  `pension_updates.created_at`. Déclenchée par une **Netlify Scheduled Function**
  (`website/netlify/functions/cleanup-pension-updates.mts`, `schedule: '@daily'`, déclarée via
  `[functions] directory = "netlify/functions"` dans `netlify.toml` racine) qui supprime les lignes de plus
  de 60 jours **et** leurs fichiers du bucket `media` (photo + vidéo). Fonction autonome (pas d'import
  `src/`, contexte de build Netlify séparé de Next.js). Route de déclenchement manuel/backup :
  `POST /api/cron/cleanup-pension-updates` (protégée par `CRON_SECRET`, même pattern que
  `api/contracts/expire`). Nécessite `SUPABASE_SERVICE_ROLE_KEY` en variable d'environnement Netlify (déjà
  utilisée par d'autres routes admin) pour bypasser les RLS lors de la purge inter-comptes.
- **Deux trous trouvés en testant le journal de séjour côté propriétaire éleveur** :
  1. Le bouton "📸 Nouvelles de la pension" n'existait que sur la fiche animal **particulier**
     (`animal_fiche_particulier.dart`), pas sur la fiche **éleveur** (`animal_fiche.dart`) — un propriétaire
     avec un profil élevage ne voyait donc jamais le journal de son animal en pension. Ajouté (nouveau
     `_hasPensionUpdates`, requête `pension_updates`).
  2. Poster une nouvelle (photo/vidéo/note) ne déclenchait **aucune notification** au propriétaire — il ne
     pouvait s'en apercevoir qu'en repassant manuellement sur la fiche. App `_post()` et web `post()`
     résolvent désormais le propriétaire actuel via `animaux_proprietes` et insèrent une notification
     (`type: 'pension_journal'`).
- **Bug — accès pension étiqueté "vétérinaire" avec un nom faux** : sur la fiche animal éleveur,
  `_loadVetAcces()` chargeait **tous** les `animal_access` non révoqués de l'animal sans filtrer par type de
  profil, puis affichait chacun avec un préfixe "Dr." — un accès pension apparaissait donc en double : une
  fois correctement dans "Accès pension actifs", une fois à tort dans "Accès vétérinaires" (nom résolu via
  `firstname`/`lastname` du profil pension, souvent vide ou avec des valeurs de test → "Dr. Pension
  Pension"). Corrigé : filtre sur `profile_type = 'veterinaire'`. Au passage, `_loadPensionAcces()` ne
  résolvait jamais le nom de la pension (toujours "Structure" par défaut) — corrigé par une jointure sur
  `user_profiles` (nom d'élevage en priorité).
- **Like + réponse du propriétaire sur le journal de séjour** (session 2026-07-04) : nouvelles colonnes
  `owner_liked`/`owner_reply`/`owner_reply_at` sur `pension_updates` (déjà couvertes par la purge à 60 jours,
  même table/ligne). Côté propriétaire (vue lecture seule) : bouton ❤️ et bouton "Répondre" (texte libre).
  Notifie la pension en retour (`type: 'pension_journal_reply'`).
- **Notifications cliquables → destination directe** : les notifications `pension_journal` (nouvelle reçue
  par le propriétaire) et `pension_journal_reply` (like/réponse reçu par la pension) ouvrent désormais
  directement la fiche/le journal concerné au clic, au lieu de rester sans action (app `notifications_page.dart`
  `_handleTap`, web `Header.tsx` `getNotifUrl`).
- **Correctifs indépendants découverts en testant** : `mapProfile()` (`auth-context.tsx`) plantait
  silencieusement sur les profils dont `especes_elevees` est stocké en tableau de chaînes plutôt qu'en
  objets `{espece, races}` — bloquait `userData` (donc toutes les pages pension) pour ces comptes ; nouveau
  hook `usePensionAccess()` remplace le check naïf `userData?.catPro==='pension'` sur 6 pages web pour
  gérer correctement les comptes multi-profils (ex : pension + particulier) ; redirection prématurée vers
  `/connexion` sur rechargement complet corrigée (attente de `authLoading` avant de décider).
- **Infos propriétaire via `animaux_proprietes`** : la recherche par puce (registre + planning) résout
  désormais le propriétaire actuel via `animaux_proprietes` (source unique, `date_fin IS NULL`) au lieu de
  dépendre d'un accès `animal_access` déjà accordé — nom d'élevage prioritaire si le propriétaire est un
  pro, adresse remontée (nouveau champ `proprietaire_adresse` sur `pension_entrees`). App : `_processChip`
  (registre) et `pickAnimalForAdmission` (planning) partagent la même fonction `_lookupAnimalByChip`. Web :
  bug de noms de colonnes corrigé au passage sur la table `users`.
- **Case occupée du planning éditable + rattachement de fiche** : cliquer une case occupée ouvre le
  formulaire d'édition complet (plus un simple résumé lecture seule). Si l'entrée n'a pas encore de fiche
  animal liée, bouton "Rattacher une fiche (puce)" qui recherche par puce et déclenche automatiquement la
  demande d'accès (`animal_access`) au propriétaire résolu. App : classe `_PensionEditSheet` rendue publique
  (`PensionEditSheet`), réutilisée par le planning. Web : `PensionEntreeModal` gagne cette même capacité
  (partagée avec le registre).
- **Statut de nettoyage des logements, jour par jour** : nouvelle table `pension_nettoyages` (logement_id,
  date, unique par jour) — remplace l'idée initiale de badge global (`enclos_chenil.dernier_nettoyage`,
  abandonnée) par une ligne dédiée sous chaque logement dans le planning, avec une icône par jour cliquable
  pour marquer/démarquer ce jour comme nettoyé (toggle insert/delete).
- **Lignes multiples selon la capacité + exclusivité "seul"** : un logement de capacité N affiche N lignes
  dans le planning ; les séjours qui se chevauchent sont répartis automatiquement dans la première ligne
  libre (algorithme glouton façon Tetris, calculé à l'affichage — pas de colonne d'assignation persistée).
  Nouveau champ `seul_dans_logement` (BOOLEAN) sur `pension_entrees` : un séjour marqué "doit être seul"
  bloque visuellement les N lignes du logement pour ses dates (bordure rouge + icône 🔒), empêchant d'y
  planifier un autre animal.
- **Suppression d'un séjour (annulation)** : bouton dédié dans le formulaire d'édition (app et web), avec
  confirmation avant suppression définitive de la ligne `pension_entrees`.
- **Champs espèce/race manquants dans l'édition (app)** : `PensionEditSheet` (ouvert au clic sur une case
  occupée du planning) n'affichait ni ne sauvegardait `espece`/`race` — d'où l'impression que ces infos
  « disparaissaient » après enregistrement. Section "Animal" ajoutée avec ces deux champs.
- **Bouton "Demander l'accès à la fiche"** : ajouté à côté de "Voir la fiche" (app + web), visible quand une
  fiche est rattachée mais qu'aucune demande d'accès n'existe encore — évite de dépendre uniquement du
  rattachement initial pour déclencher la demande.
- **Découverte majeure — `pension_acces` (legacy) vs `animal_access` (unifié)** : plusieurs pages web
  (`Header.tsx` — dialogue d'autorisation du propriétaire, `pension/fiche/[animalId]`, `pension/registre`,
  `pension/demandes`) lisaient/écrivaient encore l'ancienne table `pension_acces`, alors que l'app et tout
  le travail pension de cette session utilisent la table unifiée `animal_access` (prévue par
  `migration_v2_02_access_members.sql`, déjà écrite mais dont la bascule des pages consommatrices n'avait
  jamais été terminée). Conséquence concrète : une demande d'accès créée via l'app ou le nouveau flux web
  était invisible sur `pension/fiche`/`pension/demandes`, et le bouton Autoriser/Refuser du propriétaire
  (web) ne faisait rien (update sur une table qui ne contenait pas la ligne). Les 4 pages web sont
  maintenant alignées sur `animal_access` (statuts `pending`/`active`/`revoked`, résolution via
  `pro_profile_id`). Le carnet santé de l'animal est obligatoire pour toute réservation en pension côté
  produit, mais l'approbation du propriétaire reste requise (pas de contournement) — seule la lecture
  "aperçu" (nom/espèce/race, déjà visible sans accès) et le journal de séjour (`pension_updates`, non gaté)
  sont accessibles sans validation.
- **Bug Next.js — `params` non déballé** : `reclamer-animal/[token]` et `signer-cession/[token]` accédaient
  encore `params.token` directement (ancienne API Next.js) au lieu de `use(params)` — corrigé sur les deux.
- **Retrouver via la puce (backfill)** : les séjours créés avant les correctifs ci-dessus ont parfois
  race/espèce/propriétaire vides en base. Bouton "Retrouver via la puce" dans le formulaire d'édition
  (app + web) — relance la recherche par puce déjà enregistrée et complète uniquement les champs vides
  (ne écrase jamais une saisie manuelle existante).
- **Accès employés au planning + fiches en pension** : nouvelle permission `read_planning_pension` dans le
  catalogue `employe_permissions` (aucune migration — juste une nouvelle valeur texte). Un employé avec
  cette permission voit un bouton "📅 Planning" sur la carte de son employeur (si `cat_pro = 'pension'`)
  dans "Mes employeurs" (app : `MesEmployeursPage`, web : `/mes-employeurs`), qui ouvre le planning
  d'occupation de l'employeur en **lecture seule** (pas de création/édition/nettoyage — clic sur une case
  occupée affiche juste un résumé + lien "Voir la fiche"). App : `PensionPlanningPage` gagne
  `employerUid`/`employerNom`. Web : `/pension/planning?employerUid=...`, vérifie la permission côté client
  avant de charger les données, sinon redirige vers `/mes-employeurs`. La fiche pension
  (`/pension/fiche/[animalId]`) a aussi été étendue : si l'utilisateur n'a pas d'`animal_access` direct, elle
  vérifie s'il est employé (avec la permission) d'une pension qui, elle, a l'accès actif — et utilise le
  profil de l'employeur pour résoudre le séjour en cours.
- **Bug — "Rattacher/Retrouver via la puce" ne persistait rien** : `_linkFiche()`/`_retrouverViaPuce()` (app)
  et leurs équivalents web ne faisaient que remplir les champs du formulaire en mémoire (`setState`/`setForm`)
  sans jamais écrire en base — les infos retrouvées disparaissaient si l'utilisateur ne cliquait pas ensuite
  sur "Enregistrer". Les deux actions persistent désormais immédiatement les champs retrouvés (nom/contact/
  email propriétaire, espèce/race, animal_id) dans `pension_entrees`.
- **Bug — compteurs tableau de bord pension pas à jour** : la carte "Pensionnaires" comptait les lignes
  `animal_access` actives (accès à la fiche accordé) au lieu du nombre de séjours réellement en cours
  (`pension_entrees` statut `en_pension`) — deux choses différentes, un séjour peut exister sans que l'accès
  fiche ait été demandé/approuvé. Corrigé côté app (`eleveur_home.dart`). Sur les deux plateformes, le calcul
  "places disponibles" comptait aussi les réservations **futures** comme occupant une place dès aujourd'hui —
  filtré désormais sur `date_entree <= aujourd'hui`.
- **Bug — approbation d'accès silencieusement sans effet (`is_main` vs profil actif)** : quand une pension
  demande l'accès à une fiche, la ligne `animal_access` est créée avec le `pro_profile_id` du profil
  **actif** au moment de la demande. Mais côté propriétaire, l'écran d'autorisation (web `Header.tsx`,
  app `notifications_page.dart`, pension et vétérinaire) résolvait le profil du demandeur via
  `is_main = true` — si le compte a plusieurs profils et que le profil actif à la demande n'était pas le
  profil principal, l'`UPDATE` ne matchait aucune ligne et l'accès restait bloqué à `pending` indéfiniment
  (symptôme observé : "Accès non autorisé" persistant côté site même après clic sur Autoriser). Corrigé pour
  résoudre **tous** les profils du compte demandeur plutôt que le seul profil principal. Une demande déjà
  bloquée par ce bug doit être réapprouvée une fois après ce correctif pour se débloquer.
- **Vraie cause de "les infos disparaissent en rouvrant" — trouvée via un dump JSON de la ligne** :
  contrairement à ce qu'on pensait, les données étaient bien correctement enregistrées en base
  (`pension_entrees` contenait espece/race/puce/proprietaire_contact/email/adresse). Le bug était côté
  **lecture** : la requête `SELECT` du planning web (`pension/planning/page.tsx`) listait explicitement ses
  colonnes et avait tout simplement oublié `espece, race, puce, proprietaire_contact, proprietaire_email,
  proprietaire_adresse, notes` — ces champs n'existaient donc jamais dans l'objet chargé, d'où des champs
  vides à chaque réouverture alors que la base était correcte. L'app et le registre web utilisaient déjà
  `select()`/`select('*')` (toutes colonnes) et n'étaient pas concernés.
- **Accès lecture automatique à l'admission en pension** : décision produit confirmée par l'utilisateur
  ("le carnet de l'animal est obligatoire à l'inscription") — dès qu'une pension rattache/admet un animal
  via la puce (création d'entrée, `_linkFiche`, `_retrouverViaPuce`, scan dans "Fiches accessibles"),
  l'accès `animal_access` est créé/mis à jour directement en statut `active` (lecture : identité, santé,
  alimentation), **sans attendre l'approbation du propriétaire**. Le propriétaire reçoit toujours une
  notification, mais informative — le dialogue passe de "Autoriser/Refuser" à "OK/Révoquer l'accès"
  (web `Header.tsx`, app `notifications_page.dart`). Ne change rien pour les autres contextes (vétérinaire,
  demandes hors admission) qui restent soumis à validation explicite du propriétaire.
- **"Accès non autorisé" toujours bloqué malgré le fix ci-dessus — 3 bugs de plus trouvés en creusant un cas
  réel (fiche Utha/Pomsky déjà entièrement remplie)** :
  1. `retrouverViaPuce()`/`_retrouverViaPuce()` ne demandait/accordait l'accès **que** si des champs
     manquaient à compléter — pour un animal déjà entièrement rempli en base, rien à backfiller ⇒ la
     fonction ne faisait strictement rien, sans erreur visible. Corrige : accorde l'accès inconditionnellement
     dès que `animalId`+`ownerUid` sont connus, indépendamment du backfill des champs.
  2. `requestAnimalAccess()`/`_requestAccessTo()` faisaient un no-op silencieux dès qu'une ligne
     `animal_access` existait déjà, **quel que soit son statut** — une ligne restée bloquée à `pending`
     (créée avant le passage en lecture automatique) n'était donc jamais remontée à `active`. Corrige :
     remonte à `active` une ligne existante non-active au lieu de l'ignorer.
  3. La résolution du profil du propriétaire exigeait `is_main = true` — si le compte propriétaire n'a pas
     de profil marqué principal, la résolution échouait silencieusement et rien n'était créé. Corrige :
     profil principal en priorité, sinon n'importe quel profil du compte.

### 19.3 — Migrations à exécuter (si pas déjà fait)

```
supabase/migration_pension_logements.sql        -- logement_id, tarifs_logements, arrhes_pourcentage
supabase/migration_pension_contrat.sql          -- pension_entree_id sur documents_animaux
supabase/migration_pension_plans_tarifaires.sql -- 3 formules pension dans plans_tarifaires
supabase/migration_enclos_chenil_especes.sql    -- especes sur enclos_chenil
supabase/migration_animaux_owner_uid_claims.sql -- owner_uid sur animaux + table animal_claims
supabase/migration_pension_updates.sql          -- table pension_updates (journal de séjour)
supabase/migration_pension_entrees_proprietaire_adresse.sql -- proprietaire_adresse sur pension_entrees
supabase/migration_pension_solo_nettoyage.sql   -- seul_dans_logement sur pension_entrees
supabase/migration_pension_nettoyages_jour.sql  -- table pension_nettoyages (nettoyage jour par jour)
supabase/migration_v2_02_access_members.sql     -- IMPORTANT si pas déjà fait : crée animal_access et
                                                 -- migre les données pension_acces/vet_access_grants existantes
```

---

## 20. Module Éducateur/Comportementaliste — Phase 1 (session 2026-07-04)

Avant cette session, `education` n'existait que comme valeur de taxonomie
(`profile_type`) : aucune page dédiée, tout le monde partageait les pages
génériques (planning générique, `ProClientsPage`). Demande initiale du
propriétaire, dans l'ordre :
1. Planning des cours individuels ou collectifs
2. Cours à domicile avec trajet et localisation GPS
3. Cours en solo ou en équipe d'intervenants
4. Réservations en direct ou en ligne
5. Tarification automatisée des cours et forfaits
6. Suivi de progression de l'animal + envoi de rapport en 1 clic
7. Emails automatiques (devis, contrats, factures)
8. Notification avant séance (+ SMS) et agenda dynamique avec temps de trajet

Découpage validé avec l'utilisateur : **Phase 1** = socle (items 1, 4 partiel,
5 simple, 6) livré cette session ; **Phase 2** = GPS/trajet, équipe
d'intervenants, tarification automatisée + forfaits, devis auto — différé,
voir §20.2.

### 20.1 — Livré ✅

- **Cours individuels** : aucune nouvelle table nécessaire — le flux de
  réservation générique (`rdv_booking_page.dart`, `RdvBookingPage`) gérait
  déjà les motifs `cours_individuel`/`cours_collectif`/`evaluation` pour
  `cat_pro = 'education'` (durées par défaut déjà présentes dans
  `_defaultDureesByCatPro`). Réutilisé tel quel pour les cours individuels.
- **Cours collectifs** (plusieurs participants sur un même créneau) :
  nouvelles tables `cours_collectifs` (titre, date/heure, durée, capacité
  max, lieu, notes, statut) et `cours_collectifs_participants` (join table,
  statut inscrit/présent/absent/annulé). Migration
  `supabase/migration_education_cours_collectifs.sql`.
- **App** : `lib/pages/pro/education_planning_page.dart` — planning
  hebdomadaire combinant RDV individuels + cours collectifs, création d'un
  cours collectif (bottom sheet), détail d'un cours avec liste des
  participants et gestion du statut (présent/absent/retiré), annulation.
  Accessible depuis le drawer (`eleveur_nav.dart`) pour `cat_pro = 'education'`.
- **Web** : `website/src/app/education/planning/page.tsx` (miroir de la page
  app), nouveau `MENU_EDUCATION` dans `Header.tsx`, hook
  `useEducationAccess.ts` (miroir de `usePensionAccess`).
- **Tarification simple par prestation** : nouvelle colonne
  `user_profiles.tarifs_education` (JSONB, même modèle que
  `tarifs_logements` côté pension) — cours individuel / cours collectif
  (par participant) / évaluation / supplément à domicile. UI ajoutée dans
  `pro_profile_edit.dart` (app) et `profil/page.tsx` (web).
- **Suivi de progression + rapport en 1 clic** : une fonctionnalité
  `education_progression` existait déjà (bouton "Rapport de séance" dans
  `pro_clients_page.dart` → `_addProgression()`) mais n'était ni notifiée ni
  visible côté propriétaire — trou comblé cette session :
  - `_addProgression()` envoie désormais une notification in-app
    (`type: 'education_rapport'`) au propriétaire de l'animal dès
    l'enregistrement (le même clic "Enregistrer" fait office d'envoi —
    "en 1 clic" tel que demandé), sans UI supplémentaire.
  - Nouvelle page `lib/pages/pro/education_rapports_page.dart` (lecture
    seule) affichant l'historique des rapports de séance, accessible via un
    bouton "🐾 Suivi de progression" ajouté sur la fiche animal
    particulier (`animal_fiche_particulier.dart`) et éleveur
    (`animal_fiche.dart`) — même schéma que le bouton "📸 Nouvelles de la
    pension" livré plus tôt.
  - Web : bouton + modale équivalents sur `mes-animaux/[id]/page.tsx`.
  - Notification cliquable : `education_rapport` ouvre directement la page
    de suivi (app `notifications_page.dart`, web `Header.tsx` `getNotifUrl`).
- **Formules d'abonnement PetsMatch** (session 2026-07-05) — distinct de la
  tarification client (ci-dessus), il s'agit des paliers que l'éducateur
  paie à PetsMatch pour débloquer des fonctionnalités, comme pour la
  pension. Constat : `plans_tarifaires` n'avait aucune ligne pour
  `profil_type = 'education'`, et le système de vérification des
  fonctionnalités (`PlanService`) était codé en dur spécifiquement pour la
  pension. Découverte au passage : même pour la pension, les flags de
  fonctionnalités (`hasEmployes`, `hasInventaire`, etc.) ne sont **jamais
  appliqués en dur nulle part** — uniquement affichés sur la page
  abonnement pour orienter l'achat Stripe, sans blocage technique réel.
  Le même pattern (affichage + upsell, pas de blocage) a été répliqué pour
  l'éducateur, par cohérence avec l'existant :
  - 3 paliers (Découverte gratuit / Pro 14€ / Premium 24€, mêmes prix que
    pension) — les fonctionnalités "cœur" (planning, cours
    individuels/collectifs, tarification, suivi de progression,
    réservation en ligne) restent disponibles à tous les paliers ; seuls
    les employés, l'export facturation et les avantages de visibilité
    sont différenciés par palier.
  - `EducationPlanConfig` + `getEducationPlansLive()`/`getEducationPlanCode()`
    ajoutés dans `plan_service.dart` (miroir exact de `PensionPlanConfig`).
  - Page app `education_abonnement_page.dart` + page web
    `education/abonnement/page.tsx` (miroir de la page pension), lien
    "Mon abonnement" ajouté au drawer/menu.
  - Stripe : `/api/stripe/checkout` était déjà générique par
    `profil_type` (confirmé dans le code) — aucune modification de code
    nécessaire côté paiement, juste le seed de `plans_tarifaires`.
- **Bilan préalable obligatoire pour les nouveaux clients** (session 2026-07-05) :
  un nouveau client ne peut réserver qu'un bilan (évaluation) tant qu'il n'a
  pas eu de séance confirmée/terminée avec ce pro — configurable par
  l'éducateur (certains acceptent la prise de cours directement). Nouveau
  toggle "Exiger un bilan avant les cours" dans le profil (app + web,
  colonne `user_profiles.education_bilan_requis`, défaut `true`). Le flux
  de réservation (`RdvBookingPage` app, `services/pro/[uid]/page.tsx` web)
  vérifie si le client a déjà un RDV `confirme`/`termine` avec ce pro ;
  si non et que l'exigence est active, seul le motif "Évaluation" est
  proposé, avec un message explicatif.
- **Lien "Mes élèves" manquant dans le menu web éducateur** : la page
  `/mes-patients` (déjà générique, déjà labellisée "Mes élèves" pour
  `cat_pro = 'education'`) n'était pas dans `MENU_EDUCATION` — ajouté.
- **Bug critique découvert et corrigé — colonne `rdv.notes_annulation`
  inexistante** : référencée dans 5 fichiers (app + web) pour stocker le
  motif de refus/annulation, mais jamais créée en base. Toute requête
  `SELECT` la nommant explicitement échouait (erreur Postgres 42703),
  cassant l'affichage complet de "Mes RDV" pour **tous les profils**, pas
  seulement éducateur. Migration ajoutée pour créer la colonne manquante.

### 20.2 — Reste à faire 🔨 (Phase 2, explicitement différé)

Ordre validé avec l'utilisateur : réservation en ligne cours collectifs → tarification
automatisée + forfaits → devis auto → notification avant séance → GPS/équipe/agenda dynamique.

| Item | Détail | Statut |
|---|---|---|
| Réservation en ligne des cours collectifs | ✅ Livré (session 2026-07-04) : le client parcourt les cours collectifs à venir d'un pro directement sur sa fiche publique (app `service_detail_page.dart`, web `services/pro/[uid]/page.tsx`), choisit l'animal concerné, s'inscrit avec vérification de capacité (refus si complet), et le pro reçoit une notification (`type: 'cours_collectif_inscription'`, cliquable vers le planning). | Livré |
| Tarification automatisée + forfaits | ✅ Livré (session 2026-07-05) : (1) forfaits — le pro crée des packs de séances nommés (nom, nb séances, prix) dans son profil (`forfaits_education` table), affichés publiquement sur sa fiche pro (informationnel, pas de suivi de crédit/solde automatisé, même logique que `tarifs_education`) ; (2) tarification automatisée — le prix du cours collectif (`tarifs_education['cours_collectif']`) s'affiche désormais automatiquement au client lors de la réservation en ligne et est figé sur la ligne `cours_collectifs_participants.prix` au moment de l'inscription (pour référence/facturation même si le tarif change plus tard). Pas de calcul selon poids animal — jugé hors scope pour un éducateur (pertinent surtout pour la pension). | Livré |
| Devis automatique | ✅ Livré (session 2026-07-06) : nouvelle table `devis` (numéro, lignes, statut brouillon/envoyé/accepté/refusé/expiré, token d'acceptation public). Le pro sélectionne le client via recherche PetsMatch ou saisie libre. Web : `education/devis/page.tsx` (liste + création) + `devis/[token]/page.tsx` (page publique d'acceptation client, sans compte). App : `education_devis_page.dart`. Le devis se lie à l'animal concerné et apparaît dans ses documents, visible côté client uniquement si un devis/rapport éducateur existe réellement pour cet animal. Après acceptation : simple changement de statut, pas de génération automatique de facture. | Livré |
| Notification avant séance | ✅ Livré (session 2026-07-06), **in-app uniquement** (SMS explicitement écarté par l'utilisateur pour l'instant). Système de rappel existant (`rdv.reminder_48h/24h/1h/15min_sent`, Netlify function `send-rdv-reminders.mts`) étendu pour couvrir aussi `cours_collectifs` (nouvelles colonnes identiques + notification à chaque participant inscrit). | Livré |
| Cours à domicile + GPS/trajet | ✅ Livré (session 2026-07-08), **approche à vol d'oiseau** (pas d'API Directions payante — cohérent avec le choix initial `Geolocator.distanceBetween`). Géocodage automatique du champ `rdv.lieu` (texte libre) en coordonnées GPS via le package `geocoding` (app, déjà utilisé ailleurs) / `api-adresse.data.gouv.fr` (web, gratuit) au moment de l'enregistrement — nouvelles colonnes `rdv.lieu_lat`/`lieu_lng`. | Livré |
| Équipe d'intervenants | ✅ Livré (session 2026-07-08) : nouvelle colonne `instructeur_profile_id` sur `rdv` et `cours_collectifs` (référence `user_profiles`). Sélecteur "Intervenant assigné" dans le formulaire de modification du RDV (app `pro_agenda.dart`, web `mes-rdv/page.tsx::ModifierModal`), liste chargée depuis la table `employes` existante (aucune permission supplémentaire, juste une assignation). | Livré |
| Agenda dynamique avec temps de trajet + alerte retard | ✅ Livré (session 2026-07-08) : pour deux RDV confirmés le même jour, tous deux géocodés, dont l'écart entre fin du premier et début du second est inférieur au temps de trajet estimé (distance à vol d'oiseau ÷ 30 km/h), un bandeau "⚠️ Risque de retard" s'affiche — app (carte "Aujourd'hui" de `pro_agenda.dart`) et web (haut de `agenda/page.tsx`). | Livré |
| Emails automatiques devis/contrats/factures | Dépend du devis (ci-dessus, maintenant livré) ; contrats/factures existent déjà mais sans envoi email automatique dédié à l'éducateur. Décision explicite de l'utilisateur : reste en attente, l'in-app est privilégié partout ailleurs dans le module. | Non commencé |

### 20.3 — Migration à exécuter

```
supabase/migration_education_cours_collectifs.sql -- cours_collectifs,
                                                   -- cours_collectifs_participants,
                                                   -- tarifs_education sur user_profiles
supabase/migration_education_plans_tarifaires.sql -- 3 formules éducateur dans plans_tarifaires
supabase/migration_education_forfaits.sql         -- table forfaits_education,
                                                   -- colonne prix sur cours_collectifs_participants
supabase/migration_education_bilan_requis.sql     -- colonne education_bilan_requis sur user_profiles
supabase/migration_rdv_notes_annulation.sql        -- IMPORTANT (bug critique) : colonne
                                                   -- notes_annulation manquante sur rdv,
                                                   -- cassait "Mes RDV" pour tous les profils
```

---

## 21. Système RDV — Modification, lieu & rappels (session 2026-07-05)

Fonctionnalités génériques (tous types de pro), pas spécifiques à l'éducateur,
demandées pendant les tests du module éducateur.

- **Modifier un RDV confirmé** : nouveau bouton "✏️ Modifier" dans l'onglet
  "À venir" de "Mes RDV" (web `mes-rdv/page.tsx`) — permet de changer
  date/heure/durée/motif/lieu/notes sur un RDV déjà confirmé (jusqu'ici seul
  Terminé/Annuler existait). Synchronise `agenda_events` (pro + client),
  notifie le client (`type: 'rdv_modifie'`), et réinitialise les 4 flags de
  rappel (`reminder_48h_sent`/`24h`/`1h`/`15min`) pour qu'ils se redéclenchent
  sur la nouvelle date. **Livré aussi côté app** (`pro_agenda.dart` —
  `_showModifierDialog`/`_modifierRdv`, même logique de synchronisation).
- **Lieu du RDV** : nouveau champ texte libre `rdv.lieu` (au cabinet, au
  domicile du client, personnalisé) éditable via "Modifier". Le calcul de
  trajet/GPS complet (Directions API, distance, alerte retard) reste en
  backlog Phase 2 éducateur item 5/5 — ici c'est juste un texte informatif.
- **Rappels de RDV** : les colonnes `reminder_48h_sent`/`24h`/`1h`/`15min`
  existaient sur `rdv` depuis longtemps mais **rien ne les envoyait jamais**
  (seulement réinitialisées à `false` lors d'un changement d'heure). Nouvelle
  Netlify Scheduled Function `send-rdv-reminders.mts` (tourne toutes les
  15 min) : pour chaque palier, sélectionne les RDV `confirme` dont l'heure
  approche et dont le flag n'est pas encore passé à `true`, envoie une
  notification (`type: 'rdv_rappel'`) **au pro ET au client**, puis marque
  le flag comme envoyé.
- **Agenda multi-profil** : vérifié en détail (app `agenda_page.dart`, web
  `agenda/page.tsx`) — la synchronisation `agenda_events` scopée par
  `pro_profile_id`/profil actif existait déjà et fonctionne correctement
  (y compris avec "Modifier" ci-dessus). Aucun changement de code nécessaire.

- **Créneaux réservés individuel/collectif** (éducateur) : quand le pro
  crée une plage "Disponible" dans "Mes créneaux" (web), il peut la marquer
  "🎓 Individuel" / "👥 Collectif" / "Les deux" (`creneaux_pro.type_prestation`).
  Un créneau marqué "collectif" n'est plus proposé au client lors d'une
  réservation de RDV individuel (`services/pro/[uid]/page.tsx`) — il reste
  réservé à la planification des cours collectifs du pro. **Web
  uniquement** pour l'instant, pas encore côté app.

### 21.1 — Migrations à exécuter

```
supabase/migration_rdv_lieu.sql                    -- colonne lieu (texte) sur rdv
supabase/migration_creneaux_type_prestation.sql    -- colonne type_prestation sur creneaux_pro
```

### 21.2 — Reste à faire

- ✅ Créneaux individuel/collectif côté app (Flutter) — livré, voir §20.
- ✅ GPS/trajet complet (Phase 2 éducateur item 5/5) — livré, voir §26.

## 22. Onglet "Éducation" dans la fiche animal + correctif agenda (session 2026-07-05)

- **Fiche animal — onglet Éducation** : un éducateur/comportementaliste
  consultant la fiche d'un animal client voyait jusqu'ici les mêmes onglets
  génériques que n'importe quel autre pro non-vétérinaire, dont
  "Consultations" (vaccins/visites/traitements — non pertinent pour ce
  métier). Remplacé par un onglet dédié "Éducation" (app `animal_fiche.dart`
  → `AnimalFichePage(educationMode: true)` déclenché depuis
  `ProClientsPage._openAnimal()` ; web `mes-patients/[id]/page.tsx` via
  `isEducation`) qui affiche l'historique des rapports de séance
  (`education_progression`) avec un champ dédié **"Exercices conseillés"**,
  distinct du compte rendu libre, affiché à part pour le propriétaire.
  Rétro-compatible avec l'ancien point d'entrée rapide "Rapport de séance"
  depuis la liste des clients (`pro_clients_page.dart::_addProgression`),
  qui a aussi reçu le nouveau champ. Affichage côté propriétaire mis à jour
  en conséquence (app `education_rapports_page.dart`, web
  `mes-animaux/[id]/page.tsx`).
- **Agenda web — bug vue Jour** : voir §21 modification du 2026-07-05 —
  cliquer sur "Jour" réinitialisait toujours la date à aujourd'hui au lieu
  de préserver le jour sélectionné en vue Mois, faisant "disparaître" un
  RDV visible sur un autre jour. Corrigé (`agenda/page.tsx`).

### 22.1 — Migration à exécuter

```
supabase/migration_education_exercices_conseilles.sql  -- colonne exercices_conseilles sur education_progression
```

## 23. Séances du jour + raccourci rapport depuis le planning (session 2026-07-05)

- **Cours collectifs visibles dans l'agenda** : la création d'un cours
  collectif (app `education_planning_page.dart`, web
  `education/planning/page.tsx`) synchronise désormais aussi une entrée
  `agenda_events` pour le pro (même mécanisme que les RDV confirmés,
  `type: 'cours_collectif'`, `couleur: 'cours:<id>'`) — jusqu'ici un cours
  collectif n'apparaissait nulle part dans l'agenda du pro qui l'avait créé.
- **"Aujourd'hui" en tête d'agenda** : pas de page d'accueil dédiée
  éducateur, donc résumé ajouté directement en tête de "Mon agenda"
  (app `ProAgendaPage`, web `mes-rdv/page.tsx`) — liste compacte des
  séances du jour (RDV confirmés + cours collectifs confondus, lues via
  `agenda_events`), pastille violette pour les cours collectifs vs teal
  pour les RDV individuels.
- **Raccourci "Ajouter un rapport" depuis le planning** : dans le détail
  d'un cours collectif (app + web), un bouton 🎓 par participant ouvre
  directement l'onglet Éducation de la fiche de l'animal
  (`AnimalFichePage(initialTabIndex: 2)` côté app,
  `/mes-patients/[id]?tab=Éducation` côté web — nouveau support du
  paramètre `?tab=` sur cette page).

## 24. Correctifs agenda app (session 2026-07-05)

- **Fuite cross-profil élevage → pension** : `lib/pages/agenda/agenda_page.dart`
  incluait toujours les événements "legacy sans profile_id" en plus de ceux
  du profil actif (`epid == pid || epid.isEmpty`), même quand un profil
  secondaire précis (ex : pension) était actif. Or les événements créés
  depuis le profil éleveur (primaire, `pro_profile_id` vide) tombent dans ce
  cas "legacy" — ils étaient donc visibles depuis N'IMPORTE QUEL profil
  secondaire. Corrigé : filtre strict par `pro_profile_id` dès qu'un profil
  est actif ; le fallback "legacy" ne s'applique plus qu'au profil primaire
  (pid vide). Le web (`agenda/page.tsx`) avait déjà la bonne logique — bug
  app uniquement.
- **Bouton Retour depuis la vue Jour** : cliquait directement `widget.onBack`
  (quitte l'agenda) peu importe la vue active. Corrigé pour repasser
  d'abord en vue Mois si on n'y est pas déjà, avant de quitter la page.

## 25. Fuite cross-profil côté CLIENT dans agenda_events (session 2026-07-05)

- **Cause racine identifiée** : quand un pro confirme un RDV, une entrée
  `agenda_events` miroir est créée côté CLIENT pour qu'il voie le RDV dans
  "Mon agenda". Cette synchronisation renseignait bien `pro_profile_id`
  côté PRO, mais **jamais côté CLIENT** — laissée NULL. Résultat : dès que
  le client consultait un profil dont `activeProfileId` tombe dans le cas
  "legacy" (règle de compatibilité pour les événements d'avant le
  multi-profil), CE RDV apparaissait — même s'il avait été réservé depuis
  un tout autre profil (ex : RDV pension réservé depuis le profil éleveur,
  visible depuis n'importe quel autre profil du même compte).
- **Corrigé sur tous les points de synchronisation trouvés** : chaque
  upsert `agenda_events` côté client renseigne désormais
  `pro_profile_id: rdv.client_profile_id` (au lieu de rien) :
  - App : `lib/pages/pro/pro_agenda.dart` (3 endroits — confirmation,
    modification, confirmation avec heure précise).
  - Web : `agenda/page.tsx` (accepter une demande depuis Mon Agenda),
    `mes-rdv/page.tsx` (AccepterModal + ModifierModal),
    `pension/rdv/page.tsx` (page dédiée pension, confirmée comme étant
    la source exacte du cas signalé).
  - Web : le modal générique "+ Ajouter" (`agenda/page.tsx::AddModal`)
    ne renseignait PAS DU TOUT `pro_profile_id` sur les événements créés
    manuellement — corrigé aussi (accepte maintenant `profileId` en prop).
- **Backfill nécessaire** : les entrées déjà créées AVANT ce correctif
  restent mal taguées (NULL) tant que la migration n'est pas exécutée.

### 25.1 — Migration à exécuter

```
supabase/migration_backfill_agenda_events_client_profile.sql
```

---

## 26. Module Éducateur/Comportementaliste — Phase 2 complétée (sessions 2026-07-06 / 2026-07-08)

Les 5 items du backlog Phase 2 (§20.2) sont désormais tous livrés, dans
l'ordre validé. Détail des trois derniers :

- **Devis automatique** : nouvelle table `devis` (`numero_devis`,
  `date_devis`, `date_validite`, client PetsMatch ou saisie libre,
  `lignes` JSONB, `total_ttc`, `statut` brouillon/envoyé/accepté/refusé/
  expiré, `token_acceptation`). Le client accepte/refuse sans compte via
  un lien public (`/devis/[token]`, même pattern que `/certificat/[token]`
  déjà existant). Après acceptation : simple changement de statut — pas
  de génération automatique de facture (décision explicite). Le devis se
  lie à l'animal concerné (`documents_animaux`, visible côté client
  uniquement si un devis/rapport éducateur existe réellement pour cet
  animal).
- **Rappels avant séance** : le système de rappel existant sur `rdv`
  (`reminder_48h/24h/1h/15min_sent`, Netlify function
  `send-rdv-reminders.mts` toutes les 15 min) a été étendu pour couvrir
  aussi `cours_collectifs` — mêmes colonnes de rappel, notification
  envoyée au pro et à chaque participant inscrit (`cours_collectifs_participants`).
- **GPS/trajet + équipe d'intervenants + agenda dynamique** : approche à
  vol d'oiseau assumée dès le départ (pas d'intégration d'API Directions
  payante). `rdv.lieu` (texte libre) est géocodé automatiquement à
  l'enregistrement en `rdv.lieu_lat`/`lieu_lng` (package `geocoding` déjà
  utilisé ailleurs côté app, `api-adresse.data.gouv.fr` gratuit côté web).
  Nouvelle colonne `instructeur_profile_id` sur `rdv`/`cours_collectifs`
  pour assigner un employé (réutilise la table `employes` existante, pas
  de nouvelle notion de permission). Quand deux RDV confirmés le même jour
  sont tous deux géocodés et que l'écart entre la fin du premier et le
  début du second est inférieur au temps de trajet estimé (distance à vol
  d'oiseau ÷ 30 km/h), un bandeau "⚠️ Risque de retard" s'affiche — carte
  "Aujourd'hui" de l'agenda pro app, haut de l'agenda pro web.

### 26.1 — Bugs corrigés au passage (découverts en testant le module)

- **Notifications qui fuitent entre profils** : le filtre d'affichage
  (app `notifications_page.dart`, web `/api/notifications`) ne se basait
  que sur `profile_type` (souvent absent à la création), jamais sur
  `profile_id` pourtant bien renseigné sur la ligne — une notif destinée
  à un profil apparaissait aussi sur les autres profils du même compte.
  `profile_id` prime désormais quand présent. Idem pour les notifications
  `tache_validee` (3 points de création, app + web) qui n'écrivaient
  jamais `profile_id`.
- **`agenda_events.pro_profile_id` vide** (rappels chaleurs/mise-bas) :
  `User_Info.activeProfileId` pouvait être lu vide au moment de la
  création du rappel, écrivant une chaîne vide au lieu d'un profil
  valide — invisible dans les vues filtrées par profil. Repli sur le
  profil principal ajouté ; 111 lignes existantes corrigées en base.
- **Annonce visible/modifiable depuis le mauvais profil** : la page
  d'accueil éleveur et le contrôle de propriété d'une annonce (bouton
  "Modifier") ne vérifiaient que l'uid Firebase (partagé entre profils
  d'un même compte), pas le `profile_id` actif — une annonce créée
  depuis le profil association restait modifiable depuis le profil
  éleveur du même compte.
- **Messagerie "Contacter" silencieuse** : la table `conversations` n'a
  jamais eu de colonne `categorie` alors que le code la lit/écrit depuis
  longtemps — toute création de nouvelle conversation échouait
  silencieusement (PGRST204), masqué tant qu'une conversation existait
  déjà entre les deux participants.
- **Itinéraire Waze cassé** (lieux pet-friendly) : lien au format invalide
  (`waze://ul?...` au lieu de `waze://?...`), adresse jamais transmise
  (seulement les coordonnées brutes), et absence de `<queries>` dans le
  manifeste Android (obligatoire dès Android 11 pour détecter une app de
  navigation externe).
- **Carte des professionnels vide côté web** : la requête des profils pro
  secondaires demandait une colonne `name_elevage` inexistante sur
  `user_profiles` (réservée à `users`), faisant échouer toute la requête
  et excluant tous les pros secondaires de la carte. Par ailleurs, la
  création d'un profil pro secondaire (app `add_profile_page.dart`, web
  `profil/ajouter/page.tsx`) enregistrait les coordonnées GPS seulement
  si déjà résolues, sans filet de sécurité comme à l'édition — un pro qui
  tape son adresse sans sélectionner une suggestion restait invisible sur
  la carte pour toujours (4 profils existants sur 8 concernés, corrigés
  en base).

### 26.2 — Migrations à exécuter

```
supabase/migration_education_devis.sql
supabase/migration_cours_collectifs_reminders.sql
supabase/migration_education_intervenants_trajet.sql
supabase/migration_conversations_categorie.sql
```

---

## 27. Module Pension — Phase 2 complétée (session 2026-07-09) + chantier prioritaire suivant

Les 4 items de la Phase 2 Pension (§19.2) sont livrés — détail dans le tableau
mis à jour ci-dessus. Repère utile pour les tests : `enclos_chenil` (logements),
`pension_entrees` (registre), `pension_factures` (nouvelle table, historique +
statut de paiement), `tarifs_pension` (nouvelle colonne JSONB sur `user_profiles`).

### 27.1 — Bug corrigé au passage : `users` / `user_profiles` désynchronisés

En creusant un problème de téléphone/description manquants pour un profil
éleveur, découverte d'un problème plus large :

- **Web sans repli** : `useAuth()` (web) ne lisait que `user_profiles`, sans
  jamais retomber sur `users` (table primaire historique) quand le champ est
  vide — contrairement à l'app qui a déjà cette logique de repli
  (`main.dart::applyProfile`). Corrigé dans `auth-context.tsx` : `mapProfile()`
  accepte désormais une ligne `users` de secours pour bio/banner/téléphone/
  siret/réseaux sociaux/photos, avec traitement spécial du placeholder
  téléphone `"0000000000"` laissé par d'anciens flux de création.
- **Écriture app perdue silencieusement** : la description et le téléphone
  élevage n'étaient enregistrés que dans **Firestore** (`profil_eleveur_edit.dart`),
  plus lu nulle part depuis la migration Supabase — toute modification depuis
  l'app se perdait. Corrigé : écriture désormais dans `users` ET `user_profiles`
  (colonnes `bio`/`description`, `numero_elevage`/`phone_number`).
- **Bug multi-profil dans la gestion des employés** (`employes_page.dart`) :
  la résolution du "profil employeur" se basait sur un champ `is_main` figé
  sur le profil éleveur du compte au lieu du profil réellement actif — un
  employé ajouté depuis n'importe quel profil (éducateur, pension…) se
  retrouvait toujours rattaché au profil éleveur. Corrigé (4 endroits) pour
  utiliser `User_Info.activeProfileId`.

### 27.2 — Chantier prioritaire pour la prochaine session

L'utilisateur a validé la direction : **`users` doit devenir purement
l'identité d'authentification (uid, email, préférences globales), toutes les
données de profil doivent vivre dans `user_profiles`** (une ligne par profil).
C'est déjà la direction du code ("Sync user_profiles (source V2)" en
commentaire à plusieurs endroits), mais la bascule n'est que partielle.

**Ne pas se lancer sans cadrage** : chantier transverse à haut risque, touche
chaque lecture/écriture de profil (cartes, annonces, fiches, création,
édition) sur les 2 plateformes. Repartir de l'audit fait en §27.1 avant
d'étendre à d'autres profils (association, éducateur, pension, vétérinaire…).

### 27.3 — Phase 1 livrée : colonnes synonymes désynchronisées

Audit complet (session suivante) : `users` a ~90 colonnes de profil, la
quasi-totalité dupliquée sur `user_profiles` via ~10 migrations
incrémentales, avec des incohérences de nommage réelles causant des pertes
de données actives (l'app et le site ne lisaient pas les mêmes colonnes
pour un même concept) :

- N° ACACED : `acaced_numero` (lu par l'app) vs `acaced` (lu par le web) —
  `acaced` n'était jamais écrit par aucun code vivant.
- Doc ACACED : `acaced_doc_url` (écrit partout) vs `diplome_url` (seule
  colonne lue par le web) — `diplome_url` n'était jamais écrit.
- Téléphone : `phone` / `phone_number` / `telephone` sur `user_profiles`,
  chaque écran n'en écrivant qu'un ou deux à la fois.

Corrigé via `supabase/migration_sync_profile_synonyms.sql` : trigger
Postgres (`BEFORE INSERT OR UPDATE`) qui recopie automatiquement toute
écriture sur une de ces colonnes vers ses synonymes (sur `user_profiles`
et sur `users` pour `acaced_numero`/`acaced`), + backfill ponctuel des
lignes déjà divergentes. Approche DB plutôt que retouche des ~15 sites
d'écriture recensés : transparente pour tout code existant, futur-proof
contre un nouveau site d'écriture qui oublierait une colonne. Vérifié en
live : écriture sur une seule colonne → synonymes mis à jour
automatiquement.

Corrigé au passage : deux lectures mortes de colonnes inexistantes sur
`users` (`users.phone`, `users.telephone` — seule `phone_number` existe
réellement) dans `website/src/app/associations/[id]/page.tsx` et
`website/src/app/elevages/[id]/page.tsx`, redirigées vers `phone_number`.

**Reste pour une Phase 2** : synchronisation *entre* `users` et
`user_profiles` (`numero_elevage` notamment, écrit sur `users` sans être
répercuté sur `user_profiles` dans 2 écrans web) — plus invasif
(cross-table), non traité dans cette phase.

### 27.4 — Phase 2 livrée : complétude des écritures vers user_profiles

Audit champ par champ des ~11 sites d'écriture (voir §27.3) : `numero_tva`,
`acaced`, `kbis_url`, `acaced_doc_url`, `especes_elevees`,
`acaced_date_obtention`, `acaced_date_renewal` manquaient côté
`user_profiles` dans 3 fichiers (`profil_eleveur_edit.dart`,
`profil/page.tsx`, `elevage/profil/edit/page.tsx`) alors qu'ils étaient
bien écrits sur `users` — confirmé en base sur un profil réel (3 espèces
sur `users.especes_elevees`, tableau vide sur `user_profiles`). Un 4e
fichier (`inscription_restauration_pro_page.dart`) ne synchronisait pas
`firstname`/`lastname`/`phone_number`. Corrigé par ajout des champs
manquants aux objets d'écriture existants, sans nouvelle logique.

**Trouvé au passage, hors scope de cette phase** : aucun compte n'obtenait
de ligne `user_profiles` à l'inscription (`verifemail.dart`,
`inscription/page.tsx` n'écrivent que sur `users`) — traité en Phase 3.

### 27.5 — Phase 3 livrée : ligne user_profiles automatique à l'inscription

`is_main = true` est lu par ~90 endroits du code pour résoudre "le profil
principal du compte", la plupart sans repli — un compte sans aucune ligne
`is_main=true` (le cas de tout nouveau compte avant Phase 3, tant qu'il
n'a pas explicitement ajouté un profil) cassait silencieusement l'agenda,
la pension, les employés, Stripe, les fiches animaux, etc.

Corrigé via `supabase/migration_auto_create_main_profile.sql` : trigger
`AFTER INSERT ON users` qui crée automatiquement une ligne `user_profiles`
(`is_main=true`) avec le `profile_type` déduit des colonnes déjà connues
à l'inscription (`is_association`/`is_elevage`/`is_pro`+`cat_pro`). Filet
de sécurité à deux niveaux (repli `particulier` minimal, puis silence
total) pour ne jamais bloquer une inscription si le type déduit posait
problème. Idempotent (`ON CONFLICT (uid, profile_type) DO NOTHING`) —
si l'utilisateur complète ensuite son profil via "ajouter un profil",
l'upsert met à jour la ligne déjà créée au lieu d'en dupliquer une, et
`is_main` reste intact. Backfill défensif inclus (0 compte orphelin
constaté). Vérifié en live avec 3 types de compte (particulier, éleveur,
vétérinaire) : ligne créée avec le bon `profile_type` et `is_main=true`
à chaque fois.

**Chantier §27.2 maintenant sur une base saine** : `user_profiles` a
toujours une ligne principale dès l'inscription, complète pour tous les
champs connus, et synchronisée sans divergence de nommage avec `users`.
Reste pour une passe future : la bascule complète (arrêter d'écrire sur
`users`), et le nettoyage du modèle d'adresse à 3 variantes / des
booléens redondants avec `profile_type` — non traités, périmètre plus
large qu'une session.

### 27.6 — Phase 4 livrée (lot 1) : messagerie + profil public vers user_profiles

Reste du risque inverse : ~62 fichiers lisent des données de profil
directement sur `users` sans jamais consulter `user_profiles` — figées
si on arrête un jour d'écrire les profils sur `users`. Audit fait,
classé par risque/impact, trop large pour une session — traité par lots.

**Lot 1 (ce lot)** : messagerie (`lib/utils/messaging_helper.dart`,
`lib/pages/chatScreen.dart`, `lib/pages/message.dart` — 3 implémentations
dupliquées du même calcul nom/photo, unifiées en une méthode partagée
`MessagingHelper.getDisplayInfo()` qui lit `user_profiles`) + page de
profil public web (`website/src/app/profil/[uid]/page.tsx`). Vérifié en
live : résolution nom/photo correcte pour un profil éleveur (utilise
`nom` de `user_profiles` plutôt que `name_elevage` de `users`).

**Hors scope, flaggé pour un lot futur** : `chatScreen.dart::_navigateToUser`
(fiche complète éleveur/pro ouverte depuis le chat) recouvre le même
territoire que `user_elevage_feed.dart`/`UserDetailPageFeed` — nécessite
sa propre passe car certains champs legacy (`is_dog`/`dog_breeds`/
`cat_breeds`) n'ont pas d'équivalent sur `user_profiles`.

**Lots restants** (par ordre d'impact décroissant, voir audit complet
dans l'historique de session) : pages association (bénévoles, familles
d'accueil, groupes communauté) ; pages particulier (feed, animaux
acquis/perdus, promenades). *(Voir §27.9 — cette liste s'est révélée
incomplète : le lot association/particulier a été livré, mais un audit
plus large a trouvé un reste bien plus important que prévu.)*

### 27.7 — Phase 4 livrée (lot 2) : documents légaux/financiers vers user_profiles

Ciblait la catégorie la plus à risque : `certificats_engagement`, `devis`,
`documents_animaux` ne stockent jamais l'identité de l'émetteur à la
création (seulement son `uid` en FK) — les pages publiques de signature
(`certificat/[token]`, `devis/[token]`, `signer-contrat/[token]`) sont
donc la source primaire, pas juste un affichage. Un siret/adresse figé y
serait injecté tel quel dans un document signé, pas juste un avatar
périmé.

10 fichiers migrés (6 web, 4 app) selon 2 motifs : lecture directe du
profil (FK connue ou profil courant) → bascule simple vers
`user_profiles` (`is_main=true`) ; recherche live d'acquéreur/adoptant
par nom OU email (pas de `profile_id` connu à l'avance, 5 fichiers) →
recherche par nom bascule vers `user_profiles`, recherche par email garde
`users.email` (seul champ légitimement d'identité, absent de
`user_profiles`) puis enchaîne une requête `user_profiles` pour les
champs de préremplissage (téléphone/adresse/siret). Vérifié en live :
requêtes de recherche et de lookup par FK renvoient bien les champs à
jour de `user_profiles` (siret, adresse pro complète, téléphone) pour un
profil éleveur réel.

### 27.8 — Phase 4 livrée (lot 3) : agenda/planning/employés vers user_profiles

13 fichiers (9 web, 4 app dont `employes_page.dart` à elle seule 8 sites
d'appel) — toutes des résolutions de nom d'affichage sur un `uid` déjà
connu (assigné de tâche, employé, client de RDV, participant de cours,
auteur de mouvement d'inventaire/commentaire), aucune recherche live.
Web `elevage/agenda/page.tsx` : 6 lookups "mon propre nom" quasi
identiques dédupliqués en une fonction module-level `resolveDisplayName()`
réutilisée partout dans le fichier.

Deux bugs préexistants corrigés au passage : `agenda/page.tsx` lisait
`nom, prenom` sur `users` — colonnes qui n'existent pas (seuls
`firstname`/`lastname` existent) — le nom du client RDV en attente
retombait toujours sur "Client" ; `vet_patients_page.dart` lisait
`client?['isElevage']`/`['isPro']` en camelCase sur un résultat Supabase
snake_case, branche toujours morte empêchant l'affichage du nom
d'élevage pour un client éleveur d'un vétérinaire. Les deux sont
corrigés en même temps que la bascule, comportement visible amélioré.
Exclu du lot : `pro_zone_page.dart` (lat/lng/rayon d'intervention, pas
des données de profil affichées).

### 27.9 — Phase 4 livrée (lot 4) : association/particulier/promenades + périmètre réel restant

16 fichiers ciblés (bénévoles, familles d'accueil, groupes communauté,
promenades, feed particulier, animaux acquis/perdus, badge pro sur
annonces, journal pension) + 2 trouvés en passant appartenant au même
motif (`promenade_detail_page.dart`, équivalent Flutter oublié de la
page web promenades ; `website/src/app/employes/page.tsx`, gestion
employés pro générique distincte de celle déjà migrée au lot 3).

Cas particulier traité : `association/familles-accueil` (web + app)
charge la liste et filtre côté client par nom **et email** — `email`
n'a pas d'équivalent sur `user_profiles`. Requête `user_profiles`
principale + requête `users.select('uid, email')` fusionnée par uid pour
garder le filtre email et le préremplissage du formulaire fonctionnels.
`annonces/page.tsx` : `statut_pro`/`siret` basculent vers `user_profiles`,
`is_premium` (identité/abonnement) reste sur `users`, 2 requêtes fusionnées.

**Correction importante sur l'ampleur du chantier** : un audit de
vérification avant ce lot a montré que la liste "lots restants" notée
plus haut était incomplète. Il reste en réalité ~25-30 fichiers app et
~15-20 fichiers web non migrés, concentrés dans 4 familles non encore
traitées :
- **Annuaire pro / édition de profil** : `pro_profile_edit.dart`,
  `profil_eleveur_edit.dart` (lecture `banner_url`),
  `profil_association_edit.dart`, `service_list_page.dart`,
  `service_detail_page.dart`, pages admin (`pro_list.dart`,
  `pro_detail.dart`), web `services/page.tsx`, `services/carte/page.tsx`,
  `services/pro/[uid]/page.tsx`, `admin/page.tsx`.
- **Annonces (création/détail/feed/carte)** : `create_annonce_page.dart`,
  `annonce_detail_page.dart`, `annonces_feed_page.dart`,
  `annonces_map_page.dart`, `create_annonce_asso_page.dart`, web
  `annonces/[id]/page.tsx`, `annonces/feed/page.tsx`,
  `association/annonces/creer/page.tsx`.
- **PetFriends** : `petfriends_page.dart`, `public_profile_page.dart`
  (a déjà un repli `user_profiles` partiel non utilisé en premier),
  web `petfriends/page.tsx`.
- **Annuaire associations/élevages** : `associations_list_page.dart`,
  `mes_associations_benevole.dart`, web `mes-associations/page.tsx`,
  `mes-employeurs/page.tsx`.

Plus des lookups isolés (`chip_scanner_service.dart`, `lieu_detail_page.dart`,
recherches live par nom/email non couvertes dans `education_devis_page.dart`,
`cession_sheet.dart`, `contrat_reservation.dart`, pages `mes-rdv`/
`mes-patients`/`mes-animaux` côté web). Périmètre trop large pour une
session — décision explicite de s'arrêter à ce lot et documenter le
reste plutôt que de continuer sans cadrage. **Ne pas repartir de zéro** :
utiliser le pattern déjà établi (bascule `.from('users')` →
`.from('user_profiles').eq('is_main', true)`, `name_elevage`→`nom`,
`is_elevage`→`profile_type==='eleveur'`, `profile_picture_url`→
`avatar_url`) et découper par famille comme ci-dessus.

### 27.10 — Phase 4 livrée (lot 5) : annuaire pro / édition de profil

**Découverte majeure au passage** : `lib/pages/pro/pro_profile_edit.dart`
(édition du profil PRINCIPAL, pas secondaire) n'écrivait **que** sur
`users` à la sauvegarde — jamais sur `user_profiles`. Contrairement aux
trous ponctuels de la Phase 2 (quelques champs manquants), ici c'était
le flux entier qui ne synchronisait jamais `user_profiles` après le
premier edit d'un pro sur son profil principal. Corrigé en ajoutant un
update miroir vers `user_profiles` (`is_main=true`), même mapping que
la branche profil secondaire déjà correcte du même fichier
(`rue`→`rue_pro`, `avatar_url`→`profile_picture_url_pro`, etc.). Ce fix
d'écriture était un préalable obligatoire avant de pouvoir migrer la
lecture de ce fichier sans afficher de données figées.

Bascule lecture ensuite sur 6 fichiers en lookups directs par uid connu
(pro_profile_edit.dart branche principale, banner_url de
profil_eleveur_edit.dart, `_toggleNearMe`/`toggleNearMe` de
service_list_page.dart et services/carte/page.tsx, service_detail_page.dart
et services/pro/[uid]/page.tsx en alignant leur branche `users` sur le
remap déjà présent dans leur branche `user_profiles` voisine, requête
batch de pro_list.dart avec email scindé sur `users`).

**Hors scope, documenté pour une passe dédiée** : les pages d'annuaire
qui FUSIONNENT deux sources (`users` + `user_profiles`) avec
dédoublonnage par uid — `service_list_page.dart` (requête principale),
`pro_list.dart` (requête A), `website/src/app/services/page.tsx`,
`services/carte/page.tsx` (requête principale), `admin/page.tsx` (2
requêtes). Ce ne sont pas des bascules simples : il faut restructurer
la logique de fusion/dédoublonnage, avec un vrai risque de doublons ou
de trous si mal fait — certaines de ces fusions (`services/page.tsx`
notamment) pourraient même devenir du code mort maintenant que chaque
compte a garanti une ligne `user_profiles` `is_main=true`, mais ça reste
une décision de conception à valider, pas un simple renommage de champ.
Également laissés en l'état : les 2 requêtes de repli de
`profil_association_edit.dart` (email + champs onboarding jamais
recopiés par conception, et une branche à noms de colonnes suspects qui
ne fire que pour une association jamais encore sauvegardée).

### 27.11 — Phase 4 livrée (lot 6) : annonces (création/détail/feed/carte)

8 fichiers (5 app, 3 web) — aucun cas de fusion à dédoublonner dans ce
lot, uniquement des lookups directs par uid connu (seul ou en liste).
`is_premium` traité comme dans `annonces/page.tsx` (lot précédent) :
gardé sourcé sur `users` via une requête séparée plutôt que de faire
confiance à la colonne `user_profiles.is_premium` existante mais non
retenue comme fiable pour ce champ. Au passage, `annonce_detail_page.dart`
(`_normalizeUser`) perd les champs jamais consommés en aval et sans
équivalent `user_profiles` (`is_pro`, `is_dog`, `is_cat`, `dog_breeds`,
`cat_breeds`, `is_partenaire`) — vérifié par recherche qu'aucun code du
fichier ne les lit. Bug corrigé au passage dans 2 fichiers (`create_annonce_page.dart`,
`create_annonce_asso_page.dart`) : le pays de l'annonce était lu sur
`users.pays_elevage` alors que `pays_pro` est la colonne réellement
maintenue à jour côté `user_profiles`.

Incohérence préexistante notée mais non traitée (hors scope migration) :
`website/src/app/annonces/feed/page.tsx` n'a pas l'étape de repli photo/nom
association que son équivalent Flutter (`annonces_feed_page.dart`) a
déjà — les annonces association affichent la photo personnelle de
l'éleveur plutôt que celle de l'association sur le feed web.

### 27.12 — Phase 4 livrée (lot 7) : PetFriends

3 fichiers (2 app, 1 web) — tous des lookups directs par uid connu, un
seul cas structurel : `public_profile_page.dart` interrogeait `users`
en source primaire et `user_profiles` seulement en repli (si `users` ne
renvoyait rien) — inversé, `user_profiles` (`is_main=true`) devient la
seule source, le repli `users` supprimé (devenu inutile). Le filtre
`is_elevage`/`is_pro` de la recherche d'amis (colonnes sans équivalent
direct) remplacé par `.eq('profile_type', 'particulier')`, l'équivalent
le plus direct pour une fonctionnalité particulier↔particulier.

Incohérence préexistante notée, non corrigée : `website/src/app/petfriends/page.tsx`
n'a jamais eu ce filtre côté recherche (contrairement à l'app) — un
compte pro apparaît dans "ajouter un ami" sur le site mais pas dans
l'app. Même famille que l'incohérence notée au lot 6.

### 27.13 — Phase 4 livrée (lot 8) : annuaire associations/élevages + état réel du chantier

3 fichiers migrés (lookups directs par liste d'uid connue, dérivée de
`employes`) : `mes_associations_benevole.dart`, `mes-associations/page.tsx`
(déjà partiellement migré), `mes-employeurs/page.tsx`.
`associations_list_page.dart` + son équivalent web `associations/page.tsx`
se sont révélés être — comme au lot 5 — des pages à fusion
`users`+`user_profiles` avec dédoublonnage par uid, pas une bascule
simple : ajoutés à la catégorie B (restructuration future), pas traités.

**Audit de vérification fait avant ce lot — l'état réel du chantier est
plus large que ce que les lots précédents laissaient penser.** Plusieurs
fichiers de catégories considérées "terminées" ont en fait des lectures
`users` jamais basculées, jamais identifiées dans l'audit initial de ces
lots :
- Messagerie (lot 1) : `chat_profile_page.dart`, `petfriend_chat_page.dart`,
  `petfriends/chat/[convId]/page.tsx`, `website/src/app/messages/page.tsx`.
- Agenda (lot 3) : `lib/pages/agenda/agenda_page.dart` (fichier distinct
  de celui déjà migré).
- Employés (lot 3) : `website/src/app/association/equipe/page.tsx`.

Plus ~13 lookups simples isolés jamais couverts par aucun lot
(`chip_scanner_service.dart`, `lieu_detail_page.dart`,
`portee_form_page.dart`, `pro_clients_page.dart`,
`animal_fiche_pension_page.dart`, `fiches_pension_page.dart`,
`registre_pension_page.dart`, `animal_fiche.dart` — partiellement fait —,
`mes-animaux/[id]/page.tsx`, `ProDashboard.tsx`, `elevages/[id]/page.tsx` —
jamais aligné sur son équivalent pro `services/pro/[uid]/page.tsx` déjà
migré au lot 5, `profil/page.tsx` §agrement/capacite/email), et 4 sites
de recherche live par email sans équivalent `user_profiles`
(`cession_sheet.dart`, `CessionModal.tsx`, `education_devis_page.dart`,
`education/devis/page.tsx`) qui nécessitent une conception dédiée (motif
B des lots précédents).

**Conclusion pour la suite** : le chantier `users`→`user_profiles` en
lecture n'est pas fini, malgré 8 lots livrés (Phases 1-4). Périmètre
restant estimé : ~13 lookups simples (bascule directe, motif connu),
~7 fichiers de "catégories terminées" à vérifier/compléter, 4 sites de
recherche par email (motif B), et 7 pages à fusion users+user_profiles
(catégorie B, restructuration de dédoublonnage). Décision prise en fin
de session : pause sur ce chantier, reprise dans une session dédiée
plutôt que de continuer à la volée sans cadrage frais.

### 27.14 — Phase 4 livrée (lot 9) : catégories partielles complétées + lookups isolés

15 fichiers migrés couvrant les 3 clusters identifiés au lot 8 :
messagerie (`chat_profile_page.dart`, `petfriend_chat_page.dart`,
`petfriends/chat/[convId]/page.tsx`, `messages/page.tsx`), agenda
(`lib/pages/agenda/agenda_page.dart`, 7 sites dans un seul fichier —
distinct de celui migré au lot 3), employés
(`website/src/app/association/equipe/page.tsx`, source primaire + repli
`user_profiles` fusionnés en une seule requête, comme au lot 7 ; le
bulk-load-then-filter de `AddPetsMatchModal` basculé sur le même motif
que `association/benevoles/page.tsx` du lot 4). Plus 9 lookups isolés
jamais couverts (`chip_scanner_service.dart`, `user_detail_page_feed.dart`,
`lieu_detail_page.dart`, `portee_form_page.dart`, `pro_clients_page.dart`,
`registre_pension_page.dart`, `mes-animaux/[id]/page.tsx`,
`ProDashboard.tsx`, `elevages/[id]/page.tsx`).

Cas particulier : `registre_pension_page.dart` — nom/adresse basculent
vers `user_profiles`, `email` reste sourcé sur `users` (aucun équivalent
fiable). `ProDashboard.tsx` : `prenom`/`nom` retirés (colonnes `users`
inexistantes, toujours `undefined` avant ce fix — **ne pas** les
remapper vers `user_profiles.nom`, qui désigne le nom d'élevage et non
un nom de famille). `elevages/[id]/page.tsx` : confirmé en direct que
tous les champs éleveur (`siret`, `is_premium`, `is_validate`,
`especes_elevees`) existent bien sur `user_profiles`.

**Explicitement exclu, laissé en l'état** : `animal_fiche_pension_page.dart`
et `fiches_pension_page.dart` gardent leur repli `users.phone_number`
intentionnel (contournement d'un ancien bug de placeholder, probablement
redondant depuis le trigger de la Phase 1, mais pas retiré par prudence).

**Restant après ce lot** : 4 sites de recherche live par email (motif
nécessitant conception dédiée — `cession_sheet.dart`, `CessionModal.tsx`,
`education_devis_page.dart`, `education/devis/page.tsx`) et 7 pages à
fusion users+user_profiles avec dédoublonnage (catégorie B —
`service_list_page.dart`, `pro_list.dart`, `services/page.tsx`,
`services/carte/page.tsx`, `admin/page.tsx`, `associations_list_page.dart`,
`associations/page.tsx`). Chantier de lecture `users`→`user_profiles`
substantiellement complet pour les lookups simples ; le reste nécessite
une conception dédiée, pas une bascule mécanique.

### 27.15 — Phase 4 livrée (lot 10) : recherche live par email

4 fichiers (cession d'animal app+web, devis éducateur app+web).
`elevage/contrat/page.tsx` (déjà migré) confirme le rétrécissement de
champs nécessaire : `code_iso`/`code_iso_elevage` codés en dur `'+33'`
(pas de colonne dédiée), adresse élevage détaillée
(rue/ville/cp/pays_elevage) collapsée sur la colonne combinée unique
`adresse`, `siret` conservé (colonne réelle).

`cession_sheet.dart`/`CessionModal.tsx` avaient déjà la séparation
email/nom avec correspondance email **exacte** — comportement conservé
(pas de passage à `ilike`). `education_devis_page.dart`/`education/devis/page.tsx`
n'avaient **aucune** séparation (une seule requête `users` avec 3
conditions `ilike` combinées firstname/lastname/email) — introduit la
séparation `isEmail`, branche email en `ilike` (sémantique substring
conservée, différente de la correspondance exacte des 2 autres
fichiers). Au passage, fusionné le lookup séparé du `profile_id` client
(auparavant une 2e requête `user_profiles` après sélection) dans la
même requête de recherche, un aller-retour réseau en moins.

Vérifié en live : recherche par email exact et par email partiel
résolvent toutes deux le bon uid puis les bons champs `user_profiles`
sur un compte réel.

**Chantier de lecture `users`→`user_profiles` complet pour tous les
lookups simples et recherches live.** Seule reste la catégorie B (7
pages à fusion users+user_profiles avec dédoublonnage par uid,
restructuration dédiée non traitée cette session).

### 27.16 — Catégorie B terminée : simplification au lieu de restructuration

Avant de commencer, vérifié en base que le backfill de la Phase 3 est
réellement complet : les 12 comptes `users` ont tous une ligne
`user_profiles.is_main=true` correspondante, avec `profile_type`/`cat_pro`/
`statut_pro` cohérents. Conséquence : la fusion `users`+`user_profiles`
avec dédoublonnage par uid dans les 7 pages catégorie B n'est plus une
restructuration à concevoir — c'est de la logique morte à supprimer.
Confirmé avec l'utilisateur avant de lancer les 7 fichiers.

**5 fichiers — simplification mécanique** (suppression de la requête
`users` + du dédoublonnage, ne garde que `user_profiles`) :
`service_list_page.dart`, `pro_list.dart` (app), `associations_list_page.dart`
(app — un fichier `.bak` non-tracké préexistant dans le même dossier,
antérieur à cette session, laissé intact sans y toucher), `associations/page.tsx`,
`services/page.tsx`, `services/carte/page.tsx` (web).

**`admin/page.tsx` — cas à part**, découvert en cours de route : plus
complexe que les 6 autres car `isSecondary` ne sert pas qu'à l'affichage,
il route aussi les écritures admin (validation/refus/suppression de
compte/toggle premium) vers `users` ou `user_profiles`. Un mauvais aiguillage
ici casse le pipeline d'approbation, pas juste l'affichage — reconfirmé
avec l'utilisateur avant de toucher ce fichier spécifiquement.
Redéfinition : `isSecondary` devient `!user_profiles.is_main` au lieu de
"la ligne vient de quelle table" — cette redéfinition preserve tel quel
tout le sens déjà porté par `isSecondary` dans les 40+ endroits où il est
lu (badges, filtres, texte de confirmation suppression, clés de cache de
validation), donc pas de refonte de ces 40+ sites, seulement des fonctions
de chargement et d'écriture (`loadUsers`, `setStatut`, `mapPrimaryRows`/
`mapSecondaryRows` fusionnés en `mapProfileRows`, `loadDossiers`,
`approveDossier`, `refuseDossier`, `reconsiderDossier`, `runAutoValidate`).
`is_premium` et `email` restent lus/écrits sur `users` (aucun équivalent
fiable sur `user_profiles`, cohérent avec le pattern déjà établi lot 4).
Effet de bord positif : `loadDossiers` n'avait auparavant aucune requête
pour les profils secondaires refusés (`refusedDossiers` ne couvrait que
`users`) — la requête `user_profiles` unifiée couvre maintenant aussi ce
cas, corrigeant un trou préexistant sans complexité ajoutée.

Vérifié : `flutter analyze` (3 fichiers app, 0 nouveau problème),
`tsc --noEmit` + `eslint` (4 fichiers web, même nombre exact de problèmes
avant/après stash), `next build` production complet sans erreur.

**Chantier `users`→`user_profiles` en lecture entièrement terminé,
catégorie B incluse.**

---

## 28. Module Petsitter / Promeneur (`garde`) — Spec initiale (session 2026-07-10)

> Objectif exprimé : donner aux profils Pet sitter / Promeneur un socle de gestion
> opérationnelle aussi complet que la pension (§19), inspiré du produit "Kookie Sitter".
> Pet sitter et promeneur sont traités **ensemble** (l'utilisateur les veut "en parallèle").

### 28.1 — Décision d'architecture

`profile_type = 'garde'` existe déjà (`add_profile_page.dart`) et couvre les deux
sous-professions "Pet sitter" / "Promeneur de chiens" via `sub_profession`. Il
n'y a **pas** de type `'petsitter'` séparé dans le flux d'inscription réel — seul
un littéral legacy `'petsitter'` traîne dans les sets `proTypes` (`main.dart` et
~6 fichiers dupliqués) pour la compat `isPro`. **Décision : construire le module
sur `catPro == 'garde'`**, pas sur un nouveau type `'petsitter'`, pour rester
cohérent avec l'inscription existante. Aucun profil `'petsitter'` réel n'existe
en base à migrer.

Par ailleurs, `'sante'` couvre déjà Ostéopathe/Kinésithérapeute (sous-professions),
et `'marechal_ferrant'` est déjà un type à part entière — ces deux-là ne sont donc
pas des types "manquants", juste des types sans build-out opérationnel façon
pension pour l'instant (repoussé, hors scope immédiat). **`'taxi'`** en revanche
n'existe pas du tout (ni type, ni sous-profession) — à créer si/quand ce chantier
est repris.

### 28.2 — Fonctionnalités demandées (traduites de la description Kookie Sitter)

- **Fiches client/animal centralisées** : infos client + animaux accessibles
  app + web, historique des visites/promenades.
- **Événements planifiés** : accès agenda, démarrer/terminer une prestation,
  vue équipe des événements à venir.
- **Devis/contrats/factures automatiques** avec envoi email automatique
  (Premium/Team uniquement, comme chez Kookie Sitter).
- **Gestion des clés** : liste de clés par client, description + traçabilité.
- **Rapports post-visite** : facultatif, avec photos, envoi auto par email
  (SMS en option — **non disponible**, Twilio jamais implémenté sur ce projet,
  cf. précédent similaire noté §19.4).
- **Communication entre intervenants** (équipe partagée).
- **Suivi GPS + ordre d'itinéraire** : carte des prestations du jour, tournée
  réordonnable.
- **Services récurrents** : modèles de planification flexible (ex. 5j/semaine).
- **Forfaits** : lots de prestations pré-achetées à tarif préférentiel.
- **Tarifs clients personnalisés** : prix différents par client pour un même service.
- **Créneaux horaires de planification** configurables.
- **Gestion du personnel** : plusieurs intervenants, services/localisations/dates
  assignables individuellement.
- **Paiement en ligne des prestations** : **explicitement V2** par l'utilisateur —
  pour tous les prestataires qui le souhaitent (pas juste petsitter), sinon saisie
  manuelle pour la comptabilité (éducateur, petsitter, pension inclus). Cohérent
  avec le "paiement en ligne (lien email/SMS)" déjà noté V2 pour la pension (§19.2).

### 28.3 — Réutilisation attendue (déjà générique, pas de nouveau code)

Inventaire, Employés, Protocoles/Tâches, Agenda/RDV, Documents/contrats
signature électronique sont déjà génériques par `pro_profile_id` — même
traitement que la pension (§19.1, "parité de gestion"). Reste réellement
spécifique à construire : logements→tournées/itinéraire, gestion des clés,
forfaits, tarifs personnalisés, services récurrents, config plan/abonnement
`garde` (n'existe pas encore dans `plan_service.dart`/`use-plan.ts`, seuls
`pension` et `education` ont un config aujourd'hui).

### 28.4 — Phase 1 livrée (session 2026-07-10) : socle

**Découverte en cours de route** : `app_nav_drawer.dart` (drawer secondaire
utilisé sur les pages d'annuaire type `service_list_page.dart`) n'est **pas**
la navigation réelle d'un compte pro — tout compte `isPro` (garde inclus)
route vers `eleveur_nav.dart` via `bottom_nav.dart::_asElevage`. Le lien
`garde → RegistrePensionPage` s'y trouvait déjà, sémantiquement faux (registre
de check-in/check-out en logements, pas le modèle événementiel du petsitter)
— corrigé au passage (`pension` seul sur ce lien désormais).

- **Abonnement `garde`** : `GardePlanConfig` + `getGardeConfig`/
  `getGardePlansLive`/`getGardePlanCode` dans `plan_service.dart` (miroir
  exact de `EducationPlanConfig`, sans les champs logements propres à la
  pension). 3 paliers mêmes prix que pension/éducateur. App :
  `garde_abonnement_page.dart`. Web : `GardePlanConfig`/`usePlanGarde` dans
  `use-plan.ts`, `useGardeAccess.ts` (miroir `usePensionAccess`),
  `/garde/abonnement` (miroir exact de `/pension/abonnement`, checkout
  Stripe déjà générique par `profil_type` — aucune adaptation backend
  nécessaire, confirmé en lisant `api/stripe/checkout/route.ts`).
- **Navigation** (`eleveur_nav.dart`) : bloc `catPro == 'garde'` ajouté
  (Registre visites, Inventaire, Protocoles/Tâches, Mes Employés, Mon
  abonnement — gating `_gardePlanCode` comme pension). Web : `MENU_GARDE`
  dans `Header.tsx` (miroir `MENU_EDUCATION`), `effectiveIsGarde` ajouté à
  la résolution de menu.
- **Registre visites** (nouveau, remplace le lien pension erroné) : le
  modèle petsitter est événementiel (chaque visite = une ligne `rdv`
  existante, pas de nouvelle table). App : `registre_visites_page.dart` —
  liste À venir/Passées scopée par `pro_profile_id`, bouton "Marquer
  terminée" (`rdv.statut = 'termine'`, comportement déjà neutre côté
  `pro_agenda.dart::_updateStatut`, aucune notification collatérale à
  reproduire). Web : `/garde/registre` (même logique).
- **Rapport de visite** : réutilise la table `pension_updates` telle
  quelle (`animal_id`, `pro_uid`, `photo_url`, `note` — `pension_entree_id`
  confirmé nullable par test d'insertion live) plutôt que d'en créer une
  nouvelle identique. Bouton sur un événement dans Registre visites → photo
  optionnelle + note → notification in-app (`type: 'visite_rapport'`),
  même schéma que `education_rapport` (§20.1). **Effet de bord gratuit côté
  web** : le composant `PensionJournal.tsx` était déjà entièrement
  générique (prend `proUid` en prop, bascule lecture/écriture) — réutilisé
  tel quel dans `/garde/registre`, aucun nouveau composant de saisie créé.
  **Limite connue** : le bouton propriétaire "Nouvelles de la pension" sur
  `mes-animaux/[id]/page.tsx` affichera aussi les rapports de visite garde
  (même table, pas de colonne discriminante) — label pas encore adapté,
  cosmétique uniquement, pas de fuite de données (l'affichage reste
  scopé par `animal_id`, donc uniquement visible par le bon propriétaire).
- **Dashboard** : `eleveur_home.dart` — bloc `catPro == 'garde'` (RDV
  aujourd'hui, Visites ce mois, Statut, tous cliquables — miroir pension).
  Web `ProDashboard.tsx` : déjà suffisamment générique (patients/RDV/
  `TYPE_LABEL['garde']` déjà présents avant cette session), aucun changement
  nécessaire.

Vérifié : `flutter analyze` sur les fichiers app touchés/créés (0 nouveau
problème, comparaison avant/après via `git stash`), `tsc --noEmit` +
`eslint` sur les fichiers web (même compte d'erreurs `tsc` avant/après ;
`eslint` +1 attendu — `usePlanGarde` hérite du même avertissement
`react-hooks/set-state-in-effect` déjà toléré sur `usePensionPlan`, pas une
régression nouvelle), `next build` production complet réussi (routes
`/garde/abonnement` et `/garde/registre` confirmées dans la sortie de build).

**Reste pour les phases suivantes** (non commencé) : devis/contrats/factures
automatiques avec envoi email, gestion des clés, suivi GPS + tournée
réordonnable, services récurrents, forfaits, tarifs clients personnalisés,
créneaux horaires configurables dédiés, paiement en ligne des prestations
(V2 explicite). Onboarding dédié (`onboarding_garde.dart` façon
`onboarding_pension.dart`) également non traité — profils `garde` créés via
le flux d'inscription générique existant (`add_profile_page.dart`).

### 28.5 — ACACED manquant à l'inscription et à la validation, corrigé

Signalé par l'utilisateur après coup : le formulaire d'inscription
(`add_profile_page.dart`) n'avait **aucun champ ACACED pour `garde`** (seul
`education` l'avait, obligatoire) — le numéro n'était même pas envoyé en
base pour un profil garde. Pire, **aucune page n'avait d'upload du
justificatif ACACED pour un type pro** (`pro_profile_edit.dart`/web
`SecondaryProEdit`) — seul l'éleveur avait cette UI. `education` avait donc
déjà ce trou en prod avant cette session (champ obligatoire à l'inscription,
mais nulle part où uploader le document ensuite). Obligation légale (Code
rural, art. L214-6-1), pas une simple recommandation — corrigé pour les
deux types d'un coup plutôt que de dupliquer le trou pour garde :

- **Inscription** (`add_profile_page.dart`) : champ ACACED désormais
  obligatoire pour `garde` en plus de `education` (même traitement,
  `data['acaced_numero']` envoyé pour les deux).
- **Édition + upload du justificatif** — nouveau, n'existait pour aucun
  type pro avant cette session : section ACACED (numéro + upload
  image/PDF) ajoutée dans `pro_profile_edit.dart` (app) gated
  `catPro == 'garde' || catPro == 'education'`, écrite dans les 3 blocs
  d'écriture existants (secondaire→`user_profiles`, principal→`users`,
  principal→`user_profiles` sync). Web : même section dans
  `SecondaryProEdit` (`profil/page.tsx`) — **scope limité aux profils
  secondaires** (paramétré par `profileId`), le cas profil pro *primaire*
  côté web n'a pas été audité/couvert par ce correctif, à vérifier si des
  comptes garde/éducateur primaires existent.
  Écrit sur les deux colonnes `acaced`/`acaced_numero` (doublon déjà
  présent en base, `admin/page.tsx` lit `acaced`, l'inscription écrit
  `acaced_numero` — pas unifié, juste rendu cohérent sur les deux).
- Pas de reprise de la piste avancée de l'éleveur (dates d'obtention/
  renouvellement, statut d'expiration coloré) — numéro + justificatif
  suffisent pour que l'admin puisse valider, le suivi d'expiration reste
  pour une itération ultérieure si demandé.

Vérifié : `flutter analyze` (0 nouveau problème sur les 2 fichiers app),
`tsc --noEmit` + `eslint` sur `profil/page.tsx` (0 problème avant/après),
`next build` production complet réussi.

### 28.6 — Phase 2a livrée (session 2026-07-10) : devis/contrats/factures auto + forfaits

Découpage validé avec l'utilisateur pour continuer le module garde : devis/
contrats/factures automatiques (email inclus) + forfaits, le reste (clés,
GPS/tournée, récurrence, tarifs personnalisés, créneaux configurables) en
phases ultérieures. Exploration préalable confirmée : `devis`/`factures`
déjà pleinement génériques (aucun changement de schéma), seuls les contrats
et forfaits nécessitaient une nouvelle table (mirror du pattern déjà établi
`pension_updates` réutilisé tel quel vs `pension_factures`/`pension_entrees`
mirror selon que le nom de table est déjà neutre ou couplé au domaine).

- **Facturation** : lien de navigation manquant ajouté au bloc garde
  (`eleveur_nav.dart`) — le backend (`factures`/`FacturationPage`,
  `/elevage/facturation`) était déjà pleinement fonctionnel pour garde
  depuis le fix cross-profil de `facturation.dart` plus tôt cette session,
  seul l'accès manquait. Découverte au passage : même la pension n'a pas
  ce lien dans `eleveur_nav.dart` (a sa propre page dédiée
  `pension_factures_page.dart`) — trou pré-existant non spécifique à garde,
  non corrigé (hors scope).
- **Devis** : table `devis` déjà générique (scopée uid/profile_id, aucune
  colonne éducateur-spécifique) — `EducationDevisPage` renommée `DevisPage`
  et généralisée en place (table `forfaits`/`forfaits_garde` sélectionnée
  selon `catPro`, chips de tarifs rapides limités à `education`) plutôt que
  dupliquée. Web : `/garde/devis` ré-exporte `/education/devis/page.tsx`
  (même pattern que `associations/inventaire` → `elevage/inventaire`
  établi en catégorie B).
- **Contrats** : nouvelle table requise (`documents_animaux.rdv_id`, migration
  `migration_garde_contrat.sql` — **à exécuter manuellement dans le SQL
  Editor Supabase**, non appliquée automatiquement) — la pension elle-même
  n'utilise pas `ContractService.ts` pour ses contrats (insertion directe
  dans `documents_animaux`, découvert en lisant `/pension/contrat/page.tsx`),
  même approche reprise pour garde. Nouveau `contrat-garde.ts` (template
  HTML, mirror `contrat-pension.ts`), nouveau type `contrat_garde` câblé
  dans `/signer-contrat/[token]/page.tsx` (dispatch générique déjà en
  place). App : bouton contrat sur `registre_visites_page.dart` (insert +
  lien copié, même pattern que `registre_pension_page.dart`). Web :
  `/garde/contrat`.
- **Envoi email automatique** : n'existait pour aucun type de profil avant
  cette session (juste notification in-app). 3 nouvelles routes génériques
  (`api/devis/notify-email`, `api/contrat/notify-email`,
  `api/facture/notify-email`, mirror `api/cession/notify-email`).
  **Sécurité** : en copiant le pattern nodemailer existant, un identifiant
  Gmail codé en dur allait être dupliqué dans 3 nouveaux fichiers (déjà
  présent en dur dans 2 fichiers pré-existants, `cession`/`animal-claim` —
  non touchés, hors scope) — bloqué par le classificateur de sécurité,
  corrigé en extrayant `website/src/lib/mailer.ts` (transport partagé lisant
  `GMAIL_USER`/`GMAIL_APP_PASSWORD` depuis `.env.local`, jamais commité) au
  lieu de propager le secret en clair. Bouton "Envoyer par email" gated
  `GardePlanConfig.code != 'free'` **entièrement câblé uniquement sur
  `/garde/contrat`** (exemple de bout en bout fonctionnel) — les boutons
  équivalents sur devis (page partagée education/garde) et facture (page
  générique partagée par tous les types pro) **ne sont pas câblés dans
  l'UI** cette session, pour éviter d'élargir le risque sur des pages
  partagées par d'autres types de profils sans cadrage dédié. Les 3 routes
  API sont prêtes et testables indépendamment.
- **Forfaits** : nouvelle table `forfaits_garde` (migration
  `migration_garde_forfaits.sql` — **à exécuter manuellement**, `nb_visites`
  au lieu de `nb_seances`, RLS identique à `forfaits_education`).
  `ForfaitModal` (web) et le bottom sheet équivalent (app,
  `pro_profile_edit.dart`) généralisés en place avec sélection de
  table/colonne selon `catPro` et wording adaptatif ("visites" vs
  "séances"), plutôt que dupliqués.

**Migrations à exécuter manuellement avant mise en service** (non
appliquées par ce travail — écrites comme scripts idempotents pour le SQL
Editor Supabase, comme toutes les migrations de ce projet) :
`migration_garde_contrat.sql`, `migration_garde_forfaits.sql`.

Vérifié : `flutter analyze` sur les 5 fichiers app touchés (0 nouveau
problème, comparaison avant/après), `tsc --noEmit` (0 nouvelle erreur,
même compte qu'avant), `eslint` (0 nouveau problème sur les nouveaux
fichiers ; 1 avertissement `react-hooks/set-state-in-effect` hérité sur
`/garde/contrat`, même pattern pré-existant déjà toléré partout ailleurs
dans ce projet), `next build` production complet réussi (routes
`/garde/devis`, `/garde/contrat` confirmées dans la sortie de build).

### 28.7 — Phase 2b livrée (session 2026-07-10) : gestion des clés

Première brique de la Phase 2b (reste : GPS/tournée, services récurrents,
tarifs personnalisés par client, créneaux configurables, onboarding dédié —
non commencés).

- **Nouvelle table `cles_clients`** (migration `migration_garde_cles.sql` —
  **à exécuter manuellement**) : `animal_id`, `owner_uid`/`owner_profile_id`,
  `description`, `statut` (`en_possession`/`rendue`), `date_recuperation`,
  `date_restitution`, `notes`. Scopée `pro_uid`+`pro_profile_id`, RLS INSERT
  exige les deux (convention établie tout ce chantier).
- **Pas de nouvelle notion de "client"** : la liste des clients éligibles à
  une clé est dérivée des RDV confirmés/terminés existants (même requête
  que `registre_visites_page.dart`), pas de table clients dédiée à créer.
- App : nouvelle page `cles_clients_page.dart` (liste "En ma possession" /
  "Rendues", ajout via bottom sheet avec sélecteur client/animal, édition,
  bascule de statut en un tap, suppression). Lien ajouté au bloc garde de
  `eleveur_nav.dart`, juste après "Devis".
- Web : nouvelle route `/garde/cles` (même logique, modale au lieu de
  bottom sheet). Lien ajouté à `MENU_GARDE` dans `Header.tsx`.
- Pas de gating Premium/Team sur cette fonctionnalité (contrairement à
  Inventaire/Protocoles/Employés) — jugée basique/attendue dès le palier
  gratuit, même traitement que Registre visites/Devis.

Vérifié : `flutter analyze` sur le nouveau fichier + `eleveur_nav.dart`
(0 nouveau problème), `tsc --noEmit` + `eslint` sur `garde/cles/page.tsx`
et `Header.tsx` (0 nouvelle erreur — le seul avertissement
`react-hooks/set-state-in-effect` reproduit le pattern déjà toléré sur
`/garde/registre`), `next build` production complet réussi (`/garde/cles`
confirmée dans la sortie de build).

### 28.8 — Phase 2b livrée (session 2026-07-10) : tarifs clients personnalisés

**Découverte préalable** : garde n'avait **aucun catalogue de tarifs de
base** (contrairement à `education`/`tarifs_education` et
`pension`/`tarifs_logements`) — juste le champ libre générique `tarifs`.
Sans catalogue de base, "personnalisé" n'a pas de sens (rien à surcharger) :
prérequis ajouté avant la fonctionnalité demandée.

- **Catalogue de base `tarifs_garde`** (nouvelle colonne JSONB sur
  `user_profiles`, migration `migration_garde_tarifs_clients.sql` — **à
  exécuter manuellement**) : mirror exact de `tarifs_education`
  (`_prestationsGarde`/`PRESTATIONS_GARDE` : promenade 30min/1h/2h, garde
  journée, autre). UI app (`pro_profile_edit.dart`) + web
  (`profil/page.tsx`) mirroir la section éducateur existante.
- **Nouvelle table `tarifs_clients_garde`** : surcharge par client d'un
  type de prestation (`pro_profile_id`, `owner_profile_id`,
  `prestation_type`, `prix`), contrainte unique sur les trois. Écriture en
  "upsert si différent du tarif standard / delete si redevenu identique"
  plutôt que de stocker des doublons inutiles.
- **Clients éligibles dérivés des RDV** (même pattern que Gestion des
  clés, §28.7) — mais ici via `rdv.client_profile_id` (fiabilisé par le
  correctif RDV du 07-08) plutôt que `animaux_proprietes`, car la
  tarification est par client/payeur, pas par animal.
- App : nouvelle page `tarifs_clients_page.dart` (liste clients avec badge
  "N tarifs personnalisés" ou "Tarifs standards", tap → bottom sheet avec
  un champ par prestation, prérempli au tarif standard). Web :
  `/garde/tarifs-clients` (même logique, modale).
- **Bug pré-existant corrigé au passage** : `DevisPage`/`/education/devis`
  (généralisée pour garde en Phase 2a, §28.6) lisait en dur la colonne
  `tarifs_education` quel que soit `catPro` — les chips de saisie rapide
  n'avaient donc jamais fonctionné pour garde (aucune ligne à afficher,
  échec silencieux). Corrigé : lecture de la colonne appropriée
  (`tarifs_garde` vs `tarifs_education`) + ajout des chips garde
  (promenade 30min/1h/2h, garde journée) qui n'existaient pas du tout
  avant (les chips étaient conditionnées `catPro === 'education'` en dur).
  Une fois un client sélectionné dans le devis, ses tarifs personnalisés
  (si définis) remplacent le tarif standard dans les chips — app et web.

Vérifié : `flutter analyze` sur les 4 fichiers app touchés (0 nouveau
problème), `tsc --noEmit` (0 nouvelle erreur), `eslint` (0 nouveau
problème sur les nouveaux fichiers ; le nouvel effet de chargement des
tarifs client sur `/education/devis` reproduit le même avertissement
`react-hooks/set-state-in-effect` que tous les autres effets de
chargement de ce projet — tenté un correctif via `useCallback`, le linter
continue de tracer à travers, confirmant qu'il s'agit d'une limite
générale de la règle sur ce projet et non d'un problème introduit),
`next build` production complet réussi (`/garde/tarifs-clients`
confirmée dans la sortie de build).

### 28.9 — Phase 2b livrée (session 2026-07-10) : onboarding dédié

App uniquement — pas d'équivalent web pour l'onboarding pension non plus,
confirmé par recherche, donc aucune contrepartie web à créer ici.

- **Nouveau `onboarding_garde.dart`** : mirror exact de
  `onboarding_pension.dart` (4 slides carrousel, flag
  `SharedPreferences` `onboarding_garde_done`), contenu adapté au
  vocabulaire petsitter/promeneur (registre visites/rapports, devis/
  contrats/tarifs personnalisés, visibilité annuaire).
- **`bottom_nav.dart::_checkOnboarding`** — bug découvert en câblant le
  déclenchement : `eleveurProfiles` (et son fallback `User_Info.isPro &&
  !hasPension`) capturait déjà silencieusement tous les profils `garde`
  avant ce correctif — un nouveau profil garde déclenchait donc
  l'onboarding **éleveur** (contenu totalement hors sujet : portées,
  annonces d'élevage...), jamais un onboarding dédié. Corrigé :
  `gardeProfiles` extrait et exclu de `eleveurProfiles` et du fallback
  pro générique, nouveau flag `needsGarde` suivant exactement le même
  pattern que `needsPension` (marquage silencieux "déjà fait" si le
  profil existait avant ce correctif, pour ne pas montrer l'onboarding
  rétroactivement aux comptes garde déjà actifs).
- **Non traité, limitation pré-existante identique pour pension** : la
  feuille de choix `_showOnboardingChoice` (cas association + autre profil
  simultané) ne propose que "Association"/"Éleveur", jamais "Pension" ni
  désormais "Garde" — un profil garde+association nouvellement créé verra
  l'onboarding association proposé mais pas l'onboarding garde via cette
  feuille (reste possible séparément si `needsGarde` seul plus tard).
  Écart déjà présent pour pension avant cette session, pas aggravé,
  hors scope d'un correctif ciblé "onboarding garde".

Vérifié : `flutter analyze` sur les 2 fichiers touchés (0 nouveau
problème, comparaison `git stash` avant/après).

### 28.10 — Phase 2b/2c livrée (session 2026-07-10) : RDV clients récurrents

**Cadrage revu en cours de route** : la demande initiale "services
récurrents + créneaux configurables" s'est révélée déjà largement
couverte — `creneaux_pro` (grille hebdo + "Répliquer" sur N semaines/fin
d'année/date perso) existe déjà en app (`pro_agenda.dart`) **et** web
(`/pro/creneaux`), générique à tous les types de pro dont garde, déjà
relié dans `MENU_GARDE`. Fausse piste initiale de ma part (recherche par
nom de fichier `*creneau*`, qui ne matche pas `pro_agenda.dart` où c'est
implémenté) — corrigée après remarque de l'utilisatrice. Le vrai trou
identifié après clarification : la **récurrence côté RDV client** (ex.
« promenade tous les mardis avec Mme Dupont ») n'existait nulle part —
seule la disponibilité du pro pouvait être répliquée, pas une réservation
répétée automatiquement pour un client donné.

- **App** (`rdv_booking_page.dart`, flux client→pro déclenché depuis
  `service_detail_page.dart`) : nouveau champ `isGarde`, toggle « Répéter
  ce RDV chaque semaine » (4/8/12 semaines) visible une fois un créneau
  choisi. À la soumission, calcule les dates hebdomadaires suivantes et
  ne retient que celles réellement disponibles
  (`_isDateSlotAvailable` : tous les créneaux 15 min de `creneaux_pro`
  couvrant la durée + absence de chevauchement avec un RDV existant),
  insère une ligne `rdv` par occurrence valide, une seule notification
  agrégée au pro, retour utilisateur explicite si certaines dates n'ont
  pas pu être honorées (ex. "6/8 RDV créés").
- **Web** (`services/pro/[uid]/page.tsx`) — porté à la demande de
  l'utilisatrice après cadrage initial "app d'abord". **Découverte en
  l'explorant** : ce flux web utilise un schéma `rdv` différent de l'app
  (`date_debut`/`date_fin` au lieu de `date_heure`/`duree_minutes`, pas
  de vérification de conflit avec les RDV existants — juste
  `creneaux_pro.statut` immédiatement basculé sur `'reserve'` à la
  réservation) — écart pré-existant entre les deux plateformes, non
  corrigé (hors scope d'un ajout de récurrence, risque de casser un flux
  déjà en prod). La récurrence web reprend donc fidèlement ce même
  schéma plutôt que d'introduire celui de l'app, pour rester cohérente
  avec le comportement déjà en place. Disponibilité vérifiée par
  appartenance à la liste `slots` déjà chargée (requête sans limite de
  date supérieure côté web, contrairement à l'app plafonnée à 3 mois).
- Pas de nouvelle table ni migration — entièrement bâti sur `rdv` et
  `creneaux_pro` existants.

Vérifié : `flutter analyze` sur les 2 fichiers app touchés (0 nouveau
problème), `tsc --noEmit` (0 nouvelle erreur), `eslint` (0 nouveau
problème — même compte d'erreurs pré-existantes qu'avant sur
`services/pro/[uid]/page.tsx`, confirmé par `git stash`), `next build`
production complet réussi.

### 28.11 — Phase 2c livrée (session 2026-07-10) : GPS + tournée réordonnable

Dernière brique du module garde. **App uniquement** (confirmé avec
l'utilisatrice) — le suivi GPS en direct n'a pas de sens sur une version
web, un pet sitter ne prépare pas sa tournée depuis un ordinateur en
faisant ses visites.

**Découverte préalable (exploration dédiée)** : l'infrastructure géo
existait déjà à 90 % mais pour l'éducateur, pas pour garde —
`rdv.lieu`/`lieu_lat`/`lieu_lng` (migration `migration_education_intervenants_trajet.sql`,
géocodage natif au moment où le pro modifie un RDV), `GeocodingHelper`
(`lib/utils/geocoding_helper.dart`, géocodage + distance à vol d'oiseau),
et une heuristique "risque de retard" déjà dans `pro_agenda.dart`
(`_travelWarningsToday`) comparant le temps entre deux RDV consécutifs à
la distance à parcourir. **Aucune colonne d'ordre de passage n'existait
en revanche** — les visites n'étaient triables que par heure de RDV.

- **Nouvelle colonne `rdv.ordre_visite`** (migration
  `migration_rdv_ordre_visite.sql` — **à exécuter manuellement**) :
  ordre de passage indicatif, distinct de l'heure réservée (permet au
  pro d'optimiser son trajet sans changer les horaires convenus avec les
  clients).
- **Nouvelle page `tournee_page.dart`** ("Ma tournée", lien ajouté au
  bloc garde de `eleveur_nav.dart`) : carte (mirror du pattern
  `balades_ludiques_map_view.dart`, `google_maps_flutter`) des visites
  confirmées du jour avec marqueurs numérotés (vert=départ, rouge=fin,
  bleu=étapes) + tracé (`Polyline`) reliant les points dans l'ordre +
  marqueur violet "Ma position" (géolocalisation `geolocator`, best-effort,
  ne bloque pas le chargement si permission refusée). Distance totale à
  vol d'oiseau affichée (réutilise `GeocodingHelper.distanceKm`).
  Liste `ReorderableListView` en dessous (glisser-déposer), persiste
  `ordre_visite` par RDV à chaque réordonnancement. Tri par défaut :
  `ordre_visite` si déjà défini, sinon heure du RDV.
- **Trou pratique comblé au passage** : sans adresse géocodée, une
  visite n'a pas de position sur la carte — or `lieu`/`lieu_lat`/`lieu_lng`
  ne se remplissaient jusqu'ici qu'en passant par le flux complet
  "modifier le RDV". Ajouté un raccourci "+ Ajouter une adresse" par
  visite directement dans la liste de la tournée (dialogue simple →
  géocodage via `GeocodingHelper` → update direct de la ligne `rdv`),
  sans quoi la fonctionnalité serait restée vide pour la quasi-totalité
  des RDV existants.
- Pas d'optimisation automatique d'itinéraire (tri "plus court chemin") —
  demande explicite : "réordonnable", pas "optimisable". Laissé au pro.

Vérifié : `flutter analyze` sur les 2 fichiers touchés (0 nouveau
problème — seul avertissement : `onReorder` déprécié sur
`ReorderableListView`, même pattern déjà toléré ailleurs dans le projet
sur `step_points_carte.dart`).

---

## 29. Module "Balades ludiques" (collègue) — correctif fuite cross-profil (session 2026-07-10)

**Contexte** : module de geocaching/chasse au trésor développé par une
collègue sans accès Supabase (branche mergée via `git pull --no-rebase`,
commit `97b267f9`), distinct des "promenades" collectives. À la relecture de
`supabase/migration_balades_ludiques.sql`, l'utilisatrice a repéré l'absence
totale de `profile_id` sur les 9 nouvelles tables — uniquement scopées par
`*_uid` (Firebase uid) — soit exactement la classe de bug cross-profil déjà
corrigée ailleurs dans le projet cette session (le uid seul ne distingue pas
un profil élevage d'un profil association/pension d'un même compte). Demande
explicite : **tout doit fonctionner via `profile_id`, pas seulement le
créateur** — cohérent avec la convention établie partout ailleurs dans
l'app (`User_Info.activeProfileId` côté app, `activeProfileId` de
`useAuth()` côté web).

**Migration n'ayant jamais été exécutée en production** (colonne
`profile_id` absente du schéma réel) : schéma redessiné directement dans le
fichier plutôt que par `ALTER TABLE` a posteriori — sûr, aucune donnée
existante à migrer.

**Tables corrigées** (`supabase/migration_balades_ludiques.sql`) :
- `balades_ludiques` : + `createur_profile_id` (nullable, `ON DELETE SET
  NULL`, la ligne reste identifiable par uid même si le profil est
  supprimé) + index.
- `balades_ludiques_progressions` : `joueur_uid` → + `joueur_profile_id`
  (NOT NULL), contrainte unique migrée de `(balade_id, joueur_uid)` vers
  `(balade_id, joueur_profile_id)`, policy INSERT exige les deux.
- `balades_ludiques_validations` : + `joueur_profile_id` (nullable).
- `balades_ludiques_avis` : `user_uid` → + `profile_id` (NOT NULL),
  contrainte unique migrée vers `(balade_id, profile_id)`.
- `balades_ludiques_favoris` : `user_uid` → + `profile_id` (NOT NULL), clé
  primaire migrée de `(user_uid, balade_id)` vers `(profile_id, balade_id)`.
- `badges_obtenus` : + `profile_id` (NOT NULL), contrainte unique migrée
  vers `(profile_id, badge_id, balade_id)`.
- `joueurs_xp` : clé primaire migrée de `user_uid` vers `profile_id`
  (`user_uid` conservé en colonne simple + index, pour affichage/debug).

Toutes les policies RLS INSERT concernées mises à jour pour exiger
`*_profile_id IS NOT NULL` en plus du uid existant.

**Fichiers applicatifs corrigés** (tous les points de lecture/écriture
touchant ces tables, identifiés par grep exhaustif sur
`createur_uid|joueur_uid|user_uid` dans les deux arborescences) :

*Web* (5 fichiers) : `balades-ludiques/creer/page.tsx`,
`balades-ludiques/mes-parcours/page.tsx`, `balades-ludiques/[id]/page.tsx`,
`balades-ludiques/[id]/jouer/page.tsx`, `balades-ludiques/classement/page.tsx`
— ce dernier entièrement réécrit : l'ancien code affichait `Créateur
{uid.slice(0,6)}` (fragment de uid brut) faute de pouvoir résoudre un nom ;
désormais résolution des noms d'affichage via une requête batch
`user_profiles` (nom > profile_label > firstname+lastname > "Utilisateur").

*App* (6 fichiers) : `creation/creation_flow_page.dart`,
`mes_parcours_page.dart`, `mes_badges_page.dart`, `classement_page.dart`
(même réécriture de résolution de nom que le web), `balade_ludique_jouer_page.dart`,
`balade_ludique_detail_page.dart`. Pattern uniforme : ajout de
`User_Info.activeProfileId` (app) / `activeProfileId` de `useAuth()` (web)
sur chaque lecture/écriture de progression, favoris, avis, XP et badges ;
`_isOwner`/`isOwner` comparent désormais `createur_profile_id`, plus
`createur_uid`.

Fichiers du module sans dépendance `profile_id` (widgets défis, hub, filtres,
carte, étapes de création, stats de parcours) : audités, aucun changement
nécessaire — ils ne lisent/écrivent que des données non scopées par
utilisateur (points, défis, filtres publics).

**Package manquant** : `qrcode.react` déclaré par la collègue dans
`package.json` mais absent de `node_modules` (écart d'environnement
pré-existant, sans lien avec le correctif) — corrigé par `npm install`.

**Migration à exécuter manuellement** avant mise en service (n'a jamais
été appliquée en production, donc aucune donnée à migrer, mais toujours
un script à exécuter à la main dans le SQL Editor Supabase comme toutes
les migrations de ce projet) : `migration_balades_ludiques.sql` (version
corrigée).

Vérifié : `flutter analyze` sur tout `lib/pages/balades_ludiques` (0 nouveau
problème — seulement du bruit `withOpacity`/`onReorder` déjà présent avant
correctif, confirmé par comparaison `git stash`), `tsc --noEmit` et `eslint`
sur `website/src/app/balades-ludiques` (mêmes erreurs pré-existantes
qu'avant correctif, confirmé par `git stash` ; le correctif de
`classement/page.tsx` a même supprimé une erreur TS pré-existante au
passage).

---

## 30. Notifications cross-profil — likes + rappels serveur (session 2026-07-10)

**Contexte** : la collègue signale voir des notifications élevage (like,
tâche validée, annonce expirant) sur son profil association. Investigation :
3 causes distinctes, toutes de la même famille que le chantier `profile_id`
de cette session.

- **Like sur annonce** (`annonce_detail_page.dart`, `annonces_feed_page.dart`,
  `website/src/app/annonces/feed/page.tsx`, `website/src/app/annonces/page.tsx`) :
  la notification envoyée au propriétaire de l'annonce ne renseignait que
  `sender_profile_id` (profil de la personne qui like), jamais `profile_id`
  (profil cible = destinataire) — elle tombait donc systématiquement dans le
  fallback "aucun profil connu → afficher sur tous les profils" de
  `notifications_page.dart`. Corrigé en propageant le `profile_id` de
  l'annonce (colonne déjà présente sur `annonces`) jusqu'à l'insert de la
  notification, sur les 4 fichiers (à noter : sur `annonces/page.tsx`, la
  prop a dû être filée à travers 3 composants imbriqués
  `AnnonceCard` → `BabyPhotoCard` → `toggleLike`).
- **Tâche validée** : déjà correctement scopée par `profile_id` depuis le
  correctif du 2026-07-08 (commit `54c1323d`) — la notification vue par la
  collègue datait d'avant ce correctif (donnée historique, pas un bug actif).
- **Annonce expirant** — cause racine différente et plus grave : la Cloud
  Function planifiée `functions/annonces.js`
  (`sendAnnonceExpirationReminders`, tourne tous les jours à 7h) n'a jamais
  renseigné `profile_id` du tout sur ses insertions dans `notifications`.
  Contrairement aux bugs "app", celui-ci n'a **aucun lien avec la version de
  l'app installée** : il fuit en continu côté serveur, indépendamment de ce
  que la collègue a sur son téléphone.

**Audit étendu** : le même trou (zéro `profile_id`) a été trouvé dans 7
autres Cloud Functions programmées qui insèrent dans `notifications` :
`chaleurs.js`, `retraite.js`, `sante.js`, `agenda.js` (rappels mise-bas),
`vet_notifications.js`, `rdv_reminders.js`. Toutes corrigées (confirmation
utilisatrice de traiter les 7 en plus des 3 signalées à l'origine).

**Découverte clé** : `animaux.profile_id` n'est **pas fiable** (déjà
documenté dans `migration_fix_animaux_proprietes_unique_constraint.sql` —
jamais renseigné par certains flux comme `portee_form_page.dart`). La
source fiable du profil propriétaire courant est
`animaux_proprietes.profile_id_proprio` avec `date_fin IS NULL` (= ligne de
propriété active), même pattern que celui déjà utilisé côté app dans
`mes_animaux.dart`. Chaque Cloud Function concernée résout donc désormais
le `profile_id` via une requête (batchée quand plusieurs animaux, sinon
par ligne) sur `animaux_proprietes` plutôt que de lire une colonne
`profile_id` directement sur `animaux`. Seul `rdv_reminders.js` fait
exception : `rdv.client_profile_id` existe et est fiable (renseigné par le
correctif RDV du 07-08), donc lu directement.

**`alertes.js` volontairement non touché** : ses notifications
(`notifyUsersNearLostAnimal`, `notifyNearFoundAnimal`, `notifyAnimalOwner`)
sont des alertes de sécurité communautaire (animal perdu/trouvé à
proximité), pertinentes pour la personne quel que soit son profil actif —
contrairement aux notifications "business" d'un profil pro (élevage,
association…), les scoper par profil irait à l'encontre du besoin.

Vérifié : `flutter analyze` (0 nouveau problème sur les 2 fichiers app),
`tsc --noEmit` + `eslint` sur les 4 fichiers web (0 nouvelle erreur,
comparaison `git stash` : même compte avant/après), `eslint --fix` sur les
7 fichiers Cloud Functions (quelques erreurs `block-spacing`/`max-len`
introduites par le nouveau code, corrigées), chargement Node de chacun des
7 fichiers confirmé sans erreur de syntaxe.

**À faire après déploiement** : `firebase deploy --only functions` est
nécessaire pour que le correctif des 7 fonctions programmées prenne effet
— contrairement au reste de cette session, un rebuild/réinstall de l'app
seul ne suffit pas ici.

---

## 31. Protocoles association — désynchronisation agenda + catalogue non adapté (session 2026-07-11)

**Contexte** : signalé par l'utilisatrice après avoir généré un protocole
depuis un profil association — les tâches créées (`plan_taches`)
n'apparaissaient jamais dans "Mon Agenda", contrairement au comportement
attendu côté éleveur. Elle a aussi noté que le catalogue de protocoles
propose des concepts d'élevage contrôlé (mise bas, gestation) hors sujet
pour une association/refuge.

**Cause racine (désynchronisation agenda/protocoles)** : `plans_actifs` et
`plan_taches` (générés par `elevage/planning/page.tsx` côté web et
`planning_service.dart` côté app) n'écrivaient jamais la colonne
`profile_id` — uniquement `eleveur_profile_id`. Or la lecture "Mon Agenda"
(`elevage/agenda/page.tsx::withProfileFilter`, `agenda_page.dart`) filtre
strictement sur `profile_id` dès qu'un `activeProfileId` est présent, et ne
retombe sur `profil_source` (rétrocompat) que si `activeProfileId` est vide.
Un profil éleveur principal a souvent `activeProfileId` vide → tombe sur le
fallback permissif → "ça marche par accident". Un profil association a
toujours un `activeProfileId` renseigné → filtre strict → zéro résultat,
puisque `profile_id` n'a jamais été écrit. Corrigé en écrivant `profile_id`
en plus de `eleveur_profile_id` sur les deux inserts (`plans_actifs` et
`plan_taches`), web et app, exactement comme le fait déjà l'insertion
manuelle de tâche (`AddTacheModal.save` / insert manuel app) — le motif de
l'utilisatrice ("le planning de l'agenda et des protocoles doivent être les
mêmes") est maintenant respecté : même colonne de scope partout.

**Catalogue de protocoles adapté au contexte association** : les templates
sont des lignes créées par l'utilisateur (pas un catalogue préchargé
serveur), donc "mise bas"/"gestation" n'étaient pas des modèles imposés
mais des **options exposées dans le formulaire de création**, identiques
quel que soit le profil. Corrigé en filtrant, uniquement quand
`profilSource === 'association'` (web) / `User_Info.activeType ==
'association'` (app) :
- Cible "Femelles gestantes" retirée (implique une date de mise bas de
  toute façon absente en contexte association).
- Événements de référence (J0) "Saillie" et "Mise bas" retirés.
- Déclenchement automatique "Chaleurs" et "Gestation confirmée" retirés.

Pas de changement pour "Naissance"/"Bébés · Jeunes" ni "Femelles
allaitantes" (app) — restent pertinents pour une portée recueillie déjà
née, sans lien avec un élevage contrôlé.

**Bonus (garde-fou UX)** : en creusant, une tâche "promenade — Jour 1/364"
signalée par l'utilisatrice n'était pas un bug de génération — c'est le
toggle "Protocole récurrent (sans fin)" d'une étape quotidienne, qui fixe
`duree_semaines = 52` (soit 364 jours) sans avertissement suffisamment
visible. Renommé "Protocole récurrent (1 an)" et remplacé l'avertissement
discret (texte gris italique) par un encart orange explicite précisant le
nombre exact de tâches générées d'un coup et le fait que le protocole ne
se renouvelle pas automatiquement après cette période — même traitement
pour la durée manuelle dès qu'elle dépasse 12 semaines/mois. Web + app.

Vérifié : `flutter analyze` sur `planning_service.dart` (2 avertissements
`unnecessary_null_comparison` corrigés au passage, 3 autres pré-existants
inchangés hors scope) et `plan_template_form_page.dart` (0 problème),
`tsc --noEmit` + `eslint` sur `elevage/planning/page.tsx` (mêmes 10
problèmes pré-existants qu'avant, confirmé par `git stash` — aucune
régression), `next build` production complet réussi.

---

## 32. "Mes employeurs" — fuite d'animaux entre profils du même employeur (session 2026-07-11)

**Contexte** : signalé par l'utilisatrice en testant son profil garde — un
refuge l'ayant ajoutée comme employée (côté association), elle voyait
aussi les animaux du profil **éleveur** de ce même compte, alors qu'elle
n'avait accès qu'au profil association.

**Cause racine** : `mes-employeurs/page.tsx` (web) et
`MesEmployeursPage`/`employes_page.dart` (app) chargeaient déjà
correctement les animaux via `animaux_proprietes.profile_id_proprio IN
emploiProfileIds` (les seuls profils employé, hors bénévole, réellement
accordés) — **mais** ce résultat correct était fusionné avec une seconde
requête bien plus large, `animaux WHERE uid_eleveur IN (uids des
employeurs)`, sans aucun filtre de profil. N'importe quel employé, même
scopé à un seul profil (ex. association), récupérait donc TOUS les
animaux de TOUS les profils du compte employeur (éleveur, pension, etc.),
peu importe lequel l'avait effectivement embauché. Corrigé en supprimant
entièrement la requête large et en ne conservant que la requête déjà
correcte via `animaux_proprietes` — web et app.

**Portée** : ce n'est pas un simple affichage confus (contrairement à la
plupart des fuites notifications de cette session) — c'est une véritable
fuite de données d'un profil professionnel vers un autre profil du même
compte, potentiellement deux activités distinctes gérées par la même
personne mais avec des employés différents pour chacune.

Vérifié : `flutter analyze` sur `employes_page.dart` (40 problèmes,
identique au compte pré-existant confirmé plus tôt cette session — 0
nouveau, aucune erreur), `tsc --noEmit` (0 erreur), `next build`
production complet réussi.

**Reste à traiter** : audit complet des notifications cross-profil
(~40 sites d'insertion identifiés sans `profile_id`, catégorisés par
type — `employee_invite`, `contrat_invite`, `tache_assignee`,
`rdv_confirme`/`refuse`/`modifie`/`annule`, `pension_journal`,
`devis_recu`, `cession_*`, `promenade_*`, etc.). **Lots équipe + RDV
traités le même jour, voir §32.1 ci-dessous.** Un bug de lecture distinct a aussi été
repéré sur le site : `website/src/app/api/notifications/route.ts` ne
vérifie jamais `profile_type` côté GET (seulement `profile_id`),
contrairement au filtre app (`notifications_page.dart`) qui vérifie les
deux — à corriger indépendamment de l'écriture des `profile_id` manquants.
Restent aussi non traités : contrats/cession, pension, vétérinaire/
éducateur, inventaire, PetFriends/promenades/balades-ludiques, devis.

### 32.1 Lots "équipe" et "RDV" — notifications cross-profil corrigées (2026-07-11)

**Règle métier appliquée** (donnée explicitement par l'utilisatrice) :
« rejoindre une équipe c'est que pour le profil particulier
normalement » — toute notification `employee_invite`/`employee_revoked`
doit cibler le profil **particulier** (`profile_type = 'particulier'`,
`is_main = true`) du destinataire, jamais un autre type de profil, même
si le picker de recherche utilisé pour choisir le destinataire liste
d'autres types de profils (ex. recherche bénévole incluant des comptes
éleveur/association). Même logique étendue à `tache_assignee` /
`tache_validee` : la notification suit le profil particulier de la
personne assignée/validante, pas le profil métier de l'employeur.

**Lot équipe** (`employee_invite` / `employee_revoked`) — corrigé :
- App : `employes_page.dart`, `benevoles_page.dart` (association)
- Web : `employes/page.tsx`, `association/equipe/page.tsx` (3 modèles de
  données locaux distincts dans ce fichier — `MembreEquipe`, `Benevole`,
  `Employe` — chacun avec son propre `toggleActif`/`revoquer`),
  `association/benevoles/page.tsx`

**Lot RDV** (`rdv_confirme`/`refuse`/`modifie`/`annule`/
`contre_proposition`/`demande`/`retard`) — corrigé, source de vérité
`rdv.client_profile_id` / `rdv.pro_profile_id` :
- App : `agenda_page.dart`, `pro_agenda.dart`, `rdv_booking_page.dart`
- Web : `agenda/page.tsx`, `ProDashboard.tsx`, `mes-rdv/page.tsx`,
  `pension/rdv/page.tsx`, `services/pro/[uid]/page.tsx`
- Cloud Function : `functions/retard.js` (`rdv_retard`)

**Lot tâches/protocoles** (`tache_assignee` / `tache_validee`) — corrigé
en plus des sites déjà traités dans le lot équipe :
- App : `agenda_page.dart` (4 sites `plan_taches`/`taches_elevage`),
  `planning_jour_page.dart`
- Web : `elevage/agenda/page.tsx` — 5 sites `tache_assignee`
  (`AddTacheModal`, `AddProtocoleModal`, `EditTacheModal`,
  `EditProtocoleModal`, `AttributionModal`), résolus via un nouveau
  helper `resolveParticulierProfileId(uid)` (mirror de
  `resolveDisplayName`, filtré `profile_type='particulier'`). Le 6e site
  du fichier (`tache_validee`, notifie l'éleveur quand un employé valide)
  était déjà correct (`t.eleveur_profile_id`).

Vérifié : `flutter analyze` combiné sur les 6 fichiers Dart touchés (62
infos/warnings, 100% pré-existants — `withOpacity`/`value` dépréciés,
`curly_braces`, champs/variables inutilisés — 0 nouveau problème),
`tsc --noEmit` propre sur chaque fichier web touché, `eslint` +
chargement Node propre sur `retard.js`, `next build` production complet
réussi.

## 33. Menu éleveur affiché à la place du menu pro (garde/santé/toilettage) — désynchronisation `profile_type` (session 2026-07-12)

**Contexte** : signalé par l'utilisatrice sur son profil petsitter (app
mobile) — le menu affichait "Mon Élevage" et toutes les entrées éleveur
au lieu du menu pro garde (Registre visites, Ma tournée, Devis, Gestion
des clés, etc.).

**Cause racine** : `User_Info.isPro` (`lib/main.dart::applyProfile()`)
est calculé via `proTypes.contains(profile_type)`, un `Set` de valeurs
littérales censé lister tous les `profile_type` professionnels. Ce Set
avait dérivé du vocabulaire réellement utilisé à la création de profil
(`_profileTypes` dans `add_profile_page.dart`, seule source de vérité) :
il contenait encore `para_medical`, `petsitter`, `promeneur` — des
valeurs qui n'ont **jamais existé** en base — au lieu des vraies valeurs
`sante`, `garde`, `toilettage`. Résultat : tout profil `garde`, `sante`
ou `toilettage` avait `isPro = false`, donc `eleveur_nav.dart` (qui
branche sur `!User_Info.isPro` pour le menu éleveur vs `User_Info.isPro`
pour le menu pro) affichait le mauvais menu.

**Portée** : le même Set dupliqué et désynchronisé était copié dans
**8 fichiers au total** (app + web), chacun avec le même défaut :
- App : `main.dart` (`isPro`/`catPro`), `bottom_nav.dart` (`_kProTypes`
  — sert aussi à faire matcher le bouton "Professionnel" du switcher de
  profil, donc ce switch pouvait aussi échouer silencieusement pour ces
  3 types), `communaute/groupe_detail_page.dart` (`_proTypes`),
  `utils/messaging_helper.dart` (`_proTypes`).
- Web : `lib/auth-context.tsx` (`PRO_TYPES`, calcule `isPro` côté web —
  même bug potentiel sur le site, pas seulement l'app), `app/employes/
  page.tsx`, `app/communaute/groupes/[id]/page.tsx`, `app/certificat/
  [token]/page.tsx` (`PRO_TYPES` locaux, même défaut).
- `components/Header.tsx` avait déjà un `PRO_TYPES` correct, mais ses
  maps `typeLabel`/`typeEmoji` gardaient les anciennes clés → badge
  "Profil"/👤 générique au lieu du bon libellé pour garde/santé/
  toilettage.
- `app/api/admin/validate-profile/route.ts` : même défaut sur
  `NAF_PREFIXES` (codes NAF autorisés par type pour la validation KBIS
  auto) — les profils garde/santé/toilettage ne bénéficiaient jamais de
  la validation automatique par code NAF faute de correspondance de clé.

**Fix** : tous les Sets/maps réalignés sur `sante`, `garde`,
`toilettage` (+ `restauration` ajouté là où absent). Un commentaire a
été ajouté à chaque Set pointant vers `add_profile_page.dart`
(`_profileTypes`) comme source de vérité, pour éviter une nouvelle
dérive future.

Vérifié : `flutter analyze` sur les 4 fichiers Dart touchés (0 nouveau
problème vs baseline), `tsc --noEmit` sur les 6 fichiers web touchés (0
nouveau problème vs baseline, confirmé par `git stash`/comparaison
avant-après). App rebuild `--release` + réinstallée sur le téléphone de
l'utilisatrice, correctif confirmé.

## 34. Sélecteur d'animal à la réservation RDV — non scopé par profil actif (session 2026-07-12)

**Contexte** : signalé par l'utilisatrice — en simulant une réservation
de RDV avec un pro (ex. petsitter), le sélecteur d'animal montrait les
animaux de son profil principal au lieu de ceux du profil actuellement
actif. Demande explicite de vérifier et corriger **pour tous les pros**.

**Cause racine** : `RdvBookingPage` (`lib/pages/pro/rdv_booking_page.dart`)
— widget de réservation partagé par **tous** les types de pro (pension,
vétérinaire, éducateur, garde, etc. via les flags `isPension`/`isVet`/
`isGarde`/catPro dynamique ; seule l'association a un chemin séparé via
`visiteAnimal`) — chargeait les animaux du client via
`animaux.or(uid_eleveur.eq.$uid,uid_proprietaire.eq.$uid)`, scopé
uniquement par l'uid Firebase brut, sans filtre `profile_id`. Un compte
multi-profil (ex. particulier + éleveur) voyait donc toujours les
animaux de tous ses profils, indépendamment du profil actif au moment
de la réservation. Le pattern correct existait déjà ailleurs
(`lib/widgets/animal_picker_sheet.dart`, scopé via `animaux.profile_id`
et `animaux_proprietes.profile_id_proprio`) mais n'avait jamais été
repris dans ce fichier.

**Portée** : `RdvBookingPage` étant l'unique point d'entrée de
réservation RDV partagé, le fix couvre tous les types de pro en une
fois. Même défaut trouvé et corrigé côté web sur l'équivalent
`services/pro/[uid]/page.tsx` — deux sites : `openRdv()` (réservation
RDV) et `openInscription()` (inscription à un cours collectif
éducateur).

**Fix** : requêtes `animaux`/`animaux_proprietes` conditionnées sur
`User_Info.activeProfileId` (app) / `activeProfileId` (web, hook
`useActiveProfile`) quand non vide, mirror exact du pattern déjà
existant dans `animal_picker_sheet.dart`.

Vérifié : `flutter analyze rdv_booking_page.dart` → 0 problème,
`tsc --noEmit` propre sur `services/pro/[uid]/page.tsx`.

## 35. "Mes devis" — même défaut de scoping profil (session 2026-07-12)

**Contexte** : signalé par l'utilisatrice immédiatement après le fix
§34 — sur "Mes devis" elle voyait un devis de son profil éducateur
alors qu'un autre profil pro (garde) était actif.

**Cause racine** : même défaut que §33/§34 — `DevisPage`
(`lib/pages/pro/education_devis_page.dart`, **page partagée** entre le
menu éducateur et le menu garde de `eleveur_nav.dart`) chargeait les
devis via `.eq('pro_uid', uid)` uniquement. La colonne `pro_profile_id`
existait déjà et était déjà correctement renseignée à la création du
devis (`_save()`, ligne ~414) — seule la lecture (`_load()`) n'était
jamais filtrée dessus.

**Portée web** : `website/src/app/education/devis/page.tsx` a le même
défaut sur sa requête `devis` initiale — et `/garde/devis` n'est qu'un
re-export de ce même fichier (`export { default } from
'@/app/education/devis/page'`), donc un seul fichier à corriger côté
web aussi. `pro_profile_id` y était déjà correctement écrit à la
création (lignes 220, 247).

**Fix** : `_load()` (app) et la requête `devis` initiale (web)
conditionnées sur le profil actif (`User_Info.activeProfileId` /
`activeProfileId`) quand non vide, même pattern que §33/§34.

**Note** : les tables `forfaits_education`/`forfaits_garde` (mêmes
pages) sont déjà des tables séparées par catégorie pro — pas de risque
de fuite éducateur↔garde sur les forfaits (seul un même compte avec
deux profils du même type serait concerné, cas non signalé, non
traité).

Vérifié : `flutter analyze education_devis_page.dart` → 0 problème,
`tsc --noEmit` propre sur `education/devis/page.tsx`.

## 36. Envoi par email — devis et facture (session 2026-07-12)

**Contexte** : reprise du gap §"petsitter — reste à faire" identifié en
début de session — l'envoi par email n'était câblé que sur
`/garde/contrat`, alors que les routes API `api/devis/notify-email` et
`api/facture/notify-email` existaient déjà (scaffoldées, jamais
appelées par aucune page).

**Devis** (`education/devis/page.tsx`, partagé éducateur/garde) :
bouton "📧 Email" ajouté sur chaque devis envoyé (si `email_client`
renseigné), appelle `api/devis/notify-email` avec le lien public déjà
existant `/devis/[token]`. Gating Premium via `usePlanGarde()` — actif
uniquement quand `catPro === 'garde'` (l'éducateur n'a pas cette
notion de plan sur le web aujourd'hui, bouton laissé ungaté pour ce
cas).

**Facture** (`elevage/facturation/page.tsx`) : contrairement à
devis/contrat, la table `factures` n'avait ni colonne `token` ni page
de consultation publique. Construits de zéro, mirror exact du pattern
devis :
- Migration `supabase/migration_facture_token.sql` — ajoute
  `factures.token` (backfill des lignes existantes via
  `gen_random_uuid()`, nouvelles factures génèrent le leur côté client
  via `crypto.randomUUID()` à la création).
- Nouvelle page publique `website/src/app/facture/[token]/page.tsx`
  (lecture seule, sans compte requis — mirror `/devis/[token]`, avec
  export PDF via `window.print()`, pas d'action accepter/refuser
  puisqu'une facture n'a pas ce concept).
- Bouton "Envoyer par email" + "Voir la facture" dans la modale détail
  de `elevage/facturation/page.tsx`. Pas de gating Premium
  supplémentaire nécessaire : toute la page Facturation est déjà
  réservée au plan Premium (`planConfig.hasPremiumFeatures`).

Migration exécutée par l'utilisatrice dans le SQL Editor Supabase,
vérifiée après coup via une requête anonyme (`token` bien présent et
rempli sur les factures existantes).

Vérifié : `tsc --noEmit` propre sur les 3 fichiers touchés/créés,
`next build` production complet réussi (`/facture/[token]` compile
comme route dynamique).

## 37. Assignation de tâche association — animaux de l'élevage visibles (session 2026-07-15)

**Contexte** : signalé par l'utilisatrice — en créant une tâche pour un
bénévole/employé depuis `/association/equipe`, le sélecteur d'animal
montrait aussi les animaux du profil éleveur du même compte.

**Cause racine** : `AssignTaskModal` dans
`website/src/app/association/equipe/page.tsx` chargeait les animaux via
`animaux.eq('uid_eleveur', uid)` — scopé uniquement par l'uid Firebase
brut, sans distinguer le profil. Même défaut que §16 (fuite cession
mes_animaux_asso) mais sur un site jamais couvert par ce fix
précédent : cette modale de tâche est un fichier séparé de la page de
listing d'animaux déjà corrigée.

**Fix** : repris le pattern déjà établi et vérifié dans
`association/animaux/page.tsx` — animaux possédés en propre par le
profil association (`animaux.uid_eleveur = uid AND is_association =
true`) UNION animaux reçus par cession et scopés à ce profil
(`animaux_proprietes.profile_id_proprio = activeProfileId`).

**App** : aucune fonctionnalité équivalente (assignation de tâche avec
sélecteur d'animal côté association) n'existe dans l'app à ce jour —
recherché dans `lib/pages/association/equipe/` et `benevoles/`, aucun
insert `taches_elevage` ni picker animal trouvé. Rien à corriger côté
app, fonctionnalité web uniquement pour l'instant.

Vérifié : `tsc --noEmit` propre, `eslint` (8 problèmes, 100%
pré-existants confirmés par `git stash`/comparaison avant-après — 0
nouveau), `next build` production complet réussi.

**Suite (même session)** : le signalement initial de l'utilisatrice
visait en fait `/mes-taches` (pas `/association/equipe`) — au moment
du premier passage, cette page n'avait aucune création de tâche
localement car un commit d'une collègue (Natacha, 2026-07-13,
`47ac38b8`) ajoutant exactement cette fonctionnalité n'avait pas
encore été récupéré (`git pull`) sur cette branche de travail. Une fois
fusionné, le même défaut a été retrouvé dans
`loadEquipeEtAnimaux()` de `website/src/app/mes-taches/page.tsx`
(`animaux.eq('uid_eleveur', user.uid)` sans scoping profil) et corrigé
avec le même pattern owned(is_association)+cession
(animaux_proprietes.profile_id_proprio). Deux fichiers distincts avec
le même bug, corrigés séparément : `association/equipe/page.tsx` (déjà
existant) et `mes-taches/page.tsx` (nouveau, tout juste ajouté par la
collègue).

Vérifié : `tsc --noEmit` propre, `eslint` identique avant/après
(4 problèmes, 100% pré-existants, confirmé `git stash`), `next build`
production complet réussi.

---

## 38. Module anatomie ostéo/kiné — gating abonnement + support maréchal-ferrant (session 2026-07-16)

**Contexte** : suite du module anatomie livré §37bis (`b79605bf`, 2026-07-15).
Deux manques identifiés en relisant la grille tarifaire §8.1 :
1. L'ajout de séances au carnet santé (schéma anatomique) n'était soumis à
   aucune vérification d'abonnement, alors que la grille tarifaire "Soins
   para-médicaux" prévoit que FREE reste à l'annuaire basique (token 72h) et
   que seules les formules Essentiel (19€/mois) et Pro (29€/mois) donnent
   accès à l'ajout de séances.
2. Le maréchal-ferrant, pourtant regroupé avec ostéo/kiné sous la même grille
   tarifaire, n'avait accès ni au module anatomie ni même au menu "Mes
   patients" — aucune trace de `marechal_ferrant` dans `eleveur_nav.dart`,
   `pro_clients_page.dart`, `animal_fiche.dart` (app) ni `Header.tsx`
   `effectiveIsVet` (web), alors que l'annuaire et les pages patients avaient
   déjà un support partiel (labels, emoji) suggérant que l'intégration avait
   été commencée puis jamais terminée.

**Vérifié avant tout changement** : tables `seances_osteo`/`points_osteo`
(migrations du 2026-07-15) bien présentes en base (requête REST directe,
200 + tableau vide) — aucune régression à corriger là-dessus.

**Fix 1 — gating abonnement** :
- `plan_service.dart` (app) : nouvelle classe `SantePlanConfig` +
  `santeConfigs`/`getSanteConfig`/`getSantePlansLive(profilType)`/
  `getSantePlanCode(uid, profilType)`, sur le même modèle que
  Garde/Éducation/Pension. `profilType` paramétré ('sante' ou
  'marechal_ferrant') car ce sont deux abonnements distincts malgré une
  grille tarifaire identique.
- `supabase/migration_sante_plans_tarifaires.sql` : seed `plans_tarifaires`
  pour `profil_type IN ('sante', 'marechal_ferrant')`, plans free/essentiel/
  pro, `features` jsonb avec `hasAjoutSeances` comme différenciateur — à
  exécuter dans Supabase Dashboard → SQL Editor.
- `anatomie_points_page.dart` (app) et `AnatomiePoints.tsx` → `AnatomieSeances`
  (web, nouveau prop `profilType`) : `_nouvelleSeance()`/`nouvelleSeance()`
  vérifie `hasAjoutSeances` avant insertion ; si FREE, affiche un dialog/modal
  d'upsell renvoyant vers la nouvelle page d'abonnement au lieu de créer la
  séance.
- Nouvelle page app `sante_abonnement_page.dart` (partagée sante/
  maréchal-ferrant via prop `profilType`, sur le modèle de
  `garde_abonnement_page.dart` — l'upgrade réel se fait sur le site, l'app
  ne fait que rediriger via `launchUrl`, cohérent avec "paiement web
  uniquement").
- Nouvelles pages web `website/src/app/sante/abonnement/page.tsx` et
  `website/src/app/marechal-ferrant/abonnement/page.tsx` (Stripe checkout/
  portal, sur le modèle de `garde/abonnement/page.tsx`).

**Fix 2 — support maréchal-ferrant** (étendu partout où `sante` était déjà
géré, même traitement) :
- App : `eleveur_nav.dart` + `app_nav_drawer.dart` (menu "Mes patients"/
  "Mes équidés suivis" avec icône dédiée), `pro_clients_page.dart`
  (`vetMode`, bouton "Carnet de santé"), `animal_fiche.dart` (3 endroits :
  `_tabCount`, liste des tabs, contenu de l'onglet Anatomie).
- Web : `Header.tsx` `effectiveIsVet` (menu "Mes patients", identique à
  vétérinaire/santé — le nom `MENU_VET` est un artefact historique, son
  contenu est en réalité générique), `mes-patients/[id]/page.tsx`
  (`isVet`/`hasAnatomie`, onglet Anatomie).

Vérifié : `flutter analyze` sur les 7 fichiers app touchés/créés — 0 erreur
(uniquement des warnings de style pré-existants ailleurs dans les mêmes
fichiers). `npx tsc --noEmit` sur le site — 0 nouvelle erreur (les erreurs
restantes pré-existaient, confirmé via `git show HEAD`).

**How to apply** : la migration `migration_sante_plans_tarifaires.sql` doit
être exécutée manuellement avant que le gating ne prenne effet correctement
(sinon `getSantePlansLive`/`getSantePlanCode` retombent sur le fallback
statique `free`, ce qui bloque à tort l'ajout de séances pour les comptes
Essentiel/Pro déjà souscrits ailleurs — à vérifier si des comptes sante/
maréchal-ferrant existent déjà avant bascule en prod).

---

## 39. Nouveau module "Taxi animalier" (`profil_type = 'taxi_animalier'`) (session 2026-07-16)

**Contexte** : type de profil spec-é par l'utilisatrice mais jamais créé —
confirmé §28.1 ("`'taxi'` n'existe pas du tout") : seule une catégorie de
filtre annuaire existait (`services_page.dart`), aucun compte réel possible.
Choisi comme premier des trois nouveaux modules (avec Photographe et
Toiletteur) car le plus simple ("pas de contrat, simple réservation").

**Décisions prises avec l'utilisatrice** :
- Distance/temps de trajet en ligne droite (haversine, `GeocodingHelper`
  déjà utilisé par `tournee_page.dart`) — pas d'intégration Directions API.
- Système d'avis **générique** `avis_pro` (pas dédié taxi), réutilisable tel
  quel par les futurs modules Photographe/Toiletteur.
- `cat_pro` = `taxi_animalier` (pas `'taxi'`), pour matcher les filtres
  annuaire déjà en place.

**Implémenté, par phase** :
1. **Type de profil** : ajouté partout où `marechal_ferrant` (dernier type
   ajouté) était déjà branché — `add_profile_page.dart`, `main.dart`
   (proTypes/isPro), `eleveur_nav.dart`/`app_nav_drawer.dart`, `Header.tsx`
   (PRO_TYPES), `profil/ajouter/page.tsx`, `inscription/page.tsx`,
   `profile_switcher_header.dart`, `notifications_page.dart`, admin
   (`pro_detail.dart`/`pro_list.dart`), `groupe_detail_page.dart`,
   `messaging_helper.dart`, `ServicesMap.tsx`, `ProDashboard.tsx`,
   `validate-profile/route.ts` (codes NAF transport : 4932/4939, best-effort
   — à vérifier officiellement avant volumétrie réelle).
2. **Réservation** : réutilisé `RdvBookingPage`/`rdv_booking_page.dart`
   (système motifs dynamiques déjà générique par `cat_pro`, juste une
   entrée `taxi_animalier` ajoutée) + nouveau flag `isTaxi` pour les champs
   spécifiques (adresse départ/arrivée, nombre d'animaux, géocodage via
   `geocoding` package). Mirror web dans
   `services/pro/[uid]/page.tsx`. Nouvelles colonnes sur `rdv` (déjà
   scopée profil : `pro_uid`/`pro_profile_id`/`client_uid`/
   `client_profile_id`, aucune colonne de scoping à ajouter) —
   `migration_rdv_taxi_columns.sql`.
3. **Planning** : aucun changement — `creneaux_pro`/`pro_agenda.dart` déjà
   entièrement génériques, sans filtre `cat_pro`.
4. **Carte/trajet** : nouveau `taxi_tournee_page.dart` (dérivé de
   `tournee_page.dart`, adapté pour un trajet départ→arrivée par course
   plutôt qu'un seul lieu par visite).
5. **Historique** : nouveau `taxi_trajets_page.dart` (dérivé de
   `registre_visites_page.dart`, simplifié — pas de rapport de visite ni de
   contrat de prestation, hors scope taxi).
6. **Factures** : nouvelle table `taxi_factures` (scopée pro ET client dès
   la création — `migration_taxi_factures.sql`) + `taxi_factures_page.dart`
   (dérivé de `pension_factures_page.dart`). Montant saisi manuellement à la
   facturation (pas de tarification kilométrique automatique — aucun champ
   tarif/km construit sur le profil pour l'instant, laissé pour plus tard).
7. **Avis** : nouvelle table générique `avis_pro` (`migration_avis_pro.sql`)
   + widget réutilisable `lib/widgets/avis_pro_widget.dart`
   (`AvisProSection`), avec trigger de recalcul `note_moyenne`/`nb_avis` sur
   `user_profiles` dès la création (contrairement à petfriendly où ce
   trigger avait été fait dans une session ultérieure). Affiché sur
   `service_detail_page.dart` pour `cat_pro == 'taxi_animalier'`.

**Vérifié** : `flutter analyze` complet (2212 issues, 0 nouvelle erreur —
les 17 erreurs restantes sont toutes dans `PetsMatch-main/`, dossier dupliqué
obsolète sans rapport), `npx tsc --noEmit` et `npm run build` (site) propres
(mêmes erreurs pré-existantes qu'avant, confirmées via `git show HEAD`).

**How to apply** : 3 migrations à exécuter dans Supabase Dashboard avant mise
en prod (`migration_rdv_taxi_columns.sql`, `migration_taxi_factures.sql`,
`migration_avis_pro.sql`). Aucun compte `taxi_animalier` n'existe encore en
base — déploiement propre, rien à backfiller.

---

## 40. Module "Photographe animalier" — construction complète (session 2026-07-16)

**Contexte** : `profile_type = 'photographe'` existait déjà comme type de
profil mais sans aucune fonctionnalité dédiée (socle pro générique
agenda/RDV uniquement). Deuxième des trois modules demandés (après Taxi
animalier), plus riche : prestations tarifées, contrat signé
électroniquement, paiement acompte+solde, galerie de livraison photo.

**Décision validée avec l'utilisatrice** : une seule facture par
prestation avec `montant_acompte`+`montant_solde`+`montant_total` et un
statut détaillé (`acompte_du`→`acompte_paye`→`solde_du`→`payee`), plutôt
que deux factures séparées.

**Implémenté, par phase** :
1. **Prestations & tarifs** : nouvelle table `prestations_photographe`
   (type/prix/durée/nb photos/délai livraison/km inclus/prix km
   supp/acompte %/options JSONB), `photographe_prestations_page.dart`
   (CRUD). `forfaits_garde`/`forfaits_education` jugés trop pauvres pour
   être réutilisés (pas d'options ni d'acompte/km/délai).
2. **Réservation** : `rdv.prestation_id` (nouvelle colonne) + flag
   `isPhotographe` sur `RdvBookingPage` (sélection de prestation au lieu du
   motif dynamique, champ "Lieu du shooting" réutilisant les colonnes
   `adresse_depart`/`lat_depart`/`lng_depart` déjà ajoutées pour le taxi —
   une seule adresse suffit ici). Mirror web **différé** (le formulaire web
   `services/pro/[uid]/page.tsx` utilise un catalogue de motifs statique
   `MOTIFS_BY_CAT`, pas de fetch dynamique de prestations — à construire
   dans une session ultérieure si besoin).
3. **Contrat + signature électronique** : réutilise intégralement le
   mécanisme existant (`documents_animaux` + `/signer-contrat/[token]` +
   signature canvas) — Yousign confirmé être un stub 503, jamais utilisé en
   pratique. Nouveau `website/src/lib/contrat-photographe.ts`
   (`generateContratPrestationPhotoHTML`, calqué sur `contrat-pension.ts`),
   nouvelle branche `contrat_prestation_photo` dans
   `signer-contrat/[token]/page.tsx`, bouton "Contrat" sur la carte RDV de
   `pro_agenda.dart` (nouveau callback `onContrat`, dérivé de
   `_genererContratSignature` de `registre_visites_page.dart`).
4. **Facturation acompte/solde** : nouvelle table `photographe_factures`
   (montants acompte/solde/total + statut détaillé), dérivée de
   `taxi_factures` (session précédente). Bouton "Facturer" sur la carte RDV
   (nouveau callback `onFacturer`, pré-remplit les montants depuis
   `prestations_photographe.prix`/`acompte_pourcentage`).
5. **Galerie de livraison** : 3 nouvelles tables `albums_photo` (un par
   RDV), `album_photos` (upload multi via `storage_helper.dart`, favoris),
   `album_partage` (calquée exactement sur `partage_animal` — token auto,
   expire_at, actif — aucun système multi-photos n'existait avant).
   `photographe_album_page.dart` (app, upload/favoris/partage avec QR code)
   + page publique `website/src/app/album/[token]/page.tsx` (galerie +
   téléchargement sans connexion, sur le modèle de `/partage/[token]`).
   Nouveau callback `onAlbum` sur la carte RDV.
6. **Tableau de bord** : `photographe_dashboard_page.dart` — agrégats
   calculés à la volée (nombre de shootings terminés, CA depuis
   `photographe_factures` payées, km parcourus ce mois-ci depuis la
   position du pro jusqu'à `rdv.lat_depart`/`lng_depart`, note moyenne
   `avis_pro` déjà dénormalisée sur `user_profiles`). Aucun dashboard
   CA/km n'existait pour aucun profil pro avant celui-ci.

**Vérifié** : `flutter analyze` complet (2214 issues, 0 nouvelle erreur —
comparé à la baseline pré-session), `npx tsc --noEmit` et `npm run build`
(site) propres (mêmes erreurs pré-existantes, confirmées via `git show
HEAD`).

**How to apply** : 3 migrations à exécuter dans Supabase Dashboard avant
mise en prod (`migration_prestations_photographe.sql`,
`migration_rdv_photographe_columns.sql`, `migration_photographe_factures.sql`,
`migration_albums_photo.sql`). Aucun compte `photographe` actif n'a encore
utilisé ces fonctionnalités — déploiement propre, rien à backfiller.
Le mirror web de la réservation (point 2) reste à faire si l'utilisatrice
veut que la prise de RDV avec choix de prestation fonctionne aussi depuis
le site, pas seulement l'app.

---

## 41. Module "Toiletteur" — construction complète (session 2026-07-16)

**Contexte** : `profile_type = 'toilettage'` existait déjà comme type de
profil mais sans aucune fonctionnalité dédiée. Troisième et dernier des
modules pro demandés (après Taxi animalier et Photographe animalier), et le
plus complexe : prix variables selon espèce/poids, planning
multi-employés avec détection de conflit, fiche client avec
préférences/historique, grille tarifaire à 3 paliers (GRATUIT/PRO/PREMIUM)
avec fonctionnalités gatées.

**Décision validée avec l'utilisatrice** : planning multi-employés V1 en
vue par employé + assignation simple (dropdown à la réservation) et
détection de conflit à la création, sans glisser-déposer (hors scope V1).

**Implémenté, par phase** :
1. **Grille tarifaire** : `ToilettagePlanConfig` dans `plan_service.dart`
   (dupliqué de `SantePlanConfig`) — free (1 employé, planning simple) /
   pro 15€ (facturation, stats, galerie, export, notifications, employés
   illimités) / premium 25€ (+ planning employés, contrats+signature,
   paiement en ligne, sync Google Agenda, mise en avant — ces 3 derniers
   affichés dans la grille mais non implémentés dans cette session).
   `migration_toilettage_plans_tarifaires.sql`, `toilettage_abonnement_page.dart`
   (app) + `website/src/app/toilettage/abonnement/page.tsx` (web), Stripe
   déjà générique par `profil_type` (aucun code serveur à toucher).
2. **Prestations à prix variables** : `migration_prestations_toilettage.sql`
   (type/nom/prix_base/durée/`grille_prix` JSONB — tranches
   espèce×poids/`supplements`/`especes`). `toilettage_prestations_page.dart`
   (CRUD + éditeur de tranches) et fonction pure
   `prixPourAnimal(prestation, espece, poidsKg)` (résout le prix depuis
   `grille_prix`, fallback `prix_base`).
3. **Réservation prestation + employé + conflit** :
   `migration_postes_toilettage.sql` (table `postes_toilettage` +
   `rdv.employe_id`/`poste_id`, drop de la FK trop stricte
   `rdv_prestation_id_fkey` héritée du module photographe — `prestation_id`
   est désormais une colonne générique partagée entre modules, plus
   typée-table). Flag `isToilettage` sur `RdvBookingPage` : sélection
   prestation, prix calculé selon l'animal sélectionné (espèce/poids),
   sélection employé (`ChoiceChip`, uniquement si plusieurs employés actifs
   non-bénévoles). Détection de conflit étendue : blocage par créneau
   scopé à l'employé sélectionné (réservations parallèles autorisées entre
   employés différents), sinon blocage pro-large classique.
4. **Employés enrichis + planning (Premium)** :
   `migration_employes_toilettage.sql` (colonnes `couleur_planning`/
   `competences`/`horaires` sur `employes` + table `employe_conges`).
   `toilettage_employes_page.dart` (page dédiée, n'altère pas
   `employes_page.dart` existante), gatée `hasPlanningEmployes` avec
   upsell vers l'abonnement si formule inférieure. Invitation d'employé
   réutilise `EmployesPage`/`employe_profile_id` tel quel (déjà corrigé
   cross-profil plus tôt dans la session). `toilettage_planning_employes_page.dart`
   (vue jour, filtre par employé, RDV colorés par `couleur_planning`, sans
   glisser-déposer).
5. **Fiche client** : `migration_fiches_toilettage.sql` (`fiches_toilettage`
   1/couple animal×profil pro : shampooing préféré/allergies/coupe
   habituelle/notes, + `fiches_toilettage_photos` avant/après).
   `toilettage_fiche_client_page.dart` (préférences, historique des RDV
   terminés, upload photo caméra via `storage_helper.dart`). Nouveau
   callback `onFiche` sur la carte RDV de `pro_agenda.dart`.
6. **Facturation + tableau de bord** : `migration_toilettage_factures.sql`
   (montant simple, pas d'acompte/solde — dérivée de
   `migration_taxi_factures.sql`, contrairement au module photographe).
   `toilettage_factures_page.dart` (liste/filtre par statut/export PDF/
   marquer payée). Le callback `onFacturer` de `pro_agenda.dart`
   (jusque-là dédié au photographe) est étendu avec une branche
   `catPro == 'toilettage'` → nouvelle méthode `_facturerToilettage`
   (montant unique, pas de dialogue acompte/solde).
   `toilettage_dashboard_page.dart` : RDV terminés, CA (`toilettage_factures`
   payées), temps moyen (moyenne `duree_minutes`), clients fidèles
   (regroupement `client_uid` en mémoire, seuil ≥ 3 RDV), note moyenne
   (`avis_pro`/`user_profiles.note_moyenne` déjà dénormalisée).

**Vérifié** : `flutter analyze` complet (2217 issues, 0 nouvelle erreur —
comparé à la baseline pré-session, `PetsMatch-main/` exclu).

**How to apply** : 6 migrations à exécuter dans Supabase Dashboard avant
mise en prod (`migration_toilettage_plans_tarifaires.sql`,
`migration_prestations_toilettage.sql`, `migration_postes_toilettage.sql`,
`migration_employes_toilettage.sql`, `migration_fiches_toilettage.sql`,
`migration_toilettage_factures.sql`). Aucun compte `toilettage` actif n'a
encore utilisé ces fonctionnalités — déploiement propre, rien à
backfiller. Sync Google Agenda et paiement en ligne (items PREMIUM affichés
dans la grille) restent à construire dans une session ultérieure.

---

*Document maintenu par l'équipe PetsMatch — toute modification fonctionnelle doit être reportée ici avant implémentation.*
