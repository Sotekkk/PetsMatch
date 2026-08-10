'use client';

import { useEffect, useRef, useState } from 'react';
import { supabase } from '@/lib/supabase';

interface Animal {
  id: string;
  nom?: string | null;
  espece?: string | null;
  race?: string | null;
  date_naissance?: string | null;
  identification?: string | null;
  uid_eleveur?: string | null;
}

interface Props {
  animal: Animal;
  uid: string;
  profileId?: string | null;
  onClose: () => void;
  onReserved: () => void;
}

const QUALITES = [
  { value: 'particulier', label: 'Particulier' },
  { value: 'eleveur',     label: 'Éleveur' },
  { value: 'refuge',      label: 'Refuge / Association' },
  { value: 'autre',       label: 'Autre' },
];

// Certificat d'engagement (loi du 30/11/2021) obligatoire pour ces espèces,
// avec délai légal de 7 jours avant signature possible.
const ESPECES_DELAI_LEGAL = ['chien', 'chat'];

type DocEntry = { id: string; type: string; statut: string; url: string; created_at: string };

function splitNom(nomComplet: string): { prenom: string; nom: string } {
  const parts = nomComplet.trim().split(/\s+/);
  if (parts.length <= 1) return { prenom: parts[0] ?? '', nom: '' };
  return { prenom: parts[0], nom: parts.slice(1).join(' ') };
}

export default function ReservationModal({ animal, uid, profileId, onClose, onReserved }: Props) {
  const [step, setStep] = useState<'acquéreur' | 'details' | 'documents'>('acquéreur');

  // Acquéreur
  const [searchQuery, setSearchQuery]   = useState('');
  const [searchResult, setSearchResult] = useState<{ uid: string; nom: string; photo?: string } | null>(null);
  const [searchResults, setSearchResults] = useState<{ uid: string; nom: string; photo?: string; _raw?: Record<string, unknown> }[]>([]);
  const [searchDone, setSearchDone]     = useState(false);
  const [searching, setSearching]       = useState(false);
  const [manual, setManual]             = useState(false);
  // Données brutes de l'utilisateur PetsMatch sélectionné (pour préremplir le contrat)
  const [selectedUserData, setSelectedUserData] = useState<Record<string, unknown> | null>(null);

  // Autocomplétion adresse BAN
  const [adressSuggestions, setAdressSuggestions] = useState<{ label: string }[]>([]);
  const adressTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Détails
  const [qualite, setQualite]           = useState('particulier');
  const [nom, setNom]                   = useState('');
  const [email, setEmail]               = useState('');
  const [tel, setTel]                   = useState('');
  const [adresse, setAdresse]           = useState('');
  const [dateReservation, setDateReservation] = useState(new Date().toISOString().split('T')[0]);
  const [acompte, setAcompte]           = useState('');
  const [notes, setNotes]               = useState('');

  // Documents optionnels : contrat de réservation (app) et/ou certificat
  // d'engagement (légal, chien/chat). Si aucun n'est coché, la réservation
  // reste simple (comme aujourd'hui) — le formulaire papier de l'éleveur
  // reste possible en dehors de l'app.
  const [wantContrat, setWantContrat]       = useState(false);
  const [wantCertificat, setWantCertificat] = useState(false);
  // Prénom/nom séparés pour le certificat d'engagement (dérivés de `nom`,
  // éditables si l'éleveur veut corriger la coupure automatique)
  const [certifPrenom, setCertifPrenom] = useState('');
  const [certifNom, setCertifNom]       = useState('');
  const [certifPrenomTouched, setCertifPrenomTouched] = useState(false);

  // Contrat de réservation (documents_animaux)
  const [existingContrats, setExistingContrats] = useState<DocEntry[]>([]);
  const [loadingDocs, setLoadingDocs]           = useState(false);
  const contratPopupRef = useRef<Window | null>(null);

  // Certificat d'engagement (certificats_engagement)
  const [certifSaving, setCertifSaving] = useState(false);
  const [certifError, setCertifError]   = useState('');
  const [certifToken, setCertifToken]   = useState<string | null>(null);
  const especeLower = (animal.espece ?? '').toLowerCase();
  const needsDelaiLegal = ESPECES_DELAI_LEGAL.includes(especeLower);

  const [saving, setSaving] = useState(false);
  const [error, setError]   = useState('');

  // Reprend prénom/nom depuis le nom complet tant que l'éleveur n'a pas
  // corrigé lui-même les champs dédiés du certificat d'engagement.
  useEffect(() => {
    if (certifPrenomTouched) return;
    const { prenom, nom: n } = splitNom(nom);
    setCertifPrenom(prenom);
    setCertifNom(n);
  }, [nom, certifPrenomTouched]);

  // Charge les contrats de réservation déjà créés pour cet animal
  useEffect(() => {
    if (!wantContrat) return;
    setLoadingDocs(true);
    supabase.from('documents_animaux')
      .select('id, type, statut, url, created_at')
      .eq('animal_id', animal.id)
      .eq('type', 'contrat_reservation')
      .order('created_at', { ascending: false })
      .then(({ data }) => {
        setExistingContrats((data ?? []) as DocEntry[]);
        setLoadingDocs(false);
      });
  }, [wantContrat, animal.id]);

  function reloadContrats() {
    setLoadingDocs(true);
    supabase.from('documents_animaux')
      .select('id, type, statut, url, created_at')
      .eq('animal_id', animal.id)
      .eq('type', 'contrat_reservation')
      .order('created_at', { ascending: false })
      .then(({ data }) => {
        setExistingContrats((data ?? []) as DocEntry[]);
        setLoadingDocs(false);
      });
  }

  function openContratCreation() {
    const isElv = selectedUserData?.is_elevage === true;
    localStorage.setItem('cession_prefill', JSON.stringify({
      animal_id:          animal.id,
      animal_nom:         animal.nom ?? '',
      form_type:          'contrat_reservation',
      acq_is_eleveur:     isElv,
      acq_raison_sociale: isElv ? (selectedUserData?.name_elevage as string ?? '') : '',
      acq_siret:          isElv ? (selectedUserData?.siret as string ?? '') : '',
      acq_prenom:         (selectedUserData?.firstname as string ?? ''),
      acq_nom_famille:    (selectedUserData?.lastname as string ?? ''),
      acq_email:          email.trim(),
      acq_tel:            tel.trim(),
      acq_adresse:        adresse.trim(),
      prix:               acompte.trim(),
      date:               dateReservation,
    }));
    const popup = window.open('/elevage/contrat?from=cession', '_blank', 'width=900,height=700,left=100,top=80');
    contratPopupRef.current = popup;
    const timer = setInterval(() => {
      if (popup?.closed) {
        clearInterval(timer);
        reloadContrats();
      }
    }, 800);
  }

  async function createCertificatEngagement() {
    if (!certifPrenom.trim() || !certifNom.trim() || !email.trim()) {
      setCertifError('Prénom, nom et email du futur propriétaire sont requis pour le certificat.');
      return;
    }
    setCertifSaving(true);
    setCertifError('');
    try {
      const dateRemise = new Date();
      const dateLimite = needsDelaiLegal ? new Date(dateRemise.getTime() + 7 * 86400_000) : null;
      const res = await fetch('/api/certificat/create', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          uid,
          animal_id:             animal.id,
          espece:                animal.espece ?? '',
          race:                  animal.race ?? null,
          nom_animal:            animal.nom ?? '',
          date_naissance_animal: animal.date_naissance ?? null,
          num_identification:    animal.identification ?? null,
          acquereur_uid:         searchResult?.uid ?? null,
          acquereur_nom:         certifNom.trim(),
          acquereur_prenom:      certifPrenom.trim(),
          acquereur_email:       email.trim(),
          acquereur_telephone:   tel.trim() || null,
          acquereur_adresse:     adresse.trim() || null,
          modalite_cession:      qualite === 'autre' ? 'gratuit' : 'vente',
          prix:                  acompte ? parseFloat(acompte) : null,
          date_remise:           dateRemise.toISOString(),
          date_limite_signature: dateLimite?.toISOString() ?? null,
          notes:                 notes.trim(),
        }),
      });
      const json = await res.json();
      if (!res.ok) { setCertifError(json.error ?? 'Erreur serveur'); return; }
      setCertifToken(json.token);
    } catch (e) {
      setCertifError(`Erreur : ${e}`);
    } finally {
      setCertifSaving(false);
    }
  }

  function fillFromUser(data: Record<string, unknown>) {
    setSelectedUserData(data);
    const isElv = data.is_elevage === true;
    const n = isElv
      ? ((data.name_elevage as string) || `${data.firstname ?? ''} ${data.lastname ?? ''}`.trim())
      : `${data.firstname ?? ''} ${data.lastname ?? ''}`.trim();
    const phone = isElv
      ? `${data.code_iso_elevage ?? '+33'} ${data.numero_elevage ?? ''}`.trim()
      : `${data.code_iso ?? '+33'} ${data.phone_number ?? ''}`.trim();
    const addr = isElv
      ? ((data.adress_elevage as string) || '')
      : ((data.adress as string) || [data.rue, data.code_postal, data.ville].filter(Boolean).join(', '));
    setNom(n || 'Utilisateur PetsMatch');
    setEmail((data.email as string) ?? '');
    setTel(phone.replace(/^\+33\s*$/, ''));
    setAdresse(addr || '');
    if (isElv) setQualite('eleveur');
    if (!isElv) {
      setCertifPrenomTouched(false);
      setCertifPrenom((data.firstname as string) ?? '');
      setCertifNom((data.lastname as string) ?? '');
      setCertifPrenomTouched(true);
    }
  }

  function mapProfile(cp: Record<string, unknown>, email?: string): Record<string, unknown> {
    return {
      uid: cp.uid, firstname: cp.firstname, lastname: cp.lastname,
      name_elevage: cp.nom, is_elevage: cp.profile_type === 'eleveur',
      profile_picture_url: cp.avatar_url, phone_number: cp.phone_number,
      code_iso: '+33', code_iso_elevage: '+33',
      adress: cp.adresse, adress_elevage: cp.adresse,
      rue: cp.rue, ville: cp.ville, code_postal: cp.code_postal,
      numero_elevage: cp.numero_elevage,
      // email_contact est le champ fiable pour tous les types de profil
      // (éleveur y compris) — l'email de la table `users` (login) n'est
      // renseigné ici que si la recherche s'est faite par email.
      email: (cp.email_contact as string) || email,
    };
  }

  async function searchUser() {
    const q = searchQuery.trim();
    if (!q) return;
    setSearching(true);
    setSearchDone(false);
    setSearchResult(null);
    setSearchResults([]);
    const CP_FIELDS = 'uid, firstname, lastname, nom, profile_type, avatar_url, phone_number, adresse, rue, ville, code_postal, numero_elevage, email_contact';
    const isEmail = q.includes('@');
    let rows: Record<string, unknown>[] = [];
    if (isEmail) {
      const { data: userRow } = await supabase.from('users').select('uid, email').eq('email', q.toLowerCase()).maybeSingle();
      if (userRow) {
        const { data: cp } = await supabase.from('user_profiles').select(CP_FIELDS).eq('uid', userRow.uid).eq('is_main', true).maybeSingle();
        if (cp) rows = [mapProfile(cp, userRow.email)];
      }
    } else {
      const { data } = await supabase.from('user_profiles').select(CP_FIELDS)
        .or(`firstname.ilike.%${q}%,lastname.ilike.%${q}%,nom.ilike.%${q}%`)
        .eq('is_main', true)
        .limit(6);
      rows = ((data as Record<string, unknown>[]) ?? []).map(cp => mapProfile(cp));
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
      }));
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
      setAdressSuggestions((json.features ?? []).map((f: { properties: { label: string } }) => ({ label: f.properties.label })));
    } catch { setAdressSuggestions([]); }
  }

  function onAdresseChange(val: string) {
    setAdresse(val);
    if (adressTimer.current) clearTimeout(adressTimer.current);
    adressTimer.current = setTimeout(() => fetchAdressSuggestions(val), 300);
  }

  async function save() {
    if (!nom.trim()) { setError("Le nom du futur propriétaire est requis."); return; }
    setSaving(true);
    setError('');
    try {
      const { error: insertError } = await supabase.from('reservations_animaux').insert({
        animal_id:     animal.id,
        uid_eleveur:   uid,
        ...(profileId ? { eleveur_profile_id: profileId } : {}),
        statut:        'active',
        qualite,
        nom:           nom.trim(),
        email:         email.trim() || null,
        tel:           tel.trim() || null,
        adresse:       adresse.trim() || null,
        uid_acquereur: searchResult?.uid ?? null,
        date_reservation: dateReservation || null,
        notes:         notes.trim() || null,
      });
      if (insertError) throw insertError;
      const { error: updateError } = await supabase.from('animaux').update({ statut: 'reserve' }).eq('id', animal.id);
      if (updateError) throw updateError;
      onReserved();
    } catch (e) {
      setError(`Erreur : ${e}`);
      setSaving(false);
    }
  }

  const stepLabel = step === 'acquéreur' ? 'Étape 1/2 — Futur propriétaire'
    : step === 'details' ? 'Étape 2/2 — Détails'
    : 'Documents';

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 backdrop-blur-sm p-0 sm:p-4">
      <div className="bg-white w-full sm:max-w-lg rounded-t-3xl sm:rounded-2xl shadow-2xl max-h-[92vh] overflow-y-auto">
        <div className="sticky top-0 bg-white border-b border-gray-100 px-5 py-4 flex items-center justify-between rounded-t-3xl sm:rounded-t-2xl">
          <div>
            <h2 className="text-base font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey,sans-serif' }}>
              🔖 Réserver {animal.nom ?? 'cet animal'}
            </h2>
            <p className="text-xs text-gray-400 mt-0.5">{stepLabel}</p>
          </div>
          <button onClick={onClose} className="w-8 h-8 flex items-center justify-center text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-full transition-colors">✕</button>
        </div>

        <div className="p-5 space-y-4">
          {step === 'acquéreur' && (
            <>
              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-2">Rechercher un utilisateur PetsMatch</label>
                <div className="flex gap-2">
                  <input
                    type="text" placeholder="Nom ou email…"
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
                  {searchResults.map(r => (
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
                ✏️ Saisie manuelle (hors PetsMatch)
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

          {step === 'details' && (
            <>
              {searchResult && (
                <div className="rounded-xl p-3 border border-[#0C5C6C]/20 bg-[#0C5C6C]/5 flex items-center gap-3">
                  <span className="text-lg">✓</span>
                  <p className="text-sm font-semibold text-[#0C5C6C]">{searchResult.nom} · PetsMatch</p>
                </div>
              )}

              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1">Date de réservation</label>
                <input type="date" value={dateReservation} onChange={e => setDateReservation(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>

              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1">Qualité</label>
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
                <label className="block text-xs font-semibold text-gray-500 mb-1">Nom du futur propriétaire *</label>
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
                <input type="text" placeholder="Adresse du futur propriétaire" value={adresse}
                  onChange={e => manual ? onAdresseChange(e.target.value) : setAdresse(e.target.value)}
                  readOnly={!!searchResult && !manual}
                  className={`w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] ${searchResult && !manual ? 'bg-gray-50' : ''}`} />
                {manual && adressSuggestions.length > 0 && (
                  <div className="absolute z-10 top-full left-0 right-0 mt-1 bg-white border border-gray-200 rounded-xl shadow-lg overflow-hidden">
                    {adressSuggestions.map((s, i) => (
                      <button key={i} onClick={() => { setAdresse(s.label); setAdressSuggestions([]); }}
                        className="w-full text-left px-4 py-2.5 text-sm hover:bg-[#0C5C6C]/5 border-b border-gray-100 last:border-0 transition-colors">
                        {s.label}
                      </button>
                    ))}
                  </div>
                )}
              </div>

              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1">Acompte / arrhes versé (€) — optionnel</label>
                <input type="number" min="0" placeholder="0" value={acompte} onChange={e => setAcompte(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
              </div>

              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1">Notes</label>
                <textarea rows={2} placeholder="Conditions, remarques…" value={notes} onChange={e => setNotes(e.target.value)}
                  className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C] resize-none" />
              </div>

              {/* Documents optionnels — laisse le choix entre gérer le papier
                  soi-même ou générer les documents depuis l'application. */}
              <div className="rounded-xl border border-gray-200 p-3 space-y-2">
                <p className="text-xs font-semibold text-gray-500">Documents (optionnel)</p>
                <label className="flex items-start gap-2 cursor-pointer">
                  <input type="checkbox" checked={wantContrat} onChange={e => setWantContrat(e.target.checked)}
                    className="mt-0.5 rounded text-[#0C5C6C] focus:ring-[#0C5C6C]" />
                  <span className="text-sm text-gray-700">
                    Générer un <strong>contrat de réservation</strong>
                    <span className="block text-xs text-gray-400">Arrhes, conditions d&apos;annulation, engagement des deux parties.</span>
                  </span>
                </label>
                <label className="flex items-start gap-2 cursor-pointer">
                  <input type="checkbox" checked={wantCertificat} onChange={e => setWantCertificat(e.target.checked)}
                    className="mt-0.5 rounded text-[#0C5C6C] focus:ring-[#0C5C6C]" />
                  <span className="text-sm text-gray-700">
                    Générer un <strong>certificat d&apos;engagement</strong>
                    <span className="block text-xs text-gray-400">
                      {needsDelaiLegal
                        ? "Obligatoire pour chien/chat (loi du 30/11/2021) — délai légal de 7 jours avant signature."
                        : "Attestation d'engagement et de connaissance de l'acquéreur."}
                    </span>
                  </span>
                </label>
                <p className="text-xs text-gray-400">
                  Rien à cocher si vous gérez ces documents vous-même en dehors de l&apos;application.
                </p>
              </div>

              {error && <p className="text-xs text-red-600 bg-red-50 px-3 py-2 rounded-xl">{error}</p>}

              <div className="flex gap-2 pt-2">
                <button onClick={() => setStep('acquéreur')}
                  className="flex-1 border border-gray-200 text-gray-600 font-semibold py-2.5 rounded-xl text-sm hover:bg-gray-50 transition-colors">
                  ← Retour
                </button>
                {wantContrat || wantCertificat ? (
                  <button onClick={() => setStep('documents')} disabled={!nom.trim()}
                    className="flex-1 bg-[#0C5C6C] text-white font-semibold py-2.5 rounded-xl text-sm hover:bg-[#094F5D] disabled:opacity-40 transition-colors">
                    Documents →
                  </button>
                ) : (
                  <button onClick={save} disabled={!nom.trim() || saving}
                    className="flex-1 bg-amber-600 text-white font-semibold py-2.5 rounded-xl text-sm hover:bg-amber-700 disabled:opacity-40 transition-colors">
                    {saving ? 'Enregistrement…' : '🔖 Réserver'}
                  </button>
                )}
              </div>
            </>
          )}

          {step === 'documents' && (
            <>
              {wantContrat && (
                <div className="space-y-2">
                  <div className="flex items-center justify-between">
                    <p className="text-xs font-semibold text-[#1F2A2E]">🐾 Contrat de réservation</p>
                    <button onClick={openContratCreation} className="text-xs font-semibold text-[#0C5C6C] hover:underline">
                      + Créer un contrat
                    </button>
                  </div>
                  {loadingDocs ? (
                    <p className="text-xs text-gray-400">Chargement…</p>
                  ) : existingContrats.length === 0 ? (
                    <p className="text-xs text-gray-400 italic">Aucun contrat existant — cliquez sur « Créer un contrat » ci-dessus.</p>
                  ) : (
                    <div className="space-y-1.5">
                      {existingContrats.map(d => {
                        const label = d.statut === 'signe' ? '✅ Signé' : d.statut === 'partiellement_signe' ? '✍️ Partiel' : d.statut === 'en_attente' ? '⏳ En attente' : '📝 Brouillon';
                        const date = d.created_at ? new Date(d.created_at).toLocaleDateString('fr-FR') : '';
                        return (
                          <div key={d.id} className="flex items-center gap-2 rounded-xl border border-gray-200 px-3 py-2">
                            <div className="flex-1 min-w-0">
                              <p className="text-xs font-semibold text-[#1F2A2E]">Contrat de réservation</p>
                              <p className="text-[10px] text-gray-500">{label}{date ? `  ·  ${date}` : ''}</p>
                            </div>
                            <a href={`/signer-contrat/${(d as { id: string; token?: string }).token ?? d.id}`} target="_blank" rel="noreferrer"
                              className="p-1.5 text-gray-400 hover:text-[#0C5C6C]" title="Ouvrir">
                              <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" /></svg>
                            </a>
                          </div>
                        );
                      })}
                    </div>
                  )}
                </div>
              )}

              {wantContrat && wantCertificat && <hr className="border-gray-100" />}

              {wantCertificat && (
                <div className="space-y-2">
                  <p className="text-xs font-semibold text-[#1F2A2E]">📜 Certificat d&apos;engagement</p>
                  {needsDelaiLegal && (
                    <p className="text-[11px] text-amber-600">⚠ Signature possible par l&apos;acquéreur seulement 7 jours après la remise (loi 30/11/2021).</p>
                  )}
                  <div className="grid grid-cols-2 gap-2">
                    <div>
                      <label className="block text-[11px] text-gray-500 mb-1">Prénom *</label>
                      <input type="text" value={certifPrenom}
                        onChange={e => { setCertifPrenomTouched(true); setCertifPrenom(e.target.value); }}
                        className="w-full border border-gray-200 rounded-lg px-2.5 py-1.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                    </div>
                    <div>
                      <label className="block text-[11px] text-gray-500 mb-1">Nom *</label>
                      <input type="text" value={certifNom}
                        onChange={e => { setCertifPrenomTouched(true); setCertifNom(e.target.value); }}
                        className="w-full border border-gray-200 rounded-lg px-2.5 py-1.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                    </div>
                  </div>
                  {certifError && <p className="text-xs text-red-600 bg-red-50 px-3 py-2 rounded-xl">{certifError}</p>}
                  {certifToken ? (
                    <div className="bg-green-50 border border-green-200 rounded-xl p-3">
                      <p className="text-xs font-semibold text-green-800 mb-1">✅ Certificat créé — partagez ce lien :</p>
                      <div className="flex items-center gap-2 mt-1">
                        <code className="text-[10px] bg-white border border-green-200 rounded px-2 py-1.5 flex-1 text-green-700 break-all">
                          {typeof window !== 'undefined' ? window.location.origin : ''}/certificat/{certifToken}
                        </code>
                        <button onClick={() => navigator.clipboard.writeText(`${window.location.origin}/certificat/${certifToken}`)}
                          className="shrink-0 bg-green-600 hover:bg-green-700 text-white text-[10px] font-semibold px-2.5 py-1.5 rounded-lg">
                          Copier
                        </button>
                      </div>
                    </div>
                  ) : (
                    <button onClick={createCertificatEngagement} disabled={certifSaving}
                      className="w-full text-xs font-semibold text-[#0C5C6C] border border-[#0C5C6C]/30 rounded-xl py-2 hover:bg-[#0C5C6C]/5 disabled:opacity-50">
                      {certifSaving ? 'Création…' : '+ Créer le certificat d’engagement'}
                    </button>
                  )}
                </div>
              )}

              {error && <p className="text-xs text-red-600 bg-red-50 px-3 py-2 rounded-xl">{error}</p>}

              <div className="flex gap-2 pt-2">
                <button onClick={() => setStep('details')}
                  className="flex-1 border border-gray-200 text-gray-600 font-semibold py-2.5 rounded-xl text-sm hover:bg-gray-50 transition-colors">
                  ← Retour
                </button>
                <button onClick={save} disabled={!nom.trim() || saving}
                  className="flex-1 bg-amber-600 text-white font-semibold py-2.5 rounded-xl text-sm hover:bg-amber-700 disabled:opacity-40 transition-colors">
                  {saving ? 'Enregistrement…' : '🔖 Terminer la réservation'}
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
