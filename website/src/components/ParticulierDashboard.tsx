'use client';
/* eslint-disable @next/next/no-img-element */

// Accueil du particulier (refonte UX, maquette « Site — page d'accueil du
// particulier ») : une vraie page d'accueil grand public — recherche, accès
// rapides, mes compagnons, à découvrir, communauté, perdus et trouvés.
// Rien de nouveau côté données : mêmes tables, animaux scopés par profil.

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

interface Animal { id: string; nom?: string; espece?: string; race?: string; photo_url?: string }
interface Annonce {
  id: string; titre?: string; espece?: string; race?: string; type_vente?: string;
  photos?: string[]; prix?: number; prix_min_portee?: number; ville_eleveur?: string;
}
interface Pro { id: string; uid: string; nom?: string; avatar_url?: string; banner_url?: string; profession_pro?: string; ville_pro?: string; ville?: string }
interface Balade { id: string; titre: string; ville?: string; cover_url?: string }
interface Sujet { id: string; titre: string; categorie_slug: string; animal_types?: string[] | null; animal_type?: string | null; race?: string | null }

type Onglet = 'annonces' | 'adoptions' | 'pros' | 'activites';

const ESPECES: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', cheval: 'Cheval', lapin: 'Lapin', oiseau: 'Oiseau',
  nac: 'NAC', ovin: 'Ovin', caprin: 'Caprin', porcin: 'Porc', autre: 'Autre',
};
const espece = (e?: string | null) => (e ? ESPECES[e] ?? e : '');

// Pictogrammes sobres (trait), pas d'emojis.
function Picto({ d, couleur = '#0C5C6C' }: { d: string; couleur?: string }) {
  return (
    <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke={couleur} strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d={d} />
    </svg>
  );
}
const P = {
  coeur: 'M12 20s-7-4.4-7-10a4 4 0 017-2.6A4 4 0 0119 10c0 5.6-7 10-7 10z',
  pro: 'M4 9h16v11H4zM9 9V6h6v3M12 12.5v4.5M9.8 14.8h4.4',
  groupe: 'M9 11a3 3 0 100-6 3 3 0 000 6zM3 19c0-3 3-5 6-5s6 2 6 5M17 11.5a2.5 2.5 0 100-5M15.5 14.5c3 0 5.5 1.5 5.5 4.5',
  lieu: 'M12 21s-6-6.2-6-11a6 6 0 1112 0c0 4.8-6 11-6 11zM12 12a2 2 0 100-4 2 2 0 000 4z',
  loupe: 'M11 17a6 6 0 100-12 6 6 0 000 12zM20 20l-4.5-4.5M11 8v3M11 13.5v.01',
  boite: 'M4 8l8-4 8 4v8l-8 4-8-4zM4 8l8 4 8-4M12 12v8',
  plus: 'M12 5v14M5 12h14',
  chevron: 'M9 6l6 6-6 6',
};

const ACCES = [
  { href: '/annonces?type=adoption', label: 'Adopter un animal', d: P.coeur, fond: 'bg-[#E7F1EF]' },
  { href: '/services', label: 'Trouver un professionnel', d: P.pro, fond: 'bg-[#E7F1EF]' },
  { href: '/communaute', label: 'Communauté', d: P.groupe, fond: 'bg-[#E7F1EF]' },
  { href: '/balades-ludiques', label: 'Balades et événements', d: P.lieu, fond: 'bg-[#EEF5EA]', couleur: '#4E7A3B' },
  { href: '/animaux-perdus', label: 'Perdus et trouvés', d: P.loupe, fond: 'bg-[#FDF1E4]', couleur: '#A85A12' },
  { href: '/annonces/objets', label: 'Matériel et équipements', d: P.boite, fond: 'bg-[#E7F1EF]' },
];

function prixAnnonce(a: Annonce) {
  const p = a.prix ?? a.prix_min_portee;
  if (p == null) return null;
  return a.type_vente === 'adoption' ? `Frais d'adoption : ${p} €` : `${a.prix == null ? 'À partir de ' : ''}${p} €`;
}

function libelleSujet(s: Sujet) {
  const liste = s.animal_types?.length ? s.animal_types : s.animal_type ? [s.animal_type] : [];
  const anim = liste.length >= Object.keys(ESPECES).length ? 'Toutes espèces' : liste.map(espece).join(', ');
  return [anim, s.race].filter(Boolean).join(' · ');
}

export default function ParticulierDashboard() {
  const { user, userData, loading: authLoading, activeProfileId } = useAuth();
  const router = useRouter();
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [nbAlertes, setNbAlertes] = useState(0);
  const [annonces, setAnnonces] = useState<Annonce[]>([]);
  const [adoptions, setAdoptions] = useState<Annonce[]>([]);
  const [pros, setPros] = useState<Pro[]>([]);
  const [balades, setBalades] = useState<Balade[]>([]);
  const [sujets, setSujets] = useState<Sujet[]>([]);
  const [onglet, setOnglet] = useState<Onglet>('annonces');
  const [recherche, setRecherche] = useState('');
  const [rechercheDans, setRechercheDans] = useState<'pros' | 'annonces'>('pros');
  const [loading, setLoading] = useState(true);

  const firstname = userData?.firstname ?? '';

  useEffect(() => {
    if (!user || authLoading) return;
    const uid = user.uid;

    async function load() {
      // Animaux détenus par CE profil (jamais ceux d'un autre profil du compte).
      let q = supabase.from('animaux_proprietes').select('animal_id').eq('uid_proprio', uid).is('date_fin', null);
      if (activeProfileId) q = q.eq('profile_id_proprio', activeProfileId);
      const { data: rows } = await q;
      const animalIds = (rows ?? []).map(r => r.animal_id as string);

      let alertesQ = supabase.from('alertes_perdus').select('id', { count: 'exact', head: true })
        .eq('uid_proprietaire', uid).eq('statut', 'perdu');
      if (activeProfileId) alertesQ = alertesQ.eq('profile_id', activeProfileId);

      const colsAnnonce = 'id, titre, espece, race, type_vente, photos, prix, prix_min_portee, ville_eleveur';
      const [animauxRes, alertesRes, annoncesRes, adoptionsRes, prosRes, baladesRes, sujetsRes] = await Promise.all([
        animalIds.length
          ? supabase.from('animaux').select('id, nom, espece, race, photo_url').in('id', animalIds)
          : Promise.resolve({ data: [] }),
        alertesQ,
        supabase.from('annonces').select(colsAnnonce).eq('statut', 'disponible').neq('type_vente', 'adoption')
          .order('created_at', { ascending: false }).limit(4),
        supabase.from('annonces').select(colsAnnonce).eq('statut', 'disponible').eq('type_vente', 'adoption')
          .order('created_at', { ascending: false }).limit(4),
        supabase.from('user_profiles_complet').select('id, uid, nom, avatar_url, banner_url, profession_pro, ville_pro, ville')
          .not('profile_type', 'is', null).not('profile_type', 'in', '(eleveur,association,particulier)')
          .in('statut_pro', ['actif', 'validated']).order('created_at', { ascending: false }).limit(4),
        supabase.from('balades_ludiques').select('id, titre, ville, cover_url').eq('statut', 'publie')
          .order('created_at', { ascending: false }).limit(4),
        supabase.from('forum_sujets').select('id, titre, categorie_slug, animal_types, animal_type, race')
          .order('created_at', { ascending: false }).limit(3),
      ]);
      setAnimaux((animauxRes.data ?? []) as Animal[]);
      setNbAlertes(alertesRes.count ?? 0);
      setAnnonces((annoncesRes.data ?? []) as Annonce[]);
      setAdoptions((adoptionsRes.data ?? []) as Annonce[]);
      setPros((prosRes.data ?? []) as Pro[]);
      setBalades((baladesRes.data ?? []) as Balade[]);
      setSujets((sujetsRes.data ?? []) as Sujet[]);
      setLoading(false);
    }

    load().catch(() => setLoading(false));
  }, [user, authLoading, activeProfileId]);

  function rechercher(e: React.FormEvent) {
    e.preventDefault();
    const t = recherche.trim();
    if (rechercheDans === 'pros') router.push(t ? `/services?q=${encodeURIComponent(t)}` : '/services');
    else router.push(t ? `/annonces?race=${encodeURIComponent(t)}` : '/annonces');
  }

  const carte = 'bg-white rounded-2xl overflow-hidden shadow-[0_1px_4px_rgba(15,40,45,0.08)] hover:shadow-md transition-shadow';
  const titreSection = 'text-[22px] font-extrabold text-[#1F2A2E]';
  const voirTout = 'text-sm font-bold text-[#0C5C6C] hover:underline';

  const ONGLETS: { cle: Onglet; label: string; voir: { href: string; label: string } }[] = [
    { cle: 'annonces', label: 'Annonces', voir: { href: '/annonces', label: 'Voir toutes les annonces' } },
    { cle: 'adoptions', label: 'Adoptions', voir: { href: '/annonces?type=adoption', label: 'Voir toutes les adoptions' } },
    { cle: 'pros', label: 'Professionnels', voir: { href: '/services', label: 'Voir l\'annuaire' } },
    { cle: 'activites', label: 'Activités', voir: { href: '/balades-ludiques', label: 'Voir toutes les balades' } },
  ];
  const ongletActif = ONGLETS.find(o => o.cle === onglet)!;

  function CarteAnnonce({ a }: { a: Annonce }) {
    const photo = a.photos?.[0];
    const adoption = a.type_vente === 'adoption';
    return (
      <Link href={`/annonces/${a.id}`} className={carte}>
        <div className="h-[170px] bg-[#DCE8E5] relative">
          {photo && <img src={photo} alt="" className="w-full h-full object-cover" />}
          <span className={`absolute top-2.5 left-2.5 text-white text-[11px] font-bold px-2.5 py-0.5 rounded-full ${adoption ? 'bg-[#6E9E57]' : 'bg-[#0C5C6C]'}`}>
            {adoption ? 'Adoption' : 'Vente'}
          </span>
        </div>
        <div className="px-3.5 py-3">
          <p className="font-extrabold text-[15px] text-[#1F2A2E] truncate">{a.titre || [espece(a.espece), a.race].filter(Boolean).join(' · ')}</p>
          <p className="text-[13px] text-gray-500 truncate">{[a.race || espece(a.espece), a.ville_eleveur].filter(Boolean).join(' · ')}</p>
          {prixAnnonce(a) && <p className={`mt-2 text-[15px] font-extrabold ${adoption ? 'text-[#4E7A3B]' : 'text-[#0C5C6C]'}`}>{prixAnnonce(a)}</p>}
        </div>
      </Link>
    );
  }

  const vide = (texte: string) => <p className="col-span-full text-sm text-gray-500 bg-white rounded-2xl p-6 text-center">{texte}</p>;

  return (
    <div className="bg-[#F4F7F6] min-h-screen pb-16">
      {/* Zone 1 — accueil et recherche */}
      <section className="bg-[#0C5C6C] px-4 pt-12 pb-20">
        <div className="max-w-3xl mx-auto text-center flex flex-col items-center gap-3">
          <h1 className="text-white text-3xl md:text-[40px] font-extrabold leading-tight" style={{ fontFamily: 'Galey, sans-serif' }}>
            {firstname ? `Bienvenue ${firstname}, dans votre univers animalier` : 'Bienvenue dans votre univers animalier'}
          </h1>
          <p className="text-white/80 text-base md:text-lg">Découvrez, partagez et trouvez les services adaptés à vos compagnons.</p>
          <form onSubmit={rechercher} className="mt-4 w-full flex flex-col sm:flex-row items-stretch gap-2 bg-white rounded-2xl p-2 shadow-[0_10px_30px_rgba(0,0,0,0.18)]">
            <label htmlFor="recherche-accueil" className="sr-only">Rechercher</label>
            <div className="flex items-center gap-2 flex-1 pl-3">
              <Picto d="M11 17a6 6 0 100-12 6 6 0 000 12zM20 20l-3.5-3.5" couleur="#5E6B70" />
              <input id="recherche-accueil" value={recherche} onChange={e => setRecherche(e.target.value)}
                placeholder={rechercheDans === 'pros' ? 'Un professionnel, une ville…' : 'Une race…'}
                className="flex-1 min-w-0 py-2.5 text-base outline-none text-[#1F2A2E]" />
            </div>
            <label htmlFor="recherche-dans" className="sr-only">Rechercher dans</label>
            <select id="recherche-dans" value={rechercheDans} onChange={e => setRechercheDans(e.target.value as 'pros' | 'annonces')}
              className="rounded-xl border border-gray-200 px-3 py-2.5 text-sm text-[#1F2A2E] bg-white">
              <option value="pros">Professionnels</option>
              <option value="annonces">Annonces</option>
            </select>
            <button type="submit" className="rounded-xl bg-[#6E9E57] hover:bg-[#5E8A4A] text-white font-bold px-6 py-2.5">Rechercher</button>
          </form>
        </div>
      </section>

      {/* Zone 2 — accès rapides */}
      <section className="max-w-6xl mx-auto px-4 -mt-10 grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3.5">
        {ACCES.map(a => (
          <Link key={a.href} href={a.href}
            className="bg-white rounded-2xl px-3 py-5 flex flex-col items-center gap-2.5 text-center text-sm font-bold text-[#1F2A2E] shadow-[0_2px_8px_rgba(15,40,45,0.08)] hover:shadow-md transition-shadow">
            <span className={`w-12 h-12 rounded-[14px] flex items-center justify-center ${a.fond}`}><Picto d={a.d} couleur={a.couleur} /></span>
            {a.label}
          </Link>
        ))}
      </section>

      {loading ? (
        <div className="flex justify-center py-16"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>
      ) : (
        <>
          {/* Zone 3 — mes compagnons */}
          <section className="max-w-6xl mx-auto px-4 mt-12">
            <div className="flex items-baseline justify-between mb-4">
              <h2 className={titreSection}>Mes compagnons</h2>
              <Link href="/mes-animaux" className={voirTout}>Voir tous mes animaux</Link>
            </div>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              {animaux.slice(0, 3).map(a => (
                <Link key={a.id} href={`/mes-animaux/${a.id}`} className={carte}>
                  <div className="h-[150px] bg-[#DCE8E5]">{a.photo_url && <img src={a.photo_url} alt="" className="w-full h-full object-cover" />}</div>
                  <div className="px-3.5 py-3">
                    <p className="font-extrabold text-base text-[#1F2A2E] truncate">{a.nom || 'Sans nom'}</p>
                    <p className="text-[13px] text-gray-500 truncate">{[espece(a.espece), a.race].filter(Boolean).join(' · ')}</p>
                  </div>
                </Link>
              ))}
              <Link href="/mes-animaux/ajouter"
                className="min-h-[150px] border-2 border-dashed border-[#C9D6D3] rounded-2xl flex flex-col items-center justify-center gap-2 text-[#0C5C6C] font-bold text-sm hover:bg-white">
                <Picto d={P.plus} /> Ajouter un animal
              </Link>
            </div>
          </section>

          {/* Zone 4 — à découvrir */}
          <section className="max-w-6xl mx-auto px-4 mt-12">
            <div className="flex flex-wrap items-center justify-between gap-3 mb-4">
              <h2 className={titreSection}>À découvrir</h2>
              <div className="flex flex-wrap gap-2" role="tablist" aria-label="À découvrir">
                {ONGLETS.map(o => (
                  <button key={o.cle} type="button" role="tab" aria-selected={onglet === o.cle} onClick={() => setOnglet(o.cle)}
                    className={`px-3.5 py-1.5 rounded-full text-[13px] font-bold transition-colors ${
                      onglet === o.cle ? 'bg-[#0C5C6C] text-white' : 'bg-white border border-[#D9E2E0] text-[#33454B] hover:border-[#0C5C6C]'}`}>
                    {o.label}
                  </button>
                ))}
              </div>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
              {onglet === 'annonces' && (annonces.length ? annonces.map(a => <CarteAnnonce key={a.id} a={a} />) : vide('Aucune annonce pour le moment.'))}
              {onglet === 'adoptions' && (adoptions.length ? adoptions.map(a => <CarteAnnonce key={a.id} a={a} />) : vide('Aucun animal à l\'adoption pour le moment.'))}
              {onglet === 'pros' && (pros.length ? pros.map(p => (
                <Link key={p.id} href={`/services/pro/${p.uid}?profileId=${p.id}`} className={carte}>
                  <div className="h-[170px] bg-[#E3E9F0]">{(p.banner_url || p.avatar_url) && <img src={p.banner_url || p.avatar_url} alt="" className="w-full h-full object-cover" />}</div>
                  <div className="px-3.5 py-3">
                    <p className="font-extrabold text-[15px] text-[#1F2A2E] truncate">{p.nom || 'Professionnel'}</p>
                    <p className="text-[13px] text-gray-500 truncate">{[p.profession_pro, p.ville_pro || p.ville].filter(Boolean).join(' · ')}</p>
                    <p className="mt-2 text-[13px] font-bold text-[#0C5C6C]">Voir le profil</p>
                  </div>
                </Link>
              )) : vide('Aucun professionnel pour le moment.'))}
              {onglet === 'activites' && (balades.length ? balades.map(b => (
                <Link key={b.id} href={`/balades-ludiques/${b.id}`} className={carte}>
                  <div className="h-[170px] bg-[#EEF0E4]">{b.cover_url && <img src={b.cover_url} alt="" className="w-full h-full object-cover" />}</div>
                  <div className="px-3.5 py-3">
                    <p className="font-extrabold text-[15px] text-[#1F2A2E] truncate">{b.titre}</p>
                    <p className="text-[13px] text-gray-500 truncate">{b.ville || 'Balade ludique'}</p>
                    <p className="mt-2 text-[13px] font-bold text-[#0C5C6C]">Voir le parcours</p>
                  </div>
                </Link>
              )) : vide('Aucune balade publiée pour le moment.'))}
            </div>
            <div className="text-center mt-5">
              <Link href={ongletActif.voir.href} className="inline-block px-5 py-2.5 rounded-xl border border-[#C9D6D3] bg-white text-sm font-bold text-[#0C5C6C] hover:border-[#0C5C6C]">
                {ongletActif.voir.label}
              </Link>
            </div>
          </section>

          {/* Zones 5 et 6 — communauté, perdus et trouvés */}
          <section className="max-w-6xl mx-auto px-4 mt-12 grid grid-cols-1 lg:grid-cols-3 gap-6">
            <div className="lg:col-span-2 bg-white rounded-[18px] px-6 py-5 shadow-[0_1px_4px_rgba(15,40,45,0.08)]">
              <div className="flex items-baseline justify-between mb-1">
                <h2 className="text-xl font-extrabold text-[#1F2A2E]">Dans la communauté</h2>
                <Link href="/communaute" className={voirTout}>Voir la communauté</Link>
              </div>
              {sujets.length === 0 ? (
                <p className="text-sm text-gray-500 py-4">Aucun sujet pour le moment. Lancez la première discussion dans le forum.</p>
              ) : sujets.map((s, i) => (
                <Link key={s.id} href={`/communaute/forum/${s.categorie_slug}`}
                  className={`flex items-center gap-3.5 py-3.5 ${i < sujets.length - 1 ? 'border-b border-[#EDF1F0]' : ''}`}>
                  <span className="w-10 h-10 rounded-full bg-[#E7F1EF] flex items-center justify-center flex-shrink-0"><Picto d={P.groupe} /></span>
                  <div className="flex-1 min-w-0">
                    <p className="font-bold text-[15px] text-[#1F2A2E] truncate">{s.titre}</p>
                    <p className="text-[13px] text-gray-500 truncate">{['Forum', libelleSujet(s)].filter(Boolean).join(' · ')}</p>
                  </div>
                  <Picto d={P.chevron} couleur="#9AA7AB" />
                </Link>
              ))}
            </div>

            <div className="bg-white rounded-[18px] px-6 py-5 shadow-[0_1px_4px_rgba(15,40,45,0.08)] border-t-4 border-[#D9822B] flex flex-col gap-3">
              <h2 className="text-xl font-extrabold text-[#1F2A2E]">Perdus et trouvés</h2>
              <p className="text-sm text-gray-500 leading-relaxed">Consultez les signalements près de chez vous ou déclarez un animal perdu ou trouvé.</p>
              <Link href="/animaux-perdus/declarer" className="block text-center py-2.5 rounded-xl bg-[#A85A12] hover:bg-[#8A4A0F] text-white text-sm font-bold">Signaler un animal</Link>
              <Link href="/animaux-perdus" className="block text-center py-2.5 rounded-xl border border-[#E6CBAE] text-[#8A4A0F] text-sm font-bold">Voir les signalements</Link>
              <Link href="/mes-alertes" className="text-center text-[13px] font-bold text-[#8A4A0F]">
                Mes alertes{nbAlertes > 0 ? ` (${nbAlertes} en cours)` : ''}
              </Link>
            </div>
          </section>
        </>
      )}
    </div>
  );
}
