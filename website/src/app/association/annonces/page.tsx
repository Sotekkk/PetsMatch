'use client';

import { useEffect, useState } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { lireFiltreType, type TypeAnnonceFiltre } from '@/lib/annonces-droits';
import MesAnnoncesMateriel from '@/components/annonces/MesAnnoncesMateriel';
import FiltresAnnonces from '@/components/annonces/FiltresAnnonces';
import { Icone, BORDURE, OMBRE } from '@/components/dashboard/kit';

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
}

const STATUT_LABEL: Record<string, string> = {
  disponible: 'Disponible',
  pause:      'En pause',
  cede:       'Cédé',
  archive:    'Archivée',
  expiree:    'Expirée',
};
const STATUT_COLOR: Record<string, string> = {
  disponible: 'bg-green-100 text-green-700',
  pause:      'bg-gray-100 text-gray-500',
  cede:       'bg-teal-100 text-[#0C5C6C]',
  archive:    'bg-gray-100 text-gray-500',
  expiree:    'bg-red-100 text-red-500',
};

type Tab = 'toutes' | 'disponible' | 'pause' | 'cede';

export default function AnnoncesAssoPage() {
  const { user } = useAuth();
  const [annonces, setAnnonces] = useState<Annonce[]>([]);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<Tab>('toutes');
  const [deleting, setDeleting] = useState<string | null>(null);
  const [typeFiltre, setTypeFiltre] = useState<TypeAnnonceFiltre>('toutes');
  const [nbMateriel, setNbMateriel] = useState(0);

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

  const load = () => {
    if (!user) return;
    supabase
      .from('annonces')
      .select('id, titre, type_vente, espece, race, statut, photos, vues, contacts, created_at, expires_at')
      .eq('uid_eleveur', user.uid)
      .eq('profil_source', 'association')
      .order('created_at', { ascending: false })
      .then(({ data }) => { setAnnonces(data ?? []); setLoading(false); });
  };

  useEffect(() => { load(); }, [user]);

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

  const filtered = tab === 'toutes' ? annonces
    : tab === 'cede' ? annonces.filter(a => a.statut === 'cede' || a.statut === 'archive' || a.statut === 'expiree')
    : annonces.filter(a => a.statut === tab);

  const voirAnimaux = typeFiltre !== 'materiel';
  const voirMateriel = typeFiltre !== 'animaux';
  const total = annonces.length + nbMateriel;
  const btnIcone = 'inline-flex items-center justify-center w-9 h-9 border rounded-xl transition-colors';
  // Statuts communs aux deux types (matériel : disponible / pause).
  const statutMateriel = tab === 'cede' ? 'aucun' : tab;

  return (
    <div className="space-y-5 font-galey">
      {/* En-tête */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold text-[#1E2025]">Mes annonces</h1>
          <p className="text-sm text-gray-500 mt-0.5">{total} annonce{total !== 1 ? 's' : ''}</p>
        </div>
        <Link href="/annonces/publier"
          className="bg-[#0C5C6C] text-white px-5 py-2.5 rounded-lg text-sm font-semibold hover:bg-[#094F5D] transition-colors inline-flex items-center gap-2">
          <Icone nom="plus" taille={16} /> Publier une annonce
        </Link>
      </div>

      <FiltresAnnonces
        type={typeFiltre} onType={choisirType}
        statut={tab} onStatut={v => setTab(v as Tab)}
        statuts={([['toutes', 'Tous les statuts'], ['disponible', 'Disponible'], ['pause', 'En pause'], ['cede', 'Cédées']] as [Tab, string][]).map(([k, label]) => ({ k, label }))}
      />

      {voirAnimaux && (
        <section>
          {typeFiltre === 'toutes' && <h2 className="text-lg font-bold text-[#1E2025] mb-3">Animaux</h2>}
          {loading ? (
            <div className="flex justify-center py-16">
              <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
            </div>
          ) : filtered.length === 0 ? (
            <div className={`text-center py-12 bg-white rounded-2xl ${OMBRE}`} style={{ border: `1px solid ${BORDURE}` }}>
              <span className="w-11 h-11 mx-auto mb-3 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center"><Icone nom="patte" /></span>
              <p className="text-sm text-gray-500 mb-3">
                {tab === 'toutes' ? 'Aucune annonce d’adoption publiée.' : `Aucune annonce ${tab === 'pause' ? 'en pause' : tab === 'cede' ? 'cédée' : 'disponible'}.`}
              </p>
              {tab === 'toutes' && (
                <Link href="/association/annonces/creer"
                  className="inline-block bg-[#0C5C6C] text-white px-5 py-2.5 rounded-lg text-sm font-semibold hover:bg-[#094F5D]">
                  Publier une annonce d’adoption
                </Link>
              )}
            </div>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
              {filtered.map(a => {
                const statut = a.statut ?? 'disponible';
                const photos = (a.photos as string[]) ?? [];
                return (
                  <div key={a.id} className={`bg-white rounded-2xl overflow-hidden flex flex-col ${OMBRE}`} style={{ border: `1px solid ${BORDURE}` }}>
                    <div className="aspect-[4/3] bg-[#E8F4F6] relative">
                      {photos[0] ? (
                        <Image src={photos[0]} alt={a.titre ?? ''} fill className="object-cover" unoptimized />
                      ) : (
                        <div className="w-full h-full flex items-center justify-center text-[#0C5C6C]"><Icone nom="patte" taille={40} /></div>
                      )}
                      <div className="absolute top-2 left-2">
                        <span className="bg-white/95 text-[#1E2025] text-xs font-semibold px-2 py-0.5 rounded-full border border-[#E5E8E6]">Adoption</span>
                      </div>
                      <div className="absolute top-2 right-2">
                        <span className={`text-xs font-semibold px-2 py-0.5 rounded-full ${STATUT_COLOR[statut] ?? 'bg-gray-100 text-gray-500'}`}>
                          {STATUT_LABEL[statut] ?? statut}
                        </span>
                      </div>
                    </div>

                    <div className="p-4 flex-1 flex flex-col">
                      <h3 className="font-bold text-[#1E2025] text-[15px] truncate">
                        {a.titre ?? (`${a.espece ?? ''} ${a.race ?? ''}`.trim() || 'Sans titre')}
                      </h3>
                      <p className="text-gray-500 text-xs capitalize">{a.espece}{a.race ? ` · ${a.race}` : ''}</p>
                      <div className="flex items-center gap-3 mt-1.5 text-xs text-gray-500 tabular-nums">
                        <span className="inline-flex items-center gap-1"><Icone nom="oeil" taille={14} />{a.vues ?? 0}</span>
                        <span className="inline-flex items-center gap-1"><Icone nom="enveloppe" taille={14} />{a.contacts ?? 0}</span>
                        {a.created_at && <span className="ml-auto">{new Date(a.created_at).toLocaleDateString('fr-FR')}</span>}
                      </div>

                      <div className="flex gap-1.5 mt-3 pt-3 border-t border-[#EEF0EE]">
                        <Link href={`/annonces/${a.id}`}
                          className="flex-1 text-center text-xs bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold py-2 rounded-xl transition-colors">
                          Voir
                        </Link>
                        <Link href={`/association/annonces/creer?edit=${a.id}`}
                          className="flex-1 text-center text-xs border border-[#0C5C6C]/30 text-[#0C5C6C] hover:bg-[#E8F4F6] font-semibold py-2 rounded-xl transition-colors">
                          Modifier
                        </Link>
                        <button onClick={() => handlePause(a)}
                          title={statut === 'pause' ? 'Réactiver' : 'Mettre en pause'} aria-label={statut === 'pause' ? 'Réactiver' : 'Mettre en pause'}
                          className={`${btnIcone} ${statut === 'pause' ? 'border-[#2F7D3A] text-[#2F7D3A] hover:bg-[#EAF5EC]' : 'border-gray-200 text-gray-500 hover:border-[#0C5C6C]/40 hover:text-[#0C5C6C]'}`}>
                          <Icone nom={statut === 'pause' ? 'lecture' : 'pause'} taille={15} />
                        </button>
                        {(statut === 'expiree' || expiresWithinDays(a, 7)) && (
                          <button onClick={() => handleRenew(a)} title="Renouveler pour 30 jours" aria-label="Renouveler pour 30 jours"
                            className={`${btnIcone} border-orange-200 text-orange-700 hover:bg-orange-50`}>
                            <Icone nom="renouveler" taille={15} />
                          </button>
                        )}
                        <button onClick={() => handleDelete(a.id)} disabled={deleting === a.id} aria-label="Supprimer" title="Supprimer"
                          className={`${btnIcone} border-red-100 hover:bg-red-50 text-red-500 disabled:opacity-50`}>
                          <Icone nom="corbeille" taille={15} />
                        </button>
                      </div>
                    </div>
                  </div>
                );
              })}
            </div>
          )}
        </section>
      )}

      {voirMateriel && (
        <section>
          {typeFiltre === 'toutes' && <h2 className="text-lg font-bold text-[#1E2025] mb-3">Matériel & équipements</h2>}
          <MesAnnoncesMateriel statut={statutMateriel} onCompte={setNbMateriel} />
        </section>
      )}
    </div>
  );
}
