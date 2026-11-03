'use client';

// Lien sécurisé par document (lot 6 des documents vétérinaires) : lien
// individuel (1, 7 ou 30 jours ; 7 par défaut), copié ou envoyé par e-mail
// avec un message personnalisable ; liste des liens du document (accès,
// expiration) et révocation. « Envoyé » n'est affiché qu'après confirmation
// du service d'envoi. Miroir appli : lib/widgets/pro/lien_securise_sheet.dart.

import { useEffect, useState } from 'react';
import { apiFetch } from '@/lib/api-fetch';

const TEAL = '#0C5C6C';

export interface DocumentPartage {
  /** URL du PDF stocké ; absente : [genererPdf] le produit et le dépose (compte rendu). */
  url?: string | null;
  genererPdf?: () => Promise<string>;
  crId?: string | null;
  type: 'ordonnance' | 'compte_rendu' | 'consignes';
  titre: string;
  animalNom?: string | null;
  expediteur?: string | null;
  emailParDefaut?: string | null;
  destinataireNom?: string | null;
}

interface Lien { id: string; destinataire_email: string | null; expire_le: string; revoque_le: string | null; nb_acces: number; dernier_acces_le: string | null; created_at: string }

const messageDefaut = (animal?: string | null) => `Bonjour,\n\nVous trouverez les documents relatifs à la prise en charge de ${animal || 'votre animal'}.\n\n`
  + 'Ils comprennent les recommandations et les documents établis par votre vétérinaire.\n\n'
  + 'Nous vous invitons à les conserver et à contacter la clinique si vous avez des questions.\n\n'
  + 'Cordialement,\n\nL’équipe vétérinaire.';

const jour = (d: string) => new Date(d).toLocaleDateString('fr-FR');

export default function LienSecuriseModal({ doc, onClose }: { doc: DocumentPartage; onClose: () => void }) {
  const [url, setUrl] = useState<string | null>(doc.url ?? null);
  const [jours, setJours] = useState(7);
  const [email, setEmail] = useState(doc.emailParDefaut ?? '');
  const [message, setMessage] = useState(messageDefaut(doc.animalNom));
  const [liens, setLiens] = useState<Lien[]>([]);
  const [resultat, setResultat] = useState<{ lien: string; envoye: boolean; expire_le: string } | null>(null);
  const [occupe, setOccupe] = useState<string | null>(null);
  const [erreur, setErreur] = useState<string | null>(null);

  async function chargerLiens(u: string | null) {
    if (!u) return;
    const r = await apiFetch(`/api/liens-documents?url=${encodeURIComponent(u)}`);
    if (r.ok) setLiens(((await r.json()).liens ?? []) as Lien[]);
  }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { chargerLiens(url); }, []);

  async function creer(envoyer: boolean) {
    setOccupe(envoyer ? 'envoyer' : 'creer'); setErreur(null); setResultat(null);
    try {
      let u = url;
      if (!u && doc.genererPdf) { u = await doc.genererPdf(); setUrl(u); }
      if (!u) throw new Error('document indisponible');
      const r = await apiFetch('/api/liens-documents', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          url: u, document_type: doc.type, titre: doc.titre, animal_nom: doc.animalNom, expediteur_nom: doc.expediteur,
          cr_id: doc.crId ?? undefined, jours, envoyer, ...(envoyer && email.trim() ? { email: email.trim() } : {}),
          destinataire_nom: doc.destinataireNom ?? undefined, message: envoyer ? message : undefined,
        }),
      });
      const j = await r.json().catch(() => ({}));
      if (j.lien) setResultat({ lien: j.lien, envoye: j.envoye === true, expire_le: j.expire_le });
      if (!r.ok) setErreur(j.code === 'sans_email' ? 'Aucune adresse e-mail connue pour ce propriétaire : saisissez-la.'
        : `${j.lien ? 'Lien créé, mais l’e-mail n’est pas parti' : 'Échec'} : ${j.error ?? r.status}`);
      await chargerLiens(u);
    } catch (e) { setErreur(`Échec : ${(e as Error).message}`); }
    finally { setOccupe(null); }
  }

  async function revoquer(id: string) {
    if (!confirm('Désactiver ce lien ? Il n’ouvrira plus le document.')) return;
    const r = await apiFetch('/api/liens-documents/revoquer', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id }) });
    if (!r.ok) { alert('Révocation impossible.'); return; }
    await chargerLiens(url);
  }

  const champ = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]';
  return (
    <div className="fixed inset-0 z-[70] bg-black/40 flex items-end sm:items-center justify-center p-0 sm:p-4" onClick={onClose}>
      <div className="bg-white w-full sm:max-w-lg max-h-[92vh] overflow-y-auto rounded-t-2xl sm:rounded-2xl p-5 space-y-4" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-semibold text-[#1F2A2E]" style={{ fontFamily: 'Galey,sans-serif' }}>Lien sécurisé — {doc.titre}</h2>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-sm">Fermer</button>
        </div>
        <p className="text-xs text-gray-500">Le lien n’ouvre que ce document, sans compte, jusqu’à sa date d’expiration ; vous pouvez le désactiver à tout moment. Chaque ouverture est enregistrée.</p>
        <div>
          <label className="text-[11px] font-medium text-gray-500 block mb-1">Validité</label>
          <div className="flex gap-2">
            {[1, 7, 30].map(n => (
              <button key={n} onClick={() => setJours(n)} className="px-3 py-1.5 rounded-lg border text-sm font-semibold"
                style={jours === n ? { background: TEAL, borderColor: TEAL, color: 'white' } : { borderColor: '#E4E7E2', color: TEAL }}>
                {n} jour{n > 1 ? 's' : ''}
              </button>
            ))}
          </div>
        </div>
        <div>
          <label className="text-[11px] font-medium text-gray-500 block mb-1">E-mail du destinataire</label>
          <input value={email} onChange={e => setEmail(e.target.value)} type="email" className={champ}
            placeholder="Vide : adresse du compte PetsMatch du propriétaire" />
        </div>
        <div>
          <label className="text-[11px] font-medium text-gray-500 block mb-1">Message</label>
          <textarea value={message} onChange={e => setMessage(e.target.value)} rows={8} className={`${champ} resize-y`} />
        </div>
        <div className="flex flex-wrap gap-2 justify-end">
          <button onClick={() => creer(false)} disabled={!!occupe} className="px-4 py-2 rounded-xl border text-sm font-semibold disabled:opacity-50" style={{ borderColor: TEAL, color: TEAL }}>
            {occupe === 'creer' ? 'Création…' : 'Créer le lien seulement'}
          </button>
          <button onClick={() => creer(true)} disabled={!!occupe} className="px-4 py-2 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: TEAL }}>
            {occupe === 'envoyer' ? 'Envoi…' : 'Créer et envoyer par e-mail'}
          </button>
        </div>
        {erreur && <p className="text-xs text-red-600 bg-red-50 rounded-xl px-3 py-2">{erreur}</p>}
        {resultat && (
          <div className="rounded-xl bg-[#F4F7F8] border border-gray-200 px-3 py-2 space-y-1.5">
            {resultat.envoye && <p className="text-xs font-semibold text-[#2E7D32]">E-mail envoyé (confirmé par le service d’envoi).</p>}
            <p className="text-xs text-gray-600">Lien valable jusqu’au {jour(resultat.expire_le)} :</p>
            <div className="flex gap-2">
              <input readOnly value={resultat.lien} className="flex-1 text-xs border border-gray-200 rounded-lg px-2 py-1.5 bg-white" onFocus={e => e.target.select()} />
              <button onClick={() => navigator.clipboard.writeText(resultat.lien).then(() => alert('Lien copié.')).catch(() => {})}
                className="px-3 py-1.5 rounded-lg text-xs font-semibold text-white" style={{ background: TEAL }}>Copier</button>
            </div>
          </div>
        )}
        {liens.length > 0 && (
          <div>
            <p className="text-xs font-semibold text-gray-600 mb-1">Liens de ce document</p>
            <div className="space-y-1.5">
              {liens.map(l => {
                const etat = l.revoque_le ? 'Désactivé' : new Date(l.expire_le).getTime() < Date.now() ? 'Expiré' : `Actif jusqu’au ${jour(l.expire_le)}`;
                return (
                  <div key={l.id} className="flex flex-wrap items-center gap-2 text-xs border-t border-gray-100 pt-1.5">
                    <span className="font-semibold text-[#1E2025]">{jour(l.created_at)}</span>
                    {l.destinataire_email && <span className="text-gray-500">→ {l.destinataire_email}</span>}
                    <span className={l.revoque_le || etat === 'Expiré' ? 'text-gray-400' : 'text-[#2E7D32]'}>{etat}</span>
                    <span className="text-gray-500">{l.nb_acces} ouverture{l.nb_acces > 1 ? 's' : ''}{l.dernier_acces_le ? ` (dernière le ${jour(l.dernier_acces_le)})` : ''}</span>
                    {!l.revoque_le && new Date(l.expire_le).getTime() >= Date.now() && (
                      <button onClick={() => revoquer(l.id)} className="ml-auto font-semibold text-red-600 hover:underline">Désactiver</button>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
