import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';

// POST /api/cron/rdv-reminders
// Rappels de RDV (pro + client) à 48h / 24h / 1h / 15 min + rappels de cours
// collectifs. À déclencher toutes les 15 min par un planificateur externe
// (cron-job.org, GitHub Actions, cron Railway…).
// Protégé par CRON_SECRET (header Authorization: Bearer <secret>).
//
// Remplace l'ancienne Netlify Scheduled Function
// website/netlify/functions/send-rdv-reminders.mts.

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
);

interface Tier {
  hoursBefore: number;
  column: 'reminder_48h_sent' | 'reminder_24h_sent' | 'reminder_1h_sent' | 'reminder_15min_sent';
  label: string;
}

const TIERS: Tier[] = [
  { hoursBefore: 48,   column: 'reminder_48h_sent',   label: 'dans 48h' },
  { hoursBefore: 24,   column: 'reminder_24h_sent',   label: 'dans 24h' },
  { hoursBefore: 1,    column: 'reminder_1h_sent',    label: 'dans 1h' },
  { hoursBefore: 0.25, column: 'reminder_15min_sent', label: 'dans 15 min' },
];

interface RdvRow {
  id: string; pro_uid: string; client_uid: string;
  pro_profile_id: string | null; client_profile_id: string | null;
  date_heure: string; motif: string | null; animal_id: string | null;
}
interface CoursRow {
  id: string; pro_uid: string; pro_profile_id: string | null;
  titre: string; date_heure: string; lieu: string | null;
}

async function run(): Promise<number> {
  const now = new Date();
  let totalSent = 0;

  // ── RDV individuels ────────────────────────────────────────────────────────
  for (const tier of TIERS) {
    const threshold = new Date(now.getTime() + tier.hoursBefore * 3600_000);
    const { data: rows, error } = await supabase.from('rdv')
      .select('id, pro_uid, client_uid, pro_profile_id, client_profile_id, date_heure, motif, animal_id')
      .eq('statut', 'confirme')
      .eq(tier.column, false)
      .gt('date_heure', now.toISOString())
      .lte('date_heure', threshold.toISOString());
    if (error) { console.error(`rdv-reminders: select ${tier.label}`, error); continue; }
    if (!rows || rows.length === 0) continue;

    const rdvRows = rows as RdvRow[];
    const uids = [...new Set(rdvRows.flatMap(r => [r.pro_uid, r.client_uid]))];
    const animalIds = [...new Set(rdvRows.map(r => r.animal_id).filter(Boolean) as string[])];

    const [{ data: users }, { data: animaux }] = await Promise.all([
      supabase.from('users').select('uid, firstname, lastname, name_elevage').in('uid', uids),
      animalIds.length > 0
        ? supabase.from('animaux').select('id, nom').in('id', animalIds)
        : Promise.resolve({ data: [] as { id: string; nom: string | null }[] }),
    ]);

    const nameByUid: Record<string, string> = {};
    for (const u of (users ?? []) as { uid: string; firstname: string | null; lastname: string | null; name_elevage: string | null }[]) {
      nameByUid[u.uid] = u.name_elevage || [u.firstname, u.lastname].filter(Boolean).join(' ') || 'Quelqu\'un';
    }
    const animalNomById: Record<string, string> = {};
    for (const a of (animaux ?? []) as { id: string; nom: string | null }[]) {
      if (a.nom) animalNomById[a.id] = a.nom;
    }

    const notifRows: Record<string, unknown>[] = [];
    for (const rdv of rdvRows) {
      const heureStr = new Date(rdv.date_heure).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short', timeZone: 'Europe/Paris' });
      const animalTxt = rdv.animal_id ? animalNomById[rdv.animal_id] : undefined;
      const proNom = nameByUid[rdv.pro_uid] ?? 'votre professionnel';
      const clientNom = nameByUid[rdv.client_uid] ?? 'votre client';

      notifRows.push({
        uid: rdv.client_uid, type: 'rdv_rappel',
        title: `Rappel de RDV ${tier.label}`,
        body: `Votre RDV avec ${proNom}${animalTxt ? ` pour ${animalTxt}` : ''} est prévu le ${heureStr}.`,
        ...(rdv.client_profile_id ? { profile_id: rdv.client_profile_id } : {}),
        data: { rdv_id: rdv.id, ...(rdv.animal_id ? { animal_id: rdv.animal_id } : {}) }, read: false,
      });
      notifRows.push({
        uid: rdv.pro_uid, type: 'rdv_rappel',
        title: `Rappel de RDV ${tier.label}`,
        body: `Votre RDV avec ${clientNom}${animalTxt ? ` pour ${animalTxt}` : ''}${rdv.motif ? ` (${rdv.motif})` : ''} est prévu le ${heureStr}.`,
        ...(rdv.pro_profile_id ? { profile_id: rdv.pro_profile_id } : {}),
        data: { rdv_id: rdv.id }, read: false,
      });
    }

    if (notifRows.length > 0) {
      const { error: insErr } = await supabase.from('notifications').insert(notifRows);
      if (insErr) console.error(`rdv-reminders: notif insert ${tier.label}`, insErr);
    }
    const ids = rdvRows.map(r => r.id);
    const { error: updErr } = await supabase.from('rdv').update({ [tier.column]: true }).in('id', ids);
    if (updErr) console.error(`rdv-reminders: update ${tier.label}`, updErr);
    totalSent += ids.length;
  }

  // ── Cours collectifs (éducateur) ───────────────────────────────────────────
  for (const tier of TIERS) {
    const threshold = new Date(now.getTime() + tier.hoursBefore * 3600_000);
    const { data: rows, error } = await supabase.from('cours_collectifs')
      .select('id, pro_uid, pro_profile_id, titre, date_heure, lieu')
      .eq('statut', 'planifie')
      .eq(tier.column, false)
      .gt('date_heure', now.toISOString())
      .lte('date_heure', threshold.toISOString());
    if (error) { console.error(`rdv-reminders: cours select ${tier.label}`, error); continue; }
    if (!rows || rows.length === 0) continue;

    const coursRows = rows as CoursRow[];
    const coursIds = coursRows.map(c => c.id);
    const { data: participants } = await supabase.from('cours_collectifs_participants')
      .select('cours_id, client_uid, client_profile_id').in('cours_id', coursIds).eq('statut', 'inscrit');
    const participantsByCourse: Record<string, { client_uid: string; client_profile_id: string | null }[]> = {};
    for (const p of (participants ?? []) as { cours_id: string; client_uid: string; client_profile_id: string | null }[]) {
      (participantsByCourse[p.cours_id] ??= []).push({ client_uid: p.client_uid, client_profile_id: p.client_profile_id });
    }

    const notifRows: Record<string, unknown>[] = [];
    for (const cours of coursRows) {
      const heureStr = new Date(cours.date_heure).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short', timeZone: 'Europe/Paris' });
      const lieuTxt = cours.lieu ? ` (${cours.lieu})` : '';
      notifRows.push({
        uid: cours.pro_uid, type: 'cours_collectif_rappel',
        title: `Rappel de cours ${tier.label}`,
        body: `"${cours.titre}"${lieuTxt} est prévu le ${heureStr}.`,
        ...(cours.pro_profile_id ? { profile_id: cours.pro_profile_id } : {}),
        data: { cours_id: cours.id }, read: false,
      });
      for (const participant of participantsByCourse[cours.id] ?? []) {
        notifRows.push({
          uid: participant.client_uid, type: 'cours_collectif_rappel',
          title: `Rappel de cours ${tier.label}`,
          body: `"${cours.titre}"${lieuTxt} est prévu le ${heureStr}.`,
          ...(participant.client_profile_id ? { profile_id: participant.client_profile_id } : {}),
          data: { cours_id: cours.id }, read: false,
        });
      }
    }
    if (notifRows.length > 0) {
      const { error: insErr } = await supabase.from('notifications').insert(notifRows);
      if (insErr) console.error(`rdv-reminders: cours notif insert ${tier.label}`, insErr);
    }
    const { error: updErr } = await supabase.from('cours_collectifs').update({ [tier.column]: true }).in('id', coursIds);
    if (updErr) console.error(`rdv-reminders: cours update ${tier.label}`, updErr);
    totalSent += notifRows.length;
  }

  return totalSent;
}

export async function POST(req: NextRequest) {
  const secret = process.env.CRON_SECRET;
  if (secret) {
    const auth = req.headers.get('authorization') ?? '';
    if (auth !== `Bearer ${secret}`) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }
  }
  try {
    const sent = await run();
    return NextResponse.json({ ok: true, sent });
  } catch (e) {
    console.error('rdv-reminders: fatal', e);
    return NextResponse.json({ error: String(e) }, { status: 500 });
  }
}
