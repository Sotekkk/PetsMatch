'use client';

import { useState } from 'react';
import { supabase } from '@/lib/supabase';

export interface PensionEntree {
  id: string;
  pro_uid: string;
  animal_nom: string;
  espece?: string;
  race?: string;
  puce?: string;
  proprietaire_nom?: string;
  proprietaire_contact?: string;
  proprietaire_email?: string;
  date_entree: string;
  date_sortie_prevue?: string;
  date_sortie_effective?: string;
  logement_id?: string | null;
  animal_id?: string | null;
  notes?: string;
  statut: 'en_pension' | 'sorti';
  created_at: string;
}

const TEAL  = '#0C5C6C';
const GREEN = '#6E9E57';

export function PensionEntreeModal({ proUid, proProfileId, entree, initialLogementId, initialDateEntree, onClose, onSaved }: {
  proUid: string;
  proProfileId: string | null;
  entree?: PensionEntree;
  initialLogementId?: string;
  initialDateEntree?: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const isEdit = !!entree;
  const [form, setForm] = useState({
    animal_nom:            entree?.animal_nom ?? '',
    espece:                entree?.espece ?? '',
    race:                  entree?.race ?? '',
    puce:                  entree?.puce ?? '',
    proprietaire_nom:      entree?.proprietaire_nom ?? '',
    proprietaire_contact:  entree?.proprietaire_contact ?? '',
    proprietaire_email:    entree?.proprietaire_email ?? '',
    date_entree:           entree?.date_entree ?? initialDateEntree ?? new Date().toISOString().split('T')[0],
    date_sortie_prevue:    entree?.date_sortie_prevue ?? '',
    date_sortie_effective: entree?.date_sortie_effective ?? '',
    statut:                entree?.statut ?? 'en_pension',
    notes:                 entree?.notes ?? '',
  });
  const [saving, setSaving] = useState(false);
  const [error, setError]   = useState('');

  function set(field: string, value: string) { setForm(f => ({ ...f, [field]: value })); }

  async function save(e: React.FormEvent) {
    e.preventDefault();
    if (!form.animal_nom.trim()) { setError('Le nom est obligatoire.'); return; }
    setSaving(true);
    setError('');
    const payload = {
      pro_uid:              proUid,
      ...(proProfileId ? { pro_profile_id: proProfileId } : {}),
      animal_nom:           form.animal_nom.trim(),
      espece:               form.espece.trim().toLowerCase() || null,
      race:                 form.race.trim() || null,
      puce:                 form.puce.trim() || null,
      proprietaire_nom:     form.proprietaire_nom.trim() || null,
      proprietaire_contact: form.proprietaire_contact.trim() || null,
      proprietaire_email:   form.proprietaire_email.trim() || null,
      date_entree:          form.date_entree,
      date_sortie_prevue:   form.date_sortie_prevue || null,
      date_sortie_effective: form.statut === 'sorti' ? (form.date_sortie_effective || null) : null,
      notes:                form.notes.trim() || null,
      statut:               form.statut,
      ...(!isEdit && initialLogementId ? { logement_id: initialLogementId } : {}),
    };
    const { error: err } = isEdit
      ? await supabase.from('pension_entrees').update(payload).eq('id', entree!.id)
      : await supabase.from('pension_entrees').insert({ ...payload, created_at: new Date().toISOString() });
    if (err) { setError(err.message); setSaving(false); return; }
    onSaved();
  }

  const inp: React.CSSProperties = {
    width: '100%', padding: '10px 12px', borderRadius: 8, border: '1px solid #d1d5db',
    fontFamily: 'Galey, sans-serif', fontSize: 14, boxSizing: 'border-box',
    background: '#f9fafb', outline: 'none',
  };
  const lbl: React.CSSProperties = {
    fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 600,
    color: '#6b7280', marginBottom: 4, display: 'block',
  };
  const sec: React.CSSProperties = {
    fontFamily: 'Galey, sans-serif', fontSize: 11, fontWeight: 700,
    color: TEAL, letterSpacing: 0.8, margin: '16px 0 10px',
  };

  return (
    <div style={{
      position: 'fixed', inset: 0, background: 'rgba(0,0,0,0.5)',
      display: 'flex', alignItems: 'flex-end', justifyContent: 'center',
      zIndex: 1000,
    }} onClick={e => e.target === e.currentTarget && onClose()}>
      <div style={{
        background: 'white', borderRadius: '24px 24px 0 0',
        width: '100%', maxWidth: 620, maxHeight: '90vh', overflowY: 'auto',
        padding: '20px 24px 40px',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', marginBottom: 16 }}>
          <h2 style={{ margin: 0, fontFamily: 'Galey, sans-serif', fontWeight: 700, fontSize: 18, flex: 1 }}>
            {isEdit ? 'Modifier l\'entrée' : 'Nouvelle entrée'}
          </h2>
          <button onClick={onClose}
            style={{ background: 'none', border: 'none', fontSize: 24, cursor: 'pointer', color: '#9ca3af' }}>×</button>
        </div>

        <form onSubmit={save}>
          {/* Statut (édition seulement) */}
          {isEdit && (
            <>
              <p style={sec}>STATUT</p>
              <div style={{ display: 'flex', gap: 8, marginBottom: 4 }}>
                {([['en_pension', 'En pension', GREEN], ['sorti', 'Sorti', TEAL]] as const).map(([val, label, color]) => (
                  <button key={val} type="button" onClick={() => set('statut', val)}
                    style={{
                      flex: 1, padding: '10px 0', border: `1px solid ${form.statut === val ? color : '#d1d5db'}`,
                      borderRadius: 10, background: form.statut === val ? color : 'transparent',
                      color: form.statut === val ? 'white' : '#374151',
                      fontFamily: 'Galey, sans-serif', fontSize: 13, fontWeight: 700, cursor: 'pointer',
                    }}>
                    {label}
                  </button>
                ))}
              </div>
            </>
          )}

          {/* Animal */}
          <p style={sec}>ANIMAL</p>
          <div style={{ marginBottom: 12 }}>
            <label style={lbl}>Nom de l&apos;animal *</label>
            <input style={inp} placeholder="Ex : Médor" value={form.animal_nom}
              onChange={e => set('animal_nom', e.target.value)} required />
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 12 }}>
            <div>
              <label style={lbl}>Espèce</label>
              <input style={inp} placeholder="Chien" value={form.espece}
                onChange={e => set('espece', e.target.value)} />
            </div>
            <div>
              <label style={lbl}>Race</label>
              <input style={inp} placeholder="Labrador" value={form.race}
                onChange={e => set('race', e.target.value)} />
            </div>
          </div>
          <div style={{ marginBottom: 4 }}>
            <label style={lbl}>Numéro de puce</label>
            <input style={inp} placeholder="250 269 810 000 000" value={form.puce}
              onChange={e => set('puce', e.target.value)} />
          </div>

          {/* Propriétaire */}
          <p style={sec}>PROPRIÉTAIRE</p>
          <div style={{ marginBottom: 12 }}>
            <label style={lbl}>Nom du propriétaire</label>
            <input style={inp} placeholder="Nom" value={form.proprietaire_nom}
              onChange={e => set('proprietaire_nom', e.target.value)} />
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 4 }}>
            <div>
              <label style={lbl}>Téléphone</label>
              <input style={inp} placeholder="06 XX XX XX XX" type="tel"
                value={form.proprietaire_contact}
                onChange={e => set('proprietaire_contact', e.target.value)} />
            </div>
            <div>
              <label style={lbl}>Email</label>
              <input style={inp} placeholder="adresse@email.com" type="email"
                value={form.proprietaire_email}
                onChange={e => set('proprietaire_email', e.target.value)} />
            </div>
          </div>

          {/* Séjour */}
          <p style={sec}>SÉJOUR</p>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, marginBottom: 12 }}>
            <div>
              <label style={lbl}>Date d&apos;entrée *</label>
              <input type="date" style={inp} value={form.date_entree}
                onChange={e => set('date_entree', e.target.value)} required />
            </div>
            <div>
              <label style={lbl}>Sortie prévue</label>
              <input type="date" style={inp} value={form.date_sortie_prevue}
                onChange={e => set('date_sortie_prevue', e.target.value)} />
            </div>
          </div>
          {(isEdit && form.statut === 'sorti') && (
            <div style={{ marginBottom: 12 }}>
              <label style={lbl}>Sortie effective</label>
              <input type="date" style={inp} value={form.date_sortie_effective}
                onChange={e => set('date_sortie_effective', e.target.value)} />
            </div>
          )}
          <div style={{ marginBottom: 24 }}>
            <label style={lbl}>Notes</label>
            <textarea style={{ ...inp, resize: 'vertical', minHeight: 80 }}
              placeholder="Alimentation, médicaments, comportement…" value={form.notes}
              onChange={e => set('notes', e.target.value)} />
          </div>

          {error && (
            <p style={{ color: 'red', fontFamily: 'Galey, sans-serif', fontSize: 13, marginBottom: 12 }}>{error}</p>
          )}

          <button type="submit" disabled={saving} style={{
            width: '100%', padding: '14px 0', background: TEAL, color: 'white',
            border: 'none', borderRadius: 12, fontFamily: 'Galey, sans-serif',
            fontWeight: 700, fontSize: 16, cursor: saving ? 'not-allowed' : 'pointer', opacity: saving ? 0.7 : 1,
          }}>
            {saving ? 'Enregistrement…' : isEdit ? 'Enregistrer les modifications' : 'Enregistrer l\'entrée'}
          </button>
        </form>
      </div>
    </div>
  );
}
