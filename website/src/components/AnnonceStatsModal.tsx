'use client';

import { useEffect, useState } from 'react';
import { usePlan } from '@/lib/use-plan';

interface DayStats { date: string; vues: number; visiteurs: number; contacts: number; favoris: number; }
interface GeoStat  { departement: string; vues: number; }
interface BebeStats { index: number; vues: number; favoris: number; }

interface StatsData {
  annonce: { titre?: string; espece?: string; race?: string; type?: string; type_vente?: string; photos?: string[]; created_at?: string; vues?: number; } | null;
  totalVues: number; totalContacts: number; totalFavoris: number;
  tauxConversion: number; tauxInteret: number; scoreAttractif: number;
  classement: { position: number; total: number } | null;
  daily: DayStats[]; geo: GeoStat[]; portee: BebeStats[];
}

interface Props { annonceId: string; annonceTitle?: string; isPremium: boolean; onClose: () => void; }

function Bar({ value, max, color }: { value: number; max: number; color: string }) {
  const pct = max > 0 ? Math.round((value / max) * 100) : 0;
  return (
    <div className="flex items-center gap-2">
      <div className="flex-1 bg-gray-100 rounded-full h-2">
        <div className={`h-2 rounded-full ${color}`} style={{ width: `${pct}%` }} />
      </div>
      <span className="text-xs text-gray-500 w-8 text-right">{value}</span>
    </div>
  );
}

function StatCard({ icon, label, value, sub, color }: { icon: string; label: string; value: string | number; sub?: string; color?: string }) {
  return (
    <div className="bg-white rounded-2xl p-4 shadow-sm border border-gray-100">
      <div className="flex items-start justify-between mb-1">
        <span className="text-xl">{icon}</span>
        {sub && <span className={`text-xs font-medium px-2 py-0.5 rounded-full ${color ?? 'bg-gray-100 text-gray-500'}`}>{sub}</span>}
      </div>
      <p className="text-2xl font-bold text-[#1F2A2E] mt-1" style={{ fontFamily: 'Galey, sans-serif' }}>{value}</p>
      <p className="text-xs text-gray-500 mt-0.5">{label}</p>
    </div>
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
    fetch(`/api/annonces/stats?annonceId=${annonceId}&period=${period}`)
      .then(r => r.json())
      .then(d => { setStats(d); setLoading(false); })
      .catch(() => { setError('Impossible de charger les statistiques.'); setLoading(false); });
  }, [annonceId, period]);

  const maxVues = stats ? Math.max(...(stats.daily.map(d => d.vues)), 1) : 1;

  return (
    <div className="fixed inset-0 z-50 flex items-end md:items-center justify-center bg-black/40 px-4 pb-4 md:pb-0">
      <div className="bg-[#F8F8F6] rounded-3xl w-full max-w-2xl max-h-[90vh] overflow-y-auto shadow-2xl">
        {/* Header */}
        <div className="sticky top-0 bg-gradient-to-r from-[#0C5C6C] to-[#6E9E57] rounded-t-3xl px-6 py-4 flex items-center justify-between">
          <div>
            <p className="text-white/70 text-xs">Statistiques</p>
            <p className="text-white font-bold text-base leading-tight" style={{ fontFamily: 'Galey, sans-serif' }}>{annonceTitle ?? 'Annonce'}</p>
          </div>
          <button onClick={onClose} className="text-white/80 hover:text-white text-2xl leading-none">✕</button>
        </div>

        <div className="p-5 space-y-5">
          {loading && <div className="flex justify-center py-12"><div className="animate-spin rounded-full h-8 w-8 border-b-2 border-[#0C5C6C]" /></div>}
          {error && <p className="text-center text-red-500 py-8">{error}</p>}

          {stats && !loading && (<>
            {/* Période */}
            <div className="flex gap-2">
              {PERIOD_OPTIONS.map(p => (
                <button key={p} onClick={() => setPeriod(p)}
                  className={`px-4 py-1.5 rounded-full text-sm font-medium transition-colors ${period === p ? 'bg-[#0C5C6C] text-white' : 'bg-white text-gray-500 border border-gray-200'}`}>
                  {p} jours
                </button>
              ))}
            </div>

            {/* KPIs principaux */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              <StatCard icon="👁️" label="Vues" value={stats.totalVues} />
              <StatCard icon="💬" label="Contacts" value={stats.totalContacts} />
              <StatCard icon="❤️" label="Favoris" value={stats.totalFavoris} />
              <StatCard icon="📈" label="Conversion"
                value={`${stats.tauxConversion}%`}
                sub={stats.tauxConversion >= 5 ? '🔥 Bon' : stats.tauxConversion >= 2 ? '👍 Moyen' : '📉 Faible'}
                color={stats.tauxConversion >= 5 ? 'bg-green-100 text-green-700' : stats.tauxConversion >= 2 ? 'bg-amber-100 text-amber-700' : 'bg-red-100 text-red-700'}
              />
            </div>

            {/* Score attractivité + classement */}
            <div className="grid grid-cols-2 gap-3">
              <div className="bg-white rounded-2xl p-4 shadow-sm border border-gray-100">
                <div className="flex items-center gap-2 mb-2">
                  <span className="text-lg">🏆</span>
                  <span className="text-sm font-semibold text-[#1F2A2E]">Score attractivité</span>
                </div>
                <div className="flex items-end gap-1">
                  <span className="text-3xl font-bold" style={{ fontFamily: 'Galey, sans-serif',
                    color: stats.scoreAttractif >= 70 ? '#6E9E57' : stats.scoreAttractif >= 40 ? '#F59E0B' : '#EF4444' }}>
                    {stats.scoreAttractif}
                  </span>
                  <span className="text-gray-400 text-sm mb-1">/100</span>
                </div>
                <div className="mt-1 bg-gray-100 rounded-full h-2">
                  <div className="h-2 rounded-full transition-all" style={{
                    width: `${stats.scoreAttractif}%`,
                    backgroundColor: stats.scoreAttractif >= 70 ? '#6E9E57' : stats.scoreAttractif >= 40 ? '#F59E0B' : '#EF4444'
                  }} />
                </div>
              </div>
              {stats.classement && (
                <div className="bg-white rounded-2xl p-4 shadow-sm border border-gray-100">
                  <div className="flex items-center gap-2 mb-2">
                    <span className="text-lg">🎯</span>
                    <span className="text-sm font-semibold text-[#1F2A2E]">Classement race</span>
                  </div>
                  <p className="text-3xl font-bold text-[#0C5C6C]" style={{ fontFamily: 'Galey, sans-serif' }}>
                    #{stats.classement.position}
                  </p>
                  <p className="text-xs text-gray-500">sur {stats.classement.total} annonces</p>
                </div>
              )}
            </div>

            {/* Taux d'intérêt */}
            <div className="bg-white rounded-2xl p-4 shadow-sm border border-gray-100">
              <p className="text-sm font-semibold text-[#1F2A2E] mb-3">📊 Indicateurs</p>
              <div className="space-y-3">
                <div>
                  <div className="flex justify-between text-xs text-gray-500 mb-1"><span>Taux de contact</span><span>{stats.tauxConversion}%</span></div>
                  <div className="bg-gray-100 rounded-full h-2"><div className="h-2 rounded-full bg-[#0C5C6C]" style={{ width: `${Math.min(100, stats.tauxConversion * 5)}%` }} /></div>
                </div>
                <div>
                  <div className="flex justify-between text-xs text-gray-500 mb-1"><span>Taux d'intérêt (favoris/vues)</span><span>{stats.tauxInteret}%</span></div>
                  <div className="bg-gray-100 rounded-full h-2"><div className="h-2 rounded-full bg-[#6E9E57]" style={{ width: `${Math.min(100, stats.tauxInteret * 5)}%` }} /></div>
                </div>
              </div>
            </div>

            {/* Évolution vues (Premium) */}
            {isPremium ? (
              <div className="bg-white rounded-2xl p-4 shadow-sm border border-gray-100">
                <p className="text-sm font-semibold text-[#1F2A2E] mb-3">📈 Évolution des vues ({period}j)</p>
                {stats.daily.length === 0 ? (
                  <p className="text-sm text-gray-400 text-center py-4">Pas encore de données</p>
                ) : (
                  <div className="space-y-1.5">
                    {stats.daily.slice(-14).map(d => (
                      <div key={d.date}>
                        <div className="flex items-center gap-2 text-xs text-gray-400 mb-0.5">
                          <span className="w-16">{new Date(d.date).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' })}</span>
                          <Bar value={d.vues} max={maxVues} color="bg-[#0C5C6C]" />
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            ) : (
              <div className="bg-gradient-to-br from-amber-50 to-orange-50 border border-amber-200 rounded-2xl p-4">
                <div className="flex items-center gap-2 mb-2"><span>👑</span><span className="text-sm font-bold text-amber-800">Premium</span></div>
                <p className="text-xs text-amber-700 mb-3">Débloquez l'évolution des vues sur 7 et 30 jours, l'origine géographique, les stats par chiot et le classement dans la race.</p>
                <a href="/abonnement" className="inline-block bg-amber-500 text-white text-xs font-semibold px-4 py-2 rounded-xl hover:bg-amber-600 transition-colors">Passer Premium</a>
              </div>
            )}

            {/* Chiots de la portée — visible dès que l'annonce est de type portée */}
            {(stats.annonce?.type_vente === 'portee' || stats.portee.length > 0) && (
              <div className="bg-white rounded-2xl p-4 shadow-sm border border-gray-100">
                <p className="text-sm font-semibold text-[#1F2A2E] mb-3">🐾 Stats par chiot</p>
                {stats.portee.length === 0 ? (
                  <div className="text-center py-5">
                    <p className="text-2xl mb-2">📊</p>
                    <p className="text-sm font-medium text-gray-500">Les stats s'accumulent</p>
                    <p className="text-xs text-gray-400 mt-1">Chaque visite sur un chiot est comptée automatiquement. Revenez après quelques visites !</p>
                  </div>
                ) : (() => {
                  const topVues = stats.portee[0];
                  const topFavoris = [...stats.portee].sort((a, b) => b.favoris - a.favoris)[0];
                  return (<>
                    <div className="grid grid-cols-2 gap-3 mb-3">
                      <div className="bg-amber-50 rounded-xl p-3 text-center">
                        <p className="text-xs text-amber-600 font-semibold mb-1">🏆 Plus consulté</p>
                        <p className="text-lg font-bold text-amber-700" style={{ fontFamily: 'Galey, sans-serif' }}>Chiot #{topVues.index + 1}</p>
                        <p className="text-xs text-amber-500">👁️ {topVues.vues} vues</p>
                      </div>
                      <div className="bg-pink-50 rounded-xl p-3 text-center">
                        <p className="text-xs text-pink-600 font-semibold mb-1">❤️ Plus aimé</p>
                        <p className="text-lg font-bold text-pink-700" style={{ fontFamily: 'Galey, sans-serif' }}>Chiot #{topFavoris.index + 1}</p>
                        <p className="text-xs text-pink-500">❤️ {topFavoris.favoris} favoris</p>
                      </div>
                    </div>
                    {isPremium ? (
                      <div className="space-y-1.5 border-t border-gray-100 pt-3">
                        <p className="text-xs text-gray-400 mb-2">Classement complet</p>
                        {stats.portee.slice(0, 8).map((b, i) => (
                          <div key={b.index} className="flex items-center gap-3">
                            <span className="text-xs font-bold text-gray-300 w-5">#{i + 1}</span>
                            <span className="text-xs text-gray-600 flex-1">Chiot #{b.index + 1}</span>
                            <div className="flex items-center gap-3 text-xs text-gray-400">
                              <span>👁️ {b.vues}</span>
                              <span>❤️ {b.favoris}</span>
                            </div>
                          </div>
                        ))}
                      </div>
                    ) : (
                      <p className="text-xs text-center text-gray-400 border-t border-gray-100 pt-3">
                        👑 <span className="text-amber-600 font-medium">Premium</span> — classement complet + évolution par chiot
                      </p>
                    )}
                  </>);
                })()}
              </div>
            )}

            {/* Origine géographique (Premium) */}
            {isPremium && stats.geo.length > 0 && (
              <div className="bg-white rounded-2xl p-4 shadow-sm border border-gray-100">
                <p className="text-sm font-semibold text-[#1F2A2E] mb-3">📍 Origine des visiteurs</p>
                <div className="space-y-2">
                  {stats.geo.slice(0, 8).map(g => (
                    <div key={g.departement}>
                      <div className="flex justify-between text-xs text-gray-500 mb-1">
                        <span>{g.departement}</span><span>{g.vues} vues</span>
                      </div>
                      <Bar value={g.vues} max={stats.geo[0]?.vues ?? 1} color="bg-[#6E9E57]" />
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
