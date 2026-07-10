'use client';

import { useEffect } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

export interface BaladeMapItem {
  id: string;
  titre?: string;
  difficulte?: string;
  lat_depart: number;
  lng_depart: number;
  cover_url?: string;
}

const DIFFICULTE_COLOR: Record<string, string> = {
  facile: '#6E9E57', modere: '#F59E0B', difficile: '#DC2626',
};

function makeIcon(difficulte?: string) {
  const bg = DIFFICULTE_COLOR[difficulte ?? ''] ?? '#0C5C6C';
  return L.divIcon({
    className: '',
    html: `<div style="
      background:${bg};width:36px;height:36px;border-radius:50% 50% 50% 0;
      transform:rotate(-45deg);display:flex;align-items:center;justify-content:center;
      box-shadow:0 2px 8px rgba(0,0,0,.35);border:2px solid white;">
      <span style="transform:rotate(45deg);font-size:16px;line-height:1">🧭</span>
    </div>`,
    iconSize: [36, 36],
    iconAnchor: [18, 36],
    popupAnchor: [0, -38],
  });
}

function FitBounds({ items }: { items: BaladeMapItem[] }) {
  const map = useMap();
  useEffect(() => {
    if (items.length === 0) return;
    const bounds = L.latLngBounds(items.map(a => [a.lat_depart, a.lng_depart]));
    map.fitBounds(bounds, { padding: [40, 40], maxZoom: 12 });
  }, [items, map]);
  return null;
}

export default function BaladesLudiquesMap({ balades, onSelect }: { balades: BaladeMapItem[]; onSelect?: (id: string) => void }) {
  return (
    <MapContainer center={[46.5, 2.5]} zoom={6} style={{ height: '100%', width: '100%' }} scrollWheelZoom>
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <FitBounds items={balades} />
      {balades.map(b => (
        <Marker key={b.id} position={[b.lat_depart, b.lng_depart]} icon={makeIcon(b.difficulte)}
          eventHandlers={{ click: () => onSelect?.(b.id) }}>
          <Popup>
            <div style={{ minWidth: 160, fontFamily: 'sans-serif' }}>
              {b.cover_url && (
                <img src={b.cover_url} alt={b.titre} style={{ width: '100%', height: 80, objectFit: 'cover', borderRadius: 8, marginBottom: 6 }} />
              )}
              <p style={{ fontWeight: 700, fontSize: 13, margin: '0 0 6px', color: '#1F2A2E' }}>{b.titre}</p>
              <a href={`/balades-ludiques/${b.id}`}
                style={{ display: 'block', textAlign: 'center', background: '#0C5C6C', color: '#fff',
                  padding: '6px 12px', borderRadius: 8, fontSize: 12, fontWeight: 600, textDecoration: 'none' }}>
                Voir le parcours →
              </a>
            </div>
          </Popup>
        </Marker>
      ))}
    </MapContainer>
  );
}
