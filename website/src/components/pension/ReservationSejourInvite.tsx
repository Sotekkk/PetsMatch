'use client';
// Pension — réservation d'un séjour par un visiteur SANS COMPTE (modèle du
// vétérinaire, à la Doctolib) : l'essentiel de chaque animal (nom, espèce
// accueillie, race, sexe, naissance, identification, date du dernier vaccin,
// photo du carnet si possible), engagement à apporter le carnet de santé,
// dates du séjour. À l'envoi : « Créer mon compte » / « J'ai déjà un compte »
// (ou le téléphone de la pension). La demande est mémorisée (localStorage,
// 24 h — la validation de l'e-mail peut ouvrir un autre onglet) puis reprise une fois connecté (`mode="reprise"`) : fiche de chaque
// animal créée sur le profil actif (animaux + animaux_proprietes + vaccin +
// photo du carnet dans ses documents), puis demande envoyée (route
// /api/pension/sejour). Le site seulement : dans l'appli tout le monde est
// connecté. Compte existant sans fiche : ReservationSejourModal invite à créer
// la fiche d'abord.
import Link from 'next/link';
import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { apiFetch } from '@/lib/api-fetch';
import { useAuth } from '@/lib/auth-context';
import { useActiveProfileState } from '@/hooks/useActiveProfile';
import { PENSION_ESPECES, pensionTarifKeyForEspece } from '@/lib/pension-especes';

export const CLE_SEJOUR = 'pm_sejour_en_attente';

interface AnimalInvite {
  nom: string; espece: string; race: string; sexe: '' | 'M' | 'F'; naissance: string; identification: string;
  vaccin: string; dejaVenu: boolean | null; carnet: string | null; // photo du carnet (data URL compressée)
}
interface SejourEnAttente {
  pensionProfileId: string; animaux: AnimalInvite[]; arrivee: string; depart: string; essai: string; message: string; savedAt: number;
}
interface InfosPension { nom: string; essai_requis: boolean; essai_info: string | null; especes?: string[] }

// ── Qualité des données saisies ─────────────────────────────────────────────
const AGE_MAX: Record<string, number> = { cheval: 45, ane: 50, bovin: 25, ovin: 20, caprin: 20, porcin: 20, oiseau: 80, nac: 30 };
const joursEntre = (a: string, b: string) => Math.round((new Date(`${b}T12:00:00`).getTime() - new Date(`${a}T12:00:00`).getTime()) / 86400000);
const decaler = (iso: string, jours: number) => { const d = new Date(`${iso}T12:00:00`); d.setDate(d.getDate() + jours); return d.toISOString().slice(0, 10); };
/** Puce : 15 chiffres ; tatouage : 3 à 8 lettres / chiffres. */
function identificationValide(v: string) {
  const s = v.replace(/[\s.-]/g, '').toUpperCase();
  if (/^\d+$/.test(s)) return s.length === 15;
  return /^[A-Z0-9]{3,8}$/.test(s);
}
/** Erreur bloquante pour un animal (null = correct). */
function erreurAnimal(a: AnimalInvite, auj: string): string | null {
  const nom = a.nom.trim() || 'cet animal';
  if (a.nom.trim().length < 2) return 'Indiquez le nom de chaque animal (2 lettres au moins).';
  if (!a.espece) return `Choisissez l'espèce de ${nom}.`;
  if (!a.sexe) return `Indiquez le sexe de ${nom}.`;
  if (!a.naissance) return `Indiquez la date de naissance de ${nom} (approximative si besoin).`;
  if (a.naissance > auj) return `La date de naissance de ${nom} est dans le futur.`;
  const ageMax = AGE_MAX[a.espece] ?? 30;
  if (joursEntre(a.naissance, auj) > ageMax * 366) return `Date de naissance de ${nom} improbable (plus de ${ageMax} ans) : vérifiez l'année.`;
  if (['chien', 'chat'].includes(a.espece) && !a.identification.trim()) return `Le numéro d'identification de ${nom} est obligatoire (puce ou tatouage).`;
  if (a.identification.trim() && !identificationValide(a.identification)) return `Numéro d'identification de ${nom} invalide : une puce compte 15 chiffres, un tatouage 3 à 8 caractères.`;
  if (!a.vaccin) return `Indiquez la date du dernier vaccin de ${nom} (voir le carnet de santé).`;
  if (a.vaccin > auj) return `La date du dernier vaccin de ${nom} est dans le futur.`;
  if (a.vaccin < a.naissance) return `Le dernier vaccin de ${nom} est daté d'avant sa naissance : vérifiez les dates.`;
  if (a.dejaVenu === null) return `Indiquez si ${nom} est déjà venu dans cette pension.`;
  return null;
}

const vide = (): AnimalInvite => ({ nom: '', espece: '', race: '', sexe: '', naissance: '', identification: '', vaccin: '', dejaVenu: null, carnet: null });

/** Photo du carnet réduite (1600 px, JPEG) pour tenir dans le stockage du navigateur. */
async function compresser(file: File): Promise<string> {
  const url = URL.createObjectURL(file);
  try {
    const img = await new Promise<HTMLImageElement>((ok, ko) => { const i = new Image(); i.onload = () => ok(i); i.onerror = ko; i.src = url; });
    const r = Math.min(1, 1600 / Math.max(img.width, img.height));
    const c = document.createElement('canvas');
    c.width = Math.round(img.width * r); c.height = Math.round(img.height * r);
    c.getContext('2d')?.drawImage(img, 0, 0, c.width, c.height);
    return c.toDataURL('image/jpeg', 0.72);
  } finally { URL.revokeObjectURL(url); }
}

export default function ReservationSejourInvite({ mode, pensionProfileId, pensionNom, couleur, telephone, suite, onClose }: {
  mode: 'invite' | 'reprise'; pensionProfileId: string; pensionNom: string; couleur: string;
  telephone?: string | null; /** Chemin de retour après inscription / connexion. */ suite: string; onClose: () => void;
}) {
  const { user } = useAuth();
  const profil = useActiveProfileState();
  const [infos, setInfos] = useState<InfosPension | null>(null);
  const [animaux, setAnimaux] = useState<AnimalInvite[]>([vide()]);
  const [arrivee, setArrivee] = useState('');
  const [depart, setDepart] = useState('');
  const [essai, setEssai] = useState('');
  const [message, setMessage] = useState('');
  const [carnetPromis, setCarnetPromis] = useState(false);
  const [complet, setComplet] = useState<string | null>(null);
  const [etape, setEtape] = useState<'form' | 'compte' | 'envoi' | 'ok'>('form');
  const [erreur, setErreur] = useState('');
  const [aujourdhui, setAujourdhui] = useState('');

  // Reprise après connexion : demande mémorisée.
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setAujourdhui(new Date().toISOString().slice(0, 10));
    if (mode !== 'reprise') return;
    let p: SejourEnAttente | null = null;
    try { p = JSON.parse(localStorage.getItem(CLE_SEJOUR) ?? 'null'); } catch { p = null; }
    if (!p || p.pensionProfileId !== pensionProfileId || Date.now() - p.savedAt > 24 * 3600_000) {
      setErreur('Votre demande n\'a pas été retrouvée : merci de la refaire.');
      return;
    }
    setAnimaux(p.animaux); setArrivee(p.arrivee); setDepart(p.depart); setEssai(p.essai); setMessage(p.message); setCarnetPromis(true);
  }, [mode, pensionProfileId]);

  const especesCles = animaux.map(a => a.espece).filter(Boolean);
  const datesOk = !!arrivee && !!depart && depart >= arrivee;
  useEffect(() => {
    const qs = new URLSearchParams({ pensionProfileId });
    if (datesOk && especesCles.length) { qs.set('arrivee', arrivee); qs.set('depart', depart); qs.set('nb', String(especesCles.length)); qs.set('especes', especesCles.join(',')); }
    apiFetch(`/api/pension/sejour?${qs.toString()}`, { cache: 'no-store' })
      .then(r => (r.ok ? r.json() : null))
      .then(j => { if (j) { setInfos(j.pension as InfosPension); setComplet((j.dispo?.message as string | null | undefined) ?? null); } })
      .catch(() => {});
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pensionProfileId, arrivee, depart, datesOk, especesCles.join(',')]);

  // Espèces proposées : celles accueillies par la pension (sinon toutes).
  const especesProposees = (() => {
    const acc = (infos?.especes ?? []).map(e => pensionTarifKeyForEspece(e) ?? e.toLowerCase());
    const liste = acc.length ? PENSION_ESPECES.filter(e => acc.includes(e.key)) : PENSION_ESPECES;
    return liste.length ? liste : PENSION_ESPECES;
  })();
  const essaiRequis = !!infos?.essai_requis && animaux.some(a => a.dejaVenu === false);
  const maj = (i: number, champ: Partial<AnimalInvite>) => setAnimaux(l => l.map((a, j) => (j === i ? { ...a, ...champ } : a)));

  function verifier(): string | null {
    const auj = new Date().toISOString().slice(0, 10);
    for (const a of animaux) { const e = erreurAnimal(a, auj); if (e) return e; }
    if (!arrivee || !depart) return 'Choisissez les dates du séjour.';
    if (arrivee < auj) return 'La date d\'arrivée est passée.';
    if (arrivee > decaler(auj, 365)) return 'La date d\'arrivée est à plus d\'un an : vérifiez l\'année.';
    if (depart < arrivee) return 'La date de départ doit suivre l\'arrivée.';
    if (joursEntre(arrivee, depart) > 180) return 'Séjour de plus de 6 mois : vérifiez les dates ou contactez directement la pension.';
    if (essaiRequis && (!essai || essai >= arrivee || essai < auj)) return 'Choisissez une date d\'essai entre aujourd\'hui et la veille de l\'arrivée.';
    if (!carnetPromis) return 'Cochez l\'engagement à apporter le carnet de santé.';
    if (complet) return complet;
    return null;
  }

  function memoriser() {
    const e = verifier();
    if (e) { setErreur(e); return; }
    setErreur('');
    const donnees: SejourEnAttente = { pensionProfileId, animaux, arrivee, depart, essai: essaiRequis ? essai : '', message, savedAt: Date.now() };
    try {
      localStorage.setItem(CLE_SEJOUR, JSON.stringify(donnees));
    } catch {
      // Photos trop lourdes pour le navigateur : la demande part sans elles.
      try { localStorage.setItem(CLE_SEJOUR, JSON.stringify({ ...donnees, animaux: animaux.map(a => ({ ...a, carnet: null })) })); }
      catch { setErreur('Votre navigateur ne permet pas de mémoriser la demande : connectez-vous d\'abord.'); return; }
    }
    setEtape('compte');
  }

  /** Une fois connecté : fiches créées sur le profil actif, puis demande envoyée. */
  async function finaliser() {
    if (!user) return;
    const e = verifier();
    if (e) { setErreur(e); return; }
    setErreur(''); setEtape('envoi');
    const pid = profil.id || null;
    const ids: string[] = [];
    try {
      for (const [i, a] of animaux.entries()) {
        const id = `animal_${user.uid}_${Date.now()}_${i}`;
        const { error } = await supabase.from('animaux').insert([{
          id, nom: a.nom.trim(), espece: a.espece, race: a.race.trim() || null, sexe: a.sexe || null,
          date_naissance: a.naissance || null, identification: a.identification.replace(/[\s.-]/g, '').toUpperCase() || null,
          statut: 'present', uid_eleveur: user.uid, uid_proprietaire: user.uid, provenance_qualite: 'achat',
          ...(pid ? { profile_id: pid } : {}), updated_at: new Date().toISOString(),
        }]);
        if (error) throw new Error(error.message);
        await supabase.from('animaux_proprietes').upsert({
          animal_id: id, uid_proprio: user.uid, date_debut: a.naissance || new Date().toISOString().slice(0, 10),
          ...(pid ? { profile_id_proprio: pid } : {}),
        }, { onConflict: 'animal_id,uid_proprio' });
        // Dernier vaccin déclaré → carnet de santé (à confirmer avec le carnet papier).
        if (a.vaccin) {
          await supabase.from('vaccinations').insert({ id: `${Date.now()}_${id}`, animal_id: id, vaccin: 'Vaccin (date déclarée à la réservation)', date: a.vaccin, source: 'owner' });
        }
        // Photo du carnet → documents de la fiche.
        if (a.carnet) {
          try {
            const blob = await (await fetch(a.carnet)).blob();
            const path = `documents/${user.uid}/${id}/${Date.now()}_carnet_sante.jpg`;
            const { error: up } = await supabase.storage.from('media').upload(path, blob, { contentType: 'image/jpeg' });
            if (!up) {
              const url = supabase.storage.from('media').getPublicUrl(path).data.publicUrl;
              await supabase.from('animaux').update({ documents: [{ nom: 'Carnet de santé', url, type: 'image/jpeg', categorie: 'autre' }] }).eq('id', id);
            }
          } catch { /* photo non envoyée : le carnet papier reste demandé */ }
        }
        ids.push(id);
      }
      const consignes = [message.trim(), 'Carnet de santé : le client s\'engage à l\'apporter à l\'arrivée.'].filter(Boolean).join('\n');
      const r = await apiFetch('/api/pension/sejour', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          pensionProfileId, animalIds: ids, animalId: ids[0], dateArrivee: arrivee, dateDepart: depart,
          dejaVenus: Object.fromEntries(animaux.map((a, i) => [ids[i], !!a.dejaVenu])),
          ...(essaiRequis ? { essaiDate: essai } : {}), message: consignes, ...(pid ? { profileId: pid } : {}),
        }),
      });
      const j = await r.json().catch(() => ({})) as { error?: string };
      if (!r.ok) throw new Error(j.error ?? 'Demande impossible');
      try { localStorage.removeItem(CLE_SEJOUR); } catch { /* rien */ }
      setEtape('ok');
    } catch (err) {
      setEtape('form');
      setErreur(`${err instanceof Error ? err.message : String(err)}${ids.length ? ' Les fiches déjà créées sont dans « Mes animaux » : vous pouvez réserver depuis la fiche de la pension.' : ''}`);
    }
  }

  const champ = 'w-full border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white';
  const pastille = (actif: boolean) => (actif ? { background: couleur, color: '#fff', borderColor: couleur } : { borderColor: '#E5E7EB', color: '#1F2A2E' });
  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/40 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl w-full max-w-md p-5 max-h-[92vh] overflow-y-auto space-y-3" onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
        <div>
          <p className="font-bold text-lg text-[#1F2A2E]">{mode === 'reprise' ? 'Finaliser la demande de séjour' : 'Réserver un séjour'}</p>
          <p className="text-sm text-gray-500">{pensionNom}</p>
        </div>

        {etape === 'ok' ? (
          <>
            <p className="text-sm text-gray-700">Demande envoyée. Les fiches de vos animaux sont créées dans « Mes animaux » : complétez-les (alimentation, santé) pour la pension. {pensionNom} vous préviendra dès que le séjour sera accepté.</p>
            <a href="/mes-sejours" className="block text-center text-sm font-semibold" style={{ color: couleur }}>Voir mes demandes</a>
            <button onClick={onClose} className="w-full py-2.5 rounded-xl text-sm font-semibold text-white" style={{ background: couleur }}>Fermer</button>
          </>
        ) : etape === 'compte' && !user ? (
          <div className="rounded-2xl border border-gray-200 p-4 space-y-3">
            <p className="font-bold text-[#1E2025]">Dernière étape : identifiez-vous</p>
            <p className="text-xs text-gray-500">Votre demande est mémorisée. Créez votre compte PetsMatch gratuit (1 minute) ou connectez-vous : la fiche de vos animaux sera créée et la demande envoyée à la pension.</p>
            <Link href={`/inscription?suite=${encodeURIComponent(suite)}`} className="block w-full text-center py-3 rounded-xl text-white font-bold text-sm" style={{ backgroundColor: couleur }}>Créer mon compte</Link>
            <Link href={`/connexion?suite=${encodeURIComponent(suite)}`} className="block w-full text-center py-3 rounded-xl border font-semibold text-sm" style={{ borderColor: couleur, color: couleur }}>J&apos;ai déjà un compte</Link>
            {telephone && (
              <p className="text-xs text-gray-500 text-center pt-1">Vous préférez ne pas créer de compte ? Appelez directement{' '}
                <a href={`tel:${telephone.replace(/[^0-9+]/g, '')}`} className="font-semibold underline" style={{ color: couleur }}>le {telephone}</a>.</p>
            )}
            <button onClick={() => setEtape('form')} className="w-full text-sm font-semibold text-gray-500">Modifier</button>
          </div>
        ) : (
          <>
            {animaux.map((a, i) => (
              <div key={i} className="border border-gray-200 rounded-xl p-3 space-y-2">
                <div className="flex items-center justify-between">
                  <p className="text-xs font-bold text-gray-600">Animal {animaux.length > 1 ? i + 1 : ''}</p>
                  {animaux.length > 1 && <button type="button" onClick={() => setAnimaux(l => l.filter((_, j) => j !== i))} className="text-xs font-semibold text-[#B3261E]">Retirer</button>}
                </div>
                <div className="grid grid-cols-2 gap-2">
                  <input value={a.nom} onChange={e => maj(i, { nom: e.target.value })} placeholder="Nom *" maxLength={40} className={champ} />
                  <select value={a.espece} onChange={e => maj(i, { espece: e.target.value })} className={champ}>
                    <option value="">Espèce *</option>
                    {especesProposees.map(e => <option key={e.key} value={e.key}>{e.label}</option>)}
                  </select>
                  <input value={a.race} onChange={e => maj(i, { race: e.target.value })} placeholder="Race" maxLength={60} className={champ} />
                  <select value={a.sexe} onChange={e => maj(i, { sexe: e.target.value as AnimalInvite['sexe'] })} className={champ}>
                    <option value="">Sexe *</option><option value="M">Mâle</option><option value="F">Femelle</option>
                  </select>
                  <div><label className="block text-[11px] text-gray-500 mb-0.5">Date de naissance *</label>
                    <input type="date" min={aujourdhui ? decaler(aujourdhui, -366 * (AGE_MAX[a.espece] ?? 30)) : undefined} max={aujourdhui} value={a.naissance} onChange={e => maj(i, { naissance: e.target.value })} className={champ} /></div>
                  <div><label className="block text-[11px] text-gray-500 mb-0.5">Dernier vaccin *</label>
                    <input type="date" min={a.naissance || undefined} max={aujourdhui} value={a.vaccin} onChange={e => maj(i, { vaccin: e.target.value })} className={champ} /></div>
                </div>
                {/* Vaccin de plus d'un an : rappel sans doute dépassé (avertissement, non bloquant). */}
                {a.vaccin && aujourdhui && joursEntre(a.vaccin, aujourdhui) > 365 && (
                  <p className="text-xs font-semibold text-[#B45309]">Dernier vaccin il y a plus d&apos;un an : le rappel est probablement à faire avant le séjour, la pension peut le demander.</p>
                )}
                <input value={a.identification} onChange={e => maj(i, { identification: e.target.value })} inputMode="text" maxLength={20}
                  placeholder={`N° d'identification${['chien', 'chat'].includes(a.espece) ? ' *' : ''} (puce 15 chiffres ou tatouage)`} className={champ} />
                <div>
                  <label className="block text-[11px] text-gray-500 mb-0.5">Photo du carnet de santé (page des vaccins, si possible)</label>
                  {a.carnet ? (
                    <div className="flex items-center gap-2">
                      {/* eslint-disable-next-line @next/next/no-img-element */}
                      <img src={a.carnet} alt="Carnet de santé" className="w-14 h-14 rounded-lg object-cover" />
                      <button type="button" onClick={() => maj(i, { carnet: null })} className="text-xs font-semibold text-gray-500">Retirer la photo</button>
                    </div>
                  ) : (
                    <input type="file" accept="image/*" onChange={async e => { const f = e.target.files?.[0]; if (f) maj(i, { carnet: await compresser(f).catch(() => null) }); e.target.value = ''; }}
                      className="block w-full text-xs text-gray-600" />
                  )}
                </div>
                <div>
                  <p className="text-[11px] text-gray-500 mb-1">{a.nom.trim() || 'Cet animal'} est-il déjà venu dans cette pension ?</p>
                  <div className="flex flex-wrap gap-2">
                    {([[false, 'Non, nouveau pensionnaire'], [true, 'Oui, il est déjà venu']] as const).map(([v, lib]) => (
                      <button key={lib} type="button" onClick={() => maj(i, { dejaVenu: v })} className="px-3 py-1.5 rounded-full text-xs border" style={pastille(a.dejaVenu === v)}>{lib}</button>
                    ))}
                  </div>
                </div>
              </div>
            ))}
            <button type="button" onClick={() => setAnimaux(l => [...l, vide()])} className="text-sm font-semibold" style={{ color: couleur }}>+ Un autre animal</button>

            <div className="grid grid-cols-2 gap-2">
              <div><label className="block text-xs font-semibold text-gray-600 mb-1">Arrivée</label>
                <input type="date" min={aujourdhui} max={aujourdhui ? decaler(aujourdhui, 365) : undefined} value={arrivee} onChange={e => setArrivee(e.target.value)} className={champ} /></div>
              <div><label className="block text-xs font-semibold text-gray-600 mb-1">Départ</label>
                <input type="date" min={arrivee || aujourdhui} value={depart} onChange={e => setDepart(e.target.value)} className={champ} /></div>
            </div>
            {complet && <p className="text-sm font-semibold text-[#B3261E]">{complet} Choisissez d&apos;autres dates{animaux.length > 1 ? ' ou moins d\'animaux' : ''}.</p>}
            {essaiRequis && (
              <div>
                <label className="block text-xs font-semibold text-gray-600 mb-1">Essai avant le premier séjour</label>
                <p className="text-xs text-gray-500 mb-1">{infos?.essai_info?.trim() || 'Cette pension demande une journée d\'essai avant le premier séjour de votre animal.'}</p>
                <input type="date" min={aujourdhui} max={arrivee || undefined} value={essai} onChange={e => setEssai(e.target.value)} className={champ} />
              </div>
            )}
            <div>
              <label className="block text-xs font-semibold text-gray-600 mb-1">Consignes pour le séjour (facultatif)</label>
              <textarea value={message} onChange={e => setMessage(e.target.value)} rows={2} placeholder="Traitement à donner, habitudes, horaires d'arrivée…" className={`${champ} resize-none`} />
            </div>
            <label className="flex items-start gap-2 text-sm text-[#1F2A2E]">
              <input type="checkbox" checked={carnetPromis} onChange={e => setCarnetPromis(e.target.checked)} className="mt-0.5 w-4 h-4" style={{ accentColor: couleur }} />
              <span>J&apos;apporterai le carnet de santé de {animaux.length > 1 ? 'chaque animal' : 'mon animal'} à l&apos;arrivée (vaccins à jour).</span>
            </label>
            {erreur && <p className="text-sm text-[#B3261E]">{erreur}</p>}
            {mode === 'reprise' ? (
              <button onClick={finaliser} disabled={etape === 'envoi' || !user || !profil.loaded} className="w-full py-2.5 rounded-xl text-sm font-semibold text-white disabled:opacity-50" style={{ background: couleur }}>
                {etape === 'envoi' ? 'Envoi…' : 'Créer les fiches et envoyer la demande'}
              </button>
            ) : (
              <button onClick={memoriser} className="w-full py-2.5 rounded-xl text-sm font-semibold text-white" style={{ background: couleur }}>Continuer</button>
            )}
          </>
        )}
      </div>
    </div>
  );
}
