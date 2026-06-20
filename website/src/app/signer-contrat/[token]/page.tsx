'use client';

import { use, useEffect, useRef, useState } from 'react';
import { createClient } from '@supabase/supabase-js';
import {
  generateContratHTML, generateContratReservationHTML, generateCertificatCessionHTML,
  AnimalContrat, DataContrat, EleveurContrat,
} from '@/lib/contrat-vente';

const supabase = createClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
);

type DocStatut = 'brouillon' | 'en_attente' | 'signe' | 'archive';

interface DocRow {
  id: string;
  animal_id: string;
  uid_eleveur: string;
  type: string;
  titre: string;
  statut: DocStatut;
  signe_le: string | null;
  metadata: Record<string, string>;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  animaux: any;
}

export default function SignerContratPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = use(params);
  const [doc, setDoc]       = useState<DocRow | null>(null);
  const [html, setHtml]     = useState('');
  const [status, setStatus] = useState<'loading' | 'ready' | 'not_found'>('loading');
  const [saving, setSaving] = useState<'eleveur' | 'acquereur' | null>(null);
  const [saved, setSaved]   = useState<{ eleveur?: boolean; acquereur?: boolean }>({});
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
      if (data.type === 'contrat_reservation') {
        generatedHtml = generateContratReservationHTML(animal, dataContrat, eleveur, opts);
      } else if (data.type === 'certificat_cession') {
        generatedHtml = generateCertificatCessionHTML(animal, dataContrat, eleveur, { ...opts, eleveurUid: data.uid_eleveur });
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

      setDoc(data as DocRow);
      setHtml(generatedHtml);
      setStatus('ready');
    }
    load();
  }, [token]);

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
    const sigField    = role === 'eleveur' ? 'signature_eleveur'    : 'signature_acquereur';
    const dateField   = role === 'eleveur' ? 'signe_eleveur_le'     : 'signe_acquereur_le';
    const newSaved    = { ...saved, [role]: true };
    const newStatut: DocStatut = newSaved.eleveur && newSaved.acquereur ? 'signe' : 'en_attente';

    await supabase.from('documents_animaux').update({
      metadata: { ...doc.metadata, [sigField]: dataUrl, [dateField]: now },
      statut:   newStatut,
      ...(newStatut === 'signe' ? { signe_le: now } : {}),
    }).eq('token', token);

    setDoc(prev => prev ? { ...prev, statut: newStatut, metadata: { ...prev.metadata, [sigField]: dataUrl, [dateField]: now } } : prev);
    setSaved(newSaved);
    setSaving(null);
  }

  function clearCanvas(ref: React.RefObject<HTMLCanvasElement | null>) {
    const c = ref.current;
    if (!c) return;
    c.getContext('2d')?.clearRect(0, 0, c.width, c.height);
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

  const isSigned = doc?.statut === 'signe';
  const isEnAttente = doc?.statut === 'en_attente';
  const elvHandlers  = makeDrawHandlers(canvasElvRef,  drawingElv);
  const acqHandlers  = makeDrawHandlers(canvasAcqRef,  drawingAcq);

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col">

      {/* Bandeau statut + confidentialité */}
      <div className={`w-full py-2.5 px-4 text-center text-sm font-medium flex flex-col sm:flex-row items-center justify-center gap-2 ${
        isSigned ? 'bg-green-600 text-white' :
        isEnAttente ? 'bg-amber-500 text-white' :
        'bg-[#0C5C6C] text-white'
      }`}>
        <span>
          {isSigned
            ? '✅ Contrat signé par les deux parties'
            : isEnAttente
            ? '⏳ En attente de la signature de l\'acquéreur'
            : '📄 Contrat en cours de rédaction'}
        </span>
        <span className="opacity-75 text-xs">🔒 Lien privé — partagez uniquement avec l&apos;acquéreur</span>
      </div>

      {/* Iframe contrat */}
      <div className="flex-1 w-full" style={{ minHeight: '70vh' }}>
        <iframe
          srcDoc={html}
          className="w-full border-0"
          style={{ height: '80vh', minHeight: 500 }}
          title={doc?.titre ?? 'Contrat'}
          sandbox="allow-scripts allow-same-origin allow-popups allow-forms allow-modals"
        />
      </div>

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

          {/* Signature acquéreur */}
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
          />

        </div>

        {isSigned && (
          <p className="text-center text-green-700 font-semibold mt-4 text-sm">
            ✅ Contrat signé le {new Date(doc!.signe_le!).toLocaleDateString('fr-FR', { dateStyle: 'long' })} — les deux parties ont apposé leur signature.
          </p>
        )}

        <p className="text-center text-xs text-gray-400 mt-4">
          Ce document est accessible uniquement via ce lien privé.
          Conservez-le en lieu sûr ou imprimez-le une fois signé.
        </p>
      </div>
    </div>
  );
}

// ── Composant zone de signature ──────────────────────────────────────────────
function SignatureZone({
  label, sublabel, canvasRef, handlers, isSigned, saving, onSign, onClear, signedAt,
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
}) {
  return (
    <div className={`border-2 rounded-xl p-4 ${isSigned ? 'border-green-400 bg-green-50' : 'border-gray-200 bg-gray-50'}`}>
      <p className="text-sm font-semibold text-[#1F2A2E] mb-0.5">{label}</p>
      {sublabel && <p className="text-xs text-gray-400 mb-2">{sublabel}</p>}
      <canvas
        ref={canvasRef}
        width={400}
        height={120}
        className="w-full rounded-lg border border-gray-200 bg-white cursor-crosshair touch-none"
        style={{ height: 100 }}
        {...handlers}
      />
      <div className="flex gap-2 mt-3">
        <button onClick={onClear} disabled={isSigned}
          className="flex-1 text-xs py-2 rounded-lg border border-gray-300 text-gray-500 hover:border-gray-400 disabled:opacity-40">
          Effacer
        </button>
        <button onClick={onSign} disabled={isSigned || saving}
          className={`flex-1 text-xs py-2 rounded-lg font-semibold transition-colors ${
            isSigned
              ? 'bg-green-500 text-white cursor-default'
              : 'bg-[#0C5C6C] text-white hover:bg-[#0a4f5e]'
          } disabled:opacity-60`}>
          {saving ? '…' : isSigned ? '✓ Signé' : 'Signer'}
        </button>
      </div>
      {isSigned && signedAt && (
        <p className="text-xs text-green-600 mt-2 text-center">
          Signé le {new Date(signedAt).toLocaleDateString('fr-FR', { dateStyle: 'medium' })}
        </p>
      )}
    </div>
  );
}
