'use client';

import { useEffect, useState, useCallback } from 'react';
import Link from 'next/link';
import { useParams, useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import SignalerBaladeButton from '@/components/SignalerBaladeButton';
import { difficulteLabel, difficulteColor, dureeLabel, typeDefiIcon } from '../shared';

interface Balade {
  id: string; titre: string; description?: string; cover_url?: string; statut: string; createur_uid: string;
  createur_profile_id?: string | null;
  espece_cible?: string; difficulte?: string; duree_min?: number; distance_km?: number;
  gratuit?: boolean; prix?: number; note_moyenne?: number; nb_avis?: number; nb_favoris?: number;
  type_evenement?: string; partenaire_nom?: string;
}
interface Point { id: string; ordre: number; titre: string; type_defi: string; }
interface Avis { id: string; user_uid: string; note: number; commentaire?: string; }

export default function BaladeDetailPage() {
  const { id } = useParams<{ id: string }>();
  const { user, activeProfileId } = useAuth();
  const router = useRouter();

  const [balade, setBalade] = useState<Balade | null>(null);
  const [points, setPoints] = useState<Point[]>([]);
  const [avis, setAvis] = useState<Avis[]>([]);
  const [progression, setProgression] = useState<{ statut: string } | null>(null);
  const [isFavori, setIsFavori] = useState(false);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);

  const isOwner = !!(balade && activeProfileId && balade.createur_profile_id === activeProfileId);

  const load = useCallback(async () => {
    setLoading(true);
    const [{ data: b }, { data: pts }, { data: av }] = await Promise.all([
      supabase.from('balades_ludiques').select('*').eq('id', id).single(),
      supabase.from('balades_ludiques_points').select('*').eq('balade_id', id).order('ordre'),
      supabase.from('balades_ludiques_avis').select('*').eq('balade_id', id).order('created_at', { ascending: false }),
    ]);
    setBalade(b as Balade);
    setPoints((pts ?? []) as Point[]);
    setAvis((av ?? []) as Avis[]);

    if (user && activeProfileId) {
      const [{ data: prog }, { data: fav }] = await Promise.all([
        supabase.from('balades_ludiques_progressions').select('statut').eq('balade_id', id).eq('joueur_profile_id', activeProfileId).maybeSingle(),
        supabase.from('balades_ludiques_favoris').select('profile_id').eq('balade_id', id).eq('profile_id', activeProfileId).maybeSingle(),
      ]);
      setProgression(prog);
      setIsFavori(!!fav);
    }
    setLoading(false);
  }, [id, user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  async function toggleFavori() {
    if (!user || !activeProfileId) return;
    const next = !isFavori;
    setIsFavori(next);
    if (next) await supabase.from('balades_ludiques_favoris').insert({ user_uid: user.uid, profile_id: activeProfileId, balade_id: id });
    else await supabase.from('balades_ludiques_favoris').delete().eq('profile_id', activeProfileId).eq('balade_id', id);
    const { count } = await supabase.from('balades_ludiques_favoris').select('*', { count: 'exact', head: true }).eq('balade_id', id);
    await supabase.from('balades_ludiques').update({ nb_favoris: count ?? 0 }).eq('id', id);
  }

  async function commencer() {
    if (!user) { router.push('/connexion'); return; }
    if (!activeProfileId) return;
    if (!progression) {
      await supabase.from('balades_ludiques_progressions').insert({ balade_id: id, joueur_uid: user.uid, joueur_profile_id: activeProfileId });
      const { count } = await supabase.from('balades_ludiques_progressions').select('*', { count: 'exact', head: true }).eq('balade_id', id);
      await supabase.from('balades_ludiques').update({ nb_joueurs: count ?? 0 }).eq('id', id);
    }
    router.push(`/balades-ludiques/${id}/jouer`);
  }

  async function changerStatut(statut: string) {
    setBusy(true);
    await supabase.from('balades_ludiques').update({ statut }).eq('id', id);
    setBusy(false);
    if (statut === 'supprime') { router.push('/balades-ludiques/mes-parcours'); return; }
    load();
  }

  async function laisserAvis() {
    if (!user || !activeProfileId) return;
    const note = Number(prompt('Votre note (1 à 5) ?', '5'));
    if (!note || note < 1 || note > 5) return;
    const commentaire = prompt('Un commentaire (optionnel) ?') ?? undefined;
    await supabase.from('balades_ludiques_avis').upsert({ balade_id: id, user_uid: user.uid, profile_id: activeProfileId, note, commentaire }, { onConflict: 'balade_id,profile_id' });
    const { data: rows } = await supabase.from('balades_ludiques_avis').select('note').eq('balade_id', id);
    const notes = (rows ?? []).map((r: { note: number }) => r.note);
    const moyenne = notes.length ? Math.round((notes.reduce((a: number, b: number) => a + b, 0) / notes.length) * 10) / 10 : null;
    await supabase.from('balades_ludiques').update({ note_moyenne: moyenne, nb_avis: notes.length }).eq('id', id);

    if (moyenne != null && moyenne >= 4.5 && balade?.createur_profile_id) {
      const { data: badgeBienNote } = await supabase.from('badges').select('*').eq('code', 'createur_bien_note').maybeSingle();
      if (badgeBienNote) await supabase.from('badges_obtenus').insert({ user_uid: balade.createur_uid, profile_id: balade.createur_profile_id, badge_id: badgeBienNote.id, balade_id: id });
    }

    load();
  }

  if (loading) return <div className="flex justify-center py-24"><div className="w-8 h-8 border-2 border-teal-700 border-t-transparent rounded-full animate-spin" /></div>;
  if (!balade) return <div className="text-center py-24 text-gray-400 font-galey">Parcours introuvable</div>;

  const ctaLabel = progression?.statut === 'termine' ? 'Rejouer' : progression?.statut === 'en_cours' ? 'Continuer' : 'Commencer';

  return (
    <div className="min-h-screen bg-[#F8F8F6] pb-12">
      <div className="relative h-56 bg-teal-700">
        {balade.cover_url && <img src={balade.cover_url} alt={balade.titre} className="absolute inset-0 w-full h-full object-cover" />}
        <div className="absolute inset-0 bg-black/20" />
        <div className="absolute top-4 left-4 right-4 flex items-center justify-between">
          <button onClick={() => router.back()} className="text-white text-xl">←</button>
          <SignalerBaladeButton baladeId={id} />
        </div>
      </div>

      <div className="max-w-2xl mx-auto px-4 -mt-8 relative">
        <div className="bg-white rounded-2xl shadow-sm p-5">
          {balade.type_evenement && balade.type_evenement !== 'communautaire' && (
            <span className="inline-block mb-2 px-3 py-1 rounded-full bg-orange-600 text-white text-xs font-galey font-bold">
              🏆 {balade.type_evenement === 'officiel_petsmatch' ? 'Chasse au trésor officielle PetsMatch' : `Partenaire — ${balade.partenaire_nom ?? ''}`}
            </span>
          )}
          <h1 className="text-2xl font-bold font-galey text-gray-900">{balade.titre}</h1>
          <div className="flex flex-wrap gap-2 mt-3">
            <span className="text-xs font-galey font-semibold px-2.5 py-1 rounded-full"
              style={{ background: `${difficulteColor(balade.difficulte)}20`, color: difficulteColor(balade.difficulte) }}>
              {difficulteLabel(balade.difficulte)}
            </span>
            {balade.duree_min && <span className="text-xs font-galey px-2.5 py-1 bg-gray-100 rounded-full text-gray-600">{dureeLabel(balade.duree_min)}</span>}
            {balade.distance_km && <span className="text-xs font-galey px-2.5 py-1 bg-gray-100 rounded-full text-gray-600">{balade.distance_km} km</span>}
            <span className="text-xs font-galey font-semibold px-2.5 py-1 bg-teal-50 text-teal-700 rounded-full">{balade.gratuit ? 'Gratuit' : `${balade.prix} €`}</span>
            {balade.note_moyenne && <span className="text-xs font-galey px-2.5 py-1 bg-amber-50 text-amber-700 rounded-full">⭐ {balade.note_moyenne} ({balade.nb_avis})</span>}
            <span className="text-xs font-galey px-2.5 py-1 bg-pink-50 text-pink-600 rounded-full">❤️ {balade.nb_favoris ?? 0}</span>
          </div>
          {balade.description && <p className="mt-4 text-sm font-galey text-gray-600 leading-relaxed">{balade.description}</p>}

          <div className="mt-5">
            <p className="font-galey font-bold text-sm text-gray-800 mb-2">{points.length} étape(s)</p>
            {points.map(p => (
              <div key={p.id} className="flex items-center gap-2 py-1">
                <span className="w-6 h-6 rounded-full bg-teal-50 text-teal-700 text-xs flex items-center justify-center font-galey">{p.ordre}</span>
                <span>{typeDefiIcon(p.type_defi)}</span>
                <span className="text-sm font-galey text-gray-700">{p.titre}</span>
              </div>
            ))}
          </div>

          <div className="flex gap-3 mt-5">
            <button onClick={commencer} className="flex-1 bg-orange-600 hover:bg-orange-700 text-white font-galey font-bold py-3 rounded-xl">
              {ctaLabel}
            </button>
            {user && (
              <button onClick={toggleFavori} className="w-12 h-12 rounded-full border border-gray-200 flex items-center justify-center text-xl">
                {isFavori ? '❤️' : '🤍'}
              </button>
            )}
          </div>

          {progression?.statut === 'termine' && !isOwner && (
            <button onClick={laisserAvis} className="mt-3 w-full border border-teal-700 text-teal-700 font-galey font-semibold py-2.5 rounded-xl">
              Laisser un avis
            </button>
          )}

          {isOwner && (
            <div className="mt-6 pt-4 border-t border-gray-100">
              <p className="font-galey font-bold text-sm text-gray-800 mb-2">Gestion du parcours</p>
              <div className="flex flex-wrap gap-2">
                <Link href={`/balades-ludiques/mes-parcours/${id}/stats`} className="px-3 py-2 rounded-xl border border-gray-200 text-xs font-galey">📊 Statistiques</Link>
                <Link href={`/balades-ludiques/creer?edit=${id}`} className="px-3 py-2 rounded-xl border border-gray-200 text-xs font-galey">✏️ Modifier</Link>
                <button disabled={busy} onClick={() => changerStatut(balade.statut === 'desactive' ? 'publie' : 'desactive')}
                  className="px-3 py-2 rounded-xl border border-gray-200 text-xs font-galey">
                  {balade.statut === 'desactive' ? '▶️ Réactiver' : '⏸️ Désactiver'}
                </button>
                <button disabled={busy} onClick={() => { if (confirm('Supprimer ce parcours ? Cette action est irréversible.')) changerStatut('supprime'); }}
                  className="px-3 py-2 rounded-xl border border-red-200 text-red-600 text-xs font-galey">
                  🗑️ Supprimer
                </button>
              </div>
            </div>
          )}

          {avis.length > 0 && (
            <div className="mt-6 pt-4 border-t border-gray-100">
              <p className="font-galey font-bold text-sm text-gray-800 mb-2">Avis ({avis.length})</p>
              {avis.map(a => (
                <div key={a.id} className="mb-2">
                  <div className="text-amber-500 text-sm">{'⭐'.repeat(a.note)}</div>
                  {a.commentaire && <p className="text-sm font-galey text-gray-600">{a.commentaire}</p>}
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
