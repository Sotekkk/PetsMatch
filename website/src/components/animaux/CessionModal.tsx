'use client';

import { useState, useRef, useEffect } from 'react';
import { supabase } from '@/lib/supabase';
import { uploadDocument } from '@/lib/upload-media';
import { factureVentePdfBlob } from '@/lib/facture-vente';
import { resolveAcquereurProfileId } from '@/lib/acquereur-profile';
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

interface Reservation {
  id: string;
  qualite?: string | null;
  nom?: string | null;
  email?: string | null;
  tel?: string | null;
  adresse?: string | null;
  uid_acquereur?: string | null;
  notes?: string | null;
}

interface Props {
  animal: Animal;
  uid: string;
  profileId?: string | null;
  eleveurInfo: EleveurInfo;
  onClose: () => void;
  onCeded: () => void;
  /** true = l'utilisateur est acquéreur qui re-cède (don / abandon, pas de contrat) */
  isReCession?: boolean;
  /** Réservation active à préremplir — l'étape "Acquéreur" est alors sautée */
  reservation?: Reservation | null;
}

const QUALITES_FULL = [
  { value: 'particulier', label: 'Particulier' },
  { value: 'eleveur',     label: 'Éleveur' },
  { value: 'refuge',      label: 'Refuge / Association' },
  { value: 'autre',       label: 'Autre' },
];
const QUALITES_RECESSION = [
  { value: 'particulier', label: 'Particulier / Famille' },
  { value: 'refuge',      label: 'Association / Refuge' },
];

function fmtDate(s?: string) {
  if (!s) return '—';
  return new Date(s).toLocaleDateString('fr-FR');
}

export default function CessionModal({ animal, uid, profileId, eleveurInfo, onClose, onCeded, isReCession = false, reservation = null }: Props) {
  const [step, setStep] = useState<'acquéreur' | 'details' | 'documents'>(reservation ? 'details' : 'acquéreur');

  // Acquéreur — préremplis depuis la réservation active s'il y en a une
  const [searchQuery, setSearchQuery]   = useState('');
  const [searchResult, setSearchResult] = useState<{ uid: string; nom: string; photo?: string } | null>(
    reservation?.uid_acquereur ? { uid: reservation.uid_acquereur, nom: reservation.nom ?? 'Utilisateur PetsMatch' } : null
  );
  const [searchResults, setSearchResults] = useState<{ uid: string; nom: string; photo?: string }[]>([]);
  const [searchDone, setSearchDone]     = useState(false);
  const [searching, setSearching]       = useState(false);
  const [manual, setManual]             = useState(!!reservation && !reservation.uid_acquereur);
  // Données brutes de l'utilisateur PetsMatch sélectionné (pour préremplir le contrat)
  const [selectedUserData, setSelectedUserData] = useState<Record<string, unknown> | null>(null);

  // Autocomplétion adresse BAN
  const [adressSuggestions, setAdressSuggestions] = useState<{ label: string; rue: string; ville: string; cp: string; pays: string }[]>([]);
  const adressTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Détails
  const [qualite, setQualite]       = useState(reservation?.qualite || 'particulier');
  const [prenom, setPrenom]         = useState('');
  const [nom, setNom]               = useState(reservation?.nom ?? '');
  const [email, setEmail]           = useState(reservation?.email ?? '');
  const [tel, setTel]               = useState(reservation?.tel ?? '');
  const [adresse, setAdresse]       = useState(reservation?.adresse ?? '');
  const [dateCession, setDateCession] = useState(new Date().toISOString().split('T')[0]);
  const [prix, setPrix]             = useState('');
  const [notes, setNotes]           = useState(reservation?.notes ?? '');

  // Condition de stérilisation (cession éleveur uniquement)
  const [sterilRequise, setSterilRequise] = useState(false);
  const [sterilAgeMois, setSterilAgeMois] = useState('12');
  const dateNaissance = animal.date_naissance || null;
  const sterilEcheance = (() => {
    const m = parseInt(sterilAgeMois, 10);
    if (!dateNaissance || !m || m <= 0) return null;
    const d = new Date(dateNaissance);
    d.setMonth(d.getMonth() + m);
    return d;
  })();

  // Documents uploadés manuellement
  const [contratUrl, setContratUrl]       = useState('');
  const [certificatUrl, setCertificatUrl] = useState('');
  const [santeUrl, setSanteUrl]           = useState('');
  const [uploadingContrat, setUploadingContrat]       = useState(false);
  const [uploadingCertificat, setUploadingCertificat] = useState(false);
  const [uploadingSante, setUploadingSante]           = useState(false);
  const contratRef    = useRef<HTMLInputElement>(null);
  const certificatRef = useRef<HTMLInputElement>(null);
  const santeRef      = useRef<HTMLInputElement>(null);

  const [saving, setSaving]             = useState(false);
  const [error, setError]               = useState('');
  const [contratSigne, setContratSigne]       = useState(false);
  const [certificatSigne, setCertificatSigne] = useState(false);
  const contratPopupRef = useRef<Window | null>(null);

  // Documents existants sélectionnables
  type DocEntry = { id: string; type: string; statut: string; url: string; created_at: string; titre?: string; metadata?: Record<string, unknown> };
  const [existingContrats,    setExistingContrats]    = useState<DocEntry[]>([]);
  const [existingCertificats, setExistingCertificats] = useState<DocEntry[]>([]);
  const [existingFactures,    setExistingFactures]    = useState<DocEntry[]>([]);
  const [selectedContrat,    setSelectedContrat]    = useState<DocEntry | null>(null);
  const [selectedCertificat, setSelectedCertificat] = useState<DocEntry | null>(null);
  const [loadingDocs, setLoadingDocs] = useState(true);
  const [generatingFacture, setGeneratingFacture] = useState(false);

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

  function applyDocs(data: unknown) {
    const all = (data ?? []) as DocEntry[];
    setExistingContrats(all.filter(d => d.type === 'contrat_vente' || d.type === 'contrat_reservation'));
    setExistingCertificats(all.filter(d => d.type === 'certificat_cession'));
    setExistingFactures(all.filter(d => d.type === 'facture'));
    setLoadingDocs(false);
  }

  // Chargement de tous les documents liés à l'animal
  useEffect(() => {
    supabase.from('documents_animaux')
      .select('id, type, titre, statut, url, created_at, metadata')
      .eq('animal_id', animal.id)
      .in('type', ['contrat_vente', 'contrat_reservation', 'certificat_cession', 'facture'])
      .order('created_at', { ascending: false })
      .then(({ data }) => applyDocs(data));
  }, [animal.id]);

  function reloadDocs() {
    setLoadingDocs(true);
    supabase.from('documents_animaux')
      .select('id, type, titre, statut, url, created_at, metadata')
      .eq('animal_id', animal.id)
      .in('type', ['contrat_vente', 'contrat_reservation', 'certificat_cession', 'facture'])
      .order('created_at', { ascending: false })
      .then(({ data }) => applyDocs(data));
  }

  function openContratCreation(formType: 'contrat_vente' | 'certificat_cession' = 'contrat_vente') {
    // Pré-remplit l'animal et l'acheteur dans la page contrat via localStorage
    const isElv = selectedUserData?.is_elevage === true;
    localStorage.setItem('cession_prefill', JSON.stringify({
      animal_id:          animal.id,
      animal_nom:         animal.nom ?? '',
      form_type:          formType,
      acq_is_eleveur:     isElv,
      acq_raison_sociale: isElv ? (selectedUserData?.name_elevage as string ?? '') : '',
      acq_siret:          isElv ? (selectedUserData?.siret as string ?? '') : '',
      acq_prenom:         (selectedUserData?.firstname as string ?? ''),
      acq_nom_famille:    (selectedUserData?.lastname as string ?? ''),
      acq_email:          email.trim(),
      acq_tel:            tel.trim(),
      acq_adresse:        adresse.trim(),
      prix:               prix.trim(),
      date:               dateCession,
    }));
    const popup = window.open('/elevage/contrat?from=cession', '_blank', 'width=900,height=700,left=100,top=80');
    contratPopupRef.current = popup;
    const timer = setInterval(() => {
      if (popup?.closed) {
        clearInterval(timer);
        reloadDocs();
      }
    }, 800);
  }

  async function fillFromUser(data: Record<string, unknown>) {
    // Cession à un particulier → coordonnées du profil particulier
    // (pas le profil pro/pension souvent `is_main`).
    if (data.is_elevage !== true && data.uid) {
      const { data: part } = await supabase.from('user_profiles')
        .select('firstname, lastname, adresse, rue, ville, code_postal, phone_number, email_contact')
        .eq('uid', data.uid as string).eq('profile_type', 'particulier').maybeSingle();
      if (part) {
        data = {
          ...data,
          firstname: part.firstname ?? data.firstname,
          lastname: part.lastname ?? data.lastname,
          adress: (part.adresse ?? [part.rue, part.code_postal, part.ville].filter(Boolean).join(', ')) || data.adress,
          rue: part.rue, ville: part.ville, code_postal: part.code_postal,
          phone_number: part.phone_number ?? data.phone_number,
          email: (part.email_contact as string) || data.email,
        };
      }
    }
    setSelectedUserData(data);
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
    if (isElv) {
      setPrenom('');
      setNom(n || 'Utilisateur PetsMatch');
    } else {
      const fn = (data.firstname as string ?? '').trim();
      const ln = (data.lastname as string ?? '').trim();
      setPrenom(fn);
      setNom(ln || n || 'Utilisateur PetsMatch');
    }
    setEmail((data.email as string) ?? '');
    setTel(phone.replace(/^\+33\s*$/, ''));
    setAdresse(addr || '');
    if (isElv) setQualite('eleveur');
  }

  function mapProfile(cp: Record<string, unknown>, email?: string): Record<string, unknown> {
    return {
      uid: cp.uid, firstname: cp.firstname, lastname: cp.lastname,
      name_elevage: cp.nom, is_elevage: cp.profile_type === 'eleveur',
      profile_picture_url: cp.avatar_url, phone_number: cp.phone_number,
      code_iso: '+33', code_iso_elevage: '+33',
      adress: cp.adresse, adress_elevage: cp.adresse,
      rue: cp.rue, ville: cp.ville, code_postal: cp.code_postal,
      numero_elevage: cp.numero_elevage, siret: cp.siret,
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
    const CP_FIELDS = 'uid, firstname, lastname, nom, profile_type, avatar_url, phone_number, adresse, rue, ville, code_postal, numero_elevage, siret, email_contact';
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

  async function uploadDoc(file: File, type: 'contrat' | 'certificat' | 'sante') {
    const setter   = type === 'contrat' ? setUploadingContrat : type === 'certificat' ? setUploadingCertificat : setUploadingSante;
    const urlSetter = type === 'contrat' ? setContratUrl : type === 'certificat' ? setCertificatUrl : setSanteUrl;
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

  const nomComplet = [prenom.trim(), nom.trim()].filter(Boolean).join(' ');

  async function genererFacture() {
    const montant = parseFloat((prix || '').replace(',', '.')) || 0;
    if (montant <= 0) { setError('Renseignez d\'abord le prix pour générer une facture.'); return; }
    setGeneratingFacture(true);
    setError('');
    try {
      const meta = (selectedContrat?.metadata ?? {}) as Record<string, unknown>;
      const tvaTaux = String(meta.tva_assujetti) === 'true'
        ? (parseFloat(String(meta.tva_taux ?? '20').replace(',', '.')) || 20)
        : 0;
      const numero = `F${new Date().getFullYear()}-${String(Date.now()).slice(-6)}`;
      const blob = await factureVentePdfBlob({
        numero,
        date: dateCession,
        montantTtc: montant,
        tvaTaux,
        emetteur: {
          nom: eleveurInfo.nom, adresse: eleveurInfo.adresse, siret: eleveurInfo.siret,
          tel: eleveurInfo.tel, email: eleveurInfo.email,
        },
        client: { nom: nomComplet, adresse: adresse.trim(), tel: tel.trim(), email: email.trim() },
        animal: {
          nom: animal.nom, espece: animal.espece, race: animal.race,
          identification: animal.identification, date_naissance: animal.date_naissance,
        },
      });
      const path = `cessions/${uid}/${animal.id}/facture_${Date.now()}.pdf`;
      const file = new File([blob], `${numero}.pdf`, { type: 'application/pdf' });
      const url = await uploadDocument(file, path);
      await supabase.from('documents_animaux').insert({
        animal_id: animal.id,
        uid_eleveur: uid,
        ...(profileId ? { pro_profile_id: profileId } : {}),
        type: 'facture',
        titre: `Facture ${numero}${animal.nom ? ` — ${animal.nom}` : ''}`,
        statut: 'genere',
        url,
        metadata: { numero, montant, tva_taux: tvaTaux },
      });

      // Enregistrer aussi dans « Mes factures » (table factures)
      try {
        const ht = tvaTaux > 0 ? montant / (1 + tvaTaux / 100) : montant;
        const tvaMontant = montant - ht;
        const { data: lastRows } = await supabase.from('factures')
          .select('numero_facture').eq('uid_eleveur', uid)
          .order('numero_facture', { ascending: false }).limit(1);
        const nextNum = ((lastRows?.[0]?.numero_facture as number | undefined) ?? 0) + 1;
        const cpMatch = adresse.trim().match(/\b(\d{5})\b/);
        await supabase.from('factures').insert({
          uid_eleveur: uid,
          ...(profileId ? { profile_id: profileId } : {}),
          profil_source: 'eleveur',
          numero_facture: nextNum,
          date_facture: dateCession,
          date_prestation: dateCession,
          token: crypto.randomUUID(),
          lignes: [{
            description: `Cession — ${animal.nom ?? 'animal'}${animal.espece ? ` (${animal.espece})` : ''}`,
            quantite: 1,
            prixUnitaire: Number(ht.toFixed(2)), prixUnitaireHT: Number(ht.toFixed(2)),
            tva: tvaTaux, tauxTVA: tvaTaux,
            totalHT: Number(ht.toFixed(2)), montantTVA: Number(tvaMontant.toFixed(2)),
          }],
          total_ht: Number(ht.toFixed(2)),
          total_tva: Number(tvaMontant.toFixed(2)),
          total_ttc: montant,
          regime_tva: tvaTaux > 0 ? 'normal' : 'franchise',
          nom_client: nom.trim(),
          prenom_client: prenom.trim() || null,
          email_client: email.trim() || null,
          telephone_client: tel.trim() || null,
          rue_client: cpMatch ? adresse.trim().slice(0, cpMatch.index).trim() : adresse.trim() || null,
          cp_client: cpMatch ? cpMatch[1] : null,
          ville_client: cpMatch ? adresse.trim().slice((cpMatch.index ?? 0) + cpMatch[1].length).replace(/^[\s,]+/, '').trim() : null,
          nom_emetteur: eleveurInfo.nom,
          siret_emetteur: eleveurInfo.siret ?? null,
          email_emetteur: eleveurInfo.email ?? null,
          statut: 'emise',
        });
      } catch (e) {
        // Le PDF reste rattaché à l'animal même si l'insert échoue ; on prévient
        // que la facture n'est pas apparue dans « Mes factures ».
        console.error('[cession] insert factures échoué :', e);
        setError(`Facture créée, mais non ajoutée à « Mes factures » : ${e}`);
      }

      reloadDocs();
      window.open(URL.createObjectURL(blob), '_blank');
    } catch (e) {
      setError(`Erreur facture : ${e}`);
    } finally {
      setGeneratingFacture(false);
    }
  }

  async function save() {
    if (!nomComplet && !searchResult) { setError('Le nom de l\'acquéreur est requis.'); return; }
    if (!dateCession) { setError('La date de cession est requise.'); return; }
    setSaving(true);
    setError('');
    try {
      const finalContratUrl    = contratUrl    || selectedContrat?.url    || null;
      const finalCertificatUrl = certificatUrl || selectedCertificat?.url || null;

      const sterilOn = !isReCession && sterilRequise && !!sterilEcheance;
      const sterilEcheanceStr = sterilEcheance ? sterilEcheance.toISOString().split('T')[0] : null;

      // Profil de l'acquéreur qui recevra l'animal (particulier, pas pension…)
      const acqProfileId = await resolveAcquereurProfileId(searchResult?.uid ?? null, qualite);

      // Aucun document → cession directe (animal cédé tout de suite)
      const hasDocuments = !!finalContratUrl || !!finalCertificatUrl
        || !!selectedContrat || !!selectedCertificat
        || existingContrats.length > 0 || existingCertificats.length > 0;
      const finaliseNow = !isReCession && !hasDocuments;

      const { error: animalUpdateError } = await supabase.from('animaux').update({
        statut:                 finaliseNow ? 'sorti' : 'en_attente_cession',
        date_sortie:            dateCession,
        destinataire_qualite:   qualite,
        destinataire_nom:       nomComplet,
        destinataire_adresse:   adresse.trim() || null,
        uid_acquereur:          searchResult?.uid ?? null,
        ...(acqProfileId ? { profile_id_acquereur: acqProfileId } : {}),
        cession_contrat_url:    finalContratUrl,
        cession_certificat_url: finalCertificatUrl,
        cession_prix:           prix ? parseFloat(prix) : null,
        cession_notes:          notes.trim() || null,
        sterilisation_requise:  sterilOn,
        ...(sterilOn ? {
          sterilisation_echeance:           sterilEcheanceStr,
          sterilisation_validee:            false,
          sterilisation_eleveur_uid:        uid,
          ...(profileId ? { sterilisation_eleveur_profile_id: profileId } : {}),
        } : {}),
      }).eq('id', animal.id);
      if (animalUpdateError) throw animalUpdateError;

      // Enregistrer les mouvements dans le registre
      const acqUid = searchResult?.uid ?? null;
      // Sortie pour le cédant
      await supabase.from('registre_mouvements').insert({
        animal_id:             animal.id,
        uid_eleveur:           uid,
        ...(profileId ? { eleveur_profile_id: profileId } : {}),
        type:                  'sortie',
        date_mouvement:        dateCession,
        motif:                 'cession',
        destinataire_qualite:  qualite,
        destinataire_nom:      nomComplet || null,
        destinataire_adresse:  adresse.trim() || null,
      });
      // Entrée pour l'acquéreur s'il a un compte éleveur ou association
      if (acqUid && (qualite === 'eleveur' || qualite === 'refuge')) {
        const { data: acqProfRow } = await supabase.from('user_profiles')
          .select('id').eq('uid', acqUid).eq('is_main', true).maybeSingle();
        const acqProfileId = (acqProfRow as { id: string } | null)?.id ?? null;
        await supabase.from('registre_mouvements').insert({
          animal_id:         animal.id,
          uid_eleveur:       acqUid,
          ...(acqProfileId ? { eleveur_profile_id: acqProfileId } : {}),
          type:              'entree',
          date_mouvement:    dateCession,
          motif:             'cession',
          provenance_qualite: 'eleveur',
          provenance_nom:    eleveurInfo.nom,
          provenance_adresse: eleveurInfo.adresse ?? null,
        });
      }

      // Résoudre le profil (is_main) de l'acquéreur — utilisé pour la notification
      // ci-dessous. NB : le transfert de propriété dans animaux_proprietes
      // (clôture cédant + ouverture acquéreur, date_debut/date_fin) n'a lieu
      // qu'à la cession DÉFINITIVE, une fois le contrat signé par les deux
      // parties — voir signer-contrat/[token]/page.tsx. Le faire ici, dès
      // 'en_attente_cession', ferait apparaître l'animal comme "ancien" dans
      // la liste alors que la fiche permet encore d'annuler/recéder.
      const acqProfile: { id: string } | null = acqProfileId ? { id: acqProfileId } : null;

      // Cession directe (aucun document) → transfert de propriété immédiat
      if (finaliseNow && acqUid) {
        await supabase.from('animaux_proprietes').update({ date_fin: dateCession })
          .eq('animal_id', animal.id).eq('uid_proprio', uid).is('date_fin', null);
        await supabase.from('animaux_proprietes').upsert({
          animal_id:          animal.id,
          uid_proprio:        acqUid,
          date_debut:         dateCession,
          date_fin:           null,
          profile_id_proprio: acqProfileId,
        }, { onConflict: 'animal_id,uid_proprio' });
      }

      // Certificat de bonne santé vétérinaire → documents_animaux
      if (santeUrl) {
        await supabase.from('documents_animaux').insert({
          animal_id:  animal.id,
          uid_eleveur: uid,
          type:       'certificat_sante',
          titre:      `Certificat de bonne santé — ${animal.nom ?? 'animal'}`,
          url:        santeUrl,
          statut:     'signe',
        });
      }

      // Notifier l'acquéreur si c'est un utilisateur PetsMatch
      if (searchResult?.uid) {
        await supabase.from('notifications').insert({
          uid:   searchResult.uid,
          type:  'cession_animal',
          title: `🐾 Animal reçu : ${animal.nom ?? 'Animal'}`,
          body:  `${eleveurInfo.nom} vous a cédé ${animal.nom ?? 'un animal'}. Consultez vos animaux pour voir sa fiche.`,
          ...(acqProfile?.id ? { profile_id: acqProfile.id } : {}),
          data:  { animalId: animal.id },
          read:  false,
        });
      }

      // Clôturer la réservation d'origine s'il y en avait une
      if (reservation?.id) {
        await supabase.from('reservations_animaux')
          .update({ statut: 'transformee', updated_at: new Date().toISOString() })
          .eq('id', reservation.id);
      }

      onCeded();
    } catch (e) {
      setError(`Erreur : ${e}`);
      setSaving(false);
    }
  }

  const cessionData: CessionData = { qualite, nom: nomComplet, email, tel, adresse, dateCession, prix, notes, uid_acquereur: searchResult?.uid ?? null };

  // Cession éleveur : prénom + nom + email + téléphone + adresse obligatoires.
  const reqMark = isReCession ? '' : ' *';
  const detailsValid = !!dateCession && !!nom.trim() && (isReCession || (
    !!prenom.trim() && !!email.trim() && !!tel.trim() && !!adresse.trim() &&
    (!sterilRequise || (parseInt(sterilAgeMois, 10) || 0) > 0)
  ));

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
                {!isReCession && (
                  <div>
                    <label className="block text-xs font-semibold text-gray-500 mb-1">Prix (€)</label>
                    <input type="number" min="0" placeholder="0" value={prix} onChange={e => setPrix(e.target.value)}
                      className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                  </div>
                )}
              </div>

              <div>
                <label className="block text-xs font-semibold text-gray-500 mb-1">Qualité de l'acquéreur</label>
                <div className="flex flex-wrap gap-2">
                  {(isReCession ? QUALITES_RECESSION : QUALITES_FULL).map(q => (
                    <button key={q.value} onClick={() => setQualite(q.value)}
                      className={`px-3 py-1.5 rounded-full text-xs font-semibold border transition-colors ${qualite === q.value ? 'bg-[#0C5C6C] text-white border-[#0C5C6C]' : 'bg-white text-gray-600 border-gray-200'}`}>
                      {q.label}
                    </button>
                  ))}
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-gray-500 mb-1">Prénom{reqMark}</label>
                  <input type="text" placeholder="Prénom" value={prenom} onChange={e => setPrenom(e.target.value)}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-gray-500 mb-1">Nom{reqMark}</label>
                  <input type="text" placeholder="Nom" value={nom} onChange={e => setNom(e.target.value)}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3">
                <div>
                  <label className="block text-xs font-semibold text-gray-500 mb-1">Email{reqMark}</label>
                  <input type="email" placeholder="email@exemple.fr" value={email} onChange={e => setEmail(e.target.value)}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                </div>
                <div>
                  <label className="block text-xs font-semibold text-gray-500 mb-1">Téléphone{reqMark}</label>
                  <input type="tel" placeholder="06 XX XX XX XX" value={tel} onChange={e => setTel(e.target.value)}
                    className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                </div>
              </div>

              <div className="relative">
                <label className="block text-xs font-semibold text-gray-500 mb-1">Adresse postale{reqMark}</label>
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

              {/* ── Condition de stérilisation (cession éleveur) ── */}
              {!isReCession && (
                <div className="rounded-xl border border-[#6E9E57]/30 bg-[#6E9E57]/5 p-3 space-y-2">
                  <label className="flex items-start gap-2 cursor-pointer">
                    <input type="checkbox" checked={sterilRequise} disabled={!dateNaissance}
                      onChange={e => setSterilRequise(e.target.checked)}
                      className="mt-0.5 accent-[#6E9E57] w-4 h-4" />
                    <span>
                      <span className="block text-sm font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey,sans-serif' }}>Condition de stérilisation</span>
                      <span className="block text-[11px] text-gray-500">
                        {dateNaissance
                          ? "Le nouveau propriétaire devra faire stériliser l'animal avant l'âge fixé."
                          : "Renseignez la date de naissance de l'animal pour activer cette condition."}
                      </span>
                    </span>
                  </label>
                  {sterilRequise && (
                    <div className="pl-6 space-y-1.5">
                      <div className="flex items-center gap-2">
                        <input type="number" min={1} value={sterilAgeMois} onChange={e => setSterilAgeMois(e.target.value)}
                          className="w-20 border border-gray-200 rounded-lg px-2 py-1.5 text-sm focus:outline-none focus:border-[#0C5C6C]" />
                        <span className="text-sm text-[#1F2A2E]">mois maximum</span>
                      </div>
                      <p className="text-xs font-semibold text-[#0C5C6C]">
                        {sterilEcheance ? `📅 Échéance : ${sterilEcheance.toLocaleDateString('fr-FR')}` : 'Saisissez un âge en mois valide.'}
                      </p>
                    </div>
                  )}
                </div>
              )}

              <div className="flex gap-2 pt-2">
                <button onClick={() => setStep('acquéreur')}
                  className="flex-1 border border-gray-200 text-gray-600 font-semibold py-2.5 rounded-xl text-sm hover:bg-gray-50 transition-colors">
                  ← Retour
                </button>
                <button
                  onClick={() => isReCession ? save() : setStep('documents')}
                  disabled={!detailsValid || saving}
                  className="flex-1 bg-[#0C5C6C] text-white font-semibold py-2.5 rounded-xl text-sm hover:bg-[#094F5D] disabled:opacity-40 transition-colors">
                  {isReCession ? (saving ? 'Enregistrement…' : 'Confirmer le transfert') : 'Documents →'}
                </button>
              </div>
              {!isReCession && (
                <button
                  onClick={save}
                  disabled={!detailsValid || saving}
                  className="w-full text-xs font-medium text-[#0C5C6C] hover:underline disabled:opacity-40 disabled:no-underline">
                  {saving ? 'Enregistrement…' : 'Valider sans document (remise en main propre)'}
                </button>
              )}
            </>
          )}

          {/* ── Étape 3 : Documents ─────────────────────────────────── */}
          {step === 'documents' && (
            <>
              {loadingDocs ? (
                <p className="text-xs text-gray-400 text-center py-4">Chargement des documents…</p>
              ) : (
                <>
                  {/* ── Certificat de cession ── */}
                  <div className="flex items-center justify-between">
                    <p className="text-xs font-semibold text-[#1F2A2E]">📜 Certificat de cession / engagement</p>
                    <button onClick={() => openContratCreation('certificat_cession')}
                      className="text-xs font-semibold text-[#0C5C6C] hover:underline">
                      + Créer un certificat
                    </button>
                  </div>
                  {existingCertificats.length === 0 ? (
                    <p className="text-xs text-gray-400 italic">Aucun certificat existant — cliquez sur &ldquo;Créer un certificat&rdquo; ci-dessus.</p>
                  ) : (
                    <div className="space-y-1.5">
                      {existingCertificats.map(d => {
                        const sel = selectedCertificat?.id === d.id;
                        const label = d.statut === 'signe' ? '✅ Signé' : d.statut === 'partiellement_signe' ? '✍️ Partiel' : d.statut === 'en_attente' ? '⏳ En attente' : '📝 Brouillon';
                        const date = d.created_at ? new Date(d.created_at).toLocaleDateString('fr-FR') : '';
                        return (
                          <div key={d.id} className={`flex items-center gap-1 rounded-xl border transition-colors ${sel ? 'border-green-500 bg-green-50' : 'border-gray-200 hover:border-gray-300'}`}>
                            <button onClick={() => setSelectedCertificat(sel ? null : d)}
                              className="flex-1 flex items-center gap-2 px-3 py-2 text-left">
                              <span className="text-sm">{sel ? '🔵' : '⚪'}</span>
                              <div className="flex-1 min-w-0">
                                <p className="text-xs font-semibold text-[#1F2A2E]">Certificat de cession</p>
                                <p className="text-[10px] text-gray-500">{label}{date ? `  ·  ${date}` : ''}</p>
                              </div>
                            </button>
                            <a href={`/signer-contrat/${(d as {id:string;token?:string}).token ?? d.id}`} target="_blank" rel="noreferrer"
                              className="p-2 text-gray-400 hover:text-[#0C5C6C]" title="Ouvrir">
                              <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" /></svg>
                            </a>
                            <button onClick={async () => { if (confirm('Supprimer ce certificat ?')) { await supabase.from('documents_animaux').delete().eq('id', d.id); if (sel) setSelectedCertificat(null); reloadDocs(); } }}
                              className="p-2 text-gray-300 hover:text-red-500" title="Supprimer">
                              <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>
                            </button>
                          </div>
                        );
                      })}
                    </div>
                  )}
                  <div className="flex gap-3">
                    <input ref={certificatRef} type="file" accept=".pdf,.jpg,.jpeg,.png" className="hidden"
                      onChange={e => { if (e.target.files?.[0]) uploadDoc(e.target.files[0], 'certificat'); }} />
                    <button onClick={() => certificatRef.current?.click()} disabled={uploadingCertificat}
                      className="text-[#0C5C6C] text-xs hover:underline">
                      {uploadingCertificat ? '⏳…' : certificatUrl ? '✓ Importé · Remplacer' : '⬆️ Importer PDF'}
                    </button>
                  </div>

                  <hr className="my-1 border-gray-100" />

                  {/* ── Contrat de vente ── */}
                  <div className="flex items-center justify-between">
                    <p className="text-xs font-semibold text-[#1F2A2E]">🤝 Contrat de vente / réservation</p>
                    <button onClick={() => openContratCreation('contrat_vente')}
                      className="text-xs font-semibold text-[#0C5C6C] hover:underline flex items-center gap-1">
                      + Créer un contrat
                    </button>
                  </div>
                  {existingContrats.length === 0 ? (
                    <p className="text-xs text-gray-400 italic">Aucun contrat existant — cliquez sur &ldquo;Créer un contrat&rdquo; ci-dessus.</p>
                  ) : (
                    <div className="space-y-1.5">
                      {existingContrats.map(d => {
                        const sel = selectedContrat?.id === d.id;
                        const typeLabel = d.type === 'contrat_reservation' ? 'Contrat de réservation' : 'Contrat de vente';
                        const label = d.statut === 'signe' ? '✅ Signé' : d.statut === 'partiellement_signe' ? '✍️ Partiel' : d.statut === 'en_attente' ? '⏳ En attente' : '📝 Brouillon';
                        const date = d.created_at ? new Date(d.created_at).toLocaleDateString('fr-FR') : '';
                        return (
                          <div key={d.id} className={`flex items-center gap-1 rounded-xl border transition-colors ${sel ? 'border-green-500 bg-green-50' : 'border-gray-200 hover:border-gray-300'}`}>
                            <button onClick={() => setSelectedContrat(sel ? null : d)}
                              className="flex-1 flex items-center gap-2 px-3 py-2 text-left">
                              <span className="text-sm">{sel ? '🔵' : '⚪'}</span>
                              <div className="flex-1 min-w-0">
                                <p className="text-xs font-semibold text-[#1F2A2E]">{typeLabel}</p>
                                <p className="text-[10px] text-gray-500">{label}{date ? `  ·  ${date}` : ''}</p>
                              </div>
                            </button>
                            <a href={`/signer-contrat/${(d as {id:string;token?:string}).token ?? d.id}`} target="_blank" rel="noreferrer"
                              className="p-2 text-gray-400 hover:text-[#0C5C6C]" title="Ouvrir">
                              <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" /></svg>
                            </a>
                            <button onClick={async () => { if (confirm('Supprimer ce contrat ?')) { await supabase.from('documents_animaux').delete().eq('id', d.id); if (sel) setSelectedContrat(null); reloadDocs(); } }}
                              className="p-2 text-gray-300 hover:text-red-500" title="Supprimer">
                              <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>
                            </button>
                          </div>
                        );
                      })}
                    </div>
                  )}
                  <div className="flex gap-3">
                    <input ref={contratRef} type="file" accept=".pdf,.jpg,.jpeg,.png" className="hidden"
                      onChange={e => { if (e.target.files?.[0]) uploadDoc(e.target.files[0], 'contrat'); }} />
                    <button onClick={() => contratRef.current?.click()} disabled={uploadingContrat}
                      className="text-[#0C5C6C] text-xs hover:underline">
                      {uploadingContrat ? '⏳…' : contratUrl ? '✓ Importé · Remplacer' : '⬆️ Importer PDF'}
                    </button>
                  </div>

                  <hr className="my-1 border-gray-100" />

                  {/* ── Certificat de bonne santé vétérinaire ── */}
                  <p className="text-xs font-semibold text-[#1F2A2E]">🩺 Certificat de bonne santé <span className="font-normal text-gray-400">(vétérinaire)</span></p>
                  <p className="text-[10px] text-gray-400">PDF uniquement — délivré par le vétérinaire.</p>
                  <div className="flex items-center gap-3">
                    <input ref={santeRef} type="file" accept=".pdf" className="hidden"
                      onChange={e => { if (e.target.files?.[0]) uploadDoc(e.target.files[0], 'sante'); }} />
                    <button onClick={() => santeRef.current?.click()} disabled={uploadingSante}
                      className={`flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-xl border transition-colors ${santeUrl ? 'border-green-400 text-green-700 bg-green-50' : 'border-gray-200 text-[#0C5C6C] hover:border-[#0C5C6C]'}`}>
                      {uploadingSante ? '⏳ Upload…' : santeUrl ? '✅ PDF importé · Remplacer' : '⬆️ Importer PDF'}
                    </button>
                  </div>

                  <hr className="my-1 border-gray-100" />

                  {/* ── Facture (optionnel) ── */}
                  <p className="text-xs font-semibold text-[#1F2A2E]">🧾 Facture <span className="font-normal text-gray-400">(optionnel)</span></p>
                  {existingFactures.length > 0 && (
                    <div className="space-y-1.5">
                      {existingFactures.map(d => {
                        const date = d.created_at ? new Date(d.created_at).toLocaleDateString('fr-FR') : '';
                        return (
                          <div key={d.id} className="flex items-center gap-1 rounded-xl border border-gray-200">
                            <div className="flex-1 min-w-0 px-3 py-2">
                              <p className="text-xs font-semibold text-[#1F2A2E] truncate">{d.titre ?? 'Facture'}</p>
                              <p className="text-[10px] text-gray-500">🧾 Facture générée{date ? `  ·  ${date}` : ''}</p>
                            </div>
                            {d.url && (
                              <a href={d.url} target="_blank" rel="noreferrer" className="p-2 text-gray-400 hover:text-[#0C5C6C]" title="Ouvrir">
                                <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" /></svg>
                              </a>
                            )}
                            <button onClick={async () => { if (confirm('Supprimer cette facture ?')) { await supabase.from('documents_animaux').delete().eq('id', d.id); reloadDocs(); } }}
                              className="p-2 text-gray-300 hover:text-red-500" title="Supprimer">
                              <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" /></svg>
                            </button>
                          </div>
                        );
                      })}
                    </div>
                  )}
                  <button onClick={genererFacture} disabled={generatingFacture}
                    className="text-[#0C5C6C] text-xs font-semibold hover:underline disabled:opacity-50">
                    {generatingFacture ? '⏳ Génération…' : '🧾 Générer la facture (montant = prix)'}
                  </button>
                </>
              )}

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
