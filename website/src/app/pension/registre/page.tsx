'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { usePensionAccess } from '@/hooks/usePensionAccess';
import { supabase } from '@/lib/supabase';
import { changerLogementSejour } from '@/lib/pension-protocoles';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { PensionEntreeModal, type PensionEntree } from '@/components/PensionEntreeModal';
import { PensionJournal } from '@/components/PensionJournal';
import ArriveeDepartModal from '@/components/pension/ArriveeDepartModal';
import { PensionFacturationModal } from '@/components/PensionFacturationModal';
import { sejoursFactures } from '@/lib/pension-facture-groupee';
import { logementAccepteEspece } from '@/lib/pension-especes';
import FinalisationSejourModal from '@/components/pension/FinalisationSejourModal';
import { imprimerFeuilleJour, imprimerFichesBox } from '@/lib/pension-impressions';
import { signerContratAvecSignaturePro } from '@/lib/signature-pro';
import { thumbUrl } from '@/lib/upload-media';
import { apiFetch } from '@/lib/api-fetch';

// ── Helpers ───────────────────────────────────────────────────────────────────

const TEAL   = '#0C5C6C';
const GREEN  = '#6E9E57';
const PURPLE = '#7B5EA7';

function fmtDate(iso?: string | null) {
  if (!iso) return '—';
  try { return new Date(iso).toLocaleDateString('fr-FR'); } catch { return iso; }
}

function normalizeChip(s?: string | null) {
  return (s ?? '').replace(/[\s\-]/g, '');
}

const ESP_EMOJI: Record<string, string> = {
  chien: '', chat: '', lapin: '', oiseau: '',
  cheval: '', nac: '', ovin: '', caprin: '', porcin: '',
};
const ESP_LABEL: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', lapin: 'Lapin', oiseau: 'Oiseau',
  cheval: 'Cheval', nac: 'NAC', ovin: 'Ovin', caprin: 'Caprin', porcin: 'Porc',
};

function espEmoji(e?: string | null) { return ESP_EMOJI[e ?? ''] ?? ''; }
function espLabel(e?: string | null) { return ESP_LABEL[e ?? ''] ?? (e ?? ''); }

interface PensionFacture {
  id: string;
  entree_id: string;
  numero: string;
  animal_nom: string | null;
  proprietaire_nom: string | null;
  montant: number | null;
  statut: string;
  type?: string | null;
  date_envoi: string | null;
}

// ── Page principale ───────────────────────────────────────────────────────────

export default function RegistrePensionPage() {
  const { user, userData, isPension, loading: authLoading } = usePensionAccess();
  const router = useRouter();
  const activeProfileId = useActiveProfile();

  const [tab, setTab]                   = useState<'en_pension' | 'sorti' | 'tous'>('en_pension');
  const [entrees, setEntrees]           = useState<PensionEntree[]>([]);
  const [puceToAnimalId, setPuceToAnimalId] = useState<Record<string, string>>({});
  const [photoByAnimalId, setPhotoByAnimalId] = useState<Record<string, string>>({});
  const [logementNoms, setLogementNoms] = useState<Record<string, string>>({});
  const [factures, setFactures]         = useState<PensionFacture[]>([]);
  const [showImpayees, setShowImpayees] = useState(false);
  const [payingId, setPayingId]         = useState<string | null>(null);
  const [loading, setLoading]           = useState(true);
  const [showForm, setShowForm]         = useState(false);
  const [editEntree, setEditEntree]     = useState<PensionEntree | null>(null);
  const [filterEspece, setFilterEspece] = useState('');
  const [showFilter, setShowFilter]     = useState(false);
  const [journalFor, setJournalFor]     = useState<PensionEntree | null>(null);
  // Arrivée / sortie : fiche complète, puis suite (contrat, facture).
  const [arriveeDepart, setArriveeDepart] = useState<{ entree: PensionEntree; mode: 'arrivee' | 'depart' } | null>(null);
  // Après l'arrivée / le départ : finalisation par étapes (contrat signé et envoyé, facture).
  const [finalisation, setFinalisation] = useState<{ entree: PensionEntree; mode: 'arrivee' | 'depart'; autres?: string[] } | null>(null);
  const [facturationFor, setFacturationFor] = useState<PensionEntree | null>(null);
  const [showNonFacturees, setShowNonFacturees] = useState(false);
  // Séjours facturés par le moteur commun (factures), groupées comprises.
  const [facturesSejours, setFacturesSejours] = useState<Set<string>>(new Set());
  // Mouvements d'un jour (cartes « Arrivées / Départs aujourd'hui » de
  // l'accueil, ?mouvement=arrivees|departs) : '' = tous les séjours.
  const [mouvement, setMouvement] = useState<'' | 'presents' | 'arrivees' | 'departs' | 'a_enregistrer'>('');
  // Planning : logements (espèces, pour changer le logement attribué) et état du contrat par séjour.
  const [logementsListe, setLogementsListe] = useState<{ id: string; nom: string; especes: string[] | null }[]>([]);
  const [contrats, setContrats] = useState<Record<string, string>>({});
  // Essai facturé ? (Tarifs) — sinon il n'est jamais « à facturer ».
  const [essaiFacture, setEssaiFacture] = useState(false);
  const [jourMvt, setJourMvt] = useState('');
  useEffect(() => {
    const m = new URLSearchParams(window.location.search).get('mouvement');
    const d = new Date();
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setJourMvt(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`);
    if (m === 'presents' || m === 'arrivees' || m === 'departs' || m === 'a_enregistrer') { setMouvement(m); setTab('tous'); }
  }, []);


  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isPension) { router.push('/'); return; }
  }, [user, userData, isPension, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    let qEnt = supabase.from('pension_entrees').select('*').eq('pro_uid', user.uid).neq('statut', 'annule').order('date_entree', { ascending: false });
    if (activeProfileId) qEnt = qEnt.eq('pro_profile_id', activeProfileId) as typeof qEnt;

    let proProfileId = activeProfileId || null;
    if (!proProfileId) {
      const { data: mainProfile } = await supabase.from('user_profiles_complet')
        .select('id').eq('uid', user.uid).eq('is_main', true).maybeSingle();
      proProfileId = mainProfile?.id ?? null;
    }
    let qFact = supabase.from('pension_factures')
      .select('id, entree_id, numero, animal_nom, proprietaire_nom, montant, statut, date_envoi')
      .eq('pro_uid', user.uid).order('date_envoi', { ascending: false });
    if (proProfileId) qFact = qFact.eq('pro_profile_id', proProfileId) as typeof qFact;

    const [{ data: ent }, { data: acc }, { data: fact }, { data: enclos }] = await Promise.all([
      qEnt,
      proProfileId
        ? supabase.from('animal_access').select('animal_id').eq('pro_profile_id', proProfileId).eq('statut', 'active')
        : Promise.resolve({ data: [] as { animal_id: string }[] }),
      qFact,
      supabase.from('enclos_chenil').select('id, nom, especes').eq('uid_eleveur', user.uid),
    ]);
    setEntrees((ent ?? []) as PensionEntree[]);
    setLogementsListe((enclos ?? []) as { id: string; nom: string; especes: string[] | null }[]);
    if (proProfileId) {
      const { data: tp } = await supabase.from('user_profiles').select('tarifs_pension').eq('id', proProfileId).maybeSingle();
      setEssaiFacture(((tp as { tarifs_pension?: { essai?: { facture?: boolean } } } | null)?.tarifs_pension?.essai?.facture) === true);
    }
    // État du contrat d'hébergement des séjours en cours.
    const enCours = ((ent ?? []) as PensionEntree[]).filter(e => e.statut === 'en_pension').map(e => e.id).slice(0, 300);
    if (enCours.length) {
      const { data: docs } = await supabase.from('documents_animaux').select('pension_entree_id, statut')
        .in('type', ['contrat_hebergement', 'contrat_document_pro']).in('pension_entree_id', enCours);
      const etat: Record<string, string> = Object.fromEntries(((docs ?? []) as { pension_entree_id: string; statut: string | null }[]).map(d => [d.pension_entree_id, d.statut ?? 'brouillon']));
      // Contrats groupés (plusieurs animaux) : l'état vaut pour chaque séjour couvert.
      const { data: grp } = await supabase.from('documents_animaux').select('statut, metadata')
        .eq('uid_eleveur', user.uid).in('type', ['contrat_hebergement', 'contrat_document_pro']).not('metadata->entree_ids', 'is', null);
      for (const g of (grp ?? []) as { statut: string | null; metadata: { entree_ids?: string[] } | null }[]) {
        for (const id of g.metadata?.entree_ids ?? []) if (!etat[id]) etat[id] = g.statut ?? 'brouillon';
      }
      setContrats(etat);
    } else setContrats({});
    setFactures((fact ?? []) as PensionFacture[]);
    if (proProfileId) sejoursFactures(supabase, proProfileId).then(setFacturesSejours).catch(() => {});
    setLogementNoms(Object.fromEntries(
      ((enclos ?? []) as { id: string; nom: string | null }[]).map(l => [l.id, l.nom ?? ''])));

    const ids = [...new Set([
      ...(acc ?? []).map((a: { animal_id: string }) => a.animal_id),
      ...(ent ?? []).map((e) => e.animal_id).filter((id): id is string => !!id),
    ])];

    if (ids.length > 0) {
      const { data: animaux } = await supabase
        .from('animaux').select('id,identification,photo_url').in('id', ids);
      const map: Record<string, string> = {};
      const photos: Record<string, string> = {};
      for (const a of animaux ?? []) {
        const puce = normalizeChip(a.identification);
        if (puce) map[puce] = a.id;
        if (a.photo_url) photos[a.id] = a.photo_url;
      }
      setPuceToAnimalId(map);
      setPhotoByAnimalId(photos);
    }
    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  // Contrat du séjour (créé / mis à jour côté serveur) ouvert dans la page du contrat.
  async function ouvrirContrat(e: PensionEntree) {
    const r = await apiFetch('/api/pension/contrat', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ entreeId: e.id }) });
    const j = await r.json().catch(() => ({})) as { token?: string; id?: string; signe_pro?: boolean; error?: string };
    if (!r.ok || !j.token) { alert(j.error ?? 'Contrat impossible'); return; }
    // Signé d'avance avec la signature enregistrée de la pension (sinon elle signe sur la page).
    if (j.id && !j.signe_pro && user) {
      await signerContratAvecSignaturePro(j.id, user.uid, `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim() || 'La pension', null, true).catch(() => false);
    }
    router.push(`/signer-contrat/${j.token}`);
  }

  // Après l'arrivée : contrat / facture ; après la sortie : facture si pas encore faite.
  function apresArriveeDepart(ids?: string[]) {
    const ad = arriveeDepart;
    setArriveeDepart(null);
    load();
    if (!ad) return;
    setFinalisation({ entree: ad.entree, mode: ad.mode, autres: (ids ?? []).filter(i => i !== ad.entree.id) });
  }

  // Export CSV
  function exportCsv() {
    const rows = filtered;
    const headers = ['Nom', 'Espèce', 'Race', 'Puce', 'Client', 'Téléphone', 'Email',
      'Date entrée', 'Sortie prévue', 'Sortie effective', 'Statut', 'Notes'];
    const csv = [
      headers.join(';'),
      ...rows.map(e => [
        e.animal_nom,
        espLabel(e.espece),
        e.race ?? '',
        e.puce ?? '',
        e.proprietaire_nom ?? '',
        e.proprietaire_contact ?? '',
        e.proprietaire_email ?? '',
        fmtDate(e.date_entree),
        fmtDate(e.date_sortie_prevue),
        fmtDate(e.date_sortie_effective),
        e.statut === 'en_pension' ? 'En pension' : 'Sorti',
        (e.notes ?? '').replace(/;/g, ','),
      ].join(';')),
    ].join('\n');
    const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' });
    const url  = URL.createObjectURL(blob);
    const a    = document.createElement('a');
    a.href = url; a.download = `registre-pension-${new Date().toISOString().split('T')[0]}.csv`;
    a.click(); URL.revokeObjectURL(url);
  }

  const entreesFacturees = new Set([...factures.map(f => f.entree_id), ...facturesSejours]);

  // Séjours terminés (sortie effective enregistrée) sans aucune facture liée.
  const sejoursNonFactures = entrees.filter(e =>
    !!e.date_sortie_effective && !entreesFacturees.has(e.id) && (essaiFacture || !(e as { essai?: boolean }).essai));

  // Suivi des impayés : factures envoyées jamais marquées payées.
  const impayees = factures.filter(f => f.statut === 'envoyee');
  const seuil15j = Date.now() - 15 * 86400000;
  const debiteurs = impayees.filter(f => {
    const d = f.date_envoi ? new Date(f.date_envoi).getTime() : Date.now();
    return d < seuil15j;
  });

  async function marquerPayee(id: string) {
    setPayingId(id);
    await supabase.from('pension_factures').update({
      statut: 'payee', date_paiement: new Date().toISOString(),
    }).eq('id', id);
    setFactures(prev => prev.map(f => f.id === id ? { ...f, statut: 'payee' } : f));
    setPayingId(null);
  }

  const allEspeces = [...new Set(entrees.map(e => e.espece).filter(Boolean))] as string[];

  let filtered = entrees;
  if (tab !== 'tous') filtered = filtered.filter(e => e.statut === tab);
  if (filterEspece) filtered = filtered.filter(e => e.espece === filterEspece);
  // Présents : en pension et arrivée enregistrée (les séjours réservés ou pas encore arrivés sont exclus).
  if (mouvement === 'presents' && jourMvt) filtered = filtered.filter(e => e.statut === 'en_pension' && (e.date_entree ?? '').slice(0, 10) <= jourMvt && !!(e as { arrivee_reelle_le?: string | null }).arrivee_reelle_le);
  if (mouvement === 'arrivees' && jourMvt) filtered = filtered.filter(e => (e.date_entree ?? '').startsWith(jourMvt));
  if (mouvement === 'departs' && jourMvt) filtered = filtered.filter(e => (e.date_sortie_prevue ?? '').startsWith(jourMvt) || (e.date_sortie_effective ?? '').startsWith(jourMvt));
  // À enregistrer : arrivées pas encore faites (retards compris) jusqu'à 14 jours.
  if (mouvement === 'a_enregistrer' && jourMvt) {
    const d = new Date(`${jourMvt}T12:00:00`); d.setDate(d.getDate() + 14);
    const limite = d.toISOString().slice(0, 10);
    filtered = filtered.filter(e => e.statut === 'en_pension' && !(e as Planning).arrivee_reelle_le && (e.date_entree ?? '').slice(0, 10) <= limite);
  }
  // Planning : par jour puis par heure prévue.
  if (mouvement === 'arrivees' || mouvement === 'a_enregistrer') {
    filtered = [...filtered].sort((a, b) => `${(a.date_entree ?? '').slice(0, 10)} ${(a as Planning).heure_arrivee_prevue ?? '99'}`
      .localeCompare(`${(b.date_entree ?? '').slice(0, 10)} ${(b as Planning).heure_arrivee_prevue ?? '99'}`));
  }
  if (mouvement === 'departs') {
    filtered = [...filtered].sort((a, b) => ((a as Planning).heure_depart_prevue ?? '99').localeCompare((b as Planning).heure_depart_prevue ?? '99'));
  }

  const counts = {
    en_pension: entrees.filter(e => e.statut === 'en_pension').length,
    sorti:      entrees.filter(e => e.statut === 'sorti').length,
    tous:       entrees.length,
  };

  if (!user || !userData) return null;

  return (
    <div style={{ minHeight: '100vh', background: '#F8F8F6', paddingBottom: 60 }}>
      {/* Header */}
      <div style={{ background: TEAL, padding: '20px 24px 0' }}>
        <div style={{ maxWidth: 900, margin: '0 auto' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 16 }}>
            <button onClick={() => router.back()}
              style={{ background: 'none', border: 'none', color: 'white', fontSize: 20, cursor: 'pointer', padding: 0 }}>←</button>
            <h1 style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 20, color: 'white', flex: 1 }}>
              Nos pensionnaires
            </h1>
            <button onClick={() => setShowFilter(f => !f)}
              style={{ background: 'rgba(255,255,255,0.15)', border: '1px solid rgba(255,255,255,0.3)',
                color: 'white', borderRadius: 20, padding: '6px 14px', cursor: 'pointer',
                fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 700 }}>
              ⚙ Filtrer{filterEspece ? ' ●' : ''}
            </button>
            <button onClick={() => { if (user) void imprimerFeuilleJour(supabase, { proUid: user.uid, proProfileId: activeProfileId || null, date: jourMvt || new Date().toISOString().slice(0, 10), pensionNom: userData?.nameElevage || userData?.firstname || 'Votre pension' }); }}
              style={{ background: 'rgba(255,255,255,0.15)', border: '1px solid rgba(255,255,255,0.3)',
                color: 'white', borderRadius: 20, padding: '6px 14px', cursor: 'pointer',
                fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 700 }}>
              Feuille du jour
            </button>
            <button onClick={exportCsv} disabled={entrees.length === 0}
              style={{ background: 'rgba(255,255,255,0.15)', border: '1px solid rgba(255,255,255,0.3)',
                color: 'white', borderRadius: 20, padding: '6px 14px', cursor: 'pointer',
                fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 700,
                opacity: entrees.length === 0 ? 0.4 : 1 }}>
              ↓ CSV
            </button>
            <button onClick={() => setShowForm(true)}
              style={{ background: 'rgba(255,255,255,0.2)', border: '1px solid rgba(255,255,255,0.4)',
                color: 'white', borderRadius: 20, padding: '6px 16px', cursor: 'pointer',
                fontFamily: 'Galey, sans-serif', fontSize: 13, fontWeight: 700 }}>
              + Nouvelle entrée
            </button>
          </div>

          {/* Filtres espèce */}
          {showFilter && (
            <div style={{ marginBottom: 12, display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              {['', ...allEspeces].map(e => (
                <button key={e} onClick={() => setFilterEspece(e)}
                  style={{ padding: '4px 12px', borderRadius: 20,
                    background: filterEspece === e ? 'rgba(255,255,255,0.9)' : 'rgba(255,255,255,0.15)',
                    border: '1px solid rgba(255,255,255,0.3)',
                    color: filterEspece === e ? TEAL : 'white',
                    fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 700, cursor: 'pointer' }}>
                  {e ? espLabel(e) : 'Toutes les espèces'}
                </button>
              ))}
            </div>
          )}

          {/* Onglets */}
          <div style={{ display: 'flex', gap: 0 }}>
            {([['en_pension', 'En pension'], ['sorti', 'Sortis'], ['tous', 'Tous']] as const).map(([val, label]) => (
              <button key={val} onClick={() => setTab(val)} style={{
                flex: 1, padding: '10px 0', background: 'none', border: 'none',
                borderBottom: tab === val ? '2px solid white' : '2px solid transparent',
                color: tab === val ? 'white' : 'rgba(255,255,255,0.6)',
                fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 13, cursor: 'pointer',
              }}>
                {label}{counts[val] > 0 ? ` (${counts[val]})` : ''}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Contenu */}
      <div style={{ maxWidth: 900, margin: '24px auto', padding: '0 16px' }}>
        <div style={{ display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: 8, marginBottom: 16, fontFamily: 'Galey, sans-serif' }}>
          {([['', 'Tous les séjours'], ['a_enregistrer', 'Arrivées à enregistrer'], ['presents', 'Présents'], ['arrivees', 'Arrivées'], ['departs', 'Départs']] as const).map(([v, lib]) => (
            <button key={v} onClick={() => { setMouvement(v); if (v) setTab('tous'); }}
              style={{ padding: '6px 14px', borderRadius: 20, fontSize: 12.5, fontWeight: 700, cursor: 'pointer',
                border: `1px solid ${mouvement === v ? TEAL : '#D1D5DB'}`,
                background: mouvement === v ? 'rgba(12,92,108,0.1)' : 'white', color: mouvement === v ? TEAL : '#1F2A2E' }}>
              {lib}
            </button>
          ))}
          {(mouvement === 'arrivees' || mouvement === 'departs') && (
            <input type="date" value={jourMvt} onChange={e => setJourMvt(e.target.value)}
              style={{ padding: '5px 10px', borderRadius: 20, border: '1px solid #D1D5DB', fontSize: 12.5, color: '#1F2A2E' }} />
          )}
        </div>
        {sejoursNonFactures.length > 0 && (
          <button onClick={() => setShowNonFacturees(true)} style={{
            display: 'flex', alignItems: 'center', gap: 8, width: '100%', textAlign: 'left',
            background: '#FFF7ED', border: '1px solid #FED7AA', borderRadius: 12,
            padding: '10px 14px', marginBottom: 16, cursor: 'pointer',
          }}>
            <span style={{ fontSize: 16 }}>🧾</span>
            <span style={{ flex: 1, fontFamily: 'Galey, sans-serif', fontSize: 12.5, fontWeight: 600, color: '#9A3412' }}>
              {sejoursNonFactures.length} séjour{sejoursNonFactures.length > 1 ? 's' : ''} terminé{sejoursNonFactures.length > 1 ? 's' : ''} non facturé{sejoursNonFactures.length > 1 ? 's' : ''}
            </span>
            <span style={{ color: '#9A3412', fontSize: 16 }}>›</span>
          </button>
        )}
        {impayees.length > 0 && (
          <button onClick={() => setShowImpayees(true)} style={{
            display: 'flex', alignItems: 'center', gap: 8, width: '100%', textAlign: 'left',
            background: debiteurs.length > 0 ? '#FEF2F2' : '#F8F8F6',
            border: `1px solid ${debiteurs.length > 0 ? '#FECACA' : '#e5e7eb'}`, borderRadius: 12,
            padding: '10px 14px', marginBottom: 16, cursor: 'pointer',
          }}>
            <span style={{ fontSize: 16 }}>💳</span>
            <span style={{ flex: 1, fontFamily: 'Galey, sans-serif', fontSize: 12.5, fontWeight: 600, color: debiteurs.length > 0 ? '#991B1B' : '#6b7280' }}>
              {impayees.length} facture{impayees.length > 1 ? 's' : ''} en attente de paiement
              {debiteurs.length > 0 ? ` · ${debiteurs.length} depuis +15 j` : ''}
            </span>
            <span style={{ color: debiteurs.length > 0 ? '#991B1B' : '#9ca3af', fontSize: 16 }}>›</span>
          </button>
        )}
        {loading ? (
          <div style={{ textAlign: 'center', padding: 60, color: '#999' }}>Chargement…</div>
        ) : filtered.length === 0 ? (
          <div style={{ textAlign: 'center', padding: 60, color: '#aaa' }}>
            <div style={{ fontSize: 48, marginBottom: 12 }}>🐾</div>
            <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 16 }}>Aucune entrée</p>
            <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#ccc' }}>
              Ajoutez manuellement ou scannez une puce depuis l&apos;application mobile
            </p>
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {filtered.map(e => {
              const puce = normalizeChip(e.puce);
              const animalId = e.animal_id ?? puceToAnimalId[puce];
              return (
                <EntreeCard
                  key={e.id}
                  entree={e}
                  animalId={animalId}
                  photoUrl={animalId ? photoByAnimalId[animalId] : undefined}
                  proUid={user.uid}
                  proNom={userData?.nameElevage || userData?.firstname || 'Votre pension'}
                  isFacture={entreesFacturees.has(e.id)}
                  logementNom={e.logement_id ? logementNoms[e.logement_id] : undefined}
                  logements={logementsListe}
                  contratStatut={contrats[e.id] ?? null}
                  onLogement={async lid => {
                    const { error } = await supabase.from('pension_entrees').update({ logement_id: lid || null }).eq('id', e.id);
                    if (error) { window.alert(`Logement non enregistré : ${error.message}`); return; }
                    // Protocoles du séjour : tâches à venir sur le nouveau logement.
                    try { await changerLogementSejour(supabase, [e.id]); } catch { /* sans incidence */ }
                    load();
                  }}
                  onEdit={() => setEditEntree(e)}
                  onArrivee={e.statut === 'en_pension' && !(e as { arrivee_reelle_le?: string | null }).arrivee_reelle_le
                    ? () => setArriveeDepart({ entree: e, mode: 'arrivee' }) : undefined}
                  onSorti={() => setArriveeDepart({ entree: e, mode: 'depart' })}
                  onJournal={() => setJournalFor(e)}
                  onFacturer={() => setFacturationFor(e)}
                  onContrat={() => { void ouvrirContrat(e); }}
                  onFicheBox={() => { void imprimerFichesBox(supabase, [e.id], userData?.nameElevage || userData?.firstname || 'Votre pension'); }}
                />
              );
            })}
          </div>
        )}
      </div>

      {/* Modals */}
      {showForm && (
        <PensionEntreeModal
          proUid={user.uid}
          proProfileId={activeProfileId || null}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); load(); }}
        />
      )}
      {editEntree && (
        <PensionEntreeModal
          proUid={user.uid}
          proProfileId={activeProfileId || null}
          entree={editEntree}
          onClose={() => setEditEntree(null)}
          onSaved={() => { setEditEntree(null); load(); }}
        />
      )}
      {arriveeDepart && (
        <ArriveeDepartModal sejour={arriveeDepart.entree} mode={arriveeDepart.mode} uid={user.uid}
          onClose={() => setArriveeDepart(null)} onDone={apresArriveeDepart} />
      )}
      {finalisation && (
        <FinalisationSejourModal entree={finalisation.entree} mode={finalisation.mode} autresIds={finalisation.autres} proProfileId={activeProfileId || null}
          pensionNom={userData?.nameElevage || userData?.firstname || 'Votre pension'}
          onClose={() => { setFinalisation(null); load(); }} />
      )}
      {journalFor && (
        <PensionJournal
          pensionEntreeId={journalFor.id}
          animalId={journalFor.animal_id ?? undefined}
          animalNom={journalFor.animal_nom}
          proUid={user.uid}
          onClose={() => setJournalFor(null)}
        />
      )}
      {showNonFacturees && (
        <div style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)',
          display: 'flex', alignItems: 'flex-end', justifyContent: 'center', zIndex: 1000,
        }} onClick={e => e.target === e.currentTarget && setShowNonFacturees(false)}>
          <div style={{ background: 'white', borderRadius: '24px 24px 0 0', width: '100%', maxWidth: 500, maxHeight: '80vh', overflowY: 'auto', padding: '20px 24px 32px' }}>
            <div style={{ display: 'flex', alignItems: 'center', marginBottom: 16 }}>
              <h2 style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 17, flex: 1 }}>Séjours non facturés</h2>
              <button onClick={() => setShowNonFacturees(false)} style={{ background: 'none', border: 'none', fontSize: 22, cursor: 'pointer', color: '#9ca3af' }}>×</button>
            </div>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
              {sejoursNonFactures.map(e => (
                <button key={e.id} onClick={() => { setShowNonFacturees(false); setFacturationFor(e); }} style={{
                  display: 'flex', alignItems: 'center', gap: 10, width: '100%', textAlign: 'left',
                  background: '#F8F8F6', border: '1px solid #eee', borderRadius: 12, padding: '10px 12px', cursor: 'pointer',
                }}>
                  <span style={{ fontSize: 18 }}>{espEmoji(e.espece)}</span>
                  <div style={{ flex: 1 }}>
                    <p style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 13, color: '#1E2025' }}>{e.animal_nom}{(e as { essai?: boolean }).essai ? ' · essai' : ''}</p>
                    <p style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontSize: 11, color: '#9ca3af' }}>
                      {fmtDate(e.date_entree)} → {fmtDate(e.date_sortie_effective)} · {e.proprietaire_nom ?? '—'}
                    </p>
                  </div>
                  <span style={{ color: TEAL, fontSize: 16 }}>›</span>
                </button>
              ))}
            </div>
          </div>
        </div>
      )}
      {facturationFor && (
        <PensionFacturationModal
          entree={facturationFor}
          retour="/pension/registre"
          proProfileId={activeProfileId || null}
          pensionNom={userData?.nameElevage || userData?.firstname || 'Votre pension'}
          onClose={() => setFacturationFor(null)}
        />
      )}
      {showImpayees && (
        <div style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)',
          display: 'flex', alignItems: 'flex-end', justifyContent: 'center', zIndex: 1000,
        }} onClick={e => e.target === e.currentTarget && setShowImpayees(false)}>
          <div style={{ background: 'white', borderRadius: '24px 24px 0 0', width: '100%', maxWidth: 500, maxHeight: '80vh', overflowY: 'auto', padding: '20px 24px 32px' }}>
            <div style={{ display: 'flex', alignItems: 'center', marginBottom: 16 }}>
              <h2 style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 17, flex: 1 }}>
                Factures impayées ({impayees.length})
              </h2>
              <button onClick={() => setShowImpayees(false)} style={{ background: 'none', border: 'none', fontSize: 22, cursor: 'pointer', color: '#9ca3af' }}>×</button>
            </div>
            {impayees.length === 0 ? (
              <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#9ca3af', padding: '12px 0' }}>Aucune facture impayée.</p>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {impayees.map(f => {
                  const enRetard = f.date_envoi ? new Date(f.date_envoi).getTime() < seuil15j : false;
                  return (
                    <div key={f.id} style={{
                      display: 'flex', alignItems: 'center', gap: 10,
                      background: enRetard ? '#FEF2F2' : '#F8F8F6',
                      border: `1px solid ${enRetard ? '#FECACA' : '#eee'}`, borderRadius: 12, padding: '10px 12px',
                    }}>
                      <div style={{ flex: 1, minWidth: 0 }}>
                        <p style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 13, color: '#1E2025' }}>
                          {f.animal_nom ?? '—'} — {f.proprietaire_nom ?? '—'}
                        </p>
                        <p style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontSize: 11, color: '#9ca3af' }}>
                          {(f.montant ?? 0).toFixed(2).replace('.', ',')} € · envoyée le {fmtDate(f.date_envoi)}
                          {enRetard ? ' · en retard' : ''}
                        </p>
                      </div>
                      <button onClick={() => marquerPayee(f.id)} disabled={payingId === f.id} style={{
                        padding: '6px 12px', borderRadius: 20, border: `1px solid ${GREEN}`,
                        background: 'transparent', color: GREEN, cursor: 'pointer', whiteSpace: 'nowrap',
                        fontFamily: 'Galey, sans-serif', fontSize: 11, fontWeight: 700,
                      }}>
                        {payingId === f.id ? '…' : '✓ Marquer payée'}
                      </button>
                    </div>
                  );
                })}
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

// ── Carte entrée ──────────────────────────────────────────────────────────────

/** Champs du planning des arrivées / départs (migration_pension_horaires.sql). */
type Planning = { arrivee_reelle_le?: string | null; heure_arrivee_prevue?: string | null; heure_depart_prevue?: string | null;
  duree_arrivee_min?: number | null; duree_depart_min?: number | null; notes?: string | null };
const LIBELLE_CONTRAT: Record<string, [string, string]> = {
  brouillon: ['Contrat en brouillon', '#B45309'], en_attente: ['Contrat envoyé, à signer', '#B45309'],
  partiellement_signe: ['Contrat signé en partie (une signature manque)', '#B45309'], signe: ['Contrat signé', '#2E7D5E'],
};

function EntreeCard({ entree, animalId, photoUrl, proUid, proNom, isFacture, logementNom, logements, contratStatut, onLogement, onFicheBox, onEdit, onArrivee, onSorti, onJournal, onFacturer, onContrat }: {
  onArrivee?: () => void;
  logements: { id: string; nom: string; especes: string[] | null }[];
  contratStatut: string | null;
  onLogement: (logementId: string) => void;
  onFicheBox: () => void;
  entree: PensionEntree;
  animalId?: string;
  photoUrl?: string;
  proUid: string;
  proNom: string;
  isFacture: boolean;
  logementNom?: string;
  onEdit: () => void;
  onSorti: () => void;
  onJournal: () => void;
  onFacturer: () => void;
  onContrat: () => void;
}) {
  const inPension = entree.statut === 'en_pension';
  const bgColor   = inPension ? '#E0F2F1' : '#f3f4f6';
  const txtColor  = inPension ? TEAL : '#6b7280';
  // Séjour en cours dont la sortie prévue est passée : à sortir.
  const enRetard = inPension && !!entree.date_sortie_prevue
    && new Date(entree.date_sortie_prevue) < new Date(new Date().toDateString());
  const [sendingClaim, setSendingClaim] = useState(false);
  const [claimSent, setClaimSent] = useState(false);
  const [showActions, setShowActions] = useState(false);
  const canReclamation = !!animalId && !!entree.proprietaire_email;

  async function envoyerLienReclamation(e?: React.MouseEvent) {
    e?.stopPropagation();
    if (!animalId || !entree.proprietaire_email) return;
    setSendingClaim(true);
    try {
      const { data: claimRow, error } = await supabase.from('animal_claims').insert({
        animal_id: animalId,
        created_by_uid: proUid,
        email_destinataire: entree.proprietaire_email,
        nom_destinataire: entree.proprietaire_nom ?? null,
        tel_destinataire: entree.proprietaire_contact ?? null,
      }).select('token').single();
      if (error || !claimRow) { setSendingClaim(false); return; }
      const claimUrl = `${window.location.origin}/reclamer-animal/${claimRow.token}`;
      await apiFetch('/api/animal-claim/notify-email', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: entree.proprietaire_email,
          nom_destinataire: entree.proprietaire_nom,
          animal_nom: entree.animal_nom,
          pro_nom: proNom,
          claim_url: claimUrl,
        }),
      });
      setClaimSent(true);
    } finally {
      setSendingClaim(false);
    }
  }

  return (
    <div style={{
      background: 'white', borderRadius: 14, padding: 16,
      border: `1px solid ${inPension ? 'rgba(12,92,108,0.18)' : '#e5e7eb'}`,
      boxShadow: '0 2px 8px rgba(0,0,0,0.04)',
      cursor: 'pointer',
    }} onClick={onEdit}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 14 }}>
        {/* Photo animal (fiche propriétaire) ou icône espèce à défaut */}
        <div style={{
          width: 46, height: 46, borderRadius: 10, background: bgColor,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 22, flexShrink: 0, overflow: 'hidden',
        }}>
          {photoUrl
            ? <img src={thumbUrl(photoUrl, 96, 75, 'contain')} alt="" style={{ width: '100%', height: '100%', objectFit: 'contain' }} />
            : espEmoji(entree.espece)}
        </div>

        <div style={{ flex: 1, minWidth: 0 }}>
          {/* Nom + badge statut */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 3 }}>
            <span style={{ fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 15, color: '#1E2025' }}>
              {entree.animal_nom}
            </span>
            <span style={{
              padding: '2px 10px', borderRadius: 20, fontSize: 10, fontWeight: 700,
              fontFamily: 'Galey, sans-serif', background: bgColor, color: txtColor, whiteSpace: 'nowrap',
            }}>
              {inPension ? 'En pension' : 'Sorti'}
            </span>
            {enRetard && (
              <span style={{
                padding: '2px 10px', borderRadius: 20, fontSize: 10, fontWeight: 700,
                fontFamily: 'Galey, sans-serif', background: '#FDECEA', color: '#C62828', whiteSpace: 'nowrap',
              }}>
                Sortie prévue dépassée
              </span>
            )}
            {animalId && (
              <a href={`/pension/fiche/${animalId}`}
                onClick={e => e.stopPropagation()}
                style={{
                  padding: '2px 10px', borderRadius: 20, fontSize: 10, fontWeight: 700,
                  fontFamily: 'Galey, sans-serif', background: 'rgba(123,94,167,0.1)',
                  color: PURPLE, textDecoration: 'none', whiteSpace: 'nowrap',
                }}>
                🔍 Voir fiche
              </a>
            )}
          </div>

          {/* Espèce + race + puce */}
          <p style={{ margin: '0 0 5px', fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#9ca3af' }}>
            {[espLabel(entree.espece), entree.race].filter(Boolean).join(' · ')}
            {entree.puce ? ` — Puce ${entree.puce}` : ''}
          </p>

          <div style={{ borderTop: '1px solid #f3f4f6', margin: '8px 0' }} />

          {/* Client */}
          {(entree.proprietaire_nom || entree.proprietaire_contact || entree.proprietaire_email) && (
            <div style={{ margin: '0 0 4px' }}>
              {(entree.proprietaire_nom || entree.proprietaire_contact) && (
                <p style={{ margin: '0 0 1px', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#374151' }}>
                  👤 {[entree.proprietaire_nom, entree.proprietaire_contact].filter(Boolean).join(' · ')}
                </p>
              )}
              {entree.proprietaire_email && (
                <p style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#6b7280' }}>
                  ✉ {entree.proprietaire_email}
                </p>
              )}
            </div>
          )}

          {/* Dates */}
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 16px' }}>
            <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#6b7280' }}>
              🔑 Entrée : {fmtDate(entree.date_entree)}
            </span>
            {entree.date_sortie_prevue && (
              <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#6b7280' }}>
                📅 Prévue : {fmtDate(entree.date_sortie_prevue)}
              </span>
            )}
            {entree.date_sortie_effective && (
              <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 12, color: GREEN, fontWeight: 600 }}>
                ✓ Sorti le : {fmtDate(entree.date_sortie_effective)}
              </span>
            )}
          </div>

          {/* Planning : heures prévues, hébergement souhaité, contrat, logement */}
          {inPension && (() => {
            const pl = entree as PensionEntree & Planning;
            const souhait = /Hébergement souhaité : (box|pré)/.exec(pl.notes ?? '')?.[1];
            const [libContrat, coulContrat] = contratStatut ? (LIBELLE_CONTRAT[contratStatut] ?? ['Contrat', '#6b7280']) : ['Contrat à faire', '#B3261E'];
            const proposes = logements.filter(l => logementAccepteEspece(l.especes, entree.espece) || l.id === entree.logement_id);
            return (
              <div style={{ marginTop: 8, display: 'flex', flexWrap: 'wrap', alignItems: 'center', gap: '6px 12px', fontFamily: 'Galey, sans-serif', fontSize: 12 }}
                onClick={e => e.stopPropagation()}>
                {pl.heure_arrivee_prevue && !pl.arrivee_reelle_le && (
                  <span style={{ fontWeight: 700, color: TEAL }}>Arrivée prévue {pl.heure_arrivee_prevue.replace(':', 'h')}{pl.duree_arrivee_min ? ` (${pl.duree_arrivee_min} min)` : ''}</span>
                )}
                {pl.heure_depart_prevue && (
                  <span style={{ fontWeight: 700, color: TEAL }}>Départ prévu {pl.heure_depart_prevue.replace(':', 'h')}{pl.duree_depart_min ? ` (${pl.duree_depart_min} min)` : ''}</span>
                )}
                {souhait && <span style={{ color: '#374151' }}>{souhait === 'pré' ? 'Pré' : 'Box'} souhaité</span>}
                <span style={{ fontWeight: 700, color: coulContrat }}>{libContrat}</span>
                <button type="button" onClick={onFicheBox}
                  style={{ padding: '3px 10px', borderRadius: 8, border: `1px solid ${TEAL}`, color: TEAL, background: 'white', fontSize: 12, fontWeight: 700, cursor: 'pointer' }}>
                  Fiche box
                </button>
                {proposes.length > 0 && (
                  <select value={entree.logement_id ?? ''} onChange={e => onLogement(e.target.value)}
                    style={{ padding: '3px 8px', borderRadius: 8, border: '1px solid #D1D5DB', fontSize: 12, background: 'white' }}>
                    <option value="">Logement à attribuer</option>
                    {proposes.map(l => <option key={l.id} value={l.id}>{l.nom}</option>)}
                  </select>
                )}
              </div>
            );
          })()}

          {/* Logement affecté */}
          {logementNom && !inPension && (
            <div style={{ marginTop: 6 }}>
              <span style={{
                display: 'inline-flex', alignItems: 'center', gap: 4,
                padding: '2px 10px', borderRadius: 20, fontSize: 11, fontWeight: 700,
                fontFamily: 'Galey, sans-serif', background: '#EFF5F6', color: TEAL,
              }}>
                🏠 Logement · {logementNom}
              </span>
            </div>
          )}

          {entree.alimentation_sejour && (
            <div style={{ marginTop: 6 }}>
              <span style={{
                display: 'inline-flex', alignItems: 'center', gap: 4,
                padding: '2px 10px', borderRadius: 20, fontSize: 11, fontWeight: 700,
                fontFamily: 'Galey, sans-serif', background: '#F0F5EC', color: '#4d7a3c',
              }}>
                🌾 Alimentation séjour renseignée
              </span>
            </div>
          )}

          {/* Notes */}
          {entree.notes && (
            <p style={{ margin: '6px 0 0', fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#6b7280',
              overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
              {entree.notes}
            </p>
          )}
        </div>

        <div style={{ flexShrink: 0 }}>
          <button onClick={e => { e.stopPropagation(); setShowActions(true); }} style={{
            padding: '6px 14px', borderRadius: 20, border: `1px solid ${TEAL}`,
            background: 'transparent', color: TEAL, cursor: 'pointer',
            fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 700, whiteSpace: 'nowrap',
          }}>
            ⋯ Actions
          </button>
        </div>
      </div>

      {showActions && (
        <div style={{
          position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)',
          display: 'flex', alignItems: 'flex-end', justifyContent: 'center', zIndex: 1000,
        }} onClick={e => { e.stopPropagation(); if (e.target === e.currentTarget) setShowActions(false); }}>
          <div style={{ background: 'white', borderRadius: '24px 24px 0 0', width: '100%', maxWidth: 480, padding: '12px 8px 24px' }}
            onClick={e => e.stopPropagation()}>
            <div style={{ padding: '4px 16px 8px', display: 'flex', alignItems: 'center' }}>
              <span style={{ flex: 1, fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 15, color: '#1E2025' }}>
                {entree.animal_nom}
              </span>
              <button onClick={() => setShowActions(false)} style={{ background: 'none', border: 'none', fontSize: 22, cursor: 'pointer', color: '#9ca3af' }}>×</button>
            </div>
            {/* Dans l'ordre du séjour : arrivée (+ contrat), suivi, facture, sortie. */}
            {onArrivee && (
              <ActionRow icon="" label="Enregistrer l'arrivée" color={GREEN}
                onClick={() => { setShowActions(false); onArrivee(); }} />
            )}
            <ActionRow icon="📄" label="Contrat à signer" color={PURPLE}
              onClick={() => { setShowActions(false); onContrat(); }} />
            <ActionRow icon="📸" label="Journal" color={GREEN}
              onClick={() => { setShowActions(false); onJournal(); }} />
            {canReclamation && (
              <ActionRow icon="🔗" label={claimSent ? 'Lien de réclamation envoyé' : 'Envoyer le lien de réclamation'}
                color={claimSent ? GREEN : PURPLE} disabled={sendingClaim || claimSent}
                onClick={() => { void envoyerLienReclamation(); }} />
            )}
            <ActionRow icon="🧾" label={isFacture ? 'Facturé — voir / refaire' : 'Facturer'}
              color={isFacture ? GREEN : TEAL}
              onClick={() => { setShowActions(false); onFacturer(); }} />
            {inPension && (
              <ActionRow icon="" label="Enregistrer la sortie" color={TEAL}
                onClick={() => { setShowActions(false); onSorti(); }} />
            )}
          </div>
        </div>
      )}
    </div>
  );
}

function ActionRow({ icon, label, color, onClick, disabled }: {
  icon: string; label: string; color: string; onClick: () => void; disabled?: boolean;
}) {
  return (
    <button onClick={onClick} disabled={disabled} style={{
      display: 'flex', alignItems: 'center', gap: 12, width: '100%', textAlign: 'left',
      background: 'transparent', border: 'none', padding: '13px 16px',
      cursor: disabled ? 'default' : 'pointer', opacity: disabled ? 0.55 : 1,
      fontFamily: 'Galey, sans-serif', fontSize: 14, fontWeight: 600, color: '#1E2025',
    }}>
      <span style={{ fontSize: 18, width: 24, textAlign: 'center' }}>{icon}</span>
      <span style={{ flex: 1, color }}>{label}</span>
    </button>
  );
}

