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

function parseDate(s?: string | null): Date | null {
  if (!s) return null;
  const d = new Date(s);
  return isNaN(d.getTime()) ? null : d;
}

function fmt(d: Date) { return d.toLocaleDateString('fr-FR'); }

export default function SuiviCessionsTab({ animaux, uid, activeProfileId, onLocalUpdate }: Props) {
  const router = useRouter();
  const [nonFaitesOnly, setNonFaitesOnly] = useState(false);
  const [busy, setBusy] = useState<string | null>(null);
  const [annivAuto, setAnnivAuto] = useState(false);
  const [annivLoaded, setAnnivLoaded] = useState(false);

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
    setBusy(a.id);
    try {
      await supabase.from('animaux').update({ sterilisation_validee: true }).eq('id', a.id);
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
      onLocalUpdate(a.id, { sterilisation_validee: true });
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
      const sorted = [uid, a.uid_acquereur].sort().join('_');
      let convId: string;
      const { data: existing } = await supabase.from('conversations')
        .select('id').eq('participant_ids', sorted).or('type.eq.direct,type.is.null').maybeSingle();
      if (existing) {
        convId = existing.id;
      } else {
        const { data: me } = await supabase.from('user_profiles')
          .select('firstname, lastname, nom, avatar_url').eq('uid', uid).eq('is_main', true).maybeSingle();
        const { data: other } = await supabase.from('user_profiles')
          .select('firstname, lastname, nom, avatar_url').eq('uid', a.uid_acquereur).eq('is_main', true).maybeSingle();
        const myName = (me?.nom || `${me?.firstname ?? ''} ${me?.lastname ?? ''}`.trim()) || 'Élevage';
        const otherName = `${other?.firstname ?? ''} ${other?.lastname ?? ''}`.trim() || (other?.nom ?? 'Utilisateur');
        const participantsInfo: Record<string, unknown> = {
          [uid]: { name: myName, ...(me?.avatar_url ? { photo: me.avatar_url } : {}) },
          [a.uid_acquereur]: { name: otherName, ...(other?.avatar_url ? { photo: other.avatar_url } : {}) },
        };
        const { data: created } = await supabase.from('conversations').insert({
          type: 'direct',
          participants: [uid, a.uid_acquereur],
          participant_ids: sorted,
          participants_info: participantsInfo,
          last_message: '',
          unread_count: { [uid]: 0, [a.uid_acquereur]: 0 },
          updated_at: new Date().toISOString(),
          ...(activeProfileId ? { pro_profile_id: activeProfileId } : {}),
        }).select('id').single();
        convId = created!.id;
      }
      await supabase.from('messages').insert({
        conversation_id: convId,
        sender_id: uid,
        text: texte.trim(),
        msg_type: 'text',
        is_read: false,
      });
      const { data: conv } = await supabase.from('conversations')
        .select('participants, unread_count').eq('id', convId).maybeSingle();
      if (conv) {
        const members: string[] = (conv.participants ?? []).map((x: unknown) => String(x));
        const unread: Record<string, number> = { ...(conv.unread_count ?? {}) };
        for (const m of members) if (m !== uid) unread[m] = (unread[m] ?? 0) + 1;
        await supabase.from('conversations').update({
          last_message: texte.trim(),
          unread_count: unread,
          updated_at: new Date().toISOString(),
        }).eq('id', convId);
      }
      router.push(`/messages?conv=${convId}`);
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
                  {done && !validee && (
                    <button onClick={() => valider(a)} disabled={busy === a.id}
                      className="mt-2 w-full bg-[#6E9E57] hover:bg-[#5A8A45] text-white text-xs font-semibold py-2 rounded-lg transition-colors disabled:opacity-50">
                      {busy === a.id ? '…' : '✓ Valider la stérilisation'}
                    </button>
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
    </div>
  );
}

function Avatar({ a }: { a: AnimalLite }) {
  return a.photo_url
    ? <img src={a.photo_url} alt="" className="w-10 h-10 rounded-lg object-cover flex-shrink-0" />
    : <div className="w-10 h-10 rounded-lg bg-[#0C5C6C]/10 flex items-center justify-center flex-shrink-0">🐾</div>;
}
