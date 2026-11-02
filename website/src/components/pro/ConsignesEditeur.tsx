'use client';

// Consignes postopératoires : sections modifiables (titres, listes, gras),
// ajout / suppression / ordre des sections, modèles (structure fournie ou
// modèles de la clinique), « Enregistrer comme modèle », aperçu PDF,
// brouillon ou « Valider et signer » (vétérinaire). Rien n'est appliqué
// d'office : un modèle ne remplace la saisie qu'après confirmation.
// Miroir appli : lib/widgets/pro/consignes_editeur.dart.

import { useEffect, useMemo, useRef, useState } from 'react';
import { controlerConsignes, MODELES_BASE, type ModeleConsignes, type SectionConsigne } from '@/lib/consignes-postop';

const TEAL = '#0C5C6C';

export interface ActionsConsignes {
  chargerModeles: () => Promise<ModeleConsignes[]>;
  enregistrerModele: (nom: string, sections: SectionConsigne[]) => Promise<void>;
  /** Sections de départ à partir d'une base (modèle) + données déjà saisies. */
  prerempli: (base: SectionConsigne[]) => SectionConsigne[];
  apercu: (sections: SectionConsigne[]) => Promise<Blob>;
  enregistrer: (sections: SectionConsigne[], valider: boolean) => Promise<void>;
}

export default function ConsignesEditeur({ initiales, verrouille, peutValider, actions, onTermine, onApercu }: {
  initiales: SectionConsigne[] | null;
  verrouille: boolean;
  peutValider: boolean;
  actions: ActionsConsignes;
  onTermine: () => void;
  onApercu: (blob: Blob) => void;
}) {
  const [sections, setSections] = useState<SectionConsigne[]>(() => initiales ?? actions.prerempli(MODELES_BASE[0].sections));
  const [modeles, setModeles] = useState<ModeleConsignes[]>([]);
  const [modeleChoisi, setModeleChoisi] = useState('');
  const [verifie, setVerifie] = useState(false);
  const [occupe, setOccupe] = useState<string | null>(null);
  const zones = useRef<(HTMLTextAreaElement | null)[]>([]);

  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { actions.chargerModeles().then(setModeles).catch(() => {}); }, []);
  const controle = useMemo(() => controlerConsignes(sections), [sections]);
  const tous = [...modeles, ...MODELES_BASE];

  const maj = (i: number, patch: Partial<SectionConsigne>) => { setSections(ss => ss.map((s, j) => j === i ? { ...s, ...patch } : s)); setVerifie(false); };
  const deplacer = (i: number, d: -1 | 1) => setSections(ss => {
    const j = i + d; if (j < 0 || j >= ss.length) return ss;
    const c = [...ss]; [c[i], c[j]] = [c[j], c[i]]; return c;
  });

  /** Mise en forme de la sélection : gras, liste, titre. */
  function formater(i: number, f: 'gras' | 'liste' | 'titre') {
    const z = zones.current[i]; if (!z) return;
    const t = sections[i].texte, a = z.selectionStart, b = z.selectionEnd;
    let nouveau: string;
    if (f === 'gras') nouveau = `${t.slice(0, a)}**${t.slice(a, b) || 'texte'}**${t.slice(b)}`;
    else {
      const debut = t.lastIndexOf('\n', a - 1) + 1;
      const fin = t.indexOf('\n', b) === -1 ? t.length : t.indexOf('\n', b);
      const prefixe = f === 'liste' ? '- ' : '## ';
      const lignes = t.slice(debut, fin).split('\n').map(l => l.startsWith(prefixe) ? l.slice(prefixe.length) : prefixe + l.replace(/^(- |## )/, ''));
      nouveau = t.slice(0, debut) + lignes.join('\n') + t.slice(fin);
    }
    maj(i, { texte: nouveau });
    setTimeout(() => z.focus(), 0);
  }

  function appliquerModele() {
    const m = tous.find(x => (x.id ?? x.nom) === modeleChoisi);
    if (!m) return;
    if (sections.some(s => s.texte.trim()) && !confirm('Remplacer les consignes saisies par ce modèle ? Le texte actuel sera perdu.')) return;
    setSections(actions.prerempli(m.sections.map(s => ({ ...s }))));
    setVerifie(false);
  }

  async function lancer(a: 'apercu' | 'brouillon' | 'valider' | 'modele') {
    setOccupe(a);
    try {
      if (a === 'apercu') onApercu(await actions.apercu(sections));
      else if (a === 'modele') {
        const nom = prompt('Nom du modèle (ex. « Stérilisation chienne »)');
        if (!nom?.trim()) return;
        await actions.enregistrerModele(nom.trim(), sections);
        setModeles(await actions.chargerModeles());
        alert('Modèle enregistré : il sera proposé pour les prochaines interventions.');
      } else { await actions.enregistrer(sections, a === 'valider'); onTermine(); }
    } catch (e) { alert(`Impossible : ${(e as Error).message}`); }
    finally { setOccupe(null); }
  }

  const champ = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] disabled:bg-gray-50 disabled:text-gray-600';
  const petit = 'text-xs font-semibold px-2 py-0.5 rounded border border-gray-200 text-gray-600 hover:bg-gray-50 disabled:opacity-40';
  const peutConfirmer = peutValider && !controle.bloquants.length && (!controle.avertissements.length || verifie);

  return (
    <div className="space-y-3">
      <p className="text-xs text-gray-500">Document pour le propriétaire, distinct du compte rendu opératoire. Les modèles ne sont qu’une base : vérifiez et adaptez chaque consigne à cet animal.</p>
      {!verrouille && (
        <div className="flex flex-wrap gap-2 items-center">
          <select value={modeleChoisi} onChange={e => setModeleChoisi(e.target.value)} className="border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white">
            <option value="">Partir d’un modèle…</option>
            {modeles.length > 0 && <optgroup label="Modèles de la clinique">{modeles.map(m => <option key={m.id} value={m.id}>{m.nom}</option>)}</optgroup>}
            <optgroup label="Structure seule (à rédiger)">{MODELES_BASE.map(m => <option key={m.nom} value={m.nom}>{m.nom}</option>)}</optgroup>
          </select>
          <button onClick={appliquerModele} disabled={!modeleChoisi} className="px-3 py-2 rounded-xl border text-sm font-semibold disabled:opacity-40" style={{ borderColor: TEAL, color: TEAL }}>Appliquer</button>
        </div>
      )}
      {sections.map((s, i) => (
        <div key={i} className="border border-gray-200 rounded-xl p-3 space-y-2">
          <div className="flex items-center gap-2">
            <input value={s.titre} onChange={e => maj(i, { titre: e.target.value })} disabled={verrouille} className={`${champ} font-semibold`} />
            {!verrouille && (
              <>
                <button onClick={() => deplacer(i, -1)} className={petit} aria-label="Monter">↑</button>
                <button onClick={() => deplacer(i, 1)} className={petit} aria-label="Descendre">↓</button>
                <button onClick={() => setSections(ss => ss.filter((_, j) => j !== i))} className="text-xs text-red-600 hover:underline whitespace-nowrap">Retirer</button>
              </>
            )}
          </div>
          {!verrouille && (
            <div className="flex gap-1.5">
              <button onClick={() => formater(i, 'titre')} className={petit}>Titre</button>
              <button onClick={() => formater(i, 'liste')} className={petit}>Liste</button>
              <button onClick={() => formater(i, 'gras')} className={`${petit} font-bold`}>Gras</button>
            </div>
          )}
          <textarea ref={el => { zones.current[i] = el; }} value={s.texte} onChange={e => maj(i, { texte: e.target.value })} disabled={verrouille}
            rows={Math.max(3, s.texte.split('\n').length + 1)} placeholder={s.aide ?? ''} className={`${champ} resize-y`} />
        </div>
      ))}
      {!verrouille && (
        <button onClick={() => setSections(ss => [...ss, { titre: 'Nouvelle section', texte: '' }])} className="text-sm font-semibold hover:underline" style={{ color: TEAL }}>
          Ajouter une section
        </button>
      )}
      {!verrouille && (
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
          {!peutValider && <p className="text-xs text-gray-500">Vous préparez ces consignes : un vétérinaire les vérifie, les valide et les signe.</p>}
        </>
      )}
      <div className="flex flex-wrap gap-2 justify-between">
        <div className="flex gap-2">
          <button onClick={() => lancer('apercu')} disabled={!!occupe} className="px-4 py-2 rounded-xl border text-sm font-semibold disabled:opacity-50" style={{ borderColor: TEAL, color: TEAL }}>
            {occupe === 'apercu' ? 'Préparation…' : 'Aperçu'}
          </button>
          <button onClick={() => lancer('modele')} disabled={!!occupe} className="px-3 py-2 rounded-xl text-sm font-semibold text-gray-600 hover:underline">Enregistrer comme modèle</button>
        </div>
        {!verrouille && (
          <div className="flex flex-wrap gap-2">
            <button onClick={() => lancer('brouillon')} disabled={!!occupe} className="px-4 py-2 rounded-xl border text-sm font-semibold disabled:opacity-50" style={{ borderColor: TEAL, color: TEAL }}>
              {occupe === 'brouillon' ? 'Enregistrement…' : 'Enregistrer le brouillon'}
            </button>
            {peutValider && (
              <button onClick={() => lancer('valider')} disabled={!!occupe || !peutConfirmer} className="px-4 py-2 rounded-xl text-sm font-semibold text-white disabled:opacity-40" style={{ background: TEAL }}>
                {occupe === 'valider' ? 'Validation…' : 'Valider et signer'}
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
