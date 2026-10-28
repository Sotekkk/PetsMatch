'use client';
// Accueil éducateur / comportementaliste : tableau de bord de l'activité.
// Données réelles et modules EXISTANTS uniquement : agenda (rdv), cours
// collectifs, objectifs (education_objectifs), comptes rendus de séance
// (education_progression), forfaits souscrits. Miroir appli :
// lib/pages/pro/education_dashboard.dart. Scopé au profil actif (pro_profile_id).
import { useActualisationAuto } from '@/hooks/useActualisationAuto';
import { useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import ItineraireMenu from '@/components/dashboard/ItineraireMenu';
import { Kpi, Section, Badge, PhotoAnimal, EnteteAccueil, Tuile, Icone } from '@/components/dashboard/kit';

const TEAL = '#0C5C6C';
const VERT = '#2E7D5E';
const AMBRE = '#D97706';
const VIOLET = '#7B5EA7';

const STATUT_OBJ: Record<string, string> = {
  a_travailler: 'À travailler', en_cours: 'En cours', en_progression: 'En progression',
  acquis: 'Acquis selon évaluation', a_reevaluer: 'À réévaluer',
};

interface Rdv {
  id: string; date_heure: string; duree_minutes: number | null; statut: string; motif: string | null;
  animal_id: string | null; client_profile_id: string | null; client_nom_manuel: string | null;
  animal_nom_manuel: string | null; lieu: string | null; lieu_lat: number | null; lieu_lng: number | null;
}
interface Cours { id: string; titre: string | null; date_heure: string; lieu: string | null; pro_profile_id: string | null }
interface Objectif { id: string; animal_id: string; libelle: string; statut: string; prioritaire?: boolean | null; pro_profile_id: string | null }
interface Seance { id: string; animal_id: string; date_seance: string; statut?: string | null; rdv_id?: string | null; pro_profile_id?: string | null }
interface Animal { id: string; nom: string | null; photo_url: string | null }

const debut = (r: { date_heure: string }) => new Date(r.date_heure);
const memeJour = (a: Date, b: Date) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
const hm = (d: Date) => d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
const jm = (d: Date) => d.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' });
const domicile = (r: Rdv) => !!r.lieu?.trim() || r.lieu_lat != null;

export default function EducationDashboard({ nom, avatar }: { nom: string; avatar: string | null }) {
  const { user } = useAuth();
  const uid = user?.uid ?? '';
  const actifPid = useActiveProfile();
  const [pidPrincipal, setPidPrincipal] = useState('');
  const pid = actifPid || pidPrincipal;
  const [loading, setLoading] = useState(true);
  const [rdvs, setRdvs] = useState<Rdv[]>([]);
  const [cours, setCours] = useState<Cours[]>([]);
  const [objectifs, setObjectifs] = useState<Objectif[]>([]);
  const [seances, setSeances] = useState<Seance[]>([]);
  const [forfaitsAnimaux, setForfaitsAnimaux] = useState<string[]>([]);
  // Animaux de « Mes animaux suivis » : accès accordés à ce profil + animaux vus en RDV avec lui.
  const [nbAnimauxSuivis, setNbAnimauxSuivis] = useState(0);
  const [clients, setClients] = useState<Record<string, string>>({});
  const [animaux, setAnimaux] = useState<Record<string, Animal>>({});
  const [fiche, setFiche] = useState<Rdv | null>(null);
  const [now, setNow] = useState(() => new Date());
  const planningRef = useRef<HTMLDivElement>(null);
  const crRef = useRef<HTMLDivElement>(null);

  const charger = useCallback(async () => {
    if (!pid || !uid) return;
    const t = new Date();
    const jour = new Date(t.getFullYear(), t.getMonth(), t.getDate());
    const [rRes, cRes, oRes, sRes, fRes, accRes, rdvAnimRes] = await Promise.all([
      supabase.from('rdv').select('*').eq('pro_profile_id', pid).in('statut', ['confirme', 'termine'])
        .gte('date_heure', new Date(jour.getTime() - 60 * 86400000).toISOString())
        .lte('date_heure', new Date(jour.getTime() + 31 * 86400000).toISOString()).order('date_heure'),
      supabase.from('cours_collectifs').select('id, titre, date_heure, lieu, pro_profile_id').eq('pro_uid', uid).neq('statut', 'annule')
        .gte('date_heure', jour.toISOString()).lt('date_heure', new Date(jour.getTime() + 86400000).toISOString()).order('date_heure'),
      supabase.from('education_objectifs').select('*').eq('pro_uid', uid).order('ordre'),
      supabase.from('education_progression').select('*').eq('pro_uid', uid).order('date_seance', { ascending: false }).limit(300),
      supabase.from('forfaits_souscrits').select('*').eq('pro_uid', uid).eq('statut', 'actif'),
      supabase.from('animal_access').select('animal_id').eq('pro_profile_id', pid).in('statut', ['active', 'write_requested', 'active_write']),
      supabase.from('rdv').select('animal_id').eq('pro_uid', uid).eq('pro_profile_id', pid).in('statut', ['confirme', 'termine']),
    ]);
    setNbAnimauxSuivis(new Set([...(accRes.data ?? []), ...(rdvAnimRes.data ?? [])]
      .map(x => (x as { animal_id: string | null }).animal_id).filter(Boolean)).size);
    const liste = (rRes.data ?? []) as Rdv[];
    const duProfil = <T extends { pro_profile_id?: string | null }>(x: T[]) => x.filter(o => !o.pro_profile_id || o.pro_profile_id === pid);
    const objs = duProfil((oRes.data ?? []) as Objectif[]);
    const ses = duProfil((sRes.data ?? []) as Seance[]);
    // Forfaits d'un autre profil pro du même compte : jamais ici.
    const forf = duProfil((fRes.data ?? []) as { animal_id: string | null; pro_profile_id?: string | null }[])
      .map(f => f.animal_id).filter(Boolean) as string[];
    const suivis = new Set([...objs.filter(o => o.statut !== 'acquis').map(o => String(o.animal_id)), ...forf]);
    const profils = [...new Set(liste.map(r => r.client_profile_id).filter(Boolean) as string[])];
    const ids = [...new Set([...liste.map(r => r.animal_id).filter(Boolean) as string[], ...suivis])];
    const [pRes, aRes] = await Promise.all([
      profils.length ? supabase.from('user_profiles_complet').select('id, firstname, lastname, nom, profile_type').in('id', profils) : Promise.resolve({ data: [] }),
      ids.length ? supabase.from('animaux').select('id, nom, photo_url').in('id', ids) : Promise.resolve({ data: [] }),
    ]);
    const cl: Record<string, string> = {};
    for (const p of (pRes.data ?? []) as { id: string; firstname?: string; lastname?: string; nom?: string; profile_type?: string }[]) {
      const perso = `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim();
      const structure = (p.nom ?? '').trim();
      cl[p.id] = p.profile_type !== 'particulier' && structure ? structure : perso || structure;
    }
    const an: Record<string, Animal> = {};
    for (const a of (aRes.data ?? []) as Animal[]) an[String(a.id)] = a;
    setRdvs(liste); setCours(duProfil((cRes.data ?? []) as Cours[])); setObjectifs(objs); setSeances(ses);
    setForfaitsAnimaux(forf); setClients(cl); setAnimaux(an); setNow(new Date()); setLoading(false);
  }, [pid, uid]);

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
  // Nouvelles demandes sans recharger la page.
  useActualisationAuto(pid ? charger : null);

  const jour = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const nomAnimal = (r: Rdv) => (r.animal_id && animaux[r.animal_id]?.nom) || r.animal_nom_manuel || 'Animal';
  const nomClient = (r: Rdv) => (r.client_profile_id && clients[r.client_profile_id]) || r.client_nom_manuel || 'Client';
  const duJour = rdvs.filter(r => memeJour(debut(r), jour));
  const suivis = [...new Set([...objectifs.filter(o => o.statut !== 'acquis').map(o => String(o.animal_id)), ...forfaitsAnimaux])];
  const deplacements = rdvs.filter(r => r.statut === 'confirme' && domicile(r) && debut(r) >= jour && debut(r) < new Date(jour.getTime() + 7 * 86400000));
  const avecCr = new Set(seances.filter(s => s.rdv_id && s.statut !== 'brouillon').map(s => String(s.rdv_id)));
  const brouillonsRdv = new Set(seances.filter(s => s.rdv_id && s.statut === 'brouillon').map(s => String(s.rdv_id)));
  const aFinaliser: { cle: string; animalId: string; texte: string; href: string }[] = [
    ...rdvs.filter(r => r.animal_id && (r.statut === 'termine' || debut(r).getTime() < now.getTime() - 3600000) && !avecCr.has(r.id))
      .map(r => ({ cle: r.id, animalId: String(r.animal_id), texte: `${nomAnimal(r)} · séance du ${jm(debut(r))}${brouillonsRdv.has(r.id) ? ' (brouillon)' : ''}`,
        href: `/mes-patients/${r.animal_id}?tab=Séances&rdv=${r.id}` })),
    ...seances.filter(s => s.statut === 'brouillon' && !s.rdv_id)
      .map(s => ({ cle: s.id, animalId: String(s.animal_id), texte: `${animaux[String(s.animal_id)]?.nom ?? 'Animal'} · brouillon du ${new Date(s.date_seance).toLocaleDateString('fr-FR')}`,
        href: `/mes-patients/${s.animal_id}?tab=Séances` })),
  ];
  const statut = (r: Rdv) => {
    if (r.statut === 'termine') return { label: 'Terminée', fg: '#4B5563', bg: '#F1F2F4' };
    const fin = new Date(debut(r).getTime() + (r.duree_minutes ?? 60) * 60000);
    if (fin < now) return { label: 'À clôturer', fg: AMBRE, bg: '#FFF4DC' };
    if (debut(r) < now) return { label: 'En cours', fg: TEAL, bg: '#E6F2F3' };
    return { label: 'À venir', fg: '#1D4ED8', bg: '#E8F0FE' };
  };
  const lignesSuivis = suivis.map(id => {
    const objs = objectifs.filter(o => String(o.animal_id) === id && o.statut !== 'acquis')
      .sort((a, b) => Number(!!b.prioritaire) - Number(!!a.prioritaire));
    const derniere = seances.find(s => String(s.animal_id) === id && s.statut !== 'brouillon');
    const prochaine = rdvs.filter(r => String(r.animal_id) === id && r.statut === 'confirme' && debut(r) > now)
      .sort((a, b) => debut(a).getTime() - debut(b).getTime())[0];
    return { id, objectif: objs[0], derniere, prochaine };
  }).sort((a, b) => (a.prochaine ? debut(a.prochaine).getTime() : 9e15) - (b.prochaine ? debut(b.prochaine).getTime() : 9e15));

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-6xl mx-auto px-4 py-5 space-y-5">
        <EnteteAccueil nom={nom} avatar={avatar} sousTitre="Éducation · comportement" avatarHref="/profil"
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
              <Kpi valeur={duJour.length + cours.length} label="Rendez-vous aujourd'hui" icone="calendrier"
                onClick={() => planningRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })} />
              <Kpi valeur={nbAnimauxSuivis} label="Animaux suivis" icone="patte" teinte={VERT} href="/mes-patients" />
              <Kpi valeur={deplacements.length} label="À domicile (7 jours)" icone="maison" teinte={VIOLET} href="/mes-rdv?onglet=a_venir" />
              <Kpi valeur={aFinaliser.length} label="Comptes rendus à finaliser" icone="crayon" teinte={AMBRE} actif={aFinaliser.length > 0}
                onClick={() => crRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })} />
            </div>

            <div className="grid lg:grid-cols-3 gap-5 items-start">
              <div ref={planningRef} className="lg:col-span-2 scroll-mt-4">
                <Section titre="Planning du jour" icone={<Icone nom="calendrier" taille={18} />} compteur={duJour.length + cours.length}
                  action={<Link href="/mes-rdv?onglet=a_venir" className="text-sm font-semibold text-[#0C5C6C] hover:underline">Voir l&apos;agenda →</Link>}>
                  {duJour.length === 0 && cours.length === 0 ? (
                    <p className="text-sm text-gray-400 text-center py-8">Aucune séance prévue aujourd&apos;hui.</p>
                  ) : (
                    <div className="space-y-2">
                      {duJour.map(r => {
                        const st = statut(r);
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
                              <p className="text-xs text-gray-500 truncate">{[nomClient(r), r.motif].filter(Boolean).join(' · ')}</p>
                              <p className="text-xs text-gray-500 truncate flex items-center gap-1">
                                <Icone nom={domicile(r) ? 'pin' : 'maison'} taille={12} /><span className="truncate">{domicile(r) ? r.lieu : 'Au cabinet / terrain'}</span>
                              </p>
                            </div>
                            <Badge texte={st.label} fg={st.fg} bg={st.bg} />
                          </button>
                        );
                      })}
                      {cours.map(c => (
                        <Link key={c.id} href="/education/planning"
                          className="w-full flex items-center gap-3 border border-[#EEF0EE] rounded-xl px-3 py-2.5 hover:bg-gray-50">
                          <p className="w-12 text-sm font-bold text-[#1E2025]">{hm(debut(c))}</p>
                          <span className="text-[#0C5C6C]"><Icone nom="equipe" taille={20} /></span>
                          <span className="flex-1 min-w-0">
                            <span className="block text-sm font-bold text-[#1E2025] truncate">{c.titre ?? 'Cours collectif'}</span>
                            <span className="block text-xs text-gray-500 truncate">{['Séance collective', c.lieu].filter(Boolean).join(' · ')}</span>
                          </span>
                        </Link>
                      ))}
                    </div>
                  )}
                </Section>
              </div>

              <div className="space-y-5">
                <Section titre="Suivis éducatifs en cours" icone={<Icone nom="suivi" taille={18} />} compteur={lignesSuivis.length}
                  action={lignesSuivis.length > 0 ? <Link href="/mes-patients" className="text-sm font-semibold text-[#0C5C6C] hover:underline">Tous →</Link> : undefined}>
                  {lignesSuivis.length === 0 ? <p className="text-sm text-gray-400">Aucun suivi en cours.</p> : (
                    <div className="space-y-1">
                      {lignesSuivis.slice(0, 6).map(l => (
                        <Link key={l.id} href={`/mes-patients/${l.id}`} className="flex items-center gap-2.5 py-1.5 hover:bg-gray-50 rounded-lg">
                          <PhotoAnimal url={animaux[l.id]?.photo_url} taille={34} />
                          <span className="flex-1 min-w-0">
                            <span className="block text-sm font-bold text-[#1E2025] truncate">{animaux[l.id]?.nom ?? 'Animal'}</span>
                            <span className="block text-xs text-gray-500 truncate">{l.objectif ? `${l.objectif.libelle} · ${STATUT_OBJ[l.objectif.statut] ?? ''}` : 'Forfait en cours'}</span>
                            <span className="block text-[11px] text-gray-400 truncate">
                              {[l.derniere ? `Dernière : ${jm(new Date(l.derniere.date_seance))}` : '', l.prochaine ? `Prochaine : ${jm(debut(l.prochaine))}` : ''].filter(Boolean).join(' · ')}
                            </span>
                          </span>
                        </Link>
                      ))}
                    </div>
                  )}
                </Section>

                <div ref={crRef} className="scroll-mt-4">
                  <Section titre="Comptes rendus à finaliser" icone={<Icone nom="crayon" taille={18} />} compteur={aFinaliser.length}>
                    {aFinaliser.length === 0 ? <p className="text-sm text-gray-400">Tout est à jour.</p> : (
                      <div className="space-y-1">
                        {aFinaliser.slice(0, 5).map(x => (
                          <Link key={x.cle} href={x.href} className="flex items-center gap-2 py-1.5 hover:bg-gray-50 rounded-lg">
                            <span className="text-[#D97706]"><Icone nom="document" taille={18} /></span>
                            <span className="flex-1 text-sm text-[#1E2025] truncate">{x.texte}</span>
                            <span className="text-xs font-bold text-[#0C5C6C]">Rédiger</span>
                          </Link>
                        ))}
                      </div>
                    )}
                  </Section>
                </div>

                {deplacements.length > 0 && (
                  <Section titre="Mes déplacements (7 jours)" icone={<Icone nom="pin" taille={18} />} compteur={deplacements.length}>
                    <div className="space-y-1.5">
                      {deplacements.slice(0, 6).map(r => (
                        <div key={r.id} className="flex items-center gap-2.5">
                          <span className="w-20 text-xs font-bold text-[#1E2025]">{jm(debut(r))} {hm(debut(r))}</span>
                          <span className="flex-1 min-w-0">
                            <span className="block text-sm text-[#1E2025] truncate">{nomAnimal(r)} · {nomClient(r)}</span>
                            <span className="block text-xs text-gray-500 truncate">{r.lieu}</span>
                          </span>
                          <ItineraireMenu lat={r.lieu_lat} lng={r.lieu_lng} adresse={r.lieu}
                            className="text-xs font-semibold text-[#0C5C6C]">Itinéraire</ItineraireMenu>
                        </div>
                      ))}
                    </div>
                  </Section>
                )}
              </div>
            </div>

            <Section titre="Accès rapides" icone={<Icone nom="eclair" taille={18} />}>
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                <Tuile href="/mes-rdv?onglet=a_venir" icone="plus" label="Nouveau rendez-vous" />
                <Tuile href="/mes-patients" icone="patte" label="Mes animaux suivis" teinte={VERT} />
                <Tuile href="/education/bibliotheque" icone="exercice" label="Mes programmes d'exercices" />
                <Tuile onClick={() => crRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })} icone="crayon" label="Comptes rendus à finaliser" teinte={AMBRE} />
              </div>
            </Section>
          </>
        )}
      </div>

      {fiche && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={() => setFiche(null)}>
          <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-md p-5" onClick={e => e.stopPropagation()}>
            <div className="flex items-center gap-3">
              <PhotoAnimal url={fiche.animal_id ? animaux[fiche.animal_id]?.photo_url : null} taille={44} />
              <div className="flex-1 min-w-0">
                <p className="font-bold text-[#1E2025]">{nomAnimal(fiche)}</p>
                <p className="text-sm text-gray-500">{nomClient(fiche)} · {hm(debut(fiche))} · {fiche.duree_minutes ?? 60} min</p>
              </div>
              <Badge texte={statut(fiche).label} fg={statut(fiche).fg} bg={statut(fiche).bg} />
            </div>
            {fiche.motif && <p className="text-sm text-[#1E2025] mt-3">{fiche.motif}</p>}
            {domicile(fiche) && <p className="text-sm text-gray-500 mt-1">{fiche.lieu}</p>}
            <div className="mt-4 space-y-1">
              {fiche.animal_id && (
                <>
                  <Link href={`/mes-patients/${fiche.animal_id}`} className="block py-2 text-sm font-semibold text-[#0C5C6C]">Ouvrir la fiche éducative</Link>
                  <Link href={`/mes-patients/${fiche.animal_id}?tab=Programme`} className="block py-2 text-sm font-semibold text-[#0C5C6C]">Consulter les objectifs</Link>
                  <Link href={`/mes-patients/${fiche.animal_id}?tab=Séances&rdv=${fiche.id}`} className="block py-2 text-sm font-semibold text-[#0C5C6C]">Rédiger le compte rendu</Link>
                </>
              )}
              {domicile(fiche) && (
                <ItineraireMenu lat={fiche.lieu_lat} lng={fiche.lieu_lng} adresse={fiche.lieu} className="block py-2 text-sm font-semibold text-[#0C5C6C]">
                  Ouvrir l&apos;itinéraire
                </ItineraireMenu>
              )}
              <Link href={`/mes-rdv?onglet=a_venir&rdv=${fiche.id}`} className="block py-2 text-sm font-semibold text-[#0C5C6C]">Voir la séance dans l&apos;agenda</Link>
            </div>
            <button onClick={() => setFiche(null)} className="w-full mt-3 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Fermer</button>
          </div>
        </div>
      )}
    </div>
  );
}
