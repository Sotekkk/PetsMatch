'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

// ── Types ──────────────────────────────────────────────────────────────────────

interface ProProfile {
  id: string;
  profile_type: string;
  name_elevage: string;
  avatar_url: string | null;
  cat_pro: string;
}

interface PendingRdv {
  id: string;
  date_heure: string;
  motif: string | null;
  client_uid: string;
  animal_id: number | null;
}

interface UpcomingRdv {
  id: string;
  date_heure: string;
  motif: string | null;
  client_uid: string;
  animal_id: number | null;
  statut: string;
}

interface Patient {
  animal_id: number;
  id: string;
  status: string;
  animal: {
    id: number;
    nom: string;
    espece: string;
    race: string;
    photo_url: string | null;
  } | null;
}

interface LostAnimal {
  id: string;
  nom: string;
  espece: string;
  statut: string;
  photo_url: string | null;
  created_at: string;
}

function fmtDate(iso: string) {
  const d = new Date(iso);
  const today = new Date();
  const tomorrow = new Date(today); tomorrow.setDate(today.getDate() + 1);
  if (d.toDateString() === today.toDateString()) return "Aujourd'hui " + d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
  if (d.toDateString() === tomorrow.toDateString()) return 'Demain ' + d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
  return d.toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' }) + ' ' + d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
}

const ESPECE_EMOJI: Record<string, string> = { chien: '🐕', chat: '🐈', cheval: '🐴', lapin: '🐰', oiseau: '🦜', autre: '🐾' };

const TYPE_LABEL: Record<string, string> = {
  veterinaire: 'Vétérinaire', sante: 'Santé animale', education: 'Éducateur',
  garde: 'Pet Sitter', pension: 'Pension', toilettage: 'Toilettage',
  photographe: 'Photographe', marechal_ferrant: 'Maréchal-ferrant',
};

// ── Main component ─────────────────────────────────────────────────────────────

export default function ProDashboard({ profile, profileId }: { profile: ProProfile; profileId: string }) {
  const { user, userData } = useAuth();
  const uid = user?.uid ?? '';

  const [pendingRdvs, setPendingRdvs] = useState<PendingRdv[]>([]);
  const [upcomingRdvs, setUpcomingRdvs] = useState<UpcomingRdv[]>([]);
  const [patients, setPatients] = useState<Patient[]>([]);
  const [lostAnimals, setLostAnimals] = useState<LostAnimal[]>([]);
  const [clientNames, setClientNames] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [savingRdv, setSavingRdv] = useState<string | null>(null);

  const catPro = profile.profile_type ?? profile.cat_pro ?? '';
  const isVet  = catPro === 'veterinaire' || catPro === 'sante';
  const name   = profile.name_elevage || userData?.firstname || 'Mon cabinet';
  const avatar = profile.avatar_url ?? userData?.profilePictureUrlElevage ?? userData?.profilePictureUrl ?? null;

  // Libellé "clients" selon la profession
  const clientsLabel = isVet ? 'Mes patients'
    : catPro === 'marechal_ferrant' ? 'Mes équidés suivis'
    : catPro === 'education' ? 'Mes élèves'
    : 'Animaux suivis';

  useEffect(() => {
    if (!uid) return;
    async function load() {
      const now = new Date().toISOString();
      const future = new Date(Date.now() + 90 * 86400000).toISOString();

      const profileFilter = profileId
        ? `pro_profile_id.eq.${profileId}`
        : 'pro_profile_id.is.null,pro_profile_id.eq.';

      const [lostRes, pendRes, upRes] = await Promise.all([
        supabase.from('animaux_perdus').select('id, nom, espece, statut, photo_url, created_at')
          .order('created_at', { ascending: false }).limit(4),
        supabase.from('rdv').select('id, date_heure, motif, client_uid, animal_id')
          .eq('pro_uid', uid).in('statut', ['demande', 'contre_proposition'])
          .or(profileFilter).order('date_heure').limit(5),
        supabase.from('rdv').select('id, date_heure, motif, client_uid, animal_id, statut')
          .eq('pro_uid', uid).eq('statut', 'confirme')
          .or(profileFilter)
          .gte('date_heure', now).lte('date_heure', future).order('date_heure').limit(5),
      ]);

      setPendingRdvs((pendRes.data ?? []) as PendingRdv[]);
      setUpcomingRdvs((upRes.data ?? []) as UpcomingRdv[]);
      setLostAnimals((lostRes.data ?? []) as LostAnimal[]);

      // Accès animaux clients — table animal_access unifiée
      if (profileId) {
        const { data: grantRows } = await supabase
          .from('animal_access')
          .select('id, animal_id, statut')
          .eq('pro_profile_id', profileId)
          .eq('statut', 'active')
          .limit(6);
        if (grantRows && grantRows.length > 0) {
          const ids = grantRows.map((g: { animal_id: string }) => g.animal_id).filter(Boolean);
          const { data: animalRows } = await supabase
            .from('animaux')
            .select('id, nom, espece, race, photo_url')
            .in('id', ids);
          const animalMap = new Map((animalRows ?? []).map((a: { id: string }) => [a.id, a]));
          setPatients(grantRows.map((g: { id: string; animal_id: string; statut: string }) => ({ ...g, animal: animalMap.get(g.animal_id) ?? null })) as unknown as Patient[]);
        }
      }

      // Load client names
      const allUids = [...new Set([
        ...(pendRes.data ?? []).map((r: { client_uid: string }) => r.client_uid),
        ...(upRes.data ?? []).map((r: { client_uid: string }) => r.client_uid),
      ])];
      if (allUids.length > 0) {
        const { data: usersData } = await supabase
          .from('users').select('uid, prenom, nom, firstname, lastname')
          .in('uid', allUids);
        const names: Record<string, string> = {};
        for (const u of (usersData ?? [])) {
          const rec = u as { uid: string; prenom?: string; nom?: string; firstname?: string; lastname?: string };
          names[rec.uid] = [rec.prenom ?? rec.firstname, rec.nom ?? rec.lastname].filter(Boolean).join(' ') || 'Client';
        }
        setClientNames(names);
      }

      setLoading(false);
    }
    load();
  }, [uid, profileId, isVet]);

  async function confirmRdv(rdv: PendingRdv) {
    setSavingRdv(rdv.id);
    await supabase.from('rdv').update({ statut: 'confirme' }).eq('id', rdv.id);
    await supabase.from('agenda_events').insert({
      uid,
      titre: `RDV ${clientNames[rdv.client_uid] || 'Client'}${rdv.motif ? ` — ${rdv.motif}` : ''}`,
      type: 'rdv',
      date_debut: rdv.date_heure,
      rdv_id: rdv.id,
      pro_profile_id: profileId,
    });
    await supabase.from('notifications').insert({
      uid: rdv.client_uid,
      type: 'rdv_confirme',
      title: 'RDV confirmé',
      body: `Votre rendez-vous du ${fmtDate(rdv.date_heure)} a été confirmé.`,
      data: { rdv_id: rdv.id },
      read: false,
    });
    setPendingRdvs(p => p.filter(r => r.id !== rdv.id));
    setUpcomingRdvs(p => [...p, { ...rdv, statut: 'confirme' }].sort((a, b) => a.date_heure.localeCompare(b.date_heure)));
    setSavingRdv(null);
  }

  async function rejectRdv(rdv: PendingRdv) {
    setSavingRdv(rdv.id);
    await supabase.from('rdv').update({ statut: 'refuse' }).eq('id', rdv.id);
    await supabase.from('notifications').insert({
      uid: rdv.client_uid,
      type: 'rdv_refuse',
      title: 'RDV refusé',
      body: `Votre demande de rendez-vous du ${fmtDate(rdv.date_heure)} a été refusée.`,
      data: { rdv_id: rdv.id },
      read: false,
    });
    setPendingRdvs(p => p.filter(r => r.id !== rdv.id));
    setSavingRdv(null);
  }

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Header */}
      <div className="bg-[#0C5C6C] text-white">
        <div className="max-w-4xl mx-auto px-4 py-6">
          <div className="flex items-center gap-4">
            <div className="w-14 h-14 rounded-full overflow-hidden bg-white/20 flex-shrink-0 border-2 border-white/30">
              {avatar
                ? <Image src={avatar} alt="" width={56} height={56} className="object-cover w-full h-full" />
                : <div className="w-full h-full flex items-center justify-center text-xl font-bold">{name[0]?.toUpperCase() ?? '?'}</div>
              }
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm text-white/70">Bonjour,</p>
              <h1 className="text-xl font-bold truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{name}</h1>
              <span className="text-xs text-white/60 bg-white/10 px-2 py-0.5 rounded-full">
                {TYPE_LABEL[catPro] ?? catPro}
              </span>
            </div>
          </div>

          {/* Stats rapides */}
          <div className="grid grid-cols-3 gap-3 mt-4">
            <div className="bg-white/10 rounded-xl p-3 text-center">
              <p className="text-2xl font-bold">{pendingRdvs.length}</p>
              <p className="text-xs text-white/70 mt-0.5">En attente</p>
            </div>
            <div className="bg-white/10 rounded-xl p-3 text-center">
              <p className="text-2xl font-bold">{upcomingRdvs.length}</p>
              <p className="text-xs text-white/70 mt-0.5">RDV à venir</p>
            </div>
            <div className="bg-white/10 rounded-xl p-3 text-center">
              <p className="text-2xl font-bold">{patients.length}</p>
              <p className="text-xs text-white/70 mt-0.5">
                {isVet ? 'Patients' : 'Animaux suivis'}
              </p>
            </div>
          </div>
        </div>
      </div>

      <div className="max-w-4xl mx-auto px-4 py-6 space-y-6">

        {/* Accès rapides */}
        <div>
          <p className="text-xs font-bold text-gray-500 uppercase tracking-wide mb-3">Accès rapide</p>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <Link href="/agenda" className="bg-white rounded-2xl p-4 border border-gray-100 shadow-sm hover:shadow-md transition-shadow text-center">
              <div className="text-2xl mb-1">📅</div>
              <p className="text-xs font-semibold text-[#1F2A2E]">Mon agenda</p>
            </Link>
            <Link href="/mes-rdv" className="bg-white rounded-2xl p-4 border border-gray-100 shadow-sm hover:shadow-md transition-shadow text-center">
              <div className="text-2xl mb-1">🗓️</div>
              <p className="text-xs font-semibold text-[#1F2A2E]">Gérer les RDV</p>
            </Link>
            <Link href="/pro/creneaux" className="bg-white rounded-2xl p-4 border border-gray-100 shadow-sm hover:shadow-md transition-shadow text-center">
              <div className="text-2xl mb-1">⏰</div>
              <p className="text-xs font-semibold text-[#1F2A2E]">Mes créneaux</p>
            </Link>
            <Link href="/messages" className="bg-white rounded-2xl p-4 border border-gray-100 shadow-sm hover:shadow-md transition-shadow text-center">
              <div className="text-2xl mb-1">💬</div>
              <p className="text-xs font-semibold text-[#1F2A2E]">Messages</p>
            </Link>
          </div>
        </div>

        {/* RDV en attente */}
        {(loading || pendingRdvs.length > 0) && (
          <div>
            <div className="flex items-center justify-between mb-3">
              <p className="text-xs font-bold text-gray-500 uppercase tracking-wide">
                RDV en attente {!loading && `(${pendingRdvs.length})`}
              </p>
              <Link href="/mes-rdv" className="text-xs text-[#0C5C6C] font-medium hover:underline">Voir tout →</Link>
            </div>
            {loading ? (
              <div className="bg-white rounded-2xl border border-gray-100 p-6 flex justify-center">
                <div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
              </div>
            ) : pendingRdvs.length === 0 ? null : (
              <div className="space-y-2">
                {pendingRdvs.map(rdv => (
                  <div key={rdv.id} className="bg-amber-50 border border-amber-200 rounded-2xl px-4 py-3">
                    <div className="flex items-center justify-between mb-2">
                      <div>
                        <p className="font-semibold text-sm text-[#1F2A2E]">{clientNames[rdv.client_uid] ?? '…'}</p>
                        <p className="text-xs text-gray-500">
                          {fmtDate(rdv.date_heure)}{rdv.motif ? ` · ${rdv.motif}` : ''}
                        </p>
                      </div>
                      <span className="text-[10px] font-bold bg-amber-200 text-amber-700 px-2 py-0.5 rounded-full flex-shrink-0 ml-2">
                        En attente
                      </span>
                    </div>
                    <div className="flex gap-2">
                      <button onClick={() => confirmRdv(rdv)} disabled={savingRdv === rdv.id}
                        className="flex-1 text-xs font-semibold py-1.5 rounded-xl bg-[#0C5C6C] text-white hover:bg-[#0a4a5a] disabled:opacity-50 transition-colors">
                        ✓ Confirmer
                      </button>
                      <button onClick={() => rejectRdv(rdv)} disabled={savingRdv === rdv.id}
                        className="flex-1 text-xs font-semibold py-1.5 rounded-xl border border-red-200 text-red-500 hover:bg-red-50 disabled:opacity-50 transition-colors">
                        ✗ Refuser
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* Prochains RDV confirmés */}
        <div>
          <div className="flex items-center justify-between mb-3">
            <p className="text-xs font-bold text-gray-500 uppercase tracking-wide">Prochains RDV</p>
            <Link href="/agenda" className="text-xs text-[#0C5C6C] font-medium hover:underline">Agenda →</Link>
          </div>
          {loading ? (
            <div className="bg-white rounded-2xl border border-gray-100 p-6 flex justify-center">
              <div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
            </div>
          ) : upcomingRdvs.length === 0 ? (
            <div className="bg-white rounded-2xl border border-gray-100 p-6 text-center">
              <p className="text-3xl mb-2">📭</p>
              <p className="text-sm text-gray-400">Aucun RDV confirmé à venir</p>
              <Link href="/pro/creneaux" className="text-xs text-[#0C5C6C] font-medium hover:underline mt-1 inline-block">
                Configurer mes créneaux →
              </Link>
            </div>
          ) : (
            <div className="space-y-2">
              {upcomingRdvs.map(rdv => (
                <div key={rdv.id} className="bg-white border border-gray-100 rounded-2xl px-4 py-3 flex items-center gap-3 shadow-sm"
                  style={{ borderLeft: '4px solid #0C5C6C' }}>
                  <span className="text-xl flex-shrink-0">🩺</span>
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-sm text-[#1F2A2E] truncate">{clientNames[rdv.client_uid] ?? '…'}</p>
                    <p className="text-xs text-gray-400">{fmtDate(rdv.date_heure)}{rdv.motif ? ` · ${rdv.motif}` : ''}</p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Clients / patients — pour TOUS les profils pro */}
        <div>
          <div className="flex items-center justify-between mb-3">
            <p className="text-xs font-bold text-gray-500 uppercase tracking-wide">{clientsLabel}</p>
            <Link href="/mes-patients" className="text-xs text-[#0C5C6C] font-medium hover:underline">Voir tout →</Link>
          </div>
          {loading ? (
            <div className="bg-white rounded-2xl border border-gray-100 p-6 flex justify-center">
              <div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
            </div>
          ) : patients.length === 0 ? (
            <div className="bg-white rounded-2xl border border-gray-100 p-6 text-center">
              <p className="text-3xl mb-2">🐾</p>
              <p className="text-sm text-gray-400">Aucun animal suivi pour l&apos;instant</p>
              <p className="text-xs text-gray-300 mt-1">Les propriétaires peuvent vous accorder l&apos;accès depuis la fiche de leur animal</p>
            </div>
          ) : (
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
              {patients.map(p => {
                const animal = p.animal;
                if (!animal) return null;
                return (
                  <Link key={p.id} href={`/mes-patients/${animal.id}`}
                    className="bg-white rounded-2xl border border-gray-100 shadow-sm p-3 hover:shadow-md transition-shadow">
                    <div className="flex items-center gap-2">
                      <div className="w-10 h-10 rounded-xl overflow-hidden bg-[#E3F2FD] flex-shrink-0 flex items-center justify-center">
                        {animal.photo_url
                          ? <Image src={animal.photo_url} alt="" width={40} height={40} className="object-cover w-full h-full" />
                          : <span className="text-lg">{ESPECE_EMOJI[animal.espece?.toLowerCase()] ?? '🐾'}</span>
                        }
                      </div>
                      <div className="min-w-0">
                        <p className="font-semibold text-sm text-[#1F2A2E] truncate">{animal.nom}</p>
                        <p className="text-xs text-gray-400 truncate">{animal.race || animal.espece}</p>
                      </div>
                    </div>
                    {p.status === 'active_write' && (
                      <span className="mt-1 text-[9px] font-bold text-green-600 bg-green-50 px-1.5 py-0.5 rounded-full block text-center">✏️ Accès écriture</span>
                    )}
                  </Link>
                );
              })}
            </div>
          )}
        </div>

        {/* Animaux perdus */}
        <div>
          <div className="flex items-center justify-between mb-3">
            <p className="text-xs font-bold text-gray-500 uppercase tracking-wide">Animaux perdus / trouvés</p>
            <Link href="/animaux-perdus" className="text-xs text-[#0C5C6C] font-medium hover:underline">Voir tout →</Link>
          </div>
          {lostAnimals.length === 0 ? (
            <Link href="/animaux-perdus" className="bg-white rounded-2xl border border-gray-100 p-4 flex items-center gap-3 hover:shadow-sm transition-shadow">
              <span className="text-2xl">🔍</span>
              <p className="text-sm text-gray-500">Consulter les alertes animaux perdus</p>
            </Link>
          ) : (
            <div className="grid grid-cols-2 gap-3">
              {lostAnimals.map(a => (
                <Link key={a.id} href={`/animaux-perdus/${a.id}`}
                  className="bg-white rounded-2xl border border-gray-100 shadow-sm overflow-hidden hover:shadow-md transition-shadow">
                  <div className="h-24 bg-amber-50 relative overflow-hidden">
                    {a.photo_url
                      ? <Image src={a.photo_url} alt="" fill className="object-cover" />
                      : <div className="absolute inset-0 flex items-center justify-center text-3xl">🔍</div>
                    }
                    <span className={`absolute top-2 right-2 text-[10px] font-bold px-1.5 py-0.5 rounded-full ${
                      a.statut === 'perdu' ? 'bg-red-500 text-white' : 'bg-green-500 text-white'
                    }`}>
                      {a.statut === 'perdu' ? 'PERDU' : 'TROUVÉ'}
                    </span>
                  </div>
                  <div className="p-2">
                    <p className="font-semibold text-xs text-[#1F2A2E] truncate">{a.nom || 'Inconnu'}</p>
                    <p className="text-[10px] text-gray-400">{a.espece}</p>
                  </div>
                </Link>
              ))}
            </div>
          )}
        </div>

      </div>
    </div>
  );
}
