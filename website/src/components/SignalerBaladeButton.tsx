'use client';

import { useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';

const RAISONS = [
  { value: 'contenu_inapproprie', label: 'Contenu inapproprié' },
  { value: 'spam', label: 'Spam' },
  { value: 'maltraitance', label: 'Défi dangereux / maltraitance' },
  { value: 'autre', label: 'Autre' },
];

export default function SignalerBaladeButton({ baladeId }: { baladeId: string }) {
  const { user } = useAuth();
  const [open, setOpen] = useState(false);
  const [sent, setSent] = useState(false);

  async function signaler(raison: string) {
    if (!user) return;
    try {
      await supabase.from('signalements').insert({
        reporter_uid: user.uid, target_type: 'balade_ludique', target_id: baladeId, raison,
      });
      setSent(true);
    } catch {
      setSent(true);
    }
    setOpen(false);
  }

  if (!user) return null;

  return (
    <div className="relative">
      <button onClick={() => setOpen(v => !v)} className="text-white/80 hover:text-white text-sm font-galey flex items-center gap-1">
        🚩 Signaler
      </button>
      {open && (
        <div className="absolute right-0 top-8 bg-white rounded-xl shadow-lg border border-gray-100 py-2 w-56 z-10">
          {RAISONS.map(r => (
            <button key={r.value} onClick={() => signaler(r.value)}
              className="w-full text-left px-4 py-2 text-sm font-galey text-gray-700 hover:bg-gray-50">
              {r.label}
            </button>
          ))}
        </div>
      )}
      {sent && <p className="absolute right-0 top-8 bg-white rounded-xl shadow-lg border border-gray-100 px-4 py-2 text-xs font-galey text-gray-600 w-56 z-10">
        Signalement envoyé, merci.
      </p>}
    </div>
  );
}
