'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { ligneAnimalRdv, type AnimalRdv } from '@/lib/rdv-animaux';
import { crsDuRdv } from '@/lib/cr-rdv';

// RDV à plusieurs animaux : un compte rendu (vétérinaire) ou une séance
// (ostéo) par animal, avec l'état de chacun — fait / brouillon / à faire.
// Miroir appli : choisirAnimalRdv (lib/utils/rdv_animaux.dart).

export default function ComptesRendusAnimauxRdv({ rdvId, animaux, metier }: {
  rdvId: string; animaux: AnimalRdv[]; metier: 'veterinaire' | 'sante';
}) {
  const [etats, setEtats] = useState<Record<string, 'fait' | 'brouillon'>>({});
  const [especes, setEspeces] = useState<Record<string, string>>({});
  // Vétérinaire : compte rendu (fait ou brouillon) de chaque animal pour ce RDV.
  const [crIds, setCrIds] = useState<Record<string, string>>({});

  // Clé stable : la liste est recréée à chaque affichage de la carte.
  const ids = animaux.map(a => a.id).join(',');
  useEffect(() => {
    let annule = false;
    (async () => {
      const table = metier === 'veterinaire' ? 'comptes_rendus' : 'suivis_morpho';
      // Vétérinaire : aussi les comptes rendus faits depuis la fiche le jour du RDV.
      const [{ data: rows }, { data: an }] = await Promise.all([
        metier === 'veterinaire' ? crsDuRdv(rdvId, ids.split(',')).then(data => ({ data }))
          : supabase.from(table).select('animal_id').eq('rdv_id', rdvId),
        supabase.from('animaux').select('id, espece').in('id', ids.split(',')),
      ]);
      if (annule) return;
      const e: Record<string, 'fait' | 'brouillon'> = {};
      const ci: Record<string, string> = {};
      for (const r of (rows ?? []) as unknown as { id?: string; animal_id: string | null; statut?: string | null; rattache?: boolean }[]) {
        const id = String(r.animal_id ?? '');
        if (e[id] === 'fait') continue;
        e[id] = r.statut === 'brouillon' ? 'brouillon' : 'fait';
        if (r.id) ci[id] = r.id;
        // Compte rendu fait depuis la fiche le jour du RDV : rattaché au RDV.
        if (r.id && r.rattache === false) await supabase.from('comptes_rendus').update({ rdv_id: rdvId }).eq('id', r.id);
      }
      setEtats(e);
      setCrIds(ci);
      setEspeces(Object.fromEntries(((an ?? []) as { id: string; espece: string | null }[]).map(a => [String(a.id), a.espece ?? ''])));
    })();
    return () => { annule = true; };
  }, [rdvId, ids, metier]);

  // Fait : la fiche, onglet Consultations, ce compte rendu ouvert ;
  // brouillon : ce brouillon repris ; à faire : un compte rendu vierge du RDV.
  const lien = (a: AnimalRdv) => metier === 'veterinaire'
    ? (etats[a.id] === 'fait' && crIds[a.id]
      ? `/mes-patients/${encodeURIComponent(a.id)}?tab=Consultations&cr=${encodeURIComponent(crIds[a.id])}&rdv=${encodeURIComponent(rdvId)}`
      : etats[a.id] === 'brouillon' && crIds[a.id]
        ? `/mes-patients/${encodeURIComponent(a.id)}?crRdv=${encodeURIComponent(rdvId)}&brouillon=${encodeURIComponent(crIds[a.id])}`
        : `/mes-patients/${encodeURIComponent(a.id)}?crRdv=${encodeURIComponent(rdvId)}&nouveau=1`)
    : `/sante/suivis/nouveau?animalId=${encodeURIComponent(a.id)}&espece=${encodeURIComponent(especes[a.id] || 'chien')}&rdvId=${encodeURIComponent(rdvId)}`;

  return (
    <div className="mt-1 space-y-1" style={{ fontFamily: 'Galey, sans-serif' }}>
      {animaux.map(a => {
        const etat = etats[a.id];
        return (
          <div key={a.id} className="flex items-center gap-2">
            <p className="flex-1 min-w-0 text-xs text-gray-500 truncate">🐾 {ligneAnimalRdv(a)}</p>
            {/* Chargement complet : formulaire du compte rendu toujours repris à zéro. */}
            {/* Fait (vert plein) : l'ouvrir — Brouillon (orange) : le reprendre — À faire (contour) : le rédiger. */}
            <a href={lien(a)} className="shrink-0 text-[11px] font-semibold px-2 py-0.5 rounded-lg border"
              style={etat === 'fait' ? { background: '#2E7D32', borderColor: '#2E7D32', color: 'white' }
                : etat === 'brouillon' ? { background: '#FFF4E0', borderColor: '#C77800', color: '#8A5A00' }
                : { background: 'white', borderColor: '#0C5C6C', color: '#0C5C6C' }}>
              {etat === 'fait' ? `✓ ${metier === 'veterinaire' ? 'Compte rendu fait' : 'Séance faite'} · ouvrir`
                : etat === 'brouillon' ? 'Brouillon · reprendre'
                : `À faire · ${metier === 'veterinaire' ? 'rédiger le compte rendu' : 'rédiger la séance'}`}
            </a>
          </div>
        );
      })}
    </div>
  );
}
