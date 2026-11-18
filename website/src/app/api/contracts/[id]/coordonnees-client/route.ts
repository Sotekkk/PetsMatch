import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { requireUser } from '@/lib/server-auth';

// Coordonnées complètes du client d'un contrat de prestation (nom, e-mail,
// téléphone, adresse), lues côté serveur : depuis le navigateur, la fiche
// d'un client particulier est masquée (vues « données perso ») et le contrat
// du site s'affichait sans adresse / téléphone / e-mail alors que l'appli les
// avait. Réservé au prestataire du contrat (ou cogérant actif) et au client
// lui-même. [id] = id du document (documents_animaux).
const admin = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);

const RDV_COLS = 'id, client_nom_manuel, client_email_manuel, client_telephone_manuel, adresse_depart, date_heure, motif, prestation_id, prix_calcule, animal_id, animal_nom_manuel';
const ANIMAL_COLS = 'id, nom, espece, race, identification, date_naissance';

const t = (v: unknown) => (typeof v === 'string' ? v.trim() : v == null ? '' : String(v).trim());
const premier = (...v: unknown[]) => v.map(t).find(Boolean) ?? '';

function adresseDe(p: Record<string, unknown> | null | undefined): string {
  if (!p) return '';
  const rue = premier(p.rue, p.rue_pro, p.rue_elevage);
  const cpVille = [premier(p.code_postal, p.code_postal_pro), premier(p.ville, p.ville_pro)].filter(Boolean).join(' ');
  if (rue) return [rue, cpVille].filter(Boolean).join(', ');
  const bloc = premier(p.adresse, p.adress);
  return bloc || cpVille;
}

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const { id } = await params;
  const { data: doc } = await admin.from('documents_animaux').select('id, uid_eleveur, pro_profile_id, animal_id, rdv_id, metadata').eq('id', id).maybeSingle();
  if (!doc) return NextResponse.json({ error: 'Contrat introuvable' }, { status: 404 });
  const meta = ((doc as { metadata?: Record<string, unknown> | null }).metadata ?? {}) as Record<string, unknown>;
  const uidPro = String((doc as { uid_eleveur: string }).uid_eleveur);
  const clientUid = t(meta.client_uid) || t(meta.acquereur_uid);
  const clientPid = t(meta.client_profile_id) || t(meta.acquereur_profile_id);

  let autorise = auth.uid === uidPro || (!!clientUid && auth.uid === clientUid);
  if (!autorise) {
    const { data: co } = await admin.from('elevage_cogerants').select('id')
      .eq('uid_gerant', uidPro).eq('uid_cogerant', auth.uid).eq('statut', 'actif').is('date_fin', null).limit(1);
    autorise = (co ?? []).length > 0;
  }
  if (!autorise) return NextResponse.json({ error: 'Non autorisé' }, { status: 403 });

  const proPid = t((doc as { pro_profile_id?: string | null }).pro_profile_id);
  const [{ data: prof }, { data: compte }, { data: proProf }, { data: proCompte }] = await Promise.all([
    clientPid
      ? admin.from('user_profiles').select('firstname, lastname, nom, email_contact, phone_number, phone, telephone, adresse, rue, code_postal, ville, rue_pro, code_postal_pro, ville_pro').eq('id', clientPid).maybeSingle()
      : Promise.resolve({ data: null }),
    clientUid
      ? admin.from('users').select('firstname, lastname, email, phone_number, adress, rue, code_postal, ville').eq('uid', clientUid).maybeSingle()
      : Promise.resolve({ data: null }),
    proPid ? admin.from('user_profiles').select('email_contact, phone_number, phone').eq('id', proPid).maybeSingle() : Promise.resolve({ data: null }),
    admin.from('users').select('email, phone_number').eq('uid', uidPro).maybeSingle(),
  ]);
  // RDV du contrat, sinon le dernier de ce client avec ce prestataire : coordonnées saisies à la main.
  const rdvId = t(meta.rdv_id) || t((doc as { rdv_id?: string | null }).rdv_id);
  let rdv: Record<string, unknown> | null = null;
  if (rdvId) {
    rdv = (await admin.from('rdv').select(RDV_COLS).eq('id', rdvId).maybeSingle()).data as Record<string, unknown> | null;
  } else if (clientUid || clientPid) {
    let q = admin.from('rdv').select(RDV_COLS).eq('pro_uid', uidPro);
    q = clientUid ? q.eq('client_uid', clientUid) : q.eq('client_profile_id', clientPid);
    rdv = (await q.order('date_heure', { ascending: false }).limit(1).maybeSingle()).data as Record<string, unknown> | null;
  }
  // Séance du contrat (date, lieu, prestation, prix) et animaux concernés :
  // lus ici car la RLS peut les masquer au navigateur (le site affichait un
  // contrat de toilettage sans date ni prix).
  const r = rdv;
  let prestation: Record<string, unknown> | null = null;
  if (r?.prestation_id) {
    prestation = (await admin.from('prestations_toilettage').select('nom, prix_base').eq('id', String(r.prestation_id)).maybeSingle()).data as Record<string, unknown> | null;
  }
  const idsMeta = [meta.animaux_ids, meta.animal_ids].find(Array.isArray) as unknown[] | undefined;
  const ids = [...new Set((idsMeta ?? []).map(t).filter(Boolean))];
  if (!ids.length) { const a = t(r?.animal_id) || t((doc as { animal_id?: string | null }).animal_id); if (a) ids.push(a); }
  const animaux = ids.length
    ? ((await admin.from('animaux').select(ANIMAL_COLS).in('id', ids)).data ?? []) as Record<string, unknown>[]
    : [];
  animaux.sort((a, b) => ids.indexOf(String(a.id)) - ids.indexOf(String(b.id)));

  const p = prof as Record<string, unknown> | null;
  const pp = proProf as Record<string, unknown> | null;
  const pc = proCompte as Record<string, unknown> | null;
  const u = compte as Record<string, unknown> | null;
  const adresses = [adresseDe(p), adresseDe(u)].filter(Boolean).sort((a, b) => b.length - a.length);
  return NextResponse.json({
    nom: premier(`${t(p?.firstname)} ${t(p?.lastname)}`, p?.nom, `${t(u?.firstname)} ${t(u?.lastname)}`, rdv?.client_nom_manuel),
    email: premier(p?.email_contact, u?.email, rdv?.client_email_manuel),
    tel: premier(p?.phone_number, p?.phone, p?.telephone, u?.phone_number, rdv?.client_telephone_manuel),
    adresse: adresses[0] ?? '',
    pro: { email: premier(pp?.email_contact, pc?.email), tel: premier(pp?.phone_number, pp?.phone, pc?.phone_number) },
    rdv: r ? {
      date_heure: r.date_heure ?? null, lieu: t(r.adresse_depart), motif: t(r.motif), animal_nom: t(r.animal_nom_manuel),
      prix: r.prix_calcule ?? prestation?.prix_base ?? null, prestation_nom: t(prestation?.nom),
    } : null,
    animaux: animaux.map(a => ({ nom: t(a.nom), espece: t(a.espece), race: t(a.race), identification: t(a.identification), date_naissance: a.date_naissance ?? null })),
  });
}
