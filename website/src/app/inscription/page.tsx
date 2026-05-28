'use client';

import { useState, useRef, useEffect } from 'react';
import Image from 'next/image';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { createUserWithEmailAndPassword, updateProfile, GoogleAuthProvider, signInWithPopup } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';
import { setOptions, importLibrary } from '@googlemaps/js-api-loader';

const MAPS_KEY = process.env.NEXT_PUBLIC_FIREBASE_API_KEY ?? '';

type Role = 'particulier' | 'eleveur' | 'pro';
type Step = 'role' | 'info' | 'account';

const ROLES: { value: Role; label: string; icon: string; desc: string }[] = [
  { value: 'particulier', label: 'Particulier', icon: '🏠', desc: 'Je cherche un compagnon ou je possède des animaux' },
  { value: 'eleveur', label: 'Éleveur', icon: '🏡', desc: 'Je suis éleveur et je propose des animaux' },
  { value: 'pro', label: 'Professionnel', icon: '🩺', desc: 'Vétérinaire, toiletteur, pension…' },
];

const inputCls = 'w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white';
const labelCls = 'block text-sm font-medium text-[#1F2A2E] mb-1';

// ── Composant autocomplete adresse ────────────────────────────────────────────
function AddressInput({
  value, onChange, placeholder,
}: { value: string; onChange: (v: string, parts: { rue: string; ville: string; codePostal: string }) => void; placeholder: string }) {
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
      let rue = ''; let ville = ''; let cp = '';
      const parts = place.address_components;
      const num = parts.find(c => c.types.includes('street_number'))?.long_name ?? '';
      const route = parts.find(c => c.types.includes('route'))?.long_name ?? '';
      rue = [num, route].filter(Boolean).join(' ');
      ville = parts.find(c => c.types.includes('locality'))?.long_name
           ?? parts.find(c => c.types.includes('postal_town'))?.long_name ?? '';
      cp = parts.find(c => c.types.includes('postal_code'))?.long_name ?? '';
      onChange(p.description, { rue, ville, codePostal: cp });
    });
  }

  return (
    <div className="relative" ref={divRef}>
      <input
        type="text"
        value={query}
        onChange={(e) => onType(e.target.value)}
        placeholder={placeholder}
        className={inputCls}
      />
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

  // Éleveur / Pro
  const [nameElevage, setNameElevage] = useState('');
  const [rueElevage, setRueElevage] = useState('');
  const [villeElevage, setVilleElevage] = useState('');
  const [codePostalElevage, setCodePostalElevage] = useState('');

  // Step account
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const isEleveurOrPro = role === 'eleveur' || role === 'pro';

  function buildProfile() {
    const base = {
      firstname, lastname,
      date_of_birth: dateOfBirth || null,
      phone_number: phone || null,
    };
    if (isEleveurOrPro) {
      return {
        ...base,
        name_elevage: nameElevage || null,
        rue_elevage: rueElevage || null,
        ville_elevage: villeElevage || null,
        code_postal_elevage: codePostalElevage || null,
      };
    }
    return {
      ...base,
      rue: rue || null,
      ville: ville || null,
      code_postal: codePostal || null,
    };
  }

  async function createProfile(uid: string, emailAddr: string) {
    await supabase.from('users').upsert({
      uid,
      email: emailAddr,
      is_elevage: role === 'eleveur',
      is_pro: role === 'pro',
      ...buildProfile(),
    }, { onConflict: 'uid' });
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    if (password.length < 6) { setError('Le mot de passe doit contenir au moins 6 caractères.'); return; }
    setLoading(true);
    try {
      const cred = await createUserWithEmailAndPassword(auth, email, password);
      await updateProfile(cred.user, { displayName: `${firstname} ${lastname}`.trim() });
      await createProfile(cred.user.uid, email);
      router.push('/');
    } catch (err: unknown) {
      const code = (err as { code?: string }).code;
      if (code === 'auth/email-already-in-use') setError('Cet email est déjà utilisé.');
      else setError('Une erreur est survenue. Veuillez réessayer.');
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
      await createProfile(cred.user.uid, cred.user.email ?? '');
      router.push('/');
    } catch {
      setError('Connexion Google annulée ou échouée.');
    } finally {
      setLoading(false);
    }
  }

  // Validation step info
  function continueToAccount() {
    if (!firstname.trim() || !lastname.trim()) {
      setError('Veuillez renseigner votre prénom et nom.');
      return;
    }
    setError('');
    setStep('account');
  }

  return (
    <div className="min-h-[80vh] flex items-center justify-center px-4 py-12">
      <div className="w-full max-w-md">
        <div className="bg-white rounded-2xl shadow-sm border border-gray-100 p-8">
          <div className="flex flex-col items-center mb-8">
            <Image src="/Banniere_petsmatch.png" alt="PetsMatch" width={280} height={90} className="object-contain mb-4" />
            <p className="text-gray-500 text-sm">Connecter · Prendre soin · Partager</p>
          </div>

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
              <button onClick={() => setStep('info')}
                className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold py-3 rounded-xl transition-colors">
                Continuer
              </button>
            </>
          )}

          {/* ── Étape 2 : informations personnelles ── */}
          {step === 'info' && (
            <>
              <div className="flex items-center gap-2 mb-6">
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
                      required placeholder="Jean" className={inputCls} />
                  </div>
                  <div className="flex-1">
                    <label className={labelCls}>Nom *</label>
                    <input type="text" value={lastname} onChange={(e) => setLastname(e.target.value)}
                      required placeholder="Dupont" className={inputCls} />
                  </div>
                </div>

                <div>
                  <label className={labelCls}>Date de naissance</label>
                  <input type="date" value={dateOfBirth} onChange={(e) => setDateOfBirth(e.target.value)}
                    className={inputCls} />
                </div>

                <div>
                  <label className={labelCls}>Téléphone</label>
                  <input type="tel" value={phone} onChange={(e) => setPhone(e.target.value)}
                    placeholder="+33 6 00 00 00 00" className={inputCls} />
                </div>

                {/* Particulier : adresse personnelle */}
                {!isEleveurOrPro && (
                  <>
                    <div>
                      <label className={labelCls}>Adresse</label>
                      <AddressInput
                        value={rue}
                        placeholder="Rechercher une adresse…"
                        onChange={(_, parts) => {
                          setRue(parts.rue);
                          setVille(parts.ville);
                          setCodePostal(parts.codePostal);
                        }}
                      />
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

                {/* Éleveur / Pro : infos élevage */}
                {isEleveurOrPro && (
                  <>
                    <div>
                      <label className={labelCls}>Nom de l&apos;élevage / entreprise</label>
                      <input type="text" value={nameElevage} onChange={(e) => setNameElevage(e.target.value)}
                        placeholder="Élevage des Roches" className={inputCls} />
                    </div>
                    <div>
                      <label className={labelCls}>Adresse de l&apos;élevage</label>
                      <AddressInput
                        value={rueElevage}
                        placeholder="Rechercher une adresse…"
                        onChange={(_, parts) => {
                          setRueElevage(parts.rue);
                          setVilleElevage(parts.ville);
                          setCodePostalElevage(parts.codePostal);
                        }}
                      />
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

                <button onClick={continueToAccount}
                  className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-semibold py-3 rounded-xl transition-colors">
                  Continuer
                </button>
              </div>
            </>
          )}

          {/* ── Étape 3 : compte ── */}
          {step === 'account' && (
            <>
              <div className="flex items-center gap-2 mb-6">
                <button onClick={() => setStep('info')} className="text-gray-400 hover:text-gray-600">
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

                {error && <p className="text-red-500 text-sm">{error}</p>}

                <button type="submit" disabled={loading}
                  className="w-full bg-[#0C5C6C] hover:bg-[#094F5D] disabled:opacity-60 text-white font-semibold py-3 rounded-xl transition-colors">
                  {loading ? 'Création…' : 'Créer mon compte'}
                </button>
              </form>

              <div className="relative my-5">
                <div className="absolute inset-0 flex items-center">
                  <div className="w-full border-t border-gray-200" />
                </div>
                <div className="relative flex justify-center">
                  <span className="bg-white px-3 text-xs text-gray-400">ou</span>
                </div>
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

          <p className="text-center text-sm text-gray-500 mt-6">
            Déjà un compte ?{' '}
            <Link href="/connexion" className="text-[#0C5C6C] font-semibold hover:underline">
              Se connecter
            </Link>
          </p>
        </div>
      </div>
    </div>
  );
}
