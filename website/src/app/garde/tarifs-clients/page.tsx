'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { useGardeAccess } from '@/hooks/useGardeAccess';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';

const TEAL = '#0C5C6C';

const PRESTATIONS_GARDE = [
  { value: 'promenade_30min', label: 'Promenade (30 min)' },
  { value: 'promenade_1h', label: 'Promenade (1h)' },
  { value: 'promenade_2h', label: 'Promenade (2h)' },
  { value: 'garde_journee', label: 'Garde à domicile (journée)' },
  { value: 'autre', label: 'Autre prestation' },
];

interface ClientRow {
  client_profile_id: string;
  client_uid: string | null;
  client_nom: string;
}

export default function TarifsClientsPage() {
  const { user, userData, isGarde, loading: authLoading } = useGardeAccess();
  const router = useRouter();
  const activeProfileId = useActiveProfile();

  const [loading, setLoading] = useState(true);
  const [tarifsBase, setTarifsBase] = useState<Record<string, number>>({});
  const [clients, setClients] = useState<ClientRow[]>([]);
  const [overridesByProfile, setOverridesByProfile] = useState<Record<string, Record<string, number>>>({});
  const [editing, setEditing] = useState<ClientRow | null>(null);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isGarde) { router.push('/'); return; }
  }, [user, userData, isGarde, authLoading, router]);

  const load = useCallback(async () => {
    if (!user || !activeProfileId) return;
    setLoading(true);

    const [{ data: profileRow }, { data: rdvData }, { data: overrideData }] = await Promise.all([
      supabase.from('user_profiles').select('tarifs_garde').eq('id', activeProfileId).maybeSingle(),
      supabase.from('rdv').select('client_uid, client_profile_id, animal_id')
        .eq('pro_uid', user.uid).eq('pro_profile_id', activeProfileId)
        .in('statut', ['confirme', 'termine']).not('client_profile_id', 'is', null),
      supabase.from('tarifs_clients_garde').select('*').eq('pro_uid', user.uid).eq('pro_profile_id', activeProfileId),
    ]);

    const base = (profileRow?.tarifs_garde ?? {}) as Record<string, number>;

    const rdvRows = (rdvData ?? []) as { client_uid: string | null; client_profile_id: string | null; animal_id: string | null }[];
    const seenClients = new Map<string, { client_uid: string | null }>();
    for (const r of rdvRows) {
      if (r.client_profile_id) seenClients.set(r.client_profile_id, { client_uid: r.client_uid });
    }

    const overrideRows = (overrideData ?? []) as { owner_profile_id: string; prestation_type: string; prix: number }[];
    const overrides: Record<string, Record<string, number>> = {};
    for (const o of overrideRows) {
      overrides[o.owner_profile_id] = overrides[o.owner_profile_id] ?? {};
      overrides[o.owner_profile_id][o.prestation_type] = o.prix;
    }

    const clientProfileIds = [...seenClients.keys()];
    let names = new Map<string, string>();
    if (clientProfileIds.length) {
      const { data: profiles } = await supabase.from('user_profiles')
        .select('id, firstname, lastname, nom').in('id', clientProfileIds);
      names = new Map((profiles ?? []).map(p => {
        const nom = (p.nom as string | null)?.trim();
        const full = nom || `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim();
        return [p.id as string, full || 'Client'];
      }));
    }

    const clientRows: ClientRow[] = [...seenClients.entries()].map(([cpid, c]) => ({
      client_profile_id: cpid,
      client_uid: c.client_uid,
      client_nom: names.get(cpid) ?? 'Client',
    })).sort((a, b) => a.client_nom.localeCompare(b.client_nom));

    setTarifsBase(base);
    setClients(clientRows);
    setOverridesByProfile(overrides);
    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  if (authLoading || loading) {
    return <div className="flex justify-center py-32"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  }

  return (
    <div className="max-w-3xl mx-auto px-4 py-8">
      <h1 className="text-2xl font-bold font-galey mb-6" style={{ color: TEAL }}>Tarifs clients</h1>

      {clients.length === 0 ? (
        <p className="text-center text-gray-400 font-galey py-16">Aucun client disponible — un RDV confirmé est requis.</p>
      ) : (
        <div className="space-y-3">
          {clients.map(c => {
            const nbOverrides = Object.keys(overridesByProfile[c.client_profile_id] ?? {}).length;
            return (
              <button key={c.client_profile_id} onClick={() => setEditing(c)}
                className="w-full text-left rounded-2xl border border-gray-100 bg-white p-4 shadow-sm hover:shadow-md transition-shadow flex items-center justify-between">
                <div>
                  <p className="font-bold font-galey text-sm text-[#1F2A2E]">{c.client_nom}</p>
                  <p className={`text-xs font-galey ${nbOverrides > 0 ? 'text-[#6E9E57]' : 'text-gray-400'}`}>
                    {nbOverrides > 0 ? `${nbOverrides} tarif${nbOverrides > 1 ? 's' : ''} personnalisé${nbOverrides > 1 ? 's' : ''}` : 'Tarifs standards'}
                  </p>
                </div>
                <span className="text-gray-300">›</span>
              </button>
            );
          })}
        </div>
      )}

      {editing && (
        <TarifsModal
          client={editing}
          tarifsBase={tarifsBase}
          overrides={overridesByProfile[editing.client_profile_id] ?? {}}
          uid={user?.uid ?? ''}
          profileId={activeProfileId}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); load(); }}
        />
      )}
    </div>
  );
}

function TarifsModal({ client, tarifsBase, overrides, uid, profileId, onClose, onSaved }: {
  client: ClientRow;
  tarifsBase: Record<string, number>;
  overrides: Record<string, number>;
  uid: string;
  profileId: string;
  onClose: () => void;
  onSaved: () => void;
}) {
  const [values, setValues] = useState<Record<string, number>>(() => {
    const init: Record<string, number> = {};
    for (const p of PRESTATIONS_GARDE) init[p.value] = overrides[p.value] ?? tarifsBase[p.value] ?? 0;
    return init;
  });
  const [saving, setSaving] = useState(false);

  async function save() {
    setSaving(true);
    for (const p of PRESTATIONS_GARDE) {
      const val = values[p.value] ?? 0;
      const base = tarifsBase[p.value] ?? 0;
      if (val === base) {
        await supabase.from('tarifs_clients_garde').delete()
          .eq('pro_profile_id', profileId).eq('owner_profile_id', client.client_profile_id).eq('prestation_type', p.value);
      } else {
        await supabase.from('tarifs_clients_garde').upsert({
          pro_uid: uid,
          pro_profile_id: profileId,
          owner_uid: client.client_uid,
          owner_profile_id: client.client_profile_id,
          prestation_type: p.value,
          prix: val,
          updated_at: new Date().toISOString(),
        }, { onConflict: 'pro_profile_id,owner_profile_id,prestation_type' });
      }
    }
    setSaving(false);
    onSaved();
  }

  return (
    <div className="fixed inset-0 bg-black/40 flex items-end sm:items-center justify-center z-50 p-4">
      <div className="bg-white rounded-2xl w-full max-w-md p-6">
        <h2 className="font-bold font-galey text-lg mb-1 text-[#1F2A2E]">Tarifs — {client.client_nom}</h2>
        <p className="text-xs font-galey text-gray-400 mb-4">Laissez le tarif standard si aucune remise particulière.</p>

        <div className="space-y-3 mb-4">
          {PRESTATIONS_GARDE.map(p => (
            <div key={p.value} className="flex items-center justify-between gap-3">
              <div>
                <p className="text-sm font-galey font-semibold text-[#1F2A2E]">{p.label}</p>
                <p className="text-xs font-galey text-gray-400">Standard : {tarifsBase[p.value] ?? 0} €</p>
              </div>
              <input type="number" min={0} step={1}
                value={values[p.value] ?? 0}
                onChange={e => setValues(v => ({ ...v, [p.value]: Number(e.target.value) }))}
                className="w-20 border border-gray-200 rounded-xl px-2 py-2 text-sm font-galey text-center" />
            </div>
          ))}
        </div>

        <div className="flex gap-2">
          <button onClick={onClose}
            className="flex-1 text-sm font-medium font-galey border border-gray-200 rounded-xl py-2">
            Annuler
          </button>
          <button onClick={save} disabled={saving}
            className="flex-1 text-sm font-semibold font-galey text-white rounded-xl py-2 disabled:opacity-50"
            style={{ backgroundColor: TEAL }}>
            {saving ? '…' : 'Enregistrer'}
          </button>
        </div>
      </div>
    </div>
  );
}
