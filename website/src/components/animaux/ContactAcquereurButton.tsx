'use client';

import { useState } from 'react';
import { fetchContactAcquereur, waPhone, type ContactAcquereur } from '@/lib/contact-acquereur';

interface AnimalRef {
  id: string;
  nom?: string;
  uid_acquereur?: string | null;
  destinataire_nom?: string | null;
}

/**
 * Bouton compact « coordonnées » : au clic, charge et affiche les coordonnées
 * du nouveau propriétaire d'un animal cédé (nom, téléphone, email, adresse) +
 * actions rapides (appeler, WhatsApp, email). On sait jamais si on a besoin
 * de recontacter la famille — à poser sur toute carte animal cédé.
 */
export default function ContactAcquereurButton({ animal, className = '' }: { animal: AnimalRef; className?: string }) {
  const [loading, setLoading] = useState(false);
  const [open, setOpen] = useState(false);
  const [contact, setContact] = useState<ContactAcquereur | null>(null);

  async function handleOpen() {
    setLoading(true);
    try {
      const c = await fetchContactAcquereur(animal);
      setContact(c);
      setOpen(true);
    } finally {
      setLoading(false);
    }
  }

  const nomComplet = contact ? [contact.prenom, contact.nom].filter(Boolean).join(' ') : '';
  const aucune = !!contact && !nomComplet && !contact.tel && !contact.email && !contact.adresse;

  return (
    <>
      <button type="button" onClick={handleOpen} disabled={loading}
        title="Coordonnées du propriétaire"
        className={`shrink-0 w-7 h-7 rounded-full flex items-center justify-center text-[#0C5C6C] hover:bg-[#0C5C6C]/10 transition-colors disabled:opacity-50 ${className}`}>
        {loading ? '…' : '📇'}
      </button>

      {open && contact && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 sm:p-4"
          onClick={() => setOpen(false)}>
          <div className="bg-white rounded-t-2xl sm:rounded-2xl w-full sm:max-w-sm p-5 max-h-[85vh] overflow-y-auto"
            onClick={e => e.stopPropagation()}>
            <h3 className="font-bold text-[#1F2A2E] text-base mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>
              Coordonnées — {animal.nom ?? 'Animal'}
            </h3>
            {aucune ? (
              <p className="text-sm text-gray-500">Aucune coordonnée enregistrée pour cet animal.</p>
            ) : (
              <div className="rounded-xl bg-gray-50 border border-gray-200 p-3 text-sm space-y-1 mb-4">
                {nomComplet && <p>👤 {nomComplet}</p>}
                {contact.tel && <p>📞 {contact.tel}</p>}
                {contact.email && <p>✉️ {contact.email}</p>}
                {contact.adresse && <p>🏠 {contact.adresse}</p>}
              </div>
            )}
            <div className="flex flex-wrap gap-2">
              {contact.tel && (
                <a href={`tel:${contact.tel}`}
                  className="px-3.5 py-2 rounded-xl text-xs font-bold text-[#0C5C6C] bg-[#0C5C6C]/10 border border-[#0C5C6C]/30">
                  📞 Appeler
                </a>
              )}
              {contact.tel && (
                <a href={`https://wa.me/${waPhone(contact.tel)}`} target="_blank" rel="noopener noreferrer"
                  className="px-3.5 py-2 rounded-xl text-xs font-bold text-[#1a9e4b] bg-[#25D366]/10 border border-[#25D366]/40">
                  WhatsApp
                </a>
              )}
              {contact.email && (
                <a href={`mailto:${contact.email}`}
                  className="px-3.5 py-2 rounded-xl text-xs font-bold text-[#EA4335] bg-[#EA4335]/10 border border-[#EA4335]/30">
                  Email
                </a>
              )}
            </div>
            <button onClick={() => setOpen(false)} className="mt-4 w-full text-xs text-gray-500 py-2">Fermer</button>
          </div>
        </div>
      )}
    </>
  );
}
