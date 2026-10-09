'use client';

// Clinique vétérinaire — comptes rendus rédigés par un(e) ASV, à valider
// (miroir appli : cr_a_valider_page.dart). Scopé au profil clinique actif ;
// un vétérinaire employé l'ouvre au nom de la clinique (?clinique=<profil>).
import FormuleVetRequise from '@/components/pro/FormuleVetRequise';
import { useCallback, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfileState } from '@/hooks/useActiveProfile';

interface Cr {
  id: string; animal_id: string | null; contenu: string | null; created_at: string;
  redige_par_profile_id: string | null; _animal?: string; _auteur?: string;
}

function CrAValiderContenu() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const { id: activeProfileId, loaded } = useActiveProfileState();
  const [cliniqueParam, setCliniqueParam] = useState<string | null>(null);
  const [crs, setCrs] = useState<Cr[]>([]);
  const [fetching, setFetching] = useState(true);
  const [ouvert, setOuvert] = useState<string | null>(null);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);
  useEffect(() => { setCliniqueParam(new URLSearchParams(window.location.search).get('clinique')); }, []);
  const profilClinique = cliniqueParam || activeProfileId;

  const load = useCallback(async () => {
    if (!user || !loaded || !profilClinique) { setFetching(false); return; }
    setFetching(true);
    const { data } = await supabase.from('comptes_rendus')
      .select('id, animal_id, contenu, created_at, redige_par_profile_id')
      .eq('pro_profile_id', profilClinique).eq('statut', 'brouillon')
      .order('created_at', { ascending: false });
    const rows = (data ?? []) as Cr[];
    const aIds = [...new Set(rows.map(r => r.animal_id).filter(Boolean))] as string[];
    const pIds = [...new Set(rows.map(r => r.redige_par_profile_id).filter(Boolean))] as string[];
    const an: Record<string, string> = {}; const au: Record<string, string> = {};
    if (aIds.length) (await supabase.from('animaux').select('id, nom').in('id', aIds)).data?.forEach(a => { an[a.id as string] = (a.nom as string) ?? ''; });
    if (pIds.length) (await supabase.from('user_profiles_complet').select('id, firstname, lastname, nom').in('id', pIds)).data
      ?.forEach(p => { au[p.id as string] = `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim() || (p.nom as string) || ''; });
    rows.forEach(r => { r._animal = an[r.animal_id ?? ''] ?? 'Animal'; r._auteur = au[r.redige_par_profile_id ?? ''] ?? ''; });
    setCrs(rows);
    setFetching(false);
  }, [user, loaded, profilClinique]);

  useEffect(() => { load(); }, [load]);

  async function valider(cr: Cr) {
    // Profil du validateur : profil actif (gérant) ; employé → son profil
    // particulier est renseigné côté base via valide_par_uid.
    const { error } = await supabase.from('comptes_rendus').update({
      statut: 'valide',
      ...(!cliniqueParam && activeProfileId ? { valide_par_profile_id: activeProfileId } : {}),
    }).eq('id', cr.id);
    if (error) { alert(error.message); return; }
    setCrs(prev => prev.filter(x => x.id !== cr.id));
  }

  if (loading || fetching) return (
    <div className="flex justify-center items-center min-h-[60vh]">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  return (
    <div className="max-w-2xl mx-auto px-4 py-8 space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-[#1F2A2E] font-galey">📝 Comptes rendus à valider</h1>
        <p className="text-sm text-gray-500 mt-0.5">Rédigés par vos assistant(e)s — visibles par le propriétaire une fois validés</p>
      </div>
      {crs.length === 0 ? (
        <div className="text-center py-16 border-2 border-dashed border-gray-200 rounded-2xl text-gray-400">
          <div className="text-5xl mb-3">✅</div>
          <p className="font-medium">Aucun compte rendu en attente</p>
        </div>
      ) : (
        <div className="space-y-3">
          {crs.map(cr => (
            <div key={cr.id} className="bg-white border border-gray-100 rounded-2xl p-4 shadow-sm">
              <div className="flex items-center gap-2">
                <p className="font-semibold text-[#1F2A2E] text-sm flex-1">🐾 {cr._animal}</p>
                <span className="text-xs text-gray-400">{new Date(cr.created_at).toLocaleDateString('fr-FR')}</span>
              </div>
              {cr._auteur && <p className="text-xs text-gray-500">Rédigé par {cr._auteur}</p>}
              <p className={`text-sm text-[#1F2A2E] mt-2 whitespace-pre-wrap ${ouvert === cr.id ? '' : 'line-clamp-3'}`}>{cr.contenu}</p>
              <div className="flex items-center gap-3 mt-3">
                <button onClick={() => setOuvert(ouvert === cr.id ? null : cr.id)} className="text-xs text-[#0C5C6C] underline">
                  {ouvert === cr.id ? 'Réduire' : 'Lire en entier'}
                </button>
                {cr.animal_id && !cliniqueParam && (
                  <a href={`/mes-patients/${cr.animal_id}`} className="text-xs text-[#0C5C6C] underline">Fiche du patient</a>
                )}
                <button onClick={() => valider(cr)}
                  className="ml-auto text-xs font-semibold text-white bg-[#0C5C6C] rounded-full px-4 py-1.5">
                  Valider et envoyer
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// Validation des CR rédigés par l'équipe (ASV) : dès la formule Avancé.
export default function CrAValiderPage() {
  return <FormuleVetRequise requise="avance" fonction="Comptes rendus à valider"><CrAValiderContenu /></FormuleVetRequise>;
}
