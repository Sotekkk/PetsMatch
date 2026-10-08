'use client';

import { useEffect } from 'react';
import { useParams, useRouter } from 'next/navigation';

// Anciennes pages de catégorie : la catégorie se choisit désormais en carte
// sur /services, qui affiche ses types de service.
const SLUGS: Record<string, string> = {
  sante: 'sante', education: 'education', garde: 'garde', toilettage: 'toilettage',
  transport: 'transport', photographes: 'photographe', alimentation: 'boutiques',
  boutiques: 'boutiques', assurances: 'assurance',
};

export default function CategorieRedirect() {
  const { categorie } = useParams<{ categorie: string }>();
  const router = useRouter();
  useEffect(() => {
    const c = SLUGS[categorie];
    router.replace(c ? `/services?categorie=${c}` : '/services');
  }, [categorie, router]);
  return null;
}
