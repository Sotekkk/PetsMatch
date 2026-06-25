import { NextRequest, NextResponse } from 'next/server';
import { supabase } from '@/lib/supabase';

// POST /api/annonces/stats — tracker une vue
export async function POST(req: NextRequest) {
  try {
    const { annonceId, bebeIndex, departement, unique: isUnique } = await req.json() as {
      annonceId: string; bebeIndex?: number; departement?: string; unique?: boolean;
    };
    if (!annonceId) return NextResponse.json({ error: 'annonceId requis' }, { status: 400 });

    // Vue de l'annonce
    await supabase.rpc('increment_annonce_view', {
      p_annonce_id:  annonceId,
      p_departement: departement ?? 'inconnu',
      p_unique:      isUnique ?? false,
    });

    // Vue d'un chiot de portée
    if (bebeIndex !== undefined && bebeIndex >= 0) {
      await supabase.rpc('increment_portee_view', {
        p_annonce_id: annonceId,
        p_bebe_index: bebeIndex,
      });
    }

    return NextResponse.json({ ok: true });
  } catch (err) {
    return NextResponse.json({ error: String(err) }, { status: 500 });
  }
}

// GET /api/annonces/stats?annonceId=...&period=7|30 — récupérer les stats
export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  const annonceId = searchParams.get('annonceId');
  const period    = parseInt(searchParams.get('period') ?? '30', 10);

  if (!annonceId) return NextResponse.json({ error: 'annonceId requis' }, { status: 400 });

  const since = new Date();
  since.setDate(since.getDate() - period);
  const sinceStr = since.toISOString().split('T')[0];

  const [dailyRes, geoRes, porteeRes, annonceRes, likesRes] = await Promise.all([
    supabase.from('annonces_stats_daily')
      .select('date, vues, visiteurs, contacts, favoris, partages')
      .eq('annonce_id', annonceId)
      .gte('date', sinceStr)
      .order('date', { ascending: true }),

    supabase.from('annonces_views_geo')
      .select('departement, vues')
      .eq('annonce_id', annonceId)
      .order('vues', { ascending: false })
      .limit(10),

    supabase.from('animaux_portee_stats')
      .select('bebe_index, vues, favoris')
      .eq('annonce_id', annonceId)
      .gte('date', sinceStr),

    supabase.from('annonces')
      .select('vues, contacts, titre, espece, race, type, type_vente, photos, prix, prix_min_portee, prix_max_portee, created_at, statut')
      .eq('id', annonceId)
      .single(),

    supabase.from('likes')
      .select('id', { count: 'exact', head: true })
      .eq('annonce_id', annonceId),
  ]);

  const daily = dailyRes.data ?? [];
  const geo   = geoRes.data ?? [];
  const porteeRaw = porteeRes.data ?? [];
  const annonce   = annonceRes.data;
  const totalLikes = likesRes.count ?? 0;

  // Agréger stats par bébé
  const porteeMap: Record<number, { vues: number; favoris: number }> = {};
  for (const row of porteeRaw) {
    const i = row.bebe_index as number;
    if (!porteeMap[i]) porteeMap[i] = { vues: 0, favoris: 0 };
    porteeMap[i].vues    += row.vues    as number;
    porteeMap[i].favoris += row.favoris as number;
  }

  const totalVues     = daily.reduce((s, d) => s + ((d.vues as number) ?? 0), 0)     || (annonce?.vues ?? 0);
  const totalContacts = daily.reduce((s, d) => s + ((d.contacts as number) ?? 0), 0) || (annonce?.contacts ?? 0);
  const totalFavoris  = totalLikes;
  const tauxConversion = totalVues > 0 ? Math.round((totalContacts / totalVues) * 100) : 0;
  const tauxInteret    = totalVues > 0 ? Math.round((totalFavoris  / totalVues) * 100) : 0;

  // Classement dans la race (annonces similaires en ligne)
  const { count: totalRace } = await supabase.from('annonces')
    .select('id', { count: 'exact', head: true })
    .eq('espece', annonce?.espece ?? '')
    .eq('race',   annonce?.race   ?? '')
    .eq('statut', 'disponible');

  const { count: betterRace } = await supabase.from('annonces')
    .select('id', { count: 'exact', head: true })
    .eq('espece', annonce?.espece ?? '')
    .eq('race',   annonce?.race   ?? '')
    .eq('statut', 'disponible')
    .gt('vues', annonce?.vues ?? 0);

  const classement = (totalRace ?? 0) > 0
    ? { position: (betterRace ?? 0) + 1, total: totalRace ?? 0 }
    : null;

  // Score attractivité (0-100)
  const scoreAttractif = Math.min(100, Math.round(
    (tauxConversion * 0.4 + tauxInteret * 0.3 + Math.min(100, ((annonce?.vues ?? 0) / 10)) * 0.3)
  ));

  return NextResponse.json({
    annonce,
    totalVues,
    totalContacts,
    totalFavoris,
    tauxConversion,
    tauxInteret,
    scoreAttractif,
    classement,
    daily,
    geo,
    portee: Object.entries(porteeMap).map(([idx, s]) => ({ index: Number(idx), ...s }))
      .sort((a, b) => b.vues - a.vues),
  });
}
