'use client';

// Historique d'un patient, vue réservée au vétérinaire : tableau des
// consultations de la clinique (comptes rendus structurés —
// migration_cr_structure.sql) : date · motif · poids · actes · prescription ;
// le CR complet au clic. Miroir app : lib/pages/pro/historique_patient_page.dart.

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';

interface Cr {
  id: string; created_at: string; contenu: string | null;
  motif?: string | null; poids?: number | null; actes?: string[] | null; prescription?: string | null;
}

export default function HistoriquePatient({ animalId, animalNom, profileId, onClose }: {
  animalId: string; animalNom: string; profileId: string; onClose: () => void;
}) {
  const [crs, setCrs] = useState<Cr[] | null>(null);
  const [ouvert, setOuvert] = useState<Cr | null>(null);

  useEffect(() => {
    supabase.from('comptes_rendus').select('*').eq('animal_id', animalId).eq('pro_profile_id', profileId)
      .order('created_at', { ascending: false })
      .then(({ data }) => setCrs((data ?? []) as Cr[]));
  }, [animalId, profileId]);

  const date = (iso: string) => new Date(iso).toLocaleDateString('fr-FR');

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-4xl p-5 max-h-[90vh] overflow-y-auto"
        onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
        <div className="flex items-center mb-3">
          <h2 className="flex-1 font-bold text-lg text-[#1E2025]">🕘 Historique — {animalNom}</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl w-8 h-8">✕</button>
        </div>
        {crs === null ? (
          <div className="flex justify-center py-10"><div className="w-7 h-7 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>
        ) : crs.length === 0 ? (
          <p className="text-sm text-gray-400 py-8 text-center">Aucune consultation enregistrée pour ce patient.</p>
        ) : (
          <div className="overflow-x-auto border border-gray-100 rounded-xl">
            <table className="w-full text-sm">
              <thead className="bg-[#0C5C6C]/5 text-[#0C5C6C] text-xs">
                <tr>
                  <th className="text-left px-3 py-2">Date</th>
                  <th className="text-left px-3 py-2">Motif</th>
                  <th className="text-right px-3 py-2">Poids</th>
                  <th className="text-left px-3 py-2">Actes réalisés</th>
                  <th className="text-left px-3 py-2">Prescription</th>
                </tr>
              </thead>
              <tbody>
                {crs.map(c => (
                  <tr key={c.id} onClick={() => setOuvert(c)} className="border-t border-gray-100 hover:bg-gray-50 cursor-pointer align-top">
                    <td className="px-3 py-2 font-bold whitespace-nowrap">{date(c.created_at)}</td>
                    <td className="px-3 py-2">{c.motif || '—'}</td>
                    <td className="px-3 py-2 text-right whitespace-nowrap">{c.poids != null ? `${c.poids} kg` : '—'}</td>
                    <td className="px-3 py-2">{c.actes?.length ? c.actes.join(', ') : '—'}</td>
                    <td className="px-3 py-2">{c.prescription || '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {ouvert && (
          <div className="mt-4 rounded-xl border border-gray-200 p-4">
            <div className="flex items-center mb-2">
              <p className="flex-1 font-bold text-sm text-[#1E2025]">Consultation du {date(ouvert.created_at)}</p>
              <button onClick={() => setOuvert(null)} className="text-xs text-gray-400">Fermer</button>
            </div>
            <p className="text-sm text-[#1E2025] whitespace-pre-wrap">{ouvert.contenu}</p>
          </div>
        )}
      </div>
    </div>
  );
}
