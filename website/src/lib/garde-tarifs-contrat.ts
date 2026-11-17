// Contrat de pet-sitter (contrat cadre) — tarifs renseignés par le pro, à la
// place de « à convenir » : grille standard (user_profiles.tarifs_garde),
// prestations sur mesure (tarifs_garde_extra) et tarifs propres au client
// (tarifs_clients_garde, s'ils sont lisibles). Miroir appli :
// grilleTarifsGarde (contrat_signature_page.dart).
import { supabase } from '@/lib/supabase';

const LIBELLES: [string, string][] = [
  ['promenade_30min', 'Promenade (30 min)'],
  ['promenade_1h', 'Promenade (1h)'],
  ['promenade_2h', 'Promenade (2h)'],
  ['visite', 'Visite à domicile'],
  ['garde_journee', 'Garde à domicile (journée)'],
  ['animal_supplementaire', 'Animal supplémentaire (par passage)'],
  ['autre', 'Autre prestation'],
];
const eur = (n: number) => `${Number.isInteger(n) ? n : n.toFixed(2).replace('.', ',')} €`;

/** « Promenade (30 min) : 12 € · Visite à domicile : 15 € … », ou '' si aucun tarif. */
export async function grilleTarifsGarde(proProfileId: string | null | undefined, clientProfileId?: string | null): Promise<string> {
  if (!proProfileId) return '';
  try {
    const { data } = await supabase.from('user_profiles_complet').select('tarifs_garde, tarifs_garde_extra').eq('id', proProfileId).maybeSingle();
    const p = data as { tarifs_garde?: Record<string, unknown> | null; tarifs_garde_extra?: { label?: string; prix?: number }[] | null } | null;
    const prix: Record<string, number> = {};
    for (const [k] of LIBELLES) { const v = Number(p?.tarifs_garde?.[k]); if (v > 0) prix[k] = v; }
    if (clientProfileId) {
      const { data: perso } = await supabase.from('tarifs_clients_garde').select('prestation_type, prix')
        .eq('pro_profile_id', proProfileId).eq('owner_profile_id', clientProfileId);
      for (const t of (perso ?? []) as { prestation_type: string; prix: number | null }[]) {
        if (Number(t.prix) > 0) prix[t.prestation_type] = Number(t.prix);
      }
    }
    const lignes = LIBELLES.filter(([k]) => prix[k] > 0).map(([k, l]) => `${l} : ${eur(prix[k])}`);
    for (const e of p?.tarifs_garde_extra ?? []) {
      if (e?.label?.trim() && Number(e.prix) > 0) lignes.push(`${e.label.trim()} : ${eur(Number(e.prix))}`);
    }
    return lignes.join(' · ');
  } catch {
    return '';
  }
}
