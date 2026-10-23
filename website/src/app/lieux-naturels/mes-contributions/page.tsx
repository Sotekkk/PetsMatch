'use client';

// Mes contributions aux lieux naturels : lieux proposés (statut, motif du
// refus), photos et équipements proposés. Même règle que les lieux
// pet-friendly : l'auteur modifie ou supprime son lieu tant qu'il n'est pas
// publié ; ensuite il propose photos / équipements depuis la fiche, et la
// suppression revient à l'équipe PetsMatch.
// Miroir appli : lib/pages/nature/mes_contributions_nature_page.dart.

import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

type Ligne = Record<string, unknown> & { id: string; statut: string; created_at: string; place?: { id?: string; nom?: string } | null };

const STATUTS: Record<string, [string, string]> = {
  en_attente: ['En attente de validation', 'text-[#B45309] bg-[#FEF3C7]'],
  valide: ['Publié', 'text-[#166534] bg-[#DCFCE7]'],
  refuse: ['Non publié', 'text-[#B91C1C] bg-[#FEE2E2]'],
};

const EQUIPEMENTS: Record<string, string> = {
  has_eau: 'Eau potable', has_parking: 'Parking', has_fontaine: 'Fontaine',
  has_poubelle: 'Poubelles', parcours_ombre: 'Parcours ombragé', baignade_possible: 'Baignade',
};

export default function MesContributionsNaturePage() {
  const { user, loading } = useAuth();
  const [lieux, setLieux] = useState<Ligne[]>([]);
  const [photos, setPhotos] = useState<Ligne[]>([]);
  const [equipements, setEquipements] = useState<Ligne[]>([]);
  const [charge, setCharge] = useState(false);
  const [renvoye, setRenvoye] = useState(false);

  useEffect(() => { setRenvoye(new URLSearchParams(window.location.search).has('renvoye')); }, []);

  const charger = useCallback(() => {
    if (!user) return;
    Promise.all([
      supabase.from('natural_places').select('*').eq('submitted_by_uid', user.uid).order('created_at', { ascending: false }),
      supabase.from('natural_place_photo_suggestions').select('*, place:natural_places(id, nom)').eq('submitted_by_uid', user.uid).order('created_at', { ascending: false }),
      supabase.from('natural_place_amenity_suggestions').select('*, place:natural_places(id, nom)').eq('submitted_by_uid', user.uid).order('created_at', { ascending: false }),
    ]).then(([a, b, c]) => {
      setLieux((a.data ?? []) as Ligne[]); setPhotos((b.data ?? []) as Ligne[]); setEquipements((c.data ?? []) as Ligne[]);
      setCharge(true);
    });
  }, [user]);
  useEffect(() => { charger(); }, [charger]);

  async function supprimer(table: string, id: string, question: string) {
    if (!window.confirm(question)) return;
    // .select() : une suppression refusée par la base ne renvoie aucune ligne.
    const { data, error } = await supabase.from(table).delete().eq('id', id).select('id');
    if (error || !data?.length) alert('Suppression impossible : ce contenu a peut-être déjà été validé.');
    charger();
  }

  if (loading) return null;
  if (!user) {
    return (
      <div className="max-w-xl mx-auto px-4 py-16 text-center" style={{ fontFamily: 'Galey, sans-serif' }}>
        <Link href="/connexion?suite=/lieux-naturels/mes-contributions" className="inline-block px-5 py-2.5 rounded-xl bg-[#0C5C6C] text-white font-semibold">Se connecter</Link>
      </div>
    );
  }

  const pastille = (st: string) => {
    const [l, c] = STATUTS[st] ?? [st, 'text-gray-600 bg-gray-100'];
    return <span className={`text-[11px] font-bold px-2 py-0.5 rounded-full flex-shrink-0 ${c}`}>{l}</span>;
  };
  const date = (d: unknown) => (d ? new Date(String(d)).toLocaleDateString('fr-FR') : '');
  const boutonSupprimer = (onClick: () => void) => (
    <button type="button" onClick={onClick} className="px-4 py-2 rounded-xl border border-red-200 text-red-600 text-sm font-bold hover:bg-red-50">Supprimer</button>
  );
  const carte = (titre: string, sous: string, st: string, motif: unknown, photo: unknown, actions?: React.ReactNode) => (
    <div className="bg-white rounded-2xl shadow-sm p-4">
      <div className="flex items-start gap-3">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        {photo ? <img src={String(photo)} alt="" className="w-11 h-11 rounded-lg object-cover flex-shrink-0" /> : null}
        <p className="font-bold text-[#1F2A2E] flex-1 min-w-0">{titre}</p>{pastille(st)}
      </div>
      <p className="text-xs text-gray-500 mt-0.5">{sous}</p>
      {motif ? <p className="text-sm text-gray-700 mt-2">Motif de la modération : {String(motif)}</p> : null}
      {actions && <div className="mt-3 flex gap-2 flex-wrap">{actions}</div>}
    </div>
  );

  return (
    <div className="bg-[#F4F7F6] min-h-screen pb-16" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="bg-[#0C5C6C] text-white"><div className="max-w-2xl mx-auto px-4 py-6"><h1 className="text-2xl font-bold">Mes contributions</h1>
        <p className="text-white/75 text-sm">Lieux naturels proposés, photos et équipements.</p></div></div>
      <div className="max-w-2xl mx-auto px-4 pt-6 space-y-3">
        {renvoye && <p className="text-sm text-[#166534] bg-[#DCFCE7] rounded-xl px-3 py-2">Modifications envoyées : ton lieu sera revu par un admin (sous 48h).</p>}
        {!charge && <p className="text-sm text-gray-500">Chargement…</p>}
        <h2 className="text-lg font-bold text-[#1F2A2E] pt-2">Lieux proposés</h2>
        {charge && lieux.length === 0 && <p className="text-sm text-gray-500">Vous n&apos;avez pas encore proposé de lieu. <Link href="/lieux-naturels/proposer" className="text-[#0C5C6C] font-semibold">Proposer un lieu</Link></p>}
        {lieux.map(l => <div key={l.id}>{carte(String(l.nom ?? ''),
          `${l.adresse ? `${String(l.adresse)} · ` : ''}proposé le ${date(l.created_at)}`, l.statut,
          l.statut === 'refuse' ? l.rejection_reason : null, l.photo_url,
          l.statut !== 'valide'
            ? <>
                <Link href={`/lieux-naturels/proposer?edit=${l.id}`} className="px-4 py-2 rounded-xl bg-[#0C5C6C] text-white text-sm font-bold">{l.statut === 'refuse' ? 'Modifier et renvoyer' : 'Modifier'}</Link>
                {boutonSupprimer(() => supprimer('natural_places', l.id, `Supprimer « ${String(l.nom ?? '')} » ? Cette action est définitive.`))}
              </>
            : <Link href={`/lieux-naturels/${l.id}`} className="px-4 py-2 rounded-xl border border-[#0C5C6C] text-[#0C5C6C] text-sm font-bold">Voir la fiche</Link>)}</div>)}
        {lieux.some(l => l.statut === 'valide') && (
          <p className="text-xs text-gray-500 px-1">
            Un lieu publié ne se modifie plus directement : proposez une photo ou un équipement depuis sa fiche. Pour le faire retirer, contactez l&apos;équipe PetsMatch.
          </p>
        )}
        <h2 className="text-lg font-bold text-[#1F2A2E] pt-4">Photos proposées</h2>
        {charge && photos.length === 0 && <p className="text-sm text-gray-500">Aucune photo proposée.</p>}
        {photos.map(p => <div key={p.id}>{carte(p.place?.nom ?? 'Lieu', `Proposée le ${date(p.created_at)}`, p.statut,
          p.statut === 'refuse' ? p.rejection_reason : null, p.photo_url,
          p.statut === 'en_attente' ? boutonSupprimer(() => supprimer('natural_place_photo_suggestions', p.id, 'Retirer cette photo ? Elle ne sera pas proposée à la modération.')) : undefined)}</div>)}
        <h2 className="text-lg font-bold text-[#1F2A2E] pt-4">Équipements proposés</h2>
        {charge && equipements.length === 0 && <p className="text-sm text-gray-500">Aucun équipement proposé.</p>}
        {equipements.map(e => {
          const valeur = e.value === true ? 'oui' : e.value === false ? 'non' : String(e.value ?? '');
          return <div key={e.id}>{carte(e.place?.nom ?? 'Lieu',
            `${EQUIPEMENTS[String(e.field)] ?? String(e.field)} : ${valeur} · proposé le ${date(e.created_at)}`, e.statut,
            e.statut === 'refuse' ? e.rejection_reason : null, e.photo_url,
            e.statut === 'en_attente' ? boutonSupprimer(() => supprimer('natural_place_amenity_suggestions', e.id, 'Retirer cette proposition ? L’équipement ne sera pas proposé à la modération.')) : undefined)}</div>;
        })}
      </div>
    </div>
  );
}
