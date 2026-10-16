'use client';
// Mon portfolio (photographe) — réalisations publiques de la fiche : import
// multiple, titre, description, catégorie (proposées + libres), couverture,
// ordre (glisser-déposer), masquage, suppression, aperçu public. Jamais
// alimenté automatiquement par une galerie privée ; une personne
// identifiable exige son autorisation. Limite du plan Découverte.
// Miroir appli : photographe_portfolio_page.dart. Scopé au profil actif.
import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { useProfessionPlanCode } from '@/lib/use-plan';
import { uploadPhoto } from '@/lib/upload-media';
import { CATEGORIES_PORTFOLIO, itemsPortfolio, portfolioPublic, type ItemPortfolio } from '@/lib/portfolio';

const TEAL = '#0C5C6C';
const AMBRE = '#D97706';
const ROUGE = '#B3261E';
/** Plan Découverte : 5 photos (PlanService.photographeConfigs). */
const MAX_DECOUVERTE = 5;

export default function PortfolioPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const pid = useActiveProfile();
  const { planCode } = useProfessionPlanCode('photographe');
  const max = planCode === 'free' ? MAX_DECOUVERTE : -1;
  const [items, setItems] = useState<ItemPortfolio[] | null>(null);
  const [uidPro, setUidPro] = useState('');
  const [edit, setEdit] = useState<number | null>(null);
  const [brouillon, setBrouillon] = useState<ItemPortfolio | null>(null);
  const [nouvelleCat, setNouvelleCat] = useState('');
  const [envoi, setEnvoi] = useState('');
  const [glisse, setGlisse] = useState<number | null>(null);

  const charger = useCallback(async () => {
    if (!pid) return;
    const { data } = await supabase.from('user_profiles').select('photos_galerie, uid').eq('id', pid).maybeSingle();
    const r = data as { photos_galerie?: unknown; uid?: string } | null;
    setItems(itemsPortfolio(r?.photos_galerie)); setUidPro(r?.uid ?? '');
  }, [pid]);
  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    charger();
  }, [charger]);

  async function enregistrer(liste: ItemPortfolio[]) {
    setItems(liste);
    const { error } = await supabase.from('user_profiles').update({ photos_galerie: liste }).eq('id', pid);
    if (error) alert(`Enregistrement impossible : ${error.message}`);
  }

  async function ajouter(files: File[]) {
    if (!items || !pid) return;
    const images = files.filter(f => f.type.startsWith('image/'));
    const restant = max < 0 ? images.length : Math.max(0, max - items.length);
    const liste = [...items];
    for (let i = 0; i < Math.min(restant, images.length); i++) {
      setEnvoi(`Envoi ${i + 1} / ${Math.min(restant, images.length)}…`);
      try {
        const url = await uploadPhoto(images[i], `portfolio/${pid}/${Date.now()}_${i}.jpg`, { maxDim: 2000, quality: 0.85 });
        liste.push({ url, legende: '', description: '', categorie: '', masquee: false });
      } catch (e) { alert(`${images[i].name} : ${(e as Error).message}`); }
    }
    setEnvoi('');
    await enregistrer(liste);
    if (restant < images.length) alert(`Le plan Découverte est limité à ${MAX_DECOUVERTE} photos de portfolio.`);
  }

  function ouvrir(i: number) { setEdit(i); setBrouillon({ ...items![i] }); setNouvelleCat(''); }
  async function valider() {
    if (edit === null || !brouillon || !items) return;
    const b = { ...brouillon, categorie: nouvelleCat.trim() || brouillon.categorie };
    const liste = items.map((p, i) => (i === edit ? b : b.couverture ? { ...p, couverture: false } : p));
    setEdit(null); setBrouillon(null);
    await enregistrer(liste);
  }
  async function supprimer() {
    if (edit === null || !items || !confirm('Supprimer cette photo du portfolio ?')) return;
    const liste = items.filter((_, i) => i !== edit);
    setEdit(null); setBrouillon(null);
    await enregistrer(liste);
  }
  async function deposer(cible: number) {
    if (glisse === null || !items || glisse === cible) { setGlisse(null); return; }
    const liste = [...items];
    const [x] = liste.splice(glisse, 1);
    liste.splice(cible, 0, x);
    setGlisse(null);
    await enregistrer(liste);
  }

  if (!items) return <div className="flex justify-center py-24"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  const publiees = portfolioPublic(items).length;
  const categories = [...new Set([...CATEGORIES_PORTFOLIO, ...items.map(p => p.categorie ?? '').filter(Boolean)])];

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-6xl mx-auto px-4 py-6 space-y-4">
        <div className="flex items-center gap-3 flex-wrap">
          <div className="flex-1">
            <h1 className="text-xl font-bold text-[#1F2A2E]">Mon portfolio</h1>
            <p className="text-sm text-gray-500">{publiees} publiée{publiees > 1 ? 's' : ''} sur {items.length}{max >= 0 ? ` · plan Découverte : ${max} max` : ''} · glissez une photo pour la déplacer</p>
          </div>
          {uidPro && <Link href={`/services/pro/${uidPro}?profileId=${pid}`} target="_blank" className="px-4 py-2 rounded-xl text-sm font-semibold border border-gray-200 bg-white">Aperçu de ma fiche</Link>}
          <label className={`px-4 py-2 rounded-xl text-sm font-semibold text-white cursor-pointer ${envoi ? 'opacity-60 pointer-events-none' : ''}`} style={{ background: TEAL }}>
            {envoi || 'Ajouter des photos'}
            <input type="file" accept="image/*" multiple className="hidden" onChange={e => { ajouter([...(e.target.files ?? [])]); e.target.value = ''; }} />
          </label>
        </div>
        {max >= 0 && items.length >= max && (
          <p className="text-sm bg-white border border-gray-200 rounded-xl px-4 py-3">Limite du plan Découverte atteinte. <Link href="/photographe/abonnement" className="font-semibold" style={{ color: TEAL }}>Passer à Essentiel →</Link></p>
        )}
        {items.length === 0 ? (
          <p className="text-sm text-gray-400 text-center py-16">Présentez vos plus belles réalisations sur votre fiche professionnelle. Les photos de vos galeries clients ne sont jamais publiées automatiquement.</p>
        ) : (
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
            {items.map((p, i) => {
              const bloquee = p.personne_identifiable && !p.autorisation;
              return (
                <button key={p.url} draggable onDragStart={() => setGlisse(i)} onDragOver={e => e.preventDefault()} onDrop={() => deposer(i)}
                  onClick={() => ouvrir(i)} className="text-left bg-white rounded-2xl border border-gray-100 overflow-hidden hover:shadow-md transition-shadow"
                  style={glisse === i ? { opacity: 0.4 } : undefined}>
                  <div className="aspect-[4/3] bg-gray-50">
                    {/* eslint-disable-next-line @next/next/no-img-element */}
                    <img src={p.url} alt={p.legende} className="w-full h-full object-contain" style={p.masquee || bloquee ? { opacity: 0.45 } : undefined} />
                  </div>
                  <div className="p-2.5">
                    <p className="text-sm font-bold text-[#1F2A2E] truncate">{p.legende || 'Sans titre'}</p>
                    <p className="text-xs truncate" style={{ color: bloquee ? AMBRE : '#6B7280' }}>
                      {[p.categorie, p.couverture ? 'Couverture' : '', p.masquee ? 'Masquée' : '', bloquee ? 'Autorisation manquante' : ''].filter(Boolean).join(' · ') || '—'}
                    </p>
                  </div>
                </button>
              );
            })}
          </div>
        )}
      </div>

      {edit !== null && brouillon && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={() => setEdit(null)}>
          <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-lg p-5 space-y-3 max-h-[92vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={brouillon.url} alt="" className="w-full max-h-56 object-contain rounded-xl bg-gray-50" />
            <input value={brouillon.legende} onChange={e => setBrouillon({ ...brouillon, legende: e.target.value })} placeholder="Titre"
              className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />
            <textarea value={brouillon.description ?? ''} onChange={e => setBrouillon({ ...brouillon, description: e.target.value })} rows={2} placeholder="Description (facultatif)"
              className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
            <div>
              <p className="text-xs font-semibold text-gray-600 mb-1">Catégorie</p>
              <div className="flex flex-wrap gap-1.5">
                {categories.map(c => (
                  <button key={c} type="button" onClick={() => setBrouillon({ ...brouillon, categorie: brouillon.categorie === c ? '' : c })}
                    className="px-3 py-1 rounded-full text-xs font-semibold border"
                    style={brouillon.categorie === c ? { background: TEAL, color: '#fff', borderColor: TEAL } : { borderColor: '#E5E7EB' }}>{c}</button>
                ))}
              </div>
              <input value={nouvelleCat} onChange={e => setNouvelleCat(e.target.value)} placeholder="Nouvelle catégorie"
                className="mt-2 w-full border border-gray-200 rounded-xl px-3 py-1.5 text-sm" />
            </div>
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={!!brouillon.couverture} onChange={e => setBrouillon({ ...brouillon, couverture: e.target.checked })} />Photo de couverture</label>
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={!!brouillon.masquee} onChange={e => setBrouillon({ ...brouillon, masquee: e.target.checked })} />Masquer de la fiche publique</label>
            <label className="flex items-center gap-2 text-sm"><input type="checkbox" checked={!!brouillon.personne_identifiable} onChange={e => setBrouillon({ ...brouillon, personne_identifiable: e.target.checked })} />Une personne est identifiable</label>
            {brouillon.personne_identifiable && (
              <label className="flex items-start gap-2 text-sm pl-6">
                <input type="checkbox" checked={!!brouillon.autorisation} onChange={e => setBrouillon({ ...brouillon, autorisation: e.target.checked })} className="mt-0.5" />
                <span>J&apos;ai son autorisation écrite de publier cette photo
                  {!brouillon.autorisation && <span className="block text-xs" style={{ color: AMBRE }}>Sans autorisation, la photo reste masquée.</span>}</span>
              </label>
            )}
            <div className="flex gap-2 pt-1">
              <button onClick={supprimer} className="px-3 py-2.5 rounded-xl text-sm font-semibold" style={{ color: ROUGE }}>Supprimer</button>
              <span className="flex-1" />
              <button onClick={() => setEdit(null)} className="px-4 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Annuler</button>
              <button onClick={valider} className="px-4 py-2.5 rounded-xl text-sm font-semibold text-white" style={{ background: TEAL }}>Enregistrer</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
