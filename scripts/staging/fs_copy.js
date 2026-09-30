// Copie Firestore prod (LECTURE seule) → staging (écriture), récursive.
// Retire les jetons push : le staging ne doit jamais notifier les vrais téléphones.
// Usage : node scripts/staging/fs_copy.js
// Nécessite les deux clés de compte de service (voir README) ; supprimer la
// clé prod dans la console une fois la copie faite.
const { admin, app } = require('./config');

const prod = app('prod').firestore();
const staging = app('staging').firestore();

const PUSH_FIELDS = ['fcmToken', 'fcmTokens', 'apnsToken', 'token_fcm'];
let docs = 0, stripped = 0;

// Les DocumentReference pointent vers la prod : on les rebascule vers le staging.
function remap(v) {
  if (v instanceof admin.firestore.DocumentReference) return staging.doc(v.path);
  if (Array.isArray(v)) return v.map(remap);
  if (v && typeof v === 'object' && v.constructor === Object) {
    const o = {};
    for (const [k, x] of Object.entries(v)) o[k] = remap(x);
    return o;
  }
  return v;
}

async function copyCollection(srcCol) {
  const snap = await srcCol.get();
  let batch = staging.batch(), n = 0;
  for (const d of snap.docs) {
    const data = remap(d.data());
    for (const f of PUSH_FIELDS) if (f in data) { delete data[f]; stripped++; }
    batch.set(staging.doc(d.ref.path), data);
    docs++;
    if (++n === 400) { await batch.commit(); batch = staging.batch(); n = 0; }
  }
  if (n) await batch.commit();
  for (const d of snap.docs) for (const sub of await d.ref.listCollections()) await copyCollection(sub);
}

(async () => {
  for (const c of await prod.listCollections()) {
    const before = docs;
    await copyCollection(c);
    console.log(`${c.id}: ${docs - before} documents (sous-collections comprises)`);
  }
  console.log(`TOTAL ${docs} documents, ${stripped} jetons push retirés`);
  process.exit(0);
})().catch((e) => { console.error('ERREUR', e.message); process.exit(1); });
