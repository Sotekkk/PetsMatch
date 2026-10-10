'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { typeFromMotif } from '@/lib/agenda-type';

import TuilesSanteVet from '@/components/dashboard/TuilesSanteVet';
import { Kpi, EnteteAccueil, Puce, Tuile, TitreRubrique, Icone, BORDURE, OMBRE } from '@/components/dashboard/kit';
// ── Types ──────────────────────────────────────────────────────────────────────

interface ProProfile {
  id: string;
  profile_type: string;
  nom: string;
  avatar_url: string | null;
  cat_pro: string;
}

interface PendingRdv {
  id: string;
  date_heure: string;
  motif: string | null;
  client_uid: string;
  client_profile_id?: string | null;
  animal_id: number | null;
}

interface UpcomingRdv {
  id: string;
  date_heure: string;
  motif: string | null;
  client_uid: string;
  animal_id: number | null;
  statut: string;
}

interface Patient {
  animal_id: number;
  id: string;
  status: string;
  animal: {
    id: number;
    nom: string;
    espece: string;
    race: string;
    photo_url: string | null;
  } | null;
}

interface LostAnimal {
  id: string;
  nom: string;
  espece: string;
  statut: string;
  photo_url: string | null;
  created_at: string;
}

function fmtDate(iso: string) {
  const d = new Date(iso);
  const today = new Date();
  const tomorrow = new Date(today); tomorrow.setDate(today.getDate() + 1);
  if (d.toDateString() === today.toDateString()) return "Aujourd'hui " + d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
  if (d.toDateString() === tomorrow.toDateString()) return 'Demain ' + d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
  return d.toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' }) + ' ' + d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
}

const TYPE_LABEL: Record<string, string> = {
  veterinaire: 'Vétérinaire', sante: 'Santé animale', education: 'Éducateur',
  garde: 'Pet Sitter', pension: 'Pension', toilettage: 'Toilettage',
  photographe: 'Photographe', marechal_ferrant: 'Maréchal-ferrant',
  taxi_animalier: 'Taxi animalier',
};

// ── Main component ─────────────────────────────────────────────────────────────

export default function ProDashboard({ profile, profileId }: { profile: ProProfile; profileId: string }) {
  const { user, userData } = useAuth();
  const uid = user?.uid ?? '';

  const [pendingRdvs, setPendingRdvs] = useState<PendingRdv[]>([]);
  const [upcomingRdvs, setUpcomingRdvs] = useState<UpcomingRdv[]>([]);
  const [patients, setPatients] = useState<Patient[]>([]);
  const [lostAnimals, setLostAnimals] = useState<LostAnimal[]>([]);
  const [clientNames, setClientNames] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [savingRdv, setSavingRdv] = useState<string | null>(null);
  const [logementsDispo, setLogementsDispo] = useState(0);
  const [logementsTotal, setLogementsTotal] = useState(0);
  const [pensionnairesCount, setPensionnairesCount] = useState(0);
  const [rdvTodayCount, setRdvTodayCount] = useState(0);

  const catPro = profile.profile_type ?? profile.cat_pro ?? '';
  const isVet  = catPro === 'veterinaire' || catPro === 'sante';
  const isPension = catPro === 'pension';
  const isEducation = catPro === 'education';
  const isGarde = catPro === 'garde';
  const todayIso = new Date().toISOString().slice(0, 10);
  const rdvToday = upcomingRdvs.filter(r => (r.date_heure ?? '').slice(0, 10) === todayIso).length;
  const abonnementHref = catPro === 'veterinaire' ? '/veterinaire/abonnement' : '/sante/abonnement';
  const name   = profile.nom || userData?.firstname || 'Mon cabinet';
  const avatar = profile.avatar_url ?? userData?.profilePictureUrlElevage ?? userData?.profilePictureUrl ?? null;

  // Libellé "clients" selon la profession
  const clientsLabel = isVet ? 'Mes patients'
    : catPro === 'marechal_ferrant' ? 'Mes équidés suivis'
    : catPro === 'education' ? 'Mes élèves'
    : isPension ? 'Pensionnaires'
    : 'Animaux suivis';

  useEffect(() => {
    if (!uid) return;
    async function load() {
      const now = new Date().toISOString();
      const future = new Date(Date.now() + 90 * 86400000).toISOString();

      const profileFilter = profileId
        ? `pro_profile_id.eq.${profileId}`
        : 'pro_profile_id.is.null,pro_profile_id.eq.';

      const [lostRes, pendRes, upRes] = await Promise.all([
        supabase.from('animaux_perdus').select('id, nom, espece, statut, photo_url, created_at')
          .order('created_at', { ascending: false }).limit(4),
        supabase.from('rdv').select('id, date_heure, motif, client_uid, client_profile_id, animal_id')
          .eq('pro_uid', uid).in('statut', ['demande', 'contre_proposition'])
          .or(profileFilter).order('date_heure').limit(5),
        supabase.from('rdv').select('id, date_heure, motif, client_uid, animal_id, statut')
          .eq('pro_uid', uid).eq('statut', 'confirme')
          .or(profileFilter)
          .gte('date_heure', now).lte('date_heure', future).order('date_heure').limit(5),
      ]);

      setPendingRdvs((pendRes.data ?? []) as PendingRdv[]);
      setUpcomingRdvs((upRes.data ?? []) as UpcomingRdv[]);
      setLostAnimals((lostRes.data ?? []) as LostAnimal[]);

      // Accès animaux clients — même logique que /mes-patients : tout accès non
      // révoqué + les animaux des RDV confirmés/terminés sans accès explicite.
      if (profileId) {
        const { data: grantRows } = await supabase
          .from('animal_access')
          .select('id, animal_id, statut, granted_at')
          .eq('pro_profile_id', profileId)
          .neq('statut', 'revoked')
          .order('granted_at', { ascending: false });
        const seen = new Set((grantRows ?? []).map((g: { animal_id: string }) => g.animal_id));
        const { data: rdvRows } = await supabase
          .from('rdv')
          .select('animal_id')
          .eq('pro_uid', uid)
          .eq('pro_profile_id', profileId)
          .in('statut', ['confirme', 'termine'])
          .not('animal_id', 'is', null);
        const extra = [...new Set((rdvRows ?? [])
          .map((r: { animal_id: string }) => r.animal_id)
          .filter((id: string) => id && !seen.has(id)))]
          .map(id => ({ id: `rdv-${id}`, animal_id: id, statut: 'active' as string }));
        const allGrants = [...(grantRows ?? []), ...extra].slice(0, 6);
        if (allGrants.length > 0) {
          const ids = allGrants.map(g => g.animal_id).filter(Boolean);
          const { data: animalRows } = await supabase
            .from('animaux')
            .select('id, nom, espece, race, photo_url')
            .in('id', ids);
          const animalMap = new Map((animalRows ?? []).map((a: { id: string }) => [a.id, a]));
          setPatients(allGrants.map(g => ({
            id: g.id, animal_id: g.animal_id, status: g.statut,
            animal: animalMap.get(g.animal_id) ?? null,
          })) as unknown as Patient[]);
        }
      }

      // Load client names
      const allUids = [...new Set([
        ...(pendRes.data ?? []).map((r: { client_uid: string }) => r.client_uid),
        ...(upRes.data ?? []).map((r: { client_uid: string }) => r.client_uid),
      ])];
      if (allUids.length > 0) {
        const { data: usersData } = await supabase
          .from('user_profiles_complet').select('uid, firstname, lastname')
          .in('uid', allUids).eq('is_main', true);
        const names: Record<string, string> = {};
        for (const u of (usersData ?? [])) {
          const rec = u as { uid: string; firstname?: string; lastname?: string };
          names[rec.uid] = [rec.firstname, rec.lastname].filter(Boolean).join(' ') || 'Client';
        }
        setClientNames(names);
      }

      setLoading(false);
    }
    load();
  }, [uid, profileId, isVet]);

  useEffect(() => {
    if (!uid || !isPension) return;
    async function loadDispo() {
      const todayStr = new Date().toISOString().slice(0, 10);
      const todayStart = `${todayStr}T00:00:00`;
      const todayEnd = `${todayStr}T23:59:59`;
      const [{ data: logements }, { data: actives }, { data: rdvToday }] = await Promise.all([
        supabase.from('enclos_chenil').select('id, capacite').eq('uid_eleveur', uid),
        // Séjours réellement en cours aujourd'hui : statut actif + déjà arrivé
        supabase.from('pension_entrees').select('logement_id').eq('pro_uid', uid).eq('statut', 'en_pension').lte('date_entree', todayStr),
        supabase.from('rdv').select('id').eq('pro_uid', uid)
          .in('statut', ['demande', 'confirme', 'contre_proposition'])
          .gte('date_heure', todayStart).lte('date_heure', todayEnd),
      ]);
      setPensionnairesCount((actives ?? []).length);
      setRdvTodayCount((rdvToday ?? []).length);
      const occupePerLogement: Record<string, number> = {};
      for (const e of (actives ?? [])) {
        if (e.logement_id) occupePerLogement[e.logement_id] = (occupePerLogement[e.logement_id] ?? 0) + 1;
      }
      let dispo = 0, total = 0;
      for (const l of (logements ?? [])) {
        const capacite = l.capacite ?? 1;
        const occupe = occupePerLogement[l.id] ?? 0;
        total += capacite;
        dispo += Math.max(0, capacite - occupe);
      }
      setLogementsDispo(dispo);
      setLogementsTotal(total);
    }
    loadDispo();
  }, [uid, isPension]);

  async function confirmRdv(rdv: PendingRdv) {
    setSavingRdv(rdv.id);
    await supabase.from('rdv').update({ statut: 'confirme' }).eq('id', rdv.id);
    await supabase.from('agenda_events').insert({
      uid,
      titre: `RDV ${clientNames[rdv.client_uid] || 'Client'}${rdv.motif ? ` — ${rdv.motif}` : ''}`,
      type: typeFromMotif(rdv.motif),
      date_debut: rdv.date_heure,
      rdv_id: rdv.id,
      pro_profile_id: profileId,
    });
    await supabase.from('notifications').insert({
      uid: rdv.client_uid,
      type: 'rdv_confirme',
      title: 'RDV confirmé',
      body: `Votre rendez-vous du ${fmtDate(rdv.date_heure)} a été confirmé.`,
      ...(rdv.client_profile_id ? { profile_id: rdv.client_profile_id } : {}),
      data: { rdv_id: rdv.id },
      read: false,
    });
    setPendingRdvs(p => p.filter(r => r.id !== rdv.id));
    setUpcomingRdvs(p => [...p, { ...rdv, statut: 'confirme' }].sort((a, b) => a.date_heure.localeCompare(b.date_heure)));
    setSavingRdv(null);
  }

  async function rejectRdv(rdv: PendingRdv) {
    setSavingRdv(rdv.id);
    await supabase.from('rdv').update({ statut: 'refuse' }).eq('id', rdv.id);
    await supabase.from('notifications').insert({
      uid: rdv.client_uid,
      type: 'rdv_refuse',
      title: 'RDV refusé',
      body: `Votre demande de rendez-vous du ${fmtDate(rdv.date_heure)} a été refusée.`,
      ...(rdv.client_profile_id ? { profile_id: rdv.client_profile_id } : {}),
      data: { rdv_id: rdv.id },
      read: false,
    });
    setPendingRdvs(p => p.filter(r => r.id !== rdv.id));
    setSavingRdv(null);
  }

  return (
    <div className="min-h-screen bg-[#F6F7F5]" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="max-w-4xl mx-auto px-4 pt-5 sm:pt-8">
        <EnteteAccueil
          nom={name}
          avatar={avatar}
          surTitre="Bonjour,"
          statut={<Puce texte={TYPE_LABEL[catPro] ?? catPro} fg="#0C5C6C" bg="#E8F4F6" />}
        />

        {/* Stats rapides */}
        <div className="grid grid-cols-3 gap-3 sm:gap-4 mt-4">
          {isPension ? (
            <>
              <Kpi valeur={pensionnairesCount} label="Pensionnaires" icone="patte" href="/pension/registre" />
              <Kpi valeur={rdvTodayCount} label="RDV aujourd'hui" icone="calendrier" href="/agenda" />
              <Kpi valeur="Pension" label="Mon abonnement" icone="etoile" href="/pension/abonnement" />
            </>
          ) : isEducation ? (
            <>
              <Kpi valeur={rdvToday} label="RDV aujourd'hui" icone="calendrier" href="/education/planning" />
              <Kpi valeur={upcomingRdvs.length} label="RDV à venir" icone="horloge" href="/mes-rdv" />
              <Kpi valeur="Éducateur" label="Ma formule" icone="etoile" href="/education/abonnement" />
            </>
          ) : isVet ? (
            <>
              <Kpi valeur={patients.length} label="Patients" icone="stetho" href="/mes-patients" />
              <Kpi valeur={rdvToday} label="RDV aujourd'hui" icone="calendrier" href="/mes-rdv" />
              <Kpi valeur={TYPE_LABEL[catPro] ?? 'Pro'} label="Mon forfait" icone="etoile" href={abonnementHref} />
            </>
          ) : (
            <>
              <Kpi valeur={pendingRdvs.length} label="En attente" icone="horloge" />
              <Kpi valeur={upcomingRdvs.length} label="RDV à venir" icone="calendrier" />
              <Kpi valeur={patients.length} label="Animaux suivis" icone="patte" />
            </>
          )}
        </div>
      </div>

      <div className="max-w-4xl mx-auto px-4 py-6 space-y-6">

        {/* Disponibilité logements (pension) */}
        {isPension && logementsTotal > 0 && (
          <Link href="/pension/planning"
            className={`block bg-white rounded-2xl p-4 hover:shadow-md transition-shadow ${OMBRE}`} style={{ border: `1px solid ${BORDURE}` }}>
            <div className="flex items-center gap-3">
              <span className="w-10 h-10 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center flex-shrink-0"><Icone nom="logement" /></span>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-bold text-[#1F2A2E]">{logementsDispo} / {logementsTotal} places disponibles</p>
                <div className="w-full h-1.5 bg-gray-100 rounded-full mt-1.5 overflow-hidden">
                  <div className="h-full rounded-full"
                    style={{
                      width: `${logementsTotal === 0 ? 0 : ((logementsTotal - logementsDispo) / logementsTotal) * 100}%`,
                      backgroundColor: logementsDispo === 0 ? '#F97316' : '#6E9E57',
                    }} />
                </div>
              </div>
              <Icone nom="fleche" taille={18} className="text-gray-400" />
            </div>
          </Link>
        )}

        {/* Accès rapides — santé / vétérinaire : miroir de l'appli (TuilesSanteVet) */}
        {(catPro === 'sante' || catPro === 'veterinaire') ? (
          <TuilesSanteVet catPro={catPro} uid={uid ?? ''} profileId={profileId} abonnementHref={abonnementHref} />
        ) : (
        <div>
          <TitreRubrique titre="Accès rapide" />
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            <Tuile href="/agenda" icone="calendrier" label="Mon agenda" />
            <Tuile href="/mes-rdv" icone="calendrier" label="Gérer les RDV" />
            <Tuile href="/pro/creneaux" icone="horloge" label="Mes créneaux" />
            <Tuile href="/messages" icone="message" label="Messages" />
            {isEducation && (
              <>
                <Tuile href="/mes-patients" icone="patte" label="Mes élèves" />
                <Tuile href="/education/bibliotheque" icone="exercice" label="Bibliothèque d'exercices" />
              </>
            )}
            {isVet && (
              <>
                <Tuile href="/mes-patients" icone="patte" label="Mes patients" />
                {catPro === 'sante' && (
                  <>
                    <Tuile href="/sante/suivis" icone="suivi" label="Mes suivis" />
                    <Tuile href="/sante/contrat" icone="document" label="Mes contrats" />
                  </>
                )}
                <Tuile href="/elevage/facturation" icone="facture" label="Facturation" />
                <Tuile href={abonnementHref} icone="etoile" label="Mon abonnement" />
              </>
            )}
            {isGarde && (
              <>
                <Tuile href="/garde/registre" icone="livre" label="Registre des visites" />
                <Tuile href="/garde/cles" icone="cle" label="Gestion des clés" />
                <Tuile href="/garde/devis" icone="crayon" label="Devis" />
                <Tuile href="/garde/tarifs-clients" icone="euro" label="Tarifs clients" />
                <Tuile href="/garde/abonnement" icone="etoile" label="Mon abonnement" />
              </>
            )}
          </div>
        </div>
        )}

        {/* RDV en attente */}
        {(loading || pendingRdvs.length > 0) && (
          <div>
            <TitreRubrique titre={`RDV en attente${!loading ? ` (${pendingRdvs.length})` : ''}`} lien="/mes-rdv" />
            {loading ? (
              <div className="bg-white rounded-2xl border border-[#E5E8E6] p-6 flex justify-center">
                <div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
              </div>
            ) : pendingRdvs.length === 0 ? null : (
              <div className="space-y-2">
                {pendingRdvs.map(rdv => (
                  <div key={rdv.id} className={`bg-white rounded-2xl px-4 py-3 ${OMBRE}`} style={{ border: '1px solid #F3D9A4' }}>
                    <div className="flex items-center justify-between mb-2">
                      <div>
                        <p className="font-semibold text-sm text-[#1F2A2E]">{clientNames[rdv.client_uid] ?? '…'}</p>
                        <p className="text-xs text-gray-500">
                          {fmtDate(rdv.date_heure)}{rdv.motif ? ` · ${rdv.motif}` : ''}
                        </p>
                      </div>
                      <span className="flex-shrink-0 ml-2"><Puce texte="En attente" fg="#B45309" bg="#FEF3C7" point /></span>
                    </div>
                    <div className="flex gap-2">
                      <button onClick={() => confirmRdv(rdv)} disabled={savingRdv === rdv.id}
                        className="flex-1 text-xs font-semibold py-1.5 rounded-xl bg-[#0C5C6C] text-white hover:bg-[#0a4a5a] disabled:opacity-50 transition-colors">
                        Confirmer
                      </button>
                      <button onClick={() => rejectRdv(rdv)} disabled={savingRdv === rdv.id}
                        className="flex-1 text-xs font-semibold py-1.5 rounded-xl border border-red-200 text-red-500 hover:bg-red-50 disabled:opacity-50 transition-colors">
                        Refuser
                      </button>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* Prochains RDV confirmés */}
        <div>
          <TitreRubrique titre="Prochains RDV" lien="/agenda" libelleLien="Agenda" />
          {loading ? (
            <div className="bg-white rounded-2xl border border-[#E5E8E6] p-6 flex justify-center">
              <div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
            </div>
          ) : upcomingRdvs.length === 0 ? (
            <div className="bg-white rounded-2xl border border-[#E5E8E6] p-6 text-center">
              <span className="w-11 h-11 mx-auto mb-2 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center"><Icone nom="boite" /></span>
              <p className="text-sm text-gray-400">Aucun RDV confirmé à venir</p>
              <Link href="/pro/creneaux" className="text-xs text-[#0C5C6C] font-medium hover:underline mt-1 inline-block">
                Configurer mes créneaux →
              </Link>
            </div>
          ) : (
            <div className="space-y-2">
              {upcomingRdvs.map(rdv => (
                <div key={rdv.id} className={`bg-white rounded-2xl px-4 py-3 flex items-center gap-3 ${OMBRE}`}
                  style={{ border: `1px solid ${BORDURE}` }}>
                  <span className="w-10 h-10 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center flex-shrink-0"><Icone nom="calendrier" taille={18} /></span>
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-sm text-[#1F2A2E] truncate">{clientNames[rdv.client_uid] ?? '…'}</p>
                    <p className="text-xs text-gray-500">{fmtDate(rdv.date_heure)}{rdv.motif ? ` · ${rdv.motif}` : ''}</p>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Clients / patients — pour TOUS les profils pro */}
        <div>
          <TitreRubrique titre={clientsLabel} lien="/mes-patients" />
          {loading ? (
            <div className="bg-white rounded-2xl border border-[#E5E8E6] p-6 flex justify-center">
              <div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
            </div>
          ) : patients.length === 0 ? (
            <div className="bg-white rounded-2xl border border-[#E5E8E6] p-6 text-center">
              <span className="w-11 h-11 mx-auto mb-2 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center"><Icone nom="patte" /></span>
              <p className="text-sm text-gray-400">Aucun animal suivi pour l&apos;instant</p>
              <p className="text-xs text-gray-300 mt-1">Les propriétaires peuvent vous accorder l&apos;accès depuis la fiche de leur animal</p>
            </div>
          ) : (
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
              {patients.map(p => {
                const animal = p.animal;
                if (!animal) return null;
                return (
                  <Link key={p.id} href={`/mes-patients/${animal.id}`}
                    className={`bg-white rounded-2xl p-3 hover:shadow-md transition-shadow ${OMBRE}`} style={{ border: `1px solid ${BORDURE}` }}>
                    <div className="flex items-center gap-2">
                      <div className="w-10 h-10 rounded-xl overflow-hidden bg-[#E8F4F6] text-[#0C5C6C] flex-shrink-0 flex items-center justify-center">
                        {animal.photo_url
                          ? <Image src={animal.photo_url} alt="" width={40} height={40} className="object-cover w-full h-full" />
                          : <Icone nom="patte" taille={18} />
                        }
                      </div>
                      <div className="min-w-0">
                        <p className="font-semibold text-sm text-[#1F2A2E] truncate">{animal.nom}</p>
                        <p className="text-xs text-gray-500 truncate">{animal.race || animal.espece}</p>
                      </div>
                    </div>
                    {p.status === 'active_write' && (
                      <span className="mt-2 text-[10px] font-semibold text-[#2F7D3A] bg-[#EAF5EC] border border-[#2F7D3A]/15 px-1.5 py-0.5 rounded-full block text-center">Accès écriture</span>
                    )}
                  </Link>
                );
              })}
            </div>
          )}
        </div>

        {/* Animaux perdus */}
        <div>
          <TitreRubrique titre="Animaux perdus / trouvés" lien="/animaux-perdus" />
          {lostAnimals.length === 0 ? (
            <Link href="/animaux-perdus" className={`bg-white rounded-2xl p-4 flex items-center gap-3 hover:shadow-md transition-shadow ${OMBRE}`} style={{ border: `1px solid ${BORDURE}` }}>
              <span className="w-10 h-10 rounded-full bg-[#E8F4F6] text-[#0C5C6C] flex items-center justify-center flex-shrink-0"><Icone nom="recherche" /></span>
              <p className="text-sm text-gray-500">Consulter les alertes animaux perdus</p>
            </Link>
          ) : (
            <div className="grid grid-cols-2 gap-3">
              {lostAnimals.map(a => (
                <Link key={a.id} href={`/animaux-perdus/${a.id}`}
                  className={`bg-white rounded-2xl overflow-hidden hover:shadow-md transition-shadow ${OMBRE}`} style={{ border: `1px solid ${BORDURE}` }}>
                  <div className="h-24 bg-amber-50 relative overflow-hidden">
                    {a.photo_url
                      ? <Image src={a.photo_url} alt="" fill className="object-cover" />
                      : <div className="absolute inset-0 flex items-center justify-center text-amber-700"><Icone nom="recherche" taille={28} /></div>
                    }
                    <span className={`absolute top-2 right-2 text-[10px] font-bold px-1.5 py-0.5 rounded-full ${
                      a.statut === 'perdu' ? 'bg-red-500 text-white' : 'bg-green-500 text-white'
                    }`}>
                      {a.statut === 'perdu' ? 'PERDU' : 'TROUVÉ'}
                    </span>
                  </div>
                  <div className="p-2">
                    <p className="font-semibold text-xs text-[#1F2A2E] truncate">{a.nom || 'Inconnu'}</p>
                    <p className="text-[11px] text-gray-500">{a.espece}</p>
                  </div>
                </Link>
              ))}
            </div>
          )}
        </div>

      </div>
    </div>
  );
}
