'use client';

import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface Animal {
  id: string;
  nom?: string;
  espece?: string;
  race?: string;
  sexe?: string;
  identification?: string;
  date_naissance?: string;
  photo_url?: string;
  statut?: string;
  date_entree?: string;
  date_sortie?: string;
  provenance_qualite?: string;
  provenance_nom?: string;
  provenance_adresse?: string;
  destinataire_qualite?: string;
  destinataire_nom?: string;
  destinataire_adresse?: string;
  cause_mort?: string;
  importation_ref?: string;
}

const ESPECE_LABELS: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', cheval: 'Cheval', lapin: 'Lapin',
  oiseau: 'Oiseau', nac: 'NAC', ovin: 'Ovin', caprin: 'Caprin', porcin: 'Porc', autre: 'Autre',
};
const STATUT_STYLE: Record<string, string> = {
  present: 'bg-green-100 text-green-700',
  sorti: 'bg-blue-100 text-blue-700',
  decede: 'bg-red-100 text-red-600',
};
const STATUT_LABEL: Record<string, string> = { present: 'Présent', sorti: 'Sorti', decede: 'Décédé' };

const PROV_LABELS: Record<string, string> = {
  naissance: 'Naissance dans l\'élevage', eleveur: 'Éleveur', particulier: 'Particulier',
  refuge: 'Refuge / Association', importation: 'Importation', autre: 'Autre',
};
const DEST_LABELS: Record<string, string> = {
  eleveur: 'Éleveur', particulier: 'Particulier', animalerie: 'Animalerie', refuge: 'Refuge', autre: 'Autre',
};
const MORT_LABELS: Record<string, string> = {
  maladie: 'Maladie', accident: 'Accident', naturelle: 'Mort naturelle', euthanasie: 'Euthanasie', autre: 'Autre',
};

function fmtDate(s?: string) {
  if (!s) return '—';
  const d = new Date(s);
  return isNaN(d.getTime()) ? s : d.toLocaleDateString('fr-FR');
}

export default function RegistreEntreeSortiePage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [fetching, setFetching] = useState(true);
  const [filtreStatut, setFiltreStatut] = useState('tous');
  const [dateDebut, setDateDebut] = useState('');
  const [dateFin, setDateFin] = useState('');
  const [selected, setSelected] = useState<Animal | null>(null);
  const [editing, setEditing] = useState(false);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  async function loadData() {
    if (!user) return;
    try {
      const { data } = await supabase
        .from('animaux')
        .select('id, nom, espece, race, sexe, identification, date_naissance, photo_url, statut, date_entree, date_sortie, provenance_qualite, provenance_nom, provenance_adresse, destinataire_qualite, destinataire_nom, destinataire_adresse, cause_mort, importation_ref')
        .eq('uid_eleveur', user.uid)
        .order('date_entree', { ascending: false });
      setAnimaux((data as Animal[]) ?? []);
    } catch { /* ignore */ } finally {
      setFetching(false);
    }
  }

  useEffect(() => { loadData(); }, [user]); // eslint-disable-line react-hooks/exhaustive-deps

  if (loading || !user) return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;

  const filtered = animaux.filter((a) => {
    if (filtreStatut !== 'tous' && (a.statut ?? 'present') !== filtreStatut) return false;
    if (dateDebut && a.date_entree && a.date_entree < dateDebut) return false;
    if (dateFin && a.date_entree && a.date_entree > dateFin) return false;
    return true;
  });

  function exportCSV() {
    const headers = ['Nom', 'Espèce', 'Race', 'Sexe', 'Identification', 'Né·e le', 'Statut', 'Date d\'entrée', 'Provenance', 'Fournisseur', 'Adresse fournisseur', 'Date de sortie/décès', 'Destinataire', 'Nom destinataire', 'Adresse destinataire', 'Cause décès', 'Réf. importation'];
    const rows = filtered.map(a => [
      a.nom ?? '', ESPECE_LABELS[a.espece ?? ''] ?? a.espece ?? '', a.race ?? '', a.sexe ?? '',
      a.identification ?? '', fmtDate(a.date_naissance),
      STATUT_LABEL[a.statut ?? 'present'] ?? a.statut ?? '',
      fmtDate(a.date_entree),
      PROV_LABELS[a.provenance_qualite ?? ''] ?? a.provenance_qualite ?? '',
      a.provenance_nom ?? '', a.provenance_adresse ?? '',
      fmtDate(a.date_sortie),
      DEST_LABELS[a.destinataire_qualite ?? ''] ?? a.destinataire_qualite ?? '',
      a.destinataire_nom ?? '', a.destinataire_adresse ?? '',
      MORT_LABELS[a.cause_mort ?? ''] ?? a.cause_mort ?? '',
      a.importation_ref ?? '',
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
    <div className="max-w-5xl mx-auto px-4 py-10 print:py-4 print:px-0">
      <div className="mb-6 flex items-center justify-between print:mb-4">
        <div>
          <Link href="/mes-animaux" className="text-sm text-[#0C5C6C] hover:underline print:hidden">← Mes animaux</Link>
          <h1 className="text-2xl font-bold text-[#1F2A2E] mt-1">Registre entrées / sorties</h1>
          <p className="text-gray-500 text-sm">{animaux.length} animal{animaux.length !== 1 ? 'x' : ''}</p>
        </div>
        <div className="flex gap-2 print:hidden">
          <button onClick={exportCSV}
            className="border border-gray-200 hover:border-[#0C5C6C] text-gray-600 hover:text-[#0C5C6C] font-medium px-4 py-2.5 rounded-xl transition-colors text-sm flex items-center gap-1.5">
            📊 Excel / CSV
          </button>
          <button onClick={() => window.print()}
            className="border border-gray-200 hover:border-[#0C5C6C] text-gray-600 hover:text-[#0C5C6C] font-medium px-4 py-2.5 rounded-xl transition-colors text-sm flex items-center gap-1.5">
            🖨️ Imprimer
          </button>
        </div>
      </div>

      <div className="space-y-3 mb-6 print:hidden">
        <div className="flex gap-2 flex-wrap">
          {[['tous', 'Tous'], ['present', 'Présents'], ['sorti', 'Sortis'], ['decede', 'Décédés']].map(([val, label]) => (
            <button key={val} onClick={() => setFiltreStatut(val)}
              className={`px-4 py-1.5 rounded-full text-sm font-medium border transition-colors ${
                filtreStatut === val ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-600 border-gray-200'
              }`}>
              {label}
            </button>
          ))}
        </div>
        {/* Filtre période (date d'entrée) */}
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-sm text-gray-500 font-medium">Période d'entrée :</span>
          <input type="date" value={dateDebut} onChange={(e) => setDateDebut(e.target.value)}
            className="border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white" />
          <span className="text-gray-400 text-sm">→</span>
          <input type="date" value={dateFin} onChange={(e) => setDateFin(e.target.value)}
            className="border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white" />
          {(dateDebut || dateFin) && (
            <button onClick={() => { setDateDebut(''); setDateFin(''); }}
              className="text-xs text-gray-400 hover:text-red-500 transition-colors px-2 py-1 rounded-lg hover:bg-red-50">
              ✕ Effacer
            </button>
          )}
          {(dateDebut || dateFin) && (
            <span className="text-xs text-[#0C5C6C] font-medium bg-[#0C5C6C]/10 px-2 py-1 rounded-lg">
              {filtered.length} résultat{filtered.length !== 1 ? 's' : ''}
            </span>
          )}
        </div>
      </div>

      {fetching ? (
        <div className="flex justify-center py-20 text-gray-400">Chargement…</div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-20 text-gray-400">Aucun animal dans ce registre</div>
      ) : (
        <div className="overflow-x-auto rounded-2xl border border-gray-100 shadow-sm bg-white print:shadow-none print:border print:border-gray-300">
          <table className="w-full text-sm border-collapse">
            <thead>
              <tr className="bg-[#0C5C6C] text-white text-xs">
                <th className="text-left px-4 py-3 font-semibold">Statut</th>
                <th className="text-left px-4 py-3 font-semibold">Nom</th>
                <th className="text-left px-4 py-3 font-semibold hidden sm:table-cell">Espèce / Race</th>
                <th className="text-left px-4 py-3 font-semibold hidden md:table-cell">Identification</th>
                <th className="text-left px-4 py-3 font-semibold">Entrée</th>
                <th className="text-left px-4 py-3 font-semibold hidden sm:table-cell">Provenance</th>
                <th className="text-left px-4 py-3 font-semibold hidden lg:table-cell">Sortie / Décès</th>
                <th className="text-left px-4 py-3 font-semibold hidden lg:table-cell">Destinataire</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-50">
              {filtered.map((a) => {
                const statut = a.statut ?? 'present';
                return (
                  <tr key={a.id} onClick={() => { setSelected(a); setEditing(false); }}
                    className="hover:bg-gray-50 cursor-pointer transition-colors print:hover:bg-transparent print:cursor-auto">
                    <td className="px-4 py-3">
                      <span className={`px-2 py-0.5 rounded-lg text-xs font-semibold ${STATUT_STYLE[statut] ?? 'bg-gray-100 text-gray-600'}`}>
                        {STATUT_LABEL[statut] ?? statut}
                      </span>
                    </td>
                    <td className="px-4 py-3 font-semibold text-[#1F2A2E]">{a.nom ?? '—'}</td>
                    <td className="px-4 py-3 text-gray-500 hidden sm:table-cell">
                      {ESPECE_LABELS[a.espece ?? ''] ?? a.espece ?? '—'}{a.race ? ` · ${a.race}` : ''}
                    </td>
                    <td className="px-4 py-3 text-gray-500 hidden md:table-cell font-mono text-xs">{a.identification ?? '—'}</td>
                    <td className="px-4 py-3 text-gray-500 whitespace-nowrap">{fmtDate(a.date_entree)}</td>
                    <td className="px-4 py-3 text-gray-500 hidden sm:table-cell text-xs">
                      {PROV_LABELS[a.provenance_qualite ?? ''] ?? a.provenance_qualite ?? '—'}
                      {a.provenance_nom ? <><br /><span className="text-gray-400">{a.provenance_nom}</span></> : null}
                    </td>
                    <td className="px-4 py-3 text-gray-500 hidden lg:table-cell whitespace-nowrap">
                      {statut !== 'present' ? fmtDate(a.date_sortie) : '—'}
                      {statut === 'decede' && a.cause_mort ? <><br /><span className="text-xs text-red-400">{MORT_LABELS[a.cause_mort] ?? a.cause_mort}</span></> : null}
                    </td>
                    <td className="px-4 py-3 text-gray-500 hidden lg:table-cell text-xs">
                      {statut === 'sorti' ? (DEST_LABELS[a.destinataire_qualite ?? ''] ?? a.destinataire_qualite ?? '—') : '—'}
                      {statut === 'sorti' && a.destinataire_nom ? <><br /><span className="text-gray-400">{a.destinataire_nom}</span></> : null}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* Détail / édition */}
      {selected && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4" onClick={() => { setSelected(null); setEditing(false); }}>
          <div className="bg-white rounded-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto" onClick={(e) => e.stopPropagation()}>
            {editing ? (
              <EditRegistreForm animal={selected} uid={user.uid} onClose={() => setEditing(false)}
                onSaved={(updated) => {
                  setAnimaux((prev) => prev.map((a) => a.id === updated.id ? updated : a));
                  setSelected(updated);
                  setEditing(false);
                }} />
            ) : (
              <div className="p-6 space-y-3">
                <div className="flex items-center justify-between">
                  <h3 className="font-bold text-[#1F2A2E] text-lg">{selected.nom}</h3>
                  <span className={`px-2 py-1 rounded-lg text-xs font-semibold ${STATUT_STYLE[selected.statut ?? 'present']}`}>
                    {STATUT_LABEL[selected.statut ?? 'present']}
                  </span>
                </div>
                <p className="text-gray-500 text-sm">{ESPECE_LABELS[selected.espece ?? ''] ?? selected.espece}{selected.race ? ` · ${selected.race}` : ''}</p>
                {[
                  ['Identification', selected.identification],
                  ['Date de naissance', fmtDate(selected.date_naissance)],
                  ['Date d\'entrée', fmtDate(selected.date_entree)],
                  ['Provenance', PROV_LABELS[selected.provenance_qualite ?? ''] ?? selected.provenance_qualite],
                  ['Fournisseur', selected.provenance_nom],
                  ['Adresse fournisseur', selected.provenance_adresse],
                  ...(selected.statut === 'sorti' ? [
                    ['Date de sortie', fmtDate(selected.date_sortie)],
                    ['Destinataire', DEST_LABELS[selected.destinataire_qualite ?? ''] ?? selected.destinataire_qualite],
                    ['Nom destinataire', selected.destinataire_nom],
                    ['Adresse destinataire', selected.destinataire_adresse],
                  ] : []),
                  ...(selected.statut === 'decede' ? [
                    ['Date de décès', fmtDate(selected.date_sortie)],
                    ['Cause', MORT_LABELS[selected.cause_mort ?? ''] ?? selected.cause_mort],
                  ] : []),
                ].map(([label, val]) => val ? (
                  <div key={label} className="flex gap-3">
                    <span className="text-gray-400 text-sm w-40 flex-shrink-0">{label}</span>
                    <span className="text-gray-700 text-sm">{val}</span>
                  </div>
                ) : null)}
                <div className="flex gap-3 pt-2">
                  <button onClick={() => setEditing(true)}
                    className="flex-1 bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold py-2.5 rounded-xl text-sm transition-colors">
                    Modifier
                  </button>
                  <button onClick={() => { setSelected(null); setEditing(false); }}
                    className="flex-1 border border-gray-200 text-gray-600 font-medium py-2.5 rounded-xl text-sm hover:bg-gray-50 transition-colors">
                    Fermer
                  </button>
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

function EditRegistreForm({ animal, uid, onClose, onSaved }: {
  animal: Animal; uid: string;
  onClose: () => void; onSaved: (a: Animal) => void;
}) {
  const [statut, setStatut] = useState(animal.statut ?? 'present');
  const [dateEntree, setDateEntree] = useState(animal.date_entree?.substring(0, 10) ?? '');
  const [provQualite, setProvQualite] = useState(animal.provenance_qualite ?? '');
  const [provNom, setProvNom] = useState(animal.provenance_nom ?? '');
  const [provAdresse, setProvAdresse] = useState(animal.provenance_adresse ?? '');
  const [importRef, setImportRef] = useState(animal.importation_ref ?? '');
  const [dateSortie, setDateSortie] = useState(animal.date_sortie?.substring(0, 10) ?? '');
  const [destQualite, setDestQualite] = useState(animal.destinataire_qualite ?? '');
  const [destNom, setDestNom] = useState(animal.destinataire_nom ?? '');
  const [destAdresse, setDestAdresse] = useState(animal.destinataire_adresse ?? '');
  const [causeMort, setCauseMort] = useState(animal.cause_mort ?? '');
  const [saving, setSaving] = useState(false);

  async function handleSave(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    const payload = {
      statut, date_entree: dateEntree || undefined,
      provenance_qualite: provQualite, provenance_nom: provNom, provenance_adresse: provAdresse,
      importation_ref: importRef,
      date_sortie: dateSortie || undefined,
      destinataire_qualite: statut === 'sorti' ? destQualite : '',
      destinataire_nom: statut === 'sorti' ? destNom : '',
      destinataire_adresse: statut === 'sorti' ? destAdresse : '',
      cause_mort: statut === 'decede' ? causeMort : '',
    };
    await supabase.from('animaux').update({ ...payload, updated_at: new Date().toISOString() }).eq('id', animal.id);
    onSaved({ ...animal, ...payload });
    setSaving(false);
  }

  const inputCls = "w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white";
  const labelCls = "block text-sm font-medium text-gray-700 mb-1";

  return (
    <form onSubmit={handleSave} className="p-6 space-y-4">
      <h3 className="font-bold text-[#1F2A2E] text-lg">Registre — {animal.nom}</h3>

      <div>
        <label className={labelCls}>Statut</label>
        <div className="flex gap-2">
          {[['present', 'Présent', 'bg-green-500'], ['sorti', 'Sorti', 'bg-blue-500'], ['decede', 'Décédé', 'bg-red-500']].map(([val, label, bg]) => (
            <button key={val} type="button" onClick={() => setStatut(val)}
              className={`flex-1 py-2 rounded-xl text-sm font-medium transition-colors border-2 ${statut === val ? `${bg} text-white border-transparent` : 'border-gray-200 text-gray-600'}`}>
              {label}
            </button>
          ))}
        </div>
      </div>

      <div>
        <label className={labelCls}>Date d'entrée</label>
        <input type="date" value={dateEntree} onChange={(e) => setDateEntree(e.target.value)} className={inputCls} />
      </div>

      <div>
        <label className={labelCls}>Qualité du fournisseur</label>
        <select value={provQualite} onChange={(e) => setProvQualite(e.target.value)} className={inputCls}>
          <option value="">—</option>
          {Object.entries(PROV_LABELS).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
        </select>
      </div>
      <div>
        <label className={labelCls}>Nom / Élevage fournisseur</label>
        <input value={provNom} onChange={(e) => setProvNom(e.target.value)} className={inputCls} />
      </div>
      <div>
        <label className={labelCls}>Adresse fournisseur</label>
        <input value={provAdresse} onChange={(e) => setProvAdresse(e.target.value)} className={inputCls} />
      </div>
      {provQualite === 'importation' && (
        <div>
          <label className={labelCls}>Référence importation</label>
          <input value={importRef} onChange={(e) => setImportRef(e.target.value)} className={inputCls} />
        </div>
      )}

      {statut !== 'present' && (
        <>
          <div>
            <label className={labelCls}>{statut === 'decede' ? 'Date de décès' : 'Date de sortie'}</label>
            <input type="date" value={dateSortie} onChange={(e) => setDateSortie(e.target.value)} className={inputCls} />
          </div>
          {statut === 'sorti' && (
            <>
              <div>
                <label className={labelCls}>Qualité du destinataire</label>
                <select value={destQualite} onChange={(e) => setDestQualite(e.target.value)} className={inputCls}>
                  <option value="">—</option>
                  {Object.entries(DEST_LABELS).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
                </select>
              </div>
              <div>
                <label className={labelCls}>Nom destinataire</label>
                <input value={destNom} onChange={(e) => setDestNom(e.target.value)} className={inputCls} />
              </div>
              <div>
                <label className={labelCls}>Adresse destinataire</label>
                <input value={destAdresse} onChange={(e) => setDestAdresse(e.target.value)} className={inputCls} />
              </div>
            </>
          )}
          {statut === 'decede' && (
            <div>
              <label className={labelCls}>Cause du décès</label>
              <select value={causeMort} onChange={(e) => setCauseMort(e.target.value)} className={inputCls}>
                <option value="">—</option>
                {Object.entries(MORT_LABELS).map(([v, l]) => <option key={v} value={v}>{l}</option>)}
              </select>
            </div>
          )}
        </>
      )}

      <div className="flex gap-3 pt-1">
        <button type="submit" disabled={saving}
          className="flex-1 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-semibold py-2.5 rounded-xl text-sm transition-colors">
          {saving ? 'Enregistrement…' : 'Enregistrer'}
        </button>
        <button type="button" onClick={onClose}
          className="flex-1 border border-gray-200 text-gray-600 font-medium py-2.5 rounded-xl text-sm hover:bg-gray-50 transition-colors">
          Annuler
        </button>
      </div>
    </form>
  );
}
