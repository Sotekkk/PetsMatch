'use client';

// Pet-sitter : « Tarifs & forfaits », page unique des prix (13/11/2026).
//   • Tarifs : grille standard (user_profiles.tarifs_garde), visite d'essai
//     (clés essai_* du même JSON, lib/garde-essai.ts), prestations sur mesure
//     (tarifs_garde_extra), affichage sur la fiche (tarifs_garde_visibles).
//   • Forfaits : packs de visites ou de promenades (forfaits_garde).
//   • Par client : tarif propre à un client (tarifs_clients_garde).
// Les prix restent visibles à la réservation, même masqués sur la fiche.
// Miroir appli : lib/pages/pro/tarifs_clients_page.dart.

import { useState, useEffect, useCallback, Suspense } from 'react';
import { useRouter, useSearchParams } from 'next/navigation';
import { useGardeAccess } from '@/hooks/useGardeAccess';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { nomClientProfil } from '@/lib/nom-client';
import { uniteForfaitGarde } from '@/lib/forfait-garde';

const TEAL = '#0C5C6C';

const PRESTATIONS_GARDE = [
  { value: 'promenade_30min', label: 'Promenade (30 min)' },
  { value: 'promenade_1h', label: 'Promenade (1h)' },
  { value: 'promenade_2h', label: 'Promenade (2h)' },
  { value: 'visite', label: 'Visite à domicile' },
  { value: 'garde_journee', label: 'Garde à domicile (journée)' },
  { value: 'animal_supplementaire', label: 'Animal supplémentaire (par passage)' },
  { value: 'autre', label: 'Autre prestation' },
];

type Onglet = 'tarifs' | 'forfaits' | 'clients';

interface ClientRow {
  client_profile_id: string;
  client_uid: string | null;
  client_nom: string;
}

interface Extra { k: number; label: string; prix: number; description: string }

interface Forfait {
  id: string; nom: string; nb_visites: number; prix: number;
  description?: string | null; type_prestation?: string; affiche_public?: boolean;
}

const inputCls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm font-galey';

export default function TarifsForfaitsPage() {
  return <Suspense fallback={null}><TarifsForfaits /></Suspense>;
}

function TarifsForfaits() {
  const { user, userData, isGarde, loading: authLoading } = useGardeAccess();
  const router = useRouter();
  const params = useSearchParams();
  const activeProfileId = useActiveProfile();

  const [onglet, setOnglet] = useState<Onglet>(() => {
    const o = params.get('onglet');
    return o === 'forfaits' || o === 'clients' ? o : 'tarifs';
  });
  const [loading, setLoading] = useState(true);
  const [tarifsBase, setTarifsBase] = useState<Record<string, number>>({});
  const [extra, setExtra] = useState<Extra[]>([]);
  const [visibles, setVisibles] = useState(true);
  const [modifie, setModifie] = useState(false);
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [forfaits, setForfaits] = useState<Forfait[]>([]);
  const [forfaitEdite, setForfaitEdite] = useState<Forfait | 'nouveau' | null>(null);
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

    const [{ data: profileRow }, { data: rdvData }, { data: overrideData }, { data: forfaitsData }] = await Promise.all([
      supabase.from('user_profiles_complet').select('*').eq('id', activeProfileId).maybeSingle(),
      supabase.from('rdv').select('client_uid, client_profile_id, animal_id')
        .eq('pro_uid', user.uid).eq('pro_profile_id', activeProfileId)
        .in('statut', ['confirme', 'termine']).not('client_profile_id', 'is', null),
      supabase.from('tarifs_clients_garde').select('*').eq('pro_uid', user.uid).eq('pro_profile_id', activeProfileId),
      supabase.from('forfaits_garde').select('*').eq('pro_uid', user.uid).eq('actif', true)
        .or(`pro_profile_id.eq.${activeProfileId},pro_profile_id.is.null`).order('created_at'),
    ]);

    const p = (profileRow ?? {}) as Record<string, unknown>;
    const base: Record<string, number> = {};
    for (const [k, v] of Object.entries((p.tarifs_garde ?? {}) as Record<string, unknown>)) base[k] = Number(v) || 0;
    const ex = Array.isArray(p.tarifs_garde_extra) ? p.tarifs_garde_extra as { label?: string; prix?: number; description?: string }[] : [];

    const rdvRows = (rdvData ?? []) as { client_uid: string | null; client_profile_id: string | null }[];
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
      const { data: profiles } = await supabase.from('user_profiles_complet')
        .select('id, firstname, lastname, nom, profile_type').in('id', clientProfileIds);
      names = new Map((profiles ?? []).map(pr => [pr.id as string, nomClientProfil(pr, 'Client')]));
    }

    setTarifsBase(base);
    setExtra(ex.map((e, i) => ({ k: i + 1, label: e.label ?? '', prix: Number(e.prix) || 0, description: e.description ?? '' })));
    setVisibles(p.tarifs_garde_visibles !== false);
    setForfaits((forfaitsData ?? []) as Forfait[]);
    setClients([...seenClients.entries()].map(([cpid, c]) => ({
      client_profile_id: cpid, client_uid: c.client_uid, client_nom: names.get(cpid) ?? 'Client',
    })).sort((a, b) => a.client_nom.localeCompare(b.client_nom)));
    setOverridesByProfile(overrides);
    setModifie(false);
    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  const majBase = (k: string, v: number) => { setTarifsBase(t => ({ ...t, [k]: v })); setModifie(true); setMessage(null); };
  const majExtra = (fn: (e: Extra[]) => Extra[]) => { setExtra(fn); setModifie(true); setMessage(null); };

  async function enregistrerTarifs() {
    if (!activeProfileId) return;
    setSaving(true);
    const maj = {
      tarifs_garde: tarifsBase,
      tarifs_garde_extra: extra.filter(e => e.label.trim()).map(e => ({
        label: e.label.trim(), prix: e.prix || 0, ...(e.description.trim() ? { description: e.description.trim() } : {}),
      })),
    };
    let { error } = await supabase.from('user_profiles').update({ ...maj, tarifs_garde_visibles: visibles }).eq('id', activeProfileId);
    // migration_garde_tarifs_visibles.sql pas encore passée.
    if (error) ({ error } = await supabase.from('user_profiles').update(maj).eq('id', activeProfileId));
    setSaving(false);
    if (error) { setMessage(`Erreur : ${error.message}`); return; }
    setModifie(false);
    setMessage('Tarifs enregistrés.');
  }

  async function basculerPublic(f: Forfait, v: boolean) {
    setForfaits(prev => prev.map(x => x.id === f.id ? { ...x, affiche_public: v } : x));
    const { error } = await supabase.from('forfaits_garde').update({ affiche_public: v }).eq('id', f.id);
    if (error) load();
  }

  async function supprimerForfait(f: Forfait) {
    if (!confirm(`Supprimer le forfait « ${f.nom} » ? Il ne sera plus proposé. Les gardes déjà réservées avec ce forfait ne changent pas.`)) return;
    await supabase.from('forfaits_garde').update({ actif: false }).eq('id', f.id);
    load();
  }

  if (authLoading || loading) {
    return <div className="flex justify-center py-32"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  }

  const essai = tarifsBase.essai_actif === 1;

  return (
    <div className="max-w-3xl mx-auto px-4 py-8 font-galey">
      <h1 className="text-2xl font-bold mb-1" style={{ color: TEAL }}>Tarifs &amp; forfaits</h1>
      <p className="text-sm text-gray-500 mb-5">Vos prix, la visite d&apos;essai, vos forfaits et les prix particuliers de vos clients.</p>

      <div className="flex gap-1 bg-gray-100 rounded-xl p-1 mb-5">
        {([['tarifs', 'Tarifs'], ['forfaits', 'Forfaits'], ['clients', 'Par client']] as const).map(([k, l]) => (
          <button key={k} onClick={() => setOnglet(k)}
            className={`flex-1 py-2 rounded-lg text-sm font-semibold transition-colors ${onglet === k ? 'bg-white shadow-sm text-[#0C5C6C]' : 'text-gray-500'}`}>
            {l}
          </button>
        ))}
      </div>

      {onglet === 'tarifs' && (
        <div className="space-y-4">
          <section className="bg-white rounded-2xl border border-gray-100 p-4 shadow-sm">
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="text-sm font-bold text-[#1F2A2E]">Afficher mes tarifs et forfaits sur ma fiche publique</p>
                <p className="text-xs text-gray-500 mt-0.5">
                  {visibles ? 'Visibles sur votre fiche, sur le site et dans l’appli.'
                    : 'Votre fiche affiche « Tarifs sur demande ». Le client voit toujours le prix au moment de réserver.'}
                </p>
              </div>
              <button type="button" onClick={() => { setVisibles(v => !v); setModifie(true); setMessage(null); }}
                aria-label="Afficher mes tarifs sur ma fiche publique"
                className="relative w-11 h-6 rounded-full transition-colors flex-shrink-0"
                style={{ backgroundColor: visibles ? TEAL : '#9CA3AF' }}>
                <span className="absolute top-0.5 left-0.5 w-5 h-5 bg-white rounded-full transition-transform"
                  style={{ transform: visibles ? 'translateX(20px)' : 'translateX(0)' }} />
              </button>
            </div>
          </section>

          <section className="bg-white rounded-2xl border border-gray-100 p-4 shadow-sm">
            <p className="text-sm font-bold text-[#1F2A2E]">Tarifs standard (€ TTC)</p>
            <p className="text-xs text-gray-500 mb-3">Laissez à 0 les prestations que vous ne proposez pas.</p>
            <div className="space-y-2">
              {PRESTATIONS_GARDE.map(p => (
                <div key={p.value} className="flex items-center justify-between gap-3">
                  <span className="text-sm font-semibold text-[#1F2A2E]">{p.label}</span>
                  <div className="flex items-center gap-1">
                    <input type="number" min={0} step={1} value={tarifsBase[p.value] ?? 0}
                      onChange={e => majBase(p.value, Math.max(0, Number(e.target.value) || 0))}
                      className="w-24 border border-gray-200 rounded-xl px-2 py-2 text-sm text-center" />
                    <span className="text-xs text-gray-400">€</span>
                  </div>
                </div>
              ))}
            </div>
          </section>

          <section className="bg-white rounded-2xl border border-gray-100 p-4 shadow-sm space-y-3">
            <label className="flex items-start gap-2 text-sm text-gray-700">
              <input type="checkbox" className="mt-0.5" checked={essai}
                onChange={e => majBase('essai_actif', e.target.checked ? 1 : 0)} />
              <span><span className="font-bold text-[#1F2A2E]">Visite d&apos;essai pour les nouveaux clients</span>
                <span className="block text-xs text-gray-500">Vous rencontrez l&apos;animal avant la première garde, puis indiquez si l&apos;essai est concluant.</span>
              </span>
            </label>
            {essai && (
              <>
                <div className="grid grid-cols-2 gap-3">
                  <div>
                    <label className="text-xs font-medium text-gray-500 block mb-1">Prix de l&apos;essai (€ TTC)</label>
                    <input type="number" min={0} step={1} value={tarifsBase.essai ?? 0}
                      onChange={e => majBase('essai', Math.max(0, Number(e.target.value) || 0))} className={inputCls} />
                  </div>
                  <div>
                    <label className="text-xs font-medium text-gray-500 block mb-1">Durée (minutes)</label>
                    <input type="number" min={15} step={15} value={tarifsBase.essai_duree ?? 30}
                      onChange={e => majBase('essai_duree', Math.max(15, Number(e.target.value) || 30))} className={inputCls} />
                  </div>
                </div>
                <label className="flex items-start gap-2 text-sm text-gray-700">
                  <input type="checkbox" className="mt-0.5" checked={tarifsBase.essai_obligatoire === 1}
                    onChange={e => majBase('essai_obligatoire', e.target.checked ? 1 : 0)} />
                  <span>Essai obligatoire avant une première garde
                    <span className="block text-xs text-gray-500">Un nouveau client ne peut réserver que l&apos;essai, puis ses gardes une fois l&apos;essai concluant.</span>
                  </span>
                </label>
              </>
            )}
          </section>

          <section className="bg-white rounded-2xl border border-gray-100 p-4 shadow-sm">
            <p className="text-sm font-bold text-[#1F2A2E]">Prestations sur mesure</p>
            <p className="text-xs text-gray-500 mb-3">Ex : nuit à domicile, soins particuliers, transport…</p>
            <div className="space-y-2">
              {extra.map(e => (
                <div key={e.k} className="bg-gray-50 rounded-xl p-2.5 space-y-2">
                  <div className="flex gap-2 items-center">
                    <input value={e.label} placeholder="Intitulé"
                      onChange={ev => majExtra(l => l.map(x => x.k === e.k ? { ...x, label: ev.target.value } : x))}
                      className={inputCls} />
                    <input type="number" min={0} value={e.prix} aria-label="Prix"
                      onChange={ev => majExtra(l => l.map(x => x.k === e.k ? { ...x, prix: Math.max(0, Number(ev.target.value) || 0) } : x))}
                      className="w-24 border border-gray-200 rounded-xl px-2 py-2 text-sm text-right" />
                    <span className="text-xs text-gray-400">€</span>
                    <button onClick={() => majExtra(l => l.filter(x => x.k !== e.k))} className="text-red-400 hover:text-red-600 text-sm px-1" aria-label="Retirer">×</button>
                  </div>
                  <input value={e.description} placeholder="Précision (facultatif)"
                    onChange={ev => majExtra(l => l.map(x => x.k === e.k ? { ...x, description: ev.target.value } : x))}
                    className={inputCls} />
                </div>
              ))}
            </div>
            <button onClick={() => majExtra(l => [...l, { k: Math.max(0, ...l.map(x => x.k)) + 1, label: '', prix: 0, description: '' }])}
              className="mt-2 text-sm font-semibold" style={{ color: TEAL }}>+ Ajouter une prestation</button>
          </section>

          <div className="sticky bottom-4 flex items-center gap-3">
            <button onClick={enregistrerTarifs} disabled={saving || !modifie}
              className="flex-1 py-3 rounded-xl text-sm font-bold text-white disabled:opacity-50" style={{ backgroundColor: TEAL }}>
              {saving ? 'Enregistrement…' : modifie ? 'Enregistrer les tarifs' : 'Tarifs enregistrés'}
            </button>
          </div>
          {message && <p className={`text-sm ${message.startsWith('Erreur') ? 'text-red-600' : 'text-[#6E9E57]'}`}>{message}</p>}
        </div>
      )}

      {onglet === 'forfaits' && (
        <div className="space-y-3">
          <p className="text-sm text-gray-600">Packs de visites, de promenades ou de jours de garde, facturés à l&apos;achat puis décomptés à chaque passage. Le client les choisit à la réservation.</p>
          {forfaits.length === 0 && <p className="text-center text-gray-400 py-8">Aucun forfait pour l&apos;instant.</p>}
          {forfaits.map(f => (
            <div key={f.id} className="bg-white rounded-2xl border border-gray-100 p-4 shadow-sm">
              <div className="flex items-start justify-between gap-3">
                <button onClick={() => setForfaitEdite(f)} className="text-left">
                  <p className="text-sm font-bold text-[#1F2A2E]">{f.nom}</p>
                  <p className="text-xs text-gray-600">{f.nb_visites} {uniteForfaitGarde(f.type_prestation)} — {Number(f.prix).toFixed(0)} €</p>
                  {f.description && <p className="text-xs text-gray-400">{f.description}</p>}
                </button>
                <div className="flex gap-3 text-sm flex-shrink-0">
                  <button onClick={() => setForfaitEdite(f)} className="font-semibold" style={{ color: TEAL }}>Modifier</button>
                  <button onClick={() => supprimerForfait(f)} className="text-red-500 hover:text-red-700">Supprimer</button>
                </div>
              </div>
              <label className="flex items-center gap-2 mt-2 text-xs text-gray-600">
                <input type="checkbox" checked={f.affiche_public !== false} onChange={e => basculerPublic(f, e.target.checked)} />
                Proposer sur ma fiche et à la réservation
              </label>
            </div>
          ))}
          <button onClick={() => setForfaitEdite('nouveau')}
            className="w-full py-3 rounded-xl text-sm font-bold border-2 border-dashed" style={{ color: TEAL, borderColor: '#B7CFD4' }}>
            + Ajouter un forfait
          </button>
        </div>
      )}

      {onglet === 'clients' && (
        clients.length === 0 ? (
          <p className="text-center text-gray-400 py-16">Tarifs par client : disponible dès votre premier rendez-vous confirmé.</p>
        ) : (
          <div className="space-y-3">
            <p className="text-sm text-gray-600">Un prix particulier pour un client remplace le tarif standard pour lui seul.</p>
            {clients.map(c => {
              const nbOverrides = Object.keys(overridesByProfile[c.client_profile_id] ?? {}).length;
              return (
                <button key={c.client_profile_id} onClick={() => setEditing(c)}
                  className="w-full text-left rounded-2xl border border-gray-100 bg-white p-4 shadow-sm hover:shadow-md transition-shadow flex items-center justify-between">
                  <div>
                    <p className="font-bold text-sm text-[#1F2A2E]">{c.client_nom}</p>
                    <p className={`text-xs ${nbOverrides > 0 ? 'text-[#6E9E57]' : 'text-gray-400'}`}>
                      {nbOverrides > 0 ? `${nbOverrides} tarif${nbOverrides > 1 ? 's' : ''} personnalisé${nbOverrides > 1 ? 's' : ''}` : 'Tarifs standard'}
                    </p>
                  </div>
                  <span className="text-gray-300">›</span>
                </button>
              );
            })}
          </div>
        )
      )}

      {forfaitEdite && (
        <ForfaitModal
          forfait={forfaitEdite === 'nouveau' ? null : forfaitEdite}
          uid={user?.uid ?? ''}
          profileId={activeProfileId}
          onClose={() => setForfaitEdite(null)}
          onSaved={() => { setForfaitEdite(null); load(); }}
        />
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

function ForfaitModal({ forfait, uid, profileId, onClose, onSaved }: {
  forfait: Forfait | null; uid: string; profileId: string; onClose: () => void; onSaved: () => void;
}) {
  const [type, setType] = useState(forfait?.type_prestation ?? 'visite');
  const [nom, setNom] = useState(forfait?.nom ?? '');
  const [nb, setNb] = useState(String(forfait?.nb_visites ?? 5));
  const [prix, setPrix] = useState(forfait ? String(Number(forfait.prix)) : '');
  const [description, setDescription] = useState(forfait?.description ?? '');
  const [publicOk, setPublicOk] = useState(forfait?.affiche_public !== false);
  const [saving, setSaving] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);
  const unite = uniteForfaitGarde(type);

  async function save() {
    if (!nom.trim()) return;
    setSaving(true);
    const ligne = {
      nom: nom.trim(), nb_visites: parseInt(nb, 10) || 1, prix: parseFloat(prix.replace(',', '.')) || 0,
      description: description.trim() || null, type_prestation: type,
    };
    const ecrire = (l: Record<string, unknown>) => forfait
      ? supabase.from('forfaits_garde').update(l).eq('id', forfait.id)
      : supabase.from('forfaits_garde').insert({ ...l, pro_uid: uid, pro_profile_id: profileId || null });
    let { error } = await ecrire({ ...ligne, affiche_public: publicOk });
    // migration_garde_tarifs_visibles.sql pas encore passée.
    if (error) ({ error } = await ecrire(ligne));
    setSaving(false);
    if (error) { setErreur(error.message); return; }
    onSaved();
  }

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-sm p-6 font-galey" onClick={e => e.stopPropagation()}>
        <h3 className="font-bold text-base mb-4 text-[#1E2025]">{forfait ? 'Modifier le forfait' : 'Nouveau forfait'}</h3>
        <div className="space-y-3">
          <div className="flex gap-2">
            {([['visite', 'Visites'], ['promenade', 'Promenades'], ['garde_journee', 'Jours de garde']] as const).map(([k, l]) => (
              <button key={k} type="button" onClick={() => setType(k)}
                className="px-3 py-1.5 rounded-full text-sm font-semibold"
                style={type === k ? { background: TEAL, color: 'white' } : { background: '#F1F4F3', color: '#1F2A2E' }}>{l}</button>
            ))}
          </div>
          <input value={nom} onChange={e => setNom(e.target.value)} placeholder={`Nom du forfait (ex : Pack 5 ${unite})`} className={inputCls} />
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="text-xs font-medium text-gray-500 block mb-1">Nombre de {unite}</label>
              <input type="number" min={1} value={nb} onChange={e => setNb(e.target.value)} className={inputCls} />
            </div>
            <div>
              <label className="text-xs font-medium text-gray-500 block mb-1">Prix (€ TTC)</label>
              <input type="number" min={0} value={prix} onChange={e => setPrix(e.target.value)} className={inputCls} />
            </div>
          </div>
          <textarea value={description} onChange={e => setDescription(e.target.value)} placeholder="Description (facultatif)" rows={2}
            className={`${inputCls} resize-none`} />
          <label className="flex items-start gap-2 text-sm text-gray-700">
            <input type="checkbox" className="mt-0.5" checked={publicOk} onChange={e => setPublicOk(e.target.checked)} />
            <span>Proposer sur ma fiche et à la réservation
              <span className="block text-xs text-gray-500">Décoché, le forfait reste disponible dans vos devis.</span>
            </span>
          </label>
          {erreur && <p className="text-xs text-red-600">{erreur}</p>}
        </div>
        <div className="flex gap-3 mt-4">
          <button onClick={onClose} className="flex-1 border border-gray-200 rounded-xl py-2.5 text-sm font-semibold">Annuler</button>
          <button onClick={save} disabled={saving || !nom.trim()}
            className="flex-1 text-white rounded-xl py-2.5 text-sm font-semibold disabled:opacity-50" style={{ backgroundColor: TEAL }}>
            {saving ? '…' : forfait ? 'Enregistrer' : 'Créer'}
          </button>
        </div>
      </div>
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
      <div className="bg-white rounded-2xl w-full max-w-md p-6 max-h-[90vh] overflow-y-auto">
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
