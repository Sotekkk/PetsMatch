// RDV « Intervention » (vétérinaire) : détartrage, stérilisation… sous
// anesthésie — dépôt le matin, récupération plus tard, consignes avant
// l'intervention, dossier propre (CR pré-op, admission, CR opératoire,
// réveil, sortie). Pas de réservation en ligne : créé par la clinique.
// Miroir appli : lib/utils/intervention.dart.
import { supabase } from '@/lib/supabase';
import { apiFetch } from '@/lib/api-fetch';

export const SOUS_TYPES_INTERVENTION: { key: string; label: string; duree: number }[] = [
  { key: 'detartrage', label: 'Détartrage', duree: 60 },
  { key: 'sterilisation', label: 'Stérilisation', duree: 60 },
  { key: 'castration', label: 'Castration', duree: 45 },
  { key: 'extraction', label: 'Extraction dentaire', duree: 60 },
  { key: 'chirurgie', label: 'Chirurgie', duree: 90 },
  { key: 'autre', label: 'Autre intervention', duree: 60 },
];

export const libelleIntervention = (k: string | null | undefined) =>
  SOUS_TYPES_INTERVENTION.find(t => t.key === k)?.label ?? 'Intervention';

const JEUN = 'Animal à jeun : dernier repas la veille avant 20 h. L’eau reste à disposition jusqu’au matin.';
/** Textes proposés tant que la clinique n'a pas écrit les siens (Mon profil). */
export const CONSIGNES_PREOP_DEFAUT: Record<string, string> = {
  detartrage: `${JEUN}\nPrévoir la journée : l’animal repart en fin de journée, une fois bien réveillé.`,
  sterilisation: `${JEUN}\nPromenade / passage dehors avant de venir.\nApporter une couverture ; prévoir une collerette ou un body pour le retour.`,
  castration: `${JEUN}\nPromenade / passage dehors avant de venir.\nPrévoir une collerette pour le retour.`,
  extraction: `${JEUN}\nPrévoir la journée : alimentation molle quelques jours après.`,
  chirurgie: `${JEUN}\nApporter les traitements en cours et les derniers examens.`,
  autre: JEUN,
};

/** Consignes par défaut de la clinique (sinon les textes ci-dessus). */
export async function consignesPreopDefaut(proProfileId: string | null | undefined): Promise<Record<string, string>> {
  if (!proProfileId) return { ...CONSIGNES_PREOP_DEFAUT };
  const { data } = await supabase.from('consignes_preop_veto').select('consignes').eq('pro_profile_id', proProfileId).maybeSingle();
  const c = ((data as { consignes?: Record<string, string> } | null)?.consignes ?? {}) as Record<string, string>;
  return Object.fromEntries(SOUS_TYPES_INTERVENTION.map(t => [t.key, (c[t.key] ?? '').trim() || CONSIGNES_PREOP_DEFAUT[t.key]]));
}

export async function enregistrerConsignesPreop(proProfileId: string, consignes: Record<string, string>) {
  const { error } = await supabase.from('consignes_preop_veto')
    .upsert({ pro_profile_id: proProfileId, consignes, updated_at: new Date().toISOString() }, { onConflict: 'pro_profile_id' });
  return !error;
}

/** Envoie les consignes au propriétaire (notification + e-mail). */
export async function envoyerConsignesPreop(rdvId: string): Promise<{ ok: boolean; message: string }> {
  const r = await apiFetch('/api/rdv/consignes-preop', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ rdvId }) });
  const j = await r.json().catch(() => ({})) as { error?: string; notifie?: boolean; email_envoye?: boolean };
  if (!r.ok) return { ok: false, message: j.error ?? 'Envoi impossible' };
  return { ok: true, message: `Consignes envoyées${j.email_envoye ? ' par e-mail' : ''}${j.notifie ? `${j.email_envoye ? ' et' : ''} dans l’appli du client` : ''}.` };
}

/** Intervention (chirurgies) du RDV : celle de l'animal ce jour-là (CR pré-op
 *  fait en consultation avec la date prévue), sinon une nouvelle. Renvoie son id. */
export async function lierChirurgieRdv(rdv: { id: string; animal_id: string | null; date_heure: string; motif: string | null; pro_uid: string; pro_profile_id: string | null; intervention_type: string | null }, veterinaire?: string): Promise<string | null> {
  if (!rdv.animal_id) return null;
  const jour = new Date(rdv.date_heure).toLocaleDateString('sv-SE', { timeZone: 'Europe/Paris' });
  const { data: ex } = await supabase.from('chirurgies').select('id').eq('animal_id', rdv.animal_id).eq('date', jour).limit(1).maybeSingle();
  let id = (ex as { id?: string } | null)?.id ?? null;
  if (!id) {
    id = crypto.randomUUID();
    const { error } = await supabase.from('chirurgies').insert({
      id, animal_id: rdv.animal_id, date: jour, type: 'chirurgie',
      intitule: rdv.motif || libelleIntervention(rdv.intervention_type), statut: 'prevu', source: 'veterinaire',
      vet_id: rdv.pro_uid, pro_uid: rdv.pro_uid, ...(rdv.pro_profile_id ? { pro_profile_id: rdv.pro_profile_id } : {}),
      ...(veterinaire ? { veterinaire } : {}),
    });
    if (error) return null;
  }
  await supabase.from('rdv').update({ chirurgie_id: id }).eq('id', rdv.id);
  return id;
}
