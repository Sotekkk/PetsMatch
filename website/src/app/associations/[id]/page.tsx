'use client';

import { useEffect, useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import Image from 'next/image';
import { collection, query, where, getDocs, addDoc, serverTimestamp } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface AssoProfile {
  uid: string;
  nom: string;
  avatar: string;
  banner?: string;
  ville: string;
  description: string;
  telephone?: string;
  site_web?: string;
  instagram?: string;
  facebook?: string;
}

interface Annonce {
  id: string;
  titre?: string;
  espece?: string;
  race?: string;
  photos?: string[];
  ville_eleveur?: string;
}

interface Animal {
  id: string;
  nom: string;
  espece?: string;
  race?: string;
  statut?: string;
  photo_url?: string;
}

export default function AssociationProfilePage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { user, activeProfileId } = useAuth();
  const [profile, setProfile] = useState<AssoProfile | null>(null);
  const [annonces, setAnnonces] = useState<Annonce[]>([]);
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [loading, setLoading] = useState(true);
  const [contacting, setContacting] = useState(false);

  useEffect(() => {
    if (!id) return;

    // Détecte si l'id est un UUID de profil Supabase (36 chars avec tirets)
    // ou un Firebase UID (alphanumérique sans tirets)
    const isProfileUUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id);

    type SecProfile = { id?: string; uid?: string; profile_type?: string; profile_label?: string; nom?: string; avatar_url?: string; banner_url?: string; ville?: string; description?: string; desc_entreprise?: string; phone?: string; telephone?: string; site_web?: string; instagram?: string; facebook?: string };

    const profileQ = isProfileUUID
      // UUID de profil : query directe par id (bypass RLS, le profil est connu)
      ? supabase.from('user_profiles')
          .select('id, uid, profile_type, profile_label, nom, avatar_url, banner_url, ville, description, desc_entreprise, phone, telephone, site_web, instagram, facebook')
          .eq('id', id).maybeSingle().then(r => ({ data: r.data ? [r.data] : [], uid: (r.data as SecProfile | null)?.uid ?? id }))
      // Firebase UID : query par uid sans filtre profile_type (filtre côté client)
      : supabase.from('user_profiles')
          .select('id, uid, profile_type, profile_label, nom, avatar_url, banner_url, ville, description, desc_entreprise, phone, telephone, site_web, instagram, facebook')
          .eq('uid', id).then(r => ({ data: r.data ?? [], uid: id }));

    profileQ.then(({ data: allProfiles, uid: ownerUid }) => {
      const profiles = allProfiles as SecProfile[];
      const sp = profiles.find(p => p.profile_type === 'association') ?? profiles[0] ?? null;
      const firebaseUid = ownerUid;

      Promise.all([
        supabase.from('users').select('name_elevage, profile_picture_url_elevage, banner_url, ville_elevage, description_elevage, phone').eq('uid', firebaseUid).maybeSingle(),
        supabase.from('annonces').select('id, titre, espece, race, photos, ville_eleveur').eq('uid_eleveur', firebaseUid).eq('profil_source', 'association').eq('statut', 'disponible').order('created_at', { ascending: false }),
        supabase.from('animaux').select('id, nom, espece, race, statut, photo_url').eq('uid_eleveur', firebaseUid).eq('is_association', true).eq('statut', 'disponible').order('nom'),
      ]).then(([{ data: userRow }, { data: ann }, { data: anim }]) => {
        const nom = (sp?.nom?.trim() || sp?.profile_label?.trim())
          ?? (userRow as { name_elevage?: string } | null)?.name_elevage ?? 'Association';
        const avatar = sp?.avatar_url
          ?? (userRow as { profile_picture_url_elevage?: string } | null)?.profile_picture_url_elevage ?? '';
        const banner = sp?.banner_url
          ?? (userRow as { banner_url?: string } | null)?.banner_url ?? undefined;
        const ville = sp?.ville ?? (userRow as { ville_elevage?: string } | null)?.ville_elevage ?? '';
        const description = (sp?.desc_entreprise || sp?.description)
          ?? (userRow as { description_elevage?: string } | null)?.description_elevage ?? '';
        const telephone = sp?.phone || sp?.telephone || (userRow as { phone?: string } | null)?.phone || '';

        setProfile({ uid: firebaseUid, nom, avatar, banner, ville, description,
          telephone: telephone || undefined,
          site_web: sp?.site_web, instagram: sp?.instagram, facebook: sp?.facebook,
        });
        setAnnonces((ann ?? []) as Annonce[]);
        setAnimaux((anim ?? []) as Animal[]);
        setLoading(false);
      });
    });
  }, [id]);

  const handleContact = async () => {
    if (!user) { router.push('/connexion'); return; }
    if (!id) return;
    setContacting(true);
    try {
      const participantIds = [user.uid, id].sort().join('_');
      const snap = await getDocs(query(
        collection(db, 'conversations'),
        where('participantIds', '==', participantIds)
      ));
      let convId: string;
      if (!snap.empty) {
        convId = snap.docs[0].id;
      } else {
        // Récupère le profil Supabase de l'association
        const { data: proProfile } = await supabase
          .from('user_profiles').select('id').eq('uid', id)
          .order('is_main', { ascending: false }).limit(1).maybeSingle();

        const ref = await addDoc(collection(db, 'conversations'), {
          participants: [user.uid, id].sort(),
          participantIds,
          lastMessage: '',
          timestamp: serverTimestamp(),
          categorie: 'communaute',
          ...(proProfile?.id ? { pro_profile_id: proProfile.id } : {}),
          ...(activeProfileId ? { consumer_profile_id: activeProfileId } : {}),
        });
        convId = ref.id;
      }
      router.push(`/messages?conv=${convId}`);
    } catch { setContacting(false); }
  };

  if (loading) {
    return (
      <div className="flex justify-center items-center min-h-screen">
        <div className="animate-spin rounded-full h-10 w-10 border-b-2 border-teal-700" />
      </div>
    );
  }

  if (!profile) {
    return (
      <div className="text-center py-24 text-gray-400 font-galey">
        <p className="text-5xl mb-4">🏠</p>
        <p>Association introuvable</p>
      </div>
    );
  }

  return (
    <div className="bg-[#F8F8F6] min-h-screen">
      {/* Banner + avatar overlay */}
      <div className="relative">
        <div className="h-52 sm:h-64 bg-[#EEF5EA] overflow-hidden relative">
          {profile.banner ? (
            <Image src={profile.banner} alt={profile.nom} fill className="object-cover" sizes="100vw" unoptimized />
          ) : profile.avatar ? (
            <Image src={profile.avatar} alt={profile.nom} fill className="object-cover brightness-75" sizes="100vw" unoptimized />
          ) : (
            <div className="w-full h-full flex items-center justify-center text-8xl">🏠</div>
          )}
          <div className="absolute inset-0 bg-gradient-to-b from-transparent to-black/40" />
        </div>

        {/* Photo profil en overlay */}
        <div className="absolute -bottom-10 left-5 sm:left-8 w-20 h-20 sm:w-24 sm:h-24 rounded-full border-4 border-white shadow-md bg-[#EEF5EA] overflow-hidden">
          {profile.avatar ? (
            <Image src={profile.avatar} alt={profile.nom} fill className="object-cover" sizes="96px" unoptimized />
          ) : (
            <div className="w-full h-full flex items-center justify-center text-4xl">🏠</div>
          )}
        </div>

        {/* Bouton retour */}
        <Link href="/associations"
          className="absolute top-4 left-4 bg-white/80 backdrop-blur-sm text-[#1F2A2E] rounded-full p-2 shadow hover:bg-white transition-colors">
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
        </Link>
      </div>

      {/* Contenu */}
      <div className="max-w-3xl mx-auto px-4 pt-14 pb-16 space-y-4">

        {/* Header nom + boutons */}
        <div className="bg-white rounded-2xl shadow-sm p-5">
          <div className="flex items-start justify-between gap-3 flex-wrap">
            <div>
              <div className="flex items-center gap-2 flex-wrap">
                <h1 className="font-['Galey'] font-bold text-2xl text-[#1F2A2E]">{profile.nom}</h1>
                <span className="text-xs bg-green-100 text-green-700 px-2 py-0.5 rounded-full">Association / Refuge</span>
              </div>
              {profile.ville && (
                <p className="text-gray-500 text-sm mt-0.5">📍 {profile.ville}</p>
              )}
            </div>
            {user?.uid !== id && (
              <div className="flex gap-2 flex-wrap">
                {profile.telephone && (
                  <a href={`tel:${profile.telephone}`}
                    className="flex items-center gap-1.5 border border-[#6E9E57] text-[#6E9E57] px-3 py-1.5 rounded-xl text-sm font-semibold hover:bg-[#EEF5EA] transition-colors">
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M3 5a2 2 0 012-2h3.28a1 1 0 01.948.684l1.498 4.493a1 1 0 01-.502 1.21l-2.257 1.13a11.042 11.042 0 005.516 5.516l1.13-2.257a1 1 0 011.21-.502l4.493 1.498a1 1 0 01.684.949V19a2 2 0 01-2 2h-1C9.716 21 3 14.284 3 6V5z" />
                    </svg>
                    Appeler
                  </a>
                )}
                <button
                  onClick={handleContact}
                  disabled={contacting}
                  className="flex items-center gap-1.5 bg-[#0C5C6C] hover:bg-[#094F5D] text-white px-4 py-1.5 rounded-xl text-sm font-semibold transition-colors disabled:opacity-60">
                  {contacting ? (
                    <span className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin inline-block" />
                  ) : (
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
                    </svg>
                  )}
                  Contacter
                </button>
              </div>
            )}
          </div>

          {profile.description && (
            <p className="mt-3 text-gray-600 text-sm leading-relaxed">{profile.description}</p>
          )}

          {/* Liens sociaux */}
          {(profile.site_web || profile.instagram || profile.facebook) && (
            <div className="mt-3 flex flex-wrap gap-2">
              {profile.site_web && (
                <a href={profile.site_web} target="_blank" rel="noopener noreferrer"
                  className="text-xs text-[#0C5C6C] border border-[#0C5C6C]/30 px-3 py-1 rounded-lg hover:bg-[#0C5C6C]/5 transition-colors">
                  🌐 Site web
                </a>
              )}
              {profile.instagram && (
                <a href={`https://instagram.com/${profile.instagram.replace('@','')}`} target="_blank" rel="noopener noreferrer"
                  className="text-xs text-[#0C5C6C] border border-[#0C5C6C]/30 px-3 py-1 rounded-lg hover:bg-[#0C5C6C]/5 transition-colors">
                  📸 Instagram
                </a>
              )}
              {profile.facebook && (
                <a href={profile.facebook.startsWith('http') ? profile.facebook : `https://facebook.com/${profile.facebook}`} target="_blank" rel="noopener noreferrer"
                  className="text-xs text-[#0C5C6C] border border-[#0C5C6C]/30 px-3 py-1 rounded-lg hover:bg-[#0C5C6C]/5 transition-colors">
                  👍 Facebook
                </a>
              )}
            </div>
          )}
        </div>

      {/* Annonces */}
      {annonces.length > 0 && (
        <section>
          <h2 className="text-xl font-bold font-galey text-teal-800 mb-4">
            Animaux à adopter <span className="text-sm font-normal text-gray-400 ml-2">{annonces.length}</span>
          </h2>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-4">
            {annonces.map((a) => (
              <Link key={a.id} href={`/annonces/${a.id}`}
                className="bg-white rounded-2xl overflow-hidden shadow-sm border border-gray-100 hover:border-teal-200 hover:shadow-md transition-all group">
                <div className="aspect-square bg-gray-100 relative overflow-hidden">
                  {a.photos?.[0] ? (
                    <Image src={a.photos[0]} alt={a.titre ?? 'Animal'} fill
                      className="object-cover group-hover:scale-105 transition-transform duration-300" unoptimized />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center text-3xl text-gray-300">🐾</div>
                  )}
                  <div className="absolute top-2 left-2 bg-teal-700/90 text-white text-xs font-galey font-semibold px-2 py-0.5 rounded-full">
                    Adoption
                  </div>
                </div>
                <div className="p-3">
                  <p className="font-bold font-galey text-sm text-gray-900 truncate">{a.titre ?? 'Animal à adopter'}</p>
                  {a.race && <p className="text-xs text-gray-500 font-galey">{a.race}</p>}
                  {a.ville_eleveur && <p className="text-xs text-gray-400 font-galey">📍 {a.ville_eleveur}</p>}
                </div>
              </Link>
            ))}
          </div>
        </section>
      )}

      {/* Animaux du refuge */}
      {animaux.length > 0 && (
        <section>
          <h2 className="text-xl font-bold font-galey text-teal-800 mb-4">
            Animaux au refuge <span className="text-sm font-normal text-gray-400 ml-2">{animaux.length}</span>
          </h2>
          <div className="grid grid-cols-3 md:grid-cols-4 gap-3">
            {animaux.map((a) => (
              <div key={a.id} className="bg-white rounded-xl overflow-hidden shadow-sm border border-gray-100">
                <div className="aspect-square bg-gray-100 relative overflow-hidden">
                  {a.photo_url ? (
                    <Image src={a.photo_url} alt={a.nom} fill className="object-cover" unoptimized />
                  ) : (
                    <div className="w-full h-full flex items-center justify-center text-2xl text-gray-300">🐾</div>
                  )}
                </div>
                <div className="p-2">
                  <p className="font-bold font-galey text-xs text-gray-900 truncate">{a.nom}</p>
                  <p className="text-xs text-gray-400 font-galey truncate">{a.race ?? a.espece}</p>
                </div>
              </div>
            ))}
          </div>
        </section>
      )}

      {annonces.length === 0 && animaux.length === 0 && (
        <div className="text-center py-12 text-gray-400 font-galey">
          <p className="text-4xl mb-3">🐾</p>
          <p>Aucun animal disponible pour le moment</p>
        </div>
      )}

      <div className="text-center pt-4">
        <Link href="/adoptions" className="text-teal-600 font-galey text-sm hover:underline">
          ← Voir toutes les adoptions
        </Link>
      </div>
    </div>
  </div>
  );

}
