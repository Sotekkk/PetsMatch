'use client';
// Supprimer un contrat NON signé (brouillon, en attente, refusé, annulé,
// expiré). Un contrat signé, même en partie, reste : c'est la preuve de
// l'accord. Utilisé par les pages Contrats des pros (pension, pet-sitter,
// santé, toiletteur, photographe, maréchal…). Miroir appli :
// ContratSignaturePage._supprimerDocument.
import { useState } from 'react';
import { supabase } from '@/lib/supabase';

export const contratSupprimable = (statut?: string | null) => !['signe', 'partiellement_signe'].includes(statut ?? '');

export default function SupprimerContrat({ id, statut, libelle, onSupprime, className }: {
  id: string; statut?: string | null; libelle?: string; onSupprime: () => void; className?: string;
}) {
  const [enCours, setEnCours] = useState(false);
  if (!contratSupprimable(statut)) return null;
  return (
    <button type="button" disabled={enCours} title="Supprimer ce contrat (non signé)"
      className={className ?? 'text-xs text-red-500 hover:text-red-700 font-semibold disabled:opacity-40'}
      onClick={async ev => {
        // Carte cliquable (lien vers le contrat) : ne pas l'ouvrir.
        ev.preventDefault(); ev.stopPropagation();
        if (!confirm(`Supprimer ${libelle ? `le contrat de ${libelle}` : 'ce contrat'} ? Il n'a pas été signé : le lien envoyé au client ne fonctionnera plus.`)) return;
        setEnCours(true);
        const { data, error } = await supabase.from('documents_animaux').delete()
          .eq('id', id).not('statut', 'in', '(signe,partiellement_signe)').select('id');
        setEnCours(false);
        if (error || !data?.length) {
          alert(error ? `Suppression impossible : ${error.message}` : 'Suppression impossible : le contrat a été signé entre-temps.');
          return;
        }
        onSupprime();
      }}>
      {enCours ? '…' : 'Supprimer'}
    </button>
  );
}
