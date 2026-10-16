'use client';
// Mes galeries photo (client) : galeries privées que des photographes ont
// partagées sur le compte du profil actif. Miroir appli : mes_galeries_photo_page.dart.
import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

interface Galerie { id: string; titre: string | null; date_seance: string | null; pro_profile_id: string | null; client_profile_id: string | null; partagee_le: string | null }

export default function MesGaleriesPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const pid = useActiveProfile();
  const [galeries, setGaleries] = useState<Galerie[] | null>(null);
  const [studios, setStudios] = useState<Record<string, string>>({});

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);
  useEffect(() => {
    if (!user) return;
    (async () => {
      // RLS : seules les galeries partagées sur MON compte sont lisibles.
      const { data } = await supabase.from('albums_photo').select('id, titre, date_seance, pro_profile_id, client_profile_id, partagee_le')
        .eq('client_uid', user.uid).eq('partage_client', true).neq('statut', 'archivee').order('updated_at', { ascending: false });
      // Profil actif : galeries de ce profil (ou sans profil précis).
      const liste = ((data ?? []) as Galerie[]).filter(g => !pid || !g.client_profile_id || g.client_profile_id === pid);
      const ids = [...new Set(liste.map(g => g.pro_profile_id).filter(Boolean) as string[])];
      const { data: pros } = ids.length ? await supabase.from('user_profiles_complet').select('id, nom, firstname, lastname').in('id', ids) : { data: [] };
      setStudios(Object.fromEntries(((pros ?? []) as { id: string; nom?: string; firstname?: string; lastname?: string }[])
        .map(p => [p.id, (p.nom ?? '').trim() || `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim()])));
      setGaleries(liste);
    })();
  }, [user, pid]);

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-4xl mx-auto px-4 py-6">
        <h1 className="text-xl font-bold text-[#1F2A2E] mb-4">Mes galeries photo</h1>
        {galeries === null ? <div className="flex justify-center py-16"><div className="w-7 h-7 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>
          : galeries.length === 0 ? <p className="text-sm text-gray-400 text-center py-16">Aucune galerie partagée pour le moment. Votre photographe vous préviendra dès qu&apos;une galerie sera disponible.</p> : (
          <div className="grid sm:grid-cols-2 gap-3">
            {galeries.map(g => (
              <Link key={g.id} href={`/galerie/${g.id}`} className="bg-white rounded-2xl border border-gray-100 p-4 hover:shadow-md transition-shadow">
                <p className="font-bold text-sm text-[#1F2A2E]">{g.titre ?? 'Galerie'}</p>
                <p className="text-xs text-gray-500 mt-1">{[g.pro_profile_id ? studios[g.pro_profile_id] : '', g.date_seance ? new Date(g.date_seance).toLocaleDateString('fr-FR') : ''].filter(Boolean).join(' · ')}</p>
              </Link>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
