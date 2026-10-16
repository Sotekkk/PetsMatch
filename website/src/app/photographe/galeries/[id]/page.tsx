'use client';
// Gestion d'une galerie client (photographe) — interface studio : import par
// lots (glisser-déposer, progression, doublons écartés), grille de
// miniatures, sélection multiple, couverture, ordre, statut, partage (compte
// client et / ou lien privé avec expiration), archivage, suppression.
// Aperçus seulement (compressés, filigrane facultatif), bucket privé.
// Miroir appli : photographe_album_page.dart.
import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { useParams, useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useProfessionPlanCode } from '@/lib/use-plan';
import { STATUTS_GALERIE } from '@/lib/photographe';
import { chargerGalerie, importerPhotos, supprimerPhotos, supprimerGalerie, type ContenuGalerie } from '@/lib/galeries-client';

const TEAL = '#0C5C6C';
const ROUGE = '#B3261E';

interface Lien { id: string; token: string; expire_at: string; actif: boolean }

export default function GalerieStudioPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { user, loading } = useAuth();
  const { planCode } = useProfessionPlanCode('photographe');
  const premium = planCode !== 'free';
  const [g, setG] = useState<ContenuGalerie | null>(null);
  const [err, setErr] = useState('');
  const [liens, setLiens] = useState<Lien[]>([]);
  const [client, setClient] = useState('');
  const [sel, setSel] = useState<Set<string>>(new Set());
  const [progres, setProgres] = useState<{ fait: number; total: number } | null>(null);
  const [message, setMessage] = useState('');
  const [survol, setSurvol] = useState(false);
  const [duree, setDuree] = useState(30);
  const [titre, setTitre] = useState('');
  const [description, setDescription] = useState('');
  const [maintenant, setMaintenant] = useState(0);

  const charger = useCallback(async () => {
    try {
      const c = await chargerGalerie(id);
      if (c.role !== 'pro') { setErr('Galerie réservée au photographe.'); return; }
      setG(c); setTitre(c.album.titre ?? ''); setDescription(c.album.description ?? '');
      const { data } = await supabase.from('album_partage').select('id, token, expire_at, actif').eq('album_id', id).order('created_at', { ascending: false });
      setLiens((data ?? []) as Lien[]);
      setMaintenant(Date.now());
      if (c.album.client_profile_id) {
        const { data: p } = await supabase.from('user_profiles_complet').select('firstname, lastname, nom').eq('id', c.album.client_profile_id).maybeSingle();
        const x = p as { firstname?: string; lastname?: string; nom?: string } | null;
        setClient(`${x?.firstname ?? ''} ${x?.lastname ?? ''}`.trim() || (x?.nom ?? ''));
      }
    } catch (e) { setErr((e as Error).message); }
  }, [id]);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);
  useEffect(() => {
    if (!user) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    charger();
  }, [user, charger]);

  async function majAlbum(champs: Record<string, unknown>) {
    const { error } = await supabase.from('albums_photo').update({ ...champs, updated_at: new Date().toISOString() }).eq('id', id);
    if (error) { alert(error.message.includes('column') ? 'Migration migration_photographe_galeries_privees.sql à passer.' : error.message); return false; }
    await charger();
    return true;
  }

  async function importer(files: File[]) {
    if (!g || !files.length) return;
    const images = files.filter(f => f.type.startsWith('image/'));
    if (!images.length) return;
    setMessage(''); setProgres({ fait: 0, total: images.length });
    try {
      const b = await importerPhotos(id, images, g.album.filigrane ? `© ${g.studio.nom || 'PetsMatch'}` : null, (fait, total) => setProgres({ fait, total }));
      setMessage([
        `${b.ajoutees} photo${b.ajoutees > 1 ? 's' : ''} ajoutée${b.ajoutees > 1 ? 's' : ''}`,
        b.doublons ? `${b.doublons} doublon${b.doublons > 1 ? 's' : ''} ignoré${b.doublons > 1 ? 's' : ''}` : '',
        b.erreurs.length ? `${b.erreurs.length} erreur${b.erreurs.length > 1 ? 's' : ''} : ${b.erreurs.slice(0, 3).join(' ; ')}` : '',
      ].filter(Boolean).join(' · '));
    } catch (e) { setMessage((e as Error).message); }
    setProgres(null);
    charger();
  }

  async function supprimerSelection() {
    if (!sel.size || !confirm(`Supprimer ${sel.size} photo${sel.size > 1 ? 's' : ''} ? Cette action est définitive.`)) return;
    try { await supprimerPhotos(id, [...sel]); setSel(new Set()); charger(); } catch (e) { alert((e as Error).message); }
  }

  async function deplacer(sens: -1 | 1) {
    if (!g || sel.size !== 1) return;
    const i = g.photos.findIndex(p => sel.has(p.id));
    const j = i + sens;
    if (i < 0 || j < 0 || j >= g.photos.length) return;
    // Ordres explicites (les anciens imports peuvent partager le même ordre).
    await Promise.all(g.photos.map((p, k) => {
      const o = k === i ? j : k === j ? i : k;
      return p.ordre === o ? null : supabase.from('album_photos').update({ ordre: o }).eq('id', p.id);
    }));
    charger();
  }

  async function partageClient(actif: boolean) {
    if (!g?.album.client_uid) return;
    const premiere = actif && !g.album.partage_client;
    const ok = await majAlbum({
      partage_client: actif,
      ...(actif && g.album.statut === 'brouillon' ? { statut: 'partagee', partagee_le: new Date().toISOString() } : {}),
    });
    if (ok && premiere) {
      // Invitation du client (une seule fois, choix explicite du photographe).
      await supabase.from('notifications').insert({
        uid: g.album.client_uid, type: 'galerie_disponible', title: 'Votre galerie photo est disponible',
        body: `${g.studio.nom || 'Votre photographe'} a partagé la galerie « ${g.album.titre ?? 'Séance photo'} ».`,
        ...(g.album.client_profile_id ? { profile_id: g.album.client_profile_id } : {}),
        data: { albumId: id }, read: false,
      });
    }
  }

  async function creerLien() {
    if (!g) return;
    const expire = new Date(Date.now() + duree * 86400000).toISOString();
    const { error } = await supabase.from('album_partage').insert({ album_id: id, expire_at: expire, actif: true });
    if (error) { alert(error.message); return; }
    if (g.album.statut === 'brouillon') await majAlbum({ statut: 'partagee', partagee_le: new Date().toISOString() });
    else charger();
  }

  if (err) return <p className="text-center py-24 text-sm text-gray-500">{err}</p>;
  if (!g) return <div className="flex justify-center py-24"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  const { album, photos } = g;
  const tousSel = photos.length > 0 && sel.size === photos.length;
  const origine = typeof window !== 'undefined' ? window.location.origin : '';
  const liensActifs = liens.filter(l => l.actif && new Date(l.expire_at).getTime() > maintenant);

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-7xl mx-auto px-4 py-5">
        <Link href="/photographe/galeries" className="text-sm font-semibold" style={{ color: TEAL }}>← Mes galeries</Link>
        <div className="grid lg:grid-cols-[1fr_320px] gap-5 mt-3 items-start">
          {/* Colonne principale : import + grille */}
          <div className="space-y-4">
            <div className="bg-white rounded-2xl border border-gray-100 p-4">
              <input value={titre} onChange={e => setTitre(e.target.value)} onBlur={() => titre.trim() !== (album.titre ?? '') && majAlbum({ titre: titre.trim() || 'Séance photo' })}
                className="w-full text-xl font-bold text-[#1F2A2E] outline-none" />
              <p className="text-sm text-gray-500 mt-0.5">{[client, album.date_seance ? `séance du ${new Date(album.date_seance).toLocaleDateString('fr-FR')}` : '', `${photos.length} photo${photos.length > 1 ? 's' : ''}`].filter(Boolean).join(' · ')}</p>
              <textarea value={description} onChange={e => setDescription(e.target.value)} onBlur={() => description !== (album.description ?? '') && majAlbum({ description: description.trim() || null })}
                rows={2} placeholder="Message au client (facultatif)" className="mt-2 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
            </div>

            {premium ? (
              <label onDragOver={e => { e.preventDefault(); setSurvol(true); }} onDragLeave={() => setSurvol(false)}
                onDrop={e => { e.preventDefault(); setSurvol(false); importer([...e.dataTransfer.files]); }}
                className={`block rounded-2xl border-2 border-dashed p-6 text-center cursor-pointer ${progres ? 'pointer-events-none opacity-70' : ''}`}
                style={{ borderColor: survol ? TEAL : '#D1D5DB', background: survol ? '#E6F2F3' : '#fff' }}>
                <input type="file" accept="image/*" multiple className="hidden" onChange={e => { importer([...(e.target.files ?? [])]); e.target.value = ''; }} />
                <p className="text-sm font-semibold text-[#1F2A2E]">Glissez vos photos ici ou cliquez pour les choisir</p>
                <p className="text-xs text-gray-500 mt-1">Aperçus compressés ({album.filigrane ? 'avec filigrane' : 'sans filigrane'}) dans un espace privé. Les doublons sont ignorés.</p>
                {progres && (
                  <div className="mt-3">
                    <div className="h-2 rounded-full bg-gray-100 overflow-hidden"><div className="h-full" style={{ width: `${(progres.fait / progres.total) * 100}%`, background: TEAL }} /></div>
                    <p className="text-xs text-gray-500 mt-1">{progres.fait} / {progres.total}</p>
                  </div>
                )}
              </label>
            ) : (
              <div className="bg-white rounded-2xl border border-gray-200 p-4 text-sm">
                L&apos;import de photos est réservé à l&apos;abonnement Premium. <Link href="/photographe/abonnement" className="font-semibold" style={{ color: TEAL }}>Voir les abonnements →</Link>
              </div>
            )}
            {message && <p className="text-sm text-gray-600">{message}</p>}

            <div className="bg-white rounded-2xl border border-gray-100 p-4">
              <div className="flex flex-wrap items-center gap-2 mb-3">
                <label className="flex items-center gap-2 text-sm">
                  <input type="checkbox" checked={tousSel} onChange={() => setSel(tousSel ? new Set() : new Set(photos.map(p => p.id)))} />
                  {sel.size ? `${sel.size} sélectionnée${sel.size > 1 ? 's' : ''}` : 'Tout sélectionner'}
                </label>
                <span className="flex-1" />
                {sel.size === 1 && <>
                  <button onClick={() => majAlbum({ couverture_url: [...sel][0] })} className="px-3 py-1.5 rounded-lg text-xs font-semibold border border-gray-200">Définir comme couverture</button>
                  <button onClick={() => deplacer(-1)} className="px-3 py-1.5 rounded-lg text-xs font-semibold border border-gray-200">Avancer</button>
                  <button onClick={() => deplacer(1)} className="px-3 py-1.5 rounded-lg text-xs font-semibold border border-gray-200">Reculer</button>
                </>}
                {sel.size > 0 && <button onClick={supprimerSelection} className="px-3 py-1.5 rounded-lg text-xs font-semibold border" style={{ color: ROUGE, borderColor: '#F3C9C5' }}>Supprimer</button>}
              </div>
              {photos.length === 0 ? <p className="text-sm text-gray-400 text-center py-10">Aucune photo importée.</p> : (
                <div className="grid grid-cols-3 sm:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-2">
                  {photos.map(p => {
                    const actif = sel.has(p.id);
                    return (
                      <button key={p.id} onClick={() => setSel(s => { const n = new Set(s); if (n.has(p.id)) n.delete(p.id); else n.add(p.id); return n; })}
                        className="relative aspect-square rounded-lg overflow-hidden bg-gray-100" style={{ outline: actif ? `3px solid ${TEAL}` : 'none', outlineOffset: -3 }}>
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        <img src={p.url} alt="" loading="lazy" className="w-full h-full object-contain bg-gray-50" />
                        {album.couverture_url === p.id && <span className="absolute left-1 top-1 text-[10px] font-bold px-1.5 py-0.5 rounded bg-white/90 text-[#1F2A2E]">Couverture</span>}
                        {actif && <span className="absolute right-1 top-1 w-5 h-5 rounded-full text-white text-xs flex items-center justify-center" style={{ background: TEAL }}>✓</span>}
                      </button>
                    );
                  })}
                </div>
              )}
            </div>
          </div>

          {/* Colonne secondaire : statut, partage, archivage */}
          <div className="space-y-4">
            <div className="bg-white rounded-2xl border border-gray-100 p-4 space-y-2">
              <p className="text-sm font-bold text-[#1F2A2E]">Statut</p>
              <select value={album.statut} onChange={e => majAlbum({ statut: e.target.value, ...(e.target.value === 'livree' ? { livree_le: new Date().toISOString() } : {}) })}
                className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white">
                {Object.entries(STATUTS_GALERIE).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
              </select>
              <p className="text-xs text-gray-500">Une galerie livrée n&apos;est pas considérée comme payée : la facturation garde son propre statut.</p>
            </div>

            <div className="bg-white rounded-2xl border border-gray-100 p-4 space-y-3">
              <p className="text-sm font-bold text-[#1F2A2E]">Partage</p>
              {album.client_uid ? (
                <label className="flex items-start gap-2 text-sm">
                  <input type="checkbox" checked={album.partage_client} onChange={e => partageClient(e.target.checked)} className="mt-0.5" />
                  <span>Partager sur le compte de {client || 'mon client'}
                    <span className="block text-xs text-gray-500">Il est prévenu et retrouve la galerie dans « Mes galeries photo ».</span></span>
                </label>
              ) : <p className="text-xs text-gray-500">Galerie sans client PetsMatch : utilisez un lien privé.</p>}
              <div className="border-t border-gray-100 pt-3">
                <p className="text-xs font-semibold text-gray-600 mb-1">Lien privé</p>
                <div className="flex gap-2">
                  <select value={duree} onChange={e => setDuree(Number(e.target.value))} className="flex-1 border border-gray-200 rounded-xl px-2 py-2 text-sm bg-white">
                    <option value={7}>Valable 7 jours</option><option value={30}>Valable 30 jours</option><option value={90}>Valable 90 jours</option>
                  </select>
                  <button onClick={creerLien} className="px-3 rounded-xl text-sm font-semibold text-white" style={{ background: TEAL }}>Créer</button>
                </div>
                {liensActifs.map(l => (
                  <div key={l.id} className="mt-2 text-xs">
                    <div className="flex items-center gap-2">
                      <input readOnly value={`${origine}/album/${l.token}`} className="flex-1 border border-gray-200 rounded-lg px-2 py-1.5 bg-gray-50" onFocus={e => e.target.select()} />
                      <button onClick={() => navigator.clipboard.writeText(`${origine}/album/${l.token}`)} className="font-semibold" style={{ color: TEAL }}>Copier</button>
                    </div>
                    <div className="flex justify-between mt-0.5 text-gray-500">
                      <span>Expire le {new Date(l.expire_at).toLocaleDateString('fr-FR')}</span>
                      <button onClick={async () => { await supabase.from('album_partage').update({ actif: false }).eq('id', l.id); charger(); }} style={{ color: ROUGE }}>Désactiver</button>
                    </div>
                  </div>
                ))}
                <p className="text-[11px] text-gray-400 mt-2">Le lien n&apos;ouvre que cette galerie, n&apos;est jamais indexé et cesse de fonctionner à l&apos;expiration.</p>
              </div>
              <label className="flex items-start gap-2 text-sm border-t border-gray-100 pt-3">
                <input type="checkbox" checked={album.filigrane} onChange={e => majAlbum({ filigrane: e.target.checked })} className="mt-0.5" />
                <span>Filigrane sur les aperçus<span className="block text-xs text-gray-500">S&apos;applique aux prochains imports. Dissuasif, pas une protection absolue.</span></span>
              </label>
              <Link href={`/galerie/${id}`} target="_blank" className="block text-sm font-semibold" style={{ color: TEAL }}>Voir comme le client →</Link>
            </div>

            <div className="bg-white rounded-2xl border border-gray-100 p-4 space-y-2">
              <p className="text-sm font-bold text-[#1F2A2E]">Archivage</p>
              {album.statut === 'archivee' ? (
                <button onClick={() => majAlbum({ statut: album.partage_client ? 'partagee' : 'brouillon' })} className="w-full py-2 rounded-xl text-sm font-semibold border border-gray-200">Rouvrir la galerie</button>
              ) : (
                <button onClick={async () => {
                  if (!confirm('Archiver la galerie ? Elle ne sera plus visible du client et les liens privés seront désactivés.')) return;
                  await supabase.from('album_partage').update({ actif: false }).eq('album_id', id);
                  await majAlbum({ statut: 'archivee' });
                }} className="w-full py-2 rounded-xl text-sm font-semibold border border-gray-200">Archiver</button>
              )}
              <button onClick={async () => {
                if (!confirm('Supprimer définitivement la galerie et toutes ses photos ?')) return;
                try { await supprimerGalerie(id); router.push('/photographe/galeries'); } catch (e) { alert((e as Error).message); }
              }} className="w-full py-2 rounded-xl text-sm font-semibold border" style={{ color: ROUGE, borderColor: '#F3C9C5' }}>Supprimer la galerie</button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
