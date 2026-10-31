'use client';

// Prestations & tarifs de l'éducateur / comportementaliste : seul endroit où se
// règlent les cours, les bilans, la règle du bilan préalable, les forfaits et
// les options tarifaires (supplément à domicile, autres lignes). La
// réservation, la fiche publique et le devis lisent ces mêmes données
// (lib/prestations-education.ts). Miroir appli : education_prestations_page.dart.

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { geocodeAddress } from '@/lib/geocoding';
import AddressAutocomplete from '@/components/AddressAutocomplete';
import {
  chargerPrestationsEducation, typeAffiche, uniteTarif,
  type PrestationEducation, type OptionTarifaire,
} from '@/lib/prestations-education';

const PURPLE = '#7B5EA7';
const TEAL = '#0C5C6C';
const inputCls = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm';

type TypeCours = 'individuel' | 'collectif' | 'bilan';

interface FormCours {
  id?: string; nom: string; description: string; duree_minutes: string; prix: string;
  type: TypeCours; capacite_max: string; domicile_ok: boolean;
  lieu_adresse: string; lieu_lat: number | null; lieu_lng: number | null;
  reservable: boolean; affiche_public: boolean; sans_bilan_prealable: boolean; conditions: string;
}

interface Forfait { id: string; nom: string; nb_seances: number; prix: number; description: string | null; affiche_public: boolean }

const FORM_VIDE: FormCours = {
  nom: '', description: '', duree_minutes: '60', prix: '', type: 'individuel', capacite_max: '6', domicile_ok: true,
  lieu_adresse: '', lieu_lat: null, lieu_lng: null, reservable: true, affiche_public: true, sans_bilan_prealable: false, conditions: '',
};

function Toggle({ checked, onChange, label, hint }: { checked: boolean; onChange: (v: boolean) => void; label: string; hint?: string }) {
  return (
    <div className="flex items-center justify-between gap-4 rounded-xl border p-3"
      style={{ borderColor: checked ? PURPLE : '#E5E7EB', background: checked ? `${PURPLE}0D` : 'white' }}>
      <div>
        <p className="text-sm font-semibold" style={{ fontFamily: 'Galey, sans-serif', color: checked ? PURPLE : '#374151' }}>{label}</p>
        {hint && <p className="text-xs text-gray-500 mt-0.5">{hint}</p>}
      </div>
      <button type="button" onClick={() => onChange(!checked)} aria-pressed={checked}
        className="relative w-12 h-7 rounded-full transition-colors flex-shrink-0"
        style={{ backgroundColor: checked ? PURPLE : '#D1D5DB' }}>
        <span className="absolute top-0.5 left-0.5 w-6 h-6 bg-white rounded-full shadow transition-transform"
          style={{ transform: checked ? 'translateX(20px)' : 'translateX(0)' }} />
      </button>
    </div>
  );
}

function Pastille({ texte, couleur }: { texte: string; couleur: 'violet' | 'gris' | 'ambre' }) {
  const s = couleur === 'violet' ? { background: `${PURPLE}1A`, color: PURPLE }
    : couleur === 'ambre' ? { background: '#FEF3C7', color: '#92400E' }
    : { background: '#F3F4F6', color: '#6B7280' };
  return <span className="text-xs font-semibold px-2 py-0.5 rounded-full" style={s}>{texte}</span>;
}

function Bloc({ titre, sousTitre, action, children }: { titre: string; sousTitre?: string; action?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="bg-white border border-gray-100 rounded-2xl p-4 shadow-sm">
      <div className="flex items-start justify-between gap-3 mb-3">
        <div>
          <h2 className="text-base font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>{titre}</h2>
          {sousTitre && <p className="text-xs text-gray-500 mt-0.5">{sousTitre}</p>}
        </div>
        {action}
      </div>
      {children}
    </section>
  );
}

export default function EducationPrestationsPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const activeProfileId = useActiveProfile();
  const [pid, setPid] = useState('');
  const [prestations, setPrestations] = useState<PrestationEducation[]>([]);
  const [forfaits, setForfaits] = useState<Forfait[]>([]);
  const [busy, setBusy] = useState(true);
  const [form, setForm] = useState<FormCours | null>(null);
  const [saving, setSaving] = useState(false);
  const [geocoding, setGeocoding] = useState(false);
  const [geocodeError, setGeocodeError] = useState(false);
  // Réglages du profil (user_profiles)
  const [bilanRequis, setBilanRequis] = useState(true);
  const [bilanDescription, setBilanDescription] = useState('');
  const [tarifsVisibles, setTarifsVisibles] = useState(false);
  const [tarifs, setTarifs] = useState<Record<string, number>>({});
  const [extra, setExtra] = useState<{ label: string; prix: number; description: string }[]>([]);
  const [reglagesModifies, setReglagesModifies] = useState(false);
  const [reglagesMsg, setReglagesMsg] = useState<string | null>(null);
  const [formForfait, setFormForfait] = useState<{ nom: string; nb: string; prix: string; description: string } | null>(null);

  const load = useCallback(async () => {
    if (!user?.uid) return;
    setBusy(true);
    // Profil éducateur : l'actif, sinon celui du compte (profil principal actif).
    let id = activeProfileId;
    if (!id) {
      const { data: p } = await supabase.from('user_profiles_complet').select('id')
        .eq('uid', user.uid).eq('profile_type', 'education').limit(1).maybeSingle();
      id = (p?.id as string | undefined) ?? '';
    }
    setPid(id);
    const [liste, { data: prof }, { data: fRows }] = await Promise.all([
      chargerPrestationsEducation(user.uid, id || null),
      id
        ? supabase.from('user_profiles').select('tarifs_education, tarifs_education_extra, tarifs_education_visibles, education_bilan_requis, education_bilan_description').eq('id', id).maybeSingle()
        : Promise.resolve({ data: null }),
      (() => {
        let q = supabase.from('forfaits_education').select('id, nom, nb_seances, prix, description, affiche_public')
          .eq('pro_uid', user.uid).eq('actif', true);
        if (id) q = q.or(`pro_profile_id.eq.${id},pro_profile_id.is.null`);
        return q.order('created_at');
      })(),
    ]);
    setPrestations(liste);
    setForfaits((fRows ?? []) as Forfait[]);
    const r = prof as Record<string, unknown> | null;
    if (r) {
      setBilanRequis((r.education_bilan_requis as boolean | null) ?? true);
      setBilanDescription((r.education_bilan_description as string | null) ?? '');
      setTarifsVisibles((r.tarifs_education_visibles as boolean | null) ?? false);
      setTarifs(r.tarifs_education && typeof r.tarifs_education === 'object' ? r.tarifs_education as Record<string, number> : {});
      setExtra(Array.isArray(r.tarifs_education_extra)
        ? (r.tarifs_education_extra as OptionTarifaire[]).map(e => ({ label: e.label ?? '', prix: Number(e.prix) || 0, description: e.description ?? '' }))
        : []);
    }
    setReglagesModifies(false);
    setBusy(false);
  }, [user, activeProfileId]);

  useEffect(() => { if (!loading && !user) router.push('/connexion'); }, [loading, user, router]);
  useEffect(() => { load(); }, [load]);

  const modifier = <T,>(set: (v: T) => void) => (v: T) => { set(v); setReglagesModifies(true); setReglagesMsg(null); };

  async function enregistrerReglages() {
    if (!pid) return;
    setSaving(true);
    // Seules les colonnes de cette page : la grille de prix par type n'est plus
    // éditée (reprise en cours par la migration), domicile_supplement y reste.
    const { error } = await supabase.from('user_profiles').update({
      education_bilan_requis: bilanRequis,
      education_bilan_description: bilanDescription.trim(),
      tarifs_education_visibles: tarifsVisibles,
      tarifs_education: tarifs,
      tarifs_education_extra: extra.filter(e => e.label.trim()).map(e => ({
        label: e.label.trim(), prix: Number(e.prix) || 0,
        ...(e.description.trim() ? { description: e.description.trim() } : {}),
      })),
    }).eq('id', pid);
    setSaving(false);
    if (error) { setReglagesMsg('Enregistrement impossible, réessayez.'); return; }
    setReglagesModifies(false);
    setReglagesMsg('Enregistré');
  }

  async function enregistrerCours() {
    if (!form || !form.nom.trim() || !user?.uid) return;
    setSaving(true);
    try {
      const lieu = form.lieu_adresse.trim();
      let lat = form.lieu_lat, lng = form.lieu_lng;
      if (lieu && lat == null) {
        const geo = await geocodeAddress(lieu);
        lat = geo?.lat ?? null; lng = geo?.lng ?? null;
      }
      const collectif = form.type === 'collectif';
      const bilan = form.type === 'bilan';
      const payload = {
        nom: form.nom.trim(),
        type: collectif ? 'collectif' : 'individuel',
        bilan_requis: bilan,
        description: form.description.trim() || null,
        duree_minutes: parseInt(form.duree_minutes, 10) || 60,
        prix: form.prix.trim() ? Number(form.prix) : null,
        domicile_ok: form.domicile_ok,
        lieu_adresse: lieu || null,
        lieu_lat: lieu ? lat : null,
        lieu_lng: lieu ? lng : null,
        capacite_max: collectif ? (parseInt(form.capacite_max, 10) || 6) : null,
        reservable: form.reservable,
        affiche_public: form.affiche_public,
        sans_bilan_prealable: bilan ? false : form.sans_bilan_prealable,
        conditions: form.conditions.trim() || null,
      };
      // Les RDV déjà pris gardent leur prix (rdv.prix_calcule) : changer un
      // tarif ici ne touche que les prochaines réservations.
      if (form.id) {
        await supabase.from('prestations_education').update(payload).eq('id', form.id);
      } else {
        await supabase.from('prestations_education').insert({ ...payload, pro_uid: user.uid, pro_profile_id: pid || null });
      }
      setForm(null);
      setPrestations(await chargerPrestationsEducation(user.uid, pid || null));
    } finally {
      setSaving(false);
    }
  }

  async function basculerCours(p: PrestationEducation, champ: 'reservable' | 'affiche_public') {
    const v = !p[champ];
    setPrestations(prev => prev.map(x => x.id === p.id ? { ...x, [champ]: v } : x));
    await supabase.from('prestations_education').update({ [champ]: v }).eq('id', p.id);
  }

  async function supprimerCours(p: PrestationEducation) {
    if (!confirm(`Supprimer « ${p.nom} » ? Les RDV déjà pris ne sont pas modifiés.`)) return;
    await supabase.from('prestations_education').update({ actif: false }).eq('id', p.id);
    setPrestations(prev => prev.filter(x => x.id !== p.id));
    if (form?.id === p.id) setForm(null);
  }

  async function ajouterForfait() {
    if (!formForfait || !formForfait.nom.trim() || !user?.uid) return;
    setSaving(true);
    const { data } = await supabase.from('forfaits_education').insert({
      pro_uid: user.uid, pro_profile_id: pid || null, nom: formForfait.nom.trim(),
      nb_seances: parseInt(formForfait.nb, 10) || 1, prix: Number(formForfait.prix) || 0,
      description: formForfait.description.trim() || null, affiche_public: true,
    }).select('id, nom, nb_seances, prix, description, affiche_public').maybeSingle();
    setSaving(false);
    if (data) setForfaits(prev => [...prev, data as Forfait]);
    setFormForfait(null);
  }

  async function basculerForfaitPublic(f: Forfait) {
    setForfaits(prev => prev.map(x => x.id === f.id ? { ...x, affiche_public: !f.affiche_public } : x));
    await supabase.from('forfaits_education').update({ affiche_public: !f.affiche_public }).eq('id', f.id);
  }

  async function supprimerForfait(f: Forfait) {
    if (!confirm(`Supprimer le forfait « ${f.nom} » ? Les forfaits déjà souscrits par vos clients continuent.`)) return;
    await supabase.from('forfaits_education').update({ actif: false }).eq('id', f.id);
    setForfaits(prev => prev.filter(x => x.id !== f.id));
  }

  const ouvrirCours = (p?: PrestationEducation) => {
    setGeocodeError(false);
    setForm(p ? {
      id: p.id, nom: p.nom, description: p.description ?? '',
      duree_minutes: String(p.duree_minutes), prix: p.prix != null ? String(p.prix) : '',
      type: p.bilan_requis ? 'bilan' : p.type ?? 'individuel',
      capacite_max: p.capacite_max != null ? String(p.capacite_max) : '6', domicile_ok: p.domicile_ok,
      lieu_adresse: p.lieu_adresse ?? '', lieu_lat: p.lieu_lat ?? null, lieu_lng: p.lieu_lng ?? null,
      reservable: p.reservable, affiche_public: p.affiche_public,
      sans_bilan_prealable: p.sans_bilan_prealable, conditions: p.conditions ?? '',
    } : { ...FORM_VIDE });
  };

  const bilans = prestations.filter(p => p.bilan_requis && p.reservable);
  const aVerifier = prestations.filter(p => !p.reservable && (p.description ?? '').startsWith('Repris de votre ancienne grille'));

  const formulaireCours = form && (
    <div className="border rounded-2xl p-4 mb-3 space-y-3" style={{ borderColor: `${PURPLE}55`, background: `${PURPLE}05` }}>
      <p className="text-sm font-bold text-[#1F2A2E]">{form.id ? 'Modifier le cours' : 'Nouveau cours'}</p>
      <div className="grid grid-cols-3 gap-2">
        {([['individuel', 'Individuel'], ['collectif', 'Collectif'], ['bilan', 'Bilan']] as const).map(([t, l]) => (
          <button key={t} type="button" onClick={() => setForm({ ...form, type: t })}
            className="py-2.5 rounded-xl text-sm font-semibold border-2 transition-all"
            style={{ background: form.type === t ? `${PURPLE}18` : 'white', borderColor: form.type === t ? PURPLE : '#e5e7eb', color: form.type === t ? PURPLE : '#6B7280' }}>
            {l}
          </button>
        ))}
      </div>
      {form.type === 'bilan' && (
        <p className="text-xs text-gray-500">Un bilan est le seul cours proposé à un nouveau client quand le bilan préalable est obligatoire.</p>
      )}
      <input value={form.nom} onChange={e => setForm({ ...form, nom: e.target.value })}
        placeholder={form.type === 'bilan' ? 'Nom — ex : Bilan comportemental' : 'Nom du cours — ex : Rappel chiot'} className={inputCls} />
      <div className="grid grid-cols-2 gap-3">
        <label className="text-xs text-gray-500">Durée (min)
          <input type="number" min={5} value={form.duree_minutes} onChange={e => setForm({ ...form, duree_minutes: e.target.value })} className={`${inputCls} mt-1`} />
        </label>
        <label className="text-xs text-gray-500">Prix (€ {form.type === 'collectif' ? 'par participant' : 'par séance'})
          <input type="number" min={0} value={form.prix} onChange={e => setForm({ ...form, prix: e.target.value })} placeholder="Optionnel" className={`${inputCls} mt-1`} />
        </label>
      </div>
      {form.type === 'collectif' && (
        <label className="text-xs text-gray-500 block">Capacité maximale (participants)
          <input type="number" min={1} value={form.capacite_max} onChange={e => setForm({ ...form, capacite_max: e.target.value })} className={`${inputCls} mt-1`} />
        </label>
      )}
      <textarea value={form.description} onChange={e => setForm({ ...form, description: e.target.value })}
        rows={2} placeholder="Description (optionnel)" className={`${inputCls} resize-none`} />
      <div>
        <AddressAutocomplete
          value={form.lieu_adresse}
          onChange={v => { setForm({ ...form, lieu_adresse: v, lieu_lat: null, lieu_lng: null }); setGeocodeError(false); }}
          onSelectCoords={({ lat, lng }) => setForm(f => f ? { ...f, lieu_lat: lat, lieu_lng: lng } : f)}
          placeholder="Lieu du cours (adresse, optionnel)"
          className={inputCls}
        />
        <p className="text-[11px] text-gray-400 mt-1">Ex. « Parc de la Tête d&apos;Or, Lyon ». Vide = à votre cabinet.</p>
        <div className="flex items-center gap-2 mt-2">
          {form.lieu_lat == null && (
            <button type="button" disabled={geocoding || !form.lieu_adresse.trim()}
              onClick={async () => {
                const adresse = form.lieu_adresse.trim();
                if (!adresse) return;
                setGeocoding(true);
                const geo = await geocodeAddress(adresse);
                setGeocoding(false);
                setForm(f => f ? { ...f, lieu_lat: geo?.lat ?? null, lieu_lng: geo?.lng ?? null } : f);
                setGeocodeError(!geo);
              }}
              className="text-xs font-semibold px-3 py-1.5 rounded-lg border disabled:opacity-50"
              style={{ borderColor: PURPLE, color: PURPLE }}>
              {geocoding ? 'Recherche…' : 'Localiser'}
            </button>
          )}
          {form.lieu_lat != null && form.lieu_lng != null && (
            <span className="text-xs font-medium text-green-600">Coordonnées GPS enregistrées</span>
          )}
          {geocodeError && form.lieu_lat == null && (
            <span className="text-xs font-medium text-orange-600">Adresse introuvable — précisez la ville</span>
          )}
        </div>
      </div>
      <Toggle checked={form.domicile_ok} onChange={v => setForm({ ...form, domicile_ok: v })}
        label="Peut être proposé à domicile"
        hint="La famille pourra le demander à domicile sur les créneaux que vous autorisez (supplément à domicile ajouté s'il est défini)" />
      {form.type !== 'bilan' && (
        <Toggle checked={form.sans_bilan_prealable} onChange={v => setForm({ ...form, sans_bilan_prealable: v })}
          label="Réservable sans bilan préalable"
          hint="Exception : un nouveau client peut le réserver même si le bilan préalable est obligatoire" />
      )}
      <textarea value={form.conditions} onChange={e => setForm({ ...form, conditions: e.target.value })}
        rows={2} placeholder="Conditions de réservation (optionnel) — ex : chiot de moins de 6 mois, vaccins à jour"
        className={`${inputCls} resize-none`} />
      <Toggle checked={form.reservable} onChange={v => setForm({ ...form, reservable: v })}
        label="Actif" hint="Désactivé = en pause : ni réservable, ni affiché sur votre fiche" />
      <Toggle checked={form.affiche_public} onChange={v => setForm({ ...form, affiche_public: v })}
        label="Prix affiché sur ma fiche publique" hint="Dans la liste des tarifs, si l'affichage des tarifs est activé plus bas" />
      <div className="flex gap-2">
        <button onClick={() => setForm(null)} className="flex-1 border border-gray-200 rounded-xl py-2 text-sm text-gray-500">Annuler</button>
        <button onClick={enregistrerCours} disabled={saving || !form.nom.trim()}
          className="flex-1 text-white rounded-xl py-2 text-sm font-semibold disabled:opacity-50" style={{ background: PURPLE }}>
          {saving ? 'Enregistrement…' : 'Enregistrer'}
        </button>
      </div>
    </div>
  );

  return (
    <div className="max-w-2xl mx-auto px-4 py-6 space-y-4">
      <div>
        <h1 className="text-xl font-bold text-[#1F2A2E]" style={{ fontFamily: 'Galey, sans-serif' }}>Prestations &amp; tarifs</h1>
        <p className="text-sm text-gray-500 mt-1">
          Vos cours, bilans, forfaits et options : ce sont ces prix qui s&apos;affichent sur votre fiche, dans les réservations et dans vos devis.
        </p>
      </div>

      {busy ? (
        <p className="text-sm text-gray-400">Chargement…</p>
      ) : (
        <>
          {aVerifier.length > 0 && (
            <div className="rounded-2xl border p-3 text-sm" style={{ borderColor: '#F3D9A4', background: '#FFFBEB', color: '#92400E' }}>
              {aVerifier.length} cours {aVerifier.length > 1 ? 'ont été repris' : 'a été repris'} de votre ancienne grille de tarifs.
              Ils sont en pause : vérifiez-les, puis activez ceux que vous proposez.
            </div>
          )}

          <Bloc titre="Cours et bilans" sousTitre="La famille les choisit dans le calendrier de réservation de votre fiche."
            action={!form && (
              <button onClick={() => ouvrirCours()} className="text-white rounded-xl px-3 py-2 text-sm font-semibold shrink-0" style={{ background: PURPLE }}>
                Ajouter un cours
              </button>
            )}>
            {form && !form.id && formulaireCours}
            {prestations.length === 0 && !form ? (
              <p className="text-sm text-gray-400">Aucun cours configuré.</p>
            ) : (
              <div className="space-y-2">
                {prestations.map(p => (
                  form?.id === p.id ? <div key={p.id}>{formulaireCours}</div> : (
                    <div key={p.id} className="border border-gray-100 rounded-xl p-3" style={{ opacity: p.reservable ? 1 : 0.75 }}>
                      <div className="flex items-start gap-3">
                        <button type="button" onClick={() => ouvrirCours(p)} className="flex-1 min-w-0 text-left">
                          <p className="text-sm font-semibold text-[#1F2A2E]">{p.nom}</p>
                          <p className="text-xs text-gray-500">
                            {typeAffiche(p)}{p.type === 'collectif' ? ` (max ${p.capacite_max ?? 6})` : ''} · {p.duree_minutes} min
                            {p.prix != null ? ` · ${p.prix} € ${uniteTarif(p)}` : ' · prix non renseigné'}
                          </p>
                          {p.description && <p className="text-xs text-gray-600 mt-0.5 line-clamp-2">{p.description}</p>}
                        </button>
                        <button onClick={() => ouvrirCours(p)} className="text-xs font-semibold shrink-0" style={{ color: TEAL }}>Modifier</button>
                      </div>
                      <div className="flex flex-wrap items-center gap-1.5 mt-2">
                        <button type="button" onClick={() => basculerCours(p, 'reservable')}>
                          <Pastille texte={p.reservable ? 'Actif' : 'En pause'} couleur={p.reservable ? 'violet' : 'ambre'} />
                        </button>
                        <button type="button" onClick={() => basculerCours(p, 'affiche_public')}>
                          <Pastille texte={p.affiche_public ? 'Prix sur la fiche' : 'Prix masqué'} couleur={p.affiche_public ? 'violet' : 'gris'} />
                        </button>
                        {p.domicile_ok && <Pastille texte="À domicile possible" couleur="gris" />}
                        {!p.bilan_requis && p.sans_bilan_prealable && <Pastille texte="Sans bilan préalable" couleur="gris" />}
                        <button onClick={() => supprimerCours(p)} className="ml-auto text-xs text-gray-400 hover:text-red-500">Supprimer</button>
                      </div>
                    </div>
                  )
                ))}
              </div>
            )}
          </Bloc>

          <Bloc titre="Bilan préalable" sousTitre="Vérifié à chaque réservation : un client sans séance confirmée ou terminée avec vous est un nouveau client.">
            <div className="space-y-3">
              <Toggle checked={bilanRequis} onChange={modifier(setBilanRequis)}
                label="Bilan obligatoire avant les autres cours"
                hint="Un nouveau client ne peut réserver qu'un bilan, ou un cours marqué « Réservable sans bilan préalable »" />
              {bilanRequis && bilans.length === 0 && (
                <p className="text-xs font-medium text-orange-600">
                  Aucun bilan actif dans vos cours : les nouveaux clients verront tous vos cours. Ajoutez un cours de type « Bilan ».
                </p>
              )}
              <label className="text-xs font-medium text-gray-500 block">Présentation du bilan (déroulé, ce qu&apos;il faut prévoir)
                <textarea rows={3} value={bilanDescription} onChange={e => modifier(setBilanDescription)(e.target.value)} className={`${inputCls} mt-1`} />
              </label>
            </div>
          </Bloc>

          <Bloc titre="Forfaits" sousTitre="Plusieurs séances à un prix global. Appliqué au client depuis le dossier de la séance ; les séances utilisées sont décomptées."
            action={!formForfait && (
              <button onClick={() => setFormForfait({ nom: '', nb: '5', prix: '', description: '' })}
                className="text-sm font-semibold shrink-0" style={{ color: PURPLE }}>Ajouter un forfait</button>
            )}>
            {formForfait && (
              <div className="border rounded-xl p-3 mb-3 space-y-2" style={{ borderColor: `${PURPLE}55` }}>
                <input value={formForfait.nom} onChange={e => setFormForfait({ ...formForfait, nom: e.target.value })}
                  placeholder="Nom du forfait — ex : Pack 5 séances" className={inputCls} />
                <div className="grid grid-cols-2 gap-2">
                  <label className="text-xs text-gray-500">Nombre de séances
                    <input type="number" min={1} value={formForfait.nb} onChange={e => setFormForfait({ ...formForfait, nb: e.target.value })} className={`${inputCls} mt-1`} />
                  </label>
                  <label className="text-xs text-gray-500">Prix total (€)
                    <input type="number" min={0} value={formForfait.prix} onChange={e => setFormForfait({ ...formForfait, prix: e.target.value })} className={`${inputCls} mt-1`} />
                  </label>
                </div>
                <input value={formForfait.description} onChange={e => setFormForfait({ ...formForfait, description: e.target.value })}
                  placeholder="Description (optionnel)" className={inputCls} />
                <div className="flex gap-2">
                  <button onClick={() => setFormForfait(null)} className="flex-1 border border-gray-200 rounded-xl py-2 text-sm text-gray-500">Annuler</button>
                  <button onClick={ajouterForfait} disabled={saving || !formForfait.nom.trim()}
                    className="flex-1 text-white rounded-xl py-2 text-sm font-semibold disabled:opacity-50" style={{ background: PURPLE }}>Valider</button>
                </div>
              </div>
            )}
            {forfaits.length === 0 ? (
              !formForfait && <p className="text-sm text-gray-400">Aucun forfait.</p>
            ) : (
              <div className="space-y-2">
                {forfaits.map(f => (
                  <div key={f.id} className="border border-gray-100 rounded-xl p-3 flex items-center gap-3">
                    <div className="flex-1 min-w-0">
                      <p className="text-sm font-semibold text-[#1F2A2E]">{f.nom}</p>
                      <p className="text-xs text-gray-500">{f.nb_seances} séance{f.nb_seances > 1 ? 's' : ''} · {f.prix} €{f.description ? ` · ${f.description}` : ''}</p>
                    </div>
                    <button type="button" onClick={() => basculerForfaitPublic(f)}>
                      <Pastille texte={f.affiche_public ? 'Sur la fiche' : 'Masqué'} couleur={f.affiche_public ? 'violet' : 'gris'} />
                    </button>
                    <button onClick={() => supprimerForfait(f)} className="text-xs text-gray-400 hover:text-red-500">Supprimer</button>
                  </div>
                ))}
              </div>
            )}
          </Bloc>

          <Bloc titre="Options tarifaires" sousTitre="S'ajoutent au prix d'un cours. Le supplément à domicile est ajouté automatiquement aux réservations à domicile.">
            <label className="text-xs font-medium text-gray-500 block mb-3">Supplément à domicile (€)
              <input type="number" min={0} value={tarifs.domicile_supplement ?? 0}
                onChange={e => modifier(setTarifs)({ ...tarifs, domicile_supplement: Number(e.target.value) || 0 })}
                className={`${inputCls} mt-1 max-w-[160px]`} />
            </label>
            <p className="text-xs font-medium text-gray-600 mb-2">Autres options (ex : frais de déplacement au-delà de 20 km, compte rendu écrit détaillé)</p>
            <div className="space-y-2">
              {extra.map((e, i) => (
                <div key={i} className="bg-gray-50 rounded-xl p-2 space-y-1">
                  <div className="flex items-center gap-2">
                    <input placeholder="Nom de l'option" value={e.label}
                      onChange={ev => modifier(setExtra)(extra.map((x, j) => j === i ? { ...x, label: ev.target.value } : x))}
                      className={`${inputCls} flex-1`} />
                    <input type="number" min={0} value={e.prix} aria-label="Prix (€)"
                      onChange={ev => modifier(setExtra)(extra.map((x, j) => j === i ? { ...x, prix: Number(ev.target.value) } : x))}
                      className={`${inputCls} !w-24`} />
                    <button type="button" onClick={() => modifier(setExtra)(extra.filter((_, j) => j !== i))}
                      className="text-xs text-gray-400 hover:text-red-500 px-1">Retirer</button>
                  </div>
                  <input placeholder="Description (facultatif)" value={e.description}
                    onChange={ev => modifier(setExtra)(extra.map((x, j) => j === i ? { ...x, description: ev.target.value } : x))}
                    className={`${inputCls} text-xs`} />
                </div>
              ))}
              <button type="button" onClick={() => modifier(setExtra)([...extra, { label: '', prix: 0, description: '' }])}
                className="text-sm font-semibold" style={{ color: PURPLE }}>Ajouter une option</button>
            </div>
          </Bloc>

          <Bloc titre="Affichage sur ma fiche publique">
            <Toggle checked={tarifsVisibles} onChange={modifier(setTarifsVisibles)}
              label="Afficher mes tarifs"
              hint="Cours dont le prix est affiché, options et forfaits affichés" />
          </Bloc>

          <div className="sticky bottom-3 flex items-center justify-end gap-3">
            {reglagesMsg && <span className="text-xs font-medium" style={{ color: reglagesMsg === 'Enregistré' ? '#16A34A' : '#DC2626' }}>{reglagesMsg}</span>}
            <button onClick={enregistrerReglages} disabled={saving || !reglagesModifies || !pid}
              className="text-white rounded-xl px-4 py-2.5 text-sm font-semibold shadow disabled:opacity-40" style={{ background: TEAL }}>
              Enregistrer le bilan, les options et l&apos;affichage
            </button>
          </div>
        </>
      )}
    </div>
  );
}
