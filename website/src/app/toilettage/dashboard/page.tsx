'use client';

import { useEffect, useState, useCallback } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

function StatCard({ label, value, icon }: { label: string; value: string; icon: string }) {
  return (
    <div className="bg-white rounded-2xl p-4 flex-1 min-w-[140px]">
      <div className="text-xl">{icon}</div>
      <p className="text-xl font-bold text-[#1F2A2E] mt-2" style={{ fontFamily: 'Galey, sans-serif' }}>{value}</p>
      <p className="text-xs text-gray-500 mt-0.5">{label}</p>
    </div>
  );
}

export default function ToilettageDashboardPage() {
  const { user } = useAuth();
  const activeProfileId = useActiveProfile();
  const [loading, setLoading] = useState(true);
  const [nbRdv, setNbRdv] = useState(0);
  const [ca, setCa] = useState(0);
  const [dureeMoyenne, setDureeMoyenne] = useState(0);
  const [clientsFideles, setClientsFideles] = useState(0);
  const [noteMoyenne, setNoteMoyenne] = useState(0);
  const [nbAvis, setNbAvis] = useState(0);

  const load = useCallback(async () => {
    if (!user?.uid) return;
    setLoading(true);
    try {
      const [rdvsRes, facturesRes, profilRes] = await Promise.all([
        supabase.from('rdv').select('client_uid, duree_minutes')
          .eq('pro_uid', user.uid).eq('pro_profile_id', activeProfileId || '').eq('statut', 'termine'),
        supabase.from('toilettage_factures').select('montant').eq('pro_uid', user.uid).eq('pro_profile_id', activeProfileId || '').eq('statut', 'payee'),
        activeProfileId
          ? supabase.from('user_profiles').select('note_moyenne, nb_avis').eq('id', activeProfileId).maybeSingle()
          : Promise.resolve({ data: null }),
      ]);

      const rdvsTermines = rdvsRes.data ?? [];
      const factures = facturesRes.data ?? [];
      const profil = profilRes.data as { note_moyenne: number | null; nb_avis: number | null } | null;

      const caTotal = factures.reduce((s, f) => s + (Number(f.montant) || 0), 0);

      const durees = rdvsTermines.map(r => r.duree_minutes).filter((d): d is number => d != null);
      const dureeMoy = durees.length === 0 ? 0 : durees.reduce((a, b) => a + b, 0) / durees.length;

      const compteParClient = new Map<string, number>();
      for (const r of rdvsTermines) {
        if (!r.client_uid) continue;
        compteParClient.set(r.client_uid, (compteParClient.get(r.client_uid) ?? 0) + 1);
      }
      const fideles = [...compteParClient.values()].filter(n => n >= 3).length;

      setNbRdv(rdvsTermines.length);
      setCa(caTotal);
      setDureeMoyenne(dureeMoy);
      setClientsFideles(fideles);
      setNoteMoyenne(profil?.note_moyenne ?? 0);
      setNbAvis(profil?.nb_avis ?? 0);
    } finally {
      setLoading(false);
    }
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  if (loading) return (
    <div className="flex justify-center items-center min-h-[60vh]">
      <div className="w-8 h-8 border-2 border-[#FFB74D] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  return (
    <div className="max-w-2xl mx-auto px-4 py-8">
      <h1 className="text-2xl font-bold text-[#1F2A2E] mb-6" style={{ fontFamily: 'Galey, sans-serif' }}>Tableau de bord</h1>
      <div className="flex flex-wrap gap-3">
        <StatCard label="RDV terminés" value={`${nbRdv}`} icon="✂️" />
        <StatCard label="CA encaissé" value={`${ca.toFixed(0)} €`} icon="💶" />
        <StatCard label="Temps moyen" value={dureeMoyenne > 0 ? `${dureeMoyenne.toFixed(0)} min` : '—'} icon="⏱️" />
        <StatCard label="Clients fidèles" value={`${clientsFideles}`} icon="❤️" />
        <StatCard label="Note moyenne" value={nbAvis > 0 ? `${noteMoyenne.toFixed(1)} ★ (${nbAvis})` : '—'} icon="⭐" />
      </div>
      <p className="text-xs text-gray-400 mt-4">Chiffres calculés à la volée, pas de délai de synchronisation.</p>
    </div>
  );
}
