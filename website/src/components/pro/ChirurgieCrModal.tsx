'use client';

// Comptes rendus préopératoire et opératoire d'une intervention : saisie
// structurée, contrôles, aperçu PDF, « Enregistrer le brouillon » ou
// « Valider et signer » (vétérinaire ; l'ASV prépare). Un compte rendu validé
// ne se modifie qu'en « Nouvelle version » : la version précédente est
// archivée par le serveur (migration_chirurgies_cr.sql).
// Miroir appli : lib/widgets/pro/chirurgie_cr_page.dart.

import { useEffect, useMemo, useState } from 'react';
import LienDocument from '@/components/LienDocument';
import ConsignesEditeur, { type ActionsConsignes } from '@/components/pro/ConsignesEditeur';
import { CHAMPS_CR_CHIR, TITRE_CR_CHIR, controlerCrChir, prerempli, type ChirurgieCr, type TypeCrChir } from '@/lib/chirurgie-cr';

const TEAL = '#0C5C6C';

type Onglet = TypeCrChir | 'consignes';

export default function ChirurgieCrModal({ chirurgie, typeInitial, poidsFiche, peutValider, apercu, enregistrer, consignes, onOrdonnance, onTransmettre, onPlanifierRdv, onClose }: {
  chirurgie: ChirurgieCr;
  typeInitial: Onglet;
  poidsFiche?: number | string | null;
  peutValider: boolean;
  apercu: (type: TypeCrChir, champs: Record<string, string>) => Promise<Blob>;
  /** valider : statut « valide » + PDF ; sinon brouillon. */
  enregistrer: (type: TypeCrChir, champs: Record<string, string>, valider: boolean) => Promise<void>;
  /** Consignes postopératoires pour le propriétaire (3e onglet). */
  consignes?: ActionsConsignes;
  /** Ordonnance depuis le dossier opératoire (fenêtre au-dessus, saisie conservée). */
  onOrdonnance?: () => void;
  /** RDV de l'intervention (visible par la famille), à la date prévue. */
  onPlanifierRdv?: (datePrevue: string | null, intitule: string) => void;
  /** Document validé : imprimer / envoyer au propriétaire (avec ou sans compte). */
  onTransmettre?: (doc: Onglet, url: string, action: 'imprimer' | 'email' | 'lien') => void;
  onClose: () => void;
}) {
  const [onglet, setOnglet] = useState<Onglet>(typeInitial);
  const type: TypeCrChir = onglet === 'consignes' ? 'operatoire' : onglet;
  const setType = (t: Onglet) => setOnglet(t);
  const [champs, setChamps] = useState<Record<TypeCrChir, Record<string, string>>>(() => ({
    preop: prerempli('preop', chirurgie, poidsFiche), operatoire: prerempli('operatoire', chirurgie, poidsFiche),
  }));
  const [nouvelleVersion, setNouvelleVersion] = useState<Record<Onglet, boolean>>({ preop: false, operatoire: false, consignes: false });
  const [verifie, setVerifie] = useState(false);
  const [pdf, setPdf] = useState<{ blob: Blob; url: string } | null>(null);
  const [occupe, setOccupe] = useState<null | 'apercu' | 'brouillon' | 'valider'>(null);

  useEffect(() => () => { if (pdf) URL.revokeObjectURL(pdf.url); }, [pdf]);

  const doc = chirurgie[onglet];
  const valide = doc?.statut === 'valide';
  const verrouille = valide && !nouvelleVersion[onglet];
  const docUrl = onglet === 'preop' ? chirurgie.preop_doc_url : onglet === 'operatoire' ? chirurgie.operatoire_doc_url : chirurgie.consignes_doc_url;
  const c = champs[type];
  const controle = useMemo(() => controlerCrChir(type, c), [type, c]);
  const maj = (k: string, v: string) => { setChamps(x => ({ ...x, [type]: { ...x[type], [k]: v } })); setVerifie(false); };

  async function action(a: 'apercu' | 'brouillon' | 'valider') {
    setOccupe(a);
    try {
      if (a === 'apercu') { const blob = await apercu(type, c); setPdf({ blob, url: URL.createObjectURL(blob) }); }
      else { await enregistrer(type, c, a === 'valider'); onClose(); }
    } catch (e) { alert(`${a === 'apercu' ? 'Aperçu impossible' : 'Non enregistré'} : ${(e as Error).message}`); }
    finally { setOccupe(null); }
  }

  const champCls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] disabled:bg-gray-50 disabled:text-gray-600';
  const peutConfirmer = peutValider && !controle.bloquants.length && (!controle.avertissements.length || verifie);
  const statutTxt = !doc ? 'Non rédigé' : valide
    ? `Validé${doc.valide_le ? ` le ${new Date(String(doc.valide_le)).toLocaleDateString('fr-FR')}` : ''}${(doc.version ?? 1) > 1 ? ` · version ${doc.version}` : ''}`
    : 'Brouillon';

  const boutons = !verrouille && (
    <div className="flex flex-wrap gap-2 justify-end">
      <button onClick={() => action('brouillon')} disabled={!!occupe}
        className="px-4 py-2 rounded-xl border text-sm font-semibold disabled:opacity-50" style={{ borderColor: TEAL, color: TEAL }}>
        {occupe === 'brouillon' ? 'Enregistrement…' : 'Enregistrer le brouillon'}
      </button>
      {peutValider && (
        <button onClick={() => action('valider')} disabled={!!occupe || !peutConfirmer}
          className="px-4 py-2 rounded-xl text-sm font-semibold text-white disabled:opacity-40" style={{ background: TEAL }}>
          {occupe === 'valider' ? 'Validation…' : 'Valider et signer'}
        </button>
      )}
    </div>
  );

  const alertes = !verrouille && (
    <>
      {controle.bloquants.length > 0 && (
        <div className="bg-red-50 border border-red-200 rounded-xl px-3 py-2 text-xs text-red-700">
          <p className="font-semibold mb-1">À compléter avant la validation :</p>
          <ul className="list-disc pl-4">{controle.bloquants.map(m => <li key={m}>{m}</li>)}</ul>
        </div>
      )}
      {controle.avertissements.length > 0 && (
        <div className="bg-[#FFF8EA] border border-[#F3E2BD] rounded-xl px-3 py-2 text-xs text-[#8A5A00]">
          <p className="font-semibold mb-1">À vérifier :</p>
          <ul className="list-disc pl-4">{controle.avertissements.map(m => <li key={m}>{m}</li>)}</ul>
          {peutValider && (
            <label className="flex items-center gap-2 mt-2 font-semibold">
              <input type="checkbox" checked={verifie} onChange={e => setVerifie(e.target.checked)} className="accent-[#8A5A00]" />
              J&apos;ai vérifié ces points
            </label>
          )}
        </div>
      )}
      {!peutValider && <p className="text-xs text-gray-500">Vous préparez ce compte rendu : un vétérinaire le complète, le valide et le signe.</p>}
    </>
  );

  return (
    <div className="fixed inset-0 z-[60] bg-black/40 flex items-end sm:items-center justify-center p-0 sm:p-4" onClick={onClose}>
      <div className="bg-white w-full sm:max-w-3xl max-h-[94vh] overflow-y-auto rounded-t-2xl sm:rounded-2xl p-5 space-y-4" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between gap-3">
          <h2 className="text-lg font-semibold text-[#1F2A2E]" style={{ fontFamily: 'Galey,sans-serif' }}>{chirurgie.intitule}</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-sm">Fermer</button>
        </div>
        <div className="flex gap-2">
          {([...(['preop', 'operatoire'] as const), ...(consignes ? ['consignes' as const] : [])]).map(t => (
            <button key={t} onClick={() => { setType(t); setPdf(null); setVerifie(false); }}
              className={`px-3 py-1.5 rounded-lg text-sm font-semibold border ${onglet === t ? 'text-white' : ''}`}
              style={onglet === t ? { background: TEAL, borderColor: TEAL } : { borderColor: '#E4E7E2', color: TEAL }}>
              {t === 'consignes' ? 'Consignes au propriétaire' : TITRE_CR_CHIR[t]}
            </button>
          ))}
        </div>
        <div className="flex flex-wrap items-center gap-2 text-xs">
          <span className={`font-semibold px-2 py-0.5 rounded ${valide ? 'bg-[#0C5C6C]/10 text-[#0C5C6C]' : doc ? 'bg-[#FFF8EA] text-[#8A5A00]' : 'bg-gray-100 text-gray-500'}`}>{statutTxt}</span>
          {valide && docUrl && (
            <LienDocument href={docUrl} target="_blank" rel="noopener noreferrer" className="font-semibold hover:underline" style={{ color: TEAL }}>Ouvrir le PDF</LienDocument>
          )}
          {valide && docUrl && onTransmettre && (
            <>
              <button onClick={() => onTransmettre(onglet, docUrl, 'imprimer')} className="font-semibold hover:underline" style={{ color: TEAL }}>Imprimer</button>
              <button onClick={() => onTransmettre(onglet, docUrl, 'email')} className="font-semibold hover:underline" style={{ color: TEAL }}>Envoyer au propriétaire</button>
              <button onClick={() => onTransmettre(onglet, docUrl, 'lien')} className="font-semibold hover:underline" style={{ color: TEAL }}>Lien sécurisé</button>
            </>
          )}
          {onOrdonnance && (
            <button onClick={onOrdonnance} className="ml-auto font-semibold hover:underline" style={{ color: TEAL }}>Ordonnance</button>
          )}
          {verrouille && peutValider && (
            <button onClick={() => setNouvelleVersion(v => ({ ...v, [onglet]: true }))} className="font-semibold hover:underline" style={{ color: TEAL }}>
              Nouvelle version
            </button>
          )}
        </div>
        {nouvelleVersion[onglet] && valide && (
          <p className="text-xs bg-[#F4F7F8] border border-gray-200 rounded-xl px-3 py-2 text-gray-700">
            Nouvelle version : la version validée actuelle (et son PDF) est conservée dans l&apos;historique de l&apos;intervention.
          </p>
        )}

        {onglet === 'consignes' && consignes ? (
          <>
            {pdf && (
              <div className="space-y-2">
                <iframe src={pdf.url} title="Aperçu" className="w-full h-[58vh] border border-gray-200 rounded-xl" />
                <button onClick={() => setPdf(null)} className="px-4 py-2 rounded-xl border text-sm font-semibold" style={{ borderColor: TEAL, color: TEAL }}>Retour à la saisie</button>
              </div>
            )}
            {/* Saisie gardée pendant l'aperçu (masquée, pas démontée). */}
            <div className={pdf ? 'hidden' : ''}>
              <ConsignesEditeur key={nouvelleVersion.consignes ? 'v' : 'f'}
                initiales={chirurgie.consignes?.sections?.length ? chirurgie.consignes.sections.map(s => ({ titre: s.titre, texte: s.texte })) : null}
                verrouille={verrouille} peutValider={peutValider} actions={consignes} onTermine={onClose}
                onApercu={blob => setPdf({ blob, url: URL.createObjectURL(blob) })} />
            </div>
          </>
        ) : pdf ? (
          <>
            <iframe src={pdf.url} title="Aperçu" className="w-full h-[58vh] border border-gray-200 rounded-xl" />
            {alertes}
            <div className="flex flex-wrap gap-2 justify-between">
              <button onClick={() => setPdf(null)} disabled={!!occupe}
                className="px-4 py-2 rounded-xl border text-sm font-semibold" style={{ borderColor: TEAL, color: TEAL }}>Modifier</button>
              {boutons}
            </div>
          </>
        ) : (
          <>
            {type === 'preop' && (
              <p className="text-xs text-gray-500">L&apos;évaluation préopératoire ne vaut pas consentement du propriétaire : le PDF le précise.</p>
            )}
            {type === 'preop' && onPlanifierRdv && (
              <button onClick={() => onPlanifierRdv(c.date_prevue || null, c.intervention || chirurgie.intitule)}
                className="text-xs font-semibold px-3 py-1.5 rounded-lg border" style={{ borderColor: TEAL, color: TEAL }}>
                Planifier le RDV de l’intervention (la famille le voit dans son agenda)
              </button>
            )}
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              {CHAMPS_CR_CHIR[type].map(([k, l, long]) => (
                <div key={k} className={long ? 'sm:col-span-2' : ''}>
                  <label className="text-[11px] font-medium text-gray-500 block mb-0.5">{l}</label>
                  {long
                    ? <textarea value={c[k] ?? ''} onChange={e => maj(k, e.target.value)} rows={2} disabled={verrouille} className={`${champCls} resize-y`} />
                    : <input value={c[k] ?? ''} onChange={e => maj(k, e.target.value)} disabled={verrouille} className={champCls}
                        type={k === 'date_prevue' ? 'date' : undefined} inputMode={k === 'poids' ? 'decimal' : undefined} />}
                </div>
              ))}
            </div>
            {alertes}
            <div className="flex flex-wrap gap-2 justify-between">
              <button onClick={() => action('apercu')} disabled={!!occupe}
                className="px-4 py-2 rounded-xl border text-sm font-semibold disabled:opacity-50" style={{ borderColor: TEAL, color: TEAL }}>
                {occupe === 'apercu' ? 'Préparation…' : 'Aperçu'}
              </button>
              {boutons}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
