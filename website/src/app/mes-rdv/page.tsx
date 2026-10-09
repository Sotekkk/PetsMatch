'use client';

import { useState, useEffect, useCallback, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import OwnerContactButton from '@/components/pro/OwnerContactButton';
import { typeFromMotif } from '@/lib/agenda-type';
import PlanningClinique from '@/components/rdv/PlanningClinique';
import HistoriquePatient from '@/components/pro/HistoriquePatient';
import { retardsEnCascade } from '@/lib/retards-rdv';
import { LieuSalleSelect, LIEU_AUTO, LIEU_DOMICILE, champsLieu, lieuInitial, useSallesDispo } from '@/components/rdv/SallesClinique';
import { trouverUtilisateurParEmail, type UtilisateurTrouve } from '@/lib/user-lookup';
import { apiFetch } from '@/lib/api-fetch';

// ── Constants ──────────────────────────────────────────────────────────────────

const TEAL   = '#0C5C6C';
const GREEN  = '#6E9E57';
const ORANGE = '#FF9800';

const JOURS = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];
const MOIS  = ['jan', 'fév', 'mar', 'avr', 'mai', 'jun', 'jul', 'aoû', 'sep', 'oct', 'nov', 'déc'];

const STATUT_STYLE: Record<string, { bg: string; color: string; label: string }> = {
  demande:            { bg: '#FFF3E0', color: '#e08000',  label: 'Demande'       },
  contre_proposition: { bg: '#E3F2FD', color: '#1565C0',  label: 'Contre-prop.'  },
  confirme:           { bg: '#E8F5E9', color: '#388E3C',  label: 'Confirmé'      },
  termine:            { bg: '#F5F5F5', color: '#757575',  label: 'Terminé'       },
  annule:             { bg: '#FFEBEE', color: '#d32f2f',  label: 'Annulé'        },
  refuse:             { bg: '#FFEBEE', color: '#d32f2f',  label: 'Refusé'        },
  no_show:            { bg: '#FFF8E1', color: '#F57F17',  label: 'No-show'       },
};

const PRO_TITLE: Record<string, string> = {
  veterinaire:      'Mes rendez-vous',
  sante:            'Mes rendez-vous',
  pension:          'Gestion des RDV',
  garde:            'Mes RDV de garde',
  education:        'Mes séances',
  toilettage:       'Mes RDV toilettage',
  comportementaliste: 'Mes séances',
  osteo:            'Mes séances',
  photographe:      'Mes séances photo',
  marechal_ferrant: 'Mes interventions',
};

// ── Types ──────────────────────────────────────────────────────────────────────

interface Rdv {
  id: string;
  pro_uid: string;
  client_uid: string;
  pro_profile_id?: string | null;
  client_profile_id?: string | null;
  animal_id?: string | null;
  date_heure: string;
  motif?: string | null;
  statut: string;
  notes_annulation?: string | null;
  notes_pro?: string | null;
  notes_client?: string | null;
  client_nom_manuel?: string | null;
  client_telephone_manuel?: string | null;
  duree_minutes?: number | null;
  premiere_visite?: boolean | null;
  lieu?: string | null;
  lieu_lat?: number | null;
  lieu_lng?: number | null;
  instructeur_profile_id?: string | null;
  /** Clinique : client « peu importe », pas encore attribué. */
  praticien_indifferent?: boolean | null;
  salle_id?: string | null;
  animal_nom_manuel?: string | null;
  termine_at?: string | null;
  /** Retard estimé en cascade (minutes), calculé à l'affichage. */
  retardMin?: number;
  clientName?: string;
  animalNom?: string;
  visitCount?: number;
}

interface Employe {
  profileId: string;
  nom: string;
}

type SlotStatus = 'disponible' | 'bloque';

// ── Helpers ────────────────────────────────────────────────────────────────────

function fmtDate(iso: string) {
  return new Date(iso).toLocaleDateString('fr-FR', { weekday: 'long', day: '2-digit', month: 'long', year: 'numeric' });
}
function fmtHeure(iso: string) {
  return new Date(iso).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
}
function getMonday(d: Date): Date {
  const day = d.getDay();
  const diff = day === 0 ? -6 : 1 - day;
  const mon = new Date(d);
  mon.setDate(d.getDate() + diff);
  mon.setHours(0, 0, 0, 0);
  return mon;
}
function toDateStr(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

// ── Modal Accepter ─────────────────────────────────────────────────────────────

function AccepterModal({ rdv, proName, onClose, onDone }: {
  rdv: Rdv; proName: string; onClose: () => void; onDone: () => void;
}) {
  const [mode, setMode]     = useState<'confirme' | 'contre_proposition'>('confirme');
  const [hour, setHour]     = useState(new Date(rdv.date_heure).getHours());
  const [minute, setMinute] = useState(0);
  const [date, setDate]     = useState(rdv.date_heure.slice(0, 10));
  const [duree, setDuree]   = useState(rdv.duree_minutes ?? 60);
  const [saving, setSaving] = useState(false);
  // Clinique : vétérinaire à qui attribuer la demande ('' = titulaire).
  const [praticiens, setPraticiens] = useState<{ id: string; nom: string }[]>([]);
  const [attribue, setAttribue] = useState(rdv.praticien_indifferent ? '' : (rdv.instructeur_profile_id ?? ''));
  // Clinique : lieu = à domicile ou une salle (disponibilité sur le créneau).
  // « automatique » = salle affectée au praticien choisi sur son créneau.
  const [lieuChoix, setLieuChoix] = useState(lieuInitial(rdv) === LIEU_DOMICILE ? LIEU_DOMICILE : LIEU_AUTO);
  const debutChoisi = new Date(`${date}T${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}:00`);
  const sallesDispo = useSallesDispo(rdv.statut === 'demande' ? rdv.pro_profile_id : null,
    isNaN(debutChoisi.getTime()) ? null : debutChoisi, duree, rdv.id);
  const avecSalles = (sallesDispo?.length ?? 0) > 0;

  useEffect(() => {
    if (rdv.statut !== 'demande' || !rdv.pro_profile_id) return;
    supabase.rpc('pm_praticiens_clinique', { p_pro_profile_id: rdv.pro_profile_id }).then(({ data }) => {
      setPraticiens(((data ?? []) as { praticien_profile_id: string | null; nom: string | null }[])
        .map(p => ({ id: p.praticien_profile_id ?? '', nom: p.nom?.trim() || 'Vétérinaire' })));
    });
  }, [rdv.statut, rdv.pro_profile_id]);

  async function handleSubmit() {
    setSaving(true);
    try {
      const newDt     = new Date(`${date}T${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}:00`);
      const newStatut = mode === 'confirme' ? 'confirme' : 'contre_proposition';

      const maj = {
        statut: newStatut, date_heure: newDt.toISOString(), duree_minutes: duree,
        ...(mode === 'confirme' && avecSalles ? champsLieu(lieuChoix, rdv.lieu) : {}),
      };
      if (mode === 'confirme' && avecSalles) {
        // Salle choisie occupée → refus en base : on prévient sans valider.
        const { error } = await supabase.from('rdv').update({
          ...maj,
          ...(rdv.praticien_indifferent || praticiens.length > 1 ? { instructeur_profile_id: attribue || null, praticien_indifferent: false } : {}),
        }).eq('id', rdv.id);
        if (error) {
          alert(error.code === 'P0001' ? error.message : `Erreur : ${error.message}`);
          setSaving(false);
          return;
        }
      } else if (mode === 'confirme' && (rdv.praticien_indifferent || praticiens.length > 1)) {
        // Clinique : RDV attribué au vétérinaire choisi ; s'il n'est pas libre
        // (contrôle en base), il reste attribué comme avant.
        const { error } = await supabase.from('rdv').update({ ...maj, instructeur_profile_id: attribue || null, praticien_indifferent: false }).eq('id', rdv.id);
        if (error?.code === 'P0001') {
          await supabase.from('rdv').update({ ...maj, praticien_indifferent: false }).eq('id', rdv.id);
          alert("Ce vétérinaire n'est pas libre à cette heure : le RDV reste attribué comme avant.");
        } else if (error) throw error;
      } else {
        await supabase.from('rdv').update(maj).eq('id', rdv.id);
      }

      if (mode === 'confirme') {
        await supabase.from('agenda_events').upsert({
          uid: rdv.client_uid,
          titre: `RDV${rdv.animalNom ? ` — ${rdv.animalNom}` : ''}`,
          type: typeFromMotif(rdv.motif), date_debut: newDt.toISOString(),
          duree_minutes: duree, rdv_id: rdv.id,
          animal_id: rdv.animal_id ?? null,
          pro_profile_id: rdv.client_profile_id ?? null,
        }, { onConflict: 'rdv_id' });

        await supabase.from('agenda_events').delete()
          .eq('uid', rdv.pro_uid).eq('couleur', `rdv:${rdv.id}`);
        await supabase.from('agenda_events').insert({
          uid: rdv.pro_uid,
          titre: `RDV avec ${rdv.clientName ?? 'Client'}`,
          type: typeFromMotif(rdv.motif), date_debut: newDt.toISOString(),
          duree_minutes: duree, couleur: `rdv:${rdv.id}`,
          animal_id: rdv.animal_id ?? null,
          pro_profile_id: rdv.pro_profile_id ?? null,
        });

        await supabase.from('notifications').insert({
          uid: rdv.client_uid, type: 'rdv_confirme',
          title: `RDV confirmé par ${proName}`,
          body: `Votre rendez-vous est confirmé pour le ${fmtDate(newDt.toISOString())} à ${fmtHeure(newDt.toISOString())}`,
          ...(rdv.client_profile_id ? { profile_id: rdv.client_profile_id } : {}),
          data: { rdv_id: rdv.id }, read: false,
        });
      } else {
        await supabase.from('notifications').insert({
          uid: rdv.client_uid, type: 'rdv_contre_proposition',
          title: 'Contre-proposition de créneau',
          body: `${proName} propose un autre créneau : ${fmtDate(newDt.toISOString())} à ${fmtHeure(newDt.toISOString())}`,
          ...(rdv.client_profile_id ? { profile_id: rdv.client_profile_id } : {}),
          data: { rdv_id: rdv.id }, read: false,
        });
      }
      onDone();
    } catch { /* ignore */ } finally { setSaving(false); }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-md p-6 space-y-5" onClick={e => e.stopPropagation()}>
        <h2 className="font-bold text-lg text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>Accepter le RDV</h2>
        {mode === 'confirme' && avecSalles && sallesDispo && (
          <div>
            <label className="text-xs font-semibold text-gray-500 block" style={{ fontFamily: 'Galey, sans-serif' }}>Lieu</label>
            <LieuSalleSelect salles={sallesDispo} value={lieuChoix} onChange={setLieuChoix} />
          </div>
        )}
        {mode === 'confirme' && praticiens.length > 1 && (
          <div>
            <label className="text-xs font-semibold text-gray-500 block mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>
              Attribuer à{rdv.praticien_indifferent ? ' (le client a choisi « peu importe »)' : ''}
            </label>
            <select value={attribue} onChange={e => setAttribue(e.target.value)}
              className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm bg-white focus:outline-none focus:border-[#2E7D5E]"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              {praticiens.map(p => <option key={p.id} value={p.id}>{p.nom}</option>)}
            </select>
          </div>
        )}

        <div className="bg-gray-50 rounded-xl p-3 text-sm text-gray-600">
          <p className="font-semibold">{rdv.clientName ?? '—'}{rdv.animalNom ? ` · ${rdv.animalNom}` : ''}</p>
          <p className="text-xs text-gray-400 mt-0.5">Demandé : {fmtDate(rdv.date_heure)} à {fmtHeure(rdv.date_heure)}</p>
          {rdv.motif && <p className="text-xs text-gray-400">Motif : {rdv.motif}</p>}
        </div>

        <div className="flex gap-2 bg-gray-100 rounded-xl p-1">
          {(['confirme', 'contre_proposition'] as const).map(m => (
            <button key={m} onClick={() => setMode(m)}
              className="flex-1 py-2 text-sm font-semibold rounded-lg transition-all"
              style={{ background: mode === m ? 'white' : 'transparent', color: mode === m ? TEAL : '#6b7280', fontFamily: 'Galey, sans-serif' }}>
              {m === 'confirme' ? 'Confirmer' : 'Autre créneau'}
            </button>
          ))}
        </div>

        {mode === 'contre_proposition' && (
          <div>
            <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Date</label>
            <input type="date" value={date} onChange={e => setDate(e.target.value)}
              className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none" />
          </div>
        )}

        <div>
          <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Heure</label>
          <div className="flex gap-2 mt-2">
            <select value={hour} onChange={e => setHour(Number(e.target.value))}
              className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none">
              {Array.from({ length: 14 }, (_, i) => i + 7).map(h => (
                <option key={h} value={h}>{String(h).padStart(2, '0')}h</option>
              ))}
            </select>
            <select value={minute} onChange={e => setMinute(Number(e.target.value))}
              className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none">
              {[0, 15, 30, 45].map(m => (
                <option key={m} value={m}>{String(m).padStart(2, '0')}</option>
              ))}
            </select>
          </div>
        </div>

        <div>
          <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Durée</label>
          <div className="flex flex-wrap gap-2 mt-2">
            {[15, 30, 45, 60, 90, 120].map(d => (
              <button key={d} onClick={() => setDuree(d)}
                className="px-3 py-1.5 rounded-lg text-xs font-semibold border transition-colors"
                style={{ background: duree === d ? TEAL : 'white', color: duree === d ? 'white' : '#1E2025', borderColor: duree === d ? TEAL : '#e5e7eb', fontFamily: 'Galey, sans-serif' }}>
                {d < 60 ? `${d} min` : d === 60 ? '1 h' : `${d / 60} h`}
              </button>
            ))}
          </div>
        </div>

        <div className="flex gap-3 pt-1">
          <button onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm text-gray-600 border border-gray-200 hover:bg-gray-50 font-semibold">
            Annuler
          </button>
          <button onClick={handleSubmit} disabled={saving}
            className="flex-1 py-2.5 rounded-xl text-sm text-white font-semibold disabled:opacity-50"
            style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
            {saving ? '…' : mode === 'confirme' ? '✓ Confirmer' : 'Proposer'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Modal Modifier (RDV confirmé) ───────────────────────────────────────────────

function ModifierModal({ rdv, proName, activeProfileId, onClose, onDone }: {
  rdv: Rdv; proName: string; activeProfileId: string; onClose: () => void; onDone: () => void;
}) {
  const [date, setDate]     = useState(rdv.date_heure.slice(0, 10));
  const [hour, setHour]     = useState(new Date(rdv.date_heure).getHours());
  const [minute, setMinute] = useState(new Date(rdv.date_heure).getMinutes());
  const [duree, setDuree]   = useState(rdv.duree_minutes ?? 60);
  const [motif, setMotif]   = useState(rdv.motif ?? '');
  const [lieu, setLieu]     = useState(rdv.lieu ?? '');
  const [notes, setNotes]   = useState(rdv.notes_pro ?? '');
  const [instructeurProfileId, setInstructeurProfileId] = useState(rdv.instructeur_profile_id ?? '');
  const [employes, setEmployes] = useState<Employe[]>([]);
  const [saving, setSaving] = useState(false);
  // Clinique avec salles : lieu = à domicile (adresse facultative) ou une salle.
  const [lieuChoix, setLieuChoix] = useState(lieuInitial(rdv));
  const debutModifie = new Date(`${date}T${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}:00`);
  const sallesDispo = useSallesDispo(rdv.pro_profile_id, isNaN(debutModifie.getTime()) ? null : debutModifie, duree, rdv.id);
  const avecSalles = (sallesDispo?.length ?? 0) > 0;

  useEffect(() => {
    if (!activeProfileId) return;
    (async () => {
      const { data: emps } = await supabase.from('employes')
        .select('uid_employe, employe_profile_id').eq('eleveur_profile_id', activeProfileId).eq('actif', true);
      if (!emps || emps.length === 0) return;
      const profileIds = emps.map(e => (e as { employe_profile_id: string | null }).employe_profile_id).filter(Boolean) as string[];
      if (profileIds.length === 0) return;
      const { data: profs } = await supabase.from('user_profiles_complet').select('id, uid').in('id', profileIds);
      const uidByProfileId: Record<string, string> = {};
      for (const p of (profs ?? [])) {
        const rec = p as { id: string; uid: string };
        uidByProfileId[rec.id] = rec.uid;
      }
      const uids = Object.values(uidByProfileId);
      if (uids.length === 0) return;
      const { data: users } = await supabase.from('users_complet').select('uid, firstname, lastname').in('uid', uids);
      const nameByUid: Record<string, string> = {};
      for (const u of (users ?? [])) {
        const rec = u as { uid: string; firstname?: string; lastname?: string };
        nameByUid[rec.uid] = `${rec.firstname ?? ''} ${rec.lastname ?? ''}`.trim();
      }
      const result: Employe[] = profileIds.map(pid => ({
        profileId: pid,
        nom: nameByUid[uidByProfileId[pid]] || 'Employé',
      }));
      setEmployes(result);
    })();
  }, [activeProfileId]);

  async function handleSubmit() {
    setSaving(true);
    try {
      const newDt = new Date(`${date}T${String(hour).padStart(2, '0')}:${String(minute).padStart(2, '0')}:00`);

      // Ne re-géocode que si le lieu a changé, pour éviter un appel réseau
      // inutile à chaque modification qui ne touche pas l'adresse.
      let lieuLat = rdv.lieu_lat ?? null;
      let lieuLng = rdv.lieu_lng ?? null;
      const lieuTrimmed = avecSalles && lieuChoix !== LIEU_DOMICILE ? '' : lieu.trim();
      if (lieuTrimmed && lieuTrimmed !== (rdv.lieu ?? '')) {
        try {
          const res = await fetch(`https://api-adresse.data.gouv.fr/search/?q=${encodeURIComponent(lieuTrimmed)}&limit=1`);
          const json = await res.json();
          const coords = json?.features?.[0]?.geometry?.coordinates;
          if (coords) { lieuLng = coords[0]; lieuLat = coords[1]; } else { lieuLat = null; lieuLng = null; }
        } catch { lieuLat = null; lieuLng = null; }
      } else if (!lieuTrimmed) {
        lieuLat = null; lieuLng = null;
      }

      const { error: errMaj } = await supabase.from('rdv').update({
        date_heure: newDt.toISOString(), duree_minutes: duree,
        motif: motif.trim() || null, lieu: lieuTrimmed || null,
        lieu_lat: lieuLat, lieu_lng: lieuLng,
        notes_pro: notes.trim() || null,
        instructeur_profile_id: instructeurProfileId || null,
        // Clinique : salle choisie / à domicile ; « automatique » → la base choisit.
        ...(avecSalles ? { ...champsLieu(lieuChoix, rdv.lieu, lieuTrimmed), ...(lieuChoix === LIEU_DOMICILE && lieuTrimmed ? { lieu: lieuTrimmed, lieu_lat: lieuLat, lieu_lng: lieuLng } : {}) } : {}),
        reminder_48h_sent: false, reminder_24h_sent: false,
        reminder_1h_sent: false, reminder_15min_sent: false,
      }).eq('id', rdv.id);
      if (errMaj) {
        alert(errMaj.code === 'P0001' ? errMaj.message : `Erreur : ${errMaj.message}`);
        setSaving(false);
        return;
      }

      await supabase.from('agenda_events').upsert({
        uid: rdv.client_uid,
        titre: `RDV${rdv.animalNom ? ` — ${rdv.animalNom}` : ''}`,
        type: typeFromMotif(motif), date_debut: newDt.toISOString(),
        duree_minutes: duree, rdv_id: rdv.id,
        animal_id: rdv.animal_id ?? null,
        pro_profile_id: rdv.client_profile_id ?? null,
      }, { onConflict: 'rdv_id' });

      await supabase.from('agenda_events').delete()
        .eq('uid', rdv.pro_uid).eq('couleur', `rdv:${rdv.id}`);
      await supabase.from('agenda_events').insert({
        uid: rdv.pro_uid,
        titre: `RDV avec ${rdv.clientName ?? 'Client'}`,
        type: typeFromMotif(motif), date_debut: newDt.toISOString(),
        duree_minutes: duree, couleur: `rdv:${rdv.id}`,
        animal_id: rdv.animal_id ?? null,
        pro_profile_id: rdv.pro_profile_id ?? null,
      });

      await supabase.from('notifications').insert({
        uid: rdv.client_uid, type: 'rdv_modifie',
        title: `RDV modifié par ${proName}`,
        body: `Votre rendez-vous a été mis à jour : ${fmtDate(newDt.toISOString())} à ${fmtHeure(newDt.toISOString())}${lieu.trim() ? ` — ${lieu.trim()}` : ''}`,
        ...(rdv.client_profile_id ? { profile_id: rdv.client_profile_id } : {}),
        data: { rdv_id: rdv.id }, read: false,
      });
      onDone();
    } catch { /* ignore */ } finally { setSaving(false); }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-md p-6 space-y-5 max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
        <h2 className="font-bold text-lg text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>Modifier le RDV</h2>

        <div className="bg-gray-50 rounded-xl p-3 text-sm text-gray-600">
          <p className="font-semibold">{rdv.clientName ?? '—'}{rdv.animalNom ? ` · ${rdv.animalNom}` : ''}</p>
        </div>

        <div>
          <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Date</label>
          <input type="date" value={date} onChange={e => setDate(e.target.value)}
            className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none" />
        </div>

        <div>
          <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Heure</label>
          <div className="flex gap-2 mt-2">
            <select value={hour} onChange={e => setHour(Number(e.target.value))}
              className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none">
              {Array.from({ length: 14 }, (_, i) => i + 7).map(h => (
                <option key={h} value={h}>{String(h).padStart(2, '0')}h</option>
              ))}
            </select>
            <select value={minute} onChange={e => setMinute(Number(e.target.value))}
              className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none">
              {[0, 15, 30, 45].map(m => (
                <option key={m} value={m}>{String(m).padStart(2, '0')}</option>
              ))}
            </select>
          </div>
        </div>

        <div>
          <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Durée</label>
          <div className="flex flex-wrap gap-2 mt-2">
            {[15, 30, 45, 60, 90, 120].map(d => (
              <button key={d} onClick={() => setDuree(d)}
                className="px-3 py-1.5 rounded-lg text-xs font-semibold border transition-colors"
                style={{ background: duree === d ? TEAL : 'white', color: duree === d ? 'white' : '#1E2025', borderColor: duree === d ? TEAL : '#e5e7eb', fontFamily: 'Galey, sans-serif' }}>
                {d < 60 ? `${d} min` : d === 60 ? '1 h' : `${d / 60} h`}
              </button>
            ))}
          </div>
        </div>

        <div>
          <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Motif</label>
          <input value={motif} onChange={e => setMotif(e.target.value)}
            className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none" />
        </div>

        <div>
          <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Lieu</label>
          {avecSalles && sallesDispo ? (
            <>
              <LieuSalleSelect salles={sallesDispo} value={lieuChoix} onChange={setLieuChoix} />
              {lieuChoix === LIEU_DOMICILE && (
                <input value={lieu.toLowerCase().includes('domicile') ? '' : lieu} onChange={e => setLieu(e.target.value)} placeholder="Adresse du domicile (facultatif)"
                  className="mt-2 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none" />
              )}
            </>
          ) : (
          <input value={lieu} onChange={e => setLieu(e.target.value)} placeholder="Au cabinet, au domicile du client…"
            className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none" />
          )}
        </div>

        {employes.length > 0 && (
          <div>
            <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Intervenant assigné</label>
            <select value={instructeurProfileId} onChange={e => setInstructeurProfileId(e.target.value)}
              className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none">
              <option value="">Moi</option>
              {employes.map(e => <option key={e.profileId} value={e.profileId}>{e.nom}</option>)}
            </select>
          </div>
        )}

        <div>
          <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Notes (optionnel)</label>
          <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2}
            className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none resize-none" />
        </div>

        <div className="flex gap-3 pt-1">
          <button onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm text-gray-600 border border-gray-200 hover:bg-gray-50 font-semibold">
            Annuler
          </button>
          <button onClick={handleSubmit} disabled={saving}
            className="flex-1 py-2.5 rounded-xl text-sm text-white font-semibold disabled:opacity-50"
            style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
            {saving ? '…' : '✓ Enregistrer'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Modal Nouveau RDV (saisi par le pro) ─────────────────────────────────────
// Miroir de l'appli (_showNouveauRdvDialog / _creerRdvManuel, pro_agenda.dart) :
// client qui appelle → RDV directement confirmé ; rattaché à son compte
// PetsMatch s'il en a un, sinon e-mail de confirmation + invitation.

const DUREES_MANUEL = [15, 30, 45, 60, 90];

function NouveauRdvModal({ proUid, profileId, proName, catPro, initial, onClose, onDone }: {
  proUid: string; profileId: string; proName: string; catPro: string;
  /** Depuis le planning : date-heure, praticien ('' = titulaire) et salle. */
  initial?: { date?: Date; praticien?: string | null; salle?: string | null };
  onClose: () => void; onDone: () => void;
}) {
  const d0 = initial?.date ?? new Date();
  const [clientNom, setClientNom] = useState('');
  const [clientTel, setClientTel] = useState('');
  const [clientEmail, setClientEmail] = useState('');
  const [animalNom, setAnimalNom] = useState('');
  const [motif, setMotif] = useState('');
  const [notes, setNotes] = useState('');
  const [date, setDate] = useState(toDateStr(d0));
  const [heure, setHeure] = useState(`${String(d0.getHours()).padStart(2, '0')}:${String(Math.floor(d0.getMinutes() / 15) * 15).padStart(2, '0')}`);
  const [duree, setDuree] = useState(30);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Compte PetsMatch existant (e-mail / téléphone exacts)
  const [searching, setSearching] = useState(false);
  const [searched, setSearched] = useState(false);
  const [found, setFound] = useState<{ uid: string; nom: string; profileId: string } | null>(null);
  const [linked, setLinked] = useState<{ uid: string; nom: string; profileId: string } | null>(null);
  // Clinique : praticien et salle
  const [praticiens, setPraticiens] = useState<{ id: string; nom: string }[]>([]);
  const [salles, setSalles] = useState<{ id: string; nom: string }[]>([]);
  const [praticien, setPraticien] = useState(initial?.praticien ?? '');
  const [salle, setSalle] = useState(initial?.salle ?? '');
  // Clinique : patient créé par la clinique (propriétaire hors appli) → RDV rattaché à sa fiche.
  const [patients, setPatients] = useState<{ animalId: string; animalNom: string; clientNom: string; tel: string; email: string }[]>([]);
  const [patientId, setPatientId] = useState('');
  useEffect(() => {
    if (catPro !== 'veterinaire' || !profileId) return;
    (async () => {
      const { data: g } = await supabase.from('animal_access').select('animal_id').eq('pro_profile_id', profileId).eq('statut', 'active');
      const ids = (g ?? []).map(x => x.animal_id as string);
      if (!ids.length) return;
      const { data: an } = await supabase.from('animaux').select('id, nom, client_clinique_id').in('id', ids).not('client_clinique_id', 'is', null);
      const cIds = [...new Set((an ?? []).map(x => x.client_clinique_id as string))];
      const { data: cl } = cIds.length ? await supabase.from('clients_clinique').select('id, nom, prenom, telephone, email').in('id', cIds) : { data: [] };
      const parId = new Map(((cl ?? []) as { id: string; nom: string; prenom: string | null; telephone: string | null; email: string | null }[]).map(c => [c.id, c]));
      setPatients(((an ?? []) as { id: string; nom: string; client_clinique_id: string }[]).map(x => {
        const c = parId.get(x.client_clinique_id);
        return { animalId: x.id, animalNom: x.nom ?? '', clientNom: c ? `${c.prenom ?? ''} ${c.nom}`.trim() : '', tel: c?.telephone ?? '', email: c?.email ?? '' };
      }).sort((a, b) => a.animalNom.localeCompare(b.animalNom)));
    })();
  }, [catPro, profileId]);

  useEffect(() => {
    if (catPro !== 'veterinaire' || !profileId) return;
    Promise.all([
      supabase.rpc('pm_praticiens_clinique', { p_pro_profile_id: profileId }),
      supabase.from('salles_clinique').select('id, nom').eq('clinique_profile_id', profileId).eq('actif', true).order('ordre'),
    ]).then(([pr, sa]) => {
      setPraticiens(((pr.data ?? []) as { praticien_profile_id: string | null; nom: string | null }[])
        .map(p => ({ id: p.praticien_profile_id ?? '', nom: p.nom?.trim() || 'Vétérinaire' })));
      setSalles(((sa.data ?? []) as { id: string; nom: string | null }[]).map(s => ({ id: s.id, nom: s.nom ?? 'Salle' })));
    });
  }, [catPro, profileId]);

  async function rechercher() {
    const email = clientEmail.trim(), tel = clientTel.trim();
    if (!email && !tel) return;
    setSearching(true); setFound(null);
    try {
      let u = email ? await trouverUtilisateurParEmail(email) : null;
      if (!u && tel.replace(/[^0-9]/g, '').length >= 9) {
        const { data } = await supabase.rpc('pm_trouver_utilisateur', { p_telephone: tel });
        u = ((data ?? []) as UtilisateurTrouve[])[0] ?? null;
      }
      if (u) {
        const { data: prof } = await supabase.from('user_profiles_complet')
          .select('id').eq('uid', u.uid).eq('profile_type', 'particulier').maybeSingle();
        if (prof?.id) setFound({ uid: u.uid, nom: `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim(), profileId: prof.id as string });
      }
    } finally { setSearching(false); setSearched(true); }
  }

  async function creer() {
    if (!linked) {
      const manque = [!clientNom.trim() && 'nom', !clientTel.trim() && 'téléphone', !clientEmail.trim() && 'email'].filter(Boolean);
      if (manque.length) { setError(`Champs requis : ${manque.join(', ')}.`); return; }
    }
    setSaving(true); setError(null);
    try {
      const dh = new Date(`${date}T${heure}:00`);
      const motifTxt = motif.trim() || 'RDV';
      const { data: ins, error: e } = await supabase.from('rdv').insert({
        pro_uid: proUid, pro_profile_id: profileId,
        ...(linked ? { client_uid: linked.uid, client_profile_id: linked.profileId } : {
          client_nom_manuel: clientNom.trim(),
          client_telephone_manuel: clientTel.trim() || null,
          client_email_manuel: clientEmail.trim() || null,
        }),
        ...(animalNom.trim() ? { animal_nom_manuel: animalNom.trim() } : {}),
        ...(patientId ? { animal_id: patientId } : {}),
        cree_par_pro: true,
        date_heure: dh.toISOString(),
        motif: motifTxt,
        duree_minutes: duree,
        ...(notes.trim() ? { notes_client: notes.trim() } : {}),
        statut: 'confirme',
        ...(praticien ? { instructeur_profile_id: praticien } : {}),
        ...(salle ? { salle_id: salle } : {}),
      }).select('id').single();
      if (e || !ins) throw e ?? new Error('insert');
      const rdvId = ins.id as string;
      const nomClient = linked?.nom || clientNom.trim() || 'Client';

      // Agenda du pro
      await supabase.from('agenda_events').insert({
        uid: proUid, titre: `RDV avec ${nomClient}${animalNom.trim() ? ` — ${animalNom.trim()}` : ''}`,
        type: typeFromMotif(motifTxt), date_debut: dh.toISOString(), duree_minutes: duree,
        notes: motifTxt, couleur: `rdv:${rdvId}`, pro_profile_id: profileId,
      });
      if (linked) {
        // Client PetsMatch : son agenda + notification « RDV confirmé ».
        await supabase.from('agenda_events').upsert({
          uid: linked.uid, titre: `RDV — ${proName}`, type: typeFromMotif(motifTxt),
          date_debut: dh.toISOString(), duree_minutes: duree, notes: motifTxt,
          rdv_id: rdvId, pro_profile_id: linked.profileId,
        }, { onConflict: 'rdv_id' });
        await supabase.from('notifications').insert({
          uid: linked.uid, type: 'rdv_confirme', title: `RDV confirmé par ${proName}`,
          body: `Votre rendez-vous est confirmé pour le ${dh.toLocaleDateString('fr-FR')} à ${heure.replace(':', 'h')}`,
          profile_id: linked.profileId, data: { rdv_id: rdvId }, read: false,
        });
      } else if (clientEmail.trim()) {
        // E-mail de confirmation + invitation à rejoindre PetsMatch.
        await apiFetch('/api/rdv/notify-email', {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ email: clientEmail.trim(), client_nom: clientNom.trim(), pro_nom: proName,
            date_heure: dh.toISOString(), motif: motif.trim() || null, duree_minutes: duree }),
        }).catch(() => {});
      }
      onDone();
    } catch (e) {
      const msg = (e as { message?: string })?.message;
      setError(msg && /créneau|salle/i.test(msg) ? msg : 'Erreur lors de la création du RDV.');
      setSaving(false);
    }
  }

  const champ = 'mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]';
  const label = 'text-xs font-semibold text-gray-500 uppercase tracking-wide';

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-md p-6 space-y-4 max-h-[92vh] overflow-y-auto"
        onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
        <div>
          <h2 className="font-bold text-lg text-[#1E2025]">📅 Nouveau RDV</h2>
          <p className="text-xs text-gray-400 mt-0.5">Pour un client qui appelle. Le RDV est ajouté directement confirmé.</p>
        </div>

        {patients.length > 0 && !linked && (
          <div><label className={label}>Patient de la clinique</label>
            <select value={patientId} className={`${champ} bg-white`} onChange={e => {
              const p = patients.find(x => x.animalId === e.target.value);
              setPatientId(e.target.value);
              if (p) { setAnimalNom(p.animalNom); setClientNom(p.clientNom); setClientTel(p.tel); setClientEmail(p.email); }
            }}>
              <option value="">— Aucun (saisie libre) —</option>
              {patients.map(p => <option key={p.animalId} value={p.animalId}>{p.animalNom}{p.clientNom ? ` · ${p.clientNom}` : ''}</option>)}
            </select></div>
        )}
        {linked ? (
          <div className="flex items-center gap-3 rounded-xl p-3" style={{ background: '#6E9E570C', border: '1px solid #6E9E5733' }}>
            <span>✅</span>
            <div className="flex-1 min-w-0">
              <p className="text-[11px] font-bold text-[#4A7A32]">RDV lié à un compte PetsMatch</p>
              <p className="text-sm font-semibold truncate">{linked.nom}</p>
            </div>
            <button onClick={() => setLinked(null)} className="text-xs text-gray-400 hover:text-gray-600">Détacher</button>
          </div>
        ) : (
          <>
            <div><label className={label}>Nom du client *</label>
              <input value={clientNom} onChange={e => setClientNom(e.target.value)} className={champ} /></div>
            <div><label className={label}>Téléphone *</label>
              <input value={clientTel} onChange={e => { setClientTel(e.target.value); setSearched(false); setFound(null); }} type="tel" className={champ} /></div>
            <div><label className={label}>Email *</label>
              <input value={clientEmail} onChange={e => { setClientEmail(e.target.value); setSearched(false); setFound(null); }} type="email" className={champ} /></div>
            {(clientEmail.trim() || clientTel.trim()) && (
              <button onClick={rechercher} disabled={searching} className="text-xs font-semibold underline" style={{ color: TEAL }}>
                {searching ? 'Recherche…' : '🔎 Ce client a-t-il déjà PetsMatch ?'}
              </button>
            )}
            {found ? (
              <div className="rounded-xl p-3 space-y-2" style={{ background: '#6E9E570C', border: '1px solid #6E9E5733' }}>
                <p className="text-sm font-semibold">Compte trouvé : {found.nom}</p>
                <button onClick={() => { setLinked(found); setFound(null); }}
                  className="w-full py-2 rounded-xl text-xs font-bold border" style={{ borderColor: '#6E9E57', color: '#4A7A32' }}>
                  Rattacher ce RDV à son compte
                </button>
              </div>
            ) : searched && !searching ? (
              <p className="text-[11px] text-gray-400">Aucun compte trouvé — le client recevra un email de confirmation l&apos;invitant à rejoindre PetsMatch.</p>
            ) : null}
          </>
        )}

        <div><label className={label}>Nom de l&apos;animal</label>
          <input value={animalNom} onChange={e => setAnimalNom(e.target.value)} className={champ} /></div>
        <div><label className={label}>Motif</label>
          <input value={motif} onChange={e => setMotif(e.target.value)} className={champ} /></div>

        <div className="grid grid-cols-2 gap-3">
          <div><label className={label}>Date</label>
            <input type="date" value={date} onChange={e => setDate(e.target.value)} className={champ} /></div>
          <div><label className={label}>Heure</label>
            <input type="time" step={300} value={heure} onChange={e => setHeure(e.target.value)} className={champ} /></div>
        </div>
        <div>
          <label className={label}>Durée</label>
          <div className="flex flex-wrap gap-2 mt-1">
            {DUREES_MANUEL.map(d => (
              <button key={d} onClick={() => setDuree(d)}
                className="px-3.5 py-1.5 rounded-xl text-xs border transition-all"
                style={{ background: duree === d ? TEAL : 'white', color: duree === d ? 'white' : '#1E2025',
                  borderColor: duree === d ? TEAL : '#E4E7E2', fontWeight: duree === d ? 700 : 400 }}>
                {d < 60 ? `${d} min` : d % 60 ? `${Math.floor(d / 60)}h${d % 60}` : `${d / 60} h`}
              </button>
            ))}
          </div>
        </div>

        {praticiens.length > 1 && (
          <div><label className={label}>Vétérinaire</label>
            <select value={praticien} onChange={e => setPraticien(e.target.value)} className={`${champ} bg-white`}>
              {praticiens.map(p => <option key={p.id} value={p.id}>{p.nom}</option>)}
            </select></div>
        )}
        {salles.length > 0 && (
          <div><label className={label}>Salle</label>
            <select value={salle} onChange={e => setSalle(e.target.value)} className={`${champ} bg-white`}>
              <option value="">Attribuée automatiquement</option>
              {salles.map(s => <option key={s.id} value={s.id}>{s.nom}</option>)}
            </select></div>
        )}

        <div><label className={label}>Notes (optionnel)</label>
          <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} className={`${champ} resize-none`} /></div>

        {error && <p className="text-xs text-red-500">{error}</p>}

        <div className="flex gap-3 pt-1">
          <button onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm text-gray-600 border border-gray-200 hover:bg-gray-50 font-semibold">
            Annuler
          </button>
          <button onClick={creer} disabled={saving}
            className="flex-1 py-2.5 rounded-xl text-sm text-white font-semibold disabled:opacity-50" style={{ background: TEAL }}>
            {saving ? '…' : 'Créer le RDV'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Modal Refuser / Annuler ────────────────────────────────────────────────────

function RefuserModal({ rdv, label, type, onClose, onDone }: {
  rdv: Rdv; label: string; type: 'refuse' | 'annule'; onClose: () => void; onDone: () => void;
}) {
  const [motif, setMotif]   = useState('');
  const [saving, setSaving] = useState(false);

  async function handleSubmit() {
    setSaving(true);
    try {
      await supabase.from('rdv').update({ statut: type, notes_annulation: motif || null }).eq('id', rdv.id);
      await supabase.from('agenda_events').delete().eq('rdv_id', rdv.id);
      await supabase.from('agenda_events').delete()
        .eq('uid', rdv.pro_uid).eq('couleur', `rdv:${rdv.id}`);
      await supabase.from('notifications').insert({
        uid: rdv.client_uid,
        type: type === 'refuse' ? 'rdv_refuse' : 'rdv_annule',
        title: type === 'refuse' ? 'Demande de RDV refusée' : 'RDV annulé',
        body: `${type === 'refuse' ? 'Votre demande a été refusée' : 'Votre RDV a été annulé'}${motif ? ` — Motif : ${motif}` : ''}`,
        ...(rdv.client_profile_id ? { profile_id: rdv.client_profile_id } : {}),
        data: { rdv_id: rdv.id }, read: false,
      });
      onDone();
    } catch { /* ignore */ } finally { setSaving(false); }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-sm p-6 space-y-4" onClick={e => e.stopPropagation()}>
        <h2 className="font-bold text-lg text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>{label} ce RDV</h2>
        <div className="bg-gray-50 rounded-xl p-3 text-sm">
          <p className="font-semibold">{rdv.clientName ?? '—'}</p>
          <p className="text-xs text-gray-400 mt-0.5">{fmtDate(rdv.date_heure)} à {fmtHeure(rdv.date_heure)}</p>
        </div>
        <textarea value={motif} onChange={e => setMotif(e.target.value)} rows={3}
          placeholder="Motif (optionnel)…"
          className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none focus:outline-none"
          style={{ fontFamily: 'Galey, sans-serif' }} />
        <div className="flex gap-3">
          <button onClick={onClose} className="flex-1 py-2.5 rounded-xl text-sm text-gray-600 border border-gray-200 hover:bg-gray-50 font-semibold">Retour</button>
          <button onClick={handleSubmit} disabled={saving}
            className="flex-1 py-2.5 rounded-xl text-sm text-white font-semibold bg-red-500 hover:bg-red-600 disabled:opacity-50">
            {saving ? '…' : label}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Carte RDV ──────────────────────────────────────────────────────────────────

function RdvCard({ rdv, tab, myUid, myProfileId, onAccepter, onRefuser, onAnnuler, onTerminer, onDelete, onOpenAnimal, onModifier, onHistorique }: {
  rdv: Rdv;
  tab: 'demandes' | 'a_venir' | 'historique';
  myUid: string;
  myProfileId: string | null;
  onAccepter?: () => void;
  onRefuser?: () => void;
  onAnnuler?: () => void;
  onTerminer?: () => void;
  onDelete?: () => void;
  onOpenAnimal?: (id: string) => void;
  /** Vétérinaire : historique des consultations du patient. */
  onHistorique?: () => void;
  onModifier?: () => void;
}) {
  const [confirmDel, setConfirmDel] = useState(false);
  const st      = STATUT_STYLE[rdv.statut] ?? { bg: '#F5F5F5', color: '#757575', label: rdv.statut };
  const isFirst = rdv.visitCount === 0;

  return (
    <div className="bg-white rounded-2xl px-4 py-4 shadow-sm border border-gray-100 space-y-3">
      <div className="flex items-start justify-between gap-2">
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2 flex-wrap">
            <p className="font-bold text-[#1E2025] text-sm" style={{ fontFamily: 'Galey, sans-serif' }}>
              {rdv.clientName ?? '—'}
            </p>
            <span className="text-xs px-2 py-0.5 rounded-full font-semibold"
              style={{ background: isFirst ? '#FFF8E1' : '#E3F2FD', color: isFirst ? '#F57F17' : '#1565C0', fontFamily: 'Galey, sans-serif' }}>
              {isFirst ? '⭐ 1ère visite' : `🔄 ${rdv.visitCount} visite${(rdv.visitCount ?? 0) > 1 ? 's' : ''}`}
            </span>
          </div>
          {rdv.animalNom && (
            <p className="text-xs text-gray-500 mt-0.5">🐾 {rdv.animalNom}</p>
          )}
          {rdv.statut === 'confirme' && (
            new Date(new Date(rdv.date_heure).getTime() + (rdv.duree_minutes ?? 30) * 60000) < new Date() || (rdv.retardMin ?? 0) >= 5
          ) && (
            <div className="flex flex-wrap gap-1.5 mt-1.5">
              {new Date(new Date(rdv.date_heure).getTime() + (rdv.duree_minutes ?? 30) * 60000) < new Date() && tab === 'a_venir' && (
                <span className="text-[11px] font-bold px-2 py-0.5 rounded-full" style={{ background: '#FFF4DC', color: '#8A5A00' }}>⏳ À clôturer — marquez-le terminé</span>
              )}
              {(rdv.retardMin ?? 0) >= 5 && (
                <span className="text-[11px] font-bold px-2 py-0.5 rounded-full" style={{ background: '#FDECEA', color: '#B3261E' }}>⏱ Retard estimé +{rdv.retardMin} min</span>
              )}
            </div>
          )}
          <p className="text-sm text-[#0C5C6C] mt-1 font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
            {fmtDate(rdv.date_heure)} à {fmtHeure(rdv.date_heure)}
          </p>
          {rdv.duree_minutes && (
            <p className="text-xs text-gray-400">⏱ {rdv.duree_minutes} min</p>
          )}
          {rdv.motif && <p className="text-xs text-gray-400 mt-0.5 truncate">Motif : {rdv.motif}</p>}
          {rdv.praticien_indifferent && rdv.statut === 'demande' && (
            <p className="text-xs font-semibold mt-0.5" style={{ color: '#2E7D5E' }}>🩺 Vétérinaire au choix — à attribuer</p>
          )}
          {rdv.lieu && (
            <p className="text-xs text-gray-400 mt-0.5">
              📍 {rdv.lieu}
              {' · '}
              <a target="_blank" rel="noopener"
                href={`https://www.google.com/maps/search/?api=1&query=${rdv.lieu_lat != null && rdv.lieu_lng != null ? `${rdv.lieu_lat},${rdv.lieu_lng}` : encodeURIComponent(rdv.lieu)}`}
                className="font-semibold" style={{ color: TEAL }}>Itinéraire</a>
            </p>
          )}
          {rdv.notes_annulation && <p className="text-xs text-red-400 mt-0.5">Note : {rdv.notes_annulation}</p>}
          {rdv.notes_client && rdv.notes_client.trim() && (
            <div className="mt-2 rounded-lg border px-2.5 py-2" style={{ borderColor: '#0C5C6C26', background: '#0C5C6C0C' }}>
              <p className="text-[11px] font-bold" style={{ color: TEAL, fontFamily: 'Galey, sans-serif' }}>💬 Message du client</p>
              <p className="text-xs text-gray-600 mt-0.5" style={{ fontFamily: 'Galey, sans-serif' }}>{rdv.notes_client}</p>
            </div>
          )}
        </div>
        <span className="text-xs px-2 py-0.5 rounded-full font-semibold flex-shrink-0"
          style={{ background: st.bg, color: st.color, fontFamily: 'Galey, sans-serif' }}>
          {st.label}
        </span>
      </div>

      {/* Infos client — dispo sur tous les onglets, y compris une demande en attente */}
      {(rdv.animal_id || rdv.client_uid || rdv.client_telephone_manuel) && (
        <div className="flex gap-2 flex-wrap items-center">
          {rdv.animal_id && rdv.client_uid && (
            <OwnerContactButton
              animalId={String(rdv.animal_id)}
              animalNom={rdv.animalNom ?? rdv.clientName ?? 'Animal'}
              ownerUid={rdv.client_uid}
              myUid={myUid}
              myProfileId={myProfileId}
            />
          )}
          {!rdv.client_uid && rdv.client_telephone_manuel && (
            <a href={`tel:${rdv.client_telephone_manuel.replace(/[^0-9+]/g, '')}`}
              className="text-xs font-semibold px-3 py-1.5 rounded-xl border"
              style={{ borderColor: TEAL, color: TEAL, fontFamily: 'Galey, sans-serif' }}>
              📞 {rdv.client_telephone_manuel}
            </a>
          )}
          {rdv.animal_id && (
            <button onClick={() => onOpenAnimal?.(String(rdv.animal_id))}
              className="text-xs font-semibold px-3 py-1.5 rounded-xl border"
              style={{ borderColor: '#6E9E57', color: '#6E9E57', fontFamily: 'Galey, sans-serif' }}>
              🐾 Fiche de l&apos;animal
            </button>
          )}
          {rdv.animal_id && onHistorique && (
            <button onClick={onHistorique}
              className="text-xs font-semibold px-3 py-1.5 rounded-xl border"
              style={{ borderColor: TEAL, color: TEAL, fontFamily: 'Galey, sans-serif' }}>
              🕘 Historique
            </button>
          )}
        </div>
      )}

      <div className="flex gap-2 flex-wrap">
        {tab === 'demandes' && (
          <>
            <button onClick={onAccepter}
              className="flex-1 min-w-[80px] text-xs font-semibold px-3 py-2 rounded-xl text-white"
              style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
              ✓ Accepter
            </button>
            <button onClick={onRefuser}
              className="flex-1 min-w-[80px] text-xs font-semibold px-3 py-2 rounded-xl text-red-600 border border-red-200 hover:bg-red-50"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              ✗ Refuser
            </button>
          </>
        )}
        {tab === 'a_venir' && (
          <>
            <button onClick={onModifier}
              className="text-xs font-semibold px-3 py-2 rounded-xl border"
              style={{ borderColor: TEAL, color: TEAL, fontFamily: 'Galey, sans-serif' }}>
              ✏️ Modifier
            </button>
            <button onClick={onTerminer}
              className="flex-1 min-w-[80px] text-xs font-semibold px-3 py-2 rounded-xl text-white"
              style={{ background: GREEN, fontFamily: 'Galey, sans-serif' }}>
              ✓ Terminé
            </button>
            <button onClick={onAnnuler}
              className="flex-1 min-w-[80px] text-xs font-semibold px-3 py-2 rounded-xl text-red-600 border border-red-200 hover:bg-red-50"
              style={{ fontFamily: 'Galey, sans-serif' }}>
              Annuler
            </button>
          </>
        )}
        {tab === 'historique' && (
          <>
            {confirmDel ? (
              <div className="flex gap-2 items-center flex-1">
                <span className="text-xs text-gray-500 flex-1">Supprimer définitivement ?</span>
                <button onClick={() => setConfirmDel(false)}
                  className="px-3 py-1.5 rounded-xl text-xs border border-gray-200">Non</button>
                <button onClick={onDelete}
                  className="px-3 py-1.5 rounded-xl text-xs text-white bg-red-500 font-semibold">Oui</button>
              </div>
            ) : (
              <button onClick={() => setConfirmDel(true)}
                className="text-xs text-red-400 hover:text-red-600 px-3 py-1.5 rounded-xl border border-red-100"
                style={{ fontFamily: 'Galey, sans-serif' }}>
                Supprimer
              </button>
            )}
          </>
        )}
      </div>
    </div>
  );
}

// ── Onglet Créneaux ────────────────────────────────────────────────────────────

// Helpers 15 min (partagés avec /pro/creneaux)
function timeToMins(t: string): number {
  const [h, m] = t.split(':').map(Number);
  return h * 60 + m;
}
function minsToTime(m: number): string {
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
}
function snapTo15(t: string): string {
  return minsToTime(Math.floor(timeToMins(t) / 15) * 15);
}
interface SlotRange { start: string; end: string; statut: SlotStatus; }
function groupRanges(slotsForDate: { time: string; statut: SlotStatus }[]): SlotRange[] {
  const sorted = [...slotsForDate].sort((a, b) => a.time.localeCompare(b.time));
  if (!sorted.length) return [];
  const ranges: SlotRange[] = [];
  let rStart = sorted[0].time;
  let prevMins = timeToMins(sorted[0].time);
  let curStatut = sorted[0].statut;
  for (let i = 1; i < sorted.length; i++) {
    const curMins = timeToMins(sorted[i].time);
    if (sorted[i].statut === curStatut && curMins === prevMins + 15) {
      prevMins = curMins;
    } else {
      ranges.push({ start: rStart, end: minsToTime(prevMins + 15), statut: curStatut });
      rStart = sorted[i].time; prevMins = curMins; curStatut = sorted[i].statut;
    }
  }
  ranges.push({ start: rStart, end: minsToTime(prevMins + 15), statut: curStatut });
  return ranges;
}

function CreneauxTab({ uid, profileId }: { uid: string; profileId: string }) {
  const [weekStart, setWeekStart]           = useState(() => getMonday(new Date()));
  const [selectedDayIdx, setSelectedDayIdx] = useState(0);
  const [slots, setSlots]                   = useState<Record<string, SlotStatus>>({});
  const [loadingSlots, setLoadingSlots]     = useState(false);
  const [saving, setSaving]                 = useState(false);
  const [replicating, setReplicating]       = useState(false);
  const [showRepModal, setShowRepModal]     = useState(false);
  const [repChoice, setRepChoice]           = useState<'4sem' | 'annee' | 'perso'>('4sem');
  const [repEndDate, setRepEndDate]         = useState('');
  // Add-range modal
  const [showAddModal, setShowAddModal]     = useState(false);
  const [addMode, setAddMode]               = useState<SlotStatus>('disponible');
  const [addStart, setAddStart]             = useState('09:00');
  const [addEnd, setAddEnd]                 = useState('10:00');

  const loadSlots = useCallback(async () => {
    setLoadingSlots(true);
    const end = new Date(weekStart);
    end.setDate(weekStart.getDate() + 6);
    try {
      const { data } = await supabase
        .from('creneaux_pro')
        .select('date, heure_debut, statut')
        .eq('pro_uid', uid)
        .eq('pro_profile_id', profileId)
        .in('statut', ['disponible', 'bloque'])
        .gte('date', toDateStr(weekStart))
        .lte('date', toDateStr(end));
      const map: Record<string, SlotStatus> = {};
      for (const r of (data ?? []) as { date: string; heure_debut: string; statut: SlotStatus }[]) {
        const hhmm = r.heure_debut.substring(0, 5); // 'HH:MM'
        map[`${r.date}_${hhmm}`] = r.statut;
      }
      setSlots(map);
    } catch { /* ignore */ }
    setLoadingSlots(false);
  }, [uid, profileId, weekStart]);

  useEffect(() => { loadSlots(); }, [loadSlots]);

  const days        = Array.from({ length: 7 }, (_, i) => { const d = new Date(weekStart); d.setDate(weekStart.getDate() + i); return d; });
  const selectedDay = days[selectedDayIdx];
  const dateStr     = toDateStr(selectedDay);

  // Plages regroupées pour le jour sélectionné
  const slotsForDay = Object.entries(slots)
    .filter(([k]) => k.startsWith(`${dateStr}_`))
    .map(([k, statut]) => ({ time: k.slice(dateStr.length + 1), statut }));
  const ranges = groupRanges(slotsForDay);

  async function applyRange(start: string, end: string, statut: SlotStatus) {
    if (saving) return;
    setSaving(true);
    let cur = timeToMins(start);
    const endM = timeToMins(end);
    const newSlots: Record<string, SlotStatus> = {};
    const rows: Record<string, unknown>[] = [];
    while (cur < endM) {
      const hhmm = minsToTime(cur);
      const fin  = minsToTime(cur + 15);
      const key  = `${dateStr}_${hhmm}`;
      newSlots[key] = statut;
      rows.push({ pro_uid: uid, pro_profile_id: profileId, date: dateStr,
        heure_debut: `${hhmm}:00`, heure_fin: `${fin}:00`, statut });
      cur += 15;
    }
    setSlots(s => ({ ...s, ...newSlots }));
    try {
      await supabase.from('creneaux_pro').upsert(rows, { onConflict: 'pro_uid,pro_profile_id,praticien_profile_id,date,heure_debut' });
    } catch {
      setSlots(s => { const n = { ...s }; Object.keys(newSlots).forEach(k => delete n[k]); return n; });
    }
    setSaving(false);
  }

  async function deleteRange(r: SlotRange) {
    let cur = timeToMins(r.start);
    const endM = timeToMins(r.end);
    const hdList: string[] = [];
    const keyList: string[] = [];
    while (cur < endM) {
      const hhmm = minsToTime(cur);
      hdList.push(`${hhmm}:00`);
      keyList.push(`${dateStr}_${hhmm}`);
      cur += 15;
    }
    setSlots(s => { const n = { ...s }; keyList.forEach(k => delete n[k]); return n; });
    try {
      await supabase.from('creneaux_pro').delete()
        .eq('pro_uid', uid).eq('pro_profile_id', profileId)
        .eq('date', dateStr).in('heure_debut', hdList);
    } catch { loadSlots(); }
  }

  async function handleReplicate() {
    const weekSlots = Object.entries(slots).filter(([, v]) => v === 'disponible');
    if (!weekSlots.length) return;
    let endDate: Date;
    if (repChoice === 'annee') {
      endDate = new Date(weekStart.getFullYear(), 11, 31);
    } else if (repChoice === 'perso' && repEndDate) {
      endDate = new Date(repEndDate);
    } else {
      endDate = new Date(weekStart); endDate.setDate(weekStart.getDate() + 28);
    }
    setReplicating(true); setShowRepModal(false);
    try {
      const rows: Record<string, unknown>[] = [];
      let target = new Date(weekStart);
      target.setDate(target.getDate() + 7);
      while (target <= endDate) {
        for (const [key] of weekSlots) {
          const underIdx = key.lastIndexOf('_');
          const datePart = key.slice(0, underIdx);
          const hhmm     = key.slice(underIdx + 1);
          const orig     = new Date(datePart);
          const dayDiff  = Math.round((orig.getTime() - weekStart.getTime()) / 86400000);
          const tDay     = new Date(target);
          tDay.setDate(target.getDate() + dayDiff);
          const fin = minsToTime(timeToMins(hhmm) + 15);
          rows.push({ pro_uid: uid, pro_profile_id: profileId, date: toDateStr(tDay),
            heure_debut: `${hhmm}:00`, heure_fin: `${fin}:00`, statut: 'disponible' });
        }
        target = new Date(target); target.setDate(target.getDate() + 7);
      }
      const seen = new Set<string>();
      const deduped = rows.filter(r => {
        const k = `${r.date}_${r.heure_debut}`;
        return seen.has(k as string) ? false : (seen.add(k as string), true);
      });
      if (deduped.length) await supabase.from('creneaux_pro').upsert(deduped, { onConflict: 'pro_uid,pro_profile_id,praticien_profile_id,date,heure_debut' });
    } catch { /* ignore */ }
    setReplicating(false);
  }

  const dispCount = Object.values(slots).filter(v => v === 'disponible').length;

  return (
    <div className="space-y-4">
      {/* Navigation semaine */}
      <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-4">
        <div className="flex items-center justify-between mb-3">
          <button onClick={() => { setSlots({}); setWeekStart(d => { const n = new Date(d); n.setDate(d.getDate() - 7); return n; }); }}
            className="p-2 rounded-lg hover:bg-gray-100 text-lg font-bold" style={{ color: TEAL }}>‹</button>
          <span className="text-sm font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
            Semaine du {weekStart.getDate()} {MOIS[weekStart.getMonth()]}
          </span>
          <button onClick={() => { setSlots({}); setWeekStart(d => { const n = new Date(d); n.setDate(d.getDate() + 7); return n; }); }}
            className="p-2 rounded-lg hover:bg-gray-100 text-lg font-bold" style={{ color: TEAL }}>›</button>
        </div>
        <div className="flex gap-1.5 overflow-x-auto pb-1">
          {days.map((day, i) => {
            const sel     = i === selectedDayIdx;
            const isToday = toDateStr(day) === toDateStr(new Date());
            return (
              <button key={i} onClick={() => setSelectedDayIdx(i)}
                className="flex-shrink-0 w-11 py-2 rounded-xl text-center border transition-colors"
                style={{ background: sel ? TEAL : isToday ? `${TEAL}15` : 'white', borderColor: sel ? TEAL : isToday ? TEAL : '#e5e7eb' }}>
                <div className="text-[10px] font-semibold" style={{ color: sel ? 'white' : '#6B7280' }}>
                  {JOURS[day.getDay() === 0 ? 6 : day.getDay() - 1]}
                </div>
                <div className="text-sm font-bold" style={{ color: sel ? 'white' : isToday ? TEAL : '#1F2937' }}>
                  {day.getDate()}
                </div>
              </button>
            );
          })}
        </div>
      </div>

      {/* Actions */}
      <div className="flex gap-2">
        <button onClick={() => setShowAddModal(true)}
          className="flex-1 py-3 rounded-xl text-sm font-semibold text-white flex items-center justify-center gap-2"
          style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
          + Nouvelle plage
        </button>
        <button onClick={() => setShowRepModal(true)} disabled={dispCount === 0 || replicating}
          className="px-4 py-3 rounded-xl text-sm font-semibold border-2 transition-colors disabled:opacity-40"
          style={{ borderColor: TEAL, color: TEAL, fontFamily: 'Galey, sans-serif' }}
          title="Répliquer la semaine">
          🔁
        </button>
      </div>

      {/* Plages du jour */}
      {loadingSlots ? (
        <div className="flex justify-center py-10 text-sm text-gray-400">Chargement…</div>
      ) : ranges.length === 0 ? (
        <div className="bg-white rounded-2xl border border-dashed border-gray-200 p-8 text-center">
          <p className="text-3xl mb-2">🗓</p>
          <p className="text-sm text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
            Aucune plage configurée
          </p>
          <p className="text-xs text-gray-300 mt-1">Appuyez sur « + Nouvelle plage » pour ajouter une disponibilité ou un blocage</p>
        </div>
      ) : (
        <div className="flex flex-col gap-2">
          {ranges.map((r, i) => {
            const isDisp = r.statut === 'disponible';
            return (
              <div key={i} className="bg-white rounded-2xl px-4 py-3.5 shadow-sm border-2 flex items-center gap-3"
                style={{ borderColor: isDisp ? GREEN : ORANGE }}>
                <div className="flex-1">
                  <p className="text-lg font-bold" style={{ fontFamily: 'Galey, sans-serif', color: isDisp ? '#4A7A32' : '#E65100' }}>
                    {r.start} → {r.end}
                  </p>
                  <span className="text-xs font-semibold px-2 py-0.5 rounded-full"
                    style={{ background: isDisp ? `${GREEN}22` : '#FFF3E0', color: isDisp ? '#4A7A32' : '#E65100' }}>
                    {isDisp ? '✓ Disponible' : '🚫 Bloqué'}
                  </span>
                </div>
                <button onClick={() => deleteRange(r)}
                  className="p-2 rounded-xl hover:bg-red-50 text-red-400 hover:text-red-600 transition-colors text-sm">
                  🗑
                </button>
              </div>
            );
          })}
        </div>
      )}

      {/* Modal — Nouvelle plage */}
      {showAddModal && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4"
          onClick={() => setShowAddModal(false)}>
          <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-sm p-6 space-y-5"
            onClick={e => e.stopPropagation()}>
            <h3 className="font-bold text-base text-[#1E2025]" style={{ fontFamily: 'Galey, sans-serif' }}>
              Nouvelle plage
            </h3>

            {/* Mode */}
            <div className="flex gap-2">
              {(['disponible', 'bloque'] as const).map(m => {
                const col = m === 'disponible' ? GREEN : ORANGE;
                return (
                  <button key={m} onClick={() => setAddMode(m)}
                    className="flex-1 py-2.5 rounded-xl text-sm font-semibold border-2 transition-all"
                    style={{ background: addMode === m ? `${col}18` : 'white', borderColor: addMode === m ? col : '#e5e7eb', color: addMode === m ? (m === 'disponible' ? '#4A7A32' : '#E65100') : '#6B7280', fontFamily: 'Galey, sans-serif' }}>
                    {m === 'disponible' ? '✓ Disponible' : '🚫 Bloqué'}
                  </button>
                );
              })}
            </div>

            {/* Horaires */}
            <div className="flex items-center gap-3">
              <div className="flex-1">
                <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide block mb-1">De</label>
                <input type="time" step="900" value={addStart}
                  onChange={e => setAddStart(snapTo15(e.target.value || addStart))}
                  className="w-full border-2 border-gray-200 rounded-xl px-3 py-3 text-xl font-bold text-center focus:outline-none focus:border-[#0C5C6C] text-[#1E2025]"
                  style={{ fontFamily: 'Galey, sans-serif' }} />
              </div>
              <span className="text-2xl text-gray-400 mt-5">→</span>
              <div className="flex-1">
                <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide block mb-1">À</label>
                <input type="time" step="900" value={addEnd}
                  onChange={e => setAddEnd(snapTo15(e.target.value || addEnd))}
                  className="w-full border-2 border-gray-200 rounded-xl px-3 py-3 text-xl font-bold text-center focus:outline-none focus:border-[#0C5C6C] text-[#1E2025]"
                  style={{ fontFamily: 'Galey, sans-serif' }} />
              </div>
            </div>

            {timeToMins(addEnd) <= timeToMins(addStart) && (
              <p className="text-xs text-red-500 -mt-2">L&apos;heure de fin doit être après l&apos;heure de début.</p>
            )}

            <div className="flex gap-3">
              <button onClick={() => setShowAddModal(false)}
                className="flex-1 py-2.5 rounded-xl border border-gray-200 text-sm font-semibold text-gray-500">
                Annuler
              </button>
              <button
                onClick={async () => {
                  if (timeToMins(addEnd) <= timeToMins(addStart)) return;
                  setShowAddModal(false);
                  await applyRange(addStart, addEnd, addMode);
                }}
                disabled={saving || timeToMins(addEnd) <= timeToMins(addStart)}
                className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white disabled:opacity-50"
                style={{ background: addMode === 'disponible' ? GREEN : ORANGE, fontFamily: 'Galey, sans-serif' }}>
                {saving ? '…' : 'Appliquer'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Modal répliquer */}
      {showRepModal && (
        <div className="fixed inset-0 bg-black/40 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-2xl p-6 w-full max-w-sm shadow-xl">
            <h3 className="font-bold text-base mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>Répliquer les créneaux</h3>
            <p className="text-sm text-gray-500 mb-4">{dispCount} créneau(x) disponibles à répliquer.</p>
            <div className="flex flex-col gap-2.5 mb-5">
              {([['4sem', '4 semaines suivantes'], ['annee', "Jusqu'à la fin de l'année"], ['perso', 'Date personnalisée…']] as const).map(([v, l]) => (
                <label key={v} className="flex items-center gap-2 cursor-pointer text-sm font-medium" style={{ fontFamily: 'Galey, sans-serif' }}>
                  <input type="radio" name="rep" checked={repChoice === v} onChange={() => setRepChoice(v)} style={{ accentColor: TEAL }} />
                  {l}
                </label>
              ))}
              {repChoice === 'perso' && (
                <input type="date" value={repEndDate} onChange={e => setRepEndDate(e.target.value)}
                  className="mt-1 px-3 py-2 border border-gray-200 rounded-xl text-sm w-full focus:outline-none" />
              )}
            </div>
            <div className="flex gap-2">
              <button onClick={() => setShowRepModal(false)}
                className="flex-1 py-2.5 rounded-xl border border-gray-200 text-sm font-semibold text-gray-500">Annuler</button>
              <button onClick={handleReplicate}
                className="flex-1 py-2.5 rounded-xl text-sm font-semibold text-white" style={{ background: TEAL }}>Répliquer</button>
            </div>
          </div>
        </div>
      )}
      {replicating && (
        <div className="fixed inset-0 bg-black/20 flex items-center justify-center z-50">
          <div className="bg-white rounded-2xl px-8 py-5 text-sm font-semibold shadow-xl" style={{ color: TEAL }}>Réplication en cours…</div>
        </div>
      )}
    </div>
  );
}

// ── Page principale ────────────────────────────────────────────────────────────

type TabKey = 'demandes' | 'a_venir' | 'historique' | 'creneaux' | 'planning';

export default function MesRdvPage() {
  const { user, userData, loading } = useAuth();
  const router      = useRouter();
  const activeProfileId = useActiveProfile();

  const [activeTab, setActiveTab] = useState<TabKey>('demandes');
  const [rdvs, setRdvs]           = useState<Rdv[]>([]);
  const [fetching, setFetching]   = useState(true);
  const [catPro, setCatPro]       = useState('');

  const [modalAccepter, setModalAccepter] = useState<Rdv | null>(null);
  const [modalRefuser, setModalRefuser]   = useState<Rdv | null>(null);
  const [modalModifier, setModalModifier] = useState<Rdv | null>(null);
  const [modalAnnuler, setModalAnnuler]   = useState<Rdv | null>(null);
  const [historiqueRdv, setHistoriqueRdv] = useState<Rdv | null>(null);
  const [modalNouveau, setModalNouveau]   = useState<{ date?: Date; praticien?: string | null; salle?: string | null } | null>(null);

  const [aujourdhui, setAujourdhui] = useState<{ id: string; titre: string; date_debut: string; type: string }[]>([]);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  // Résoudre le cat_pro depuis le profil actif
  useEffect(() => {
    async function resolveCatPro() {
      if (activeProfileId) {
        const { data } = await supabase.from('user_profiles_complet')
          .select('profile_type, cat_pro').eq('id', activeProfileId).single();
        if (data) {
          const r = data as { profile_type: string; cat_pro: string };
          setCatPro(r.profile_type ?? r.cat_pro ?? '');
          return;
        }
      }
      setCatPro(userData?.catPro ?? '');
    }
    resolveCatPro();
  }, [activeProfileId, userData]);

  // Vétérinaire : l'agenda s'ouvre sur « À venir » (une seule fois).
  const ongletInitialFait = useRef(false);
  const [rdvFocus, setRdvFocus] = useState<string | null>(null);
  useEffect(() => {
    if (ongletInitialFait.current || !catPro) return;
    ongletInitialFait.current = true;
    // Lien depuis l'accueil vétérinaire : ?onglet=…&rdv=… (lu sans
    // useSearchParams, qui exige un Suspense au build).
    const q = new URLSearchParams(window.location.search);
    const onglet = q.get('onglet') as TabKey | null;
    if (onglet && ['demandes', 'a_venir', 'historique', 'creneaux', 'planning'].includes(onglet)) setActiveTab(onglet);
    else if (catPro === 'veterinaire') setActiveTab('a_venir');
    setRdvFocus(q.get('rdv'));
  }, [catPro]);

  // RDV visé : défile jusqu'à sa carte et la met en avant.
  useEffect(() => {
    if (!rdvFocus || fetching) return;
    const el = document.getElementById(`rdv-${rdvFocus}`);
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }, [rdvFocus, fetching, activeTab]);

  const proName = userData?.nameElevage ?? userData?.firstname ?? 'Le professionnel';

  const fetchRdvs = useCallback(async () => {
    if (!user) return;
    setFetching(true);
    try {
      const { data } = await supabase
        .from('rdv')
        .select('id, pro_uid, client_uid, pro_profile_id, client_profile_id, animal_id, date_heure, motif, statut, notes_annulation, notes_pro, notes_client, client_nom_manuel, client_telephone_manuel, duree_minutes, premiere_visite, lieu, lieu_lat, lieu_lng, instructeur_profile_id, praticien_indifferent, salle_id, animal_nom_manuel, termine_at')
        .eq('pro_uid', user.uid)
        .eq('pro_profile_id', activeProfileId)
        .order('date_heure', { ascending: true });

      const list = (data ?? []) as Rdv[];
      const clientUids = [...new Set(list.map(r => r.client_uid).filter(Boolean))];
      const clientProfileIds = [...new Set(list.map(r => r.client_profile_id).filter(Boolean) as string[])];
      const animalIds  = [...new Set(list.map(r => r.animal_id).filter(Boolean) as string[])];

      // ⚠ Multi-profil : le nom vient du profil client_profile_id du RDV
      // (pas de name_elevage / is_main, qui affichent le nom d'élevage).
      const [profilesRes, usersRes, animauxRes] = await Promise.all([
        clientProfileIds.length ? supabase.from('user_profiles_complet').select('id, firstname, lastname, nom').in('id', clientProfileIds) : Promise.resolve({ data: [] }),
        clientUids.length ? supabase.from('users_complet').select('uid, firstname, lastname, prenom, nom').in('uid', clientUids) : Promise.resolve({ data: [] }),
        animalIds.length  ? supabase.from('animaux').select('id, nom').in('id', animalIds) : Promise.resolve({ data: [] }),
      ]);

      const profilesMap: Record<string, string> = {};
      for (const p of (profilesRes.data ?? [])) {
        const rec = p as { id: string; firstname?: string; lastname?: string; nom?: string };
        const name = (rec.nom ?? '').trim() || `${rec.firstname ?? ''} ${rec.lastname ?? ''}`.trim();
        if (name) profilesMap[rec.id] = name;
      }
      const usersMap: Record<string, string> = {};
      for (const u of (usersRes.data ?? [])) {
        const rec = u as { uid: string; firstname?: string; lastname?: string; prenom?: string; nom?: string };
        usersMap[rec.uid] = [rec.prenom ?? rec.firstname, rec.nom ?? rec.lastname].filter(Boolean).join(' ') || 'Client';
      }
      const animauxMap: Record<string, string> = {};
      for (const a of (animauxRes.data ?? [])) {
        const rec = a as { id: string; nom?: string };
        if (rec.nom) animauxMap[rec.id] = rec.nom;
      }

      const visitCounts: Record<string, number> = {};
      if (clientUids.length) {
        const { data: hist } = await supabase.from('rdv')
          .select('client_uid').eq('pro_uid', user.uid)
          .in('client_uid', clientUids).in('statut', ['confirme', 'termine']);
        for (const h of (hist ?? [])) {
          const cUid = (h as { client_uid: string }).client_uid;
          visitCounts[cUid] = (visitCounts[cUid] ?? 0) + 1;
        }
      }

      setRdvs(list.map(r => ({
        ...r,
        clientName: (r.client_profile_id ? profilesMap[r.client_profile_id] : undefined) ?? usersMap[r.client_uid] ?? undefined,
        // Nom figé à la réservation (animal_nom_manuel) si la fiche n'est pas lisible.
        animalNom:  (r.animal_id ? animauxMap[String(r.animal_id)] : undefined) || r.animal_nom_manuel || undefined,
        visitCount: visitCounts[r.client_uid] ?? 0,
      })));
    } catch { /* ignore */ } finally { setFetching(false); }
  }, [user, activeProfileId]);

  useEffect(() => { fetchRdvs(); }, [fetchRdvs]);

  const fetchAujourdhui = useCallback(async () => {
    // Ne pas interroger tant que le profil actif n'est pas résolu — un
    // filtre absent ferait fuiter les séances de tous les profils
    // (ex : pension visible depuis le profil éducation).
    if (!user || !activeProfileId) return;
    const start = new Date(); start.setHours(0, 0, 0, 0);
    const end = new Date(start); end.setDate(end.getDate() + 1);
    try {
      const { data } = await supabase.from('agenda_events').select('id, titre, date_debut, type')
        .eq('uid', user.uid)
        .eq('pro_profile_id', activeProfileId)
        .gte('date_debut', start.toISOString()).lt('date_debut', end.toISOString())
        .order('date_debut');
      setAujourdhui((data ?? []) as { id: string; titre: string; date_debut: string; type: string }[]);
    } catch { /* ignore */ }
  }, [user, activeProfileId]);

  useEffect(() => { fetchAujourdhui(); }, [fetchAujourdhui]);

  async function marquerTermine(rdv: Rdv) {
    // Heure réelle de fin : base des retards en cascade (alerte automatique).
    await supabase.from('rdv').update({ statut: 'termine', termine_at: new Date().toISOString() }).eq('id', rdv.id);
    // Séance terminée → invite la famille à laisser un avis (une seule fois :
    // pas de relance si un avis existe déjà ou si la notif a déjà été postée).
    try {
      if (user && rdv.client_uid) {
        let avisQ = supabase.from('avis_pro').select('id')
          .eq('pro_uid', user.uid).eq('client_uid', rdv.client_uid);
        if (rdv.pro_profile_id) avisQ = avisQ.eq('pro_profile_id', rdv.pro_profile_id);
        const [{ data: existingAvis }, { data: dupNotif }] = await Promise.all([
          avisQ.limit(1).maybeSingle(),
          supabase.from('notifications').select('id')
            .eq('uid', rdv.client_uid).eq('type', 'avis_demande')
            .contains('data', { rdv_id: rdv.id }).limit(1).maybeSingle(),
        ]);
        if (!existingAvis && !dupNotif) {
          const proNom = (userData?.nameElevage
            ?? `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim()) || 'votre professionnel';
          await supabase.from('notifications').insert({
            uid: rdv.client_uid, type: 'avis_demande',
            title: 'Votre avis compte',
            body: `Comment s'est passée votre séance avec ${proNom} ? Laissez un avis.`,
            ...(rdv.client_profile_id ? { profile_id: rdv.client_profile_id } : {}),
            data: {
              rdv_id: rdv.id, pro_uid: user.uid,
              ...(rdv.pro_profile_id ? { pro_profile_id: rdv.pro_profile_id } : {}),
              pro_nom: proNom,
              url: `/services/pro/${user.uid}?avis=1${rdv.pro_profile_id ? `&profileId=${rdv.pro_profile_id}` : ''}`,
            },
            read: false,
          });
        }
      }
    } catch { /* ignore */ }
    fetchRdvs();
  }

  async function deleteRdv(rdvId: string) {
    await supabase.from('agenda_events').delete().eq('rdv_id', rdvId);
    if (user) {
      await supabase.from('agenda_events').delete()
        .eq('uid', user.uid).eq('couleur', `rdv:${rdvId}`);
    }
    await supabase.from('rdv').delete().eq('id', rdvId);
    setRdvs(prev => prev.filter(r => r.id !== rdvId));
  }

  function openAnimalFiche(animalId: string) {
    router.push(`/mes-patients/${animalId}`);
  }

  if (loading) return (
    <div className="flex justify-center py-32">
      <div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
    </div>
  );

  if (!user) return null;

  const now = new Date();
  const demandes   = rdvs.filter(r => r.statut === 'demande' || r.statut === 'contre_proposition');
  // Vétérinaire : un RDV reste « À venir » tant qu'il n'est pas marqué
  // terminé (même passé — « À clôturer ») et porte son retard estimé.
  const estVeto = catPro === 'veterinaire';
  const retards = estVeto ? retardsEnCascade(rdvs) : {};
  const aVenir     = estVeto
    ? rdvs.filter(r => r.statut === 'confirme').map(r => ({ ...r, retardMin: retards[r.id] }))
    : rdvs.filter(r => r.statut === 'confirme' && new Date(r.date_heure) > now);
  const historique = rdvs.filter(r =>
    r.statut !== 'demande' && r.statut !== 'contre_proposition' &&
    !(r.statut === 'confirme' && (estVeto || new Date(r.date_heure) > now))
  );

  const TABS: { key: TabKey; label: string; badge: number }[] = [
    { key: 'demandes',   label: 'Demandes',   badge: demandes.length   },
    { key: 'a_venir',    label: 'À venir',    badge: aVenir.length     },
    { key: 'historique', label: 'Historique', badge: 0                 },
    { key: 'creneaux',   label: 'Créneaux',   badge: 0                 },
    // Clinique : journée en colonnes par praticien / par salle.
    ...(catPro === 'veterinaire' ? [{ key: 'planning' as TabKey, label: 'Planning', badge: 0 }] : []),
  ];

  const currentList = activeTab === 'demandes' ? demandes : activeTab === 'a_venir' ? aVenir : historique;

  const pageTitle = PRO_TITLE[catPro] ?? 'Mes rendez-vous';

  return (
    <div className="bg-[#F8F8F6] min-h-screen">
      {/* Header */}
      <div style={{ background: TEAL }} className="text-white px-4 py-6">
        <div className="max-w-3xl mx-auto">
          <div className="flex items-center gap-3 mb-4">
            <button onClick={() => router.back()}
              className="p-2 rounded-lg bg-white/10 hover:bg-white/20 transition-colors">
              ←
            </button>
            <h1 className="text-xl font-bold flex-1" style={{ fontFamily: 'Galey, sans-serif' }}>{pageTitle}</h1>
            <button onClick={() => setModalNouveau({})}
              className="px-3 py-2 rounded-xl bg-white text-sm font-semibold hover:bg-white/90 transition-colors"
              style={{ color: TEAL, fontFamily: 'Galey, sans-serif' }}>
              ＋ Nouveau RDV
            </button>
          </div>

          {/* Stats rapides */}
          <div className="grid grid-cols-3 gap-2 mb-4">
            <div className="bg-white/10 rounded-xl p-2.5 text-center">
              <p className="text-xl font-bold">{demandes.length}</p>
              <p className="text-[10px] text-white/70">En attente</p>
            </div>
            <div className="bg-white/10 rounded-xl p-2.5 text-center">
              <p className="text-xl font-bold">{aVenir.length}</p>
              <p className="text-[10px] text-white/70">À venir</p>
            </div>
            <div className="bg-white/10 rounded-xl p-2.5 text-center">
              <p className="text-xl font-bold">{historique.length}</p>
              <p className="text-[10px] text-white/70">Historique</p>
            </div>
          </div>

          {/* Tabs */}
          <div className="flex gap-1 bg-white/10 rounded-xl p-1">
            {TABS.map(t => (
              <button key={t.key} onClick={() => setActiveTab(t.key)}
                className="flex-1 py-2 px-1 text-xs font-semibold rounded-lg transition-all flex items-center justify-center gap-1"
                style={{ background: activeTab === t.key ? 'white' : 'transparent', color: activeTab === t.key ? TEAL : 'rgba(255,255,255,0.75)', fontFamily: 'Galey, sans-serif' }}>
                {t.label}
                {t.badge > 0 && (
                  <span className="text-[9px] font-bold px-1.5 py-0.5 rounded-full"
                    style={{ background: activeTab === t.key ? TEAL : 'rgba(255,255,255,0.2)', color: 'white' }}>
                    {t.badge}
                  </span>
                )}
              </button>
            ))}
          </div>
        </div>
      </div>

      <div className="max-w-3xl mx-auto px-4 py-6">
        {/* Séances du jour (RDV + cours collectifs confondus) */}
        {/* Vétérinaire : la journée est déjà dans « À venir ». */}
        {aujourdhui.length > 0 && catPro !== 'veterinaire' && (
          <div className="bg-white rounded-2xl border p-4 mb-4" style={{ borderColor: `${TEAL}33` }}>
            <p className="text-xs font-bold uppercase tracking-wide mb-2.5" style={{ fontFamily: 'Galey, sans-serif', color: TEAL }}>
              📅 Aujourd&apos;hui ({aujourdhui.length})
            </p>
            <div className="space-y-1.5">
              {aujourdhui.map(e => {
                const dh = new Date(e.date_debut);
                const heure = `${String(dh.getHours()).padStart(2, '0')}h${String(dh.getMinutes()).padStart(2, '0')}`;
                const estCollectif = e.type === 'cours_collectif';
                return (
                  <div key={e.id} className="flex items-center gap-2 text-sm">
                    <span className="w-1.5 h-1.5 rounded-full flex-shrink-0" style={{ background: estCollectif ? '#7B5EA7' : TEAL }} />
                    <span className="font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>{heure}</span>
                    <span className="text-gray-600 truncate" style={{ fontFamily: 'Galey, sans-serif' }}>{e.titre}</span>
                  </div>
                );
              })}
            </div>
          </div>
        )}

        {/* Onglet créneaux */}
        {activeTab === 'creneaux' && user && (
          <CreneauxTab uid={user.uid} profileId={activeProfileId ?? ''} />
        )}

        {/* Planning de la clinique */}
        {activeTab === 'planning' && activeProfileId && (
          <PlanningClinique profileId={activeProfileId} version={rdvs} uid={user?.uid}
            onCreer={(date, praticien, salle) => setModalNouveau({ date, praticien, salle })}
            onOuvrirRdv={id => {
              const r = rdvs.find(x => x.id === id);
              if (!r) return;
              if (r.statut === 'demande') setModalAccepter(r);
              else if (r.statut === 'confirme') setModalModifier(r);
            }} />
        )}

        {/* Onglets RDV */}
        {activeTab !== 'creneaux' && activeTab !== 'planning' && (
          fetching ? (
            <div className="flex justify-center py-16">
              <div className="w-7 h-7 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" />
            </div>
          ) : currentList.length === 0 ? (
            <div className="text-center py-20 text-gray-400">
              <div className="text-5xl mb-4">📅</div>
              <p className="font-semibold" style={{ fontFamily: 'Galey, sans-serif' }}>
                {activeTab === 'demandes' ? 'Aucune demande en attente' : activeTab === 'a_venir' ? 'Aucun RDV à venir' : 'Aucun historique'}
              </p>
              {activeTab === 'demandes' && (
                <p className="text-xs mt-2 text-gray-400">Les clients vous enverront des demandes via votre profil</p>
              )}
            </div>
          ) : (
            <div className="space-y-3">
              {currentList.map(rdv => (
                <div key={rdv.id} id={`rdv-${rdv.id}`}
                  className={rdvFocus === rdv.id ? 'rounded-2xl ring-2 ring-[#0C5C6C] ring-offset-2' : undefined}>
                <RdvCard rdv={rdv} tab={activeTab as 'demandes' | 'a_venir' | 'historique'}
                  myUid={user?.uid ?? ''} myProfileId={activeProfileId || null}
                  onAccepter={() => setModalAccepter(rdv)}
                  onRefuser={() => setModalRefuser(rdv)}
                  onAnnuler={() => setModalAnnuler(rdv)}
                  onTerminer={() => marquerTermine(rdv)}
                  onDelete={() => deleteRdv(rdv.id)}
                  onOpenAnimal={openAnimalFiche}
                  onModifier={() => setModalModifier(rdv)}
                  onHistorique={catPro === 'veterinaire' && rdv.animal_id ? () => setHistoriqueRdv(rdv) : undefined}
                />
                </div>
              ))}
            </div>
          )
        )}
      </div>

      {historiqueRdv?.animal_id && activeProfileId && (
        <HistoriquePatient animalId={String(historiqueRdv.animal_id)} animalNom={historiqueRdv.animalNom ?? 'Patient'}
          profileId={activeProfileId} onClose={() => setHistoriqueRdv(null)} />
      )}
      {modalNouveau && user && activeProfileId && (
        <NouveauRdvModal proUid={user.uid} profileId={activeProfileId} proName={proName} catPro={catPro}
          initial={modalNouveau} onClose={() => setModalNouveau(null)}
          onDone={() => { setModalNouveau(null); fetchRdvs(); }} />
      )}
      {modalAccepter && (
        <AccepterModal rdv={modalAccepter} proName={proName}
          onClose={() => setModalAccepter(null)}
          onDone={() => { setModalAccepter(null); fetchRdvs(); }} />
      )}
      {modalModifier && (
        <ModifierModal rdv={modalModifier} proName={proName} activeProfileId={activeProfileId ?? ''}
          onClose={() => setModalModifier(null)}
          onDone={() => { setModalModifier(null); fetchRdvs(); }} />
      )}
      {modalRefuser && (
        <RefuserModal rdv={modalRefuser} label="Refuser" type="refuse"
          onClose={() => setModalRefuser(null)}
          onDone={() => { setModalRefuser(null); fetchRdvs(); }} />
      )}
      {modalAnnuler && (
        <RefuserModal rdv={modalAnnuler} label="Annuler" type="annule"
          onClose={() => setModalAnnuler(null)}
          onDone={() => { setModalAnnuler(null); fetchRdvs(); }} />
      )}
    </div>
  );
}
