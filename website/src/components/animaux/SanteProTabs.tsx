'use client';
// Fiches vétérinaire / ostéopathe — onglets Synthèse et Documents. Miroir
// appli : lib/widgets/animal/sante_pro_tabs.dart. Données existantes :
// comptes_rendus, ordonnances, suivis_morpho, carnet (poids, allergies,
// traitements, vaccinations, chirurgies), rdv (profil actif).
import { useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { titreCompteRendu } from '@/lib/morpho';

const TEAL = '#0C5C6C';
const ROUGE = '#B3261E';
type Row = Record<string, unknown>;

const dateFr = (v: unknown) => v ? new Date(String(v)).toLocaleDateString('fr-FR') : '';
const texte = (v: unknown) => String(v ?? '').replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').trim();

function Carte({ titre, children, action }: { titre: string; children: React.ReactNode; action?: React.ReactNode }) {
  return (
    <div className="bg-white rounded-2xl border border-gray-100 p-4" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="flex items-center justify-between mb-2">
        <p className="font-bold text-sm text-[#1F2A2E]">{titre}</p>
        {action}
      </div>
      <div className="text-sm text-[#1F2A2E] space-y-1">{children}</div>
    </div>
  );
}
const Discret = ({ t }: { t: string }) => <p className="text-sm text-gray-400">{t}</p>;

async function prochainRdv(animalId: string, pid: string | null) {
  if (!pid) return null;
  const { data } = await supabase.from('rdv').select('id, date_heure, motif, lieu').eq('pro_profile_id', pid).eq('animal_id', animalId)
    .eq('statut', 'confirme').gte('date_heure', new Date().toISOString()).order('date_heure').limit(1).maybeSingle();
  return data as { id: string; date_heure: string; motif: string | null; lieu: string | null } | null;
}
const rdvTexte = (r: { date_heure: string; motif: string | null; lieu: string | null }) =>
  `${new Date(r.date_heure).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })}${r.motif ? ` · ${r.motif}` : ''}${r.lieu ? ` · ${r.lieu}` : ''}`;

/** Ligne de rappel cliquable : rappel fait aujourd'hui / RDV de rappel. */
function LigneRappel({ onClick, children, rouge, gras }: { onClick: () => void; children: React.ReactNode; rouge?: boolean; gras?: boolean }) {
  return (
    <button type="button" onClick={onClick}
      className={`w-full flex items-center justify-between gap-2 text-left hover:underline ${gras ? 'font-semibold' : ''}`}
      style={rouge ? { color: ROUGE } : undefined}>
      <span>{children}</span><span aria-hidden className="text-gray-400">›</span>
    </button>
  );
}

/** Nouveau RDV pour cet animal (propriétaire pré-rempli) — mes-rdv. */
const lienNouveauRdv = (animalId: string, motif?: string) =>
  `/mes-rdv?nouveau=1&animal=${encodeURIComponent(animalId)}${motif ? `&motif=${encodeURIComponent(motif)}` : ''}`;

export function SyntheseVet({ animalId, pid, onIdentite, onFaireRappel, peutEcrire }: {
  animalId: string; pid: string | null; onIdentite: () => void;
  /** Rappel fait aujourd'hui : formulaire vaccin pré-rempli (nom, prochain rappel) — absent en lecture seule. */
  onFaireRappel?: (vaccin: string, rappel: string) => void;
  /** Écriture au carnet autorisée (pesée depuis la Synthèse). */
  peutEcrire?: boolean;
}) {
  const [rappelOuvert, setRappelOuvert] = useState<Row | null>(null);
  // Pesée du jour (souvent le premier geste) → courbe de poids + fiche ;
  // reprise ensuite dans le compte rendu.
  const [pesee, setPesee] = useState<string | null>(null);
  const [maj, setMaj] = useState(0);
  async function enregistrerPesee() {
    const kg = parseFloat((pesee ?? '').replace(',', '.').replace(/\s/g, ''));
    if (!(kg > 0)) return;
    const { error } = await supabase.from('poids').insert({ id: `${Date.now()}`, animal_id: animalId, valeur: kg, date: new Date().toISOString(), notes: 'Consultation' });
    if (error) { alert(`Erreur : ${error.message}`); return; }
    await supabase.from('animaux').update({ poids: kg }).eq('id', animalId);
    setPesee(null); setMaj(n => n + 1);
  }
  const [d, setD] = useState<{ cr: Row | null; poids: Row | null; allergies: Row[]; trt: Row[]; vac: Row[]; chir: Row[]; rdv: Awaited<ReturnType<typeof prochainRdv>> } | null>(null);
  useEffect(() => {
    let annule = false;
    (async () => {
      const [cr, poids, al, trt, vac, chir, rdv] = await Promise.all([
        supabase.from('comptes_rendus').select('*').eq('animal_id', animalId).order('created_at', { ascending: false }).limit(1).maybeSingle(),
        supabase.from('poids').select('*').eq('animal_id', animalId).order('date', { ascending: false }).limit(1).maybeSingle(),
        supabase.from('allergies').select('*').eq('animal_id', animalId),
        supabase.from('traitements').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
        supabase.from('vaccinations').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
        supabase.from('chirurgies').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
        prochainRdv(animalId, pid),
      ]);
      if (!annule) setD({ cr: cr.data as Row | null, poids: poids.data as Row | null, allergies: (al.data ?? []) as Row[], trt: (trt.data ?? []) as Row[], vac: (vac.data ?? []) as Row[], chir: (chir.data ?? []) as Row[], rdv });
    })();
    return () => { annule = true; };
  }, [animalId, pid, maj]);
  if (!d) return <div className="flex justify-center py-10"><div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  const now = new Date();
  const actifs = d.trt.filter(t => !t.date_fin || new Date(String(t.date_fin)) >= now);
  // Rappel dépassé seulement si la DERNIÈRE injection de sa catégorie (rage,
  // CHPPi, leptospirose…, sinon nom normalisé) a un rappel passé — miroir appli.
  const groupe = (v: Row) => String(v.categorie ?? '').trim().toLowerCase() || String(v.vaccin ?? '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  const derniersMap = new Map<string, Row>();
  for (const v of d.vac) {
    const k = groupe(v); const cur = derniersMap.get(k);
    if (!cur || new Date(String(v.date ?? 0)) > new Date(String(cur.date ?? 0))) derniersMap.set(k, v);
  }
  const derniers = [...derniersMap.values()].sort((a, b) => new Date(String(b.date ?? 0)).getTime() - new Date(String(a.date ?? 0)).getTime());
  const depasses = derniers.filter(v => v.date_rappel && new Date(String(v.date_rappel)) < now);
  const prochains = derniers.filter(v => v.date_rappel && new Date(String(v.date_rappel)) >= now)
    .sort((a, b) => new Date(String(a.date_rappel)).getTime() - new Date(String(b.date_rappel)).getTime());
  const poids = d.poids?.valeur ?? d.poids?.poids;
  const auj = new Date().toLocaleDateString('sv-SE');
  /** Prochain rappel au même intervalle que l'injection précédente (1 an à défaut). */
  const rappelSuivant = (v: Row) => {
    const d0 = v.date ? new Date(String(v.date)) : null, dr = v.date_rappel ? new Date(String(v.date_rappel)) : null;
    const base = new Date(auj + 'T12:00:00');
    if (d0 && dr && dr > d0) base.setDate(base.getDate() + Math.round((dr.getTime() - d0.getTime()) / 86400000));
    else base.setFullYear(base.getFullYear() + 1);
    return base.toLocaleDateString('sv-SE');
  };
  const nomVaccin = (v: Row) => String(v.vaccin ?? v.categorie ?? 'vaccin');
  return (
    <div className="space-y-4">
      {(d.allergies.length > 0 || depasses.length > 0) && (
        <Carte titre="Alertes cliniques">
          {d.allergies.map((a, i) => <p key={i} style={{ color: ROUGE }}>Allergie : {String(a.description ?? a.nom ?? '')}</p>)}
          {depasses.slice(0, 3).map((v, i) => <LigneRappel key={`v${i}`} onClick={() => setRappelOuvert(v)} rouge>Rappel dépassé : {String(v.vaccin ?? 'vaccin')} ({dateFr(v.date_rappel)})</LigneRappel>)}
        </Carte>
      )}
      {rappelOuvert && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={() => setRappelOuvert(null)}>
          <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-sm p-5 space-y-2" onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
            <p className="font-bold text-[#1F2A2E]">Rappel : {nomVaccin(rappelOuvert)}</p>
            {onFaireRappel && (
              <button type="button" onClick={() => { onFaireRappel(nomVaccin(rappelOuvert), rappelSuivant(rappelOuvert)); setRappelOuvert(null); }}
                className="w-full text-left rounded-xl border border-gray-200 px-4 py-3 hover:bg-gray-50">
                <span className="block text-sm font-semibold text-[#0C5C6C]">Enregistrer le rappel</span>
                <span className="block text-xs text-gray-500">Fait aujourd’hui, prochain rappel au même intervalle</span>
              </button>
            )}
            <Link href={lienNouveauRdv(animalId, `Rappel vaccin — ${nomVaccin(rappelOuvert)}`)}
              className="block rounded-xl border border-gray-200 px-4 py-3 hover:bg-gray-50">
              <span className="block text-sm font-semibold text-[#0C5C6C]">Planifier un RDV de rappel</span>
              <span className="block text-xs text-gray-500">Dans l’agenda du propriétaire et des co-propriétaires</span>
            </Link>
            <button type="button" onClick={() => setRappelOuvert(null)} className="w-full text-sm text-gray-500 py-2">Fermer</button>
          </div>
        </div>
      )}
      <div className="grid sm:grid-cols-2 gap-4">
        <Carte titre="Dernière consultation">{d.cr ? <><p className="text-xs font-semibold text-gray-600">{dateFr(d.cr.created_at)}</p><p className="line-clamp-3">{texte(d.cr.contenu)}</p></> : <Discret t="Aucun compte rendu." />}</Carte>
        <Carte titre="Prochain rendez-vous">
          {d.rdv ? <p>{rdvTexte(d.rdv)}</p> : <Discret t="Aucun rendez-vous planifié." />}
          <div className="flex flex-wrap gap-2 pt-1">
            {d.rdv && (
              <Link href={`/mes-rdv?onglet=a_venir&rdv=${d.rdv.id}&modifier=1&animal=${encodeURIComponent(animalId)}`}
                className="px-3 py-1.5 rounded-lg border text-xs font-semibold" style={{ borderColor: TEAL, color: TEAL }}>Modifier</Link>
            )}
            <Link href={lienNouveauRdv(animalId)} className="px-3 py-1.5 rounded-lg border text-xs font-semibold" style={{ borderColor: TEAL, color: TEAL }}>
              {d.rdv ? 'Autre RDV' : 'Planifier un RDV'}
            </Link>
          </div>
        </Carte>
        <Carte titre="Dernier poids connu" action={peutEcrire && pesee == null ? (
          <button type="button" onClick={() => setPesee('')} className="text-xs font-semibold" style={{ color: TEAL }}>+ Nouvelle pesée</button>
        ) : undefined}>
          {poids != null ? <p>{String(poids)} kg · {dateFr(d.poids?.date)}</p> : <Discret t="Non renseigné." />}
          {pesee != null && (
            <div className="flex items-center gap-2 pt-1">
              <input autoFocus inputMode="decimal" value={pesee} onChange={e => setPesee(e.target.value)} placeholder="Poids (kg)"
                onKeyDown={e => { if (e.key === 'Enter') enregistrerPesee(); }}
                className="w-28 border border-gray-200 rounded-lg px-2 py-1.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              <button type="button" onClick={enregistrerPesee} className="px-3 py-1.5 rounded-lg text-xs font-semibold text-white" style={{ background: TEAL }}>Enregistrer</button>
              <button type="button" onClick={() => setPesee(null)} className="text-xs text-gray-500">Annuler</button>
            </div>
          )}
        </Carte>
        <Carte titre="Allergies">{d.allergies.length ? d.allergies.map((a, i) => <p key={i}>{String(a.description ?? a.nom ?? '')}{a.severite ? ` (${String(a.severite)})` : ''}</p>) : <Discret t="Non renseigné." />}</Carte>
        <Carte titre="Traitements actifs">{actifs.length ? actifs.map((t, i) => <p key={i}>{String(t.nom ?? '')}{t.posologie ? ` — ${String(t.posologie)}` : ''}</p>) : <Discret t="Aucun traitement en cours." />}</Carte>
        <Carte titre="Vaccinations">
          {d.vac.length ? <>
            {derniers.map((v, i) => v.date_rappel ? (
              <LigneRappel key={i} onClick={() => setRappelOuvert(v)} rouge={new Date(String(v.date_rappel)) < now}>
                {String(v.vaccin ?? '')} — {dateFr(v.date)} · rappel {dateFr(v.date_rappel)}
              </LigneRappel>
            ) : (
              <p key={i}>{String(v.vaccin ?? '')} — {dateFr(v.date)}</p>
            ))}
            {prochains[0] && <LigneRappel onClick={() => setRappelOuvert(prochains[0])} gras>Prochain rappel : {String(prochains[0].vaccin ?? '')} le {dateFr(prochains[0].date_rappel)}</LigneRappel>}
          </> : <Discret t="Aucune vaccination enregistrée." />}
        </Carte>
        <Carte titre="Antécédents">{d.chir.length ? d.chir.slice(0, 5).map((c, i) => <p key={i}>{dateFr(c.date)} — {String(c.intitule ?? c.nom ?? c.type ?? 'Chirurgie')}</p>) : <Discret t="Aucun antécédent chirurgical enregistré." />}</Carte>
      </div>
      <button onClick={onIdentite} className="px-4 py-2 rounded-xl border text-sm font-semibold" style={{ borderColor: TEAL, color: TEAL }}>Identité complète</button>
    </div>
  );
}

export function SyntheseOsteo({ animalId, pid, onIdentite, onSeances }: { animalId: string; pid: string | null; onIdentite: () => void; onSeances: () => void }) {
  const [d, setD] = useState<{ seances: Row[]; rdv: Awaited<ReturnType<typeof prochainRdv>> } | null>(null);
  useEffect(() => {
    let annule = false;
    (async () => {
      const [{ data }, rdv] = await Promise.all([
        supabase.from('suivis_morpho').select('*').eq('animal_id', animalId).eq('source', 'professionnel').order('date', { ascending: false }),
        prochainRdv(animalId, pid),
      ]);
      const s = ((data ?? []) as Row[]).filter(x => !pid || x.pro_profile_id === pid);
      if (!annule) setD({ seances: s, rdv });
    })();
    return () => { annule = true; };
  }, [animalId, pid]);
  if (!d) return <div className="flex justify-center py-10"><div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  const der = d.seances[0];
  const motif = d.seances.map(s => String(s.motif ?? '').trim()).find(Boolean) ?? '';
  const brouillons = d.seances.filter(s => s.statut === 'brouillon').length;
  const c = (k: string) => texte(der?.[k]);
  return (
    <div className="space-y-4">
      {brouillons > 0 && (
        <button onClick={onSeances} className="w-full text-left rounded-xl px-4 py-3 text-sm font-semibold" style={{ background: '#FFF4DC', color: '#8A5A00' }}>
          {brouillons} séance{brouillons > 1 ? 's' : ''} à finaliser
        </button>
      )}
      <div className="grid sm:grid-cols-2 gap-4">
        <Carte titre="Motif du suivi">{motif ? <p>{motif}</p> : <Discret t="Non renseigné." />}</Carte>
        <Carte titre="Séances" action={<button onClick={onSeances} className="text-xs font-semibold" style={{ color: TEAL }}>Voir</button>}>
          {der ? <>
            <p className="font-semibold">{d.seances.length} séance{d.seances.length > 1 ? 's' : ''} réalisée{d.seances.length > 1 ? 's' : ''}</p>
            <p>Dernière : {dateFr(der.date)} — {titreCompteRendu(String(der.type_suivi ?? ''))}</p>
            {der.lieu ? <p>Lieu : {String(der.lieu)}</p> : null}
          </> : <Discret t="Aucune séance enregistrée." />}
        </Carte>
        <Carte titre="Principales observations">
          {c('observations_bilan') || c('intervention') ? <>
            {c('observations_bilan') && <p>{c('observations_bilan')}</p>}
            {c('intervention') && <p>Intervention : {c('intervention')}</p>}
          </> : <Discret t="Aucune observation." />}
        </Carte>
        <Carte titre="Recommandations en cours">
          {c('suivi_recommande') || c('commentaires') ? <>
            {c('suivi_recommande') && <p>{c('suivi_recommande')}</p>}
            {c('commentaires') && <p>{c('commentaires')}</p>}
            {der?.prochain_controle ? <p style={{ color: '#D97706' }}>Prochain contrôle : {dateFr(der.prochain_controle)}</p> : null}
          </> : <Discret t="Aucune recommandation." />}
        </Carte>
        <Carte titre="Prochain rendez-vous">
          {d.rdv ? <p>{rdvTexte(d.rdv)}</p> : <Discret t="Aucun rendez-vous planifié." />}
          <div className="flex flex-wrap gap-2 pt-1">
            {d.rdv && (
              <Link href={`/mes-rdv?onglet=a_venir&rdv=${d.rdv.id}&modifier=1&animal=${encodeURIComponent(animalId)}`}
                className="px-3 py-1.5 rounded-lg border text-xs font-semibold" style={{ borderColor: TEAL, color: TEAL }}>Modifier</Link>
            )}
            <Link href={lienNouveauRdv(animalId)} className="px-3 py-1.5 rounded-lg border text-xs font-semibold" style={{ borderColor: TEAL, color: TEAL }}>
              {d.rdv ? 'Autre RDV' : 'Planifier un RDV'}
            </Link>
          </div>
        </Carte>
      </div>
      <button onClick={onIdentite} className="px-4 py-2 rounded-xl border text-sm font-semibold" style={{ borderColor: TEAL, color: TEAL }}>Identité complète</button>
    </div>
  );
}

export function DocumentsSantePro({ animalId, pid, osteo = false }: { animalId: string; pid: string | null; osteo?: boolean }) {
  const [d, setD] = useState<{ crs: Row[]; ordos: Row[]; seances: Row[] } | null>(null);
  useEffect(() => {
    let annule = false;
    (async () => {
      if (osteo) {
        const { data } = await supabase.from('suivis_morpho').select('*').eq('animal_id', animalId).eq('source', 'professionnel')
          .neq('statut', 'brouillon').order('date', { ascending: false });
        if (!annule) setD({ crs: [], ordos: [], seances: ((data ?? []) as Row[]).filter(x => !pid || x.pro_profile_id === pid) });
      } else {
        const [cr, o] = await Promise.all([
          supabase.from('comptes_rendus').select('*').eq('animal_id', animalId).order('created_at', { ascending: false }),
          supabase.from('ordonnances').select('*').eq('animal_id', animalId).order('created_at', { ascending: false }),
        ]);
        if (!annule) setD({ crs: (cr.data ?? []) as Row[], ordos: (o.data ?? []) as Row[], seances: [] });
      }
    })();
    return () => { annule = true; };
  }, [animalId, pid, osteo]);
  if (!d) return <div className="flex justify-center py-10"><div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  const ligne = (cle: string, titre: string, sous: string, href?: string | null) => (
    <a key={cle} href={href ?? undefined} target={href?.startsWith('http') ? '_blank' : undefined} rel="noreferrer"
      className={`block py-2 border-t border-gray-50 first:border-0 ${href ? 'hover:bg-gray-50' : 'pointer-events-none'}`}>
      <p className="text-sm font-semibold">{titre}</p>
      {sous && <p className="text-xs text-gray-500 truncate">{sous}</p>}
    </a>
  );
  return osteo ? (
    <div className="space-y-4">
      <Carte titre="Comptes rendus de séance (PDF)">
        {d.seances.length === 0 ? <Discret t="Aucun compte rendu finalisé." />
          : d.seances.map(s => ligne(String(s.id), `${titreCompteRendu(String(s.type_suivi ?? ''))} — ${dateFr(s.date)}`, texte(s.motif), `/sante/suivis/${s.id}`))}
      </Carte>
      <p className="text-xs text-gray-400">Chaque compte rendu s&apos;exporte en PDF depuis son détail ; il reste rattaché à sa séance et à l&apos;animal.</p>
    </div>
  ) : (
    <div className="space-y-4">
      <Carte titre="Comptes rendus">
        {d.crs.length === 0 ? <Discret t="Aucun compte rendu." /> : d.crs.map(c => ligne(String(c.id), `Compte rendu — ${dateFr(c.created_at)}`, texte(c.contenu), (c.doc_url as string) || null))}
      </Carte>
      <Carte titre="Ordonnances">
        {d.ordos.length === 0 ? <Discret t="Aucune ordonnance." /> : d.ordos.map(o => ligne(String(o.id), `Ordonnance — ${dateFr(o.date_emit ?? o.created_at)}`, texte(o.notes), (o.doc_url as string) || null))}
      </Carte>
      <p className="text-xs text-gray-400">Résultats et pièces jointes : rattachés à leur consultation (onglet Consultations).</p>
    </div>
  );
}
