import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin, checkAdmin } from '../_lib/guard';

export async function POST(req: NextRequest) {
  try {
    const { uid, annonce_id, action } = await req.json() as {
      uid: string; annonce_id: string; action: 'approve' | 'reject' | 'suspend' | 'restore';
    };
    if (!uid || !annonce_id || !action) {
      return NextResponse.json({ error: 'Paramètres manquants' }, { status: 400 });
    }
    if (!(await checkAdmin(uid))) {
      return NextResponse.json({ error: 'Non autorisé' }, { status: 403 });
    }

    const statut =
      action === 'approve'  ? 'disponible' :
      action === 'reject'   ? 'refuse'     :
      action === 'suspend'  ? 'suspendu'   :
      action === 'restore'  ? 'disponible' : 'refuse';

    const update: Record<string, unknown> = { statut };
    if (action === 'restore') update.is_suspect = false;

    const { error } = await supabaseAdmin.from('annonces').update(update).eq('id', annonce_id);
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });

    return NextResponse.json({ ok: true });
  } catch (err) {
    console.error('[admin/annonces]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}

// GET /api/admin/annonces
//   ?type=suspectes|suspendues                    → files de modération (existant)
//   ?type=toutes&uid=<admin>&...filtres&page=0    → vue complète filtrée
export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const type = searchParams.get('type') ?? 'suspectes';

  const cols = 'id, titre, espece, espece_autre, race, uid_eleveur, nom_eleveur, ville_eleveur, ' +
    'departement_eleveur, created_at, expire_at, photos, type, type_vente, profil_source, ' +
    'is_suspect, suspect_reasons, statut, vues, prix, prix_min_portee, prix_max_portee, boost_until';

  if (type === 'toutes') {
    if (!(await checkAdmin(searchParams.get('uid')))) {
      return NextResponse.json({ error: 'Non autorisé' }, { status: 403 });
    }
    const page = Math.max(0, parseInt(searchParams.get('page') ?? '0', 10));
    const pageSize = 60;
    const sort = searchParams.get('sort') ?? 'created_at';
    const q = (searchParams.get('q') ?? '').trim();

    let query = supabaseAdmin.from('annonces')
      .select(cols, { count: 'exact' })
      .order(sort === 'vues' ? 'vues' : 'created_at', { ascending: false })
      .range(page * pageSize, page * pageSize + pageSize - 1);

    const espece = searchParams.get('espece');
    const statut = searchParams.get('statut');
    const typeVente = searchParams.get('type_vente');
    const profilSource = searchParams.get('profil_source');
    const eleveur = searchParams.get('eleveur');
    const depuis = searchParams.get('depuis');
    if (espece) query = query.eq('espece', espece);
    if (statut) query = query.eq('statut', statut);
    if (typeVente) query = query.eq('type_vente', typeVente);
    if (profilSource) query = query.eq('profil_source', profilSource);
    if (eleveur) query = query.or(`uid_eleveur.eq.${eleveur},nom_eleveur.ilike.%${eleveur}%`);
    if (depuis) query = query.gte('created_at', depuis);
    if (q) query = query.or(`titre.ilike.%${q}%,race.ilike.%${q}%,nom_eleveur.ilike.%${q}%`);

    const { data, error, count } = await query;
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });
    return NextResponse.json({ annonces: data ?? [], total: count ?? 0, page, pageSize });
  }

  let query = supabaseAdmin.from('annonces')
    .select(cols)
    .order('created_at', { ascending: false })
    .limit(100);

  if (type === 'suspectes') {
    query = query.eq('is_suspect', true).in('statut', ['disponible', 'en_attente', 'pause']);
  } else if (type === 'suspendues') {
    query = query.in('statut', ['suspendu', 'refuse']);
  }

  const { data, error } = await query;
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ annonces: data ?? [] });
}
