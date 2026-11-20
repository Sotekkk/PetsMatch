'use client';

// Planning de l'équipe d'un salon (toiletteur…) : la journée, RDV colorés par
// employé (employes.couleur_planning), filtre par employé, conflits signalés
// (même employé, deux RDV qui se chevauchent). Pas de salles : elles sont
// propres aux cliniques vétérinaires (PlanningClinique). Les actions passent
// par les modales de Mes RDV (onOuvrirRdv).
// Miroir appli : lib/pages/pro/toilettage_planning_employes_page.dart.

import { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '@/lib/supabase';

const TEAL = '#0C5C6C';
const INK = '#1E2025';
const MUTED = '#6F767B';
const LINE = '#E4E7E2';
const ROUGE = '#B42318';
const FONT = { fontFamily: 'Galey, sans-serif' } as const;

interface Employe { id: string; prenom: string | null; nom: string | null; couleur_planning: string | null }
interface RdvJour {
  id: string; date_heure: string; duree_minutes: number | null; motif: string | null; statut: string;
  employe_id: string | number | null; client_profile_id: string | null; client_nom_manuel: string | null;
  animal_id: string | null; animal_nom_manuel: string | null;
}

const ymd = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

export default function PlanningEmployes({ profileId, version, onOuvrirRdv }: {
  profileId: string; version?: unknown; onOuvrirRdv: (rdvId: string) => void;
}) {
  const [jour, setJour] = useState(() => new Date());
  const [loading, setLoading] = useState(true);
  const [employes, setEmployes] = useState<Employe[]>([]);
  const [rdvs, setRdvs] = useState<RdvJour[]>([]);
  const [noms, setNoms] = useState<{ clients: Record<string, string>; animaux: Record<string, string> }>({ clients: {}, animaux: {} });
  const [filtre, setFiltre] = useState<string | null>(null);

  const charger = useCallback(async () => {
    if (!profileId) return;
    const debut = new Date(jour.getFullYear(), jour.getMonth(), jour.getDate());
    const fin = new Date(debut.getTime() + 86400000);
    const [em, rd] = await Promise.all([
      // type NULL = employé ordinaire (seuls les bénévoles d'association ont un type).
      supabase.from('employes').select('id, prenom, nom, couleur_planning')
        .eq('eleveur_profile_id', profileId).eq('actif', true).or('type.is.null,type.neq.benevole'),
      supabase.from('rdv').select('id, date_heure, duree_minutes, motif, statut, employe_id, client_profile_id, client_nom_manuel, animal_id, animal_nom_manuel')
        .eq('pro_profile_id', profileId).in('statut', ['demande', 'confirme', 'termine'])
        .gte('date_heure', debut.toISOString()).lt('date_heure', fin.toISOString()).order('date_heure'),
    ]);
    const liste = (rd.data ?? []) as RdvJour[];
    setEmployes((em.data ?? []) as Employe[]);
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

  // Conflits : même employé, deux RDV qui se chevauchent.
  const conflits = useMemo(() => {
    const out = new Set<string>();
    const debut = (r: RdvJour) => new Date(r.date_heure).getTime();
    const finR = (r: RdvJour) => debut(r) + (r.duree_minutes ?? 30) * 60000;
    const avec = rdvs.filter(r => r.employe_id != null);
    for (let i = 0; i < avec.length; i++) for (let j = i + 1; j < avec.length; j++) {
      const a = avec[i], b = avec[j];
      if (String(a.employe_id) === String(b.employe_id) && debut(a) < finR(b) && debut(b) < finR(a)) { out.add(a.id); out.add(b.id); }
    }
    return out;
  }, [rdvs]);

  const affiches = filtre == null ? rdvs : rdvs.filter(r => (filtre === '' ? r.employe_id == null : String(r.employe_id) === filtre));
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
        <p className="text-sm font-semibold capitalize" style={{ color: INK }}>
          {jour.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' })}
        </p>
      </div>

      {employes.length > 0 && (
        <div className="flex flex-wrap gap-1.5 px-3 py-2.5 border-b" style={{ borderColor: LINE }}>
          {[{ id: null as string | null, l: 'Tous', c: '' }, ...employes.map(e => ({ id: String(e.id), l: `${e.prenom ?? ''}`.trim() || nomEmploye(e.id), c: couleur(e.id) })),
            ...(rdvs.some(r => r.employe_id == null) ? [{ id: '', l: 'Non assigné', c: couleur(null) }] : [])].map(o => (
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
          {employes.length === 0 && (
            <p className="text-xs rounded-xl px-3 py-2 bg-[#F6F7F5]" style={{ color: MUTED }}>
              Aucun employé déclaré : ajoutez votre équipe dans « Employés » pour répartir les rendez-vous.
            </p>
          )}
          {affiches.length === 0 ? (
            <p className="text-center text-sm py-10" style={{ color: MUTED }}>Aucun RDV ce jour.</p>
          ) : affiches.map(r => {
            const d = new Date(r.date_heure);
            const client = (r.client_profile_id && noms.clients[r.client_profile_id]) || r.client_nom_manuel || 'Client';
            const animal = (r.animal_id && noms.animaux[String(r.animal_id)]) || r.animal_nom_manuel || '';
            const conflit = conflits.has(r.id);
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
                    {nomEmploye(r.employe_id)}{r.statut === 'demande' ? ' · demande' : r.statut === 'termine' ? ' · terminé' : ''}
                    {conflit ? ' · conflit : deux rendez-vous en même temps' : ''}
                  </span>
                </span>
                <span className="text-xs flex-shrink-0" style={{ color: MUTED }}>{r.duree_minutes ?? 30} min</span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}
