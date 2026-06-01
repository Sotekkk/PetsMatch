# PetsMatch — Spécifications fonctionnelles complètes
**Date de mise à jour : 2026-06-01**
**Branche active : `feature/v2-updates`**

---

## 1. Présentation du projet

PetsMatch est une plateforme dédiée aux éleveurs et propriétaires d'animaux, disponible sur **3 supports synchronisés** :

| Support | Technologie | Statut |
|---|---|---|
| App Android | Flutter | ✅ En production |
| App iOS | Flutter | 🔜 À publier |
| Site web | Next.js 14 | ✅ En développement actif |

**Profils utilisateur :**
- **Éleveur** : gestion d'élevage, annonces, registre, animaux, contrats
- **Particulier** : recherche d'annonces, animaux perdus, animaux personnels
- **Professionnel** (vétérinaire, etc.) : à venir
- **Admin** : panel de gestion (à développer)

**Règle de développement :** toute fonctionnalité est déployée sur les 3 versions simultanément. Design identique (couleurs, composants).

---

## 2. Architecture technique

### Stack

| Composant | Solution | Notes |
|---|---|---|
| Auth | Firebase Auth | UID = clé étrangère partout |
| Base de données | Supabase (PostgreSQL) | Migration Firestore → Supabase terminée en mai 2026 |
| Stockage fichiers | Firebase Storage | Photos animaux, documents |
| Push notifications | Firebase Cloud Messaging (FCM) | Alertes perdus + likes |
| App mobile | Flutter (Dart) | Android + iOS |
| Site web | Next.js 14 (App Router) + TypeScript + Tailwind CSS | |
| Functions | Firebase Cloud Functions (Node.js) | `sendLikeNotification`, `notifyUsersNearLostAnimal` |

### Supabase
- URL : `https://zyvpngcvzrkdytypjlyq.supabase.co`
- RLS : désactivé (à réactiver avec politiques basées sur Firebase UID)
- Tables principales : `users`, `animaux`, `annonces`, `conversations`, `messages`, `alertes_perdus`, `animaux_trouves`, `alimentations`, `marques_aliments`, `vaccinations`, `traitements`, `visites`, `gestations`, `saillies`, `registre_entree_sortie`

### Navigation Flutter
- Bottom nav persistante dans toutes les sous-pages via `IndexedStack` + `GlobalKey<NavigatorState>` par onglet + `PopScope(canPop: false)`.

---

## 3. Fonctionnalités implémentées — V1 ✅

### 3.1 Authentification et profil

| Fonctionnalité | App | Web |
|---|---|---|
| Inscription en 3 étapes (rôle → infos perso → email/mdp) | ✅ | ✅ |
| Connexion / déconnexion | ✅ | ✅ |
| Profil éleveur (nom élevage, adresse, photos) | ✅ | ✅ |
| Profil particulier (prénom, nom, ville, téléphone) | ✅ | ✅ |
| Synchronisation Firestore + Supabase à chaque édition | ✅ | ✅ |
| Géocodage adresse (latitude/longitude + locality Google Places) | ✅ | ✅ |

### 3.2 Mes animaux — Fiche animal

**Onglet Identité**

| Fonctionnalité | App | Web |
|---|---|---|
| Espèce, race (autocomplete JSON), sexe, date naissance, couleur, poids | ✅ | ✅ |
| Photo principale + galerie (crop carré) | ✅ | ✅ |
| Numéro de puce / tatouage | ✅ | ✅ |
| Généalogie : père et mère (nom, race, puce) | ✅ | ✅ |
| Sélecteur père/mère depuis "mes animaux" (bottom sheet) | ✅ | ✅ |
| Registre Entrées/Sorties (provenance, destinsataire, cause de sortie) | ✅ | ✅ |
| Auto-fill registre depuis généalogie (provenance = naissance) | ✅ | ✅ |
| Département auto depuis Google Places dans registre | ✅ | ✅ |

**Onglet Suivi Repro (éleveur)**

| Fonctionnalité | App | Web |
|---|---|---|
| Cycles de chaleurs (date début/fin, intervalles) | ✅ | ✅ |
| Saillies (partenaire, date, notes) | ✅ | ✅ |
| Gestation auto-créée depuis saillie (durée par espèce) | ✅ | ✅ |
| Gestation confirmée (switch + bannière rappel vétérinaire) | ✅ | ✅ |
| Portées | ✅ | ✅ |

**Onglet Carnet Santé**

| Fonctionnalité | App | Web |
|---|---|---|
| Vaccinations (nom, date, rappel) | ✅ | ✅ |
| Antiparasitaires / Vermifuges | ✅ | ✅ |
| Visites vétérinaires | ✅ | ✅ |
| Courbe de poids | ✅ | ✅ |
| Notifications rappels (1 semaine + 1 jour + jour J) | ✅ | — |

**Onglet Alimentation** *(ajouté mai 2026)*

| Fonctionnalité | App | Web |
|---|---|---|
| Calcul DER (70 × kg^0.75 × facteurs) | ✅ | ✅ |
| Facteurs : activité, phase de vie, stérilisation, état repro, énergie de la race | ✅ | ✅ |
| Types de ration : Croquettes, BARF, Ménagère, Mixte | ✅ | ✅ |
| Mixte avec 3 options de 2e composant (Pâtée / BARF / Ménagère) | ✅ | ✅ |
| Option repas séparés (croquettes matin, pâtée soir) | ✅ | ✅ |
| Plan de repas journalier détaillé | ✅ | ✅ |
| Vue résumé (calories nécessaires, ration, composition, calories apportées) | ✅ | ✅ |
| Doses modifiables manuellement par l'utilisateur | ✅ | ✅ |
| Saisie densité énergétique manuelle (depuis le paquet) | ✅ | ✅ |
| Recette bottom sheet : ménagère (proportions) + BARF (grammes par composant) | ✅ | ✅ |
| Recherche marque/gamme depuis base de données | ✅ | ✅ |
| Interpolation doses fabricant par poids | ✅ | ✅ |
| Indicateur ✅/⚠️ calories apportées vs DER | ✅ | ✅ |
| Bouton "Recalculer" → calculateur, puis retour résumé après save | ✅ | ✅ |

### 3.3 Base de données marques d'aliments

| Contenu | Nb gammes | Statut |
|---|---|---|
| Croquettes chien adulte | 20 | ✅ Migration v2 |
| Croquettes chat adulte | 10 | ✅ Migration v2 |
| Pâtées chien adulte | 8 | ✅ Migration v2 |
| Pâtées chat adulte | 12 | ✅ Migration v2 |
| Granulés cheval adulte | 4 | ✅ Migration v2 |
| Granulés lapin adulte | 6 | ✅ Migration v2 |
| Croquettes chiot (puppy) | 14 | ✅ Migration v3 |
| Pâtées chiot (puppy) | 3 | ✅ Migration v3 |
| Croquettes chaton (kitten) | 7 | ✅ Migration v3 |
| Pâtées chaton (kitten) | 7 | ✅ Migration v3 |
| **Total** | **~91 gammes** | ⚠️ Migrations à exécuter dans Supabase |

Marques couvertes : Royal Canin, Hill's Science Plan, Purina (ONE + Pro Plan), Farmina N&D, Josera, Brit Care, Belcando, Taste of the Wild, Orijen, Animonda, Schesir, Almo Nature, True Instinct, Edgard & Cooper, Virbac HPM, Calibra, Advance, Oxbow, Versele-Laga, Cunipic, Cavalor, Spillers, Equifirst.

Doses calculées depuis la formule DER avec facteur croissance pour les juniors. Interface admin à créer pour ajouter/modifier sans code.

### 3.4 Annonces

| Fonctionnalité | App | Web |
|---|---|---|
| Création annonce (compagnon / portée / saillie) | ✅ | ✅ |
| Galerie photos avec crop carré | ✅ | ✅ |
| Liste "Mes annonces" avec filtres statut (disponible / pause / archivée) | ✅ | ✅ |
| Modifier / Mettre en pause / Supprimer une annonce | ✅ | ✅ |
| Feed immersif style TikTok (photo 4:5, glassmorphism) | ✅ | ✅ |
| Filtres : espèce, race (autocomplete), type, distance | ✅ | ✅ |
| Likes animaux + notification push éleveur | ✅ | ✅ |
| Favoris utilisateur | ✅ | ✅ |
| Clic notification like → annonce directe | ✅ | — |
| "Animaux similaires" → liste filtrée (pas le feed) | ✅ | — |

### 3.5 Animaux perdus / trouvés

| Fonctionnalité | App | Web |
|---|---|---|
| Déclarer un animal perdu | ✅ | ✅ |
| Déclarer un animal trouvé | ✅ | ✅ |
| Liste avec filtres (espèce, race, ville, région, département) | ✅ | ✅ |
| Carte interactive | ✅ | ✅ |
| Auto-fill département (Google Places) | ✅ | ✅ |
| Pré-remplissage photo depuis fiche animal | ✅ | ✅ |
| Contact via messagerie interne | ✅ | ✅ |
| Partager (génère message texte) | ✅ | ✅ |
| Notifications push aux éleveurs proches | ✅ | — |
| Réinitialisation des filtres | ✅ | ✅ |

### 3.6 Messagerie

| Fonctionnalité | App | Web |
|---|---|---|
| Liste conversations | ✅ | ✅ |
| Chat temps réel (Supabase Realtime) | ✅ | ✅ |
| Types : Annonce / Animal perdu / Contact élevage | ✅ | ✅ |

### 3.7 Élevages (annuaire)

| Fonctionnalité | App | Web |
|---|---|---|
| Liste élevages avec filtres (espèce, race, localisation) | ✅ | ✅ |
| Fiche élevage | ✅ | ✅ |
| Contacter l'éleveur | ✅ | ✅ |

### 3.8 Enregistrement / Sanitaire (éleveur)

| Fonctionnalité | App | Web |
|---|---|---|
| Registre Entrées/Sorties | ✅ | ✅ |
| Suivi sanitaire (vaccins, traitements, visites) | ✅ | ✅ |
| Contrats de réservation | ✅ | ✅ |
| Factures | ✅ | — |
| Export PDF | ✅ | — |
| Import Excel | — | 🔜 |

### 3.9 Notifications

| Type | App | Web |
|---|---|---|
| Badge rouge cloche (Realtime + polling 20s) | ✅ | ✅ |
| Alertes animaux perdus (push FCM) | ✅ | — |
| Likes/favoris (push FCM via Cloud Function) | ✅ | — |
| Rappels santé (vaccins, antiparasitaires) | ✅ | — |

---

## 4. Fonctionnalités en cours / V2 🔜

### 4.1 Alimentation — compléments
- [ ] Interface admin web pour ajouter/modifier marques sans code
- [ ] Historique des changements d'alimentation (marque/gamme + date)
- [ ] Alertes prise/perte de poids rapide
- [ ] Ration gestante (+25% à partir de S5) et lactation (+50%)
- [ ] Chiots/chatons en sevrage (progression 4→8 semaines)
- [ ] Lien avec courbe de poids existante
- [ ] Recettes en base de données (admin)

### 4.2 Fiche animal — compléments
- [ ] Notifications carnet santé sur le web (rappels vaccins, antiparasitaires)
- [ ] Transfert de propriété : lien email → fiche animal sur nouveau compte → historique
- [ ] Animaux "Anciens" (post-transfert) : lecture seule, sans carnet ni repro
- [ ] Contrats payants (offre future)

### 4.3 Suivi repro — compléments
- [ ] Saillies croisées : MAJ automatique de la fiche partenaire (même élevage)

### 4.4 Annonces — compléments
- [ ] Description père/mère visible sur fiche annonce (particulier)
- [ ] Identification mère obligatoire selon espèce
- [ ] Visuel liste annonces web : style "match" avec filtres (cohérence app)

### 4.5 Messagerie — redesign
- [ ] Ajout "Messages" au menu (app + web)
- [ ] Types : Annonce / Animal perdu / Contact élevage / Discussion libre / Service pro
- [ ] Appui long : Épingler / Archiver / Sourdine / Bloquer / Supprimer

### 4.6 Feed — filtres
- [ ] Filtre race dans le feed selon l'espèce sélectionnée

### 4.7 Registre E/S
- [ ] Import Excel (web, profil éleveur)
- [ ] Export PDF web

### 4.8 Profil professionnel
- [ ] Vétérinaires, comportementalistes, etc.
- [ ] Page Services

---

## 5. Fonctionnalités planifiées — V3

### 5.1 Sécurité / Conformité RGPD (obligatoire avant lancement public)

**V1 minimum légal :**
- [ ] CGU + Politique de confidentialité (pages statiques + lien app)
- [ ] Bannière cookies RGPD (opt-in/opt-out, Google Analytics, Firebase)
- [ ] Mentions légales (éditeur, hébergeur, responsable de traitement)
- [ ] Registre des traitements RGPD (document interne)
- [ ] Consentement explicite inscription (`cgu_accepted_at` en BDD)
- [ ] Export données utilisateur (RGPD art. 20) → JSON complet
- [ ] Suppression compte + données (RGPD art. 17) → cascade Auth + Supabase + Storage

**V2 sécurité avancée :**
- [ ] RLS Supabase durcies par table (politiques Firebase UID)
- [ ] 2FA opt-in (TOTP / SMS)
- [ ] Gestion rôles fins (admin / éleveur / particulier / pro / vétérinaire)
- [ ] Partage vétérinaire temporaire (lien token 72h → carnet santé lecture seule)
- [ ] Logs d'accès (archivage 6 mois)
- [ ] Audit admin (`audit_logs`)
- [ ] Chiffrement données sensibles (puce + données santé, AES Edge Function)
- [ ] Sauvegardes automatiques + test restauration trimestriel

### 5.2 Animaux perdus — compléments
- [ ] iOS : notifications non reçues (à investiguer)
- [ ] Carte web avec filtres synchronisés carte ↔ liste

### 5.3 Panel admin
- [ ] Gestion utilisateurs (suspension, rôles)
- [ ] Gestion marques aliments (CRUD sans code)
- [ ] Gestion recettes ménagères
- [ ] Statistiques plateforme
- [ ] Audit logs

### 5.4 Suivi portées
- [ ] Poids individuels des chiots/chatons avec courbe de croissance
- [ ] Sevrage progressif

### 5.5 iOS
- [ ] Publication App Store
- [ ] Notifications push (à vérifier — alertes perdus ne passent pas actuellement)

---

## 6. Base de données Supabase — Tables principales

```
users               — profils (éleveur + particulier, sync Firebase UID)
animaux             — fiches animaux
vaccinations        — carnet santé
traitements         — antiparasitaires, vermifuges
visites             — visites vétérinaires
saillies            — suivi repro
gestations          — suivi repro (gestation_confirmee boolean)
alertes_perdus      — animaux perdus (+ departement TEXT, V2)
animaux_trouves     — animaux trouvés (+ departement TEXT, V2)
annonces            — annonces marketplace
notifications       — centre de notifications
conversations       — messagerie
messages            — messagerie
alimentations       — données alimentation par animal
marques_aliments    — base marques/gammes avec densité + doses JSONB
registre_entree_sortie — registre officiel éleveur
posts               — (réseau social, non actif)
```

---

## 7. Tâches en attente — par priorité

### Haute priorité
1. **Exécuter les migrations SQL** dans Supabase :
   - `migration_marques_v2.sql` (~50 gammes adultes)
   - `migration_marques_v3_junior.sql` (~34 gammes junior/puppy/kitten)
2. **Filtre race dans le feed** selon l'espèce sélectionnée
3. **RGPD V1** : CGU, politique confidentialité, bannière cookies, suppression compte

### Priorité moyenne
4. Interface admin web pour les marques d'aliments
5. Transfert de propriété animal
6. Notifications carnet santé sur le web
7. Export PDF web (registre, contrats)

### Priorité basse / V3
8. Portées : courbes croissance individuelles
9. Messagerie redesign complet
10. Panel admin complet
11. iOS : fix notifications push
12. Import Excel registre (web)

---

## 8. Palette de couleurs et design

| Nom | Hex | Usage |
|---|---|---|
| Vert primaire | `#6E9E57` | Boutons CTA, accents positifs |
| Teal | `#0C5C6C` | Couleur principale, nav, titres |
| Teal foncé | `#094F5D` | Hover / actif |
| Fond clair | `#F5F7F0` | Background général |
| Texte principal | `#1F2A2E` | Textes noirs |
| Police | Galey | Titres et textes UI |

---

## 9. Fichiers clés

| Fichier | Rôle |
|---|---|
| `lib/pages/eleveur/animaux/animal_fiche.dart` | Fiche animal complète (4 onglets) |
| `lib/pages/eleveur/nav/eleveur_nav.dart` | Navigation éleveur (bottom nav persistante) |
| `lib/pages/particulier/nav/particulier_nav.dart` | Navigation particulier |
| `lib/pages/annonces/annonces_feed_page.dart` | Feed annonces immersif |
| `lib/pages/animaux_perdus/animaux_perdus_page.dart` | Animaux perdus (liste + carte) |
| `supabase/schema.sql` | Schéma complet Supabase |
| `supabase/migration_marques_v2.sql` | Marques adultes (~50 gammes) |
| `supabase/migration_marques_v3_junior.sql` | Marques junior (~34 gammes) |
| `src/app/mes-animaux/[id]/page.tsx` | Fiche animal web (4 onglets) |
| `src/app/annonces/feed/page.tsx` | Feed annonces web |
| `src/app/mes-annonces/page.tsx` | Gestion annonces éleveur web |
