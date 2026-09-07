import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin, checkAdmin } from '../_lib/guard';

interface OwnerOut {
  profile_id: string | null;
  uid: string | null;
  nom: string;
  profile_type: string | null;
  role_proprio: string | null;
  statut: string | null;
  date_debut: string | null;
  date_fin: string | null;
}

interface AnimalOut {
  id: string;
  nom: string | null;
  espece: string | null;
  race: string | null;
  statut: string | null;
  photo_url: string | null;
  created_at: string | null;
  uid_eleveur: string | null;
  uid_proprietaire: string | null;
  owners: OwnerOut[];
  principal: OwnerOut | null;
  orphelin: boolean;
  legacy_uid_only: boolean;
}

function profileName(p: Record<string, unknown> | undefined): string {
  if (!p) return '—';
  const composed = `${(p.firstname as string) ?? ''} ${(p.lastname as string) ?? ''}`.trim();
  return (p.nom as string)?.trim() || composed || (p.profile_label as string) || '—';
}

// GET /api/admin/animaux?uid=<admin>&espece=&statut=&proprio_type=&orphelin=1&q=
export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  if (!(await checkAdmin(searchParams.get('uid')))) {
    return NextResponse.json({ error: 'Non autorisé' }, { status: 403 });
  }

  const espece = searchParams.get('espece');
  const statut = searchParams.get('statut');
  const proprioType = searchParams.get('proprio_type');
  const orphelinOnly = searchParams.get('orphelin') === '1';
  const q = (searchParams.get('q') ?? '').trim().toLowerCase();

  try {
    const [animauxRes, apRes] = await Promise.all([
      supabaseAdmin
        .from('animaux')
        .select('id, nom, espece, race, statut, photo_url, created_at, uid_eleveur, uid_proprietaire, profile_id, profile_id_eleveur')
        .order('created_at', { ascending: false }),
      supabaseAdmin
        .from('animaux_proprietes')
        .select('animal_id, profile_id_proprio, uid_proprio, role_proprio, statut, date_debut, date_fin'),
    ]);
    if (animauxRes.error) throw animauxRes.error;
    if (apRes.error) throw apRes.error;

    const animaux = (animauxRes.data ?? []) as Record<string, unknown>[];
    const ap = (apRes.data ?? []) as Record<string, unknown>[];

    // Résolution des profils propriétaires (par id) + fallback par uid.
    const profileIds = new Set<string>();
    const uids = new Set<string>();
    for (const r of ap) {
      if (r.profile_id_proprio) profileIds.add(r.profile_id_proprio as string);
      if (r.uid_proprio) uids.add(r.uid_proprio as string);
    }
    for (const a of animaux) {
      if (a.uid_eleveur) uids.add(a.uid_eleveur as string);
      if (a.uid_proprietaire) uids.add(a.uid_proprietaire as string);
    }

    const profByIdArr = profileIds.size
      ? (await supabaseAdmin.from('user_profiles')
          .select('id, uid, nom, firstname, lastname, profile_type, profile_label, is_main')
          .in('id', [...profileIds])).data ?? []
      : [];
    const mainByUidArr = uids.size
      ? (await supabaseAdmin.from('user_profiles')
          .select('id, uid, nom, firstname, lastname, profile_type, profile_label, is_main')
          .in('uid', [...uids]).eq('is_main', true)).data ?? []
      : [];
    const profById = new Map((profByIdArr as Record<string, unknown>[]).map(p => [p.id as string, p]));
    const mainByUid = new Map((mainByUidArr as Record<string, unknown>[]).map(p => [p.uid as string, p]));

    const apByAnimal = new Map<string, Record<string, unknown>[]>();
    for (const r of ap) {
      const k = r.animal_id as string;
      if (!apByAnimal.has(k)) apByAnimal.set(k, []);
      apByAnimal.get(k)!.push(r);
    }

    let rows: AnimalOut[] = animaux.map(a => {
      const links = apByAnimal.get(a.id as string) ?? [];
      const owners: OwnerOut[] = links.map(l => {
        const p: Record<string, unknown> | undefined =
          (l.profile_id_proprio ? profById.get(l.profile_id_proprio as string) : undefined)
          ?? (l.uid_proprio ? mainByUid.get(l.uid_proprio as string) : undefined);
        return {
          profile_id: (l.profile_id_proprio as string) ?? null,
          uid: (l.uid_proprio as string) ?? null,
          nom: profileName(p),
          profile_type: (p?.profile_type as string) ?? null,
          role_proprio: (l.role_proprio as string) ?? null,
          statut: (l.statut as string) ?? null,
          date_debut: (l.date_debut as string) ?? null,
          date_fin: (l.date_fin as string) ?? null,
        };
      });
      owners.sort((x, y) => (x.role_proprio === 'principal' ? -1 : 0) - (y.role_proprio === 'principal' ? -1 : 0));

      const legacyUid = (a.uid_eleveur as string) || (a.uid_proprietaire as string) || null;
      let principal = owners.find(o => o.role_proprio === 'principal' && (!o.date_fin)) ?? owners[0] ?? null;
      const orphelin = owners.length === 0;
      if (orphelin && legacyUid) {
        const p = mainByUid.get(legacyUid);
        principal = {
          profile_id: (p?.id as string) ?? null,
          uid: legacyUid,
          nom: profileName(p as Record<string, unknown> | undefined),
          profile_type: (p?.profile_type as string) ?? null,
          role_proprio: 'legacy',
          statut: null, date_debut: null, date_fin: null,
        };
      }

      return {
        id: a.id as string,
        nom: (a.nom as string) ?? null,
        espece: (a.espece as string) ?? null,
        race: (a.race as string) ?? null,
        statut: (a.statut as string) ?? null,
        photo_url: (a.photo_url as string) ?? null,
        created_at: (a.created_at as string) ?? null,
        uid_eleveur: (a.uid_eleveur as string) ?? null,
        uid_proprietaire: (a.uid_proprietaire as string) ?? null,
        owners,
        principal,
        orphelin,
        legacy_uid_only: orphelin && !!legacyUid,
      };
    });

    if (espece) rows = rows.filter(r => (r.espece ?? 'autre') === espece);
    if (statut) rows = rows.filter(r => r.statut === statut);
    if (orphelinOnly) rows = rows.filter(r => r.orphelin);
    if (proprioType) rows = rows.filter(r => r.principal?.profile_type === proprioType
      || r.owners.some(o => o.profile_type === proprioType));
    if (q) rows = rows.filter(r =>
      (r.nom ?? '').toLowerCase().includes(q)
      || (r.race ?? '').toLowerCase().includes(q)
      || (r.principal?.nom ?? '').toLowerCase().includes(q)
      || r.id.toLowerCase() === q);

    return NextResponse.json({ animaux: rows, total: rows.length });
  } catch (err) {
    console.error('[admin/animaux]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
