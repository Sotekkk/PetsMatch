'use client';

import { useCallback, useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfileState } from '@/hooks/useActiveProfile';
import { geocodeAddress, distanceKm } from '@/lib/geocoding';

// Vitesse moyenne heuristique (à vol d'oiseau) + marge de sécurité — même
// principe que lib/pages/pro/education_reservation_page.dart (app), utilisé
// ici pour FILTRER les créneaux à domicile proposés.
const VITESSE_TRAJET_KMH = 30;
const MARGE_TRAJET_MIN = 15;

// Calendrier de réservation "intelligent" pour l'éducateur/comportementaliste
// (web) — remplace le modal RDV générique pour cat_pro === 'education' :
// la famille choisit un cours dans le catalogue du pro (prestations_education)
// puis un créneau dans une vraie vue semaine. Miroir de
// lib/pages/pro/education_reservation_page.dart (app) — même algorithme de
// calcul des créneaux disponibles.

interface Prestation {
  id: string; nom: string; description?: string | null;
  duree_minutes: number; prix?: number | null; bilan_requis: boolean; domicile_ok: boolean;
  lieu_adresse?: string | null; lieu_lat?: number | null; lieu_lng?: number | null;
  type?: 'individuel' | 'collectif' | null; capacite_max?: number | null;
}
// Séance de groupe déjà planifiée (cours collectif), rapprochée d'un créneau fixe.
type CoursSeance = { date_heure: string; coursId: string; capacite: number; inscrits: number };
interface Animal { id: number | string; nom: string; espece: string; }
interface Props {
  proUid: string;
  proProfileId: string | null;
  proName: string;
  catColor: string;
  onClose: () => void;
}

function toDateStr(d: Date) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
function mondayOf(d: Date) {
  const day = d.getDay(); // 0 = dimanche
  const diff = day === 0 ? -6 : 1 - day;
  const m = new Date(d);
  m.setDate(m.getDate() + diff);
  m.setHours(0, 0, 0, 0);
  return m;
}
const DAY_FMT = new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' });
const MONTH_FMT = new Intl.DateTimeFormat('fr-FR', { month: 'short', year: 'numeric' });

export default function EducationReservationModal({ proUid, proProfileId, proName, catColor, onClose }: Props) {
  const { user } = useAuth();
  const router = useRouter();
  const { id: activeProfileId, loaded: profileLoaded } = useActiveProfileState();

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [success, setSuccess] = useState(false);

  const [prestations, setPrestations] = useState<Prestation[]>([]);
  const [selectedPrestation, setSelectedPrestation] = useState<Prestation | null>(null);
  const [isFirstTime, setIsFirstTime] = useState(false);
  const [bilanRequis, setBilanRequis] = useState(true);

  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [selectedAnimalId, setSelectedAnimalId] = useState<number | string | null>(null);
  const [notes, setNotes] = useState('');

  // Profil du pro consulté, résolu une fois (fallback "is_main" si l'appelant
  // n'a pas passé proProfileId) — évite de filtrer créneaux/RDV/notif sur un
  // pro_profile_id vide, qui ne retourne/n'écrit jamais la bonne ligne.
  const [resolvedProfileId, setResolvedProfileId] = useState<string | null>(null);
  const [delaiMinH, setDelaiMinH] = useState(0); // délai mini de réservation imposé par le pro (heures)
  const [weekStart, setWeekStart] = useState(() => mondayOf(new Date()));
  // Chargement paresseux semaine par semaine (clé = lundi yyyy-MM-dd) — une
  // semaine ≈ 280 lignes, l'ancien fetch « 3 mois » était plafonné à 1000
  // (~4 semaines) par PostgREST.
  type Slot = { date: string; heure_debut: string; heure_fin: string; type_prestation: string | null; domicile_ok: boolean; trajet_origine: string | null };
  type RdvBlock = { date_heure: string; duree_minutes: number; lieu_lat: number | null; lieu_lng: number | null };
  const [slotsByWeek, setSlotsByWeek] = useState<Record<string, Slot[]>>({});
  const [rdvsByWeek, setRdvsByWeek] = useState<Record<string, RdvBlock[]>>({});
  const [coursByWeek, setCoursByWeek] = useState<Record<string, CoursSeance[]>>({});
  const [loadingWeeks, setLoadingWeeks] = useState<Record<string, boolean>>({});
  const [probedFirstDate, setProbedFirstDate] = useState<string | null | undefined>(undefined); // undefined = pas encore sondé

  // Trajet à domicile
  const [domicile, setDomicile] = useState(false);
  const [domicileChoiceMade, setDomicileChoiceMade] = useState(false);
  const [adresseDomicile, setAdresseDomicile] = useState('');
  const [geocodingDomicile, setGeocodingDomicile] = useState(false);
  const [domicileLatLng, setDomicileLatLng] = useState<{ lat: number; lng: number } | null>(null);
  const [origineDefaut, setOrigineDefaut] = useState('cabinet');
  const [cabinetLatLng, setCabinetLatLng] = useState<{ lat: number; lng: number } | null>(null);
  const [autreDomicileLatLng, setAutreDomicileLatLng] = useState<{ lat: number; lng: number } | null>(null);

  useEffect(() => {
    if (!user) { router.push('/connexion'); return; }
    if (!profileLoaded) return; // attend la lecture du profil actif (localStorage) avant de scoper les animaux
    (async () => {
      const cols = 'id, education_bilan_requis, delai_min_reservation_h, trajet_origine_defaut, autre_domicile_lat, autre_domicile_lng, latitude, longitude, lat, lng';
      const proRow = proProfileId
        ? await supabase.from('user_profiles').select(cols).eq('id', proProfileId).maybeSingle()
        : await supabase.from('user_profiles').select(cols).eq('uid', proUid).eq('is_main', true).maybeSingle();
      const proData = proRow.data as {
        id?: string; education_bilan_requis?: boolean; delai_min_reservation_h?: number | null;
        trajet_origine_defaut?: string;
        autre_domicile_lat?: number; autre_domicile_lng?: number;
        latitude?: number; longitude?: number; lat?: number; lng?: number;
      } | null;
      // Le profil du pro consulté n'est pas forcément passé en paramètre
      // (lien sans ?profileId=...) — on retombe alors sur le profil "is_main"
      // résolu ci-dessus, pour ne jamais filtrer les créneaux/RDV sur un id vide.
      const profileId = proProfileId ?? proData?.id ?? '';
      setResolvedProfileId(profileId || null);
      const bReq = proData?.education_bilan_requis ?? true;
      setBilanRequis(bReq);
      setDelaiMinH(proData?.delai_min_reservation_h ?? 0);
      setOrigineDefaut(proData?.trajet_origine_defaut ?? 'cabinet');
      if (proData?.autre_domicile_lat != null && proData?.autre_domicile_lng != null) {
        setAutreDomicileLatLng({ lat: proData.autre_domicile_lat, lng: proData.autre_domicile_lng });
      }
      const cabLat = proData?.latitude ?? proData?.lat;
      const cabLng = proData?.longitude ?? proData?.lng;
      if (cabLat != null && cabLng != null) setCabinetLatLng({ lat: cabLat, lng: cabLng });

      const { data: priorRdv } = await supabase.from('rdv').select('id')
        .eq('client_uid', user.uid).eq('pro_uid', proUid).eq('pro_profile_id', profileId)
        .in('statut', ['confirme', 'termine']).limit(1);
      const firstTime = (priorRdv ?? []).length === 0;
      setIsFirstTime(firstTime);

      let pQ = supabase.from('prestations_education').select('id, nom, description, duree_minutes, prix, bilan_requis, domicile_ok, lieu_adresse, lieu_lat, lieu_lng, type, capacite_max')
        .eq('pro_uid', proUid).eq('actif', true);
      if (profileId) pQ = pQ.eq('pro_profile_id', profileId);
      const { data: pRows } = await pQ.order('ordre').order('created_at');
      let all = (pRows ?? []) as Prestation[];
      if (bReq && firstTime) {
        const bilans = all.filter(p => p.bilan_requis);
        if (bilans.length > 0) all = bilans;
      }
      setPrestations(all);

      // Animaux du client : profil actif d'abord (animaux.profile_id) PUIS
      // animaux_proprietes (source de vérité de la propriété courante — la
      // colonne animaux.profile_id est souvent null sur les vieux comptes,
      // cf. rdv_booking_page.dart _loadAnimaux).
      let directQ = supabase.from('animaux').select('id, nom, espece')
        .or(`uid_eleveur.eq.${user.uid},uid_proprietaire.eq.${user.uid}`);
      if (activeProfileId) directQ = directQ.eq('profile_id', activeProfileId);
      let ownQ = supabase.from('animaux_proprietes').select('animal_id')
        .eq('uid_proprio', user.uid).is('date_fin', null);
      if (activeProfileId) ownQ = ownQ.eq('profile_id_proprio', activeProfileId);
      const [{ data: directRows }, { data: ownRows }] = await Promise.all([directQ, ownQ]);
      const direct = (directRows ?? []) as Animal[];
      const directIds = new Set(direct.map(a => String(a.id)));
      const missingIds = [...new Set(((ownRows ?? []) as { animal_id: string }[]).map(r => r.animal_id))]
        .filter(id => id && !directIds.has(String(id)));
      let viaCession: Animal[] = [];
      if (missingIds.length > 0) {
        const { data: r2 } = await supabase.from('animaux').select('id, nom, espece').in('id', missingIds);
        viaCession = (r2 ?? []) as Animal[];
      }
      setAnimaux([...direct, ...viaCession].sort((a, b) => (a.nom ?? '').localeCompare(b.nom ?? '')));
      setLoading(false);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user, proUid, proProfileId, profileLoaded, activeProfileId]);

  const weekKeyOf = (d: Date) => toDateStr(mondayOf(d));
  // Cours collectif : créneaux fixes bout à bout + inscription à une séance
  // de groupe (capacité / liste d'attente) au lieu d'un RDV 1-pour-1.
  const isCollectif = selectedPrestation?.type === 'collectif';

  // Charge les séances de groupe d'une semaine + le nombre d'inscrits.
  const loadCoursWeek = useCallback(async (wk: string) => {
    const pid = resolvedProfileId;
    if (!pid) return;
    const [my, mm, md] = wk.split('-').map(Number);
    const monday = new Date(my, mm - 1, md);
    const sunday = new Date(my, mm - 1, md + 7);
    const { data: cRows } = await supabase.from('cours_collectifs')
      .select('id, date_heure, capacite_max')
      .eq('pro_uid', proUid).eq('pro_profile_id', pid).neq('statut', 'annule')
      .gte('date_heure', monday.toISOString()).lte('date_heure', sunday.toISOString());
    const cours = (cRows ?? []) as { id: string; date_heure: string; capacite_max: number | null }[];
    const ids = cours.map(c => c.id);
    const counts: Record<string, number> = {};
    if (ids.length > 0) {
      const { data: parts } = await supabase.from('cours_collectifs_participants')
        .select('cours_id').in('cours_id', ids).neq('statut', 'annule');
      for (const p of (parts ?? []) as { cours_id: string }[]) counts[p.cours_id] = (counts[p.cours_id] ?? 0) + 1;
    }
    setCoursByWeek(m => ({
      ...m,
      [wk]: cours.map(c => ({
        date_heure: c.date_heure, coursId: c.id,
        capacite: c.capacite_max ?? 6, inscrits: counts[c.id] ?? 0,
      })),
    }));
  }, [resolvedProfileId, proUid]);

  // Charge (une seule fois) créneaux + RDV de la semaine de `anyDay`.
  const loadWeek = useCallback(async (anyDay: Date) => {
    const pid = resolvedProfileId;
    if (!pid) return;
    const wk = weekKeyOf(anyDay);
    if (slotsByWeek[wk] || loadingWeeks[wk]) return;
    setLoadingWeeks(m => ({ ...m, [wk]: true }));
    const [my, mm, md] = wk.split('-').map(Number);
    const monday = new Date(my, mm - 1, md);
    const sunday = new Date(my, mm - 1, md + 6);
    const [{ data: slotRows }, { data: rdvRows }] = await Promise.all([
      supabase.from('creneaux_pro').select('date, heure_debut, heure_fin, type_prestation, domicile_ok, trajet_origine')
        .eq('pro_uid', proUid).eq('statut', 'disponible').eq('pro_profile_id', pid)
        .gte('date', toDateStr(monday)).lte('date', toDateStr(sunday))
        .order('date').order('heure_debut'),
      supabase.from('rdv').select('date_heure, duree_minutes, lieu_lat, lieu_lng')
        .eq('pro_uid', proUid).eq('pro_profile_id', pid)
        .in('statut', ['confirme', 'demande'])
        .gte('date_heure', monday.toISOString())
        .lte('date_heure', new Date(my, mm - 1, md + 7).toISOString()),
    ]);
    setSlotsByWeek(m => ({ ...m, [wk]: (slotRows ?? []) as Slot[] }));
    setRdvsByWeek(m => ({ ...m, [wk]: (rdvRows ?? []) as RdvBlock[] }));
    setLoadingWeeks(m => ({ ...m, [wk]: false }));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [resolvedProfileId, proUid, slotsByWeek, loadingWeeks]);

  // Sondage : 1re date (≥ aujourd'hui) avec une dispo compatible (non
  // collectif, + domicile si demandé). Puis positionne la semaine dessus.
  const goToFirstAvailableWeek = useCallback(async () => {
    const pid = resolvedProfileId;
    if (!pid) return;
    let q = supabase.from('creneaux_pro').select('date')
      .eq('pro_uid', proUid).eq('statut', 'disponible').eq('pro_profile_id', pid)
      .gte('date', toDateStr(new Date()));
    if (isCollectif) {
      q = q.eq('type_prestation', 'collectif');
    } else {
      q = q.or('type_prestation.is.null,type_prestation.neq.collectif');
      if (domicile) q = q.eq('domicile_ok', true);
    }
    const { data } = await q.order('date').limit(1);
    const first = (data ?? [])[0]?.date as string | undefined;
    setProbedFirstDate(first ?? null);
    if (first) {
      const [y, mo, dd] = first.split('-').map(Number);
      const m = mondayOf(new Date(y, mo - 1, dd));
      setWeekStart(w => (m.getTime() > w.getTime() ? m : w));
    }
  }, [resolvedProfileId, proUid, domicile, isCollectif]);

  // Charge la semaine visible dès qu'elle change (et au 1er affichage du calendrier).
  useEffect(() => {
    if (selectedPrestation && resolvedProfileId) {
      loadWeek(weekStart);
      if (isCollectif) loadCoursWeek(weekKeyOf(weekStart));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [weekStart, selectedPrestation, resolvedProfileId, loadWeek, loadCoursWeek, isCollectif]);

  // Au choix d'un cours / d'une option domicile : (re)sonde la 1re dispo.
  useEffect(() => {
    if (selectedPrestation && resolvedProfileId) goToFirstAvailableWeek();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selectedPrestation, domicile, domicileLatLng, resolvedProfileId]);

  const duration = selectedPrestation?.duree_minutes ?? 60;

  // Vérifie qu'il reste assez de temps pour le trajet avant/après ce créneau
  // à domicile — même heuristique que education_reservation_page.dart _trajetOk.
  function trajetOk(
    startMin: number, endMin: number, origineCreneau: string | null,
    rdvsDuJour: { startMin: number; endMin: number; lat: number | null; lng: number | null }[],
  ): boolean {
    if (!domicileLatLng) return true;
    const origine = origineCreneau ?? origineDefaut;
    const base = origine === 'autre_domicile' ? autreDomicileLatLng : cabinetLatLng;

    let precedent: { endMin: number; lat: number | null; lng: number | null } | undefined;
    let suivant: { startMin: number; lat: number | null; lng: number | null } | undefined;
    for (const r of rdvsDuJour) {
      if (r.endMin <= startMin) precedent = r;
      if (r.startMin >= endMin && !suivant) suivant = r;
    }

    const avantLat = precedent?.lat ?? base?.lat ?? null;
    const avantLng = precedent?.lng ?? base?.lng ?? null;
    const avantFin = precedent?.endMin ?? 0;
    if (avantLat != null && avantLng != null) {
      const distKm = distanceKm(avantLat, avantLng, domicileLatLng.lat, domicileLatLng.lng);
      const trajetMin = Math.ceil((distKm / VITESSE_TRAJET_KMH) * 60) + MARGE_TRAJET_MIN;
      if (startMin - avantFin < trajetMin) return false;
    }
    if (suivant?.lat != null && suivant?.lng != null) {
      const distKm = distanceKm(domicileLatLng.lat, domicileLatLng.lng, suivant.lat, suivant.lng);
      const trajetMin = Math.ceil((distKm / VITESSE_TRAJET_KMH) * 60) + MARGE_TRAJET_MIN;
      if (suivant.startMin - endMin < trajetMin) return false;
    }
    return true;
  }

  // Même algorithme que education_reservation_page.dart — pour la SEULE
  // semaine affichée (créneaux/RDV chargés semaine par semaine).
  const weekKey = toDateStr(weekStart);
  const weekSlots = slotsByWeek[weekKey] ?? [];
  const weekRdvs = rdvsByWeek[weekKey] ?? [];
  const weekCours = coursByWeek[weekKey] ?? [];
  const smartSlotsByDate = useMemo(() => {
    type SlotOut = { heure_debut: string; heure_fin: string; coursId?: string | null; capacite?: number; inscrits?: number; complet?: boolean };
    if (!selectedPrestation || weekSlots.length === 0) return {} as Record<string, SlotOut[]>;
    const collectif = selectedPrestation.type === 'collectif';
    const step = collectif ? duration : 15;
    // Heure minimale réservable : maintenant + délai imposé par le pro
    // (repli 30 min si aucun délai). Gère le multi-jours.
    const earliestBookable = new Date(Date.now() + (delaiMinH > 0 ? delaiMinH * 3600_000 : 30 * 60_000));

    const byDate: Record<string, { s: number; e: number; origine: string | null }[]> = {};
    for (const slot of weekSlots) {
      const slotCollectif = slot.type_prestation === 'collectif';
      if (collectif !== slotCollectif) continue;
      if (!collectif && domicile && !slot.domicile_ok) continue;
      const [sh, sm] = slot.heure_debut.split(':').map(Number);
      const [eh, em] = slot.heure_fin.split(':').map(Number);
      (byDate[slot.date] ??= []).push({ s: sh * 60 + sm, e: eh * 60 + em, origine: slot.trajet_origine });
    }

    const result: Record<string, SlotOut[]> = {};
    for (const [date, ranges] of Object.entries(byDate)) {
      ranges.sort((a, b) => a.s - b.s);
      const windows: { s: number; e: number; origine: string | null }[] = [];
      for (const r of ranges) {
        const last = windows[windows.length - 1];
        if (last && r.s <= last.e) { last.e = Math.max(last.e, r.e); } else { windows.push({ ...r }); }
      }

      const rdvsDuJour = weekRdvs
        .filter(rdv => toDateStr(new Date(rdv.date_heure)) === date)
        .map(rdv => {
          const dh = new Date(rdv.date_heure);
          const start = dh.getHours() * 60 + dh.getMinutes();
          return { startMin: start, endMin: start + (rdv.duree_minutes ?? 30), lat: rdv.lieu_lat, lng: rdv.lieu_lng };
        })
        .sort((a, b) => a.startMin - b.startMin);
      const blocked = rdvsDuJour.map(r => ({ s: r.startMin, e: r.endMin }));

      const available: SlotOut[] = [];
      const [dy, dmo, dd] = date.split('-').map(Number);
      const capaciteDefaut = selectedPrestation.capacite_max ?? 6;
      for (const w of windows) {
        for (let t = w.s; t + duration <= w.e; t += step) {
          if (new Date(dy, dmo - 1, dd, 0, t) < earliestBookable) continue;
          if (!collectif) {
            if (blocked.some(b => t < b.e && t + duration > b.s)) continue;
            if (domicile && domicileLatLng && !trajetOk(t, t + duration, w.origine, rdvsDuJour)) continue;
          }
          const pad = (n: number) => String(n).padStart(2, '0');
          const h = Math.floor(t / 60), m = t % 60;
          const out: SlotOut = {
            heure_debut: `${pad(h)}:${pad(m)}:00`,
            heure_fin: `${pad(Math.floor((t + duration) / 60))}:${pad((t + duration) % 60)}:00`,
          };
          if (collectif) {
            const match = weekCours.find(c => {
              const cdh = new Date(c.date_heure);
              return cdh.getFullYear() === dy && cdh.getMonth() === dmo - 1 && cdh.getDate() === dd
                && cdh.getHours() === h && cdh.getMinutes() === m;
            });
            const capacite = match?.capacite ?? capaciteDefaut;
            const inscrits = match?.inscrits ?? 0;
            out.coursId = match?.coursId ?? null;
            out.capacite = capacite;
            out.inscrits = inscrits;
            out.complet = inscrits >= capacite;
          }
          available.push(out);
        }
      }
      if (available.length > 0) result[date] = available;
    }
    return result;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [weekSlots, weekRdvs, weekCours, duration, selectedPrestation, domicile, domicileLatLng, origineDefaut, cabinetLatLng, autreDomicileLatLng, delaiMinH]);

  const weekLoading = !!loadingWeeks[weekKey] || (!!selectedPrestation && probedFirstDate === undefined);
  const aucuneDispo = probedFirstDate === null && !weekLoading;

  async function geocoderDomicile() {
    const adresse = adresseDomicile.trim();
    if (!adresse) return;
    setGeocodingDomicile(true);
    const geo = await geocodeAddress(adresse);
    setDomicileLatLng(geo);
    setGeocodingDomicile(false);
    setDomicileChoiceMade(true);
  }

  // Nom à afficher au pro : celui du PROFIL avec lequel le client réserve
  // (pas is_main, qui renvoie le nom d'élevage au lieu du particulier).
  async function resolveClientName(): Promise<string> {
    if (activeProfileId) {
      const { data } = await supabase.from('user_profiles').select('firstname, lastname, nom').eq('id', activeProfileId).maybeSingle();
      if (data) {
        const name = (data.nom ?? '').trim() || `${data.firstname ?? ''} ${data.lastname ?? ''}`.trim();
        if (name) return name;
      }
    }
    if (user) {
      const { data } = await supabase.from('users').select('firstname, lastname').eq('uid', user.uid).maybeSingle();
      const name = data ? `${data.firstname ?? ''} ${data.lastname ?? ''}`.trim() : '';
      if (name) return name;
    }
    return 'Un client';
  }

  // Inscription à une séance de groupe (cours collectif) — find-or-create de
  // la séance puis insertion du participant (capacité → 'demande' /
  // 'en_attente'). Miroir de education_reservation_page.dart _inscrireCollectif.
  async function enrollCollectif(dateHeure: Date) {
    if (!user || !selectedPrestation) return;
    const pid = resolvedProfileId ?? '';
    const utc = dateHeure.toISOString();

    let coursId: string | null = null;
    const { data: existing } = await supabase.from('cours_collectifs').select('id')
      .eq('pro_uid', proUid).eq('pro_profile_id', pid).eq('date_heure', utc).neq('statut', 'annule').limit(1);
    if (existing && existing.length > 0) {
      coursId = existing[0].id as string;
    } else {
      const { data: created } = await supabase.from('cours_collectifs').insert({
        pro_uid: proUid, pro_profile_id: pid, prestation_id: selectedPrestation.id,
        titre: selectedPrestation.nom, date_heure: utc, duree_minutes: duration,
        capacite_max: selectedPrestation.capacite_max ?? 6,
        ...(selectedPrestation.lieu_adresse ? { lieu: selectedPrestation.lieu_adresse } : {}),
        ...(selectedPrestation.lieu_lat != null ? { lieu_lat: selectedPrestation.lieu_lat, lieu_lng: selectedPrestation.lieu_lng } : {}),
        statut: 'planifie',
      }).select('id').single();
      coursId = (created?.id as string) ?? null;
    }
    if (!coursId) throw new Error('cours introuvable');

    const { data: current } = await supabase.from('cours_collectifs_participants')
      .select('id').eq('cours_id', coursId).neq('statut', 'annule');
    const capacite = selectedPrestation.capacite_max ?? 6;
    const complet = (current ?? []).length >= capacite;

    await supabase.from('cours_collectifs_participants').insert({
      cours_id: coursId, client_uid: user.uid,
      ...(activeProfileId ? { client_profile_id: activeProfileId } : {}),
      animal_id: selectedAnimalId,
      ...(selectedPrestation.prix != null ? { prix: selectedPrestation.prix } : {}),
      statut: complet ? 'en_attente' : 'demande',
    });

    const clientName = await resolveClientName();
    const dateStr = dateHeure.toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' });
    await supabase.from('notifications').insert({
      uid: proUid, type: 'cours_collectif_inscription',
      title: `Demande d'inscription — ${selectedPrestation.nom}`,
      body: `${clientName} souhaite s'inscrire au cours du ${dateStr} — en attente de votre confirmation.`,
      ...(pid ? { profile_id: pid } : {}),
      data: { coursId }, read: false,
    });
  }

  async function confirmSlot(date: string, heureDebut: string) {
    if (!user || !selectedPrestation) return;
    setSaving(true);
    try {
      const [h, m] = heureDebut.split(':').map(Number);
      const dateHeure = new Date(`${date}T00:00:00`);
      dateHeure.setHours(h, m, 0, 0);
      if (isCollectif) {
        await enrollCollectif(dateHeure);
        setSuccess(true);
        return;
      }
      await supabase.from('rdv').insert({
        pro_uid: proUid,
        pro_profile_id: resolvedProfileId ?? '',
        client_uid: user.uid,
        ...(activeProfileId ? { client_profile_id: activeProfileId } : {}),
        animal_id: selectedAnimalId,
        date_heure: dateHeure.toISOString(),
        duree_minutes: duration,
        motif: selectedPrestation.nom,
        ...(notes.trim() ? { notes_client: notes.trim() } : {}),
        ...(domicile && adresseDomicile.trim() ? { lieu: adresseDomicile.trim() } : {}),
        ...(domicile && domicileLatLng ? { lieu_lat: domicileLatLng.lat, lieu_lng: domicileLatLng.lng } : {}),
        ...(!domicile && selectedPrestation.lieu_adresse ? {
          lieu: selectedPrestation.lieu_adresse,
          ...(selectedPrestation.lieu_lat != null ? { lieu_lat: selectedPrestation.lieu_lat, lieu_lng: selectedPrestation.lieu_lng } : {}),
        } : {}),
        statut: 'demande',
      });
      const clientName = await resolveClientName();
      const dateStr = dateHeure.toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' });
      await supabase.from('notifications').insert({
        uid: proUid, type: 'rdv_demande',
        title: 'Nouvelle demande de RDV',
        body: `${clientName || 'Un client'} souhaite un cours "${selectedPrestation.nom}" le ${dateStr}`,
        ...(resolvedProfileId ? { profile_id: resolvedProfileId } : {}),
        data: { client_uid: user.uid }, read: false,
      });
      setSuccess(true);
    } finally {
      setSaving(false);
    }
  }

  const days = Array.from({ length: 7 }, (_, i) => { const d = new Date(weekStart); d.setDate(d.getDate() + i); return d; });

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center"
      onClick={e => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="bg-white w-full max-w-2xl rounded-t-3xl sm:rounded-3xl max-h-[92vh] overflow-y-auto">
        <div className="flex justify-center pt-3 pb-1 sm:hidden"><div className="w-10 h-1 bg-gray-200 rounded-full" /></div>
        <div className="px-5 pt-4 pb-8">
          <div className="flex items-center justify-between mb-5">
            <h2 className="text-lg font-bold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>
              Réserver un cours — {proName}
            </h2>
            <button onClick={onClose} className="text-gray-400 hover:text-gray-600 text-xl w-8 h-8 flex items-center justify-center">✕</button>
          </div>

          {success ? (
            <div className="flex flex-col items-center gap-4 py-8 text-center">
              <div className="w-16 h-16 rounded-full bg-green-100 flex items-center justify-center text-3xl">✅</div>
              <p className="font-bold text-[#1E2025] text-lg" style={{ fontFamily: 'Galey, sans-serif' }}>Demande envoyée !</p>
              <p className="text-sm text-gray-500" style={{ fontFamily: 'Galey, sans-serif' }}>
                {proName} recevra votre demande et vous confirmera le cours.
              </p>
              <button onClick={onClose} className="mt-2 px-6 py-2.5 rounded-2xl text-white font-semibold text-sm"
                style={{ backgroundColor: catColor, fontFamily: 'Galey, sans-serif' }}>
                Fermer
              </button>
            </div>
          ) : loading ? (
            <div className="flex justify-center py-12">
              <div className="w-8 h-8 border-4 border-t-transparent rounded-full animate-spin" style={{ borderColor: `${catColor} transparent transparent transparent` }} />
            </div>
          ) : prestations.length === 0 ? (
            <p className="text-sm text-gray-500 text-center py-8" style={{ fontFamily: 'Galey, sans-serif' }}>
              Ce professionnel n&apos;a pas encore configuré de cours à réserver en ligne.
            </p>
          ) : !selectedPrestation ? (
            <div className="space-y-3">
              <p className="text-sm font-semibold" style={{ fontFamily: 'Galey, sans-serif', color: catColor }}>Choisissez un cours</p>
              {isFirstTime && bilanRequis && (
                <p className="text-xs text-orange-600" style={{ fontFamily: 'Galey, sans-serif' }}>
                  Première réservation : un bilan préalable peut être requis.
                </p>
              )}
              {prestations.map(p => (
                <button key={p.id} onClick={() => {
                    setSelectedPrestation(p);
                    setDomicile(false);
                    // Collectif : jamais à domicile → pas d'étape de choix.
                    setDomicileChoiceMade(p.type === 'collectif' || !p.domicile_ok);
                    setDomicileLatLng(null);
                    setAdresseDomicile('');
                    setCoursByWeek({});
                  }}
                  className="w-full flex items-center justify-between rounded-2xl border p-4 text-left hover:shadow-sm transition-shadow"
                  style={{ borderColor: `${catColor}40` }}>
                  <div>
                    <p className="text-sm font-bold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>{p.nom}</p>
                    {p.description && <p className="text-xs text-gray-500" style={{ fontFamily: 'Galey, sans-serif' }}>{p.description}</p>}
                    <p className="text-xs text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
                      {p.duree_minutes} min{p.prix ? ` · ${p.prix.toFixed(0)} €` : ''}
                      {p.type === 'collectif' ? ` · en groupe (max ${p.capacite_max ?? 6})` : ''}
                    </p>
                  </div>
                  <span style={{ color: catColor }}>›</span>
                </button>
              ))}
            </div>
          ) : !domicileChoiceMade ? (
            <div className="space-y-4">
              <button onClick={() => setSelectedPrestation(null)} className="text-xs font-semibold flex items-center gap-1" style={{ color: catColor, fontFamily: 'Galey, sans-serif' }}>
                ← {selectedPrestation.nom}
              </button>
              <p className="text-sm font-semibold" style={{ fontFamily: 'Galey, sans-serif', color: catColor }}>Ce cours peut avoir lieu à domicile</p>
              <div className="flex gap-3">
                <button onClick={() => { setDomicile(false); setDomicileChoiceMade(true); }}
                  className="flex-1 py-3 rounded-2xl border text-sm font-semibold"
                  style={{ borderColor: catColor, color: catColor, fontFamily: 'Galey, sans-serif' }}>
                  Chez le professionnel
                </button>
                <button onClick={() => setDomicile(true)}
                  className="flex-1 py-3 rounded-2xl text-sm font-semibold text-white"
                  style={{ backgroundColor: domicile ? catColor : '#D1D5DB', fontFamily: 'Galey, sans-serif' }}>
                  À domicile
                </button>
              </div>
              {domicile && (
                <>
                  <input value={adresseDomicile} onChange={e => setAdresseDomicile(e.target.value)}
                    placeholder="Votre adresse (numéro, rue, ville)"
                    className="w-full px-3 py-2 border border-gray-200 rounded-xl text-sm font-galey" />
                  <p className="text-xs text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
                    Seuls les créneaux compatibles avec le trajet du professionnel seront proposés.
                  </p>
                  <button onClick={geocoderDomicile} disabled={geocodingDomicile || !adresseDomicile.trim()}
                    className="w-full py-3 rounded-2xl text-sm font-semibold text-white disabled:opacity-50"
                    style={{ backgroundColor: catColor, fontFamily: 'Galey, sans-serif' }}>
                    {geocodingDomicile ? '…' : 'Voir les créneaux'}
                  </button>
                </>
              )}
            </div>
          ) : (
            <div className="space-y-4">
              <button onClick={() => setSelectedPrestation(null)} className="text-xs font-semibold flex items-center gap-1" style={{ color: catColor, fontFamily: 'Galey, sans-serif' }}>
                ← {selectedPrestation.nom}
              </button>

              {animaux.length === 0 ? (
                <p className="text-xs text-gray-500" style={{ fontFamily: 'Galey, sans-serif' }}>
                  Ajoutez un animal depuis <a href="/mes-animaux" className="underline">Mes animaux</a> pour réserver.
                </p>
              ) : (
                <div className="flex flex-wrap gap-2">
                  {animaux.map(a => (
                    <button key={a.id} onClick={() => setSelectedAnimalId(selectedAnimalId === a.id ? null : a.id)}
                      className="px-3 py-1.5 rounded-full border text-xs font-semibold"
                      style={{
                        borderColor: selectedAnimalId === a.id ? catColor : '#E5E7EB',
                        backgroundColor: selectedAnimalId === a.id ? `${catColor}15` : 'white',
                        color: selectedAnimalId === a.id ? catColor : '#6B7280',
                        fontFamily: 'Galey, sans-serif',
                      }}>
                      🐾 {a.nom}
                    </button>
                  ))}
                </div>
              )}

              <p className="text-xs font-semibold" style={{ fontFamily: 'Galey, sans-serif', color: catColor }}>
                {isCollectif
                  ? `👥 Séance de groupe${selectedPrestation.capacite_max ? ` — max ${selectedPrestation.capacite_max}` : ''}`
                  : domicile ? `🏠 À domicile — ${adresseDomicile}` : '📍 Chez le professionnel'}
                {isCollectif && selectedPrestation.lieu_adresse ? ` · ${selectedPrestation.lieu_adresse}` : ''}
              </p>

              {isFirstTime ? (
                <div className="rounded-xl border p-3" style={{ borderColor: `${catColor}40`, backgroundColor: `${catColor}0C` }}>
                  <p className="text-xs font-bold mb-2" style={{ fontFamily: 'Galey, sans-serif', color: catColor }}>
                    Première fois avec ce professionnel
                  </p>
                  <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={3}
                    placeholder="Décrivez brièvement votre besoin"
                    className="w-full border border-gray-200 rounded-lg px-3 py-2 text-sm font-galey resize-none bg-white" />
                  <p className="text-[11px] text-gray-400 mt-1" style={{ fontFamily: 'Galey, sans-serif' }}>
                    Visible par le professionnel — facultatif mais utile
                  </p>
                </div>
              ) : (
                <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} placeholder="Message pour le pro (optionnel)"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm font-galey resize-none" />
              )}

              {!selectedAnimalId && (
                <div className="rounded-xl border px-3 py-2.5 text-xs font-semibold flex items-start gap-2"
                  style={{ borderColor: `${catColor}55`, backgroundColor: `${catColor}10`, color: catColor, fontFamily: 'Galey, sans-serif' }}>
                  <span>⚠️</span>
                  <span>
                    {animaux.length === 0
                      ? 'Aucun animal sur ce profil. Ajoutez-en un depuis « Mes animaux » (ou basculez sur votre profil particulier) pour pouvoir réserver un créneau.'
                      : 'Choisissez d’abord un animal ci-dessus : les créneaux ne sont cliquables qu’une fois l’animal sélectionné.'}
                  </span>
                </div>
              )}

              <div className="flex items-center justify-between">
                <button onClick={() => setWeekStart(d => { const n = new Date(d); n.setDate(n.getDate() - 7); return n; })}
                  className="w-8 h-8 rounded-full border border-gray-200 hover:bg-gray-50">‹</button>
                <p className="text-xs font-semibold capitalize" style={{ fontFamily: 'Galey, sans-serif' }}>{MONTH_FMT.format(weekStart)}</p>
                <button onClick={() => setWeekStart(d => { const n = new Date(d); n.setDate(n.getDate() + 7); return n; })}
                  className="w-8 h-8 rounded-full border border-gray-200 hover:bg-gray-50">›</button>
              </div>

              {weekLoading ? (
                <p className="text-xs text-gray-400 py-2" style={{ fontFamily: 'Galey, sans-serif' }}>Chargement des créneaux…</p>
              ) : aucuneDispo ? (
                <p className="text-xs py-2 px-3 rounded-lg" style={{ fontFamily: 'Galey, sans-serif', background: '#FFF7ED', color: '#9A3412' }}>
                  Ce professionnel n’a pas encore publié de disponibilités pour ce type de cours.
                </p>
              ) : Object.keys(smartSlotsByDate).length === 0 && probedFirstDate ? (
                <div className="text-xs py-2 px-3 rounded-lg flex items-center justify-between gap-2"
                  style={{ fontFamily: 'Galey, sans-serif', background: `${catColor}0F`, color: catColor }}>
                  <span>Rien de disponible cette semaine.</span>
                  <button className="font-bold whitespace-nowrap" onClick={goToFirstAvailableWeek}>Prochaines dispos ›</button>
                </div>
              ) : null}

              <div className="space-y-3 max-h-[45vh] overflow-y-auto">
                {days.filter(day => (smartSlotsByDate[toDateStr(day)] ?? []).length > 0).map(day => {
                  const key = toDateStr(day);
                  const daySlots = smartSlotsByDate[key] ?? [];
                  return (
                    <div key={key} className="rounded-xl border border-gray-100 p-3">
                      <p className="text-xs font-bold capitalize mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>{DAY_FMT.format(day)}</p>
                      <div className="flex flex-wrap gap-2">
                        {daySlots.map(s => (
                          <button key={s.heure_debut} disabled={saving || !selectedAnimalId}
                            onClick={() => confirmSlot(key, s.heure_debut)}
                            className="px-3 py-1.5 rounded-lg border text-xs font-semibold disabled:opacity-40 flex flex-col items-center leading-tight"
                            style={{
                              borderColor: s.complet ? '#FDBA74' : catColor,
                              color: s.complet ? '#C2410C' : catColor,
                              fontFamily: 'Galey, sans-serif',
                            }}>
                            <span>{s.heure_debut.slice(0, 5)}</span>
                            {s.capacite != null && (
                              <span className="text-[10px] opacity-70">
                                {s.complet ? 'complet' : `${s.inscrits}/${s.capacite} pl.`}
                              </span>
                            )}
                          </button>
                        ))}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
