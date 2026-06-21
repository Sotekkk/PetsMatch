'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface Annonce {
  id: string;
  titre?: string;
  type_annonce?: string;
  espece?: string;
  statut?: string;
  prix?: number;
  created_at?: string;
  photo_url?: string;
}

const TYPE_LABELS: Record<string, string> = {
  adoption: 'Adoption',
  don: 'Don',
  accueil_temporaire: 'Accueil temporaire',
  recherche_fa: 'Recherche FA',
};

const STATUT_STYLE: Record<string, string> = {
  active: 'bg-green-100 text-green-700',
  expirée: 'bg-gray-100 text-gray-500',
  vendue: 'bg-teal-100 text-teal-700',
};

export default function AnnoncesAssoPage() {
  const { user } = useAuth();
  const [annonces, setAnnonces] = useState<Annonce[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user) return;
    supabase
      .from('annonces')
      .select('id, titre, type_annonce, espece, statut, prix, created_at, photo_url')
      .eq('uid_eleveur', user.uid)
      .eq('profil_source', 'association')
      .order('created_at', { ascending: false })
      .then(({ data }) => {
        setAnnonces(data ?? []);
        setLoading(false);
      });
  }, [user]);

  const handleDelete = async (id: string) => {
    if (!confirm('Supprimer cette annonce ?')) return;
    await supabase.from('annonces').delete().eq('id', id);
    setAnnonces(prev => prev.filter(a => a.id !== id));
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold font-galey text-teal-800">Mes Annonces</h1>
        <Link href="/association/annonces/creer"
          className="bg-teal-700 text-white px-4 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800 transition-colors">
          + Déposer une annonce
        </Link>
      </div>

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : annonces.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">📣</p>
          <p className="font-galey mb-4">Aucune annonce publiée</p>
          <Link href="/association/annonces/creer"
            className="bg-teal-700 text-white px-6 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800">
            Déposer une annonce
          </Link>
        </div>
      ) : (
        <div className="space-y-3">
          {annonces.map(a => (
            <div key={a.id} className="bg-white rounded-2xl shadow-sm p-4 flex gap-4 border border-gray-100 hover:border-teal-200 transition-all">
              {/* Photo */}
              <div className="w-16 h-16 rounded-xl overflow-hidden bg-gray-100 flex-shrink-0">
                {a.photo_url ? (
                  <img src={a.photo_url} alt={a.titre} className="w-full h-full object-cover" />
                ) : (
                  <div className="w-full h-full flex items-center justify-center text-2xl text-gray-300">🐾</div>
                )}
              </div>
              {/* Infos */}
              <div className="flex-1 min-w-0">
                <div className="flex items-start justify-between gap-2">
                  <p className="font-bold font-galey text-gray-900 truncate">{a.titre ?? 'Sans titre'}</p>
                  <span className={`text-xs font-galey font-semibold px-2 py-0.5 rounded-full flex-shrink-0 ${STATUT_STYLE[a.statut ?? ''] ?? 'bg-gray-100 text-gray-500'}`}>
                    {a.statut ?? 'active'}
                  </span>
                </div>
                <div className="flex items-center gap-3 text-xs text-gray-500 font-galey mt-1">
                  {a.type_annonce && <span>{TYPE_LABELS[a.type_annonce] ?? a.type_annonce}</span>}
                  {a.espece && <span>• {a.espece}</span>}
                  {a.prix != null && a.prix > 0 && <span>• {a.prix}€</span>}
                  {a.created_at && <span>• {new Date(a.created_at).toLocaleDateString('fr-FR')}</span>}
                </div>
              </div>
              {/* Actions */}
              <div className="flex items-center gap-2 flex-shrink-0">
                <Link href={`/annonces/${a.id}/modifier`}
                  className="text-xs text-teal-600 hover:text-teal-800 border border-teal-200 px-3 py-1 rounded-full font-galey hover:bg-teal-50">
                  Modifier
                </Link>
                <button onClick={() => handleDelete(a.id)}
                  className="text-red-400 hover:text-red-600 text-sm">🗑</button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
