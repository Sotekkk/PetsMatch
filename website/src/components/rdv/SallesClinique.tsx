'use client';

// Salles de la clinique vétérinaire : choix du lieu d'un RDV (à domicile ou
// salle, avec disponibilité sur le créneau) et réservation ponctuelle d'une
// salle (radio, opération…). Données : pm_salles_dispo / occupations_salle
// (migration_salles_occupation_direct.sql). Miroir app :
// lib/widgets/rdv/salles_clinique_widgets.dart.

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';

const TEAL = '#0C5C6C';
const FONT = { fontFamily: 'Galey, sans-serif' } as const;

/** Valeurs du champ Lieu : salle choisie automatiquement, à domicile, sinon id de salle. */
export const LIEU_AUTO = 'auto';
export const LIEU_DOMICILE = 'domicile';

export interface SalleDispo { id: string; nom: string; type: string; libre: boolean }

export const libelleTypeSalle = (t: string) =>
  ({ consultation: 'Consultation', chirurgie: 'Chirurgie', imagerie: 'Imagerie', hospitalisation: 'Hospitalisation' } as Record<string, string>)[t]
  ?? (t ? t[0].toUpperCase() + t.slice(1) : '');

export async function chargerSallesDispo(profileId: string, debut: Date, dureeMinutes: number, exclureRdv?: string | null): Promise<SalleDispo[]> {
  const { data, error } = await supabase.rpc('pm_salles_dispo', {
    p_pro_profile_id: profileId,
    p_debut: debut.toISOString(),
    p_fin: new Date(debut.getTime() + dureeMinutes * 60000).toISOString(),
    p_exclure_rdv: exclureRdv ?? null,
  });
  if (error) {
    // pm_salles_dispo indisponible (migration_salles_occupation_direct.sql
    // pas encore passée) : liste des salles sans la disponibilité.
    const { data: s } = await supabase.from('salles_clinique').select('id, nom, type_salle')
      .eq('clinique_profile_id', profileId).eq('actif', true).order('ordre');
    return ((s ?? []) as { id: string; nom: string | null; type_salle: string | null }[])
      .map(x => ({ id: x.id, nom: x.nom ?? 'Salle', type: x.type_salle ?? 'consultation', libre: true }));
  }
  return ((data ?? []) as { id: string; nom: string | null; type_salle: string | null; libre: boolean }[])
    .map(s => ({ id: s.id, nom: s.nom ?? 'Salle', type: s.type_salle ?? 'consultation', libre: !!s.libre }));
}

/** Valeur initiale du champ Lieu pour un RDV. */
export function lieuInitial(rdv: { lieu?: string | null; lieu_lat?: number | null; salle_id?: string | null }): string {
  if ((rdv.lieu ?? '').toLowerCase().includes('domicile') || rdv.lieu_lat != null) return LIEU_DOMICILE;
  return rdv.salle_id ?? LIEU_AUTO;
}

/** Champ Lieu → colonnes du RDV ({} = la base choisit la salle). */
export function champsLieu(choix: string, rdvLieu?: string | null, adresse = ''): Record<string, unknown> {
  if (choix === LIEU_AUTO) return { salle_id: null };
  if (choix === LIEU_DOMICILE) {
    const actuel = (rdvLieu ?? '').trim();
    return { salle_id: null, lieu: adresse.trim() || (actuel.toLowerCase().includes('domicile') ? actuel : 'À domicile') };
  }
  return { salle_id: choix, lieu: null, lieu_lat: null, lieu_lng: null };
}

/** Liste « Lieu » : à domicile ou une salle (occupées grisées). `salles`
 *  null = chargement ; liste vide = clinique sans salle (rien n'est affiché). */
export function useSallesDispo(profileId: string | null | undefined, debut: Date | null, dureeMinutes: number, exclureRdv?: string | null) {
  const [salles, setSalles] = useState<SalleDispo[] | null>(null);
  const cle = debut ? debut.getTime() : 0;
  useEffect(() => {
    if (!profileId || !cle) return;
    let actif = true;
    chargerSallesDispo(profileId, new Date(cle), dureeMinutes, exclureRdv).then(s => { if (actif) setSalles(s); });
    return () => { actif = false; };
  }, [profileId, cle, dureeMinutes, exclureRdv]);
  return salles;
}

export function LieuSalleSelect({ salles, value, onChange }: {
  salles: SalleDispo[]; value: string; onChange: (v: string) => void;
}) {
  return (
    <select value={value} onChange={e => onChange(e.target.value)}
      className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white focus:outline-none focus:border-[#0C5C6C]" style={FONT}>
      <option value={LIEU_AUTO}>Automatique (salle du praticien)</option>
      <option value={LIEU_DOMICILE}>🏠 À domicile</option>
      {salles.map(s => (
        <option key={s.id} value={s.id} disabled={!s.libre && s.id !== value}>
          {s.nom} · {libelleTypeSalle(s.type)}{s.libre ? '' : ' — occupée'}
        </option>
      ))}
    </select>
  );
}

const MOTIFS_OCC = ['Radio / imagerie', 'Échographie', 'Chirurgie', 'Consultation', 'Soins', 'Autre'];
const DUREES_OCC = [15, 30, 45, 60, 90, 120, 180];
const fmtDuree = (d: number) => d < 60 ? `${d} min` : d % 60 ? `${Math.floor(d / 60)}h${d % 60}` : `${d / 60} h`;
const ymd = (d: Date) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const hm = (d: Date) => `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`;

/** Réservation ponctuelle d'une salle. `praticiens` : id '' = titulaire. */
export function ReserverSalleModal({ profileId, salles, praticiens, salleId, debut, uid, onClose, onDone }: {
  profileId: string;
  salles: { id: string; nom: string; type: string }[];
  praticiens: { id: string; nom: string }[];
  salleId?: string | null;
  debut?: Date | null;
  uid?: string;
  onClose: () => void; onDone: () => void;
}) {
  const [salle, setSalle] = useState(salleId || salles[0]?.id || '');
  const [motif, setMotif] = useState(MOTIFS_OCC[0]);
  const [maintenant, setMaintenant] = useState(() => !debut || debut.getTime() <= Date.now());
  const [date, setDate] = useState(ymd(debut ?? new Date()));
  const [heure, setHeure] = useState(hm(debut ?? new Date()));
  const [duree, setDuree] = useState(30);
  const [praticien, setPraticien] = useState(praticiens[0]?.id ?? '');
  const [saving, setSaving] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);

  async function reserver() {
    setSaving(true); setErreur(null);
    const d0 = maintenant ? new Date() : new Date(`${date}T${heure}:00`);
    const { error } = await supabase.from('occupations_salle').insert({
      clinique_profile_id: profileId, salle_id: salle,
      debut: d0.toISOString(), fin: new Date(d0.getTime() + duree * 60000).toISOString(),
      motif, ...(praticien ? { praticien_profile_id: praticien } : {}), ...(uid ? { cree_par_uid: uid } : {}),
    });
    if (error) {
      setErreur(error.code === 'P0001' ? error.message : `Réservation impossible (${error.message}).`);
      setSaving(false);
      return;
    }
    onDone();
  }

  const chip = (sel: boolean) => ({
    background: sel ? TEAL : 'white', color: sel ? 'white' : '#1E2025', borderColor: sel ? TEAL : '#E4E7E2',
  });
  const label = 'text-xs font-semibold text-gray-500 uppercase tracking-wide';

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-md p-6 space-y-4 max-h-[92vh] overflow-y-auto"
        onClick={e => e.stopPropagation()} style={FONT}>
        <div>
          <h2 className="font-bold text-lg text-[#1E2025]">🔒 Réserver une salle</h2>
          <p className="text-xs text-gray-400 mt-0.5">Radio pendant une consultation, opération programmée… La salle est bloquée pour tous.</p>
        </div>
        <div><label className={label}>Salle</label>
          <select value={salle} onChange={e => setSalle(e.target.value)}
            className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white focus:outline-none">
            {salles.map(s => <option key={s.id} value={s.id}>{s.nom} · {libelleTypeSalle(s.type)}</option>)}
          </select></div>
        <div><label className={label}>Pour</label>
          <div className="flex flex-wrap gap-1.5 mt-1">
            {MOTIFS_OCC.map(m => (
              <button key={m} onClick={() => setMotif(m)} className="px-3 py-1.5 rounded-xl text-xs border font-semibold" style={chip(motif === m)}>{m}</button>
            ))}
          </div></div>
        <div><label className={label}>Quand</label>
          <div className="flex flex-wrap items-center gap-2 mt-1">
            <button onClick={() => setMaintenant(true)} className="px-3 py-1.5 rounded-xl text-xs border font-semibold" style={chip(maintenant)}>Maintenant</button>
            <button onClick={() => setMaintenant(false)} className="px-3 py-1.5 rounded-xl text-xs border font-semibold" style={chip(!maintenant)}>Plus tard</button>
            {!maintenant && (
              <>
                <input type="date" value={date} onChange={e => setDate(e.target.value)} className="border border-gray-200 rounded-xl px-2 py-1.5 text-sm" />
                <input type="time" step={300} value={heure} onChange={e => setHeure(e.target.value)} className="border border-gray-200 rounded-xl px-2 py-1.5 text-sm" />
              </>
            )}
          </div></div>
        <div><label className={label}>Durée</label>
          <div className="flex flex-wrap gap-1.5 mt-1">
            {DUREES_OCC.map(d => (
              <button key={d} onClick={() => setDuree(d)} className="px-3 py-1.5 rounded-xl text-xs border font-semibold" style={chip(duree === d)}>{fmtDuree(d)}</button>
            ))}
          </div></div>
        {praticiens.length > 1 && (
          <div><label className={label}>Vétérinaire</label>
            <select value={praticien} onChange={e => setPraticien(e.target.value)}
              className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white focus:outline-none">
              {praticiens.map(p => <option key={p.id} value={p.id}>{p.nom}</option>)}
            </select></div>
        )}
        {erreur && <p className="text-xs text-red-500">{erreur}</p>}
        <div className="flex gap-3 pt-1">
          <button onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm text-gray-600 border border-gray-200 hover:bg-gray-50 font-semibold">Annuler</button>
          <button onClick={reserver} disabled={saving || !salle}
            className="flex-1 py-2.5 rounded-xl text-sm text-white font-semibold disabled:opacity-50" style={{ background: TEAL }}>
            {saving ? '…' : 'Réserver la salle'}
          </button>
        </div>
      </div>
    </div>
  );
}
