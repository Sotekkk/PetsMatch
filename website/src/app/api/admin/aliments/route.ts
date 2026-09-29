import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin, requireAdmin } from '../_lib/guard';

// /api/admin/aliments — catalogue marques_aliments (admin, jeton Firebase requis).
//   GET    ?q=&espece=&type=&age=&source=officiel|membres&estime=1  → liste + nb de fiches qui l'utilisent
//   POST   { ...champs }            → nouvel aliment officiel (ajoute_par_uid NULL)
//   PATCH  { id, ...champs }        → modification
//   DELETE ?id=                     → suppression ; les fiches alimentations qui
//          l'utilisaient gardent leur copie (marque, gamme, densité) — seul le
//          lien marque_id est détaché (pas de clé étrangère sur ce lien).

const COLS = 'id, marque, gamme, espece, taille_race, age_categorie, type_aliment, densite_kcal_100g, doses, notes, ajoute_par_uid, kcal_estime, formule_sterilise, created_at';

// Seuls ces champs sont modifiables depuis l'admin (jamais id / created_at /
// ajoute_par_uid, qui restent la trace de l'auteur).
const EDITABLE = ['marque', 'gamme', 'espece', 'taille_race', 'age_categorie', 'type_aliment',
  'densite_kcal_100g', 'doses', 'notes', 'kcal_estime', 'formule_sterilise'] as const;

function pickEditable(body: Record<string, unknown>): Record<string, unknown> | string {
  const out: Record<string, unknown> = {};
  for (const k of EDITABLE) if (k in body) out[k] = body[k];
  if ('marque' in out && !String(out.marque ?? '').trim()) return 'La marque est obligatoire.';
  if ('gamme' in out && !String(out.gamme ?? '').trim()) return 'Le nom du produit est obligatoire.';
  if ('densite_kcal_100g' in out && out.densite_kcal_100g !== null) {
    const v = Number(out.densite_kcal_100g);
    if (!Number.isFinite(v) || v < 20 || v > 700) return 'kcal/100 g invalide (entre 20 et 700).';
    out.densite_kcal_100g = v;
  }
  if ('doses' in out) {
    if (!Array.isArray(out.doses)) return 'Tableau de doses invalide.';
    out.doses = (out.doses as { poids_kg?: unknown; grammes?: unknown }[])
      .map(d => ({ poids_kg: Number(d.poids_kg), grammes: Number(d.grammes) }))
      .filter(d => d.poids_kg > 0 && d.grammes > 0)
      .sort((a, b) => a.poids_kg - b.poids_kg);
  }
  for (const k of ['marque', 'gamme', 'notes', 'taille_race'] as const) {
    if (k in out && typeof out[k] === 'string') out[k] = (out[k] as string).trim() || null;
  }
  return out;
}

export async function GET(req: NextRequest) {
  const auth = await requireAdmin(req);
  if (auth instanceof NextResponse) return auth;
  const sp = req.nextUrl.searchParams;
  let query = supabaseAdmin.from('marques_aliments').select(COLS)
    .order('marque').order('gamme').limit(1000);
  const q = (sp.get('q') ?? '').trim().replace(/[,()]/g, ' ');
  if (q) query = query.or(`marque.ilike.%${q}%,gamme.ilike.%${q}%`);
  if (sp.get('espece')) query = query.eq('espece', sp.get('espece')!);
  if (sp.get('type')) query = query.eq('type_aliment', sp.get('type')!);
  if (sp.get('age')) query = query.eq('age_categorie', sp.get('age')!);
  if (sp.get('source') === 'membres') query = query.not('ajoute_par_uid', 'is', null);
  if (sp.get('source') === 'officiel') query = query.is('ajoute_par_uid', null);
  if (sp.get('estime') === '1') query = query.eq('kcal_estime', true);
  const { data, error } = await query;
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });

  // Nombre de fiches qui utilisent chaque aliment. Pas de .in(ids) : avec tout
  // le catalogue (500+ id) l'URL devient trop longue et la requête échoue ;
  // les fiches liées à un aliment sont peu nombreuses → lues d'un coup.
  const usage: Record<string, number> = {};
  const { data: refs } = await supabaseAdmin.from('alimentations').select('marque_id').not('marque_id', 'is', null);
  for (const r of refs ?? []) { const id = r.marque_id as string; usage[id] = (usage[id] ?? 0) + 1; }
  return NextResponse.json({ aliments: (data ?? []).map(r => ({ ...r, nb_fiches: usage[r.id as string] ?? 0 })) });
}

export async function POST(req: NextRequest) {
  const auth = await requireAdmin(req);
  if (auth instanceof NextResponse) return auth;
  const fields = pickEditable(await req.json().catch(() => ({})));
  if (typeof fields === 'string') return NextResponse.json({ error: fields }, { status: 400 });
  if (!fields.marque || !fields.gamme || !fields.espece) {
    return NextResponse.json({ error: 'Marque, nom du produit et espèce sont obligatoires.' }, { status: 400 });
  }
  const { data, error } = await supabaseAdmin.from('marques_aliments')
    .insert({ ...fields, ajoute_par_uid: null }).select(COLS).single();
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ aliment: { ...data, nb_fiches: 0 } });
}

export async function PATCH(req: NextRequest) {
  const auth = await requireAdmin(req);
  if (auth instanceof NextResponse) return auth;
  const body = await req.json().catch(() => ({})) as Record<string, unknown>;
  const id = typeof body.id === 'string' ? body.id : null;
  if (!id) return NextResponse.json({ error: 'id requis' }, { status: 400 });
  const fields = pickEditable(body);
  if (typeof fields === 'string') return NextResponse.json({ error: fields }, { status: 400 });
  const { data, error } = await supabaseAdmin.from('marques_aliments')
    .update(fields).eq('id', id).select(COLS).single();
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ aliment: data });
}

export async function DELETE(req: NextRequest) {
  const auth = await requireAdmin(req);
  if (auth instanceof NextResponse) return auth;
  const id = req.nextUrl.searchParams.get('id');
  if (!id) return NextResponse.json({ error: 'id requis' }, { status: 400 });
  await supabaseAdmin.from('alimentations').update({ marque_id: null }).eq('marque_id', id);
  const { error } = await supabaseAdmin.from('marques_aliments').delete().eq('id', id);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ ok: true });
}
