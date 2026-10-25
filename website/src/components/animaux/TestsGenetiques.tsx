'use client';

// Génétique & tests d'un animal (table tests_genetiques). Particulier : dans
// le carnet de santé ; éleveur : dans le suivi repro. Miroir appli :
// _showTestGenetiqueSheet (fiche particulier) et _GenetiqueSection (onglet
// Repro de la fiche éleveur) — mêmes champs, profil_adn_etabli synchronisé.

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { uploadDocument } from '@/lib/upload-media';
import { GENETIC_TESTS, GENETIC_TEST_CATEGORIES, RESULTAT_LABEL, resultatChipClass } from '@/lib/genetics';
import { dateValide } from '@/lib/controle-dates';
import ChampDate from '@/components/ChampDate';
import HealthSection from '@/components/animaux/HealthSection';

const LIBELLE_CATEGORIE: Record<string, string> = {
  maladie: 'Maladie héréditaire', adn: 'Profil ADN', robe: 'Génétique de la robe',
  aptitude: 'Aptitude / performance', autre: 'Autre',
};
const AUTRE = '__autre__';

interface Test {
  id: string; categorie?: string | null; code?: string | null; nom?: string | null;
  resultat?: string | null; genotype?: string | null; laboratoire?: string | null;
  date_test?: string | null; url?: string | null; lien_resultat?: string | null; notes?: string | null;
}

const cls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30';
const etiquette = 'text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block';

function FormTest({ espece, onCancel, onSaved, animalId, uid, dateNaissance }: {
  espece: string; animalId: string; uid: string; onCancel: () => void; onSaved: (t: Test) => void;
  dateNaissance?: string | null;
}) {
  const naissance = dateNaissance ? dateNaissance.slice(0, 10) : '';
  const presetsPour = (c: string) => (GENETIC_TESTS[espece] ?? []).filter(t => t.categorie === c);
  const [categorie, setCategorie] = useState('maladie');
  const [code, setCode] = useState(presetsPour('maladie')[0]?.code ?? AUTRE);
  const [nom, setNom] = useState(presetsPour('maladie')[0]?.nom ?? '');
  const [resultat, setResultat] = useState('clair');
  const [genotype, setGenotype] = useState('');
  const [labo, setLabo] = useState('');
  const [date, setDate] = useState('');
  const [lien, setLien] = useState('');
  const [notes, setNotes] = useState('');
  const [fichier, setFichier] = useState<File | null>(null);
  const [erreur, setErreur] = useState('');
  const [saving, setSaving] = useState(false);
  const presets = presetsPour(categorie);

  const changerCategorie = (c: string) => {
    setCategorie(c);
    const p = presetsPour(c);
    setCode(p[0]?.code ?? AUTRE);
    setNom(p[0]?.nom ?? '');
    if (c === 'adn') setResultat('etabli');
  };

  async function enregistrer() {
    if (!nom.trim()) { setErreur('Indiquez le nom du test.'); return; }
    if (date && !dateValide(date)) { setErreur('Date du test : date invalide (JJ/MM/AAAA).'); return; }
    if (date && date > new Date().toLocaleDateString('sv-SE')) { setErreur('Date du test : ne peut pas être dans le futur.'); return; }
    if (date && naissance && date < naissance) { setErreur("Date du test : ne peut pas être antérieure à la naissance de l'animal."); return; }
    setSaving(true); setErreur('');
    try {
      let url: string | null = null;
      if (fichier) {
        const ext = fichier.name.split('.').pop() ?? 'pdf';
        url = await uploadDocument(fichier, `documents/${uid}/${Date.now()}_${crypto.randomUUID()}.${ext}`);
      }
      const ligne: Test & Record<string, unknown> = {
        id: `${Date.now()}`, animal_id: animalId, uid, espece, categorie,
        code: code !== AUTRE ? code : null, nom: nom.trim(),
        resultat: categorie === 'robe' ? null : resultat,
        genotype: genotype.trim() || null, laboratoire: labo.trim() || null,
        date_test: date || null, url, notes: notes.trim() || null,
        ...(lien.trim() ? { lien_resultat: lien.trim() } : {}),
        created_at: new Date().toISOString(),
      };
      const { error } = await supabase.from('tests_genetiques').insert(ligne);
      if (error) throw error;
      onSaved(ligne);
    } catch (e) {
      setErreur(`Enregistrement impossible : ${e instanceof Error ? e.message : String(e)}`);
    }
    setSaving(false);
  }

  return (
    <div className="space-y-3">
      <div>
        <label className={etiquette}>Catégorie</label>
        <select value={categorie} onChange={e => changerCategorie(e.target.value)} className={`${cls} bg-white`}>
          {GENETIC_TEST_CATEGORIES.map(c => <option key={c} value={c}>{LIBELLE_CATEGORIE[c] ?? c}</option>)}
        </select>
      </div>
      {presets.length > 0 && (
        <div>
          <label className={etiquette}>Test</label>
          <select value={code} className={`${cls} bg-white`} onChange={e => {
            setCode(e.target.value);
            setNom(e.target.value === AUTRE ? '' : presets.find(t => t.code === e.target.value)?.nom ?? '');
          }}>
            {presets.map(t => <option key={t.code} value={t.code}>{t.nom}{t.races ? ` (${t.races})` : ''}</option>)}
            <option value={AUTRE}>Autre (saisie libre)</option>
          </select>
        </div>
      )}
      {(presets.length === 0 || code === AUTRE) && (
        <div>
          <label className={etiquette}>Nom du test <span className="text-red-400">*</span></label>
          <input value={nom} onChange={e => setNom(e.target.value)} placeholder="Ex : WFFS, MDR1, PKD…" className={cls} />
        </div>
      )}
      {categorie !== 'robe' && (
        <div>
          <label className={etiquette}>Résultat</label>
          <select value={resultat} onChange={e => setResultat(e.target.value)} className={`${cls} bg-white`}>
            {Object.entries(RESULTAT_LABEL).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </div>
      )}
      <div>
        <label className={etiquette}>Génotype / notation labo</label>
        <input value={genotype} onChange={e => setGenotype(e.target.value)} placeholder="N/N, N/WFFS, HD-A/A…" className={cls} />
      </div>
      <div>
        <label className={etiquette}>Laboratoire</label>
        <input value={labo} onChange={e => setLabo(e.target.value)} placeholder="Labéo, Antagene, UC Davis…" className={cls} />
      </div>
      <ChampDate label="Date du test" value={date} onChange={setDate} min={naissance || undefined} max={new Date().toLocaleDateString('sv-SE')} />
      <div>
        <label className={etiquette}>Lien du résultat en ligne</label>
        <input value={lien} onChange={e => setLien(e.target.value)} placeholder="https://… (Embark, Wisdom Panel…)" className={cls} />
      </div>
      <div>
        <label className={etiquette}>Résultat joint (PDF / photo)</label>
        <label className="flex items-center gap-2 px-3 py-2 border border-gray-200 rounded-xl cursor-pointer hover:bg-gray-50 text-sm">
          <span className="flex-1 text-gray-600 truncate">{fichier ? fichier.name : 'Joindre le résultat…'}</span>
          <input type="file" accept=".pdf,image/*" className="hidden" onChange={e => setFichier(e.target.files?.[0] ?? null)} />
        </label>
      </div>
      <div>
        <label className={etiquette}>Notes</label>
        <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} className={cls} />
      </div>
      {erreur && <p className="text-xs text-red-600 bg-red-50 rounded-xl px-3 py-2">{erreur}</p>}
      <div className="flex gap-2 pt-1">
        <button onClick={onCancel} className="flex-1 py-2 rounded-xl border border-gray-200 text-sm text-gray-600 hover:bg-gray-50">Annuler</button>
        <button onClick={enregistrer} disabled={saving}
          className="flex-1 py-2 rounded-xl bg-[#0C5C6C] text-white text-sm font-semibold hover:bg-[#094F5D] disabled:opacity-50">
          {saving ? '…' : 'Enregistrer'}
        </button>
      </div>
    </div>
  );
}

function LigneTest({ t, canWrite, onDelete }: { t: Test; canWrite: boolean; onDelete: () => void }) {
  const [open, setOpen] = useState(false);
  const sous = [t.laboratoire, t.date_test ? new Date(`${t.date_test.slice(0, 10)}T12:00:00`).toLocaleDateString('fr-FR') : '']
    .filter(Boolean).join(' · ');
  return (
    <div className="px-4 py-3">
      <button type="button" onClick={() => setOpen(o => !o)} className="w-full flex items-center gap-2 text-left">
        <span className="flex-1 min-w-0">
          <span className="block text-sm font-medium text-[#1F2A2E] truncate">{t.nom ?? 'Test'}</span>
          {sous && <span className="block text-xs text-gray-500">{sous}</span>}
        </span>
        {(t.resultat || t.genotype) && (
          <span className={`text-xs font-semibold rounded-full px-2 py-0.5 ${resultatChipClass(t.resultat)}`}>
            {t.resultat ? RESULTAT_LABEL[t.resultat] ?? t.resultat : t.genotype}
          </span>
        )}
      </button>
      {open && (
        <div className="mt-2 space-y-1 text-sm text-gray-600">
          {t.categorie && <p><span className="text-gray-400">Catégorie : </span>{LIBELLE_CATEGORIE[t.categorie] ?? t.categorie}</p>}
          {t.genotype && <p><span className="text-gray-400">Génotype : </span>{t.genotype}</p>}
          {t.notes && <p>{t.notes}</p>}
          <div className="flex flex-wrap gap-3 pt-1">
            {t.lien_resultat && <a href={t.lien_resultat} target="_blank" rel="noopener noreferrer" className="text-xs font-semibold text-[#0C5C6C] hover:underline">Résultat en ligne</a>}
            {t.url && <a href={t.url} target="_blank" rel="noopener noreferrer" className="text-xs font-semibold text-[#0C5C6C] hover:underline">Voir le document</a>}
            {canWrite && <button type="button" onClick={onDelete} className="text-xs text-red-500 hover:text-red-700 ml-auto">Supprimer</button>}
          </div>
        </div>
      )}
    </div>
  );
}

/** Rubrique « Génétique & tests » (dans un HealthPanel). */
export default function TestsGenetiques({ animalId, espece, uid, canWrite, dateNaissance }: {
  animalId: string; espece: string; uid: string; canWrite: boolean;
  /** Date de naissance : un test ne peut pas lui être antérieur. */
  dateNaissance?: string | null;
}) {
  const [tests, setTests] = useState<Test[]>([]);
  const [ajout, setAjout] = useState(false);

  useEffect(() => {
    let annule = false;
    supabase.from('tests_genetiques').select('*').eq('animal_id', animalId).order('date_test', { ascending: false })
      .then(({ data }) => { if (!annule) setTests((data ?? []) as Test[]); });
    return () => { annule = true; };
  }, [animalId]);

  // Profil ADN établi : drapeau de la fiche (vitrine reproducteurs, annonces).
  const syncAdn = async (liste: Test[]) => {
    const etabli = liste.some(t => t.categorie === 'adn' && t.resultat === 'etabli');
    await supabase.from('animaux').update({ profil_adn_etabli: etabli }).eq('id', animalId);
  };

  return (
    <HealthSection title="Génétique & tests" color="#7C3AED" count={tests.length}
      onAdd={canWrite ? () => setAjout(a => !a) : undefined} addFormOpen={ajout}
      addForm={<FormTest espece={espece} animalId={animalId} uid={uid} dateNaissance={dateNaissance} onCancel={() => setAjout(false)}
        onSaved={async t => { const liste = [t, ...tests]; setTests(liste); setAjout(false); await syncAdn(liste); }} />}>
      {tests.map(t => (
        <LigneTest key={t.id} t={t} canWrite={canWrite} onDelete={async () => {
          if (!confirm('Supprimer ce test ?')) return;
          const { error } = await supabase.from('tests_genetiques').delete().eq('id', t.id);
          if (error) { alert(`Suppression impossible : ${error.message}`); return; }
          const liste = tests.filter(x => x.id !== t.id);
          setTests(liste);
          await syncAdn(liste);
        }} />
      ))}
      {tests.length === 0 && <p className="p-4 text-sm text-gray-400">Aucun test</p>}
    </HealthSection>
  );
}
