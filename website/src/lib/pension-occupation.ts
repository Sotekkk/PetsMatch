// Pension : un logement a-t-il encore de la place pour un séjour ? Utilisé à
// chaque attribution manuelle (arrivée, registre, logements) pour avertir
// avant de surbooker. Miroir appli : lib/utils/pension_occupation.dart.
import type { SupabaseClient } from '@supabase/supabase-js';

const jour = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

/** Nuits du séjour (arrivée incluse, départ exclu ; séjour d'un jour : ce jour). */
function nuits(debut: string, fin: string | null): string[] {
  const out: string[] = [];
  const d = new Date(`${debut.slice(0, 10)}T12:00:00`);
  const f = fin ? fin.slice(0, 10) : debut.slice(0, 10);
  if (f <= debut.slice(0, 10)) return [debut.slice(0, 10)];
  while (jour(d) < f && out.length < 400) { out.push(jour(d)); d.setDate(d.getDate() + 1); }
  return out;
}

/**
 * Message d'avertissement si le logement est complet sur une nuit du séjour
 * (null s'il reste de la place). `exclure` : séjours qui ne comptent pas
 * (celui qu'on place, ses compagnons placés en même temps).
 */
export async function avertissementLogementComplet(sb: SupabaseClient, logementId: string, sejour: { date_entree?: string | null; date_sortie_prevue?: string | null; seul_dans_logement?: boolean | null; pro_profile_id?: string | null }, exclure: string[] = []): Promise<string | null> {
  if (!logementId || !sejour.date_entree) return null;
  const { data: lg } = await sb.from('enclos_chenil').select('nom, capacite').eq('id', logementId).maybeSingle();
  if (!lg) return null;
  const capacite = Number((lg as { capacite?: number | null }).capacite) || 1;
  // Temps de désinfection entre deux séjours (Tarifs de la pension).
  let desinf = 0;
  if (sejour.pro_profile_id) {
    const { data: p } = await sb.from('user_profiles').select('tarifs_pension').eq('id', sejour.pro_profile_id).maybeSingle();
    const n = Number(((p as { tarifs_pension?: { desinfection_jours?: number } } | null)?.tarifs_pension)?.desinfection_jours);
    desinf = Number.isFinite(n) && n > 0 ? Math.min(7, Math.round(n)) : 0;
  }
  const plus = (iso: string | null, n: number) => { if (!iso) return null; const d = new Date(`${iso.slice(0, 10)}T12:00:00`); d.setDate(d.getDate() + n); return jour(d); };
  const { data: occ } = await sb.from('pension_entrees').select('id, date_entree, date_sortie_prevue, seul_dans_logement')
    .eq('logement_id', logementId).eq('statut', 'en_pension');
  const autres = ((occ ?? []) as { id: string; date_entree: string; date_sortie_prevue: string | null; seul_dans_logement: boolean | null }[])
    .filter(o => !exclure.includes(String(o.id)));
  const complets: string[] = [];
  for (const j of nuits(sejour.date_entree, sejour.date_sortie_prevue ?? null)) {
    // Occupé jusqu'au départ + désinfection.
    const ici = autres.filter(o => nuits(o.date_entree, plus(o.date_sortie_prevue ?? null, desinf)).includes(j));
    const plein = ici.length + 1 > capacite || ici.some(o => o.seul_dans_logement === true) || (sejour.seul_dans_logement === true && ici.length > 0);
    if (plein) complets.push(j);
  }
  if (!complets.length) return null;
  const fr = (j: string) => `${j.slice(8, 10)}/${j.slice(5, 7)}`;
  const liste = complets.length > 4 ? `${complets.slice(0, 4).map(fr).join(', ')}…` : complets.map(fr).join(', ');
  return `${(lg as { nom: string }).nom} est complet le ${liste} (${capacite} place${capacite > 1 ? 's' : ''}${desinf ? `, désinfection de ${desinf} j comprise` : ''}) : choisissez un autre logement.`;
}
