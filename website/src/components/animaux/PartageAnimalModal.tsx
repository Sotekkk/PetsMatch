'use client';

import { useCallback, useEffect, useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { supabase } from '@/lib/supabase';

// Partage de la fiche d'un animal : lien + QR code en lecture seule, onglets
// au choix (partage_animal.sections — la base n'ouvre que ceux-là).
// Miroir appli : lib/pages/particulier/partage_animal_sheet.dart.

export const SECTIONS_PARTAGE: [string, string][] = [
  ['identite', 'Identité'],
  ['sante', 'Carnet de santé'],
  ['poids', 'Poids'],
  ['alimentation', 'Alimentation'],
  ['documents', 'Documents'],
  ['genealogie', 'Généalogie'],
];

const DUREES: [string, number][] = [['24 heures', 1], ['3 jours', 3], ['7 jours', 7], ['30 jours', 30]];

type Lien = { id: string; token: string; expire_at: string; sections: string[] | null };

const lienUrl = (token: string) => `https://www.petsmatchapp.com/partage/${token}`;
const libelles = (s: string[] | null) =>
  SECTIONS_PARTAGE.filter(([k]) => (s ?? ['identite']).includes(k)).map(([, l]) => l).join(', ');

export default function PartageAnimalModal({ animalId, animalNom, uid, profileId, onClose }: {
  animalId: string; animalNom: string; uid: string; profileId?: string | null; onClose: () => void;
}) {
  const [sections, setSections] = useState<string[]>(['identite', 'sante']);
  const [duree, setDuree] = useState(7);
  const [liens, setLiens] = useState<Lien[]>([]);
  const [nouveau, setNouveau] = useState<string | null>(null);
  const [creation, setCreation] = useState(false);
  const [erreur, setErreur] = useState('');
  const [copie, setCopie] = useState(false);

  const charger = useCallback(async () => {
    let q = supabase.from('partage_animal').select('*')
      .eq('animal_id', animalId).eq('actif', true).gt('expire_at', new Date().toISOString())
      .order('created_at', { ascending: false });
    q = profileId ? q.eq('partageur_profile_id', profileId) : q.eq('uid_partageur', uid);
    const { data } = await q;
    setLiens((data ?? []) as Lien[]);
  }, [animalId, uid, profileId]);
  useEffect(() => { charger(); }, [charger]);

  async function creer() {
    setCreation(true); setErreur('');
    const { data, error } = await supabase.from('partage_animal').insert({
      animal_id: animalId, uid_partageur: uid,
      ...(profileId ? { partageur_profile_id: profileId } : {}),
      expire_at: new Date(Date.now() + duree * 86400000).toISOString(),
      actif: true,
      sections: SECTIONS_PARTAGE.map(([k]) => k).filter(k => sections.includes(k)),
    }).select('token').single();
    setCreation(false);
    if (error || !data) { setErreur(`Création impossible : ${error?.message ?? 'erreur inconnue'}`); return; }
    setNouveau((data as { token: string }).token);
    charger();
  }

  async function desactiver(id: string, token: string) {
    await supabase.from('partage_animal').update({ actif: false }).eq('id', id);
    if (nouveau === token) setNouveau(null);
    charger();
  }

  const token = nouveau ?? liens[0]?.token ?? null;
  const url = token ? lienUrl(token) : null;

  return (
    <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4" onClick={onClose}>
      <div className="bg-white rounded-2xl shadow-xl w-full max-w-md max-h-[90vh] overflow-y-auto p-5" onClick={e => e.stopPropagation()}
        style={{ fontFamily: 'Galey, sans-serif' }}>
        <div className="flex items-start justify-between gap-3">
          <div>
            <h2 className="text-lg font-bold text-[#1F2A2E]">Partager la fiche</h2>
            <p className="text-sm text-[#6E9E57]">{animalNom}</p>
          </div>
          <button onClick={onClose} aria-label="Fermer" className="text-gray-400 hover:text-gray-600 text-xl leading-none">×</button>
        </div>
        <p className="text-xs text-gray-500 mt-1">Lien en lecture seule : la personne voit uniquement les onglets cochés, sans rien pouvoir modifier.</p>

        <p className="text-sm font-semibold text-[#1F2A2E] mt-4 mb-1">Onglets visibles</p>
        <div className="space-y-1">
          {SECTIONS_PARTAGE.map(([k, l]) => (
            <label key={k} className={`flex items-center gap-2 text-sm ${k === 'identite' ? 'text-gray-500' : 'cursor-pointer'}`}>
              <input type="checkbox" className="w-4 h-4 accent-[#6E9E57]" checked={sections.includes(k)} disabled={k === 'identite'}
                onChange={() => setSections(s => s.includes(k) ? s.filter(x => x !== k) : [...s, k])} />
              {k === 'identite' ? `${l} (toujours)` : l}
            </label>
          ))}
        </div>

        <p className="text-sm font-semibold text-[#1F2A2E] mt-4 mb-1">Durée du lien</p>
        <div className="flex flex-wrap gap-2">
          {DUREES.map(([l, j]) => (
            <button key={j} type="button" onClick={() => setDuree(j)}
              className={`px-3 py-1.5 rounded-full text-xs font-semibold border ${duree === j ? 'bg-[#6E9E57] text-white border-[#6E9E57]' : 'text-gray-700 border-gray-200'}`}>{l}</button>
          ))}
        </div>

        <button type="button" onClick={creer} disabled={creation}
          className="w-full mt-4 py-2.5 rounded-xl bg-[#6E9E57] text-white text-sm font-bold hover:bg-[#5A8A45] disabled:opacity-60">
          {creation ? 'Création…' : 'Créer un nouveau lien'}
        </button>
        {erreur && <p className="text-xs text-red-600 mt-2">{erreur}</p>}

        {url && (
          <div className="mt-5 pt-4 border-t border-gray-100 flex flex-col items-center gap-3">
            <div className="p-3 border border-gray-200 rounded-2xl bg-white"><QRCodeSVG value={url} size={170} /></div>
            <p className="w-full text-center text-[11px] bg-gray-50 rounded-lg px-3 py-2 break-all">{url}</p>
            <div className="flex gap-2 w-full">
              <button type="button" onClick={() => { navigator.clipboard.writeText(url); setCopie(true); setTimeout(() => setCopie(false), 2000); }}
                className="flex-1 py-2 rounded-xl border border-gray-200 text-sm font-semibold text-gray-700 hover:bg-gray-50">{copie ? 'Lien copié' : 'Copier le lien'}</button>
              <a href={url} target="_blank" rel="noopener noreferrer"
                className="flex-1 py-2 rounded-xl bg-[#0C5C6C] text-white text-sm font-semibold text-center hover:bg-[#094F5D]">Aperçu</a>
            </div>
          </div>
        )}

        {liens.length > 0 && (
          <div className="mt-5">
            <p className="text-sm font-semibold text-[#1F2A2E] mb-2">Liens actifs</p>
            <div className="space-y-2">
              {liens.map(l => (
                <div key={l.id} className="flex items-center gap-2 border border-gray-200 rounded-xl px-3 py-2">
                  <div className="flex-1 min-w-0">
                    <p className="text-xs text-gray-700 truncate">…/{l.token.slice(0, 8)}… · expire le {new Date(l.expire_at).toLocaleDateString('fr-FR')}</p>
                    <p className="text-[11px] text-gray-500">{libelles(l.sections)}</p>
                  </div>
                  <button type="button" onClick={() => desactiver(l.id, l.token)} className="text-xs font-semibold text-red-600 hover:underline">Désactiver</button>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
