import { createClient } from '@supabase/supabase-js';

// Netlify Scheduled Function — envoie des rappels de RDV (côté pro ET
// côté client) à 48h, 24h, 1h et 15 min avant le rendez-vous. Autonome
// (pas d'import depuis src/) car ce fichier est buildé dans un contexte
// séparé du reste de l'app Next.js. Tourne toutes les 15 min pour
// couvrir le palier le plus fin.

interface Tier {
  hoursBefore: number;
  column: 'reminder_48h_sent' | 'reminder_24h_sent' | 'reminder_1h_sent' | 'reminder_15min_sent';
  label: string;
}

const TIERS: Tier[] = [
  { hoursBefore: 48,    column: 'reminder_48h_sent',   label: 'dans 48h' },
  { hoursBefore: 24,    column: 'reminder_24h_sent',   label: 'dans 24h' },
  { hoursBefore: 1,     column: 'reminder_1h_sent',    label: 'dans 1h' },
  { hoursBefore: 0.25,  column: 'reminder_15min_sent', label: 'dans 15 min' },
];

interface RdvRow {
  id: string;
  pro_uid: string;
  client_uid: string;
  date_heure: string;
  motif: string | null;
  animal_id: string | null;
}

interface CoursRow {
  id: string;
  pro_uid: string;
  titre: string;
  date_heure: string;
  lieu: string | null;
}

async function sendRdvReminders() {
  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );

  const now = new Date();
  let totalSent = 0;

  for (const tier of TIERS) {
    const threshold = new Date(now.getTime() + tier.hoursBefore * 3600_000);

    const { data: rows, error } = await supabase.from('rdv')
      .select('id, pro_uid, client_uid, date_heure, motif, animal_id')
      .eq('statut', 'confirme')
      .eq(tier.column, false)
      .gt('date_heure', now.toISOString())
      .lte('date_heure', threshold.toISOString());

    if (error) {
      console.error(`send-rdv-reminders: select failed for tier ${tier.label}`, error);
      continue;
    }
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
      const dt = new Date(rdv.date_heure);
      const heureStr = dt.toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short', timeZone: 'Europe/Paris' });
      const animalTxt = rdv.animal_id ? animalNomById[rdv.animal_id] : undefined;
      const proNom = nameByUid[rdv.pro_uid] ?? 'votre professionnel';
      const clientNom = nameByUid[rdv.client_uid] ?? 'votre client';

      notifRows.push({
        uid: rdv.client_uid, type: 'rdv_rappel',
        title: `Rappel de RDV ${tier.label}`,
        body: `Votre RDV avec ${proNom}${animalTxt ? ` pour ${animalTxt}` : ''} est prévu le ${heureStr}.`,
        data: { rdv_id: rdv.id }, read: false,
      });
      notifRows.push({
        uid: rdv.pro_uid, type: 'rdv_rappel',
        title: `Rappel de RDV ${tier.label}`,
        body: `Votre RDV avec ${clientNom}${animalTxt ? ` pour ${animalTxt}` : ''}${rdv.motif ? ` (${rdv.motif})` : ''} est prévu le ${heureStr}.`,
        data: { rdv_id: rdv.id }, read: false,
      });
    }

    if (notifRows.length > 0) {
      const { error: insErr } = await supabase.from('notifications').insert(notifRows);
      if (insErr) console.error(`send-rdv-reminders: notification insert failed for tier ${tier.label}`, insErr);
    }

    const ids = rdvRows.map(r => r.id);
    const { error: updErr } = await supabase.from('rdv').update({ [tier.column]: true }).in('id', ids);
    if (updErr) console.error(`send-rdv-reminders: update failed for tier ${tier.label}`, updErr);

    totalSent += ids.length;
    console.log(`send-rdv-reminders: sent ${ids.length} reminder(s) for tier ${tier.label}`);
  }

  // ── Cours collectifs (éducateur) — même mécanique, un cours a plusieurs
  // participants inscrits en plus du pro, contrairement à un rdv individuel.
  for (const tier of TIERS) {
    const threshold = new Date(now.getTime() + tier.hoursBefore * 3600_000);

    const { data: rows, error } = await supabase.from('cours_collectifs')
      .select('id, pro_uid, titre, date_heure, lieu')
      .eq('statut', 'planifie')
      .eq(tier.column, false)
      .gt('date_heure', now.toISOString())
      .lte('date_heure', threshold.toISOString());

    if (error) {
      console.error(`send-rdv-reminders: cours_collectifs select failed for tier ${tier.label}`, error);
      continue;
    }
    if (!rows || rows.length === 0) continue;

    const coursRows = rows as CoursRow[];
    const coursIds = coursRows.map(c => c.id);

    const { data: participants } = await supabase.from('cours_collectifs_participants')
      .select('cours_id, client_uid').in('cours_id', coursIds).eq('statut', 'inscrit');
    const participantsByCourse: Record<string, string[]> = {};
    for (const p of (participants ?? []) as { cours_id: string; client_uid: string }[]) {
      (participantsByCourse[p.cours_id] ??= []).push(p.client_uid);
    }

    const notifRows: Record<string, unknown>[] = [];
    for (const cours of coursRows) {
      const dt = new Date(cours.date_heure);
      const heureStr = dt.toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short', timeZone: 'Europe/Paris' });
      const lieuTxt = cours.lieu ? ` (${cours.lieu})` : '';

      notifRows.push({
        uid: cours.pro_uid, type: 'cours_collectif_rappel',
        title: `Rappel de cours ${tier.label}`,
        body: `"${cours.titre}"${lieuTxt} est prévu le ${heureStr}.`,
        data: { cours_id: cours.id }, read: false,
      });
      for (const clientUid of participantsByCourse[cours.id] ?? []) {
        notifRows.push({
          uid: clientUid, type: 'cours_collectif_rappel',
          title: `Rappel de cours ${tier.label}`,
          body: `"${cours.titre}"${lieuTxt} est prévu le ${heureStr}.`,
          data: { cours_id: cours.id }, read: false,
        });
      }
    }

    if (notifRows.length > 0) {
      const { error: insErr } = await supabase.from('notifications').insert(notifRows);
      if (insErr) console.error(`send-rdv-reminders: cours_collectifs notification insert failed for tier ${tier.label}`, insErr);
    }

    const { error: updErr } = await supabase.from('cours_collectifs').update({ [tier.column]: true }).in('id', coursIds);
    if (updErr) console.error(`send-rdv-reminders: cours_collectifs update failed for tier ${tier.label}`, updErr);

    totalSent += notifRows.length;
    console.log(`send-rdv-reminders: sent ${notifRows.length} cours_collectifs reminder(s) for tier ${tier.label}`);
  }

  return new Response(JSON.stringify({ rdvRemindered: totalSent }), { status: 200 });
}

export default sendRdvReminders;

export const config = {
  schedule: '*/15 * * * *',
};
