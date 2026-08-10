# Référentiel des zones anatomiques interactives — Ostéopathie

Ce document liste, par espèce, les zones cliquables canoniques du schéma
anatomique interactif (module ostéopathie). Chaque zone a un identifiant
stable (`zone_id`), un nom d'affichage, un groupe (utilisé pour la couleur
en mode "Anatomie"), et la liste des vues dans lesquelles elle doit être
cliquable.

Vues possibles : `face`, `profil_g`, `profil_d`, `arriere`, `ventrale`.

> La vue "Dorsale" (dessus) n'est pas une vue séparée : elle est couverte par
> la vue `arriere` (fichier combiné "arrière et dorsale"). Ne pas prévoir de
> visuel ni de zones dédiés à une vue `dorsale` distincte.

Zones bilatérales : suffixe `_g` (gauche) / `_d` (droit).
Zones médianes (colonne, tête, queue...) : pas de suffixe.

---

## Chien

| zone_id | Nom affiché | Groupe (couleur "Anatomie") | Vues |
|---|---|---|---|
| `crane` | Crâne | Crâne | face, profil_g, profil_d, arriere, dorsale |
| `atm_g` / `atm_d` | ATM gauche / droit | Crâne | face, profil_g\*, profil_d\*, ventrale |
| `machoire` | Mâchoire | Crâne | face, ventrale |
| `atlas_c1` | Atlas (C1) | Rachis cervical | face, profil_g, profil_d, arriere |
| `axis_c2` | Axis (C2) | Rachis cervical | face, profil_g, profil_d, arriere |
| `cervicales_c3_c7` | Cervicales (C3-C7) | Rachis cervical | face, profil_g, profil_d, arriere, ventrale |
| `epaule_g` / `_d` | Épaule | Épaule / Scapula | face, profil_g, profil_d, arriere, ventrale |
| `scapula_g` / `_d` | Scapula | Épaule / Scapula | face, profil_g, profil_d, arriere, ventrale |
| `humerus_g` / `_d` | Humérus | Membre thoracique | face, profil_g, profil_d, ventrale |
| `biceps_brachial_g` / `_d` | Biceps brachial | Membre thoracique | ventrale |
| `coude_g` / `_d` | Coude | Membre thoracique | face, profil_g, profil_d, ventrale |
| `radius_ulna_g` / `_d` | Radius / Ulna | Membre thoracique | face, profil_g, profil_d, ventrale |
| `carpe_g` / `_d` | Carpe | Membre thoracique | face, profil_g, profil_d, ventrale |
| `metacarpe_g` / `_d` | Métacarpe | Membre thoracique | face, profil_g, profil_d, ventrale |
| `doigts_avant_g` / `_d` | Doigts (avant) | Membre thoracique | face, profil_g, profil_d, ventrale |
| `cage_thoracique` | Cage thoracique / Côtes | Cage thoracique | face, profil_g, profil_d, ventrale |
| `sternum` | Sternum | Cage thoracique | face, ventrale |
| `thoraciques_t1_t13` | Thoraciques (T1-T13) | Rachis thoracique | profil_g, profil_d, arriere, ventrale |
| `abdomen` | Abdomen | Abdomen | face, profil_g, profil_d, ventrale |
| `diaphragme` | Diaphragme | Abdomen | ventrale |
| `nombril` | Nombril | Abdomen | ventrale |
| `lombaires_l1_l7` | Lombaires (L1-L7) | Rachis lombaire | profil_g, profil_d, arriere, ventrale |
| `sacrum` | Sacrum | Sacrum | profil_g, profil_d, arriere, ventrale |
| `bassin_g` / `_d` | Bassin | Bassin / Hanche | profil_g, profil_d, arriere, ventrale |
| `hanche_g` / `_d` | Hanche | Bassin / Hanche | profil_g, profil_d, arriere, ventrale |
| `femur_g` / `_d` | Fémur | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `grasset_g` / `_d` | Grasset (genou) | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `tibia_perone_g` / `_d` | Tibia / Péroné | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `jarret_g` / `_d` | Jarret (tarse) | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `metatarse_g` / `_d` | Métatarse | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `doigts_arriere_g` / `_d` | Doigts (arrière) | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `queue` | Queue | Queue | profil_g, profil_d, arriere |

\* En vue profil, seul l'ATM du côté visible est cliquable (l'autre est masqué par la tête).

### Décisions actées (2026-08-03)
- **Atlas (C1) / Axis (C2)** : séparés en 2 zones distinctes partout (mobilité atlanto-occipitale ≠ atlanto-axoïdienne).
- **Épaule / Scapula** : 2 points distincts (`epaule_g/d` et `scapula_g/d`), pas de fusion.
- **Vue dorsale** : pas de vue séparée, couverte par `arriere` (fichier combiné "arrière et dorsale").
- **Zones tissus mous en vue ventrale** : "Biceps brachial", "Diaphragme", "Nombril" sont conservées (enrichissement au-delà des zones strictement ostéo-articulaires de la spec d'origine), visibles uniquement en vue `ventrale`.

### Corrections restant à appliquer sur les visuels
- **Genou vs Rotule** : nommé "Genou" en vue arrière, "Rotule" en vue ventrale. Nom canonique retenu : **Grasset** (terme vétérinaire), avec "genou" en synonyme d'affichage si besoin de vulgariser.
- **Tarse vs Tarpe** : "Tarpe" est une coquille sur la vue profil gauche. Nom canonique : **Jarret (tarse)**.
- **Numérotation vertèbres thoraciques** : varie selon les vues (T1-T11 sur profil gauche, T1-T12 sur vue arrière, T1-T13 sur profil droit). Anatomiquement le chien a 13 vertèbres thoraciques (T1-T13) — à uniformiser sur **T1-T13** partout où le rachis thoracique est visible.
- **Zones crâniennes à enrichir** : le chat et le cheval ont des zones crâniennes fines en vue face/ventrale (région temporale, arc zygomatique, maxillaire, mandibule, symphyse mentonnière, os nasal) que le chien n'a pas encore (juste Crâne/ATM/Mâchoire). À ajouter sur les visuels du chien pour harmoniser le niveau de détail entre espèces.

---

## Décision transversale (2026-08-03)

Les membres sont **détaillés par articulation partout** (chien, chat, cheval),
pas regroupés en un seul point par patte. C'est déjà le cas sur les visuels
du chien ; il faudra ajouter les points manquants sur les visuels chat/cheval
(actuellement un seul point "Membre thoracique/pelvien" groupé) — voir la
section corrections plus bas.

## Chat

| zone_id | Nom affiché | Groupe (couleur "Anatomie") | Vues |
|---|---|---|---|
| `crane` | Crâne | Crâne | face, profil_g, profil_d, arriere, ventrale |
| `atm_g` / `atm_d` | ATM gauche / droite | ATM | face, profil_g\*, profil_d\*, ventrale |
| `region_temporale_g` / `_d` | Région temporale | Région temporale | face, ventrale |
| `arc_zygomatique_g` / `_d` | Arc zygomatique | Arc zygomatique | face, ventrale |
| `maxillaire_g` / `_d` | Maxillaire | Maxillaire | face, ventrale |
| `mandibule_g` / `_d` | Mandibule | Mandibule | face, ventrale |
| `symphyse_mentonniere` | Symphyse mentonnière | Symphyse mentonnière | face, ventrale |
| `os_nasal` | Os nasal | Os nasal | face, ventrale |
| `atlas_c1` | Atlas (C1) | Rachis cervical | face, profil_g, profil_d, arriere |
| `axis_c2` | Axis (C2) | Rachis cervical | face, profil_g, profil_d, arriere |
| `cervicales_c3_c7` | Cervicales (C3-C7) | Rachis cervical | face, profil_g, profil_d, arriere, ventrale |
| `epaule_g` / `_d` | Épaule | Épaule / Scapula | face, profil_g, profil_d, arriere, ventrale |
| `scapula_g` / `_d` | Scapula | Épaule / Scapula | face, profil_g, profil_d, arriere, ventrale |
| `humerus_g` / `_d` | Humérus | Membre thoracique | face, profil_g, profil_d, ventrale |
| `coude_g` / `_d` | Coude | Membre thoracique | face, profil_g, profil_d, ventrale |
| `radius_ulna_g` / `_d` | Radius / Ulna | Membre thoracique | face, profil_g, profil_d, ventrale |
| `carpe_g` / `_d` | Carpe | Membre thoracique | face, profil_g, profil_d, ventrale |
| `metacarpe_g` / `_d` | Métacarpe | Membre thoracique | face, profil_g, profil_d, ventrale |
| `doigts_avant_g` / `_d` | Doigts (avant) | Membre thoracique | face, profil_g, profil_d, ventrale |
| `cage_thoracique` | Cage thoracique / Côtes | Cage thoracique | face, profil_g, profil_d, ventrale |
| `sternum` | Sternum | Cage thoracique | face, ventrale |
| `thoraciques_t1_t13` | Thoraciques (T1-T13) | Rachis thoracique | profil_g, profil_d, arriere, ventrale |
| `abdomen` | Abdomen | Abdomen | face, profil_g, profil_d, ventrale |
| `lombaires_l1_l7` | Lombaires (L1-L7) | Rachis lombaire | profil_g, profil_d, arriere, ventrale |
| `sacrum` | Sacrum | Sacrum | profil_g, profil_d, arriere, ventrale |
| `bassin_g` / `_d` | Bassin | Bassin / Hanche | profil_g, profil_d, arriere, ventrale |
| `hanche_g` / `_d` | Hanche | Bassin / Hanche | profil_g, profil_d, arriere, ventrale |
| `femur_g` / `_d` | Fémur | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `grasset_g` / `_d` | Grasset | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `tibia_perone_g` / `_d` | Tibia / Péroné | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `jarret_g` / `_d` | Jarret (tarse) | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `metatarse_g` / `_d` | Métatarse | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `doigts_arriere_g` / `_d` | Doigts (arrière) | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `queue` | Queue | Queue | profil_g, profil_d, arriere |

\* En vue profil, seul l'ATM du côté visible est cliquable.

Bon point relevé sur les visuels actuels : le rachis thoracique (T1-T13) et
lombaire (L1-L7) sont déjà numérotés de façon cohérente sur toutes les vues
du chat — pas de correction nécessaire ici, contrairement au chien.

---

## Cheval

Particularités par rapport au chien/chat : "Encolure / Cervical" au lieu de
"Rachis cervical" (terminologie équestre usuelle), 18 vertèbres thoraciques
(T1-T18) et seulement 6 lombaires (L1-L6) — anatomiquement correct pour
l'espèce, et déjà cohérent sur toutes les vues générées (pas de correction
de numérotation nécessaire, contrairement au chien).

| zone_id | Nom affiché | Groupe (couleur "Anatomie") | Vues |
|---|---|---|---|
| `crane` | Crâne | Crâne | face, profil_g, profil_d, arriere, ventrale |
| `atm_g` / `atm_d` | ATM gauche / droite | ATM | face, profil_g\*, profil_d\*, ventrale |
| `region_temporale_g` / `_d` | Région temporale | Région temporale | face, ventrale |
| `arc_zygomatique_g` / `_d` | Arc zygomatique | Arc zygomatique | face, ventrale |
| `maxillaire_g` / `_d` | Maxillaire | Maxillaire | face, ventrale |
| `mandibule_g` / `_d` | Mandibule | Mandibule | face, ventrale |
| `symphyse_mentonniere` | Symphyse mentonnière | Symphyse mentonnière | face, ventrale |
| `os_nasal` | Os nasal | Os nasal | face, ventrale |
| `os_hyoide` | Os hyoïde | Tissus mous (gorge) | ventrale |
| `larynx_trachee` | Larynx / Trachée | Tissus mous (gorge) | ventrale |
| `atlas_c1` | Atlas (C1) | Encolure / Cervical | face, profil_g, profil_d, arriere |
| `axis_c2` | Axis (C2) | Encolure / Cervical | face, profil_g, profil_d, arriere |
| `cervicales_c3_c7` | Cervicales (C3-C7) | Encolure / Cervical | face, profil_g, profil_d, arriere, ventrale |
| `epaule_g` / `_d` | Épaule | Épaule / Scapula | face, profil_g, profil_d, arriere, ventrale |
| `scapula_g` / `_d` | Scapula | Épaule / Scapula | face, profil_g, profil_d, arriere, ventrale |
| `humerus_g` / `_d` | Humérus | Membre thoracique | face, profil_g, profil_d, ventrale |
| `coude_g` / `_d` | Coude | Membre thoracique | face, profil_g, profil_d, ventrale |
| `radius_ulna_g` / `_d` | Radius / Ulna | Membre thoracique | face, profil_g, profil_d, ventrale |
| `carpe_g` / `_d` | Carpe | Membre thoracique | face, profil_g, profil_d, ventrale |
| `metacarpe_g` / `_d` | Métacarpe (canon) | Membre thoracique | face, profil_g, profil_d, ventrale |
| `doigts_avant_g` / `_d` | Doigt (avant / boulet-paturon-sabot) | Membre thoracique | face, profil_g, profil_d, ventrale |
| `cage_thoracique` | Cage thoracique / Côtes | Cage thoracique | face, profil_g, profil_d, ventrale |
| `sternum` | Sternum | Cage thoracique | face, ventrale |
| `thoraciques_t1_t18` | Thoraciques (T1-T18) | Rachis thoracique | profil_g, profil_d, arriere, ventrale |
| `abdomen` | Abdomen | Abdomen | face, profil_g, profil_d, ventrale |
| `lombaires_l1_l6` | Lombaires (L1-L6) | Rachis lombaire | profil_g, profil_d, arriere, ventrale |
| `sacrum` | Sacrum | Sacrum | profil_g, profil_d, arriere, ventrale |
| `bassin_g` / `_d` | Bassin | Bassin / Hanche | profil_g, profil_d, arriere, ventrale |
| `hanche_g` / `_d` | Hanche | Bassin / Hanche | profil_g, profil_d, arriere, ventrale |
| `femur_g` / `_d` | Fémur | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `grasset_g` / `_d` | Grasset | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `tibia_perone_g` / `_d` | Tibia / Péroné | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `jarret_g` / `_d` | Jarret (tarse) | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `metatarse_g` / `_d` | Métatarse (canon) | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `doigts_arriere_g` / `_d` | Doigt (arrière / boulet-paturon-sabot) | Membre pelvien | profil_g, profil_d, arriere, ventrale |
| `queue` | Queue | Queue | profil_g, profil_d, arriere |

\* En vue profil, seul l'ATM du côté visible est cliquable.

`os_hyoide` et `larynx_trachee` sont spécifiques au cheval sur les visuels
actuels (pertinents pour l'évaluation de la sangle thoraco-cervicale et du
poll chez le cheval) — à garder tel quel ou à valider si on veut un
équivalent chez le chien/chat pour cohérence totale des zones "tissus mous".

---

## Corrections à reporter sur les visuels (chat + cheval)

Ces écarts existent parce que les visuels actuels ont été générés avant les
décisions d'harmonisation ci-dessus :

1. **Membres regroupés → à détailler par articulation.** Chat et cheval
   n'ont aujourd'hui qu'un seul point "Membre thoracique/pelvien" par patte ;
   il faut faire apparaître un point cliquable par articulation (épaule,
   scapula, humérus, coude, radius/ulna, carpe, métacarpe, doigts — et
   l'équivalent au postérieur), comme sur les visuels du chien.
2. **Épaule / Scapula fusionnés → à séparer en 2 points**, comme décidé
   pour le chien.
3. **Atlas / Axis non distingués → à séparer en 2 points** (actuellement
   noyés dans "Rachis cervical (C1 à C7)" sans point dédié C1/C2 sur
   chat et cheval).
4. **Sternum fusionné dans "Cage thoracique"** sur chat/cheval (la légende
   dit "Côtes et sternum") → à séparer en 2 zones distinctes comme pour
   le chien.

## Prompt de génération (ChatGPT / DALL-E)

Style demandé : planche d'atlas anatomique vétérinaire ("encyclopédie
médicale"), pas l'illustration peinte/réaliste actuelle. Pour chaque
image à régénérer : prendre la ligne du tableau ci-dessus correspondant à
l'espèce, filtrer les zones dont la colonne "Vues" contient la vue voulue,
et lister leurs noms affichés dans le prompt.

**Gabarit à réutiliser pour chaque vue :**

> Illustration médicale vétérinaire de style planche d'atlas anatomique
> (façon Gray's Anatomy vétérinaire / atlas d'anatomie comparée), vue
> **[VUE : de face / de profil gauche / de profil droit / arrière-dessus /
> ventrale]** d'un **[ESPÈCE]** adulte, en position debout neutre.
>
> Style graphique :
> - Line art précis et anatomiquement fidèle, traits de contour fins gris
>   foncé
> - Chaque zone anatomique remplie d'un aplat de couleur uni et distinct
>   (pas de dégradé, pas de rendu 3D/glossy, pas de photoréalisme, pas de
>   peinture picturale)
> - Ombrage discret réservé aux contours/reliefs, jamais à l'intérieur des
>   zones colorées
> - Fond d'une couleur unie et saturée, qui n'apparaît nulle part ailleurs
>   dans l'illustration : **vert vif (#00FF00) ou magenta pur (#FF00FF)**
>   ("fond vert" façon incrustation cinéma). Ne PAS demander un fond
>   "transparent" — les générateurs d'images ne savent pas produire de
>   vrai canal alpha, ils se contentent de peindre un damier gris/blanc en
>   pixels opaques, ce qui est inutilisable.
> - Cadrage et échelle identiques à ceux des autres vues de la même espèce,
>   pour permettre un alignement précis entre les vues
>
> Contraintes strictes :
> - AUCUN texte, AUCUNE étiquette, AUCUN chiffre, AUCUN logo, AUCUNE
>   interface, AUCUN point numéroté, AUCUNE ligne de rappel — uniquement
>   l'animal illustré avec ses zones anatomiques colorées
>
> Zones anatomiques à faire apparaître comme régions distinctes (chacune
> dans sa propre couleur) : **[LISTE DES ZONES DE CETTE VUE]**
>
> Haute résolution, exploitable comme asset pour une application mobile.

**Exemple rempli — Chien, vue profil gauche :**

> Illustration médicale vétérinaire de style planche d'atlas anatomique
> (façon Gray's Anatomy vétérinaire), vue de profil gauche d'un chien
> adulte de taille moyenne, en position debout neutre.
>
> Style graphique : line art précis et anatomiquement fidèle, traits de
> contour fins gris foncé. Chaque zone anatomique remplie d'un aplat de
> couleur uni et distinct (pas de dégradé, pas de rendu 3D/glossy, pas de
> photoréalisme). Ombrage discret réservé aux contours, jamais à
> l'intérieur des zones colorées. Fond d'un vert vif uni (#00FF00), sans
> aucun élément de cette couleur ailleurs dans l'image. Cadrage et échelle
> identiques aux autres vues du chien.
>
> Aucun texte, aucune étiquette, aucun chiffre, aucun logo, aucune
> interface, aucun point numéroté, aucune ligne de rappel — uniquement
> l'animal illustré avec ses zones colorées.
>
> Zones à faire apparaître comme régions distinctes : Crâne, ATM (côté
> gauche visible), Atlas (C1), Axis (C2), Cervicales (C3 à C7), Épaule,
> Scapula, Humérus, Coude, Radius/Ulna, Carpe, Métacarpe, Doigts (avant),
> Cage thoracique, Thoraciques (T1 à T13), Abdomen, Lombaires (L1 à L7),
> Sacrum, Bassin, Hanche, Fémur, Grasset, Tibia/Péroné, Jarret, Métatarse,
> Doigts (arrière), Queue.
>
> Haute résolution, exploitable comme asset pour une application mobile.

**Exemple rempli — Cheval, vue de face :**

> Illustration médicale vétérinaire de style planche d'atlas anatomique
> (façon Gray's Anatomy vétérinaire), vue de face d'un cheval adulte, en
> position debout neutre, tête droite.
>
> Style graphique : line art précis et anatomiquement fidèle, traits de
> contour fins gris foncé. Chaque zone anatomique remplie d'un aplat de
> couleur uni et distinct (pas de dégradé, pas de rendu 3D/glossy, pas de
> photoréalisme). Ombrage discret réservé aux contours, jamais à
> l'intérieur des zones colorées. Fond d'un vert vif uni (#00FF00), sans
> aucun élément de cette couleur ailleurs dans l'image. Cadrage et échelle
> identiques aux autres vues du cheval.
>
> Aucun texte, aucune étiquette, aucun chiffre, aucun logo, aucune
> interface, aucun point numéroté, aucune ligne de rappel — uniquement
> l'animal illustré avec ses zones colorées.
>
> Zones à faire apparaître comme régions distinctes : Crâne, ATM gauche,
> ATM droite, Région temporale gauche/droite, Arc zygomatique gauche/droite,
> Maxillaire gauche/droite, Mandibule gauche/droite, Symphyse mentonnière,
> Os nasal, Atlas (C1), Axis (C2), Cervicales (C3 à C7), Épaule gauche/droite,
> Scapula gauche/droite, Humérus gauche/droite, Coude gauche/droite,
> Radius/Ulna gauche/droite, Carpe gauche/droite, Métacarpe gauche/droite,
> Doigt avant gauche/droite, Cage thoracique, Sternum, Abdomen.
>
> Haute résolution, exploitable comme asset pour une application mobile.

**Conseil pratique** : génère une vue à la fois, en réutilisant l'image
précédente de la même espèce comme référence ("reprends la même pose, le
même style et la même échelle que l'image précédente, mais en vue de
profil droit") — ça aide ChatGPT à garder une cohérence entre les 5 vues
d'une même espèce, ce qui est le point le plus fragile avec ce type de
génération.

**Transparence — étape obligatoire après génération** : ChatGPT ne produit
jamais de vrai canal alpha, même en exportant en `.png` (vérifié : les
fichiers reçus sont en mode `RGB`, pas `RGBA` — le "fond transparent"
demandé est juste un damier gris/blanc peint en pixels opaques). Après
génération sur fond vert vif :
1. Ouvrir l'image dans un outil de suppression de fond (remove.bg,
   Photoroom, ou Photopea en gratuit/en ligne).
2. Supprimer le fond vert → exporter en PNG avec canal alpha réel.
3. Vérifier que le fichier final est bien en mode `RGBA` avant de l'ajouter
   à `assets/anatomie/`.

## Rongeurs, Oiseaux, autres espèces à venir

À compléter selon le même principe (membres détaillés par articulation,
zones crâniennes fines, atlas/axis séparés) une fois les visuels "propres"
disponibles. Les espèces plus petites (rongeurs, oiseaux) auront
probablement une structure squelettique différente (ex. pas de radius/ulna
distinct chez l'oiseau, aile ≠ patte) — le référentiel devra être adapté
zone par zone plutôt que copié tel quel.
