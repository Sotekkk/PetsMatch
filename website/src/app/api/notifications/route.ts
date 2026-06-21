import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

// GET /api/notifications?uid=xxx
export async function GET(req: NextRequest) {
  const uid = req.nextUrl.searchParams.get('uid');
  if (!uid) return NextResponse.json([]);

  const { data } = await supabase
    .from('notifications')
    .select('*')
    .eq('uid', uid)
    .eq('read', false)
    .order('created_at', { ascending: false })
    .limit(20);

  return NextResponse.json(data ?? []);
}

// PATCH /api/notifications — marquer tout comme lu
export async function PATCH(req: NextRequest) {
  const { uid } = await req.json().catch(() => ({})) as { uid?: string };
  if (!uid) return NextResponse.json({ error: 'uid requis' }, { status: 400 });

  await supabase
    .from('notifications')
    .update({ read: true })
    .eq('uid', uid)
    .eq('read', false);

  return NextResponse.json({ success: true });
}
