'use client';

import { MapContainer, TileLayer, Marker, useMapEvents } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

export interface EditablePoint {
  lat: number;
  lng: number;
  titre?: string;
}

function numberIcon(n: number) {
  return L.divIcon({
    className: '',
    html: `<div style="
      background:#0C5C6C;width:30px;height:30px;border-radius:50%;
      display:flex;align-items:center;justify-content:center;color:#fff;
      font-family:sans-serif;font-weight:700;font-size:13px;
      box-shadow:0 2px 6px rgba(0,0,0,.35);border:2px solid white;">${n}</div>`,
    iconSize: [30, 30],
    iconAnchor: [15, 15],
  });
}

function ClickCatcher({ onClick }: { onClick: (lat: number, lng: number) => void }) {
  useMapEvents({ click: (e) => onClick(e.latlng.lat, e.latlng.lng) });
  return null;
}

export default function BaladesLudiquesPointsEditor({ points, onAddPoint, onSelectPoint, center }: {
  points: EditablePoint[];
  onAddPoint: (lat: number, lng: number) => void;
  onSelectPoint?: (index: number) => void;
  center?: [number, number];
}) {
  return (
    <MapContainer center={center ?? [46.5, 2.5]} zoom={center ? 14 : 6} style={{ height: '100%', width: '100%' }} scrollWheelZoom>
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <ClickCatcher onClick={onAddPoint} />
      {points.map((p, i) => (
        <Marker key={i} position={[p.lat, p.lng]} icon={numberIcon(i + 1)}
          eventHandlers={{ click: () => onSelectPoint?.(i) }} />
      ))}
    </MapContainer>
  );
}
