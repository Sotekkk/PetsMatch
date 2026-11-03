import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { requireUser } from '@/lib/server-auth';
import { echapperHtml, emailValide, gabaritEmail, envoyerEmail } from '@/lib/email-petsmatch';

// RDV « Intervention » (vétérinaire) : consignes avant l'intervention (à
// jeun…) envoyées au propriétaire — notification s'il a un compte, e-mail
// sinon / en plus. POST { rdvId }. Réservé au professionnel du RDV (titulaire,
// cogérant, employé actif de la clinique). Miroir appli : envoyerConsignesPreop
// (lib/utils/intervention.dart) qui appelle cette route.
const admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY ?? '', { auth: { persistSession: false } });

interface RdvRow {
  id: string; date_heure: string; motif: string | null; animal_id: string | null; animal_nom_manuel: string | null;
  pro_uid: string; pro_profile_id: string | null; client_uid: string | null; client_profile_id: string | null;
  client_email_manuel: string | null; client_nom_manuel: string | null;
  intervention_type: string | null; heure_recuperation: string | null; consignes_preop: string | null;
}

async function estPro(rdv: RdvRow, uid: string) {
  if (rdv.pro_uid === uid) return true;
  const [{ data: co }, { data: emp }] = await Promise.all([
    admin.from('elevage_cogerants').select('id').eq('uid_gerant', rdv.pro_uid).eq('uid_cogerant', uid).eq('statut', 'actif').is('date_fin', null).limit(1),
    rdv.pro_profile_id
      ? admin.from('employes').select('id').eq('eleveur_profile_id', rdv.pro_profile_id).eq('uid_employe', uid).eq('actif', true).limit(1)
      : Promise.resolve({ data: [] }),
  ]);
  return (co ?? []).length > 0 || (emp ?? []).length > 0;
}

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const body = await req.json().catch(() => ({})) as { rdvId?: string };
  if (!body.rdvId || !/^[0-9a-f-]{36}$/i.test(body.rdvId)) return NextResponse.json({ error: 'rdvId requis' }, { status: 400 });
  const { data } = await admin.from('rdv')
    .select('id, date_heure, motif, animal_id, animal_nom_manuel, pro_uid, pro_profile_id, client_uid, client_profile_id, client_email_manuel, client_nom_manuel, intervention_type, heure_recuperation, consignes_preop')
    .eq('id', body.rdvId).maybeSingle();
  const rdv = data as RdvRow | null;
  if (!rdv) return NextResponse.json({ error: 'Rendez-vous introuvable' }, { status: 404 });
  if (!(await estPro(rdv, auth.uid))) return NextResponse.json({ error: 'Réservé au professionnel' }, { status: 403 });
  const consignes = (rdv.consignes_preop ?? '').trim();
  if (!consignes) return NextResponse.json({ error: 'Aucune consigne à envoyer' }, { status: 400 });

  const { data: p } = await admin.from('user_profiles_complet').select('nom, firstname, lastname').eq('id', rdv.pro_profile_id ?? '').maybeSingle();
  const pp = p as { nom?: string | null; firstname?: string | null; lastname?: string | null } | null;
  const proNom = (pp?.nom ?? '').trim() || `${pp?.firstname ?? ''} ${pp?.lastname ?? ''}`.trim() || 'Votre vétérinaire';
  let animal = rdv.animal_nom_manuel ?? '';
  if (rdv.animal_id) animal = ((await admin.from('animaux').select('nom').eq('id', rdv.animal_id).maybeSingle()).data as { nom?: string } | null)?.nom ?? animal;
  const fmt = (d: string, o: Intl.DateTimeFormatOptions) => new Date(d).toLocaleString('fr-FR', { ...o, timeZone: 'Europe/Paris' });
  const depot = fmt(rdv.date_heure, { weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' });
  const recup = rdv.heure_recuperation ? fmt(rdv.heure_recuperation, { hour: '2-digit', minute: '2-digit' }) : null;
  const intitule = rdv.motif || 'Intervention';

  let notifie = false;
  if (rdv.client_uid) {
    await admin.from('notifications').insert({
      uid: rdv.client_uid, type: 'rdv_consignes_preop', title: `Avant l'intervention${animal ? ` de ${animal}` : ''}`,
      body: `${intitule} le ${depot}${recup ? ` (récupération vers ${recup})` : ''}. Consignes : ${consignes}`,
      ...(rdv.client_profile_id ? { profile_id: rdv.client_profile_id } : {}),
      data: { rdv_id: rdv.id }, read: false,
    });
    notifie = true;
  }
  let email: string | null = null;
  if (rdv.client_profile_id) email = ((await admin.from('user_profiles_complet').select('email_contact').eq('id', rdv.client_profile_id).maybeSingle()).data as { email_contact?: string } | null)?.email_contact ?? null;
  if (!emailValide(email)) email = rdv.client_email_manuel;
  if (!emailValide(email) && rdv.client_uid) email = ((await admin.from('users').select('email').eq('uid', rdv.client_uid).maybeSingle()).data as { email?: string } | null)?.email ?? null;
  let emailEnvoye = false;
  if (emailValide(email)) {
    try {
      await envoyerEmail(email!.trim(), `${intitule}${animal ? ` de ${animal}` : ''} — consignes avant l'intervention`, gabaritEmail({
        sousTitre: 'Avant l’intervention',
        salutation: `Bonjour${rdv.client_nom_manuel ? ` <strong>${echapperHtml(rdv.client_nom_manuel)}</strong>` : ''},`,
        paragraphes: [
          `<strong>${echapperHtml(proNom)}</strong> accueille ${animal ? `<strong>${echapperHtml(animal)}</strong>` : 'votre animal'} pour : <strong>${echapperHtml(intitule)}</strong>.`,
          `Dépôt : <strong>${echapperHtml(depot)}</strong>${recup ? `<br/>Récupération prévue vers <strong>${echapperHtml(recup)}</strong> (nous vous confirmerons l’heure)` : ''}.`,
          `<strong>Consignes à respecter :</strong><br/>${echapperHtml(consignes).replace(/\n/g, '<br/>')}`,
          'En cas de question ou d’empêchement, contactez la clinique.',
        ],
      }));
      emailEnvoye = true;
    } catch (e) { console.error('[consignes-preop] e-mail', e); }
  }
  if (!notifie && !emailEnvoye) return NextResponse.json({ error: 'Aucun moyen de joindre le client (ni compte, ni e-mail).' }, { status: 400 });
  return NextResponse.json({ ok: true, notifie, email_envoye: emailEnvoye });
}
