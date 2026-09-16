// Adresse connue du client réservant un RDV (à domicile) — pré-remplissage
// pour éviter une ressaisie. Miroir de _loadClientAdresse dans
// lib/pages/pro/rdv_booking_page.dart (app).
//
// Piège vérifié en base réelle : la colonne générique `rue/code_postal/ville`
// de user_profiles est l'adresse personnelle et est renseignée (avec lat/lng
// déjà géocodés) pour TOUS les types de profil, y compris éleveur — les
// colonnes dédiées `rue_elevage/code_postal_elevage/ville_elevage` sont en
// pratique quasi toujours NULL (rarement saisies séparément). On lit donc
// les colonnes génériques en priorité, et on ne bascule sur *_elevage
// (géocodées à la volée, pas de lat_elevage/lng_elevage) que si les
// génériques sont vides.
import { supabase } from '@/lib/supabase';
import { geocodeAddress } from '@/lib/geocoding';

export interface ClientKnownAddress {
  text: string;
  lat: number | null;
  lng: number | null;
}

export async function getClientKnownAddress(
  uid: string,
  activeProfileId: string | null | undefined
): Promise<ClientKnownAddress | null> {
  try {
    let row: Record<string, unknown> | null = null;
    if (activeProfileId) {
      const { data } = await supabase
        .from('user_profiles')
        .select('rue, ville, code_postal, pays, lat, lng, rue_elevage, ville_elevage, code_postal_elevage, pays_elevage')
        .eq('id', activeProfileId)
        .maybeSingle();
      row = data;
    }
    if (!row) {
      const { data } = await supabase
        .from('users')
        .select('rue, ville, code_postal, pays, lat, lng')
        .eq('uid', uid)
        .maybeSingle();
      row = data;
    }
    if (!row) return null;

    const genericParts = [row.rue, row.code_postal, row.ville]
      .map((v) => (v == null ? '' : String(v).trim()))
      .filter((s) => s.length > 0);
    if (genericParts.length > 0) {
      const lat = typeof row.lat === 'number' ? row.lat : null;
      const lng = typeof row.lng === 'number' ? row.lng : null;
      return { text: genericParts.join(', '), lat, lng };
    }

    const elevageParts = [row.rue_elevage, row.code_postal_elevage, row.ville_elevage]
      .map((v) => (v == null ? '' : String(v).trim()))
      .filter((s) => s.length > 0);
    if (elevageParts.length === 0) return null;
    const text = elevageParts.join(', ');
    const geo = await geocodeAddress(text);
    return { text, lat: geo?.lat ?? null, lng: geo?.lng ?? null };
  } catch {
    return null;
  }
}
