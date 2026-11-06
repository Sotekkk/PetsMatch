// Tableau de bord éleveur (accueil du site, components/EleveurDashboard.tsx) :
// LECTURE SEULE des modules existants, rien n'est créé ni recalculé ailleurs.
// Chaque élément n'apparaît que dans un bloc :
//   • À faire   : tâches manuelles (taches_elevage) + tâches de protocole qui
//                 ne sont pas des soins (plan_taches hors ACTES_CARNET) ;
//   • Soins     : rappels du CARNET (vaccinations / vermifuges / antiparasitaires,
//                 date_rappel de la dernière ligne de chaque soin, même règle
//                 de renouvellement que functions/sante.js), soins des protocoles
//                 (plan_taches, type_acte sanitaire) et tâches « Vaccin — … »
//                 posées par les rappels (masquées quand le rappel du carnet
//                 du même jour est déjà listé). Les événements d'agenda
//                 « Rappel vaccin — … » (copies du carnet) ne sont pas repris ;
//   • Agenda    : autres événements de l'agenda + RDV vétérinaires à venir
//                 (taches_elevage.rdv_veto_cabinet) ;
//   • Activité  : contrats à envoyer / à signer, demandes de récupération.
// Filtres de profil : ceux de l'agenda de l'élevage (app/elevage/agenda/page.tsx,
// withProfileFilter + sansAutresProfils). Miroir appli : lib/utils/tableau_bord_eleveur.dart.
import { supabase } from '@/lib/supabase';
import { ACTES_CARNET } from '@/lib/carnet-depuis-tache';
import { sansAutresProfils } from '@/lib/cloisonnement-profils';
import { loadMembres } from '@/components/agenda/AddTacheModal';

export const HORIZON_JOURS = 7;

export interface LigneTB {
  cle: string;
  titre: string;
  /** AAAA-MM-JJ (jour local). */
  date: string;
  heure?: string | null;
  animal?: string | null;
  responsable?: string | null;
  fait: boolean;
  retard: boolean;
  lien: string;
  /** Pastille de catégorie (couleur de l'agenda). */
  couleur?: string;
  sousTitre?: string | null;
  /** Rappel du carnet : jour|acte|animal (pour masquer la tâche du même rappel). */
  cleSoin?: string;
  /** Rappel du carnet : jour|soin|produit — même clé = une seule ligne, animaux regroupés. */
  groupe?: string;
  /** Rappel du carnet : de quoi ouvrir le formulaire de soin prérempli (PorteeSoinModal). */
  soin?: { typeActe: string; produit: string; animalIds: string[]; ecartJours: number | null };
  /** Soins d'un protocole le même jour (une ligne) : tâches à valider ensemble. */
  protocole?: RoutineBrute[];
  /** Coche directe possible (tâches simples uniquement). */
  cochable?: { table: 'taches_elevage'; ligne: TacheBrute } | { table: 'plan_taches'; ligne: RoutineBrute };
}

export interface TacheBrute {
  id: string; titre: string; date: string; statut: string; heure?: string | null;
  uid_eleveur: string; eleveur_profile_id?: string | null;
  animal_id?: string | null; animal_nom?: string | null;
  assigne_a?: string | null; assignes_a?: string[] | null;
  rdv_veto_cabinet?: string | null; rdv_veto_motif?: string | null;
}
export interface RoutineBrute {
  id: string; label: string; date_prevue: string; statut: string; type_acte?: string | null;
  animal_nom?: string | null; assigned_to?: string | null;
  animal_id?: string | null; etape_id?: string | null; jour_traitement?: number | null; total_jours?: number | null; uid_eleveur?: string | null;
}
interface EvenementBrut {
  id: number | string; titre: string; date_debut: string; type?: string | null; animal_id?: unknown;
}

// Tables du carnet avec date de rappel (functions/sante.js, TABLES).
const CARNET: { table: string; acte: string; libelle: string; nom: string; cols: string }[] = [
  { table: 'vaccinations', acte: 'vaccin', libelle: 'Rappel vaccin', nom: 'vaccin', cols: 'id,animal_id,date,date_rappel,vaccin,categorie' },
  { table: 'vermifuges', acte: 'vermifuge', libelle: 'Rappel vermifuge', nom: 'produit', cols: 'id,animal_id,date,date_rappel,produit' },
  { table: 'antiparasitaires', acte: 'antiparasitaire', libelle: 'Rappel antiparasitaire', nom: 'produit', cols: 'id,animal_id,date,date_rappel,produit' },
];
// Type de soin du formulaire PorteeSoinModal pour chaque table du carnet.
const TYPE_SOIN: Record<string, string> = { vaccinations: 'vaccination', vermifuges: 'vermifuge', antiparasitaires: 'antiparasitaire' };

/** Animaux présents du profil actif — même calcul que le compteur « Animaux » de l'accueil. */
export async function animauxDuProfil(ownerUid: string, activeProfileId: string): Promise<string[]> {
  let q = supabase.from('animaux_proprietes').select('animal_id').eq('uid_proprio', ownerUid).is('date_fin', null);
  if (activeProfileId) {
    const { data: check } = await supabase.from('animaux_proprietes').select('animal_id')
      .eq('uid_proprio', ownerUid).not('profile_id_proprio', 'is', null).limit(1);
    if ((check ?? []).length > 0) q = q.eq('profile_id_proprio', activeProfileId);
  }
  const { data } = await q.limit(2000);
  return [...new Set((data ?? []).map((r: { animal_id: unknown }) => String(r.animal_id)).filter(Boolean))];
}

// Rappel déjà renouvelé : un soin SAISI PLUS TARD pour le même animal (ou le
// même jour avec un rappel plus lointain) — vermifuge / antiparasitaire : quel
// que soit le nom saisi (« Effitix Virbac » puis « Virbac Effitix »), comme
// functions/sante.js ; vaccin : même type (catégorie, sinon nom du vaccin).
// Un soin plus ANCIEN à rappel lointain (ex. 19/05, rappel en 2027) ne masque
// pas le rappel d'un soin plus récent (cas de Tokyo, 06/11/2026).
const normTB = (v: unknown) => String(v ?? '').trim().toLowerCase();
const typeVaccinTB = (r: Record<string, unknown>) => {
  const c = normTB(r.categorie);
  return c && c !== 'autre' ? c : normTB(r.vaccin);
};
function rappelRemplace(table: string, r: Record<string, unknown>, lignes: Record<string, unknown>[]): boolean {
  const jour = (v: unknown) => String(v ?? '').slice(0, 10);
  return lignes.some(x => {
    if (String(x.id) === String(r.id)) return false;
    if (table === 'vaccinations' && typeVaccinTB(x) !== typeVaccinTB(r)
      && !(normTB(r.vaccin) && normTB(x.vaccin) === normTB(r.vaccin))) return false;
    const dx = jour(x.date), dr = jour(r.date);
    if (!dx || !dr) return false;
    return dx > dr || (dx === dr && !!jour(x.date_rappel) && !!jour(r.date_rappel) && jour(x.date_rappel) > jour(r.date_rappel));
  });
}

/** Même rappel le même jour pour plusieurs animaux : une ligne (comme les notifications groupées). */
function grouperRappels(lignes: LigneTB[]): LigneTB[] {
  const groupes = new Map<string, LigneTB[]>();
  for (const l of lignes) {
    const k = l.groupe ?? l.cle;
    groupes.set(k, [...(groupes.get(k) ?? []), l]);
  }
  return [...groupes.values()].map(g => g.length === 1 ? g[0] : {
    ...g[0],
    cle: g.map(x => x.cle).join('+'),
    animal: g.map(x => x.animal).filter(Boolean).join(', '),
    soin: g[0].soin ? { ...g[0].soin, animalIds: g.flatMap(x => x.soin?.animalIds ?? []) } : undefined,
    // Plusieurs animaux : la liste des animaux (la fiche de chacun s'ouvre de là).
    lien: '/mes-animaux',
  });
}

/** Rappels du carnet à faire (en retard ou dans l'horizon) pour ces animaux. */
async function rappelsCarnet(ids: string[], end: string, today: string): Promise<LigneTB[]> {
  if (!ids.length) return [];
  const morceaux: string[][] = [];
  for (let i = 0; i < ids.length; i += 100) morceaux.push(ids.slice(i, i + 100));
  const noms = new Map<string, string>();
  const lignes: LigneTB[] = [];
  await Promise.all(morceaux.map(async m => {
    const { data } = await supabase.from('animaux').select('id, nom').in('id', m);
    (data ?? []).forEach((a: { id: string | number; nom?: string | null }) => noms.set(String(a.id), a.nom ?? ''));
  }));
  await Promise.all(CARNET.map(async c => {
    const rows: Record<string, unknown>[] = [];
    await Promise.all(morceaux.map(async m => {
      const { data, error } = await supabase.from(c.table).select(c.cols).in('animal_id', m).limit(5000);
      if (error) console.error(`tableau de bord, ${c.table}:`, error.message);
      rows.push(...((data ?? []) as unknown as Record<string, unknown>[]));
    }));
    const parAnimal = new Map<string, Record<string, unknown>[]>();
    rows.forEach(r => { const k = String(r.animal_id); parAnimal.set(k, [...(parAnimal.get(k) ?? []), r]); });
    for (const r of rows) {
      const rappel = String(r.date_rappel ?? '').slice(0, 10);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(rappel) || rappel > end) continue;
      // Soin déjà renouvelé : plus rien à faire.
      if (rappelRemplace(c.table, r, parAnimal.get(String(r.animal_id)) ?? [])) continue;
      const produit = String(r[c.nom] ?? '').trim();
      const animalId = String(r.animal_id);
      // Intervalle habituel (soin → rappel) : proposé pour le prochain rappel.
      const dSoin = String(r.date ?? '').slice(0, 10);
      const ecart = /^\d{4}-\d{2}-\d{2}$/.test(dSoin)
        ? Math.round((Date.parse(`${rappel}T12:00:00`) - Date.parse(`${dSoin}T12:00:00`)) / 86400000) : null;
      lignes.push({
        cle: `c_${c.table}_${r.id}`, titre: produit ? `${c.libelle} — ${produit}` : c.libelle,
        date: rappel, animal: noms.get(animalId) || null, fait: false, retard: rappel < today,
        lien: `/mes-animaux/${animalId}?tab=sante&cat=${c.table}`, sousTitre: 'Carnet de santé',
        cleSoin: `${rappel}|${c.acte}|${animalId}`,
        soin: { typeActe: TYPE_SOIN[c.table], produit, animalIds: [animalId], ecartJours: ecart && ecart > 0 ? ecart : null },
        // Mots du produit triés : « Effitix Virbac » = « Virbac Effitix ».
        groupe: `${rappel}|${c.table}|${produit.toLowerCase().split(/\s+/).filter(Boolean).sort().join(' ')}`,
      });
    }
  }));
  return lignes;
}
export interface ContratTB { id: string; titre: string; statut: string; animal_nom?: string | null; date: string }
export interface RecuperationTB { id: string; animal_nom: string; date: string }

export interface DonneesTB {
  aFaire: LigneTB[];
  soins: LigneTB[];
  agenda: LigneTB[];
  contrats: ContratTB[];
  recuperations: RecuperationTB[];
}

// Couleurs de l'agenda (app/agenda/page.tsx, TYPE_COLOR).
const COULEUR_TYPE: Record<string, string> = {
  rdv: '#2196F3', mise_bas: '#E91E63', medication: '#FF9800', visite: '#4CAF50', formation: '#7B1FA2',
  reunion: '#0288D1', absence: '#78909C', autre: '#9E9E9E',
};

export const ymd = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const jourLocal = (iso: string) => ymd(new Date(iso));

/** Titres posés par les fonctions (« 💉 Vaccin — Luna ») : sans pictogramme à l'écran. */
export function sansPictos(t: string): string {
  return t.replace(/[\p{Extended_Pictographic}️‍]/gu, '').replace(/\s{2,}/g, ' ').trim();
}

const ACTE_TITRE = /^(vaccin|vermifuge|antiparasitaire|traitement)s?\s+—\s+/i;
const ACTE_RAPPEL = /^rappel\s+(vaccin|vermifuge|antiparasitaire)\s+—\s+/i;
const acteDe = (titre: string, re: RegExp) => (sansPictos(titre).match(re)?.[1] ?? '').toLowerCase();

/** Lien vers le jour de l'agenda de l'élevage. */
export const lienJour = (date: string) => `/elevage/agenda?date=${date}`;

export async function chargerTableauBord(p: { userUid: string; ownerUid: string; activeProfileId: string }): Promise<DonneesTB> {
  const { userUid, ownerUid, activeProfileId } = p;
  const auj = new Date();
  const today = ymd(auj);
  const fin = new Date(auj); fin.setDate(fin.getDate() + HORIZON_JOURS);
  const end = ymd(fin);

  // Même règle que l'agenda de l'élevage : profile_id strict, sinon repli
  // uid_eleveur + profil_source (tâches automatiques sans profile_id).
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const avecProfil = async (q: () => any) => {
    const repli = () => q().eq('uid_eleveur', ownerUid).or('profil_source.is.null,profil_source.eq.eleveur');
    if (!activeProfileId) return repli();
    const strict = await q().eq('profile_id', activeProfileId);
    if ((strict.data ?? []).length > 0) return strict;
    return repli();
  };
  const colsR = 'id,label,date_prevue,statut,type_acte,animal_nom,assigned_to,animal_id,etape_id,jour_traitement,total_jours,uid_eleveur';
  const colsT = 'id,titre,date,statut,heure,uid_eleveur,eleveur_profile_id,animal_id,animal_nom,assignes_a,assigne_a,rdv_veto_cabinet,rdv_veto_motif';
  const assigneesAMoi = () => activeProfileId
    ? supabase.from('plan_taches').select(colsR).eq('assigned_profile_id', activeProfileId)
    : supabase.from('plan_taches').select(colsR).eq('assigned_to', userUid);

  const tachesAMoi = () => activeProfileId
    ? supabase.from('taches_elevage').select(colsT).eq('assigne_profile_id', activeProfileId)
    : supabase.from('taches_elevage').select(colsT).eq('assigne_a', userUid);

  const carnetP = animauxDuProfil(ownerUid, activeProfileId).then(ids => rappelsCarnet(ids, end, today)).catch(() => [] as LigneTB[]);

  const [rVenir, rRetard, rMoi, rMoiRetard, tVenir, tRetard, tMoi, tMoiRetard, ev, membres, contrats, recups] = await Promise.all([
    avecProfil(() => supabase.from('plan_taches').select(colsR).gte('date_prevue', today).lte('date_prevue', end).limit(300)),
    avecProfil(() => supabase.from('plan_taches').select(colsR).neq('statut', 'fait').lt('date_prevue', today).order('date_prevue', { ascending: false }).limit(200)),
    assigneesAMoi().gte('date_prevue', today).lte('date_prevue', end).limit(300),
    assigneesAMoi().neq('statut', 'fait').lt('date_prevue', today).limit(200),
    avecProfil(() => supabase.from('taches_elevage').select(colsT).gte('date', today).lte('date', end).limit(300)),
    avecProfil(() => supabase.from('taches_elevage').select(colsT).neq('statut', 'fait').lt('date', today).order('date', { ascending: false }).limit(200)),
    // Assignées au profil actif (miroir appli agenda_page.dart).
    tachesAMoi().gte('date', today).lte('date', end).limit(300),
    tachesAMoi().neq('statut', 'fait').lt('date', today).limit(200),
    (activeProfileId
      ? supabase.from('agenda_events').select('id,titre,date_debut,type,animal_id').eq('pro_profile_id', activeProfileId)
      : supabase.from('agenda_events').select('id,titre,date_debut,type,animal_id').eq('uid', userUid).or('pro_profile_id.is.null,pro_profile_id.eq.'))
      .gte('date_debut', new Date(`${today}T00:00:00`).toISOString()).lte('date_debut', `${end}T23:59:59`).order('date_debut').limit(300),
    loadMembres(ownerUid, 'eleveur', userUid).catch(() => []),
    // Contrats de l'élevage (app/elevage/contrat/page.tsx) qui attendent une action.
    supabase.from('documents_animaux').select('id,titre,statut,animal_id,created_at')
      .eq('uid_eleveur', ownerUid).in('type', ['contrat_vente', 'contrat_reservation', 'certificat_cession', 'contrat_saillie'])
      .in('statut', ['brouillon', 'en_attente', 'partiellement_signe']).order('created_at', { ascending: false }).limit(50),
    // Demandes de récupération (app/mes-animaux/recuperations/page.tsx).
    supabase.from('animal_recuperations').select('id,animal_id,created_at')
      .eq('eleveur_uid', ownerUid).eq('statut', 'en_attente').order('created_at', { ascending: false }).limit(50),
  ]);

  const nomMembre = new Map<string, string>((membres as { uid: string; nom: string }[]).map(m => [m.uid, m.nom]));
  const responsable = (uid?: string | null) => (uid ? nomMembre.get(uid) ?? null : null);

  // Protocoles : dédoublonnés (assignées à moi ∪ tâches de l'élevage).
  const vusR = new Set<string>();
  const routines = ([...(rVenir.data ?? []), ...(rRetard.data ?? []), ...(rMoi.data ?? []), ...(rMoiRetard.data ?? [])] as RoutineBrute[])
    .filter(r => (vusR.has(r.id) ? false : (vusR.add(r.id), true)));
  const vusT = new Set<string>();
  const taches = (await sansAutresProfils([...(tVenir.data ?? []), ...(tRetard.data ?? []), ...(tMoi.data ?? []), ...(tMoiRetard.data ?? [])] as TacheBrute[], activeProfileId, userUid))
    .filter(t => (vusT.has(t.id) ? false : (vusT.add(t.id), true)));
  const evenements = await sansAutresProfils((ev.data ?? []) as EvenementBrut[], activeProfileId, userUid);

  const aFaire: LigneTB[] = [];
  const soins: LigneTB[] = [];
  const agenda: LigneTB[] = [];

  // Soins d'un protocole : une ligne par étape et par jour (tous les animaux), validée
  // en une fois depuis l'accueil (carnet + registre) — ValiderSoinsProtocoleModal.
  const groupesProto = new Map<string, RoutineBrute[]>();
  for (const r of routines) {
    const date = r.date_prevue.slice(0, 10);
    const fait = r.statut === 'fait';
    const ligne: LigneTB = {
      cle: `r_${r.id}`, titre: sansPictos(r.label || 'Tâche'), date, animal: r.animal_nom ?? null,
      responsable: responsable(r.assigned_to), fait, retard: !fait && date < today, lien: lienJour(date),
    };
    if (ACTES_CARNET.includes(r.type_acte ?? '')) {
      const k = `${date}|${r.etape_id ?? sansPictos(r.label || '')}`;
      groupesProto.set(k, [...(groupesProto.get(k) ?? []), r]);
    } else {
      aFaire.push({ ...ligne, cochable: { table: 'plan_taches', ligne: r } });
    }
  }
  for (const [k, g] of groupesProto) {
    const date = g[0].date_prevue.slice(0, 10);
    const restantes = g.filter(r => r.statut !== 'fait');
    const fait = restantes.length === 0;
    soins.push({
      cle: `p_${k}`, titre: sansPictos(g[0].label || 'Soin'), date,
      animal: g.map(r => r.animal_nom).filter(Boolean).join(', ') || null,
      responsable: responsable(g[0].assigned_to), fait, retard: !fait && date < today,
      lien: '/elevage/planning', sousTitre: fait ? 'Protocole — fait' : `Protocole${g.length > 1 ? ` — ${restantes.length}/${g.length} à faire` : ''}`,
      protocole: restantes,
    });
  }

  const carnet = await carnetP;
  soins.push(...grouperRappels(carnet));
  const soinsDuJour = new Set(carnet.map(l => l.cleSoin!));
  for (const t of taches) {
    const date = t.date.slice(0, 10);
    const fait = t.statut === 'fait';
    const resp = responsable(t.assigne_a ?? t.assignes_a?.[0] ?? null);
    if (t.rdv_veto_cabinet) {
      if (date < today && fait) continue;
      agenda.push({
        cle: `t_${t.id}`, titre: sansPictos(t.titre), date, heure: t.heure ?? null, animal: t.animal_nom ?? null,
        responsable: resp, fait, retard: !fait && date < today, lien: lienJour(date), couleur: COULEUR_TYPE.visite,
        sousTitre: [t.rdv_veto_cabinet, t.rdv_veto_motif].filter(Boolean).join(' · ') || null,
      });
      continue;
    }
    const acte = acteDe(t.titre, ACTE_TITRE);
    const ligne: LigneTB = {
      cle: `t_${t.id}`, titre: sansPictos(t.titre), date, heure: t.heure ?? null, animal: t.animal_nom ?? null,
      responsable: resp, fait, retard: !fait && date < today, lien: lienJour(date),
    };
    if (acte) {
      // Même rappel déjà listé depuis le carnet : la tâche du jour n'est pas répétée.
      if (t.animal_id && soinsDuJour.has(`${date}|${acte}|${t.animal_id}`)) continue;
      soins.push({ ...ligne, sousTitre: 'Rappel du carnet' });
    } else {
      aFaire.push({ ...ligne, cochable: { table: 'taches_elevage', ligne: t } });
    }
  }

  for (const e of evenements) {
    const date = jourLocal(e.date_debut);
    // Copie d'agenda d'un rappel du carnet : déjà listée depuis le carnet.
    if (e.type === 'medication' && acteDe(e.titre, ACTE_RAPPEL)) continue;
    if (date < today) continue;
    const d = new Date(e.date_debut);
    const heure = d.getHours() || d.getMinutes() ? `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}` : null;
    agenda.push({
      cle: `e_${e.id}`, titre: sansPictos(e.titre), date, heure, fait: false, retard: false, lien: lienJour(date),
      couleur: COULEUR_TYPE[e.type ?? ''] ?? COULEUR_TYPE.autre,
    });
  }

  // Ordre : en retard d'abord (le plus ancien en tête), puis par jour et heure ; faites en dernier dans la journée.
  const tri = (a: LigneTB, b: LigneTB) =>
    Number(b.retard) - Number(a.retard) || a.date.localeCompare(b.date) || Number(a.fait) - Number(b.fait)
    || (a.heure ?? '99').localeCompare(b.heure ?? '99') || a.titre.localeCompare(b.titre);
  aFaire.sort(tri); soins.sort(tri); agenda.sort(tri);

  // Contrats et récupérations : seulement les animaux de CE profil.
  const contratsL = await sansAutresProfils((contrats.data ?? []) as { id: string; titre?: string | null; statut: string; animal_id?: unknown; created_at: string }[], activeProfileId, userUid);
  const recupsL = await sansAutresProfils((recups.data ?? []) as { id: string; animal_id?: unknown; created_at: string }[], activeProfileId, userUid);
  const idsAnimaux = [...new Set([...contratsL, ...recupsL].map(x => x.animal_id).filter(a => a != null && a !== '').map(String))];
  const noms = new Map<string, string>();
  if (idsAnimaux.length) {
    const { data } = await supabase.from('animaux').select('id, nom').in('id', idsAnimaux);
    (data ?? []).forEach((a: { id: string | number; nom?: string | null }) => noms.set(String(a.id), a.nom ?? ''));
  }

  return {
    aFaire, soins, agenda,
    contrats: contratsL.map(c => ({
      id: c.id, titre: sansPictos(c.titre || 'Contrat'), statut: c.statut,
      animal_nom: c.animal_id != null ? noms.get(String(c.animal_id)) || null : null, date: c.created_at,
    })),
    recuperations: recupsL.map(r => ({ id: r.id, animal_nom: noms.get(String(r.animal_id)) || 'Animal', date: r.created_at })),
  };
}
