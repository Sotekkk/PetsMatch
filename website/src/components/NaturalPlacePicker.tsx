'use client';

import { MapContainer, TileLayer, Marker, useMapEvents } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

function pinIcon() {
  return L.divIcon({
    className: '',
    html: `<div style="
      background:#0C5C6C;width:34px;height:34px;border-radius:50% 50% 50% 0;
      transform:rotate(-45deg);display:flex;align-items:center;justify-content:center;
      box-shadow:0 2px 6px rgba(0,0,0,.35);border:2px solid white;">
      <span style="transform:rotate(45deg);font-size:15px;line-height:1">📍</span>
    </div>`,
    iconSize: [34, 34],
    iconAnchor: [17, 34],
  });
}

function ClickCatcher({ onPick }: { onPick: (lat: number, lng: number) => void }) {
  useMapEvents({ click: (e) => onPick(e.latlng.lat, e.latlng.lng) });
  return null;
}

export default function NaturalPlacePicker({ lat, lng, onChange }: {
  lat: number; lng: number; onChange: (lat: number, lng: number) => void;
}) {
  return (
    <MapContainer center={[lat, lng]} zoom={13} style={{ height: '100%', width: '100%' }} scrollWheelZoom>
      <TileLayer
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
      />
      <ClickCatcher onPick={onChange} />
      <Marker
        position={[lat, lng]}
        icon={pinIcon()}
        draggable
        eventHandlers={{ dragend: (e) => { const p = e.target.getLatLng(); onChange(p.lat, p.lng); } }}
      />
    </MapContainer>
  );
}
