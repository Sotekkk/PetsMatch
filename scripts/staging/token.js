// Jeton d'identité Firebase STAGING « en tant que » n'importe quel uid,
// sans son mot de passe (custom token signé par le compte de service staging).
// Usage : node scripts/staging/token.js <uid>   → affiche les claims, jamais le jeton.
// Module : const { idToken } = require('./token'); await idToken(uid)
const { STAGING, app } = require('./config');

async function idToken(uid) {
  const custom = await app('staging').auth().createCustomToken(uid);
  const r = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${STAGING.firebaseWebApiKey}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ token: custom, returnSecureToken: true }),
    },
  );
  const j = await r.json();
  if (!j.idToken) throw new Error('Échange refusé : ' + JSON.stringify(j.error || j));
  return j.idToken;
}
module.exports = { idToken };

if (require.main === module) {
  idToken(process.argv[2]).then((t) => {
    const p = JSON.parse(Buffer.from(t.split('.')[1], 'base64url').toString());
    console.log(`OK sub=${p.sub} iss=${p.iss} exp=${new Date(p.exp * 1000).toISOString()}`);
    process.exit(0);
  }).catch((e) => { console.error(e.message); process.exit(1); });
}
