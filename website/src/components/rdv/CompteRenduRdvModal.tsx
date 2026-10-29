'use client';

// Compte rendu fait, ouvert depuis le RDV (Gérer mes RDV) sans quitter la
// page : texte, examens joints du jour, imprimer / envoyer au propriétaire,
// « Modifier » (formulaire complet de la fiche, retour au RDV ensuite).

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { maSignaturePro } from '@/lib/signature-pro';
import { pdfCompteRendu } from '@/lib/fin-consultation';
import { imprimerPdf, envoyerPdfParEmail } from '@/lib/transmission-document';
import LienDocument from '@/components/LienDocument';

const TEAL = '#0C5C6C';

interface Cr { id: string; animal_id: string; contenu: string | null; created_at: string; motif?: string | null; doc_url?: string | null; statut?: string | null }

export default function CompteRenduRdvModal({ crId, animalNom, rdvId, proProfileId, clientNom, onClose }: {
  crId: string; animalNom: string; rdvId: string; proProfileId: string | null; clientNom?: string; onClose: () => void;
}) {
  const { user, userData } = useAuth();
  const [cr, setCr] = useState<Cr | null>(null);
  const [examens, setExamens] = useState<{ id: string; titre: string | null; image_url: string | null }[]>([]);
  const [action, setAction] = useState<'' | 'imprimer' | 'email'>('');

  useEffect(() => {
    let annule = false;
    (async () => {
      const { data } = await supabase.from('comptes_rendus').select('*').eq('id', crId).maybeSingle();
      if (annule || !data) return;
      const c = data as Cr;
      setCr(c);
      // Radios / examens du jour avec pièce jointe.
      const jour = new Date(c.created_at).toLocaleDateString('sv-SE');
      const { data: rx } = await supabase.from('radios').select('id, titre, image_url').eq('animal_id', c.animal_id).eq('date', jour);
      if (!annule) setExamens(((rx ?? []) as { id: string; titre: string | null; image_url: string | null }[]).filter(r => r.image_url));
    })();
    return () => { annule = true; };
  }, [crId]);

  async function transmettre(a: 'imprimer' | 'email') {
    if (!cr || !user) return;
    setAction(a);
    try {
      const signature = await maSignaturePro(user.uid).catch(() => null);
      const praticien = `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim();
      const blob = await pdfCompteRendu(cr, { proProfileId, praticien, signature, emailCompte: user.email, proprietaire: clientNom });
      if (a === 'imprimer') imprimerPdf(blob);
      else await envoyerPdfParEmail(blob, { type: 'compte_rendu', destinataireNom: clientNom, expediteur: userData?.nameElevage || praticien,
        animalNom, nomFichier: `Compte-rendu-${animalNom}.pdf`, animalId: cr.animal_id });
    } catch (e) {
      alert(`Impossible : ${(e as Error).message}`);
    } finally { setAction(''); }
  }

  const bouton = 'text-xs font-semibold px-3 py-1.5 rounded-lg border disabled:opacity-50';
  return (
    <div className="fixed inset-0 z-50 flex justify-end bg-black/30" onClick={onClose}>
      <aside className="h-full w-full max-w-xl bg-white shadow-2xl overflow-y-auto p-6" onClick={e => e.stopPropagation()}
        style={{ fontFamily: 'Galey, sans-serif' }}>
        <div className="flex items-start gap-3">
          <div className="flex-1">
            <p className="text-sm font-bold" style={{ color: TEAL }}>
              {cr ? new Date(cr.created_at).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' }) : ''}
            </p>
            <h3 className="text-xl font-bold text-[#1E2025]">Compte rendu — {animalNom}</h3>
          </div>
          <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl w-8 h-8" aria-label="Fermer">✕</button>
        </div>
        {!cr ? <p className="text-sm text-gray-400 mt-6">Chargement…</p> : (
          <>
            {cr.contenu?.trim()
              ? <p className="mt-4 text-sm text-[#1E2025] whitespace-pre-wrap leading-relaxed">{cr.contenu}</p>
              : <p className="mt-4 text-sm text-gray-400">Aucun texte saisi.</p>}
            {(cr.doc_url || examens.length > 0) && (
              <div className="mt-4 space-y-1">
                <p className="text-[11px] font-bold tracking-wider uppercase text-gray-500">Pièces jointes</p>
                {cr.doc_url && (
                  <LienDocument href={cr.doc_url} target="_blank" rel="noopener noreferrer" className="block text-sm font-semibold underline" style={{ color: TEAL }}>
                    Document joint
                  </LienDocument>
                )}
                {examens.map(x => (
                  <LienDocument key={x.id} href={x.image_url!} target="_blank" rel="noopener noreferrer" className="block text-sm font-semibold underline" style={{ color: TEAL }}>
                    {x.titre || 'Radio / examen'}
                  </LienDocument>
                ))}
              </div>
            )}
            <div className="flex flex-wrap gap-2 mt-5">
              <a href={`/mes-patients/${encodeURIComponent(cr.animal_id)}?modifierCr=${encodeURIComponent(cr.id)}&rdv=${encodeURIComponent(rdvId)}`}
                className="text-xs font-semibold px-3 py-1.5 rounded-lg text-white" style={{ background: TEAL }}>
                Modifier
              </a>
              <button disabled={!!action} onClick={() => transmettre('imprimer')} className={bouton} style={{ borderColor: TEAL, color: TEAL }}>
                {action === 'imprimer' ? '…' : 'Imprimer'}
              </button>
              <button disabled={!!action} onClick={() => transmettre('email')} className={bouton} style={{ borderColor: TEAL, color: TEAL }}>
                {action === 'email' ? '…' : 'Envoyer au propriétaire'}
              </button>
              <a href={`/mes-patients/${encodeURIComponent(cr.animal_id)}?tab=Consultations&cr=${encodeURIComponent(cr.id)}&rdv=${encodeURIComponent(rdvId)}`}
                className={bouton} style={{ borderColor: '#D1D5DB', color: '#4B5563' }}>
                Voir la fiche
              </a>
            </div>
          </>
        )}
      </aside>
    </div>
  );
}
