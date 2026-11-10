'use client';

import { useEffect, useState, useCallback } from 'react';
import { useRouter } from 'next/navigation';
import { usePensionAccess } from '@/hooks/usePensionAccess';
import { useActiveProfile } from '@/hooks/useActiveProfile';
import { supabase } from '@/lib/supabase';
import HorairesPensionForm from '@/components/pension/HorairesPensionForm';
import { ACCEPT_DOCUMENT_PRO, deposerDocumentPro, fichierEnPdf } from '@/lib/document-pro';
import { lireHoraires, type HorairesPension } from '@/lib/pension-horaires';
import { PENSION_ESPECES, pensionGroupe, pensionTarifAccepte, pensionTarifEquin, type TarifsPension } from '@/lib/pension-especes';

interface EspeceRow {
  key: string;
  label: string;
  emoji: string;
  accepte: boolean;
  prixSeul: string;
  prixPartage: string;
}

interface Reduction {
  minNuits: string;
  pourcentage: string;
}

const num = (s: string) => {
  const n = parseFloat(s.replace(',', '.'));
  return Number.isFinite(n) ? n : null;
};

export default function PensionTarifsPage() {
  const { user, userData, isPension, loading: authLoading } = usePensionAccess();
  const activeProfileId = useActiveProfile();
  const router = useRouter();

  const [profileId, setProfileId] = useState<string | null>(null);
  const [especes, setEspeces] = useState<EspeceRow[]>([]);
  const [reductions, setReductions] = useState<Reduction[]>([]);
  // Règlement du séjour (repris dans le contrat) : arrhes facultatives + moment du solde.
  const [arrhes, setArrhes] = useState(false);
  const [arrhesPct, setArrhesPct] = useState('30');
  const [solde, setSolde] = useState<'arrivee' | 'depart'>('arrivee');
  const [afficherPublic, setAfficherPublic] = useState(false);
  // Essai obligatoire avant le premier séjour (réservation en ligne).
  const [essaiRequis, setEssaiRequis] = useState(false);
  const [essaiInfo, setEssaiInfo] = useState('');
  // Essai : facturé ou non (au choix de la pension), et son prix.
  const [essaiFacture, setEssaiFacture] = useState(false);
  const [essaiPrix, setEssaiPrix] = useState('');
  // Durée d'une visite de la pension (RDV « visite », durees_motifs.visite).
  const [dureeVisite, setDureeVisite] = useState(30);
  const [dureesMotifs, setDureesMotifs] = useState<Record<string, number>>({});
  // Horaires d'arrivée / de départ (null = pas d'horaires).
  const [horaires, setHoraires] = useState<HorairesPension | null>(null);
  const [erreurHoraires, setErreurHoraires] = useState('');
  // Modèle de contrat de la pension (envoyé à la place du contrat PetsMatch).
  const [modele, setModele] = useState<{ url: string; nom: string; le?: string } | null>(null);
  const [envoiModele, setEnvoiModele] = useState('');
  const [showAutres, setShowAutres] = useState(false);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [saved, setSaved] = useState(false);

  useEffect(() => {
    if (authLoading) return;
    if (!user) { router.push('/connexion'); return; }
    if (userData && !isPension) { router.push('/'); return; }
  }, [user, userData, isPension, authLoading, router]);

  const load = useCallback(async () => {
    if (!user) return;
    let pid = activeProfileId || null;
    if (!pid) {
      const { data: mainProfile } = await supabase.from('user_profiles_complet')
        .select('id').eq('uid', user.uid).eq('is_main', true).maybeSingle();
      pid = mainProfile?.id ?? null;
    }
    setProfileId(pid);
    if (!pid) { setLoading(false); return; }

    const { data } = await supabase.from('user_profiles_complet')
      .select('tarifs_pension, especes_acceptees').eq('id', pid).maybeSingle();
    const t = (data?.tarifs_pension ?? null) as (TarifsPension & { afficher_public?: boolean }) | null;
    const acceptees = new Set((data?.especes_acceptees as string[] | undefined) ?? []);
    setAfficherPublic(t?.afficher_public === true);
    const { data: es } = await supabase.from('user_profiles').select('pension_essai_requis, pension_essai_info').eq('id', pid).maybeSingle();
    setEssaiRequis((es as { pension_essai_requis?: boolean } | null)?.pension_essai_requis === true);
    setEssaiInfo((es as { pension_essai_info?: string | null } | null)?.pension_essai_info ?? '');
    // Colonne absente tant que migration_pension_horaires.sql n'est pas passée.
    const { data: hr } = await supabase.from('user_profiles').select('pension_horaires').eq('id', pid).maybeSingle();
    setHoraires(lireHoraires((hr as { pension_horaires?: unknown } | null)?.pension_horaires));
    const { data: md } = await supabase.from('user_profiles').select('pension_contrat_modele').eq('id', pid).maybeSingle();
    const m = (md as { pension_contrat_modele?: { url?: string; nom?: string; le?: string } | null } | null)?.pension_contrat_modele;
    setModele(m?.url ? { url: m.url, nom: m.nom || 'Mon contrat', le: m.le } : null);

    // Prix déjà saisis, par key.
    const prixByKey: Record<string, { seul: string; partage: string }> = {};
    if (Array.isArray(t?.especes)) {
      for (const e of t.especes) {
        // Équidés : box / pré.
        prixByKey[e.espece] = pensionTarifEquin(e.espece) ? {
          seul: e.prix_box != null ? String(e.prix_box) : e.prix_pre == null && e.prix_seul != null ? String(e.prix_seul) : '',
          partage: e.prix_pre != null ? String(e.prix_pre) : '',
        } : {
          seul: e.prix_seul != null ? String(e.prix_seul) : '',
          partage: e.prix_partage != null ? String(e.prix_partage) : '',
        };
      }
    } else if (Array.isArray(t?.tranches_poids) && t.tranches_poids.length > 0) {
      // Rétro-compat : reprend le prix de la 1re tranche comme défaut pour
      // les espèces acceptées.
      const first = t.tranches_poids[0];
      const seul = first.prix_seul != null ? String(first.prix_seul) : '';
      const partage = first.prix_partage != null ? String(first.prix_partage) : '';
      for (const sp of PENSION_ESPECES) {
        if (pensionTarifAccepte(sp.key, acceptees)) prixByKey[sp.key] = { seul, partage };
      }
    }

    // Ancien tarif unique « Animaux de la ferme » → repris pour chaque espèce
    // de la ferme qui n'a pas encore son prix.
    for (const sp of PENSION_ESPECES) {
      const legacy = prixByKey[pensionGroupe(sp.key)];
      if (legacy && pensionGroupe(sp.key) === 'animaux_ferme' && !prixByKey[sp.key]) prixByKey[sp.key] = legacy;
    }

    const rows: EspeceRow[] = PENSION_ESPECES.map(sp => ({
      key: sp.key,
      label: sp.label,
      emoji: sp.emoji,
      accepte: pensionTarifAccepte(sp.key, acceptees),
      prixSeul: prixByKey[sp.key]?.seul ?? '',
      prixPartage: prixByKey[sp.key]?.partage ?? '',
    })).sort((a, b) => (a.accepte === b.accepte ? 0 : a.accepte ? -1 : 1));

    setEspeces(rows);
    const reg = (t as { reglement?: { arrhes_pct?: number | null; solde?: string } } | null)?.reglement;
    setArrhes((reg?.arrhes_pct ?? 0) > 0);
    if ((reg?.arrhes_pct ?? 0) > 0) setArrhesPct(String(reg!.arrhes_pct));
    setSolde(reg?.solde === 'depart' ? 'depart' : 'arrivee');
    const cfgEssai = (t as { essai?: { facture?: boolean; prix?: number | null } } | null)?.essai;
    setEssaiFacture(cfgEssai?.facture === true);
    setEssaiPrix(cfgEssai?.prix ? String(cfgEssai.prix) : '');
    const { data: dm } = await supabase.from('user_profiles').select('durees_motifs').eq('id', pid).maybeSingle();
    const dms = ((dm as { durees_motifs?: Record<string, number> | null } | null)?.durees_motifs ?? {}) as Record<string, number>;
    setDureesMotifs(dms);
    setDureeVisite(Number(dms.visite) > 0 ? Number(dms.visite) : 30);
    setReductions(((t?.reductions_long_sejour ?? []) as { min_nuits?: number; pourcentage?: number }[]).map(m => ({
      minNuits: m.min_nuits != null ? String(m.min_nuits) : '',
      pourcentage: m.pourcentage != null ? String(m.pourcentage) : '',
    })));
    setLoading(false);
  }, [user, activeProfileId]);

  useEffect(() => { load(); }, [load]);

  const save = async () => {
    if (!profileId) return;
    setSaving(true);
    setSaved(false);

    const especesOut = especes
      .filter(e => e.prixSeul.trim() !== '' || (pensionTarifEquin(e.key) && e.prixPartage.trim() !== ''))
      .map(e => {
        if (pensionTarifEquin(e.key)) {
          // Équidés : box / pré ; prix_seul repris pour les anciens lecteurs.
          const box = num(e.prixSeul), pre = num(e.prixPartage);
          const base = box ?? pre ?? 0;
          return { espece: e.key, prix_box: box, prix_pre: pre, prix_seul: base, prix_partage: base };
        }
        const seul = num(e.prixSeul) ?? 0;
        return { espece: e.key, prix_seul: seul, prix_partage: num(e.prixPartage) ?? seul };
      });

    const reductions_long_sejour = reductions
      .filter(r => r.minNuits.trim() !== '')
      .map(r => ({
        min_nuits: Math.round(num(r.minNuits) ?? 0),
        pourcentage: num(r.pourcentage) ?? 0,
      }))
      .sort((a, b) => a.min_nuits - b.min_nuits);

    await supabase.from('user_profiles')
      .update({ tarifs_pension: { especes: especesOut, reductions_long_sejour, afficher_public: afficherPublic,
        reglement: { arrhes_pct: arrhes ? (num(arrhesPct) ?? 0) : null, solde },
        essai: { facture: essaiFacture, prix: essaiFacture ? (num(essaiPrix) ?? 0) : null } } })
      .eq('id', profileId);
    await supabase.from('user_profiles')
      .update({ pension_essai_requis: essaiRequis, pension_essai_info: essaiInfo.trim() || null })
      .eq('id', profileId);
    await supabase.from('user_profiles').update({ durees_motifs: { ...dureesMotifs, visite: dureeVisite } }).eq('id', profileId);
    const { error: errH } = await supabase.from('user_profiles').update({ pension_horaires: horaires }).eq('id', profileId);
    setErreurHoraires(errH ? `Horaires non enregistrés : ${errH.message}` : '');

    setSaving(false);
    setSaved(true);
    setTimeout(() => setSaved(false), 3000);
  };

  if (!user || !userData || loading) {
    return <div className="max-w-4xl mx-auto px-4 py-10 text-center text-gray-400 font-galey">Chargement…</div>;
  }

  const inputCls = "w-full px-3 py-2 border border-gray-200 rounded-lg text-sm font-galey focus:outline-none focus:ring-2 focus:ring-teal-300";

  return (
    <div className="max-w-4xl mx-auto px-4 py-6 space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold font-galey text-teal-800">Tarification</h1>
        <button onClick={save} disabled={saving}
          className="bg-teal-700 disabled:opacity-60 text-white px-4 py-2 rounded-full text-sm font-galey font-semibold hover:bg-teal-800 transition-colors">
          {saving ? 'Enregistrement…' : 'Enregistrer'}
        </button>
      </div>
      {saved && <p className="text-sm font-galey text-[#6E9E57]">✓ Tarifs enregistrés.</p>}

      <label className={`flex items-start gap-3 bg-white rounded-2xl shadow-sm p-4 border cursor-pointer ${afficherPublic ? 'border-[#6E9E57]/40' : 'border-gray-100'}`}>
        <input type="checkbox" className="mt-1" checked={afficherPublic}
          onChange={e => setAfficherPublic(e.target.checked)} />
        <span>
          <span className="block font-galey font-semibold text-sm text-[#1E2025]">Afficher mes tarifs sur ma fiche publique</span>
          <span className="block font-galey text-xs text-gray-500 mt-0.5">
            Les clients verront le prix par nuit et par espèce dans l&apos;annuaire des pros.
          </span>
        </span>
      </label>

      <div className={`bg-white rounded-2xl shadow-sm p-4 border ${essaiRequis ? 'border-[#6E9E57]/40' : 'border-gray-100'}`}>
        <label className="flex items-start gap-3 cursor-pointer">
          <input type="checkbox" className="mt-1" checked={essaiRequis} onChange={e => setEssaiRequis(e.target.checked)} />
          <span>
            <span className="block font-galey font-semibold text-sm text-[#1E2025]">Essai obligatoire avant le premier séjour</span>
            <span className="block font-galey text-xs text-gray-500 mt-0.5">
              À la réservation en ligne, le client propose une date d&apos;essai (une journée) avant le premier séjour de son animal.
            </span>
          </span>
        </label>
        {essaiRequis && (
          <>
            <input value={essaiInfo} onChange={e => setEssaiInfo(e.target.value)} placeholder="Précisions pour le client (facultatif) : journée de 9 h à 17 h, ce que l'essai permet d'observer"
              className={`${inputCls} mt-3`} />
            <label className="flex items-center gap-2 mt-3 text-sm font-galey text-[#1E2025]">
              <input type="checkbox" checked={essaiFacture} onChange={e => setEssaiFacture(e.target.checked)} />
              Essai facturé
            </label>
            {essaiFacture ? (
              <label className="flex items-center gap-2 mt-2 text-sm font-galey text-[#1E2025]">Prix de l&apos;essai
                <input type="number" min={0} step={1} value={essaiPrix} onChange={e => setEssaiPrix(e.target.value)} className={`${inputCls} w-24`} /> €
              </label>
            ) : (
              <p className="text-xs text-gray-500 mt-1 font-galey">Essai non facturé : il sert à observer le comportement de l&apos;animal ; il n&apos;apparaît jamais comme « à facturer ».</p>
            )}
            <p className="text-xs text-gray-500 mt-1 font-galey">Avec vos horaires d&apos;arrivée, le client choisit aussi l&apos;heure de l&apos;essai.</p>
          </>
        )}
      </div>

      <HorairesPensionForm value={horaires} onChange={setHoraires} />
      <div className="bg-white rounded-2xl shadow-sm p-4 border border-gray-100">
        <label className="flex items-center justify-between gap-3 text-sm font-galey text-[#1E2025]">
          <span><span className="block font-semibold">Durée d&apos;une visite de la pension</span>
            <span className="block text-xs text-gray-500">Rendez-vous « visite » pris par un client avant de réserver.</span></span>
          <span className="flex items-center gap-1.5">
            <input type="number" min={5} max={240} step={5} value={dureeVisite} onChange={e => setDureeVisite(Math.max(5, Number(e.target.value) || 30))}
              className="w-20 px-2 py-1.5 border border-gray-200 rounded-lg text-sm text-right" />
            <span className="text-xs text-gray-500">min</span>
          </span>
        </label>
      </div>

      {/* Mon contrat d'hébergement : modèle envoyé à la place du contrat PetsMatch. */}
      <div className={`bg-white rounded-2xl shadow-sm p-4 border ${modele ? 'border-[#6E9E57]/40' : 'border-gray-100'} space-y-2`}>
        <p className="font-galey font-semibold text-sm text-[#1E2025]">Mon contrat d&apos;hébergement</p>
        <p className="font-galey text-xs text-gray-500">Vous avez votre propre contrat ? Chargez-le (PDF ou photo) : à l&apos;arrivée, vous pourrez l&apos;envoyer à la place du contrat PetsMatch. Il est signé en ligne par le client, avec votre signature enregistrée.</p>
        {modele ? (
          <div className="flex flex-wrap items-center gap-3 text-sm font-galey">
            <a href={modele.url} target="_blank" rel="noopener" className="font-semibold text-[#0C5C6C]">{modele.nom}</a>
            <button type="button" onClick={async () => {
              if (!profileId || !window.confirm('Retirer votre modèle de contrat ?')) return;
              const { error } = await supabase.from('user_profiles').update({ pension_contrat_modele: null }).eq('id', profileId);
              if (error) { setEnvoiModele(`Erreur : ${error.message}`); return; }
              setModele(null);
            }} className="text-xs font-semibold text-[#B3261E]">Retirer</button>
          </div>
        ) : null}
        <input type="file" accept={ACCEPT_DOCUMENT_PRO} className="block w-full text-xs text-gray-600" onChange={async e => {
          const f = e.target.files?.[0]; e.target.value = '';
          if (!f || !user || !profileId) return;
          setEnvoiModele('Envoi…');
          try {
            const url = await deposerDocumentPro(await fichierEnPdf(f), user.uid);
            const m = { url, nom: f.name.replace(/\.[^.]+$/, '') || 'Mon contrat', le: new Date().toISOString() };
            const { error } = await supabase.from('user_profiles').update({ pension_contrat_modele: m }).eq('id', profileId);
            if (error) throw new Error(error.message);
            setModele(m); setEnvoiModele('Modèle enregistré.');
          } catch (err) { setEnvoiModele(`Erreur : ${err instanceof Error ? err.message : String(err)}`); }
        }} />
        {envoiModele && <p className="text-xs font-galey text-gray-600">{envoiModele}</p>}
      </div>
      {erreurHoraires && <p className="text-sm text-[#B3261E] font-galey">{erreurHoraires}</p>}

      <div className="bg-white rounded-2xl shadow-sm p-5 space-y-4 border border-teal-100">
        <div>
          <h2 className="font-bold font-galey text-teal-800">Prix par espèce</h2>
          <p className="text-xs font-galey text-gray-500 mt-1">
            Tarif par nuit selon l&apos;espèce et selon que l&apos;animal est seul ou partage son logement.
            Le tarif est ensuite suggéré automatiquement à la facturation.
          </p>
        </div>
        {especes.filter(e => e.accepte).length === 0 && (
          <p className="text-xs font-galey text-orange-800 bg-orange-50 border border-orange-200 rounded-lg p-2.5">
            Aucune espèce acceptée définie. Ajoutez vos espèces dans votre profil pour ne remplir que celles-ci.
          </p>
        )}
        <div className="space-y-3">
          {especes.map((e, i) => {
            const anyAccepted = especes.some(x => x.accepte);
            const visible = anyAccepted ? (e.accepte || showAutres) : true;
            if (!visible) return null;
            return (
              <div key={e.key} className="border border-gray-100 rounded-xl p-3">
                <div className="flex items-center gap-2 mb-2">
                  <span className="font-galey font-bold text-sm text-[#1E2025]">{e.label}</span>
                  {e.accepte && (
                    <span className="text-[10px] font-galey font-bold px-2 py-0.5 rounded-full bg-[#6E9E57]/12 text-[#6E9E57]">
                      Accepté
                    </span>
                  )}
                </div>
                <div className="flex flex-wrap items-center gap-2">
                  <input placeholder={pensionTarifEquin(e.key) ? 'Box (€ TTC/nuit)' : 'Prix seul (€ TTC/nuit)'} value={e.prixSeul} inputMode="decimal"
                    onChange={ev => setEspeces(rows => rows.map((x, j) => j === i ? { ...x, prixSeul: ev.target.value } : x))}
                    className={`${inputCls} flex-1 min-w-[140px]`} />
                  <input placeholder={pensionTarifEquin(e.key) ? 'Pré (€ TTC/nuit)' : 'Prix partagé (€ TTC/nuit)'} value={e.prixPartage} inputMode="decimal"
                    onChange={ev => setEspeces(rows => rows.map((x, j) => j === i ? { ...x, prixPartage: ev.target.value } : x))}
                    className={`${inputCls} flex-1 min-w-[140px]`} />
                </div>
              </div>
            );
          })}
        </div>
        {especes.some(e => e.accepte) && especes.some(e => !e.accepte) && (
          <button onClick={() => setShowAutres(v => !v)}
            className="text-sm font-galey font-semibold text-teal-700">
            {showAutres ? '− Masquer les autres espèces' : '+ Tarif pour une autre espèce'}
          </button>
        )}
      </div>

      <div className="bg-white rounded-2xl shadow-sm p-5 space-y-4 border border-teal-100">
        <div>
          <h2 className="font-bold font-galey text-teal-800">Réductions séjour long</h2>
          <p className="text-xs font-galey text-gray-500 mt-1">
            Réduction appliquée sur le tarif total à partir d&apos;un nombre de nuits (toutes espèces).
          </p>
        </div>
        <div className="space-y-3">
          {reductions.map((r, i) => (
            <div key={i} className="flex flex-wrap items-center gap-2">
              <input placeholder="À partir de (nuits)" value={r.minNuits} inputMode="numeric"
                onChange={e => setReductions(rs => rs.map((x, j) => j === i ? { ...x, minNuits: e.target.value } : x))}
                className={`${inputCls} flex-1 min-w-[160px]`} />
              <input placeholder="Réduction (%)" value={r.pourcentage} inputMode="decimal"
                onChange={e => setReductions(rs => rs.map((x, j) => j === i ? { ...x, pourcentage: e.target.value } : x))}
                className={`${inputCls} flex-1 min-w-[140px]`} />
              <button onClick={() => setReductions(rs => rs.filter((_, j) => j !== i))}
                className="text-red-500 hover:text-red-600 text-sm font-galey px-2">✕</button>
            </div>
          ))}
        </div>
        <button onClick={() => setReductions(rs => [...rs, { minNuits: '', pourcentage: '' }])}
          className="text-sm font-galey font-semibold text-teal-700 border border-teal-200 rounded-full px-4 py-1.5 hover:bg-teal-50 transition-colors">
          + Ajouter une réduction
        </button>
      </div>

      <div className="bg-white rounded-2xl shadow-sm p-5 space-y-3 border border-teal-100">
        <div>
          <h2 className="font-bold font-galey text-teal-800">Règlement du séjour</h2>
          <p className="text-xs font-galey text-gray-500 mt-1">
            Repris dans le contrat d&apos;hébergement. Les arrhes confirment la réservation : si le client annule, elles restent acquises
            à la pension ; si la pension annule, elle les rembourse au double.
          </p>
        </div>
        <label className="flex items-center gap-2 text-sm font-galey cursor-pointer">
          <input type="checkbox" checked={arrhes} onChange={e => setArrhes(e.target.checked)} />
          Demander des arrhes à la réservation
        </label>
        {arrhes && (
          <div className="flex items-center gap-2">
            <input value={arrhesPct} onChange={e => setArrhesPct(e.target.value)} inputMode="decimal" className={`${inputCls} w-28`} />
            <span className="text-sm font-galey text-gray-600">% du séjour (souvent 25 à 30 %)</span>
          </div>
        )}
        <div className="flex flex-wrap items-center gap-2 text-sm font-galey">
          <span>{arrhes ? 'Solde réglé :' : 'Séjour réglé :'}</span>
          {([['arrivee', "à l'arrivée"], ['depart', 'au départ']] as const).map(([v, lib]) => (
            <button key={v} type="button" onClick={() => setSolde(v)}
              className={`px-3 py-1 rounded-full border ${solde === v ? 'bg-teal-700 text-white border-teal-700' : 'border-gray-200 text-gray-700'}`}>
              {lib}
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}
