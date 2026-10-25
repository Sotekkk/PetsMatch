'use client';
// « Contacter » d'une fiche publique (professionnel, élevage, association) :
// coordonnées en clair et choix du moyen — messagerie PetsMatch, appel, SMS,
// WhatsApp, e-mail. Visible aussi sans compte (la messagerie demande alors la
// connexion puis ouvre la conversation). Toujours le PROFIL affiché :
// profileId = conversation avec ce profil ; tel / email = ceux de ce profil.
// Miroir appli : lib/widgets/contact_canaux.dart (showContactSheet).
import { useEffect } from 'react';
import ContactCanaux from '@/components/ContactCanaux';

export default function ContactModal({ nom, uid, profileId, tel, email, onClose }: {
  nom: string; uid: string; profileId?: string | null; tel?: string | null; email?: string | null; onClose: () => void;
}) {
  useEffect(() => {
    const echap = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', echap);
    return () => window.removeEventListener('keydown', echap);
  }, [onClose]);
  const t = (tel ?? '').trim(), m = (email ?? '').trim();
  return (
    <div className="fixed inset-0 z-50 bg-black/40 flex items-end sm:items-center justify-center p-4" onClick={onClose}>
      <div role="dialog" aria-modal="true" aria-label={`Contacter ${nom}`}
        className="bg-white rounded-2xl shadow-xl w-full max-w-sm p-5 space-y-4" onClick={e => e.stopPropagation()}
        style={{ fontFamily: 'Galey, sans-serif' }}>
        <div className="flex items-center gap-2">
          <p className="flex-1 font-bold text-[#1E2025]">Contacter {nom}</p>
          <button type="button" onClick={onClose} aria-label="Fermer"
            className="w-8 h-8 flex items-center justify-center rounded-lg text-gray-400 hover:bg-gray-50">×</button>
        </div>
        {(t || m) && (
          <div className="text-sm text-gray-600 space-y-1">
            {t && <p>Téléphone : <a href={`tel:${t.replace(/[^0-9+]/g, '')}`} className="font-semibold text-[#0C5C6C]">{t}</a></p>}
            {m && <p className="break-all">E-mail : <a href={`mailto:${m}`} className="font-semibold text-[#0C5C6C]">{m}</a></p>}
          </div>
        )}
        <ContactCanaux uid={uid} profileId={profileId} tel={t} email={m} sujet="Contact via PetsMatch"
          texteVide="Aucune coordonnée indiquée." />
        <p className="text-[11px] text-gray-400">« Message PetsMatch » ouvre la messagerie (connexion demandée si besoin).</p>
      </div>
    </div>
  );
}
