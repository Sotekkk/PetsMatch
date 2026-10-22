'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useParams, useRouter } from 'next/navigation';
import { collection, addDoc, serverTimestamp } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import {
  ANNONCE_OBJET_TRANSACTIONS, ANNONCE_OBJET_ETATS, categorieLabel,
} from '@/lib/annonce-objet-categories';
import { Icone, Puce, BORDURE } from '@/components/dashboard/kit';
import { TEINTES_STATUT } from '@/components/annonces/GestionAnnonces';

interface AnnonceObjet {
  id: string;
  uid: string;
  profile_id: string | null;
  titre: string;
  categorie: string;
  type_transaction: string;
  prix: number | null;
  prix_unite: string | null;
  prix_negociable: boolean | null;
  etat: string | null;
  description: string | null;
  photos: string[] | null;
  ville: string | null;
  code_postal: string | null;
  nom_vendeur: string | null;
  statut: string | null;
  created_at: string | null;
}

function prixLabel(a: AnnonceObjet): string {
  if (a.type_transaction === 'don') return 'Don';
  if (a.type_transaction === 'recherche') return 'Recherche';
  if (a.prix == null) return 'Prix à convenir';
  return `${Math.round(a.prix)} €${a.prix_unite ?? ''}${a.prix_negociable ? ' (négociable)' : ''}`;
}

export default function AnnonceObjetDetailPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { user, activeProfileId } = useAuth();
  const [a, setA] = useState<AnnonceObjet | null>(null);
  const [loading, setLoading] = useState(true);
  const [photoIdx, setPhotoIdx] = useState(0);
  const [sending, setSending] = useState(false);
  const [sent, setSent] = useState(false);

  useEffect(() => {
    supabase.from('annonces_objets').select('*').eq('id', id).maybeSingle().then(({ data }) => {
      setA(data as AnnonceObjet | null);
      setLoading(false);
      if (data && data.uid !== user?.uid) {
        supabase.from('annonces_objets').update({ vues: (data.vues ?? 0) + 1 }).eq('id', id);
      }
    });
  }, [id, user?.uid]);

  if (loading) return <div className="py-32 text-center text-gray-400">Chargement…</div>;
  if (!a) return <div className="py-32 text-center text-gray-400">Annonce introuvable.</div>;

  const isOwner = !!user && a.uid === user.uid
    && (!a.profile_id || !activeProfileId || a.profile_id === activeProfileId);
  const photos = a.photos ?? [];

  async function contact() {
    if (!user) { router.push('/connexion'); return; }
    if (!a) return;
    setSending(true);
    try {
      supabase.from('annonces_objets').select('contacts').eq('id', a.id).maybeSingle()
        .then(({ data }) => data && supabase.from('annonces_objets')
          .update({ contacts: (data.contacts ?? 0) + 1 }).eq('id', a.id));
      const { data: sellerProfile } = await supabase
        .from('user_profiles_complet').select('id').eq('uid', a.uid)
        .order('is_main', { ascending: false }).limit(1).maybeSingle();
      const participants = [user.uid, a.uid].sort();
      const convId = participants.join('_') + '_objet_' + a.id;
      const msg = `Bonjour, je suis intéressé(e) par votre annonce : ${a.titre}`;
      await addDoc(collection(db, 'conversations'), {
        id: convId, participants, lastMessage: msg, timestamp: serverTimestamp(),
        unreadCount: { [a.uid]: 1 }, categorie: 'annonces-materiel',
        ...(sellerProfile?.id ? { pro_profile_id: sellerProfile.id } : {}),
        ...(activeProfileId ? { consumer_profile_id: activeProfileId } : {}),
      });
      await addDoc(collection(db, 'conversations', convId, 'messages'), {
        text: msg, senderId: user.uid, timestamp: serverTimestamp(), isRead: false,
      });
      setSent(true);
      router.push('/messages');
    } catch { setSending(false); }
  }

  const statut = a.statut === 'pause' ? { label: 'En pause', t: TEINTES_STATUT.gris } : { label: 'En ligne', t: TEINTES_STATUT.vert };
  const bouton = 'inline-flex items-center justify-center gap-2 rounded-xl text-sm font-semibold transition-colors min-h-11 px-4';

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-6xl mx-auto px-4 sm:px-6 py-5 sm:py-8">
        <Link href="/annonces/objets" className="inline-flex items-center gap-1.5 text-sm font-semibold text-[#0C5C6C] hover:underline mb-4">
          <span className="rotate-180 inline-flex"><Icone nom="fleche" taille={16} /></span> Matériel & équipements
        </Link>

        <div className="grid grid-cols-1 lg:grid-cols-[minmax(0,1.1fr)_minmax(0,1fr)] gap-5 lg:gap-8 items-start">
          {/* Galerie */}
          <div className="min-w-0">
            {photos.length > 0 ? (
              <>
                <div className="aspect-[4/3] bg-[#EEF1EF] rounded-2xl overflow-hidden">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={photos[photoIdx]} alt={a.titre} className="w-full h-full object-contain" />
                </div>
                {photos.length > 1 && (
                  <div className="grid grid-cols-4 sm:grid-cols-5 gap-2 mt-3">
                    {photos.map((p, i) => (
                      <button key={p} onClick={() => setPhotoIdx(i)} aria-label={`Photo ${i + 1}`}
                        className={`aspect-[4/3] rounded-xl overflow-hidden bg-[#EEF1EF] ${i === photoIdx ? 'ring-2 ring-[#0C5C6C] ring-offset-2' : 'opacity-80 hover:opacity-100'}`}>
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        <img src={p} alt="" className="w-full h-full object-cover" />
                      </button>
                    ))}
                  </div>
                )}
              </>
            ) : (
              <div className="aspect-[4/3] bg-[#EEF1EF] rounded-2xl flex items-center justify-center text-[#0C5C6C]"><Icone nom="caisse" taille={56} /></div>
            )}
          </div>

          {/* Résumé, vendeur, informations */}
          <div className="min-w-0 space-y-4">
            <div>
              <div className="flex items-start justify-between gap-4">
                <h1 className="text-[28px] sm:text-4xl font-bold text-[#1E2025] leading-tight break-words min-w-0">{a.titre}</h1>
                <p className="text-2xl sm:text-3xl font-bold text-[#0C5C6C] tabular-nums text-right flex-shrink-0">{prixLabel(a)}</p>
              </div>
              <p className="text-base text-gray-600 mt-1">{[categorieLabel(a.categorie), a.ville].filter(Boolean).join(' · ')}</p>
              <div className="flex flex-wrap items-center gap-2 mt-3">
                <Puce texte={statut.label} fg={statut.t.fg} bg={statut.t.bg} point />
                <Puce texte={ANNONCE_OBJET_TRANSACTIONS[a.type_transaction] ?? 'Vente'} fg="#41525A" bg="#FFFFFF" />
              </div>
            </div>

            {/* Vendeur : contact jamais proposé au propriétaire (la gestion est dans « Mes annonces »). */}
            <section className="bg-white rounded-2xl p-5" style={{ border: `1px solid ${BORDURE}` }}>
              <p className="text-sm font-semibold text-gray-500 mb-1">Vendeur</p>
              <p className="font-bold text-lg text-[#1E2025]">{a.nom_vendeur ?? 'Particulier'}</p>
              {(a.ville || a.code_postal) && <p className="text-sm text-gray-500 inline-flex items-center gap-1"><Icone nom="pin" taille={14} />{[a.ville, a.code_postal].filter(Boolean).join(' · ')}</p>}
              {!isOwner && (
                <button onClick={contact} disabled={sending || sent}
                  className={`${bouton} w-full mt-4 bg-[#0C5C6C] hover:bg-[#094F5D] text-white disabled:opacity-60`}>
                  <Icone nom="enveloppe" taille={17} />
                  {!user ? 'Se connecter pour contacter' : sent ? 'Message envoyé' : sending ? 'Envoi…' : 'Contacter le vendeur'}
                </button>
              )}
            </section>

            <section className="bg-white rounded-2xl p-5" style={{ border: `1px solid ${BORDURE}` }}>
              <h2 className="font-bold text-lg text-[#1E2025] mb-1">Informations</h2>
              <dl className="text-[15px]">
                {[
                  ['Catégorie', categorieLabel(a.categorie)],
                  ['Transaction', ANNONCE_OBJET_TRANSACTIONS[a.type_transaction] ?? 'Vente'],
                  ['État', a.etat ? (ANNONCE_OBJET_ETATS[a.etat] ?? a.etat) : null],
                  ['Lieu', [a.ville, a.code_postal].filter(Boolean).join(' · ') || null],
                  ['Publiée le', a.created_at ? new Date(a.created_at).toLocaleDateString('fr-FR') : null],
                ].filter(([, v]) => v).map(([k, v]) => (
                  <div key={k} className="grid grid-cols-[minmax(0,9rem)_1fr] gap-3 py-1.5">
                    <dt className="text-gray-500">{k}</dt><dd className="text-[#1E2025] break-words">{v}</dd>
                  </div>
                ))}
              </dl>
            </section>
          </div>
        </div>

        {a.description && (
          <section className="bg-white rounded-2xl p-5 sm:p-6 mt-6 sm:mt-8" style={{ border: `1px solid ${BORDURE}` }}>
            <h2 className="font-bold text-lg sm:text-xl text-[#1E2025] mb-3">Description</h2>
            <p className="text-[15px] text-[#41525A] leading-relaxed whitespace-pre-line">{a.description}</p>
          </section>
        )}
      </div>
    </div>
  );
}
