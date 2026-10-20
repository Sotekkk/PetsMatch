import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { requireUser } from '@/lib/server-auth';
import { pensionPrixNuit, pensionTarifKeyForEspece, pensionTarifPourKey, type TarifsPension } from '@/lib/pension-especes';

// Pension — contrat d'hébergement d'un séjour (documents_animaux,
// type contrat_hebergement). POST { entreeId, transmettre? } (pension ou
// cogérant) : crée ou met à jour le contrat avec une photographie complète
// dans metadata — client (séjour, sinon demande de séjour, sinon propriétaire
// de la fiche), animal, dates, hébergement, tarif / nuit, total, acompte. La
// page de signature et le PDF de l'appli lisent ces données sans dépendre de
// pension_entrees (illisible pour le client). Les signatures déjà posées sont
// conservées. `transmettre` : statut en_attente + notification au client.
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
  const b = await req.json().catch(() => ({})) as { entreeId?: string; transmettre?: boolean };
  const { data: en } = await admin.from('pension_entrees').select('*').eq('id', b.entreeId ?? '').maybeSingle();
  const e = en as Ligne | null;
  if (!e) return NextResponse.json({ error: 'Séjour introuvable' }, { status: 404 });
  const proUid = String(e.pro_uid);
  if (!(await estGestionnaire(proUid, auth.uid))) return NextResponse.json({ error: 'Réservé à la pension' }, { status: 403 });
  const animalId = txt(e.animal_id);

  // Client : demande de séjour acceptée, sinon propriétaire principal de la fiche.
  let clientUid: string | null = null, clientProfileId: string | null = null;
  const { data: dem } = await admin.from('pension_demandes').select('client_uid, client_profile_id')
    .or(`entree_id.eq.${e.id},essai_entree_id.eq.${e.id}`).limit(1).maybeSingle();
  if (dem) { clientUid = (dem as Ligne).client_uid as string; clientProfileId = ((dem as Ligne).client_profile_id as string) ?? null; }
  if (!clientUid && animalId) {
    const { data: pr } = await admin.from('animaux_proprietes').select('uid_proprio, profile_id_proprio, role_proprio')
      .eq('animal_id', animalId).is('date_fin', null).order('role_proprio', { ascending: false }).limit(1).maybeSingle();
    if (pr && (pr as Ligne).uid_proprio !== proUid) {
      clientUid = (pr as Ligne).uid_proprio as string; clientProfileId = ((pr as Ligne).profile_id_proprio as string) ?? null;
    }
  }
  let cp: Ligne | null = null;
  if (clientProfileId) {
    const { data } = await admin.from('user_profiles_complet').select('firstname, lastname, nom, phone_number, email_contact, rue, code_postal, ville').eq('id', clientProfileId).maybeSingle();
    cp = data as Ligne | null;
  }
  let emailCompte: string | null = null;
  if (clientUid) {
    const { data } = await admin.from('users').select('email').eq('uid', clientUid).maybeSingle();
    emailCompte = txt((data as Ligne | null)?.email);
  }
  const contactSejour = txt(e.proprietaire_contact);
  const clientNom = txt(e.proprietaire_nom) ?? (`${txt(cp?.firstname) ?? ''} ${txt(cp?.lastname) ?? ''}`.trim() || txt(cp?.nom));
  const clientEmail = txt(e.proprietaire_email) ?? (contactSejour?.includes('@') ? contactSejour : null) ?? txt(cp?.email_contact) ?? emailCompte;
  const clientTel = (contactSejour && !contactSejour.includes('@') ? contactSejour : null) ?? txt(cp?.phone_number);
  const clientAdresse = txt(e.proprietaire_adresse) ?? ([cp?.rue, cp?.code_postal, cp?.ville].map(txt).filter(Boolean).join(' ') || null);

  // Hébergement + tarif du séjour (tarifs par espèce, box / pré, réductions séjour long).
  let logementNom: string | null = null, logementType: string | null = null;
  if (txt(e.logement_id)) {
    const { data } = await admin.from('enclos_chenil').select('nom, type').eq('id', e.logement_id as string).maybeSingle();
    logementNom = txt((data as Ligne | null)?.nom); logementType = txt((data as Ligne | null)?.type);
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
  const debut = txt(e.date_entree), fin = txt(e.date_sortie_prevue);
  const nuits = debut && fin ? Math.max(1, Math.round((new Date(`${fin}T12:00:00`).getTime() - new Date(`${debut}T12:00:00`).getTime()) / 86400000)) : null;
  const key = pensionTarifKeyForEspece(txt(e.espece));
  const especesTarifs = (tarifs as Tarifs | null)?.especes;
  const t = key && Array.isArray(especesTarifs) ? pensionTarifPourKey(especesTarifs, key) : undefined;
  const tarifNuit = t ? pensionPrixNuit(t, { seul: e.seul_dans_logement !== false, hebergement: logementType }) : 0;
  let reduction = 0;
  for (const r of (tarifs as Tarifs | null)?.reductions_long_sejour ?? []) if (nuits && nuits >= (r.min_nuits ?? 0)) reduction = r.pourcentage ?? 0;
  const total = tarifNuit > 0 && nuits ? Math.round(tarifNuit * nuits * (1 - reduction / 100) * 100) / 100 : null;
  // Règlement (Tarifs) : arrhes facultatives + moment du solde ; ancien réglage en repli.
  const reglement = (tarifs as (Tarifs & { reglement?: { arrhes_pct?: number | null; solde?: string } }) | null)?.reglement;
  if (reglement) arrhes = (reglement.arrhes_pct ?? 0) > 0 ? Number(reglement.arrhes_pct) : null;
  const soldeMoment = reglement?.solde === 'depart' ? 'depart' : 'arrivee';
  const arrhesMontant = arrhes && total ? Math.round(total * arrhes) / 100 : null;

  const snapshot: Ligne = {
    client_nom: clientNom, client_email: clientEmail, client_tel: clientTel, client_adresse: clientAdresse,
    client_uid: clientUid, client_profile_id: clientProfileId,
    acquereur_nom: clientNom, acquereur_email: clientEmail, acquereur_tel: clientTel,
    animal_nom: txt(e.animal_nom), espece: txt(e.espece), race: txt(e.race), puce: txt(e.puce),
    date_entree: debut, date_sortie_prevue: fin, essai: e.essai === true,
    logement_nom: logementNom, tarif_nuit: tarifNuit > 0 ? tarifNuit : null, nb_nuits: nuits,
    reduction_pct: reduction || null, prix_total: total, arrhes_pourcentage: arrhes,
    arrhes_montant: arrhesMontant, solde_moment: soldeMoment,
    consignes_sejour: txt(e.consignes_sejour),
  };

  const { data: ex } = await admin.from('documents_animaux').select('id, token, statut, metadata')
    .eq('pension_entree_id', e.id).eq('type', 'contrat_hebergement').limit(1).maybeSingle();
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
      titre: `Contrat d'hébergement — ${txt(e.animal_nom) ?? ''}`, statut, metadata: snapshot,
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
      body: `${txt((pp as Ligne | null)?.nom) ?? 'La pension'} vous envoie le contrat d'hébergement de ${txt(e.animal_nom) ?? 'votre animal'} : vérifiez et signez`,
      data: { token, url: `/signer-contrat/${token}` }, read: false,
    });
  }
  return NextResponse.json({ ok: true, id, token, statut, client_notifie: !!(b.transmettre && clientUid) });
}
