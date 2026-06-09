'use client';

import { useEffect, useState } from 'react';
import { useParams, useSearchParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

// ─── Types ─────────────────────────────────────────────────────────────────────

interface ProData {
  uid: string;
  name: string;
  profession: string;
  description: string;
  ville: string;
  photo: string;
  banner: string;
  accept_new_clients: boolean;
  especes: string[];
  horaires: Record<string, string>;
  certifications: { nom: string; numero?: string }[];
  tarifs: string;
  site_web: string;
  instagram: string;
  facebook: string;
  rayon: number;
  cat_pro: string;
  profileTableId?: string;
}

interface Slot { date: string; heure: number; }
interface Animal { id: number; nom: string; espece: string; }

const JOURS = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
const CAT_COLORS: Record<string, string> = {
  veterinaire: '#2196F3', sante: '#2196F3', education: '#FF9800',
  garde: '#4CAF50', toilettage: '#00BCD4', photographe: '#E91E63',
  marechal_ferrant: '#795548', referencement: '#CDDC39', pension: '#4CAF50',
};
const RDV_MOTIFS: Record<string, { label: string; icon: string }[]> = {
  veterinaire: [
    { label: 'Consultation', icon: '🩺' }, { label: 'Vaccination', icon: '💉' },
    { label: 'Bilan annuel', icon: '📋' }, { label: 'Autre', icon: '➕' },
  ],
  sante: [
    { label: 'Consultation', icon: '🩺' }, { label: 'Bilan', icon: '📋' }, { label: 'Autre', icon: '➕' },
  ],
  garde: [
    { label: 'Visite de la pension', icon: '🏡' }, { label: 'Arrivée de l\'animal', icon: '📥' },
    { label: 'Départ de l\'animal', icon: '📤' }, { label: 'Autre', icon: '➕' },
  ],
  education: [
    { label: 'Cours individuel', icon: '🎓' }, { label: 'Cours collectif', icon: '👥' }, { label: 'Autre', icon: '➕' },
  ],
};

function toDateStr(d: Date) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
function fmtDate(str: string) {
  const d = new Date(str + 'T00:00:00');
  return d.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
}

// ─── Page ──────────────────────────────────────────────────────────────────────

export default function ProDetailPage() {
  const { uid } = useParams<{ uid: string }>();
  const searchParams = useSearchParams();
  const profileTableId = searchParams.get('profileId') ?? undefined;
  const router = useRouter();
  const { user } = useAuth();

  const [pro, setPro] = useState<ProData | null>(null);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<'presentation' | 'horaires'>('presentation');

  // RDV booking modal
  const [showRdv, setShowRdv] = useState(false);
  const [slots, setSlots] = useState<Slot[]>([]);
  const [slotsLoading, setSlotsLoading] = useState(false);
  const [selectedDate, setSelectedDate] = useState('');
  const [selectedHeure, setSelectedHeure] = useState<number | null>(null);
  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [selectedAnimalId, setSelectedAnimalId] = useState<number | null>(null);
  const [motif, setMotif] = useState('');
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
          uid: data.uid, name: data.name_elevage || '', profession: data.profession_pro || '',
          description: data.desc_entreprise || data.description || '',
          ville: data.ville || '', photo: data.avatar_url || '', banner: data.banner_url || '',
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
          photo: data.profile_picture_url_elevage || data.profile_picture_url || '',
          banner: data.banner_url || '',
          accept_new_clients: data.accept_new_clients ?? true,
          especes: Array.isArray(data.especes_acceptees) ? data.especes_acceptees : [],
          horaires: (data.horaires && typeof data.horaires === 'object') ? data.horaires : {},
          certifications: Array.isArray(data.certifications) ? data.certifications : [],
          tarifs: data.tarifs || '', site_web: data.site_web || '',
          instagram: data.instagram || '', facebook: data.facebook || '',
          rayon: data.rayon_intervention || 0, cat_pro: data.cat_pro || '',
        };
      }

      if (row) {
        setPro({ ...(row as unknown as ProData), profileTableId });
      }
    } finally {
      setLoading(false);
    }
  }

  async function openRdv() {
    if (!user) { router.push('/connexion'); return; }
    setShowRdv(true);
    setRdvSuccess(false);
    setSlotsLoading(true);

    const [slotsRes, animauxRes] = await Promise.all([
      supabase.from('creneaux_pro').select('date, heure_debut')
        .eq('pro_uid', uid)
        .eq('statut', 'disponible')
        .gte('date', toDateStr(new Date()))
        .order('date').order('heure_debut'),
      supabase.from('animaux').select('id, nom, espece').eq('uid_user', user.uid),
    ]);

    const rawSlots = (slotsRes.data ?? []) as { date: string; heure_debut: string }[];
    setSlots(rawSlots.map(s => ({ date: s.date, heure: parseInt(s.heure_debut, 10) })));
    setAnimaux((animauxRes.data ?? []) as Animal[]);
    setSlotsLoading(false);
  }

  async function confirmRdv() {
    if (!selectedDate || selectedHeure === null || !user || !pro) return;
    setSaving(true);
    try {
      const dateDebut = new Date(`${selectedDate}T${String(selectedHeure).padStart(2, '0')}:00:00`);
      const dateFin   = new Date(dateDebut.getTime() + 60 * 60 * 1000);
      await supabase.from('rdv').insert({
        pro_uid:        pro.uid,
        client_uid:     user.uid,
        animal_id:      selectedAnimalId || null,
        date_debut:     dateDebut.toISOString(),
        date_fin:       dateFin.toISOString(),
        statut:         'en_attente',
        motif:          motif || null,
        notes:          notes || null,
        pro_profile_id: pro.profileTableId || null,
      });
      await supabase.from('creneaux_pro').update({ statut: 'reserve' })
        .eq('pro_uid', pro.uid).eq('date', selectedDate)
        .eq('heure_debut', `${String(selectedHeure).padStart(2, '0')}:00:00`);
      await supabase.from('notifications').insert({
        uid: pro.uid, type: 'rdv_demande',
        title: 'Nouvelle demande de RDV',
        body: `Demande pour le ${fmtDate(selectedDate)} à ${selectedHeure}h.`,
        data: { pro_uid: pro.uid },
      });
      setRdvSuccess(true);
    } catch (e) {
      alert('Erreur lors de la réservation. Veuillez réessayer.');
    } finally {
      setSaving(false);
    }
  }

  // ── Regrouper créneaux par date ──────────────────────────────────────────────
  const slotsByDate = slots.reduce<Record<string, number[]>>((acc, s) => {
    if (!acc[s.date]) acc[s.date] = [];
    acc[s.date].push(s.heure);
    return acc;
  }, {});
  const availableDates = Object.keys(slotsByDate).sort();

  if (loading) {
    return (
      <div className="min-h-screen bg-[#F8F8F8] flex items-center justify-center">
        <div className="w-8 h-8 border-4 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }
  if (!pro) {
    return (
      <div className="min-h-screen bg-[#F8F8F8] flex flex-col items-center justify-center gap-3">
        <span className="text-5xl">🔍</span>
        <p className="text-gray-500" style={{ fontFamily: 'Galey, sans-serif' }}>Profil introuvable</p>
        <Link href="/services/carte" className="text-[#0C5C6C] text-sm underline">← Retour aux services</Link>
      </div>
    );
  }

  const catColor = CAT_COLORS[pro.cat_pro] ?? '#0C5C6C';
  const motifs = RDV_MOTIFS[pro.cat_pro] ?? [{ label: 'RDV', icon: '📅' }, { label: 'Autre', icon: '➕' }];

  return (
    <div className="min-h-screen bg-[#F8F8F8] pb-28">

      {/* ── Header ── */}
      <div className="relative">
        {/* Bannière */}
        <div className="h-48 w-full bg-gradient-to-br from-[#0C5C6C] to-[#1E2025] overflow-hidden">
          {(pro.banner || pro.photo) && (
            <img
              src={pro.banner || pro.photo}
              alt=""
              className="w-full h-full object-cover"
              style={{ filter: 'brightness(0.7)' }}
            />
          )}
        </div>

        {/* Bouton retour */}
        <Link href="/services/carte"
          className="absolute top-4 left-4 w-9 h-9 rounded-full bg-black/30 flex items-center justify-center text-white hover:bg-black/50 transition-colors">
          ←
        </Link>

        {/* Avatar chevauchant */}
        <div className="absolute left-4"
          style={{ bottom: '-40px' }}>
          <div className="w-20 h-20 rounded-full border-3 border-white shadow-lg overflow-hidden bg-white flex items-center justify-center"
            style={{ borderWidth: 3, borderStyle: 'solid', borderColor: 'white' }}>
            {pro.photo
              ? <img src={pro.photo} alt={pro.name} className="w-full h-full object-cover" />
              : <span className="text-3xl">💼</span>
            }
          </div>
        </div>

        {/* Badge dispo */}
        <div className="absolute right-4"
          style={{ bottom: '-16px' }}>
          <span className={`text-xs font-bold px-3 py-1.5 rounded-full ${
            pro.accept_new_clients ? 'bg-green-100 text-green-700' : 'bg-orange-100 text-orange-700'
          }`} style={{ fontFamily: 'Galey, sans-serif' }}>
            {pro.accept_new_clients ? '✓ Disponible' : 'Complet'}
          </span>
        </div>
      </div>

      {/* ── Info principale ── */}
      <div className="bg-white pt-14 pb-4 px-4 border-b border-gray-100">
        <h1 className="text-xl font-bold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>
          {pro.name || 'Professionnel'}
        </h1>
        {pro.profession && (
          <p className="text-sm font-semibold mt-0.5" style={{ color: catColor, fontFamily: 'Galey, sans-serif' }}>
            {pro.profession}
          </p>
        )}
        {pro.ville && (
          <p className="text-sm text-gray-500 mt-1" style={{ fontFamily: 'Galey, sans-serif' }}>
            📍 {pro.ville}{pro.rayon > 0 ? ` · ${pro.rayon} km` : ''}
          </p>
        )}

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

        {(pro.site_web || pro.instagram || pro.facebook) && (
          <div className="flex gap-2 mt-3 flex-wrap">
            {pro.site_web && (
              <a href={pro.site_web.startsWith('http') ? pro.site_web : `https://${pro.site_web}`}
                target="_blank" rel="noopener noreferrer"
                className="flex items-center gap-1 text-xs border border-gray-200 rounded-full px-3 py-1 text-gray-600 hover:bg-gray-50"
                style={{ fontFamily: 'Galey, sans-serif' }}>
                🌐 Site web
              </a>
            )}
            {pro.instagram && (
              <a href={`https://instagram.com/${pro.instagram.replace('@', '')}`}
                target="_blank" rel="noopener noreferrer"
                className="flex items-center gap-1 text-xs border border-gray-200 rounded-full px-3 py-1 text-gray-600 hover:bg-gray-50"
                style={{ fontFamily: 'Galey, sans-serif' }}>
                📸 Instagram
              </a>
            )}
            {pro.facebook && (
              <a href={pro.facebook.startsWith('http') ? pro.facebook : `https://${pro.facebook}`}
                target="_blank" rel="noopener noreferrer"
                className="flex items-center gap-1 text-xs border border-gray-200 rounded-full px-3 py-1 text-gray-600 hover:bg-gray-50"
                style={{ fontFamily: 'Galey, sans-serif' }}>
                👤 Facebook
              </a>
            )}
          </div>
        )}
      </div>

      {/* ── Onglets ── */}
      <div className="bg-white border-b border-gray-100 px-4">
        <div className="flex">
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

      {/* ── Contenu ── */}
      <div className="max-w-2xl mx-auto px-4 py-4 space-y-4">
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
                      <span className="text-[#0C5C6C] mt-0.5">✓</span>
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
                    <span className="text-sm" style={{
                      fontFamily: 'Galey, sans-serif',
                      color: pro.horaires[j] ? '#444444' : '#9CA3AF',
                    }}>
                      {pro.horaires[j] || 'Fermé'}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}
      </div>

      {/* ── Barre du bas ── */}
      <div className="fixed bottom-0 left-0 right-0 bg-white border-t border-gray-100 px-4 py-3 flex gap-3"
        style={{ paddingBottom: 'calc(12px + env(safe-area-inset-bottom))' }}>
        <Link href={`/messages?uid=${pro.uid}`}
          className="flex-1 flex items-center justify-center gap-2 border border-gray-200 rounded-2xl py-3.5 text-sm font-semibold text-[#1E2025] hover:bg-gray-50 transition-colors"
          style={{ fontFamily: 'Galey, sans-serif' }}>
          💬 Contacter
        </Link>
        <button
          onClick={openRdv}
          disabled={!pro.accept_new_clients}
          className="flex-1 flex items-center justify-center gap-2 rounded-2xl py-3.5 text-sm font-semibold text-white transition-colors disabled:opacity-50"
          style={{ backgroundColor: catColor, fontFamily: 'Galey, sans-serif' }}>
          📅 {pro.accept_new_clients ? 'Prendre RDV' : 'Complet'}
        </button>
      </div>

      {/* ── Modal RDV ── */}
      {showRdv && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end justify-center"
          onClick={e => { if (e.target === e.currentTarget) setShowRdv(false); }}>
          <div className="bg-white w-full max-w-lg rounded-t-3xl max-h-[90vh] overflow-y-auto">

            {/* Handle */}
            <div className="flex justify-center pt-3 pb-2">
              <div className="w-10 h-1 bg-gray-200 rounded-full" />
            </div>

            <div className="px-5 pb-8">
              <div className="flex items-center justify-between mb-5">
                <h2 className="text-lg font-bold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>
                  Prendre RDV
                </h2>
                <button onClick={() => setShowRdv(false)} className="text-gray-400 hover:text-gray-600 text-xl">✕</button>
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
                  <div className="w-8 h-8 border-4 border-t-transparent rounded-full animate-spin" style={{ borderColor: catColor }} />
                </div>
              ) : (
                <div className="space-y-5">

                  {/* Motif */}
                  <div>
                    <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-2"
                      style={{ fontFamily: 'Galey, sans-serif' }}>Motif *</p>
                    <div className="grid grid-cols-2 gap-2">
                      {motifs.map(m => (
                        <button key={m.label} onClick={() => setMotif(m.label)}
                          className="flex items-center gap-2 px-3 py-2.5 rounded-xl border text-sm font-semibold transition-colors text-left"
                          style={{
                            fontFamily: 'Galey, sans-serif',
                            borderColor: motif === m.label ? catColor : '#E5E7EB',
                            backgroundColor: motif === m.label ? `${catColor}15` : 'white',
                            color: motif === m.label ? catColor : '#6B7280',
                          }}>
                          <span>{m.icon}</span> {m.label}
                        </button>
                      ))}
                    </div>
                  </div>

                  {/* Date */}
                  {availableDates.length === 0 ? (
                    <div className="text-center py-6 bg-gray-50 rounded-2xl">
                      <p className="text-sm text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
                        Aucun créneau disponible pour le moment
                      </p>
                    </div>
                  ) : (
                    <>
                      <div>
                        <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-2"
                          style={{ fontFamily: 'Galey, sans-serif' }}>Date *</p>
                        <div className="flex gap-2 overflow-x-auto pb-1">
                          {availableDates.slice(0, 14).map(d => (
                            <button key={d} onClick={() => { setSelectedDate(d); setSelectedHeure(null); }}
                              className="flex-shrink-0 flex flex-col items-center px-3 py-2 rounded-xl border text-xs font-semibold transition-colors"
                              style={{
                                fontFamily: 'Galey, sans-serif',
                                borderColor: selectedDate === d ? catColor : '#E5E7EB',
                                backgroundColor: selectedDate === d ? `${catColor}15` : 'white',
                                color: selectedDate === d ? catColor : '#6B7280',
                              }}>
                              <span>{new Date(d + 'T00:00:00').toLocaleDateString('fr-FR', { weekday: 'short' })}</span>
                              <span className="font-bold">{new Date(d + 'T00:00:00').getDate()}</span>
                              <span>{new Date(d + 'T00:00:00').toLocaleDateString('fr-FR', { month: 'short' })}</span>
                            </button>
                          ))}
                        </div>
                      </div>

                      {selectedDate && (
                        <div>
                          <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-2"
                            style={{ fontFamily: 'Galey, sans-serif' }}>Heure *</p>
                          <div className="flex flex-wrap gap-2">
                            {(slotsByDate[selectedDate] ?? []).sort((a, b) => a - b).map(h => (
                              <button key={h} onClick={() => setSelectedHeure(h)}
                                className="px-4 py-2 rounded-xl border text-sm font-semibold transition-colors"
                                style={{
                                  fontFamily: 'Galey, sans-serif',
                                  borderColor: selectedHeure === h ? catColor : '#E5E7EB',
                                  backgroundColor: selectedHeure === h ? `${catColor}15` : 'white',
                                  color: selectedHeure === h ? catColor : '#6B7280',
                                }}>
                                {String(h).padStart(2, '0')}:00
                              </button>
                            ))}
                          </div>
                        </div>
                      )}
                    </>
                  )}

                  {/* Animal */}
                  {animaux.length > 0 && (
                    <div>
                      <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-2"
                        style={{ fontFamily: 'Galey, sans-serif' }}>Animal (optionnel)</p>
                      <div className="flex gap-2 flex-wrap">
                        {animaux.map(a => (
                          <button key={a.id} onClick={() => setSelectedAnimalId(selectedAnimalId === a.id ? null : a.id)}
                            className="px-3 py-1.5 rounded-xl border text-sm font-semibold transition-colors"
                            style={{
                              fontFamily: 'Galey, sans-serif',
                              borderColor: selectedAnimalId === a.id ? catColor : '#E5E7EB',
                              backgroundColor: selectedAnimalId === a.id ? `${catColor}15` : 'white',
                              color: selectedAnimalId === a.id ? catColor : '#6B7280',
                            }}>
                            {a.nom}
                          </button>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Notes */}
                  <div>
                    <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-2"
                      style={{ fontFamily: 'Galey, sans-serif' }}>Notes (optionnel)</p>
                    <textarea
                      value={notes}
                      onChange={e => setNotes(e.target.value)}
                      rows={2}
                      placeholder="Informations complémentaires…"
                      className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
                      style={{ fontFamily: 'Galey, sans-serif' }}
                    />
                  </div>

                  {/* Confirmer */}
                  <button
                    onClick={confirmRdv}
                    disabled={saving || !motif || !selectedDate || selectedHeure === null}
                    className="w-full py-4 rounded-2xl text-white font-bold text-sm disabled:opacity-50 transition-opacity"
                    style={{ backgroundColor: catColor, fontFamily: 'Galey, sans-serif' }}>
                    {saving ? '…' : 'Confirmer la demande'}
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
