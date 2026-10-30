'use client';

// Race d'un animal : liste déroulante des races de l'espèce quand elle existe
// (public/breeds/*.json), « Autre race » pour saisir librement ; champ libre
// pour les espèces sans liste. Miroir appli : ChampRace (lib/widgets/champ_race.dart).
import { useEffect, useState } from 'react';

const FICHIERS: Record<string, string> = {
  chien: 'dog_breeds', chat: 'cat_breeds', cheval: 'horse_breeds', lapin: 'rabbit_breeds', nac: 'nac_breeds',
  oiseau: 'bird_breeds', ovin: 'sheep_breeds', caprin: 'goat_breeds', porcin: 'pig_breeds',
};
const AUTRE = '__autre__';

export default function ChampRace({ espece, value, onChange, className }: {
  espece: string; value: string; onChange: (race: string) => void; className?: string;
}) {
  const [races, setRaces] = useState<string[]>([]);
  const [libre, setLibre] = useState(false);

  useEffect(() => {
    const f = FICHIERS[espece];
    let annule = false;
    if (!f) { setRaces([]); return; }
    fetch(`/breeds/${f}.json`).then(r => r.json()).then((d: string[]) => { if (!annule) setRaces(Array.isArray(d) ? d : []); })
      .catch(() => { if (!annule) setRaces([]); });
    return () => { annule = true; };
  }, [espece]);

  if (races.length === 0 || libre || (value && !races.includes(value))) {
    return (
      <div className="flex gap-2">
        <input value={value} onChange={e => onChange(e.target.value)} placeholder="Race" className={`${className ?? ''} flex-1`} />
        {races.length > 0 && (
          <button type="button" onClick={() => { setLibre(false); onChange(''); }} className="text-xs font-semibold text-[#0C5C6C] whitespace-nowrap">
            Liste
          </button>
        )}
      </div>
    );
  }
  return (
    <select value={value} onChange={e => { if (e.target.value === AUTRE) { setLibre(true); onChange(''); } else onChange(e.target.value); }}
      className={`${className ?? ''} bg-white`}>
      <option value="">Race —</option>
      {races.map(r => <option key={r} value={r}>{r}</option>)}
      <option value={AUTRE}>Autre race (saisir)</option>
    </select>
  );
}
