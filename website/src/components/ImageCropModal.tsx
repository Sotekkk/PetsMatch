'use client';

import { useState, useRef, useCallback } from 'react';
import ReactCrop, {
  type Crop, type PixelCrop,
  centerCrop, makeAspectCrop,
} from 'react-image-crop';
import 'react-image-crop/dist/ReactCrop.css';

interface Props {
  src: string;
  aspect?: number;
  maxDim?: number;
  title?: string;
  onConfirm: (blob: Blob) => void;
  onCancel: () => void;
}

function initCrop(w: number, h: number, aspect: number): Crop {
  return centerCrop(makeAspectCrop({ unit: '%', width: 90 }, aspect, w, h), w, h);
}

function cropToBlob(img: HTMLImageElement, crop: PixelCrop, maxDim: number, quality = 0.85): Promise<Blob> {
  const scaleX = img.naturalWidth / img.width;
  const scaleY = img.naturalHeight / img.height;
  let w = Math.round(crop.width * scaleX);
  let h = Math.round(crop.height * scaleY);
  if (w > maxDim || h > maxDim) {
    const r = Math.min(maxDim / w, maxDim / h);
    w = Math.round(w * r);
    h = Math.round(h * r);
  }
  const canvas = document.createElement('canvas');
  canvas.width = w;
  canvas.height = h;
  const ctx = canvas.getContext('2d')!;
  ctx.drawImage(
    img,
    crop.x * scaleX, crop.y * scaleY, crop.width * scaleX, crop.height * scaleY,
    0, 0, w, h,
  );
  return new Promise((resolve, reject) =>
    canvas.toBlob(b => (b ? resolve(b) : reject(new Error('canvas empty'))), 'image/jpeg', quality)
  );
}

export default function ImageCropModal({
  src, aspect = 1, maxDim = 1200, title = 'Recadrer la photo', onConfirm, onCancel,
}: Props) {
  const imgRef = useRef<HTMLImageElement>(null);
  const [crop, setCrop] = useState<Crop>();
  const [completedCrop, setCompletedCrop] = useState<PixelCrop>();
  const [confirming, setConfirming] = useState(false);

  const onImageLoad = useCallback((e: React.SyntheticEvent<HTMLImageElement>) => {
    const { width, height } = e.currentTarget;
    setCrop(initCrop(width, height, aspect));
  }, [aspect]);

  async function handleConfirm() {
    if (!imgRef.current || !completedCrop) return;
    setConfirming(true);
    try {
      const blob = await cropToBlob(imgRef.current, completedCrop, maxDim);
      onConfirm(blob);
    } finally {
      setConfirming(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/75 p-4">
      <div className="bg-white rounded-2xl overflow-hidden w-full max-w-md shadow-2xl flex flex-col">
        <div className="flex items-center justify-between px-4 py-3 border-b border-gray-100">
          <h2 className="font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>{title}</h2>
          <button onClick={onCancel} className="text-gray-400 hover:text-gray-600 text-2xl leading-none">×</button>
        </div>
        <div className="bg-gray-900 p-4 flex items-center justify-center">
          <ReactCrop crop={crop} onChange={c => setCrop(c)} onComplete={c => setCompletedCrop(c)} aspect={aspect}>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img ref={imgRef} src={src} onLoad={onImageLoad} alt=""
              className="max-w-full max-h-[55vh] object-contain" />
          </ReactCrop>
        </div>
        <p className="text-center text-xs text-gray-400 py-2">Déplacez et redimensionnez la sélection</p>
        <div className="flex gap-3 px-4 pb-4">
          <button onClick={onCancel}
            className="flex-1 py-2.5 rounded-xl border border-gray-200 text-sm text-gray-600 hover:bg-gray-50">
            Annuler
          </button>
          <button onClick={handleConfirm} disabled={!completedCrop || confirming}
            className="flex-1 py-2.5 rounded-xl bg-[#0C5C6C] text-white text-sm font-semibold hover:bg-[#094F5D] disabled:opacity-50">
            {confirming ? '…' : 'Recadrer'}
          </button>
        </div>
      </div>
    </div>
  );
}
