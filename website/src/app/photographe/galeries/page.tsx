'use client';
// Mes galeries clients (photographe) : liste filtrable par statut et création
// (rattachée ou non à une séance de l'agenda, sans fiche animal obligatoire).
// Fonctionnalité Premium. Miroir appli : photographe_galeries_page.dart.
// Scopé au profil actif (pro_profile_id).
import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { useProfessionPlanCode } from '@/lib/use-plan';
import { STATUTS_GALERIE, styleGalerie } from '@/lib/photographe';

const TEAL = '#0C5C6C';

interface Galerie {
  id: string; titre: string | null; statut: string | null; date_seance: string | null; client_profile_id: string | null;
  rdv_id: string | null; updated_at: string | null; created_at: string; partage_client: boolean | null;
}
interface Seance { id: string; date_heure: string; motif: string | null; client_uid: string | null; client_profile_id: string | null; client_nom_manuel: string | null; prestation_id?: string | null }

export default function GaleriesPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const pid = useActiveProfile();
  const { planCode, loading: planLoading } = useProfessionPlanCode('photographe');
  const premium = planCode === 'premium';
  const [galeries, setGaleries] = useState<Galerie[]>([]);
  const [nb, setNb] = useState<Record<string, number>>({});
  const [clients, setClients] = useState<Record<string, string>>({});
  const [seances, setSeances] = useState<Seance[]>([]);
  const [filtre, setFiltre] = useState('en_cours');
  const [busy, setBusy] = useState(true);
  const [creation, setCreation] = useState<{ titre: string; date: string; rdvId: string } | null>(null);
  const [enCours, setEnCours] = useState(false);

  const charger = useCallback(async () => {
    if (!user || !pid) return;
    const depuis = new Date(Date.now() - 120 * 86400000).toISOString();
    const [g, s] = await Promise.all([
      supabase.from('albums_photo').select('*').eq('pro_profile_id', pid).order('updated_at', { ascending: false }),
      supabase.from('rdv').select('id, date_heure, motif, client_uid, client_profile_id, client_nom_manuel, prestation_id').eq('pro_profile_id', pid)
        .in('statut', ['confirme', 'termine']).gte('date_heure', depuis).order('date_heure', { ascending: false }).limit(80),
    ]);
    const gal = (g.data ?? []) as Galerie[];
    const se = (s.data ?? []) as Seance[];
    const profils = [...new Set([...gal.map(x => x.client_profile_id), ...se.map(x => x.client_profile_id)].filter(Boolean) as string[])];
    const [p, ph] = await Promise.all([
      profils.length ? supabase.from('user_profiles_complet').select('id, firstname, lastname, nom, profile_type').in('id', profils) : Promise.resolve({ data: [] }),
      gal.length ? supabase.from('album_photos').select('album_id').in('album_id', gal.map(x => x.id)) : Promise.resolve({ data: [] }),
    ]);
    const cl: Record<string, string> = {};
    for (const x of (p.data ?? []) as { id: string; firstname?: string; lastname?: string; nom?: string; profile_type?: string }[]) {
      const perso = `${x.firstname ?? ''} ${x.lastname ?? ''}`.trim(); const st = (x.nom ?? '').trim();
      cl[x.id] = x.profile_type !== 'particulier' && st ? st : perso || st;
    }
    const n: Record<string, number> = {};
    for (const x of (ph.data ?? []) as { album_id: string }[]) n[x.album_id] = (n[x.album_id] ?? 0) + 1;
    setGaleries(gal); setSeances(se); setClients(cl); setNb(n); setBusy(false);
  }, [user, pid]);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    charger();
  }, [charger]);

  const nomSeance = (s: Seance) => (s.client_profile_id && clients[s.client_profile_id]) || s.client_nom_manuel || 'Client';

  async function creer() {
    if (!creation || !user || !pid) return;
    setEnCours(true);
    const s = seances.find(x => x.id === creation.rdvId);
    // Forfait de la séance : photos incluses et prix de la photo supplémentaire.
    const { data: presta } = s?.prestation_id
      ? await supabase.from('prestations_photographe').select('nb_photos, prix_photo_supp').eq('id', s.prestation_id).maybeSingle()
      : { data: null };
    const pr = presta as { nb_photos?: number | null; prix_photo_supp?: number | null } | null;
    const { data, error } = await supabase.from('albums_photo').insert({
      pro_uid: user.uid, pro_profile_id: pid,
      titre: creation.titre.trim() || (s ? `Séance photo — ${nomSeance(s)}` : 'Séance photo'),
      date_seance: creation.date || (s ? s.date_heure.slice(0, 10) : null),
      ...(s ? { rdv_id: s.id, client_uid: s.client_uid, client_profile_id: s.client_profile_id } : {}),
      ...(pr?.nb_photos != null ? { nb_photos_incluses: pr.nb_photos } : {}),
      ...(pr?.prix_photo_supp != null ? { prix_photo_supp: pr.prix_photo_supp } : {}),
    }).select('id').single();
    setEnCours(false);
    if (error) { alert(error.message.includes('column') ? 'Migrations des galeries à passer (migration_photographe_galeries_statut.sql puis migration_photographe_galeries_privees.sql).' : error.message); return; }
    router.push(`/photographe/galeries/${(data as { id: string }).id}`);
  }

  const visibles = galeries.filter(g => {
    const s = g.statut ?? 'brouillon';
    return filtre === 'tous' ? true : filtre === 'en_cours' ? !['livree', 'archivee'].includes(s) : s === filtre;
  });
  const avecGalerie = new Set(galeries.map(g => g.rdv_id).filter(Boolean));

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-6xl mx-auto px-4 py-6 space-y-4">
        <div className="flex items-center gap-3 flex-wrap">
          <h1 className="text-xl font-bold text-[#1F2A2E] flex-1">Mes galeries clients</h1>
          {premium && <button onClick={() => setCreation({ titre: '', date: '', rdvId: '' })} className="px-4 py-2 rounded-xl text-sm font-semibold text-white" style={{ background: TEAL }}>Nouvelle galerie</button>}
        </div>
        {!planLoading && !premium && (
          <div className="bg-white border border-gray-200 rounded-2xl p-4 text-sm">
            <p className="font-semibold text-[#1F2A2E]">Les galeries clients privées sont réservées à la formule Premium.</p>
            <p className="text-gray-600 mt-1">Aperçus compressés et protégés, partage privé au client, sélection et livraison des photos.</p>
            <Link href="/photographe/abonnement" className="inline-block mt-2 font-semibold" style={{ color: TEAL }}>Voir les abonnements →</Link>
          </div>
        )}
        <div className="flex flex-wrap gap-2">
          {[['en_cours', 'En cours'], ...Object.entries(STATUTS_GALERIE).map(([k, v]) => [k, v.label]), ['tous', 'Toutes']].map(([k, l]) => (
            <button key={k} onClick={() => setFiltre(k)} className="px-3 py-1.5 rounded-full text-xs font-semibold border"
              style={filtre === k ? { background: TEAL, color: '#fff', borderColor: TEAL } : { background: '#fff', color: '#374151', borderColor: '#D1D5DB' }}>{l}</button>
          ))}
        </div>
        {busy ? <div className="flex justify-center py-16"><div className="w-7 h-7 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>
          : visibles.length === 0 ? <p className="text-sm text-gray-400 text-center py-16">Aucune galerie.</p> : (
          <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {visibles.map(g => {
              const st = styleGalerie(g.statut);
              const n = nb[g.id] ?? 0;
              return (
                <Link key={g.id} href={`/photographe/galeries/${g.id}`} className="bg-white rounded-2xl border border-gray-100 p-4 hover:shadow-md transition-shadow">
                  <div className="flex items-start gap-2">
                    <p className="flex-1 font-bold text-[#1F2A2E] text-sm">{g.titre ?? 'Galerie'}</p>
                    <span className="text-[11px] font-bold px-2 py-0.5 rounded-full" style={{ color: st.fg, background: st.bg }}>{st.label}</span>
                  </div>
                  <p className="text-xs text-gray-500 mt-1">
                    {[(g.client_profile_id && clients[g.client_profile_id]) || '', g.date_seance ? new Date(g.date_seance).toLocaleDateString('fr-FR') : '', `${n} photo${n > 1 ? 's' : ''}`].filter(Boolean).join(' · ')}
                  </p>
                  {g.partage_client && <p className="text-[11px] mt-1" style={{ color: TEAL }}>Partagée sur le compte du client</p>}
                </Link>
              );
            })}
          </div>
        )}
      </div>

      {creation && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={() => setCreation(null)}>
          <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-md p-5 space-y-3" onClick={e => e.stopPropagation()}>
            <p className="font-bold text-[#1F2A2E]">Nouvelle galerie</p>
            <label className="block"><span className="text-xs font-semibold text-gray-600">Séance associée (facultatif)</span>
              <select value={creation.rdvId} onChange={e => setCreation({ ...creation, rdvId: e.target.value })} className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white">
                <option value="">Aucune séance</option>
                {seances.map(s => (
                  <option key={s.id} value={s.id}>
                    {new Date(s.date_heure).toLocaleDateString('fr-FR')} — {nomSeance(s)}{s.motif ? ` · ${s.motif}` : ''}{avecGalerie.has(s.id) ? ' (galerie existante)' : ''}
                  </option>
                ))}
              </select>
            </label>
            <label className="block"><span className="text-xs font-semibold text-gray-600">Titre</span>
              <input value={creation.titre} onChange={e => setCreation({ ...creation, titre: e.target.value })} placeholder="Ex : Portraits de Tokyo"
                className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" /></label>
            <label className="block"><span className="text-xs font-semibold text-gray-600">Date de la séance</span>
              <input type="date" value={creation.date} onChange={e => setCreation({ ...creation, date: e.target.value })}
                className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" /></label>
            <p className="text-xs text-gray-500">La galerie est créée en brouillon : rien n&apos;est visible du client avant que vous la partagiez.</p>
            <div className="flex gap-2">
              <button onClick={() => setCreation(null)} className="flex-1 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Annuler</button>
              <button onClick={creer} disabled={enCours} className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: TEAL }}>Créer</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
