'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { Badge, ESPECES, fmtDate, downloadCsv } from './ui';

interface Annonce {
  id: string; titre: string | null; espece: string | null; race: string | null;
  uid_eleveur: string | null; nom_eleveur: string | null; ville_eleveur: string | null;
  created_at: string | null; expire_at: string | null; photos: string[] | null;
  type: string | null; type_vente: string | null; profil_source: string | null;
  statut: string | null; is_suspect: boolean | null; vues: number | null;
  prix: number | null; boost_until: string | null;
}

const STATUTS = ['disponible', 'en_attente', 'pause', 'suspendu', 'refuse', 'vendu', 'expire'];
const STATUT_COLOR: Record<string, string> = {
  disponible: '#16a34a', en_attente: '#2563eb', pause: '#64748b',
  suspendu: '#ea580c', refuse: '#dc2626', vendu: '#7c3aed', expire: '#a1a1aa',
};

export default function AnnoncesToutesTab({ adminUid }: { adminUid: string }) {
  const [rows, setRows] = useState<Annonce[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(0);
  const [loaded, setLoaded] = useState(false);
  const [f, setF] = useState({ q: '', espece: '', statut: '', typeVente: '', profilSource: '', sort: 'created_at' });
  const [busy, setBusy] = useState<string | null>(null);

  // Tout changement de filtre revient page 0 (setState synchrone en handler).
  const setFilter = (patch: Partial<typeof f>) => { setF(prev => ({ ...prev, ...patch })); setPage(0); };
  const { q, espece, statut, typeVente, profilSource, sort } = f;

  useEffect(() => {
    let alive = true;
    const p = new URLSearchParams({ type: 'toutes', uid: adminUid, page: String(page), sort });
    if (q.trim()) p.set('q', q.trim());
    if (espece) p.set('espece', espece);
    if (statut) p.set('statut', statut);
    if (typeVente) p.set('type_vente', typeVente);
    if (profilSource) p.set('profil_source', profilSource);
    fetch(`/api/admin/annonces?${p}`)
      .then(r => r.json())
      .then(json => { if (!alive) return; setRows(json.annonces ?? []); setTotal(json.total ?? 0); setLoaded(true); })
      .catch(() => { if (alive) setLoaded(true); });
    return () => { alive = false; };
  }, [adminUid, page, sort, q, espece, statut, typeVente, profilSource]);

  const loading = !loaded;

  async function act(id: string, action: 'suspend' | 'restore') {
    setBusy(id);
    try {
      const res = await fetch('/api/admin/annonces', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ uid: adminUid, annonce_id: id, action }),
      });
      if (res.ok) {
        setRows(prev => prev.map(a => a.id === id
          ? { ...a, statut: action === 'suspend' ? 'suspendu' : 'disponible', is_suspect: action === 'restore' ? false : a.is_suspect }
          : a));
      }
    } finally {
      setBusy(null);
    }
  }

  const inputCls = 'px-3 py-1.5 rounded-xl border border-gray-200 bg-white text-sm outline-none focus:border-[#A7C79A]';
  const pages = Math.ceil(total / 60);

  return (
    <div>
      <div className="flex flex-wrap gap-2 mb-3 items-center">
        <input className={`${inputCls} flex-1 min-w-[180px]`} placeholder="Titre, race, éleveur…" value={q} onChange={e => setFilter({ q: e.target.value })} />
        <select className={inputCls} value={espece} onChange={e => setFilter({ espece: e.target.value })}>
          <option value="">Espèce</option>{ESPECES.map(e => <option key={e} value={e}>{e}</option>)}
        </select>
        <select className={inputCls} value={statut} onChange={e => setFilter({ statut: e.target.value })}>
          <option value="">Statut</option>{STATUTS.map(s => <option key={s} value={s}>{s}</option>)}
        </select>
        <select className={inputCls} value={typeVente} onChange={e => setFilter({ typeVente: e.target.value })}>
          <option value="">Type</option>
          <option value="vente">Vente</option><option value="saillie">Saillie</option>
          <option value="adoption">Adoption</option><option value="portee">Portée</option>
        </select>
        <select className={inputCls} value={profilSource} onChange={e => setFilter({ profilSource: e.target.value })}>
          <option value="">Source</option>
          <option value="eleveur">Éleveur</option><option value="particulier">Particulier</option>
          <option value="association">Association</option>
        </select>
        <select className={inputCls} value={sort} onChange={e => setFilter({ sort: e.target.value })}>
          <option value="created_at">Récentes</option><option value="vues">Plus vues</option>
        </select>
        <span className="text-sm text-gray-400 ml-auto">{total} annonces</span>
        <button onClick={() => downloadCsv('annonces.csv', [
          ['ID', 'Titre', 'Espèce', 'Race', 'Statut', 'Type', 'Source', 'Éleveur', 'Ville', 'Vues', 'Prix', 'Créée'],
          ...rows.map(r => [r.id, r.titre, r.espece, r.race, r.statut, r.type_vente, r.profil_source,
            r.nom_eleveur ?? r.uid_eleveur, r.ville_eleveur, r.vues, r.prix, r.created_at])])}
          className="text-sm px-3 py-1.5 rounded-xl border border-gray-200 hover:bg-gray-50">⬇ CSV</button>
      </div>

      {loading ? (
        <div className="flex justify-center py-16"><div className="w-8 h-8 border-4 border-[#A7C79A] border-t-transparent rounded-full animate-spin" /></div>
      ) : (
        <div className="bg-white rounded-2xl border border-gray-100 overflow-hidden">
          <table className="w-full text-sm">
            <thead className="bg-gray-50 text-gray-500 text-xs uppercase">
              <tr>
                <th className="text-left px-4 py-2.5">Annonce</th>
                <th className="text-left px-3 py-2.5">Statut</th>
                <th className="text-left px-3 py-2.5">Source</th>
                <th className="text-left px-3 py-2.5">Éleveur</th>
                <th className="text-right px-3 py-2.5">Vues</th>
                <th className="text-left px-3 py-2.5">Créée</th>
                <th className="px-3 py-2.5"></th>
              </tr>
            </thead>
            <tbody>
              {rows.map(r => (
                <tr key={r.id} className="border-t border-gray-100 hover:bg-[#F5FAF2]">
                  <td className="px-4 py-2.5">
                    <div className="flex items-center gap-2">
                      {r.photos?.[0]
                        ? <img src={r.photos[0]} alt="" className="w-8 h-8 rounded-lg object-cover flex-shrink-0" />
                        : <div className="w-8 h-8 rounded-lg bg-gray-100 flex items-center justify-center flex-shrink-0">📋</div>}
                      <div className="min-w-0">
                        <Link href={`/annonces/${r.id}`} target="_blank" className="font-medium text-gray-800 hover:underline truncate block">
                          {r.titre ?? 'Sans titre'}
                        </Link>
                        <p className="text-xs text-gray-400 truncate">
                          {[r.espece, r.race, r.type_vente].filter(Boolean).join(' · ')}
                          {r.boost_until && new Date(r.boost_until) > new Date() && ' · 🚀 boost'}
                        </p>
                      </div>
                    </div>
                  </td>
                  <td className="px-3 py-2.5">
                    <Badge label={r.statut ?? '—'} color={STATUT_COLOR[r.statut ?? ''] ?? '#64748b'} />
                    {r.is_suspect && <span className="ml-1" title="suspecte">⚠️</span>}
                  </td>
                  <td className="px-3 py-2.5 text-gray-500 text-xs">{r.profil_source ?? '—'}</td>
                  <td className="px-3 py-2.5 text-gray-600 text-xs truncate max-w-[140px]">{r.nom_eleveur ?? r.uid_eleveur ?? '—'}</td>
                  <td className="px-3 py-2.5 text-right text-gray-600 tabular-nums">{r.vues ?? 0}</td>
                  <td className="px-3 py-2.5 text-gray-400 text-xs">{fmtDate(r.created_at)}</td>
                  <td className="px-3 py-2.5 text-right">
                    {r.statut === 'suspendu' || r.statut === 'refuse'
                      ? <button disabled={busy === r.id} onClick={() => act(r.id, 'restore')}
                          className="text-xs px-2.5 py-1 rounded-lg border border-green-300 text-green-700 disabled:opacity-50">Réactiver</button>
                      : <button disabled={busy === r.id} onClick={() => act(r.id, 'suspend')}
                          className="text-xs px-2.5 py-1 rounded-lg border border-orange-300 text-orange-700 disabled:opacity-50">Désactiver</button>}
                  </td>
                </tr>
              ))}
              {rows.length === 0 && <tr><td colSpan={7} className="text-center text-gray-400 py-10">Aucune annonce.</td></tr>}
            </tbody>
          </table>
        </div>
      )}

      {pages > 1 && (
        <div className="flex justify-center gap-2 mt-4 text-sm">
          <button disabled={page === 0} onClick={() => setPage(p => p - 1)}
            className="px-3 py-1.5 rounded-lg border border-gray-200 disabled:opacity-40">‹</button>
          <span className="px-3 py-1.5 text-gray-500">{page + 1} / {pages}</span>
          <button disabled={page + 1 >= pages} onClick={() => setPage(p => p + 1)}
            className="px-3 py-1.5 rounded-lg border border-gray-200 disabled:opacity-40">›</button>
        </div>
      )}
    </div>
  );
}
