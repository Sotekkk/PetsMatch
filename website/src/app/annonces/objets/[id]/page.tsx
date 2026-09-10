'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useParams, useRouter } from 'next/navigation';
import { collection, addDoc, serverTimestamp } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import {
  ANNONCE_OBJET_TRANSACTIONS, ANNONCE_OBJET_ETATS, categorieEmoji, categorieLabel,
} from '@/lib/annonce-objet-categories';

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
        .from('user_profiles').select('id').eq('uid', a.uid)
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

  return (
    <div className="max-w-2xl mx-auto px-4 py-8 pb-16">
      <Link href="/annonces/objets" className="text-sm text-[#0C5C6C] hover:underline">← Petites annonces</Link>

      {photos.length > 0 && (
        <div className="mt-3">
          <div className="aspect-[4/3] bg-[#EEF3F0] rounded-2xl overflow-hidden">
            <img src={photos[photoIdx]} alt={a.titre} className="w-full h-full object-cover" />
          </div>
          {photos.length > 1 && (
            <div className="flex gap-2 mt-2 overflow-x-auto">
              {photos.map((p, i) => (
                <button key={p} onClick={() => setPhotoIdx(i)}
                  className={`w-16 h-16 rounded-lg overflow-hidden border-2 flex-shrink-0 ${i === photoIdx ? 'border-[#0C5C6C]' : 'border-transparent'}`}>
                  <img src={p} alt="" className="w-full h-full object-cover" />
                </button>
              ))}
            </div>
          )}
        </div>
      )}

      <div className="flex flex-wrap gap-2 mt-4">
        <span className="text-xs font-semibold px-2.5 py-1 rounded-full bg-[#0C5C6C]/10 text-[#0C5C6C]">
          {categorieEmoji(a.categorie)} {categorieLabel(a.categorie)}
        </span>
        <span className="text-xs font-semibold px-2.5 py-1 rounded-full bg-[#6E9E57]/10 text-[#6E9E57]">
          {ANNONCE_OBJET_TRANSACTIONS[a.type_transaction] ?? 'Vente'}
        </span>
        {a.etat && (
          <span className="text-xs font-semibold px-2.5 py-1 rounded-full bg-slate-100 text-slate-600">
            {ANNONCE_OBJET_ETATS[a.etat] ?? a.etat}
          </span>
        )}
      </div>

      <h1 className="text-2xl font-bold text-[#1F2A2E] mt-3" style={{ fontFamily: 'Galey, sans-serif' }}>{a.titre}</h1>
      <p className="text-xl font-bold text-[#0C5C6C] mt-1">{prixLabel(a)}</p>

      {a.description && <p className="text-[#2C3A40] text-sm leading-relaxed whitespace-pre-line mt-4">{a.description}</p>}

      <div className="text-sm text-gray-500 mt-4 space-y-1">
        {(a.ville || a.code_postal) && <p>📍 {[a.ville, a.code_postal].filter(Boolean).join(' · ')}</p>}
        <p>👤 {a.nom_vendeur ?? 'Particulier'}{a.created_at ? ` · ${new Date(a.created_at).toLocaleDateString('fr-FR')}` : ''}</p>
      </div>

      {isOwner ? (
        <Link href={`/annonces/creer-objet?edit=${a.id}`}
          className="block w-full text-center mt-6 py-3.5 rounded-2xl border border-[#0C5C6C] text-[#0C5C6C] font-bold hover:bg-[#E8F4F6] transition-colors">
          Modifier mon annonce
        </Link>
      ) : (
        <button onClick={contact} disabled={sending || sent}
          className="w-full mt-6 py-3.5 rounded-2xl text-white font-bold disabled:opacity-60"
          style={{ background: '#0C5C6C', fontFamily: 'Galey, sans-serif' }}>
          {sent ? '✓ Message envoyé' : sending ? 'Envoi…' : '💬 Contacter le vendeur'}
        </button>
      )}
    </div>
  );
}
