'use client';

import { useEffect, useState } from 'react';
import { useParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';

interface Animal {
  id: string;
  nom?: string;
  espece?: string;
  race?: string;
  sexe?: string;
  date_naissance?: string;
  identification?: string;
  photo_url?: string;
  description?: string;
  notes?: string;
  couleur?: string;
  poids?: number;
  taille?: number;
}

interface PartageRow {
  animal_id: string;
  expire_at: string;
  actif: boolean;
}

type State =
  | { status: 'loading' }
  | { status: 'expired' }
  | { status: 'invalid' }
  | { status: 'ok'; animal: Animal };

const ESPECE_EMOJI: Record<string, string> = {
  chien: '🐶', chat: '🐱', equide: '🐴', lapin: '🐰',
  oiseau: '🦜', reptile: '🦎', autre: '🐾',
};

export default function PartageAnimalPage() {
  const { token } = useParams<{ token: string }>();
  const [state, setState] = useState<State>({ status: 'loading' });

  useEffect(() => {
    if (!token) { setState({ status: 'invalid' }); return; }
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [token]);

  async function load() {
    try {
      const { data: partage, error } = await supabase
        .from('partage_animal')
        .select('animal_id, expire_at, actif')
        .eq('token', token)
        .single();

      if (error || !partage) { setState({ status: 'invalid' }); return; }

      const row = partage as PartageRow;
      if (!row.actif || new Date(row.expire_at) < new Date()) {
        setState({ status: 'expired' }); return;
      }

      const { data: animal, error: aErr } = await supabase
        .from('animaux')
        .select('id, nom, espece, race, sexe, date_naissance, identification, photo_url, description, notes, couleur, poids, taille')
        .eq('id', row.animal_id)
        .single();

      if (aErr || !animal) { setState({ status: 'invalid' }); return; }

      setState({ status: 'ok', animal: animal as Animal });
    } catch {
      setState({ status: 'invalid' });
    }
  }

  if (state.status === 'loading') {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="text-center">
          <div className="w-10 h-10 border-4 border-green-500 border-t-transparent rounded-full animate-spin mx-auto mb-3" />
          <p className="text-gray-500 font-medium">Chargement de la fiche…</p>
        </div>
      </div>
    );
  }

  if (state.status === 'expired') {
    return <_ErrorPage icon="⏰" title="Lien expiré" message="Ce lien de partage n'est plus valide. Demandez un nouveau lien à son propriétaire." />;
  }

  if (state.status === 'invalid') {
    return <_ErrorPage icon="🔒" title="Lien invalide" message="Ce lien de partage est introuvable ou a été désactivé." />;
  }

  const { animal } = state;
  const emoji = ESPECE_EMOJI[animal.espece ?? 'autre'] ?? '🐾';

  const age = animal.date_naissance
    ? (() => {
        const diff = Date.now() - new Date(animal.date_naissance).getTime();
        const months = Math.floor(diff / (1000 * 60 * 60 * 24 * 30.44));
        if (months < 2) return `${Math.floor(diff / (1000 * 60 * 60 * 24))} jours`;
        if (months < 24) return `${months} mois`;
        return `${Math.floor(months / 12)} ans`;
      })()
    : null;

  return (
    <div className="min-h-screen bg-gradient-to-b from-green-50 to-white">
      {/* Header PetsMatch */}
      <div className="bg-white border-b border-gray-100 px-4 py-3 flex items-center gap-2">
        <span className="text-xl font-bold text-green-700" style={{ fontFamily: 'Galey, sans-serif' }}>
          PetsMatch
        </span>
        <span className="text-xs text-gray-400 bg-gray-100 px-2 py-0.5 rounded-full ml-auto">
          Fiche partagée · lecture seule
        </span>
      </div>

      <div className="max-w-md mx-auto px-4 py-8">
        {/* Photo + identité */}
        <div className="bg-white rounded-3xl shadow-sm border border-gray-100 overflow-hidden mb-4">
          {animal.photo_url ? (
            <div className="relative w-full h-56">
              <img
                src={animal.photo_url}
                alt={animal.nom ?? 'Animal'}
                className="w-full h-full object-cover"
              />
            </div>
          ) : (
            <div className="w-full h-40 bg-green-50 flex items-center justify-center text-7xl">
              {emoji}
            </div>
          )}

          <div className="p-5">
            <div className="flex items-start justify-between mb-1">
              <h1 className="text-2xl font-bold text-gray-900" style={{ fontFamily: 'Galey, sans-serif' }}>
                {animal.nom ?? 'Sans nom'}
              </h1>
              <span className="text-2xl">{emoji}</span>
            </div>
            {animal.race && (
              <p className="text-green-700 font-medium text-sm mb-3">{animal.race}</p>
            )}

            <div className="grid grid-cols-2 gap-3 mt-3">
              {animal.espece && <_InfoChip label="Espèce" value={_capitalize(animal.espece)} />}
              {animal.sexe && <_InfoChip label="Sexe" value={_capitalize(animal.sexe)} />}
              {age && <_InfoChip label="Âge" value={age} />}
              {animal.couleur && <_InfoChip label="Couleur" value={animal.couleur} />}
              {animal.poids && <_InfoChip label="Poids" value={`${animal.poids} kg`} />}
              {animal.taille && <_InfoChip label="Taille" value={`${animal.taille} cm`} />}
            </div>
          </div>
        </div>

        {/* Identification */}
        {animal.identification && (
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 mb-4">
            <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-1">Identification</p>
            <p className="font-mono text-sm text-gray-800">{animal.identification}</p>
          </div>
        )}

        {/* Description */}
        {animal.description && (
          <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4 mb-4">
            <p className="text-xs font-semibold text-gray-400 uppercase tracking-wider mb-2">Description</p>
            <p className="text-sm text-gray-700 leading-relaxed">{animal.description}</p>
          </div>
        )}

        {/* Notes */}
        {animal.notes && (
          <div className="bg-amber-50 rounded-2xl border border-amber-100 p-4 mb-4">
            <p className="text-xs font-semibold text-amber-600 uppercase tracking-wider mb-2">Notes</p>
            <p className="text-sm text-gray-700 leading-relaxed">{animal.notes}</p>
          </div>
        )}

        {/* Footer */}
        <p className="text-center text-xs text-gray-400 mt-6">
          Fiche partagée via PetsMatch · Données en lecture seule
        </p>
      </div>
    </div>
  );
}

function _ErrorPage({ icon, title, message }: { icon: string; title: string; message: string }) {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="text-center max-w-sm">
        <div className="text-6xl mb-4">{icon}</div>
        <h1 className="text-xl font-bold text-gray-800 mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>{title}</h1>
        <p className="text-gray-500 text-sm leading-relaxed">{message}</p>
        <a
          href="/"
          className="mt-6 inline-block bg-green-600 text-white px-6 py-2.5 rounded-full text-sm font-medium hover:bg-green-700 transition-colors"
        >
          Retour à l&apos;accueil
        </a>
      </div>
    </div>
  );
}

function _InfoChip({ label, value }: { label: string; value: string }) {
  return (
    <div className="bg-gray-50 rounded-xl px-3 py-2">
      <p className="text-xs text-gray-400 font-medium">{label}</p>
      <p className="text-sm font-semibold text-gray-800">{value}</p>
    </div>
  );
}

function _capitalize(s: string) {
  return s.charAt(0).toUpperCase() + s.slice(1);
}
