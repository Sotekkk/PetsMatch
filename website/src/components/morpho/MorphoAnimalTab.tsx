'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { TEAL, labelTypeSuivi, morphoSpeciesSupported } from '@/lib/morpho';

interface SuiviRow { id: string; date: string; type_suivi: string }

/// Onglet "Morphologie" embarqué dans la fiche patient (mes-patients/[id]) —
/// liste les suivis morphologiques de CET animal, création rapide.
export default function MorphoAnimalTab({ animalId, espece }: { animalId: string; espece: string }) {
  const [loading, setLoading] = useState(true);
  const [suivis, setSuivis] = useState<SuiviRow[]>([]);

  useEffect(() => {
    let active = true;
    supabase.from('suivis_morpho').select('id, date, type_suivi').eq('animal_id', animalId)
      .order('date', { ascending: false }).then(({ data }) => {
        if (active) { setSuivis((data ?? []) as SuiviRow[]); setLoading(false); }
      });
    return () => { active = false; };
  }, [animalId]);

  if (!morphoSpeciesSupported(espece)) {
    return <p className="text-sm text-gray-400 font-galey py-8 text-center">Le suivi morphologique est disponible pour chien, chat et cheval.</p>;
  }

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h3 className="text-sm font-bold font-galey text-gray-800">Suivi morphologique &amp; bien-être</h3>
        <a href={`/sante/suivis/nouveau?animalId=${animalId}&espece=${encodeURIComponent(espece)}`}
          className="text-white px-3 py-1.5 rounded-full text-xs font-galey font-semibold" style={{ background: TEAL }}>
          + Nouveau suivi
        </a>
      </div>
      {loading ? (
        <div className="flex justify-center py-8"><div className="animate-spin rounded-full h-8 w-8 border-b-2" style={{ borderColor: TEAL }} /></div>
      ) : suivis.length === 0 ? (
        <p className="text-sm text-gray-400 font-galey py-8 text-center">Aucun suivi pour l&apos;instant.</p>
      ) : (
        <div className="space-y-2">
          {suivis.map(s => (
            <a key={s.id} href={`/sante/suivis/${s.id}`}
              className="block bg-white rounded-xl border border-gray-100 p-3 hover:border-teal-200 transition-colors">
              <p className="text-sm font-bold font-galey text-gray-900">{labelTypeSuivi(s.type_suivi)}</p>
              <p className="text-xs text-gray-500 font-galey">{new Date(s.date).toLocaleDateString('fr-FR')}</p>
            </a>
          ))}
        </div>
      )}
    </div>
  );
}
