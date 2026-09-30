// Tests RLS messagerie (conversations, messages, message_reactions) sur le
// STAGING, par rôle, via la vraie API REST.
// Usage : node scripts/staging/rls_messagerie_test.js
// Réf. : supabase/migration_rls_messagerie.sql
const { as } = require('./sb');

const NAT = 'YF9kR7jSTObnnw9lVj8gCl031rS2';    // Natacha
const CONV = 'c04e94e4-e46a-49d4-9983-e8adf669a72b'; // conversation directe de Natacha
const EMP = 'IfhRVwY55KUXW12lBG4D0bs0V383';    // employé de Natacha (pas participant)
const TIERS = 'G59EC6CC61OUFQdVPMmw8e9Gp8v2';  // compte asso, non admin, pas participant
const ADMIN = 'PZltNeW1M4cmEmOdRlbvOVmUNyB2';  // users.is_admin
const TS = Date.now();

let ok = 0, ko = 0;
function check(label, cond, r) {
  if (cond) ok++; else ko++;
  console.log(`${cond ? 'OK ' : 'KO '} ${label}${cond || !r ? '' : '  → ' + r.status + ' ' + r.body.slice(0, 160)}`);
}
const rows = (r) => (r.status >= 200 && r.status < 300 && r.body ? JSON.parse(r.body) : []);

(async () => {
  const nat = await as(NAT), emp = await as(EMP), tiers = await as(TIERS),
    admin = await as(ADMIN), anon = await as(null);

  console.log('── Lecture');
  let r = await nat.rest(`messages?select=id&conversation_id=eq.${CONV}`);
  const nbMsg = rows(r).length;
  check(`Natacha lit les messages de sa conversation (${nbMsg})`, nbMsg > 0, r);
  r = await nat.rest(`conversations?select=id&participants=cs.["${NAT}"]`);
  check('Natacha voit ses conversations', rows(r).length > 0, r);
  r = await tiers.rest(`messages?select=id&conversation_id=eq.${CONV}`);
  check('Tiers ne lit pas les messages de Natacha', rows(r).length === 0, r);
  r = await tiers.rest('conversations?select=participants');
  check('Tiers ne voit que ses conversations', rows(r).every((c) => c.participants.includes(TIERS)), r);
  r = await emp.rest(`messages?select=id&conversation_id=eq.${CONV}`);
  check('Employé ne lit pas les messages de son employeur', rows(r).length === 0, r);
  r = await anon.rest('messages?select=id&limit=5');
  check('Non connecté : aucun message', rows(r).length === 0, r);
  r = await anon.rest('conversations?select=id&limit=5');
  check('Non connecté : aucune conversation', rows(r).length === 0, r);
  r = await admin.rest(`messages?select=id&conversation_id=eq.${CONV}`);
  check('Admin lit une conversation (modération)', rows(r).length === nbMsg, r);

  console.log('── Envoi');
  r = await nat.insert('messages', { id: `test_${TS}`, conversation_id: CONV, sender_id: NAT, text: 'test rls', msg_type: 'text', is_read: false });
  check('Natacha envoie un message', rows(r).length === 1, r);
  r = await nat.insert('messages', { id: `test_${TS}_b`, conversation_id: CONV, sender_id: TIERS, text: 'usurpation', msg_type: 'text' });
  check('Natacha ne peut pas écrire au nom d\'un autre', r.status >= 400, r);
  r = await tiers.insert('messages', { id: `test_${TS}_c`, conversation_id: CONV, sender_id: TIERS, text: 'intrus', msg_type: 'text' });
  check('Tiers ne peut pas écrire dans la conversation', r.status >= 400, r);
  r = await anon.insert('messages', { id: `test_${TS}_d`, conversation_id: CONV, sender_id: 'x', text: 'anon', msg_type: 'text' });
  check('Non connecté ne peut pas écrire', r.status >= 400, r);

  console.log('── Réactions');
  r = await nat.insert('message_reactions', { message_id: `test_${TS}`, uid: NAT, emoji: '👍' });
  check('Natacha réagit à un message', rows(r).length === 1, r);
  r = await tiers.insert('message_reactions', { message_id: `test_${TS}`, uid: TIERS, emoji: '👎' });
  check('Tiers ne peut pas réagir', r.status >= 400, r);
  r = await tiers.rest(`message_reactions?select=id&message_id=eq.test_${TS}`);
  check('Tiers ne voit pas les réactions', rows(r).length === 0, r);
  r = await nat.del(`message_reactions?message_id=eq.test_${TS}&uid=eq.${NAT}`);
  check('Natacha retire sa réaction', rows(r).length === 1, r);

  console.log('── Conversation (mise à jour)');
  r = await nat.update(`conversations?id=eq.${CONV}`, { last_message: 'test rls' });
  check('Natacha met à jour sa conversation', rows(r).length === 1, r);
  r = await tiers.update(`conversations?id=eq.${CONV}`, { last_message: 'piraté' });
  check('Tiers ne peut pas la modifier', rows(r).length === 0, r);
  r = await tiers.del(`messages?id=eq.test_${TS}`);
  check('Tiers ne peut pas supprimer un message', rows(r).length === 0, r);
  r = await nat.del(`messages?id=eq.test_${TS}`);
  check('Natacha supprime son message', rows(r).length === 1, r);

  console.log('── Nouvelle conversation / groupe');
  const NEW = `test_conv_${TS}`;
  r = await nat.insert('conversations', { id: NEW, type: 'direct', participants: [NAT, TIERS], participant_ids: [NAT, TIERS].sort().join(',') });
  check('Natacha crée une conversation avec le tiers', rows(r).length === 1, r);
  r = await tiers.rest(`conversations?select=id&id=eq.${NEW}`);
  check('Le tiers la voit (il en fait partie)', rows(r).length === 1, r);
  r = await tiers.insert('conversations', { id: `${NEW}_x`, type: 'direct', participants: [NAT, EMP] });
  check('Créer une conversation sans en faire partie : refusé', r.status >= 400, r);
  const GRP = `test_grp_${TS}`;
  r = await nat.insert('conversations', { id: GRP, type: 'groupe', nom: 'test', created_by: NAT, participants: [NAT, TIERS, EMP], participant_ids: [NAT, TIERS, EMP].join(',') });
  check('Natacha crée un groupe', rows(r).length === 1, r);
  r = await tiers.update(`conversations?id=eq.${GRP}`, { participants: [NAT, EMP], participant_ids: [NAT, EMP].join(',') });
  check('Le tiers quitte le groupe', r.status >= 200 && r.status < 300, r);
  r = await tiers.rest(`conversations?select=id&id=eq.${GRP}`);
  check('… et ne le voit plus', rows(r).length === 0, r);
  r = await nat.del(`conversations?id=in.(${NEW},${GRP})`);
  check('Natacha supprime les conversations de test', rows(r).length === 2, r);

  console.log(`\n${ok} OK / ${ko} KO`);
  process.exit(ko ? 1 : 0);
})().catch((e) => { console.error(e.message); process.exit(1); });
