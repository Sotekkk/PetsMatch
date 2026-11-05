'use client';
import { useEffect, useState } from 'react';
import { usePathname } from 'next/navigation';
import { estDansPanneau, signalerPanneau, MSG_PANNEAU_PRET, MSG_PANNEAU_FERMER } from '@/lib/panneau';
import Image from 'next/image';
import Header from '@/components/Header';
import Footer from '@/components/Footer';
import CookieBanner from '@/components/CookieBanner';
import ValidationGuard from '@/components/ValidationGuard';
import OnboardingGate from '@/components/onboarding/OnboardingGate';

// Routes sans header/banner/footer (pages publiques de signature, etc.)
const NO_CHROME = ['/signer-contrat', '/signer-cession', '/certificat'];

export default function SiteShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const bare = NO_CHROME.some(r => pathname.startsWith(r));
  // Page ouverte dans un panneau (components/PanneauPage.tsx) : sans en-tête.
  const [panneau, setPanneau] = useState(false);
  useEffect(() => {
    if (!estDansPanneau()) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setPanneau(true);
    signalerPanneau(MSG_PANNEAU_PRET);
  }, []);
  // Molette sur un champ numérique en cours de saisie : le navigateur change sa valeur
  // sans qu'on le voie (prix de 90 € enregistré à 88 €). On quitte le champ : la valeur
  // reste telle quelle et la page défile normalement.
  useEffect(() => {
    const surMolette = (e: WheelEvent) => {
      const champ = e.target;
      if (champ instanceof HTMLInputElement && champ.type === 'number' && document.activeElement === champ) champ.blur();
    };
    document.addEventListener('wheel', surMolette, { capture: true, passive: true });
    return () => document.removeEventListener('wheel', surMolette, { capture: true });
  }, []);
  // En panneau, une page qui revient vers Gérer mes RDV (retour après une
  // action) referme le panneau au lieu de s'y afficher.
  useEffect(() => {
    if (panneau && pathname.startsWith('/mes-rdv')) signalerPanneau(MSG_PANNEAU_FERMER);
  }, [panneau, pathname]);

  if (bare) return <main className="flex-1">{children}</main>;

  // Même structure avec ou sans panneau : la page garde sa place dans l'arbre. Sinon,
  // à la détection du panneau, React la recréait : ce qu'elle avait lu une seule fois
  // au montage (facture préparée dans sessionStorage) était perdu.
  return (
    <>
      {!panneau && <Header />}
      {!panneau && (
        <Image
          src="/Banniere_petsmatch_site.png"
          alt="PetsMatch"
          width={0}
          height={0}
          sizes="100vw"
          // Accueils (éleveur / pro « / », association « /association ») : hauteur
          // plafonnée sur très grand écran (bannière entière, centrée)
          className={pathname === '/' || pathname === '/association' ? 'w-full h-auto max-h-[260px] object-contain object-center block bg-white' : 'w-full h-auto block'}
          priority
        />
      )}
      <ValidationGuard>
        <main className="flex-1">{children}</main>
      </ValidationGuard>
      {!panneau && <Footer />}
      {!panneau && <CookieBanner />}
      {!panneau && <OnboardingGate />}
    </>
  );
}
