'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';

// ── Types ─────────────────────────────────────────────────────────────────────

interface PensionAcces {
  id: string;
  pro_uid: string;
  animal_id: string;
  owner_uid: string;
  statut: 'pending' | 'approved' | 'refused';
  pro_nom?: string;
  animal_nom?: string;
  created_at: string;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const TEAL  = '#0C5C6C';
const GREEN = '#6E9E57';

const STATUT_CONFIG = {
  pending:  { label: 'En attente',  color: '#e08000', bg: '#FFF3E0' },
  approved: { label: 'Autorisé',    color: GREEN,     bg: '#E8F5E9' },
  refused:  { label: 'Refusé',      color: '#d32f2f', bg: '#FFEBEE' },
};

function fmtDate(iso: string) {
  try { return new Date(iso).toLocaleDateString('fr-FR'); } catch { return iso; }
}

// ── Page principale ───────────────────────────────────────────────────────────

export default function DemandesAccesPage() {
  const { user, userData } = useAuth();
  const router = useRouter();

  const [demandes, setDemandes] = useState<PensionAcces[]>([]);
  const [loading, setLoading]   = useState(true);
  const [tab, setTab]           = useState<'pending' | 'approved' | 'refused' | 'tous'>('tous');

  const isPension = userData?.isPro && userData?.catPro === 'pension';

  useEffect(() => {
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isPension) { router.push('/'); return; }
  }, [user, userData, isPension, router]);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    const { data } = await supabase
      .from('pension_acces')
      .select('*')
      .eq('pro_uid', user.uid)
      .order('created_at', { ascending: false });
    setDemandes((data ?? []) as PensionAcces[]);
    setLoading(false);
  }, [user]);

  useEffect(() => { load(); }, [load]);

  const filtered = demandes.filter(d =>
    tab === 'tous' ? true : d.statut === tab
  );

  const counts = {
    tous:     demandes.length,
    pending:  demandes.filter(d => d.statut === 'pending').length,
    approved: demandes.filter(d => d.statut === 'approved').length,
    refused:  demandes.filter(d => d.statut === 'refused').length,
  };

  if (!user || !userData) return null;

  return (
    <div style={{ minHeight: '100vh', background: '#F8F8F6', paddingBottom: 60 }}>
      {/* Header */}
      <div style={{ background: TEAL, padding: '20px 24px 0' }}>
        <div style={{ maxWidth: 800, margin: '0 auto' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 16 }}>
            <button onClick={() => router.back()}
              style={{ background: 'none', border: 'none', color: 'white', fontSize: 20, cursor: 'pointer', padding: 0 }}>
              ←
            </button>
            <h1 style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 20, color: 'white' }}>
              Demandes d'accès fiches
            </h1>
          </div>

          {/* Onglets */}
          <div style={{ display: 'flex', gap: 0 }}>
            {([['tous', 'Toutes'], ['pending', 'En attente'], ['approved', 'Autorisées'], ['refused', 'Refusées']] as const).map(([val, label]) => (
              <button key={val} onClick={() => setTab(val)} style={{
                flex: 1, padding: '10px 0', background: 'none', border: 'none',
                borderBottom: tab === val ? '2px solid white' : '2px solid transparent',
                color: tab === val ? 'white' : 'rgba(255,255,255,0.6)',
                fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 12, cursor: 'pointer',
              }}>
                {label}{counts[val] > 0 ? ` (${counts[val]})` : ''}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Contenu */}
      <div style={{ maxWidth: 800, margin: '24px auto', padding: '0 16px' }}>

        {/* Explication */}
        <div style={{
          background: 'rgba(12,92,108,0.06)', border: '1px solid rgba(12,92,108,0.2)',
          borderRadius: 12, padding: '12px 16px', marginBottom: 20,
          fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#374151', lineHeight: 1.5,
        }}>
          🔑 Scannez la puce d'un animal depuis l'application mobile pour envoyer une demande d'accès à son propriétaire.
          Le propriétaire reçoit une notification et peut autoriser ou refuser la consultation de la fiche.
        </div>

        {loading ? (
          <div style={{ textAlign: 'center', padding: 60, color: '#999' }}>Chargement…</div>
        ) : filtered.length === 0 ? (
          <div style={{ textAlign: 'center', padding: 60, color: '#aaa' }}>
            <div style={{ fontSize: 48, marginBottom: 12 }}>🔑</div>
            <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 16 }}>Aucune demande</p>
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {filtered.map(d => <DemandeCard key={d.id} demande={d} />)}
          </div>
        )}
      </div>
    </div>
  );
}

// ── Carte demande ─────────────────────────────────────────────────────────────

function DemandeCard({ demande }: { demande: PensionAcces }) {
  const cfg = STATUT_CONFIG[demande.statut];

  return (
    <div style={{
      background: 'white', borderRadius: 14, padding: 16,
      border: '1px solid #e5e7eb', boxShadow: '0 2px 8px rgba(0,0,0,0.05)',
    }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
        {/* Icône animal */}
        <div style={{
          width: 48, height: 48, borderRadius: 10,
          background: 'rgba(12,92,108,0.08)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 24, flexShrink: 0,
        }}>🐾</div>

        <div style={{ flex: 1 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
            <span style={{ fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 16, color: '#1E2025' }}>
              {demande.animal_nom ?? 'Animal'}
            </span>
            <span style={{
              padding: '2px 10px', borderRadius: 20, fontSize: 11, fontWeight: 700,
              fontFamily: 'Galey, sans-serif',
              background: cfg.bg, color: cfg.color,
            }}>{cfg.label}</span>
          </div>

          <p style={{ margin: '0 0 4px', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6b7280' }}>
            Demande envoyée le {fmtDate(demande.created_at)}
          </p>

          {demande.statut === 'approved' && (
            <p style={{ margin: '6px 0 0', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6E9E57', fontWeight: 600 }}>
              ✓ Le propriétaire a autorisé l'accès à cette fiche.
            </p>
          )}
          {demande.statut === 'refused' && (
            <p style={{ margin: '6px 0 0', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#d32f2f' }}>
              Le propriétaire a refusé la demande.
            </p>
          )}
          {demande.statut === 'pending' && (
            <p style={{ margin: '6px 0 0', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#e08000' }}>
              ⏳ En attente de réponse du propriétaire.
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
