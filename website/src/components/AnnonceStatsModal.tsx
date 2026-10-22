'use client';
// Fenêtre « Statistiques » d'une annonce. Indicateurs et calculs inchangés
// (api/annonces/stats) ; seules les données réelles sont affichées. Miroir
// appli : _AnnonceStatsSheet (lib/pages/eleveur/post/mes_annonces_page.dart).

import { useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api-fetch';
import { Icone, BORDURE } from '@/components/dashboard/kit';

interface DayStats { date: string; vues: number; visiteurs: number; contacts: number; favoris: number; }
interface GeoStat  { departement: string; vues: number; }
interface BebeStats { index: number; vues: number; favoris: number; }

interface StatsData {
  annonce: { titre?: string; espece?: string; race?: string; type?: string; type_vente?: string; photos?: string[]; created_at?: string; vues?: number; } | null;
  // type = 'portee' | 'saillie' | 'animal' ; type_vente = 'vente' | 'don' | etc.
  totalVues: number; totalContacts: number; totalFavoris: number;
  tauxConversion: number; tauxInteret: number; scoreAttractif: number;
  classement: { position: number; total: number } | null;
  daily: DayStats[]; geo: GeoStat[]; portee: BebeStats[];
}

interface Props { annonceId: string; annonceTitle?: string; isPremium: boolean; onClose: () => void; }

const TEAL = '#0C5C6C';
const ENCRE = '#1E2025';
const carte = 'bg-white rounded-2xl p-4';
const bord = { border: `1px solid ${BORDURE}` };

function Barre({ value, max, color }: { value: number; max: number; color: string }) {
  const pct = max > 0 ? Math.round((value / max) * 100) : 0;
  return (
    <div className="flex items-center gap-2">
      <div className="flex-1 bg-gray-100 rounded-full h-2">
        <div className="h-2 rounded-full" style={{ width: `${pct}%`, background: color }} />
      </div>
      <span className="text-xs text-gray-500 w-8 text-right tabular-nums">{value}</span>
    </div>
  );
}

function Kpi({ icone, teinte, valeur, label, puce }: { icone: string; teinte: string; valeur: string | number; label: string; puce?: { texte: string; fg: string; bg: string } }) {
  return (
    <div className={carte} style={bord}>
      <div className="flex items-start justify-between gap-2">
        <span style={{ color: teinte }}><Icone nom={icone} taille={22} /></span>
        {puce && <span className="text-[11px] font-semibold px-2 py-0.5 rounded-full" style={{ color: puce.fg, background: puce.bg }}>{puce.texte}</span>}
      </div>
      <p className="text-2xl font-bold mt-3 tabular-nums" style={{ color: ENCRE }}>{valeur}</p>
      <p className="text-sm text-gray-500">{label}</p>
    </div>
  );
}

/** Courbe des vues jour par jour sur la période (jours sans visite = 0). */
function CourbeVues({ daily, period }: { daily: DayStats[]; period: number }) {
  const parJour = new Map(daily.map(d => [d.date.slice(0, 10), d.vues ?? 0]));
  const jours: { date: Date; vues: number }[] = [];
  for (let i = period - 1; i >= 0; i--) {
    const d = new Date(); d.setHours(12, 0, 0, 0); d.setDate(d.getDate() - i);
    const cle = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
    jours.push({ date: d, vues: parJour.get(cle) ?? 0 });
  }
  const max = Math.max(4, ...jours.map(j => j.vues));
  const pas = max <= 8 ? 2 : Math.ceil(max / 4);
  const haut = Math.ceil(max / pas) * pas;
  const W = 560, H = 190, G = 30, B = 24, D = 8;
  const x = (i: number) => G + (i * (W - G - D)) / Math.max(1, jours.length - 1);
  const y = (v: number) => 8 + (H - B - 8) * (1 - v / haut);
  const ligne = jours.map((j, i) => `${i === 0 ? 'M' : 'L'}${x(i).toFixed(1)},${y(j.vues).toFixed(1)}`).join(' ');
  const aire = `${ligne} L${x(jours.length - 1).toFixed(1)},${y(0)} L${x(0).toFixed(1)},${y(0)} Z`;
  const graduations = Array.from({ length: haut / pas + 1 }, (_, k) => k * pas);
  const intervalle = Math.max(1, Math.round(jours.length / 7));
  const fmt = (d: Date) => d.toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' }).replace('.', '');
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-auto" role="img" aria-label="Évolution des vues">
      {graduations.map(v => (
        <g key={v}>
          <line x1={G} x2={W - D} y1={y(v)} y2={y(v)} stroke="#EEF0EE" />
          <text x={G - 8} y={y(v) + 4} textAnchor="end" fontSize="11" fill="#6B7280">{v}</text>
        </g>
      ))}
      <path d={aire} fill={TEAL} opacity={0.08} />
      <path d={ligne} fill="none" stroke={TEAL} strokeWidth={2} strokeLinejoin="round" />
      {jours.map((j, i) => <circle key={i} cx={x(i)} cy={y(j.vues)} r={jours.length > 14 ? 2.5 : 3.5} fill={TEAL}><title>{`${fmt(j.date)} : ${j.vues} vue${j.vues > 1 ? 's' : ''}`}</title></circle>)}
      {jours.map((j, i) => (i % intervalle === 0 || i === jours.length - 1) && (
        <text key={`l${i}`} x={x(i)} y={H - 6} textAnchor="middle" fontSize="11" fill="#6B7280">{fmt(j.date)}</text>
      ))}
    </svg>
  );
}

const PERIOD_OPTIONS = [7, 30] as const;
type Period = typeof PERIOD_OPTIONS[number];

export default function AnnonceStatsModal({ annonceId, annonceTitle, isPremium, onClose }: Props) {
  const [stats, setStats] = useState<StatsData | null>(null);
  const [loading, setLoading] = useState(true);
  const [period, setPeriod] = useState<Period>(30);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    apiFetch(`/api/annonces/stats?annonceId=${annonceId}&period=${period}`)
      .then(r => r.json())
      .then(d => { setStats(d); setLoading(false); })
      .catch(() => { setError('Impossible de charger les statistiques.'); setLoading(false); });
  }, [annonceId, period]);

  useEffect(() => {
    const touche = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', touche);
    return () => document.removeEventListener('keydown', touche);
  }, [onClose]);

  const conv = stats?.tauxConversion ?? 0;
  const puceConversion = conv >= 5 ? { texte: 'Bon', fg: '#2F7D3A', bg: '#EAF5EC' }
    : conv >= 2 ? { texte: 'Moyen', fg: '#B45309', bg: '#FEF3C7' }
    : { texte: 'Faible', fg: '#B91C1C', bg: '#FEF2F2' };
  const couleurScore = (s: number) => s >= 70 ? '#6E9E57' : s >= 40 ? '#D97706' : '#DC2626';

  return (
    <div className="fixed inset-0 z-50 flex items-end md:items-center justify-center bg-black/40 px-0 md:px-4" onClick={onClose}>
      <div className="bg-[#F6F7F5] rounded-t-3xl md:rounded-3xl w-full max-w-2xl max-h-[92vh] overflow-y-auto shadow-2xl" style={{ fontFamily: 'Galey, sans-serif' }}
        onClick={e => e.stopPropagation()} role="dialog" aria-modal="true" aria-label="Statistiques de l’annonce">
        {/* En-tête */}
        <div className="sticky top-0 z-10 bg-white px-5 sm:px-6 pt-5 pb-4 flex flex-wrap items-center gap-3" style={{ borderBottom: `1px solid ${BORDURE}` }}>
          <h2 className="flex-1 min-w-0 text-lg sm:text-xl font-bold truncate" style={{ color: ENCRE }}>
            Statistiques de {annonceTitle ?? 'l’annonce'}
          </h2>
          <div className="inline-flex rounded-xl p-1 bg-[#F3F6F5]" role="tablist" aria-label="Période">
            {PERIOD_OPTIONS.map(p => (
              <button key={p} onClick={() => setPeriod(p)} role="tab" aria-selected={period === p}
                className={`px-3.5 py-1.5 rounded-lg text-sm font-semibold transition-colors ${period === p ? 'bg-[#0C5C6C] text-white' : 'text-gray-600 hover:text-[#0C5C6C]'}`}>
                {p} jours
              </button>
            ))}
          </div>
          <button onClick={onClose} aria-label="Fermer" className="w-9 h-9 inline-flex items-center justify-center rounded-xl text-gray-500 hover:bg-gray-100">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M6 6l12 12M18 6L6 18" /></svg>
          </button>
        </div>

        <div className="p-4 sm:p-6 space-y-4">
          {loading && <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-2 border-[#0C5C6C] border-t-transparent" /></div>}
          {error && <p className="text-center text-red-600 py-8">{error}</p>}

          {stats && !loading && (<>
            {/* Indicateurs principaux */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              <Kpi icone="oeil" teinte={TEAL} valeur={stats.totalVues} label="Vues" />
              <Kpi icone="personne" teinte={TEAL} valeur={stats.totalContacts} label="Contacts" />
              <Kpi icone="coeur" teinte="#E0457B" valeur={stats.totalFavoris} label="Favoris" />
              <Kpi icone="barres" teinte={TEAL} valeur={`${stats.tauxConversion} %`} label="Conversion" puce={puceConversion} />
            </div>

            {/* Évolution des vues (Premium) */}
            {isPremium ? (
              <div className={carte} style={bord}>
                <p className="text-[15px] font-semibold mb-2" style={{ color: ENCRE }}>Évolution des vues</p>
                {stats.daily.length === 0
                  ? <p className="text-sm text-gray-400 text-center py-6">Pas encore de données sur cette période.</p>
                  : <CourbeVues daily={stats.daily} period={period} />}
              </div>
            ) : (
              <div className="rounded-2xl p-4 bg-[#FFFBEB]" style={{ border: '1px solid #FDE68A' }}>
                <p className="flex items-center gap-2 text-sm font-bold text-[#92400E]"><Icone nom="couronne" taille={17} />Premium</p>
                <p className="text-sm text-[#92400E] mt-1 mb-3">Débloquez l’évolution des vues sur 7 et 30 jours, l’origine géographique, les stats par chiot et le classement dans la race.</p>
                <a href="/abonnement" className="inline-flex items-center gap-2 bg-[#D97706] hover:bg-[#B45309] text-white text-sm font-semibold px-4 py-2 rounded-xl transition-colors">Passer Premium</a>
              </div>
            )}

            {/* Score d'attractivité + classement */}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div className={carte} style={bord}>
                <p className="flex items-center gap-2 text-sm font-semibold" style={{ color: ENCRE }}><span style={{ color: TEAL }}><Icone nom="etoile" taille={18} /></span>Score d’attractivité</p>
                <p className="mt-2"><span className="text-3xl font-bold tabular-nums" style={{ color: couleurScore(stats.scoreAttractif) }}>{stats.scoreAttractif}</span><span className="text-gray-400 text-sm"> / 100</span></p>
                <div className="mt-2 bg-gray-100 rounded-full h-2">
                  <div className="h-2 rounded-full" style={{ width: `${stats.scoreAttractif}%`, background: couleurScore(stats.scoreAttractif) }} />
                </div>
              </div>
              {stats.classement && (
                <div className={carte} style={bord}>
                  <p className="flex items-center gap-2 text-sm font-semibold" style={{ color: ENCRE }}><span style={{ color: TEAL }}><Icone nom="barres" taille={18} /></span>Classement dans la race</p>
                  <p className="text-3xl font-bold mt-2 tabular-nums" style={{ color: TEAL }}>{stats.classement.position}<sup className="text-base">e</sup></p>
                  <p className="text-sm text-gray-500">sur {stats.classement.total} annonce{stats.classement.total > 1 ? 's' : ''}</p>
                </div>
              )}
            </div>

            {/* Taux */}
            <div className={carte} style={bord}>
              <p className="text-sm font-semibold mb-3" style={{ color: ENCRE }}>Indicateurs</p>
              <div className="space-y-3">
                <div>
                  <div className="flex justify-between text-sm text-gray-600 mb-1"><span>Taux de contact</span><span className="tabular-nums">{stats.tauxConversion} %</span></div>
                  <div className="bg-gray-100 rounded-full h-2"><div className="h-2 rounded-full bg-[#0C5C6C]" style={{ width: `${Math.min(100, stats.tauxConversion * 5)}%` }} /></div>
                </div>
                <div>
                  <div className="flex justify-between text-sm text-gray-600 mb-1"><span>Taux d’intérêt (favoris / vues)</span><span className="tabular-nums">{stats.tauxInteret} %</span></div>
                  <div className="bg-gray-100 rounded-full h-2"><div className="h-2 rounded-full bg-[#6E9E57]" style={{ width: `${Math.min(100, stats.tauxInteret * 5)}%` }} /></div>
                </div>
              </div>
            </div>

            {/* Chiots de la portée — visible dès que l'annonce est de type portée */}
            {(stats.annonce?.type === 'portee' || stats.portee.length > 0) && (
              <div className={carte} style={bord}>
                <p className="flex items-center gap-2 text-sm font-semibold mb-3" style={{ color: ENCRE }}><span style={{ color: TEAL }}><Icone nom="patte" taille={18} /></span>Stats par chiot</p>
                {stats.portee.length === 0 ? (
                  <div className="text-center py-4">
                    <p className="text-sm font-medium text-gray-600">Les stats s’accumulent</p>
                    <p className="text-sm text-gray-400 mt-1">Chaque visite sur un chiot est comptée automatiquement. Revenez après quelques visites.</p>
                  </div>
                ) : (() => {
                  const topVues = stats.portee[0];
                  const topFavoris = [...stats.portee].sort((a, b) => b.favoris - a.favoris)[0];
                  return (<>
                    <div className="grid grid-cols-2 gap-3 mb-3">
                      <div className="rounded-xl p-3 text-center bg-[#F3F6F5]">
                        <p className="text-xs font-semibold text-gray-500 mb-1">Plus consulté</p>
                        <p className="text-lg font-bold" style={{ color: ENCRE }}>Chiot n° {topVues.index + 1}</p>
                        <p className="text-xs text-gray-500 tabular-nums">{topVues.vues} vues</p>
                      </div>
                      <div className="rounded-xl p-3 text-center bg-[#F3F6F5]">
                        <p className="text-xs font-semibold text-gray-500 mb-1">Plus aimé</p>
                        <p className="text-lg font-bold" style={{ color: ENCRE }}>Chiot n° {topFavoris.index + 1}</p>
                        <p className="text-xs text-gray-500 tabular-nums">{topFavoris.favoris} favoris</p>
                      </div>
                    </div>
                    {isPremium ? (
                      <div className="space-y-1.5 pt-3" style={{ borderTop: `1px solid ${BORDURE}` }}>
                        <p className="text-xs text-gray-400 mb-2">Classement complet</p>
                        {stats.portee.slice(0, 8).map((b, i) => (
                          <div key={b.index} className="flex items-center gap-3 text-sm">
                            <span className="font-bold text-gray-300 w-6 tabular-nums">{i + 1}</span>
                            <span className="text-gray-700 flex-1">Chiot n° {b.index + 1}</span>
                            <span className="inline-flex items-center gap-1 text-gray-500 tabular-nums"><Icone nom="oeil" taille={14} />{b.vues}</span>
                            <span className="inline-flex items-center gap-1 text-gray-500 tabular-nums"><Icone nom="coeur" taille={14} />{b.favoris}</span>
                          </div>
                        ))}
                      </div>
                    ) : (
                      <p className="text-sm text-center text-gray-500 pt-3" style={{ borderTop: `1px solid ${BORDURE}` }}>
                        <span className="font-semibold text-[#B45309]">Premium</span> : classement complet et évolution par chiot
                      </p>
                    )}
                  </>);
                })()}
              </div>
            )}

            {/* Origine géographique (Premium) */}
            {isPremium && stats.geo.length > 0 && (
              <div className={carte} style={bord}>
                <p className="flex items-center gap-2 text-sm font-semibold mb-3" style={{ color: ENCRE }}><span style={{ color: TEAL }}><Icone nom="pin" taille={18} /></span>Origine des visiteurs</p>
                <div className="space-y-2">
                  {stats.geo.slice(0, 8).map(g => (
                    <div key={g.departement}>
                      <div className="flex justify-between text-sm text-gray-600 mb-1"><span>{g.departement}</span><span className="tabular-nums">{g.vues} vues</span></div>
                      <Barre value={g.vues} max={stats.geo[0]?.vues ?? 1} color="#6E9E57" />
                    </div>
                  ))}
                </div>
              </div>
            )}
          </>)}
        </div>
      </div>
    </div>
  );
}
