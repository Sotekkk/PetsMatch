'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

const STATUTS: Record<string, { label: string; color: string }> = {
  en_soin:    { label: 'En soin',     color: 'bg-orange-100 text-orange-700' },
  disponible: { label: 'Disponible',  color: 'bg-green-100 text-green-700' },
  en_fa:      { label: 'En FA',       color: 'bg-purple-100 text-purple-700' },
  adopte:     { label: 'Adopté',      color: 'bg-teal-100 text-teal-700' },
  transfere:  { label: 'Transféré',   color: 'bg-blue-100 text-blue-700' },
  decede:     { label: 'Décédé',      color: 'bg-red-100 text-red-700' },
};

function age(dn: string | null): string {
  if (!dn) return '';
  const mois = Math.floor((Date.now() - new Date(dn).getTime()) / (1000 * 60 * 60 * 24 * 30));
  if (mois < 1) return 'Moins d\'1 mois';
  if (mois < 12) return `${mois} mois`;
  const ans = Math.floor(mois / 12);
  const rm = mois % 12;
  return rm ? `${ans} an${ans > 1 ? 's' : ''} ${rm} mois` : `${ans} an${ans > 1 ? 's' : ''}`;
}

function fmtDate(d: string | null): string {
  if (!d) return '–';
  return new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: 'long', year: 'numeric' });
}

export default function AnimalAssoFichePage() {
  const { id } = useParams<{ id: string }>();
  const { user } = useAuth();
  const router = useRouter();
  const [animal, setAnimal] = useState<any>(null);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [editStatut, setEditStatut] = useState('');
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  useEffect(() => {
    if (!user || !id) return;
    supabase
      .from('animaux')
      .select('*')
      .eq('id', id)
      .eq('uid_eleveur', user.uid)
      .single()
      .then(({ data }) => {
        setAnimal(data);
        setEditStatut(data?.statut ?? '');
        setLoading(false);
      });
  }, [user, id]);

  const handleStatutChange = async (newStatut: string) => {
    setEditStatut(newStatut);
    setSaving(true);
    await supabase.from('animaux').update({ statut: newStatut }).eq('id', id);
    setAnimal((prev: any) => ({ ...prev, statut: newStatut }));
    setSaving(false);
  };

  const handleDelete = async () => {
    await supabase.from('animaux').delete().eq('id', id);
    router.push('/association/animaux');
  };

  if (loading) {
    return (
      <div className="flex justify-center py-20">
        <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
      </div>
    );
  }

  if (!animal) {
    return (
      <div className="text-center py-20 text-gray-500">
        <p className="text-4xl mb-3">🐾</p>
        <p className="font-galey">Animal introuvable</p>
        <Link href="/association/animaux" className="text-teal-600 underline mt-4 inline-block">
          Retour aux animaux
        </Link>
      </div>
    );
  }

  const sc = STATUTS[animal.statut] ?? { label: animal.statut, color: 'bg-gray-100 text-gray-700' };

  return (
    <div className="space-y-5 max-w-2xl">
      {/* Header */}
      <div className="flex items-center gap-3">
        <button onClick={() => router.back()} className="text-gray-400 hover:text-gray-600 text-xl">←</button>
        <h1 className="text-2xl font-bold font-galey text-teal-800">{animal.nom}</h1>
        <span className={`ml-auto text-xs font-galey font-bold px-3 py-1 rounded-full ${sc.color}`}>
          {sc.label}
        </span>
      </div>

      {/* Photo + infos rapides */}
      <div className="bg-white rounded-2xl shadow-sm overflow-hidden border border-gray-100">
        <div className="aspect-video bg-gray-100 relative overflow-hidden max-h-72">
          {animal.photo_url ? (
            <img src={animal.photo_url} alt={animal.nom} className="w-full h-full object-cover" />
          ) : (
            <div className="w-full h-full flex items-center justify-center text-6xl text-gray-300">🐾</div>
          )}
        </div>
        <div className="p-4 grid grid-cols-2 sm:grid-cols-3 gap-3">
          {[
            { label: 'Espèce',     value: animal.espece },
            { label: 'Race',       value: animal.race ?? '–' },
            { label: 'Sexe',       value: animal.sexe === 'male' ? 'Mâle' : animal.sexe === 'femelle' ? 'Femelle' : '–' },
            { label: 'Âge',        value: age(animal.date_naissance) || '–' },
            { label: 'Entrée',     value: fmtDate(animal.date_entree) },
            { label: 'Poids',      value: animal.poids ? `${animal.poids} kg` : '–' },
          ].map(({ label, value }) => (
            <div key={label}>
              <p className="text-xs text-gray-400 font-galey">{label}</p>
              <p className="text-sm font-galey font-semibold text-gray-800 capitalize">{value}</p>
            </div>
          ))}
        </div>
      </div>

      {/* Changer statut */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
        <p className="text-sm font-galey font-semibold text-gray-700 mb-2">Statut</p>
        <div className="flex flex-wrap gap-2">
          {Object.entries(STATUTS).map(([key, { label, color }]) => (
            <button key={key} onClick={() => handleStatutChange(key)}
              className={`px-3 py-1.5 rounded-full text-xs font-galey font-semibold border transition-all ${
                editStatut === key ? color + ' ring-2 ring-offset-1 ring-current' : 'bg-white text-gray-500 border-gray-200 hover:bg-gray-50'
              }`}>
              {label}
            </button>
          ))}
        </div>
        {saving && <p className="text-xs text-teal-500 mt-2 font-galey">Enregistrement…</p>}
      </div>

      {/* Santé */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
        <p className="text-sm font-galey font-semibold text-gray-700 mb-3">Santé</p>
        <div className="grid grid-cols-2 gap-2">
          {[
            { label: 'Vacciné',                value: animal.vaccins ?? animal.vaccines },
            { label: 'Vermifugé',              value: animal.vermifuge },
            { label: 'Identifié (puce/tatoo)', value: animal.identification },
            { label: 'Stérilisé',              value: animal.sterilise },
          ].map(({ label, value }) => (
            <div key={label} className="flex items-center gap-2">
              <span className={`w-5 h-5 rounded-full flex items-center justify-center text-xs flex-shrink-0 ${value ? 'bg-green-100 text-green-600' : 'bg-gray-100 text-gray-400'}`}>
                {value ? '✓' : '✗'}
              </span>
              <span className="text-sm font-galey text-gray-700">{label}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Notes */}
      {animal.description && (
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
          <p className="text-sm font-galey font-semibold text-gray-700 mb-2">Notes</p>
          <p className="text-sm font-galey text-gray-600 whitespace-pre-wrap">{animal.description}</p>
        </div>
      )}

      {/* Actions */}
      <div className="space-y-3">
        {animal.statut === 'disponible' && (
          <Link href={`/association/annonces/creer?animalId=${id}`}
            className="flex items-center justify-center gap-2 w-full bg-teal-700 text-white py-3.5 rounded-xl font-galey font-bold text-base hover:bg-teal-800 transition-colors">
            💚 Mettre en adoption
          </Link>
        )}
        <Link href={`/association/animaux/${id}/modifier`}
          className="flex items-center justify-center gap-2 w-full bg-white border border-teal-200 text-teal-700 py-3 rounded-xl font-galey font-semibold text-sm hover:bg-teal-50 transition-colors">
          ✏️ Modifier la fiche
        </Link>
        {!showDeleteConfirm ? (
          <button onClick={() => setShowDeleteConfirm(true)}
            className="w-full text-red-400 py-2 text-sm font-galey hover:text-red-600 transition-colors">
            Supprimer l'animal
          </button>
        ) : (
          <div className="bg-red-50 border border-red-200 rounded-xl p-4 text-center">
            <p className="text-sm font-galey text-red-700 mb-3">Confirmer la suppression de {animal.nom} ?</p>
            <div className="flex gap-3 justify-center">
              <button onClick={() => setShowDeleteConfirm(false)}
                className="px-4 py-2 rounded-lg border border-gray-200 text-sm font-galey text-gray-600 hover:bg-gray-50">
                Annuler
              </button>
              <button onClick={handleDelete}
                className="px-4 py-2 rounded-lg bg-red-500 text-white text-sm font-galey hover:bg-red-600">
                Supprimer
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
