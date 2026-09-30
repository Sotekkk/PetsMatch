// Client HTTP minimal vers le Supabase STAGING, « en tant que » un uid Firebase
// (ou non connecté avec as(null)). Passe par les vraies API REST et Storage,
// donc teste exactement ce que voient l'appli et le site.
const { STAGING } = require('./config');
const { idToken } = require('./token');

async function as(uid) {
  const h = { apikey: STAGING.supabasePublishableKey };
  if (uid) h.Authorization = 'Bearer ' + (await idToken(uid));
  const call = async (method, p, body, extra = {}) => {
    const r = await fetch(STAGING.supabaseUrl + p, { method, headers: { ...h, ...extra }, body });
    return { status: r.status, body: await r.text() };
  };
  return {
    // GET REST : as(uid).rest('animaux?select=id&limit=5')
    rest: (p) => call('GET', '/rest/v1/' + p),
    // Écritures REST ; renvoient les lignes touchées (Prefer: return=representation).
    insert: (table, row) => call('POST', `/rest/v1/${table}`, JSON.stringify(row),
      { 'Content-Type': 'application/json', Prefer: 'return=representation' }),
    // Insertion SANS relecture (comme l'appli / le site pour une ligne destinée
    // à quelqu'un d'autre : une relecture exigerait le droit de la lire).
    insertMin: (table, row) => call('POST', `/rest/v1/${table}`, JSON.stringify(row),
      { 'Content-Type': 'application/json', Prefer: 'return=minimal' }),
    update: (p, patch) => call('PATCH', '/rest/v1/' + p, JSON.stringify(patch),
      { 'Content-Type': 'application/json', Prefer: 'return=representation' }),
    del: (p) => call('DELETE', '/rest/v1/' + p, undefined, { Prefer: 'return=representation' }),
    list: (bucket, prefix = '') => call('POST', `/storage/v1/object/list/${bucket}`,
      JSON.stringify({ prefix, limit: 100 }), { 'Content-Type': 'application/json' }),
    // media / petsmatch n'acceptent pas text/plain → faux JPEG.
    upload: (bucket, name, upsert = false, contentType) => call('POST', `/storage/v1/object/${bucket}/${name}`,
      Buffer.from('test'), {
        'Content-Type': contentType || (['media', 'petsmatch'].includes(bucket) ? 'image/jpeg'
          : bucket === 'contrats' ? 'text/html;charset=utf-8' : 'text/plain'),
        'x-upsert': String(upsert),
      }),
    remove: (bucket, names) => call('DELETE', `/storage/v1/object/${bucket}`,
      JSON.stringify({ prefixes: names }), { 'Content-Type': 'application/json' }),
  };
}
module.exports = { as };
