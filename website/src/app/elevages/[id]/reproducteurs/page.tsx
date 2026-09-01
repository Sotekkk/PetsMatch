'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import Image from 'next/image';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { ESPECE_LABEL, ESPECE_EMOJI, UUID_RE, ageLabel, sexeSymbol, type Repro } from '@/lib/repro';

export default function ReproducteursPage() {
  const params = useParams();
  const id = String(params.id ?? '');
  const [repros, setRepros] = useState<Repro[]>([]);
  const [nomElevage, setNomElevage] = useState('');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!id) return;
    (async () => {
      // 1. UID Firebase de l'éleveur
      let euid = id;
      if (UUID_RE.test(id)) {
        const { data } = await supabase.from('user_profiles').select('uid').eq('id', id).maybeSingle();
        euid = (data?.uid as string) ?? id;
      }
      // 2. Profil ÉLEVEUR uniquement (jamais un autre profil du même compte)
      const { data: prof } = await supabase.from('user_profiles')
        .select('id, nom, montre_reproducteurs')
        .eq('uid', euid).eq('profile_type', 'eleveur').maybeSingle();
      setNomElevage((prof?.nom as string) ?? '');
      if (!prof?.id || prof.montre_reproducteurs !== true) { setRepros([]); setLoading(false); return; }
      // 3. Reproducteurs publics
      const { data: rows } = await supabase.from('animaux')
        .select('id, nom, nom_pedigree, espece, race, sexe, photo_url, date_naissance, '
          + 'couleur, pedigree_lof, pedigree_numero, club_registre, description, is_retraite')
        .eq('profile_id', prof.id).eq('uid_eleveur', euid).eq('reproducteur_public', true)
        .order('espece').order('race').order('nom');
      setRepros((rows ?? []) as unknown as Repro[]);
      setLoading(false);
    })();
  }, [id]);

  // { espèce : { race : Repro[] } }
  const grouped: Record<string, Record<string, Repro[]>> = {};
  for (const r of repros) {
    const esp = r.espece || 'autre';
    const race = (r.race && r.race.trim()) || 'Sans race renseignée';
    (grouped[esp] ??= {})[race] ??= [];
    grouped[esp][race].push(r);
  }

  return (
    <div className="min-h-screen bg-[#F5F5F0]">
      <div className="max-w-3xl mx-auto px-4 py-6">
        <Link href={`/elevages/${id}`} className="text-[#0C5C6C] text-sm font-semibold hover:underline">
          ← Retour au profil
        </Link>
        <h1 className="font-['Galey'] font-bold text-2xl text-[#1F2A2E] mt-2 mb-1">Reproducteurs</h1>
        {nomElevage && <p className="text-gray-500 text-sm mb-5">{nomElevage}</p>}

        {loading ? (
          <p className="text-gray-400 text-sm py-12 text-center">Chargement…</p>
        ) : repros.length === 0 ? (
          <p className="text-gray-400 text-sm text-center py-12 bg-white rounded-2xl shadow-sm">
            Aucun reproducteur affiché.
          </p>
        ) : (
          Object.entries(grouped).map(([esp, races]) => (
            <section key={esp} className="mb-8">
              <h2 className="font-['Galey'] font-bold text-lg text-[#1F2A2E] mb-2">
                {ESPECE_EMOJI[esp] ?? '🐾'} {ESPECE_LABEL[esp] ?? esp}
              </h2>
              {Object.entries(races).map(([race, list]) => (
                <div key={race} className="mb-4">
                  <p className="text-xs font-semibold text-gray-500 mb-2">{race}</p>
                  <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
                    {list.map(r => (
                      <Link key={r.id} href={`/elevages/${id}/reproducteurs/${r.id}`}
                        className="bg-white rounded-xl shadow-sm border border-gray-100 overflow-hidden hover:shadow-md transition-shadow block">
                        <div className="aspect-square bg-[#F5F5F0] relative">
                          {r.photo_url ? (
                            <Image src={r.photo_url} alt={r.nom ?? ''} fill className="object-cover" sizes="(max-width:640px) 50vw, 200px" />
                          ) : (
                            <div className="w-full h-full flex items-center justify-center text-4xl">
                              {ESPECE_EMOJI[r.espece ?? ''] ?? '🐾'}
                            </div>
                          )}
                          {r.is_retraite && (
                            <span className="absolute top-1.5 left-1.5 bg-[#B45309] text-white text-[9px] font-semibold px-1.5 py-0.5 rounded-full">
                              Retraité
                            </span>
                          )}
                          {sexeSymbol(r.sexe) && (
                            <span className="absolute top-1.5 right-1.5 bg-[#0C5C6C]/90 text-white text-[11px] font-bold w-5 h-5 rounded-full flex items-center justify-center">
                              {sexeSymbol(r.sexe)}
                            </span>
                          )}
                        </div>
                        <div className="p-2.5">
                          <p className="font-semibold text-[#1F2A2E] text-xs truncate">{r.nom ?? 'Sans nom'}</p>
                          {r.nom_pedigree && (
                            <p className="text-gray-400 text-[10px] truncate">{r.nom_pedigree}</p>
                          )}
                          <p className="text-gray-500 text-[11px] mt-0.5 truncate">
                            {[r.race, ageLabel(r.date_naissance)].filter(Boolean).join(' · ')}
                          </p>
                        </div>
                      </Link>
                    ))}
                  </div>
                </div>
              ))}
            </section>
          ))
        )}
      </div>
    </div>
  );
}
