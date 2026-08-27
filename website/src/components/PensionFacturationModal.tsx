'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import type { PensionEntree } from '@/components/PensionEntreeModal';

const TEAL = '#0C5C6C';

const ESP_LABEL: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', lapin: 'Lapin', oiseau: 'Oiseau',
  cheval: 'Cheval', nac: 'NAC', ovin: 'Ovin', caprin: 'Caprin', porcin: 'Porc',
};
function espLabel(e?: string | null) { return ESP_LABEL[e ?? ''] ?? (e ?? ''); }

function fmtDateIso(iso?: string | null) {
  if (!iso) return '—';
  try { return new Date(iso).toLocaleDateString('fr-FR'); } catch { return iso; }
}

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
  // la config du pro (tranches de poids + réduction séjour long), reste
  // librement modifiable ensuite. N'écrase jamais une saisie déjà en cours.
  useEffect(() => {
    (async () => {
      if (!proProfileId) return;
      const { data: profil } = await supabase.from('user_profiles')
        .select('tarifs_pension').eq('id', proProfileId).maybeSingle();
      const config = profil?.tarifs_pension;
      if (!config || typeof config !== 'object') return;
      const tranches: Array<{ poids_max?: number; prix_seul?: number; prix_partage?: number }> = config.tranches_poids ?? [];
      if (tranches.length === 0) return;

      let poids: number | undefined;
      if (entree.animal_id) {
        const { data: animal } = await supabase.from('animaux').select('poids').eq('id', entree.animal_id).maybeSingle();
        poids = animal?.poids ?? undefined;
      }
      const seul = entree.seul_dans_logement !== false;

      let tranche = tranches.find(t => poids == null || t.poids_max == null || poids <= t.poids_max);
      if (!tranche) tranche = tranches[tranches.length - 1];
      const prixNuit = (seul ? tranche.prix_seul : tranche.prix_partage) ?? 0;

      let reductionPct = 0;
      const reductions: Array<{ min_nuits?: number; pourcentage?: number }> = config.reductions_long_sejour ?? [];
      for (const r of reductions) {
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
  function facturePayload() {
    return {
      pro_uid: proUid,
      ...(proProfileId ? { pro_profile_id: proProfileId } : {}),
      entree_id: entree.id,
      animal_nom: entree.animal_nom,
      proprietaire_nom: entree.proprietaire_nom,
      montant: montantFacture,
      statut: 'envoyee',
      ...(isAcompte ? { type: 'acompte', acompte_pct: pctNum } : {}),
    };
  }

  function invoiceHtml(numero: string) {
    return `<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"><title>Facture ${numero}</title>
<style>body{font-family:Arial,sans-serif;font-size:12px;margin:24px;color:#222}h1{font-size:18px;margin-bottom:2px}.meta{color:#666;font-size:11px;margin-bottom:20px}
.grid{display:flex;gap:24px;margin-bottom:16px}.box{flex:1;background:#f8f8f6;border-radius:6px;padding:10px 12px}.box b{display:block;font-size:9px;letter-spacing:.5px;color:#888;margin-bottom:4px}
table{width:100%;border-collapse:collapse;margin-bottom:12px}th{background:#f0f0f0;font-weight:bold;text-align:left;padding:6px 8px;border:1px solid #ccc}td{padding:6px 8px;border:1px solid #ddd}
.totals{margin-left:auto;width:260px}.totals div{display:flex;justify-content:space-between;padding:3px 0}.totals .grand{font-weight:bold;font-size:14px;border-top:1px solid #ccc;padding-top:6px;color:${TEAL}}
.foot{margin-top:28px;font-size:10px;color:#999}@media print{body{margin:10px}}</style>
</head><body>
<h1>🧾 ${isAcompte ? `Facture d'acompte ${numero}` : `Facture ${numero}`}</h1>
<p class="meta">${pensionNom} — émise le ${new Date().toLocaleDateString('fr-FR')}${isAcompte ? ` · acompte de ${pctNum}% du séjour` : ''}</p>
<div class="grid">
  <div class="box"><b>ANIMAL</b>${entree.animal_nom} · ${espLabel(entree.espece)}${entree.race ? `<br>${entree.race}` : ''}${entree.puce ? `<br>Puce : ${entree.puce}` : ''}</div>
  <div class="box"><b>PROPRIÉTAIRE</b>${entree.proprietaire_nom ?? '—'}${entree.proprietaire_email ? `<br>${entree.proprietaire_email}` : ''}${entree.proprietaire_contact ? `<br>${entree.proprietaire_contact}` : ''}</div>
  <div class="box"><b>SÉJOUR</b>Entrée : ${fmtDateIso(entree.date_entree)}<br>Sortie : ${fmtDateIso(entree.date_sortie_effective ?? entree.date_sortie_prevue)}<br><b style="color:${TEAL}">${nuitsNum} nuit${nuitsNum > 1 ? 's' : ''}</b></div>
</div>
<table><thead><tr><th>Description</th><th>Qté</th><th>P.U. HT</th><th>Total HT</th></tr></thead><tbody>
<tr><td>Pension du ${fmtDateIso(entree.date_entree)} au ${fmtDateIso(entree.date_sortie_effective ?? entree.date_sortie_prevue)}</td><td>${nuitsNum}</td><td>${fmt(tarifNum)}</td><td>${fmt(tarifNum * nuitsNum)}</td></tr>
${suppNum > 0 ? `<tr><td>${suppDesc || 'Suppléments'}</td><td>1</td><td>${fmt(suppNum)}</td><td>${fmt(suppNum)}</td></tr>` : ''}
</tbody></table>
<div class="totals">
${avecTVA ? `<div><span>Sous-total HT</span><span>${fmt(sousTotal)}</span></div><div><span>TVA 20%</span><span>${fmt(tvaAmt)}</span></div>` : ''}
<div${isAcompte ? '' : ' class="grand"'}><span>${avecTVA ? 'TOTAL TTC séjour' : 'TOTAL séjour'}</span><span>${fmt(total)}</span></div>
${isAcompte ? `<div><span>Acompte ${pctNum}%</span><span>${fmt(montantFacture)}</span></div>
<div class="grand"><span>À RÉGLER MAINTENANT</span><span>${fmt(montantFacture)}</span></div>
<div><span>Solde à la sortie</span><span>${fmt(total - montantFacture)}</span></div>` : ''}
</div>
<p class="foot">${isAcompte ? `Acompte à régler pour confirmer la réservation. Le solde de ${fmt(total - montantFacture)} sera facturé à la fin du séjour. ` : 'Paiement à réception de facture. '}Document généré via PetsMatch.</p>
</body></html>`;
  }

  function apercu() {
    const numero = genNumero();
    const win = window.open('', '_blank');
    if (!win) { setError('Autorisez les popups pour imprimer'); return; }
    win.document.write(invoiceHtml(numero));
    win.document.close();
    setTimeout(() => win.print(), 300);
  }

  async function marquerFacture() {
    if (tarifNum <= 0) { setError('Renseignez un tarif par nuit.'); return; }
    setMarking(true);
    setError('');
    try {
      const numero = genNumero();
      const { error: err } = await supabase.from('pension_factures').insert({ ...facturePayload(), numero });
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
      if (!ownerUid) { setError(`Propriétaire introuvable dans PetsMatch (email : ${ownerEmail})`); setSending(false); return; }

      let ownerProfileId: string | null = null;
      if (entree.animal_id) {
        const { data: propRow } = await supabase.from('animaux_proprietes')
          .select('profile_id_proprio').eq('animal_id', entree.animal_id).is('date_fin', null)
          .order('date_debut', { ascending: false }).limit(1).maybeSingle();
        ownerProfileId = propRow?.profile_id_proprio ?? null;
      }

      const numero = genNumero();

      await supabase.from('notifications').insert({
        uid: ownerUid,
        type: 'facture_pension',
        title: isAcompte ? "Votre acompte de pension est disponible" : 'Votre facture de pension est disponible',
        body: isAcompte
          ? `${pensionNom} vous demande un acompte de ${pctNum}% pour le séjour de ${entree.animal_nom}.`
          : `${pensionNom} vous a envoyé la facture pour le séjour de ${entree.animal_nom}.`,
        ...(ownerProfileId ? { profile_id: ownerProfileId } : {}),
        data: { invoice: numero, animal_nom: entree.animal_nom, pension_nom: pensionNom },
        read: false,
      });

      const { error: err } = await supabase.from('pension_factures').insert({ ...facturePayload(), numero, proprietaire_uid: ownerUid });
      if (err) { setError(err.message); setSending(false); return; }
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
          {sending ? 'Envoi en cours…' : '✉️ Envoyer au propriétaire'}
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
