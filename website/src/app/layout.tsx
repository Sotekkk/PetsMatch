import type { Metadata } from "next";
import Image from "next/image";
import "./globals.css";
import Header from "@/components/Header";
import Footer from "@/components/Footer";
import CookieBanner from "@/components/CookieBanner";
import { AuthProvider } from "@/lib/auth-context";
import ValidationGuard from "@/components/ValidationGuard";
import PushInit from "@/components/PushInit";

export const metadata: Metadata = {
  title: "PetsMatch — Connecter · Prendre soin · Partager",
  description: "Trouvez votre compagnon idéal, découvrez les élevages certifiés et aidez les animaux perdus.",
  keywords: "animaux, élevage, chien, chat, adoption, compagnon, animaux perdus",
  manifest: "/manifest.json",
  appleWebApp: {
    capable: true,
    statusBarStyle: "default",
    title: "PetsMatch",
  },
  icons: {
    apple: "/Logo_petsmatch_fond_blanc.png",
  },
  openGraph: {
    title: "PetsMatch",
    description: "La communauté des passionnés d'animaux",
    images: ["/Banniere_petsmatch.png"],
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr" className="h-full">
      <body className="min-h-full flex flex-col antialiased">
        <AuthProvider>
          <PushInit />
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
        </AuthProvider>
      </body>
    </html>
  );
}
