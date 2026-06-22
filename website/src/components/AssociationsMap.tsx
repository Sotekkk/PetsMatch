'use client';

import { useEffect } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import Link from 'next/link';

export interface AssoMapItem {
  id: string;
  name: string;
  avatar?: string;
  ville?: string;
  lat: number;
  lng: number;
}

function makeIcon() {
  return L.divIcon({
    className: '',
    html: `<div style="
      background:#0C5C6C;width:36px;height:36px;border-radius:50% 50% 50% 0;
      transform:rotate(-45deg);display:flex;align-items:center;justify-content:center;
      box-shadow:0 2px 6px rgba(0,0,0,.3);border:2px solid white;">
      <span style="transform:rotate(45deg);font-size:16px;line-height:1">🏠</span>
    </div>`,
    iconSize: [36, 36],
    iconAnchor: [18, 36],
    popupAnchor: [0, -38],
  });
}

function FitBounds({ assos }: { assos: AssoMapItem[] }) {
  const map = useMap();
  useEffect(() => {
    if (assos.length === 0) return;
    const bounds = L.latLngBounds(assos.map(a => [a.lat, a.lng]));
    map.fitBounds(bounds, { padding: [40, 40], maxZoom: 10 });
  }, [assos, map]);
  return null;
}

export default function AssociationsMap({ assos }: { assos: AssoMapItem[] }) {
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
      <FitBounds assos={assos} />
      {assos.map(a => (
        <Marker key={a.id} position={[a.lat, a.lng]} icon={makeIcon()}>
          <Popup>
            <div className="text-sm" style={{ minWidth: 160 }}>
              <p className="font-bold text-[#1F2A2E]">{a.name}</p>
              {a.ville && <p className="text-gray-500 text-xs">📍 {a.ville}</p>}
              <p className="text-gray-400 text-xs">Association / Refuge</p>
              <Link href={`/associations/${a.id}`}
                className="block mt-2 text-center text-xs bg-[#0C5C6C] text-white font-medium py-1.5 px-3 rounded-lg hover:bg-[#094F5D] transition-colors">
                Voir le profil
              </Link>
            </div>
          </Popup>
        </Marker>
      ))}
      {assos.length === 0 && (
        <div className="absolute inset-0 flex items-center justify-center z-[1000] pointer-events-none">
          <p className="bg-white/90 rounded-xl px-4 py-2 text-gray-500 text-sm shadow">
            Aucune association avec coordonnées GPS
          </p>
        </div>
      )}
    </MapContainer>
  );
}
