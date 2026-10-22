'use client';

import { useEffect, useState, use } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { ESPECES_LIEUX } from '@/lib/especes-lieux';
import { referencementLieu, LIBELLE_REFERENCEMENT } from '@/lib/lieux-categories';
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
  plan?: string | null;
  verification?: string | null;
  source_conditions?: string | null;
  derniere_confirmation_le?: string | null;
  animaux_en_salle?: boolean | null;
  terrasse?: boolean | null;
  restriction_taille?: boolean | null;
  supplement_animal?: boolean | null;
  conditions_particulieres?: string | null;
  recommandation?: string | null;
}

type TroisEtats = boolean | null;
const etat = (v: TroisEtats | undefined) => (v === true ? 'Oui' : v === false ? 'Non' : 'Non renseigné');
const RAISONS_LIEU: [string, string][] = [
  ['information_incorrecte', 'Information incorrecte'], ['animaux_refuses', 'Les animaux ne sont pas acceptés'],
  ['lieu_ferme', 'Lieu fermé définitivement'], ['photo_non_autorisee', 'Photo utilisée sans autorisation'],
  ['donnees_personnelles', 'Données personnelles exposées'], ['autre', 'Autre'],
];

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
  const { user, activeProfileId } = useAuth();

  const [lieu, setLieu] = useState<Lieu | null>(null);
  const [avis, setAvis] = useState<Avis[]>([]);
  const [loading, setLoading] = useState(true);
  const [loadingAvis, setLoadingAvis] = useState(true);

  const [note, setNote] = useState(0);
  const [noteAccueil, setNoteAccueil] = useState(0);
  const [commentaire, setCommentaire] = useState('');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  // Contributions : correction proposée, signalement (modérés par l'admin).
  const [panneau, setPanneau] = useState<'' | 'correction' | 'signalement'>('');
  const [corr, setCorr] = useState<{ especes: string[]; interieur: TroisEtats; terrasse: TroisEtats; taille: TroisEtats; supplement: TroisEtats; commentaire: string }>(
    { especes: [], interieur: null, terrasse: null, taille: null, supplement: null, commentaire: '' });
  const [raison, setRaison] = useState('');
  const [detailSignal, setDetailSignal] = useState('');
  const [messageContrib, setMessageContrib] = useState('');
  // Revendication gratuite (vérifiée par l'équipe).
  const [maRevendication, setMaRevendication] = useState<{ statut: string; motif?: string | null } | null>(null);
  const [rev, setRev] = useState({ fonction: 'Gérant(e)', siret: '', methode: 'email_pro' as 'email_pro' | 'justificatif', email: '' });
  const [revFichier, setRevFichier] = useState<File | null>(null);
  const [revOuvert, setRevOuvert] = useState(false);
  const [revErreur, setRevErreur] = useState('');

  useEffect(() => {
    if (!user) return;
    supabase.from('petfriendly_revendications').select('statut, motif').eq('place_id', id).eq('uid', user.uid)
      .order('created_at', { ascending: false }).limit(1).maybeSingle()
      .then(({ data }) => setMaRevendication(data as typeof maRevendication));
  }, [user, id]);

  async function envoyerRevendication() {
    if (!user) return;
    const siret = rev.siret.replace(/\s/g, '');
    if (siret.length !== 14) { setRevErreur('SIRET : 14 chiffres.'); return; }
    if (rev.methode === 'email_pro' && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(rev.email.trim())) { setRevErreur('Adresse e-mail invalide.'); return; }
    if (rev.methode === 'justificatif' && !revFichier) { setRevErreur('Ajoutez le justificatif.'); return; }
    setRevErreur('');
    let url: string | null = null;
    if (rev.methode === 'justificatif' && revFichier) {
      // Stockage privé (documents) : seul l'admin l'ouvre, par lien temporaire.
      const ext = revFichier.type === 'application/pdf' ? 'pdf' : 'jpg';
      const chemin = `revendications/${user.uid}/${id}_${Date.now()}.${ext}`;
      const { error: e } = await supabase.storage.from('documents').upload(chemin, revFichier, { contentType: revFichier.type || 'image/jpeg', upsert: true });
      if (e) { setRevErreur(`Envoi du justificatif impossible : ${e.message}`); return; }
      url = supabase.storage.from('documents').getPublicUrl(chemin).data.publicUrl;
    }
    const { error: err } = await supabase.from('petfriendly_revendications').insert({
      place_id: id, uid: user.uid, ...(activeProfileId ? { profile_id: activeProfileId } : {}),
      fonction: rev.fonction, siret, methode: rev.methode,
      ...(rev.methode === 'email_pro' ? { email_pro: rev.email.trim() } : {}), ...(url ? { justificatif_url: url } : {}),
    });
    if (err) { setRevErreur(`Envoi impossible : ${err.message}`); return; }
    setMaRevendication({ statut: 'en_attente' }); setRevOuvert(false);
  }

  function ouvrirCorrection() {
    if (!lieu) return;
    setCorr({ especes: lieu.especes_acceptees ?? [], interieur: lieu.animaux_en_salle ?? null, terrasse: lieu.terrasse ?? null,
      taille: lieu.restriction_taille ?? null, supplement: lieu.supplement_animal ?? null, commentaire: '' });
    setPanneau('correction'); setMessageContrib('');
  }

  async function envoyerCorrection() {
    if (!user || !lieu) return;
    const champs: Record<string, unknown> = {};
    const avant = lieu.especes_acceptees ?? [];
    if (avant.length !== corr.especes.length || avant.some(e => !corr.especes.includes(e))) champs.especes_acceptees = corr.especes;
    if (corr.interieur !== (lieu.animaux_en_salle ?? null)) champs.animaux_en_salle = corr.interieur;
    if (corr.terrasse !== (lieu.terrasse ?? null)) champs.terrasse = corr.terrasse;
    if (corr.taille !== (lieu.restriction_taille ?? null)) champs.restriction_taille = corr.taille;
    if (corr.supplement !== (lieu.supplement_animal ?? null)) champs.supplement_animal = corr.supplement;
    if (!Object.keys(champs).length && !corr.commentaire.trim()) { setMessageContrib('Aucune modification à envoyer.'); return; }
    const { error: err } = await supabase.from('petfriendly_corrections').insert({
      place_id: id, uid: user.uid, ...(activeProfileId ? { profile_id: activeProfileId } : {}),
      champs, ...(corr.commentaire.trim() ? { commentaire: corr.commentaire.trim() } : {}),
    });
    setMessageContrib(err ? `Envoi impossible : ${err.message}` : "Merci : votre correction sera vérifiée par l'équipe.");
    if (!err) setPanneau('');
  }

  async function envoyerSignalement() {
    if (!user || !raison) return;
    const { error: err } = await supabase.from('signalements').insert({
      reporter_uid: user.uid, target_type: 'lieu', target_id: id, raison, ...(detailSignal.trim() ? { description: detailSignal.trim() } : {}),
    });
    setMessageContrib(err ? `Envoi impossible : ${err.message}` : 'Merci, votre signalement a été transmis.');
    if (!err) { setPanneau(''); setRaison(''); setDetailSignal(''); }
  }

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
        .from('user_profiles_complet').select('id').eq('uid', user.uid).eq('is_main', true).maybeSingle();
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
  const ref = referencementLieu(lieu);
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
          <p className="text-sm text-gray-800 mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
            <span className="text-[#FFA000]">★</span> {(lieu.note_moyenne ?? 0).toFixed(1)} ({lieu.nb_avis ?? 0} avis)
          </p>
        )}
        <p className={`text-sm font-bold mb-2 ${ref === 'partenaire' ? 'text-[#4E7A3B]' : ref === 'verifie' ? 'text-[#0C5C6C]' : 'text-gray-700'}`}
          style={{ fontFamily: 'Galey, sans-serif' }}>{LIBELLE_REFERENCEMENT[ref]}</p>
        <div className={`rounded-xl px-3.5 py-3 mb-5 text-[13px] leading-relaxed border ${ref === 'communaute'
          ? 'bg-[#FDF6EC] border-[#F1D9B5] text-[#6B4A12]' : 'bg-[#E8F4F6] border-[#CFE5EA] text-[#0C4A55]'}`} style={{ fontFamily: 'Galey, sans-serif' }}>
          {ref === 'communaute'
            ? "Ce lieu a été ajouté par un membre de PetsMatch. Les conditions d'accueil des animaux n'ont pas été confirmées par l'établissement. Nous vous recommandons de les vérifier avant votre visite."
            : `Informations gérées par l'établissement.${ref === 'verifie' ? " La vérification concerne le gestionnaire de la fiche, pas la qualité de l'établissement." : ''}`}
        </div>

        {/* Adresse / contact */}
        <div className="bg-white rounded-2xl shadow-sm p-4 mb-5 flex flex-col gap-2.5">
          {(lieu.adresse || lieu.ville) && (
            <p className="text-sm flex items-center gap-2" style={{ fontFamily: 'Galey, sans-serif' }}>
              {[lieu.adresse, lieu.ville].filter(Boolean).join(', ')}
            </p>
          )}
          {lieu.telephone && (
            <a href={`tel:${lieu.telephone}`} className="text-sm flex items-center gap-2 text-[#0C5C6C]" style={{ fontFamily: 'Galey, sans-serif' }}>
              {lieu.telephone}
            </a>
          )}
          {lieu.site_web && (
            <a
              href={lieu.site_web.startsWith('http') ? lieu.site_web : `https://${lieu.site_web}`}
              target="_blank" rel="noopener noreferrer"
              className="text-sm flex items-center gap-2 text-[#0C5C6C] underline truncate"
              style={{ fontFamily: 'Galey, sans-serif' }}
            >
              {lieu.site_web}
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

        {/* Conditions d'accueil (tous les lieux) : 3 états, source et date */}
        <div className="mb-5 bg-white rounded-2xl shadow-sm p-4" style={{ fontFamily: 'Galey, sans-serif' }}>
          <h2 className="font-bold text-base text-[#1F2A2E]">Conditions d&apos;accueil des animaux</h2>
          <p className="text-xs text-gray-500 mt-0.5">
            Source : {ref === 'communaute' || lieu.source_conditions === 'communaute' ? 'communauté' : 'établissement'}
            {lieu.derniere_confirmation_le ? ` · ${ref === 'communaute' ? 'dernière visite déclarée' : 'confirmé'} le ${new Date(lieu.derniere_confirmation_le).toLocaleDateString('fr-FR')}` : ''}
          </p>
          <table className="w-full mt-3 text-sm">
            <tbody>
              {([
                ['Espèces accueillies', especes.length ? especes.map(e => ESPECES_LIEUX.find(x => x.value === e.toLowerCase())?.label ?? ESPECE_LABEL[e.toLowerCase()] ?? e).join(', ') : 'Non renseigné'],
                ['Accès intérieur', etat(lieu.animaux_en_salle)],
                ['Terrasse / extérieur', etat(lieu.terrasse)],
                ['Restriction de taille', etat(lieu.restriction_taille)],
                ["Nombre d'animaux", lieu.nb_animaux_max != null ? `${lieu.nb_animaux_max} maximum` : 'Non renseigné'],
                ['Supplément', etat(lieu.supplement_animal)],
                ...(lieu.conditions_particulieres ? [['Conditions particulières', lieu.conditions_particulieres]] : []),
              ] as [string, string][]).map(([k, v]) => (
                <tr key={k} className="border-t border-gray-100">
                  <td className="py-2 pr-3 text-gray-500 align-top w-44">{k}</td>
                  <td className={`py-2 ${v === 'Non renseigné' ? 'text-gray-400' : 'font-semibold text-[#1F2A2E]'}`}>{v}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <p className="text-[11px] text-gray-400 mt-2">« Non renseigné » : l&apos;information n&apos;a pas été donnée, ce n&apos;est pas une confirmation.</p>
        </div>

        {ref === 'communaute' && lieu.recommandation && (
          <div className="mb-5" style={{ fontFamily: 'Galey, sans-serif' }}>
            <h2 className="font-bold text-base text-[#1F2A2E] mb-2">Pourquoi un membre recommande ce lieu</h2>
            <p className="text-sm text-gray-700 italic leading-relaxed">« {lieu.recommandation} »</p>
          </div>
        )}

        {/* Contribuer : corriger, signaler */}
        {user?.uid !== lieu.uid_pro && (
          <div className="mb-5 bg-white rounded-2xl shadow-sm divide-y" style={{ fontFamily: 'Galey, sans-serif' }}>
            <button type="button" onClick={() => user ? ouvrirCorrection() : setMessageContrib('Connectez-vous pour contribuer.')}
              className="w-full text-left px-4 py-3 text-sm font-bold text-[#1F2A2E] hover:bg-gray-50">Proposer une correction</button>
            <button type="button" onClick={() => { if (user) { setPanneau('signalement'); setMessageContrib(''); } else setMessageContrib('Connectez-vous pour contribuer.'); }}
              className="w-full text-left px-4 py-3 text-sm font-bold text-[#1F2A2E] hover:bg-gray-50">Signaler une information</button>
            {panneau === 'correction' && (
              <div className="px-4 py-4 space-y-3">
                <p className="text-xs text-gray-500">Votre proposition est vérifiée avant d&apos;être appliquée.</p>
                <div className="flex flex-wrap gap-2">
                  {ESPECES_LIEUX.map(e => (
                    <label key={e.value} className="flex items-center gap-1.5 text-sm border border-gray-200 rounded-lg px-2 py-1">
                      <input type="checkbox" className="accent-[#0C5C6C]" checked={corr.especes.includes(e.value)}
                        onChange={() => setCorr(c => ({ ...c, especes: c.especes.includes(e.value) ? c.especes.filter(x => x !== e.value) : [...c.especes, e.value] }))} />
                      {e.label}
                    </label>
                  ))}
                </div>
                {([['Accès intérieur', 'interieur'], ['Terrasse / extérieur', 'terrasse'], ['Restriction de taille', 'taille'], ['Supplément tarifaire', 'supplement']] as const).map(([lib, cle]) => (
                  <fieldset key={cle}>
                    <legend className="text-sm font-bold mb-1">{lib}</legend>
                    <div className="grid grid-cols-3 gap-2">
                      {([['Oui', true], ['Non', false], ['Je ne sais pas', null]] as [string, TroisEtats][]).map(([t, v]) => (
                        <button key={t} type="button" aria-pressed={corr[cle] === v} onClick={() => setCorr(c => ({ ...c, [cle]: v }))}
                          className={`py-1.5 rounded-lg border text-sm ${corr[cle] === v ? 'border-[#0C5C6C] bg-[#E8F4F6] text-[#0C5C6C] font-bold' : 'border-gray-200'}`}>{t}</button>
                      ))}
                    </div>
                  </fieldset>
                ))}
                <textarea value={corr.commentaire} onChange={e => setCorr(c => ({ ...c, commentaire: e.target.value }))} rows={3}
                  placeholder="Précisions (adresse, horaires, fermeture…)" className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />
                <button type="button" onClick={envoyerCorrection} className="w-full py-2.5 rounded-xl bg-[#0C5C6C] text-white font-bold text-sm">Envoyer</button>
              </div>
            )}
            {panneau === 'signalement' && (
              <div className="px-4 py-4 space-y-2">
                {RAISONS_LIEU.map(([v, l]) => (
                  <label key={v} className="flex items-center gap-2 text-sm">
                    <input type="radio" name="raison-lieu" className="accent-[#0C5C6C]" checked={raison === v} onChange={() => setRaison(v)} />{l}
                  </label>
                ))}
                <textarea value={detailSignal} onChange={e => setDetailSignal(e.target.value)} rows={2} placeholder="Précisions"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />
                <button type="button" disabled={!raison} onClick={envoyerSignalement}
                  className="w-full py-2.5 rounded-xl bg-[#0C5C6C] text-white font-bold text-sm disabled:opacity-40">Envoyer</button>
              </div>
            )}
          </div>
        )}
        {messageContrib && <p className="text-sm text-[#0C5C6C] -mt-3 mb-5" style={{ fontFamily: 'Galey, sans-serif' }}>{messageContrib}</p>}

        {/* Gestion : gestionnaire, ou revendication gratuite d'une fiche sans gestionnaire */}
        {!lieu.uid_pro && (
          <div className="mb-5 bg-white rounded-2xl border border-gray-200 p-4" style={{ fontFamily: 'Galey, sans-serif' }}>
            <p className="font-bold text-sm text-[#1F2A2E]">Vous gérez cet établissement ?</p>
            <p className="text-[13px] text-gray-600 mt-1">
              {maRevendication?.statut === 'en_attente' ? "Votre demande est en cours de vérification par l'équipe PetsMatch."
                : maRevendication?.statut === 'refusee' ? `Votre demande précédente a été refusée${maRevendication.motif ? ` : ${maRevendication.motif}` : ''}. Vous pouvez en envoyer une nouvelle.`
                : 'Revendiquez gratuitement cette fiche pour corriger les informations et répondre aux avis. Sans abonnement.'}
            </p>
            {maRevendication?.statut !== 'en_attente' && !revOuvert && (
              user
                ? <button type="button" onClick={() => setRevOuvert(true)} className="mt-3 w-full py-2.5 rounded-xl border border-[#0C5C6C] text-[#0C5C6C] text-sm font-bold">Revendiquer cette fiche</button>
                : <Link href={`/connexion?suite=/animal-friendly/${id}`} className="mt-3 block text-center py-2.5 rounded-xl border border-[#0C5C6C] text-[#0C5C6C] text-sm font-bold">Se connecter pour revendiquer</Link>
            )}
            {revOuvert && (
              <div className="mt-3 space-y-3">
                <div><label htmlFor="rev-fonction" className="text-sm font-bold block mb-1">Votre fonction *</label>
                  <select id="rev-fonction" value={rev.fonction} onChange={e => setRev(r => ({ ...r, fonction: e.target.value }))} className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white">
                    {['Gérant(e)', 'Propriétaire', 'Directeur / directrice', 'Salarié(e) mandaté(e)', 'Autre'].map(f => <option key={f}>{f}</option>)}
                  </select></div>
                <div><label htmlFor="rev-siret" className="text-sm font-bold block mb-1">SIRET de l&apos;établissement *</label>
                  <input id="rev-siret" inputMode="numeric" maxLength={17} value={rev.siret} onChange={e => setRev(r => ({ ...r, siret: e.target.value }))} className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" /></div>
                <fieldset className="space-y-2">
                  <legend className="text-sm font-bold mb-1">Preuve de votre lien avec l&apos;établissement *</legend>
                  <label className="flex items-start gap-2 text-sm"><input type="radio" name="rev-methode" className="mt-1 accent-[#0C5C6C]" checked={rev.methode === 'email_pro'} onChange={() => setRev(r => ({ ...r, methode: 'email_pro' }))} />
                    <span><strong>Adresse e-mail professionnelle</strong><br /><span className="text-gray-500 text-xs">Au nom de domaine du site de l&apos;établissement.</span></span></label>
                  {rev.methode === 'email_pro' && <input type="email" aria-label="E-mail professionnel" value={rev.email} onChange={e => setRev(r => ({ ...r, email: e.target.value }))} placeholder="contact@etablissement.fr" className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />}
                  <label className="flex items-start gap-2 text-sm"><input type="radio" name="rev-methode" className="mt-1 accent-[#0C5C6C]" checked={rev.methode === 'justificatif'} onChange={() => setRev(r => ({ ...r, methode: 'justificatif' }))} />
                    <span><strong>Justificatif</strong><br /><span className="text-gray-500 text-xs">Kbis, extrait INSEE, bail ou facture au nom de l&apos;établissement (PDF ou photo).</span></span></label>
                  {rev.methode === 'justificatif' && <input type="file" accept="image/*,application/pdf" aria-label="Justificatif" onChange={e => setRevFichier(e.target.files?.[0] ?? null)} className="text-sm" />}
                </fieldset>
                <p className="text-xs text-gray-500">Chaque demande est vérifiée par l&apos;équipe PetsMatch avant de donner l&apos;accès à la fiche. Les avis et l&apos;historique sont conservés.</p>
                {revErreur && <p className="text-sm text-red-600">{revErreur}</p>}
                <button type="button" onClick={envoyerRevendication} className="w-full py-2.5 rounded-xl bg-[#0C5C6C] text-white font-bold text-sm">Envoyer ma demande</button>
              </div>
            )}
          </div>
        )}

        {/* Conditions animaux (hébergement) */}
        {isHeb && lieu.uid_pro && (lieu.animaux_dans_chambre != null || lieu.frais_animal_nuit != null || lieu.nb_animaux_max != null || lieu.espace_detente != null || (lieu.equipements_fournis?.length ?? 0) > 0) && (
          <div className="mb-5">
            <h2 className="font-bold text-base text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>Hébergement</h2>
            <div className="bg-white rounded-xl shadow-sm p-3.5 flex flex-col gap-1.5 text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
              {lieu.animaux_dans_chambre != null && <p>Animaux dans la chambre : {lieu.animaux_dans_chambre ? 'oui' : 'non'}</p>}
              {lieu.frais_animal_nuit != null && <p>Supplément / nuit : {lieu.frais_animal_nuit}€</p>}
              {lieu.nb_animaux_max != null && <p>Animaux max / séjour : {lieu.nb_animaux_max === 0 ? 'Pas de limite' : lieu.nb_animaux_max}</p>}
              {lieu.espace_detente != null && <p>Espace détente animaux : {lieu.espace_detente ? 'oui' : 'non'}</p>}
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
