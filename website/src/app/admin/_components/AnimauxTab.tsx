'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { Badge, ESPECES, TYPE_LABELS, fmtDate, typeBadge, downloadCsv } from './ui';

interface Owner {
  profile_id: string | null; uid: string | null; nom: string;
  profile_type: string | null; role_proprio: string | null; statut: string | null;
  date_debut: string | null; date_fin: string | null;
}
interface Animal {
  id: string; nom: string | null; espece: string | null; race: string | null;
  statut: string | null; photo_url: string | null; created_at: string | null;
  uid_eleveur: string | null; uid_proprietaire: string | null;
  owners: Owner[]; principal: Owner | null; orphelin: boolean; legacy_uid_only: boolean;
}

const STATUTS = ['disponible', 'reserve', 'vendu', 'en_elevage', 'retraite', 'decede', 'cede'];

export default function AnimauxTab({ adminUid }: { adminUid: string }) {
  const [rows, setRows] = useState<Animal[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [espece, setEspece] = useState('');
  const [statut, setStatut] = useState('');
  const [proprioType, setProprioType] = useState('');
  const [orphelin, setOrphelin] = useState(false);
  const [q, setQ] = useState('');
  const [selected, setSelected] = useState<Animal | null>(null);

  useEffect(() => {
    let alive = true;
    const p = new URLSearchParams({ uid: adminUid });
    if (espece) p.set('espece', espece);
    if (statut) p.set('statut', statut);
    if (proprioType) p.set('proprio_type', proprioType);
    if (orphelin) p.set('orphelin', '1');
    if (q.trim()) p.set('q', q.trim());
    fetch(`/api/admin/animaux?${p}`)
      .then(r => r.json())
      .then(json => { if (!alive) return; setRows(json.animaux ?? []); setLoaded(true); })
      .catch(() => { if (alive) setLoaded(true); });
    return () => { alive = false; };
  }, [adminUid, espece, statut, proprioType, orphelin, q]);
  const loading = !loaded;

  const inputCls = 'px-3 py-1.5 rounded-xl border border-gray-200 bg-white text-sm outline-none focus:border-[#A7C79A]';

  return (
    <div className="max-w-6xl mx-auto">
      <div className="flex flex-wrap gap-2 mb-3 items-center">
        <input className={`${inputCls} flex-1 min-w-[200px]`} placeholder="Nom, race, ID animal…"
          value={q} onChange={e => setQ(e.target.value)} />
        <select className={inputCls} value={espece} onChange={e => setEspece(e.target.value)}>
          <option value="">Toutes espèces</option>
          {ESPECES.map(e => <option key={e} value={e}>{e}</option>)}
        </select>
        <select className={inputCls} value={statut} onChange={e => setStatut(e.target.value)}>
          <option value="">Tous statuts</option>
          {STATUTS.map(s => <option key={s} value={s}>{s}</option>)}
        </select>
        <select className={inputCls} value={proprioType} onChange={e => setProprioType(e.target.value)}>
          <option value="">Tout type de proprio</option>
          {Object.entries(TYPE_LABELS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
        <label className="flex items-center gap-1.5 text-sm text-gray-600">
          <input type="checkbox" checked={orphelin} onChange={e => setOrphelin(e.target.checked)} />
          Orphelins
        </label>
        <span className="text-sm text-gray-400 ml-auto">{rows.length} animaux</span>
        <button onClick={() => downloadCsv('animaux.csv', [
          ['ID', 'Nom', 'Espèce', 'Race', 'Statut', 'Créé le', 'Propriétaire principal', 'Type proprio', 'Co-proprios', 'Orphelin'],
          ...rows.map(r => [r.id, r.nom, r.espece, r.race, r.statut, r.created_at,
            r.principal?.nom ?? '', r.principal?.profile_type ?? '',
            r.owners.filter(o => o.role_proprio !== 'principal').map(o => o.nom).join(' / '),
            r.orphelin ? 'oui' : 'non'])])}
          className="text-sm px-3 py-1.5 rounded-xl border border-gray-200 hover:bg-gray-50">⬇ CSV</button>
      </div>

      {loading ? (
        <div className="flex justify-center py-16">
          <div className="w-8 h-8 border-4 border-[#A7C79A] border-t-transparent rounded-full animate-spin" />
        </div>
      ) : (
        <div className="bg-white rounded-2xl border border-gray-100 overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-gray-500 text-xs uppercase">
              <tr>
                <th className="text-left px-4 py-2.5">Animal</th>
                <th className="text-left px-3 py-2.5">Espèce</th>
                <th className="text-left px-3 py-2.5">Statut</th>
                <th className="text-left px-3 py-2.5">Propriétaire principal</th>
                <th className="text-left px-3 py-2.5">Co-propriétaires</th>
                <th className="text-left px-3 py-2.5">Créé</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(r => (
                <tr key={r.id} onClick={() => setSelected(r)}
                  className="border-t border-gray-100 hover:bg-[#F5FAF2] cursor-pointer">
                  <td className="px-4 py-2.5">
                    <div className="flex items-center gap-2">
                      {r.photo_url
                        ? <img src={r.photo_url} alt="" className="w-8 h-8 rounded-lg object-cover flex-shrink-0" />
                        : <div className="w-8 h-8 rounded-lg bg-gray-100 flex items-center justify-center flex-shrink-0">🐾</div>}
                      <div className="min-w-0">
                        <p className="font-medium text-gray-800 truncate">{r.nom ?? 'Sans nom'}</p>
                        {r.race && <p className="text-xs text-gray-400 truncate">{r.race}</p>}
                      </div>
                    </div>
                  </td>
                  <td className="px-3 py-2.5 text-gray-600">{r.espece ?? '—'}</td>
                  <td className="px-3 py-2.5"><Badge label={r.statut ?? '—'} color="#0C5C6C" /></td>
                  <td className="px-3 py-2.5">
                    {r.principal ? (
                      <div className="flex items-center gap-1.5 flex-wrap">
                        <span className="text-gray-700">{r.principal.nom}</span>
                        {typeBadge(r.principal.profile_type)}
                        {r.orphelin && <Badge label={r.legacy_uid_only ? 'legacy uid' : 'orphelin'} color="#dc2626" />}
                      </div>
                    ) : <Badge label="orphelin" color="#dc2626" />}
                  </td>
                  <td className="px-3 py-2.5 text-gray-500 text-xs">
                    {r.owners.filter(o => o.role_proprio !== 'principal' && !o.date_fin).map(o => o.nom).join(', ') || '—'}
                  </td>
                  <td className="px-3 py-2.5 text-gray-400 text-xs">{fmtDate(r.created_at)}</td>
                </tr>
              ))}
              {rows.length === 0 && (
                <tr><td colSpan={6} className="text-center text-gray-400 py-10">Aucun animal.</td></tr>
              )}
            </tbody>
          </table>
        </div>
      )}

      {selected && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4" onClick={() => setSelected(null)}>
          <div className="bg-white rounded-2xl shadow-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
            <div className="bg-[#A7C79A] px-6 py-4 flex items-center gap-3">
              {selected.photo_url
                ? <img src={selected.photo_url} alt="" className="w-14 h-14 rounded-xl object-cover" />
                : <div className="w-14 h-14 rounded-xl bg-white/40 flex items-center justify-center text-2xl">🐾</div>}
              <div className="flex-1">
                <p className="text-lg font-bold text-gray-800">{selected.nom ?? 'Sans nom'}</p>
                <p className="text-xs text-gray-600">{[selected.espece, selected.race].filter(Boolean).join(' · ')}</p>
              </div>
              <button onClick={() => setSelected(null)} className="text-gray-600 text-xl">✕</button>
            </div>
            <div className="p-6 space-y-4">
              <p className="text-xs font-mono text-gray-400 break-all">{selected.id}</p>
              <div className="grid grid-cols-2 gap-3 text-sm">
                <div><span className="text-gray-400 text-xs block">Statut</span>{selected.statut ?? '—'}</div>
                <div><span className="text-gray-400 text-xs block">Créé le</span>{fmtDate(selected.created_at)}</div>
              </div>
              <div>
                <p className="text-sm font-semibold text-[#6E9E57] mb-2">Propriétaires ({selected.owners.length})</p>
                {selected.owners.length === 0 && (
                  <div className="text-sm text-red-600 bg-red-50 rounded-xl p-3">
                    Aucune ligne animaux_proprietes.
                    {selected.legacy_uid_only && <> Rattaché en legacy à <span className="font-mono text-xs">{selected.uid_eleveur ?? selected.uid_proprietaire}</span>.</>}
                  </div>
                )}
                <div className="space-y-2">
                  {selected.owners.map((o, i) => (
                    <div key={i} className="flex items-center gap-2 flex-wrap bg-gray-50 rounded-xl px-3 py-2">
                      <Badge label={o.role_proprio ?? '?'} color={o.role_proprio === 'principal' ? '#6E9E57' : '#64748b'} />
                      <span className="text-sm text-gray-700">{o.nom}</span>
                      {typeBadge(o.profile_type)}
                      {o.statut && <span className="text-xs text-gray-400">{o.statut}</span>}
                      {o.date_fin && <span className="text-xs text-red-400">fin {fmtDate(o.date_fin)}</span>}
                      {o.uid && (
                        <Link href={`/elevages/${o.uid}`} target="_blank"
                          className="ml-auto text-xs text-[#0C5C6C] hover:underline">fiche ↗</Link>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
