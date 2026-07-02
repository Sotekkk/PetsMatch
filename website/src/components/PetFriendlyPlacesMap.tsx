'use client';

import { useEffect } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import Link from 'next/link';

export interface PetFriendlyMapItem {
  id: string;
  nom: string;
  categorie: string;
  ville?: string | null;
  lat: number;
  lng: number;
  note_moyenne?: number | null;
  nb_avis?: number | null;
}

const CAT_COLOR: Record<string, string> = {
  hebergement: '#1E88E5',
  restauration: '#EF6C00',
};
const CAT_EMOJI: Record<string, string> = {
  hebergement: '🏨',
  restauration: '🍽️',
};
const CAT_LABEL: Record<string, string> = {
  hebergement: 'Hébergement',
  restauration: 'Restauration',
};

function makeIcon(categorie: string) {
  const color = CAT_COLOR[categorie] ?? '#0C5C6C';
  const emoji = CAT_EMOJI[categorie] ?? '📍';

  return L.divIcon({
    className: '',
    html: `<div style="
      background:${color};width:34px;height:34px;border-radius:50% 50% 50% 0;
      transform:rotate(-45deg);display:flex;align-items:center;justify-content:center;
      box-shadow:0 2px 6px rgba(0,0,0,.3);border:2px solid white;">
      <span style="transform:rotate(45deg);font-size:15px;line-height:1">${emoji}</span>
    </div>`,
    iconSize: [34, 34],
    iconAnchor: [17, 34],
    popupAnchor: [0, -36],
  });
}

function FitBounds({ places }: { places: PetFriendlyMapItem[] }) {
  const map = useMap();
  useEffect(() => {
    if (places.length === 0) return;
    const bounds = L.latLngBounds(places.map(p => [p.lat, p.lng]));
    map.fitBounds(bounds, { padding: [40, 40], maxZoom: 11 });
  }, [places, map]);
  return null;
}

export default function PetFriendlyPlacesMap({ places }: { places: PetFriendlyMapItem[] }) {
  return (
    <MapContainer
      center={[46.6, 1.9]}
      zoom={6}
      style={{ height: '100%', width: '100%', borderRadius: '1rem' }}
      scrollWheelZoom>
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <FitBounds places={places} />
      {places.map(p => (
        <Marker key={p.id} position={[p.lat, p.lng]} icon={makeIcon(p.categorie)}>
          <Popup>
            <div className="text-sm" style={{ minWidth: 160 }}>
              <p className="font-bold text-[#1F2A2E]">{p.nom}</p>
              <p className="text-gray-500 text-xs">{CAT_EMOJI[p.categorie]} {CAT_LABEL[p.categorie] ?? p.categorie}</p>
              {p.ville && <p className="text-gray-500 text-xs">📍 {p.ville}</p>}
              {(p.nb_avis ?? 0) > 0 && (
                <p className="text-gray-500 text-xs">★ {(p.note_moyenne ?? 0).toFixed(1)} ({p.nb_avis} avis)</p>
              )}
              <Link href={`/animal-friendly/${p.id}`}
                className="block mt-2 text-center text-xs bg-[#0C5C6C] text-white font-medium py-1.5 px-3 rounded-lg hover:bg-[#094F5D] transition-colors">
                Voir la fiche
              </Link>
            </div>
          </Popup>
        </Marker>
      ))}
      {places.length === 0 && (
        <div className="absolute inset-0 flex items-center justify-center z-[1000] pointer-events-none">
          <p className="bg-white/90 rounded-xl px-4 py-2 text-gray-500 text-sm shadow">
            Aucun lieu avec coordonnées GPS
          </p>
        </div>
      )}
    </MapContainer>
  );
}
