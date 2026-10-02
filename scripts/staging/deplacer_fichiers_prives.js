// Stockage phase 2b lot 2 : déplace les anciens fichiers sensibles restés
// dans des buckets PUBLICS vers le bucket privé `documents`, puis réécrit
// en base les liens qui les référencent.
//   media/profiles/<uid>/…kbis… / …acaced…   (KBIS, ACACED de l'appli)
//   media/chat_images/…                       (images de la messagerie)
//   media/pension_updates/…, visite_rapports/ (photos / vidéos de pension)
//   petsmatch/documents/…                     (KBIS / ACACED / documents asso du site)
//   promenades-photos/<id>/…  → documents/promenades/<id>/…
//
// Usage (Git Bash, racine du dépôt) :
//   node scripts/staging/deplacer_fichiers_prives.js staging            (simulation)
//   node scripts/staging/deplacer_fichiers_prives.js staging --appliquer
//   node scripts/staging/deplacer_fichiers_prives.js prod --appliquer
// Clés lues dans %USERPROFILE%\petsmatch-db.env : <ENV>_DB_URL et
// <ENV>_SECRET_KEY (clé secrète / service_role du projet).
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const ENV = (process.argv[2] || '').toLowerCase();
const APPLIQUER = process.argv.includes('--appliquer');
const PROJETS = { staging: 'https://ozftswznayxzrbcfmher.supabase.co', prod: 'https://zyvpngcvzrkdytypjlyq.supabase.co' };
if (!PROJETS[ENV]) { console.error('Usage : node deplacer_fichiers_prives.js staging|prod [--appliquer]'); process.exit(1); }

const HOME = process.env.USERPROFILE || process.env.HOME;
const conf = Object.fromEntries(fs.readFileSync(path.join(HOME, 'petsmatch-db.env'), 'utf8')
  .split(/\r?\n/).map((l) => l.match(/^([A-Z_]+)=(.*)$/)).filter(Boolean).map((m) => [m[1], m[2]]));
const DB = conf[`${ENV.toUpperCase()}_DB_URL`];
const CLE = process.env[`${ENV.toUpperCase()}_SECRET_KEY`] || conf[`${ENV.toUpperCase()}_SECRET_KEY`];
if (!DB) { console.error(`${ENV.toUpperCase()}_DB_URL absent de petsmatch-db.env`); process.exit(1); }
if (APPLIQUER && !CLE) { console.error(`${ENV.toUpperCase()}_SECRET_KEY absent (petsmatch-db.env ou variable d'environnement)`); process.exit(1); }
const URL = PROJETS[ENV];
const PSQL = 'C:/Program Files/PostgreSQL/17/bin/psql.exe';
const psql = (sql) => execFileSync(PSQL, [DB, '-At', '-F', '\t', '-v', 'ON_ERROR_STOP=1', '-c', sql],
  { encoding: 'utf8', env: { ...process.env, PGCLIENTENCODING: 'UTF8' } });

const SELECTION = `
  SELECT bucket_id, name FROM storage.objects
  WHERE (bucket_id = 'media' AND (name ~ '^profiles/[^/]+/([a-z_0-9]*_)?(kbis|acaced)'
                                 OR name ~ '^(chat_images|pension_updates|visite_rapports)/'))
     OR (bucket_id = 'petsmatch' AND name ~ '^documents/')
     OR bucket_id = 'promenades-photos'
  ORDER BY bucket_id, name`;
const cible = (bucket, name) => (bucket === 'promenades-photos' ? `promenades/${name}` : name);

// Colonnes qui peuvent contenir ces liens.
const COLONNES = [
  ['user_profiles', ['kbis_url', 'acaced_doc_url', 'diplome_url', 'statuts_url', 'arrete_prefectoral_url']],
  ['users', ['kbis_url', 'acaced_doc_url', 'document_elevage']],
  ['messages', ['image_url']],
  ['promenades_messages', ['image_url']],
  ['pension_updates', ['photo_url', 'video_url']],
];

(async () => {
  // psql sous Windows : fins de ligne CRLF → \r à retirer des noms.
  const fichiers = psql(SELECTION).split(/\r?\n/).map((l) => l.trim()).filter(Boolean).map((l) => l.split('\t'));
  console.log(`${ENV} : ${fichiers.length} fichier(s) à déplacer${APPLIQUER ? '' : ' (simulation)'}`);
  const deplaces = [];
  for (const [bucket, name] of fichiers) {
    const dest = cible(bucket, name);
    if (!APPLIQUER) { console.log(`  ${bucket}/${name} → documents/${dest}`); continue; }
    const r = await fetch(`${URL}/storage/v1/object/move`, {
      method: 'POST',
      headers: { apikey: CLE, Authorization: `Bearer ${CLE}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ bucketId: bucket, sourceKey: name, destinationBucket: 'documents', destinationKey: dest }),
    });
    if (r.ok) deplaces.push([bucket, name, dest]);
    console.log(`  ${r.ok ? 'OK ' : 'KO '} ${bucket}/${name}${r.ok ? '' : ' → ' + r.status + ' ' + (await r.text()).slice(0, 120)}`);
  }
  if (!APPLIQUER) return;

  // Réécriture des liens : pour chaque fichier PRÉSENT dans `documents`
  // (déplacé maintenant ou lors d'un passage précédent), les liens qui
  // pointent encore vers son ancien bucket public sont corrigés.
  // Idempotent : peut être relancé sans risque.
  const ancien = `CASE WHEN o.name LIKE 'promenades/%'
                     THEN '/object/public/promenades-photos/' || substr(o.name, 12)
                   WHEN o.name LIKE 'documents/%' THEN '/object/public/petsmatch/' || o.name
                   ELSE '/object/public/media/' || o.name END`;
  const maj = COLONNES.flatMap(([t, cols]) => cols.map((c) => `
    UPDATE public.${t} x SET ${c} = replace(x.${c}, a.ancien, a.nouveau)
    FROM (SELECT ${ancien} AS ancien, '/object/public/documents/' || o.name AS nouveau
          FROM storage.objects o
          WHERE o.bucket_id = 'documents'
            AND (o.name ~ '^profiles/[^/]+/([a-z_0-9]*_)?(kbis|acaced)'
                 OR o.name ~ '^(chat_images|pension_updates|visite_rapports|promenades|documents)/')) a
    WHERE x.${c} LIKE '%' || a.ancien || '%';`)).join('\n');
  const sortie = execFileSync(PSQL, [DB, '-At', '-v', 'ON_ERROR_STOP=1', '-f', '-'],
    { input: `BEGIN;\n${maj}\nCOMMIT;\n`, encoding: 'utf8', env: { ...process.env, PGCLIENTENCODING: 'UTF8' } });
  const nb = (sortie.match(/UPDATE (\d+)/g) || []).reduce((n, l) => n + Number(l.split(' ')[1]), 0);
  console.log(`Liens réécrits en base : ${nb} (sur ${deplaces.length} fichier(s) déplacé(s) à ce passage)`);
})().catch((e) => { console.error(e.message); process.exit(1); });
