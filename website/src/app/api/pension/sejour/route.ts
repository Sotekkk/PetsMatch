import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { requireUser } from '@/lib/server-auth';

// Pension — réservation de séjour par le client (demande à accepter).
//  GET  ?pensionProfileId=&animalId= (client) → infos pension (essai exigé,
//       tarifs publics), premier séjour de cet animal chez elle ?
//  POST { pensionProfileId, animalId, dateArrivee, dateDepart, dejaVenu?, essaiDate?, message?, profileId? }
//       (client) → demande (pension_demandes) + accès à la fiche pour la pension.
//       Sans historique chez cette pension, le client dit si l'animal est déjà
//       venu (`dejaVenu`) ; l'essai n'est exigé que pour un nouveau pensionnaire.
//  POST { action: 'decider', demandeId, accepter, motif?, forcer? } (pension) →
//       séjour (+ essai) créés dans pension_entrees, ou refus ; client prévenu.
//       Sans `forcer`, 409 { complet, jours } si un jour du séjour dépasse la
//       capacité des hébergements (enclos_chenil).
//  POST { action: 'annuler', demandeId } (client) → demande annulée.
const admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY ?? '', { auth: { persistSession: false } });
const JOUR = /^\d{4}-\d{2}-\d{2}$/;
const fr = (d: string) => new Date(`${d}T12:00:00`).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long' });

async function pension(pid: string) {
  const { data } = await admin.from('user_profiles').select('id, uid, nom, profile_type, pension_essai_requis, pension_essai_info, tarifs_pension').eq('id', pid).maybeSingle();
  const p = data as { id: string; uid: string; nom: string | null; profile_type: string | null; pension_essai_requis?: boolean; pension_essai_info?: string | null; tarifs_pension?: Record<string, unknown> | null } | null;
  return p && p.profile_type === 'pension' ? p : null;
}

async function premierSejour(proUid: string, animalId: string) {
  const { count } = await admin.from('pension_entrees').select('id', { count: 'exact', head: true }).eq('pro_uid', proUid).eq('animal_id', animalId);
  return !count;
}

async function estProprio(uid: string, animalId: string) {
  const { data } = await admin.from('animaux_proprietes').select('id').eq('animal_id', animalId).eq('uid_proprio', uid).is('date_fin', null).limit(1);
  if ((data ?? []).length) return true;
  const { data: a } = await admin.from('animaux').select('uid_proprietaire').eq('id', animalId).maybeSingle();
  return (a as { uid_proprietaire?: string | null } | null)?.uid_proprietaire === uid;
}

/** Jours (nuits) du séjour où les hébergements sont déjà pleins. Sans
 *  hébergement configuré (pension familiale), aucune limite connue. */
async function joursComplets(proUid: string, proProfileId: string | null, jours: string[]) {
  const { data: lg } = await admin.from('enclos_chenil').select('capacite').eq('uid_eleveur', proUid);
  const logements = (lg ?? []) as { capacite: number | null }[];
  if (!logements.length || !jours.length) return { capacite: 0, complets: [] as { jour: string; occupes: number }[] };
  const capacite = logements.reduce((t, l) => t + (l.capacite ?? 1), 0);
  const tri = [...jours].sort();
  const { data: en } = await admin.from('pension_entrees').select('date_entree, date_sortie_prevue, pro_profile_id')
    .eq('pro_uid', proUid).eq('statut', 'en_pension').lte('date_entree', tri[tri.length - 1]);
  const entrees = ((en ?? []) as { date_entree: string; date_sortie_prevue: string | null; pro_profile_id: string | null }[])
    .filter(e => !proProfileId || !e.pro_profile_id || e.pro_profile_id === proProfileId);
  const occupe = (e: { date_entree: string; date_sortie_prevue: string | null }, j: string) =>
    e.date_entree <= j && (!e.date_sortie_prevue || e.date_sortie_prevue > j || (e.date_sortie_prevue === e.date_entree && j === e.date_entree));
  const complets = tri.map(j => ({ jour: j, occupes: entrees.filter(e => occupe(e, j)).length })).filter(x => x.occupes >= capacite);
  return { capacite, complets };
}

/** Nuits du séjour (le jour du départ n'est pas compté ; séjour d'un jour = ce jour). */
function nuitsDuSejour(arrivee: string, depart: string) {
  const out: string[] = [];
  const d = new Date(`${arrivee}T12:00:00Z`);
  const fin = new Date(`${depart}T12:00:00Z`);
  while (d < fin && out.length < 400) { out.push(d.toISOString().slice(0, 10)); d.setUTCDate(d.getUTCDate() + 1); }
  return out.length ? out : [arrivee];
}

async function estGestionnaire(proUid: string, uid: string) {
  if (proUid === uid) return true;
  const { data } = await admin.from('elevage_cogerants').select('id').eq('uid_gerant', proUid).eq('uid_cogerant', uid).eq('statut', 'actif').is('date_fin', null).limit(1);
  return (data ?? []).length > 0;
}

export async function GET(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const p = await pension(req.nextUrl.searchParams.get('pensionProfileId') ?? '');
  if (!p) return NextResponse.json({ error: 'Pension introuvable' }, { status: 404 });
  const animalId = req.nextUrl.searchParams.get('animalId');
  const tarifs = p.tarifs_pension && (p.tarifs_pension as { afficher_public?: boolean }).afficher_public ? p.tarifs_pension : null;
  return NextResponse.json({
    pension: { nom: p.nom ?? 'Pension', essai_requis: !!p.pension_essai_requis, essai_info: p.pension_essai_info ?? null, tarifs },
    premier_sejour: animalId ? await premierSejour(p.uid, animalId) : null,
  }, { headers: { 'Cache-Control': 'private, no-store' } });
}

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const b = await req.json().catch(() => ({})) as {
    action?: string; pensionProfileId?: string; animalId?: string; dateArrivee?: string; dateDepart?: string; essaiDate?: string | null; dejaVenu?: boolean | null; hebergement?: string | null;
    message?: string; profileId?: string | null; demandeId?: string; accepter?: boolean; motif?: string; forcer?: boolean;
  };
  const maintenant = new Date().toISOString();

  // ── Décision de la pension ──
  if (b.action === 'decider') {
    const { data } = await admin.from('pension_demandes').select('*').eq('id', b.demandeId ?? '').maybeSingle();
    const d = data as Record<string, string | null> | null;
    if (!d) return NextResponse.json({ error: 'Demande introuvable' }, { status: 404 });
    if (!(await estGestionnaire(d.pro_uid as string, auth.uid))) return NextResponse.json({ error: 'Réservé à la pension' }, { status: 403 });
    if (d.statut !== 'demande') return NextResponse.json({ error: 'Demande déjà traitée' }, { status: 409 });
    const notifClient = async (type: string, title: string, body: string) => admin.from('notifications').insert({
      uid: d.client_uid, type, title, body, ...(d.client_profile_id ? { profile_id: d.client_profile_id } : {}),
      data: { demande_id: d.id, animalId: d.animal_id }, read: false,
    });
    if (!b.accepter) {
      const motif = (b.motif ?? '').trim().slice(0, 500) || null;
      await admin.from('pension_demandes').update({ statut: 'refusee', motif_refus: motif, decide_le: maintenant }).eq('id', d.id);
      await notifClient('pension_sejour_refuse', 'Séjour non accepté',
        `Votre demande de séjour pour ${d.animal_nom ?? 'votre animal'} (${fr(d.date_arrivee as string)} → ${fr(d.date_depart as string)}) n'a pas pu être acceptée.${motif ? ` ${motif}` : ''}`);
      return NextResponse.json({ ok: true });
    }
    // Places libres : la pension peut accepter quand même (surbooking assumé).
    if (!b.forcer) {
      const jours = [...nuitsDuSejour(d.date_arrivee as string, d.date_depart as string), ...(d.essai_date ? [d.essai_date] : [])];
      const { capacite, complets } = await joursComplets(d.pro_uid as string, d.pro_profile_id, jours);
      if (complets.length) {
        return NextResponse.json({
          error: `Complet ${complets.length > 1 ? 'les' : 'le'} ${complets.slice(0, 5).map(c => fr(c.jour)).join(', ')}${complets.length > 5 ? '…' : ''} (${capacite} place${capacite > 1 ? 's' : ''}).`,
          complet: true, capacite, jours: complets,
        }, { status: 409 });
      }
    }
    // Verrou : un seul « Accepter » passe (double clic, deux appareils).
    const { data: verrou } = await admin.from('pension_demandes').update({ statut: 'acceptee', decide_le: maintenant })
      .eq('id', d.id).eq('statut', 'demande').select('id');
    if (!(verrou ?? []).length) return NextResponse.json({ error: 'Demande déjà traitée' }, { status: 409 });
    // Séjour (et essai) dans le registre, avec la fiche et les coordonnées du client.
    const { data: an } = await admin.from('animaux').select('nom, espece, race, identification, photo_url').eq('id', d.animal_id as string).maybeSingle();
    const a = an as { nom?: string | null; espece?: string | null; race?: string | null; identification?: string | null; photo_url?: string | null } | null;
    const { data: cp } = d.client_profile_id
      ? await admin.from('user_profiles_complet').select('firstname, lastname, nom, phone_number, email_contact, rue, code_postal, ville').eq('id', d.client_profile_id).maybeSingle()
      : { data: null };
    const c = cp as Record<string, string | null> | null;
    const base = {
      pro_uid: d.pro_uid, pro_profile_id: d.pro_profile_id, animal_id: d.animal_id,
      animal_nom: a?.nom ?? d.animal_nom ?? 'Animal', espece: a?.espece ?? d.espece, race: a?.race ?? null, puce: a?.identification ?? null,
      photo_url: a?.photo_url ?? null,
      proprietaire_nom: (`${c?.firstname ?? ''} ${c?.lastname ?? ''}`.trim() || c?.nom) ?? null,
      proprietaire_contact: c?.phone_number ?? null, proprietaire_email: c?.email_contact ?? null,
      proprietaire_adresse: [c?.rue, c?.code_postal, c?.ville].filter(Boolean).join(' ') || null,
      statut: 'en_pension',
    };
    const { data: ent, error } = await admin.from('pension_entrees').insert({
      ...base, date_entree: d.date_arrivee, date_sortie_prevue: d.date_depart,
      // Consignes du client (traitement, habitudes…) → consignes du séjour.
      ...(d.message ? { consignes_sejour: d.message } : {}),
      notes: [d.hebergement ? `Hébergement souhaité : ${d.hebergement === 'pre' ? 'pré' : 'box'}` : '', d.message ? `Message du client : ${d.message}` : ''].filter(Boolean).join('\n') || null,
    }).select('id').single();
    if (error) {
      await admin.from('pension_demandes').update({ statut: 'demande', decide_le: null }).eq('id', d.id);
      return NextResponse.json({ error: error.message }, { status: 500 });
    }
    let essaiId: string | null = null;
    if (d.essai_date) {
      const { data: es } = await admin.from('pension_entrees').insert({
        ...base, date_entree: d.essai_date, date_sortie_prevue: d.essai_date, notes: 'Essai avant le premier séjour', essai: true,
      }).select('id').single();
      essaiId = (es as { id?: string } | null)?.id ?? null;
    }
    await admin.from('pension_demandes').update({ entree_id: (ent as { id: string }).id, essai_entree_id: essaiId }).eq('id', d.id);
    await notifClient('pension_sejour_accepte', 'Séjour confirmé',
      `${d.animal_nom ?? 'Votre animal'} est attendu du ${fr(d.date_arrivee as string)} au ${fr(d.date_depart as string)}.${d.essai_date ? ` Essai le ${fr(d.essai_date)}.` : ''}`);
    return NextResponse.json({ ok: true });
  }

  // ── Annulation par le client ──
  if (b.action === 'annuler') {
    const { data } = await admin.from('pension_demandes').select('id, client_uid, statut, pro_uid, pro_profile_id, animal_nom').eq('id', b.demandeId ?? '').maybeSingle();
    const d = data as { id: string; client_uid: string; statut: string; pro_uid: string; pro_profile_id: string | null; animal_nom: string | null } | null;
    if (!d || d.client_uid !== auth.uid) return NextResponse.json({ error: 'Demande introuvable' }, { status: 404 });
    if (d.statut !== 'demande') return NextResponse.json({ error: 'Demande déjà traitée : contactez la pension.' }, { status: 409 });
    await admin.from('pension_demandes').update({ statut: 'annulee', decide_le: maintenant }).eq('id', d.id);
    await admin.from('notifications').insert({ uid: d.pro_uid, ...(d.pro_profile_id ? { profile_id: d.pro_profile_id } : {}), type: 'pension_demande_annulee',
      title: 'Demande de séjour annulée', body: `Le client a annulé sa demande de séjour pour ${d.animal_nom ?? 'son animal'}.`, data: { demande_id: d.id }, read: false });
    return NextResponse.json({ ok: true });
  }

  // ── Nouvelle demande du client ──
  const p = await pension(b.pensionProfileId ?? '');
  if (!p) return NextResponse.json({ error: 'Pension introuvable' }, { status: 404 });
  if (!b.animalId || !(await estProprio(auth.uid, b.animalId))) return NextResponse.json({ error: 'Choisissez un de vos animaux.' }, { status: 400 });
  if (!JOUR.test(b.dateArrivee ?? '') || !JOUR.test(b.dateDepart ?? '') || (b.dateDepart as string) < (b.dateArrivee as string)) {
    return NextResponse.json({ error: 'Dates de séjour invalides.' }, { status: 400 });
  }
  const aujourdhui = maintenant.slice(0, 10);
  if ((b.dateArrivee as string) < aujourdhui) return NextResponse.json({ error: 'La date d\'arrivée est passée.' }, { status: 400 });
  const premier = await premierSejour(p.uid, b.animalId);
  if (premier && typeof b.dejaVenu !== 'boolean') {
    return NextResponse.json({ error: 'Indiquez si votre animal est déjà venu dans cette pension.' }, { status: 400 });
  }
  // null = historique connu chez la pension (pas un nouveau pensionnaire).
  const nouveau: boolean | null = premier ? !b.dejaVenu : null;
  let essai: string | null = null;
  if (p.pension_essai_requis && nouveau) {
    if (!JOUR.test(b.essaiDate ?? '') || (b.essaiDate as string) >= (b.dateArrivee as string) || (b.essaiDate as string) < aujourdhui) {
      return NextResponse.json({ error: 'Cette pension demande un essai avant le premier séjour : choisissez une date d\'essai avant l\'arrivée.' }, { status: 400 });
    }
    essai = b.essaiDate as string;
  }
  const { data: an } = await admin.from('animaux').select('nom, espece').eq('id', b.animalId).maybeSingle();
  const a = an as { nom?: string | null; espece?: string | null } | null;
  let profil: string | null = null;
  if (b.profileId) {
    const { data } = await admin.from('user_profiles').select('id').eq('id', b.profileId).eq('uid', auth.uid).maybeSingle();
    profil = (data as { id?: string } | null)?.id ?? null;
  }
  const { data: dem, error } = await admin.from('pension_demandes').insert({
    pro_uid: p.uid, pro_profile_id: p.id, client_uid: auth.uid, client_profile_id: profil, animal_id: b.animalId,
    animal_nom: a?.nom ?? null, espece: a?.espece ?? null, date_arrivee: b.dateArrivee, date_depart: b.dateDepart,
    essai_date: essai, nouveau_pensionnaire: nouveau, hebergement: b.hebergement === 'box' || b.hebergement === 'pre' ? b.hebergement : null, message: (b.message ?? '').trim().slice(0, 1000) || null,
  }).select('id').single();
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  // La pension consulte la fiche de l'animal (santé, alimentation) pour préparer le séjour.
  const { data: acc } = await admin.from('animal_access').select('id, statut').eq('animal_id', b.animalId).eq('pro_profile_id', p.id).maybeSingle();
  const accRow = acc as { id: string; statut: string } | null;
  if (!accRow) {
    await admin.from('animal_access').insert({ animal_id: b.animalId, pro_profile_id: p.id, granted_by_profile_id: profil,
      permissions: ['read_basic', 'read_alimentation', 'read_health', 'write_notes'], statut: 'active', granted_at: maintenant });
  } else if (accRow.statut !== 'active') {
    await admin.from('animal_access').update({ statut: 'active', permissions: ['read_basic', 'read_alimentation', 'read_health', 'write_notes'], granted_at: maintenant }).eq('id', accRow.id);
  }
  await admin.from('notifications').insert({
    uid: p.uid, profile_id: p.id, type: 'pension_demande_sejour', title: 'Nouvelle demande de séjour',
    body: `${a?.nom ?? 'Un animal'}${nouveau === true ? ' (nouveau pensionnaire)' : nouveau === false ? ' (déjà venu selon le client)' : ''} : du ${fr(b.dateArrivee as string)} au ${fr(b.dateDepart as string)}${essai ? `, essai proposé le ${fr(essai)}` : ''}.`,
    data: { demande_id: (dem as { id: string }).id }, read: false,
  });
  return NextResponse.json({ ok: true, demandeId: (dem as { id: string }).id, essai_requis: !!essai });
}
