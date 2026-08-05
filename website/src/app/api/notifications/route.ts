import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

// GET /api/notifications?uid=xxx&profileId=yyy
export async function GET(req: NextRequest) {
  const uid = req.nextUrl.searchParams.get('uid');
  const profileId = req.nextUrl.searchParams.get('profileId');
  if (!uid) return NextResponse.json([]);

  const { data } = await supabase
    .from('notifications')
    .select('*')
    .eq('uid', uid)
    .eq('read', false)
    .order('created_at', { ascending: false })
    .limit(50);

  // profile_id est la source la plus fiable (multi-profil) — s'il est
  // renseigné sur la notif, il prime sur profile_type (souvent absent à
  // la création). Sans ce filtre, une notif destinée à un autre profil du
  // même compte (ex. éleveur) apparaît aussi côté particulier/association.
  const filtered = (data ?? []).filter((n) => {
    if (n.profile_id) return n.profile_id === profileId;
    return true;
  }).slice(0, 20);

  return NextResponse.json(filtered);
}

// PATCH /api/notifications — marquer tout comme lu (uniquement les notifs du
// profil actif, pas celles des autres profils du même compte)
export async function PATCH(req: NextRequest) {
  const { uid, profileId } = await req.json().catch(() => ({})) as { uid?: string; profileId?: string };
  if (!uid) return NextResponse.json({ error: 'uid requis' }, { status: 400 });

  const { data } = await supabase
    .from('notifications')
    .select('id, profile_id')
    .eq('uid', uid)
    .eq('read', false);

  const ids = (data ?? [])
    .filter((n) => !n.profile_id || n.profile_id === profileId)
    .map((n) => n.id);

  if (ids.length > 0) {
    await supabase.from('notifications').update({ read: true }).in('id', ids);
  }

  return NextResponse.json({ success: true });
}

// POST /api/notifications — envoyer une notification (uid direct ou lookup par email)
export async function POST(req: NextRequest) {
  const { uid: directUid, email, type, title, body, data, profileType } =
    await req.json().catch(() => ({})) as {
      uid?: string; email?: string;
      type: string; title: string; body: string;
      data?: Record<string, unknown>;
      // Type de profil destinataire à résoudre (défaut 'particulier' — la
      // notion "particulier toujours présent" sert d'ancrage par défaut).
      profileType?: string;
    };

  let uid = directUid;
  if (!uid && email) {
    const { data: u } = await supabase.from('users').select('uid').eq('email', email).maybeSingle();
    uid = u?.uid;
  }
  if (!uid || !type || !title) return NextResponse.json({ error: 'params manquants' }, { status: 400 });

  const { data: prof } = await supabase.from('user_profiles').select('id')
    .eq('uid', uid).eq('profile_type', profileType || 'particulier').maybeSingle();

  await supabase.from('notifications').insert({
    uid, type, title, body: body ?? '', data: data ?? {},
    ...(prof?.id ? { profile_id: prof.id } : {}),
    read: false,
  });

  return NextResponse.json({ success: true });
}
