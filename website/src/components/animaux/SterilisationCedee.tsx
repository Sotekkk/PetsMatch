'use client';
// Condition de stérilisation d'un animal cédé (vue élevage) : exigée ou non,
// échéance, confirmée. Alimente l'onglet « Suivi » des cessions et ses
// rappels (J-30, J-7, J-48 h, J-0). Miroir appli :
// animal_fiche.dart (_editerSterilisation).
import { useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface AnimalSteril {
  id?: string; date_naissance?: string | null;
  sterilisation_requise?: boolean | null; sterilisation_echeance?: string | null; sterilisation_validee?: boolean | null;
}

export function SterilisationCedee({ animal, profileId, modifiable, onChange }: {
  animal: AnimalSteril; profileId: string | null; modifiable: boolean;
  onChange: (v: Partial<AnimalSteril>) => void;
}) {
  const { user } = useAuth();
  const [edit, setEdit] = useState(false);
  const echeanceDefaut = () => {
    if (animal.date_naissance) {
      const d = new Date(animal.date_naissance);
      return `${d.getFullYear() + 1}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    }
    return '';
  };
  const [requise, setRequise] = useState(!!animal.sterilisation_requise);
  const [echeance, setEcheance] = useState((animal.sterilisation_echeance ?? '').slice(0, 10) || echeanceDefaut());
  const [validee, setValidee] = useState(!!animal.sterilisation_validee);
  const [erreur, setErreur] = useState('');

  const libelle = !animal.sterilisation_requise ? 'Aucune condition de stérilisation'
    : animal.sterilisation_validee ? 'Stérilisation confirmée'
    : `Stérilisation exigée${animal.sterilisation_echeance ? ` avant le ${new Date(animal.sterilisation_echeance).toLocaleDateString('fr-FR')}` : ''}`;

  async function enregistrer() {
    if (!animal.id || !user) return;
    const v = {
      sterilisation_requise: requise,
      sterilisation_echeance: requise && echeance ? echeance : null,
      sterilisation_validee: requise && validee,
      sterilisation_eleveur_uid: requise ? user.uid : null,
      ...(requise && profileId ? { sterilisation_eleveur_profile_id: profileId } : {}),
    };
    const { error } = await supabase.from('animaux').update(v).eq('id', animal.id);
    if (error) { setErreur(error.message); return; }
    onChange(v); setEdit(false); setErreur('');
  }

  return (
    <div className="mt-2 pt-2 border-t border-blue-200">
      {!edit ? (
        <p className="text-xs text-blue-800 flex items-center gap-2">
          <span className="flex-1">{libelle}</span>
          {modifiable && <button onClick={() => setEdit(true)} className="font-semibold underline">Modifier</button>}
        </p>
      ) : (
        <div className="space-y-2 text-xs text-blue-900">
          <label className="flex items-center gap-2"><input type="checkbox" checked={requise} onChange={e => setRequise(e.target.checked)} />Stérilisation exigée</label>
          {requise && (
            <>
              <label className="flex items-center gap-2">Échéance
                <input type="date" value={echeance} onChange={e => setEcheance(e.target.value)} className="border border-blue-200 rounded px-2 py-1 bg-white" />
              </label>
              <label className="flex items-center gap-2"><input type="checkbox" checked={validee} onChange={e => setValidee(e.target.checked)} />Stérilisation confirmée</label>
            </>
          )}
          <p className="text-[11px] text-blue-600">Le suivi apparaît dans l&apos;onglet « Suivi » de vos animaux, avec des rappels avant l&apos;échéance.</p>
          {erreur && <p className="text-red-600">{erreur}</p>}
          <div className="flex gap-2">
            <button onClick={() => setEdit(false)} className="px-3 py-1 rounded-lg border border-blue-200 bg-white">Annuler</button>
            <button onClick={enregistrer} className="px-3 py-1 rounded-lg text-white" style={{ background: '#1565C0' }}>Enregistrer</button>
          </div>
        </div>
      )}
    </div>
  );
}
