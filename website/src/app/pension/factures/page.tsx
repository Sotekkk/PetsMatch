'use client';

import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { usePensionAccess } from '@/hooks/usePensionAccess';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { supabase } from '@/lib/supabase';
import { openPensionInvoice, type PensionFactureData } from '@/lib/pension-facture-html';

const TEAL = '#0C5C6C';
const GREEN = '#6E9E57';

interface PensionFacture {
  id: string;
  numero: string;
  entree_id: string | null;
  proprietaire_uid: string | null;
  token: string | null;
  animal_nom: string | null;
  proprietaire_nom: string | null;
  montant: number | null;
  statut: string;
  type?: string | null;
  pdf_url?: string | null;
  details?: PensionFactureData | null;
  date_envoi: string | null;
  date_paiement: string | null;
}

function fmtDate(iso?: string | null) {
  if (!iso) return '—';
  try { return new Date(iso).toLocaleDateString('fr-FR'); } catch { return iso; }
}
function fmtMontant(v?: number | null) {
  return `${(v ?? 0).toFixed(2).replace('.', ',')} €`;
}

export default function PensionFacturesPage() {
  const { user, userData, isPension, loading: authLoading } = usePensionAccess();
  const activeProfileId = useActiveProfile();
  const router = useRouter();

  const [factures, setFactures] = useState<PensionFacture[]>([]);
  const [loading, setLoading] = useState(true);
  const [filtre, setFiltre] = useState<'tous' | 'envoyee' | 'payee'>('tous');
  const [payingId, setPayingId] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);

  const pensionNom = userData?.nameElevage || `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim() || 'Votre pension';

  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isPension) { router.push('/'); return; }
  }, [user, userData, isPension, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    let proProfileId = activeProfileId || null;
    if (!proProfileId) {
      const { data: mainProfile } = await supabase.from('user_profiles')
        .select('id').eq('uid', user.uid).eq('is_main', true).maybeSingle();
      proProfileId = mainProfile?.id ?? null;
    }
    let q = supabase.from('pension_factures')
      .select('*')
      .eq('pro_uid', user.uid).order('date_envoi', { ascending: false });
    if (proProfileId) q = q.eq('pro_profile_id', proProfileId) as typeof q;
    const { data } = await q;
    setFactures((data ?? []) as PensionFacture[]);
    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  function openInvoice(f: PensionFacture) {
    const d: PensionFactureData = f.details
      ? { ...f.details, numero: f.numero, pensionNom: f.details.pensionNom || pensionNom }
      : {
          numero: f.numero, pensionNom, emiseLe: f.date_envoi,
          animal: { nom: f.animal_nom }, proprietaire: { nom: f.proprietaire_nom },
          sejour: {}, nuits: 1, tarifNuit: f.montant ?? 0, avecTVA: false,
          isAcompte: f.type === 'acompte', acomptePct: 100,
        };
    if (!openPensionInvoice(d)) alert('Autorisez les popups pour ouvrir la facture.');
  }

  async function marquerPayee(id: string) {
    setPayingId(id);
    await supabase.from('pension_factures').update({
      statut: 'payee', date_paiement: new Date().toISOString(),
    }).eq('id', id);
    setFactures(prev => prev.map(f => f.id === id ? { ...f, statut: 'payee' } : f));
    setPayingId(null);
  }

  async function supprimer(f: PensionFacture) {
    if (!confirm(`Supprimer définitivement la facture ${f.numero} ?`)) return;
    setBusyId(f.id);
    const { error } = await supabase.from('pension_factures').delete().eq('id', f.id);
    if (error) { alert(`Suppression impossible : ${error.message}`); setBusyId(null); return; }
    setFactures(prev => prev.filter(x => x.id !== f.id));
    setBusyId(null);
  }

  async function renvoyer(f: PensionFacture) {
    setBusyId(f.id);
    try {
      let email: string | null = null;
      if (f.entree_id) {
        const { data: ent } = await supabase.from('pension_entrees')
          .select('proprietaire_email').eq('id', f.entree_id).maybeSingle();
        email = (ent?.proprietaire_email as string | null)?.trim() || null;
      }
      const url = f.token ? `/facture-pension/${f.token}` : null;
      const acompte = f.type === 'acompte';

      if (f.proprietaire_uid && url) {
        await supabase.from('notifications').insert({
          uid: f.proprietaire_uid,
          type: 'facture_pension',
          title: acompte ? 'Votre acompte de pension est disponible' : 'Votre facture de pension est disponible',
          body: `${pensionNom} vous renvoie ${acompte ? "l'acompte" : 'la facture'} pour le séjour de ${f.animal_nom ?? 'votre animal'}.`,
          data: { invoice: f.numero, animal_nom: f.animal_nom, pension_nom: pensionNom, ...(url ? { url } : {}) },
          read: false,
        });
      }

      if (email && url) {
        await fetch('/api/facture/notify-email', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            email,
            client_nom: f.proprietaire_nom || 'Client',
            pro_nom: pensionNom,
            numero_facture: f.numero,
            total_ttc: f.montant ?? 0,
            facture_url: `${window.location.origin}${url}`,
            ...(f.pdf_url ? { pdf_url: f.pdf_url } : {}),
          }),
        });
        alert(`Facture renvoyée à ${email}${f.proprietaire_uid ? ' + notification' : ''}.`);
      } else if (f.proprietaire_uid) {
        alert('Notification renvoyée (aucun email propriétaire enregistré).');
      } else {
        alert('Impossible de renvoyer : ni email ni compte propriétaire.');
      }
    } finally {
      setBusyId(null);
    }
  }

  function exportCsv() {
    const headers = ['Numéro', 'Type', 'Animal', 'Client', 'Montant', 'Statut', 'Envoyée le', 'Payée le'];
    const csv = [
      headers.join(';'),
      ...filtered.map(f => [
        f.numero,
        f.type === 'acompte' ? 'Acompte' : 'Complète',
        f.animal_nom ?? '',
        f.proprietaire_nom ?? '',
        (f.montant ?? 0).toFixed(2).replace('.', ','),
        f.statut === 'payee' ? 'Payée' : 'En attente',
        fmtDate(f.date_envoi),
        fmtDate(f.date_paiement),
      ].join(';')),
    ].join('\n');
    const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = `factures-pension-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click(); URL.revokeObjectURL(url);
  }

  const filtered = filtre === 'tous' ? factures : factures.filter(f => f.statut === filtre);
  const totalDu = factures.filter(f => f.statut === 'envoyee')
    .reduce((s, f) => s + (f.montant ?? 0), 0);

  const counts = {
    tous: factures.length,
    envoyee: factures.filter(f => f.statut === 'envoyee').length,
    payee: factures.filter(f => f.statut === 'payee').length,
  };

  if (!user || !userData) return null;

  return (
    <div style={{ minHeight: '100vh', background: '#F8F8F6', paddingBottom: 60 }}>
      <div style={{ background: TEAL, padding: '20px 24px' }}>
        <div style={{ maxWidth: 900, margin: '0 auto', display: 'flex', alignItems: 'center', gap: 12 }}>
          <button onClick={() => router.push('/pension/registre')}
            style={{ background: 'none', border: 'none', color: 'white', fontSize: 20, cursor: 'pointer', padding: 0 }}>←</button>
          <h1 style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 20, color: 'white', flex: 1 }}>
            Mes factures
          </h1>
          <button onClick={exportCsv} disabled={factures.length === 0}
            style={{ background: 'rgba(255,255,255,0.15)', border: '1px solid rgba(255,255,255,0.3)',
              color: 'white', borderRadius: 20, padding: '6px 14px', cursor: 'pointer',
              fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 700,
              opacity: factures.length === 0 ? 0.4 : 1 }}>
            ↓ CSV
          </button>
        </div>
      </div>

      <div style={{ maxWidth: 900, margin: '20px auto', padding: '0 16px' }}>
        {totalDu > 0 && (
          <div style={{ background: '#FEF2F2', border: '1px solid #FECACA', borderRadius: 12, padding: '10px 14px', marginBottom: 16,
            fontFamily: 'Galey, sans-serif', fontSize: 13, fontWeight: 600, color: '#991B1B' }}>
            💳 {fmtMontant(totalDu)} en attente de paiement
          </div>
        )}

        <div style={{ display: 'flex', gap: 8, marginBottom: 16 }}>
          {([['tous', 'Toutes'], ['envoyee', 'En attente'], ['payee', 'Payées']] as const).map(([val, label]) => (
            <button key={val} onClick={() => setFiltre(val)} style={{
              padding: '6px 14px', borderRadius: 20, cursor: 'pointer',
              border: `1px solid ${filtre === val ? TEAL : '#d1d5db'}`,
              background: filtre === val ? TEAL : 'white', color: filtre === val ? 'white' : '#374151',
              fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 700,
            }}>
              {label}{counts[val] > 0 ? ` (${counts[val]})` : ''}
            </button>
          ))}
        </div>

        {loading ? (
          <div style={{ textAlign: 'center', padding: 60, color: '#999' }}>Chargement…</div>
        ) : filtered.length === 0 ? (
          <div style={{ textAlign: 'center', padding: 60, color: '#aaa' }}>
            <div style={{ fontSize: 48, marginBottom: 12 }}>🧾</div>
            <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 16 }}>Aucune facture</p>
            <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#ccc' }}>
              Facturez un séjour depuis « Nos pensionnaires » → bouton Actions.
            </p>
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            {filtered.map(f => {
              const paye = f.statut === 'payee';
              return (
                <div key={f.id} onClick={() => openInvoice(f)} style={{
                  background: 'white', borderRadius: 14, padding: 14,
                  border: '1px solid #e5e7eb', boxShadow: '0 2px 8px rgba(0,0,0,0.04)',
                  display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer',
                }}>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 2 }}>
                      <span style={{ fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 14, color: '#1E2025' }}>
                        {f.animal_nom ?? '—'} — {f.proprietaire_nom ?? '—'}
                      </span>
                      {f.type === 'acompte' && (
                        <span style={{ fontSize: 10, fontWeight: 700, fontFamily: 'Galey, sans-serif',
                          background: 'rgba(12,92,108,0.1)', color: TEAL, padding: '1px 8px', borderRadius: 20 }}>
                          Acompte
                        </span>
                      )}
                      <span style={{ fontSize: 10, fontWeight: 700, fontFamily: 'Galey, sans-serif',
                        background: paye ? 'rgba(110,158,87,0.12)' : '#FDECEA',
                        color: paye ? GREEN : '#C62828', padding: '1px 8px', borderRadius: 20 }}>
                        {paye ? 'Payée' : 'En attente'}
                      </span>
                    </div>
                    <p style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontSize: 11, color: '#9ca3af' }}>
                      {f.numero} · {fmtMontant(f.montant)} · envoyée le {fmtDate(f.date_envoi)}
                      {paye && f.date_paiement ? ` · payée le ${fmtDate(f.date_paiement)}` : ''}
                    </p>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0, flexWrap: 'wrap', justifyContent: 'flex-end' }}
                    onClick={e => e.stopPropagation()}>
                    {f.pdf_url && (
                      <a href={f.pdf_url} target="_blank" rel="noopener noreferrer"
                        style={{ fontFamily: 'Galey, sans-serif', fontSize: 11, fontWeight: 700, color: TEAL, whiteSpace: 'nowrap' }}>
                        PDF ↗
                      </a>
                    )}
                    <button onClick={() => renvoyer(f)} disabled={busyId === f.id} title="Renvoyer au propriétaire" style={{
                      padding: '6px 12px', borderRadius: 20, border: `1px solid ${TEAL}`,
                      background: 'transparent', color: TEAL, cursor: 'pointer', whiteSpace: 'nowrap',
                      fontFamily: 'Galey, sans-serif', fontSize: 11, fontWeight: 700,
                    }}>
                      {busyId === f.id ? '…' : '↻ Renvoyer'}
                    </button>
                    {!paye && (
                      <button onClick={() => marquerPayee(f.id)} disabled={payingId === f.id} style={{
                        padding: '6px 12px', borderRadius: 20, border: `1px solid ${GREEN}`,
                        background: 'transparent', color: GREEN, cursor: 'pointer', whiteSpace: 'nowrap',
                        fontFamily: 'Galey, sans-serif', fontSize: 11, fontWeight: 700,
                      }}>
                        {payingId === f.id ? '…' : '✓ Payée'}
                      </button>
                    )}
                    <button onClick={() => supprimer(f)} disabled={busyId === f.id} title="Supprimer la facture" style={{
                      padding: '6px 10px', borderRadius: 20, border: '1px solid #FECACA',
                      background: 'transparent', color: '#C62828', cursor: 'pointer',
                      fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 700,
                    }}>
                      🗑
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
