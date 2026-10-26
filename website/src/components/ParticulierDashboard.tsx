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

interface Evenement { id: string; titre?: string; type?: string; date_debut: string; animal_id?: string | null }
interface TacheSoin { id: string; titre?: string; date: string; heure?: string | null; animal_id?: string | null; notes?: string | null }
interface Rappel { id: string; animal_id: string; date_rappel: string; libelle: string; cat: string }

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
  agenda: 'M4 6h16v14H4zM4 10h16M8 3v4M16 3v4',
  coche: 'M5 12l4 4 10-10',
  horloge: 'M12 21a9 9 0 100-18 9 9 0 000 18zM12 7v5l3 2',
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

const cleJour = (d: Date) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;

/** « Aujourd’hui », « Demain » ou « lun. 3 nov. » (+ heure si précisée). */
function quand(iso?: string | null, avecHeure = false) {
  if (!iso) return '';
  const d = iso.length <= 10 ? new Date(`${iso}T00:00:00`) : new Date(iso);
  if (isNaN(d.getTime())) return '';
  const auj = new Date(); auj.setHours(0, 0, 0, 0);
  const j0 = new Date(d); j0.setHours(0, 0, 0, 0);
  const j = Math.round((j0.getTime() - auj.getTime()) / 86400000);
  const jour = j === 0 ? 'Aujourd’hui' : j === 1 ? 'Demain'
    : d.toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' });
  return avecHeure && iso.length > 10 && (d.getHours() || d.getMinutes())
    ? `${jour} · ${d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}` : jour;
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
  // Mon quotidien — scopé au profil actif (miroir de l'appli).
  const [evenements, setEvenements] = useState<Evenement[]>([]);
  const [tachesSoin, setTachesSoin] = useState<TacheSoin[]>([]);
  const [rappels, setRappels] = useState<Rappel[]>([]);
  const [message, setMessage] = useState<string | null>(null);

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
      // Mon quotidien : rendez-vous et tâches (15 jours), soins à donner
      // (prises de traitement du jour et en retard, à cocher), rappels santé.
      const debut = new Date(); debut.setHours(0, 0, 0, 0);
      const fin = new Date(debut); fin.setDate(fin.getDate() + 15);
      const fin30 = new Date(debut); fin30.setDate(fin30.getDate() + 30);
      const colsEv = 'id, titre, type, date_debut, animal_id';
      const evQ = activeProfileId
        ? supabase.from('agenda_events').select(colsEv).eq('pro_profile_id', activeProfileId)
        : supabase.from('agenda_events').select(colsEv).eq('uid', uid).or('pro_profile_id.is.null,pro_profile_id.eq.');
      let soinQ = supabase.from('taches_elevage').select('id, titre, date, heure, animal_id, notes')
        .eq('uid_eleveur', uid).eq('profil_source', 'particulier').neq('statut', 'fait')
        .lte('date', cleJour(debut));
      if (activeProfileId) soinQ = soinQ.or(`profile_id.eq.${activeProfileId},profile_id.is.null`);
      const SANTE = [
        { table: 'vaccinations', champ: 'vaccin', libelle: 'Rappel vaccin' },
        { table: 'vermifuges', champ: 'produit', libelle: 'Vermifuge' },
        { table: 'antiparasitaires', champ: 'produit', libelle: 'Antiparasitaire' },
      ];
      const [evRes, soinRes, ...santeRes] = await Promise.all([
        evQ.gte('date_debut', debut.toISOString()).lte('date_debut', fin.toISOString()).order('date_debut').limit(8),
        soinQ.order('date').order('heure').limit(6),
        ...SANTE.map(t => animalIds.length
          ? supabase.from(t.table).select(`id, animal_id, date, date_rappel, ${t.champ}${t.table === 'vaccinations' ? ', categorie' : ''}`)
              .in('animal_id', animalIds).order('date', { ascending: false, nullsFirst: false }).limit(300)
          : Promise.resolve({ data: [] })),
      ]);
      // Seule la dernière injection de chaque vaccin / produit compte : un
      // rappel déjà fait disparaît, un rappel en retard reste jusqu'à ce qu'il
      // soit fait (un an au plus).
      const depuis = new Date(debut); depuis.setFullYear(depuis.getFullYear() - 1);
      const listeRappels: Rappel[] = [];
      santeRes.forEach((r, i) => {
        const vus = new Set<string>();
        for (const row of (r.data ?? []) as unknown as Record<string, string | null>[]) {
          const quoi = row[SANTE[i].champ];
          const cle = `${row.animal_id}|${String(row.categorie || quoi || '').toLowerCase()}`;
          if (vus.has(cle)) continue;
          vus.add(cle);
          const dr = row.date_rappel ? String(row.date_rappel).slice(0, 10) : '';
          if (!dr || dr < cleJour(depuis) || dr > cleJour(fin30)) continue;
          listeRappels.push({
            id: String(row.id), animal_id: String(row.animal_id), date_rappel: dr,
            libelle: quoi ? `${SANTE[i].libelle} ${quoi}` : SANTE[i].libelle, cat: SANTE[i].table,
          });
        }
      });
      listeRappels.sort((a, b) => a.date_rappel.localeCompare(b.date_rappel));
      // Co-propriété : RDV, rappels et tâches de soin des animaux partagés,
      // créés chez l'autre co-propriétaire (« pris par » / « ajouté par »).
      let evs = (evRes.data ?? []) as (Evenement & { uid?: string })[];
      let soins = (soinRes.data ?? []) as TacheSoin[];
      if (animalIds.length) {
        const { data: co } = await supabase.from('animaux_proprietes').select('profile_id_proprio')
          .in('animal_id', animalIds).eq('statut', 'actif').is('date_fin', null).neq('uid_proprio', uid);
        const profils = [...new Set((co ?? []).map(r => r.profile_id_proprio as string).filter(Boolean))];
        const noms = new Map<string, string>();
        if (profils.length) {
          const { data: ups } = await supabase.from('user_profiles_complet')
            .select('uid, nom, firstname, lastname').in('id', profils).eq('profile_type', 'particulier');
          for (const u of (ups ?? []) as { uid: string; nom?: string; firstname?: string; lastname?: string }[]) {
            noms.set(u.uid, `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim() || u.nom || 'Co-propriétaire');
          }
        }
        if (noms.size) {
          const [{ data: evCo }, { data: soinCo }] = await Promise.all([
            supabase.from('agenda_events').select('id, titre, type, date_debut, animal_id, uid')
              .in('animal_id', animalIds).in('uid', [...noms.keys()])
              .gte('date_debut', debut.toISOString()).lte('date_debut', fin.toISOString()).order('date_debut').limit(8),
            supabase.from('taches_elevage').select('id, titre, date, heure, animal_id, notes')
              .eq('profil_source', 'particulier').neq('statut', 'fait').in('animal_id', animalIds).neq('uid_eleveur', uid)
              .lte('date', cleJour(debut)).order('date').limit(6),
          ]);
          const vusEv = new Set(evs.map(e => e.id));
          for (const e of (evCo ?? []) as (Evenement & { uid?: string })[]) {
            if (vusEv.has(e.id)) continue;
            vusEv.add(e.id);
            evs.push({ ...e, titre: `${e.titre ?? ''} — ${e.type === 'rdv' ? 'pris par' : 'ajouté par'} ${noms.get(e.uid ?? '')}` });
          }
          evs = evs.sort((a, b) => a.date_debut.localeCompare(b.date_debut));
          const vusSoin = new Set(soins.map(t => t.id));
          soins = [...soins, ...((soinCo ?? []) as TacheSoin[]).filter(t => !vusSoin.has(t.id))]
            .sort((a, b) => `${a.date} ${a.heure ?? ''}`.localeCompare(`${b.date} ${b.heure ?? ''}`)).slice(0, 6);
        }
      }
      setEvenements(evs);
      setTachesSoin(soins);
      setRappels(listeRappels.slice(0, 4));

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

  async function validerSoin(t: TacheSoin) {
    const { error } = await supabase.from('taches_elevage').update({ statut: 'fait' }).eq('id', t.id);
    if (error) { setMessage('Validation impossible, réessayez.'); return; }
    setTachesSoin(prev => prev.filter(x => x.id !== t.id));
    setMessage('Soin validé.');
    setTimeout(() => setMessage(null), 2500);
  }

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

  function monQuotidien() {
    const rdv = evenements.filter(e => e.type === 'rdv' || e.type === 'visite').slice(0, 3);
    const aFaire = evenements.filter(e => e.type !== 'rdv' && e.type !== 'visite').slice(0, 3);
    const rien = !rdv.length && !aFaire.length && !tachesSoin.length && !rappels.length;
    const nomAnimal = (id?: string | null) => animaux.find(a => a.id === id)?.nom ?? '';
    // Fiche de l'animal sur son carnet de santé : l'endroit où l'on valide.
    const ficheSante = (id?: string | null, cat?: string, rappel?: string) =>
      id && animaux.some(a => a.id === id)
        ? `/mes-animaux/${id}?tab=sante${cat ? `&cat=${cat}` : ''}${rappel ? `&rappel=${encodeURIComponent(rappel)}` : ''}`
        : '/agenda';
    const joindre = (...l: (string | null | undefined)[]) => l.filter(Boolean).join(' · ');
    const sousTitre = (t: string) => <p className="px-5 pt-4 pb-1 text-[11px] font-bold tracking-wider uppercase text-gray-500">{t}</p>;
    const ligne = (cle: string, href: string, d: string, couleur: string, fond: string, titre: string, detail: string) => (
      <Link key={cle} href={href} className="flex items-center gap-3 px-5 py-2.5 hover:bg-[#F7FAF9]">
        <span className={`w-9 h-9 rounded-[10px] flex items-center justify-center flex-shrink-0 ${fond}`}><Picto d={d} couleur={couleur} /></span>
        <span className="flex-1 min-w-0">
          <span className="block font-bold text-sm text-[#1F2A2E] truncate">{titre}</span>
          {detail && <span className="block text-xs text-gray-500 truncate">{detail}</span>}
        </span>
        <Picto d={P.chevron} couleur="#9AA7AB" />
      </Link>
    );
    const aujourdhui = cleJour(new Date());
    return (
      <section className="max-w-6xl mx-auto px-4 mt-12">
        <div className="flex items-baseline justify-between mb-4">
          <h2 className={titreSection}>Mon quotidien</h2>
          <Link href="/agenda" className={voirTout}>Ouvrir mon agenda</Link>
        </div>
        <div className="bg-white rounded-[18px] shadow-[0_1px_4px_rgba(15,40,45,0.08)] pb-3">
          {message && <p role="status" className="mx-5 mt-4 text-sm font-semibold text-[#4E7A3B]">{message}</p>}
          {rien ? (
            <div className="px-5 pt-5 pb-2">
              <p className="font-bold text-sm text-[#1F2A2E]">Rien de prévu pour le moment.</p>
              <p className="text-[13px] text-gray-500 mt-1">Profitez de vos compagnons. Vos rendez-vous, tâches et rappels santé apparaîtront ici.</p>
            </div>
          ) : (
            <>
              {rdv.length > 0 && <>{sousTitre('Prochains rendez-vous')}
                {rdv.map(e => ligne(`rdv-${e.id}`, '/agenda', P.agenda, '#0C5C6C', 'bg-[#E7F1EF]', e.titre || 'Rendez-vous',
                  joindre(quand(e.date_debut, true), nomAnimal(e.animal_id))))}</>}
              {tachesSoin.length > 0 && <>{sousTitre('Soins à donner')}
                {tachesSoin.map(t => {
                  const enRetard = t.date < aujourdhui;
                  const detail = joindre(enRetard ? `En retard · ${quand(t.date)}` : 'Aujourd’hui', t.heure?.slice(0, 5), t.notes);
                  return (
                    <div key={`soin-${t.id}`} className="flex items-center gap-1 pl-3 pr-5 py-1 hover:bg-[#F7FAF9]">
                      <button type="button" onClick={() => validerSoin(t)} aria-label={`Valider : ${t.titre ?? 'soin'}`} title="Valider"
                        className="w-9 h-9 flex items-center justify-center flex-shrink-0">
                        <span className="w-[18px] h-[18px] rounded border-2 border-[#4E7A3B]" />
                      </button>
                      <Link href={ficheSante(t.animal_id, 'traitements')} className="flex-1 min-w-0 flex items-center gap-2">
                        <span className="flex-1 min-w-0">
                          <span className="block font-bold text-sm text-[#1F2A2E] line-clamp-2">{(t.titre || 'Soin').replace(/^\S*\u{1F48A}\S*\s*/u, '')}</span>
                          <span className={`block text-xs truncate ${enRetard ? 'text-red-700' : 'text-gray-500'}`}>{detail}</span>
                        </span>
                        <Picto d={P.chevron} couleur="#9AA7AB" />
                      </Link>
                    </div>
                  );
                })}</>}
              {aFaire.length > 0 && <>{sousTitre('À faire')}
                {aFaire.map(e => ligne(`af-${e.id}`, '/agenda', P.coche, '#4E7A3B', 'bg-[#EEF5EA]', e.titre || 'Tâche',
                  joindre(quand(e.date_debut, true), nomAnimal(e.animal_id))))}</>}
              {rappels.length > 0 && <>{sousTitre('Rappels et échéances')}
                {rappels.map(r => ligne(`rap-${r.cat}-${r.id}`, ficheSante(r.animal_id, r.cat, r.id), P.horloge, '#A85A12', 'bg-[#FDF1E4]',
                  joindre(r.libelle, nomAnimal(r.animal_id)),
                  r.date_rappel < aujourdhui ? `En retard · ${quand(r.date_rappel)}` : quand(r.date_rappel)))}</>}
            </>
          )}
        </div>
      </section>
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
          {/* Mon quotidien — rendez-vous, soins à donner, à faire, rappels santé */}
          {monQuotidien()}

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
