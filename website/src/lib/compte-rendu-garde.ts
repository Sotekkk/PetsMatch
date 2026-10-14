// Pet-sitting — compte rendu express d'une promenade / visite (miroir appli :
// lib/pages/pro/visite_rapport_sheet.dart). Message généré à partir des
// éléments cochés, enregistré dans pension_updates (rattaché au RDV si la
// migration migration_garde_compte_rendu_express.sql est passée) + la
// notification existante au propriétaire. Aucun PDF.
import { supabase } from '@/lib/supabase';
import { compressImage } from '@/lib/compress-image';
import { gardePrestationKey } from '@/lib/garde-facturation';

export const ITEMS_PROMENADE: { key: string; label: string }[] = [
  { key: 'ok', label: "Tout s'est bien passé" },
  { key: 'besoins', label: 'Besoins effectués' },
  { key: 'eau', label: 'Eau proposée' },
  { key: 'jeux', label: 'Jeux / activité' },
];
export const ITEMS_VISITE: { key: string; label: string }[] = [
  { key: 'ok', label: "Tout s'est bien passé" },
  { key: 'repas', label: 'Repas donné' },
  { key: 'eau', label: 'Eau renouvelée' },
  { key: 'litiere', label: 'Litière / besoins' },
  { key: 'consignes', label: 'Consignes effectuées' },
  { key: 'medicament', label: 'Médicament donné selon les consignes' },
];

/** Famille de prestation (filtres agenda / tableau de bord) — miroir appli familleGarde. */
export function familleGarde(motif?: string | null): 'garde' | 'promenade' | 'visite' | 'autre' {
  const k = gardePrestationKey(motif);
  if (k === 'garde_journee') return 'garde';
  if (k.startsWith('promenade')) return 'promenade';
  if (k === 'visite') return 'visite';
  return 'autre';
}
export const FAMILLES_GARDE: { key: string; label: string }[] = [
  { key: 'garde', label: 'Gardes' },
  { key: 'promenade', label: 'Promenades' },
  { key: 'visite', label: 'Visites à domicile' },
  { key: 'autre', label: 'Autres' },
];

export function estPromenade(motif?: string | null) {
  const m = (motif ?? '').toLowerCase();
  return m.includes('promenade') || m.includes('balade');
}

const fin = (t: string) => (t.trim().endsWith('.') ? t.trim() : `${t.trim()}.`);

/** Message lisible généré (« La promenade de Luna est terminée. Tout s'est bien passé… »). */
export function messageCompteRendu(o: {
  promenade: boolean; animal: string; items: Set<string>;
  comportement?: string; incident?: string; note?: string; nbPhotos?: number;
}): string {
  const a = o.animal || "l'animal";
  const sujet = o.animal || "L'animal";
  const p: string[] = [o.promenade ? `La promenade de ${a} est terminée.` : `La visite pour ${a} est terminée.`];
  if (o.items.has('ok')) p.push("Tout s'est bien passé.");
  if (o.items.has('besoins')) p.push(`${sujet} a fait ses besoins.`);
  if (o.items.has('repas')) p.push('Le repas a été donné.');
  if (o.items.has('eau')) p.push(o.promenade ? "De l'eau a été proposée." : "L'eau a été renouvelée.");
  if (o.items.has('litiere')) p.push('La litière et les besoins ont été gérés.');
  if (o.items.has('jeux')) p.push(`${sujet} a profité de jeux et d'activité.`);
  if (o.items.has('consignes')) p.push('Vos consignes ont été suivies.');
  if (o.items.has('medicament')) p.push('Le traitement a été donné selon vos consignes.');
  if (o.comportement?.trim()) p.push(`Comportement : ${fin(o.comportement)}`);
  if (o.incident?.trim()) p.push(`Incident signalé : ${fin(o.incident)}`);
  if (o.note?.trim()) p.push(o.note.trim());
  if (o.nbPhotos === 1) p.push('Une photo est disponible.');
  else if ((o.nbPhotos ?? 0) > 1) p.push(`${o.nbPhotos} photos sont disponibles.`);
  return p.join(' ');
}

/** Photo dans le stockage privé `documents` (comme l'appli, uploadPhotoPrive). */
async function uploadPhotoPrive(file: File, path: string): Promise<string> {
  const blob = await compressImage(file, 1600, 0.8, false);
  const { error } = await supabase.storage.from('documents').upload(path, blob, { contentType: 'image/jpeg', upsert: true });
  if (error) throw error;
  return `${supabase.storage.from('documents').getPublicUrl(path).data.publicUrl}?v=${Date.now()}`;
}

export interface RdvCompteRendu {
  id: string; animal_id: string | null; client_uid: string | null; client_profile_id?: string | null; motif?: string | null;
}

/** Enregistre et envoie le compte rendu (après validation du pet-sitter). */
export async function envoyerCompteRendu(o: {
  rdv: RdvCompteRendu; proUid: string; proNom: string; animalNom: string; message: string; incident: boolean; photos: File[];
}) {
  const urls: string[] = [];
  for (let i = 0; i < o.photos.length; i++) {
    urls.push(await uploadPhotoPrive(o.photos[i], `visite_rapports/${o.proUid}_${Date.now()}_${i}.jpg`));
  }
  const lignes: Record<string, unknown>[] = [
    { note: o.message, photo_url: urls[0] ?? null },
    ...urls.slice(1).map(u => ({ note: null, photo_url: u })),
  ];
  for (let i = 0; i < lignes.length; i++) {
    const base = { animal_id: o.rdv.animal_id, pro_uid: o.proUid, ...lignes[i] };
    const { error } = await supabase.from('pension_updates').insert({ ...base, rdv_id: o.rdv.id, ...(i === 0 ? { incident: o.incident } : {}) });
    // Migration pas encore passée (colonnes rdv_id / incident absentes) → insertion simple.
    if (error) {
      const { error: e2 } = await supabase.from('pension_updates').insert(base);
      if (e2) throw e2;
    }
  }
  const owner = o.rdv.client_uid;
  if (!owner) return;
  let destPid = o.rdv.client_profile_id ?? null;
  if (!destPid) {
    const { data } = await supabase.from('user_profiles_complet').select('id')
      .eq('uid', owner).eq('profile_type', 'particulier').order('is_main', { ascending: false }).limit(1).maybeSingle();
    destPid = (data?.id as string | undefined) ?? null;
  }
  const kind = estPromenade(o.rdv.motif) ? 'Compte rendu de promenade' : 'Compte rendu de visite';
  const extrait = o.message.length > 160 ? `${o.message.slice(0, 157)}…` : o.message;
  // Jamais de code d'accès ni d'info sensible : seulement le message.
  await supabase.from('notifications').insert({
    uid: owner, type: 'visite_rapport',
    title: `${o.incident ? 'Incident — ' : ''}${kind}${o.animalNom ? ` — ${o.animalNom}` : ''}`,
    body: `${o.proNom || 'Votre pet sitter'} : ${extrait}`,
    ...(destPid ? { profile_id: destPid } : {}),
    data: { animalId: o.rdv.animal_id ?? '', animalNom: o.animalNom, rdvId: o.rdv.id, ...(o.incident ? { incident: true } : {}) },
    read: false,
  });
}
