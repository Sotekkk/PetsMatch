'use client';

import { useEffect, useState } from 'react';
import Image from 'next/image';
import { useRouter, useParams } from 'next/navigation';
import { collection, query, where, getDocs, addDoc, serverTimestamp } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';

// ── Types ─────────────────────────────────────────────────────────────────────

interface Animal {
  id: number | string; nom: string; espece: string; race: string | null;
  sexe: string | null; couleur: string | null; date_naissance: string | null;
  identification: string | null; passeport_numero: string | null;
  photo_url: string | null; sterilise: boolean | null;
  poids: number | null; taille: number | null; notes: string | null;
  uid_proprietaire: string | null; uid_eleveur: string | null;
}
interface Owner {
  uid: string; firstname: string | null; lastname: string | null;
  name_elevage: string | null; email: string | null;
  phone_number: string | null; numero_elevage: string | null;
  adress_elevage: string | null; rue_elevage: string | null;
  ville_elevage: string | null; code_postal_elevage: string | null;
  ville: string | null; code_postal: string | null;
  is_elevage: boolean | null; is_pro: boolean | null;
}
interface Grant { id: string; statut: string; pro_profile_id: string; }
interface VaccinEntry {
  id: string; vaccin: string; date: string;
  date_rappel: string | null; lot: string | null; veterinaire: string | null; source: string | null;
}
interface VisiteEntry {
  id: string; date: string; motif: string | null;
  veterinaire: string | null; diagnostic: string | null; notes: string | null;
  source: string | null; vet_id: string | null;
}
interface TraitementEntry {
  id: string; date: string; nom: string; posologie: string | null;
  date_fin: string | null; notes: string | null; source: string | null; vet_id: string | null;
}
interface CompteRendu {
  id: string; created_at: string; contenu: string | null; pro_uid: string | null;
}
interface Ordonnance {
  id: string; date_emit: string; doc_url: string | null; notes: string | null; pro_uid: string | null;
}
interface RadioEntry {
  id: string; date: string; titre: string | null; notes: string | null; veterinaire: string | null;
}
interface Chaleur { id: string; date: string; date_fin: string | null; duree: number | null; notes: string | null; }
interface Saillie { id: string; date: string; nom_partenaire: string | null; methode: string | null; notes: string | null; }
interface Gestation {
  id: string; date: string | null; date_prevue: string | null; date_naissance: string | null;
  nb_attendu: number | null; nb_nes: number | null; notes: string | null; gestation_confirmee: boolean | null;
}

// ── Constants ─────────────────────────────────────────────────────────────────

const ESPECE_EMOJI: Record<string, string> = {
  chien: '🐕', chat: '🐈', cheval: '🐴', lapin: '🐰',
  oiseau: '🦜', nac: '🦎', ovin: '🐑', caprin: '🐐', porcin: '🐷', ane: '🐴',
};
const PENSION_TYPES = new Set(['pension', 'garde', 'toilettage', 'photographe']);
const TEAL = '#0C5C6C';

// ── Helpers ───────────────────────────────────────────────────────────────────

function fmtDate(iso: string | null) {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('fr-FR', { day: '2-digit', month: 'long', year: 'numeric' });
}
function fmtDateShort(iso: string | null) {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: 'numeric' });
}
function calcAge(dateNaissance: string | null): string {
  if (!dateNaissance) return '';
  const birth = new Date(dateNaissance);
  const months = (new Date().getFullYear() - birth.getFullYear()) * 12 + new Date().getMonth() - birth.getMonth();
  return months < 24 ? `${months} mois` : `${Math.floor(months / 12)} ans`;
}

// ── Sub-components ────────────────────────────────────────────────────────────

function InfoGrid({ rows }: { rows: { label: string; value: string | null | undefined }[] }) {
  return (
    <div className="grid grid-cols-2 gap-3 text-sm">
      {rows.map(r => (
        <div key={r.label}>
          <p className="text-[10px] text-gray-400 uppercase tracking-wide">{r.label}</p>
          <p className="font-medium text-[#1F2A2E]">{r.value || '—'}</p>
        </div>
      ))}
    </div>
  );
}

function Card({ title, children }: { title?: string; children: React.ReactNode }) {
  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-5">
      {title && <h3 className="font-bold text-sm text-[#1F2A2E] mb-4" style={{ fontFamily: 'Galey, sans-serif' }}>{title}</h3>}
      {children}
    </div>
  );
}

function EmptyState({ text }: { text: string }) {
  return <p className="text-center py-10 text-gray-400 text-sm">{text}</p>;
}

// ── Main page ─────────────────────────────────────────────────────────────────

export default function PatientDetailPage() {
  const { user, userData } = useAuth();
  const router = useRouter();
  const params = useParams();
  const animalId = params.id as string;
  const activeProfileId = useActiveProfile();

  const [catPro, setCatPro] = useState('');
  const [tab, setTab] = useState('Identité');
  const [animal, setAnimal] = useState<Animal | null>(null);
  const [owner, setOwner] = useState<Owner | null>(null);
  const [grant, setGrant] = useState<Grant | null>(null);
  const [loading, setLoading] = useState(true);

  // Santé
  const [vaccins, setVaccins] = useState<VaccinEntry[]>([]);
  const [visites, setVisites] = useState<VisiteEntry[]>([]);
  const [traitements, setTraitements] = useState<TraitementEntry[]>([]);
  // Consultations (soignants)
  const [comptesRendus, setComptesRendus] = useState<CompteRendu[]>([]);
  const [ordonnances, setOrdonnances] = useState<Ordonnance[]>([]);
  const [radios, setRadios] = useState<RadioEntry[]>([]);
  // Repro
  const [chaleurs, setChaleurs] = useState<Chaleur[]>([]);
  const [saillies, setSaillies] = useState<Saillie[]>([]);
  const [gestations, setGestations] = useState<Gestation[]>([]);
  // Éducation (rapports de séance + exercices conseillés)
  const [rapports, setRapports] = useState<{ id: string; date_seance: string; contenu: string; exercices_conseilles: string | null }[]>([]);
  const [showAddRapport, setShowAddRapport] = useState(false);
  const [rapportContenu, setRapportContenu] = useState('');
  const [rapportExercices, setRapportExercices] = useState('');
  const [savingRapport, setSavingRapport] = useState(false);

  // Add entry form
  type AddType = null | 'vaccin' | 'visite' | 'traitement' | 'ordonnance' | 'radio' | 'cr' | 'mesure';
  const [addingType, setAddingType] = useState<AddType>(null);
  const [showAddMenu, setShowAddMenu] = useState(false);
  const [formDate, setFormDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [formMotif, setFormMotif] = useState('');
  const [formDiag, setFormDiag] = useState('');
  const [formNotes, setFormNotes] = useState('');
  const [formNom, setFormNom] = useState('');
  const [formLot, setFormLot] = useState('');
  const [formRappel, setFormRappel] = useState('');
  const [formPosologie, setFormPosologie] = useState('');
  const [formDateFin, setFormDateFin] = useState('');
  const [formTitre, setFormTitre] = useState('');
  const [formPoids, setFormPoids] = useState('');
  const [formTaille, setFormTaille] = useState('');
  const [savingForm, setSavingForm] = useState(false);
  const [requestingWrite, setRequestingWrite] = useState(false);
  const [openingChat, setOpeningChat] = useState(false);

  // Pro type
  useEffect(() => {
    if (activeProfileId) {
      supabase.from('user_profiles').select('profile_type, cat_pro').eq('id', activeProfileId).single()
        .then(({ data }) => {
          if (data) { const r = data as { profile_type: string; cat_pro: string }; setCatPro(r.profile_type ?? r.cat_pro ?? ''); }
        });
    } else { setCatPro(userData?.catPro ?? ''); }
  }, [activeProfileId, userData]);

  const isPensionType = PENSION_TYPES.has(catPro);
  const isVet = catPro === 'veterinaire' || catPro === 'sante';
  const isEducation = catPro === 'education';
  const hasWriteAccess = isVet
    ? (grant?.statut === 'active' || grant?.statut === 'active_write')
    : grant?.statut === 'active_write';
  const writeRequested = grant?.statut === 'write_requested';
  const isPending = grant?.statut === 'pending';

  const TABS: string[] = isPensionType
    ? ['Identité', 'Santé', 'Alimentation', 'Propriétaire']
    : isVet
      ? ['Identité', 'Santé', 'Repro', 'Propriétaire', 'Consultations']
      : isEducation
        ? ['Identité', 'Santé', 'Éducation', 'Propriétaire']
        : ['Identité', 'Santé', 'Propriétaire', 'Consultations'];

  // Load data
  useEffect(() => {
    if (!user || !animalId || !activeProfileId) return;
    async function load() {
      const [animalRes, grantRes] = await Promise.all([
        supabase.from('animaux').select('*').eq('id', animalId).single(),
        supabase.from('animal_access').select('id, statut, pro_profile_id')
          .eq('pro_profile_id', activeProfileId).eq('animal_id', animalId).maybeSingle(),
      ]);
      const a = animalRes.data as Animal | null;
      setAnimal(a);
      setGrant(grantRes.data as Grant | null);
      if (!a) { setLoading(false); return; }

      const ownerUid = a.uid_proprietaire ?? a.uid_eleveur;
      const isFemelle = a.sexe?.toLowerCase() === 'femelle';

      const results = await Promise.allSettled([
        ownerUid
          ? supabase.from('users').select('uid, firstname, lastname, name_elevage, email, phone_number, numero_elevage, adress_elevage, rue_elevage, ville_elevage, code_postal_elevage, ville, code_postal, is_elevage, is_pro').eq('uid', ownerUid).maybeSingle()
          : Promise.resolve({ data: null }),
        supabase.from('vaccinations').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
        supabase.from('visites').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
        supabase.from('traitements').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
        supabase.from('comptes_rendus').select('*').eq('animal_id', animalId).order('created_at', { ascending: false }),
        supabase.from('ordonnances').select('*').eq('animal_id', animalId).order('date_emit', { ascending: false }),
        supabase.from('radios').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
        isFemelle ? supabase.from('chaleurs').select('*').eq('animal_id', animalId).order('date', { ascending: false }) : Promise.resolve({ data: [] }),
        supabase.from('saillies').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
        isFemelle ? supabase.from('gestations').select('*').eq('animal_id', animalId).order('date', { ascending: false }) : Promise.resolve({ data: [] }),
        supabase.from('education_progression').select('id, date_seance, contenu, exercices_conseilles').eq('animal_id', animalId).order('date_seance', { ascending: false }),
      ]);

      const get = <T,>(i: number): T[] => {
        const r = results[i];
        if (r.status === 'fulfilled') return ((r.value as { data: unknown }).data ?? []) as T[];
        return [];
      };
      const getSingle = <T,>(i: number): T | null => {
        const r = results[i];
        if (r.status === 'fulfilled') return (r.value as { data: unknown }).data as T | null;
        return null;
      };

      setOwner(getSingle<Owner>(0));
      setVaccins(get<VaccinEntry>(1));
      setVisites(get<VisiteEntry>(2));
      setTraitements(get<TraitementEntry>(3));
      setComptesRendus(get<CompteRendu>(4));
      setOrdonnances(get<Ordonnance>(5));
      setRadios(get<RadioEntry>(6));
      setChaleurs(get<Chaleur>(7));
      setSaillies(get<Saillie>(8));
      setGestations(get<Gestation>(9));
      setRapports(get<{ id: string; date_seance: string; contenu: string; exercices_conseilles: string | null }>(10));
      setLoading(false);
    }
    load();
  }, [user, animalId, activeProfileId]);

  async function saveForm() {
    if (!user?.uid || !animalId) return;
    setSavingForm(true);
    const vetName = (userData?.nameElevage ?? (`${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim())) || undefined;
    const base = { animal_id: animalId, vet_id: user.uid, source: 'veterinaire', veterinaire: vetName };
    try {
      if (addingType === 'vaccin') {
        await supabase.from('vaccinations').insert({ ...base, vaccin: formNom.trim(), date: formDate, date_rappel: formRappel || null, lot: formLot.trim() || null });
        const { data } = await supabase.from('vaccinations').select('*').eq('animal_id', animalId).order('date', { ascending: false });
        setVaccins((data ?? []) as VaccinEntry[]);
      } else if (addingType === 'visite') {
        await supabase.from('visites').insert({ ...base, ...(activeProfileId ? { vet_profile_id: activeProfileId } : {}), date: formDate, motif: formMotif.trim() || null, diagnostic: formDiag.trim() || null, notes: formNotes.trim() || null });
        const { data } = await supabase.from('visites').select('*').eq('animal_id', animalId).order('date', { ascending: false });
        setVisites((data ?? []) as VisiteEntry[]);
      } else if (addingType === 'traitement') {
        await supabase.from('traitements').insert({ ...base, nom: formNom.trim(), posologie: formPosologie.trim() || null, date: formDate, date_fin: formDateFin || null, notes: formNotes.trim() || null });
        const { data } = await supabase.from('traitements').select('*').eq('animal_id', animalId).order('date', { ascending: false });
        setTraitements((data ?? []) as TraitementEntry[]);
      } else if (addingType === 'ordonnance') {
        const ownerUid = animal?.uid_proprietaire ?? animal?.uid_eleveur ?? null;
        let ownerProfileId: string | null = null;
        if (ownerUid) {
          const { data: ownerProfile } = await supabase.from('user_profiles').select('id').eq('uid', ownerUid).eq('is_main', true).maybeSingle();
          ownerProfileId = ownerProfile?.id ?? null;
        }
        const pid = activeProfileId || null;
        await supabase.from('ordonnances').insert({
          animal_id: animalId,
          pro_uid: user.uid,
          ...(pid ? { pro_profile_id: pid } : {}),
          owner_uid: ownerUid,
          ...(ownerProfileId ? { owner_profile_id: ownerProfileId } : {}),
          date_emit: formDate,
          notes: formNotes.trim() || null,
        });
        const { data } = await supabase.from('ordonnances').select('*').eq('animal_id', animalId).order('date_emit', { ascending: false });
        setOrdonnances((data ?? []) as Ordonnance[]);
      } else if (addingType === 'radio') {
        await supabase.from('radios').insert({ ...base, titre: formTitre.trim() || 'Radio / Examen', date: formDate, notes: formNotes.trim() || null });
        const { data } = await supabase.from('radios').select('*').eq('animal_id', animalId).order('date', { ascending: false });
        setRadios((data ?? []) as RadioEntry[]);
      } else if (addingType === 'cr') {
        const ownerUid = animal?.uid_proprietaire ?? animal?.uid_eleveur ?? null;
        const contenu = [
          formMotif.trim() && `Motif : ${formMotif.trim()}`,
          formDiag.trim() && `Diagnostic : ${formDiag.trim()}`,
          formNotes.trim() && formNotes.trim(),
        ].filter(Boolean).join('\n\n');
        await supabase.from('comptes_rendus').insert({ animal_id: animalId, pro_uid: user.uid, owner_uid: ownerUid, contenu: contenu || null });
        const { data } = await supabase.from('comptes_rendus').select('*').eq('animal_id', animalId).order('created_at', { ascending: false });
        setComptesRendus((data ?? []) as CompteRendu[]);
      } else if (addingType === 'mesure') {
        const updates: Record<string, number> = {};
        if (formPoids.trim()) updates.poids = parseFloat(formPoids);
        if (formTaille.trim()) updates.taille = parseFloat(formTaille);
        if (Object.keys(updates).length > 0) {
          await supabase.from('animaux').update(updates).eq('id', animalId);
          setAnimal(a => a ? { ...a, ...updates } : a);
        }
      }
    } finally {
      setFormNom(''); setFormLot(''); setFormRappel(''); setFormMotif(''); setFormDiag('');
      setFormNotes(''); setFormPosologie(''); setFormDateFin(''); setFormTitre('');
      setFormPoids(''); setFormTaille('');
      setFormDate(new Date().toISOString().slice(0, 10));
      setAddingType(null); setSavingForm(false);
    }
  }

  async function soumettreRapport() {
    if (!user?.uid || !animalId || !rapportContenu.trim()) return;
    setSavingRapport(true);
    try {
      const ownerUid = animal?.uid_proprietaire ?? animal?.uid_eleveur ?? null;
      await supabase.from('education_progression').insert({
        pro_uid: user.uid,
        animal_id: animalId,
        owner_uid: ownerUid,
        date_seance: new Date().toISOString().slice(0, 10),
        contenu: rapportContenu.trim(),
        exercices_conseilles: rapportExercices.trim() || null,
      });
      if (ownerUid) {
        const proNom = (userData?.nameElevage ?? (`${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim())) || 'Votre éducateur';
        await supabase.from('notifications').insert({
          uid: ownerUid, type: 'education_rapport',
          title: `Rapport de séance — ${animal?.nom ?? 'Animal'}`,
          body: `${proNom} a envoyé un rapport de séance pour ${animal?.nom ?? 'votre animal'}.`,
          data: { animalId, animalNom: animal?.nom ?? 'Animal' },
          read: false,
        });
      }
      const { data } = await supabase.from('education_progression')
        .select('id, date_seance, contenu, exercices_conseilles').eq('animal_id', animalId).order('date_seance', { ascending: false });
      setRapports((data ?? []) as { id: string; date_seance: string; contenu: string; exercices_conseilles: string | null }[]);
      setRapportContenu(''); setRapportExercices(''); setShowAddRapport(false);
    } finally {
      setSavingRapport(false);
    }
  }

  async function requestWriteAccess() {
    if (!user || !grant || !animal) return;
    setRequestingWrite(true);
    await supabase.from('animal_access').update({ statut: 'write_requested' }).eq('id', grant.id);
    setGrant(g => g ? { ...g, statut: 'write_requested' } : g);
    const ownerUid = animal.uid_proprietaire ?? animal.uid_eleveur;
    if (ownerUid) {
      await supabase.from('notifications').insert({
        uid: ownerUid, type: 'write_access_requested',
        title: "Demande d'accès en écriture",
        body: `${userData?.nameElevage ?? userData?.firstname ?? 'Un professionnel'} demande l'accès en écriture pour ${animal.nom}.`,
        data: { grant_id: grant.id, animal_id: String(animalId) }, read: false,
      });
    }
    setRequestingWrite(false);
  }

  async function openChat(ownerUid: string) {
    if (!user) return;
    setOpeningChat(true);
    try {
      const sorted = [user.uid, ownerUid].sort();
      const participantIds = sorted.join('_');
      const snap = await getDocs(query(collection(db, 'conversations'), where('participantIds', '==', participantIds)));
      let convId: string;
      if (!snap.empty) {
        convId = snap.docs[0].id;
      } else {
        const ref = await addDoc(collection(db, 'conversations'), {
          participants: sorted,
          participantIds,
          lastMessage: '',
          timestamp: serverTimestamp(),
          categorie: 'services',
          unreadCount: { [user.uid]: 0, [ownerUid]: 0 },
        });
        convId = ref.id;
      }
      router.push(`/messages?conv=${convId}`);
    } finally {
      setOpeningChat(false);
    }
  }

  if (!user) return null;
  if (loading) return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="w-8 h-8 border-4 border-t-transparent rounded-full animate-spin" style={{ borderColor: TEAL, borderTopColor: 'transparent' }} />
    </div>
  );
  if (!animal) return (
    <div className="min-h-screen flex items-center justify-center text-gray-400 text-sm">Animal introuvable ou accès refusé.</div>
  );

  const ownerName = owner
    ? (owner.is_elevage || owner.is_pro) && owner.name_elevage
      ? owner.name_elevage
      : [owner.firstname, owner.lastname].filter(Boolean).join(' ') || 'Propriétaire'
    : '—';

  return (
    <div className="min-h-screen bg-[#F8F8F8]">

      {/* ── Header ── */}
      <div style={{ background: TEAL }} className="text-white">
        <div className="max-w-3xl mx-auto px-4 pt-4 pb-2 flex items-center gap-3">
          <button onClick={() => router.back()} className="p-2 rounded-lg bg-white/10 hover:bg-white/20 transition-colors">←</button>
          <span className="font-bold text-base flex-1" style={{ fontFamily: 'Galey, sans-serif' }}>Fiche patient</span>
          {hasWriteAccess && (
            <span className="text-[10px] font-bold bg-green-400/30 text-green-100 px-2 py-0.5 rounded-full">✏️ Écriture</span>
          )}
          {isPending && (
            <span className="text-[10px] font-bold bg-amber-400/30 text-amber-100 px-2 py-0.5 rounded-full">⏳ En attente</span>
          )}
        </div>

        {/* Animal summary */}
        <div className="max-w-3xl mx-auto px-4 py-3 flex items-center gap-4">
          <div className="w-16 h-16 rounded-2xl overflow-hidden bg-white/20 flex-shrink-0 flex items-center justify-center">
            {animal.photo_url
              ? <Image src={animal.photo_url} alt="" width={64} height={64} className="object-cover w-full h-full" />
              : <span className="text-3xl">{ESPECE_EMOJI[animal.espece?.toLowerCase()] ?? '🐾'}</span>
            }
          </div>
          <div className="min-w-0">
            <h2 className="text-xl font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>{animal.nom}</h2>
            <p className="text-white/70 text-sm">{[animal.race, animal.espece].filter(Boolean).join(' · ')}{animal.date_naissance ? ` · ${calcAge(animal.date_naissance)}` : ''}</p>
            <div className="flex flex-wrap gap-1.5 mt-1">
              {animal.sexe && <span className="text-[10px] bg-white/20 px-2 py-0.5 rounded-full capitalize">{animal.sexe}</span>}
              {animal.sterilise && <span className="text-[10px] bg-white/20 px-2 py-0.5 rounded-full">Stérilisé(e)</span>}
              {animal.poids && <span className="text-[10px] bg-white/20 px-2 py-0.5 rounded-full">{animal.poids} kg</span>}
              {animal.identification && <span className="text-[10px] bg-white/20 px-2 py-0.5 rounded-full font-mono">🔖 {animal.identification}</span>}
            </div>
          </div>
        </div>

        {/* Tabs */}
        <div className="max-w-3xl mx-auto px-4 overflow-x-auto pb-0">
          <div className="flex gap-1 bg-white/10 rounded-xl p-1 min-w-max">
            {TABS.map(t => (
              <button key={t} onClick={() => setTab(t)}
                className="whitespace-nowrap px-4 py-2 text-sm font-semibold rounded-lg transition-colors"
                style={{
                  background: tab === t ? 'white' : 'transparent',
                  color: tab === t ? TEAL : 'rgba(255,255,255,0.75)',
                  fontFamily: 'Galey, sans-serif',
                }}>
                {t}
              </button>
            ))}
          </div>
        </div>
        <div className="h-4" />
      </div>

      {/* ── Content ── */}
      <div className="max-w-3xl mx-auto px-4 py-5 space-y-4">

        {/* ── Identité ── */}
        {tab === 'Identité' && (
          <>
            <Card title="Identité">
              <InfoGrid rows={[
                { label: 'Espèce',        value: animal.espece },
                { label: 'Race',          value: animal.race },
                { label: 'Sexe',          value: animal.sexe },
                { label: 'Couleur/Robe',  value: animal.couleur },
                { label: 'Date de naissance', value: fmtDate(animal.date_naissance) },
                { label: 'Âge',           value: calcAge(animal.date_naissance) },
                { label: 'Poids',         value: animal.poids ? `${animal.poids} kg` : null },
                { label: 'Taille',        value: animal.taille ? `${animal.taille} cm` : null },
                { label: 'Identification',value: animal.identification },
                { label: 'Passeport',     value: animal.passeport_numero },
                { label: 'Stérilisé(e)', value: animal.sterilise === true ? 'Oui' : animal.sterilise === false ? 'Non' : null },
              ]} />
            </Card>

            {animal.notes && (
              <Card title="Notes du propriétaire">
                <p className="text-sm text-gray-600 whitespace-pre-wrap">{animal.notes}</p>
              </Card>
            )}

            {/* Accès en écriture pour non-vets */}
            {!isVet && grant && (
              <Card title="Accès au dossier">
                {hasWriteAccess ? (
                  <div className="flex items-center gap-2 text-green-600 text-sm">
                    <span>✓</span>
                    <p>Accès en écriture accordé — vous pouvez noter des observations.</p>
                  </div>
                ) : writeRequested ? (
                  <div className="flex items-center gap-2 text-amber-600 text-sm bg-amber-50 rounded-xl p-3">
                    <span>⏳</span>
                    <p>Demande d&apos;accès en écriture envoyée, en attente de validation.</p>
                  </div>
                ) : (
                  <>
                    <p className="text-sm text-gray-500 mb-3">Accès en lecture. En cas de besoin, demandez l&apos;accès en écriture au propriétaire.</p>
                    <button onClick={requestWriteAccess} disabled={requestingWrite}
                      className="text-sm font-semibold text-white px-4 py-2 rounded-xl transition-colors disabled:opacity-50"
                      style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
                      {requestingWrite ? '…' : "Demander l'accès en écriture"}
                    </button>
                  </>
                )}
              </Card>
            )}

            {isPending && (
              <div className="bg-amber-50 border border-amber-200 rounded-2xl p-4 flex gap-3">
                <span className="text-xl">⏳</span>
                <div>
                  <p className="font-semibold text-amber-800 text-sm">En attente d&apos;approbation</p>
                  <p className="text-xs text-amber-600 mt-0.5">Le propriétaire n&apos;a pas encore validé votre accès à ce dossier.</p>
                </div>
              </div>
            )}
          </>
        )}

        {/* ── Santé ── */}
        {tab === 'Santé' && (
          <>
            {isPensionType && (
              <div className="bg-blue-50 border border-blue-200 rounded-2xl p-3 flex gap-2 items-center text-blue-700 text-xs font-medium">
                <span>📖</span><span>Lecture seule — accordé par le propriétaire</span>
              </div>
            )}

            {/* Vaccins */}
            <Card title={`💉 Vaccinations (${vaccins.length})`}>
              {vaccins.length === 0 ? <EmptyState text="Aucun vaccin enregistré" /> : (
                <div className="space-y-3">
                  {vaccins.map(v => {
                    const due = v.date_rappel && new Date(v.date_rappel) <= new Date();
                    return (
                      <div key={v.id} className="border border-gray-100 rounded-xl p-3 flex items-start gap-3">
                        <div className="w-8 h-8 rounded-lg bg-[#E3F2FD] flex items-center justify-center text-sm flex-shrink-0">💉</div>
                        <div className="flex-1 min-w-0">
                          <p className="font-semibold text-sm text-[#1F2A2E]">{v.vaccin}</p>
                          <p className="text-xs text-gray-500">Injecté le {fmtDateShort(v.date)}</p>
                          {v.date_rappel && (
                            <p className={`text-xs font-medium mt-0.5 ${due ? 'text-red-500' : 'text-[#0C5C6C]'}`}>
                              {due ? '⚠️ Rappel dû' : '📅 Rappel'} le {fmtDateShort(v.date_rappel)}
                            </p>
                          )}
                          {v.lot && <p className="text-xs text-gray-400">Lot : {v.lot}</p>}
                          {v.veterinaire && <p className="text-xs text-gray-400">Dr {v.veterinaire}</p>}
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </Card>

            {/* Visites / Consultations */}
            <Card title={`🩺 Visites vétérinaires (${visites.length})`}>
              {visites.length === 0 ? <EmptyState text="Aucune visite enregistrée" /> : (
                <div className="space-y-3">
                  {visites.map(v => (
                    <div key={v.id} className="border border-gray-100 rounded-xl p-3">
                      <div className="flex items-center justify-between mb-1">
                        <p className="font-semibold text-sm text-[#1F2A2E]">{fmtDateShort(v.date)}</p>
                        {v.motif && <span className="text-[10px] bg-[#E3F2FD] text-[#0C5C6C] px-2 py-0.5 rounded-full font-medium">{v.motif}</span>}
                      </div>
                      {v.diagnostic && <p className="text-xs text-gray-600"><span className="font-medium">Diagnostic : </span>{v.diagnostic}</p>}
                      {v.notes && <p className="text-xs text-gray-400 mt-1">{v.notes}</p>}
                      {v.veterinaire && <p className="text-xs text-gray-400 mt-0.5">Dr {v.veterinaire}</p>}
                    </div>
                  ))}
                </div>
              )}
            </Card>

            {/* Traitements */}
            <Card title={`💊 Traitements (${traitements.length})`}>
              {traitements.length === 0 ? <EmptyState text="Aucun traitement enregistré" /> : (
                <div className="space-y-3">
                  {traitements.map(t => (
                    <div key={t.id} className="border border-gray-100 rounded-xl p-3">
                      <div className="flex items-center justify-between mb-1">
                        <p className="font-semibold text-sm text-[#1F2A2E]">{t.nom}</p>
                        <p className="text-xs text-gray-400">{fmtDateShort(t.date)}</p>
                      </div>
                      {t.posologie && <p className="text-xs text-gray-600">{t.posologie}</p>}
                      {t.date_fin && <p className="text-xs text-gray-400">Fin : {fmtDateShort(t.date_fin)}</p>}
                      {t.notes && <p className="text-xs text-gray-400 mt-1">{t.notes}</p>}
                    </div>
                  ))}
                </div>
              )}
            </Card>
            {/* Mesures */}
            {(animal.poids || animal.taille) && (
              <Card title="⚖️ Mesures">
                <div className="grid grid-cols-2 gap-4">
                  {animal.poids != null && (
                    <div className="bg-[#E3F2FD] rounded-xl p-4 text-center">
                      <p className="text-2xl font-bold text-[#0C5C6C]" style={{ fontFamily: 'Galey, sans-serif' }}>{animal.poids} kg</p>
                      <p className="text-xs text-gray-500 mt-1">Poids</p>
                    </div>
                  )}
                  {animal.taille != null && (
                    <div className="bg-[#E3F2FD] rounded-xl p-4 text-center">
                      <p className="text-2xl font-bold text-[#0C5C6C]" style={{ fontFamily: 'Galey, sans-serif' }}>{animal.taille} cm</p>
                      <p className="text-xs text-gray-500 mt-1">Taille</p>
                    </div>
                  )}
                </div>
                {hasWriteAccess && (
                  <button onClick={() => setAddingType('mesure')}
                    className="mt-3 w-full text-sm font-semibold py-2 rounded-xl border border-[#0C5C6C] text-[#0C5C6C] hover:bg-[#E3F2FD] transition-colors"
                    style={{ fontFamily: 'Galey, sans-serif' }}>
                    + Mettre à jour les mesures
                  </button>
                )}
              </Card>
            )}
          </>
        )}

        {/* ── Repro ── */}
        {tab === 'Repro' && (
          <>
            {animal.sexe?.toLowerCase() === 'femelle' && (
              <>
                <Card title={`🌡️ Chaleurs (${chaleurs.length})`}>
                  {chaleurs.length === 0 ? <EmptyState text="Aucune chaleur enregistrée" /> : (
                    <div className="space-y-2">
                      {chaleurs.map(c => (
                        <div key={c.id} className="border border-gray-100 rounded-xl p-3">
                          <p className="text-sm font-medium text-[#1F2A2E]">
                            {fmtDateShort(c.date)}{c.date_fin ? ` → ${fmtDateShort(c.date_fin)}` : ''}
                          </p>
                          {c.duree != null && <p className="text-xs text-gray-500">{c.duree} jour{c.duree > 1 ? 's' : ''}</p>}
                          {c.notes && <p className="text-xs text-gray-400 mt-1">{c.notes}</p>}
                        </div>
                      ))}
                    </div>
                  )}
                </Card>

                <Card title={`🤰 Gestations (${gestations.length})`}>
                  {gestations.length === 0 ? <EmptyState text="Aucune gestation enregistrée" /> : (
                    <div className="space-y-2">
                      {gestations.map(g => (
                        <div key={g.id} className="border border-gray-100 rounded-xl p-3">
                          {g.date && <p className="text-xs text-gray-500">Saillie : {fmtDateShort(g.date)}</p>}
                          {g.date_prevue && <p className="text-sm font-medium text-[#1F2A2E]">Naissance prévue : {fmtDateShort(g.date_prevue)}</p>}
                          {g.date_naissance && <p className="text-sm font-medium text-green-600">Naissance : {fmtDateShort(g.date_naissance)}</p>}
                          {g.gestation_confirmee && <span className="text-[10px] bg-green-50 text-green-600 font-bold px-1.5 py-0.5 rounded-full">Confirmée</span>}
                          {g.nb_attendu != null && <p className="text-xs text-gray-500">{g.nb_attendu} petit(s) attendu(s){g.nb_nes != null ? ` · ${g.nb_nes} né(s)` : ''}</p>}
                          {g.notes && <p className="text-xs text-gray-400 mt-1">{g.notes}</p>}
                        </div>
                      ))}
                    </div>
                  )}
                </Card>
              </>
            )}

            <Card title={`❤️ Saillies (${saillies.length})`}>
              {saillies.length === 0 ? <EmptyState text="Aucune saillie enregistrée" /> : (
                <div className="space-y-2">
                  {saillies.map(s => (
                    <div key={s.id} className="border border-gray-100 rounded-xl p-3">
                      <p className="text-sm font-medium text-[#1F2A2E]">{fmtDateShort(s.date)}</p>
                      {s.nom_partenaire && <p className="text-xs text-gray-500">Partenaire : {s.nom_partenaire}</p>}
                      {s.methode && <p className="text-xs text-gray-400">Méthode : {s.methode}</p>}
                      {s.notes && <p className="text-xs text-gray-400 mt-1">{s.notes}</p>}
                    </div>
                  ))}
                </div>
              )}
            </Card>

            {animal.sexe?.toLowerCase() !== 'femelle' && saillies.length === 0 && chaleurs.length === 0 && (
              <EmptyState text="Aucune donnée de reproduction enregistrée" />
            )}
          </>
        )}

        {/* ── Alimentation (pension) ── */}
        {tab === 'Alimentation' && (
          <Card title="🍽️ Alimentation">
            <div className="bg-blue-50 border border-blue-200 rounded-xl p-3 flex gap-2 items-center text-blue-700 text-xs font-medium mb-4">
              <span>📖</span><span>Données renseignées par le propriétaire — lecture seule</span>
            </div>
            <EmptyState text="Plan alimentaire non renseigné par le propriétaire" />
          </Card>
        )}

        {/* ── Éducation (rapports de séance + exercices conseillés) ── */}
        {tab === 'Éducation' && (
          <Card title="🎓 Suivi de progression">
            {hasWriteAccess && (
              <button onClick={() => setShowAddRapport(v => !v)}
                className="w-full text-white rounded-2xl py-3 font-semibold text-sm transition-colors flex items-center justify-center gap-2 mb-4"
                style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
                <span className="text-lg leading-none">+</span>
                Ajouter un rapport de séance
              </button>
            )}
            {showAddRapport && (
              <div className="border border-gray-100 rounded-2xl p-4 mb-4 space-y-3">
                <div>
                  <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide block mb-1">Compte rendu</label>
                  <textarea value={rapportContenu} onChange={e => setRapportContenu(e.target.value)} rows={3}
                    placeholder="Déroulé de la séance, observations, progrès…"
                    className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
                </div>
                <div>
                  <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide block mb-1">Exercices conseillés</label>
                  <textarea value={rapportExercices} onChange={e => setRapportExercices(e.target.value)} rows={2}
                    placeholder="Exercices à faire à la maison d'ici la prochaine séance…"
                    className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
                </div>
                <button onClick={soumettreRapport} disabled={savingRapport || !rapportContenu.trim()}
                  className="w-full text-white rounded-xl py-2.5 text-sm font-semibold disabled:opacity-50"
                  style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
                  {savingRapport ? '…' : 'Envoyer au propriétaire'}
                </button>
              </div>
            )}
            {rapports.length === 0 ? (
              <EmptyState text="Aucun rapport de séance pour l'instant" />
            ) : (
              <div className="space-y-3">
                {rapports.map(r => (
                  <div key={r.id} className="border border-gray-100 rounded-xl p-3">
                    <p className="text-xs text-gray-400 mb-1">{fmtDateShort(r.date_seance)}</p>
                    <p className="text-sm text-[#1F2A2E]">{r.contenu}</p>
                    {r.exercices_conseilles && (
                      <div className="mt-2 bg-[#EEF5EA] rounded-lg px-2.5 py-1.5">
                        <p className="text-xs font-semibold text-[#4A7A32] mb-0.5">🏋️ Exercices conseillés</p>
                        <p className="text-xs text-[#4A7A32]">{r.exercices_conseilles}</p>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </Card>
        )}

        {/* ── Propriétaire ── */}
        {tab === 'Propriétaire' && (
          <Card title="👤 Propriétaire">
            {!owner ? (
              <EmptyState text="Informations du propriétaire non disponibles" />
            ) : (
              <div className="space-y-4">
                <div className="flex items-center gap-3">
                  <div className="w-12 h-12 rounded-full bg-[#E3F2FD] flex items-center justify-center text-xl flex-shrink-0">
                    {owner.is_elevage ? '🏡' : '👤'}
                  </div>
                  <div>
                    <p className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>{ownerName}</p>
                    {owner.is_elevage && owner.name_elevage && (
                      <p className="text-xs text-gray-500">Élevage</p>
                    )}
                  </div>
                </div>
                <div className="border-t border-gray-50 pt-4">
                  <InfoGrid rows={[
                    { label: 'Email', value: owner.email },
                    {
                      label: 'Téléphone',
                      value: (owner.is_elevage || owner.is_pro) && owner.numero_elevage
                        ? owner.numero_elevage
                        : owner.phone_number,
                    },
                    {
                      label: 'Adresse',
                      value: [
                        owner.rue_elevage ?? owner.adress_elevage,
                        [owner.code_postal_elevage ?? owner.code_postal, owner.ville_elevage ?? owner.ville].filter(Boolean).join(' '),
                      ].filter(Boolean).join(', ') || null,
                    },
                  ]} />
                </div>
                <div className="flex gap-2 mt-2">
                  <button onClick={() => openChat(owner.uid)} disabled={openingChat}
                    className="flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-sm font-semibold text-white transition-colors disabled:opacity-60"
                    style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
                    {openingChat ? '…' : '💬 Envoyer un message'}
                  </button>
                  {owner.email && (
                    <a href={`mailto:${owner.email}`}
                      className="flex items-center justify-center gap-2 px-4 py-2.5 rounded-xl text-sm font-semibold border border-gray-200 text-gray-600 hover:bg-gray-50 transition-colors">
                      ✉️
                    </a>
                  )}
                </div>
              </div>
            )}
          </Card>
        )}

        {/* ── Consultations (carnet de santé complet) ── */}
        {tab === 'Consultations' && (
          <>
            {/* Bouton + avec submenu */}
            {hasWriteAccess && (
              <div className="relative">
                <button onClick={() => setShowAddMenu(v => !v)}
                  className="w-full text-white rounded-2xl py-3 font-semibold text-sm transition-colors flex items-center justify-center gap-2"
                  style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
                  <span className="text-lg leading-none">+</span>
                  {isVet ? 'Ajouter au dossier' : 'Ajouter une observation'}
                </button>
                {showAddMenu && (
                  <div className="absolute top-full left-0 right-0 mt-1 bg-white rounded-2xl shadow-lg border border-gray-100 z-10 overflow-hidden">
                    {[
                      { type: 'cr',         label: '📋 Rédiger un CR',       show: isVet },
                      { type: 'vaccin',     label: '💉 Vaccin',               show: true },
                      { type: 'visite',     label: '🩺 Visite vétérinaire',   show: isVet },
                      { type: 'traitement', label: '💊 Traitement',            show: true },
                      { type: 'ordonnance', label: '📄 Ordonnance',            show: isVet },
                      { type: 'radio',      label: '🩻 Radio / Examen',        show: isVet },
                      { type: 'mesure',     label: '⚖️ Nouvelle mesure',       show: isVet },
                    ].filter(i => i.show).map(item => (
                      <button key={item.type}
                        onClick={() => { setAddingType(item.type as AddType); setShowAddMenu(false); }}
                        className="w-full text-left px-4 py-3 text-sm font-medium text-[#1F2A2E] hover:bg-gray-50 border-b border-gray-50 last:border-0 transition-colors"
                        style={{ fontFamily: 'Galey, sans-serif' }}>
                        {item.label}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )}

            {!hasWriteAccess && !writeRequested && (
              <div className="bg-amber-50 border border-amber-200 rounded-2xl p-4 flex gap-3 items-start">
                <span className="text-xl">📖</span>
                <div>
                  <p className="text-sm font-semibold text-amber-800">Lecture seule</p>
                  <p className="text-xs text-amber-600 mt-0.5">Demandez l&apos;accès en écriture depuis l&apos;onglet Identité.</p>
                </div>
              </div>
            )}

            {/* Vaccins */}
            <Card title={`💉 Vaccinations (${vaccins.length})`}>
              {vaccins.length === 0 ? <EmptyState text="Aucun vaccin enregistré" /> : (
                <div className="space-y-2">
                  {vaccins.map(v => {
                    const due = v.date_rappel && new Date(v.date_rappel) <= new Date();
                    return (
                      <div key={v.id} className="border border-gray-100 rounded-xl p-3">
                        <div className="flex items-center justify-between">
                          <p className="font-semibold text-sm text-[#1F2A2E]">{v.vaccin}</p>
                          <p className="text-xs text-gray-400">{fmtDateShort(v.date)}</p>
                        </div>
                        {v.date_rappel && <p className={`text-xs mt-0.5 ${due ? 'text-red-500 font-medium' : 'text-[#0C5C6C]'}`}>{due ? '⚠️ Rappel dû' : '📅 Rappel'} le {fmtDateShort(v.date_rappel)}</p>}
                        {v.lot && <p className="text-xs text-gray-400">Lot : {v.lot}</p>}
                        {v.veterinaire && <p className="text-xs text-gray-400">Dr {v.veterinaire}</p>}
                      </div>
                    );
                  })}
                </div>
              )}
            </Card>

            {/* Visites */}
            <Card title={`🩺 Visites vétérinaires (${visites.length})`}>
              {visites.length === 0 ? <EmptyState text="Aucune visite enregistrée" /> : (
                <div className="space-y-3">
                  {visites.map(v => (
                    <div key={v.id} className="border border-gray-100 rounded-xl p-3">
                      <div className="flex items-center justify-between mb-1">
                        <p className="font-semibold text-sm text-[#1F2A2E]">{fmtDateShort(v.date)}</p>
                        {v.motif && <span className="text-[10px] bg-[#E3F2FD] text-[#0C5C6C] px-2 py-0.5 rounded-full">{v.motif}</span>}
                      </div>
                      {v.diagnostic && <p className="text-xs text-gray-600"><span className="font-medium">Diagnostic : </span>{v.diagnostic}</p>}
                      {v.notes && <p className="text-xs text-gray-400 mt-1">{v.notes}</p>}
                      {v.veterinaire && <p className="text-xs text-gray-400 mt-0.5">Dr {v.veterinaire}</p>}
                    </div>
                  ))}
                </div>
              )}
            </Card>

            {/* Traitements */}
            <Card title={`💊 Traitements (${traitements.length})`}>
              {traitements.length === 0 ? <EmptyState text="Aucun traitement enregistré" /> : (
                <div className="space-y-2">
                  {traitements.map(t => (
                    <div key={t.id} className="border border-gray-100 rounded-xl p-3">
                      <div className="flex items-center justify-between">
                        <p className="font-semibold text-sm text-[#1F2A2E]">{t.nom}</p>
                        <p className="text-xs text-gray-400">{fmtDateShort(t.date)}</p>
                      </div>
                      {t.posologie && <p className="text-xs text-gray-600">{t.posologie}</p>}
                      {t.date_fin && <p className="text-xs text-gray-400">Fin : {fmtDateShort(t.date_fin)}</p>}
                      {t.notes && <p className="text-xs text-gray-400 mt-1">{t.notes}</p>}
                    </div>
                  ))}
                </div>
              )}
            </Card>

            {/* Comptes rendus */}
            <Card title={`📋 Comptes rendus (${comptesRendus.length})`}>
              {comptesRendus.length === 0 ? <EmptyState text="Aucun compte rendu enregistré" /> : (
                <div className="space-y-3">
                  {comptesRendus.map(c => (
                    <div key={c.id} className="border border-gray-100 rounded-xl p-3">
                      <p className="text-xs text-gray-400 mb-1">{fmtDateShort(c.created_at)}</p>
                      {c.contenu
                        ? <p className="text-sm text-[#1F2A2E] whitespace-pre-wrap">{c.contenu}</p>
                        : <p className="text-xs text-gray-400 italic">Compte rendu vide</p>
                      }
                    </div>
                  ))}
                </div>
              )}
            </Card>

            {/* Ordonnances */}
            <Card title={`📄 Ordonnances (${ordonnances.length})`}>
              {ordonnances.length === 0 ? <EmptyState text="Aucune ordonnance enregistrée" /> : (
                <div className="space-y-2">
                  {ordonnances.map(o => (
                    <div key={o.id} className="border border-gray-100 rounded-xl p-3 flex items-center gap-3">
                      <span className="text-xl">📄</span>
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-[#1F2A2E]">{fmtDateShort(o.date_emit)}</p>
                        {o.notes && <p className="text-xs text-gray-400">{o.notes}</p>}
                      </div>
                      {o.doc_url && (
                        <a href={o.doc_url} target="_blank" rel="noopener noreferrer"
                          className="text-xs font-semibold px-3 py-1.5 rounded-lg text-white flex-shrink-0"
                          style={{ background: TEAL }}>
                          Voir
                        </a>
                      )}
                    </div>
                  ))}
                </div>
              )}
            </Card>

            {/* Radios / Examens */}
            {isVet && (
              <Card title={`🩻 Radios / Examens (${radios.length})`}>
                {radios.length === 0 ? <EmptyState text="Aucun examen enregistré" /> : (
                  <div className="space-y-2">
                    {radios.map(r => (
                      <div key={r.id} className="border border-gray-100 rounded-xl p-3">
                        <div className="flex items-center justify-between">
                          <p className="font-semibold text-sm text-[#1F2A2E]">{r.titre || 'Radio / Examen'}</p>
                          <p className="text-xs text-gray-400">{fmtDateShort(r.date)}</p>
                        </div>
                        {r.notes && <p className="text-xs text-gray-400 mt-1">{r.notes}</p>}
                        {r.veterinaire && <p className="text-xs text-gray-400">Dr {r.veterinaire}</p>}
                      </div>
                    ))}
                  </div>
                )}
              </Card>
            )}
          </>
        )}
      </div>

      {/* ── Modales d'ajout ── */}
      {addingType && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4"
          onClick={() => setAddingType(null)}>
          <div className="bg-white rounded-2xl w-full max-w-md p-6 space-y-4 max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between">
              <h3 className="font-bold text-base text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
                {addingType === 'cr' && '📋 Rédiger un compte rendu'}
                {addingType === 'vaccin' && '💉 Nouveau vaccin'}
                {addingType === 'visite' && '🩺 Nouvelle visite'}
                {addingType === 'traitement' && '💊 Nouveau traitement'}
                {addingType === 'ordonnance' && '📄 Nouvelle ordonnance'}
                {addingType === 'radio' && '🩻 Radio / Examen'}
                {addingType === 'mesure' && '⚖️ Nouvelle mesure'}
              </h3>
              <button onClick={() => setAddingType(null)} className="text-gray-400 hover:text-gray-600 text-xl">×</button>
            </div>

            {/* Champ date commun (pas pour mesure) */}
            {addingType !== 'mesure' && (
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Date</label>
                <input type="date" value={formDate} onChange={e => setFormDate(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
            )}

            {/* Vaccin */}
            {addingType === 'vaccin' && (<>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Nom du vaccin *</label>
                <input value={formNom} onChange={e => setFormNom(e.target.value)} placeholder="Ex : Primovaccination, Rage, Leptospirose…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Date de rappel</label>
                <input type="date" value={formRappel} onChange={e => setFormRappel(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">N° de lot</label>
                <input value={formLot} onChange={e => setFormLot(e.target.value)} placeholder="Numéro de lot…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
            </>)}

            {/* Visite */}
            {addingType === 'visite' && (<>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Motif</label>
                <select value={formMotif} onChange={e => setFormMotif(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white">
                  <option value="">— Sélectionner —</option>
                  {['Consultation', 'Rappel de vaccin', 'Urgence', 'Suivi post-opératoire', 'Contrôle', 'Autre'].map(m => (
                    <option key={m} value={m}>{m}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Diagnostic / Observations</label>
                <textarea value={formDiag} onChange={e => setFormDiag(e.target.value)} rows={3}
                  placeholder="Examen clinique, diagnostic…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Notes</label>
                <textarea value={formNotes} onChange={e => setFormNotes(e.target.value)} rows={2}
                  placeholder="Notes libres…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
            </>)}

            {/* Traitement */}
            {addingType === 'traitement' && (<>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Nom du produit *</label>
                <input value={formNom} onChange={e => setFormNom(e.target.value)} placeholder="Ex : Amoxicilline, Frontline…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Posologie</label>
                <input value={formPosologie} onChange={e => setFormPosologie(e.target.value)} placeholder="Ex : 1 comprimé matin et soir…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Date de fin</label>
                <input type="date" value={formDateFin} onChange={e => setFormDateFin(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Notes</label>
                <textarea value={formNotes} onChange={e => setFormNotes(e.target.value)} rows={2}
                  placeholder="Notes complémentaires…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
            </>)}

            {/* Ordonnance */}
            {addingType === 'ordonnance' && (<>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Posologie / Instructions</label>
                <textarea value={formNotes} onChange={e => setFormNotes(e.target.value)} rows={3}
                  placeholder="Détail des médicaments, posologie…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
              <p className="text-xs text-gray-400">L&apos;upload de PDF sera disponible prochainement.</p>
            </>)}

            {/* Radio */}
            {addingType === 'radio' && (<>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Titre de l&apos;examen</label>
                <input value={formTitre} onChange={e => setFormTitre(e.target.value)} placeholder="Ex : Radio thorax, Échographie abdominale…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Observations</label>
                <textarea value={formNotes} onChange={e => setFormNotes(e.target.value)} rows={3}
                  placeholder="Résultats, observations…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
              <p className="text-xs text-gray-400">L&apos;upload d&apos;images sera disponible prochainement.</p>
            </>)}

            {/* Compte rendu */}
            {addingType === 'cr' && (<>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Motif de consultation</label>
                <select value={formMotif} onChange={e => setFormMotif(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white">
                  <option value="">— Sélectionner —</option>
                  {['Consultation', 'Rappel de vaccin', 'Urgence', 'Suivi post-opératoire', 'Contrôle', 'Chirurgie', 'Autre'].map(m => (
                    <option key={m} value={m}>{m}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Examen clinique / Diagnostic</label>
                <textarea value={formDiag} onChange={e => setFormDiag(e.target.value)} rows={4}
                  placeholder="Résultats de l'examen, diagnostic posé…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Notes / Recommandations</label>
                <textarea value={formNotes} onChange={e => setFormNotes(e.target.value)} rows={3}
                  placeholder="Suivi recommandé, prescriptions, notes libres…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
            </>)}

            {/* Mesure */}
            {addingType === 'mesure' && (<>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs font-medium text-gray-500 block mb-1">Poids (kg)</label>
                  <input type="number" step="0.1" min="0" value={formPoids} onChange={e => setFormPoids(e.target.value)}
                    placeholder={animal.poids ? String(animal.poids) : 'kg'}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                </div>
                <div>
                  <label className="text-xs font-medium text-gray-500 block mb-1">Taille (cm)</label>
                  <input type="number" step="0.5" min="0" value={formTaille} onChange={e => setFormTaille(e.target.value)}
                    placeholder={animal.taille ? String(animal.taille) : 'cm'}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                </div>
              </div>
              {animal.poids != null && <p className="text-xs text-gray-400">Poids actuel : {animal.poids} kg{animal.taille ? ` · ${animal.taille} cm` : ''}</p>}
            </>)}

            <div className="flex gap-3 pt-1">
              <button onClick={() => setAddingType(null)}
                className="flex-1 border border-gray-200 text-gray-600 text-sm font-medium py-2.5 rounded-xl hover:bg-gray-50 transition-colors">
                Annuler
              </button>
              <button onClick={saveForm} disabled={savingForm}
                className="flex-1 text-white text-sm font-semibold py-2.5 rounded-xl transition-colors disabled:opacity-50"
                style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
                {savingForm ? 'Enregistrement…' : 'Enregistrer'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
