'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { useGardeAccess } from '@/hooks/useGardeAccess';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';

const TEAL = '#0C5C6C';

interface Cle {
  id: string;
  animal_id: string | null;
  owner_uid: string | null;
  description: string;
  statut: string;
  date_recuperation: string | null;
  date_restitution: string | null;
  notes: string | null;
  _animal_nom?: string;
  _client_nom?: string;
}

interface ClientOption {
  animal_id: string;
  animal_nom: string;
  client_uid: string | null;
  client_nom: string;
}

function fmtDate(iso: string) {
  try {
    return new Date(iso).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', year: 'numeric' });
  } catch { return iso; }
}

export default function ClesClientsPage() {
  const { user, userData, isGarde, loading: authLoading } = useGardeAccess();
  const router = useRouter();
  const activeProfileId = useActiveProfile();

  const [tab, setTab] = useState<'en_possession' | 'rendues'>('en_possession');
  const [cles, setCles] = useState<Cle[]>([]);
  const [clients, setClients] = useState<ClientOption[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<Cle | 'new' | null>(null);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isGarde) { router.push('/'); return; }
  }, [user, userData, isGarde, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);

    let clesQ = supabase.from('cles_clients').select('*').eq('pro_uid', user.uid);
    if (activeProfileId) clesQ = clesQ.eq('pro_profile_id', activeProfileId) as typeof clesQ;
    const { data: clesData } = await clesQ.order('created_at', { ascending: false });
    const clesRows = (clesData ?? []) as Cle[];

    let rdvQ = supabase.from('rdv').select('client_uid, animal_id').eq('pro_uid', user.uid);
    if (activeProfileId) rdvQ = rdvQ.eq('pro_profile_id', activeProfileId) as typeof rdvQ;
    const { data: rdvData } = await rdvQ.in('statut', ['confirme', 'termine']).not('animal_id', 'is', null);
    const rdvRows = (rdvData ?? []) as { client_uid: string | null; animal_id: string | null }[];

    const seenAnimals = new Map<string, string | null>();
    for (const r of rdvRows) {
      if (r.animal_id) seenAnimals.set(r.animal_id, r.client_uid);
    }

    const animalIds = [...new Set([...seenAnimals.keys(), ...clesRows.map(c => c.animal_id).filter((a): a is string => !!a)])];
    const clientUids = [...new Set([...seenAnimals.values(), ...clesRows.map(c => c.owner_uid)].filter((u): u is string => !!u))];

    const [{ data: animaux }, { data: users }] = await Promise.all([
      animalIds.length
        ? supabase.from('animaux').select('id, nom').in('id', animalIds)
        : Promise.resolve({ data: [] as { id: string; nom: string | null }[] }),
      clientUids.length
        ? supabase.from('user_profiles').select('uid, firstname, lastname, nom').in('uid', clientUids).eq('is_main', true)
        : Promise.resolve({ data: [] as { uid: string; firstname: string | null; lastname: string | null; nom: string | null }[] }),
    ]);

    const animalNames = new Map((animaux ?? []).map(a => [a.id, a.nom || 'Animal']));
    const clientNames = new Map((users ?? []).map(u => {
      const nom = u.nom?.trim();
      const full = nom || `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim();
      return [u.uid, full || 'Client'];
    }));

    setCles(clesRows.map(c => ({
      ...c,
      _animal_nom: c.animal_id ? animalNames.get(c.animal_id) ?? 'Animal' : 'Animal',
      _client_nom: c.owner_uid ? clientNames.get(c.owner_uid) ?? 'Client' : 'Client',
    })));

    setClients([...seenAnimals.entries()].map(([animal_id, client_uid]) => ({
      animal_id,
      animal_nom: animalNames.get(animal_id) ?? 'Animal',
      client_uid,
      client_nom: client_uid ? clientNames.get(client_uid) ?? 'Client' : 'Client',
    })).sort((a, b) => a.animal_nom.localeCompare(b.animal_nom)));

    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  async function toggleStatut(cle: Cle) {
    const rendue = cle.statut === 'rendue';
    await supabase.from('cles_clients').update({
      statut: rendue ? 'en_possession' : 'rendue',
      ...(rendue ? {} : { date_restitution: new Date().toISOString().slice(0, 10) }),
      updated_at: new Date().toISOString(),
    }).eq('id', cle.id);
    load();
  }

  async function deleteCle(cle: Cle) {
    if (!confirm('Supprimer cette clé ? Cette action est irréversible.')) return;
    await supabase.from('cles_clients').delete().eq('id', cle.id);
    load();
  }

  if (authLoading || loading) {
    return <div className="flex justify-center py-32"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  }

  const enPossession = cles.filter(c => c.statut !== 'rendue');
  const rendues = cles.filter(c => c.statut === 'rendue');
  const displayed = tab === 'en_possession' ? enPossession : rendues;

  return (
    <div className="max-w-3xl mx-auto px-4 py-8">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold font-galey" style={{ color: TEAL }}>Gestion des clés</h1>
        <button onClick={() => setEditing('new')}
          className="text-sm font-semibold font-galey text-white rounded-xl px-4 py-2"
          style={{ backgroundColor: TEAL }}>
          + Ajouter
        </button>
      </div>

      <div className="flex bg-gray-100 rounded-xl p-1 mb-6 max-w-sm">
        {(['en_possession', 'rendues'] as const).map(t => (
          <button key={t} onClick={() => setTab(t)}
            className={`flex-1 py-2 rounded-lg text-sm font-medium font-galey transition-colors ${tab === t ? 'bg-white shadow-sm text-[#1F2A2E]' : 'text-gray-500'}`}>
            {t === 'en_possession' ? `En ma possession (${enPossession.length})` : `Rendues (${rendues.length})`}
          </button>
        ))}
      </div>

      {displayed.length === 0 ? (
        <p className="text-center text-gray-400 font-galey py-16">
          {tab === 'en_possession' ? 'Aucune clé en votre possession' : 'Aucune clé rendue'}
        </p>
      ) : (
        <div className="space-y-3">
          {displayed.map(cle => {
            const rendue = cle.statut === 'rendue';
            return (
              <div key={cle.id} className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
                <div className="flex items-start justify-between mb-2">
                  <p className="font-bold font-galey text-sm text-[#1F2A2E]">🔑 {cle._animal_nom} — {cle._client_nom}</p>
                  <span className={`text-xs font-semibold font-galey px-2 py-1 rounded-full whitespace-nowrap ${rendue ? 'bg-[#EEF5EA] text-[#6E9E57]' : 'bg-[#E8F4F6] text-[#0C5C6C]'}`}>
                    {rendue ? 'Rendue' : 'En ma possession'}
                  </span>
                </div>
                <p className="text-sm font-galey text-[#1F2A2E] mb-1">{cle.description}</p>
                {cle.notes && <p className="text-xs font-galey text-gray-500 italic mb-1">{cle.notes}</p>}
                <p className="text-xs font-galey text-gray-400 mb-3">
                  {rendue && cle.date_restitution
                    ? `Rendue le ${fmtDate(cle.date_restitution)}`
                    : cle.date_recuperation
                      ? `Récupérée le ${fmtDate(cle.date_recuperation)}`
                      : ''}
                </p>
                <div className="flex gap-2">
                  <button onClick={() => toggleStatut(cle)}
                    className="flex-1 text-xs font-medium font-galey border border-gray-200 rounded-xl py-2 hover:bg-gray-50">
                    {rendue ? 'Marquer récupérée' : 'Marquer rendue'}
                  </button>
                  <button onClick={() => setEditing(cle)}
                    className="text-xs font-medium font-galey border border-gray-200 rounded-xl px-3 py-2 hover:bg-gray-50">
                    Modifier
                  </button>
                  <button onClick={() => deleteCle(cle)}
                    className="text-xs font-medium font-galey border border-red-200 text-red-500 rounded-xl px-3 py-2 hover:bg-red-50">
                    Supprimer
                  </button>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {editing && (
        <CleModal
          cle={editing === 'new' ? null : editing}
          clients={clients}
          uid={user?.uid ?? ''}
          profileId={activeProfileId}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); load(); }}
        />
      )}
    </div>
  );
}

function CleModal({ cle, clients, uid, profileId, onClose, onSaved }: {
  cle: Cle | null;
  clients: ClientOption[];
  uid: string;
  profileId: string | null;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [animalId, setAnimalId] = useState(cle?.animal_id ?? clients[0]?.animal_id ?? '');
  const [description, setDescription] = useState(cle?.description ?? '');
  const [notes, setNotes] = useState(cle?.notes ?? '');
  const [saving, setSaving] = useState(false);

  async function save() {
    if (!description.trim()) return;
    setSaving(true);
    if (cle) {
      await supabase.from('cles_clients').update({
        description: description.trim(),
        notes: notes.trim() || null,
        updated_at: new Date().toISOString(),
      }).eq('id', cle.id);
    } else {
      if (!animalId) { setSaving(false); return; }
      const client = clients.find(c => c.animal_id === animalId);
      await supabase.from('cles_clients').insert({
        pro_uid: uid,
        ...(profileId ? { pro_profile_id: profileId } : {}),
        animal_id: animalId,
        owner_uid: client?.client_uid ?? null,
        description: description.trim(),
        notes: notes.trim() || null,
        date_recuperation: new Date().toISOString().slice(0, 10),
      });
    }
    setSaving(false);
    onSaved();
  }

  return (
    <div className="fixed inset-0 bg-black/40 flex items-end sm:items-center justify-center z-50 p-4">
      <div className="bg-white rounded-2xl w-full max-w-md p-6">
        <h2 className="font-bold font-galey text-lg mb-4 text-[#1F2A2E]">{cle ? 'Modifier la clé' : 'Nouvelle clé'}</h2>

        {!cle && (
          clients.length === 0 ? (
            <p className="text-sm font-galey text-gray-500 mb-4">Aucun client disponible — un RDV confirmé est requis avant d&apos;ajouter une clé.</p>
          ) : (
            <select value={animalId} onChange={e => setAnimalId(e.target.value)}
              className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm font-galey mb-4">
              {clients.map(c => (
                <option key={c.animal_id} value={c.animal_id}>{c.animal_nom} — {c.client_nom}</option>
              ))}
            </select>
          )
        )}
        {cle && <p className="text-sm font-galey font-semibold text-[#1F2A2E] mb-4">{cle._animal_nom} — {cle._client_nom}</p>}

        <textarea value={description} onChange={e => setDescription(e.target.value)}
          placeholder="Ex : clé sous le paillasson, digicode 1234B…"
          rows={2}
          className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm font-galey mb-3" />

        <textarea value={notes} onChange={e => setNotes(e.target.value)}
          placeholder="Notes (facultatif) — consignes particulières…"
          rows={2}
          className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm font-galey mb-4" />

        <div className="flex gap-2">
          <button onClick={onClose}
            className="flex-1 text-sm font-medium font-galey border border-gray-200 rounded-xl py-2">
            Annuler
          </button>
          <button onClick={save}
            disabled={saving || !description.trim() || (!cle && clients.length === 0)}
            className="flex-1 text-sm font-semibold font-galey text-white rounded-xl py-2 disabled:opacity-50"
            style={{ backgroundColor: TEAL }}>
            {saving ? '…' : cle ? 'Enregistrer' : 'Ajouter'}
          </button>
        </div>
      </div>
    </div>
  );
}
