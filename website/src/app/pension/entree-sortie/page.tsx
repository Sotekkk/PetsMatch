'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { usePensionAccess } from '@/hooks/usePensionAccess';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { supabase } from '@/lib/supabase';

interface Entree {
  id: string;
  animal_nom: string;
  espece?: string | null;
  race?: string | null;
  puce?: string | null;
  proprietaire_nom?: string | null;
  proprietaire_contact?: string | null;
  proprietaire_email?: string | null;
  proprietaire_adresse?: string | null;
  date_entree: string;
  date_sortie_prevue?: string | null;
  date_sortie_effective?: string | null;
  statut: 'en_pension' | 'sorti';
}

const ESP_LABEL: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', lapin: 'Lapin', oiseau: 'Oiseau',
  cheval: 'Cheval', nac: 'NAC', ovin: 'Ovin', caprin: 'Caprin', porcin: 'Porc',
};

function fmtDate(s?: string | null) {
  if (!s) return '—';
  const d = new Date(s);
  return isNaN(d.getTime()) ? s : d.toLocaleDateString('fr-FR');
}

function printFiche(e: Entree) {
  const espLabel = ESP_LABEL[e.espece ?? ''] ?? e.espece ?? '—';
  const html = `<!DOCTYPE html><html lang="fr"><head><meta charset="UTF-8"><title>Fiche ${e.animal_nom}</title>
<style>
body{font-family:Arial,sans-serif;font-size:13px;margin:24px;color:#222}
h1{font-size:20px;margin:0 0 2px}
.sub{color:#666;font-size:12px;margin-bottom:20px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:20px}
.box{border:1px solid #ccc;border-radius:8px;padding:14px}
.box h2{font-size:13px;text-transform:uppercase;letter-spacing:.05em;color:#0C5C6C;margin:0 0 10px}
.row{display:flex;justify-content:space-between;padding:5px 0;border-bottom:1px solid #eee;font-size:13px}
.row:last-child{border-bottom:none}
.row span:first-child{color:#666}
.row span:last-child{font-weight:600;text-align:right}
.dates{display:flex;gap:20px;margin-top:20px}
.dates .box{flex:1;text-align:center}
.dates .box .label{color:#666;font-size:11px;text-transform:uppercase;letter-spacing:.05em}
.dates .box .value{font-size:18px;font-weight:700;color:#0C5C6C;margin-top:4px}
.foot{margin-top:28px;font-size:10px;color:#999}
@media print{body{margin:10px}}
</style>
</head><body>
<h1>🐾 ${e.animal_nom}</h1>
<p class="sub">Fiche d'entrée / sortie — pension</p>
<div class="grid">
  <div class="box">
    <h2>Animal</h2>
    <div class="row"><span>Espèce</span><span>${espLabel}</span></div>
    <div class="row"><span>Race</span><span>${e.race || '—'}</span></div>
    <div class="row"><span>Identification</span><span>${e.puce || '—'}</span></div>
  </div>
  <div class="box">
    <h2>Propriétaire</h2>
    <div class="row"><span>Nom</span><span>${e.proprietaire_nom || '—'}</span></div>
    <div class="row"><span>Téléphone</span><span>${e.proprietaire_contact || '—'}</span></div>
    <div class="row"><span>Email</span><span>${e.proprietaire_email || '—'}</span></div>
    <div class="row"><span>Adresse</span><span>${e.proprietaire_adresse || '—'}</span></div>
  </div>
</div>
<div class="dates">
  <div class="box"><div class="label">Date d'entrée</div><div class="value">${fmtDate(e.date_entree)}</div></div>
  <div class="box"><div class="label">${e.statut === 'sorti' ? 'Date de sortie' : 'Sortie prévue'}</div><div class="value">${fmtDate(e.statut === 'sorti' ? e.date_sortie_effective : e.date_sortie_prevue)}</div></div>
</div>
<p class="foot">Imprimé le ${new Date().toLocaleDateString('fr-FR')} • PetsMatch</p>
</body></html>`;
  const win = window.open('', '_blank');
  if (!win) { alert('Autorisez les popups pour imprimer'); return; }
  win.document.write(html);
  win.document.close();
  setTimeout(() => win.print(), 300);
}

export default function PensionEntreeSortiePage() {
  const { user, userData, isPension, loading: authLoading } = usePensionAccess();
  const activeProfileId = useActiveProfile();
  const router = useRouter();
  const [entrees, setEntrees] = useState<Entree[]>([]);
  const [loading, setLoading] = useState(true);
  const [filtreStatut, setFiltreStatut] = useState<'tous' | 'en_pension' | 'sorti'>('tous');
  const [search, setSearch] = useState('');
  const [selected, setSelected] = useState<Entree | null>(null);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isPension) { router.push('/'); return; }
  }, [user, userData, isPension, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    let q = supabase.from('pension_entrees').select('*').eq('pro_uid', user.uid).order('date_entree', { ascending: false });
    if (activeProfileId) q = q.eq('pro_profile_id', activeProfileId) as typeof q;
    const { data } = await q;
    setEntrees((data ?? []) as Entree[]);
    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  if (!user || !userData || loading) {
    return <div className="max-w-5xl mx-auto px-4 py-10 text-center text-gray-400 font-galey">Chargement…</div>;
  }

  const filtered = entrees.filter((e) => {
    if (filtreStatut !== 'tous' && e.statut !== filtreStatut) return false;
    if (search && !`${e.animal_nom} ${e.espece ?? ''} ${e.race ?? ''} ${e.proprietaire_nom ?? ''}`.toLowerCase().includes(search.toLowerCase())) return false;
    return true;
  });

  function exportCSV() {
    const headers = ['Nom', 'Espèce', 'Race', 'Identification', 'Propriétaire', 'Téléphone', 'Email', 'Date entrée', 'Sortie prévue', 'Sortie effective', 'Statut'];
    const rows = filtered.map(e => [
      e.animal_nom, ESP_LABEL[e.espece ?? ''] ?? e.espece ?? '', e.race ?? '', e.puce ?? '',
      e.proprietaire_nom ?? '', e.proprietaire_contact ?? '', e.proprietaire_email ?? '',
      fmtDate(e.date_entree), fmtDate(e.date_sortie_prevue), fmtDate(e.date_sortie_effective),
      e.statut === 'sorti' ? 'Sorti' : 'En pension',
    ]);
    const csv = [headers, ...rows].map(r => r.map(v => `"${String(v).replace(/"/g, '""')}"`).join(';')).join('\n');
    const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const el = document.createElement('a');
    el.href = url;
    el.download = `registre_entree_sortie_${new Date().toISOString().slice(0, 10)}.csv`;
    el.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div className="max-w-5xl mx-auto px-4 py-6 space-y-4">
      <div className="flex items-center justify-between flex-wrap gap-2">
        <div>
          <h1 className="text-2xl font-bold font-galey text-teal-800">Entrée - Sortie</h1>
          <p className="text-gray-500 text-sm font-galey">{filtered.length} animal{filtered.length !== 1 ? 'x' : ''}</p>
        </div>
        <button onClick={exportCSV}
          className="border border-gray-200 hover:border-teal-700 text-gray-600 hover:text-teal-700 font-galey font-medium px-4 py-2 rounded-full transition-colors text-sm">
          📊 Excel / CSV
        </button>
      </div>

      <div className="space-y-3">
        <input value={search} onChange={(e) => setSearch(e.target.value)}
          placeholder="Rechercher par animal, race, propriétaire…"
          className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300" />
        <div className="flex gap-2 flex-wrap">
          {([['tous', 'Tous'], ['en_pension', 'Présents'], ['sorti', 'Sortis']] as const).map(([val, label]) => (
            <button key={val} onClick={() => setFiltreStatut(val)}
              className={`px-4 py-1.5 rounded-full text-sm font-galey font-medium border transition-colors ${
                filtreStatut === val ? 'bg-teal-700 text-white border-teal-700' : 'bg-white text-gray-600 border-gray-200'
              }`}>
              {label}
            </button>
          ))}
        </div>
      </div>

      {filtered.length === 0 ? (
        <div className="text-center py-20 text-gray-400 font-galey">Aucun animal dans ce registre</div>
      ) : (
        <div className="overflow-x-auto rounded-2xl border border-gray-100 shadow-sm bg-white">
          <table className="w-full text-sm border-collapse">
            <thead>
              <tr className="bg-teal-700 text-white text-xs font-galey">
                <th className="text-left px-4 py-3 font-semibold">Statut</th>
                <th className="text-left px-4 py-3 font-semibold">Nom</th>
                <th className="text-left px-4 py-3 font-semibold hidden sm:table-cell">Espèce / Race</th>
                <th className="text-left px-4 py-3 font-semibold hidden md:table-cell">Identification</th>
                <th className="text-left px-4 py-3 font-semibold hidden sm:table-cell">Propriétaire</th>
                <th className="text-left px-4 py-3 font-semibold">Entrée</th>
                <th className="text-left px-4 py-3 font-semibold hidden lg:table-cell">Sortie</th>
                <th className="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-50 font-galey">
              {filtered.map((e) => (
                <tr key={e.id} onClick={() => setSelected(e)} className="hover:bg-gray-50 cursor-pointer transition-colors">
                  <td className="px-4 py-3">
                    <span className={`px-2 py-0.5 rounded-lg text-xs font-semibold ${e.statut === 'sorti' ? 'bg-blue-100 text-blue-700' : 'bg-green-100 text-green-700'}`}>
                      {e.statut === 'sorti' ? 'Sorti' : 'Présent'}
                    </span>
                  </td>
                  <td className="px-4 py-3 font-semibold text-[#1F2A2E]">{e.animal_nom}</td>
                  <td className="px-4 py-3 text-gray-500 hidden sm:table-cell">
                    {ESP_LABEL[e.espece ?? ''] ?? e.espece ?? '—'}{e.race ? ` · ${e.race}` : ''}
                  </td>
                  <td className="px-4 py-3 text-gray-500 hidden md:table-cell font-mono text-xs">{e.puce ?? '—'}</td>
                  <td className="px-4 py-3 text-gray-500 hidden sm:table-cell">{e.proprietaire_nom ?? '—'}</td>
                  <td className="px-4 py-3 text-gray-500 whitespace-nowrap">{fmtDate(e.date_entree)}</td>
                  <td className="px-4 py-3 text-gray-500 hidden lg:table-cell whitespace-nowrap">
                    {fmtDate(e.statut === 'sorti' ? e.date_sortie_effective : e.date_sortie_prevue)}
                  </td>
                  <td className="px-4 py-3 text-right">
                    <button onClick={(ev) => { ev.stopPropagation(); printFiche(e); }}
                      className="text-teal-700 hover:text-teal-900 text-xs font-semibold">🖨️ Fiche</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Détail / fiche individuelle */}
      {selected && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4" onClick={() => setSelected(null)}>
          <div className="bg-white rounded-2xl w-full max-w-lg p-6 space-y-3" onClick={(ev) => ev.stopPropagation()}>
            <div className="flex items-center justify-between">
              <h3 className="font-bold font-galey text-teal-800 text-lg">{selected.animal_nom}</h3>
              <span className={`px-2 py-1 rounded-lg text-xs font-semibold ${selected.statut === 'sorti' ? 'bg-blue-100 text-blue-700' : 'bg-green-100 text-green-700'}`}>
                {selected.statut === 'sorti' ? 'Sorti' : 'Présent'}
              </span>
            </div>
            {[
              ['Espèce', ESP_LABEL[selected.espece ?? ''] ?? selected.espece],
              ['Race', selected.race],
              ['Identification', selected.puce],
              ['Propriétaire', selected.proprietaire_nom],
              ['Téléphone', selected.proprietaire_contact],
              ['Email', selected.proprietaire_email],
              ['Adresse', selected.proprietaire_adresse],
              ['Date d\'entrée', fmtDate(selected.date_entree)],
              [selected.statut === 'sorti' ? 'Date de sortie' : 'Sortie prévue',
                fmtDate(selected.statut === 'sorti' ? selected.date_sortie_effective : selected.date_sortie_prevue)],
            ].map(([label, val]) => val ? (
              <div key={label} className="flex gap-3">
                <span className="text-gray-400 text-sm font-galey w-36 flex-shrink-0">{label}</span>
                <span className="text-gray-700 text-sm font-galey">{val}</span>
              </div>
            ) : null)}
            <div className="flex gap-3 pt-2">
              <button onClick={() => printFiche(selected)}
                className="flex-1 bg-teal-700 hover:bg-teal-800 text-white font-galey font-semibold py-2.5 rounded-xl text-sm transition-colors">
                🖨️ Imprimer la fiche
              </button>
              <button onClick={() => setSelected(null)}
                className="flex-1 border border-gray-200 text-gray-600 font-galey font-medium py-2.5 rounded-xl text-sm hover:bg-gray-50 transition-colors">
                Fermer
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
