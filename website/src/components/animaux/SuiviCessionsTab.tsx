'use client';

import { useState, useEffect, useRef } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { fetchContactAcquereur } from '@/lib/contact-acquereur';
import ContactAcquereurButton from '@/components/animaux/ContactAcquereurButton';

interface AnimalLite {
  id: string;
  nom?: string;
  race?: string;
  photo_url?: string;
  statut?: string;
  date_naissance?: string;
  uid_acquereur?: string | null;
  profile_id_acquereur?: string | null;
  destinataire_nom?: string | null;
  sterilise?: boolean | null;
  sterilisation_requise?: boolean | null;
  sterilisation_echeance?: string | null;
  sterilisation_validee?: boolean | null;
}

interface Props {
  animaux: AnimalLite[];
  /** uid du gérant principal (propriétaire réel de l'élevage). */
  uid: string;
  /** uid Firebase réel de la personne connectée (identité des messages
   * envoyés). Différent de `uid` pour un cogérant ; par défaut = uid. */
  myUid?: string;
  activeProfileId?: string | null;
  onLocalUpdate: (id: string, patch: Partial<AnimalLite>) => void;
}

interface Contact { prenom?: string; nom?: string; tel?: string; email?: string; adresse?: string }

function parseDate(s?: string | null): Date | null {
  if (!s) return null;
  const d = new Date(s);
  return isNaN(d.getTime()) ? null : d;
}

function fmt(d: Date) { return d.toLocaleDateString('fr-FR'); }
function fmtLong(d: Date) { return d.toLocaleDateString('fr-FR', { day: '2-digit', month: 'short', year: 'numeric' }); }

type StatutSuivi = 'a_faire' | 'retard' | 'recu';
type StatutFiltre = 'a_suivre' | 'tous' | 'a_faire' | 'retard' | 'recu';
type EcheanceFiltre = 'toutes' | 'depassees' | '30j';
interface DossierSuivi { a: AnimalLite; ech: Date | null; days: number | null; statut: StatutSuivi; declaree: boolean }

/** Téléphone au format international sans « + » pour wa.me (France par défaut). */
function waPhone(raw: string): string {
  let d = raw.replace(/[^0-9]/g, '');
  if (d.startsWith('00')) d = d.slice(2);
  if (d.startsWith('0')) d = '33' + d.slice(1);
  return d;
}

export default function SuiviCessionsTab({ animaux, uid, myUid, activeProfileId, onLocalUpdate }: Props) {
  const senderUid = myUid ?? uid;
  const [q, setQ] = useState('');
  const [statutFiltre, setStatutFiltre] = useState<StatutFiltre>('a_suivre');
  const [echeanceFiltre, setEcheanceFiltre] = useState<EcheanceFiltre>('toutes');
  const [certif, setCertif] = useState<AnimalLite | null>(null);
  const [valideesLe, setValideesLe] = useState<Record<string, string>>({});
  const [busy, setBusy] = useState<string | null>(null);
  const [annivAuto, setAnnivAuto] = useState(false);
  const [annivLoaded, setAnnivLoaded] = useState(false);
  const [relance, setRelance] = useState<{ a: AnimalLite; contact: Contact } | null>(null);
  const [relanceMsg, setRelanceMsg] = useState('');
  const [voeux, setVoeux] = useState<{ a: AnimalLite; contact: Contact } | null>(null);
  const [voeuxMsg, setVoeuxMsg] = useState('');

  useEffect(() => {
    supabase.from('user_profiles_complet').select('cession_anniv_auto')
      .eq('uid', uid).eq('is_main', true).maybeSingle()
      .then(({ data }) => { setAnnivAuto(data?.cession_anniv_auto === true); setAnnivLoaded(true); });
  }, [uid]);

  async function toggleAnnivAuto(v: boolean) {
    setAnnivAuto(v);
    const { error } = await supabase.from('user_profiles')
      .update({ cession_anniv_auto: v }).eq('uid', uid).eq('is_main', true);
    if (error) setAnnivAuto(!v);
  }

  const cedes = animaux.filter(a => a.statut === 'sorti');

  const today = new Date(new Date().toDateString());

  // Dossiers de stérilisation : délais calculés depuis l'échéance contractuelle
  // enregistrée (jamais déduits d'un âge type). « Certificat reçu » = validé par
  // l'éleveur ; une échéance passée ne vaut jamais stérilisation réalisée.
  const sterilAll: DossierSuivi[] = cedes.filter(a => a.sterilisation_requise).map(a => {
    const ech = parseDate(a.sterilisation_echeance);
    const days = ech ? Math.round((new Date(ech.toDateString()).getTime() - today.getTime()) / 86400000) : null;
    const recu = !!a.sterilisation_validee;
    const statut: StatutSuivi = recu ? 'recu' : days != null && days < 0 ? 'retard' : 'a_faire';
    return { a, ech, days, statut, declaree: !!a.sterilise };
  });
  const nbASuivre = sterilAll.filter(d => d.statut !== 'recu').length;
  const nbRetard = sterilAll.filter(d => d.statut === 'retard').length;
  const nbRecus = sterilAll.filter(d => d.statut === 'recu').length;
  const qn = q.trim().toLowerCase();
  const rang: Record<StatutSuivi, number> = { retard: 0, a_faire: 1, recu: 2 };
  const sterilList = sterilAll.filter(d => {
    if (statutFiltre === 'a_suivre' && d.statut === 'recu') return false;
    if (statutFiltre !== 'a_suivre' && statutFiltre !== 'tous' && d.statut !== statutFiltre) return false;
    if (echeanceFiltre === 'depassees' && !(d.days != null && d.days < 0)) return false;
    if (echeanceFiltre === '30j' && !(d.days != null && d.days >= 0 && d.days <= 30)) return false;
    if (qn && ![d.a.nom, d.a.destinataire_nom, d.a.race].some(v => (v ?? '').toLowerCase().includes(qn))) return false;
    return true;
  }).sort((x, y) => rang[x.statut] - rang[y.statut]
    || (x.ech?.getTime() ?? Infinity) - (y.ech?.getTime() ?? Infinity));

  // Date de validation du certificat (ligne cession, si elle existe)
  const idsRecus = sterilAll.filter(d => d.statut === 'recu').map(d => d.a.id).join(',');
  useEffect(() => {
    if (!idsRecus) return;
    supabase.from('cessions').select('animal_id, sterilisation_validee_at')
      .in('animal_id', idsRecus.split(',')).not('sterilisation_validee_at', 'is', null)
      .then(({ data }) => {
        const m: Record<string, string> = {};
        for (const r of (data ?? []) as { animal_id: string; sterilisation_validee_at: string }[]) m[r.animal_id] = r.sterilisation_validee_at;
        setValideesLe(m);
      });
  }, [idsRecus]);

  const Echeance = ({ d, inline = false }: { d: DossierSuivi; inline?: boolean }) => {
    if (!d.ech) return <span className="text-gray-500">Échéance non renseignée</span>;
    const delai = d.statut === 'recu' || d.days == null ? null
      : d.days < 0 ? `Dépassée de ${-d.days} jour${-d.days > 1 ? 's' : ''}`
      : d.days === 0 ? 'Aujourd’hui' : `Dans ${d.days} jour${d.days > 1 ? 's' : ''}`;
    const rouge = d.statut === 'retard';
    return inline ? (
      <span className="text-gray-600">{fmtLong(d.ech)}{delai && <span className={rouge ? 'text-[#B91C1C]' : ''}> · {delai}</span>}</span>
    ) : (
      <span className="block">
        <span className="block text-[#1F2A2E]">{fmtLong(d.ech)}</span>
        {delai && <span className={`block text-xs ${rouge ? 'text-[#B91C1C]' : 'text-gray-500'}`}>{delai}</span>}
      </span>
    );
  };

  const BadgeStatut = ({ s, declaree }: { s: StatutSuivi; declaree: boolean }) => {
    const m = { a_faire: ['À faire', 'bg-gray-100 text-[#1F2A2E]'], retard: ['En retard', 'bg-red-50 text-[#DC2626]'], recu: ['Certificat reçu', 'bg-[#EAF2E5] text-[#4D7A3C]'] }[s];
    return (
      <span className="inline-flex flex-col items-start gap-0.5">
        <span className={`inline-block px-2.5 py-1 rounded-md text-xs font-medium whitespace-nowrap ${m[1]}`}>{m[0]}</span>
        {declaree && s !== 'recu' && <span className="text-[11px] text-gray-500">Déclarée par la famille</span>}
      </span>
    );
  };

  const ActionsSuivi = ({ d, mobile = false }: { d: DossierSuivi; mobile?: boolean }) => {
    const enCours = busy === d.a.id;
    const btn = `${mobile ? 'h-8 px-3 text-xs' : 'h-9 px-3 text-sm'} rounded-md border border-gray-300 text-[#1F2A2E] font-medium hover:border-[#0C5C6C] hover:text-[#0C5C6C] disabled:opacity-50 whitespace-nowrap`;
    const lien = `${mobile ? 'h-8 text-xs' : 'h-9 text-sm'} px-2 font-semibold text-[#0C5C6C] hover:underline disabled:opacity-50 whitespace-nowrap`;
    return (
      <div className={`flex items-center gap-2 ${mobile ? '' : 'justify-start'}`}>
        {d.statut === 'recu' ? (
          <button type="button" onClick={() => setCertif(d.a)} className={btn}>Voir le certificat</button>
        ) : (
          <>
            <button type="button" onClick={() => valider(d.a)} disabled={enCours} className={btn}>
              {enCours ? '…' : mobile ? 'Certificat' : 'Recevoir le certificat'}
            </button>
            <button type="button" onClick={() => openRelance(d.a)} disabled={enCours} className={lien}>Relancer</button>
          </>
        )}
        {!mobile && <MenuDossier a={d.a} />}
      </div>
    );
  };

  const anniv = cedes
    .map(a => {
      const dn = parseDate(a.date_naissance);
      if (!dn) return null;
      let next = new Date(today.getFullYear(), dn.getMonth(), dn.getDate());
      if (next < today) next = new Date(today.getFullYear() + 1, dn.getMonth(), dn.getDate());
      const days = Math.round((next.getTime() - today.getTime()) / 86400000);
      if (days > 60) return null;
      return { a, days, age: next.getFullYear() - dn.getFullYear() };
    })
    .filter((x): x is { a: AnimalLite; days: number; age: number } => x !== null)
    .sort((x, y) => x.days - y.days);

  async function valider(a: AnimalLite) {
    // L'éleveur peut valider dès réception du certificat vétérinaire, même si le
    // propriétaire n'a pas déclaré la stérilisation.
    if (!a.sterilise && !window.confirm(
      `Confirmez-vous avoir reçu le certificat de stérilisation vétérinaire pour ${a.nom ?? 'cet animal'} ?\n\n`
      + 'La stérilisation sera marquée comme faite et validée, et le propriétaire en sera informé.')) {
      return;
    }
    setBusy(a.id);
    try {
      await supabase.from('animaux').update({ sterilisation_validee: true, sterilise: true }).eq('id', a.id);
      await supabase.from('cessions')
        .update({ sterilisation_validee: true, sterilisation_validee_at: new Date().toISOString() })
        .eq('animal_id', a.id).eq('sterilisation_requise', true);
      if (a.uid_acquereur) {
        const { data: acqProfile } = await supabase.from('user_profiles_complet')
          .select('id').eq('uid', a.uid_acquereur).eq('is_main', true).maybeSingle();
        await supabase.from('notifications').insert({
          uid: a.uid_acquereur,
          type: 'sterilisation_validee',
          title: `Stérilisation validée — ${a.nom ?? 'Animal'}`,
          body: `L'éleveur a validé la stérilisation de ${a.nom ?? 'votre animal'}. Merci !`,
          ...(acqProfile?.id ? { profile_id: acqProfile.id } : {}),
          data: { animalId: a.id },
          read: false,
        });
      }
      onLocalUpdate(a.id, { sterilisation_validee: true, sterilise: true });
    } finally {
      setBusy(null);
    }
  }

  /// Vœux d'anniversaire — mêmes canaux que « Relancer la famille » :
  /// Application, WhatsApp, Email. Fonctionne même sans compte PetsMatch (les
  /// coordonnées viennent du contrat / de la fiche cession / de la correction
  /// manuelle, cf. [[project_cession_sterilisation]]).
  async function openVoeux(a: AnimalLite) {
    setBusy(a.id);
    try {
      const { contact: c } = await fetchContactAcquereur(a);
      const nom = a.nom ?? 'votre compagnon';
      const salut = c.prenom ? `Bonjour ${c.prenom},\n\n` : '';
      setVoeuxMsg(`${salut}Joyeux anniversaire ${nom} ! Toute l'équipe pense à lui aujourd'hui.`);
      setVoeux({ a, contact: c });
    } finally {
      setBusy(null);
    }
  }

  // ── Relance famille (stérilisation) ────────────────────────────────────────
  /// Profils pour taguer la conversation. `consumer_profile_id` = profil de
  /// l'acquéreur qui détient l'animal cédé (`profile_id_acquereur`), sinon son
  /// profil particulier, sinon principal. Ce profil-là doit voir la conversation
  /// ET la notification (cohérence). Sans tag, /messages masque la conversation.
  async function convTags(acqUid: string, a?: AnimalLite) {
    const { data: elevP } = await supabase.from('user_profiles_complet')
      .select('id').eq('uid', uid).eq('profile_type', 'eleveur').maybeSingle();
    let consumer = (a?.profile_id_acquereur ?? null) as string | null;
    if (!consumer) {
      const { data: part } = await supabase.from('user_profiles_complet')
        .select('id').eq('uid', acqUid).eq('profile_type', 'particulier').maybeSingle();
      consumer = part?.id ?? null;
    }
    if (!consumer) {
      const { data: main } = await supabase.from('user_profiles_complet')
        .select('id').eq('uid', acqUid).eq('is_main', true).maybeSingle();
      consumer = main?.id ?? null;
    }
    return { pro: (elevP?.id ?? activeProfileId ?? null) as string | null, consumer };
  }

  async function openOrCreateConv(acqUid: string, a?: AnimalLite): Promise<string> {
    const sorted = [senderUid, acqUid].sort().join('_');
    const { pro, consumer } = await convTags(acqUid, a);
    const { data: existing } = await supabase.from('conversations')
      .select('id, pro_profile_id, consumer_profile_id, categorie, deleted_for')
      .eq('participant_ids', sorted).or('type.eq.direct,type.is.null').maybeSingle();
    if (existing) {
      const patch: Record<string, unknown> = {};
      if (!existing.pro_profile_id && pro) patch.pro_profile_id = pro;
      if (!existing.consumer_profile_id && consumer) patch.consumer_profile_id = consumer;
      if (!existing.categorie || existing.categorie === 'elevage') patch.categorie = 'contact-elevage';
      if (existing.deleted_for && Object.keys(existing.deleted_for).length) patch.deleted_for = {};
      if (Object.keys(patch).length) await supabase.from('conversations').update(patch).eq('id', existing.id);
      return existing.id;
    }
    const { data: me } = await supabase.from('user_profiles_complet')
      .select('firstname, lastname, nom, avatar_url').eq('uid', senderUid).eq('is_main', true).maybeSingle();
    const { data: other } = await supabase.from('user_profiles_complet')
      .select('firstname, lastname, nom, avatar_url').eq('uid', acqUid).eq('is_main', true).maybeSingle();
    const myName = (me?.nom || `${me?.firstname ?? ''} ${me?.lastname ?? ''}`.trim()) || 'Élevage';
    const otherName = `${other?.firstname ?? ''} ${other?.lastname ?? ''}`.trim() || (other?.nom ?? 'Utilisateur');
    const { data: created } = await supabase.from('conversations').insert({
      type: 'direct',
      participants: [senderUid, acqUid],
      participant_ids: sorted,
      participants_info: {
        [senderUid]: { name: myName, ...(me?.avatar_url ? { photo: me.avatar_url } : {}) },
        [acqUid]: { name: otherName, ...(other?.avatar_url ? { photo: other.avatar_url } : {}) },
      },
      last_message: '',
      unread_count: { [senderUid]: 0, [acqUid]: 0 },
      updated_at: new Date().toISOString(),
      categorie: 'contact-elevage',
      ...(pro ? { pro_profile_id: pro } : {}),
      ...(consumer ? { consumer_profile_id: consumer } : {}),
    }).select('id').single();
    return created!.id;
  }

  async function postToConv(convId: string, texte: string) {
    await supabase.from('messages').insert({
      conversation_id: convId, sender_id: senderUid, text: texte, msg_type: 'text', is_read: false,
    });
    const { data: conv } = await supabase.from('conversations')
      .select('participants, unread_count').eq('id', convId).maybeSingle();
    if (conv) {
      const members: string[] = (conv.participants ?? []).map((x: unknown) => String(x));
      const unread: Record<string, number> = { ...(conv.unread_count ?? {}) };
      for (const m of members) if (m !== senderUid) unread[m] = (unread[m] ?? 0) + 1;
      await supabase.from('conversations').update({
        last_message: texte, unread_count: unread, updated_at: new Date().toISOString(),
        // Un nouveau message fait réapparaître la conversation si le
        // destinataire l'avait supprimée de sa liste.
        deleted_for: {},
      }).eq('id', convId);
    }
  }

  async function openRelance(a: AnimalLite) {
    setBusy(a.id);
    try {
      const { contact: c } = await fetchContactAcquereur(a);

      const nomA = a.nom ?? "l'animal";
      const ech = parseDate(a.sterilisation_echeance);
      const echStr = ech ? fmt(ech) : null;
      const salut = c.prenom ? `Bonjour ${c.prenom},` : 'Bonjour,';
      const msg = a.sterilise
        ? `${salut}\n\nLa stérilisation de ${nomA} a bien été déclarée. Pourriez-vous nous transmettre le certificat vétérinaire afin que nous puissions la valider ? Merci beaucoup.`
        : `${salut}\n\nPetit rappel concernant la stérilisation de ${nomA}${echStr ? `, à réaliser avant le ${echStr}` : ''}. Merci de nous transmettre le certificat vétérinaire une fois l'intervention réalisée. Bien à vous.`;
      setRelanceMsg(msg);
      setRelance({ a, contact: c });
    } finally {
      setBusy(null);
    }
  }

  /// Envoi in-app générique (message dans la conversation élevage + notif),
  /// réutilisé par le canal « Application » de la relance et des vœux.
  async function envoyerInApp(a: AnimalLite, texte: string, notifType: string, notifTitre: string, onDone: () => void) {
    if (!a.uid_acquereur || !texte) return;
    if (a.uid_acquereur === senderUid) {
      alert("L'acquéreur est votre propre compte : le message in-app ne peut pas s'afficher. "
        + 'Testez avec un autre compte, ou par WhatsApp / Email.');
      return;
    }
    setBusy(a.id);
    try {
      const { consumer } = await convTags(a.uid_acquereur, a);
      const convId = await openOrCreateConv(a.uid_acquereur, a);
      await postToConv(convId, texte);
      // Un simple message est déjà notifié par le trigger trg_notify_new_message ;
      // seule la relance (type dédié) mérite sa propre notif.
      if (notifType !== 'message') await supabase.from('notifications').insert({
        uid: a.uid_acquereur,
        type: notifType,
        title: notifTitre,
        body: texte.length > 140 ? texte.slice(0, 137) + '…' : texte,
        ...(consumer ? { profile_id: consumer } : {}),
        data: { animalId: a.id },
        read: false,
      });
      onDone();
      alert('Message envoyé dans l\'application.');
    } finally {
      setBusy(null);
    }
  }

  if (cedes.length === 0) {
    return (
      <div className="text-center py-16 px-4 bg-white border border-dashed border-gray-300 rounded-lg">
        <p className="text-[15px] font-semibold text-[#1F2A2E]">Aucun animal cédé</p>
        <p className="text-sm text-gray-500 mt-1">Le suivi des stérilisations et les anniversaires de vos animaux cédés apparaîtront ici.</p>
      </div>
    );
  }

  const filtresActifs = !!q || statutFiltre !== 'a_suivre' || echeanceFiltre !== 'toutes';

  return (
    <div className="space-y-8">
      {/* ── Suivi des stérilisations ── */}
      <section className="bg-white border border-gray-200 rounded-lg p-4 sm:p-5">
        <h2 className="text-lg font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Suivi des stérilisations</h2>
        <p className="text-sm text-gray-500 mt-0.5">Échéances, certificats et relances des familles.</p>

        {/* Compteurs */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mt-4">
          {([
            ['À suivre', nbASuivre, 'bg-[#E8F4F6] text-[#0C5C6C]', <svg key="i" className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth={1.8} viewBox="0 0 24 24" aria-hidden><circle cx="12" cy="12" r="9" /><path strokeLinecap="round" d="M12 7.5V12l3 2" /></svg>],
            ['Échéances dépassées', nbRetard, 'bg-red-50 text-[#DC2626]', <svg key="i" className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth={2.2} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" d="M12 6v8M12 18h.01" /></svg>],
            ['Certificats reçus', nbRecus, 'bg-[#EAF2E5] text-[#4D7A3C]', <svg key="i" className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth={1.6} viewBox="0 0 24 24" aria-hidden><path strokeLinecap="round" strokeLinejoin="round" d="M19.5 14.25v-2.63a3.38 3.38 0 00-3.38-3.37h-1.5a1.13 1.13 0 01-1.12-1.13v-1.5a3.38 3.38 0 00-3.38-3.37H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.63c-.62 0-1.13.5-1.13 1.13v17.25c0 .62.5 1.12 1.13 1.12h12.75c.62 0 1.12-.5 1.12-1.12V11.25a9 9 0 00-9-9z" /></svg>],
          ] as const).map(([label, n, pastille, icone]) => (
            <div key={label} className="flex items-center gap-4 border border-gray-200 rounded-lg px-4 py-3">
              <span className={`w-11 h-11 rounded-full flex items-center justify-center flex-shrink-0 ${pastille}`}>{icone}</span>
              <span>
                <span className="block text-sm text-gray-600">{label}</span>
                <span className="block text-2xl font-bold text-[#1F2A2E] tabular-nums leading-tight">{n}</span>
              </span>
            </div>
          ))}
        </div>

        {/* Recherche + filtres */}
        <div className="flex flex-col sm:flex-row gap-2 mt-4">
          <label className="relative flex-1 min-w-0">
            <span className="sr-only">Rechercher un animal ou une famille</span>
            <svg className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-gray-400" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24" aria-hidden>
              <path strokeLinecap="round" d="M21 21l-5.2-5.2m0 0A7.5 7.5 0 105.2 5.2a7.5 7.5 0 0010.6 10.6z" />
            </svg>
            <input type="search" value={q} onChange={e => setQ(e.target.value)} placeholder="Rechercher un animal ou une famille"
              className="w-full h-10 pl-9 pr-3 rounded-lg border border-gray-300 bg-white text-sm focus:outline-none focus:border-[#0C5C6C]" />
          </label>
          <div className="grid grid-cols-2 gap-2 sm:flex">
            <select value={statutFiltre} onChange={e => setStatutFiltre(e.target.value as StatutFiltre)} aria-label="Statut"
              className="h-10 rounded-lg border border-gray-300 bg-white px-3 text-sm focus:outline-none focus:border-[#0C5C6C]">
              <option value="a_suivre">Statut : À suivre</option>
              <option value="tous">Statut : Tous</option>
              <option value="a_faire">Statut : À faire</option>
              <option value="retard">Statut : En retard</option>
              <option value="recu">Statut : Certificat reçu</option>
            </select>
            <select value={echeanceFiltre} onChange={e => setEcheanceFiltre(e.target.value as EcheanceFiltre)} aria-label="Échéance"
              className="h-10 rounded-lg border border-gray-300 bg-white px-3 text-sm focus:outline-none focus:border-[#0C5C6C]">
              <option value="toutes">Échéance : Toutes</option>
              <option value="depassees">Échéance : Dépassées</option>
              <option value="30j">Échéance : 30 prochains jours</option>
            </select>
          </div>
        </div>

        {sterilAll.length === 0 ? (
          <p className="text-sm text-gray-500 mt-5">Aucune condition de stérilisation sur vos cessions.</p>
        ) : sterilList.length === 0 ? (
          <div className="text-center py-10 mt-4 border border-dashed border-gray-300 rounded-lg">
            <p className="text-sm font-semibold text-[#1F2A2E]">Aucun suivi ne correspond à vos filtres</p>
            {filtresActifs && (
              <button type="button" onClick={() => { setQ(''); setStatutFiltre('a_suivre'); setEcheanceFiltre('toutes'); }}
                className="mt-2 text-sm font-semibold text-[#0C5C6C] hover:underline">Réinitialiser les filtres</button>
            )}
          </div>
        ) : (
          <>
            {/* Ordinateur : tableau */}
            <div className="hidden md:block mt-4 border border-gray-200 rounded-lg overflow-hidden">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 text-left text-xs font-semibold text-gray-600">
                  <tr>
                    <th className="px-4 py-3">Animal</th>
                    <th className="px-4 py-3">Famille</th>
                    <th className="px-4 py-3">Échéance</th>
                    <th className="px-4 py-3">Statut</th>
                    <th className="px-4 py-3">Actions</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {sterilList.map(d => (
                    <tr key={d.a.id} className="align-middle">
                      <td className="px-4 py-3">
                        <Link href={`/mes-animaux/${d.a.id}`} className="flex items-center gap-3 group">
                          <Avatar a={d.a} />
                          <span className="min-w-0">
                            <span className="block font-semibold text-[#1F2A2E] group-hover:underline truncate">{d.a.nom ?? 'Sans nom'}</span>
                            {d.a.race && <span className="block text-xs text-gray-500 truncate">{d.a.race}</span>}
                          </span>
                        </Link>
                      </td>
                      <td className="px-4 py-3 text-[#1F2A2E]">{d.a.destinataire_nom || <span className="text-gray-400">—</span>}</td>
                      <td className="px-4 py-3"><Echeance d={d} /></td>
                      <td className="px-4 py-3"><BadgeStatut s={d.statut} declaree={d.declaree} /></td>
                      <td className="px-4 py-3"><ActionsSuivi d={d} /></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>

            {/* Mobile : cartes compactes */}
            <div className="md:hidden mt-4 space-y-2">
              {sterilList.map(d => (
                <div key={d.a.id} className="border border-gray-200 rounded-lg p-3">
                  <div className="flex items-start gap-3">
                    <Link href={`/mes-animaux/${d.a.id}`} className="flex-shrink-0"><Avatar a={d.a} /></Link>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-start justify-between gap-2">
                        <Link href={`/mes-animaux/${d.a.id}`} className="font-semibold text-sm text-[#1F2A2E] truncate hover:underline">
                          {d.a.nom ?? 'Sans nom'}{d.a.race && <span className="font-normal text-gray-500"> · {d.a.race}</span>}
                        </Link>
                        <BadgeStatut s={d.statut} declaree={false} />
                      </div>
                      <p className="text-xs text-gray-600 truncate">{d.a.destinataire_nom || 'Famille non renseignée'}</p>
                      <div className="text-xs mt-0.5"><Echeance d={d} inline /></div>
                      {d.declaree && d.statut !== 'recu' && <p className="text-[11px] text-gray-500">Stérilisation déclarée par la famille</p>}
                    </div>
                  </div>
                  <div className="mt-2.5 flex items-center justify-between gap-2"><ActionsSuivi d={d} mobile /><MenuDossier a={d.a} /></div>
                </div>
              ))}
            </div>
          </>
        )}
      </section>

      {/* ── Anniversaires ── */}
      <section className="bg-white border border-gray-200 rounded-lg p-4 sm:p-5">
        <h2 className="text-lg font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Anniversaires</h2>
        <p className="text-sm text-gray-500 mt-0.5">Animaux cédés fêtant leur anniversaire dans les 60 prochains jours.</p>
        {annivLoaded && (
          <label className="flex items-start gap-2 mt-3 cursor-pointer">
            <input type="checkbox" checked={annivAuto} onChange={e => toggleAnnivAuto(e.target.checked)}
              className="mt-0.5 accent-[#0C5C6C] w-4 h-4" />
            <span>
              <span className="block text-sm font-semibold text-[#1F2A2E]">Message d&apos;anniversaire automatique</span>
              <span className="block text-xs text-gray-500">Envoie chaque année un message de vœux aux acquéreurs qui ont l&apos;application.</span>
            </span>
          </label>
        )}
        {anniv.length === 0 ? (
          <p className="text-sm text-gray-500 mt-3">Aucun anniversaire dans les 60 prochains jours.</p>
        ) : (
          <div className="mt-3 border border-gray-200 rounded-lg divide-y divide-gray-100">
            {anniv.map(({ a, days, age }) => (
              <div key={a.id} className="flex items-center gap-3 px-3 py-2.5">
                <Link href={`/mes-animaux/${a.id}`} className="flex-shrink-0"><Avatar a={a} /></Link>
                <div className="flex-1 min-w-0">
                  <p className="text-sm font-semibold text-[#1F2A2E] truncate">{a.nom ?? 'Sans nom'}</p>
                  <p className="text-xs text-gray-500">
                    {days === 0 ? `Aujourd'hui · ${age} an${age > 1 ? 's' : ''}` : `Dans ${days} jour${days > 1 ? 's' : ''} · aura ${age} an${age > 1 ? 's' : ''}`}
                  </p>
                </div>
                <button onClick={() => openVoeux(a)} disabled={busy === a.id}
                  className="h-9 px-3 rounded-lg border border-[#0C5C6C] text-[#0C5C6C] text-sm font-semibold hover:bg-[#E8F4F6] disabled:opacity-50 whitespace-nowrap">
                  {busy === a.id ? '…' : 'Envoyer mes vœux'}
                </button>
                <MenuDossier a={a} />
              </div>
            ))}
          </div>
        )}
      </section>

      {/* ── Modale « Voir le certificat » ── */}
      {certif && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 sm:p-4" onClick={() => setCertif(null)}>
          <div className="bg-white rounded-t-xl sm:rounded-xl w-full sm:max-w-md p-5" onClick={e => e.stopPropagation()}>
            <h3 className="font-bold text-[#1F2A2E] text-base" style={{ fontFamily: 'Galey, sans-serif' }}>Certificat de stérilisation — {certif.nom ?? 'Animal'}</h3>
            <p className="text-sm text-[#4D7A3C] font-semibold mt-3">Certificat reçu{valideesLe[certif.id] ? ` le ${fmt(new Date(valideesLe[certif.id]))}` : ''}</p>
            <p className="text-sm text-gray-600 mt-1">La stérilisation a été validée à réception du certificat vétérinaire. Aucun fichier n’est joint dans PetsMatch : les documents de l’animal se trouvent dans sa fiche, onglet Administratif.</p>
            <div className="flex gap-2 mt-4">
              <Link href={`/mes-animaux/${certif.id}`} className="flex-1 h-10 inline-flex items-center justify-center rounded-lg bg-[#0C5C6C] text-white text-sm font-semibold hover:bg-[#094F5D]">Ouvrir la fiche</Link>
              <button type="button" onClick={() => setCertif(null)} className="flex-1 h-10 rounded-lg border border-gray-300 text-sm font-semibold text-gray-700 hover:bg-gray-50">Fermer</button>
            </div>
          </div>
        </div>
      )}

      {/* ── Modale « Relancer la famille » ── */}
      {relance && (() => {
        const c = relance.contact;
        const a = relance.a;
        const aucune = !c.prenom && !c.nom && !c.tel && !c.email && !c.adresse;
        return (
          <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 sm:p-4"
            onClick={() => setRelance(null)}>
            <div className="bg-white rounded-t-2xl sm:rounded-2xl w-full sm:max-w-md p-5 max-h-[90vh] overflow-y-auto"
              onClick={e => e.stopPropagation()}>
              <h3 className="font-bold text-[#1F2A2E] text-base mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>
                Relancer la famille — {a.nom ?? 'Animal'}
              </h3>
              <div className="rounded-xl bg-gray-50 border border-gray-200 p-3 text-xs space-y-1 mb-3">
                {(c.prenom || c.nom) && <p><span className="text-gray-500">Destinataire : </span>{[c.prenom, c.nom].filter(Boolean).join(' ')}</p>}
                {c.tel && <p><span className="text-gray-500">Téléphone : </span><a href={`tel:${c.tel}`} className="text-[#0C5C6C] font-medium">{c.tel}</a></p>}
                {c.email && <p><span className="text-gray-500">Email : </span>{c.email}</p>}
                {c.adresse && <p><span className="text-gray-500">Adresse : </span>{c.adresse}</p>}
                {aucune && <p className="text-gray-500">Aucune coordonnée dans le contrat.</p>}
              </div>
              <textarea value={relanceMsg} onChange={e => setRelanceMsg(e.target.value)} rows={6}
                className="w-full border border-gray-300 rounded-xl p-3 text-sm resize-none focus:outline-none focus:border-[#0C5C6C]" />
              <p className="text-[11px] font-bold text-gray-400 tracking-wide mt-3 mb-2">ENVOYER VIA</p>
              <div className="flex flex-wrap gap-2">
                {a.uid_acquereur && (
                  <button onClick={() => envoyerInApp(a, relanceMsg.trim(), 'sterilisation_relance',
                      `Rappel stérilisation — ${a.nom ?? 'votre animal'}`, () => setRelance(null))}
                    disabled={busy === a.id}
                    className="px-3.5 py-2 rounded-xl text-xs font-bold text-[#0C5C6C] bg-[#0C5C6C]/10 border border-[#0C5C6C]/30 disabled:opacity-50">
                    Application
                  </button>
                )}
                {c.tel && (
                  <a href={`https://wa.me/${waPhone(c.tel)}?text=${encodeURIComponent(relanceMsg.trim())}`}
                    target="_blank" rel="noopener noreferrer" onClick={() => setRelance(null)}
                    className="px-3.5 py-2 rounded-xl text-xs font-bold text-[#1a9e4b] bg-[#25D366]/10 border border-[#25D366]/40">
                    WhatsApp
                  </a>
                )}
                {c.email && (
                  <a href={`mailto:${c.email}?subject=${encodeURIComponent(`Stérilisation ${a.nom ?? ''} — rappel`)}&body=${encodeURIComponent(relanceMsg.trim())}`}
                    onClick={() => setRelance(null)}
                    className="px-3.5 py-2 rounded-xl text-xs font-bold text-[#EA4335] bg-[#EA4335]/10 border border-[#EA4335]/30">
                    Email
                  </a>
                )}
              </div>
              <button onClick={() => setRelance(null)} className="mt-4 w-full text-xs text-gray-500 py-2">Fermer</button>
            </div>
          </div>
        );
      })()}

      {/* ── Modale « Vœux d'anniversaire » ── */}
      {voeux && (() => {
        const c = voeux.contact;
        const a = voeux.a;
        const aucune = !c.prenom && !c.nom && !c.tel && !c.email && !c.adresse;
        return (
          <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 sm:p-4"
            onClick={() => setVoeux(null)}>
            <div className="bg-white rounded-t-2xl sm:rounded-2xl w-full sm:max-w-md p-5 max-h-[90vh] overflow-y-auto"
              onClick={e => e.stopPropagation()}>
              <h3 className="font-bold text-[#1F2A2E] text-base mb-3" style={{ fontFamily: 'Galey, sans-serif' }}>
                Envoyer mes vœux — {a.nom ?? 'Animal'}
              </h3>
              <div className="rounded-xl bg-gray-50 border border-gray-200 p-3 text-xs space-y-1 mb-3">
                {(c.prenom || c.nom) && <p><span className="text-gray-500">Destinataire : </span>{[c.prenom, c.nom].filter(Boolean).join(' ')}</p>}
                {c.tel && <p><span className="text-gray-500">Téléphone : </span><a href={`tel:${c.tel}`} className="text-[#0C5C6C] font-medium">{c.tel}</a></p>}
                {c.email && <p><span className="text-gray-500">Email : </span>{c.email}</p>}
                {c.adresse && <p><span className="text-gray-500">Adresse : </span>{c.adresse}</p>}
                {aucune && <p className="text-gray-500">Aucune coordonnée connue pour cet animal.</p>}
              </div>
              <textarea value={voeuxMsg} onChange={e => setVoeuxMsg(e.target.value)} rows={6}
                className="w-full border border-gray-300 rounded-xl p-3 text-sm resize-none focus:outline-none focus:border-[#0C5C6C]" />
              <p className="text-[11px] font-bold text-gray-400 tracking-wide mt-3 mb-2">ENVOYER VIA</p>
              <div className="flex flex-wrap gap-2">
                {a.uid_acquereur && (
                  <button onClick={async () => {
                      const { data: me } = await supabase.from('user_profiles_complet')
                        .select('firstname, lastname, nom').eq('uid', senderUid).eq('is_main', true).maybeSingle();
                      const myName = (me?.nom || `${me?.firstname ?? ''} ${me?.lastname ?? ''}`.trim()) || 'Votre éleveur';
                      envoyerInApp(a, voeuxMsg.trim(), 'message', myName, () => setVoeux(null));
                    }}
                    disabled={busy === a.id}
                    className="px-3.5 py-2 rounded-xl text-xs font-bold text-[#0C5C6C] bg-[#0C5C6C]/10 border border-[#0C5C6C]/30 disabled:opacity-50">
                    Application
                  </button>
                )}
                {c.tel && (
                  <a href={`https://wa.me/${waPhone(c.tel)}?text=${encodeURIComponent(voeuxMsg.trim())}`}
                    target="_blank" rel="noopener noreferrer" onClick={() => setVoeux(null)}
                    className="px-3.5 py-2 rounded-xl text-xs font-bold text-[#1a9e4b] bg-[#25D366]/10 border border-[#25D366]/40">
                    WhatsApp
                  </a>
                )}
                {c.email && (
                  <a href={`mailto:${c.email}?subject=${encodeURIComponent(`Joyeux anniversaire ${a.nom ?? ''}`)}&body=${encodeURIComponent(voeuxMsg.trim())}`}
                    onClick={() => setVoeux(null)}
                    className="px-3.5 py-2 rounded-xl text-xs font-bold text-[#EA4335] bg-[#EA4335]/10 border border-[#EA4335]/30">
                    Email
                  </a>
                )}
              </div>
              <button onClick={() => setVoeux(null)} className="mt-4 w-full text-xs text-gray-500 py-2">Fermer</button>
            </div>
          </div>
        );
      })()}
    </div>
  );
}

function MenuDossier({ a }: { a: AnimalLite }) {
  const [ouvert, setOuvert] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (!ouvert) return;
    const fermer = (e: MouseEvent) => { if (ref.current && !ref.current.contains(e.target as Node)) setOuvert(false); };
    document.addEventListener('mousedown', fermer);
    return () => document.removeEventListener('mousedown', fermer);
  }, [ouvert]);
  return (
    <div ref={ref} className="relative">
      <button type="button" onClick={() => setOuvert(o => !o)} aria-label={`Autres actions pour ${a.nom ?? 'cet animal'}`} aria-expanded={ouvert}
        className="w-8 h-8 rounded-md text-gray-500 hover:bg-gray-100 flex items-center justify-center">
        <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 24 24" aria-hidden><circle cx="5" cy="12" r="1.6" /><circle cx="12" cy="12" r="1.6" /><circle cx="19" cy="12" r="1.6" /></svg>
      </button>
      {ouvert && (
        <div className="absolute right-0 top-9 z-20 w-56 bg-white border border-gray-200 rounded-lg shadow-lg py-1">
          <ContactAcquereurButton animal={a} variante="menu" />
          <Link href={`/mes-animaux/${a.id}`} className="block px-3 py-2 text-sm text-[#1F2A2E] hover:bg-gray-50">Ouvrir la fiche</Link>
        </div>
      )}
    </div>
  );
}

function Avatar({ a }: { a: AnimalLite }) {
  const [erreur, setErreur] = useState(false);
  return a.photo_url && !erreur
    // eslint-disable-next-line @next/next/no-img-element
    ? <img src={a.photo_url} alt="" onError={() => setErreur(true)} className="w-11 h-11 rounded-md object-cover flex-shrink-0" />
    : (
      <div className="w-11 h-11 rounded-md bg-[#EDF2F2] text-[#8B9FA1] flex items-center justify-center flex-shrink-0" aria-hidden>
        <svg className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth={1.5} viewBox="0 0 24 24"><path strokeLinecap="round" strokeLinejoin="round" d="M2.25 15.75l5.16-5.16a2.25 2.25 0 013.18 0l5.16 5.16m-1.5-1.5l1.41-1.41a2.25 2.25 0 013.18 0l2.91 2.91M3.75 21h16.5A1.5 1.5 0 0021.75 19.5V4.5A1.5 1.5 0 0020.25 3H3.75A1.5 1.5 0 002.25 4.5v15A1.5 1.5 0 003.75 21z" /></svg>
      </div>
    );
}
