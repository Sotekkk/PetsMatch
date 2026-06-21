import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

// POST /api/contracts/expire
// Déclenche manuellement l'expiration des contrats (pg_cron le fait chaque nuit à 2h UTC)
// Protégé par CRON_SECRET (header Authorization: Bearer <secret>)
export async function POST(req: NextRequest) {
  const secret = process.env.CRON_SECRET;
  if (secret) {
    const auth = req.headers.get('authorization') ?? '';
    if (auth !== `Bearer ${secret}`) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }
  }

  const { data, error } = await supabase.rpc('expire_contracts');
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });

  return NextResponse.json({ expired: data ?? 0 });
}
