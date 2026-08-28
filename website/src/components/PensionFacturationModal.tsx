'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import type { PensionEntree } from '@/components/PensionEntreeModal';
import { pensionTarifKeyForEspece, type TarifsPension } from '@/lib/pension-especes';
import { openPensionInvoice, type PensionFactureData } from '@/lib/pension-facture-html';

const TEAL = '#0C5C6C';

function fmt(v: number) { return `${v.toFixed(2).replace('.', ',')} €`; }

export function PensionFacturationModal({ entree, proUid, proProfileId, pensionNom, onClose, onSaved }: {
  entree: PensionEntree;
  proUid: string;
  proProfileId: string | null;
  pensionNom: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const dateEntree = entree.date_entree ? new Date(entree.date_entree) : null;
  const dateSortie = entree.date_sortie_effective
    ? new Date(entree.date_sortie_effective)
    : (entree.date_sortie_prevue ? new Date(entree.date_sortie_prevue) : new Date());
  const nuitsInitiales = dateEntree
    ? Math.max(1, Math.round((dateSortie.getTime() - dateEntree.getTime()) / 86400000))
    : 1;

  const [tarif, setTarif] = useState('');
  const [nbNuits, setNbNuits] = useState(String(nuitsInitiales));
  const [suppDesc, setSuppDesc] = useState('');
  const [suppMontant, setSuppMontant] = useState('');
  const [avecTVA, setAvecTVA] = useState(false);
  const [isAcompte, setIsAcompte] = useState(false);
  const [acomptePct, setAcomptePct] = useState('30');
  const [sending, setSending] = useState(false);
  const [marking, setMarking] = useState(false);
  const [error, setError] = useState('');

  // Tarification automatisée — pré-remplit le tarif/nuit suggéré à partir de
  // la config du pro (prix par espèce + réduction séjour long), reste
  // librement modifiable ensuite. N'écrase jamais une saisie déjà en cours.
  useEffect(() => {
    (async () => {
      if (!proProfileId) return;
      const { data: profil } = await supabase.from('user_profiles')
        .select('tarifs_pension').eq('id', proProfileId).maybeSingle();
      const config = profil?.tarifs_pension as TarifsPension | null;
      if (!config || typeof config !== 'object') return;
      const seul = entree.seul_dans_logement !== false;

      let prixNuit = 0;
      if (Array.isArray(config.especes) && config.especes.length > 0) {
        // Nouveau modèle : prix fixe par espèce.
        const key = pensionTarifKeyForEspece(entree.espece);
        if (!key) return;
        const match = config.especes.find(e => e.espece === key);
        if (!match) return;
        prixNuit = (seul ? match.prix_seul : (match.prix_partage ?? match.prix_seul)) ?? 0;
      } else if (Array.isArray(config.tranches_poids) && config.tranches_poids.length > 0) {
        // Rétro-compat : ancien modèle tranches de poids.
        const tranches = config.tranches_poids;
        let poids: number | undefined;
        if (entree.animal_id) {
          const { data: animal } = await supabase.from('animaux').select('poids').eq('id', entree.animal_id).maybeSingle();
          poids = animal?.poids ?? undefined;
        }
        let tranche = tranches.find(t => poids == null || t.poids_max == null || poids <= t.poids_max);
        if (!tranche) tranche = tranches[tranches.length - 1];
        prixNuit = (seul ? tranche.prix_seul : tranche.prix_partage) ?? 0;
      } else {
        return;
      }

      let reductionPct = 0;
      for (const r of (config.reductions_long_sejour ?? [])) {
        if (nuitsInitiales >= (r.min_nuits ?? 0)) reductionPct = r.pourcentage ?? 0;
      }
      const prixFinal = prixNuit * (1 - reductionPct / 100);
      setTarif(prev => prev === '' && prixFinal > 0 ? prixFinal.toFixed(2) : prev);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [proProfileId, entree.id]);

  const tarifNum = parseFloat(tarif.replace(',', '.')) || 0;
  const nuitsNum = parseInt(nbNuits, 10) || 1;
  const suppNum = parseFloat(suppMontant.replace(',', '.')) || 0;
  const sousTotal = tarifNum * nuitsNum + suppNum;
  const tvaAmt = avecTVA ? sousTotal * 0.2 : 0;
  const total = sousTotal + tvaAmt;
  const pctNum = Math.min(100, Math.max(1, Math.round(parseFloat(acomptePct.replace(',', '.')) || 30)));
  // Montant réellement facturé : total du séjour, ou une fraction si c'est un acompte.
  const montantFacture = isAcompte ? Math.round(total * pctNum) / 100 : total;

  function genNumero() {
    return `${isAcompte ? 'ACPT' : 'FACT'}-${new Date().toISOString().slice(0, 10).replace(/-/g, '')}-${Date.now().toString().slice(-4)}`;
  }
  function factureData(numero: string): PensionFactureData {
    return {
      numero,
      pensionNom,
      emiseLe: new Date().toISOString(),
      animal: { nom: entree.animal_nom, espece: entree.espece, race: entree.race, puce: entree.puce },
      proprietaire: { nom: entree.proprietaire_nom, email: entree.proprietaire_email, contact: entree.proprietaire_contact },
      sejour: { dateEntree: entree.date_entree, dateSortie: entree.date_sortie_effective ?? entree.date_sortie_prevue },
      nuits: nuitsNum,
      tarifNuit: tarifNum,
      suppDesc,
      suppMontant: suppNum,
      avecTVA,
      isAcompte,
      acomptePct: pctNum,
    };
  }
  function facturePayload(numero: string, token: string) {
    return {
      pro_uid: proUid,
      ...(proProfileId ? { pro_profile_id: proProfileId } : {}),
      entree_id: entree.id,
      numero,
      token,
      animal_nom: entree.animal_nom,
      proprietaire_nom: entree.proprietaire_nom,
      montant: montantFacture,
      statut: 'envoyee',
      details: factureData(numero),
      ...(isAcompte ? { type: 'acompte', acompte_pct: pctNum } : {}),
    };
  }

  // Insert résilient : si `details` / `token` n'existent pas encore (migration
  // pas passée), on réessaie sans les colonnes manquantes.
  async function insertFacture(payload: Record<string, unknown>) {
    let p = payload;
    for (let i = 0; i < 3; i++) {
      const res = await supabase.from('pension_factures').insert(p);
      if (!res.error) return res;
      const m = /'?(\w+)'? column|column "?(\w+)"?|(\bdetails\b|\btoken\b)/i.exec(res.error.message);
      const col = m?.[1] || m?.[2] || m?.[3];
      if (col && col in p) {
        const { [col]: _omit, ...rest } = p;
        void _omit;
        p = rest;
        continue;
      }
      return res;
    }
    return supabase.from('pension_factures').insert(p);
  }

  function apercu() {
    if (!openPensionInvoice(factureData(genNumero()))) {
      setError('Autorisez les popups pour ouvrir la facture');
    }
  }

  async function marquerFacture() {
    if (tarifNum <= 0) { setError('Renseignez un tarif par nuit.'); return; }
    setMarking(true);
    setError('');
    try {
      const { error: err } = await insertFacture(facturePayload(genNumero(), crypto.randomUUID()));
      if (err) { setError(err.message); setMarking(false); return; }
      onSaved();
    } finally {
      setMarking(false);
    }
  }

  async function envoyerAuProprietaire() {
    const ownerEmail = (entree.proprietaire_email ?? '').trim();
    if (!ownerEmail) { setError('Email du propriétaire non renseigné.'); return; }
    setSending(true);
    setError('');
    try {
      const { data: ownerRow } = await supabase.from('users').select('uid').eq('email', ownerEmail).maybeSingle();
      const ownerUid = ownerRow?.uid as string | undefined;

      let ownerProfileId: string | null = null;
      if (ownerUid && entree.animal_id) {
        const { data: propRow } = await supabase.from('animaux_proprietes')
          .select('profile_id_proprio').eq('animal_id', entree.animal_id).is('date_fin', null)
          .order('date_debut', { ascending: false }).limit(1).maybeSingle();
        ownerProfileId = propRow?.profile_id_proprio ?? null;
      }

      const numero = genNumero();
      const token = crypto.randomUUID();

      // Notification in-app uniquement si le propriétaire a un compte PetsMatch.
      if (ownerUid) {
        await supabase.from('notifications').insert({
          uid: ownerUid,
          type: 'facture_pension',
          title: isAcompte ? "Votre acompte de pension est disponible" : 'Votre facture de pension est disponible',
          body: isAcompte
            ? `${pensionNom} vous demande un acompte de ${pctNum}% pour le séjour de ${entree.animal_nom}.`
            : `${pensionNom} vous a envoyé la facture pour le séjour de ${entree.animal_nom}.`,
          ...(ownerProfileId ? { profile_id: ownerProfileId } : {}),
          data: { invoice: numero, animal_nom: entree.animal_nom, pension_nom: pensionNom, url: `/facture-pension/${token}` },
          read: false,
        });
      }

      const { error: err } = await insertFacture({
        ...facturePayload(numero, token),
        ...(ownerUid ? { proprietaire_uid: ownerUid } : {}),
      });
      if (err) { setError(err.message); setSending(false); return; }

      // Email avec le lien de consultation (en plus de la notification in-app).
      try {
        await fetch('/api/facture/notify-email', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            email: ownerEmail,
            client_nom: entree.proprietaire_nom || 'Client',
            pro_nom: pensionNom,
            numero_facture: numero,
            total_ttc: montantFacture,
            facture_url: `${window.location.origin}/facture-pension/${token}`,
          }),
        });
      } catch { /* l'email est un bonus, on n'échoue pas la facturation dessus */ }

      onSaved();
    } finally {
      setSending(false);
    }
  }

  const inp: React.CSSProperties = {
    width: '100%', padding: '10px 12px', borderRadius: 8, border: '1px solid #d1d5db',
    fontFamily: 'Galey, sans-serif', fontSize: 14, boxSizing: 'border-box', background: 'white', outline: 'none',
  };
  const lbl: React.CSSProperties = { fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 600, color: '#6b7280', marginBottom: 4, display: 'block' };

  return (
    <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)', display: 'flex', alignItems: 'flex-end', justifyContent: 'center', zIndex: 1000 }}
      onClick={e => e.target === e.currentTarget && onClose()}>
      <div style={{ background: 'white', borderRadius: '24px 24px 0 0', width: '100%', maxWidth: 560, maxHeight: '90vh', overflowY: 'auto', padding: '20px 24px 32px' }}>
        <div style={{ display: 'flex', alignItems: 'center', marginBottom: 4 }}>
          <div style={{ flex: 1 }}>
            <h2 style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 17 }}>Facturation pension</h2>
            <p style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#6b7280' }}>{entree.animal_nom} — {entree.proprietaire_nom ?? '—'}</p>
          </div>
          <button onClick={onClose} style={{ background: 'none', border: 'none', fontSize: 22, cursor: 'pointer', color: '#9ca3af' }}>×</button>
        </div>

        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginTop: 16, marginBottom: 12 }}>
          <div>
            <label style={lbl}>Tarif par nuit (€)</label>
            <input style={inp} type="number" step="0.01" placeholder="25" value={tarif} onChange={e => setTarif(e.target.value)} />
          </div>
          <div>
            <label style={lbl}>Nombre de nuits</label>
            <input style={inp} type="number" value={nbNuits} onChange={e => setNbNuits(e.target.value)} />
          </div>
        </div>
        <div style={{ marginBottom: 8 }}>
          <label style={lbl}>Suppléments (optionnel)</label>
          <input style={inp} placeholder="Ex : Frais vétérinaires, médicaments…" value={suppDesc} onChange={e => setSuppDesc(e.target.value)} />
        </div>
        <div style={{ marginBottom: 16 }}>
          <label style={lbl}>Montant suppléments (€)</label>
          <input style={inp} type="number" step="0.01" placeholder="0" value={suppMontant} onChange={e => setSuppMontant(e.target.value)} />
        </div>

        <label style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 12px', borderRadius: 10, border: `1px solid ${avecTVA ? TEAL + '4d' : '#e5e7eb'}`, background: avecTVA ? TEAL + '0d' : '#f9fafb', marginBottom: 10, cursor: 'pointer' }}>
          <input type="checkbox" checked={avecTVA} onChange={e => setAvecTVA(e.target.checked)} />
          <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#374151', flex: 1 }}>Assujetti à la TVA (20%)</span>
        </label>

        <div style={{ padding: '10px 12px', borderRadius: 10, border: `1px solid ${isAcompte ? TEAL + '4d' : '#e5e7eb'}`, background: isAcompte ? TEAL + '0d' : '#f9fafb', marginBottom: 16 }}>
          <label style={{ display: 'flex', alignItems: 'center', gap: 10, cursor: 'pointer' }}>
            <input type="checkbox" checked={isAcompte} onChange={e => setIsAcompte(e.target.checked)} />
            <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#374151', flex: 1 }}>Facture d&apos;acompte (réservation)</span>
          </label>
          {isAcompte && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 10 }}>
              <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280' }}>Pourcentage</span>
              <input style={{ ...inp, width: 90 }} type="number" min={1} max={100} value={acomptePct} onChange={e => setAcomptePct(e.target.value)} />
              <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280' }}>
                % · solde {fmt(total - montantFacture)} à la sortie
              </span>
            </div>
          )}
        </div>

        <div style={{ background: TEAL + '0a', border: `1px solid ${TEAL}26`, borderRadius: 12, padding: 14, marginBottom: 20 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280', marginBottom: 4 }}>
            <span>Pension ({nuitsNum} nuit{nuitsNum > 1 ? 's' : ''} × {fmt(tarifNum)})</span><span>{fmt(tarifNum * nuitsNum)}</span>
          </div>
          {suppNum > 0 && (
            <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280', marginBottom: 4 }}>
              <span>Suppléments</span><span>{fmt(suppNum)}</span>
            </div>
          )}
          <div style={{ borderTop: '1px solid #e5e7eb', margin: '10px 0' }} />
          {avecTVA && (
            <>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280', marginBottom: 4 }}>
                <span>Sous-total HT</span><span>{fmt(sousTotal)}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280', marginBottom: 8 }}>
                <span>TVA 20%</span><span>{fmt(tvaAmt)}</span>
              </div>
              <div style={{ borderTop: '1px solid #e5e7eb', margin: '8px 0' }} />
            </>
          )}
          <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: isAcompte ? 13 : 15, fontWeight: isAcompte ? 400 : 700, color: isAcompte ? '#6b7280' : TEAL }}>
            <span>{avecTVA ? 'TOTAL TTC séjour' : 'TOTAL séjour'}</span><span>{fmt(total)}</span>
          </div>
          {isAcompte && (
            <>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280', margin: '4px 0' }}>
                <span>Solde restant à la sortie</span><span>{fmt(total - montantFacture)}</span>
              </div>
              <div style={{ borderTop: '1px solid #e5e7eb', margin: '8px 0' }} />
              <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: 15, fontWeight: 700, color: TEAL }}>
                <span>Acompte {pctNum}% à facturer</span><span>{fmt(montantFacture)}</span>
              </div>
            </>
          )}
        </div>

        {error && <p style={{ color: '#dc2626', fontFamily: 'Galey, sans-serif', fontSize: 13, marginBottom: 12 }}>{error}</p>}

        <button onClick={apercu} disabled={tarifNum <= 0} style={{
          width: '100%', padding: '13px 0', background: TEAL, color: 'white', border: 'none', borderRadius: 12,
          fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 14, cursor: tarifNum <= 0 ? 'not-allowed' : 'pointer',
          opacity: tarifNum <= 0 ? 0.6 : 1, marginBottom: 10,
        }}>
          🖨️ Aperçu / Imprimer
        </button>
        <button onClick={envoyerAuProprietaire} disabled={tarifNum <= 0 || sending || marking} style={{
          width: '100%', padding: '13px 0', background: 'transparent', color: TEAL, border: `1px solid ${TEAL}`, borderRadius: 12,
          fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 14, cursor: tarifNum <= 0 ? 'not-allowed' : 'pointer',
          opacity: tarifNum <= 0 ? 0.6 : 1, marginBottom: 10,
        }}>
          {sending ? 'Envoi en cours…' : '✉️ Envoyer au propriétaire (email + notif)'}
        </button>
        <button onClick={marquerFacture} disabled={tarifNum <= 0 || sending || marking} style={{
          width: '100%', padding: '11px 0', background: 'transparent', color: '#6b7280', border: 'none',
          fontFamily: 'Galey, sans-serif', fontWeight: 600, fontSize: 13, cursor: tarifNum <= 0 ? 'not-allowed' : 'pointer',
        }}>
          {marking ? '…' : isAcompte ? '✔ Marquer acompte facturé (sans envoi)' : '✔ Marquer facturé (sans envoi)'}
        </button>
      </div>
    </div>
  );
}
