'use client';

import { useState, useRef, useEffect } from 'react';

interface Suggestion {
  label: string;
  lat: number;
  lon: number;
}

interface Props {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
  className?: string;
}

/**
 * Autocomplete d'adresse française via api-adresse.data.gouv.fr (gratuit, sans clé).
 * Affiche une mini-carte OpenStreetMap après sélection.
 */
export default function AddressAutocomplete({ value, onChange, placeholder, className }: Props) {
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const [open, setOpen] = useState(false);
  const [coords, setCoords] = useState<{ lat: number; lon: number } | null>(null);
  const debounce = useRef<ReturnType<typeof setTimeout> | null>(null);
  const prevValue = useRef(value);

  // Efface la carte si la valeur est vidée depuis le parent
  useEffect(() => {
    if (!value && prevValue.current) {
      setCoords(null);
      setSuggestions([]);
    }
    prevValue.current = value;
  }, [value]);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const v = e.target.value;
    onChange(v);
    setCoords(null);
    if (debounce.current) clearTimeout(debounce.current);
    if (v.trim().length < 3) { setSuggestions([]); setOpen(false); return; }
    debounce.current = setTimeout(async () => {
      try {
        const res = await fetch(
          `https://api-adresse.data.gouv.fr/search/?q=${encodeURIComponent(v)}&limit=5`
        );
        const json = await res.json();
        const list: Suggestion[] = (json.features ?? []).map(
          (f: { properties: { label: string }; geometry: { coordinates: [number, number] } }) => ({
            label: f.properties.label,
            lon: f.geometry.coordinates[0],
            lat: f.geometry.coordinates[1],
          })
        );
        setSuggestions(list);
        setOpen(list.length > 0);
      } catch { /* réseau indisponible, on ignore */ }
    }, 350);
  };

  const select = (s: Suggestion) => {
    onChange(s.label);
    setCoords({ lat: s.lat, lon: s.lon });
    setSuggestions([]);
    setOpen(false);
  };

  const mapSrc = coords
    ? `https://www.openstreetmap.org/export/embed.html?bbox=${coords.lon - 0.008},${coords.lat - 0.005},${coords.lon + 0.008},${coords.lat + 0.005}&layer=mapnik&marker=${coords.lat},${coords.lon}`
    : null;

  return (
    <div className="relative">
      <input
        value={value}
        onChange={handleChange}
        onFocus={() => suggestions.length > 0 && setOpen(true)}
        onBlur={() => setTimeout(() => setOpen(false), 200)}
        placeholder={placeholder ?? 'Commencez à taper une adresse…'}
        className={className}
        autoComplete="off"
      />

      {open && suggestions.length > 0 && (
        <ul className="absolute z-50 w-full mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
          {suggestions.map((s, i) => (
            <li
              key={i}
              onMouseDown={() => select(s)}
              className="flex items-center gap-2 px-3 py-2.5 text-sm text-gray-700 cursor-pointer hover:bg-teal-50 hover:text-teal-800 border-b border-gray-50 last:border-0"
            >
              <span className="text-gray-400 flex-shrink-0">📍</span>
              {s.label}
            </li>
          ))}
        </ul>
      )}

      {mapSrc && (
        <div className="mt-2 rounded-xl overflow-hidden border border-gray-200" style={{ height: 140 }}>
          <iframe
            src={mapSrc}
            width="100%"
            height="100%"
            style={{ border: 0 }}
            title="Localisation"
          />
        </div>
      )}
    </div>
  );
}
