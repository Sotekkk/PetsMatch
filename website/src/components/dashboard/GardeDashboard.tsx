'use client';
// Accueil pet-sitting / garde : tableau de bord de l'activité du jour.
// Uniquement des données réelles et des modules EXISTANTS : agenda (rdv),
// registre + séjours (garde-sejours), gestion des clés (cles_clients),
// compte rendu express (pension_updates). Miroir appli :
// lib/pages/pro/garde_dashboard.dart.
//
// Heures réelles : rdv.arrivee_validee_le = début effectif, depart_valide_le /
// termine_at = fin effective ; rdv.date_heure (prévu) n'est jamais modifié.
import { useCallback, useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import ItineraireMenu from '@/components/dashboard/ItineraireMenu';
import CompteRenduExpressModal from '@/components/garde/CompteRenduExpressModal';
import { Kpi, Section, Badge, PhotoAnimal, EnteteAccueil, Tuile, Icone } from '@/components/dashboard/kit';
import { gardePrestationKey } from '@/lib/garde-facturation';
import { gardeMotifLabel } from '@/lib/garde-labels';
import { estGardeJournee, groupeGardeSejours, type GardeSejour } from '@/lib/garde-sejours';
import { familleGarde, FAMILLES_GARDE } from '@/lib/compte-rendu-garde';

const TEAL = '#0C5C6C';
const VERT = '#2E7D5E';
const AMBRE = '#D97706';
const OR = '#B8860B';
const VIOLET = '#7B5EA7';

interface Rdv {
  id: string; date_heure: string; duree_minutes: number | null; statut: string; motif: string | null;
  animal_id: string | null; client_uid: string | null; client_profile_id: string | null;
  client_nom_manuel: string | null; animal_nom_manuel: string | null;
  lieu: string | null; lieu_lat: number | null; lieu_lng: number | null; salle_id: string | null;
  notes_client: string | null; instructeur_profile_id: string | null;
  arrivee_validee_le: string | null; depart_valide_le: string | null; termine_at: string | null;
  _animal_nom?: string; _client_nom?: string;
}
interface Cle { id: string; animal_id: string | null; owner_uid: string | null; description: string | null }
interface Animal { id: string; nom: string | null; espece: string | null; photo_url: string | null }

const debut = (r: Rdv) => new Date(r.date_heure);
const finPrevue = (r: Rdv) => new Date(debut(r).getTime() + (r.duree_minutes ?? 30) * 60000);
const memeJour = (a: Date, b: Date) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
const hm = (d: Date) => d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
const jm = (d: Date) => d.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' });
const exterieur = (r: Rdv) => (!!r.lieu?.trim() && !r.salle_id) || r.lieu_lat != null;

export default function GardeDashboard({ nom, avatar }: { nom: string; avatar: string | null }) {
  const { user } = useAuth();
  const uid = user?.uid ?? '';
  // Profil actif, sinon profil principal (pet-sitter sans profil secondaire) — comme SanteDashboard.
  const actifPid = useActiveProfile();
  const [pidPrincipal, setPidPrincipal] = useState('');
  const pid = actifPid || pidPrincipal;
  const [loading, setLoading] = useState(true);
  const [rdvs, setRdvs] = useState<Rdv[]>([]);
  const [cles, setCles] = useState<Cle[]>([]);
  const [animaux, setAnimaux] = useState<Record<string, Animal>>({});
  const [intervenants, setIntervenants] = useState<Record<string, string>>({});
  const [avecCr, setAvecCr] = useState<Set<string>>(new Set());
  const [famille, setFamille] = useState('tous');
  const [fiche, setFiche] = useState<Rdv | null>(null);
  const [compteRendu, setCompteRendu] = useState<Rdv | null>(null);
  const [now, setNow] = useState(() => new Date());
  const planningRef = useRef<HTMLDivElement>(null);

  const charger = useCallback(async () => {
    if (!pid) return;
    const t = new Date();
    const jour = new Date(t.getFullYear(), t.getMonth(), t.getDate());
    const { data: rows } = await supabase.from('rdv').select('*')
      .eq('pro_profile_id', pid).in('statut', ['confirme', 'termine'])
      .gte('date_heure', new Date(jour.getTime() - 30 * 86400000).toISOString())
      .lte('date_heure', new Date(jour.getTime() + 31 * 86400000).toISOString())
      .order('date_heure');
    const liste = (rows ?? []) as Rdv[];
    const { data: c } = await supabase.from('cles_clients').select('id, animal_id, owner_uid, description')
      .eq('pro_profile_id', pid).eq('statut', 'en_possession');
    const lesCles = (c ?? []) as Cle[];
    const profils = [...new Set([...liste.map(r => r.client_profile_id), ...liste.map(r => r.instructeur_profile_id)].filter(Boolean) as string[])];
    const ids = [...new Set([...liste.map(r => r.animal_id), ...lesCles.map(k => k.animal_id)].filter(Boolean) as string[])];
    const [profRes, animRes] = await Promise.all([
      profils.length ? supabase.from('user_profiles_complet').select('id, firstname, lastname, nom, profile_type').in('id', profils) : Promise.resolve({ data: [] }),
      ids.length ? supabase.from('animaux').select('id, nom, espece, photo_url').in('id', ids) : Promise.resolve({ data: [] }),
    ]);
    const cl: Record<string, string> = {}, inter: Record<string, string> = {};
    const intervenantIds = new Set(liste.map(r => r.instructeur_profile_id).filter(Boolean) as string[]);
    for (const p of (profRes.data ?? []) as { id: string; firstname?: string; lastname?: string; nom?: string; profile_type?: string }[]) {
      const perso = `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim();
      const structure = (p.nom ?? '').trim();
      cl[p.id] = p.profile_type !== 'particulier' && structure ? structure : perso || structure;
      if (intervenantIds.has(p.id)) inter[p.id] = perso || cl[p.id];
    }
    const an: Record<string, Animal> = {};
    for (const a of (animRes.data ?? []) as Animal[]) an[String(a.id)] = a;
    for (const r of liste) {
      r._animal_nom = (r.animal_id && an[String(r.animal_id)]?.nom) || r.animal_nom_manuel || 'Animal';
      r._client_nom = (r.client_profile_id && cl[r.client_profile_id]) || r.client_nom_manuel || 'Client';
    }
    // Comptes rendus envoyés pour les prestations du jour (colonne rdv_id).
    const ajd = liste.filter(r => memeJour(debut(r), t)).map(r => r.id);
    let cr = new Set<string>();
    if (ajd.length) {
      const { data, error } = await supabase.from('pension_updates').select('rdv_id').in('rdv_id', ajd);
      if (!error) cr = new Set((data ?? []).map(x => String((x as { rdv_id: string }).rdv_id)));
    }
    setRdvs(liste); setCles(lesCles); setAnimaux(an); setIntervenants(inter); setAvecCr(cr);
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
    const canal = supabase.channel(`dash-garde-${pid}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'rdv', filter: `pro_profile_id=eq.${pid}` }, () => { charger(); })
      .subscribe();
    return () => { supabase.removeChannel(canal); };
  }, [pid, charger]);

  const jour = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const duJour = rdvs.filter(r => memeJour(debut(r), now)).sort((a, b) => a.date_heure.localeCompare(b.date_heure));
  const sejours: GardeSejour[] = groupeGardeSejours(rdvs);
  const enGarde = sejours.filter(s => s.statut !== 'termine' && (s.statut === 'en_garde'
    || (jour >= new Date(s.dateEntree.getFullYear(), s.dateEntree.getMonth(), s.dateEntree.getDate())
      && jour <= new Date(s.dateSortiePrevue.getFullYear(), s.dateSortiePrevue.getMonth(), s.dateSortiePrevue.getDate()))));
  const entrees = sejours.filter(s => memeJour(s.dateEntree, now));
  const sorties = sejours.filter(s => memeJour(s.dateSortiePrevue, now) && s.statut !== 'termine');
  // Clés à restituer : en ma possession alors que le client n'a plus de prestation confirmée à venir.
  const clesARestituer = cles.filter(k => !rdvs.some(r => r.statut === 'confirme' && debut(r) >= jour
    && ((k.owner_uid && r.client_uid === k.owner_uid) || (k.animal_id && r.animal_id === k.animal_id))));
  const aCloturer = rdvs.filter(r => r.statut === 'confirme' && !estGardeJournee(r) && finPrevue(r) < now);
  const cleDe = (r: Rdv) => cles.find(k => (k.animal_id && k.animal_id === r.animal_id) || (k.owner_uid && k.owner_uid === r.client_uid)) ?? null;
  const prestation = (r: Rdv) => {
    const k = gardePrestationKey(r.motif);
    return gardeMotifLabel(k === 'autre' ? (r.motif?.trim() || 'Prestation') : k, r.animal_id ? animaux[r.animal_id]?.espece : null);
  };
  const lieu = (r: Rdv) => estGardeJournee(r) ? 'Chez moi (garde)' : r.lieu?.trim() || 'Adresse non renseignée';
  const reel = (iso: string | null) => (iso ? new Date(iso) : null);
  const statut = (r: Rdv) => {
    if (r.statut === 'termine') return { label: 'Terminé', fg: '#4B5563', bg: '#F1F2F4' };
    if (r.arrivee_validee_le && !r.depart_valide_le && !estGardeJournee(r)) return { label: 'En cours', fg: TEAL, bg: '#E6F2F3' };
    if (finPrevue(r) < now && !estGardeJournee(r)) return { label: 'À clôturer', fg: AMBRE, bg: '#FFF4DC' };
    return { label: 'À venir', fg: '#1D4ED8', bg: '#E8F0FE' };
  };

  async function maj(r: Rdv, champs: Partial<Rdv>) {
    const { error } = await supabase.from('rdv').update(champs).eq('id', r.id);
    if (error) { alert(`Erreur : ${error.message}`); return; }
    setRdvs(l => l.map(x => (x.id === r.id ? { ...x, ...champs } : x)));
  }
  const commencer = (r: Rdv) => maj(r, { arrivee_validee_le: new Date().toISOString() });
  async function terminer(r: Rdv) {
    const t = new Date().toISOString();
    await maj(r, { depart_valide_le: t, termine_at: t, statut: 'termine' });
    setFiche(null);
    if (r.animal_id) setCompteRendu({ ...r, statut: 'termine' });
  }

  const presentes = FAMILLES_GARDE.filter(f => duJour.some(r => familleGarde(r.motif) === f.key));
  const liste = famille === 'tous' ? duJour : duJour.filter(r => familleGarde(r.motif) === famille);
  const ext = duJour.filter(r => exterieur(r) && !estGardeJournee(r));
  const faites = ext.filter(r => r.statut === 'termine').length;
  const chip = (actif: boolean) => `px-3 py-1.5 rounded-lg text-xs font-semibold border ${actif ? 'text-white border-transparent' : 'text-[#1E2025] border-[#E4E7E2] bg-white'}`;

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-6xl mx-auto px-4 py-5 space-y-5">
        <EnteteAccueil nom={nom} avatar={avatar} sousTitre="Pet-sitting · garde à domicile" avatarHref="/profil"
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
              <Kpi valeur={duJour.length} label="Prestations du jour" icone="calendrier"
                onClick={() => planningRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' })} />
              <Kpi valeur={enGarde.length} label="Animaux en garde" icone="patte" teinte={VERT} href="/mes-patients" />
              <Kpi valeur={entrees.length + sorties.length} label="Entrées / sorties" icone="fleche" teinte={VIOLET} href="/garde/registre" />
              <Kpi valeur={clesARestituer.length} label="Clés à gérer" icone="cle" teinte={OR} href="/garde/cles" />
            </div>

            <div className="grid lg:grid-cols-3 gap-5 items-start">
              {/* Planning du jour */}
              <div ref={planningRef} className="lg:col-span-2 scroll-mt-4">
                <Section titre="Planning du jour" icone={<Icone nom="calendrier" taille={18} />}
                  action={<Link href="/mes-rdv?onglet=a_venir" className="text-sm font-semibold text-[#0C5C6C] hover:underline">Voir l&apos;agenda complet →</Link>}>
                  {presentes.length > 1 && (
                    <div className="flex flex-wrap gap-2 mb-3">
                      <button type="button" onClick={() => setFamille('tous')} className={chip(famille === 'tous')} style={famille === 'tous' ? { background: TEAL } : {}}>Toutes ({duJour.length})</button>
                      {presentes.map(f => (
                        <button key={f.key} type="button" onClick={() => setFamille(f.key)} className={chip(famille === f.key)} style={famille === f.key ? { background: TEAL } : {}}>
                          {f.label} ({duJour.filter(r => familleGarde(r.motif) === f.key).length})
                        </button>
                      ))}
                    </div>
                  )}
                  {liste.length === 0 ? (
                    <p className="text-sm text-gray-400 text-center py-8">Aucune prestation aujourd&apos;hui.</p>
                  ) : (
                    <div className="space-y-2">
                      {liste.map(r => {
                        const st = statut(r);
                        const cle = estGardeJournee(r) ? null : cleDe(r);
                        return (
                          <button key={r.id} type="button" onClick={() => setFiche(r)}
                            className="w-full text-left flex items-center gap-3 border border-[#EEF0EE] rounded-xl px-3 py-2.5 hover:bg-gray-50">
                            <div className="w-12 flex-shrink-0">
                              <p className="text-sm font-bold text-[#1E2025]">{hm(debut(r))}</p>
                              <p className="text-[11px] text-gray-500">{(r.duree_minutes ?? 30) >= 1440 ? 'journée' : `${r.duree_minutes ?? 30} min`}</p>
                            </div>
                            <PhotoAnimal url={r.animal_id ? animaux[r.animal_id]?.photo_url : null} />
                            <div className="flex-1 min-w-0">
                              <p className="text-sm font-bold text-[#1E2025] truncate">{r._animal_nom}</p>
                              <p className="text-xs text-gray-500 truncate">{r._client_nom} · {prestation(r)}</p>
                              <p className="text-xs text-gray-500 truncate flex items-center gap-1">
                                <Icone nom={estGardeJournee(r) ? 'maison' : 'pin'} taille={12} /><span className="truncate">{lieu(r)}</span>
                                {cle && <span title="Clé en ma possession" className="text-[#B8860B]"><Icone nom="cle" taille={12} /></span>}
                              </p>
                              {r.instructeur_profile_id && intervenants[r.instructeur_profile_id] && (
                                <p className="text-[11px] text-gray-500">Intervenant : {intervenants[r.instructeur_profile_id]}</p>
                              )}
                            </div>
                            <span className="flex flex-col items-end gap-0.5">
                              <Badge texte={st.label} fg={st.fg} bg={st.bg} />
                              {avecCr.has(r.id) && <span className="text-[11px] font-semibold" style={{ color: VERT }}>Compte rendu envoyé</span>}
                            </span>
                          </button>
                        );
                      })}
                    </div>
                  )}
                </Section>
              </div>

              <div className="space-y-5">
                {/* Tournée du jour (le module « Ma tournée » avec carte est dans l'appli) */}
                <Section titre="Ma tournée" icone={<Icone nom="pin" taille={18} />}>
                  {ext.length === 0 ? (
                    <p className="text-sm text-gray-400">Aucune intervention à l&apos;extérieur aujourd&apos;hui.</p>
                  ) : (
                    <>
                      <p className="text-sm text-[#1E2025] mb-2">{ext.length} intervention{ext.length > 1 ? 's' : ''} · {faites} terminée{faites > 1 ? 's' : ''} · {ext.length - faites} restante{ext.length - faites > 1 ? 's' : ''}</p>
                      <ol className="space-y-2">
                        {ext.map((r, i) => (
                          <li key={r.id} className="flex items-start gap-2 text-sm">
                            <span className="w-5 h-5 rounded-full bg-[#E6F2F3] text-[#0C5C6C] text-[11px] font-bold flex items-center justify-center flex-shrink-0">{i + 1}</span>
                            <span className={`flex-1 min-w-0 ${r.statut === 'termine' ? 'text-gray-400 line-through' : 'text-[#1E2025]'}`}>
                              {hm(debut(r))} · {r._animal_nom}<span className="block text-xs text-gray-500 truncate no-underline">{lieu(r)}</span>
                            </span>
                            {r.statut !== 'termine' && (r.lieu?.trim() || r.lieu_lat != null) && (
                              <ItineraireMenu lat={r.lieu_lat} lng={r.lieu_lng} adresse={r.lieu} className="text-xs font-semibold text-[#0C5C6C]">Itinéraire ▾</ItineraireMenu>
                            )}
                          </li>
                        ))}
                      </ol>
                    </>
                  )}
                </Section>

                {/* Gestion quotidienne */}
                <Section titre="Gestion quotidienne" icone={<Icone nom="valide" taille={18} />}>
                  {aCloturer.length + entrees.length + sorties.length + enGarde.length + clesARestituer.length === 0 && (
                    <p className="text-sm text-gray-400">Rien à signaler aujourd&apos;hui.</p>
                  )}
                  {aCloturer.length > 0 && (
                    <Bloc titre={`Prestations à clôturer (${aCloturer.length})`} lien="/mes-rdv?onglet=a_venir">
                      {aCloturer.slice(0, 4).map(r => (
                        <button key={r.id} type="button" onClick={() => setFiche(r)} className="block w-full text-left text-sm truncate" style={{ color: AMBRE }}>
                          {jm(debut(r))} {hm(debut(r))} · {r._animal_nom} · {prestation(r)}
                        </button>
                      ))}
                    </Bloc>
                  )}
                  {(entrees.length > 0 || sorties.length > 0) && (
                    <Bloc titre={`Entrées / sorties du jour (${entrees.length + sorties.length})`} lien="/garde/registre">
                      {entrees.map((s, i) => <p key={`e${i}`} className="text-sm text-gray-600 truncate">Arrivée · {s.animalNom} ({s.clientNom}){s.arriveeValideeLe ? ' — validée' : ''}</p>)}
                      {sorties.map((s, i) => <p key={`s${i}`} className="text-sm text-gray-600 truncate">Départ · {s.animalNom} ({s.clientNom})</p>)}
                    </Bloc>
                  )}
                  {enGarde.length > 0 && (
                    <Bloc titre={`Animaux en garde (${enGarde.length})`} lien="/mes-patients">
                      <p className="text-sm text-[#1E2025]">{enGarde.map(s => s.animalNom).join(', ')}</p>
                    </Bloc>
                  )}
                  {clesARestituer.length > 0 && (
                    <Bloc titre={`Clés à restituer (${clesARestituer.length})`} lien="/garde/cles">
                      {clesARestituer.slice(0, 4).map(k => (
                        <p key={k.id} className="text-sm text-[#1E2025] truncate">{k.description || 'Clé'}{k.animal_id && animaux[k.animal_id] ? ` · ${animaux[k.animal_id].nom}` : ''}</p>
                      ))}
                    </Bloc>
                  )}
                </Section>
              </div>
            </div>

            {/* Accès rapides : seulement l'utile au quotidien (le reste est dans le menu) */}
            <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
              <Tuile href="/mes-rdv?onglet=a_venir" icone="plus" label="Nouveau RDV" />
              <Tuile href="/garde/registre" icone="livre" label="Registre" />
              <Tuile href="/garde/cles" icone="cle" label="Gestion des clés" teinte={OR} />
              <Tuile href="/mes-patients" icone="patte" label="Mes animaux en garde" teinte={VERT} />
            </div>
          </>
        )}
      </div>

      {fiche && (() => {
        const r = rdvs.find(x => x.id === fiche.id) ?? fiche;
        const st = statut(r);
        const cle = estGardeJournee(r) ? null : cleDe(r);
        const cleRestituer = !!cle && clesARestituer.some(k => k.id === cle.id);
        const debutReel = reel(r.arrivee_validee_le), finReelle = reel(r.depart_valide_le) ?? reel(r.termine_at);
        const garde = estGardeJournee(r);
        return (
          <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={() => setFiche(null)}>
            <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-lg p-5 max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
              <div className="flex items-center gap-3">
                <PhotoAnimal url={r.animal_id ? animaux[r.animal_id]?.photo_url : null} taille={44} />
                <div className="flex-1 min-w-0">
                  <p className="font-bold text-lg text-[#1E2025] truncate">{r._animal_nom}</p>
                  <p className="text-sm text-gray-500 truncate">{prestation(r)} · {r._client_nom}</p>
                </div>
                <Badge texte={st.label} fg={st.fg} bg={st.bg} />
              </div>
              <div className="mt-4 space-y-1.5 text-sm text-[#1E2025]">
                <p>Prévu le {jm(debut(r))} à {hm(debut(r))} · {r.duree_minutes ?? 30} min</p>
                {(debutReel || finReelle) && (
                  <p className="font-semibold" style={{ color: TEAL }}>
                    {[debutReel && `Début réel ${hm(debutReel)}`, finReelle && `fin réelle ${hm(finReelle)}`].filter(Boolean).join(' · ')}
                  </p>
                )}
                <p>{lieu(r)}</p>
                {r.instructeur_profile_id && intervenants[r.instructeur_profile_id] && <p>Intervenant : {intervenants[r.instructeur_profile_id]}</p>}
              </div>
              <p className="text-sm font-bold text-[#1E2025] mt-4 mb-1">Consignes du propriétaire</p>
              <p className={`text-sm whitespace-pre-line ${r.notes_client?.trim() ? 'text-[#1E2025]' : 'text-gray-400'}`}>
                {r.notes_client?.trim() || 'Aucune consigne saisie pour ce rendez-vous.'}
              </p>
              {!garde && (
                // Clé : statuts existants seulement ; jamais de code d'accès ici.
                <Link href="/garde/cles" className="mt-3 flex items-center gap-2 text-sm">
                  <span style={{ color: cle ? (cleRestituer ? AMBRE : OR) : '#9CA3AF' }}><Icone nom="cle" taille={16} /></span>
                  <span className={`flex-1 ${cle ? 'text-[#1E2025]' : 'text-gray-400'}`}>
                    {!cle ? 'Aucune clé enregistrée pour ce client' : cleRestituer ? `Clé à restituer — ${cle.description ?? ''}` : `Clé en ma possession — ${cle.description ?? ''}`}
                  </span>
                  <span className="text-xs font-bold text-[#0C5C6C]">Gestion des clés</span>
                </Link>
              )}
              <div className="flex flex-wrap gap-2 mt-5">
                {exterieur(r) && (
                  <ItineraireMenu lat={r.lieu_lat} lng={r.lieu_lng} adresse={r.lieu}
                    className="px-3 py-2 rounded-xl border text-sm font-semibold text-[#0C5C6C] border-[#CFDCDD]">Itinéraire ▾</ItineraireMenu>
                )}
                {garde ? (
                  <Link href="/garde/registre" className="px-3 py-2 rounded-xl border text-sm font-semibold text-[#0C5C6C] border-[#CFDCDD]">Arrivée / départ (registre)</Link>
                ) : r.statut === 'confirme' && !debutReel ? (
                  <button type="button" onClick={() => { commencer(r); setFiche(null); }}
                    className="px-4 py-2 rounded-xl text-sm font-bold text-white" style={{ background: TEAL }}>Commencer</button>
                ) : null}
                {!garde && r.statut === 'confirme' && (
                  <button type="button" onClick={() => terminer(r)}
                    className="px-4 py-2 rounded-xl text-sm font-bold text-white" style={{ background: VERT }}>Terminer</button>
                )}
                {!garde && r.animal_id && (r.statut === 'termine' || debutReel) && (
                  <button type="button" onClick={() => { setFiche(null); setCompteRendu(r); }}
                    className="px-3 py-2 rounded-xl border text-sm font-semibold text-[#0C5C6C] border-[#CFDCDD]">Compte rendu</button>
                )}
                <Link href="/mes-rdv?onglet=a_venir" className="px-3 py-2 text-sm font-semibold text-[#0C5C6C]">Voir dans l&apos;agenda</Link>
              </div>
            </div>
          </div>
        );
      })()}

      {compteRendu && user && (
        <CompteRenduExpressModal
          rdv={compteRendu}
          animalNom={compteRendu._animal_nom ?? ''}
          proUid={user.uid}
          proNom={nom}
          onClose={() => setCompteRendu(null)}
          onEnvoye={() => setAvecCr(s => new Set([...s, compteRendu.id]))}
        />
      )}
    </div>
  );
}

function Bloc({ titre, lien, children }: { titre: string; lien: string; children: React.ReactNode }) {
  return (
    <div className="mt-3 first:mt-0">
      <div className="flex items-center justify-between mb-1">
        <p className="text-sm font-bold text-[#1E2025]">{titre}</p>
        <Link href={lien} className="text-xs font-semibold text-[#0C5C6C] hover:underline">Voir</Link>
      </div>
      {children}
    </div>
  );
}
