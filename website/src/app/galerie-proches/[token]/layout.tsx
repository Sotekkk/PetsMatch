import type { Metadata } from 'next';

// Galeries privées : jamais indexées par les moteurs de recherche.
export const metadata: Metadata = { title: 'Galerie privée', robots: { index: false, follow: false } };

export default function Layout({ children }: { children: React.ReactNode }) {
  return children;
}
