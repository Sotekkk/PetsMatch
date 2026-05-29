'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

// ── Types ──────────────────────────────────────────────────────────────────────

interface Lieu {
  id: string;
  nom: string;
  categorie: string;
  adresse?: string;
  ville?: string;
  description?: string;
  created_at: string;
}

// ── Constantes ─────────────────────────────────────────────────────────────────

const CATEGORIES = [
  'Tous',
  'Randonnée / Parc',
  'Restaurant / Bar',
  'Hôtel / Hébergement',
  'Boutique',
  'Autre',
];

const CAT_COLORS: Record<string, { bg: string; text: string }> = {
  'Randonnée / Parc':    { bg: '#F0FDF4', text: '#16A34A' },
  'Restaurant / Bar':    { bg: '#FFF7ED', text: '#EA580C' },
  'Hôtel / Hébergement': { bg: '#EFF6FF', text: '#2563EB' },
  'Boutique':            { bg: '#F5F3FF', text: '#7C3AED' },
  'Autre':               { bg: '#F9FAFB', text: '#6B7280' },
};

function catStyle(cat: string) {
  return CAT_COLORS[cat] ?? CAT_COLORS['Autre'];
}

// ── Composants ─────────────────────────────────────────────────────────────────

function LieuCard({ lieu }: { lieu: Lieu }) {
  const { bg, text } = catStyle(lieu.categorie);
  const localisation = [lieu.adresse, lieu.ville].filter(Boolean).join(', ');

  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-5 flex flex-col gap-2">
      <div className="flex items-start justify-between gap-3">
        <h3 className="font-bold text-[#1E2025] text-base leading-snug" style={{ fontFamily: 'Galey, sans-serif' }}>
          {lieu.nom}
        </h3>
        <span
          className="flex-shrink-0 text-xs font-semibold px-2.5 py-1 rounded-full"
          style={{ backgroundColor: bg, color: text, fontFamily: 'Galey, sans-serif' }}
        >
          {lieu.categorie}
        </span>
      </div>
      {localisation && (
        <p className="text-sm text-gray-500 flex items-center gap-1.5">
          <span>📍</span> {localisation}
        </p>
      )}
      {lieu.description && (
        <p className="text-sm text-gray-600 line-clamp-2" style={{ fontFamily: 'Galey, sans-serif' }}>
          {lieu.description}
        </p>
      )}
    </div>
  );
}

function AddLieuModal({ onClose, onSaved }: { onClose: () => void; onSaved: () => void }) {
  const { user } = useAuth();
  const [nom, setNom] = useState('');
  const [categorie, setCategorie] = useState(CATEGORIES[1]);
  const [adresse, setAdresse] = useState('');
  const [ville, setVille] = useState('');
  const [description, setDescription] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!nom.trim()) { setError('Le nom est obligatoire.'); return; }
    setSaving(true);
    setError('');
    try {
      const { error: err } = await supabase.from('animal_friendly_lieux').insert({
        nom: nom.trim(),
        categorie,
        adresse: adresse.trim() || null,
        ville: ville.trim() || null,
        description: description.trim() || null,
        ajout_par_uid: user?.uid ?? null,
        created_at: new Date().toISOString(),
      });
      if (err) throw err;
      onSaved();
      onClose();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Erreur inattendue');
      setSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4">
      <div className="bg-white rounded-2xl w-full max-w-lg shadow-2xl overflow-hidden">
        <div className="px-6 pt-6 pb-4 border-b border-gray-100 flex items-center justify-between">
          <h2 className="font-bold text-lg" style={{ fontFamily: 'Galey, sans-serif' }}>Ajouter un lieu</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-2xl leading-none">&times;</button>
        </div>
        <form onSubmit={handleSubmit} className="px-6 py-5 flex flex-col gap-4 max-h-[70vh] overflow-y-auto">
          <div>
            <label className="block text-xs font-semibold text-gray-500 mb-1.5" style={{ fontFamily: 'Galey, sans-serif' }}>
              Nom du lieu *
            </label>
            <input
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#1E88E5] focus:ring-1 focus:ring-[#1E88E5]"
              placeholder="Ex : Parc de la Tête d'Or"
              value={nom}
              onChange={e => setNom(e.target.value)}
              style={{ fontFamily: 'Galey, sans-serif' }}
            />
          </div>
          <div>
            <label className="block text-xs font-semibold text-gray-500 mb-1.5" style={{ fontFamily: 'Galey, sans-serif' }}>
              Catégorie *
            </label>
            <select
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#1E88E5] bg-white"
              value={categorie}
              onChange={e => setCategorie(e.target.value)}
              style={{ fontFamily: 'Galey, sans-serif' }}
            >
              {CATEGORIES.slice(1).map(c => <option key={c} value={c}>{c}</option>)}
            </select>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-semibold text-gray-500 mb-1.5" style={{ fontFamily: 'Galey, sans-serif' }}>Adresse</label>
              <input
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#1E88E5] focus:ring-1 focus:ring-[#1E88E5]"
                placeholder="Rue, numéro"
                value={adresse}
                onChange={e => setAdresse(e.target.value)}
                style={{ fontFamily: 'Galey, sans-serif' }}
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-gray-500 mb-1.5" style={{ fontFamily: 'Galey, sans-serif' }}>Ville</label>
              <input
                className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#1E88E5] focus:ring-1 focus:ring-[#1E88E5]"
                placeholder="Ex : Lyon"
                value={ville}
                onChange={e => setVille(e.target.value)}
                style={{ fontFamily: 'Galey, sans-serif' }}
              />
            </div>
          </div>
          <div>
            <label className="block text-xs font-semibold text-gray-500 mb-1.5" style={{ fontFamily: 'Galey, sans-serif' }}>Description</label>
            <textarea
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#1E88E5] focus:ring-1 focus:ring-[#1E88E5] resize-none"
              placeholder="Quelques mots sur ce lieu…"
              rows={3}
              value={description}
              onChange={e => setDescription(e.target.value)}
              style={{ fontFamily: 'Galey, sans-serif' }}
            />
          </div>
          {error && <p className="text-sm text-red-500">{error}</p>}
          <button
            type="submit"
            disabled={saving}
            className="w-full bg-[#1E88E5] text-white font-bold py-3 rounded-xl disabled:opacity-50 transition-opacity"
            style={{ fontFamily: 'Galey, sans-serif' }}
          >
            {saving ? 'Enregistrement…' : 'Ajouter ce lieu'}
          </button>
        </form>
      </div>
    </div>
  );
}

// ── Page ───────────────────────────────────────────────────────────────────────

export default function AnimalFriendlyPage() {
  const { user } = useAuth();
  const [lieux, setLieux] = useState<Lieu[]>([]);
  const [loading, setLoading] = useState(true);
  const [activeCategory, setActiveCategory] = useState('Tous');
  const [showModal, setShowModal] = useState(false);

  async function loadLieux() {
    setLoading(true);
    try {
      const { data } = await supabase
        .from('animal_friendly_lieux')
        .select('id, nom, categorie, adresse, ville, description, created_at')
        .order('created_at', { ascending: false });
      setLieux((data ?? []) as Lieu[]);
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => { loadLieux(); }, []);

  const filtered = activeCategory === 'Tous'
    ? lieux
    : lieux.filter(l => l.categorie === activeCategory);

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Hero */}
      <div className="bg-[#1E88E5] text-white px-4 py-10">
        <div className="max-w-2xl mx-auto text-center">
          <p className="text-4xl mb-3">🐾</p>
          <h1 className="text-2xl font-bold mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
            Animal Friendly
          </h1>
          <p className="text-white/70 text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
            Parcs, restaurants, hôtels et lieux qui accueillent vos animaux.
          </p>
        </div>
      </div>

      <div className="max-w-3xl mx-auto px-4 py-6">
        {/* Filtres catégories */}
        <div className="flex gap-2 overflow-x-auto pb-2 mb-6 scrollbar-hide">
          {CATEGORIES.map(cat => (
            <button
              key={cat}
              onClick={() => setActiveCategory(cat)}
              className="flex-shrink-0 px-4 py-2 rounded-full text-sm font-semibold transition-all"
              style={{
                fontFamily: 'Galey, sans-serif',
                backgroundColor: activeCategory === cat ? '#1E88E5' : '#FFFFFF',
                color: activeCategory === cat ? '#FFFFFF' : '#6B7280',
                border: `1.5px solid ${activeCategory === cat ? '#1E88E5' : '#E5E7EB'}`,
              }}
            >
              {cat}
            </button>
          ))}
        </div>

        {/* Header avec compteur + bouton ajout */}
        <div className="flex items-center justify-between mb-4">
          <p className="text-sm text-gray-500" style={{ fontFamily: 'Galey, sans-serif' }}>
            {loading ? '…' : `${filtered.length} lieu${filtered.length > 1 ? 'x' : ''}`}
          </p>
          {user && (
            <button
              onClick={() => setShowModal(true)}
              className="flex items-center gap-2 bg-[#1E88E5] text-white text-sm font-bold px-4 py-2 rounded-full shadow-sm hover:bg-[#1976D2] transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}
            >
              <span className="text-base leading-none">+</span> Ajouter un lieu
            </button>
          )}
        </div>

        {/* Liste */}
        {loading ? (
          <div className="flex justify-center py-20">
            <div className="w-8 h-8 border-2 border-[#1E88E5] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : filtered.length === 0 ? (
          <div className="text-center py-20 flex flex-col items-center gap-3">
            <span className="text-6xl">📍</span>
            <p className="font-bold text-gray-700" style={{ fontFamily: 'Galey, sans-serif' }}>
              {activeCategory !== 'Tous' ? `Aucun lieu "${activeCategory}"` : 'Aucun lieu pour l\'instant'}
            </p>
            <p className="text-sm text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
              Soyez le premier à en ajouter un !
            </p>
            {!user && (
              <p className="text-sm text-[#1E88E5]" style={{ fontFamily: 'Galey, sans-serif' }}>
                Connectez-vous pour contribuer.
              </p>
            )}
          </div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {filtered.map(lieu => <LieuCard key={lieu.id} lieu={lieu} />)}
          </div>
        )}

        {/* Info contribution */}
        {!user && lieux.length > 0 && (
          <div className="mt-8 bg-[#E3F2FD] rounded-xl px-5 py-4 flex items-start gap-3">
            <span className="text-lg flex-shrink-0">ℹ️</span>
            <p className="text-sm text-[#1E88E5]" style={{ fontFamily: 'Galey, sans-serif' }}>
              Connectez-vous à l&apos;application PetsMatch pour ajouter un lieu animal friendly.
            </p>
          </div>
        )}
      </div>

      {/* Modal ajout */}
      {showModal && (
        <AddLieuModal
          onClose={() => setShowModal(false)}
          onSaved={loadLieux}
        />
      )}
    </div>
  );
}
