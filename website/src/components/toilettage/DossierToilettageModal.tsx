'use client';
// Toiletteur — dossier d'une séance (rdv) : compte rendu de toilettage (fiche
// de séance + conseils de soin du pelage, partagé au propriétaire), contrat de
// prestation, facture. Pas de compte rendu vétérinaire ni d'ordonnance.
// Miroir appli : toilettage_dossier_seance.dart.
import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import ContactCanaux from '@/components/ContactCanaux';
import SeanceToilettageModal, { type RdvSeance } from '@/components/toilettage/SeanceToilettageModal';
import ConsignesRdvForm from '@/components/ConsignesRdvForm';
import { apiFetch } from '@/lib/api-fetch';
import { reponsesAffichables } from '@/lib/consignes-rdv';
import { envoyerContratParEmail } from '@/lib/contrat-email';

const TEAL = '#0C5C6C';
const AMBRE = '#D97706';
const VERT = '#2E7D5E';
const GRIS = '#6B7280';
const MODES_PAIEMENT = ['Carte bancaire', 'Espèces', 'Virement bancaire', 'Chèque'];

interface RdvRow {
  id: string; date_heure: string; duree_minutes: number | null; statut: string; motif: string | null;
  animal_id: string | null; animal_nom_manuel?: string | null; client_uid: string | null; client_profile_id: string | null;
  prestation_id: string | null; prix_calcule?: number | null; pro_uid?: string; pro_profile_id?: string | null; employe_id?: string | null;
  client_telephone_manuel?: string | null; client_email_manuel?: string | null;
  consignes?: Record<string, string> | null; consignes_le?: string | null; consignes_demandees_le?: string | null;
}
interface Seance { id: string; compte_rendu: string | null; partage_proprietaire: boolean }
interface Contrat { id: string; token: string; statut: string }
interface Facture { id: string; statut: string; total_ttc: number | null; pdf_url: string | null; numero_affichage?: string | null; numero_facture?: string | null; date_paiement?: string | null; mode_paiement?: string | null }

const jour = (d: Date) => d.toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' });
const hm = (d: Date) => d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
const eur = (n: number | null | undefined) => `${Math.round(Number(n) || 0)} €`;

export default function DossierToilettageModal({ rdvId, nomClient, animal, onClose, onChanged }: {
  rdvId: string; nomClient: string; animal?: string | null; onClose: () => void; onChanged?: () => void;
}) {
  const router = useRouter();
  const { user } = useAuth();
  const pidActif = useActiveProfile();
  const [r, setR] = useState<RdvRow | null>(null);
  const [animalNom, setAnimalNom] = useState(animal ?? '');
  const [prestation, setPrestation] = useState<{ nom: string; prix: number | null }>({ nom: 'Prestation de toilettage', prix: null });
  const [seance, setSeance] = useState<Seance | null>(null);
  const [contrat, setContrat] = useState<Contrat | null>(null);
  const [facture, setFacture] = useState<Facture | null>(null);
  const [coord, setCoord] = useState({ tel: '', email: '', prenom: '', nom: '', rue: '', cp: '', ville: '' });
  const [modePaiement, setModePaiement] = useState(MODES_PAIEMENT[0]);
  const [ouvrirCr, setOuvrirCr] = useState(false);
  const [saisirConsignes, setSaisirConsignes] = useState(false);
  const [message, setMessage] = useState('');
  const [enCours, setEnCours] = useState('');
  const [now, setNow] = useState(0);

  const charger = useCallback(async () => {
    const { data: rdv } = await supabase.from('rdv').select('*').eq('id', rdvId).maybeSingle();
    const x = rdv as RdvRow | null;
    if (!x) return;
    setR(x);
    const [pr, an, se, ct, fa, prof] = await Promise.all([
      x.prestation_id ? supabase.from('prestations_toilettage').select('nom, prix_base').eq('id', x.prestation_id).maybeSingle() : Promise.resolve({ data: null }),
      x.animal_id ? supabase.from('animaux').select('nom').eq('id', x.animal_id).maybeSingle() : Promise.resolve({ data: null }),
      supabase.from('seances_toilettage').select('id, compte_rendu, partage_proprietaire').eq('rdv_id', rdvId).maybeSingle(),
      supabase.from('documents_animaux').select('id, token, statut').eq('rdv_id', rdvId).eq('type', 'contrat_prestation_toilettage').maybeSingle(),
      supabase.from('factures').select('id, statut, total_ttc, pdf_url, numero_affichage, numero_facture, date_paiement, mode_paiement')
        .eq('source_rdv_id', rdvId).neq('statut', 'annulee').or('type_facture.is.null,type_facture.not.in.(acompte,avoir)')
        .order('created_at', { ascending: false }).limit(1).maybeSingle(),
      x.client_profile_id
        ? supabase.from('user_profiles_complet').select('firstname, lastname, phone_number, phone, email_contact, rue, code_postal, ville, rue_pro, code_postal_pro, ville_pro').eq('id', x.client_profile_id).maybeSingle()
        : Promise.resolve({ data: null }),
    ]);
    const p = pr.data as { nom?: string; prix_base?: number } | null;
    setPrestation({ nom: p?.nom || x.motif?.trim() || 'Prestation de toilettage', prix: x.prix_calcule ?? p?.prix_base ?? null });
    const nomA = (an.data as { nom?: string } | null)?.nom ?? x.animal_nom_manuel ?? '';
    if (nomA) setAnimalNom(nomA);
    setSeance(se.data as Seance | null);
    setContrat(ct.data as Contrat | null);
    setFacture(fa.data as Facture | null);
    const pf = prof.data as Record<string, string | null | undefined> | null;
    const v = (...a: (string | null | undefined)[]) => a.map(y => (y ?? '').trim()).find(Boolean) ?? '';
    setCoord({
      tel: v(pf?.phone_number, pf?.phone, x.client_telephone_manuel), email: v(pf?.email_contact, x.client_email_manuel),
      prenom: v(pf?.firstname), nom: v(pf?.lastname), rue: v(pf?.rue, pf?.rue_pro), cp: v(pf?.code_postal, pf?.code_postal_pro), ville: v(pf?.ville, pf?.ville_pro),
    });
    setNow(Date.now());
  }, [rdvId]);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    charger();
  }, [charger]);

  if (!r) return null;
  const debut = new Date(r.date_heure);
  const passee = now > 0 && debut.getTime() < now;
  const pid = r.pro_profile_id || pidActif;

  async function notifier(type: string, title: string, body: string, data: Record<string, unknown>) {
    if (!r?.client_uid) { setMessage('Client sans compte PetsMatch : transmettez par e-mail ou téléphone.'); return; }
    await supabase.from('notifications').insert({
      uid: r.client_uid, type, title, body, ...(r.client_profile_id ? { profile_id: r.client_profile_id } : {}), data, read: false,
    });
    setMessage('Transmis au client.');
  }

  async function partagerCr() {
    if (!seance?.compte_rendu?.trim()) { setMessage('Rédigez d\'abord le compte rendu.'); return; }
    await supabase.from('seances_toilettage').update({ partage_proprietaire: true, updated_at: new Date().toISOString() }).eq('id', seance.id);
    setSeance({ ...seance, partage_proprietaire: true });
    await notifier('toilettage_cr', 'Compte rendu de toilettage', `Le compte rendu du toilettage de ${animalNom || 'votre animal'} est disponible.`,
      { animalId: r?.animal_id, seance_id: seance.id });
    onChanged?.();
  }

  async function genererContrat() {
    if (!user || !r) return;
    const { data: ab } = await supabase.from('abonnements').select('plan_code').eq('uid', user.uid).eq('profil_type', 'toilettage').eq('statut', 'actif').limit(1).maybeSingle();
    if (((ab as { plan_code?: string } | null)?.plan_code ?? 'free') === 'free') { setMessage('La signature électronique des contrats est disponible avec les formules payantes.'); return; }
    const { data, error } = await supabase.from('documents_animaux').insert({
      uid_eleveur: user.uid, ...(pid ? { pro_profile_id: pid } : {}), animal_id: r.animal_id, rdv_id: r.id,
      type: 'contrat_prestation_toilettage', titre: `Contrat de prestation toilettage — ${nomClient}`, statut: 'en_attente',
      // client_uid / client_profile_id / client_email : le contrat remonte dans « Mes contrats » du client.
      metadata: { client_nom: nomClient, client_uid: r.client_uid, client_profile_id: r.client_profile_id, client_email: coord.email || null,
        prestation_nom: prestation.nom, prix_total: prestation.prix != null ? Number(prestation.prix).toFixed(2) : null },
    }).select('id, token, statut').single();
    if (error) { setMessage(error.message); return; }
    const c = data as Contrat;
    setContrat(c);
    if (r.client_uid) {
      await notifier('contrat_invite', 'Contrat de prestation à signer', 'Votre toiletteur vous envoie le contrat de votre rendez-vous — vérifiez et signez',
        { token: c.token, url: `/signer-contrat/${c.token}` });
    } else {
      // Client sans compte : contrat à signer par e-mail (lien personnel).
      const ok = await envoyerContratParEmail({ email: coord.email, clientNom: nomClient, proProfileId: pid, token: c.token, titre: 'Contrat de prestation toilettage' });
      setMessage(ok ? 'Contrat envoyé au client par e-mail.' : 'Contrat créé — adresse e-mail du client inconnue.');
    }
    onChanged?.();
  }

  async function demanderConsignes() {
    if (!r) return;
    const res = await apiFetch('/api/rdv/consignes', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: 'demander', rdvId: r.id }) });
    const j = await res.json().catch(() => ({})) as { error?: string; notifie?: boolean; email_envoye?: boolean };
    if (!res.ok) { setMessage(j.error ?? 'Demande impossible'); return; }
    setMessage(`Consignes demandées${j.email_envoye ? ' par e-mail' : ''}${j.notifie ? `${j.email_envoye ? ' et' : ''} par notification` : ''}.`);
    charger();
  }

  function facturer() {
    if (!r) return;
    try {
      // Prix TTC affiché : le HT est déduit selon le régime de TVA du pro.
      sessionStorage.setItem('pm_facture_prefill', JSON.stringify({
        nomClient: coord.nom || nomClient, prenomClient: coord.prenom || undefined, emailClient: coord.email || undefined, telClient: coord.tel || undefined,
        rueClient: coord.rue || undefined, cpClient: coord.cp || undefined, villeClient: coord.ville || undefined,
        sourceRdvId: r.id, sourceAnimalId: r.animal_id ?? undefined, clientUid: r.client_uid ?? undefined, clientProfileId: r.client_profile_id ?? undefined,
        lignes: [{ description: [prestation.nom, animalNom].filter(Boolean).join(' — ') + ` — ${debut.toLocaleDateString('fr-FR')}`, quantite: 1, prixUnitaire: 0, prixTTC: Number(prestation.prix ?? 0), tva: 20 }],
      }));
    } catch { /* facture vierge */ }
    router.push('/elevage/facturation');
  }

  async function marquerPayee() {
    if (!facture) return;
    const maj = { statut: 'payee', mode_paiement: modePaiement, date_paiement: new Date().toISOString() };
    const { error } = await supabase.from('factures').update(maj).eq('id', facture.id);
    if (error) { setMessage(error.message); return; }
    setFacture({ ...facture, ...maj });
    setMessage('Paiement enregistré : la facture est acquittée.');
    onChanged?.();
  }

  // Vrais boutons (Relancer, Saisir…) ; l'action en cours affiche « … ».
  const btn = (t: string, f: () => unknown) => (
    <button key={t} type="button" disabled={!!enCours}
      onClick={async () => { setEnCours(t); setMessage(''); try { await f(); } finally { setEnCours(''); } }}
      className="text-sm font-semibold px-3 py-1.5 rounded-full border disabled:opacity-50 hover:bg-[#0C5C6C]/5"
      style={{ color: TEAL, borderColor: TEAL }}>
      {enCours === t ? '…' : t}
    </button>
  );
  const ligne = (titre: string, etat: string, c: string, actions: React.ReactNode[]) => (
    <div className="py-2 border-b border-gray-50 last:border-0">
      <div className="flex items-center gap-2 flex-wrap">
        <span className="w-28 text-sm font-bold text-[#1E2025]">{titre}</span>
        <span className="flex-1 text-sm min-w-[140px]" style={{ color: c }}>{etat}</span>
      </div>
      {actions.length > 0 && <div className="flex flex-wrap gap-2 mt-1.5">{actions}</div>}
    </div>
  );
  const crRedige = !!seance?.compte_rendu?.trim();

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-lg p-5 max-h-[92vh] overflow-y-auto" onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
        <p className="font-bold text-[#1E2025]">{prestation.nom}</p>
        <p className="text-sm text-gray-500">{nomClient} · {jour(debut)} à {hm(debut)}{r.duree_minutes ? ` · ${r.duree_minutes} min` : ''}</p>
        {animalNom && <p className="text-sm">Animal : {animalNom}</p>}
        {message && <p className="text-sm mt-2 rounded-xl px-3 py-2 bg-[#E6F2F3]" style={{ color: TEAL }}>{message}</p>}

        <div className="mt-3 border border-gray-100 rounded-xl px-3 py-1.5">
          {ligne('Compte rendu',
            !seance ? (passee ? 'À rédiger' : 'Après la séance') : !crRedige ? 'Fiche remplie, compte rendu à rédiger' : seance.partage_proprietaire ? 'Partagé avec le client' : 'Rédigé, non partagé',
            !seance ? (passee ? AMBRE : GRIS) : seance.partage_proprietaire ? VERT : AMBRE,
            [btn(seance ? 'Ouvrir' : 'Rédiger', () => r.animal_id ? setOuvrirCr(true) : setMessage('Animal non renseigné sur le rendez-vous.')),
              ...(crRedige && !seance?.partage_proprietaire && r.client_uid ? [btn('Partager', partagerCr)] : [])])}
          {ligne('Consignes',
            r.consignes_le ? `Reçues le ${new Date(r.consignes_le).toLocaleDateString('fr-FR')}` : r.consignes_demandees_le ? `Demandées le ${new Date(r.consignes_demandees_le).toLocaleDateString('fr-FR')}, en attente` : 'Non demandées',
            r.consignes_le ? VERT : r.consignes_demandees_le ? AMBRE : GRIS,
            r.consignes_le ? [] : [btn(r.consignes_demandees_le ? 'Relancer' : 'Demander', demanderConsignes), btn('Saisir', () => setSaisirConsignes(true))])}
          {r.consignes_le && reponsesAffichables('toilettage', r.consignes).length > 0 && (
            <div className="rounded-xl bg-[#F1F7F8] px-3 py-2 mb-1.5 space-y-1">
              {reponsesAffichables('toilettage', r.consignes).map(x => (
                <p key={x.label} className="text-xs"><span className="font-bold text-[#0C5C6C]">{x.label} : </span><span className="text-gray-700 whitespace-pre-line">{x.valeur}</span></p>
              ))}
            </div>
          )}
          {ligne('Contrat',
            !contrat ? 'Non généré' : contrat.statut === 'signe' ? 'Signé' : contrat.statut === 'partiellement_signe' ? 'Signé par une partie' : 'En attente de signature',
            !contrat ? GRIS : contrat.statut === 'signe' ? VERT : AMBRE,
            !contrat ? [btn('Générer et envoyer', genererContrat)]
              : [btn('Voir', () => router.push(`/signer-contrat/${contrat.token}`)),
                ...(contrat.statut !== 'signe' && r.client_uid ? [btn('Renvoyer', () => notifier('contrat_invite', 'Contrat de prestation à signer',
                  'Votre toiletteur vous envoie le contrat de votre rendez-vous — vérifiez et signez', { token: contrat.token, url: `/signer-contrat/${contrat.token}` }))] : []),
                ...(contrat.statut !== 'signe' && !r.client_uid ? [btn('Envoyer par e-mail', async () => {
                  const ok = await envoyerContratParEmail({ email: coord.email, clientNom: nomClient, proProfileId: pid, token: contrat.token, titre: 'Contrat de prestation toilettage' });
                  setMessage(ok ? 'Contrat envoyé par e-mail.' : 'Adresse e-mail du client inconnue.');
                })] : [])])}
          {ligne('Facture',
            !facture ? (passee ? 'À émettre' : 'Non facturée')
              : facture.statut === 'payee' ? `Payée${facture.date_paiement ? ` le ${new Date(facture.date_paiement).toLocaleDateString('fr-FR')}` : ''} · ${eur(facture.total_ttc)}`
              : `Émise, non payée · ${eur(facture.total_ttc)}`,
            !facture ? (passee ? AMBRE : GRIS) : facture.statut === 'payee' ? VERT : AMBRE,
            !facture ? [btn('Facturer', facturer)]
              : [btn('Voir', () => router.push('/elevage/facturation')),
                ...(r.client_uid ? [btn('Transmettre', () => notifier('facture_recue', 'Nouvelle facture — votre toiletteur',
                  `Facture n° ${facture.numero_affichage ?? facture.numero_facture ?? ''} · ${(Number(facture.total_ttc) || 0).toFixed(2)} €`,
                  { facture_id: facture.id, ...(facture.pdf_url ? { url: facture.pdf_url } : {}) }))] : [])])}
          {facture && facture.statut !== 'payee' && (
            <div className="flex flex-wrap items-center gap-2 pb-2 pl-0 sm:pl-[7.5rem]">
              <select value={modePaiement} onChange={e => setModePaiement(e.target.value)} className="border border-gray-200 rounded-lg px-2 py-1 text-sm bg-white">
                {MODES_PAIEMENT.map(m => <option key={m}>{m}</option>)}
              </select>
              <button onClick={marquerPayee} className="px-3 py-1.5 rounded-lg text-sm font-semibold text-white" style={{ background: TEAL }}>Marquer payée</button>
            </div>
          )}
        </div>
        <p className="text-[11px] text-gray-400 mt-1">Le compte rendu partagé (avec vos conseils de soin du pelage) apparaît dans l&apos;onglet Consultations de l&apos;animal.</p>

        <div className="mt-3">
          <p className="text-sm font-semibold text-[#1E2025] mb-1.5">Contacter le client</p>
          <ContactCanaux uid={r.client_uid} tel={coord.tel} email={coord.email} sujet={`Votre rendez-vous toilettage du ${jour(debut)}`} />
        </div>
        <button onClick={onClose} className="w-full mt-4 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Fermer</button>
      </div>
      {saisirConsignes && (
        <div className="fixed inset-0 z-[60] flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={e => { e.stopPropagation(); setSaisirConsignes(false); }}>
          <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-lg p-5 max-h-[92vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
            <ConsignesRdvForm rdvId={r.id} onSaved={() => { setSaisirConsignes(false); charger(); }} />
            <button onClick={() => setSaisirConsignes(false)} className="w-full mt-3 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Fermer</button>
          </div>
        </div>
      )}
      {ouvrirCr && r.animal_id && user && pid && (
        <div onClick={e => e.stopPropagation()}>
          <SeanceToilettageModal animalId={r.animal_id} animalNom={animalNom || 'Animal'} proUid={r.pro_uid || user.uid} profileId={pid}
            rdv={{ id: r.id, date_heure: r.date_heure, duree_minutes: r.duree_minutes, client_uid: r.client_uid, client_profile_id: r.client_profile_id, employe_id: r.employe_id ?? null } as RdvSeance}
            prestation={prestation.nom} onClose={() => setOuvrirCr(false)} onSaved={() => { setOuvrirCr(false); charger(); onChanged?.(); }} />
        </div>
      )}
    </div>
  );
}
