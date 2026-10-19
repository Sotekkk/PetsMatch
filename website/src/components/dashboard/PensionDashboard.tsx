'use client';
// Accueil pension : poste de pilotage du jour. Données réelles et modules
// EXISTANTS uniquement : séjours (pension_entrees), hébergements
// (enclos_chenil), tâches (taches_elevage, profil_source 'pension'), journal
// (pension_updates). Miroir appli : lib/pages/pro/pension_dashboard.dart.
import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { apiFetch } from '@/lib/api-fetch';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import ArriveeDepartModal, { type SejourPension } from '@/components/pension/ArriveeDepartModal';
import { Kpi, Section, Badge, PhotoAnimal, EnteteAccueil, Tuile, Icone } from '@/components/dashboard/kit';

const TEAL = '#0C5C6C';
const VERT = '#2E7D5E';
const AMBRE = '#D97706';
const ROUGE = '#B3261E';
const VIOLET = '#7B5EA7';

interface Sejour extends SejourPension {
  date_entree: string; date_sortie_prevue: string | null; statut: string; pro_profile_id?: string | null;
  arrivee_reelle_le?: string | null;
}
interface Demande { id: string; animal_id: string; animal_nom: string | null; nouveau_pensionnaire?: boolean | null; hebergement?: string | null; date_arrivee: string; date_depart: string; essai_date: string | null; message: string | null }
interface Logement { id: string; nom: string; capacite: number | null }
interface Tache { id: string; titre: string | null; date: string; animal_id: string | null; animal_nom: string | null }
interface Animal { id: string; nom: string | null; photo_url: string | null }

const iso = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const jm = (s?: string | null) => s ? new Date(s).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' }) : '';
const hm = (s: string) => new Date(s).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });

export default function PensionDashboard({ nom, avatar }: { nom: string; avatar: string | null }) {
  const { user } = useAuth();
  const uid = user?.uid ?? '';
  const pid = useActiveProfile();
  const [loading, setLoading] = useState(true);
  const [sejours, setSejours] = useState<Sejour[]>([]);
  const [logements, setLogements] = useState<Logement[]>([]);
  const [taches, setTaches] = useState<Tache[]>([]);
  const [incidents, setIncidents] = useState<{ id: string; note: string | null }[]>([]);
  const [animaux, setAnimaux] = useState<Record<string, Animal>>({});
  const [action, setAction] = useState<{ sejour: Sejour; mode: 'arrivee' | 'depart' } | null>(null);
  const [now, setNow] = useState(() => new Date());
  // Demandes de séjour des clients (à accepter / refuser).
  const [demandes, setDemandes] = useState<Demande[]>([]);
  const [decision, setDecision] = useState('');

  const charger = useCallback(async () => {
    if (!uid) return;
    const t = new Date();
    const jour = new Date(t.getFullYear(), t.getMonth(), t.getDate());
    let tq = supabase.from('taches_elevage').select('id, titre, date, animal_id, animal_nom').eq('profil_source', 'pension')
      .neq('statut', 'fait').lte('date', iso(jour));
    tq = pid ? tq.eq('eleveur_profile_id', pid) : tq.eq('uid_eleveur', uid);
    let dq = supabase.from('pension_demandes').select('id, animal_id, animal_nom, date_arrivee, date_depart, essai_date, message, nouveau_pensionnaire, hebergement')
      .eq('pro_uid', uid).eq('statut', 'demande');
    if (pid) dq = dq.eq('pro_profile_id', pid);
    const dRes = await dq.order('date_arrivee');
    setDemandes(dRes.error ? [] : (dRes.data ?? []) as Demande[]);
    const [sRes, lRes, tRes, iRes] = await Promise.all([
      supabase.from('pension_entrees').select('*').eq('pro_uid', uid).eq('statut', 'en_pension')
        .lte('date_entree', iso(new Date(jour.getTime() + 30 * 86400000))).order('date_entree'),
      supabase.from('enclos_chenil').select('id, nom, capacite').eq('uid_eleveur', uid).order('nom'),
      tq.order('date'),
      supabase.from('pension_updates').select('id, note').eq('pro_uid', uid).eq('incident', true)
        .gte('created_at', new Date(jour.getTime() - 2 * 86400000).toISOString()),
    ]);
    const s = ((sRes.data ?? []) as Sejour[]).filter(x => !pid || !x.pro_profile_id || x.pro_profile_id === pid);
    const ids = [...new Set(s.map(x => x.animal_id).filter(Boolean) as string[])];
    const { data: a } = ids.length ? await supabase.from('animaux').select('id, nom, photo_url').in('id', ids) : { data: [] };
    const an: Record<string, Animal> = {};
    for (const x of (a ?? []) as Animal[]) an[String(x.id)] = x;
    setSejours(s); setLogements((lRes.data ?? []) as Logement[]); setTaches((tRes.data ?? []) as Tache[]);
    setIncidents(iRes.error ? [] : (iRes.data ?? []) as { id: string; note: string | null }[]);
    setAnimaux(an); setNow(new Date()); setLoading(false);
  }, [uid, pid]);

  useEffect(() => {
    if (!uid) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    charger();
  }, [uid, charger]);

  async function decider(d: Demande, accepter: boolean, forcer = false) {
    let motif: string | null = null;
    if (!accepter) {
      motif = window.prompt('Motif pour le client (facultatif) : complet à ces dates…', '');
      if (motif === null) return;
    }
    setDecision(d.id);
    const r = await apiFetch('/api/pension/sejour', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'decider', demandeId: d.id, accepter, ...(motif ? { motif } : {}), ...(forcer ? { forcer: true } : {}) }) });
    const j = await r.json().catch(() => ({})) as { error?: string; complet?: boolean };
    setDecision('');
    // Hébergements pleins sur une partie du séjour : accepter quand même ?
    if (r.status === 409 && j.complet && accepter && !forcer) {
      if (window.confirm(`${j.error}\nAccepter quand même ce séjour ?`)) decider(d, true, true);
      return;
    }
    if (!r.ok) { window.alert(j.error ?? 'Action impossible'); return; }
    charger();
  }

  const jour = iso(now);
  const presents = sejours.filter(s => s.date_entree <= jour);
  const arrivees = sejours.filter(s => s.date_entree === jour);
  const departs = sejours.filter(s => s.date_sortie_prevue === jour);
  const aConfirmer = arrivees.filter(s => !s.arrivee_reelle_le);
  const aCloturer = sejours.filter(s => s.date_sortie_prevue && s.date_sortie_prevue < jour);
  const enRetard = taches.filter(t => t.date < jour);
  const nomA = (s: Sejour) => (s.animal_id && animaux[s.animal_id]?.nom) || s.animal_nom || 'Animal';
  const photo = (s: Sejour) => (s.animal_id ? animaux[s.animal_id]?.photo_url : null) ?? null;
  const logementNom = (s: Sejour) => logements.find(l => l.id === s.logement_id)?.nom ?? 'Sans hébergement attribué';
  const ficheHref = (s: Sejour) => s.animal_id ? `/pension/fiche/${s.animal_id}` : '/pension/registre';
  const occupes = new Set(presents.map(s => s.logement_id).filter(Boolean) as string[]);
  const reserves = new Set(sejours.filter(s => s.date_entree > jour && s.logement_id && !occupes.has(s.logement_id)).map(s => s.logement_id as string));
  const capacite = logements.reduce((t, l) => t + (l.capacite ?? 1), 0);
  const alertes = [
    ...aCloturer.map(s => ({ cle: `d${s.id}`, texte: `Départ prévu le ${jm(s.date_sortie_prevue)} non clôturé — ${nomA(s)}`, onClick: () => setAction({ sejour: s, mode: 'depart' }) })),
    ...(enRetard.length ? [{ cle: 'taches', texte: `${enRetard.length} tâche${enRetard.length > 1 ? 's' : ''} en retard (soins, traitements…)`, href: '/mes-taches' }] : []),
    ...incidents.map(i => ({ cle: `i${i.id}`, texte: `Incident signalé${i.note ? ` : ${i.note}` : ''}`, href: '/pension/registre' })),
  ];

  const ligneES = (s: Sejour, arrivee: boolean) => {
    const fait = arrivee && !!s.arrivee_reelle_le;
    return (
      <div key={`${arrivee ? 'a' : 'd'}${s.id}`} className="flex items-center gap-2.5 py-1.5">
        <span style={{ color: arrivee ? VERT : VIOLET }}><Icone nom="fleche" taille={16} /></span>
        <PhotoAnimal url={photo(s)} taille={32} />
        <Link href={ficheHref(s)} className="flex-1 min-w-0">
          <span className="block text-sm font-bold text-[#1E2025] truncate">{nomA(s)}</span>
          <span className="block text-xs text-gray-500 truncate">
            {[s.proprietaire_nom, logementNom(s), fait ? `arrivé à ${hm(s.arrivee_reelle_le!)}` : ''].filter(Boolean).join(' · ')}
          </span>
        </Link>
        {fait ? <Badge texte="Arrivé" fg={VERT} bg="#E7F3EC" /> : (
          <button onClick={() => setAction({ sejour: s, mode: arrivee ? 'arrivee' : 'depart' })}
            className="text-xs font-bold text-[#0C5C6C] whitespace-nowrap">{arrivee ? "Enregistrer l'arrivée" : 'Enregistrer le départ'}</button>
        )}
      </div>
    );
  };

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-6xl mx-auto px-4 py-5 space-y-5">
        <EnteteAccueil nom={nom} avatar={avatar} sousTitre="Pension animalière" avatarHref="/profil"
          actions={
            <span className="hidden sm:inline-flex items-center gap-2 text-sm text-[#1E2025] bg-white border border-[#E5E8E6] rounded-full px-3.5 py-2">
              <Icone nom="calendrier" taille={16} />
              <span className="first-letter:uppercase">{now.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}</span>
            </span>
          } />

        {loading ? (
          <div className="flex justify-center py-20"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>
        ) : (
          <>
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
              <Kpi valeur={presents.length} label="Animaux présents" icone="patte" href="/pension/registre?mouvement=presents" />
              <Kpi valeur={arrivees.length} label="Arrivées aujourd'hui" icone="fleche" teinte={VERT} actif={aConfirmer.length > 0} href="/pension/registre?mouvement=arrivees" />
              <Kpi valeur={departs.length} label="Départs aujourd'hui" icone="fleche" teinte={VIOLET} href="/pension/registre?mouvement=departs" />
              <Kpi valeur={logements.length ? occupes.size : presents.length}
                label={logements.length ? `Occupés / ${logements.length} hébergements` : 'Occupation (sans box)'}
                icone="logement" teinte={AMBRE} href="/pension/planning" />
            </div>
            {logements.length > 0 && capacite > 0 && (
              <p className="text-xs text-gray-500 -mt-2">{presents.length} animal{presents.length > 1 ? 'aux' : ''} pour une capacité de {capacite} place{capacite > 1 ? 's' : ''}</p>
            )}

            {demandes.length > 0 && (
              <Section titre="Demandes de séjour" icone={<Icone nom="calendrier" taille={18} />} compteur={demandes.length}>
                <div className="divide-y divide-gray-100">
                  {demandes.map(d => (
                    <div key={d.id} className="py-2.5 flex flex-wrap items-center gap-2">
                      <div className="flex-1 min-w-[180px]">
                        <p className="text-sm font-bold text-[#1E2025]">{d.animal_nom ?? 'Animal'}
                          {d.nouveau_pensionnaire === true && <span className="font-semibold text-xs text-[#D97706]"> · nouveau pensionnaire</span>}
                          {d.nouveau_pensionnaire === false && <span className="font-normal text-xs text-gray-500"> · déjà venu (selon le client)</span>}
                        </p>
                        <p className="text-xs text-gray-500">Du {jm(d.date_arrivee)} au {jm(d.date_depart)}{d.essai_date ? ` · essai le ${jm(d.essai_date)}` : ''}{d.hebergement === 'box' ? ' · box' : d.hebergement === 'pre' ? ' · pré' : ''}</p>
                        {d.message && <p className="text-xs text-gray-500 italic">« {d.message} »</p>}
                      </div>
                      <Link href={`/pension/fiche/${d.animal_id}`} className="text-xs font-semibold text-[#0C5C6C]">Fiche</Link>
                      <button disabled={decision === d.id} onClick={() => decider(d, false)} className="text-xs font-semibold text-gray-500 px-2 py-1">Refuser</button>
                      <button disabled={decision === d.id} onClick={() => decider(d, true)}
                        className="text-xs font-bold text-white rounded-full px-3 py-1.5 disabled:opacity-50" style={{ background: VERT }}>Accepter</button>
                    </div>
                  ))}
                </div>
              </Section>
            )}

            {alertes.length > 0 && (
              <Section titre="À traiter" icone={<Icone nom="cloche" taille={18} />} compteur={alertes.length}>
                <div className="space-y-1">
                  {alertes.slice(0, 5).map(a => 'href' in a && a.href ? (
                    <Link key={a.cle} href={a.href} className="flex items-center gap-2 py-1.5 text-sm text-[#1E2025]">
                      <span style={{ color: ROUGE }}>●</span><span className="flex-1">{a.texte}</span>
                    </Link>
                  ) : (
                    <button key={a.cle} onClick={'onClick' in a ? a.onClick : undefined} className="w-full text-left flex items-center gap-2 py-1.5 text-sm text-[#1E2025]">
                      <span style={{ color: ROUGE }}>●</span><span className="flex-1">{a.texte}</span>
                    </button>
                  ))}
                </div>
              </Section>
            )}

            <div className="grid lg:grid-cols-5 gap-5 items-start">
              <div className="lg:col-span-3 space-y-5">
                <Section titre="Arrivées et départs du jour" icone={<Icone nom="fleche" taille={18} />} compteur={arrivees.length + departs.length}
                  action={<Link href="/pension/entree-sortie" className="text-sm font-semibold text-[#0C5C6C] hover:underline">Entrées / sorties →</Link>}>
                  {arrivees.length + departs.length === 0
                    ? <p className="text-sm text-gray-400">Aucune arrivée ni aucun départ prévu aujourd&apos;hui.</p>
                    : <div>{arrivees.map(s => ligneES(s, true))}{departs.map(s => ligneES(s, false))}</div>}
                </Section>
                <Section titre="Animaux présents" icone={<Icone nom="patte" taille={18} />} compteur={presents.length}
                  action={<Link href="/pension/registre" className="text-sm font-semibold text-[#0C5C6C] hover:underline">Tous →</Link>}>
                  {presents.length === 0 ? <p className="text-sm text-gray-400">Aucun animal en pension.</p> : (
                    <div className="space-y-1">
                      {[...presents].sort((a, b) => (a.date_sortie_prevue ?? '9').localeCompare(b.date_sortie_prevue ?? '9')).slice(0, 8).map(s => {
                        const n = taches.filter(t => t.animal_id === s.animal_id).length;
                        return (
                          <Link key={s.id} href={ficheHref(s)} className="flex items-center gap-2.5 py-1.5 hover:bg-gray-50 rounded-lg">
                            <PhotoAnimal url={photo(s)} taille={36} />
                            <span className="flex-1 min-w-0">
                              <span className="block text-sm font-bold text-[#1E2025] truncate">{nomA(s)}</span>
                              <span className="block text-xs text-gray-500 truncate">{logementNom(s)}{s.date_sortie_prevue ? ` · départ le ${jm(s.date_sortie_prevue)}` : ''}</span>
                              {s.consignes_sejour && <span className="block text-xs font-semibold truncate" style={{ color: AMBRE }}>{s.consignes_sejour.split('\n')[0]}</span>}
                            </span>
                            {n > 0 && <Badge texte={`${n} tâche${n > 1 ? 's' : ''}`} fg={AMBRE} bg="#FFF4DC" />}
                          </Link>
                        );
                      })}
                    </div>
                  )}
                </Section>
              </div>
              <div className="lg:col-span-2 space-y-5">
                <Section titre="Tâches et soins à faire" icone={<Icone nom="valide" taille={18} />} compteur={taches.length}
                  action={<Link href="/mes-taches" className="text-sm font-semibold text-[#0C5C6C] hover:underline">Mes tâches →</Link>}>
                  {taches.length === 0 ? <p className="text-sm text-gray-400">Rien à faire pour l&apos;instant.</p> : (
                    <div className="space-y-1.5">
                      {taches.slice(0, 8).map(t => (
                        <p key={t.id} className="text-sm text-[#1E2025] flex items-center gap-2">
                          <span style={{ color: t.date < jour ? ROUGE : '#9CA3AF' }}>○</span>
                          <span className="flex-1">{[t.titre ?? 'Tâche', t.animal_nom].filter(Boolean).join(' · ')}</span>
                          {t.date < jour && <span className="text-[11px]" style={{ color: ROUGE }}>depuis le {jm(t.date)}</span>}
                        </p>
                      ))}
                    </div>
                  )}
                </Section>
                <Section titre="Occupation des hébergements" icone={<Icone nom="logement" taille={18} />}
                  action={<Link href="/pension/planning" className="text-sm font-semibold text-[#0C5C6C] hover:underline">Planning →</Link>}>
                  {logements.length === 0 ? (
                    <p className="text-sm text-gray-500">Pension sans box individuel : {presents.length} animal{presents.length > 1 ? 'aux' : ''} présent{presents.length > 1 ? 's' : ''}.</p>
                  ) : (
                    <div className="grid grid-cols-3 text-center">
                      {([['Disponibles', Math.max(0, logements.length - occupes.size - reserves.size), VERT], ['Occupés', occupes.size, TEAL], ['Réservés', reserves.size, AMBRE]] as const).map(([l, v, c]) => (
                        <div key={l}><p className="text-2xl font-bold" style={{ color: c }}>{v}</p><p className="text-xs text-gray-500">{l}</p></div>
                      ))}
                    </div>
                  )}
                </Section>
              </div>
            </div>

            <Section titre="Accès rapides" icone={<Icone nom="eclair" taille={18} />}>
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                <Tuile href="/pension/registre" icone="plus" label="Nouvelle réservation" />
                <Tuile href="/pension/planning" icone="calendrier" label="Planning des hébergements" />
                <Tuile href="/pension/entree-sortie" icone="fleche" label="Entrées / sorties" />
                <Tuile href="/pension/registre" icone="patte" label="Animaux présents" teinte={VERT} />
              </div>
            </Section>
          </>
        )}
      </div>
      {action && (
        <ArriveeDepartModal sejour={action.sejour} mode={action.mode} uid={uid}
          onClose={() => setAction(null)} onDone={() => { setAction(null); charger(); }} />
      )}
    </div>
  );
}
