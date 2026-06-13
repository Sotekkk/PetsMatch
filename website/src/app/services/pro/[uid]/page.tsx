'use client';

import { useEffect, useState, Suspense } from 'react';
import { useParams, useSearchParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import VerificationBadge, { getBadgeLevel } from '@/components/VerificationBadge';

// ─── Types ─────────────────────────────────────────────────────────────────────

interface ProData {
  uid: string; name: string; profession: string; description: string;
  ville: string; adresse: string; code_postal: string;
  photo: string; banner: string; accept_new_clients: boolean;
  especes: string[]; horaires: Record<string, string>;
  certifications: { nom: string; numero?: string }[];
  tarifs: string; site_web: string; instagram: string; facebook: string;
  rayon: number; cat_pro: string; profileTableId?: string;
  statut_pro?: string; siret?: string; is_premium?: boolean;
}
interface Slot { date: string; heureDebut: string; heureFin: string; }
interface Animal { id: number; nom: string; espece: string; }

// ─── Données statiques ─────────────────────────────────────────────────────────

const JOURS = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];

const CAT_COLORS: Record<string, string> = {
  veterinaire: '#2196F3', sante: '#2196F3', education: '#FF9800',
  garde: '#4CAF50', toilettage: '#00BCD4', photographe: '#E91E63',
  marechal_ferrant: '#795548', referencement: '#CDDC39', pension: '#4CAF50',
};

const MOTIFS_BY_CAT: Record<string, { key: string; label: string; icon: string; duree: number }[]> = {
  veterinaire: [
    { key: 'consultation', label: 'Consultation',  icon: '🩺', duree: 30 },
    { key: 'vaccination',  label: 'Vaccination',   icon: '💉', duree: 20 },
    { key: 'bilan',        label: 'Bilan annuel',  icon: '📋', duree: 45 },
    { key: 'urgence',      label: 'Urgence',       icon: '🚨', duree: 60 },
    { key: 'chirurgie',    label: 'Chirurgie',     icon: '🔬', duree: 120 },
    { key: 'autre',        label: 'Autre',         icon: '➕', duree: 30 },
  ],
  sante: [
    { key: 'consultation', label: 'Consultation',  icon: '🩺', duree: 45 },
    { key: 'seance',       label: 'Séance',        icon: '💆', duree: 60 },
    { key: 'autre',        label: 'Autre',         icon: '➕', duree: 60 },
  ],
  garde: [
    { key: 'promenade_30min', label: 'Promenade 30 min', icon: '🦮', duree: 30 },
    { key: 'promenade_1h',    label: 'Promenade 1h',     icon: '🦮', duree: 60 },
    { key: 'garde_journee',   label: 'Garde journée',    icon: '🏠', duree: 480 },
    { key: 'autre',           label: 'Autre',            icon: '➕', duree: 60 },
  ],
  pension: [
    { key: 'visite',   label: 'Visite de la pension', icon: '🏡', duree: 30 },
    { key: 'arrivee',  label: 'Arrivée de l\'animal', icon: '📥', duree: 60 },
    { key: 'depart',   label: 'Départ de l\'animal',  icon: '📤', duree: 30 },
    { key: 'autre',    label: 'Autre',                icon: '➕', duree: 30 },
  ],
  education: [
    { key: 'cours_individuel', label: 'Cours individuel', icon: '🎓', duree: 60 },
    { key: 'cours_collectif',  label: 'Cours collectif',  icon: '👥', duree: 90 },
    { key: 'evaluation',       label: 'Évaluation',       icon: '📝', duree: 45 },
    { key: 'autre',            label: 'Autre',            icon: '➕', duree: 60 },
  ],
  toilettage: [
    { key: 'bain',               label: 'Bain',               icon: '🛁', duree: 45 },
    { key: 'toilettage_complet', label: 'Toilettage complet', icon: '✂️', duree: 90 },
    { key: 'coupe',              label: 'Coupe',              icon: '✂️', duree: 60 },
    { key: 'autre',              label: 'Autre',              icon: '➕', duree: 60 },
  ],
};
const DEFAULT_MOTIFS = [
  { key: 'rdv',   label: 'Rendez-vous', icon: '📅', duree: 30 },
  { key: 'autre', label: 'Autre',       icon: '➕', duree: 30 },
];

function fmtTime(t: string) { return t.substring(0, 5); }
function fmtDate(str: string) {
  const d = new Date(str + 'T00:00:00');
  return d.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
}
function toDateStr(d: Date) {
  return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;
}

// ─── Page ──────────────────────────────────────────────────────────────────────

function ProDetailContent() {
  const { uid } = useParams<{ uid: string }>();
  const searchParams = useSearchParams();
  const profileTableId = searchParams.get('profileId') ?? undefined;
  const router = useRouter();
  const { user } = useAuth();

  const [pro, setPro] = useState<ProData | null>(null);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<'presentation' | 'horaires'>('presentation');

  // RDV
  const [showRdv, setShowRdv] = useState(false);
  const [slots, setSlots] = useState<Slot[]>([]);
  const [slotsLoading, setSlotsLoading] = useState(false);
  const [selectedDate, setSelectedDate] = useState('');
  const [selectedSlot, setSelectedSlot] = useState<Slot | null>(null);
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [selectedAnimalId, setSelectedAnimalId] = useState<number | null>(null);
  const [motifKey, setMotifKey] = useState('');
  const [premiereVisite, setPremiereVisite] = useState<boolean | null>(null);
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);
  const [rdvSuccess, setRdvSuccess] = useState(false);

  useEffect(() => { loadPro(); }, [uid]);

  async function loadPro() {
    setLoading(true);
    try {
      let row: Record<string, unknown> | null = null;
      if (profileTableId) {
        const { data } = await supabase.from('user_profiles').select('*').eq('id', profileTableId).maybeSingle();
        if (data) row = {
          uid: data.uid, name: data.name_elevage || '',
          profession: data.profession_pro || '',
          description: data.desc_entreprise || data.description || '',
          ville: data.ville || '', adresse: data.adresse || '', code_postal: data.code_postal || '',
          photo: data.avatar_url || '', banner: data.banner_url || '',
          accept_new_clients: data.accept_new_clients ?? true,
          especes: Array.isArray(data.especes_acceptees) ? data.especes_acceptees : [],
          horaires: (data.horaires && typeof data.horaires === 'object') ? data.horaires : {},
          certifications: Array.isArray(data.certifications) ? data.certifications : [],
          tarifs: data.tarifs || '', site_web: data.site_web || '',
          instagram: data.instagram || '', facebook: data.facebook || '',
          rayon: data.rayon_intervention || 0,
          cat_pro: data.profile_type || data.cat_pro || '',
        };
      } else {
        const { data } = await supabase.from('users').select('*').eq('uid', uid).maybeSingle();
        if (data) row = {
          uid: data.uid, name: data.name_elevage || data.firstname || '',
          profession: data.profession_pro || '',
          description: data.desc_entreprise || '',
          ville: data.ville_elevage || data.ville || '',
          adresse: data.adresse || '',
          code_postal: data.code_postal || '',
          photo: data.profile_picture_url_elevage || data.profile_picture_url || '',
          banner: data.banner_url || '',
          accept_new_clients: data.accept_new_clients ?? true,
          especes: Array.isArray(data.especes_acceptees) ? data.especes_acceptees : [],
          horaires: (data.horaires && typeof data.horaires === 'object') ? data.horaires : {},
          certifications: Array.isArray(data.certifications) ? data.certifications : [],
          tarifs: data.tarifs || '', site_web: data.site_web || '',
          instagram: data.instagram || '', facebook: data.facebook || '',
          rayon: data.rayon_intervention || 0, cat_pro: data.cat_pro || '',
          statut_pro: data.statut_pro || '', siret: data.siret || '', is_premium: data.is_premium ?? false,
        };
      }
      if (row) setPro({ ...(row as unknown as ProData), profileTableId });
    } finally {
      setLoading(false);
    }
  }

  async function openRdv() {
    if (!user) { router.push('/connexion'); return; }
    setShowRdv(true);
    setRdvSuccess(false);
    setMotifKey('');
    setPremiereVisite(null);
    setSelectedDate('');
    setSelectedSlot(null);
    setSelectedAnimalId(null);
    setNotes('');
    setSlotsLoading(true);
    const profileId = profileTableId ?? '';
    const [slotsRes, animauxRes] = await Promise.all([
      supabase.from('creneaux_pro').select('date, heure_debut, heure_fin')
        .eq('pro_uid', uid)
        .eq('statut', 'disponible')
        .eq('pro_profile_id', profileId)
        .gte('date', toDateStr(new Date()))
        .order('date').order('heure_debut'),
      supabase.from('animaux').select('id, nom, espece')
        .or(`uid_eleveur.eq.${user.uid},uid_proprietaire.eq.${user.uid}`)
        .order('nom'),
    ]);
    const rawSlots = (slotsRes.data ?? []) as { date: string; heure_debut: string; heure_fin: string }[];
    setSlots(rawSlots.map(s => ({ date: s.date, heureDebut: s.heure_debut, heureFin: s.heure_fin })));
    setAnimaux((animauxRes.data ?? []) as Animal[]);
    setSlotsLoading(false);
  }

  async function confirmRdv() {
    if (!selectedSlot || !motifKey || !user || !pro) return;
    if (pro.cat_pro === 'veterinaire' && premiereVisite === null) return;
    setSaving(true);
    try {
      const dateDebut = new Date(`${selectedSlot.date}T${selectedSlot.heureDebut}`);
      const dateFin   = new Date(`${selectedSlot.date}T${selectedSlot.heureFin}`);
      const motifInfo = (MOTIFS_BY_CAT[pro.cat_pro] ?? DEFAULT_MOTIFS).find(m => m.key === motifKey);
      const motifLabel = motifInfo?.label ?? motifKey;
      await supabase.from('rdv').insert({
        pro_uid: pro.uid, client_uid: user.uid,
        animal_id: selectedAnimalId || null,
        date_debut: dateDebut.toISOString(), date_fin: dateFin.toISOString(),
        statut: 'en_attente',
        motif: premiereVisite !== null ? `${motifLabel}${premiereVisite ? ' (1ère visite)' : ''}` : motifLabel,
        notes: notes || null,
        pro_profile_id: pro.profileTableId || null,
      });
      await supabase.from('creneaux_pro').update({ statut: 'reserve' })
        .eq('pro_uid', pro.uid)
        .eq('date', selectedSlot.date)
        .eq('heure_debut', selectedSlot.heureDebut);
      await supabase.from('notifications').insert({
        uid: pro.uid, type: 'rdv_demande',
        title: 'Nouvelle demande de RDV',
        body: `Demande pour le ${fmtDate(selectedSlot.date)} à ${fmtTime(selectedSlot.heureDebut)} — ${motifLabel}.`,
        data: { pro_uid: pro.uid },
      });
      setRdvSuccess(true);
    } catch {
      alert('Erreur lors de la réservation. Veuillez réessayer.');
    } finally {
      setSaving(false);
    }
  }

  const slotsByDate = slots.reduce<Record<string, Slot[]>>((acc, s) => {
    if (!acc[s.date]) acc[s.date] = [];
    acc[s.date].push(s);
    return acc;
  }, {});
  const availableDates = Object.keys(slotsByDate).sort();

  const motifs = MOTIFS_BY_CAT[pro?.cat_pro ?? ''] ?? DEFAULT_MOTIFS;
  const isVet  = pro?.cat_pro === 'veterinaire' || pro?.cat_pro === 'sante';
  const catColor = CAT_COLORS[pro?.cat_pro ?? ''] ?? '#0C5C6C';

  const canConfirm = !!motifKey && !!selectedSlot &&
    (pro?.cat_pro !== 'veterinaire' || premiereVisite !== null);

  if (loading) return (
    <div className="min-h-screen bg-[#F8F8F8] flex items-center justify-center">
      <div className="w-8 h-8 border-4 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  );
  if (!pro) return (
    <div className="min-h-screen bg-[#F8F8F8] flex flex-col items-center justify-center gap-3">
      <span className="text-5xl">🔍</span>
      <p className="text-gray-500" style={{ fontFamily: 'Galey, sans-serif' }}>Profil introuvable</p>
      <Link href="/services/carte" className="text-[#0C5C6C] text-sm underline">← Retour aux services</Link>
    </div>
  );

  const fullAddress = [pro.adresse, pro.code_postal, pro.ville].filter(Boolean).join(' ');

  return (
    <div className="min-h-screen bg-[#F8F8F8]">

      {/* ── Bannière + avatar ── */}
      <div className="relative">
        <div className="h-48 w-full overflow-hidden" style={{
          background: `linear-gradient(135deg, ${catColor}cc, #1E2025)`,
        }}>
          {(pro.banner || pro.photo) && (
            <img src={pro.banner || pro.photo} alt="" className="w-full h-full object-cover"
              style={{ filter: 'brightness(0.65)' }} />
          )}
        </div>
        <Link href="/services/carte"
          className="absolute top-4 left-4 w-9 h-9 rounded-full bg-black/30 flex items-center justify-center text-white text-lg hover:bg-black/50 transition-colors">
          ←
        </Link>
        <div className="absolute left-4" style={{ bottom: '-40px' }}>
          <div className="w-20 h-20 rounded-full border-white bg-white shadow-lg overflow-hidden flex items-center justify-center"
            style={{ borderWidth: 3, borderStyle: 'solid' }}>
            {pro.photo
              ? <img src={pro.photo} alt={pro.name} className="w-full h-full object-cover" />
              : <span className="text-3xl">💼</span>
            }
          </div>
        </div>
        <div className="absolute right-4" style={{ bottom: '-16px' }}>
          <span className={`text-xs font-bold px-3 py-1.5 rounded-full ${
            pro.accept_new_clients ? 'bg-green-100 text-green-700' : 'bg-orange-100 text-orange-700'
          }`} style={{ fontFamily: 'Galey, sans-serif' }}>
            {pro.accept_new_clients ? '✓ Disponible' : 'Complet'}
          </span>
        </div>
      </div>

      {/* ── Info + CTA ── */}
      <div className="bg-white pt-14 pb-5 px-4 border-b border-gray-100">
        <div className="flex items-center gap-2">
          <h1 className="text-xl font-bold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>
            {pro.name || 'Professionnel'}
          </h1>
          <VerificationBadge level={getBadgeLevel({ statutPro: pro.statut_pro, siret: pro.siret, isPremium: pro.is_premium })} size="md" />
        </div>
        {pro.profession && (
          <p className="text-sm font-semibold mt-0.5" style={{ color: catColor, fontFamily: 'Galey, sans-serif' }}>
            {pro.profession}
          </p>
        )}

        {/* Adresse */}
        {(fullAddress || pro.rayon > 0) && (
          <p className="text-sm text-gray-500 mt-1.5 flex items-center gap-1" style={{ fontFamily: 'Galey, sans-serif' }}>
            <span>📍</span>
            <span>{fullAddress || pro.ville}{pro.rayon > 0 ? ` · Rayon ${pro.rayon} km` : ''}</span>
          </p>
        )}

        {/* Espèces */}
        {pro.especes.length > 0 && (
          <div className="flex flex-wrap gap-1.5 mt-3">
            {pro.especes.map(e => (
              <span key={e} className="text-xs font-semibold px-2.5 py-1 rounded-full"
                style={{ backgroundColor: `${catColor}18`, color: catColor, fontFamily: 'Galey, sans-serif' }}>
                {e}
              </span>
            ))}
          </div>
        )}

        {/* Réseaux sociaux */}
        {(pro.site_web || pro.instagram || pro.facebook) && (
          <div className="flex gap-2 mt-3 flex-wrap">
            {pro.site_web && (
              <a href={pro.site_web.startsWith('http') ? pro.site_web : `https://${pro.site_web}`}
                target="_blank" rel="noopener noreferrer"
                className="text-xs border border-gray-200 rounded-full px-3 py-1 text-gray-600 hover:bg-gray-50"
                style={{ fontFamily: 'Galey, sans-serif' }}>
                🌐 Site web
              </a>
            )}
            {pro.instagram && (
              <a href={`https://instagram.com/${pro.instagram.replace('@', '')}`}
                target="_blank" rel="noopener noreferrer"
                className="text-xs border border-gray-200 rounded-full px-3 py-1 text-gray-600 hover:bg-gray-50"
                style={{ fontFamily: 'Galey, sans-serif' }}>
                📸 Instagram
              </a>
            )}
            {pro.facebook && (
              <a href={pro.facebook.startsWith('http') ? pro.facebook : `https://${pro.facebook}`}
                target="_blank" rel="noopener noreferrer"
                className="text-xs border border-gray-200 rounded-full px-3 py-1 text-gray-600 hover:bg-gray-50"
                style={{ fontFamily: 'Galey, sans-serif' }}>
                👤 Facebook
              </a>
            )}
          </div>
        )}

        {/* Boutons CTA — dans le profil, pas en bas */}
        <div className="flex gap-3 mt-4">
          <Link href={`/messages?uid=${pro.uid}`}
            className="flex-1 flex items-center justify-center gap-2 border border-gray-200 rounded-2xl py-3 text-sm font-semibold text-[#1E2025] hover:bg-gray-50 transition-colors"
            style={{ fontFamily: 'Galey, sans-serif' }}>
            💬 Contacter
          </Link>
          <button
            onClick={openRdv}
            disabled={!pro.accept_new_clients}
            className="flex-1 flex items-center justify-center gap-2 rounded-2xl py-3 text-sm font-semibold text-white transition-colors disabled:opacity-50"
            style={{ backgroundColor: catColor, fontFamily: 'Galey, sans-serif' }}>
            📅 {pro.accept_new_clients ? 'Prendre RDV' : 'Complet'}
          </button>
        </div>
      </div>

      {/* ── Onglets ── */}
      <div className="bg-white border-b border-gray-100 px-4">
        <div className="flex max-w-2xl mx-auto">
          {(['presentation', 'horaires'] as const).map(t => (
            <button key={t} onClick={() => setTab(t)}
              className={`flex-1 py-3 text-sm font-semibold border-b-2 transition-colors ${
                tab === t ? 'border-[#0C5C6C] text-[#0C5C6C]' : 'border-transparent text-gray-400'
              }`}
              style={{ fontFamily: 'Galey, sans-serif' }}>
              {t === 'presentation' ? 'Présentation' : 'Horaires'}
            </button>
          ))}
        </div>
      </div>

      {/* ── Contenu onglets ── */}
      <div className="max-w-2xl mx-auto px-4 py-4 space-y-4 pb-10">
        {tab === 'presentation' && (
          <>
            <div className="bg-white rounded-2xl p-4 shadow-sm">
              <p className="font-bold text-[#1E2025] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>À propos</p>
              <p className="text-sm text-gray-600 leading-relaxed" style={{ fontFamily: 'Galey, sans-serif' }}>
                {pro.description || 'Aucune description disponible.'}
              </p>
            </div>
            {pro.tarifs && (
              <div className="bg-white rounded-2xl p-4 shadow-sm">
                <p className="font-bold text-[#1E2025] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Tarifs</p>
                <p className="text-sm text-gray-600 leading-relaxed" style={{ fontFamily: 'Galey, sans-serif' }}>{pro.tarifs}</p>
              </div>
            )}
            {pro.certifications.length > 0 && (
              <div className="bg-white rounded-2xl p-4 shadow-sm">
                <p className="font-bold text-[#1E2025] mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>Certifications</p>
                <div className="space-y-2">
                  {pro.certifications.map((c, i) => (
                    <div key={i} className="flex items-start gap-2">
                      <span style={{ color: catColor }}>✓</span>
                      <div>
                        <p className="text-sm font-semibold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>{c.nom}</p>
                        {c.numero && <p className="text-xs text-gray-400">N° {c.numero}</p>}
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </>
        )}
        {tab === 'horaires' && (
          <div className="bg-white rounded-2xl p-4 shadow-sm">
            <p className="font-bold text-[#1E2025] mb-4" style={{ fontFamily: 'Galey, sans-serif' }}>Horaires d&apos;ouverture</p>
            {Object.keys(pro.horaires).length === 0 ? (
              <p className="text-sm text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>Non renseignés</p>
            ) : (
              <div className="space-y-2">
                {JOURS.map(j => (
                  <div key={j} className="flex items-center">
                    <span className="w-24 text-sm font-semibold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>{j}</span>
                    <span className="text-sm" style={{ fontFamily: 'Galey, sans-serif', color: pro.horaires[j] ? '#444' : '#9CA3AF' }}>
                      {pro.horaires[j] || 'Fermé'}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>

      {/* ── Modal RDV ── */}
      {showRdv && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center"
          onClick={e => { if (e.target === e.currentTarget) setShowRdv(false); }}>
          <div className="bg-white w-full max-w-lg rounded-t-3xl sm:rounded-3xl max-h-[92vh] overflow-y-auto">

            <div className="flex justify-center pt-3 pb-1 sm:hidden">
              <div className="w-10 h-1 bg-gray-200 rounded-full" />
            </div>

            <div className="px-5 pt-4 pb-8">
              <div className="flex items-center justify-between mb-5">
                <h2 className="text-lg font-bold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>
                  Prendre RDV — {pro.name}
                </h2>
                <button onClick={() => setShowRdv(false)} className="text-gray-400 hover:text-gray-600 text-xl w-8 h-8 flex items-center justify-center">✕</button>
              </div>

              {rdvSuccess ? (
                <div className="flex flex-col items-center gap-4 py-8 text-center">
                  <div className="w-16 h-16 rounded-full bg-green-100 flex items-center justify-center text-3xl">✅</div>
                  <p className="font-bold text-[#1E2025] text-lg" style={{ fontFamily: 'Galey, sans-serif' }}>Demande envoyée !</p>
                  <p className="text-sm text-gray-500" style={{ fontFamily: 'Galey, sans-serif' }}>
                    {pro.name} recevra votre demande et vous confirmera le rendez-vous.
                  </p>
                  <button onClick={() => setShowRdv(false)}
                    className="mt-2 px-6 py-2.5 rounded-2xl text-white font-semibold text-sm"
                    style={{ backgroundColor: catColor, fontFamily: 'Galey, sans-serif' }}>
                    Fermer
                  </button>
                </div>
              ) : slotsLoading ? (
                <div className="flex justify-center py-12">
                  <div className="w-8 h-8 border-4 border-t-transparent rounded-full animate-spin"
                    style={{ borderColor: `${catColor} transparent transparent transparent` }} />
                </div>
              ) : (
                <div className="space-y-6">

                  {/* Motif */}
                  <div>
                    <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-2.5"
                      style={{ fontFamily: 'Galey, sans-serif' }}>Motif *</p>
                    <div className="grid grid-cols-2 gap-2">
                      {motifs.map(m => (
                        <button key={m.key} onClick={() => setMotifKey(m.key)}
                          className="flex items-center gap-2 px-3 py-2.5 rounded-xl border text-sm font-semibold transition-all text-left"
                          style={{
                            fontFamily: 'Galey, sans-serif',
                            borderColor: motifKey === m.key ? catColor : '#E5E7EB',
                            backgroundColor: motifKey === m.key ? `${catColor}15` : 'white',
                            color: motifKey === m.key ? catColor : '#6B7280',
                          }}>
                          <span className="flex-shrink-0">{m.icon}</span>
                          <span>{m.label}</span>
                        </button>
                      ))}
                    </div>
                  </div>

                  {/* Première visite (vétérinaire seulement) */}
                  {isVet && motifKey && (
                    <div>
                      <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-2.5"
                        style={{ fontFamily: 'Galey, sans-serif' }}>Première visite ? *</p>
                      <div className="flex gap-3">
                        {[{ val: true, label: 'Oui, première visite' }, { val: false, label: 'Non, déjà client(e)' }].map(opt => (
                          <button key={String(opt.val)} onClick={() => setPremiereVisite(opt.val)}
                            className="flex-1 py-2.5 rounded-xl border text-sm font-semibold transition-all"
                            style={{
                              fontFamily: 'Galey, sans-serif',
                              borderColor: premiereVisite === opt.val ? catColor : '#E5E7EB',
                              backgroundColor: premiereVisite === opt.val ? `${catColor}15` : 'white',
                              color: premiereVisite === opt.val ? catColor : '#6B7280',
                            }}>
                            {opt.label}
                          </button>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Sélection animal — toujours visible */}
                  <div>
                    <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-2.5"
                      style={{ fontFamily: 'Galey, sans-serif' }}>Pour quel animal ?</p>
                    {animaux.length === 0 ? (
                      <div className="flex items-center gap-2 bg-gray-50 rounded-xl px-4 py-3">
                        <span className="text-gray-400 text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
                          Aucun animal enregistré —{' '}
                        </span>
                        <Link href="/mes-animaux" className="text-sm font-semibold underline"
                          style={{ color: catColor, fontFamily: 'Galey, sans-serif' }}>
                          Ajouter un animal
                        </Link>
                      </div>
                    ) : (
                      <div className="flex flex-wrap gap-2">
                        {animaux.map(a => (
                          <button key={a.id} onClick={() => setSelectedAnimalId(selectedAnimalId === a.id ? null : a.id)}
                            className="flex items-center gap-1.5 px-3 py-2 rounded-xl border text-sm font-semibold transition-all"
                            style={{
                              fontFamily: 'Galey, sans-serif',
                              borderColor: selectedAnimalId === a.id ? catColor : '#E5E7EB',
                              backgroundColor: selectedAnimalId === a.id ? `${catColor}15` : 'white',
                              color: selectedAnimalId === a.id ? catColor : '#6B7280',
                            }}>
                            <span>{a.espece === 'chien' ? '🐶' : a.espece === 'chat' ? '🐱' : a.espece === 'cheval' ? '🐴' : '🐾'}</span>
                            {a.nom}
                          </button>
                        ))}
                      </div>
                    )}
                  </div>

                  {/* Date */}
                  {availableDates.length === 0 ? (
                    <div className="text-center py-6 bg-gray-50 rounded-2xl">
                      <span className="text-2xl block mb-2">📅</span>
                      <p className="text-sm text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
                        Aucun créneau disponible pour le moment
                      </p>
                    </div>
                  ) : (
                    <>
                      <div>
                        <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-2.5"
                          style={{ fontFamily: 'Galey, sans-serif' }}>Date *</p>
                        <div className="flex gap-2 overflow-x-auto pb-1 -mx-1 px-1">
                          {availableDates.slice(0, 14).map(d => {
                            const dt = new Date(d + 'T00:00:00');
                            return (
                              <button key={d} onClick={() => { setSelectedDate(d); setSelectedSlot(null); }}
                                className="flex-shrink-0 flex flex-col items-center px-3 py-2.5 rounded-xl border text-xs font-semibold transition-all min-w-[52px]"
                                style={{
                                  fontFamily: 'Galey, sans-serif',
                                  borderColor: selectedDate === d ? catColor : '#E5E7EB',
                                  backgroundColor: selectedDate === d ? `${catColor}15` : 'white',
                                  color: selectedDate === d ? catColor : '#6B7280',
                                }}>
                                <span className="text-[10px] uppercase">{dt.toLocaleDateString('fr-FR', { weekday: 'short' })}</span>
                                <span className="text-base font-bold leading-tight">{dt.getDate()}</span>
                                <span className="text-[10px]">{dt.toLocaleDateString('fr-FR', { month: 'short' })}</span>
                              </button>
                            );
                          })}
                        </div>
                      </div>

                      {selectedDate && (
                        <div>
                          <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-2.5"
                            style={{ fontFamily: 'Galey, sans-serif' }}>Heure *</p>
                          <div className="flex flex-wrap gap-2">
                            {(slotsByDate[selectedDate] ?? [])
                              .sort((a, b) => a.heureDebut.localeCompare(b.heureDebut))
                              .map(s => (
                                <button
                                  key={`${s.date}_${s.heureDebut}`}
                                  onClick={() => setSelectedSlot(s)}
                                  className="px-4 py-2 rounded-xl border text-sm font-semibold transition-all"
                                  style={{
                                    fontFamily: 'Galey, sans-serif',
                                    borderColor: selectedSlot?.heureDebut === s.heureDebut ? catColor : '#E5E7EB',
                                    backgroundColor: selectedSlot?.heureDebut === s.heureDebut ? `${catColor}15` : 'white',
                                    color: selectedSlot?.heureDebut === s.heureDebut ? catColor : '#6B7280',
                                  }}>
                                  {fmtTime(s.heureDebut)}
                                </button>
                              ))}
                          </div>
                        </div>
                      )}
                    </>
                  )}

                  {/* Notes */}
                  <div>
                    <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-2"
                      style={{ fontFamily: 'Galey, sans-serif' }}>Notes (optionnel)</p>
                    <textarea
                      value={notes} onChange={e => setNotes(e.target.value)} rows={2}
                      placeholder="Informations complémentaires, symptômes, demandes spécifiques…"
                      className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 resize-none"
                      style={{ fontFamily: 'Galey, sans-serif', focusRingColor: catColor } as React.CSSProperties}
                    />
                  </div>

                  {/* Récap + Confirmer */}
                  {selectedSlot && motifKey && (
                    <div className="bg-gray-50 rounded-2xl px-4 py-3 text-sm space-y-1">
                      <p className="font-bold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>Récapitulatif</p>
                      <p className="text-gray-600" style={{ fontFamily: 'Galey, sans-serif' }}>
                        📅 {fmtDate(selectedSlot.date)} à {fmtTime(selectedSlot.heureDebut)}
                      </p>
                      <p className="text-gray-600" style={{ fontFamily: 'Galey, sans-serif' }}>
                        📋 {motifs.find(m => m.key === motifKey)?.label}
                        {premiereVisite === true ? ' — 1ère visite' : ''}
                      </p>
                      {selectedAnimalId && (
                        <p className="text-gray-600" style={{ fontFamily: 'Galey, sans-serif' }}>
                          🐾 {animaux.find(a => a.id === selectedAnimalId)?.nom}
                        </p>
                      )}
                    </div>
                  )}

                  <button
                    onClick={confirmRdv}
                    disabled={saving || !canConfirm}
                    className="w-full py-4 rounded-2xl text-white font-bold text-sm disabled:opacity-40 transition-opacity"
                    style={{ backgroundColor: catColor, fontFamily: 'Galey, sans-serif' }}>
                    {saving ? '…' : 'Confirmer la demande de RDV'}
                  </button>

                </div>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default function ProDetailPage() {
  return (
    <Suspense>
      <ProDetailContent />
    </Suspense>
  );
}
