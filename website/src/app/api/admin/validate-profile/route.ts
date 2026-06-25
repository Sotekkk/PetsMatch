import { NextRequest, NextResponse } from 'next/server';
import { supabase } from '@/lib/supabase';

// ─── Codes NAF autorisés par type de profil ───────────────────────────────────
// L'API renvoie le code sous la forme "01.49Z" — on compare les préfixes normalisés
const NAF_PREFIXES: Record<string, string[]> = {
  eleveur:          ['0141', '0142', '0143', '0144', '0145', '0146', '0147', '0149', '0150', '0321', '0322', '0161'],
  association:      ['9499', '9491', '9492', '8899', '8891', '8531', '8532', '8551', '8552', '8559', '8690', '7500', '0149'],
  veterinaire:      ['7500'],
  para_medical:     ['7500', '8690', '8610', '8621', '8622', '8559', '8552'],
  education:        ['8552', '8559', '8531', '8532', '9499', '0149'],
  petsitter:        ['9609', '9499', '8559', '0149'],
  pension:          ['5520', '9609', '0149'],
  promeneur:        ['9609', '9499'],
  photographe:      ['7420', '9609'],
  marechal_ferrant: ['0161', '2573', '0149'],
};

// ─── Normalisation texte ──────────────────────────────────────────────────────
const STOPWORDS = new Set([
  'sas', 'sarl', 'eurl', 'sca', 'snc', 'sci', 'scp', 'scop', 'sa', 'se',
  'association', 'asso', 'de', 'la', 'le', 'les', 'du', 'des', 'et', 'en',
  'pour', 'sur', 'par', 'au', 'aux', 'un', 'une', 'the', 'of',
]);

function normalize(s: string): string {
  return s
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ').trim();
}

function significantWords(s: string): Set<string> {
  return new Set(normalize(s).split(' ').filter(w => w.length > 2 && !STOPWORDS.has(w)));
}

// Similarité Jaccard sur mots significatifs
function jaccard(a: string, b: string): number {
  const wa = significantWords(a);
  const wb = significantWords(b);
  if (wa.size === 0 && wb.size === 0) return 1;
  if (wa.size === 0 || wb.size === 0) return 0;
  const inter = [...wa].filter(w => wb.has(w)).length;
  const union = new Set([...wa, ...wb]).size;
  return inter / union;
}

// Vérifie si un code NAF correspond au type de profil
function nafOk(nafCode: string, profileType: string): boolean {
  const code = nafCode.replace(/[^0-9A-Za-z]/g, '').toUpperCase();
  const allowed = NAF_PREFIXES[profileType] ?? [];
  return allowed.some(p => code.startsWith(p.toUpperCase()));
}

// ─── Appel API Annuaire des Entreprises (gratuit, pas de clé) ────────────────
interface SireneResult {
  nom_complet?: string;
  siren?: string;
  siege?: { activite_principale?: string; etat_administratif?: string };
  etat_administratif?: string;
  dirigeants?: { nom?: string; prenoms?: string; qualite?: string }[];
  nombre_etablissements_ouverts?: number;
}

async function searchSirene(query: string): Promise<SireneResult | null> {
  try {
    const url = `https://recherche-entreprises.api.gouv.fr/search?q=${encodeURIComponent(query)}&page=1&per_page=1`;
    const res = await fetch(url, {
      headers: { 'Accept': 'application/json' },
      signal: AbortSignal.timeout(8000),
    });
    if (!res.ok) return null;
    const json = await res.json() as { results?: SireneResult[] };
    return json.results?.[0] ?? null;
  } catch {
    return null;
  }
}

// ─── Résultat de validation ───────────────────────────────────────────────────
interface ValidationResult {
  score: number;
  autoValidated: boolean;
  reasons: string[];
  apiData: Record<string, unknown> | null;
}

// ─── Algo principal ───────────────────────────────────────────────────────────
async function validateProfile(profile: Record<string, unknown>): Promise<ValidationResult> {
  const profileType = (profile.profile_type as string) ?? '';
  const siret       = (profile.siret as string | null) ?? null;
  const rna         = (profile.rna  as string | null) ?? null;
  const nom         = (profile.nom  as string | null)
                   ?? (profile.name_elevage as string | null)
                   ?? null;
  const firstname   = (profile.firstname as string | null) ?? null;
  const lastname    = (profile.lastname  as string | null) ?? null;

  const reasons: string[] = [];
  let score = 0;
  let apiData: Record<string, unknown> | null = null;

  // Particuliers : pas de validation SIRET nécessaire
  if (profileType === 'particulier') {
    return { score: 1, autoValidated: true, reasons: ['✅ Profil particulier — aucune vérification SIRET requise'], apiData: null };
  }

  // Identifiant de recherche : SIRET ou RNA
  const searchQuery = siret ?? rna ?? nom;
  if (!searchQuery) {
    reasons.push('❌ Aucun SIRET, RNA ou nom fourni — vérification impossible');
    return { score: 0, autoValidated: false, reasons, apiData: null };
  }

  // ── Appel API ──
  const result = await searchSirene(searchQuery);

  if (!result) {
    reasons.push(`❌ Identifiant "${searchQuery}" introuvable dans l'annuaire des entreprises (INSEE/Sirene)`);
    reasons.push('⚠️  Causes possibles : SIRET/RNA incorrect, entité non encore enregistrée, ou API temporairement indisponible');
    return { score: 0, autoValidated: false, reasons, apiData: null };
  }

  apiData = result as unknown as Record<string, unknown>;

  // ── Statut de l'entité ──
  const etat = result.siege?.etat_administratif ?? result.etat_administratif ?? '';
  if (etat === 'A') {
    reasons.push('✅ Entité active dans le registre (état administratif A)');
    score += 0.25;
  } else if (etat === 'F') {
    reasons.push(`❌ Entité fermée (état administratif F) — SIRET ${siret ?? searchQuery}`);
    score -= 0.2;
  } else {
    reasons.push(`⚠️  État administratif inconnu : "${etat}"`);
  }

  // ── Nom / raison sociale ──
  const apiNom = result.nom_complet ?? '';
  if (nom && apiNom) {
    const sim = jaccard(nom, apiNom);
    if (sim >= 0.6) {
      reasons.push(`✅ Nom correspondant : "${apiNom}" (similarité ${Math.round(sim * 100)}%)`);
      score += 0.30;
    } else if (sim >= 0.3) {
      reasons.push(`⚠️  Nom partiellement correspondant : "${apiNom}" vs "${nom}" (similarité ${Math.round(sim * 100)}%)`);
      score += 0.10;
    } else {
      reasons.push(`❌ Nom ne correspond pas : annuaire="${apiNom}" / déclaré="${nom}" (similarité ${Math.round(sim * 100)}%)`);
    }
  } else if (!nom) {
    reasons.push(`⚠️  Aucun nom déclaré — entité trouvée : "${apiNom}"`);
    score += 0.05;
  }

  // ── Code NAF ──
  const nafCode = result.siege?.activite_principale ?? '';
  if (nafCode) {
    if (nafOk(nafCode, profileType)) {
      reasons.push(`✅ Code NAF ${nafCode} compatible avec le type "${profileType}"`);
      score += 0.25;
    } else {
      reasons.push(`❌ Code NAF ${nafCode} non attendu pour le type "${profileType}" (domaine d'activité incompatible)`);
    }
  } else {
    reasons.push('⚠️  Code NAF non disponible dans l\'annuaire');
  }

  // ── Dirigeant ──
  const dirigeants = result.dirigeants ?? [];
  if (dirigeants.length > 0 && (firstname || lastname)) {
    const fullName = `${firstname ?? ''} ${lastname ?? ''}`;
    const matched = dirigeants.some(d => {
      const apiFullName = `${d.prenoms ?? ''} ${d.nom ?? ''}`;
      return jaccard(fullName, apiFullName) >= 0.5;
    });
    if (matched) {
      reasons.push(`✅ Nom du dirigeant/représentant trouvé dans l'annuaire`);
      score += 0.20;
    } else {
      const listedNames = dirigeants.slice(0, 3).map(d => `${d.prenoms ?? ''} ${d.nom ?? ''}`.trim()).join(', ');
      reasons.push(`⚠️  Nom déclaré "${fullName}" ne correspond à aucun dirigeant listé (${listedNames || 'liste vide'})`);
    }
  } else if (dirigeants.length === 0) {
    reasons.push('⚠️  Aucun dirigeant disponible dans l\'annuaire pour comparaison');
  }

  // ── Seuil d'auto-validation ──
  const AUTO_THRESHOLD = 0.6;
  const clampedScore = Math.max(0, Math.min(1, score));
  const autoValidated = clampedScore >= AUTO_THRESHOLD;

  if (autoValidated) {
    reasons.push(`✅ Score ${Math.round(clampedScore * 100)}/100 ≥ ${AUTO_THRESHOLD * 100} — validation automatique`);
  } else {
    reasons.push(`⚠️  Score ${Math.round(clampedScore * 100)}/100 < ${AUTO_THRESHOLD * 100} — revue manuelle requise`);
  }

  return { score: clampedScore, autoValidated, reasons, apiData };
}

// ─── Route POST ───────────────────────────────────────────────────────────────
export async function POST(req: NextRequest) {
  try {
    const body = await req.json() as { profileId?: string; uid?: string; adminUid?: string };
    const { profileId, uid, adminUid } = body;

    if (!profileId && !uid) {
      return NextResponse.json({ error: 'profileId ou uid requis' }, { status: 400 });
    }

    // Récupérer le profil
    let query = supabase.from('user_profiles').select('*');
    if (profileId) query = query.eq('id', profileId) as typeof query;
    else           query = query.eq('uid', uid!) as typeof query;

    const { data: profiles, error: fetchErr } = await query;
    if (fetchErr || !profiles || profiles.length === 0) {
      return NextResponse.json({ error: 'Profil introuvable' }, { status: 404 });
    }

    const results = [];

    for (const profile of profiles as Record<string, unknown>[]) {
      const pid = profile.id as string;
      const ptype = profile.profile_type as string;

      // Skip particulier et profils déjà validés manuellement
      if (ptype === 'particulier') {
        results.push({ profileId: pid, skipped: true, reason: 'particulier' });
        continue;
      }

      const validation = await validateProfile(profile);

      // Mise à jour user_profiles
      const newStatus = validation.autoValidated ? 'auto_validated' : 'needs_review';
      await supabase.from('user_profiles').update({
        validation_status:     newStatus,
        validation_score:      validation.score,
        validation_reasons:    validation.reasons,
        validation_api_data:   validation.apiData,
        validation_checked_at: new Date().toISOString(),
        ...(validation.autoValidated ? {
          is_validate: true,
          statut_pro:  'actif',
        } : {}),
      }).eq('id', pid);

      // Créer ou résoudre une alerte admin
      if (!validation.autoValidated) {
        // Upsert alerte (dédoublonnage : une alerte pending par profil)
        const { data: existing } = await supabase
          .from('admin_alerts')
          .select('id')
          .eq('profile_id', pid)
          .eq('status', 'pending')
          .maybeSingle();

        if (!existing) {
          await supabase.from('admin_alerts').insert({
            profile_id: pid,
            uid:        profile.uid as string,
            alert_type: 'validation_required',
            status:     'pending',
            data: {
              profile_type: ptype,
              siret:    profile.siret,
              rna:      profile.rna,
              nom:      profile.nom ?? profile.name_elevage,
              score:    validation.score,
              reasons:  validation.reasons,
            },
          });
        }
      } else {
        // Résoudre les alertes en attente pour ce profil
        await supabase.from('admin_alerts')
          .update({ status: 'resolved', resolved_at: new Date().toISOString(), resolved_by: adminUid ?? 'auto' })
          .eq('profile_id', pid).eq('status', 'pending');
      }

      results.push({
        profileId: pid,
        profileType: ptype,
        score: validation.score,
        autoValidated: validation.autoValidated,
        reasons: validation.reasons,
      });
    }

    return NextResponse.json({ results });
  } catch (err) {
    console.error('validate-profile error:', err);
    return NextResponse.json({ error: String(err) }, { status: 500 });
  }
}
