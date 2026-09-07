'use client';

import React, { useEffect, useMemo, useState } from 'react';
import { Badge, fmtDate, typeBadge, downloadCsv } from './ui';

interface UidStat {
  uid: string; email: string | null; inscrit_le: string | null; derniere_activite: string | null;
  types: string[]; plan_principal: string | null; premium: boolean;
  abos_actifs: { profil_type: string; plan_code: string; periodicite: string; manuel: boolean; date_fin: string | null }[];
  animaux: number; annonces_total: number; annonces_actives: number; annonces_vues: number;
  boosts_actifs: number; photos_estimees: number; messages: number; conversations: number;
  posts: number; rdv: number; balade_parcours: number; balade_termines: number; balade_km: number;
}
interface ProfStat {
  profile_id: string; uid: string; profile_type: string | null; is_main: boolean; nom: string;
  plan_code: string | null; is_premium: boolean;
  animaux: number; annonces_total: number; annonces_actives: number; annonces_vues: number;
  boosts_actifs: number; messages: number; posts: number; rdv: number;
  balade_parcours: number; balade_termines: number; balade_points: number; balade_km: number;
}

type SortKey = 'annonces_vues' | 'animaux' | 'annonces_total' | 'photos_estimees' | 'messages' | 'balade_km' | 'derniere_activite';

export default function ConsommationTab({ adminUid }: { adminUid: string }) {
  const [byUid, setByUid] = useState<UidStat[]>([]);
  const [byProfile, setByProfile] = useState<ProfStat[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [q, setQ] = useState('');
  const [sortKey, setSortKey] = useState<SortKey>('annonces_vues');
  const [expanded, setExpanded] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    fetch(`/api/admin/stats?uid=${adminUid}`)
      .then(r => r.json())
      .then(json => { if (!alive) return; setByUid(json.by_uid ?? []); setByProfile(json.by_profile ?? []); setLoaded(true); })
      .catch(() => { if (alive) setLoaded(true); });
    return () => { alive = false; };
  }, [adminUid]);
  const loading = !loaded;

  const profByUid = useMemo(() => {
    const m = new Map<string, ProfStat[]>();
    for (const p of byProfile) {
      if (!m.has(p.uid)) m.set(p.uid, []);
      m.get(p.uid)!.push(p);
    }
    return m;
  }, [byProfile]);

  const rows = useMemo(() => {
    let r = [...byUid];
    if (q.trim()) {
      const s = q.trim().toLowerCase();
      r = r.filter(x => (x.email ?? '').toLowerCase().includes(s) || x.uid.toLowerCase().includes(s)
        || (x.types ?? []).some(t => t.includes(s)));
    }
    r.sort((a, b) => {
      if (sortKey === 'derniere_activite') {
        return new Date(b.derniere_activite ?? 0).getTime() - new Date(a.derniere_activite ?? 0).getTime();
      }
      return (b[sortKey] as number) - (a[sortKey] as number);
    });
    return r;
  }, [byUid, q, sortKey]);

  const tops = useMemo(() => ({
    media: [...byUid].sort((a, b) => b.photos_estimees - a.photos_estimees)[0],
    annonces: [...byUid].sort((a, b) => b.annonces_total - a.annonces_total)[0],
    vues: [...byUid].sort((a, b) => b.annonces_vues - a.annonces_vues)[0],
    km: [...byUid].sort((a, b) => b.balade_km - a.balade_km)[0],
  }), [byUid]);

  const inputCls = 'px-3 py-1.5 rounded-xl border border-gray-200 bg-white text-sm outline-none focus:border-[#A7C79A]';

  return (
    <div className="max-w-6xl mx-auto">
      {loading ? (
        <div className="flex justify-center py-16"><div className="w-8 h-8 border-4 border-[#A7C79A] border-t-transparent rounded-full animate-spin" /></div>
      ) : (
        <>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-3 mb-4">
            {[
              { l: 'Top médias', s: tops.media, v: (x: UidStat) => `${x.photos_estimees} photos` },
              { l: 'Top annonces', s: tops.annonces, v: (x: UidStat) => `${x.annonces_total}` },
              { l: 'Top vues', s: tops.vues, v: (x: UidStat) => `${x.annonces_vues}` },
              { l: 'Top km balades', s: tops.km, v: (x: UidStat) => `${x.balade_km} km` },
            ].map(c => (
              <div key={c.l} className="bg-white rounded-2xl border border-gray-100 p-3">
                <p className="text-xs text-gray-400">{c.l}</p>
                <p className="text-lg font-bold text-[#0C5C6C]" style={{ fontFamily: 'Galey, sans-serif' }}>
                  {c.s ? c.v(c.s) : '—'}
                </p>
                <p className="text-xs text-gray-400 truncate">{c.s?.email ?? c.s?.uid ?? ''}</p>
              </div>
            ))}
          </div>

          <div className="flex flex-wrap gap-2 mb-3 items-center">
            <input className={`${inputCls} flex-1 min-w-[200px]`} placeholder="email, uid, type…" value={q} onChange={e => setQ(e.target.value)} />
            <select className={inputCls} value={sortKey} onChange={e => setSortKey(e.target.value as SortKey)}>
              <option value="annonces_vues">Trier : vues</option>
              <option value="animaux">Trier : animaux</option>
              <option value="annonces_total">Trier : annonces</option>
              <option value="photos_estimees">Trier : photos</option>
              <option value="messages">Trier : messages</option>
              <option value="balade_km">Trier : km balades</option>
              <option value="derniere_activite">Trier : dernière activité</option>
            </select>
            <span className="text-sm text-gray-400 ml-auto">{rows.length} comptes</span>
            <button onClick={() => downloadCsv('consommation.csv', [
              ['uid', 'email', 'types', 'plan', 'premium', 'abos_actifs', 'plan_fin', 'inscrit', 'derniere_activite', 'animaux',
                'annonces_total', 'annonces_actives', 'vues', 'photos_est', 'messages', 'conversations',
                'posts', 'rdv', 'balade_parcours', 'balade_km', 'boosts'],
              ...rows.map(r => [r.uid, r.email, (r.types ?? []).join('|'), r.plan_principal, r.premium ? 'oui' : 'non',
                (r.abos_actifs ?? []).map(a => `${a.profil_type}:${a.plan_code}/${a.periodicite}${a.manuel ? '(manuel)' : ''}`).join(' | '),
                (r.abos_actifs ?? []).map(a => a.date_fin).filter(Boolean).sort()[0] ?? '',
                r.inscrit_le, r.derniere_activite, r.animaux, r.annonces_total, r.annonces_actives, r.annonces_vues,
                r.photos_estimees, r.messages, r.conversations, r.posts, r.rdv, r.balade_parcours, r.balade_km, r.boosts_actifs])])}
              className="text-sm px-3 py-1.5 rounded-xl border border-gray-200 hover:bg-gray-50">⬇ CSV</button>
          </div>

          <div className="bg-white rounded-2xl border border-gray-100 overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 text-gray-500 text-xs uppercase">
                <tr>
                  <th className="text-left px-4 py-2.5">Compte</th>
                  <th className="text-right px-2 py-2.5">Animaux</th>
                  <th className="text-right px-2 py-2.5">Annonces</th>
                  <th className="text-right px-2 py-2.5">Vues</th>
                  <th className="text-right px-2 py-2.5">Photos~</th>
                  <th className="text-right px-2 py-2.5">Msg</th>
                  <th className="text-right px-2 py-2.5">RDV</th>
                  <th className="text-right px-2 py-2.5">Balades</th>
                  <th className="text-left px-3 py-2.5">Activité</th>
                </tr>
              </thead>
              <tbody>
                {rows.map(r => {
                  const profs = profByUid.get(r.uid) ?? [];
                  const open = expanded === r.uid;
                  return (
                    <React.Fragment key={r.uid}>
                      <tr onClick={() => setExpanded(open ? null : r.uid)}
                        className="border-t border-gray-100 hover:bg-[#F5FAF2] cursor-pointer">
                        <td className="px-4 py-2.5">
                          <div className="flex items-center gap-1.5 flex-wrap">
                            <span className="text-gray-400 text-xs">{profs.length ? (open ? '▾' : '▸') : ''}</span>
                            <span className="text-gray-800 font-medium">{r.email ?? r.uid.slice(0, 10)}</span>
                            {r.premium && <Badge label="★" color="#d97706" />}
                            {(r.types ?? []).map(t => <span key={t}>{typeBadge(t)}</span>)}
                            {r.abos_actifs?.some(a => a.manuel) && <Badge label="abo manuel" color="#7c3aed" />}
                            {(() => {
                              const fins = (r.abos_actifs ?? []).map(a => a.date_fin).filter(Boolean) as string[];
                              if (!fins.length) return null;
                              const soonest = fins.sort()[0];
                              const exp = new Date(soonest) < new Date();
                              return <span className={`text-xs ${exp ? 'text-red-500 font-semibold' : 'text-gray-400'}`}>
                                {exp ? '⚠ expiré ' : 'plan → '}{fmtDate(soonest)}
                              </span>;
                            })()}
                          </div>
                        </td>
                        <td className="px-2 py-2.5 text-right tabular-nums">{r.animaux}</td>
                        <td className="px-2 py-2.5 text-right tabular-nums">{r.annonces_actives}/{r.annonces_total}</td>
                        <td className="px-2 py-2.5 text-right tabular-nums">{r.annonces_vues}</td>
                        <td className="px-2 py-2.5 text-right tabular-nums">{r.photos_estimees}</td>
                        <td className="px-2 py-2.5 text-right tabular-nums">{r.messages}</td>
                        <td className="px-2 py-2.5 text-right tabular-nums">{r.rdv}</td>
                        <td className="px-2 py-2.5 text-right tabular-nums">{r.balade_termines}/{r.balade_parcours}{r.balade_km ? ` · ${r.balade_km}km` : ''}</td>
                        <td className="px-3 py-2.5 text-gray-400 text-xs">{fmtDate(r.derniere_activite)}</td>
                      </tr>
                      {open && profs.map(p => (
                        <tr key={p.profile_id} className="bg-gray-50/60 text-xs text-gray-600">
                          <td className="pl-10 pr-4 py-1.5">
                            <span className="mr-1.5">{typeBadge(p.profile_type)}</span>{p.nom}
                            {p.is_main && <span className="text-gray-400"> · principal</span>}
                            {p.plan_code && p.plan_code !== 'free' && <Badge label={p.plan_code} color="#0C5C6C" />}
                          </td>
                          <td className="px-2 py-1.5 text-right tabular-nums">{p.animaux}</td>
                          <td className="px-2 py-1.5 text-right tabular-nums">{p.annonces_actives}/{p.annonces_total}</td>
                          <td className="px-2 py-1.5 text-right tabular-nums">{p.annonces_vues}</td>
                          <td className="px-2 py-1.5 text-right">—</td>
                          <td className="px-2 py-1.5 text-right tabular-nums">{p.messages}</td>
                          <td className="px-2 py-1.5 text-right tabular-nums">{p.rdv}</td>
                          <td className="px-2 py-1.5 text-right tabular-nums">{p.balade_termines}/{p.balade_parcours}</td>
                          <td className="px-3 py-1.5" />
                        </tr>
                      ))}
                    </React.Fragment>
                  );
                })}
                {rows.length === 0 && <tr><td colSpan={9} className="text-center text-gray-400 py-10">Aucune donnée. La migration admin_consommation_stats est-elle passée ?</td></tr>}
              </tbody>
            </table>
          </div>
        </>
      )}
    </div>
  );
}
