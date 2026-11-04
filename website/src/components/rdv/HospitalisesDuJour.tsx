'use client';

// Hospitalisés du jour (vétérinaire) : interventions du jour et animaux encore
// présents à la clinique — état (attendu, déposé, au bloc, en réveil, prêt à
// partir), récupération prévue, actions rapides (déposé, prévenir réveillé /
// prêt, récupéré à tout moment après le dépôt : l'animal quitte la liste et le
// RDV passe dans l'historique, trigger trg_rdv_sortie_statut) et dossier de la
// séance. Vétérinaire ou ASV.
// Miroir appli : lib/widgets/pro/hospitalises_du_jour.dart.
import { useCallback, useEffect, useState } from 'react';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { ETATS_HOSPIT, etatHospit, hospitalisesDuJour, libelleIntervention, messageIntervention, type Hospitalise } from '@/lib/intervention';

const TEAL = '#0C5C6C';
const hm = (d: string | null) => d ? new Date(d).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }).replace(':', 'h') : '';

export default function HospitalisesDuJour({ profileId, version, onOuvrirDossier, masquerSiVide = true, onChange }: {
  profileId: string; version?: unknown;
  /** Après une action (animal récupéré → RDV terminé) : la page recharge ses listes. */
  onChange?: () => void;
  /** Absent : lien vers Gérer mes RDV (dossier ouvert). */
  onOuvrirDossier?: (rdvId: string) => void;
  masquerSiVide?: boolean;
}) {
  const [liste, setListe] = useState<Hospitalise[] | null>(null);
  const [enCours, setEnCours] = useState('');
  const [message, setMessage] = useState('');
  const [, setTick] = useState(0);

  const charger = useCallback(() => { hospitalisesDuJour(profileId).then(setListe).catch(() => setListe([])); }, [profileId]);
  useEffect(() => { charger(); }, [charger, version]);
  // L'état « au bloc » dépend de l'heure : rafraîchi chaque minute.
  useEffect(() => { const t = setInterval(() => setTick(x => x + 1), 60000); return () => clearInterval(t); }, []);

  if (!liste || (masquerSiVide && liste.length === 0)) return null;

  const agir = async (cle: string, f: () => Promise<string | void>) => {
    setEnCours(cle); setMessage('');
    try { const m = await f(); if (m) setMessage(m); charger(); onChange?.(); } finally { setEnCours(''); }
  };
  const maj = (id: string, champs: Record<string, string | null>) => agir(`${id}:${Object.keys(champs)[0]}`, async () => {
    const { error } = await supabase.from('rdv').update(champs).eq('id', id);
    if (error) return `Non enregistré : ${error.message}`;
    if (champs.sortie_le) return 'Animal récupéré : le RDV est dans l’historique.';
  });
  const btn = (cle: string, label: string, f: () => void, plein = false) => (
    <button key={cle} type="button" disabled={!!enCours} onClick={f}
      className="text-xs font-semibold px-2.5 py-1 rounded-lg border whitespace-nowrap disabled:opacity-50"
      style={plein ? { background: TEAL, borderColor: TEAL, color: 'white' } : { borderColor: TEAL, color: TEAL }}>
      {enCours === cle ? '…' : label}
    </button>
  );
  const presents = liste.filter(h => { const e = etatHospit(h); return e !== 'attendu' && e !== 'rentre'; }).length;

  return (
    <section className="bg-white rounded-2xl border border-[#E5E8E6] p-4">
      <div className="flex items-center gap-2 mb-2">
        <h2 className="flex-1 font-bold text-base text-[#1E2025]">Hospitalisés du jour</h2>
        <span className="text-xs font-semibold text-gray-500">{presents} présent{presents > 1 ? 's' : ''} · {liste.length} intervention{liste.length > 1 ? 's' : ''}</span>
      </div>
      {message && <p className="text-xs mb-2 rounded-lg px-2 py-1.5 bg-[#E6F2F3]" style={{ color: TEAL }}>{message}</p>}
      {liste.length === 0 ? <p className="text-sm text-gray-400 text-center py-6">Aucune intervention aujourd&apos;hui.</p> : (
        <div>
          {liste.map(h => {
            const e = etatHospit(h);
            const st = ETATS_HOSPIT[e];
            const jourAvant = new Date(h.date_heure).toDateString() !== new Date().toDateString();
            return (
              <div key={h.id} className="py-2.5 border-b border-[#F0F1EF] last:border-0">
                <div className="flex items-center gap-3">
                  {h.animalPhoto
                    // eslint-disable-next-line @next/next/no-img-element
                    ? <img src={h.animalPhoto} alt="" className="w-10 h-10 rounded-full object-cover flex-shrink-0" />
                    : <div className="w-10 h-10 rounded-full bg-[#E6F2F3] flex-shrink-0" />}
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-bold text-[#1E2025] truncate">{h.animalNom} <span className="font-normal text-gray-500">· {h.motif || libelleIntervention(h.intervention_type)}</span></p>
                    <p className="text-xs text-gray-500 truncate">
                      {[h.clientNom, jourAvant ? `depuis le ${new Date(h.date_heure).toLocaleDateString('fr-FR')}` : `dépôt ${hm(h.date_heure)}`,
                        h.bloc_debut ? `bloc ${hm(h.bloc_debut)}` : '', h.heure_recuperation && !h.sortie_le ? `récup. ${new Date(h.heure_recuperation).toDateString() !== new Date().toDateString()
                          ? `${new Date(h.heure_recuperation).toLocaleDateString('fr-FR', { weekday: 'short', day: 'numeric', month: 'short' })} ` : ''}${hm(h.heure_recuperation)}` : ''].filter(Boolean).join(' · ')}
                    </p>
                  </div>
                  <span className="text-[11px] font-bold px-2 py-0.5 rounded-full whitespace-nowrap" style={{ color: st.fg, background: st.bg }}>{st.label}{h.sortie_le ? ` à ${hm(h.sortie_le)}` : ''}</span>
                </div>
                <div className="flex flex-wrap gap-1.5 mt-1.5 pl-[52px]">
                  {e === 'attendu' && btn(`${h.id}:admis_le`, 'Animal déposé', () => maj(h.id, { admis_le: new Date().toISOString() }), true)}
                  {(e === 'depose' || e === 'bloc') && btn(`${h.id}:reveille`, 'Réveillé — prévenir', () => agir(`${h.id}:reveille`, () => messageIntervention(h.id, 'reveille')))}
                  {(e === 'depose' || e === 'bloc' || e === 'reveil') && btn(`${h.id}:pret`, 'Prêt — prévenir', () => agir(`${h.id}:pret`, () => messageIntervention(h.id, 'pret')), e === 'reveil')}
                  {e !== 'attendu' && e !== 'rentre' && btn(`${h.id}:sortie_le`, 'Récupéré', () => maj(h.id, { sortie_le: new Date().toISOString() }), e === 'pret')}
                  {h.client_telephone_manuel && !h.client_uid && (
                    <a href={`tel:${h.client_telephone_manuel}`} className="text-xs font-semibold px-2.5 py-1 rounded-lg border" style={{ borderColor: TEAL, color: TEAL }}>Appeler</a>
                  )}
                  {onOuvrirDossier
                    ? btn(`${h.id}:dossier`, 'Dossier', () => onOuvrirDossier(h.id))
                    : <Link href={`/mes-rdv?rdv=${encodeURIComponent(h.id)}&dossier=1`} className="text-xs font-semibold px-2.5 py-1 rounded-lg border" style={{ borderColor: TEAL, color: TEAL }}>Dossier</Link>}
                </div>
              </div>
            );
          })}
        </div>
      )}
    </section>
  );
}
