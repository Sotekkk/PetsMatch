'use client';

// Document fait par le professionnel (tous les métiers), depuis un RDV :
//  • compte rendu (PDF ou photo) → rangé avec le RDV / l'animal et envoyé au
//    client (e-mail + notification) à la place du compte rendu généré ;
//  • contrat (PDF ou photo) → signé en ligne par le client, comme un contrat
//    généré ; ma signature est apposée d'office si elle est enregistrée.
// Miroir appli : showDocumentProSheet (lib/utils/document_pro.dart).

import { useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { envoyerPiecesParEmail } from '@/lib/transmission-document';
import { envoyerContratParEmail } from '@/lib/contrat-email';
import { signerContratAvecSignaturePro } from '@/lib/signature-pro';
import {
  ACCEPT_DOCUMENT_PRO, fichierEnPdf, chargerCompteRenduPro, creerContratPro, type RdvDocumentPro,
} from '@/lib/document-pro';

const TEAL = '#0C5C6C';

export default function DocumentProModal({ rdv, mode, clientNom, animalNom, proNom, catPro, onClose, onDone }: {
  rdv: RdvDocumentPro & { client_email_manuel?: string | null };
  mode: 'compte_rendu' | 'contrat';
  /** Métier du pro (abonnements.profil_type) : contrat = formule payante, comme le contrat PetsMatch. */
  catPro: string;
  clientNom: string; animalNom?: string; proNom: string;
  onClose: () => void;
  /** Après dépôt : [id] du document créé. */
  onDone: (id: string) => void;
}) {
  const { user } = useAuth();
  const cr = mode === 'compte_rendu';
  const [fichier, setFichier] = useState<File | null>(null);
  const [titre, setTitre] = useState(cr ? `Compte rendu${animalNom ? ` — ${animalNom}` : ''}` : `Contrat — ${clientNom}`);
  const [envoyer, setEnvoyer] = useState(true);
  const [enCours, setEnCours] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);

  async function emailClient(): Promise<string | null> {
    const { data } = await supabase.rpc('pm_contact_client_rdv', { p_rdv_id: rdv.id });
    const e = ((data ?? null) as { email?: string } | null)?.email?.trim();
    return e || rdv.client_email_manuel?.trim() || null;
  }

  async function notifier(type: string, title: string, body: string, data: Record<string, unknown>) {
    if (!rdv.client_uid) return;
    await supabase.from('notifications').insert({
      uid: rdv.client_uid, type, title, body, ...(rdv.client_profile_id ? { profile_id: rdv.client_profile_id } : {}), data, read: false,
    });
  }

  async function valider() {
    if (!user || !fichier) { setErreur('Choisissez un fichier (PDF ou photo).'); return; }
    setEnCours(true); setErreur(null);
    try {
      if (!cr) {
        const { data: ab } = await supabase.from('abonnements').select('plan_code').eq('uid', user.uid).eq('profil_type', catPro)
          .eq('statut', 'actif').order('created_at', { ascending: false }).limit(1).maybeSingle();
        if (((ab as { plan_code?: string } | null)?.plan_code ?? 'free') === 'free') {
          setErreur('La signature électronique des contrats est disponible avec les formules payantes.'); setEnCours(false); return;
        }
      }
      const blob = await fichierEnPdf(fichier);
      const proProfileId = rdv.pro_profile_id ?? null;
      const titreOk = titre.trim() || (cr ? 'Compte rendu' : 'Contrat');
      if (cr) {
        const { id } = await chargerCompteRenduPro(blob, { rdv, uid: user.uid, proProfileId, titre: titreOk });
        if (envoyer) {
          await notifier('compte_rendu_pro', 'Nouveau compte rendu', `${proNom || 'Votre professionnel'} vous a transmis un compte rendu${animalNom ? ` pour ${animalNom}` : ''}.`,
            { rdv_id: rdv.id, ...(rdv.animal_id ? { animal_id: rdv.animal_id } : {}), document_id: id });
          const email = await emailClient();
          await envoyerPiecesParEmail([{ type: 'compte_rendu', blob, nomFichier: `${titreOk.replace(/[\\/:*?"<>|]/g, '-')}.pdf` }], {
            emailParDefaut: email, destinataireNom: clientNom, expediteur: proNom, animalNom: animalNom ?? '', animalId: rdv.animal_id ?? null,
          });
        }
        onDone(id);
      } else {
        const email = await emailClient();
        const c = await creerContratPro(blob, { rdv, uid: user.uid, proProfileId, titre: titreOk, clientNom, clientEmail: email });
        // Ma signature apposée d'office ; sinon je la dessine sur la page du contrat.
        const signe = await signerContratAvecSignaturePro(c.id, user.uid, proNom);
        if (rdv.client_uid) {
          await notifier('contrat_invite', 'Contrat à signer', `${proNom || 'Votre professionnel'} vous envoie un contrat — vérifiez et signez`,
            { token: c.token, url: `/signer-contrat/${c.token}` });
        } else if (email) {
          await envoyerContratParEmail({ email, clientNom, proProfileId, token: c.token, titre: titreOk });
        }
        if (!signe) window.open(`/signer-contrat/${c.token}`, '_blank');
        onDone(c.id);
      }
    } catch (e) {
      setErreur((e as Error).message);
      setEnCours(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-md p-5 space-y-4" onClick={e => e.stopPropagation()}
        style={{ fontFamily: 'Galey, sans-serif' }}>
        <div>
          <h2 className="font-bold text-lg text-[#1E2025]">{cr ? 'Charger mon compte rendu' : 'Charger mon contrat'}</h2>
          <p className="text-xs text-gray-500 mt-0.5">{cr
            ? 'Votre propre document (PDF ou photo) : c’est lui qui est envoyé au client et rangé avec le rendez-vous.'
            : 'Votre propre contrat (PDF ou photo) : le client le lit et le signe en ligne, comme un contrat PetsMatch.'}</p>
        </div>
        <label className="block">
          <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Fichier</span>
          <input type="file" accept={ACCEPT_DOCUMENT_PRO} onChange={e => setFichier(e.target.files?.[0] ?? null)}
            className="mt-1 block w-full text-sm" />
        </label>
        <label className="block">
          <span className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Titre</span>
          <input value={titre} onChange={e => setTitre(e.target.value)}
            className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
        </label>
        {cr && (
          <label className="flex items-center gap-3 cursor-pointer">
            <input type="checkbox" checked={envoyer} onChange={e => setEnvoyer(e.target.checked)} className="w-4 h-4" style={{ accentColor: TEAL }} />
            <span className="text-sm text-[#1E2025]">Envoyer au client maintenant (e-mail{rdv.client_uid ? ' et notification' : ''})</span>
          </label>
        )}
        {erreur && <p className="text-xs text-red-500">{erreur}</p>}
        <div className="flex gap-2">
          <button type="button" onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm border border-gray-200 text-gray-600">Annuler</button>
          <button type="button" disabled={enCours || !fichier} onClick={valider}
            className="flex-[2] py-2.5 rounded-xl text-sm font-semibold text-white disabled:opacity-40" style={{ background: TEAL }}>
            {enCours ? '…' : cr ? (envoyer ? 'Enregistrer et envoyer' : 'Enregistrer') : 'Envoyer le contrat à signer'}
          </button>
        </div>
      </div>
    </div>
  );
}
