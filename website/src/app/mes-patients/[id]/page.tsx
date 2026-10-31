'use client';

import { AideEtapes } from '@/components/animaux/EtapesTraitement';
import { useEspaceClinique } from '@/lib/espace-clinique';
import { PlanAlimentationDepuisLigne } from '@/components/alimentation/PlanAlimentationLecture';
import { poidsKg } from '@/lib/poids';
import { progression, libelleDuree, echeanceDans, DUREES_EXERCICE, DUREE_DEFAUT_JOURS } from '@/lib/exercices-progression';
import { SyntheseVet, SyntheseOsteo, DocumentsSantePro } from '@/components/animaux/SanteProTabs';
import ProAnimalEntete from '@/components/animaux/ProAnimalEntete';
import CompteRenduExpressModal from '@/components/garde/CompteRenduExpressModal';
import ToilettageFicheTabs from '@/components/toilettage/ToilettageFicheTabs';
import { gardePrestationKey } from '@/lib/garde-facturation';
import { gardeMotifLabel, accesLogementLabel } from '@/lib/garde-labels';
import { Suspense, useEffect, useState, useCallback, useRef } from 'react';
import Image from 'next/image';
import { useRouter, useParams, useSearchParams } from 'next/navigation';
import { httpsCallable } from 'firebase/functions';
import { functions } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { animauxDetailRdv, type AnimalRdv } from '@/lib/rdv-animaux';
import { crsDuRdv } from '@/lib/cr-rdv';
import { maSignaturePro, enregistrerSignaturePro } from '@/lib/signature-pro';
import SignatureProModal from '@/components/signature/SignatureProModal';
import { useAuth } from '@/lib/auth-context';
import { RichText, RichTextEditor, richTextIsEmpty, richTextToPlain } from '@/lib/rich-text';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { AnatomieSeances } from '@/components/AnatomiePoints';
import MorphoAnimalTab from '@/components/morpho/MorphoAnimalTab';
import OwnerContactButton from '@/components/pro/OwnerContactButton';
import { retourDossierEducation } from '@/components/education/DossierEducationModal';

import LienDocument from '@/components/LienDocument';
import ConsultationsVet, { type CrVet, type OrdoVet } from '@/components/pro/ConsultationsVet';
import HistoriquePatient from '@/components/pro/HistoriquePatient';
import { ouvrirDocument } from '@/lib/document-prive';
import { ordonnancePdfBlob, compteRenduPdfBlob, ageAnimal, sexeAnimal } from '@/lib/ordonnance-pdf';
import { imprimerPdf, pdfDepuisUrl, envoyerPdfParEmail } from '@/lib/transmission-document';
import { phraseChampsARemplir, erreursDatesSante } from '@/lib/controle-dates';
import VermifugeOptions, { colonnesPrises, optionsVermifugeVides, type OptionsVermifuge } from '@/components/animaux/VermifugeOptions';
import { uploadDocument as uploadDocToStorage } from '@/lib/upload-media';
import { allerOuFermer } from '@/lib/panneau';
// ── Types ─────────────────────────────────────────────────────────────────────

interface Animal {
  id: number | string; nom: string; espece: string; race: string | null;
  sexe: string | null; couleur: string | null; couleur_yeux: string | null; date_naissance: string | null;
  identification: string | null; passeport_numero: string | null;
  photo_url: string | null; sterilise: boolean | null;
  poids: number | null; taille: number | null; notes: string | null;
  uid_proprietaire: string | null; uid_eleveur: string | null;
}
interface Owner {
  uid: string; firstname: string | null; lastname: string | null;
  name_elevage: string | null; email: string | null;
  phone_number: string | null; numero_elevage: string | null;
  adress_elevage: string | null; rue_elevage: string | null;
  ville_elevage: string | null; code_postal_elevage: string | null;
  ville: string | null; code_postal: string | null; rue?: string | null;
  is_elevage: boolean | null; is_pro: boolean | null;
}
interface Grant { id: string; statut: string; pro_profile_id: string; granted_by_profile_id?: string | null }
/** Profil (user_profiles) qui a confié l'animal : son adresse prime sur celle
 *  du compte (multi-profil : un compte éleveur peut avoir un profil particulier). */
interface OwnerProfil {
  id: string; profile_type: string | null; firstname: string | null; lastname: string | null; nom: string | null;
  adresse?: string | null; rue?: string | null; code_postal?: string | null; ville?: string | null;
  rue_elevage?: string | null; adress_elevage?: string | null; code_postal_elevage?: string | null; ville_elevage?: string | null;
}
interface VaccinEntry {
  id: string; vaccin: string; date: string;
  date_rappel: string | null; lot: string | null; veterinaire: string | null; source: string | null;
}
// alimentations — écrite par le propriétaire depuis l'appli (animal_fiche.dart
// _AlimentationTab). notes packe des détails secondaires en pipe-séparé,
// dont le nombre de repas/jour en 4ᵉ segment — cf. _save() côté appli.
interface AlimentationEntry {
  id: string; type_ration: string | null; marque: string | null; gamme: string | null;
  niveau_activite: string | null; densite_calorique: number | null; notes: string | null;
}
interface VisiteEntry {
  id: string; date: string; motif: string | null;
  veterinaire: string | null; diagnostic: string | null; notes: string | null;
  source: string | null; vet_id: string | null;
}
interface GardeRdvFiche {
  id: string; date_heure: string; duree_minutes: number | null; statut: string; motif: string | null;
  lieu: string | null; notes_client: string | null; acces_logement?: string | null; animal_id: string | null;
  client_uid: string | null; client_profile_id: string | null;
  arrivee_validee_le?: string | null; depart_valide_le?: string | null; termine_at?: string | null;
}
interface TraitementEntry {
  id: string; date: string; nom: string; posologie: string | null;
  date_fin: string | null; notes: string | null; source: string | null; vet_id: string | null;
}
interface CompteRendu {
  id: string; created_at: string; contenu: string | null; pro_uid: string | null;
  animal_id?: string | null; rdv_id?: string | null;
  statut?: 'brouillon' | 'valide' | null;
  brouillon?: unknown;
  // CR structuré (migration_cr_structure.sql) — historique du patient.
  motif?: string | null; poids?: number | null; actes?: string[] | null; prescription?: string | null;
  produits?: ProduitCr[] | null;
}
interface Ordonnance {
  id: string; date_emit: string; doc_url: string | null; notes: string | null; pro_uid: string | null;
}
interface RadioEntry {
  id: string; date: string; titre: string | null; notes: string | null; veterinaire: string | null; image_url?: string | null;
}
// Miroir des 4 domaines carnet manquants côté web (déjà écrits par le véto
// depuis l'appli — animal_fiche.dart, cf. VET06) : vermifuges, antiparasitaires,
// chirurgies, allergies.
interface VermifugeEntry {
  id: string; date: string; produit: string; dosage: string | null;
  date_rappel: string | null; frequence: string | null; notes: string | null;
  source: string | null; veterinaire: string | null;
}
interface AntiparasitaireEntry {
  id: string; date: string; produit: string; type: string | null;
  date_rappel: string | null; frequence: string | null; notes: string | null;
  source: string | null; veterinaire: string | null;
}
interface ChirurgieEntry {
  id: string; date: string; type: string | null; intitule: string; statut: string | null;
  clinique: string | null; protocole_preop: string | null; protocole_postop: string | null;
  notes: string | null; source: string | null; veterinaire: string | null;
}
interface AllergieEntry {
  id: string; date: string | null; type: string | null; description: string;
  severite: string | null; notes: string | null; source: string | null;
}
interface Chaleur { id: string; date: string; date_fin: string | null; duree: number | null; notes: string | null; }
interface Saillie { id: string; date: string; nom_partenaire: string | null; methode: string | null; notes: string | null; }
interface Gestation {
  id: string; date: string | null; date_prevue: string | null; date_naissance: string | null;
  nb_attendu: number | null; nb_nes: number | null; notes: string | null; gestation_confirmee: boolean | null;
}
interface EducObjectif {
  id: string; libelle: string; categorie: string | null; statut: string; note: string | null; ordre: number;
  prioritaire?: boolean | null; difficultes?: string | null;
}
interface EducExercice { id: string; titre: string; description: string | null; media: unknown; etapes?: { titre: string }[] | null; }
interface EducAttribue {
  id: string; titre_snapshot: string; description_snapshot?: string | null;
  cadence: string | null; echeance: string | null; statut: string; rappels_actifs: boolean;
  etapes_snapshot?: { titre: string }[] | null; nb_validations?: number | null; validations?: string[] | null;
}
interface EducRetour {
  id: string; attribution_id: string; note: string | null;
  media: { type: string; url: string }[] | null; ressenti: string | null; from_pro: boolean;
}
interface RapportEduP {
  id: string; date_seance: string; contenu: string; exercices_conseilles: string | null;
  type?: string; bilan_motif?: string | null; bilan_recommandation?: string | null; bilan_nb_seances_estime?: number | null;
  // migration_education_fiche.sql
  statut?: string | null; type_seance?: string | null; lieu?: string | null; duree_minutes?: number | null;
  objectifs_travailles?: string[] | null; comportements?: string | null; difficultes?: string | null;
  prochaine_etape?: string | null; rdv_id?: string | null;
}
interface ForfaitSous { id: string; nom_snapshot: string; nb_seances_total: number; nb_seances_utilisees: number; statut: string; }
const EDUC_RESSENTI: Record<string, string> = { facile: '😊 Facile', moyen: '😐 Moyen', difficile: '😓 Difficile', bloque: '🚫 Bloqué' };

// ── Constants ─────────────────────────────────────────────────────────────────

const EDUC_CATEGORIES: Record<string, string> = {
  rappel: 'Rappel', laisse: 'Marche en laisse', proprete: 'Propreté', aboiements: 'Aboiements',
  destruction: 'Destruction', socialisation_chien: 'Socialisation chiens', socialisation_humain: 'Socialisation humains',
  manipulation: 'Manipulation / soins', solitude: 'Solitude', agressivite: 'Agressivité', peurs: 'Peurs', autre: 'Autre',
};
// Statut renseigné par le professionnel (aucun pourcentage calculé) — miroir appli education_shared.dart.
const EDUC_STATUTS = ['a_travailler', 'en_cours', 'en_progression', 'acquis', 'a_reevaluer'] as const;
const EDUC_STATUT_LABEL: Record<string, string> = {
  a_travailler: 'À travailler', en_cours: 'En cours', en_progression: 'En progression',
  acquis: 'Acquis selon évaluation', a_reevaluer: 'À réévaluer',
};
const educStatutColor = (s: string) => ({ acquis: '#6E9E57', en_progression: '#2E7D8C', en_cours: '#EFA100', a_reevaluer: '#7B5EA7' } as Record<string, string>)[s] ?? '#D5573B';
const EDUC_TYPES_SEANCE: Record<string, string> = {
  bilan: 'Bilan initial', individuelle: 'Séance individuelle', collective: 'Séance collective',
  domicile: 'Séance à domicile', exterieur: 'Séance en extérieur', suivi: 'Suivi comportemental',
};

const ESPECE_EMOJI: Record<string, string> = {
  chien: '', chat: '', cheval: '', lapin: '',
  oiseau: '', nac: '', ovin: '', caprin: '', porcin: '', ane: '',
};
const PENSION_TYPES = new Set(['pension', 'garde', 'toilettage', 'photographe']);
const TEAL = '#0C5C6C';

// ── Helpers ───────────────────────────────────────────────────────────────────

function fmtDate(iso: string | null) {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('fr-FR', { day: '2-digit', month: 'long', year: 'numeric' });
}
function fmtDateShort(iso: string | null) {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('fr-FR', { day: '2-digit', month: '2-digit', year: 'numeric' });
}
function calcAge(dateNaissance: string | null): string {
  if (!dateNaissance) return '';
  const birth = new Date(dateNaissance);
  const months = (new Date().getFullYear() - birth.getFullYear()) * 12 + new Date().getMonth() - birth.getMonth();
  return months < 24 ? `${months} mois` : `${Math.floor(months / 12)} ans`;
}

// ── Sub-components ────────────────────────────────────────────────────────────

function InfoGrid({ rows }: { rows: { label: string; value: string | null | undefined }[] }) {
  return (
    <div className="grid grid-cols-2 gap-3 text-sm">
      {rows.map(r => (
        <div key={r.label}>
          <p className="text-[10px] text-gray-400 uppercase tracking-wide">{r.label}</p>
          <p className="font-medium text-[#1F2A2E]">{r.value || '—'}</p>
        </div>
      ))}
    </div>
  );
}

function Card({ title, children, action }: { title?: string; children: React.ReactNode; action?: React.ReactNode }) {
  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-5">
      {(title || action) && (
        <div className="flex items-center justify-between gap-2 mb-4">
          {title ? <h3 className="font-bold text-sm text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>{title}</h3> : <span />}
          {action}
        </div>
      )}
      {children}
    </div>
  );
}

function EmptyState({ text }: { text: string }) {
  return <p className="text-center py-10 text-gray-400 text-sm">{text}</p>;
}

// ── Main page ─────────────────────────────────────────────────────────────────

function ForfaitSousForm({ proUid, onSave, onCancel }: {
  proUid: string;
  onSave: (nom: string, nb: number, prix: number | null, forfaitId: string | null) => void;
  onCancel: () => void;
}) {
  const [nom, setNom] = useState('');
  const [nb, setNb] = useState('5');
  const [prix, setPrix] = useState('');
  const [forfaitId, setForfaitId] = useState('');
  const [catalog, setCatalog] = useState<{ id: string; nom: string; nb_seances: number; prix: number }[]>([]);
  useEffect(() => {
    if (!proUid) return;
    supabase.from('forfaits_education').select('id, nom, nb_seances, prix').eq('pro_uid', proUid).eq('actif', true).order('created_at')
      .then(({ data }) => setCatalog((data ?? []) as typeof catalog));
  }, [proUid]);
  return (
    <div className="border border-[#EF6C00]/30 rounded-2xl p-4 mb-4 bg-[#EF6C00]/5 space-y-2">
      {catalog.length > 0 && (
        <select value={forfaitId} onChange={e => {
          const v = e.target.value; setForfaitId(v);
          const f = catalog.find(x => x.id === v);
          if (f) { setNom(f.nom); setNb(String(f.nb_seances)); setPrix(String(f.prix)); }
        }} className="w-full border border-gray-200 rounded-xl px-2 py-2 text-sm">
          <option value="">Saisie libre…</option>
          {catalog.map(f => <option key={f.id} value={f.id}>{f.nom} · {f.nb_seances}× · {f.prix}€</option>)}
        </select>
      )}
      <input value={nom} onChange={e => setNom(e.target.value)} placeholder="Nom du forfait"
        className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />
      <div className="flex gap-2">
        <input type="number" value={nb} onChange={e => setNb(e.target.value)} placeholder="Nb séances"
          className="w-28 border border-gray-200 rounded-xl px-3 py-2 text-sm" />
        <input type="number" value={prix} onChange={e => setPrix(e.target.value)} placeholder="Prix (€)"
          className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm" />
      </div>
      <div className="flex gap-2">
        <button onClick={onCancel} className="flex-1 border border-gray-200 rounded-xl py-2 text-sm text-gray-500">Annuler</button>
        <button onClick={() => onSave(nom, Number(nb), prix ? Number(prix) : null, forfaitId || null)}
          disabled={!nom.trim()} className="flex-1 text-white rounded-xl py-2 text-sm font-semibold disabled:opacity-50" style={{ background: '#EF6C00' }}>
          Enregistrer
        </button>
      </div>
    </div>
  );
}

interface VaccinCr { nom: string; lot: string; date: string; rappel: string | null }
/** Phase d'un traitement (dégressif : plusieurs phases enchaînées). */
/** doses : dose propre à chaque prise (clé de PRISES) — absente : dose partout. */
interface PhaseCr { dose: string; prises: string[]; frequenceJours: number; dureeJours: number | null; doses?: Record<string, string> }
const doseDe = (p: PhaseCr, k: string) => p.doses?.[k]?.trim() || p.dose.trim();
const dosesParPrise = (p: PhaseCr) => !!p.doses && p.prises.length > 1;
interface TraitementCr { nom: string; type: string; phases: PhaseCr[]; rappels: boolean; notes: string }
interface ArticlePharmacie { id: string; nom: string; categorie: string; lot: string | null; quantite: number | null; unite: string | null; prix_vente?: number | null }
/** Produit vendu pendant la consultation (non administré : pas au carnet) —
 *  facturé et décompté du stock. Miroir de _ProduitCr (appli). */
interface ProduitCr { nom: string; quantite: number; prix: number | null; item_id?: string | null }

type LigneFacture = { description: string; quantite: number; prixUnitaire: number; tva: number };

/** Lignes de facture d'une consultation (grille du vétérinaire + prix de la
 *  pharmacie) — miroir appli _lignesFacture. [prefixe] : nom de l'animal
 *  devant chaque ligne (visite à plusieurs animaux). */
/** Rubriques du texte d'un compte rendu reprises telles quelles quand on le
 *  modifie (actes déjà inscrits au carnet) — voir modifierCr. */
const TITRES_CR_CONSERVES = ['Vaccins', 'Vermifuge', 'Antiparasitaire', 'Allergie / pathologie', 'Chirurgie', 'Hospitalisation', 'Examen', 'Traitement', 'Produits délivrés'];

function lignesConsultation({ an, motif, actes, vaccins, traitements, poids, produits, tarif, prixPharma, prefixe = '' }: {
  an: { espece?: string | null; sexe?: string | null; poids?: number | string | null };
  motif: string; actes: string[]; vaccins: VaccinCr[]; traitements: TraitementCr[]; poids: number | null; produits: ProduitCr[];
  tarif: (k: string) => number | null; prixPharma: (nom: string) => number | null; prefixe?: string;
}): LigneFacture[] {
  const pre = prefixe ? `${prefixe} — ` : '';
  const espece = (an.espece ?? '').toLowerCase();
  const femelle = (an.sexe ?? '').toLowerCase().startsWith('f');
  const kg = poids ?? (an.poids != null && an.poids !== '' ? Number(an.poids) : null);
  const tranche = kg == null ? '25' : kg < 10 ? '10' : kg < 25 ? '25' : kg < 45 ? '45' : '45p';
  const lignes: LigneFacture[] = [];
  const ligne = (d: string, ttc: number | null) => lignes.push({ description: pre + d, quantite: 1, prixUnitaire: ttc == null ? 0 : Math.round(ttc / 1.2 * 100) / 100, tva: 20 });
  const m = motif.toLowerCase();
  ligne(motif || 'Consultation', tarif(m.includes('urgen') ? 'consultation_urgence' : m.includes('domicile') ? 'visite_domicile' : 'consultation'));
  for (const a of actes) {
    if (a === 'Examen clinique' || (a === 'Vaccination' && vaccins.length)) continue;
    let prix: number | null = null;
    if (a === 'Vaccination') prix = tarif(espece === 'chat' ? 'vaccin_chat' : 'vaccin_chien');
    if (a === 'Pose de puce') prix = tarif('identification');
    if (a === 'Castration / stérilisation') prix = espece === 'chat' ? tarif(femelle ? 'sterilisation_chatte' : 'castration_chat')
      : tarif(`${femelle ? 'sterilisation_chienne' : 'castration_chien'}_${tranche}`);
    ligne(a, prix);
  }
  for (const v of vaccins) ligne(`Vaccin ${v.nom}${v.lot ? ` (lot ${v.lot})` : ''}`, prixPharma(v.nom) ?? tarif(espece === 'chat' ? 'vaccin_chat' : 'vaccin_chien'));
  for (const tr of traitements) ligne(tr.nom, prixPharma(tr.nom));
  // Produits vendus (non administrés) : quantité + prix saisi, sinon prix de vente du stock.
  for (const p of produits) {
    const ttc = p.prix ?? prixPharma(p.nom);
    lignes.push({ description: pre + p.nom, quantite: p.quantite, prixUnitaire: ttc == null ? 0 : Math.round(ttc / 1.2 * 100) / 100, tva: 20 });
  }
  return lignes;
}
/** Soin du compte rendu inscrit au carnet dans sa rubrique (miroir de _SoinCr, appli). */
interface SoinCr { type: 'vermifuge' | 'antiparasitaire' | 'allergie' | 'chirurgie' | 'hospitalisation' | 'radio'; nom: string; detail: string; rappel_mois?: number | null }
const SOINS_LIBELLES: Record<SoinCr['type'], string> = {
  vermifuge: 'Vermifuge', antiparasitaire: 'Antiparasitaire', allergie: 'Allergie / pathologie',
  chirurgie: 'Chirurgie', hospitalisation: 'Hospitalisation', radio: 'Radio / examen',
};
const libelleSoin = (s: SoinCr) => s.detail ? `${s.nom} (${s.detail})` : s.nom;
const libelleProduit = (p: ProduitCr) => p.quantite === 1 ? p.nom : `${p.nom} ×${String(p.quantite).replace('.', ',')}`;

const ANTIPARASITAIRES_COURANTS = ['Bravecto', 'NexGard', 'NexGard Spectra', 'Simparica', 'Simparica Trio', 'Credelio',
  'Advocate', 'Stronghold', 'Frontline', 'Broadline', 'Milbemax', 'Drontal', 'Milpro', 'Profender', 'Seresto (collier)', 'Scalibor (collier)'];
const MEDICAMENTS_COURANTS = ['Metacam (méloxicam)', 'Previcox', 'Onsior', 'Rimadyl', 'Synulox', 'Clavaseptin', 'Kesium', 'Marbocyl',
  'Convenia', 'Prednisolone', 'Cortavance', 'Apoquel', 'Cytopoint', 'Vetmedin', 'Fortekor', 'Cerenia', 'Gabapentine', 'Tramadol',
  'Forthyron', 'Cardalis'];
const ACTES_COURANTS = ['Examen clinique', 'Vaccination', 'Prise de sang', 'Analyse sanguine', 'Radiographie', 'Échographie',
  "Analyse d'urine", 'Coproscopie', 'Injection', 'Soins de plaie', 'Détartrage', 'Pose de puce', 'Castration / stérilisation',
  'Chirurgie', 'Hospitalisation', 'Euthanasie'];
const VACCINS_COURANTS = ['CHPPiL', 'Rage', 'Leptospirose', 'Toux du chenil', 'Leishmaniose', 'Typhus / coryza (RC P)',
  'Leucose (FeLV)', 'Myxomatose', 'VHD (lapin)', 'Grippe équine', 'Rhinopneumonie', 'Tétanos'];
/** Prises de la journée → libellé + heure du rappel au propriétaire. */
/** Moments proposés → libellé + heure du rappel ; une prise libre (plus de 3
 *  par jour, horaire précis) est son heure « HH:MM ». Miroir de _kPrises. */
const PRISES: Record<string, [string, string]> = {
  matin: ['Matin', '08:00'], midi: ['Midi', '12:00'], apres_midi: ['Après-midi', '16:00'],
  soir: ['Soir', '19:00'], coucher: ['Coucher', '22:00'],
};
/** « 08:00 » → « 8 h », « 22:30 » → « 22 h 30 ». */
const heureCourte = (h: string) => { const m = /^(\d{1,2}):(\d{2})$/.exec(h); return m ? `${parseInt(m[1], 10)} h${m[2] === '00' ? '' : ` ${m[2]}`}` : h; };
const heurePrise = (k: string) => PRISES[k]?.[1] ?? k;
const nomPrise = (k: string) => PRISES[k]?.[0] ?? `À ${heureCourte(k)}`;
const quandPrise = (k: string) => PRISES[k] ? `le ${PRISES[k][0].toLowerCase()}` : `à ${heureCourte(k)}`;
const prisesTriees = (p: string[]) => [...p].sort((a, b) => heurePrise(a).localeCompare(heurePrise(b)));

/** Actes réalisés : liste déroulante à cocher, recherche + autre acte. */
function ActesSelect({ value, onChange }: { value: string[]; onChange: (v: string[]) => void }) {
  const [ouvert, setOuvert] = useState(false);
  const [q, setQ] = useState('');
  const [autre, setAutre] = useState('');
  const tous = [...new Set([...ACTES_COURANTS, ...value])];
  const liste = tous.filter(a => !q || a.toLowerCase().includes(q.toLowerCase()));
  const basculer = (a: string) => onChange(value.includes(a) ? value.filter(x => x !== a) : [...value, a]);
  const ajouter = () => { const v = autre.trim(); if (v && !value.includes(v)) onChange([...value, v]); setAutre(''); };
  return (
    <div className="relative">
      <button type="button" onClick={() => setOuvert(o => !o)}
        className="w-full flex items-center justify-between border border-gray-200 rounded-xl px-3 py-2.5 text-sm bg-white text-left">
        <span className={value.length ? 'text-[#1F2A2E]' : 'text-gray-400'}>{value.length ? value.join(', ') : 'Choisir les actes…'}</span>
        <span className={`text-gray-400 text-xs ml-2 transition-transform ${ouvert ? 'rotate-180' : ''}`}>▼</span>
      </button>
      {ouvert && (
        <div className="absolute z-30 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-2xl shadow-lg overflow-hidden">
          <div className="p-2 border-b border-gray-100">
            <input value={q} onChange={e => setQ(e.target.value)} placeholder="🔎 Rechercher un acte"
              className="w-full border border-gray-200 rounded-lg px-2.5 py-1.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
          </div>
          <div className="max-h-56 overflow-y-auto p-1">
            {liste.map(a => (
              <label key={a} className="flex items-center gap-2.5 px-2 py-1.5 rounded-lg hover:bg-gray-50 cursor-pointer text-sm">
                <input type="checkbox" checked={value.includes(a)} onChange={() => basculer(a)} className="w-4 h-4 accent-[#0C5C6C]" />
                {a}
              </label>
            ))}
          </div>
          <div className="flex gap-2 p-2 border-t border-gray-100">
            <input value={autre} onChange={e => setAutre(e.target.value)} placeholder="Autre acte (biopsie, ECG…)"
              onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); ajouter(); } }}
              className="flex-1 border border-gray-200 rounded-lg px-2.5 py-1.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
            <button type="button" onClick={ajouter} className="px-2.5 rounded-lg text-sm font-semibold text-[#0C5C6C] border border-gray-200">＋</button>
            <button type="button" onClick={() => setOuvert(false)} className="px-3 rounded-lg text-sm font-semibold text-white bg-[#0C5C6C]">OK</button>
          </div>
        </div>
      )}
    </div>
  );
}

type UniteDelai = 'jours' | 'semaines' | 'mois' | 'ans';
const JOURS_PAR_UNITE = { jours: 1, semaines: 7, mois: 30 } as const;
/** Rappel « dans N jours / semaines / mois / ans » à partir de la date du vaccin. */
function delaiRappel(dateIso: string, n: string, unite: UniteDelai): string | null {
  const v = parseInt(n, 10);
  if (!(v > 0)) return null;
  return unite === 'jours' ? plus(dateIso, v) : unite === 'semaines' ? plus(dateIso, 7 * v)
    : unite === 'mois' ? plus(dateIso, 0, v) : plus(dateIso, 0, 0, v);
}

function plus(dateIso: string, jours = 0, mois = 0, ans = 0): string {
  const d = new Date(dateIso + 'T12:00:00');
  d.setFullYear(d.getFullYear() + ans, d.getMonth() + mois, d.getDate() + jours);
  return d.toISOString().slice(0, 10);
}

/** « 1 cp matin et soir, tous les 2 jours, pendant 3 jours ». */
function libellePhase(p: PhaseCr): string {
  const cles = prisesTriees(p.prises);
  const noms = cles.map(k => PRISES[k] ? PRISES[k][0].toLowerCase() : `à ${heureCourte(k)}`);
  const quand = noms.length > 1 ? `${noms.slice(0, -1).join(', ')} et ${noms[noms.length - 1]}` : noms.join('');
  return [
    dosesParPrise(p)
      ? cles.map(k => [doseDe(p, k), quandPrise(k)].filter(Boolean).join(' ')).join(', ')
      : [p.dose.trim(), quand].filter(Boolean).join(' '),
    p.frequenceJours > 1 ? `tous les ${p.frequenceJours} jours` : '',
    p.dureeJours ? `pendant ${p.dureeJours} jour${p.dureeJours > 1 ? 's' : ''}` : 'au long cours',
  ].filter(Boolean).join(', ');
}
const posologieComplete = (t: TraitementCr) => t.phases.map(libellePhase).join(', puis ');

/** Champ texte + suggestions de la pharmacie dès la 1re lettre (saisie libre possible). */
function ChampPharmacie({ value, onChange, onChoix, articles, placeholder, courants = [] }: {
  value: string; onChange: (v: string) => void; onChoix: (a: ArticlePharmacie) => void;
  articles: ArticlePharmacie[]; placeholder: string;
  /** Liste courante proposée après la pharmacie (ex. vaccins usuels). */
  courants?: string[];
}) {
  const [ouvert, setOuvert] = useState(false);
  // Liste déroulante avec recherche : tout au focus, filtré à la frappe.
  const q = value.trim().toLowerCase();
  const ok = (n: string) => !q || n.toLowerCase().includes(q);
  const stock = articles.filter(a => ok(a.nom));
  const noms = new Set(stock.map(a => a.nom.toLowerCase()));
  const sugg: ArticlePharmacie[] = [
    ...stock,
    ...courants.filter(c => ok(c) && !noms.has(c.toLowerCase()))
      .map(c => ({ id: `c:${c}`, nom: c, categorie: '_courant', lot: null, quantite: null, unite: null })),
  ].slice(0, 40);
  return (
    <div className="relative">
      <input value={value} placeholder={placeholder}
        onChange={e => { onChange(e.target.value); setOuvert(true); }} onFocus={() => setOuvert(true)}
        onBlur={() => setTimeout(() => setOuvert(false), 150)}
        className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
      {ouvert && (sugg.length > 0 || articles.length === 0) && (
        <div className="absolute z-20 left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-y-auto max-h-64">
          {articles.length === 0 && (
            <p className="px-3 py-2 text-[11px] text-gray-400">Pharmacie vide — ajoutez vos produits dans Inventaire pour les retrouver ici (lot, stock).</p>
          )}
          {sugg.map(a => (
            <button key={a.id} type="button" onMouseDown={() => { onChoix(a); setOuvert(false); }}
              className="w-full text-left px-3 py-2 hover:bg-gray-50 border-b border-gray-50 last:border-0">
              <span className="block text-sm text-[#1E2025]">{a.categorie === 'vaccin' ? '💉' : '💊'} {a.nom}</span>
              {a.categorie !== '_courant' && (
                <span className="block text-[11px] text-gray-400">
                  {['Pharmacie', a.lot && `Lot ${a.lot}`, a.quantite != null && `Stock ${a.quantite} ${a.unite ?? ''}`.trim()].filter(Boolean).join(' · ')}
                </span>
              )}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

// ── Compte rendu vétérinaire : vaccins réalisés / traitements prescrits ──────
// → carnet de santé (rappels au propriétaire par les Cloud Functions sante.js)
// + ordonnance PDF. Miroir app : compte_rendu_page.dart (_blocActes).
const LIBELLES_CARNET: Record<string, string> = {
  vaccin: 'Vaccin', traitement: 'Traitement', vermifuge: 'Vermifuge', antiparasitaire: 'Antiparasitaire',
  allergie: 'Allergie / pathologie', chirurgie: 'Chirurgie', hospitalisation: 'Hospitalisation', radio: 'Examen',
};

function ActesCr({ vaccins, setVaccins, traitements, setTraitements, produits, setProduits, soins, setSoins, onSaisirCarnet, carnet = [], onRetirerCarnet, profileId, animalId }: {
  /** Inscrits au carnet aujourd'hui : affichés dans leur rubrique (« inscrit au carnet »). */
  carnet?: { cle: string; type: string; libelle: string }[];
  onRetirerCarnet?: (cle: string) => void;
  vaccins: VaccinCr[]; setVaccins: (v: VaccinCr[]) => void;
  traitements: TraitementCr[]; setTraitements: (t: TraitementCr[]) => void;
  produits: ProduitCr[]; setProduits: (p: ProduitCr[]) => void;
  soins: SoinCr[]; setSoins: (s: SoinCr[]) => void;
  /** Soin saisi avec le formulaire complet du carnet (même formulaire que la rubrique). */
  onSaisirCarnet?: (t: 'vermifuge' | 'antiparasitaire' | 'allergie' | 'chirurgie' | 'radio') => void;
  profileId: string | null;
  animalId?: string | null;
}) {
  const auj = new Date().toISOString().slice(0, 10);
  const carnetDe = (garde: (t: string) => boolean) => carnet.filter(a => garde(a.type)).map(a => (
    <div key={a.cle} className="flex items-center gap-2 rounded-xl border border-[#0C5C6C]/20 bg-[#0C5C6C]/5 px-3 py-2">
      <span className="flex-1 min-w-0">
        <span className="block text-sm font-semibold text-[#1E2025] truncate">{LIBELLES_CARNET[a.type] ?? a.type} : {a.libelle}</span>
        <span className="block text-[11px] text-gray-500">Inscrit au carnet — repris dans ce compte rendu</span>
      </span>
      {onRetirerCarnet && (
        <button type="button" title="Ne pas reprendre dans le compte rendu" aria-label={`Ne pas reprendre : ${a.libelle}`}
          onClick={() => onRetirerCarnet(a.cle)} className="text-gray-400 hover:text-gray-600 text-lg leading-none">×</button>
      )}
    </div>
  ));
  // Rappels de vaccins à faire : en retard ou dans les 30 jours (dernière
  // injection de chaque vaccin seulement — un rappel déjà fait n'apparaît plus).
  const [rappels, setRappels] = useState<{ vaccin: string; date: string | null; date_rappel: string }[]>([]);
  useEffect(() => {
    if (!animalId) return;
    supabase.from('vaccinations').select('vaccin, categorie, date, date_rappel').eq('animal_id', animalId)
      .order('date', { ascending: false, nullsFirst: false }).limit(200)
      .then(({ data }) => {
        const limite = plus(auj, 30);
        const vus = new Set<string>();
        const res: { vaccin: string; date: string | null; date_rappel: string }[] = [];
        for (const r of (data ?? []) as { vaccin?: string; categorie?: string; date?: string | null; date_rappel?: string | null }[]) {
          const cle = String(r.categorie || r.vaccin || '').toLowerCase();
          if (!cle || vus.has(cle)) continue;
          vus.add(cle);
          const dr = r.date_rappel ? String(r.date_rappel).slice(0, 10) : '';
          if (!dr || dr > limite) continue;
          res.push({ vaccin: r.vaccin || r.categorie || 'Vaccin', date: r.date ? String(r.date).slice(0, 10) : null, date_rappel: dr });
        }
        setRappels(res.sort((a, b) => a.date_rappel.localeCompare(b.date_rappel)));
      });
  }, [animalId, auj]);
  const rappelsAFaire = rappels.filter(r => !vaccins.some(v => v.nom.toLowerCase() === r.vaccin.toLowerCase()));
  /** Même intervalle qu'entre la dernière injection et son rappel (1 an à défaut). */
  const rappelSuivant = (r: { date: string | null; date_rappel: string }) => {
    if (!r.date || r.date_rappel <= r.date) return plus(auj, 0, 0, 1);
    const jours = Math.round((new Date(r.date_rappel + 'T12:00:00').getTime() - new Date(r.date + 'T12:00:00').getTime()) / 86400000);
    return plus(auj, jours);
  };
  const [vac, setVac] = useState<(VaccinCr & { index: number }) | null>(null);
  // Produit vendu en cours de saisie (quantité / prix en texte : virgule acceptée).
  const [prod, setProd] = useState<{ nom: string; quantite: string; prix: string; item_id: string | null; index: number } | null>(null);
  const [soin, setSoin] = useState<(SoinCr & { index: number }) | null>(null);
  const [trt, setTrt] = useState<(TraitementCr & { index: number }) | null>(null);
  // Délai libre du rappel ; unité de durée affichée par phase de traitement.
  const [dans, setDans] = useState('');
  const [dansUnite, setDansUnite] = useState<UniteDelai>('mois');
  const [unitesDuree, setUnitesDuree] = useState<Record<number, keyof typeof JOURS_PAR_UNITE>>({});
  const [pharmacie, setPharmacie] = useState<ArticlePharmacie[]>([]);
  useEffect(() => {
    if (!profileId) return;
    supabase.from('inventaire_items').select('id, nom, categorie, lot, quantite, unite, prix_vente').eq('eleveur_profile_id', profileId).order('nom')
      .then(({ data }) => setPharmacie((data ?? []) as ArticlePharmacie[]));
  }, [profileId]);

  const champ = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]';
  const chip = (sel: boolean) => `px-2.5 py-1 rounded-lg text-xs border ${sel ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-600 border-gray-200 hover:border-[#0C5C6C]'}`;
  const ligne = (icone: string, titre: string, sous: string, onEdit: () => void, onDelete: () => void, key: string) => (
    <div key={key} className="flex items-center gap-2.5 bg-white border border-[#0C5C6C]/25 rounded-xl px-3 py-2">
      <button type="button" onClick={onEdit} className="flex-1 min-w-0 flex items-center gap-2.5 text-left" title="Modifier">
        <span>{icone}</span>
        <span className="min-w-0">
          <span className="block text-sm font-semibold text-[#1E2025] truncate">{titre}</span>
          {sous && <span className="block text-xs text-gray-500">{sous}</span>}
        </span>
      </button>
      <button type="button" onClick={onEdit} className="text-gray-400 hover:text-[#0C5C6C] px-1" title="Modifier">✎</button>
      <button type="button" onClick={onDelete} className="text-gray-400 hover:text-gray-600 px-1" title="Retirer">✕</button>
    </div>
  );
  const majPhase = (i: number, p: Partial<PhaseCr>) => trt && setTrt({ ...trt, phases: trt.phases.map((x, j) => j === i ? { ...x, ...p } : x) });
  const remplacer = <T,>(liste: T[], i: number, v: T) => i >= 0 ? liste.map((x, j) => j === i ? v : x) : [...liste, v];

  return (
    <div className="space-y-3 rounded-2xl bg-[#0C5C6C]/5 p-3">
      {rappelsAFaire.length > 0 && (
        <div className="space-y-1.5">
          <p className="text-xs font-semibold text-gray-600">Rappels de vaccins à faire</p>
          <div className="rounded-xl border border-[#F0D9B5] bg-[#FFF7EC] divide-y divide-[#F0D9B5]">
            {rappelsAFaire.map(r => {
              const j = Math.round((new Date(r.date_rappel + 'T12:00:00').getTime() - new Date(auj + 'T12:00:00').getTime()) / 86400000);
              const dateFr = new Date(r.date_rappel + 'T12:00:00').toLocaleDateString('fr-FR');
              return (
                <div key={r.vaccin} className="flex items-center gap-2 px-3 py-2">
                  <span className="flex-1 min-w-0">
                    <span className="block text-sm font-semibold text-[#1E2025] truncate">{r.vaccin}</span>
                    <span className={`block text-xs ${j < 0 ? 'text-red-700' : 'text-gray-600'}`}>
                      {j < 0 ? `En retard depuis le ${dateFr}` : j === 0 ? 'Rappel aujourd’hui' : `Rappel le ${dateFr} (dans ${j} j)`}
                    </span>
                  </span>
                  <button type="button" title="Faire le rappel" aria-label={`Faire le rappel : ${r.vaccin}`}
                    onClick={() => setVac({ nom: r.vaccin, lot: '', date: auj, rappel: rappelSuivant(r), index: -1 })}
                    className="w-8 h-8 rounded-full border border-[#0C5C6C] text-[#0C5C6C] font-bold text-lg leading-none flex items-center justify-center hover:bg-[#0C5C6C]/10">+</button>
                </div>
              );
            })}
          </div>
        </div>
      )}
      <div className="space-y-2">
        <p className="text-xs font-semibold text-gray-600">💉 Vaccins réalisés</p>
        {vaccins.map((v, i) => ligne('💉', v.nom, [v.lot && `Lot ${v.lot}`, v.rappel && `Rappel le ${new Date(v.rappel + 'T12:00:00').toLocaleDateString('fr-FR')}`].filter(Boolean).join(' · '),
          () => setVac({ ...v, index: i }), () => setVaccins(vaccins.filter((_, j) => j !== i)), `v${i}`))}
        {carnetDe(t => t === 'vaccin')}
        {vac ? (
          <div className="bg-white rounded-xl border border-gray-200 p-3 space-y-2">
            <ChampPharmacie value={vac.nom} onChange={nom => setVac({ ...vac, nom })} placeholder="Vaccin (nom / marque) *"
              articles={pharmacie.filter(a => a.categorie === 'vaccin')}
              onChoix={a => setVac({ ...vac, nom: a.nom, lot: a.lot ?? vac.lot })} courants={VACCINS_COURANTS} />
            <input value={vac.lot} onChange={e => setVac({ ...vac, lot: e.target.value })} placeholder="N° de lot" className={champ} />
            <p className="text-xs text-gray-500">Prochain rappel (le propriétaire sera prévenu)</p>
            <div className="flex flex-wrap gap-1.5">
              {([['3 semaines', plus(vac.date, 21)], ['1 mois', plus(vac.date, 0, 1)], ['6 mois', plus(vac.date, 0, 6)],
                 ['1 an', plus(vac.date, 0, 0, 1)], ['3 ans', plus(vac.date, 0, 0, 3)], ['Aucun', null]] as const).map(([l, d]) => (
                <button key={l} type="button" onClick={() => { setVac({ ...vac, rappel: d }); setDans(''); }} className={chip(vac.rappel === d)}>{l}</button>
              ))}
            </div>
            {/* Délai libre jusqu'au prochain rappel. */}
            <div className="flex items-center gap-2 text-sm text-[#1E2025]">
              Ou dans
              <input type="number" min={1} inputMode="numeric" value={dans} aria-label="Délai avant le rappel"
                onChange={e => { setDans(e.target.value); const r = delaiRappel(vac.date, e.target.value, dansUnite); if (r) setVac({ ...vac, rappel: r }); }}
                className="w-16 text-center border border-gray-200 rounded-xl px-2 py-1.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              <select value={dansUnite} aria-label="Unité"
                onChange={e => { const u = e.target.value as UniteDelai; setDansUnite(u); const r = delaiRappel(vac.date, dans, u); if (r) setVac({ ...vac, rappel: r }); }}
                className="border border-gray-200 rounded-xl px-2 py-1.5 text-sm bg-white focus:outline-none focus:border-[#0C5C6C]">
                {(['jours', 'semaines', 'mois', 'ans'] as const).map(u => <option key={u} value={u}>{u}</option>)}
              </select>
            </div>
            {vac.rappel && <p className="text-xs font-semibold text-[#0C5C6C]">Rappel le {new Date(vac.rappel + 'T12:00:00').toLocaleDateString('fr-FR')}</p>}
            <div className="flex gap-2">
              <button type="button" onClick={() => setVac(null)} className="flex-1 py-2 rounded-xl text-sm border border-gray-200 text-gray-600">Annuler</button>
              <button type="button" disabled={!vac.nom.trim()} onClick={() => {
                const { index, ...v } = vac;
                setVaccins(remplacer(vaccins, index, { ...v, nom: v.nom.trim(), lot: v.lot.trim() })); setVac(null);
              }} className="flex-1 py-2 rounded-xl text-sm text-white font-semibold bg-[#0C5C6C] disabled:opacity-40">
                {vac.index >= 0 ? 'Enregistrer' : 'Ajouter'}
              </button>
            </div>
          </div>
        ) : (
          <button type="button" onClick={() => setVac({ nom: '', lot: '', date: auj, rappel: plus(auj, 0, 0, 1), index: -1 })}
            className="text-sm font-semibold text-[#0C5C6C]">＋ Ajouter un vaccin</button>
        )}
      </div>

      <div className="space-y-2">
        <p className="text-xs font-semibold text-gray-600">💊 Traitements prescrits</p>
        {traitements.map((t, i) => ligne('💊', t.nom, [posologieComplete(t), t.rappels ? 'rappels au propriétaire' : ''].filter(Boolean).join(' · '),
          () => setTrt({ ...t, index: i }), () => setTraitements(traitements.filter((_, j) => j !== i)), `t${i}`))}
        {carnetDe(t => t === 'traitement')}
        {trt ? (
          <div className="bg-white rounded-xl border border-gray-200 p-3 space-y-2">
            <ChampPharmacie value={trt.nom} onChange={nom => setTrt({ ...trt, nom })} placeholder="Médicament *"
              articles={pharmacie.filter(a => a.categorie !== 'vaccin' && a.categorie !== 'alimentation' && a.categorie !== 'antiparasitaire')}
              courants={MEDICAMENTS_COURANTS}
              onChoix={a => setTrt({ ...trt, nom: a.nom })} />
            <div className="flex flex-wrap gap-1.5">
              {[['medicament', 'Médicament'], ['autre', 'Autre']].map(([k, l]) => (
                <button key={k} type="button" onClick={() => setTrt({ ...trt, type: k })} className={chip(trt.type === k)}>{l}</button>
              ))}
            </div>
            <AideEtapes mot="phase" />
            {trt.phases.map((p, i) => (
              <div key={i} className="rounded-xl border border-gray-200 bg-[#F6F8F7] p-2.5 space-y-2">
                <div className="flex items-center">
                  <span className="flex-1 text-xs font-bold text-[#1E2025]">{trt.phases.length > 1 ? `Phase ${i + 1}` : 'Posologie'}</span>
                  {trt.phases.length > 1 && (
                    <button type="button" onClick={() => setTrt({ ...trt, phases: trt.phases.filter((_, j) => j !== i) })} className="text-gray-400 px-1">✕</button>
                  )}
                </div>
                {!dosesParPrise(p) && (
                  <input value={p.dose} onChange={e => majPhase(i, { dose: e.target.value })} placeholder="Dose par prise — ex. 1 cp, ½ cp, 2 mL, 1 pipette" className={champ} />
                )}
                <div className="flex flex-wrap gap-1.5">
                  {Object.entries(PRISES).map(([k, [l, h]]) => (
                    <button key={k} type="button" className={chip(p.prises.includes(k))}
                      onClick={() => majPhase(i, { prises: p.prises.includes(k) ? p.prises.filter(x => x !== k) : [...p.prises, k] })}>{l} · {heureCourte(h)}</button>
                  ))}
                  {/* Heures libres (plus de 3 prises par jour, horaire précis). */}
                  {prisesTriees(p.prises).filter(k => !PRISES[k]).map(k => (
                    <button key={k} type="button" className={chip(true)} title="Retirer cette prise"
                      onClick={() => majPhase(i, { prises: p.prises.filter(x => x !== k) })}>{nomPrise(k)} ×</button>
                  ))}
                  <label className="inline-flex items-center gap-1 text-xs font-semibold text-[#0C5C6C]">
                    + Autre heure
                    <input type="time" aria-label="Ajouter une prise à une autre heure" className="border border-gray-200 rounded-lg px-1.5 py-1 text-xs"
                      onChange={e => { const h = e.target.value; if (/^\d{2}:\d{2}$/.test(h) && !p.prises.includes(h)) majPhase(i, { prises: [...p.prises, h] }); e.target.value = ''; }} />
                  </label>
                </div>
                {/* Dose propre à chaque prise (1 cp le matin, ½ cp le soir…). */}
                {p.prises.length > 1 && (
                  <label className="flex items-center gap-2 text-sm text-[#1E2025]">
                    <input type="checkbox" checked={!!p.doses} className="accent-[#0C5C6C]"
                      onChange={e => majPhase(i, e.target.checked
                        ? { doses: Object.fromEntries(p.prises.map(k => [k, p.dose])) }
                        : { doses: undefined, dose: p.dose.trim() || Object.values(p.doses ?? {}).find(d => d.trim()) || '' })} />
                    Dose différente selon la prise
                  </label>
                )}
                {/* Une ligne par prise : moment + heure à gauche, dose à droite. */}
                {dosesParPrise(p) && prisesTriees(p.prises).map(k => (
                  <div key={k} className="flex items-center gap-2">
                    <span className="w-32 shrink-0 text-sm font-semibold text-[#1E2025]">{nomPrise(k)} · {heureCourte(heurePrise(k))}</span>
                    <input value={p.doses?.[k] ?? ''} aria-label={`Dose ${nomPrise(k).toLowerCase()}`}
                      onChange={e => majPhase(i, { doses: { ...p.doses, [k]: e.target.value } })}
                      placeholder="Dose — ex. 1 cp, ½ cp" className={champ} />
                  </div>
                ))}
                {/* Intervalle libre : une prise tous les N jours. */}
                <div className="flex items-center gap-2 text-sm text-[#1E2025]">
                  Tous les
                  <input type="number" min={1} inputMode="numeric" value={p.frequenceJours}
                    onChange={e => majPhase(i, { frequenceJours: Math.max(1, parseInt(e.target.value, 10) || 1) })}
                    className="w-16 text-center border border-gray-200 rounded-xl px-2 py-1.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                  {p.frequenceJours > 1 ? 'jours' : 'jour (tous les jours)'}
                </div>
                {/* Durée libre (jours / semaines / mois) ou durées courantes. */}
                <div className="flex items-center gap-2 text-sm text-[#1E2025]">
                  Pendant
                  <input type="number" min={1} inputMode="numeric" aria-label="Durée"
                    value={p.dureeJours == null ? '' : (unitesDuree[i] ?? 'jours') === 'jours' ? p.dureeJours : Math.round(p.dureeJours / JOURS_PAR_UNITE[unitesDuree[i] ?? 'jours'])}
                    onChange={e => { const n = parseInt(e.target.value, 10); majPhase(i, { dureeJours: n > 0 ? n * JOURS_PAR_UNITE[unitesDuree[i] ?? 'jours'] : null }); }}
                    className="w-16 text-center border border-gray-200 rounded-xl px-2 py-1.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                  <select value={unitesDuree[i] ?? 'jours'} aria-label="Unité de durée"
                    onChange={e => {
                      const u = e.target.value as keyof typeof JOURS_PAR_UNITE;
                      const n = p.dureeJours == null ? null : Math.round(p.dureeJours / JOURS_PAR_UNITE[unitesDuree[i] ?? 'jours']);
                      setUnitesDuree({ ...unitesDuree, [i]: u });
                      if (n) majPhase(i, { dureeJours: n * JOURS_PAR_UNITE[u] });
                    }}
                    className="border border-gray-200 rounded-xl px-2 py-1.5 text-sm bg-white focus:outline-none focus:border-[#0C5C6C]">
                    {(['jours', 'semaines', 'mois'] as const).map(u => <option key={u} value={u}>{u}</option>)}
                  </select>
                </div>
                <div className="flex flex-wrap items-center gap-1.5">
                  {[3, 5, 7, 10, 14].map(n => <button key={n} type="button" onClick={() => { majPhase(i, { dureeJours: n }); setUnitesDuree({ ...unitesDuree, [i]: 'jours' }); }} className={chip(p.dureeJours === n)}>{n} j</button>)}
                  {i === trt.phases.length - 1 && (
                    <button type="button" onClick={() => majPhase(i, { dureeJours: null })} className={chip(p.dureeJours === null)}>Au long cours</button>
                  )}
                </div>
                {/* Rythme impossible : une prise tous les 100 jours pendant 17 jours. */}
                {p.dureeJours != null && p.frequenceJours > p.dureeJours && (
                  <p className="text-xs text-red-600 bg-red-50 rounded-xl px-3 py-2">
                    Une prise tous les {p.frequenceJours} jours ne tient pas dans {p.dureeJours} jour{p.dureeJours > 1 ? 's' : ''} de traitement — le rythme doit être inférieur ou égal à la durée.
                  </p>
                )}
              </div>
            ))}
            <button type="button" className="text-sm font-semibold text-[#0C5C6C]"
              onClick={() => {
                const der = trt.phases[trt.phases.length - 1];
                setTrt({ ...trt, phases: [...trt.phases.map((x, j) => j === trt.phases.length - 1 && !x.dureeJours ? { ...x, dureeJours: 3 } : x),
                  { dose: '', prises: [...der.prises], frequenceJours: der.frequenceJours, dureeJours: der.dureeJours ?? 3 }] });
              }}>📉 Ajouter une phase (dose dégressive)</button>
            <label className="flex items-center gap-2 text-sm text-[#1E2025]">
              <input type="checkbox" checked={trt.rappels} onChange={e => setTrt({ ...trt, rappels: e.target.checked })} className="w-4 h-4 accent-[#0C5C6C]" />
              Rappeler chaque prise au propriétaire (matin 8 h · midi 12 h · soir 19 h)
            </label>
            <input value={trt.notes} onChange={e => setTrt({ ...trt, notes: e.target.value })} placeholder="Remarque (facultatif) — précautions, à jeun…" className={champ} />
            <div className="flex gap-2">
              <button type="button" onClick={() => setTrt(null)} className="flex-1 py-2 rounded-xl text-sm border border-gray-200 text-gray-600">Annuler</button>
              <button type="button" disabled={!trt.nom.trim() || trt.phases.some(p => p.prises.length === 0 || (p.dureeJours != null && p.frequenceJours > p.dureeJours))} onClick={() => {
                const { index, ...t } = trt;
                setTraitements(remplacer(traitements, index, { ...t, nom: t.nom.trim(), notes: t.notes.trim() })); setTrt(null);
              }} className="flex-1 py-2 rounded-xl text-sm text-white font-semibold bg-[#0C5C6C] disabled:opacity-40">
                {trt.index >= 0 ? 'Enregistrer' : 'Ajouter'}
              </button>
            </div>
          </div>
        ) : (
          <button type="button" onClick={() => setTrt({ nom: '', type: 'medicament', rappels: true, notes: '', index: -1,
            phases: [{ dose: '1 cp', prises: ['matin', 'soir'], frequenceJours: 1, dureeJours: 7 }] })}
            className="text-sm font-semibold text-[#0C5C6C]">＋ Ajouter un traitement</button>
        )}
        {traitements.length > 0 && (
          <p className="text-[11px] text-gray-500">📄 L&apos;ordonnance sera générée en PDF et ajoutée aux documents de l&apos;animal.</p>
        )}
      </div>
      <p className="text-[11px] text-gray-500">Cliquez une ligne pour la modifier. Inscrits au carnet de santé ; le propriétaire reçoit les rappels.</p>
      <div className="space-y-2">
        <p className="text-xs font-semibold text-gray-600">Autres soins (inscrits au carnet)</p>
        {soins.map((s, i) => ligne('', `${SOINS_LIBELLES[s.type]} : ${s.nom}`,
          [s.detail, s.rappel_mois ? `rappel dans ${s.rappel_mois} mois` : ''].filter(Boolean).join(' · '),
          () => setSoin({ ...s, index: i }), () => setSoins(soins.filter((_, j) => j !== i)), `s${i}`))}
        {carnetDe(t => t !== 'vaccin' && t !== 'traitement')}
        {soin ? (
          <div className="bg-white rounded-xl border border-gray-200 p-3 space-y-2">
            <div className="flex flex-wrap gap-1.5">
              {(Object.keys(SOINS_LIBELLES) as SoinCr['type'][]).map(t => (
                <button key={t} type="button" className={chip(soin.type === t)}
                  onClick={() => setSoin({ ...soin, type: t, rappel_mois: t === 'vermifuge' || t === 'antiparasitaire' ? soin.rappel_mois : null })}>{SOINS_LIBELLES[t]}</button>
              ))}
            </div>
            {soin.type === 'vermifuge' || soin.type === 'antiparasitaire' ? (
              <ChampPharmacie value={soin.nom} onChange={nom => setSoin({ ...soin, nom })} placeholder="Produit *"
                articles={pharmacie.filter(a => a.categorie !== 'vaccin' && a.categorie !== 'alimentation')}
                onChoix={a => setSoin({ ...soin, nom: a.nom })} />
            ) : (
              <input value={soin.nom} onChange={e => setSoin({ ...soin, nom: e.target.value })} className={champ}
                placeholder={soin.type === 'allergie' ? 'Allergie / pathologie *' : soin.type === 'radio' ? 'Examen (radio, échographie, prise de sang…) *' : 'Intervention *'} />
            )}
            <input value={soin.detail} onChange={e => setSoin({ ...soin, detail: e.target.value })} className={champ}
              placeholder={soin.type === 'vermifuge' ? 'Dosage (facultatif)' : soin.type === 'antiparasitaire' ? 'Fréquence / posologie (facultatif)'
                : soin.type === 'allergie' ? 'Sévérité (facultatif)' : soin.type === 'radio' ? 'Résultats / observations (facultatif)' : 'Notes (facultatif)'} />
            {(soin.type === 'vermifuge' || soin.type === 'antiparasitaire') && (
              <>
                <p className="text-xs text-gray-500">Prochain rappel (le propriétaire sera prévenu)</p>
                <div className="flex flex-wrap gap-1.5">
                  {([null, 1, 3, 6, 12] as const).map(m => (
                    <button key={String(m)} type="button" className={chip((soin.rappel_mois ?? null) === m)}
                      onClick={() => setSoin({ ...soin, rappel_mois: m })}>{m == null ? 'Aucun' : m === 12 ? '1 an' : `${m} mois`}</button>
                  ))}
                </div>
              </>
            )}
            <div className="flex gap-2">
              <button type="button" onClick={() => setSoin(null)} className="flex-1 py-2 rounded-xl text-sm border border-gray-200 text-gray-600">Annuler</button>
              <button type="button" disabled={!soin.nom.trim()} onClick={() => {
                const { index, ...s } = soin;
                const ok: SoinCr = { ...s, nom: s.nom.trim(), detail: s.detail.trim() };
                setSoins(index >= 0 ? soins.map((x, j) => j === index ? ok : x) : [...soins, ok]); setSoin(null);
              }} className="flex-1 py-2 rounded-xl text-sm text-white font-semibold bg-[#0C5C6C] disabled:opacity-40">
                {soin.index >= 0 ? 'Enregistrer' : 'Ajouter'}
              </button>
            </div>
          </div>
        ) : (
          onSaisirCarnet ? (
            <div className="space-y-1.5">
              <p className="text-xs text-gray-500">Ajouter avec le formulaire complet du carnet :</p>
              <div className="flex flex-wrap gap-1.5">
                {([['vermifuge', 'Vermifuge'], ['antiparasitaire', 'Antiparasitaire'], ['allergie', 'Allergie / pathologie'],
                   ['chirurgie', 'Chirurgie / hospitalisation'], ['radio', 'Radio / examen']] as const).map(([t, l]) => (
                  <button key={t} type="button" onClick={() => onSaisirCarnet(t)} className={chip(false)}>＋ {l}</button>
                ))}
              </div>
            </div>
          ) : (
            <button type="button" onClick={() => setSoin({ type: 'vermifuge', nom: '', detail: '', rappel_mois: null, index: -1 })}
              className="text-sm font-semibold text-[#0C5C6C]">＋ Ajouter un soin (vermifuge, allergie, chirurgie, examen…)</button>
          )
        )}
      </div>
      <div className="space-y-2">
        <p className="text-xs font-semibold text-gray-600">Produits vendus (non administrés)</p>
        {produits.map((p, i) => ligne('', libelleProduit(p),
          p.prix == null ? 'Prix du stock ou à compléter sur la facture' : `${(p.prix * p.quantite).toFixed(2)} € TTC`,
          () => setProd({ nom: p.nom, quantite: String(p.quantite).replace('.', ','), prix: p.prix == null ? '' : p.prix.toFixed(2).replace('.', ','), item_id: p.item_id ?? null, index: i }),
          () => setProduits(produits.filter((_, j) => j !== i)), `p${i}`))}
        {prod ? (
          <div className="bg-white rounded-xl border border-gray-200 p-3 space-y-2">
            <ChampPharmacie value={prod.nom} onChange={nom => setProd({ ...prod, nom, item_id: null })} placeholder="Produit (stock ou saisie libre) *"
              articles={pharmacie.filter(a => a.categorie !== 'vaccin')}
              onChoix={a => setProd({ ...prod, nom: a.nom, item_id: a.id, prix: a.prix_vente != null ? Number(a.prix_vente).toFixed(2).replace('.', ',') : prod.prix })} />
            {prod.item_id && (() => {
              const a = pharmacie.find(x => x.id === prod.item_id);
              return a?.quantite != null ? <p className="text-xs text-gray-500">En stock : {a.quantite} {a.unite ?? ''}</p> : null;
            })()}
            <div className="flex gap-2">
              <input value={prod.quantite} onChange={e => setProd({ ...prod, quantite: e.target.value })} inputMode="decimal" placeholder="Quantité" aria-label="Quantité" className={`${champ} w-24`} />
              <input value={prod.prix} onChange={e => setProd({ ...prod, prix: e.target.value })} inputMode="decimal" placeholder="Prix unitaire TTC (€)" aria-label="Prix unitaire TTC" className={champ} />
            </div>
            <div className="flex gap-2">
              <button type="button" onClick={() => setProd(null)} className="flex-1 py-2 rounded-xl text-sm border border-gray-200 text-gray-600">Annuler</button>
              <button type="button" disabled={!prod.nom.trim() || !(parseFloat(prod.quantite.replace(',', '.')) > 0)} onClick={() => {
                const prixNum = parseFloat(prod.prix.replace(',', '.').replace(/\s/g, ''));
                const p: ProduitCr = { nom: prod.nom.trim(), quantite: parseFloat(prod.quantite.replace(',', '.')), prix: isNaN(prixNum) ? null : prixNum, item_id: prod.item_id };
                setProduits(prod.index >= 0 ? produits.map((x, j) => j === prod.index ? p : x) : [...produits, p]); setProd(null);
              }} className="flex-1 py-2 rounded-xl text-sm text-white font-semibold bg-[#0C5C6C] disabled:opacity-40">
                {prod.index >= 0 ? 'Enregistrer' : 'Ajouter'}
              </button>
            </div>
          </div>
        ) : (
          <button type="button" onClick={() => setProd({ nom: '', quantite: '1', prix: '', item_id: null, index: -1 })}
            className="text-sm font-semibold text-[#0C5C6C]">＋ Ajouter un produit vendu</button>
        )}
        <p className="text-[11px] text-gray-500">Ajoutés à la facture et décomptés du stock à l’enregistrement ; pas inscrits au carnet.</p>
      </div>
      {/* Récapitulatif de la consultation */}
      {(vaccins.length + traitements.length + soins.length + produits.length + carnet.length) > 0 && (
        <div className="space-y-1">
          <p className="text-xs font-semibold text-gray-600">Fait pendant cette consultation</p>
          <ul className="rounded-xl border border-gray-200 bg-white px-3 py-2 text-sm text-[#1E2025] space-y-0.5">
            {[
              ...vaccins.map(v => `Vaccin : ${v.nom}${v.lot ? ` (lot ${v.lot})` : ''}`),
              ...traitements.map(t => `Traitement : ${t.nom}`),
              ...soins.map(x => `${SOINS_LIBELLES[x.type]} : ${x.nom}`),
              ...carnet.map(a => `${LIBELLES_CARNET[a.type] ?? a.type} : ${a.libelle}`),
              ...produits.map(p => `Produit vendu : ${libelleProduit(p)}`),
            ].map((l, i) => <li key={i}>• {l}</li>)}
          </ul>
        </div>
      )}
    </div>
  );
}

function PatientDetailPageInner() {
  const { user, userData } = useAuth();
  // Espace employé : documents au nom de la clinique (proUid = titulaire),
  // rédigés / prescrits par l'employé (son profil dans la clinique).
  const esp = useEspaceClinique();
  const proUid = esp.uid;
  const router = useRouter();
  const params = useParams();
  const searchParams = useSearchParams();
  const animalId = params.id as string;
  const activeProfileId = useActiveProfile();

  const [catPro, setCatPro] = useState('');
  const [tab, setTab] = useState(searchParams.get('tab') ?? 'Identité');
  const [animal, setAnimal] = useState<Animal | null>(null);
  const [owner, setOwner] = useState<Owner | null>(null);
  const [grant, setGrant] = useState<Grant | null>(null);
  const [loading, setLoading] = useState(true);
  const [alimentation, setAlimentation] = useState<AlimentationEntry | null>(null);

  // Santé
  const [vaccins, setVaccins] = useState<VaccinEntry[]>([]);
  const [visites, setVisites] = useState<VisiteEntry[]>([]);
  const [traitements, setTraitements] = useState<TraitementEntry[]>([]);
  const [vermifuges, setVermifuges] = useState<VermifugeEntry[]>([]);
  const [antiparasitaires, setAntiparasitaires] = useState<AntiparasitaireEntry[]>([]);
  const [chirurgies, setChirurgies] = useState<ChirurgieEntry[]>([]);
  const [allergies, setAllergies] = useState<AllergieEntry[]>([]);
  // Consultations (soignants)
  const [comptesRendus, setComptesRendus] = useState<CompteRendu[]>([]);
  const [ordonnances, setOrdonnances] = useState<Ordonnance[]>([]);
  const [radios, setRadios] = useState<RadioEntry[]>([]);
  // Repro
  const [chaleurs, setChaleurs] = useState<Chaleur[]>([]);
  const [saillies, setSaillies] = useState<Saillie[]>([]);
  const [gestations, setGestations] = useState<Gestation[]>([]);
  // Éducation (rapports de séance + exercices conseillés)
  const [rapports, setRapports] = useState<RapportEduP[]>([]);
  const [objectifs, setObjectifs] = useState<EducObjectif[]>([]);
  const [objForm, setObjForm] = useState<{ id?: string; libelle: string; categorie: string; statut: string; note: string; prioritaire?: boolean; difficultes?: string } | null>(null);
  const [savingObj, setSavingObj] = useState(false);
  const [biblio, setBiblio] = useState<EducExercice[]>([]);
  const [attribues, setAttribues] = useState<EducAttribue[]>([]);
  const [retours, setRetours] = useState<Record<string, EducRetour[]>>({});
  const [replyFor, setReplyFor] = useState<string | null>(null);
  const [replyNote, setReplyNote] = useState('');
  // Durée : jours (null = jusqu'à validation, -1 = date choisie) ; nbValidations : réussites (exercices sans étapes).
  const [attrPicker, setAttrPicker] = useState<{ ids: Set<string>; cadence: string; echeance: string; rappels: boolean; duree: number | null; nbValidations: number } | null>(null);
  const [savingAttr, setSavingAttr] = useState(false);
  const [showAddRapport, setShowAddRapport] = useState(false);
  const [rapportContenu, setRapportContenu] = useState('');
  const [rapportExercices, setRapportExercices] = useState('');
  const [rapportType, setRapportType] = useState<'seance' | 'bilan'>('seance');
  // Compte rendu de séance complet (migration_education_fiche.sql).
  const [seanceType, setSeanceType] = useState('individuelle');
  const [seanceLieu, setSeanceLieu] = useState('');
  const [seanceDuree, setSeanceDuree] = useState('');
  const [seanceObjs, setSeanceObjs] = useState<string[]>([]);
  // Compte rendu : nouvel objectif saisi librement, exercices de la
  // bibliothèque joints (exercices_attribues.progression_id).
  const [nouvelObjSeance, setNouvelObjSeance] = useState('');
  const [ajoutObjSeance, setAjoutObjSeance] = useState(false);
  const [crExos, setCrExos] = useState<string[]>([]);
  const [crExosOuvert, setCrExosOuvert] = useState(false);
  const [seanceDetaille, setSeanceDetaille] = useState(false);
  const [seanceComport, setSeanceComport] = useState('');
  const [seanceDiff, setSeanceDiff] = useState('');
  const [seanceProchaine, setSeanceProchaine] = useState('');
  const [seanceRdvId, setSeanceRdvId] = useState<string | null>(null);
  const [prochainRdv, setProchainRdv] = useState<{ date_heure: string; motif: string | null; lieu: string | null } | null>(null);
  // Fiche pet-sitter : prestations (rdv), clés, comptes rendus express.
  const [gardeRdvs, setGardeRdvs] = useState<GardeRdvFiche[]>([]);
  const [gardeCles, setGardeCles] = useState<{ id: string; description: string | null; statut: string | null }[]>([]);
  const [gardeCrs, setGardeCrs] = useState<{ id: string; note: string | null; photo_url: string | null; created_at: string; incident?: boolean | null; rdv_id?: string | null }[]>([]);
  const [crRdv, setCrRdv] = useState<GardeRdvFiche | null>(null);
  // Motif de l'accompagnement saisi depuis la Synthèse (education_suivis).
  const [motifSuivi, setMotifSuivi] = useState<string | null>(null);
  const [motifEdit, setMotifEdit] = useState<string | null>(null);
  const [bilanMotif, setBilanMotif] = useState('');
  const [bilanReco, setBilanReco] = useState('');
  const [bilanNb, setBilanNb] = useState('');
  const [bilanForfait, setBilanForfait] = useState('');
  const [forfaitsEdu, setForfaitsEdu] = useState<{ id: string; nom: string; nb_seances: number; prix: number }[]>([]);
  // Après l'envoi d'un bilan : lien vers le devis pré-rempli (forfait conseillé + objectifs en note).
  const [devisPrefillUrl, setDevisPrefillUrl] = useState<string | null>(null);
  const [forfaitsSous, setForfaitsSous] = useState<ForfaitSous[]>([]);
  // Depuis le dossier de la séance : « Appliquer un forfait » ouvre le formulaire.
  const [showForfaitSousForm, setShowForfaitSousForm] = useState(() => searchParams.get('forfait') === '1');
  const [imputerForfait, setImputerForfait] = useState(true);
  const [savingRapport, setSavingRapport] = useState(false);
  const [editingRapportId, setEditingRapportId] = useState<string | null>(null);
  const [deleteRapportConfirmId, setDeleteRapportConfirmId] = useState<string | null>(null);

  // Add entry form
  type AddType = null | 'vaccin' | 'visite' | 'traitement' | 'ordonnance' | 'radio' | 'cr' | 'mesure'
    | 'vermifuge' | 'antiparasitaire' | 'chirurgie' | 'allergie';
  const [addingType, setAddingType] = useState<AddType>(null);
  // Brouillon de compte rendu repris (ligne modifiée au lieu d'en créer une).
  const [brouillonId, setBrouillonId] = useState<string | null>(null);
  // RDV à plusieurs animaux (?crRdv=<id>, « Gérer mes RDV ») : le compte rendu
  // de cet animal est rattaché au RDV (rdv_id) pour la facture de la visite.
  const [crRdvId, setCrRdvId] = useState<string | null>(null);
  // « Compte rendu fait » depuis un RDV : ce compte rendu, ouvert dans Consultations.
  const [crCible, setCrCible] = useState<string | null>(() => searchParams.get('cr'));
  // Ma signature (signatures_pro), apposée sur les CR et ordonnances.
  const [signature, setSignature] = useState<string | null | undefined>(undefined);
  const [signer, setSigner] = useState(false);
  useEffect(() => {
    if (!user?.uid || catPro !== 'veterinaire') return;
    maSignaturePro(user.uid).then(setSignature).catch(() => setSignature(null));
  }, [user?.uid, catPro]);
  const [visite, setVisite] = useState<{ rdvId: string; animaux: AnimalRdv[]; etats: Record<string, 'fait' | 'brouillon'> } | null>(null);
  const chargerVisite = useCallback(async (rdvId: string) => {
    const { data: r } = await supabase.from('rdv').select('animaux_detail').eq('id', rdvId).maybeSingle();
    const animaux = animauxDetailRdv((r ?? {}) as { animaux_detail?: unknown });
    if (animaux.length === 0) { setVisite(null); return; }
    // Comptes rendus du RDV, y compris ceux faits depuis la fiche le jour du RDV.
    const crs = await crsDuRdv(rdvId, animaux.map(a => a.id));
    const etats: Record<string, 'fait' | 'brouillon'> = {};
    for (const c of (crs ?? []) as { animal_id: string | null; statut: string | null }[]) {
      const id = String(c.animal_id ?? '');
      if (etats[id] !== 'fait') etats[id] = c.statut === 'brouillon' ? 'brouillon' : 'fait';
    }
    setVisite({ rdvId, animaux, etats });
  }, []);
  // Compte rendu déjà préparé pour « RDV|animal » (et non une seule fois par
  // page : en passant d'un animal à l'autre, la page peut être réutilisée).
  const crRdvOuvert = useRef('');
  // Compte rendu validé rouvert dans le formulaire (« Modifier ») : la ligne
  // est mise à jour, et ce qui n'est pas repris dans les champs (vaccins,
  // traitements, examens… déjà dans le texte) est conservé.
  const [crEdition, setCrEdition] = useState<null | { cr: CompteRendu; conserve: { titre: string; corps: string }[] }>(null);
  // Après un compte rendu : page suivante déjà choisie (facture, animal suivant).
  const navigationSuivie = useRef(false);
  // Soin saisi depuis le compte rendu avec le formulaire complet du carnet :
  // la saisie du CR est mise de côté puis reprise (le soin apparaît alors
  // dans « Déjà inscrit au carnet aujourd'hui »).
  const [retourCr, setRetourCr] = useState<null | {
    motif: string; notes: string; diag: string; poids: string; actes: string[]; vaccins: VaccinCr[];
    traitements: TraitementCr[]; produits: ProduitCr[]; soins: SoinCr[]; brouillonId: string | null; demande: string;
  }>(null);
  // Synthèse rechargée après une saisie (rappel fait depuis la Synthèse).
  const [syntheseMaj, setSyntheseMaj] = useState(0);
  const [showAddMenu, setShowAddMenu] = useState(false);
  const [formDate, setFormDate] = useState(() => new Date().toISOString().slice(0, 10));
  const [formMotif, setFormMotif] = useState('');
  const [formDiag, setFormDiag] = useState('');
  const [formNotes, setFormNotes] = useState('');
  const [formNom, setFormNom] = useState('');
  const [formLot, setFormLot] = useState('');
  const [formRappel, setFormRappel] = useState('');
  const [formPosologie, setFormPosologie] = useState('');
  const [formDateFin, setFormDateFin] = useState('');
  const [formTitre, setFormTitre] = useState('');
  // vermifuge/antiparasitaire/chirurgie/allergie
  const [formDosage, setFormDosage] = useState('');
  const [formFrequence, setFormFrequence] = useState('');
  // Vermifuge / antiparasitaire : fréquence en chiffre + unité (rappel calculé),
  // durée de prise et rappels à chaque prise — mêmes options que le carnet du propriétaire.
  const [freqN, setFreqN] = useState('');
  const [freqU, setFreqU] = useState<'jour' | 'semaine' | 'mois' | 'an'>('mois');
  const [optsVerm, setOptsVerm] = useState<OptionsVermifuge>(optionsVermifugeVides());
  // Radio / examen : fichier joint (image ou PDF).
  const [formFichier, setFormFichier] = useState<File | null>(null);
  function appliquerFrequence(nTxt: string, u: 'jour' | 'semaine' | 'mois' | 'an') {
    const n = parseInt(nTxt, 10);
    if (!(n > 0)) { setFormFrequence(''); return; }
    setFormFrequence(`${n} ${u === 'jour' ? (n > 1 ? 'jours' : 'jour') : u === 'semaine' ? (n > 1 ? 'semaines' : 'semaine') : u === 'mois' ? 'mois' : (n > 1 ? 'ans' : 'an')}`);
    const d = new Date(`${formDate || new Date().toLocaleDateString('sv-SE')}T12:00:00`);
    if (u === 'jour') d.setDate(d.getDate() + n);
    else if (u === 'semaine') d.setDate(d.getDate() + 7 * n);
    else if (u === 'mois') d.setMonth(d.getMonth() + n);
    else d.setFullYear(d.getFullYear() + n);
    setFormRappel(d.toLocaleDateString('sv-SE'));
  }
  const [formSubType, setFormSubType] = useState('');
  const [formIntitule, setFormIntitule] = useState('');
  const [formClinique, setFormClinique] = useState('');
  const [formPreop, setFormPreop] = useState('');
  const [formPostop, setFormPostop] = useState('');
  const [formStatut, setFormStatut] = useState('prevu');
  const [formSeverite, setFormSeverite] = useState('');
  const [formDescription, setFormDescription] = useState('');
  const [formPoids, setFormPoids] = useState('');
  const [formTaille, setFormTaille] = useState('');
  const [savingForm, setSavingForm] = useState(false);
  // Contrôle des dates de l'acte (miroir carnet de santé du propriétaire).
  const [formErreurs, setFormErreurs] = useState<string[]>([]);
  // Champs obligatoires vides au dernier essai : une phrase (« Date et motif
  // sont à remplir. ») qui se réduit quand on les remplit.
  const [formManquants, setFormManquants] = useState<string[]>([]);
  // Patient créé par la clinique : client du fichier (propriétaire hors appli).
  const [clientClinique, setClientClinique] = useState<{ nom: string; prenom: string | null; telephone: string | null;
    email: string | null; adresse: string | null; code_postal: string | null; ville: string | null; notes: string | null; uid_lie: string | null } | null>(null);
  // Compte rendu vétérinaire : actes saisis (carnet + ordonnance PDF).
  const [vaccinsCr, setVaccinsCr] = useState<VaccinCr[]>([]);
  const [produitsCr, setProduitsCr] = useState<ProduitCr[]>([]);
  const [soinsCr, setSoinsCr] = useState<SoinCr[]>([]);
  const [actesRealises, setActesRealises] = useState<string[]>([]);
  // Actes inscrits au carnet AUJOURD'HUI par moi (Synthèse, onglet Santé) et
  // pesée du jour : repris dans le compte rendu sans être réécrits au carnet
  // (ceux déjà couverts par un compte rendu de ce jour sont exclus) — miroir
  // de _chargerCarnetDuJour (compte_rendu_page.dart).
  type ActeCarnet = { cle: string; type: 'vaccin' | 'traitement' | 'vermifuge' | 'antiparasitaire' | 'allergie' | 'chirurgie' | 'hospitalisation' | 'radio'; libelle: string; vaccin?: VaccinCr };
  const [carnetJour, setCarnetJour] = useState<ActeCarnet[]>([]);
  const [poidsCarnet, setPoidsCarnet] = useState<number | null>(null);
  useEffect(() => {
    if (addingType !== 'cr' || catPro !== 'veterinaire' || !user?.uid || !animalId) return;
    let annule = false;
    (async () => {
      const auj = new Date().toLocaleDateString('sv-SE');
      let q = supabase.from('comptes_rendus').select('created_at').eq('animal_id', animalId).gte('created_at', new Date(auj + 'T00:00:00').toISOString());
      q = activeProfileId ? q.eq('pro_profile_id', activeProfileId) : q.eq('pro_uid', user.uid);
      const { data: crs } = await q.order('created_at', { ascending: false }).limit(1);
      // Les actes et la pesée d'un compte rendu sont inscrits au carnet juste
      // APRÈS lui (à l'enregistrement) : ils lui restent rattachés (3 min) et ne
      // sont pas repris par le compte rendu suivant du même jour.
      const depuis = crs?.[0]?.created_at ? new Date(String(crs[0].created_at)).getTime() + 3 * 60000 : 0;
      const apres = (r: Record<string, unknown>) => !depuis || !r.created_at || new Date(String(r.created_at)).getTime() > depuis;
      const tables = [['vaccinations', 'vaccin'], ['traitements', 'traitement'], ['vermifuges', 'vermifuge'], ['antiparasitaires', 'antiparasitaire'],
        ['allergies', 'allergie'], ['chirurgies', 'chirurgie'], ['radios', 'radio']] as const;
      const res: ActeCarnet[] = [];
      for (const [table, rubrique] of tables) {
        const { data } = await supabase.from(table).select('*').eq('animal_id', animalId).eq('vet_id', user.uid).eq('date', auj).order('created_at');
        for (const r of (data ?? []) as Record<string, unknown>[]) {
          if (!apres(r)) continue;
          const s = (k: string) => String(r[k] ?? '').trim();
          const type: ActeCarnet['type'] = rubrique === 'chirurgie' && s('type') === 'hospitalisation' ? 'hospitalisation' : rubrique;
          const libelle = type === 'vaccin' ? `${s('vaccin') || 'Vaccin'}${s('lot') ? ` (lot ${s('lot')})` : ''}`
            : type === 'traitement' ? `${s('nom') || 'Traitement'}${s('posologie') ? ` — ${s('posologie')}` : ''}`
            : type === 'allergie' ? `${s('description') || 'Allergie'}${s('severite') ? ` (${s('severite')})` : ''}`
            : type === 'chirurgie' || type === 'hospitalisation' ? s('intitule') || (type === 'chirurgie' ? 'Chirurgie' : 'Hospitalisation')
            : type === 'radio' ? s('titre') || 'Radio / examen'
            : s('produit') || (type === 'vermifuge' ? 'Vermifuge' : 'Antiparasitaire');
          res.push({ cle: `${table}:${s('id')}`, type, libelle,
            ...(type === 'vaccin' ? { vaccin: { nom: s('vaccin') || 'Vaccin', lot: s('lot'), date: auj, rappel: s('date_rappel').slice(0, 10) || null } } : {}) });
        }
      }
      const { data: p } = await supabase.from('poids').select('valeur, created_at').eq('animal_id', animalId).eq('date', auj)
        .order('created_at', { ascending: false }).limit(1).maybeSingle();
      if (annule) return;
      setCarnetJour(res);
      const kg = p && apres(p as Record<string, unknown>) && p.valeur != null ? Number(p.valeur) : null;
      setPoidsCarnet(kg);
      if (kg != null) setFormPoids(f => f.trim() ? f : String(kg).replace('.', ','));
      if (res.some(a => a.type === 'vaccin')) setActesRealises(a => a.includes('Vaccination') ? a : [...a, 'Vaccination']);
    })();
    return () => { annule = true; };
  }, [addingType, catPro, user?.uid, animalId, activeProfileId]);
  // Dernière demande de RDV de cet animal : motif + message du client.
  const [dernierRdv, setDernierRdv] = useState<{ id: string; motif: string | null; notes_client: string | null; client_nom_manuel: string | null; client_email_manuel: string | null; client_telephone_manuel: string | null; client_uid: string | null; client_profile_id: string | null } | null>(null);
  // Demande écrite par le client en prenant RDV : reprise dans le compte rendu
  // (« Demande du client : … ») sauf si le vétérinaire la retire.
  const [demandeClient, setDemandeClient] = useState('');
  const [autreActe, setAutreActe] = useState('');
  const [traitementsCr, setTraitementsCr] = useState<TraitementCr[]>([]);
  const [requestingWrite, setRequestingWrite] = useState(false);
  const [historiqueOuvert, setHistoriqueOuvert] = useState(false);
  const [ownerProfil, setOwnerProfil] = useState<OwnerProfil | null>(null);

  // Profil propriétaire : celui qui a accordé l'accès, sinon le client du
  // dernier RDV de l'animal.
  useEffect(() => {
    if (!animalId) return;
    let annule = false;
    (async () => {
      let profilId = grant?.granted_by_profile_id ?? null;
      if (!profilId) {
        const { data } = await supabase.from('rdv').select('client_profile_id').eq('animal_id', animalId)
          .not('client_profile_id', 'is', null).order('date_heure', { ascending: false }).limit(1).maybeSingle();
        profilId = (data as { client_profile_id: string } | null)?.client_profile_id ?? null;
      }
      if (!profilId) return;
      const { data } = await supabase.from('user_profiles_complet').select('*').eq('id', profilId).maybeSingle();
      if (!annule) setOwnerProfil(data as OwnerProfil | null);
    })();
    return () => { annule = true; };
  }, [animalId, grant?.granted_by_profile_id]);

  // Pro type
  useEffect(() => {
    if (activeProfileId) {
      supabase.from('user_profiles_complet').select('profile_type, cat_pro').eq('id', activeProfileId).single()
        .then(({ data }) => {
          if (data) { const r = data as { profile_type: string; cat_pro: string }; setCatPro(r.profile_type ?? r.cat_pro ?? ''); }
        });
    } else { setCatPro(userData?.catPro ?? ''); }
  }, [activeProfileId, userData]);

  // Fiche éducative : Synthèse par défaut, prochain RDV de ce profil, et
  // compte rendu pré-rempli depuis une séance (?rdv=<id>, tableau de bord).
  useEffect(() => {
    if (!['education', 'garde', 'veterinaire', 'sante', 'toilettage'].includes(catPro)) return;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    if (!searchParams.get('tab')) setTab(t => (t === 'Identité' ? 'Synthèse' : t));
  }, [catPro, searchParams]);
  const chargerGarde = useCallback(async () => {
    if (catPro !== 'garde' || !animalId || !activeProfileId || !user) return;
    const [r, c, u] = await Promise.all([
      supabase.from('rdv').select('*').eq('pro_profile_id', activeProfileId).eq('animal_id', animalId)
        .in('statut', ['confirme', 'termine']).order('date_heure', { ascending: false }).limit(150),
      supabase.from('cles_clients').select('id, description, statut').eq('pro_profile_id', activeProfileId).eq('animal_id', animalId),
      supabase.from('pension_updates').select('*').eq('pro_uid', user.uid).eq('animal_id', animalId)
        .order('created_at', { ascending: false }).limit(60),
    ]);
    setGardeRdvs((r.data ?? []) as GardeRdvFiche[]);
    setGardeCles((c.data ?? []) as { id: string; description: string | null; statut: string | null }[]);
    setGardeCrs(u.error ? [] : (u.data ?? []) as typeof gardeCrs);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [catPro, animalId, activeProfileId, user]);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    chargerGarde();
  }, [chargerGarde]);
  useEffect(() => {
    if (catPro !== 'education' || !animalId || !activeProfileId) return;
    let annule = false;
    (async () => {
      const { data } = await supabase.from('rdv').select('date_heure, motif, lieu')
        .eq('pro_profile_id', activeProfileId).eq('animal_id', animalId).eq('statut', 'confirme')
        .gte('date_heure', new Date().toISOString()).order('date_heure').limit(1).maybeSingle();
      if (!annule) setProchainRdv(data as { date_heure: string; motif: string | null; lieu: string | null } | null);
      const { data: ms, error: msErr } = await supabase.from('education_suivis').select('motif')
        .eq('pro_profile_id', activeProfileId).eq('animal_id', animalId).maybeSingle();
      if (!annule && !msErr) setMotifSuivi((ms as { motif: string | null } | null)?.motif ?? null);
      const rdvId = searchParams.get('rdv');
      if (rdvId && !annule) {
        const { data: r } = await supabase.from('rdv').select('id, lieu, duree_minutes').eq('id', rdvId).maybeSingle();
        if (r && !annule) {
          const rr = r as { id: string; lieu: string | null; duree_minutes: number | null };
          setSeanceRdvId(rr.id);
          if (rr.lieu) { setSeanceLieu(rr.lieu); setSeanceType('domicile'); }
          if (rr.duree_minutes) setSeanceDuree(String(rr.duree_minutes));
          setShowAddRapport(true);
          setTab('Séances');
        }
      }
    })();
    return () => { annule = true; };
  }, [catPro, animalId, activeProfileId, searchParams]);

  // Autre animal (page réutilisée) : rien de la saisie du précédent.
  const animalPrecedent = useRef(animalId);
  useEffect(() => {
    if (animalPrecedent.current === animalId) return;
    animalPrecedent.current = animalId;
    viderCr(); setCrRdvId(null); setAddingType(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [animalId]);

  useEffect(() => {
    const crRdv = searchParams.get('crRdv');
    const cle = `${crRdv}|${animalId}`;
    if (!crRdv || catPro !== 'veterinaire' || !animalId || crRdvOuvert.current === cle) return;
    crRdvOuvert.current = cle;
    chargerVisite(crRdv);
    (async () => {
      // « Brouillon · reprendre » (identifiant dans le lien) : CE brouillon.
      const brouillonParam = searchParams.get('brouillon');
      if (brouillonParam) {
        const { data: b } = await supabase.from('comptes_rendus').select('*').eq('id', brouillonParam).maybeSingle();
        if (b) {
          viderCr(); setCrRdvId(crRdv); reprendreBrouillon(b as CompteRendu);
          if ((b as { rdv_id?: string | null }).rdv_id !== crRdv) await supabase.from('comptes_rendus').update({ rdv_id: crRdv }).eq('id', brouillonParam);
          return;
        }
      }
      // Compte rendu de CE RDV pour cet animal : déjà fait → on l'ouvre ;
      // brouillon → on le reprend ; sinon un compte rendu vierge.
      // Y compris un compte rendu fait depuis la fiche le jour du RDV (sans
      // lien) : il est alors rattaché au RDV.
      const duRdv = (await crsDuRdv(crRdv, [String(animalId)])).filter(c => c.animal_id === String(animalId));
      const { data: existants } = duRdv.length
        ? await supabase.from('comptes_rendus').select('*').in('id', duRdv.map(c => c.id)).order('created_at', { ascending: false })
        : { data: [] };
      const liste = (existants ?? []) as CompteRendu[];
      for (const c of duRdv.filter(x => !x.rattache)) {
        await supabase.from('comptes_rendus').update({ rdv_id: crRdv }).eq('id', c.id);
      }
      const fait = liste.find(c => c.statut !== 'brouillon');
      if (fait) { setTab('Consultations'); setCrCible(fait.id); return; }
      setCrRdvId(crRdv);
      const brouillon = liste.find(c => c.statut === 'brouillon');
      if (brouillon) { viderCr(); setCrRdvId(crRdv); reprendreBrouillon(brouillon); return; }
      const { data: r } = await supabase.from('rdv').select('motif, animaux_detail, notes_client').eq('id', crRdv).maybeSingle();
      const detail = animauxDetailRdv((r ?? {}) as { animaux_detail?: unknown });
      viderCr();
      // Saisie en cours (non enregistrée) de ce compte rendu : reprise telle quelle.
      if (!restaurerCrEnCours(crRdv)) {
        setFormMotif(detail.find(a => a.id === String(animalId))?.motif ?? (r as { motif?: string | null } | null)?.motif ?? '');
        setDemandeClient(String((r as { notes_client?: string | null } | null)?.notes_client ?? '').trim());
      }
      setAddingType('cr');
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [catPro, animalId, searchParams]);

  const isPensionType = PENSION_TYPES.has(catPro);
  const isVet = catPro === 'veterinaire' || catPro === 'sante' || catPro === 'marechal_ferrant';
  // Anatomie (pointage libre) fusionne dans Morphologie pour santé — reste
  // séparé pour maréchal-ferrant, hors périmètre de la fusion. Véto n'avait
  // pas Anatomie mais obtient Morphologie (comme côté appli).
  const hasAnatomie = catPro === 'marechal_ferrant';
  const hasMorpho = catPro === 'sante' || catPro === 'veterinaire';
  const isEducation = catPro === 'education';
  const hasWriteAccess = isVet
    ? (grant?.statut === 'active' || grant?.statut === 'active_write')
    : grant?.statut === 'active_write';
  const writeRequested = grant?.statut === 'write_requested';
  const isPending = grant?.statut === 'pending';
  // Fiche créée par un autre pro : identité + ses propres documents ; le
  // carnet reste privé tant que le propriétaire ne l'a pas partagé.
  const identiteSeule = grant?.statut === 'identite';
  // … sauf le carnet commun (vaccins, vermifuges, antiparasitaires, poids,
  // allergies, traitements) : lu et écrit par le vétérinaire et l'ostéo / kiné
  // (pm_carnet_commun, migration_carnet_commun_pros.sql).
  const carnetCommun = identiteSeule && (catPro === 'veterinaire' || catPro === 'sante');
  // Les rapports de séance sont le contenu propre de l'éducateur (ses notes de
  // séance), pas une modification de la fiche du propriétaire — n'importe quel
  // accès accordé (lecture ou écriture) suffit pour les gérer, comme côté app.
  const hasReportAccess = grant?.statut === 'active' || grant?.statut === 'active_write' || identiteSeule;

  // Toiletteur : Synthèse · Prestations · Consignes · Historique (Identité /
  // Santé ouvrables depuis la Synthèse).
  const TABS: string[] = catPro === 'toilettage'
    ? ['Synthèse', 'Prestations', 'Consignes', 'Historique']
    : isPensionType
    ? ['Identité', 'Santé', 'Alimentation']
    : isVet
      // Ostéo / kiné (sante) : UN onglet « Consultations » = ses comptes
      // rendus de séance ; vétérinaire : ses consultations + « Ostéo / Kiné ».
      // Véto : Synthèse · Consultations · Santé (carnet / repro / ostéo-kiné) · Documents ;
      // ostéo : Synthèse · Séances · Documents (plus d'onglet Bilans : les bilans
      // sont des séances). Identité depuis la Synthèse.
      ? catPro === 'sante'
        ? ['Synthèse', 'Séances', 'Documents']
        : catPro === 'veterinaire'
          ? ['Synthèse', 'Consultations', 'Santé', 'Documents']
          : ['Identité', 'Santé', 'Repro', 'Consultations',
            ...(hasAnatomie ? ['Anatomie'] : []),
            ...(hasMorpho ? ['Ostéo / Kiné'] : [])]
      : isEducation
        // Fiche éducative : Identité / Santé restent ouvrables depuis la Synthèse.
        ? ['Synthèse', 'Programme', 'Séances', 'Documents']
        // Pet-sitter / toilettage / photographe / taxi animalier… : Consultations
        // (CR/ordonnances/radios) est réservé aux professions de santé, pas
        // seulement en lecture seule — masqué, pas juste verrouillé. Le
        // pet-sitter garde Alimentation (essentiel pour nourrir l'animal).
        // Fiche pet-sitter : Identité / Santé / Alimentation ouvrables depuis la Synthèse.
        : catPro === 'garde'
          ? ['Synthèse', 'Prestations', 'Consignes', 'Historique']
          : ['Identité', 'Santé'];
  // Propriétaire : bloc commun sous l'en-tête (ProAnimalEntete), plus un onglet.

  // Load data
  useEffect(() => {
    if (!user || !animalId || !activeProfileId) return;
    async function load() {
      const [animalRes, grantRes] = await Promise.all([
        supabase.from('animaux').select('*').eq('id', animalId).single(),
        supabase.from('animal_access').select('id, statut, pro_profile_id, granted_by_profile_id')
          .eq('pro_profile_id', activeProfileId).eq('animal_id', animalId).maybeSingle(),
      ]);
      const a = animalRes.data as Animal | null;
      setAnimal(a);
      setGrant(grantRes.data as Grant | null);
      if (!a) { setLoading(false); return; }
      const clientId = (a as unknown as { client_clinique_id?: string | null }).client_clinique_id;
      if (clientId) {
        const { data: cc } = await supabase.from('clients_clinique').select('*').eq('id', clientId).maybeSingle();
        setClientClinique(cc as typeof clientClinique);
      }

      const ownerUid = a.uid_proprietaire ?? a.uid_eleveur;
      const isFemelle = a.sexe?.toLowerCase() === 'femelle';

      const results = await Promise.allSettled([
        ownerUid
          ? supabase.from('users_complet').select('uid, firstname, lastname, name_elevage, email, phone_number, numero_elevage, adress_elevage, rue_elevage, ville_elevage, code_postal_elevage, rue, ville, code_postal, is_elevage, is_pro').eq('uid', ownerUid).maybeSingle()
          : Promise.resolve({ data: null }),
        supabase.from('vaccinations').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
        supabase.from('visites').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
        supabase.from('traitements').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
        supabase.from('comptes_rendus').select('*').eq('animal_id', animalId).order('created_at', { ascending: false }),
        supabase.from('ordonnances').select('*').eq('animal_id', animalId).order('date_emit', { ascending: false }),
        supabase.from('radios').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
        isFemelle ? supabase.from('chaleurs').select('*').eq('animal_id', animalId).order('date', { ascending: false }) : Promise.resolve({ data: [] }),
        supabase.from('saillies').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
        isFemelle ? supabase.from('gestations').select('*').eq('animal_id', animalId).order('date', { ascending: false }) : Promise.resolve({ data: [] }),
        supabase.from('education_progression').select('*').eq('animal_id', animalId).order('date_seance', { ascending: false }),
        supabase.from('education_objectifs').select('id, libelle, categorie, statut, note, ordre').eq('animal_id', animalId).order('ordre').order('created_at'),
        supabase.from('exercices_attribues').select('id, titre_snapshot, description_snapshot, cadence, echeance, statut, rappels_actifs, etapes_snapshot, nb_validations, validations').eq('animal_id', animalId).order('assigned_at', { ascending: false }),
        supabase.from('forfaits_souscrits').select('id, nom_snapshot, nb_seances_total, nb_seances_utilisees, statut').eq('animal_id', animalId).order('souscrit_le', { ascending: false }),
        supabase.from('alimentations').select('*').eq('animal_id', animalId).maybeSingle(),
        supabase.from('vermifuges').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
        supabase.from('antiparasitaires').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
        supabase.from('chirurgies').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
        supabase.from('allergies').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
      ]);

      const get = <T,>(i: number): T[] => {
        const r = results[i];
        if (r.status === 'fulfilled') return ((r.value as { data: unknown }).data ?? []) as T[];
        return [];
      };
      const getSingle = <T,>(i: number): T | null => {
        const r = results[i];
        if (r.status === 'fulfilled') return (r.value as { data: unknown }).data as T | null;
        return null;
      };

      setOwner(getSingle<Owner>(0));
      setVaccins(get<VaccinEntry>(1));
      setVisites(get<VisiteEntry>(2));
      setTraitements(get<TraitementEntry>(3));
      setComptesRendus(get<CompteRendu>(4));
      setOrdonnances(get<Ordonnance>(5));
      setRadios(get<RadioEntry>(6));
      setChaleurs(get<Chaleur>(7));
      setSaillies(get<Saillie>(8));
      setGestations(get<Gestation>(9));
      setRapports(get<RapportEduP>(10));
      setObjectifs(get<EducObjectif>(11));
      const attr = get<EducAttribue>(12);
      setAttribues(attr);
      setForfaitsSous(get<ForfaitSous>(13).filter(f => f.statut !== 'annule'));
      setAlimentation(getSingle<AlimentationEntry>(14));
      setVermifuges(get<VermifugeEntry>(15));
      setAntiparasitaires(get<AntiparasitaireEntry>(16));
      setChirurgies(get<ChirurgieEntry>(17));
      setAllergies(get<AllergieEntry>(18));
      if (attr.length) {
        const { data: rt } = await supabase.from('exercices_retours')
          .select('id, attribution_id, note, media, ressenti, from_pro')
          .in('attribution_id', attr.map(a => a.id)).order('created_at');
        const grouped: Record<string, EducRetour[]> = {};
        for (const row of (rt ?? []) as EducRetour[]) (grouped[row.attribution_id] ??= []).push(row);
        setRetours(grouped);
        const unseen = ((rt ?? []) as EducRetour[]).filter(r => !r.from_pro).map(r => r.id);
        if (unseen.length) supabase.from('exercices_retours').update({ vu_par_pro: true }).in('id', unseen);
      }
      setLoading(false);
    }
    load();
  }, [user, animalId, activeProfileId]);

  // Notifie le propriétaire (in-app + push FCM) — même Cloud Function que
  // l'appli (functions/vet_notifications.js:notifyOwnerVetEntry), jamais
  // câblée côté site jusqu'ici malgré l'écriture directe déjà en place.
  /** Compte rendu validé → notification au propriétaire avec lien direct
   *  (miroir appli _notifyOwner). Copie aux co-propriétaires par le serveur. */
  async function notifierCompteRendu(crId?: string) {
    try {
      const { data: prop } = await supabase.from('animaux_proprietes').select('uid_proprio, profile_id_proprio')
        .eq('animal_id', animalId).eq('role_proprio', 'principal').eq('statut', 'actif').is('date_fin', null).limit(1).maybeSingle();
      const uid = (prop?.uid_proprio as string | undefined) ?? animal?.uid_proprietaire ?? null;
      if (!uid) return;
      const proNom = userData?.nameElevage || `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim() || 'Votre vétérinaire';
      const nom = animal?.nom ?? '';
      await supabase.from('notifications').insert({
        uid, type: 'compte_rendu_recu',
        title: `Compte rendu — ${nom || 'votre animal'}`,
        body: `${proNom} a ajouté un compte rendu${nom ? ` pour ${nom}` : ''}.`,
        ...(prop?.profile_id_proprio ? { profile_id: prop.profile_id_proprio } : {}),
        data: { animalId, animalNom: nom, ...(crId ? { crId } : {}) }, read: false,
      });
    } catch { /* ignore */ }
  }

  async function notifyOwner(typeActe: string, vetName: string) {
    try {
      await httpsCallable(functions, 'notifyOwnerVetEntry')({ animalId, vetName, typeActe });
    } catch { /* best-effort */ }
  }

  /** Vaccins / traitements du CR → carnet ; traitements → ordonnance PDF. */
  async function ecrireActesCr(vetName: string, ownerUid: string | null) {
    if (!user?.uid || !animalId) return;
    const erreurs: string[] = [];
    const auj = new Date();
    const ymd = (d: Date) => d.toISOString().slice(0, 10);
    for (const v of vaccinsCr) {
      const { error } = await supabase.from('vaccinations').insert({
        id: `${Date.now()}${Math.floor(Math.random() * 1000)}`, animal_id: animalId, vaccin: v.nom, lot: v.lot || null,
        veterinaire: vetName || null, date: v.date, date_validite_debut: v.date, date_rappel: v.rappel,
        source: 'veterinaire', vet_id: user.uid,
      });
      if (error) erreurs.push(`vaccin ${v.nom}`);
    }
    // Autres soins : chacun dans sa rubrique du carnet.
    for (const s of soinsCr) {
      const base = { id: `${Date.now()}${Math.floor(Math.random() * 1000)}`, animal_id: animalId, date: ymd(auj), source: 'veterinaire', vet_id: user.uid };
      const rappel = s.rappel_mois ? ymd(new Date(auj.getFullYear(), auj.getMonth() + s.rappel_mois, auj.getDate(), 12)) : null;
      const { error } = s.type === 'vermifuge'
        ? await supabase.from('vermifuges').insert({ ...base, produit: s.nom, dosage: s.detail || null, date_rappel: rappel })
        : s.type === 'antiparasitaire'
          ? await supabase.from('antiparasitaires').insert({ ...base, produit: s.nom, frequence: s.detail || null, date_rappel: rappel })
          : s.type === 'allergie'
            ? await supabase.from('allergies').insert({ ...base, description: s.nom, severite: s.detail || null })
            : s.type === 'radio'
              ? await supabase.from('radios').insert({ ...base, id: crypto.randomUUID(), titre: s.nom, notes: s.detail || null, veterinaire: vetName || null })
              : await supabase.from('chirurgies').insert({ ...base, id: crypto.randomUUID(), type: s.type, intitule: s.nom, statut: 'realise', notes: s.detail || null, veterinaire: vetName || null });
      if (error) erreurs.push(`${SOINS_LIBELLES[s.type].toLowerCase()} ${s.nom}`);
    }
    for (const t of traitementsCr) {
      // Antiparasitaire : section « Antiparasitaires » du carnet (pas les traitements).
      if (t.type === 'antiparasitaire') {
        const { error } = await supabase.from('antiparasitaires').insert({
          id: `${Date.now()}${Math.floor(Math.random() * 1000)}`, animal_id: animalId, produit: t.nom,
          date: new Date(auj).toLocaleDateString('sv-SE'), frequence: posologieComplete(t), notes: t.notes || null,
          source: 'veterinaire', vet_id: user.uid,
        });
        if (error) erreurs.push(`antiparasitaire ${t.nom}`);
        continue;
      }
      let debut = new Date(auj);
      for (let i = 0; i < t.phases.length; i++) {
        const ph = t.phases[i];
        const fin = ph.dureeJours ? new Date(debut.getTime() + ph.dureeJours * 86400000) : null;
        const cles = prisesTriees(ph.prises);
        const heures = cles.map(heurePrise);
        const rappel = t.rappels && heures.length > 0;
        const notesPhase = [t.phases.length > 1 ? `Phase ${i + 1}/${t.phases.length}` : '', t.notes].filter(Boolean).join(' — ');
        const { error } = await supabase.from('traitements').insert({
          id: `${Date.now()}${i}${Math.floor(Math.random() * 1000)}`, animal_id: animalId, type: t.type, nom: t.nom,
          posologie: libellePhase(ph), date: debut.toISOString(), date_fin: fin?.toISOString() ?? null,
          notes: notesPhase || null, source: 'veterinaire', vet_id: user.uid,
          rappel_actif: rappel,
          ...(rappel ? {
            rappel_frequence_jours: ph.frequenceJours, rappel_duree_jours: ph.dureeJours ?? 30,
            rappel_fin: (fin ?? new Date(debut.getTime() + 30 * 86400000)).toISOString(), rappel_heures: heures,
            // Dose de CHAQUE prise : la notification dit la bonne quantité.
            ...(dosesParPrise(ph) ? { rappel_quantites: cles.map(k => doseDe(ph, k)) } : {}),
          } : {}),
        });
        if (error) erreurs.push(`traitement ${t.nom}`);
        if (!fin) break;
        debut = fin;
      }
    }
    if (vaccinsCr.length) await notifyOwner('vaccin', vetName);
    for (const t of new Set(soinsCr.map(s => s.type))) {
      if (t !== 'radio') await notifyOwner(t, vetName);
    }
    if (traitementsCr.some(t => t.type !== 'antiparasitaire')) await notifyOwner('traitement', vetName);
    if (traitementsCr.some(t => t.type === 'antiparasitaire')) await notifyOwner('antiparasitaire', vetName);

    if (traitementsCr.length) {
      try {
        const pid = activeProfileId || null;
        const { data: cl } = pid
          ? await supabase.from('user_profiles_complet').select('nom, rue_pro, code_postal_pro, ville_pro, phone_number, certifications').eq('id', pid).maybeSingle()
          : { data: null };
        const certs = (cl?.certifications ?? []) as { nom?: string; numero?: string }[];
        const ordre = certs.find(c => (c.nom ?? '').toLowerCase().includes('ordre'))?.numero ?? '';
        const prescripteur = `${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim() || 'Vétérinaire';
        const proprio = owner ? `${owner.firstname ?? ''} ${owner.lastname ?? ''}`.trim() : '';
        const blob = await ordonnancePdfBlob({
          cliniqueNom: (cl?.nom as string | undefined)?.trim() || 'Cabinet vétérinaire',
          cliniqueAdresse: [cl?.rue_pro, `${cl?.code_postal_pro ?? ''} ${cl?.ville_pro ?? ''}`.trim()].filter(x => (x ?? '').toString().trim()).join(', '),
          cliniqueTel: (cl?.phone_number as string | undefined) ?? '',
          numeroOrdre: ordre,
          prescripteur,
          animalNom: animal?.nom ?? 'Animal',
          animalEspeceRace: [animal?.espece, animal?.race].filter(Boolean).join(' · '),
          animalSexe: sexeAnimal(animal?.sexe), animalAge: ageAnimal(animal?.date_naissance, (animal as { age_estime?: string | number | null } | null)?.age_estime),
          signature,
          animalIdentification: animal?.identification ?? '',
          animalPoids: formPoids.trim() ? `${formPoids.trim().replace('.', ',')} kg` : animal?.poids != null ? `${animal.poids} kg` : '',
          proprietaire: proprio,
          lignes: traitementsCr.map(t => ({ medicament: t.nom, posologie: posologieComplete(t), notes: t.notes })),
        });
        const path = `ordonnances/${user.uid}/${Date.now()}.pdf`;
        const { error: upErr } = await supabase.storage.from('documents').upload(path, blob, { upsert: true, contentType: 'application/pdf' });
        if (upErr) throw upErr;
        const docUrl = supabase.storage.from('documents').getPublicUrl(path).data.publicUrl;
        let ownerProfileId: string | null = null;
        if (ownerUid) {
          const { data: op } = await supabase.from('user_profiles_complet').select('id')
            .eq('uid', ownerUid).eq('profile_type', 'particulier').limit(1).maybeSingle();
          ownerProfileId = (op?.id as string | undefined) ?? null;
        }
        const { error: ordErr } = await supabase.from('ordonnances').insert({
          animal_id: animalId, pro_uid: proUid, ...(pid ? { pro_profile_id: pid, praticien_profile_id: (esp.espace ? esp.monProfil : null) ?? pid } : {}),
          owner_uid: ownerUid, ...(ownerProfileId ? { owner_profile_id: ownerProfileId } : {}),
          praticien_uid: user.uid, doc_url: docUrl, date_emit: ymd(auj),
          ...(crRdvId ? { rdv_id: crRdvId } : {}),
          notes: traitementsCr.map(t => t.nom).join(', '),
        });
        if (ordErr) throw ordErr;
        const { data } = await supabase.from('ordonnances').select('*').eq('animal_id', animalId).order('date_emit', { ascending: false });
        setOrdonnances((data ?? []) as Ordonnance[]);
        await notifyOwner('ordonnance', vetName);
      } catch { erreurs.push('ordonnance'); }
    }
    const [v, t] = await Promise.all([
      supabase.from('vaccinations').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
      supabase.from('traitements').select('*').eq('animal_id', animalId).order('date', { ascending: false }),
    ]);
    setVaccins((v.data ?? []) as VaccinEntry[]);
    setTraitements((t.data ?? []) as TraitementEntry[]);
    if (erreurs.length) alert(`Non enregistré : ${erreurs.join(', ')} — vérifiez l'accès au carnet de l'animal.`);
  }

  /** En-tête / patient / propriétaire des PDF (CR, ordonnance). */
  async function infosDocument() {
    const { data: cl } = activeProfileId
      ? await supabase.from('user_profiles_complet')
        .select('nom, firstname, lastname, rue_pro, code_postal_pro, ville_pro, rue, code_postal, ville, phone_number, phone, telephone, email_contact')
        .eq('id', activeProfileId).maybeSingle()
      : { data: null };
    const v = (x: unknown) => String(x ?? '').trim();
    const proprio = clientClinique ? `${clientClinique.prenom ?? ''} ${clientClinique.nom}`.trim()
      : owner ? `${owner.firstname ?? ''} ${owner.lastname ?? ''}`.trim() : '';
    return {
      clinique: (cl?.nom as string | undefined)?.trim() || 'Cabinet vétérinaire',
      // Adresse professionnelle, sinon celle du profil.
      adresse: (v(cl?.rue_pro) || v(cl?.ville_pro)
        ? [cl?.rue_pro, `${cl?.code_postal_pro ?? ''} ${cl?.ville_pro ?? ''}`.trim()]
        : [cl?.rue, `${cl?.code_postal ?? ''} ${cl?.ville ?? ''}`.trim()]).filter(x => v(x)).join(', '),
      tel: v(cl?.phone_number) || v(cl?.phone) || v(cl?.telephone),
      cliniqueEmail: v(cl?.email_contact) || v(user?.email),
      praticien: `${v(cl?.firstname) || v(userData?.firstname)} ${v(cl?.lastname) || v(userData?.lastname)}`.trim(),
      proprio, email: clientClinique?.email ?? null,
    };
  }

  async function transmettreCr(c: CompteRendu, action: 'imprimer' | 'email') {
    try {
      const i = await infosDocument();
      const blob = await compteRenduPdfBlob({
        cliniqueNom: i.clinique, cliniqueAdresse: i.adresse, cliniqueTel: i.tel, cliniqueEmail: i.cliniqueEmail,
        praticien: i.praticien,
        animalNom: animal?.nom ?? 'Animal', animalEspeceRace: [animal?.espece, animal?.race].filter(Boolean).join(' · '),
        animalSexe: sexeAnimal(animal?.sexe), animalAge: ageAnimal(animal?.date_naissance, (animal as { age_estime?: string | number | null } | null)?.age_estime),
        signature,
        animalIdentification: animal?.identification ?? '', proprietaire: i.proprio,
        contenu: c.contenu ?? '', date: new Date(c.created_at),
      });
      if (action === 'imprimer') imprimerPdf(blob);
      else await envoyerPdfParEmail(blob, { type: 'compte_rendu', emailParDefaut: i.email, destinataireNom: i.proprio,
        expediteur: i.clinique, animalNom: animal?.nom, nomFichier: `Compte-rendu-${animal?.nom ?? 'animal'}.pdf`, animalId });
    } catch (e) { alert(`Impossible : ${(e as Error).message}`); }
  }

  async function transmettreOrdo(o: Ordonnance, action: 'imprimer' | 'email') {
    if (!o.doc_url) return;
    try {
      const blob = await pdfDepuisUrl(o.doc_url);
      if (action === 'imprimer') { imprimerPdf(blob); return; }
      const i = await infosDocument();
      await envoyerPdfParEmail(blob, { type: 'ordonnance', emailParDefaut: i.email, destinataireNom: i.proprio,
        expediteur: i.clinique, animalNom: animal?.nom, nomFichier: `Ordonnance-${animal?.nom ?? 'animal'}.pdf`, animalId });
    } catch (e) { alert(`Impossible : ${(e as Error).message}`); }
  }

  useEffect(() => {
    if (addingType !== 'cr' || !animalId || !activeProfileId) return;
    supabase.from('rdv').select('id, motif, notes_client, client_nom_manuel, client_email_manuel, client_telephone_manuel, client_uid, client_profile_id')
      .eq('animal_id', animalId).eq('pro_profile_id', activeProfileId).in('statut', ['confirme', 'termine'])
      .lte('date_heure', new Date(Date.now() + 12 * 3600000).toISOString())
      .order('date_heure', { ascending: false }).limit(1).maybeSingle()
      .then(({ data }) => {
        setDernierRdv(data as typeof dernierRdv);
        if (data?.motif) setFormMotif(m => m || (data.motif as string));
        if (data?.notes_client && !crRdvId) setDemandeClient(d => d || String(data.notes_client).trim());
      });
  }, [addingType, animalId, activeProfileId]);

  /** Facture de la consultation, au choix du vétérinaire : RDV (grille de
   *  tarifs du profil), actes, produits (prix de vente de la pharmacie). */
  /** Produits vendus pris dans le stock : sortie enregistrée (mouvement « consommation ») et quantité mise à jour. */
  async function decompterStock(produits: ProduitCr[]) {
    if (!user?.uid || !activeProfileId) return;
    for (const p of produits) {
      if (!p.item_id) continue;
      const { data: item } = await supabase.from('inventaire_items').select('quantite, stupefiant').eq('id', p.item_id).maybeSingle();
      if (!item) continue;
      const apres = Math.max(0, Number(item.quantite ?? 0) - p.quantite);
      await supabase.from('inventaire_mouvements').insert({
        item_id: p.item_id, uid_eleveur: proUid, uid_auteur: user.uid, eleveur_profile_id: activeProfileId,
        type: 'consommation', quantite: p.quantite, note: 'Vente — consultation',
        ...(item.stupefiant ? { stock_apres: apres } : {}),
      });
      await supabase.from('inventaire_items').update({ quantite: apres }).eq('id', p.item_id);
    }
  }

  async function proposerFacture(motif: string, actes: string[], vaccins: VaccinCr[], traitements: TraitementCr[], poids: number | null, produits: ProduitCr[] = [], rdvFacture?: string) {
    if (!activeProfileId || !animal) return;
    const [{ data: t }, { data: ph }] = await Promise.all([
      supabase.from('user_profiles_complet').select('tarifs_veto').eq('id', activeProfileId).maybeSingle(),
      supabase.from('inventaire_items').select('nom, prix_vente').eq('eleveur_profile_id', activeProfileId),
    ]);
    const tarifs = (t?.tarifs_veto ?? {}) as Record<string, unknown>;
    // Aucune grille saisie : les prix seraient à 0 → proposer de la remplir.
    if (Object.values(tarifs).every(v => !(parseFloat(String(v ?? '').replace(',', '.')) > 0))
      && confirm('Vos tarifs ne sont pas encore renseignés : la facture serait à 0 €.\n\nOuvrir « Mes tarifs » pour les saisir ?\n(Annuler : préparer la facture quand même)')) {
      navigationSuivie.current = true;
      router.push('/profil#tarifs');
      return;
    }
    const tarif = (k: string) => { const v = parseFloat(String(tarifs[k] ?? '').replace(',', '.')); return isNaN(v) ? null : v; };
    const prixPharma = (nom: string) => {
      const o = ((ph ?? []) as { nom: string; prix_vente: number | null }[]).find(x => x.nom.toLowerCase() === nom.toLowerCase());
      return o?.prix_vente ?? null;
    };
    const lignes = lignesConsultation({ an: animal, motif, actes, vaccins, traitements, poids, produits, tarif, prixPharma });
    const total = lignes.reduce((s, l) => s + l.prixUnitaire * 1.2, 0);
    const aCompleter = lignes.filter(l => l.prixUnitaire === 0).length;
    const recap = lignes.map(l => `• ${l.description} : ${l.prixUnitaire ? `${(l.prixUnitaire * 1.2).toFixed(2)} €` : 'à compléter'}`).join('\n');
    if (!confirm(`Facturer cette consultation ?\n\n${recap}\n\nTotal estimé : ${total.toFixed(2)} € TTC${aCompleter ? ` (${aCompleter} prix à compléter)` : ''}\nTout reste modifiable avant l'émission.`)) return;

    // Client : propriétaire PetsMatch (coordonnées de facturation selon
    // particulier / élevage / association — pm_client_facturation), sinon
    // fichier de la clinique, sinon RDV. Miroir appli.
    const c = { prenom: '', nom: '', email: '', tel: '', rue: '', cp: '', ville: '', pays: '', siret: '', tva: '' };
    // Client du RDV (co-propriétaire qui a amené l'animal) si connu.
    const { data: cf } = await supabase.rpc('pm_client_facturation', {
      p_animal_id: animalId, ...(dernierRdv?.client_profile_id ? { p_client_profile_id: dernierRdv.client_profile_id } : {}),
    });
    const j = (cf ?? null) as Record<string, string> | null;
    if (j && (j.nom || j.prenom)) {
      Object.assign(c, { prenom: j.prenom ?? '', nom: j.nom ?? '', email: j.email ?? '', tel: j.telephone ?? '', rue: j.rue ?? '',
        cp: j.code_postal ?? '', ville: j.ville ?? '', pays: j.pays ?? '', siret: j.siret ?? '', tva: j.numero_tva ?? '' });
    } else if (clientClinique) {
      const cc = clientClinique as typeof clientClinique & { adresse?: string | null; code_postal?: string | null; ville?: string | null };
      Object.assign(c, { prenom: cc.prenom ?? '', nom: cc.nom ?? '', email: cc.email ?? '', tel: cc.telephone ?? '',
        rue: cc.adresse ?? '', cp: cc.code_postal ?? '', ville: cc.ville ?? '' });
    } else if (owner) {
      Object.assign(c, { prenom: owner.firstname ?? '', nom: owner.lastname ?? '' });
    } else if (dernierRdv) {
      Object.assign(c, { nom: dernierRdv.client_nom_manuel ?? '', email: dernierRdv.client_email_manuel ?? '', tel: dernierRdv.client_telephone_manuel ?? '' });
    }
    try {
      sessionStorage.setItem('pm_facture_prefill', JSON.stringify({
        prenomClient: c.prenom, nomClient: c.nom, emailClient: c.email, telClient: c.tel,
        rueClient: c.rue, cpClient: c.cp, villeClient: c.ville, paysClient: c.pays, siretClient: c.siret, tvaClient: c.tva, lignes,
        notes: `Consultation de ${animal.nom}`,
        sourceRdvId: rdvFacture ?? dernierRdv?.id, sourceAnimalId: animalId,
        ...((rdvFacture ?? crRdvId) ? { retour: `/mes-rdv?rdv=${encodeURIComponent((rdvFacture ?? crRdvId)!)}` } : {}),
        clientUid: dernierRdv?.client_uid ?? animal.uid_proprietaire ?? undefined,
        clientProfileId: dernierRdv?.client_profile_id ?? undefined,
      }));
    } catch { /* ignore */ }
    navigationSuivie.current = true;
    router.push('/elevage/facturation');
  }

  /** Vaccins et traitements de CE compte rendu (facture) : inscrits au carnet
   *  après le compte rendu précédent du jour (et ses 3 min d'enregistrement),
   *  jusqu'aux 3 min qui suivent celui-ci — pas ceux des comptes rendus
   *  précédents. Miroir appli _carnetDuCr. */
  async function carnetDuCr(aid: string, cr: { created_at: string }) {
    const cree = new Date(cr.created_at);
    const jour = cree.toLocaleDateString('sv-SE');
    const debutJour = new Date(cree.getFullYear(), cree.getMonth(), cree.getDate());
    let q = supabase.from('comptes_rendus').select('created_at').eq('animal_id', aid)
      .gte('created_at', debutJour.toISOString()).lt('created_at', cree.toISOString());
    q = activeProfileId ? q.eq('pro_profile_id', activeProfileId) : q.eq('pro_uid', user?.uid ?? '');
    const { data: prec } = await q.order('created_at', { ascending: false }).limit(1);
    const bas = prec?.[0]?.created_at ? new Date(String(prec[0].created_at)).getTime() + 3 * 60000 : 0;
    const haut = cree.getTime() + 3 * 60000;
    const dansCr = (r: { created_at?: string | null }) => {
      if (!r.created_at) return true;
      const t = new Date(r.created_at).getTime();
      return t > bas && t <= haut;
    };
    const [{ data: v }, { data: t }] = await Promise.all([
      supabase.from('vaccinations').select('vaccin, lot, date, date_rappel, created_at').eq('animal_id', aid).eq('date', jour).eq('vet_id', user?.uid ?? ''),
      supabase.from('traitements').select('nom, created_at').eq('animal_id', aid).eq('date', jour).eq('vet_id', user?.uid ?? ''),
    ]);
    return {
      vac: ((v ?? []) as { vaccin: string | null; lot: string | null; date: string; date_rappel: string | null; created_at?: string | null }[]).filter(dansCr),
      trt: ((t ?? []) as { nom: string | null; created_at?: string | null }[]).filter(dansCr),
    };
  }

  /** RDV à plusieurs animaux : une seule facture pour la visite, avec les
   *  lignes de chaque animal (son compte rendu validé et ses actes du jour). */
  async function facturerVisite(rdvId: string) {
    if (!activeProfileId || !user) return;
    const { data: r } = await supabase.from('rdv').select('id, animaux_detail, client_uid, client_profile_id, client_nom_manuel, client_email_manuel, client_telephone_manuel')
      .eq('id', rdvId).maybeSingle();
    const detail = animauxDetailRdv((r ?? {}) as { animaux_detail?: unknown });
    if (!r || detail.length === 0) return;
    // Comptes rendus validés du RDV (y compris faits depuis la fiche le jour du RDV).
    const idsCr = (await crsDuRdv(rdvId, detail.map(a => a.id))).filter(c => c.statut !== 'brouillon').map(c => c.id);
    const [{ data: crsData }, { data: ans }, { data: t }, { data: ph }, { data: deja }] = await Promise.all([
      idsCr.length ? supabase.from('comptes_rendus').select('*').in('id', idsCr).order('created_at') : Promise.resolve({ data: [] }),
      supabase.from('animaux').select('id, nom, espece, sexe, poids').in('id', detail.map(a => a.id)),
      supabase.from('user_profiles_complet').select('tarifs_veto').eq('id', activeProfileId).maybeSingle(),
      supabase.from('inventaire_items').select('nom, prix_vente').eq('eleveur_profile_id', activeProfileId),
      supabase.from('factures').select('id').eq('source_rdv_id', rdvId).limit(1),
    ]);
    const tarifs = (t?.tarifs_veto ?? {}) as Record<string, unknown>;
    const tarif = (k: string) => { const v = parseFloat(String(tarifs[k] ?? '').replace(',', '.')); return isNaN(v) ? null : v; };
    const prixPharma = (nom: string) => ((ph ?? []) as { nom: string; prix_vente: number | null }[]).find(x => x.nom.toLowerCase() === nom.toLowerCase())?.prix_vente ?? null;
    const crs = (crsData ?? []) as (CompteRendu & { produits?: ProduitCr[] | null })[];
    const lignes: LigneFacture[] = [];
    const noms: string[] = [];
    for (const a of detail) {
      const cr = crs.filter(c => String(c.animal_id) === a.id).pop();
      if (!cr) continue;
      const an = ((ans ?? []) as { id: string; nom: string; espece: string | null; sexe: string | null; poids: number | null }[]).find(x => String(x.id) === a.id);
      const { vac, trt } = await carnetDuCr(a.id, cr);
      const nom = an?.nom ?? a.nom;
      lignes.push(...lignesConsultation({
        an: an ?? {}, prefixe: nom, motif: cr.motif ?? a.motif ?? '', actes: cr.actes ?? [], poids: cr.poids ?? null, produits: cr.produits ?? [],
        vaccins: ((vac ?? []) as { vaccin: string | null; lot: string | null; date: string; date_rappel: string | null }[])
          .map(v => ({ nom: v.vaccin ?? 'Vaccin', lot: v.lot ?? '', date: String(v.date).slice(0, 10), rappel: v.date_rappel ? String(v.date_rappel).slice(0, 10) : null })),
        traitements: [...new Set(((trt ?? []) as { nom: string | null }[]).map(x => x.nom ?? '').filter(Boolean))]
          .map(n => ({ nom: n, type: 'medicament', phases: [], rappels: false, notes: '' })),
        tarif, prixPharma,
      }));
      noms.push(nom);
    }
    if (lignes.length === 0) return;
    if ((deja ?? []).length > 0 && !confirm('Une facture existe déjà pour cette visite. En préparer une autre ?')) return;
    const total = lignes.reduce((s, l) => s + l.prixUnitaire * l.quantite * 1.2, 0);
    const aCompleter = lignes.filter(l => l.prixUnitaire === 0).length;
    const recap = lignes.map(l => `• ${l.description} : ${l.prixUnitaire ? `${(l.prixUnitaire * 1.2).toFixed(2)} €` : 'à compléter'}`).join('\n');
    if (!confirm(`Facturer la visite (${noms.length} animaux) ?\n\n${recap}\n\nTotal estimé : ${total.toFixed(2)} € TTC${aCompleter ? ` (${aCompleter} prix à compléter)` : ''}\nTout reste modifiable avant l'émission.`)) return;
    const rr = r as { client_uid: string | null; client_profile_id: string | null; client_nom_manuel: string | null; client_email_manuel: string | null; client_telephone_manuel: string | null };
    const c = { prenom: '', nom: '', email: '', tel: '', rue: '', cp: '', ville: '', pays: '', siret: '', tva: '' };
    const { data: cf } = await supabase.rpc('pm_client_facturation', {
      p_animal_id: detail[0].id, ...(rr.client_profile_id ? { p_client_profile_id: rr.client_profile_id } : {}),
    });
    const j = (cf ?? null) as Record<string, string> | null;
    if (j && (j.nom || j.prenom)) {
      Object.assign(c, { prenom: j.prenom ?? '', nom: j.nom ?? '', email: j.email ?? '', tel: j.telephone ?? '', rue: j.rue ?? '',
        cp: j.code_postal ?? '', ville: j.ville ?? '', pays: j.pays ?? '', siret: j.siret ?? '', tva: j.numero_tva ?? '' });
    } else {
      Object.assign(c, { nom: rr.client_nom_manuel ?? '', email: rr.client_email_manuel ?? '', tel: rr.client_telephone_manuel ?? '' });
    }
    const listeNoms = noms.length > 1 ? `${noms.slice(0, -1).join(', ')} et ${noms[noms.length - 1]}` : noms[0];
    try {
      sessionStorage.setItem('pm_facture_prefill', JSON.stringify({
        prenomClient: c.prenom, nomClient: c.nom, emailClient: c.email, telClient: c.tel,
        rueClient: c.rue, cpClient: c.cp, villeClient: c.ville, paysClient: c.pays, siretClient: c.siret, tvaClient: c.tva, lignes,
        notes: `Consultation de ${listeNoms}`,
        sourceRdvId: rdvId, sourceAnimalId: detail[0].id, retour: `/mes-rdv?rdv=${encodeURIComponent(rdvId)}`,
        clientUid: rr.client_uid ?? undefined, clientProfileId: rr.client_profile_id ?? undefined,
      }));
    } catch { /* ignore */ }
    navigationSuivie.current = true;
    router.push('/elevage/facturation');
  }

  /** Après un compte rendu d'une visite à plusieurs animaux : facture proposée
   *  quand tous les comptes rendus sont faits. Renvoie false si ce n'est pas une telle visite. */
  async function apresCrVisite(rdvId: string): Promise<boolean> {
    const { data: r } = await supabase.from('rdv').select('animaux_detail').eq('id', rdvId).maybeSingle();
    const detail = animauxDetailRdv((r ?? {}) as { animaux_detail?: unknown });
    if (detail.length === 0) return false;
    const crs = (await crsDuRdv(rdvId, detail.map(a => a.id))).filter(c => c.statut !== 'brouillon');
    const faits = new Set(crs.map(c => c.animal_id));
    const restants = detail.filter(a => !faits.has(a.id)).map(a => a.nom);
    await chargerVisite(rdvId);
    if (restants.length === 0) await facturerVisite(rdvId);
    else {
      // Animal suivant de la visite (premier sans compte rendu).
      const suivant = detail.find(a => !faits.has(a.id));
      if (suivant && confirm(`Compte rendu enregistré. Reste : ${restants.join(', ')} — la facture de la visite sera proposée au dernier compte rendu.\n\nPasser au compte rendu de ${suivant.nom} ?`)) {
        navigationSuivie.current = true;
        window.location.assign(`/mes-patients/${encodeURIComponent(suivant.id)}?crRdv=${encodeURIComponent(rdvId)}`);
      }
    }
    return true;
  }

  /** « Modifier » un compte rendu validé : même formulaire qu'à la création,
   *  pré-rempli depuis le texte (motif, demande, poids, actes, diagnostic,
   *  recommandations) ; le reste du texte (vaccins, examens…) est conservé et
   *  complété par ce qui est ajouté. */
  function modifierCr(cr: CompteRendu) {
    viderCr();
    const champs: Record<string, string> = {};
    const conserve: { titre: string; corps: string }[] = [];
    const EDITABLES = ['Motif', 'Demande du client', 'Poids', 'Actes réalisés', 'Diagnostic', 'Recommandations'];
    let courant: { titre: string; corps: string } | null = null;
    for (const p of (cr.contenu ?? '').split(/\n\s*\n/)) {
      const m = /^([^:\n]{2,40}) : ([\s\S]*)$/.exec(p.trim());
      if (m && (EDITABLES.includes(m[1]) || TITRES_CR_CONSERVES.includes(m[1]))) {
        courant = { titre: m[1], corps: m[2] };
        if (EDITABLES.includes(m[1])) champs[m[1]] = m[2]; else conserve.push(courant);
      } else if (courant) {
        // Paragraphe sans titre : suite du précédent.
        courant.corps += `\n\n${p}`;
        if (EDITABLES.includes(courant.titre)) champs[courant.titre] = courant.corps;
      } else {
        courant = { titre: 'Recommandations', corps: p };
        champs.Recommandations = p;
      }
    }
    setFormMotif(cr.motif ?? champs.Motif ?? '');
    setDemandeClient(champs['Demande du client'] ?? '');
    setFormPoids(cr.poids != null ? String(cr.poids).replace('.', ',') : '');
    setActesRealises(cr.actes ?? []);
    setFormDiag(champs.Diagnostic ?? '');
    setFormNotes(champs.Recommandations ?? '');
    setCrRdvId(cr.rdv_id ?? null);
    setCrEdition({ cr, conserve });
    setAddingType('cr');
  }

  /** Facture d'un compte rendu, après coup : motif, poids, actes du CR +
   *  vaccins / traitements inscrits au carnet par moi le jour du CR ; visite
   *  à plusieurs animaux : la facture de toute la visite. */
  async function facturerCr(c: CompteRendu) {
    if (c.rdv_id) {
      const { data: rv } = await supabase.from('rdv').select('animaux_detail').eq('id', c.rdv_id).maybeSingle();
      if (animauxDetailRdv((rv ?? {}) as { animaux_detail?: unknown }).length > 0) { await facturerVisite(c.rdv_id); return; }
    }
    const { vac, trt } = await carnetDuCr(String(animalId), c);
    const vaccins: VaccinCr[] = ((vac ?? []) as { vaccin: string | null; lot: string | null; date: string; date_rappel: string | null }[])
      .map(v => ({ nom: v.vaccin ?? 'Vaccin', lot: v.lot ?? '', date: String(v.date).slice(0, 10), rappel: v.date_rappel ? String(v.date_rappel).slice(0, 10) : null }));
    const noms = [...new Set(((trt ?? []) as { nom: string | null }[]).map(x => x.nom ?? '').filter(Boolean))];
    await proposerFacture(c.motif ?? '', c.actes ?? [], vaccins,
      noms.map(nom => ({ nom, type: 'medicament', phases: [], rappels: false, notes: '' })), c.poids ?? null,
      c.produits ?? [], c.rdv_id ?? searchParams.get('rdv') ?? undefined);
  }

  // Liens depuis Gérer mes RDV : « Modifier » un compte rendu fait
  // (?modifierCr=), « Facturer » le RDV (?facturerRdv=).
  const actionRdvFaite = useRef('');
  useEffect(() => {
    const modif = searchParams.get('modifierCr');
    const fact = searchParams.get('facturerRdv');
    const cle = `${modif}|${fact}|${animalId}`;
    if ((!modif && !fact) || catPro !== 'veterinaire' || !animalId || !animal || actionRdvFaite.current === cle) return;
    actionRdvFaite.current = cle;
    (async () => {
      if (modif) {
        const { data } = await supabase.from('comptes_rendus').select('*').eq('id', modif).maybeSingle();
        if (data) modifierCr(data as CompteRendu);
        return;
      }
      const { data: rv } = await supabase.from('rdv').select('motif, animaux_detail').eq('id', fact!).maybeSingle();
      if (animauxDetailRdv((rv ?? {}) as { animaux_detail?: unknown }).length > 0) await facturerVisite(fact!);
      else {
        const crs = (await crsDuRdv(fact!, [String(animalId)])).filter(c => c.statut !== 'brouillon');
        const { data: cr } = crs.length ? await supabase.from('comptes_rendus').select('*').eq('id', crs[0].id).maybeSingle() : { data: null };
        if (cr) await facturerCr({ ...(cr as CompteRendu), rdv_id: fact });
        // Pas encore de compte rendu : facture du RDV (motif seul), à compléter.
        else await proposerFacture((rv as { motif?: string | null } | null)?.motif ?? '', [], [], [], null, [], fact!);
      }
      // Facture refusée : retour au RDV.
      if (!navigationSuivie.current) retourAuRdv(fact!);
    })();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [searchParams, catPro, animalId, animal]);

  /** Retour à la vue du RDV (Gérer mes RDV, RDV mis en avant). */
  function retourAuRdv(rdvId: string) {
    window.location.assign(`/mes-rdv?rdv=${encodeURIComponent(rdvId)}`);
  }

  /** Nouveau compte rendu : formulaire vierge (rien d'une saisie précédente). */
  function viderCr() {
    setBrouillonId(null); setRetourCr(null); setDemandeClient(''); setCrEdition(null);
    setFormMotif(''); setFormPoids(''); setFormNotes(''); setFormDiag('');
    setActesRealises([]); setVaccinsCr([]); setTraitementsCr([]); setProduitsCr([]); setSoinsCr([]); setAutreActe('');
    setCarnetJour([]); setPoidsCarnet(null); setFormErreurs([]); setFormManquants([]);
  }

  function reprendreBrouillon(cr: { id: string; brouillon?: unknown; motif?: string | null; contenu?: string | null }) {
    // Saisie gardée avec le brouillon ; à défaut (brouillon d'ASV), motif et texte du compte rendu.
    const e = (cr.brouillon ?? { motif: cr.motif ?? '', texte: cr.contenu ?? '' }) as { motif?: string; poids?: string; texte?: string; diag?: string; demande?: string; actes?: string[]; vaccins?: VaccinCr[]; traitements?: TraitementCr[]; produits?: ProduitCr[]; soins?: SoinCr[] };
    setBrouillonId(cr.id); setDemandeClient(e.demande ?? '');
    setFormMotif(e.motif ?? ''); setFormPoids(e.poids ?? ''); setFormNotes(e.texte ?? ''); setFormDiag(e.diag ?? '');
    setActesRealises(e.actes ?? []); setVaccinsCr(e.vaccins ?? []); setTraitementsCr(e.traitements ?? []); setProduitsCr(e.produits ?? []); setSoinsCr(e.soins ?? []);
    setAddingType('cr');
  }

  function saisirSoinDepuisCr(t: 'vermifuge' | 'antiparasitaire' | 'allergie' | 'chirurgie' | 'radio') {
    setRetourCr({ motif: formMotif, notes: formNotes, diag: formDiag, poids: formPoids, actes: actesRealises, vaccins: vaccinsCr,
      traitements: traitementsCr, produits: produitsCr, soins: soinsCr, brouillonId, demande: demandeClient });
    setFormNom(''); setFormNotes(''); setFormDiag(''); setFormRappel(''); setFormTitre(''); setFormDosage(''); setFormFrequence('');
    setFormSubType(''); setFormIntitule(''); setFormSeverite(''); setFormDescription('');
    setFormDate(new Date().toLocaleDateString('sv-SE'));
    setAddingType(t);
  }
  function revenirAuCr(r: NonNullable<typeof retourCr>) {
    setFormMotif(r.motif); setFormNotes(r.notes); setFormDiag(r.diag); setFormPoids(r.poids);
    setActesRealises(r.actes); setVaccinsCr(r.vaccins); setTraitementsCr(r.traitements); setProduitsCr(r.produits); setSoinsCr(r.soins);
    setBrouillonId(r.brouillonId); setDemandeClient(r.demande); setRetourCr(null); setAddingType('cr');
  }

  // Compte rendu en cours, pas encore enregistré : gardé (onglet du
  // navigateur) jusqu'à son enregistrement, pour le retrouver tel quel si la
  // fenêtre est fermée ou la page rechargée (radio ajoutée entre-temps…).
  const cleCrEnCours = animalId ? `pm_cr_en_cours:${animalId}` : '';
  useEffect(() => {
    if (addingType !== 'cr' || !cleCrEnCours || crEdition) return;
    const vide = !formMotif.trim() && !formNotes.trim() && !formDiag.trim() && !actesRealises.length && !vaccinsCr.length
      && !traitementsCr.length && !produitsCr.length && !soinsCr.length;
    if (vide) return;
    try {
      sessionStorage.setItem(cleCrEnCours, JSON.stringify({
        jour: new Date().toLocaleDateString('sv-SE'), rdv: crRdvId ?? null, brouillonId,
        motif: formMotif, notes: formNotes, diag: formDiag, poids: formPoids, demande: demandeClient,
        actes: actesRealises, vaccins: vaccinsCr, traitements: traitementsCr, produits: produitsCr, soins: soinsCr,
      }));
    } catch { /* stockage indisponible : rien de gardé */ }
  }, [addingType, cleCrEnCours, crEdition, crRdvId, brouillonId, formMotif, formNotes, formDiag, formPoids, demandeClient,
    actesRealises, vaccinsCr, traitementsCr, produitsCr, soinsCr]);
  /** Reprend la saisie gardée du compte rendu (même animal, même RDV, même jour). */
  function restaurerCrEnCours(rdvId: string | null): boolean {
    if (!cleCrEnCours) return false;
    try {
      const s = JSON.parse(sessionStorage.getItem(cleCrEnCours) ?? 'null');
      if (!s || s.jour !== new Date().toLocaleDateString('sv-SE') || (s.rdv ?? null) !== (rdvId ?? null)) return false;
      setFormMotif(s.motif ?? ''); setFormNotes(s.notes ?? ''); setFormDiag(s.diag ?? ''); setFormPoids(s.poids ?? '');
      setDemandeClient(s.demande ?? ''); setBrouillonId(s.brouillonId ?? null);
      setActesRealises(s.actes ?? []); setVaccinsCr(s.vaccins ?? []); setTraitementsCr(s.traitements ?? []);
      setProduitsCr(s.produits ?? []); setSoinsCr(s.soins ?? []);
      return true;
    } catch { return false; }
  }
  function oublierCrEnCours() {
    try { if (cleCrEnCours) sessionStorage.removeItem(cleCrEnCours); } catch { /* ignore */ }
  }

  /** [enBrouillon] : CR enregistré sans être validé — invisible du propriétaire,
   *  sans carnet / pesée / facture ; repris plus tard (brouillonId). */
  async function saveForm(enBrouillon = false) {
    if (!user?.uid || !animalId) return;
    if (addingType !== 'mesure') {
      const erreurs = erreursDatesSante(
        { date: formDate, date_rappel: formRappel, date_fin: formDateFin, ...(addingType === 'chirurgie' ? { statut: formStatut } : {}) },
        [{ key: 'date', label: 'Date', required: true }, { key: 'date_rappel', label: 'Date de rappel' }, { key: 'date_fin', label: 'Date de fin' }]);
      // Allergie : date constatée, jamais dans le futur.
      if (addingType === 'allergie' && formDate && formDate > new Date().toLocaleDateString('sv-SE')) {
        erreurs.push('Date constatée : ne peut pas être dans le futur.');
      }
      const libelleNom = addingType === 'vaccin' ? 'Vaccin' : addingType === 'traitement' ? 'Traitement' : 'Produit';
      const vides = [
        ...(!formDate ? ['date'] : []),
        ...(addingType === 'visite' && !formMotif.trim() ? ['motif'] : []),
        ...(['vaccin', 'traitement', 'vermifuge', 'antiparasitaire'].includes(addingType ?? '') && !formNom.trim() ? [`nom:${libelleNom}`] : []),
      ];
      const autres = erreurs.filter(e => !e.endsWith(': obligatoire.'));
      setFormManquants(vides);
      setFormErreurs(autres);
      if (autres.length || vides.length) return;
    }
    if (addingType === 'vermifuge' && optsVerm.rappel && optsVerm.heures.length === 0) {
      alert('Ajoutez au moins une heure de rappel (ou décochez « Rappel à chaque prise »).');
      return;
    }
    setSavingForm(true);
    const vetName = (userData?.nameElevage ?? (`${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim())) || '';
    const base = { animal_id: animalId, vet_id: user.uid, source: 'veterinaire', veterinaire: vetName || undefined };
    try {
      if (addingType === 'vaccin') {
        await supabase.from('vaccinations').insert({ ...base, vaccin: formNom.trim(), date: formDate, date_rappel: formRappel || null, lot: formLot.trim() || null });
        const { data } = await supabase.from('vaccinations').select('*').eq('animal_id', animalId).order('date', { ascending: false });
        setVaccins((data ?? []) as VaccinEntry[]);
        await notifyOwner('vaccin', vetName);
      } else if (addingType === 'visite') {
        await supabase.from('visites').insert({ ...base, ...(activeProfileId ? { vet_profile_id: activeProfileId } : {}), date: formDate, motif: formMotif.trim() || null, diagnostic: formDiag.trim() || null, notes: formNotes.trim() || null });
        const { data } = await supabase.from('visites').select('*').eq('animal_id', animalId).order('date', { ascending: false });
        setVisites((data ?? []) as VisiteEntry[]);
        await notifyOwner('visite', vetName);
      } else if (addingType === 'traitement') {
        await supabase.from('traitements').insert({ ...base, nom: formNom.trim(), posologie: formPosologie.trim() || null, date: formDate, date_fin: formDateFin || null, notes: formNotes.trim() || null });
        const { data } = await supabase.from('traitements').select('*').eq('animal_id', animalId).order('date', { ascending: false });
        setTraitements((data ?? []) as TraitementEntry[]);
        await notifyOwner('traitement', vetName);
      } else if (addingType === 'vermifuge') {
        await supabase.from('vermifuges').insert({ ...base, produit: formNom.trim(), dosage: formDosage.trim() || null, date: formDate, date_rappel: formRappel || null, frequence: formFrequence.trim() || null, notes: formNotes.trim() || null,
          ...colonnesPrises(optsVerm, formDate) });
        const { data } = await supabase.from('vermifuges').select('*').eq('animal_id', animalId).order('date', { ascending: false });
        setVermifuges((data ?? []) as VermifugeEntry[]);
        await notifyOwner('vermifuge', vetName);
      } else if (addingType === 'antiparasitaire') {
        await supabase.from('antiparasitaires').insert({ ...base, produit: formNom.trim(), type: formSubType.trim() || null, date: formDate, date_rappel: formRappel || null, frequence: formFrequence.trim() || null, notes: formNotes.trim() || null });
        const { data } = await supabase.from('antiparasitaires').select('*').eq('animal_id', animalId).order('date', { ascending: false });
        setAntiparasitaires((data ?? []) as AntiparasitaireEntry[]);
        await notifyOwner('antiparasitaire', vetName);
      } else if (addingType === 'chirurgie') {
        const { error: eChir } = await supabase.from('chirurgies').insert({ ...base, id: crypto.randomUUID(), type: formSubType || 'chirurgie', intitule: formIntitule.trim(), date: formDate, statut: formStatut, clinique: formClinique.trim() || null, protocole_preop: formPreop.trim() || null, protocole_postop: formPostop.trim() || null, notes: formNotes.trim() || null });
        if (eChir) { alert(`Non enregistré : ${eChir.message}`); return; }
        const { data } = await supabase.from('chirurgies').select('*').eq('animal_id', animalId).order('date', { ascending: false });
        setChirurgies((data ?? []) as ChirurgieEntry[]);
        await notifyOwner(formSubType === 'hospitalisation' ? 'hospitalisation' : 'chirurgie', vetName);
      } else if (addingType === 'allergie') {
        await supabase.from('allergies').insert({ animal_id: animalId, vet_id: user.uid, source: 'veterinaire', type: formSubType.trim() || null, description: formDescription.trim(), severite: formSeverite.trim() || null, date: formDate, notes: formNotes.trim() || null });
        const { data } = await supabase.from('allergies').select('*').eq('animal_id', animalId).order('date', { ascending: false });
        setAllergies((data ?? []) as AllergieEntry[]);
        await notifyOwner('allergie', vetName);
      } else if (addingType === 'ordonnance') {
        const ownerUid = animal?.uid_proprietaire ?? animal?.uid_eleveur ?? null;
        let ownerProfileId: string | null = null;
        if (ownerUid) {
          const { data: ownerProfile } = await supabase.from('user_profiles_complet').select('id').eq('uid', ownerUid).eq('is_main', true).maybeSingle();
          ownerProfileId = ownerProfile?.id ?? null;
        }
        const pid = activeProfileId || null;
        await supabase.from('ordonnances').insert({
          animal_id: animalId,
          pro_uid: proUid,
          ...(pid ? { pro_profile_id: pid } : {}),
          owner_uid: ownerUid,
          ...(ownerProfileId ? { owner_profile_id: ownerProfileId } : {}),
          date_emit: formDate,
          notes: formNotes.trim() || null,
        });
        const { data } = await supabase.from('ordonnances').select('*').eq('animal_id', animalId).order('date_emit', { ascending: false });
        setOrdonnances((data ?? []) as Ordonnance[]);
      } else if (addingType === 'radio') {
        // Pièce jointe : image ou PDF de l'examen (même stockage que le carnet du propriétaire).
        let imageUrl: string | null = null;
        if (formFichier) {
          const ext = formFichier.name.split('.').pop() ?? 'pdf';
          imageUrl = await uploadDocToStorage(formFichier, `radios/${user.uid}/${crypto.randomUUID()}.${ext}`);
        }
        const { error: eRadio } = await supabase.from('radios').insert({ ...base, id: crypto.randomUUID(), titre: formTitre.trim() || 'Radio / Examen', date: formDate, notes: formNotes.trim() || null,
          ...(imageUrl ? { image_url: imageUrl } : {}) });
        if (eRadio) { alert(`Radio non enregistrée : ${eRadio.message}`); return; }
        const { data } = await supabase.from('radios').select('*').eq('animal_id', animalId).order('date', { ascending: false });
        setRadios((data ?? []) as RadioEntry[]);
      } else if (addingType === 'cr') {
        const ownerUid = animal?.uid_proprietaire ?? animal?.uid_eleveur ?? null;
        const poidsCr = formPoids.trim() ? parseFloat(formPoids.replace(',', '.')) : null;
        // Actes du CR + actes déjà inscrits au carnet aujourd'hui (Synthèse, Santé).
        const duCarnet = (t: ActeCarnet['type']) => carnetJour.filter(a => a.type === t).map(a => a.libelle);
        const vaccinsTxt = [...vaccinsCr.map(v => v.nom + (v.lot ? ` (lot ${v.lot})` : '')), ...duCarnet('vaccin')];
        const traitementsTxt = [...traitementsCr.map(t => `${t.nom} — ${posologieComplete(t)}`), ...duCarnet('traitement')];
        const prescription = traitementsTxt.join(' ; ');
        let contenu = [
          formMotif.trim() && `Motif : ${formMotif.trim()}`,
          demandeClient.trim() && `Demande du client : ${demandeClient.trim()}`,
          poidsCr != null && !isNaN(poidsCr) && `Poids : ${poidsCr} kg`,
          actesRealises.length > 0 && `Actes réalisés : ${actesRealises.join(', ')}.`,
          formDiag.trim() && `Diagnostic : ${formDiag.trim()}`,
          // Texte libre du vétérinaire : précédé de « Recommandations : » (en gras dans le PDF).
          formNotes.trim() && (/^recommandations?\b/i.test(formNotes.trim()) ? formNotes.trim() : `Recommandations : ${formNotes.trim()}`),
          vaccinsTxt.length > 0 && `Vaccins : ${vaccinsTxt.join(', ')}.`,
          ...(([['vermifuge', 'Vermifuge'], ['antiparasitaire', 'Antiparasitaire'], ['allergie', 'Allergie / pathologie'],
            ['chirurgie', 'Chirurgie'], ['hospitalisation', 'Hospitalisation'], ['radio', 'Examen']] as const).map(([t, titre]) => {
            const l = [...soinsCr.filter(s => s.type === t).map(libelleSoin), ...duCarnet(t)];
            return l.length > 0 && `${titre} : ${l.join(', ')}.`;
          })),
          traitementsTxt.length > 0 && `Traitement : ${traitementsTxt.join(' ; ')}.`,
          produitsCr.length > 0 && `Produits délivrés : ${produitsCr.map(libelleProduit).join(', ')}.`,
        ].filter(Boolean).join('\n\n');
        // Modification d'un compte rendu validé : texte déjà présent (vaccins,
        // examens…) conservé, complété par les ajouts de même rubrique.
        if (crEdition) {
          const paras = contenu ? contenu.split('\n\n') : [];
          const fusion = crEdition.conserve.map(c => {
            const i = paras.findIndex(p => p.startsWith(`${c.titre} : `));
            if (i < 0) return `${c.titre} : ${c.corps}`;
            const ajout = paras.splice(i, 1)[0].slice(c.titre.length + 3).replace(/\.$/, '');
            const base = c.corps.replace(/\.$/, '');
            return base.includes(ajout) ? `${c.titre} : ${base}.` : `${c.titre} : ${base}${c.titre === 'Traitement' ? ' ; ' : ', '}${ajout}.`;
          });
          // Rubriques éditables d'abord (motif… recommandations), puis le reste.
          const edites = paras.filter(p => !TITRES_CR_CONSERVES.some(t => p.startsWith(`${t} : `)));
          const nouveaux = paras.filter(p => TITRES_CR_CONSERVES.some(t => p.startsWith(`${t} : `)));
          contenu = [...edites, ...fusion, ...nouveaux].join('\n\n');
        }
        // Profil du vétérinaire (multi-profil) ; statut contrôlé en base
        // (brouillon si l'auteur n'a pas le droit de valider — équipe clinique).
        const ligneCr = {
          animal_id: animalId, pro_uid: proUid, owner_uid: ownerUid, contenu: contenu || null,
          ...(crRdvId ? { rdv_id: crRdvId } : {}),
          ...(activeProfileId ? { pro_profile_id: activeProfileId,
            redige_par_profile_id: (esp.espace ? esp.monProfil : null) ?? activeProfileId,
            valide_par_profile_id: enBrouillon ? null : (esp.espace ? esp.monProfil : null) ?? activeProfileId } : {}),
          statut: enBrouillon ? 'brouillon' : 'valide', redige_par_uid: user.uid,
          ...(formMotif.trim() ? { motif: formMotif.trim() } : {}),
          ...(poidsCr != null && !isNaN(poidsCr) ? { poids: poidsCr } : {}),
          ...(actesRealises.length ? { actes: actesRealises } : {}),
          ...(prescription ? { prescription } : {}),
          ...(produitsCr.length ? { produits: produitsCr } : {}),
          // Saisie complète gardée avec le brouillon (format commun appli / site).
          ...(enBrouillon || brouillonId ? { brouillon: enBrouillon ? {
            motif: formMotif.trim(), poids: formPoids.trim(), texte: formNotes.trim(), diag: formDiag.trim(),
            demande: demandeClient.trim(), actes: actesRealises, vaccins: vaccinsCr, traitements: traitementsCr, produits: produitsCr, soins: soinsCr,
          } : null } : {}),
        };
        // « Modifier » un compte rendu validé : la ligne est mise à jour (reste
        // validée, modification tracée), ajouts inscrits au carnet ; ni
        // nouvelle notification ni facture ; retour au RDV.
        if (crEdition) {
          const ancien = crEdition.cr;
          const poidsOk = poidsCr != null && !isNaN(poidsCr) ? poidsCr : null;
          const { error } = await supabase.from('comptes_rendus').update({
            contenu: contenu || null, motif: formMotif.trim() || null, poids: poidsOk, actes: actesRealises,
            prescription: (ancien.prescription && prescription && !ancien.prescription.includes(prescription)
              ? `${ancien.prescription} ; ${prescription}` : ancien.prescription || prescription) || null,
            produits: [...(ancien.produits ?? []), ...produitsCr],
          }).eq('id', ancien.id);
          if (error) { alert(`Modification non enregistrée : ${error.message}`); return; }
          oublierCrEnCours();
          if (poidsOk != null && poidsOk !== ancien.poids && poidsOk !== poidsCarnet) {
            await supabase.from('poids').insert({ id: `${Date.now()}`, animal_id: animalId, valeur: poidsOk, date: new Date().toISOString(), notes: 'Consultation' });
            await supabase.from('animaux').update({ poids: poidsOk }).eq('id', animalId);
            setAnimal(a => a ? { ...a, poids: poidsOk } : a);
          }
          if (catPro === 'veterinaire' && (vaccinsCr.length || traitementsCr.length || soinsCr.length)) await ecrireActesCr(vetName, ownerUid);
          if (catPro === 'veterinaire' && produitsCr.length) await decompterStock(produitsCr);
          const { data } = await supabase.from('comptes_rendus').select('*').eq('animal_id', animalId).order('created_at', { ascending: false });
          setComptesRendus((data ?? []) as CompteRendu[]);
          setCrEdition(null);
          const rdvRetour = ancien.rdv_id ?? searchParams.get('rdv');
          if (rdvRetour) retourAuRdv(rdvRetour);
          return;
        }
        const { error: eCr } = brouillonId
          ? await supabase.from('comptes_rendus').update(ligneCr).eq('id', brouillonId)
          : await supabase.from('comptes_rendus').insert(ligneCr);
        if (eCr) { alert(`Erreur : ${eCr.message}`); return; }
        oublierCrEnCours();
        if (enBrouillon) {
          const { data } = await supabase.from('comptes_rendus').select('*').eq('animal_id', animalId).order('created_at', { ascending: false });
          setComptesRendus((data ?? []) as CompteRendu[]);
          if (crRdvId) retourAuRdv(crRdvId);
          return;
        }
        // Propriétaire prévenu, lien direct vers ce compte rendu.
        {
          let qCr = supabase.from('comptes_rendus').select('id').eq('animal_id', animalId);
          qCr = activeProfileId ? qCr.eq('pro_profile_id', activeProfileId) : qCr.eq('pro_uid', user.uid);
          const { data: dernier } = await qCr.order('created_at', { ascending: false }).limit(1).maybeSingle();
          await notifierCompteRendu(brouillonId ?? (dernier?.id as string | undefined));
        }
        // Pesée du jour → courbe de poids + poids de la fiche (sauf si c'est
        // la pesée déjà inscrite aujourd'hui depuis la Synthèse).
        if (poidsCr != null && !isNaN(poidsCr) && poidsCr !== poidsCarnet) {
          await supabase.from('poids').insert({ id: `${Date.now()}`, animal_id: animalId, valeur: poidsCr, date: new Date().toISOString(), notes: 'Consultation' });
          await supabase.from('animaux').update({ poids: poidsCr }).eq('id', animalId);
          setAnimal(a => a ? { ...a, poids: poidsCr } : a);
        }
        const { data } = await supabase.from('comptes_rendus').select('*').eq('animal_id', animalId).order('created_at', { ascending: false });
        setComptesRendus((data ?? []) as CompteRendu[]);
        if (catPro === 'veterinaire' && (vaccinsCr.length || traitementsCr.length || soinsCr.length)) {
          await ecrireActesCr(vetName, ownerUid);
        }
        if (catPro === 'veterinaire' && produitsCr.length) await decompterStock(produitsCr);
        // Visite à plusieurs animaux : une seule facture, une fois tous les CR faits.
        if (catPro === 'veterinaire' && !(crRdvId && await apresCrVisite(crRdvId))) {
          await proposerFacture(formMotif.trim(), actesRealises,
            [...vaccinsCr, ...carnetJour.flatMap(a => a.vaccin ? [a.vaccin] : [])], traitementsCr,
            poidsCr != null && !isNaN(poidsCr) ? poidsCr : null, produitsCr);
        }
        // Compte rendu d'un RDV : retour à la vue du RDV (sauf facture ou animal suivant ouverts).
        if (crRdvId && !navigationSuivie.current) retourAuRdv(crRdvId);
      } else if (addingType === 'mesure') {
        const updates: Record<string, number> = {};
        const kgSaisi = poidsKg(formPoids);
        if (kgSaisi != null) updates.poids = kgSaisi;
        if (formTaille.trim()) updates.taille = parseFloat(formTaille);
        if (carnetCommun) {
          // Fiche d'un autre pro : la fiche n'est pas modifiable, le poids va dans
          // la courbe (carnet commun) et le trigger le reporte sur la fiche.
          if (kgSaisi != null) {
            const { error: ep } = await supabase.from('poids').insert({ id: `${Date.now()}`, animal_id: animalId, valeur: kgSaisi, date: new Date().toISOString(), notes: 'Consultation' });
            if (ep) alert(`Poids non enregistré : ${ep.message}`);
            else setAnimal(a => a ? { ...a, poids: kgSaisi } : a);
          }
        } else if (Object.keys(updates).length > 0) {
          await supabase.from('animaux').update(updates).eq('id', animalId);
          setAnimal(a => a ? { ...a, ...updates } : a);
        }
      }
    } finally {
      setVaccinsCr([]); setTraitementsCr([]); setProduitsCr([]); setSoinsCr([]); setActesRealises([]); setAutreActe('');
      setCarnetJour([]); setPoidsCarnet(null); setBrouillonId(null);
      // Soin saisi depuis le compte rendu : retour au compte rendu (après les remises à zéro).
      if (retourCr && addingType !== 'cr') setTimeout(() => revenirAuCr(retourCr), 0);
      setFormNom(''); setFormLot(''); setFormRappel(''); setFormMotif(''); setFormDiag('');
      setFormNotes(''); setFormPosologie(''); setFormDateFin(''); setFormTitre('');
      setFormPoids(''); setFormTaille('');
      setFormDosage(''); setFormFrequence(''); setFormSubType(''); setFormIntitule('');
      setFormClinique(''); setFormPreop(''); setFormPostop(''); setFormStatut('prevu');
      setFormSeverite(''); setFormDescription('');
      setFormDate(new Date().toISOString().slice(0, 10));
      setAddingType(null); setSavingForm(false);
      setFreqN(''); setFreqU('mois'); setOptsVerm(optionsVermifugeVides()); setFormFichier(null);
      setSyntheseMaj(n => n + 1);
    }
  }

  // Notification à la famille — uniquement pour un compte rendu finalisé.
  async function notifierRapportEdu(isBilan: boolean) {
    const ownerUid = animal?.uid_proprietaire ?? animal?.uid_eleveur ?? null;
    if (!ownerUid || !animalId) return;
    const proNom = (userData?.nameElevage ?? (`${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim())) || 'Votre éducateur';
    const { data: propRow } = await supabase.from('animaux_proprietes')
      .select('profile_id_proprio').eq('animal_id', animalId).is('date_fin', null)
      .order('date_debut', { ascending: false }).limit(1).maybeSingle();
    await supabase.from('notifications').insert({
      uid: ownerUid, type: isBilan ? 'education_bilan' : 'education_rapport',
      title: `${isBilan ? 'Bilan comportemental' : 'Rapport de séance'} — ${animal?.nom ?? 'Animal'}`,
      body: `${proNom} a envoyé ${isBilan ? 'le bilan' : 'un rapport de séance'} pour ${animal?.nom ?? 'votre animal'}.`,
      ...(propRow?.profile_id_proprio ? { profile_id: propRow.profile_id_proprio } : {}),
      data: { animalId, animalNom: animal?.nom ?? 'Animal', url: `/mes-animaux/${animalId}?tab=education` },
      read: false,
    });
  }

  async function soumettreRapport(finalise = true) {
    if (!user?.uid || !animalId || richTextIsEmpty(rapportContenu)) return;
    setSavingRapport(true);
    try {
      const ownerUid = animal?.uid_proprietaire ?? animal?.uid_eleveur ?? null;
      const isBilan = rapportType === 'bilan';
      const extra: Record<string, unknown> = {
        statut: finalise ? 'finalise' : 'brouillon',
        pro_profile_id: activeProfileId || null,
        ...(seanceRdvId ? { rdv_id: seanceRdvId } : {}),
        type_seance: seanceType,
        lieu: seanceLieu.trim() || null,
        duree_minutes: seanceDuree.trim() ? Number(seanceDuree) : null,
        objectifs_travailles: seanceObjs,
        comportements: seanceDetaille ? (seanceComport.trim() || null) : null,
        difficultes: seanceDetaille ? (seanceDiff.trim() || null) : null,
        prochaine_etape: seanceDetaille ? (seanceProchaine.trim() || null) : null,
      };
      const ligne = {
        pro_uid: user.uid,
        animal_id: animalId,
        owner_uid: ownerUid,
        date_seance: new Date().toISOString().slice(0, 10),
        type: rapportType,
        contenu: rapportContenu.trim(),
        exercices_conseilles: !isBilan ? (rapportExercices.trim() || null) : null,
        ...(!isBilan && imputerForfait && forfaitActif ? { forfait_souscrit_id: forfaitActif.id } : {}),
        ...(isBilan ? {
          bilan_motif: bilanMotif.trim() || null,
          bilan_observations: rapportContenu.trim(),
          bilan_recommandation: bilanReco.trim() || null,
          bilan_nb_seances_estime: bilanNb.trim() ? Number(bilanNb) : null,
          bilan_forfait_conseille_id: bilanForfait || null,
        } : {}),
      };
      let { data: insRow, error: insErr } = await supabase.from('education_progression').insert({ ...ligne, ...extra }).select('id').single();
      // migration_education_fiche.sql pas encore passée : format d'origine (pas de brouillon).
      if (insErr) {
        if (!finalise) { alert('Brouillon indisponible : migration_education_fiche.sql à passer.'); return; }
        ({ data: insRow, error: insErr } = await supabase.from('education_progression').insert(ligne).select('id').single());
        if (insErr) throw insErr;
      }
      // Exercices de la bibliothèque joints au compte rendu → attribués à l'animal.
      const joints = !isBilan ? biblio.filter(b => crExos.includes(b.id)) : [];
      if (joints.length > 0 && insRow?.id) {
        const lignesExos = joints.map(b => ({
          exercice_id: b.id, pro_uid: user.uid, pro_profile_id: activeProfileId || null,
          animal_id: animalId, owner_uid: ownerUid, progression_id: insRow.id,
          titre_snapshot: b.titre, description_snapshot: b.description, media_snapshot: b.media ?? [],
        }));
        const { error: exErr } = await supabase.from('exercices_attribues')
          .insert(lignesExos.map((l, i) => ({ ...l, etapes_snapshot: joints[i].etapes ?? [], nb_validations: 1 })));
        // Repli sans les colonnes d'étapes (base pas encore migrée).
        if (exErr) await supabase.from('exercices_attribues').insert(lignesExos);
        // Visibles tout de suite dans Programme > Exercices.
        const { data: attr } = await supabase.from('exercices_attribues')
          .select('id, titre_snapshot, description_snapshot, cadence, echeance, statut, rappels_actifs, etapes_snapshot, nb_validations, validations').eq('animal_id', animalId).order('assigned_at', { ascending: false });
        if (attr) setAttribues(attr as EducAttribue[]);
      }
      // Rattaché à un RDV : rien n'est envoyé maintenant, tout part à la fin du
      // RDV (dossier de la séance → Terminer et envoyer).
      if (finalise && !seanceRdvId) await notifierRapportEdu(isBilan);
      if (!isBilan && imputerForfait && forfaitActif) await imputerSeanceForfait(forfaitActif);
      const { data } = await supabase.from('education_progression')
        .select('*').eq('animal_id', animalId).order('date_seance', { ascending: false });
      setRapports((data ?? []) as RapportEduP[]);
      // Ouvert depuis le dossier de la séance (éducateur) : retour au RDV.
      const retourRdv = searchParams.get('retourRdv');
      if (retourRdv && finalise) { allerOuFermer(router, retourDossierEducation(retourRdv)); return; }
      if (isBilan && finalise) {
        const params = new URLSearchParams({ prefill: '1', animal: animalId });
        if (ownerUid) params.set('clientUid', ownerUid);
        const { data: pp } = await supabase.from('animaux_proprietes')
          .select('profile_id_proprio').eq('animal_id', animalId).is('date_fin', null)
          .order('date_debut', { ascending: false }).limit(1).maybeSingle();
        if (pp?.profile_id_proprio) params.set('clientProfileId', pp.profile_id_proprio);
        if (owner?.lastname) params.set('nom', owner.lastname);
        if (owner?.firstname) params.set('prenom', owner.firstname);
        if (owner?.email) params.set('email', owner.email);
        const f = forfaitsEdu.find(x => x.id === bilanForfait);
        if (f) {
          params.set('ligneDesc', `Forfait ${f.nom} (${f.nb_seances} séances)`);
          params.set('ligneQte', '1');
          params.set('lignePrix', String(f.prix));
        }
        const objLibelles = objectifs.map(o => o.libelle).filter(Boolean);
        const noteParts: string[] = [];
        const recoPlain = richTextToPlain(bilanReco).trim();
        if (recoPlain) noteParts.push(recoPlain);
        if (objLibelles.length) noteParts.push(`Objectifs de travail : ${objLibelles.join(', ')}.`);
        if (noteParts.length) params.set('note', noteParts.join('\n\n'));
        setDevisPrefillUrl(`/education/devis?${params.toString()}`);
      }
      setRapportContenu(''); setRapportExercices(''); setShowAddRapport(false);
      setRapportType('seance'); setBilanMotif(''); setBilanReco(''); setBilanNb(''); setBilanForfait('');
      setSeanceType('individuelle'); setSeanceLieu(''); setSeanceDuree(''); setSeanceObjs([]);
      setCrExos([]); setCrExosOuvert(false); setNouvelObjSeance('');
      setSeanceDetaille(false); setSeanceComport(''); setSeanceDiff(''); setSeanceProchaine(''); setSeanceRdvId(null);
    } finally {
      setSavingRapport(false);
    }
  }

  function startEditRapport(r: { id: string; contenu: string; exercices_conseilles: string | null }) {
    setEditingRapportId(r.id);
    setRapportContenu(r.contenu);
    setRapportExercices(r.exercices_conseilles ?? '');
    setShowAddRapport(false);
  }

  async function saveEditRapport(finaliser = false) {
    if (!editingRapportId || richTextIsEmpty(rapportContenu)) return;
    setSavingRapport(true);
    try {
      const avant = rapports.find(r => r.id === editingRapportId);
      await supabase.from('education_progression').update({
        contenu: rapportContenu.trim(),
        exercices_conseilles: rapportExercices.trim() || null,
        ...(finaliser ? { statut: 'finalise' } : {}),
      }).eq('id', editingRapportId);
      if (finaliser && avant?.statut === 'brouillon') {
        if (!(avant as { rdv_id?: string | null }).rdv_id) await notifierRapportEdu(avant.type === 'bilan');
        setRapports(prev => prev.map(r => r.id === editingRapportId ? { ...r, statut: 'finalise' } : r));
      }
      setRapports(prev => prev.map(r => r.id === editingRapportId
        ? { ...r, contenu: rapportContenu.trim(), exercices_conseilles: rapportExercices.trim() || null }
        : r));
      setEditingRapportId(null); setRapportContenu(''); setRapportExercices('');
    } finally {
      setSavingRapport(false);
    }
  }

  async function deleteRapport(id: string) {
    await supabase.from('education_progression').delete().eq('id', id);
    setRapports(prev => prev.filter(r => r.id !== id));
    setDeleteRapportConfirmId(null);
  }

  // ── Objectifs (plan de travail) ──
  async function ajouterObjectifSeance() {
    const libelle = nouvelObjSeance.trim();
    if (!libelle || !user?.uid || !animalId) return;
    setAjoutObjSeance(true);
    try {
      const ownerUid = animal?.uid_proprietaire ?? animal?.uid_eleveur ?? null;
      const { data, error } = await supabase.from('education_objectifs').insert({
        libelle, statut: 'a_travailler', pro_uid: user.uid, pro_profile_id: activeProfileId || null,
        animal_id: animalId, owner_uid: ownerUid, ordre: objectifs.length,
      }).select('id').single();
      if (error || !data) { alert('Ajout de l’objectif impossible, réessayez.'); return; }
      await reloadObjectifs();
      setSeanceObjs(v => [...v, data.id as string]);
      setNouvelObjSeance('');
    } finally {
      setAjoutObjSeance(false);
    }
  }

  async function ouvrirExosCr() {
    setCrExosOuvert(v => !v);
    if (biblio.length > 0 || !user?.uid) return;
    const { data } = await supabase.from('exercices_bibliotheque')
      .select('id, titre, description, media, etapes').eq('pro_uid', user.uid).eq('actif', true).order('created_at', { ascending: false });
    setBiblio((data ?? []) as EducExercice[]);
  }

  async function reloadObjectifs() {
    const { data } = await supabase.from('education_objectifs')
      .select('id, libelle, categorie, statut, note, ordre').eq('animal_id', animalId).order('ordre').order('created_at');
    setObjectifs((data ?? []) as EducObjectif[]);
  }

  async function notifyOwnerObjectif(libelle: string) {
    const ownerUid = animal?.uid_proprietaire ?? animal?.uid_eleveur ?? null;
    if (!ownerUid) return;
    const proNom = (userData?.nameElevage ?? (`${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim())) || 'Votre éducateur';
    const { data: propRow } = await supabase.from('animaux_proprietes')
      .select('profile_id_proprio').eq('animal_id', animalId).is('date_fin', null).limit(1).maybeSingle();
    await supabase.from('notifications').insert({
      uid: ownerUid, type: 'education_objectif_acquis',
      title: `Objectif atteint — ${animal?.nom ?? 'votre animal'} 🎉`,
      body: `${proNom} a validé « ${libelle} ».`,
      ...(propRow?.profile_id_proprio ? { profile_id: propRow.profile_id_proprio } : {}),
      data: { animalId, animalNom: animal?.nom ?? 'Animal', url: `/mes-animaux/${animalId}?tab=education` },
    });
  }

  async function saveObjectif() {
    if (!objForm || !objForm.libelle.trim() || !user?.uid) return;
    setSavingObj(true);
    try {
      const wasAcquis = objForm.id ? objectifs.find(o => o.id === objForm.id)?.statut === 'acquis' : false;
      const now = new Date().toISOString();
      const payload: Record<string, unknown> = {
        libelle: objForm.libelle.trim(),
        categorie: objForm.categorie || null,
        statut: objForm.statut,
        note: richTextIsEmpty(objForm.note) ? null : objForm.note.trim(),
        updated_at: now,
        acquis_le: objForm.statut === 'acquis' ? (wasAcquis ? undefined : now) : null,
      };
      const extra = { prioritaire: !!objForm.prioritaire, difficultes: objForm.difficultes?.trim() || null };
      const ecrire = async (champs: Record<string, unknown>) => {
        if (objForm.id) return supabase.from('education_objectifs').update(champs).eq('id', objForm.id);
        const ownerUid = animal?.uid_proprietaire ?? animal?.uid_eleveur ?? null;
        return supabase.from('education_objectifs').insert({
          ...champs, pro_uid: user.uid, pro_profile_id: activeProfileId || null,
          animal_id: animalId, owner_uid: ownerUid, ordre: objectifs.length,
        });
      };
      // Repli sans les colonnes de migration_education_fiche.sql.
      const { error: e1 } = await ecrire({ ...payload, ...extra });
      if (e1) await ecrire(payload);
      if (objForm.statut === 'acquis' && !wasAcquis) await notifyOwnerObjectif(objForm.libelle.trim());
      setObjForm(null);
      await reloadObjectifs();
    } finally {
      setSavingObj(false);
    }
  }

  async function setObjectifStatut(o: EducObjectif, statut: string) {
    const wasAcquis = o.statut === 'acquis';
    setObjectifs(prev => prev.map(x => x.id === o.id ? { ...x, statut } : x));
    const now = new Date().toISOString();
    await supabase.from('education_objectifs').update({
      statut, updated_at: now, acquis_le: statut === 'acquis' ? (wasAcquis ? undefined : now) : null,
    }).eq('id', o.id);
    if (statut === 'acquis' && !wasAcquis) await notifyOwnerObjectif(o.libelle);
  }

  async function deleteObjectif(id: string) {
    await supabase.from('education_objectifs').delete().eq('id', id);
    setObjectifs(prev => prev.filter(o => o.id !== id));
  }

  // ── Exercices attribués ──
  async function openAttrPicker() {
    if (!user?.uid) return;
    const { data } = await supabase.from('exercices_bibliotheque')
      .select('id, titre, description, media, etapes').eq('pro_uid', user.uid).eq('actif', true).order('created_at', { ascending: false });
    setBiblio((data ?? []) as EducExercice[]);
    setAttrPicker({ ids: new Set(), cadence: '', echeance: echeanceDans(DUREE_DEFAUT_JOURS) ?? '', rappels: false, duree: DUREE_DEFAUT_JOURS, nbValidations: 1 });
  }

  async function attribuerExercices() {
    if (!attrPicker || attrPicker.ids.size === 0 || !user?.uid) return;
    setSavingAttr(true);
    try {
      const ownerUid = animal?.uid_proprietaire ?? animal?.uid_eleveur ?? null;
      const chosen = biblio.filter(b => attrPicker.ids.has(b.id));
      await supabase.from('exercices_attribues').insert(chosen.map(b => ({
        exercice_id: b.id, pro_uid: user.uid, pro_profile_id: activeProfileId || null,
        animal_id: animalId, owner_uid: ownerUid,
        titre_snapshot: b.titre, description_snapshot: b.description, media_snapshot: b.media ?? [],
        cadence: attrPicker.cadence.trim() || null,
        echeance: attrPicker.echeance || null,
        etapes_snapshot: b.etapes ?? [],
        nb_validations: (b.etapes ?? []).length ? 1 : attrPicker.nbValidations,
        rappels_actifs: attrPicker.rappels,
      })));
      if (ownerUid) {
        const proNom = (userData?.nameElevage ?? (`${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim())) || 'Votre éducateur';
        const { data: propRow } = await supabase.from('animaux_proprietes')
          .select('profile_id_proprio').eq('animal_id', animalId).is('date_fin', null).limit(1).maybeSingle();
        await supabase.from('notifications').insert({
          uid: ownerUid, type: 'education_exercice_assigne',
          title: `Nouveaux exercices — ${animal?.nom ?? 'votre animal'}`,
          body: `${proNom} a ajouté ${chosen.length} exercice${chosen.length > 1 ? 's' : ''} à faire.`,
          ...(propRow?.profile_id_proprio ? { profile_id: propRow.profile_id_proprio } : {}),
          data: { animalId, animalNom: animal?.nom ?? 'Animal', url: `/mes-animaux/${animalId}?tab=education` },
        });
      }
      setAttrPicker(null);
      const { data } = await supabase.from('exercices_attribues')
        .select('id, titre_snapshot, description_snapshot, cadence, echeance, statut, rappels_actifs, etapes_snapshot, nb_validations, validations').eq('animal_id', animalId).order('assigned_at', { ascending: false });
      setAttribues((data ?? []) as EducAttribue[]);
    } finally {
      setSavingAttr(false);
    }
  }

  async function retirerAttribue(id: string) {
    await supabase.from('exercices_attribues').delete().eq('id', id);
    setAttribues(prev => prev.filter(a => a.id !== id));
  }

  const forfaitActif = forfaitsSous.find(f => f.statut === 'actif') ?? null;

  async function reloadForfaitsSous() {
    const { data } = await supabase.from('forfaits_souscrits')
      .select('id, nom_snapshot, nb_seances_total, nb_seances_utilisees, statut').eq('animal_id', animalId).order('souscrit_le', { ascending: false });
    setForfaitsSous(((data ?? []) as ForfaitSous[]).filter(f => f.statut !== 'annule'));
  }

  async function registerForfaitSous(nom: string, nb: number, prix: number | null, forfaitId: string | null) {
    if (!nom.trim() || !user?.uid) return;
    const ownerUid = animal?.uid_proprietaire ?? animal?.uid_eleveur ?? null;
    await supabase.from('forfaits_souscrits').insert({
      ...(forfaitId ? { forfait_id: forfaitId } : {}),
      pro_uid: user.uid, pro_profile_id: activeProfileId || null,
      client_uid: ownerUid, animal_id: animalId,
      nom_snapshot: nom.trim(), nb_seances_total: nb || 1, ...(prix != null ? { prix_snapshot: prix } : {}),
    });
    setShowForfaitSousForm(false);
    await reloadForfaitsSous();
  }

  async function imputerSeanceForfait(f: ForfaitSous) {
    const used = f.nb_seances_utilisees + 1;
    const termine = used >= f.nb_seances_total;
    await supabase.from('forfaits_souscrits').update({
      nb_seances_utilisees: used,
      ...(termine ? { statut: 'termine', termine_le: new Date().toISOString() } : {}),
    }).eq('id', f.id);
    if (used === f.nb_seances_total - 1 || termine) {
      const ownerUid = animal?.uid_proprietaire ?? animal?.uid_eleveur ?? null;
      if (ownerUid) {
        await supabase.from('notifications').insert({
          uid: ownerUid, type: 'education_forfait_bas',
          title: `Forfait ${termine ? 'terminé' : 'bientôt terminé'} — ${animal?.nom ?? 'votre animal'}`,
          body: termine
            ? `Toutes les séances du forfait « ${f.nom_snapshot} » ont été utilisées.`
            : `Il reste 1 séance sur le forfait « ${f.nom_snapshot} ».`,
          data: { animalId, url: `/mes-animaux/${animalId}?tab=education` },
        });
      }
    }
    await reloadForfaitsSous();
  }

  const [genAttest, setGenAttest] = useState(false);
  async function genererAttestation() {
    if (!user?.uid || (rapports.length === 0 && objectifs.length === 0)) return;
    setGenAttest(true);
    try {
      const { jsPDF } = await import('jspdf');
      const doc = new jsPDF({ unit: 'pt', format: 'a4' });
      const proNom = (userData?.nameElevage ?? (`${userData?.firstname ?? ''} ${userData?.lastname ?? ''}`.trim())) || 'Éducateur canin';
      const acquis = objectifs.filter(o => o.statut === 'acquis');
      const autres = objectifs.filter(o => o.statut !== 'acquis');
      const dates = rapports.map(r => r.date_seance).filter(Boolean).sort();
      const periode = dates.length ? ` du ${new Date(dates[0]).toLocaleDateString('fr-FR')} au ${new Date(dates[dates.length - 1]).toLocaleDateString('fr-FR')}` : '';
      let y = 60;
      doc.setFillColor(239, 108, 0); doc.rect(40, 40, 515, 54, 'F');
      doc.setTextColor(255).setFont('helvetica', 'bold').setFontSize(17);
      doc.text('Attestation de fin de programme', 54, 68);
      doc.setFontSize(10).setFont('helvetica', 'normal');
      doc.text(`Suivi comportemental — ${animal?.nom ?? ''}`, 54, 84);
      y = 130;
      doc.setTextColor(30).setFontSize(11);
      const intro = doc.splitTextToSize(
        `Je soussigné(e) ${proNom}, atteste avoir accompagné ${animal?.nom ?? 'cet animal'} dans un programme d'éducation${periode}, à raison de ${rapports.length} séance${rapports.length > 1 ? 's' : ''}.`, 515);
      doc.text(intro, 40, y); y += intro.length * 15 + 14;
      if (acquis.length) {
        doc.setFont('helvetica', 'bold').setTextColor(239, 108, 0).text('Objectifs atteints', 40, y); y += 16;
        doc.setFont('helvetica', 'normal').setTextColor(30).setFontSize(10);
        acquis.forEach(o => { doc.text(`•  ${o.libelle}`, 48, y); y += 14; });
        y += 8;
      }
      if (autres.length) {
        doc.setFont('helvetica', 'bold').setTextColor(110).setFontSize(11).text('Axes de travail à poursuivre', 40, y); y += 16;
        doc.setFont('helvetica', 'normal').setTextColor(30).setFontSize(10);
        autres.forEach(o => { doc.text(`•  ${o.libelle}`, 48, y); y += 14; });
      }
      doc.setFontSize(10).setTextColor(30);
      doc.text(`Fait le ${new Date().toLocaleDateString('fr-FR')}`, 40, 760);
      doc.text(proNom, 515, 760, { align: 'right' });
      const blob = doc.output('blob');
      const path = `attestations/${user.uid}/${animalId}_${Date.now()}.pdf`;
      // Stockage privé : ouverture via lien temporaire (lien-document)
      const { error } = await supabase.storage.from('documents').upload(path, blob, { upsert: true, contentType: 'application/pdf' });
      if (error) throw error;
      const { data: pub } = supabase.storage.from('documents').getPublicUrl(path);
      const ownerUid = animal?.uid_proprietaire ?? animal?.uid_eleveur ?? null;
      await supabase.from('education_attestations').insert({
        animal_id: animalId, pro_uid: user.uid, pro_profile_id: activeProfileId || null,
        owner_uid: ownerUid, pdf_url: pub.publicUrl,
        contenu: { objectifs_atteints: acquis.map(o => o.libelle), nb_seances: rapports.length },
      });
      if (ownerUid) {
        await supabase.from('notifications').insert({
          uid: ownerUid, type: 'education_attestation',
          title: `Attestation de fin de programme — ${animal?.nom ?? 'votre animal'}`,
          body: `${proNom} vous a remis l'attestation.`,
          data: { animalId, url: `/mes-animaux/${animalId}?tab=education` },
        });
      }
      void ouvrirDocument(pub.publicUrl);
    } finally {
      setGenAttest(false);
    }
  }

  // ── Exercices en PDF (famille sans compte) ────────────────────────────────
  const [genExosPdf, setGenExosPdf] = useState(false);
  async function envoyerExercicesPdf() {
    if (!user?.uid || attribues.length === 0) return;
    setGenExosPdf(true);
    try {
      const { jsPDF } = await import('jspdf');
      const doc = new jsPDF({ unit: 'pt', format: 'a4' });
      let y = 60;
      doc.setFillColor(239, 108, 0); doc.rect(40, 40, 515, 54, 'F');
      doc.setTextColor(255).setFont('helvetica', 'bold').setFontSize(17);
      doc.text('Programme d\'éducation', 54, 68);
      doc.setFontSize(10).setFont('helvetica', 'normal');
      doc.text(animal?.nom ?? '', 54, 84);
      y = 130;
      for (const e of attribues) {
        if (y > 720) { doc.addPage(); y = 60; }
        doc.setTextColor(30).setFont('helvetica', 'bold').setFontSize(12);
        doc.text(e.titre_snapshot, 40, y); y += 16;
        if (e.cadence || e.echeance) {
          doc.setFont('helvetica', 'normal').setTextColor(110).setFontSize(9);
          doc.text([e.cadence ? `Fréquence : ${e.cadence}` : null, e.echeance ? `À faire avant le : ${e.echeance}` : null]
            .filter(Boolean).join('  ·  '), 40, y);
          y += 14;
        }
        if (e.description_snapshot) {
          doc.setFont('helvetica', 'normal').setTextColor(30).setFontSize(10);
          const lines = doc.splitTextToSize(richTextToPlain(e.description_snapshot), 515);
          doc.text(lines, 40, y); y += lines.length * 13 + 18;
        } else {
          y += 10;
        }
      }
      const blob = doc.output('blob');
      const path = `exercices_pdf/${user.uid}/${animalId}_${Date.now()}.pdf`;
      const { error } = await supabase.storage.from('media').upload(path, blob, { upsert: true, contentType: 'application/pdf' });
      if (error) throw error;
      const { data: pub } = supabase.storage.from('media').getPublicUrl(path);
      window.open(pub.publicUrl, '_blank');
    } finally {
      setGenExosPdf(false);
    }
  }

  // ── Lien de suivi (famille sans compte) ────────────────────────────────────
  const [showSuiviLien, setShowSuiviLien] = useState(false);
  const [suiviLien, setSuiviLien] = useState<string | null>(null);
  const [genSuiviLien, setGenSuiviLien] = useState(false);
  async function genererSuiviLien() {
    if (!user?.uid) return;
    setGenSuiviLien(true);
    try {
      const expireAt = new Date(); expireAt.setDate(expireAt.getDate() + 30);
      const { data, error } = await supabase.from('partage_suivi_education').insert({
        animal_id: animalId, pro_uid: user.uid,
        ...(activeProfileId ? { pro_profile_id: activeProfileId } : {}),
        expire_at: expireAt.toISOString(), actif: true,
      }).select('token').single();
      if (error) throw error;
      setSuiviLien(`${window.location.origin}/suivi/${data.token}`);
      setShowSuiviLien(true);
    } finally {
      setGenSuiviLien(false);
    }
  }

  async function envoyerReponse(attributionId: string) {
    if (!replyNote.trim() || !user?.uid) return;
    await supabase.from('exercices_retours').insert({
      attribution_id: attributionId, author_uid: user.uid, author_profile_id: activeProfileId || null,
      note: replyNote.trim(), from_pro: true, vu_par_pro: true,
    });
    const ownerUid = animal?.uid_proprietaire ?? animal?.uid_eleveur ?? null;
    if (ownerUid) {
      await supabase.from('notifications').insert({
        uid: ownerUid, type: 'education_rapport',
        title: `Message de l'éducateur — ${animal?.nom ?? 'votre animal'}`,
        body: 'À propos d\'un exercice.',
        data: { animalId, url: `/mes-animaux/${animalId}?tab=education` },
      });
    }
    setReplyFor(null); setReplyNote('');
    const { data: rt } = await supabase.from('exercices_retours')
      .select('id, attribution_id, note, media, ressenti, from_pro')
      .in('attribution_id', attribues.map(a => a.id)).order('created_at');
    const grouped: Record<string, EducRetour[]> = {};
    for (const row of (rt ?? []) as EducRetour[]) (grouped[row.attribution_id] ??= []).push(row);
    setRetours(grouped);
  }

  async function requestWriteAccess() {
    if (!user || !grant || !animal) return;
    setRequestingWrite(true);
    await supabase.from('animal_access').update({ statut: 'write_requested' }).eq('id', grant.id);
    setGrant(g => g ? { ...g, statut: 'write_requested' } : g);
    const ownerUid = animal.uid_proprietaire ?? animal.uid_eleveur;
    if (ownerUid) {
      const { data: propRow } = await supabase.from('animaux_proprietes')
        .select('profile_id_proprio').eq('animal_id', animalId).is('date_fin', null)
        .order('date_debut', { ascending: false }).limit(1).maybeSingle();
      await supabase.from('notifications').insert({
        uid: ownerUid, type: 'write_access_requested',
        title: "Demande d'accès en écriture",
        body: `${userData?.nameElevage ?? userData?.firstname ?? 'Un professionnel'} demande l'accès en écriture pour ${animal.nom}.`,
        ...(propRow?.profile_id_proprio ? { profile_id: propRow.profile_id_proprio } : {}),
        data: { grant_id: grant.id, animal_id: String(animalId) }, read: false,
      });
    }
    setRequestingWrite(false);
  }


  if (!user) return null;
  if (loading) return (
    <div className="min-h-screen flex items-center justify-center">
      <div className="w-8 h-8 border-4 border-t-transparent rounded-full animate-spin" style={{ borderColor: TEAL, borderTopColor: 'transparent' }} />
    </div>
  );
  if (!animal) return (
    <div className="min-h-screen flex items-center justify-center text-gray-400 text-sm">Animal introuvable ou accès refusé.</div>
  );


  return (
    <div className="min-h-screen bg-[#F8F8F8]">

      {/* ── Header ── */}
      <div style={{ background: TEAL }} className="text-white">
        <div className="max-w-3xl mx-auto px-4 pt-4 pb-2 flex items-center gap-3">
          <button onClick={() => router.back()} className="p-2 rounded-lg bg-white/10 hover:bg-white/20 transition-colors">←</button>
          <span className="font-bold text-base flex-1" style={{ fontFamily: 'Galey, sans-serif' }}>
            {catPro === 'garde' ? 'Animal en garde' : catPro === 'education' ? 'Animal suivi' : catPro === 'toilettage' ? 'Fiche toilettage' : 'Fiche patient'}
          </span>
          {(catPro === 'education' || catPro === 'garde') && user && (
            <OwnerContactButton
              animalId={animalId}
              animalNom={animal.nom ?? 'Animal'}
              ownerUid={animal.uid_proprietaire ?? animal.uid_eleveur ?? null}
              myUid={user.uid}
              myProfileId={activeProfileId ?? null}
              className="bg-white/10 hover:bg-white/20 !text-white"
            />
          )}
          {hasWriteAccess && (
            <span className="text-[10px] font-bold bg-green-400/30 text-green-100 px-2 py-0.5 rounded-full">✏️ Écriture</span>
          )}
          {isPending && (
            <span className="text-[10px] font-bold bg-amber-400/30 text-amber-100 px-2 py-0.5 rounded-full">⏳ En attente</span>
          )}
          {identiteSeule && (
            <span className="text-[10px] font-bold bg-white/20 text-white px-2 py-0.5 rounded-full">Identité seule</span>
          )}
        </div>

        {searchParams.get('retourRdv') && (
          <div className="max-w-3xl mx-auto px-4 pt-3">
            <button type="button" onClick={() => allerOuFermer(router, retourDossierEducation(searchParams.get('retourRdv')!))}
              className="w-full text-left text-sm font-semibold rounded-xl px-3 py-2 bg-white/90 text-[#0C5C6C]">
              ← Revenir au dossier de la séance
            </button>
          </div>
        )}
        {/* Animal summary */}
        <div className="max-w-3xl mx-auto px-4 py-3 flex items-center gap-4">
          <div className="w-16 h-16 rounded-2xl overflow-hidden bg-white/20 flex-shrink-0 flex items-center justify-center">
            {animal.photo_url
              ? <Image src={animal.photo_url} alt="" width={64} height={64} className="object-cover w-full h-full" />
              : <span className="text-3xl">{ESPECE_EMOJI[animal.espece?.toLowerCase()] ?? ''}</span>
            }
          </div>
          <div className="min-w-0">
            <h2 className="text-xl font-bold" style={{ fontFamily: 'Galey, sans-serif' }}>{animal.nom}</h2>
            <p className="text-white/70 text-sm">{[animal.race, animal.espece].filter(Boolean).join(' · ')}{animal.date_naissance ? ` · ${calcAge(animal.date_naissance)}` : ''}</p>
            <div className="flex flex-wrap gap-1.5 mt-1">
              {animal.sexe && <span className="text-[10px] bg-white/20 px-2 py-0.5 rounded-full capitalize">{animal.sexe}</span>}
              {animal.sterilise && <span className="text-[10px] bg-white/20 px-2 py-0.5 rounded-full">Stérilisé(e)</span>}
              {animal.poids && <span className="text-[10px] bg-white/20 px-2 py-0.5 rounded-full">{animal.poids} kg</span>}
              {animal.identification && <span className="text-[10px] bg-white/20 px-2 py-0.5 rounded-full font-mono">🔖 {animal.identification}</span>}
            </div>
          </div>
        </div>

        {/* Tabs */}
        <div className="max-w-3xl mx-auto px-4 overflow-x-auto pb-0">
          <div className="flex gap-1 bg-white/10 rounded-xl p-1 min-w-max">
            {TABS.map(t => (
              <button key={t} onClick={() => setTab(t)}
                className="whitespace-nowrap px-4 py-2 text-sm font-semibold rounded-lg transition-colors"
                style={{
                  background: tab === t ? 'white' : 'transparent',
                  color: tab === t ? TEAL : 'rgba(255,255,255,0.75)',
                  fontFamily: 'Galey, sans-serif',
                }}>
                {t}
              </button>
            ))}
          </div>
        </div>
        <div className="h-4" />
      </div>

      {/* ── Content ── */}
      <div className="max-w-3xl mx-auto px-4 py-5 space-y-4">
        {/* Propriétaire : appeler, message, urgence, personnes autorisées (garde / pension). */}
        {user && <ProAnimalEntete animalId={String(animal.id)} catPro={catPro} myUid={user.uid} myProfileId={activeProfileId || null} />}

        {/* ── Identité ── */}
        {/* ── Véto / ostéo : Synthèse, Documents, sous-onglets Santé ── */}
        {tab === 'Synthèse' && catPro === 'veterinaire' && (
          <SyntheseVet key={syntheseMaj} animalId={animalId} pid={activeProfileId || null} onIdentite={() => setTab('Identité')}
            peutEcrire={hasWriteAccess}
            onFaireRappel={hasWriteAccess ? (vaccin, rappel) => {
              setFormNom(vaccin); setFormDate(new Date().toLocaleDateString('sv-SE')); setFormRappel(rappel); setAddingType('vaccin');
            } : undefined} />
        )}
        {tab === 'Synthèse' && catPro === 'sante' && (
          <SyntheseOsteo animalId={animalId} pid={activeProfileId || null} onIdentite={() => setTab('Identité')} onSeances={() => setTab('Séances')} />
        )}
        {tab === 'Documents' && (catPro === 'veterinaire' || catPro === 'sante') && (
          <DocumentsSantePro animalId={animalId} pid={activeProfileId || null} osteo={catPro === 'sante'} />
        )}
        {catPro === 'veterinaire' && ['Santé', 'Repro', 'Ostéo / Kiné'].includes(tab) && (
          <div className="flex gap-2">
            {([['Santé', 'Carnet de santé'], ['Repro', 'Reproduction'], ['Ostéo / Kiné', 'Ostéo / Kiné']] as const).map(([t, l]) => (
              <button key={t} onClick={() => setTab(t)} className="px-3 py-1.5 rounded-full text-xs font-semibold"
                style={tab === t ? { background: TEAL, color: 'white' } : { background: '#F1F4F3', color: '#1F2A2E' }}>{l}</button>
            ))}
          </div>
        )}
        {catPro === 'sante' && ['Identité', 'Santé', 'Repro'].includes(tab) && (
          <div className="flex gap-2">
            {([['Identité', 'Identité'], ['Santé', 'Carnet de santé']] as const).map(([t, l]) => (
              <button key={t} onClick={() => setTab(t)} className="px-3 py-1.5 rounded-full text-xs font-semibold"
                style={tab === t ? { background: TEAL, color: 'white' } : { background: '#F1F4F3', color: '#1F2A2E' }}>{l}</button>
            ))}
          </div>
        )}

        {tab === 'Identité' && (
          <>
            <Card title="Identité">
              <InfoGrid rows={[
                { label: 'Espèce',        value: animal.espece },
                { label: 'Race',          value: animal.race },
                { label: 'Sexe',          value: animal.sexe },
                { label: 'Couleur/Robe',  value: animal.couleur },
                { label: 'Couleur des yeux',  value: animal.couleur_yeux },
                { label: 'Date de naissance', value: fmtDate(animal.date_naissance) },
                { label: 'Âge',           value: calcAge(animal.date_naissance) },
                { label: 'Poids',         value: animal.poids ? `${animal.poids} kg` : null },
                { label: 'Taille',        value: animal.taille ? `${animal.taille} cm` : null },
                { label: 'Identification',value: animal.identification },
                { label: 'Passeport',     value: animal.passeport_numero },
                { label: 'Stérilisé(e)', value: animal.sterilise === true ? 'Oui' : animal.sterilise === false ? 'Non' : null },
              ]} />
            </Card>

            {animal.notes && (
              <Card title="Notes du propriétaire">
                <p className="text-sm text-gray-600 whitespace-pre-wrap">{animal.notes}</p>
              </Card>
            )}

            {/* Accès en écriture pour non-vets */}
            {!isVet && grant && !identiteSeule && (
              <Card title="Accès au dossier">
                {hasWriteAccess ? (
                  <div className="flex items-center gap-2 text-green-600 text-sm">
                    <span>✓</span>
                    <p>Accès en écriture accordé — vous pouvez noter des observations.</p>
                  </div>
                ) : writeRequested ? (
                  <div className="flex items-center gap-2 text-amber-600 text-sm bg-amber-50 rounded-xl p-3">
                    <span>⏳</span>
                    <p>Demande d&apos;accès en écriture envoyée, en attente de validation.</p>
                  </div>
                ) : (
                  <>
                    <p className="text-sm text-gray-500 mb-3">Accès en lecture. En cas de besoin, demandez l&apos;accès en écriture au propriétaire.</p>
                    <button onClick={requestWriteAccess} disabled={requestingWrite}
                      className="text-sm font-semibold text-white px-4 py-2 rounded-xl transition-colors disabled:opacity-50"
                      style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
                      {requestingWrite ? '…' : "Demander l'accès en écriture"}
                    </button>
                  </>
                )}
              </Card>
            )}

            {isPending && (
              <div className="bg-amber-50 border border-amber-200 rounded-2xl p-4 flex gap-3">
                <span className="text-xl">⏳</span>
                <div>
                  <p className="font-semibold text-amber-800 text-sm">En attente d&apos;approbation</p>
                  <p className="text-xs text-amber-600 mt-0.5">Le propriétaire n&apos;a pas encore validé votre accès à ce dossier.</p>
                </div>
              </div>
            )}
          </>
        )}

        {/* ── Santé ── */}
        {tab === 'Santé' && identiteSeule && !carnetCommun && (
          <div className="bg-white rounded-2xl border border-gray-100 p-6 text-center">
            <p className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Carnet de santé privé</p>
            <p className="text-sm text-gray-600 mt-1">La fiche de cet animal a été créée par un autre professionnel. Vous voyez son identité et vos propres documents ; son carnet et les documents de l’autre professionnel restent privés tant que le propriétaire ne les a pas partagés.</p>
          </div>
        )}
        {tab === 'Santé' && (!identiteSeule || carnetCommun) && (() => {
          // Vétérinaire avec l'accès en écriture : « + Ajouter » sur chaque rubrique du carnet
          // (carnet commun : pas les chirurgies ni les radios, documents propres à chaque pro).
          const ajout = (t: AddType) => isVet && (hasWriteAccess || (carnetCommun && t !== 'chirurgie' && t !== 'radio')) ? (
            <button type="button" onClick={() => setAddingType(t)}
              className="text-xs font-semibold px-3 py-1.5 rounded-lg border border-[#0C5C6C] text-[#0C5C6C] hover:bg-[#0C5C6C]/5">+ Ajouter</button>
          ) : undefined;
          return (
          <>
            {carnetCommun && (
              <p className="text-xs text-gray-600 bg-[#F4F7F8] border border-gray-200 rounded-lg px-3 py-2">
                Fiche créée par un autre professionnel : carnet commun (vaccins, vermifuges, antiparasitaires, poids, allergies, traitements) partagé entre les professionnels de santé. Les comptes rendus, ordonnances, radios et chirurgies de chacun restent privés.
              </p>
            )}
            {isPensionType && (
              <div className="bg-blue-50 border border-blue-200 rounded-2xl p-3 flex gap-2 items-center text-blue-700 text-xs font-medium">
                <span>📖</span><span>Lecture seule — accordé par le propriétaire</span>
              </div>
            )}

            {/* Vaccins */}
            <Card title={`💉 Vaccinations (${vaccins.length})`} action={ajout('vaccin')}>
              {vaccins.length === 0 ? <EmptyState text="Aucun vaccin enregistré" /> : (
                <div className="space-y-3">
                  {vaccins.map(v => {
                    const due = v.date_rappel && new Date(v.date_rappel) <= new Date();
                    return (
                      <div key={v.id} className="border border-gray-100 rounded-xl p-3 flex items-start gap-3">
                        <div className="w-8 h-8 rounded-lg bg-[#E3F2FD] flex items-center justify-center text-sm flex-shrink-0">💉</div>
                        <div className="flex-1 min-w-0">
                          <p className="font-semibold text-sm text-[#1F2A2E]">{v.vaccin}</p>
                          <p className="text-xs text-gray-500">Injecté le {fmtDateShort(v.date)}</p>
                          {v.date_rappel && (
                            <p className={`text-xs font-medium mt-0.5 ${due ? 'text-red-500' : 'text-[#0C5C6C]'}`}>
                              {due ? '⚠️ Rappel dû' : '📅 Rappel'} le {fmtDateShort(v.date_rappel)}
                            </p>
                          )}
                          {v.lot && <p className="text-xs text-gray-400">Lot : {v.lot}</p>}
                          {v.veterinaire && <p className="text-xs text-gray-400">Dr {v.veterinaire}</p>}
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
            </Card>

            {/* Visites : doublon des consultations pour le vétérinaire (comptes rendus). */}
            {!isVet && (
            <Card title={`🩺 Visites vétérinaires (${visites.length})`}>
              {visites.length === 0 ? <EmptyState text="Aucune visite enregistrée" /> : (
                <div className="space-y-3">
                  {visites.map(v => (
                    <div key={v.id} className="border border-gray-100 rounded-xl p-3">
                      <div className="flex items-center justify-between mb-1">
                        <p className="font-semibold text-sm text-[#1F2A2E]">{fmtDateShort(v.date)}</p>
                        {v.motif && <span className="text-[10px] bg-[#E3F2FD] text-[#0C5C6C] px-2 py-0.5 rounded-full font-medium">{v.motif}</span>}
                      </div>
                      {v.diagnostic && <p className="text-xs text-gray-600"><span className="font-medium">Diagnostic : </span>{v.diagnostic}</p>}
                      {v.notes && <p className="text-xs text-gray-400 mt-1">{v.notes}</p>}
                      {v.veterinaire && <p className="text-xs text-gray-400 mt-0.5">Dr {v.veterinaire}</p>}
                    </div>
                  ))}
                </div>
              )}
            </Card>
            )}

            {/* Traitements */}
            <Card title={`💊 Traitements (${traitements.length})`} action={ajout('traitement')}>
              {traitements.length === 0 ? <EmptyState text="Aucun traitement enregistré" /> : (
                <div className="space-y-3">
                  {traitements.map(t => (
                    <div key={t.id} className="border border-gray-100 rounded-xl p-3">
                      <div className="flex items-center justify-between mb-1">
                        <p className="font-semibold text-sm text-[#1F2A2E]">{t.nom}</p>
                        <p className="text-xs text-gray-400">{fmtDateShort(t.date)}</p>
                      </div>
                      {t.posologie && <p className="text-xs text-gray-600">{t.posologie}</p>}
                      {t.date_fin && <p className="text-xs text-gray-400">Fin : {fmtDateShort(t.date_fin)}</p>}
                      {t.notes && <p className="text-xs text-gray-400 mt-1">{t.notes}</p>}
                    </div>
                  ))}
                </div>
              )}
            </Card>
            {isVet && (
              <>
            {/* Vermifuges */}
            <Card title={`🪱 Vermifuges (${vermifuges.length})`} action={ajout('vermifuge')}>
              {vermifuges.length === 0 ? <EmptyState text="Aucun vermifuge enregistré" /> : (
                <div className="space-y-2">
                  {vermifuges.map(v => {
                    const due = v.date_rappel && new Date(v.date_rappel) <= new Date();
                    return (
                      <div key={v.id} className="border border-gray-100 rounded-xl p-3">
                        <div className="flex items-center justify-between">
                          <p className="font-semibold text-sm text-[#1F2A2E]">{v.produit}</p>
                          <p className="text-xs text-gray-400">{fmtDateShort(v.date)}</p>
                        </div>
                        {v.dosage && <p className="text-xs text-gray-600">{v.dosage}</p>}
                        {v.date_rappel && <p className={`text-xs mt-0.5 ${due ? 'text-red-500 font-medium' : 'text-[#0C5C6C]'}`}>{due ? '⚠️ Rappel dû' : '📅 Rappel'} le {fmtDateShort(v.date_rappel)}</p>}
                        {v.notes && <p className="text-xs text-gray-400 mt-1">{v.notes}</p>}
                      </div>
                    );
                  })}
                </div>
              )}
            </Card>

            {/* Antiparasitaires */}
            <Card title={`🦟 Antiparasitaires (${antiparasitaires.length})`} action={ajout('antiparasitaire')}>
              {antiparasitaires.length === 0 ? <EmptyState text="Aucun antiparasitaire enregistré" /> : (
                <div className="space-y-2">
                  {antiparasitaires.map(a => {
                    const due = a.date_rappel && new Date(a.date_rappel) <= new Date();
                    return (
                      <div key={a.id} className="border border-gray-100 rounded-xl p-3">
                        <div className="flex items-center justify-between">
                          <p className="font-semibold text-sm text-[#1F2A2E]">{a.produit}</p>
                          <p className="text-xs text-gray-400">{fmtDateShort(a.date)}</p>
                        </div>
                        {a.type && <p className="text-xs text-gray-600">{a.type}</p>}
                        {a.date_rappel && <p className={`text-xs mt-0.5 ${due ? 'text-red-500 font-medium' : 'text-[#0C5C6C]'}`}>{due ? '⚠️ Rappel dû' : '📅 Rappel'} le {fmtDateShort(a.date_rappel)}</p>}
                        {a.notes && <p className="text-xs text-gray-400 mt-1">{a.notes}</p>}
                      </div>
                    );
                  })}
                </div>
              )}
            </Card>

            {/* Chirurgies / Hospitalisations (hors carnet commun) */}
            {!carnetCommun && (
            <Card title={`🏥 Chirurgies / Hospitalisations (${chirurgies.length})`} action={ajout('chirurgie')}>
              {chirurgies.length === 0 ? <EmptyState text="Aucune chirurgie enregistrée" /> : (
                <div className="space-y-2">
                  {chirurgies.map(c => (
                    <div key={c.id} className="border border-gray-100 rounded-xl p-3">
                      <div className="flex items-center justify-between mb-1">
                        <p className="font-semibold text-sm text-[#1F2A2E]">{c.intitule}</p>
                        <p className="text-xs text-gray-400">{fmtDateShort(c.date)}</p>
                      </div>
                      {c.statut && <span className="text-[10px] bg-[#E3F2FD] text-[#0C5C6C] px-2 py-0.5 rounded-full">{c.statut === 'realise' ? 'Réalisée' : c.statut === 'annule' ? 'Annulée' : 'Prévue'}</span>}
                      {c.clinique && <p className="text-xs text-gray-500 mt-1">{c.clinique}</p>}
                      {c.protocole_preop && <p className="text-xs text-gray-400 mt-1"><span className="font-medium">Pré-op : </span>{c.protocole_preop}</p>}
                      {c.protocole_postop && <p className="text-xs text-gray-400 mt-1"><span className="font-medium">Post-op : </span>{c.protocole_postop}</p>}
                      {c.notes && <p className="text-xs text-gray-400 mt-1">{c.notes}</p>}
                    </div>
                  ))}
                </div>
              )}
            </Card>
            )}

            {/* Allergies */}
            <Card title={`⚠️ Allergies / pathologies (${allergies.length})`} action={ajout('allergie')}>
              {allergies.length === 0 ? <EmptyState text="Aucune allergie enregistrée" /> : (
                <div className="space-y-2">
                  {allergies.map(a => (
                    <div key={a.id} className="border border-gray-100 rounded-xl p-3">
                      <div className="flex items-center justify-between">
                        <p className="font-semibold text-sm text-[#1F2A2E]">{a.description}</p>
                        {a.date && <p className="text-xs text-gray-400">{fmtDateShort(a.date)}</p>}
                      </div>
                      {(a.type || a.severite) && <p className="text-xs text-gray-600">{[a.type, a.severite].filter(Boolean).join(' · ')}</p>}
                      {a.notes && <p className="text-xs text-gray-400 mt-1">{a.notes}</p>}
                    </div>
                  ))}
                </div>
              )}
            </Card>

            {/* Radios / Examens */}
            {isVet && (
              <Card title={`🩻 Radios / Examens (${radios.length})`} action={ajout('radio')}>
                {radios.length === 0 ? <EmptyState text="Aucun examen enregistré" /> : (
                  <div className="space-y-2">
                    {radios.map(r => (
                      <div key={r.id} className="border border-gray-100 rounded-xl p-3">
                        <div className="flex items-center justify-between">
                          <p className="font-semibold text-sm text-[#1F2A2E]">{r.titre || 'Radio / Examen'}</p>
                          <p className="text-xs text-gray-400">{fmtDateShort(r.date)}</p>
                        </div>
                        {r.notes && <p className="text-xs text-gray-400 mt-1">{r.notes}</p>}
                        {r.veterinaire && <p className="text-xs text-gray-400">Dr {r.veterinaire}</p>}
                        {r.image_url && (
                          <LienDocument href={r.image_url} target="_blank" rel="noopener noreferrer"
                            className="inline-block mt-1 text-xs font-semibold underline text-[#0C5C6C]">Voir la pièce jointe</LienDocument>
                        )}
                      </div>
                    ))}
                  </div>
                )}
              </Card>
            )}
              </>
            )}
            {/* Mesures */}
            {(animal.poids || animal.taille) && (
              <Card title="⚖️ Mesures">
                <div className="grid grid-cols-2 gap-4">
                  {animal.poids != null && (
                    <div className="bg-[#E3F2FD] rounded-xl p-4 text-center">
                      <p className="text-2xl font-bold text-[#0C5C6C]" style={{ fontFamily: 'Galey, sans-serif' }}>{animal.poids} kg</p>
                      <p className="text-xs text-gray-500 mt-1">Poids</p>
                    </div>
                  )}
                  {animal.taille != null && (
                    <div className="bg-[#E3F2FD] rounded-xl p-4 text-center">
                      <p className="text-2xl font-bold text-[#0C5C6C]" style={{ fontFamily: 'Galey, sans-serif' }}>{animal.taille} cm</p>
                      <p className="text-xs text-gray-500 mt-1">Taille</p>
                    </div>
                  )}
                </div>
                {(hasWriteAccess || carnetCommun) && (
                  <button onClick={() => setAddingType('mesure')}
                    className="mt-3 w-full text-sm font-semibold py-2 rounded-xl border border-[#0C5C6C] text-[#0C5C6C] hover:bg-[#E3F2FD] transition-colors"
                    style={{ fontFamily: 'Galey, sans-serif' }}>
                    + Mettre à jour les mesures
                  </button>
                )}
              </Card>
            )}
          </>
          );
        })()}

        {/* ── Repro ── */}
        {tab === 'Repro' && (
          <>
            {animal.sexe?.toLowerCase() === 'femelle' && (
              <>
                <Card title={`🌡️ Chaleurs (${chaleurs.length})`}>
                  {chaleurs.length === 0 ? <EmptyState text="Aucune chaleur enregistrée" /> : (
                    <div className="space-y-2">
                      {chaleurs.map(c => (
                        <div key={c.id} className="border border-gray-100 rounded-xl p-3">
                          <p className="text-sm font-medium text-[#1F2A2E]">
                            {fmtDateShort(c.date)}{c.date_fin ? ` → ${fmtDateShort(c.date_fin)}` : ''}
                          </p>
                          {c.duree != null && <p className="text-xs text-gray-500">{c.duree} jour{c.duree > 1 ? 's' : ''}</p>}
                          {c.notes && <p className="text-xs text-gray-400 mt-1">{c.notes}</p>}
                        </div>
                      ))}
                    </div>
                  )}
                </Card>

                <Card title={`🤰 Gestations (${gestations.length})`}>
                  {gestations.length === 0 ? <EmptyState text="Aucune gestation enregistrée" /> : (
                    <div className="space-y-2">
                      {gestations.map(g => (
                        <div key={g.id} className="border border-gray-100 rounded-xl p-3">
                          {g.date && <p className="text-xs text-gray-500">Saillie : {fmtDateShort(g.date)}</p>}
                          {g.date_prevue && <p className="text-sm font-medium text-[#1F2A2E]">Naissance prévue : {fmtDateShort(g.date_prevue)}</p>}
                          {g.date_naissance && <p className="text-sm font-medium text-green-600">Naissance : {fmtDateShort(g.date_naissance)}</p>}
                          {g.gestation_confirmee && <span className="text-[10px] bg-green-50 text-green-600 font-bold px-1.5 py-0.5 rounded-full">Confirmée</span>}
                          {g.nb_attendu != null && <p className="text-xs text-gray-500">{g.nb_attendu} petit(s) attendu(s){g.nb_nes != null ? ` · ${g.nb_nes} né(s)` : ''}</p>}
                          {g.notes && <p className="text-xs text-gray-400 mt-1">{g.notes}</p>}
                        </div>
                      ))}
                    </div>
                  )}
                </Card>
              </>
            )}

            <Card title={`❤️ Saillies (${saillies.length})`}>
              {saillies.length === 0 ? <EmptyState text="Aucune saillie enregistrée" /> : (
                <div className="space-y-2">
                  {saillies.map(s => (
                    <div key={s.id} className="border border-gray-100 rounded-xl p-3">
                      <p className="text-sm font-medium text-[#1F2A2E]">{fmtDateShort(s.date)}</p>
                      {s.nom_partenaire && <p className="text-xs text-gray-500">Partenaire : {s.nom_partenaire}</p>}
                      {s.methode && <p className="text-xs text-gray-400">Méthode : {s.methode}</p>}
                      {s.notes && <p className="text-xs text-gray-400 mt-1">{s.notes}</p>}
                    </div>
                  ))}
                </div>
              )}
            </Card>

            {animal.sexe?.toLowerCase() !== 'femelle' && saillies.length === 0 && chaleurs.length === 0 && (
              <EmptyState text="Aucune donnée de reproduction enregistrée" />
            )}
          </>
        )}

        {/* ── Alimentation (pension) ── */}
        {tab === 'Alimentation' && (
          <Card title="🍽️ Alimentation">
            <div className="bg-blue-50 border border-blue-200 rounded-xl p-3 flex gap-2 items-center text-blue-700 text-xs font-medium mb-4">
              <span>📖</span><span>Données renseignées par le propriétaire — lecture seule</span>
            </div>
            <PlanAlimentationDepuisLigne row={alimentation as unknown as Record<string, unknown> | null} espece={animal?.espece ?? ''}
              nomAnimal={animal?.nom ?? ''} vuePro={false} large vide="Plan alimentaire non renseigné par le propriétaire." />
          </Card>
        )}

        {/* ── Pet-sitter : Synthèse · Prestations · Consignes · Historique ── */}
        {catPro === 'garde' && ['Synthèse', 'Prestations', 'Consignes', 'Historique'].includes(tab) && (() => {
          const now = new Date();
          const debut = (r: GardeRdvFiche) => new Date(r.date_heure);
          const fin = (r: GardeRdvFiche) => new Date(debut(r).getTime() + (r.duree_minutes ?? 30) * 60000);
          const hm = (d: Date) => d.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });
          const jour = (d: Date) => d.toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' });
          const journee = (r: GardeRdvFiche) => /garde/i.test(r.motif ?? '') && /journ/i.test(r.motif ?? '');
          const prestation = (r: GardeRdvFiche) => {
            const k = gardePrestationKey(r.motif);
            return k === 'autre' ? (r.motif?.trim() || 'Prestation') : gardeMotifLabel(k, animal.espece);
          };
          const horaires = (r: GardeRdvFiche) => {
            if (journee(r)) return `${jour(debut(r))} · journée`;
            const rd = r.arrivee_validee_le ? new Date(r.arrivee_validee_le) : null;
            const rf = r.depart_valide_le ? new Date(r.depart_valide_le) : r.termine_at ? new Date(r.termine_at) : null;
            return `${jour(debut(r))} · prévu ${hm(debut(r))}–${hm(fin(r))}${rd || rf ? ` · réel ${rd ? hm(rd) : '?'}–${rf ? hm(rf) : '…'}` : ''}`;
          };
          const aVenir = gardeRdvs.filter(r => r.statut === 'confirme' && fin(r) > now).sort((a, b) => debut(a).getTime() - debut(b).getTime());
          const passees = gardeRdvs.filter(r => !aVenir.includes(r));
          const prochaine = aVenir[0] ?? null;
          const consignes = (prochaine?.notes_client ?? gardeRdvs.find(r => r.notes_client?.trim())?.notes_client ?? '').trim();
          const acces = accesLogementLabel((prochaine ?? gardeRdvs[0])?.acces_logement);
          const cle = gardeCles.find(c => c.statut === 'en_possession');
          const traitsEnCours = traitements.filter(t => !t.date_fin || new Date(t.date_fin) >= now);
          const a = alimentation as (typeof alimentation & { nb_repas?: number | null; ration_grammes?: number | null; ration2_grammes?: number | null }) | null;
          const nbRepas = a?.nb_repas || Number(a?.notes?.split('|')?.[3]) || 0;
          const discret = (t: string) => <p className="text-sm text-gray-400">{t}</p>;
          const ligne = (r: GardeRdvFiche) => {
            const avecCr = gardeCrs.some(c => c.rdv_id === r.id);
            return (
              <div key={r.id} className="flex items-start gap-3 py-2 border-t border-gray-50 first:border-0">
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-bold text-[#1F2A2E]">{prestation(r)}</p>
                  <p className="text-xs text-gray-600">{horaires(r)}</p>
                  {r.lieu && <p className="text-xs text-gray-500 truncate">{r.lieu}</p>}
                </div>
                <div className="text-right shrink-0">
                  <p className="text-xs font-bold" style={{ color: r.statut === 'termine' ? '#6B7280' : TEAL }}>{r.statut === 'termine' ? 'Terminée' : 'Confirmée'}</p>
                  {r.statut === 'termine' && !avecCr && !journee(r) && (
                    <button onClick={() => setCrRdv(r)} className="text-xs font-semibold" style={{ color: TEAL }}>Compte rendu</button>
                  )}
                  {avecCr && <p className="text-[11px]" style={{ color: '#2E7D5E' }}>CR envoyé</p>}
                </div>
              </div>
            );
          };
          if (tab === 'Synthèse') return (
            <>
              <div className="grid sm:grid-cols-2 gap-4">
                <Card title={prochaine && debut(prochaine) < now ? 'Prestation en cours' : 'Prochaine prestation'}>
                  {prochaine ? (
                    <div className="text-sm space-y-0.5">
                      <p className="font-bold">{prestation(prochaine)}</p>
                      <p>{horaires(prochaine)}</p>
                      {prochaine.lieu && <p className="text-gray-600">Lieu : {prochaine.lieu}</p>}
                    </div>
                  ) : discret('Aucune prestation à venir.')}
                </Card>
                <Card title="Consignes essentielles">
                  <div className="text-sm space-y-1">
                    {consignes && <p className="whitespace-pre-line">{consignes}</p>}
                    {acces && <p>Accès au logement : {acces}</p>}
                    {allergies.map(al => <p key={al.id} style={{ color: '#B3261E' }}>Allergie : {al.description}</p>)}
                    {!consignes && !acces && allergies.length === 0 && discret('Aucune consigne transmise.')}
                  </div>
                </Card>
                <Card title="Clés">
                  {cle ? <p className="text-sm">{cle.description ?? 'Clé'} — en votre possession</p> : discret('Aucune clé en votre possession pour cet animal.')}
                  <a href="/garde/cles" className="text-xs font-semibold" style={{ color: TEAL }}>Gestion des clés →</a>
                </Card>
                <Card title="Dernier compte rendu">
                  {gardeCrs[0] ? (
                    <div className="text-sm">
                      <p className="text-xs" style={{ color: gardeCrs[0].incident ? '#B3261E' : '#6B7280' }}>{new Date(gardeCrs[0].created_at).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })}</p>
                      <p>{gardeCrs[0].note ?? 'Photo partagée'}</p>
                    </div>
                  ) : discret('Aucun compte rendu envoyé.')}
                </Card>
              </div>
              <div className="flex flex-wrap gap-2">
                {(['Identité', 'Santé', 'Alimentation'] as const).map(t => (
                  <button key={t} onClick={() => setTab(t)} className="px-4 py-2 rounded-xl border text-sm font-semibold" style={{ borderColor: TEAL, color: TEAL }}>
                    {t === 'Santé' ? 'Carnet de santé (lecture)' : t === 'Alimentation' ? 'Alimentation complète' : t}
                  </button>
                ))}
              </div>
            </>
          );
          if (tab === 'Prestations') return (
            <>
              <Card title="À venir">{aVenir.length === 0 ? discret('Aucune.') : aVenir.slice(0, 20).map(ligne)}</Card>
              <Card title="Passées">{passees.length === 0 ? discret('Aucune.') : passees.slice(0, 30).map(ligne)}</Card>
            </>
          );
          if (tab === 'Consignes') return (
            <>
              <Card title="Alimentation">
                <PlanAlimentationDepuisLigne row={a as unknown as Record<string, unknown> | null} espece={animal?.espece ?? ''}
                  nomAnimal={animal?.nom ?? ''} vuePro={false} vide="Plan d'alimentation non renseigné par le propriétaire." />
              </Card>
              <Card title="Traitements et précautions">
                <div className="text-sm space-y-0.5">
                  {traitsEnCours.map(t => <p key={t.id}>{t.nom}{t.posologie ? ` — ${t.posologie}` : ''}</p>)}
                  {allergies.map(al => <p key={al.id} style={{ color: '#B3261E' }}>Allergie : {al.description}</p>)}
                  {traitsEnCours.length === 0 && allergies.length === 0 && discret('Aucun traitement en cours ni allergie connue.')}
                </div>
              </Card>
              <Card title="Instructions d'accès">
                <div className="text-sm space-y-0.5">
                  {[...new Set(gardeRdvs.map(r => accesLogementLabel(r.acces_logement)).filter(Boolean))].map(x => <p key={x}>{x}</p>)}
                  {gardeCles.map(c => <p key={c.id}>Clé : {c.description ?? 'Clé'} ({c.statut === 'en_possession' ? 'en votre possession' : 'rendue'})</p>)}
                  {gardeCles.length === 0 && !gardeRdvs.some(r => r.acces_logement) && discret("Aucune instruction d'accès.")}
                  <p className="text-xs text-gray-400">Aucun code d&apos;accès n&apos;est stocké dans la fiche.</p>
                </div>
              </Card>
              <Card title="Consignes des réservations">
                {gardeRdvs.filter(r => r.notes_client?.trim()).length === 0 ? discret('Aucune consigne saisie par le propriétaire.') : (
                  <div className="space-y-2">
                    {gardeRdvs.filter(r => r.notes_client?.trim()).slice(0, 5).map(r => (
                      <div key={r.id}><p className="text-xs text-gray-500">{debut(r).toLocaleDateString('fr-FR')}</p><p className="text-sm whitespace-pre-line">{r.notes_client}</p></div>
                    ))}
                  </div>
                )}
              </Card>
            </>
          );
          const faites = gardeRdvs.filter(r => r.statut === 'termine');
          return (
            <>
              <Card title="Comptes rendus et photos">
                {gardeCrs.length === 0 ? discret('Aucun compte rendu.') : (
                  <div className="space-y-3">
                    {gardeCrs.slice(0, 20).map(c => (
                      <div key={c.id} className="flex gap-3">
                        {/* eslint-disable-next-line @next/next/no-img-element */}
                        {c.photo_url && <img src={c.photo_url} alt="" className="w-14 h-14 rounded-lg object-cover" />}
                        <div>
                          <p className="text-xs" style={{ color: c.incident ? '#B3261E' : '#6B7280' }}>{new Date(c.created_at).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })}{c.incident ? ' · incident' : ''}</p>
                          {c.note && <p className="text-sm">{c.note}</p>}
                        </div>
                      </div>
                    ))}
                  </div>
                )}
              </Card>
              <Card title={`Prestations réalisées (${faites.length})`}>
                {faites.length === 0 ? discret('Aucune prestation terminée.') : faites.slice(0, 30).map(r => (
                  <p key={r.id} className="text-sm py-1">{prestation(r)} · {horaires(r)}</p>
                ))}
              </Card>
            </>
          );
        })()}
        {catPro === 'toilettage' && user && activeProfileId && ['Synthèse', 'Prestations', 'Consignes', 'Historique'].includes(tab) && (
          <ToilettageFicheTabs tab={tab} setTab={setTab} animalId={animalId} animalNom={animal.nom ?? 'Animal'}
            proUid={user.uid} profileId={activeProfileId} allergies={allergies} traitements={traitements} />
        )}
        {crRdv && user && (
          <CompteRenduExpressModal rdv={crRdv} animalNom={animal.nom ?? 'Animal'} proUid={user.uid}
            proNom={userData?.nameElevage ?? ''} onClose={() => setCrRdv(null)} onEnvoye={() => chargerGarde()} />
        )}

        {/* ── Éducation (plan de travail + rapports de séance) ── */}
        {isEducation && tab === 'Synthèse' && (() => {
          const bilans = rapports.filter(r => r.type === 'bilan');
          const motif = motifSuivi?.trim() || bilans.find(b => b.bilan_motif)?.bilan_motif || '';
          const finalises = rapports.filter(r => r.statut !== 'brouillon');
          const derniere = finalises[0];
          const brouillons = rapports.filter(r => r.statut === 'brouillon').length;
          const prioritaires = [...objectifs.filter(o => o.prioritaire && o.statut !== 'acquis'),
            ...objectifs.filter(o => !o.prioritaire && o.statut !== 'acquis')].slice(0, 3);
          const reco = bilans[0]?.bilan_recommandation ? richTextToPlain(bilans[0].bilan_recommandation).trim() : '';
          const travail = derniere?.exercices_conseilles?.trim() ?? '';
          const discret = (t: string) => <p className="text-sm text-gray-400">{t}</p>;
          return (
            <>
              {brouillons > 0 && (
                <button onClick={() => setTab('Séances')} className="w-full text-left rounded-xl px-4 py-3 text-sm font-semibold"
                  style={{ background: '#FFF4DC', color: '#8A5A00' }}>
                  {brouillons} compte{brouillons > 1 ? 's' : ''} rendu{brouillons > 1 ? 's' : ''} à finaliser
                </button>
              )}
              <div className="grid sm:grid-cols-2 gap-4">
                <Card title="Motif de l'accompagnement">
                  {motifEdit !== null ? (
                    <div className="space-y-2">
                      <textarea value={motifEdit} onChange={e => setMotifEdit(e.target.value)} rows={3} autoFocus
                        placeholder="Ex : réactivité envers les congénères, tirage en laisse…"
                        className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
                      <div className="flex gap-2">
                        <button onClick={() => setMotifEdit(null)} className="flex-1 border border-gray-200 rounded-xl py-2 text-sm text-gray-500">Annuler</button>
                        <button onClick={async () => {
                          if (!user || !activeProfileId) return;
                          const texte = motifEdit.trim();
                          const { error } = await supabase.from('education_suivis').upsert({
                            pro_uid: user.uid, pro_profile_id: activeProfileId, animal_id: animalId,
                            motif: texte || null, updated_at: new Date().toISOString(),
                          }, { onConflict: 'pro_profile_id,animal_id' });
                          if (error) { alert('Motif non enregistré (migration_education_suivi_motif.sql à passer).'); return; }
                          setMotifSuivi(texte); setMotifEdit(null);
                        }} className="flex-1 text-white rounded-xl py-2 text-sm font-semibold" style={{ background: '#EF6C00' }}>Enregistrer</button>
                      </div>
                    </div>
                  ) : (
                    <button type="button" onClick={() => setMotifEdit(motif)} className="w-full text-left">
                      {motif ? <p className="text-sm">{motif}</p> : discret('Non renseigné.')}
                      <span className="text-xs font-semibold" style={{ color: TEAL }}>{motif ? 'Modifier' : 'Renseigner'}</span>
                    </button>
                  )}
                </Card>
                <Card title="Programme actif">
                  {forfaitActif
                    ? <p className="text-sm">{forfaitActif.nom_snapshot} — séance {forfaitActif.nb_seances_utilisees}/{forfaitActif.nb_seances_total}</p>
                    : discret('Aucun forfait en cours.')}
                </Card>
                <Card title="Objectifs prioritaires">
                  {prioritaires.length === 0 ? discret('Aucun objectif en cours.') : (
                    <div className="space-y-1.5">
                      {prioritaires.map(o => (
                        <p key={o.id} className="text-sm flex items-center gap-2">
                          <span className="w-2 h-2 rounded-full shrink-0" style={{ background: educStatutColor(o.statut) }} />
                          <span className="flex-1">{o.libelle}</span>
                          <span className="text-xs" style={{ color: educStatutColor(o.statut) }}>{EDUC_STATUT_LABEL[o.statut]}</span>
                        </p>
                      ))}
                    </div>
                  )}
                </Card>
                <Card title="Dernière séance">
                  {derniere ? (
                    <>
                      <p className="text-xs font-semibold text-gray-600">{fmtDateShort(derniere.date_seance)} · {EDUC_TYPES_SEANCE[derniere.type_seance ?? ''] ?? (derniere.type === 'bilan' ? 'Bilan' : 'Séance')}</p>
                      <p className="text-sm mt-1 line-clamp-3">{richTextToPlain(derniere.contenu)}</p>
                    </>
                  ) : discret('Aucune séance enregistrée.')}
                </Card>
                <Card title="Prochain rendez-vous">
                  {prochainRdv
                    ? <p className="text-sm">{new Date(prochainRdv.date_heure).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })}{prochainRdv.motif ? ` · ${prochainRdv.motif}` : ''}{prochainRdv.lieu ? ` · ${prochainRdv.lieu}` : ''}</p>
                    : discret('Aucune séance planifiée.')}
                </Card>
                <Card title="Recommandations en cours">
                  {!reco && !travail ? discret('Aucune recommandation partagée.') : (
                    <div className="space-y-1 text-sm">
                      {reco && <p>{reco}</p>}
                      {travail && <p>Travail à la maison : {travail}</p>}
                    </div>
                  )}
                </Card>
              </div>
              <div className="flex flex-wrap gap-2">
                <button onClick={() => setTab('Identité')} className="px-4 py-2 rounded-xl border text-sm font-semibold" style={{ borderColor: TEAL, color: TEAL }}>Identité</button>
                <button onClick={() => setTab('Santé')} className="px-4 py-2 rounded-xl border text-sm font-semibold" style={{ borderColor: TEAL, color: TEAL }}>Carnet de santé (lecture)</button>
              </div>
            </>
          );
        })()}

        {isEducation && tab === 'Documents' && (
          <>
            <Card title="Bilans comportementaux">
              {rapports.filter(r => r.type === 'bilan' && r.statut !== 'brouillon').length === 0 ? <EmptyState text="Aucun bilan finalisé" /> : (
                <div className="divide-y divide-gray-50">
                  {rapports.filter(r => r.type === 'bilan' && r.statut !== 'brouillon').map(r => (
                    <button key={r.id} onClick={() => setTab('Séances')} className="w-full text-left py-2">
                      <p className="text-sm font-semibold">Bilan — {fmtDateShort(r.date_seance)}</p>
                      <p className="text-xs text-gray-500 truncate">{richTextToPlain(r.contenu)}</p>
                    </button>
                  ))}
                </div>
              )}
            </Card>
            <Card title="Comptes rendus de séance">
              {rapports.filter(r => r.type !== 'bilan' && r.statut !== 'brouillon').length === 0 ? <EmptyState text="Aucun compte rendu finalisé" /> : (
                <div className="divide-y divide-gray-50">
                  {rapports.filter(r => r.type !== 'bilan' && r.statut !== 'brouillon').slice(0, 10).map(r => (
                    <button key={r.id} onClick={() => setTab('Séances')} className="w-full text-left py-2">
                      <p className="text-sm font-semibold">{EDUC_TYPES_SEANCE[r.type_seance ?? ''] ?? 'Séance'} — {fmtDateShort(r.date_seance)}</p>
                      <p className="text-xs text-gray-500 truncate">{richTextToPlain(r.contenu)}</p>
                    </button>
                  ))}
                </div>
              )}
            </Card>
            {hasReportAccess && (
              <Card title="Supports et documents partagés">
                <div className="grid sm:grid-cols-3 gap-2">
                  <button onClick={envoyerExercicesPdf} disabled={genExosPdf || attribues.length === 0}
                    className="border border-[#EF6C00]/40 text-[#EF6C00] rounded-xl py-2.5 font-semibold text-xs disabled:opacity-40">
                    {genExosPdf ? '…' : 'Exercices en PDF'}
                  </button>
                  <button onClick={genererSuiviLien} disabled={genSuiviLien}
                    className="border border-[#0C5C6C]/40 text-[#0C5C6C] rounded-xl py-2.5 font-semibold text-xs disabled:opacity-40">
                    {genSuiviLien ? '…' : 'Lien de suivi pour la famille'}
                  </button>
                  <button onClick={genererAttestation} disabled={genAttest || (rapports.length === 0 && objectifs.length === 0)}
                    className="border border-[#6E9E57] text-[#4A7A32] rounded-xl py-2.5 font-semibold text-xs disabled:opacity-40">
                    {genAttest ? 'Génération…' : 'Attestation de fin'}
                  </button>
                </div>
              </Card>
            )}
          </>
        )}

        {isEducation && tab === 'Programme' && (
          <>
          <Card title="🎯 Plan de travail">
            {hasReportAccess && (
              <button onClick={() => setObjForm({ libelle: '', categorie: '', statut: 'a_travailler', note: '' })}
                className="w-full text-white rounded-2xl py-2.5 font-semibold text-sm flex items-center justify-center gap-2 mb-4"
                style={{ background: '#EF6C00', fontFamily: 'Galey, sans-serif' }}>
                <span className="text-lg leading-none">+</span> Ajouter un objectif
              </button>
            )}
            {objForm && (
              <div className="border border-[#EF6C00]/30 rounded-2xl p-4 mb-4 space-y-3 bg-[#EF6C00]/5">
                <input value={objForm.libelle} onChange={e => setObjForm({ ...objForm, libelle: e.target.value })}
                  placeholder="Ex : Revient au rappel en extérieur"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />
                <select value={objForm.categorie} onChange={e => setObjForm({ ...objForm, categorie: e.target.value })}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white">
                  <option value="">Catégorie (optionnel)…</option>
                  {Object.entries(EDUC_CATEGORIES).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
                <div className="flex flex-wrap gap-1.5">
                  {EDUC_STATUTS.map(s => (
                    <button key={s} type="button" onClick={() => setObjForm({ ...objForm, statut: s })}
                      className="text-xs px-2.5 py-1.5 rounded-lg border"
                      style={objForm.statut === s ? { background: educStatutColor(s), borderColor: educStatutColor(s), color: 'white', fontWeight: 600 } : { borderColor: '#E5E7EB', color: '#6B7280' }}>
                      {EDUC_STATUT_LABEL[s]}
                    </button>
                  ))}
                </div>
                <label className="flex items-center gap-2 text-sm text-gray-700">
                  <input type="checkbox" checked={!!objForm.prioritaire} onChange={e => setObjForm({ ...objForm, prioritaire: e.target.checked })} />
                  Objectif prioritaire
                </label>
                <input value={objForm.difficultes ?? ''} onChange={e => setObjForm({ ...objForm, difficultes: e.target.value })}
                  placeholder="Difficultés rencontrées (facultatif)"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />
                <RichTextEditor value={objForm.note} onChange={html => setObjForm(f => f ? { ...f, note: html } : f)}
                  minHeight={90} placeholder="Note (facultatif)" />
                <div className="flex gap-2">
                  <button onClick={() => setObjForm(null)}
                    className="flex-1 border border-gray-200 rounded-xl py-2 text-sm text-gray-500">Annuler</button>
                  <button onClick={saveObjectif} disabled={savingObj || !objForm.libelle.trim()}
                    className="flex-1 text-white rounded-xl py-2 text-sm font-semibold disabled:opacity-50"
                    style={{ background: '#EF6C00' }}>Enregistrer</button>
                </div>
              </div>
            )}
            {objectifs.length === 0 ? (
              <EmptyState text="Aucun objectif défini" />
            ) : (
              <div className="space-y-2">
                {objectifs.map(o => (
                  <div key={o.id} className="border border-gray-100 rounded-xl p-3">
                    <div className="flex items-start gap-2">
                      <span className="w-2.5 h-2.5 rounded-full mt-1 shrink-0" style={{ background: educStatutColor(o.statut) }} />
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-semibold text-[#1F2A2E]">{o.libelle}
                          {o.prioritaire && <span className="ml-2 text-[10px] font-bold px-1.5 py-0.5 rounded" style={{ background: '#E6F2F3', color: TEAL }}>Prioritaire</span>}</p>
                        <p className="text-xs" style={{ color: educStatutColor(o.statut) }}>{EDUC_STATUT_LABEL[o.statut]}
                          {o.categorie && EDUC_CATEGORIES[o.categorie] ? ` · ${EDUC_CATEGORIES[o.categorie]}` : ''}</p>
                        {o.note && <div className="text-xs text-gray-500 mt-0.5"><RichText value={o.note} /></div>}
                        {o.difficultes && <p className="text-xs text-gray-600 mt-0.5">Difficultés : {o.difficultes}</p>}
                      </div>
                      {hasReportAccess && (
                        <div className="flex gap-1 shrink-0">
                          {EDUC_STATUTS.filter(s => s !== o.statut).map(s => (
                            <button key={s} onClick={() => setObjectifStatut(o, s)}
                              title={`→ ${EDUC_STATUT_LABEL[s]}`}
                              className="text-[10px] px-1.5 py-0.5 rounded border border-gray-200 text-gray-500">
                              {EDUC_STATUT_LABEL[s]}
                            </button>
                          ))}
                          <button onClick={() => setObjForm({ id: o.id, libelle: o.libelle, categorie: o.categorie ?? '', statut: o.statut, note: o.note ?? '', prioritaire: !!o.prioritaire, difficultes: o.difficultes ?? '' })}
                            className="text-gray-300 hover:text-gray-500 text-xs">✏️</button>
                          <button onClick={() => deleteObjectif(o.id)}
                            className="text-gray-300 hover:text-red-400 text-xs">🗑</button>
                        </div>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </Card>
          <Card title="🏋️ Exercices attribués">
            {hasReportAccess && (
              <button onClick={openAttrPicker}
                className="w-full text-white rounded-2xl py-2.5 font-semibold text-sm flex items-center justify-center gap-2 mb-4"
                style={{ background: '#EF6C00', fontFamily: 'Galey, sans-serif' }}>
                <span className="text-lg leading-none">+</span> Attribuer des exercices
              </button>
            )}
            {attrPicker && (
              <div className="border border-[#EF6C00]/30 rounded-2xl p-4 mb-4 bg-[#EF6C00]/5 space-y-2">
                <p className="text-xs font-semibold text-gray-500">Choisir dans la bibliothèque</p>
                {biblio.length === 0 ? (
                  <p className="text-xs text-gray-400">Bibliothèque vide — créez des exercices dans « Bibliothèque d&apos;exercices ».</p>
                ) : biblio.map(b => (
                  <label key={b.id} className="flex items-center gap-2 text-sm cursor-pointer">
                    <input type="checkbox" checked={attrPicker.ids.has(b.id)}
                      onChange={e => setAttrPicker(p => {
                        if (!p) return p;
                        const ids = new Set(p.ids);
                        if (e.target.checked) ids.add(b.id); else ids.delete(b.id);
                        return { ...p, ids };
                      })} />
                    {b.titre}
                  </label>
                ))}
                <input value={attrPicker.cadence} onChange={e => setAttrPicker(p => p ? { ...p, cadence: e.target.value } : p)}
                  placeholder="Cadence (facultatif) — ex : 2 fois par jour"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm mt-1" />
                <p className="text-xs font-semibold text-gray-500 pt-1">Durée</p>
                <div className="flex flex-wrap gap-1.5">
                  {DUREES_EXERCICE.map(d => (
                    <button key={d.label} type="button" onClick={() => setAttrPicker(p => p ? { ...p, duree: d.jours, echeance: echeanceDans(d.jours) ?? '' } : p)}
                      className="px-2.5 py-1 rounded-lg text-xs font-semibold border"
                      style={attrPicker.duree === d.jours ? { borderColor: '#EF6C00', color: '#EF6C00', background: '#EF6C0014' } : { borderColor: '#E5E7EB', color: '#6B7280' }}>
                      {d.label}
                    </button>
                  ))}
                  <input type="date" value={attrPicker.duree === -1 ? attrPicker.echeance : ''} aria-label="Jusqu'à une date"
                    onChange={e => setAttrPicker(p => p ? { ...p, duree: e.target.value ? -1 : DUREE_DEFAUT_JOURS, echeance: e.target.value || (echeanceDans(DUREE_DEFAUT_JOURS) ?? '') } : p)}
                    className="border border-gray-200 rounded-lg px-2 py-0.5 text-xs" />
                </div>
                <p className="text-[11px] text-gray-500">
                  {attrPicker.echeance ? `Rappels jusqu'au ${new Date(`${attrPicker.echeance}T12:00:00`).toLocaleDateString('fr-FR')} ou jusqu'à validation.` : "Rappels jusqu'à ce que la famille valide l'exercice."}
                </p>
                {(() => {
                  const choisis = biblio.filter(b => attrPicker.ids.has(b.id));
                  const sansEtapes = choisis.filter(b => !(b.etapes ?? []).length).length;
                  const avecEtapes = choisis.length - sansEtapes;
                  return (
                    <>
                      {sansEtapes > 0 && (
                        <>
                          <p className="text-xs font-semibold text-gray-500 pt-1">{avecEtapes ? 'Réussites à obtenir (exercices sans étapes)' : 'Réussites à obtenir'}</p>
                          <div className="flex flex-wrap gap-1.5">
                            {[1, 2, 3, 5, 7].map(n => (
                              <button key={n} type="button" onClick={() => setAttrPicker(p => p ? { ...p, nbValidations: n } : p)}
                                className="px-2.5 py-1 rounded-lg text-xs font-semibold border"
                                style={attrPicker.nbValidations === n ? { borderColor: '#EF6C00', color: '#EF6C00', background: '#EF6C0014' } : { borderColor: '#E5E7EB', color: '#6B7280' }}>
                                {n === 1 ? '1 (une fois)' : `${n} jours`}
                              </button>
                            ))}
                          </div>
                          <p className="text-[11px] text-gray-500">La famille valide une réussite par jour ; l&apos;exercice est terminé au total atteint.</p>
                        </>
                      )}
                      {avecEtapes > 0 && <p className="text-[11px] text-gray-500">{avecEtapes} exercice{avecEtapes > 1 ? 's ont' : ' a'} des étapes : la famille les valide une à une.</p>}
                    </>
                  );
                })()}
                <label className="flex items-center gap-2 text-sm text-gray-600">
                  <input type="checkbox" checked={attrPicker.rappels}
                    onChange={e => setAttrPicker(p => p ? { ...p, rappels: e.target.checked } : p)} />
                  Rappel quotidien à la famille pendant la durée, tant que non terminé
                </label>
                <div className="flex gap-2 pt-1">
                  <button onClick={() => setAttrPicker(null)} className="flex-1 border border-gray-200 rounded-xl py-2 text-sm text-gray-500">Annuler</button>
                  <button onClick={attribuerExercices} disabled={savingAttr || attrPicker.ids.size === 0}
                    className="flex-1 text-white rounded-xl py-2 text-sm font-semibold disabled:opacity-50" style={{ background: '#EF6C00' }}>
                    Envoyer à la famille
                  </button>
                </div>
              </div>
            )}
            {attribues.length === 0 ? (
              <EmptyState text="Aucun exercice attribué" />
            ) : (
              <div className="space-y-2">
                {attribues.map(a => (
                  <div key={a.id} className="border border-gray-100 rounded-xl p-3">
                    <div className="flex items-center justify-between gap-2">
                      <div className="min-w-0">
                        <p className={`text-sm font-semibold ${a.statut === 'fait' ? 'line-through text-gray-400' : 'text-[#1F2A2E]'}`}>{a.titre_snapshot}</p>
                        <p className="text-xs text-gray-500">
                          {(() => {
                            const pr = progression(a);
                            return [
                              pr.termine ? '✓ Terminé par la famille' : pr.total > 1
                                ? (pr.etapes.length ? `Étape ${pr.faites}/${pr.total}` : `${pr.faites}/${pr.total} réussites`)
                                : 'En attente',
                              a.cadence ?? '',
                              libelleDuree(a) ?? '',
                            ].filter(Boolean).join(' · ');
                          })()}
                        </p>
                      </div>
                      {hasReportAccess && (
                        <div className="flex items-center gap-1 shrink-0">
                          <button title="Rappel quotidien"
                            onClick={async () => {
                              const next = !a.rappels_actifs;
                              setAttribues(prev => prev.map(x => x.id === a.id ? { ...x, rappels_actifs: next } : x));
                              await supabase.from('exercices_attribues').update({ rappels_actifs: next }).eq('id', a.id);
                            }}
                            className={`text-sm ${a.rappels_actifs ? 'text-[#EF6C00]' : 'text-gray-300'}`}>
                            {a.rappels_actifs ? '🔔' : '🔕'}
                          </button>
                          <button onClick={() => retirerAttribue(a.id)} className="text-gray-300 hover:text-red-400 text-sm">🗑</button>
                        </div>
                      )}
                    </div>
                    {(retours[a.id] ?? []).map(rt => (
                      <div key={rt.id} className={`mt-2 rounded-lg p-2 ${rt.from_pro ? 'bg-[#EF6C00]/10' : 'bg-gray-100'}`}>
                        <p className="text-[10px] font-bold text-gray-500">
                          {rt.from_pro ? '🎓 Vous' : '👪 Famille'}
                          {rt.ressenti && EDUC_RESSENTI[rt.ressenti] ? ` · ${EDUC_RESSENTI[rt.ressenti]}` : ''}
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
                    {hasReportAccess && (replyFor === a.id ? (
                      <div className="mt-2 flex gap-2">
                        <input value={replyNote} onChange={e => setReplyNote(e.target.value)} autoFocus
                          placeholder="Votre réponse…" className="flex-1 border border-gray-200 rounded-lg px-2 py-1 text-xs" />
                        <button onClick={() => envoyerReponse(a.id)} className="text-xs text-white bg-[#EF6C00] rounded-lg px-2 py-1 font-semibold">Envoyer</button>
                        <button onClick={() => { setReplyFor(null); setReplyNote(''); }} className="text-xs text-gray-400">×</button>
                      </div>
                    ) : (
                      <button onClick={() => { setReplyFor(a.id); setReplyNote(''); }} className="text-xs text-[#EF6C00] font-semibold mt-2">↩ Répondre</button>
                    ))}
                  </div>
                ))}
              </div>
            )}
          </Card>
          <Card title="🎫 Forfait">
            {hasReportAccess && (
              <button onClick={() => setShowForfaitSousForm(v => !v)}
                className="w-full text-white rounded-2xl py-2.5 font-semibold text-sm flex items-center justify-center gap-2 mb-4"
                style={{ background: '#EF6C00', fontFamily: 'Galey, sans-serif' }}>
                <span className="text-lg leading-none">+</span> Enregistrer un forfait pris
              </button>
            )}
            {showForfaitSousForm && (
              <ForfaitSousForm proUid={user?.uid ?? ''} onSave={registerForfaitSous} onCancel={() => setShowForfaitSousForm(false)} />
            )}
            {forfaitsSous.length === 0 ? (
              <EmptyState text="Aucun forfait" />
            ) : (
              <div className="space-y-2">
                {forfaitsSous.map(f => {
                  const actif = f.statut === 'actif';
                  const pct = f.nb_seances_total === 0 ? 0 : Math.min(100, (f.nb_seances_utilisees / f.nb_seances_total) * 100);
                  return (
                    <div key={f.id} className="border border-gray-100 rounded-xl p-3">
                      <div className="flex items-center justify-between">
                        <p className="text-sm font-semibold text-[#1F2A2E]">{f.nom_snapshot}</p>
                        <p className="text-xs font-bold text-[#EF6C00]">{actif ? `${f.nb_seances_utilisees} / ${f.nb_seances_total}` : 'Terminé'}</p>
                      </div>
                      <div className="mt-1.5 h-1.5 rounded-full bg-gray-100 overflow-hidden">
                        <div className="h-full bg-[#EF6C00]" style={{ width: `${pct}%` }} />
                      </div>
                      {hasReportAccess && actif && (
                        <button onClick={async () => {
                          await supabase.from('forfaits_souscrits').update({ statut: 'termine', termine_le: new Date().toISOString() }).eq('id', f.id);
                          reloadForfaitsSous();
                        }} className="text-[11px] text-gray-400 mt-1">Clôturer</button>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </Card>
          </>
        )}

        {isEducation && tab === 'Séances' && (
          <>
          <Card title="Séances et comptes rendus">
            {hasReportAccess && (
              <button onClick={() => setShowAddRapport(v => !v)}
                className="w-full text-white rounded-2xl py-3 font-semibold text-sm transition-colors flex items-center justify-center gap-2 mb-4"
                style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
                <span className="text-lg leading-none">+</span>
                Nouvelle séance
              </button>
            )}
            {devisPrefillUrl && (
              <div className="bg-[#FFF3E9] border border-[#EF6C00]/40 rounded-2xl p-3 mb-4 flex items-center justify-between gap-3">
                <p className="text-xs text-gray-700">Bilan envoyé. Proposez le programme conseillé à la famille.</p>
                <div className="flex items-center gap-2 shrink-0">
                  <button onClick={() => router.push(devisPrefillUrl)}
                    className="text-white text-xs font-semibold px-3 py-1.5 rounded-lg" style={{ background: '#EF6C00' }}>
                    Créer le devis
                  </button>
                  <button onClick={() => setDevisPrefillUrl(null)} className="text-gray-400 text-xs">✕</button>
                </div>
              </div>
            )}
            {showAddRapport && (
              <div className="border border-gray-100 rounded-2xl p-4 mb-4 space-y-3">
                <div className="flex flex-wrap gap-1.5">
                  {Object.entries(EDUC_TYPES_SEANCE).map(([k, label]) => (
                    <button key={k} onClick={async () => {
                      setSeanceType(k);
                      const t = k === 'bilan' ? 'bilan' : 'seance';
                      setRapportType(t);
                      if (t === 'bilan' && forfaitsEdu.length === 0 && user?.uid) {
                        const { data } = await supabase.from('forfaits_education')
                          .select('id, nom, nb_seances, prix').eq('pro_uid', user.uid).eq('actif', true).order('created_at');
                        setForfaitsEdu((data ?? []) as typeof forfaitsEdu);
                      }
                    }}
                      className="text-xs px-2.5 py-1.5 rounded-lg border"
                      style={seanceType === k ? { background: '#EF6C00', borderColor: '#EF6C00', color: 'white', fontWeight: 600 } : { borderColor: '#E5E7EB', color: '#6B7280' }}>
                      {label}
                    </button>
                  ))}
                </div>
                <div className="flex gap-2">
                  <input value={seanceLieu} onChange={e => setSeanceLieu(e.target.value)} placeholder="Lieu (domicile, parc, terrain…)"
                    className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm" />
                  <input type="number" value={seanceDuree} onChange={e => setSeanceDuree(e.target.value)} placeholder="Durée (min)"
                    className="w-32 border border-gray-200 rounded-xl px-3 py-2 text-sm" />
                </div>
                {(
                  <div>
                    <p className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-1">Objectifs travaillés</p>
                    {objectifs.length === 0 && <p className="text-xs text-gray-400 mb-1">Aucun objectif pour l&apos;instant : ajoutez-en un ci-dessous.</p>}
                    <div className="flex flex-wrap gap-1.5">
                      {objectifs.map(o => {
                        const on = seanceObjs.includes(o.id);
                        return (
                          <button key={o.id} type="button" onClick={() => setSeanceObjs(v => on ? v.filter(x => x !== o.id) : [...v, o.id])}
                            className="text-xs px-2.5 py-1 rounded-full border"
                            style={on ? { background: '#FFF3E9', borderColor: '#EF6C00', color: '#B24E00', fontWeight: 600 } : { borderColor: '#E5E7EB', color: '#6B7280' }}>
                            {o.libelle}
                          </button>
                        );
                      })}
                    </div>
                    <div className="flex gap-2 mt-2">
                      <input value={nouvelObjSeance} onChange={e => setNouvelObjSeance(e.target.value)}
                        onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); ajouterObjectifSeance(); } }}
                        placeholder="Nouvel objectif (ex : marche en laisse détendue)"
                        className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm" />
                      <button type="button" onClick={ajouterObjectifSeance} disabled={ajoutObjSeance || !nouvelObjSeance.trim()}
                        className="text-xs font-semibold px-3 py-2 rounded-xl border disabled:opacity-40"
                        style={{ borderColor: '#EF6C00', color: '#B24E00' }}>Ajouter</button>
                    </div>
                  </div>
                )}
                {rapportType === 'bilan' && (
                  <input value={bilanMotif} onChange={e => setBilanMotif(e.target.value)}
                    placeholder="Motif de la demande (aboiements, laisse…)"
                    className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />
                )}
                <div>
                  <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide block mb-1">
                    {rapportType === 'bilan' ? 'Observations' : 'Déroulement de la séance'}
                  </label>
                  <RichTextEditor value={rapportContenu} onChange={setRapportContenu} minHeight={150}
                    placeholder={rapportType === 'bilan' ? 'Comportement observé, contexte de vie…' : 'Déroulé de la séance, observations, progrès…'} />
                </div>
                {rapportType === 'bilan' ? (
                  <>
                    <RichTextEditor value={bilanReco} onChange={setBilanReco} minHeight={110}
                      placeholder="Recommandation : programme conseillé, priorités…" />
                    <div className="flex gap-2">
                      <input type="number" value={bilanNb} onChange={e => setBilanNb(e.target.value)} placeholder="Nb séances"
                        className="w-28 border border-gray-200 rounded-xl px-3 py-2 text-sm" />
                      <select value={bilanForfait} onChange={e => setBilanForfait(e.target.value)}
                        className="flex-1 border border-gray-200 rounded-xl px-2 py-2 text-sm">
                        <option value="">Forfait conseillé…</option>
                        {forfaitsEdu.map(f => <option key={f.id} value={f.id}>{f.nom} · {f.nb_seances}× · {f.prix}€</option>)}
                      </select>
                    </div>
                  </>
                ) : (
                  <div>
                    <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide block mb-1">Recommandations / travail avant la prochaine séance</label>
                    <textarea value={rapportExercices} onChange={e => setRapportExercices(e.target.value)} rows={2}
                      placeholder="Exercices à faire à la maison d'ici la prochaine séance…"
                      className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
                    <button type="button" onClick={ouvrirExosCr}
                      className="mt-2 text-sm font-semibold px-3 py-2 rounded-xl border w-full text-left"
                      style={{ borderColor: '#EF6C00', color: '#B24E00' }}>
                      {crExos.length > 0 ? `${crExos.length} exercice${crExos.length > 1 ? 's' : ''} de la bibliothèque joint${crExos.length > 1 ? 's' : ''}` : 'Joindre des exercices de ma bibliothèque'}
                    </button>
                    {crExosOuvert && (
                      <div className="mt-2 border border-gray-200 rounded-xl p-2 max-h-64 overflow-y-auto space-y-1">
                        {biblio.length === 0 ? (
                          <p className="text-xs text-gray-400 p-1">Aucun exercice dans votre bibliothèque.</p>
                        ) : biblio.map(b => {
                          const on = crExos.includes(b.id);
                          return (
                            <label key={b.id} className="flex items-start gap-2 p-1.5 rounded-lg cursor-pointer hover:bg-gray-50">
                              <input type="checkbox" checked={on} className="mt-0.5"
                                onChange={() => setCrExos(v => on ? v.filter(x => x !== b.id) : [...v, b.id])} />
                              <span className="text-sm">
                                <span className="font-semibold text-[#1F2A2E]">{b.titre}</span>
                                {b.description && !richTextIsEmpty(b.description) && <span className="block text-xs text-gray-500 line-clamp-1">{richTextToPlain(b.description)}</span>}
                              </span>
                            </label>
                          );
                        })}
                      </div>
                    )}
                    {crExos.length > 0 && <p className="text-[11px] text-gray-500 mt-1">Ils seront attribués à l&apos;animal (onglet Programme) et visibles par le propriétaire.</p>}
                  </div>
                )}
                <label className="flex items-center gap-2 text-sm text-gray-700">
                  <input type="checkbox" checked={seanceDetaille} onChange={e => setSeanceDetaille(e.target.checked)} />
                  Compte rendu détaillé
                </label>
                {seanceDetaille && (
                  <div className="space-y-2">
                    {([['Comportements observés', seanceComport, setSeanceComport], ['Difficultés', seanceDiff, setSeanceDiff], ['Prochaine étape', seanceProchaine, setSeanceProchaine]] as const).map(([label, v, set]) => (
                      <textarea key={label} value={v} onChange={e => set(e.target.value)} rows={2} placeholder={label}
                        className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
                    ))}
                  </div>
                )}
                {rapportType === 'seance' && forfaitActif && (
                  <label className="flex items-center gap-2 text-xs text-gray-600">
                    <input type="checkbox" checked={imputerForfait} onChange={e => setImputerForfait(e.target.checked)} />
                    Imputer sur le forfait « {forfaitActif.nom_snapshot} » ({forfaitActif.nb_seances_utilisees + 1}/{forfaitActif.nb_seances_total})
                  </label>
                )}
                <div className="flex gap-2">
                  <button onClick={() => soumettreRapport(false)} disabled={savingRapport || richTextIsEmpty(rapportContenu)}
                    className="flex-1 border rounded-xl py-2.5 text-sm font-semibold disabled:opacity-50"
                    style={{ borderColor: '#EF6C00', color: '#EF6C00', fontFamily: 'Galey, sans-serif' }}>
                    Brouillon
                  </button>
                  <button onClick={() => soumettreRapport(true)} disabled={savingRapport || richTextIsEmpty(rapportContenu)}
                    className="flex-[2] text-white rounded-xl py-2.5 text-sm font-semibold disabled:opacity-50"
                    style={{ background: rapportType === 'bilan' ? '#EF6C00' : TEAL, fontFamily: 'Galey, sans-serif' }}>
                    {savingRapport ? '…' : seanceRdvId ? (rapportType === 'bilan' ? 'Enregistrer le bilan' : 'Enregistrer le compte rendu')
                      : rapportType === 'bilan' ? 'Finaliser et envoyer le bilan' : 'Finaliser et envoyer'}
                  </button>
                </div>
                {seanceRdvId && (
                  <p className="text-[11px] text-gray-500 text-center">Rien n&apos;est envoyé maintenant : tout part à la fin du RDV (dossier de la séance, « Terminer et envoyer »).</p>
                )}
              </div>
            )}
            {editingRapportId && (
              <div className="border border-[#0C5C6C]/30 rounded-2xl p-4 mb-4 space-y-3 bg-[#E8F4F6]/30">
                <p className="text-xs font-semibold text-[#0C5C6C] uppercase tracking-wide">Modifier le rapport</p>
                <div>
                  <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide block mb-1">Compte rendu</label>
                  <RichTextEditor value={rapportContenu} onChange={setRapportContenu} minHeight={140} />
                </div>
                <div>
                  <label className="text-xs font-semibold text-gray-500 uppercase tracking-wide block mb-1">Exercices conseillés</label>
                  <textarea value={rapportExercices} onChange={e => setRapportExercices(e.target.value)} rows={2}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-none" />
                </div>
                <div className="flex gap-2">
                  <button onClick={() => { setEditingRapportId(null); setRapportContenu(''); setRapportExercices(''); }}
                    className="flex-1 border border-gray-200 text-gray-600 rounded-xl py-2.5 text-sm font-semibold">
                    Annuler
                  </button>
                  <button onClick={() => saveEditRapport(false)} disabled={savingRapport || richTextIsEmpty(rapportContenu)}
                    className="flex-1 text-white rounded-xl py-2.5 text-sm font-semibold disabled:opacity-50"
                    style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
                    {savingRapport ? '…' : 'Enregistrer'}
                  </button>
                  {rapports.find(r => r.id === editingRapportId)?.statut === 'brouillon' && (
                    <button onClick={() => saveEditRapport(true)} disabled={savingRapport || richTextIsEmpty(rapportContenu)}
                      className="flex-1 text-white rounded-xl py-2.5 text-sm font-semibold disabled:opacity-50"
                      style={{ background: '#EF6C00', fontFamily: 'Galey, sans-serif' }}>
                      Finaliser et envoyer
                    </button>
                  )}
                </div>
              </div>
            )}
            {rapports.length === 0 ? (
              <EmptyState text="Aucun rapport de séance pour l'instant" />
            ) : (
              <div className="space-y-3">
                {rapports.map(r => (
                  <div key={r.id} className={`border rounded-xl p-3 ${r.type === 'bilan' ? 'border-[#EF6C00]' : 'border-gray-100'}`}>
                    <div className="flex items-center justify-between mb-1">
                      <p className="text-xs text-gray-400 flex items-center gap-1.5">
                        {r.type === 'bilan' && <span className="text-[9px] bg-[#EF6C00] text-white px-1 py-0.5 rounded font-bold">BILAN</span>}
                        {r.statut === 'brouillon' && <span className="text-[9px] px-1 py-0.5 rounded font-bold" style={{ background: '#FFF4DC', color: '#8A5A00' }}>BROUILLON</span>}
                        {fmtDateShort(r.date_seance)}
                      </p>
                      {hasReportAccess && (
                        <div className="flex gap-2">
                          <button onClick={() => startEditRapport(r)} className="text-gray-400 hover:text-[#0C5C6C] text-xs">✏️</button>
                          {deleteRapportConfirmId === r.id ? (
                            <span className="flex gap-1">
                              <button onClick={() => deleteRapport(r.id)} className="text-red-600 font-semibold text-xs">Confirmer</button>
                              <button onClick={() => setDeleteRapportConfirmId(null)} className="text-gray-400 text-xs">✕</button>
                            </span>
                          ) : (
                            <button onClick={() => setDeleteRapportConfirmId(r.id)} className="text-gray-400 hover:text-red-500 text-xs">🗑️</button>
                          )}
                        </div>
                      )}
                    </div>
                    {(r.type_seance || r.lieu || r.duree_minutes) && (
                      <p className="text-xs text-gray-600 mb-0.5">{[EDUC_TYPES_SEANCE[r.type_seance ?? ''], r.lieu, r.duree_minutes ? `${r.duree_minutes} min` : ''].filter(Boolean).join(' · ')}</p>
                    )}
                    {(r.objectifs_travailles?.length ?? 0) > 0 && (
                      <p className="text-xs font-semibold text-gray-700 mb-0.5">Objectifs travaillés : {(r.objectifs_travailles ?? []).map(id => objectifs.find(o => o.id === id)?.libelle).filter(Boolean).join(', ')}</p>
                    )}
                    {r.type === 'bilan' && r.bilan_motif && <p className="text-xs font-semibold text-gray-700 mb-0.5">Motif : {r.bilan_motif}</p>}
                    <div className="text-sm text-[#1F2A2E]"><RichText value={r.contenu} /></div>
                    {r.type === 'bilan' && r.bilan_recommandation && (
                      <div className="mt-1.5 bg-[#FFF3E9] rounded-lg px-2 py-1.5">
                        <p className="text-[11px] font-bold text-[#EF6C00]">Recommandation</p>
                        <div className="text-xs text-gray-800"><RichText value={r.bilan_recommandation} /></div>
                        {r.bilan_nb_seances_estime != null && <p className="text-[10px] text-gray-500">Estimation : {r.bilan_nb_seances_estime} séances</p>}
                      </div>
                    )}
                    {([['Comportements observés', r.comportements], ['Difficultés', r.difficultes], ['Prochaine étape', r.prochaine_etape]] as const).map(([l, v]) => v ? (
                      <p key={l} className="text-xs text-gray-700 mt-1">{l} : {v}</p>
                    ) : null)}
                    {r.exercices_conseilles && (
                      <div className="mt-2 bg-[#EEF5EA] rounded-lg px-2.5 py-1.5">
                        <p className="text-xs font-semibold text-[#4A7A32] mb-0.5">Recommandations / travail à la maison</p>
                        <p className="text-xs text-[#4A7A32]">{r.exercices_conseilles}</p>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </Card>
          </>
        )}

        {/* ── Consultations : suivi des consultations (CR + ordonnances) ; le
             carnet de santé reste dans l'onglet Santé ── */}
        {tab === 'Consultations' && isVet && catPro !== 'sante' && (
          <>
            {identiteSeule ? (
              <p className="text-xs text-gray-600 bg-[#F4F7F8] border border-gray-200 rounded-lg px-3 py-2">
                Fiche créée par un autre professionnel : vos comptes rendus et ordonnances restent privés{carnetCommun
                  ? ' ; le carnet commun (vaccins, traitements, poids…) est partagé entre les professionnels de santé.'
                  : ' ; le carnet de santé n’est pas partagé.'}
              </p>
            ) : !hasWriteAccess && !writeRequested && (
              <p className="text-xs text-[#8A5A00] bg-[#FFF8EA] border border-[#F3E2BD] rounded-lg px-3 py-2">
                Lecture seule — demandez l&apos;accès en écriture depuis l&apos;onglet Identité.
              </p>
            )}
            <ConsultationsVet
              crOuvert={crCible}
              crs={comptesRendus as CrVet[]} ordos={ordonnances as OrdoVet[]}
              peutCr={hasWriteAccess || identiteSeule} peutCarnet={hasWriteAccess || carnetCommun} peutValider={hasWriteAccess || identiteSeule}
              menuCarnet={[
                { label: 'Vaccin', onClick: () => setAddingType('vaccin') },
                { label: 'Traitement', onClick: () => setAddingType('traitement') },
                ...(carnetCommun ? [] : [
                  { label: 'Ordonnance (PDF)', onClick: () => setAddingType('ordonnance') },
                  { label: 'Radio / Examen', onClick: () => setAddingType('radio') },
                ]),
                { label: 'Nouvelle mesure', onClick: () => setAddingType('mesure') },
              ]}
              onNouveauCr={() => { viderCr(); setCrRdvId(null); restaurerCrEnCours(null); setAddingType('cr'); }}
              onHistorique={() => setHistoriqueOuvert(true)}
              onReprendre={reprendreBrouillon}
              onModifier={cr => modifierCr(cr as CompteRendu)}
              onFacturer={cr => facturerCr(cr as CompteRendu)}
              onSupprimer={async (cr) => {
                // Droits contrôlés en base : un CR validé n'est supprimable que par qui peut valider.
                const { data, error } = await supabase.from('comptes_rendus').delete().eq('id', cr.id).select('id');
                if (error || !data?.length) { alert(`Suppression impossible : ${error?.message ?? 'seul un vétérinaire qui peut valider supprime un compte rendu validé'}`); return; }
                setComptesRendus(prev => prev.filter(x => x.id !== cr.id));
              }}
              onValider={async (cr) => {
                const { error } = await supabase.from('comptes_rendus').update({
                  statut: 'valide', ...(activeProfileId ? { valide_par_profile_id: activeProfileId } : {}),
                }).eq('id', cr.id);
                if (error) { alert(error.message); return; }
                await notifierCompteRendu(cr.id);
                // Relit le CR : validateur / date posés par le serveur.
                const { data } = await supabase.from('comptes_rendus').select('*').eq('id', cr.id).maybeSingle();
                setComptesRendus(prev => prev.map(x => x.id === cr.id ? { ...x, ...(data ?? { statut: 'valide' }) } : x));
              }}
              onTransmettreCr={(cr, action) => transmettreCr(cr as CompteRendu, action)}
              onTransmettreOrdo={(o, action) => transmettreOrdo(o as Ordonnance, action)}
            />
            {historiqueOuvert && animal && (
              <HistoriquePatient animalId={String(animal.id)} animalNom={animal.nom ?? 'Patient'}
                profileId={activeProfileId} onClose={() => setHistoriqueOuvert(false)} />
            )}
          </>
        )}

        {tab === 'Anatomie' && animal && (
          <AnatomieSeances animalId={String(animal.id)} espece={animal.espece} profilType={catPro} />
        )}

        {tab === 'Ostéo / Kiné' && animal && (
          <MorphoAnimalTab animalId={String(animal.id)} espece={animal.espece} proProfileId={activeProfileId} />
        )}
        {tab === 'Séances' && catPro === 'sante' && animal && (
          <MorphoAnimalTab animalId={String(animal.id)} espece={animal.espece} proProfileId={activeProfileId} />
        )}
      </div>

      {/* ── Modales d'ajout ── */}
      {addingType && (
        <div className="fixed inset-0 bg-black/40 z-50 flex items-end sm:items-center justify-center p-4"
          onClick={() => { if (retourCr) revenirAuCr(retourCr); else setAddingType(null); }}>
          <div className="bg-white rounded-2xl w-full max-w-md p-6 space-y-4 max-h-[90vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between">
              <h3 className="font-bold text-base text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
                {addingType === 'cr' && (crEdition ? 'Modifier le compte rendu' : 'Rédiger un compte rendu')}
                {addingType === 'vaccin' && '💉 Nouveau vaccin'}
                {addingType === 'visite' && '🩺 Nouvelle visite'}
                {addingType === 'traitement' && '💊 Nouveau traitement'}
                {addingType === 'vermifuge' && '🪱 Nouveau vermifuge'}
                {addingType === 'antiparasitaire' && '🦟 Nouvel antiparasitaire'}
                {addingType === 'chirurgie' && '🏥 Chirurgie / Hospitalisation'}
                {addingType === 'allergie' && '⚠️ Nouvelle allergie / pathologie'}
                {addingType === 'ordonnance' && '📄 Nouvelle ordonnance'}
                {addingType === 'radio' && '🩻 Radio / Examen'}
                {addingType === 'mesure' && '⚖️ Nouvelle mesure'}
              </h3>
              <button onClick={() => { if (retourCr) revenirAuCr(retourCr); else setAddingType(null); }} className="text-gray-400 hover:text-gray-600 text-xl">×</button>
            </div>

            {/* Champ date commun (pas pour mesure) */}
            {addingType !== 'mesure' && (
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Date</label>
                <input type="date" value={formDate} onChange={e => setFormDate(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
            )}

            {/* Vaccin */}
            {addingType === 'vaccin' && (<>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Nom du vaccin *</label>
                <input value={formNom} onChange={e => setFormNom(e.target.value)} placeholder="Ex : Primovaccination, Rage, Leptospirose…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Date de rappel</label>
                <input type="date" value={formRappel} onChange={e => setFormRappel(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">N° de lot</label>
                <input value={formLot} onChange={e => setFormLot(e.target.value)} placeholder="Numéro de lot…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
            </>)}

            {/* Visite */}
            {addingType === 'visite' && (<>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Motif <span className="text-red-400">*</span></label>
                <select value={formMotif} onChange={e => setFormMotif(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white">
                  <option value="">— Sélectionner —</option>
                  {['Consultation', 'Rappel de vaccin', 'Urgence', 'Suivi post-opératoire', 'Contrôle', 'Autre'].map(m => (
                    <option key={m} value={m}>{m}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Diagnostic / Observations</label>
                <textarea value={formDiag} onChange={e => setFormDiag(e.target.value)} rows={3}
                  placeholder="Examen clinique, diagnostic…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Notes</label>
                <textarea value={formNotes} onChange={e => setFormNotes(e.target.value)} rows={2}
                  placeholder="Notes libres…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
            </>)}

            {/* Traitement */}
            {addingType === 'traitement' && (<>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Nom du produit *</label>
                <input value={formNom} onChange={e => setFormNom(e.target.value)} placeholder="Ex : Amoxicilline, Frontline…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Posologie</label>
                <input value={formPosologie} onChange={e => setFormPosologie(e.target.value)} placeholder="Ex : 1 comprimé matin et soir…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Date de fin</label>
                <input type="date" value={formDateFin} onChange={e => setFormDateFin(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Notes</label>
                <textarea value={formNotes} onChange={e => setFormNotes(e.target.value)} rows={2}
                  placeholder="Notes complémentaires…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
            </>)}

            {/* Vermifuge */}
            {addingType === 'vermifuge' && (<>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Produit *</label>
                <input value={formNom} onChange={e => setFormNom(e.target.value)} placeholder="Ex : Milbemax, Drontal…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Dosage</label>
                <input value={formDosage} onChange={e => setFormDosage(e.target.value)} placeholder="Ex : 1 comprimé…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Fréquence (prochain rappel)</label>
                <div className="flex gap-2">
                  <input type="number" min={1} value={freqN} aria-label="Fréquence"
                    onChange={e => { setFreqN(e.target.value); appliquerFrequence(e.target.value, freqU); }}
                    className="w-20 border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                  <select value={freqU} aria-label="Unité"
                    onChange={e => { const u = e.target.value as typeof freqU; setFreqU(u); appliquerFrequence(freqN, u); }}
                    className="flex-1 border border-gray-200 rounded-xl px-3 py-2.5 text-sm bg-white focus:outline-none focus:border-[#0C5C6C]">
                    <option value="jour">Jour(s)</option><option value="semaine">Semaine(s)</option><option value="mois">Mois</option><option value="an">An(s)</option>
                  </select>
                </div>
              </div>
              {/* Durée de prise (ex. 3 jours) et rappels à chaque prise. */}
              <VermifugeOptions animalId={animalId} value={optsVerm} onChange={setOptsVerm} groupe={false} />
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Date de rappel</label>
                <input type="date" value={formRappel} onChange={e => setFormRappel(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Notes</label>
                <textarea value={formNotes} onChange={e => setFormNotes(e.target.value)} rows={2}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
            </>)}

            {/* Antiparasitaire */}
            {addingType === 'antiparasitaire' && (<>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Produit *</label>
                <input value={formNom} onChange={e => setFormNom(e.target.value)} placeholder="Ex : Frontline, Advantix…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Type</label>
                <input value={formSubType} onChange={e => setFormSubType(e.target.value)} placeholder="Ex : Pipette, Collier, Spray…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Fréquence (prochain rappel)</label>
                <div className="flex gap-2">
                  <input type="number" min={1} value={freqN} aria-label="Fréquence"
                    onChange={e => { setFreqN(e.target.value); appliquerFrequence(e.target.value, freqU); }}
                    className="w-20 border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                  <select value={freqU} aria-label="Unité"
                    onChange={e => { const u = e.target.value as typeof freqU; setFreqU(u); appliquerFrequence(freqN, u); }}
                    className="flex-1 border border-gray-200 rounded-xl px-3 py-2.5 text-sm bg-white focus:outline-none focus:border-[#0C5C6C]">
                    <option value="jour">Jour(s)</option><option value="semaine">Semaine(s)</option><option value="mois">Mois</option><option value="an">An(s)</option>
                  </select>
                </div>
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Date de rappel</label>
                <input type="date" value={formRappel} onChange={e => setFormRappel(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Notes</label>
                <textarea value={formNotes} onChange={e => setFormNotes(e.target.value)} rows={2}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
            </>)}

            {/* Chirurgie / Hospitalisation */}
            {addingType === 'chirurgie' && (<>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Type</label>
                <select value={formSubType || 'chirurgie'} onChange={e => setFormSubType(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white">
                  <option value="chirurgie">Chirurgie</option>
                  <option value="hospitalisation">Hospitalisation</option>
                </select>
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Intervention *</label>
                <input value={formIntitule} onChange={e => setFormIntitule(e.target.value)} placeholder="Ex : Stérilisation, Détartrage sous AG…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Statut</label>
                <select value={formStatut} onChange={e => setFormStatut(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white">
                  <option value="prevu">Prévue</option>
                  <option value="realise">Réalisée</option>
                  <option value="annule">Annulée</option>
                </select>
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Clinique / vétérinaire</label>
                <input value={formClinique} onChange={e => setFormClinique(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Protocole pré-opératoire</label>
                <textarea value={formPreop} onChange={e => setFormPreop(e.target.value)} rows={2}
                  placeholder="Jeûne, prémédication, anesthésie…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Protocole post-opératoire</label>
                <textarea value={formPostop} onChange={e => setFormPostop(e.target.value)} rows={2}
                  placeholder="Analgésie, soins de plaie, repos, contrôle…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Notes</label>
                <textarea value={formNotes} onChange={e => setFormNotes(e.target.value)} rows={2}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
            </>)}

            {/* Allergie */}
            {addingType === 'allergie' && (<>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Type</label>
                <select value={formSubType} onChange={e => setFormSubType(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white">
                  <option value="">— Sélectionner —</option>
                  {['alimentaire', 'médicamenteuse', 'environnementale', 'maladie chronique', 'autre'].map(t => (
                    <option key={t} value={t}>{t}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Description *</label>
                <input value={formDescription} onChange={e => setFormDescription(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Sévérité</label>
                <select value={formSeverite} onChange={e => setFormSeverite(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white">
                  <option value="">— Sélectionner —</option>
                  {['légère', 'modérée', 'sévère'].map(s => (
                    <option key={s} value={s}>{s}</option>
                  ))}
                </select>
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Notes / antécédents</label>
                <textarea value={formNotes} onChange={e => setFormNotes(e.target.value)} rows={2}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
            </>)}

            {/* Ordonnance */}
            {addingType === 'ordonnance' && (<>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Posologie / Instructions</label>
                <textarea value={formNotes} onChange={e => setFormNotes(e.target.value)} rows={3}
                  placeholder="Détail des médicaments, posologie…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
              <p className="text-xs text-gray-400">L&apos;upload de PDF sera disponible prochainement.</p>
            </>)}

            {/* Radio */}
            {addingType === 'radio' && (<>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Titre de l&apos;examen</label>
                <input value={formTitre} onChange={e => setFormTitre(e.target.value)} placeholder="Ex : Radio thorax, Échographie abdominale…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Observations</label>
                <textarea value={formNotes} onChange={e => setFormNotes(e.target.value)} rows={3}
                  placeholder="Résultats, observations…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Pièce jointe (image ou PDF)</label>
                <input type="file" accept="image/*,application/pdf" onChange={e => setFormFichier(e.target.files?.[0] ?? null)}
                  className="w-full text-sm file:mr-3 file:px-3 file:py-1.5 file:rounded-lg file:border-0 file:bg-[#0C5C6C]/10 file:text-[#0C5C6C] file:font-semibold" />
                {formFichier && <p className="text-xs text-gray-500 mt-1">{formFichier.name}</p>}
              </div>
            </>)}

            {/* Compte rendu */}
            {addingType === 'cr' && (<>
              {/* Ma signature : apposée sur les comptes rendus et ordonnances. */}
              {catPro === 'veterinaire' && signature !== undefined && (
                <div className={`flex items-center gap-2 rounded-xl px-3 py-2 ${signature ? 'bg-[#0C5C6C]/5' : 'bg-[#FFF4E0]'}`}>
                  <span className={`flex-1 text-[12.5px] ${signature ? 'text-gray-600' : 'text-[#8A5A00]'}`}>
                    {signature ? 'Votre signature est apposée sur vos comptes rendus et ordonnances.'
                      : 'Ajoutez votre signature : elle sera apposée sur vos comptes rendus et ordonnances.'}
                  </span>
                  <button type="button" onClick={() => setSigner(true)} className="text-sm font-bold text-[#0C5C6C] px-2">
                    {signature ? 'Modifier' : 'Signer'}
                  </button>
                </div>
              )}
              {/* Visite à plusieurs animaux : passer d'un animal à l'autre. */}
              {visite && (
                <div className="rounded-xl border border-[#0C5C6C]/25 bg-[#0C5C6C]/5 px-3 py-2.5">
                  <p className="text-[13px] font-bold text-[#0C5C6C]">Visite : {visite.animaux.length} animaux</p>
                  <div className="flex flex-wrap gap-2 mt-2">
                    {visite.animaux.map(a => {
                      const courant = a.id === String(animalId);
                      const etat = visite.etats[a.id];
                      // Fait (vert plein), brouillon (orange), à faire (contour) ; animal en cours souligné.
                      return (
                        <button key={a.id} type="button" disabled={courant}
                          onClick={() => window.location.assign(`/mes-patients/${encodeURIComponent(a.id)}?crRdv=${encodeURIComponent(visite.rdvId)}`)}
                          className={`px-3 py-1.5 rounded-full text-[12.5px] font-semibold border-2 ${courant ? 'underline underline-offset-2' : ''}`}
                          style={etat === 'fait' ? { background: '#2E7D32', color: 'white', borderColor: '#2E7D32' }
                            : etat === 'brouillon' ? { background: '#FFF4E0', color: '#8A5A00', borderColor: '#C77800' }
                            : { background: 'white', color: '#0C5C6C', borderColor: '#0C5C6C' }}>
                          {etat === 'fait' ? '✓ ' : ''}{a.nom} · {etat === 'fait' ? 'fait' : etat === 'brouillon' ? 'brouillon' : 'à faire'}{courant ? ' (en cours)' : ''}
                        </button>
                      );
                    })}
                  </div>
                </div>
              )}
              {catPro === 'veterinaire' && (
                <ActesCr vaccins={vaccinsCr} setVaccins={setVaccinsCr} traitements={traitementsCr} setTraitements={setTraitementsCr}
                  produits={produitsCr} setProduits={setProduitsCr} soins={soinsCr} setSoins={setSoinsCr}
                  onSaisirCarnet={hasWriteAccess ? saisirSoinDepuisCr : undefined}
                  carnet={carnetJour} onRetirerCarnet={cle => setCarnetJour(c => c.filter(x => x.cle !== cle))}
                  profileId={activeProfileId || null} animalId={animalId} />
              )}
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Motif de consultation</label>
                {/* Pré-rempli avec le motif de la demande de RDV ; suggestions usuelles. */}
                <input value={formMotif} onChange={e => setFormMotif(e.target.value)} list="motifs-cr"
                  placeholder="Consultation, vaccination, boiterie…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white" />
                <datalist id="motifs-cr">
                  {['Consultation', 'Vaccination', 'Bilan annuel', 'Urgence', 'Suivi post-opératoire', 'Contrôle', 'Chirurgie'].map(m => <option key={m} value={m} />)}
                </datalist>
                {demandeClient.trim() && (
                  <div className="mt-2 text-xs text-gray-600 bg-gray-50 border border-gray-200 rounded-xl px-3 py-2">
                    <p><span className="font-semibold text-gray-700">Demande du client</span> (reprise dans le compte rendu) : {demandeClient}</p>
                    <button type="button" onClick={() => setDemandeClient('')} className="mt-1 font-semibold text-[#0C5C6C]">Ne pas la reprendre</button>
                  </div>
                )}
              </div>
              <div className="grid grid-cols-[1fr_120px] gap-2 items-end">
                <p className="text-xs font-medium text-gray-500">Poids du jour (kg) — alimente la courbe de poids</p>
                <input value={formPoids} onChange={e => setFormPoids(e.target.value)} inputMode="decimal" placeholder="kg"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Actes réalisés</label>
                <ActesSelect value={actesRealises} onChange={setActesRealises} />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Examen clinique / Diagnostic</label>
                <textarea value={formDiag} onChange={e => setFormDiag(e.target.value)} rows={4}
                  placeholder="Résultats de l'examen, diagnostic posé…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
              <div>
                <label className="text-xs font-medium text-gray-500 block mb-1">Notes / Recommandations</label>
                <textarea value={formNotes} onChange={e => setFormNotes(e.target.value)} rows={3}
                  placeholder="Suivi recommandé, prescriptions, notes libres…"
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>
            </>)}

            {/* Mesure */}
            {addingType === 'mesure' && (<>
              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="text-xs font-medium text-gray-500 block mb-1">Poids (kg)</label>
                  <input type="number" step="0.1" min="0" value={formPoids} onChange={e => setFormPoids(e.target.value)}
                    placeholder={animal.poids ? String(animal.poids) : 'kg'}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                </div>
                <div>
                  <label className="text-xs font-medium text-gray-500 block mb-1">Taille (cm)</label>
                  <input type="number" step="0.5" min="0" value={formTaille} onChange={e => setFormTaille(e.target.value)}
                    placeholder={animal.taille ? String(animal.taille) : 'cm'}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                </div>
              </div>
              {animal.poids != null && <p className="text-xs text-gray-400">Poids actuel : {animal.poids} kg{animal.taille ? ` · ${animal.taille} cm` : ''}</p>}
            </>)}

            {(() => {
              const restants = formManquants.filter(k => k === 'date' ? !formDate : k === 'motif' ? !formMotif.trim() : !formNom.trim())
                .map(k => k === 'date' ? 'Date' : k === 'motif' ? 'Motif' : k.slice(4));
              const lignes = [...(restants.length ? [phraseChampsARemplir(restants)] : []), ...formErreurs];
              return lignes.length > 0 && (
                <ul className="text-xs text-red-600 bg-red-50 rounded-xl px-3 py-2 space-y-0.5">
                  {lignes.map(e => <li key={e}>{e}</li>)}
                </ul>
              );
            })()}
            <div className="flex gap-3 pt-1">
              <button onClick={() => { if (retourCr) { revenirAuCr(retourCr); return; } setAddingType(null); setBrouillonId(null); setCrEdition(null); setFormErreurs([]); setFormManquants([]); }}
                className="flex-1 border border-gray-200 text-gray-600 text-sm font-medium py-2.5 rounded-xl hover:bg-gray-50 transition-colors">
                Annuler
              </button>
              {addingType === 'cr' && catPro === 'veterinaire' && !crEdition && (
                <button onClick={() => saveForm(true)} disabled={savingForm} title="Non visible du propriétaire ; à reprendre plus tard"
                  className="flex-1 border text-sm font-semibold py-2.5 rounded-xl transition-colors disabled:opacity-50"
                  style={{ borderColor: TEAL, color: TEAL, fontFamily: 'Galey, sans-serif' }}>
                  Brouillon
                </button>
              )}
              <button onClick={() => saveForm()} disabled={savingForm}
                className="flex-1 text-white text-sm font-semibold py-2.5 rounded-xl transition-colors disabled:opacity-50"
                style={{ background: TEAL, fontFamily: 'Galey, sans-serif' }}>
                {savingForm ? 'Enregistrement…' : 'Enregistrer'}
              </button>
            </div>
            {addingType === 'cr' && catPro === 'veterinaire' && (
              <p className="text-[11px] text-gray-500 text-center">{crEdition
                ? 'Compte rendu déjà validé : la modification est tracée et le propriétaire voit la version corrigée. Vaccins, examens… déjà inscrits restent dans le texte.'
                : 'Brouillon : non visible du propriétaire, à reprendre et modifier plus tard.'}</p>
            )}
          </div>
        </div>
      )}

      {showSuiviLien && suiviLien && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 sm:p-4"
          onClick={() => setShowSuiviLien(false)}>
          <div className="bg-white rounded-t-2xl sm:rounded-2xl w-full sm:max-w-sm p-5" onClick={e => e.stopPropagation()}>
            <h3 className="font-bold text-[#1F2A2E] text-base mb-1" style={{ fontFamily: 'Galey, sans-serif' }}>
              🔗 Lien pour la famille
            </h3>
            <p className="text-xs text-gray-500 mb-3">Lecture seule, valable 30 jours — plan de travail, exercices, comptes rendus.</p>
            <div className="bg-gray-50 border border-gray-200 rounded-xl px-3 py-2.5 text-xs text-gray-700 break-all mb-3">
              {suiviLien}
            </div>
            <div className="flex gap-2">
              <button onClick={() => { navigator.clipboard?.writeText(suiviLien); }}
                className="flex-1 border border-gray-200 text-gray-600 text-sm font-semibold py-2 rounded-xl">
                Copier
              </button>
              <a href={`https://wa.me/?text=${encodeURIComponent(`Suivi éducatif de ${animal?.nom ?? 'votre animal'} : ${suiviLien}`)}`}
                target="_blank" rel="noopener noreferrer"
                className="flex-1 text-center bg-[#25D366] text-white text-sm font-semibold py-2 rounded-xl">
                WhatsApp
              </a>
            </div>
            <button onClick={() => setShowSuiviLien(false)} className="mt-3 w-full text-xs text-gray-400 py-1">Fermer</button>
          </div>
        </div>
      )}
      {signer && user?.uid && (
        <SignatureProModal onClose={() => setSigner(false)} onValider={async dataUrl => {
          if (await enregistrerSignaturePro(user.uid, dataUrl)) { setSignature(dataUrl); setSigner(false); }
          else alert('Signature non enregistrée — réessayez.');
        }} />
      )}
    </div>
  );
}

export default function PatientDetailPage() {
  return (
    <Suspense fallback={null}>
      <PatientDetailPageInner />
    </Suspense>
  );
}
