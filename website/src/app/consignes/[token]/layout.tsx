import type { Metadata } from 'next';

// Lien personnel : jamais indexé par les moteurs de recherche.
export const metadata: Metadata = { title: 'Vos consignes', robots: { index: false, follow: false } };

export default function Layout({ children }: { children: React.ReactNode }) {
  return children;
}
