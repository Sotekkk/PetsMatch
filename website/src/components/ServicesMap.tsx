'use client';

import { useEffect } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { couleurMarqueurPro } from '@/lib/annuaire-couleurs';

export interface ProMapItem {
  uid: string;
  profileTableId?: string; // user_profiles.id pour profils secondaires
  name: string;
  photo?: string;
  banner?: string;
  profession?: string;
  ville?: string;
  cat_pro?: string;
  especes: string[];
  accept_new_clients?: boolean;
  lat: number;
  lng: number;
  rayon_intervention?: number;
}

// Couleurs : src/lib/annuaire-couleurs.ts (partagées avec la liste).
// Pastille neutre (patte) à la place de l'ancien émoji.
const PATTE_SVG = '<svg width="15" height="15" viewBox="0 0 24 24" fill="white" aria-hidden="true"><ellipse cx="12" cy="16.5" rx="4.2" ry="3.4"/><circle cx="6.5" cy="10.5" r="1.8"/><circle cx="9.8" cy="6.5" r="1.8"/><circle cx="14.2" cy="6.5" r="1.8"/><circle cx="17.5" cy="10.5" r="1.8"/></svg>';

function makeIcon(cat: string) {
  const color = couleurMarqueurPro(cat);
  return L.divIcon({
    className: '',
    html: `<div style="
      background:${color};width:36px;height:36px;border-radius:50% 50% 50% 0;
      transform:rotate(-45deg);display:flex;align-items:center;justify-content:center;
      box-shadow:0 2px 6px rgba(0,0,0,.3);border:2px solid white;">
      <span style="transform:rotate(45deg);display:flex">${PATTE_SVG}</span>
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
                  <div style={{ width: 36, height: 36, borderRadius: 8, background: '#F3F4F6', flexShrink: 0 }} />
                )}
                <div>
                  <p style={{ margin: 0, fontWeight: 700, fontSize: 13, color: '#1E2025' }}>{p.name}</p>
                  {p.profession && <p style={{ margin: 0, fontSize: 11, color: couleurMarqueurPro(p.cat_pro) }}>{p.profession}</p>}
                </div>
              </div>
              {p.ville && <p style={{ margin: '0 0 4px', fontSize: 11, color: '#6B7280' }}>{p.ville}</p>}
              {p.especes.length > 0 && (
                <p style={{ margin: '0 0 8px', fontSize: 11, color: '#aaa' }}>{p.especes.join(' · ')}</p>
              )}
              {p.accept_new_clients !== false && (
                <span style={{ display: 'inline-block', background: '#E8F5E9', color: '#388E3C',
                  fontSize: 10, fontWeight: 700, padding: '2px 8px', borderRadius: 8, marginBottom: 8 }}>
                  Disponible
                </span>
              )}
              <a href={`/services/pro/${p.uid}${p.profileTableId ? `?profileId=${p.profileTableId}` : ''}`}
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
