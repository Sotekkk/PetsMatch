'use client';
// Recherche d'un lieu avec Google Maps (Places) : adresse, mais aussi lieu
// nommé (plage, forêt, parc, studio…). Renvoie le libellé (nom du lieu +
// adresse) et les coordonnées GPS. Saisie libre conservée si Google est
// indisponible. Miroir appli : AdresseRechercheField (lib/widgets).
import { useEffect, useRef, useState } from 'react';
import { setOptions, importLibrary } from '@googlemaps/js-api-loader';

export interface LieuTrouve { libelle: string; lat: number | null; lng: number | null }

export default function LieuGoogleRecherche({ value, onChange, onSelect, placeholder, autoFocus }: {
  value: string; onChange: (v: string) => void; onSelect: (l: LieuTrouve) => void;
  placeholder?: string; autoFocus?: boolean;
}) {
  const auto = useRef<google.maps.places.AutocompleteService | null>(null);
  const details = useRef<google.maps.places.PlacesService | null>(null);
  const attente = useRef<ReturnType<typeof setTimeout> | null>(null);
  const [suggestions, setSuggestions] = useState<google.maps.places.AutocompletePrediction[]>([]);

  useEffect(() => {
    const cle = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;
    if (!cle) return;
    setOptions({ key: cle, v: 'weekly', language: 'fr' });
    importLibrary('places').then(() => {
      auto.current = new window.google.maps.places.AutocompleteService();
      details.current = new window.google.maps.places.PlacesService(document.createElement('div'));
    }).catch(() => {});
  }, []);

  function saisir(v: string) {
    onChange(v);
    if (attente.current) clearTimeout(attente.current);
    if (v.trim().length < 3 || !auto.current) { setSuggestions([]); return; }
    attente.current = setTimeout(() => {
      auto.current?.getPlacePredictions(
        { input: v, componentRestrictions: { country: ['fr', 'be', 'ch', 'lu'] }, language: 'fr' } as google.maps.places.AutocompletionRequest,
        (preds, statut) => setSuggestions(statut === window.google.maps.places.PlacesServiceStatus.OK && preds ? preds : []),
      );
    }, 350);
  }

  function choisir(p: google.maps.places.AutocompletePrediction) {
    setSuggestions([]);
    onChange(p.description);
    details.current?.getDetails({ placeId: p.place_id, fields: ['name', 'formatted_address', 'geometry'] }, (place, statut) => {
      if (statut !== window.google.maps.places.PlacesServiceStatus.OK || !place) {
        onSelect({ libelle: p.description, lat: null, lng: null });
        return;
      }
      const adr = place.formatted_address ?? p.description;
      const nom = place.name ?? '';
      // Lieu nommé (plage, parc…) : « Nom, adresse » ; adresse simple : telle quelle.
      const libelle = nom && !adr.startsWith(nom) ? `${nom}, ${adr}` : adr;
      onChange(libelle);
      const loc = place.geometry?.location;
      onSelect({ libelle, lat: loc ? loc.lat() : null, lng: loc ? loc.lng() : null });
    });
  }

  return (
    <div className="relative">
      <input value={value} onChange={e => saisir(e.target.value)} placeholder={placeholder ?? 'Rechercher un lieu ou une adresse (Google Maps)'}
        autoFocus={autoFocus} className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />
      {suggestions.length > 0 && (
        <div className="absolute z-10 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
          {suggestions.slice(0, 5).map(p => (
            <button key={p.place_id} type="button" onClick={() => choisir(p)} className="block w-full text-left px-3 py-2 text-sm hover:bg-gray-50">
              <span className="font-semibold text-[#1F2A2E]">{p.structured_formatting?.main_text ?? p.description}</span>
              {p.structured_formatting?.secondary_text && <span className="block text-xs text-gray-500">{p.structured_formatting.secondary_text}</span>}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
