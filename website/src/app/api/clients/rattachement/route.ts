import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { requireUser } from '@/lib/server-auth';

// Clients sans appli → compte PetsMatch (à la Doctolib) : un professionnel
// (clinique, toiletteur, maréchal-ferrant, ostéopathe, éducateur, pet-sitter —
// fichier clients_clinique ; pension — fiche créée à l'entrée en pension,
// pension_entrees.proprietaire_email) a créé la fiche de l'animal ; le client
// crée ensuite son compte avec la même adresse e-mail et valide lui-même le
// rattachement. Identifiant de proposition : id du client, ou « pension:<animal> ».
//  GET  → propositions pour l'e-mail du compte (fiches non rattachées, non refusées).
//  POST { clientId, accepter, profileId? } → rattache (animaux, rendez-vous)
//       ou refuse (plus de proposition).
const admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY ?? '', { auth: { persistSession: false } });

async function emailsDuCompte(uid: string): Promise<string[]> {
  const out = new Set<string>();
  const { data: u } = await admin.from('users').select('email').eq('uid', uid).maybeSingle();
  const e = (u as { email?: string | null } | null)?.email?.trim().toLowerCase();
  if (e) out.add(e);
  const { data: profs } = await admin.from('user_profiles_complet').select('email_contact').eq('uid', uid);
  for (const p of (profs ?? []) as { email_contact?: string | null }[]) {
    const x = p.email_contact?.trim().toLowerCase();
    if (x) out.add(x);
  }
  return [...out];
}

interface ClientRow { id: string; clinique_profile_id: string; nom: string; prenom: string | null; email: string | null; uid_lie: string | null; rattachement_refuse_le?: string | null }

async function propositions(uid: string) {
  const emails = await emailsDuCompte(uid);
  if (!emails.length) return [];
  const { data } = await admin.from('clients_clinique').select('id, clinique_profile_id, nom, prenom, email, uid_lie, rattachement_refuse_le')
    .in('email', emails).is('uid_lie', null).is('rattachement_refuse_le', null);
  const clients = (data ?? []) as ClientRow[];
  const out = [];
  for (const c of clients) {
    const { data: an } = await admin.from('animaux').select('id, nom, espece').eq('client_clinique_id', c.id);
    const animaux = (an ?? []) as { id: string; nom: string | null; espece: string | null }[];
    if (!animaux.length) continue;
    const { data: pro } = await admin.from('user_profiles_complet').select('nom, firstname, lastname, profile_type').eq('id', c.clinique_profile_id).maybeSingle();
    const p = pro as { nom?: string | null; firstname?: string | null; lastname?: string | null; profile_type?: string | null } | null;
    out.push({
      clientId: c.id,
      pro: { nom: (p?.nom ?? '').trim() || `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim() || 'Un professionnel', metier: p?.profile_type ?? '' },
      animaux,
    });
  }
  // Pension : animaux dont la fiche a été créée par la pension (uid_eleveur =
  // la pension), sans propriétaire, entrés avec l'adresse e-mail du compte.
  const filtreEmails = emails.filter(e => !/[,()]/.test(e)).map(e => `proprietaire_email.ilike.${e}`).join(',');
  const { data: ent } = filtreEmails
    ? await admin.from('pension_entrees').select('animal_id, animal_nom, espece, pro_uid, pro_profile_id, proprietaire_email, rattachement_refuse_le')
      .not('animal_id', 'is', null).or(filtreEmails)
    : { data: [] };
  const vus = new Set<string>();
  for (const e of (ent ?? []) as { animal_id: string; animal_nom: string | null; espece: string | null; pro_uid: string; pro_profile_id: string | null; proprietaire_email: string | null; rattachement_refuse_le: string | null }[]) {
    if (!e.proprietaire_email || !emails.includes(e.proprietaire_email.trim().toLowerCase()) || e.rattachement_refuse_le || vus.has(e.animal_id)) continue;
    vus.add(e.animal_id);
    const { data: a } = await admin.from('animaux').select('id, nom, espece, uid_eleveur, uid_proprietaire').eq('id', e.animal_id).maybeSingle();
    const an = a as { id: string; nom: string | null; espece: string | null; uid_eleveur: string | null; uid_proprietaire: string | null } | null;
    if (!an || an.uid_eleveur !== e.pro_uid || an.uid_proprietaire) continue;
    const { data: props } = await admin.from('animaux_proprietes').select('id').eq('animal_id', an.id).neq('uid_proprio', e.pro_uid).is('date_fin', null).limit(1);
    if ((props ?? []).length) continue;
    const { data: pro } = await admin.from('user_profiles_complet').select('nom, firstname, lastname').eq('id', e.pro_profile_id ?? '').maybeSingle();
    const p = pro as { nom?: string | null; firstname?: string | null; lastname?: string | null } | null;
    out.push({
      clientId: `pension:${an.id}`,
      pro: { nom: (p?.nom ?? '').trim() || `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim() || 'Votre pension', metier: 'pension' },
      animaux: [{ id: an.id, nom: an.nom ?? e.animal_nom, espece: an.espece ?? e.espece }],
    });
  }
  return out;
}

export async function GET(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  return NextResponse.json({ propositions: await propositions(auth.uid) }, { headers: { 'Cache-Control': 'private, no-store' } });
}

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const body = await req.json().catch(() => ({})) as { clientId?: string; accepter?: boolean; profileId?: string | null };
  const dispo = await propositions(auth.uid);
  const prop = dispo.find(p => p.clientId === body.clientId);
  if (!prop) return NextResponse.json({ error: 'Proposition introuvable ou déjà traitée' }, { status: 404 });
  const maintenant = new Date().toISOString();

  const pension = prop.clientId.startsWith('pension:');
  if (!body.accepter) {
    if (pension) {
      await admin.from('pension_entrees').update({ rattachement_refuse_le: maintenant }).eq('animal_id', prop.animaux[0].id);
    } else {
      await admin.from('clients_clinique').update({ rattachement_refuse_le: maintenant, updated_at: maintenant }).eq('id', prop.clientId);
    }
    return NextResponse.json({ ok: true });
  }

  // Profil destinataire : celui indiqué s'il appartient au compte, sinon le profil particulier.
  let profil: string | null = null;
  if (body.profileId) {
    const { data } = await admin.from('user_profiles').select('id').eq('id', body.profileId).eq('uid', auth.uid).maybeSingle();
    profil = (data as { id?: string } | null)?.id ?? null;
  }
  if (!profil) {
    const { data } = await admin.from('user_profiles').select('id').eq('uid', auth.uid).eq('profile_type', 'particulier').limit(1).maybeSingle();
    profil = (data as { id?: string } | null)?.id ?? null;
  }
  const date = maintenant.slice(0, 10);
  for (const a of prop.animaux) {
    // L'animal passe au propriétaire ; le professionnel garde son accès (animal_access).
    const { data: deja } = await admin.from('animaux_proprietes').select('id').eq('animal_id', a.id).eq('uid_proprio', auth.uid).is('date_fin', null).limit(1);
    if (!(deja ?? []).length) {
      await admin.from('animaux_proprietes').insert({
        animal_id: a.id, uid_proprio: auth.uid, ...(profil ? { profile_id_proprio: profil } : {}),
        date_debut: date, role_proprio: 'principal', statut: 'actif',
      });
    }
    await admin.from('animaux').update({ uid_proprietaire: auth.uid, statut: 'present', updated_at: maintenant }).eq('id', a.id);
  }
  if (!pension) {
    await admin.from('clients_clinique').update({ uid_lie: auth.uid, ...(profil ? { profile_lie_id: profil } : {}), updated_at: maintenant }).eq('id', prop.clientId);
  }
  // Rendez-vous de ces animaux encore sans compte client : rattachés.
  const ids = prop.animaux.map(a => a.id);
  await admin.from('rdv').update({ client_uid: auth.uid, ...(profil ? { client_profile_id: profil } : {}) })
    .in('animal_id', ids).is('client_uid', null);
  // Le professionnel est prévenu (la pension garde l'accès via ses séjours).
  let pid: string | undefined;
  if (pension) {
    const { data: e } = await admin.from('pension_entrees').select('pro_profile_id').eq('animal_id', prop.animaux[0].id).not('pro_profile_id', 'is', null).limit(1).maybeSingle();
    pid = (e as { pro_profile_id?: string } | null)?.pro_profile_id;
  } else {
    const { data: c } = await admin.from('clients_clinique').select('clinique_profile_id').eq('id', prop.clientId).maybeSingle();
    pid = (c as { clinique_profile_id?: string } | null)?.clinique_profile_id;
  }
  if (pid) {
    const { data: up } = await admin.from('user_profiles').select('uid').eq('id', pid).maybeSingle();
    const proUid = (up as { uid?: string } | null)?.uid;
    if (proUid) {
      await admin.from('notifications').insert({
        uid: proUid, profile_id: pid, type: 'client_rattache', title: 'Votre client a rejoint PetsMatch',
        body: `${prop.animaux.map(a => a.nom).filter(Boolean).join(', ') || 'La fiche'} est désormais rattachée au compte de son propriétaire. Vous gardez votre accès.`,
        data: { client_id: prop.clientId }, read: false,
      });
    }
  }
  return NextResponse.json({ ok: true, animaux: ids });
}
