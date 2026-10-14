'use client';
// Compte rendu express d'une promenade / visite (pet-sitting) — miroir appli
// showVisiteRapportSheet : éléments à cocher, message généré, aperçu,
// photos et incident facultatifs, envoi après validation.
import { useMemo, useState } from 'react';
import {
  ITEMS_PROMENADE, ITEMS_VISITE, estPromenade, messageCompteRendu, envoyerCompteRendu, type RdvCompteRendu,
} from '@/lib/compte-rendu-garde';

const TEAL = '#0C5C6C';
const ROUGE = '#B3261E';

export default function CompteRenduExpressModal({ rdv, animalNom, proUid, proNom, onClose, onEnvoye }: {
  rdv: RdvCompteRendu; animalNom: string; proUid: string; proNom: string;
  onClose: () => void; onEnvoye?: () => void;
}) {
  const promenade = estPromenade(rdv.motif);
  const choix = promenade ? ITEMS_PROMENADE : ITEMS_VISITE;
  const [items, setItems] = useState<Set<string>>(new Set());
  const [avecComportement, setAvecComportement] = useState(false);
  const [comportement, setComportement] = useState('');
  const [avecIncident, setAvecIncident] = useState(false);
  const [incident, setIncident] = useState('');
  const [note, setNote] = useState('');
  const [photos, setPhotos] = useState<File[]>([]);
  const [envoi, setEnvoi] = useState(false);
  const [erreur, setErreur] = useState('');

  const message = useMemo(() => messageCompteRendu({
    promenade, animal: animalNom, items,
    comportement: avecComportement ? comportement : '', incident: avecIncident ? incident : '',
    note, nbPhotos: photos.length,
  }), [promenade, animalNom, items, avecComportement, comportement, avecIncident, incident, note, photos.length]);

  const basculer = (k: string) => setItems(s => { const n = new Set(s); if (n.has(k)) n.delete(k); else n.add(k); return n; });
  const puce = (actif: boolean, couleur = TEAL) => ({
    className: 'px-3 py-1.5 rounded-full text-sm font-semibold',
    style: actif ? { background: couleur, color: 'white' } : { background: couleur === TEAL ? '#F1F4F3' : '#FDECEA', color: couleur === TEAL ? '#1F2A2E' : couleur },
  });

  async function valider() {
    setEnvoi(true); setErreur('');
    try {
      await envoyerCompteRendu({ rdv, proUid, proNom, animalNom, message, incident: avecIncident && !!incident.trim(), photos });
      onEnvoye?.();
      onClose();
    } catch (e) {
      setErreur(e instanceof Error ? e.message : 'Envoi impossible');
      setEnvoi(false);
    }
  }

  const champ = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]';
  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-lg p-5 max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}
        style={{ fontFamily: 'Galey, sans-serif' }}>
        <h3 className="font-bold text-[#1E2025] text-lg mb-3">
          {promenade ? 'Compte rendu de promenade' : 'Compte rendu de visite'}{animalNom ? ` — ${animalNom}` : ''}
        </h3>
        <div className="flex flex-wrap gap-2">
          {choix.map(c => <button key={c.key} type="button" onClick={() => basculer(c.key)} {...puce(items.has(c.key))}>{c.label}</button>)}
          <button type="button" onClick={() => setAvecComportement(v => !v)} {...puce(avecComportement)}>Comportement particulier</button>
          <button type="button" onClick={() => setAvecIncident(v => !v)} {...puce(avecIncident, ROUGE)}>Incident</button>
        </div>
        {avecComportement && <input className={`${champ} mt-3`} placeholder="Ex : un peu craintif avec les vélos" value={comportement} onChange={e => setComportement(e.target.value)} />}
        {avecIncident && <textarea rows={2} className={`${champ} mt-3`} placeholder="Que s'est-il passé ?" value={incident} onChange={e => setIncident(e.target.value)} />}
        <textarea rows={2} className={`${champ} mt-3`} placeholder="Note libre (facultatif)" value={note} onChange={e => setNote(e.target.value)} />
        <div className="flex flex-wrap items-center gap-2 mt-3">
          {photos.map((f, i) => (
            <div key={i} className="relative">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img src={URL.createObjectURL(f)} alt="" className="w-14 h-14 rounded-lg object-cover" />
              <button type="button" onClick={() => setPhotos(p => p.filter((_, j) => j !== i))} aria-label="Retirer la photo"
                className="absolute -top-1.5 -right-1.5 w-5 h-5 rounded-full bg-black/60 text-white text-xs">✕</button>
            </div>
          ))}
          <label className="px-3 py-2 rounded-xl border text-sm font-semibold cursor-pointer" style={{ borderColor: TEAL, color: TEAL }}>
            + Photos
            <input type="file" accept="image/*" multiple className="hidden"
              onChange={e => { const fs = Array.from(e.target.files ?? []); if (fs.length) setPhotos(p => [...p, ...fs]); }} />
          </label>
        </div>
        <p className="text-xs font-bold text-gray-500 mt-4 mb-1">Aperçu</p>
        <p className="text-sm leading-relaxed rounded-xl p-3" style={{ background: avecIncident ? '#FDECEA' : '#F1F5F4' }}>{message}</p>
        {erreur && <p className="text-sm text-red-600 mt-2">{erreur}</p>}
        <div className="flex gap-2 mt-4">
          <button type="button" onClick={onClose} className="px-4 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Annuler</button>
          <button type="button" disabled={envoi || (avecIncident && !incident.trim())} onClick={valider}
            className="flex-1 py-2.5 rounded-xl text-sm font-bold text-white disabled:opacity-50" style={{ background: avecIncident ? ROUGE : TEAL }}>
            {envoi ? 'Envoi…' : 'Valider et envoyer au propriétaire'}
          </button>
        </div>
      </div>
    </div>
  );
}
