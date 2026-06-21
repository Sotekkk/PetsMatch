'use client';

import { useEffect, useState } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import Link from 'next/link';
import { collection, query, orderBy, getDocs, doc, updateDoc, addDoc, getDoc } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { useAuth } from '@/lib/auth-context';
import { usePlan } from '@/lib/use-plan';

interface Ligne {
  description: string;
  quantite: number;
  prixUnitaire: number;
  tva: number;
}

interface Facture {
  id: string;
  numeroFacture?: number;
  nomClient?: string;
  adresseClient?: string;
  tvaClient?: string;
  dateFacture?: string;
  datePrestation?: string;
  dateEcheance?: string;
  statut?: string;
  totalHT?: number;
  totalTVA?: number;
  totalTTC?: number;
  tvaEmetteur?: string;
  lignes?: Ligne[];
  profilSource?: string;
}

const STATUT_STYLE: Record<string, string> = {
  emise: 'bg-amber-100 text-amber-700',
  payee: 'bg-green-100 text-green-700',
  annulee: 'bg-red-100 text-red-600',
};
const STATUT_LABEL: Record<string, string> = { emise: 'Émise', payee: 'Payée', annulee: 'Annulée' };

function today() { return new Date().toLocaleDateString('fr-FR'); }
function addDays(n: number) {
  const d = new Date(); d.setDate(d.getDate() + n);
  return d.toLocaleDateString('fr-FR');
}

export default function FacturationPage() {
  const { user, userData, loading } = useAuth();
  const router = useRouter();
  const pathname = usePathname();
  const profilSource = pathname.startsWith('/association') ? 'association' : 'eleveur';
  const { config: planConfig, loading: planLoading } = usePlan();
  const [factures, setFactures] = useState<Facture[]>([]);
  const [fetching, setFetching] = useState(true);
  const [filtreStatut, setFiltreStatut] = useState('tous');
  const [selected, setSelected] = useState<Facture | null>(null);
  const [showForm, setShowForm] = useState(false);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  useEffect(() => {
    if (!user) return;
    getDocs(query(collection(db, 'users', user.uid, 'factures'), orderBy('numeroFacture', 'desc')))
      .then((snap) => {
        const all = snap.docs.map((d) => ({ id: d.id, ...d.data() }) as Facture);
        const filtered = profilSource === 'association'
          ? all.filter(f => f.profilSource === 'association')
          : all.filter(f => f.profilSource !== 'association');
        setFactures(filtered);
        setFetching(false);
      })
      .catch(() => setFetching(false));
  }, [user]);

  async function handleStatutChange(id: string, statut: string) {
    await updateDoc(doc(db, 'users', user!.uid, 'factures', id), { statut });
    setFactures((prev) => prev.map((f) => f.id === id ? { ...f, statut } : f));
    setSelected((prev) => prev?.id === id ? { ...prev, statut } : prev);
  }

  if (loading || planLoading || !user) return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;

  if (!planConfig.hasPremiumFeatures) {
    return (
      <div className="min-h-[70vh] flex flex-col items-center justify-center gap-4 px-4 text-center">
        <span className="text-5xl">🔒</span>
        <h2 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
          Facturation — Plan Premium requis
        </h2>
        <p className="text-gray-500 text-sm max-w-sm">
          La facturation est disponible avec le plan Premium. Gérez vos factures directement depuis votre espace éleveur.
        </p>
        <a href="/abonnement"
          className="bg-[#D97706] hover:bg-[#B45309] text-white font-semibold px-6 py-3 rounded-xl transition-colors text-sm">
          👑 Voir les plans
        </a>
      </div>
    );
  }

  const filtered = filtreStatut === 'tous' ? factures : factures.filter((f) => (f.statut ?? 'emise') === filtreStatut);
  const totalEmises = factures.filter((f) => f.statut === 'emise').reduce((s, f) => s + (f.totalTTC ?? 0), 0);

  return (
    <div className="max-w-5xl mx-auto px-4 py-10">
      <div className="flex items-center justify-between mb-6">
        <div>
          <Link href="/mes-annonces" className="text-sm text-[#0C5C6C] hover:underline">← Mes annonces</Link>
          <h1 className="text-2xl font-bold text-[#1F2A2E] mt-1">Facturation</h1>
          <p className="text-gray-500 text-sm">
            {factures.length} facture{factures.length !== 1 ? 's' : ''}
            {totalEmises > 0 && ` · ${totalEmises.toFixed(2)} € en attente`}
          </p>
        </div>
        <button onClick={() => setShowForm(true)}
          className="bg-[#6E9E57] hover:bg-[#5A8A45] text-white font-semibold px-5 py-2.5 rounded-xl transition-colors text-sm flex items-center gap-2">
          + Nouvelle facture
        </button>
      </div>

      <div className="flex gap-2 flex-wrap mb-6">
        {[['tous', 'Toutes'], ['emise', 'Émises'], ['payee', 'Payées'], ['annulee', 'Annulées']].map(([val, label]) => (
          <button key={val} onClick={() => setFiltreStatut(val)}
            className={`px-4 py-1.5 rounded-full text-sm font-medium border transition-colors ${
              filtreStatut === val ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-600 border-gray-200'
            }`}>
            {label}
          </button>
        ))}
      </div>

      {fetching ? (
        <div className="flex justify-center py-20 text-gray-400">Chargement…</div>
      ) : filtered.length === 0 ? (
        <div className="text-center py-20 text-gray-400">Aucune facture</div>
      ) : (
        <div className="space-y-3">
          {filtered.map((f) => (
            <div key={f.id} onClick={() => setSelected(f)}
              className="bg-white rounded-2xl border border-gray-100 shadow-sm p-4 hover:shadow-md transition-shadow cursor-pointer flex items-center gap-4">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2 mb-1">
                  <p className="font-bold text-[#1F2A2E] text-sm">Facture n° {f.numeroFacture}</p>
                  <span className={`text-xs font-semibold px-2 py-0.5 rounded-full ${STATUT_STYLE[f.statut ?? 'emise']}`}>
                    {STATUT_LABEL[f.statut ?? 'emise']}
                  </span>
                </div>
                <p className="text-gray-500 text-xs truncate">{f.nomClient}</p>
                <p className="text-gray-400 text-xs">{f.dateFacture}</p>
              </div>
              <p className="font-bold text-[#1F2A2E] text-base flex-shrink-0">
                {(f.totalTTC ?? 0).toFixed(2)} €
              </p>
            </div>
          ))}
        </div>
      )}

      {/* Détail facture */}
      {selected && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4" onClick={() => setSelected(null)}>
          <div className="bg-white rounded-2xl w-full max-w-lg max-h-[90vh] overflow-y-auto p-6" onClick={(e) => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-4">
              <h3 className="font-bold text-[#1F2A2E] text-lg">Facture n° {selected.numeroFacture}</h3>
              <span className={`text-xs font-semibold px-2 py-1 rounded-full ${STATUT_STYLE[selected.statut ?? 'emise']}`}>
                {STATUT_LABEL[selected.statut ?? 'emise']}
              </span>
            </div>

            <div className="space-y-2 mb-4">
              {[
                ['Client', selected.nomClient],
                ['Adresse client', selected.adresseClient],
                ['TVA client', selected.tvaClient],
                ['Date facture', selected.dateFacture],
                ['Date prestation', selected.datePrestation],
                ['Date échéance', selected.dateEcheance],
              ].map(([l, v]) => v ? (
                <div key={l} className="flex gap-3">
                  <span className="text-gray-400 text-sm w-36 flex-shrink-0">{l}</span>
                  <span className="text-gray-700 text-sm">{v}</span>
                </div>
              ) : null)}
            </div>

            {(selected.lignes ?? []).length > 0 && (
              <div className="border border-gray-100 rounded-xl overflow-hidden mb-4">
                <table className="w-full text-xs">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="text-left px-3 py-2 text-gray-500 font-medium">Description</th>
                      <th className="text-right px-3 py-2 text-gray-500 font-medium">Qté</th>
                      <th className="text-right px-3 py-2 text-gray-500 font-medium">P.U.</th>
                      <th className="text-right px-3 py-2 text-gray-500 font-medium">TVA</th>
                    </tr>
                  </thead>
                  <tbody>
                    {(selected.lignes ?? []).map((l, i) => (
                      <tr key={i} className="border-t border-gray-100">
                        <td className="px-3 py-2 text-gray-700">{l.description}</td>
                        <td className="px-3 py-2 text-right text-gray-600">{l.quantite}</td>
                        <td className="px-3 py-2 text-right text-gray-600">{l.prixUnitaire?.toFixed(2)} €</td>
                        <td className="px-3 py-2 text-right text-gray-600">{l.tva}%</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
                <div className="bg-gray-50 px-3 py-2 space-y-1">
                  <div className="flex justify-between text-xs text-gray-500"><span>Total HT</span><span>{(selected.totalHT ?? 0).toFixed(2)} €</span></div>
                  <div className="flex justify-between text-xs text-gray-500"><span>TVA</span><span>{(selected.totalTVA ?? 0).toFixed(2)} €</span></div>
                  <div className="flex justify-between text-sm font-bold text-[#1F2A2E]"><span>Total TTC</span><span>{(selected.totalTTC ?? 0).toFixed(2)} €</span></div>
                </div>
              </div>
            )}

            {selected.statut === 'emise' && (
              <div className="flex gap-2 mb-3">
                <button onClick={() => handleStatutChange(selected.id, 'payee')}
                  className="flex-1 bg-[#6E9E57] hover:bg-[#5A8A45] text-white font-semibold py-2 rounded-xl text-sm transition-colors">
                  Marquer payée
                </button>
                <button onClick={() => handleStatutChange(selected.id, 'annulee')}
                  className="flex-1 border border-red-200 hover:bg-red-50 text-red-500 font-medium py-2 rounded-xl text-sm transition-colors">
                  Annuler
                </button>
              </div>
            )}
            <button onClick={() => setSelected(null)}
              className="w-full border border-gray-200 text-gray-600 font-medium py-2.5 rounded-xl text-sm hover:bg-gray-50 transition-colors">
              Fermer
            </button>
          </div>
        </div>
      )}

      {showForm && (
        <NouvelleFactureForm uid={user.uid} userData={userData} nextNum={(factures[0]?.numeroFacture ?? 0) + 1}
          profilSource={profilSource}
          onClose={() => setShowForm(false)}
          onSaved={(f) => { setFactures((prev) => [f, ...prev]); setShowForm(false); }} />
      )}
    </div>
  );
}

function NouvelleFactureForm({ uid, userData, nextNum, profilSource = 'eleveur', onClose, onSaved }: {
  uid: string; userData: unknown; nextNum: number; profilSource?: string;
  onClose: () => void; onSaved: (f: Facture) => void;
}) {
  const [nomClient, setNomClient] = useState('');
  const [adresseClient, setAdresseClient] = useState('');
  const [tvaClient, setTvaClient] = useState('');
  const [dateFacture, setDateFacture] = useState(today());
  const [datePrestation, setDatePrestation] = useState(today());
  const [dateEcheance, setDateEcheance] = useState(addDays(30));
  const [lignes, setLignes] = useState<Ligne[]>([{ description: '', quantite: 1, prixUnitaire: 0, tva: 20 }]);
  const [saving, setSaving] = useState(false);

  function addLigne() { setLignes((prev) => [...prev, { description: '', quantite: 1, prixUnitaire: 0, tva: 20 }]); }
  function removeLigne(i: number) { setLignes((prev) => prev.filter((_, idx) => idx !== i)); }
  function updateLigne(i: number, field: keyof Ligne, value: string) {
    setLignes((prev) => prev.map((l, idx) => idx === i ? { ...l, [field]: field === 'description' ? value : Number(value) } : l));
  }

  const totalHT = lignes.reduce((s, l) => s + l.quantite * l.prixUnitaire, 0);
  const totalTVA = lignes.reduce((s, l) => s + l.quantite * l.prixUnitaire * l.tva / 100, 0);
  const totalTTC = totalHT + totalTVA;

  async function handleSave(e: React.FormEvent) {
    e.preventDefault();
    setSaving(true);
    const data = {
      numeroFacture: nextNum, nomClient, adresseClient, tvaClient,
      dateFacture, datePrestation, dateEcheance,
      statut: 'emise', lignes, totalHT, totalTVA, totalTTC,
      createdAt: new Date().toISOString(),
      profilSource,
    };
    const ref = await addDoc(collection(db, 'users', uid, 'factures'), data);
    onSaved({ id: ref.id, ...data });
  }

  const inputCls = "w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white";

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl w-full max-w-2xl max-h-[90vh] overflow-y-auto p-6" onClick={(e) => e.stopPropagation()}>
        <h3 className="font-bold text-[#1F2A2E] text-lg mb-4">Facture n° {nextNum}</h3>
        <form onSubmit={handleSave} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Client *</label>
            <input value={nomClient} onChange={(e) => setNomClient(e.target.value)} required placeholder="Nom du client" className={inputCls} />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">Adresse client</label>
            <input value={adresseClient} onChange={(e) => setAdresseClient(e.target.value)} className={inputCls} />
          </div>
          <div className="flex gap-3">
            <div className="flex-1">
              <label className="block text-sm font-medium text-gray-700 mb-1">Date facture</label>
              <input value={dateFacture} onChange={(e) => setDateFacture(e.target.value)} className={inputCls} />
            </div>
            <div className="flex-1">
              <label className="block text-sm font-medium text-gray-700 mb-1">Date prestation</label>
              <input value={datePrestation} onChange={(e) => setDatePrestation(e.target.value)} className={inputCls} />
            </div>
            <div className="flex-1">
              <label className="block text-sm font-medium text-gray-700 mb-1">Échéance</label>
              <input value={dateEcheance} onChange={(e) => setDateEcheance(e.target.value)} className={inputCls} />
            </div>
          </div>

          <div>
            <div className="flex items-center justify-between mb-2">
              <label className="text-sm font-semibold text-gray-700">Lignes</label>
              <button type="button" onClick={addLigne} className="text-sm text-[#0C5C6C] font-medium hover:underline">+ Ajouter</button>
            </div>
            <div className="space-y-2">
              {lignes.map((l, i) => (
                <div key={i} className="grid grid-cols-12 gap-2 items-center">
                  <input value={l.description} onChange={(e) => updateLigne(i, 'description', e.target.value)}
                    placeholder="Description" className={`col-span-5 ${inputCls}`} />
                  <input type="number" min="0" step="0.01" value={l.quantite} onChange={(e) => updateLigne(i, 'quantite', e.target.value)}
                    className={`col-span-2 ${inputCls}`} placeholder="Qté" />
                  <input type="number" min="0" step="0.01" value={l.prixUnitaire} onChange={(e) => updateLigne(i, 'prixUnitaire', e.target.value)}
                    className={`col-span-2 ${inputCls}`} placeholder="P.U." />
                  <input type="number" min="0" max="100" value={l.tva} onChange={(e) => updateLigne(i, 'tva', e.target.value)}
                    className={`col-span-2 ${inputCls}`} placeholder="TVA%" />
                  <button type="button" onClick={() => removeLigne(i)} className="col-span-1 text-red-400 hover:text-red-600 text-lg">×</button>
                </div>
              ))}
            </div>
          </div>

          <div className="bg-gray-50 rounded-xl p-3 space-y-1 text-sm">
            <div className="flex justify-between text-gray-500"><span>Total HT</span><span>{totalHT.toFixed(2)} €</span></div>
            <div className="flex justify-between text-gray-500"><span>TVA</span><span>{totalTVA.toFixed(2)} €</span></div>
            <div className="flex justify-between font-bold text-[#1F2A2E]"><span>Total TTC</span><span>{totalTTC.toFixed(2)} €</span></div>
          </div>

          <div className="flex gap-3 pt-1">
            <button type="submit" disabled={saving}
              className="flex-1 bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-semibold py-3 rounded-xl transition-colors text-sm">
              {saving ? 'Enregistrement…' : 'Créer la facture'}
            </button>
            <button type="button" onClick={onClose}
              className="flex-1 border border-gray-200 text-gray-600 font-medium py-3 rounded-xl transition-colors text-sm hover:bg-gray-50">
              Annuler
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
