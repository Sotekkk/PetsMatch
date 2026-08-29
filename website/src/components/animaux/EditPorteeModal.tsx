'use client';

import { useState } from 'react';
import { supabase } from '@/lib/supabase';

export interface PorteeAnimal {
  id: string;
  nom?: string | null;
  sexe?: string | null;
  espece?: string | null;
  race?: string | null;
  identification?: string | null;
  date_naissance?: string | null;
  photo_url?: string | null;
  date_entree?: string | null;
  description?: string | null;
  pedigree?: boolean | null;
  club_registre?: string | null;
  pedigree_lof?: string | null;
  nom_pere?: string | null;
  puce_pere?: string | null;
  nom_mere?: string | null;
  puce_mere?: string | null;
  race_mere?: string | null;
  date_naissance_mere?: string | null;
}

// Modal « Modifier la portée » — infos communes à tous les animaux d'une portée.
// Réutilisé côté éleveur (Mes animaux) et côté employé (Mes employeurs), d'où
// les props `uid` / `activeProfileId` qui ciblent l'élevage propriétaire.
export default function EditPorteeModal({ pid, members, uid, activeProfileId, onClose, onSaved }: {
  pid: string;
  members: PorteeAnimal[];
  uid: string;
  activeProfileId: string | null;
  onClose: () => void;
  onSaved: (fields: Partial<PorteeAnimal>) => void;
}) {
  const first = members[0];
  const espece = first.espece ?? '';
  const [race, setRace] = useState(first.race ?? '');
  const [dateNaissance, setDateNaissance] = useState(first.date_naissance?.slice(0, 10) ?? '');
  const [description, setDescription] = useState(first.description ?? '');
  const [pedigree, setPedigree] = useState(!!first.pedigree);
  const [clubRegistre, setClubRegistre] = useState(first.club_registre ?? '');
  const [pedigreeLof, setPedigreeLof] = useState(first.pedigree_lof ?? '');
  const [nomPere, setNomPere] = useState(first.nom_pere ?? '');
  const [pucePere, setPucePere] = useState(first.puce_pere ?? '');
  const [nomMere, setNomMere] = useState(first.nom_mere ?? '');
  const [puceMere, setPuceMere] = useState(first.puce_mere ?? '');
  const [raceMere, setRaceMere] = useState(first.race_mere ?? '');
  const [dateNaissanceMere, setDateNaissanceMere] = useState(first.date_naissance_mere?.slice(0, 10) ?? '');
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState('');

  const [showPerePicker, setShowPerePicker] = useState(false);
  const [myMales, setMyMales] = useState<PorteeAnimal[]>([]);
  const [loadingMales, setLoadingMales] = useState(false);
  const [showMerePicker, setShowMerePicker] = useState(false);
  const [myFemelles, setMyFemelles] = useState<PorteeAnimal[]>([]);
  const [loadingFemelles, setLoadingFemelles] = useState(false);

  async function loadMaleAnimals() {
    if (!uid) return;
    setLoadingMales(true);
    let qm = supabase.from('animaux')
      .select('id, nom, sexe, espece, race, identification, date_naissance, photo_url')
      .eq('uid_eleveur', uid).eq('espece', espece).eq('sexe', 'male')
      .or('statut.is.null,statut.eq.present');
    if (activeProfileId) qm = qm.eq('profile_id', activeProfileId) as typeof qm;
    const { data } = await qm.order('nom');
    setMyMales((data ?? []) as PorteeAnimal[]);
    setLoadingMales(false);
  }

  async function loadFemelleAnimals() {
    if (!uid) return;
    setLoadingFemelles(true);
    let qf = supabase.from('animaux')
      .select('id, nom, sexe, espece, race, identification, date_naissance, photo_url')
      .eq('uid_eleveur', uid).eq('espece', espece).eq('sexe', 'femelle')
      .or('statut.is.null,statut.eq.present');
    if (activeProfileId) qf = qf.eq('profile_id', activeProfileId) as typeof qf;
    const { data } = await qf.order('nom');
    setMyFemelles((data ?? []) as PorteeAnimal[]);
    setLoadingFemelles(false);
  }

  function selectPere(a: PorteeAnimal) {
    setNomPere(a.nom ?? '');
    setPucePere(a.identification ?? '');
    setShowPerePicker(false);
  }

  function selectMere(a: PorteeAnimal) {
    setNomMere(a.nom ?? '');
    setPuceMere(a.identification ?? '');
    setRaceMere(a.race ?? '');
    setDateNaissanceMere(a.date_naissance?.slice(0, 10) ?? '');
    setShowMerePicker(false);
  }

  const iCls = 'w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]';

  async function handleSave() {
    if (!dateNaissance) { setError('La date de naissance est obligatoire.'); return; }
    setSaving(true); setError('');
    const fields: Partial<PorteeAnimal> = {
      race: race.trim() || undefined,
      date_naissance: dateNaissance,
      date_entree: dateNaissance,
      description: description.trim() || undefined,
      pedigree,
      club_registre: clubRegistre.trim() || undefined,
      pedigree_lof: pedigreeLof.trim() || undefined,
      nom_pere: nomPere.trim() || undefined,
      puce_pere: pucePere.trim() || undefined,
      nom_mere: nomMere.trim() || undefined,
      puce_mere: puceMere.trim() || undefined,
      race_mere: raceMere.trim() || undefined,
      date_naissance_mere: dateNaissanceMere || undefined,
    };
    const dbFields = Object.fromEntries(Object.entries(fields).map(([k, v]) => [k, v ?? null]));
    const { error: err } = await supabase.from('animaux').update(dbFields).eq('portee_id', pid);
    setSaving(false);
    if (err) { setError('Erreur lors de la sauvegarde.'); return; }
    setSaved(true);
    setTimeout(() => onSaved(fields), 800);
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 p-4">
      <div className="bg-white rounded-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto">
        <div className="p-5">
          <div className="flex items-center gap-3 mb-4">
            <div className="w-10 h-10 rounded-xl bg-[#0C5C6C0D] flex items-center justify-center text-xl">✏️</div>
            <div className="flex-1">
              <p className="font-bold text-[#1F2A2E] text-base" style={{ fontFamily: 'Galey, sans-serif' }}>Modifier la portée</p>
              <p className="text-xs text-gray-400">{members.length} animal{members.length > 1 ? 'aux' : ''} concerné{members.length > 1 ? 's' : ''}</p>
            </div>
            <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl leading-none">✕</button>
          </div>

          <div className="flex gap-3 mb-4">
            <div className="flex-1">
              <label className="block text-xs font-medium text-gray-600 mb-1">Race</label>
              <input className={iCls} value={race} onChange={e => setRace(e.target.value)} placeholder="Race commune à tous" />
            </div>
            <div className="flex-1">
              <label className="block text-xs font-medium text-gray-600 mb-1">
                Date de naissance <span className="text-red-400">*</span>
              </label>
              <input type="date" className={iCls} value={dateNaissance}
                onChange={e => setDateNaissance(e.target.value)}
                max={new Date().toISOString().slice(0, 10)} />
            </div>
          </div>

          <div className="mb-4">
            <label className="block text-xs font-medium text-gray-600 mb-1">Description (optionnel)</label>
            <textarea rows={2} className={`${iCls} resize-none`} value={description}
              onChange={e => setDescription(e.target.value)}
              placeholder="Caractère, particularités de la portée…" />
          </div>

          <div className="border border-gray-100 rounded-xl p-4 space-y-3 mb-4">
            <p className="text-sm font-semibold text-gray-700">🏅 Pedigree &amp; Registre</p>
            <div className="flex items-center justify-between py-1">
              <span className="text-sm text-gray-700">Inscrit au registre (LOF / LOOF…)</span>
              <button type="button" onClick={() => setPedigree(!pedigree)}
                className={`w-11 h-6 rounded-full transition-colors relative flex-shrink-0 ${pedigree ? 'bg-[#6E9E57]' : 'bg-gray-200'}`}>
                <div className={`w-5 h-5 bg-white rounded-full absolute top-0.5 transition-transform shadow-sm ${pedigree ? 'translate-x-5' : 'translate-x-0.5'}`} />
              </button>
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">Club de race / Association pedigree</label>
              <input className={iCls} value={clubRegistre} onChange={e => setClubRegistre(e.target.value)}
                placeholder="Ex: SCC, Club du Berger Australien…" />
            </div>
            <div>
              <label className="block text-xs font-medium text-gray-600 mb-1">N° d&apos;inscription au registre</label>
              <input className={iCls} value={pedigreeLof} onChange={e => setPedigreeLof(e.target.value)}
                placeholder="Ex: LOF 12345/00, LOOF 67890…" />
            </div>
          </div>

          <div className="border border-gray-100 rounded-xl p-4 space-y-3 mb-4">
            <p className="text-sm font-semibold text-gray-700">♂ Père (optionnel)</p>
            <div className="relative">
              <button type="button"
                onClick={async () => {
                  if (!showPerePicker) await loadMaleAnimals();
                  setShowPerePicker(v => !v);
                  setShowMerePicker(false);
                }}
                className="w-full flex items-center gap-2 px-3 py-2 border border-[#0C5C6C] text-[#0C5C6C] rounded-xl text-sm font-medium hover:bg-[#E8F4F6] transition-colors">
                <span>🔍</span>
                <span>Chercher parmi mes animaux</span>
              </button>
              {showPerePicker && (
                <ParentPickerList animals={myMales} isLoading={loadingMales} onSelect={selectPere} />
              )}
            </div>
            <div className="flex gap-3">
              <div className="flex-1">
                <label className="block text-xs font-medium text-gray-600 mb-1">Nom du père</label>
                <input className={iCls} value={nomPere} onChange={e => setNomPere(e.target.value)} placeholder="Nom" />
              </div>
              <div className="flex-1">
                <label className="block text-xs font-medium text-gray-600 mb-1">N° identification</label>
                <input className={iCls} value={pucePere} onChange={e => setPucePere(e.target.value)} placeholder="Puce / tatouage" />
              </div>
            </div>
          </div>

          <div className="border border-gray-100 rounded-xl p-4 space-y-3 mb-5">
            <p className="text-sm font-semibold text-gray-700">♀ Mère (optionnel)</p>
            <div className="relative">
              <button type="button"
                onClick={async () => {
                  if (!showMerePicker) await loadFemelleAnimals();
                  setShowMerePicker(v => !v);
                  setShowPerePicker(false);
                }}
                className="w-full flex items-center gap-2 px-3 py-2 border border-[#0C5C6C] text-[#0C5C6C] rounded-xl text-sm font-medium hover:bg-[#E8F4F6] transition-colors">
                <span>🔍</span>
                <span>Chercher parmi mes animaux</span>
              </button>
              {showMerePicker && (
                <ParentPickerList animals={myFemelles} isLoading={loadingFemelles} onSelect={selectMere} />
              )}
            </div>
            <div className="flex gap-3">
              <div className="flex-1">
                <label className="block text-xs font-medium text-gray-600 mb-1">Nom de la mère</label>
                <input className={iCls} value={nomMere} onChange={e => setNomMere(e.target.value)} placeholder="Nom" />
              </div>
              <div className="flex-1">
                <label className="block text-xs font-medium text-gray-600 mb-1">N° identification</label>
                <input className={iCls} value={puceMere} onChange={e => setPuceMere(e.target.value)} placeholder="Puce / tatouage" />
              </div>
            </div>
            <div className="flex gap-3">
              <div className="flex-1">
                <label className="block text-xs font-medium text-gray-600 mb-1">Race de la mère</label>
                <input className={iCls} value={raceMere} onChange={e => setRaceMere(e.target.value)} placeholder="Race" />
              </div>
              <div className="flex-1">
                <label className="block text-xs font-medium text-gray-600 mb-1">Date de naissance</label>
                <input type="date" className={iCls} value={dateNaissanceMere}
                  onChange={e => setDateNaissanceMere(e.target.value)}
                  max={new Date().toISOString().slice(0, 10)} />
              </div>
            </div>
          </div>

          {error && <p className="text-sm text-red-600 mb-3 bg-red-50 rounded-xl px-3 py-2">{error}</p>}
          {saved && <p className="text-sm text-[#6E9E57] mb-3 bg-[#EEF5EA] rounded-xl px-3 py-2 font-semibold">✓ Portée mise à jour</p>}

          <div className="flex gap-3">
            <button onClick={onClose}
              className="flex-1 border border-gray-200 text-gray-600 font-semibold py-3 rounded-xl text-sm hover:bg-gray-50 transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              Annuler
            </button>
            <button onClick={handleSave} disabled={saving || saved}
              className="flex-1 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 disabled:cursor-not-allowed text-white font-semibold py-3 rounded-xl text-sm transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              {saving ? 'Enregistrement…' : 'Enregistrer'}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

function ParentPickerList({ animals, isLoading, onSelect }: {
  animals: PorteeAnimal[];
  isLoading: boolean;
  onSelect: (a: PorteeAnimal) => void;
}) {
  const [search, setSearch] = useState('');
  const q = search.trim().toLowerCase();
  const filtered = q
    ? animals.filter(a =>
        (a.nom ?? '').toLowerCase().includes(q) ||
        (a.race ?? '').toLowerCase().includes(q))
    : animals;

  return (
    <div className="absolute z-20 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
      <div className="p-2 border-b border-gray-100">
        <input
          type="text"
          autoFocus
          value={search}
          onChange={e => setSearch(e.target.value)}
          placeholder="Rechercher par nom…"
          className="w-full border border-gray-200 rounded-lg px-3 py-1.5 text-sm focus:outline-none focus:border-[#0C5C6C]"
        />
      </div>
      <div className="max-h-52 overflow-y-auto">
        {isLoading ? (
          <p className="text-sm text-gray-400 text-center py-4">Chargement…</p>
        ) : filtered.length === 0 ? (
          <p className="text-sm text-gray-400 text-center py-4">Aucun animal trouvé</p>
        ) : filtered.map(a => (
          <button key={a.id} type="button" onClick={() => onSelect(a)}
            className="w-full flex items-center gap-3 px-3 py-2.5 hover:bg-[#E8F4F6] text-left border-b border-gray-50 last:border-0 transition-colors">
            <div className="w-10 h-10 rounded-lg overflow-hidden flex-shrink-0 bg-gray-100 flex items-center justify-center">
              {a.photo_url ? (
                // eslint-disable-next-line @next/next/no-img-element
                <img src={a.photo_url} alt="" className="w-full h-full object-contain" />
              ) : (
                <span className="text-gray-300 text-lg">🐾</span>
              )}
            </div>
            <div className="min-w-0">
              <p className="text-sm font-semibold text-gray-800 truncate">{a.nom || 'Sans nom'}</p>
              {a.race && <p className="text-xs text-gray-400 truncate">{a.race}</p>}
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}
