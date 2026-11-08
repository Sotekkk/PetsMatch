// Pension — impressions : fiche à afficher sur le box (une page par
// pensionnaire) et feuille du jour par logement (tournée à cocher, signature).
// Fenêtre d'impression du navigateur. Miroir appli : lib/utils/pension_impressions.dart.
import type { SupabaseClient } from '@supabase/supabase-js';
import { alimSejourFournisParLabel, type AlimentationSejour } from '@/lib/pension-especes';
import { pensionLogementTypeLabel } from '@/lib/pension-logements';
import { momentLabel } from '@/lib/pension-protocoles';

type Ligne = Record<string, unknown>;
const t = (v: unknown) => (v == null ? '' : String(v).trim());
const esc = (s: string) => s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]!));
const fr = (d: string) => (d ? new Date(`${d.slice(0, 10)}T12:00:00`).toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'long' }) : '');
const TRANCHES: Record<string, string> = { matin: 'Matin', midi: 'Midi', apres_midi: 'Après-midi', soir: 'Soir' };
const ORDRE_TRANCHE: Record<string, number> = { matin: 0, midi: 1, apres_midi: 2, soir: 3 };

function ouvrir(titre: string, corps: string) {
  const win = window.open('', '_blank');
  if (!win) { alert('Autorisez les fenêtres pour imprimer.'); return; }
  win.document.write(`<!doctype html><html lang="fr"><head><meta charset="utf-8"><title>${esc(titre)}</title>
<style>
body{font-family:Arial,sans-serif;font-size:12px;color:#222;margin:18px}
h1{font-size:22px;margin:0 0 2px}h2{font-size:13px;margin:14px 0 6px;border-bottom:1px solid #ccc;padding-bottom:3px;color:#0C5C6C}
.page{page-break-after:always}.page:last-child{page-break-after:auto}
.tete{display:flex;gap:14px;align-items:center}.photo{width:110px;height:110px;object-fit:cover;border-radius:10px;border:1px solid #ddd}
.sub{color:#555;font-size:12px}.grille{display:grid;grid-template-columns:1fr 1fr;gap:4px 16px}
table{width:100%;border-collapse:collapse}td,th{border:1px solid #ddd;padding:5px 6px;text-align:left;vertical-align:top}th{background:#f3f6f6;font-size:11px}
.case{width:14px;height:14px;border:1.5px solid #555;border-radius:3px;display:inline-block}
.sign{margin-top:24px;display:flex;gap:40px}.sign div{flex:1;border-top:1px solid #999;padding-top:4px;font-size:11px;color:#666}
.foot{margin-top:14px;font-size:10px;color:#999}@media print{body{margin:8mm}}
</style></head><body>${corps}</body></html>`);
  win.document.close();
  setTimeout(() => win.print(), 400);
}

function alimHtml(a: AlimentationSejour | null | undefined): string {
  if (!a) return '';
  const l = [alimSejourFournisParLabel(a.fournis_par), a.foin && `Foin : ${a.foin}`, a.granules && `Granulés / croquettes : ${a.granules}`,
    a.complements && `Compléments : ${a.complements}`, a.autres && `Autres : ${a.autres}`, a.consignes && `Consignes : ${a.consignes}`].filter(Boolean) as string[];
  return l.map(x => `<div>${esc(x)}</div>`).join('');
}

/** Fiche à afficher sur le box : une page par pensionnaire. */
export async function imprimerFichesBox(sb: SupabaseClient, entreeIds: string[], pensionNom: string) {
  if (!entreeIds.length) return;
  const { data: ens } = await sb.from('pension_entrees').select('*').in('id', entreeIds);
  const entrees = (ens ?? []) as Ligne[];
  const lgIds = [...new Set(entrees.map(e => t(e.logement_id)).filter(Boolean))];
  const { data: lgs } = lgIds.length ? await sb.from('enclos_chenil').select('id, nom, type').in('id', lgIds) : { data: [] };
  const lgNom = new Map(((lgs ?? []) as Ligne[]).map(l => [t(l.id), `${t(l.nom)}${t(l.type) ? ` (${pensionLogementTypeLabel(t(l.type))})` : ''}`]));
  const { data: tch } = await sb.from('plan_taches').select('pension_entree_id, etape_id, label, tranche_horaire, plan_template_etapes(sejour_moment, jour_offset)')
    .in('pension_entree_id', entreeIds);
  const pages = entrees.map(e => {
    // Protocoles du séjour : une ligne par étape (sans « Jour x/y »).
    const vues = new Map<string, { label: string; tranche: string; moment: string }>();
    for (const x of ((tch ?? []) as Ligne[]).filter(x => t(x.pension_entree_id) === t(e.id))) {
      const k = t(x.etape_id);
      if (vues.has(k)) continue;
      const et = (x.plan_template_etapes ?? {}) as Ligne;
      vues.set(k, { label: t(x.label).replace(/ — Jour \d+\/\d+$/, ''), tranche: TRANCHES[t(x.tranche_horaire)] ?? '',
        moment: momentLabel(t(et.sejour_moment), Number(et.jour_offset) || 0) });
    }
    const protos = [...vues.values()];
    const photo = t(e.photo_url);
    return `<div class="page">
  <div class="tete">
    ${photo ? `<img class="photo" src="${esc(photo)}" alt="">` : ''}
    <div>
      <h1>${esc(t(e.animal_nom) || 'Pensionnaire')}</h1>
      <div class="sub">${esc([t(e.espece), t(e.race)].filter(Boolean).join(' · '))}${t(e.puce) ? ` · Identification ${esc(t(e.puce))}` : ''}</div>
      <div class="sub">Logement : <b>${esc(lgNom.get(t(e.logement_id)) ?? 'non attribué')}</b></div>
      <div class="sub">Du ${esc(fr(t(e.date_entree)))}${t(e.heure_arrivee_prevue) ? ` (${esc(t(e.heure_arrivee_prevue).replace(':', 'h'))})` : ''} au ${esc(fr(t(e.date_sortie_prevue)))}${t(e.heure_depart_prevue) ? ` (${esc(t(e.heure_depart_prevue).replace(':', 'h'))})` : ''}${e.essai === true ? ' · ESSAI' : ''}</div>
    </div>
  </div>
  <h2>Propriétaire</h2>
  <div class="grille"><div>${esc(t(e.proprietaire_nom) || '—')}</div><div>${esc(t(e.proprietaire_contact))}</div><div>${esc(t(e.proprietaire_email))}</div></div>
  ${alimHtml(e.alimentation_sejour as AlimentationSejour | null) ? `<h2>Alimentation</h2>${alimHtml(e.alimentation_sejour as AlimentationSejour | null)}` : ''}
  ${t(e.consignes_sejour) ? `<h2>Consignes, traitements, apports</h2><div>${esc(t(e.consignes_sejour)).replace(/\n/g, '<br>')}</div>` : ''}
  ${t(e.effets_personnels) ? `<h2>Effets personnels</h2><div>${esc(t(e.effets_personnels))}</div>` : ''}
  ${protos.length ? `<h2>Protocoles du séjour</h2><table><tr><th>Soin / tâche</th><th>Quand</th><th>Créneau</th></tr>${protos.map(p =>
    `<tr><td>${esc(p.label)}</td><td>${esc(p.moment)}</td><td>${esc(p.tranche)}</td></tr>`).join('')}</table>` : ''}
  <div class="foot">${esc(pensionNom)} · fiche imprimée le ${new Date().toLocaleDateString('fr-FR')}</div>
</div>`;
  });
  ouvrir(`Fiche box — ${entrees.map(e => t(e.animal_nom)).join(', ')}`, pages.join(''));
}

/** Feuille du jour : pensionnaires présents par logement, repas, tâches à cocher. */
export async function imprimerFeuilleJour(sb: SupabaseClient, o: { proUid: string; proProfileId: string | null; date: string; pensionNom: string }) {
  let qe = sb.from('pension_entrees').select('*').eq('pro_uid', o.proUid).eq('statut', 'en_pension')
    .lte('date_entree', o.date);
  if (o.proProfileId) qe = qe.eq('pro_profile_id', o.proProfileId);
  const { data: ens } = await qe;
  const presents = ((ens ?? []) as Ligne[]).filter(e => !t(e.date_sortie_prevue) || t(e.date_sortie_prevue).slice(0, 10) >= o.date);
  let qt = sb.from('plan_taches').select('label, tranche_horaire, animal_nom, box_id, lieu, statut')
    .eq('uid_eleveur', o.proUid).eq('profil_source', 'pension').eq('date_prevue', o.date);
  if (o.proProfileId) qt = qt.eq('eleveur_profile_id', o.proProfileId);
  const { data: tch } = await qt;
  const { data: lgs } = await sb.from('enclos_chenil').select('id, nom').eq('uid_eleveur', o.proUid).order('nom');
  const logements = ((lgs ?? []) as Ligne[]).map(l => ({ id: t(l.id), nom: t(l.nom) }));
  const taches = (tch ?? []) as Ligne[];
  const blocs: { titre: string; animaux: Ligne[]; taches: Ligne[] }[] = [];
  for (const l of [...logements, { id: '', nom: 'Sans logement attribué' }]) {
    const animaux = presents.filter(e => t(e.logement_id) === l.id);
    const tl = taches.filter(x => t(x.box_id) === l.id || (!l.id && !t(x.box_id)));
    if (animaux.length || tl.length) blocs.push({ titre: l.nom, animaux, taches: tl });
  }
  const corps = `<h1>Feuille du jour — ${esc(fr(o.date))}</h1>
<div class="sub">${esc(o.pensionNom)} · ${presents.length} pensionnaire(s)</div>
${blocs.map(b => `<h2>${esc(b.titre)}</h2>
${b.animaux.length ? `<div class="sub" style="margin-bottom:4px">${b.animaux.map(a => `<b>${esc(t(a.animal_nom))}</b>${t(a.consignes_sejour) ? ` — ${esc(t(a.consignes_sejour).split('\n')[0])}` : ''}`).join('<br>')}</div>` : ''}
${b.animaux.filter(a => alimHtml(a.alimentation_sejour as AlimentationSejour | null)).map(a => `<div class="sub"><b>Repas ${esc(t(a.animal_nom))} :</b> ${alimHtml(a.alimentation_sejour as AlimentationSejour | null).replace(/<\/?div>/g, ' ')}</div>`).join('')}
${b.taches.length ? `<table style="margin-top:6px"><tr><th style="width:22px"></th><th>Tâche</th><th>Animal</th><th style="width:80px">Créneau</th><th style="width:90px">Fait par</th></tr>
${[...b.taches].sort((x, y) => (ORDRE_TRANCHE[t(x.tranche_horaire)] ?? 9) - (ORDRE_TRANCHE[t(y.tranche_horaire)] ?? 9)).map(x =>
  `<tr><td><span class="case"></span></td><td>${esc(t(x.label))}</td><td>${esc(t(x.animal_nom))}</td><td>${esc(TRANCHES[t(x.tranche_horaire)] ?? '')}</td><td></td></tr>`).join('')}</table>` : ''}`).join('')}
<div class="sign"><div>Employé(e)</div><div>Responsable</div></div>
<div class="foot">Imprimé le ${new Date().toLocaleString('fr-FR')}</div>`;
  ouvrir(`Feuille du jour ${o.date}`, corps);
}
