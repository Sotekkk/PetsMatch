'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';

// ── Types ─────────────────────────────────────────────────────────────────────

interface PensionEntree {
  id: string;
  pro_uid: string;
  animal_nom: string;
  espece?: string;
  race?: string;
  puce?: string;
  proprietaire_nom?: string;
  proprietaire_contact?: string;
  date_entree: string;
  date_sortie_prevue?: string;
  date_sortie_effective?: string;
  notes?: string;
  statut: 'en_pension' | 'sorti';
  animal_id?: string;
  created_at: string;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const TEAL = '#0C5C6C';
const GREEN = '#6E9E57';

function fmtDate(iso?: string) {
  if (!iso) return '—';
  try { return new Date(iso).toLocaleDateString('fr-FR'); } catch { return iso; }
}

// ── Composant principal ───────────────────────────────────────────────────────

export default function RegistrePensionPage() {
  const { user, userData } = useAuth();
  const router = useRouter();

  const [tab, setTab]           = useState<'en_pension' | 'sorti' | 'tous'>('en_pension');
  const [entrees, setEntrees]   = useState<PensionEntree[]>([]);
  const [loading, setLoading]   = useState(true);
  const [showForm, setShowForm] = useState(false);

  const isPension = userData?.isPro && userData?.catPro === 'pension';

  useEffect(() => {
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isPension) { router.push('/'); return; }
  }, [user, userData, isPension, router]);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    const { data } = await supabase
      .from('pension_entrees')
      .select('*')
      .eq('pro_uid', user.uid)
      .order('date_entree', { ascending: false });
    setEntrees((data ?? []) as PensionEntree[]);
    setLoading(false);
  }, [user]);

  useEffect(() => { load(); }, [load]);

  async function marquerSorti(id: string) {
    const today = new Date().toISOString().split('T')[0];
    await supabase.from('pension_entrees').update({
      statut: 'sorti',
      date_sortie_effective: today,
    }).eq('id', id);
    setEntrees(prev => prev.map(e => e.id === id
      ? { ...e, statut: 'sorti', date_sortie_effective: today }
      : e
    ));
  }

  const filtered = entrees.filter(e =>
    tab === 'tous' ? true : e.statut === tab
  );

  if (!user || !userData) return null;

  return (
    <div style={{ minHeight: '100vh', background: '#F8F8F6', paddingBottom: 60 }}>
      {/* Header */}
      <div style={{ background: TEAL, padding: '20px 24px 0' }}>
        <div style={{ maxWidth: 800, margin: '0 auto' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 16 }}>
            <button
              onClick={() => router.back()}
              style={{ background: 'none', border: 'none', color: 'white', fontSize: 20, cursor: 'pointer', padding: 0 }}
            >←</button>
            <h1 style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 20, color: 'white' }}>
              Registre pension
            </h1>
            <div style={{ flex: 1 }} />
            <button
              onClick={() => setShowForm(true)}
              style={{
                background: 'rgba(255,255,255,0.2)', border: '1px solid rgba(255,255,255,0.4)',
                color: 'white', borderRadius: 20, padding: '6px 16px', cursor: 'pointer',
                fontFamily: 'Galey, sans-serif', fontSize: 13, fontWeight: 700,
              }}
            >+ Nouvelle entrée</button>
          </div>

          {/* Onglets */}
          <div style={{ display: 'flex', gap: 0 }}>
            {([['en_pension', 'En pension'], ['sorti', 'Sortis'], ['tous', 'Tous']] as const).map(([val, label]) => (
              <button key={val} onClick={() => setTab(val)} style={{
                flex: 1, padding: '10px 0', background: 'none', border: 'none',
                borderBottom: tab === val ? '2px solid white' : '2px solid transparent',
                color: tab === val ? 'white' : 'rgba(255,255,255,0.6)',
                fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 13, cursor: 'pointer',
              }}>{label}</button>
            ))}
          </div>
        </div>
      </div>

      {/* Contenu */}
      <div style={{ maxWidth: 800, margin: '24px auto', padding: '0 16px' }}>
        {loading ? (
          <div style={{ textAlign: 'center', padding: 60, color: '#999' }}>Chargement…</div>
        ) : filtered.length === 0 ? (
          <div style={{ textAlign: 'center', padding: 60, color: '#aaa' }}>
            <div style={{ fontSize: 48, marginBottom: 12 }}>🐾</div>
            <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 16 }}>Aucune entrée</p>
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {filtered.map(e => (
              <EntreeCard key={e.id} entree={e} onSorti={() => marquerSorti(e.id)} />
            ))}
          </div>
        )}
      </div>

      {/* Formulaire modal */}
      {showForm && (
        <NewEntreeModal
          proUid={user.uid}
          onClose={() => setShowForm(false)}
          onSaved={() => { setShowForm(false); load(); }}
        />
      )}
    </div>
  );
}

// ── Carte entrée ──────────────────────────────────────────────────────────────

function EntreeCard({ entree, onSorti }: { entree: PensionEntree; onSorti: () => void }) {
  const inPension = entree.statut === 'en_pension';
  return (
    <div style={{
      background: 'white', borderRadius: 14, padding: 16,
      border: `1px solid ${inPension ? 'rgba(12,92,108,0.2)' : '#e5e7eb'}`,
      boxShadow: '0 2px 8px rgba(0,0,0,0.05)',
    }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
        <div style={{ flex: 1 }}>
          {/* Nom + badge */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
            <span style={{ fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 16, color: '#1E2025' }}>
              {entree.animal_nom}
            </span>
            <span style={{
              padding: '2px 10px', borderRadius: 20, fontSize: 11, fontWeight: 700,
              fontFamily: 'Galey, sans-serif',
              background: inPension ? '#E0F2F1' : '#f3f4f6',
              color: inPension ? TEAL : '#6b7280',
            }}>
              {inPension ? 'En pension' : 'Sorti'}
            </span>
          </div>

          {/* Espèce / Race / Puce */}
          {(entree.espece || entree.race || entree.puce) && (
            <p style={{ margin: '0 0 6px', fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#9ca3af' }}>
              {[entree.espece, entree.race].filter(Boolean).join(' · ')}
              {entree.puce ? ` — Puce : ${entree.puce}` : ''}
            </p>
          )}

          <hr style={{ border: 'none', borderTop: '1px solid #f0f0f0', margin: '8px 0' }} />

          {/* Propriétaire */}
          {(entree.proprietaire_nom || entree.proprietaire_contact) && (
            <p style={{ margin: '0 0 4px', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#374151' }}>
              👤 {[entree.proprietaire_nom, entree.proprietaire_contact].filter(Boolean).join(' · ')}
            </p>
          )}

          {/* Dates */}
          <p style={{ margin: '0 0 4px', fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#374151' }}>
            🔑 Entrée : {fmtDate(entree.date_entree)}
            {entree.date_sortie_prevue ? ` · Prévue : ${fmtDate(entree.date_sortie_prevue)}` : ''}
          </p>
          {entree.date_sortie_effective && (
            <p style={{ margin: '0 0 4px', fontFamily: 'Galey, sans-serif', fontSize: 13, color: GREEN, fontWeight: 600 }}>
              ✓ Sorti le : {fmtDate(entree.date_sortie_effective)}
            </p>
          )}

          {/* Notes */}
          {entree.notes && (
            <p style={{ margin: '6px 0 0', fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#6b7280',
              overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: '100%' }}>
              {entree.notes}
            </p>
          )}
        </div>
      </div>

      {/* Bouton marquer sorti */}
      {inPension && (
        <div style={{ marginTop: 12, display: 'flex', justifyContent: 'flex-end' }}>
          <button onClick={onSorti} style={{
            padding: '6px 16px', borderRadius: 20, border: `1px solid ${TEAL}`,
            background: 'transparent', color: TEAL, cursor: 'pointer',
            fontFamily: 'Galey, sans-serif', fontSize: 13, fontWeight: 700,
          }}>
            Marquer sorti →
          </button>
        </div>
      )}
    </div>
  );
}

// ── Formulaire nouvelle entrée ────────────────────────────────────────────────

function NewEntreeModal({ proUid, onClose, onSaved }: {
  proUid: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [form, setForm] = useState({
    animal_nom: '',
    espece: '',
    race: '',
    puce: '',
    proprietaire_nom: '',
    proprietaire_contact: '',
    date_entree: new Date().toISOString().split('T')[0],
    date_sortie_prevue: '',
    notes: '',
  });
  const [saving, setSaving] = useState(false);
  const [error, setError]   = useState('');

  function set(field: string, value: string) {
    setForm(f => ({ ...f, [field]: value }));
  }

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (!form.animal_nom.trim()) { setError('Le nom de l\'animal est obligatoire.'); return; }
    setSaving(true);
    const payload: Record<string, string | null> = {
      pro_uid: proUid,
      animal_nom: form.animal_nom.trim(),
      espece: form.espece.trim() || null!,
      race: form.race.trim() || null!,
      puce: form.puce.trim() || null!,
      proprietaire_nom: form.proprietaire_nom.trim() || null!,
      proprietaire_contact: form.proprietaire_contact.trim() || null!,
      date_entree: form.date_entree,
      date_sortie_prevue: form.date_sortie_prevue || null!,
      notes: form.notes.trim() || null!,
      statut: 'en_pension',
      created_at: new Date().toISOString(),
    };
    const { error: err } = await supabase.from('pension_entrees').insert(payload);
    if (err) { setError(err.message); setSaving(false); return; }
    onSaved();
  }

  const inputStyle: React.CSSProperties = {
    width: '100%', padding: '10px 12px', borderRadius: 8, border: '1px solid #d1d5db',
    fontFamily: 'Galey, sans-serif', fontSize: 14, boxSizing: 'border-box',
    background: '#f9fafb', outline: 'none',
  };
  const labelStyle: React.CSSProperties = {
    fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 600,
    color: '#6b7280', marginBottom: 4, display: 'block',
  };

  return (
    <div style={{
      position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)',
      display: 'flex', alignItems: 'flex-end', justifyContent: 'center',
      zIndex: 1000, padding: '0 0 0 0',
    }} onClick={e => e.target === e.currentTarget && onClose()}>
      <div style={{
        background: 'white', borderRadius: '24px 24px 0 0',
        width: '100%', maxWidth: 600, maxHeight: '90vh', overflowY: 'auto',
        padding: '20px 24px 40px',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', marginBottom: 20 }}>
          <h2 style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 18, flex: 1 }}>
            Nouvelle entrée pension
          </h2>
          <button onClick={onClose} style={{ background: 'none', border: 'none', fontSize: 22, cursor: 'pointer', color: '#9ca3af' }}>×</button>
        </div>

        <form onSubmit={save}>
          {/* ANIMAL */}
          <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 11, fontWeight: 700, color: TEAL, letterSpacing: 0.8, marginBottom: 10 }}>ANIMAL</p>

          <div style={{ marginBottom: 12 }}>
            <label style={labelStyle}>Nom de l'animal *</label>
            <input style={inputStyle} placeholder="Ex : Médor" value={form.animal_nom}
              onChange={e => set('animal_nom', e.target.value)} required />
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 12 }}>
            <div>
              <label style={labelStyle}>Espèce</label>
              <input style={inputStyle} placeholder="Ex : Chien" value={form.espece}
                onChange={e => set('espece', e.target.value)} />
            </div>
            <div>
              <label style={labelStyle}>Race</label>
              <input style={inputStyle} placeholder="Ex : Labrador" value={form.race}
                onChange={e => set('race', e.target.value)} />
            </div>
          </div>

          <div style={{ marginBottom: 20 }}>
            <label style={labelStyle}>Numéro de puce</label>
            <input style={inputStyle} placeholder="250 269 810 000 000" value={form.puce}
              onChange={e => set('puce', e.target.value)} />
          </div>

          {/* PROPRIÉTAIRE */}
          <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 11, fontWeight: 700, color: TEAL, letterSpacing: 0.8, marginBottom: 10 }}>PROPRIÉTAIRE</p>

          <div style={{ marginBottom: 12 }}>
            <label style={labelStyle}>Nom</label>
            <input style={inputStyle} placeholder="Nom du propriétaire" value={form.proprietaire_nom}
              onChange={e => set('proprietaire_nom', e.target.value)} />
          </div>
          <div style={{ marginBottom: 20 }}>
            <label style={labelStyle}>Contact (tél / email)</label>
            <input style={inputStyle} placeholder="06 XX XX XX XX" value={form.proprietaire_contact}
              onChange={e => set('proprietaire_contact', e.target.value)} />
          </div>

          {/* SÉJOUR */}
          <p style={{ fontFamily: 'Galey, sans-serif', fontSize: 11, fontWeight: 700, color: TEAL, letterSpacing: 0.8, marginBottom: 10 }}>SÉJOUR</p>

          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 12 }}>
            <div>
              <label style={labelStyle}>Date d'entrée *</label>
              <input type="date" style={inputStyle} value={form.date_entree}
                onChange={e => set('date_entree', e.target.value)} required />
            </div>
            <div>
              <label style={labelStyle}>Sortie prévue</label>
              <input type="date" style={inputStyle} value={form.date_sortie_prevue}
                onChange={e => set('date_sortie_prevue', e.target.value)} />
            </div>
          </div>

          <div style={{ marginBottom: 24 }}>
            <label style={labelStyle}>Notes</label>
            <textarea style={{ ...inputStyle, resize: 'vertical', minHeight: 80 }}
              placeholder="Alimentation, médicaments, comportement…" value={form.notes}
              onChange={e => set('notes', e.target.value)} />
          </div>

          {error && <p style={{ color: 'red', fontFamily: 'Galey, sans-serif', fontSize: 13, marginBottom: 12 }}>{error}</p>}

          <button type="submit" disabled={saving} style={{
            width: '100%', padding: '14px 0', background: TEAL, color: 'white',
            border: 'none', borderRadius: 12, fontFamily: 'Galey, sans-serif',
            fontWeight: 700, fontSize: 16, cursor: saving ? 'not-allowed' : 'pointer',
            opacity: saving ? 0.7 : 1,
          }}>
            {saving ? 'Enregistrement…' : 'Enregistrer l\'entrée'}
          </button>
        </form>
      </div>
    </div>
  );
}
