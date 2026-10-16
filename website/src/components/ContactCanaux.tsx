'use client';
// Contacter un client par le moyen de son choix : messagerie PetsMatch (s'il a
// un compte), appel, SMS, WhatsApp, e-mail. Chaque bouton n'apparaît que si
// la coordonnée existe. Miroir appli : lib/widgets/contact_canaux.dart.
import { waPhone } from '@/lib/contact-acquereur';

const TEAL = '#0C5C6C';

export default function ContactCanaux({ uid, tel, email, sujet, className = '' }: {
  uid?: string | null; tel?: string | null; email?: string | null;
  /** Objet pré-rempli de l'e-mail. */
  sujet?: string; className?: string;
}) {
  const t = (tel ?? '').trim(), m = (email ?? '').trim();
  const liens: { label: string; href: string; externe?: boolean }[] = [
    ...(uid ? [{ label: 'Message', href: `/messages?uid=${encodeURIComponent(uid)}` }] : []),
    ...(t ? [
      { label: 'Appeler', href: `tel:${t.replace(/[^0-9+]/g, '')}` },
      { label: 'SMS', href: `sms:${t.replace(/[^0-9+]/g, '')}` },
      { label: 'WhatsApp', href: `https://wa.me/${waPhone(t)}`, externe: true },
    ] : []),
    ...(m ? [{ label: 'E-mail', href: `mailto:${m}${sujet ? `?subject=${encodeURIComponent(sujet)}` : ''}` }] : []),
  ];
  if (!liens.length) return <p className={`text-xs text-gray-400 ${className}`}>Aucune coordonnée pour ce client.</p>;
  return (
    <div className={`flex flex-wrap gap-2 ${className}`}>
      {liens.map(l => (
        <a key={l.label} href={l.href} {...(l.externe ? { target: '_blank', rel: 'noopener noreferrer' } : {})}
          className="px-3 py-1.5 rounded-xl text-sm font-semibold border border-gray-200 bg-white hover:border-[#0C5C6C]" style={{ color: TEAL }}>
          {l.label}
        </a>
      ))}
    </div>
  );
}
