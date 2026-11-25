'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { usePensionAccess } from '@/hooks/usePensionAccess';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { animauxPartis } from '@/lib/pensionnaires-partis';

// ── Types ─────────────────────────────────────────────────────────────────────

interface PensionAcces {
  id: string;
  animal_id: string;
  statut: 'pending' | 'active' | 'revoked';
  animal_nom?: string;
  photo_url?: string | null;
  puce?: string | null;
  created_at: string;
  granted_at?: string | null;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const TEAL  = '#0C5C6C';
const GREEN = '#6E9E57';

const STATUT_CONFIG = {
  pending: { label: 'En attente', color: '#e08000', bg: '#FFF3E0' },
  active:  { label: 'Autorisé',   color: GREEN,     bg: '#E8F5E9' },
  revoked: { label: 'Refusé',     color: '#d32f2f', bg: '#FFEBEE' },
};

function fmtDate(iso: string) {
  try { return new Date(iso).toLocaleDateString('fr-FR'); } catch { return iso; }
}

// ── Page principale ───────────────────────────────────────────────────────────

export default function DemandesAccesPage() {
  const { user, userData, isPension, loading: authLoading } = usePensionAccess();
  const router = useRouter();
  const activeProfileId = useActiveProfile();

  const [demandes, setDemandes] = useState<PensionAcces[]>([]);
  const [loading, setLoading]   = useState(true);
  const [recherche, setRecherche] = useState('');
  const [tab, setTab]           = useState<'pending' | 'active' | 'revoked' | 'tous'>('tous');


  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isPension) { router.push('/'); return; }
  }, [user, userData, isPension, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    // Repli (profil actif inconnu) : le profil pension / pet-sitter du compte —
    // jamais is_main (souvent l'élevage : ses accès s'affichaient ici).
    let proProfileId = activeProfileId || null;
    if (!proProfileId) {
      const { data: proProfile } = await supabase.from('user_profiles_complet')
        .select('id').eq('uid', user.uid).in('profile_type', ['pension', 'garde']).limit(1).maybeSingle();
      proProfileId = proProfile?.id ?? null;
    }
    if (!proProfileId) { setDemandes([]); setLoading(false); return; }
    const { data } = await supabase.from('animal_access')
      .select('id, animal_id, statut, created_at, granted_at')
      .eq('pro_profile_id', proProfileId)
      .order('created_at', { ascending: false });
    const rows = (data ?? []) as PensionAcces[];
    const ids = rows.map(r => r.animal_id);
    if (ids.length > 0) {
      const { data: animaux } = await supabase.from('animaux').select('id, nom, photo_url, identification').in('id', ids);
      const parId = new Map((animaux ?? []).map(a => [String(a.id), a]));
      for (const r of rows) {
        const a = parId.get(String(r.animal_id));
        if (a) { r.animal_nom = a.nom ?? 'Animal'; r.photo_url = a.photo_url; r.puce = a.identification; }
      }
    }
    // Séjour terminé et rien à venir : retiré de la liste (sauf demande en attente).
    const partis = await animauxPartis(proProfileId, new Map(rows.map(r => [String(r.animal_id), r.granted_at ?? r.created_at])));
    setDemandes(rows.filter(r => r.statut === 'pending' || !partis.has(String(r.animal_id))));
    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  const q = recherche.trim().toLowerCase();
  const qPuce = q.replace(/[\s-]/g, '');
  const filtered = demandes.filter(d => (tab === 'tous' || d.statut === tab)
    && (!q || (d.animal_nom ?? '').toLowerCase().includes(q)
      || (!!qPuce && (d.puce ?? '').toLowerCase().replace(/[\s-]/g, '').includes(qPuce))));

  const counts = {
    tous:    demandes.length,
    pending: demandes.filter(d => d.statut === 'pending').length,
    active:  demandes.filter(d => d.statut === 'active').length,
    revoked: demandes.filter(d => d.statut === 'revoked').length,
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
            {([['tous', 'Toutes'], ['pending', 'En attente'], ['active', 'Autorisées'], ['revoked', 'Refusées']] as const).map(([val, label]) => (
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
          Scannez la puce d'un animal depuis l'application mobile pour envoyer une demande d'accès à son propriétaire.
          Le propriétaire reçoit une notification et peut autoriser ou refuser la consultation de la fiche.
        </div>

        <input value={recherche} onChange={e => setRecherche(e.target.value)}
          placeholder="Rechercher par nom ou numéro de puce" aria-label="Rechercher par nom ou numéro de puce"
          style={{ width: '100%', boxSizing: 'border-box', padding: '12px 14px', borderRadius: 12, border: '1px solid #d1d5db',
            background: 'white', fontFamily: 'Galey, sans-serif', fontSize: 14, marginBottom: 16, outline: 'none' }} />

        {loading ? (
          <div style={{ textAlign: 'center', padding: 60, color: '#999' }}>Chargement…</div>
        ) : filtered.length === 0 ? (
          <div style={{ textAlign: 'center', padding: 60, color: '#aaa' }}>
            <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 16 }}>{q ? 'Aucun résultat' : 'Aucune demande'}</p>
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
  const router = useRouter();
  const [photoKo, setPhotoKo] = useState(false);
  const cfg = STATUT_CONFIG[demande.statut];

  return (
    <div style={{
      background: 'white', borderRadius: 14, padding: 16,
      border: '1px solid #e5e7eb', boxShadow: '0 2px 8px rgba(0,0,0,0.05)',
    }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
        {/* Photo de l'animal, sinon son initiale */}
        {demande.photo_url && !photoKo ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={demande.photo_url} alt={demande.animal_nom ?? 'Animal'} onError={() => setPhotoKo(true)}
            style={{ width: 64, height: 64, borderRadius: 10, objectFit: 'cover', flexShrink: 0 }} />
        ) : <div style={{
          width: 64, height: 64, borderRadius: 10,
          background: 'rgba(12,92,108,0.08)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 24, flexShrink: 0, fontFamily: 'Galey, sans-serif', fontWeight: 700, color: TEAL,
        }}>{(demande.animal_nom ?? 'A').charAt(0).toUpperCase()}</div>}

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

          {demande.puce && (
            <p style={{ margin: '0 0 4px', fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#9ca3af' }}>Puce : {demande.puce}</p>
          )}

          {demande.statut === 'active' && (<>
            <p style={{ margin: '6px 0 0', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#6E9E57', fontWeight: 600 }}>
              Le propriétaire a autorisé l'accès à cette fiche.
            </p>
            <button onClick={() => router.push(`/pension/fiche/${demande.animal_id}`)}
              style={{ marginTop: 8, padding: '8px 16px', background: TEAL, color: 'white', border: 'none', borderRadius: 10,
                fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 13, cursor: 'pointer' }}>Voir la fiche</button>
          </>)}
          {demande.statut === 'revoked' && (
            <p style={{ margin: '6px 0 0', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#d32f2f' }}>
              Le propriétaire a refusé la demande.
            </p>
          )}
          {demande.statut === 'pending' && (
            <p style={{ margin: '6px 0 0', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#e08000' }}>
              En attente de réponse du propriétaire.
            </p>
          )}
        </div>
      </div>
    </div>
  );
}
