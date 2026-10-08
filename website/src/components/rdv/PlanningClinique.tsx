'use client';

// Planning de la clinique vétérinaire : journée en colonnes, par praticien ou
// par salle — RDV confirmés, demandes (dont « vétérinaire au choix »),
// indisponibilités et disponibilités. Les actions passent par les modales de
// Mes RDV (onOuvrirRdv). Miroir app : lib/pages/pro/planning_clinique_page.dart.

import { useCallback, useEffect, useMemo, useState } from 'react';
import { supabase } from '@/lib/supabase';

const TEAL = '#0C5C6C';
const INK = '#1E2025';
const MUTED = '#6F767B';
const LINE = '#E4E7E2';
const FONT = { fontFamily: 'Galey, sans-serif' } as const;
const H_PX = 64;      // hauteur d'une heure
const COL_W = 160;
const COULEURS = ['#0C5C6C', '#6E9E57', '#E08A3C', '#8E5BB5', '#C2185B', '#1E88E5', '#6D4C41'];

interface RdvPlanning {
  id: string; date_heure: string; duree_minutes?: number | null; statut: string; motif?: string | null;
  instructeur_profile_id?: string | null; salle_id?: string | null; praticien_indifferent?: boolean | null;
  animal_id?: string | null; animal_nom_manuel?: string | null;
  client_profile_id?: string | null; client_nom_manuel?: string | null;
}
interface Colonne { id: string; titre: string; sousTitre?: string; couleur: string }

const ymd = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const minutes = (hhmm: string) => { const [h, m] = hhmm.split(':'); return Number(h) * 60 + Number(m); };
const TYPES: Record<string, string> = { consultation: 'Consultation', chirurgie: 'Chirurgie', imagerie: 'Imagerie', hospitalisation: 'Hospitalisation' };

export default function PlanningClinique({ profileId, version, onOuvrirRdv, onCreer }: {
  profileId: string;
  /** Case vide touchée → nouveau RDV (praticien '' = titulaire, null = non précisé). */
  onCreer?: (date: Date, praticien: string | null, salle: string | null) => void;
  /** Change quand Mes RDV a rechargé ses RDV (après une action) → rechargement. */
  version?: unknown;
  onOuvrirRdv: (rdvId: string) => void;
}) {
  const [jour, setJour] = useState(() => new Date());
  const [parSalle, setParSalle] = useState(false);
  const [loading, setLoading] = useState(true);
  const [praticiens, setPraticiens] = useState<{ id: string; nom: string }[]>([]);
  const [salles, setSalles] = useState<{ id: string; nom: string; type: string }[]>([]);
  const [rdvs, setRdvs] = useState<RdvPlanning[]>([]);
  const [indispos, setIndispos] = useState<{ id: string; titre?: string; date_debut: string; date_fin?: string | null; duree_minutes?: number | null; praticien_profile_id?: string | null }[]>([]);
  const [creneaux, setCreneaux] = useState<{ praticien_profile_id: string | null; salle_id: string | null; heure_debut: string; heure_fin: string }[]>([]);
  const [noms, setNoms] = useState<{ clients: Record<string, string>; animaux: Record<string, string> }>({ clients: {}, animaux: {} });

  const charger = useCallback(async () => {
    if (!profileId) return;
    const debut = new Date(jour.getFullYear(), jour.getMonth(), jour.getDate());
    const fin = new Date(debut.getTime() + 86400000);
    const veille = new Date(debut.getTime() - 86400000);
    const [pr, sa, rd, ind, cr] = await Promise.all([
      supabase.rpc('pm_praticiens_clinique', { p_pro_profile_id: profileId }),
      supabase.from('salles_clinique').select('id, nom, type_salle').eq('clinique_profile_id', profileId).eq('actif', true).order('ordre'),
      supabase.from('rdv').select('id, date_heure, duree_minutes, statut, motif, instructeur_profile_id, salle_id, praticien_indifferent, animal_id, animal_nom_manuel, client_profile_id, client_nom_manuel')
        .eq('pro_profile_id', profileId).in('statut', ['demande', 'confirme', 'termine'])
        .gte('date_heure', debut.toISOString()).lt('date_heure', fin.toISOString()),
      supabase.from('agenda_events').select('id, titre, date_debut, date_fin, duree_minutes, praticien_profile_id')
        .eq('type', 'indisponible').eq('pro_profile_id', profileId)
        .lt('date_debut', fin.toISOString()).gte('date_debut', veille.toISOString()),
      supabase.from('creneaux_pro').select('praticien_profile_id, salle_id, heure_debut, heure_fin').eq('pro_profile_id', profileId).eq('date', ymd(jour)),
    ]);
    const liste = (rd.data ?? []) as RdvPlanning[];
    setPraticiens(((pr.data ?? []) as { praticien_profile_id: string | null; nom: string | null }[])
      .map(p => ({ id: p.praticien_profile_id ?? '', nom: p.nom?.trim() || 'Vétérinaire' })));
    setSalles(((sa.data ?? []) as { id: string; nom: string | null; type_salle: string | null }[])
      .map(s => ({ id: s.id, nom: s.nom ?? 'Salle', type: s.type_salle ?? 'consultation' })));
    setRdvs(liste);
    setIndispos((ind.data ?? []) as typeof indispos);
    setCreneaux((cr.data ?? []) as typeof creneaux);

    const profils = [...new Set(liste.map(r => r.client_profile_id).filter(Boolean) as string[])];
    const animaux = [...new Set(liste.map(r => r.animal_id).filter(Boolean) as string[])];
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

  const couleurPraticien = useCallback((id: string | null | undefined) => {
    const i = praticiens.findIndex(p => p.id === (id ?? ''));
    return COULEURS[(i < 0 ? 0 : i) % COULEURS.length];
  }, [praticiens]);

  const colonnes: Colonne[] = useMemo(() => {
    if (parSalle) {
      const cols: Colonne[] = salles.map(s => ({ id: s.id, titre: s.nom, sousTitre: TYPES[s.type] ?? s.type, couleur: TEAL }));
      if (rdvs.some(r => !r.salle_id || !salles.some(s => s.id === r.salle_id))) cols.push({ id: '', titre: 'Sans salle', couleur: MUTED });
      return cols;
    }
    return praticiens.map(p => ({ id: p.id, titre: p.nom, couleur: couleurPraticien(p.id) }));
  }, [parSalle, salles, praticiens, rdvs, couleurPraticien]);

  const [deb, fin] = useMemo(() => {
    let a = 8 * 60, b = 19 * 60;
    for (const c of creneaux) { a = Math.min(a, minutes(c.heure_debut)); b = Math.max(b, minutes(c.heure_fin)); }
    for (const r of rdvs) {
      const d = new Date(r.date_heure); const m = d.getHours() * 60 + d.getMinutes();
      a = Math.min(a, m); b = Math.max(b, m + (r.duree_minutes ?? 30));
    }
    return [Math.floor(a / 60) * 60, Math.ceil(b / 60) * 60];
  }, [creneaux, rdvs]);
  const hauteur = (fin - deb) / 60 * H_PX;
  const y = (m: number) => (m - deb) / 60 * H_PX;

  const dansColonne = (r: RdvPlanning, c: Colonne) => parSalle
    ? (c.id === '' ? (!r.salle_id || !salles.some(s => s.id === r.salle_id)) : r.salle_id === c.id)
    : (r.instructeur_profile_id ?? '') === c.id;

  const nomPraticien = (id?: string | null) => praticiens.find(p => p.id === (id ?? ''))?.nom ?? 'Vétérinaire';
  const aujourdhui = ymd(jour) === ymd(new Date());
  const decaler = (n: number) => setJour(d => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n));
  const debJour = new Date(jour.getFullYear(), jour.getMonth(), jour.getDate());

  return (
    <div className="bg-white rounded-2xl border overflow-hidden" style={{ ...FONT, borderColor: LINE }}>
      {/* Barre : date + bascule */}
      <div className="flex flex-wrap items-center justify-between gap-3 px-3 py-3 border-b" style={{ borderColor: LINE }}>
        <div className="flex items-center gap-1">
          <button onClick={() => decaler(-1)} className="w-8 h-8 rounded-full hover:bg-gray-100" aria-label="Jour précédent">‹</button>
          <input type="date" value={ymd(jour)} onChange={e => e.target.value && setJour(new Date(e.target.value + 'T00:00:00'))}
            className="text-sm font-bold px-2 py-1 rounded-lg border" style={{ borderColor: LINE, color: INK }} />
          <button onClick={() => decaler(1)} className="w-8 h-8 rounded-full hover:bg-gray-100" aria-label="Jour suivant">›</button>
          {!aujourdhui && (
            <button onClick={() => setJour(new Date())} className="text-xs underline ml-1" style={{ color: TEAL }}>Aujourd&apos;hui</button>
          )}
        </div>
        <div className="flex p-[3px] rounded-xl" style={{ backgroundColor: '#F2F3F1' }}>
          {[{ v: false, l: 'Praticiens' }, { v: true, l: 'Salles' }].map(o => (
            <button key={o.l} onClick={() => setParSalle(o.v)}
              className="px-3 py-1.5 rounded-[10px] text-[13px] font-semibold transition-all"
              style={{ backgroundColor: parSalle === o.v ? 'white' : 'transparent', color: parSalle === o.v ? TEAL : MUTED,
                boxShadow: parSalle === o.v ? '0 1px 4px rgba(0,0,0,.06)' : 'none' }}>
              {o.l}
            </button>
          ))}
        </div>
      </div>

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="w-7 h-7 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
        </div>
      ) : colonnes.length === 0 ? (
        <p className="text-center text-sm py-12" style={{ color: MUTED }}>
          {parSalle ? 'Aucune salle déclarée pour la clinique.' : 'Aucun praticien.'}
        </p>
      ) : (
        <div className="overflow-x-auto">
          <div style={{ minWidth: 48 + colonnes.length * COL_W }}>
            {/* En-têtes */}
            <div className="flex border-b sticky top-0 bg-white z-10" style={{ borderColor: LINE }}>
              <div className="w-12 flex-shrink-0" />
              {colonnes.map(c => (
                <div key={c.id || '_'} className="flex-1 px-2 py-2 border-l flex items-center gap-1.5 min-w-0" style={{ borderColor: LINE, minWidth: COL_W }}>
                  <span className="w-2 h-2 rounded-full flex-shrink-0" style={{ background: c.couleur }} />
                  <span className="min-w-0">
                    <span className="block text-[12.5px] font-bold truncate" style={{ color: INK }}>{c.titre}</span>
                    {c.sousTitre && <span className="block text-[10.5px] truncate" style={{ color: MUTED }}>{c.sousTitre}</span>}
                  </span>
                </div>
              ))}
            </div>
            {/* Grille */}
            <div className="flex max-h-[70vh] overflow-y-auto">
              <div className="w-12 flex-shrink-0 relative" style={{ height: hauteur }}>
                {Array.from({ length: (fin - deb) / 60 }, (_, i) => (
                  <span key={i} className="absolute right-1.5 text-[10.5px]" style={{ top: i * H_PX - 6, color: MUTED }}>
                    {String((deb / 60) + i).padStart(2, '0')}:00
                  </span>
                ))}
              </div>
              {colonnes.map(c => {
                const dispos = parSalle ? creneaux.filter(x => c.id && x.salle_id === c.id) : creneaux.filter(x => (x.praticien_profile_id ?? '') === c.id);
                const ind = parSalle ? [] : indispos.filter(e => (e.praticien_profile_id ?? '') === c.id);
                return (
                  <div key={c.id || '_'} className={`flex-1 relative border-l overflow-hidden ${onCreer ? 'cursor-copy' : ''}`}
                    style={{ height: hauteur, minWidth: COL_W, borderColor: LINE }}
                    title={onCreer ? 'Cliquer pour ajouter un RDV' : undefined}
                    onClick={e => {
                      if (!onCreer) return;
                      const m = deb + Math.floor((e.clientY - e.currentTarget.getBoundingClientRect().top) / H_PX * 60 / 15) * 15;
                      onCreer(new Date(debJour.getTime() + m * 60000), parSalle ? null : c.id, parSalle && c.id ? c.id : null);
                    }}>
                    {dispos.map((x, i) => (
                      <div key={i} className="absolute left-0 right-0" style={{ top: y(minutes(x.heure_debut)), height: (minutes(x.heure_fin) - minutes(x.heure_debut)) / 60 * H_PX, background: '#EFF6F1' }} />
                    ))}
                    {Array.from({ length: (fin - deb) / 60 - 1 }, (_, i) => (
                      <div key={i} className="absolute left-0 right-0 h-px" style={{ top: (i + 1) * H_PX, background: '#F0F1EF' }} />
                    ))}
                    {ind.map(e => {
                      const d0 = new Date(e.date_debut);
                      const d1 = e.date_fin ? new Date(e.date_fin) : new Date(d0.getTime() + (e.duree_minutes ?? 60) * 60000);
                      const a = Math.max(0, (d0.getTime() - debJour.getTime()) / 60000);
                      const b = Math.min(1440, (d1.getTime() - debJour.getTime()) / 60000);
                      if (b <= a) return null;
                      return (
                        <div key={e.id} className="absolute left-0.5 right-0.5 rounded-md p-1 text-[10.5px] overflow-hidden"
                          style={{ top: Math.max(0, y(a)), height: (b - a) / 60 * H_PX, background: '#E9EAE8', border: '1px solid #D0D3CF', color: MUTED }}>
                          {e.titre || 'Indisponible'}
                        </div>
                      );
                    })}
                    {rdvs.filter(r => dansColonne(r, c)).map(r => {
                      const d = new Date(r.date_heure);
                      const m = d.getHours() * 60 + d.getMinutes();
                      const h = Math.max(22, (r.duree_minutes ?? 30) / 60 * H_PX);
                      const demande = r.statut === 'demande';
                      const auChoix = demande && r.praticien_indifferent;
                      const coul = couleurPraticien(r.instructeur_profile_id);
                      const animal = (r.animal_id && noms.animaux[String(r.animal_id)]) || r.animal_nom_manuel || '';
                      const client = (r.client_profile_id && noms.clients[r.client_profile_id]) || r.client_nom_manuel || '';
                      const heure = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;
                      return (
                        <button key={r.id} onClick={e => { e.stopPropagation(); onOuvrirRdv(r.id); }}
                          className="absolute left-[3px] right-[3px] rounded-[7px] px-1.5 py-0.5 text-left overflow-hidden hover:shadow-md transition-shadow"
                          style={{ top: y(m), height: h, background: demande ? 'white' : `${coul}E0`, border: `${demande ? 1.5 : 1}px solid ${coul}`, color: demande ? INK : 'white' }}>
                          <span className="block text-[11px] font-bold truncate">{heure} · {r.motif || 'RDV'}</span>
                          {h >= 34 && (animal || client) && <span className="block text-[10.5px] truncate opacity-85">{[animal, client].filter(Boolean).join(' · ')}</span>}
                          {h >= 48 && (
                            <span className={`block text-[10px] truncate ${demande ? 'italic' : ''}`} style={{ color: demande ? coul : 'rgba(255,255,255,.85)' }}>
                              {auChoix ? 'Demande · vétérinaire au choix' : demande ? 'Demande à valider' : parSalle ? nomPraticien(r.instructeur_profile_id) : ''}
                            </span>
                          )}
                        </button>
                      );
                    })}
                  </div>
                );
              })}
            </div>
          </div>
        </div>
      )}

      {/* Légende */}
      <div className="flex flex-wrap gap-x-4 gap-y-1.5 px-3 py-2.5 border-t text-[11px]" style={{ borderColor: LINE, color: MUTED }}>
        {[
          { f: `${TEAL}E0`, b: TEAL, l: 'Confirmé' },
          { f: 'white', b: TEAL, l: 'Demande' },
          { f: '#EFF6F1', b: '#CFE3D6', l: 'Disponible' },
          { f: '#E9EAE8', b: '#D0D3CF', l: 'Indisponible' },
        ].map(x => (
          <span key={x.l} className="flex items-center gap-1.5">
            <span className="w-3.5 h-3.5 rounded" style={{ background: x.f, border: `1px solid ${x.b}` }} />{x.l}
          </span>
        ))}
      </div>
    </div>
  );
}
