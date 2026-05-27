# Guide de contribution — PetsMatch Web

> Voir aussi : `C:\dev\PetsMatch\CONTRIBUTING.md` (règles communes app + web)
> Voir aussi : `C:\dev\PetsMatch\SPEC.md` (spécifications complètes du projet)
> Voir aussi : `C:\dev\PetsMatch\TASKS.md` (tâches en cours)

---

Ce repo (`petsmatch-web`) suit exactement les mêmes conventions Git que le repo Flutter.
Référez-vous aux fichiers listés ci-dessus pour :
- Les conventions de commit
- Le workflow de branches
- La règle de déclaration des fichiers en cours
- La checklist avant push

## Checklist spécifique web avant push

- [ ] `npm run build` sans erreur TypeScript
- [ ] Testé dans Chrome (desktop + mobile viewport)
- [ ] Photos uploadées bien en carré (ImageCropModal utilisé)
- [ ] `useAuth()` utilisé correctement (pas d'accès direct à Firebase sans passer par le contexte)
- [ ] Aucune clé secrète dans le code (utiliser `.env.local`)
- [ ] TASKS.md dans le repo Flutter mis à jour
