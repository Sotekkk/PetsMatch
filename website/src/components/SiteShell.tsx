'use client';
import { usePathname } from 'next/navigation';
import Image from 'next/image';
import Header from '@/components/Header';
import Footer from '@/components/Footer';
import CookieBanner from '@/components/CookieBanner';
import ValidationGuard from '@/components/ValidationGuard';

// Routes sans header/banner/footer (pages publiques de signature, etc.)
const NO_CHROME = ['/signer-contrat', '/signer-cession', '/certificat'];

export default function SiteShell({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const bare = NO_CHROME.some(r => pathname.startsWith(r));

  if (bare) return <main className="flex-1">{children}</main>;

  return (
    <>
      <Header />
      <Image
        src="/Banniere_petsmatch_site.png"
        alt="PetsMatch"
        width={0}
        height={0}
        sizes="100vw"
        className="w-full h-auto block"
        priority
      />
      <ValidationGuard>
        <main className="flex-1">{children}</main>
      </ValidationGuard>
      <Footer />
      <CookieBanner />
    </>
  );
}
