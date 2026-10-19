// Client sans compte : contrat à signer envoyé par e-mail (lien à jeton, sans
// compte) via /api/contrat/notify-email. Miroir appli : envoyerContratParEmail
// (toilettage_dossier_seance.dart).
import { apiFetch } from '@/lib/api-fetch';
import { supabase } from '@/lib/supabase';

export async function envoyerContratParEmail(opts: {
  email: string; clientNom: string; proProfileId: string | null | undefined; token: string; titre?: string;
}): Promise<boolean> {
  if (!opts.email.trim()) return false;
  let proNom = '';
  if (opts.proProfileId) {
    const { data } = await supabase.from('user_profiles_complet').select('nom, firstname, lastname').eq('id', opts.proProfileId).maybeSingle();
    const p = data as { nom?: string | null; firstname?: string | null; lastname?: string | null } | null;
    proNom = (p?.nom ?? '').trim() || `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim();
  }
  const r = await apiFetch('/api/contrat/notify-email', {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: opts.email.trim(), client_nom: opts.clientNom, pro_nom: proNom || 'Votre professionnel',
      ...(opts.titre ? { titre: opts.titre } : {}), signing_url: `${window.location.origin}/signer-contrat/${opts.token}` }),
  });
  return r.ok;
}
