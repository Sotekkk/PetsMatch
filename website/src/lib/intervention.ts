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

/** Interventions de l'animal (récentes d'abord) : choisir le CR préopératoire à reprendre. */
export async function chirurgiesAnimal(animalId: string): Promise<{ id: string; date: string | null; intitule: string | null; preop: { statut?: string } | null; operatoire: unknown }[]> {
  const { data } = await supabase.from('chirurgies').select('id, date, intitule, preop, operatoire').eq('animal_id', animalId)
    .order('date', { ascending: false }).limit(15);
  return (data ?? []) as { id: string; date: string | null; intitule: string | null; preop: { statut?: string } | null; operatoire: unknown }[];
}

/** Rattache le RDV à une autre intervention (CR pré-op existant), datée du jour
 *  de l'intervention ; l'ancienne, restée vide, est supprimée. */
export async function rattacherChirurgie(rdv: { id: string; date_heure: string; chirurgie_id: string | null }, chirurgieId: string): Promise<string | null> {
  const jour = new Date(rdv.date_heure).toLocaleDateString('sv-SE', { timeZone: 'Europe/Paris' });
  const { error } = await supabase.from('chirurgies').update({ date: jour }).eq('id', chirurgieId);
  if (error) return error.message;
  const { error: e2 } = await supabase.from('rdv').update({ chirurgie_id: chirurgieId }).eq('id', rdv.id);
  if (e2) return e2.message;
  if (rdv.chirurgie_id && rdv.chirurgie_id !== chirurgieId) {
    const { data: ancienne } = await supabase.from('chirurgies').select('preop, operatoire, consignes').eq('id', rdv.chirurgie_id).maybeSingle();
    const a = ancienne as { preop: unknown; operatoire: unknown; consignes: unknown } | null;
    if (a && !a.preop && !a.operatoire && !a.consignes) await supabase.from('chirurgies').delete().eq('id', rdv.chirurgie_id);
  }
  return null;
}

/** Suivi de la journée au propriétaire : notification (appli), sinon e-mail,
 *  sinon message « appelez-le au … ». */
export async function messageIntervention(rdvId: string, message: 'reveille' | 'pret' | 'recuperation'): Promise<string> {
  const r = await apiFetch('/api/rdv/consignes-preop', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ rdvId, message }) });
  const j = await r.json().catch(() => ({})) as { error?: string; notifie?: boolean; email_envoye?: boolean };
  if (j.notifie) return 'Client prévenu dans l’appli.';
  if (j.email_envoye) return 'Client prévenu par e-mail.';
  return j.error ?? 'Envoi impossible.';
}

/** Intervention (chirurgies) du RDV : celle de l'animal ce jour-là (CR pré-op
 *  fait en consultation avec la date prévue), sinon une nouvelle. Renvoie son id. */
export async function lierChirurgieRdv(rdv: { id: string; animal_id: string | null; date_heure: string; motif: string | null; pro_uid: string; pro_profile_id: string | null; intervention_type: string | null }, veterinaire?: string): Promise<string | null> {
  if (!rdv.animal_id) return null;
  const jour = new Date(rdv.date_heure).toLocaleDateString('sv-SE', { timeZone: 'Europe/Paris' });
  const { data: ex } = await supabase.from('chirurgies').select('id').eq('animal_id', rdv.animal_id).eq('date', jour).limit(1).maybeSingle();
  let id = (ex as { id?: string } | null)?.id ?? null;
  // Sinon : CR préopératoire récent de l'animal (consultation des jours
  // précédents), pas encore opéré — repris et daté du jour de l'intervention.
  if (!id) {
    const depuis = new Date(Date.parse(rdv.date_heure) - 60 * 86400000).toISOString().slice(0, 10);
    const { data: recents } = await supabase.from('chirurgies').select('id, preop, operatoire, date')
      .eq('animal_id', rdv.animal_id).gte('date', depuis).order('date', { ascending: false }).limit(10);
    const c = ((recents ?? []) as { id: string; preop: unknown; operatoire: unknown }[]).find(x => x.preop && !x.operatoire);
    if (c) { id = c.id; await supabase.from('chirurgies').update({ date: jour }).eq('id', id); }
  }
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

// ── Hospitalisés du jour (lot 2) ────────────────────────────────────────────
export interface Hospitalise {
  id: string; date_heure: string; motif: string | null; statut: string; intervention_type: string | null;
  animal_id: string | null; animal_nom_manuel: string | null; client_uid: string | null; client_profile_id: string | null;
  client_nom_manuel: string | null; client_telephone_manuel: string | null;
  heure_recuperation: string | null; bloc_debut: string | null; bloc_fin: string | null;
  admis_le: string | null; reveil_le: string | null; pret_le: string | null; sortie_le: string | null;
  animalNom: string; animalPhoto: string | null; clientNom: string;
}

export type EtatHospit = 'attendu' | 'depose' | 'bloc' | 'reveil' | 'pret' | 'rentre';
export const ETATS_HOSPIT: Record<EtatHospit, { label: string; fg: string; bg: string }> = {
  attendu: { label: 'Attendu', fg: '#6B7280', bg: '#F1F4F3' },
  depose: { label: 'Déposé', fg: '#0C5C6C', bg: '#E6F2F3' },
  bloc: { label: 'Au bloc', fg: '#8A5A00', bg: '#FFF4DC' },
  reveil: { label: 'En réveil', fg: '#6D28D9', bg: '#F1EAFE' },
  pret: { label: 'Prêt à partir', fg: '#2E7D32', bg: '#E8F5E9' },
  rentre: { label: 'Récupéré', fg: '#6B7280', bg: '#F1F4F3' },
};

export function etatHospit(h: Pick<Hospitalise, 'admis_le' | 'reveil_le' | 'pret_le' | 'sortie_le' | 'bloc_debut' | 'bloc_fin'>, now = new Date()): EtatHospit {
  if (h.sortie_le) return 'rentre';
  if (h.pret_le) return 'pret';
  if (h.reveil_le) return 'reveil';
  if (h.admis_le) {
    const t = now.getTime();
    if (h.bloc_debut && t >= Date.parse(h.bloc_debut) && (!h.bloc_fin || t <= Date.parse(h.bloc_fin))) return 'bloc';
    return 'depose';
  }
  return 'attendu';
}

/** Interventions du jour de la clinique + animaux encore hospitalisés (déposés avant).
 *  Animal récupéré : retiré de la liste, le RDV est dans l'historique. */
export async function hospitalisesDuJour(proProfileId: string): Promise<Hospitalise[]> {
  const d = new Date(); const debut = new Date(d.getFullYear(), d.getMonth(), d.getDate()); const fin = new Date(debut.getTime() + 86400000);
  const cols = 'id, date_heure, motif, statut, intervention_type, animal_id, animal_nom_manuel, client_uid, client_profile_id, client_nom_manuel, client_telephone_manuel, heure_recuperation, bloc_debut, bloc_fin, admis_le, reveil_le, pret_le, sortie_le';
  const [{ data: jour }, { data: restants }] = await Promise.all([
    supabase.from('rdv').select(cols).eq('pro_profile_id', proProfileId).not('intervention_type', 'is', null)
      .gte('date_heure', debut.toISOString()).lt('date_heure', fin.toISOString()).not('statut', 'in', '(annule,refuse)').is('sortie_le', null),
    supabase.from('rdv').select(cols).eq('pro_profile_id', proProfileId).not('intervention_type', 'is', null)
      .not('admis_le', 'is', null).is('sortie_le', null).lt('date_heure', debut.toISOString()),
  ]);
  const lignes = [...((restants ?? []) as Omit<Hospitalise, 'animalNom' | 'animalPhoto' | 'clientNom'>[]), ...((jour ?? []) as Omit<Hospitalise, 'animalNom' | 'animalPhoto' | 'clientNom'>[])];
  const ids = [...new Set(lignes.map(l => l.animal_id).filter(Boolean) as string[])];
  const pids = [...new Set(lignes.map(l => l.client_profile_id).filter(Boolean) as string[])];
  const [{ data: an }, { data: cl }] = await Promise.all([
    ids.length ? supabase.from('animaux').select('id, nom, photo_url').in('id', ids) : Promise.resolve({ data: [] }),
    pids.length ? supabase.from('user_profiles_complet').select('id, firstname, lastname, nom').in('id', pids) : Promise.resolve({ data: [] }),
  ]);
  const animaux = new Map(((an ?? []) as { id: string; nom: string | null; photo_url: string | null }[]).map(a => [String(a.id), a]));
  const clients = new Map(((cl ?? []) as { id: string; firstname: string | null; lastname: string | null; nom: string | null }[])
    .map(c => [c.id, `${c.firstname ?? ''} ${c.lastname ?? ''}`.trim() || (c.nom ?? '')]));
  const ordre: EtatHospit[] = ['bloc', 'reveil', 'depose', 'pret', 'attendu', 'rentre'];
  return lignes.map(l => ({
    ...l,
    animalNom: (l.animal_id ? animaux.get(String(l.animal_id))?.nom : null) || l.animal_nom_manuel || 'Animal',
    animalPhoto: l.animal_id ? animaux.get(String(l.animal_id))?.photo_url ?? null : null,
    clientNom: (l.client_profile_id ? clients.get(l.client_profile_id) : '') || l.client_nom_manuel || 'Client',
  })).sort((a, b) => ordre.indexOf(etatHospit(a)) - ordre.indexOf(etatHospit(b)) || a.date_heure.localeCompare(b.date_heure));
}
