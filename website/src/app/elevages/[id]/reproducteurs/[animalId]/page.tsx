'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import Image from 'next/image';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { ESPECE_LABEL, UUID_RE, ageLabel, type Repro } from '@/lib/repro';
import { offspringWord, resultatChipClass, testChipLabel, type TestGenetique } from '@/lib/genetics';

function fmtDate(iso?: string | null) {
  if (!iso) return '';
  const d = new Date(iso);
  return isNaN(d.getTime()) ? '' : d.toLocaleDateString('fr-FR');
}

export default function ReproDetailPage() {
  const params = useParams();
  const id = String(params.id ?? '');
  const animalId = String(params.animalId ?? '');
  const [repro, setRepro] = useState<Repro | null>(null);
  const [tests, setTests] = useState<TestGenetique[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!id || !animalId) return;
    (async () => {
      let euid = id;
      if (UUID_RE.test(id)) {
        const { data } = await supabase.from('user_profiles').select('uid').eq('id', id).maybeSingle();
        euid = (data?.uid as string) ?? id;
      }
      const { data: prof } = await supabase.from('user_profiles')
        .select('id, montre_reproducteurs')
        .eq('uid', euid).eq('profile_type', 'eleveur').maybeSingle();
      if (!prof?.id || prof.montre_reproducteurs !== true) { setLoading(false); return; }

      const { data: a } = await supabase.from('animaux')
        .select('id, nom, nom_pedigree, espece, race, sexe, photo_url, date_naissance, '
          + 'couleur, pedigree_lof, pedigree_numero, club_registre, description, is_retraite, '
          + 'nb_petits_produits, historique_fertilite, profil_adn_etabli')
        .eq('id', animalId).eq('profile_id', prof.id).eq('uid_eleveur', euid)
        .eq('reproducteur_public', true).maybeSingle();
      if (!a) { setLoading(false); return; }
      setRepro(a as unknown as Repro);

      const { data: tg } = await supabase.from('tests_genetiques')
        .select('categorie, code, nom, resultat, genotype').eq('animal_id', animalId);
      setTests((tg ?? []) as TestGenetique[]);
      setLoading(false);
    })();
  }, [id, animalId]);

  if (loading) {
    return <p className="text-center text-gray-400 text-sm py-20">Chargement…</p>;
  }
  if (!repro) {
    return (
      <div className="max-w-lg mx-auto px-4 py-20 text-center">
        <p className="text-gray-500 mb-4">Reproducteur introuvable.</p>
        <Link href={`/elevages/${id}/reproducteurs`} className="text-[#0C5C6C] font-semibold hover:underline">
          ← Retour aux reproducteurs
        </Link>
      </div>
    );
  }

  const line = (label: string, value?: string | null) =>
    value && value.trim() ? (
      <div className="flex gap-3 py-1.5 text-sm">
        <span className="w-36 shrink-0 text-gray-500">{label}</span>
        <span className="font-semibold text-[#1F2A2E]">{value}</span>
      </div>
    ) : null;

  const naissance = repro.date_naissance
    ? `${fmtDate(repro.date_naissance)}${ageLabel(repro.date_naissance) ? `  ·  ${ageLabel(repro.date_naissance)}` : ''}`
    : '';
  const sexe = (repro.sexe ?? '').toLowerCase().startsWith('m')
    ? 'Mâle'
    : (repro.sexe ?? '').toLowerCase().startsWith('f') ? 'Femelle' : (repro.sexe ?? '');

  return (
    <div className="min-h-screen bg-[#F5F5F0]">
      <div className="max-w-2xl mx-auto px-4 py-6">
        <Link href={`/elevages/${id}/reproducteurs`} className="text-[#0C5C6C] text-sm font-semibold hover:underline">
          ← Tous les reproducteurs
        </Link>

        <div className="bg-white rounded-2xl shadow-sm overflow-hidden mt-3">
          <div className="relative aspect-[4/3] bg-[#EEF5EA]">
            {repro.photo_url ? (
              <Image src={repro.photo_url} alt={repro.nom ?? ''} fill className="object-cover" sizes="(max-width:768px) 100vw, 640px" />
            ) : (
              <div className="w-full h-full flex items-center justify-center text-6xl">🐾</div>
            )}
            {repro.is_retraite && (
              <span className="absolute top-3 left-3 bg-[#B45309] text-white text-xs font-semibold px-2 py-1 rounded-lg">
                Retraité
              </span>
            )}
          </div>

          <div className="p-5">
            <h1 className="font-['Galey'] font-bold text-2xl text-[#1F2A2E]">{repro.nom ?? 'Reproducteur'}</h1>
            {repro.nom_pedigree && <p className="text-gray-500 text-sm mt-0.5">{repro.nom_pedigree}</p>}

            <div className="mt-4 divide-y divide-gray-100">
              {line('Espèce', ESPECE_LABEL[repro.espece ?? ''] ?? repro.espece)}
              {line('Race', repro.race)}
              {line('Sexe', sexe)}
              {line('Naissance', naissance)}
              {line('Couleur / robe', repro.couleur)}
              {line('N° LOF / pedigree', [repro.pedigree_lof, repro.pedigree_numero].filter(Boolean).join(' · '))}
              {line('Club / registre', repro.club_registre)}
            </div>

            {repro.description && (
              <div className="mt-5">
                <h2 className="font-['Galey'] font-bold text-[#1F2A2E] text-sm mb-1">Présentation</h2>
                <p className="text-sm text-gray-700 leading-relaxed whitespace-pre-line">{repro.description}</p>
              </div>
            )}

            {(() => {
              const maladies = tests.filter(t => t.categorie === 'maladie');
              const robes = tests.filter(t => t.categorie === 'robe');
              const adnEtabli = repro.profil_adn_etabli === true
                || tests.some(t => t.categorie === 'adn' && t.resultat === 'etabli');
              if (maladies.length === 0 && robes.length === 0 && !adnEtabli) return null;
              return (
                <div className="mt-5">
                  <h2 className="font-['Galey'] font-bold text-[#1F2A2E] text-sm mb-2">Statut génétique</h2>
                  <div className="flex flex-wrap gap-2">
                    {adnEtabli && (
                      <span className="inline-flex items-center gap-1.5 bg-[#EEF5EA] text-[#4d7a3c] text-xs font-semibold px-2.5 py-1 rounded-full">
                        ✓ Profil ADN établi
                      </span>
                    )}
                    {maladies.map((t, i) => (
                      <span key={i} className={`inline-flex items-center text-xs font-semibold px-2.5 py-1 rounded-full ${resultatChipClass(t.resultat)}`}>
                        {testChipLabel(t)}
                      </span>
                    ))}
                  </div>
                  {robes.length > 0 && (
                    <p className="text-xs text-gray-500 mt-2">
                      Robe : {robes.map(t => `${t.nom}${t.genotype ? ` ${t.genotype}` : ''}`).join(' · ')}
                    </p>
                  )}
                </div>
              );
            })()}

            {(repro.nb_petits_produits != null || (repro.historique_fertilite ?? '').trim()) && (
              <div className="mt-5">
                <h2 className="font-['Galey'] font-bold text-[#1F2A2E] text-sm mb-1">Fertilité</h2>
                {repro.nb_petits_produits != null && (
                  <p className="text-sm font-semibold text-[#1F2A2E] capitalize">
                    {repro.nb_petits_produits} {offspringWord(repro.espece)} produits
                  </p>
                )}
                {(repro.historique_fertilite ?? '').trim() && (
                  <p className="text-sm text-gray-700 leading-relaxed whitespace-pre-line mt-1">{repro.historique_fertilite}</p>
                )}
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
