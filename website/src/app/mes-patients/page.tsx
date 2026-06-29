'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

function clientsPageTitle(catPro: string): string {
  if (catPro === 'veterinaire' || catPro === 'sante') return 'Mes patients';
  if (catPro === 'marechal_ferrant') return 'Mes équidés suivis';
  if (catPro === 'education') return 'Mes élèves';
  return 'Animaux suivis';
}

interface Animal {
  id: number;
  nom: string;
  espece: string;
  race: string;
  date_naissance: string | null;
  photo_url: string | null;
}

interface Grant {
  id: string;
  animal_id: number;
  statut: string;
  granted_at: string;
  animal: Animal | null;
}

const ESPECE_EMOJI: Record<string, string> = {
  chien: '🐕', chat: '🐈', cheval: '🐴', lapin: '🐰',
  oiseau: '🦜', nac: '🦎', ovin: '🐑', caprin: '🐐', porcin: '🐷',
};

function age(dateNaissance: string | null): string {
  if (!dateNaissance) return '';
  const birth = new Date(dateNaissance);
  const now = new Date();
  const months = (now.getFullYear() - birth.getFullYear()) * 12 + now.getMonth() - birth.getMonth();
  if (months < 24) return `${months} mois`;
  return `${Math.floor(months / 12)} ans`;
}

export default function MesPatientsPage() {
  const { user, userData } = useAuth();
  const router = useRouter();
  const activeProfileId = useActiveProfile();
  const [grants, setGrants] = useState<Grant[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [catPro, setCatPro] = useState('');

  useEffect(() => {
    if (activeProfileId) {
      supabase.from('user_profiles').select('profile_type, cat_pro').eq('id', activeProfileId).single()
        .then(({ data }) => { if (data) { const r = data as { profile_type: string; cat_pro: string }; setCatPro(r.profile_type ?? r.cat_pro ?? ''); } });
    } else {
      setCatPro(userData?.catPro ?? '');
    }
  }, [activeProfileId, userData]);

  useEffect(() => {
    if (!user || !activeProfileId) return;
    async function load() {
      const { data: grantRows, error: grantErr } = await supabase
        .from('animal_access')
        .select('id, animal_id, statut, granted_at')
        .eq('pro_profile_id', activeProfileId)
        .neq('statut', 'revoked')
        .order('granted_at', { ascending: false });

      if (grantErr) {
        console.error('[mes-patients] grants error msg:', grantErr.message);
        console.error('[mes-patients] grants error code:', grantErr.code);
        console.error('[mes-patients] grants error details:', grantErr.details);
        console.error('[mes-patients] grants error hint:', grantErr.hint);
        setLoading(false);
        return;
      }
      if (!grantRows || grantRows.length === 0) {
        console.log('[mes-patients] no grants for profile:', activeProfileId);
        setLoading(false);
        return;
      }

      const animalIds = grantRows.map(g => g.animal_id).filter(Boolean);
      const { data: animalRows, error: animalErr } = await supabase
        .from('animaux')
        .select('id, nom, espece, race, date_naissance, photo_url')
        .in('id', animalIds);

      if (animalErr) console.error('[mes-patients] animaux error:', animalErr);

      const animalMap = new Map((animalRows ?? []).map(a => [a.id, a]));
      const merged = grantRows.map(g => ({
        ...g,
        animal: animalMap.get(g.animal_id) ?? null,
      }));
      setGrants(merged as unknown as Grant[]);
      setLoading(false);
    }
    load();
  }, [user, activeProfileId]);

  if (!user) return (
    <div className="min-h-screen flex items-center justify-center text-gray-400 text-sm">
      Connectez-vous pour accéder à vos patients.
    </div>
  );

  const filtered = grants.filter(g => {
    if (!g.animal) return false;
    if (!search) return true;
    return g.animal.nom.toLowerCase().includes(search.toLowerCase()) ||
      g.animal.espece.toLowerCase().includes(search.toLowerCase()) ||
      g.animal.race.toLowerCase().includes(search.toLowerCase());
  });

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Header */}
      <div className="bg-[#0C5C6C] text-white px-4 py-6">
        <div className="max-w-3xl mx-auto flex items-center gap-3">
          <button onClick={() => router.back()} className="p-2 rounded-lg bg-white/10 hover:bg-white/20 transition-colors">
            ←
          </button>
          <div>
            <h1 className="text-xl font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>{clientsPageTitle(catPro)}</h1>
            <p className="text-white/60 text-xs">{grants.length} animal{grants.length !== 1 ? 'aux' : ''} avec accès accordé</p>
          </div>
        </div>
      </div>

      <div className="max-w-3xl mx-auto px-4 py-6">
        {/* Recherche */}
        <div className="mb-4">
          <input
            value={search} onChange={e => setSearch(e.target.value)}
            placeholder="Rechercher un patient…"
            className="w-full bg-white border border-gray-200 rounded-2xl px-4 py-3 text-sm focus:outline-none focus:border-[#0C5C6C] shadow-sm"
            style={{ fontFamily: 'Galey, sans-serif' }}
          />
        </div>

        {loading ? (
          <div className="flex justify-center py-20">
            <div className="w-8 h-8 border-4 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : filtered.length === 0 ? (
          <div className="text-center py-20">
            <p className="text-4xl mb-3">🐾</p>
            <p className="text-gray-500 text-sm font-medium" style={{ fontFamily: 'Galey, sans-serif' }}>
              {search ? 'Aucun résultat' : 'Aucun patient pour l\'instant'}
            </p>
            <p className="text-gray-400 text-xs mt-1">
              Les propriétaires vous accordent l&apos;accès depuis la fiche de leur animal
            </p>
          </div>
        ) : (
          <div className="space-y-2">
            {filtered.map(g => {
              const a = g.animal;
              if (!a) return null;
              return (
                <Link key={g.id} href={`/mes-patients/${a.id}`}
                  className="bg-white rounded-2xl border border-gray-100 shadow-sm px-4 py-3 flex items-center gap-4 hover:shadow-md transition-shadow">
                  <div className="w-14 h-14 rounded-2xl overflow-hidden bg-[#E3F2FD] flex-shrink-0 flex items-center justify-center">
                    {a.photo_url
                      ? <Image src={a.photo_url} alt="" width={56} height={56} className="object-cover w-full h-full" />
                      : <span className="text-2xl">{ESPECE_EMOJI[a.espece?.toLowerCase()] ?? '🐾'}</span>
                    }
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-bold text-sm text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>{a.nom}</p>
                    <p className="text-xs text-gray-500">{a.race || a.espece}{a.date_naissance ? ` · ${age(a.date_naissance)}` : ''}</p>
                    <span className="text-[10px] font-bold text-green-600 bg-green-50 px-1.5 py-0.5 rounded-full">
                      Accès accordé
                    </span>
                  </div>
                  <span className="text-gray-300 text-lg">›</span>
                </Link>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}
