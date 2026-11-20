'use client';
// Accueil maréchal-ferrant : tournée du jour, demandes, interventions à
// clôturer et ferrures à renouveler (dernière intervention terminée + délai
// du profil, user_profiles.marechal_cycle_semaines, 7 semaines par défaut —
// migration_marechal_cycle_ferrure.sql). Miroir appli :
// lib/pages/pro/marechal_dashboard.dart. Scopé au profil actif.
import { useActualisationAuto } from '@/hooks/useActualisationAuto';
import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import ItineraireMenu from '@/components/dashboard/ItineraireMenu';
import { Kpi, Section, Badge, PhotoAnimal, EnteteAccueil, Tuile, Icone } from '@/components/dashboard/kit';

const TEAL = '#0C5C6C';
const VERT = '#2E7D5E';
const AMBRE = '#D97706';
const ROUGE = '#B3261E';
const BRUN = '#8D6E63';
export const CYCLE_DEFAUT = 7;

interface Rdv {
  id: string; date_heure: string; duree_minutes: number | null; statut: string; motif: string | null;
  animal_id: string | null; client_profile_id: string | null; client_nom_manuel: string | null;
  animal_nom_manuel: string | null; lieu: string | null; lieu_lat: number | null; lieu_lng: number | null;
  notes_client: string | null; created_at: string | null;
}
const debut = (r: Rdv) => new Date(r.date_heure);
const fin = (r: Rdv) => new Date(debut(r).getTime() + (r.duree_minutes ?? 60) * 60000);
const memeJour = (a: Date, b: Date) => a.toDateString() === b.toDateString();
const hm = (d: Date) => d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
const jm = (d: Date) => d.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' });
const ACTIFS = ['demande', 'contre_proposition', 'confirme'];
function lienRdv(r: Rdv) {
  // Un RDV confirmé reste dans « À venir » jusqu'à « Terminé », même une fois passé.
  const onglet = r.statut === 'demande' || r.statut === 'contre_proposition' ? 'demandes' : r.statut === 'confirme' ? 'a_venir' : 'historique';
  return `/mes-rdv?onglet=${onglet}&rdv=${r.id}`;
}
/** Même cheval : fiche PetsMatch, sinon nom saisi + client (fiche hors appli). */
const cleCheval = (r: Rdv) => r.animal_id
  ? `a:${r.animal_id}`
  : r.animal_nom_manuel?.trim() ? `m:${r.client_profile_id ?? r.client_nom_manuel ?? ''}:${r.animal_nom_manuel.trim().toLowerCase()}` : null;

export default function MarechalDashboard({ nom, avatar }: { nom: string; avatar: string | null }) {
  const { user } = useAuth();
  const uid = user?.uid ?? '';
  const actifPid = useActiveProfile();
  const [pidPrincipal, setPidPrincipal] = useState('');
  const pid = actifPid || pidPrincipal;
  const [loading, setLoading] = useState(true);
  const [rdvs, setRdvs] = useState<Rdv[]>([]);
  const [clients, setClients] = useState<Record<string, string>>({});
  const [animaux, setAnimaux] = useState<Record<string, { nom: string | null; photo_url: string | null }>>({});
  const [cycle, setCycle] = useState(CYCLE_DEFAUT);
  const [now, setNow] = useState(() => new Date());

  const charger = useCallback(async () => {
    if (!pid) return;
    const t = new Date();
    // Un an d'historique : de quoi retrouver la dernière ferrure de chaque cheval.
    const depuis = new Date(t.getFullYear() - 1, t.getMonth(), 1).toISOString();
    const [r, p] = await Promise.all([
      supabase.from('rdv')
        .select('id, date_heure, duree_minutes, statut, motif, animal_id, client_profile_id, client_nom_manuel, animal_nom_manuel, lieu, lieu_lat, lieu_lng, notes_client, created_at')
        .eq('pro_profile_id', pid).in('statut', [...ACTIFS, 'termine'])
        .gte('date_heure', depuis).order('date_heure').limit(3000),
      supabase.from('user_profiles').select('marechal_cycle_semaines').eq('id', pid).maybeSingle(),
    ]);
    const liste = (r.data ?? []) as Rdv[];
    const c = Number((p.data as { marechal_cycle_semaines?: number | null } | null)?.marechal_cycle_semaines);
    setCycle(c >= 2 && c <= 26 ? c : CYCLE_DEFAUT);
    const profils = [...new Set(liste.map(x => x.client_profile_id).filter(Boolean) as string[])];
    const ids = [...new Set(liste.map(x => x.animal_id).filter(Boolean) as string[])];
    const [pRes, aRes] = await Promise.all([
      profils.length ? supabase.from('user_profiles_complet').select('id, firstname, lastname, nom, profile_type').in('id', profils) : Promise.resolve({ data: [] }),
      ids.length ? supabase.from('animaux').select('id, nom, photo_url').in('id', ids) : Promise.resolve({ data: [] }),
    ]);
    const cl: Record<string, string> = {};
    for (const x of (pRes.data ?? []) as { id: string; firstname?: string; lastname?: string; nom?: string; profile_type?: string }[]) {
      const perso = `${x.firstname ?? ''} ${x.lastname ?? ''}`.trim(); const st = (x.nom ?? '').trim();
      cl[x.id] = x.profile_type !== 'particulier' && st ? st : perso || st;
    }
    const an: Record<string, { nom: string | null; photo_url: string | null }> = {};
    for (const a of (aRes.data ?? []) as { id: string; nom: string | null; photo_url: string | null }[]) an[String(a.id)] = a;
    setRdvs(liste); setClients(cl); setAnimaux(an);
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
  useActualisationAuto(pid ? charger : null);

  async function changerCycle(n: number) {
    const avant = cycle;
    setCycle(n);
    const { error } = await supabase.from('user_profiles').update({ marechal_cycle_semaines: n }).eq('id', pid);
    if (error) {
      setCycle(avant);
      alert(error.message.includes('marechal_cycle_semaines') ? 'Réglage indisponible : migration migration_marechal_cycle_ferrure.sql à passer.' : error.message);
    }
  }

  const nomAnimal = (r: Rdv) => (r.animal_id && animaux[r.animal_id]?.nom) || r.animal_nom_manuel || 'Cheval';
  const nomClient = (r: Rdv) => (r.client_profile_id && clients[r.client_profile_id]) || r.client_nom_manuel || 'Client';
  const photo = (r: Rdv) => (r.animal_id ? animaux[r.animal_id]?.photo_url : null) ?? null;
  const adresse = (r: Rdv) => r.lieu?.trim() && r.lieu.trim().toLowerCase() !== 'à domicile' ? r.lieu.trim() : null;

  const tournee = rdvs.filter(r => (r.statut === 'confirme' || r.statut === 'termine') && memeJour(debut(r), now));
  const debutMois = new Date(now.getFullYear(), now.getMonth(), 1);
  const finMois = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  const duMois = rdvs.filter(r => debut(r) >= debutMois && debut(r) < finMois);
  const demandes = rdvs.filter(r => (r.statut === 'demande' || r.statut === 'contre_proposition') && fin(r) > now);
  const aCloturer = rdvs.filter(r => r.statut === 'confirme' && fin(r) <= now).sort((a, b) => b.date_heure.localeCompare(a.date_heure));
  const prochain = tournee.find(r => r.statut === 'confirme' && fin(r) > now && (adresse(r) || r.lieu_lat != null));

  // Ferrures à renouveler : dernière intervention terminée + délai, sans RDV
  // déjà prévu pour ce cheval ; affichées dès 7 jours avant l'échéance.
  const derniere = new Map<string, Rdv>();
  const prevus = new Set<string>();
  for (const r of rdvs) {
    const k = cleCheval(r); if (!k) continue;
    if (r.statut === 'termine') { const d = derniere.get(k); if (!d || d.date_heure < r.date_heure) derniere.set(k, r); }
    else if (ACTIFS.includes(r.statut) && fin(r) > now) prevus.add(k);
  }
  const aujourdhui = new Date(now.toDateString()).getTime();
  const renouveler = [...derniere.entries()]
    .filter(([k]) => !prevus.has(k))
    .map(([, r]) => {
      const ech = new Date(debut(r)); ech.setDate(ech.getDate() + cycle * 7);
      return { r, ech, ecart: Math.round((new Date(ech.toDateString()).getTime() - aujourdhui) / 86400000) };
    })
    .filter(x => x.ecart <= 7)
    .sort((a, b) => a.ecart - b.ecart);
  const programmer = (r: Rdv) => {
    const q = new URLSearchParams({ nouveau: '1' });
    if (r.animal_id) q.set('animal', r.animal_id);
    if (r.motif?.trim()) q.set('motif', r.motif.trim());
    return `/mes-rdv?${q.toString()}`;
  };

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-6xl mx-auto px-4 py-5 space-y-5">
        <EnteteAccueil nom={nom} avatar={avatar} sousTitre="Maréchal-ferrant" avatarHref="/profil"
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
              <Kpi valeur={tournee.length} label="RDV aujourd'hui" icone={<Icone nom="calendrier" />} href="/mes-rdv?onglet=a_venir" />
              <Kpi valeur={duMois.length} label="RDV ce mois" icone={<Icone nom="suivi" />} teinte={BRUN} href="/agenda" />
              <Kpi valeur={demandes.length} label="Demandes en attente" icone={<Icone nom="enveloppe" />} teinte={AMBRE} actif={demandes.length > 0} href="/mes-rdv?onglet=demandes" />
              <Kpi valeur={aCloturer.length} label="Interventions à clôturer" icone={<Icone nom="valide" />} teinte={ROUGE} actif={aCloturer.length > 0} href="/mes-rdv?onglet=a_venir" />
            </div>

            <div className="grid lg:grid-cols-3 gap-5 items-start">
              <div className="lg:col-span-2 space-y-5">
                <Section titre="Tournée du jour" icone={<Icone nom="pin" taille={18} />} compteur={tournee.length}
                  action={prochain
                    ? <ItineraireMenu lat={prochain.lieu_lat} lng={prochain.lieu_lng} adresse={prochain.lieu} className="text-sm font-bold text-[#0C5C6C]">Itinéraire du prochain ▾</ItineraireMenu>
                    : <Link href="/agenda" className="text-sm font-semibold text-[#0C5C6C] hover:underline">Voir l&apos;agenda →</Link>}>
                  {tournee.length === 0 ? <p className="text-sm text-gray-400 text-center py-8">Aucune intervention aujourd&apos;hui.</p> : (
                    <div className="space-y-2">
                      {tournee.map(r => {
                        const fait = r.statut === 'termine';
                        const passe = !fait && fin(r) <= now;
                        const st = fait ? { t: 'Terminé', fg: '#4B5563', bg: '#F1F2F4' }
                          : passe ? { t: 'À clôturer', fg: AMBRE, bg: '#FFF4DC' }
                          : debut(r) <= now ? { t: 'En cours', fg: TEAL, bg: '#E6F2F3' } : { t: 'À venir', fg: '#1D4ED8', bg: '#E8F0FE' };
                        const a = adresse(r);
                        return (
                          <div key={r.id} className="flex items-center gap-2">
                            <Link href={lienRdv(r)} className="flex-1 min-w-0 flex items-center gap-3 border border-[#EEF0EE] rounded-xl px-3 py-2.5 hover:bg-gray-50">
                              <div className="w-12 flex-shrink-0">
                                <p className="text-sm font-bold text-[#1E2025]">{hm(debut(r))}</p>
                                <p className="text-[11px] text-gray-500">{r.duree_minutes ?? 60} min</p>
                              </div>
                              <PhotoAnimal url={photo(r)} />
                              <div className="flex-1 min-w-0">
                                <p className="text-sm font-bold text-[#1E2025] truncate">{nomAnimal(r)} · {nomClient(r)}</p>
                                <p className="text-xs text-gray-500 truncate">{r.motif?.trim() || 'Intervention'}</p>
                                <p className="text-xs truncate" style={{ color: a || r.lieu_lat != null ? '#6B7280' : AMBRE }}>{a ?? (r.lieu_lat != null ? 'Position enregistrée' : 'Adresse non renseignée')}</p>
                              </div>
                              <Badge texte={st.t} fg={st.fg} bg={st.bg} />
                            </Link>
                            {!fait && (a || r.lieu_lat != null) && (
                              <ItineraireMenu lat={r.lieu_lat} lng={r.lieu_lng} adresse={r.lieu} className="w-9 h-9 rounded-full border border-[#E5E8E6] flex items-center justify-center text-[#0C5C6C]">
                                <Icone nom="pin" taille={16} />
                              </ItineraireMenu>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  )}
                </Section>

                <Section titre="Ferrures à renouveler" icone={<Icone nom="renouveler" taille={18} />} compteur={renouveler.length}
                  action={
                    <label className="text-xs text-gray-500 flex items-center gap-1.5">
                      Toutes les
                      <select value={cycle} onChange={e => changerCycle(Number(e.target.value))}
                        className="border border-[#E5E8E6] rounded-lg px-1.5 py-1 text-sm font-semibold text-[#1E2025] bg-white">
                        {Array.from({ length: 25 }, (_, i) => i + 2).map(n => <option key={n} value={n}>{n}</option>)}
                      </select>
                      semaines
                    </label>
                  }>
                  {renouveler.length === 0 ? (
                    <p className="text-sm text-gray-400 text-center py-6">Aucun cheval à revoir dans les 7 prochains jours.</p>
                  ) : (
                    <div className="space-y-1">
                      {renouveler.slice(0, 8).map(({ r, ech, ecart }) => (
                        <div key={r.id} className="flex items-center gap-2 py-1.5">
                          <PhotoAnimal url={photo(r)} taille={32} />
                          <div className="flex-1 min-w-0">
                            <p className="text-[13px] font-bold text-[#1E2025] truncate">{nomAnimal(r)} · {nomClient(r)}</p>
                            <p className="text-[11.5px] text-gray-500 truncate">{[r.motif?.trim() || 'Intervention', `le ${jm(debut(r))}`, `à revoir le ${jm(ech)}`].join(' · ')}</p>
                          </div>
                          <span className={`text-[11.5px] font-semibold whitespace-nowrap ${ecart < 0 ? 'text-red-600' : 'text-gray-500'}`}>
                            {ecart < 0 ? `En retard de ${-ecart} j` : ecart === 0 ? "Aujourd'hui" : `Dans ${ecart} j`}
                          </span>
                          <Link href={programmer(r)} className="text-xs font-bold text-white rounded-lg px-2.5 py-1.5" style={{ background: TEAL }}>Programmer</Link>
                        </div>
                      ))}
                      {renouveler.length > 8 && <p className="text-xs text-gray-500 pt-1">et {renouveler.length - 8} autre{renouveler.length - 8 > 1 ? 's' : ''}</p>}
                    </div>
                  )}
                </Section>
              </div>

              <div className="space-y-5">
                <Section titre="Demandes en attente" icone={<Icone nom="cloche" taille={18} />} compteur={demandes.length}
                  action={demandes.length ? <Link href="/mes-rdv?onglet=demandes" className="text-sm font-bold" style={{ color: TEAL }}>Voir toutes</Link> : undefined}>
                  {demandes.length === 0 ? <p className="text-sm text-gray-400">Aucune demande à traiter.</p> : demandes.slice(0, 4).map(r => (
                    <Link key={r.id} href={lienRdv(r)} className="flex items-center gap-2 py-1.5 hover:bg-gray-50 rounded-lg">
                      <PhotoAnimal url={photo(r)} taille={32} />
                      <div className="flex-1 min-w-0">
                        <p className="text-[13px] font-bold text-[#1E2025] truncate">{nomAnimal(r)} · {nomClient(r)}</p>
                        <p className="text-[11.5px] text-gray-500 truncate">{[r.motif?.trim() || 'Rendez-vous', `le ${jm(debut(r))} à ${hm(debut(r))}`].join(' · ')}</p>
                      </div>
                      <span className="text-[11.5px] font-bold whitespace-nowrap" style={{ color: TEAL }}>Répondre</span>
                    </Link>
                  ))}
                </Section>

                <Section titre="Interventions à clôturer" icone={<Icone nom="valide" taille={18} />} compteur={aCloturer.length}
                  action={aCloturer.length > 4 ? <Link href="/mes-rdv?onglet=a_venir" className="text-sm font-bold" style={{ color: TEAL }}>Voir toutes</Link> : undefined}>
                  {aCloturer.length === 0 ? <p className="text-sm text-gray-400">Toutes les interventions passées sont clôturées.</p> : aCloturer.slice(0, 4).map(r => (
                    <Link key={r.id} href={lienRdv(r)} className="flex items-center gap-2 py-1.5 hover:bg-gray-50 rounded-lg">
                      <PhotoAnimal url={photo(r)} taille={32} />
                      <div className="flex-1 min-w-0">
                        <p className="text-[13px] font-bold text-[#1E2025] truncate">{nomAnimal(r)} · {nomClient(r)}</p>
                        <p className="text-[11.5px] text-gray-500 truncate">{[r.motif?.trim() || 'Intervention', `le ${jm(debut(r))} à ${hm(debut(r))}`].join(' · ')}</p>
                      </div>
                      <span className="text-[11.5px] font-bold whitespace-nowrap" style={{ color: TEAL }}>Clôturer</span>
                    </Link>
                  ))}
                </Section>
              </div>
            </div>

            <Section titre="Accès rapides" icone={<Icone nom="eclair" taille={18} />}>
              <div className="grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-7 gap-2">
                <Tuile href="/mes-rdv?nouveau=1" icone="plus" label="Nouveau rendez-vous" />
                <Tuile href="/mes-patients" icone="patte" label="Mes équidés suivis" teinte={VERT} />
                <Tuile href="/marechal-ferrant/devis" icone="crayon" label="Devis" teinte={BRUN} />
                <Tuile href="/marechal-ferrant/contrat" icone="document" label="Mes contrats" teinte={AMBRE} />
                <Tuile href="/elevage/facturation" icone="facture" label="Facturation" teinte={VERT} />
                <Tuile href="/messages" icone="message" label="Messages" />
                <Tuile href="/marechal-ferrant/abonnement" icone="etoile" label="Mon abonnement" teinte={AMBRE} />
              </div>
            </Section>
          </>
        )}
      </div>
    </div>
  );
}
