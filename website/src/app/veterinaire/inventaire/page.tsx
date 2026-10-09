'use client';
// Pharmacie vétérinaire : même page que l'inventaire (mode véto détecté sur le
// profil actif), réservée aux formules Avancé et Clinique.
import InventairePage from '@/app/elevage/inventaire/page';
import FormuleVetRequise from '@/components/pro/FormuleVetRequise';

export default function PharmacieVetPage() {
  return <FormuleVetRequise requise="avance" fonction="Inventaire & pharmacie"><InventairePage /></FormuleVetRequise>;
}
