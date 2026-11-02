'use client';

// Éditeur d'ordonnance (contenu structuré, migration_ordonnances_v2.sql) :
// lignes complètes (médicament, présentation, principe actif, posologie, voie,
// durée, quantité, renouvellement, instructions, mentions réglementaires),
// contrôles (bloquants / à vérifier), aperçu du PDF, puis « Modifier »,
// « Enregistrer le brouillon » ou « Valider et signer » (vétérinaire
// seulement — l'ASV prépare). Rien n'est complété automatiquement.
// Miroir appli : lib/widgets/pro/ordonnance_editeur_page.dart.

import { useEffect, useMemo, useState } from 'react';
import { articleDe, completerDepuisArticle, controlerOrdo, ligneVide, nettoyerOrdo, VOIES, type ArticleOrdo, type ContenuOrdo, type LigneOrdo } from '@/lib/ordonnance';

const TEAL = '#0C5C6C';

export default function OrdonnanceEditeur({ titre, contenuInitial, dateInitiale, espece, rectifie, prescripteur, peutValider,
  chargerArticles, apercu, enregistrerBrouillon, valider, onClose }: {
  titre: string;
  contenuInitial: ContenuOrdo;
  /** AAAA-MM-JJ. */
  dateInitiale: string;
  espece?: string | null;
  /** Version rectificative : ordonnance corrigée. */
  rectifie?: { numero?: string | null; date?: string | null } | null;
  /** Vétérinaire connecté (nom porté sur l'ordonnance s'il valide). */
  prescripteur: string;
  peutValider: boolean;
  /** Pharmacie de la clinique : suggestions et informations reprises. */
  chargerArticles?: () => Promise<ArticleOrdo[]>;
  apercu: (c: ContenuOrdo, date: string) => Promise<Blob>;
  enregistrerBrouillon: (c: ContenuOrdo, date: string) => Promise<void>;
  valider: (c: ContenuOrdo, date: string) => Promise<void>;
  onClose: () => void;
}) {
  const [date, setDate] = useState(dateInitiale);
  const [poids, setPoids] = useState(contenuInitial.poids ?? '');
  const [remarques, setRemarques] = useState(contenuInitial.remarques ?? '');
  const [lignes, setLignes] = useState<LigneOrdo[]>(contenuInitial.lignes.length ? contenuInitial.lignes : [ligneVide()]);
  const [pdf, setPdf] = useState<{ blob: Blob; url: string } | null>(null);
  const [verifie, setVerifie] = useState(false);
  const [occupe, setOccupe] = useState<null | 'apercu' | 'brouillon' | 'valider'>(null);

  useEffect(() => () => { if (pdf) URL.revokeObjectURL(pdf.url); }, [pdf]);
  const [articles, setArticles] = useState<ArticleOrdo[]>([]);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { chargerArticles?.().then(setArticles).catch(() => {}); }, []);
  /** Médicament choisi dans la pharmacie : champs vides complétés (dose jamais). */
  const choisirMedicament = (i: number, nom: string) => {
    setLignes(ls => ls.map((l, j) => j !== i ? l : completerDepuisArticle({ ...l, medicament: nom }, articleDe(nom, articles))));
    setVerifie(false);
  };

  const contenu = (): ContenuOrdo => nettoyerOrdo({ lignes, poids, remarques });
  const controle = useMemo(() => controlerOrdo({ lignes, poids, remarques }, espece), [lignes, poids, remarques, espece]);
  const maj = (i: number, k: keyof LigneOrdo, v: string) => { setLignes(ls => ls.map((l, j) => j === i ? { ...l, [k]: v } : l)); setVerifie(false); };

  async function action(type: 'apercu' | 'brouillon' | 'valider') {
    if (type === 'valider' && (controle.bloquants.length || !date)) return;
    setOccupe(type);
    try {
      if (type === 'apercu') {
        const blob = await apercu(contenu(), date);
        setPdf({ blob, url: URL.createObjectURL(blob) });
      } else if (type === 'brouillon') {
        await enregistrerBrouillon(contenu(), date); onClose();
      } else {
        await valider(contenu(), date); onClose();
      }
    } catch (e) {
      alert(`${type === 'apercu' ? 'Aperçu impossible' : 'Non enregistré'} : ${(e as Error).message}`);
    } finally { setOccupe(null); }
  }

  const champ = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]';
  const etiquette = 'text-[11px] font-medium text-gray-500 block mb-0.5';
  const avertir = controle.avertissements.length > 0;
  const peutConfirmer = peutValider && !controle.bloquants.length && !!date && (!avertir || verifie);

  const boutonsFin = (
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

  const alertes = (
    <>
      {controle.bloquants.length > 0 && (
        <div className="bg-red-50 border border-red-200 rounded-xl px-3 py-2 text-xs text-red-700">
          <p className="font-semibold mb-1">À compléter avant la validation :</p>
          <ul className="list-disc pl-4">{controle.bloquants.map(m => <li key={m}>{m}</li>)}</ul>
        </div>
      )}
      {avertir && (
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
      {!peutValider && (
        <p className="text-xs text-gray-500">Vous préparez cette ordonnance : un vétérinaire la complète, la valide et la signe.</p>
      )}
    </>
  );

  return (
    <div className="fixed inset-0 z-[60] bg-black/40 flex items-end sm:items-center justify-center p-0 sm:p-4" onClick={onClose}>
      <div className="bg-white w-full sm:max-w-3xl max-h-[94vh] overflow-y-auto rounded-t-2xl sm:rounded-2xl p-5 space-y-4" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between gap-3">
          <h2 className="text-lg font-semibold text-[#1F2A2E]" style={{ fontFamily: 'Galey,sans-serif' }}>{titre}</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-sm">Fermer</button>
        </div>

        {pdf ? (
          <>
            <iframe src={pdf.url} title="Aperçu de l'ordonnance" className="w-full h-[58vh] border border-gray-200 rounded-xl" />
            {alertes}
            <div className="flex flex-wrap gap-2 justify-between">
              <button onClick={() => setPdf(null)} disabled={!!occupe}
                className="px-4 py-2 rounded-xl border text-sm font-semibold" style={{ borderColor: TEAL, color: TEAL }}>Modifier</button>
              {boutonsFin}
            </div>
          </>
        ) : (
          <>
            {rectifie && (
              <p className="text-xs bg-[#F4F7F8] border border-gray-200 rounded-xl px-3 py-2 text-gray-700">
                Version rectificative de l&apos;ordonnance{rectifie.numero ? ` n° ${rectifie.numero}` : ''}{rectifie.date ? ` du ${new Date(`${rectifie.date.slice(0, 10)}T12:00:00`).toLocaleDateString('fr-FR')}` : ''} :
                à la validation, celle-ci est marquée « Remplacée » et reste consultable.
              </p>
            )}
            {peutValider && (
              <p className="text-xs text-gray-500">Prescripteur : <span className="font-semibold text-gray-700">{prescripteur || '—'}</span> (votre nom et votre signature figurent sur l&apos;ordonnance validée).</p>
            )}
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className={etiquette}>Date de l&apos;ordonnance</label>
                <input type="date" value={date} onChange={e => setDate(e.target.value)} className={champ} />
              </div>
              <div>
                <label className={etiquette}>Poids (kg, facultatif)</label>
                <input value={poids} onChange={e => setPoids(e.target.value)} inputMode="decimal" placeholder="Laisser vide si non pesé" className={champ} />
              </div>
            </div>
            <datalist id="voies-ordonnance">{VOIES.map(v => <option key={v} value={v} />)}</datalist>
            <datalist id="pharmacie-ordonnance">{articles.map(a => <option key={a.nom} value={a.nom} />)}</datalist>
            <div className="space-y-3">
              {lignes.map((l, i) => (
                <div key={i} className="border border-gray-200 rounded-xl p-3 space-y-2">
                  <div className="flex items-center justify-between">
                    <span className="text-xs font-semibold text-gray-600">Médicament {i + 1}</span>
                    {lignes.length > 1 && (
                      <button onClick={() => setLignes(ls => ls.filter((_, j) => j !== i))} className="text-xs text-red-600 hover:underline">Retirer</button>
                    )}
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
                    <div><label className={etiquette}>Médicament *</label><input value={l.medicament} onChange={e => choisirMedicament(i, e.target.value)} list="pharmacie-ordonnance" className={champ} /></div>
                    <div><label className={etiquette}>Présentation et concentration</label><input value={l.presentation} onChange={e => maj(i, 'presentation', e.target.value)} placeholder="ex. comprimé 50 mg" className={champ} /></div>
                    <div className="sm:col-span-2"><label className={etiquette}>Principe actif</label><input value={l.principeActif} onChange={e => maj(i, 'principeActif', e.target.value)} className={champ} /></div>
                    <div className="sm:col-span-2"><label className={etiquette}>Posologie * (dose, prises, fréquence)</label>
                      <textarea value={l.posologie} onChange={e => maj(i, 'posologie', e.target.value)} rows={2} className={`${champ} resize-none`} /></div>
                    <div><label className={etiquette}>Voie d&apos;administration</label><input value={l.voie} onChange={e => maj(i, 'voie', e.target.value)} list="voies-ordonnance" className={champ} /></div>
                    <div><label className={etiquette}>Durée *</label><input value={l.duree} onChange={e => maj(i, 'duree', e.target.value)} placeholder="ex. 7 jours, au long cours" className={champ} /></div>
                    <div><label className={etiquette}>Quantité à délivrer</label><input value={l.quantite} onChange={e => maj(i, 'quantite', e.target.value)} placeholder="ex. 1 boîte de 14" className={champ} /></div>
                    <div><label className={etiquette}>Renouvellement</label><input value={l.renouvellement} onChange={e => maj(i, 'renouvellement', e.target.value)} placeholder="Vide = non renouvelable" className={champ} /></div>
                    <div className="sm:col-span-2"><label className={etiquette}>Instructions particulières</label><input value={l.instructions} onChange={e => maj(i, 'instructions', e.target.value)} placeholder="à jeun, avec le repas…" className={champ} /></div>
                    <div className="sm:col-span-2"><label className={etiquette}>Mentions réglementaires</label><input value={l.mentions} onChange={e => maj(i, 'mentions', e.target.value)} placeholder="temps d'attente, catégorie du médicament…" className={champ} /></div>
                  </div>
                </div>
              ))}
              <button onClick={() => setLignes(ls => [...ls, ligneVide()])} className="text-sm font-semibold hover:underline" style={{ color: TEAL }}>
                Ajouter un médicament
              </button>
            </div>
            <div>
              <label className={etiquette}>Remarques (facultatif)</label>
              <textarea value={remarques} onChange={e => setRemarques(e.target.value)} rows={2} className={`${champ} resize-none`} />
            </div>
            {alertes}
            <div className="flex flex-wrap gap-2 justify-between">
              <button onClick={() => action('apercu')} disabled={!!occupe}
                className="px-4 py-2 rounded-xl border text-sm font-semibold disabled:opacity-50" style={{ borderColor: TEAL, color: TEAL }}>
                {occupe === 'apercu' ? 'Préparation…' : 'Aperçu'}
              </button>
              {boutonsFin}
            </div>
          </>
        )}
      </div>
    </div>
  );
}
