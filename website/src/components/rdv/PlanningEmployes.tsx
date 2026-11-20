'use client';

// Planning de l'équipe d'un salon (toiletteur…) : la journée, RDV colorés par
// employé (employes.couleur_planning), filtre par employé, conflits signalés
// (même employé ou même poste, deux RDV qui se chevauchent). Vue « Postes » :
// postes du salon (table, baignoire…) = lignes salles_clinique de type
// « poste », gérées ici ; le poste d'un RDV (rdv.salle_id) se choisit à
// l'acceptation / la modification. Les actions passent par les modales de
// Mes RDV (onOuvrirRdv).
// Miroir appli : lib/pages/pro/toilettage_planning_employes_page.dart.

import { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { TYPE_POSTE } from '@/components/rdv/SallesClinique';

const TEAL = '#0C5C6C';
const INK = '#1E2025';
const MUTED = '#6F767B';
const LINE = '#E4E7E2';
const ROUGE = '#B42318';
const FONT = { fontFamily: 'Galey, sans-serif' } as const;

interface Employe { id: string; prenom: string | null; nom: string | null; couleur_planning: string | null }
interface Poste { id: string; nom: string; ordre: number }
interface RdvJour {
  id: string; date_heure: string; duree_minutes: number | null; motif: string | null; statut: string;
  employe_id: string | number | null; salle_id: string | null; client_profile_id: string | null; client_nom_manuel: string | null;
  animal_id: string | null; animal_nom_manuel: string | null;
}

const ymd = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

export default function PlanningEmployes({ profileId, version, onOuvrirRdv }: {
  profileId: string; version?: unknown; onOuvrirRdv: (rdvId: string) => void;
}) {
  const [jour, setJour] = useState(() => new Date());
  const [loading, setLoading] = useState(true);
  const [employes, setEmployes] = useState<Employe[]>([]);
  const [postes, setPostes] = useState<Poste[]>([]);
  const [rdvs, setRdvs] = useState<RdvJour[]>([]);
  const [noms, setNoms] = useState<{ clients: Record<string, string>; animaux: Record<string, string> }>({ clients: {}, animaux: {} });
  const [vue, setVue] = useState<'employes' | 'postes'>('employes');
  const [filtre, setFiltre] = useState<string | null>(null);
  const [gestion, setGestion] = useState(false);

  const charger = useCallback(async () => {
    if (!profileId) return;
    const debut = new Date(jour.getFullYear(), jour.getMonth(), jour.getDate());
    const fin = new Date(debut.getTime() + 86400000);
    const [em, rd, po] = await Promise.all([
      // type NULL = employé ordinaire (seuls les bénévoles d'association ont un type).
      supabase.from('employes').select('id, prenom, nom, couleur_planning')
        .eq('eleveur_profile_id', profileId).eq('actif', true).or('type.is.null,type.neq.benevole'),
      supabase.from('rdv').select('id, date_heure, duree_minutes, motif, statut, employe_id, salle_id, client_profile_id, client_nom_manuel, animal_id, animal_nom_manuel')
        .eq('pro_profile_id', profileId).in('statut', ['demande', 'confirme', 'termine'])
        .gte('date_heure', debut.toISOString()).lt('date_heure', fin.toISOString()).order('date_heure'),
      supabase.from('salles_clinique').select('id, nom, ordre').eq('clinique_profile_id', profileId)
        .eq('type_salle', TYPE_POSTE).eq('actif', true).order('ordre').order('created_at'),
    ]);
    const liste = (rd.data ?? []) as RdvJour[];
    setEmployes((em.data ?? []) as Employe[]);
    setPostes(((po.data ?? []) as { id: string; nom: string | null; ordre: number | null }[])
      .map(p => ({ id: p.id, nom: p.nom ?? 'Poste', ordre: p.ordre ?? 0 })));
    setRdvs(liste);
    const profils = [...new Set(liste.map(r => r.client_profile_id).filter(Boolean) as string[])];
    const animaux = [...new Set(liste.map(r => r.animal_id).filter(Boolean).map(String))];
    const [pp, aa] = await Promise.all([
      profils.length ? supabase.from('user_profiles_complet').select('id, firstname, lastname, nom').in('id', profils) : Promise.resolve({ data: [] }),
      animaux.length ? supabase.from('animaux').select('id, nom').in('id', animaux) : Promise.resolve({ data: [] }),
    ]);
    const clients: Record<string, string> = {};
    for (const p of (pp.data ?? []) as { id: string; firstname?: string; lastname?: string; nom?: string }[]) {
      clients[p.id] = `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim() || p.nom || '';
    }
    const bestioles: Record<string, string> = {};
    for (const a of (aa.data ?? []) as { id: string; nom?: string }[]) bestioles[String(a.id)] = a.nom ?? '';
    setNoms({ clients, animaux: bestioles });
    setLoading(false);
  }, [profileId, jour]);

  useEffect(() => { charger(); }, [charger, version]);

  const employe = (id: RdvJour['employe_id']) => (id == null ? undefined : employes.find(e => String(e.id) === String(id)));
  const couleur = (id: RdvJour['employe_id']) => employe(id)?.couleur_planning || (id == null ? '#B0B5B8' : '#FFB74D');
  const nomEmploye = (id: RdvJour['employe_id']) => {
    const e = employe(id);
    return e ? `${e.prenom ?? ''} ${e.nom ?? ''}`.trim() || 'Employé' : 'Non assigné';
  };
  const nomPoste = (id: string | null) => (id ? postes.find(p => p.id === id)?.nom : undefined);

  // Conflits : même employé (ou même poste), deux RDV qui se chevauchent.
  const conflits = useMemo(() => {
    const out = new Map<string, 'employe' | 'poste'>();
    const debut = (r: RdvJour) => new Date(r.date_heure).getTime();
    const finR = (r: RdvJour) => debut(r) + (r.duree_minutes ?? 30) * 60000;
    const actifs = rdvs.filter(r => r.statut !== 'termine');
    for (let i = 0; i < actifs.length; i++) for (let j = i + 1; j < actifs.length; j++) {
      const a = actifs[i], b = actifs[j];
      if (!(debut(a) < finR(b) && debut(b) < finR(a))) continue;
      if (a.employe_id != null && String(a.employe_id) === String(b.employe_id)) { out.set(a.id, 'employe'); out.set(b.id, 'employe'); }
      else if (a.salle_id && a.salle_id === b.salle_id) { out.set(a.id, 'poste'); out.set(b.id, 'poste'); }
    }
    return out;
  }, [rdvs]);

  const parPoste = vue === 'postes';
  const affiches = filtre == null ? rdvs
    : parPoste ? rdvs.filter(r => (filtre === '' ? !nomPoste(r.salle_id) : r.salle_id === filtre))
    : rdvs.filter(r => (filtre === '' ? r.employe_id == null : String(r.employe_id) === filtre));
  const puces: { id: string | null; l: string; c: string }[] = parPoste
    ? [{ id: null, l: 'Tous', c: '' }, ...postes.map(p => ({ id: p.id, l: p.nom, c: '' })),
       ...(rdvs.some(r => !nomPoste(r.salle_id)) ? [{ id: '', l: 'Sans poste', c: '' }] : [])]
    : [{ id: null, l: 'Tous', c: '' }, ...employes.map(e => ({ id: String(e.id), l: `${e.prenom ?? ''}`.trim() || nomEmploye(e.id), c: couleur(e.id) })),
       ...(rdvs.some(r => r.employe_id == null) ? [{ id: '', l: 'Non assigné', c: couleur(null) }] : [])];
  const aujourdhui = ymd(jour) === ymd(new Date());
  const decaler = (n: number) => setJour(d => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n));

  return (
    <div className="bg-white rounded-2xl border overflow-hidden" style={{ ...FONT, borderColor: LINE }}>
      <div className="flex flex-wrap items-center gap-3 px-3 py-3 border-b" style={{ borderColor: LINE }}>
        <div className="flex items-center gap-1">
          <button onClick={() => decaler(-1)} className="w-8 h-8 rounded-full hover:bg-gray-100" aria-label="Jour précédent">‹</button>
          <input type="date" value={ymd(jour)} onChange={e => e.target.value && setJour(new Date(e.target.value + 'T00:00:00'))}
            className="text-sm font-bold px-2 py-1 rounded-lg border" style={{ borderColor: LINE, color: INK }} />
          <button onClick={() => decaler(1)} className="w-8 h-8 rounded-full hover:bg-gray-100" aria-label="Jour suivant">›</button>
          {!aujourdhui && (
            <button onClick={() => setJour(new Date())} className="text-xs underline ml-1" style={{ color: TEAL }}>Aujourd&apos;hui</button>
          )}
        </div>
        <p className="text-sm font-semibold capitalize flex-1" style={{ color: INK }}>
          {jour.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' })}
        </p>
        <div className="flex p-[3px] rounded-xl" style={{ backgroundColor: '#F2F3F1' }}>
          {([{ v: 'employes', l: 'Employés' }, { v: 'postes', l: 'Postes' }] as const).map(o => (
            <button key={o.v} onClick={() => { setVue(o.v); setFiltre(null); }}
              className="px-3 py-1.5 rounded-[10px] text-[13px] font-semibold"
              style={{ backgroundColor: vue === o.v ? 'white' : 'transparent', color: vue === o.v ? TEAL : MUTED,
                boxShadow: vue === o.v ? '0 1px 4px rgba(0,0,0,.06)' : 'none' }}>{o.l}</button>
          ))}
        </div>
        <button onClick={() => setGestion(true)} className="text-sm font-semibold hover:underline" style={{ color: TEAL }}>Gérer les postes</button>
      </div>

      {(parPoste ? postes.length > 0 : employes.length > 0) && (
        <div className="flex flex-wrap gap-1.5 px-3 py-2.5 border-b" style={{ borderColor: LINE }}>
          {puces.map(o => (
            <button key={o.id ?? '*'} onClick={() => setFiltre(o.id)}
              className="inline-flex items-center gap-1.5 px-3 py-1 rounded-full text-xs font-semibold border"
              style={{ borderColor: filtre === o.id ? TEAL : LINE, background: filtre === o.id ? '#E8F4F6' : 'white', color: filtre === o.id ? TEAL : INK }}>
              {o.c && <span className="w-2.5 h-2.5 rounded-full" style={{ background: o.c }} />}{o.l}
            </button>
          ))}
        </div>
      )}

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="w-7 h-7 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
        </div>
      ) : (
        <div className="p-3 space-y-2">
          {!parPoste && employes.length === 0 && (
            <p className="text-xs rounded-xl px-3 py-2 bg-[#F6F7F5]" style={{ color: MUTED }}>
              Aucun employé déclaré : ajoutez votre équipe dans « Employés » pour répartir les rendez-vous.
            </p>
          )}
          {parPoste && postes.length === 0 && (
            <p className="text-xs rounded-xl px-3 py-2 bg-[#F6F7F5]" style={{ color: MUTED }}>
              Aucun poste déclaré. Créez vos postes (table 1, baignoire…) avec « Gérer les postes », puis choisissez le poste
              de chaque rendez-vous en l&apos;acceptant ou en le modifiant.
            </p>
          )}
          {affiches.length === 0 ? (
            <p className="text-center text-sm py-10" style={{ color: MUTED }}>Aucun RDV ce jour.</p>
          ) : affiches.map(r => {
            const d = new Date(r.date_heure);
            const client = (r.client_profile_id && noms.clients[r.client_profile_id]) || r.client_nom_manuel || 'Client';
            const animal = (r.animal_id && noms.animaux[String(r.animal_id)]) || r.animal_nom_manuel || '';
            const conflit = conflits.get(r.id);
            const poste = nomPoste(r.salle_id);
            return (
              <button key={r.id} onClick={() => onOuvrirRdv(r.id)}
                className="w-full text-left bg-white rounded-xl border px-3.5 py-3 flex items-center gap-3 hover:shadow-sm transition-shadow"
                style={{ borderColor: conflit ? ROUGE : LINE, borderLeft: `4px solid ${couleur(r.employe_id)}` }}>
                <span className="text-sm font-bold w-12 flex-shrink-0" style={{ color: INK }}>
                  {d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
                </span>
                <span className="flex-1 min-w-0">
                  <span className="block text-sm font-semibold truncate" style={{ color: INK }}>
                    {r.motif || 'RDV'}{animal ? ` · ${animal}` : ''} — {client}
                  </span>
                  <span className="block text-xs" style={{ color: conflit ? ROUGE : MUTED }}>
                    {nomEmploye(r.employe_id)}{poste ? ` · ${poste}` : postes.length ? ' · sans poste' : ''}
                    {r.statut === 'demande' ? ' · demande' : r.statut === 'termine' ? ' · terminé' : ''}
                    {conflit === 'employe' ? ' · conflit : deux rendez-vous en même temps' : conflit === 'poste' ? ' · conflit : poste déjà occupé' : ''}
                  </span>
                </span>
                <span className="text-xs flex-shrink-0" style={{ color: MUTED }}>{r.duree_minutes ?? 30} min</span>
              </button>
            );
          })}
        </div>
      )}
      {gestion && <GestionPostes profileId={profileId} postes={postes} onClose={() => setGestion(false)} onChange={charger} />}
    </div>
  );
}

/** Postes du salon : ajouter, renommer, ordonner, retirer (actif = false :
 *  les RDV déjà placés gardent leur poste). */
function GestionPostes({ profileId, postes, onClose, onChange }: {
  profileId: string; postes: Poste[]; onClose: () => void; onChange: () => void;
}) {
  const [nouveau, setNouveau] = useState('');
  const [edition, setEdition] = useState<Record<string, string>>({});
  const [erreur, setErreur] = useState<string | null>(null);
  const [enCours, setEnCours] = useState(false);

  async function executer(f: () => PromiseLike<{ error: { message: string } | null }>) {
    setEnCours(true); setErreur(null);
    const { error } = await f();
    if (error) setErreur(`Action impossible : ${error.message}`);
    setEnCours(false);
    onChange();
  }
  const ajouter = () => {
    const nom = nouveau.trim();
    if (!nom) return;
    setNouveau('');
    void executer(() => supabase.from('salles_clinique').insert({
      clinique_profile_id: profileId, nom, type_salle: TYPE_POSTE, ordre: postes.length,
    }));
  };
  const renommer = (id: string) => {
    const nom = (edition[id] ?? '').trim();
    setEdition(e => { const c = { ...e }; delete c[id]; return c; });
    if (!nom || nom === postes.find(p => p.id === id)?.nom) return;
    void executer(() => supabase.from('salles_clinique').update({ nom }).eq('id', id));
  };
  // Échange de deux postes : l'ordre est renuméroté (0, 1, 2…) pour rester stable.
  const deplacer = (i: number, d: -1 | 1) => {
    const liste = [...postes];
    const j = i + d;
    if (j < 0 || j >= liste.length) return;
    [liste[i], liste[j]] = [liste[j], liste[i]];
    void executer(async () => {
      for (let k = 0; k < liste.length; k++) {
        const { error } = await supabase.from('salles_clinique').update({ ordre: k }).eq('id', liste[k].id);
        if (error) return { error };
      }
      return { error: null };
    });
  };
  const retirer = (p: Poste) => {
    if (!confirm(`Retirer le poste « ${p.nom} » ? Les rendez-vous déjà placés sur ce poste le gardent.`)) return;
    void executer(() => supabase.from('salles_clinique').update({ actif: false }).eq('id', p.id));
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-md p-6 space-y-4 max-h-[90vh] overflow-y-auto"
        style={FONT} onClick={e => e.stopPropagation()}>
        <div>
          <h2 className="font-bold text-lg" style={{ color: INK }}>Postes du salon</h2>
          <p className="text-xs mt-1" style={{ color: MUTED }}>
            Table de toilettage, baignoire, poste de séchage… Le poste d&apos;un rendez-vous se choisit en l&apos;acceptant
            ou en le modifiant ; un poste déjà occupé sur le créneau est grisé.
          </p>
        </div>
        <div className="space-y-2">
          {postes.length === 0 && <p className="text-sm" style={{ color: MUTED }}>Aucun poste pour l&apos;instant.</p>}
          {postes.map((p, i) => (
            <div key={p.id} className="flex items-center gap-2">
              <input value={edition[p.id] ?? p.nom} onChange={e => setEdition(x => ({ ...x, [p.id]: e.target.value }))}
                onBlur={() => { if (edition[p.id] !== undefined) renommer(p.id); }}
                onKeyDown={e => { if (e.key === 'Enter') renommer(p.id); }}
                aria-label="Nom du poste" className="flex-1 min-w-0 border border-gray-200 rounded-xl px-3 py-2 text-sm" />
              <button onClick={() => deplacer(i, -1)} disabled={enCours || i === 0} aria-label="Monter"
                className="w-8 h-8 rounded-lg border border-gray-200 text-sm disabled:opacity-30">↑</button>
              <button onClick={() => deplacer(i, 1)} disabled={enCours || i === postes.length - 1} aria-label="Descendre"
                className="w-8 h-8 rounded-lg border border-gray-200 text-sm disabled:opacity-30">↓</button>
              <button onClick={() => retirer(p)} disabled={enCours} className="text-xs font-semibold px-1" style={{ color: ROUGE }}>Retirer</button>
            </div>
          ))}
        </div>
        <div className="flex gap-2">
          <input value={nouveau} onChange={e => setNouveau(e.target.value)} onKeyDown={e => { if (e.key === 'Enter') ajouter(); }}
            placeholder="Ex. Table 1, Baignoire" className="flex-1 min-w-0 border border-gray-200 rounded-xl px-3 py-2 text-sm" />
          <button onClick={ajouter} disabled={enCours || !nouveau.trim()}
            className="px-4 py-2 rounded-xl text-sm font-semibold text-white disabled:opacity-40" style={{ background: TEAL }}>Ajouter</button>
        </div>
        {erreur && <p className="text-sm" style={{ color: ROUGE }}>{erreur}</p>}
        <button onClick={onClose} className="w-full py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Fermer</button>
      </div>
    </div>
  );
}
