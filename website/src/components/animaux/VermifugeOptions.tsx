'use client';

// Vermifuge du carnet : traitement sur plusieurs jours avec rappel à chaque
// prise (colonnes rappel_* + Cloud Function sendTraitementReminders) et
// saisie pour plusieurs animaux d'un coup. Miroir appli :
// lib/widgets/carnet/vermifuge_options.dart.

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';

export interface OptionsVermifuge { dureeJours: number; rappel: boolean; heures: string[]; autres: string[] }
export const optionsVermifugeVides = (): OptionsVermifuge => ({ dureeJours: 1, rappel: false, heures: [], autres: [] });

/** Colonnes « prises » à enregistrer sur la ligne vermifuges. */
export function colonnesPrises(o: OptionsVermifuge, date?: string): Record<string, unknown> {
  const rappel = o.rappel && o.heures.length > 0;
  const out: Record<string, unknown> = { duree_jours: o.dureeJours, rappel_actif: rappel };
  if (rappel) {
    out.rappel_frequence_jours = 1;
    out.rappel_duree_jours = o.dureeJours;
    out.rappel_heures = o.heures;
    if (date && /^\d{4}-\d{2}-\d{2}$/.test(date)) {
      const fin = new Date(`${date.slice(0, 10)}T12:00:00`);
      fin.setDate(fin.getDate() + o.dureeJours - 1);
      out.rappel_fin = fin.toISOString().slice(0, 10);
    }
  }
  return out;
}

export default function VermifugeOptions({ animalId, value, onChange, groupe = true, prises = true }: {
  animalId: string; value: OptionsVermifuge; onChange: (v: OptionsVermifuge) => void; groupe?: boolean;
  /** false : seulement « Appliquer aussi à » (ex. antiparasitaire). */
  prises?: boolean;
}) {
  const [heure, setHeure] = useState('08:00');
  const [animaux, setAnimaux] = useState<{ id: string; nom: string | null }[]>([]);
  const [ouvert, setOuvert] = useState(false);
  const [recherche, setRecherche] = useState('');

  // Autres animaux présents du même propriétaire (même profil, même espèce).
  useEffect(() => {
    if (!groupe) return;
    let annule = false;
    (async () => {
      const { data: moi } = await supabase.from('animaux_proprietes').select('profile_id_proprio, uid_proprio')
        .eq('animal_id', animalId).is('date_fin', null).limit(1).maybeSingle();
      const { data: animal } = await supabase.from('animaux').select('espece').eq('id', animalId).maybeSingle();
      if (!moi) return;
      const q = supabase.from('animaux_proprietes').select('animal_id').is('date_fin', null);
      const { data: liens } = await (moi.profile_id_proprio ? q.eq('profile_id_proprio', moi.profile_id_proprio) : q.eq('uid_proprio', moi.uid_proprio));
      const ids = [...new Set(((liens ?? []) as { animal_id: string }[]).map(l => String(l.animal_id)))].filter(x => x !== animalId);
      if (!ids.length) return;
      let qa = supabase.from('animaux').select('id, nom, espece, statut').in('id', ids);
      if (animal?.espece) qa = qa.eq('espece', animal.espece);
      const { data } = await qa.order('nom');
      if (!annule) setAnimaux(((data ?? []) as { id: string; nom: string | null; statut: string | null }[])
        .filter(a => !['sorti', 'decede'].includes(a.statut ?? '')));
    })();
    return () => { annule = true; };
  }, [animalId, groupe]);

  const maj = (p: Partial<OptionsVermifuge>) => onChange({ ...value, ...p });
  const cadre = 'rounded-xl border border-[#E4E7E2] bg-[#F8F8F6] p-3';
  const nbAutres = value.autres.length;

  return (
    <div className="space-y-3">
      {prises && <div className={cadre}>
        <div className="flex items-center gap-2 text-sm">
          <span className="font-semibold text-[#1F2A2E] flex-1">Durée du traitement</span>
          <input type="number" min={1} max={60} value={value.dureeJours}
            onChange={e => maj({ dureeJours: Math.min(60, Math.max(1, parseInt(e.target.value, 10) || 1)) })}
            className="w-16 border border-gray-200 rounded-lg px-2 py-1 text-sm text-center" />
          <span>{value.dureeJours > 1 ? 'jours' : 'jour'}</span>
        </div>
        <label className="flex items-center gap-2 text-sm mt-3 cursor-pointer">
          <input type="checkbox" checked={value.rappel} onChange={e => maj({ rappel: e.target.checked, heures: e.target.checked && value.heures.length === 0 && heure ? [heure] : value.heures })} className="accent-[#0C5C6C] w-4 h-4" />
          <span className="font-semibold text-[#1F2A2E]">Rappel à chaque prise</span>
        </label>
        {value.rappel && (
          <div className="mt-2">
            <p className="text-xs text-gray-500 mb-2">{value.dureeJours > 1 ? `Chaque jour pendant ${value.dureeJours} jours, aux heures suivantes :` : 'Le jour de la prise, à :'}</p>
            <div className="flex flex-wrap items-center gap-2">
              {value.heures.map(h => (
                <span key={h} className="inline-flex items-center gap-1 text-xs bg-[#6E9E57]/15 text-[#3D6B2E] rounded-full px-2 py-1">
                  {h}<button type="button" onClick={() => maj({ heures: value.heures.filter(x => x !== h) })} aria-label={`Retirer ${h}`}>✕</button>
                </span>
              ))}
              <input type="time" value={heure} onChange={e => setHeure(e.target.value)} className="border border-gray-200 rounded-lg px-2 py-1 text-xs" />
              <button type="button" onClick={() => heure && !value.heures.includes(heure) && maj({ heures: [...value.heures, heure].sort() })}
                className="text-xs font-semibold text-[#0C5C6C]">+ Ajouter</button>
            </div>
          </div>
        )}
      </div>}

      {groupe && animaux.length > 0 && (
        <div className="relative">
          <label className="block text-xs font-semibold text-gray-500 mb-1">Appliquer aussi à</label>
          <button type="button" onClick={() => setOuvert(v => !v)}
            className="w-full flex items-center gap-2 border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white text-left">
            <span className={`flex-1 truncate ${nbAutres ? 'text-[#1F2A2E]' : 'text-gray-400'}`}>
              {nbAutres === 0 ? 'Aucun autre animal'
                : `${nbAutres} ${nbAutres > 1 ? 'autres animaux' : 'autre animal'} : ${animaux.filter(a => value.autres.includes(a.id)).map(a => a.nom ?? 'Animal').join(', ')}`}
            </span>
            <span className="text-gray-400">{ouvert ? '▴' : '▾'}</span>
          </button>
          {ouvert && (
            <div className="absolute z-20 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg">
              <div className="p-2 border-b border-gray-100">
                <input value={recherche} onChange={e => setRecherche(e.target.value)} placeholder="Rechercher un animal"
                  className="w-full border border-gray-200 rounded-lg px-3 py-1.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              {(() => {
                const q = recherche.trim().toLowerCase();
                const liste = q ? animaux.filter(a => (a.nom ?? '').toLowerCase().includes(q)) : animaux;
                const tous = liste.length > 0 && liste.every(a => value.autres.includes(a.id));
                return (
                  <div className="max-h-64 overflow-y-auto py-1">
                    <label className="flex items-center gap-2 px-3 py-2 text-sm font-semibold text-[#1F2A2E] hover:bg-gray-50 cursor-pointer">
                      <input type="checkbox" checked={tous} className="accent-[#6E9E57] w-4 h-4"
                        onChange={e => maj({ autres: e.target.checked
                          ? [...new Set([...value.autres, ...liste.map(a => a.id)])]
                          : value.autres.filter(x => !liste.some(a => a.id === x)) })} />
                      {q ? 'Sélectionner les résultats' : 'Tout sélectionner'}
                    </label>
                    {liste.map(a => (
                      <label key={a.id} className="flex items-center gap-2 px-3 py-2 text-sm text-[#1F2A2E] hover:bg-gray-50 cursor-pointer">
                        <input type="checkbox" checked={value.autres.includes(a.id)} className="accent-[#6E9E57] w-4 h-4"
                          onChange={e => maj({ autres: e.target.checked ? [...value.autres, a.id] : value.autres.filter(x => x !== a.id) })} />
                        {a.nom ?? 'Animal'}
                      </label>
                    ))}
                    {liste.length === 0 && <p className="px-3 py-3 text-sm text-gray-400">Aucun animal trouvé.</p>}
                  </div>
                );
              })()}
              <div className="p-2 border-t border-gray-100 text-right">
                <button type="button" onClick={() => setOuvert(false)} className="text-sm font-semibold text-[#0C5C6C] px-2">Valider</button>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
