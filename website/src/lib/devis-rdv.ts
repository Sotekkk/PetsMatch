// Devis rattachés à un RDV (créés depuis le dossier de la consultation /
// séance) : enregistrés sans être envoyés, puis envoyés au client à la fin
// avec le reste des documents (« Terminer et envoyer ») — lien de signature
// par e-mail + notification s'il a un compte. Miroir appli : lib/utils/devis_rdv.dart.
import { supabase } from '@/lib/supabase';
import { apiFetch } from '@/lib/api-fetch';

export interface DevisRdv {
  id: string; statut: string; total_ttc: number; email_client: string | null;
  nom_client: string | null; prenom_client: string | null;
  client_uid: string | null; client_profile_id: string | null; token_acceptation: string | null;
  /** Document signable (documents_animaux) du devis. */
  docId: string | null; docToken: string | null;
}

/** Devis du RDV pas encore acceptés / refusés (brouillon ou déjà envoyé). */
export async function devisDuRdv(rdvId: string): Promise<DevisRdv[]> {
  const { data } = await supabase.from('devis')
    .select('id, statut, total_ttc, email_client, nom_client, prenom_client, client_uid, client_profile_id, token_acceptation')
    .eq('rdv_id', rdvId).in('statut', ['brouillon', 'envoye']).order('created_at');
  const liste = (data ?? []) as Omit<DevisRdv, 'docId' | 'docToken'>[];
  return Promise.all(liste.map(async d => {
    const { data: doc } = await supabase.from('documents_animaux').select('id, token')
      .contains('metadata', { devis_id: d.id }).limit(1).maybeSingle();
    return { ...d, total_ttc: Number(d.total_ttc ?? 0), docId: (doc?.id as string) ?? null, docToken: (doc?.token as string) ?? null };
  }));
}

/** Envoie le devis : statut « envoyé », document à signer, notification, e-mail. Renvoie false si aucun e-mail n'est parti. */
export async function envoyerDevisRdv(d: DevisRdv, o: { proNom: string; emailSecours?: string | null }): Promise<boolean> {
  if (d.statut === 'brouillon') {
    await supabase.from('devis').update({ statut: 'envoye', updated_at: new Date().toISOString() }).eq('id', d.id);
  }
  if (d.docId) await supabase.from('documents_animaux').update({ statut: 'en_attente' }).eq('id', d.docId).eq('statut', 'brouillon');
  const chemin = d.docToken ? `/signer-contrat/${d.docToken}` : `/devis/${d.token_acceptation}`;
  if (d.client_uid) {
    await supabase.from('notifications').insert({
      uid: d.client_uid, type: 'devis_recu', title: 'Vous avez reçu un devis',
      body: `Un devis de ${d.total_ttc.toFixed(2)} € vous a été envoyé.`,
      ...(d.client_profile_id ? { profile_id: d.client_profile_id } : {}),
      data: { devis_id: d.id, token: d.docToken ?? d.token_acceptation, url: chemin }, read: false,
    });
  }
  const email = (d.email_client || o.emailSecours || '').trim();
  if (!email) return false;
  const r = await apiFetch('/api/devis/notify-email', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email, client_nom: `${d.prenom_client ?? ''} ${d.nom_client ?? ''}`.trim() || 'Client',
      pro_nom: o.proNom || 'Votre professionnel', total_ttc: d.total_ttc,
      devis_url: `${window.location.origin}${chemin}`,
    }),
  });
  return r.ok;
}
