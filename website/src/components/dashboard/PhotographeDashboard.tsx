'use client';
// Accueil photographe : tableau de bord du studio. Données réelles et modules
// existants : rdv (séances), prestations_photographe, albums_photo (+ statut,
// migration_photographe_galeries_statut.sql), devis, contrats
// (documents_animaux type contrat_prestation_photo). Statistiques (CA, avis)
// sur /photographe/dashboard. Miroir appli :
// lib/pages/pro/photographe_studio_dashboard.dart. Scopé au profil actif.
import { useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { Kpi, Section, Badge, EnteteAccueil, Tuile, Icone } from '@/components/dashboard/kit';
import { styleGalerie, GALERIES_A_LIVRER } from '@/lib/photographe';

const AMBRE = '#D97706';
const VERT = '#2E7D5E';
const VIOLET = '#7B5EA7';

interface Rdv {
  id: string; date_heure: string; duree_minutes: number | null; statut: string; motif: string | null; lieu: string | null;
  animal_id: string | null; animal_nom_manuel: string | null; client_uid: string | null; client_profile_id: string | null;
  client_nom_manuel: string | null; prestation_id: string | null; notes_client: string | null;
}
interface Galerie {
  id: string; titre: string | null; rdv_id: string | null; client_profile_id: string | null; statut?: string | null;
  date_seance?: string | null; updated_at?: string | null; created_at: string;
}
interface Devis { id: string; numero_devis: string | null; date_devis: string; total_ttc: number | null; client_profile_id: string | null; nom_client: string | null; prenom_client: string | null }

const jour = (d: Date) => d.toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' });
const hm = (d: Date) => d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });

export default function PhotographeDashboard({ nom, avatar }: { nom: string; avatar: string | null }) {
  const { user } = useAuth();
  const uid = user?.uid ?? '';
  const actifPid = useActiveProfile();
  const [pidPrincipal, setPidPrincipal] = useState('');
  const pid = actifPid || pidPrincipal;
  const [loading, setLoading] = useState(true);
  const [now, setNow] = useState(0);
  const [seances, setSeances] = useState<Rdv[]>([]);
  const [passees, setPassees] = useState<Rdv[]>([]);
  const [demandes, setDemandes] = useState<Rdv[]>([]);
  const [galeries, setGaleries] = useState<Galerie[]>([]);
  const [statutDispo, setStatutDispo] = useState(true);
  const [devis, setDevis] = useState<Devis[]>([]);
  const [contrats, setContrats] = useState<{ id: string; rdv_id: string | null }[]>([]);
  const [nbPhotos, setNbPhotos] = useState<Record<string, number>>({});
  // Dossier de chaque séance : devis (rdv_id), contrats, factures (source_rdv_id).
  const [devisSeances, setDevisSeances] = useState<{ rdv_id: string; statut: string; total_ttc: number | null }[]>([]);
  const [contratsSeances, setContratsSeances] = useState<{ rdv_id: string; statut: string }[]>([]);
  const [facturesSeances, setFacturesSeances] = useState<{ source_rdv_id: string; statut: string; total_ttc: number | null }[]>([]);
  const [prix, setPrix] = useState<Record<string, number>>({});
  const router = useRouter();
  const [clients, setClients] = useState<Record<string, string>>({});
  const [animaux, setAnimaux] = useState<Record<string, string>>({});
  const [prestations, setPrestations] = useState<Record<string, string>>({});
  const [fiche, setFiche] = useState<Rdv | null>(null);
  const galeriesRef = useRef<HTMLDivElement>(null);

  const charger = useCallback(async () => {
    if (!pid) return;
    const t = Date.now();
    const iso = (ms: number) => new Date(ms).toISOString();
    const [s, p, d, dv, ct] = await Promise.all([
      supabase.from('rdv').select('*').eq('pro_profile_id', pid).eq('statut', 'confirme')
        .gte('date_heure', iso(t - 6 * 3600000)).lt('date_heure', iso(t + 30 * 86400000)).order('date_heure').limit(40),
      supabase.from('rdv').select('*').eq('pro_profile_id', pid).in('statut', ['confirme', 'termine'])
        .gte('date_heure', iso(t - 60 * 86400000)).lt('date_heure', iso(t)).order('date_heure', { ascending: false }),
      supabase.from('rdv').select('*').eq('pro_profile_id', pid).in('statut', ['demande', 'contre_proposition']).order('date_heure'),
      supabase.from('devis').select('id, numero_devis, date_devis, total_ttc, client_profile_id, nom_client, prenom_client')
        .eq('pro_profile_id', pid).eq('statut', 'envoye').order('date_devis', { ascending: false }),
      supabase.from('documents_animaux').select('id, rdv_id').eq('pro_profile_id', pid).eq('type', 'contrat_prestation_photo').eq('statut', 'en_attente'),
    ]);
    let g = await supabase.from('albums_photo').select('*').eq('pro_profile_id', pid).order('updated_at', { ascending: false }).limit(60);
    let dispo = true;
    if (g.error) {
      // Migration des statuts pas encore passée.
      dispo = false;
      g = await supabase.from('albums_photo').select('*').eq('pro_profile_id', pid).order('created_at', { ascending: false }).limit(60);
    }
    const gal = (g.data ?? []) as Galerie[];
    const tous = [...((s.data ?? []) as Rdv[]), ...((p.data ?? []) as Rdv[]), ...((d.data ?? []) as Rdv[])];
    const profils = [...new Set([...tous.map(x => x.client_profile_id), ...gal.map(x => x.client_profile_id), ...((dv.data ?? []) as Devis[]).map(x => x.client_profile_id)].filter(Boolean) as string[])];
    const ids = [...new Set(tous.map(x => x.animal_id).filter(Boolean) as string[])];
    const prs = [...new Set(tous.map(x => x.prestation_id).filter(Boolean) as string[])];
    const [pRes, aRes, prRes, phRes] = await Promise.all([
      profils.length ? supabase.from('user_profiles_complet').select('id, firstname, lastname, nom, profile_type').in('id', profils) : Promise.resolve({ data: [] }),
      ids.length ? supabase.from('animaux').select('id, nom').in('id', ids) : Promise.resolve({ data: [] }),
      prs.length ? supabase.from('prestations_photographe').select('id, nom, prix').in('id', prs) : Promise.resolve({ data: [] }),
      gal.length ? supabase.from('album_photos').select('album_id').in('album_id', gal.map(x => x.id)) : Promise.resolve({ data: [] }),
    ]);
    const cl: Record<string, string> = {};
    for (const x of (pRes.data ?? []) as { id: string; firstname?: string; lastname?: string; nom?: string; profile_type?: string }[]) {
      const perso = `${x.firstname ?? ''} ${x.lastname ?? ''}`.trim(); const st = (x.nom ?? '').trim();
      cl[x.id] = x.profile_type !== 'particulier' && st ? st : perso || st;
    }
    const rdvIds = [...new Set([...((s.data ?? []) as Rdv[]), ...((p.data ?? []) as Rdv[])].map(x => x.id))];
    if (rdvIds.length) {
      const [dv2, ct2, fa2] = await Promise.all([
        supabase.from('devis').select('rdv_id, statut, total_ttc').in('rdv_id', rdvIds),
        supabase.from('documents_animaux').select('rdv_id, statut').eq('type', 'contrat_prestation_photo').in('rdv_id', rdvIds),
        supabase.from('factures').select('source_rdv_id, statut, total_ttc').in('source_rdv_id', rdvIds),
      ]);
      setDevisSeances(dv2.error ? [] : (dv2.data ?? []) as typeof devisSeances);
      setContratsSeances((ct2.data ?? []) as typeof contratsSeances);
      setFacturesSeances((fa2.data ?? []) as typeof facturesSeances);
    }
    setPrix(Object.fromEntries(((prRes.data ?? []) as { id: string; prix?: number | null }[]).map(x => [x.id, Number(x.prix) || 0])));
    const nb: Record<string, number> = {};
    for (const x of (phRes.data ?? []) as { album_id: string }[]) nb[x.album_id] = (nb[x.album_id] ?? 0) + 1;
    setSeances((s.data ?? []) as Rdv[]); setPassees((p.data ?? []) as Rdv[]); setDemandes((d.data ?? []) as Rdv[]);
    setDevis((dv.data ?? []) as Devis[]); setContrats((ct.data ?? []) as { id: string; rdv_id: string | null }[]);
    setGaleries(gal); setStatutDispo(dispo); setNbPhotos(nb); setClients(cl);
    setAnimaux(Object.fromEntries(((aRes.data ?? []) as { id: string; nom: string }[]).map(x => [String(x.id), x.nom])));
    setPrestations(Object.fromEntries(((prRes.data ?? []) as { id: string; nom: string }[]).map(x => [x.id, x.nom])));
    setNow(t); setLoading(false);
  }, [pid]);

  useEffect(() => {
    if (!uid || actifPid) return;
    supabase.from('user_profiles_complet').select('id').eq('uid', uid).eq('is_main', true).maybeSingle()
      .then(({ data }) => setPidPrincipal((data as { id: string } | null)?.id ?? ''));
  }, [uid, actifPid]);
  useEffect(() => {
    if (!pid) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    charger();
  }, [pid, charger]);

  const nomClient = (r: { client_profile_id: string | null; client_nom_manuel?: string | null; nom_client?: string | null; prenom_client?: string | null }) =>
    (r.client_profile_id && clients[r.client_profile_id]) || r.client_nom_manuel || `${r.prenom_client ?? ''} ${r.nom_client ?? ''}`.trim() || 'Client';
  const prestation = (r: Rdv) => (r.prestation_id && prestations[r.prestation_id]) || r.motif?.trim() || 'Séance photo';
  const animal = (r: Rdv) => (r.animal_id && animaux[r.animal_id]) || r.animal_nom_manuel || null;
  const statut = (g: Galerie) => (statutDispo ? g.statut ?? 'brouillon' : 'brouillon');
  const galerieDe = (r: Rdv) => galeries.find(g => g.rdv_id === r.id);
  const contratAttente = (r: Rdv) => contrats.some(c => c.rdv_id === r.id);
  const depuis = (iso?: string | null) => {
    if (!iso) return '';
    const j = Math.floor((now - new Date(iso).getTime()) / 86400000);
    return j <= 0 ? "aujourd'hui" : j === 1 ? 'hier' : `il y a ${j} jours`;
  };

  const semaine = seances.filter(r => new Date(r.date_heure).getTime() < now + 7 * 86400000).length;
  const aLivrer = galeries.filter(g => GALERIES_A_LIVRER.has(statut(g)));
  const selections = galeries.filter(g => statut(g) === 'selection_recue');
  const enCours = galeries.filter(g => !['livree', 'archivee'].includes(statut(g)));
  const galVues = (enCours.length ? enCours : galeries.filter(g => statut(g) !== 'archivee')).slice(0, 8);
  const sansGalerie = passees.filter(r => !galerieDe(r));
  const versGaleries = () => galeriesRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });

  const alertes: { cle: string; t: string; c: string; href?: string; r?: Rdv }[] = [
    ...(demandes.length ? [{ cle: 'dem', t: `${demandes.length} demande${demandes.length > 1 ? 's' : ''} de séance à confirmer`, c: AMBRE, href: '/mes-rdv?onglet=demandes' }] : []),
    ...selections.map(g => ({ cle: `s${g.id}`, t: `Sélection reçue — ${g.titre ?? 'galerie'}`, c: VERT })),
    ...sansGalerie.slice(0, 4).map(r => ({ cle: `g${r.id}`, t: `Galerie à créer — séance du ${jour(new Date(r.date_heure))}, ${nomClient(r)}`, c: VIOLET, r })),
    ...(contrats.length ? [{ cle: 'ct', t: `${contrats.length} contrat${contrats.length > 1 ? 's' : ''} en attente de signature`, c: AMBRE, href: '/photographe/contrat' }] : []),
  ];

  const seancesBloc = (
    <Section titre="Prochaines séances" icone={<Icone nom="calendrier" taille={18} />} compteur={seances.length}
      action={<Link href="/mes-rdv?onglet=a_venir" className="text-sm font-semibold text-[#0C5C6C] hover:underline">Voir l&apos;agenda →</Link>}>
      {seances.length === 0 ? <p className="text-sm text-gray-400 text-center py-8">Aucune séance programmée dans les 30 prochains jours.</p> : (
        <div className="space-y-2">
          {seances.slice(0, 8).map(r => {
            const d = new Date(r.date_heure);
            return (
              <button key={r.id} type="button" onClick={() => setFiche(r)}
                className="w-full text-left flex items-center gap-3 border border-[#EEF0EE] rounded-xl px-3 py-2.5 hover:bg-gray-50">
                <div className="w-20 flex-shrink-0">
                  <p className="text-sm font-bold text-[#1E2025]">{jour(d)}</p>
                  <p className="text-[11px] text-gray-500">{hm(d)} · {r.duree_minutes ?? 60} min</p>
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-bold text-[#1E2025] truncate">{prestation(r)}</p>
                  <p className="text-xs text-gray-500 truncate">{[nomClient(r), animal(r)].filter(Boolean).join(' · ')}</p>
                  {r.lieu?.trim() && <p className="text-xs text-gray-500 truncate">{r.lieu.trim()}</p>}
                </div>
                {contratAttente(r) ? <Badge texte="Contrat à signer" fg={AMBRE} bg="#FFF4DC" /> : <Badge texte="Confirmée" fg="#1D4ED8" bg="#E8F0FE" />}
              </button>
            );
          })}
        </div>
      )}
    </Section>
  );

  const galeriesBloc = (
    <div ref={galeriesRef} className="scroll-mt-4">
      <Section titre="Galeries en cours" icone={<Icone nom="image" taille={18} />} compteur={enCours.length}>
        {!statutDispo && <p className="text-xs mb-2" style={{ color: AMBRE }}>Migration migration_photographe_galeries_statut.sql à passer pour suivre les statuts.</p>}
        {galVues.length === 0 ? <p className="text-sm text-gray-400 text-center py-8">Aucune galerie. Créez-la depuis une séance ou depuis Mes galeries.</p> : (
          <div className="space-y-2">
            {galVues.map(g => {
              const st = styleGalerie(statut(g));
              const n = nbPhotos[g.id] ?? 0;
              return (
                <Link key={g.id} href={`/photographe/galeries/${g.id}`} className="flex items-center gap-3 border border-[#EEF0EE] rounded-xl px-3 py-2.5 hover:bg-gray-50">
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-bold text-[#1E2025] truncate">{g.titre ?? 'Galerie'}</p>
                    <p className="text-xs text-gray-500 truncate">
                      {[nomClient(g), g.date_seance ? `séance du ${jour(new Date(g.date_seance))}` : '', `${n} photo${n > 1 ? 's' : ''}`].filter(Boolean).join(' · ')}
                    </p>
                    <p className="text-[11px] text-gray-400">Dernière activité : {depuis(g.updated_at ?? g.created_at)}</p>
                  </div>
                  <Badge texte={st.label} fg={st.fg} bg={st.bg} />
                </Link>
              );
            })}
          </div>
        )}
      </Section>
    </div>
  );

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-6xl mx-auto px-4 py-5 space-y-5">
        <EnteteAccueil nom={nom} avatar={avatar} sousTitre="Studio photo" avatarHref="/profil"
          actions={now ? (
            <span className="hidden sm:inline-flex items-center gap-2 text-sm text-[#1E2025] bg-white border border-[#E5E8E6] rounded-full px-3.5 py-2">
              <Icone nom="calendrier" taille={16} />
              <span className="first-letter:uppercase">{new Date(now).toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}</span>
            </span>
          ) : null} />
        {loading && pid ? (
          <div className="flex justify-center py-20"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>
        ) : (
          <>
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
              <Kpi valeur={semaine} label="Séances à venir (7 jours)" icone="calendrier" href="/mes-rdv?onglet=a_venir" />
              <Kpi valeur={aLivrer.length} label="Galeries à livrer" icone="image" teinte={VIOLET} actif={aLivrer.length > 0} onClick={versGaleries} />
              <Kpi valeur={devis.length} label="Devis en attente" icone="facture" teinte={AMBRE} actif={devis.length > 0} href="/photographe/devis" />
              <Kpi valeur={selections.length} label="Sélections à traiter" icone="coeur" teinte={VERT} actif={selections.length > 0} onClick={versGaleries} />
            </div>
            <div className="grid lg:grid-cols-3 gap-5 items-start">
              <div className="lg:col-span-2 space-y-5">
                {seancesBloc}
                {galeriesBloc}
              </div>
              <div className="space-y-5">
                {alertes.length > 0 && (
                  <Section titre="À traiter" icone={<Icone nom="cloche" taille={18} />} compteur={alertes.length}>
                    <div className="space-y-1">
                      {alertes.slice(0, 7).map(a => a.href ? (
                        <Link key={a.cle} href={a.href} className="flex items-center gap-2 py-1.5 text-sm text-[#1E2025]">
                          <span style={{ color: a.c }}>●</span><span className="flex-1">{a.t}</span>
                        </Link>
                      ) : (
                        <button key={a.cle} onClick={() => (a.r ? setFiche(a.r) : versGaleries())} className="w-full text-left flex items-center gap-2 py-1.5 text-sm text-[#1E2025]">
                          <span style={{ color: a.c }}>●</span><span className="flex-1">{a.t}</span>
                        </button>
                      ))}
                    </div>
                  </Section>
                )}
                {devis.length > 0 && (
                  <Section titre="Devis en attente" icone={<Icone nom="facture" taille={18} />} compteur={devis.length}
                    action={<Link href="/photographe/devis" className="text-sm font-semibold text-[#0C5C6C] hover:underline">Tous les devis →</Link>}>
                    <div className="space-y-2">
                      {devis.slice(0, 5).map(d => (
                        <Link key={d.id} href="/photographe/devis" className="flex items-center gap-2">
                          <span className="flex-1 min-w-0">
                            <span className="block text-sm font-semibold text-[#1E2025] truncate">{nomClient(d)}</span>
                            <span className="block text-xs text-gray-500">{d.numero_devis ?? 'Devis'} · envoyé {depuis(d.date_devis)}</span>
                          </span>
                          <span className="text-sm font-bold text-[#1E2025]">{Math.round(Number(d.total_ttc) || 0)} €</span>
                        </Link>
                      ))}
                    </div>
                  </Section>
                )}
              </div>
            </div>
            <Section titre="Accès rapides" icone={<Icone nom="eclair" taille={18} />}
              action={<Link href="/photographe/dashboard" className="text-sm font-semibold text-[#0C5C6C] hover:underline">Statistiques →</Link>}>
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                <Tuile href="/mes-rdv?onglet=a_venir" icone="plus" label="Nouvelle séance" />
                <Tuile href="/photographe/galeries" icone="image" label="Mes galeries" teinte={VIOLET} />
                <Tuile href="/photographe/devis" icone="facture" label="Créer un devis" />
                <Tuile href="/elevage/facturation" icone="facture" label="Facturation" />
              </div>
            </Section>
          </>
        )}
      </div>

      {fiche && (() => {
        const d = new Date(fiche.date_heure);
        const lieu = fiche.lieu?.trim();
        const lien = (href: string, t: string, externe = false) => (
          <a href={href} {...(externe ? { target: '_blank', rel: 'noopener noreferrer' } : {})} className="block py-2 text-sm font-semibold text-[#0C5C6C]">{t}</a>
        );
        return (
          <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={() => setFiche(null)}>
            <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-md p-5" onClick={ev => ev.stopPropagation()}>
              <p className="font-bold text-[#1E2025]">{prestation(fiche)}</p>
              <p className="text-sm text-gray-500">{nomClient(fiche)} · {jour(d)} à {hm(d)} · {fiche.duree_minutes ?? 60} min</p>
              {lieu && <p className="text-sm mt-1">Lieu : {lieu}</p>}
              {animal(fiche) && <p className="text-sm">Animal : {animal(fiche)}</p>}
              {fiche.notes_client?.trim() && <p className="text-sm" style={{ color: AMBRE }}>Demande : {fiche.notes_client.trim()}</p>}
              {contratAttente(fiche) && <p className="text-sm" style={{ color: AMBRE }}>Contrat en attente de signature</p>}
              <div className="mt-3 border border-gray-100 rounded-xl px-3 py-1.5">
                {(() => {
                  const dv = devisSeances.find(x => x.rdv_id === fiche.id);
                  const ct = contratsSeances.find(x => x.rdv_id === fiche.id);
                  const fa = facturesSeances.find(x => x.source_rdv_id === fiche.id && x.statut !== 'annulee');
                  const gal = galerieDe(fiche);
                  const eur = (n: number | null) => `${Math.round(Number(n) || 0)} €`;
                  const VERT_ = '#2E7D5E', GRIS = '#6B7280';
                  const nouveauDevis = () => {
                    const q = new URLSearchParams({ prefill: '1', rdv: fiche.id, nom: nomClient(fiche),
                      ...(fiche.client_uid ? { clientUid: fiche.client_uid } : {}), ...(fiche.client_profile_id ? { clientProfileId: fiche.client_profile_id } : {}),
                      ...(fiche.animal_id ? { animal: fiche.animal_id } : {}),
                      ...(fiche.prestation_id ? { ligneDesc: prestation(fiche), lignePrix: String(prix[fiche.prestation_id] ?? 0) } : {}) });
                    router.push(`/photographe/devis?${q.toString()}`);
                  };
                  const facturer = () => {
                    try {
                      sessionStorage.setItem('pm_facture_prefill', JSON.stringify({
                        nomClient: nomClient(fiche), sourceRdvId: fiche.id, sourceAnimalId: fiche.animal_id ?? undefined,
                        clientUid: fiche.client_uid ?? undefined, clientProfileId: fiche.client_profile_id ?? undefined,
                        lignes: [{ description: `${prestation(fiche)} — séance du ${jour(new Date(fiche.date_heure))}`, quantite: 1,
                          prixUnitaire: fiche.prestation_id ? prix[fiche.prestation_id] ?? 0 : 0, tva: 20 }],
                      }));
                    } catch { /* stockage indisponible : facture vierge */ }
                    router.push('/elevage/facturation');
                  };
                  const lignes: [string, string, string, string, () => void][] = [
                    ['Devis', dv ? (dv.statut === 'accepte' ? `Accepté · ${eur(dv.total_ttc)}` : dv.statut === 'envoye' ? `Envoyé, en attente · ${eur(dv.total_ttc)}` : dv.statut === 'refuse' ? 'Refusé' : `Brouillon · ${eur(dv.total_ttc)}`) : 'Aucun',
                      dv ? (dv.statut === 'accepte' ? VERT_ : dv.statut === 'envoye' ? AMBRE : GRIS) : GRIS, dv ? 'Voir' : 'Créer', dv ? () => router.push('/photographe/devis') : nouveauDevis],
                    ['Contrat', ct ? (ct.statut === 'signe' ? 'Signé' : ct.statut === 'partiellement_signe' ? 'Signé par une partie' : ct.statut === 'refuse' ? 'Refusé' : 'En attente de signature') : 'Non généré',
                      ct?.statut === 'signe' ? VERT_ : ct ? AMBRE : GRIS, 'Voir', () => router.push('/photographe/contrat')],
                    ['Galerie', gal ? styleGalerie(statut(gal)).label : 'Pas encore créée', gal ? styleGalerie(statut(gal)).fg : GRIS,
                      gal ? 'Ouvrir' : 'Créer', () => router.push(gal ? `/photographe/galeries/${gal.id}` : '/photographe/galeries')],
                    ['Facture', fa ? (fa.statut === 'payee' ? `Payée · ${eur(fa.total_ttc)}` : `Émise, non payée · ${eur(fa.total_ttc)}`) : 'Non facturée',
                      fa?.statut === 'payee' ? VERT_ : fa ? AMBRE : GRIS, fa ? 'Voir' : 'Facturer', fa ? () => router.push('/elevage/facturation') : facturer],
                  ];
                  return lignes.map(([t, etat, c, act, f]) => (
                    <div key={t} className="flex items-center gap-2 py-1">
                      <span className="w-16 text-sm font-bold text-[#1E2025]">{t}</span>
                      <span className="flex-1 text-sm" style={{ color: c }}>{etat}</span>
                      <button onClick={f} className="text-sm font-semibold text-[#0C5C6C]">{act}</button>
                    </div>
                  ));
                })()}
              </div>
              <div className="mt-2">
                {fiche.client_uid && lien(`/messages?uid=${fiche.client_uid}`, 'Contacter le client')}
                {lieu && lien(`https://www.google.com/maps/dir/?api=1&destination=${encodeURIComponent(lieu)}`, "Itinéraire jusqu'au lieu", true)}
                {lien(`/mes-rdv?onglet=a_venir&rdv=${fiche.id}`, "Voir la séance dans l'agenda")}
              </div>
              <button onClick={() => setFiche(null)} className="w-full mt-3 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Fermer</button>
            </div>
          </div>
        );
      })()}
    </div>
  );
}
