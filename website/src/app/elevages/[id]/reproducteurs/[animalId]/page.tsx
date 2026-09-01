'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import Image from 'next/image';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { ESPECE_LABEL, UUID_RE, ageLabel, type Repro } from '@/lib/repro';

const TEST_LABEL: Record<string, string> = {
  adn: 'Test ADN', hanches: 'Test hanches',
  sante_repro: 'Santé reproducteur', filiation: 'Filiation',
};

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
  const [tests, setTests] = useState<string[]>([]);
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
          + 'couleur, pedigree_lof, pedigree_numero, club_registre, description, is_retraite')
        .eq('id', animalId).eq('profile_id', prof.id).eq('uid_eleveur', euid)
        .eq('reproducteur_public', true).maybeSingle();
      if (!a) { setLoading(false); return; }
      setRepro(a as unknown as Repro);

      const { data: docs } = await supabase.from('documents_animaux')
        .select('type').eq('animal_id', animalId).in('type', Object.keys(TEST_LABEL));
      setTests([...new Set((docs ?? []).map(d => d.type as string))]);
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

            {tests.length > 0 && (
              <div className="mt-5">
                <h2 className="font-['Galey'] font-bold text-[#1F2A2E] text-sm mb-2">Tests renseignés</h2>
                <div className="flex flex-wrap gap-2">
                  {tests.map(t => (
                    <span key={t} className="inline-flex items-center gap-1.5 bg-[#EEF5EA] text-[#4d7a3c] text-xs font-semibold px-2.5 py-1 rounded-full">
                      ✓ {TEST_LABEL[t] ?? t}
                    </span>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
