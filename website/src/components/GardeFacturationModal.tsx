'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { gardeJoursAFacturer, gardeTarif, gardePeriodeLabel, type GardeRdvFacture } from '@/lib/garde-facturation';

const TEAL = '#0C5C6C';

function fmt(v: number) { return `${v.toFixed(2).replace('.', ',')} €`; }

// Facturation d'un séjour de garde à domicile — bascule vers le moteur de
// facturation commun (numérotation, PDF archivé, envoi email + notification),
// même logique que l'appli (garde_facture_helper.dart : une seule facture,
// une ligne, quantité = nb de jours du séjour, TVA 20% fixe).
export function GardeFacturationModal({ rdv, proUid, proProfileId, animalNom, clientNom, clientEmail, clientTel, onClose }: {
  rdv: GardeRdvFacture;
  proUid: string;
  proProfileId: string | null;
  animalNom: string;
  clientNom: string;
  clientEmail?: string;
  clientTel?: string;
  onClose: () => void;
}) {
  const router = useRouter();
  const [loading, setLoading] = useState(true);
  const [jours, setJours] = useState<GardeRdvFacture[]>([rdv]);
  const [tarif, setTarif] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    let alive = true;
    (async () => {
      const [j, t] = await Promise.all([
        gardeJoursAFacturer(proUid, proProfileId, rdv),
        gardeTarif(proUid, proProfileId, rdv),
      ]);
      if (!alive) return;
      setJours(j);
      if (t > 0) setTarif(t.toFixed(2));
      setLoading(false);
    })();
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rdv.id, proUid, proProfileId]);

  const tarifNum = parseFloat(tarif.replace(',', '.')) || 0;
  const n = jours.length;
  const totalHT = tarifNum * n;
  const totalTVA = totalHT * 0.2;
  const totalTTC = totalHT + totalTVA;
  const periode = gardePeriodeLabel(jours);

  function continuer() {
    if (tarifNum <= 0) { setError('Renseignez un tarif par jour.'); return; }
    const designation = n > 1 ? `Garde à domicile — ${n} jours (${periode})` : `Garde journée — ${animalNom}`;
    const prefill = {
      nomClient: clientNom,
      emailClient: clientEmail ?? '',
      telClient: clientTel ?? '',
      lignes: [{ description: designation, quantite: n, prixUnitaire: tarifNum, tva: 20 }],
      sourceRdvId: rdv.id,
      sourceRdvIds: jours.map(j => j.id),
      sourceAnimalId: rdv.animal_id ?? undefined,
      clientUid: rdv.client_uid ?? undefined,
      clientProfileId: rdv.client_profile_id ?? undefined,
    };
    try { sessionStorage.setItem('pm_facture_prefill', JSON.stringify(prefill)); } catch { /* ignore */ }
    onClose();
    router.push('/elevage/facturation');
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
            <h2 style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 17 }}>Facturation garde à domicile</h2>
            <p style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#6b7280' }}>{animalNom} — {clientNom}</p>
          </div>
          <button onClick={onClose} style={{ background: 'none', border: 'none', fontSize: 22, cursor: 'pointer', color: '#9ca3af' }}>×</button>
        </div>

        {loading ? (
          <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280', margin: '16px 0' }}>Chargement…</p>
        ) : (
          <>
            <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#374151', margin: '16px 0 12px' }}>
              {n > 1 ? `Cette garde couvre ${n} jours (${periode}).` : `Garde d'un jour (${periode}).`}
            </p>

            <div style={{ marginBottom: 16 }}>
              <label style={lbl}>Tarif par jour (€)</label>
              <input style={inp} type="number" step="0.01" placeholder="25" value={tarif} onChange={e => setTarif(e.target.value)} />
            </div>

            <div style={{ background: TEAL + '0a', border: `1px solid ${TEAL}26`, borderRadius: 12, padding: 14, marginBottom: 20 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280', marginBottom: 4 }}>
                <span>Garde ({n} jour{n > 1 ? 's' : ''} × {fmt(tarifNum)})</span><span>{fmt(totalHT)}</span>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280', marginBottom: 8 }}>
                <span>TVA 20%</span><span>{fmt(totalTVA)}</span>
              </div>
              <div style={{ borderTop: '1px solid #e5e7eb', margin: '8px 0' }} />
              <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'Galey, sans-serif', fontSize: 15, fontWeight: 700, color: TEAL }}>
                <span>TOTAL TTC</span><span>{fmt(totalTTC)}</span>
              </div>
            </div>

            {error && <p style={{ color: '#dc2626', fontFamily: 'Galey, sans-serif', fontSize: 13, marginBottom: 12 }}>{error}</p>}

            <button onClick={continuer} disabled={tarifNum <= 0} style={{
              width: '100%', padding: '13px 0', background: TEAL, color: 'white', border: 'none', borderRadius: 12,
              fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 14,
              cursor: tarifNum <= 0 ? 'not-allowed' : 'pointer',
              opacity: tarifNum <= 0 ? 0.6 : 1, marginBottom: 10,
            }}>
              Continuer vers la facture →
            </button>
          </>
        )}
      </div>
    </div>
  );
}
