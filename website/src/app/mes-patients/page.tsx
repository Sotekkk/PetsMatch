'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import OwnerContactButton from '@/components/pro/OwnerContactButton';

function clientsPageTitle(catPro: string): string {
  if (catPro === 'veterinaire' || catPro === 'sante') return 'Mes patients';
  if (catPro === 'marechal_ferrant') return 'Mes équidés suivis';
  if (catPro === 'education') return 'Mes élèves';
  if (catPro === 'garde') return 'Mes animaux en garde';
  return 'Animaux suivis';
}

interface Animal {
  id: number;
  nom: string;
  espece: string;
  race: string;
  date_naissance: string | null;
  photo_url: string | null;
  uid_proprietaire: string | null;
}

interface Grant {
  id: string;
  animal_id: number;
  statut: string;
  granted_at: string;
  animal: Animal | null;
}

const ESPECE_EMOJI: Record<string, string> = {
  chien: '🐕', chat: '🐈', cheval: '🐴', lapin: '🐰',
  oiseau: '🦜', nac: '🦎', ovin: '🐑', caprin: '🐐', porcin: '🐷',
};

function age(dateNaissance: string | null): string {
  if (!dateNaissance) return '';
  const birth = new Date(dateNaissance);
  const now = new Date();
  const months = (now.getFullYear() - birth.getFullYear()) * 12 + now.getMonth() - birth.getMonth();
  if (months < 24) return `${months} mois`;
  return `${Math.floor(months / 12)} ans`;
}

interface ChipResult {
  id: number; nom: string; espece: string; race: string; photo_url: string | null;
  uid_eleveur: string | null; uid_proprietaire: string | null;
}

export default function MesPatientsPage() {
  const { user, userData } = useAuth();
  const router = useRouter();
  const activeProfileId = useActiveProfile();
  const [grants, setGrants] = useState<Grant[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [catPro, setCatPro] = useState('');

  // ── Recherche par numéro de puce (ajouter un patient directement) ────────
  const [showChipModal, setShowChipModal] = useState(false);
  const [chipInput, setChipInput] = useState('');
  const [chipSearching, setChipSearching] = useState(false);
  const [chipSearched, setChipSearched] = useState(false);
  const [chipResult, setChipResult] = useState<ChipResult | null>(null);
  const [chipRequestStatus, setChipRequestStatus] = useState<string | null>(null);
  const [chipRequesting, setChipRequesting] = useState(false);

  async function searchByChip() {
    const normalized = chipInput.replace(/[\s-]/g, '');
    if (!normalized) return;
    setChipSearching(true);
    setChipSearched(true);
    setChipResult(null);
    setChipRequestStatus(null);
    try {
      const { data } = await supabase.from('animaux')
        .select('id, nom, espece, race, photo_url, identification, uid_eleveur, uid_proprietaire')
        .eq('identification', normalized)
        .limit(1)
        .maybeSingle();
      if (data) {
        setChipResult(data as unknown as ChipResult);
        if (activeProfileId) {
          const { data: existing } = await supabase.from('animal_access')
            .select('statut').eq('pro_profile_id', activeProfileId).eq('animal_id', data.id)
            .neq('statut', 'revoked').limit(1).maybeSingle();
          setChipRequestStatus((existing?.statut as string | undefined) ?? null);
        }
      }
    } finally {
      setChipSearching(false);
    }
  }

  async function requestAccessByChip() {
    if (!chipResult || !activeProfileId || !user) return;
    const ownerUid = chipResult.uid_eleveur ?? chipResult.uid_proprietaire;
    if (!ownerUid) return;
    setChipRequesting(true);
    try {
      const { data: ownerProfile } = await supabase.from('user_profiles')
        .select('id').eq('uid', ownerUid).eq('is_main', true).maybeSingle();
      if (!ownerProfile) throw new Error('Profil propriétaire introuvable');
      await supabase.from('animal_access').upsert({
        pro_profile_id: activeProfileId,
        granted_by_profile_id: ownerProfile.id,
        animal_id: chipResult.id,
        permissions: ['read_basic', 'read_health', 'write_health'],
        statut: 'pending',
      }, { onConflict: 'animal_id,pro_profile_id' });

      const { data: myProfile } = await supabase.from('user_profiles')
        .select('firstname, lastname, nom').eq('uid', user.uid).eq('is_main', true).maybeSingle();
      const clinic = (myProfile?.nom ?? '').trim();
      const isClinic = clinic.length > 0;
      const displayName = isClinic ? clinic : `${myProfile?.firstname ?? ''} ${myProfile?.lastname ?? ''}`.trim();
      const vetDisplay = isClinic ? displayName : (displayName ? `Dr. ${displayName}` : 'Un professionnel');

      await supabase.from('notifications').insert({
        uid: ownerUid,
        type: 'vet_access_demande',
        title: `Demande d'accès — ${vetDisplay}`,
        body: `${vetDisplay} demande l'accès au carnet de santé de ${chipResult.nom}.`,
        profile_id: ownerProfile.id,
        data: { animal_id: chipResult.id, vet_id: user.uid, vet_nom: displayName, is_clinic: isClinic, animal_nom: chipResult.nom },
        read: false,
      });
      setChipRequestStatus('pending');
    } catch (e) {
      alert(`Erreur : ${(e as Error).message}`);
    } finally {
      setChipRequesting(false);
    }
  }

  function closeChipModal() {
    setShowChipModal(false);
    setChipInput(''); setChipSearched(false); setChipResult(null); setChipRequestStatus(null);
  }

  useEffect(() => {
    if (activeProfileId) {
      supabase.from('user_profiles').select('profile_type, cat_pro').eq('id', activeProfileId).single()
        .then(({ data }) => { if (data) { const r = data as { profile_type: string; cat_pro: string }; setCatPro(r.profile_type ?? r.cat_pro ?? ''); } });
    } else {
      setCatPro(userData?.catPro ?? '');
    }
  }, [activeProfileId, userData]);

  useEffect(() => {
    if (!user || !activeProfileId) return;
    async function load() {
      const { data: grantRows, error: grantErr } = await supabase
        .from('animal_access')
        .select('id, animal_id, statut, granted_at')
        .eq('pro_profile_id', activeProfileId)
        .neq('statut', 'revoked')
        .order('granted_at', { ascending: false });

      if (grantErr) {
        console.error('[mes-patients] grants error msg:', grantErr.message);
        console.error('[mes-patients] grants error code:', grantErr.code);
        console.error('[mes-patients] grants error details:', grantErr.details);
        console.error('[mes-patients] grants error hint:', grantErr.hint);
        setLoading(false);
        return;
      }

      // Complète avec les animaux des RDV confirmés/terminés qui n'ont pas
      // encore d'accès explicite (même logique que l'app) — filtré par
      // pro_profile_id pour éviter une fuite cross-profil.
      const seenIds = new Set((grantRows ?? []).map(g => g.animal_id));
      const { data: rdvRows } = await supabase
        .from('rdv')
        .select('animal_id')
        .eq('pro_uid', user!.uid)
        .eq('pro_profile_id', activeProfileId)
        .in('statut', ['confirme', 'termine'])
        .not('animal_id', 'is', null);
      const extraIds = [...new Set((rdvRows ?? []).map(r => r.animal_id).filter((id) => id && !seenIds.has(id)))];
      const extraGrants: Grant[] = extraIds.map(id => ({
        id: `rdv-${id}`, animal_id: id, statut: 'active', granted_at: '', animal: null,
      }));
      const allGrants = [...(grantRows ?? []), ...extraGrants];

      if (allGrants.length === 0) {
        console.log('[mes-patients] no grants for profile:', activeProfileId);
        setLoading(false);
        return;
      }

      const animalIds = allGrants.map(g => g.animal_id).filter(Boolean);
      const { data: animalRows, error: animalErr } = await supabase
        .from('animaux')
        .select('id, nom, espece, race, date_naissance, photo_url, uid_proprietaire')
        .in('id', animalIds);

      if (animalErr) console.error('[mes-patients] animaux error:', animalErr);

      const animalMap = new Map((animalRows ?? []).map(a => [a.id, a]));
      const merged = allGrants.map(g => ({
        ...g,
        animal: animalMap.get(g.animal_id) ?? null,
      }));
      setGrants(merged as unknown as Grant[]);
      setLoading(false);
    }
    load();
  }, [user, activeProfileId]);

  // Auto-retrait : le propriétaire peut aussi révoquer depuis la fiche animal
  // (mes-animaux/[id]/page.tsx) — même effet, mêmes colonnes. Ne s'applique
  // qu'aux accès explicites (animal_access), pas aux entrées "rdv-<id>"
  // (complétées depuis un RDV confirmé, sans ligne animal_access dédiée).
  async function revokeGrant(grantId: string, animalNom: string) {
    if (!confirm(`Vous retirer de la liste de ${animalNom} ? Vous n'aurez plus accès à sa fiche.`)) return;
    await supabase.from('animal_access')
      .update({ statut: 'revoked', revoked_at: new Date().toISOString() })
      .eq('id', grantId);
    setGrants(prev => prev.filter(g => g.id !== grantId));
  }

  if (!user) return (
    <div className="min-h-screen flex items-center justify-center text-gray-400 text-sm">
      Connectez-vous pour accéder à vos patients.
    </div>
  );

  const filtered = grants.filter(g => {
    if (!g.animal) return false;
    if (!search) return true;
    return g.animal.nom.toLowerCase().includes(search.toLowerCase()) ||
      g.animal.espece.toLowerCase().includes(search.toLowerCase()) ||
      g.animal.race.toLowerCase().includes(search.toLowerCase());
  });

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Header */}
      <div className="bg-[#0C5C6C] text-white px-4 py-6">
        <div className="max-w-3xl mx-auto flex items-center gap-3">
          <button onClick={() => router.back()} className="p-2 rounded-lg bg-white/10 hover:bg-white/20 transition-colors">
            ←
          </button>
          <div>
            <h1 className="text-xl font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>{clientsPageTitle(catPro)}</h1>
            <p className="text-white/60 text-xs">{grants.length} animal{grants.length !== 1 ? 'aux' : ''} avec accès accordé</p>
          </div>
        </div>
      </div>

      <div className="max-w-3xl mx-auto px-4 py-6">
        {/* Recherche */}
        <div className="mb-4 flex gap-2">
          <input
            value={search} onChange={e => setSearch(e.target.value)}
            placeholder={catPro === 'garde' ? 'Rechercher un animal…' : catPro === 'education' ? 'Rechercher un élève…' : 'Rechercher un patient…'}
            className="flex-1 bg-white border border-gray-200 rounded-2xl px-4 py-3 text-sm focus:outline-none focus:border-[#0C5C6C] shadow-sm"
            style={{ fontFamily: 'Galey, sans-serif' }}
          />
          <button
            onClick={() => setShowChipModal(true)}
            title="Ajouter un patient par numéro de puce"
            className="flex-shrink-0 bg-white border border-gray-200 rounded-2xl px-4 py-3 text-sm font-semibold text-[#0C5C6C] shadow-sm hover:bg-[#0C5C6C]/5 transition-colors flex items-center gap-1.5"
            style={{ fontFamily: 'Galey, sans-serif' }}
          >
            <span aria-hidden>#️⃣</span>
            <span className="hidden sm:inline">Puce</span>
          </button>
        </div>

        {loading ? (
          <div className="flex justify-center py-20">
            <div className="w-8 h-8 border-4 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : filtered.length === 0 ? (
          <div className="text-center py-20">
            <p className="text-4xl mb-3">🐾</p>
            <p className="text-gray-500 text-sm font-medium" style={{ fontFamily: 'Galey, sans-serif' }}>
              {search ? 'Aucun résultat' : 'Aucun patient pour l\'instant'}
            </p>
            <p className="text-gray-400 text-xs mt-1">
              Les propriétaires vous accordent l&apos;accès depuis la fiche de leur animal
            </p>
          </div>
        ) : (
          <div className="space-y-2">
            {filtered.map(g => {
              const a = g.animal;
              if (!a) return null;
              return (
                <div key={g.id} className="relative">
                  <Link href={`/mes-patients/${a.id}`}
                    className="bg-white rounded-2xl border border-gray-100 shadow-sm px-4 py-3 flex items-center gap-4 hover:shadow-md transition-shadow">
                    <div className="w-14 h-14 rounded-2xl overflow-hidden bg-[#E3F2FD] flex-shrink-0 flex items-center justify-center">
                      {a.photo_url
                        ? <Image src={a.photo_url} alt="" width={56} height={56} className="object-cover w-full h-full" />
                        : <span className="text-2xl">{ESPECE_EMOJI[a.espece?.toLowerCase()] ?? '🐾'}</span>
                      }
                    </div>
                    <div className="flex-1 min-w-0">
                      <p className="font-bold text-sm text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>{a.nom}</p>
                      <p className="text-xs text-gray-500">{a.race || a.espece}{a.date_naissance ? ` · ${age(a.date_naissance)}` : ''}</p>
                      <span className="text-[10px] font-bold text-green-600 bg-green-50 px-1.5 py-0.5 rounded-full">
                        Accès accordé
                      </span>
                    </div>
                    {(catPro === 'education' || catPro === 'garde') && <span className="w-7" />}
                    {!g.id.startsWith('rdv-') && <span className="w-7" />}
                    <span className="text-gray-300 text-lg">›</span>
                  </Link>
                  {(catPro === 'education' || catPro === 'garde') && user && (
                    <div className="absolute top-1/2 -translate-y-1/2 right-9">
                      <OwnerContactButton
                        animalId={String(a.id)}
                        animalNom={a.nom}
                        ownerUid={a.uid_proprietaire}
                        myUid={user.uid}
                        myProfileId={activeProfileId ?? null}
                      />
                    </div>
                  )}
                  {!g.id.startsWith('rdv-') && (
                    <button
                      onClick={(e) => { e.preventDefault(); revokeGrant(g.id, a.nom); }}
                      title="Me retirer"
                      className="absolute top-1/2 -translate-y-1/2 w-7 h-7 flex items-center justify-center rounded-full text-red-400 hover:bg-red-50 hover:text-red-500 transition-colors"
                      style={{ right: (catPro === 'education' || catPro === 'garde') ? '2.75rem' : '2.25rem' }}
                    >
                      <span className="text-sm">✕</span>
                    </button>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Modale recherche par numéro de puce */}
      {showChipModal && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 sm:p-4"
          onClick={closeChipModal}>
          <div className="bg-white rounded-t-2xl sm:rounded-2xl w-full sm:max-w-md p-5 max-h-[90vh] overflow-y-auto"
            onClick={e => e.stopPropagation()}>
            <h3 className="font-bold text-[#1F2A2E] text-base mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>
              Ajouter un patient par puce
            </h3>
            <p className="text-xs text-gray-500 mb-4">
              Entrez le numéro de puce (identification) de l&apos;animal pour retrouver sa fiche et demander l&apos;accès à son propriétaire.
            </p>
            <div className="flex gap-2">
              <input
                autoFocus
                value={chipInput}
                onChange={e => setChipInput(e.target.value)}
                onKeyDown={e => { if (e.key === 'Enter') searchByChip(); }}
                placeholder="Ex : 250269802005832"
                className="flex-1 border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]"
                style={{ fontFamily: 'Galey, sans-serif' }}
              />
              <button
                onClick={searchByChip}
                disabled={chipSearching || !chipInput.trim()}
                className="px-4 py-2.5 rounded-xl text-sm font-semibold bg-[#0C5C6C] text-white disabled:opacity-50"
                style={{ fontFamily: 'Galey, sans-serif' }}
              >
                {chipSearching ? '…' : 'Rechercher'}
              </button>
            </div>

            {chipSearched && !chipSearching && (
              chipResult ? (
                <div className="mt-4 border border-gray-200 rounded-xl p-3 flex items-center gap-3">
                  <div className="w-12 h-12 rounded-xl overflow-hidden bg-[#E3F2FD] flex-shrink-0 flex items-center justify-center">
                    {chipResult.photo_url
                      ? <Image src={chipResult.photo_url} alt="" width={48} height={48} className="object-cover w-full h-full" />
                      : <span className="text-xl">{ESPECE_EMOJI[chipResult.espece?.toLowerCase()] ?? '🐾'}</span>}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-sm text-[#1F2A2E]">{chipResult.nom}</p>
                    <p className="text-xs text-gray-500">{chipResult.race || chipResult.espece}</p>
                  </div>
                  {chipRequestStatus === 'pending' ? (
                    <span className="text-xs font-bold text-orange-600 bg-orange-50 px-2.5 py-1.5 rounded-full">Demande envoyée</span>
                  ) : chipRequestStatus === 'active' || chipRequestStatus === 'active_write' ? (
                    <span className="text-xs font-bold text-green-600 bg-green-50 px-2.5 py-1.5 rounded-full">Accès accordé</span>
                  ) : (
                    <button
                      onClick={requestAccessByChip}
                      disabled={chipRequesting}
                      className="text-xs font-bold text-white bg-[#6E9E57] px-3 py-1.5 rounded-full disabled:opacity-50"
                    >
                      {chipRequesting ? '…' : 'Demander l\'accès'}
                    </button>
                  )}
                </div>
              ) : (
                <p className="mt-4 text-sm text-gray-500 text-center py-3">Aucun animal trouvé avec ce numéro de puce.</p>
              )
            )}

            <button onClick={closeChipModal} className="mt-4 w-full text-xs text-gray-500 py-2">Fermer</button>
          </div>
        </div>
      )}
    </div>
  );
}
