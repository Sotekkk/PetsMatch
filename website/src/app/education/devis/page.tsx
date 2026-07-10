'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

interface Ligne { description: string; quantite: number; prix_unitaire: number; total: number; }

interface Devis {
  id: string;
  numero_devis: string | null;
  date_devis: string;
  date_validite: string | null;
  client_uid: string | null;
  animal_id: string | null;
  nom_client: string | null;
  prenom_client: string | null;
  email_client: string | null;
  telephone_client: string | null;
  lignes: Ligne[];
  total_ttc: number;
  note: string | null;
  statut: string;
  token_acceptation: string;
  date_reponse: string | null;
  created_at: string;
}

interface UserResult {
  uid: string; firstname?: string; lastname?: string; email?: string; phone_number?: string; profile_id?: string;
}

interface AnimalOption { id: string; nom: string; espece: string | null; }

const STATUT_STYLE: Record<string, string> = {
  brouillon: 'bg-gray-100 text-gray-600',
  envoye:    'bg-blue-100 text-blue-700',
  accepte:   'bg-green-100 text-green-700',
  refuse:    'bg-red-100 text-red-600',
  expire:    'bg-amber-100 text-amber-700',
};
const STATUT_LABEL: Record<string, string> = {
  brouillon: 'Brouillon', envoye: 'Envoyé', accepte: 'Accepté', refuse: 'Refusé', expire: 'Expiré',
};

export default function DevisPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const activeProfileId = useActiveProfile();

  const [devisList, setDevisList] = useState<Devis[]>([]);
  const [fetching, setFetching] = useState(true);
  const [showForm, setShowForm] = useState(false);
  const [tarifs, setTarifs] = useState<Record<string, number>>({});
  const [forfaits, setForfaits] = useState<{ id: string; nom: string; prix: number }[]>([]);
  const [newLink, setNewLink] = useState<string | null>(null);

  // Form state
  const [nomClient, setNomClient] = useState('');
  const [prenomClient, setPrenomClient] = useState('');
  const [emailClient, setEmailClient] = useState('');
  const [telClient, setTelClient] = useState('');
  const [clientUid, setClientUid] = useState<string | null>(null);
  const [clientProfileId, setClientProfileId] = useState<string | null>(null);
  const [dateValidite, setDateValidite] = useState('');
  const [note, setNote] = useState('');
  const [lignes, setLignes] = useState<Ligne[]>([{ description: '', quantite: 1, prix_unitaire: 0, total: 0 }]);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const [userSearch, setUserSearch] = useState('');
  const [userResults, setUserResults] = useState<UserResult[]>([]);
  const [userSearchLoading, setUserSearchLoading] = useState(false);
  const [deleteConfirmId, setDeleteConfirmId] = useState<string | null>(null);
  const [animaux, setAnimaux] = useState<AnimalOption[]>([]);
  const [animalId, setAnimalId] = useState('');
  const [catPro, setCatPro] = useState('');

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);

  useEffect(() => {
    if (!user) return;
    Promise.all([
      supabase.from('devis').select('*').eq('pro_uid', user.uid).order('created_at', { ascending: false }),
      supabase.from('user_profiles').select('tarifs_education, profile_type, cat_pro').eq('id', activeProfileId).maybeSingle(),
      activeProfileId
        ? supabase.from('animal_access').select('animal_id').eq('pro_profile_id', activeProfileId).in('statut', ['active', 'active_write'])
        : Promise.resolve({ data: [] }),
    ]).then(async ([d, t, acc]) => {
      const pt = (t.data?.profile_type ?? t.data?.cat_pro ?? '') as string;
      setCatPro(pt);
      setDevisList((d.data ?? []) as Devis[]);
      setTarifs((t.data?.tarifs_education ?? {}) as Record<string, number>);
      const forfaitsTable = pt === 'garde' ? 'forfaits_garde' : 'forfaits_education';
      const { data: forfaitsData } = await supabase.from(forfaitsTable).select('id,nom,prix').eq('pro_uid', user.uid).eq('actif', true);
      setForfaits((forfaitsData ?? []) as { id: string; nom: string; prix: number }[]);
      const animalIds = [...new Set(((acc.data ?? []) as { animal_id: string }[]).map(a => a.animal_id))];
      if (animalIds.length > 0) {
        const { data: anims } = await supabase.from('animaux').select('id,nom,espece').in('id', animalIds);
        setAnimaux((anims ?? []) as AnimalOption[]);
      }
      setFetching(false);
    });
  }, [user, activeProfileId]);

  async function searchUsers(q: string) {
    setUserSearch(q);
    setClientUid(null); setClientProfileId(null);
    const query = q.trim();
    if (query.length < 2) { setUserResults([]); return; }
    setUserSearchLoading(true);
    const cpFields = 'id,uid,firstname,lastname,phone_number';
    if (query.includes('@')) {
      const { data: users } = await supabase.from('users').select('uid, email')
        .ilike('email', `%${query}%`).neq('uid', user?.uid ?? '').limit(6);
      const uids = (users ?? []).map(u => u.uid);
      const emailByUid = new Map((users ?? []).map(u => [u.uid, u.email as string]));
      const { data: cps } = uids.length
        ? await supabase.from('user_profiles').select(cpFields).in('uid', uids).eq('is_main', true)
        : { data: [] as Record<string, unknown>[] };
      setUserResults((cps ?? []).map(cp => ({
        uid: cp.uid as string, firstname: cp.firstname as string, lastname: cp.lastname as string,
        email: emailByUid.get(cp.uid as string) ?? '', phone_number: cp.phone_number as string,
        profile_id: cp.id as string,
      })));
    } else {
      const { data: cps } = await supabase.from('user_profiles').select(`${cpFields},email_contact`)
        .or(`firstname.ilike.%${query}%,lastname.ilike.%${query}%`)
        .neq('uid', user?.uid ?? '').eq('is_main', true).limit(6);
      setUserResults((cps ?? []).map(cp => ({
        uid: cp.uid as string, firstname: cp.firstname as string, lastname: cp.lastname as string,
        email: (cp.email_contact as string) ?? '', phone_number: cp.phone_number as string,
        profile_id: cp.id as string,
      })));
    }
    setUserSearchLoading(false);
  }

  function prefillUser(u: UserResult) {
    setNomClient(u.lastname ?? '');
    setPrenomClient(u.firstname ?? '');
    setEmailClient(u.email ?? '');
    setTelClient(u.phone_number ?? '');
    setClientUid(u.uid);
    setClientProfileId(u.profile_id ?? null);
    setUserSearch(`${u.firstname ?? ''} ${u.lastname ?? ''}`.trim());
    setUserResults([]);
  }

  function updateLigne(i: number, patch: Partial<Ligne>) {
    setLignes(prev => prev.map((l, idx) => {
      if (idx !== i) return l;
      const merged = { ...l, ...patch };
      merged.total = Math.round(merged.quantite * merged.prix_unitaire * 100) / 100;
      return merged;
    }));
  }

  function addLigne(description: string, prix: number) {
    setLignes(prev => [...prev, { description, quantite: 1, prix_unitaire: prix, total: prix }]);
  }

  function removeLigne(i: number) {
    setLignes(prev => prev.filter((_, idx) => idx !== i));
  }

  const totalTtc = lignes.reduce((s, l) => s + (l.total || 0), 0);

  function resetForm() {
    setNomClient(''); setPrenomClient(''); setEmailClient(''); setTelClient('');
    setClientUid(null); setClientProfileId(null);
    setDateValidite(''); setNote(''); setAnimalId('');
    setLignes([{ description: '', quantite: 1, prix_unitaire: 0, total: 0 }]);
    setUserSearch(''); setUserResults([]);
    setError('');
  }

  // Le devis lié à un animal apparaît dans les documents de l'animal (visible par
  // le propriétaire) — l'éducateur, lui, n'a pas accès à l'onglet Documents de la fiche.
  async function syncDocumentAnimal(devisId: string, animal: string, statut: string, token: string, total: number) {
    if (!user || !animal) return;
    const docStatut = statut === 'accepte' ? 'signe' : statut === 'refuse' ? 'refuse' : statut === 'brouillon' ? 'brouillon' : 'en_attente';
    const { data: existing } = await supabase.from('documents_animaux').select('id')
      .eq('animal_id', animal).eq('type', 'devis').contains('metadata', { devis_id: devisId }).maybeSingle();
    if (existing) {
      await supabase.from('documents_animaux').update({ statut: docStatut }).eq('id', existing.id);
    } else {
      await supabase.from('documents_animaux').insert({
        animal_id: animal,
        uid_eleveur: user.uid,
        pro_profile_id: activeProfileId || null,
        type: 'devis',
        titre: `Devis — ${total.toFixed(2)} €`,
        url: `${window.location.origin}/devis/${token}`,
        statut: docStatut,
        metadata: { devis_id: devisId, token },
      });
    }
  }

  async function handleCreate(envoyer: boolean) {
    if (!user) return;
    const validLignes = lignes.filter(l => l.description.trim());
    if (!nomClient.trim() || !emailClient.trim()) {
      setError('Nom et email du client sont obligatoires.');
      return;
    }
    if (validLignes.length === 0) {
      setError('Ajoutez au moins une ligne de prestation.');
      return;
    }
    setSaving(true);
    setError('');
    try {
      const token = crypto.randomUUID();
      const row = {
        pro_uid: user.uid,
        pro_profile_id: activeProfileId || null,
        date_devis: new Date().toISOString().slice(0, 10),
        date_validite: dateValidite || null,
        client_uid: clientUid,
        client_profile_id: clientProfileId,
        animal_id: animalId || null,
        nom_client: nomClient.trim(),
        prenom_client: prenomClient.trim(),
        email_client: emailClient.trim(),
        telephone_client: telClient.trim() || null,
        lignes: validLignes,
        total_ttc: totalTtc,
        note: note.trim() || null,
        statut: envoyer ? 'envoye' : 'brouillon',
        token_acceptation: token,
      };
      const { data, error: err } = await supabase.from('devis').insert(row).select().single();
      if (err) { setError(err.message); return; }

      if (envoyer && clientUid) {
        await supabase.from('notifications').insert({
          uid: clientUid,
          type: 'devis_recu',
          title: 'Vous avez reçu un devis',
          body: `Un devis de ${totalTtc.toFixed(2)} € vous a été envoyé.`,
          data: { devis_id: data.id, token },
          read: false,
        });
      }
      if (animalId) await syncDocumentAnimal(data.id, animalId, row.statut, token, totalTtc);

      setDevisList(prev => [data as Devis, ...prev]);
      setShowForm(false);
      if (envoyer) setNewLink(`${window.location.origin}/devis/${token}`);
      resetForm();
    } finally {
      setSaving(false);
    }
  }

  async function handleSend(d: Devis) {
    await supabase.from('devis').update({ statut: 'envoye', updated_at: new Date().toISOString() }).eq('id', d.id);
    if (d.client_uid) {
      await supabase.from('notifications').insert({
        uid: d.client_uid,
        type: 'devis_recu',
        title: 'Vous avez reçu un devis',
        body: `Un devis de ${d.total_ttc.toFixed(2)} € vous a été envoyé.`,
        data: { devis_id: d.id, token: d.token_acceptation },
        read: false,
      });
    }
    if (d.animal_id) await syncDocumentAnimal(d.id, d.animal_id, 'envoye', d.token_acceptation, d.total_ttc);
    setDevisList(prev => prev.map(x => x.id === d.id ? { ...x, statut: 'envoye' } : x));
    setNewLink(`${window.location.origin}/devis/${d.token_acceptation}`);
  }

  async function handleDelete(id: string) {
    await supabase.from('devis').delete().eq('id', id).neq('statut', 'accepte');
    setDevisList(prev => prev.filter(d => d.id !== id));
    setDeleteConfirmId(null);
  }

  if (loading) return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;

  const origin = typeof window !== 'undefined' ? window.location.origin : 'https://www.petsmatchapp.com';

  return (
    <div className="max-w-4xl mx-auto px-4 py-10">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Devis</h1>
          <p className="text-gray-500 text-sm">Créez et envoyez un devis pour vos prestations</p>
        </div>
        <button onClick={() => { setShowForm(true); setNewLink(null); }}
          className="bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold px-5 py-2.5 rounded-xl text-sm">
          + Nouveau devis
        </button>
      </div>

      {newLink && (
        <div className="mb-6 bg-green-50 border border-green-200 rounded-xl p-4">
          <p className="text-sm font-semibold text-green-800 mb-1">✅ Devis envoyé — partagez ce lien au client :</p>
          <div className="flex items-center gap-2 mt-2">
            <code className="text-xs bg-white border border-green-200 rounded px-3 py-2 flex-1 text-green-700 break-all">{newLink}</code>
            <button onClick={() => navigator.clipboard.writeText(newLink)}
              className="shrink-0 bg-green-600 hover:bg-green-700 text-white text-xs font-semibold px-3 py-2 rounded-lg">
              Copier
            </button>
          </div>
        </div>
      )}

      {showForm && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-start justify-center overflow-y-auto py-8 px-4">
          <div className="bg-white rounded-2xl shadow-2xl w-full max-w-2xl p-6">
            <div className="flex items-center justify-between mb-5">
              <h2 className="text-lg font-bold text-[#1F2A2E]">Nouveau devis</h2>
              <button onClick={() => { setShowForm(false); resetForm(); }} className="text-gray-400 hover:text-gray-600 text-xl">✕</button>
            </div>

            {error && <div className="mb-4 text-sm text-red-600 bg-red-50 border border-red-200 rounded-lg px-4 py-2">{error}</div>}

            <div className="space-y-4">
              {/* Client */}
              <div>
                <p className="text-xs font-semibold text-gray-500 uppercase mb-2">Client</p>
                <div className="relative mb-3">
                  <input
                    value={userSearch}
                    onChange={e => searchUsers(e.target.value)}
                    placeholder="Rechercher un utilisateur PetsMatch (optionnel)…"
                    className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm pr-8 focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
                  />
                  {userSearchLoading && <span className="absolute right-2 top-2.5 text-gray-400 text-xs">…</span>}
                  {userResults.length > 0 && (
                    <div className="absolute z-20 w-full bg-white border border-gray-200 rounded-xl shadow-lg mt-1 max-h-48 overflow-y-auto">
                      {userResults.map(u => (
                        <button key={u.uid} onClick={() => prefillUser(u)}
                          className="w-full text-left px-4 py-2.5 hover:bg-[#E8F4F6] text-sm flex flex-col">
                          <span className="font-medium text-[#1F2A2E]">{u.firstname} {u.lastname}</span>
                          <span className="text-xs text-gray-500">{u.email}</span>
                        </button>
                      ))}
                    </div>
                  )}
                </div>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="block text-xs text-gray-600 mb-1">Nom *</label>
                    <input value={nomClient} onChange={e => setNomClient(e.target.value)} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm" />
                  </div>
                  <div>
                    <label className="block text-xs text-gray-600 mb-1">Prénom</label>
                    <input value={prenomClient} onChange={e => setPrenomClient(e.target.value)} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm" />
                  </div>
                </div>
                <div className="mt-3">
                  <label className="block text-xs text-gray-600 mb-1">Email *</label>
                  <input type="email" value={emailClient} onChange={e => setEmailClient(e.target.value)} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm" />
                </div>
                <div className="mt-3">
                  <label className="block text-xs text-gray-600 mb-1">Téléphone</label>
                  <input value={telClient} onChange={e => setTelClient(e.target.value)} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm" />
                </div>
              </div>

              {/* Lignes */}
              <div className="border-t pt-4">
                <p className="text-xs font-semibold text-gray-500 uppercase mb-2">Prestations</p>
                {(Object.keys(tarifs).length > 0 || forfaits.length > 0) && (
                  <div className="flex flex-wrap gap-2 mb-3">
                    {catPro === 'education' && tarifs.cours_individuel && (
                      <button onClick={() => addLigne('Cours individuel', tarifs.cours_individuel)}
                        className="text-xs border border-[#0C5C6C]/30 text-[#0C5C6C] px-2.5 py-1 rounded-lg hover:bg-[#E8F4F6]">
                        + Cours individuel ({tarifs.cours_individuel} €)
                      </button>
                    )}
                    {catPro === 'education' && tarifs.cours_collectif && (
                      <button onClick={() => addLigne('Cours collectif', tarifs.cours_collectif)}
                        className="text-xs border border-[#0C5C6C]/30 text-[#0C5C6C] px-2.5 py-1 rounded-lg hover:bg-[#E8F4F6]">
                        + Cours collectif ({tarifs.cours_collectif} €)
                      </button>
                    )}
                    {catPro === 'education' && tarifs.evaluation && (
                      <button onClick={() => addLigne('Évaluation', tarifs.evaluation)}
                        className="text-xs border border-[#0C5C6C]/30 text-[#0C5C6C] px-2.5 py-1 rounded-lg hover:bg-[#E8F4F6]">
                        + Évaluation ({tarifs.evaluation} €)
                      </button>
                    )}
                    {forfaits.map(f => (
                      <button key={f.id} onClick={() => addLigne(f.nom, f.prix)}
                        className="text-xs border border-[#7B5EA7]/30 text-[#7B5EA7] px-2.5 py-1 rounded-lg hover:bg-[#7B5EA7]/10">
                        + {f.nom} ({f.prix} €)
                      </button>
                    ))}
                  </div>
                )}
                <div className="space-y-2">
                  {lignes.map((l, i) => (
                    <div key={i} className="flex items-center gap-2">
                      <input value={l.description} onChange={e => updateLigne(i, { description: e.target.value })}
                        placeholder="Description" className="flex-1 border border-gray-200 rounded-lg px-3 py-2 text-sm" />
                      <input type="number" min={1} value={l.quantite}
                        onChange={e => updateLigne(i, { quantite: parseInt(e.target.value) || 1 })}
                        className="w-16 border border-gray-200 rounded-lg px-2 py-2 text-sm text-center" />
                      <input type="number" min={0} step="0.01" value={l.prix_unitaire}
                        onChange={e => updateLigne(i, { prix_unitaire: parseFloat(e.target.value) || 0 })}
                        className="w-24 border border-gray-200 rounded-lg px-2 py-2 text-sm text-right" />
                      <span className="w-20 text-right text-sm font-semibold text-[#1F2A2E]">{l.total.toFixed(2)} €</span>
                      <button onClick={() => removeLigne(i)} className="text-red-400 hover:text-red-600 px-1">✕</button>
                    </div>
                  ))}
                </div>
                <button onClick={() => setLignes(prev => [...prev, { description: '', quantite: 1, prix_unitaire: 0, total: 0 }])}
                  className="mt-2 text-xs text-[#0C5C6C] font-semibold hover:underline">+ Ajouter une ligne</button>
                <div className="flex justify-end mt-3 pt-3 border-t">
                  <span className="text-base font-bold text-[#1F2A2E]">Total : {totalTtc.toFixed(2)} €</span>
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs text-gray-600 mb-1">Date de validité</label>
                  <input type="date" value={dateValidite} onChange={e => setDateValidite(e.target.value)} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm" />
                </div>
                {animaux.length > 0 && (
                  <div>
                    <label className="block text-xs text-gray-600 mb-1">Animal concerné (optionnel)</label>
                    <select value={animalId} onChange={e => setAnimalId(e.target.value)}
                      className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm">
                      <option value="">—</option>
                      {animaux.map(a => <option key={a.id} value={a.id}>{a.nom}{a.espece ? ` (${a.espece})` : ''}</option>)}
                    </select>
                  </div>
                )}
              </div>
              <div>
                <label className="block text-xs text-gray-600 mb-1">Notes internes</label>
                <textarea value={note} onChange={e => setNote(e.target.value)} rows={2} className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm resize-none" />
              </div>
            </div>

            <div className="flex gap-3 mt-6">
              <button onClick={() => { setShowForm(false); resetForm(); }} className="flex-1 border border-gray-200 text-gray-600 font-medium py-2.5 rounded-xl text-sm hover:bg-gray-50">Annuler</button>
              <button onClick={() => handleCreate(false)} disabled={saving}
                className="flex-1 border border-[#0C5C6C]/30 text-[#0C5C6C] font-semibold py-2.5 rounded-xl text-sm hover:bg-[#E8F4F6] disabled:opacity-50">
                Enregistrer en brouillon
              </button>
              <button onClick={() => handleCreate(true)} disabled={saving}
                className="flex-1 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-50 text-white font-semibold py-2.5 rounded-xl text-sm">
                {saving ? 'Envoi…' : 'Créer et envoyer'}
              </button>
            </div>
          </div>
        </div>
      )}

      {fetching ? (
        <div className="text-center py-16 text-gray-400">Chargement…</div>
      ) : devisList.length === 0 ? (
        <div className="text-center py-16 text-gray-400">
          <p className="text-4xl mb-3">📋</p>
          <p className="font-medium text-gray-600">Aucun devis</p>
          <p className="text-sm mt-1">Créez votre premier devis pour un client</p>
        </div>
      ) : (
        <div className="space-y-3">
          {devisList.map(d => (
            <div key={d.id} className="bg-white border border-gray-100 rounded-xl p-4 flex items-center gap-4 shadow-sm">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="font-semibold text-[#1F2A2E] text-sm">{d.prenom_client} {d.nom_client}</span>
                  <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${STATUT_STYLE[d.statut] ?? 'bg-gray-100 text-gray-600'}`}>
                    {STATUT_LABEL[d.statut] ?? d.statut}
                  </span>
                </div>
                <p className="text-xs text-gray-500 mt-1">{d.lignes.length} ligne(s) — {Number(d.total_ttc).toFixed(2)} €</p>
                <p className="text-xs text-gray-400 mt-0.5">
                  Créé le {new Date(d.created_at).toLocaleDateString('fr-FR')}
                  {d.date_reponse && <> · Répondu le {new Date(d.date_reponse).toLocaleDateString('fr-FR')}</>}
                </p>
              </div>
              <div className="flex gap-1.5 shrink-0 flex-wrap justify-end">
                {d.statut === 'brouillon' && (
                  <button onClick={() => handleSend(d)}
                    className="text-xs bg-[#0C5C6C] text-white px-3 py-1.5 rounded-lg hover:bg-[#094F5D] font-medium">
                    Envoyer
                  </button>
                )}
                {d.statut !== 'brouillon' && (
                  <button onClick={() => navigator.clipboard.writeText(`${origin}/devis/${d.token_acceptation}`)}
                    className="text-xs border border-gray-200 text-gray-600 px-3 py-1.5 rounded-lg hover:bg-gray-50">
                    Lien
                  </button>
                )}
                <Link href={`/devis/${d.token_acceptation}`} target="_blank"
                  className="text-xs bg-[#0C5C6C]/10 text-[#0C5C6C] px-3 py-1.5 rounded-lg hover:bg-[#0C5C6C]/20 font-medium">
                  Voir
                </Link>
                {d.statut !== 'accepte' && (
                  deleteConfirmId === d.id ? (
                    <span className="flex gap-1">
                      <button onClick={() => handleDelete(d.id)}
                        className="text-xs bg-red-600 hover:bg-red-700 text-white px-3 py-1.5 rounded-lg font-medium">Confirmer</button>
                      <button onClick={() => setDeleteConfirmId(null)}
                        className="text-xs border border-gray-200 text-gray-500 px-2 py-1.5 rounded-lg hover:bg-gray-50">✕</button>
                    </span>
                  ) : (
                    <button onClick={() => setDeleteConfirmId(d.id)}
                      className="text-xs border border-red-200 text-red-500 px-3 py-1.5 rounded-lg hover:bg-red-50">
                      Supprimer
                    </button>
                  )
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
