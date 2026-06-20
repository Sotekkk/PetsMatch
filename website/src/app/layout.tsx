import type { Metadata } from "next";
import "./globals.css";
import { AuthProvider } from "@/lib/auth-context";
import PushInit from "@/components/PushInit";
import SiteShell from "@/components/SiteShell";

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
          <SiteShell>{children}</SiteShell>
        </AuthProvider>
      </body>
    </html>
  );
}
