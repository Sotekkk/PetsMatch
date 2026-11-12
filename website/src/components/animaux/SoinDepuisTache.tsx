'use client';

// Tâche « rappel du carnet » cochée (accueil, agenda) : vérifie le carnet, puis
// coche la tâche (soin déjà fait pour tous) ou ouvre le formulaire de soin
// prérempli avec les animaux restants — enregistré, la tâche est validée.
// Logique : lib/soin-depuis-tache.ts.
import { useCallback, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import PorteeSoinModal, { type SoinAnimal } from '@/components/animaux/PorteeSoinModal';
import { dejaAdministres, estTacheRappelSoin, resoudreSoinTache, type SoinTache } from '@/lib/soin-depuis-tache';
import { basculerTacheManuelle } from '@/lib/valider-tache';
type Tache = { id: string; titre: string; date: string; statut: string; uid_eleveur: string; eleveur_profile_id?: string | null };

export function useSoinDepuisTache() {
  const { user, activeProfileId } = useAuth();
  const [ouvert, setOuvert] = useState<{ t: Tache; soin: SoinTache; animaux: SoinAnimal[]; restants: string[]; deja: string[]; apres: () => void } | null>(null);

  const valider = useCallback(async (t: Tache) => {
    if (!user) return;
    await basculerTacheManuelle({ ...t, statut: 'a_faire' }, { uid: user.uid, profileId: activeProfileId || null });
  }, [user, activeProfileId]);

  /** true : la tâche est prise en charge ici (cochée ou formulaire ouvert). */
  const traiter = useCallback(async (t: Tache, apres: () => void): Promise<boolean> => {
    if (t.statut === 'fait' || !estTacheRappelSoin(t.titre)) return false;
    const soin = await resoudreSoinTache(t.id);
    if (!soin) return false;
    const faits = await dejaAdministres(soin, t.date.slice(0, 10));
    const restants = soin.animalIds.filter(id => !faits.has(id));
    if (!restants.length) { await valider(t); apres(); return true; }
    const { data } = await supabase.from('animaux').select('id, nom, espece, sexe, date_naissance, identification').in('id', soin.animalIds);
    const animaux = ((data ?? []) as SoinAnimal[]).map(a => ({ ...a, id: String(a.id) }))
      .sort((a, b) => Number(restants.includes(b.id)) - Number(restants.includes(a.id)) || (a.nom ?? '').localeCompare(b.nom ?? ''));
    setOuvert({ t, soin, animaux, restants, deja: soin.animalIds.filter(id => faits.has(id)), apres });
    return true;
  }, [valider]);

  const nomDe = (id: string) => ouvert?.animaux.find(a => a.id === id)?.nom ?? '';
  const modal = ouvert ? (
    <PorteeSoinModal
      titre={`${ouvert.soin.label}${ouvert.soin.produit ? ` — ${ouvert.soin.produit}` : ''}`}
      animals={ouvert.animaux}
      uid={ouvert.t.uid_eleveur}
      activeProfileId={ouvert.t.eleveur_profile_id ?? activeProfileId ?? null}
      info={ouvert.deja.length ? `Déjà inscrit au carnet : ${ouvert.deja.map(nomDe).filter(Boolean).join(', ')}.` : undefined}
      initial={{ typeActe: ouvert.soin.typeActe, description: ouvert.soin.produit, selection: ouvert.restants }}
      onSaved={async () => { await valider(ouvert.t); ouvert.apres(); }}
      onClose={() => setOuvert(null)} />
  ) : null;

  return { traiter, modal };
}
