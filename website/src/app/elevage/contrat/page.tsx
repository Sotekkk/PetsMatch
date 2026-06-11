'use client';

import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { collection, query, orderBy, onSnapshot, addDoc, deleteDoc, doc, serverTimestamp } from 'firebase/firestore';
import { ref, uploadBytesResumable, getDownloadURL, deleteObject } from 'firebase/storage';
import { db, storage } from '@/lib/firebase';
import { useAuth } from '@/lib/auth-context';
import { usePlan } from '@/lib/use-plan';

interface Contrat {
  id: string;
  nom: string;
  type: 'reservation' | 'vente' | 'saillie' | 'autre';
  fileName: string;
  ext: string;
  url: string;
  storagePath: string;
  dateUpload?: { seconds: number };
}

const TYPE_META = {
  reservation: { label: 'Réservation', color: 'bg-teal-50 text-teal-700 border-teal-200', icon: '🐾', desc: 'Arrhes, conditions, disponibilité' },
  vente:       { label: 'Vente',        color: 'bg-green-50 text-green-700 border-green-200', icon: '🤝', desc: 'Transfert de propriété, garanties légales' },
  saillie:     { label: 'Saillie',      color: 'bg-pink-50 text-pink-700 border-pink-200',   icon: '💜', desc: 'Conditions de saillie, honoraires' },
  autre:       { label: 'Autre',        color: 'bg-gray-50 text-gray-600 border-gray-200',   icon: '📄', desc: '' },
};

const MODELES = [
  { type: 'reservation' as const, title: 'Contrat de réservation', icon: '🐾', bg: 'bg-teal-50', border: 'border-teal-200', desc: 'Formalise la réservation d\'un animal avec versement d\'arrhes, conditions d\'annulation et engagement des deux parties.' },
  { type: 'vente' as const,       title: 'Contrat de vente',        icon: '🤝', bg: 'bg-green-50', border: 'border-green-200', desc: 'Officialise le transfert de propriété, inclut les garanties légales (vices rédhibitoires), l\'état de santé et les conditions de la cession.' },
  { type: 'saillie' as const,     title: 'Contrat de saillie',      icon: '💜', bg: 'bg-pink-50', border: 'border-pink-200', desc: 'Définit les conditions de la saillie extérieure, le prix, le droit au chiot/poulain, et les responsabilités de chaque partie.' },
];

export default function ContratsPage() {
  const { user, loading } = useAuth();
  const { config: planConfig, loading: planLoading } = usePlan();
  const router = useRouter();
  const [contrats, setContrats] = useState<Contrat[]>([]);
  const [uploading, setUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [showTypeModal, setShowTypeModal] = useState(false);
  const [pendingFile, setPendingFile] = useState<File | null>(null);
  const [pendingNom, setPendingNom] = useState('');
  const [selectedType, setSelectedType] = useState<Contrat['type']>('reservation');
  const [showNomModal, setShowNomModal] = useState(false);
  const [deleting, setDeleting] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (!loading && !user) router.push('/connexion');
  }, [loading, user, router]);

  useEffect(() => {
    if (!user) return;
    const q = query(
      collection(db, 'users', user.uid, 'contrats'),
      orderBy('dateUpload', 'desc')
    );
    const unsub = onSnapshot(q, snap => {
      setContrats(snap.docs.map(d => ({ id: d.id, ...d.data() } as Contrat)));
    });
    return unsub;
  }, [user]);

  if (!planLoading && !planConfig.hasPremiumFeatures) {
    return (
      <div className="min-h-[70vh] flex flex-col items-center justify-center gap-4 px-4 text-center">
        <span className="text-5xl">🔒</span>
        <h2 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
          Contrats — Plan Premium requis
        </h2>
        <p className="text-gray-500 text-sm max-w-sm">
          La gestion des contrats est disponible avec le plan Premium. Sécurisez vos ventes, réservations et saillies avec des contrats professionnels.
        </p>
        <a href="/abonnement"
          className="bg-[#D97706] hover:bg-[#B45309] text-white font-semibold px-6 py-3 rounded-xl transition-colors text-sm">
          👑 Voir les plans
        </a>
        <a href="/" className="text-sm text-gray-400 hover:text-[#0C5C6C]">← Retour à l&apos;accueil</a>
      </div>
    );
  }

  function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    setPendingFile(file);
    setPendingNom(file.name.replace(/\.[^.]+$/, ''));
    setSelectedType('reservation');
    setShowTypeModal(true);
    e.target.value = '';
  }

  function confirmType(type: Contrat['type']) {
    setSelectedType(type);
    setShowTypeModal(false);
    setShowNomModal(true);
  }

  async function confirmUpload() {
    if (!pendingFile || !user) return;
    setShowNomModal(false);
    setUploading(true);
    setUploadProgress(0);
    try {
      const ext = pendingFile.name.split('.').pop() ?? 'pdf';
      const storagePath = `contrats/${user.uid}/${Date.now()}_${pendingFile.name}`;
      const storageRef = ref(storage, storagePath);
      const task = uploadBytesResumable(storageRef, pendingFile);
      await new Promise<void>((resolve, reject) => {
        task.on('state_changed',
          snap => setUploadProgress(Math.round(snap.bytesTransferred / snap.totalBytes * 100)),
          reject,
          resolve
        );
      });
      const url = await getDownloadURL(storageRef);
      await addDoc(collection(db, 'users', user.uid, 'contrats'), {
        nom: pendingNom.trim() || pendingFile.name,
        type: selectedType,
        fileName: pendingFile.name,
        ext,
        url,
        storagePath,
        dateUpload: serverTimestamp(),
      });
    } catch {
      alert('Erreur lors de l\'upload. Veuillez réessayer.');
    } finally {
      setUploading(false);
      setUploadProgress(0);
      setPendingFile(null);
    }
  }

  async function handleDelete(c: Contrat) {
    if (!confirm(`Supprimer "${c.nom}" ?`)) return;
    setDeleting(c.id);
    try {
      await deleteObject(ref(storage, c.storagePath));
      await deleteDoc(doc(db, 'users', user!.uid, 'contrats', c.id));
    } catch {
      alert('Erreur lors de la suppression.');
    } finally {
      setDeleting(null);
    }
  }

  function formatDate(ts?: { seconds: number }) {
    if (!ts) return '';
    return new Date(ts.seconds * 1000).toLocaleDateString('fr-FR');
  }

  const isCls = 'w-full border border-gray-200 rounded-xl px-4 py-2.5 text-sm focus:outline-none focus:border-[#0C5C6C] bg-white';

  return (
    <div className="max-w-3xl mx-auto px-4 py-8 space-y-8">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>
            📄 Mes Contrats
          </h1>
          <p className="text-sm text-gray-500 mt-0.5">Réservations, ventes, saillies — centralisez vos documents</p>
        </div>
        <button
          onClick={() => fileRef.current?.click()}
          disabled={uploading}
          className="flex items-center gap-2 bg-[#6E9E57] hover:bg-[#5A8A45] disabled:opacity-60 text-white text-sm font-semibold px-4 py-2.5 rounded-xl transition-colors">
          {uploading
            ? <span className="text-xs">{uploadProgress}%…</span>
            : <><span>⬆️</span><span>Ajouter un contrat</span></>}
        </button>
        <input ref={fileRef} type="file" accept=".pdf,.jpg,.jpeg,.png" className="hidden" onChange={handleFileChange} />
      </div>

      {/* Modèles */}
      <div>
        <h2 className="text-sm font-semibold text-gray-700 mb-3">Modèles de contrats</h2>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          {MODELES.map(m => (
            <div key={m.type} className={`${m.bg} border ${m.border} rounded-xl p-4 space-y-1.5`}>
              <div className="text-2xl">{m.icon}</div>
              <p className="text-sm font-semibold text-[#1F2A2E]">{m.title}</p>
              <p className="text-xs text-gray-500 leading-relaxed">{m.desc}</p>
              <button
                onClick={() => fileRef.current?.click()}
                className="mt-2 text-xs font-semibold text-[#0C5C6C] hover:underline">
                ⬆️ Importer votre modèle
              </button>
            </div>
          ))}
        </div>
        <p className="text-xs text-gray-400 mt-2">
          Importez vos propres modèles PDF ou images. La génération automatique de contrats pré-remplis sera disponible prochainement.
        </p>
      </div>

      {/* Liste des contrats */}
      <div>
        <h2 className="text-sm font-semibold text-gray-700 mb-3">Contrats enregistrés ({contrats.length})</h2>
        {contrats.length === 0 ? (
          <div className="text-center py-12 border-2 border-dashed border-gray-200 rounded-xl text-gray-400">
            <div className="text-4xl mb-3">📂</div>
            <p className="text-sm font-medium">Aucun contrat enregistré</p>
            <p className="text-xs mt-1">Importez vos premiers documents en cliquant sur &laquo; Ajouter un contrat &raquo;</p>
          </div>
        ) : (
          <div className="space-y-2">
            {contrats.map(c => {
              const meta = TYPE_META[c.type] ?? TYPE_META.autre;
              const isImg = ['jpg', 'jpeg', 'png', 'webp'].includes(c.ext?.toLowerCase() ?? '');
              return (
                <div key={c.id} className="flex items-center gap-3 p-3 border border-gray-100 rounded-xl bg-white hover:border-gray-200 transition-colors">
                  <div className="w-10 h-10 rounded-lg flex items-center justify-center text-xl flex-shrink-0 bg-gray-50 border border-gray-100">
                    {isImg ? '🖼️' : '📄'}
                  </div>
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-[#1F2A2E] truncate">{c.nom}</p>
                    <div className="flex items-center gap-2 mt-0.5">
                      <span className={`text-xs px-2 py-0.5 rounded-full border font-medium ${meta.color}`}>
                        {meta.icon} {meta.label}
                      </span>
                      {c.dateUpload && (
                        <span className="text-xs text-gray-400">{formatDate(c.dateUpload)}</span>
                      )}
                    </div>
                  </div>
                  <div className="flex items-center gap-2 flex-shrink-0">
                    <a href={c.url} target="_blank" rel="noopener noreferrer"
                      className="text-xs text-[#0C5C6C] hover:underline font-medium">
                      Ouvrir
                    </a>
                    <button
                      onClick={() => handleDelete(c)}
                      disabled={deleting === c.id}
                      className="text-xs text-red-400 hover:text-red-600 font-medium disabled:opacity-40">
                      {deleting === c.id ? '…' : 'Supprimer'}
                    </button>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>

      {/* Upload progress bar */}
      {uploading && (
        <div className="w-full bg-gray-100 rounded-full h-2">
          <div className="bg-[#6E9E57] h-2 rounded-full transition-all" style={{ width: `${uploadProgress}%` }} />
        </div>
      )}

      {/* Modal choix du type */}
      {showTypeModal && (
        <div className="fixed inset-0 z-[100] flex items-end sm:items-center justify-center bg-black/50 px-4 pb-4 sm:pb-0"
          onClick={e => { if (e.target === e.currentTarget) { setShowTypeModal(false); setPendingFile(null); } }}>
          <div className="bg-white rounded-2xl p-6 w-full max-w-sm shadow-xl space-y-3">
            <h3 className="font-bold text-[#1F2A2E] text-base" style={{ fontFamily: 'Galey, sans-serif' }}>
              Type de contrat
            </h3>
            {(['reservation', 'vente', 'saillie', 'autre'] as const).map(t => {
              const m = TYPE_META[t];
              return (
                <button key={t} onClick={() => confirmType(t)}
                  className={`w-full flex items-center gap-3 p-3 rounded-xl border text-left transition-colors hover:opacity-80 ${m.color}`}>
                  <span className="text-xl">{m.icon}</span>
                  <div>
                    <p className="text-sm font-semibold">{m.label}</p>
                    {m.desc && <p className="text-xs opacity-70">{m.desc}</p>}
                  </div>
                </button>
              );
            })}
          </div>
        </div>
      )}

      {/* Modal nom du contrat */}
      {showNomModal && (
        <div className="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 px-4"
          onClick={e => { if (e.target === e.currentTarget) { setShowNomModal(false); setPendingFile(null); } }}>
          <div className="bg-white rounded-2xl p-6 w-full max-w-sm shadow-xl space-y-4">
            <h3 className="font-bold text-[#1F2A2E] text-base" style={{ fontFamily: 'Galey, sans-serif' }}>
              Nommer le document
            </h3>
            <input value={pendingNom} onChange={e => setPendingNom(e.target.value)}
              placeholder="Nom du contrat" className={isCls} autoFocus />
            <div className="flex gap-2">
              <button onClick={() => { setShowNomModal(false); setPendingFile(null); }}
                className="flex-1 border border-gray-200 text-gray-600 text-sm font-medium py-2.5 rounded-xl hover:bg-gray-50">
                Annuler
              </button>
              <button onClick={confirmUpload}
                className="flex-1 bg-[#6E9E57] hover:bg-[#5A8A45] text-white text-sm font-semibold py-2.5 rounded-xl transition-colors">
                Enregistrer
              </button>
            </div>
          </div>
        </div>
      )}

      <div className="pt-2">
        <Link href="/" className="text-sm text-gray-400 hover:text-[#0C5C6C]">← Retour à l&apos;accueil</Link>
      </div>
    </div>
  );
}
