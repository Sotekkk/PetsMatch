'use client';
// Bloc propriétaire commun des fiches animaux professionnelles (véto, ostéo,
// éducateur, pet-sitter, pension) : nom, appeler, message, coordonnées,
// contact d'urgence et personnes autorisées à déposer / récupérer l'animal.
// Remplace l'ancien onglet « Propriétaire ». Miroir appli :
// lib/widgets/animal/pro_animal_entete.dart (même résolution du propriétaire :
// client du fichier clinique, sinon profil qui a accordé l'accès au profil
// actif, sinon client du dernier RDV de ce profil — jamais is_main seul).
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { openOrCreateOwnerConversation } from '@/lib/owner-contact';

const TEAL = '#0C5C6C';
const IcTel = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
    <path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z" />
  </svg>
);
const IcMsg = () => (
  <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden>
    <path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z" />
  </svg>
);
type Contact = { nom: string; tel: string; lien?: string };
type Row = Record<string, unknown>;

const contacts = (raw: unknown): Contact[] => (Array.isArray(raw) ? raw : [])
  .map(c => ({ nom: String((c as Row)?.nom ?? '').trim(), tel: String((c as Row)?.tel ?? '').trim(), lien: String((c as Row)?.lien ?? '').trim() }))
  .filter(c => c.nom || c.tel);
const champ = (m: Row | null | undefined, cles: string[]) => {
  for (const k of cles) { const v = String(m?.[k] ?? '').trim(); if (v) return v; }
  return '';
};
const joindre = (parts: string[]) => parts.map(p => p.trim()).filter(Boolean).join(', ');

export default function ProAnimalEntete({ animalId, catPro, myUid, myProfileId }: {
  animalId: string; catPro: string; myUid: string; myProfileId: string | null;
}) {
  const router = useRouter();
  const avecAutorises = catPro === 'garde' || catPro === 'pension';
  const [o, setO] = useState<{ nom: string; sous: string; tel: string; email: string; adresse: string; uid: string | null } | null>(null);
  const [urgence, setUrgence] = useState<Contact[]>([]);
  const [autorises, setAutorises] = useState<Contact[]>([]);
  const [ouvert, setOuvert] = useState(false);
  const [chat, setChat] = useState(false);

  useEffect(() => {
    let annule = false;
    (async () => {
      const { data: a } = await supabase.from('animaux').select('*').eq('id', animalId).maybeSingle();
      if (!a || annule) return;
      setUrgence(contacts((a as Row).contacts_urgence));
      setAutorises(contacts((a as Row).personnes_autorisees));
      // Client du fichier du pro : celui de MON profil pour une fiche rattachée
      // (créée par un autre pro), sinon celui de la fiche.
      let clientId = (a as Row).client_clinique_id as string | null;
      if (myProfileId) {
        const { data: l } = await supabase.from('animaux_clients_pro').select('client_id')
          .eq('animal_id', animalId).eq('pro_profile_id', myProfileId).maybeSingle();
        if (l?.client_id) clientId = l.client_id as string;
      }
      if (clientId) {
        const { data: c } = await supabase.from('clients_clinique').select('*').eq('id', clientId).maybeSingle();
        if (c && !annule) {
          const r = c as Row;
          setO({
            nom: `${r.prenom ?? ''} ${r.nom ?? ''}`.trim(), tel: champ(r, ['telephone']), email: champ(r, ['email']),
            adresse: joindre([champ(r, ['adresse']), `${champ(r, ['code_postal'])} ${champ(r, ['ville'])}`]),
            uid: (r.uid_lie as string | null) ?? null,
            sous: r.uid_lie ? 'Client' : 'Client — hors PetsMatch',
          });
          return;
        }
      }
      let profilId: string | null = null;
      if (myProfileId) {
        const { data: g } = await supabase.from('animal_access').select('granted_by_profile_id')
          .eq('animal_id', animalId).eq('pro_profile_id', myProfileId).maybeSingle();
        profilId = (g as Row | null)?.granted_by_profile_id as string | null ?? null;
        if (!profilId) {
          const { data: r } = await supabase.from('rdv').select('client_profile_id').eq('animal_id', animalId)
            .eq('pro_profile_id', myProfileId).not('client_profile_id', 'is', null)
            .order('date_heure', { ascending: false }).limit(1).maybeSingle();
          profilId = (r as Row | null)?.client_profile_id as string | null ?? null;
        }
      }
      const { data: prof } = profilId
        ? await supabase.from('user_profiles_complet').select('*').eq('id', profilId).maybeSingle()
        : { data: null };
      const p = prof as Row | null;
      const uid = String(p?.uid ?? (a as Row).uid_proprietaire ?? (a as Row).uid_eleveur ?? '') || null;
      const { data: u } = uid ? await supabase.from('users_complet').select('*').eq('uid', uid).maybeSingle() : { data: null };
      const us = u as Row | null;
      const part = p?.profile_type === 'particulier';
      const nomProf = part ? `${p?.firstname ?? ''} ${p?.lastname ?? ''}`.trim() : champ(p, ['nom', 'name_elevage']);
      if (annule) return;
      setO({
        nom: nomProf || `${us?.firstname ?? ''} ${us?.lastname ?? ''}`.trim(),
        sous: part || !p ? 'Propriétaire' : 'Propriétaire (professionnel)',
        tel: champ(p, part ? ['telephone', 'phone_number'] : ['numero_elevage', 'telephone', 'phone_number']) || champ(us, ['phone_number', 'numero_elevage']),
        email: champ(p, ['email_contact', 'email']) || champ(us, ['email']),
        adresse: joindre([
          champ(p, part ? ['rue', 'adresse'] : ['rue_elevage', 'rue', 'adresse']),
          `${champ(p, part ? ['code_postal'] : ['code_postal_elevage', 'code_postal'])} ${champ(p, part ? ['ville'] : ['ville_elevage', 'ville'])}`,
        ]) || joindre([champ(us, ['rue']), `${champ(us, ['code_postal'])} ${champ(us, ['ville'])}`]),
        uid,
      });
    })();
    return () => { annule = true; };
  }, [animalId, myProfileId]);

  async function message() {
    if (!o?.uid || chat) return;
    setChat(true);
    try {
      const convId = await openOrCreateOwnerConversation(myUid, myProfileId, o.uid);
      router.push(`/messages?conv=${convId}`);
    } finally { setChat(false); }
  }

  if (!o) return null;
  const tel = (t: string) => `tel:${t.replace(/\s/g, '')}`;
  const ligne = (label: string, valeur: string, t?: string) => (
    <p className="text-xs text-gray-600" key={label + valeur}>
      <span className="text-gray-400">{label} : </span>{valeur}
      {t && <a href={tel(t)} className="ml-2 font-semibold" style={{ color: TEAL }}>Appeler</a>}
    </p>
  );
  const btn = 'w-9 h-9 rounded-full flex items-center justify-center text-sm disabled:opacity-40';

  return (
    <div className="bg-white rounded-2xl border border-gray-100 px-4 py-3" style={{ fontFamily: 'Galey, sans-serif' }}>
      <div className="flex items-center gap-3">
        <button type="button" onClick={() => setOuvert(v => !v)} className="flex-1 min-w-0 text-left">
          <p className="text-sm font-bold text-[#1F2A2E] truncate">{o.nom || 'Propriétaire non renseigné'}</p>
          <p className="text-xs text-gray-500 truncate">{[o.sous, o.tel].filter(Boolean).join(' · ')}</p>
          {!ouvert && urgence[0] && (
            <p className="text-xs text-gray-500 truncate">Contact d&apos;urgence : {[urgence[0].nom, urgence[0].tel].filter(Boolean).join(' · ')}</p>
          )}
        </button>
        <a href={o.tel ? tel(o.tel) : undefined} aria-disabled={!o.tel} title="Appeler"
          className={`${btn} ${o.tel ? '' : 'pointer-events-none opacity-40'}`} style={{ background: `${TEAL}14`, color: TEAL }}><IcTel /></a>
        <button type="button" onClick={message} disabled={!o.uid || chat} title="Message" className={btn}
          style={{ background: `${TEAL}14`, color: TEAL }}>{chat ? '…' : <IcMsg />}</button>
        <button type="button" onClick={() => setOuvert(v => !v)} className="text-gray-400 px-1" aria-label="Détails">{ouvert ? '▴' : '▾'}</button>
      </div>
      {ouvert && (
        <div className="mt-2 pt-2 border-t border-gray-100 space-y-1">
          {o.email && ligne('E-mail', o.email)}
          {o.adresse && ligne('Adresse', o.adresse)}
          {urgence.map(c => ligne("Contact d'urgence", [c.nom, c.tel].filter(Boolean).join(' · '), c.tel || undefined))}
          {avecAutorises && autorises.map(c => ligne('Autorisé·e à déposer / récupérer',
            [c.nom, c.lien ? `(${c.lien})` : '', c.tel].filter(Boolean).join(' '), c.tel || undefined))}
          {!o.email && !o.adresse && !urgence.length && !(avecAutorises && autorises.length) && (
            <p className="text-xs text-gray-400">Aucune autre information transmise.</p>
          )}
        </div>
      )}
    </div>
  );
}
