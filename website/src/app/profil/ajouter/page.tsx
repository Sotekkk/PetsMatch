'use client';

import { useState, useEffect, useRef } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/lib/auth-context';
import { supabase } from '@/lib/supabase';
import { setOptions, importLibrary } from '@googlemaps/js-api-loader';
import { notifyProfilePendingValidation } from '@/lib/notifications';

// ── Types ─────────────────────────────────────────────────────────────────────

const PROFILE_TYPES = [
  { type: 'particulier',      emoji: '👤', label: 'Particulier',      desc: 'Propriétaire d\'animaux de compagnie' },
  { type: 'eleveur',          emoji: '🐾', label: 'Éleveur',          desc: 'Élevage professionnel, reproduction' },
  { type: 'association',      emoji: '🤝', label: 'Association',      desc: 'Refuge, SPA, association de protection animale' },
  { type: 'veterinaire',      emoji: '🏥', label: 'Vétérinaire',      desc: 'Clinique vétérinaire, soins médicaux' },
  { type: 'sante',            emoji: '💆', label: 'Santé animale',     desc: 'Ostéo, kiné, acupuncteur, naturopathe…' },
  { type: 'education',        emoji: '🧠', label: 'Éducation',        desc: 'Éducateur, comportementaliste, dresseur' },
  { type: 'garde',            emoji: '🏠', label: 'Garde',            desc: 'Pet sitter à domicile, promeneur' },
  { type: 'pension',          emoji: '🏨', label: 'Pension',          desc: 'Hébergement temporaire, pensionnat' },
  { type: 'toilettage',       emoji: '✂️', label: 'Toilettage',       desc: 'Salon de toilettage, bain-brush' },
  { type: 'photographe',      emoji: '📷', label: 'Photographe',      desc: 'Photographe animalier spécialisé' },
  { type: 'marechal_ferrant', emoji: '🔨', label: 'Maréchal-ferrant', desc: 'Soins des sabots, ferrure équine' },
];

const SUB_PROFESSIONS: Record<string, string[]> = {
  sante:            ['Ostéopathe', 'Chiropracteur', 'Kinésithérapeute', 'Naturopathe', 'Acupuncteur', 'Maréchal-ferrant'],
  education:        ['Éducateur canin', 'Comportementaliste', 'Dresseur'],
  garde:            ['Pet sitter', 'Promeneur de chiens'],
  photographe:      ['Photographe animalier', 'Photographe équin', 'Photographe de studio'],
  marechal_ferrant: ['Maréchal-ferrant traditionnel', 'Parage naturel'],
};

const ESPECES = ['Chien', 'Chat', 'Lapin', 'Oiseau', 'Reptile', 'Rongeur', 'Cheval', 'NAC'];

const PRO_TYPES = new Set(['veterinaire', 'sante', 'education', 'garde', 'pension', 'toilettage', 'photographe', 'marechal_ferrant']);
const HAS_SIRET  = new Set(['veterinaire', 'sante', 'education', 'pension', 'toilettage', 'photographe', 'marechal_ferrant']);
const HAS_RAYON  = new Set(['veterinaire', 'sante', 'education', 'garde', 'toilettage', 'photographe', 'marechal_ferrant']);

const ACTIVE_PROFILE_KEY = 'petsMatch_activeProfileId';

// ── Page ──────────────────────────────────────────────────────────────────────

export default function AjouterProfilPage() {
  const { user, userData } = useAuth();
  const router = useRouter();
  const [step, setStep] = useState<'type' | 'form'>('type');
  const [selectedType, setSelectedType] = useState('');

  if (!user) {
    return (
      <div className="min-h-screen flex items-center justify-center">
        <p className="text-gray-500">Vous devez être connecté pour ajouter un profil.</p>
      </div>
    );
  }

  if (step === 'type') {
    return (
      <div className="min-h-screen bg-[#F8F8F8]">
        <div className="max-w-2xl mx-auto px-4 py-8">
          {/* Back */}
          <button onClick={() => router.back()} className="flex items-center gap-2 text-[#0C5C6C] mb-6 hover:underline text-sm font-medium">
            ← Retour
          </button>

          <h1 className="text-2xl font-bold text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
            Ajouter un profil
          </h1>
          <p className="text-gray-500 text-sm mb-6">
            Chaque profil a sa propre adresse, ses coordonnées et ses informations professionnelles.
          </p>

          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">
            {PROFILE_TYPES.map((t) => (
              <button
                key={t.type}
                onClick={() => { setSelectedType(t.type); setStep('form'); }}
                className={`bg-white rounded-2xl p-4 text-left hover:shadow-md transition-shadow border hover:border-[#6E9E57] ${
                  t.type === 'association' ? 'border-teal-200 bg-teal-50/30' : 'border-gray-100'
                }`}>
                <div className="text-3xl mb-2">{t.emoji}</div>
                <p className="font-bold text-sm text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>{t.label}</p>
                <p className="text-xs text-gray-400 mt-1 leading-snug">{t.desc}</p>
              </button>
            ))}
          </div>
        </div>
      </div>
    );
  }

  const typeInfo = PROFILE_TYPES.find(t => t.type === selectedType)!;

  if (selectedType === 'association') {
    return (
      <AssociationForm
        uid={user.uid}
        onBack={() => setStep('type')}
        onSaved={(id) => {
          localStorage.setItem(ACTIVE_PROFILE_KEY, id);
          router.push('/profil');
        }}
      />
    );
  }

  return (
    <ProfileForm
      typeInfo={typeInfo}
      uid={user.uid}
      userFirstname={userData?.firstname ?? ''}
      userLastname={userData?.lastname ?? ''}
      onBack={() => setStep('type')}
      onSaved={(newProfileId) => {
        localStorage.setItem(ACTIVE_PROFILE_KEY, newProfileId);
        router.push('/');
      }}
    />
  );
}

// ── Formulaire ────────────────────────────────────────────────────────────────

function ProfileForm({ typeInfo, uid, userFirstname, userLastname, onBack, onSaved }: {
  typeInfo: { type: string; emoji: string; label: string };
  uid: string;
  userFirstname: string;
  userLastname: string;
  onBack: () => void;
  onSaved: (id: string) => void;
}) {
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  // Champs communs
  const [profileLabel, setProfileLabel] = useState(() => defaultLabel(typeInfo.type, userFirstname, userLastname));
  const [nomCabinet, setNomCabinet] = useState('');
  const [phone, setPhone] = useState('');
  const [description, setDescription] = useState('');
  const [siret, setSiret] = useState('');
  const [siteWeb, setSiteWeb] = useState('');
  const [subProfession, setSubProfession] = useState('');
  const [rayon, setRayon] = useState(20);
  const [especesSet, setEspecesSet] = useState<Set<string>>(new Set());
  const [especesEleveesSet, setEspecesEleveesSet] = useState<Set<string>>(new Set());

  // Champs adresse
  const [rue, setRue] = useState('');
  const [ville, setVille] = useState('');
  const [cp, setCp] = useState('');
  const [pays, setPays] = useState('France');
  const [lat, setLat] = useState<number | null>(null);
  const [lng, setLng] = useState<number | null>(null);

  // Éleveur
  const [numElevage, setNumElevage] = useState('');
  const [acaced, setAcaced] = useState('');
  const [acacedDateObtention, setAcacedDateObtention] = useState('');
  const [siretDocFile, setSiretDocFile] = useState<File | null>(null);
  const [acacedDocFile, setAcacedDocFile] = useState<File | null>(null);
  const siretDocRef = useRef<HTMLInputElement>(null);
  const acacedDocRef = useRef<HTMLInputElement>(null);

  // Maps autocomplete
  const addressInputRef = useRef<HTMLInputElement>(null);
  const [addressSearch, setAddressSearch] = useState('');
  const [predictions, setPredictions] = useState<google.maps.places.AutocompletePrediction[]>([]);
  const [autocompleteService, setAutocompleteService] = useState<google.maps.places.AutocompleteService | null>(null);
  const [placesService, setPlacesService] = useState<google.maps.places.PlacesService | null>(null);
  const debounceRef = useRef<NodeJS.Timeout | null>(null);
  const mapDivRef = useRef<HTMLDivElement>(null);

  const isProType   = PRO_TYPES.has(typeInfo.type);
  const isEleveur   = typeInfo.type === 'eleveur';
  const isParticulier = typeInfo.type === 'particulier';
  const hasSiret    = HAS_SIRET.has(typeInfo.type);
  const hasRayon    = HAS_RAYON.has(typeInfo.type);
  const subOptions  = SUB_PROFESSIONS[typeInfo.type] ?? [];

  // Initialiser Google Maps
  useEffect(() => {
    const apiKey = process.env.NEXT_PUBLIC_GOOGLE_MAPS_KEY ?? '';
    setOptions({ key: apiKey, v: 'weekly', language: 'fr' });
    importLibrary('places').then((places) => {
      const lib = places as typeof google.maps.places;
      setAutocompleteService(new lib.AutocompleteService());
      if (mapDivRef.current) {
        setPlacesService(new lib.PlacesService(mapDivRef.current));
      }
    }).catch(() => {/* noop */});
  }, []);

  function onAddressChange(val: string) {
    setAddressSearch(val);
    if (debounceRef.current) clearTimeout(debounceRef.current);
    if (val.length < 3) { setPredictions([]); return; }
    debounceRef.current = setTimeout(() => {
      autocompleteService?.getPlacePredictions(
        { input: val, componentRestrictions: { country: 'fr' } },
        (res) => setPredictions(res ?? []),
      );
    }, 400);
  }

  function selectPrediction(p: google.maps.places.AutocompletePrediction) {
    setPredictions([]);
    setAddressSearch(p.description);
    if (!placesService) return;
    placesService.getDetails({ placeId: p.place_id, fields: ['address_components', 'geometry'] }, (result) => {
      if (!result) return;
      let num = '', route = '', cpVal = '', villeVal = '', paysVal = 'France';
      for (const c of result.address_components ?? []) {
        if (c.types.includes('street_number')) num = c.long_name;
        if (c.types.includes('route')) route = c.long_name;
        if (c.types.includes('postal_code')) cpVal = c.long_name;
        if (c.types.includes('locality')) villeVal = c.long_name;
        else if (c.types.includes('administrative_area_level_2') && !villeVal) villeVal = c.long_name;
        if (c.types.includes('country')) paysVal = c.long_name;
      }
      setRue([num, route].filter(Boolean).join(' '));
      setCp(cpVal);
      setVille(villeVal);
      setPays(paysVal);
      const loc = result.geometry?.location;
      if (loc) { setLat(loc.lat()); setLng(loc.lng()); }
    });
  }

  async function handleSave() {
    const errs: string[] = [];
    if (!profileLabel.trim()) errs.push('Libellé du profil');
    if (!ville.trim()) errs.push('Ville');
    if (isEleveur) {
      if (!nomCabinet.trim()) errs.push("Nom de l'élevage");
      if (!phone.trim()) errs.push('Téléphone');
      if (!rue.trim()) errs.push('Rue');
      if (!cp.trim()) errs.push('Code postal');
      if (!pays.trim()) errs.push('Pays');
      if (!siret.trim()) errs.push('SIRET');
      if (!siretDocFile) errs.push('Justificatif SIRET (KBIS)');
      if (!acaced.trim()) errs.push('N° ACACED');
      if (!acacedDateObtention) errs.push("Date d'obtention ACACED");
      if (!acacedDocFile) errs.push('Certificat ACACED');
    }
    if (errs.length > 0) { setError(`Champs obligatoires manquants : ${errs.join(', ')}`); return; }
    setSaving(true);
    setError('');
    try {
      const data: Record<string, unknown> = {
        uid,
        profile_type:  typeInfo.type,
        profile_label: profileLabel.trim(),
        phone:         phone.trim(),
        adresse:       addressSearch.trim(),
        rue:           rue.trim(),
        ville:         ville.trim(),
        code_postal:   cp.trim(),
        pays:          pays.trim() || 'France',
        description:   description.trim(),
        site_web:      siteWeb.trim(),
      };
      if (lat !== null) data.latitude  = lat;
      if (lng !== null) data.longitude = lng;

      if (isParticulier) {
        data.firstname = userFirstname;
        data.lastname  = userLastname;
      }
      if (isEleveur) {
        data.name_elevage     = nomCabinet.trim();
        data.numero_elevage   = numElevage.trim();
        data.is_elevage       = true;
        data.siret            = siret.trim();
        data.acaced_numero    = acaced.trim();
        data.acaced_date_obtention = acacedDateObtention;
        data.especes_elevees  = Array.from(especesEleveesSet);

        // Upload KBIS
        if (siretDocFile) {
          const ext = siretDocFile.name.split('.').pop() ?? 'jpg';
          const path = `documents/${uid}/kbis.${ext}`;
          const { data: up } = await supabase.storage.from('petsmatch').upload(path, siretDocFile, { upsert: true });
          if (up) {
            const { data: pub } = supabase.storage.from('petsmatch').getPublicUrl(path);
            data.kbis_url = pub.publicUrl;
          }
        }
        // Upload ACACED
        if (acacedDocFile) {
          const ext = acacedDocFile.name.split('.').pop() ?? 'jpg';
          const path = `documents/${uid}/acaced.${ext}`;
          const { data: up } = await supabase.storage.from('petsmatch').upload(path, acacedDocFile, { upsert: true });
          if (up) {
            const { data: pub } = supabase.storage.from('petsmatch').getPublicUrl(path);
            data.acaced_doc_url = pub.publicUrl;
          }
        }
      }
      if (isProType) {
        data.cat_pro           = typeInfo.type;
        data.name_elevage      = nomCabinet.trim();
        data.profession_pro    = subProfession || typeInfo.label;
        data.siret             = siret.trim();
        data.rayon_intervention = rayon;
        data.especes_acceptees = Array.from(especesSet);
      }

      // Vérifie si le profil existe déjà (pour ne pas remettre en_attente lors d'une mise à jour)
      const { data: existing } = await supabase
        .from('user_profiles')
        .select('id')
        .eq('uid', uid)
        .eq('profile_type', typeInfo.type)
        .maybeSingle();
      const isNew = !existing;
      if (isNew && (isProType || isEleveur)) {
        data.statut_pro = 'en_attente';
      }

      const { data: rows, error: err } = await supabase
        .from('user_profiles')
        .upsert(data, { onConflict: 'uid,profile_type' })
        .select('id');

      if (err) throw err;

      // Sync champs éleveur dans la table users (SIRET, ACACED, docs)
      if (isEleveur) {
        const usersPayload: Record<string, unknown> = {
          uid,
          siret: siret.trim(),
          acaced: acaced.trim(),
          acaced_date_obtention: acacedDateObtention,
        };
        if (data.kbis_url) usersPayload.kbis_url = data.kbis_url;
        if (data.acaced_doc_url) usersPayload.acaced_doc_url = data.acaced_doc_url;
        await supabase.from('users').upsert(usersPayload, { onConflict: 'uid' });
      }

      const id = (rows as { id: string }[])[0]?.id ?? '';
      if (isNew && (isProType || isEleveur)) {
        await notifyProfilePendingValidation(uid, typeInfo.type);
      }
      onSaved(id);
    } catch (e: unknown) {
      setError((e as Error).message ?? 'Erreur lors de la sauvegarde.');
      setSaving(false);
    }
  }

  function toggleEspece(e: string, set: Set<string>, setter: (s: Set<string>) => void) {
    const next = new Set(set);
    if (next.has(e)) next.delete(e); else next.add(e);
    setter(next);
  }

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      {/* Div invisible requis par PlacesService */}
      <div ref={mapDivRef} style={{ display: 'none' }} />

      <div className="max-w-xl mx-auto px-4 py-8">
        <button onClick={onBack} className="flex items-center gap-2 text-[#0C5C6C] mb-6 hover:underline text-sm font-medium">
          ← {typeInfo.emoji} {typeInfo.label}
        </button>

        <h1 className="text-2xl font-bold text-[#1F2A2E] mb-6" style={{ fontFamily: 'Galey, sans-serif' }}>
          Créer le profil {typeInfo.label}
        </h1>

        {error && (
          <div className="mb-4 bg-red-50 border border-red-200 text-red-600 rounded-xl px-4 py-3 text-sm">
            {error}
          </div>
        )}

        <div className="space-y-5">
          {/* Libellé */}
          <Field label="Nom du profil" required>
            <input value={profileLabel} onChange={e => setProfileLabel(e.target.value)}
              className="w-full input-field" placeholder="Ex : Mon cabinet vétérinaire" />
          </Field>

          {/* Nom cabinet / élevage */}
          {!isParticulier && (
            <Field label={isEleveur ? "Nom de l'élevage" : "Nom du cabinet / établissement"}>
              <input value={nomCabinet} onChange={e => setNomCabinet(e.target.value)}
                className="w-full input-field" placeholder={isEleveur ? 'Ex : Élevage du Moulin' : 'Ex : Cabinet Dupont'} />
            </Field>
          )}

          {/* Sous-profession */}
          {subOptions.length > 0 && (
            <Field label="Profession">
              <select value={subProfession} onChange={e => setSubProfession(e.target.value)} className="w-full input-field">
                <option value="">Choisir…</option>
                {subOptions.map(s => <option key={s} value={s}>{s}</option>)}
              </select>
            </Field>
          )}

          {/* Adresse */}
          <div>
            <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-2">Adresse professionnelle</p>
            <div className="relative mb-2">
              <input
                ref={addressInputRef}
                value={addressSearch}
                onChange={e => onAddressChange(e.target.value)}
                className="w-full input-field pr-10"
                placeholder="Rechercher une adresse…"
              />
              <span className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400">🔍</span>
              {predictions.length > 0 && (
                <div className="absolute z-20 top-full left-0 right-0 bg-white border border-gray-200 rounded-xl shadow-lg mt-1 overflow-hidden">
                  {predictions.slice(0, 4).map(p => (
                    <button key={p.place_id} onClick={() => selectPrediction(p)}
                      className="w-full text-left px-4 py-2.5 text-sm hover:bg-gray-50 border-b border-gray-50 last:border-0">
                      📍 {p.description}
                    </button>
                  ))}
                </div>
              )}
            </div>
            <input value={rue} onChange={e => setRue(e.target.value)}
              className="w-full input-field mb-2" placeholder="Rue / numéro" />
            <div className="flex gap-2">
              <input value={ville} onChange={e => setVille(e.target.value)}
                className="flex-1 input-field" placeholder="Ville" required />
              <input value={cp} onChange={e => setCp(e.target.value)}
                className="w-28 input-field" placeholder="Code postal" />
            </div>
            <input value={pays} onChange={e => setPays(e.target.value)}
              className="w-full input-field mt-2" placeholder="Pays" />
          </div>

          {/* Téléphone */}
          <Field label="Téléphone professionnel">
            <input value={phone} onChange={e => setPhone(e.target.value)}
              className="w-full input-field" placeholder="06 12 34 56 78" />
          </Field>

          {/* Éleveur spécifique */}
          {isEleveur && (
            <>
              {/* Hidden file inputs */}
              <input ref={siretDocRef} type="file" accept="image/*,application/pdf" className="hidden"
                onChange={e => { const f = e.target.files?.[0]; if (f) setSiretDocFile(f); e.target.value = ''; }} />
              <input ref={acacedDocRef} type="file" accept="image/*,application/pdf" className="hidden"
                onChange={e => { const f = e.target.files?.[0]; if (f) setAcacedDocFile(f); e.target.value = ''; }} />

              <Field label="SIRET" required>
                <input value={siret} onChange={e => setSiret(e.target.value)}
                  className="w-full input-field" placeholder="14 chiffres" maxLength={14} />
              </Field>

              <div>
                <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">
                  Justificatif SIRET (KBIS) <span className="text-red-500">*</span>
                </p>
                {siretDocFile ? (
                  <div className="flex items-center gap-2 bg-green-50 border border-green-200 rounded-xl px-3 py-2">
                    <span className="text-green-600 text-sm">✓</span>
                    <span className="text-xs text-green-700 flex-1 truncate">{siretDocFile.name}</span>
                    <button type="button" onClick={() => siretDocRef.current?.click()}
                      className="text-xs text-[#0C5C6C] font-medium hover:underline">Changer</button>
                  </div>
                ) : (
                  <button type="button" onClick={() => siretDocRef.current?.click()}
                    className="w-full border-2 border-dashed border-gray-200 hover:border-[#0C5C6C] rounded-xl py-3 text-sm text-gray-400 hover:text-[#0C5C6C] transition-colors">
                    📎 Joindre le KBIS ou extrait SIRET (image ou PDF)
                  </button>
                )}
              </div>

              <Field label="N° ACACED" required>
                <input value={acaced} onChange={e => setAcaced(e.target.value)}
                  className="w-full input-field" placeholder="Ex : ACE-2023-XXXX" />
              </Field>

              <div>
                <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">
                  Date d&apos;obtention ACACED <span className="text-red-500">*</span>
                </p>
                <input type="date" value={acacedDateObtention} onChange={e => setAcacedDateObtention(e.target.value)}
                  className="w-full input-field" />
              </div>

              <div>
                <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">
                  Certificat ACACED <span className="text-red-500">*</span>
                </p>
                {acacedDocFile ? (
                  <div className="flex items-center gap-2 bg-green-50 border border-green-200 rounded-xl px-3 py-2">
                    <span className="text-green-600 text-sm">✓</span>
                    <span className="text-xs text-green-700 flex-1 truncate">{acacedDocFile.name}</span>
                    <button type="button" onClick={() => acacedDocRef.current?.click()}
                      className="text-xs text-[#0C5C6C] font-medium hover:underline">Changer</button>
                  </div>
                ) : (
                  <button type="button" onClick={() => acacedDocRef.current?.click()}
                    className="w-full border-2 border-dashed border-gray-200 hover:border-[#0C5C6C] rounded-xl py-3 text-sm text-gray-400 hover:text-[#0C5C6C] transition-colors">
                    📎 Joindre le certificat ACACED (image ou PDF)
                  </button>
                )}
              </div>

              <Field label="Numéro d'élevage (optionnel)">
                <input value={numElevage} onChange={e => setNumElevage(e.target.value)}
                  className="w-full input-field" placeholder="Numéro SIREN/DDPP" />
              </Field>

              <div>
                <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-2">Espèces élevées</p>
                <EspecesChips selected={especesEleveesSet} onToggle={e => toggleEspece(e, especesEleveesSet, setEspecesEleveesSet)} />
              </div>
            </>
          )}

          {/* Pro spécifique */}
          {isProType && (
            <>
              {hasSiret && (
                <Field label="SIRET">
                  <input value={siret} onChange={e => setSiret(e.target.value)}
                    className="w-full input-field" placeholder="14 chiffres" maxLength={14} />
                </Field>
              )}
              {hasRayon && (
                <div>
                  <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-2">
                    Rayon d&apos;intervention : {rayon} km
                  </p>
                  <input type="range" min={5} max={100} step={5} value={rayon}
                    onChange={e => setRayon(Number(e.target.value))}
                    className="w-full accent-[#6E9E57]" />
                </div>
              )}
              <div>
                <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-2">Espèces acceptées</p>
                <EspecesChips selected={especesSet} onToggle={e => toggleEspece(e, especesSet, setEspecesSet)} />
              </div>
            </>
          )}

          {/* Description */}
          <Field label="Description (facultatif)">
            <textarea value={description} onChange={e => setDescription(e.target.value)}
              rows={3} className="w-full input-field resize-none"
              placeholder="Présentation, spécialités…" />
          </Field>

          {/* Site web */}
          <Field label="Site web (facultatif)">
            <input value={siteWeb} onChange={e => setSiteWeb(e.target.value)}
              className="w-full input-field" placeholder="https://…" type="url" />
          </Field>

          <button
            onClick={handleSave}
            disabled={saving}
            className="w-full py-4 bg-[#6E9E57] hover:bg-[#5A8A45] text-white font-bold rounded-xl transition-colors disabled:opacity-60">
            {saving ? 'Création…' : 'Créer le profil et basculer'}
          </button>
        </div>
      </div>

      <style jsx>{`
        .input-field {
          background: white;
          border: 1px solid #e5e7eb;
          border-radius: 10px;
          padding: 10px 14px;
          font-size: 14px;
          outline: none;
          transition: border-color 0.15s;
          font-family: 'Galey', sans-serif;
        }
        .input-field:focus {
          border-color: #6E9E57;
          box-shadow: 0 0 0 2px rgba(110,158,87,0.15);
        }
      `}</style>
    </div>
  );
}

// ── Formulaire Association ────────────────────────────────────────────────────

function AssociationForm({ uid, onBack, onSaved }: {
  uid: string;
  onBack: () => void;
  onSaved: (id: string) => void;
}) {
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const [nomAsso, setNomAsso]               = useState('');
  const [nomResponsable, setNomResponsable] = useState('');
  const [rna, setRna]                       = useState('');
  const [siret, setSiret]                   = useState('');
  const [acaced, setAcaced]                 = useState('');
  const [acacedDate, setAcacedDate]         = useState('');
  const [phone, setPhone]                   = useState('');
  const [siteWeb, setSiteWeb]               = useState('');
  const [description, setDescription]       = useState('');
  const [rue, setRue]                       = useState('');
  const [ville, setVille]                   = useState('');
  const [cp, setCp]                         = useState('');

  const [siretDocFile, setSiretDocFile]     = useState<File | null>(null);
  const [acacedDocFile, setAcacedDocFile]   = useState<File | null>(null);
  const siretDocRef = useRef<HTMLInputElement>(null);
  const acacedDocRef = useRef<HTMLInputElement>(null);

  async function handleSave() {
    const errs: string[] = [];
    if (!nomAsso.trim())        errs.push("Nom de l'association");
    if (!nomResponsable.trim()) errs.push('Nom du responsable');
    if (!siret.trim())          errs.push('SIRET / SIREN');
    if (!siretDocFile)          errs.push('Justificatif SIRET');
    if (!acaced.trim())         errs.push('N° ACACED');
    if (!acacedDate)            errs.push("Date d'obtention ACACED");
    if (!rue.trim())            errs.push('Rue');
    if (!ville.trim())          errs.push('Ville');
    if (!cp.trim())             errs.push('Code postal');
    if (errs.length > 0) { setError(`Champs obligatoires : ${errs.join(', ')}`); return; }

    setSaving(true);
    setError('');
    try {
      const profileData: Record<string, unknown> = {
        uid,
        profile_type:      'association',
        profile_label:     nomAsso.trim(),
        name_elevage:      nomAsso.trim(),
        profession_pro:    nomResponsable.trim(),
        ordre_veterinaire: rna.trim() || null,
        siret:             siret.trim(),
        certifications:    [{ nom: 'ACACED', numero: acaced.trim(), date_obtention: acacedDate }],
        phone:             phone.trim() || null,
        site_web:          siteWeb.trim() || null,
        desc_entreprise:   description.trim() || null,
        rue:               rue.trim(),
        ville:             ville.trim(),
        code_postal:       cp.trim(),
        pays:              'France',
        statut_pro:        'en_attente',
      };

      // Upload KBIS
      if (siretDocFile) {
        const ext = siretDocFile.name.split('.').pop() ?? 'pdf';
        const path = `documents/${uid}/asso_kbis.${ext}`;
        const { data: up } = await supabase.storage.from('petsmatch').upload(path, siretDocFile, { upsert: true });
        if (up) {
          const { data: pub } = supabase.storage.from('petsmatch').getPublicUrl(path);
          profileData.kbis_url = pub.publicUrl;
        }
      }
      // Upload ACACED
      if (acacedDocFile) {
        const ext = acacedDocFile.name.split('.').pop() ?? 'pdf';
        const path = `documents/${uid}/asso_acaced.${ext}`;
        const { data: up } = await supabase.storage.from('petsmatch').upload(path, acacedDocFile, { upsert: true });
        if (up) {
          const { data: pub } = supabase.storage.from('petsmatch').getPublicUrl(path);
          profileData.acaced_doc_url = pub.publicUrl;
        }
      }

      const { data: rows, error: err } = await supabase
        .from('user_profiles')
        .upsert(profileData, { onConflict: 'uid,profile_type' })
        .select('id');
      if (err) throw err;

      // Marque le profil primaire comme association
      await supabase.from('users').update({ is_association: true }).eq('uid', uid);

      const id = (rows as { id: string }[])[0]?.id ?? '';
      await notifyProfilePendingValidation(uid, 'association');
      onSaved(id);
    } catch (e: unknown) {
      setError((e as Error).message ?? 'Erreur lors de la sauvegarde.');
      setSaving(false);
    }
  }

  return (
    <div className="min-h-screen bg-[#F8F8F8]">
      <div className="max-w-xl mx-auto px-4 py-8">
        <button onClick={onBack} className="flex items-center gap-2 text-[#0C5C6C] mb-6 hover:underline text-sm font-medium">
          ← 🤝 Association
        </button>

        <h1 className="text-2xl font-bold text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>
          Créer le profil Association
        </h1>
        <p className="text-gray-400 text-sm mb-6">Refuge, SPA ou association de protection animale</p>

        {error && (
          <div className="mb-4 bg-red-50 border border-red-200 text-red-600 rounded-xl px-4 py-3 text-sm">{error}</div>
        )}

        {/* File inputs cachés */}
        <input ref={siretDocRef} type="file" accept="image/*,application/pdf" className="hidden"
          onChange={e => { const f = e.target.files?.[0]; if (f) setSiretDocFile(f); e.target.value = ''; }} />
        <input ref={acacedDocRef} type="file" accept="image/*,application/pdf" className="hidden"
          onChange={e => { const f = e.target.files?.[0]; if (f) setAcacedDocFile(f); e.target.value = ''; }} />

        <div className="space-y-5">
          <AssocField label="Nom de l'association" required>
            <input value={nomAsso} onChange={e => setNomAsso(e.target.value)}
              className="w-full input-field" placeholder="Ex : SPA de Lyon, Refuge du Soleil…" />
          </AssocField>

          <AssocField label="Nom du responsable / propriétaire" required>
            <input value={nomResponsable} onChange={e => setNomResponsable(e.target.value)}
              className="w-full input-field" placeholder="Prénom Nom du président(e)" />
          </AssocField>

          <AssocField label="SIRET / SIREN" required>
            <input value={siret} onChange={e => setSiret(e.target.value)}
              className="w-full input-field" placeholder="9 ou 14 chiffres" maxLength={14} />
          </AssocField>

          <div>
            <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">
              Justificatif SIRET (KBIS / extrait) <span className="text-red-500">*</span>
            </p>
            {siretDocFile ? (
              <div className="flex items-center gap-2 bg-green-50 border border-green-200 rounded-xl px-3 py-2">
                <span className="text-green-600 text-sm">✓</span>
                <span className="text-xs text-green-700 flex-1 truncate">{siretDocFile.name}</span>
                <button type="button" onClick={() => siretDocRef.current?.click()}
                  className="text-xs text-[#0C5C6C] font-medium hover:underline">Changer</button>
              </div>
            ) : (
              <button type="button" onClick={() => siretDocRef.current?.click()}
                className="w-full border-2 border-dashed border-gray-200 hover:border-[#0C5C6C] rounded-xl py-3 text-sm text-gray-400 hover:text-[#0C5C6C] transition-colors">
                📎 Joindre le KBIS ou extrait SIRET (image ou PDF)
              </button>
            )}
          </div>

          <AssocField label="Numéro RNA" hint="Répertoire National des Associations — format W123456789">
            <input value={rna} onChange={e => setRna(e.target.value)}
              className="w-full input-field" placeholder="W123456789" />
          </AssocField>

          <AssocField label="N° ACACED" required>
            <input value={acaced} onChange={e => setAcaced(e.target.value)}
              className="w-full input-field" placeholder="Ex : ACE-2023-XXXX" />
          </AssocField>

          <div>
            <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">
              Date d&apos;obtention ACACED <span className="text-red-500">*</span>
            </p>
            <input type="date" value={acacedDate} onChange={e => setAcacedDate(e.target.value)}
              className="w-full input-field" max={new Date().toISOString().slice(0, 10)} />
          </div>

          <div>
            <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">Certificat ACACED</p>
            {acacedDocFile ? (
              <div className="flex items-center gap-2 bg-green-50 border border-green-200 rounded-xl px-3 py-2">
                <span className="text-green-600 text-sm">✓</span>
                <span className="text-xs text-green-700 flex-1 truncate">{acacedDocFile.name}</span>
                <button type="button" onClick={() => acacedDocRef.current?.click()}
                  className="text-xs text-[#0C5C6C] font-medium hover:underline">Changer</button>
              </div>
            ) : (
              <button type="button" onClick={() => acacedDocRef.current?.click()}
                className="w-full border-2 border-dashed border-gray-200 hover:border-[#0C5C6C] rounded-xl py-3 text-sm text-gray-400 hover:text-[#0C5C6C] transition-colors">
                📎 Joindre le certificat ACACED (image ou PDF)
              </button>
            )}
          </div>

          <div>
            <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-2">Adresse du siège</p>
            <input value={rue} onChange={e => setRue(e.target.value)}
              className="w-full input-field mb-2" placeholder="Rue / numéro *" />
            <div className="flex gap-2">
              <input value={cp} onChange={e => setCp(e.target.value)}
                className="w-28 input-field" placeholder="Code postal *" />
              <input value={ville} onChange={e => setVille(e.target.value)}
                className="flex-1 input-field" placeholder="Ville *" />
            </div>
          </div>

          <AssocField label="Téléphone">
            <input value={phone} onChange={e => setPhone(e.target.value)}
              className="w-full input-field" placeholder="06 12 34 56 78" />
          </AssocField>

          <AssocField label="Site web (facultatif)">
            <input value={siteWeb} onChange={e => setSiteWeb(e.target.value)}
              className="w-full input-field" placeholder="https://…" type="url" />
          </AssocField>

          <AssocField label="Présentation (facultatif)">
            <textarea value={description} onChange={e => setDescription(e.target.value)}
              rows={3} className="w-full input-field resize-none"
              placeholder="Mission de l'association, historique, actions…" />
          </AssocField>

          <div className="bg-amber-50 border border-amber-200 rounded-xl px-4 py-3 text-sm text-amber-800">
            Votre profil sera soumis à validation avant d&apos;être visible.
          </div>

          <button onClick={handleSave} disabled={saving}
            className="w-full py-4 bg-[#0C5C6C] hover:bg-[#094F5D] text-white font-bold rounded-xl transition-colors disabled:opacity-60"
            style={{ fontFamily: 'Galey, sans-serif' }}>
            {saving ? 'Création…' : 'Créer le profil association'}
          </button>
        </div>
      </div>

      <style jsx>{`
        .input-field {
          background: white;
          border: 1px solid #e5e7eb;
          border-radius: 10px;
          padding: 10px 14px;
          font-size: 14px;
          outline: none;
          transition: border-color 0.15s;
          font-family: 'Galey', sans-serif;
        }
        .input-field:focus {
          border-color: #0C5C6C;
          box-shadow: 0 0 0 2px rgba(12,92,108,0.12);
        }
      `}</style>
    </div>
  );
}

function AssocField({ label, hint, required, children }: { label: string; hint?: string; required?: boolean; children: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-1">
        {label}{required && <span className="text-red-500 ml-1">*</span>}
      </p>
      {hint && <p className="text-xs text-gray-400 mb-1.5">{hint}</p>}
      {children}
    </div>
  );
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function Field({ label, required, children }: { label: string; required?: boolean; children: React.ReactNode }) {
  return (
    <div>
      <p className="text-xs font-bold text-[#0C5C6C] uppercase tracking-wide mb-2">
        {label}{required && <span className="text-red-500 ml-1">*</span>}
      </p>
      {children}
    </div>
  );
}

function EspecesChips({ selected, onToggle }: { selected: Set<string>; onToggle: (e: string) => void }) {
  return (
    <div className="flex flex-wrap gap-2">
      {ESPECES.map(e => (
        <button key={e} onClick={() => onToggle(e)}
          className={`px-3 py-1.5 rounded-full text-sm font-medium border transition-colors ${
            selected.has(e)
              ? 'bg-[#DCE8D5] border-[#6E9E57] text-[#1F2A2E]'
              : 'bg-white border-gray-200 text-gray-600 hover:border-[#6E9E57]'
          }`}>
          {e}
        </button>
      ))}
    </div>
  );
}

function defaultLabel(type: string, firstname: string, lastname: string): string {
  return ({
    particulier:      `${firstname} ${lastname}`.trim() || 'Mon profil',
    eleveur:          'Mon élevage',
    veterinaire:      'Mon cabinet vétérinaire',
    sante:            'Mon cabinet',
    education:        'Mon activité éducation',
    garde:            'Mon activité garde',
    pension:          'Ma pension',
    toilettage:       'Mon salon',
    photographe:      'Mon activité photo',
    marechal_ferrant: 'Mon activité maréchalerie',
  } as Record<string, string>)[type] ?? 'Mon profil';
}
