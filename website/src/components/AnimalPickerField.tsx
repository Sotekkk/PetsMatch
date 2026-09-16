'use client';

import { useMemo, useState } from 'react';

// Sélecteur d'animal (champ + modale avec recherche et photo) — miroir de
// AnimalPickerSheet/AnimalPickerField (app, lib/widgets/animal_picker_sheet.dart).
// Remplace le rendu en chips/emoji (illisible dès qu'on a beaucoup d'animaux).

export interface PickableAnimal {
  id: number | string;
  nom: string;
  espece: string;
  race?: string | null;
  photo_url?: string | null;
}

function AnimalThumb({ animal, size = 44 }: { animal: PickableAnimal; size?: number }) {
  const [broken, setBroken] = useState(false);
  const photo = animal.photo_url;
  return (
    <div
      className="flex items-center justify-center overflow-hidden shrink-0"
      style={{ width: size, height: size, borderRadius: size >= 40 ? 10 : 6, backgroundColor: '#EEF5EA' }}
    >
      {photo && !broken ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={photo} alt="" width={size} height={size} className="object-cover w-full h-full" onError={() => setBroken(true)} />
      ) : (
        <span style={{ fontSize: size >= 40 ? 16 : 12 }}>🐾</span>
      )}
    </div>
  );
}

interface FieldProps {
  animaux: PickableAnimal[];
  selectedId: number | string | null;
  onSelect: (id: number | string | null) => void;
  accentColor: string;
  placeholder?: string;
}

export function AnimalPickerField({ animaux, selectedId, onSelect, accentColor, placeholder = 'Choisir un animal…' }: FieldProps) {
  const [open, setOpen] = useState(false);
  const selected = animaux.find(a => a.id === selectedId) ?? null;

  return (
    <>
      <button type="button" onClick={() => setOpen(true)}
        className="w-full flex items-center gap-2.5 px-3.5 py-2.5 rounded-xl border bg-white text-left"
        style={{ borderColor: '#D1D5DB' }}>
        {selected ? (
          <>
            <AnimalThumb animal={selected} size={32} />
            <span className="flex-1 text-sm font-semibold" style={{ fontFamily: 'Galey, sans-serif', color: accentColor }}>
              {selected.nom}
            </span>
          </>
        ) : (
          <span className="flex-1 text-sm" style={{ fontFamily: 'Galey, sans-serif', color: '#9CA3AF' }}>{placeholder}</span>
        )}
        <span className="text-gray-400">⌄</span>
      </button>
      {open && (
        <AnimalPickerModal
          animaux={animaux}
          currentId={selectedId}
          accentColor={accentColor}
          onClose={() => setOpen(false)}
          onPick={(id) => { onSelect(id); setOpen(false); }}
        />
      )}
    </>
  );
}

interface ModalProps {
  animaux: PickableAnimal[];
  currentId: number | string | null;
  accentColor: string;
  onClose: () => void;
  onPick: (id: number | string) => void;
}

function AnimalPickerModal({ animaux, currentId, accentColor, onClose, onPick }: ModalProps) {
  const [query, setQuery] = useState('');
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return animaux;
    return animaux.filter(a => a.nom.toLowerCase().includes(q));
  }, [animaux, query]);

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40" onClick={onClose}>
      <div className="w-full sm:max-w-md bg-white rounded-t-3xl sm:rounded-2xl max-h-[75vh] flex flex-col"
        onClick={e => e.stopPropagation()}>
        <div className="flex items-center px-2 py-3 border-b border-gray-100">
          <button onClick={onClose} className="p-2 text-gray-700" aria-label="Fermer">←</button>
          <p className="flex-1 text-center text-[15px] font-bold" style={{ fontFamily: 'Galey, sans-serif', color: '#1F2A2E' }}>
            Sélectionner un animal
          </p>
          <span className="w-9" />
        </div>
        {animaux.length > 5 && (
          <div className="px-3.5 pt-2.5 pb-1.5">
            <input value={query} onChange={e => setQuery(e.target.value)} autoFocus
              placeholder="Rechercher un animal…"
              className="w-full px-3.5 py-2.5 rounded-xl text-sm bg-gray-100"
              style={{ fontFamily: 'Galey, sans-serif' }} />
          </div>
        )}
        <div className="flex-1 overflow-y-auto">
          {filtered.length === 0 ? (
            <p className="text-center text-sm text-gray-400 py-8" style={{ fontFamily: 'Galey, sans-serif' }}>
              Aucun animal pour « {query} »
            </p>
          ) : (
            filtered.map(a => {
              const selected = a.id === currentId;
              return (
                <button key={a.id} onClick={() => onPick(a.id)}
                  className="w-full flex items-center gap-3 px-3.5 py-2.5 border-b border-gray-50 text-left"
                  style={{ backgroundColor: selected ? `${accentColor}1F` : 'transparent' }}>
                  <AnimalThumb animal={a} />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold truncate"
                      style={{ fontFamily: 'Galey, sans-serif', color: selected ? accentColor : '#1F2A2E' }}>
                      {a.nom}
                    </p>
                    <p className="text-xs text-gray-400 truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
                      {[a.espece, a.race].filter(Boolean).join(' · ')}
                    </p>
                  </div>
                  <span style={{ color: accentColor }}>›</span>
                </button>
              );
            })
          )}
        </div>
        <div style={{ height: 'env(safe-area-inset-bottom, 12px)' }} />
      </div>
    </div>
  );
}
