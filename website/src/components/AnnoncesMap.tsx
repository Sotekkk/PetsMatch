'use client';

import { useEffect } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import Link from 'next/link';

export interface AnnonceMapItem {
  id: string;
  titre?: string;
  espece?: string;
  race?: string;
  type_vente?: string;
  type?: string;
  photos?: string[];
  prix?: number;
  prix_min_portee?: number;
  prix_max_portee?: number;
  ville_eleveur?: string;
  nom_eleveur?: string;
  lat: number;
  lng: number;
}

const ESPECE_EMOJI: Record<string, string> = {
  chien: '🐕', chat: '🐈', cheval: '🐴', lapin: '🐇',
  oiseau: '🦜', nac: '🦎', ovin: '🐑', caprin: '🐐', porcin: '🐷',
};

function makeIcon(typeVente?: string, espece?: string) {
  const isSaillie = typeVente === 'saillie';
  const bg = isSaillie ? '#8B5CF6' : '#6E9E57';
  const emoji = ESPECE_EMOJI[espece ?? ''] ?? '🐾';
  return L.divIcon({
    className: '',
    html: `<div style="
      background:${bg};width:38px;height:38px;border-radius:50% 50% 50% 0;
      transform:rotate(-45deg);display:flex;align-items:center;justify-content:center;
      box-shadow:0 2px 8px rgba(0,0,0,.35);border:2px solid white;">
      <span style="transform:rotate(45deg);font-size:17px;line-height:1">${emoji}</span>
    </div>`,
    iconSize: [38, 38],
    iconAnchor: [19, 38],
    popupAnchor: [0, -40],
  });
}

function FitBounds({ items }: { items: AnnonceMapItem[] }) {
  const map = useMap();
  useEffect(() => {
    if (items.length === 0) return;
    const bounds = L.latLngBounds(items.map(a => [a.lat, a.lng]));
    map.fitBounds(bounds, { padding: [40, 40], maxZoom: 10 });
  }, [items, map]);
  return null;
}

export default function AnnoncesMap({ annonces }: { annonces: AnnonceMapItem[] }) {
  return (
    <MapContainer
      center={[46.5, 2.5]}
      zoom={6}
      style={{ height: '100%', width: '100%' }}
      scrollWheelZoom>
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <FitBounds items={annonces} />
      {annonces.map((a, idx) => {
        const isSaillie = a.type_vente === 'saillie';
        const isPortee  = a.type === 'portee';
        const titre = a.titre || `${a.espece ?? ''} ${a.race ?? ''}`.trim();
        const prix = isPortee
          ? (a.prix_min_portee != null ? `dès ${a.prix_min_portee} €` : null)
          : (a.prix != null ? `${a.prix} €` : null);
        const badge = isSaillie ? '💜 Saillie' : isPortee ? '🐾 Portée' : '🐾 Compagnon';
        const badgeColor = isSaillie ? '#8B5CF6' : '#6E9E57';
        const photo = a.photos?.[0];

        return (
          <Marker key={`${a.id}_${idx}`} position={[a.lat, a.lng]} icon={makeIcon(a.type_vente, a.espece)}>
            <Popup>
              <div style={{ minWidth: 170, fontFamily: 'sans-serif' }}>
                {photo && (
                  <img src={photo} alt={titre}
                    style={{ width: '100%', height: 90, objectFit: 'cover', borderRadius: 8, marginBottom: 8 }} />
                )}
                <div style={{ display: 'flex', alignItems: 'flex-start', gap: 6, marginBottom: 4 }}>
                  <span style={{ background: badgeColor, color: '#fff', fontSize: 10, fontWeight: 700,
                    padding: '2px 7px', borderRadius: 10, flexShrink: 0 }}>
                    {badge}
                  </span>
                </div>
                <p style={{ fontWeight: 700, fontSize: 13, margin: '0 0 2px', color: '#1F2A2E' }}>{titre}</p>
                {a.race && <p style={{ fontSize: 11, color: '#6F767B', margin: '0 0 2px' }}>{a.race}</p>}
                {prix && <p style={{ fontSize: 13, fontWeight: 700, color: '#0C5C6C', margin: '0 0 4px' }}>{prix}</p>}
                {a.ville_eleveur && (
                  <p style={{ fontSize: 11, color: '#9CA3AF', margin: '0 0 2px' }}>📍 {a.ville_eleveur}</p>
                )}
                {a.nom_eleveur && (
                  <p style={{ fontSize: 11, color: '#9CA3AF', margin: '0 0 8px' }}>🏡 {a.nom_eleveur}</p>
                )}
                <a href={`/annonces/${a.id}`}
                  style={{ display: 'block', textAlign: 'center', background: '#0C5C6C', color: '#fff',
                    padding: '6px 12px', borderRadius: 8, fontSize: 12, fontWeight: 600, textDecoration: 'none' }}>
                  Voir l&apos;annonce →
                </a>
              </div>
            </Popup>
          </Marker>
        );
      })}
    </MapContainer>
  );
}
