'use client';

import { useEffect } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

export interface AlerteMapItem {
  id: string;
  type?: 'perdu' | 'trouve'; // default perdu
  nom_animal: string;
  espece?: string;
  race?: string;
  photo_url?: string;
  derniere_localisation?: string;
  contact?: string;
  date_perte?: string;
  date_trouve?: string;
  lat: number;
  lng: number;
  onDetail?: () => void;
}

function especeEmoji(espece?: string): string {
  return ({
    chien: '🐕', chat: '🐈', cheval: '🐴', lapin: '🐇',
    oiseau: '🦜', nac: '🦎', ovin: '🐑', caprin: '🐐', porcin: '🐷',
  } as Record<string, string>)[espece ?? ''] ?? '🐾';
}

const ESPECE_BG: Record<string, string> = {
  chien:  '#DBEAFE',
  chat:   '#FCE7F3',
  cheval: '#FEF3C7',
  lapin:  '#D1FAE5',
  oiseau: '#EDE9FE',
  nac:    '#FEE2E2',
  ovin:   '#F0FDF4',
  caprin: '#FFF7ED',
  porcin: '#FDF2F8',
};

const ESPECE_BORDER: Record<string, string> = {
  chien:  '#3B82F6',
  chat:   '#EC4899',
  cheval: '#F59E0B',
  lapin:  '#10B981',
  oiseau: '#8B5CF6',
  nac:    '#EF4444',
  ovin:   '#22C55E',
  caprin: '#F97316',
  porcin: '#D946EF',
};

function makeIcon(espece?: string, type: 'perdu' | 'trouve' = 'perdu') {
  const emoji = especeEmoji(espece);
  const key = espece ?? '';
  const border = type === 'trouve' ? '#16A34A' : (ESPECE_BORDER[key] ?? '#EF4444');
  return L.divIcon({
    className: '',
    html: `<div style="
      background:${border};width:38px;height:38px;border-radius:50% 50% 50% 0;
      transform:rotate(-45deg);display:flex;align-items:center;justify-content:center;
      box-shadow:0 2px 8px rgba(0,0,0,.35);border:2px solid white;">
      <span style="transform:rotate(45deg);font-size:17px;line-height:1">${emoji}</span>
    </div>`,
    iconSize: [38, 38],
    iconAnchor: [19, 38],
    popupAnchor: [0, -40],
  });
}

function FitBounds({ alertes }: { alertes: AlerteMapItem[] }) {
  const map = useMap();
  useEffect(() => {
    if (alertes.length === 0) return;
    const bounds = L.latLngBounds(alertes.map(a => [a.lat, a.lng]));
    map.fitBounds(bounds, { padding: [40, 40], maxZoom: 12 });
  }, [alertes, map]);
  return null;
}

function fmtDate(s?: string) {
  if (!s) return null;
  return new Date(s).toLocaleDateString('fr-FR');
}

export default function AnimauxPerdusMap({ alertes }: { alertes: AlerteMapItem[] }) {
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
      <FitBounds alertes={alertes} />
      {alertes.map(a => {
        const isPerdu = (a.type ?? 'perdu') === 'perdu';
        const bg = ESPECE_BG[a.espece ?? ''] ?? '#FEE2E2';
        const markerColor = isPerdu ? (ESPECE_BORDER[a.espece ?? ''] ?? '#EF4444') : '#16A34A';
        return (
        <Marker key={`${a.type ?? 'perdu'}_${a.id}`} position={[a.lat, a.lng]} icon={makeIcon(a.espece, a.type ?? 'perdu')}
          eventHandlers={{ click: a.onDetail ? () => a.onDetail!() : undefined }}>
          <Popup>
            <div style={{ minWidth: 160, fontFamily: 'sans-serif' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
                {a.photo_url ? (
                  <img src={a.photo_url} alt={a.nom_animal}
                    style={{ width: 40, height: 40, borderRadius: '50%', objectFit: 'cover', flexShrink: 0 }} />
                ) : (
                  <div style={{ width: 40, height: 40, borderRadius: '50%', background: isPerdu ? bg : '#DCFCE7', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20, flexShrink: 0 }}>
                    {especeEmoji(a.espece)}
                  </div>
                )}
                <div style={{ minWidth: 0 }}>
                  <p style={{ fontWeight: 700, fontSize: 13, margin: 0, color: '#1F2A2E' }}>
                    {isPerdu ? a.nom_animal : `${especeEmoji(a.espece)} ${a.espece?.charAt(0).toUpperCase() ?? ''}${a.espece?.slice(1) ?? 'Animal trouvé'}`}
                  </p>
                  <p style={{ fontSize: 11, color: markerColor, fontWeight: 600, margin: 0 }}>
                    {isPerdu ? '🚨 Perdu' : '🐾 Trouvé'}
                  </p>
                </div>
              </div>
              {(a.espece || a.race) && (
                <p style={{ fontSize: 11, color: '#6B7280', margin: '2px 0' }}>
                  {a.espece}{a.race ? ` · ${a.race}` : ''}
                </p>
              )}
              {a.derniere_localisation && (
                <p style={{ fontSize: 11, color: '#F97316', margin: '2px 0' }}>📍 {a.derniere_localisation}</p>
              )}
              {isPerdu && a.date_perte && (
                <p style={{ fontSize: 11, color: '#9CA3AF', margin: '2px 0' }}>Perdu le {fmtDate(a.date_perte)}</p>
              )}
              {!isPerdu && a.date_trouve && (
                <p style={{ fontSize: 11, color: '#16A34A', margin: '2px 0' }}>Trouvé le {fmtDate(a.date_trouve)}</p>
              )}
              {a.contact && isPerdu && (
                <a href={a.contact.includes('@') ? `mailto:${a.contact}` : `tel:${a.contact}`}
                  style={{ display: 'block', marginTop: 8, textAlign: 'center', fontSize: 12,
                    background: '#0C5C6C', color: 'white', fontWeight: 600,
                    padding: '6px 12px', borderRadius: 8, textDecoration: 'none' }}>
                  Contacter
                </a>
              )}
              {a.onDetail && (
                <button onClick={() => a.onDetail!()} style={{ display: 'block', width: '100%', marginTop: 8, textAlign: 'center', fontSize: 12,
                  background: isPerdu ? '#0C5C6C' : '#16A34A', color: 'white', fontWeight: 600,
                  padding: '6px 12px', borderRadius: 8, border: 'none', cursor: 'pointer' }}>
                  Voir le détail
                </button>
              )}
            </div>
          </Popup>
        </Marker>
        );
      })}
    </MapContainer>
  );
}
