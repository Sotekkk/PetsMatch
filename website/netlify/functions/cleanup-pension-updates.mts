import { createClient } from '@supabase/supabase-js';

// Netlify Scheduled Function — purge quotidienne des nouvelles pension
// (photo/vidéo/note) de plus de 60 jours, pour éviter de saturer le
// stockage. Autonome (pas d'import depuis src/) car ce fichier est
// buildé dans un contexte séparé du reste de l'app Next.js.

const RETENTION_DAYS = 60;
const STORAGE_MARKER = '/storage/v1/object/public/media/';

async function cleanupPensionUpdates() {
  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );

  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - RETENTION_DAYS);

  const { data: rows, error } = await supabase.from('pension_updates')
    .select('id, photo_url, video_url')
    .lt('created_at', cutoff.toISOString());

  if (error) {
    console.error('cleanup-pension-updates: select failed', error);
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
  if (!rows || rows.length === 0) {
    console.log('cleanup-pension-updates: nothing to delete');
    return new Response(JSON.stringify({ deleted: 0 }), { status: 200 });
  }

  const paths: string[] = [];
  for (const row of rows as { photo_url: string | null; video_url: string | null }[]) {
    for (const url of [row.photo_url, row.video_url]) {
      if (!url) continue;
      const idx = url.indexOf(STORAGE_MARKER);
      if (idx !== -1) paths.push(decodeURIComponent(url.slice(idx + STORAGE_MARKER.length)));
    }
  }
  if (paths.length > 0) {
    const { error: storageErr } = await supabase.storage.from('media').remove(paths);
    if (storageErr) console.error('cleanup-pension-updates: storage remove failed', storageErr);
  }

  const ids = (rows as { id: string }[]).map(r => r.id);
  const { error: delErr } = await supabase.from('pension_updates').delete().in('id', ids);
  if (delErr) {
    console.error('cleanup-pension-updates: delete failed', delErr);
    return new Response(JSON.stringify({ error: delErr.message }), { status: 500 });
  }

  console.log(`cleanup-pension-updates: deleted ${ids.length} update(s) older than ${RETENTION_DAYS} days`);
  return new Response(JSON.stringify({ deleted: ids.length }), { status: 200 });
}

export default cleanupPensionUpdates;

export const config = {
  schedule: '@daily',
};
