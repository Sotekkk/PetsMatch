'use client';

import { useEffect, useState, useCallback } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { distanceKm } from '@/lib/geocoding';

function StatCard({ label, value, icon }: { label: string; value: string; icon: string }) {
  return (
    <div className="bg-white rounded-2xl p-4 flex-1 min-w-[140px]">
      <div className="text-xl">{icon}</div>
      <p className="text-xl font-bold text-[#1F2A2E] mt-2" style={{ fontFamily: 'Galey, sans-serif' }}>{value}</p>
      <p className="text-xs text-gray-500 mt-0.5">{label}</p>
    </div>
  );
}

export default function PhotographeDashboardPage() {
  const { user } = useAuth();
  const activeProfileId = useActiveProfile();
  const [loading, setLoading] = useState(true);
  const [nbShootings, setNbShootings] = useState(0);
  const [ca, setCa] = useState(0);
  const [kmCeMois, setKmCeMois] = useState(0);
  const [noteMoyenne, setNoteMoyenne] = useState(0);
  const [nbAvis, setNbAvis] = useState(0);

  const load = useCallback(async () => {
    if (!user?.uid) return;
    setLoading(true);
    try {
      const now = new Date();
      const startOfMonth = new Date(Date.UTC(now.getFullYear(), now.getMonth(), 1)).toISOString();

      const [shootingsRes, facturesRes, rdvsMoisRes, profilRes] = await Promise.all([
        supabase.from('rdv').select('id').eq('pro_uid', user.uid).eq('pro_profile_id', activeProfileId || '').eq('statut', 'termine'),
        supabase.from('photographe_factures').select('montant_total').eq('pro_uid', user.uid).eq('pro_profile_id', activeProfileId || '').eq('statut', 'payee'),
        supabase.from('rdv').select('lat_depart, lng_depart')
          .eq('pro_uid', user.uid).eq('pro_profile_id', activeProfileId || '').eq('statut', 'termine')
          .gte('date_heure', startOfMonth).not('lat_depart', 'is', null),
        activeProfileId
          ? supabase.from('user_profiles').select('lat, lng, note_moyenne, nb_avis').eq('id', activeProfileId).maybeSingle()
          : Promise.resolve({ data: null }),
      ]);

      const shootings = shootingsRes.data ?? [];
      const factures = facturesRes.data ?? [];
      const rdvsMois = rdvsMoisRes.data ?? [];
      const profil = profilRes.data as { lat: number | null; lng: number | null; note_moyenne: number | null; nb_avis: number | null } | null;

      const caTotal = factures.reduce((s, f) => s + (Number(f.montant_total) || 0), 0);

      let km = 0;
      if (profil?.lat != null && profil?.lng != null) {
        for (const r of rdvsMois) {
          if (r.lat_depart != null && r.lng_depart != null) {
            km += distanceKm(profil.lat, profil.lng, r.lat_depart, r.lng_depart);
          }
        }
      }

      setNbShootings(shootings.length);
      setCa(caTotal);
      setKmCeMois(km);
      setNoteMoyenne(profil?.note_moyenne ?? 0);
      setNbAvis(profil?.nb_avis ?? 0);
    } finally {
      setLoading(false);
    }
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  if (loading) return (
    <div className="flex justify-center items-center min-h-[60vh]">
      <div className="w-8 h-8 border-2 border-[#90A4AE] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  return (
    <div className="max-w-2xl mx-auto px-4 py-8">
      <h1 className="text-2xl font-bold text-[#1F2A2E] mb-6" style={{ fontFamily: 'Galey, sans-serif' }}>Tableau de bord</h1>
      <div className="flex flex-wrap gap-3">
        <StatCard label="Shootings réalisés" value={`${nbShootings}`} icon="📷" />
        <StatCard label="CA encaissé" value={`${ca.toFixed(0)} €`} icon="💶" />
        <StatCard label="Km ce mois-ci" value={`${kmCeMois.toFixed(0)} km`} icon="🚗" />
        <StatCard label="Note moyenne" value={nbAvis > 0 ? `${noteMoyenne.toFixed(1)} ★ (${nbAvis})` : '—'} icon="⭐" />
      </div>
      <p className="text-xs text-gray-400 mt-4">Chiffres calculés à la volée, pas de délai de synchronisation.</p>
    </div>
  );
}
