'use client';
// Accueil toiletteur : tableau de bord du salon (activité du jour). Données
// réelles et modules existants : rdv (étapes horodatées, migration
// toilettage_suivi), prestations_toilettage, employes. Miroir appli :
// lib/pages/pro/toilettage_salon_dashboard.dart. Scopé au profil actif.
import { useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { Kpi, Section, Badge, PhotoAnimal, EnteteAccueil, Tuile, Icone } from '@/components/dashboard/kit';
import SeanceToilettageModal from '@/components/toilettage/SeanceToilettageModal';
import DossierToilettageModal from '@/components/toilettage/DossierToilettageModal';

const TEAL = '#0C5C6C';
const VERT = '#2E7D5E';
const AMBRE = '#D97706';
const ROUGE = '#B3261E';
const VIOLET = '#7B5EA7';

interface Rdv {
  id: string; date_heure: string; duree_minutes: number | null; statut: string; motif: string | null;
  animal_id: string | null; client_uid: string | null; client_profile_id: string | null; client_nom_manuel: string | null;
  animal_nom_manuel: string | null; notes_client: string | null; employe_id: string | null; prestation_id: string | null;
  arrivee_validee_le?: string | null; prestation_debut_le?: string | null; pret_le?: string | null;
}
type Etape = 'aConfirmer' | 'attendu' | 'arrive' | 'enCours' | 'pret' | 'termine' | 'annule' | 'absent';
const etape = (r: Rdv): Etape => {
  if (r.statut === 'demande' || r.statut === 'contre_proposition') return 'aConfirmer';
  if (r.statut === 'annule' || r.statut === 'refuse') return 'annule';
  if (r.statut === 'absent') return 'absent';
  if (r.statut === 'termine') return 'termine';
  if (r.pret_le) return 'pret';
  if (r.prestation_debut_le) return 'enCours';
  if (r.arrivee_validee_le) return 'arrive';
  return 'attendu';
};
const STYLE: Record<Etape, { label: string; fg: string; bg: string }> = {
  aConfirmer: { label: 'À confirmer', fg: AMBRE, bg: '#FFF4DC' },
  attendu: { label: 'Confirmé', fg: '#1D4ED8', bg: '#E8F0FE' },
  arrive: { label: 'Animal arrivé', fg: VIOLET, bg: '#F1ECF8' },
  enCours: { label: 'En cours', fg: TEAL, bg: '#E6F2F3' },
  pret: { label: 'Prêt à récupérer', fg: VERT, bg: '#E7F3EC' },
  termine: { label: 'Terminé', fg: '#4B5563', bg: '#F1F2F4' },
  annule: { label: 'Annulé', fg: '#6B7280', bg: '#F3F4F6' },
  absent: { label: 'Non présenté', fg: ROUGE, bg: '#FDECEA' },
};
const debut = (r: Rdv) => new Date(r.date_heure);
const fin = (r: Rdv) => new Date(debut(r).getTime() + (r.duree_minutes ?? 60) * 60000);
const memeJour = (a: Date, b: Date) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
const hm = (d: Date) => d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
const jm = (d: Date) => d.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' });

export default function ToilettageDashboard({ nom, avatar }: { nom: string; avatar: string | null }) {
  const { user } = useAuth();
  const uid = user?.uid ?? '';
  const actifPid = useActiveProfile();
  const [pidPrincipal, setPidPrincipal] = useState('');
  const pid = actifPid || pidPrincipal;
  const [loading, setLoading] = useState(true);
  const [rdvs, setRdvs] = useState<Rdv[]>([]);
  const [demandes, setDemandes] = useState<Rdv[]>([]);
  const [employes, setEmployes] = useState<Record<string, string>>({});
  const [clients, setClients] = useState<Record<string, string>>({});
  const [animaux, setAnimaux] = useState<Record<string, { nom: string | null; photo_url: string | null }>>({});
  const [prestations, setPrestations] = useState<Record<string, string>>({});
  const [prixPresta, setPrixPresta] = useState<Record<string, number>>({});
  // RDV déjà facturés (factures.source_rdv_id, hors annulées).
  const [factures, setFactures] = useState<Set<string>>(new Set());
  const [fiche, setFiche] = useState<Rdv | null>(null);
  const [seanceRdv, setSeanceRdv] = useState<Rdv | null>(null);
  const [dossierId, setDossierId] = useState<string | null>(null);
  const [now, setNow] = useState(() => new Date());
  const planningRef = useRef<HTMLDivElement>(null);

  const charger = useCallback(async () => {
    if (!pid) return;
    const t = new Date();
    const jour = new Date(t.getFullYear(), t.getMonth(), t.getDate());
    const [r, d, e] = await Promise.all([
      supabase.from('rdv').select('*').eq('pro_profile_id', pid).in('statut', ['confirme', 'termine', 'absent'])
        .gte('date_heure', new Date(jour.getTime() - 7 * 86400000).toISOString())
        .lt('date_heure', new Date(jour.getTime() + 86400000).toISOString()).order('date_heure'),
      supabase.from('rdv').select('*').eq('pro_profile_id', pid).in('statut', ['demande', 'contre_proposition']).order('date_heure'),
      supabase.from('employes').select('id, prenom, nom').eq('eleveur_profile_id', pid).eq('actif', true),
    ]);
    const liste = (r.data ?? []) as Rdv[];
    const dem = (d.data ?? []) as Rdv[];
    const tous = [...liste, ...dem];
    const profils = [...new Set(tous.map(x => x.client_profile_id).filter(Boolean) as string[])];
    const ids = [...new Set(tous.map(x => x.animal_id).filter(Boolean) as string[])];
    const prs = [...new Set(tous.map(x => x.prestation_id).filter(Boolean) as string[])];
    const [pRes, aRes, prRes] = await Promise.all([
      profils.length ? supabase.from('user_profiles_complet').select('id, firstname, lastname, nom, profile_type').in('id', profils) : Promise.resolve({ data: [] }),
      ids.length ? supabase.from('animaux').select('id, nom, photo_url').in('id', ids) : Promise.resolve({ data: [] }),
      prs.length ? supabase.from('prestations_toilettage').select('id, nom, prix_base').in('id', prs) : Promise.resolve({ data: [] }),
    ]);
    const cl: Record<string, string> = {};
    for (const p of (pRes.data ?? []) as { id: string; firstname?: string; lastname?: string; nom?: string; profile_type?: string }[]) {
      const perso = `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim(); const st = (p.nom ?? '').trim();
      cl[p.id] = p.profile_type !== 'particulier' && st ? st : perso || st;
    }
    const an: Record<string, { nom: string | null; photo_url: string | null }> = {};
    for (const a of (aRes.data ?? []) as { id: string; nom: string | null; photo_url: string | null }[]) an[String(a.id)] = a;
    const pr: Record<string, string> = {};
    for (const p of (prRes.data ?? []) as { id: string; nom: string }[]) pr[p.id] = p.nom;
    const em: Record<string, string> = {};
    for (const x of (e.data ?? []) as { id: string; prenom: string | null; nom: string | null }[]) em[x.id] = `${x.prenom ?? ''} ${x.nom ?? ''}`.trim();
    setPrixPresta(Object.fromEntries(((prRes.data ?? []) as { id: string; prix_base?: number | null }[]).map(x => [x.id, Number(x.prix_base) || 0])));
    if (liste.length) {
      const { data: fa } = await supabase.from('factures').select('source_rdv_id, statut').in('source_rdv_id', liste.map(x => x.id));
      setFactures(new Set(((fa ?? []) as { source_rdv_id: string; statut: string }[]).filter(f => f.statut !== 'annulee').map(f => f.source_rdv_id)));
    }
    setRdvs(liste); setDemandes(dem); setEmployes(em); setClients(cl); setAnimaux(an); setPrestations(pr);
    setNow(new Date()); setLoading(false);
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

  const nomAnimal = (r: Rdv) => (r.animal_id && animaux[r.animal_id]?.nom) || r.animal_nom_manuel || 'Animal';
  const nomClient = (r: Rdv) => (r.client_profile_id && clients[r.client_profile_id]) || r.client_nom_manuel || 'Client';
  const prestation = (r: Rdv) => (r.prestation_id && prestations[r.prestation_id]) || r.motif?.trim() || 'Prestation';
  const employe = (r: Rdv) => (r.employe_id ? employes[r.employe_id] : undefined);
  const duJour = rdvs.filter(r => memeJour(debut(r), now)).sort((a, b) => debut(a).getTime() - debut(b).getTime());
  const enCours = duJour.filter(r => etape(r) === 'enCours').length;
  const prets = rdvs.filter(r => etape(r) === 'pret');
  const conflits = new Set<string>();
  const avecEmp = duJour.filter(r => r.employe_id && r.statut !== 'absent');
  for (let i = 0; i < avecEmp.length; i++) for (let j = i + 1; j < avecEmp.length; j++) {
    const a = avecEmp[i], b = avecEmp[j];
    if (a.employe_id === b.employe_id && debut(a) < fin(b) && debut(b) < fin(a)) { conflits.add(a.id); conflits.add(b.id); }
  }
  const retards = duJour.filter(r => etape(r) === 'attendu' && debut(r).getTime() + 15 * 60000 < now.getTime());
  const aFinaliser = rdvs.filter(r => !memeJour(debut(r), now) && ['attendu', 'arrive', 'enCours', 'pret'].includes(etape(r)));

  async function maj(r: Rdv, champs: Record<string, unknown>) {
    const { error } = await supabase.from('rdv').update(champs).eq('id', r.id);
    if (error) { alert(error.message.includes('column') ? 'Migration migration_toilettage_suivi.sql à passer.' : error.message); return; }
    setFiche(null); charger();
  }
  async function pret(r: Rdv) {
    // Prévenir le propriétaire : jamais automatique, choisi à chaque fois.
    const prevenir = window.confirm(`Prévenir le propriétaire que le toilettage de ${nomAnimal(r)} est terminé ?\n(Annuler = sans prévenir)`);
    await maj(r, { pret_le: new Date().toISOString() });
    if (prevenir && r.client_uid) {
      await supabase.from('notifications').insert({
        uid: r.client_uid, type: 'toilettage_pret', title: `${nomAnimal(r)} est prêt`,
        body: `Le toilettage de ${nomAnimal(r)} est terminé. Vous pouvez venir le récupérer.`,
        ...(r.client_profile_id ? { profile_id: r.client_profile_id } : {}),
        data: { rdv_id: r.id, ...(r.animal_id ? { animalId: r.animal_id } : {}) }, read: false,
      });
    }
  }

  const employesLignes = Object.entries(employes).map(([id, n]) => {
    const l = duJour.filter(r => r.employe_id === id && r.statut !== 'absent');
    const cours = l.find(r => etape(r) === 'enCours');
    const prochain = l.find(r => debut(r) > now);
    const libre = l.filter(r => fin(r) > now).map(fin).sort((a, b) => b.getTime() - a.getTime())[0];
    return { id, nom: n, n: l.length, cours, prochain, libre };
  }).sort((a, b) => b.n - a.n);

  const alertes = [
    ...(demandes.length ? [{ cle: 'dem', t: `${demandes.length} rendez-vous en attente de confirmation`, c: AMBRE, href: '/mes-rdv?onglet=demandes' }] : []),
    ...prets.map(r => ({ cle: `p${r.id}`, t: `${nomAnimal(r)} est prêt à récupérer`, c: VERT, r })),
    ...retards.map(r => ({ cle: `r${r.id}`, t: `${nomAnimal(r)} attendu à ${hm(debut(r))}, pas encore arrivé`, c: ROUGE, r })),
    ...(conflits.size ? [{ cle: 'conf', t: 'Conflit de planning : un employé a deux rendez-vous en même temps', c: ROUGE, href: '/mes-rdv?onglet=planning' }] : []),
    ...aFinaliser.map(r => ({ cle: `f${r.id}`, t: `Prestation du ${jm(debut(r))} à finaliser — ${nomAnimal(r)}`, c: AMBRE, r })),
  ];

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-6xl mx-auto px-4 py-5 space-y-5">
        <EnteteAccueil nom={nom} avatar={avatar} sousTitre="Salon de toilettage" avatarHref="/profil"
          actions={
            <span className="hidden sm:inline-flex items-center gap-2 text-sm text-[#1E2025] bg-white border border-[#E5E8E6] rounded-full px-3.5 py-2">
              <Icone nom="calendrier" taille={16} />
              <span className="first-letter:uppercase">{now.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}</span>
            </span>
          } />
        {loading && pid ? (
          <div className="flex justify-center py-20"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>
        ) : (
          <>
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
              <Kpi valeur={duJour.filter(r => r.statut !== 'absent').length} label="Rendez-vous aujourd'hui" icone="calendrier"
                onClick={() => planningRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })} />
              <Kpi valeur={enCours} label="Prestations en cours" icone="soin" teinte={TEAL}
                onClick={() => planningRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })} />
              <Kpi valeur={prets.length} label="Animaux prêts" icone="patte" teinte={VERT} actif={prets.length > 0}
                onClick={() => prets[0] && setFiche(prets[0])} />
              <Kpi valeur={demandes.length} label="Rendez-vous à confirmer" icone="enveloppe" teinte={AMBRE} actif={demandes.length > 0} href="/mes-rdv?onglet=demandes" />
            </div>
            <div className="grid lg:grid-cols-3 gap-5 items-start">
              <div ref={planningRef} className="lg:col-span-2 scroll-mt-4">
                <Section titre="Planning du jour" icone={<Icone nom="calendrier" taille={18} />} compteur={duJour.length}
                  action={<Link href="/mes-rdv?onglet=a_venir" className="text-sm font-semibold text-[#0C5C6C] hover:underline">Voir l&apos;agenda →</Link>}>
                  {duJour.length === 0 ? <p className="text-sm text-gray-400 text-center py-8">Aucun rendez-vous aujourd&apos;hui.</p> : (
                    <div className="space-y-2">
                      {duJour.map(r => {
                        const st = STYLE[etape(r)];
                        return (
                          <button key={r.id} type="button" onClick={() => setFiche(r)}
                            className="w-full text-left flex items-center gap-3 border border-[#EEF0EE] rounded-xl px-3 py-2.5 hover:bg-gray-50">
                            <div className="w-12 flex-shrink-0">
                              <p className="text-sm font-bold text-[#1E2025]">{hm(debut(r))}</p>
                              <p className="text-[11px] text-gray-500">{r.duree_minutes ?? 60} min</p>
                            </div>
                            <PhotoAnimal url={r.animal_id ? animaux[r.animal_id]?.photo_url : null} />
                            <div className="flex-1 min-w-0">
                              <p className="text-sm font-bold text-[#1E2025] truncate">{nomAnimal(r)}</p>
                              <p className="text-xs text-gray-500 truncate">{prestation(r)} · {nomClient(r)}</p>
                              {employe(r) && <p className="text-xs truncate" style={{ color: conflits.has(r.id) ? ROUGE : '#6B7280' }}>Toiletteur : {employe(r)}{conflits.has(r.id) ? ' · conflit de planning' : ''}</p>}
                              {r.notes_client?.trim() && <p className="text-xs truncate" style={{ color: AMBRE }}>{r.notes_client.trim()}</p>}
                            </div>
                            <Badge texte={st.label} fg={st.fg} bg={st.bg} />
                          </button>
                        );
                      })}
                    </div>
                  )}
                </Section>
              </div>
              <div className="space-y-5">
                {alertes.length > 0 && (
                  <Section titre="À traiter" icone={<Icone nom="cloche" taille={18} />} compteur={alertes.length}>
                    <div className="space-y-1">
                      {alertes.slice(0, 6).map(a => 'href' in a && a.href ? (
                        <Link key={a.cle} href={a.href} className="flex items-center gap-2 py-1.5 text-sm text-[#1E2025]">
                          <span style={{ color: a.c }}>●</span><span className="flex-1">{a.t}</span>
                        </Link>
                      ) : (
                        <button key={a.cle} onClick={() => 'r' in a && a.r && setFiche(a.r)} className="w-full text-left flex items-center gap-2 py-1.5 text-sm text-[#1E2025]">
                          <span style={{ color: a.c }}>●</span><span className="flex-1">{a.t}</span>
                        </button>
                      ))}
                    </div>
                  </Section>
                )}
                {employesLignes.length > 0 && (
                  <Section titre="Équipe du jour" icone={<Icone nom="equipe" taille={18} />} compteur={employesLignes.filter(e => e.n > 0).length}
                    action={<Link href="/mes-rdv?onglet=planning" className="text-sm font-semibold text-[#0C5C6C] hover:underline">Planning équipe →</Link>}>
                    <div className="space-y-2">
                      {employesLignes.map(e => (
                        <div key={e.id} className="flex items-center gap-2.5">
                          <span className="w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold" style={{ background: `${TEAL}18`, color: TEAL }}>{(e.nom[0] ?? '?').toUpperCase()}</span>
                          <span className="flex-1 min-w-0">
                            <span className="block text-sm font-bold text-[#1E2025] truncate">{e.nom}</span>
                            <span className="block text-xs text-gray-500 truncate">
                              {e.n === 0 ? 'Aucun rendez-vous attribué' : [`${e.n} rendez-vous`, e.cours ? `en cours : ${nomAnimal(e.cours)}` : e.prochain ? `prochain à ${hm(debut(e.prochain))}` : '', e.libre ? `libre à ${hm(e.libre)}` : ''].filter(Boolean).join(' · ')}
                            </span>
                          </span>
                        </div>
                      ))}
                    </div>
                  </Section>
                )}
              </div>
            </div>
            <Section titre="Accès rapides" icone={<Icone nom="eclair" taille={18} />}
              action={<Link href="/toilettage/dashboard" className="text-sm font-semibold text-[#0C5C6C] hover:underline">Statistiques →</Link>}>
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                <Tuile href="/mes-rdv?onglet=a_venir" icone="plus" label="Nouveau rendez-vous" />
                <Tuile href="/mes-patients" icone="patte" label="Fiches animaux" teinte={VERT} />
                <Tuile href="/mes-rdv?onglet=planning" icone="calendrier" label="Planning équipe" />
                <Tuile href="/elevage/facturation" icone="facture" label="Facturation" />
              </div>
            </Section>
          </>
        )}
      </div>

      {fiche && (() => {
        const e = etape(fiche);
        const st = STYLE[e];
        const passe = fin(fiche) < now;
        const bouton = (t: string, f: () => void, c = TEAL) => (
          <button onClick={f} className="block w-full text-left py-2 text-sm font-semibold" style={{ color: c }}>{t}</button>
        );
        const iso = () => new Date().toISOString();
        return (
          <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={() => setFiche(null)}>
            <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-md p-5" onClick={ev => ev.stopPropagation()}>
              <div className="flex items-center gap-3">
                <PhotoAnimal url={fiche.animal_id ? animaux[fiche.animal_id]?.photo_url : null} taille={44} />
                <div className="flex-1 min-w-0">
                  <p className="font-bold text-[#1E2025]">{nomAnimal(fiche)}</p>
                  <p className="text-sm text-gray-500">{nomClient(fiche)} · {hm(debut(fiche))} · {fiche.duree_minutes ?? 60} min</p>
                </div>
                <Badge texte={st.label} fg={st.fg} bg={st.bg} />
              </div>
              <p className="text-sm font-semibold text-[#1E2025] mt-3">{prestation(fiche)}</p>
              {employe(fiche) && <p className="text-sm text-gray-500">Toiletteur : {employe(fiche)}</p>}
              {fiche.notes_client?.trim() && <p className="text-sm mt-1">Consignes : {fiche.notes_client.trim()}</p>}
              <div className="mt-3">
                {e === 'attendu' && bouton('Animal arrivé', () => maj(fiche, { arrivee_validee_le: iso() }))}
                {e === 'attendu' && passe && bouton('Non présenté', () => maj(fiche, { statut: 'absent' }), ROUGE)}
                {e === 'arrive' && bouton('Démarrer le toilettage', () => maj(fiche, { prestation_debut_le: iso() }))}
                {e === 'enCours' && bouton('Toilettage terminé — animal prêt', () => pret(fiche), VERT)}
                {e === 'pret' && bouton('Animal récupéré — clôturer', () => maj(fiche, { statut: 'termine', termine_at: iso() }))}
                {(e === 'pret' || e === 'termine') && !factures.has(fiche.id) && bouton('Facturer la prestation', () => {
                  // Facture pré-remplie (module existant) ; terminé ≠ payé.
                  const prix = (fiche as Rdv & { prix_calcule?: number | null }).prix_calcule ?? (fiche.prestation_id ? prixPresta[fiche.prestation_id] : 0) ?? 0;
                  try {
                    sessionStorage.setItem('pm_facture_prefill', JSON.stringify({
                      nomClient: nomClient(fiche), sourceRdvId: fiche.id, sourceAnimalId: fiche.animal_id ?? undefined,
                      clientUid: fiche.client_uid ?? undefined, clientProfileId: fiche.client_profile_id ?? undefined,
                      // Prix TTC affiché : le HT est déduit selon le régime de TVA du pro.
                      lignes: [{ description: `${prestation(fiche)} — ${nomAnimal(fiche)}`, quantite: 1, prixUnitaire: 0, prixTTC: Number(prix) || 0, tva: 20 }],
                    }));
                  } catch { /* facture vierge */ }
                  window.location.href = '/elevage/facturation';
                })}
                {factures.has(fiche.id) && <Link href="/elevage/facturation" className="block py-2 text-sm font-semibold text-[#0C5C6C]">Prestation facturée — voir la facturation</Link>}
                {bouton('Dossier de la séance (compte rendu, contrat, facture)', () => { setDossierId(fiche.id); setFiche(null); })}
                {fiche.animal_id && ['enCours', 'pret', 'termine'].includes(e) && bouton('Fiche technique de la prestation', () => { setSeanceRdv(fiche); setFiche(null); })}
                {fiche.animal_id && <Link href={`/mes-patients/${fiche.animal_id}`} className="block py-2 text-sm font-semibold text-[#0C5C6C]">Fiche animal et consignes</Link>}
                <Link href={`/mes-rdv?onglet=a_venir&rdv=${fiche.id}`} className="block py-2 text-sm font-semibold text-[#0C5C6C]">Voir le rendez-vous dans l&apos;agenda</Link>
              </div>
              <button onClick={() => setFiche(null)} className="w-full mt-3 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Fermer</button>
            </div>
          </div>
        );
      })()}
      {dossierId && (() => {
        const d = rdvs.find(x => x.id === dossierId);
        return d ? <DossierToilettageModal rdvId={d.id} nomClient={nomClient(d)} animal={nomAnimal(d)} onClose={() => setDossierId(null)} onChanged={charger} /> : null;
      })()}
      {seanceRdv?.animal_id && uid && pid && (
        <SeanceToilettageModal animalId={seanceRdv.animal_id} animalNom={nomAnimal(seanceRdv)} proUid={uid} profileId={pid}
          rdv={seanceRdv} prestation={prestation(seanceRdv)} onClose={() => setSeanceRdv(null)} onSaved={charger} />
      )}
    </div>
  );
}
