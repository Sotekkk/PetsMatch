'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

export interface Competence { key: string; label: string }

const COULEURS_PLANNING = ['#6E9E57', '#FFB74D', '#4DB6AC', '#7986CB', '#F06292', '#BA68C8'];
const JOURS_SEMAINE = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];

interface Employe {
  id: string;
  uid_employe: string | null;
  employe_profile_id: string | null;
  prenom: string | null;
  nom: string | null;
  couleur_planning: string | null;
  competences: string[] | null;
  horaires: Record<string, { debut: string; fin: string }> | null;
}

interface Conge {
  id: string; date_debut: string; date_fin: string;
  statut: 'en_attente' | 'approuve' | 'refuse'; motif: string | null; demande_par_uid: string | null;
}

function fmtDate(iso: string) {
  const d = new Date(iso);
  return `${d.getDate().toString().padStart(2, '0')}/${(d.getMonth() + 1).toString().padStart(2, '0')}/${d.getFullYear()}`;
}

/**
 * Employés enrichis (couleur planning / compétences / horaires / congés) —
 * même architecture app que ToilettageEmployesPage/PensionEmployesPage/
 * GardeEmployesPage : vient en complément de /elevage/employes (invitation/
 * permissions, générique), pas en remplacement. Colonnes déjà génériques
 * sur `employes` (couleur_planning/competences/horaires) + table
 * `employe_conges` — pas de migration supplémentaire nécessaire ici.
 */
export default function EmployesAvancesPage({
  themeColor,
  title,
  competences,
  hasEmployes,
  planLoading,
  abonnementHref,
  guardOk,
  guardLoading,
}: {
  themeColor: string;
  title: string;
  competences: Competence[];
  hasEmployes: boolean;
  planLoading: boolean;
  abonnementHref: string;
  /** true si le profil actif correspond bien à ce métier (hook d'accès dédié) — false redirige. */
  guardOk: boolean;
  guardLoading: boolean;
}) {
  const { user, loading: authLoading } = useAuth();
  const activeProfileId = useActiveProfile();
  const router = useRouter();

  const [profileId, setProfileId] = useState<string | null>(null);
  const [employes, setEmployes] = useState<Employe[]>([]);
  const [loading, setLoading] = useState(true);
  const [editing, setEditing] = useState<Employe | null>(null);

  useEffect(() => {
    if (authLoading || guardLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (!guardOk) { router.push('/'); return; }
  }, [user, authLoading, guardOk, guardLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    let pid = activeProfileId || null;
    if (!pid) {
      const { data: mainProfile } = await supabase.from('user_profiles_complet')
        .select('id').eq('uid', user.uid).eq('is_main', true).maybeSingle();
      pid = mainProfile?.id ?? null;
    }
    setProfileId(pid);
    if (!pid) { setLoading(false); return; }

    // .neq('type', 'benevole') exclurait TOUT le monde : ce champ n'est
    // jamais renseigné pour un employé normal (seuls les bénévoles
    // association l'ont), et NULL != 'benevole' n'est jamais vrai en SQL
    // (piège déjà rencontré côté toilettage — évité ici d'entrée).
    const { data } = await supabase.from('employes').select('*')
      .eq('eleveur_profile_id', pid).eq('actif', true)
      .or('type.is.null,type.neq.benevole');
    setEmployes((data ?? []) as Employe[]);
    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  if (authLoading || guardLoading || planLoading || loading) {
    return <div className="max-w-2xl mx-auto p-6 text-center text-gray-400">Chargement…</div>;
  }

  return (
    <div className="max-w-2xl mx-auto p-4 sm:p-6">
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-xl font-bold" style={{ color: themeColor }}>{title}</h1>
        <Link href="/elevage/employes"
          className="text-sm font-semibold px-3 py-2 rounded-lg text-white"
          style={{ backgroundColor: themeColor }}>
          + Inviter
        </Link>
      </div>

      {!hasEmployes ? (
        <div className="text-center border rounded-xl p-8 bg-gray-50">
          <p className="font-semibold mb-1">Fonctionnalité réservée aux formules Pro et Premium</p>
          <p className="text-sm text-gray-500 mb-4">Couleur planning, prestations confiées, horaires et congés par employé.</p>
          <Link href={abonnementHref} className="inline-block px-4 py-2 rounded-lg text-white font-semibold"
            style={{ backgroundColor: themeColor }}>
            Voir les formules
          </Link>
        </div>
      ) : employes.length === 0 ? (
        <p className="text-center text-gray-400 py-10">Aucun employé actif.<br />Invitez-en un avec le bouton ci-dessus.</p>
      ) : (
        <div className="space-y-2">
          {employes.map(e => (
            <button key={e.id} onClick={() => setEditing(e)}
              className="w-full flex items-center gap-3 border rounded-xl p-3 text-left hover:bg-gray-50">
              <span className="w-3 h-3 rounded-full shrink-0" style={{ backgroundColor: e.couleur_planning || themeColor }} />
              <div className="flex-1 min-w-0">
                <div className="font-semibold text-sm truncate">{`${e.prenom ?? ''} ${e.nom ?? ''}`.trim() || 'Employé'}</div>
                <div className="text-xs text-gray-500 truncate">
                  {!e.competences || e.competences.length === 0
                    ? 'Toutes prestations'
                    : e.competences.map(c => competences.find(x => x.key === c)?.label ?? c).join(', ')}
                </div>
              </div>
              <span className="text-gray-300">›</span>
            </button>
          ))}
        </div>
      )}

      {editing && profileId && (
        <EmployeEditModal
          employe={editing}
          themeColor={themeColor}
          competences={competences}
          onClose={() => setEditing(null)}
          onSaved={() => { setEditing(null); load(); }}
        />
      )}
    </div>
  );
}

function EmployeEditModal({
  employe, themeColor, competences, onClose, onSaved,
}: {
  employe: Employe; themeColor: string; competences: Competence[];
  onClose: () => void; onSaved: () => void;
}) {
  const { user } = useAuth();
  const [couleur, setCouleur] = useState(employe.couleur_planning || COULEURS_PLANNING[0]);
  const [comps, setComps] = useState<Set<string>>(new Set(employe.competences ?? []));
  const [horaires, setHoraires] = useState<Record<string, { debut: string; fin: string }>>(employe.horaires ?? {});
  const [conges, setConges] = useState<Conge[]>([]);
  const [congeDebut, setCongeDebut] = useState('');
  const [congeFin, setCongeFin] = useState('');
  const [saving, setSaving] = useState(false);
  const [loadingConges, setLoadingConges] = useState(true);

  const loadConges = useCallback(async () => {
    const { data } = await supabase.from('employe_conges').select('id, date_debut, date_fin, statut, motif, demande_par_uid')
      .eq('employe_id', employe.id).order('date_debut', { ascending: false });
    setConges((data ?? []) as Conge[]);
    setLoadingConges(false);
  }, [employe.id]);

  useEffect(() => { loadConges(); }, [loadConges]);

  const repondre = async (conge: Conge, approuve: boolean) => {
    await supabase.from('employe_conges').update({ statut: approuve ? 'approuve' : 'refuse' }).eq('id', conge.id);
    if (employe.uid_employe) {
      await supabase.from('notifications').insert({
        uid: employe.uid_employe,
        type: 'conge_reponse',
        title: approuve ? 'Congé approuvé' : 'Congé refusé',
        body: approuve
          ? `Votre demande de congé du ${fmtDate(conge.date_debut)} au ${fmtDate(conge.date_fin)} a été approuvée.`
          : `Votre demande de congé du ${fmtDate(conge.date_debut)} au ${fmtDate(conge.date_fin)} a été refusée.`,
        ...(employe.employe_profile_id ? { profile_id: employe.employe_profile_id } : {}),
        data: { congeId: conge.id, approved: approuve },
        read: false,
      });
    }
    loadConges();
  };

  const toggleJour = (j: string) => {
    setHoraires(prev => {
      const next = { ...prev };
      if (next[j]) delete next[j]; else next[j] = { debut: '09:00', fin: '18:00' };
      return next;
    });
  };

  const toggleComp = (k: string) => {
    setComps(prev => {
      const next = new Set(prev);
      if (next.has(k)) next.delete(k); else next.add(k);
      return next;
    });
  };

  const addConge = async () => {
    if (!congeDebut || !congeFin) return;
    await supabase.from('employe_conges').insert({
      employe_id: employe.id, date_debut: congeDebut, date_fin: congeFin,
      statut: 'approuve', demande_par_uid: user?.uid ?? null,
    });
    setCongeDebut(''); setCongeFin('');
    loadConges();
  };

  const removeConge = async (id: string) => {
    await supabase.from('employe_conges').delete().eq('id', id);
    loadConges();
  };

  const submit = async () => {
    setSaving(true);
    await supabase.from('employes').update({
      couleur_planning: couleur,
      competences: Array.from(comps),
      horaires,
    }).eq('id', employe.id);
    setSaving(false);
    onSaved();
  };

  return (
    <div className="fixed inset-0 bg-black/40 flex items-end sm:items-center justify-center z-50" onClick={onClose}>
      <div className="bg-white rounded-t-2xl sm:rounded-2xl w-full sm:max-w-md max-h-[90vh] overflow-y-auto p-5"
        onClick={e => e.stopPropagation()}>
        <h2 className="font-bold text-lg mb-4">{`${employe.prenom ?? ''} ${employe.nom ?? ''}`.trim() || 'Employé'}</h2>

        <p className="text-xs text-gray-500 mb-2">Couleur planning</p>
        <div className="flex gap-2 mb-4">
          {COULEURS_PLANNING.map(c => (
            <button key={c} onClick={() => setCouleur(c)}
              className="w-8 h-8 rounded-full"
              style={{ backgroundColor: c, outline: couleur === c ? '2px solid #111' : 'none', outlineOffset: 2 }} />
          ))}
        </div>

        <p className="text-xs text-gray-500 mb-2">Prestations confiées (vide = toutes)</p>
        <div className="flex flex-wrap gap-2 mb-4">
          {competences.map(c => (
            <button key={c.key} onClick={() => toggleComp(c.key)}
              className="text-xs px-3 py-1.5 rounded-full border"
              style={comps.has(c.key) ? { backgroundColor: `${themeColor}33`, borderColor: themeColor } : { borderColor: '#e5e7eb' }}>
              {c.label}
            </button>
          ))}
        </div>

        <p className="text-xs text-gray-500 mb-2">Jours travaillés</p>
        <div className="flex flex-wrap gap-2 mb-4">
          {JOURS_SEMAINE.map(j => (
            <button key={j} onClick={() => toggleJour(j)}
              className="text-xs px-3 py-1.5 rounded-full border capitalize"
              style={horaires[j] ? { backgroundColor: `${themeColor}33`, borderColor: themeColor } : { borderColor: '#e5e7eb' }}>
              {j}
            </button>
          ))}
        </div>

        <div className="flex items-center justify-between mb-2">
          <p className="text-sm font-semibold text-gray-700">Congés</p>
        </div>
        <div className="flex items-center gap-2 mb-2">
          <input type="date" value={congeDebut} onChange={e => setCongeDebut(e.target.value)}
            className="border rounded px-2 py-1 text-xs flex-1" />
          <span className="text-gray-400 text-xs">→</span>
          <input type="date" value={congeFin} onChange={e => setCongeFin(e.target.value)}
            className="border rounded px-2 py-1 text-xs flex-1" />
          <button onClick={addConge} className="text-xs px-2 py-1 rounded font-semibold" style={{ color: themeColor }}>Ajouter</button>
        </div>
        {loadingConges ? null : conges.length === 0 ? (
          <p className="text-xs text-gray-400 mb-4">Aucun congé programmé.</p>
        ) : (
          <div className="space-y-2 mb-4">
            {conges.map(c => {
              const style = c.statut === 'en_attente'
                ? { label: 'En attente', bg: '#FFF3E0', color: '#C2740B' }
                : c.statut === 'refuse'
                ? { label: 'Refusé', bg: '#FFEBEE', color: '#C62828' }
                : { label: 'Approuvé', bg: '#E8F5E9', color: '#2E7D32' };
              return (
                <div key={c.id} className="border rounded-lg p-2 text-xs">
                  <div className="flex items-center justify-between gap-2">
                    <span>{fmtDate(c.date_debut)} → {fmtDate(c.date_fin)}</span>
                    <div className="flex items-center gap-2">
                      <span className="px-2 py-0.5 rounded-full font-semibold" style={{ background: style.bg, color: style.color }}>
                        {style.label}
                      </span>
                      <button onClick={() => removeConge(c.id)} className="text-gray-400 hover:text-red-500">✕</button>
                    </div>
                  </div>
                  {c.motif && <p className="text-gray-500 mt-1">{c.motif}</p>}
                  {c.statut === 'en_attente' && (
                    <div className="flex gap-2 mt-2">
                      <button onClick={() => repondre(c, false)}
                        className="flex-1 py-1 rounded border border-red-300 text-red-600 font-semibold">Refuser</button>
                      <button onClick={() => repondre(c, true)}
                        className="flex-1 py-1 rounded text-white font-semibold" style={{ backgroundColor: themeColor }}>Approuver</button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}

        <div className="flex gap-2 mt-4">
          <button onClick={onClose} className="flex-1 py-2.5 rounded-lg border font-semibold text-sm">Annuler</button>
          <button onClick={submit} disabled={saving} className="flex-1 py-2.5 rounded-lg text-white font-semibold text-sm disabled:opacity-60"
            style={{ backgroundColor: themeColor }}>
            {saving ? '…' : 'Enregistrer'}
          </button>
        </div>
      </div>
    </div>
  );
}
