# Recompresse EN PLACE les images lourdes déjà stockées (même chemin → même
# URL, aucune ligne de la base à modifier). Les originaux trop lourds (photos
# de profil / galerie de 6 à 8 Mo envoyées brutes par le site) étaient
# retéléchargés en entier à chaque affichage (dépassement « Cached Egress »).
#
#   python scripts/recompresser_images_stockage.py              → simulation (rien n'est modifié)
#   python scripts/recompresser_images_stockage.py --appliquer  → remplace les fichiers
#
# Réglages : images > 800 Ko des buckets publics et documents, réduites à
# 1600 px (2000 px pour documents), JPEG qualité 80 (PNG transparent gardé en
# PNG). Jamais : galeries / livraisons (originaux des photographes),
# story_music. Remplacée seulement si le gain dépasse 30 %. Clé service lue
# dans website/.env.local. Nécessite Pillow.
import io
import json
import re
import sys
import urllib.parse
import urllib.request
from pathlib import Path

from PIL import Image, ImageOps

APPLIQUER = '--appliquer' in sys.argv
BUCKETS = ['media', 'petsmatch', 'social', 'stories', 'documents']
SEUIL = 800 * 1024

env = {}
for l in (Path(__file__).resolve().parent.parent / 'website' / '.env.local').read_text(encoding='utf-8').splitlines():
    m = re.match(r'^([A-Z0-9_]+)=(.*)$', l)
    if m and m[1] not in env:
        env[m[1]] = m[2].strip('"')
URL = env['NEXT_PUBLIC_SUPABASE_URL']
KEY = env.get('SUPABASE_SERVICE_ROLE_KEY') or env['SUPABASE_SECRET_KEY']
H = {'apikey': KEY, 'Authorization': 'Bearer ' + KEY}


def requete(url, data=None, method=None, headers=None):
    req = urllib.request.Request(url, data=data, method=method, headers={**H, **(headers or {})})
    with urllib.request.urlopen(req) as r:
        return r.read()


def lister(bucket, prefix, out):
    offset = 0
    while True:
        corps = json.dumps({'prefix': prefix, 'limit': 1000, 'offset': offset}).encode()
        items = json.loads(requete(f'{URL}/storage/v1/object/list/{bucket}', corps, 'POST',
                                   {'Content-Type': 'application/json'}))
        for it in items:
            p = f'{prefix}/{it["name"]}' if prefix else it['name']
            if not it.get('metadata'):
                lister(bucket, p, out)
            else:
                out.append({'bucket': bucket, 'chemin': p, 'taille': it['metadata'].get('size') or 0,
                            'type': it['metadata'].get('mimetype') or ''})
        if len(items) < 1000:
            break
        offset += 1000


fichiers = []
for b in BUCKETS:
    lister(b, '', fichiers)
cibles = [f for f in fichiers if re.match(r'^image/(jpe?g|png|webp)$', f['type'], re.I)
          and f['taille'] > SEUIL and not f['chemin'].startswith('story_music/')]

avant = apres = n = 0
for f in cibles:
    chemin_url = urllib.parse.quote(f['chemin'])
    try:
        src = requete(f'{URL}/storage/v1/object/authenticated/{f["bucket"]}/{chemin_url}')
        img = ImageOps.exif_transpose(Image.open(io.BytesIO(src)))
        png = img.format == 'PNG' or (img.mode in ('RGBA', 'LA', 'P') and 'transparency' in img.info)
        png = png and img.mode in ('RGBA', 'LA', 'P')
        cote = 2000 if f['bucket'] == 'documents' else 1600
        img.thumbnail((cote, cote))
        buf = io.BytesIO()
        if png:
            img.save(buf, 'PNG', optimize=True)
        else:
            img.convert('RGB').save(buf, 'JPEG', quality=80, optimize=True, progressive=True)
        out = buf.getvalue()
    except Exception as e:
        print('  ignorée', f['bucket'], f['chemin'], e)
        continue
    if len(out) > len(src) * 0.7:
        continue
    avant += len(src); apres += len(out); n += 1
    print(f'  {len(src) / 1e6:5.1f} -> {len(out) / 1e6:5.2f} Mo  {f["bucket"]}/{f["chemin"]}')
    if APPLIQUER:
        try:
            requete(f'{URL}/storage/v1/object/{f["bucket"]}/{chemin_url}', out, 'PUT',
                    {'Content-Type': 'image/png' if png else 'image/jpeg', 'x-upsert': 'true'})
        except Exception as e:
            print('    ÉCHEC remplacement', e)

print(f'\n{n} images {"remplacées" if APPLIQUER else "à remplacer (simulation)"} : '
      f'{avant / 1e6:.1f} Mo -> {apres / 1e6:.1f} Mo')
