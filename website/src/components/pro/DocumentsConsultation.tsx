'use client';

// « Documents de la consultation » (lot 5 des documents vétérinaires) : depuis
// la saisie du compte rendu ou le dossier opératoire, ouvrir l'ordonnance, les
// comptes rendus pré / opératoire et les consignes dans une fenêtre, sans
// quitter la page ni perdre la saisie ; liste des documents déjà faits,
// actualisée après chaque enregistrement. Miroir appli :
// lib/widgets/pro/documents_consultation.dart.

import { useState } from 'react';
import LienDocument from '@/components/LienDocument';
import { LIBELLE_STATUT, type OrdonnanceRow } from '@/lib/ordonnance';
import { TITRE_CR_CHIR, type ChirurgieCr } from '@/lib/chirurgie-cr';

const TEAL = '#0C5C6C';
type DocChir = 'preop' | 'operatoire' | 'consignes';
const LIBELLE_DOC: Record<DocChir, string> = { ...TITRE_CR_CHIR, consignes: 'Consignes postopératoires' };

export default function DocumentsConsultation({ ordonnances, interventions, onOrdonnance, onOuvrirOrdonnance, onDocIntervention, onNouvelleIntervention, onTransmettre, peutPreparer }: {
  /** Ordonnances de cette consultation (RDV, ou du jour). */
  ordonnances: OrdonnanceRow[];
  /** Interventions de l'animal proposées (récentes ou à venir). */
  interventions: (ChirurgieCr & { statut?: string | null })[];
  onOrdonnance: () => void;
  onOuvrirOrdonnance: (o: OrdonnanceRow) => void;
  onDocIntervention: (c: ChirurgieCr, doc: DocChir) => void;
  /** Crée l'intervention puis ouvre le document demandé. */
  onNouvelleIntervention: (intitule: string, doc: DocChir) => Promise<void>;
  /** Document d'intervention validé : imprimer / envoyer au propriétaire (avec ou sans compte). */
  onTransmettre?: (doc: DocChir, url: string, action: 'imprimer' | 'email') => void;
  peutPreparer: boolean;
}) {
  const [ouvert, setOuvert] = useState(true);
  const [choix, setChoix] = useState<DocChir | null>(null);
  const [intitule, setIntitule] = useState('');
  const [occupe, setOccupe] = useState(false);

  const docsChir = interventions.flatMap(c => (['preop', 'operatoire', 'consignes'] as DocChir[])
    .filter(d => c[d]).map(d => ({ c, d, url: d === 'preop' ? c.preop_doc_url : d === 'operatoire' ? c.operatoire_doc_url : c.consignes_doc_url })));
  const nb = ordonnances.length + docsChir.length;
  const bouton = 'px-3 py-1.5 rounded-lg border text-xs font-semibold';

  return (
    <div className="rounded-xl border border-[#0C5C6C]/25 bg-white">
      <button type="button" onClick={() => setOuvert(o => !o)} className="w-full flex items-center justify-between px-3 py-2.5">
        <span className="text-[13px] font-bold" style={{ color: TEAL }}>Documents de la consultation{nb ? ` (${nb})` : ''}</span>
        <span className="text-xs text-gray-400">{ouvert ? 'Masquer' : 'Afficher'}</span>
      </button>
      {ouvert && (
        <div className="px-3 pb-3 space-y-3">
          {peutPreparer && (
            <div className="flex flex-wrap gap-2">
              <button type="button" onClick={onOrdonnance} className={bouton} style={{ borderColor: TEAL, color: TEAL }}>Ordonnance</button>
              {(['preop', 'operatoire', 'consignes'] as DocChir[]).map(d => (
                <button key={d} type="button" onClick={() => setChoix(choix === d ? null : d)}
                  className={bouton} style={choix === d ? { background: TEAL, borderColor: TEAL, color: 'white' } : { borderColor: TEAL, color: TEAL }}>
                  {LIBELLE_DOC[d]}
                </button>
              ))}
            </div>
          )}
          {/* Document d'intervention : choisir l'intervention ou en créer une. */}
          {choix && (
            <div className="rounded-lg bg-[#F4F7F8] p-2.5 space-y-2">
              <p className="text-xs font-semibold text-gray-600">{LIBELLE_DOC[choix]} — pour quelle intervention ?</p>
              {interventions.length > 0 && (
                <div className="flex flex-wrap gap-2">
                  {interventions.map(c => (
                    <button key={c.id} type="button" onClick={() => { onDocIntervention(c, choix); setChoix(null); }}
                      className="px-2.5 py-1 rounded-lg border border-gray-200 bg-white text-xs font-semibold text-[#1E2025]">
                      {c.intitule} · {new Date(`${c.date.slice(0, 10)}T12:00:00`).toLocaleDateString('fr-FR')}
                    </button>
                  ))}
                </div>
              )}
              <div className="flex gap-2">
                <input value={intitule} onChange={e => setIntitule(e.target.value)} placeholder="Nouvelle intervention (ex. stérilisation)"
                  className="flex-1 border border-gray-200 rounded-lg px-2.5 py-1.5 text-xs bg-white" />
                <button type="button" disabled={!intitule.trim() || occupe}
                  onClick={async () => {
                    setOccupe(true);
                    try { await onNouvelleIntervention(intitule.trim(), choix); setIntitule(''); setChoix(null); }
                    catch (e) { alert(`Intervention non créée : ${(e as Error).message}`); }
                    finally { setOccupe(false); }
                  }}
                  className="px-3 py-1.5 rounded-lg text-xs font-semibold text-white disabled:opacity-40" style={{ background: TEAL }}>Créer</button>
              </div>
            </div>
          )}
          {nb === 0 ? (
            <p className="text-xs text-gray-400">Aucun document pour cette consultation.</p>
          ) : (
            <div className="space-y-1.5">
              {ordonnances.map(o => {
                const st = o.statut ?? 'signee';
                return (
                  <div key={o.id} className="flex flex-wrap items-center gap-2 text-xs">
                    <span className="font-semibold text-[#1E2025]">Ordonnance{o.numero ? ` n° ${o.numero}` : ''}</span>
                    <span className={st === 'brouillon' ? 'text-[#8A5A00]' : 'text-gray-500'}>{LIBELLE_STATUT[st]}</span>
                    {st === 'brouillon' && peutPreparer && (
                      <button type="button" onClick={() => onOuvrirOrdonnance(o)} className="font-semibold hover:underline" style={{ color: TEAL }}>Compléter</button>
                    )}
                    {o.doc_url && <LienDocument href={o.doc_url} target="_blank" rel="noopener noreferrer" className="font-semibold hover:underline" style={{ color: TEAL }}>PDF</LienDocument>}
                  </div>
                );
              })}
              {docsChir.map(({ c, d, url }) => (
                <div key={`${c.id}-${d}`} className="flex flex-wrap items-center gap-2 text-xs">
                  <span className="font-semibold text-[#1E2025]">{LIBELLE_DOC[d]} — {c.intitule}</span>
                  <span className={c[d]?.statut === 'valide' ? 'text-gray-500' : 'text-[#8A5A00]'}>{c[d]?.statut === 'valide' ? 'Validé' : 'Brouillon'}</span>
                  {peutPreparer && (
                    <button type="button" onClick={() => onDocIntervention(c, d)} className="font-semibold hover:underline" style={{ color: TEAL }}>Ouvrir</button>
                  )}
                  {url && <LienDocument href={url} target="_blank" rel="noopener noreferrer" className="font-semibold hover:underline" style={{ color: TEAL }}>PDF</LienDocument>}
                  {url && onTransmettre && (
                    <>
                      <button type="button" onClick={() => onTransmettre(d, url, 'imprimer')} className="font-semibold hover:underline" style={{ color: TEAL }}>Imprimer</button>
                      <button type="button" onClick={() => onTransmettre(d, url, 'email')} className="font-semibold hover:underline" style={{ color: TEAL }}>Envoyer</button>
                    </>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
