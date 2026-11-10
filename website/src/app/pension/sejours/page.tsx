'use client';
// Pension — gestion des demandes de séjour (comme la gestion des RDV) :
//  À traiter : demandes reçues (regroupées par client et dates) → Accepter
//    (logement + heures, AccepterSejourModal) / Refuser.
//  À venir : séjours acceptés pas encore arrivés → arrhes (à facturer /
//    facturées / payées, « Facturer les arrhes »), essai (date, heure,
//    « Essai concluant » / « Non concluant » = séjour annulé), contrat.
//  Historique : refusées, annulées, arrivées.
// Écritures via la route /api/pension/sejour. Miroir appli : pension_demandes_page.dart.
import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { usePensionAccess } from '@/hooks/usePensionAccess';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { supabase } from '@/lib/supabase';
import { signerContratAvecSignaturePro, maSignaturePro, enregistrerSignaturePro } from '@/lib/signature-pro';
import SignatureProModal from '@/components/signature/SignatureProModal';
import { apiFetch } from '@/lib/api-fetch';
import AccepterSejourModal, { type DemandeSejour } from '@/components/pension/AccepterSejourModal';
import { PensionFacturationModal } from '@/components/PensionFacturationModal';
import type { PensionEntree } from '@/components/PensionEntreeModal';

const TEAL = '#0C5C6C';
const VERT = '#2E7D5E';
const ORANGE = '#B45309';
const ROUGE = '#B3261E';

type Demande = DemandeSejour & {
  client_uid: string | null; client_profile_id: string | null; statut: string; message: string | null;
  entree_id: string | null; essai_entree_id: string | null; essai_heure?: string | null; heure_essai?: string | null;
  essai_resultat?: string | null; motif_refus?: string | null; created_at?: string;
};
interface Sejour { id: string; statut: string; arrivee_reelle_le: string | null; logement_id: string | null }

const jm = (d?: string | null) => (d ? new Date(`${d.slice(0, 10)}T12:00:00`).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' }) : '');
const h = (x?: string | null) => (x ? ` (${x.replace(':', 'h')})` : '');

export default function DemandesSejourPage() {
  const router = useRouter();
  const { user, userData, isPension, loading: authLoading } = usePensionAccess();
  const pid = useActiveProfile();
  const [onglet, setOnglet] = useState<'attente' | 'avenir' | 'historique'>('attente');
  const [demandes, setDemandes] = useState<Demande[]>([]);
  const [sejours, setSejours] = useState<Record<string, Sejour>>({});
  const [clients, setClients] = useState<Record<string, string>>({});
  const [arrhesFacts, setArrhesFacts] = useState<Record<string, string>>({}); // séjour → statut de la facture d'acompte
  // Contrat par séjour : statut, document, lien de signature, signé par la pension ?
  const [contrats, setContrats] = useState<Record<string, { statut: string; id: string; token: string | null; signePro: boolean }>>({});
  const [arrhesPct, setArrhesPct] = useState<number | null>(null);
  const [loading, setLoading] = useState(true);
  const [aAccepter, setAAccepter] = useState<Demande[] | null>(null);
  const [facturer, setFacturer] = useState<PensionEntree | null>(null);
  const [enCours, setEnCours] = useState('');

  // Retour de facturation : onglet demandé dans l'adresse.
  useEffect(() => {
    const o = new URLSearchParams(window.location.search).get('onglet');
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (o === 'attente' || o === 'avenir' || o === 'historique') setOnglet(o);
  }, []);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isPension) router.push('/');
  }, [user, userData, isPension, authLoading, router]);

  const charger = useCallback(async () => {
    if (!user) return;
    let q = supabase.from('pension_demandes').select('*').eq('pro_uid', user.uid);
    if (pid) q = q.eq('pro_profile_id', pid);
    const { data } = await q.order('date_arrivee', { ascending: true });
    const ds = (data ?? []) as Demande[];
    setDemandes(ds);
    const idsSejours = [...new Set(ds.flatMap(d => [d.entree_id, d.essai_entree_id]).filter(Boolean) as string[])];
    const pids = [...new Set(ds.map(d => d.client_profile_id).filter(Boolean) as string[])];
    const [{ data: se }, { data: cl }, { data: fa }, { data: dc }, { data: tp }] = await Promise.all([
      idsSejours.length ? supabase.from('pension_entrees').select('id, statut, arrivee_reelle_le, logement_id').in('id', idsSejours) : Promise.resolve({ data: [] }),
      pids.length ? supabase.from('user_profiles_complet').select('id, firstname, lastname, nom').in('id', pids) : Promise.resolve({ data: [] }),
      idsSejours.length && pid ? supabase.from('factures').select('source_pension_entree_id, statut, type_facture').eq('profile_id', pid).in('source_pension_entree_id', idsSejours) : Promise.resolve({ data: [] }),
      idsSejours.length ? supabase.from('documents_animaux').select('id, token, pension_entree_id, statut, metadata').in('type', ['contrat_hebergement', 'contrat_document_pro']).in('pension_entree_id', idsSejours) : Promise.resolve({ data: [] }),
      pid ? supabase.from('user_profiles').select('tarifs_pension').eq('id', pid).maybeSingle() : Promise.resolve({ data: null }),
    ]);
    setSejours(Object.fromEntries(((se ?? []) as Sejour[]).map(s => [s.id, s])));
    setClients(Object.fromEntries(((cl ?? []) as { id: string; firstname: string | null; lastname: string | null; nom: string | null }[])
      .map(c => [c.id, `${c.firstname ?? ''} ${c.lastname ?? ''}`.trim() || c.nom || 'Client'])));
    const af: Record<string, string> = {};
    for (const f of (fa ?? []) as { source_pension_entree_id: string; statut: string | null; type_facture: string | null }[]) {
      if (f.statut === 'annulee') continue;
      if (f.type_facture === 'acompte' || !af[f.source_pension_entree_id]) af[f.source_pension_entree_id] = `${f.type_facture === 'acompte' ? 'acompte' : 'complete'}:${f.statut ?? 'envoyee'}`;
    }
    setArrhesFacts(af);
    const ct: Record<string, { statut: string; id: string; token: string | null; signePro: boolean }> = {};
    for (const d of (dc ?? []) as { id: string; token: string | null; pension_entree_id: string; statut: string | null; metadata: { entree_ids?: string[]; signature_eleveur?: string | null } | null }[]) {
      const v = { statut: d.statut ?? 'brouillon', id: d.id, token: d.token, signePro: !!d.metadata?.signature_eleveur };
      for (const id of [d.pension_entree_id, ...(d.metadata?.entree_ids ?? [])]) ct[id] = v;
    }
    setContrats(ct);
    const reg = (tp as { tarifs_pension?: { reglement?: { arrhes_pct?: number | null } } } | null)?.tarifs_pension?.reglement;
    setArrhesPct(reg?.arrhes_pct && reg.arrhes_pct > 0 ? reg.arrhes_pct : null);
    setLoading(false);
  }, [user, pid]);
  // eslint-disable-next-line react-hooks/set-state-in-effect
  useEffect(() => { void charger(); }, [charger]);

  // Regroupement : même client, mêmes dates, même statut.
  const groupes = Object.values(demandes.reduce<Record<string, Demande[]>>((acc, d) => {
    const k = `${d.statut}|${d.client_uid ?? d.id}|${d.client_profile_id ?? ''}|${d.date_arrivee}|${d.date_depart}`;
    (acc[k] ??= []).push(d);
    return acc;
  }, {}));
  const arrive = (g: Demande[]) => g.some(d => d.entree_id && (sejours[d.entree_id]?.arrivee_reelle_le || sejours[d.entree_id]?.statut === 'sorti'));
  const parOnglet = {
    attente: groupes.filter(g => g[0].statut === 'demande'),
    avenir: groupes.filter(g => g[0].statut === 'acceptee' && !arrive(g)),
    historique: groupes.filter(g => g[0].statut === 'refusee' || g[0].statut === 'annulee' || (g[0].statut === 'acceptee' && arrive(g))).reverse(),
  };

  async function refuser(g: Demande[]) {
    const motif = window.prompt('Motif pour le client (facultatif) : complet à ces dates…', '');
    if (motif === null) return;
    setEnCours(g[0].id);
    const r = await apiFetch('/api/pension/sejour', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'decider', demandeId: g[0].id, demandeIds: g.map(d => d.id), accepter: false, ...(motif ? { motif } : {}) }) });
    setEnCours('');
    if (!r.ok) { const j = await r.json().catch(() => ({})) as { error?: string }; window.alert(j.error ?? 'Refus impossible'); return; }
    void charger();
  }

  async function essai(g: Demande[], concluant: boolean) {
    let motif: string | null = '';
    if (!concluant) {
      motif = window.prompt('Essai non concluant : le séjour sera annulé et le client prévenu. Motif (facultatif) :', '');
      if (motif === null) return;
    }
    setEnCours(g[0].id);
    const r = await apiFetch('/api/pension/sejour', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'essai', demandeIds: g.map(d => d.id), concluant, ...(motif ? { motif } : {}) }) });
    setEnCours('');
    if (!r.ok) { const j = await r.json().catch(() => ({})) as { error?: string }; window.alert(j.error ?? 'Action impossible'); return; }
    await charger();
    // Essai concluant : place aux arrhes (si le règlement en prévoit).
    if (concluant && arrhesPct && window.confirm(`Essai concluant, le client est prévenu. Envoyer maintenant la facture d'arrhes (${arrhesPct} %) ?`)) {
      await ouvrirFacturationArrhes(g);
    }
  }

  // Signature de la pension : signature enregistrée reprise d'office, sinon
  // page du contrat pour signer (elle sera enregistrée pour la suite).
  async function signerContrat(c: { id: string; token: string | null }) {
    if (!user) return;
    if (!(await maSignaturePro(user.uid).catch(() => null))) { setASigner(c); return; }
    const ok = await signerContratAvecSignaturePro(c.id, user.uid, userData?.nameElevage || userData?.firstname || 'Pension').catch(() => false);
    if (ok) await charger();
  }
  const [aSigner, setASigner] = useState<{ id: string; token: string | null } | null>(null);

  async function ouvrirFacturationArrhes(g: Demande[]) {
    const eid = g.find(d => d.entree_id)?.entree_id;
    if (!eid) return;
    const { data } = await supabase.from('pension_entrees').select('*').eq('id', eid).maybeSingle();
    if (data) setFacturer(data as PensionEntree);
  }

  // Carte d'un groupe (fonction, pas un composant : rendue à chaque passage).
  function carte(g: Demande[]) {
    const d = g[0];
    const essaiD = g.find(x => x.essai_date);
    const resultat = g.find(x => x.essai_resultat)?.essai_resultat ?? null;
    const sejourIds = g.map(x => x.entree_id).filter(Boolean) as string[];
    const fact = sejourIds.map(i => arrhesFacts[i]).find(Boolean);
    // Contrat du séjour, ou de l'essai (fait à l'arrivée de l'essai).
    const contrat = [...sejourIds, ...(g.map(x => x.essai_entree_id).filter(Boolean) as string[])].map(i => contrats[i]).find(Boolean);
    const lib = (t: string, c: string) => <span className="text-xs font-semibold" style={{ color: c }}>{t}</span>;
    return (
      <div className="bg-white rounded-2xl border border-[#E5E8E6] p-4 space-y-2">
        <div className="flex flex-wrap items-start gap-2">
          <div className="flex-1 min-w-[180px]">
            <p className="font-bold text-[#1E2025]">
              {g.map(x => x.animal_nom ?? 'Animal').join(', ')}
              {g.some(x => x.nouveau_pensionnaire === true) && <span className="text-xs font-semibold" style={{ color: ORANGE }}> · nouveau pensionnaire</span>}
            </p>
            <p className="text-sm text-gray-600">{d.client_profile_id ? clients[d.client_profile_id] ?? 'Client' : 'Client'}</p>
            <p className="text-sm text-gray-600">Du {jm(d.date_arrivee)}{h(d.heure_arrivee)} au {jm(d.date_depart)}{h(d.heure_depart)}</p>
            {g.some(x => x.hebergement) && (
              <p className="text-xs text-gray-500">{g.filter(x => x.hebergement).map(x => `${x.animal_nom} : ${x.hebergement === 'pre' ? 'pré' : 'box'} souhaité`).join(' · ')}</p>
            )}
            {d.message && <p className="text-xs text-gray-500 italic">« {d.message} »</p>}
            {d.statut === 'refusee' || d.statut === 'annulee' ? (
              <p className="text-xs" style={{ color: ROUGE }}>{d.statut === 'refusee' ? 'Refusée' : 'Annulée'}{d.motif_refus ? ` : ${d.motif_refus}` : ''}</p>
            ) : null}
          </div>
          {d.statut === 'demande' && (
            <div className="flex gap-2">
              <button disabled={enCours === d.id} onClick={() => refuser(g)} className="text-sm font-semibold text-gray-500 px-3 py-1.5">Refuser</button>
              <button disabled={enCours === d.id} onClick={() => setAAccepter(g)} className="text-sm font-bold text-white rounded-full px-4 py-1.5 disabled:opacity-50" style={{ background: VERT }}>
                {g.length > 1 ? `Accepter les ${g.length}` : 'Accepter'}
              </button>
            </div>
          )}
        </div>

        {/* Essai */}
        {essaiD && (
          <div className="flex flex-wrap items-center gap-2 border-t border-gray-100 pt-2">
            <span className="text-sm text-[#1E2025]">Essai le {jm(essaiD.essai_date)}{h(essaiD.heure_essai)}</span>
            {resultat === 'concluant' ? lib('Essai concluant', VERT)
              : resultat === 'non_concluant' ? lib('Essai non concluant', ROUGE)
              : d.statut === 'acceptee' ? (
                <>
                  {lib('À valider après l\'essai', ORANGE)}
                  <button disabled={enCours === d.id} onClick={() => essai(g, true)} className="text-xs font-bold text-white rounded-full px-3 py-1" style={{ background: VERT }}>Essai concluant</button>
                  <button disabled={enCours === d.id} onClick={() => essai(g, false)} className="text-xs font-semibold rounded-full px-3 py-1 border" style={{ color: ROUGE, borderColor: ROUGE }}>Non concluant</button>
                </>
              ) : null}
          </div>
        )}

        {/* Arrhes + contrat (séjours acceptés) */}
        {d.statut === 'acceptee' && !arrive(g) && (
          <div className="flex flex-wrap items-center gap-3 border-t border-gray-100 pt-2">
            {essaiD && resultat !== 'concluant' && !fact ? lib('Arrhes demandées après un essai concluant', '#6b7280')
              : fact ? lib(fact.endsWith(':payee') ? (fact.startsWith('acompte') ? 'Arrhes payées' : 'Séjour payé') : (fact.startsWith('acompte') ? 'Arrhes facturées, en attente de paiement' : 'Séjour facturé'), fact.endsWith(':payee') ? VERT : ORANGE)
              : arrhesPct ? (
                <>
                  {lib(`Arrhes à facturer (${arrhesPct} %)`, ORANGE)}
                  <button onClick={() => { void ouvrirFacturationArrhes(g); }} className="text-xs font-bold text-white rounded-full px-3 py-1" style={{ background: TEAL }}>Facturer les arrhes</button>
                </>
              ) : lib('Pas d\'arrhes prévues', '#6b7280')}
            {contrat?.statut === 'signe' ? lib('Contrat signé', VERT)
              : contrat?.statut === 'partiellement_signe' && !contrat.signePro ? (
                <>
                  {lib('Contrat signé par le client — à signer par vous', ORANGE)}
                  <button onClick={() => { void signerContrat(contrat); }} className="text-xs font-bold text-white rounded-full px-3 py-1" style={{ background: TEAL }}>Signer</button>
                </>
              )
              : lib(contrat ? 'Contrat envoyé' : 'Contrat à faire à l\'arrivée', '#6b7280')}
            <Link href="/pension/registre?mouvement=a_enregistrer" className="text-xs font-semibold" style={{ color: TEAL }}>Arrivées à enregistrer</Link>
          </div>
        )}
      </div>
    );
  }

  if (!user || loading) return <div className="max-w-4xl mx-auto px-4 py-10 text-center text-gray-400">Chargement…</div>;
  const liste = parOnglet[onglet];
  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-4xl mx-auto px-4 py-5 space-y-4">
        <div className="flex items-center justify-between gap-3">
          <h1 className="text-xl font-extrabold text-[#1E2025]">Demandes de séjour</h1>
          <Link href="/pension/registre" className="text-sm font-semibold" style={{ color: TEAL }}>Registre</Link>
        </div>
        <div className="flex gap-2 flex-wrap">
          {([['attente', 'À traiter'], ['avenir', 'À venir'], ['historique', 'Historique']] as const).map(([v, l]) => (
            <button key={v} onClick={() => setOnglet(v)} className="px-4 py-1.5 rounded-full text-sm font-semibold border"
              style={onglet === v ? { background: TEAL, color: '#fff', borderColor: TEAL } : { background: '#fff', color: '#1E2025', borderColor: '#D1D5DB' }}>
              {l}{parOnglet[v].length ? ` (${parOnglet[v].length})` : ''}
            </button>
          ))}
        </div>
        {liste.length === 0 ? (
          <p className="text-sm text-gray-500 py-8 text-center">{onglet === 'attente' ? 'Aucune demande à traiter.' : onglet === 'avenir' ? 'Aucun séjour accepté à venir.' : 'Aucun historique.'}</p>
        ) : (
          <div className="space-y-3">{liste.map(g => <div key={g.map(x => x.id).join('-')}>{carte(g)}</div>)}</div>
        )}
      </div>
      {aAccepter && user && (
        <AccepterSejourModal groupe={aAccepter} uid={user.uid} proProfileId={pid || null} couleur={VERT}
          onClose={() => setAAccepter(null)} onDone={() => { setAAccepter(null); void charger(); }} />
      )}
      {aSigner && user && (
        <SignatureProModal onClose={() => setASigner(null)} onValider={async dataUrl => {
          await enregistrerSignaturePro(user.uid, dataUrl);
          const c = aSigner;
          setASigner(null);
          await signerContrat(c);
        }} />
      )}
      {facturer && (
        <PensionFacturationModal entree={facturer} proProfileId={pid || null} acompte={arrhesPct} retour="/pension/sejours?onglet=avenir"
          pensionNom={userData?.nameElevage || userData?.firstname || 'Votre pension'}
          onClose={() => { setFacturer(null); void charger(); }} />
      )}
    </div>
  );
}
