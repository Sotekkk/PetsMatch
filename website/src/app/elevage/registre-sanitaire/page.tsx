'use client';

import { useEffect, useState } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { usePlan } from '@/lib/use-plan';

interface Acte {
  id: string;
  animal_nom?: string;
  espece?: string;
  sexe?: string;
  identification?: string;
  date_naissance?: string;
  date_acte?: string;
  type_acte?: string;
  intervenant?: string;
  description?: string;
  ordonnance_num?: string;
}

const TYPE_LABELS: Record<string, string> = {
  vaccination: 'Vaccination', visite: 'Visite vétérinaire', traitement: 'Traitement',
  vermifuge: 'Vermifuge', antiparasitaire: 'Antiparasitaire', osteopathie: 'Ostéopathie',
  ferrage: 'Ferrage', radiographie: 'Radiographie', chirurgie: 'Chirurgie', autre: 'Autre',
};
const TYPE_COLORS: Record<string, string> = {
  vaccination: 'bg-green-100 text-green-700', visite: 'bg-blue-100 text-blue-700',
  traitement: 'bg-teal-100 text-teal-700', vermifuge: 'bg-yellow-100 text-yellow-700',
  antiparasitaire: 'bg-orange-100 text-orange-700', osteopathie: 'bg-purple-100 text-purple-700',
  ferrage: 'bg-stone-100 text-stone-700', radiographie: 'bg-slate-100 text-slate-700',
  chirurgie: 'bg-red-100 text-red-700', autre: 'bg-gray-100 text-gray-600',
};

export default function RegistreSanitairePage() {
  const { user, loading } = useAuth();
  const activeProfileId = useActiveProfile();
  const { config: planConfig, loading: planLoading } = usePlan();
  const router = useRouter();
  const pathname = usePathname();
  const profilSource = pathname.startsWith('/association') ? 'association' : 'eleveur';
  const [actes, setActes] = useState<Acte[]>([]);
  const [fetching, setFetching] = useState(true);
  const [filtreType, setFiltreType] = useState('tous');
  const [search, setSearch] = useState('');
  const [dateDebut, setDateDebut] = useState('');
  const [dateFin, setDateFin] = useState('');
  const [selected, setSelected] = useState<Acte | null>(null);
  const [showForm, setShowForm] = useState(false);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  if (!planLoading && !planConfig.hasRegistres) {
    return (
      <div className="min-h-[70vh] flex flex-col items-center justify-center gap-4 px-4 text-center">
        <span className="text-5xl">🔒</span>
        <h2 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
          Registre sanitaire — Plan Pro requis
        </h2>
        <p className="text-gray-500 text-sm max-w-sm">
          Le registre sanitaire est disponible à partir du plan Pro. Passez à un plan supérieur pour gérer les actes vétérinaires de vos animaux.
        </p>
        <a href="/abonnement"
          className="bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold px-6 py-3 rounded-xl transition-colors text-sm">
          ⚡ Voir les plans
        </a>
        <a href="/" className="text-sm text-gray-400 hover:text-[#0C5C6C]">← Retour à l&apos;accueil</a>
      </div>
    );
  }

  useEffect(() => {
    if (!user) return;
    (async () => {
      try {
        const q = supabase.from('registre_sanitaire').select('*').eq('uid_eleveur', user.uid)
          .order('date_acte', { ascending: false });
        const { data } = await (profilSource === 'association'
          ? q.eq('profil_source', 'association')
          : q.or('profil_source.is.null,profil_source.eq.eleveur'));
        setActes((data as Acte[]) ?? []);
      } catch { /* ignore */ } finally {
        setFetching(false);
      }
    })();
  }, [user]);

  async function handleDelete(id: string) {
    if (!confirm('Supprimer cet acte ?')) return;
    await supabase.from('registre_sanitaire').delete().eq('id', id);
    setActes((prev) => prev.filter((a) => a.id !== id));
    setSelected(null);
  }

  if (loading || !user) return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;

  const filtered = actes.filter((a) => {
    if (filtreType !== 'tous' && a.type_acte !== filtreType) return false;
    if (search && !`${a.animal_nom ?? ''} ${a.espece ?? ''} ${a.intervenant ?? ''}`.toLowerCase().includes(search.toLowerCase())) return false;
    if (dateDebut && a.date_acte && a.date_acte < dateDebut) return false;
    if (dateFin && a.date_acte && a.date_acte > dateFin) return false;
    return true;
  });

  function fmtDate(s?: string) {
    if (!s) return '—';
    const d = new Date(s);
    return isNaN(d.getTime()) ? s : d.toLocaleDateString('fr-FR');
  }

  function exportCSV() {
    const headers = ['Animal', 'Espèce', 'Sexe', 'Identification', 'Né·e le', 'Type d\'acte', 'Date de l\'acte', 'Intervenant', 'Description', 'N° ordonnance'];
    const rows = filtered.map(a => [
      a.animal_nom ?? '', a.espece ?? '', a.sexe ?? '', a.identification ?? '',
      fmtDate(a.date_naissance), TYPE_LABELS[a.type_acte ?? ''] ?? a.type_acte ?? '',
      fmtDate(a.date_acte), a.intervenant ?? '', a.description ?? '', a.ordonnance_num ?? '',
    ]);
    const csv = [headers, ...rows].map(r => r.map(v => `"${String(v).replace(/"/g, '""')}"`).join(';')).join('\n');
    const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `registre_sanitaire_${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div className="max-w-5xl mx-auto px-4 py-10 print:py-4 print:px-0">
      <div className="flex items-center justify-between mb-6 print:mb-4">
        <div>
          <Link href="/mes-animaux" className="text-sm text-[#0C5C6C] hover:underline print:hidden">← Mes animaux</Link>
          <h1 className="text-2xl font-bold text-[#1F2A2E] mt-1">Registre sanitaire</h1>
          <p className="text-gray-500 text-sm">{actes.length} acte{actes.length !== 1 ? 's' : ''} enregistré{actes.length !== 1 ? 's' : ''}</p>
        </div>
        <div className="flex gap-2 print:hidden">
          <button onClick={exportCSV}
            className="border border-gray-200 hover:border-[#0C5C6C] text-gray-600 hover:text-[#0C5C6C] font-medium px-4 py-2.5 rounded-xl transition-colors text-sm flex items-center gap-1.5">
            📊 Excel / CSV
          </button>
          <button onClick={() => window.print()}
            className="border border-gray-200 hover:border-[#0C5C6C] text-gray-600 hover:text-[#0C5C6C] font-medium px-4 py-2.5 rounded-xl transition-colors text-sm flex items-center gap-1.5">
            🖨️ Imprimer
          </button>
          <button onClick={() => setShowForm(true)}
            className="bg-[#6E9E57] hover:bg-[#5A8A45] text-white font-semibold px-5 py-2.5 rounded-xl transition-colors text-sm flex items-center gap-2">
            + Nouvel acte
          </button>
        </div>
      </div>

      {/* Filtres */}
      <div className="mb-4 space-y-3 print:hidden">
        <input value={search} onChange={(e) => setSearch(e.target.value)}
          placeholder="Rechercher par animal, espèce, intervenant…"
          className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white" />
        {/* Filtre période */}
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-sm text-gray-500 font-medium">Période :</span>
          <input type="date" value={dateDebut} onChange={(e) => setDateDebut(e.target.value)}
            className="border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white" />
          <span className="text-gray-400 text-sm">→</span>
          <input type="date" value={dateFin} onChange={(e) => setDateFin(e.target.value)}
            className="border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white" />
          {(dateDebut || dateFin) && (
            <button onClick={() => { setDateDebut(''); setDateFin(''); }}
              className="text-xs text-gray-400 hover:text-red-500 transition-colors px-2 py-1 rounded-lg hover:bg-red-50">
              ✕ Effacer
            </button>
          )}
          {(dateDebut || dateFin) && (
            <span className="text-xs text-[#0C5C6C] font-medium bg-[#0C5C6C]/10 px-2 py-1 rounded-lg">
              {filtered.length} résultat{filtered.length !== 1 ? 's' : ''}
            </span>
          )}
        </div>
        <div className="flex gap-2 flex-wrap">
          <button onClick={() => setFiltreType('tous')}
            className={`px-3 py-1.5 rounded-full text-xs font-medium border transition-colors ${filtreType === 'tous' ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-600 border-gray-200'}`}>
            Tous
          </button>
          {Object.entries(TYPE_LABELS).map(([val, label]) => (
            <button key={val} onClick={() => setFiltreType(val)}
              className={`px-3 py-1.5 rounded-full text-xs font-medium border transition-colors ${filtreType === val ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-600 border-gray-200'}`}>
              {label}
            </button>
          ))}
        </div>
      </div>

      {fetching ? (
        <div className="flex justify-center py-20 text-gray-400">Chargement…</div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-20 text-gray-400">Aucun acte enregistré</div>
      ) : (
        <>
          {/* Tableau (visible écran + impression) */}
          <div className="overflow-x-auto rounded-2xl border border-gray-100 shadow-sm bg-white print:shadow-none print:border print:border-gray-300">
            <table className="w-full text-sm border-collapse">
              <thead>
                <tr className="bg-[#0C5C6C] text-white text-xs">
                  <th className="text-left px-4 py-3 font-semibold">Type d'acte</th>
                  <th className="text-left px-4 py-3 font-semibold">Animal</th>
                  <th className="text-left px-4 py-3 font-semibold hidden sm:table-cell">Espèce</th>
                  <th className="text-left px-4 py-3 font-semibold hidden md:table-cell">Identification</th>
                  <th className="text-left px-4 py-3 font-semibold hidden lg:table-cell">Intervenant</th>
                  <th className="text-left px-4 py-3 font-semibold">Date</th>
                  <th className="text-left px-4 py-3 font-semibold hidden lg:table-cell">Description</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-50">
                {filtered.map((a) => (
                  <tr key={a.id} onClick={() => setSelected(a)}
                    className="hover:bg-gray-50 cursor-pointer transition-colors print:hover:bg-transparent print:cursor-auto">
                    <td className="px-4 py-3">
                      <span className={`px-2 py-0.5 rounded-lg text-xs font-semibold ${TYPE_COLORS[a.type_acte ?? ''] ?? 'bg-gray-100 text-gray-600'}`}>
                        {TYPE_LABELS[a.type_acte ?? ''] ?? a.type_acte ?? '—'}
                      </span>
                    </td>
                    <td className="px-4 py-3 font-semibold text-[#1F2A2E]">{a.animal_nom ?? '—'}</td>
                    <td className="px-4 py-3 text-gray-500 hidden sm:table-cell">{a.espece ?? '—'}</td>
                    <td className="px-4 py-3 text-gray-500 hidden md:table-cell font-mono text-xs">{a.identification ?? '—'}</td>
                    <td className="px-4 py-3 text-gray-500 hidden lg:table-cell">{a.intervenant ?? '—'}</td>
                    <td className="px-4 py-3 text-gray-500 whitespace-nowrap">{fmtDate(a.date_acte)}</td>
                    <td className="px-4 py-3 text-gray-400 text-xs hidden lg:table-cell max-w-xs truncate">{a.description ?? '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          {/* Cartes mobiles masquées à l'impression */}
          <div className="hidden">
            {/* Le tableau ci-dessus gère mobile via responsive columns */}
          </div>
        </>
      )}

      {/* Détail acte */}
      {selected && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4" onClick={() => setSelected(null)}>
          <div className="bg-white rounded-2xl w-full max-w-lg p-6 space-y-3" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between">
              <span className={`px-2 py-1 rounded-lg text-xs font-semibold ${TYPE_COLORS[selected.type_acte ?? ''] ?? 'bg-gray-100 text-gray-600'}`}>
                {TYPE_LABELS[selected.type_acte ?? ''] ?? selected.type_acte}
              </span>
              <button onClick={() => handleDelete(selected.id)} className="text-red-400 hover:text-red-600 text-sm">Supprimer</button>
            </div>
            <h3 className="font-bold text-[#1F2A2E] text-lg">{selected.animal_nom}</h3>
            {[
              ['Date de l\'acte', fmtDate(selected.date_acte)],
              ['Espèce', selected.espece],
              ['Sexe', selected.sexe],
              ['Né·e le', fmtDate(selected.date_naissance)],
              ['Identification', selected.identification],
              ['Intervenant', selected.intervenant],
              ['Description', selected.description],
              ['N° ordonnance', selected.ordonnance_num],
            ].map(([label, val]) => val ? (
              <div key={label} className="flex gap-3">
                <span className="text-gray-400 text-sm w-36 flex-shrink-0">{label}</span>
                <span className="text-gray-700 text-sm">{val}</span>
              </div>
            ) : null)}
            <button onClick={() => setSelected(null)} className="mt-2 w-full border border-gray-200 rounded-xl py-2.5 text-sm text-gray-600 hover:bg-gray-50 transition-colors">
              Fermer
            </button>
          </div>
        </div>
      )}

      {/* Formulaire nouvel acte */}
      {showForm && <NouvelActeForm uid={user.uid} profileId={activeProfileId || null} profilSource={profilSource} onClose={() => setShowForm(false)} onSaved={(acte) => { setActes((prev) => [acte, ...prev]); setShowForm(false); }} />}
    </div>
  );
}

function NouvelActeForm({ uid, profileId, profilSource = 'eleveur', onClose, onSaved }: { uid: string; profileId?: string | null; profilSource?: string; onClose: () => void; onSaved: (a: Acte) => void }) {
  const [animaux, setAnimaux] = useState<{ id: string; nom: string; espece: string; sexe: string; identification: string; date_naissance: string }[]>([]);
  const [animalId, setAnimalId] = useState('');
  const [typeActe, setTypeActe] = useState('');
  const [dateActe, setDateActe] = useState('');
  const [intervenant, setIntervenant] = useState('');
  const [description, setDescription] = useState('');
  const [ordonnance, setOrdonnance] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  useEffect(() => {
    const q = supabase.from('animaux').select('id, nom, espece, sexe, identification, date_naissance').eq('uid_eleveur', uid).order('nom');
    (profilSource === 'association' ? q.eq('is_association', true) : q.or('is_association.is.null,is_association.eq.false'))
      .then(({ data }) => setAnimaux((data as typeof animaux) ?? []));
  }, [uid]);

  async function handleSave(e: React.FormEvent) {
    e.preventDefault();
    if (!animalId || !typeActe || !dateActe) { setError('Animal, type et date sont requis.'); return; }
    setSaving(true);
    const animal = animaux.find((a) => a.id === animalId);
    const id = Date.now().toString();
    const { error: err } = await supabase.from('registre_sanitaire').insert({
      id, uid_eleveur: uid,
      ...(profileId ? { eleveur_profile_id: profileId } : {}),
      animal_nom: animal?.nom ?? '',
      espece: animal?.espece ?? '',
      date_naissance: animal?.date_naissance ?? null,
      identification: animal?.identification ?? '',
      sexe: animal?.sexe ?? '',
      date_acte: dateActe,
      type_acte: typeActe,
      intervenant, description,
      ordonnance_num: ordonnance,
      profil_source: profilSource,
    });
    if (err) { setError('Erreur : ' + err.message); setSaving(false); return; }
    onSaved({ id, animal_nom: animal?.nom, espece: animal?.espece, date_acte: dateActe, type_acte: typeActe, intervenant, description });
  }

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-lg p-6" onClick={(e) => e.stopPropagation()}>
        <h3 className="font-bold text-[#1F2A2E] text-lg mb-4">Nouvel acte sanitaire</h3>
        <form onSubmit={handleSave} className="space-y-3">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Animal *</label>
            <select value={animalId} onChange={(e) => setAnimalId(e.target.value)} required
              className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white">
              <option value="">Sélectionner…</option>
              {animaux.map((a) => <option key={a.id} value={a.id}>{a.nom} ({a.espece})</option>)}
            </select>
          </div>
          <div className="flex gap-3">
            <div className="flex-1">
              <label className="block text-sm font-medium text-gray-700 mb-1">Type d'acte *</label>
              <select value={typeActe} onChange={(e) => setTypeActe(e.target.value)} required
                className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white">
                <option value="">Choisir…</option>
                {Object.entries(TYPE_LABELS).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
              </select>
            </div>
            <div className="flex-1">
              <label className="block text-sm font-medium text-gray-700 mb-1">Date de l'acte *</label>
              <input type="date" value={dateActe} onChange={(e) => setDateActe(e.target.value)} required
                className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white" />
            </div>
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Intervenant</label>
            <input value={intervenant} onChange={(e) => setIntervenant(e.target.value)} placeholder="Vétérinaire, ostéopathe…"
              className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white" />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Description / Acte réalisé</label>
            <textarea value={description} onChange={(e) => setDescription(e.target.value)} rows={2}
              className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white resize-none" />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">N° ordonnance</label>
            <input value={ordonnance} onChange={(e) => setOrdonnance(e.target.value)}
              className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white" />
          </div>
          {error && <p className="text-red-500 text-sm">{error}</p>}
          <div className="flex gap-3 pt-1">
            <button type="submit" disabled={saving}
              className="flex-1 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-semibold py-2.5 rounded-xl transition-colors text-sm">
              {saving ? 'Enregistrement…' : 'Enregistrer'}
            </button>
            <button type="button" onClick={onClose}
              className="flex-1 border border-gray-200 text-gray-600 font-medium py-2.5 rounded-xl transition-colors text-sm hover:bg-gray-50">
              Annuler
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
