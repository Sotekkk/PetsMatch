'use client';

import { useEffect, useState, useCallback } from 'react';
import { useParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { loadBreeds } from '@/lib/breeds';
import HealthSection from '@/components/animaux/HealthSection';
import CessionModal from '@/components/animaux/CessionModal';
import { uploadBlob, uploadDocument as uploadDocToStorage } from '@/lib/upload-media';
import ImageCropModal from '@/components/ImageCropModal';
import AlimentationTab from './AlimentationTab';
import { triggerAutoProtocoles } from '@/lib/planning-service';
import { PensionJournal } from '@/components/PensionJournal';

// ─── Types ───────────────────────────────────────────────────────────────────

interface Animal {
  id: string; nom?: string; espece?: string; race?: string; sexe?: string;
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
const STATUT_FR: Record<string,{label:string;color:string}> = { present:{label:'Présent',color:'text-green-700 bg-green-100'}, sorti:{label:'Sorti',color:'text-blue-700 bg-blue-100'}, decede:{label:'Décédé',color:'text-red-600 bg-red-100'} };

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

function fmtPoids(v: number): string {
  if (v < 1) return v.toFixed(3);
  if (v < 10) return v.toFixed(1);
  return v.toFixed(0);
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

function AddHealthForm({ fields, onSave, onCancel, saving, initial }:
  { fields: { key:string; label:string; type?:string; required?:boolean }[];
    onSave:(data:Record<string,string>)=>Promise<void>;
    onCancel:()=>void; saving:boolean; initial?: Record<string,string> }) {
  const [form, setForm] = useState<Record<string,string>>(initial ?? {});
  return (
    <div className="space-y-3">
      {fields.map(f => (
        <Field key={f.key} label={f.label} value={form[f.key]??''} required={f.required}
          type={f.type??'text'} onChange={v => setForm(p=>({...p,[f.key]:v}))} />
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

function HealthRecord({ fields, record, onDelete }:
  { fields:{key:string;label:string}[]; record:HealthRecord; onDelete:()=>void }) {
  const [open, setOpen] = useState(false);
  const mainField = fields[0];
  return (
    <div className="px-4 py-3">
      <div className="flex items-center gap-2 cursor-pointer" onClick={() => setOpen(!open)}>
        <div className="flex-1">
          <p className="text-sm font-medium text-[#1F2A2E]">{String(record[mainField.key] ?? '—')}</p>
          {fields[1] && <p className="text-xs text-gray-400">{fmtDate(record[fields[1].key] as string)}</p>}
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
              <span className="text-gray-700">{f.key.includes('date') ? fmtDate(record[f.key] as string) : String(record[f.key])}</span>
            </div>
          ) : null)}
          <button onClick={onDelete} className="mt-2 text-xs text-red-400 hover:text-red-600 font-medium">Supprimer</button>
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

function SaillieForm({ partners, isMale, initial, saving, onSave, onCancel }: {
  partners: { id: string; nom: string; identification: string }[];
  isMale: boolean;
  initial?: Record<string, string>;
  saving: boolean;
  onSave: (data: Record<string, string>) => Promise<void>;
  onCancel: () => void;
}) {
  const [form, setForm] = useState<Record<string, string>>(initial ?? {});
  const cls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-[#0C5C6C]/30';
  const setF = (k: string, v: string) => setForm(p => ({ ...p, [k]: v }));
  return (
    <div className="space-y-3">
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Date <span className="text-red-400 ml-0.5">*</span></label>
        <input type="date" value={form.date ?? ''} onChange={e => setF('date', e.target.value)} className={cls} />
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
        <button type="button" onClick={() => onSave(form)}
          disabled={saving || !form.date || !form.nom_partenaire}
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
  const [datePrevue, setDatePrevue] = useState(initial?.date_prevue ?? '');
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
    }
  }

  return (
    <div className="space-y-3">
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">Date de conception <span className="text-red-400">*</span></label>
        <input type="date" value={date} onChange={e => handleDateChange(e.target.value)} className={cls} />
      </div>
      <div>
        <label className="text-xs font-semibold text-gray-400 uppercase tracking-wide mb-1 block">
          Mise-bas estimée{jours > 0 ? ` (auto: ${jours} j)` : ''}
        </label>
        <input type="date" value={datePrevue}
          onChange={e => { setDatePrevue(e.target.value); setDateOverride(true); }}
          className={`${cls} ${!dateOverride && datePrevue ? 'bg-green-50 border-green-200' : ''}`} />
      </div>
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
          onClick={() => onSave({ date, date_prevue: datePrevue, date_naissance: dateNaissance, nb_attendu: nbAttendu, nb_nes: nbNes, notes, gestation_confirmee: confirmed ? 'true' : 'false' })}
          className="flex-1 py-2 rounded-xl bg-[#0C5C6C] text-white text-sm font-semibold hover:bg-[#094F5D] disabled:opacity-50">
          {saving ? '…' : 'Enregistrer'}
        </button>
      </div>
    </div>
  );
}

// ─── Documents Animal Tab ─────────────────────────────────────────────────────

function DocumentsAnimalTab({ animalId }: { animalId: string }) {
  const [docs, setDocs] = useState<Record<string,unknown>[]>([]);
  const [certs, setCerts] = useState<Record<string,unknown>[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function load() {
      const [docsRes, certsRes] = await Promise.all([
        supabase.from('documents_animaux').select('*').eq('animal_id', animalId).order('created_at', { ascending: false }),
        supabase.from('certificats_engagement').select('id, nom_animal, acquereur_prenom, acquereur_nom, statut, date_remise, date_signature_acquereur, token_signature').eq('animal_id', animalId).order('date_remise', { ascending: false }),
      ]);
      setDocs(docsRes.data ?? []);
      setCerts(certsRes.data ?? []);
      setLoading(false);
    }
    load();
    // Recharge quand l'onglet reprend le focus (ex. retour de la page de signature)
    const onFocus = () => load();
    window.addEventListener('focus', onFocus);
    return () => window.removeEventListener('focus', onFocus);
  }, [animalId]);

  const typeLabel: Record<string,string> = {
    contrat_vente: 'Contrat de vente',
    contrat_reservation: 'Contrat de réservation',
    contrat_saillie: 'Contrat de saillie',
    contrat_adoption: 'Contrat d\'adoption',
    certificat_cession: 'Certificat de cession',
  };
  const typeIcon: Record<string,string> = {
    contrat_vente: '🤝',
    contrat_reservation: '🔖',
    contrat_saillie: '💞',
    contrat_adoption: '🏡',
    certificat_cession: '📋',
  };
  const statutBadge = (statut: string) => {
    const cfg: Record<string,[string,string]> = {
      signe: ['bg-green-100 text-green-800', 'Signé'],
      archive: ['bg-gray-100 text-gray-600', 'Archivé'],
    };
    const [cls, label] = cfg[statut] ?? ['bg-yellow-100 text-yellow-800', 'Brouillon'];
    return <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${cls}`}>{label}</span>;
  };

  if (loading) return <div className="flex justify-center py-12"><div className="w-6 h-6 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;

  const empty = docs.length === 0 && certs.length === 0;
  if (empty) return (
    <div className="flex flex-col items-center py-16 text-gray-400 gap-2">
      <span className="text-5xl">📂</span>
      <p className="font-semibold">Aucun document lié à cet animal</p>
      <p className="text-sm">Créez un contrat depuis <strong>Administratif → Contrats</strong></p>
    </div>
  );

  return (
    <div className="space-y-3 mt-4">
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
      if (k !== 'id' && k !== 'animal_id' && k !== 'created_at' && v != null)
        data[k] = String(v);
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
              <SaillieForm partners={partners} isMale={isMale} saving={savingRepro}
                onSave={saveSaillie} onCancel={() => setReproAdd(null)} />
            </div>
          )}
          {saillies.length === 0 && !reproAdd && <p className="text-sm text-gray-400 text-center py-8">Aucune saillie enregistrée</p>}
          {saillies.map(r => (
            <div key={r.id} className="bg-white rounded-2xl p-4 shadow-sm">
              {editId === r.id ? (
                <SaillieForm partners={partners} isMale={isMale} saving={savingRepro} initial={editData}
                  onSave={async d => { await updateRepro('saillies', r.id, d); setEditId(null); }}
                  onCancel={() => setEditId(null)} />
              ) : (
                <div className="flex items-start gap-3">
                  <div className="w-10 h-10 rounded-xl bg-purple-50 flex items-center justify-center text-xl flex-shrink-0">💕</div>
                  <div className="flex-1 cursor-pointer" onClick={() => startEdit(r)}>
                    <p className="font-semibold text-sm">{fmtDate(String(r.date ?? ''))}</p>
                    {!!r.nom_partenaire && <p className="text-xs text-gray-600">Partenaire : {String(r.nom_partenaire)}</p>}
                    {!!r.methode && <p className="text-xs text-gray-400">{String(r.methode)}</p>}
                    {!!r.notes && <p className="text-xs text-gray-400">{String(r.notes)}</p>}
                    <p className="text-xs text-[#0C5C6C] mt-1">Modifier →</p>
                  </div>
                  {!readOnly && <button onClick={() => deleteRepro('saillies', r.id)} className="text-red-300 hover:text-red-500 text-lg">×</button>}
                </div>
              )}
            </div>
          ))}
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
                    {!!r.date_prevue && <p className="text-xs text-gray-600">Mise-bas prévue : {fmtDate(String(r.date_prevue))}</p>}
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
          const l1 = `${fmtPoids(tip.val)} kg`, l2 = xLabel(tip.i);
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

// ─── Page principale ──────────────────────────────────────────────────────────

export default function AnimalFichePage() {
  const { id } = useParams<{ id: string }>();
  const { user, userData } = useAuth();
  const activeProfileId = useActiveProfile();
  const router = useRouter();
  const isEleveur = userData?.isElevage === true;
  // isOwner = l'utilisateur est bien le propriétaire de cet animal (pas juste un employé)
  // Déterminé après chargement de l'animal (voir useMemo ci-dessous)
  const isNew = id === 'ajouter';

  // ── État identité
  const [loading, setLoading] = useState(!isNew);
  const [saving, setSaving] = useState(false);
  const [editing, setEditing] = useState(isNew);
  const [tab, setTab] = useState<'identite'|'sante'|'repro'|'alimentation'|'consultations'|'documents'>('identite');

  const [animal, setAnimal] = useState<Animal>({ id:'', espece:'chien', sexe:'male' });
  const [breeds, setBreeds] = useState<string[]>([]);

  // ── Cession
  const [showCession, setShowCession] = useState(false);
  const [cessionEnCours, setCessionEnCours] = useState<Record<string, unknown> | null>(null);
  const [confirmingCession, setConfirmingCession] = useState(false);
  const [revokingCession, setRevokingCession] = useState(false);

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
    vaccinations:[], traitements:[], visites:[], vermifuges:[], antiparasitaires:[], allergies:[], poids:[]
  });
  const [addOpen, setAddOpen] = useState<string|null>(null);
  const [savingHealth, setSavingHealth] = useState(false);
  const [editPoids, setEditPoids] = useState<string|null>(null);

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
  const [mesMales, setMesMales] = useState<{id:string;nom:string;identification?:string;race?:string;photo_url?:string}[]>([]);
  const [showPerePicker, setShowPerePicker] = useState(false);

  // ── Chargement
  const loadAnimal = useCallback(async () => {
    if (!user || isNew) return;
    const { data } = await supabase.from('animaux').select('*').eq('id', id).single();
    if (data) {
      setAnimal(data as Animal);
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
    const tables = ['vaccinations','traitements','visites','vermifuges','antiparasitaires','allergies','poids'];
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
      const { data: users } = await supabase.from('users').select('uid, firstname, lastname').in('uid', proUids);
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
    if (!cessionEnCours) return;
    setConfirmingCession(true);
    const now = new Date().toISOString();
    await supabase.from('cessions').update({ statut: 'confirme', confirmed_at: now }).eq('id', cessionEnCours.id);
    await supabase.from('animaux').update({
      statut: 'sorti',
      date_sortie: (cessionEnCours.date_cession as string) ?? now.split('T')[0],
      destinataire_nom: cessionEnCours.nom_acquereur,
      destinataire_adresse: cessionEnCours.adresse_acquereur ?? null,
      destinataire_qualite: cessionEnCours.qualite ?? 'particulier',
      uid_acquereur: cessionEnCours.uid_acquereur ?? null,
    }).eq('id', id);
    setAnimal(p => ({ ...p, statut: 'sorti', date_sortie: (cessionEnCours.date_cession as string) ?? now.split('T')[0], destinataire_nom: cessionEnCours.nom_acquereur as string }));
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

  useEffect(() => { loadBreeds(animal.espece ?? 'chien').then(setBreeds); }, [animal.espece]);
  useEffect(() => { loadAnimal(); loadHealth(); loadRepro(); loadAlerte(); loadDocs(); loadMouvements(); }, [loadAnimal, loadHealth, loadRepro, loadAlerte, loadDocs, loadMouvements]);
  useEffect(() => { loadCessionEnCours(); }, [loadCessionEnCours]);
  useEffect(() => {
    if (!id || isNew) return;
    supabase.from('pension_updates').select('id').eq('animal_id', id).limit(1)
      .then(({ data }) => setHasPensionUpdates((data ?? []).length > 0));
    supabase.from('education_progression').select('id').eq('animal_id', id).limit(1)
      .then(({ data }) => setHasEducationRapports((data ?? []).length > 0));
  }, [id, isNew]);
  useEffect(() => {
    if (!user || !isEleveur) return;
    supabase.from('users').select('name_elevage, rue_elevage, ville_elevage').eq('uid', user.uid).maybeSingle()
      .then(({ data }) => {
        if (data) {
          setNomElevage((data as {name_elevage?:string}).name_elevage ?? '');
          const parts = [(data as {rue_elevage?:string;ville_elevage?:string}).rue_elevage, (data as {ville_elevage?:string}).ville_elevage].filter(Boolean);
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
        nom: animal.nom?.trim(), espece: animal.espece, race: animal.race, sexe: animal.sexe,
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
        const { error } = await supabase.from('animaux').update({ ...payload, updated_at: new Date().toISOString() }).eq('id', id);
        if (error) throw error;
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
  async function saveHealthRecord(table: string, data: Record<string,string>) {
    if (!id) return;
    setSavingHealth(true);
    await supabase.from(table).insert({ ...data, animal_id: id, id: crypto.randomUUID() });
    await loadHealth();
    setAddOpen(null);
    setSavingHealth(false);
  }

  async function updateHealthRecord(table: string, recordId: string, data: Record<string,string>) {
    setSavingHealth(true);
    await supabase.from(table).update(data).eq('id', recordId);
    await loadHealth();
    setEditPoids(null);
    setSavingHealth(false);
  }

  async function deleteHealthRecord(table: string, recordId: string) {
    await supabase.from(table).delete().eq('id', recordId);
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
    await supabase.from(table).insert({ ...processed, animal_id: id, id: crypto.randomUUID() });

    // Protocoles automatiques
    if (table === 'chaleurs' && data.date) {
      triggerAutoProtocoles({
        uid: user.uid, declencheur: 'chaleurs',
        animalId: id, dateEvenement: new Date(data.date),
        espece: animal.espece,
      }).catch(() => {});
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
      await supabase.from('saillies').insert({ ...data, animal_id: id, id: crypto.randomUUID() });
      if (data.partenaire_animal_id) {
        await supabase.from('saillies').insert({
          id: crypto.randomUUID(),
          animal_id: data.partenaire_animal_id,
          date: data.date,
          nom_partenaire: animal.nom ?? '',
          ident_partenaire: animal.identification ?? '',
          methode: data.methode ?? '',
          notes: data.notes ?? '',
          partenaire_animal_id: id,
        });
      }
      // A07 — Gestation automatique pour la femelle
      if (animal.sexe === 'femelle' && data.date) {
        const jours = GESTATION_DUREE[animal.espece ?? ''] ?? 0;
        const gestData: Record<string, unknown> = {
          id: crypto.randomUUID(),
          animal_id: id,
          date: data.date,
          gestation_confirmee: false,
        };
        if (jours > 0) {
          const prevue = new Date(data.date);
          prevue.setDate(prevue.getDate() + jours);
          gestData.date_prevue = prevue.toISOString().substring(0, 10);
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

  if (loading) {
    return <div className="flex items-center justify-center py-32"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin"/></div>;
  }

  const isAcquereur = !!user && user.uid === animal.uid_acquereur;
  // isOwner : propriétaire original OU acquéreur après cession confirmée
  const isOwner = !!user && (user.uid === animal.uid_eleveur || isAcquereur);
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
    : [{ key:'identite', label:'Identité' }, { key:'sante', label:'Carnet de santé' }, { key:'alimentation', label:'Alimentation' }, { key:'consultations', label:'Consultations vét.' }, { key:'documents', label:'Documents' }];

  const isMale = (animal.sexe ?? '').toLowerCase().startsWith('m');
  const showPoil = ['chien','chat'].includes(animal.espece ?? '');
  const showTaille = animal.espece !== 'oiseau';

  return (
    <div className="max-w-3xl mx-auto px-4 py-6">
      {/* Header */}
      <div className="flex items-center gap-3 mb-6">
        <Link href="/mes-animaux" className="text-gray-400 hover:text-gray-600 text-2xl">←</Link>
        <div className="flex-1 min-w-0">
          <h1 className="text-xl font-bold text-[#1F2A2E] truncate" style={{ fontFamily: 'Galey, sans-serif' }}>
            {isNew ? 'Nouvel animal' : (animal.nom ?? 'Sans nom')}
          </h1>
          {!isNew && (
            <p className="text-sm text-gray-500">
              {[animal.espece && ESPECE_EMOJI[animal.espece], animal.race || animal.espece, animal.date_naissance && age(animal.date_naissance)].filter(Boolean).join(' · ')}
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
                <SelectField label="Espèce" value={animal.espece??'chien'} onChange={v=>set('espece',v)}
                  options={ESPECES.map(e=>({ value:e, label:e.charAt(0).toUpperCase()+e.slice(1) }))} />
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
                    className={`w-12 h-6 rounded-full transition-colors relative ${animal.sterilise ? 'bg-[#6E9E57]' : 'bg-gray-200'}`}>
                    <div className={`w-5 h-5 bg-white rounded-full absolute top-0.5 transition-transform ${animal.sterilise ? 'translate-x-6' : 'translate-x-0.5'}`}/>
                  </button>
                </div>
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
                  { label:'Espèce', value:animal.espece },
                  { label:'Race', value:animal.race },
                  { label:'Sexe', value:animal.sexe==='male'?'♂ Mâle':animal.sexe==='femelle'?'♀ Femelle':'Inconnu' },
                  { label:'Naissance', value:fmtDate(animal.date_naissance) + (animal.date_naissance ? ` (${age(animal.date_naissance)})` : '') },
                  { label:'Couleur', value:animal.couleur },
                  { label:'Identification', value:animal.identification },
                  { label:'Passeport', value:animal.passeport_europeen },
                  { label:'Stérilisé(e)', value:animal.sterilise===true?'Oui':animal.sterilise===false?'Non':undefined },
                  { label:'Type de poil', value:animal.type_poil },
                  { label:'Taille', value:animal.taille ? animal.taille+' cm' : undefined },
                  { label:'Poids', value:animal.poids ? animal.poids+' kg' : undefined },
                ].filter(r=>r.value).map(r=>(
                  <div key={r.label} className="flex gap-2 text-sm">
                    <span className="text-gray-400 w-28 flex-shrink-0">{r.label}</span>
                    <span className="text-[#1F2A2E] font-medium">{r.value}</span>
                  </div>
                ))}
                {animal.description && <p className="text-sm text-gray-600 pt-1 border-t border-gray-100">{animal.description}</p>}
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
          {!editing && (animal.pedigree_lof || animal.club_registre || animal.pedigree_url) && (
            <div className="bg-white rounded-2xl p-4 space-y-2 shadow-sm">
              <h3 className="font-bold text-[#1F2A2E] text-sm uppercase tracking-wide mb-2" style={{ fontFamily:'Galey,sans-serif' }}>🏅 Pedigree & Registre</h3>
              {animal.pedigree_lof && (
                <div className="flex gap-2 text-sm">
                  <span className="text-gray-400 w-28 flex-shrink-0">Inscription</span>
                  <span className="font-medium text-[#1F2A2E]">{animal.pedigree_lof}</span>
                </div>
              )}
              {animal.club_registre && (
                <div className="flex gap-2 text-sm">
                  <span className="text-gray-400 w-28 flex-shrink-0">Club / Registre</span>
                  <span className="font-medium text-[#1F2A2E]">{animal.club_registre}</span>
                </div>
              )}
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
                  <div className="col-span-2">
                    <Field label="Race du père" value={animal.race_pere??''} onChange={v=>set('race_pere',v)} />
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
                  <div className="col-span-2">
                    <Field label="Race de la mère" value={animal.race_mere??''} onChange={v=>set('race_mere',v)} />
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
                  <button onClick={()=>set('contacts_urgence', [...(animal.contacts_urgence??[]), {nom:'',tel:''}])}
                    className="text-xs text-[#0C5C6C] font-semibold">+ Ajouter</button>
                )}
              </div>
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
                        <p className="text-sm font-galey text-gray-800">{r.contenu}</p>
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
          <HealthSection title="Vaccinations" icon="💉" color="#2196F3" count={health.vaccinations.length}
            onAdd={canWriteSante ? ()=>setAddOpen(addOpen==='vaccinations'?null:'vaccinations') : undefined}
            addFormOpen={addOpen==='vaccinations'}
            addForm={<AddHealthForm saving={savingHealth} onCancel={()=>setAddOpen(null)}
              onSave={d=>saveHealthRecord('vaccinations',d)}
              fields={[{key:'vaccin',label:'Vaccin',required:true},{key:'date',label:'Date',type:'date'},{key:'date_rappel',label:'Date de rappel',type:'date'},{key:'lot',label:'N° de lot'},{key:'veterinaire',label:'Vétérinaire'}]}/>}>
            {health.vaccinations.map(r=>(
              <HealthRecord key={r.id} record={r} onDelete={()=>deleteHealthRecord('vaccinations',r.id)}
                fields={[{key:'vaccin',label:'Vaccin'},{key:'date',label:'Date'},{key:'date_rappel',label:'Rappel'},{key:'lot',label:'Lot'},{key:'veterinaire',label:'Vétérinaire'}]}/>
            ))}
            {health.vaccinations.length===0 && <p className="p-4 text-sm text-gray-400">Aucune vaccination</p>}
          </HealthSection>

          {/* Vermifuges */}
          <HealthSection title="Vermifuges" icon="🧪" color="#6E9E57" count={health.vermifuges.length}
            onAdd={canWriteSante ? ()=>setAddOpen(addOpen==='vermifuges'?null:'vermifuges') : undefined}
            addFormOpen={addOpen==='vermifuges'}
            addForm={<AddHealthForm saving={savingHealth} onCancel={()=>setAddOpen(null)}
              onSave={d=>saveHealthRecord('vermifuges',d)}
              fields={[{key:'produit',label:'Produit',required:true},{key:'date',label:'Date',type:'date'},{key:'date_rappel',label:'Date de rappel',type:'date'},{key:'dosage',label:'Dosage'},{key:'notes',label:'Notes'}]}/>}>
            {health.vermifuges.map(r=>(
              <HealthRecord key={r.id} record={r} onDelete={()=>deleteHealthRecord('vermifuges',r.id)}
                fields={[{key:'produit',label:'Produit'},{key:'date',label:'Date'},{key:'date_rappel',label:'Rappel'},{key:'dosage',label:'Dosage'},{key:'notes',label:'Notes'}]}/>
            ))}
            {health.vermifuges.length===0 && <p className="p-4 text-sm text-gray-400">Aucun vermifuge</p>}
          </HealthSection>

          {/* Antiparasitaires */}
          <HealthSection title="Antiparasitaires" icon="🛡️" color="#5B8648" count={health.antiparasitaires.length}
            onAdd={canWriteSante ? ()=>setAddOpen(addOpen==='antiparasitaires'?null:'antiparasitaires') : undefined}
            addFormOpen={addOpen==='antiparasitaires'}
            addForm={<AddHealthForm saving={savingHealth} onCancel={()=>setAddOpen(null)}
              onSave={d=>saveHealthRecord('antiparasitaires',d)}
              fields={[{key:'produit',label:'Produit',required:true},{key:'type',label:'Type (collier, pipette…)'},{key:'date',label:'Date',type:'date'},{key:'date_rappel',label:'Date de rappel',type:'date'},{key:'frequence',label:'Fréquence'},{key:'notes',label:'Notes'}]}/>}>
            {health.antiparasitaires.map(r=>(
              <HealthRecord key={r.id} record={r} onDelete={()=>deleteHealthRecord('antiparasitaires',r.id)}
                fields={[{key:'produit',label:'Produit'},{key:'type',label:'Type'},{key:'date',label:'Date'},{key:'date_rappel',label:'Rappel'},{key:'frequence',label:'Fréquence'},{key:'notes',label:'Notes'}]}/>
            ))}
            {health.antiparasitaires.length===0 && <p className="p-4 text-sm text-gray-400">Aucun antiparasitaire</p>}
          </HealthSection>

          {/* Traitements */}
          <HealthSection title="Traitements" icon="💊" color="#8D6E63" count={health.traitements.length}
            onAdd={canWriteSante ? ()=>setAddOpen(addOpen==='traitements'?null:'traitements') : undefined}
            addFormOpen={addOpen==='traitements'}
            addForm={<AddHealthForm saving={savingHealth} onCancel={()=>setAddOpen(null)}
              onSave={d=>saveHealthRecord('traitements',d)}
              fields={[{key:'nom',label:'Nom',required:true},{key:'type',label:'Type'},{key:'posologie',label:'Posologie'},{key:'date',label:'Date début',type:'date'},{key:'date_fin',label:'Date fin',type:'date'}]}/>}>
            {health.traitements.map(r=>(
              <HealthRecord key={r.id} record={r} onDelete={()=>deleteHealthRecord('traitements',r.id)}
                fields={[{key:'nom',label:'Nom'},{key:'type',label:'Type'},{key:'posologie',label:'Posologie'},{key:'date',label:'Début'},{key:'date_fin',label:'Fin'}]}/>
            ))}
            {health.traitements.length===0 && <p className="p-4 text-sm text-gray-400">Aucun traitement</p>}
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
                fields={[{key:'description',label:'Description'},{key:'type',label:'Type'},{key:'severite',label:'Sévérité'},{key:'date',label:'Date'},{key:'notes',label:'Notes'}]}/>
            ))}
            {health.allergies.length===0 && <p className="p-4 text-sm text-gray-400">Aucune allergie</p>}
          </HealthSection>

          {/* Poids */}
          <HealthSection title="Courbe de poids" icon="⚖️" color="#5F9EAA" count={health.poids.length}
            onAdd={canWriteSante ? ()=>setAddOpen(addOpen==='poids'?null:'poids') : undefined}
            addFormOpen={addOpen==='poids'}
            addForm={<AddHealthForm saving={savingHealth} onCancel={()=>setAddOpen(null)}
              onSave={d=>saveHealthRecord('poids',d)}
              fields={[{key:'valeur',label:'Poids (kg)',required:true,type:'number'},{key:'date',label:'Date',type:'date'},{key:'notes',label:'Notes'}]}/>}>
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
                          <AddHealthForm saving={savingHealth} onCancel={()=>setEditPoids(null)}
                            onSave={d=>updateHealthRecord('poids',r.id,d)}
                            initial={{ valeur: String(r.valeur??''), date: String(r.date??''), notes: String(r.notes??'') }}
                            fields={[{key:'valeur',label:'Poids (kg)',required:true,type:'number'},{key:'date',label:'Date',type:'date'},{key:'notes',label:'Notes'}]}/>
                        ) : (
                          <>
                            <div className="flex items-center gap-2 mb-1">
                              <span className="font-semibold text-sm text-[#5F9EAA]">{fmtPoids(val)} kg</span>
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
                fields={[{key:'motif',label:'Motif'},{key:'date',label:'Date'},{key:'veterinaire',label:'Vétérinaire'},{key:'diagnostic',label:'Diagnostic'},{key:'notes',label:'Notes'}]}/>
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
        <ConsultationsVetTab crs={crs} ordonnances={ordonnances} vetNames={vetNames} />
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
        />
      )}

      {/* ── TAB DOCUMENTS ───────────────────────────────────────────────── */}
      {tab === 'documents' && !isNew && (
        <DocumentsAnimalTab animalId={id ?? ''} />
      )}

      {showPerePicker && (
        <div className="fixed inset-0 bg-black/50 z-50 flex items-end sm:items-center justify-center p-4"
          onClick={() => setShowPerePicker(false)}>
          <div className="bg-white rounded-2xl w-full max-w-md max-h-[70vh] overflow-hidden shadow-2xl"
            onClick={e => e.stopPropagation()}>
            <div className="p-4 border-b border-gray-100">
              <h3 className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Choisir le père</h3>
            </div>
            <div className="overflow-y-auto max-h-[55vh]">
              {mesMales.map(m => (
                <button key={m.id} type="button"
                  onClick={() => {
                    set('nom_pere', m.nom);
                    set('puce_pere', m.identification ?? '');
                    set('race_pere', m.race ?? '');
                    setShowPerePicker(false);
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
          onClick={() => setShowMerePicker(false)}>
          <div className="bg-white rounded-2xl w-full max-w-md max-h-[70vh] overflow-hidden shadow-2xl"
            onClick={e => e.stopPropagation()}>
            <div className="p-4 border-b border-gray-100">
              <h3 className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Choisir la mère</h3>
            </div>
            <div className="overflow-y-auto max-h-[55vh]">
              {mesFemelles.map(f => (
                <button key={f.id} type="button"
                  onClick={() => {
                    set('nom_mere', f.nom);
                    set('puce_mere', f.identification ?? '');
                    set('race_mere', f.race ?? '');
                    if (f.date_naissance) set('date_naissance_mere', f.date_naissance.substring(0, 10));
                    setShowMerePicker(false);
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
          eleveurInfo={{ nom: nomElevage || user.email || 'Éleveur', adresse: adresseElevage, email: user.email ?? '' }}
          onClose={() => setShowCession(false)}
          onCeded={() => { setShowCession(false); loadAnimal(); }}
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
