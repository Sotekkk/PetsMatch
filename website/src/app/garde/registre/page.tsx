'use client';

import { useState, useEffect, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { useGardeAccess } from '@/hooks/useGardeAccess';
import { supabase } from '@/lib/supabase';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { PensionJournal } from '@/components/PensionJournal';
import { groupeGardeSejours, estGardeJournee, type GardeRdvRow, type GardeSejour } from '@/lib/garde-sejours';

const TEAL = '#0C5C6C';

interface Rdv extends GardeRdvRow {
  _client_email?: string;
  _client_tel?: string;
  _animal_espece?: string;
  _animal_race?: string;
  _animal_puce?: string;
}

function fmtDate(iso: string) {
  try {
    return new Date(iso).toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' });
  } catch { return iso; }
}
function fmtDateCourt(d: Date) {
  try { return d.toLocaleDateString('fr-FR', { day: 'numeric', month: 'short' }); } catch { return ''; }
}
function fmtDateFull(d: Date) {
  try { return d.toLocaleDateString('fr-FR'); } catch { return ''; }
}

const STATUT_LABEL: Record<GardeSejour['statut'], string> = {
  a_venir: 'À venir', en_garde: 'En garde', termine: 'Terminé',
};

export default function RegistreVisitesPage() {
  const { user, userData, isGarde, loading: authLoading } = useGardeAccess();
  const router = useRouter();
  const activeProfileId = useActiveProfile();

  const [tab, setTab] = useState<'a_venir' | 'passees' | 'registre'>('a_venir');
  const [registreFiltre, setRegistreFiltre] = useState<'a_venir' | 'en_garde' | 'termine' | 'tous'>('tous');
  const [visites, setVisites] = useState<Rdv[]>([]);
  const [loading, setLoading] = useState(true);
  const [journalFor, setJournalFor] = useState<Rdv | null>(null);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isGarde) { router.push('/'); return; }
  }, [user, userData, isGarde, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    setLoading(true);
    let q = supabase.from('rdv')
      .select('id, animal_id, client_uid, client_profile_id, date_heure, motif, statut, arrivee_validee_le, depart_valide_le')
      .eq('pro_uid', user.uid);
    if (activeProfileId) q = q.eq('pro_profile_id', activeProfileId) as typeof q;
    const { data } = await q.in('statut', ['confirme', 'termine']).order('date_heure', { ascending: true });
    const rows = (data ?? []) as Rdv[];

    // client_uid → client_profile_id (le profil qui a réservé — jamais
    // is_main, qui peut renvoyer un autre profil du même compte
    // multi-profils, ex. l'éleveur au lieu du particulier).
    const clientPids = [...new Set(rows.map(r => r.client_profile_id).filter((p): p is string => !!p))];
    const uidsNoPid = [...new Set(rows.filter(r => !r.client_profile_id).map(r => r.client_uid).filter((u): u is string => !!u))];
    const animalIds = [...new Set(rows.map(r => r.animal_id).filter((a): a is string => !!a))];

    const [{ data: byPid }, { data: byUid }, { data: animaux }] = await Promise.all([
      clientPids.length
        ? supabase.from('user_profiles').select('id, firstname, lastname, nom, email_contact, phone_number').in('id', clientPids)
        : Promise.resolve({ data: [] as { id: string; firstname: string | null; lastname: string | null; nom: string | null; email_contact: string | null; phone_number: string | null }[] }),
      uidsNoPid.length
        ? supabase.from('user_profiles').select('uid, firstname, lastname, nom, email_contact, phone_number').in('uid', uidsNoPid).eq('is_main', true)
        : Promise.resolve({ data: [] as { uid: string; firstname: string | null; lastname: string | null; nom: string | null; email_contact: string | null; phone_number: string | null }[] }),
      animalIds.length
        ? supabase.from('animaux').select('id, nom, espece, race, puce').in('id', animalIds)
        : Promise.resolve({ data: [] as { id: string; nom: string | null; espece: string | null; race: string | null; puce: string | null }[] }),
    ]);

    const nomOf = (c: { nom: string | null; firstname: string | null; lastname: string | null }) =>
      c.nom?.trim() || `${c.firstname ?? ''} ${c.lastname ?? ''}`.trim() || 'Client';
    const nameByPid = new Map((byPid ?? []).map(c => [c.id, nomOf(c)]));
    const emailByPid = new Map((byPid ?? []).map(c => [c.id, c.email_contact ?? '']));
    const telByPid = new Map((byPid ?? []).map(c => [c.id, c.phone_number ?? '']));
    const nameByUid = new Map((byUid ?? []).map(c => [c.uid, nomOf(c)]));
    const emailByUid = new Map((byUid ?? []).map(c => [c.uid, c.email_contact ?? '']));
    const telByUid = new Map((byUid ?? []).map(c => [c.uid, c.phone_number ?? '']));
    const animalById = new Map((animaux ?? []).map(a => [a.id, a]));

    const rowsEnriched = rows.map(r => {
      const pid = r.client_profile_id ?? null;
      const a = r.animal_id ? animalById.get(r.animal_id) : undefined;
      return {
        ...r,
        _client_nom: (pid && nameByPid.get(pid)) || nameByUid.get(r.client_uid ?? '') || 'Client',
        _client_email: (pid && emailByPid.get(pid)) || emailByUid.get(r.client_uid ?? '') || '',
        _client_tel: (pid && telByPid.get(pid)) || telByUid.get(r.client_uid ?? '') || '',
        _animal_nom: a?.nom ?? '',
        _animal_espece: a?.espece ?? '',
        _animal_race: a?.race ?? '',
        _animal_puce: a?.puce ?? '',
      };
    });

    setVisites(rowsEnriched);
    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  async function marquerTermine(rdv: Rdv) {
    await supabase.from('rdv').update({ statut: 'termine' }).eq('id', rdv.id);
    load();
  }

  // Registre légal garde à domicile — l'animal est arrivé/reparti (posé sur
  // le 1er/dernier jour du séjour). Voir supabase/migration_garde_presence.sql.
  async function validerArrivee(sejour: GardeSejour) {
    await supabase.from('rdv').update({ arrivee_validee_le: new Date().toISOString() }).eq('id', sejour.jours[0].id);
    load();
  }
  async function validerDepart(sejour: GardeSejour) {
    await supabase.from('rdv').update({ depart_valide_le: new Date().toISOString() }).eq('id', sejour.jours[sejour.jours.length - 1].id);
    load();
  }

  function registreRows(sejours: GardeSejour[]) {
    return sejours.map(s => {
      const j = s.jours[0] as Rdv;
      return [
        s.animalNom,
        j._animal_espece || '—',
        j._animal_race || '—',
        j._animal_puce || '—',
        s.clientNom,
        j._client_tel || '—',
        j._client_email || '—',
        fmtDateFull(s.dateEntree),
        fmtDateFull(s.dateSortiePrevue),
        s.departValideLe ? fmtDateFull(s.departValideLe) : '—',
        STATUT_LABEL[s.statut],
      ];
    });
  }

  function exportCsv(sejours: GardeSejour[]) {
    if (!sejours.length) return;
    const header = ['Nom', 'Espèce', 'Race', 'Puce', 'Client', 'Téléphone', 'Email', 'Date entrée', 'Sortie prévue', 'Sortie effective', 'Statut'];
    const rows = registreRows(sejours);
    const csv = [header, ...rows]
      .map(row => row.map(v => String(v ?? '').replace(/;/g, ',')).join(';'))
      .join('\n');
    const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `registre-garde-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  async function exportPdf(sejours: GardeSejour[]) {
    if (!sejours.length) return;
    const { jsPDF } = await import('jspdf');
    const autoTable = (await import('jspdf-autotable')).default;
    const doc = new jsPDF({ unit: 'pt', format: 'a4', orientation: 'landscape' });
    doc.setFont('helvetica', 'bold');
    doc.setFontSize(13);
    doc.text('REGISTRE GARDE À DOMICILE — ENTRÉES & SORTIES', 40, 40);
    doc.setFont('helvetica', 'normal');
    doc.setFontSize(8);
    doc.setTextColor(110);
    doc.text(`Édité le ${new Date().toLocaleDateString('fr-FR')}`, 40, 54);
    autoTable(doc, {
      startY: 66,
      margin: { left: 40, right: 40 },
      head: [['Nom', 'Espèce', 'Race', 'Puce', 'Client', 'Téléphone', 'Email', 'Date entrée', 'Sortie prévue', 'Sortie effective', 'Statut']],
      body: registreRows(sejours),
      headStyles: { fillColor: [12, 92, 108], fontSize: 8 },
      bodyStyles: { fontSize: 8 },
    });
    doc.save(`registre-garde-${new Date().toISOString().slice(0, 10)}.pdf`);
  }

  if (authLoading || loading) {
    return <div className="flex justify-center py-32"><div className="w-8 h-8 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;
  }

  const now = new Date();
  const tousSejours = groupeGardeSejours(visites);
  const sejoursActifs = tousSejours.filter(s => s.statut !== 'termine');
  const sejoursTermines = [...tousSejours.filter(s => s.statut === 'termine')].sort((a, b) => b.dateSortiePrevue.getTime() - a.dateSortiePrevue.getTime());

  const visitesSimples = visites.filter(r => !estGardeJournee(r));
  const aVenirSimples = visitesSimples.filter(r => r.statut !== 'termine' && new Date(r.date_heure) >= now);
  const passeesSimples = visitesSimples.filter(r => !aVenirSimples.includes(r)).slice().reverse();

  type Item = GardeSejour | Rdv;
  const isSejour = (it: Item): it is GardeSejour => 'jours' in it;

  const aVenirItems: Item[] = [...sejoursActifs, ...aVenirSimples]
    .sort((a, b) => (isSejour(a) ? a.dateEntree.getTime() : new Date(a.date_heure).getTime())
      - (isSejour(b) ? b.dateEntree.getTime() : new Date(b.date_heure).getTime()));
  const passeesItems: Item[] = [...sejoursTermines, ...passeesSimples]
    .sort((a, b) => (isSejour(b) ? b.dateSortiePrevue.getTime() : new Date(b.date_heure).getTime())
      - (isSejour(a) ? a.dateSortiePrevue.getTime() : new Date(a.date_heure).getTime()));

  const displayed = tab === 'passees' ? passeesItems : aVenirItems;

  const registreFiltered = registreFiltre === 'tous' ? tousSejours : tousSejours.filter(s => s.statut === registreFiltre);
  const registreSorted = [...registreFiltered].sort((a, b) => b.dateEntree.getTime() - a.dateEntree.getTime());

  return (
    <div className="max-w-3xl mx-auto px-4 py-8">
      <h1 className="text-2xl font-bold font-galey mb-6" style={{ color: TEAL }}>Registre visites</h1>

      <div className="flex bg-gray-100 rounded-xl p-1 mb-6 max-w-lg overflow-x-auto">
        {([
          ['a_venir', `À venir (${aVenirItems.length})`],
          ['passees', `Passées (${passeesItems.length})`],
          ['registre', `Registre (${tousSejours.length})`],
        ] as const).map(([t, label]) => (
          <button key={t} onClick={() => setTab(t)}
            className={`flex-1 py-2 px-2 rounded-lg text-sm font-medium font-galey transition-colors whitespace-nowrap ${tab === t ? 'bg-white shadow-sm text-[#1F2A2E]' : 'text-gray-500'}`}>
            {label}
          </button>
        ))}
      </div>

      {tab === 'registre' ? (
        <div>
          <div className="flex flex-wrap gap-2 mb-4">
            {([
              ['a_venir', 'À venir'], ['en_garde', 'En garde'], ['termine', 'Terminés'], ['tous', 'Tous'],
            ] as const).map(([f, label]) => (
              <button key={f} onClick={() => setRegistreFiltre(f)}
                className={`px-3 py-1.5 rounded-full text-xs font-medium font-galey border ${registreFiltre === f ? 'text-white' : 'text-gray-600 border-gray-200'}`}
                style={registreFiltre === f ? { backgroundColor: TEAL, borderColor: TEAL } : {}}>
                {label}
              </button>
            ))}
          </div>
          <div className="flex gap-2 mb-4">
            <button onClick={() => exportCsv(registreSorted)} disabled={!registreSorted.length}
              className="flex-1 text-sm font-medium font-galey border rounded-xl py-2 disabled:opacity-40"
              style={{ color: TEAL, borderColor: TEAL }}>
              📄 CSV
            </button>
            <button onClick={() => exportPdf(registreSorted)} disabled={!registreSorted.length}
              className="flex-1 text-sm font-medium font-galey border rounded-xl py-2 disabled:opacity-40"
              style={{ color: TEAL, borderColor: TEAL }}>
              📕 PDF
            </button>
          </div>
          {registreSorted.length === 0 ? (
            <p className="text-center text-gray-400 font-galey py-16">Aucun séjour de garde à domicile</p>
          ) : (
            <div className="space-y-3">
              {registreSorted.map(s => (
                <SejourRegistreCard key={`${s.animalId}-${s.dateEntree.toISOString()}`} sejour={s}
                  onValiderArrivee={() => validerArrivee(s)} onValiderDepart={() => validerDepart(s)} />
              ))}
            </div>
          )}
        </div>
      ) : displayed.length === 0 ? (
        <p className="text-center text-gray-400 font-galey py-16">
          {tab === 'a_venir' ? 'Aucune visite à venir' : 'Aucune visite passée'}
        </p>
      ) : (
        <div className="space-y-3">
          {displayed.map(item => isSejour(item) ? (
            <SejourTourneeCard key={`${item.animalId}-${item.dateEntree.toISOString()}`} sejour={item}
              onValiderArrivee={() => validerArrivee(item)} onValiderDepart={() => validerDepart(item)} />
          ) : (
            <VisiteCard key={item.id} rdv={item} onTerminer={() => marquerTermine(item)} onRapport={() => setJournalFor(item)} />
          ))}
        </div>
      )}

      {journalFor && (
        <PensionJournal
          animalId={journalFor.animal_id}
          animalNom={journalFor._animal_nom || 'Animal'}
          proUid={user?.uid}
          onClose={() => setJournalFor(null)}
        />
      )}
    </div>
  );
}

function VisiteCard({ rdv, onTerminer, onRapport }: { rdv: Rdv; onTerminer: () => void; onRapport: () => void }) {
  const isTermine = rdv.statut === 'termine';
  return (
    <div className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
      <div className="flex items-start justify-between mb-3">
        <div>
          <p className="font-bold font-galey text-sm text-[#1F2A2E]">{rdv._animal_nom} — {rdv._client_nom}</p>
          <p className="text-xs text-gray-400 font-galey">🚶 Visite / promenade · animal chez son propriétaire</p>
          <p className="text-xs text-gray-400 font-galey">{fmtDate(rdv.date_heure)}</p>
        </div>
        <span className={`text-xs font-semibold font-galey px-2 py-1 rounded-full ${isTermine ? 'bg-[#EEF5EA] text-[#6E9E57]' : 'bg-[#E8F4F6] text-[#0C5C6C]'}`}>
          {isTermine ? 'Terminée' : 'Confirmée'}
        </span>
      </div>
      <div className="flex gap-2">
        {!isTermine && (
          <button onClick={onTerminer}
            className="flex-1 text-xs font-medium font-galey border border-gray-200 rounded-xl py-2 hover:bg-gray-50">
            Marquer terminée
          </button>
        )}
        <button onClick={onRapport}
          className="flex-1 text-xs font-medium font-galey text-white rounded-xl py-2"
          style={{ backgroundColor: TEAL }}>
          Rapport de visite
        </button>
      </div>
    </div>
  );
}

function SejourTourneeCard({ sejour, onValiderArrivee, onValiderDepart }: {
  sejour: GardeSejour; onValiderArrivee: () => void; onValiderDepart: () => void;
}) {
  const unSeulJour = sejour.jours.length === 1;
  const periode = unSeulJour ? `le ${fmtDateCourt(sejour.dateEntree)}` : `du ${fmtDateCourt(sejour.dateEntree)} au ${fmtDateCourt(sejour.dateSortiePrevue)}`;
  return (
    <div className="rounded-2xl border-2 bg-white p-4 shadow-sm" style={{ borderColor: TEAL }}>
      <div className="flex items-start justify-between mb-3">
        <div>
          <p className="font-bold font-galey text-sm text-[#1F2A2E]">🏠 Garde à domicile — {sejour.animalNom} — {sejour.clientNom}</p>
          <p className="text-xs text-gray-400 font-galey">Chez vous {periode}</p>
        </div>
        <span className={`text-xs font-semibold font-galey px-2 py-1 rounded-full whitespace-nowrap ${sejour.statut === 'en_garde' ? 'bg-[#EEF5EA] text-[#6E9E57]' : 'bg-[#FFF8E1] text-[#CA8A04]'}`}>
          {sejour.statut === 'en_garde' ? 'En cours' : 'À venir'}
        </span>
      </div>
      {sejour.statut === 'a_venir' ? (
        <button onClick={onValiderArrivee}
          className="w-full text-xs font-medium font-galey text-white rounded-xl py-2"
          style={{ backgroundColor: TEAL }}>
          🏠 Valider l&apos;arrivée
        </button>
      ) : (
        <>
          <p className="text-xs font-galey text-[#6E9E57] font-semibold mb-2">
            ✅ Arrivé le {sejour.arriveeValideeLe ? fmtDateCourt(sejour.arriveeValideeLe) : ''}
          </p>
          <button onClick={onValiderDepart}
            className="w-full text-xs font-medium font-galey border rounded-xl py-2"
            style={{ color: TEAL, borderColor: TEAL }}>
            🚪 Valider le départ
          </button>
        </>
      )}
    </div>
  );
}

function SejourRegistreCard({ sejour, onValiderArrivee, onValiderDepart }: {
  sejour: GardeSejour; onValiderArrivee: () => void; onValiderDepart: () => void;
}) {
  const j = sejour.jours[0] as Rdv;
  const label = STATUT_LABEL[sejour.statut];
  const cls = sejour.statut === 'termine' ? 'bg-[#EEF5EA] text-[#6E9E57]'
    : sejour.statut === 'en_garde' ? 'bg-[#E8F4F6] text-[#0C5C6C]' : 'bg-[#FFF8E1] text-[#CA8A04]';
  const details = [j._animal_espece, j._animal_race, j._animal_puce ? `Puce ${j._animal_puce}` : ''].filter(Boolean).join(' · ');
  const contact = [sejour.clientNom, j._client_tel, j._client_email].filter(Boolean).join(' · ');
  return (
    <div className="rounded-2xl border border-gray-100 bg-white p-4 shadow-sm">
      <div className="flex items-start justify-between mb-1">
        <p className="font-bold font-galey text-sm text-[#1F2A2E]">{sejour.animalNom}</p>
        <span className={`text-xs font-semibold font-galey px-2 py-1 rounded-full whitespace-nowrap ${cls}`}>{label}</span>
      </div>
      {details && <p className="text-xs text-gray-400 font-galey mb-1">{details}</p>}
      <p className="text-xs text-gray-500 font-galey mb-2">👤 {contact}</p>
      <p className="text-xs font-galey font-semibold text-[#1F2A2E] mb-2">
        Entrée le {fmtDateFull(sejour.dateEntree)}
        {sejour.departValideLe ? ` · Sortie le ${fmtDateFull(sejour.departValideLe)}` : ` · Sortie prévue le ${fmtDateFull(sejour.dateSortiePrevue)}`}
      </p>
      {sejour.statut !== 'termine' && (
        sejour.statut === 'a_venir' ? (
          <button onClick={onValiderArrivee}
            className="w-full text-xs font-medium font-galey border rounded-xl py-2" style={{ color: TEAL, borderColor: TEAL }}>
            Valider l&apos;arrivée
          </button>
        ) : (
          <button onClick={onValiderDepart}
            className="w-full text-xs font-medium font-galey border rounded-xl py-2" style={{ color: TEAL, borderColor: TEAL }}>
            Valider le départ
          </button>
        )
      )}
    </div>
  );
}
