'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

const STATUTS = [
  { key: 'en_soin',   label: 'En soin',     color: 'bg-orange-100 text-orange-700',  dot: 'bg-orange-400' },
  { key: 'disponible',label: 'Disponible',  color: 'bg-green-100 text-green-700',    dot: 'bg-green-500' },
  { key: 'en_fa',     label: 'En FA',       color: 'bg-purple-100 text-purple-700',  dot: 'bg-purple-500' },
  { key: 'adopte',    label: 'Adopté',      color: 'bg-teal-100 text-teal-700',      dot: 'bg-teal-500' },
  { key: 'transfere', label: 'Transféré',   color: 'bg-blue-100 text-blue-700',      dot: 'bg-blue-500' },
];
const STATUT_MAP = Object.fromEntries(STATUTS.map(s => [s.key, s]));

function mondayOf(d: Date) {
  const day = new Date(d);
  day.setDate(d.getDate() - (d.getDay() === 0 ? 6 : d.getDay() - 1));
  day.setHours(0, 0, 0, 0);
  return day;
}

function addDays(d: Date, n: number) {
  const r = new Date(d);
  r.setDate(r.getDate() + n);
  return r;
}

const JOURS = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

export default function ChenilWebPage() {
  const { user } = useAuth();
  const [animaux, setAnimaux] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [weekStart, setWeekStart] = useState(() => mondayOf(new Date()));
  const [activeTab, setActiveTab] = useState<'list' | 'week'>('list');

  useEffect(() => {
    if (!user) return;
    supabase
      .from('animaux')
      .select('id, nom, espece, photo_url, statut, date_entree, date_sortie')
      .eq('uid_eleveur', user.uid)
      .order('nom')
      .then(({ data }) => {
        setAnimaux(data ?? []);
        setLoading(false);
      });
  }, [user]);

  const enChenil = animaux.filter(a => ['present', 'en_soin', 'disponible'].includes(a.statut));

  const handleStatut = async (id: string, statut: string) => {
    await supabase.from('animaux').update({ statut }).eq('id', id);
    setAnimaux(prev => prev.map(a => a.id === id ? { ...a, statut } : a));
  };

  const handleDate = async (id: string, field: 'date_entree' | 'date_sortie', value: string) => {
    await supabase.from('animaux').update({ [field]: value || null }).eq('id', id);
    setAnimaux(prev => prev.map(a => a.id === id ? { ...a, [field]: value } : a));
  };

  const days = Array.from({ length: 7 }, (_, i) => addDays(weekStart, i));
  const today = new Date(); today.setHours(0,0,0,0);

  const isPresent = (a: any, day: Date) => {
    if (!a.date_entree) return false;
    const start = new Date(a.date_entree); start.setHours(0,0,0,0);
    const end = a.date_sortie ? new Date(a.date_sortie) : new Date('2099-12-31');
    end.setHours(0,0,0,0);
    return day >= start && day <= end;
  };

  const fmtDate = (d: string | null) => {
    if (!d) return '—';
    return new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: '2-digit' });
  };

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold font-galey text-teal-800">Chenil / Planning</h1>

      {/* Tabs */}
      <div className="flex gap-2">
        {(['list', 'week'] as const).map(t => (
          <button key={t} onClick={() => setActiveTab(t)}
            className={`px-4 py-2 rounded-full text-sm font-galey font-semibold transition-colors ${
              activeTab === t ? 'bg-teal-700 text-white' : 'bg-white border border-gray-200 text-gray-600 hover:bg-gray-50'}`}>
            {t === 'list' ? '📋 Au chenil' : '📅 Vue semaine'}
          </button>
        ))}
      </div>

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
        </div>
      ) : activeTab === 'list' ? (
        /* ── Liste ── */
        enChenil.length === 0 ? (
          <div className="text-center py-16 text-gray-400">
            <p className="text-4xl mb-3">🏠</p>
            <p className="font-galey">Aucun animal au chenil</p>
          </div>
        ) : (
          <div className="space-y-3">
            {enChenil.map(a => {
              const sc = STATUT_MAP[a.statut];
              return (
                <div key={a.id} className="bg-white rounded-2xl shadow-sm p-4 border border-gray-100">
                  <div className="flex items-center justify-between mb-3">
                    <p className="font-bold font-galey text-gray-900">{a.nom}
                      {a.espece && <span className="text-gray-400 font-normal text-sm ml-2">({a.espece})</span>}
                    </p>
                    <select value={a.statut} onChange={e => handleStatut(a.id, e.target.value)}
                      className={`text-xs font-galey font-semibold px-3 py-1 rounded-full border-0 focus:outline-none focus:ring-1 focus:ring-teal-400 cursor-pointer ${sc?.color ?? 'bg-gray-100 text-gray-600'}`}>
                      {STATUTS.map(s => <option key={s.key} value={s.key}>{s.label}</option>)}
                    </select>
                  </div>
                  <div className="flex items-center gap-4">
                    <div>
                      <p className="text-xs text-gray-400 font-galey mb-0.5">Entrée</p>
                      <input type="date" value={a.date_entree ?? ''} onChange={e => handleDate(a.id, 'date_entree', e.target.value)}
                        className="text-sm border border-gray-200 rounded-lg px-2 py-1 font-galey focus:outline-none focus:ring-1 focus:ring-teal-400" />
                    </div>
                    <div>
                      <p className="text-xs text-gray-400 font-galey mb-0.5">Sortie prévue</p>
                      <input type="date" value={a.date_sortie ?? ''} onChange={e => handleDate(a.id, 'date_sortie', e.target.value)}
                        className="text-sm border border-gray-200 rounded-lg px-2 py-1 font-galey focus:outline-none focus:ring-1 focus:ring-teal-400" />
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )
      ) : (
        /* ── Vue semaine ── */
        <div className="bg-white rounded-2xl shadow-sm overflow-hidden border border-gray-100">
          {/* Navigation */}
          <div className="flex items-center justify-between px-4 py-3 bg-teal-50 border-b border-teal-100">
            <button onClick={() => setWeekStart(d => addDays(d, -7))}
              className="text-teal-700 hover:text-teal-900 font-bold text-lg px-2">‹</button>
            <p className="font-bold font-galey text-teal-800 text-sm">
              Semaine du {weekStart.toLocaleDateString('fr-FR', { day: 'numeric', month: 'long' })}
            </p>
            <button onClick={() => setWeekStart(d => addDays(d, 7))}
              className="text-teal-700 hover:text-teal-900 font-bold text-lg px-2">›</button>
          </div>
          {/* En-têtes */}
          <div className="flex border-b border-gray-100">
            <div className="w-24 flex-shrink-0" />
            {days.map((d, i) => {
              const isToday = d.getTime() === today.getTime();
              return (
                <div key={i} className={`flex-1 text-center py-2 text-xs font-galey ${isToday ? 'bg-green-50 text-green-700 font-bold' : 'text-gray-500'}`}>
                  <p>{JOURS[i]}</p>
                  <p className="font-bold">{d.getDate()}</p>
                </div>
              );
            })}
          </div>
          {/* Lignes animaux */}
          {animaux.length === 0 ? (
            <div className="text-center py-8 text-gray-400 font-galey text-sm">Aucun animal</div>
          ) : (
            animaux.map(a => {
              const sc = STATUT_MAP[a.statut];
              return (
                <div key={a.id} className="flex border-b border-gray-50 hover:bg-gray-50/50">
                  <div className="w-24 flex-shrink-0 flex items-center px-3 py-2">
                    <div className="flex items-center gap-1.5 min-w-0">
                      {sc && <div className={`w-2 h-2 rounded-full ${sc.dot} flex-shrink-0`} />}
                      <span className="text-xs font-galey font-semibold text-gray-800 truncate">{a.nom}</span>
                    </div>
                  </div>
                  {days.map((d, i) => {
                    const present = isPresent(a, d);
                    return (
                      <div key={i} className={`flex-1 mx-0.5 my-1.5 rounded ${present ? (sc?.dot ?? 'bg-gray-300') + ' opacity-40' : ''}`} style={{ minHeight: 28 }} />
                    );
                  })}
                </div>
              );
            })
          )}
        </div>
      )}
    </div>
  );
}
