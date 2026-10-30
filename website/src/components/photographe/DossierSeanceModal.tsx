'use client';
// Photographe — dossier d'une séance (rdv) : le client est le PROPRIÉTAIRE
// (pas de carnet de santé, compte rendu ni ordonnance). Devis, contrat,
// galerie, sélection du client, facture : chacun avec son statut et sa
// transmission au client. Ouvert depuis le tableau de bord, Mes rendez-vous
// et Mes clients. Miroir appli : photographe_dossier_seance.dart.
import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { geocodeAddress } from '@/lib/geocoding';
import { styleGalerie } from '@/lib/photographe';
import { envoyerContratParEmail } from '@/lib/contrat-email';
import ContactCanaux from '@/components/ContactCanaux';
import DocumentProModal from '@/components/pro/DocumentProModal';
import { TYPE_CONTRAT_PRO } from '@/lib/document-pro';
import LieuGoogleRecherche from '@/components/LieuGoogleRecherche';
import { livrerFichiers, relancerSelection, FactureNonPayeeError, JOURS_LIVRAISON, JOURS_LIVRAISON_DEFAUT, LIVRAISON_MAX, fmtTaille } from '@/lib/galeries-client';

const TEAL = '#0C5C6C';
const AMBRE = '#D97706';
const VERT = '#2E7D5E';
const ROUGE = '#B3261E';
const GRIS = '#6B7280';

export interface RdvDossier {
  id: string; date_heure: string; duree_minutes: number | null; statut: string; motif: string | null;
  lieu: string | null; lieu_type?: string | null; adresse_depart?: string | null; notes_client?: string | null;
  animal_id: string | null; animal_nom_manuel?: string | null; client_uid: string | null; client_profile_id: string | null;
  prestation_id: string | null; pro_uid?: string; pro_profile_id?: string | null;
}

export const lieuSeance = (r: Pick<RdvDossier, 'lieu' | 'lieu_type' | 'adresse_depart'>) => {
  const adr = r.adresse_depart?.trim() ?? '';
  const l = r.lieu?.trim() ?? '';
  if (r.lieu_type === 'domicile') return `À domicile : ${adr}`;
  if (r.lieu_type === 'photographe') return adr || `Lieu à préciser${l.startsWith('Souhait') ? ` — ${l}` : ''}`;
  return adr || l;
};

const jour = (d: Date) => d.toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' });
const hm = (d: Date) => d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
const eur = (n: number | null | undefined) => `${Math.round(Number(n) || 0)} €`;

interface Devis { id: string; statut: string; total_ttc: number | null; token_acceptation: string | null }
interface Contrat { id: string; token: string; statut: string }
interface Galerie { id: string; statut: string | null; nb_photos_incluses?: number | null; prix_photo_supp?: number | null; selection_confirmee_le?: string | null }
interface Facture { id: string; statut: string; total_ttc: number | null; pdf_url: string | null; numero_affichage?: string | null; numero_facture?: string | null; date_paiement?: string | null; mode_paiement?: string | null }
const MODES_PAIEMENT = ['Virement bancaire', 'Carte bancaire', 'Espèces', 'Chèque'];

export default function DossierSeanceModal({ rdv, nomClient, prestation, animal, depuisAgenda, onClose, onChanged }: {
  rdv: RdvDossier; nomClient: string; prestation: string; animal?: string | null; depuisAgenda?: boolean;
  onClose: () => void; onChanged?: () => void;
}) {
  const router = useRouter();
  const { user } = useAuth();
  const pidActif = useActiveProfile();
  const [loading, setLoading] = useState(true);
  const [devis, setDevis] = useState<Devis | null>(null);
  const [contrat, setContrat] = useState<Contrat | null>(null);
  const [galerie, setGalerie] = useState<Galerie | null>(null);
  const [facture, setFacture] = useState<Facture | null>(null);
  const [nbPhotos, setNbPhotos] = useState(0);
  const [nbChoisies, setNbChoisies] = useState(0);
  const [prix, setPrix] = useState<number | null>(null);
  const [message, setMessage] = useState('');
  const [lieuEdit, setLieuEdit] = useState<{ adresse: string; prevenir: boolean; lat: number | null; lng: number | null } | null>(null);
  // Coordonnées du client : son profil PetsMatch (à jour), sinon celles
  // saisies par le photographe sur le rendez-vous.
  // Suite de la séance (sélection → paiement → retouche → livraison).
  const [livraisonExp, setLivraisonExp] = useState<string | null>(null);
  const [modePaiement, setModePaiement] = useState(MODES_PAIEMENT[0]);
  const [joursLiv, setJoursLiv] = useState(JOURS_LIVRAISON_DEFAUT);
  const [finals, setFinals] = useState<File[]>([]);
  const [livEnCours, setLivEnCours] = useState('');
  const [coord, setCoord] = useState({ tel: '', email: '', prenom: '', nom: '', rue: '', cp: '', ville: '' });
  // Animaux de la séance (plusieurs possibles), pour les lignes de devis / facture.
  const animaux = (animal ?? '').split('+').map(x => x.trim()).filter(Boolean).join(', ');
  const designation = [prestation, animaux].filter(Boolean).join(' — ');
  const [diffusion, setDiffusion] = useState<string | null>(null);
  // Contrat : celui de PetsMatch (généré) ou le mien (PDF / photo chargé).
  const [monContrat, setMonContrat] = useState(false);
  const [r, setR] = useState(rdv);
  const [now, setNow] = useState(0);
  const pid = r.pro_profile_id || pidActif;
  const debut = new Date(r.date_heure);
  // Séance commencée (horodatage figé au chargement : rendu pur).
  const passee = now > 0 && debut.getTime() < now;

  const charger = useCallback(async () => {
    const [d, c, g, f, p] = await Promise.all([
      supabase.from('devis').select('id, statut, total_ttc, token_acceptation').eq('rdv_id', rdv.id).order('created_at', { ascending: false }).limit(1).maybeSingle(),
      supabase.from('documents_animaux').select('id, token, statut').eq('rdv_id', rdv.id).in('type', ['contrat_prestation_photo', TYPE_CONTRAT_PRO])
        .not('statut', 'in', '(annule,refuse)').order('created_at', { ascending: false }).limit(1).maybeSingle(),
      supabase.from('albums_photo').select('*').eq('rdv_id', rdv.id).maybeSingle(),
      supabase.from('factures').select('id, statut, total_ttc, pdf_url, numero_affichage, numero_facture, date_paiement, mode_paiement, type_facture').eq('source_rdv_id', rdv.id).neq('statut', 'annulee').or('type_facture.is.null,type_facture.not.in.(acompte,avoir)').order('created_at', { ascending: false }).limit(1).maybeSingle(),
      rdv.prestation_id ? supabase.from('prestations_photographe').select('prix').eq('id', rdv.prestation_id).maybeSingle() : Promise.resolve({ data: null }),
    ]);
    setDevis(d.error ? null : d.data as Devis | null);
    setContrat(c.data as Contrat | null);
    const gal = g.data as Galerie | null;
    setGalerie(gal);
    setFacture(f.data as Facture | null);
    setPrix((p.data as { prix?: number } | null)?.prix ?? null);
    const [{ data: man }, { data: prof }] = await Promise.all([
      supabase.from('rdv').select('client_telephone_manuel, client_email_manuel').eq('id', rdv.id).maybeSingle(),
      rdv.client_profile_id
        ? supabase.from('user_profiles_complet')
          .select('firstname, lastname, phone_number, phone, email_contact, rue, code_postal, ville, rue_pro, code_postal_pro, ville_pro')
          .eq('id', rdv.client_profile_id).maybeSingle()
        : Promise.resolve({ data: null }),
    ]);
    const m = man as { client_telephone_manuel?: string | null; client_email_manuel?: string | null } | null;
    const pr = prof as Record<string, string | null | undefined> | null;
    const v = (...x: (string | null | undefined)[]) => x.map(y => (y ?? '').trim()).find(Boolean) ?? '';
    setCoord({
      tel: v(pr?.phone_number, pr?.phone, m?.client_telephone_manuel), email: v(pr?.email_contact, m?.client_email_manuel),
      prenom: v(pr?.firstname), nom: v(pr?.lastname),
      // Sans adresse au profil : adresse du shooting à domicile.
      rue: v(pr?.rue, pr?.rue_pro, rdv.lieu_type === 'domicile' ? rdv.adresse_depart : null),
      cp: v(pr?.code_postal, pr?.code_postal_pro), ville: v(pr?.ville, pr?.ville_pro),
    });
    if (gal) {
      const { data: ph } = await supabase.from('album_photos').select('selectionnee').eq('album_id', gal.id);
      const l = (ph ?? []) as { selectionnee?: boolean }[];
      setNbPhotos(l.length); setNbChoisies(l.filter(x => x.selectionnee).length);
      const { data: liv } = await supabase.from('album_livraisons').select('expire_le').eq('album_id', gal.id)
        .gt('expire_le', new Date().toISOString()).limit(1).maybeSingle();
      setLivraisonExp((liv as { expire_le?: string } | null)?.expire_le ?? null);
    }
    setNow(Date.now()); setLoading(false);
  }, [rdv.id, rdv.prestation_id, rdv.client_profile_id, rdv.lieu_type, rdv.adresse_depart]);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    charger();
  }, [charger]);

  async function notifier(type: string, title: string, body: string, data: Record<string, unknown>) {
    if (!r.client_uid) { setMessage('Client sans compte PetsMatch : transmettez par e-mail ou téléphone.'); return false; }
    await supabase.from('notifications').insert({
      uid: r.client_uid, type, title, body, ...(r.client_profile_id ? { profile_id: r.client_profile_id } : {}), data, read: false,
    });
    setMessage('Transmis au client.');
    return true;
  }

  // ── Devis ──
  const creerDevis = () => {
    // Tarifs affichés TTC : le total du devis est la somme des lignes.
    const q = new URLSearchParams({ prefill: '1', rdv: r.id, nom: coord.nom || nomClient,
      ...(coord.prenom ? { prenom: coord.prenom } : {}), ...(coord.email ? { email: coord.email } : {}), ...(coord.tel ? { tel: coord.tel } : {}),
      ...(r.client_uid ? { clientUid: r.client_uid } : {}), ...(r.client_profile_id ? { clientProfileId: r.client_profile_id } : {}),
      ...(r.animal_id ? { animal: r.animal_id } : {}),
      ...(prix != null ? { ligneDesc: designation, lignePrix: String(prix) } : {}) });
    router.push(`/photographe/devis?${q.toString()}`);
  };
  async function transmettreDevis() {
    if (!devis) return;
    if (devis.statut === 'brouillon') await supabase.from('devis').update({ statut: 'envoye', updated_at: new Date().toISOString() }).eq('id', devis.id);
    await notifier('devis_recu', 'Vous avez reçu un devis', `Un devis de ${(Number(devis.total_ttc) || 0).toFixed(2)} € vous a été envoyé.`,
      { devis_id: devis.id, token: devis.token_acceptation, url: `/devis/${devis.token_acceptation}` });
    setDevis({ ...devis, statut: devis.statut === 'brouillon' ? 'envoye' : devis.statut });
    onChanged?.();
  }

  // ── Contrat ──
  async function genererContrat(choix: string) {
    if (!user) return;
    const { data: pr } = r.prestation_id
      ? await supabase.from('prestations_photographe').select('nom, prix, acompte_pourcentage').eq('id', r.prestation_id).maybeSingle()
      : { data: null };
    const p = pr as { nom?: string; prix?: number; acompte_pourcentage?: number } | null;
    const { data, error } = await supabase.from('documents_animaux').insert({
      uid_eleveur: user.uid, ...(pid ? { pro_profile_id: pid } : {}), animal_id: r.animal_id, rdv_id: r.id,
      type: 'contrat_prestation_photo', titre: `Contrat de prestation photo — ${nomClient}`, statut: 'en_attente',
      // client_uid / client_profile_id / client_email : le contrat remonte dans
      // « Mes contrats » du client (profil destinataire uniquement).
      metadata: { client_nom: nomClient, client_uid: r.client_uid ?? null, client_profile_id: r.client_profile_id ?? null,
        client_email: coord.email || null, prestation_nom: p?.nom ?? null, prix_total: p?.prix != null ? String(p.prix) : null,
        acompte_pourcentage: p?.acompte_pourcentage != null ? String(p.acompte_pourcentage) : null, autorisation_images: choix },
    }).select('id, token, statut').single();
    if (error) { setMessage(error.message); return; }
    const c = data as Contrat;
    setContrat(c); setDiffusion(null);
    await transmettreContrat(c.token);
    onChanged?.();
  }
  // Notification si le client a un compte, sinon e-mail avec le lien personnel.
  const transmettreContrat = async (token: string) => {
    if (r.client_uid) {
      return notifier('contrat_invite', 'Contrat de prestation à signer',
        'Votre photographe vous envoie le contrat de votre séance — vérifiez et signez', { token, url: `/signer-contrat/${token}` });
    }
    const ok = await envoyerContratParEmail({ email: coord.email, clientNom: nomClient, proProfileId: pid, token, titre: 'Contrat de prestation photo' });
    setMessage(ok ? 'Contrat envoyé au client par e-mail.' : 'Adresse e-mail du client inconnue : transmettez le contrat autrement.');
    return ok;
  };

  // ── Galerie ──
  async function ouvrirGalerie() {
    if (galerie) { router.push(`/photographe/galeries/${galerie.id}`); return; }
    if (!user) return;
    const { data: pr } = r.prestation_id
      ? await supabase.from('prestations_photographe').select('nb_photos, prix_photo_supp').eq('id', r.prestation_id).maybeSingle()
      : { data: null };
    const p = pr as { nb_photos?: number | null; prix_photo_supp?: number | null } | null;
    const { data, error } = await supabase.from('albums_photo').insert({
      pro_uid: user.uid, ...(pid ? { pro_profile_id: pid } : {}), rdv_id: r.id, client_uid: r.client_uid, client_profile_id: r.client_profile_id,
      titre: `Séance photo — ${nomClient}`, date_seance: r.date_heure.slice(0, 10),
      ...(p?.nb_photos != null ? { nb_photos_incluses: p.nb_photos } : {}), ...(p?.prix_photo_supp != null ? { prix_photo_supp: p.prix_photo_supp } : {}),
    }).select('id').single();
    if (error) { setMessage(error.message); return; }
    router.push(`/photographe/galeries/${(data as { id: string }).id}`);
  }

  // ── Facture ──
  async function facturer() {
    const supp = galerie?.nb_photos_incluses != null && galerie.prix_photo_supp ? Math.max(0, nbChoisies - galerie.nb_photos_incluses) : 0;
    // Acompte déjà réglé pour cette séance : déduit (facture de solde).
    const { data: acomptes } = await supabase.from('factures').select('total_ttc, numero_affichage, numero_facture')
      .eq('source_rdv_id', r.id).eq('type_facture', 'acompte').eq('statut', 'payee');
    const deductions = ((acomptes ?? []) as { total_ttc: number | null; numero_affichage?: string | null; numero_facture?: string | number | null }[])
      .filter(a => Number(a.total_ttc) > 0)
      .map(a => ({ description: `Acompte déjà réglé (facture n° ${a.numero_affichage ?? a.numero_facture ?? ''})`, quantite: 1, prixUnitaire: 0, prixTTC: -Number(a.total_ttc), tva: 20 }));
    try {
      // Tarifs affichés TTC : le HT est déduit selon le régime de TVA du pro.
      sessionStorage.setItem('pm_facture_prefill', JSON.stringify({
        nomClient: coord.nom || nomClient, prenomClient: coord.prenom || undefined,
        emailClient: coord.email || undefined, telClient: coord.tel || undefined,
        rueClient: coord.rue || undefined, cpClient: coord.cp || undefined, villeClient: coord.ville || undefined,
        sourceRdvId: r.id, sourceAnimalId: r.animal_id ?? undefined,
        clientUid: r.client_uid ?? undefined, clientProfileId: r.client_profile_id ?? undefined,
        lignes: [
          { description: `${designation} — séance du ${jour(debut)}`, quantite: 1, prixUnitaire: 0, prixTTC: prix ?? 0, tva: 20 },
          ...(supp > 0 ? [{ description: 'Photos supplémentaires', quantite: supp, prixUnitaire: 0, prixTTC: Number(galerie!.prix_photo_supp), tva: 20 }] : []),
          ...deductions,
        ],
      }));
    } catch { /* facture vierge */ }
    router.push('/elevage/facturation');
  }
  const transmettreFacture = () => facture && notifier('facture_recue', 'Nouvelle facture — votre photographe',
    `Facture n° ${facture.numero_affichage ?? facture.numero_facture ?? ''} · ${(Number(facture.total_ttc) || 0).toFixed(2)} €`,
    { facture_id: facture.id, ...(facture.pdf_url ? { url: facture.pdf_url } : {}) });

  // ── Suite de la séance ──
  async function marquerPayee() {
    if (!facture) return;
    const maj = { statut: 'payee', mode_paiement: modePaiement, date_paiement: new Date().toISOString() };
    const { error } = await supabase.from('factures').update(maj).eq('id', facture.id);
    if (error) { setMessage(error.message); return; }
    setFacture({ ...facture, ...maj });
    setMessage('Paiement enregistré : la facture est acquittée.');
    onChanged?.();
  }
  async function passerEnRetouche() {
    if (!galerie) return;
    const { error } = await supabase.from('albums_photo').update({ statut: 'en_retouche', updated_at: new Date().toISOString() }).eq('id', galerie.id);
    if (error) { setMessage(error.message); return; }
    setGalerie({ ...galerie, statut: 'en_retouche' });
    if (r.client_uid) {
      await supabase.from('notifications').insert({
        uid: r.client_uid, type: 'galerie_disponible', title: 'Vos photos sont en retouche',
        body: `${prestation} : votre photographe retouche les photos que vous avez choisies.`,
        ...(r.client_profile_id ? { profile_id: r.client_profile_id } : {}), data: { albumId: galerie.id }, read: false,
      });
    }
    onChanged?.();
  }
  async function livrer(forcer = false) {
    if (!galerie || !finals.length) return;
    try {
      const res = await livrerFichiers(galerie.id, finals, joursLiv, setLivEnCours, forcer);
      setFinals([]); setLivEnCours('');
      setMessage(res.email_envoye ? 'Livraison envoyée : le client a reçu l\'e-mail avec le lien et la date limite.' : 'Livraison publiée (aucun e-mail : adresse du client inconnue).');
      await charger(); onChanged?.();
    } catch (e) {
      setLivEnCours('');
      if (e instanceof FactureNonPayeeError) {
        if (confirm(`${e.message}\n\nLa livraison se fait normalement une fois la facture payée. Livrer quand même ?`)) livrer(true);
        return;
      }
      setMessage((e as Error).message);
    }
  }
  async function relancer() {
    if (!galerie) return;
    try {
      const res = await relancerSelection(galerie.id);
      setMessage(`Client relancé${res.email_envoye ? ' par e-mail' : ''}${res.notifiee ? `${res.email_envoye ? ' et' : ''} par notification` : ''}.`);
    } catch (e) { setMessage((e as Error).message); }
  }

  async function enregistrerLieu() {
    if (!lieuEdit?.adresse.trim()) return;
    const adr = lieuEdit.adresse.trim();
    // Lieu choisi dans Google Maps : coordonnées déjà connues.
    const geo = lieuEdit.lat != null && lieuEdit.lng != null ? { lat: lieuEdit.lat, lng: lieuEdit.lng } : await geocodeAddress(adr);
    const { error } = await supabase.from('rdv').update({
      adresse_depart: adr, ...(r.lieu_type ? {} : { lieu_type: 'photographe' }), ...(geo ? { lat_depart: geo.lat, lng_depart: geo.lng } : {}),
    }).eq('id', r.id);
    if (error) { setMessage(error.message); return; }
    if (lieuEdit.prevenir) await notifier('rdv_modifie', 'Lieu de votre séance photo', `Votre séance du ${jour(debut)} à ${hm(debut)} aura lieu : ${adr}`, { rdv_id: r.id });
    setR({ ...r, adresse_depart: adr, lieu_type: r.lieu_type ?? 'photographe' });
    setLieuEdit(null);
    onChanged?.();
  }

  const lieu = lieuSeance(r);
  const btn = (t: string, f: () => void) => <button key={t} onClick={f} className="text-sm font-semibold ml-2" style={{ color: TEAL }}>{t}</button>;
  const ligne = (titre: string, etat: string, c: string, actions: React.ReactNode[]) => (
    <div className="flex items-center gap-2 py-1.5">
      <span className="w-20 text-sm font-bold text-[#1E2025]">{titre}</span>
      <span className="flex-1 text-sm" style={{ color: c }}>{etat}</span>
      {actions}
    </div>
  );

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-lg p-5 max-h-[92vh] overflow-y-auto" onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
        <p className="font-bold text-[#1E2025]">{prestation}</p>
        <p className="text-sm text-gray-500">{nomClient} · {jour(debut)} à {hm(debut)} · {r.duree_minutes ?? 60} min</p>
        {animal && <p className="text-sm">Animal{animal.includes('+') ? 'aux' : ''} : {animal}</p>}
        {lieu && <p className="text-sm" style={{ color: lieu.startsWith('Lieu à préciser') ? AMBRE : '#1E2025' }}>{lieu}</p>}
        {r.notes_client?.trim() && <p className="text-sm" style={{ color: AMBRE }}>Demande : {r.notes_client.trim()}</p>}

        <div className="mt-3 border border-gray-100 rounded-xl px-3 py-1.5">
          {loading ? <div className="flex justify-center py-6"><div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div> : (
            <>
              {ligne('Devis',
                !devis ? 'Aucun' : devis.statut === 'accepte' ? `Accepté · ${eur(devis.total_ttc)}` : devis.statut === 'envoye' ? `Envoyé, en attente · ${eur(devis.total_ttc)}` : devis.statut === 'refuse' ? 'Refusé' : `Brouillon · ${eur(devis.total_ttc)}`,
                !devis ? GRIS : devis.statut === 'accepte' ? VERT : devis.statut === 'refuse' ? ROUGE : AMBRE,
                [!devis ? btn('Créer', creerDevis) : btn('Voir', () => router.push('/photographe/devis')),
                  ...(devis && (devis.statut === 'brouillon' || devis.statut === 'envoye') && r.client_uid ? [btn(devis.statut === 'brouillon' ? 'Envoyer' : 'Relancer', transmettreDevis)] : [])])}
              {ligne('Contrat',
                !contrat ? 'Non généré' : contrat.statut === 'signe' ? 'Signé' : contrat.statut === 'partiellement_signe' ? 'Signé par une partie' : 'En attente de signature',
                !contrat ? GRIS : contrat.statut === 'signe' ? VERT : AMBRE,
                !contrat ? [btn('Générer et envoyer', () => setDiffusion('')), btn('Charger mon contrat', () => setMonContrat(true))]
                  : [btn('Voir', () => router.push(`/signer-contrat/${contrat.token}`)), ...(contrat.statut !== 'signe' ? [btn(r.client_uid ? 'Renvoyer' : 'Envoyer par e-mail', () => { transmettreContrat(contrat.token); })] : [])])}
              {diffusion !== null && !contrat && (
                <div className="bg-gray-50 rounded-xl p-3 my-1 space-y-1.5">
                  <p className="text-xs font-semibold text-gray-600">Diffusion des photos par vous (écrite dans le contrat) :</p>
                  {([['book', 'Book et portfolio PetsMatch, sauf refus du client'], ['book_reseaux', 'Book, site, réseaux sociaux et portfolio PetsMatch'], ['aucune', 'Aucune diffusion']] as const).map(([k, l]) => (
                    <button key={k} onClick={() => genererContrat(k)} className="block w-full text-left text-sm px-3 py-2 rounded-lg bg-white border border-gray-200 hover:border-[#0C5C6C]">{l}</button>
                  ))}
                  <p className="text-[11px] text-gray-400">Une personne identifiable n&apos;est jamais diffusée sans son autorisation écrite.</p>
                </div>
              )}
              {ligne('Galerie',
                !galerie ? (passee ? 'À créer' : 'Après la séance') : `${styleGalerie(galerie.statut).label} · ${nbPhotos} photo${nbPhotos > 1 ? 's' : ''}`,
                !galerie ? (passee ? AMBRE : GRIS) : styleGalerie(galerie.statut).fg,
                [btn(galerie ? 'Ouvrir' : 'Créer', ouvrirGalerie)])}
              {galerie && (nbChoisies > 0 || galerie.selection_confirmee_le) && ligne('Sélection',
                `${nbChoisies} choisie${nbChoisies > 1 ? 's' : ''}${galerie.nb_photos_incluses != null ? ` sur ${galerie.nb_photos_incluses} incluse${galerie.nb_photos_incluses > 1 ? 's' : ''}` : ''}${galerie.selection_confirmee_le ? ' · confirmée' : ' · en cours'}`,
                galerie.selection_confirmee_le ? AMBRE : GRIS,
                [btn('Voir les photos', () => router.push(`/photographe/galeries/${galerie.id}?selection=1`))])}
              {ligne('Facture',
                !facture ? (passee ? 'À émettre' : 'Non facturée') : facture.statut === 'payee' ? `Payée · ${eur(facture.total_ttc)}` : `Émise, non payée · ${eur(facture.total_ttc)}`,
                !facture ? (passee ? AMBRE : GRIS) : facture.statut === 'payee' ? VERT : AMBRE,
                [!facture ? btn('Facturer', facturer) : btn('Voir', () => router.push('/elevage/facturation')),
                  ...(facture && r.client_uid ? [btn('Transmettre', () => { transmettreFacture(); })] : [])])}
            </>
          )}
        </div>
        <p className="text-[11px] text-gray-400 mt-1">Chaque élément garde son statut : une galerie livrée n&apos;est pas une facture payée.</p>

        {galerie && galerie.statut !== 'brouillon' && (() => {
          const selOk = !!galerie.selection_confirmee_le;
          const payOk = facture?.statut === 'payee';
          const retOk = ['en_retouche', 'livree'].includes(galerie.statut ?? '');
          const livOk = galerie.statut === 'livree';
          const tailleFinals = finals.reduce((n, f) => n + f.size, 0);
          const etape = (n: number, titre: string, fait: boolean, actif: boolean, detail: string, action?: React.ReactNode) => (
            <div className="flex gap-3 py-2 border-t border-gray-100 first:border-t-0">
              <span className="w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold text-white shrink-0"
                style={{ background: fait ? VERT : actif ? TEAL : '#D1D5DB' }}>{fait ? '✓' : n}</span>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-semibold" style={{ color: fait || actif ? '#1E2025' : GRIS }}>{titre}</p>
                <p className="text-xs" style={{ color: fait ? VERT : GRIS }}>{detail}</p>
                {actif && action && <div className="mt-1.5">{action}</div>}
              </div>
            </div>
          );
          return (
            <div className="mt-3 border border-gray-100 rounded-xl px-3 py-1">
              <p className="text-xs font-bold text-gray-500 uppercase tracking-wide pt-2">Suite de la séance</p>
              {etape(1, 'Sélection du client', selOk, !selOk,
                selOk ? `${nbChoisies} photo${nbChoisies > 1 ? 's' : ''} confirmée${nbChoisies > 1 ? 's' : ''}` : nbChoisies ? `${nbChoisies} cochée${nbChoisies > 1 ? 's' : ''}, pas encore confirmée` : 'En attente du client',
                <button onClick={relancer} className="text-sm font-semibold" style={{ color: TEAL }}>Relancer le client</button>)}
              {etape(2, 'Paiement', payOk, selOk && !payOk,
                payOk ? `Payée${facture?.date_paiement ? ` le ${new Date(facture.date_paiement).toLocaleDateString('fr-FR')}` : ''}${facture?.mode_paiement ? ` · ${facture.mode_paiement}` : ''}`
                  : facture ? `Facture émise, ${eur(facture.total_ttc)} à régler` : 'Facture à émettre',
                facture ? (
                  <div className="flex flex-wrap items-center gap-2">
                    <select value={modePaiement} onChange={e => setModePaiement(e.target.value)} className="border border-gray-200 rounded-lg px-2 py-1 text-sm bg-white">
                      {MODES_PAIEMENT.map(m => <option key={m}>{m}</option>)}
                    </select>
                    <button onClick={marquerPayee} className="px-3 py-1.5 rounded-lg text-sm font-semibold text-white" style={{ background: TEAL }}>Marquer payée</button>
                  </div>
                ) : <button onClick={facturer} className="text-sm font-semibold" style={{ color: TEAL }}>Émettre la facture</button>)}
              {etape(3, 'Retouche', retOk, selOk && !retOk,
                retOk ? (livOk ? 'Terminée' : 'En cours') : payOk ? 'À lancer' : 'Après le paiement (ou dès maintenant si vous le souhaitez)',
                <button onClick={passerEnRetouche} className="px-3 py-1.5 rounded-lg text-sm font-semibold text-white" style={{ background: TEAL }}>Passer en retouche</button>)}
              {etape(4, 'Livraison des photos finales', livOk, retOk && !livOk,
                livOk ? (livraisonExp ? `Livrée · à télécharger avant le ${new Date(livraisonExp).toLocaleDateString('fr-FR')}` : 'Livrée') : 'Fichiers retouchés, 500 Mo maximum',
                <div className="space-y-1.5">
                  <label className="block text-sm font-semibold cursor-pointer" style={{ color: TEAL }}>
                    {finals.length ? `${finals.length} fichier${finals.length > 1 ? 's' : ''} (${fmtTaille(tailleFinals)})` : 'Choisir les fichiers retouchés…'}
                    <input type="file" multiple className="hidden" onChange={e => { setFinals([...(e.target.files ?? [])]); e.target.value = ''; }} />
                  </label>
                  {tailleFinals > LIVRAISON_MAX && <p className="text-xs" style={{ color: ROUGE }}>Plus de 500 Mo : compressez ou faites deux livraisons.</p>}
                  {finals.length > 0 && (
                    <div className="flex flex-wrap items-center gap-2">
                      <select value={joursLiv} onChange={e => setJoursLiv(Number(e.target.value))} className="border border-gray-200 rounded-lg px-2 py-1 text-sm bg-white">
                        {JOURS_LIVRAISON.map(j => <option key={j} value={j}>À télécharger sous {j} jours</option>)}
                      </select>
                      <button onClick={() => livrer()} disabled={!!livEnCours || tailleFinals > LIVRAISON_MAX}
                        className="px-3 py-1.5 rounded-lg text-sm font-semibold text-white disabled:opacity-50" style={{ background: TEAL }}>
                        {livEnCours || 'Livrer au client'}
                      </button>
                    </div>
                  )}
                </div>)}
            </div>
          );
        })()}
        {message && <p className="text-sm mt-2" style={{ color: TEAL }}>{message}</p>}

        <div className="mt-2">
          {lieuEdit ? (
            <div className="py-2 space-y-2">
              {r.lieu?.startsWith('Souhait') && <p className="text-xs text-gray-500">{r.lieu}</p>}
              <LieuGoogleRecherche value={lieuEdit.adresse} autoFocus placeholder="Rechercher le lieu : plage, forêt, parc, studio, adresse…"
                onChange={v => setLieuEdit(l => (l ? { ...l, adresse: v, lat: null, lng: null } : l))}
                onSelect={x => setLieuEdit(l => (l ? { ...l, adresse: x.libelle, lat: x.lat, lng: x.lng } : l))} />
              {r.client_uid && <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={lieuEdit.prevenir} onChange={e => setLieuEdit({ ...lieuEdit, prevenir: e.target.checked })} />Prévenir le client</label>}
              <div className="flex gap-2">
                <button onClick={() => setLieuEdit(null)} className="flex-1 py-2 rounded-xl text-sm font-semibold border border-gray-200">Annuler</button>
                <button onClick={enregistrerLieu} className="flex-1 py-2 rounded-xl text-sm font-semibold text-white" style={{ background: TEAL }}>Enregistrer</button>
              </div>
            </div>
          ) : (
            <button onClick={() => setLieuEdit({ adresse: r.lieu_type === 'photographe' ? r.adresse_depart ?? '' : '', prevenir: !!r.client_uid, lat: null, lng: null })}
              className="block py-2 text-sm font-semibold" style={{ color: TEAL }}>{r.lieu_type === 'domicile' ? 'Modifier le lieu' : 'Préciser le lieu du shooting'}</button>
          )}
          <div className="py-2">
            <p className="text-sm font-semibold text-[#1E2025] mb-1.5">Contacter le client</p>
            <ContactCanaux uid={r.client_uid} tel={coord.tel} email={coord.email} sujet={`Votre séance photo du ${jour(debut)}`} />
          </div>
          {r.adresse_depart?.trim() && <a href={`https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(r.adresse_depart.trim())}`} target="_blank" rel="noopener noreferrer" className="block py-2 text-sm font-semibold" style={{ color: TEAL }}>Itinéraire jusqu&apos;au lieu</a>}
          {!depuisAgenda && <a href={`/mes-rdv?onglet=a_venir&rdv=${r.id}`} className="block py-2 text-sm font-semibold" style={{ color: TEAL }}>Voir la séance dans l&apos;agenda</a>}
        </div>
        <button onClick={onClose} className="w-full mt-3 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Fermer</button>
      </div>
      {monContrat && (
        <DocumentProModal mode="contrat" rdv={{ ...r, pro_profile_id: pid || null }} clientNom={nomClient} animalNom={animaux || undefined}
          proNom={user?.displayName ?? ''} onClose={() => setMonContrat(false)}
          onDone={() => { setMonContrat(false); setMessage('Contrat envoyé au client pour signature.'); charger(); onChanged?.(); }} />
      )}
    </div>
  );
}
