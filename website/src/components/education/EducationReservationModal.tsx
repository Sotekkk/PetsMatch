'use client';

import { useEffect, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
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
}
interface Animal { id: number; nom: string; espece: string; }
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
  const activeProfileId = useActiveProfile();

  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [success, setSuccess] = useState(false);

  const [prestations, setPrestations] = useState<Prestation[]>([]);
  const [selectedPrestation, setSelectedPrestation] = useState<Prestation | null>(null);
  const [isFirstTime, setIsFirstTime] = useState(false);
  const [bilanRequis, setBilanRequis] = useState(true);

  const [animaux, setAnimaux] = useState<Animal[]>([]);
  const [selectedAnimalId, setSelectedAnimalId] = useState<number | null>(null);
  const [notes, setNotes] = useState('');

  const [weekStart, setWeekStart] = useState(() => mondayOf(new Date()));
  const [slots, setSlots] = useState<{ date: string; heure_debut: string; heure_fin: string; type_prestation: string | null; domicile_ok: boolean; trajet_origine: string | null }[]>([]);
  const [existingRdvs, setExistingRdvs] = useState<{ date_heure: string; duree_minutes: number; lieu_lat: number | null; lieu_lng: number | null }[]>([]);

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
    (async () => {
      const profileId = proProfileId ?? '';
      const cols = 'education_bilan_requis, trajet_origine_defaut, autre_domicile_lat, autre_domicile_lng, latitude, longitude, lat, lng';
      const proRow = proProfileId
        ? await supabase.from('user_profiles').select(cols).eq('id', proProfileId).maybeSingle()
        : await supabase.from('user_profiles').select(cols).eq('uid', proUid).eq('is_main', true).maybeSingle();
      const proData = proRow.data as {
        education_bilan_requis?: boolean; trajet_origine_defaut?: string;
        autre_domicile_lat?: number; autre_domicile_lng?: number;
        latitude?: number; longitude?: number; lat?: number; lng?: number;
      } | null;
      const bReq = proData?.education_bilan_requis ?? true;
      setBilanRequis(bReq);
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

      let pQ = supabase.from('prestations_education').select('id, nom, description, duree_minutes, prix, bilan_requis, domicile_ok')
        .eq('pro_uid', proUid).eq('actif', true);
      if (proProfileId) pQ = pQ.eq('pro_profile_id', proProfileId);
      const { data: pRows } = await pQ.order('ordre').order('created_at');
      let all = (pRows ?? []) as Prestation[];
      if (bReq && firstTime) {
        const bilans = all.filter(p => p.bilan_requis);
        if (bilans.length > 0) all = bilans;
      }
      setPrestations(all);

      let animauxQ = supabase.from('animaux').select('id, nom, espece')
        .or(`uid_eleveur.eq.${user.uid},uid_proprietaire.eq.${user.uid}`).order('nom');
      if (activeProfileId) animauxQ = animauxQ.eq('profile_id', activeProfileId);
      const { data: animauxData } = await animauxQ;
      setAnimaux((animauxData ?? []) as Animal[]);

      const now = new Date();
      const maxDt = new Date(now.getFullYear(), now.getMonth() + 3, now.getDate());
      const [{ data: slotRows }, { data: rdvRows }] = await Promise.all([
        supabase.from('creneaux_pro').select('date, heure_debut, heure_fin, type_prestation, domicile_ok, trajet_origine')
          .eq('pro_uid', proUid).eq('statut', 'disponible').eq('pro_profile_id', profileId)
          .gte('date', toDateStr(now)).lte('date', toDateStr(maxDt))
          .order('date').order('heure_debut').limit(1000),
        supabase.from('rdv').select('date_heure, duree_minutes, lieu_lat, lieu_lng')
          .eq('pro_uid', proUid).eq('pro_profile_id', profileId)
          .in('statut', ['confirme', 'demande'])
          .gte('date_heure', now.toISOString()),
      ]);
      setSlots((slotRows ?? []) as typeof slots);
      setExistingRdvs((rdvRows ?? []) as typeof existingRdvs);
      setLoading(false);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user, proUid, proProfileId]);

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

  // Même algorithme que education_reservation_page.dart _smartSlotsByDate.
  const smartSlotsByDate = useMemo(() => {
    if (!selectedPrestation || slots.length === 0) return {} as Record<string, { heure_debut: string; heure_fin: string }[]>;
    const now = new Date();
    const todayKey = toDateStr(now);
    const nowMinutes = now.getHours() * 60 + now.getMinutes() + 30;

    const byDate: Record<string, { s: number; e: number; origine: string | null }[]> = {};
    for (const slot of slots) {
      if (slot.type_prestation === 'collectif') continue;
      if (domicile && !slot.domicile_ok) continue;
      const [sh, sm] = slot.heure_debut.split(':').map(Number);
      const [eh, em] = slot.heure_fin.split(':').map(Number);
      (byDate[slot.date] ??= []).push({ s: sh * 60 + sm, e: eh * 60 + em, origine: slot.trajet_origine });
    }

    const result: Record<string, { heure_debut: string; heure_fin: string }[]> = {};
    for (const [date, ranges] of Object.entries(byDate)) {
      ranges.sort((a, b) => a.s - b.s);
      const windows: { s: number; e: number; origine: string | null }[] = [];
      for (const r of ranges) {
        const last = windows[windows.length - 1];
        if (last && r.s <= last.e) { last.e = Math.max(last.e, r.e); } else { windows.push({ ...r }); }
      }

      const rdvsDuJour = existingRdvs
        .filter(rdv => toDateStr(new Date(rdv.date_heure)) === date)
        .map(rdv => {
          const dh = new Date(rdv.date_heure);
          const start = dh.getHours() * 60 + dh.getMinutes();
          return { startMin: start, endMin: start + (rdv.duree_minutes ?? 30), lat: rdv.lieu_lat, lng: rdv.lieu_lng };
        })
        .sort((a, b) => a.startMin - b.startMin);
      const blocked = rdvsDuJour.map(r => ({ s: r.startMin, e: r.endMin }));

      const available: { heure_debut: string; heure_fin: string }[] = [];
      for (const w of windows) {
        for (let t = w.s; t + duration <= w.e; t += 15) {
          if (date === todayKey && t < nowMinutes) continue;
          const overlaps = blocked.some(b => t < b.e && t + duration > b.s);
          if (overlaps) continue;
          if (domicile && domicileLatLng && !trajetOk(t, t + duration, w.origine, rdvsDuJour)) continue;
          const pad = (n: number) => String(n).padStart(2, '0');
          available.push({
            heure_debut: `${pad(Math.floor(t / 60))}:${pad(t % 60)}:00`,
            heure_fin: `${pad(Math.floor((t + duration) / 60))}:${pad((t + duration) % 60)}:00`,
          });
        }
      }
      if (available.length > 0) result[date] = available;
    }
    return result;
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [slots, existingRdvs, duration, selectedPrestation, domicile, domicileLatLng, origineDefaut, cabinetLatLng, autreDomicileLatLng]);

  async function geocoderDomicile() {
    const adresse = adresseDomicile.trim();
    if (!adresse) return;
    setGeocodingDomicile(true);
    const geo = await geocodeAddress(adresse);
    setDomicileLatLng(geo);
    setGeocodingDomicile(false);
    setDomicileChoiceMade(true);
  }

  async function confirmSlot(date: string, heureDebut: string) {
    if (!user || !selectedPrestation) return;
    setSaving(true);
    try {
      const [h, m] = heureDebut.split(':').map(Number);
      const dateHeure = new Date(`${date}T00:00:00`);
      dateHeure.setHours(h, m, 0, 0);
      await supabase.from('rdv').insert({
        pro_uid: proUid,
        pro_profile_id: proProfileId ?? '',
        client_uid: user.uid,
        ...(activeProfileId ? { client_profile_id: activeProfileId } : {}),
        animal_id: selectedAnimalId,
        date_heure: dateHeure.toISOString(),
        duree_minutes: duration,
        motif: selectedPrestation.nom,
        ...(notes.trim() ? { notes_client: notes.trim() } : {}),
        ...(domicile && adresseDomicile.trim() ? { lieu: adresseDomicile.trim() } : {}),
        ...(domicile && domicileLatLng ? { lieu_lat: domicileLatLng.lat, lieu_lng: domicileLatLng.lng } : {}),
        statut: 'demande',
      });
      const { data: userData } = await supabase.from('user_profiles').select('firstname, lastname').eq('uid', user.uid).eq('is_main', true).maybeSingle();
      const clientName = userData ? `${userData.firstname ?? ''} ${userData.lastname ?? ''}`.trim() : 'Un client';
      const dateStr = dateHeure.toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' });
      await supabase.from('notifications').insert({
        uid: proUid, type: 'rdv_demande',
        title: 'Nouvelle demande de RDV',
        body: `${clientName || 'Un client'} souhaite un cours "${selectedPrestation.nom}" le ${dateStr}`,
        ...(proProfileId ? { profile_id: proProfileId } : {}),
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
                    setDomicileChoiceMade(!p.domicile_ok);
                    setDomicileLatLng(null);
                    setAdresseDomicile('');
                  }}
                  className="w-full flex items-center justify-between rounded-2xl border p-4 text-left hover:shadow-sm transition-shadow"
                  style={{ borderColor: `${catColor}40` }}>
                  <div>
                    <p className="text-sm font-bold text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>{p.nom}</p>
                    {p.description && <p className="text-xs text-gray-500" style={{ fontFamily: 'Galey, sans-serif' }}>{p.description}</p>}
                    <p className="text-xs text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
                      {p.duree_minutes} min{p.prix ? ` · ${p.prix.toFixed(0)} €` : ''}
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
                {domicile ? `🏠 À domicile — ${adresseDomicile}` : '📍 Chez le professionnel'}
              </p>

              <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} placeholder="Message pour le pro (optionnel)"
                className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm font-galey resize-none" />

              <div className="flex items-center justify-between">
                <button onClick={() => setWeekStart(d => { const n = new Date(d); n.setDate(n.getDate() - 7); return n; })}
                  className="w-8 h-8 rounded-full border border-gray-200 hover:bg-gray-50">‹</button>
                <p className="text-xs font-semibold capitalize" style={{ fontFamily: 'Galey, sans-serif' }}>{MONTH_FMT.format(weekStart)}</p>
                <button onClick={() => setWeekStart(d => { const n = new Date(d); n.setDate(n.getDate() + 7); return n; })}
                  className="w-8 h-8 rounded-full border border-gray-200 hover:bg-gray-50">›</button>
              </div>

              <div className="space-y-3 max-h-[45vh] overflow-y-auto">
                {days.map(day => {
                  const key = toDateStr(day);
                  const daySlots = smartSlotsByDate[key] ?? [];
                  return (
                    <div key={key} className="rounded-xl border border-gray-100 p-3">
                      <p className="text-xs font-bold capitalize mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>{DAY_FMT.format(day)}</p>
                      {daySlots.length === 0 ? (
                        <p className="text-xs text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>Aucun créneau disponible</p>
                      ) : (
                        <div className="flex flex-wrap gap-2">
                          {daySlots.map(s => (
                            <button key={s.heure_debut} disabled={saving || !selectedAnimalId}
                              onClick={() => confirmSlot(key, s.heure_debut)}
                              className="px-3 py-1.5 rounded-lg border text-xs font-semibold disabled:opacity-40"
                              style={{ borderColor: catColor, color: catColor, fontFamily: 'Galey, sans-serif' }}>
                              {s.heure_debut.slice(0, 5)}
                            </button>
                          ))}
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
              {!selectedAnimalId && animaux.length > 0 && (
                <p className="text-xs text-gray-400 text-center" style={{ fontFamily: 'Galey, sans-serif' }}>Choisissez un animal pour activer les créneaux.</p>
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
