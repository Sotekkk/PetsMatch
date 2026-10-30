'use client';
// Adresse vérifiée par Google Maps (autocomplétion Places) : la personne
// choisit une adresse proposée, on renvoie rue / ville / code postal / pays
// et les coordonnées. Même champ que l'inscription (extrait de
// app/inscription/page.tsx), réutilisé par la réservation éducateur.
import { useEffect, useRef, useState } from 'react';
import { setOptions, importLibrary } from '@googlemaps/js-api-loader';

const MAPS_KEY = process.env.NEXT_PUBLIC_FIREBASE_API_KEY ?? '';

export interface PartiesAdresse { rue: string; ville: string; codePostal: string; pays?: string; lat?: number; lng?: number }

export default function AdresseGoogleInput({ value, onChange, placeholder, className }: {
  value: string;
  onChange: (v: string, parts: PartiesAdresse) => void;
  placeholder: string;
  className?: string;
}) {
  const [query, setQuery] = useState(value);
  const [predictions, setPredictions] = useState<google.maps.places.AutocompletePrediction[]>([]);
  const autocompleteRef = useRef<google.maps.places.AutocompleteService | null>(null);
  const placesRef = useRef<google.maps.places.PlacesService | null>(null);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    try { setOptions({ key: MAPS_KEY, v: 'weekly', language: 'fr' }); } catch {}
    (async () => {
      try {
        const { AutocompleteService, PlacesService } = await importLibrary('places') as google.maps.PlacesLibrary;
        autocompleteRef.current = new AutocompleteService();
        placesRef.current = new PlacesService(document.createElement('div'));
      } catch {}
    })();
  }, []);

  function onType(v: string) {
    setQuery(v);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    if (!v.trim() || !autocompleteRef.current) { setPredictions([]); return; }
    debounceRef.current = setTimeout(() => {
      autocompleteRef.current!.getPlacePredictions(
        { input: v, componentRestrictions: { country: ['fr', 'be', 'ch', 'lu', 'mc'] }, types: ['address'] },
        (res) => setPredictions(res ?? []),
      );
    }, 300);
  }

  function selectPrediction(p: google.maps.places.AutocompletePrediction) {
    setQuery(p.description);
    setPredictions([]);
    placesRef.current?.getDetails({ placeId: p.place_id, fields: ['address_components', 'geometry'] }, (place) => {
      if (!place?.address_components) return;
      const parts = place.address_components;
      const num = parts.find(c => c.types.includes('street_number'))?.long_name ?? '';
      const route = parts.find(c => c.types.includes('route'))?.long_name ?? '';
      const rue = [num, route].filter(Boolean).join(' ');
      const ville = parts.find(c => c.types.includes('locality'))?.long_name
                 ?? parts.find(c => c.types.includes('postal_town'))?.long_name ?? '';
      const codePostal = parts.find(c => c.types.includes('postal_code'))?.long_name ?? '';
      const pays = parts.find(c => c.types.includes('country'))?.long_name ?? '';
      const loc = place.geometry?.location;
      onChange(p.description, { rue, ville, codePostal, pays, lat: loc?.lat(), lng: loc?.lng() });
    });
  }

  return (
    <div className="relative">
      <input type="text" value={query} onChange={(e) => onType(e.target.value)} placeholder={placeholder}
        className={className ?? 'w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white'} />
      {predictions.length > 0 && (
        <ul className="absolute z-50 left-0 right-0 bg-white border border-gray-200 rounded-xl mt-1 shadow-lg max-h-52 overflow-y-auto">
          {predictions.map((p) => (
            <li key={p.place_id}
              className="px-4 py-2.5 text-sm cursor-pointer hover:bg-[#E8F4F6] text-[#1F2A2E]"
              onMouseDown={() => selectPrediction(p)}>
              {p.description}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
