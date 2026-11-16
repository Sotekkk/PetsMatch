'use client';
// Admin — Stockage (16/11/2026) : taille de la base et des fichiers, détail
// des galeries photo (par photographe, par galerie, livraisons en cours,
// galeries anciennes), tendance à partir des relevés quotidiens.
// Données : /api/admin/stockage (migration_admin_stockage.sql).
// La bande passante sortante (egress) ne se lit pas depuis la base : voir le
// tableau de bord Supabase.
import React, { useEffect, useMemo, useState } from 'react';
import { apiFetch } from '@/lib/api-fetch';

const TEAL = '#0C5C6C';

interface Gal {
  album_id: string; pro_uid: string; pro_profile_id: string | null; titre: string | null; statut: string | null;
  created_at: string; livree_le: string | null; photos: number; apercus_octets: number; livraisons_octets: number;
  livraison_expire_le: string | null; photographe: string;
}
interface Releve { jour: string; base_octets: number; buckets: Record<string, { fichiers: number; octets: number }>; galeries: { albums?: number; photos?: number; apercus_octets?: number; livraisons_octets?: number } }
interface Donnees {
  base_octets: number;
  tables: { nom: string; octets: number; lignes: number }[];
  buckets: { bucket: string; fichiers: number; octets: number }[];
  galeries: Gal[];
  releves: Releve[];
}

const LIBELLES_BUCKETS: Record<string, string> = {
  galeries: 'Galeries photo (aperçus)', livraisons: 'Livraisons photo (temporaire)', documents: 'Documents (factures, contrats…)',
  animaux: 'Photos des animaux', avatars: 'Photos de profil', annonces: 'Annonces', posts: 'Réseau social',
};

export const fmtOctets = (o: number | null | undefined) => {
  const n = Number(o) || 0;
  if (n >= 1024 ** 3) return `${(n / 1024 ** 3).toFixed(2).replace('.', ',')} Go`;
  if (n >= 1024 ** 2) return `${(n / 1024 ** 2).toFixed(1).replace('.', ',')} Mo`;
  if (n >= 1024) return `${Math.round(n / 1024)} Ko`;
  return `${n} o`;
};
const fmtNb = (n: number) => n.toLocaleString('fr-FR');
const fmtJour = (d: string | null) => (d ? new Date(d).toLocaleDateString('fr-FR') : '—');
const totalFichiers = (r: Releve) => Object.values(r.buckets ?? {}).reduce((t, b) => t + (Number(b.octets) || 0), 0);

function Carte({ titre, valeur, detail }: { titre: string; valeur: string; detail?: string }) {
  return (
    <div className="bg-white rounded-2xl border border-gray-100 p-4">
      <p className="text-xs font-semibold text-gray-500">{titre}</p>
      <p className="text-2xl font-bold text-[#1F2A2E] mt-1">{valeur}</p>
      {detail && <p className="text-xs text-gray-500 mt-0.5">{detail}</p>}
    </div>
  );
}

function Ecart({ actuel, avant, libelle }: { actuel: number; avant: number | null; libelle: string }) {
  if (avant == null) return <span className="text-xs text-gray-400">{libelle} : pas encore de relevé</span>;
  const d = actuel - avant;
  const couleur = d > 0 ? '#B45309' : d < 0 ? '#2E7D5E' : '#6B7280';
  return <span className="text-xs" style={{ color: couleur }}>{libelle} : {d > 0 ? '+' : d < 0 ? '−' : ''}{fmtOctets(Math.abs(d))}</span>;
}

export default function StockageTab() {
  const [d, setD] = useState<Donnees | null>(null);
  const [erreur, setErreur] = useState('');
  const [ouvert, setOuvert] = useState<string | null>(null);
  const [vueGal, setVueGal] = useState<'photographes' | 'galeries' | 'livraisons' | 'anciennes'>('photographes');
  const [maintenant] = useState(() => Date.now());

  useEffect(() => {
    let vivant = true;
    apiFetch('/api/admin/stockage', { cache: 'no-store' })
      .then(async r => { const j = await r.json(); if (!vivant) return; if (!r.ok) setErreur(j.error ?? 'Chargement impossible'); else setD(j as Donnees); })
      .catch(e => { if (vivant) setErreur((e as Error).message); });
    return () => { vivant = false; };
  }, []);

  const parPhotographe = useMemo(() => {
    const m = new Map<string, { cle: string; nom: string; galeries: Gal[]; photos: number; apercus: number; livraisons: number }>();
    for (const g of d?.galeries ?? []) {
      const cle = g.pro_profile_id ?? `uid:${g.pro_uid}`;
      const e = m.get(cle) ?? { cle, nom: g.photographe, galeries: [], photos: 0, apercus: 0, livraisons: 0 };
      e.galeries.push(g); e.photos += g.photos; e.apercus += g.apercus_octets; e.livraisons += g.livraisons_octets;
      m.set(cle, e);
    }
    return [...m.values()].sort((a, b) => (b.apercus + b.livraisons) - (a.apercus + a.livraisons));
  }, [d]);

  if (erreur) return <p className="text-sm text-red-600 py-6">{erreur}</p>;
  if (!d) return <div className="flex justify-center py-16"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;

  const fichiers = d.buckets.reduce((t, b) => t + Number(b.octets), 0);
  const nbFichiers = d.buckets.reduce((t, b) => t + Number(b.fichiers), 0);
  const apercus = d.galeries.reduce((t, g) => t + g.apercus_octets, 0);
  const livraisons = d.galeries.reduce((t, g) => t + g.livraisons_octets, 0);
  const photos = d.galeries.reduce((t, g) => t + g.photos, 0);

  // Tendance : relevé le plus proche d'il y a N jours.
  const rel = d.releves;
  const avant = (jours: number) => {
    const cible = new Date(maintenant - jours * 86400000).toISOString().slice(0, 10);
    const r = [...rel].reverse().find(x => x.jour <= cible);
    return r ?? null;
  };
  const r7 = avant(7), r30 = avant(30);
  const derniers = rel.slice(-60);
  const maxTotal = Math.max(1, ...derniers.map(r => r.base_octets + totalFichiers(r)));

  const SIX_MOIS = 182 * 86400000;
  const anciennes = d.galeries.filter(g => g.statut === 'archivee' || (g.livree_le && maintenant - new Date(g.livree_le).getTime() > SIX_MOIS)
    || (!g.livree_le && maintenant - new Date(g.created_at).getTime() > SIX_MOIS));
  const enCours = d.galeries.filter(g => g.livraisons_octets > 0).sort((a, b) => (a.livraison_expire_le ?? '').localeCompare(b.livraison_expire_le ?? ''));

  const ligneGal = (g: Gal, avecPhotographe = true) => (
    <tr key={g.album_id} className="border-t border-gray-100">
      <td className="py-1.5 pr-3">{g.titre || 'Séance photo'}{avecPhotographe && <span className="block text-xs text-gray-500">{g.photographe}</span>}</td>
      <td className="py-1.5 pr-3 text-xs">{g.statut ?? '—'}</td>
      <td className="py-1.5 pr-3 text-right">{fmtNb(g.photos)}</td>
      <td className="py-1.5 pr-3 text-right">{fmtOctets(g.apercus_octets)}</td>
      <td className="py-1.5 pr-3 text-right">{g.livraisons_octets ? `${fmtOctets(g.livraisons_octets)} · jusqu'au ${fmtJour(g.livraison_expire_le)}` : '—'}</td>
      <td className="py-1.5 text-right text-xs text-gray-500">{fmtJour(g.created_at)}</td>
    </tr>
  );
  const enteteGal = (
    <thead><tr className="text-left text-xs text-gray-500">
      <th className="pb-1 pr-3 font-semibold">Galerie</th><th className="pb-1 pr-3 font-semibold">Statut</th>
      <th className="pb-1 pr-3 font-semibold text-right">Photos</th><th className="pb-1 pr-3 font-semibold text-right">Aperçus</th>
      <th className="pb-1 pr-3 font-semibold text-right">Livraison</th><th className="pb-1 font-semibold text-right">Créée le</th>
    </tr></thead>
  );

  return (
    <div className="space-y-5" style={{ fontFamily: 'Galey, sans-serif' }}>
      {/* 1. Vue d'ensemble */}
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <Carte titre="Base de données" valeur={fmtOctets(d.base_octets)} detail="Tables, index et historique" />
        <Carte titre="Fichiers stockés" valeur={fmtOctets(fichiers)} detail={`${fmtNb(nbFichiers)} fichiers`} />
        <Carte titre="Galeries photo" valeur={fmtOctets(apercus + livraisons)} detail={`${fmtNb(d.galeries.length)} galeries · ${fmtNb(photos)} photos`} />
        <Carte titre="Livraisons en cours" valeur={fmtOctets(livraisons)} detail={`${enCours.length} galerie${enCours.length > 1 ? 's' : ''}, supprimées à expiration`} />
      </div>

      {/* 3. Tendance */}
      <div className="bg-white rounded-2xl border border-gray-100 p-4">
        <div className="flex flex-wrap items-baseline gap-x-4 gap-y-1">
          <p className="text-sm font-bold text-[#1F2A2E]">Évolution (base + fichiers)</p>
          <Ecart actuel={d.base_octets + fichiers} avant={r7 ? r7.base_octets + totalFichiers(r7) : null} libelle="7 jours" />
          <Ecart actuel={d.base_octets + fichiers} avant={r30 ? r30.base_octets + totalFichiers(r30) : null} libelle="30 jours" />
        </div>
        {derniers.length > 1 ? (
          <div className="mt-3">
            <div className="flex items-end gap-[2px] h-28" role="img" aria-label="Volume total par jour">
              {derniers.map(r => {
                const t = r.base_octets + totalFichiers(r);
                return <div key={r.jour} title={`${fmtJour(r.jour)} : ${fmtOctets(t)}`} className="flex-1 rounded-t-sm min-w-[3px]"
                  style={{ height: `${Math.max(4, (t / maxTotal) * 100)}%`, background: TEAL, opacity: 0.85 }} />;
              })}
            </div>
            <div className="flex justify-between text-[11px] text-gray-400 mt-1">
              <span>{fmtJour(derniers[0].jour)}</span><span>{fmtJour(derniers[derniers.length - 1].jour)}</span>
            </div>
          </div>
        ) : <p className="text-xs text-gray-500 mt-2">Premier relevé enregistré aujourd&apos;hui : la courbe se remplira jour après jour (relevé automatique chaque nuit).</p>}
      </div>

      <div className="grid lg:grid-cols-2 gap-5 items-start">
        {/* Espaces de stockage */}
        <div className="bg-white rounded-2xl border border-gray-100 p-4">
          <p className="text-sm font-bold text-[#1F2A2E] mb-2">Fichiers par espace</p>
          <table className="w-full text-sm">
            <thead><tr className="text-left text-xs text-gray-500"><th className="pb-1 font-semibold">Espace</th><th className="pb-1 font-semibold text-right">Fichiers</th><th className="pb-1 font-semibold text-right">Volume</th><th className="pb-1 font-semibold text-right">Part</th></tr></thead>
            <tbody>
              {d.buckets.map(b => (
                <tr key={b.bucket} className="border-t border-gray-100">
                  <td className="py-1.5 pr-2">{LIBELLES_BUCKETS[b.bucket] ?? b.bucket}<span className="block text-[11px] text-gray-400">{b.bucket}</span></td>
                  <td className="py-1.5 text-right">{fmtNb(Number(b.fichiers))}</td>
                  <td className="py-1.5 text-right">{fmtOctets(Number(b.octets))}</td>
                  <td className="py-1.5 text-right text-xs text-gray-500">{fichiers ? Math.round(Number(b.octets) / fichiers * 100) : 0} %</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        {/* Tables */}
        <div className="bg-white rounded-2xl border border-gray-100 p-4">
          <p className="text-sm font-bold text-[#1F2A2E] mb-2">Plus grosses tables</p>
          <table className="w-full text-sm">
            <thead><tr className="text-left text-xs text-gray-500"><th className="pb-1 font-semibold">Table</th><th className="pb-1 font-semibold text-right">Lignes (estim.)</th><th className="pb-1 font-semibold text-right">Volume</th></tr></thead>
            <tbody>
              {d.tables.map(t => (
                <tr key={t.nom} className="border-t border-gray-100">
                  <td className="py-1.5 font-mono text-xs">{t.nom}</td>
                  <td className="py-1.5 text-right">{fmtNb(Number(t.lignes))}</td>
                  <td className="py-1.5 text-right">{fmtOctets(Number(t.octets))}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* 2. Galeries photo en détail */}
      <div className="bg-white rounded-2xl border border-gray-100 p-4">
        <div className="flex flex-wrap items-center gap-2 mb-3">
          <p className="text-sm font-bold text-[#1F2A2E] mr-2">Galeries photo</p>
          {([['photographes', 'Par photographe'], ['galeries', 'Toutes les galeries'], ['livraisons', `Livraisons en cours (${enCours.length})`], ['anciennes', `Anciennes / archivées (${anciennes.length})`]] as const).map(([k, l]) => (
            <button key={k} onClick={() => setVueGal(k)} className="px-3 py-1 rounded-full text-xs font-semibold"
              style={vueGal === k ? { background: TEAL, color: 'white' } : { background: '#F1F4F3', color: '#1F2A2E' }}>{l}</button>
          ))}
        </div>
        <div className="overflow-x-auto">
          {vueGal === 'photographes' ? (
            <table className="w-full text-sm">
              <thead><tr className="text-left text-xs text-gray-500">
                <th className="pb-1 pr-3 font-semibold">Photographe</th><th className="pb-1 pr-3 font-semibold text-right">Galeries</th>
                <th className="pb-1 pr-3 font-semibold text-right">Photos</th><th className="pb-1 pr-3 font-semibold text-right">Aperçus</th>
                <th className="pb-1 font-semibold text-right">Livraisons</th>
              </tr></thead>
              <tbody>
                {parPhotographe.map(p => (
                  <React.Fragment key={p.cle}>
                    <tr className="border-t border-gray-100 cursor-pointer hover:bg-gray-50" onClick={() => setOuvert(ouvert === p.cle ? null : p.cle)}>
                      <td className="py-1.5 pr-3 font-semibold">{ouvert === p.cle ? '▾' : '▸'} {p.nom}</td>
                      <td className="py-1.5 pr-3 text-right">{p.galeries.length}</td>
                      <td className="py-1.5 pr-3 text-right">{fmtNb(p.photos)}</td>
                      <td className="py-1.5 pr-3 text-right">{fmtOctets(p.apercus)}</td>
                      <td className="py-1.5 text-right">{fmtOctets(p.livraisons)}</td>
                    </tr>
                    {ouvert === p.cle && (
                      <tr><td colSpan={5} className="pb-3 pl-5">
                        <table className="w-full text-sm">{enteteGal}<tbody>{p.galeries.map(g => ligneGal(g, false))}</tbody></table>
                      </td></tr>
                    )}
                  </React.Fragment>
                ))}
              </tbody>
            </table>
          ) : (
            <table className="w-full text-sm">
              {enteteGal}
              <tbody>{(vueGal === 'galeries' ? d.galeries : vueGal === 'livraisons' ? enCours : anciennes).map(g => ligneGal(g))}</tbody>
            </table>
          )}
          {vueGal === 'anciennes' && anciennes.length > 0 && (
            <p className="text-xs text-gray-500 mt-2">Galeries archivées, livrées depuis plus de 6 mois ou créées il y a plus de 6 mois sans livraison : à voir avec le photographe avant tout nettoyage.</p>
          )}
        </div>
      </div>
      <p className="text-xs text-gray-400">La bande passante sortante (egress) n&apos;est pas lisible depuis la base : consultez le tableau de bord Supabase (Usage).</p>
    </div>
  );
}
