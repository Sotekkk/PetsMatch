'use client';
// Galerie privée côté client (compte destinataire ou lien privé) : grille
// d'aperçus aux proportions conservées, agrandissement. Aperçus seulement
// (compressés, filigrane si activé) : les fichiers finaux ne sont jamais
// exposés ici. Sélection : le client coche ses photos puis confirme
// explicitement (définitif). Livraison : ZIP en stockage temporaire,
// téléchargeables jusqu'à la date d'expiration affichée.
// Coups de cœur (cœur) : distincts de la sélection (coche), retrouvés dans
// Mes favoris > Shootings. Partage aux proches : lien de consultation seule,
// aperçus filigranés (rôle « proche » : ni sélection, ni livraison).
import { useCallback, useEffect, useState } from 'react';
import { choisirPhoto, confirmerSelection, liensLivraison, fmtTaille, aimerPhoto, lienProches, desactiverLienProches, type ContenuGalerie } from '@/lib/galeries-client';

const TEAL = '#0C5C6C';
const ROUGE = '#B3261E';

export default function GalerieVue({ charger, token }: { charger: () => Promise<ContenuGalerie>; token?: string }) {
  const [etat, setEtat] = useState<{ ok: true; g: ContenuGalerie } | { ok: false; err: string } | null>(null);
  const [zoom, setZoom] = useState<number | null>(null);
  const [vueSelection, setVueSelection] = useState(false);
  const [confirmation, setConfirmation] = useState<string | null>(null);
  const [occupe, setOccupe] = useState(false);
  const [partage, setPartage] = useState<{ url: string; expire_at: string } | null>(null);
  const [copie, setCopie] = useState(false);

  const recharger = useCallback(() => {
    charger().then(g => setEtat({ ok: true, g })).catch(e => setEtat({ ok: false, err: (e as Error).message }));
  }, [charger]);

  useEffect(() => {
    let annule = false;
    charger().then(g => { if (!annule) setEtat({ ok: true, g }); })
      .catch(e => { if (!annule) setEtat({ ok: false, err: (e as Error).message }); });
    return () => { annule = true; };
  }, [charger]);

  useEffect(() => {
    if (zoom === null || !etat?.ok) return;
    const n = etat.g.photos.length;
    const k = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setZoom(null);
      if (e.key === 'ArrowRight') setZoom(z => (z === null ? z : (z + 1) % n));
      if (e.key === 'ArrowLeft') setZoom(z => (z === null ? z : (z - 1 + n) % n));
    };
    window.addEventListener('keydown', k);
    return () => window.removeEventListener('keydown', k);
  }, [zoom, etat]);

  if (!etat) return <div className="flex justify-center py-24"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  if (!etat.ok) return (
    <div className="max-w-md mx-auto text-center py-24 px-4">
      <p className="font-bold text-[#1F2A2E]">Galerie indisponible</p>
      <p className="text-sm text-gray-500 mt-1">{etat.err}</p>
    </div>
  );
  const { album, studio, livraison } = etat.g;
  const toutes = etat.g.photos;
  const photos = vueSelection ? toutes.filter(p => p.selectionnee) : toutes;
  const protege = (e: React.SyntheticEvent) => e.preventDefault();
  const client = etat.g.role === 'client';
  const proche = etat.g.role === 'proche';
  const selectionOuverte = client && album.statut === 'partagee' && !album.selection_confirmee_le;
  const nbChoisies = toutes.filter(p => p.selectionnee).length;
  const nbLivres = livraison.reduce((n, l) => n + (l.nb ?? 0), 0);

  async function basculer(id: string, choisie: boolean) {
    if (!etat?.ok) return;
    const g = etat.g;
    setEtat({ ok: true, g: { ...g, photos: g.photos.map(p => (p.id === id ? { ...p, selectionnee: choisie } : p)) } });
    try { await choisirPhoto(album.id, id, choisie, token); } catch (e) { alert((e as Error).message); recharger(); }
  }
  async function aimer(id: string, aimee: boolean) {
    if (!etat?.ok) return;
    const g = etat.g;
    setEtat({ ok: true, g: { ...g, photos: g.photos.map(p => (p.id === id ? { ...p, aimee } : p)) } });
    try { await aimerPhoto(album.id, id, aimee, token); } catch (e) { alert((e as Error).message); recharger(); }
  }
  async function ouvrirPartage() {
    setOccupe(true);
    try { setPartage(await lienProches(album.id, token)); setCopie(false); } catch (e) { alert((e as Error).message); }
    setOccupe(false);
  }
  async function couperPartage() {
    if (!confirm('Désactiver le lien ? Vos proches ne pourront plus voir la galerie.')) return;
    try { await desactiverLienProches(album.id, token); setPartage(null); } catch (e) { alert((e as Error).message); }
  }
  async function confirmer() {
    setOccupe(true);
    try { await confirmerSelection(album.id, confirmation ?? '', token); setConfirmation(null); recharger(); }
    catch (e) { alert((e as Error).message); }
    setOccupe(false);
  }
  async function telecharger() {
    setOccupe(true);
    try {
      const liens = await liensLivraison(album.id, token);
      // Un lien par archive : déclenchés l'un après l'autre (URL signées 10 min).
      for (const l of liens) {
        const a = document.createElement('a');
        a.href = l.url; a.download = l.nom; a.rel = 'noopener';
        document.body.appendChild(a); a.click(); a.remove();
        await new Promise(r => setTimeout(r, 800));
      }
    } catch (e) { alert((e as Error).message); }
    setOccupe(false);
  }
  const coeur = (plein: boolean) => (
    <svg width="18" height="18" viewBox="0 0 24 24" fill={plein ? '#fff' : 'none'} stroke="#fff" strokeWidth={2} aria-hidden>
      <path d="M12 20s-7-4.4-9-9a5 5 0 019-3 5 5 0 019 3c-2 4.6-9 9-9 9z" />
    </svg>
  );
  const coche = (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth={2.6} strokeLinecap="round" strokeLinejoin="round" aria-hidden>
      <path d="M5 12.5l4.5 4.5L19 7.5" />
    </svg>
  );
  const messagePartage = partage
    ? `Regardez les photos de notre séance « ${album.titre ?? 'Séance photo'} »${studio.nom ? ` par ${studio.nom}` : ''} : ${partage.url}`
    : '';

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-6xl mx-auto px-4 py-6">
        <div className="flex items-center gap-3 mb-1">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          {studio.avatar && <img src={studio.avatar} alt="" className="w-10 h-10 rounded-full object-cover" />}
          <div>
            <h1 className="text-xl font-bold text-[#1F2A2E]">{album.titre ?? 'Galerie'}</h1>
            <p className="text-sm text-gray-500">
              {[studio.nom, album.date_seance ? `séance du ${new Date(album.date_seance).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })}` : '', `${photos.length} photo${photos.length > 1 ? 's' : ''}`].filter(Boolean).join(' · ')}
            </p>
          </div>
        </div>
        {album.description && <p className="text-sm text-gray-700 mt-2 whitespace-pre-line">{album.description}</p>}
        <p className="text-xs text-gray-400 mt-2">
          {proche ? 'Galerie partagée avec vous : aperçus protégés par filigrane.' : 'Aperçus en qualité réduite. Les fichiers définitifs vous seront remis par votre photographe.'}
        </p>
        {client && (
          <div className="mt-3 flex flex-wrap items-center gap-2">
            <button onClick={ouvrirPartage} disabled={occupe} className="px-3 py-2 rounded-xl text-sm font-semibold border border-gray-200 bg-white disabled:opacity-50">Partager à mes proches</button>
            {!token && <a href="/favoris?onglet=shootings" className="px-3 py-2 text-sm font-semibold" style={{ color: TEAL }}>Mes coups de cœur dans Mes favoris</a>}
          </div>
        )}

        {livraison.length > 0 && (
          <div className="mt-4 bg-white rounded-2xl border border-gray-100 p-4 flex flex-wrap items-center gap-3">
            <div className="flex-1 min-w-[200px]">
              <p className="text-sm font-bold text-[#1F2A2E]">Vos photos finales sont prêtes</p>
              <p className="text-xs text-gray-500">
                {[nbLivres ? `${nbLivres} fichier${nbLivres > 1 ? 's' : ''}` : '', fmtTaille(livraison.reduce((n, l) => n + (l.taille ?? 0), 0)),
                  livraison.length > 1 ? `${livraison.length} archives ZIP` : 'archive ZIP'].filter(Boolean).join(' · ')}
              </p>
              <p className="text-xs mt-0.5" style={{ color: ROUGE }}>Disponibles jusqu&apos;au {new Date(livraison[0].expire_le).toLocaleDateString('fr-FR')}, puis supprimées : pensez à les enregistrer.</p>
            </div>
            <button onClick={telecharger} disabled={occupe} className="px-4 py-2.5 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: TEAL }}>Télécharger</button>
          </div>
        )}

        {client && (selectionOuverte || album.selection_confirmee_le) && (
          <div className="mt-4 bg-white rounded-2xl border border-gray-100 p-4 flex flex-wrap items-center gap-3">
            <div className="flex-1 min-w-[200px]">
              {album.selection_confirmee_le ? (
                <>
                  <p className="text-sm font-bold text-[#1F2A2E]">Sélection envoyée le {new Date(album.selection_confirmee_le).toLocaleDateString('fr-FR')}</p>
                  <p className="text-xs text-gray-500">{nbChoisies} photo{nbChoisies > 1 ? 's' : ''} choisie{nbChoisies > 1 ? 's' : ''}. Votre photographe prépare vos fichiers.</p>
                </>
              ) : (
                <>
                  <p className="text-sm font-bold text-[#1F2A2E]">Choisissez vos photos</p>
                  <p className="text-xs text-gray-500">
                    Cochez chaque photo que vous souhaitez recevoir ; le cœur garde vos coups de cœur dans Mes favoris. {nbChoisies} sélectionnée{nbChoisies > 1 ? 's' : ''}{album.nb_photos_incluses ? ` sur ${album.nb_photos_incluses} incluse${album.nb_photos_incluses > 1 ? 's' : ''} dans votre prestation` : ''}.
                    {album.nb_photos_incluses && nbChoisies > album.nb_photos_incluses
                      ? (album.prix_photo_supp
                        ? ` ${nbChoisies - album.nb_photos_incluses} photo${nbChoisies - album.nb_photos_incluses > 1 ? 's' : ''} supplémentaire${nbChoisies - album.nb_photos_incluses > 1 ? 's' : ''} × ${album.prix_photo_supp} € = ${(nbChoisies - album.nb_photos_incluses) * album.prix_photo_supp} € en plus du forfait.`
                        : ' Les photos supplémentaires sont facturées selon le tarif de votre photographe.')
                      : ''}
                  </p>
                </>
              )}
            </div>
            {nbChoisies > 0 && (
              <button onClick={() => setVueSelection(v => !v)} className="px-3 py-2 rounded-xl text-sm font-semibold border border-gray-200">
                {vueSelection ? 'Toutes les photos' : 'Voir ma sélection'}
              </button>
            )}
            {selectionOuverte && (
              <button onClick={() => setConfirmation('')} disabled={!nbChoisies} className="px-4 py-2 rounded-xl text-sm font-semibold text-white disabled:opacity-40" style={{ background: TEAL }}>
                Confirmer ma sélection
              </button>
            )}
          </div>
        )}

        {photos.length === 0 ? <p className="text-sm text-gray-400 text-center py-16">{vueSelection ? 'Aucune photo sélectionnée.' : 'Aucune photo pour le moment.'}</p> : (
          <div className="mt-5 columns-2 sm:columns-3 lg:columns-4 gap-3 [column-fill:_balance]">
            {photos.map((p, i) => (
              <div key={p.id} className="relative mb-3 break-inside-avoid rounded-xl overflow-hidden bg-gray-100"
                style={p.selectionnee && client ? { outline: `3px solid ${TEAL}`, outlineOffset: -3 } : undefined}>
                <button onClick={() => setZoom(i)} className="block w-full">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img src={p.url} alt="" loading="lazy" draggable={false} onContextMenu={protege}
                    className="w-full h-auto block select-none" style={p.largeur && p.hauteur ? { aspectRatio: `${p.largeur} / ${p.hauteur}` } : undefined} />
                </button>
                {client && (
                  <button onClick={() => aimer(p.id, !p.aimee)} aria-label={p.aimee ? 'Retirer de mes coups de cœur' : 'Coup de cœur'}
                    className="absolute left-2 top-2 w-9 h-9 rounded-full flex items-center justify-center" style={{ background: p.aimee ? '#E0457B' : 'rgba(0,0,0,0.35)' }}>
                    {coeur(!!p.aimee)}
                  </button>
                )}
                {selectionOuverte ? (
                  <button onClick={() => basculer(p.id, !p.selectionnee)} aria-label={p.selectionnee ? 'Retirer de ma sélection' : 'Ajouter à ma sélection'}
                    className="absolute right-2 top-2 w-9 h-9 rounded-full flex items-center justify-center border-2 border-white/80" style={{ background: p.selectionnee ? TEAL : 'rgba(0,0,0,0.35)' }}>
                    {p.selectionnee && coche}
                  </button>
                ) : p.selectionnee && client ? (
                  <span className="absolute right-2 top-2 w-7 h-7 rounded-full flex items-center justify-center" style={{ background: TEAL }}>{coche}</span>
                ) : null}
              </div>
            ))}
          </div>
        )}
      </div>
      {zoom !== null && photos[zoom] && (
        <div className="fixed inset-0 z-50 bg-black/90 flex items-center justify-center" onClick={() => setZoom(null)}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={photos[zoom].url} alt="" draggable={false} onContextMenu={protege}
            className="max-w-[94vw] max-h-[88vh] object-contain select-none" onClick={e => e.stopPropagation()} />
          {photos.length > 1 && (
            <>
              <button onClick={e => { e.stopPropagation(); setZoom((zoom - 1 + photos.length) % photos.length); }}
                className="absolute left-3 top-1/2 -translate-y-1/2 w-11 h-11 rounded-full bg-white/15 text-white text-2xl">‹</button>
              <button onClick={e => { e.stopPropagation(); setZoom((zoom + 1) % photos.length); }}
                className="absolute right-3 top-1/2 -translate-y-1/2 w-11 h-11 rounded-full bg-white/15 text-white text-2xl">›</button>
            </>
          )}
          <p className="absolute bottom-4 text-white/70 text-sm">{zoom + 1} / {photos.length}</p>
          {client && (
            <button onClick={e => { e.stopPropagation(); aimer(photos[zoom].id, !photos[zoom].aimee); }} aria-label="Coup de cœur"
              className="absolute top-4 left-4 w-10 h-10 rounded-full flex items-center justify-center" style={{ background: photos[zoom].aimee ? '#E0457B' : 'rgba(255,255,255,0.18)' }}>
              {coeur(!!photos[zoom].aimee)}
            </button>
          )}
          {selectionOuverte && (
            <button onClick={e => { e.stopPropagation(); basculer(photos[zoom].id, !photos[zoom].selectionnee); }}
              className="absolute top-4 right-4 px-4 py-2 rounded-full text-sm font-semibold text-white" style={{ background: photos[zoom].selectionnee ? TEAL : 'rgba(255,255,255,0.18)' }}>
              {photos[zoom].selectionnee ? 'Dans ma sélection' : 'Ajouter à ma sélection'}
            </button>
          )}
        </div>
      )}
      {partage && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={() => setPartage(null)}>
          <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-md p-5 space-y-3" onClick={e => e.stopPropagation()}>
            <p className="font-bold text-[#1F2A2E]">Partager à mes proches</p>
            <p className="text-sm text-gray-600">Vos proches voient les photos en aperçu, avec filigrane, sans pouvoir les télécharger ni les choisir. Lien valable jusqu&apos;au {new Date(partage.expire_at).toLocaleDateString('fr-FR')}.</p>
            <div className="grid grid-cols-2 gap-2">
              <a href={`https://wa.me/?text=${encodeURIComponent(messagePartage)}`} target="_blank" rel="noopener noreferrer" className="py-2.5 rounded-xl text-sm font-semibold text-center border border-gray-200">WhatsApp</a>
              <a href={`sms:?&body=${encodeURIComponent(messagePartage)}`} className="py-2.5 rounded-xl text-sm font-semibold text-center border border-gray-200">SMS</a>
              <a href={`mailto:?subject=${encodeURIComponent(`Photos — ${album.titre ?? 'Séance photo'}`)}&body=${encodeURIComponent(messagePartage)}`} className="py-2.5 rounded-xl text-sm font-semibold text-center border border-gray-200">E-mail</a>
              <button onClick={async () => { try { await navigator.clipboard.writeText(partage.url); setCopie(true); } catch { prompt('Copiez le lien :', partage.url); } }}
                className="py-2.5 rounded-xl text-sm font-semibold border border-gray-200">{copie ? 'Lien copié' : 'Copier le lien'}</button>
            </div>
            {typeof navigator !== 'undefined' && 'share' in navigator && (
              <button onClick={() => navigator.share({ title: album.titre ?? 'Séance photo', text: messagePartage }).catch(() => {})}
                className="w-full py-2.5 rounded-xl text-sm font-semibold text-white" style={{ background: TEAL }}>Partager…</button>
            )}
            <div className="flex gap-2">
              <button onClick={couperPartage} className="flex-1 py-2.5 rounded-xl text-sm font-semibold border border-gray-200" style={{ color: ROUGE }}>Désactiver le lien</button>
              <button onClick={() => setPartage(null)} className="flex-1 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Fermer</button>
            </div>
          </div>
        </div>
      )}
      {confirmation !== null && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={() => setConfirmation(null)}>
          <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-md p-5 space-y-3" onClick={e => e.stopPropagation()}>
            <p className="font-bold text-[#1F2A2E]">Confirmer ma sélection</p>
            <p className="text-sm text-gray-600">Vous avez choisi {nbChoisies} photo{nbChoisies > 1 ? 's' : ''}. Une fois confirmée, la sélection est transmise à votre photographe et ne peut plus être modifiée.</p>
            <textarea value={confirmation} onChange={e => setConfirmation(e.target.value)} rows={3} placeholder="Un message pour votre photographe (facultatif)"
              className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
            <div className="flex gap-2">
              <button onClick={() => setConfirmation(null)} className="flex-1 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Revenir</button>
              <button onClick={confirmer} disabled={occupe} className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: TEAL }}>Confirmer</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
