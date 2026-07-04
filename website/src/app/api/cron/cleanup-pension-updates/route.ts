import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

const RETENTION_DAYS = 60;
const STORAGE_MARKER = '/storage/v1/object/public/media/';

// POST /api/cron/cleanup-pension-updates
// Déclenche manuellement la purge des nouvelles pension (photo/vidéo/note) de
// plus de 60 jours (le Netlify Scheduled Function le fait chaque jour).
// Protégé par CRON_SECRET (header Authorization: Bearer <secret>)
export async function POST(req: NextRequest) {
  const secret = process.env.CRON_SECRET;
  if (secret) {
    const auth = req.headers.get('authorization') ?? '';
    if (auth !== `Bearer ${secret}`) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }
  }

  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - RETENTION_DAYS);

  const { data: rows, error } = await supabase.from('pension_updates')
    .select('id, photo_url, video_url')
    .lt('created_at', cutoff.toISOString());
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  if (!rows || rows.length === 0) return NextResponse.json({ deleted: 0 });

  const paths: string[] = [];
  for (const row of rows) {
    for (const url of [row.photo_url, row.video_url]) {
      if (!url) continue;
      const idx = url.indexOf(STORAGE_MARKER);
      if (idx !== -1) paths.push(decodeURIComponent(url.slice(idx + STORAGE_MARKER.length)));
    }
  }
  if (paths.length > 0) {
    await supabase.storage.from('media').remove(paths);
  }

  const ids = rows.map(r => r.id);
  const { error: delErr } = await supabase.from('pension_updates').delete().in('id', ids);
  if (delErr) return NextResponse.json({ error: delErr.message }, { status: 500 });

  return NextResponse.json({ deleted: ids.length });
}
