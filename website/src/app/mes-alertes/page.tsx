'use client';

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { setOptions, importLibrary } from '@googlemaps/js-api-loader';

// ─── Structure Supabase alertes_perdus ────────────────────────────────────────
interface Alerte {
  id: string;
  uid_proprietaire: string;
  nom_animal?: string;
  espece?: string;
  race?: string;
  sexe?: string;
  couleur?: string;
  photo_url?: string;
  derniere_localisation?: string;
  statut?: string;
  date_retrouve?: string;
  numero_alerte?: string;
  animal_id?: string;
  date_perte?: string;
  description?: string;
  contact?: string;
  lat?: number;
  lng?: number;
  created_at?: string;
}

const ESPECES = ['chien', 'chat', 'lapin', 'oiseau', 'nac', 'cheval', 'ovin', 'caprin', 'porcin', 'autre'];
const ESPECE_LABEL: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', lapin: 'Lapin', oiseau: 'Oiseau', nac: 'NAC',
  cheval: 'Cheval', ovin: 'Ovin', caprin: 'Caprin', porcin: 'Porc', autre: 'Autre',
};

function fmtDate(s?: string) {
  if (!s) return '—';
  return new Date(s).toLocaleDateString('fr-FR');
}

function genNumero() {
  const now = new Date();
  const rand = Math.floor(1000 + Math.random() * 9000);
  return `A${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, '0')}${String(now.getDate()).padStart(2, '0')}-${rand}`;
}

export default function MesAlertesPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const [alertes, setAlertes] = useState<Alerte[]>([]);
  const [fetching, setFetching] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [editAlerte, setEditAlerte] = useState<Alerte | null>(null);
  const [locationAlerte, setLocationAlerte] = useState<Alerte | null>(null);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  async function fetchAlertes() {
    if (!user) return;
    try {
      const { data } = await supabase
        .from('alertes_perdus')
        .select('*')
        .eq('uid_proprietaire', user.uid)
        .order('created_at', { ascending: false });
      setAlertes((data as Alerte[]) ?? []);
    } catch { /* ignore */ } finally {
      setFetching(false);
    }
  }

  useEffect(() => { fetchAlertes(); }, [user]); // eslint-disable-line react-hooks/exhaustive-deps

  async function handleRetrouve(id: string) {
    await supabase.from('alertes_perdus').update({
      statut: 'retrouve',
      date_retrouve: new Date().toISOString().slice(0, 10),
    }).eq('id', id);
    fetchAlertes();
  }

  async function handleDelete(id: string) {
    if (!confirm('Supprimer cette alerte définitivement ?')) return;
    await supabase.from('alertes_perdus').delete().eq('id', id);
    setAlertes(prev => prev.filter(a => a.id !== id));
  }

  if (loading || !user) {
    return (
      <div className="flex justify-center py-32">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  const perdues = alertes.filter(a => (a.statut ?? 'perdu') === 'perdu');
  const retrouvees = alertes.filter(a => a.statut === 'retrouve');

  return (
    <div className="max-w-3xl mx-auto px-4 py-8">
      {/* En-tête */}
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
            Mes alertes perdus
          </h1>
          <p className="text-gray-500 text-sm">
            {perdues.length} active{perdues.length !== 1 ? 's' : ''}{retrouvees.length > 0 ? ` · ${retrouvees.length} retrouvé${retrouvees.length !== 1 ? 's' : ''}` : ''}
          </p>
        </div>
        <button
          onClick={() => { setEditAlerte(null); setShowForm(true); }}
          className="bg-orange-500 hover:bg-orange-600 text-white font-semibold px-5 py-2.5 rounded-xl transition-colors text-sm flex items-center gap-2">
          + Nouvelle alerte
        </button>
      </div>

      {fetching ? (
        <div className="flex justify-center py-20">
          <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
        </div>
      ) : alertes.length === 0 ? (
        <div className="text-center py-20 bg-white rounded-2xl border border-gray-100">
          <p className="text-5xl mb-4">🔍</p>
          <p className="text-gray-600 font-semibold mb-1">Aucune alerte active</p>
          <p className="text-gray-400 text-sm mb-4">Déclarez un animal perdu depuis sa fiche ou le bouton ci-dessus</p>
          <button
            onClick={() => { setEditAlerte(null); setShowForm(true); }}
            className="bg-orange-500 hover:bg-orange-600 text-white font-semibold px-6 py-3 rounded-xl transition-colors text-sm">
            Déclarer un animal perdu
          </button>
        </div>
      ) : (
        <div className="space-y-3">
          {alertes.map(a => {
            const retrouve = a.statut === 'retrouve';
            return (
              <div key={a.id}
                className={`bg-white rounded-2xl border-2 shadow-sm p-4 flex items-start gap-4 ${retrouve ? 'border-[#6E9E57]/40' : 'border-orange-200'}`}>
                {/* Photo */}
                <div className={`w-14 h-14 rounded-full flex-shrink-0 flex items-center justify-center overflow-hidden relative ${retrouve ? 'bg-[#EEF5EA]' : 'bg-orange-50'}`}>
                  {a.photo_url ? (
                    <Image src={a.photo_url} alt={a.nom_animal ?? ''} fill className="object-cover" />
                  ) : (
                    <span className="text-2xl">🐾</span>
                  )}
                </div>

                {/* Infos */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="font-bold text-[#1F2A2E] text-sm">{a.nom_animal ?? 'Animal inconnu'}</span>
                    <span className={`text-xs font-semibold px-2 py-0.5 rounded-full ${retrouve ? 'bg-[#EEF5EA] text-[#6E9E57]' : 'bg-orange-100 text-orange-700'}`}>
                      {retrouve ? '✓ Retrouvé' : '⚠ Perdu'}
                    </span>
                  </div>
                  <p className="text-gray-500 text-xs mt-0.5">
                    {ESPECE_LABEL[a.espece ?? ''] ?? a.espece ?? ''}
                    {a.race ? ` · ${a.race}` : ''}
                    {a.sexe ? ` · ${a.sexe}` : ''}
                    {a.couleur ? ` · ${a.couleur}` : ''}
                  </p>
                  {a.derniere_localisation && (
                    <p className="text-xs text-orange-600 mt-0.5">📍 {a.derniere_localisation}</p>
                  )}
                  {a.date_perte && (
                    <p className="text-xs text-gray-400">Perdu le {fmtDate(a.date_perte)}</p>
                  )}
                  {a.numero_alerte && (
                    <p className="text-[10px] text-orange-400 font-semibold mt-0.5">N° {a.numero_alerte}</p>
                  )}
                  {retrouve && a.date_retrouve && (
                    <p className="text-xs text-[#6E9E57]">Retrouvé le {fmtDate(a.date_retrouve)}</p>
                  )}
                </div>

                {/* Actions */}
                <div className="flex flex-col gap-1.5 flex-shrink-0">
                  {!retrouve && (
                    <button
                      onClick={() => handleRetrouve(a.id)}
                      className="text-xs bg-[#6E9E57] hover:bg-[#5A8A45] text-white font-medium px-3 py-1.5 rounded-xl transition-colors whitespace-nowrap">
                      ✓ Retrouvé
                    </button>
                  )}
                  <button
                    onClick={() => { setEditAlerte(a); setShowForm(true); }}
                    className="text-xs border border-gray-200 hover:border-[#0C5C6C] text-gray-600 hover:text-[#0C5C6C] font-medium px-3 py-1.5 rounded-xl transition-colors">
                    Modifier
                  </button>
                  {!retrouve && (
                    <button
                      onClick={() => setLocationAlerte(a)}
                      className="text-xs border border-orange-200 hover:bg-orange-50 text-orange-600 font-medium px-3 py-1.5 rounded-xl transition-colors whitespace-nowrap">
                      📍 Lieu
                    </button>
                  )}
                  <button
                    onClick={() => handleDelete(a.id)}
                    className="text-xs border border-red-100 hover:bg-red-50 text-red-400 font-medium px-3 py-1.5 rounded-xl transition-colors">
                    Supprimer
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* Formulaire création / édition */}
      {showForm && (
        <AlerteForm
          uid={user.uid}
          alerte={editAlerte}
          onClose={() => { setShowForm(false); setEditAlerte(null); }}
          onSaved={() => { setShowForm(false); setEditAlerte(null); fetchAlertes(); }}
        />
      )}

      {/* Mise à jour localisation */}
      {locationAlerte && (
        <LocationModal
          alerte={locationAlerte}
          onClose={() => setLocationAlerte(null)}
          onSaved={() => { setLocationAlerte(null); fetchAlertes(); }}
        />
      )}
    </div>
  );
}

// ── Champ localisation avec autocomplete Google Places ────────────────────────

function LocationInput({ value, onChange, placeholder = 'Ville, rue, quartier…', inputCls = '' }: {
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
  inputCls?: string;
}) {
  const [predictions, setPredictions] = useState<google.maps.places.AutocompletePrediction[]>([]);
  const autocompleteRef = useRef<google.maps.places.AutocompleteService | null>(null);
  const placesRef = useRef<google.maps.places.PlacesService | null>(null);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    const apiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_API_KEY;
    if (!apiKey) return;
    setOptions({ key: apiKey, v: 'weekly', language: 'fr' });
    importLibrary('places').then(() => {
      autocompleteRef.current = new window.google.maps.places.AutocompleteService();
      const dummyDiv = document.createElement('div');
      placesRef.current = new window.google.maps.places.PlacesService(dummyDiv);
    }).catch(() => {});
  }, []);

  function handleChange(val: string) {
    onChange(val);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    if (val.trim().length < 3) { setPredictions([]); return; }
    debounceRef.current = setTimeout(() => {
      autocompleteRef.current?.getPlacePredictions(
        { input: val, componentRestrictions: { country: ['fr', 'be', 'ch', 'lu'] }, language: 'fr' } as google.maps.places.AutocompletionRequest,
        (preds, status) => {
          if (status === window.google.maps.places.PlacesServiceStatus.OK && preds) {
            setPredictions(preds);
          } else {
            setPredictions([]);
          }
        }
      );
    }, 400);
  }

  function selectPrediction(pred: google.maps.places.AutocompletePrediction) {
    setPredictions([]);
    placesRef.current?.getDetails(
      { placeId: pred.place_id, fields: ['address_components'] },
      (place, status) => {
        if (status !== window.google.maps.places.PlacesServiceStatus.OK || !place?.address_components) {
          onChange(pred.description);
          return;
        }
        let num = '', route = '', postalCode = '', city = '';
        for (const c of place.address_components) {
          if (c.types.includes('street_number')) num = c.long_name;
          if (c.types.includes('route')) route = c.long_name;
          if (c.types.includes('postal_code')) postalCode = c.long_name;
          if (c.types.includes('locality')) city = c.long_name;
          else if (c.types.includes('postal_town') && !city) city = c.long_name;
        }
        const street = [num, route].filter(Boolean).join(' ');
        onChange([street, postalCode, city].filter(Boolean).join(', '));
      }
    );
  }

  return (
    <div className="relative">
      <input
        value={value}
        onChange={e => handleChange(e.target.value)}
        onBlur={() => setTimeout(() => setPredictions([]), 200)}
        placeholder={placeholder}
        className={inputCls || 'w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-orange-400 bg-white'}
      />
      {predictions.length > 0 && (
        <div className="absolute z-50 top-full left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
          {predictions.map(p => (
            <button key={p.place_id} type="button"
              onMouseDown={() => selectPrediction(p)}
              className="w-full text-left px-4 py-2.5 text-sm hover:bg-orange-50 text-gray-700 border-b border-gray-50 last:border-0">
              📍 {p.description}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

// ── Formulaire création / édition ─────────────────────────────────────────────

function AlerteForm({ uid, alerte, onClose, onSaved }: {
  uid: string;
  alerte: Alerte | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const isEdit = !!alerte;
  const [nom, setNom] = useState(alerte?.nom_animal ?? '');
  const [espece, setEspece] = useState(alerte?.espece ?? 'chien');
  const [race, setRace] = useState(alerte?.race ?? '');
  const [sexe, setSexe] = useState(alerte?.sexe ?? '');
  const [couleur, setCouleur] = useState(alerte?.couleur ?? '');
  const [datePerte, setDatePerte] = useState(alerte?.date_perte?.slice(0, 10) ?? new Date().toISOString().slice(0, 10));
  const [localisation, setLocalisation] = useState(alerte?.derniere_localisation ?? '');
  const [description, setDescription] = useState(alerte?.description ?? '');
  const [contact, setContact] = useState(alerte?.contact ?? '');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  async function handleSave(e: React.FormEvent) {
    e.preventDefault();
    if (!nom.trim()) { setError('Le nom de l\'animal est requis.'); return; }
    setSaving(true);
    setError('');
    try {
      const payload = {
        uid_proprietaire: uid,
        nom_animal: nom.trim(),
        espece,
        race: race.trim() || null,
        sexe: sexe || null,
        couleur: couleur.trim() || null,
        date_perte: datePerte || null,
        derniere_localisation: localisation.trim() || null,
        description: description.trim() || null,
        contact: contact.trim() || null,
        statut: alerte?.statut ?? 'perdu',
      };
      if (isEdit) {
        await supabase.from('alertes_perdus').update(payload).eq('id', alerte!.id);
      } else {
        await supabase.from('alertes_perdus').insert({
          ...payload,
          numero_alerte: genNumero(),
        });
      }
      onSaved();
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : 'Erreur lors de l\'enregistrement');
    } finally {
      setSaving(false);
    }
  }

  const inputCls = "w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white";
  const labelCls = "block text-sm font-medium text-gray-700 mb-1";

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
        <div className="p-6">
          <h3 className="font-bold text-[#1F2A2E] text-lg mb-4" style={{ fontFamily: 'Galey, sans-serif' }}>
            {isEdit ? 'Modifier l\'alerte' : 'Déclarer un animal perdu'}
          </h3>
          <form onSubmit={handleSave} className="space-y-3">
            {/* Nom */}
            <div>
              <label className={labelCls}>Nom de l&apos;animal *</label>
              <input value={nom} onChange={e => setNom(e.target.value)} required placeholder="Rex, Luna…" className={inputCls} />
            </div>

            {/* Espèce */}
            <div>
              <label className={labelCls}>Espèce</label>
              <div className="flex flex-wrap gap-1.5">
                {ESPECES.map(e => (
                  <button key={e} type="button" onClick={() => setEspece(e)}
                    className={`px-3 py-1.5 rounded-xl text-xs font-medium border transition-colors ${espece === e ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'border-gray-200 text-gray-600 hover:border-[#0C5C6C]/40'}`}>
                    {ESPECE_LABEL[e]}
                  </button>
                ))}
              </div>
            </div>

            <div className="flex gap-3">
              <div className="flex-1">
                <label className={labelCls}>Race</label>
                <input value={race} onChange={e => setRace(e.target.value)} placeholder="Labrador…" className={inputCls} />
              </div>
              <div className="flex-1">
                <label className={labelCls}>Couleur / Signes</label>
                <input value={couleur} onChange={e => setCouleur(e.target.value)} placeholder="Roux, tâche blanche…" className={inputCls} />
              </div>
            </div>

            {/* Sexe */}
            <div>
              <label className={labelCls}>Sexe</label>
              <div className="flex gap-2">
                {[['', 'Non renseigné'], ['male', 'Mâle'], ['femelle', 'Femelle']].map(([v, l]) => (
                  <button key={v} type="button" onClick={() => setSexe(v)}
                    className={`flex-1 py-2 rounded-xl text-xs font-medium border transition-colors ${sexe === v ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'border-gray-200 text-gray-600'}`}>
                    {l}
                  </button>
                ))}
              </div>
            </div>

            {/* Date de perte */}
            <div>
              <label className={labelCls}>Date de perte</label>
              <input type="date" value={datePerte} onChange={e => setDatePerte(e.target.value)} className={inputCls} />
            </div>

            {/* Localisation */}
            <div>
              <label className={labelCls}>Dernière localisation connue</label>
              <LocationInput value={localisation} onChange={setLocalisation}
                placeholder="Rechercher une adresse…" inputCls={inputCls} />
            </div>

            {/* Description */}
            <div>
              <label className={labelCls}>Description / Particularités</label>
              <textarea value={description} onChange={e => setDescription(e.target.value)} rows={2}
                placeholder="Collier rouge, puce tatouage N°…" className={`${inputCls} resize-none`} />
            </div>

            {/* Contact */}
            <div>
              <label className={labelCls}>Contact (téléphone ou email)</label>
              <input value={contact} onChange={e => setContact(e.target.value)} placeholder="06 XX XX XX XX" className={inputCls} />
            </div>

            {error && <p className="text-red-500 text-sm">{error}</p>}

            <div className="flex gap-3 pt-1">
              <button type="submit" disabled={saving}
                className="flex-1 bg-orange-500 hover:bg-orange-600 disabled:opacity-60 text-white font-semibold py-2.5 rounded-xl transition-colors text-sm">
                {saving ? 'Enregistrement…' : isEdit ? 'Mettre à jour' : 'Déclarer perdu'}
              </button>
              <button type="button" onClick={onClose}
                className="flex-1 border border-gray-200 text-gray-600 font-medium py-2.5 rounded-xl text-sm hover:bg-gray-50 transition-colors">
                Annuler
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  );
}

// ── Modal mise à jour localisation ────────────────────────────────────────────

function LocationModal({ alerte, onClose, onSaved }: {
  alerte: Alerte;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [localisation, setLocalisation] = useState(alerte.derniere_localisation ?? '');
  const [saving, setSaving] = useState(false);

  async function handleSave(e: React.FormEvent) {
    e.preventDefault();
    if (!localisation.trim()) return;
    setSaving(true);
    try {
      await supabase.from('alertes_perdus').update({
        derniere_localisation: localisation.trim(),
      }).eq('id', alerte.id);
      onSaved();
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-md p-6" onClick={e => e.stopPropagation()}>
        <h3 className="font-bold text-[#1F2A2E] text-base mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>
          Mettre à jour la localisation
        </h3>
        <p className="text-gray-400 text-xs mb-4">{alerte.nom_animal}</p>
        <form onSubmit={handleSave} className="space-y-3">
          <LocationInput
            value={localisation}
            onChange={setLocalisation}
            placeholder="Rechercher une adresse…"
          />
          <div className="flex gap-3">
            <button type="submit" disabled={saving || !localisation.trim()}
              className="flex-1 bg-orange-500 hover:bg-orange-600 disabled:opacity-60 text-white font-semibold py-2.5 rounded-xl transition-colors text-sm">
              {saving ? 'Enregistrement…' : 'Mettre à jour'}
            </button>
            <button type="button" onClick={onClose}
              className="flex-1 border border-gray-200 text-gray-600 font-medium py-2.5 rounded-xl text-sm hover:bg-gray-50 transition-colors">
              Annuler
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
