import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { requireUser } from '@/lib/server-auth';

// Pension — réservation de séjour par le client (demande à accepter).
// Plusieurs animaux : une demande (pension_demandes) par animal, mêmes dates,
// même client — la pension les voit regroupées et les accepte en une fois.
//  GET  ?pensionProfileId=&animalId= | &animalIds=a,b (client) → infos pension
//       (essai exigé, tarifs publics), premier séjour de chaque animal chez
//       elle ; avec &arrivee=&depart=&nb= → places libres (`dispo`).
//  POST { pensionProfileId, animalIds | animalId, dateArrivee, dateDepart,
//         dejaVenus?: { [animalId]: bool } | dejaVenu?, essaiDate?, message?, profileId? }
//       (client) → une demande par animal + accès à la fiche pour la pension.
//       Sans historique chez cette pension, le client dit si l'animal est déjà
//       venu ; l'essai n'est exigé que pour un nouveau pensionnaire. 409
//       { complet } si les hébergements n'ont plus assez de places pour le
//       nombre d'animaux.
//  POST { action: 'decider', demandeIds | demandeId, accepter, motif?, forcer? }
//       (pension) → séjours (+ essais) créés dans pension_entrees, ou refus ;
//       client prévenu une fois. Sans `forcer`, 409 { complet, jours } si un
//       jour du séjour dépasse la capacité des hébergements (enclos_chenil).
//  POST { action: 'annuler', demandeId } (client) → demande annulée.
const admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY ?? '', { auth: { persistSession: false } });
const JOUR = /^\d{4}-\d{2}-\d{2}$/;
const fr = (d: string) => new Date(`${d}T12:00:00`).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long' });
const liste = (noms: string[]) => noms.length <= 1 ? (noms[0] ?? '') : `${noms.slice(0, -1).join(', ')} et ${noms[noms.length - 1]}`;

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

/** Jours (nuits) du séjour où les hébergements n'ont pas `nb` places libres.
 *  Sans hébergement configuré (pension familiale), aucune limite connue. */
async function joursComplets(proUid: string, proProfileId: string | null, jours: string[], nb: number | ((jour: string) => number) = 1) {
  const besoin = (j: string) => (typeof nb === 'function' ? nb(j) : nb);
  const { data: lg } = await admin.from('enclos_chenil').select('capacite').eq('uid_eleveur', proUid);
  const logements = (lg ?? []) as { capacite: number | null }[];
  if (!logements.length || !jours.length) return { capacite: 0, complets: [] as { jour: string; occupes: number; restantes: number }[] };
  const capacite = logements.reduce((t, l) => t + (l.capacite ?? 1), 0);
  const tri = [...new Set(jours)].sort();
  const { data: en } = await admin.from('pension_entrees').select('date_entree, date_sortie_prevue, pro_profile_id')
    .eq('pro_uid', proUid).eq('statut', 'en_pension').lte('date_entree', tri[tri.length - 1]);
  const entrees = ((en ?? []) as { date_entree: string; date_sortie_prevue: string | null; pro_profile_id: string | null }[])
    .filter(e => !proProfileId || !e.pro_profile_id || e.pro_profile_id === proProfileId);
  const occupe = (e: { date_entree: string; date_sortie_prevue: string | null }, j: string) =>
    e.date_entree <= j && (!e.date_sortie_prevue || e.date_sortie_prevue > j || (e.date_sortie_prevue === e.date_entree && j === e.date_entree));
  const complets = tri.map(j => {
    const occupes = entrees.filter(e => occupe(e, j)).length;
    return { jour: j, occupes, restantes: Math.max(0, capacite - occupes) };
  }).filter(x => x.occupes + besoin(x.jour) > capacite);
  return { capacite, complets };
}

/** Message « complet » lisible (client comme pension). */
function texteComplet(capacite: number, complets: { jour: string; restantes: number }[], nb: number) {
  const jours = complets.slice(0, 5).map(c => fr(c.jour)).join(', ') + (complets.length > 5 ? '…' : '');
  const reste = Math.min(...complets.map(c => c.restantes));
  if (nb > 1 && reste > 0) {
    return `Plus assez de places pour ${nb} animaux ${complets.length > 1 ? 'les' : 'le'} ${jours} : ${reste} place${reste > 1 ? 's' : ''} libre${reste > 1 ? 's' : ''} (${capacite} au total).`;
  }
  return `Complet ${complets.length > 1 ? 'les' : 'le'} ${jours} (${capacite} place${capacite > 1 ? 's' : ''}).`;
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
  const sp = req.nextUrl.searchParams;
  const p = await pension(sp.get('pensionProfileId') ?? '');
  if (!p) return NextResponse.json({ error: 'Pension introuvable' }, { status: 404 });
  const animalId = sp.get('animalId');
  const animalIds = [...new Set((sp.get('animalIds') ?? '').split(',').map(s => s.trim()).filter(Boolean))].slice(0, 20);
  const tarifs = p.tarifs_pension && (p.tarifs_pension as { afficher_public?: boolean }).afficher_public ? p.tarifs_pension : null;
  const premiers: Record<string, boolean> = {};
  for (const id of animalIds) premiers[id] = await premierSejour(p.uid, id);
  // Places libres pour le nombre d'animaux choisis, aux dates demandées.
  const arrivee = sp.get('arrivee') ?? '', depart = sp.get('depart') ?? '';
  let dispo: { capacite: number; complets: { jour: string; restantes: number }[]; message: string | null } | null = null;
  if (JOUR.test(arrivee) && JOUR.test(depart) && depart >= arrivee) {
    const nb = Math.max(1, Math.min(20, Number(sp.get('nb')) || 1));
    const { capacite, complets } = await joursComplets(p.uid, p.id, nuitsDuSejour(arrivee, depart), nb);
    dispo = { capacite, complets: complets.map(c => ({ jour: c.jour, restantes: c.restantes })), message: complets.length ? texteComplet(capacite, complets, nb) : null };
  }
  return NextResponse.json({
    pension: { nom: p.nom ?? 'Pension', essai_requis: !!p.pension_essai_requis, essai_info: p.pension_essai_info ?? null, tarifs },
    premier_sejour: animalId ? await premierSejour(p.uid, animalId) : null,
    premiers, dispo,
  }, { headers: { 'Cache-Control': 'private, no-store' } });
}

type Demande = Record<string, string | null>;

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const b = await req.json().catch(() => ({})) as {
    action?: string; pensionProfileId?: string; animalId?: string; animalIds?: string[]; dateArrivee?: string; dateDepart?: string; essaiDate?: string | null;
    dejaVenu?: boolean | null; dejaVenus?: Record<string, boolean> | null; hebergement?: string | null;
    message?: string; profileId?: string | null; demandeId?: string; demandeIds?: string[]; accepter?: boolean; motif?: string; forcer?: boolean;
  };
  const maintenant = new Date().toISOString();

  // ── Décision de la pension (une demande ou un groupe : mêmes dates, même client) ──
  if (b.action === 'decider') {
    const ids = [...new Set([...(Array.isArray(b.demandeIds) ? b.demandeIds : []), ...(b.demandeId ? [b.demandeId] : [])].map(String))].slice(0, 20);
    if (!ids.length) return NextResponse.json({ error: 'Demande introuvable' }, { status: 404 });
    const { data } = await admin.from('pension_demandes').select('*').in('id', ids);
    const toutes = (data ?? []) as Demande[];
    if (!toutes.length) return NextResponse.json({ error: 'Demande introuvable' }, { status: 404 });
    const d0 = toutes[0];
    // Un seul client, une seule pension par décision groupée.
    if (toutes.some(d => d.pro_uid !== d0.pro_uid || d.client_uid !== d0.client_uid)) {
      return NextResponse.json({ error: 'Demandes de clients différents' }, { status: 400 });
    }
    if (!(await estGestionnaire(d0.pro_uid as string, auth.uid))) return NextResponse.json({ error: 'Réservé à la pension' }, { status: 403 });
    const ouvertes = toutes.filter(d => d.statut === 'demande');
    if (!ouvertes.length) return NextResponse.json({ error: 'Demande déjà traitée' }, { status: 409 });
    const noms = ouvertes.map(d => d.animal_nom ?? 'Animal');
    const notifClient = async (type: string, title: string, body: string) => admin.from('notifications').insert({
      uid: d0.client_uid, type, title, body, ...(d0.client_profile_id ? { profile_id: d0.client_profile_id } : {}),
      data: { demande_id: ouvertes[0].id, demande_ids: ouvertes.map(d => d.id), animalId: ouvertes[0].animal_id }, read: false,
    });
    const periode = (d: Demande) => `${fr(d.date_arrivee as string)} → ${fr(d.date_depart as string)}`;
    if (!b.accepter) {
      const motif = (b.motif ?? '').trim().slice(0, 500) || null;
      await admin.from('pension_demandes').update({ statut: 'refusee', motif_refus: motif, decide_le: maintenant })
        .in('id', ouvertes.map(d => d.id as string)).eq('statut', 'demande');
      await notifClient('pension_sejour_refuse', 'Séjour non accepté',
        `Votre demande de séjour pour ${liste(noms) || 'votre animal'} (${periode(ouvertes[0])}) n'a pas pu être acceptée.${motif ? ` ${motif}` : ''}`);
      return NextResponse.json({ ok: true });
    }
    // Places libres pour tous les animaux du groupe : la pension peut accepter
    // quand même (surbooking assumé).
    if (!b.forcer) {
      const parJour = new Map<string, number>();
      for (const d of ouvertes) {
        for (const j of new Set([...nuitsDuSejour(d.date_arrivee as string, d.date_depart as string), ...(d.essai_date ? [d.essai_date] : [])])) {
          parJour.set(j, (parJour.get(j) ?? 0) + 1);
        }
      }
      const { capacite, complets } = await joursComplets(d0.pro_uid as string, d0.pro_profile_id, [...parJour.keys()], j => parJour.get(j) ?? 1);
      if (complets.length) {
        return NextResponse.json({ error: texteComplet(capacite, complets, ouvertes.length), complet: true, capacite, jours: complets }, { status: 409 });
      }
    }
    // Verrou : un seul « Accepter » passe (double clic, deux appareils).
    const { data: verrou } = await admin.from('pension_demandes').update({ statut: 'acceptee', decide_le: maintenant })
      .in('id', ouvertes.map(d => d.id as string)).eq('statut', 'demande').select('id');
    const verrouillees = new Set(((verrou ?? []) as { id: string }[]).map(v => String(v.id)));
    const aTraiter = ouvertes.filter(d => verrouillees.has(String(d.id)));
    if (!aTraiter.length) return NextResponse.json({ error: 'Demande déjà traitée' }, { status: 409 });
    const { data: cp } = d0.client_profile_id
      ? await admin.from('user_profiles_complet').select('firstname, lastname, nom, phone_number, email_contact, rue, code_postal, ville').eq('id', d0.client_profile_id).maybeSingle()
      : { data: null };
    const c = cp as Record<string, string | null> | null;
    const acceptes: Demande[] = [];
    let erreur: string | null = null;
    for (const d of aTraiter) {
      // Séjour (et essai) dans le registre, avec la fiche et les coordonnées du client.
      const { data: an } = await admin.from('animaux').select('nom, espece, race, identification, photo_url').eq('id', d.animal_id as string).maybeSingle();
      const a = an as { nom?: string | null; espece?: string | null; race?: string | null; identification?: string | null; photo_url?: string | null } | null;
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
        await admin.from('pension_demandes').update({ statut: 'demande', decide_le: null }).eq('id', d.id as string);
        erreur = error.message;
        continue;
      }
      let essaiId: string | null = null;
      if (d.essai_date) {
        const { data: es } = await admin.from('pension_entrees').insert({
          ...base, date_entree: d.essai_date, date_sortie_prevue: d.essai_date, notes: 'Essai avant le premier séjour', essai: true,
        }).select('id').single();
        essaiId = (es as { id?: string } | null)?.id ?? null;
      }
      await admin.from('pension_demandes').update({ entree_id: (ent as { id: string }).id, essai_entree_id: essaiId }).eq('id', d.id as string);
      acceptes.push(d);
    }
    if (!acceptes.length) return NextResponse.json({ error: erreur ?? 'Acceptation impossible' }, { status: 500 });
    const n = acceptes.map(d => d.animal_nom ?? 'Votre animal');
    const essais = [...new Set(acceptes.map(d => d.essai_date).filter(Boolean) as string[])];
    await notifClient('pension_sejour_accepte', 'Séjour confirmé',
      `${liste(n)} ${n.length > 1 ? 'sont attendus' : 'est attendu'} du ${fr(acceptes[0].date_arrivee as string)} au ${fr(acceptes[0].date_depart as string)}.${essais.length ? ` Essai le ${essais.map(fr).join(', ')}.` : ''}`);
    return NextResponse.json({ ok: true, acceptees: acceptes.length, ...(erreur ? { erreur } : {}) });
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

  // ── Nouvelle demande du client (un ou plusieurs animaux) ──
  const p = await pension(b.pensionProfileId ?? '');
  if (!p) return NextResponse.json({ error: 'Pension introuvable' }, { status: 404 });
  const animalIds = [...new Set([...(Array.isArray(b.animalIds) ? b.animalIds : []), ...(b.animalId ? [b.animalId] : [])].map(String))].slice(0, 20);
  if (!animalIds.length) return NextResponse.json({ error: 'Choisissez un de vos animaux.' }, { status: 400 });
  for (const id of animalIds) {
    if (!(await estProprio(auth.uid, id))) return NextResponse.json({ error: 'Choisissez un de vos animaux.' }, { status: 400 });
  }
  if (!JOUR.test(b.dateArrivee ?? '') || !JOUR.test(b.dateDepart ?? '') || (b.dateDepart as string) < (b.dateArrivee as string)) {
    return NextResponse.json({ error: 'Dates de séjour invalides.' }, { status: 400 });
  }
  const aujourdhui = maintenant.slice(0, 10);
  if ((b.dateArrivee as string) < aujourdhui) return NextResponse.json({ error: 'La date d\'arrivée est passée.' }, { status: 400 });
  const { data: ans } = await admin.from('animaux').select('id, nom, espece').in('id', animalIds);
  const infosAnimal = new Map(((ans ?? []) as { id: string; nom: string | null; espece: string | null }[]).map(a => [String(a.id), a]));
  // Nouveau pensionnaire ? (null = historique connu chez la pension)
  const nouveaux = new Map<string, boolean | null>();
  for (const id of animalIds) {
    if (!(await premierSejour(p.uid, id))) { nouveaux.set(id, null); continue; }
    const v = b.dejaVenus && typeof b.dejaVenus[id] === 'boolean' ? b.dejaVenus[id] : b.dejaVenu;
    if (typeof v !== 'boolean') {
      return NextResponse.json({ error: `Indiquez si ${infosAnimal.get(id)?.nom ?? 'votre animal'} est déjà venu dans cette pension.` }, { status: 400 });
    }
    nouveaux.set(id, !v);
  }
  const avecEssai = !!p.pension_essai_requis && [...nouveaux.values()].some(v => v === true);
  let essai: string | null = null;
  if (avecEssai) {
    if (!JOUR.test(b.essaiDate ?? '') || (b.essaiDate as string) >= (b.dateArrivee as string) || (b.essaiDate as string) < aujourdhui) {
      return NextResponse.json({ error: 'Cette pension demande un essai avant le premier séjour : choisissez une date d\'essai avant l\'arrivée.' }, { status: 400 });
    }
    essai = b.essaiDate as string;
  }
  // Places libres pour tous les animaux (la pension tranche ensuite).
  const { capacite, complets } = await joursComplets(p.uid, p.id, nuitsDuSejour(b.dateArrivee as string, b.dateDepart as string), animalIds.length);
  if (complets.length) {
    return NextResponse.json({ error: `${texteComplet(capacite, complets, animalIds.length)} Choisissez d'autres dates${animalIds.length > 1 ? ' ou moins d\'animaux' : ''}.`, complet: true, jours: complets }, { status: 409 });
  }
  let profil: string | null = null;
  if (b.profileId) {
    const { data } = await admin.from('user_profiles').select('id').eq('id', b.profileId).eq('uid', auth.uid).maybeSingle();
    profil = (data as { id?: string } | null)?.id ?? null;
  }
  const message = (b.message ?? '').trim().slice(0, 1000) || null;
  const { data: dems, error } = await admin.from('pension_demandes').insert(animalIds.map(id => ({
    pro_uid: p.uid, pro_profile_id: p.id, client_uid: auth.uid, client_profile_id: profil, animal_id: id,
    animal_nom: infosAnimal.get(id)?.nom ?? null, espece: infosAnimal.get(id)?.espece ?? null, date_arrivee: b.dateArrivee, date_depart: b.dateDepart,
    essai_date: nouveaux.get(id) === true ? essai : null, nouveau_pensionnaire: nouveaux.get(id) ?? null,
    hebergement: b.hebergement === 'box' || b.hebergement === 'pre' ? b.hebergement : null, message,
  }))).select('id');
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  const demandeIds = ((dems ?? []) as { id: string }[]).map(d => d.id);
  // La pension consulte la fiche de chaque animal (santé, alimentation) pour préparer le séjour.
  const permissions = ['read_basic', 'read_alimentation', 'read_health', 'write_notes'];
  for (const id of animalIds) {
    const { data: acc } = await admin.from('animal_access').select('id, statut').eq('animal_id', id).eq('pro_profile_id', p.id).maybeSingle();
    const accRow = acc as { id: string; statut: string } | null;
    if (!accRow) {
      await admin.from('animal_access').insert({ animal_id: id, pro_profile_id: p.id, granted_by_profile_id: profil, permissions, statut: 'active', granted_at: maintenant });
    } else if (accRow.statut !== 'active') {
      await admin.from('animal_access').update({ statut: 'active', permissions, granted_at: maintenant }).eq('id', accRow.id);
    }
  }
  const nom = (id: string) => {
    const n = infosAnimal.get(id)?.nom ?? 'Un animal';
    const v = nouveaux.get(id);
    return `${n}${v === true ? ' (nouveau pensionnaire)' : v === false ? ' (déjà venu selon le client)' : ''}`;
  };
  await admin.from('notifications').insert({
    uid: p.uid, profile_id: p.id, type: 'pension_demande_sejour', title: animalIds.length > 1 ? `Nouvelle demande de séjour · ${animalIds.length} animaux` : 'Nouvelle demande de séjour',
    body: `${liste(animalIds.map(nom))} : du ${fr(b.dateArrivee as string)} au ${fr(b.dateDepart as string)}${essai ? `, essai proposé le ${fr(essai)}` : ''}.`,
    data: { demande_id: demandeIds[0], demande_ids: demandeIds }, read: false,
  });
  return NextResponse.json({ ok: true, demandeId: demandeIds[0], demandeIds, essai_requis: !!essai });
}
