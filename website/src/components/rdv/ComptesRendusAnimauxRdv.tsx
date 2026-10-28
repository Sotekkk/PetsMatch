'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { ligneAnimalRdv, type AnimalRdv } from '@/lib/rdv-animaux';

// RDV à plusieurs animaux : un compte rendu (vétérinaire) ou une séance
// (ostéo) par animal, avec l'état de chacun — fait / brouillon / à faire.
// Miroir appli : choisirAnimalRdv (lib/utils/rdv_animaux.dart).

export default function ComptesRendusAnimauxRdv({ rdvId, animaux, metier }: {
  rdvId: string; animaux: AnimalRdv[]; metier: 'veterinaire' | 'sante';
}) {
  const [etats, setEtats] = useState<Record<string, 'fait' | 'brouillon'>>({});
  const [especes, setEspeces] = useState<Record<string, string>>({});

  useEffect(() => {
    let annule = false;
    (async () => {
      const table = metier === 'veterinaire' ? 'comptes_rendus' : 'suivis_morpho';
      const [{ data: rows }, { data: an }] = await Promise.all([
        supabase.from(table).select(metier === 'veterinaire' ? 'animal_id, statut' : 'animal_id').eq('rdv_id', rdvId),
        supabase.from('animaux').select('id, espece').in('id', animaux.map(a => a.id)),
      ]);
      if (annule) return;
      const e: Record<string, 'fait' | 'brouillon'> = {};
      for (const r of (rows ?? []) as unknown as { animal_id: string | null; statut?: string | null }[]) {
        const id = String(r.animal_id ?? '');
        if (e[id] !== 'fait') e[id] = r.statut === 'brouillon' ? 'brouillon' : 'fait';
      }
      setEtats(e);
      setEspeces(Object.fromEntries(((an ?? []) as { id: string; espece: string | null }[]).map(a => [String(a.id), a.espece ?? ''])));
    })();
    return () => { annule = true; };
  }, [rdvId, animaux, metier]);

  const lien = (a: AnimalRdv) => metier === 'veterinaire'
    ? `/mes-patients/${encodeURIComponent(a.id)}?crRdv=${encodeURIComponent(rdvId)}`
    : `/sante/suivis/nouveau?animalId=${encodeURIComponent(a.id)}&espece=${encodeURIComponent(especes[a.id] || 'chien')}&rdvId=${encodeURIComponent(rdvId)}`;

  return (
    <div className="mt-1 space-y-1" style={{ fontFamily: 'Galey, sans-serif' }}>
      {animaux.map(a => {
        const etat = etats[a.id];
        return (
          <div key={a.id} className="flex items-center gap-2">
            <p className="flex-1 min-w-0 text-xs text-gray-500 truncate">🐾 {ligneAnimalRdv(a)}</p>
            {/* Chargement complet : formulaire du compte rendu toujours repris à zéro. */}
            <a href={lien(a)} className="shrink-0 text-[11px] font-semibold px-2 py-0.5 rounded-lg border"
              style={etat === 'fait' ? { borderColor: '#2E7D32', color: '#2E7D32' }
                : etat === 'brouillon' ? { borderColor: '#8A5A00', color: '#8A5A00' }
                : { borderColor: '#0C5C6C', color: '#0C5C6C' }}>
              {etat === 'fait' ? (metier === 'veterinaire' ? 'Compte rendu fait' : 'Séance faite')
                : etat === 'brouillon' ? 'Brouillon'
                : metier === 'veterinaire' ? 'Compte rendu' : 'Séance'}
            </a>
          </div>
        );
      })}
    </div>
  );
}
