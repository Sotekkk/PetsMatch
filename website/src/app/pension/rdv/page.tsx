'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';

// ── Types ─────────────────────────────────────────────────────────────────────

interface Rdv {
  id: string;
  pro_uid: string;
  client_uid: string;
  pro_profile_id?: string | null;
  client_profile_id?: string | null;
  animal_id?: string | null;
  date_heure: string;
  motif?: string | null;
  statut: string;
  notes_annulation?: string | null;
  duree_minutes?: number | null;
  clientName?: string;
  animalNom?: string;
  visitCount?: number;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const TEAL = '#0C5C6C';

function fmtDate(iso: string) {
  return new Date(iso).toLocaleDateString('fr-FR', { weekday: 'long', day: '2-digit', month: 'long', year: 'numeric' });
}
function fmtHeure(iso: string) {
  return new Date(iso).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
}

const STATUT_STYLE: Record<string, { bg: string; color: string; label: string }> = {
  demande:            { bg: '#FFF3E0', color: '#e08000', label: 'Demande' },
  confirme:           { bg: '#E8F5E9', color: '#388E3C', label: 'Confirmé' },
  annule:             { bg: '#FFEBEE', color: '#d32f2f', label: 'Annulé' },
  refuse:             { bg: '#FFEBEE', color: '#d32f2f', label: 'Refusé' },
  termine:            { bg: '#F5F5F5', color: '#757575', label: 'Terminé' },
  contre_proposition: { bg: '#E3F2FD', color: '#1565C0', label: 'Contre-prop.' },
};

// ── Modal accepter ────────────────────────────────────────────────────────────

function AccepterModal({ rdv, proName, onClose, onDone }: {
  rdv: Rdv; proName: string; onClose: () => void; onDone: () => void;
}) {
  const [mode, setMode] = useState<'confirme' | 'contre_proposition'>('confirme');
  const [hour, setHour] = useState(new Date(rdv.date_heure).getHours());
  const [minute, setMinute] = useState(0);
  const [date, setDate] = useState(rdv.date_heure.slice(0, 10));
  const [duree, setDuree] = useState(rdv.duree_minutes ?? 60);
  const [saving, setSaving] = useState(false);

  async function handleSubmit() {
    setSaving(true);
    try {
      const newDt = new Date(`${date}T${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}:00`);
      const newStatut = mode === 'confirme' ? 'confirme' : 'contre_proposition';

      await supabase.from('rdv').update({
        statut: newStatut,
        date_heure: newDt.toISOString(),
        duree_minutes: duree,
      }).eq('id', rdv.id);

      if (mode === 'confirme') {
        // Agenda client
        await supabase.from('agenda_events').upsert({
          uid: rdv.client_uid,
          titre: `RDV pension${rdv.animalNom ? ` — ${rdv.animalNom}` : ''}`,
          type: 'rdv',
          date_debut: newDt.toISOString(),
          duree_minutes: duree,
          rdv_id: rdv.id,
          pro_profile_id: rdv.client_profile_id ?? null,
        }, { onConflict: 'rdv_id' });

        // Agenda pension — couleur trick
        await supabase.from('agenda_events').delete()
          .eq('uid', rdv.pro_uid).eq('couleur', `rdv:${rdv.id}`);
        await supabase.from('agenda_events').insert({
          uid: rdv.pro_uid,
          titre: `RDV avec ${rdv.clientName ?? 'Client'}`,
          type: 'rdv',
          date_debut: newDt.toISOString(),
          duree_minutes: duree,
          couleur: `rdv:${rdv.id}`,
          pro_profile_id: rdv.pro_profile_id ?? null,
        });

        // Notification client
        await supabase.from('notifications').insert({
          uid: rdv.client_uid,
          type: 'rdv_confirme',
          title: `RDV confirmé par ${proName}`,
          body: `Votre rendez-vous est confirmé pour le ${fmtDate(newDt.toISOString())} à ${fmtHeure(newDt.toISOString())}`,
          data: { rdv_id: rdv.id },
          read: false,
        });
      } else {
        await supabase.from('notifications').insert({
          uid: rdv.client_uid,
          type: 'rdv_contre_proposition',
          title: 'Contre-proposition de créneau',
          body: `${proName} propose un autre créneau : ${fmtDate(newDt.toISOString())} à ${fmtHeure(newDt.toISOString())}`,
          data: { rdv_id: rdv.id },
          read: false,
        });
      }
      onDone();
    } catch { /* ignore */ } finally { setSaving(false); }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-md p-6 space-y-5" onClick={e => e.stopPropagation()}>
        <h2 className="font-bold text-lg text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>Accepter le RDV</h2>

        <div className="flex gap-2 bg-gray-100 rounded-xl p-1">
          {(['confirme', 'contre_proposition'] as const).map(m => (
            <button key={m} onClick={() => setMode(m)}
              className="flex-1 py-2 text-sm font-semibold rounded-lg transition-all"
              style={{
                background: mode === m ? 'white' : 'transparent',
                color: mode === m ? TEAL : '#6b7280',
                fontFamily: 'Galey, sans-serif',
              }}>
              {m === 'confirme' ? 'Confirmer' : 'Autre créneau'}
            </button>
          ))}
        </div>

        {mode === 'contre_proposition' && (
          <div>
            <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Date</label>
            <input type="date" value={date} onChange={e => setDate(e.target.value)}
              className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none"
              style={{ borderColor: '#e5e7eb' }} />
          </div>
        )}

        <div>
          <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Heure</label>
          <div className="flex gap-2 mt-2">
            <select value={hour} onChange={e => setHour(Number(e.target.value))}
              className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none">
              {Array.from({ length: 14 }, (_, i) => i + 7).map(h => (
                <option key={h} value={h}>{String(h).padStart(2, '0')}h</option>
              ))}
            </select>
            <select value={minute} onChange={e => setMinute(Number(e.target.value))}
              className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none">
              {[0, 15, 30, 45].map(m => (
                <option key={m} value={m}>{String(m).padStart(2, '0')}</option>
              ))}
            </select>
          </div>
        </div>

        <div>
          <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Durée</label>
          <div className="flex flex-wrap gap-2 mt-2">
            {[15, 30, 45, 60, 90, 120].map(d => (
              <button key={d} onClick={() => setDuree(d)}
                className="px-3 py-1.5 rounded-lg text-xs font-semibold border transition-colors"
                style={{
                  background: duree === d ? TEAL : 'white',
                  color: duree === d ? 'white' : '#1E2025',
                  borderColor: duree === d ? TEAL : '#e5e7eb',
                  fontFamily: 'Galey, sans-serif',
                }}>
                {d < 60 ? `${d} min` : `${d / 60} h`}
              </button>
            ))}
          </div>
        </div>

        <div className="flex gap-3 justify-end pt-1">
          <button onClick={onClose} className="px-4 py-2 rounded-xl text-sm text-gray-600 border border-gray-200 hover:bg-gray-50">
            Annuler
          </button>
          <button onClick={handleSubmit} disabled={saving}
            className="px-5 py-2 rounded-xl text-sm text-white font-semibold disabled:opacity-50 transition-colors"
            style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
            {saving ? '…' : mode === 'confirme' ? 'Confirmer' : 'Proposer'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Modal refuser / annuler ────────────────────────────────────────────────────

function RefuserModal({ rdv, label, type, onClose, onDone }: {
  rdv: Rdv; label: string; type: 'refuse' | 'annule'; onClose: () => void; onDone: () => void;
}) {
  const [motif, setMotif] = useState('');
  const [saving, setSaving] = useState(false);

  async function handleSubmit() {
    setSaving(true);
    try {
      await supabase.from('rdv').update({ statut: type === 'refuse' ? 'annule' : 'annule', notes_annulation: motif || null }).eq('id', rdv.id);
      await supabase.from('agenda_events').delete().eq('rdv_id', rdv.id);
      await supabase.from('agenda_events').delete()
        .eq('uid', rdv.pro_uid).eq('couleur', `rdv:${rdv.id}`);
      await supabase.from('notifications').insert({
        uid: rdv.client_uid,
        type: type === 'refuse' ? 'rdv_refuse' : 'rdv_annule',
        title: type === 'refuse' ? 'Demande de RDV refusée' : 'RDV annulé',
        body: `${type === 'refuse' ? 'Votre demande de RDV a été refusée' : 'Votre RDV a été annulé'}${motif ? ` — Motif : ${motif}` : ''}`,
        data: { rdv_id: rdv.id },
        read: false,
      });
      onDone();
    } catch { /* ignore */ } finally { setSaving(false); }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-2xl shadow-2xl w-full max-w-sm p-6 space-y-4" onClick={e => e.stopPropagation()}>
        <h2 className="font-bold text-lg text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>{label} ce RDV</h2>
        <p className="text-sm text-gray-500">
          Client : <strong>{rdv.clientName ?? '—'}</strong><br />
          {fmtDate(rdv.date_heure)} à {fmtHeure(rdv.date_heure)}
        </p>
        <textarea value={motif} onChange={e => setMotif(e.target.value)} rows={3}
          placeholder="Motif (optionnel)…"
          className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none focus:outline-none"
          style={{ fontFamily: 'Galey, sans-serif' }} />
        <div className="flex gap-3 justify-end">
          <button onClick={onClose} className="px-4 py-2 rounded-xl text-sm text-gray-600 border border-gray-200 hover:bg-gray-50">Retour</button>
          <button onClick={handleSubmit} disabled={saving}
            className="px-5 py-2 rounded-xl text-sm text-white bg-red-500 hover:bg-red-600 font-semibold disabled:opacity-50 transition-colors">
            {saving ? '…' : label}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Carte RDV ─────────────────────────────────────────────────────────────────

function RdvCard({ rdv, tab, onAccepter, onRefuser, onAnnuler, onTerminer, onDelete }: {
  rdv: Rdv;
  tab: 'demandes' | 'a_venir' | 'historique';
  onAccepter?: () => void;
  onRefuser?: () => void;
  onAnnuler?: () => void;
  onTerminer?: () => void;
  onDelete?: () => void;
}) {
  const [confirmDel, setConfirmDel] = useState(false);
  const st = STATUT_STYLE[rdv.statut] ?? { bg: '#F5F5F5', color: '#757575', label: rdv.statut };
  const isFirst = rdv.visitCount === 0;

  return (
    <div className="bg-white rounded-2xl px-4 py-4 shadow-sm border border-gray-100 space-y-3">
      <div className="flex items-start justify-between gap-2">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <p className="font-bold text-[#1E2025] text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
              {rdv.clientName ?? '—'}
            </p>
            <span className="text-xs px-2 py-0.5 rounded-full font-semibold"
              style={{ background: isFirst ? '#FFF8E1' : '#E3F2FD', color: isFirst ? '#F57F17' : '#1565C0', fontFamily: 'Galey, sans-serif' }}>
              {isFirst ? '⭐ Première visite' : `🔄 ${rdv.visitCount} visite${(rdv.visitCount ?? 0) > 1 ? 's' : ''}`}
            </span>
          </div>
          {rdv.animalNom && (
            <p className="text-xs text-gray-500 mt-0.5">Animal : {rdv.animalNom}</p>
          )}
          <p className="text-xs text-[#0C5C6C] mt-1 font-medium">
            {fmtDate(rdv.date_heure)} à {fmtHeure(rdv.date_heure)}
          </p>
          {rdv.motif && <p className="text-xs text-gray-400 mt-0.5 truncate">Motif : {rdv.motif}</p>}
          {rdv.notes_annulation && <p className="text-xs text-red-400 mt-0.5">Note : {rdv.notes_annulation}</p>}
        </div>
        <span className="text-xs px-2 py-0.5 rounded-full font-semibold flex-shrink-0"
          style={{ background: st.bg, color: st.color, fontFamily: 'Galey, sans-serif' }}>
          {st.label}
        </span>
      </div>

      <div className="flex gap-2 flex-wrap">
        {tab === 'demandes' && (
          <>
            <button onClick={onAccepter}
              className="flex-1 min-w-[80px] text-xs font-semibold px-3 py-2 rounded-xl text-white transition-colors"
              style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
              Accepter
            </button>
            <button onClick={onRefuser}
              className="flex-1 min-w-[80px] text-xs font-semibold px-3 py-2 rounded-xl text-red-600 border border-red-200 hover:bg-red-50 transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              Refuser
            </button>
          </>
        )}
        {tab === 'a_venir' && (
          <>
            <button onClick={onTerminer}
              className="flex-1 min-w-[80px] text-xs font-semibold px-3 py-2 rounded-xl text-white transition-colors"
              style={{ background: '#6E9E57', fontFamily: 'Galey, sans-serif' }}>
              Terminé
            </button>
            <button onClick={onAnnuler}
              className="flex-1 min-w-[80px] text-xs font-semibold px-3 py-2 rounded-xl text-red-600 border border-red-200 hover:bg-red-50 transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              Annuler
            </button>
          </>
        )}
        {tab === 'historique' && (
          confirmDel ? (
            <div className="flex gap-2 items-center w-full">
              <span className="text-xs text-gray-500 flex-1">Supprimer définitivement ?</span>
              <button onClick={() => setConfirmDel(false)}
                className="px-3 py-1.5 rounded-xl text-xs border border-gray-200 hover:bg-gray-50">Non</button>
              <button onClick={onDelete}
                className="px-3 py-1.5 rounded-xl text-xs text-white bg-red-500 hover:bg-red-600 font-semibold">Supprimer</button>
            </div>
          ) : (
            <button onClick={() => setConfirmDel(true)}
              className="text-xs text-red-400 hover:text-red-600 px-3 py-1.5 rounded-xl border border-red-100 hover:border-red-200 transition-colors"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              Supprimer
            </button>
          )
        )}
      </div>
    </div>
  );
}

// ── Page principale ───────────────────────────────────────────────────────────

export default function PensionRdvPage() {
  const { user, userData, loading, availableProfiles } = useAuth();
  const router = useRouter();
  const [activeTab, setActiveTab] = useState<'demandes' | 'a_venir' | 'historique'>('demandes');
  const [rdvs, setRdvs] = useState<Rdv[]>([]);
  const [fetching, setFetching] = useState(true);

  const [modalAccepter, setModalAccepter] = useState<Rdv | null>(null);
  const [modalRefuser, setModalRefuser]   = useState<Rdv | null>(null);
  const [modalAnnuler, setModalAnnuler]   = useState<Rdv | null>(null);

  // Vérifie si l'utilisateur a AU MOINS un profil pension (peu importe le profil actif)
  const pensionProfile = availableProfiles.find(p => p.profile_type === 'pension');
  const isPension = !!(pensionProfile ?? (userData?.isPro && userData?.catPro === 'pension'));
  const proName   = (pensionProfile?.nom as string | null) ?? userData?.nameElevage ?? userData?.firstname ?? 'La pension';

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  const fetchRdvs = useCallback(async () => {
    if (!user) return;
    setFetching(true);
    try {
      // Filtre uniquement par pro_uid — la page est déjà réservée aux pensions (isPension)
      const { data } = await supabase.from('rdv').select('*')
        .eq('pro_uid', user.uid)
        .order('date_heure', { ascending: true });

      const list = (data ?? []) as Rdv[];
      const clientUids = [...new Set(list.map(r => r.client_uid).filter(Boolean))];
      const animalIds  = [...new Set(list.map(r => r.animal_id).filter(Boolean) as string[])];

      const [usersRes, animauxRes] = await Promise.all([
        clientUids.length ? supabase.from('users').select('uid, firstname, lastname').in('uid', clientUids) : Promise.resolve({ data: [] }),
        animalIds.length  ? supabase.from('animaux').select('id, nom').in('id', animalIds) : Promise.resolve({ data: [] }),
      ]);

      const usersMap: Record<string, string> = {};
      for (const u of (usersRes.data ?? [])) {
        const rec = u as { uid: string; firstname?: string; lastname?: string };
        usersMap[rec.uid] = [rec.firstname, rec.lastname].filter(Boolean).join(' ') || rec.uid;
      }
      const animauxMap: Record<string, string> = {};
      for (const a of (animauxRes.data ?? [])) {
        const rec = a as { id: string; nom?: string };
        if (rec.nom) animauxMap[rec.id] = rec.nom;
      }

      // Compter les visites par client
      const visitCounts: Record<string, number> = {};
      if (clientUids.length) {
        const { data: hist } = await supabase.from('rdv')
          .select('client_uid').eq('pro_uid', user.uid)
          .in('client_uid', clientUids).in('statut', ['confirme', 'termine']);
        for (const h of (hist ?? [])) {
          const cUid = (h as { client_uid: string }).client_uid;
          visitCounts[cUid] = (visitCounts[cUid] ?? 0) + 1;
        }
      }

      setRdvs(list.map(r => ({
        ...r,
        clientName: usersMap[r.client_uid] ?? undefined,
        animalNom:  r.animal_id ? animauxMap[r.animal_id] ?? undefined : undefined,
        visitCount: visitCounts[r.client_uid] ?? 0,
      })));
    } catch { /* ignore */ } finally { setFetching(false); }
  }, [user]);

  useEffect(() => { fetchRdvs(); }, [fetchRdvs]);

  async function marquerTermine(rdv: Rdv) {
    await supabase.from('rdv').update({ statut: 'termine' }).eq('id', rdv.id);
    fetchRdvs();
  }

  async function deleteRdv(rdvId: string) {
    await supabase.from('agenda_events').delete().eq('rdv_id', rdvId);
    if (user) {
      await supabase.from('agenda_events').delete()
        .eq('uid', user.uid).eq('couleur', `rdv:${rdvId}`);
    }
    await supabase.from('rdv').delete().eq('id', rdvId);
    setRdvs(prev => prev.filter(r => r.id !== rdvId));
  }

  if (loading) return (
    <div className="flex justify-center py-32">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  if (!user || !isPension) return (
    <div className="max-w-lg mx-auto px-4 py-16 text-center">
      <p className="text-gray-500" style={{ fontFamily: 'Galey, sans-serif' }}>
        Cette page est réservée aux professionnels pension.
      </p>
    </div>
  );

  const now = new Date();
  const demandes   = rdvs.filter(r => r.statut === 'demande');
  const aVenir     = rdvs.filter(r => r.statut === 'confirme' && new Date(r.date_heure) > now);
  const historique = rdvs.filter(r => !['demande'].includes(r.statut) && !(r.statut === 'confirme' && new Date(r.date_heure) > now));

  const TABS = [
    { key: 'demandes'   as const, label: 'Demandes',  badge: demandes.length },
    { key: 'a_venir'    as const, label: 'À venir',   badge: aVenir.length },
    { key: 'historique' as const, label: 'Historique', badge: 0 },
  ];

  const currentList = activeTab === 'demandes' ? demandes : activeTab === 'a_venir' ? aVenir : historique;

  return (
    <div className="bg-[#F8F8F6] min-h-screen">
      <div style={{ background: TEAL }} className="text-white px-4 py-6">
        <div className="max-w-3xl mx-auto">
          <h1 className="text-xl font-bold mb-4" style={{ fontFamily: 'Galey, sans-serif' }}>Gestion des RDV</h1>
          <div className="flex gap-1 bg-white/10 rounded-xl p-1">
            {TABS.map(t => (
              <button key={t.key} onClick={() => setActiveTab(t.key)}
                className="flex-1 py-2 px-3 text-sm font-semibold rounded-lg transition-all flex items-center justify-center gap-1.5"
                style={{
                  background: activeTab === t.key ? 'white' : 'transparent',
                  color: activeTab === t.key ? TEAL : 'rgba(255,255,255,0.75)',
                  fontFamily: 'Galey, sans-serif',
                }}>
                {t.label}
                {t.badge > 0 && (
                  <span className="text-[10px] font-bold px-1.5 py-0.5 rounded-full"
                    style={{
                      background: activeTab === t.key ? TEAL : 'rgba(255,255,255,0.2)',
                      color: 'white',
                    }}>
                    {t.badge}
                  </span>
                )}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="max-w-3xl mx-auto px-4 py-6">
        {fetching ? (
          <div className="flex justify-center py-16">
            <div className="w-7 h-7 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : currentList.length === 0 ? (
          <div className="text-center py-20 text-gray-400">
            <div className="text-5xl mb-4">📅</div>
            <p className="font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
              {activeTab === 'demandes' ? 'Aucune demande en attente' : activeTab === 'a_venir' ? 'Aucun RDV à venir' : 'Aucun historique'}
            </p>
          </div>
        ) : (
          <div className="space-y-3">
            {currentList.map(rdv => (
              <RdvCard key={rdv.id} rdv={rdv} tab={activeTab}
                onAccepter={() => setModalAccepter(rdv)}
                onRefuser={() => setModalRefuser(rdv)}
                onAnnuler={() => setModalAnnuler(rdv)}
                onTerminer={() => marquerTermine(rdv)}
                onDelete={() => deleteRdv(rdv.id)}
              />
            ))}
          </div>
        )}
      </div>

      {modalAccepter && (
        <AccepterModal rdv={modalAccepter} proName={proName}
          onClose={() => setModalAccepter(null)}
          onDone={() => { setModalAccepter(null); fetchRdvs(); }} />
      )}
      {modalRefuser && (
        <RefuserModal rdv={modalRefuser} label="Refuser" type="refuse"
          onClose={() => setModalRefuser(null)}
          onDone={() => { setModalRefuser(null); fetchRdvs(); }} />
      )}
      {modalAnnuler && (
        <RefuserModal rdv={modalAnnuler} label="Annuler" type="annule"
          onClose={() => setModalAnnuler(null)}
          onDone={() => { setModalAnnuler(null); fetchRdvs(); }} />
      )}
    </div>
  );
}
