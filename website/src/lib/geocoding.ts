// Géocodage d'adresse (web) — utilise l'API gratuite api-adresse.data.gouv.fr,
// déjà le pattern employé par AddressAutocomplete.tsx. Miroir de
// lib/utils/geocoding_helper.dart (app), même heuristique de distance
// (haversine) pour rester cohérent entre les deux plateformes.

export async function geocodeAddress(address: string): Promise<{ lat: number; lng: number } | null> {
  const q = address.trim();
  if (!q) return null;
  try {
    const res = await fetch(`https://api-adresse.data.gouv.fr/search/?q=${encodeURIComponent(q)}&limit=1`);
    if (!res.ok) return null;
    const data = await res.json();
    const feature = data?.features?.[0];
    if (!feature) return null;
    const [lng, lat] = feature.geometry.coordinates as [number, number];
    return { lat, lng };
  } catch {
    return null;
  }
}

// Distance à vol d'oiseau en km (formule de haversine).
export function distanceKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c;
}
