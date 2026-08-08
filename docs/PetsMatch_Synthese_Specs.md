# PetsMatch — Synthèse des specs & feuille de route
**Generé le 2026-08-06 — Consolidation specs_petsmatch.md + SPECS_PETSMATCH.md**

---

## 1. Vue d'ensemble du projet

PetsMatch est une plateforme dédiée aux acteurs de l'univers animal, disponible sur 3 surfaces synchronisées :

| Surface | Tech | Statut |
|---|---|---|
| App Android | Flutter | ✅ En production |
| App iOS | Flutter | 🔜 À publier |
| Site web | Next.js 14 + TypeScript + Tailwind | ✅ En développement actif |

**Stack technique :** Firebase Auth (identité), Supabase/PostgreSQL (données), Firebase Storage (fichiers), FCM (push notifications), Cloud Functions (crons/alertes).

**Règle absolue :** chaque feature doit être implémentée sur les 3 surfaces (Android, iOS, Web) **et** dans le panel Admin.

---

## 2. Profils utilisateurs

| Profil | Description |
|---|---|
| **Éleveur** | Gestion complète élevage — animaux, portées, annonces, registre, contrats, employés |
| **Association** | Profil secondaire ou principal — adoption, bénévoles, FA, chenil, animaux sans généalogie |
| **Particulier** | Animaux personnels, recherche annonces, animaux perdus, agenda, messagerie |
| **Professionnel** | Vétérinaire, comportementaliste, pet sitter, éducateur, garde, toilettage, ostéo, maréchal-ferrant, photographe |
| **Admin** | Panel de validation et gestion (app + web) |

**Architecture multi-profils :** 1 uid Firebase = 1 compte. Chaque profil (principal ou secondaire) a son UUID dans `user_profiles`. `User_Info.activeProfileId` pointe vers le profil actif. La table `users` reste l'identité d'authentification ; toutes les données de profil migrent progressivement vers `user_profiles`.

---

## 3. État d'avancement global

### ✅ Fonctionnalités livrées (socle)

**Authentification & profil**
- Inscription 3 étapes (rôle → infos → email/mdp), connexion, déconnexion
- Profils éleveur, particulier, pro — édition complète app + web
- Multi-profils (ajout/switch) — isolation par `profile_id` sur toutes les tables métier
- Validation admin des profils secondaires

**Animaux**
- Fiche animal (4 onglets : Identité, Repro, Santé, Alimentation) — app + web
- Généalogie, portées, suivi repro (saillie, gestation, alertes)
- Carnet santé complet (vaccins, antiparasitaires, visites, traitements, courbes poids)
- Module alimentation (DER, types de ration, marques, calculs)
- Scanner puce NFC
- Cession d'animaux — contrat de vente, signature canvas, `animaux_proprietes` (fixé §45)
- Fiche animal sans compte propriétaire + lien de réclamation (§19.4)

**Associations (✅ app + web)**
- Profil association complet (RNA, agrément, capacité)
- Animaux association (statuts spécifiques, sans généalogie)
- Annonces d'adoption — feed dédié, isolation `profil_source` (fixé §46)
- Contrat d'adoption (6 articles, participation par espèce)
- Familles d'accueil (FA) — réseau, placement, suivi
- Chenil / Enclos — gestion des logements, planning semaine
- Bénévoles — invitation, permissions, tâches assignées

**Planning & tâches**
- Templates protocoles sanitaires (vermifuge, vaccination…) — app + web
- Vue calendrier mensuelle avec pastilles (PLN01 ✅)
- Vue planning du jour + validation
- Tâches manuelles + assignation employés
- Notifications push tâches assignées

**Module Pension (✅ app + web)**
- Socle complet : registre entrées/sorties, planning d'occupation 14j, logements (chenil)
- Réservation intelligente (suggestion automatique du meilleur logement)
- Tarification automatisée par tranches de poids
- Journal de séjour avec photos/vidéos + like/réponse propriétaire
- Facturation + export CSV + alertes impayés
- Contrats pension (PDF, signature canvas)
- Accès employés au planning (permission `read_planning_pension`)
- Formules d'abonnement pension (Découverte/Pro/Premium) dans `plans_tarifaires`

**Module Garde / Pet sitter (✅ socle)**
- Navigation, abonnement, registre visites, rapports de visite
- Devis, forfaits, contrats, facturation, envoi email
- ACACED obligatoire à l'inscription + upload justificatif

**Module Éducateur (✅)**
- Cours collectifs, devis, contrats, facturation, intervenants, trajet
- Anatomie + schémas (ostéo/kiné + maréchal-ferrant)
- Gating abonnement sante (Essentiel/Pro)

**Annonces**
- Feed immersif (style TikTok) — app + web
- Marketplace : croquettes, portées, saillies, services
- Isolation éleveur ↔ association (fixé §46)
- Quotas par plan (FREE/PRO/PREMIUM)

**Messagerie**
- 7 catégories de conversations, épinglage, archivage, sourdine, blocage
- Catégorie PetFriends
- Chat groupe PetFriends

**Services & Annuaire**
- Annuaire pros (carte + liste) — vétérinaires, santé, éducation, garde, pension, toilettage, photographe
- Filtres catégorie/profession, géolocalisation
- Zone d'intervention sur carte
- Fiche profession complète + horaires + tarifs

**Lieux Pet-Friendly (✅ partiellement)**
- Feed `/lieux-pet-friendly` + filtres (app + web)
- Profil établissement complet (bannière, horaires, infos pet-friendly)
- Likes & favoris, avis clients, contestation
- Navigation GPS (Waze + Google Maps) — fix itinéraire §43
- Gestion tarifaire via admin (`plans_tarifaires`)

**PetFriends (✅)**
- Demandes d'amis bidirectionnelles, notifications
- Profil public, animaux partagés (`visible_petfriends`)
- Messagerie directe PetFriends

**Promenades collectives**
- Liste, rejoindre/quitter, formulaire création
- GPS / Waze, jauge participants, visibilité (publique/PetFriends/invitation)
- Invitations nominatives, notifications rappel

**Animaux perdus/trouvés**
- Alertes (liste + carte), matching perdu ↔ trouvé
- Notifications push (FCM)

**Facturation & contrats**
- Contrats de vente éleveur, certificat d'engagement (éleveur + association)
- Signature canvas (acquéreur + cédant) via `/signer-contrat/[token]`
- Génération PDF (window.print + CSS print)
- Envoi email (nodemailer)

**Modèle économique**
- Abonnements Stripe par type de profil (éleveur, vétérinaire, pension, garde, éducateur, sante, photo)
- Boosts ponctuels d'annonces
- Plans tarifaires éditables sans déploiement depuis `/admin`
- Associations : accès complet gratuit, permanent

**Infrastructure**
- Migration `users` → `user_profiles` en lecture : **terminée** (lots 1-16 + catégorie B, §27)
- Trigger auto-création `user_profiles` à l'inscription (§27.5)
- Trigger synonymes colonnes (acaced, téléphone — §27.3)
- Notifications push (FCM) : chaleurs, mise-bas, vaccins, rappels, tâches, RDV, perdu/trouvé, messages

---

## 4. Bugs récents corrigés (sessions 2026-08-06)

### §43 — Notifications doublons push + nom client RDV
- Doublons push corrigés (inscription en double des tokens FCM)
- Nom client dans notification RDV corrigé

### §44 — Annuaire pro (fuite santé → vétérinaires)
- Filtre catégorie web corrigé (découpe sur la virgule + test appartenance)
- Filtre `prof` (profession) aligné app ↔ web
- **Reste :** "Assurances & juridique" non construit ; "Alimentation"/"Boutiques" pointent toutes sur `referencement` sans sous-catégorie distincte

### §45 — Animaux : fuite "Mes animaux acquis" + cession mauvais profil + Realtime instable
- `animaux_acquis_page` scopé par `profile_id_proprio` (plus par uid Firebase global)
- `cession_sheet` : cible désormais le profil principal (`is_main`) de l'acquéreur (plus toujours `particulier`)
- `_confirmerCession()` : écriture `animaux_proprietes` ajoutée (acquéreur sans ligne de propriété → animal invisible)
- Realtime `annonces` remplacé par requête ponctuelle + pull-to-refresh (plus de `CHANNEL_ERROR`)
- **Reste :** corriger données historiques (animal "fly" sur compte test, `date_fin` sans réouverture)

### §46 — Annonces : fuite association ↔ éleveur
- `user_detail_page_feed` : exclusion `profil_source='association'` ajoutée côté éleveur
- `plan_service.countActiveAnnonces()` : annonces association exclues du quota éleveur
- `user_elevage_feed` : même fix dans le feed éleveur
- **Reste :** correction ponctuelle de l'annonce "Testeuse" (nom figé incorrect) — en attente de confirmation

---

## 5. Validations en cours (décisions à prendre)

Ces points sont bloqués ou en attente d'une décision de ta part avant qu'on puisse les implémenter ou les clore :

| # | Sujet | Question à trancher |
|---|---|---|
| V1 | **YouSign / Signature légale** | Fournir un abonnement YouSign + clé API pour activer le stub (`YouSignProvider`). Sans ça, toutes les signatures restent canvas manuscrit (valeur légale limitée). |
| V2 | **Données test à corriger en base** | Animal "fly" (compte "Le domaine de Negan") — `animaux_proprietes` clôturée sans réouverture. Annonce "Adoption — Testeuse" — `nom_eleveur` figé incorrect. Corriger ou laisser en l'état (comptes test) ? |
| V3 | **Annuaire : sous-catégories "Alimentation" / "Boutiques & Créateurs"** | Distinguer boutique / créateur / fournisseur alimentaire ? Nécessite d'ajouter des sous-professions standardisées à l'inscription. |
| V4 | **Paiement Stripe pension** | Saisir les prix dans `/admin` → Tarification pour créer automatiquement les produits Stripe et activer le checkout en ligne. |
| V5 | **RLS Supabase** | Politique actuelle : `USING (true)` sur toutes les tables (permissif). À durcir avant lancement production. Quand est-ce qu'on s'y attaque ? |
| V6 | **Messagerie Firestore → Supabase** | `conversations` et `messages` sont encore sur Firestore. Migration prévue mais non planifiée. |
| V7 | **iOS App Store** | App iOS prête mais non publiée. Validation Apple + dossier de publication à lancer. |
| V8 | **Lieux pet-friendly : carte interactive (PFP22)** | Marqueurs sur Google Maps / Mapbox — déjà classé V2 mais à prioriser si le feed est bien reçu. |
| V9 | **Synchronisation inverse `users` ↔ `user_profiles`** | `numero_elevage` écrit sur `users` sans répercussion sur `user_profiles`. Nettoyage du modèle d'adresse à 3 variantes + booléens redondants avec `profile_type`. Périmètre large — à planner. |
| V10 | **ACACED profil pro primaire côté web** | L'upload du justificatif ACACED a été ajouté pour les profils secondaires. Le cas profil pro *primaire* web (garde/éducateur) n'a pas été audité. |

---

## 6. Ce qui reste à construire — par module

### 6.1 Modules à compléter (features partielles)

**Associations**
- ASSO04 : Candidatures d'adoption — formulaire acquéreur (web 🔜, app 🔜, admin 🔜)
- FA V2 : Bilans/photos depuis l'app de la FA ; notifications FA sur changements statut animal

**Planning élevage**
- PLN02 : Vue calendrier web (Next.js) — seule l'app est livrée
- PLN03 : Vue unifiée "Mes tâches" pour l'employé (tâches manuelles + protocoles fusionnées)
- PLN05-07 : Export PDF protocoles, planning du jour/semaine
- Phase 3 : Rondes promenade + rotation automatique ; socialisation bébés par semaine d'âge

**Employés**
- EMP02 : Planning soigneurs (créneaux de travail, vue hebdomadaire)
- EMP03 : Affectation soigneurs → chambres/animaux
- EMP01 web : UI d'attribution des permissions (toggles dans `/elevage/employes`)

**Module Pension**
- Logement "hors service" (indisponible temporairement, hors nettoyage)
- Planning V2 : statuts "non confirmé" + distinction entrée/sortie réelle vs prévue

**Module Garde / Pet sitter**
- Gestion des clés (suivi, remise, récupération)
- Suivi GPS + tournée réordonnable
- Services récurrents + forfaits par abonnement client
- Tarifs clients personnalisés
- Créneaux horaires configurables dédiés
- Paiement en ligne des prestations (V2 explicite)
- Onboarding dédié `garde`

**Contrats**
- CONT02 : Générateur PDF côté serveur (`/api/pdf/...`) via `@react-pdf/renderer`
- CONT03 : Contrat de réservation adaptatif
- CONT04 : Contrat de vente adaptatif avec clauses éleveur + garanties légales
- CONT06 : Contrat Pension/Chenil
- CONT07 : Contrat de Prestation Pro (toilettage, dressage…)
- CONT08 : Éditeur templates adaptatifs (UI pro pour personnaliser clauses)

**Signatures**
- CERT01 app : Bouton "Certificat d'engagement" dans fiche animal (app Flutter à faire)
- CERT02 (CONT05) : Migration YouSign pour valeur légale eIDAS (bloqué sur V1)

**Lieux Pet-Friendly**
- PFP22 (V2) : Carte interactive avec marqueurs
- PFP36 (V2) : Dashboard stats pro avancées

**Promenades**
- PRO14/15 : Page détail promenade (app + web)
- PRO16 (V2) : Page "Mes promenades" (modification/annulation)
- PRO18 (V2) : Chat de groupe promenade

**PetFriends**
- PFR09 (V2) : Supprimer un PetFriend
- PFR16 (V2) : Suggestions PetFriends (même ville + mêmes espèces)
- PFR22 (V2) : Stats admin PetFriends

**Messagerie**
- MSG06 web : Notification push nouveau message (côté web non livré)
- Migration Firestore → Supabase (`conversations`, `messages`)

**Annuaire / Services**
- "Assurances & juridique" : aucun `profile_type` existant — à construire si prioritaire
- "Alimentation" / "Boutiques & Créateurs" : sous-catégories à définir

**RGPD**
- SET06 web : Export données RGPD (seule l'app est livrée)

### 6.2 Modules non démarrés

**Planning Hébergements (Pension V2)**
- Concept conçu (§4) mais lié au module Pension existant : `lieux_hebergement`, `etat_lieux_hebergement`, `position_animaux` — tables définies, pas encore déployées
- Vue "Curage du jour" (équin), alertes nettoyage > 2h

**Validation automatique & Badges de confiance (§9)**
- Validation KBIS auto via API INSEE (base posée dans `api/admin/validate-profile`)
- Badges (Certifié, Vérifié, Partenaire) — spécification écrite, UI admin à construire
- Conditions par profil : SIRET valide, RNA, agrément préfectoral, ACACED

**Régie publicitaire / Marketplace partenaires (§8.3)**
- Modèle pub ciblée (pas transactionnel) — tuiles partenaires dans le feed
- Dashboard annonceur, ciblage espèce/profil/région, rapports impressions/clics
- Non démarré — décision business d'abord

**Suivi RGPD / Audit logs**
- Table `audit_logs` prévue mais non créée
- Dashboard admin des actions sensibles

---

## 7. Priorités recommandées

Voici ce que je recommande de travailler en premier, compte tenu de l'état actuel et de tes validations en cours :

### 🔴 Priorité 1 — Stabilité et données (à faire immédiatement)

Ces points touchent à l'intégrité des données ou bloquent des validations.

**A. Correction des données test (V2)**
Décider et exécuter (ou non) la correction des 2 résidus de données :
- Animal "fly" — ligne `animaux_proprietes` clôturée sans réouverture
- Annonce "Testeuse" — `nom_eleveur` figé incorrect

**B. Saisir les prix pension dans `/admin`**
Action rapide (< 30 min) qui active le paiement Stripe pension immédiatement. La plomberie est prête (V4).

**C. RLS Supabase**
La politique `USING (true)` expose toutes les données avant lancement. À planifier avant ouverture au public, même si ça peut attendre le premier batch de vrais utilisateurs.

### 🟠 Priorité 2 — Complétude produit (bloquant pour certains profils)

**D. CERT01 app — Certificat d'engagement dans la fiche animal**
Seul le web est livré. L'éleveur qui utilise uniquement l'app ne peut pas générer de certificat. C'est une obligation légale (Loi Lucie Castets) — fort impact utilisateur.

**E. Candidatures adoption (ASSO04)**
Le flux adoption est incomplet sans dossier acquéreur. L'association peut créer des annonces mais ne peut pas gérer les candidatures structurées.

**F. PLN02 — Vue calendrier web**
L'app a le calendrier mensuel mais le web non. Asymétrie visible par les utilisateurs web (éleveurs, associations).

**G. EMP01 web — Permissions employés**
La gestion des permissions est faite en app mais l'UI web dans `/elevage/employes` n'est pas encore construite.

### 🟡 Priorité 3 — Croissance et différenciation

**H. Module Garde — Gestion des clés**
Fonctionnalité très attendue des pet sitters professionnels — différenciant fort vs concurrents.

**I. Contrats serveur (CONT02)**
Remplacer `window.print()` par un générateur PDF serveur. Nécessaire pour les contrats envoyés par email avec rendu propre + signature embarquée.

**J. Sous-catégories annuaire (V3)**
Trancher la question "Alimentation" / "Boutiques & Créateurs" pour que ces tuiles ne soient plus vides.

**K. Lieux pet-friendly — Carte interactive (PFP22)**
Classé V2 mais fort impact utilisateur si le feed décolle. À surveiller selon l'adoption.

### 🟢 Priorité 4 — V2 / futures itérations

- YouSign (V1 — bloqué sur décision/contrat business)
- Migration messagerie Firestore → Supabase
- Planning Hébergements complet (§4 — lieux_hebergement)
- Module Garde phase 3 (GPS, récurrence, forfaits clients)
- Régie publicitaire (décision business d'abord)
- Dashboard stats avancées lieux pet-friendly (PFP36)
- Export RGPD web (SET06)
- iOS App Store (dossier Apple à lancer)

---

## 8. Ce qu'il faudrait ajouter / clarifier dans les specs

Les points ci-dessous sont mentionnés dans les docs mais incompletement spécifiés — à détailler avant implémentation :

| Sujet | Gap de spec |
|---|---|
| **Candidatures adoption** | Formulaire acquéreur : quels champs exactement ? Workflow de validation par l'association ? Notifications ? |
| **Contrats V2 (CONT03-07)** | Clauses dynamiques par type et espèce — contenu exact des templates à rédiger |
| **Régie pub / Marketplace** | Modèle de ciblage précis, formats de tuiles, intégration dans le feed, dashboard annonceur |
| **Validation automatique badges** | Conditions complètes par type de profil (quels champs déclenchent quels badges) |
| **Planning Hébergements (§4)** | Statut de l'implémentation réelle vs la spec écrite — à quel point est-ce déjà dans le code pension ? |
| **Promenades — page détail** | Contenu exact de PRO14/15 (liste participants avec avatars, boutons d'action) |
| **RGPD export web** | Données à inclure côté web vs app — identiques ou périmètre différent ? |
| **"Assurances & juridique"** | Décider si on construit ce `profile_type` ou si on retire la tuile de l'annuaire |
| **Notification API route.ts web** | `api/notifications/route.ts` ne filtre pas `profile_type` côté GET (seul `profile_id`) — comportement attendu vs app |

---

## 9. Schéma BDD — Migrations en attente

Migrations écrites mais non encore exécutées dans Supabase Dashboard :

```
supabase/migration_education_devis.sql
supabase/migration_cours_collectifs_reminders.sql
supabase/migration_education_intervenants_trajet.sql
supabase/migration_conversations_categorie.sql
supabase/migration_facture_token.sql          (à vérifier — exécutée ?)
```

Tables définies dans les specs mais **tables non encore créées en BDD** :
```
lieux_hebergement         (§4 — Planning Hébergements)
etat_lieux_hebergement
position_animaux
historique_lieux_hebergement
structure_employees       (§5 — distinct de la table employes existante ?)
employee_plannings
petfriendly_places        (PFP01 — à vérifier si exécutée)
petfriendly_reviews
petfriendly_review_contests
place_likes
place_favoris
promenades_invitations    (PRO01)
petfriends                (PFR01 — à vérifier si exécutée)
audit_logs
alertes_correspondances
```

---

## 10. Design system (référence)

| Élément | Valeur |
|---|---|
| Couleur primaire (CTA) | `#6E9E57` (vert) |
| Couleur secondaire (nav, titres) | `#0C5C6C` (teal) |
| Couleur hover/actif | `#094F5D` |
| Fond général | `#F5F7F0` |
| Texte principal | `#1F2A2E` |
| Police | Galey (titres + UI) |
| Coins arrondis | `rounded-xl` (12px) / `rounded-2xl` (16px) |
| Photos | Crop carré — `image_cropper` (Flutter) |

---

## 11. Règles techniques à ne jamais oublier

- **Ne jamais écrire dans Firestore** pour les nouvelles features — tout dans Supabase
- **Firestore résiduel** (ne plus y ajouter) : conversations, messages, likedPost, bloquer, fcmToken
- **Prix Supabase** : utiliser `float8`, pas `numeric` (numeric renvoyé en string par PostgREST)
- **Races** : toujours lire depuis les JSON assets (`dog_breeds.json`, `cat_breeds.json`…)
- **FCM Token** : sauvegardé dans Firestore ET Supabase au login et sur `onTokenRefresh`
- **Multi-profils** : profil principal → `pro_profile_id = ''` (chaîne vide, jamais NULL) ; profil secondaire → `pro_profile_id = user_profiles.id`
- **`user_profiles`** : source de vérité pour les données de profil ; `users` = identité auth uniquement (migration en lecture terminée §27)
- **RLS** : permissif (`USING (true)`) partout — à durcir avant production
- **Migrations SQL** : toujours les tester d'abord sur un profil de test avant exécution en prod

---

*Document consolidé à partir de specs_petsmatch.md (46 sections, 6351 lignes) et SPECS_PETSMATCH.md (12 sections, 1828 lignes).*
*Mettre à jour après chaque session de développement.*
