'use client';
// Annonces « Matériel & équipements » du profil actif, intégrées à la page
// « Mes annonces » (site). Mêmes données, statuts et actions qu'auparavant
// (modifier, pause / activer, supprimer).

import { useCallback, useEffect, useState } from 'react';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { categorieLabel, ANNONCE_OBJET_TRANSACTIONS } from '@/lib/annonce-objet-categories';
import { Puce } from '@/components/dashboard/kit';
import { CarteAnnonce, EtatVide, Chargement, correspondRecherche, TEINTES_STATUT } from '@/components/annonces/GestionAnnonces';
import BoostAnnonceModal from '@/components/annonces/BoostAnnonceModal';

interface AnnonceObjet {
  id: string;
  titre: string;
  categorie: string;
  type_transaction: string;
  prix: number | null;
  prix_unite: string | null;
  photos: string[] | null;
  statut: string | null;
  boost_until: string | null;
  vues: number | null;
  contacts: number | null;
  created_at: string | null;
}

function prixLabel(a: AnnonceObjet): string {
  if (a.type_transaction === 'don') return 'Don';
  if (a.type_transaction === 'recherche') return 'Recherche';
  if (a.prix == null) return 'Prix à convenir';
  return `${Math.round(a.prix)} €${a.prix_unite ?? ''}`;
}
const boostActif = (s: string | null) => !!s && new Date(s) > new Date();

/** `statut` : filtre de statut commun de la page ('toutes', 'disponible', 'pause'…) ;
 *  `recherche` : texte de la barre de recherche (titre, catégorie). */
export default function MesAnnoncesMateriel({ statut = 'toutes', recherche = '', onCompte }: { statut?: string; recherche?: string; onCompte?: (n: number) => void }) {
  const { user, activeProfileId } = useAuth();
  const [rows, setRows] = useState<AnnonceObjet[] | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [boostId, setBoostId] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!user) return;
    const { data: migrated } = await supabase.from('annonces_objets').select('id')
      .eq('uid', user.uid).not('profile_id', 'is', null).limit(1);
    let q = supabase.from('annonces_objets').select(
      'id, titre, categorie, type_transaction, prix, prix_unite, photos, statut, boost_until, vues, contacts, created_at',
    ).neq('statut', 'supprime').order('created_at', { ascending: false });
    q = migrated && migrated.length > 0 && activeProfileId
      ? q.eq('profile_id', activeProfileId)
      : q.eq('uid', user.uid);
    const { data } = await q;
    setRows((data ?? []) as AnnonceObjet[]);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);
  useEffect(() => { if (rows) onCompte?.(rows.length); }, [rows, onCompte]);

  async function togglePause(a: AnnonceObjet) {
    setBusy(a.id);
    const next = a.statut === 'pause' ? 'disponible' : 'pause';
    await supabase.from('annonces_objets').update({ statut: next }).eq('id', a.id);
    setRows(r => (r ?? []).map(x => x.id === a.id ? { ...x, statut: next } : x));
    setBusy(null);
  }
  async function remove(a: AnnonceObjet) {
    if (!confirm('Supprimer définitivement cette annonce ?')) return;
    setBusy(a.id);
    await supabase.from('annonces_objets').update({ statut: 'supprime' }).eq('id', a.id);
    setRows(r => (r ?? []).filter(x => x.id !== a.id));
    setBusy(null);
  }

  if (rows === null) return <Chargement />;
  const liste = (statut === 'toutes' ? rows : rows.filter(a => (a.statut ?? 'disponible') === statut))
    .filter(a => correspondRecherche(recherche, a.titre, categorieLabel(a.categorie)));

  if (liste.length === 0) {
    if (rows.length === 0) return null; // « Aucune annonce » est affiché par la rubrique.
    return <EtatVide icone="caisse" texte={recherche.trim() ? 'Aucune annonce de matériel ne correspond à la recherche.' : 'Aucune annonce de matériel avec ce statut.'} />;
  }

  return (
    <div className="space-y-3">
      {liste.map(a => {
        const pause = a.statut === 'pause';
        // Boost choisi à la publication, paiement pas encore confirmé : pas en ligne.
        const attente = a.statut === 'attente_boost';
        const booste = boostActif(a.boost_until);
        const t = TEINTES_STATUT[attente ? 'ambre' : pause ? 'gris' : 'vert'];
        return (
          <CarteAnnonce key={a.id} href={`/annonces/objets/${a.id}`} photo={a.photos?.[0]} iconeVide="caisse"
            titre={a.titre}
            sousTitre={`${categorieLabel(a.categorie)} · ${ANNONCE_OBJET_TRANSACTIONS[a.type_transaction] ?? 'Vente'}`}
            etiquettes={<>
              <Puce texte={attente ? 'En attente de paiement' : pause ? 'En pause' : 'En ligne'} fg={t.fg} bg={t.bg} point />
              {booste && <Puce texte="Boostée" fg="#B45309" bg="#FEF3C7" icone="eclair" />}
            </>}
            prix={prixLabel(a)}
            indicateurs={[
              { icone: 'oeil', texte: `${a.vues ?? 0} vue${(a.vues ?? 0) > 1 ? 's' : ''}` },
              { icone: 'enveloppe', texte: `${a.contacts ?? 0} contact${(a.contacts ?? 0) > 1 ? 's' : ''}` },
              ...(a.created_at ? [{ icone: 'calendrier', texte: new Date(a.created_at).toLocaleDateString('fr-FR') }] : []),
            ]}
            principales={attente ? [
              { label: 'Reprendre la publication', icone: 'crayon', href: `/annonces/creer-objet?edit=${a.id}` },
            ] : [
              { label: 'Voir', icone: 'oeil', href: `/annonces/objets/${a.id}` },
              { label: 'Modifier', icone: 'crayon', href: `/annonces/creer-objet?edit=${a.id}` },
            ]}
            menu={attente ? [
              { label: 'Supprimer', icone: 'corbeille', danger: true, disabled: busy === a.id, onClick: () => remove(a) },
            ] : [
              { label: booste ? 'Prolonger le boost' : 'Booster l’annonce', icone: 'eclair', actif: booste, onClick: () => setBoostId(a.id) },
              { label: pause ? 'Activer' : 'Mettre en pause', icone: pause ? 'lecture' : 'pause', disabled: busy === a.id, onClick: () => togglePause(a) },
              { label: 'Supprimer', icone: 'corbeille', danger: true, disabled: busy === a.id, onClick: () => remove(a) },
            ]} />
        );
      })}
      {boostId && (
        <BoostAnnonceModal annonceId={boostId} table="annonces_objets"
          boostUntil={rows.find(x => x.id === boostId)?.boost_until} onClose={() => setBoostId(null)} />
      )}
    </div>
  );
}
