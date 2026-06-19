'use client';

import { useState, useRef, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { uploadDocument } from '@/lib/upload-media';
import { generateContratHTML as generateContratHTMLLib, generateCertificatCessionHTML } from '@/lib/contrat-vente';

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



function buildContratHTML(animal: Animal, data: CessionData, eleveur: EleveurInfo): string {
  const sbUrl  = process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
  const sbKey  = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? '';
  return generateContratHTMLLib(animal, data, eleveur, { animalId: animal.id, supabaseUrl: sbUrl, supabaseKey: sbKey });
}

function buildCertHTML(animal: Animal, data: CessionData, eleveur: EleveurInfo, eleveurUid: string): string {
  const sbUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? '';
  const sbKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? '';
  return generateCertificatCessionHTML(animal, data, eleveur, { animalId: animal.id, supabaseUrl: sbUrl, supabaseKey: sbKey, eleveurUid });
}

function openDoc(html: string) {
  const win = window.open('', '_blank', 'width=900,height=700');
  if (!win) { alert('Autorisez les popups'); return; }
  win.document.write(html);
  win.document.close();
}

export default function CessionModal({ animal, uid, eleveurInfo, onClose, onCeded }: Props) {
  const [step, setStep] = useState<'acquéreur' | 'details' | 'documents'>('acquéreur');

  // Acquéreur
  const [searchQuery, setSearchQuery]   = useState('');
  const [searchResult, setSearchResult] = useState<{ uid: string; nom: string; photo?: string } | null>(null);
  const [searchResults, setSearchResults] = useState<{ uid: string; nom: string; photo?: string }[]>([]);
  const [searchDone, setSearchDone]     = useState(false);
  const [searching, setSearching]       = useState(false);
  const [manual, setManual]             = useState(false);

  // Autocomplétion adresse BAN
  const [adressSuggestions, setAdressSuggestions] = useState<{ label: string; rue: string; ville: string; cp: string; pays: string }[]>([]);
  const adressTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

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

  const [saving, setSaving]             = useState(false);
  const [error, setError]               = useState('');
  const [contratSigne, setContratSigne]       = useState(false);
  const [certificatSigne, setCertificatSigne] = useState(false);

  // Contrat existant dans documents_animaux (auto-attach DOC05)
  const [existingContrat, setExistingContrat] = useState<{ type: string; statut: string; url: string } | null>(null);

  // Écoute le contrat ou certificat signé depuis la popup
  useEffect(() => {
    const handler = (e: MessageEvent) => {
      if (e.data?.type === 'contract_signed') {
        if (e.data.url) setContratUrl(e.data.url);
        setContratSigne(true);
      } else if (e.data?.type === 'certificate_signed') {
        if (e.data.url) setCertificatUrl(e.data.url);
        setCertificatSigne(true);
      }
    };
    window.addEventListener('message', handler);
    return () => window.removeEventListener('message', handler);
  }, []);

  // Chargement du contrat existant lié à l'animal (DOC05)
  useEffect(() => {
    supabase.from('documents_animaux')
      .select('type, statut, url')
      .eq('animal_id', animal.id)
      .in('type', ['contrat_vente', 'contrat_reservation'])
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle()
      .then(({ data }) => { if (data) setExistingContrat(data as { type: string; statut: string; url: string }); });
  }, [animal.id]);

  function fillFromUser(data: Record<string, unknown>) {
    const isElv = data.is_elevage === true;
    const n = isElv
      ? ((data.name_elevage as string) || `${data.firstname ?? ''} ${data.lastname ?? ''}`.trim())
      : `${data.firstname ?? ''} ${data.lastname ?? ''}`.trim();
    const phone = isElv
      ? `${data.code_iso_elevage ?? data.code_iso ?? '+33'} ${data.numero_elevage ?? ''}`.trim()
      : `${data.code_iso ?? '+33'} ${data.phone_number ?? ''}`.trim();
    const addr = isElv
      ? ((data.adress_elevage as string) || [data.rue_elevage, data.code_postal_elevage, data.ville_elevage, data.pays_elevage].filter(Boolean).join(', '))
      : ((data.adress as string) || [data.rue, data.code_postal, data.ville, data.pays].filter(Boolean).join(', '));
    setNom(n || 'Utilisateur PetsMatch');
    setEmail((data.email as string) ?? '');
    setTel(phone.replace(/^\+33\s*$/, ''));
    setAdresse(addr || '');
    if (isElv) setQualite('eleveur');
  }

  async function searchUser() {
    const q = searchQuery.trim();
    if (!q) return;
    setSearching(true);
    setSearchDone(false);
    setSearchResult(null);
    setSearchResults([]);
    const FIELDS = 'uid, firstname, lastname, name_elevage, is_elevage, profile_picture_url, email, phone_number, code_iso, rue, ville, code_postal, pays, adress, numero_elevage, code_iso_elevage, rue_elevage, ville_elevage, code_postal_elevage, pays_elevage, adress_elevage';
    const isEmail = q.includes('@');
    let rows: Record<string, unknown>[] = [];
    if (isEmail) {
      const { data } = await supabase.from('users').select(FIELDS).eq('email', q.toLowerCase()).maybeSingle();
      if (data) rows = [data];
    } else {
      const { data } = await supabase.from('users').select(FIELDS)
        .or(`firstname.ilike.%${q}%,lastname.ilike.%${q}%,name_elevage.ilike.%${q}%`)
        .limit(6);
      rows = (data as Record<string, unknown>[]) ?? [];
    }
    if (rows.length === 1) {
      const d = rows[0];
      const n = (d.is_elevage ? (d.name_elevage as string) : '') || `${d.firstname ?? ''} ${d.lastname ?? ''}`.trim();
      setSearchResult({ uid: d.uid as string, nom: n || 'Utilisateur PetsMatch', photo: d.profile_picture_url as string });
      fillFromUser(d);
    } else if (rows.length > 1) {
      setSearchResults(rows.map(d => {
        const n = (d.is_elevage ? (d.name_elevage as string) : '') || `${d.firstname ?? ''} ${d.lastname ?? ''}`.trim();
        return { uid: d.uid as string, nom: n || 'Utilisateur PetsMatch', photo: d.profile_picture_url as string, _raw: d };
      }) as { uid: string; nom: string; photo?: string }[]);
    }
    setSearchDone(true);
    setSearching(false);
  }

  function selectFromList(item: { uid: string; nom: string; photo?: string; _raw?: Record<string, unknown> }) {
    setSearchResult({ uid: item.uid, nom: item.nom, photo: item.photo });
    setSearchResults([]);
    if (item._raw) fillFromUser(item._raw);
  }

  async function fetchAdressSuggestions(val: string) {
    if (val.length < 3) { setAdressSuggestions([]); return; }
    try {
      const res = await fetch(`https://api-adresse.data.gouv.fr/search/?q=${encodeURIComponent(val)}&limit=5`);
      const json = await res.json();
      setAdressSuggestions((json.features ?? []).map((f: { properties: { label: string; housenumber?: string; street?: string; city?: string; postcode?: string; country?: string } }) => ({
        label: f.properties.label,
        rue: [f.properties.housenumber, f.properties.street].filter(Boolean).join(' '),
        ville: f.properties.city ?? '',
        cp: f.properties.postcode ?? '',
        pays: 'France',
      })));
    } catch { setAdressSuggestions([]); }
  }

  function onAdresseChange(val: string) {
    setAdresse(val);
    if (adressTimer.current) clearTimeout(adressTimer.current);
    adressTimer.current = setTimeout(() => fetchAdressSuggestions(val), 300);
  }

  function pickAdresse(s: { label: string; rue: string; ville: string; cp: string; pays: string }) {
    setAdresse(s.label);
    setAdressSuggestions([]);
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
      // Auto-attach contrat existant si aucun n'a été uploadé manuellement (DOC05)
      const finalContratUrl = contratUrl || existingContrat?.url || null;

      await supabase.from('animaux').update({
        statut:                 'sorti',
        date_sortie:            dateCession,
        destinataire_qualite:   qualite,
        destinataire_nom:       nom.trim(),
        destinataire_adresse:   adresse.trim() || null,
        uid_acquereur:          searchResult?.uid ?? null,
        cession_contrat_url:    finalContratUrl,
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
                    type="text" placeholder="Nom ou email de l'acquéreur…"
                    value={searchQuery} onChange={e => setSearchQuery(e.target.value)}
                    onKeyDown={e => { if (e.key === 'Enter') searchUser(); }}
                    className="flex-1 border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]"
                  />
                  <button onClick={searchUser} disabled={searching}
                    className="px-4 py-2 bg-[#0C5C6C] text-white text-sm font-semibold rounded-xl hover:bg-[#094F5D] disabled:opacity-50 transition-colors">
                    {searching ? '…' : 'Chercher'}
                  </button>
                </div>
              </div>

              {searchDone && searchResults.length > 1 && (
                <div className="rounded-xl border border-gray-200 overflow-hidden">
                  {(searchResults as { uid: string; nom: string; photo?: string; _raw?: Record<string, unknown> }[]).map(r => (
                    <button key={r.uid} onClick={() => selectFromList(r)}
                      className="w-full flex items-center gap-3 px-4 py-3 hover:bg-[#0C5C6C]/5 border-b border-gray-100 last:border-0 transition-colors text-left">
                      {r.photo
                        ? <img src={r.photo} className="w-8 h-8 rounded-full object-cover flex-shrink-0" alt="" />
                        : <div className="w-8 h-8 rounded-full bg-[#0C5C6C]/10 flex items-center justify-center text-sm flex-shrink-0">🐾</div>}
                      <span className="text-sm font-semibold text-[#1F2A2E]">{r.nom}</span>
                    </button>
                  ))}
                </div>
              )}

              {searchDone && searchResults.length === 0 && (
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
                    <p className="text-sm text-gray-500 text-center">Aucun utilisateur trouvé.</p>
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

              <div className="relative">
                <label className="block text-xs font-semibold text-gray-500 mb-1">Adresse</label>
                <input type="text" placeholder="Adresse de l'acquéreur" value={adresse}
                  onChange={e => manual ? onAdresseChange(e.target.value) : setAdresse(e.target.value)}
                  readOnly={!!searchResult && !manual}
                  className={`w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] ${searchResult && !manual ? 'bg-gray-50' : ''}`} />
                {manual && adressSuggestions.length > 0 && (
                  <div className="absolute z-10 top-full left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
                    {adressSuggestions.map((s, i) => (
                      <button key={i} onClick={() => pickAdresse(s)}
                        className="w-full text-left px-4 py-2.5 text-sm hover:bg-[#0C5C6C]/5 border-b border-gray-100 last:border-0 transition-colors">
                        {s.label}
                      </button>
                    ))}
                  </div>
                )}
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

              {/* Bannière contrat existant auto-attaché (DOC05) */}
              {existingContrat && !contratUrl && (
                <div className="flex items-start gap-2 bg-green-50 border border-green-200 rounded-xl p-3">
                  <span className="text-green-600 mt-0.5">✅</span>
                  <div>
                    <p className="text-xs font-bold text-green-800">Contrat existant détecté</p>
                    <p className="text-xs text-green-700">
                      {existingContrat.type === 'contrat_reservation' ? 'Contrat de réservation' : 'Contrat de vente'}
                      {' '}({existingContrat.statut === 'signe' ? 'signé ✓' : 'brouillon'}) — sera automatiquement attaché à cette cession.
                    </p>
                  </div>
                </div>
              )}

              {/* Certificat de cession */}
              <div className={`border rounded-xl p-4 space-y-3 ${certificatSigne ? 'border-green-300 bg-green-50' : 'border-gray-200'}`}>
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm font-bold text-[#1F2A2E]">📜 Certificat de cession</p>
                    <p className="text-xs text-gray-400">Document légal de transfert — champs modifiables + signature canvas</p>
                  </div>
                  <button
                    onClick={() => openDoc(buildCertHTML(animal, cessionData, eleveurInfo, uid))}
                    className="text-xs font-semibold text-[#0C5C6C] border border-[#0C5C6C]/30 px-3 py-1.5 rounded-lg hover:bg-[#0C5C6C]/5 transition-colors">
                    ✍️ Générer &amp; signer
                  </button>
                </div>
                {certificatSigne && (
                  <div className="flex items-center gap-2 text-xs text-green-700 font-semibold">
                    <span>✅ Certificat signé numériquement et enregistré</span>
                    {certificatUrl && <a href={certificatUrl} target="_blank" rel="noreferrer" className="underline">Voir</a>}
                  </div>
                )}
                {!certificatSigne && (
                  <div>
                    <input ref={certificatRef} type="file" accept=".pdf,.jpg,.jpeg,.png" className="hidden"
                      onChange={e => { if (e.target.files?.[0]) uploadDoc(e.target.files[0], 'certificat'); }} />
                    <button onClick={() => certificatRef.current?.click()} disabled={uploadingCertificat}
                      className="w-full border-2 border-dashed border-gray-200 rounded-xl py-2.5 text-xs text-gray-400 hover:border-[#0C5C6C]/40 hover:text-[#0C5C6C] transition-colors">
                      {uploadingCertificat ? '⏳ Upload…' : certificatUrl ? '✓ Uploadé · Remplacer' : '⬆️ Ou uploader un PDF signé'}
                    </button>
                  </div>
                )}
              </div>

              {/* Contrat de vente numérique */}
              <div className={`border rounded-xl p-4 space-y-3 ${contratSigne ? 'border-green-300 bg-green-50' : 'border-gray-200'}`}>
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-sm font-bold text-[#1F2A2E]">🤝 Contrat de vente</p>
                    <p className="text-xs text-gray-400">Signature numérique · Stocké pour les deux parties</p>
                  </div>
                  <button
                    onClick={() => openDoc(buildContratHTML(animal, cessionData, eleveurInfo))}
                    className="text-xs font-semibold text-[#6E9E57] border border-[#6E9E57]/40 px-3 py-1.5 rounded-lg hover:bg-[#6E9E57]/5 transition-colors">
                    ✍️ Signer en ligne
                  </button>
                </div>
                {contratSigne && (
                  <div className="flex items-center gap-2 text-xs text-green-700 font-semibold">
                    <span>✅ Contrat signé numériquement et enregistré</span>
                    {contratUrl && <a href={contratUrl} target="_blank" rel="noreferrer" className="underline">Voir</a>}
                  </div>
                )}
                {!contratSigne && (
                  <div>
                    <input ref={contratRef} type="file" accept=".pdf,.jpg,.jpeg,.png" className="hidden"
                      onChange={e => { if (e.target.files?.[0]) uploadDoc(e.target.files[0], 'contrat'); }} />
                    <button onClick={() => contratRef.current?.click()} disabled={uploadingContrat}
                      className="w-full border-2 border-dashed border-gray-200 rounded-xl py-2 text-xs text-gray-400 hover:border-[#0C5C6C]/40 hover:text-[#0C5C6C] transition-colors">
                      {uploadingContrat ? '⏳ Upload…' : contratUrl ? '✓ Uploadé · Remplacer' : '⬆️ Ou uploader un PDF signé'}
                    </button>
                  </div>
                )}
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
