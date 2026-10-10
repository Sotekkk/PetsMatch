'use client';

import { Suspense, useEffect, useRef, useState, useCallback } from 'react';
import Link from 'next/link';
import { useRouter, useSearchParams } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { usePlan } from '@/lib/use-plan';
import { thumbUrl } from '@/lib/upload-media';
import CessionModal from '@/components/animaux/CessionModal';
import PorteePoidsModal from '@/components/animaux/PorteePoidsModal';
import PorteeSoinModal from '@/components/animaux/PorteeSoinModal';
import EditPorteeModal from '@/components/animaux/EditPorteeModal';
import SuiviCessionsTab from '@/components/animaux/SuiviCessionsTab';
import ContactAcquereurButton from '@/components/animaux/ContactAcquereurButton';

interface Animal {
  id: string;
  nom?: string;
  espece?: string;
  race?: string;
  sexe?: string;
  identification?: string;
  date_naissance?: string;
  photo_url?: string;
  statut?: string;
  date_entree?: string;
  date_sortie?: string;
  portee_id?: string;
  description?: string;
  pedigree?: boolean;
  club_registre?: string;
  pedigree_lof?: string;
  nom_pere?: string;
  puce_pere?: string;
  nom_mere?: string;
  puce_mere?: string;
  race_mere?: string;
  date_naissance_mere?: string;
  reproducteur?: boolean;
  reproducteur_public?: boolean;
  nom_pedigree?: string;
  is_retraite?: boolean;
  intervalle_chaleurs_jours?: number | null;
  uid_eleveur?: string | null;
  uid_acquereur?: string | null;
  destinataire_nom?: string | null;
  sterilise?: boolean | null;
  sterilisation_requise?: boolean | null;
  sterilisation_echeance?: string | null;
  sterilisation_validee?: boolean | null;
}

const CHALEURS_INTERVAL_WEB: Record<string, number> = {
  chien: 182, chat: 21, lapin: 14, ovin: 17, caprin: 21, porcin: 21, cheval: 21,
};

const SPECIES = [
  { value: 'tous',   label: 'Tous',    color: '#1F2A2E' },
  { value: 'chien',  label: 'Chiens',  color: '#6E9E57' },
  { value: 'chat',   label: 'Chats',   color: '#0C5C6C' },
  { value: 'cheval', label: 'Chevaux', color: '#5B8648' },
  { value: 'lapin',  label: 'Lapins',  color: '#E08080' },
  { value: 'ovin',   label: 'Ovins',   color: '#5F9EAA' },
  { value: 'caprin', label: 'Caprins', color: '#8D6E63' },
  { value: 'porcin', label: 'Porcins', color: '#E25C5C' },
  { value: 'nac',    label: 'NAC',     color: '#F4B400' },
  { value: 'oiseau', label: 'Oiseaux', color: '#26A69A' },
  { value: 'autre',  label: 'Autres',  color: '#6F767B' },
];


function speciesLabel(v: string) {
  return SPECIES.find(s => s.value === v)?.label ?? v;
}

function formatDate(d?: string) {
  if (!d) return '';
  return new Date(d).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: '2-digit' });
}


/** Statut lisible : présence (présent / cédé / décédé) distincte de la réservation. */
function etatAnimal(a: Animal, isBebe: boolean): { label: string; color: string } {
  if (a.statut === 'decede') return { label: 'Décédé', color: '#E25C5C' };
  if (a.statut === 'sorti') return { label: 'Cédé', color: '#0C5C6C' };
  if (a.statut === 'en_attente_cession' || a.statut === 'cession_en_cours') return { label: 'Cession en cours', color: '#F59E0B' };
  if (a.statut === 'reserve') return { label: 'Réservé', color: '#D97706' };
  return { label: isBebe ? 'Disponible' : 'Présent', color: '#6E9E57' };
}

/** Emplacement photo neutre (photo absente ou en erreur de chargement). */
function PhotoAnimal({ src, alt, ajouterHref }: { src?: string; alt: string; ajouterHref?: string }) {
  const [erreur, setErreur] = useState(false);
  return (
    <div className="relative flex-shrink-0 w-20 h-20 sm:w-full sm:h-auto sm:aspect-[4/3] rounded-md overflow-hidden bg-[#EDF2F2]">
      {src && !erreur ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img src={src} alt={alt} loading="lazy" onError={() => setErreur(true)} className="w-full h-full object-cover" />
      ) : (
        <div className="w-full h-full flex flex-col items-center justify-center gap-1 text-[#8B9FA1]">
          <svg className="w-7 h-7" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" aria-hidden>
            <path strokeLinecap="round" strokeLinejoin="round" d="M2.25 15.75l5.16-5.16a2.25 2.25 0 013.18 0l5.16 5.16m-1.5-1.5l1.41-1.41a2.25 2.25 0 013.18 0l2.91 2.91M3.75 21h16.5A1.5 1.5 0 0021.75 19.5V4.5A1.5 1.5 0 0020.25 3H3.75A1.5 1.5 0 002.25 4.5v15A1.5 1.5 0 003.75 21zm10.5-11.25h.008v.008h-.008V9.75zm.375 0a.375.375 0 11-.75 0 .375.375 0 01.75 0z" />
          </svg>
          {ajouterHref && <span className="hidden sm:block text-[11px] font-semibold text-[#0C5C6C]">Ajouter une photo</span>}
        </div>
      )}
    </div>
  );
}

function AnimalCard({ a, tab, isBebe = false, reproducteur = false, reproPublic = false, isRetraite = false, chaleurFlag = false, gestanteFlag = false, selectMode = false, selected = false, peutModifier = false, onOuvrir, onDelete, onToggleReproducteur, onToggleReproPublic, onToggleRetraite, onSelect, onCeder, onTransferer }: {
  a: Animal; tab: 'presents' | 'anciens' | 'decedes';
  /** Chiot d'une portée (vue Bébés) : statut « Disponible » au lieu de « Présent ». */
  isBebe?: boolean;
  reproducteur?: boolean; reproPublic?: boolean; isRetraite?: boolean; chaleurFlag?: boolean; gestanteFlag?: boolean;
  selectMode?: boolean; selected?: boolean;
  /** Ajout de photo / modifications autorisés (éleveur propriétaire, animal non cédé). */
  peutModifier?: boolean;
  onOuvrir?: () => void;
  onDelete?: () => void; onToggleReproducteur?: () => void; onToggleReproPublic?: () => void; onToggleRetraite?: () => void; onSelect?: () => void;
  onCeder?: () => void;
  onTransferer?: () => void;
}) {
  const isMale   = (a.sexe ?? '').toLowerCase().startsWith('m');
  const isFemale = (a.sexe ?? '').toLowerCase().startsWith('f');
  const photo    = a.photo_url ? thumbUrl(a.photo_url, 400, 75, 'cover') : undefined;
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [menu, setMenu] = useState(false);
  const menuRef = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!menu) return;
    const fermer = (e: MouseEvent) => { if (menuRef.current && !menuRef.current.contains(e.target as Node)) setMenu(false); };
    document.addEventListener('mousedown', fermer);
    return () => document.removeEventListener('mousedown', fermer);
  }, [menu]);

  const etat = etatAnimal(a, isBebe);
  const nom = a.nom || 'Sans nom';
  const ligne1 = [isMale ? 'Mâle' : isFemale ? 'Femelle' : null, a.race || speciesLabel(a.espece ?? '')].filter(Boolean).join(' · ');
  const ligne2 = a.identification ? `Puce ${a.identification}` : 'Identification non renseignée';
  const reperes = [
    reproducteur && { t: 'Reproducteur', c: '#0C5C6C' },
    reproducteur && reproPublic && { t: 'Profil public', c: '#0C5C6C' },
    isRetraite && { t: 'Retraité', c: '#B45309' },
    gestanteFlag && { t: 'Gestante', c: '#6E9E57' },
    chaleurFlag && { t: 'En chaleur', c: '#DB2777' },
  ].filter(Boolean) as { t: string; c: string }[];

  const actions: { label: string; onClick: () => void; danger?: boolean }[] = [];
  if (onToggleReproducteur) actions.push({ label: reproducteur ? 'Retirer des reproducteurs' : 'Marquer comme reproducteur', onClick: onToggleReproducteur });
  if (reproducteur && onToggleReproPublic) actions.push({ label: reproPublic ? 'Masquer du profil public' : 'Afficher sur mon profil public', onClick: onToggleReproPublic });
  if (onToggleRetraite) actions.push({ label: isRetraite ? 'Annuler la retraite' : 'Mettre en retraite', onClick: onToggleRetraite });
  if (onCeder) actions.push({ label: 'Céder cet animal', onClick: onCeder });
  if (onTransferer) actions.push({ label: 'Transférer / donner', onClick: onTransferer });
  if (onDelete) actions.push({ label: 'Supprimer la fiche', onClick: () => setConfirmDelete(true), danger: true });

  const corps = (
    <div className="flex sm:flex-col gap-3 sm:gap-2.5 p-3 h-full">
      <PhotoAnimal src={photo} alt={nom} ajouterHref={peutModifier && !photo ? `/mes-animaux/${a.id}` : undefined} />
      <div className="min-w-0 flex-1 flex flex-col">
        <div className="flex items-start justify-between gap-2">
          <p className="font-semibold text-[#1F2A2E] text-sm truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{nom}</p>
          <span className="flex items-center gap-1.5 text-xs whitespace-nowrap flex-shrink-0" style={{ color: etat.color }}>
            <span className="w-1.5 h-1.5 rounded-full" style={{ backgroundColor: etat.color }} />{etat.label}
          </span>
        </div>
        <p className="text-xs text-gray-500 mt-1 truncate">{ligne1}</p>
        <p className="text-xs text-gray-500 truncate">{ligne2}</p>
        {reperes.length > 0 && (
          <p className="text-[11px] mt-1.5 flex flex-wrap gap-x-2 gap-y-0.5">
            {reperes.map(r => <span key={r.t} style={{ color: r.c }} className="font-medium">{r.t}</span>)}
          </p>
        )}
      </div>
    </div>
  );

  return (
    <div className={`relative bg-white border rounded-lg transition-colors ${selected ? 'border-[#0C5C6C] ring-1 ring-[#0C5C6C]' : 'border-gray-200 hover:border-gray-300'}`}>
      {selectMode ? (
        <button type="button" onClick={onSelect} className="block w-full text-left" aria-pressed={selected}>
          <span className={`absolute top-2 left-2 z-10 w-5 h-5 rounded border flex items-center justify-center ${selected ? 'bg-[#0C5C6C] border-[#0C5C6C]' : 'bg-white border-gray-400'}`}>
            {selected && <svg className="w-3.5 h-3.5 text-white" fill="none" stroke="currentColor" strokeWidth={3} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" /></svg>}
          </span>
          {corps}
        </button>
      ) : (
        <Link href={`/mes-animaux/${a.id}`} onClick={onOuvrir} className="block" aria-label={`Ouvrir la fiche de ${nom}`}>
          {corps}
        </Link>
      )}
      {/* Actions dans le flux (jamais par-dessus le texte) */}
      {!selectMode && (actions.length > 0 || a.statut === 'sorti') && (
        <div ref={menuRef} className="relative flex justify-end px-2 pb-2 -mt-1">
          <button type="button" onClick={() => setMenu(m => !m)} aria-label={`Autres actions pour ${nom}`} aria-expanded={menu}
            className="w-8 h-8 rounded-md text-gray-500 hover:bg-gray-100 flex items-center justify-center">
            <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24" aria-hidden><circle cx="5" cy="12" r="1.6" /><circle cx="12" cy="12" r="1.6" /><circle cx="19" cy="12" r="1.6" /></svg>
          </button>
          {menu && (
            <div className="absolute right-2 bottom-10 z-20 w-60 bg-white border border-gray-200 rounded-lg shadow-lg py-1">
              {a.statut === 'sorti' && <ContactAcquereurButton animal={a} variante="menu" />}
              {actions.map(ac => (
                <button key={ac.label} type="button" onClick={() => { setMenu(false); ac.onClick(); }}
                  className={`w-full text-left px-3 py-2 text-sm hover:bg-gray-50 ${ac.danger ? 'text-red-600' : 'text-[#1F2A2E]'}`}>
                  {ac.label}
                </button>
              ))}
            </div>
          )}
        </div>
      )}
      {confirmDelete && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40" onClick={() => setConfirmDelete(false)}>
          <div className="bg-white rounded-xl p-6 shadow-xl max-w-sm w-full mx-4" onClick={e => e.stopPropagation()}>
            <p className="font-bold text-[#1F2A2E] text-base mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
              Supprimer cet animal ?
            </p>
            <p className="text-sm text-gray-500 mb-5">
              La fiche de <strong>{nom}</strong> sera définitivement supprimée.
            </p>
            <div className="flex gap-3 justify-end">
              <button onClick={() => setConfirmDelete(false)}
                className="px-4 py-2 rounded-lg text-sm text-gray-700 border border-gray-300 hover:bg-gray-50">
                Annuler
              </button>
              <button onClick={() => { setConfirmDelete(false); onDelete?.(); }}
                className="px-4 py-2 rounded-lg text-sm text-white bg-red-600 hover:bg-red-700 font-semibold">
                Supprimer
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

/** Menu « ⋯ » des actions d'une portée. */
function MenuPortee({ actions }: { actions: { label: string; onClick?: () => void; href?: string }[] }) {
  const [ouvert, setOuvert] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!ouvert) return;
    const fermer = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setOuvert(false); };
    document.addEventListener('mousedown', fermer);
    return () => document.removeEventListener('mousedown', fermer);
  }, [ouvert]);
  return (
    <div ref={ref} className="relative">
      <button type="button" onClick={() => setOuvert(o => !o)} aria-label="Autres actions de la portée" aria-expanded={ouvert}
        className="h-9 w-9 rounded-lg border border-gray-300 text-gray-600 hover:bg-gray-50 flex items-center justify-center">
        <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24" aria-hidden><circle cx="5" cy="12" r="1.6" /><circle cx="12" cy="12" r="1.6" /><circle cx="19" cy="12" r="1.6" /></svg>
      </button>
      {ouvert && (
        <div className="absolute right-0 top-10 z-20 w-60 bg-white border border-gray-200 rounded-lg shadow-lg py-1">
          {actions.map(ac => ac.href ? (
            <Link key={ac.label} href={ac.href} onClick={() => setOuvert(false)} className="block px-3 py-2 text-sm text-[#1F2A2E] hover:bg-gray-50">{ac.label}</Link>
          ) : (
            <button key={ac.label} type="button" onClick={() => { setOuvert(false); ac.onClick?.(); }}
              className="w-full text-left px-3 py-2 text-sm text-[#1F2A2E] hover:bg-gray-50">{ac.label}</button>
          ))}
        </div>
      )}
    </div>
  );
}

function MesAnimauxPageInner() {
  const { user, userData, loading, activeProfileId } = useAuth();
  const { plan } = usePlan();
  const router = useRouter();
  const searchParams = useSearchParams();

  const isEleveur = userData?.isElevage === true;

  // Filtre restauré depuis l'URL (?tab=&sub=) pour que la flèche "retour" depuis
  // la fiche d'un animal retrouve le même filtre au lieu de repartir à zéro.
  const tabParam = searchParams.get('tab');
  const initialTab: 'presents' | 'anciens' | 'suivi' | 'decedes' =
    tabParam === 'anciens' ? 'anciens'
      : tabParam === 'suivi' ? 'suivi'
      : tabParam === 'decedes' ? 'decedes'
      : 'presents';
  const initialSub = searchParams.get('sub');
  const initialSubTab: 'tous' | 'repro' | 'bebes' =
    initialSub === 'repro' || initialSub === 'bebes' ? initialSub : 'tous';
  const initialPortee = searchParams.get('portee') ?? '';
  const initialCedesSub: 'tous' | 'bebes' = searchParams.get('cedes') === 'bebes' ? 'bebes' : 'tous';

  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [cessionEnAttente, setCessionEnAttente] = useState<Set<string>>(new Set());
  const [fetching, setFetching] = useState(true);
  const [chaleurFlags, setChaleurFlags] = useState<Record<string, boolean>>({});
  const [gestanteFlags, setGestanteFlags] = useState<Record<string, boolean>>({});
  const [tab, setTab] = useState<'presents' | 'anciens' | 'suivi' | 'decedes'>(initialTab);
  const [cederAnimal, setCederAnimal] = useState<Animal | null>(null);
  const [invitesCopro, setInvitesCopro] = useState<{ animal_id: string; nom: string }[]>([]);
  const [nomElevage, setNomElevage] = useState('');
  const [adresseElevage, setAdresseElevage] = useState('');
  const [presentsSubTab, setPresentsSubTab] = useState<'tous' | 'repro' | 'bebes'>(initialSubTab);
  // Portée sélectionnée dans le filtre "Bébés" — '' = toutes les portées.
  const [selectedPortee, setSelectedPortee] = useState(initialPortee);
  // Onglet Cédés : tous les animaux, ou bébés cédés regroupés par portée
  // (retrouver une portée et ses courbes de poids après les départs).
  const [cedesSubTab, setCedesSubTab] = useState<'tous' | 'bebes'>(initialCedesSub);
  const bebesVue: 'presents' | 'cedes' = tab === 'anciens' ? 'cedes' : 'presents';
  const vueBebes = (tab === 'presents' && presentsSubTab === 'bebes') || (tab === 'anciens' && cedesSubTab === 'bebes');

  // Garde l'URL synchro avec les filtres actifs (remplace l'entrée d'historique,
  // pas de nouvelle entrée à chaque clic) pour que le retour depuis une fiche
  // animal restaure le bon filtre.
  useEffect(() => {
    const params = new URLSearchParams();
    if (tab !== 'presents') params.set('tab', tab);
    if (presentsSubTab !== 'tous') params.set('sub', presentsSubTab);
    if (vueBebes && selectedPortee) params.set('portee', selectedPortee);
    if (tab === 'anciens' && cedesSubTab === 'bebes') params.set('cedes', 'bebes');
    const qs = params.toString();
    router.replace(qs ? `/mes-animaux?${qs}` : '/mes-animaux', { scroll: false });
  }, [tab, presentsSubTab, selectedPortee, cedesSubTab, vueBebes, router]);
  const [selectMode, setSelectMode] = useState(false);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  // Modal soin portée
  const [soinPorteeAnimals, setSoinPorteeAnimals] = useState<Animal[] | null>(null);
  const [poidsPortee, setPoidsPortee] = useState<{ animals: Animal[]; dn: string | null } | null>(null);
  const [editPorteeGroup, setEditPorteeGroup] = useState<{ pid: string; members: Animal[] } | null>(null);

  // Filtres présents
  const [filtreEspece, setFiltreEspece] = useState('tous');
  const [filtreSexe, setFiltreSexe] = useState('tous');
  const [filtreRace, setFiltreRace] = useState('');
  const [filtreRetraite, setFiltreRetraite] = useState(false);
  const [filtreRepro, setFiltreRepro] = useState(false);
  const [filtreGestante, setFiltreGestante] = useState(false);
  const [filtreChaleur, setFiltreChaleur] = useState(false);
  // Réservation (statut commercial) — distincte de la présence à l'élevage
  const [filtreReservation, setFiltreReservation] = useState<'tous' | 'disponible' | 'reserve'>('tous');

  // Filtres cédés (ex-« anciens » — les décédés ont leur propre onglet ci-dessous)
  const [anciensEspece, setAnciensEspece] = useState('tous');

  // Filtres décédés
  const [decedesEspece, setDecedesEspece] = useState('tous');

  // Recherche
  const [search, setSearch] = useState('');

  // uid Firebase réel du propriétaire du profil actif — jamais forcément
  // user.uid : un cogérant (elevage_cogerants) a un uid différent du gérant,
  // mais la ligne user_profiles du profil emprunté (activeProfileId) reste
  // celle du gérant. Sans ça, "Mes Animaux" resterait scopé sur le compte
  // personnel du cogérant (0 animal trouvé).
  const [ownerUid, setOwnerUid] = useState<string | null>(null);
  useEffect(() => {
    if (!user) { setOwnerUid(null); return; }
    let cancelled = false;
    (async () => {
      let resolved = user.uid;
      if (activeProfileId) {
        const { data } = await supabase.from('user_profiles_complet').select('uid').eq('id', activeProfileId).maybeSingle();
        resolved = (data?.uid as string | undefined) ?? user.uid;
      }
      if (!cancelled) setOwnerUid(resolved);
    })();
    return () => { cancelled = true; };
  }, [user, activeProfileId]);

  // Filtres et position conservés au retour depuis une fiche (onglet, catégorie
  // et portée sont déjà dans l'URL ; le reste dans la session du navigateur).
  const CLE_ETAT = 'pm_mes_animaux_etat';
  const etatRestaure = useRef(false);
  const scrollARestaurer = useRef<number | null>(null);
  useEffect(() => {
    try {
      const raw = sessionStorage.getItem(CLE_ETAT);
      if (raw) {
        const e = JSON.parse(raw);
        setSearch(e.search ?? ''); setFiltreEspece(e.espece ?? 'tous'); setFiltreSexe(e.sexe ?? 'tous');
        setFiltreRace(e.race ?? ''); setFiltreRetraite(!!e.retraite); setFiltreGestante(!!e.gestante);
        setFiltreChaleur(!!e.chaleur); setFiltreReservation(e.reservation ?? 'tous');
        setAnciensEspece(e.anciensEspece ?? 'tous'); setDecedesEspece(e.decedesEspece ?? 'tous');
        if (typeof e.scrollY === 'number') scrollARestaurer.current = e.scrollY;
      }
    } catch { /* stockage indisponible */ }
    etatRestaure.current = true;
  }, []);
  useEffect(() => {
    if (!etatRestaure.current) return;
    try {
      const prev = JSON.parse(sessionStorage.getItem(CLE_ETAT) ?? '{}');
      sessionStorage.setItem(CLE_ETAT, JSON.stringify({ ...prev, search, espece: filtreEspece, sexe: filtreSexe, race: filtreRace,
        retraite: filtreRetraite, gestante: filtreGestante, chaleur: filtreChaleur, reservation: filtreReservation,
        anciensEspece, decedesEspece }));
    } catch { /* */ }
  }, [search, filtreEspece, filtreSexe, filtreRace, filtreRetraite, filtreGestante, filtreChaleur, filtreReservation, anciensEspece, decedesEspece]);
  function memoriserPosition() {
    try {
      const prev = JSON.parse(sessionStorage.getItem(CLE_ETAT) ?? '{}');
      sessionStorage.setItem(CLE_ETAT, JSON.stringify({ ...prev, scrollY: window.scrollY }));
    } catch { /* */ }
  }

  // UI state
  const [filterOpen, setFilterOpen] = useState(false);
  const [addMenuOpen, setAddMenuOpen] = useState(false);
  const addMenuRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (addMenuRef.current && !addMenuRef.current.contains(e.target as Node)) {
        setAddMenuOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  // Invitations de co-propriété reçues (statut='invite')
  useEffect(() => {
    if (!user) return;
    let cancelled = false;
    (async () => {
      const { data } = await supabase.from('animaux_proprietes')
        .select('animal_id').eq('uid_proprio', user.uid).eq('statut', 'invite').is('date_fin', null);
      const ids = (data ?? []).map(r => r.animal_id as string);
      if (ids.length === 0) { if (!cancelled) setInvitesCopro([]); return; }
      const { data: an } = await supabase.from('animaux').select('id, nom').in('id', ids);
      if (!cancelled) setInvitesCopro((an ?? []).map(a => ({ animal_id: a.id as string, nom: (a.nom as string) || 'un animal' })));
    })();
    return () => { cancelled = true; };
  }, [user]);

  useEffect(() => {
    if (!user || !isEleveur || !ownerUid) return;
    supabase.from('user_profiles_complet').select('nom, rue_pro, ville_pro').eq('uid', ownerUid).eq('is_main', true).maybeSingle()
      .then(({ data }) => {
        if (data) {
          setNomElevage((data as {nom?:string}).nom ?? '');
          const parts = [(data as {rue_pro?:string}).rue_pro, (data as {ville_pro?:string}).ville_pro].filter(Boolean);
          setAdresseElevage(parts.join(', '));
        }
      });
  }, [user, isEleveur, ownerUid]);

  useEffect(() => {
    // Attendre que l'auth ET le profil actif soient chargés avant de requêter
    if (!user || loading) return;
    setFetching(true);
    let cancelled = false;

    async function loadAll() {
      const uid = user!.uid;

      // uid réel du propriétaire du profil actif (résolu localement, sans
      // dépendre du state `ownerUid` pour éviter tout décalage de timing).
      let resolvedOwnerUid = uid;
      if (activeProfileId) {
        const { data: ownerRow } = await supabase.from('user_profiles_complet')
          .select('uid').eq('id', activeProfileId).maybeSingle();
        resolvedOwnerUid = (ownerRow?.uid as string | undefined) ?? uid;
      }

      // Source : animaux_proprietes — filtré par profile_id_proprio (post-migration V2.05)
      // Vérifie d'abord si la migration a été jouée, sinon retombe sur uid_proprio
      let ownRows: { animal_id: string; date_fin: string | null; role_proprio?: string | null }[] = [];
      if (activeProfileId) {
        const { data: check } = await supabase
          .from('animaux_proprietes')
          .select('animal_id')
          .eq('uid_proprio', resolvedOwnerUid)
          .not('profile_id_proprio', 'is', null)
          .limit(1);
        if ((check ?? []).length > 0) {
          // Migration faite → filtre strict par profil (vide = correct pour ce profil)
          const { data: byProfile } = await supabase
            .from('animaux_proprietes')
            .select('animal_id, date_fin, role_proprio')
            .eq('uid_proprio', resolvedOwnerUid)
            .eq('profile_id_proprio', activeProfileId)
            .eq('statut', 'actif');
          ownRows = (byProfile ?? []) as typeof ownRows;
        } else {
          // Migration pas encore jouée → tous les animaux de l'uid
          const { data: fallback } = await supabase
            .from('animaux_proprietes')
            .select('animal_id, date_fin, role_proprio')
            .eq('uid_proprio', resolvedOwnerUid)
            .eq('statut', 'actif');
          ownRows = (fallback ?? []) as typeof ownRows;
        }
      } else {
        const { data } = await supabase
          .from('animaux_proprietes')
          .select('animal_id, date_fin, role_proprio')
          .eq('uid_proprio', resolvedOwnerUid)
          .eq('statut', 'actif');
        ownRows = (data ?? []) as typeof ownRows;
      }

      const rows = ownRows;
      const currentIds = new Set(rows.filter(r => !r.date_fin).map(r => r.animal_id as string));
      const allAnimalIds = [...new Set(rows.map(r => r.animal_id as string))];

      if (allAnimalIds.length === 0) {
        if (!cancelled) { setAnimaux([]); setCessionEnAttente(new Set()); setFetching(false); }
        return;
      }

      const { data } = await supabase
        .from('animaux')
        .select('*')
        .in('id', allAnimalIds)
        .order('nom', { ascending: true });

      // Cédé puis repris par une asso / un élevage : la fiche porte le statut
      // du nouveau détenteur — pour ce profil l'animal est sorti (onglet Cédés).
      const merged = ((data ?? []) as Animal[]).map(a =>
        !currentIds.has(a.id) && a.uid_eleveur !== resolvedOwnerUid
          && !['decede', 'sorti', 'cession_en_cours', 'en_attente_cession'].includes(a.statut ?? '')
          ? { ...a, statut: 'sorti' } : a);
      if (!cancelled) { setAnimaux(merged); setCessionEnAttente(currentIds); setFetching(false); }

      // Calcul flags chaleurs et gestante pour les femelles présentes
      const femIds = merged
        .filter((a: Animal) => (a.sexe ?? '').startsWith('f') && a.statut !== 'sorti' && a.statut !== 'decede')
        .map((a: Animal) => a.id);

      if (femIds.length === 0) return;

      const eleveurUids = [...new Set(merged.map((a) => a.uid_eleveur).filter((u): u is string => !!u))];
      const [{ data: chaleurs }, { data: gests }, { data: naissances }, { data: protocoles }] = await Promise.all([
        supabase.from('chaleurs').select('animal_id, date').in('animal_id', femIds).order('date', { ascending: false }),
        supabase.from('gestations').select('animal_id').in('animal_id', femIds).eq('gestation_confirmee', true).is('date_naissance', null),
        supabase.from('gestations').select('animal_id, date_naissance').in('animal_id', femIds).not('date_naissance', 'is', null).order('date_naissance', { ascending: false }),
        eleveurUids.length
          ? supabase.from('protocoles_chaleur_race').select('uid_eleveur, espece, race, intervalle_jours').in('uid_eleveur', eleveurUids)
          : Promise.resolve({ data: [] as { uid_eleveur: string; espece: string; race: string; intervalle_jours: number }[] }),
      ]);

      const lastChaleur: Record<string, Date> = {};
      for (const c of (chaleurs ?? [])) {
        const aid = c.animal_id as string;
        if (!lastChaleur[aid]) { const d = new Date(c.date as string); if (!isNaN(d.getTime())) lastChaleur[aid] = d; }
      }

      const lastMiseBas: Record<string, Date> = {};
      for (const n of (naissances ?? [])) {
        const aid = n.animal_id as string;
        if (!lastMiseBas[aid]) { const d = new Date(n.date_naissance as string); if (!isNaN(d.getTime())) lastMiseBas[aid] = d; }
      }

      // Correspondance souple (sous-chaîne dans les deux sens) : la race
      // stockée sur l'animal vient souvent du sélecteur officiel (ex.
      // "Spitz Allemand") alors que l'éleveur tape un raccourci dans le
      // protocole (ex. "Spitz") — une correspondance exacte les manquerait.
      const raceProtocoles = protocoles ?? [];
      function raceIntervalFor(uidEleveur: string | null | undefined, espece: string, race: string | null | undefined): number | null {
        const e = espece.toLowerCase().trim();
        const r = (race || '').toLowerCase().trim();
        if (!r) return null;
        for (const p of raceProtocoles) {
          if (p.uid_eleveur !== uidEleveur) continue;
          if ((p.espece || '').toLowerCase().trim() !== e) continue;
          const pr = (p.race || '').toLowerCase().trim();
          if (pr && (pr.includes(r) || r.includes(pr))) return p.intervalle_jours;
        }
        return null;
      }

      const JOURS_LACTATION = 56;
      const cFlags: Record<string, boolean> = {};
      const now = new Date();
      for (const a of merged) {
        const miseBas = lastMiseBas[a.id];
        // Mise-bas récente : cycle suspendu pendant l'allaitement.
        if (miseBas && (now.getTime() - miseBas.getTime()) / 86400000 < JOURS_LACTATION) continue;

        const interval = a.intervalle_chaleurs_jours || raceIntervalFor(a.uid_eleveur, a.espece ?? '', a.race) || CHALEURS_INTERVAL_WEB[a.espece ?? ''] || 0;
        if (!interval) continue;

        // Une mise-bas postérieure à la dernière chaleur enregistrée redémarre
        // le cycle : sans ça, une femelle qui vient de mettre bas retombe,
        // une fois la lactation passée, sur sa dernière chaleur d'AVANT la
        // gestation, largement dépassée.
        const last = lastChaleur[a.id];
        const effectiveLast = (miseBas && (!last || miseBas.getTime() > last.getTime())) ? miseBas : last;
        if (!effectiveLast) continue;

        const next = new Date(effectiveLast.getTime() + interval * 86400000);
        if ((next.getTime() - now.getTime()) / 86400000 <= 7) cFlags[a.id] = true;
      }

      const gFlags: Record<string, boolean> = {};
      for (const g of (gests ?? [])) gFlags[g.animal_id as string] = true;

      if (cancelled) return;
      setChaleurFlags(cFlags);
      setGestanteFlags(gFlags);
    }

    loadAll().catch(() => { if (!cancelled) setFetching(false); });
    return () => { cancelled = true; };
  }, [user, loading, isEleveur, activeProfileId]);

  useEffect(() => {
    if (fetching || scrollARestaurer.current == null) return;
    const y = scrollARestaurer.current;
    scrollARestaurer.current = null;
    requestAnimationFrame(() => window.scrollTo(0, y));
    try {
      const prev = JSON.parse(sessionStorage.getItem(CLE_ETAT) ?? '{}');
      delete prev.scrollY;
      sessionStorage.setItem(CLE_ETAT, JSON.stringify(prev));
    } catch { /* */ }
  }, [fetching]);

  async function deleteAnimal(id: string) {
    await supabase.from('animaux').delete().eq('id', id);
    setAnimaux(prev => prev.filter(a => a.id !== id));
  }

  async function toggleReproducteur(id: string, current: boolean) {
    await supabase.from('animaux').update({ reproducteur: !current }).eq('id', id);
    setAnimaux(prev => prev.map(a => a.id === id ? { ...a, reproducteur: !current } : a));
  }

  async function toggleReproPublic(id: string, current: boolean) {
    await supabase.from('animaux').update({ reproducteur_public: !current }).eq('id', id);
    setAnimaux(prev => prev.map(a => a.id === id ? { ...a, reproducteur_public: !current } : a));
  }

  async function toggleRetraite(id: string, current: boolean) {
    await supabase.from('animaux').update({ is_retraite: !current }).eq('id', id);
    setAnimaux(prev => prev.map(a => a.id === id ? { ...a, is_retraite: !current } : a));
  }

  function toggleSelect(id: string) {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }

  async function regrouperEnPortee() {
    if (selectedIds.size < 2) return;
    const porteeId = `portee_${Date.now()}`;
    await supabase.from('animaux').update({ portee_id: porteeId }).in('id', [...selectedIds]);
    setAnimaux(prev => prev.map(a => selectedIds.has(a.id) ? { ...a, portee_id: porteeId } : a));
    setSelectMode(false);
    setSelectedIds(new Set());
  }

  if (loading || !user) return <div className="flex justify-center py-32 text-gray-400">Chargement…</div>;

  // Séparer présents / cédés / décédés via animaux_proprietes (source unique)
  // cessionEnAttente = animal_id où date_fin IS NULL = propriétaire actuel.
  // Le statut de l'animal est exclu explicitement en plus de la ligne
  // animaux_proprietes : une sortie/décès déclaré manuellement dans le
  // registre ne clôture pas toujours cette ligne, l'animal ne doit pour
  // autant pas rester visible dans Présents.
  const presents = animaux.filter(a => cessionEnAttente.has(a.id) && a.statut !== 'decede' && a.statut !== 'sorti');
  const anciens  = animaux.filter(a => a.statut === 'sorti');
  const decedes  = animaux.filter(a => a.statut === 'decede');

  // Espèces disponibles dans chaque groupe
  const especesPresents = [...new Set(presents.map(a => a.espece).filter(Boolean))] as string[];
  const especesAnciens  = [...new Set(anciens.map(a => a.espece).filter(Boolean))] as string[];
  const especesDecedes  = [...new Set(decedes.map(a => a.espece).filter(Boolean))] as string[];

  // Races disponibles selon espèce sélectionnée (présents)
  const racesDisponibles = filtreEspece !== 'tous'
    ? [...new Set(presents.filter(a => a.espece === filtreEspece).map(a => a.race).filter(Boolean))] as string[]
    : [];

  const searchLower = search.toLowerCase().trim();

  // Filtrage présents
  const filteredPresents = presents.filter(a => {
    if (filtreEspece !== 'tous' && a.espece !== filtreEspece) return false;
    if (filtreSexe !== 'tous') {
      const s = (a.sexe ?? '').toLowerCase();
      if (filtreSexe === 'male' && !s.startsWith('m')) return false;
      if (filtreSexe === 'femelle' && !s.startsWith('f')) return false;
    }
    if (filtreRace && a.race !== filtreRace) return false;
    if (filtreRetraite && !a.is_retraite) return false;
    if (filtreRepro && !a.reproducteur) return false;
    if (filtreGestante && !gestanteFlags[a.id]) return false;
    if (filtreChaleur && !chaleurFlags[a.id]) return false;
    if (filtreReservation === 'reserve' && a.statut !== 'reserve') return false;
    if (filtreReservation === 'disponible' && a.statut === 'reserve') return false;
    if (searchLower) {
      const nom  = (a.nom            ?? '').toLowerCase();
      const puce = (a.identification ?? '').toLowerCase();
      if (!nom.includes(searchLower) && !puce.includes(searchLower)) return false;
    }
    return true;
  });

  // Filtrage cédés
  const filteredAnciens = anciens.filter(a => {
    if (anciensEspece !== 'tous' && a.espece !== anciensEspece) return false;
    if (searchLower) {
      const nom  = (a.nom            ?? '').toLowerCase();
      const puce = (a.identification ?? '').toLowerCase();
      if (!nom.includes(searchLower) && !puce.includes(searchLower)) return false;
    }
    return true;
  });

  // Filtrage décédés
  const filteredDecedes = decedes.filter(a => {
    if (decedesEspece !== 'tous' && a.espece !== decedesEspece) return false;
    if (searchLower) {
      const nom  = (a.nom            ?? '').toLowerCase();
      const puce = (a.identification ?? '').toLowerCase();
      if (!nom.includes(searchLower) && !puce.includes(searchLower)) return false;
    }
    return true;
  });

  const activeFilterCount = tab === 'presents'
    ? (filtreEspece !== 'tous' ? 1 : 0) + (filtreSexe !== 'tous' ? 1 : 0) + (filtreRace ? 1 : 0) +
      (filtreRetraite ? 1 : 0) + (filtreGestante ? 1 : 0) + (filtreChaleur ? 1 : 0) +
      (filtreReservation !== 'tous' ? 1 : 0)
    : tab === 'decedes'
    ? (decedesEspece !== 'tous' ? 1 : 0)
    : (anciensEspece !== 'tous' ? 1 : 0);

  // Bébés vendus/cédés (statut 'sorti') : masqués par défaut (filtre
  // « Présents »), seuls affichés (grisés) avec « Cédés » — la carte garde
  // l'historique de la portée (dont la courbe de poids saisie par
  // l'éleveur). Décédés toujours exclus.
  const filteredBebes = animaux.filter(a => {
    if (a.statut === 'decede') return false;
    if ((bebesVue === 'cedes') !== (a.statut === 'sorti')) return false;
    // Onglet Cédés : seuls ses filtres (espèce) et la recherche s'appliquent.
    if (bebesVue === 'cedes') {
      if (anciensEspece !== 'tous' && a.espece !== anciensEspece) return false;
      if (searchLower && !(a.nom ?? '').toLowerCase().includes(searchLower) && !(a.identification ?? '').toLowerCase().includes(searchLower)) return false;
      return true;
    }
    if (filtreEspece !== 'tous' && a.espece !== filtreEspece) return false;
    if (filtreSexe !== 'tous') {
      const s = (a.sexe ?? '').toLowerCase();
      if (filtreSexe === 'male' && !s.startsWith('m')) return false;
      if (filtreSexe === 'femelle' && !s.startsWith('f')) return false;
    }
    if (filtreRace && a.race !== filtreRace) return false;
    if (filtreReservation === 'reserve' && a.statut !== 'reserve') return false;
    if (filtreReservation === 'disponible' && a.statut === 'reserve') return false;
    if (filtreGestante && !gestanteFlags[a.id]) return false;
    if (filtreChaleur && !chaleurFlags[a.id]) return false;
    if (searchLower) {
      const nom  = (a.nom            ?? '').toLowerCase();
      const puce = (a.identification ?? '').toLowerCase();
      if (!nom.includes(searchLower) && !puce.includes(searchLower)) return false;
    }
    return true;
  });

  // Sub-tab filtering (presents only)
  const presentsForSubTab = (() => {
    if (presentsSubTab === 'repro') return filteredPresents.filter(a => a.reproducteur === true);
    if (presentsSubTab === 'bebes') return filteredBebes.filter(a => !!a.portee_id && !a.reproducteur);
    return filteredPresents;
  })();

  const currentList = tab === 'presents' ? presentsForSubTab : tab === 'decedes' ? filteredDecedes : filteredAnciens;

  // Groupement par portée (bébés uniquement) — inclut les frères/sœurs reproducteurs
  const porteeGroups: Map<string, Animal[]> = new Map();
  if (vueBebes) {
    // 1) Collecter les portee_id des vrais bébés (non-reproducteurs)
    const porteeIdsEnVue = new Set(
      filteredBebes.filter(a => !!a.portee_id && !a.reproducteur).map(a => a.portee_id!)
    );
    // 2) Inclure TOUS les membres de ces portées (y compris reproducteurs, y
    // compris cédés — un membre de la portée sorti reste dans le groupe).
    for (const a of filteredBebes) {
      if (!a.portee_id || !porteeIdsEnVue.has(a.portee_id)) continue;
      const group = porteeGroups.get(a.portee_id) ?? [];
      group.push(a);
      porteeGroups.set(a.portee_id, group);
    }
    const sorted = [...porteeGroups.entries()].sort((a, b) => {
      const da = new Date(a[1][0]?.date_naissance ?? '').getTime();
      const db = new Date(b[1][0]?.date_naissance ?? '').getTime();
      return db - da;
    });
    porteeGroups.clear();
    for (const [k, v] of sorted) porteeGroups.set(k, v);
  }

  // Filtre "une seule portée" — '' = toutes.
  const visiblePorteeGroups = [...porteeGroups.entries()].filter(([pid]) => !selectedPortee || pid === selectedPortee);

  function resetFilters() {
    if (tab === 'presents') {
      setFiltreEspece('tous'); setFiltreSexe('tous'); setFiltreRace('');
      setFiltreRetraite(false); setFiltreRepro(false); setFiltreGestante(false); setFiltreChaleur(false);
      setFiltreReservation('tous');
    } else if (tab === 'decedes') {
      setDecedesEspece('tous');
    } else {
      setAnciensEspece('tous');
    }
  }

  return (
    <>
    <div className="max-w-5xl mx-auto px-4 py-8">
      {/* En-tête */}
      <div className="flex items-start justify-between gap-3 mb-5">
        <div>
          <h1 className="text-2xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
            Mes animaux
          </h1>
          <p className="text-gray-500 text-sm mt-1">
            {presents.length} présent{presents.length !== 1 ? 's' : ''} · {animaux.length} animal{animaux.length !== 1 ? 'aux' : ''} au total
          </p>
        </div>
        <div className="relative" ref={addMenuRef}>
          {isEleveur ? (
            <>
              <button
                onClick={() => setAddMenuOpen(v => !v)} aria-expanded={addMenuOpen}
                className="h-10 bg-[#0C5C6C] hover:bg-[#094F5D] text-white text-sm font-semibold px-4 rounded-lg transition-colors flex items-center gap-1.5">
                + Ajouter
                <svg className={`w-3.5 h-3.5 transition-transform ${addMenuOpen ? 'rotate-180' : ''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24" aria-hidden>
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2.5} d="M19 9l-7 7-7-7" />
                </svg>
              </button>
              {addMenuOpen && (
                <div className="absolute right-0 top-full mt-2 w-60 bg-white rounded-lg shadow-lg border border-gray-200 overflow-hidden z-20 py-1">
                  <Link href="/mes-animaux/ajouter" onClick={() => setAddMenuOpen(false)} className="block px-4 py-2.5 hover:bg-gray-50">
                    <p className="text-sm font-semibold text-[#1F2A2E]">Ajouter un animal</p>
                    <p className="text-xs text-gray-500">Fiche individuelle</p>
                  </Link>
                  <Link href="/mes-animaux/portee" onClick={() => setAddMenuOpen(false)} className="block px-4 py-2.5 hover:bg-gray-50 border-t border-gray-100">
                    <p className="text-sm font-semibold text-[#1F2A2E]">Charger une portée</p>
                    <p className="text-xs text-gray-500">Plusieurs animaux d&apos;un coup</p>
                  </Link>
                </div>
              )}
            </>
          ) : (
            <Link href="/mes-animaux/ajouter"
              className="h-10 inline-flex items-center bg-[#0C5C6C] hover:bg-[#094F5D] text-white text-sm font-semibold px-4 rounded-lg transition-colors">
              + Ajouter
            </Link>
          )}
        </div>
      </div>

      {/* Invitations de co-propriété reçues */}
      {invitesCopro.length > 0 && (
        <div className="space-y-2 mb-5">
          {invitesCopro.map(inv => (
            <Link key={inv.animal_id} href={`/mes-animaux/${inv.animal_id}`}
              className="flex items-center gap-3 rounded-lg bg-white border border-gray-200 px-4 py-3 hover:border-gray-300">
              <span className="text-sm text-[#1F2A2E] flex-1">Invitation à co-gérer la fiche de <strong>{inv.nom}</strong></span>
              <span className="text-sm font-semibold text-[#0C5C6C]">Voir</span>
            </Link>
          ))}
        </div>
      )}

      {/* Onglets (éleveur uniquement) */}
      {isEleveur && (
        <div className="flex gap-6 border-b border-gray-200 mb-4 overflow-x-auto" role="tablist">
          {(['presents', 'anciens', 'suivi', 'decedes'] as const).map((t) => (
            <button key={t} role="tab" aria-selected={tab === t}
              onClick={() => { setTab(t); setFilterOpen(false); setSelectMode(false); setSelectedIds(new Set()); }}
              className={`py-3 -mb-px border-b-2 text-sm font-semibold whitespace-nowrap transition-colors ${
                tab === t ? 'border-[#0C5C6C] text-[#0C5C6C]' : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}>
              {t === 'presents' ? `Présents · ${presents.length}`
                : t === 'anciens' ? `Cédés · ${anciens.length}`
                : t === 'decedes' ? `Décédés · ${decedes.length}`
                : 'Suivi'}
            </button>
          ))}
        </div>
      )}

      {tab === 'suivi' && isEleveur && user && (
        <SuiviCessionsTab
          animaux={animaux}
          uid={ownerUid ?? user.uid}
          myUid={user.uid}
          activeProfileId={activeProfileId ?? null}
          onLocalUpdate={(id, patch) => setAnimaux(prev => prev.map(a => a.id === id ? { ...a, ...patch } : a))}
        />
      )}

      {tab !== 'suivi' && (
      <>
      {/* Barre : recherche, catégorie, portée, filtres */}
      <div className="flex flex-col sm:flex-row sm:flex-wrap gap-2 mb-3">
        <label className="relative flex-1 min-w-0 sm:min-w-[220px]">
          <span className="sr-only">Rechercher un animal</span>
          <svg className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" aria-hidden>
            <path strokeLinecap="round" d="M21 21l-5.2-5.2m0 0A7.5 7.5 0 105.2 5.2a7.5 7.5 0 0010.6 10.6z" />
          </svg>
          <input type="search" value={search} onChange={e => setSearch(e.target.value)}
            placeholder="Rechercher par nom ou numéro de puce"
            className="w-full h-10 pl-9 pr-3 rounded-lg border border-gray-300 bg-white text-sm focus:outline-none focus:border-[#0C5C6C]" />
        </label>
        <div className="flex gap-2 flex-wrap">
          {tab === 'presents' && isEleveur && (
            <select value={presentsSubTab} aria-label="Catégorie"
              onChange={e => { setPresentsSubTab(e.target.value as 'tous' | 'repro' | 'bebes'); setSelectedPortee(''); setSelectMode(false); setSelectedIds(new Set()); }}
              className="h-10 flex-1 sm:flex-none rounded-lg border border-gray-300 bg-white px-3 text-sm text-[#1F2A2E] focus:outline-none focus:border-[#0C5C6C]">
              <option value="tous">Tous les animaux</option>
              <option value="repro">Reproducteurs</option>
              <option value="bebes">Bébés</option>
            </select>
          )}
          {tab === 'anciens' && (
            <select value={cedesSubTab} aria-label="Catégorie"
              onChange={e => { setCedesSubTab(e.target.value as 'tous' | 'bebes'); setSelectedPortee(''); }}
              className="h-10 flex-1 sm:flex-none rounded-lg border border-gray-300 bg-white px-3 text-sm text-[#1F2A2E] focus:outline-none focus:border-[#0C5C6C]">
              <option value="tous">Tous les animaux</option>
              <option value="bebes">Bébés (par portée)</option>
            </select>
          )}
          {vueBebes && porteeGroups.size > 0 && (
            <select value={selectedPortee} aria-label="Portée" onChange={e => setSelectedPortee(e.target.value)}
              className="h-10 flex-1 sm:flex-none sm:max-w-[260px] rounded-lg border border-gray-300 bg-white px-3 text-sm text-[#1F2A2E] focus:outline-none focus:border-[#0C5C6C]">
              <option value="">Toutes les portées</option>
              {[...porteeGroups.entries()].map(([pid, members]) => {
                const first = members[0];
                const nomMere = first.nom_mere?.trim() ?? '';
                return <option key={pid} value={pid}>{nomMere ? `Portée de ${nomMere}` : 'Portée'}{first.date_naissance ? ` — ${new Date(first.date_naissance).toLocaleDateString('fr-FR')}` : ''}</option>;
              })}
            </select>
          )}
          <button type="button" onClick={() => setFilterOpen(!filterOpen)} aria-expanded={filterOpen}
            className={`h-10 px-3 rounded-lg border text-sm font-semibold flex items-center gap-2 ${
              activeFilterCount > 0 ? 'border-[#0C5C6C] text-[#0C5C6C] bg-[#E8F4F6]' : 'border-gray-300 text-gray-700 bg-white hover:bg-gray-50'}`}>
            Filtres{activeFilterCount > 0 && <span className="text-xs bg-[#0C5C6C] text-white rounded px-1.5">{activeFilterCount}</span>}
          </button>
          {tab === 'presents' && (
            <button type="button" onClick={() => { setSelectMode(m => !m); setSelectedIds(new Set()); }}
              className="h-10 px-3 rounded-lg border border-gray-300 bg-white text-sm font-semibold text-gray-700 hover:bg-gray-50">
              {selectMode ? 'Annuler la sélection' : 'Sélectionner'}
            </button>
          )}
        </div>
      </div>

      {/* Panneau de filtres compact */}
      {filterOpen && (
        <div className="bg-white border border-gray-200 rounded-lg p-3 mb-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-2">
            <select aria-label="Espèce"
              value={tab === 'presents' ? filtreEspece : tab === 'decedes' ? decedesEspece : anciensEspece}
              onChange={e => { const v = e.target.value; if (tab === 'presents') { setFiltreEspece(v); setFiltreRace(''); } else if (tab === 'decedes') setDecedesEspece(v); else setAnciensEspece(v); }}
              className="h-10 rounded-lg border border-gray-300 bg-white px-3 text-sm">
              <option value="tous">Toutes les espèces</option>
              {SPECIES.filter(s => s.value !== 'tous' && (tab === 'presents' ? especesPresents : tab === 'decedes' ? especesDecedes : especesAnciens).includes(s.value))
                .map(s => <option key={s.value} value={s.value}>{s.label}</option>)}
            </select>
            {tab === 'presents' && (
              <>
                <select aria-label="Sexe" value={filtreSexe} onChange={e => setFiltreSexe(e.target.value)}
                  className="h-10 rounded-lg border border-gray-300 bg-white px-3 text-sm">
                  <option value="tous">Tous les sexes</option>
                  <option value="male">Mâles</option>
                  <option value="femelle">Femelles</option>
                </select>
                {racesDisponibles.length > 0 && (
                  <select aria-label="Race" value={filtreRace} onChange={e => setFiltreRace(e.target.value)}
                    className="h-10 rounded-lg border border-gray-300 bg-white px-3 text-sm">
                    <option value="">Toutes les races</option>
                    {racesDisponibles.map(r => <option key={r} value={r}>{r}</option>)}
                  </select>
                )}
                <select aria-label="Réservation" value={filtreReservation} onChange={e => setFiltreReservation(e.target.value as 'tous' | 'disponible' | 'reserve')}
                  className="h-10 rounded-lg border border-gray-300 bg-white px-3 text-sm">
                  <option value="tous">Toutes les réservations</option>
                  <option value="disponible">Disponibles</option>
                  <option value="reserve">Réservés</option>
                </select>
              </>
            )}
          </div>
          {tab === 'presents' && (
            <div className="flex flex-wrap gap-x-5 gap-y-2 mt-3 text-sm text-[#1F2A2E]">
              {isEleveur && (
                <label className="flex items-center gap-2"><input type="checkbox" checked={filtreRetraite} onChange={e => setFiltreRetraite(e.target.checked)} className="accent-[#0C5C6C] w-4 h-4" />Retraités</label>
              )}
              <label className="flex items-center gap-2"><input type="checkbox" checked={filtreGestante} onChange={e => setFiltreGestante(e.target.checked)} className="accent-[#0C5C6C] w-4 h-4" />Gestantes</label>
              <label className="flex items-center gap-2"><input type="checkbox" checked={filtreChaleur} onChange={e => setFiltreChaleur(e.target.checked)} className="accent-[#0C5C6C] w-4 h-4" />En chaleur</label>
            </div>
          )}
          {activeFilterCount > 0 && (
            <button type="button" onClick={resetFilters} className="mt-3 text-sm font-semibold text-[#0C5C6C] hover:underline">Réinitialiser les filtres</button>
          )}
        </div>
      )}

      {/* Liste */}
      {fetching ? (
        <div className="flex justify-center py-16">
          <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
        </div>
      ) : (vueBebes ? visiblePorteeGroups.length === 0 : currentList.length === 0) ? (
        <div className="text-center py-16 px-4 bg-white border border-dashed border-gray-300 rounded-lg">
          <p className="text-[15px] font-semibold text-[#1F2A2E]">
            {searchLower || activeFilterCount > 0 ? 'Aucun animal ne correspond'
              : tab === 'presents' && presentsSubTab === 'repro' ? 'Aucun reproducteur'
              : vueBebes ? (bebesVue === 'presents' ? 'Aucun bébé présent' : 'Aucun bébé cédé')
              : tab === 'presents' ? 'Aucun animal présent'
              : tab === 'decedes' ? 'Aucun animal décédé'
              : 'Aucun animal cédé'}
          </p>
          <p className="text-sm text-gray-500 mt-1">
            {searchLower || activeFilterCount > 0 ? 'Modifiez la recherche ou les filtres.'
              : tab === 'presents' && presentsSubTab === 'repro' ? 'Ouvrez le menu d’un animal pour le marquer comme reproducteur.'
              : vueBebes && bebesVue === 'presents' ? 'Les portées déjà parties se retrouvent dans Cédés › Bébés.'
              : tab === 'presents' && animaux.length === 0 ? 'Ajoutez votre premier animal.' : ''}
          </p>
          {(searchLower || activeFilterCount > 0) && (
            <button type="button" onClick={() => { setSearch(''); resetFilters(); }} className="mt-3 text-sm font-semibold text-[#0C5C6C] hover:underline">Réinitialiser</button>
          )}
        </div>
      ) : vueBebes ? (
        <div className="space-y-4">
          {visiblePorteeGroups.map(([pid, members]) => {
            const first = members[0];
            const dn = first.date_naissance ? new Date(first.date_naissance).toLocaleDateString('fr-FR') : null;
            const nomMere = first.nom_mere?.trim() ?? '';
            const meta = [first.race || speciesLabel(first.espece ?? ''), `${members.length} ${members.length > 1 ? 'chiots' : 'chiot'}`, dn ? `Nés le ${dn}` : null].filter(Boolean).join(' · ');
            const cedes = bebesVue === 'cedes';
            return (
              <section key={pid} className="bg-white border border-gray-200 rounded-lg overflow-visible">
                <div className="flex flex-wrap items-center justify-between gap-3 px-4 py-3.5 border-b border-gray-100">
                  <div className="min-w-0">
                    <h3 className="text-base font-semibold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>{nomMere ? `Portée de ${nomMere}` : 'Portée'}</h3>
                    <p className="text-xs text-gray-500 mt-0.5">{meta}</p>
                  </div>
                  <div className="flex items-center gap-2">
                    {selectedPortee !== pid && (
                      <button type="button" onClick={() => { setSelectedPortee(pid); window.scrollTo({ top: 0, behavior: 'smooth' }); }}
                        className="h-9 px-3 rounded-lg border border-[#0C5C6C] text-[#0C5C6C] text-sm font-semibold hover:bg-[#E8F4F6]">
                        Voir la portée
                      </button>
                    )}
                    {isEleveur && !cedes && (
                      <MenuPortee actions={[
                        { label: 'Modifier les informations de la portée', onClick: () => setEditPorteeGroup({ pid, members }) },
                        { label: 'Courbes de poids', onClick: () => setPoidsPortee({ animals: animaux.filter(x => x.portee_id === pid), dn: first.date_naissance ?? null }) },
                        { label: 'Soin pour toute la portée', onClick: () => setSoinPorteeAnimals(members) },
                        { label: 'Créer une annonce', href: `/annonces/creer?portee_id=${pid}` },
                      ]} />
                    )}
                    {cedes && (
                      <MenuPortee actions={[{ label: 'Courbes de poids', onClick: () => setPoidsPortee({ animals: animaux.filter(x => x.portee_id === pid), dn: first.date_naissance ?? null }) }]} />
                    )}
                  </div>
                </div>
                <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3 p-3">
                  {members.map(a => {
                    const cede = a.statut === 'sorti';
                    return <AnimalCard key={a.id} a={a} tab={tab} isBebe={!a.reproducteur}
                      reproducteur={!!a.reproducteur} reproPublic={!!a.reproducteur_public} isRetraite={!!a.is_retraite}
                      chaleurFlag={!!chaleurFlags[a.id]} gestanteFlag={!!gestanteFlags[a.id]}
                      selectMode={selectMode} selected={selectedIds.has(a.id)} onSelect={() => toggleSelect(a.id)}
                      peutModifier={isEleveur && !cede} onOuvrir={memoriserPosition}
                      onDelete={selectMode || cede ? undefined : () => deleteAnimal(a.id)}
                      onToggleReproducteur={isEleveur && !selectMode && !cede ? () => toggleReproducteur(a.id, !!a.reproducteur) : undefined}
                      onToggleReproPublic={isEleveur && !selectMode && !cede ? () => toggleReproPublic(a.id, !!a.reproducteur_public) : undefined}
                      onToggleRetraite={isEleveur && !selectMode && !cede ? () => toggleRetraite(a.id, !!a.is_retraite) : undefined} />;
                  })}
                </div>
              </section>
            );
          })}
          {selectedPortee && (
            <button type="button" onClick={() => setSelectedPortee('')} className="text-sm font-semibold text-[#0C5C6C] hover:underline">Afficher toutes les portées</button>
          )}
        </div>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3">
          {currentList.map(a => <AnimalCard key={a.id} a={a} tab={tab}
            reproducteur={!!a.reproducteur} reproPublic={!!a.reproducteur_public} isRetraite={!!a.is_retraite}
            chaleurFlag={!!chaleurFlags[a.id]} gestanteFlag={!!gestanteFlags[a.id]}
            selectMode={tab === 'presents' && selectMode} selected={selectedIds.has(a.id)} onSelect={() => toggleSelect(a.id)}
            peutModifier={tab === 'presents'} onOuvrir={memoriserPosition}
            onDelete={selectMode ? undefined : () => deleteAnimal(a.id)}
            onToggleReproducteur={isEleveur && tab === 'presents' && !selectMode ? () => toggleReproducteur(a.id, !!a.reproducteur) : undefined}
            onToggleReproPublic={isEleveur && tab === 'presents' && !selectMode ? () => toggleReproPublic(a.id, !!a.reproducteur_public) : undefined}
            onToggleRetraite={isEleveur && tab === 'presents' && !selectMode ? () => toggleRetraite(a.id, !!a.is_retraite) : undefined}
            onCeder={isEleveur && tab === 'presents' && !selectMode && a.uid_eleveur === (ownerUid ?? user?.uid) ? () => setCederAnimal(a) : undefined}
            onTransferer={tab === 'presents' && !selectMode && a.uid_eleveur !== (ownerUid ?? user?.uid) && a.uid_acquereur === (ownerUid ?? user?.uid) ? () => setCederAnimal(a) : undefined} />)}
        </div>
      )}
      </>
      )}

      {/* Barre action sélection */}
      {selectMode && selectedIds.size > 0 && (
        <div className="fixed bottom-6 left-1/2 -translate-x-1/2 z-30 flex items-center gap-3 bg-[#1F2A2E] text-white rounded-2xl px-5 py-3 shadow-2xl">
          <span className="text-sm font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
            {selectedIds.size} sélectionné{selectedIds.size > 1 ? 's' : ''}
          </span>
          <button
            onClick={regrouperEnPortee}
            disabled={selectedIds.size < 2}
            className="bg-[#0C5C6C] hover:bg-[#0a4d5b] disabled:opacity-40 text-white text-sm font-semibold px-4 py-1.5 rounded-xl transition-colors">
            Regrouper en portée
          </button>
        </div>
      )}

      {/* Liens admin éleveur */}
      {isEleveur && (
        <div className="mt-8 grid grid-cols-1 sm:grid-cols-2 gap-3">
          {([
            ['/elevage/registre-sanitaire', 'Registre sanitaire', 'Actes vétérinaires'],
            ['/elevage/registre-entree-sortie', 'Entrées / Sorties', 'Registre légal'],
          ] as const).map(([href, titre, sous]) => (
            <Link key={href} href={plan === 'free' ? '/abonnement' : href}
              className="flex items-center justify-between gap-3 bg-white border border-gray-200 rounded-lg px-4 py-3 hover:border-gray-300">
              <span>
                <span className="flex items-center gap-2">
                  <span className="font-semibold text-[#1F2A2E] text-sm">{titre}</span>
                  {plan === 'free' && <span className="text-[10px] font-bold text-[#B45309] border border-[#B45309]/40 rounded px-1.5">Pro</span>}
                </span>
                <span className="block text-gray-500 text-xs">{sous}</span>
              </span>
              <svg className="w-4 h-4 text-gray-400" fill="none" stroke="currentColor" strokeWidth={2} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" strokeLinejoin="round" d="M9 5l7 7-7 7" /></svg>
            </Link>
          ))}
        </div>
      )}
    </div>

    {/* Modal soin portée */}
    {soinPorteeAnimals && (
      <PorteeSoinModal
        animals={soinPorteeAnimals}
        uid={ownerUid ?? user?.uid ?? ''}
        activeProfileId={activeProfileId ?? null}
        onClose={() => setSoinPorteeAnimals(null)}
      />
    )}

    {/* Modal courbes de poids portée */}
    {poidsPortee && (
      <PorteePoidsModal
        animals={poidsPortee.animals}
        dateNaissance={poidsPortee.dn}
        onClose={() => setPoidsPortee(null)}
      />
    )}

    {/* Modal modifier portée */}
    {editPorteeGroup && (
      <EditPorteeModal
        pid={editPorteeGroup.pid}
        members={editPorteeGroup.members}
        uid={ownerUid ?? user?.uid ?? ''}
        activeProfileId={activeProfileId ?? null}
        onClose={() => setEditPorteeGroup(null)}
        onSaved={(fields) => {
          setAnimaux(prev => prev.map(a => a.portee_id === editPorteeGroup.pid ? { ...a, ...fields } as Animal : a));
          setEditPorteeGroup(null);
        }}
      />
    )}

    {/* Modal cession */}
    {cederAnimal && user && (
      <CessionModal
        animal={cederAnimal}
        uid={ownerUid ?? user.uid}
        profileId={activeProfileId || null}
        eleveurInfo={{ nom: nomElevage || user.email || 'Éleveur', adresse: adresseElevage, email: user.email ?? '' }}
        // Particulier (animal acquis ou ajouté lui-même) : don / abandon,
        // signature de l'acquéreur requise — miroir de la fiche appli.
        isReCession={cederAnimal.uid_eleveur !== (ownerUid ?? user.uid)}
        onClose={() => setCederAnimal(null)}
        onCeded={() => {
          setCederAnimal(null);
          setFetching(true);
          const ouid = ownerUid ?? user.uid;
          supabase.from('animaux')
            .select('*').or(`uid_eleveur.eq.${ouid},uid_acquereur.eq.${ouid}`)
            .order('nom', { ascending: true })
            .then(({ data }) => { setAnimaux((data ?? []) as Animal[]); setFetching(false); });
        }}
      />
    )}
    </>
  );
}

export default function MesAnimauxPage() {
  return (
    <Suspense fallback={null}>
      <MesAnimauxPageInner />
    </Suspense>
  );
}
