import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { requireUser } from '@/lib/server-auth';
import { adresseClient, clientDuSejour, nomComplet } from '@/lib/client-pension';
import { pensionPrixNuit, pensionTarifKeyForEspece, pensionTarifPourKey, type TarifsPension } from '@/lib/pension-especes';

// Pension — contrat d'hébergement d'un séjour (documents_animaux,
// type contrat_hebergement). POST { entreeId, entreeIds?, transmettre? } (pension ou
// cogérant) : crée ou met à jour le contrat avec une photographie complète
// dans metadata — client (séjour, sinon demande de séjour, sinon propriétaire
// de la fiche), animal, dates, hébergement, tarif / nuit, total, acompte. La
// page de signature et le PDF de l'appli lisent ces données sans dépendre de
// pension_entrees (illisible pour le client). Les signatures déjà posées sont
// conservées. `transmettre` : statut en_attente + notification au client.
// Réponse : id, token, statut, client_email / client_nom, signe_pro / signe_client.
const admin = createClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.SUPABASE_SERVICE_ROLE_KEY ?? '', { auth: { persistSession: false } });

type Ligne = Record<string, unknown>;
const txt = (v: unknown) => (typeof v === 'string' && v.trim() ? v.trim() : null);

async function estGestionnaire(proUid: string, uid: string) {
  if (proUid === uid) return true;
  const { data } = await admin.from('elevage_cogerants').select('id').eq('uid_gerant', proUid).eq('uid_cogerant', uid).eq('statut', 'actif').is('date_fin', null).limit(1);
  return (data ?? []).length > 0;
}

export async function POST(req: NextRequest) {
  const auth = await requireUser(req);
  if (auth instanceof NextResponse) return auth;
  const b = await req.json().catch(() => ({})) as { entreeId?: string; entreeIds?: string[]; transmettre?: boolean };
  const { data: en } = await admin.from('pension_entrees').select('*').eq('id', b.entreeId ?? '').maybeSingle();
  const e = en as Ligne | null;
  if (!e) return NextResponse.json({ error: 'Séjour introuvable' }, { status: 404 });
  const proUid = String(e.pro_uid);
  if (!(await estGestionnaire(proUid, auth.uid))) return NextResponse.json({ error: 'Réservé à la pension' }, { status: 403 });
  const animalId = txt(e.animal_id);

  // Client du séjour (demande, sinon propriétaire de la fiche — profil exact :
  // un élevage reste l'élevage) et ses coordonnées (profil, compte, séjour).
  const client = await clientDuSejour(admin, e, proUid);
  const clientUid = client.uid, clientProfileId = client.profileId;
  const clientNom = nomComplet(client) || null;
  const clientEmail = client.email || null;
  const clientTel = client.tel || null;
  const clientAdresse = adresseClient(client) || null;

  // Plusieurs animaux du même client (arrivée groupée) : un seul contrat qui
  // les liste tous (`entreeIds`) ; le séjour `entreeId` porte le contrat.
  const idsGroupe = [...new Set([String(e.id), ...(Array.isArray(b.entreeIds) ? b.entreeIds.map(String) : [])])].slice(0, 20);
  let sejours: Ligne[] = [e];
  if (idsGroupe.length > 1) {
    const { data: autres } = await admin.from('pension_entrees').select('*').in('id', idsGroupe).eq('pro_uid', proUid);
    sejours = [e, ...((autres ?? []) as Ligne[]).filter(x => String(x.id) !== String(e.id))];
  }

  type Tarifs = TarifsPension & { reductions_long_sejour?: { min_nuits: number; pourcentage: number }[] };
  let tarifs: Tarifs | null = null;
  let arrhes: number | null = null;
  if (txt(e.pro_profile_id)) {
    const { data } = await admin.from('user_profiles').select('tarifs_pension').eq('id', e.pro_profile_id as string).maybeSingle();
    tarifs = ((data as Ligne | null)?.tarifs_pension ?? null) as Tarifs | null;
  }
  {
    const { data } = await admin.from('users').select('arrhes_pourcentage').eq('uid', proUid).maybeSingle();
    const a = Number((data as Ligne | null)?.arrhes_pourcentage);
    arrhes = Number.isFinite(a) && a > 0 ? a : null;
  }
  // Hébergement + tarif de chaque séjour (tarifs par espèce, box / pré, réductions séjour long).
  const lignes: { nom: string; espece: string | null; race: string | null; puce: string | null; logement: string | null; tarifNuit: number; nuits: number | null; total: number | null; reduction: number; debut: string | null; fin: string | null }[] = [];
  for (const x of sejours) {
    let logementNom: string | null = null, logementType: string | null = null;
    if (txt(x.logement_id)) {
      const { data } = await admin.from('enclos_chenil').select('nom, type').eq('id', x.logement_id as string).maybeSingle();
      logementNom = txt((data as Ligne | null)?.nom); logementType = txt((data as Ligne | null)?.type);
    }
    const debut = txt(x.date_entree), fin = txt(x.date_sortie_prevue);
    const nuits = debut && fin ? Math.max(1, Math.round((new Date(`${fin}T12:00:00`).getTime() - new Date(`${debut}T12:00:00`).getTime()) / 86400000)) : null;
    const key = pensionTarifKeyForEspece(txt(x.espece));
    const especesTarifs = (tarifs as Tarifs | null)?.especes;
    const t = key && Array.isArray(especesTarifs) ? pensionTarifPourKey(especesTarifs, key) : undefined;
    const tarifNuit = t ? pensionPrixNuit(t, { seul: x.seul_dans_logement !== false, hebergement: logementType }) : 0;
    let reduction = 0;
    for (const r of (tarifs as Tarifs | null)?.reductions_long_sejour ?? []) if (nuits && nuits >= (r.min_nuits ?? 0)) reduction = r.pourcentage ?? 0;
    const total = tarifNuit > 0 && nuits ? Math.round(tarifNuit * nuits * (1 - reduction / 100) * 100) / 100 : null;
    lignes.push({ nom: txt(x.animal_nom) ?? 'Animal', espece: txt(x.espece), race: txt(x.race), puce: txt(x.puce), logement: logementNom, tarifNuit, nuits, total, reduction, debut, fin });
  }
  const groupe = lignes.length > 1;
  const l0 = lignes[0];
  const debut = lignes.map(l => l.debut).filter(Boolean).sort()[0] ?? null;
  const fin = lignes.map(l => l.fin).filter(Boolean).sort().reverse()[0] ?? null;
  const nuits = groupe ? Math.max(0, ...lignes.map(l => l.nuits ?? 0)) || null : l0.nuits;
  const tarifNuit = lignes.reduce((t, l) => t + l.tarifNuit, 0);
  const total = lignes.every(l => l.total != null) ? Math.round(lignes.reduce((t, l) => t + (l.total ?? 0), 0) * 100) / 100 : null;
  const reduction = groupe ? 0 : l0.reduction;
  const liste = (f: (l: typeof l0) => string | null) => lignes.map(l => { const v = f(l); return v ? `${l.nom} : ${v}` : null; }).filter(Boolean).join(' · ') || null;
  // Règlement (Tarifs) : arrhes facultatives + moment du solde ; ancien réglage en repli.
  const reglement = (tarifs as (Tarifs & { reglement?: { arrhes_pct?: number | null; solde?: string } }) | null)?.reglement;
  if (reglement) arrhes = (reglement.arrhes_pct ?? 0) > 0 ? Number(reglement.arrhes_pct) : null;
  const soldeMoment = reglement?.solde === 'depart' ? 'depart' : 'arrivee';
  const arrhesMontant = arrhes && total ? Math.round(total * arrhes) / 100 : null;

  const snapshot: Ligne = {
    client_nom: clientNom, client_email: clientEmail, client_tel: clientTel, client_adresse: clientAdresse,
    client_uid: clientUid, client_profile_id: clientProfileId,
    acquereur_nom: clientNom, acquereur_email: clientEmail, acquereur_tel: clientTel,
    // Plusieurs animaux : « Arya (chien — Berger), Luna (chat) », identification
    // et logement par animal, tarif / nuit et total pour l'ensemble.
    animal_nom: groupe ? lignes.map(l => `${l.nom}${l.espece ? ` (${l.espece}${l.race ? ` — ${l.race}` : ''})` : ''}`).join(', ') : txt(e.animal_nom),
    espece: groupe ? null : txt(e.espece), race: groupe ? null : txt(e.race),
    puce: groupe ? liste(l => l.puce) : txt(e.puce),
    date_entree: debut, date_sortie_prevue: fin, essai: e.essai === true,
    logement_nom: groupe ? liste(l => l.logement) : l0.logement, tarif_nuit: tarifNuit > 0 ? tarifNuit : null, nb_nuits: nuits,
    reduction_pct: reduction || null, prix_total: total, arrhes_pourcentage: arrhes,
    arrhes_montant: arrhesMontant, solde_moment: soldeMoment,
    consignes_sejour: txt(e.consignes_sejour),
    entree_ids: lignes.length > 1 ? sejours.map(x => String(x.id)) : null,
  };

  const { data: ex } = await admin.from('documents_animaux').select('id, token, statut, metadata')
    .in('pension_entree_id', sejours.map(x => String(x.id))).eq('type', 'contrat_hebergement').limit(1).maybeSingle();
  const exist = ex as { id: string; token: string; statut: string; metadata: Ligne | null } | null;
  let id: string, token: string, statut: string;
  if (exist) {
    statut = b.transmettre && (exist.statut === 'brouillon' || !exist.statut) ? 'en_attente' : exist.statut;
    await admin.from('documents_animaux').update({
      metadata: { ...(exist.metadata ?? {}), ...snapshot },
      statut, ...(clientUid ? { uid_acquereur: clientUid, acquereur_profile_id: clientProfileId } : {}),
      ...(animalId ? { animal_id: animalId } : {}),
      ...(txt(e.pro_profile_id) ? { pro_profile_id: e.pro_profile_id } : {}),
    }).eq('id', exist.id);
    id = exist.id; token = exist.token;
  } else {
    statut = b.transmettre ? 'en_attente' : 'brouillon';
    const { data: cree, error } = await admin.from('documents_animaux').insert({
      uid_eleveur: proUid, pro_profile_id: txt(e.pro_profile_id), pension_entree_id: e.id, type: 'contrat_hebergement',
      titre: `Contrat d'hébergement — ${groupe ? lignes.map(l => l.nom).join(', ') : txt(e.animal_nom) ?? ''}`, statut, metadata: snapshot,
      ...(clientUid ? { uid_acquereur: clientUid, acquereur_profile_id: clientProfileId } : {}), ...(animalId ? { animal_id: animalId } : {}),
    }).select('id, token').single();
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });
    id = (cree as { id: string }).id; token = (cree as { token: string }).token;
  }

  if (b.transmettre && clientUid) {
    const { data: pp } = await admin.from('user_profiles').select('nom').eq('id', (e.pro_profile_id as string) ?? '').maybeSingle();
    await admin.from('notifications').insert({
      uid: clientUid, ...(clientProfileId ? { profile_id: clientProfileId } : {}), type: 'contrat_invite',
      title: 'Contrat à signer',
      body: `${txt((pp as Ligne | null)?.nom) ?? 'La pension'} vous envoie le contrat d'hébergement de ${groupe ? lignes.map(l => l.nom).join(', ') : txt(e.animal_nom) ?? 'votre animal'} : vérifiez et signez`,
      data: { token, url: `/signer-contrat/${token}` }, read: false,
    });
  }
  // Signature de la pension déjà posée ? (finalisation : signer d'office avec la signature enregistrée)
  const { data: apres } = await admin.from('documents_animaux').select('metadata, statut').eq('id', id).maybeSingle();
  const meta = ((apres as { metadata?: Ligne | null } | null)?.metadata ?? {}) as Ligne;
  return NextResponse.json({
    ok: true, id, token, statut: (apres as { statut?: string } | null)?.statut ?? statut, client_notifie: !!(b.transmettre && clientUid),
    client_email: clientEmail, client_nom: clientNom, client_a_compte: !!clientUid,
    signe_pro: !!txt(meta.signature_eleveur), signe_client: !!txt(meta.signature_acquereur),
  });
}
