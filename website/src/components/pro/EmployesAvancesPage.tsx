'use client';

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import AddEmployeModal from '@/components/pro/AddEmployeModal';
import { completerPermsPension } from '@/lib/permissions-pension';

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
  /** Photo du profil de l'employé (chargée à part). */
  photo?: string | null;
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
  permissions,
}: {
  /** Autorisations réglables ici (ex. pension) ; absent = pas de bouton. */
  permissions?: readonly { key: string; label: string; desc: string }[];
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
  const [ajout, setAjout] = useState(false);
  const [autorisations, setAutorisations] = useState<Employe | null>(null);

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
    // Nom de l'employé : son profil particulier (les colonnes prenom / nom de
    // `employes` ne sont pas remplies à l'invitation).
    const rows = (data ?? []) as Employe[];
    const pids = rows.map(e => e.employe_profile_id).filter((x): x is string => !!x);
    if (pids.length) {
      const { data: profils } = await supabase.from('user_profiles_complet')
        .select('id, firstname, lastname, avatar_url').in('id', pids);
      const parId = new Map((profils ?? []).map(p => [String(p.id), p]));
      for (const e of rows) {
        const p = e.employe_profile_id ? parId.get(e.employe_profile_id) : undefined;
        if (p) { e.prenom = e.prenom || p.firstname; e.nom = e.nom || p.lastname; e.photo = p.avatar_url; }
      }
    }
    setEmployes(rows);
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
        {hasEmployes && (
          <button onClick={() => setAjout(true)}
            className="text-sm font-semibold px-3 py-2 rounded-lg text-white"
            style={{ backgroundColor: themeColor }}>
            + Inviter
          </button>
        )}
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
            <div key={e.id} className="flex items-stretch gap-2">
            <button onClick={() => setEditing(e)}
              className="flex-1 min-w-0 flex items-center gap-3 border rounded-xl p-3 text-left hover:bg-gray-50">
              {e.photo
                // eslint-disable-next-line @next/next/no-img-element
                ? <img src={e.photo} alt="" className="w-9 h-9 rounded-full object-cover shrink-0 border-2" style={{ borderColor: e.couleur_planning || themeColor }} />
                : <span className="w-3 h-3 rounded-full shrink-0" style={{ backgroundColor: e.couleur_planning || themeColor }} />}
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
            {permissions && e.employe_profile_id && (
              <button onClick={() => setAutorisations(e)}
                className="shrink-0 px-3 rounded-xl border text-xs font-semibold hover:bg-gray-50" style={{ color: themeColor }}>
                Autorisations
              </button>
            )}
            </div>
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
      {autorisations && permissions && profileId && (
        <AutorisationsModal employe={autorisations} eleveurProfileId={profileId} permissions={permissions}
          themeColor={themeColor} onClose={() => setAutorisations(null)} />
      )}
      {ajout && user && (
        <AddEmployeModal uid={user.uid} profileId={profileId} onClose={() => { setAjout(false); load(); }} />
      )}
    </div>
  );
}

/** Autorisations d'un employé, limitées à la liste de la page (les autres sont conservées). */
function AutorisationsModal({ employe, eleveurProfileId, permissions, themeColor, onClose }: {
  employe: Employe; eleveurProfileId: string; permissions: readonly { key: string; label: string; desc: string }[];
  themeColor: string; onClose: () => void;
}) {
  const [choix, setChoix] = useState<Set<string> | null>(null);
  const [enregistrement, setEnregistrement] = useState(false);
  const [erreur, setErreur] = useState('');
  const cles = permissions.map(p => p.key);
  useEffect(() => {
    supabase.from('employe_permissions').select('permission')
      .eq('eleveur_profile_id', eleveurProfileId).eq('employe_profile_id', employe.employe_profile_id ?? '')
      .then(({ data }) => setChoix(new Set((data ?? []).map(r => String(r.permission)).filter(p => cles.includes(p)))));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [employe.id, eleveurProfileId]);
  async function enregistrer() {
    if (!choix || !employe.employe_profile_id) return;
    setEnregistrement(true); setErreur('');
    const finales = completerPermsPension(choix);
    const { error: e1 } = await supabase.from('employe_permissions').delete()
      .eq('eleveur_profile_id', eleveurProfileId).eq('employe_profile_id', employe.employe_profile_id).in('permission', cles);
    const { error: e2 } = finales.size === 0 || e1 ? { error: e1 } : await supabase.from('employe_permissions').insert(
      [...finales].map(permission => ({ eleveur_profile_id: eleveurProfileId, employe_profile_id: employe.employe_profile_id, permission })));
    setEnregistrement(false);
    if (e1 || e2) { setErreur("Les autorisations n'ont pas pu être enregistrées. Réessayez."); return; }
    onClose();
  }
  const nom = `${employe.prenom ?? ''} ${employe.nom ?? ''}`.trim() || 'cet employé';
  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-md max-h-[85vh] overflow-y-auto p-5" onClick={ev => ev.stopPropagation()}>
        <h2 className="font-bold text-lg mb-1" style={{ color: themeColor }}>Autorisations de {nom}</h2>
        <p className="text-xs text-gray-500 mb-4">Les actions sur les pensionnaires donnent aussi « Planning pension ».</p>
        {!choix ? <p className="text-center text-gray-400 py-6">Chargement…</p> : (
          <div className="space-y-2">
            {permissions.map(p => (
              <label key={p.key} className="flex items-start gap-3 border rounded-xl p-3 cursor-pointer hover:bg-gray-50">
                <input type="checkbox" className="mt-1" checked={choix.has(p.key)}
                  onChange={ev => setChoix(prev => {
                    const s = new Set(prev ?? []);
                    if (ev.target.checked) s.add(p.key); else s.delete(p.key);
                    return s;
                  })} />
                <span>
                  <span className="block text-sm font-semibold text-gray-800">{p.label}</span>
                  <span className="block text-xs text-gray-500">{p.desc}</span>
                </span>
              </label>
            ))}
          </div>
        )}
        {erreur && <p className="text-sm text-red-600 mt-3">{erreur}</p>}
        <div className="flex gap-2 mt-4">
          <button onClick={onClose} className="flex-1 py-2.5 border rounded-xl text-sm text-gray-600">Annuler</button>
          <button onClick={enregistrer} disabled={!choix || enregistrement}
            className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ backgroundColor: themeColor }}>
            {enregistrement ? 'Enregistrement…' : 'Enregistrer'}
          </button>
        </div>
      </div>
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
