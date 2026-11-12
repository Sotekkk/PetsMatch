'use client';
// Accueil éleveur : soin d'un protocole pour plusieurs animaux le même jour,
// validé en une fois — animaux cochés (à décocher si besoin), inscription au
// carnet et au registre cochée d'office. Même enregistrement que le planning du
// jour (validerTachesProtocole). Miroir appli : _ValiderSoinsSheet (eleveur_dashboard.dart).
import { useState } from 'react';
import { validerTachesProtocole, type TacheSanitaire } from '@/lib/carnet-depuis-tache';
import { useAuth } from '@/lib/auth-context';
import { moiIntervenant } from '@/lib/registre-source';

export type TacheProtocole = TacheSanitaire & { uid_eleveur?: string | null; animal_nom?: string | null };

export default function ValiderSoinsProtocoleModal({ titre, taches, uid, profileId, onClose, onValidated }: {
  titre: string; taches: TacheProtocole[]; uid: string; profileId: string | null;
  onClose: () => void; onValidated: () => void;
}) {
  const [selected, setSelected] = useState<Record<string, boolean>>(() => Object.fromEntries(taches.map(t => [t.id, true])));
  const { userData } = useAuth();
  const [inscrire, setInscrire] = useState(true);
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);
  const [erreur, setErreur] = useState('');
  const nb = taches.filter(t => selected[t.id]).length;

  async function valider() {
    setSaving(true); setErreur('');
    try {
      await validerTachesProtocole(taches.filter(t => selected[t.id]), { uid, profileId, notes, inscrire, intervenant: moiIntervenant(userData) });
      onValidated();
    } catch (e) {
      setErreur(`Validation impossible : ${(e as Error).message}`);
      setSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-md p-5 space-y-4 max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}
        style={{ fontFamily: 'Galey, sans-serif' }}>
        <div>
          <h2 className="text-lg font-bold text-[#1E2025]">{titre}</h2>
          <p className="text-sm text-gray-500">Protocole · {taches.length} animal{taches.length > 1 ? 'aux' : ''}</p>
        </div>
        <div className="space-y-1">
          {taches.length > 1 && (
            <div className="flex justify-end">
              <button type="button" className="text-xs font-semibold text-[#0C5C6C] hover:underline"
                onClick={() => { const tous = taches.every(t => selected[t.id]); setSelected(Object.fromEntries(taches.map(t => [t.id, !tous]))); }}>
                {taches.every(t => selected[t.id]) ? 'Tout désélectionner' : 'Tout sélectionner'}
              </button>
            </div>
          )}
          {taches.map(t => (
            <label key={t.id} className="flex items-center gap-3 p-2 rounded-xl hover:bg-gray-50 cursor-pointer">
              <input type="checkbox" checked={!!selected[t.id]} className="w-4 h-4 accent-[#0C5C6C]"
                onChange={e => setSelected(s => ({ ...s, [t.id]: e.target.checked }))} />
              <span className="text-sm font-semibold text-[#1E2025]">{t.animal_nom || 'Animal'}</span>
            </label>
          ))}
        </div>
        <label className="flex items-start gap-2 text-sm text-gray-700 cursor-pointer">
          <input type="checkbox" checked={inscrire} onChange={e => setInscrire(e.target.checked)} className="mt-0.5 w-4 h-4 accent-[#0C5C6C]" />
          <span>Inscrire dans le carnet de santé et le registre sanitaire de chaque animal</span>
        </label>
        <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} placeholder="Notes (optionnel)"
          className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
        {erreur && <p className="text-sm text-red-700 bg-red-50 rounded-xl px-3 py-2">{erreur}</p>}
        <div className="flex gap-3">
          <button type="button" onClick={onClose} className="flex-1 py-2.5 border border-gray-200 rounded-xl text-sm font-semibold text-gray-600">Annuler</button>
          <button type="button" onClick={valider} disabled={saving || nb === 0}
            className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white bg-[#0C5C6C] disabled:opacity-50">
            {saving ? 'Enregistrement…' : `Valider pour ${nb} animal${nb > 1 ? 'aux' : ''}`}
          </button>
        </div>
      </div>
    </div>
  );
}
