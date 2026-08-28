'use client';

import { useEffect, useMemo, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { lookupAnimalByChip, requestAnimalAccess } from '@/lib/pension-chip-lookup';
import { especeMatchesLogement } from '@/lib/pension-especes';

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

const TYPE_LABEL: Record<string, string> = {
  box: 'Box', enclos: 'Enclos', parc: 'Parc', chatterie: 'Chatterie', cage: 'Cage',
};

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
  owner_profile_id?: string;
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
  const [logementId, setLogementId] = useState<string | null>(entree?.logement_id ?? initialLogementId ?? null);
  const [logements, setLogements] = useState<{ id: string; nom: string; type: string; capacite: number; especes?: string[] | null }[]>([]);
  const [occupants, setOccupants] = useState<{
    id: string; logement_id: string | null; date_entree: string | null;
    date_sortie_prevue: string | null; date_sortie_effective: string | null;
  }[]>([]);
  const [linkingFiche, setLinkingFiche] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError]   = useState('');
  const [accessStatus, setAccessStatus] = useState<string | null | undefined>(undefined);
  const [checkingAccess, setCheckingAccess] = useState(false);
  const [topChip, setTopChip] = useState('');
  const [topSearching, setTopSearching] = useState(false);
  const [topNotFound, setTopNotFound] = useState(false);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const [{ data: log }, { data: occ }] = await Promise.all([
        supabase.from('enclos_chenil').select('id, nom, type, capacite, especes').eq('uid_eleveur', proUid).order('nom'),
        // tous les séjours pas encore sortis + assignés à un logement, avec
        // leurs dates → on calcule la dispo sur la période demandée.
        supabase.from('pension_entrees')
          .select('id, logement_id, date_entree, date_sortie_prevue, date_sortie_effective')
          .eq('pro_uid', proUid).neq('statut', 'sorti').not('logement_id', 'is', null),
      ]);
      if (cancelled) return;
      setLogements(log ?? []);
      setOccupants((occ ?? []) as typeof occupants);
    })();
    return () => { cancelled = true; };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [proUid]);

  // Occupation de chaque logement SUR LA PÉRIODE demandée (chevauchement de dates).
  const periodOccupancy = useMemo(() => {
    const reqStart = form.date_entree ? new Date(form.date_entree).getTime() : -8.64e15;
    const reqEnd = form.date_sortie_prevue ? new Date(form.date_sortie_prevue).getTime() : 8.64e15;
    const counts: Record<string, number> = {};
    for (const o of occupants) {
      if (!o.logement_id) continue;
      if (isEdit && entree && o.id === entree.id) continue;
      const oStart = o.date_entree ? new Date(o.date_entree).getTime() : -8.64e15;
      const oEnd = o.date_sortie_effective ? new Date(o.date_sortie_effective).getTime()
        : o.date_sortie_prevue ? new Date(o.date_sortie_prevue).getTime() : 8.64e15;
      if (oStart < reqEnd && oEnd > reqStart) counts[o.logement_id] = (counts[o.logement_id] ?? 0) + 1;
    }
    return counts;
  }, [occupants, form.date_entree, form.date_sortie_prevue, isEdit, entree]);

  async function searchTopChip() {
    if (!topChip.trim()) return;
    setTopSearching(true);
    setTopNotFound(false);
    try {
      const found = await lookupAnimalByChip(topChip.trim());
      if (!found.animal_id) { setTopNotFound(true); return; }
      setAnimalId(found.animal_id);
      setForm(f => ({
        ...f,
        animal_nom: found.animal_nom || f.animal_nom,
        espece: found.espece || f.espece,
        race: found.race || f.race,
        puce: found.puce || f.puce,
        proprietaire_nom: found.proprietaire_nom || f.proprietaire_nom,
        proprietaire_contact: found.proprietaire_contact || f.proprietaire_contact,
        proprietaire_email: found.proprietaire_email || f.proprietaire_email,
        proprietaire_adresse: found.proprietaire_adresse || f.proprietaire_adresse,
      }));
      if (found.owner_uid) {
        await requestAnimalAccess(found.animal_id, found.owner_uid, proUid, proProfileId,
          'Votre pension', found.animal_nom || 'cet animal', found.owner_profile_id);
        setAccessStatus('pending');
      }
    } finally {
      setTopSearching(false);
    }
  }

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
        .select('uid_proprio, profile_id_proprio').eq('animal_id', animalId).is('date_fin', null)
        .order('date_debut', { ascending: false }).limit(1).maybeSingle();
      const ownerUid = propRow?.uid_proprio;
      if (!ownerUid) {
        setError('Propriétaire introuvable pour cet animal.');
        return;
      }
      await requestAnimalAccess(animalId, ownerUid, proUid, proProfileId, 'Votre pension', form.animal_nom, propRow?.profile_id_proprio ?? null);
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
      if (!form.animal_nom.trim() && found.animal_nom) update.animal_nom = found.animal_nom;
      if (!form.espece.trim() && found.espece) update.espece = found.espece;
      if (!form.race.trim() && found.race) update.race = found.race;
      if (!form.puce.trim() && found.puce) update.puce = found.puce;
      if (!form.proprietaire_nom.trim() && found.proprietaire_nom) update.proprietaire_nom = found.proprietaire_nom;
      if (!form.proprietaire_contact.trim() && found.proprietaire_contact) update.proprietaire_contact = found.proprietaire_contact;
      if (!form.proprietaire_email.trim() && found.proprietaire_email) update.proprietaire_email = found.proprietaire_email;
      if (!form.proprietaire_adresse.trim() && found.proprietaire_adresse) update.proprietaire_adresse = found.proprietaire_adresse;
      if (!animalId && found.animal_id) update.animal_id = found.animal_id;
      if (Object.keys(update).length > 0 && isEdit && entree) {
        const { error: err } = await supabase.from('pension_entrees').update(update).eq('id', entree.id);
        if (err) { setError(`Échec de l'enregistrement : ${err.message}`); return; }
      }
      setForm(f => ({ ...f, ...update }));
      if (!animalId) setAnimalId(found.animal_id);
      // Demander/vérifier l'accès à la fiche, indépendamment des champs à compléter
      // (l'animal peut déjà être entièrement rempli et n'avoir jamais reçu de demande).
      if (found.owner_uid) {
        await requestAnimalAccess(found.animal_id, found.owner_uid, proUid, proProfileId,
          'Votre pension', form.animal_nom || entree?.animal_nom || 'cet animal', found.owner_profile_id);
        setAccessStatus('pending');
      }
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
        if (!entree.animal_nom?.trim() && found.animal_nom) update.animal_nom = found.animal_nom;
        if (!entree.espece?.trim() && found.espece) update.espece = found.espece;
        if (!entree.race?.trim() && found.race) update.race = found.race;
        if (!entree.puce?.trim() && found.puce) update.puce = found.puce;
        if (found.proprietaire_nom) update.proprietaire_nom = found.proprietaire_nom;
        if (found.proprietaire_contact) update.proprietaire_contact = found.proprietaire_contact;
        if (found.proprietaire_email) update.proprietaire_email = found.proprietaire_email;
        if (found.proprietaire_adresse) update.proprietaire_adresse = found.proprietaire_adresse;
        const { error: err } = await supabase.from('pension_entrees').update(update).eq('id', entree.id);
        if (err) { setError(`Échec de l'enregistrement : ${err.message}`); return; }
      }
      setAnimalId(found.animal_id);
      setForm(f => ({
        ...f,
        animal_nom: f.animal_nom.trim() || found.animal_nom || f.animal_nom,
        espece: f.espece.trim() || found.espece || f.espece,
        race: f.race.trim() || found.race || f.race,
        puce: f.puce.trim() || found.puce || f.puce,
        proprietaire_nom: found.proprietaire_nom || f.proprietaire_nom,
        proprietaire_contact: found.proprietaire_contact || f.proprietaire_contact,
        proprietaire_email: found.proprietaire_email || f.proprietaire_email,
        proprietaire_adresse: found.proprietaire_adresse || f.proprietaire_adresse,
      }));
      // Envoie la demande d'accès dès le rattachement, que ce soit une
      // nouvelle entrée ou une entrée existante — le propriétaire doit
      // valider avant tout accès à la fiche santé/alimentation.
      if (found.owner_uid) {
        await requestAnimalAccess(found.animal_id, found.owner_uid, proUid, proProfileId,
          'Votre pension', found.animal_nom || entree?.animal_nom || form.animal_nom || 'cet animal', found.owner_profile_id);
        setAccessStatus('pending');
      }
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

    // Un animal identifié (fiche rattachée) ne peut pas avoir deux séjours
    // en_pension aux dates qui se chevauchent — même pension (double
    // réservation) ou une autre (déjà constaté avec Clémentine).
    if (animalId && form.statut === 'en_pension') {
      const { data: autres } = await supabase.from('pension_entrees')
        .select('id, date_entree, date_sortie_prevue, date_sortie_effective')
        .eq('animal_id', animalId).eq('statut', 'en_pension')
        .neq('id', entree?.id ?? '00000000-0000-0000-0000-000000000000');
      const newStart = new Date(form.date_entree);
      const newEnd = form.date_sortie_prevue ? new Date(form.date_sortie_prevue) : new Date(2100, 0, 1);
      const conflit = (autres ?? []).find(a => {
        const aStart = new Date(a.date_entree);
        const aEnd = a.date_sortie_effective ? new Date(a.date_sortie_effective)
          : (a.date_sortie_prevue ? new Date(a.date_sortie_prevue) : new Date(2100, 0, 1));
        return newStart <= aEnd && aStart <= newEnd;
      });
      if (conflit) {
        setError(`${form.animal_nom.trim()} a déjà un séjour en pension sur ces dates. Vérifiez son autre réservation avant d'enregistrer celle-ci.`);
        setSaving(false);
        return;
      }
    }

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
      logement_id:          logementId,
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

        {!isEdit && (
          <div style={{
            background: 'rgba(12,92,108,0.06)', border: `1px solid rgba(12,92,108,0.25)`,
            borderRadius: 14, padding: 14, marginBottom: 20,
          }}>
            <p style={{ margin: '0 0 8px', fontFamily: 'Galey, sans-serif', fontSize: 12, fontWeight: 700, color: TEAL }}>
              🔑 CHERCHER PAR NUMÉRO DE PUCE
            </p>
            <p style={{ margin: '0 0 10px', fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#6b7280' }}>
              Retrouvez la fiche de l&apos;animal et pré-remplissez tout le formulaire — envoie automatiquement
              la demande d&apos;accès à la fiche santé/alimentation au propriétaire.
            </p>
            <div style={{ display: 'flex', gap: 8 }}>
              <input style={{ ...inp, background: 'white' }} placeholder="250 269 810 000 000"
                value={topChip} onChange={e => { setTopChip(e.target.value); setTopNotFound(false); }}
                onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); searchTopChip(); } }} />
              <button type="button" onClick={searchTopChip} disabled={topSearching || !topChip.trim()}
                style={{ padding: '0 18px', borderRadius: 8, border: 'none', background: TEAL, color: 'white',
                  fontFamily: 'Galey, sans-serif', fontSize: 13, fontWeight: 700,
                  cursor: topSearching || !topChip.trim() ? 'not-allowed' : 'pointer',
                  opacity: topSearching || !topChip.trim() ? 0.6 : 1, whiteSpace: 'nowrap' }}>
                {topSearching ? 'Recherche…' : 'Chercher'}
              </button>
            </div>
            {topNotFound && (
              <p style={{ margin: '8px 0 0', fontFamily: 'Galey, sans-serif', fontSize: 12, color: '#dc2626' }}>
                Aucun animal trouvé avec cette puce — vous pouvez continuer en saisie manuelle ci-dessous.
              </p>
            )}
            {animalId && (
              <p style={{ margin: '8px 0 0', fontFamily: 'Galey, sans-serif', fontSize: 12, color: GREEN, fontWeight: 600 }}>
                ✓ Fiche trouvée et pré-remplie — demande d&apos;accès envoyée au propriétaire.
              </p>
            )}
          </div>
        )}

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

          {/* Logement */}
          <p style={sec}>EMPLACEMENT</p>
          <div style={{ marginBottom: 16 }}>
            <label style={lbl}>Logement</label>
            <select style={inp} value={logementId ?? ''} onChange={e => setLogementId(e.target.value || null)}>
              <option value="">Non assigné</option>
              {[...logements]
                .map(l => {
                  const occ = periodOccupancy[l.id] ?? 0;
                  const libre = occ < l.capacite;
                  const compatible = especeMatchesLogement(form.espece, l.especes);
                  return { l, occ, libre, compatible };
                })
                .sort((a, b) => {
                  const rank = (x: typeof a) => (x.compatible ? 0 : 2) + (x.libre ? 0 : 1);
                  return rank(a) - rank(b) || a.l.nom.localeCompare(b.l.nom);
                })
                .map(({ l, occ, libre, compatible }) => {
                  const isCurrent = l.id === (entree?.logement_id ?? '');
                  const raison = !compatible ? ' · espèce non acceptée'
                    : !libre ? ' · complet sur la période' : '';
                  return (
                    <option key={l.id} value={l.id} disabled={(!compatible || !libre) && !isCurrent}>
                      {l.nom} ({TYPE_LABEL[l.type] ?? l.type}) — {occ}/{l.capacite} place{l.capacite > 1 ? 's' : ''}{raison}
                    </option>
                  );
                })}
            </select>
            <p style={{ margin: '6px 0 0', fontFamily: 'Galey, sans-serif', fontSize: 11.5, color: '#9ca3af' }}>
              {logements.length === 0
                ? <>Aucun logement créé — <Link href="/pension/chenil" style={{ color: TEAL }}>en créer un</Link>.</>
                : 'Seuls les logements de la bonne espèce et libres sur les dates du séjour sont sélectionnables.'}
            </p>
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
