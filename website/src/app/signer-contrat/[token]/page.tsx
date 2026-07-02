'use client';

import { use, useEffect, useRef, useState } from 'react';
import { createClient } from '@supabase/supabase-js';
import {
  generateContratHTML, generateContratReservationHTML, generateCertificatCessionHTML,
  generateContratSaillieHTML,
  AnimalContrat, DataContrat, EleveurContrat,
} from '@/lib/contrat-vente';
import { generateContratAdoptionHTML } from '@/lib/contrat-adoption';
import { generateContratHebergementHTML } from '@/lib/contrat-pension';
import { useAuth } from '@/lib/auth-context';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

type FemelleRow = {
  id: string;
  nom?: string;
  race?: string;
  couleur?: string;
  identification?: string;
  date_naissance?: string;
  pedigree_numero?: string;
  pedigree_lof?: string;
};

type DocStatut = 'brouillon' | 'en_attente' | 'signe' | 'archive' | 'partiellement_signe' | 'annule' | 'expire' | 'refuse';

interface DocRow {
  id: string;
  animal_id: string;
  pension_entree_id?: string;
  uid_eleveur: string;
  type: string;
  titre: string;
  statut: DocStatut;
  signe_le: string | null;
  pdf_signe_url: string | null;
  rejection_reason: string | null;
  metadata: Record<string, string>;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  animaux: any;
}

export default function SignerContratPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = use(params);
  const { user }  = useAuth();
  const [doc, setDoc]       = useState<DocRow | null>(null);
  const [html, setHtml]     = useState('');
  const [status, setStatus] = useState<'loading' | 'ready' | 'not_found'>('loading');
  const [saving, setSaving]       = useState<'eleveur' | 'acquereur' | null>(null);
  const [saved, setSaved]         = useState<{ eleveur?: boolean; acquereur?: boolean }>({});
  const [refuseModal, setRefuseModal] = useState(false);
  const [refuseReason, setRefuseReason] = useState('');
  const [refusing, setRefusing]   = useState(false);
  // Données stockées pour re-générer le HTML saillie après sélection femelle
  const [eleveurStored, setEleveurStored]         = useState<EleveurContrat | null>(null);
  const [animalStored, setAnimalStored]           = useState<AnimalContrat | null>(null);
  const [dataContratStored, setDataContratStored] = useState<DataContrat | null>(null);
  // Sélecteur femelle (contrepartie connectée, contrat saillie)
  const [femelles, setFemelles]           = useState<FemelleRow[]>([]);
  const [selectedFemId, setSelectedFemId] = useState('');
  const [loadingFemelles, setLoadingFemelles] = useState(false);
  const [femelleSaved, setFemelleSaved]   = useState(false);
  const [savingFemelle, setSavingFemelle] = useState(false);
  // Correction coordonnées acquéreur
  const [editContact, setEditContact]     = useState(false);
  const [contactNom, setContactNom]       = useState('');
  const [contactPrenom, setContactPrenom] = useState('');
  const [contactAdresse, setContactAdresse] = useState('');
  const [contactTel, setContactTel]       = useState('');
  const [savingContact, setSavingContact] = useState(false);
  const canvasElvRef        = useRef<HTMLCanvasElement>(null);
  const canvasAcqRef        = useRef<HTMLCanvasElement>(null);
  const drawingElv          = useRef(false);
  const drawingAcq          = useRef(false);

  useEffect(() => {
    async function load() {
      const { data } = await supabase
        .from('documents_animaux')
        .select('*, animaux(nom,espece,race,sexe,identification,date_naissance,couleur,pedigree_numero,pedigree_lof,nom_pere,puce_pere,nom_mere,puce_mere)')
        .eq('token', token)
        .maybeSingle();

      if (!data) { setStatus('not_found'); return; }

      const { data: profil } = await supabase
        .from('users')
        .select('firstname,lastname,name_elevage,adress_elevage,adress,siret,numero_elevage,code_iso_elevage,email,ville_elevage,ville,phone_number,code_iso')
        .eq('uid', data.uid_eleveur)
        .maybeSingle();

      const meta = (data.metadata ?? {}) as Record<string, string>;
      const elvNom  = profil?.name_elevage || `${profil?.firstname ?? ''} ${profil?.lastname ?? ''}`.trim() || 'Éleveur';
      const elvTel  = profil ? `${profil.code_iso_elevage ?? '+33'} ${profil.numero_elevage ?? ''}`.trim() : '';
      const villeElevage = profil?.ville_elevage ?? profil?.ville ?? '';

      const eleveur: EleveurContrat = {
        nom: elvNom,
        adresse: profil?.adress_elevage ?? profil?.adress ?? '',
        siret: profil?.siret ?? '',
        email: profil?.email ?? '',
        tel: elvTel,
      };
      const animal: AnimalContrat = {
        nom: data.animaux?.nom ?? '',
        espece: data.animaux?.espece ?? '',
        race: data.animaux?.race ?? '',
        sexe: data.animaux?.sexe ?? '',
        identification: data.animaux?.identification ?? '',
        date_naissance: data.animaux?.date_naissance ?? '',
        couleur: data.animaux?.couleur ?? '',
        pedigree_numero: data.animaux?.pedigree_numero ?? '',
        pedigree_lof: data.animaux?.pedigree_lof ?? '',
        nom_pere: data.animaux?.nom_pere ?? '',
        puce_pere: data.animaux?.puce_pere ?? '',
        nom_mere: data.animaux?.nom_mere ?? '',
        puce_mere: data.animaux?.puce_mere ?? '',
        ville_naissance: villeElevage,
      };
      const dataContrat: DataContrat = {
        nom: meta.acquereur_nom ?? '',
        email: meta.acquereur_email ?? '',
        tel: meta.acquereur_tel ?? '',
        adresse: meta.acquereur_adresse ?? '',
        prix: meta.prix ?? '',
        dateCession: meta.date_cession ?? '',
        notes: meta.notes ?? '',
      };
      const opts = {
        animalId: '',
        supabaseUrl: '',
        supabaseKey: '',
        avecSterilisation: (meta as Record<string, unknown>).avec_sterilisation !== false,
      };

      let generatedHtml = '';
      if (data.type === 'contrat_hebergement') {
        const { data: entree } = await supabase
          .from('pension_entrees')
          .select('animal_nom, espece, race, proprietaire_nom, proprietaire_contact, date_entree, date_sortie_prevue')
          .eq('id', data.pension_entree_id)
          .maybeSingle();
        generatedHtml = generateContratHebergementHTML(
          entree ?? { animal_nom: meta.acquereur_nom ?? '' },
          {
            nom: elvNom,
            adresse: profil?.adress_elevage ?? profil?.adress ?? '',
            email: profil?.email ?? '',
            tel: elvTel,
            siret: profil?.siret ?? '',
          },
          {
            tarifNuit: meta.tarif_nuit,
            arrhesPourcentage: meta.arrhes_pourcentage ? Number(meta.arrhes_pourcentage) : undefined,
            logementNom: meta.logement_nom,
            notes: meta.notes,
          },
        );
      } else if (data.type === 'contrat_adoption') {
        const assoInfo = {
          nom: meta.asso_nom ?? elvNom,
          adresse: meta.asso_adresse ?? profil?.adress_elevage ?? '',
          tel: meta.asso_tel ?? elvTel,
          email: meta.asso_email ?? profil?.email ?? '',
          siret: meta.asso_siret ?? profil?.siret ?? '',
        };
        const adoptant = {
          nom: meta.acquereur_nom ?? '',
          prenom: meta.acquereur_prenom ?? '',
          adresse: meta.acquereur_adresse ?? '',
          tel: meta.acquereur_tel ?? '',
          email: meta.acquereur_email ?? '',
        };
        const dataAdoption = {
          participation: meta.participation ?? '',
          dateContrat: meta.dateContrat ?? meta.date_cession ?? '',
          avecSteril: meta.avecSteril === 'true',
          notes: meta.notes ?? '',
          acquereur_email: meta.acquereur_email ?? '',
        };
        generatedHtml = generateContratAdoptionHTML(assoInfo, animal, adoptant, dataAdoption, {
          signatureEleveur: meta.signature_eleveur,
          signatureAcquereur: meta.signature_acquereur,
        });
      } else if (data.type === 'contrat_reservation') {
        generatedHtml = generateContratReservationHTML(animal, dataContrat, eleveur, opts);
      } else if (data.type === 'certificat_cession') {
        generatedHtml = generateCertificatCessionHTML(animal, dataContrat, eleveur, { ...opts, eleveurUid: data.uid_eleveur });
      } else if (data.type === 'contrat_saillie') {
        generatedHtml = generateContratSaillieHTML(animal, dataContrat, eleveur, opts);
      } else {
        generatedHtml = generateContratHTML(animal, dataContrat, eleveur, opts);
      }

      // Pré-remplir les canvases depuis les signatures sauvegardées
      const sigElv = meta.signature_eleveur;
      const sigAcq = meta.signature_acquereur;
      if (sigElv || sigAcq) {
        setSaved({ eleveur: !!sigElv, acquereur: !!sigAcq });
      }
      // Charger les images après que les canvas sont montés
      if (sigElv) setTimeout(() => drawSavedSig(canvasElvRef, sigElv), 100);
      if (sigAcq) setTimeout(() => drawSavedSig(canvasAcqRef, sigAcq), 100);

      setEleveurStored(eleveur);
      setAnimalStored(animal);
      setDataContratStored(dataContrat);
      if (meta.femelle_animal_id) setFemelleSaved(true);
      // Pré-remplir les champs contact acquéreur
      setContactNom(meta.acquereur_nom ?? '');
      setContactPrenom(meta.acquereur_prenom ?? '');
      setContactAdresse(meta.acquereur_adresse ?? '');
      setContactTel(meta.acquereur_tel ?? '');
      setDoc(data as DocRow);
      setHtml(generatedHtml);
      setStatus('ready');
    }
    load();
  }, [token]);

  // Charger les femelles de la contrepartie si elle est connectée et c'est un contrat de saillie
  useEffect(() => {
    if (!doc || !user || doc.type !== 'contrat_saillie') return;
    if (user.email !== doc.metadata?.acquereur_email) return;
    if (doc.metadata?.femelle_animal_id) return;
    setLoadingFemelles(true);
    supabase
      .from('animaux')
      .select('id, nom, race, couleur, identification, date_naissance, pedigree_numero, pedigree_lof')
      .eq('uid_eleveur', user.uid)
      .eq('espece', doc.animaux?.espece ?? '')
      .then(({ data }) => {
        setFemelles((data ?? []) as FemelleRow[]);
        setLoadingFemelles(false);
      });
  }, [doc, user]);

  function drawSavedSig(ref: React.RefObject<HTMLCanvasElement | null>, dataUrl: string) {
    const canvas = ref.current;
    if (!canvas) return;
    const img = new window.Image();
    img.onload = () => canvas.getContext('2d')?.drawImage(img, 0, 0);
    img.src = dataUrl;
  }

  function makeDrawHandlers(ref: React.RefObject<HTMLCanvasElement | null>, drawing: React.MutableRefObject<boolean>) {
    function getPos(e: React.MouseEvent | React.TouchEvent) {
      const canvas = ref.current!;
      const rect = canvas.getBoundingClientRect();
      const scaleX = canvas.width / rect.width;
      const scaleY = canvas.height / rect.height;
      const src = 'touches' in e ? e.touches[0] : e;
      return { x: (src.clientX - rect.left) * scaleX, y: (src.clientY - rect.top) * scaleY };
    }
    return {
      onMouseDown: (e: React.MouseEvent) => {
        drawing.current = true;
        const ctx = ref.current!.getContext('2d')!;
        ctx.beginPath(); const p = getPos(e); ctx.moveTo(p.x, p.y);
      },
      onMouseMove: (e: React.MouseEvent) => {
        if (!drawing.current) return;
        const ctx = ref.current!.getContext('2d')!;
        ctx.lineWidth = 2; ctx.strokeStyle = '#1F2A2E'; ctx.lineCap = 'round';
        const p = getPos(e); ctx.lineTo(p.x, p.y); ctx.stroke();
      },
      onMouseUp: () => { drawing.current = false; },
      onMouseLeave: () => { drawing.current = false; },
      onTouchStart: (e: React.TouchEvent) => {
        e.preventDefault(); drawing.current = true;
        const ctx = ref.current!.getContext('2d')!;
        ctx.beginPath(); const p = getPos(e); ctx.moveTo(p.x, p.y);
      },
      onTouchMove: (e: React.TouchEvent) => {
        e.preventDefault();
        if (!drawing.current) return;
        const ctx = ref.current!.getContext('2d')!;
        ctx.lineWidth = 2; ctx.strokeStyle = '#1F2A2E'; ctx.lineCap = 'round';
        const p = getPos(e); ctx.lineTo(p.x, p.y); ctx.stroke();
      },
      onTouchEnd: () => { drawing.current = false; },
    };
  }

  async function signer(role: 'eleveur' | 'acquereur') {
    const canvas = role === 'eleveur' ? canvasElvRef.current : canvasAcqRef.current;
    if (!canvas || !doc) return;
    const dataUrl = canvas.toDataURL('image/png');
    // Vérifier qu'il y a bien une signature (non-blanc)
    const ctx = canvas.getContext('2d');
    const imgData = ctx?.getImageData(0, 0, canvas.width, canvas.height);
    const hasInk = imgData && Array.from(imgData.data).some((v, i) => i % 4 === 3 && v > 0);
    if (!hasInk) { alert('Veuillez dessiner votre signature avant de valider.'); return; }

    setSaving(role);
    const now = new Date().toISOString();
    const sigField  = role === 'eleveur' ? 'signature_eleveur'  : 'signature_acquereur';
    const dateField = role === 'eleveur' ? 'signe_eleveur_le'   : 'signe_acquereur_le';
    const newSaved  = { ...saved, [role]: true };
    const bothSigned = newSaved.eleveur && newSaved.acquereur;
    const newStatut: DocStatut = bothSigned ? 'signe'
      : (newSaved.eleveur || newSaved.acquereur) ? 'partiellement_signe'
      : 'en_attente';

    await supabase.from('documents_animaux').update({
      metadata: { ...doc.metadata, [sigField]: dataUrl, [dateField]: now },
      statut:   newStatut,
      ...(bothSigned ? { signe_le: now } : {}),
    }).eq('token', token);

    // Quand le contrat de cession est entièrement signé → finaliser le transfert de l'animal
    if (bothSigned && (doc.type === 'contrat_vente' || doc.type === 'certificat_cession') && doc.animal_id) {
      await supabase.from('animaux').update({ statut: 'sorti' }).eq('id', doc.animal_id).eq('statut', 'en_attente_cession');
    }

    // Notifications inter-parties
    const acqEmail  = doc.metadata?.acquereur_email;
    const acqNom    = doc.metadata?.acquereur_nom || 'L\'acquéreur';
    const titre     = doc.titre ?? 'le contrat';
    const signingUrl = `${window.location.origin}/signer-contrat/${token}`;

    if (bothSigned) {
      // Les deux ont signé → notifier les deux
      fetch('/api/notifications', { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ uid: doc.uid_eleveur, type: 'contrat_signe_complet', title: '✅ Contrat signé !',
          body: `${acqNom} a apposé sa signature — ${titre} est désormais signé par les deux parties.`,
          data: { token } }) });
      if (acqEmail) fetch('/api/notifications', { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: acqEmail, type: 'contrat_signe_complet', title: '✅ Contrat signé !',
          body: `L'éleveur a apposé sa signature — ${titre} est désormais signé par les deux parties.`,
          data: { token, url: signingUrl } }) });
    } else if (role === 'acquereur') {
      // Acquéreur vient de signer → notifier l'éleveur
      fetch('/api/notifications', { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ uid: doc.uid_eleveur, type: 'contrat_signe_acquereur', title: '✍️ Signature reçue',
          body: `${acqNom} a signé ${titre} — à vous de signer pour finaliser.`,
          data: { token } }) });
    } else {
      // Éleveur vient de signer → notifier l'acquéreur
      if (acqEmail) fetch('/api/notifications', { method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: acqEmail, type: 'contrat_signe_eleveur', title: '✍️ L\'éleveur a signé',
          body: `L'éleveur a signé ${titre} — à vous de signer pour finaliser.`,
          data: { token, url: signingUrl } }) });
    }

    setDoc(prev => prev ? { ...prev, statut: newStatut, ...(bothSigned ? { signe_le: now } : {}), metadata: { ...prev.metadata, [sigField]: dataUrl, [dateField]: now } } : prev);
    setSaved(newSaved);
    setSaving(null);
  }

  function clearCanvas(ref: React.RefObject<HTMLCanvasElement | null>) {
    const c = ref.current;
    if (!c) return;
    c.getContext('2d')?.clearRect(0, 0, c.width, c.height);
  }

  async function saveFemelle() {
    if (!doc || !selectedFemId || !animalStored || !eleveurStored || !dataContratStored) return;
    const femelle = femelles.find(f => f.id === selectedFemId);
    if (!femelle) return;
    setSavingFemelle(true);
    const femelleData = {
      femelle_animal_id:      femelle.id,
      femelle_nom:            femelle.nom ?? '',
      femelle_race:           femelle.race ?? '',
      femelle_couleur:        femelle.couleur ?? '',
      femelle_identification: femelle.identification ?? '',
      femelle_pedigree:       femelle.pedigree_numero ?? femelle.pedigree_lof ?? '',
      femelle_naissance:      femelle.date_naissance ?? '',
    };
    await supabase.from('documents_animaux').update({
      metadata: { ...doc.metadata, ...femelleData },
    }).eq('token', token);

    const newHtml = generateContratSaillieHTML(animalStored, dataContratStored, eleveurStored, {
      animalId: doc.animal_id,
      femelleData: {
        nom:            femelle.nom,
        race:           femelle.race,
        couleur:        femelle.couleur,
        identification: femelle.identification,
        pedigree:       femelle.pedigree_numero ?? femelle.pedigree_lof,
        naissance:      femelle.date_naissance,
      },
    });
    setDoc(prev => prev ? { ...prev, metadata: { ...prev.metadata, ...femelleData } } : prev);
    setHtml(newHtml);
    setFemelleSaved(true);
    setSavingFemelle(false);
  }

  async function refuser() {
    if (!doc) return;
    setRefusing(true);
    const reason = refuseReason.trim() || null;
    await fetch(`/api/contracts/${doc.id}/refuse`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ reason, actorEmail: doc.metadata?.acquereur_email ?? null }),
    });
    // Notifier l'éleveur du refus
    const acqNom = doc.metadata?.acquereur_nom || 'L\'acquéreur';
    fetch('/api/notifications', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ uid: doc.uid_eleveur, type: 'contrat_refuse', title: '❌ Contrat refusé',
        body: `${acqNom} a refusé ${doc.titre ?? 'le contrat'}${reason ? ` — ${reason}` : ''}.`,
        data: { token } }) });
    setDoc(prev => prev ? { ...prev, statut: 'refuse', rejection_reason: reason } : prev);
    setRefusing(false);
    setRefuseModal(false);
    if (window.opener) window.opener.postMessage({ type: 'contract_refused' }, '*');
  }

  async function saveContactAcquereur() {
    if (!doc) return;
    setSavingContact(true);
    const newMeta = {
      ...doc.metadata,
      acquereur_nom:     contactNom.trim(),
      acquereur_prenom:  contactPrenom.trim(),
      acquereur_adresse: contactAdresse.trim(),
      acquereur_tel:     contactTel.trim(),
    };
    await supabase.from('documents_animaux').update({ metadata: newMeta }).eq('id', doc.id);
    // Régénère le HTML avec les nouvelles coordonnées
    if (eleveurStored && animalStored) {
      const updatedData = { ...dataContratStored!, nom: contactNom.trim(), adresse: contactAdresse.trim(), tel: contactTel.trim() };
      let newHtml = '';
      if (doc.type === 'contrat_reservation') newHtml = generateContratReservationHTML(animalStored, updatedData, eleveurStored, {});
      else if (doc.type === 'certificat_cession') newHtml = generateCertificatCessionHTML(animalStored, updatedData, eleveurStored, { eleveurUid: doc.uid_eleveur });
      else if (doc.type === 'contrat_saillie') newHtml = generateContratSaillieHTML(animalStored, updatedData, eleveurStored, {});
      else newHtml = generateContratHTML(animalStored, updatedData, eleveurStored, {});
      if (newHtml) setHtml(newHtml);
    }
    setDoc(prev => prev ? { ...prev, metadata: newMeta } : prev);
    setSavingContact(false);
    setEditContact(false);
  }

  if (status === 'loading') return (
    <div className="flex items-center justify-center min-h-screen bg-gray-50">
      <div className="text-center">
        <div className="w-10 h-10 border-4 border-[#0C5C6C] border-t-transparent rounded-full animate-spin mx-auto mb-4" />
        <p className="text-gray-500 font-medium">Chargement du contrat…</p>
      </div>
    </div>
  );

  if (status === 'not_found') return (
    <div className="flex items-center justify-center min-h-screen bg-gray-50">
      <div className="text-center text-gray-400">
        <p className="text-5xl mb-4">📄</p>
        <p className="text-xl font-bold text-gray-600">Document introuvable</p>
        <p className="text-sm mt-2">Le lien est invalide ou expiré.</p>
      </div>
    </div>
  );

  const isSigned    = doc?.statut === 'signe';
  const isPartial   = doc?.statut === 'partiellement_signe';
  const isEnAttente = doc?.statut === 'en_attente';
  const isRefused   = doc?.statut === 'refuse';
  const isCancelled = doc?.statut === 'annule';
  const isExpired   = doc?.statut === 'expire';
  const isFinal     = isSigned || isRefused || isCancelled || isExpired;
  // Éleveur/propriétaire = peut modifier les champs du contrat. Acquéreur = lecture seule sur les champs vendeur.
  const isOwner = !!user && !!doc && user.uid === doc.uid_eleveur;
  const iframeHtml = isOwner ? html : html.replace(/contenteditable="true"/g, 'contenteditable="false"');
  const elvHandlers  = makeDrawHandlers(canvasElvRef,  drawingElv);
  const acqHandlers  = makeDrawHandlers(canvasAcqRef,  drawingAcq);

  function handlePrint() {
    if (!html) return;
    const sigElv = doc?.metadata?.signature_eleveur as string | undefined;
    const sigAcq = doc?.metadata?.signature_acquereur as string | undefined;

    // Parse le HTML du contrat et injecte les signatures dans les zones prévues
    const parser = new DOMParser();
    const htmlDoc = parser.parseFromString(html, 'text/html');

    if (doc?.type !== 'contrat_adoption') {
      const elvRole = doc?.type === 'contrat_saillie' ? 'proprietaire_male' : 'vendeur';
      const acqRole = doc?.type === 'contrat_saillie' ? 'proprietaire_femelle' : 'acheteur';
      if (sigElv) {
        htmlDoc.querySelectorAll(`[data-signer="${elvRole}"] .sign-img`).forEach(el => {
          el.innerHTML = `<img src="${sigElv}" style="max-height:60px;max-width:100%;object-fit:contain">`;
        });
      }
      if (sigAcq) {
        htmlDoc.querySelectorAll(`[data-signer="${acqRole}"] .sign-img`).forEach(el => {
          el.innerHTML = `<img src="${sigAcq}" style="max-height:60px;max-width:100%;object-fit:contain">`;
        });
      }
    }

    // CSS d'impression — supprime les panneaux fixes, corrige la pagination
    const style = htmlDoc.createElement('style');
    style.textContent = `
      @page { size: A4; margin: 15mm 20mm; }
      *, *::before, *::after { -webkit-print-color-adjust: exact !important; print-color-adjust: exact !important; }
      .toolbar, .sig-panel { display: none !important; }
      .page { padding: 20px 30px 30px !important; }
      body { padding-bottom: 0 !important; }
      .sign-block { page-break-inside: avoid; break-inside: avoid; }
      .sign-section { page-break-inside: avoid; break-inside: avoid; }
      .sign-img { height: auto !important; min-height: 64px; overflow: visible !important; }
      .sign-img img { max-height: 60px !important; max-width: 100% !important; object-fit: contain !important; display: block; margin: 0 auto; }
      .sign-row { page-break-inside: avoid; break-inside: avoid; }
    `;
    htmlDoc.head.appendChild(style);

    const printHtml = `<!DOCTYPE html>\n${htmlDoc.documentElement.outerHTML}`;
    const win = window.open('', '_blank', 'width=900,height=1200');
    if (!win) return;
    win.document.write(printHtml);
    win.document.close();
    setTimeout(() => { win.focus(); win.print(); }, 600);
  }

  const bannerCls = isSigned    ? 'bg-green-600 text-white' :
                    isRefused   ? 'bg-red-500 text-white' :
                    isCancelled ? 'bg-gray-500 text-white' :
                    isExpired   ? 'bg-orange-500 text-white' :
                    isPartial   ? 'bg-blue-500 text-white' :
                    isEnAttente ? 'bg-amber-500 text-white' :
                                  'bg-[#0C5C6C] text-white';
  const bannerMsg  = isSigned    ? '✅ Contrat signé par les deux parties' :
                     isRefused   ? `❌ Contrat refusé${doc?.rejection_reason ? ` — ${doc.rejection_reason}` : ''}` :
                     isCancelled ? '🚫 Contrat annulé' :
                     isExpired   ? '⏰ Contrat expiré' :
                     isPartial   ? '✍️ Une signature reçue — en attente de la seconde partie' :
                     isEnAttente ? '⏳ En attente des signatures' :
                                   '📄 Contrat en cours de rédaction';

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col">

      {/* Bandeau statut + confidentialité */}
      <div className={`w-full py-2.5 px-4 text-center text-sm font-medium flex flex-col sm:flex-row items-center justify-center gap-2 ${bannerCls}`}>
        <span>{bannerMsg}</span>
        {!isFinal && <span className="opacity-75 text-xs">🔒 Lien privé — partagez uniquement avec l&apos;acquéreur</span>}
      </div>

      {/* Section correction coordonnées — acquéreur uniquement */}
      {!isOwner && !isFinal && (
        <div className="bg-amber-50 border-b border-amber-100 px-4 py-3">
          {!editContact ? (
            <div className="flex items-center justify-between max-w-3xl mx-auto">
              <div className="text-sm text-amber-800">
                <span className="font-semibold">Vos coordonnées : </span>
                {[contactPrenom, contactNom].filter(Boolean).join(' ') || doc?.metadata?.acquereur_nom || '—'}
                {contactAdresse && ` · ${contactAdresse}`}
              </div>
              <button onClick={() => setEditContact(true)}
                className="text-xs text-amber-700 border border-amber-300 px-3 py-1 rounded-lg hover:bg-amber-100 transition-colors flex-shrink-0 ml-3">
                ✏️ Corriger
              </button>
            </div>
          ) : (
            <div className="max-w-3xl mx-auto space-y-3">
              <p className="text-sm font-semibold text-amber-800">Corriger vos coordonnées</p>
              <div className="grid grid-cols-2 gap-3">
                <input value={contactPrenom} onChange={e => setContactPrenom(e.target.value)} placeholder="Prénom"
                  className="border border-amber-200 rounded-lg px-3 py-1.5 text-sm bg-white focus:outline-none focus:border-amber-400" />
                <input value={contactNom} onChange={e => setContactNom(e.target.value)} placeholder="Nom"
                  className="border border-amber-200 rounded-lg px-3 py-1.5 text-sm bg-white focus:outline-none focus:border-amber-400" />
                <input value={contactAdresse} onChange={e => setContactAdresse(e.target.value)} placeholder="Adresse complète"
                  className="border border-amber-200 rounded-lg px-3 py-1.5 text-sm bg-white focus:outline-none focus:border-amber-400 col-span-2" />
                <input value={contactTel} onChange={e => setContactTel(e.target.value)} placeholder="Téléphone"
                  className="border border-amber-200 rounded-lg px-3 py-1.5 text-sm bg-white focus:outline-none focus:border-amber-400" />
              </div>
              <div className="flex gap-2">
                <button onClick={saveContactAcquereur} disabled={savingContact}
                  className="bg-amber-600 hover:bg-amber-700 text-white text-sm font-semibold px-4 py-1.5 rounded-lg transition-colors disabled:opacity-50">
                  {savingContact ? '…' : '✅ Enregistrer'}
                </button>
                <button onClick={() => setEditContact(false)}
                  className="text-sm text-gray-500 hover:text-gray-700 px-3 py-1.5">
                  Annuler
                </button>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Iframe contrat */}
      <div className="flex-1 w-full" style={{ minHeight: '70vh' }}>
        <iframe
          srcDoc={iframeHtml}
          className="w-full border-0"
          style={{ height: '80vh', minHeight: 500 }}
          title={doc?.titre ?? 'Contrat'}
          sandbox="allow-scripts allow-same-origin allow-popups allow-forms allow-modals"
        />
      </div>

      {/* Sélecteur femelle — contrat de saillie, contrepartie connectée */}
      {doc?.type === 'contrat_saillie' && user && user.email === doc.metadata?.acquereur_email && !isFinal && (
        <div className="bg-purple-50 border-t border-purple-100 px-4 py-3">
          {femelleSaved ? (
            <p className="text-center text-sm text-purple-700 font-medium">
              ✅ Votre femelle a été liée au contrat — le document a été mis à jour.
            </p>
          ) : (
            <div className="max-w-xl mx-auto space-y-2">
              <p className="text-sm font-semibold text-purple-800 text-center">🐾 Liez votre femelle au contrat</p>
              <p className="text-xs text-center text-purple-600">Sélectionnez votre animal parmi ceux enregistrés dans votre compte PetsMatch.</p>
              {loadingFemelles ? (
                <p className="text-xs text-gray-500 text-center">Chargement de vos animaux…</p>
              ) : femelles.length === 0 ? (
                <p className="text-xs text-gray-500 text-center">Aucun animal de cette espèce dans votre compte — complétez le contrat manuellement.</p>
              ) : (
                <div className="flex gap-2 pt-1">
                  <select value={selectedFemId} onChange={e => setSelectedFemId(e.target.value)}
                    className="flex-1 border border-purple-200 rounded-xl px-3 py-2 text-sm bg-white focus:outline-none focus:border-purple-400">
                    <option value="">Sélectionnez votre femelle…</option>
                    {femelles.map(f => (
                      <option key={f.id} value={f.id}>{f.nom}{f.race ? ` (${f.race})` : ''}</option>
                    ))}
                  </select>
                  <button onClick={saveFemelle} disabled={!selectedFemId || savingFemelle}
                    className="bg-purple-600 hover:bg-purple-700 text-white text-sm font-semibold px-4 py-2 rounded-xl transition-colors disabled:opacity-40">
                    {savingFemelle ? '…' : 'Confirmer'}
                  </button>
                </div>
              )}
            </div>
          )}
        </div>
      )}

      {/* Zone signatures */}
      <div className="bg-white border-t border-gray-200 p-4 sm:p-6">
        <h2 className="text-base font-bold text-[#1F2A2E] mb-4 text-center">Signatures</h2>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-6 max-w-3xl mx-auto">

          {/* Signature éleveur */}
          <SignatureZone
            label="Signature de l'éleveur"
            sublabel={doc?.metadata?.acquereur_nom ? undefined : undefined}
            canvasRef={canvasElvRef}
            handlers={elvHandlers}
            isSigned={!!saved.eleveur}
            saving={saving === 'eleveur'}
            onSign={() => signer('eleveur')}
            onClear={() => { clearCanvas(canvasElvRef); setSaved(p => ({ ...p, eleveur: false })); }}
            signedAt={doc?.metadata?.signe_eleveur_le}
          />

          {/* Signature acquéreur — grisée pour le vendeur */}
          <SignatureZone
            label="Signature de l'acquéreur"
            sublabel={doc?.metadata?.acquereur_nom || undefined}
            canvasRef={canvasAcqRef}
            handlers={acqHandlers}
            isSigned={!!saved.acquereur}
            saving={saving === 'acquereur'}
            onSign={() => signer('acquereur')}
            onClear={() => { clearCanvas(canvasAcqRef); setSaved(p => ({ ...p, acquereur: false })); }}
            signedAt={doc?.metadata?.signe_acquereur_le}
            disabled={isOwner}
          />

        </div>

        {isSigned && (
          <p className="text-center text-green-700 font-semibold mt-4 text-sm">
            ✅ Contrat signé{doc?.signe_le && new Date(doc.signe_le).getFullYear() > 1970
              ? ` le ${new Date(doc.signe_le).toLocaleDateString('fr-FR', { dateStyle: 'long' })}`
              : ''} — les deux parties ont apposé leur signature.
          </p>
        )}

        {/* PREP07 — Actions disponibles dès que l'éleveur a signé */}
        {(isSigned || (isOwner && saved.eleveur)) && (
          <div className="flex justify-center mt-4 gap-3 flex-wrap">
            {/* Valider et fermer — revient à la page précédente sans imprimer */}
            <button
              onClick={() => {
                // Notifier l'ouvreur si présent (popup depuis contrat page)
                if (window.opener && !window.opener.closed) {
                  try { window.opener.postMessage({ type: 'contract_signed', token }, '*'); } catch { /* cross-origin */ }
                }
                // Fermer si popup ; sinon rediriger (timeout laisse le temps au close)
                window.close();
                setTimeout(() => { window.location.href = '/elevage/contrat'; }, 300);
              }}
              className="flex items-center gap-2 bg-[#6E9E57] hover:bg-[#5a8a45] text-white text-sm font-semibold px-5 py-2.5 rounded-xl transition-colors">
              ✅ Valider et fermer
            </button>
            {doc?.pdf_signe_url ? (
              <a href={doc.pdf_signe_url} download
                className="flex items-center gap-2 border border-green-600 text-green-700 hover:bg-green-50 text-sm font-semibold px-5 py-2.5 rounded-xl transition-colors">
                📥 Télécharger le PDF signé
              </a>
            ) : (
              <button onClick={handlePrint}
                className="flex items-center gap-2 border border-gray-300 text-gray-600 hover:bg-gray-50 text-sm font-semibold px-5 py-2.5 rounded-xl transition-colors">
                🖨️ Imprimer / PDF
              </button>
            )}
          </div>
        )}

        {/* PREP08 — Refuser */}
        {!isFinal && (
          <div className="flex justify-center mt-4">
            <button onClick={() => setRefuseModal(true)}
              className="text-xs text-red-400 hover:text-red-600 underline underline-offset-2">
              ❌ Refuser ce contrat
            </button>
          </div>
        )}

        <p className="text-center text-xs text-gray-400 mt-4">
          Ce document est accessible uniquement via ce lien privé.
          {isSigned ? ' Imprimez-le ou téléchargez-le pour le conserver.' : ' Conservez-le en lieu sûr ou imprimez-le une fois signé.'}
        </p>
      </div>

      {/* Modal refus */}
      {refuseModal && (
        <div className="fixed inset-0 z-[200] flex items-center justify-center bg-black/50 px-4"
          onClick={e => { if (e.target === e.currentTarget) setRefuseModal(false); }}>
          <div className="bg-white rounded-2xl p-6 w-full max-w-sm shadow-xl space-y-4">
            <h3 className="font-bold text-[#1F2A2E] text-base font-galey">❌ Refuser ce contrat</h3>
            <p className="text-sm text-gray-500">Indiquez optionnellement la raison du refus. L&apos;éleveur en sera informé.</p>
            <textarea
              value={refuseReason}
              onChange={e => setRefuseReason(e.target.value)}
              placeholder="Motif du refus (facultatif)…"
              rows={3}
              className="w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-red-400 resize-none"
            />
            <div className="flex gap-2">
              <button onClick={() => setRefuseModal(false)} disabled={refusing}
                className="flex-1 border border-gray-200 text-gray-600 text-sm font-medium py-2.5 rounded-xl hover:bg-gray-50 disabled:opacity-40">
                Annuler
              </button>
              <button onClick={refuser} disabled={refusing}
                className="flex-1 bg-red-500 hover:bg-red-600 text-white text-sm font-semibold py-2.5 rounded-xl transition-colors disabled:opacity-60">
                {refusing ? '…' : 'Confirmer le refus'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ── Composant zone de signature ──────────────────────────────────────────────
function SignatureZone({
  label, sublabel, canvasRef, handlers, isSigned, saving, onSign, onClear, signedAt, disabled,
}: {
  label: string;
  sublabel?: string;
  canvasRef: React.RefObject<HTMLCanvasElement | null>;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  handlers: any;
  isSigned: boolean;
  saving: boolean;
  onSign: () => void;
  onClear: () => void;
  signedAt?: string;
  disabled?: boolean;
}) {
  return (
    <div className={`border-2 rounded-xl p-4 ${isSigned ? 'border-green-400 bg-green-50' : disabled ? 'border-gray-200 bg-gray-100 opacity-60' : 'border-gray-200 bg-gray-50'}`}>
      <p className="text-sm font-semibold text-[#1F2A2E] mb-0.5">{label}</p>
      {sublabel && <p className="text-xs text-gray-400 mb-2">{sublabel}</p>}
      <canvas
        ref={canvasRef}
        width={400}
        height={120}
        className={`w-full rounded-lg border border-gray-200 bg-white touch-none ${disabled ? 'cursor-not-allowed' : 'cursor-crosshair'}`}
        style={{ height: 100 }}
        {...(disabled ? {} : handlers)}
      />
      {disabled && !isSigned && (
        <p className="text-xs text-gray-400 mt-2 text-center italic">Réservé à l&apos;acquéreur</p>
      )}
      {!disabled && (
        <div className="flex gap-2 mt-3">
          <button onClick={onClear} disabled={isSigned || disabled}
            className="flex-1 text-xs py-2 rounded-lg border border-gray-300 text-gray-500 hover:border-gray-400 disabled:opacity-40">
            Effacer
          </button>
          <button onClick={onSign} disabled={isSigned || saving || disabled}
            className={`flex-1 text-xs py-2 rounded-lg font-semibold transition-colors ${
              isSigned
                ? 'bg-green-500 text-white cursor-default'
                : 'bg-[#0C5C6C] text-white hover:bg-[#0a4f5e]'
            } disabled:opacity-60`}>
            {saving ? '…' : isSigned ? '✓ Signé' : 'Signer'}
          </button>
        </div>
      )}
      {isSigned && signedAt && (
        <p className="text-xs text-green-600 mt-2 text-center">
          Signé le {new Date(signedAt).toLocaleDateString('fr-FR', { dateStyle: 'medium' })}
        </p>
      )}
    </div>
  );
}
