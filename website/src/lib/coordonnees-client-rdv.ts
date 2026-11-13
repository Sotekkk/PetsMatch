// Coordonnées du client d'un RDV pour préremplir une facture : profil du
// client, compte (RPC pm_contact_client_rdv, réservée au pro du RDV) et saisie
// manuelle (client sans compte). Miroir appli : coordonneesClientRdv
// (lib/pages/pro/toilettage_dossier_seance.dart).
import { supabase } from '@/lib/supabase';

export interface CoordonneesClient {
  prenom: string; nom: string; email: string; tel: string; rue: string; cp: string; ville: string;
}

const premier = (...v: unknown[]) => v.map(x => String(x ?? '').trim()).find(x => x) ?? '';

export async function coordonneesClientRdv(rdvId: string, clientProfileId?: string | null): Promise<CoordonneesClient> {
  const [man, prof, cc] = await Promise.all([
    supabase.from('rdv').select('client_telephone_manuel, client_email_manuel').eq('id', rdvId).maybeSingle()
      .then(r => r.data as Record<string, unknown> | null, () => null),
    clientProfileId
      ? supabase.from('user_profiles_complet')
        .select('firstname, lastname, phone_number, phone, email_contact, rue, code_postal, ville, rue_pro, code_postal_pro, ville_pro')
        .eq('id', clientProfileId).maybeSingle().then(r => r.data as Record<string, unknown> | null, () => null)
      : Promise.resolve(null),
    supabase.rpc('pm_contact_client_rdv', { p_rdv_id: rdvId }).then(r => r.data as Record<string, unknown> | null, () => null),
  ]);
  return {
    tel: premier(prof?.phone_number, prof?.phone, cc?.telephone, man?.client_telephone_manuel),
    email: premier(prof?.email_contact, cc?.email, man?.client_email_manuel),
    prenom: premier(prof?.firstname, cc?.prenom),
    nom: premier(prof?.lastname, cc?.nom),
    rue: premier(prof?.rue, prof?.rue_pro, cc?.rue),
    cp: premier(prof?.code_postal, prof?.code_postal_pro, cc?.code_postal),
    ville: premier(prof?.ville, prof?.ville_pro, cc?.ville),
  };
}

/** Champs du préremplissage de facture (/elevage/facturation). */
export function prefillClient(c: CoordonneesClient, nomAffiche: string) {
  return {
    nomClient: c.nom || nomAffiche,
    ...(c.nom && c.prenom ? { prenomClient: c.prenom } : {}),
    emailClient: c.email, telClient: c.tel,
    rueClient: c.rue, cpClient: c.cp, villeClient: c.ville,
  };
}
