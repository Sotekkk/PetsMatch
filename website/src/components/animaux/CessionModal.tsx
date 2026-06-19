'use client';

import { useState, useRef } from 'react';
import { supabase } from '@/lib/supabase';
import { uploadDocument } from '@/lib/upload-media';

interface Animal {
  id: string;
  nom?: string;
  espece?: string;
  race?: string;
  sexe?: string;
  identification?: string;
  date_naissance?: string;
  uid_eleveur?: string | null;
}

interface EleveurInfo {
  nom: string;
  adresse?: string;
  email?: string;
  tel?: string;
  siret?: string;
}

interface CessionData {
  qualite: string;
  nom: string;
  email: string;
  tel: string;
  adresse: string;
  dateCession: string;
  prix: string;
  notes: string;
  uid_acquereur: string | null;
}

interface Props {
  animal: Animal;
  uid: string;
  eleveurInfo: EleveurInfo;
  onClose: () => void;
  onCeded: () => void;
}

const QUALITES = [
  { value: 'particulier', label: 'Particulier' },
  { value: 'eleveur',     label: 'Éleveur' },
  { value: 'refuge',      label: 'Refuge / Association' },
  { value: 'autre',       label: 'Autre' },
];

function fmtDate(s?: string) {
  if (!s) return '—';
  return new Date(s).toLocaleDateString('fr-FR');
}

function generateCertificatHTML(animal: Animal, data: CessionData, eleveur: EleveurInfo): string {
  const today = new Date().toLocaleDateString('fr-FR');
  const espece = animal.espece ? (animal.espece.charAt(0).toUpperCase() + animal.espece.slice(1)) : '—';
  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"><title>Certificat de cession</title>
<style>
  body{font-family:Arial,sans-serif;font-size:12px;margin:40px;color:#222}
  h1{font-size:20px;text-align:center;margin-bottom:4px;color:#0C5C6C}
  .sub{text-align:center;font-size:11px;color:#666;margin-bottom:28px}
  .section{margin-bottom:18px}
  .section-title{font-size:13px;font-weight:bold;color:#0C5C6C;border-bottom:1px solid #0C5C6C;padding-bottom:3px;margin-bottom:8px}
  .row{display:flex;gap:24px;margin-bottom:6px}
  .field{flex:1}
  .label{font-size:10px;color:#666;margin-bottom:2px}
  .value{font-size:12px;font-weight:600}
  .sign-row{display:flex;gap:48px;margin-top:40px}
  .sign-block{flex:1}
  .sign-line{border-bottom:1px solid #888;margin-top:40px;margin-bottom:4px}
  .foot{margin-top:32px;font-size:9px;color:#aaa;text-align:center}
  @media print{body{margin:20px}}
</style></head><body>
<h1>Certificat de cession</h1>
<p class="sub">Établi conformément aux dispositions légales en vigueur</p>

<div class="section">
  <div class="section-title">Vendeur / Cédant</div>
  <div class="row">
    <div class="field"><div class="label">Nom / Raison sociale</div><div class="value">${eleveur.nom}</div></div>
    <div class="field"><div class="label">Adresse</div><div class="value">${eleveur.adresse ?? '—'}</div></div>
  </div>
  <div class="row">
    <div class="field"><div class="label">Email</div><div class="value">${eleveur.email ?? '—'}</div></div>
    <div class="field"><div class="label">Téléphone</div><div class="value">${eleveur.tel ?? '—'}</div></div>
    ${eleveur.siret ? `<div class="field"><div class="label">SIRET</div><div class="value">${eleveur.siret}</div></div>` : ''}
  </div>
</div>

<div class="section">
  <div class="section-title">Acquéreur</div>
  <div class="row">
    <div class="field"><div class="label">Nom</div><div class="value">${data.nom || '—'}</div></div>
    <div class="field"><div class="label">Qualité</div><div class="value">${QUALITES.find(q => q.value === data.qualite)?.label ?? data.qualite}</div></div>
  </div>
  <div class="row">
    <div class="field"><div class="label">Adresse</div><div class="value">${data.adresse || '—'}</div></div>
    <div class="field"><div class="label">Email</div><div class="value">${data.email || '—'}</div></div>
    <div class="field"><div class="label">Téléphone</div><div class="value">${data.tel || '—'}</div></div>
  </div>
</div>

<div class="section">
  <div class="section-title">Animal cédé</div>
  <div class="row">
    <div class="field"><div class="label">Nom</div><div class="value">${animal.nom ?? '—'}</div></div>
    <div class="field"><div class="label">Espèce / Race</div><div class="value">${espece} — ${animal.race ?? '—'}</div></div>
    <div class="field"><div class="label">Sexe</div><div class="value">${animal.sexe ?? '—'}</div></div>
  </div>
  <div class="row">
    <div class="field"><div class="label">Date de naissance</div><div class="value">${fmtDate(animal.date_naissance)}</div></div>
    <div class="field"><div class="label">N° identification</div><div class="value">${animal.identification ?? '—'}</div></div>
  </div>
</div>

<div class="section">
  <div class="section-title">Conditions de cession</div>
  <div class="row">
    <div class="field"><div class="label">Date de cession</div><div class="value">${fmtDate(data.dateCession)}</div></div>
    <div class="field"><div class="label">Prix de cession</div><div class="value">${data.prix ? data.prix + ' €' : 'Non communiqué'}</div></div>
  </div>
  ${data.notes ? `<div style="margin-top:6px"><div class="label">Notes</div><div class="value">${data.notes}</div></div>` : ''}
</div>

<div class="section">
  <p style="font-size:11px;line-height:1.6;color:#444">
    Je soussigné·e, vendeur / cédant, certifie que l'animal décrit ci-dessus est en bonne santé au jour de la cession,
    à ma connaissance, et qu'il a fait l'objet des soins nécessaires à son bon développement.<br/>
    L'acquéreur reconnaît avoir pris connaissance de l'état de santé de l'animal et accepte les conditions de la présente cession.
  </p>
</div>

<div class="sign-row">
  <div class="sign-block">
    <div style="font-size:11px;font-weight:bold">Signature du vendeur</div>
    <div style="font-size:10px;color:#666;margin-bottom:2px">${eleveur.nom}</div>
    <div class="sign-line"></div>
    <div style="font-size:9px;color:#aaa">Date et signature</div>
  </div>
  <div class="sign-block">
    <div style="font-size:11px;font-weight:bold">Signature de l'acquéreur</div>
    <div style="font-size:10px;color:#666;margin-bottom:2px">${data.nom || '...'}</div>
    <div class="sign-line"></div>
    <div style="font-size:9px;color:#aaa">Date et signature</div>
  </div>
</div>

<p class="foot">Document généré le ${today} via PetsMatch · Ce certificat ne remplace pas les obligations légales d'identification et de déclaration.</p>
</body></html>`;
}

function generateContratHTML(animal: Animal, data: CessionData, eleveur: EleveurInfo): string {
  const today = new Date().toLocaleDateString('fr-FR');
  const espece = animal.espece ? (animal.espece.charAt(0).toUpperCase() + animal.espece.slice(1)) : '—';
  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="UTF-8"><title>Contrat de vente</title>
<style>
  body{font-family:Arial,sans-serif;font-size:12px;margin:40px;color:#222}
  h1{font-size:20px;text-align:center;margin-bottom:4px;color:#0C5C6C}
  .sub{text-align:center;font-size:11px;color:#666;margin-bottom:28px}
  .section{margin-bottom:18px}
  .section-title{font-size:13px;font-weight:bold;color:#0C5C6C;border-bottom:1px solid #0C5C6C;padding-bottom:3px;margin-bottom:8px}
  .row{display:flex;gap:24px;margin-bottom:6px}
  .field{flex:1}
  .label{font-size:10px;color:#666;margin-bottom:2px}
  .value{font-size:12px;font-weight:600}
  .article{margin-bottom:14px}
  .art-title{font-size:11px;font-weight:bold;margin-bottom:4px}
  .art-body{font-size:11px;line-height:1.6;color:#444}
  .sign-row{display:flex;gap:48px;margin-top:40px}
  .sign-block{flex:1}
  .sign-line{border-bottom:1px solid #888;margin-top:40px;margin-bottom:4px}
  .foot{margin-top:32px;font-size:9px;color:#aaa;text-align:center}
  @media print{body{margin:20px}}
</style></head><body>
<h1>Contrat de vente d'animal</h1>
<p class="sub">Entre les soussignés — Établi le ${fmtDate(data.dateCession)}</p>

<div class="section">
  <div class="section-title">Parties</div>
  <div class="row">
    <div class="field">
      <div class="label">Vendeur</div>
      <div class="value">${eleveur.nom}</div>
      <div style="font-size:11px;color:#555">${eleveur.adresse ?? ''} · ${eleveur.email ?? ''} · ${eleveur.tel ?? ''}</div>
      ${eleveur.siret ? `<div style="font-size:11px;color:#555">SIRET : ${eleveur.siret}</div>` : ''}
    </div>
    <div class="field">
      <div class="label">Acheteur</div>
      <div class="value">${data.nom || '—'} (${QUALITES.find(q => q.value === data.qualite)?.label ?? data.qualite})</div>
      <div style="font-size:11px;color:#555">${data.adresse || ''} · ${data.email || ''} · ${data.tel || ''}</div>
    </div>
  </div>
</div>

<div class="section">
  <div class="section-title">Animal vendu</div>
  <div class="row">
    <div class="field"><div class="label">Nom</div><div class="value">${animal.nom ?? '—'}</div></div>
    <div class="field"><div class="label">Espèce / Race</div><div class="value">${espece} — ${animal.race ?? '—'}</div></div>
    <div class="field"><div class="label">Sexe</div><div class="value">${animal.sexe ?? '—'}</div></div>
  </div>
  <div class="row">
    <div class="field"><div class="label">Date de naissance</div><div class="value">${fmtDate(animal.date_naissance)}</div></div>
    <div class="field"><div class="label">N° identification</div><div class="value">${animal.identification ?? '—'}</div></div>
  </div>
</div>

<div class="section">
  <div class="section-title">Conditions</div>
  <div class="row">
    <div class="field"><div class="label">Date de vente</div><div class="value">${fmtDate(data.dateCession)}</div></div>
    <div class="field"><div class="label">Prix de vente TTC</div><div class="value">${data.prix ? data.prix + ' €' : '—'}</div></div>
  </div>
</div>

<div class="section">
  <div class="section-title">Clauses</div>
  <div class="article">
    <div class="art-title">Article 1 — Garanties légales</div>
    <div class="art-body">Conformément aux articles L.217-1 et suivants du Code de la consommation, l'animal vendu est garanti contre les vices cachés pendant 30 jours à compter de la livraison. Le vendeur déclare l'animal en bonne santé à sa connaissance au jour de la vente.</div>
  </div>
  <div class="article">
    <div class="art-title">Article 2 — État de santé</div>
    <div class="art-body">L'acheteur déclare avoir pris connaissance du carnet de santé de l'animal et accepte l'animal dans l'état dans lequel il se trouve. L'animal a bénéficié des vaccinations et traitements prophylactiques appropriés à son âge.</div>
  </div>
  <div class="article">
    <div class="art-title">Article 3 — Transfert de propriété</div>
    <div class="art-body">Le transfert de propriété s'effectue à la date de remise de l'animal contre paiement du prix convenu. L'acheteur s'engage à déclarer le changement de propriétaire auprès de l'organisme d'identification compétent dans les délais légaux.</div>
  </div>
  <div class="article">
    <div class="art-title">Article 4 — Bien-être animal</div>
    <div class="art-body">L'acheteur s'engage à assurer les soins nécessaires à l'animal, à lui procurer des conditions de vie adaptées à son espèce et sa race, et à respecter la législation en vigueur relative à la détention d'animaux de compagnie.</div>
  </div>
  ${data.notes ? `<div class="article"><div class="art-title">Conditions particulières</div><div class="art-body">${data.notes}</div></div>` : ''}
</div>

<div class="sign-row">
  <div class="sign-block">
    <div style="font-size:11px;font-weight:bold">Vendeur — Lu et approuvé</div>
    <div style="font-size:10px;color:#666;margin-bottom:2px">${eleveur.nom}</div>
    <div class="sign-line"></div>
    <div style="font-size:9px;color:#aaa">Date et signature</div>
  </div>
  <div class="sign-block">
    <div style="font-size:11px;font-weight:bold">Acheteur — Lu et approuvé</div>
    <div style="font-size:10px;color:#666;margin-bottom:2px">${data.nom || '...'}</div>
    <div class="sign-line"></div>
    <div style="font-size:9px;color:#aaa">Date et signature</div>
  </div>
</div>

<p class="foot">Contrat établi en deux exemplaires originaux · ${today} · PetsMatch</p>
</body></html>`;
}

function openPrint(html: string) {
  const win = window.open('', '_blank');
  if (!win) { alert('Autorisez les popups pour imprimer'); return; }
  win.document.write(html);
  win.document.close();
  setTimeout(() => win.print(), 400);
}

export default function CessionModal({ animal, uid, eleveurInfo, onClose, onCeded }: Props) {
  const [step, setStep] = useState<'acquéreur' | 'details' | 'documents'>('acquéreur');

  // Acquéreur
  const [searchEmail, setSearchEmail]   = useState('');
  const [searchResult, setSearchResult] = useState<{ uid: string; nom: string; photo?: string } | null>(null);
  const [searchDone, setSearchDone]     = useState(false);
  const [searching, setSearching]       = useState(false);
  const [manual, setManual]             = useState(false);

  // Détails
  const [qualite, setQualite]       = useState('particulier');
  const [nom, setNom]               = useState('');
  const [email, setEmail]           = useState('');
  const [tel, setTel]               = useState('');
  const [adresse, setAdresse]       = useState('');
  const [dateCession, setDateCession] = useState(new Date().toISOString().split('T')[0]);
  const [prix, setPrix]             = useState('');
  const [notes, setNotes]           = useState('');

  // Documents
  const [contratUrl, setContratUrl]       = useState('');
  const [certificatUrl, setCertificatUrl] = useState('');
  const [uploadingContrat, setUploadingContrat]       = useState(false);
  const [uploadingCertificat, setUploadingCertificat] = useState(false);
  const contratRef    = useRef<HTMLInputElement>(null);
  const certificatRef = useRef<HTMLInputElement>(null);

  const [saving, setSaving] = useState(false);
  const [error, setError]   = useState('');

  async function searchUser() {
    if (!searchEmail.trim()) return;
    setSearching(true);
    setSearchDone(false);
    setSearchResult(null);
    const { data } = await supabase
      .from('users')
      .select('uid, firstname, lastname, name_elevage, is_elevage, profile_picture_url')
      .eq('email', searchEmail.trim().toLowerCase())
      .maybeSingle();
    if (data) {
      const n = data.is_elevage
        ? (data.name_elevage ?? `${data.firstname ?? ''} ${data.lastname ?? ''}`.trim())
        : `${data.firstname ?? ''} ${data.lastname ?? ''}`.trim();
      setSearchResult({ uid: data.uid, nom: n || 'Utilisateur PetsMatch', photo: data.profile_picture_url });
      setNom(n);
      setEmail(searchEmail.trim());
    }
    setSearchDone(true);
    setSearching(false);
  }

  async function uploadDoc(file: File, type: 'contrat' | 'certificat') {
    const setter = type === 'contrat' ? setUploadingContrat : setUploadingCertificat;
    const urlSetter = type === 'contrat' ? setContratUrl : setCertificatUrl;
    setter(true);
    try {
      const ext = file.name.split('.').pop() ?? 'pdf';
      const path = `cessions/${uid}/${animal.id}/${type}_${Date.now()}.${ext}`;
      const url = await uploadDocument(file, path);
      urlSetter(url);
    } catch (e) {
      setError(`Erreur upload : ${e}`);
    } finally {
      setter(false);
    }
  }

  async function save() {
    if (!nom.trim() && !searchResult) { setError('Le nom de l\'acquéreur est requis.'); return; }
    if (!dateCession) { setError('La date de cession est requise.'); return; }
    setSaving(true);
    setError('');
    try {
      await supabase.from('animaux').update({
        statut:                 'sorti',
        date_sortie:            dateCession,
        destinataire_qualite:   qualite,
        destinataire_nom:       nom.trim(),
        destinataire_adresse:   adresse.trim() || null,
        uid_acquereur:          searchResult?.uid ?? null,
        cession_contrat_url:    contratUrl || null,
        cession_certificat_url: certificatUrl || null,
        cession_prix:           prix ? parseFloat(prix) : null,
        cession_notes:          notes.trim() || null,
      }).eq('id', animal.id);

      // Notifier l'acquéreur si c'est un utilisateur PetsMatch
      if (searchResult?.uid) {
        await supabase.from('notifications').insert({
          uid:   searchResult.uid,
          type:  'cession_animal',
          title: `🐾 Animal reçu : ${animal.nom ?? 'Animal'}`,
          body:  `${eleveurInfo.nom} vous a cédé ${animal.nom ?? 'un animal'}. Consultez vos animaux pour voir sa fiche.`,
          data:  { animalId: animal.id },
          read:  false,
        });
      }

      onCeded();
    } catch (e) {
      setError(`Erreur : ${e}`);
      setSaving(false);
    }
  }

  const cessionData: CessionData = { qualite, nom, email, tel, adresse, dateCession, prix, notes, uid_acquereur: searchResult?.uid ?? null };

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 backdrop-blur-sm p-0 sm:p-4">
      <div className="bg-white w-full sm:max-w-lg rounded-t-3xl sm:rounded-2xl shadow-2xl max-h-[92vh] overflow-y-auto">
        {/* Header */}
        <div className="sticky top-0 bg-white border-b border-gray-100 px-5 py-4 flex items-center justify-between rounded-t-3xl sm:rounded-t-2xl">
          <div>
            <h2 className="text-base font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey,sans-serif' }}>
              🤝 Céder {animal.nom ?? 'cet animal'}
            </h2>
            <p className="text-xs text-gray-400 mt-0.5">
              {step === 'acquéreur' ? 'Étape 1/3 — Acquéreur' : step === 'details' ? 'Étape 2/3 — Détails' : 'Étape 3/3 — Documents'}
            </p>
          </div>
          <button onClick={onClose} className="w-8 h-8 flex items-center justify-center text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-full transition-colors">✕</button>
        </div>

        <div className="p-5 space-y-4">

          {/* ── Étape 1 : Acquéreur ──────────────────────────────────── */}
          {step === 'acquéreur' && (
            <>
              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-2">Rechercher un utilisateur PetsMatch</label>
                <div className="flex gap-2">
                  <input
                    type="email" placeholder="Email de l'acquéreur"
                    value={searchEmail} onChange={e => setSearchEmail(e.target.value)}
                    onKeyDown={e => { if (e.key === 'Enter') searchUser(); }}
                    className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]"
                  />
                  <button onClick={searchUser} disabled={searching}
                    className="px-4 py-2 bg-[#0C5C6C] text-white text-sm font-semibold rounded-xl hover:bg-[#094F5D] disabled:opacity-50 transition-colors">
                    {searching ? '…' : 'Chercher'}
                  </button>
                </div>
              </div>

              {searchDone && (
                <div className={`rounded-xl p-3 border ${searchResult ? 'border-[#0C5C6C]/20 bg-[#0C5C6C]/5' : 'border-gray-200 bg-gray-50'}`}>
                  {searchResult ? (
                    <div className="flex items-center gap-3">
                      {searchResult.photo
                        ? <img src={searchResult.photo} className="w-10 h-10 rounded-full object-cover" alt="" />
                        : <div className="w-10 h-10 rounded-full bg-[#0C5C6C]/10 flex items-center justify-center text-lg">🐾</div>}
                      <div>
                        <p className="text-sm font-bold text-[#1F2A2E]">{searchResult.nom}</p>
                        <p className="text-xs text-[#0C5C6C]">✓ Utilisateur PetsMatch trouvé</p>
                      </div>
                    </div>
                  ) : (
                    <p className="text-sm text-gray-500 text-center">Aucun utilisateur trouvé avec cet email.</p>
                  )}
                </div>
              )}

              <div className="flex items-center gap-3">
                <div className="flex-1 h-px bg-gray-200" />
                <span className="text-xs text-gray-400">ou</span>
                <div className="flex-1 h-px bg-gray-200" />
              </div>

              <button
                onClick={() => { setManual(true); setStep('details'); }}
                className="w-full border border-gray-200 rounded-xl px-4 py-3 text-sm font-semibold text-gray-600 hover:bg-gray-50 hover:border-[#0C5C6C] transition-colors">
                ✏️ Saisie manuelle (acquéreur hors PetsMatch)
              </button>

              {searchResult && (
                <button
                  onClick={() => setStep('details')}
                  className="w-full bg-[#0C5C6C] text-white font-semibold py-3 rounded-xl text-sm hover:bg-[#094F5D] transition-colors">
                  Continuer →
                </button>
              )}
            </>
          )}

          {/* ── Étape 2 : Détails ───────────────────────────────────── */}
          {step === 'details' && (
            <>
              {searchResult && (
                <div className="rounded-xl p-3 border border-[#0C5C6C]/20 bg-[#0C5C6C]/5 flex items-center gap-3">
                  <span className="text-lg">✓</span>
                  <p className="text-sm font-semibold text-[#0C5C6C]">{searchResult.nom} · PetsMatch</p>
                </div>
              )}

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-gray-500 mb-1">Date de cession *</label>
                  <input type="date" value={dateCession} onChange={e => setDateCession(e.target.value)}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-gray-500 mb-1">Prix (€)</label>
                  <input type="number" min="0" placeholder="0" value={prix} onChange={e => setPrix(e.target.value)}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1">Qualité de l'acquéreur</label>
                <div className="flex flex-wrap gap-2">
                  {QUALITES.map(q => (
                    <button key={q.value} onClick={() => setQualite(q.value)}
                      className={`px-3 py-1.5 rounded-full text-xs font-semibold border transition-colors ${qualite === q.value ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-600 border-gray-200'}`}>
                      {q.label}
                    </button>
                  ))}
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1">Nom de l'acquéreur *</label>
                <input type="text" placeholder="Nom complet" value={nom} onChange={e => setNom(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-gray-500 mb-1">Email</label>
                  <input type="email" placeholder="email@exemple.fr" value={email} onChange={e => setEmail(e.target.value)}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-gray-500 mb-1">Téléphone</label>
                  <input type="tel" placeholder="06 XX XX XX XX" value={tel} onChange={e => setTel(e.target.value)}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                </div>
              </div>

              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1">Adresse</label>
                <input type="text" placeholder="Adresse de l'acquéreur" value={adresse} onChange={e => setAdresse(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>

              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1">Notes / Conditions particulières</label>
                <textarea rows={3} placeholder="Conditions de remise, remarques…" value={notes} onChange={e => setNotes(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>

              <div className="flex gap-2 pt-2">
                <button onClick={() => setStep('acquéreur')}
                  className="flex-1 border border-gray-200 text-gray-600 font-semibold py-2.5 rounded-xl text-sm hover:bg-gray-50 transition-colors">
                  ← Retour
                </button>
                <button onClick={() => setStep('documents')} disabled={!nom.trim() || !dateCession}
                  className="flex-1 bg-[#0C5C6C] text-white font-semibold py-2.5 rounded-xl text-sm hover:bg-[#094F5D] disabled:opacity-40 transition-colors">
                  Documents →
                </button>
              </div>
            </>
          )}

          {/* ── Étape 3 : Documents ─────────────────────────────────── */}
          {step === 'documents' && (
            <>
              <p className="text-xs text-gray-500">Générez les documents et/ou uploadez les versions signées.</p>

              {/* Certificat de cession */}
              <div className="border border-gray-200 rounded-xl p-4 space-y-3">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm font-bold text-[#1F2A2E]">📜 Certificat de cession</p>
                    <p className="text-xs text-gray-400">Document légal de transfert de propriété</p>
                  </div>
                  <button
                    onClick={() => openPrint(generateCertificatHTML(animal, cessionData, eleveurInfo))}
                    className="text-xs font-semibold text-[#0C5C6C] border border-[#0C5C6C]/30 px-3 py-1.5 rounded-lg hover:bg-[#0C5C6C]/5 transition-colors">
                    🖨️ Générer
                  </button>
                </div>
                <div>
                  <input ref={certificatRef} type="file" accept=".pdf,.jpg,.jpeg,.png" className="hidden"
                    onChange={e => { if (e.target.files?.[0]) uploadDoc(e.target.files[0], 'certificat'); }} />
                  <button onClick={() => certificatRef.current?.click()} disabled={uploadingCertificat}
                    className="w-full border-2 border-dashed border-gray-200 rounded-xl py-2.5 text-xs text-gray-400 hover:border-[#0C5C6C]/40 hover:text-[#0C5C6C] transition-colors">
                    {uploadingCertificat ? '⏳ Upload…' : certificatUrl ? '✓ Certificat uploadé · Remplacer' : '⬆️ Uploader le certificat signé'}
                  </button>
                  {certificatUrl && <p className="text-xs text-green-600 mt-1">✓ Certificat enregistré</p>}
                </div>
              </div>

              {/* Contrat de vente */}
              <div className="border border-gray-200 rounded-xl p-4 space-y-3">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm font-bold text-[#1F2A2E]">🤝 Contrat de vente</p>
                    <p className="text-xs text-gray-400">Inclut garanties légales et clauses de vente</p>
                  </div>
                  <button
                    onClick={() => openPrint(generateContratHTML(animal, cessionData, eleveurInfo))}
                    className="text-xs font-semibold text-[#0C5C6C] border border-[#0C5C6C]/30 px-3 py-1.5 rounded-lg hover:bg-[#0C5C6C]/5 transition-colors">
                    🖨️ Générer
                  </button>
                </div>
                <div>
                  <input ref={contratRef} type="file" accept=".pdf,.jpg,.jpeg,.png" className="hidden"
                    onChange={e => { if (e.target.files?.[0]) uploadDoc(e.target.files[0], 'contrat'); }} />
                  <button onClick={() => contratRef.current?.click()} disabled={uploadingContrat}
                    className="w-full border-2 border-dashed border-gray-200 rounded-xl py-2.5 text-xs text-gray-400 hover:border-[#0C5C6C]/40 hover:text-[#0C5C6C] transition-colors">
                    {uploadingContrat ? '⏳ Upload…' : contratUrl ? '✓ Contrat uploadé · Remplacer' : '⬆️ Uploader le contrat signé'}
                  </button>
                  {contratUrl && <p className="text-xs text-green-600 mt-1">✓ Contrat enregistré</p>}
                </div>
              </div>

              {error && <p className="text-xs text-red-600 bg-red-50 px-3 py-2 rounded-xl">{error}</p>}

              <div className="flex gap-2 pt-2">
                <button onClick={() => setStep('details')}
                  className="flex-1 border border-gray-200 text-gray-600 font-semibold py-2.5 rounded-xl text-sm hover:bg-gray-50 transition-colors">
                  ← Retour
                </button>
                <button onClick={save} disabled={saving}
                  className="flex-1 bg-[#6E9E57] text-white font-semibold py-2.5 rounded-xl text-sm hover:bg-[#5B8648] disabled:opacity-50 transition-colors">
                  {saving ? '⏳ Enregistrement…' : '✓ Valider la cession'}
                </button>
              </div>
              <p className="text-xs text-gray-400 text-center">Les documents sont optionnels. Vous pouvez les ajouter plus tard.</p>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
