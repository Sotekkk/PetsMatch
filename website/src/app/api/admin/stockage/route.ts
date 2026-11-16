import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin, requireAdmin } from '../_lib/guard';

// Admin — onglet « Stockage » : taille de la base, plus grosses tables,
// fichiers par espace de stockage, détail des galeries photo (par galerie et
// par photographe) et relevés quotidiens pour la tendance.
// Fonctions SQL réservées à service_role (migration_admin_stockage.sql).
// Le relevé du jour est (re)pris à chaque ouverture, en plus de la Cloud
// Function quotidienne sendStockageReleve.
export async function GET(req: NextRequest) {
  const auth = await requireAdmin(req);
  if (auth instanceof NextResponse) return auth;

  const releve = await supabaseAdmin.rpc('admin_stockage_releve');
  if (releve.error) {
    return NextResponse.json({
      error: releve.error.message.includes('admin_stockage')
        ? 'Migration supabase/migration_admin_stockage.sql à passer.' : releve.error.message,
    }, { status: 500 });
  }
  const depuis = new Date(Date.now() - 180 * 86400000).toISOString().slice(0, 10);
  const [base, tables, buckets, galeries, releves] = await Promise.all([
    supabaseAdmin.rpc('admin_stockage_base'),
    supabaseAdmin.rpc('admin_stockage_tables', { p_limite: 25 }),
    supabaseAdmin.rpc('admin_stockage_buckets'),
    supabaseAdmin.rpc('admin_stockage_galeries'),
    supabaseAdmin.from('stockage_releves').select('jour, base_octets, buckets, galeries').gte('jour', depuis).order('jour'),
  ]);
  const err = [base, tables, buckets, galeries, releves].find(r => r.error)?.error;
  if (err) return NextResponse.json({ error: err.message }, { status: 500 });

  // Noms des photographes (profil pro de la galerie, sinon profil principal).
  type Gal = { album_id: string; pro_uid: string; pro_profile_id: string | null; titre: string | null; statut: string | null;
    created_at: string; livree_le: string | null; photos: number; apercus_octets: number; livraisons_octets: number; livraison_expire_le: string | null };
  const gals = (galeries.data ?? []) as Gal[];
  const pids = [...new Set(gals.map(g => g.pro_profile_id).filter((x): x is string => !!x))];
  const uids = [...new Set(gals.filter(g => !g.pro_profile_id).map(g => g.pro_uid))];
  const noms = new Map<string, string>();
  const nomDe = (p: { nom?: string | null; firstname?: string | null; lastname?: string | null }) =>
    (p.nom ?? '').trim() || `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim();
  for (let i = 0; i < pids.length; i += 200) {
    const { data } = await supabaseAdmin.from('user_profiles_complet').select('id, nom, firstname, lastname').in('id', pids.slice(i, i + 200));
    for (const p of (data ?? []) as { id: string; nom?: string | null; firstname?: string | null; lastname?: string | null }[]) noms.set(p.id, nomDe(p));
  }
  for (let i = 0; i < uids.length; i += 200) {
    const { data } = await supabaseAdmin.from('user_profiles').select('uid, nom, firstname, lastname, profile_type, is_main').in('uid', uids.slice(i, i + 200));
    for (const p of (data ?? []) as { uid: string; nom?: string | null; firstname?: string | null; lastname?: string | null; profile_type?: string | null; is_main?: boolean | null }[]) {
      if (p.profile_type === 'photographe' || !noms.has(`uid:${p.uid}`)) noms.set(`uid:${p.uid}`, nomDe(p));
    }
  }

  return NextResponse.json({
    base_octets: Number(base.data ?? 0),
    tables: tables.data ?? [],
    buckets: buckets.data ?? [],
    galeries: gals.map(g => ({
      ...g, photos: Number(g.photos), apercus_octets: Number(g.apercus_octets), livraisons_octets: Number(g.livraisons_octets),
      photographe: (g.pro_profile_id ? noms.get(g.pro_profile_id) : noms.get(`uid:${g.pro_uid}`)) || 'Photographe',
    })),
    releves: releves.data ?? [],
  });
}
