'use client';

import { useEffect, useState, use } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

// ── Types ──────────────────────────────────────────────────────────────────────

interface Lieu {
  id: string;
  uid_pro?: string | null;
  nom: string;
  categorie: string;
  ville?: string | null;
  adresse?: string | null;
  description?: string | null;
  lat?: number | null;
  lng?: number | null;
  banniere_url?: string | null;
  photos?: string[] | null;
  especes_acceptees?: string[] | null;
  horaires?: Record<string, string> | null;
  note_moyenne?: number | null;
  nb_avis?: number | null;
  telephone?: string | null;
  site_web?: string | null;
  animaux_dans_chambre?: boolean | null;
  frais_animal_nuit?: number | null;
  nb_animaux_max?: number | null;
  espace_detente?: boolean | null;
  equipements_fournis?: string[] | null;
}

interface Avis {
  id: string;
  note: number;
  note_accueil: number;
  commentaire: string;
  reponse_pro?: string | null;
  created_at: string;
}

// ── Constantes ─────────────────────────────────────────────────────────────────

const DAYS = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const DAY_LABEL: Record<string, string> = {
  lundi: 'Lundi', mardi: 'Mardi', mercredi: 'Mercredi', jeudi: 'Jeudi',
  vendredi: 'Vendredi', samedi: 'Samedi', dimanche: 'Dimanche',
};
const ESPECE_LABEL: Record<string, string> = {
  chien: 'Chien', chat: 'Chat', cheval: 'Cheval', lapin: 'Lapin', oiseau: 'Oiseau', nac: 'NAC',
};

function parseMins(s: string): number {
  const [h, m] = s.trim().split(':');
  return parseInt(h, 10) * 60 + parseInt(m, 10);
}

function ouvertLabel(horaires?: Record<string, string> | null): string {
  if (!horaires || Object.keys(horaires).length === 0) return '';
  const now = new Date();
  const dayKey = DAYS[(now.getDay() + 6) % 7];
  const val = horaires[dayKey];
  if (!val || val.toLowerCase().startsWith('ferm')) return '🔴 Fermé';
  const parts = val.split('-');
  if (parts.length < 2) return '';
  try {
    const t = now.getHours() * 60 + now.getMinutes();
    const open = parseMins(parts[0]);
    const close = parseMins(parts[1]);
    if (t >= open && t < close) return '🟢 Ouvert · Ferme à ' + parts[1].trim();
    if (t < open) return '🔴 Fermé · Ouvre à ' + parts[0].trim();
    return '🔴 Fermé';
  } catch {
    return '';
  }
}

// ── Page ───────────────────────────────────────────────────────────────────────

export default function LieuDetailPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = use(params);
  const { user } = useAuth();

  const [lieu, setLieu] = useState<Lieu | null>(null);
  const [avis, setAvis] = useState<Avis[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingAvis, setLoadingAvis] = useState(true);

  const [note, setNote] = useState(0);
  const [noteAccueil, setNoteAccueil] = useState(0);
  const [commentaire, setCommentaire] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  async function loadLieu() {
    setLoading(true);
    try {
      const { data } = await supabase.from('petfriendly_places').select().eq('id', id).single();
      setLieu(data as Lieu);
    } finally {
      setLoading(false);
    }
  }

  async function loadAvis() {
    setLoadingAvis(true);
    try {
      const { data } = await supabase
        .from('petfriendly_reviews')
        .select('id, note, note_accueil, commentaire, reponse_pro, created_at')
        .eq('place_id', id)
        .eq('statut', 'actif')
        .order('created_at', { ascending: false })
        .limit(20);
      setAvis((data ?? []) as Avis[]);
    } finally {
      setLoadingAvis(false);
    }
  }

  useEffect(() => { loadLieu(); loadAvis(); }, [id]);

  async function submitAvis() {
    if (!user || note === 0 || noteAccueil === 0 || commentaire.trim().length < 20) {
      setError('Note globale + accueil obligatoires, commentaire de 20 caractères minimum.');
      return;
    }
    setSaving(true);
    setError('');
    try {
      const { data: profileRow } = await supabase
        .from('user_profiles').select('id').eq('uid', user.uid).eq('is_main', true).maybeSingle();
      const { error: err } = await supabase.from('petfriendly_reviews').insert({
        place_id: id,
        user_uid: user.uid,
        user_profile_id: profileRow?.id ?? null,
        note,
        note_accueil: noteAccueil,
        commentaire: commentaire.trim(),
      });
      if (err) throw err;
      setNote(0); setNoteAccueil(0); setCommentaire('');
      await loadAvis();
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : 'Erreur inattendue';
      setError(msg.includes('unique') ? 'Vous avez déjà laissé un avis pour ce lieu.' : msg);
    } finally {
      setSaving(false);
    }
  }

  if (loading) {
    return (
      <div className="min-h-screen flex justify-center items-center bg-[#F8F8F8]">
        <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
      </div>
    );
  }

  if (!lieu) {
    return (
      <div className="min-h-screen flex flex-col items-center justify-center gap-3 bg-[#F8F8F8]">
        <p className="font-bold text-gray-700" style={{ fontFamily: 'Galey, sans-serif' }}>Lieu introuvable</p>
        <Link href="/animal-friendly" className="text-[#0C5C6C] text-sm underline">Retour aux lieux pet-friendly</Link>
      </div>
    );
  }

  const isHeb = lieu.categorie === 'hebergement';
  const ouvert = ouvertLabel(lieu.horaires);
  const especes = lieu.especes_acceptees ?? [];
  const photos = lieu.photos ?? [];
  const mapsUrl = lieu.lat != null && lieu.lng != null
    ? `https://www.google.com/maps/dir/?api=1&destination=${lieu.lat},${lieu.lng}`
    : null;

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Bannière */}
      <div className="relative h-56" style={{ backgroundColor: isHeb ? '#1E88E5' : '#EF6C00' }}>
        {lieu.banniere_url && (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={lieu.banniere_url} alt={lieu.nom} className="absolute inset-0 w-full h-full object-cover" />
        )}
        <div className="absolute inset-0" style={{ background: 'linear-gradient(to bottom, rgba(0,0,0,0.1), rgba(0,0,0,0.6))' }} />
        <Link
          href="/animal-friendly"
          className="absolute top-4 left-4 w-9 h-9 rounded-full bg-black/30 text-white flex items-center justify-center hover:bg-black/45 transition-colors"
        >
          ←
        </Link>
      </div>

      <div className="max-w-2xl mx-auto px-4 py-5">
        <h1 className="font-extrabold text-2xl text-[#1E2025] mb-1.5" style={{ fontFamily: 'Galey, sans-serif' }}>
          {lieu.nom}
        </h1>
        {ouvert && <p className="text-sm mb-1.5" style={{ fontFamily: 'Galey, sans-serif' }}>{ouvert}</p>}
        {(lieu.note_moyenne ?? 0) > 0 && (
          <p className="text-sm text-gray-800 mb-4" style={{ fontFamily: 'Galey, sans-serif' }}>
            <span className="text-[#FFA000]">★</span> {(lieu.note_moyenne ?? 0).toFixed(1)} ({lieu.nb_avis ?? 0} avis)
          </p>
        )}

        {/* Adresse / contact */}
        <div className="bg-white rounded-2xl shadow-sm p-4 mb-5 flex flex-col gap-2.5">
          {(lieu.adresse || lieu.ville) && (
            <p className="text-sm flex items-center gap-2" style={{ fontFamily: 'Galey, sans-serif' }}>
              📍 {[lieu.adresse, lieu.ville].filter(Boolean).join(', ')}
            </p>
          )}
          {lieu.telephone && (
            <a href={`tel:${lieu.telephone}`} className="text-sm flex items-center gap-2 text-[#0C5C6C]" style={{ fontFamily: 'Galey, sans-serif' }}>
              📞 {lieu.telephone}
            </a>
          )}
          {lieu.site_web && (
            <a
              href={lieu.site_web.startsWith('http') ? lieu.site_web : `https://${lieu.site_web}`}
              target="_blank" rel="noopener noreferrer"
              className="text-sm flex items-center gap-2 text-[#0C5C6C] underline truncate"
              style={{ fontFamily: 'Galey, sans-serif' }}
            >
              🌐 {lieu.site_web}
            </a>
          )}
          <div className="flex gap-2 pt-1.5">
            {lieu.telephone && (
              <a href={`tel:${lieu.telephone}`}
                className="flex-1 text-center py-2.5 rounded-xl text-sm font-semibold bg-green-600 text-white"
                style={{ fontFamily: 'Galey, sans-serif' }}>
                Appeler
              </a>
            )}
            {mapsUrl && (
              <a href={mapsUrl} target="_blank" rel="noopener noreferrer"
                className="flex-1 text-center py-2.5 rounded-xl text-sm font-semibold bg-[#334155] text-white"
                style={{ fontFamily: 'Galey, sans-serif' }}>
                Itinéraire
              </a>
            )}
          </div>
        </div>

        {/* Espèces acceptées */}
        {especes.length > 0 && (
          <div className="mb-5">
            <h2 className="font-bold text-base text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Animaux acceptés</h2>
            <div className="flex flex-wrap gap-2">
              {especes.map(e => (
                <span key={e} className="text-xs font-medium px-3 py-1.5 rounded-full bg-[#E8F5E9] text-[#2E7D32]" style={{ fontFamily: 'Galey, sans-serif' }}>
                  {ESPECE_LABEL[e.toLowerCase()] ?? e}
                </span>
              ))}
            </div>
          </div>
        )}

        {/* Conditions animaux (hébergement) */}
        {isHeb && (lieu.animaux_dans_chambre != null || lieu.frais_animal_nuit != null || lieu.nb_animaux_max != null || lieu.espace_detente != null || (lieu.equipements_fournis?.length ?? 0) > 0) && (
          <div className="mb-5">
            <h2 className="font-bold text-base text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Conditions animaux</h2>
            <div className="bg-white rounded-xl shadow-sm p-3.5 flex flex-col gap-1.5 text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
              {lieu.animaux_dans_chambre != null && <p>{lieu.animaux_dans_chambre ? '✅' : '❌'} Animaux dans la chambre</p>}
              {lieu.frais_animal_nuit != null && <p>Supplément / nuit : {lieu.frais_animal_nuit}€</p>}
              {lieu.nb_animaux_max != null && <p>Animaux max / séjour : {lieu.nb_animaux_max === 0 ? 'Pas de limite' : lieu.nb_animaux_max}</p>}
              {lieu.espace_detente != null && <p>{lieu.espace_detente ? '✅' : '❌'} Espace détente animaux</p>}
              {(lieu.equipements_fournis?.length ?? 0) > 0 && <p>Équipements fournis : {lieu.equipements_fournis!.join(', ')}</p>}
            </div>
          </div>
        )}

        {/* Description */}
        {lieu.description && (
          <div className="mb-5">
            <h2 className="font-bold text-base text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Description</h2>
            <p className="text-sm text-gray-700 leading-relaxed" style={{ fontFamily: 'Galey, sans-serif' }}>{lieu.description}</p>
          </div>
        )}

        {/* Horaires */}
        {lieu.horaires && Object.keys(lieu.horaires).length > 0 && (
          <div className="mb-5">
            <h2 className="font-bold text-base text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Horaires</h2>
            <div className="bg-white rounded-xl shadow-sm p-3.5">
              {DAYS.map(d => {
                const val = lieu.horaires?.[d];
                const ferme = !val || val.toLowerCase().startsWith('ferm');
                return (
                  <div key={d} className="flex justify-between py-1 text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
                    <span className="text-gray-600 w-24">{DAY_LABEL[d]}</span>
                    <span className={ferme ? 'text-red-500' : 'text-gray-700'}>{ferme ? 'Fermé' : val}</span>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Photos */}
        {photos.length > 0 && (
          <div className="mb-5">
            <h2 className="font-bold text-base text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Photos</h2>
            <div className="flex gap-2 overflow-x-auto pb-1">
              {photos.map((p, i) => (
                // eslint-disable-next-line @next/next/no-img-element
                <img key={i} src={p} alt="" className="w-24 h-32 object-cover rounded-lg flex-shrink-0" />
              ))}
            </div>
          </div>
        )}

        {/* Avis */}
        <h2 className="font-bold text-base text-[#1F2A2E] mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>
          Avis ({lieu.nb_avis ?? 0})
        </h2>

        {user && (
          <div className="bg-white rounded-2xl shadow-sm p-4 mb-4">
            <p className="font-bold text-sm mb-2.5" style={{ fontFamily: 'Galey, sans-serif' }}>Laisser un avis</p>
            <p className="text-xs text-gray-500 mb-1.5" style={{ fontFamily: 'Galey, sans-serif' }}>Note globale</p>
            <div className="flex gap-1 mb-2.5">
              {[1, 2, 3, 4, 5].map(n => (
                <button key={n} onClick={() => setNote(n)} className="text-2xl leading-none">
                  <span style={{ color: n <= note ? '#FFA000' : '#E5E7EB' }}>★</span>
                </button>
              ))}
            </div>
            <p className="text-xs text-gray-500 mb-1.5" style={{ fontFamily: 'Galey, sans-serif' }}>Accueil des animaux</p>
            <div className="flex gap-1 mb-2.5">
              {[1, 2, 3, 4, 5].map(n => (
                <button key={n} onClick={() => setNoteAccueil(n)} className="text-2xl leading-none">
                  <span style={{ color: n <= noteAccueil ? '#FFA000' : '#E5E7EB' }}>★</span>
                </button>
              ))}
            </div>
            <textarea
              value={commentaire}
              onChange={e => setCommentaire(e.target.value)}
              rows={3}
              maxLength={1000}
              placeholder="Votre commentaire (min 20 caractères)…"
              className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm resize-none focus:outline-none focus:border-[#0C5C6C] mb-2.5"
              style={{ fontFamily: 'Galey, sans-serif', backgroundColor: '#F8F9FA' }}
            />
            {error && <p className="text-sm text-red-500 mb-2">{error}</p>}
            <button
              onClick={submitAvis}
              disabled={saving}
              className="w-full bg-[#0C5C6C] text-white font-semibold py-2.5 rounded-lg disabled:opacity-50 transition-opacity"
              style={{ fontFamily: 'Galey, sans-serif' }}
            >
              {saving ? 'Envoi…' : 'Publier l’avis'}
            </button>
          </div>
        )}

        {loadingAvis ? (
          <div className="flex justify-center py-8">
            <div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
          </div>
        ) : avis.length === 0 ? (
          <p className="text-sm text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>Aucun avis pour le moment.</p>
        ) : (
          <div className="flex flex-col gap-2.5">
            {avis.map(a => (
              <div key={a.id} className="bg-white rounded-xl shadow-sm p-3.5">
                <div className="flex items-center gap-3 mb-1.5">
                  <div className="flex gap-0.5">
                    {[1, 2, 3, 4, 5].map(n => (
                      <span key={n} style={{ color: n <= a.note ? '#FFA000' : '#E5E7EB', fontSize: 13 }}>★</span>
                    ))}
                  </div>
                  {a.note_accueil > 0 && (
                    <div className="flex items-center gap-0.5 text-gray-400">
                      🐾
                      {[1, 2, 3, 4, 5].map(n => (
                        <span key={n} style={{ color: n <= a.note_accueil ? '#9CA3AF' : '#E5E7EB', fontSize: 11 }}>★</span>
                      ))}
                    </div>
                  )}
                  <span className="text-[11px] text-gray-400 ml-auto" style={{ fontFamily: 'Galey, sans-serif' }}>
                    {new Date(a.created_at).toLocaleDateString('fr-FR')}
                  </span>
                </div>
                <p className="text-sm text-gray-800" style={{ fontFamily: 'Galey, sans-serif' }}>{a.commentaire}</p>
                {a.reponse_pro && (
                  <div className="mt-2 bg-[#E8F5E9] rounded-lg p-2.5">
                    <p className="text-[11px] font-semibold text-[#0C5C6C] mb-0.5" style={{ fontFamily: 'Galey, sans-serif' }}>Réponse de l&apos;établissement</p>
                    <p className="text-xs text-gray-700" style={{ fontFamily: 'Galey, sans-serif' }}>{a.reponse_pro}</p>
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
