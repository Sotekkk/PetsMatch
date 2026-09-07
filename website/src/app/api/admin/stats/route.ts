import { NextRequest, NextResponse } from 'next/server';
import { supabaseAdmin, checkAdmin } from '../_lib/guard';

// GET /api/admin/stats?uid=<admin> — consommation par uid & par profil.
export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url);
  if (!(await checkAdmin(searchParams.get('uid')))) {
    return NextResponse.json({ error: 'Non autorisé' }, { status: 403 });
  }
  try {
    const { data, error } = await supabaseAdmin.rpc('admin_consommation_stats');
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });
    return NextResponse.json(data ?? { by_uid: [], by_profile: [] });
  } catch (err) {
    console.error('[admin/stats]', err);
    return NextResponse.json({ error: 'Erreur serveur' }, { status: 500 });
  }
}
