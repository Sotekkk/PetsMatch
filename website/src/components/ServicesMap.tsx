'use client';

import { useEffect } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

export interface ProMapItem {
  uid: string;
  name: string;
  photo?: string;
  profession?: string;
  ville?: string;
  cat_pro?: string;
  especes: string[];
  accept_new_clients?: boolean;
  lat: number;
  lng: number;
}

// Couleur par cat_pro (miroir app Flutter)
const CAT_COLORS: Record<string, string> = {
  sante:          '#2196F3',  // bleu
  veterinaire:    '#2196F3',  // bleu
  education:      '#FF9800',  // orange
  garde:          '#4CAF50',  // vert
  referencement:  '#CDDC39',  // jaune
};
const DEFAULT_COLOR = '#9C27B0'; // violet

const CAT_EMOJI: Record<string, string> = {
  sante:         '🩺',
  veterinaire:   '🩺',
  education:     '🎓',
  garde:         '🏡',
  referencement: '📋',
};
const DEFAULT_EMOJI = '💼';

function makeIcon(cat: string) {
  const color = CAT_COLORS[cat] ?? DEFAULT_COLOR;
  const emoji = CAT_EMOJI[cat] ?? DEFAULT_EMOJI;
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

function FitBounds({ pros }: { pros: ProMapItem[] }) {
  const map = useMap();
  useEffect(() => {
    if (pros.length === 0) return;
    const bounds = L.latLngBounds(pros.map(p => [p.lat, p.lng]));
    map.fitBounds(bounds, { padding: [40, 40], maxZoom: 12 });
  }, [pros, map]);
  return null;
}

export default function ServicesMap({ pros }: { pros: ProMapItem[] }) {
  return (
    <MapContainer
      center={[46.5, 2.5]}
      zoom={6}
      style={{ height: '100%', width: '100%', borderRadius: '1rem' }}
      scrollWheelZoom
    >
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <FitBounds pros={pros} />
      {pros.map(p => (
        <Marker key={p.uid} position={[p.lat, p.lng]} icon={makeIcon(p.cat_pro ?? '')}>
          <Popup>
            <div style={{ minWidth: 170, fontFamily: 'Galey, sans-serif' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
                {p.photo ? (
                  <img src={p.photo} alt={p.name}
                    style={{ width: 36, height: 36, borderRadius: 8, objectFit: 'cover', flexShrink: 0 }} />
                ) : (
                  <div style={{ width: 36, height: 36, borderRadius: 8, background: CAT_COLORS[p.cat_pro ?? ''] ?? DEFAULT_COLOR,
                    display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 18 }}>
                    {CAT_EMOJI[p.cat_pro ?? ''] ?? DEFAULT_EMOJI}
                  </div>
                )}
                <div>
                  <p style={{ margin: 0, fontWeight: 700, fontSize: 13, color: '#1E2025' }}>{p.name}</p>
                  {p.profession && <p style={{ margin: 0, fontSize: 11, color: CAT_COLORS[p.cat_pro ?? ''] ?? DEFAULT_COLOR }}>{p.profession}</p>}
                </div>
              </div>
              {p.ville && <p style={{ margin: '0 0 4px', fontSize: 11, color: '#888' }}>📍 {p.ville}</p>}
              {p.especes.length > 0 && (
                <p style={{ margin: '0 0 8px', fontSize: 11, color: '#aaa' }}>{p.especes.join(' · ')}</p>
              )}
              {p.accept_new_clients !== false && (
                <span style={{ display: 'inline-block', background: '#E8F5E9', color: '#388E3C',
                  fontSize: 10, fontWeight: 700, padding: '2px 8px', borderRadius: 8, marginBottom: 8 }}>
                  Disponible
                </span>
              )}
              <a href={`/services/pro/${p.uid}`}
                style={{ display: 'block', textAlign: 'center', fontSize: 12, background: '#0C5C6C',
                  color: 'white', fontWeight: 600, padding: '6px 12px', borderRadius: 8, textDecoration: 'none' }}>
                Voir le profil
              </a>
            </div>
          </Popup>
        </Marker>
      ))}
    </MapContainer>
  );
}
