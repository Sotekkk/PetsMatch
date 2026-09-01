'use client';

import { useState } from 'react';
import { MapContainer, TileLayer, Marker, useMapEvents } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { supabase } from '@/lib/supabase';

const PIN = L.divIcon({
  className: '',
  html: `<div style="background:#C62828;width:26px;height:26px;border-radius:50% 50% 50% 0;transform:rotate(-45deg);border:2px solid white;box-shadow:0 2px 6px rgba(0,0,0,.35)"></div>`,
  iconSize: [26, 26],
  iconAnchor: [13, 26],
});

function ClickCatcher({ onPick }: { onPick: (lat: number, lng: number) => void }) {
  useMapEvents({ click: (e) => onPick(e.latlng.lat, e.latlng.lng) });
  return null;
}

export default function CyanoReportModal({
  placeId, placeLat, placeLng, current, profileId, forceConfirme = false, onClose, onDone,
}: {
  placeId: string;
  placeLat: number;
  placeLng: number;
  current?: { lat?: number | null; lng?: number | null; statut?: string | null; photo_url?: string | null };
  profileId: string | null;
  forceConfirme?: boolean;
  onClose: () => void;
  onDone: () => void;
}) {
  const [pt, setPt] = useState<[number, number]>([
    current?.lat ?? placeLat, current?.lng ?? placeLng,
  ]);
  const [statut, setStatut] = useState<'suspecte' | 'confirme'>(
    forceConfirme ? 'confirme' : (current?.statut as 'suspecte' | 'confirme') ?? 'suspecte',
  );
  const [photo, setPhoto] = useState<File | null>(null);
  const [saving, setSaving] = useState(false);

  async function save() {
    setSaving(true);
    try {
      let photoUrl = current?.photo_url ?? null;
      if (photo) {
        const ext = photo.name.split('.').pop() || 'jpg';
        const path = `natural_places/cyano_${placeId}_${Date.now()}.${ext}`;
        const { error } = await supabase.storage.from('media').upload(path, photo, { upsert: true });
        if (!error) photoUrl = supabase.storage.from('media').getPublicUrl(path).data.publicUrl;
      }
      await supabase.from('natural_places').update({
        alerte_cyano: true,
        alerte_cyano_statut: statut,
        alerte_cyano_lat: pt[0],
        alerte_cyano_lng: pt[1],
        alerte_cyano_date: new Date().toISOString(),
        alerte_cyano_profile_id: profileId || null,
        ...(statut === 'confirme' ? { alerte_cyano_photo_url: photoUrl } : {}),
      }).eq('id', placeId);
      onDone();
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 z-[2000] flex items-end sm:items-center justify-center bg-black/40" onClick={onClose}>
      <div className="bg-white rounded-t-2xl sm:rounded-2xl w-full sm:max-w-md p-5 max-h-[92vh] overflow-y-auto"
        onClick={e => e.stopPropagation()}>
        <h3 className="font-bold text-[#1F2A2E] text-base mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>
          Alerte cyanobactéries
        </h3>
        <p className="text-xs text-gray-500 mb-3">Cliquez sur la carte pour poser le point sur la zone d&apos;eau.</p>

        <div className="h-52 rounded-xl overflow-hidden mb-3">
          <MapContainer center={pt} zoom={15} style={{ height: '100%', width: '100%' }} scrollWheelZoom>
            <TileLayer url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
              attribution='&copy; OpenStreetMap' />
            <ClickCatcher onPick={(lat, lng) => setPt([lat, lng])} />
            <Marker position={pt} icon={PIN} />
          </MapContainer>
        </div>

        <div className="flex gap-2 mb-3">
          {(['suspecte', 'confirme'] as const).map(s => (
            <button key={s} onClick={() => setStatut(s)}
              className={`flex-1 py-2 rounded-lg text-xs font-semibold border transition-colors ${
                statut === s
                  ? (s === 'confirme' ? 'bg-red-600 border-red-600 text-white' : 'bg-amber-500 border-amber-500 text-white')
                  : 'border-gray-300 text-gray-600'}`}>
              {s === 'confirme' ? '✔️ Confirmé' : '❓ Suspecté'}
            </button>
          ))}
        </div>

        {statut === 'confirme' && (
          <div className="mb-3">
            <p className="text-xs text-gray-500 mb-1">Photo obligatoire pour confirmer.</p>
            <input type="file" accept="image/*"
              onChange={e => setPhoto(e.target.files?.[0] ?? null)}
              className="text-xs" />
            {(photo || current?.photo_url) && (
              <p className="text-xs text-green-700 mt-1">✓ {photo ? photo.name : 'photo existante'}</p>
            )}
          </div>
        )}

        <div className="flex gap-2">
          <button onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm text-gray-500 border border-gray-200">
            Annuler
          </button>
          <button onClick={save}
            disabled={saving || (statut === 'confirme' && !photo && !current?.photo_url)}
            className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white bg-red-600 disabled:opacity-40">
            {saving ? '…' : statut === 'confirme' ? 'Confirmer l’alerte' : 'Signaler l’alerte'}
          </button>
        </div>
      </div>
    </div>
  );
}
