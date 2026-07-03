'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { lookupAnimalByChip, requestAnimalAccess } from '@/lib/pension-chip-lookup';

export interface PensionEntree {
  id: string;
  pro_uid: string;
  animal_nom: string;
  espece?: string | null;
  race?: string | null;
  puce?: string | null;
  proprietaire_nom?: string | null;
  proprietaire_contact?: string | null;
  proprietaire_email?: string | null;
  proprietaire_adresse?: string | null;
  date_entree: string;
  date_sortie_prevue?: string | null;
  date_sortie_effective?: string | null;
  logement_id?: string | null;
  animal_id?: string | null;
  seul_dans_logement?: boolean;
  notes?: string | null;
  statut: 'en_pension' | 'sorti';
  created_at: string;
}

const TEAL  = '#0C5C6C';
const GREEN = '#6E9E57';

export interface PensionEntreePrefill {
  animal_id?: string;
  animal_nom?: string;
  espece?: string;
  race?: string;
  puce?: string;
  proprietaire_nom?: string;
  proprietaire_contact?: string;
  proprietaire_email?: string;
  proprietaire_adresse?: string;
  owner_uid?: string;
}

export function PensionEntreeModal({ proUid, proProfileId, entree, initialLogementId, initialDateEntree, prefill, onClose, onSaved }: {
  proUid: string;
  proProfileId: string | null;
  entree?: PensionEntree;
  initialLogementId?: string;
  initialDateEntree?: string;
  prefill?: PensionEntreePrefill;
  onClose: () => void;
  onSaved: () => void;
}) {
  const isEdit = !!entree;
  const [form, setForm] = useState({
    animal_nom:            entree?.animal_nom ?? prefill?.animal_nom ?? '',
    espece:                entree?.espece ?? prefill?.espece ?? '',
    race:                  entree?.race ?? prefill?.race ?? '',
    puce:                  entree?.puce ?? prefill?.puce ?? '',
    proprietaire_nom:      entree?.proprietaire_nom ?? prefill?.proprietaire_nom ?? '',
    proprietaire_contact:  entree?.proprietaire_contact ?? prefill?.proprietaire_contact ?? '',
    proprietaire_email:    entree?.proprietaire_email ?? prefill?.proprietaire_email ?? '',
    proprietaire_adresse:  entree?.proprietaire_adresse ?? prefill?.proprietaire_adresse ?? '',
    date_entree:           entree?.date_entree ?? initialDateEntree ?? new Date().toISOString().split('T')[0],
    date_sortie_prevue:    entree?.date_sortie_prevue ?? '',
    date_sortie_effective: entree?.date_sortie_effective ?? '',
    statut:                entree?.statut ?? 'en_pension',
    notes:                 entree?.notes ?? '',
    seul_dans_logement:    entree?.seul_dans_logement ?? false,
  });
  const [animalId, setAnimalId] = useState<string | null | undefined>(entree?.animal_id ?? prefill?.animal_id);
  const [linkingFiche, setLinkingFiche] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError]   = useState('');
  const [accessStatus, setAccessStatus] = useState<string | null | undefined>(undefined);
  const [checkingAccess, setCheckingAccess] = useState(false);

  useEffect(() => {
    if (!animalId || !proProfileId) return;
    let cancelled = false;
    supabase.from('animal_access').select('statut')
      .eq('pro_profile_id', proProfileId).eq('animal_id', animalId).maybeSingle()
      .then(({ data }) => { if (!cancelled) setAccessStatus(data?.statut ?? null); });
    return () => { cancelled = true; };
  }, [animalId, proProfileId]);

  async function demanderAcces() {
    if (!animalId) return;
    setCheckingAccess(true);
    try {
      const { data: propRow } = await supabase.from('animaux_proprietes')
        .select('uid_proprio').eq('animal_id', animalId).is('date_fin', null)
        .order('date_debut', { ascending: false }).limit(1).maybeSingle();
      const ownerUid = propRow?.uid_proprio;
      if (!ownerUid) {
        setError('Propriétaire introuvable pour cet animal.');
        return;
      }
      await requestAnimalAccess(animalId, ownerUid, proUid, proProfileId, 'Votre pension', form.animal_nom);
      setAccessStatus('pending');
    } finally {
      setCheckingAccess(false);
    }
  }

  async function retrouverViaPuce() {
    const puce = entree?.puce?.trim();
    if (!puce) {
      setError('Aucun numéro de puce enregistré pour ce séjour.');
      return;
    }
    setLinkingFiche(true);
    try {
      const found = await lookupAnimalByChip(puce);
      if (!found.animal_id) {
        setError('Aucun animal trouvé avec cette puce.');
        return;
      }
      const update: Record<string, string> = {};
      if (!form.espece.trim() && found.espece) update.espece = found.espece;
      if (!form.race.trim() && found.race) update.race = found.race;
      if (!form.proprietaire_nom.trim() && found.proprietaire_nom) update.proprietaire_nom = found.proprietaire_nom;
      if (!form.proprietaire_contact.trim() && found.proprietaire_contact) update.proprietaire_contact = found.proprietaire_contact;
      if (!form.proprietaire_email.trim() && found.proprietaire_email) update.proprietaire_email = found.proprietaire_email;
      if (!form.proprietaire_adresse.trim() && found.proprietaire_adresse) update.proprietaire_adresse = found.proprietaire_adresse;
      if (!animalId && found.animal_id) update.animal_id = found.animal_id;
      if (Object.keys(update).length > 0 && isEdit && entree) {
        await supabase.from('pension_entrees').update(update).eq('id', entree.id);
      }
      setForm(f => ({ ...f, ...update }));
      if (!animalId) setAnimalId(found.animal_id);
    } finally {
      setLinkingFiche(false);
    }
  }

  async function linkFiche() {
    const chip = window.prompt('Numéro de puce de l\'animal :');
    if (!chip || !chip.trim()) return;
    setLinkingFiche(true);
    try {
      const found = await lookupAnimalByChip(chip.trim());
      if (!found.animal_id) {
        setError('Aucun animal trouvé avec cette puce.');
        return;
      }
      if (isEdit && entree) {
        const update: Record<string, string> = { animal_id: found.animal_id };
        if (found.proprietaire_nom) update.proprietaire_nom = found.proprietaire_nom;
        if (found.proprietaire_contact) update.proprietaire_contact = found.proprietaire_contact;
        if (found.proprietaire_email) update.proprietaire_email = found.proprietaire_email;
        if (found.proprietaire_adresse) update.proprietaire_adresse = found.proprietaire_adresse;
        await supabase.from('pension_entrees').update(update).eq('id', entree.id);
        if (found.owner_uid) {
          await requestAnimalAccess(found.animal_id, found.owner_uid, proUid, proProfileId,
            'Votre pension', entree.animal_nom);
          setAccessStatus('pending');
        }
      }
      setAnimalId(found.animal_id);
      setForm(f => ({
        ...f,
        proprietaire_nom: found.proprietaire_nom || f.proprietaire_nom,
        proprietaire_contact: found.proprietaire_contact || f.proprietaire_contact,
        proprietaire_email: found.proprietaire_email || f.proprietaire_email,
        proprietaire_adresse: found.proprietaire_adresse || f.proprietaire_adresse,
      }));
    } finally {
      setLinkingFiche(false);
    }
  }

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
      proprietaire_adresse: form.proprietaire_adresse.trim() || null,
      date_entree:          form.date_entree,
      date_sortie_prevue:   form.date_sortie_prevue || null,
      date_sortie_effective: form.statut === 'sorti' ? (form.date_sortie_effective || null) : null,
      notes:                form.notes.trim() || null,
      statut:               form.statut,
      seul_dans_logement:   form.seul_dans_logement,
      ...(!isEdit && initialLogementId ? { logement_id: initialLogementId } : {}),
      ...(!isEdit && animalId ? { animal_id: animalId } : {}),
    };
    const { error: err } = isEdit
      ? await supabase.from('pension_entrees').update(payload).eq('id', entree!.id)
      : await supabase.from('pension_entrees').insert({ ...payload, created_at: new Date().toISOString() });
    if (err) { setError(err.message); setSaving(false); return; }
    onSaved();
  }

  async function deleteEntree() {
    if (!entree) return;
    if (!window.confirm('Supprimer ce séjour ? Cette action est irréversible (annulation de la réservation).')) return;
    setSaving(true);
    const { error: err } = await supabase.from('pension_entrees').delete().eq('id', entree.id);
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
          <div style={{ marginBottom: 12 }}>
            <label style={lbl}>Numéro de puce</label>
            <input style={inp} placeholder="250 269 810 000 000" value={form.puce}
              onChange={e => set('puce', e.target.value)} />
          </div>
          {isEdit && entree?.puce && (
            <div style={{ marginBottom: 12 }}>
              <button type="button" onClick={retrouverViaPuce} disabled={linkingFiche}
                style={{ width: '100%', padding: '10px 0', borderRadius: 10, border: `1px solid ${TEAL}`,
                  background: 'transparent', color: TEAL, cursor: 'pointer',
                  fontFamily: 'Galey, sans-serif', fontSize: 13, fontWeight: 700 }}>
                {linkingFiche ? 'Recherche…' : 'Retrouver via la puce'}
              </button>
            </div>
          )}

          {/* Fiche animal */}
          <p style={sec}>FICHE ANIMAL</p>
          <div style={{ marginBottom: 12 }}>
            {animalId ? (
              <>
                <Link href={`/pension/fiche/${animalId}`}
                  style={{ display: 'block', textAlign: 'center', padding: '10px 0', borderRadius: 10,
                    border: `1px solid ${TEAL}`, color: TEAL, fontFamily: 'Galey, sans-serif', fontSize: 13, fontWeight: 700, textDecoration: 'none' }}>
                  Voir la fiche
                </Link>
                {accessStatus === undefined ? null : accessStatus === null ? (
                  <button type="button" onClick={demanderAcces} disabled={checkingAccess}
                    style={{ width: '100%', padding: '10px 0', borderRadius: 10, border: `1px solid ${GREEN}`,
                      background: 'transparent', color: GREEN, cursor: 'pointer', marginTop: 8,
                      fontFamily: 'Galey, sans-serif', fontSize: 13, fontWeight: 700 }}>
                    {checkingAccess ? 'Envoi…' : 'Demander l\'accès à la fiche'}
                  </button>
                ) : (
                  <p style={{ margin: '8px 0 0', fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#9ca3af' }}>
                    {accessStatus === 'active' ? 'Accès accordé par le propriétaire'
                      : accessStatus === 'pending' ? 'Demande d\'accès en attente'
                      : 'Accès refusé par le propriétaire'}
                  </p>
                )}
              </>
            ) : (
              <>
                <p style={{ margin: '0 0 8px', fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#9ca3af' }}>
                  Aucune fiche rattachée à ce séjour.
                </p>
                <button type="button" onClick={linkFiche} disabled={linkingFiche}
                  style={{ width: '100%', padding: '10px 0', borderRadius: 10, border: `1px solid ${GREEN}`,
                    background: 'transparent', color: GREEN, cursor: 'pointer',
                    fontFamily: 'Galey, sans-serif', fontSize: 13, fontWeight: 700 }}>
                  {linkingFiche ? 'Recherche…' : 'Rattacher une fiche (puce)'}
                </button>
              </>
            )}
          </div>
          <label style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 16, cursor: 'pointer' }}>
            <input type="checkbox" checked={form.seul_dans_logement}
              onChange={e => setForm(f => ({ ...f, seul_dans_logement: e.target.checked }))} />
            <span style={{ fontFamily: 'Galey, sans-serif', fontSize: 13, color: '#374151' }}>
              Animal doit être seul dans le logement
            </span>
          </label>

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
          <div style={{ marginBottom: 4 }}>
            <label style={lbl}>Adresse</label>
            <input style={inp} placeholder="Rue, code postal, ville" value={form.proprietaire_adresse}
              onChange={e => set('proprietaire_adresse', e.target.value)} />
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
          {isEdit && (
            <button type="button" onClick={deleteEntree} disabled={saving} style={{
              width: '100%', padding: '12px 0', background: 'transparent', color: '#dc2626',
              border: '1px solid #dc2626', borderRadius: 12, fontFamily: 'Galey, sans-serif',
              fontWeight: 600, fontSize: 14, cursor: saving ? 'not-allowed' : 'pointer',
              opacity: saving ? 0.7 : 1, marginTop: 10,
            }}>
              Supprimer le séjour (annulation)
            </button>
          )}
        </form>
      </div>
    </div>
  );
}
