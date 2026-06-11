'use client';

import { useState, useRef, useEffect } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { createUserWithEmailAndPassword, signInWithEmailAndPassword, updateProfile, GoogleAuthProvider, signInWithPopup } from 'firebase/auth';
import { ref as storageRef, uploadBytes, getDownloadURL } from 'firebase/storage';
import { auth, storage } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { setOptions, importLibrary } from '@googlemaps/js-api-loader';

const MAPS_KEY = process.env.NEXT_PUBLIC_FIREBASE_API_KEY ?? '';

type Role = 'particulier' | 'eleveur' | 'pro';
type Step = 'role' | 'info' | 'docs' | 'account';

const ROLES: { value: Role; label: string; icon: string; desc: string }[] = [
  { value: 'particulier', label: 'Particulier', icon: '🏠', desc: 'Je cherche un compagnon ou je possède des animaux' },
  { value: 'eleveur',     label: 'Éleveur',     icon: '🏡', desc: 'Je suis éleveur certifié et je propose des animaux' },
  { value: 'pro',         label: 'Professionnel', icon: '🩺', desc: 'Vétérinaire, toiletteur, pension…' },
];

const PRO_CATEGORIES: Record<string, string[]> = {
  'Prestataire':         ['Éducateur comportementaliste', 'Promeneur de chiens', 'Pet sitter', 'Toiletteur', 'Photographe animalier'],
  'Pension pour animaux': ['Pension pour animaux'],
  'Santé animal':        ['Vétérinaire', 'Auxiliaire de santé', 'Maréchal-ferrant', 'Spécialiste de santé'],
};

const CAT_PRO_MAP: Record<string, string> = {
  'Vétérinaire':                  'veterinaire',
  'Auxiliaire de santé':          'sante',
  'Maréchal-ferrant':             'marechal_ferrant',
  'Spécialiste de santé':         'sante',
  'Pension pour animaux':         'pension',
  'Toiletteur':                   'toilettage',
  'Promeneur de chiens':          'garde',
  'Pet sitter':                   'garde',
  'Éducateur comportementaliste': 'education',
  'Photographe animalier':        'photographe',
};

const inputCls = 'w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white';
const labelCls = 'block text-sm font-medium text-[#1F2A2E] mb-1';

// ── Autocomplete adresse ───────────────────────────────────────────────────────
function AddressInput({ value, onChange, placeholder }: {
  value: string;
  onChange: (v: string, parts: { rue: string; ville: string; codePostal: string }) => void;
  placeholder: string;
}) {
  const [query, setQuery] = useState(value);
  const [predictions, setPredictions] = useState<google.maps.places.AutocompletePrediction[]>([]);
  const autocompleteRef = useRef<google.maps.places.AutocompleteService | null>(null);
  const placesRef = useRef<google.maps.places.PlacesService | null>(null);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const divRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    try { setOptions({ key: MAPS_KEY, v: 'weekly', language: 'fr' }); } catch {}
    (async () => {
      try {
        const { AutocompleteService } = await importLibrary('places') as google.maps.PlacesLibrary;
        autocompleteRef.current = new AutocompleteService();
        const div = document.createElement('div');
        const { PlacesService } = await importLibrary('places') as google.maps.PlacesLibrary;
        placesRef.current = new PlacesService(div);
      } catch {}
    })();
  }, []);

  function onType(v: string) {
    setQuery(v);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    if (!v.trim() || !autocompleteRef.current) { setPredictions([]); return; }
    debounceRef.current = setTimeout(() => {
      autocompleteRef.current!.getPlacePredictions(
        { input: v, componentRestrictions: { country: 'fr' }, types: ['address'] },
        (res) => setPredictions(res ?? []),
      );
    }, 300);
  }

  function selectPrediction(p: google.maps.places.AutocompletePrediction) {
    setQuery(p.description);
    setPredictions([]);
    placesRef.current?.getDetails({ placeId: p.place_id, fields: ['address_components'] }, (place) => {
      if (!place?.address_components) return;
      const parts = place.address_components;
      const num = parts.find(c => c.types.includes('street_number'))?.long_name ?? '';
      const route = parts.find(c => c.types.includes('route'))?.long_name ?? '';
      const rue = [num, route].filter(Boolean).join(' ');
      const ville = parts.find(c => c.types.includes('locality'))?.long_name
                 ?? parts.find(c => c.types.includes('postal_town'))?.long_name ?? '';
      const codePostal = parts.find(c => c.types.includes('postal_code'))?.long_name ?? '';
      onChange(p.description, { rue, ville, codePostal });
    });
  }

  return (
    <div className="relative" ref={divRef}>
      <input type="text" value={query} onChange={(e) => onType(e.target.value)}
        placeholder={placeholder} className={inputCls} />
      {predictions.length > 0 && (
        <ul className="absolute z-50 left-0 right-0 bg-white border border-gray-200 rounded-xl mt-1 shadow-lg max-h-52 overflow-y-auto">
          {predictions.map((p) => (
            <li key={p.place_id}
              className="px-4 py-2.5 text-sm cursor-pointer hover:bg-[#E8F4F6] text-[#1F2A2E]"
              onMouseDown={() => selectPrediction(p)}>
              {p.description}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

// ── Upload tile ────────────────────────────────────────────────────────────────
function UploadTile({ label, file, onSelect, onRemove, accept = '.pdf,.jpg,.jpeg,.png' }: {
  label: string; file: File | null;
  onSelect: (f: File) => void; onRemove: () => void; accept?: string;
}) {
  const inputRef = useRef<HTMLInputElement>(null);
  return (
    <div>
      <input ref={inputRef} type="file" accept={accept} className="hidden"
        onChange={(e) => { const f = e.target.files?.[0]; if (f) onSelect(f); }} />
      {file ? (
        <div className="flex items-center gap-2 px-3 py-2.5 border border-[#6E9E57] bg-[#6E9E57]/5 rounded-xl text-sm">
          <svg className="w-4 h-4 text-[#6E9E57] shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
          </svg>
          <span className="flex-1 text-[#1F2A2E] truncate">{file.name}</span>
          <button type="button" onClick={onRemove} className="text-red-400 hover:text-red-600 text-xs shrink-0">✕</button>
        </div>
      ) : (
        <button type="button" onClick={() => inputRef.current?.click()}
          className="w-full flex items-center gap-2 px-3 py-2.5 border border-dashed border-gray-300 rounded-xl text-sm text-gray-500 hover:border-[#0C5C6C] hover:text-[#0C5C6C] transition-colors">
          <svg className="w-4 h-4 shrink-0" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-8l-4-4m0 0L8 8m4-4v12" />
          </svg>
          {label}
        </button>
      )}
    </div>
  );
}

// ── Helpers ────────────────────────────────────────────────────────────────────
function normalizeForComparison(s: string): string {
  return s.toUpperCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^A-Z0-9]/g, '');
}

async function uploadToStorage(file: File, path: string): Promise<string> {
  const r = storageRef(storage, path);
  const snap = await uploadBytes(r, file);
  return getDownloadURL(snap.ref);
}

// ── Page principale ────────────────────────────────────────────────────────────
export default function InscriptionPage() {
  const router = useRouter();
  const [step, setStep] = useState<Step>('role');
  const [role, setRole] = useState<Role>('particulier');

  // Step info — communs
  const [firstname, setFirstname] = useState('');
  const [lastname, setLastname] = useState('');
  const [dateOfBirth, setDateOfBirth] = useState('');
  const [phone, setPhone] = useState('');

  // Particulier
  const [rue, setRue] = useState('');
  const [ville, setVille] = useState('');
  const [codePostal, setCodePostal] = useState('');

  // Éleveur / Pro — adresse
  const [nameElevage, setNameElevage] = useState('');
  const [rueElevage, setRueElevage] = useState('');
  const [villeElevage, setVilleElevage] = useState('');
  const [codePostalElevage, setCodePostalElevage] = useState('');

  // Step docs — communs éleveur/pro
  const [siret, setSiret] = useState('');
  const [kbisFile, setKbisFile] = useState<File | null>(null);

  // Step docs — éleveur uniquement
  const [acacedNumero, setAcacedNumero] = useState('');
  const [acacedFile, setAcacedFile] = useState<File | null>(null);

  // Step docs — pro uniquement
  const [categoriePro, setCategoriePro] = useState('');
  const [professionPro, setProfessionPro] = useState('');
  const [ordreVet, setOrdreVet] = useState('');

  // Step account
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [cguAccepted, setCguAccepted] = useState(false);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [siretVerifying, setSiretVerifying] = useState(false);

  const isEleveurOrPro = role === 'eleveur' || role === 'pro';
  const isVet = professionPro === 'Vétérinaire';
  const professions = categoriePro ? PRO_CATEGORIES[categoriePro] ?? [] : [];

  // ── Navigation ──────────────────────────────────────────────────────────────
  function continueToInfo() { setError(''); setStep('info'); }

  function continueFromInfo() {
    if (!firstname.trim() || !lastname.trim()) {
      setError('Veuillez renseigner votre prénom et nom.');
      return;
    }
    setError('');
    setStep(isEleveurOrPro ? 'docs' : 'account');
  }

  async function continueFromDocs() {
    const siretClean = siret.replace(/\s/g, '');
    if (!siretClean || siretClean.length < 9) {
      setError('Le numéro SIRET/SIREN est obligatoire (9 ou 14 chiffres).');
      return;
    }
    // KBIS optionnel — la vérification API SIRET est suffisante ; le Kbis est un plus
    if (role === 'pro') {
      if (!categoriePro || !professionPro) {
        setError('Veuillez sélectionner votre catégorie et profession.');
        return;
      }
      if (isVet && !ordreVet.trim()) {
        setError("Le numéro d'ordre vétérinaire est obligatoire.");
        return;
      }
    }
    setError('');

    // RNA (W + 9 chiffres) — format valide, pas d'API publique de vérification
    if (/^[Ww]\d{9}$/.test(siretClean)) {
      setStep('account');
      return;
    }

    // SIREN (9) ou SIRET (14) — chiffres uniquement
    if (!/^\d{9}(\d{5})?$/.test(siretClean)) {
      setError('Format invalide. Attendu : SIREN (9 chiffres), SIRET (14 chiffres) ou RNA (W + 9 chiffres).');
      return;
    }

    // Vérification API entreprise (gratuite, sans auth)
    setSiretVerifying(true);
    try {
      const res = await fetch(
        `https://recherche-entreprises.api.gouv.fr/search?q=${siretClean}&page=1&per_page=1`
      );
      if (res.ok) {
        const json = await res.json() as {
          results?: {
            siren?: string;
            nom_complet?: string;
            activite_principale?: string;
            siege?: { siret?: string; etat_administratif?: string; activite_principale?: string };
          }[];
          total_results?: number;
        };
        const found = json.results?.[0];
        const matches = found?.siege?.siret === siretClean || found?.siren === siretClean;
        if (!found || !matches) {
          setError('Ce numéro SIRET/SIREN est introuvable. Vérifiez votre saisie.');
          return;
        }
        if (found.siege?.etat_administratif === 'F') {
          setError('Cette entreprise est fermée ou radiée. Contactez le support si nécessaire.');
          return;
        }
        // Vérification nom : comparaison normalisée entre nom déclaré et nom API
        const nomApi = normalizeForComparison(found.nom_complet ?? '');
        const nomDeclare = normalizeForComparison(nameElevage || `${firstname} ${lastname}`);
        if (nomApi && nomDeclare.length >= 4 && !nomApi.includes(nomDeclare.slice(0, 5)) && !nomDeclare.includes(nomApi.slice(0, 5))) {
          setError(`Le nom de votre entreprise ne correspond pas au SIRET renseigné (trouvé : ${found.nom_complet}). Vérifiez votre saisie ou contactez le support : www.petsmatch.com/contact`);
          return;
        }
      }
      // Si l'API est indisponible, on laisse passer (vérification manuelle par l'admin)
    } catch {
      // API indisponible — vérification manuelle par l'admin
    } finally {
      setSiretVerifying(false);
    }

    setStep('account');
  }

  // ── Création du profil Supabase ──────────────────────────────────────────────
  async function createProfile(uid: string, emailAddr: string) {
    const ts = Date.now();
    let kbisUrl = '';
    let acacedDocUrl = '';

    if (kbisFile) {
      kbisUrl = await uploadToStorage(kbisFile, `documentElevage/Siret/${uid}_${ts}_${kbisFile.name}`);
    }
    if (acacedFile) {
      acacedDocUrl = await uploadToStorage(acacedFile, `documentElevage/Acaced/${uid}_${ts}_${acacedFile.name}`);
    }

    const catPro = professionPro ? CAT_PRO_MAP[professionPro] ?? 'autre' : undefined;
    const certifications = isVet && ordreVet.trim()
      ? [{ nom: 'Numéro d\'ordre vétérinaire', organisme: 'Ordre national des vétérinaires', numero: ordreVet.trim() }]
      : undefined;

    const base: Record<string, unknown> = {
      uid,
      email: emailAddr,
      firstname: firstname.trim(),
      lastname: lastname.trim(),
      date_of_birth: dateOfBirth || null,
      phone_number: phone || null,
      cgu_accepted_at: new Date().toISOString(),
      is_elevage: role === 'eleveur',
      is_pro: role === 'pro',
      is_validate: false,
    };

    if (isEleveurOrPro) {
      Object.assign(base, {
        name_elevage: nameElevage || null,
        rue_elevage: rueElevage || null,
        ville_elevage: villeElevage || null,
        code_postal_elevage: codePostalElevage || null,
        siret: siret.trim(),
        kbis_url: kbisUrl || null,
        statut_pro: 'en_attente',
      });
      if (role === 'eleveur') {
        Object.assign(base, {
          acaced: acacedNumero.trim() || null,
          acaced_doc_url: acacedDocUrl || null,
        });
      }
      if (role === 'pro') {
        Object.assign(base, {
          cat_pro: catPro ?? null,
          profession_pro: professionPro || null,
          certifications: certifications ?? null,
        });
      }
    } else {
      Object.assign(base, {
        rue: rue || null,
        ville: ville || null,
        code_postal: codePostal || null,
      });
    }

    await supabase.from('users').upsert(base, { onConflict: 'uid' });
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    if (password.length < 6) { setError('Le mot de passe doit contenir au moins 6 caractères.'); return; }
    if (!cguAccepted) { setError('Vous devez accepter les CGU pour créer un compte.'); return; }
    setLoading(true);
    try {
      const cred = await createUserWithEmailAndPassword(auth, email, password);
      await updateProfile(cred.user, { displayName: `${firstname} ${lastname}`.trim() });
      await createProfile(cred.user.uid, email);
      if (isEleveurOrPro) {
        router.push('/en-attente-validation');
      } else {
        router.push('/');
      }
    } catch (err: unknown) {
      const code = (err as { code?: string }).code;
      if (code === 'auth/email-already-in-use') {
        // Récupération : inscription précédemment interrompue avant la fin
        try {
          const existing = await signInWithEmailAndPassword(auth, email, password);
          await updateProfile(existing.user, { displayName: `${firstname} ${lastname}`.trim() });
          await createProfile(existing.user.uid, email); // upsert idempotent
          if (isEleveurOrPro) router.push('/en-attente-validation');
          else router.push('/');
          return;
        } catch {
          setError('Cet email est déjà utilisé. Connectez-vous depuis la page de connexion, ou réinitialisez votre mot de passe.');
        }
      } else {
        setError('Une erreur est survenue. Veuillez réessayer.');
      }
    } finally {
      setLoading(false);
    }
  }

  async function handleGoogle() {
    setError('');
    setLoading(true);
    try {
      const cred = await signInWithPopup(auth, new GoogleAuthProvider());
      const fn = cred.user.displayName?.split(' ')[0] ?? '';
      const ln = cred.user.displayName?.split(' ').slice(1).join(' ') ?? '';
      setFirstname(fn); setLastname(ln);
      // Google inscription → particulier seulement (les pros/éleveurs doivent passer par le flow complet)
      await supabase.from('users').upsert({
        uid: cred.user.uid,
        email: cred.user.email ?? '',
        firstname: fn,
        lastname: ln,
        is_elevage: false,
        is_pro: false,
        cgu_accepted_at: new Date().toISOString(),
      }, { onConflict: 'uid' });
      router.push('/');
    } catch {
      setError('Connexion Google annulée ou échouée.');
    } finally {
      setLoading(false);
    }
  }

  const stepCount = isEleveurOrPro ? 4 : 3;
  const stepIndex = step === 'role' ? 1 : step === 'info' ? 2 : step === 'docs' ? 3 : stepCount;

  return (
    <div className="min-h-[80vh] flex items-center justify-center px-4 py-12">
      <div className="w-full max-w-md">
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-8">

          <div className="flex flex-col items-center mb-6">
            <Image src="/Banniere_petsmatch.png" alt="PetsMatch" width={280} height={90} className="object-contain mb-4" />
            <p className="text-gray-500 text-sm">Connecter · Prendre soin · Partager</p>
          </div>

          {/* Barre de progression */}
          {step !== 'role' && (
            <div className="flex gap-1 mb-6">
              {Array.from({ length: stepCount }, (_, i) => (
                <div key={i} className={`flex-1 h-1 rounded-full transition-colors ${i < stepIndex ? 'bg-[#0C5C6C]' : 'bg-gray-200'}`} />
              ))}
            </div>
          )}

          {/* ── Étape 1 : rôle ── */}
          {step === 'role' && (
            <>
              <h2 className="text-lg font-bold text-[#1F2A2E] mb-1 text-center">Créer un compte</h2>
              <p className="text-gray-500 text-sm text-center mb-6">Quel est votre profil ?</p>
              <div className="space-y-3 mb-6">
                {ROLES.map((r) => (
                  <button key={r.value} onClick={() => setRole(r.value)}
                    className={`w-full flex items-center gap-4 p-4 rounded-xl border-2 transition-all text-left ${
                      role === r.value ? 'border-[#0C5C6C] bg-[#E8F4F6]' : 'border-gray-200 hover:border-gray-300'
                    }`}>
                    <span className="text-2xl">{r.icon}</span>
                    <div>
                      <p className="font-semibold text-[#1F2A2E] text-sm">{r.label}</p>
                      <p className="text-gray-500 text-xs">{r.desc}</p>
                    </div>
                    {role === r.value && (
                      <span className="ml-auto text-[#0C5C6C]">
                        <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
                          <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                        </svg>
                      </span>
                    )}
                  </button>
                ))}
              </div>
              {isEleveurOrPro && (
                <div className="bg-amber-50 border border-amber-200 rounded-xl p-3 mb-4 text-xs text-amber-700">
                  Votre compte sera activé après vérification de vos documents par notre équipe (48h ouvrées).
                </div>
              )}
              <button onClick={continueToInfo}
                className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold py-3 rounded-xl transition-colors">
                Continuer
              </button>
            </>
          )}

          {/* ── Étape 2 : informations personnelles ── */}
          {step === 'info' && (
            <>
              <div className="flex items-center gap-2 mb-5">
                <button onClick={() => setStep('role')} className="text-gray-400 hover:text-gray-600">
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
                  </svg>
                </button>
                <h2 className="text-base font-bold text-[#1F2A2E]">
                  Vos informations · {ROLES.find((r) => r.value === role)?.label}
                </h2>
              </div>

              <div className="space-y-4">
                <div className="flex gap-3">
                  <div className="flex-1">
                    <label className={labelCls}>Prénom *</label>
                    <input type="text" value={firstname} onChange={(e) => setFirstname(e.target.value)}
                      placeholder="Jean" className={inputCls} />
                  </div>
                  <div className="flex-1">
                    <label className={labelCls}>Nom *</label>
                    <input type="text" value={lastname} onChange={(e) => setLastname(e.target.value)}
                      placeholder="Dupont" className={inputCls} />
                  </div>
                </div>
                <div>
                  <label className={labelCls}>Date de naissance</label>
                  <input type="date" value={dateOfBirth} onChange={(e) => setDateOfBirth(e.target.value)} className={inputCls} />
                </div>
                <div>
                  <label className={labelCls}>Téléphone</label>
                  <input type="tel" value={phone} onChange={(e) => setPhone(e.target.value)}
                    placeholder="+33 6 00 00 00 00" className={inputCls} />
                </div>

                {!isEleveurOrPro && (
                  <>
                    <div>
                      <label className={labelCls}>Adresse</label>
                      <AddressInput value={rue} placeholder="Rechercher une adresse…"
                        onChange={(_, parts) => { setRue(parts.rue); setVille(parts.ville); setCodePostal(parts.codePostal); }} />
                    </div>
                    <div className="flex gap-3">
                      <div className="w-28">
                        <label className={labelCls}>Code postal</label>
                        <input type="text" value={codePostal} onChange={(e) => setCodePostal(e.target.value)}
                          placeholder="75001" className={inputCls} />
                      </div>
                      <div className="flex-1">
                        <label className={labelCls}>Ville</label>
                        <input type="text" value={ville} onChange={(e) => setVille(e.target.value)}
                          placeholder="Paris" className={inputCls} />
                      </div>
                    </div>
                  </>
                )}

                {isEleveurOrPro && (
                  <>
                    <div>
                      <label className={labelCls}>Nom de l&apos;élevage / entreprise</label>
                      <input type="text" value={nameElevage} onChange={(e) => setNameElevage(e.target.value)}
                        placeholder="Élevage des Roches" className={inputCls} />
                    </div>
                    <div>
                      <label className={labelCls}>Adresse de l&apos;élevage / structure</label>
                      <AddressInput value={rueElevage} placeholder="Rechercher une adresse…"
                        onChange={(_, parts) => { setRueElevage(parts.rue); setVilleElevage(parts.ville); setCodePostalElevage(parts.codePostal); }} />
                    </div>
                    <div className="flex gap-3">
                      <div className="w-28">
                        <label className={labelCls}>Code postal</label>
                        <input type="text" value={codePostalElevage} onChange={(e) => setCodePostalElevage(e.target.value)}
                          placeholder="75001" className={inputCls} />
                      </div>
                      <div className="flex-1">
                        <label className={labelCls}>Ville</label>
                        <input type="text" value={villeElevage} onChange={(e) => setVilleElevage(e.target.value)}
                          placeholder="Paris" className={inputCls} />
                      </div>
                    </div>
                  </>
                )}

                {error && <p className="text-red-500 text-sm">{error}</p>}
                <button onClick={continueFromInfo}
                  className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold py-3 rounded-xl transition-colors">
                  Continuer
                </button>
              </div>
            </>
          )}

          {/* ── Étape 3 : documents (éleveur / pro uniquement) ── */}
          {step === 'docs' && (
            <>
              <div className="flex items-center gap-2 mb-5">
                <button onClick={() => setStep('info')} className="text-gray-400 hover:text-gray-600">
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
                  </svg>
                </button>
                <h2 className="text-base font-bold text-[#1F2A2E]">Documents · {ROLES.find((r) => r.value === role)?.label}</h2>
              </div>

              <div className="bg-blue-50 border border-blue-200 rounded-xl p-3 mb-5 text-xs text-blue-700">
                Ces documents sont vérifiés par notre équipe avant l&apos;activation de votre compte.
                Formats acceptés : PDF, JPG, PNG.
              </div>

              <div className="space-y-5">
                {/* SIRET */}
                <div>
                  <label className={labelCls}>Numéro SIRET / SIREN *</label>
                  <input type="text" value={siret} onChange={(e) => setSiret(e.target.value)}
                    placeholder="12345678900012" className={inputCls} maxLength={17} />
                </div>
                <div>
                  <label className={labelCls}>
                    Justificatif SIRET / Kbis
                    <span className="text-xs text-gray-400 font-normal ml-1">(optionnel — renforce la vérification)</span>
                  </label>
                  <UploadTile label="Déposer le Kbis ou extrait SIRET"
                    file={kbisFile} onSelect={setKbisFile} onRemove={() => setKbisFile(null)} />
                </div>

                {/* ACACED — éleveur */}
                {role === 'eleveur' && (
                  <>
                    <div>
                      <label className={labelCls}>
                        Numéro ACACED
                        <span className="text-xs text-gray-400 font-normal ml-1">(obligatoire pour chiens/chats)</span>
                      </label>
                      <input type="text" value={acacedNumero} onChange={(e) => setAcacedNumero(e.target.value)}
                        placeholder="2022/9fd5-fd12" className={inputCls} />
                    </div>
                    <div>
                      <label className={labelCls}>
                        Document ACACED
                        <span className="text-xs text-gray-400 font-normal ml-1">(optionnel maintenant, requis avant validation)</span>
                      </label>
                      <UploadTile label="Déposer le certificat ACACED"
                        file={acacedFile} onSelect={setAcacedFile} onRemove={() => setAcacedFile(null)} />
                    </div>
                  </>
                )}

                {/* Catégorie / Profession — pro */}
                {role === 'pro' && (
                  <>
                    <div>
                      <label className={labelCls}>Catégorie professionnelle *</label>
                      <select value={categoriePro}
                        onChange={(e) => { setCategoriePro(e.target.value); setProfessionPro(''); }}
                        className={inputCls}>
                        <option value="">Sélectionner…</option>
                        {Object.keys(PRO_CATEGORIES).map((c) => (
                          <option key={c} value={c}>{c}</option>
                        ))}
                      </select>
                    </div>
                    {categoriePro && (
                      <div>
                        <label className={labelCls}>Profession *</label>
                        <select value={professionPro} onChange={(e) => setProfessionPro(e.target.value)}
                          className={inputCls}>
                          <option value="">Sélectionner…</option>
                          {professions.map((p) => (
                            <option key={p} value={p}>{p}</option>
                          ))}
                        </select>
                      </div>
                    )}
                    {isVet && (
                      <div>
                        <label className={labelCls}>Numéro d&apos;ordre vétérinaire *</label>
                        <input type="text" value={ordreVet} onChange={(e) => setOrdreVet(e.target.value)}
                          placeholder="XXXXX" className={inputCls} />
                      </div>
                    )}
                  </>
                )}

                {error && <p className="text-red-500 text-sm">{error}</p>}
                <button onClick={continueFromDocs} disabled={siretVerifying}
                  className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-semibold py-3 rounded-xl transition-colors">
                  {siretVerifying ? 'Vérification SIRET…' : 'Continuer'}
                </button>
              </div>
            </>
          )}

          {/* ── Étape 4 : compte ── */}
          {step === 'account' && (
            <>
              <div className="flex items-center gap-2 mb-5">
                <button onClick={() => setStep(isEleveurOrPro ? 'docs' : 'info')} className="text-gray-400 hover:text-gray-600">
                  <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
                  </svg>
                </button>
                <h2 className="text-base font-bold text-[#1F2A2E]">Connexion · {ROLES.find((r) => r.value === role)?.label}</h2>
              </div>

              <form onSubmit={handleSubmit} className="space-y-4">
                <div>
                  <label className={labelCls}>Email *</label>
                  <input type="email" value={email} onChange={(e) => setEmail(e.target.value)}
                    required placeholder="votre@email.com" className={inputCls} />
                </div>
                <div>
                  <label className={labelCls}>Mot de passe *</label>
                  <input type="password" value={password} onChange={(e) => setPassword(e.target.value)}
                    required placeholder="6 caractères minimum" className={inputCls} />
                </div>

                <label className="flex items-start gap-3 cursor-pointer select-none">
                  <input type="checkbox" checked={cguAccepted} onChange={(e) => setCguAccepted(e.target.checked)}
                    className="mt-0.5 w-4 h-4 accent-[#0C5C6C] shrink-0" />
                  <span className="text-xs text-gray-600 leading-relaxed">
                    J&apos;ai lu et j&apos;accepte les{' '}
                    <Link href="/cgu" target="_blank" className="text-[#0C5C6C] underline">CGU</Link>{' '}
                    et la{' '}
                    <Link href="/confidentialite" target="_blank" className="text-[#0C5C6C] underline">Politique de confidentialité</Link>{' '}
                    de PetsMatch. *
                  </span>
                </label>

                {isEleveurOrPro && (
                  <div className="bg-amber-50 border border-amber-200 rounded-xl p-3 text-xs text-amber-700">
                    Votre compte sera actif après validation de vos documents par notre équipe (48h ouvrées).
                  </div>
                )}

                {error && <p className="text-red-500 text-sm">{error}</p>}

                <button type="submit" disabled={loading || !cguAccepted}
                  className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-semibold py-3 rounded-xl transition-colors">
                  {loading ? 'Création en cours…' : 'Créer mon compte'}
                </button>
              </form>

              {!isEleveurOrPro && (
                <>
                  <div className="relative my-5">
                    <div className="absolute inset-0 flex items-center"><div className="w-full border-t border-gray-200" /></div>
                    <div className="relative flex justify-center"><span className="bg-white px-3 text-xs text-gray-400">ou</span></div>
                  </div>
                  <button onClick={handleGoogle} disabled={loading}
                    className="w-full flex items-center justify-center gap-3 border border-gray-200 rounded-xl py-3 text-sm font-medium text-gray-700 hover:bg-gray-50 transition-colors disabled:opacity-60">
                    <svg className="w-5 h-5" viewBox="0 0 24 24">
                      <path fill="#4285F4" d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" />
                      <path fill="#34A853" d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" />
                      <path fill="#FBBC05" d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" />
                      <path fill="#EA4335" d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" />
                    </svg>
                    Continuer avec Google
                  </button>
                </>
              )}
            </>
          )}

          <p className="text-center text-sm text-gray-500 mt-6">
            Déjà un compte ?{' '}
            <Link href="/connexion" className="text-[#0C5C6C] font-semibold hover:underline">Se connecter</Link>
          </p>
        </div>
      </div>
    </div>
  );
}
