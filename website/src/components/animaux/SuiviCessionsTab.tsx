'use client';

import { useState, useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';

interface AnimalLite {
  id: string;
  nom?: string;
  race?: string;
  photo_url?: string;
  statut?: string;
  date_naissance?: string;
  uid_acquereur?: string | null;
  destinataire_nom?: string | null;
  sterilise?: boolean | null;
  sterilisation_requise?: boolean | null;
  sterilisation_echeance?: string | null;
  sterilisation_validee?: boolean | null;
}

interface Props {
  animaux: AnimalLite[];
  uid: string;
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

/** Téléphone au format international sans « + » pour wa.me (France par défaut). */
function waPhone(raw: string): string {
  let d = raw.replace(/[^0-9]/g, '');
  if (d.startsWith('00')) d = d.slice(2);
  if (d.startsWith('0')) d = '33' + d.slice(1);
  return d;
}

export default function SuiviCessionsTab({ animaux, uid, activeProfileId, onLocalUpdate }: Props) {
  const router = useRouter();
  const [nonFaitesOnly, setNonFaitesOnly] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [annivAuto, setAnnivAuto] = useState(false);
  const [annivLoaded, setAnnivLoaded] = useState(false);
  const [relance, setRelance] = useState<{ a: AnimalLite; contact: Contact } | null>(null);
  const [relanceMsg, setRelanceMsg] = useState('');

  useEffect(() => {
    supabase.from('user_profiles').select('cession_anniv_auto')
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

  let sterilList = cedes.filter(a => a.sterilisation_requise);
  const sterilCount = sterilList.length;
  if (nonFaitesOnly) sterilList = sterilList.filter(a => !a.sterilise || !a.sterilisation_validee);
  sterilList = [...sterilList].sort((a, b) => {
    const da = parseDate(a.sterilisation_echeance)?.getTime() ?? Infinity;
    const db = parseDate(b.sterilisation_echeance)?.getTime() ?? Infinity;
    return da - db;
  });

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
        const { data: acqProfile } = await supabase.from('user_profiles')
          .select('id').eq('uid', a.uid_acquereur).eq('is_main', true).maybeSingle();
        await supabase.from('notifications').insert({
          uid: a.uid_acquereur,
          type: 'sterilisation_validee',
          title: `✅ Stérilisation validée — ${a.nom ?? 'Animal'}`,
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

  async function envoyerVoeux(a: AnimalLite) {
    if (!a.uid_acquereur) return;
    const nom = a.nom ?? 'votre compagnon';
    const texte = window.prompt(
      'Message d\'anniversaire à envoyer à l\'acquéreur :',
      `Joyeux anniversaire ${nom} ! 🎂 Toute l'équipe pense à lui aujourd'hui.`,
    );
    if (!texte || !texte.trim()) return;
    setBusy(a.id);
    try {
      const convId = await openOrCreateConv(a.uid_acquereur);
      await postToConv(convId, texte.trim());
      router.push(`/messages?conv=${convId}`);
    } finally {
      setBusy(null);
    }
  }

  // ── Relance famille (stérilisation) ────────────────────────────────────────
  /// Profils pour taguer la conversation : sans `pro_profile_id` +
  /// `consumer_profile_id`, la liste /messages masque la conversation « sans
  /// profil » à l'acquéreur (profil particulier). Backfill si elle existe déjà.
  async function convTags(acqUid: string) {
    const [{ data: elevP }, { data: acqP }] = await Promise.all([
      supabase.from('user_profiles').select('id').eq('uid', uid).eq('profile_type', 'eleveur').maybeSingle(),
      supabase.from('user_profiles').select('id').eq('uid', acqUid).eq('profile_type', 'particulier').maybeSingle(),
    ]);
    return { pro: (elevP?.id ?? activeProfileId ?? null) as string | null, consumer: (acqP?.id ?? null) as string | null };
  }

  async function openOrCreateConv(acqUid: string): Promise<string> {
    const sorted = [uid, acqUid].sort().join('_');
    const { pro, consumer } = await convTags(acqUid);
    const { data: existing } = await supabase.from('conversations')
      .select('id, pro_profile_id, consumer_profile_id, categorie')
      .eq('participant_ids', sorted).or('type.eq.direct,type.is.null').maybeSingle();
    if (existing) {
      const patch: Record<string, unknown> = {};
      if (!existing.pro_profile_id && pro) patch.pro_profile_id = pro;
      if (!existing.consumer_profile_id && consumer) patch.consumer_profile_id = consumer;
      if (!existing.categorie || existing.categorie === 'elevage') patch.categorie = 'contact-elevage';
      if (Object.keys(patch).length) await supabase.from('conversations').update(patch).eq('id', existing.id);
      return existing.id;
    }
    const { data: me } = await supabase.from('user_profiles')
      .select('firstname, lastname, nom, avatar_url').eq('uid', uid).eq('is_main', true).maybeSingle();
    const { data: other } = await supabase.from('user_profiles')
      .select('firstname, lastname, nom, avatar_url').eq('uid', acqUid).eq('is_main', true).maybeSingle();
    const myName = (me?.nom || `${me?.firstname ?? ''} ${me?.lastname ?? ''}`.trim()) || 'Élevage';
    const otherName = `${other?.firstname ?? ''} ${other?.lastname ?? ''}`.trim() || (other?.nom ?? 'Utilisateur');
    const { data: created } = await supabase.from('conversations').insert({
      type: 'direct',
      participants: [uid, acqUid],
      participant_ids: sorted,
      participants_info: {
        [uid]: { name: myName, ...(me?.avatar_url ? { photo: me.avatar_url } : {}) },
        [acqUid]: { name: otherName, ...(other?.avatar_url ? { photo: other.avatar_url } : {}) },
      },
      last_message: '',
      unread_count: { [uid]: 0, [acqUid]: 0 },
      updated_at: new Date().toISOString(),
      categorie: 'contact-elevage',
      ...(pro ? { pro_profile_id: pro } : {}),
      ...(consumer ? { consumer_profile_id: consumer } : {}),
    }).select('id').single();
    return created!.id;
  }

  async function postToConv(convId: string, texte: string) {
    await supabase.from('messages').insert({
      conversation_id: convId, sender_id: uid, text: texte, msg_type: 'text', is_read: false,
    });
    const { data: conv } = await supabase.from('conversations')
      .select('participants, unread_count').eq('id', convId).maybeSingle();
    if (conv) {
      const members: string[] = (conv.participants ?? []).map((x: unknown) => String(x));
      const unread: Record<string, number> = { ...(conv.unread_count ?? {}) };
      for (const m of members) if (m !== uid) unread[m] = (unread[m] ?? 0) + 1;
      await supabase.from('conversations').update({
        last_message: texte, unread_count: unread, updated_at: new Date().toISOString(),
      }).eq('id', convId);
    }
  }

  async function openRelance(a: AnimalLite) {
    setBusy(a.id);
    try {
      const c: Contact = {};
      const put = (k: keyof Contact, v: unknown) => {
        const s = (v ?? '').toString().trim();
        if (s && !c[k]) c[k] = s;
      };
      // Priorité : profil particulier de l'acquéreur (s'il est utilisateur, ses
      // coordonnées sont à jour) → contrat signé → ligne cessions.
      if (a.uid_acquereur) {
        const { data: p } = await supabase.from('user_profiles')
          .select('firstname, lastname, phone_number, email_contact, adresse, rue, code_postal, ville')
          .eq('uid', a.uid_acquereur).eq('profile_type', 'particulier').maybeSingle();
        if (p) {
          put('prenom', p.firstname); put('nom', p.lastname);
          put('tel', p.phone_number); put('email', p.email_contact);
          put('adresse', p.adresse ?? [p.rue, p.code_postal, p.ville].filter(Boolean).join(' '));
        }
      }

      const { data: doc } = await supabase.from('documents_animaux')
        .select('metadata')
        .eq('animal_id', a.id)
        .in('type', ['contrat_vente', 'certificat_cession'])
        .order('created_at', { ascending: false })
        .limit(1).maybeSingle();
      const m = (doc?.metadata ?? {}) as Record<string, unknown>;
      put('prenom', m.acquereur_prenom);
      put('nom', m.acquereur_nom_famille ?? m.acquereur_nom);
      put('tel', m.acquereur_tel);
      put('email', m.acquereur_email);
      put('adresse', [m.acquereur_adresse, [m.acquereur_cp, m.acquereur_ville].filter(Boolean).join(' ')]
        .filter((x) => x && String(x).trim()).join(', '));

      const { data: cs } = await supabase.from('cessions')
        .select('prenom_acquereur, nom_acquereur, tel_acquereur, email_acquereur, adresse_acquereur')
        .eq('animal_id', a.id).order('created_at', { ascending: false }).limit(1).maybeSingle();
      if (cs) {
        put('prenom', cs.prenom_acquereur); put('nom', cs.nom_acquereur);
        put('tel', cs.tel_acquereur); put('email', cs.email_acquereur); put('adresse', cs.adresse_acquereur);
      }
      put('nom', a.destinataire_nom);

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

  async function relanceInApp(a: AnimalLite, texte: string) {
    if (!a.uid_acquereur || !texte) return;
    setBusy(a.id);
    try {
      const convId = await openOrCreateConv(a.uid_acquereur);
      await postToConv(convId, texte);
      const { data: acqProfile } = await supabase.from('user_profiles')
        .select('id').eq('uid', a.uid_acquereur).eq('is_main', true).maybeSingle();
      await supabase.from('notifications').insert({
        uid: a.uid_acquereur,
        type: 'sterilisation_relance',
        title: `✂️ Rappel stérilisation — ${a.nom ?? 'votre animal'}`,
        body: texte.length > 140 ? texte.slice(0, 137) + '…' : texte,
        ...(acqProfile?.id ? { profile_id: acqProfile.id } : {}),
        data: { animalId: a.id },
        read: false,
      });
      setRelance(null);
      alert('Relance envoyée dans l\'application ✅');
    } finally {
      setBusy(null);
    }
  }

  if (cedes.length === 0) {
    return (
      <div className="flex flex-col items-center py-20 text-center">
        <span className="text-5xl mb-4">🐾</span>
        <p className="text-gray-500 font-medium" style={{ fontFamily: 'Galey, sans-serif' }}>Aucun animal cédé</p>
        <p className="text-xs text-gray-400 mt-1">Le suivi de stérilisation et les anniversaires de vos chiots cédés apparaîtront ici.</p>
      </div>
    );
  }

  return (
    <div className="space-y-8">
      {/* ── Stérilisation ── */}
      <section>
        <div className="flex items-center justify-between mb-3">
          <h3 className="text-base font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>✂️ Stérilisation</h3>
          {sterilCount > 0 && (
            <button onClick={() => setNonFaitesOnly(v => !v)}
              className={`px-3 py-1.5 rounded-full text-xs font-semibold border transition-colors ${
                nonFaitesOnly ? 'bg-[#0C5C6C] border-[#0C5C6C] text-white' : 'border-gray-300 text-gray-600'
              }`}>
              Non faite
            </button>
          )}
        </div>
        {sterilList.length === 0 ? (
          <p className="text-sm text-gray-500">
            {nonFaitesOnly ? 'Toutes les stérilisations demandées sont faites et validées. 🎉' : 'Aucune condition de stérilisation sur vos cessions.'}
          </p>
        ) : (
          <div className="space-y-2">
            {sterilList.map(a => {
              const ech = parseDate(a.sterilisation_echeance);
              const validee = !!a.sterilisation_validee;
              const done = !!a.sterilise;
              const enRetard = !!ech && ech < today && !validee;
              const days = ech ? Math.round((ech.getTime() - today.getTime()) / 86400000) : null;
              const chip = validee
                ? { label: '✅ Validée', cls: 'bg-[#6E9E57]/15 text-[#4d7a3c]' }
                : done
                ? { label: '🟡 Déclarée · à valider', cls: 'bg-orange-100 text-orange-700' }
                : enRetard
                ? { label: `En retard de ${-(days ?? 0)} j`, cls: 'bg-red-100 text-red-700' }
                : { label: '⏳ À faire', cls: 'bg-gray-100 text-gray-600' };
              return (
                <div key={a.id} className="border border-gray-200 rounded-xl p-3">
                  <div className="flex items-center gap-3">
                    <Avatar a={a} />
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-semibold text-[#1F2A2E] truncate">{a.nom ?? 'Sans nom'}</p>
                      <p className="text-xs text-gray-500 truncate">
                        {[a.destinataire_nom, a.race].filter(Boolean).join(' · ')}
                      </p>
                    </div>
                    <span className={`px-2 py-1 rounded-full text-[10px] font-bold ${chip.cls}`}>{chip.label}</span>
                  </div>
                  <p className={`text-xs mt-2 ${enRetard ? 'text-red-700' : 'text-gray-600'}`}>
                    {ech
                      ? (enRetard
                        ? `Devait être fait avant le ${fmt(ech)}`
                        : validee ? `Échéance : ${fmt(ech)}` : `Avant le ${fmt(ech)}${days != null ? ` · dans ${days} j` : ''}`)
                      : 'Échéance non définie'}
                  </p>
                  {!validee && (
                    <div className="mt-2 flex gap-2">
                      <button onClick={() => valider(a)} disabled={busy === a.id}
                        className="flex-1 bg-[#6E9E57] hover:bg-[#5A8A45] text-white text-xs font-semibold py-2 rounded-lg transition-colors disabled:opacity-50">
                        {busy === a.id ? '…' : (done ? '✓ Valider' : '✓ Certificat reçu')}
                      </button>
                      <button onClick={() => openRelance(a)} disabled={busy === a.id}
                        className="flex-1 border border-[#0C5C6C] text-[#0C5C6C] text-xs font-semibold py-2 rounded-lg hover:bg-[#0C5C6C]/5 transition-colors disabled:opacity-50">
                        {busy === a.id ? '…' : '📣 Relancer la famille'}
                      </button>
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </section>

      {/* ── Anniversaires ── */}
      <section>
        <h3 className="text-base font-bold text-[#1F2A2E] mb-2" style={{ fontFamily: 'Galey, sans-serif' }}>🎂 Anniversaires</h3>
        {annivLoaded && (
          <label className="flex items-start gap-2 mb-3 p-2.5 rounded-xl bg-gray-50 border border-gray-200 cursor-pointer">
            <input type="checkbox" checked={annivAuto} onChange={e => toggleAnnivAuto(e.target.checked)}
              className="mt-0.5 accent-[#6E9E57] w-4 h-4" />
            <span>
              <span className="block text-sm font-semibold text-[#1F2A2E]">Message d&apos;anniversaire automatique</span>
              <span className="block text-[11px] text-gray-500">Envoie chaque année un message de vœux aux acquéreurs qui ont l&apos;appli.</span>
            </span>
          </label>
        )}
        {anniv.length === 0 ? (
          <p className="text-sm text-gray-500">Aucun anniversaire dans les 60 prochains jours.</p>
        ) : (
          <div className="space-y-2">
            {anniv.map(({ a, days, age }) => {
              const aujourdhui = days === 0;
              return (
                <div key={a.id} className={`border rounded-xl p-3 flex items-center gap-3 ${aujourdhui ? 'border-[#6E9E57]/40 bg-[#6E9E57]/5' : 'border-gray-200'}`}>
                  <Avatar a={a} />
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-semibold text-[#1F2A2E] truncate">{a.nom ?? 'Sans nom'}</p>
                    <p className={`text-xs ${aujourdhui ? 'text-[#4d7a3c] font-semibold' : 'text-gray-500'}`}>
                      {aujourdhui ? `🎉 Aujourd'hui · ${age} an${age > 1 ? 's' : ''}` : `Dans ${days} j · aura ${age} an${age > 1 ? 's' : ''}`}
                    </p>
                  </div>
                  {a.uid_acquereur && (
                    <button onClick={() => envoyerVoeux(a)} disabled={busy === a.id}
                      className="text-xs font-semibold text-[#0C5C6C] border border-[#0C5C6C]/30 px-3 py-1.5 rounded-lg hover:bg-[#0C5C6C]/5 transition-colors disabled:opacity-50">
                      {busy === a.id ? '…' : '🎂 Vœux'}
                    </button>
                  )}
                </div>
              );
            })}
          </div>
        )}
      </section>

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
                {(c.prenom || c.nom) && <p>👤 {[c.prenom, c.nom].filter(Boolean).join(' ')}</p>}
                {c.tel && <p>📞 <a href={`tel:${c.tel}`} className="text-[#0C5C6C] font-medium">{c.tel}</a></p>}
                {c.email && <p>✉️ {c.email}</p>}
                {c.adresse && <p>🏠 {c.adresse}</p>}
                {aucune && <p className="text-gray-500">Aucune coordonnée dans le contrat.</p>}
              </div>
              <textarea value={relanceMsg} onChange={e => setRelanceMsg(e.target.value)} rows={6}
                className="w-full border border-gray-300 rounded-xl p-3 text-sm resize-none focus:outline-none focus:border-[#0C5C6C]" />
              <p className="text-[11px] font-bold text-gray-400 tracking-wide mt-3 mb-2">ENVOYER VIA</p>
              <div className="flex flex-wrap gap-2">
                {a.uid_acquereur && (
                  <button onClick={() => relanceInApp(a, relanceMsg.trim())} disabled={busy === a.id}
                    className="px-3.5 py-2 rounded-xl text-xs font-bold text-[#0C5C6C] bg-[#0C5C6C]/10 border border-[#0C5C6C]/30 disabled:opacity-50">
                    🔔 Application
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
    </div>
  );
}

function Avatar({ a }: { a: AnimalLite }) {
  return a.photo_url
    ? <img src={a.photo_url} alt="" className="w-10 h-10 rounded-lg object-cover flex-shrink-0" />
    : <div className="w-10 h-10 rounded-lg bg-[#0C5C6C]/10 flex items-center justify-center flex-shrink-0">🐾</div>;
}
