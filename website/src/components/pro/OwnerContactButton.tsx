'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { fetchOwnerContact, saveOwnerContactManuel, waPhone, openOrCreateOwnerConversation, type OwnerContactData } from '@/lib/owner-contact';

/**
 * Bouton compact « coordonnées » : au clic, charge et affiche les coordonnées
 * du propriétaire d'un animal suivi (nom, téléphone, email) + actions
 * rapides (message dans l'appli, appeler, WhatsApp, email). Si le
 * propriétaire n'a pas (ou plus) de compte PetsMatch actif, les coordonnées
 * sont modifiables (info reçue autrement — tél., mail…).
 */
export default function OwnerContactButton({
  animalId, animalNom, ownerUid, myUid, myProfileId, className = '',
}: {
  animalId: string; animalNom: string; ownerUid: string | null;
  myUid: string; myProfileId: string | null; className?: string;
}) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);
  const [messaging, setMessaging] = useState(false);
  const [open, setOpen] = useState(false);
  const [contact, setContact] = useState<OwnerContactData | null>(null);
  const [editable, setEditable] = useState(false);
  const [editing, setEditing] = useState(false);
  const [form, setForm] = useState<OwnerContactData>({});
  const [saving, setSaving] = useState(false);

  async function handleOpen() {
    setLoading(true);
    try {
      const { contact: c, editable: e } = await fetchOwnerContact(animalId, ownerUid);
      setContact(c);
      setEditable(e);
      setForm(c);
      setEditing(false);
      setOpen(true);
    } finally {
      setLoading(false);
    }
  }

  async function handleSave() {
    setSaving(true);
    try {
      const cleaned: OwnerContactData = {};
      (Object.keys(form) as (keyof OwnerContactData)[]).forEach(k => {
        const v = (form[k] ?? '').trim();
        if (v) cleaned[k] = v;
      });
      await saveOwnerContactManuel(animalId, cleaned);
      setContact(cleaned);
      setEditing(false);
    } finally {
      setSaving(false);
    }
  }

  async function handleMessage() {
    if (!ownerUid) return;
    setMessaging(true);
    try {
      const convId = await openOrCreateOwnerConversation(myUid, myProfileId, ownerUid);
      router.push(`/messages?conv=${convId}`);
    } finally {
      setMessaging(false);
    }
  }

  const nomComplet = contact ? [contact.prenom, contact.nom].filter(Boolean).join(' ') : '';
  const aucune = !!contact && !nomComplet && !contact.tel && !contact.email;

  return (
    <>
      <button type="button" onClick={handleOpen} disabled={loading}
        title="Coordonnées du propriétaire"
        className={`shrink-0 w-7 h-7 rounded-full flex items-center justify-center text-[#0C5C6C] hover:bg-[#0C5C6C]/10 transition-colors disabled:opacity-50 ${className}`}>
        {loading ? '…' : '📇'}
      </button>

      {open && contact && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 sm:p-4"
          onClick={() => setOpen(false)}>
          <div className="bg-white rounded-t-2xl sm:rounded-2xl w-full sm:max-w-sm p-5 max-h-[85vh] overflow-y-auto"
            onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-1">
              <h3 className="font-bold text-[#1F2A2E] text-base" style={{ fontFamily: 'Galey, sans-serif' }}>
                Coordonnées — {animalNom}
              </h3>
              {editable && !editing && (
                <button onClick={() => setEditing(true)} className="text-xs font-semibold text-[#0C5C6C] shrink-0">
                  ✏️ Modifier
                </button>
              )}
            </div>
            {editable && (
              <p className="text-[11px] text-gray-400 mb-3">
                {editing
                  ? "Le propriétaire n'a pas (ou plus) de compte actif — corrigez si vous avez une info plus récente."
                  : 'Propriétaire sans compte actif : coordonnées modifiables si besoin.'}
              </p>
            )}

            {editing ? (
              <div className="space-y-2 mb-4">
                <div className="grid grid-cols-2 gap-2">
                  <input value={form.prenom ?? ''} onChange={e => setForm(f => ({ ...f, prenom: e.target.value }))}
                    placeholder="Prénom" className="border border-gray-200 rounded-xl px-3 py-2 text-sm" />
                  <input value={form.nom ?? ''} onChange={e => setForm(f => ({ ...f, nom: e.target.value }))}
                    placeholder="Nom" className="border border-gray-200 rounded-xl px-3 py-2 text-sm" />
                </div>
                <input value={form.tel ?? ''} onChange={e => setForm(f => ({ ...f, tel: e.target.value }))}
                  placeholder="Téléphone" className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />
                <input value={form.email ?? ''} onChange={e => setForm(f => ({ ...f, email: e.target.value }))}
                  placeholder="Email" className="w-full border border-gray-200 rounded-xl px-3 py-2 text-sm" />
                <div className="flex gap-2 pt-1">
                  <button onClick={() => { setForm(contact); setEditing(false); }} disabled={saving}
                    className="flex-1 border border-gray-200 text-gray-600 text-sm font-semibold py-2 rounded-xl disabled:opacity-50">
                    Annuler
                  </button>
                  <button onClick={handleSave} disabled={saving}
                    className="flex-1 bg-[#0C5C6C] text-white text-sm font-semibold py-2 rounded-xl disabled:opacity-50">
                    {saving ? '…' : 'Enregistrer'}
                  </button>
                </div>
              </div>
            ) : aucune ? (
              <p className="text-sm text-gray-500 mb-4">Aucune coordonnée enregistrée pour cet animal.</p>
            ) : (
              <div className="rounded-xl bg-gray-50 border border-gray-200 p-3 text-sm space-y-1 mb-4">
                {nomComplet && <p>👤 {nomComplet}</p>}
                {contact.tel && <p>📞 {contact.tel}</p>}
                {contact.email && <p>✉️ {contact.email}</p>}
              </div>
            )}

            {!editing && (
              <div className="flex flex-wrap gap-2">
                {ownerUid && (
                  <button onClick={handleMessage} disabled={messaging}
                    className="px-3.5 py-2 rounded-xl text-xs font-bold text-[#0C5C6C] bg-[#0C5C6C]/10 border border-[#0C5C6C]/30 disabled:opacity-50">
                    {messaging ? '…' : '💬 Application'}
                  </button>
                )}
                {contact.tel && (
                  <a href={`tel:${contact.tel}`}
                    className="px-3.5 py-2 rounded-xl text-xs font-bold text-[#0C5C6C] bg-[#0C5C6C]/10 border border-[#0C5C6C]/30">
                    📞 Appeler
                  </a>
                )}
                {contact.tel && (
                  <a href={`https://wa.me/${waPhone(contact.tel)}`} target="_blank" rel="noopener noreferrer"
                    className="px-3.5 py-2 rounded-xl text-xs font-bold text-[#1a9e4b] bg-[#25D366]/10 border border-[#25D366]/40">
                    WhatsApp
                  </a>
                )}
                {contact.email && (
                  <a href={`mailto:${contact.email}`}
                    className="px-3.5 py-2 rounded-xl text-xs font-bold text-[#EA4335] bg-[#EA4335]/10 border border-[#EA4335]/30">
                    Email
                  </a>
                )}
              </div>
            )}
            <button onClick={() => setOpen(false)} className="mt-4 w-full text-xs text-gray-500 py-2">Fermer</button>
          </div>
        </div>
      )}
    </>
  );
}
