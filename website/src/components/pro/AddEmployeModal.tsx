'use client';

// Ajout d'un employé (recherche d'un compte, limite de la formule, invitation
// notifiée). Partagé par « Mon équipe » (/elevage/employes) et les pages
// « Mes employés » des pros (pension, pet-sitter, toilettage).
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { ROLES_VETO, controleFormuleVeto, appliquerDroitsRoleVeto, type RoleVeto } from '@/lib/clinique';

interface CandidateUser {
  uid: string;
  firstname: string | null;
  lastname: string | null;
  name_elevage: string | null;
  is_elevage: boolean;
  is_pro: boolean;
  cat_pro: string | null;
}

const CAT_SANTE = new Set(['sante', 'veterinaire', 'vétérinaire', 'vet']);

function candidateNom(u: CandidateUser): string {
  if (u.is_elevage) return u.name_elevage?.trim() || 'Élevage';
  return `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim() || u.uid;
}

export default function AddEmployeModal({ uid, profileId, estClinique = false, onClose }: { uid: string; profileId: string | null; estClinique?: boolean; onClose: () => void }) {
  const [role, setRole] = useState<RoleVeto>('asv');
  const [query, setQuery] = useState('');
  const [allUsers, setAllUsers] = useState<CandidateUser[]>([]);
  const [results, setResults] = useState<CandidateUser[]>([]);
  const [loading, setLoading] = useState(true);
  const [adding, setAdding] = useState<string | null>(null);
  const [nomElevage, setNomElevage] = useState('');

  useEffect(() => {
    async function load() {
      const { data: profile } = profileId
        ? await supabase.from('user_profiles_complet').select('nom, firstname, lastname').eq('id', profileId).maybeSingle()
        : await supabase.from('user_profiles_complet').select('nom, firstname, lastname').eq('uid', uid).eq('is_main', true).maybeSingle();
      setNomElevage(
        (profile?.nom as string)?.trim() ||
        `${profile?.firstname ?? ''} ${profile?.lastname ?? ''}`.trim()
      );
      const { data } = await supabase.from('user_profiles_complet')
        .select('uid, firstname, lastname, nom, profile_type, cat_pro')
        .neq('uid', uid).eq('profile_type', 'particulier').limit(2000);
      const filtered = (data ?? []).map(u => ({
        uid: u.uid as string,
        firstname: u.firstname as string | null,
        lastname: u.lastname as string | null,
        name_elevage: u.nom as string | null,
        is_elevage: u.profile_type === 'eleveur',
        is_pro: !!u.profile_type && u.profile_type !== 'eleveur' && u.profile_type !== 'particulier',
        cat_pro: u.cat_pro as string | null,
      })).filter(u => !(u.is_pro && CAT_SANTE.has((u.cat_pro ?? '').toLowerCase().trim())));
      setAllUsers(filtered);
      setLoading(false);
    }
    load();
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [uid, profileId]);

  function search(q: string) {
    setQuery(q);
    if (q.trim().length < 2) { setResults([]); return; }
    const lq = q.toLowerCase();
    setResults(
      allUsers.filter(u =>
        `${u.firstname ?? ''} ${u.lastname ?? ''} ${u.name_elevage ?? ''}`.toLowerCase().includes(lq)
      ).slice(0, 15)
    );
  }

  async function ajouter(u: CandidateUser) {
    setAdding(u.uid);
    try {
      let existingQ = supabase.from('employes').select().eq('uid_eleveur', uid).eq('uid_employe', u.uid);
      if (profileId) existingQ = existingQ.eq('eleveur_profile_id', profileId);
      const { data: existing } = await existingQ.maybeSingle();

      // Clinique : formule (ASV dès Avancé, praticiens en Clinique).
      if (estClinique && profileId && (!existing || !existing.actif)) {
        const refus = await controleFormuleVeto(uid, profileId, role);
        if (refus) { alert(refus); return; }
      }
      // Profil particulier de la personne : c'est lui qui porte l'emploi.
      const { data: targetParticulier } = await supabase.from('user_profiles_complet')
        .select('id').eq('uid', u.uid).eq('profile_type', 'particulier').maybeSingle();

      // Limite d'employés par forfait (éducateur/pension) — la page
      // d'abonnement annonce ces limites mais rien ne les appliquait jusqu'ici.
      if (!existing || !existing.actif) {
        const catPro = profileId
          ? (await supabase.from('user_profiles_complet').select('profile_type,cat_pro').eq('id', profileId).maybeSingle()).data
          : (await supabase.from('user_profiles_complet').select('cat_pro').eq('uid', uid).eq('is_main', true).maybeSingle()).data;
        const catProVal = (catPro as { cat_pro?: string } | null)?.cat_pro;
        if (catProVal === 'education' || catProVal === 'pension') {
          const { data: abo } = await supabase.from('abonnements')
            .select('plan_code').eq('uid', uid).eq('profil_type', catProVal).eq('statut', 'actif')
            .order('created_at', { ascending: false }).limit(1).maybeSingle();
          const planCode = abo?.plan_code ?? 'free';
          const { data: planRow } = await supabase.from('plans_tarifaires')
            .select('features').eq('profil_type', catProVal).eq('plan_code', planCode).maybeSingle();
          const fallbackMax: Record<string, number> = { free: 0, pro: 3, premium: -1 };
          const features = (planRow?.features ?? {}) as Record<string, unknown>;
          const maxEmployes = typeof features.maxEmployes === 'number' ? features.maxEmployes : (fallbackMax[planCode] ?? 0);
          if (maxEmployes !== -1) {
            let countQ = supabase.from('employes').select('id', { count: 'exact', head: true })
              .eq('uid_eleveur', uid).eq('actif', true);
            if (profileId) countQ = countQ.eq('eleveur_profile_id', profileId);
            const { count } = await countQ;
            if ((count ?? 0) >= maxEmployes) {
              alert(maxEmployes === 0
                ? 'Votre formule actuelle ne permet pas d\'ajouter d\'employé. Passez à une formule supérieure.'
                : `Limite de ${maxEmployes} employé(s) atteinte pour votre formule. Passez à une formule supérieure pour en ajouter plus.`);
              return;
            }
          }
        }
      }

      if (existing) {
        if (existing.actif) { alert('Cette personne est déjà dans votre équipe.'); return; }
        await supabase.from('employes').update({
          actif: true,
          ...(estClinique ? { role_pro: role } : {}),
          ...(targetParticulier?.id ? { employe_profile_id: targetParticulier.id } : {}),
        }).eq('id', existing.id);
      } else {
        await supabase.from('employes').insert({
          uid_employe: u.uid,
          uid_eleveur: uid,
          ...(profileId ? { eleveur_profile_id: profileId } : {}),
          ...(targetParticulier?.id ? { employe_profile_id: targetParticulier.id } : {}),
          ...(estClinique ? { role_pro: role } : {}),
          actif: true,
        });
      }
      if (estClinique && profileId && targetParticulier?.id) {
        await appliquerDroitsRoleVeto(profileId, targetParticulier.id as string, role);
      }
      await supabase.from('notifications').insert({
        uid: u.uid, type: 'employee_invite',
        title: 'Invitation à rejoindre une équipe',
        body: `Vous avez été ajouté à l'équipe de ${nomElevage}`,
        ...(targetParticulier?.id ? { profile_id: targetParticulier.id } : {}),
        data: { eleveurUid: uid, eleveurNom: nomElevage },
        read: false,
      });
      onClose();
    } finally {
      setAdding(null);
    }
  }

  return (
    <div className="fixed inset-0 bg-black/60 z-50 flex items-end sm:items-center justify-center p-0 sm:p-4">
      <div className="bg-white w-full max-w-md rounded-t-3xl sm:rounded-2xl shadow-2xl max-h-[85vh] flex flex-col">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-100">
          <h3 className="font-bold text-[#1F2A2E]">{estClinique ? "Ajouter à l'équipe" : 'Ajouter un employé'}</h3>
          <button onClick={onClose} className="p-1.5 rounded-xl hover:bg-gray-100 transition-colors">
            <svg className="w-5 h-5 text-gray-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>
        {estClinique && (
          <div className="px-4 pt-4 grid grid-cols-2 gap-2">
            {ROLES_VETO.map(r => (
              <button key={r.key} type="button" onClick={() => setRole(r.key)}
                className={`rounded-xl border px-3 py-2.5 text-sm font-semibold transition-colors ${role === r.key
                  ? 'bg-[#0C5C6C] border-[#0C5C6C] text-white' : 'bg-white border-[#0C5C6C] text-[#0C5C6C]'}`}>
                {r.icon} {r.label}
              </button>
            ))}
          </div>
        )}
        <div className="p-4">
          <input value={query} onChange={e => search(e.target.value)} autoFocus
            placeholder="Rechercher par prénom ou nom…"
            className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-teal-600 focus:ring-1 focus:ring-teal-600 bg-white" />
        </div>
        <div className="flex-1 overflow-y-auto px-4 pb-4">
          {loading && <div className="flex justify-center py-8"><div className="w-5 h-5 border-2 border-teal-600 border-t-transparent rounded-full animate-spin" /></div>}
          {!loading && query.length < 2 && (
            <p className="text-xs text-gray-400 text-center py-6">Tapez au moins 2 lettres pour rechercher.</p>
          )}
          {!loading && query.length >= 2 && results.length === 0 && (
            <p className="text-sm text-gray-400 text-center py-6">Aucun utilisateur trouvé</p>
          )}
          <div className="space-y-2">
            {results.map(u => {
              const nom = candidateNom(u);
              return (
                <div key={u.uid} className="flex items-center gap-3 p-3 rounded-xl hover:bg-gray-50 transition-colors">
                  <div className="w-10 h-10 rounded-full bg-teal-50 flex items-center justify-center flex-shrink-0 font-bold text-teal-600">
                    {nom[0]?.toUpperCase() ?? '?'}
                  </div>
                  <span className="flex-1 text-sm font-medium text-[#1F2A2E]">{nom}</span>
                  <button onClick={() => ajouter(u)} disabled={adding === u.uid}
                    className="text-sm font-semibold text-teal-700 border border-teal-700 hover:bg-teal-50 px-3 py-1.5 rounded-xl transition-colors disabled:opacity-50">
                    {adding === u.uid ? '…' : 'Ajouter'}
                  </button>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
