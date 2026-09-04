'use client';

import { useEffect, useState, useCallback, useRef } from 'react';
import { useParams, useRouter, useSearchParams } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { RichText } from '@/lib/rich-text';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { loadBreeds } from '@/lib/breeds';
import HealthSection from '@/components/animaux/HealthSection';
import CessionModal, { type Reservation } from '@/components/animaux/CessionModal';
import ReservationModal from '@/components/animaux/ReservationModal';
import { uploadBlob, uploadDocument as uploadDocToStorage } from '@/lib/upload-media';
import { resolveAcquereurProfileId } from '@/lib/acquereur-profile';
import ImageCropModal from '@/components/ImageCropModal';
import AlimentationTab from './AlimentationTab';
import { AnatomieOwnerSection } from '@/components/AnatomiePoints';
import { triggerAutoProtocoles } from '@/lib/planning-service';
import { PensionJournal } from '@/components/PensionJournal';
import { typesVaccinPour, categorieOptions, suggestFromCategorie } from '@/lib/vaccinTypes';

// ─── Types ───────────────────────────────────────────────────────────────────

interface Animal {
  id: string; nom?: string; nom_pedigree?: string; espece?: string; espece_autre?: string; race?: string; sexe?: string;
  date_naissance?: string; couleur?: string; identification?: string;
  sterilise?: boolean; description?: string; notes?: string; photo_url?: string;
  statut?: string; passeport_europeen?: string; type_poil?: string; taille?: string; poids?: string;
  pedigree?: boolean; pedigree_lof?: string; pedigree_numero?: string; club_registre?: string; pedigree_url?: string;
  nom_pere?: string; puce_pere?: string; race_pere?: string;
  nom_mere?: string; puce_mere?: string; race_mere?: string; date_naissance_mere?: string;
  importation_ref?: string;
  contacts_urgence?: { nom: string; tel: string }[];
  documents?: { nom: string; url: string; type: string; categorie?: string }[];
  date_entree?: string; provenance_qualite?: string; provenance_nom?: string;
  provenance_adresse?: string; date_sortie?: string; destinataire_qualite?: string;
  destinataire_nom?: string; destinataire_adresse?: string; cause_mort?: string;
  uid_eleveur?: string | null; uid_proprietaire?: string | null; uid_acquereur?: string | null;
  cession_contrat_url?: string | null; cession_certificat_url?: string | null;
  cession_prix?: number | null; cession_notes?: string | null;
  intervalle_chaleurs_jours?: number | null;
  chaleurs_responsable_uid?: string | null;
  chaleurs_responsable_profile_id?: string | null;
  sterilisation_requise?: boolean | null;
  sterilisation_echeance?: string | null;
  sterilisation_validee?: boolean | null;
  sterilisation_eleveur_uid?: string | null;
  sterilisation_eleveur_profile_id?: string | null;
}

interface HealthRecord { id: string; [key: string]: unknown; }

// ─── Constantes ──────────────────────────────────────────────────────────────

const ESPECES = ['chien','chat','lapin','oiseau','nac','cheval','ovin','caprin','porcin','autre'];
const ESPECE_EMOJI: Record<string,string> = { chien:'🐕', chat:'🐈', cheval:'🐴', lapin:'🐰', oiseau:'🦜', nac:'🦎', ovin:'🐑', caprin:'🐐', porcin:'🐷', autre:'🐾' };
const TYPES_POIL = ['Court','Mi-long','Long','Frisé','Fil de soie','Ras'];
const PROV_QUALITES = ['naissance','eleveur','particulier','refuge','importation','autre'];
const DEST_QUALITES = ['eleveur','particulier','refuge','autre'];
const CAUSES_MORT = ['maladie','accident','naturelle','inconnue'];
const PROV_FR: Record<string,string> = { naissance:"Naissance dans l'élevage", eleveur:'Éleveur', particulier:'Particulier', refuge:'Refuge / Association', importation:'Importation', autre:'Autre' };
const DEST_FR: Record<string,string> = { eleveur:'Éleveur', particulier:'Particulier', refuge:'Refuge', autre:'Autre' };
const MORT_FR: Record<string,string> = { maladie:'Maladie', accident:'Accident', naturelle:'Mort naturelle', inconnue:'Inconnue' };
const STATUT_FR: Record<string,{label:string;color:string}> = { present:{label:'Présent',color:'text-green-700 bg-green-100'}, reserve:{label:'Réservé',color:'text-amber-700 bg-amber-100'}, sorti:{label:'Sorti',color:'text-blue-700 bg-blue-100'}, decede:{label:'Décédé',color:'text-red-600 bg-red-100'} };

const PEDIGREE_CONFIG: Record<string, { label: string; types: string[] }> = {
  chien:  { label: 'LOF (Livre des Origines Français)', types: ['LOF', 'Non-LOF'] },
  chat:   { label: 'LOOF (Livre Officiel des Origines Félines)', types: ['LOOF', 'Non-LOOF'] },
  cheval: { label: 'Registre', types: ["Stud-book", "Registre d'élevage", 'Non-inscrit'] },
  lapin:  { label: 'Livre de race', types: ['Livre de race', 'Non-inscrit'] },
  oiseau: { label: 'Baguage', types: ['Bagué fermé', 'Bagué ouvert', 'Non-bagué'] },
  ovin:   { label: 'Livre généalogique', types: ['Livre généalogique', 'Non-inscrit'] },
  caprin: { label: 'Livre généalogique', types: ['Livre généalogique', 'Non-inscrit'] },
  porcin: { label: 'Livre généalogique LG', types: ['Livre généalogique LG', 'Non-inscrit'] },
  nac:    { label: "Registre d'élevage", types: ["Registre d'élevage", 'Non-inscrit'] },
};

const DOC_TYPES: { value: string; label: string; icon: string }[] = [
  { value: 'adn',         label: 'Test ADN',             icon: '🧬' },
  { value: 'sante_repro', label: 'Santé reproducteur',   icon: '🏥' },
  { value: 'filiation',   label: 'Filiation',            icon: '🔗' },
  { value: 'hanches',     label: 'Test hanches',         icon: '🦴' },
  { value: 'autre',       label: 'Autre',                icon: '📁' },
];

const GESTATION_DUREE: Record<string,number> = { chien:63, chat:65, cheval:340, ovin:150, caprin:150, porcin:114, lapin:31 };
const CONFIRMATION_INFO: Record<string,string> = {
  chien:  'Confirmation recommandée par écho vers J+21 à J+28',
  chat:   'Confirmation recommandée par écho vers J+21 à J+28',
  cheval: 'Premier contrôle écho vers J+14-16, puis confirmation vers J+42',
  lapin:  'Confirmation par palpation possible vers J+10-14',
  ovin:   'Confirmation par écho ou palpation vers J+40-70',
  caprin: 'Confirmation par écho ou palpation vers J+40-70',
  porcin: 'Retour en chaleur vers J+21 si gestation non confirmée',
};

const CHALEURS_INTERVAL: Record<string, number> = {
  chien: 182, chat: 21, lapin: 14, ovin: 17, caprin: 21, porcin: 21, cheval: 21,
};
const CHALEURS_INFO: Record<string, string> = {
  chien:  'Intervalle moyen : 6 mois',
  chat:   'Intervalle moyen : 21 jours (si non stérilisée)',
  cheval: 'Saisonnière printemps-été · cycle ~21j',
  ovin:   'Saisonnière automne-hiver · cycle ~17j',
  caprin: 'Saisonnière automne-hiver · cycle ~21j',
  porcin: 'Intervalle moyen : 21 jours',
  lapin:  'Réceptive quasi-permanente',
};

function nextHeatDate(chaleurs: HealthRecord[], espece: string, customInterval?: number | null): Date | null {
  const interval = customInterval ?? CHALEURS_INTERVAL[espece];
  if (!interval || chaleurs.length === 0) return null;
  const sorted = [...chaleurs].sort((a, b) =>
    new Date(String(b.date ?? 0)).getTime() - new Date(String(a.date ?? 0)).getTime()
  );
  const lastDate = new Date(String(sorted[0].date ?? ''));
  if (isNaN(lastDate.getTime())) return null;
  return new Date(lastDate.getTime() + interval * 86400000);
}

function NextHeatBanner({ nextHeat, espece }: { nextHeat: Date; espece: string }) {
  const now = new Date();
  const diff = Math.round((nextHeat.getTime() - now.getTime()) / 86400000);
  const info = CHALEURS_INFO[espece] ?? '';

  let bg: string, text: string, border: string, icon: string, label: string;
  if (diff < 0) {
    bg = 'bg-red-50'; text = 'text-red-700'; border = 'border-red-300'; icon = '⚠️';
    label = `Chaleurs probables (${-diff}j de retard)`;
  } else if (diff === 0) {
    bg = 'bg-red-50'; text = 'text-red-700'; border = 'border-red-300'; icon = '🔴';
    label = "Chaleurs attendues aujourd'hui !";
  } else if (diff === 1) {
    bg = 'bg-red-50'; text = 'text-red-700'; border = 'border-red-300'; icon = '🔴';
    label = 'Chaleurs attendues demain !';
  } else if (diff <= 7) {
    bg = 'bg-amber-50'; text = 'text-amber-700'; border = 'border-amber-300'; icon = '🟠';
    label = `Chaleurs prochaines dans ${diff} jours`;
  } else {
    bg = 'bg-green-50'; text = 'text-green-700'; border = 'border-green-300'; icon = '🌸';
    label = `Prochaines chaleurs : ${nextHeat.toLocaleDateString('fr-FR')}`;
  }

  return (
    <div className={`${bg} border ${border} rounded-xl p-3 flex items-start gap-2 mb-3`}>
      <span className="text-lg">{icon}</span>
      <div>
        <p className={`text-sm font-bold ${text}`} style={{ fontFamily: 'Galey,sans-serif' }}>{label}</p>
        {info && <p className={`text-xs ${text} opacity-80`}>{info}</p>}
      </div>
    </div>
  );
}

// Axe de graphe : compact, g sous 1 kg.
function fmtPoids(v: number): string {
  if (v < 1) return `${Math.round(v * 1000)}g`;
  if (v < 10) return v.toFixed(1);
  return v.toFixed(0);
}
// Libellé complet : grammes sous 1 kg (bébés de petites espèces), kg au-delà.
// Le stockage reste toujours en kg.
function poidsLabel(kg: number): string {
  if (kg < 1) return `${Math.round(kg * 1000)} g`;
  if (kg < 10) return `${kg.toFixed(2).replace(/0+$/, '').replace(/\.$/, '').replace('.', ',')} kg`;
  return `${kg.toFixed(1).replace('.', ',')} kg`;
}
function fmtDate(d?: string | null) {
  if (!d) return '';
  try { return new Date(d).toLocaleDateString('fr-FR', { day:'2-digit', month:'2-digit', year:'2-digit' }); } catch { return d; }
}
function age(dob?: string | null) {
  if (!dob) return '';
  const diff = Date.now() - new Date(dob).getTime();
  const days = Math.floor(diff / 86400000);
  if (days < 30) return `${days} j`;
  if (days < 365) return `${Math.floor(days/30)} mois`;
  const y = Math.floor(days/365); const m = Math.floor((days % 365)/30);
  return m > 0 ? `${y} an${y>1?'s':''} ${m} mois` : `${y} an${y>1?'s':''}`;
}

// ─── Champ texte générique ────────────────────────────────────────────────────

function Field({ label, value, onChange, type='text', rows, required }:
  { label:string; value:string; onChange:(v:string)=>void; type?:string; rows?:number; required?:boolean }) {
  const cls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30';
  if (type === 'checkbox') {
    return (
      <label className="flex items-center gap-2 text-sm text-gray-700 cursor-pointer select-none">
        <input type="checkbox" checked={value === 'true'}
          onChange={e => onChange(e.target.checked ? 'true' : 'false')}
          className="w-4 h-4 rounded border-gray-300 text-[#0C5C6C] focus:ring-[#0C5C6C]/30" />
        {label}
      </label>
    );
  }
  return (
    <div>
      <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">
        {label}{required && <span className="text-red-400 ml-0.5">*</span>}
      </label>
      {rows ? (
        <textarea value={value} onChange={e=>onChange(e.target.value)} rows={rows} className={cls} />
      ) : (
        <input type={type} value={value} onChange={e=>onChange(e.target.value)} className={cls} />
      )}
    </div>
  );
}

function SelectField({ label, value, onChange, options }:
  { label:string; value:string; onChange:(v:string)=>void; options:{value:string;label:string}[] }) {
  return (
    <div>
      <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">{label}</label>
      <select value={value} onChange={e=>onChange(e.target.value)}
        className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30 bg-white">
        {options.map(o => <option key={o.value} value={o.value}>{o.label}</option>)}
      </select>
    </div>
  );
}

// ─── Section santé générique ──────────────────────────────────────────────────
// Types de vaccins par espèce : voir @/lib/vaccinTypes (partagé avec
// association/animaux/[id]/page.tsx pour ne jamais diverger entre profils).

function AddHealthForm({ fields, onSave, onCancel, saving, initial, espece, existingCategories }:
  { fields: { key:string; label:string; type?:string; required?:boolean; options?:{value:string;label:string}[] }[];
    onSave:(data:Record<string,string>)=>Promise<void>;
    onCancel:()=>void; saving:boolean; initial?: Record<string,string>; espece?: string; existingCategories?: string[] }) {
  const [form, setForm] = useState<Record<string,string>>(initial ?? {});
  const hasRappelField = fields.some(f => f.key === 'date_rappel');
  const hasValiditeField = fields.some(f => f.key === 'date_validite_debut');
  // Fréquence (ex: antiparasitaires) : valeur + unité au lieu d'un texte
  // libre, pour calculer automatiquement la date de rappel. Best-effort pour
  // relire une fréquence texte existante en édition (ex: "1 mois").
  const parsedFreq = /^(\d+)\s*(jour|semaine|mois)/i.exec(initial?.frequence ?? '');
  const [freqValeur, setFreqValeur] = useState(parsedFreq?.[1] ?? '1');
  const [freqUnite, setFreqUnite] = useState<'jour'|'semaine'|'mois'>(
    (parsedFreq?.[2]?.toLowerCase() as 'jour'|'semaine'|'mois') ?? 'mois');
  function applyFrequence(valeur: string, unite: 'jour'|'semaine'|'mois', dateStr?: string) {
    const n = parseInt(valeur, 10);
    setForm(p => {
      if (!(n > 0)) return p;
      const next = {...p};
      const uniteLabel = unite === 'jour' ? `jour${n>1?'s':''}` : unite === 'semaine' ? `semaine${n>1?'s':''}` : 'mois';
      next.frequence = `${n} ${uniteLabel}`;
      const d0 = dateStr ?? p.date;
      if (d0) {
        const days = unite === 'jour' ? n : unite === 'semaine' ? n*7 : n*30;
        const d = new Date(d0); d.setDate(d.getDate() + days);
        next.date_rappel = d.toISOString().slice(0,10);
      }
      return next;
    });
  }
  return (
    <div className="space-y-3">
      {fields.map(f => f.type === 'frequence' ? (
        <div key={f.key}>
          <label className="block text-xs font-semibold text-gray-500 mb-1">{f.label}</label>
          <div className="flex gap-2">
            <input type="number" min={1} value={freqValeur}
              onChange={e => { setFreqValeur(e.target.value); applyFrequence(e.target.value, freqUnite); }}
              className="w-20 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30" />
            <select value={freqUnite}
              onChange={e => { const u = e.target.value as 'jour'|'semaine'|'mois'; setFreqUnite(u); applyFrequence(freqValeur, u); }}
              className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30">
              <option value="jour">Jour(s)</option>
              <option value="semaine">Semaine(s)</option>
              <option value="mois">Mois</option>
            </select>
          </div>
        </div>
      ) : f.type === 'select' ? (
        <SelectField key={f.key} label={f.label} value={form[f.key]??''} options={f.options ?? []}
          onChange={v => setForm(p=>{
            const next = {...p,[f.key]:v};
            // Sélectionner un type pré-remplit le nom du vaccin s'il est
            // encore vide, et déclenche la suggestion des dates.
            if (f.key === 'categorie') {
              if (!next.vaccin) next.vaccin = v;
              if ((hasRappelField || hasValiditeField) && next.date) {
                const dejaVaccine = (existingCategories ?? []).includes(v);
                const sug = suggestFromCategorie(espece, v, next.date, dejaVaccine);
                if (sug) { next.date_rappel = sug.rappel; next.date_validite_debut = sug.validite; }
              }
            }
            return next;
          })} />
      ) : (
        <Field key={f.key} label={f.label} value={form[f.key]??''} required={f.required}
          type={f.type??'text'} onChange={v => setForm(p=>{
            const next = {...p,[f.key]:v};
            // Date d'injection changée (y compris une correction après un
            // premier choix) : on recalcule toujours les deux dates tant
            // qu'un type est sélectionné, pour éviter qu'une suggestion
            // figée sur une date precedente ne reste affichee par erreur.
            if (f.key === 'date' && p.categorie && (hasRappelField || hasValiditeField)) {
              const dejaVaccine = (existingCategories ?? []).includes(p.categorie);
              const sug = suggestFromCategorie(espece, p.categorie, v, dejaVaccine);
              if (sug) { next.date_rappel = sug.rappel; next.date_validite_debut = sug.validite; }
            }
            // Date changée alors qu'une fréquence est déjà saisie (ex:
            // antiparasitaires) : recalcule le rappel sur la nouvelle date.
            if (f.key === 'date' && fields.some(ff => ff.type === 'frequence')) {
              const n = parseInt(freqValeur, 10);
              if (n > 0) {
                const days = freqUnite === 'jour' ? n : freqUnite === 'semaine' ? n*7 : n*30;
                const d = new Date(v); d.setDate(d.getDate() + days);
                next.date_rappel = d.toISOString().slice(0,10);
              }
            }
            return next;
          })} />
      ))}
      <div className="flex gap-2 pt-1">
        <button onClick={onCancel} className="flex-1 py-2 rounded-xl border border-gray-200 text-sm text-gray-600 hover:bg-gray-50">Annuler</button>
        <button onClick={() => onSave(form)} disabled={saving}
          className="flex-1 py-2 rounded-xl bg-[#0C5C6C] text-white text-sm font-semibold hover:bg-[#094F5D] disabled:opacity-50">
          {saving ? '…' : 'Enregistrer'}
        </button>
      </div>
    </div>
  );
}

function HealthRecord({ fields, record, onDelete, onSave, saving, canWrite, espece, existingCategories, onRappel }:
  { fields:{key:string;label:string;type?:string;required?:boolean;options?:{value:string;label:string}[]}[]; record:HealthRecord; onDelete:()=>void;
    onSave?:(data:Record<string,string>)=>Promise<void>; saving?:boolean; canWrite?:boolean; espece?: string; existingCategories?: string[];
    onRappel?:()=>void }) {
  const [open, setOpen] = useState(false);
  const [editing, setEditing] = useState(false);
  const mainField = fields[0];
  // Un acte saisi par un vétérinaire est certifié : le propriétaire ne peut
  // pas le supprimer ni le modifier, seul le vétérinaire qui l'a rédigé le
  // peut (depuis son propre espace pro).
  const isVetEntry = record.source === 'veterinaire';

  if (editing && onSave) {
    const initial: Record<string,string> = {};
    fields.forEach(f => { initial[f.key] = String(record[f.key] ?? ''); });
    return (
      <div className="px-4 py-3">
        <AddHealthForm saving={!!saving} onCancel={()=>setEditing(false)}
          onSave={async d => { await onSave(d); setEditing(false); }}
          initial={initial} fields={fields} espece={espece} existingCategories={existingCategories} />
      </div>
    );
  }

  return (
    <div className="px-4 py-3">
      <div className="flex items-center gap-2 cursor-pointer" onClick={() => setOpen(!open)}>
        <div className="flex-1">
          <p className="text-sm font-medium text-[#1F2A2E] flex items-center gap-1.5">
            {String(record[mainField.key] ?? '—')}
            {isVetEntry && <span title="Certifié par un vétérinaire" className="text-xs">🔒</span>}
          </p>
          {(() => {
            const dateField = fields.find(f => f.type === 'date');
            return dateField && record[dateField.key]
              ? <p className="text-xs text-gray-400">{fmtDate(record[dateField.key] as string)}</p>
              : null;
          })()}
        </div>
        <svg className={`w-4 h-4 text-gray-400 transition-transform ${open?'rotate-180':''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7"/>
        </svg>
      </div>
      {open && (
        <div className="mt-2 space-y-1">
          {fields.map(f => record[f.key] ? (
            <div key={f.key} className="flex gap-2 text-xs">
              <span className="text-gray-400 w-24 flex-shrink-0">{f.label}</span>
              <span className="text-gray-700">{f.type === 'date' ? fmtDate(record[f.key] as string) : String(record[f.key])}</span>
            </div>
          ) : null)}
          {isVetEntry && (
            <p className="mt-2 text-xs text-gray-400">
              🔒 Certifié{record.veterinaire ? ` par ${String(record.veterinaire)}` : ' par un vétérinaire'} — non modifiable
            </p>
          )}
          <div className="flex gap-3 mt-2">
            {canWrite && onRappel && (
              <button onClick={onRappel} className="text-xs text-[#0C5C6C] hover:text-[#094F5D] font-medium">+ Rappel</button>
            )}
            {!isVetEntry && canWrite && onSave && (
              <button onClick={()=>setEditing(true)} className="text-xs text-[#0C5C6C] hover:text-[#094F5D] font-medium">Modifier</button>
            )}
            {!isVetEntry && (
              <button onClick={onDelete} className="text-xs text-red-400 hover:text-red-600 font-medium">Supprimer</button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Onglet Consultations vétérinaires (lecture seule) ───────────────────────

function ConsultationsVetTab({ crs, ordonnances, vetNames }:
  { crs: HealthRecord[]; ordonnances: HealthRecord[]; vetNames: Record<string,string> }) {

  const isEmpty = crs.length === 0 && ordonnances.length === 0;

  if (isEmpty) return (
    <div className="flex flex-col items-center justify-center py-20 px-8 text-center">
      <span className="text-6xl mb-4 opacity-20">🩺</span>
      <p className="font-semibold text-[#1F2A2E] text-base mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
        Aucune consultation enregistrée
      </p>
      <p className="text-sm text-gray-400" style={{ fontFamily: 'Galey, sans-serif' }}>
        Les comptes rendus et ordonnances rédigés par votre vétérinaire apparaîtront ici.
      </p>
    </div>
  );

  return (
    <div className="space-y-3">
      {crs.length > 0 && (
        <HealthSection title="Comptes rendus" icon="📋" color="#0C5C6C" count={crs.length}>
          {crs.map(cr => <VetDocCard key={cr.id as string} record={cr} vetNames={vetNames} />)}
        </HealthSection>
      )}
      {ordonnances.length > 0 && (
        <HealthSection title="Ordonnances" icon="💊" color="#0C5C6C" count={ordonnances.length}>
          {ordonnances.map(o => <VetDocCard key={o.id as string} record={o} vetNames={vetNames} />)}
        </HealthSection>
      )}
    </div>
  );
}

function VetDocCard({ record, vetNames }:
  { record: HealthRecord; vetNames: Record<string,string> }) {
  const [open, setOpen] = useState(false);
  const docUrl  = record.doc_url  as string | undefined;
  const date    = record.date     as string | undefined;
  const notes   = record.notes    as string | undefined;
  const contenu = record.contenu  as string | undefined;
  const proUid  = record.pro_uid  as string | undefined;
  const vetName = proUid ? (vetNames[proUid] ?? 'Vétérinaire') : 'Vétérinaire';

  return (
    <div className="px-4 py-3">
      <div className="flex items-center gap-2 cursor-pointer" onClick={() => setOpen(!open)}>
        <div className="flex-1">
          <div className="flex items-center gap-2 flex-wrap">
            {date && <span className="text-sm font-medium text-[#1F2A2E]">{fmtDate(date)}</span>}
            <span className="text-xs px-2 py-0.5 rounded-full font-semibold"
              style={{ backgroundColor: '#0C5C6C20', color: '#0C5C6C' }}>
              🩺 {vetName}
            </span>
          </div>
          {(notes || contenu) && (
            <p className="text-xs text-gray-400 truncate mt-0.5">{notes ?? contenu}</p>
          )}
        </div>
        <svg className={`w-4 h-4 text-gray-400 transition-transform ${open ? 'rotate-180' : ''}`}
          fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
        </svg>
      </div>
      {open && (
        <div className="mt-2 space-y-1.5">
          {(contenu || notes) && (
            <p className="text-sm text-gray-600 leading-relaxed">{contenu ?? notes}</p>
          )}
          {docUrl && (
            <a href={docUrl} target="_blank" rel="noopener noreferrer"
              className="inline-flex items-center gap-1 text-xs text-[#0C5C6C] font-semibold hover:underline">
              <span>📎</span> Voir le document
            </a>
          )}
        </div>
      )}
    </div>
  );
}

// ─── Upload + affichage documents vétérinaires ──────────────────────────────

function DocUploadForm({ onSave, onCancel, saving }:
  { onSave:(file:File,notes:string,date:string)=>void; onCancel:()=>void; saving:boolean }) {
  const [file, setFile] = useState<File|null>(null);
  const [notes, setNotes] = useState('');
  const [date, setDate] = useState('');
  const cls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30';
  return (
    <div className="space-y-3">
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Date</label>
        <input type="date" value={date} onChange={e=>setDate(e.target.value)} className={cls}/>
      </div>
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Fichier (PDF / image) <span className="text-red-400">*</span></label>
        <label className="flex items-center gap-2 px-3 py-2 border border-gray-200 rounded-xl cursor-pointer hover:bg-gray-50 text-sm">
          <span className="text-lg">📎</span>
          <span className="flex-1 text-gray-600 truncate">{file ? file.name : 'Sélectionner un fichier…'}</span>
          <input type="file" accept=".pdf,image/*" className="hidden" onChange={e=>setFile(e.target.files?.[0]??null)}/>
        </label>
      </div>
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Notes (optionnel)</label>
        <textarea value={notes} onChange={e=>setNotes(e.target.value)} rows={2} className={cls} placeholder="Observations…"/>
      </div>
      <div className="flex gap-2 pt-1">
        <button onClick={onCancel} className="flex-1 py-2 rounded-xl border border-gray-200 text-sm text-gray-600 hover:bg-gray-50">Annuler</button>
        <button onClick={()=>{ if(file) onSave(file,notes,date); }} disabled={saving||!file}
          className="flex-1 py-2 rounded-xl bg-[#0C5C6C] text-white text-sm font-semibold hover:bg-[#094F5D] disabled:opacity-50">
          {saving ? '…' : 'Enregistrer'}
        </button>
      </div>
    </div>
  );
}

function DocCard({ record, onDelete }:
  { record:HealthRecord; onDelete:()=>void }) {
  const [open, setOpen] = useState(false);
  const docUrl = record.doc_url as string | undefined;
  const date = record.date as string | undefined;
  const notes = record.notes as string | undefined;
  return (
    <div className="px-4 py-3">
      <div className="flex items-center gap-2 cursor-pointer" onClick={()=>setOpen(!open)}>
        <div className="flex-1">
          <p className="text-sm font-medium text-[#1F2A2E]">{date ? fmtDate(date) : 'Document'}</p>
          {notes && <p className="text-xs text-gray-400 truncate">{notes}</p>}
        </div>
        <svg className={`w-4 h-4 text-gray-400 transition-transform ${open?'rotate-180':''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7"/>
        </svg>
      </div>
      {open && (
        <div className="mt-2 space-y-2">
          {docUrl && (
            <a href={docUrl} target="_blank" rel="noopener noreferrer"
              className="inline-flex items-center gap-1 text-xs text-[#0C5C6C] font-semibold hover:underline">
              <span>📎</span> Voir le document
            </a>
          )}
          {notes && <p className="text-xs text-gray-500">{notes}</p>}
          <button onClick={onDelete} className="block text-xs text-red-400 hover:text-red-600 font-medium">Supprimer</button>
        </div>
      )}
    </div>
  );
}

// ─── Formulaire saillie (avec sélecteur de partenaire) ───────────────────────

// Parse une valeur `dates` (jsonb array, ou chaîne "d1,d2", ou date simple)
// en liste de dates ISO (yyyy-mm-dd) triée.
function parseSaillieDates(raw?: string, fallback?: string): string[] {
  const out: string[] = [];
  if (raw) {
    let arr: unknown = raw;
    try { arr = JSON.parse(raw); } catch { arr = raw.split(','); }
    if (Array.isArray(arr)) {
      for (const v of arr) {
        const s = String(v).trim().substring(0, 10);
        if (/^\d{4}-\d{2}-\d{2}$/.test(s)) out.push(s);
      }
    }
  }
  if (out.length === 0 && fallback) {
    const s = fallback.substring(0, 10);
    if (/^\d{4}-\d{2}-\d{2}$/.test(s)) out.push(s);
  }
  return [...new Set(out)].sort();
}

// Fenêtre de mise-bas : [1re saillie + N, dernière saillie + N] + date probable (milieu).
function fenetreMiseBas(dates: string[], espece: string): { debut: string; fin: string; probable: string } | null {
  const n = GESTATION_DUREE[espece] ?? 0;
  if (n <= 0 || dates.length === 0) return null;
  const sorted = [...dates].sort();
  const add = (d: string) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
  const debut = add(sorted[0]);
  const fin = add(sorted[sorted.length - 1]);
  const probable = new Date((debut.getTime() + fin.getTime()) / 2);
  const iso = (x: Date) => x.toISOString().substring(0, 10);
  return { debut: iso(debut), fin: iso(fin), probable: iso(probable) };
}

function SaillieForm({ partners, isMale, initial, saving, espece, onSave, onCancel }: {
  partners: { id: string; nom: string; identification: string }[];
  isMale: boolean;
  initial?: Record<string, string>;
  saving: boolean;
  espece?: string;
  onSave: (data: Record<string, string>) => Promise<void>;
  onCancel: () => void;
}) {
  const [form, setForm] = useState<Record<string, string>>(initial ?? {});
  const [dates, setDates] = useState<string[]>(
    parseSaillieDates(initial?.dates, initial?.date));
  const cls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30';
  const setF = (k: string, v: string) => setForm(p => ({ ...p, [k]: v }));
  const setDateAt = (i: number, v: string) => setDates(p => { const c = [...p]; c[i] = v; return c.filter(Boolean).sort(); });
  const fen = !isMale && espece ? fenetreMiseBas(dates.filter(Boolean), espece) : null;
  return (
    <div className="space-y-3">
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Dates de saillie <span className="text-red-400 ml-0.5">*</span></label>
        <div className="space-y-2">
          {(dates.length ? dates : ['']).map((d, i) => (
            <div key={i} className="flex items-center gap-2">
              <input type="date" value={d ?? ''} onChange={e => setDateAt(i, e.target.value)} className={cls} />
              <span className="text-xs text-gray-400 whitespace-nowrap">Saillie {i + 1}</span>
              {dates.length > 1 && (
                <button type="button" onClick={() => setDates(p => p.filter((_, j) => j !== i))}
                  className="text-red-300 hover:text-red-500 text-lg leading-none">×</button>
              )}
            </div>
          ))}
        </div>
        <button type="button" onClick={() => setDates(p => [...p, ''])}
          className="mt-1.5 text-xs font-semibold text-[#6E9E57] hover:underline">+ Ajouter une date de saillie</button>
        {fen && (
          <div className="mt-2 bg-green-50 border border-green-200 rounded-xl p-2.5 text-xs text-green-800 leading-relaxed">
            {fen.debut === fen.fin
              ? <>Mise-bas estimée : <b>{fmtDate(fen.probable)}</b></>
              : <>Fenêtre mise-bas : <b>{fmtDate(fen.debut)} → {fmtDate(fen.fin)}</b><br />Date la plus probable : <b>{fmtDate(fen.probable)}</b></>}
          </div>
        )}
      </div>
      {partners.length > 0 && (
        <div>
          <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2 block">
            {isMale ? 'Femelles de votre élevage' : 'Mâles de votre élevage'}
          </label>
          <div className="flex flex-wrap gap-2">
            {partners.map(p => (
              <button key={p.id} type="button"
                onClick={() => setForm(prev => ({ ...prev, nom_partenaire: p.nom, ident_partenaire: p.identification ?? '', partenaire_animal_id: p.id }))}
                className={`px-3 py-1 rounded-full text-xs font-medium border transition-colors ${form.partenaire_animal_id === p.id ? 'bg-[#6E9E57] text-white border-[#6E9E57]' : 'border-gray-200 text-gray-600 hover:border-[#6E9E57]'}`}>
                {p.nom}
              </button>
            ))}
          </div>
        </div>
      )}
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Nom du partenaire <span className="text-red-400 ml-0.5">*</span></label>
        <input type="text" value={form.nom_partenaire ?? ''} onChange={e => setF('nom_partenaire', e.target.value)} className={cls} />
      </div>
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Identification partenaire</label>
        <input type="text" value={form.ident_partenaire ?? ''} onChange={e => setF('ident_partenaire', e.target.value)} className={cls} />
      </div>
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Méthode</label>
        <select value={form.methode ?? 'naturelle'} onChange={e => setF('methode', e.target.value)}
          className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30 bg-white">
          <option value="naturelle">Naturelle</option>
          <option value="ia">IA (insémination artificielle)</option>
          <option value="iaf">IAF (semence fraîche)</option>
        </select>
      </div>
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Notes</label>
        <textarea value={form.notes ?? ''} onChange={e => setF('notes', e.target.value)} rows={2} className={cls} />
      </div>
      <div className="flex gap-2 pt-1">
        <button type="button" onClick={onCancel}
          className="flex-1 py-2 rounded-xl border border-gray-200 text-sm text-gray-600 hover:bg-gray-50">Annuler</button>
        <button type="button"
          onClick={() => {
            const clean = [...new Set(dates.filter(Boolean))].sort();
            onSave({ ...form, date: clean[0], dates: JSON.stringify(clean) });
          }}
          disabled={saving || dates.filter(Boolean).length === 0 || !form.nom_partenaire}
          className="flex-1 py-2 rounded-xl bg-[#0C5C6C] text-white text-sm font-semibold hover:bg-[#094F5D] disabled:opacity-50">
          {saving ? '…' : 'Enregistrer'}
        </button>
      </div>
    </div>
  );
}

// ─── Formulaire Gestation ─────────────────────────────────────────────────────

function GestationForm({ espece, initial, saving, onSave, onCancel }: {
  espece: string;
  initial?: Record<string, string>;
  saving: boolean;
  onSave: (data: Record<string, string>) => Promise<void>;
  onCancel: () => void;
}) {
  const [date, setDate] = useState(initial?.date ?? '');
  const [datePrevue, setDatePrevue] = useState(initial?.date_prevue?.substring(0, 10) ?? '');
  const [datePrevueFin, setDatePrevueFin] = useState(initial?.date_prevue_fin?.substring(0, 10) ?? '');
  const [dateOverride, setDateOverride] = useState(!!initial?.date_prevue);
  const [dateNaissance, setDateNaissance] = useState(initial?.date_naissance ?? '');
  const [nbAttendu, setNbAttendu] = useState(initial?.nb_attendu ?? '');
  const [nbNes, setNbNes] = useState(initial?.nb_nes ?? '');
  const [notes, setNotes] = useState(initial?.notes ?? '');
  const [confirmed, setConfirmed] = useState(initial?.gestation_confirmee === 'true');
  const cls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30';
  const jours = GESTATION_DUREE[espece] ?? 0;

  function handleDateChange(d: string) {
    setDate(d);
    if (d && jours > 0 && !dateOverride) {
      const prevue = new Date(d);
      prevue.setDate(prevue.getDate() + jours);
      setDatePrevue(prevue.toISOString().substring(0, 10));
      setDatePrevueFin('');
    }
  }

  const probable = datePrevue && datePrevueFin
    ? new Date((new Date(datePrevue).getTime() + new Date(datePrevueFin).getTime()) / 2).toISOString().substring(0, 10)
    : datePrevue;

  return (
    <div className="space-y-3">
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Date de conception <span className="text-red-400">*</span></label>
        <input type="date" value={date} onChange={e => handleDateChange(e.target.value)} className={cls} />
      </div>
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">
          {datePrevueFin ? 'Mise-bas — début de fenêtre' : 'Mise-bas estimée'}{jours > 0 ? ` (auto: ${jours} j)` : ''}
        </label>
        <input type="date" value={datePrevue}
          onChange={e => { setDatePrevue(e.target.value); setDateOverride(true); }}
          className={`${cls} ${!dateOverride && datePrevue ? 'bg-green-50 border-green-200' : ''}`} />
      </div>
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">
          Mise-bas — fin de fenêtre <span className="text-gray-300 normal-case">(si plusieurs saillies)</span>
        </label>
        <input type="date" value={datePrevueFin}
          onChange={e => setDatePrevueFin(e.target.value)} className={cls} />
      </div>
      {datePrevue && datePrevueFin && (
        <div className="bg-green-50 border border-green-200 rounded-xl p-2.5 text-xs text-green-800 leading-relaxed">
          Fenêtre : <b>{fmtDate(datePrevue)} → {fmtDate(datePrevueFin)}</b><br />
          Date la plus probable : <b>{fmtDate(probable)}</b>
        </div>
      )}
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Nb attendus</label>
        <input type="number" value={nbAttendu} onChange={e => setNbAttendu(e.target.value)} className={cls} />
      </div>
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Date de mise-bas réelle</label>
        <input type="date" value={dateNaissance} onChange={e => setDateNaissance(e.target.value)} className={cls} />
      </div>
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Nb nés</label>
        <input type="number" value={nbNes} onChange={e => setNbNes(e.target.value)} className={cls} />
      </div>
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Notes</label>
        <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} className={cls} />
      </div>
      <div className="flex items-center gap-3 py-1">
        <button type="button" onClick={() => setConfirmed(!confirmed)}
          className={`w-10 h-6 rounded-full transition-colors flex items-center ${confirmed ? 'bg-[#6E9E57] justify-end' : 'bg-gray-200 justify-start'}`}>
          <span className="w-5 h-5 bg-white rounded-full shadow mx-0.5 block" />
        </button>
        <span className="text-sm font-medium text-[#1F2A2E]" style={{ fontFamily: 'Galey,sans-serif' }}>
          {confirmed ? '✓ Gestation confirmée' : 'Gestation confirmée ?'}
        </span>
      </div>
      {!confirmed && CONFIRMATION_INFO[espece] && (
        <div className="bg-amber-50 border border-amber-200 rounded-xl p-3 flex gap-2">
          <span className="text-amber-500 text-sm">ℹ</span>
          <p className="text-xs text-amber-700">{CONFIRMATION_INFO[espece]}</p>
        </div>
      )}
      <div className="flex gap-2 pt-1">
        <button type="button" onClick={onCancel}
          className="flex-1 py-2 rounded-xl border border-gray-200 text-sm text-gray-600 hover:bg-gray-50">Annuler</button>
        <button type="button" disabled={saving || !date}
          onClick={() => onSave({ date, date_prevue: datePrevue, date_prevue_fin: datePrevueFin, date_naissance: dateNaissance, nb_attendu: nbAttendu, nb_nes: nbNes, notes, gestation_confirmee: confirmed ? 'true' : 'false' })}
          className="flex-1 py-2 rounded-xl bg-[#0C5C6C] text-white text-sm font-semibold hover:bg-[#094F5D] disabled:opacity-50">
          {saving ? '…' : 'Enregistrer'}
        </button>
      </div>
    </div>
  );
}

// ─── Formulaire Pesée (choix g / kg) ─────────────────────────────────────────

function fmtWeightInput(v: number): string {
  if (Number.isInteger(v)) return String(v);
  return v.toFixed(2).replace(/0+$/, '').replace(/\.$/, '');
}

function WeightForm({ initial, lastKg, saving, onSave, onCancel }: {
  initial?: { valeur?: string; date?: string; notes?: string };
  lastKg?: number | null;
  saving: boolean;
  onSave: (data: Record<string, string>) => void | Promise<void>;
  onCancel: () => void;
}) {
  const initKg = initial?.valeur ? parseFloat(String(initial.valeur).replace(',', '.')) : NaN;
  const initUnite: 'g' | 'kg' = Number.isFinite(initKg)
    ? (initKg < 1 ? 'g' : 'kg')
    : (lastKg != null && lastKg < 1 ? 'g' : 'kg');
  const [unite, setUnite] = useState<'g' | 'kg'>(initUnite);
  const [value, setValue] = useState(
    Number.isFinite(initKg) ? fmtWeightInput(initUnite === 'g' ? initKg * 1000 : initKg) : '');
  const [date, setDate] = useState(initial?.date?.slice(0, 10) ?? new Date().toISOString().slice(0, 10));
  const [notes, setNotes] = useState(initial?.notes ?? '');
  const cls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30';

  function switchUnite(u: 'g' | 'kg') {
    if (u === unite) return;
    const v = parseFloat(value.replace(',', '.'));
    setUnite(u);
    if (Number.isFinite(v)) setValue(fmtWeightInput(u === 'g' ? v * 1000 : v / 1000));
  }

  function submit() {
    const v = parseFloat(value.replace(',', '.'));
    if (!Number.isFinite(v) || !date) return;
    const kg = unite === 'g' ? v / 1000 : v;
    onSave({ valeur: String(kg), date, notes: notes.trim() });
  }

  return (
    <div className="space-y-3">
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Poids <span className="text-red-400 ml-0.5">*</span></label>
        <div className="flex gap-2">
          <input type="number" step="any" inputMode="decimal" value={value}
            onChange={e => setValue(e.target.value)} className={cls} />
          <div className="flex rounded-xl border border-gray-200 overflow-hidden shrink-0">
            {(['g', 'kg'] as const).map(u => (
              <button key={u} type="button" onClick={() => switchUnite(u)}
                className={`px-3.5 text-sm font-bold ${unite === u ? 'bg-[#6E9E57] text-white' : 'bg-white text-gray-500'}`}>
                {u}
              </button>
            ))}
          </div>
        </div>
      </div>
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Date</label>
        <input type="date" value={date} onChange={e => setDate(e.target.value)} className={cls} />
      </div>
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Notes</label>
        <textarea value={notes} onChange={e => setNotes(e.target.value)} rows={2} className={cls} />
      </div>
      <div className="flex gap-2 pt-1">
        <button type="button" onClick={onCancel}
          className="flex-1 py-2 rounded-xl border border-gray-200 text-sm text-gray-600 hover:bg-gray-50">Annuler</button>
        <button type="button" onClick={submit} disabled={saving || !value || !date}
          className="flex-1 py-2 rounded-xl bg-[#0C5C6C] text-white text-sm font-semibold hover:bg-[#094F5D] disabled:opacity-50">
          {saving ? '…' : 'Enregistrer'}
        </button>
      </div>
    </div>
  );
}

// ─── Documents Animal Tab ─────────────────────────────────────────────────────

const DOC_LIBRE_CATS: { value: string; label: string; icon: string }[] = [
  { value: 'contrat',        label: 'Contrat d\'achat / adoption',  icon: '📄' },
  { value: 'pedigree',       label: 'Pédigrée numérique',           icon: '🏅' },
  { value: 'identification', label: 'Carte d\'identification (I-CAD)', icon: '🪪' },
  { value: 'passeport',      label: 'Passeport européen',           icon: '📘' },
  { value: 'assurance',      label: 'Attestation d\'assurance',     icon: '🛡️' },
  { value: 'vaccination',    label: 'Carnet de vaccination',        icon: '💉' },
  { value: 'facture',        label: 'Facture vétérinaire',          icon: '🧾' },
  { value: 'autre',          label: 'Autre document administratif', icon: '📎' },
];

interface DocLibre { nom: string; url: string; categorie?: string; type?: string; ajoute_le?: string; date_expiration?: string }

function DocumentsAnimalTab({ animalId }: { animalId: string }) {
  const { user } = useAuth();
  const activeProfileId = useActiveProfile();
  const [docs, setDocs] = useState<Record<string,unknown>[]>([]);
  const [certs, setCerts] = useState<Record<string,unknown>[]>([]);
  const [libres, setLibres] = useState<DocLibre[]>([]);
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const [cat, setCat] = useState('contrat');
  const [expiration, setExpiration] = useState('');

  useEffect(() => {
    async function load() {
      const [docsRes, certsRes, animRes] = await Promise.all([
        supabase.from('documents_animaux').select('*').eq('animal_id', animalId).order('created_at', { ascending: false }),
        supabase.from('certificats_engagement').select('id, nom_animal, acquereur_prenom, acquereur_nom, statut, date_remise, date_signature_acquereur, token_signature').eq('animal_id', animalId).order('date_remise', { ascending: false }),
        supabase.from('animaux').select('documents').eq('id', animalId).maybeSingle(),
      ]);
      setDocs(docsRes.data ?? []);
      setCerts(certsRes.data ?? []);
      setLibres(((animRes.data?.documents as DocLibre[]) ?? []));
      setLoading(false);
    }
    load();
    // Recharge quand l'onglet reprend le focus (ex. retour de la page de signature)
    const onFocus = () => load();
    window.addEventListener('focus', onFocus);
    return () => window.removeEventListener('focus', onFocus);
  }, [animalId]);

  async function saveLibres(next: DocLibre[]) {
    setLibres(next);
    await supabase.from('animaux').update({ documents: next }).eq('id', animalId);
  }

  async function handleUpload(file: File) {
    if (!user) return;
    setUploading(true);
    try {
      const path = `documents/${user.uid}/${animalId}/${Date.now()}_${file.name.replace(/\s/g, '_')}`;
      const { error } = await supabase.storage.from('media').upload(path, file);
      if (error) throw error;
      const { data: { publicUrl } } = supabase.storage.from('media').getPublicUrl(path);
      const entry: DocLibre = {
        nom: file.name, url: publicUrl, categorie: cat, type: file.type,
        ajoute_le: new Date().toISOString().slice(0, 10),
        ...(expiration ? { date_expiration: expiration } : {}),
      };
      await saveLibres([...libres, entry]);
      if (expiration) {
        const exp = new Date(expiration);
        let rappel = new Date(exp); rappel.setDate(rappel.getDate() - 30);
        if (rappel < new Date()) rappel = exp;
        rappel.setHours(8, 0, 0, 0);
        await supabase.from('agenda_events').insert({
          uid: user.uid,
          titre: `Document à renouveler : ${DOC_LIBRE_CATS.find(c => c.value === cat)?.label ?? file.name}`,
          type: 'autre',
          date_debut: rappel.toISOString(),
          animal_id: Number.isFinite(Number(animalId)) ? Number(animalId) : null,
          ...(activeProfileId ? { profile_id: activeProfileId, pro_profile_id: activeProfileId } : {}),
        });
      }
      setExpiration('');
    } catch { /* ignore */ }
    finally { setUploading(false); }
  }

  const typeLabel: Record<string,string> = {
    contrat_vente: 'Contrat de vente',
    contrat_reservation: 'Contrat de réservation',
    contrat_saillie: 'Contrat de saillie',
    contrat_adoption: 'Contrat d\'adoption',
    certificat_cession: 'Certificat de cession',
    devis: 'Devis (éducateur)',
  };
  const typeIcon: Record<string,string> = {
    contrat_vente: '🤝',
    contrat_reservation: '🔖',
    contrat_saillie: '💞',
    contrat_adoption: '🏡',
    certificat_cession: '📋',
    devis: '🧾',
  };
  const statutBadge = (statut: string) => {
    const cfg: Record<string,[string,string]> = {
      signe: ['bg-green-100 text-green-800', 'Signé'],
      archive: ['bg-gray-100 text-gray-600', 'Archivé'],
      en_attente: ['bg-blue-100 text-blue-700', 'En attente de réponse'],
      refuse: ['bg-red-100 text-red-600', 'Refusé'],
    };
    const [cls, label] = cfg[statut] ?? ['bg-yellow-100 text-yellow-800', 'Brouillon'];
    return <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${cls}`}>{label}</span>;
  };

  if (loading) return <div className="flex justify-center py-12"><div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;

  const uploadCard = (
    <div className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
      <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-2">Mes documents</p>
      <div className="flex flex-wrap items-center gap-2">
        <select value={cat} onChange={e => setCat(e.target.value)}
          className="text-xs border border-gray-200 rounded-lg px-2 py-1.5 bg-white focus:outline-none focus:border-[#0C5C6C]">
          {DOC_LIBRE_CATS.map(c => <option key={c.value} value={c.value}>{c.icon} {c.label}</option>)}
        </select>
        <label className="text-xs text-gray-500 flex items-center gap-1">
          Expire le
          <input type="date" value={expiration} onChange={e => setExpiration(e.target.value)}
            className="border border-gray-200 rounded-lg px-2 py-1 focus:outline-none focus:border-[#0C5C6C]" />
        </label>
        <label className={`text-xs font-semibold px-3 py-1.5 rounded-full cursor-pointer transition-colors ${uploading ? 'bg-gray-200 text-gray-400' : 'bg-[#0C5C6C] text-white hover:bg-[#094F5D]'}`}>
          {uploading ? 'Envoi…' : '+ Ajouter'}
          <input type="file" className="hidden" disabled={uploading}
            accept=".pdf,.doc,.docx,.jpg,.jpeg,.png,.webp"
            onChange={e => { const f = e.target.files?.[0]; if (f) handleUpload(f); e.target.value = ''; }} />
        </label>
      </div>
      {expiration && <p className="text-[11px] text-gray-400 mt-1.5">Un rappel sera ajouté à votre agenda 30 jours avant l&apos;expiration.</p>}
      <div className="mt-3 divide-y divide-gray-50">
        {libres.length === 0 && <p className="text-sm text-gray-400 py-2">Aucun document ajouté.</p>}
        {libres.map((d, i) => {
          const exp = d.date_expiration ? new Date(d.date_expiration) : null;
          const expired = exp && exp < new Date();
          const soon = exp && !expired && (exp.getTime() - Date.now()) / 86400000 <= 30;
          return (
            <div key={i} className="flex items-center gap-3 py-2.5">
              <span className="text-xl">{DOC_LIBRE_CATS.find(c => c.value === d.categorie)?.icon ?? '📎'}</span>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-gray-800 truncate">{d.nom}</p>
                <p className="text-xs text-gray-400">
                  {DOC_LIBRE_CATS.find(c => c.value === d.categorie)?.label ?? 'Document'}
                  {exp && (
                    <span className={`ml-2 font-semibold ${expired ? 'text-red-600' : soon ? 'text-orange-600' : 'text-gray-400'}`}>
                      {expired ? 'Expiré' : 'Expire'} le {exp.toLocaleDateString('fr-FR')}
                    </span>
                  )}
                </p>
              </div>
              <a href={d.url} target="_blank" rel="noreferrer" className="text-xs text-[#0C5C6C] hover:underline">Voir</a>
              <button onClick={() => saveLibres(libres.filter((_, j) => j !== i))}
                className="text-red-300 hover:text-red-500 text-lg leading-none">×</button>
            </div>
          );
        })}
      </div>
    </div>
  );

  const empty = docs.length === 0 && certs.length === 0 && libres.length === 0;
  if (empty) return (
    <div className="space-y-3 mt-4">
      {uploadCard}
      <div className="flex flex-col items-center py-10 text-gray-400 gap-2">
        <span className="text-5xl">📂</span>
        <p className="font-semibold">Aucun contrat officiel pour l&apos;instant</p>
        <p className="text-sm">Les contrats signés avec un éleveur / éducateur apparaîtront ici.</p>
      </div>
    </div>
  );

  return (
    <div className="space-y-3 mt-4">
      {uploadCard}
      {docs.length > 0 && (
        <>
          <h3 className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide">Contrats &amp; Documents</h3>
          {docs.map((doc) => {
            const meta = (doc.metadata as Record<string,string>) ?? {};
            const acq = [meta.acquereur_prenom, meta.acquereur_nom].filter(Boolean).join(' ');
            const date = doc.created_at ? new Date(doc.created_at as string).toLocaleDateString('fr-FR') : '';
            const type = doc.type as string ?? '';
            return (
              <div key={doc.id as string} className="flex items-center gap-3 bg-gray-50 rounded-xl px-4 py-3 border border-gray-100">
                <span className="text-2xl">{typeIcon[type] ?? '📄'}</span>
                <div className="flex-1 min-w-0">
                  <div className="font-semibold text-sm text-gray-800">{typeLabel[type] ?? 'Document'}</div>
                  {acq && <div className="text-xs text-gray-500">{acq}</div>}
                  <div className="flex items-center gap-2 mt-0.5">
                    <span className="text-xs text-gray-400">{date}</span>
                    {statutBadge(doc.statut as string)}
                  </div>
                </div>
                {(!!doc.url || !!doc.token) && (
                  <a href={doc.pdf_signe_url ? String(doc.pdf_signe_url) : doc.url ? String(doc.url) : `/signer-contrat/${doc.token}`}
                    target="_blank" rel="noreferrer"
                    className="text-[#0C5C6C] hover:text-[#0a4a58] flex-shrink-0"
                    title={!doc.url ? 'Ouvrir / Signer' : 'Ouvrir le document'}>
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" /></svg>
                  </a>
                )}
              </div>
            );
          })}
        </>
      )}

      {certs.length > 0 && (
        <>
          <h3 className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mt-4">Certificats d&apos;engagement</h3>
          {certs.map((cert) => {
            const acq = [cert.acquereur_prenom, cert.acquereur_nom].filter(Boolean).join(' ');
            const date = cert.date_remise ? new Date(cert.date_remise as string).toLocaleDateString('fr-FR') : '';
            const statut = cert.statut as string;
            const token = cert.token_signature as string | null;
            const sigLink = token ? `/certificat/${token}` : null;
            const dateSig = cert.date_signature_acquereur
              ? new Date(cert.date_signature_acquereur as string).toLocaleDateString('fr-FR') : null;
            return (
              <div key={cert.id as string} className="flex items-center gap-3 bg-gray-50 rounded-xl px-4 py-3 border border-gray-100">
                <span className="text-2xl">✅</span>
                <div className="flex-1 min-w-0">
                  <div className="font-semibold text-sm text-gray-800">Certificat d&apos;engagement</div>
                  {acq && <div className="text-xs text-gray-500">{acq}</div>}
                  <div className="flex items-center gap-2 mt-0.5">
                    <span className="text-xs text-gray-400">{date}</span>
                    {statut === 'signe'
                      ? <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-green-100 text-green-800">Signé{dateSig ? ` ${dateSig}` : ''}</span>
                      : <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-yellow-100 text-yellow-800">En attente</span>}
                  </div>
                </div>
                {sigLink && statut !== 'signe' && (
                  <button onClick={() => { navigator.clipboard.writeText(window.location.origin + sigLink); }}
                    title="Copier le lien de signature"
                    className="text-[#0C5C6C] hover:text-[#0a4a58] flex-shrink-0">
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1" /></svg>
                  </button>
                )}
              </div>
            );
          })}
        </>
      )}
    </div>
  );
}

// ─── Onglet Éducation (comptes rendus + exercices cochables) ─────────────────

interface RapportEdu {
  id: string;
  date_seance: string | null;
  contenu: string | null;
  exercices_conseilles: string | null;
  exercices_coches: boolean[] | null;
  type?: string;
  bilan_motif?: string | null;
  bilan_recommandation?: string | null;
  bilan_nb_seances_estime?: number | null;
}

const EDU_CATEGORIES: Record<string, string> = {
  rappel: 'Rappel', laisse: 'Marche en laisse', proprete: 'Propreté', aboiements: 'Aboiements',
  destruction: 'Destruction', socialisation_chien: 'Socialisation chiens', socialisation_humain: 'Socialisation humains',
  manipulation: 'Manipulation / soins', solitude: 'Solitude', agressivite: 'Agressivité', peurs: 'Peurs', autre: 'Autre',
};
const EDU_STATUT_LABEL: Record<string, string> = { a_travailler: 'À travailler', en_cours: 'En cours', acquis: 'Acquis' };
const eduStatutColor = (s: string) => s === 'acquis' ? '#6E9E57' : s === 'en_cours' ? '#EFA100' : '#D5573B';
interface EduObjectif { id: string; libelle: string; categorie: string | null; statut: string; note: string | null; acquis_le?: string | null; }
interface EduExercice {
  id: string; titre_snapshot: string; description_snapshot: string | null;
  media_snapshot: { type: string; url: string }[] | null;
  cadence: string | null; echeance: string | null; statut: string;
  rappels_actifs?: boolean; rappels_mutes?: boolean;
}
interface EduRetour {
  id: string; attribution_id: string; note: string | null;
  media: { type: string; url: string }[] | null; ressenti: string | null; from_pro: boolean;
}
const RESSENTI: Record<string, string> = { facile: '😊 Facile', moyen: '😐 Moyen', difficile: '😓 Difficile', bloque: '🚫 Bloqué' };

interface EduForfait { id: string; nom_snapshot: string; nb_seances_total: number; nb_seances_utilisees: number; statut: string; }
interface EduAttestation { id: string; pdf_url: string; emise_le: string; }

function EducationRapportsTab({ animalId }: { animalId: string }) {
  const { user } = useAuth();
  const [rapports, setRapports] = useState<RapportEdu[]>([]);
  const [objectifs, setObjectifs] = useState<EduObjectif[]>([]);
  const [exercices, setExercices] = useState<EduExercice[]>([]);
  const [forfaits, setForfaits] = useState<EduForfait[]>([]);
  const [attestations, setAttestations] = useState<EduAttestation[]>([]);
  const [retours, setRetours] = useState<Record<string, EduRetour[]>>({});
  const [loading, setLoading] = useState(true);
  const [retourFor, setRetourFor] = useState<EduExercice | null>(null);
  const [retourNote, setRetourNote] = useState('');
  const [retourRessenti, setRetourRessenti] = useState('');
  const [retourImgs, setRetourImgs] = useState<string[]>([]);
  const [sendingRetour, setSendingRetour] = useState(false);

  const reload = useCallback(() => {
    Promise.all([
      supabase.from('education_progression')
        .select('id, date_seance, contenu, exercices_conseilles, exercices_coches, type, bilan_motif, bilan_recommandation, bilan_nb_seances_estime')
        .eq('animal_id', animalId).order('date_seance', { ascending: false }),
      supabase.from('education_objectifs')
        .select('id, libelle, categorie, statut, note, acquis_le')
        .eq('animal_id', animalId).order('ordre').order('created_at'),
      supabase.from('exercices_attribues')
        .select('id, pro_uid, pro_profile_id, titre_snapshot, description_snapshot, media_snapshot, cadence, echeance, statut, rappels_actifs, rappels_mutes')
        .eq('animal_id', animalId).order('assigned_at', { ascending: false }),
      supabase.from('forfaits_souscrits')
        .select('id, nom_snapshot, nb_seances_total, nb_seances_utilisees, statut')
        .eq('animal_id', animalId).order('souscrit_le', { ascending: false }),
      supabase.from('education_attestations')
        .select('id, pdf_url, emise_le').eq('animal_id', animalId).order('emise_le', { ascending: false }),
    ]).then(async ([r, o, e, fo, at]) => {
      setForfaits(((fo.data ?? []) as EduForfait[]).filter(f => f.statut !== 'annule'));
      setAttestations((at.data ?? []) as EduAttestation[]);
      const exos = (e.data ?? []) as (EduExercice & { pro_uid?: string; pro_profile_id?: string })[];
      setRapports((r.data ?? []) as RapportEdu[]);
      setObjectifs((o.data ?? []) as EduObjectif[]);
      setExercices(exos);
      const ids = exos.map(x => x.id);
      if (ids.length) {
        const { data: rt } = await supabase.from('exercices_retours')
          .select('id, attribution_id, note, media, ressenti, from_pro')
          .in('attribution_id', ids).order('created_at');
        const grouped: Record<string, EduRetour[]> = {};
        for (const row of (rt ?? []) as EduRetour[]) (grouped[row.attribution_id] ??= []).push(row);
        setRetours(grouped);
      }
      setLoading(false);
    });
  }, [animalId]);

  useEffect(() => { reload(); }, [reload]);

  async function toggleExerciceFait(ex: EduExercice) {
    const next = ex.statut === 'fait' ? 'a_faire' : 'fait';
    setExercices(prev => prev.map(x => x.id === ex.id ? { ...x, statut: next } : x));
    await supabase.from('exercices_attribues')
      .update({ statut: next, updated_at: new Date().toISOString() }).eq('id', ex.id);
  }

  async function uploadRetourImg(file: File) {
    const ext = file.name.split('.').pop() ?? 'jpg';
    const path = `exercices_retours/${user?.uid ?? 'x'}/${Date.now()}.${ext}`;
    const { error } = await supabase.storage.from('petsmatch').upload(path, file, { upsert: true });
    if (!error) {
      const { data: pub } = supabase.storage.from('petsmatch').getPublicUrl(path);
      setRetourImgs(prev => [...prev, pub.publicUrl]);
    }
  }

  async function sendRetour() {
    if (!retourFor || (!retourNote.trim() && !retourRessenti && retourImgs.length === 0)) return;
    setSendingRetour(true);
    try {
      const ex = retourFor as EduExercice & { pro_uid?: string; pro_profile_id?: string };
      await supabase.from('exercices_retours').insert({
        attribution_id: ex.id, author_uid: user?.uid,
        note: retourNote.trim() || null,
        media: retourImgs.map(u => ({ type: 'image', url: u })),
        ressenti: retourRessenti || null, from_pro: false,
      });
      if (ex.pro_uid) {
        await supabase.from('notifications').insert({
          uid: ex.pro_uid, type: 'education_retour_exercice',
          title: 'Retour famille', body: `La famille a répondu sur « ${ex.titre_snapshot} ».`,
          ...(ex.pro_profile_id ? { profile_id: ex.pro_profile_id } : {}),
          data: { animalId, url: `/mes-patients/${animalId}` },
        });
      }
      setRetourFor(null); setRetourNote(''); setRetourRessenti(''); setRetourImgs([]);
      reload();
    } finally {
      setSendingRetour(false);
    }
  }

  const lignes = (raw: string | null) => (raw ?? '')
    .split(/[\n;]/).map(s => s.trim()).filter(Boolean);

  async function toggle(rapport: RapportEdu, index: number, total: number) {
    const cur = [...(rapport.exercices_coches ?? [])];
    while (cur.length < total) cur.push(false);
    cur[index] = !cur[index];
    setRapports(rs => rs.map(r => r.id === rapport.id ? { ...r, exercices_coches: cur } : r));
    await supabase.from('education_progression').update({ exercices_coches: cur }).eq('id', rapport.id);
  }

  if (loading) return <div className="flex justify-center py-12"><div className="w-6 h-6 border-2 border-[#7B5EA7] border-t-transparent rounded-full animate-spin" /></div>;
  if (rapports.length === 0 && objectifs.length === 0 && exercices.length === 0 && forfaits.length === 0 && attestations.length === 0) return (
    <div className="flex flex-col items-center py-16 text-gray-400 gap-2">
      <span className="text-5xl">🎓</span>
      <p className="font-semibold">Aucun suivi éducatif pour l&apos;instant</p>
      <p className="text-sm">Le plan de travail et les comptes rendus de votre éducateur apparaîtront ici.</p>
    </div>
  );

  return (
    <div className="space-y-3 mt-4">
      {attestations.map(a => (
        <a key={a.id} href={a.pdf_url} target="_blank" rel="noopener noreferrer"
          className="flex items-center justify-between rounded-2xl border border-[#6E9E57]/30 bg-[#EEF5EA] p-3">
          <div>
            <p className="text-sm font-bold text-gray-800">🎓 Attestation de fin de programme</p>
            <p className="text-xs text-gray-500">Émise le {new Date(a.emise_le).toLocaleDateString('fr-FR')}</p>
          </div>
          <span className="text-xs font-semibold text-[#4A7A32]">Ouvrir →</span>
        </a>
      ))}
      {forfaits.map(f => {
        const actif = f.statut === 'actif';
        const pct = f.nb_seances_total === 0 ? 0 : Math.min(100, (f.nb_seances_utilisees / f.nb_seances_total) * 100);
        return (
          <div key={f.id} className="rounded-2xl border border-[#EF6C00]/30 bg-[#FFF3E9] p-3">
            <div className="flex items-center justify-between">
              <p className="text-sm font-bold text-gray-800">🎫 {f.nom_snapshot}</p>
              <p className="text-xs font-bold text-[#EF6C00]">{actif ? `${f.nb_seances_utilisees} / ${f.nb_seances_total} séances` : 'Terminé'}</p>
            </div>
            <div className="mt-1.5 h-1.5 rounded-full bg-[#EF6C00]/15 overflow-hidden">
              <div className="h-full bg-[#EF6C00]" style={{ width: `${pct}%` }} />
            </div>
          </div>
        );
      })}
      {(objectifs.length > 0 || rapports.length > 0) && (() => {
        type Ev = { date: string; label: string; emoji: string };
        const events: Ev[] = [];
        for (const r of rapports) {
          if (!r.date_seance) continue;
          events.push({ date: r.date_seance, label: r.type === 'bilan' ? 'Bilan comportemental' : 'Séance', emoji: r.type === 'bilan' ? '📋' : '🎓' });
        }
        for (const o of objectifs) {
          if (o.statut === 'acquis' && o.acquis_le) events.push({ date: o.acquis_le, label: `Objectif atteint : ${o.libelle}`, emoji: '✅' });
        }
        events.sort((a, b) => b.date.localeCompare(a.date));
        return (
          <div className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
            <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-2">Progression</p>
            {objectifs.length > 0 && (
              <div className="flex flex-wrap gap-1.5 mb-3">
                {objectifs.map(o => (
                  <span key={o.id} className="text-[11px] px-2 py-0.5 rounded-full" style={{ background: `${eduStatutColor(o.statut)}18`, color: eduStatutColor(o.statut) }}>
                    {o.statut === 'acquis' ? '✅' : o.statut === 'en_cours' ? '🟡' : '🔴'} {o.libelle}
                  </span>
                ))}
              </div>
            )}
            {events.length > 0 && (
              <div className="space-y-2">
                {events.map((e, i) => (
                  <div key={i} className="flex items-center gap-2 text-xs">
                    <span>{e.emoji}</span>
                    <span className="font-medium text-gray-800">{e.label}</span>
                    <span className="text-gray-400">· {new Date(e.date).toLocaleDateString('fr-FR')}</span>
                  </div>
                ))}
              </div>
            )}
          </div>
        );
      })()}
      {objectifs.length > 0 && (
        <div className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
          <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-2">Plan de travail</p>
          <div className="space-y-2">
            {objectifs.map(o => (
              <div key={o.id} className="flex items-start gap-2">
                <span className="w-2.5 h-2.5 rounded-full mt-1 shrink-0" style={{ background: eduStatutColor(o.statut) }} />
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-semibold text-gray-800">{o.libelle}</p>
                  <p className="text-xs" style={{ color: eduStatutColor(o.statut) }}>
                    {EDU_STATUT_LABEL[o.statut] ?? o.statut}
                    {o.categorie && EDU_CATEGORIES[o.categorie] ? ` · ${EDU_CATEGORIES[o.categorie]}` : ''}
                  </p>
                  {o.note && <div className="text-xs text-gray-500 mt-0.5"><RichText value={o.note} /></div>}
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
      {exercices.length > 0 && (
        <div className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
          <p className="text-xs font-bold text-gray-400 uppercase tracking-wide mb-2">Exercices à faire</p>
          <div className="space-y-3">
            {exercices.map(ex => {
              const done = ex.statut === 'fait';
              const media = ex.media_snapshot ?? [];
              return (
                <div key={ex.id} className={`rounded-xl border p-3 ${done ? 'border-[#6E9E57]' : 'border-gray-100'}`}>
                  <div className="flex items-start justify-between gap-2">
                    <p className={`text-sm font-semibold ${done ? 'line-through text-gray-400' : 'text-gray-800'}`}>{ex.titre_snapshot}</p>
                    <div className="flex items-center gap-2 shrink-0">
                      {ex.rappels_actifs && (
                        <button title={ex.rappels_mutes ? 'Réactiver les rappels' : 'Mettre les rappels en pause'}
                          onClick={async () => {
                            const next = !ex.rappels_mutes;
                            setExercices(prev => prev.map(x => x.id === ex.id ? { ...x, rappels_mutes: next } : x));
                            await supabase.from('exercices_attribues').update({ rappels_mutes: next }).eq('id', ex.id);
                          }}
                          className="text-sm">{ex.rappels_mutes ? '🔕' : '🔔'}</button>
                      )}
                      <button onClick={() => toggleExerciceFait(ex)}
                        className={`text-xs font-semibold ${done ? 'text-[#6E9E57]' : 'text-[#7B5EA7]'}`}>
                        {done ? '✓ Fait' : 'Marquer fait'}
                      </button>
                    </div>
                  </div>
                  <div className="flex flex-wrap gap-1.5 mt-1">
                    {ex.cadence && <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-gray-100 text-gray-500">{ex.cadence}</span>}
                    {ex.echeance && <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-[#D5573B]/10 text-[#D5573B]">avant le {new Date(ex.echeance).toLocaleDateString('fr-FR')}</span>}
                  </div>
                  {ex.description_snapshot && <div className="text-xs text-gray-600 mt-1.5"><RichText value={ex.description_snapshot} /></div>}
                  {media.length > 0 && (
                    <div className="flex gap-2 mt-2 overflow-x-auto">
                      {media.map((m, i) => m.type === 'video' ? (
                        <a key={i} href={m.url} target="_blank" rel="noopener noreferrer"
                          className="w-16 h-16 shrink-0 rounded-lg bg-gray-100 flex items-center justify-center text-gray-400">▶</a>
                      ) : (
                        /* eslint-disable-next-line @next/next/no-img-element */
                        <a key={i} href={m.url} target="_blank" rel="noopener noreferrer" className="shrink-0">
                          <img src={m.url} alt="" className="w-16 h-16 rounded-lg object-cover" />
                        </a>
                      ))}
                    </div>
                  )}
                  {(retours[ex.id] ?? []).map(rt => (
                    <div key={rt.id} className={`mt-2 rounded-lg p-2 ${rt.from_pro ? 'bg-[#F3EEFA]' : 'bg-gray-100'}`}>
                      <p className="text-[10px] font-bold text-gray-500">
                        {rt.from_pro ? '🎓 Éducateur' : '👪 Famille'}
                        {rt.ressenti && RESSENTI[rt.ressenti] ? ` · ${RESSENTI[rt.ressenti]}` : ''}
                      </p>
                      {rt.note && <p className="text-xs text-gray-800 mt-0.5">{rt.note}</p>}
                      {(rt.media ?? []).length > 0 && (
                        <div className="flex gap-1.5 mt-1 overflow-x-auto">
                          {(rt.media ?? []).map((m, i) => (
                            /* eslint-disable-next-line @next/next/no-img-element */
                            <a key={i} href={m.url} target="_blank" rel="noopener noreferrer">
                              <img src={m.url} alt="" className="w-12 h-12 rounded object-cover" />
                            </a>
                          ))}
                        </div>
                      )}
                    </div>
                  ))}
                  <button onClick={() => { setRetourFor(ex); setRetourNote(''); setRetourRessenti(''); setRetourImgs([]); }}
                    className="text-xs text-[#7B5EA7] font-semibold mt-2">+ Donner un retour</button>
                </div>
              );
            })}
          </div>
        </div>
      )}
      {retourFor && (
        <div className="fixed inset-0 z-50 bg-black/40 flex items-end sm:items-center justify-center p-4" onClick={() => setRetourFor(null)}>
          <div className="bg-white rounded-2xl p-4 w-full max-w-md space-y-3" onClick={e => e.stopPropagation()}>
            <p className="font-bold text-[#1F2A2E]">Retour — {retourFor.titre_snapshot}</p>
            <div className="flex flex-wrap gap-1.5">
              {Object.entries(RESSENTI).map(([k, v]) => (
                <button key={k} onClick={() => setRetourRessenti(retourRessenti === k ? '' : k)}
                  className={`text-xs px-2.5 py-1 rounded-full border ${retourRessenti === k ? 'bg-[#7B5EA7]/15 border-[#7B5EA7] text-[#7B5EA7]' : 'border-gray-200 text-gray-500'}`}>{v}</button>
              ))}
            </div>
            <textarea value={retourNote} onChange={e => setRetourNote(e.target.value)} rows={3}
              placeholder="Comment ça s'est passé ? Ce qui bloque…"
              className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
            <div className="flex flex-wrap gap-2">
              {retourImgs.map((u, i) => (
                /* eslint-disable-next-line @next/next/no-img-element */
                <img key={i} src={u} alt="" className="w-14 h-14 rounded-lg object-cover" />
              ))}
              <label className="w-14 h-14 rounded-lg border-2 border-dashed border-gray-200 flex items-center justify-center text-gray-400 cursor-pointer text-xl">
                +
                <input type="file" accept="image/*" className="hidden"
                  onChange={e => { const f = e.target.files?.[0]; if (f) uploadRetourImg(f); e.target.value = ''; }} />
              </label>
            </div>
            <div className="flex gap-2">
              <button onClick={() => setRetourFor(null)} className="flex-1 border border-gray-200 rounded-xl py-2 text-sm text-gray-500">Annuler</button>
              <button onClick={sendRetour} disabled={sendingRetour}
                className="flex-1 bg-[#7B5EA7] text-white rounded-xl py-2 text-sm font-semibold disabled:opacity-50">Envoyer</button>
            </div>
          </div>
        </div>
      )}
      {rapports.map(r => {
        const exos = lignes(r.exercices_conseilles);
        const coches = r.exercices_coches ?? [];
        const isBilan = r.type === 'bilan';
        return (
          <div key={r.id} className={`rounded-2xl border bg-white p-4 shadow-sm ${isBilan ? 'border-[#EF6C00]' : 'border-gray-100'}`}>
            <p className="text-sm font-bold text-[#7B5EA7] flex items-center gap-2">
              {isBilan && <span className="text-[10px] bg-[#EF6C00] text-white px-1.5 py-0.5 rounded font-bold">BILAN</span>}
              {r.date_seance ? new Date(r.date_seance).toLocaleDateString('fr-FR') : ''}
            </p>
            {isBilan && r.bilan_motif && <p className="text-xs font-semibold text-gray-700 mt-1">Motif : {r.bilan_motif}</p>}
            {r.contenu && <div className="text-sm text-gray-800 mt-1"><RichText value={r.contenu} /></div>}
            {isBilan && r.bilan_recommandation && (
              <div className="mt-2 rounded-xl bg-[#FFF3E9] p-3">
                <p className="text-xs font-bold text-[#EF6C00]">📋 Recommandation</p>
                <div className="text-xs text-gray-800 mt-0.5"><RichText value={r.bilan_recommandation} /></div>
                {r.bilan_nb_seances_estime != null && <p className="text-[11px] text-gray-500 mt-0.5">Estimation : {r.bilan_nb_seances_estime} séances</p>}
              </div>
            )}
            {exos.length > 0 && (
              <div className="mt-3 rounded-xl bg-[#F3EEFA] p-3">
                <p className="text-xs font-bold text-[#7B5EA7]">🏋️ Exercices à faire à la maison</p>
                <div className="mt-1 space-y-1">
                  {exos.map((ex, i) => {
                    const done = !!coches[i];
                    return (
                      <button key={i} onClick={() => toggle(r, i, exos.length)}
                        className="flex items-start gap-2 text-left w-full">
                        <span className={`mt-0.5 text-base ${done ? 'text-[#6E9E57]' : 'text-gray-300'}`}>
                          {done ? '☑' : '☐'}
                        </span>
                        <span className={`text-[13px] ${done ? 'line-through text-gray-400' : 'text-gray-800'}`}>{ex}</span>
                      </button>
                    );
                  })}
                </div>
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

// ─── Onglet Pension & Garde (journal photos / vidéos / notes) ────────────────

interface PensionUpdate {
  id: string;
  created_at: string | null;
  photo_url: string | null;
  video_url: string | null;
  note: string | null;
}

function PensionJournalTab({ animalId, animalNom }: { animalId: string; animalNom: string }) {
  const [updates, setUpdates] = useState<PensionUpdate[]>([]);
  const [loading, setLoading] = useState(true);
  const [showFull, setShowFull] = useState(false);

  useEffect(() => {
    supabase.from('pension_updates')
      .select('id, created_at, photo_url, video_url, note')
      .eq('animal_id', animalId).order('created_at', { ascending: false })
      .then(({ data }) => { setUpdates((data ?? []) as PensionUpdate[]); setLoading(false); });
  }, [animalId]);

  if (loading) return <div className="flex justify-center py-12"><div className="w-6 h-6 border-2 border-[#6E9E57] border-t-transparent rounded-full animate-spin" /></div>;
  if (updates.length === 0) return (
    <div className="flex flex-col items-center py-16 text-gray-400 gap-2">
      <span className="text-5xl">📸</span>
      <p className="font-semibold">Aucune nouvelle pour l&apos;instant</p>
      <p className="text-sm">Les photos et messages de la pension ou du pet-sitter apparaîtront ici.</p>
    </div>
  );

  return (
    <div className="space-y-3 mt-4">
      <button onClick={() => setShowFull(true)}
        className="w-full text-sm font-semibold text-[#6E9E57] border border-[#6E9E57]/40 rounded-xl py-2 hover:bg-[#6E9E57]/5 transition-colors">
        Ouvrir le journal complet (réactions, commentaires…)
      </button>
      {updates.map(u => (
        <div key={u.id} className="rounded-2xl border border-gray-100 bg-white overflow-hidden shadow-sm">
          {u.photo_url
            ? <img src={u.photo_url} alt="" className="w-full max-h-72 object-cover" />
            : u.video_url
            ? <video src={u.video_url} controls className="w-full max-h-72 bg-black" />
            : null}
          <div className="p-3">
            {u.note && <p className="text-sm text-gray-800 whitespace-pre-line">{u.note}</p>}
            <p className="text-xs text-gray-400 mt-1">
              {u.created_at ? new Date(u.created_at).toLocaleString('fr-FR', { dateStyle: 'medium', timeStyle: 'short' }) : ''}
            </p>
          </div>
        </div>
      ))}
      {showFull && (
        <PensionJournal animalId={animalId} animalNom={animalNom} readOnly onClose={() => setShowFull(false)} />
      )}
    </div>
  );
}

// ─── Suivi Repro Tab (composant séparé pour respecter les règles des hooks) ───

interface SuiviReproTabProps {
  isMale: boolean;
  espece: string;
  animalId: string;
  userId: string;
  animalNom: string;
  animalIdent: string;
  chaleurs: HealthRecord[];
  saillies: HealthRecord[];
  gestations: HealthRecord[];
  reproAdd: string | null;
  setReproAdd: (v: string | null) => void;
  savingRepro: boolean;
  saveRepro: (table: string, data: Record<string, string>) => Promise<void>;
  saveSaillie: (data: Record<string, string>) => Promise<void>;
  updateRepro: (table: string, id: string, data: Record<string, string>) => Promise<void>;
  deleteRepro: (table: string, id: string) => Promise<void>;
  intervalleCustom: number | null;
  onSaveIntervalleCustom: (val: number | null) => Promise<void>;
  readOnly?: boolean;
}

function SuiviReproTab({ isMale, espece, animalId, userId, animalNom, animalIdent, chaleurs, saillies, gestations, reproAdd, setReproAdd, savingRepro, saveRepro, saveSaillie, updateRepro, deleteRepro, intervalleCustom, onSaveIntervalleCustom, readOnly = false }: SuiviReproTabProps) {
  const subtabs = isMale
    ? [{ key: 'saillies', label: 'Saillies' }]
    : [{ key: 'chaleurs', label: 'Chaleurs' }, { key: 'saillies', label: 'Saillies' }, { key: 'gestations', label: 'Gestations' }];
  const [subTab, setSubTab] = useState(subtabs[0].key);
  const [editId, setEditId] = useState<string | null>(null);
  const [editData, setEditData] = useState<Record<string, string>>({});
  const [partners, setPartners] = useState<{ id: string; nom: string; identification: string }[]>([]);
  const [showIntervalModal, setShowIntervalModal] = useState(false);
  const [intervalInput, setIntervalInput] = useState('');
  const [savingInterval, setSavingInterval] = useState(false);

  useEffect(() => {
    if (!userId || !animalId) return;
    const sexePartenaire = isMale ? 'femelle' : 'male';
    supabase.from('animaux')
      .select('id, nom, identification')
      .eq('uid_eleveur', userId)
      .eq('espece', espece)
      .eq('sexe', sexePartenaire)
      .neq('id', animalId)
      .then(({ data }) => { if (data) setPartners(data as { id: string; nom: string; identification: string }[]); });
  }, [userId, espece, isMale, animalId]);

  function startEdit(record: HealthRecord) {
    const data: Record<string, string> = {};
    for (const [k, v] of Object.entries(record)) {
      if (k === 'id' || k === 'animal_id' || k === 'created_at' || v == null) continue;
      data[k] = Array.isArray(v) ? JSON.stringify(v) : String(v);
    }
    setEditId(record.id);
    setEditData(data);
  }

  const chaleurFields = [
    { key: 'date', label: 'Date de début', type: 'date', required: true },
    { key: 'date_fin', label: 'Date de fin', type: 'date' },
    { key: 'duree', label: 'Durée (jours)' },
    { key: 'notes', label: 'Notes' },
  ];
  const gestationFields = [
    { key: 'date', label: 'Date de conception', type: 'date', required: true },
    { key: 'date_prevue', label: `Mise-bas estimée (auto: ${GESTATION_DUREE[espece] ?? '?'} j)`, type: 'date' },
    { key: 'nb_attendu', label: 'Nb attendus', type: 'number' },
    { key: 'date_naissance', label: 'Date naissance réelle', type: 'date' },
    { key: 'nb_nes', label: 'Nb nés', type: 'number' },
    { key: 'notes', label: 'Notes' },
  ];

  return (
    <div className="space-y-4">
      <div className="flex gap-1 bg-gray-100 rounded-xl p-1">
        {subtabs.map(t => (
          <button key={t.key} onClick={() => setSubTab(t.key)}
            className={`flex-1 py-2 text-sm font-semibold rounded-lg transition-all ${subTab === t.key ? 'bg-white text-[#0C5C6C] shadow-sm' : 'text-gray-500 hover:text-gray-700'}`}>
            {t.label}
          </button>
        ))}
      </div>

      {subTab === 'chaleurs' && !isMale && (
        <div className="space-y-3">
          <div className="flex justify-between items-center">
            <h3 className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey,sans-serif' }}>Chaleurs</h3>
            <div className="flex gap-2">
              {!readOnly && <button onClick={() => { setIntervalInput(String(intervalleCustom ?? CHALEURS_INTERVAL[espece] ?? '')); setShowIntervalModal(true); }}
                className="text-sm border border-[#0C5C6C] text-[#0C5C6C] font-semibold px-3 py-1.5 rounded-full hover:bg-[#0C5C6C]/10">
                ⏱ Intervalle
              </button>}
              {!readOnly && <button onClick={() => { setReproAdd(reproAdd === 'chaleurs' ? null : 'chaleurs'); setEditId(null); }}
                className="text-sm bg-[#0C5C6C] text-white font-semibold px-3 py-1.5 rounded-full hover:bg-[#094F5D]">+ Ajouter</button>}
            </div>
          </div>
          {intervalleCustom != null && (
            <p className="text-xs text-[#0C5C6C] bg-[#0C5C6C]/10 rounded-lg px-3 py-1.5">
              Intervalle personnalisé : <strong>{intervalleCustom} jours</strong>
              <span className="text-gray-400"> (défaut espèce : {CHALEURS_INTERVAL[espece] ?? '?'} j)</span>
            </p>
          )}
          {showIntervalModal && (
            <div className="bg-white rounded-2xl p-4 shadow-sm border border-gray-100 space-y-3">
              <p className="font-semibold text-sm text-[#1F2A2E]">Espacement des chaleurs (jours)</p>
              <input
                type="number" min="1" value={intervalInput}
                onChange={e => setIntervalInput(e.target.value)}
                placeholder={String(CHALEURS_INTERVAL[espece] ?? '')}
                className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30"
              />
              <div className="flex gap-2">
                <button
                  disabled={savingInterval}
                  onClick={async () => {
                    const val = parseInt(intervalInput, 10);
                    if (!val || val < 1) return;
                    setSavingInterval(true);
                    await onSaveIntervalleCustom(val);
                    setSavingInterval(false);
                    setShowIntervalModal(false);
                  }}
                  className="flex-1 bg-[#0C5C6C] text-white text-sm font-semibold py-2 rounded-xl hover:bg-[#094F5D] disabled:opacity-50">
                  {savingInterval ? 'Enregistrement…' : 'Enregistrer'}
                </button>
                <button
                  disabled={savingInterval}
                  onClick={async () => {
                    setSavingInterval(true);
                    await onSaveIntervalleCustom(null);
                    setSavingInterval(false);
                    setShowIntervalModal(false);
                  }}
                  className="flex-1 border border-gray-300 text-gray-600 text-sm font-semibold py-2 rounded-xl hover:bg-gray-50 disabled:opacity-50">
                  Réinitialiser
                </button>
                <button onClick={() => setShowIntervalModal(false)}
                  className="px-3 text-gray-400 hover:text-gray-600 text-xl">×</button>
              </div>
            </div>
          )}
          {(() => { const next = nextHeatDate(chaleurs, espece, intervalleCustom); return next ? <NextHeatBanner nextHeat={next} espece={espece} /> : null; })()}
          {reproAdd === 'chaleurs' && (
            <div className="bg-white rounded-2xl p-4 shadow-sm">
              <AddHealthForm saving={savingRepro} onCancel={() => setReproAdd(null)}
                onSave={d => saveRepro('chaleurs', d)} fields={chaleurFields} />
            </div>
          )}
          {chaleurs.length === 0 && !reproAdd && <p className="text-sm text-gray-400 text-center py-8">Aucune chaleur enregistrée</p>}
          {chaleurs.map(r => (
            <div key={r.id} className="bg-white rounded-2xl p-4 shadow-sm">
              {editId === r.id ? (
                <AddHealthForm saving={savingRepro} initial={editData} fields={chaleurFields}
                  onCancel={() => setEditId(null)}
                  onSave={async d => { await updateRepro('chaleurs', r.id, d); setEditId(null); }} />
              ) : (
                <div className="flex items-start gap-3">
                  <div className="w-10 h-10 rounded-xl bg-pink-50 flex items-center justify-center text-xl flex-shrink-0">🌸</div>
                  <div className="flex-1 cursor-pointer" onClick={() => startEdit(r)}>
                    <p className="font-semibold text-sm">
                      {fmtDate(String(r.date ?? ''))}{r.date_fin ? ` → ${fmtDate(String(r.date_fin))}` : ''}
                    </p>
                    {!!r.duree && <p className="text-xs text-gray-500">Durée : {String(r.duree)} jours</p>}
                    {!!r.notes && <p className="text-xs text-gray-400">{String(r.notes)}</p>}
                    <p className="text-xs text-[#0C5C6C] mt-1">Modifier →</p>
                  </div>
                  {!readOnly && <button onClick={() => deleteRepro('chaleurs', r.id)} className="text-red-300 hover:text-red-500 text-lg">×</button>}
                </div>
              )}
            </div>
          ))}
        </div>
      )}

      {subTab === 'saillies' && (
        <div className="space-y-3">
          <div className="flex justify-between items-center">
            <h3 className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey,sans-serif' }}>Saillies</h3>
            {!readOnly && <button onClick={() => { setReproAdd(reproAdd === 'saillies' ? null : 'saillies'); setEditId(null); }}
              className="text-sm bg-[#0C5C6C] text-white font-semibold px-3 py-1.5 rounded-full hover:bg-[#094F5D]">+ Ajouter</button>}
          </div>
          {reproAdd === 'saillies' && (
            <div className="bg-white rounded-2xl p-4 shadow-sm">
              <SaillieForm partners={partners} isMale={isMale} saving={savingRepro} espece={espece}
                onSave={saveSaillie} onCancel={() => setReproAdd(null)} />
            </div>
          )}
          {saillies.length === 0 && !reproAdd && <p className="text-sm text-gray-400 text-center py-8">Aucune saillie enregistrée</p>}
          {saillies.map(r => {
            const sd = parseSaillieDates(r.dates != null ? JSON.stringify(r.dates) : undefined, String(r.date ?? ''));
            const fen = !isMale ? fenetreMiseBas(sd, espece) : null;
            return (
            <div key={r.id} className="bg-white rounded-2xl p-4 shadow-sm">
              {editId === r.id ? (
                <SaillieForm partners={partners} isMale={isMale} saving={savingRepro} initial={editData} espece={espece}
                  onSave={async d => { await updateRepro('saillies', r.id, d); setEditId(null); }}
                  onCancel={() => setEditId(null)} />
              ) : (
                <div className="flex items-start gap-3">
                  <div className="w-10 h-10 rounded-xl bg-purple-50 flex items-center justify-center text-xl flex-shrink-0">💕</div>
                  <div className="flex-1 cursor-pointer" onClick={() => startEdit(r)}>
                    {sd.length > 1 ? (
                      <div className="text-sm font-semibold leading-snug">
                        {sd.map((d, i) => <div key={i}>Saillie {i + 1} : {fmtDate(d)}</div>)}
                      </div>
                    ) : (
                      <p className="font-semibold text-sm">{fmtDate(String(r.date ?? ''))}</p>
                    )}
                    {fen && (
                      <p className="text-xs text-green-700 mt-0.5">
                        {fen.debut === fen.fin
                          ? `Mise-bas estimée : ${fmtDate(fen.probable)}`
                          : `Fenêtre mise-bas : ${fmtDate(fen.debut)} → ${fmtDate(fen.fin)} · probable ${fmtDate(fen.probable)}`}
                      </p>
                    )}
                    {!!r.nom_partenaire && <p className="text-xs text-gray-600">Partenaire : {String(r.nom_partenaire)}</p>}
                    {!!r.methode && <p className="text-xs text-gray-400">{String(r.methode)}</p>}
                    {!!r.notes && <p className="text-xs text-gray-400">{String(r.notes)}</p>}
                    <p className="text-xs text-[#0C5C6C] mt-1">Modifier →</p>
                  </div>
                  {!readOnly && <button onClick={() => deleteRepro('saillies', r.id)} className="text-red-300 hover:text-red-500 text-lg">×</button>}
                </div>
              )}
            </div>
          ); })}
        </div>
      )}

      {subTab === 'gestations' && !isMale && (
        <div className="space-y-3">
          <div className="flex justify-between items-center">
            <h3 className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey,sans-serif' }}>Gestations</h3>
            {!readOnly && <button onClick={() => { setReproAdd(reproAdd === 'gestations' ? null : 'gestations'); setEditId(null); }}
              className="text-sm bg-[#0C5C6C] text-white font-semibold px-3 py-1.5 rounded-full hover:bg-[#094F5D]">+ Ajouter</button>}
          </div>
          {reproAdd === 'gestations' && (
            <div className="bg-white rounded-2xl p-4 shadow-sm">
              <GestationForm espece={espece} saving={savingRepro} onCancel={() => setReproAdd(null)}
                onSave={async d => { await saveRepro('gestations', d); }} />
            </div>
          )}
          {gestations.length === 0 && !reproAdd && <p className="text-sm text-gray-400 text-center py-8">Aucune gestation enregistrée</p>}
          {gestations.map(r => (
            <div key={r.id} className="bg-white rounded-2xl p-4 shadow-sm">
              {editId === r.id ? (
                <GestationForm espece={espece} initial={editData} saving={savingRepro}
                  onCancel={() => setEditId(null)}
                  onSave={async d => { await updateRepro('gestations', r.id, d); setEditId(null); }} />
              ) : (
                <div className="flex items-start gap-3">
                  <div className="w-10 h-10 rounded-xl bg-amber-50 flex items-center justify-center text-xl flex-shrink-0">🤰</div>
                  <div className="flex-1 cursor-pointer" onClick={() => startEdit(r)}>
                    <div className="flex items-center gap-2 mb-0.5 flex-wrap">
                      <p className="font-semibold text-sm">Conception : {fmtDate(String(r.date ?? ''))}</p>
                      {r.gestation_confirmee != null && (
                        <span className={`text-xs font-semibold px-2 py-0.5 rounded-full ${r.gestation_confirmee ? 'bg-green-100 text-green-700' : 'bg-amber-100 text-amber-700'}`}>
                          {r.gestation_confirmee ? '✓ Confirmée' : 'À confirmer'}
                        </span>
                      )}
                    </div>
                    {!!r.date_prevue && (() => {
                      const d0 = String(r.date_prevue).substring(0, 10);
                      const d1 = r.date_prevue_fin ? String(r.date_prevue_fin).substring(0, 10) : '';
                      if (!d1 || d1 === d0) return <p className="text-xs text-gray-600">Mise-bas prévue : {fmtDate(d0)}</p>;
                      const prob = new Date((new Date(d0).getTime() + new Date(d1).getTime()) / 2).toISOString().substring(0, 10);
                      return (
                        <p className="text-xs text-green-700">
                          Fenêtre mise-bas : {fmtDate(d0)} → {fmtDate(d1)}<br />
                          Date la plus probable : {fmtDate(prob)}
                        </p>
                      );
                    })()}
                    {!!r.date_naissance && <p className="text-xs text-gray-600">Née le : {fmtDate(String(r.date_naissance))}</p>}
                    {!!r.nb_attendu && <p className="text-xs text-gray-400">{String(r.nb_attendu)} attendu(s){r.nb_nes ? ` · ${String(r.nb_nes)} né(s)` : ''}</p>}
                    {!!r.notes && <p className="text-xs text-gray-400">{String(r.notes)}</p>}
                    <p className="text-xs text-[#0C5C6C] mt-1">Modifier →</p>
                  </div>
                  {!readOnly && <button onClick={() => deleteRepro('gestations', r.id)} className="text-red-300 hover:text-red-500 text-lg">×</button>}
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ─── Weight chart (SVG) ───────────────────────────────────────────────────────

function WeightChartSVG({ data, isJuvenile, dateNaissance }: {
  data: { date?: unknown; valeur?: unknown }[];
  isJuvenile: boolean;
  dateNaissance?: string;
}) {
  const [hovered, setHovered] = useState<number | null>(null);
  const W = 400, H = 160, L = 44, T = 20, R = 12, B = 30;
  const w = W - L - R, h = H - T - B;

  const vals = data.map(d => parseFloat(String(d.valeur ?? '0')) || 0);
  const minY = Math.min(...vals), maxY = Math.max(...vals);
  const rangeY = maxY - minY < 0.01 ? 1 : (maxY - minY) * 1.2;
  const baseY = minY - rangeY * 0.1;

  const pts = vals.map((v, i) => ({
    x: L + (vals.length < 2 ? w / 2 : i * w / (vals.length - 1)),
    y: T + h - ((v - baseY) / rangeY) * h,
    val: v, i,
  }));

  const xLabel = (i: number) => {
    const raw = String(data[i].date ?? '');
    if (!raw) return '';
    const dt = new Date(raw);
    if (isNaN(dt.getTime())) return '';
    if (isJuvenile && dateNaissance) {
      const days = Math.floor((dt.getTime() - new Date(dateNaissance).getTime()) / 86400000);
      if (days < 14) return `${days}j`;
      if (days < 90) return `${Math.round(days / 7)}sem`;
      return `${Math.round(days / 30)}m`;
    }
    return dt.toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit' });
  };

  const linePath = pts.map((p, i) => `${i === 0 ? 'M' : 'L'}${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(' ');
  const areaPath = `M${pts[0].x.toFixed(1)},${T + h} ${pts.map(p => `L${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(' ')} L${pts[pts.length - 1].x.toFixed(1)},${T + h} Z`;

  const gridLines = Array.from({ length: 5 }, (_, g) => ({
    yVal: baseY + g * rangeY / 4, yPx: T + h - g * h / 4,
  }));

  const step = Math.ceil((vals.length - 1) / 4) || 1;
  const labelIdxs = new Set([0, vals.length - 1]);
  for (let i = step; i < vals.length - 1; i += step) labelIdxs.add(i);

  const tip = hovered !== null ? pts[hovered] : null;

  return (
    <div className="px-4 pt-3 pb-1">
      <p className="text-xs font-semibold text-[#5F9EAA] mb-1">
        {isJuvenile ? 'Courbe de croissance' : 'Évolution du poids'}
      </p>
      <svg viewBox={`0 0 ${W} ${H}`} className="w-full" style={{ height: 160 }}>
        <defs>
          <linearGradient id="wg" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="#5F9EAA" stopOpacity="0.18" />
            <stop offset="100%" stopColor="#5F9EAA" stopOpacity="0" />
          </linearGradient>
        </defs>
        {gridLines.map(({ yVal, yPx }, g) => (
          <g key={g}>
            <line x1={L} y1={yPx} x2={W - R} y2={yPx} stroke="#F0F0F0" strokeWidth="1" />
            <text x={L - 4} y={yPx + 3} textAnchor="end" fontSize="9" fill="#BBBBBB" fontFamily="system-ui">
              {fmtPoids(yVal < 0 ? 0 : yVal)}
            </text>
          </g>
        ))}
        <path d={areaPath} fill="url(#wg)" />
        <path d={linePath} fill="none" stroke="#5F9EAA" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" />
        {pts.map(p => (
          <g key={p.i} onMouseEnter={() => setHovered(p.i)} onMouseLeave={() => setHovered(null)} style={{ cursor: 'pointer' }}>
            <circle cx={p.x} cy={p.y} r={hovered === p.i ? 5.5 : 3.5} fill="#5F9EAA" />
            <circle cx={p.x} cy={p.y} r={hovered === p.i ? 3.5 : 2} fill="white" />
          </g>
        ))}
        {pts.filter(p => labelIdxs.has(p.i)).map(p => (
          <text key={p.i} x={p.x} y={T + h + 16} textAnchor="middle" fontSize="9" fill="#BBBBBB" fontFamily="system-ui">
            {xLabel(p.i)}
          </text>
        ))}
        {tip && (() => {
          const l1 = poidsLabel(tip.val), l2 = xLabel(tip.i);
          const tw = Math.max(l1.length, l2.length) * 6.5 + 14;
          const th2 = 36;
          let tx = tip.x - tw / 2, ty = tip.y - th2 - 10;
          if (tx < L) tx = L;
          if (tx + tw > W - R) tx = W - R - tw;
          if (ty < T) ty = tip.y + 10;
          return (
            <g>
              <rect x={tx} y={ty} width={tw} height={th2} rx="6" fill="#5F9EAA" />
              <text x={tx + tw / 2} y={ty + 13} textAnchor="middle" fontSize="11" fill="white" fontWeight="700" fontFamily="system-ui">{l1}</text>
              <text x={tx + tw / 2} y={ty + 27} textAnchor="middle" fontSize="9" fill="rgba(255,255,255,0.8)" fontFamily="system-ui">{l2}</text>
            </g>
          );
        })()}
      </svg>
    </div>
  );
}

// ─── Co-propriétaires (profils particuliers) ──────────────────────────────────

interface CoproRow {
  id: string; uid_proprio: string; profile_id_proprio: string | null;
  role_proprio: string; statut: string; transfert_principal_propose: boolean;
  invite_par_profile_id: string | null; _name?: string;
}

function CoproprietairesSection({ animalId, animalNom, userUid }: {
  animalId: string; animalNom: string; userUid?: string;
}) {
  const [myProfileId, setMyProfileId] = useState<string | null>(null);
  const [myName, setMyName] = useState('Un propriétaire');
  const [rows, setRows] = useState<CoproRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState(false);
  const [showSearch, setShowSearch] = useState(false);
  const [q, setQ] = useState('');
  const [searching, setSearching] = useState(false);
  const [searchDone, setSearchDone] = useState(false);
  const [results, setResults] = useState<{ uid: string; profileId: string; name: string; email: string }[]>([]);

  const load = useCallback(async () => {
    if (!userUid) return;
    setLoading(true);
    let pid = myProfileId;
    if (!pid) {
      const { data: me } = await supabase.from('user_profiles')
        .select('id, firstname, lastname, nom').eq('uid', userUid).eq('profile_type', 'particulier').maybeSingle();
      pid = (me?.id as string) ?? null;
      setMyProfileId(pid);
      const n = `${me?.firstname ?? ''} ${me?.lastname ?? ''}`.trim() || (me?.nom as string) || '';
      if (n) setMyName(n);
    }
    const { data } = await supabase.from('animaux_proprietes')
      .select('id, uid_proprio, profile_id_proprio, role_proprio, statut, transfert_principal_propose, invite_par_profile_id')
      .eq('animal_id', animalId).is('date_fin', null).in('statut', ['actif', 'invite']);
    const list = (data ?? []) as CoproRow[];
    const ids = [...new Set(list.filter(r => r.statut === 'actif' && r.profile_id_proprio).map(r => r.profile_id_proprio as string))];
    if (ids.length) {
      const { data: profs } = await supabase.from('user_profiles').select('id, firstname, lastname, nom').in('id', ids);
      const byId = new Map((profs ?? []).map(p => [p.id as string, `${p.firstname ?? ''} ${p.lastname ?? ''}`.trim() || (p.nom as string) || 'Propriétaire']));
      list.forEach(r => { r._name = byId.get(r.profile_id_proprio ?? '') ?? 'Propriétaire'; });
    }
    list.sort((a, b) => (a.role_proprio === 'principal' ? 0 : a.statut === 'actif' ? 1 : 2) - (b.role_proprio === 'principal' ? 0 : b.statut === 'actif' ? 1 : 2));
    setRows(list);
    setLoading(false);
  }, [animalId, userUid, myProfileId]);

  useEffect(() => { load(); }, [load]);

  const myRow = rows.find(r => r.profile_id_proprio === myProfileId);
  const amPrincipal = myRow?.role_proprio === 'principal' && myRow?.statut === 'actif';
  const myInvite = rows.find(r => r.uid_proprio === userUid && r.statut === 'invite');
  const transfertPourMoi = myRow?.transfert_principal_propose === true && myRow?.statut === 'actif';

  async function notify(uid: string, profileId: string | null, type: string, title: string, body: string) {
    try {
      await supabase.from('notifications').insert({
        uid, type, title, body,
        ...(profileId ? { profile_id: profileId, recipient_profile_id: profileId } : {}),
        data: { animal_id: animalId, animal_nom: animalNom }, read: false, created_at: new Date().toISOString(),
      });
    } catch { /* noop */ }
  }

  async function run(fn: () => Promise<void>) {
    if (busy) return;
    setBusy(true);
    try { await fn(); await load(); } catch (e) { alert(`Erreur : ${e instanceof Error ? e.message : e}`); }
    finally { setBusy(false); }
  }

  async function search() {
    const term = q.trim();
    if (term.length < 3) return;
    setSearching(true); setSearchDone(true);
    let users: { uid: string; firstname: string; lastname: string; email: string }[] = [];
    if (term.includes('@')) {
      const { data } = await supabase.from('users').select('uid, firstname, lastname, email').eq('email', term.toLowerCase()).limit(5);
      users = (data ?? []) as typeof users;
    } else {
      const { data } = await supabase.from('users').select('uid, firstname, lastname, email').or(`firstname.ilike.%${term}%,lastname.ilike.%${term}%`).limit(15);
      users = (data ?? []) as typeof users;
    }
    users = users.filter(u => u.uid !== userUid);
    const uids = users.map(u => u.uid);
    const profByUid = new Map<string, string>();
    if (uids.length) {
      const { data: profs } = await supabase.from('user_profiles').select('uid, id').in('uid', uids).eq('profile_type', 'particulier');
      (profs ?? []).forEach(p => profByUid.set(p.uid as string, p.id as string));
    }
    setResults(users.filter(u => profByUid.has(u.uid)).map(u => ({
      uid: u.uid, profileId: profByUid.get(u.uid)!, email: u.email,
      name: `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim() || 'Utilisateur PetsMatch',
    })));
    setSearching(false);
  }

  function invite(picked: { uid: string; profileId: string; name: string }) {
    if (rows.some(r => r.uid_proprio === picked.uid)) {
      alert('Cette personne est déjà propriétaire ou invitée.');
      return;
    }
    return run(async () => {
      await supabase.from('animaux_proprietes').upsert({
        animal_id: animalId, uid_proprio: picked.uid, profile_id_proprio: picked.profileId,
        role_proprio: 'secondaire', statut: 'invite', transfert_principal_propose: false,
        date_debut: new Date().toISOString().slice(0, 10), date_fin: null,
        invite_par_profile_id: myProfileId, invite_le: new Date().toISOString(), accepte_le: null,
      }, { onConflict: 'animal_id,uid_proprio' });
      await notify(picked.uid, picked.profileId, 'coproprio_invitation', 'Invitation de co-propriété',
        `${myName} vous invite à co-gérer la fiche de ${animalNom}.`);
      setShowSearch(false); setQ(''); setResults([]); setSearchDone(false);
    });
  }

  const repondreInvite = (accepte: boolean) => run(async () => {
    if (!myInvite) return;
    await supabase.from('animaux_proprietes').update({
      statut: accepte ? 'actif' : 'refuse', ...(accepte ? { accepte_le: new Date().toISOString() } : {}),
    }).eq('id', myInvite.id);
    if (myInvite.invite_par_profile_id) {
      const { data: inv } = await supabase.from('user_profiles').select('uid').eq('id', myInvite.invite_par_profile_id).maybeSingle();
      if (inv?.uid) await notify(inv.uid as string, myInvite.invite_par_profile_id,
        accepte ? 'coproprio_invitation_acceptee' : 'coproprio_invitation_refusee',
        accepte ? 'Invitation acceptée' : 'Invitation refusée',
        accepte ? `${myName} co-gère désormais ${animalNom}.` : `${myName} a refusé de co-gérer ${animalNom}.`);
    }
  });

  const principalRow = rows.find(r => r.role_proprio === 'principal');

  return (
    <div className="rounded-2xl border border-[#6E9E57]/20 bg-[#6E9E57]/5 p-4">
      <div className="flex items-center gap-2 mb-1">
        <span className="text-base">👥</span>
        <p className="font-bold text-sm text-[#4a7a37]" style={{ fontFamily: 'Galey, sans-serif' }}>Propriétaires</p>
      </div>
      <p className="text-xs text-gray-500 mb-3">
        Les co-propriétaires ont accès à toute la fiche, en lecture et écriture. Le principal est le référent I-CAD.
      </p>

      {myInvite && (
        <div className="rounded-xl bg-[#EAF2F4] border border-[#0C5C6C]/25 p-3 mb-3">
          <p className="text-sm font-bold text-[#1F2A2E]">Vous êtes invité·e à co-gérer cette fiche</p>
          <p className="text-xs text-gray-600 mb-2">En acceptant, vous aurez un accès complet en lecture et écriture.</p>
          <div className="flex gap-2">
            <button disabled={busy} onClick={() => repondreInvite(true)} className="text-xs font-semibold px-3 py-1.5 rounded-xl bg-[#0C5C6C] text-white disabled:opacity-50">Accepter</button>
            <button disabled={busy} onClick={() => repondreInvite(false)} className="text-xs font-semibold px-3 py-1.5 rounded-xl border border-gray-300 text-gray-600 disabled:opacity-50">Refuser</button>
          </div>
        </div>
      )}

      {transfertPourMoi && (
        <div className="rounded-xl bg-[#EAF2F4] border border-[#0C5C6C]/25 p-3 mb-3">
          <p className="text-sm font-bold text-[#1F2A2E]">On vous propose de devenir propriétaire principal</p>
          <p className="text-xs text-gray-600 mb-2">Vous deviendrez le référent I-CAD de cet animal.</p>
          <div className="flex gap-2">
            <button disabled={busy} onClick={() => run(async () => {
              await supabase.rpc('transferer_proprietaire_principal', { p_animal_id: animalId, p_nouveau_profile_id: myProfileId });
              if (principalRow?.uid_proprio) await notify(principalRow.uid_proprio, principalRow.profile_id_proprio, 'coproprio_transfert_accepte', 'Transfert de propriété accepté', `${myName} est maintenant le propriétaire principal de ${animalNom}.`);
              alert('Vous êtes propriétaire principal. Pensez à mettre à jour la déclaration I-CAD : PetsMatch ne modifie pas le fichier national automatiquement.');
            })} className="text-xs font-semibold px-3 py-1.5 rounded-xl bg-[#0C5C6C] text-white disabled:opacity-50">Accepter</button>
            <button disabled={busy} onClick={() => run(async () => {
              await supabase.from('animaux_proprietes').update({ transfert_principal_propose: false }).eq('id', myRow!.id);
              if (principalRow?.uid_proprio) await notify(principalRow.uid_proprio, principalRow.profile_id_proprio, 'coproprio_transfert_accepte', 'Transfert de propriété refusé', `${myName} préfère rester co-propriétaire de ${animalNom}.`);
            })} className="text-xs font-semibold px-3 py-1.5 rounded-xl border border-gray-300 text-gray-600 disabled:opacity-50">Refuser</button>
          </div>
        </div>
      )}

      {loading ? (
        <p className="text-xs text-gray-400 py-3">Chargement…</p>
      ) : (
        <div className="space-y-2">
          {rows.map(r => {
            const isPrincipal = r.role_proprio === 'principal';
            const isInvite = r.statut === 'invite';
            const isMe = r.profile_id_proprio === myProfileId;
            return (
              <div key={r.id} className="flex items-center justify-between bg-white rounded-xl px-3 py-2 shadow-sm">
                <div>
                  <p className="text-sm font-semibold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
                    {isInvite ? 'Invitation envoyée' : r._name}{isMe ? ' (vous)' : ''}
                  </p>
                  <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${
                    isInvite ? 'bg-amber-100 text-amber-700' : isPrincipal ? 'bg-[#EAF2F4] text-[#0C5C6C]' : 'bg-[#EFF4EA] text-[#4a7a37]'
                  }`}>
                    {isInvite ? 'En attente' : isPrincipal ? 'Principal · I-CAD' : 'Co-propriétaire'}
                  </span>
                </div>
                {amPrincipal && !isPrincipal && (
                  <div className="flex gap-2">
                    {isInvite ? (
                      <button disabled={busy} onClick={() => run(async () => { await supabase.from('animaux_proprietes').delete().eq('id', r.id); })}
                        className="text-xs font-semibold px-3 py-1.5 rounded-xl border border-red-200 text-red-500 disabled:opacity-50">Annuler</button>
                    ) : (
                      <>
                        {!r.transfert_principal_propose && (
                          <button disabled={busy} onClick={() => run(async () => {
                            await supabase.from('animaux_proprietes').update({ transfert_principal_propose: true }).eq('id', r.id);
                            await notify(r.uid_proprio, r.profile_id_proprio, 'coproprio_transfert_propose', 'Proposition : devenir propriétaire principal', `${myName} vous propose de devenir le propriétaire principal de ${animalNom}.`);
                          })} className="text-xs font-semibold px-3 py-1.5 rounded-xl border border-[#0C5C6C]/30 text-[#0C5C6C] disabled:opacity-50">Rendre principal</button>
                        )}
                        <button disabled={busy} onClick={() => run(async () => {
                          await supabase.from('animaux_proprietes').delete().eq('id', r.id);
                          await notify(r.uid_proprio, r.profile_id_proprio, 'coproprio_retire', 'Co-propriété retirée', `Vous n'êtes plus co-propriétaire de ${animalNom}.`);
                        })} className="text-xs font-semibold px-3 py-1.5 rounded-xl border border-red-200 text-red-500 disabled:opacity-50">Retirer</button>
                      </>
                    )}
                  </div>
                )}
              </div>
            );
          })}

          {amPrincipal && (
            showSearch ? (
              <div className="bg-white rounded-xl p-3 shadow-sm">
                <div className="flex gap-2">
                  <input value={q} onChange={e => setQ(e.target.value)} onKeyDown={e => e.key === 'Enter' && search()}
                    placeholder="E-mail exact ou nom" className="flex-1 border border-gray-200 rounded-lg px-3 py-1.5 text-sm" />
                  <button disabled={searching} onClick={search} className="text-xs font-semibold px-3 py-1.5 rounded-lg bg-[#6E9E57] text-white disabled:opacity-50">OK</button>
                </div>
                {searching && <p className="text-xs text-gray-400 mt-2">Recherche…</p>}
                {searchDone && !searching && results.length === 0 && <p className="text-xs text-gray-400 mt-2">Aucun compte trouvé.</p>}
                {results.map(u => (
                  <button key={u.uid} onClick={() => invite(u)} className="w-full text-left mt-2 flex items-center justify-between hover:bg-gray-50 rounded-lg px-2 py-1.5">
                    <span><span className="text-sm font-medium text-[#1F2A2E]">{u.name}</span><span className="block text-xs text-gray-400">{u.email}</span></span>
                    <span className="text-[#6E9E57] text-lg">＋</span>
                  </button>
                ))}
                <button onClick={() => { setShowSearch(false); setQ(''); setResults([]); setSearchDone(false); }} className="text-xs text-gray-400 mt-2">Annuler</button>
              </div>
            ) : (
              <button onClick={() => setShowSearch(true)} className="w-full text-sm font-semibold py-2 rounded-xl bg-[#6E9E57] text-white" style={{ fontFamily: 'Galey, sans-serif' }}>
                + Inviter un co-propriétaire
              </button>
            )
          )}

          {!amPrincipal && myRow?.statut === 'actif' && (
            <button disabled={busy} onClick={() => run(async () => {
              await supabase.from('animaux_proprietes').delete().eq('id', myRow!.id);
              if (principalRow?.uid_proprio) await notify(principalRow.uid_proprio, principalRow.profile_id_proprio, 'coproprio_quitte', 'Un co-propriétaire a quitté', `${myName} ne co-gère plus la fiche de ${animalNom}.`);
            })} className="w-full text-sm font-medium py-2 rounded-xl border border-red-200 text-red-500 disabled:opacity-50">
              Quitter la copropriété
            </button>
          )}
        </div>
      )}
    </div>
  );
}

// ─── Page principale ──────────────────────────────────────────────────────────

export default function AnimalFichePage() {
  const { id } = useParams<{ id: string }>();
  const { user, userData } = useAuth();
  const activeProfileId = useActiveProfile();
  const router = useRouter();
  const searchParams = useSearchParams();
  const isEleveur = userData?.isElevage === true;
  // isOwner = l'utilisateur est bien le propriétaire de cet animal (pas juste un employé)
  // Déterminé après chargement de l'animal (voir useMemo ci-dessous)
  const isNew = id === 'ajouter';

  // Deep-link depuis une notification santé (rappel vaccin/vermifuge/
  // antiparasitaire) : ?tab=sante&cat=antiparasitaires ouvre directement
  // l'onglet et déplie/scrolle la bonne section, au lieu de forcer l'usager
  // à retrouver la catégorie lui-même.
  const tabParam = searchParams.get('tab');
  const catParam = searchParams.get('cat');

  // ── État identité
  const [loading, setLoading] = useState(!isNew);
  const [saving, setSaving] = useState(false);
  const [editing, setEditing] = useState(isNew);
  const [tab, setTab] = useState<'identite'|'sante'|'repro'|'alimentation'|'consultations'|'documents'|'education'|'pension'>(
    (['sante', 'education', 'pension', 'documents'] as const).includes(tabParam as never)
      ? (tabParam as 'sante') : 'identite'
  );

  const [animal, setAnimal] = useState<Animal>({ id:'', espece:'chien', sexe:'male' });
  // Recherche d'un contact PetsMatch pour Contacts urgence
  const [showContactSearch, setShowContactSearch] = useState(false);
  const [contactQuery, setContactQuery] = useState('');
  const [contactResults, setContactResults] = useState<{ nom: string; tel: string }[]>([]);
  const [contactSearching, setContactSearching] = useState(false);
  const [contactSearchDone, setContactSearchDone] = useState(false);
  // Propriétaire courant selon animaux_proprietes (date_fin IS NULL) — source
  // de vérité pour la propriété (voir migration_fix_animaux_proprietes_
  // unique_constraint.sql), contrairement à animaux.uid_eleveur/uid_
  // proprietaire qui ne bougent pas forcément à chaque cession/transfert.
  const [currentProprioUid, setCurrentProprioUid] = useState<string | null>(null);
  const steriliseSavedRef = useRef(false);
  const [breeds, setBreeds] = useState<string[]>([]);

  // ── Cession
  const [showCession, setShowCession] = useState(false);
  const [cessionEnCours, setCessionEnCours] = useState<Record<string, unknown> | null>(null);
  const [confirmingCession, setConfirmingCession] = useState(false);
  const [revokingCession, setRevokingCession] = useState(false);

  // ── Réservation (avant cession)
  const [showReservation, setShowReservation] = useState(false);
  const [reservation, setReservation] = useState<Reservation | null>(null);
  const [cancelingReservation, setCancelingReservation] = useState(false);

  // ── État enregistre entrée/sortie
  const [showRegistre, setShowRegistre] = useState(false);
  const [mouvements, setMouvements] = useState<{id:string;type:string;date_mouvement:string;motif?:string;provenance_qualite?:string;provenance_nom?:string;destinataire_qualite?:string;destinataire_nom?:string}[]>([]);
  const [showAddMvt, setShowAddMvt] = useState(false);
  const [mvtForm, setMvtForm] = useState({type:'entree',date:new Date().toISOString().slice(0,10),motif:'',provQualite:'',provNom:'',destQualite:'',destNom:'',notes:''});
  const [savingMvt, setSavingMvt] = useState(false);

  // ── État alerte perdue
  const [alerteId, setAlerteId] = useState<string|null>(null);
  const [alerteStatut, setAlerteStatut] = useState<string|null>(null);

  // ── État santé
  const [health, setHealth] = useState<Record<string, HealthRecord[]>>({
    vaccinations:[], traitements:[], visites:[], vermifuges:[], antiparasitaires:[], chirurgies:[], allergies:[], poids:[]
  });
  const [addOpen, setAddOpen] = useState<string|null>(null);
  const [savingHealth, setSavingHealth] = useState(false);
  const [editPoids, setEditPoids] = useState<string|null>(null);
  // "+ Rappel" sur un vaccin : pré-remplit le formulaire d'ajout avec le
  // même vaccin/vétérinaire, il ne reste qu'à changer date et lot.
  const [rappelPrefill, setRappelPrefill] = useState<Record<string,string>|null>(null);

  // ── État documents vétérinaires
  const [ordonnances, setOrdonnances] = useState<HealthRecord[]>([]);
  const [radios, setRadios] = useState<HealthRecord[]>([]);
  const [crs, setCrs] = useState<HealthRecord[]>([]);
  const [addDocOpen, setAddDocOpen] = useState<string|null>(null);
  const [savingDoc, setSavingDoc] = useState(false);
  const [vetNames, setVetNames] = useState<Record<string,string>>({});

  // ── Accès vétérinaires (animal_access)
  const [vetAcces, setVetAcces] = useState<{id:string;pro_profile_id:string;vet_nom:string;statut:string;granted_at?:string}[]>([]);
  const [vetAccesSaving, setVetAccesSaving] = useState<string|null>(null);
  const [hasPensionUpdates, setHasPensionUpdates] = useState(false);
  const [hasEducationRapports, setHasEducationRapports] = useState(false);
  const [showEducationRapports, setShowEducationRapports] = useState(false);
  const [educationRapports, setEducationRapports] = useState<{ id: string; date_seance: string; contenu: string; exercices_conseilles: string | null }[]>([]);
  const [showJournal, setShowJournal] = useState(false);

  // ── État repro
  const [chaleurs, setChaleurs] = useState<HealthRecord[]>([]);
  const [saillies, setSaillies] = useState<HealthRecord[]>([]);
  const [gestations, setGestations] = useState<HealthRecord[]>([]);
  const [reproAdd, setReproAdd] = useState<string|null>(null);
  const [savingRepro, setSavingRepro] = useState(false);
  const [isEmployeOfOwner, setIsEmployeOfOwner] = useState(false);
  const [employePerms, setEmployePerms] = useState<string[]>([]);

  // ── État documents
  const [uploading, setUploading] = useState(false);
  const [pendingDocType, setPendingDocType] = useState<string>('autre');
  const [uploadingPedigree, setUploadingPedigree] = useState(false);
  const [photoUploading, setPhotoUploading] = useState(false);
  const [cropSrc, setCropSrc] = useState<string | null>(null);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [nomElevage, setNomElevage] = useState('');
  const [adresseElevage, setAdresseElevage] = useState('');
  const [mesFemelles, setMesFemelles] = useState<{id:string;nom:string;identification?:string;race?:string;photo_url?:string;date_naissance?:string}[]>([]);
  const [showMerePicker, setShowMerePicker] = useState(false);
  const [mereSearch, setMereSearch] = useState('');
  const [mesMales, setMesMales] = useState<{id:string;nom:string;identification?:string;race?:string;photo_url?:string}[]>([]);
  const [showPerePicker, setShowPerePicker] = useState(false);
  const [pereSearch, setPereSearch] = useState('');
  // Rattachement par puce : recherche l'animal (tous propriétaires confondus,
  // ex. saillie extérieure) correspondant au numéro de puce saisi, pour
  // permettre plus tard une vraie généalogie inter-éleveurs.
  const [perePuceMatch, setPerePuceMatch] = useState<{id:string;nom:string;race?:string}|null>(null);
  const [merePuceMatch, setMerePuceMatch] = useState<{id:string;nom:string;race?:string}|null>(null);

  // ── Chargement
  const loadAnimal = useCallback(async () => {
    if (!user || isNew) return;
    const { data } = await supabase.from('animaux').select('*').eq('id', id).single();
    if (data) {
      setAnimal(data as Animal);
      steriliseSavedRef.current = data.sterilise === true;
      supabase.from('animaux_proprietes').select('uid_proprio')
        .eq('animal_id', id).is('date_fin', null).maybeSingle()
        .then(({ data: prop }) => setCurrentProprioUid(prop?.uid_proprio ?? null));
      if (data.uid_eleveur && data.uid_eleveur !== user.uid) {
        // Cherche la relation employé en essayant d'abord par uid, puis par profile_id
        let empRow: { id: string; eleveur_profile_id: string | null } | null = null;

        const { data: r1 } = await supabase.from('employes')
          .select('id, eleveur_profile_id')
          .eq('uid_eleveur', data.uid_eleveur).eq('uid_employe', user.uid).eq('actif', true).maybeSingle();
        empRow = r1 ?? null;

        // Fallback : vérification par employe_profile_id (pour les lignes sans uid_employe)
        if (!empRow && activeProfileId) {
          const { data: allEmpRows } = await supabase.from('employes')
            .select('id, eleveur_profile_id, uid_eleveur')
            .eq('employe_profile_id', activeProfileId)
            .eq('actif', true);
          const matched = (allEmpRows ?? []).find(
            (r: { uid_eleveur: string; eleveur_profile_id: string | null }) => r.uid_eleveur === data.uid_eleveur
          );
          empRow = matched ?? null;
        }

        if (empRow) {
          setIsEmployeOfOwner(true);
          if (empRow.eleveur_profile_id && activeProfileId) {
            const { data: permsRows } = await supabase.from('employe_permissions')
              .select('permission')
              .eq('eleveur_profile_id', empRow.eleveur_profile_id)
              .eq('employe_profile_id', activeProfileId);
            setEmployePerms((permsRows ?? []).map((r: { permission: string }) => r.permission));
          }
        }
      }
    }
    setLoading(false);
  }, [id, user, isNew, activeProfileId]);

  const loadHealth = useCallback(async () => {
    if (!id || isNew) return;
    const tables = ['vaccinations','traitements','visites','vermifuges','antiparasitaires','chirurgies','allergies','poids'];
    const results = await Promise.all(
      tables.map(t => supabase.from(t).select('*').eq('animal_id', id).order('date', { ascending: false }))
    );
    const newHealth: Record<string,HealthRecord[]> = {};
    tables.forEach((t,i) => { newHealth[t] = (results[i].data ?? []) as HealthRecord[]; });
    setHealth(newHealth);
  }, [id, isNew]);

  const loadRepro = useCallback(async () => {
    if (!id || isNew || (!isEleveur && !isEmployeOfOwner)) return;
    const [ch, sa, ge] = await Promise.all([
      supabase.from('chaleurs').select('*').eq('animal_id', id).order('date', { ascending: false }),
      supabase.from('saillies').select('*').eq('animal_id', id).order('date', { ascending: false }),
      supabase.from('gestations').select('*').eq('animal_id', id).order('date', { ascending: false }),
    ]);
    setChaleurs((ch.data ?? []) as HealthRecord[]);
    setSaillies((sa.data ?? []) as HealthRecord[]);
    setGestations((ge.data ?? []) as HealthRecord[]);
  }, [id, isNew, isEleveur, isEmployeOfOwner]);

  const loadAlerte = useCallback(async () => {
    if (!id || isNew) return;
    const { data } = await supabase.from('alertes_perdus').select('id, statut')
      .eq('animal_id', id).eq('statut', 'perdu').maybeSingle();
    if (data) { setAlerteId(data.id); setAlerteStatut(data.statut); }
  }, [id, isNew]);

  const loadDocs = useCallback(async () => {
    if (!id || isNew) return;
    const [ord, rad, cr, grants] = await Promise.all([
      supabase.from('ordonnances').select('*').eq('animal_id', id).order('date', { ascending: false }),
      supabase.from('radios').select('*').eq('animal_id', id).order('date', { ascending: false }),
      supabase.from('comptes_rendus').select('*').eq('animal_id', id).order('date', { ascending: false }),
      supabase.from('animal_access').select('id, pro_profile_id, statut, granted_at').eq('animal_id', id).neq('statut', 'revoked'),
    ]);
    const allDocs = [...(ord.data ?? []), ...(rad.data ?? []), ...(cr.data ?? [])] as HealthRecord[];
    setOrdonnances((ord.data ?? []) as HealthRecord[]);
    setRadios((rad.data ?? []) as HealthRecord[]);
    setCrs((cr.data ?? []) as HealthRecord[]);
    // Résoudre les noms des vétérinaires (docs + accès)
    const grantRows = (grants.data ?? []) as {id:string;pro_profile_id:string;statut:string;granted_at?:string}[];
    const proProfileIds = grantRows.map(g => g.pro_profile_id).filter(Boolean);
    let profileUidMap: Record<string,string> = {};
    if (proProfileIds.length > 0) {
      const { data: profiles } = await supabase.from('user_profiles').select('id, uid').in('id', proProfileIds);
      (profiles ?? []).forEach((p: {id:string;uid:string}) => { profileUidMap[p.id] = p.uid; });
    }
    const vetUids = Object.values(profileUidMap);
    const proUids = [...new Set([...allDocs.map(d => d.pro_uid as string).filter(Boolean), ...vetUids])];
    const names: Record<string,string> = {};
    if (proUids.length > 0) {
      const { data: users } = await supabase.from('user_profiles').select('uid, firstname, lastname').in('uid', proUids).eq('is_main', true);
      (users ?? []).forEach((u: Record<string,unknown>) => {
        const nom = `${u.firstname ?? ''} ${u.lastname ?? ''}`.trim();
        names[u.uid as string] = nom ? `Dr. ${nom}` : 'Vétérinaire';
      });
      setVetNames(names);
    }
    setVetAcces(grantRows.map(g => ({ ...g, vet_nom: names[profileUidMap[g.pro_profile_id]] ?? 'Vétérinaire' })));
  }, [id, isNew]);

  const loadMouvements = useCallback(async () => {
    if (!id || isNew || !user) return;
    const { data } = await supabase.from('registre_mouvements').select('id, type, date_mouvement, motif, provenance_qualite, provenance_nom, destinataire_qualite, destinataire_nom')
      .eq('animal_id', id).eq('uid_eleveur', user.uid).order('date_mouvement', { ascending: false });
    setMouvements(data ?? []);
  }, [id, isNew, user]);

  const loadCessionEnCours = useCallback(async () => {
    if (!id || isNew || animal.statut !== 'cession_en_cours') return;
    const { data } = await supabase
      .from('cessions')
      .select('*')
      .eq('animal_id', id)
      .neq('statut', 'revoquee')
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    setCessionEnCours(data ?? null);
  }, [id, isNew, animal.statut]);

  async function confirmerCession() {
    if (!cessionEnCours || !user) return;
    setConfirmingCession(true);
    const now = new Date().toISOString();
    const dateCession = (cessionEnCours.date_cession as string) ?? now.split('T')[0];
    await supabase.from('cessions').update({ statut: 'confirme', confirmed_at: now }).eq('id', cessionEnCours.id);
    const acqUidC = cessionEnCours.uid_acquereur as string | null;
    const acqProfileId = await resolveAcquereurProfileId(
      acqUidC,
      (cessionEnCours.qualite as string | undefined) ?? null,
      (cessionEnCours.acquereur_profile_id as string | undefined) ?? null,
    );
    await supabase.from('animaux').update({
      statut: 'sorti',
      date_sortie: dateCession,
      destinataire_nom: cessionEnCours.nom_acquereur,
      destinataire_adresse: cessionEnCours.adresse_acquereur ?? null,
      destinataire_qualite: cessionEnCours.qualite ?? 'particulier',
      uid_acquereur: acqUidC ?? null,
      ...(acqProfileId ? { profile_id_acquereur: acqProfileId } : {}),
    }).eq('id', id);

    // Historique de propriété — bascule seulement maintenant que la cession
    // est définitive (confirmée par l'éleveur), pas avant : sinon l'animal
    // apparaîtrait comme "ancien" dans la liste dès la création de la
    // cession alors que l'éleveur pouvait encore la révoquer.
    await supabase.from('animaux_proprietes')
      .update({ date_fin: dateCession })
      .eq('animal_id', id)
      .eq('uid_proprio', user.uid)
      .is('date_fin', null);
    if (acqUidC) {
      await supabase.from('animaux_proprietes').upsert({
        animal_id:          id,
        uid_proprio:        acqUidC,
        date_debut:         dateCession,
        date_fin:           null,
        profile_id_proprio: acqProfileId,
      }, { onConflict: 'animal_id,uid_proprio' });
    }

    // Registre entrées / sorties : SORTIE pour le cédant (+ ENTRÉE pour
    // l'acquéreur éleveur / association).
    try {
      if (acqUidC) {
        const { data: dejaSorti } = await supabase.from('registre_mouvements')
          .select('id').eq('animal_id', id).eq('type', 'sortie').eq('motif', 'cession').limit(1);
        if (!dejaSorti || dejaSorti.length === 0) {
          const { data: acqU } = await supabase.from('users')
            .select('firstname, lastname, name_elevage, is_elevage, is_association').eq('uid', acqUidC).maybeSingle();
          const acqNom = (acqU?.name_elevage as string || '').trim()
            || `${acqU?.firstname ?? ''} ${acqU?.lastname ?? ''}`.trim()
            || (cessionEnCours.nom_acquereur as string | undefined) || '';
          const acqEleveur = acqU?.is_elevage === true;
          const acqAsso = acqU?.is_association === true;
          await supabase.from('registre_mouvements').insert({
            animal_id: id, uid_eleveur: user.uid, type: 'sortie',
            date_mouvement: dateCession, motif: 'cession',
            destinataire_qualite: acqEleveur ? 'eleveur' : acqAsso ? 'association' : 'particulier',
            destinataire_nom: acqNom, cession_id: cessionEnCours.id,
          });
          if (acqEleveur || acqAsso) {
            const { data: acqProf } = await supabase.from('user_profiles')
              .select('id').eq('uid', acqUidC).eq('is_main', true).maybeSingle();
            await supabase.from('registre_mouvements').insert({
              animal_id: id, uid_eleveur: acqUidC,
              ...(acqProf?.id ? { eleveur_profile_id: acqProf.id } : {}),
              type: 'entree', date_mouvement: dateCession, motif: 'cession',
              provenance_qualite: 'eleveur', cession_id: cessionEnCours.id,
            });
          }
        }
      }
    } catch { /* pas bloquant */ }

    setAnimal(p => ({ ...p, statut: 'sorti', date_sortie: dateCession, destinataire_nom: cessionEnCours.nom_acquereur as string }));
    setCessionEnCours(null);
    setConfirmingCession(false);
  }

  async function revoquerCession() {
    if (!cessionEnCours || !confirm('Révoquer la cession ? L\'animal restera dans votre élevage.')) return;
    setRevokingCession(true);
    await supabase.from('cessions').update({ statut: 'revoquee' }).eq('id', cessionEnCours.id);
    await supabase.from('animaux').update({ statut: 'present' }).eq('id', id);
    setAnimal(p => ({ ...p, statut: 'present' }));
    setCessionEnCours(null);
    setRevokingCession(false);
  }

  const loadReservation = useCallback(async () => {
    if (!id || isNew || animal.statut !== 'reserve') { setReservation(null); return; }
    const { data } = await supabase
      .from('reservations_animaux')
      .select('*')
      .eq('animal_id', id)
      .eq('statut', 'active')
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();
    setReservation((data ?? null) as Reservation | null);
  }, [id, isNew, animal.statut]);

  async function annulerReservation() {
    if (!reservation || !confirm('Annuler la réservation ?')) return;
    setCancelingReservation(true);
    await supabase.from('reservations_animaux').update({ statut: 'annulee', updated_at: new Date().toISOString() }).eq('id', reservation.id);
    await supabase.from('animaux').update({ statut: 'present' }).eq('id', id);
    setAnimal(p => ({ ...p, statut: 'present' }));
    setReservation(null);
    setCancelingReservation(false);
  }

  useEffect(() => { loadBreeds(animal.espece ?? 'chien').then(setBreeds); }, [animal.espece]);

  useEffect(() => {
    const puce = (animal.puce_pere ?? '').trim();
    if (puce.length < 4) { setPerePuceMatch(null); return; }
    const t = setTimeout(async () => {
      const { data } = await supabase.from('animaux').select('id,nom,race')
        .eq('identification', puce).neq('id', id ?? '').limit(1);
      setPerePuceMatch(data && data[0] ? data[0] : null);
    }, 500);
    return () => clearTimeout(t);
  }, [animal.puce_pere, id]);

  useEffect(() => {
    const puce = (animal.puce_mere ?? '').trim();
    if (puce.length < 4) { setMerePuceMatch(null); return; }
    const t = setTimeout(async () => {
      const { data } = await supabase.from('animaux').select('id,nom,race')
        .eq('identification', puce).neq('id', id ?? '').limit(1);
      setMerePuceMatch(data && data[0] ? data[0] : null);
    }, 500);
    return () => clearTimeout(t);
  }, [animal.puce_mere, id]);
  useEffect(() => { loadAnimal(); loadHealth(); loadRepro(); loadAlerte(); loadDocs(); loadMouvements(); }, [loadAnimal, loadHealth, loadRepro, loadAlerte, loadDocs, loadMouvements]);
  // Deep-link depuis une notification santé : scrolle jusqu'à la section
  // ouverte par ?cat=... une fois l'onglet Santé affiché.
  useEffect(() => {
    if (tab !== 'sante' || !catParam) return;
    const el = document.getElementById(`health-${catParam}`);
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
  }, [tab, catParam, loading]);
  useEffect(() => { loadCessionEnCours(); }, [loadCessionEnCours]);
  useEffect(() => { loadReservation(); }, [loadReservation]);
  useEffect(() => {
    if (!id || isNew) return;
    supabase.from('pension_updates').select('id').eq('animal_id', id).limit(1)
      .then(({ data }) => setHasPensionUpdates((data ?? []).length > 0));
    Promise.all([
      supabase.from('education_progression').select('id').eq('animal_id', id).limit(1),
      supabase.from('education_objectifs').select('id').eq('animal_id', id).limit(1),
      supabase.from('exercices_attribues').select('id').eq('animal_id', id).limit(1),
      supabase.from('forfaits_souscrits').select('id').eq('animal_id', id).limit(1),
      supabase.from('education_attestations').select('id').eq('animal_id', id).limit(1),
    ]).then(([r, o, e, f, at]) => setHasEducationRapports(
      (r.data ?? []).length > 0 || (o.data ?? []).length > 0 || (e.data ?? []).length > 0 || (f.data ?? []).length > 0 || (at.data ?? []).length > 0));
  }, [id, isNew]);
  useEffect(() => {
    if (!user || !isEleveur) return;
    supabase.from('user_profiles').select('nom, rue_pro, ville_pro').eq('uid', user.uid).eq('is_main', true).maybeSingle()
      .then(({ data }) => {
        if (data) {
          setNomElevage((data as {nom?:string}).nom ?? '');
          const parts = [(data as {rue_pro?:string;ville_pro?:string}).rue_pro, (data as {ville_pro?:string}).ville_pro].filter(Boolean);
          setAdresseElevage(parts.join(', '));
        }
      });
  }, [user, isEleveur]);

  useEffect(() => {
    if (!user || !isEleveur) return;
    supabase.from('animaux').select('id, nom, identification, race, photo_url, date_naissance')
      .eq('uid_eleveur', user.uid).eq('sexe', 'femelle').order('nom')
      .then(({ data }) => setMesFemelles((data ?? []) as {id:string;nom:string;identification?:string;race?:string;photo_url?:string;date_naissance?:string}[]));
    supabase.from('animaux').select('id, nom, identification, race, photo_url')
      .eq('uid_eleveur', user.uid).eq('sexe', 'male').order('nom')
      .then(({ data }) => setMesMales((data ?? []) as {id:string;nom:string;identification?:string;race?:string;photo_url?:string}[]));
  }, [user, isEleveur]);

  // ── Sauvegarde identité
  async function approveVetAcces(grantId: string) {
    setVetAccesSaving(grantId);
    try {
      await supabase.from('animal_access').update({ statut: 'active', granted_at: new Date().toISOString() }).eq('id', grantId);
      setVetAcces(prev => prev.map(g => g.id === grantId ? { ...g, statut: 'active', granted_at: new Date().toISOString() } : g));
    } finally { setVetAccesSaving(null); }
  }

  async function revokeVetAcces(grantId: string) {
    if (!confirm('Révoquer l\'accès de ce vétérinaire au carnet de santé ?')) return;
    setVetAccesSaving(grantId);
    try {
      await supabase.from('animal_access').update({ statut: 'revoked' }).eq('id', grantId);
      setVetAcces(prev => prev.filter(g => g.id !== grantId));
    } finally { setVetAccesSaving(null); }
  }

  async function saveAnimal() {
    if (!user) return;
    if (!animal.nom?.trim()) { setSaveError('Le nom est requis.'); return; }
    setSaveError(null);
    setSaving(true);
    try {
      const payload: Partial<Animal> = {
        nom: animal.nom?.trim(), nom_pedigree: animal.nom_pedigree?.trim() || undefined, espece: animal.espece,
        espece_autre: animal.espece === 'autre' ? (animal.espece_autre || undefined) : undefined,
        race: animal.race, sexe: animal.sexe,
        date_naissance: animal.date_naissance || undefined, couleur: animal.couleur,
        identification: animal.identification, sterilise: animal.sterilise,
        description: animal.description, notes: animal.notes,
        type_poil: animal.type_poil, taille: animal.taille, poids: animal.poids,
        pedigree: animal.pedigree, pedigree_lof: animal.pedigree_lof, pedigree_numero: animal.pedigree_numero,
        club_registre: animal.club_registre, pedigree_url: animal.pedigree_url,
        passeport_europeen: animal.passeport_europeen,
        nom_pere: animal.nom_pere, puce_pere: animal.puce_pere, race_pere: animal.race_pere,
        nom_mere: animal.nom_mere, puce_mere: animal.puce_mere, race_mere: animal.race_mere,
        contacts_urgence: animal.contacts_urgence,
        photo_url: animal.photo_url,
        statut: animal.statut || 'present',
        date_entree: animal.date_entree || undefined,
        provenance_qualite: animal.provenance_qualite || undefined,
        provenance_nom: animal.provenance_nom || undefined,
        provenance_adresse: animal.provenance_adresse || undefined,
        importation_ref: animal.importation_ref || undefined,
        date_naissance_mere: animal.date_naissance_mere || undefined,
        date_sortie: animal.date_sortie || undefined,
        destinataire_qualite: animal.destinataire_qualite || undefined,
        destinataire_nom: animal.destinataire_nom || undefined,
        destinataire_adresse: animal.destinataire_adresse || undefined,
        cause_mort: animal.cause_mort || undefined,
      };

      if (isNew || !id) {
        const newId = crypto.randomUUID();
        const row = {
          ...payload, id: newId,
          uid_eleveur: isEleveur ? user.uid : null,
          uid_proprietaire: !isEleveur ? user.uid : null,
          created_at: new Date().toISOString(),
        };
        const { error } = await supabase.from('animaux').insert(row);
        if (error) throw error;
        router.replace(`/mes-animaux/${newId}`);
      } else {
        // Stérilisation déclarée (false → true) alors que l'éleveur l'exige :
        // horodater et notifier l'éleveur pour qu'il valide.
        const declareSteril = !!animal.sterilise && !steriliseSavedRef.current
          && !!animal.sterilisation_requise && !animal.sterilisation_validee;
        const updatePayload: Record<string, unknown> = { ...payload, updated_at: new Date().toISOString() };
        if (declareSteril) updatePayload.sterilisation_declaree_at = new Date().toISOString();
        const { error } = await supabase.from('animaux').update(updatePayload).eq('id', id);
        if (error) throw error;
        if (declareSteril && animal.sterilisation_eleveur_uid) {
          await supabase.from('notifications').insert({
            uid:   animal.sterilisation_eleveur_uid,
            type:  'sterilisation_declaree',
            title: `✂️ Stérilisation déclarée — ${animal.nom ?? 'Animal'}`,
            body:  `Le propriétaire de ${animal.nom ?? 'l\'animal'} a déclaré la stérilisation. À valider dans le suivi des cessions.`,
            ...(animal.sterilisation_eleveur_profile_id ? { profile_id: animal.sterilisation_eleveur_profile_id } : {}),
            data:  { animalId: id, tab: 'suivi' },
            read:  false,
          });
        }
        setEditing(false);
        await loadAnimal();
      }
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : (e as { message?: string })?.message ?? 'Erreur inconnue';
      setSaveError(msg);
    } finally {
      setSaving(false);
    }
  }

  // ── Upload photo animal
  function handlePhotoChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setCropSrc(URL.createObjectURL(file));
    e.target.value = '';
  }

  async function handleCropConfirm(blob: Blob) {
    if (!user) return;
    setCropSrc(null);
    setPhotoUploading(true);
    try {
      const url = await uploadBlob(blob, `animaux/${user.uid}/${Date.now()}.jpg`);
      if (!isNew) {
        await supabase.from('animaux').update({ photo_url: url }).eq('id', id);
      }
      set('photo_url', url);
    } catch { /* ignore */ }
    finally { setPhotoUploading(false); }
  }

  function handleCropCancel() {
    if (cropSrc) URL.revokeObjectURL(cropSrc);
    setCropSrc(null);
  }

  // ── Sauvegarde registre
  async function saveRegistre() {
    if (!id) return;
    await supabase.from('animaux').update({
      statut: animal.statut, date_entree: animal.date_entree,
      provenance_qualite: animal.provenance_qualite, provenance_nom: animal.provenance_nom,
      provenance_adresse: animal.provenance_adresse,
      importation_ref: animal.importation_ref || null,
      date_naissance_mere: animal.date_naissance_mere || null,
      date_sortie: animal.date_sortie,
      destinataire_qualite: animal.destinataire_qualite, destinataire_nom: animal.destinataire_nom,
      destinataire_adresse: animal.destinataire_adresse, cause_mort: animal.cause_mort,
    }).eq('id', id);
    setShowRegistre(false);
  }

  // ── Ajout enregistrement santé
  // Répercute un acte de santé (créé, modifié) dans le registre sanitaire.
  // Une ligne existante liée à ce même enregistrement (source_table +
  // source_id) est mise à jour plutôt que dupliquée. Le site n'écrivait
  // jamais dans ce registre jusqu'ici (seule l'app le faisait, et
  // uniquement à la création) : les vaccins/soins saisis ici n'y
  // apparaissaient donc jamais, et une suppression ne nettoyait rien.
  const REGISTRE_TYPE_ACTE: Record<string,string> = {
    vaccinations: 'vaccination', vermifuges: 'vermifuge',
    antiparasitaires: 'antiparasitaire', traitements: 'traitement', visites: 'visite',
  };
  function registreDescription(table: string, data: Record<string,unknown>): string {
    switch (table) {
      case 'vaccinations': {
        const lot = String(data.lot ?? '').trim();
        return `Vaccin : ${data.vaccin}${lot ? ` (lot ${lot})` : ''}`;
      }
      case 'vermifuges': {
        const dosage = String(data.dosage ?? '').trim();
        return `${data.produit}${dosage ? ` — ${dosage}` : ''}`;
      }
      case 'antiparasitaires':
        return String(data.produit ?? '');
      case 'traitements': {
        const posologie = String(data.posologie ?? '').trim();
        return `${data.nom}${posologie ? ` — ${posologie}` : ''}`;
      }
      case 'visites': {
        const diag = String(data.diagnostic ?? '').trim();
        return diag || 'Visite vétérinaire';
      }
      default:
        return '';
    }
  }
  async function writeRegistreActe(table: string, recordId: string, data: Record<string,unknown>) {
    const typeActe = REGISTRE_TYPE_ACTE[table];
    if (!typeActe || !user || !id) return;
    const dateActe = String(data.date ?? '');
    if (!dateActe) return;
    try {
      await supabase.from('registre_sanitaire').upsert({
        uid_eleveur: user.uid,
        ...(activeProfileId ? { eleveur_profile_id: activeProfileId } : {}),
        animal_id: id,
        animal_nom: animal.nom ?? '',
        espece: animal.espece ?? '',
        date_naissance: animal.date_naissance ?? null,
        identification: animal.identification ?? '',
        sexe: animal.sexe ?? '',
        date_acte: dateActe,
        type_acte: typeActe,
        intervenant: String(data.veterinaire ?? ''),
        description: registreDescription(table, data),
        ordonnance_num: '',
        profil_source: 'eleveur',
        source_table: table,
        source_id: recordId,
      }, { onConflict: 'source_table,source_id' });
    } catch {}
  }
  async function deleteRegistreActe(table: string, recordId: string) {
    if (!REGISTRE_TYPE_ACTE[table]) return;
    try {
      await supabase.from('registre_sanitaire').delete().eq('source_table', table).eq('source_id', recordId);
    } catch {}
  }

  async function saveHealthRecord(table: string, data: Record<string,string>) {
    if (!id) return;
    setSavingHealth(true);
    const recordId = crypto.randomUUID();
    await supabase.from(table).insert({ ...data, animal_id: id, id: recordId });
    await writeRegistreActe(table, recordId, data);
    await loadHealth();
    setAddOpen(null);
    setSavingHealth(false);
  }

  // Traitement avec rappels récurrents (ex: piqûre tous les 3 jours pendant
  // 3 semaines) : transforme les champs texte du formulaire générique en
  // colonnes typées (booléen, entiers, tableau d'heures, date de fin
  // calculée) avant l'insert.
  async function saveTraitement(data: Record<string,string>) {
    if (!id) return;
    setSavingHealth(true);
    const rappelActif = data.rappel_actif === 'true';
    const payload: Record<string, unknown> = {
      animal_id: id, id: crypto.randomUUID(),
      nom: data.nom, type: data.type, description_maladie: data.description_maladie || null,
      posologie: data.posologie,
      date: data.date || null, date_fin: data.date_fin || null,
      notes: data.notes || null,
      rappel_actif: rappelActif,
    };
    if (rappelActif) {
      const frequence = parseInt(data.rappel_frequence_jours || '1', 10) || 1;
      const duree = parseInt(data.rappel_duree_jours || '7', 10) || 7;
      const heures = (data.rappel_heures || '').split(',').map(h => h.trim()).filter(Boolean);
      payload.rappel_frequence_jours = frequence;
      payload.rappel_duree_jours = duree;
      payload.rappel_heures = heures;
      if (data.date) {
        const fin = new Date(data.date);
        fin.setDate(fin.getDate() + duree);
        payload.rappel_fin = fin.toISOString().slice(0, 10);
      }
    }
    await supabase.from('traitements').insert(payload);
    await writeRegistreActe('traitements', payload.id as string, payload as Record<string,unknown>);
    await loadHealth();
    setAddOpen(null);
    setSavingHealth(false);
  }

  async function updateHealthRecord(table: string, recordId: string, data: Record<string,string>) {
    setSavingHealth(true);
    await supabase.from(table).update(data).eq('id', recordId);
    await writeRegistreActe(table, recordId, data);
    await loadHealth();
    setEditPoids(null);
    setSavingHealth(false);
  }

  async function deleteHealthRecord(table: string, recordId: string) {
    await supabase.from(table).delete().eq('id', recordId);
    await deleteRegistreActe(table, recordId);
    await loadHealth();
  }

  async function saveDocRecord(table: string, file: File, notes: string, date: string) {
    if (!id || !user) return;
    setSavingDoc(true);
    try {
      const ext = file.name.split('.').pop() ?? 'pdf';
      const path = `${table}/${user.uid}/${crypto.randomUUID()}.${ext}`;
      const url = await uploadDocToStorage(file, path);
      await supabase.from(table).insert({
        id: crypto.randomUUID(), animal_id: id, pro_uid: user.uid,
        doc_url: url, notes: notes || null, date: date || null,
      });
      await loadDocs();
      setAddDocOpen(null);
    } catch (e) { console.error(e); }
    setSavingDoc(false);
  }

  async function deleteDocRecord(table: string, recordId: string) {
    if (!confirm('Supprimer ce document ? Cette action est irréversible.')) return;
    await supabase.from(table).delete().eq('id', recordId);
    await loadDocs();
  }

  // ── Ajout repro
  async function saveRepro(table: string, data: Record<string,string>) {
    if (!id || !user) return;
    setSavingRepro(true);
    const processed: Record<string, unknown> = { ...data };
    if ('gestation_confirmee' in processed) {
      processed.gestation_confirmee = processed.gestation_confirmee === 'true';
    }
    // Les colonnes DATE n'acceptent pas '' : on convertit en null.
    for (const k of Object.keys(processed)) {
      if (processed[k] === '') processed[k] = null;
    }
    await supabase.from(table).insert({ ...processed, animal_id: id, id: crypto.randomUUID() });

    // Protocoles automatiques
    if (table === 'chaleurs' && data.date) {
      triggerAutoProtocoles({
        uid: user.uid, declencheur: 'chaleurs',
        animalId: id, dateEvenement: new Date(data.date),
        espece: animal.espece,
      }).catch(() => {});
      // Rappels agenda J-7 et J-1 pour la prochaine chaleur — miroir de
      // l'appli (_AddChaleursDialog.onSave) pour que le calendrier affiche
      // la même chose que sur mobile.
      const interval = animal.intervalle_chaleurs_jours ?? CHALEURS_INTERVAL[animal.espece ?? ''];
      if (interval) {
        const startDate = new Date(data.date);
        const nextHeat = new Date(startDate);
        nextHeat.setDate(nextHeat.getDate() + interval);
        const nomAnimal = animal.nom || 'animal';
        for (const offset of [7, 1]) {
          const rappel = new Date(nextHeat);
          rappel.setDate(rappel.getDate() - offset);
          if (rappel.getTime() > Date.now()) {
            const dateAt8 = new Date(rappel.getFullYear(), rappel.getMonth(), rappel.getDate(), 8, 0, 0);
            await supabase.from('agenda_events').insert({
              uid: user.uid,
              titre: `Chaleurs prévues J-${offset} — ${nomAnimal}`,
              type: 'medication',
              date_debut: dateAt8.toISOString(),
              ...(activeProfileId ? { pro_profile_id: activeProfileId, profile_id: activeProfileId } : {}),
            }).then(({ error }) => { if (error) console.error('agenda_events chaleurs error:', error.message); });
          }
        }
      }
    }
    if (table === 'gestations' && processed.gestation_confirmee === true && data.date_prevue) {
      triggerAutoProtocoles({
        uid: user.uid, declencheur: 'gestation',
        animalId: id, dateEvenement: new Date(data.date_prevue),
        espece: animal.espece,
      }).catch(() => {});
    }

    await loadRepro();
    setReproAdd(null);
    setSavingRepro(false);
  }

  async function deleteRepro(table: string, recordId: string) {
    await supabase.from(table).delete().eq('id', recordId);
    // La gestation supprimée peut avoir un événement "Mise-bas prévue" lié
    // dans l'agenda (agenda_events.gestation_id) : sans ce nettoyage, il
    // reste orphelin et continue de s'afficher indéfiniment.
    if (table === 'gestations') {
      await supabase.from('agenda_events').delete().eq('gestation_id', recordId);
    }
    await loadRepro();
  }

  async function updateRepro(table: string, recordId: string, data: Record<string, string>) {
    if (!id || !user) return;
    setSavingRepro(true);
    try {
      const processed: Record<string, unknown> = { ...data };
      if ('gestation_confirmee' in processed) {
        processed.gestation_confirmee = processed.gestation_confirmee === 'true';
      }
      if (typeof processed.dates === 'string') {
        try { processed.dates = JSON.parse(processed.dates as string); }
        catch { processed.dates = parseSaillieDates(processed.dates as string); }
      }
      for (const k of Object.keys(processed)) {
        if (processed[k] === '') processed[k] = null;
      }
      await supabase.from(table).update(processed).eq('id', recordId);

      // Protocoles automatiques gestation lors de la confirmation
      if (table === 'gestations' && processed.gestation_confirmee === true && data.date_prevue) {
        // Vérifier que la gestation n'était pas déjà confirmée
        const prev = gestations.find(g => g.id === recordId);
        if (!prev?.gestation_confirmee) {
          triggerAutoProtocoles({
            uid: user.uid, declencheur: 'gestation',
            animalId: id, dateEvenement: new Date(data.date_prevue),
            espece: animal.espece,
          }).catch(() => {});
        }
      }

      await loadRepro();
    } finally {
      setSavingRepro(false);
    }
  }

  async function saveSaillie(data: Record<string, string>) {
    if (!id || !user) return;
    setSavingRepro(true);
    try {
      const dates = parseSaillieDates(data.dates, data.date);
      const premiere = dates[0] ?? data.date;
      await supabase.from('saillies').insert({
        ...data, dates, date: premiere, animal_id: id, id: crypto.randomUUID(),
      });
      if (data.partenaire_animal_id) {
        await supabase.from('saillies').insert({
          id: crypto.randomUUID(),
          animal_id: data.partenaire_animal_id,
          date: premiere,
          dates,
          nom_partenaire: animal.nom ?? '',
          ident_partenaire: animal.identification ?? '',
          methode: data.methode ?? '',
          notes: data.notes ?? '',
          partenaire_animal_id: id,
        });
      }
      // A07 — Gestation automatique pour la femelle (fenêtre de mise-bas)
      if (animal.sexe === 'femelle' && premiere) {
        const gestData: Record<string, unknown> = {
          id: crypto.randomUUID(),
          animal_id: id,
          date: premiere,
          gestation_confirmee: false,
        };
        const fen = fenetreMiseBas(dates, animal.espece ?? '');
        if (fen) {
          gestData.date_prevue = fen.debut;
          gestData.date_prevue_fin = fen.fin;
        }
        await supabase.from('gestations').insert(gestData);
      }
      await loadRepro();
      setReproAdd(null);
    } finally {
      setSavingRepro(false);
    }
  }

  // ── Alerte perdue
  async function marquerRetrouve() {
    if (!alerteId) return;
    await supabase.from('alertes_perdus').update({
      statut: 'retrouve', date_retrouve: new Date().toISOString().substring(0,10)
    }).eq('id', alerteId);
    setAlerteId(null); setAlerteStatut(null);
  }

  // ── Upload document
  async function uploadDocument(file: File) {
    if (!id || !user) return;
    setUploading(true);
    try {
      const path = `documents/${user.uid}/${id}/${Date.now()}_${file.name.replace(/\s/g, '_')}`;
      const { error } = await supabase.storage.from('media').upload(path, file);
      if (error) throw error;
      const { data: { publicUrl } } = supabase.storage.from('media').getPublicUrl(path);
      const newDocs = [...(animal.documents ?? []), { nom: file.name, url: publicUrl, type: file.type, categorie: pendingDocType }];
      await supabase.from('animaux').update({ documents: newDocs }).eq('id', id);
      set('documents', newDocs);
    } catch { /* ignore */ }
    finally { setUploading(false); }
  }

  async function deleteDocument(index: number) {
    const newDocs = (animal.documents ?? []).filter((_, i) => i !== index);
    await supabase.from('animaux').update({ documents: newDocs }).eq('id', id);
    set('documents', newDocs);
  }

  // ── Export CSV
  function exportCSV() {
    const rows = [
      ['Nom', animal.nom ?? ''],
      ['Espèce', animal.espece ?? ''],
      ['Race', animal.race ?? ''],
      ['Sexe', animal.sexe ?? ''],
      ['Date de naissance', animal.date_naissance ?? ''],
      ['Couleur', animal.couleur ?? ''],
      ['Identification', animal.identification ?? ''],
      ['Stérilisé(e)', animal.sterilise ? 'Oui' : 'Non'],
      ['Passeport', animal.passeport_europeen ?? ''],
      ['Père', animal.nom_pere ?? ''],
      ['Race père', animal.race_pere ?? ''],
      ['Mère', animal.nom_mere ?? ''],
      ['Race mère', animal.race_mere ?? ''],
      ['Statut', animal.statut ?? ''],
      ['Date entrée', animal.date_entree ?? ''],
      ['Provenance', animal.provenance_nom ?? ''],
    ];
    const csv = rows.map(r => r.map(v => `"${v}"`).join(';')).join('\n');
    const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url; a.download = `${animal.nom ?? 'animal'}_fiche.csv`; a.click();
    URL.revokeObjectURL(url);
  }

  const set = (k: keyof Animal, v: unknown) => setAnimal(p => ({ ...p, [k]: v }));

  // Recherche d'un contact PetsMatch (Contacts urgence) — alternative à la
  // saisie manuelle, pas un remplacement : le contact ajouté (nom + tel)
  // reste ensuite modifiable comme n'importe quel contact saisi à la main.
  async function searchContactPetsMatch() {
    const q = contactQuery.trim();
    if (!q) return;
    setContactSearching(true);
    setContactSearchDone(false);
    try {
      const isEmail = q.includes('@');
      let rows: { firstname?: string; lastname?: string; phone_number?: string }[] = [];
      if (isEmail) {
        const { data: userRow } = await supabase.from('users').select('uid, email')
            .eq('email', q.toLowerCase()).maybeSingle();
        if (userRow) {
          const { data: cp } = await supabase.from('user_profiles')
              .select('firstname, lastname, phone_number')
              .eq('uid', userRow.uid).eq('is_main', true).maybeSingle();
          rows = cp ? [cp] : [];
        }
      } else {
        const { data } = await supabase.from('user_profiles')
            .select('firstname, lastname, phone_number')
            .or(`firstname.ilike.%${q}%,lastname.ilike.%${q}%`)
            .eq('is_main', true)
            .limit(8);
        rows = data ?? [];
      }
      setContactResults(rows.map(r => ({
        nom: `${r.firstname ?? ''} ${r.lastname ?? ''}`.trim() || 'Utilisateur PetsMatch',
        tel: r.phone_number ?? '',
      })));
    } finally {
      setContactSearching(false);
      setContactSearchDone(true);
    }
  }

  function addContactFromSearch(c: { nom: string; tel: string }) {
    set('contacts_urgence', [...(animal.contacts_urgence ?? []), c]);
    setShowContactSearch(false);
    setContactQuery('');
    setContactResults([]);
    setContactSearchDone(false);
  }

  // Suggestions dès la saisie (2 caractères), sans attendre le bouton
  // « Chercher » ou la touche Entrée.
  useEffect(() => {
    if (!showContactSearch) return;
    if (contactQuery.trim().length < 2) {
      setContactResults([]);
      setContactSearchDone(false);
      return;
    }
    const t = setTimeout(() => { searchContactPetsMatch(); }, 350);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [contactQuery, showContactSearch]);

  if (loading) {
    return <div className="flex items-center justify-center py-32"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin"/></div>;
  }

  const isAcquereur = !!user && user.uid === animal.uid_acquereur;
  // isOwner : propriétaire courant selon animaux_proprietes (source de
  // vérité, gère les cessions/transferts) — repli sur les colonnes
  // uid_eleveur/uid_proprietaire/uid_acquereur si l'animal n'a pas (encore)
  // de ligne animaux_proprietes (ex: anciennes fiches jamais migrées).
  const isOwner = !!user && (
    currentProprioUid != null
      ? user.uid === currentProprioUid
      : (user.uid === animal.uid_eleveur || user.uid === animal.uid_proprietaire || isAcquereur)
  );
  // canWrite : propriétaire OU employé avec write_animaux
  const canWrite = isOwner || (isEmployeOfOwner && employePerms.includes('write_animaux'));
  // canWriteSante : propriétaire OU employé avec write_sante (ou write_animaux)
  const canWriteSante = isOwner || (isEmployeOfOwner && (employePerms.includes('write_sante') || employePerms.includes('write_animaux')));
  // isCede du point de vue de l'éleveur original (pas de l'acquéreur qui a les droits d'écriture)
  const isCede = (animal.statut === 'sorti' || animal.statut === 'decede') && !isAcquereur;
  const isOriginalBreeder = isEleveur && !!user && user.uid === animal.uid_eleveur;
  // Animal cédé vu par l'éleveur d'origine → lecture seule, juste Identité
  const tabs = (isCede && isOriginalBreeder && !isAcquereur)
    ? [{ key:'identite', label:'Identité' }, { key:'documents', label:'Documents' }]
    : (isEleveur || isEmployeOfOwner)
    ? [{ key:'identite', label:'Identité' }, { key:'sante', label:'Carnet Santé' }, { key:'repro', label:'Suivi Repro' }, { key:'alimentation', label:'Alimentation' }, { key:'consultations', label:'Consultations vét.' }, { key:'documents', label:'Documents' }]
    : [
        { key:'identite', label:'Identité' },
        { key:'sante', label:'Carnet de santé' },
        { key:'alimentation', label:'Alimentation' },
        { key:'consultations', label:'Consultations vét.' },
        { key:'documents', label:'Documents' },
        ...(hasEducationRapports ? [{ key:'education', label:'Éducation' }] : []),
        ...(hasPensionUpdates ? [{ key:'pension', label:'Pension & Garde' }] : []),
      ];

  const isMale = (animal.sexe ?? '').toLowerCase().startsWith('m');
  const showPoil = ['chien','chat'].includes(animal.espece ?? '');
  const showTaille = animal.espece !== 'oiseau';

  return (
    <div className="max-w-3xl mx-auto px-4 py-6">
      {/* Header */}
      <div className="flex items-center gap-3 mb-6">
        <button type="button" onClick={() => router.back()} className="text-gray-400 hover:text-gray-600 text-2xl">←</button>
        <div className="flex-1 min-w-0">
          <h1 className="text-xl font-bold text-[#1F2A2E] truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
            {isNew ? 'Nouvel animal' : (animal.nom ?? 'Sans nom')}
          </h1>
          {!isNew && (
            <p className="text-sm text-gray-500">
              {[animal.espece && ESPECE_EMOJI[animal.espece], animal.race || (animal.espece === 'autre' ? animal.espece_autre : animal.espece) || animal.espece, animal.date_naissance && age(animal.date_naissance)].filter(Boolean).join(' · ')}
            </p>
          )}
        </div>
        {!isNew && !editing && (
          <div className="flex items-center gap-2">
            <button onClick={() => window.print()} title="Imprimer"
              className="w-8 h-8 rounded-full bg-gray-100 hover:bg-gray-200 flex items-center justify-center text-gray-500 text-sm transition-colors">
              🖨️
            </button>
            <button onClick={exportCSV} title="Exporter CSV"
              className="w-8 h-8 rounded-full bg-gray-100 hover:bg-gray-200 flex items-center justify-center text-gray-500 text-sm transition-colors">
              📊
            </button>
            {isOwner && !isCede && animal.statut === 'present' && (
              <button onClick={() => setShowReservation(true)}
                className="text-sm text-amber-700 font-semibold border border-amber-300 rounded-full px-3 py-1.5 hover:bg-amber-50 transition-colors">
                🔖 Réserver
              </button>
            )}
            {isOwner && animal.statut === 'reserve' && (
              <button onClick={annulerReservation} disabled={cancelingReservation}
                className="text-sm text-gray-500 font-semibold border border-gray-200 rounded-full px-3 py-1.5 hover:bg-gray-50 disabled:opacity-50 transition-colors">
                {cancelingReservation ? '…' : 'Annuler la réservation'}
              </button>
            )}
            {isOwner && !isCede && animal.statut !== 'cession_en_cours' && (
              <button onClick={() => setShowCession(true)}
                className="text-sm text-amber-700 font-semibold border border-amber-300 rounded-full px-3 py-1.5 hover:bg-amber-50 transition-colors">
                🤝 Céder
              </button>
            )}
            {canWrite && !isCede && animal.statut !== 'cession_en_cours' && (
              <button onClick={() => setEditing(true)}
                className="text-sm text-[#0C5C6C] font-semibold border border-[#0C5C6C]/30 rounded-full px-3 py-1.5 hover:bg-[#0C5C6C]/5">
                Modifier
              </button>
            )}
            {(isEleveur || isEmployeOfOwner) && !canWrite && !isCede && (
              <span className="text-xs text-gray-400 border border-gray-200 rounded-full px-3 py-1.5">
                Lecture seule
              </span>
            )}
          </div>
        )}
        {editing && (
          <button onClick={saveAnimal} disabled={saving}
            className="text-sm bg-[#6E9E57] hover:bg-[#5A8A45] text-white font-semibold rounded-full px-4 py-1.5 disabled:opacity-50">
            {saving ? '…' : 'Enregistrer'}
          </button>
        )}
      </div>
      {saveError && (
        <div className="mb-4 px-4 py-3 bg-red-50 border border-red-200 rounded-xl text-sm text-red-700">
          {saveError}
        </div>
      )}

      {/* Bannière cession EN COURS — acquéreur (lecture seule, doit signer) */}
      {animal.statut === 'cession_en_cours' && isAcquereur && cessionEnCours && (() => {
        const hasSigned = cessionEnCours.statut === 'signe_acquereur' || cessionEnCours.statut === 'confirme';
        const token = cessionEnCours.token as string | undefined;
        const signingUrl = token ? `/signer-cession/${token}` : null;
        const prix = cessionEnCours.prix as number | null;
        const dateC = cessionEnCours.date_cession as string | undefined;
        const contratUrl  = cessionEnCours.contrat_url    as string | null;
        const certifUrl   = cessionEnCours.certificat_url as string | null;
        return (
          <div className="mb-4 bg-blue-50 border border-blue-300 rounded-2xl p-4 space-y-3">
            <div className="flex items-start gap-3">
              <span className="text-2xl">📦</span>
              <div className="flex-1 min-w-0">
                <p className="text-sm font-bold text-blue-800" style={{ fontFamily:'Galey,sans-serif' }}>
                  Animal en cours de transfert vers vous
                </p>
                <p className="text-xs text-blue-700 mt-0.5">
                  Signez les documents et validez le paiement pour finaliser la cession. La fiche est en lecture seule jusqu'à confirmation.
                </p>
                {(dateC || prix) && (
                  <p className="text-xs text-blue-600 mt-1">
                    {dateC && <>Date prévue : <strong>{new Date(dateC).toLocaleDateString('fr-FR')}</strong></>}
                    {dateC && prix ? ' · ' : ''}
                    {prix && prix > 0 && <>Prix : <strong>{prix} €</strong></>}
                  </p>
                )}
                {/* Statut documents */}
                <div className="flex gap-3 mt-2 text-xs">
                  <span className={contratUrl ? 'text-green-600' : 'text-orange-500'}>
                    {contratUrl ? '✅' : '○'} Contrat
                  </span>
                  <span className={certifUrl ? 'text-green-600' : 'text-orange-500'}>
                    {certifUrl ? '✅' : '○'} Certificat
                  </span>
                </div>
              </div>
            </div>
            {!hasSigned && signingUrl && (
              <a href={signingUrl}
                className="block w-full text-center text-sm font-semibold text-white bg-blue-600 hover:bg-blue-700 rounded-xl py-2.5 transition-colors">
                ✍️ Signer les documents
              </a>
            )}
            {hasSigned && (
              <div className="flex items-center gap-2 text-xs text-green-700 font-semibold bg-green-50 rounded-xl px-3 py-2">
                <span>✅</span>
                <span>Documents signés — en attente de confirmation du vendeur.</span>
              </div>
            )}
          </div>
        );
      })()}

      {/* Bannière réservation active */}
      {animal.statut === 'reserve' && reservation && (
        <div className="mb-4 bg-amber-50 border border-amber-300 rounded-2xl p-4">
          <div className="flex items-start gap-3">
            <span className="text-2xl">🔖</span>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-bold text-amber-800" style={{ fontFamily:'Galey,sans-serif' }}>
                Réservé pour {reservation.nom as string}
              </p>
              <p className="text-xs text-amber-700 mt-0.5">
                {[reservation.email, reservation.tel].filter(Boolean).join(' · ')}
                {reservation.date_reservation ? ` · réservé le ${new Date(reservation.date_reservation as string).toLocaleDateString('fr-FR')}` : ''}
              </p>
              <p className="text-xs text-amber-600 mt-2">
                Les infos seront préremplies quand vous cliquerez sur « 🤝 Céder ».
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Bannière cession EN COURS — cédant (peut confirmer / révoquer) */}
      {animal.statut === 'cession_en_cours' && !isAcquereur && (
        <div className="mb-4 bg-amber-50 border border-amber-300 rounded-2xl p-4">
          <div className="flex items-start gap-3">
            <span className="text-2xl">⏳</span>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-bold text-amber-800" style={{ fontFamily:'Galey,sans-serif' }}>
                Cession en attente de confirmation
              </p>
              {cessionEnCours && (
                <p className="text-xs text-amber-700 mt-0.5">
                  Acquéreur : <strong>{cessionEnCours.nom_acquereur as string}</strong>
                  {cessionEnCours.email_acquereur ? ` · ${cessionEnCours.email_acquereur}` : ''}
                  {cessionEnCours.statut === 'signe_acquereur'
                    ? ' · ✍️ Signé par l\'acquéreur'
                    : ' · En attente de signature acquéreur'}
                </p>
              )}
              <div className="flex gap-2 mt-3 flex-wrap">
                <button
                  onClick={confirmerCession}
                  disabled={confirmingCession || revokingCession}
                  className="text-xs font-semibold bg-[#6E9E57] hover:bg-[#5a8a45] text-white px-3 py-1.5 rounded-lg transition-colors disabled:opacity-50">
                  {confirmingCession ? '…' : '✅ Confirmer le transfert'}
                </button>
                <button
                  onClick={revoquerCession}
                  disabled={confirmingCession || revokingCession}
                  className="text-xs font-semibold border border-red-300 text-red-600 hover:bg-red-50 px-3 py-1.5 rounded-lg transition-colors disabled:opacity-50">
                  {revokingCession ? '…' : '✕ Révoquer'}
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Bannière condition de stérilisation — vue propriétaire / acquéreur */}
      {isAcquereur && animal.sterilisation_requise && !animal.sterilise && !animal.sterilisation_validee && (() => {
        const ech = animal.sterilisation_echeance ? new Date(animal.sterilisation_echeance) : null;
        const enRetard = !!ech && ech < new Date(new Date().toDateString());
        return (
          <div className={`mb-4 rounded-2xl p-4 border ${enRetard ? 'bg-red-50 border-red-200' : 'bg-orange-50 border-orange-200'}`}>
            <div className="flex items-start gap-3">
              <span className="text-2xl">✂️</span>
              <div className="flex-1">
                <p className={`text-sm font-bold ${enRetard ? 'text-red-800' : 'text-orange-900'}`} style={{ fontFamily:'Galey,sans-serif' }}>
                  {enRetard ? 'Stérilisation en retard' : 'Stérilisation à réaliser'}
                </p>
                <p className={`text-xs mt-0.5 ${enRetard ? 'text-red-700' : 'text-orange-800'}`}>
                  L&apos;éleveur demande la stérilisation de {animal.nom ?? 'cet animal'}
                  {ech ? ` avant le ${ech.toLocaleDateString('fr-FR')}` : ''}. Modifiez la fiche et activez « Stérilisé(e) » une fois faite pour qu&apos;il valide.
                </p>
              </div>
            </div>
          </div>
        );
      })()}

      {/* Bannière cession TERMINÉE */}
      {isCede && animal.date_sortie && (
        <div className="mb-4 bg-blue-50 border border-blue-200 rounded-2xl p-4">
          <div className="flex items-start gap-3">
            <span className="text-2xl">🤝</span>
            <div className="flex-1">
              <p className="text-sm font-bold text-blue-800" style={{ fontFamily:'Galey,sans-serif' }}>
                Animal {animal.statut === 'decede' ? 'décédé' : 'cédé'} le {new Date(animal.date_sortie).toLocaleDateString('fr-FR')}
              </p>
              {animal.destinataire_nom && (
                <p className="text-xs text-blue-600 mt-0.5">
                  Acquéreur : {animal.destinataire_nom}
                  {animal.destinataire_adresse ? ` · ${animal.destinataire_adresse}` : ''}
                </p>
              )}
              {animal.cession_prix && <p className="text-xs text-blue-600">Prix : {animal.cession_prix} €</p>}
              <div className="flex gap-2 mt-2 flex-wrap">
                {animal.cession_certificat_url && (
                  <a href={animal.cession_certificat_url} target="_blank" rel="noopener"
                    className="text-xs font-semibold text-blue-700 border border-blue-300 px-2.5 py-1 rounded-lg hover:bg-blue-100 transition-colors">
                    📜 Certificat de cession
                  </a>
                )}
                {animal.cession_contrat_url && (
                  <a href={animal.cession_contrat_url} target="_blank" rel="noopener"
                    className="text-xs font-semibold text-blue-700 border border-blue-300 px-2.5 py-1 rounded-lg hover:bg-blue-100 transition-colors">
                    🤝 Contrat de vente
                  </a>
                )}
                {animal.uid_acquereur && (
                  <span className="text-xs font-semibold text-blue-700 bg-blue-100 px-2.5 py-1 rounded-lg">
                    ✓ Acquéreur sur PetsMatch
                  </span>
                )}
              </div>
              {animal.cession_notes && <p className="text-xs text-blue-500 mt-1 italic">{animal.cession_notes}</p>}
            </div>
          </div>
        </div>
      )}

      {/* Tabs */}
      <div className="overflow-x-auto mb-6 -mx-4 px-4">
        <div className="flex gap-1 bg-gray-100 rounded-xl p-1 min-w-max">
          {tabs.map(t => (
            <button key={t.key} onClick={() => setTab(t.key as typeof tab)}
              className={`whitespace-nowrap px-4 py-2 text-sm font-semibold rounded-lg transition-all ${
                tab === t.key ? 'bg-white text-[#0C5C6C] shadow-sm' : 'text-gray-500 hover:text-gray-700'
              }`}
              style={{ fontFamily: 'Galey, sans-serif' }}>
              {t.label}
            </button>
          ))}
        </div>
      </div>

      {/* ── TAB IDENTITÉ ──────────────────────────────────────────────────── */}
      {tab === 'identite' && (
        <div className="space-y-4">
          {/* Photo */}
          <div className="flex justify-center">
            <label className={`w-28 h-28 rounded-2xl overflow-hidden bg-[#EEF5EA] flex items-center justify-center relative ${editing ? 'cursor-pointer' : ''}`}>
              {animal.photo_url ? (
                <img src={animal.photo_url} alt="" className="w-full h-full object-cover"/>
              ) : (
                <span className="text-5xl">{ESPECE_EMOJI[animal.espece ?? ''] ?? '🐾'}</span>
              )}
              {editing && (
                <>
                  <div className="absolute inset-0 bg-black/30 flex items-center justify-center">
                    {photoUploading ? (
                      <div className="w-6 h-6 border-2 border-white border-t-transparent rounded-full animate-spin"/>
                    ) : (
                      <span className="text-white text-2xl">📷</span>
                    )}
                  </div>
                  <input type="file" accept="image/*" className="hidden"
                    onChange={handlePhotoChange} disabled={photoUploading} />
                </>
              )}
            </label>
          </div>

          {/* Alerte */}
          {!isNew && alerteId && alerteStatut === 'perdu' && (
            <div className="flex items-center gap-3 bg-amber-50 border border-amber-300 rounded-2xl p-4">
              <span className="text-2xl">🔍</span>
              <div className="flex-1">
                <p className="font-bold text-amber-800 text-sm">Alerte perdue active</p>
              </div>
              <button onClick={marquerRetrouve}
                className="text-xs bg-[#6E9E57] text-white font-semibold px-3 py-1.5 rounded-full hover:bg-[#5A8A45]">
                Retrouvé !
              </button>
            </div>
          )}
          {!isNew && !alerteId && (
            <Link href={`/animaux-perdus/declarer?animal=${id}`}
              className="flex items-center gap-3 border border-amber-200 rounded-2xl p-4 hover:bg-amber-50 transition-colors">
              <span className="text-2xl">🔍</span>
              <span className="text-sm font-medium text-amber-700">Déclarer perdu</span>
              <span className="ml-auto text-amber-400">›</span>
            </Link>
          )}

          {/* Identité */}
          <div className="bg-white rounded-2xl p-4 space-y-4 shadow-sm">
            <h3 className="font-bold text-[#1F2A2E] text-sm uppercase tracking-wide" style={{ fontFamily:'Galey,sans-serif' }}>Identité</h3>
            {editing ? (
              <>
                <Field label="Nom" value={animal.nom??''} onChange={v=>set('nom',v)} required />
                <Field label="Nom de pedigree / affixe" value={animal.nom_pedigree??''} onChange={v=>set('nom_pedigree',v)} />
                <SelectField label="Espèce" value={animal.espece??'chien'} onChange={v=>set('espece',v)}
                  options={ESPECES.map(e=>({ value:e, label:e.charAt(0).toUpperCase()+e.slice(1) }))} />
                {animal.espece === 'autre' && (
                  <Field label="Préciser l'espèce" value={animal.espece_autre??''} onChange={v=>set('espece_autre',v)} />
                )}
                <div>
                  <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Race</label>
                  <input list={`breeds-${id}`} value={animal.race??''} onChange={e=>set('race',e.target.value)}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30" placeholder="Sélectionner ou saisir" />
                  <datalist id={`breeds-${id}`}>{breeds.map(b => <option key={b} value={b}/>)}</datalist>
                </div>
                <div>
                  <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Sexe</label>
                  <div className="flex gap-2">
                    {['male','femelle','inconnu'].map(s => (
                      <button key={s} onClick={()=>set('sexe',s)}
                        className={`flex-1 py-2 rounded-xl border text-sm font-medium transition-colors ${animal.sexe===s ? 'bg-[#0C5C6C] border-[#0C5C6C] text-white' : 'border-gray-200 text-gray-600 hover:border-gray-300'}`}>
                        {s==='male'?'♂ Mâle':s==='femelle'?'♀ Femelle':'Inconnu'}
                      </button>
                    ))}
                  </div>
                </div>
                <Field label="Date de naissance" value={animal.date_naissance??''} onChange={v=>set('date_naissance',v)} type="date" />
                <Field label="Couleur / Robe" value={animal.couleur??''} onChange={v=>set('couleur',v)} />
                <Field label={['cheval'].includes(animal.espece??'') ? 'SIRE / Puce' : 'Identification (puce / tatouage)'} value={animal.identification??''} onChange={v=>set('identification',v)} />
                {animal.espece !== 'oiseau' && <Field label="Passeport européen n°" value={animal.passeport_europeen??''} onChange={v=>set('passeport_europeen',v)} />}
                <div className="flex items-center justify-between">
                  <span className="text-sm text-gray-700">Stérilisé(e)</span>
                  <button onClick={()=>set('sterilise',!animal.sterilise)}
                    className={`w-12 h-6 rounded-full transition-colors relative ${animal.sterilise ? 'bg-[#6E9E57]' : 'bg-gray-400'}`}>
                    <div className={`w-5 h-5 bg-white rounded-full absolute top-0.5 transition-transform ${animal.sterilise ? 'translate-x-6' : 'translate-x-0.5'}`}/>
                  </button>
                </div>
                {animal.sterilisation_requise && !animal.sterilise && (
                  <p className="text-xs text-orange-700 -mt-1">
                    Stérilisation demandée par l&apos;éleveur
                    {animal.sterilisation_echeance ? ` avant le ${fmtDate(animal.sterilisation_echeance)}` : ''}. Activez ce réglage une fois faite pour qu&apos;il valide.
                  </p>
                )}
                {showPoil && <SelectField label="Type de poil" value={animal.type_poil??''} onChange={v=>set('type_poil',v)}
                  options={[{value:'',label:'—'}, ...TYPES_POIL.map(t=>({value:t,label:t}))]} />}
                {showTaille && <Field label={animal.espece==='cheval'?'Taille au garrot (cm)':'Taille (cm)'} value={animal.taille??''} onChange={v=>set('taille',v)} />}
                {animal.espece!=='oiseau' && <Field label="Poids (kg)" value={animal.poids??''} onChange={v=>set('poids',v)} />}
                <Field label="Description" value={animal.description??''} onChange={v=>set('description',v)} rows={3} />
                <Field label="Notes" value={animal.notes??''} onChange={v=>set('notes',v)} rows={2} />
              </>
            ) : (
              <div className="space-y-2">
                {[
                  { label:'Nom', value:animal.nom },
                  { label:'Espèce', value: animal.espece === 'autre'
                      ? (animal.espece_autre || 'Autre')
                      : (animal.espece ? animal.espece.charAt(0).toUpperCase()+animal.espece.slice(1) : undefined) },
                  { label:'Race', value:animal.race },
                  { label:'Sexe', value:animal.sexe==='male'?'♂ Mâle':animal.sexe==='femelle'?'♀ Femelle':'Inconnu' },
                  { label:'Naissance', value: animal.date_naissance ? `${fmtDate(animal.date_naissance)} (${age(animal.date_naissance)})` : undefined },
                  { label:'Couleur', value:animal.couleur },
                  { label:'Identification', value:animal.identification },
                  { label:'Passeport', value:animal.passeport_europeen, show: animal.espece !== 'oiseau' },
                  { label:'Stérilisé(e)', value:animal.sterilise===true?'Oui':'Non' },
                  { label:'Type de poil', value:animal.type_poil, show: showPoil },
                  { label:'Taille', value:animal.taille ? animal.taille+' cm' : undefined, show: showTaille },
                  { label:'Poids', value:animal.poids ? animal.poids+' kg' : undefined, show: animal.espece !== 'oiseau' },
                ].filter(r=>r.show!==false).map(r=>(
                  <div key={r.label} className="flex gap-2 text-sm">
                    <span className="text-gray-400 w-28 flex-shrink-0">{r.label}</span>
                    <span className={r.value ? 'text-[#1F2A2E] font-medium' : 'text-gray-400 italic'}>
                      {r.value || 'Non renseigné'}
                    </span>
                  </div>
                ))}
                <div className="pt-2 border-t border-gray-100 space-y-1">
                  <p className="text-gray-400 text-xs font-semibold uppercase">Description</p>
                  <p className={animal.description ? 'text-sm text-gray-600' : 'text-sm text-gray-400 italic'}>
                    {animal.description || 'Non renseigné'}
                  </p>
                </div>
                <div className="space-y-1">
                  <p className="text-gray-400 text-xs font-semibold uppercase">Notes</p>
                  <p className={animal.notes ? 'text-sm text-gray-600' : 'text-sm text-gray-400 italic'}>
                    {animal.notes || 'Non renseigné'}
                  </p>
                </div>
              </div>
            )}
          </div>

          {/* Pedigree */}
          {editing && (
            <div className="bg-white rounded-2xl p-4 space-y-4 shadow-sm">
              <h3 className="font-bold text-[#1F2A2E] text-sm uppercase tracking-wide" style={{ fontFamily:'Galey,sans-serif' }}>🏅 Pedigree & Registre de race</h3>
              <div>
                <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2 block">
                  {PEDIGREE_CONFIG[animal.espece ?? '']?.label ?? 'Inscription au registre'}
                </label>
                <div className="flex flex-wrap gap-2">
                  {(PEDIGREE_CONFIG[animal.espece ?? '']?.types ?? ['Oui', 'Non']).map(t => (
                    <button key={t} type="button" onClick={() => set('pedigree_lof', t)}
                      className={`px-4 py-2 rounded-xl border text-sm font-medium transition-colors ${animal.pedigree_lof === t ? 'bg-[#0C5C6C] border-[#0C5C6C] text-white' : 'border-gray-200 text-gray-600 hover:border-gray-300'}`}>
                      {t}
                    </button>
                  ))}
                </div>
              </div>
              {animal.pedigree_lof && !animal.pedigree_lof.toLowerCase().startsWith('non') && (
                <>
                  <Field label="N° de pedigree (LOF, LOOF, SIRE…)" value={animal.pedigree_numero ?? ''} onChange={v => set('pedigree_numero', v)} />
                  <Field label="Club / Registre" value={animal.club_registre ?? ''} onChange={v => set('club_registre', v)} />
                  <div>
                    <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Document pedigree</label>
                    <div className="flex items-center gap-3">
                      <label className={`inline-flex items-center gap-2 px-4 py-2 rounded-xl border text-sm cursor-pointer transition-colors ${uploadingPedigree ? 'bg-gray-50 text-gray-400 border-gray-200' : 'border-[#0C5C6C]/40 text-[#0C5C6C] hover:bg-[#0C5C6C]/5'}`}>
                        {uploadingPedigree ? '⏳ Envoi…' : '📄 Joindre le pedigree'}
                        <input type="file" className="hidden" accept=".pdf,.jpg,.jpeg,.png,.webp" disabled={uploadingPedigree}
                          onChange={async e => {
                            const file = e.target.files?.[0]; if (!file || !user) return;
                            setUploadingPedigree(true);
                            try {
                              const path = `documents/${user.uid}/${id ?? 'new'}/${Date.now()}_pedigree.${file.name.split('.').pop()}`;
                              const { error } = await supabase.storage.from('media').upload(path, file);
                              if (!error) {
                                const { data: { publicUrl } } = supabase.storage.from('media').getPublicUrl(path);
                                set('pedigree_url', publicUrl);
                                if (!isNew && id) await supabase.from('animaux').update({ pedigree_url: publicUrl }).eq('id', id);
                              }
                            } finally { setUploadingPedigree(false); e.target.value = ''; }
                          }} />
                      </label>
                      {animal.pedigree_url && (
                        <a href={animal.pedigree_url} target="_blank" rel="noopener noreferrer"
                          className="text-xs text-[#0C5C6C] hover:underline">Voir →</a>
                      )}
                    </div>
                  </div>
                </>
              )}
            </div>
          )}
          {/* Pedigree — vue */}
          {!editing && (
            <div className="bg-white rounded-2xl p-4 space-y-2 shadow-sm">
              <h3 className="font-bold text-[#1F2A2E] text-sm uppercase tracking-wide mb-2" style={{ fontFamily:'Galey,sans-serif' }}>🏅 Pedigree & Registre</h3>
              <div className="flex gap-2 text-sm">
                <span className="text-gray-400 w-28 flex-shrink-0">Inscription</span>
                <span className={animal.pedigree_lof ? 'font-medium text-[#1F2A2E]' : 'text-gray-400 italic'}>
                  {animal.pedigree_lof || 'Non renseigné'}
                </span>
              </div>
              {animal.pedigree_numero && (
                <div className="flex gap-2 text-sm">
                  <span className="text-gray-400 w-28 flex-shrink-0">N° pedigree</span>
                  <span className="font-medium text-[#1F2A2E]">{animal.pedigree_numero}</span>
                </div>
              )}
              <div className="flex gap-2 text-sm">
                <span className="text-gray-400 w-28 flex-shrink-0">Club / Registre</span>
                <span className={animal.club_registre ? 'font-medium text-[#1F2A2E]' : 'text-gray-400 italic'}>
                  {animal.club_registre || 'Non renseigné'}
                </span>
              </div>
              {animal.pedigree_url && (
                <a href={animal.pedigree_url} target="_blank" rel="noopener noreferrer"
                  className="inline-flex items-center gap-1 text-sm text-[#0C5C6C] hover:underline">📄 Document pedigree</a>
              )}
            </div>
          )}

          {/* Généalogie (éleveur) */}
          {isEleveur && (
            <div className="bg-white rounded-2xl p-4 space-y-4 shadow-sm">
              <h3 className="font-bold text-[#1F2A2E] text-sm uppercase tracking-wide" style={{ fontFamily:'Galey,sans-serif' }}>Généalogie</h3>
              {editing ? (
                <div className="grid grid-cols-2 gap-3">
                  {mesMales.length > 0 && (
                    <div className="col-span-2 flex items-center justify-between pt-1">
                      <span className="text-xs font-semibold text-gray-400 uppercase tracking-wide">♂ Père</span>
                      <button type="button" onClick={() => setShowPerePicker(true)}
                        className="text-xs text-[#0C5C6C] font-semibold hover:text-[#094F5D]">
                        Choisir parmi mes animaux
                      </button>
                    </div>
                  )}
                  <Field label="Nom du père" value={animal.nom_pere??''} onChange={v=>set('nom_pere',v)} />
                  <Field label="Puce père" value={animal.puce_pere??''} onChange={v=>set('puce_pere',v)} />
                  {perePuceMatch && animal.nom_pere !== perePuceMatch.nom && (
                    <div className="col-span-2 flex items-center justify-between gap-2 bg-blue-50 border border-blue-100 rounded-lg px-3 py-2">
                      <span className="text-xs text-[#0C5C6C]">
                        🔗 Puce trouvée en base : <strong>{perePuceMatch.nom}</strong>{perePuceMatch.race ? ` (${perePuceMatch.race})` : ''}
                      </span>
                      <button type="button" onClick={() => {
                        set('nom_pere', perePuceMatch.nom);
                        set('race_pere', perePuceMatch.race ?? '');
                        setPerePuceMatch(null);
                      }} className="text-xs font-semibold text-[#0C5C6C] hover:underline flex-shrink-0">Rattacher</button>
                    </div>
                  )}
                  <div className="col-span-2">
                    <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Race du père</label>
                    <input list={`breeds-pere-${id}`} value={animal.race_pere??''} onChange={e=>set('race_pere',e.target.value)}
                      className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30" placeholder="Sélectionner ou saisir" />
                    <datalist id={`breeds-pere-${id}`}>{breeds.map(b => <option key={b} value={b}/>)}</datalist>
                  </div>
                  {mesFemelles.length > 0 && (
                    <div className="col-span-2 flex items-center justify-between pt-1">
                      <span className="text-xs font-semibold text-gray-400 uppercase tracking-wide">♀ Mère</span>
                      <button type="button" onClick={() => setShowMerePicker(true)}
                        className="text-xs text-[#6E9E57] font-semibold hover:text-[#5A8A45]">
                        Choisir parmi mes animaux
                      </button>
                    </div>
                  )}
                  <Field label="Nom de la mère" value={animal.nom_mere??''} onChange={v=>set('nom_mere',v)} />
                  <Field label="Puce mère" value={animal.puce_mere??''} onChange={v=>set('puce_mere',v)} />
                  {merePuceMatch && animal.nom_mere !== merePuceMatch.nom && (
                    <div className="col-span-2 flex items-center justify-between gap-2 bg-green-50 border border-green-100 rounded-lg px-3 py-2">
                      <span className="text-xs text-[#5A8A45]">
                        🔗 Puce trouvée en base : <strong>{merePuceMatch.nom}</strong>{merePuceMatch.race ? ` (${merePuceMatch.race})` : ''}
                      </span>
                      <button type="button" onClick={() => {
                        set('nom_mere', merePuceMatch.nom);
                        set('race_mere', merePuceMatch.race ?? '');
                        setMerePuceMatch(null);
                      }} className="text-xs font-semibold text-[#5A8A45] hover:underline flex-shrink-0">Rattacher</button>
                    </div>
                  )}
                  <div className="col-span-2">
                    <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Race de la mère</label>
                    <input list={`breeds-mere-${id}`} value={animal.race_mere??''} onChange={e=>set('race_mere',e.target.value)}
                      className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30" placeholder="Sélectionner ou saisir" />
                    <datalist id={`breeds-mere-${id}`}>{breeds.map(b => <option key={b} value={b}/>)}</datalist>
                  </div>
                </div>
              ) : (
                <div className="space-y-2">
                  {[
                    { label:'♂ Père', nom:animal.nom_pere, puce:animal.puce_pere, race:animal.race_pere },
                    { label:'♀ Mère', nom:animal.nom_mere, puce:animal.puce_mere, race:animal.race_mere },
                  ].map(row => (row.nom || row.puce || row.race) && (
                    <div key={row.label} className="text-sm space-y-0.5">
                      <p className="text-gray-400 text-xs font-semibold uppercase">{row.label}</p>
                      <div className="flex flex-wrap gap-3">
                        {row.nom && <span className="text-[#1F2A2E] font-medium">{row.nom}</span>}
                        {row.race && <span className="text-gray-500">{row.race}</span>}
                        {row.puce && <span className="text-gray-400 text-xs">#{row.puce}</span>}
                      </div>
                    </div>
                  ))}
                  {!animal.nom_pere && !animal.nom_mere && <p className="text-sm text-gray-400">Non renseignée</p>}
                </div>
              )}
            </div>
          )}

          {/* Contacts urgence */}
          {(
            <div className="bg-white rounded-2xl p-4 space-y-3 shadow-sm">
              <div className="flex items-center justify-between">
                <h3 className="font-bold text-[#1F2A2E] text-sm uppercase tracking-wide" style={{ fontFamily:'Galey,sans-serif' }}>Contacts urgence</h3>
                {editing && (
                  <div className="flex items-center gap-3">
                    <button onClick={()=>{ setShowContactSearch(v=>!v); setContactResults([]); setContactSearchDone(false); }}
                      className="text-xs text-[#0C5C6C] font-semibold">🔍 Rechercher</button>
                    <button onClick={()=>set('contacts_urgence', [...(animal.contacts_urgence??[]), {nom:'',tel:''}])}
                      className="text-xs text-[#0C5C6C] font-semibold">+ Ajouter</button>
                  </div>
                )}
              </div>
              {editing && showContactSearch && (
                <div className="border border-gray-200 rounded-xl p-3 space-y-2 bg-gray-50">
                  <p className="text-xs text-gray-500">Nom, prénom ou email d&apos;un utilisateur PetsMatch.</p>
                  <div className="flex gap-2">
                    <input value={contactQuery} onChange={e=>setContactQuery(e.target.value)}
                      onKeyDown={e=>{ if (e.key==='Enter') searchContactPetsMatch(); }}
                      placeholder="Nom, prénom ou email…"
                      className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white" />
                    <button onClick={searchContactPetsMatch} disabled={contactSearching}
                      className="px-3 py-2 rounded-xl bg-[#0C5C6C] text-white text-sm font-semibold disabled:opacity-50">
                      {contactSearching ? '…' : 'Chercher'}
                    </button>
                  </div>
                  {contactResults.map((r,i) => (
                    <button key={i} onClick={()=>addContactFromSearch(r)}
                      className="w-full flex items-center gap-2 border border-gray-200 rounded-xl px-3 py-2 bg-white text-left hover:bg-gray-50">
                      <span className="text-[#0C5C6C]">👤</span>
                      <span className="flex-1">
                        <span className="block text-sm font-semibold text-[#1F2A2E]">{r.nom}</span>
                        {r.tel && <span className="block text-xs text-gray-400">{r.tel}</span>}
                      </span>
                      <span className="text-gray-400">›</span>
                    </button>
                  ))}
                  {contactSearchDone && contactResults.length === 0 && (
                    <p className="text-sm text-gray-400">Aucun utilisateur trouvé.</p>
                  )}
                </div>
              )}
              {(animal.contacts_urgence ?? []).map((c,i) => (
                <div key={i} className="flex gap-2 items-center">
                  {editing ? (
                    <>
                      <input value={c.nom} onChange={e=>{
                        const arr = [...(animal.contacts_urgence??[])];
                        arr[i] = {...arr[i], nom:e.target.value};
                        set('contacts_urgence',arr);
                      }} placeholder="Nom" className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm" />
                      <input value={c.tel} onChange={e=>{
                        const arr = [...(animal.contacts_urgence??[])];
                        arr[i] = {...arr[i], tel:e.target.value};
                        set('contacts_urgence',arr);
                      }} placeholder="Téléphone" className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm" />
                      <button onClick={()=>{
                        const arr = (animal.contacts_urgence??[]).filter((_,j)=>j!==i);
                        set('contacts_urgence',arr);
                      }} className="text-red-400 hover:text-red-600 text-lg">×</button>
                    </>
                  ) : (
                    <div className="text-sm">
                      <span className="font-medium text-[#1F2A2E]">{c.nom}</span>
                      {c.tel && <a href={`tel:${c.tel}`} className="ml-2 text-[#0C5C6C] hover:underline">{c.tel}</a>}
                    </div>
                  )}
                </div>
              ))}
              {!(animal.contacts_urgence?.length) && !editing && <p className="text-sm text-gray-400">Aucun contact</p>}
            </div>
          )}

          {/* Registre Entrée/Sortie (éleveur) */}
          {isEleveur && (
            <div className="bg-white rounded-2xl shadow-sm overflow-hidden">
              <button onClick={()=>setShowRegistre(!showRegistre)}
                className="w-full flex items-center gap-3 p-4 hover:bg-gray-50 transition-colors">
                <span className="text-xl">📂</span>
                <span className="flex-1 text-left font-semibold text-sm text-[#1F2A2E]" style={{ fontFamily:'Galey,sans-serif' }}>Registre Entrée / Sortie</span>
                {!showRegistre && animal.statut && (
                  <span className={`text-xs font-semibold px-2 py-0.5 rounded-full mr-1 ${STATUT_FR[animal.statut]?.color ?? ''}`}>
                    {STATUT_FR[animal.statut]?.label}
                  </span>
                )}
                <svg className={`w-4 h-4 text-gray-400 transition-transform ${showRegistre?'rotate-180':''}`} fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7"/>
                </svg>
              </button>
              {showRegistre && (
                <div className="border-t border-gray-100 p-4 space-y-4">
                  {!editing ? (
                    /* ── Vue lecture seule ── */
                    <div className="space-y-2">
                      {(() => {
                        const st = STATUT_FR[animal.statut ?? 'present'];
                        return <span className={`inline-flex items-center px-2.5 py-1 rounded-full text-xs font-semibold ${st.color}`}>{st.label}</span>;
                      })()}
                      {[
                        { label:"Date d'entrée", value: animal.date_entree ? new Date(animal.date_entree).toLocaleDateString('fr-FR') : undefined },
                        { label:'Provenance', value: PROV_FR[animal.provenance_qualite??''] },
                        { label:'Fournisseur', value: animal.provenance_nom },
                        { label:'Adresse', value: animal.provenance_adresse },
                        { label:'Réf. import.', value: animal.importation_ref },
                        ...(animal.provenance_qualite === 'naissance' ? [
                          { label:'Mère (puce)', value: animal.puce_mere },
                          { label:'Race mère', value: animal.race_mere },
                        ] : []),
                        { label:'Naissance mère', value: animal.date_naissance_mere ? new Date(animal.date_naissance_mere).toLocaleDateString('fr-FR') : undefined },
                        ...(animal.statut==='sorti' ? [
                          { label:'Date de sortie', value: animal.date_sortie ? new Date(animal.date_sortie).toLocaleDateString('fr-FR') : undefined },
                          { label:'Destinataire', value: DEST_FR[animal.destinataire_qualite??''] },
                          { label:'Nom destinataire', value: animal.destinataire_nom },
                          { label:'Adresse dest.', value: animal.destinataire_adresse },
                        ] : []),
                        ...(animal.statut==='decede' ? [
                          { label:'Date de décès', value: animal.date_sortie ? new Date(animal.date_sortie).toLocaleDateString('fr-FR') : undefined },
                          { label:'Cause', value: MORT_FR[animal.cause_mort??''] },
                        ] : []),
                      ].filter(r=>r.value).map(r=>(
                        <div key={r.label} className="flex gap-2 text-sm">
                          <span className="text-gray-400 w-36 flex-shrink-0">{r.label}</span>
                          <span className="text-[#1F2A2E] font-medium">{r.value}</span>
                        </div>
                      ))}
                    </div>
                  ) : (
                    /* ── Mode édition ── */
                    <>
                      {/* Statut */}
                      <div>
                        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-2 block">Statut</label>
                        <div className="flex gap-2">
                          {[{v:'present',l:'Présent',c:'#6E9E57'},{v:'sorti',l:'Sorti',c:'#0C5C6C'},{v:'decede',l:'Décédé',c:'#EF4444'}].map(s=>(
                            <button key={s.v} onClick={()=>set('statut',s.v)}
                              style={animal.statut===s.v ? {backgroundColor:s.c,borderColor:s.c,color:'#fff'} : {borderColor:'#d1d5db',color:s.c}}
                              className="flex-1 py-2 rounded-xl border text-sm font-semibold transition-colors">
                              {s.l}
                            </button>
                          ))}
                        </div>
                      </div>
                      {/* Entrée */}
                      <Field label="Date d'entrée" value={animal.date_entree??''} onChange={v=>set('date_entree',v)} type="date" />
                      <SelectField label="Qualité du fournisseur" value={animal.provenance_qualite??''}
                        onChange={v => {
                          set('provenance_qualite', v);
                          if (v === 'naissance') {
                            if (!animal.provenance_nom && nomElevage) set('provenance_nom', nomElevage);
                            if (!animal.provenance_adresse && adresseElevage) set('provenance_adresse', adresseElevage);
                            if (!animal.date_entree && animal.date_naissance) set('date_entree', animal.date_naissance.substring(0, 10));
                          }
                        }}
                        options={[{value:'',label:'—'}, ...PROV_QUALITES.map(q=>({value:q,label:PROV_FR[q]??q}))]} />
                      <Field label="Nom / Élevage fournisseur" value={animal.provenance_nom??''} onChange={v=>set('provenance_nom',v)} />
                      <Field label="Adresse fournisseur" value={animal.provenance_adresse??''} onChange={v=>set('provenance_adresse',v)} />
                      {animal.provenance_qualite === 'naissance' && (animal.nom_mere || animal.puce_mere) && (
                        <div className="flex items-center gap-2 px-3 py-2 rounded-xl bg-[#F0F8EE] border border-[#A7C79A] text-sm">
                          <span className="text-[#6E9E57]">♀</span>
                          <span className="text-[#4A7A3A]">Mère : {animal.nom_mere || '—'}{animal.puce_mere ? ` · Puce ${animal.puce_mere}` : ''}</span>
                        </div>
                      )}
                      {animal.provenance_qualite === 'importation' && (
                        <Field label="Référence d'importation" value={animal.importation_ref??''} onChange={v=>set('importation_ref',v)} />
                      )}
                      <Field label="Date de naissance de la mère" value={animal.date_naissance_mere??''} onChange={v=>set('date_naissance_mere',v)} type="date" />
                      {/* Sortie */}
                      {animal.statut === 'sorti' && (
                        <>
                          <Field label="Date de sortie" value={animal.date_sortie??''} onChange={v=>set('date_sortie',v)} type="date" />
                          <SelectField label="Qualité du destinataire" value={animal.destinataire_qualite??''} onChange={v=>set('destinataire_qualite',v)}
                            options={[{value:'',label:'—'}, ...DEST_QUALITES.map(q=>({value:q,label:DEST_FR[q]??q}))]} />
                          <Field label="Nom du destinataire" value={animal.destinataire_nom??''} onChange={v=>set('destinataire_nom',v)} />
                          <Field label="Adresse destinataire" value={animal.destinataire_adresse??''} onChange={v=>set('destinataire_adresse',v)} />
                        </>
                      )}
                      {/* Décès */}
                      {animal.statut === 'decede' && (
                        <>
                          <Field label="Date de décès" value={animal.date_sortie??''} onChange={v=>set('date_sortie',v)} type="date" />
                          <SelectField label="Cause du décès" value={animal.cause_mort??''} onChange={v=>set('cause_mort',v)}
                            options={[{value:'',label:'—'}, ...CAUSES_MORT.map(c=>({value:c,label:MORT_FR[c]??c}))]} />
                        </>
                      )}
                      {!isNew && (
                        <button onClick={saveRegistre}
                          className="w-full py-2.5 bg-[#0C5C6C] hover:bg-[#094F5D] text-white text-sm font-semibold rounded-xl transition-colors">
                          Enregistrer le registre
                        </button>
                      )}
                    </>
                  )}
                  {/* ── Historique mouvements ── */}
                  <div className="pt-2 border-t border-gray-100">
                    <div className="flex items-center justify-between mb-2">
                      <span className="text-xs font-semibold text-gray-400 uppercase tracking-wide">Historique des mouvements</span>
                      <button onClick={() => setShowAddMvt(true)}
                        className="text-xs font-semibold text-[#6E9E57] hover:text-[#4A7A3A] flex items-center gap-1">
                        <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4"/></svg>
                        Ajouter
                      </button>
                    </div>
                    {mouvements.length === 0 ? (
                      <p className="text-xs text-gray-400">Aucun mouvement · utilisez &quot;Ajouter&quot; pour saillies, pensions…</p>
                    ) : (
                      <div className="space-y-2">
                        {mouvements.map(m => {
                          const isE = m.type === 'entree';
                          const motifLabels: Record<string,string> = {cession:'Cession',saillie:'Saillie',pension:'Pension / Garde',retraite:'Retraite',adoption:'Adoption',vente:'Vente',naissance:'Naissance',achat:'Achat',retour_saillie:'Retour saillie',retour_pension:'Retour pension',autre:'Autre'};
                          const provFr: Record<string,string> = {eleveur:'Éleveur',particulier:'Particulier',refuge:'Refuge',association:'Association',naissance:'Naissance',importation:'Importation',autre:'Autre'};
                          const tiers = isE ? [provFr[m.provenance_qualite??''], m.provenance_nom].filter(Boolean).join(' — ') : [provFr[m.destinataire_qualite??''], m.destinataire_nom].filter(Boolean).join(' — ');
                          return (
                            <div key={m.id} className={`flex items-start gap-2 px-3 py-2 rounded-xl text-xs ${isE ? 'bg-[#F0F8EE] border border-[#A7C79A]' : 'bg-orange-50 border border-orange-200'}`}>
                              <span className={isE ? 'text-[#6E9E57]' : 'text-orange-600'}>{isE ? '↓' : '↑'}</span>
                              <div className="flex-1 min-w-0">
                                <span className={`font-semibold ${isE ? 'text-[#4A7A3A]' : 'text-orange-700'}`}>{isE ? 'Entrée' : 'Sortie'}</span>
                                {m.motif && <span className="text-gray-500"> · {motifLabels[m.motif] ?? m.motif}</span>}
                                {tiers && <div className="text-gray-500 truncate">{tiers}</div>}
                              </div>
                              <span className="text-gray-400 whitespace-nowrap">{new Date(m.date_mouvement).toLocaleDateString('fr-FR')}</span>
                            </div>
                          );
                        })}
                      </div>
                    )}
                  </div>
                </div>
              )}
            </div>
          )}
          {/* Documents */}
          {!isNew && (
            <div className="bg-white rounded-2xl shadow-sm overflow-hidden">
              <div className="flex items-center gap-3 p-4 border-b border-gray-100">
                <span className="text-xl">📎</span>
                <span className="flex-1 font-semibold text-sm text-[#1F2A2E]" style={{ fontFamily:'Galey,sans-serif' }}>Documents</span>
                <select value={pendingDocType} onChange={e => setPendingDocType(e.target.value)}
                  className="text-xs border border-gray-200 rounded-lg px-2 py-1.5 bg-white focus:outline-none focus:border-[#0C5C6C] mr-1">
                  {DOC_TYPES.map(t => <option key={t.value} value={t.value}>{t.icon} {t.label}</option>)}
                </select>
                <label className={`text-xs font-semibold px-3 py-1.5 rounded-full cursor-pointer transition-colors ${uploading ? 'bg-gray-200 text-gray-400' : 'bg-[#0C5C6C] text-white hover:bg-[#094F5D]'}`}>
                  {uploading ? 'Envoi…' : '+ Ajouter'}
                  <input type="file" className="hidden" disabled={uploading}
                    accept=".pdf,.doc,.docx,.jpg,.jpeg,.png,.webp"
                    onChange={e => { const f = e.target.files?.[0]; if (f) uploadDocument(f); e.target.value = ''; }} />
                </label>
              </div>
              <div className="divide-y divide-gray-50">
                {(animal.documents ?? []).length === 0 && (
                  <p className="p-4 text-sm text-gray-400">Aucun document</p>
                )}
                {(animal.documents ?? []).map((doc, i) => (
                  <div key={i} className="flex items-center gap-3 px-4 py-3">
                    <span className="text-2xl flex-shrink-0">
                      {DOC_TYPES.find(t => t.value === doc.categorie)?.icon ?? (doc.type?.includes('pdf') ? '📄' : doc.type?.includes('image') ? '🖼️' : '📁')}
                    </span>
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-medium text-[#1F2A2E] truncate">{doc.nom}</p>
                      {doc.categorie && doc.categorie !== 'autre' && (
                        <p className="text-xs text-gray-400">{DOC_TYPES.find(t => t.value === doc.categorie)?.label}</p>
                      )}
                    </div>
                    <a href={doc.url} target="_blank" rel="noopener noreferrer"
                      className="text-xs text-[#0C5C6C] hover:underline mr-2">Voir</a>
                    <button onClick={() => deleteDocument(i)} className="text-red-300 hover:text-red-500 text-lg">×</button>
                  </div>
                ))}
              </div>
            </div>
          )}
        {/* ── Journal de pension ───────────────────────────────────────────── */}
        {!isNew && hasPensionUpdates && (
          <button onClick={() => setShowJournal(true)}
            className="w-full text-left rounded-2xl border border-[#6E9E57]/30 bg-[#6E9E57]/5 p-4 hover:bg-[#6E9E57]/10 transition-colors">
            <div className="flex items-center gap-2">
              <span className="text-base">📸</span>
              <p className="font-bold text-sm text-[#6E9E57]" style={{ fontFamily: 'Galey, sans-serif' }}>
                Nouvelles de la pension
              </p>
              <span className="ml-auto text-gray-400">›</span>
            </div>
          </button>
        )}
        {showJournal && (
          <PensionJournal
            animalId={id}
            animalNom={animal.nom || 'Animal'}
            readOnly
            onClose={() => setShowJournal(false)}
          />
        )}
        {/* ── Suivi de progression éducateur/comportementaliste ────────────── */}
        {!isNew && hasEducationRapports && (
          <button onClick={() => {
            setShowEducationRapports(true);
            supabase.from('education_progression').select('id, date_seance, contenu, exercices_conseilles')
              .eq('animal_id', id).order('date_seance', { ascending: false })
              .then(({ data }) => setEducationRapports(data ?? []));
          }}
            className="w-full text-left rounded-2xl border border-[#7B5EA7]/30 bg-[#7B5EA7]/5 p-4 hover:bg-[#7B5EA7]/10 transition-colors">
            <div className="flex items-center gap-2">
              <span className="text-base">🐾</span>
              <p className="font-bold text-sm text-[#7B5EA7]" style={{ fontFamily: 'Galey, sans-serif' }}>
                Suivi de progression
              </p>
              <span className="ml-auto text-gray-400">›</span>
            </div>
          </button>
        )}
        {showEducationRapports && (
          <div className="fixed inset-0 bg-black/50 z-50 flex items-end md:items-center justify-center p-4"
            onClick={() => setShowEducationRapports(false)}>
            <div className="bg-white rounded-2xl w-full max-w-lg max-h-[85vh] flex flex-col" onClick={e => e.stopPropagation()}>
              <div className="flex items-center justify-between p-5 border-b border-gray-100">
                <h3 className="font-bold font-galey text-[#7B5EA7]">Suivi — {animal.nom || 'Animal'}</h3>
                <button onClick={() => setShowEducationRapports(false)} className="text-gray-400 hover:text-gray-600 text-xl">✕</button>
              </div>
              <div className="overflow-y-auto flex-1 p-4">
                {educationRapports.length === 0 ? (
                  <p className="text-center text-gray-400 font-galey py-10">Aucun rapport de séance pour l&apos;instant</p>
                ) : (
                  <div className="space-y-3">
                    {educationRapports.map(r => (
                      <div key={r.id} className="rounded-xl border border-gray-100 p-3">
                        <p className="text-xs font-galey text-gray-400 mb-1">{r.date_seance}</p>
                        <div className="text-sm font-galey text-gray-800"><RichText value={r.contenu} /></div>
                        {r.exercices_conseilles && (
                          <div className="mt-2 bg-[#EEF5EA] rounded-lg px-2.5 py-1.5">
                            <p className="text-xs font-semibold font-galey text-[#4A7A32] mb-0.5">🏋️ Exercices conseillés</p>
                            <p className="text-xs font-galey text-[#4A7A32]">{r.exercices_conseilles}</p>
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            </div>
          </div>
        )}
        {/* ── Co-propriétaires ─────────────────────────────────────────────── */}
        {!isNew && (
          <CoproprietairesSection animalId={id} animalNom={animal.nom || 'Animal'} userUid={user?.uid} />
        )}
        {/* ── Accès vétérinaires ───────────────────────────────────────────── */}
        {!isNew && vetAcces.length > 0 && (
          <div className="rounded-2xl border border-[#26A69A]/20 bg-[#26A69A]/5 p-4">
            <div className="flex items-center gap-2 mb-3">
              <span className="text-base">🩺</span>
              <p className="font-bold text-sm text-[#26A69A]" style={{ fontFamily: 'Galey, sans-serif' }}>
                Accès vétérinaires
              </p>
            </div>
            <div className="space-y-2">
              {vetAcces.map(g => (
                <div key={g.id} className="flex items-center justify-between bg-white rounded-xl px-3 py-2 shadow-sm">
                  <div>
                    <p className="text-sm font-semibold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
                      Dr. {g.vet_nom}
                    </p>
                    <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${
                      g.statut === 'active' ? 'bg-green-100 text-green-700' : 'bg-amber-100 text-amber-700'
                    }`}>
                      {g.statut === 'active' ? 'Accès accordé' : 'En attente de validation'}
                    </span>
                  </div>
                  <div className="flex gap-2">
                    {g.statut === 'pending' && (
                      <button
                        onClick={() => approveVetAcces(g.id)}
                        disabled={vetAccesSaving === g.id}
                        className="text-xs font-semibold px-3 py-1.5 rounded-xl bg-[#26A69A] text-white hover:bg-[#1e9087] disabled:opacity-50"
                        style={{ fontFamily: 'Galey, sans-serif' }}
                      >
                        {vetAccesSaving === g.id ? '…' : '✓ Approuver'}
                      </button>
                    )}
                    {g.statut === 'active' && (
                      <button
                        onClick={() => revokeVetAcces(g.id)}
                        disabled={vetAccesSaving === g.id}
                        className="text-xs font-semibold px-3 py-1.5 rounded-xl border border-red-200 text-red-500 hover:bg-red-50 disabled:opacity-50"
                        style={{ fontFamily: 'Galey, sans-serif' }}
                      >
                        {vetAccesSaving === g.id ? '…' : 'Révoquer'}
                      </button>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}
        </div>
      )}

      {/* ── TAB CARNET DE SANTÉ ────────────────────────────────────────────── */}
      {tab === 'sante' && (
        <div className="space-y-3">
          {/* Vaccinations */}
          <HealthSection id="health-vaccinations" defaultOpen={catParam==='vaccinations'}
            title="Vaccinations" icon="💉" color="#2196F3" count={health.vaccinations.length}
            onAdd={canWriteSante ? ()=>{ setRappelPrefill(null); setAddOpen(addOpen==='vaccinations'?null:'vaccinations'); } : undefined}
            addFormOpen={addOpen==='vaccinations'}
            addForm={<AddHealthForm key={JSON.stringify(rappelPrefill)} saving={savingHealth} onCancel={()=>{ setAddOpen(null); setRappelPrefill(null); }}
              onSave={async d=>{ await saveHealthRecord('vaccinations',d); setRappelPrefill(null); }}
              initial={rappelPrefill ?? undefined}
              espece={animal.espece}
              existingCategories={health.vaccinations.map(v=>String(v.categorie??'')).filter(Boolean)}
              fields={[{key:'categorie',label:'Type de vaccin',type:'select',options:categorieOptions(animal.espece)},{key:'vaccin',label:'Vaccin (marque/produit)',required:true},{key:'date',label:'Date',type:'date'},{key:'date_validite_debut',label:'Valide à partir de',type:'date'},{key:'date_rappel',label:'Date de rappel',type:'date'},{key:'lot',label:'N° de lot'},{key:'veterinaire',label:'Vétérinaire'}]}/>}>
            {health.vaccinations.map(r=>(
              <HealthRecord key={r.id} record={r} onDelete={()=>deleteHealthRecord('vaccinations',r.id)}
                onSave={d=>updateHealthRecord('vaccinations',r.id,d)} saving={savingHealth} canWrite={canWriteSante}
                espece={animal.espece}
                existingCategories={health.vaccinations.map(v=>String(v.categorie??'')).filter(Boolean)}
                onRappel={canWriteSante ? ()=>{
                  setRappelPrefill({ vaccin: String(r.vaccin??''), veterinaire: String(r.veterinaire??''), categorie: String(r.categorie??'') });
                  setAddOpen('vaccinations');
                } : undefined}
                fields={[{key:'vaccin',label:'Vaccin',required:true},{key:'date',label:'Date',type:'date'},{key:'categorie',label:'Type de vaccin',type:'select',options:categorieOptions(animal.espece)},{key:'date_validite_debut',label:'Valide à partir de',type:'date'},{key:'date_rappel',label:'Rappel',type:'date'},{key:'lot',label:'Lot'},{key:'veterinaire',label:'Vétérinaire'}]}/>
            ))}
            {health.vaccinations.length===0 && <p className="p-4 text-sm text-gray-400">Aucune vaccination</p>}
          </HealthSection>

          {/* Vermifuges */}
          <HealthSection id="health-vermifuges" defaultOpen={catParam==='vermifuges'}
            title="Vermifuges" icon="🧪" color="#6E9E57" count={health.vermifuges.length}
            onAdd={canWriteSante ? ()=>{ setRappelPrefill(null); setAddOpen(addOpen==='vermifuges'?null:'vermifuges'); } : undefined}
            addFormOpen={addOpen==='vermifuges'}
            addForm={<AddHealthForm key={JSON.stringify(rappelPrefill)} saving={savingHealth} onCancel={()=>{ setAddOpen(null); setRappelPrefill(null); }}
              onSave={async d=>{ await saveHealthRecord('vermifuges',d); setRappelPrefill(null); }}
              initial={rappelPrefill ?? undefined}
              fields={[{key:'produit',label:'Produit',required:true},{key:'date',label:'Date',type:'date'},{key:'frequence',label:'Fréquence',type:'frequence'},{key:'date_rappel',label:'Date de rappel',type:'date'},{key:'dosage',label:'Dosage'},{key:'notes',label:'Notes'}]}/>}>
            {health.vermifuges.map(r=>(
              <HealthRecord key={r.id} record={r} onDelete={()=>deleteHealthRecord('vermifuges',r.id)}
                onSave={d=>updateHealthRecord('vermifuges',r.id,d)} saving={savingHealth} canWrite={canWriteSante}
                onRappel={canWriteSante ? ()=>{
                  setRappelPrefill({ produit: String(r.produit??''), dosage: String(r.dosage??''), frequence: String(r.frequence??'') });
                  setAddOpen('vermifuges');
                } : undefined}
                fields={[{key:'produit',label:'Produit',required:true},{key:'date',label:'Date',type:'date'},{key:'frequence',label:'Fréquence',type:'frequence'},{key:'date_rappel',label:'Rappel',type:'date'},{key:'dosage',label:'Dosage'},{key:'notes',label:'Notes'}]}/>
            ))}
            {health.vermifuges.length===0 && <p className="p-4 text-sm text-gray-400">Aucun vermifuge</p>}
          </HealthSection>

          {/* Antiparasitaires */}
          <HealthSection id="health-antiparasitaires" defaultOpen={catParam==='antiparasitaires'}
            title="Antiparasitaires" icon="🛡️" color="#5B8648" count={health.antiparasitaires.length}
            onAdd={canWriteSante ? ()=>{ setRappelPrefill(null); setAddOpen(addOpen==='antiparasitaires'?null:'antiparasitaires'); } : undefined}
            addFormOpen={addOpen==='antiparasitaires'}
            addForm={<AddHealthForm key={JSON.stringify(rappelPrefill)} saving={savingHealth} onCancel={()=>{ setAddOpen(null); setRappelPrefill(null); }}
              onSave={async d=>{ await saveHealthRecord('antiparasitaires',d); setRappelPrefill(null); }}
              initial={rappelPrefill ?? undefined}
              fields={[{key:'produit',label:'Produit',required:true},{key:'type',label:'Type (collier, pipette…)'},{key:'date',label:'Date',type:'date'},{key:'frequence',label:'Fréquence',type:'frequence'},{key:'date_rappel',label:'Date de rappel',type:'date'},{key:'notes',label:'Notes'}]}/>}>
            {health.antiparasitaires.map(r=>(
              <HealthRecord key={r.id} record={r} onDelete={()=>deleteHealthRecord('antiparasitaires',r.id)}
                onSave={d=>updateHealthRecord('antiparasitaires',r.id,d)} saving={savingHealth} canWrite={canWriteSante}
                onRappel={canWriteSante ? ()=>{
                  setRappelPrefill({ produit: String(r.produit??''), type: String(r.type??''), frequence: String(r.frequence??'') });
                  setAddOpen('antiparasitaires');
                } : undefined}
                fields={[{key:'produit',label:'Produit',required:true},{key:'type',label:'Type'},{key:'date',label:'Date',type:'date'},{key:'frequence',label:'Fréquence',type:'frequence'},{key:'date_rappel',label:'Rappel',type:'date'},{key:'notes',label:'Notes'}]}/>
            ))}
            {health.antiparasitaires.length===0 && <p className="p-4 text-sm text-gray-400">Aucun antiparasitaire</p>}
          </HealthSection>

          {/* Traitements */}
          <HealthSection id="health-traitements" defaultOpen={catParam==='traitements'}
            title="Traitements" icon="💊" color="#8D6E63" count={health.traitements.length}
            onAdd={canWriteSante ? ()=>setAddOpen(addOpen==='traitements'?null:'traitements') : undefined}
            addFormOpen={addOpen==='traitements'}
            addForm={<AddHealthForm saving={savingHealth} onCancel={()=>setAddOpen(null)}
              onSave={saveTraitement}
              fields={[{key:'nom',label:'Nom',required:true},{key:'type',label:'Type'},{key:'description_maladie',label:'Description de la maladie'},{key:'posologie',label:'Posologie'},{key:'date',label:'Date début',type:'date'},{key:'date_fin',label:'Date fin',type:'date'},
                {key:'rappel_actif',label:'Activer les rappels récurrents',type:'checkbox'},
                {key:'rappel_frequence_jours',label:'Répéter tous les X jours',type:'number'},
                {key:'rappel_duree_jours',label:'Durée du traitement (jours)',type:'number'},
                {key:'rappel_heures',label:'Heures de rappel (ex: 08:00, 20:00)'},
                {key:'notes',label:'Commentaires (ex: impressions de tolérance au traitement)'}]}/>}>
            {health.traitements.map(r=>(
              <HealthRecord key={r.id} record={r} onDelete={()=>deleteHealthRecord('traitements',r.id)}
                fields={[{key:'nom',label:'Nom'},{key:'type',label:'Type'},{key:'description_maladie',label:'Maladie'},{key:'posologie',label:'Posologie'},{key:'date',label:'Début'},{key:'date_fin',label:'Fin'},{key:'notes',label:'Commentaires'}]}/>
            ))}
            {health.traitements.length===0 && <p className="p-4 text-sm text-gray-400">Aucun traitement</p>}
          </HealthSection>

          {/* Chirurgie / Hospitalisation */}
          <HealthSection id="health-chirurgies" defaultOpen={catParam==='chirurgies'}
            title="Chirurgie / Hospitalisation" icon="🏥" color="#C2185B" count={health.chirurgies.length}
            onAdd={canWriteSante ? ()=>setAddOpen(addOpen==='chirurgies'?null:'chirurgies') : undefined}
            addFormOpen={addOpen==='chirurgies'}
            addForm={<AddHealthForm saving={savingHealth} onCancel={()=>setAddOpen(null)}
              onSave={d=>saveHealthRecord('chirurgies', { ...d, type: d.type || 'chirurgie', statut: d.statut || 'prevu' })}
              fields={[
                {key:'type',label:'Type',type:'select',options:[{value:'chirurgie',label:'Chirurgie'},{value:'hospitalisation',label:'Hospitalisation'}]},
                {key:'intitule',label:'Intervention (ex : stérilisation, détartrage sous AG)',required:true},
                {key:'date',label:'Date (prévue ou réalisée)',type:'date',required:true},
                {key:'statut',label:'Statut',type:'select',options:[{value:'prevu',label:'Prévue'},{value:'realise',label:'Réalisée'},{value:'annule',label:'Annulée'}]},
                {key:'clinique',label:'Clinique / vétérinaire'},
                {key:'protocole_preop',label:'Protocole pré-opératoire (jeûne, prémédication, anesthésie…)',type:'textarea'},
                {key:'protocole_postop',label:'Protocole post-opératoire (analgésie, soins de plaie, repos, contrôle…)',type:'textarea'},
                {key:'notes',label:'Notes'},
              ]}/>}>
            {health.chirurgies.map(r=>(
              <HealthRecord key={r.id} record={r} onDelete={()=>deleteHealthRecord('chirurgies',r.id)}
                onSave={d=>updateHealthRecord('chirurgies',r.id,d)} saving={savingHealth} canWrite={canWriteSante}
                fields={[
                  {key:'intitule',label:'Intervention',required:true},
                  {key:'type',label:'Type'},{key:'date',label:'Date',type:'date'},{key:'statut',label:'Statut'},
                  {key:'clinique',label:'Clinique / vétérinaire'},
                  {key:'protocole_preop',label:'Protocole pré-opératoire',type:'textarea'},
                  {key:'protocole_postop',label:'Protocole post-opératoire',type:'textarea'},
                  {key:'notes',label:'Notes'},
                ]}/>
            ))}
            {health.chirurgies.length===0 && <p className="p-4 text-sm text-gray-400">Aucune intervention</p>}
          </HealthSection>

          {/* Allergies */}
          <HealthSection title="Allergies" icon="⚠️" color="#E25C5C" count={health.allergies.length}
            onAdd={canWriteSante ? ()=>setAddOpen(addOpen==='allergies'?null:'allergies') : undefined}
            addFormOpen={addOpen==='allergies'}
            addForm={<AddHealthForm saving={savingHealth} onCancel={()=>setAddOpen(null)}
              onSave={d=>saveHealthRecord('allergies',d)}
              fields={[{key:'description',label:'Description',required:true},{key:'type',label:'Type'},{key:'severite',label:'Sévérité (légère/modérée/sévère)'},{key:'date',label:'Date constatée',type:'date'},{key:'notes',label:'Notes'}]}/>}>
            {health.allergies.map(r=>(
              <HealthRecord key={r.id} record={r} onDelete={()=>deleteHealthRecord('allergies',r.id)}
                onSave={d=>updateHealthRecord('allergies',r.id,d)} saving={savingHealth} canWrite={canWriteSante}
                fields={[{key:'description',label:'Description',required:true},{key:'type',label:'Type'},{key:'severite',label:'Sévérité'},{key:'date',label:'Date',type:'date'},{key:'notes',label:'Notes'}]}/>
            ))}
            {health.allergies.length===0 && <p className="p-4 text-sm text-gray-400">Aucune allergie</p>}
          </HealthSection>

          {/* Poids */}
          <HealthSection title="Courbe de poids" icon="⚖️" color="#5F9EAA" count={health.poids.length}
            onAdd={canWriteSante ? ()=>setAddOpen(addOpen==='poids'?null:'poids') : undefined}
            addFormOpen={addOpen==='poids'}
            addForm={<WeightForm saving={savingHealth} onCancel={()=>setAddOpen(null)}
              lastKg={(() => {
                const s = [...health.poids].sort((a,b)=>String(a.date??'').localeCompare(String(b.date??'')));
                return s.length ? (parseFloat(String(s[s.length-1].valeur??'0'))||null) : null;
              })()}
              onSave={d=>saveHealthRecord('poids',d)}/>}>
            {(() => {
              const sorted = [...health.poids].sort((a,b) => String(a.date??'').localeCompare(String(b.date??'')));
              const maxPoids = Math.max(...sorted.map(r => parseFloat(String(r.valeur??'0'))||0), 0.1);
              const isJuvenile = !!animal.date_naissance && (Date.now() - new Date(animal.date_naissance).getTime()) / 86400000 < 548;
              return (
                <>
                  {sorted.length >= 2 && (
                    <WeightChartSVG data={sorted as { date?: unknown; valeur?: unknown }[]} isJuvenile={isJuvenile} dateNaissance={animal.date_naissance} />
                  )}
                  {sorted.map(r => {
                    const val = parseFloat(String(r.valeur??'0'));
                    const pct = Math.round((val/maxPoids)*100);
                    const isEditing = editPoids === r.id;
                    return (
                      <div key={r.id} className="px-4 py-3 border-b border-gray-50 last:border-0">
                        {isEditing ? (
                          <WeightForm saving={savingHealth} onCancel={()=>setEditPoids(null)}
                            onSave={d=>updateHealthRecord('poids',r.id,d)}
                            initial={{ valeur: String(r.valeur??''), date: String(r.date??''), notes: String(r.notes??'') }}/>
                        ) : (
                          <>
                            <div className="flex items-center gap-2 mb-1">
                              <span className="font-semibold text-sm text-[#5F9EAA]">{poidsLabel(val)}</span>
                              <span className="text-xs text-gray-400 flex-1">{fmtDate(String(r.date??''))}</span>
                              <button onClick={()=>setEditPoids(r.id)} className="text-xs text-[#0C5C6C] hover:text-[#094F5D] font-medium px-1">✏️</button>
                              <button onClick={()=>deleteHealthRecord('poids',r.id)} className="text-xs text-red-400 hover:text-red-600">×</button>
                            </div>
                            <div className="h-1.5 bg-gray-100 rounded-full overflow-hidden">
                              <div className="h-full rounded-full transition-all" style={{ width:`${pct}%`, backgroundColor:'#5F9EAA' }}/>
                            </div>
                            {!!r.notes && <p className="text-xs text-gray-400 mt-1">{String(r.notes)}</p>}
                          </>
                        )}
                      </div>
                    );
                  })}
                </>
              );
            })()}
            {health.poids.length===0 && <p className="p-4 text-sm text-gray-400">Aucune mesure</p>}
          </HealthSection>

          {/* Visites vétérinaires */}
          <HealthSection title="Visites vétérinaires" icon="🏥" color="#26A69A" count={health.visites.length}
            onAdd={canWriteSante ? ()=>setAddOpen(addOpen==='visites'?null:'visites') : undefined}
            addFormOpen={addOpen==='visites'}
            addForm={<AddHealthForm saving={savingHealth} onCancel={()=>setAddOpen(null)}
              onSave={d=>saveHealthRecord('visites',d)}
              fields={[{key:'motif',label:'Motif',required:true},{key:'date',label:'Date',type:'date'},{key:'veterinaire',label:'Vétérinaire'},{key:'diagnostic',label:'Diagnostic'},{key:'notes',label:'Notes'}]}/>}>
            {health.visites.map(r=>(
              <HealthRecord key={r.id} record={r} onDelete={()=>deleteHealthRecord('visites',r.id)}
                onSave={d=>updateHealthRecord('visites',r.id,d)} saving={savingHealth} canWrite={canWriteSante}
                fields={[{key:'motif',label:'Motif',required:true},{key:'date',label:'Date',type:'date'},{key:'veterinaire',label:'Vétérinaire'},{key:'diagnostic',label:'Diagnostic'},{key:'notes',label:'Notes'}]}/>
            ))}
            {health.visites.length===0 && <p className="p-4 text-sm text-gray-400">Aucune visite</p>}
          </HealthSection>

          {/* Ordonnances */}
          <HealthSection title="Ordonnances" icon="📋" color="#7B5EA7" count={ordonnances.length}
            onAdd={()=>setAddDocOpen(addDocOpen==='ordonnances'?null:'ordonnances')}
            addFormOpen={addDocOpen==='ordonnances'}
            addForm={<DocUploadForm saving={savingDoc} onCancel={()=>setAddDocOpen(null)}
              onSave={(f,n,d)=>saveDocRecord('ordonnances',f,n,d)}/>}>
            {ordonnances.map(r=>(
              <DocCard key={r.id} record={r} onDelete={()=>deleteDocRecord('ordonnances',r.id as string)}/>
            ))}
            {ordonnances.length===0 && <p className="p-4 text-sm text-gray-400">Aucune ordonnance</p>}
          </HealthSection>

          {/* Radios / Imagerie */}
          <HealthSection title="Radios / Imagerie" icon="🩻" color="#546E7A" count={radios.length}
            onAdd={()=>setAddDocOpen(addDocOpen==='radios'?null:'radios')}
            addFormOpen={addDocOpen==='radios'}
            addForm={<DocUploadForm saving={savingDoc} onCancel={()=>setAddDocOpen(null)}
              onSave={(f,n,d)=>saveDocRecord('radios',f,n,d)}/>}>
            {radios.map(r=>(
              <DocCard key={r.id} record={r} onDelete={()=>deleteDocRecord('radios',r.id as string)}/>
            ))}
            {radios.length===0 && <p className="p-4 text-sm text-gray-400">Aucune radio / image</p>}
          </HealthSection>

          {/* Comptes rendus */}
          <HealthSection title="Comptes rendus" icon="📄" color="#5F9EAA" count={crs.length}
            onAdd={()=>setAddDocOpen(addDocOpen==='comptes_rendus'?null:'comptes_rendus')}
            addFormOpen={addDocOpen==='comptes_rendus'}
            addForm={<DocUploadForm saving={savingDoc} onCancel={()=>setAddDocOpen(null)}
              onSave={(f,n,d)=>saveDocRecord('comptes_rendus',f,n,d)}/>}>
            {crs.map(r=>(
              <DocCard key={r.id} record={r} onDelete={()=>deleteDocRecord('comptes_rendus',r.id as string)}/>
            ))}
            {crs.length===0 && <p className="p-4 text-sm text-gray-400">Aucun compte rendu</p>}
          </HealthSection>
        </div>
      )}

      {/* ── TAB SUIVI REPRO (éleveur + employé avec accès repro) ────────── */}
      {tab === 'repro' && (isEleveur || isEmployeOfOwner) && (
        <SuiviReproTab
          isMale={isMale}
          espece={animal.espece ?? 'chien'}
          animalId={id ?? ''}
          userId={user?.uid ?? ''}
          animalNom={animal.nom ?? ''}
          animalIdent={animal.identification ?? ''}
          chaleurs={chaleurs}
          saillies={saillies}
          gestations={gestations}
          reproAdd={reproAdd}
          setReproAdd={setReproAdd}
          savingRepro={savingRepro}
          saveRepro={saveRepro}
          saveSaillie={saveSaillie}
          updateRepro={updateRepro}
          deleteRepro={deleteRepro}
          intervalleCustom={animal.intervalle_chaleurs_jours ?? null}
          onSaveIntervalleCustom={async (val) => {
            await supabase.from('animaux').update({ intervalle_chaleurs_jours: val }).eq('id', id ?? '');
            setAnimal(prev => ({ ...prev, intervalle_chaleurs_jours: val }));
          }}
          readOnly={isEmployeOfOwner && !employePerms.includes('write_repro')}
        />
      )}

      {/* ── TAB CONSULTATIONS VÉTÉRINAIRES ───────────────────────────────── */}
      {tab === 'consultations' && !isNew && (
        <div className="space-y-4">
          <ConsultationsVetTab crs={crs} ordonnances={ordonnances} vetNames={vetNames} />
          <AnatomieOwnerSection animalId={id ?? ''} espece={animal.espece ?? ''} />
        </div>
      )}

      {tab === 'alimentation' && !isNew && (
        <AlimentationTab
          animalId={id ?? ''}
          espece={animal.espece ?? 'chien'}
          sexe={animal.sexe ?? 'male'}
          sterilise={animal.sterilise ?? false}
          dateNaissance={animal.date_naissance}
          nom={animal.nom}
          userId={user?.uid ?? ''}
          poidsFiche={animal.poids}
        />
      )}

      {/* ── TAB DOCUMENTS ───────────────────────────────────────────────── */}
      {tab === 'documents' && !isNew && (
        <DocumentsAnimalTab animalId={id ?? ''} />
      )}

      {tab === 'education' && !isNew && (
        <EducationRapportsTab animalId={id ?? ''} />
      )}

      {tab === 'pension' && !isNew && (
        <PensionJournalTab animalId={id ?? ''} animalNom={animal.nom || 'Animal'} />
      )}

      {showPerePicker && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-4"
          onClick={() => { setShowPerePicker(false); setPereSearch(''); }}>
          <div className="bg-white rounded-2xl w-full max-w-md max-h-[70vh] overflow-hidden shadow-2xl"
            onClick={e => e.stopPropagation()}>
            <div className="p-4 border-b border-gray-100">
              <h3 className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Choisir le père</h3>
            </div>
            <div className="p-3 border-b border-gray-100">
              <input type="text" autoFocus value={pereSearch} onChange={e => setPereSearch(e.target.value)}
                placeholder="Rechercher par nom…"
                className="w-full border border-gray-200 rounded-lg px-3 py-1.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
            </div>
            <div className="overflow-y-auto max-h-[55vh]">
              {mesMales
                .filter(m => m.nom?.toLowerCase().includes(pereSearch.trim().toLowerCase()))
                .map(m => (
                <button key={m.id} type="button"
                  onClick={() => {
                    set('nom_pere', m.nom);
                    set('puce_pere', m.identification ?? '');
                    set('race_pere', m.race ?? '');
                    setShowPerePicker(false);
                    setPereSearch('');
                  }}
                  className="w-full flex items-center gap-3 px-4 py-3 hover:bg-blue-50 transition-colors text-left border-b border-gray-50">
                  <div className="w-10 h-10 rounded-xl overflow-hidden bg-blue-50 flex-shrink-0 flex items-center justify-center">
                    {m.photo_url
                      ? <img src={m.photo_url} alt="" className="w-full h-full object-cover" />
                      : <span className="text-lg">♂</span>}
                  </div>
                  <div>
                    <p className="font-semibold text-sm text-[#1F2A2E]">{m.nom}</p>
                    <p className="text-xs text-gray-400">{[m.race, m.identification ? `#${m.identification}` : null].filter(Boolean).join(' · ')}</p>
                  </div>
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {showMerePicker && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-4"
          onClick={() => { setShowMerePicker(false); setMereSearch(''); }}>
          <div className="bg-white rounded-2xl w-full max-w-md max-h-[70vh] overflow-hidden shadow-2xl"
            onClick={e => e.stopPropagation()}>
            <div className="p-4 border-b border-gray-100">
              <h3 className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Choisir la mère</h3>
            </div>
            <div className="p-3 border-b border-gray-100">
              <input type="text" autoFocus value={mereSearch} onChange={e => setMereSearch(e.target.value)}
                placeholder="Rechercher par nom…"
                className="w-full border border-gray-200 rounded-lg px-3 py-1.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
            </div>
            <div className="overflow-y-auto max-h-[55vh]">
              {mesFemelles
                .filter(f => f.nom?.toLowerCase().includes(mereSearch.trim().toLowerCase()))
                .map(f => (
                <button key={f.id} type="button"
                  onClick={() => {
                    set('nom_mere', f.nom);
                    set('puce_mere', f.identification ?? '');
                    set('race_mere', f.race ?? '');
                    if (f.date_naissance) set('date_naissance_mere', f.date_naissance.substring(0, 10));
                    setShowMerePicker(false);
                    setMereSearch('');
                  }}
                  className="w-full flex items-center gap-3 px-4 py-3 hover:bg-[#F0F8EE] transition-colors text-left border-b border-gray-50">
                  <div className="w-10 h-10 rounded-xl overflow-hidden bg-[#EEF5EA] flex-shrink-0 flex items-center justify-center">
                    {f.photo_url
                      ? <img src={f.photo_url} alt="" className="w-full h-full object-cover" />
                      : <span className="text-lg">♀</span>}
                  </div>
                  <div>
                    <p className="font-semibold text-sm text-[#1F2A2E]">{f.nom}</p>
                    <p className="text-xs text-gray-400">{[f.race, f.identification ? `#${f.identification}` : null].filter(Boolean).join(' · ')}</p>
                  </div>
                </button>
              ))}
            </div>
          </div>
        </div>
      )}

      {cropSrc && (
        <ImageCropModal src={cropSrc} aspect={1} maxDim={800}
          onConfirm={handleCropConfirm} onCancel={handleCropCancel} />
      )}

      {showCession && user && (
        <CessionModal
          animal={animal}
          uid={user.uid}
          profileId={activeProfileId || null}
          eleveurInfo={{ nom: nomElevage || user.email || 'Éleveur', adresse: adresseElevage, email: user.email ?? '' }}
          reservation={animal.statut === 'reserve' ? reservation : null}
          onClose={() => setShowCession(false)}
          onCeded={() => { setShowCession(false); setReservation(null); loadAnimal(); }}
        />
      )}

      {showReservation && user && (
        <ReservationModal
          animal={animal}
          uid={user.uid}
          profileId={activeProfileId || null}
          onClose={() => setShowReservation(false)}
          onReserved={() => { setShowReservation(false); loadAnimal(); loadReservation(); }}
        />
      )}

      {showAddMvt && user && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4" onClick={() => setShowAddMvt(false)}>
          <div className="bg-white rounded-2xl w-full max-w-md" onClick={e => e.stopPropagation()}>
            <div className="p-5 space-y-3">
              <h3 className="font-bold text-[#1F2A2E] text-base" style={{fontFamily:'Galey,sans-serif'}}>Ajouter un mouvement</h3>
              <div className="flex gap-2">
                {[['entree','Entrée'],['sortie','Sortie']].map(([v,l])=>(
                  <button key={v} onClick={()=>setMvtForm(f=>({...f,type:v,motif:''}))}
                    className={`flex-1 py-2 rounded-xl text-sm font-semibold border-2 transition-colors ${mvtForm.type===v?'bg-[#0C5C6C] border-[#0C5C6C] text-white':'border-gray-200 text-gray-600'}`}>{l}</button>
                ))}
              </div>
              <input type="date" value={mvtForm.date} onChange={e=>setMvtForm(f=>({...f,date:e.target.value}))}
                className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              <select value={mvtForm.motif} onChange={e=>setMvtForm(f=>({...f,motif:e.target.value}))}
                className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white">
                <option value="">Motif (optionnel)</option>
                {(mvtForm.type==='entree'?[['naissance','Naissance'],['achat','Achat'],['cession','Cession'],['retour_saillie','Retour saillie'],['retour_pension','Retour pension'],['autre','Autre']]:[['cession','Cession'],['saillie','Saillie'],['pension','Pension / Garde'],['retraite','Retraite'],['adoption','Adoption'],['vente','Vente'],['autre','Autre']]).map(([v,l])=>(
                  <option key={v} value={v}>{l}</option>
                ))}
              </select>
              {mvtForm.type==='entree' ? (
                <>
                  <select value={mvtForm.provQualite} onChange={e=>setMvtForm(f=>({...f,provQualite:e.target.value}))}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white">
                    <option value="">Qualité fournisseur</option>
                    {[['eleveur','Éleveur'],['particulier','Particulier'],['refuge','Refuge'],['naissance','Naissance'],['importation','Importation'],['autre','Autre']].map(([v,l])=><option key={v} value={v}>{l}</option>)}
                  </select>
                  <input placeholder="Nom / Élevage" value={mvtForm.provNom} onChange={e=>setMvtForm(f=>({...f,provNom:e.target.value}))}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                </>
              ) : (
                <>
                  <select value={mvtForm.destQualite} onChange={e=>setMvtForm(f=>({...f,destQualite:e.target.value}))}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white">
                    <option value="">Qualité destinataire</option>
                    {[['eleveur','Éleveur'],['particulier','Particulier'],['refuge','Refuge'],['association','Association'],['autre','Autre']].map(([v,l])=><option key={v} value={v}>{l}</option>)}
                  </select>
                  <input placeholder="Nom / Élevage" value={mvtForm.destNom} onChange={e=>setMvtForm(f=>({...f,destNom:e.target.value}))}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                </>
              )}
              <input placeholder="Notes (optionnel)" value={mvtForm.notes} onChange={e=>setMvtForm(f=>({...f,notes:e.target.value}))}
                className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              <div className="flex gap-2 pt-1">
                <button disabled={savingMvt} onClick={async () => {
                  setSavingMvt(true);
                  const payload: Record<string,string> = {
                    animal_id: id as string, uid_eleveur: user.uid,
                    type: mvtForm.type, date_mouvement: mvtForm.date,
                    ...(activeProfileId ? { eleveur_profile_id: activeProfileId } : {}),
                  };
                  if (mvtForm.motif) payload.motif = mvtForm.motif;
                  if (mvtForm.type==='entree') {
                    if (mvtForm.provQualite) payload.provenance_qualite = mvtForm.provQualite;
                    if (mvtForm.provNom) payload.provenance_nom = mvtForm.provNom;
                  } else {
                    if (mvtForm.destQualite) payload.destinataire_qualite = mvtForm.destQualite;
                    if (mvtForm.destNom) payload.destinataire_nom = mvtForm.destNom;
                  }
                  if (mvtForm.notes) payload.notes = mvtForm.notes;
                  await supabase.from('registre_mouvements').insert(payload);
                  setSavingMvt(false);
                  setShowAddMvt(false);
                  setMvtForm({type:'entree',date:new Date().toISOString().slice(0,10),motif:'',provQualite:'',provNom:'',destQualite:'',destNom:'',notes:''});
                  loadMouvements();
                }}
                  className="flex-1 bg-[#0C5C6C] disabled:opacity-60 text-white font-semibold py-2.5 rounded-xl text-sm">
                  {savingMvt ? 'Enregistrement…' : 'Enregistrer'}
                </button>
                <button onClick={()=>setShowAddMvt(false)} className="flex-1 border border-gray-200 text-gray-600 font-medium py-2.5 rounded-xl text-sm">Annuler</button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
