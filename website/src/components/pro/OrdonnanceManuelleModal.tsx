'use client';

// Ordonnance saisie par le vétérinaire hors compte rendu : lignes (médicament,
// posologie, remarques) → aperçu du PDF → « Modifier » ou « Valider ». Sert à
// créer une ordonnance (menu « Ordonnance (PDF) ») et à produire le PDF d'une
// ordonnance ajoutée à la main sans document (« Générer le PDF »). Rien n'est
// déduit ni complété automatiquement : la saisie d'origine est seulement
// affichée pour que le vétérinaire la reprenne. Miroir appli :
// lib/widgets/pro/ordonnance_manuelle_sheet.dart.

import { useEffect, useState } from 'react';
import type { LigneOrdonnance } from '@/lib/ordonnance-pdf';

const TEAL = '#0C5C6C';

export interface SaisieOrdonnance { date: string; poids: string; lignes: LigneOrdonnance[] }

interface Ligne { medicament: string; posologie: string; notes: string }
const vide = (): Ligne => ({ medicament: '', posologie: '', notes: '' });

export default function OrdonnanceManuelleModal({ titre, dateInitiale, saisieOrigine, prescripteur, apercu, enregistrer, onClose }: {
  titre: string;
  /** AAAA-MM-JJ. */
  dateInitiale: string;
  /** Notes d'une ordonnance ajoutée à la main, affichées pour être reprises. */
  saisieOrigine?: string | null;
  /** Nom porté sur l'ordonnance (le vétérinaire connecté). */
  prescripteur: string;
  apercu: (s: SaisieOrdonnance) => Promise<Blob>;
  enregistrer: (s: SaisieOrdonnance, pdf: Blob) => Promise<void>;
  onClose: () => void;
}) {
  const [date, setDate] = useState(dateInitiale);
  const [poids, setPoids] = useState('');
  const [lignes, setLignes] = useState<Ligne[]>([vide()]);
  const [manques, setManques] = useState<string[]>([]);
  const [pdf, setPdf] = useState<{ blob: Blob; url: string } | null>(null);
  const [occupe, setOccupe] = useState(false);

  useEffect(() => () => { if (pdf) URL.revokeObjectURL(pdf.url); }, [pdf]);

  const maj = (i: number, k: keyof Ligne, v: string) => setLignes(ls => ls.map((l, j) => j === i ? { ...l, [k]: v } : l));
  const saisie = (): SaisieOrdonnance => ({
    date, poids: poids.trim(),
    lignes: lignes.filter(l => l.medicament.trim() || l.posologie.trim() || l.notes.trim())
      .map(l => ({ medicament: l.medicament.trim(), posologie: l.posologie.trim(), notes: l.notes.trim() || undefined })),
  });

  async function voirApercu() {
    const s = saisie();
    const m: string[] = [];
    if (!date) m.push('Date de l’ordonnance');
    if (!s.lignes.length) m.push('Au moins un médicament');
    s.lignes.forEach((l, i) => {
      if (!l.medicament) m.push(`Ligne ${i + 1} : médicament`);
      if (!l.posologie) m.push(`Ligne ${i + 1} : posologie (dose, fréquence, durée)`);
    });
    setManques(m);
    if (m.length) return;
    setOccupe(true);
    try {
      const blob = await apercu(s);
      setPdf({ blob, url: URL.createObjectURL(blob) });
    } catch (e) { alert(`Aperçu impossible : ${(e as Error).message}`); }
    finally { setOccupe(false); }
  }

  async function valider() {
    if (!pdf) return;
    setOccupe(true);
    try { await enregistrer(saisie(), pdf.blob); onClose(); }
    catch (e) { alert(`Non enregistré : ${(e as Error).message}`); }
    finally { setOccupe(false); }
  }

  const champ = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]';

  return (
    <div className="fixed inset-0 z-50 bg-black/40 flex items-end sm:items-center justify-center p-0 sm:p-4" onClick={onClose}>
      <div className="bg-white w-full sm:max-w-2xl max-h-[92vh] overflow-y-auto rounded-t-2xl sm:rounded-2xl p-5 space-y-4" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold text-[#1F2A2E]" style={{ fontFamily: 'Galey,sans-serif' }}>{titre}</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-sm">Fermer</button>
        </div>

        {pdf ? (
          <>
            <iframe src={pdf.url} title="Aperçu de l'ordonnance" className="w-full h-[60vh] border border-gray-200 rounded-xl" />
            <div className="flex gap-2 justify-end">
              <button onClick={() => setPdf(null)} disabled={occupe}
                className="px-4 py-2 rounded-xl border text-sm font-semibold" style={{ borderColor: TEAL, color: TEAL }}>Modifier</button>
              <button onClick={valider} disabled={occupe}
                className="px-4 py-2 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: TEAL }}>
                {occupe ? 'Enregistrement…' : 'Valider'}
              </button>
            </div>
          </>
        ) : (
          <>
            <p className="text-xs text-gray-500">Prescripteur : <span className="font-semibold text-gray-700">{prescripteur || '—'}</span> (votre nom et votre signature figurent sur l&apos;ordonnance).</p>
            {saisieOrigine?.trim() && (
              <div className="bg-[#F4F7F8] border border-gray-200 rounded-xl px-3 py-2">
                <p className="text-xs font-semibold text-gray-600 mb-1">Saisie d&apos;origine (à reprendre dans les lignes ci-dessous)</p>
                <p className="text-sm text-gray-700 whitespace-pre-wrap">{saisieOrigine}</p>
              </div>
            )}
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Date de l&apos;ordonnance</label>
                <input type="date" value={date} onChange={e => setDate(e.target.value)} className={champ} />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Poids (kg, facultatif)</label>
                <input value={poids} onChange={e => setPoids(e.target.value)} inputMode="decimal" placeholder="Laisser vide si non pesé" className={champ} />
              </div>
            </div>
            <div className="space-y-3">
              {lignes.map((l, i) => (
                <div key={i} className="border border-gray-200 rounded-xl p-3 space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-gray-600">Ligne {i + 1}</span>
                    {lignes.length > 1 && (
                      <button onClick={() => setLignes(ls => ls.filter((_, j) => j !== i))} className="text-xs text-red-600 hover:underline">Retirer</button>
                    )}
                  </div>
                  <input value={l.medicament} onChange={e => maj(i, 'medicament', e.target.value)} placeholder="Médicament" className={champ} />
                  <textarea value={l.posologie} onChange={e => maj(i, 'posologie', e.target.value)} rows={2}
                    placeholder="Posologie : dose, nombre de prises, fréquence, durée" className={`${champ} resize-none`} />
                  <input value={l.notes} onChange={e => maj(i, 'notes', e.target.value)} placeholder="Remarques (facultatif)" className={champ} />
                </div>
              ))}
              <button onClick={() => setLignes(ls => [...ls, vide()])} className="text-sm font-semibold hover:underline" style={{ color: TEAL }}>
                Ajouter un médicament
              </button>
            </div>
            {manques.length > 0 && (
              <div className="bg-[#FFF8EA] border border-[#F3E2BD] rounded-xl px-3 py-2 text-xs text-[#8A5A00]">
                <p className="font-semibold mb-1">À compléter avant l&apos;aperçu :</p>
                <ul className="list-disc pl-4">{manques.map(m => <li key={m}>{m}</li>)}</ul>
              </div>
            )}
            <div className="flex justify-end">
              <button onClick={voirApercu} disabled={occupe}
                className="px-4 py-2 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: TEAL }}>
                {occupe ? 'Préparation…' : 'Aperçu'}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
