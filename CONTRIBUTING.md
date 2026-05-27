# Guide de contribution — PetsMatch

> Conventions Git et règles de collaboration pour éviter les conflits.

---

## 1. Workflow Git

### Branches

```
main          ← branche stable, ne jamais pousser directement
dev           ← intégration commune, merge fréquent depuis les feature branches
feat/xxx      ← nouvelle fonctionnalité
fix/xxx       ← correction de bug
refactor/xxx  ← refactoring sans changement fonctionnel
```

**Règle :** on ne push jamais directement sur `main`. Toujours passer par `dev` ou une PR.

### Cycle de travail

```
1. git checkout dev && git pull origin dev     # se synchroniser
2. git checkout -b feat/ma-feature             # créer sa branche
3. ... développement ...
4. git push origin feat/ma-feature
5. Ouvrir une PR vers dev
6. L'autre personne relit rapidement avant merge
7. Merge dans dev → tester ensemble
8. Merge dev → main pour une release
```

---

## 2. Convention des messages de commit

Format : `type(scope): description courte en français`

### Types

| Type | Usage |
|---|---|
| `feat` | Nouvelle fonctionnalité |
| `fix` | Correction de bug |
| `refactor` | Refactoring (pas de changement comportemental) |
| `style` | Changement visuel / CSS / couleurs |
| `docs` | Documentation uniquement |
| `chore` | Config, dépendances, pubspec, package.json |
| `wip` | Travail en cours (commit intermédiaire, ne pas merger) |

### Scopes

| Scope | Correspond à |
|---|---|
| `app` | Flutter — générique |
| `web` | Next.js — générique |
| `app/animaux` | Pages animaux Flutter |
| `app/annonces` | Pages annonces Flutter |
| `app/admin` | Panel admin Flutter |
| `app/eleveur` | Espace éleveur Flutter |
| `web/animaux` | Pages mes-animaux Next.js |
| `web/annonces` | Pages annonces Next.js |
| `web/elevage` | Espace éleveur Next.js |
| `supabase` | Edge functions / schema SQL |
| `auth` | Authentification |

### Exemples

```
feat(app/animaux): ajout type_poil et poids dans portée
fix(web/annonces): correction affichage filtre espèce
refactor(app/admin): remplacement setState dans StatelessWidget
style(web): harmonisation couleurs chips filtres
chore(app): mise à jour image_cropper 9.1.0 → 12.0.0
feat(supabase): edge function delete-user avec cascade
```

### Corps du commit (optionnel mais recommandé pour les features)

```
feat(app/animaux): ajout section pedigree dans fiche animal

- Chip par espèce (LOF/LOOF/Stud-book selon espèce)
- Upload document pedigree vers Firebase Storage
- Champ importation_ref affiché si provenance = importation

Web: même feature dans mes-animaux/[id]/page.tsx
```

---

## 3. Éviter les conflits de fichiers

### Règle principale

**Avant de toucher un fichier, le déclarer dans `TASKS.md`** en mettant son prénom dans la colonne "Assigné" et le statut "en cours".

### Fichiers à risque élevé (souvent modifiés)

**Flutter :**
- `lib/pages/eleveur/animaux/animal_fiche.dart` — fiche animal complète
- `lib/pages/eleveur/animaux/portee_form_page.dart` — formulaire portée
- `lib/main.dart` — init app
- `lib/utils.dart` — fonctions partagées

**Web :**
- `src/app/mes-animaux/[id]/page.tsx` — fiche animal web
- `src/app/mes-animaux/portee/page.tsx` — portée web
- `src/lib/auth-context.tsx` — contexte auth partagé
- `src/components/Header.tsx` — navigation

### Si conflit de merge

1. Ne jamais faire `git checkout -- fichier` (perte de travail)
2. Ouvrir les deux versions côte à côte et fusionner manuellement
3. Chercher les marqueurs `<<<<<<`, `======`, `>>>>>>` et résoudre section par section
4. Tester après résolution avant de committer

---

## 4. Ce qu'il faut préciser dans le message de push/PR

Quand tu pousses une branche et que l'autre doit le savoir, le message de PR doit répondre à :

```
## Ce qui a changé
- [liste des fichiers modifiés avec une ligne d'explication]

## Ce que l'autre doit faire
- [ ] Rien (indépendant)
- [ ] Merger dev avant de continuer (si fichiers partagés)
- [ ] Mettre à jour la base de données (si nouveau champ Supabase)
- [ ] Redéployer l'Edge Function (si modif supabase/functions/)
- [ ] Mettre à jour les dépendances (flutter pub get / npm install)

## Points d'attention
- [effets de bord possibles, pages à retester]
```

### Cas particuliers à toujours signaler

| Modification | Action requise par l'autre |
|---|---|
| Nouveau champ dans `schema.sql` | Exécuter le `ALTER TABLE` dans Supabase |
| Nouvelle Edge Function | Déployer via dashboard Supabase |
| Nouveau package Flutter | `flutter pub get` |
| Nouveau package npm | `npm install` |
| Modification `auth-context.tsx` | Tester toutes les pages qui utilisent `useAuth()` |
| Modification `utils.dart` | Vérifier les pages qui l'importent |
| Nouvelle couleur / constante globale | L'ajouter aussi dans l'autre repo |

---

## 5. Branches courantes — ne pas supprimer

```
main    ← ne jamais supprimer
dev     ← ne jamais supprimer
```

Supprimer les branches `feat/` une fois mergées.

---

## 6. Checklist avant de push

- [ ] `flutter analyze` sans erreur (app)
- [ ] `npm run build` sans erreur (web)
- [ ] Photos uploadées bien en carré (crop activé)
- [ ] Testé sur les deux versions si feature commune
- [ ] TASKS.md mis à jour (statut → terminé)
- [ ] Aucun fichier `.env.local` ou clé secrète dans le commit
