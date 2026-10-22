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
  referencement?: 'communaute' | 'verifie' | 'partenaire';
}

// Couleur d'épingle selon le référencement (une seule carte pour les trois).
const REF_COLOR: Record<string, string> = { communaute: '#FFFFFF', verifie: '#0C5C6C', partenaire: '#6E9E57' };
const REF_LABEL: Record<string, string> = {
  communaute: 'Recommandé par la communauté', verifie: 'Établissement vérifié', partenaire: 'Partenaire PetsMatch',
};
const CAT_LABEL: Record<string, string> = {
  hebergement: 'Hébergement', restauration: 'Café / restaurant', commerce: 'Commerce', activite: 'Activité ou loisir',
};

function makeIcon(referencement: string) {
  const fond = REF_COLOR[referencement] ?? '#0C5C6C';
  const bord = referencement === 'communaute' ? '#5E6B70' : '#FFFFFF';
  return L.divIcon({
    className: '',
    html: `<div style="background:${fond};width:30px;height:30px;border-radius:50% 50% 50% 0;
      transform:rotate(-45deg);box-shadow:0 2px 6px rgba(0,0,0,.3);border:3px solid ${bord};"></div>`,
    iconSize: [30, 30],
    iconAnchor: [15, 30],
    popupAnchor: [0, -32],
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
        <Marker key={p.id} position={[p.lat, p.lng]} icon={makeIcon(p.referencement ?? 'verifie')}>
          <Popup>
            <div className="text-sm" style={{ minWidth: 160 }}>
              <p className="font-bold text-[#1F2A2E]">{p.nom}</p>
              <p className="text-gray-500 text-xs">{CAT_LABEL[p.categorie] ?? p.categorie}{p.referencement ? ` · ${REF_LABEL[p.referencement]}` : ''}</p>
              {p.ville && <p className="text-gray-500 text-xs">{p.ville}</p>}
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
