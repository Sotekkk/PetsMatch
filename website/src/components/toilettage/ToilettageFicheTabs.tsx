'use client';
// Fiche toilettage d'un animal (site) — onglets Synthèse · Prestations ·
// Consignes · Historique, sous l'en-tête commun de mes-patients/[id].
// Données : rdv, prestations_toilettage, fiches_toilettage (consignes
// permanentes du salon), seances_toilettage (fiche technique par prestation),
// fiches_toilettage_photos ; allergies / traitements déclarés par le
// propriétaire (lecture seule). Miroir appli : toilettage_fiche_client_page.dart.
// Scopé au profil toiletteur actif (pro_profile_id).
import { useCallback, useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { etapeToilettage, STYLE_ETAPE, labelTravail, labelCooperation, labelTolerance, TOLERANCE_SECHOIR } from '@/lib/toilettage';
import SeanceToilettageModal, { type RdvSeance, type SeanceToilettage } from './SeanceToilettageModal';

const TEAL = '#0C5C6C';
const ROUGE = '#B3261E';
const AMBRE = '#D97706';

interface Rdv extends RdvSeance {
  statut: string; motif: string | null; prestation_id: string | null; notes_client: string | null;
  arrivee_validee_le?: string | null;
}
interface Photo { id: string; type: string; url: string; rdv_id: string | null }
type Fiche = Record<string, string | null> & { id: string };

const CHAMPS: [string, string][] = [
  ['type_poil', 'Type de poil'],
  ['particularites_pelage', 'Particularités du pelage'],
  ['coupe_habituelle', 'Coupe habituelle'],
  ['longueur_coupe', 'Longueur souhaitée'],
  ['shampooing_prefere', 'Shampooing habituel'],
  ['produits_a_eviter', 'Produits à éviter'],
  ['zones_sensibles', 'Zones sensibles'],
  ['comportement_manipulation', 'Comportement pendant la manipulation'],
  ['demandes_specifiques', 'Demandes spécifiques du propriétaire'],
  ['notes', 'Notes internes'],
];

function Carte({ titre, action, children }: { titre: string; action?: React.ReactNode; children: React.ReactNode }) {
  return (
    <div className="bg-white rounded-2xl border border-gray-100 shadow-sm p-5">
      <div className="flex items-center justify-between mb-3">
        <h3 className="font-bold text-sm text-[#1F2A2E]">{titre}</h3>
        {action}
      </div>
      {children}
    </div>
  );
}
const discret = (t: string) => <p className="text-sm text-gray-400">{t}</p>;
const jour = (iso: string) => new Date(iso).toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short', year: 'numeric' });
const hm = (iso: string) => new Date(iso).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' });

export default function ToilettageFicheTabs({ tab, setTab, animalId, animalNom, proUid, profileId, allergies, traitements }: {
  tab: string; setTab: (t: string) => void; animalId: string; animalNom: string; proUid: string; profileId: string;
  allergies: { id: string; description: string }[];
  traitements: { id: string; nom: string; posologie: string | null; date_fin: string | null }[];
}) {
  const [loading, setLoading] = useState(true);
  const [fiche, setFiche] = useState<Fiche | null>(null);
  const [rdvs, setRdvs] = useState<Rdv[]>([]);
  const [seances, setSeances] = useState<SeanceToilettage[]>([]);
  const [photos, setPhotos] = useState<Photo[]>([]);
  const [prestations, setPrestations] = useState<Record<string, string>>({});
  const [employes, setEmployes] = useState<Record<string, string>>({});
  const [form, setForm] = useState<Record<string, string>>({});
  const [saving, setSaving] = useState(false);
  const [now, setNow] = useState(0);
  const [modal, setModal] = useState<{ rdv: Rdv | null; seance: SeanceToilettage | null } | null>(null);

  const charger = useCallback(async () => {
    const [f, r, s, e] = await Promise.all([
      supabase.from('fiches_toilettage').select('*').eq('pro_profile_id', profileId).eq('animal_id', animalId).maybeSingle(),
      supabase.from('rdv').select('*').eq('pro_profile_id', profileId).eq('animal_id', animalId)
        .in('statut', ['demande', 'contre_proposition', 'confirme', 'termine', 'absent']).order('date_heure', { ascending: false }).limit(150),
      supabase.from('seances_toilettage').select('*').eq('pro_profile_id', profileId).eq('animal_id', animalId).order('date_seance', { ascending: false }),
      supabase.from('employes').select('id, prenom, nom').eq('eleveur_profile_id', profileId),
    ]);
    const fi = f.data as Fiche | null;
    const liste = (r.data ?? []) as Rdv[];
    const prIds = [...new Set(liste.map(x => x.prestation_id).filter(Boolean) as string[])];
    const [pr, ph] = await Promise.all([
      prIds.length ? supabase.from('prestations_toilettage').select('id, nom').in('id', prIds) : Promise.resolve({ data: [] }),
      fi ? supabase.from('fiches_toilettage_photos').select('id, type, url, rdv_id').eq('fiche_id', fi.id).order('created_at') : Promise.resolve({ data: [] }),
    ]);
    setFiche(fi); setRdvs(liste); setSeances(s.error ? [] : (s.data ?? []) as SeanceToilettage[]);
    setPhotos((ph.data ?? []) as Photo[]);
    setPrestations(Object.fromEntries(((pr.data ?? []) as { id: string; nom: string }[]).map(x => [x.id, x.nom])));
    setEmployes(Object.fromEntries(((e.data ?? []) as { id: string; prenom: string | null; nom: string | null }[]).map(x => [x.id, `${x.prenom ?? ''} ${x.nom ?? ''}`.trim()])));
    setForm(Object.fromEntries([...CHAMPS.map(([k]) => [k, fi?.[k] ?? '']), ['tolerance_sechoir', fi?.tolerance_sechoir ?? '']]));
    setNow(Date.now()); setLoading(false);
  }, [animalId, profileId]);
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    charger();
  }, [charger]);

  if (loading) return <div className="flex justify-center py-16"><div className="w-7 h-7 border-2 border-[#0C5C6C] border-t-transparent rounded-full animate-spin" /></div>;

  const debut = (r: Rdv) => new Date(r.date_heure).getTime();
  const prestation = (r: Rdv) => (r.prestation_id && prestations[r.prestation_id]) || r.motif?.trim() || 'Prestation';
  const seanceDe = (r: Rdv) => seances.find(s => s.rdv_id === r.id) ?? null;
  const aVenir = rdvs.filter(r => ['demande', 'contre_proposition', 'confirme'].includes(r.statut)
    && debut(r) + (r.duree_minutes ?? 60) * 60000 > now && etapeToilettage(r) !== 'pret').sort((a, b) => debut(a) - debut(b));
  const passees = rdvs.filter(r => !aVenir.includes(r));
  const terminees = rdvs.filter(r => r.statut === 'termine');
  const f = (k: string) => fiche?.[k]?.trim() || null;
  const traitsEnCours = traitements.filter(t => !t.date_fin || new Date(t.date_fin).getTime() >= now);
  const ouvrir = (rdv: Rdv | null, seance: SeanceToilettage | null) => setModal({ rdv, seance });

  const modale = modal && (
    <SeanceToilettageModal animalId={animalId} animalNom={animalNom} proUid={proUid} profileId={profileId}
      rdv={modal.rdv} seance={modal.seance} prestation={modal.rdv ? prestation(modal.rdv) : undefined}
      onClose={() => setModal(null)} onSaved={charger} />
  );

  if (tab === 'Synthèse') {
    const p = aVenir[0];
    const derniere = terminees[0];
    const ds = (derniere && seanceDe(derniere)) ?? seances[0] ?? null;
    const apres = ds ? photos.filter(x => x.type === 'apres' && x.rdv_id === ds.rdv_id).at(-1) : undefined;
    const tol = fiche?.tolerance_sechoir;
    const alertes: [string, string][] = [
      ...allergies.map(a => [`Allergie déclarée : ${a.description}`, ROUGE] as [string, string]),
      ...traitsEnCours.map(t => [`Traitement en cours : ${t.nom}`, AMBRE] as [string, string]),
      ...(f('produits_a_eviter') ? [[`Produits à éviter : ${f('produits_a_eviter')}`, ROUGE] as [string, string]] : []),
      ...(f('zones_sensibles') ? [[`Zones sensibles : ${f('zones_sensibles')}`, AMBRE] as [string, string]] : []),
      ...(f('comportement_manipulation') ? [[`Comportement : ${f('comportement_manipulation')}`, AMBRE] as [string, string]] : []),
      ...(tol && tol !== 'bonne' ? [[`Séchoir : ${labelTolerance(tol)}`, AMBRE] as [string, string]] : []),
    ];
    const dates = terminees.map(debut).sort((a, b) => a - b);
    const joursMoy = dates.length >= 2 ? (dates[dates.length - 1] - dates[0]) / 86400000 / (dates.length - 1) : 0;
    return (
      <>
        <div className="grid sm:grid-cols-2 gap-4">
          <Carte titre="Prochain rendez-vous">
            {p ? (
              <div className="text-sm space-y-0.5">
                <p className="font-bold">{prestation(p)}</p>
                <p>{jour(p.date_heure)} à {hm(p.date_heure)} · {p.duree_minutes ?? 60} min</p>
                {p.employe_id && employes[p.employe_id] && <p className="text-gray-600">Toiletteur : {employes[p.employe_id]}</p>}
                {p.notes_client?.trim() && <p style={{ color: AMBRE }}>Demande du client : {p.notes_client.trim()}</p>}
              </div>
            ) : discret('Aucun rendez-vous à venir.')}
          </Carte>
          <Carte titre="Alertes importantes">
            {alertes.length === 0 ? discret('Aucune alerte renseignée.') : (
              <div className="text-sm space-y-1">{alertes.map(([t, c]) => <p key={t} style={{ color: c }}>{t}</p>)}</div>
            )}
          </Carte>
          <Carte titre="Coupe habituelle" action={<button onClick={() => setTab('Consignes')} className="text-xs font-semibold" style={{ color: TEAL }}>Modifier</button>}>
            <div className="text-sm space-y-0.5">
              {!f('coupe_habituelle') && !f('longueur_coupe') && !f('type_poil') && discret('Non renseignée — à compléter dans Consignes.')}
              {f('type_poil') && <p>Poil : {f('type_poil')}</p>}
              {f('coupe_habituelle') && <p>{f('coupe_habituelle')}</p>}
              {f('longueur_coupe') && <p>Longueur : {f('longueur_coupe')}</p>}
              {f('shampooing_prefere') && <p>Shampooing : {f('shampooing_prefere')}</p>}
            </div>
          </Carte>
          <Carte titre="Dernière prestation">
            {!derniere && !ds ? discret('Aucune prestation terminée.') : (
              <div className="flex gap-3">
                <div className="flex-1 text-sm space-y-0.5">
                  {derniere && <p className="font-bold">{prestation(derniere)} — {jour(derniere.date_heure)}</p>}
                  {ds && (ds.travaux ?? []).length > 0 && <p>{(ds.travaux ?? []).map(labelTravail).join(', ')}</p>}
                  {ds?.cooperation && <p>Comportement : {labelCooperation(ds.cooperation)}</p>}
                  {ds?.precautions && <p style={{ color: AMBRE }}>Précautions : {ds.precautions}</p>}
                  {derniere && !ds && <button onClick={() => ouvrir(derniere, null)} className="text-xs font-semibold" style={{ color: TEAL }}>Remplir la fiche technique</button>}
                </div>
                {/* eslint-disable-next-line @next/next/no-img-element */}
                {apres && <img src={apres.url} alt="" className="w-20 h-20 rounded-lg object-cover" />}
              </div>
            )}
          </Carte>
          <Carte titre="Fréquence">
            <div className="text-sm space-y-0.5">
              <p>{terminees.length} prestation{terminees.length > 1 ? 's' : ''} terminée{terminees.length > 1 ? 's' : ''}</p>
              {joursMoy >= 10 && <p>Rythme : environ toutes les {Math.round(joursMoy / 7)} semaines</p>}
              {derniere && <p>Dernière visite : {jour(derniere.date_heure)}</p>}
            </div>
          </Carte>
        </div>
        <div className="flex flex-wrap gap-2">
          {(['Identité', 'Santé'] as const).map(t => (
            <button key={t} onClick={() => setTab(t)} className="px-4 py-2 rounded-xl border text-sm font-semibold" style={{ borderColor: TEAL, color: TEAL }}>
              {t === 'Santé' ? 'Carnet de santé (lecture)' : t}
            </button>
          ))}
        </div>
        {modale}
      </>
    );
  }

  if (tab === 'Prestations') {
    const ligne = (r: Rdv) => {
      const st = STYLE_ETAPE[etapeToilettage(r)];
      const s = seanceDe(r);
      const passee = !aVenir.includes(r);
      return (
        <div key={r.id} className="py-2.5 border-t border-gray-50 first:border-0">
          <div className="flex items-center gap-2">
            <p className="flex-1 text-sm font-bold text-[#1F2A2E]">{prestation(r)}</p>
            <span className="text-[11px] font-bold px-2 py-0.5 rounded-full" style={{ color: st.fg, background: st.bg }}>{st.label}</span>
          </div>
          <p className="text-xs text-gray-600">{jour(r.date_heure)} à {hm(r.date_heure)} · {r.duree_minutes ?? 60} min{r.employe_id && employes[r.employe_id] ? ` · ${employes[r.employe_id]}` : ''}</p>
          {r.notes_client?.trim() && <p className="text-xs" style={{ color: AMBRE }}>Demande : {r.notes_client.trim()}</p>}
          {passee && r.statut !== 'absent' && (
            <button onClick={() => ouvrir(r, s)} className="text-xs font-semibold mt-1" style={{ color: TEAL }}>
              {s ? `Fiche technique${s.partage_proprietaire ? ' · compte rendu partagé' : ''}` : 'Remplir la fiche technique'}
            </button>
          )}
        </div>
      );
    };
    return (
      <>
        <Carte titre={`À venir (${aVenir.length})`}>{aVenir.length === 0 ? discret('Aucun rendez-vous à venir.') : aVenir.map(ligne)}</Carte>
        <Carte titre={`Passées (${passees.length})`}>{passees.length === 0 ? discret('Aucune prestation passée.') : passees.slice(0, 40).map(ligne)}</Carte>
        {modale}
      </>
    );
  }

  if (tab === 'Consignes') {
    const demande = rdvs.find(r => r.notes_client?.trim());
    async function enregistrer() {
      setSaving(true);
      const data = {
        ...Object.fromEntries(CHAMPS.map(([k]) => [k, form[k]?.trim() || null])),
        tolerance_sechoir: form.tolerance_sechoir || null, updated_at: new Date().toISOString(),
      };
      const r0 = rdvs[0];
      const { error } = fiche
        ? await supabase.from('fiches_toilettage').update(data).eq('id', fiche.id)
        : await supabase.from('fiches_toilettage').insert({
            ...data, pro_uid: proUid, pro_profile_id: profileId, animal_id: animalId,
            ...(r0?.client_uid ? { client_uid: r0.client_uid } : {}), ...(r0?.client_profile_id ? { client_profile_id: r0.client_profile_id } : {}),
          });
      setSaving(false);
      if (error) { alert(error.message.includes('column') ? 'Migration migration_toilettage_fiche.sql à passer.' : error.message); return; }
      charger();
    }
    const input = (k: string, l: string) => (
      <label key={k} className="block">
        <span className="text-xs font-semibold text-gray-600">{l}</span>
        <textarea value={form[k] ?? ''} onChange={e => setForm(x => ({ ...x, [k]: e.target.value }))} rows={k === 'notes' || k === 'demandes_specifiques' ? 3 : 1}
          className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm resize-y" />
      </label>
    );
    return (
      <>
        <Carte titre="Déclaré par le propriétaire">
          <div className="text-sm space-y-1">
            {allergies.length === 0 && traitsEnCours.length === 0 && !demande && discret('Rien de déclaré dans le carnet du propriétaire.')}
            {allergies.map(a => <p key={a.id} style={{ color: ROUGE }}>Allergie : {a.description}</p>)}
            {traitsEnCours.map(t => <p key={t.id}>Traitement : {t.nom}{t.posologie ? ` — ${t.posologie}` : ''}</p>)}
            {demande && <p>Dernière demande à la réservation : {demande.notes_client?.trim()}</p>}
            <p className="text-xs text-gray-400 pt-1">Lecture seule : ces informations viennent du carnet de santé et des réservations.</p>
          </div>
        </Carte>
        <Carte titre="Observations du salon">
          <div className="grid sm:grid-cols-2 gap-3">
            {CHAMPS.slice(0, 8).map(([k, l]) => input(k, l))}
            <label className="block">
              <span className="text-xs font-semibold text-gray-600">Tolérance au séchoir</span>
              <select value={form.tolerance_sechoir ?? ''} onChange={e => setForm(x => ({ ...x, tolerance_sechoir: e.target.value }))}
                className="mt-1 w-full border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white">
                <option value="">Non renseignée</option>
                {TOLERANCE_SECHOIR.map(([k, l]) => <option key={k} value={k}>{l}</option>)}
              </select>
            </label>
          </div>
          <div className="space-y-3 mt-3">{CHAMPS.slice(8).map(([k, l]) => input(k, l))}</div>
          <button onClick={enregistrer} disabled={saving} className="mt-4 w-full sm:w-auto px-6 py-2.5 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: TEAL }}>
            {saving ? 'Enregistrement…' : 'Enregistrer les consignes'}
          </button>
          <p className="text-xs text-gray-400 mt-2">Consignes permanentes du salon : reprises à chaque rendez-vous, jamais visibles du propriétaire.</p>
        </Carte>
      </>
    );
  }

  // Historique : une entrée par fiche technique, avec ses photos.
  return (
    <>
      <Carte titre={`Fiches techniques (${seances.length})`}>
        {seances.length === 0 ? discret("Aucune fiche technique pour l'instant. Remplissez-la depuis l'onglet Prestations après chaque toilettage.") : (
          <div className="space-y-3">
            {seances.map(s => {
              const r = rdvs.find(x => x.id === s.rdv_id) ?? null;
              const ph = photos.filter(p => s.rdv_id && p.rdv_id === s.rdv_id);
              return (
                <button key={s.id} onClick={() => ouvrir(r, s)} className="w-full text-left border border-gray-100 rounded-xl p-3 hover:bg-gray-50">
                  <div className="flex items-center gap-2">
                    <p className="flex-1 text-sm font-bold text-[#1F2A2E]">
                      {new Date(s.date_seance).toLocaleDateString('fr-FR', { day: 'numeric', month: 'long', year: 'numeric' })}{r ? ` — ${prestation(r)}` : ''}
                    </p>
                    {s.partage_proprietaire && <span className="text-[11px] font-bold px-2 py-0.5 rounded-full" style={{ color: TEAL, background: '#E6F2F3' }}>Partagé</span>}
                  </div>
                  <div className="text-sm space-y-0.5 mt-1">
                    {s.employe_id && employes[s.employe_id] && <p className="text-xs text-gray-500">Toiletteur : {employes[s.employe_id]}</p>}
                    {(s.travaux ?? []).length > 0 && <p>{(s.travaux ?? []).map(labelTravail).join(', ')}</p>}
                    {s.longueur_coupe && <p>Longueur : {s.longueur_coupe}</p>}
                    {s.produits && <p>Produits : {s.produits}</p>}
                    {s.cooperation && <p>Comportement : {labelCooperation(s.cooperation)}</p>}
                    {s.precautions && <p style={{ color: AMBRE }}>Précautions : {s.precautions}</p>}
                    {s.observations && <p>Observations : {s.observations}</p>}
                    {s.compte_rendu && <p>Compte rendu : {s.compte_rendu}</p>}
                  </div>
                  {ph.length > 0 && (
                    <div className="flex gap-2 mt-2">
                      {ph.map(p => (
                        <div key={p.id} className="text-center">
                          {/* eslint-disable-next-line @next/next/no-img-element */}
                          <img src={p.url} alt="" className="w-14 h-14 rounded-lg object-cover" />
                          <p className="text-[10px] text-gray-500">{p.type === 'avant' ? 'Avant' : 'Après'}</p>
                        </div>
                      ))}
                    </div>
                  )}
                </button>
              );
            })}
          </div>
        )}
      </Carte>
      {modale}
    </>
  );
}
