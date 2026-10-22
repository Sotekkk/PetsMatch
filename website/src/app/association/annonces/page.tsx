'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { lireFiltreType, FILTRES_TYPE, type TypeAnnonceFiltre } from '@/lib/annonces-droits';
import MesAnnoncesMateriel from '@/components/annonces/MesAnnoncesMateriel';
import BoostAnnonceModal from '@/components/annonces/BoostAnnonceModal';
import { Puce } from '@/components/dashboard/kit';
import {
  EnteteGestion, BarreFiltres, CarteAnnonce, RubriqueAnnonces, EtatVide, Chargement,
  correspondRecherche, TEINTES_STATUT,
} from '@/components/annonces/GestionAnnonces';

interface Annonce {
  id: string;
  titre?: string;
  type_vente?: string;
  espece?: string;
  race?: string;
  statut?: string;
  photos?: string[];
  vues?: number;
  contacts?: number;
  created_at?: string;
  expires_at?: string;
  boost_until?: string;
}

const STATUT_LABEL: Record<string, string> = {
  disponible: 'Disponible',
  pause:      'En pause',
  cede:       'Cédé',
  archive:    'Archivée',
  expiree:    'Expirée',
};
// Teinte de la puce de statut (TEINTES_STATUT du kit de gestion).
const STATUT_TEINTE: Record<string, string> = {
  disponible: 'vert', pause: 'gris', cede: 'teal', archive: 'gris', expiree: 'rouge',
};

type Tab = 'toutes' | 'disponible' | 'pause' | 'cede';

export default function AnnoncesAssoPage() {
  const { user, activeProfileId } = useAuth();
  const [annonces, setAnnonces] = useState<Annonce[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<Tab>('toutes');
  const [deleting, setDeleting] = useState<string | null>(null);
  const [typeFiltre, setTypeFiltre] = useState<TypeAnnonceFiltre>('toutes');
  const [nbMateriel, setNbMateriel] = useState(0);
  const [recherche, setRecherche] = useState('');
  // Boost : point d'entrée unique (menu « … ») ; ?boost=<id> l'ouvre (lien de l'appli).
  const [boostId, setBoostId] = useState<string | null>(null);
  useEffect(() => {
    const b = new URLSearchParams(window.location.search).get('boost');
    if (b) setBoostId(b);
  }, []);

  // Filtre de type lu dans l'URL (?type=animaux|materiel), anciens liens compris.
  useEffect(() => {
    setTypeFiltre(lireFiltreType(new URLSearchParams(window.location.search).get('type')));
  }, []);
  function choisirType(t: TypeAnnonceFiltre) {
    setTypeFiltre(t);
    const u = new URL(window.location.href);
    if (t === 'toutes') u.searchParams.delete('type'); else u.searchParams.set('type', t);
    window.history.replaceState({}, '', u.pathname + u.search);
  }

  const load = async () => {
    if (!user) return;
    let q = supabase
      .from('annonces')
      .select('id, titre, type_vente, espece, race, statut, photos, vues, contacts, created_at, expires_at, boost_until')
      .eq('uid_eleveur', user.uid)
      .eq('profil_source', 'association');
    // Annonces rattachées au profil association actif (une association
    // supprimée puis recréée ne reprend pas les annonces de l'ancienne) ;
    // repli sur l'uid pour les annonces antérieures à profile_id.
    if (activeProfileId) {
      const { data: check } = await supabase.from('annonces').select('id')
        .eq('uid_eleveur', user.uid).eq('profil_source', 'association').not('profile_id', 'is', null).limit(1);
      if ((check ?? []).length > 0) q = q.eq('profile_id', activeProfileId);
    }
    const { data } = await q.order('created_at', { ascending: false });
    setAnnonces(data ?? []);
    setLoading(false);
  };

  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { load(); }, [user, activeProfileId]);

  // Realtime
  useEffect(() => {
    if (!user) return;
    const channel = supabase.channel(`asso-annonces-${user.uid}`)
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'annonces', filter: `uid_eleveur=eq.${user.uid}` },
        (p) => setAnnonces(prev => prev.map(a => a.id === (p.new as Annonce).id ? { ...a, ...p.new as Annonce } : a)))
      .on('postgres_changes', { event: 'DELETE', schema: 'public', table: 'annonces', filter: `uid_eleveur=eq.${user.uid}` },
        (p) => setAnnonces(prev => prev.filter(a => a.id !== (p.old as Annonce).id)))
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [user]);

  const handlePause = async (a: Annonce) => {
    const next = a.statut === 'pause' ? 'disponible' : 'pause';
    await supabase.from('annonces').update({ statut: next }).eq('id', a.id);
    setAnnonces(prev => prev.map(x => x.id === a.id ? { ...x, statut: next } : x));
  };

  const handleRenew = async (a: Annonce) => {
    const newExpires = new Date();
    newExpires.setDate(newExpires.getDate() + 30);
    const newExpiresIso = newExpires.toISOString();
    await supabase.from('annonces').update({ statut: 'disponible', expires_at: newExpiresIso }).eq('id', a.id);
    setAnnonces(prev => prev.map(x => x.id === a.id ? { ...x, statut: 'disponible', expires_at: newExpiresIso } : x));
  };

  // Renouvellement proposé dès J-7 — les adoptions associatives dépassent
  // souvent la durée de vie standard d'une annonce (30 jours), pas la peine
  // d'attendre l'expiration complète pour prolonger.
  const expiresWithinDays = (a: Annonce, days: number): boolean => {
    if (!a.expires_at) return false;
    const remaining = (new Date(a.expires_at).getTime() - Date.now()) / 86400000;
    return remaining <= days;
  };

  const handleDelete = async (id: string) => {
    if (!confirm('Supprimer définitivement cette annonce ?')) return;
    setDeleting(id);
    await supabase.from('annonces').delete().eq('id', id);
    setAnnonces(prev => prev.filter(a => a.id !== id));
    setDeleting(null);
  };

  const parStatut = tab === 'toutes' ? annonces
    : tab === 'cede' ? annonces.filter(a => a.statut === 'cede' || a.statut === 'archive' || a.statut === 'expiree')
    : annonces.filter(a => a.statut === tab);
  const filtered = parStatut.filter(a => correspondRecherche(recherche, a.titre, a.espece, a.race));

  const voirAnimaux = typeFiltre !== 'materiel';
  const voirMateriel = typeFiltre !== 'animaux';
  const total = annonces.length + nbMateriel;
  // Statuts communs aux deux types (matériel : disponible / pause).
  const statutMateriel = tab === 'cede' ? 'aucun' : tab;

  return (
    <div className="font-galey">
      <EnteteGestion total={total} publierHref="/annonces/publier" />

      <BarreFiltres recherche={recherche} onRecherche={setRecherche} filtres={[
        { label: 'Type', valeur: typeFiltre, options: FILTRES_TYPE, onChange: v => choisirType(v as TypeAnnonceFiltre) },
        { label: 'Statut', valeur: tab, onChange: v => setTab(v as Tab),
          options: ([['toutes', 'Tous'], ['disponible', 'Disponible'], ['pause', 'En pause'], ['cede', 'Cédées']] as [Tab, string][]).map(([k, label]) => ({ k, label })) },
      ]} />

      {voirAnimaux && (
        <RubriqueAnnonces titre="Animaux à l’adoption" icone="patte" nombre={loading ? null : annonces.length}>
          {loading ? <Chargement /> : filtered.length === 0 ? (
            <EtatVide icone="patte" texte={recherche.trim() ? 'Aucune annonce ne correspond à la recherche.'
              : tab === 'toutes' ? 'Aucune annonce d’adoption publiée.' : `Aucune annonce ${tab === 'pause' ? 'en pause' : tab === 'cede' ? 'cédée' : 'disponible'}.`} />
          ) : (
            <div className="space-y-3">
              {filtered.map(a => {
                const statut = a.statut ?? 'disponible';
                const photos = (a.photos as string[]) ?? [];
                const t = TEINTES_STATUT[STATUT_TEINTE[statut] ?? 'gris'];
                const booste = !!a.boost_until && new Date(a.boost_until) > new Date();
                return (
                  <CarteAnnonce key={a.id} href={`/annonces/${a.id}`} photo={photos[0]}
                    titre={a.titre ?? (`${a.espece ?? ''} ${a.race ?? ''}`.trim() || 'Sans titre')}
                    sousTitre={[a.espece, a.race].filter(Boolean).join(' · ')}
                    etiquettes={<>
                      <Puce texte={STATUT_LABEL[statut] ?? statut} fg={t.fg} bg={t.bg} point />
                      <Puce texte="Adoption" fg="#41525A" bg="#F3F6F5" />
                      {booste && <Puce texte="Boostée" fg="#B45309" bg="#FEF3C7" icone="eclair" />}
                    </>}
                    indicateurs={[
                      { icone: 'oeil', texte: `${a.vues ?? 0} vue${(a.vues ?? 0) > 1 ? 's' : ''}` },
                      { icone: 'enveloppe', texte: `${a.contacts ?? 0} contact${(a.contacts ?? 0) > 1 ? 's' : ''}` },
                      ...(a.created_at ? [{ icone: 'calendrier', texte: new Date(a.created_at).toLocaleDateString('fr-FR') }] : []),
                    ]}
                    principales={[
                      { label: 'Voir', icone: 'oeil', href: `/annonces/${a.id}` },
                      { label: 'Modifier', icone: 'crayon', href: `/association/annonces/creer?edit=${a.id}` },
                    ]}
                    menu={[
                      { label: booste ? 'Prolonger le boost' : 'Booster l’annonce', icone: 'eclair', onClick: () => setBoostId(a.id), actif: booste },
                      { label: statut === 'pause' ? 'Réactiver' : 'Mettre en pause', icone: statut === 'pause' ? 'lecture' : 'pause', onClick: () => handlePause(a) },
                      ...((statut === 'expiree' || expiresWithinDays(a, 7)) ? [{ label: 'Renouveler pour 30 jours', icone: 'renouveler', onClick: () => handleRenew(a) }] : []),
                      { label: deleting === a.id ? 'Suppression…' : 'Supprimer', icone: 'corbeille', danger: true, disabled: deleting === a.id, onClick: () => handleDelete(a.id) },
                    ]} />
                );
              })}
            </div>
          )}
        </RubriqueAnnonces>
      )}

      {boostId && (
        <BoostAnnonceModal annonceId={boostId} returnPath="/association/annonces"
          boostUntil={annonces.find(x => x.id === boostId)?.boost_until}
          onClose={() => { setBoostId(null); if (window.location.search.includes('boost=')) window.history.replaceState({}, '', '/association/annonces'); }} />
      )}

      {voirMateriel && (
        <RubriqueAnnonces titre="Matériel & équipements" icone="caisse" nombre={nbMateriel}>
          <MesAnnoncesMateriel statut={statutMateriel} recherche={recherche} onCompte={setNbMateriel} />
        </RubriqueAnnonces>
      )}
    </div>
  );
}
