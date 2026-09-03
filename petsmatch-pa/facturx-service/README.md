# facturx-service

Micro-service **d'assemblage Factur-X** : prend un PDF lisible + le XML CII et
produit un **PDF/A-3** conforme, avec le XML embarqué sous le nom `factur-x.xml`
(relation `Data`), les métadonnées XMP `pdfaid` + l'extension Factur-X, et
l'`OutputIntent` sRGB.

Pourquoi Python : la librairie [`factur-x`](https://pypi.org/project/factur-x/)
(Akretion) est l'implémentation de référence et gère toute la plomberie PDF/A-3
(XMP, AF, OutputIntent, ID). Le reste de `petsmatch-pa` (normalisation,
validation, génération du XML CII) reste en Node/TS.

> Repli assumé du cahier des charges §12 (« repli possible sur un micro-service
> Python `factur-x` si la conformité PDF/A-3 se révèle trop coûteuse en Node »).

## API

`POST /facturx`  (multipart/form-data)

| champ | requis | description |
|---|---|---|
| `xml` | ✅ | fichier XML CII (profil EN 16931) |
| `pdf` | — | PDF lisible source ; si absent, un PDF minimal est rendu à partir du XML |
| `level` | — | `en16931` (défaut) \| `basic` \| `minimum` |

Réponse : `application/pdf` (le Factur-X), en-tête `X-Facturx-Level`.

`GET /health` → `{ "ok": true }`

## Lancer en local

```
cd petsmatch-pa/facturx-service
python -m venv .venv && . .venv/Scripts/activate   # (Windows) ou source .venv/bin/activate
pip install -r requirements.txt
python app.py            # écoute sur :8081
```

## Déploiement

Conteneur (`Dockerfile` fourni). ⚠️ pour la partie fiscale, hébergement **UE**
+ objectif **SecNumCloud** (cf. feuille de route décision B).
