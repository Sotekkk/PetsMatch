'use client';

import { useCallback, useState } from 'react';
import { supabase } from '@/lib/supabase';

export interface SoinAnimal {
  id: string;
  nom?: string | null;
  espece?: string | null;
  sexe?: string | null;
  date_naissance?: string | null;
  identification?: string | null;
}

const ACTE_TYPES = [
  { value: 'vermifuge',       label: 'Vermifuge',          emoji: '🐛' },
  { value: 'vaccination',     label: 'Vaccination',         emoji: '💉' },
  { value: 'antiparasitaire', label: 'Antiparasitaire',     emoji: '🛡️' },
  { value: 'traitement',      label: 'Traitement',          emoji: '💊' },
  { value: 'visite',          label: 'Visite vétérinaire',  emoji: '🏥' },
  { value: 'osteopathie',     label: 'Ostéopathie',         emoji: '🤲' },
  { value: 'chirurgie',       label: 'Chirurgie',           emoji: '🔬' },
  { value: 'autre',           label: 'Autre',               emoji: '📋' },
];

// Modal « Soin portée » — un même acte de santé appliqué à plusieurs animaux
// d'une portée. `uid` / `activeProfileId` = l'élevage propriétaire (éleveur ou
// employeur pour un employé).
export default function PorteeSoinModal({ animals, uid, activeProfileId, onClose }: {
  animals: SoinAnimal[];
  uid: string;
  activeProfileId: string | null;
  onClose: () => void;
}) {
  const [typeActe, setTypeActe]       = useState('vermifuge');
  const [date, setDate]               = useState(new Date().toISOString().slice(0, 10));
  const [description, setDescription] = useState('');
  const [intervenant, setIntervenant] = useState('');
  const [ordonnance, setOrdonnance]   = useState('');
  const [dosage, setDosage]           = useState('');
  const [notes, setNotes]             = useState('');
  const [saving, setSaving]           = useState(false);
  const [saved, setSaved]             = useState(false);
  const [error, setError]             = useState('');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(() => new Set(animals.map(a => a.id)));

  const toggleAnimal = useCallback((id: string) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }, []);

  const handleSave = useCallback(async () => {
    if (!description.trim()) { setError('Le produit / la description est obligatoire.'); return; }
    if (selectedIds.size === 0) { setError('Sélectionnez au moins un animal.'); return; }
    setSaving(true); setError('');
    const dateIso = new Date(date).toISOString();
    const desc    = description.trim();
    const interv  = intervenant.trim();
    let success = 0;
    for (const animal of animals.filter(a => selectedIds.has(a.id))) {
      try {
        const entryId = `${Date.now()}_${animal.id}`;
        const n = notes.trim();
        if (typeActe === 'vermifuge') {
          await supabase.from('vermifuges').insert({
            id: entryId, animal_id: animal.id,
            produit: desc, date: dateIso, source: 'owner',
            ...(dosage.trim() ? { dosage: dosage.trim() } : {}),
            ...(n ? { notes: n } : {}),
          });
        } else if (typeActe === 'vaccination') {
          await supabase.from('vaccinations').insert({
            id: entryId, animal_id: animal.id,
            vaccin: desc, veterinaire: interv, date: dateIso, source: 'owner',
          });
        } else if (typeActe === 'antiparasitaire') {
          await supabase.from('antiparasitaires').insert({
            id: entryId, animal_id: animal.id,
            produit: desc, type: 'autre', date: dateIso, source: 'owner',
            ...(dosage.trim() ? { frequence: dosage.trim() } : {}),
            ...(n ? { notes: n } : {}),
          });
        } else if (typeActe === 'visite' || typeActe === 'osteopathie') {
          await supabase.from('visites').insert({
            id: entryId, animal_id: animal.id,
            motif: typeActe === 'osteopathie' ? 'Autre' : 'Consultation',
            veterinaire: interv, date: dateIso,
            diagnostic: typeActe === 'osteopathie' ? `Ostéopathie — ${desc}` : desc,
            ...(n ? { notes: n } : {}),
            source: 'owner',
          });
        } else {
          await supabase.from('traitements').insert({
            id: entryId, animal_id: animal.id,
            nom: desc, type: typeActe === 'chirurgie' ? 'autre' : 'medicament',
            date: dateIso, source: 'owner',
          });
        }
        await supabase.from('registre_sanitaire').insert({
          id:          `rs_${entryId}`,
          uid_eleveur: uid,
          ...(activeProfileId ? { eleveur_profile_id: activeProfileId } : {}),
          animal_id:   animal.id,
          animal_nom:  animal.nom ?? '',
          espece:      animal.espece ?? '',
          date_naissance: animal.date_naissance ?? null,
          identification: animal.identification ?? '',
          sexe:           animal.sexe ?? '',
          date_acte:      dateIso,
          type_acte:      typeActe,
          intervenant:    interv,
          description:    desc,
          ordonnance_num: ordonnance.trim(),
        });
        success++;
      } catch { /* continue */ }
    }
    setSaving(false);
    if (success > 0) { setSaved(true); setTimeout(onClose, 1200); }
    else setError('Erreur lors de l\'enregistrement. Vérifiez votre connexion.');
  }, [animals, uid, activeProfileId, typeActe, date, description, dosage, notes, intervenant, ordonnance, onClose, selectedIds]);

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 p-4">
      <div className="bg-white rounded-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto">
        <div className="p-5">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-xl bg-[#FFF8E1] flex items-center justify-center text-xl">💊</div>
            <div className="flex-1">
              <p className="font-bold text-[#1F2A2E] text-base" style={{ fontFamily: 'Galey, sans-serif' }}>Soin pour la portée</p>
              <p className="text-xs text-[#6E9E57]">{selectedIds.size}/{animals.length} animal{animals.length > 1 ? 'aux' : ''} sélectionné{selectedIds.size > 1 ? 's' : ''}</p>
            </div>
            <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl leading-none">✕</button>
          </div>

          <div className="flex flex-wrap gap-1.5 mb-1">
            {animals.map(a => {
              const sel = selectedIds.has(a.id);
              return (
                <button key={a.id} onClick={() => toggleAnimal(a.id)}
                  className={`flex items-center gap-1 text-xs font-medium px-2 py-0.5 rounded-lg border transition-all ${
                    sel
                      ? 'bg-[#0C5C6C12] text-[#0C5C6C] border-[#0C5C6C40]'
                      : 'bg-gray-100 text-gray-400 border-gray-200 line-through'
                  }`}
                  style={{ fontFamily: 'Galey, sans-serif' }}>
                  {a.nom ?? '?'}
                  {!sel && <span className="text-gray-300 text-[10px]">✕</span>}
                </button>
              );
            })}
          </div>
          <p className="text-[10px] text-gray-400 mb-4">Touchez un animal pour le retirer du soin</p>

          <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-2">Type de soin</p>
          <div className="flex flex-wrap gap-2 mb-4">
            {ACTE_TYPES.map(t => (
              <button key={t.value}
                className={`flex items-center gap-1 text-xs font-semibold px-3 py-1.5 rounded-lg border transition-colors ${
                  typeActe === t.value
                    ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]'
                    : 'bg-gray-50 text-gray-700 border-gray-200 hover:border-[#0C5C6C]'
                }`}
                style={{ fontFamily: 'Galey, sans-serif' }}
                onClick={() => { setTypeActe(t.value); setDosage(''); }}>
                {t.emoji} {t.label}
              </button>
            ))}
          </div>

          <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">Date du soin</p>
          <input type="date" value={date} onChange={e => setDate(e.target.value)}
            max={new Date().toISOString().slice(0, 10)}
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm mb-4 focus:outline-none focus:border-[#0C5C6C]"
            style={{ fontFamily: 'Galey, sans-serif' }} />

          <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">Produit / description *</p>
          <textarea value={description} onChange={e => setDescription(e.target.value)} rows={2}
            placeholder="Ex : Milbemax® 1 comprimé par chiot de 0,5 kg à 10 kg"
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm mb-4 resize-none focus:outline-none focus:border-[#0C5C6C]"
            style={{ fontFamily: 'Galey, sans-serif' }} />

          {(typeActe === 'vermifuge' || typeActe === 'antiparasitaire') && (
            <>
              <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">
                {typeActe === 'antiparasitaire' ? 'Fréquence (optionnel)' : 'Dosage (optionnel)'}
              </p>
              <input value={dosage} onChange={e => setDosage(e.target.value)}
                placeholder={typeActe === 'antiparasitaire' ? 'Ex : 1 mois' : 'Ex : 1 cp / 5 kg'}
                className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm mb-4 focus:outline-none focus:border-[#0C5C6C]"
                style={{ fontFamily: 'Galey, sans-serif' }} />
            </>
          )}

          <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">Administré par (optionnel)</p>
          <input value={intervenant} onChange={e => setIntervenant(e.target.value)}
            placeholder="Éleveur, Dr. Dupont, …"
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm mb-4 focus:outline-none focus:border-[#0C5C6C]"
            style={{ fontFamily: 'Galey, sans-serif' }} />

          <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">Notes (optionnel)</p>
          <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2}
            placeholder="Observations, réactions, …"
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm mb-4 resize-none focus:outline-none focus:border-[#0C5C6C]"
            style={{ fontFamily: 'Galey, sans-serif' }} />

          <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">N° ordonnance (optionnel)</p>
          <input value={ordonnance} onChange={e => setOrdonnance(e.target.value)}
            placeholder="ORD-2024-XXXXX"
            className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm mb-5 focus:outline-none focus:border-[#0C5C6C]"
            style={{ fontFamily: 'Galey, sans-serif' }} />

          {error && <p className="text-sm text-red-600 mb-3 bg-red-50 rounded-xl px-3 py-2">{error}</p>}
          {saved && <p className="text-sm text-[#6E9E57] mb-3 bg-[#EEF5EA] rounded-xl px-3 py-2 font-semibold">✓ {animals.length} enregistrement{animals.length > 1 ? 's' : ''} ajouté{animals.length > 1 ? 's' : ''} au registre</p>}

          <div className="flex gap-3">
            <button onClick={onClose}
              className="flex-1 border border-gray-200 text-gray-600 font-semibold py-3 rounded-xl text-sm hover:bg-gray-50 transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              Annuler
            </button>
            <button onClick={handleSave} disabled={saving || saved || selectedIds.size === 0}
              className="flex-1 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 disabled:cursor-not-allowed text-white font-semibold py-3 rounded-xl text-sm transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              {saving ? 'Enregistrement…' : `Enregistrer pour ${selectedIds.size} animal${selectedIds.size > 1 ? 'aux' : ''}`}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
