'use client';
// Pet-sitting — après l'acceptation d'une demande (un passage ou une série) :
// contrat de garde pré-rempli à faire signer, facture au choix (maintenant /
// acompte / après la prestation), enregistrement de la clé si le client la
// remet. Miroir appli : lib/pages/pro/garde_acceptation.dart.
// Scopé au profil pet-sitter actif (pro_profile_id) — jamais l'uid seul.
import { useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { supabase } from '@/lib/supabase';
import { usePlanGarde } from '@/lib/use-plan';
import { gardeTarif } from '@/lib/garde-facturation';
import { accesLogementLabel } from '@/lib/garde-labels';

const TEAL = '#0C5C6C';

export interface RdvAccepte {
  id: string; pro_uid: string; client_uid: string; client_profile_id?: string | null;
  animal_id?: string | null; date_heure: string; motif?: string | null; lieu?: string | null;
  notes_client?: string | null; acces_logement?: string | null; forfait_id?: string | null;
  animaux_ids?: unknown[] | null; clientName?: string; animalNom?: string;
}
type Ligne = { description: string; quantite: number; prixUnitaire: number; tva: number };

const eur = (v: number) => `${v.toFixed(2).replace('.', ',')} €`;
function periode(rdvs: RdvAccepte[]) {
  const d = rdvs.map(r => new Date(r.date_heure)).sort((a, b) => a.getTime() - b.getTime());
  if (!d.length) return '';
  const f = (x: Date) => x.toLocaleDateString('fr-FR');
  return d.length === 1 ? `le ${f(d[0])}` : `du ${f(d[0])} au ${f(d[d.length - 1])}`;
}

export default function ApresAcceptationGardeModal({ rdvs, proProfileId, onClose }: {
  rdvs: RdvAccepte[]; proProfileId: string | null; onClose: () => void;
}) {
  const router = useRouter();
  const { plan } = usePlanGarde();
  const premium = plan === 'premium';
  const first = rdvs[0];
  const [lignes, setLignes] = useState<Ligne[]>([]);
  const [total, setTotal] = useState(0);
  const [busy, setBusy] = useState('');
  const [msg, setMsg] = useState('');

  // Chiffrage : forfait choisi, sinon tarif × passages (+ animal supplémentaire).
  useEffect(() => {
    let alive = true;
    (async () => {
      const n = rdvs.length;
      const noms = first.animalNom ? ` — ${first.animalNom}` : '';
      if (first.forfait_id) {
        const { data: f } = await supabase.from('forfaits_garde').select('nom, prix').eq('id', first.forfait_id).maybeSingle();
        const prix = Number(f?.prix) || 0;
        if (f && prix > 0) {
          if (!alive) return;
          setLignes([{ description: `Forfait ${f.nom}${noms} (${periode(rdvs)})`, quantite: 1, prixUnitaire: prix, tva: 20 }]);
          setTotal(prix);
          return;
        }
      }
      const prix = await gardeTarif(first.pro_uid, proProfileId, { ...first, animal_id: first.animal_id ?? null });
      const l: Ligne[] = [{ description: `${first.motif ?? 'Prestation'}${noms} (${periode(rdvs)})`, quantite: n, prixUnitaire: prix, tva: 20 }];
      let t = prix * n;
      const animaux = Array.isArray(first.animaux_ids) && first.animaux_ids.length > 0 ? first.animaux_ids.length : 1;
      if (animaux > 1 && proProfileId) {
        const { data: p } = await supabase.from('user_profiles_complet').select('tarifs_garde').eq('id', proProfileId).maybeSingle();
        const supp = Number((p?.tarifs_garde as Record<string, number> | null)?.animal_supplementaire) || 0;
        if (supp > 0) {
          l.push({ description: 'Animal supplémentaire', quantite: (animaux - 1) * n, prixUnitaire: supp, tva: 20 });
          t += supp * (animaux - 1) * n;
        }
      }
      if (!alive) return;
      setLignes(l); setTotal(t);
    })();
    return () => { alive = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function contrat() {
    if (!proProfileId) return;
    setBusy('contrat'); setMsg('');
    try {
      const acces = accesLogementLabel(first.acces_logement);
      const details: Record<string, unknown> = {
        prestation: [first.motif ?? 'Prestation', rdvs.length > 1 ? `${rdvs.length} passages ${periode(rdvs)}` : ''].filter(Boolean).join(' — '),
        date_prestation: first.date_heure.slice(0, 10),
        ...(total > 0 ? { tarif: total.toFixed(2) } : {}),
        notes: [
          first.lieu ? `Lieu de prise en charge : ${first.lieu}` : '',
          acces ? `Accès au logement : ${acces}` : '',
          first.notes_client?.trim() ? `Consignes : ${first.notes_client.trim()}` : '',
        ].filter(Boolean).join('\n'),
        ...(first.lieu ? { client_adresse: first.lieu } : {}),
      };
      const noms = first.animalNom ? first.animalNom.split(' + ') : [];
      const { data: ex } = await supabase.from('documents_animaux').select('id, token, statut, metadata')
        .eq('uid_eleveur', first.pro_uid).eq('pro_profile_id', proProfileId)
        .eq('type', 'contrat_garde').eq('metadata->>client_uid', first.client_uid)
        .order('created_at', { ascending: false }).limit(1).maybeSingle();
      let token = (ex?.token as string | undefined) ?? null;
      if (!token || String(ex?.statut ?? '').startsWith('signe')) {
        const { data, error } = await supabase.from('documents_animaux').insert({
          uid_eleveur: first.pro_uid, pro_profile_id: proProfileId, type: 'contrat_garde',
          titre: `Contrat de prestation — ${first.clientName ?? 'Client'}`, statut: 'en_attente',
          ...(first.animal_id ? { animal_id: first.animal_id } : {}),
          metadata: {
            client_nom: first.clientName ?? 'Client', client_uid: first.client_uid,
            ...(first.client_profile_id ? { client_profile_id: first.client_profile_id } : {}),
            ...(noms.length ? { animal_nom: first.animalNom, animal_noms: noms } : {}),
            ...details,
          },
        }).select('token').single();
        if (error) throw error;
        token = (data?.token as string | null) ?? null;
      } else {
        const meta = { ...((ex!.metadata as Record<string, unknown>) ?? {}), ...details };
        const l = new Set([...(((meta.animal_noms as string[] | undefined) ?? [])), ...noms]);
        if (l.size) meta.animal_noms = [...l];
        await supabase.from('documents_animaux').update({ metadata: meta }).eq('id', ex!.id);
      }
      if (token) window.open(`/signer-contrat/${token}`, '_blank');
    } catch (e) {
      setMsg(`Contrat : ${e instanceof Error ? e.message : String(e)}`);
    } finally { setBusy(''); }
  }

  function facturer(acompte: boolean) {
    const l: Ligne[] = acompte
      ? [{ description: `Acompte — ${first.motif ?? 'Prestation'} (${periode(rdvs)})`, quantite: 1, prixUnitaire: Math.round(total * 30) / 100, tva: 20 }]
      : lignes;
    const prefill = {
      nomClient: first.clientName ?? '',
      lignes: l,
      ...(acompte ? { typeFacture: 'acompte' } : { sourceRdvId: first.id, sourceRdvIds: rdvs.map(r => r.id) }),
      sourceAnimalId: first.animal_id ?? undefined,
      clientUid: first.client_uid,
      clientProfileId: first.client_profile_id ?? undefined,
    };
    try { sessionStorage.setItem('pm_facture_prefill', JSON.stringify(prefill)); } catch { /* ignore */ }
    onClose();
    router.push('/elevage/facturation');
  }

  async function cle() {
    const desc = window.prompt('Description de la clé (aucun code d\'accès ici)', 'Clé du logement');
    if (desc === null || !proProfileId) return;
    setBusy('cle');
    const { error } = await supabase.from('cles_clients').insert({
      pro_uid: first.pro_uid, pro_profile_id: proProfileId,
      ...(first.animal_id ? { animal_id: first.animal_id } : {}),
      owner_uid: first.client_uid,
      ...(first.client_profile_id ? { owner_profile_id: first.client_profile_id } : {}),
      description: desc.trim() || 'Clé du logement',
      date_recuperation: new Date().toISOString().slice(0, 10),
    });
    setBusy('');
    setMsg(error ? `Clé : ${error.message}` : 'Clé enregistrée dans « Gestion des clés ».');
  }

  const tuile = (icone: string, titre: string, sous: string, onClick: () => void, cle?: string) => (
    <button type="button" onClick={onClick} disabled={!!busy}
      className="w-full flex items-center gap-3 text-left py-2.5 px-1 rounded-xl hover:bg-gray-50 disabled:opacity-50">
      <span className="w-9 h-9 rounded-full flex items-center justify-center text-base flex-shrink-0" style={{ background: `${TEAL}18` }}>{icone}</span>
      <span className="flex-1 min-w-0">
        <span className="block text-sm font-bold text-[#1E2025]">{busy === cle && cle ? '…' : titre}</span>
        <span className="block text-xs text-gray-500">{sous}</span>
      </span>
      <span className="text-gray-400">›</span>
    </button>
  );
  const verrou = (
    <p className="text-xs text-amber-700 bg-amber-50 rounded-lg px-3 py-2">
      Contrat et facturation inclus dans la formule Premium. <Link href="/garde/abonnement" className="underline font-semibold">Voir les plans</Link>
    </p>
  );

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-3xl sm:rounded-2xl shadow-2xl w-full max-w-md p-5 space-y-2 max-h-[90vh] overflow-y-auto"
        onClick={e => e.stopPropagation()} style={{ fontFamily: 'Galey, sans-serif' }}>
        <h2 className="font-extrabold text-lg" style={{ color: TEAL }}>Demande acceptée ✓</h2>
        <p className="text-xs text-gray-600">
          {[first.animalNom, first.clientName, rdvs.length > 1 ? `${rdvs.length} passages` : '', total > 0 ? eur(total) : ''].filter(Boolean).join(' · ')}
        </p>
        <p className="text-xs font-bold text-gray-400 uppercase tracking-wide pt-2">Contrat</p>
        {premium ? tuile('✍️', 'Envoyer le contrat de garde', 'Pré-rempli : prestation, dates, lieu, accès, tarif', contrat, 'contrat') : verrou}
        <p className="text-xs font-bold text-gray-400 uppercase tracking-wide pt-2">Facturation</p>
        {premium ? (
          <>
            {tuile('🧾', 'Facturer maintenant', total > 0 ? `Paiement d'avance — ${eur(total)}` : "Paiement d'avance (tarif à compléter)", () => facturer(false))}
            {tuile('💶', 'Demander un acompte', total > 0 ? `30 % — ${eur(total * 0.3)} (modifiable)` : 'Montant à saisir', () => facturer(true))}
          </>
        ) : verrou}
        {tuile('🕒', 'Facturer après la prestation', 'Depuis le registre ou le RDV une fois terminé', onClose)}
        {first.acces_logement === 'remise_cles' && (
          <>
            <p className="text-xs font-bold text-gray-400 uppercase tracking-wide pt-2">Clés</p>
            {tuile('🔑', 'Enregistrer la clé du client', 'Le client vous remet ses clés', cle, 'cle')}
          </>
        )}
        {msg && <p className="text-xs text-gray-600 pt-1">{msg}</p>}
        <button type="button" onClick={onClose} className="w-full mt-2 py-2.5 rounded-xl text-sm font-semibold border border-gray-200">Fermer</button>
      </div>
    </div>
  );
}
