'use client';

import { useEffect } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import Link from 'next/link';

export interface EleveurMapItem {
  id: string;
  name: string;
  photo?: string;
  ville?: string;
  especes: string[];
  lat: number;
  lng: number;
}

// Couleur par espèce (miroir du Flutter app)
function markerColor(especes: string[]): string {
  if (especes.length === 0) return '#E91E8C';
  if (especes.length > 1) return '#E91E63';
  return ({
    chien:  '#2196F3',
    chat:   '#FF9800',
    cheval: '#4CAF50',
    lapin:  '#9C27B0',
    oiseau: '#00BCD4',
    nac:    '#CDDC39',
    ovin:   '#E91E63',
    caprin: '#E91E63',
    porcin: '#E91E63',
  } as Record<string, string>)[especes[0]] ?? '#E91E8C';
}

function makeIcon(especes: string[]) {
  const color = markerColor(especes);
  const emoji = ({
    chien: '🐕', chat: '🐈', cheval: '🐴', lapin: '🐇',
    oiseau: '🦜', nac: '🦎', ovin: '🐑', caprin: '🐐', porcin: '🐷',
  } as Record<string, string>)[especes[0] ?? ''] ?? '🏡';

  return L.divIcon({
    className: '',
    html: `<div style="
      background:${color};width:36px;height:36px;border-radius:50% 50% 50% 0;
      transform:rotate(-45deg);display:flex;align-items:center;justify-content:center;
      box-shadow:0 2px 6px rgba(0,0,0,.3);border:2px solid white;">
      <span style="transform:rotate(45deg);font-size:16px;line-height:1">${emoji}</span>
    </div>`,
    iconSize: [36, 36],
    iconAnchor: [18, 36],
    popupAnchor: [0, -38],
  });
}

// Recentre la carte quand les données changent
function FitBounds({ eleveurs }: { eleveurs: EleveurMapItem[] }) {
  const map = useMap();
  useEffect(() => {
    if (eleveurs.length === 0) return;
    const bounds = L.latLngBounds(eleveurs.map(e => [e.lat, e.lng]));
    map.fitBounds(bounds, { padding: [40, 40], maxZoom: 10 });
  }, [eleveurs, map]);
  return null;
}

export default function ElevagesMap({ eleveurs }: { eleveurs: EleveurMapItem[] }) {
  return (
    <MapContainer
      center={[46.5, 2.5]}
      zoom={6}
      style={{ height: '100%', width: '100%', borderRadius: '1rem' }}
      scrollWheelZoom>
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <FitBounds eleveurs={eleveurs} />
      {eleveurs.map(e => (
        <Marker key={e.id} position={[e.lat, e.lng]} icon={makeIcon(e.especes)}>
          <Popup>
            <div className="text-sm" style={{ minWidth: 160 }}>
              <p className="font-bold text-[#1F2A2E]">{e.name}</p>
              {e.ville && <p className="text-gray-500 text-xs">📍 {e.ville}</p>}
              {e.especes.length > 0 && (
                <p className="text-gray-400 text-xs capitalize">{e.especes.join(' · ')}</p>
              )}
              <Link href={`/elevages/${e.id}`}
                className="block mt-2 text-center text-xs bg-[#0C5C6C] text-white font-medium py-1.5 px-3 rounded-lg hover:bg-[#094F5D] transition-colors">
                Voir le profil
              </Link>
            </div>
          </Popup>
        </Marker>
      ))}
      {eleveurs.length === 0 && (
        <div className="absolute inset-0 flex items-center justify-center z-[1000] pointer-events-none">
          <p className="bg-white/90 rounded-xl px-4 py-2 text-gray-500 text-sm shadow">
            Aucun éleveur avec coordonnées GPS
          </p>
        </div>
      )}
    </MapContainer>
  );
}
