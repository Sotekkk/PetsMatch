# PetsMatch — Spec : Écosystème Animaux Perdus / Trouvés

> Spec complète. Fichier de référence pour les deux dépôts (app Flutter + web Next.js).
> Règle absolue : toute feature se déploie sur les **deux versions** avec design identique.

---

## Vue d'ensemble

Créer un écosystème complet permettant :
- Déclarer un animal perdu ✅ (V1 fait)
- Déclarer un animal trouvé 🔲 (à faire)
- Recherche croisée automatique perdu ↔ trouvé 🔲
- Identification via puce électronique 🔲
- Mise en relation automatisée 🔲
- Notifications utilisateurs proches ✅ (fait pour perdus)
- Bouton global "J'ai trouvé un animal" accessible partout 🔲

---

## A. Déclarer un animal perdu ✅ — À vérifier / compléter

> Implémenté dans `alerte_perdu_form_page.dart` (app) + `animaux-perdus/declarer/page.tsx` (web).
> Vérifier qu'aucun champ obligatoire ne manque.

### Champs obligatoires
- Nom animal (manuel OU sélection depuis mes animaux)
- Espèce
- Race
- Sexe
- Date disparition
- Date dernière localisation
- Identification (numéro puce / tatouage)
- Ville (minimum obligatoire)
- Code postal (auto-complété depuis Google Places)
- Pays
- Région
- Contact : email + téléphone + messagerie PetsMatch

### Préremplissage depuis fiche animal
Depuis "Déclarer perdu" dans la fiche animal : nom, espèce, race, sexe, photo, numéro puce, contact urgence.

### Statuts
| Statut | Description |
|---|---|
| `perdu` | Déclaration initiale |
| `aperçu` | Signalement d'observation |
| `retrouvé` | Animal retrouvé |
| `cloture` | Alerte fermée manuellement |

### Données supplémentaires
- Circonstances de disparition
- Récompense (optionnel)
- Description physique
- Dernière position GPS

### Table BDD : `alertes_perdus`
```sql
id, uid_proprietaire, nom_animal, espece, race, sexe,
date_disparition, date_derniere_localisation,
identification (puce/tatouage), photo_url,
ville, code_postal, pays, region, lat, lng,
circonstances, recompense, description,
statut (perdu/apercu/retrouve/cloture),
contact_email, contact_telephone, contact_messagerie (bool),
created_at, updated_at
```

---

## B. Déclarer un animal trouvé 🔲 — NOUVEAU

> Permettre à particuliers, refuges, vétérinaires, éleveurs et associations de déclarer rapidement un animal trouvé.

### Fichiers à créer
- App : `lib/pages/particulier/animal_trouve_form_page.dart`
- Web : `src/app/animaux-perdus/declarer-trouve/page.tsx`
- Liste : intégrer dans `animaux_perdus_page.dart` + `animaux-perdus/page.tsx` (onglet "Trouvés")

### Champs obligatoires
- Espèce
- Race estimée
- Sexe estimé
- Date découverte
- Localisation découverte (Google Places → lat/lng)
- Photo minimum 1
- Contact (email OU téléphone OU messagerie PetsMatch)

### Champs optionnels
- Nom supposé (collier/médaille)
- Couleur
- Taille estimée
- État de santé
- Collier / médaille (description)
- Comportement (docile, craintif, agressif…)

### Statuts
| Statut | Description |
|---|---|
| `trouve` | Déclaration initiale |
| `pris_en_charge` | Hébergé / à la fourrière |
| `proprietaire_contacte` | Contact établi |
| `restitue` | Rendu au propriétaire |
| `cloture` | Clôturé sans suite |

### Table BDD : `animaux_trouves` (nouvelle table à créer)
```sql
CREATE TABLE animaux_trouves (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid_declarant    TEXT REFERENCES users(uid) ON DELETE SET NULL,
  espece           TEXT NOT NULL,
  race             TEXT,
  sexe             TEXT,
  nom_suppose      TEXT,
  couleur          TEXT,
  taille           TEXT,
  etat_sante       TEXT,
  collier          TEXT,
  comportement     TEXT,
  date_decouverte  DATE NOT NULL,
  ville            TEXT,
  code_postal      TEXT,
  pays             TEXT DEFAULT 'France',
  region           TEXT,
  lat              FLOAT8,
  lng              FLOAT8,
  photo_urls       TEXT[],
  contact_email    TEXT,
  contact_telephone TEXT,
  contact_messagerie BOOLEAN DEFAULT true,
  statut           TEXT DEFAULT 'trouve',
  created_at       TIMESTAMPTZ DEFAULT NOW(),
  updated_at       TIMESTAMPTZ DEFAULT NOW()
);
```

### UX — Bouton global "J'ai trouvé un animal"
- Visible dans le **menu (drawer)** éleveur + particulier + accueil
- Bouton flottant ou en haut de l'écran accueil (action urgente)
- Couleur : vert `#6E9E57` avec icône `Icons.pets` ou `Icons.search`
- Web : lien dans Header + bannière d'accueil

---

## C. Carte animaux perdus / trouvés 🔲 — Extension de la carte existante

> Étendre la carte actuelle `animaux_perdus_page.dart` / `animaux-perdus/page.tsx`.

### Filtres supplémentaires
- **Type** : Perdu / Trouvé (actuellement : Perdu uniquement)
- Espèce
- Race
- Pays / Région / Ville
- Distance (10 km, 20 km, 50 km, 100 km)

### Code couleur des marqueurs
| Couleur | Signification |
|---|---|
| 🔴 Rouge | Animal perdu |
| 🟢 Vert | Animal trouvé |
| 🟠 Orange | Aperçu |
| 🔵 Bleu | Retrouvé (archivé) |

---

## D. Recherche croisée automatique perdu ↔ trouvé 🔲

> Algorithme de matching automatique entre `alertes_perdus` et `animaux_trouves`.

### Critères de comparaison
| Critère | Poids |
|---|---|
| Espèce identique | Obligatoire (0 si différent) |
| Race identique | +30 pts |
| Sexe identique | +20 pts |
| Zone géographique ≤ 50 km | +20 pts |
| Dates compatibles (trouvé ≥ perdu) | +15 pts |
| Couleur similaire | +10 pts |
| Puce identique | +100 pts (match certain) |

### Score de correspondance
- **≥ 90%** → Notification automatique push + in-app :
  *"Un animal trouvé pourrait correspondre à votre alerte"*
- **70–89%** → Suggestion dans l'interface
- **< 70%** → Pas de notification

### Déclenchement
- À chaque nouvelle alerte perdu → chercher dans `animaux_trouves` des 30 derniers jours
- À chaque nouvelle déclaration trouvé → chercher dans `alertes_perdus` actives
- Implémentation : Firebase Cloud Function `matchLostFound` (appelable) OU trigger Supabase (pg_cron / webhook)

### Table de correspondances (optionnel V2)
```sql
CREATE TABLE alertes_correspondances (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  alerte_id      UUID REFERENCES alertes_perdus(id) ON DELETE CASCADE,
  trouve_id      UUID REFERENCES animaux_trouves(id) ON DELETE CASCADE,
  score          INT,
  notifie        BOOLEAN DEFAULT false,
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(alerte_id, trouve_id)
);
```

---

## E. Identification par puce électronique 🔲

### Périmètre — 3 usages couverts par le même service

| Usage | Contexte | Résultat attendu |
|---|---|---|
| **Gestion élevage** | Éleveur dans son élevage | Ouvre directement la fiche de l'animal (`animal_fiche.dart`) |
| **Animal trouvé** | Particulier / vétérinaire / refuge | Ouvre fiche OU alerte perdue liée |
| **Animal inconnu** | Puce non reconnue | Propose créer fiche / déclarer trouvé / déclarer perdu |

> **Cas d'usage élevage (prioritaire)** : l'éleveur scanne la puce d'un de ses animaux pendant ses soins
> (vaccination, pesée, contrôle) → la fiche de l'animal s'ouvre immédiatement sans navigation manuelle.
> C'est le cas d'usage quotidien le plus fréquent.

### V1 — Saisie manuelle
- Champ "Numéro de puce" dans le formulaire animal trouvé
- Bouton "Rechercher par puce" dans la page animaux perdus/trouvés ET dans "Mes animaux"
- Recherche dans `animaux.identification` (élevage) + `alertes_perdus.identification` + `animaux_trouves`

### V2 — Lecteur Bluetooth externe
**Protocoles supportés :** Bluetooth HID, BLE, ISO11784, ISO11785, FDX-B

**Compatibilité :** Android, iOS (web si possible via Web Bluetooth API)

**Service Flutter à créer : `ChipScannerService`**
```dart
class ChipScannerService {
  Future<void> connect();        // Connexion lecteur BLE
  Future<void> disconnect();
  Stream<String> listen();       // Stream numéros de puce lus
  String parseChip(String raw);  // Normalisation format (FDX-B → 15 chiffres)
  Future<ChipSearchResult> searchAnimal(String chipNumber); // Recherche multi-table
}

class ChipSearchResult {
  final AnimalFicheResult? ownAnimal;     // Animal de l'éleveur (priorité 1)
  final AlertePerduResult? alertePerdue; // Alerte active associée (priorité 2)
  final AnimalTrouveResult? trouve;      // Déclaration "trouvé" existante
  // Si null → animal inconnu
}
```

**Workflow UX :**
1. Bouton "Scanner une puce" (lecteur BT) ou "Saisir une puce" (manuel)
2. Connexion lecteur → lecture → numéro affiché
3. Recherche automatique dans `animaux` (élevage), `alertes_perdus`, `animaux_trouves`

**Résultats possibles :**
- ✅ **Animal de l'éleveur** → ouvre directement `AnimalFichePage` (fiche complète)
- ✅ **Alerte perdue connue** → ouvre la fiche d'alerte + propose de contacter le propriétaire
- ✅ **Déclaration "trouvé" existante** → affiche la déclaration + propose de matcher
- ❓ **Inconnu** → propose : créer fiche animal / déclarer trouvé / déclarer perdu

**Point d'entrée UX :**
- Icône "scanner" dans la barre de recherche de "Mes animaux" (éleveur)
- Bouton flottant dans la page animaux perdus/trouvés
- Accessible depuis le menu principal (drawer)

---

## F. Notifications 🔲 — Extension

### Nouveaux types de notifications
| Type | Déclencheur |
|---|---|
| `animal_trouve_proximite` | Nouveau trouvé < 10 km d'une alerte active |
| `matching_perdu_trouve` | Score correspondance ≥ 90% |
| `scan_puce_succes` | Puce identifiée |
| `animal_retrouve` | Statut alerte → "retrouvé" |
| `contact_recu` | Message reçu via messagerie intégrée |

### Rayon de notification
- Animaux perdus : 20 km (existant)
- Animaux trouvés : 10 km depuis l'alerte perdue correspondante

### Synchronisation
- Android ✅ (push FCM via Firebase Cloud Functions)
- iOS (à tester)
- Web : notification navigateur (Web Push / FCM web token)
- Cloche in-app obligatoire partout

---

## G. Messagerie intégrée perdu / trouvé 🔲

> Créer automatiquement une conversation PetsMatch lors d'un matching ou d'un contact manuel.

### Objet automatique
```
Animal trouvé correspondant potentiellement à votre alerte
```

### Message prérempli
```
Bonjour,

J'ai trouvé un animal pouvant correspondre à votre alerte PetsMatch.
Pouvez-vous me contacter pour que nous puissions vérifier s'il s'agit bien de votre animal ?

Cordialement
```

### Implémentation
- Créer une conversation Firestore `conversations` (existant) avec `type: 'alerte_perdu'` ou `type: 'animal_trouve'`
- Lien vers l'alerte / la déclaration dans les métadonnées de conversation

---

## H. Sécurité / anti-spam 🔲

- **Limite** : max 3 alertes actives simultanées par utilisateur
- **Détection doublons** : même espèce + race + ville + créateur dans les 24h → bloquer
- **Captcha** : sur la création d'alerte pour les comptes < 7 jours
- **Modération admin** : file de signalement si description suspecte (mots-clés)
- **Validation** : photo obligatoire pour les animaux trouvés

---

## I. Historique / Statistiques 🔲 (V3)

Prévoir dans l'interface admin :
- Nombre d'animaux retrouvés (total + par mois)
- Délai moyen de résolution
- Zones géographiques fréquentes de disparition (heatmap)
- Taux de résolution (retrouvés / perdus déclarés)
- Top espèces perdues

---

## Priorités de développement

### V1 (prioritaire)
- [ ] Déclarer animal trouvé (formulaire + carte + filtres)
- [ ] Bouton global "J'ai trouvé un animal" (menu + accueil)
- [ ] Intégration carte : onglet Perdu / Trouvé + code couleur
- [ ] Saisie manuelle numéro puce → recherche
- [ ] Notifications de proximité pour les trouvés
- [ ] Messagerie automatique perdu/trouvé
- [ ] Vérifier complétude du formulaire "Perdu" existant

### V2
- [ ] Lecteur Bluetooth (`ChipScannerService`)
- [ ] Matching intelligent avec score
- [ ] Notifications de correspondance automatiques

### V3
- [ ] IA rapprochement photos (vision par ordinateur)
- [ ] Détection automatique correspondances en temps réel
- [ ] Partenariats vétérinaires / refuges (accès étendu)
- [ ] Statistiques et heatmaps admin
