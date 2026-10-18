import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { verifiedUid, requireUser } from '@/lib/server-auth';
import { questionnaire } from '@/lib/consignes-rdv';
import { SITE_URL, echapperHtml, emailValide, gabaritEmail, envoyerEmail } from '@/lib/email-petsmatch';

// Consignes du client avant un rendez-vous (toiletteur).
//  GET  ?token= (lien personnel, sans compte) ou ?rdvId= (client du rdv ou
//       professionnel) → contexte, questionnaire, réponses, préremplissage
//       (consignes du rendez-vous précédent chez ce professionnel).
//  POST { token | rdvId, reponses }  → enregistre (client ; professionnel
//       pour une saisie à sa place) ; le professionnel est prévenu.
//  POST { action: 'demander', rdvId } → le professionnel demande les
//       consignes : notification (compte) + e-mail avec le lien personnel.
const admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY ?? '', { auth: { persistSession: false } });
const PRIVE = { 'Cache-Control': 'private, no-store', 'X-Robots-Tag': 'noindex, nofollow' };

interface RdvRow {
  id: string; date_heure: string; motif: string | null; statut: string; animal_id: string | null; animal_nom_manuel: string | null;
  pro_uid: string; pro_profile_id: string | null; client_uid: string | null; client_profile_id: string | null;
  client_email_manuel: string | null; client_nom_manuel: string | null;
  consignes: Record<string, string> | null; consignes_le: string | null; consignes_token: string | null;
}
const COLS = 'id, date_heure, motif, statut, animal_id, animal_nom_manuel, pro_uid, pro_profile_id, client_uid, client_profile_id, client_email_manuel, client_nom_manuel, consignes, consignes_le, consignes_token';

async function chargerRdv(par: { token?: string | null; rdvId?: string | null }): Promise<RdvRow | null> {
  const q = admin.from('rdv').select(COLS);
  if (par.token && /^[0-9a-f-]{36}$/i.test(par.token)) return ((await q.eq('consignes_token', par.token).maybeSingle()).data as RdvRow | null) ?? null;
  if (par.rdvId && /^[0-9a-f-]{36}$/i.test(par.rdvId)) return ((await q.eq('id', par.rdvId).maybeSingle()).data as RdvRow | null) ?? null;
  return null;
}

async function estPro(rdv: RdvRow, uid: string | null) {
  if (!uid) return false;
  if (rdv.pro_uid === uid) return true;
  const { data } = await admin.from('elevage_cogerants').select('id').eq('uid_gerant', rdv.pro_uid).eq('uid_cogerant', uid)
    .eq('statut', 'actif').is('date_fin', null).limit(1);
  return (data ?? []).length > 0;
}

async function infosPro(rdv: RdvRow) {
  const { data } = await admin.from('user_profiles_complet').select('nom, firstname, lastname, profile_type, cat_pro').eq('id', rdv.pro_profile_id ?? '').maybeSingle();
  const p = data as { nom?: string | null; firstname?: string | null; lastname?: string | null; profile_type?: string | null; cat_pro?: string | null } | null;
  return { nom: (p?.nom ?? '').trim() || `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim() || 'Votre professionnel', metier: p?.profile_type || p?.cat_pro || '' };
}

async function nomAnimal(rdv: RdvRow) {
  if (rdv.animal_id) {
    const { data } = await admin.from('animaux').select('nom').eq('id', rdv.animal_id).maybeSingle();
    const n = (data as { nom?: string } | null)?.nom;
    if (n) return n;
  }
  return rdv.animal_nom_manuel ?? '';
}

export async function GET(req: NextRequest) {
  const sp = req.nextUrl.searchParams;
  const token = sp.get('token');
  const rdv = await chargerRdv({ token, rdvId: sp.get('rdvId') });
  if (!rdv) return NextResponse.json({ error: 'Rendez-vous introuvable ou lien expiré' }, { status: 404, headers: PRIVE });
  let role: 'client' | 'pro' | null = token ? 'client' : null;
  if (!role) {
    const uid = await verifiedUid(req);
    role = uid && uid === rdv.client_uid ? 'client' : (await estPro(rdv, uid)) ? 'pro' : null;
  }
  if (!role) return NextResponse.json({ error: 'Accès non autorisé' }, { status: 403, headers: PRIVE });
  const pro = await infosPro(rdv);
  // Préremplissage : consignes du dernier rendez-vous chez ce professionnel (même animal ou même client).
  let prefill: Record<string, string> | null = null;
  if (!rdv.consignes && rdv.pro_profile_id) {
    let q = admin.from('rdv').select('consignes').eq('pro_profile_id', rdv.pro_profile_id).not('consignes', 'is', null).neq('id', rdv.id);
    q = rdv.animal_id ? q.eq('animal_id', rdv.animal_id) : rdv.client_uid ? q.eq('client_uid', rdv.client_uid) : q.eq('id', '00000000-0000-0000-0000-000000000000');
    const { data } = await q.order('date_heure', { ascending: false }).limit(1);
    prefill = ((data ?? [])[0] as { consignes?: Record<string, string> } | undefined)?.consignes ?? null;
  }
  return NextResponse.json({
    role, pro_nom: pro.nom, metier: pro.metier, animal_nom: await nomAnimal(rdv),
    rdv: { id: rdv.id, date_heure: rdv.date_heure, motif: rdv.motif, statut: rdv.statut },
    questions: questionnaire(pro.metier), reponses: rdv.consignes, saisi_le: rdv.consignes_le, prefill,
  }, { headers: PRIVE });
}

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({})) as { action?: string; token?: string; rdvId?: string; reponses?: Record<string, unknown> };

  if (body.action === 'demander') {
    const auth = await requireUser(req);
    if (auth instanceof NextResponse) return auth;
    const rdv = await chargerRdv({ rdvId: body.rdvId });
    if (!rdv) return NextResponse.json({ error: 'Rendez-vous introuvable' }, { status: 404 });
    if (!(await estPro(rdv, auth.uid))) return NextResponse.json({ error: 'Réservé au professionnel' }, { status: 403 });
    const pro = await infosPro(rdv);
    const animal = await nomAnimal(rdv);
    const lien = `${SITE_URL}/consignes/${rdv.consignes_token}`;
    const quand = new Date(rdv.date_heure).toLocaleString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Paris' });
    let notifie = false;
    if (rdv.client_uid) {
      await admin.from('notifications').insert({
        uid: rdv.client_uid, type: 'rdv_consignes', title: `Vos consignes pour ${animal || 'votre animal'}`,
        body: `${pro.nom} vous invite à préciser vos consignes avant le rendez-vous du ${quand}.`,
        ...(rdv.client_profile_id ? { profile_id: rdv.client_profile_id } : {}),
        data: { rdv_id: rdv.id, url: `/consignes/${rdv.consignes_token}` }, read: false,
      });
      notifie = true;
    }
    // E-mail : profil du client, rendez-vous, puis e-mail du compte.
    let email: string | null = null;
    if (rdv.client_profile_id) email = ((await admin.from('user_profiles_complet').select('email_contact').eq('id', rdv.client_profile_id).maybeSingle()).data as { email_contact?: string } | null)?.email_contact ?? null;
    if (!emailValide(email)) email = rdv.client_email_manuel;
    if (!emailValide(email) && rdv.client_uid) email = ((await admin.from('users').select('email').eq('uid', rdv.client_uid).maybeSingle()).data as { email?: string } | null)?.email ?? null;
    let emailEnvoye = false;
    if (emailValide(email)) {
      try {
        await envoyerEmail(email!.trim(), `Vos consignes pour le rendez-vous du ${quand}`, gabaritEmail({
          sousTitre: 'Préparez votre rendez-vous',
          salutation: `Bonjour${rdv.client_nom_manuel ? ` <strong>${echapperHtml(rdv.client_nom_manuel)}</strong>` : ''},`,
          paragraphes: [
            `<strong>${echapperHtml(pro.nom)}</strong> vous accueille le ${echapperHtml(quand)}${animal ? ` avec <strong>${echapperHtml(animal)}</strong>` : ''}.`,
            'Pour que tout se passe au mieux, indiquez vos consignes : coupe souhaitée, zones sensibles, tolérance au séchoir, comportement, produits à éviter… Cela prend une minute, sans créer de compte.',
            `Vous pouvez aussi retrouver vos rendez-vous, factures et le carnet de votre animal dans l'application PetsMatch ou sur <a href="${SITE_URL}" style="color:#0C5C6C;">petsmatchapp.com</a>.`,
          ],
          bouton: { label: 'Indiquer mes consignes', url: lien },
        }));
        emailEnvoye = true;
      } catch (e) { console.error('[consignes] e-mail', e); }
    }
    if (!notifie && !emailEnvoye) return NextResponse.json({ error: 'Aucun moyen de joindre le client (ni compte, ni e-mail).' }, { status: 400 });
    await admin.from('rdv').update({ consignes_demandees_le: new Date().toISOString() }).eq('id', rdv.id);
    return NextResponse.json({ ok: true, notifie, email_envoye: emailEnvoye, lien });
  }

  // Enregistrement des réponses.
  const rdv = await chargerRdv({ token: body.token, rdvId: body.rdvId });
  if (!rdv) return NextResponse.json({ error: 'Rendez-vous introuvable ou lien expiré' }, { status: 404 });
  let role: 'client' | 'pro' | null = body.token ? 'client' : null;
  if (!role) {
    const uid = await verifiedUid(req);
    role = uid && uid === rdv.client_uid ? 'client' : (await estPro(rdv, uid)) ? 'pro' : null;
  }
  if (!role) return NextResponse.json({ error: 'Accès non autorisé' }, { status: 403 });
  if (['annule', 'refuse'].includes(rdv.statut)) return NextResponse.json({ error: 'Ce rendez-vous est annulé.' }, { status: 409 });
  const pro = await infosPro(rdv);
  const cles = new Set(questionnaire(pro.metier).map(q => q.cle));
  const reponses: Record<string, string> = {};
  for (const [k, v] of Object.entries(body.reponses ?? {})) {
    if (cles.has(k) && typeof v === 'string' && v.trim()) reponses[k] = v.trim().slice(0, 1500);
  }
  const { error } = await admin.from('rdv').update({ consignes: reponses, consignes_le: new Date().toISOString() }).eq('id', rdv.id);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  if (role === 'client') {
    const animal = await nomAnimal(rdv);
    await admin.from('notifications').insert({
      uid: rdv.pro_uid, type: 'rdv_consignes_recues', title: 'Consignes reçues',
      body: `Le client a indiqué ses consignes${animal ? ` pour ${animal}` : ''} (rendez-vous du ${new Date(rdv.date_heure).toLocaleDateString('fr-FR', { timeZone: 'Europe/Paris' })}).`,
      ...(rdv.pro_profile_id ? { profile_id: rdv.pro_profile_id } : {}),
      data: { rdv_id: rdv.id }, read: false,
    });
  }
  return NextResponse.json({ ok: true });
}
