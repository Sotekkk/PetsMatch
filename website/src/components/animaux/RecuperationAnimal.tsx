'use client';
// « Récupérer mon animal » (site) — appels /api/animaux/recuperer et
// fenêtre affichée quand une puce saisie correspond à un animal déjà
// enregistré. Miroir appli : lib/utils/recuperation_animal.dart.
import { useState } from 'react';
import { apiFetch } from '@/lib/api-fetch';
import { STORE_ANDROID, STORE_IOS } from '@/lib/stores';

export interface VerifPuce {
  etat: 'aucun' | 'deja_a_vous' | 'detenu' | 'recuperable';
  animal?: { id?: string; nom: string | null; espece?: string | null; race?: string | null; photo_url?: string | null; date_naissance?: string | null };
  elevage?: string; correspondance?: boolean; demandeEnCours?: boolean;
}

export async function appelRecuperation<T = { ok?: boolean; error?: string }>(body: Record<string, unknown>): Promise<T> {
  const r = await apiFetch('/api/animaux/recuperer', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  const j = await r.json();
  if (!r.ok) throw new Error(j.error ?? 'Opération impossible');
  return j as T;
}

export const verifierPuce = (puce: string) => appelRecuperation<VerifPuce>({ action: 'verifier', puce });

const TEAL = '#0C5C6C';

/** Fenêtre « animal déjà enregistré ». onFini(animalId?) : rattaché → id. */
export function RecuperationModal({ verif, profileId, onFermer, onFini }: {
  verif: VerifPuce; profileId: string | null; onFermer: () => void; onFini: (animalId?: string) => void;
}) {
  const [message, setMessage] = useState('');
  const [etat, setEtat] = useState<'' | 'envoi' | 'demande_envoyee'>(verif.demandeEnCours ? 'demande_envoyee' : '');
  const [erreur, setErreur] = useState('');
  const a = verif.animal;

  async function rattacher() {
    setEtat('envoi'); setErreur('');
    try { await appelRecuperation({ action: 'rattacher', animalId: a?.id, profileId }); onFini(a?.id); }
    catch (e) { setErreur((e as Error).message); setEtat(''); }
  }
  async function demander() {
    setEtat('envoi'); setErreur('');
    try { await appelRecuperation({ action: 'demander', animalId: a?.id, profileId, message }); setEtat('demande_envoyee'); }
    catch (e) { setErreur((e as Error).message); setEtat(''); }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={onFermer}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-md p-5 space-y-3" onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
        {verif.etat === 'deja_a_vous' ? (
          <>
            <p className="font-bold text-[#1F2A2E]">{a?.nom ?? 'Cet animal'} est déjà dans vos animaux</p>
            <p className="text-sm text-gray-600">Cette puce correspond à une fiche qui vous appartient déjà.</p>
          </>
        ) : verif.etat === 'detenu' ? (
          <>
            <p className="font-bold text-[#1F2A2E]">Puce déjà enregistrée</p>
            <p className="text-sm text-gray-600">Cette puce est enregistrée sur PetsMatch pour un animal appartenant à un autre compte. Vérifiez le numéro saisi ; si cet animal est le vôtre, contactez son propriétaire actuel ou notre équipe.</p>
          </>
        ) : (
          <>
            <div className="flex items-center gap-3">
              {/* eslint-disable-next-line @next/next/no-img-element */}
              {a?.photo_url && <img src={a.photo_url} alt="" className="w-14 h-14 rounded-xl object-cover" />}
              <div>
                <p className="font-bold text-[#1F2A2E]">{a?.nom ?? 'Cet animal'} est déjà enregistré</p>
                <p className="text-sm text-gray-500">{[a?.race, verif.elevage ? `par ${verif.elevage}` : ''].filter(Boolean).join(' · ')}</p>
              </div>
            </div>
            {etat === 'demande_envoyee' ? (
              <p className="text-sm text-gray-700">Votre demande a été envoyée à l&apos;élevage. Vous serez prévenu dès qu&apos;il l&apos;aura validée : l&apos;animal apparaîtra alors dans vos animaux, avec sa fiche complète.</p>
            ) : verif.correspondance ? (
              <>
                <p className="text-sm text-gray-700">Vos coordonnées correspondent à celles de l&apos;acquéreur enregistré par l&apos;élevage. Récupérez sa fiche complète (identité, généalogie, carnet de santé, documents) plutôt que d&apos;en créer une nouvelle.</p>
                <button onClick={rattacher} disabled={etat === 'envoi'} className="w-full py-2.5 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: TEAL }}>Rattacher {a?.nom ?? "l'animal"} à mon compte</button>
              </>
            ) : (
              <>
                <p className="text-sm text-gray-700">Si c&apos;est votre animal, demandez à l&apos;élevage de vous transmettre sa fiche complète plutôt que d&apos;en créer une nouvelle.</p>
                <textarea value={message} onChange={e => setMessage(e.target.value)} rows={2} placeholder="Un mot pour l'élevage (facultatif)"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
                <button onClick={demander} disabled={etat === 'envoi'} className="w-full py-2.5 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: TEAL }}>Demander à récupérer sa fiche</button>
              </>
            )}
          </>
        )}
        {erreur && <p className="text-sm" style={{ color: '#B3261E' }}>{erreur}</p>}
        <button onClick={onFermer} className="w-full py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Fermer</button>
      </div>
    </div>
  );
}

/** Message d'invitation (WhatsApp, SMS, e-mail). */
export function messageInvitation(prenom: string, elevage: string, animal: string, lien: string) {
  return `Bonjour${prenom ? ` ${prenom}` : ''}, ${elevage || 'votre éleveur'} vous invite à retrouver ${animal} sur PetsMatch : sa fiche (identité, généalogie, carnet de santé, documents) vous attend. `
    + `Ouvrez ce lien pour la récupérer, en créant votre compte sur le site ou dans l'application PetsMatch : ${lien}`
    + ` — Application : Android ${STORE_ANDROID} · iPhone ${STORE_IOS}`;
}

/** Numéro au format international pour WhatsApp (06… → 336…). */
export const telInternational = (tel: string) => {
  const d = tel.replace(/\D/g, '');
  if (d.startsWith('00')) return d.slice(2);
  if (d.startsWith('0') && d.length === 10) return `33${d.slice(1)}`;
  return d;
};

/** Élevage : inviter l'acquéreur (sans compte) à récupérer la fiche de
 *  l'animal cédé — WhatsApp, SMS, e-mail ou lien à copier. */
export function InviterAcquereurBouton({ animalId }: { animalId: string }) {
  const [etat, setEtat] = useState<'' | 'envoi' | 'pret'>('');
  const [inv, setInv] = useState<{ lien: string; email: string | null; tel: string | null; prenom: string; nom: string; animalNom: string; proNom: string } | null>(null);
  const [info, setInfo] = useState('');
  async function preparer() {
    setEtat('envoi'); setInfo('');
    try {
      const r = await appelRecuperation<{ token: string; email: string | null; tel: string | null; prenom: string; nom: string; animalNom: string; proNom: string }>({ action: 'inviter', animalId });
      setInv({ ...r, lien: `${window.location.origin}/reclamer-animal/${r.token}` });
      setEtat('pret');
    } catch (e) { setInfo((e as Error).message); setEtat(''); }
  }
  async function email() {
    if (!inv?.email) return;
    const r = await apiFetch('/api/animal-claim/notify-email', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: inv.email, nom_destinataire: inv.nom, animal_nom: inv.animalNom, pro_nom: inv.proNom, claim_url: inv.lien, contexte: 'cession' }),
    });
    setInfo(r.ok ? `E-mail envoyé à ${inv.email}.` : "L'e-mail n'a pas pu être envoyé.");
  }
  const msg = inv ? messageInvitation(inv.prenom, inv.proNom, inv.animalNom, inv.lien) : '';
  const btn = 'text-xs font-semibold text-blue-700 border border-blue-300 px-2.5 py-1 rounded-lg hover:bg-blue-100 transition-colors';
  return (
    <span className="inline-flex flex-col gap-1.5">
      {etat !== 'pret' ? (
        <button onClick={preparer} disabled={etat === 'envoi'} className={`${btn} disabled:opacity-50`}>Inviter l&apos;acquéreur à récupérer la fiche</button>
      ) : inv && (
        <span className="flex flex-wrap gap-1.5 items-center">
          <span className="text-[11px] text-blue-700 w-full">Envoyer l&apos;invitation{inv.prenom || inv.nom ? ` à ${`${inv.prenom} ${inv.nom}`.trim()}` : ''} :</span>
          <a className={btn} target="_blank" rel="noopener noreferrer"
            href={inv.tel ? `https://wa.me/${telInternational(inv.tel)}?text=${encodeURIComponent(msg)}` : `https://wa.me/?text=${encodeURIComponent(msg)}`}>WhatsApp</a>
          <a className={btn} href={`sms:${inv.tel ? inv.tel.replace(/\s/g, '') : ''}?&body=${encodeURIComponent(msg)}`}>SMS</a>
          {inv.email
            ? <button className={btn} onClick={email}>E-mail</button>
            : <a className={btn} href={`mailto:?subject=${encodeURIComponent(`${inv.animalNom} vous attend sur PetsMatch`)}&body=${encodeURIComponent(msg)}`}>E-mail</a>}
          <button className={btn} onClick={async () => { try { await navigator.clipboard.writeText(msg); setInfo('Message copié.'); } catch { setInfo(inv.lien); } }}>Copier le message</button>
        </span>
      )}
      {info && <span className="text-[11px] text-blue-600">{info}</span>}
    </span>
  );
}
