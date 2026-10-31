'use client';

// Dossier de la séance — vétérinaire et ostéo / kiné : toutes les étapes du RDV
// au même endroit (un seul bouton sur la carte du RDV, comme l'éducateur, le
// toiletteur et le photographe). Pour chaque document, le choix entre le faire
// avec PetsMatch et charger le sien. Un compte rendu chargé n'empêche pas
// d'ajouter les soins (produits, traitements, vaccins) via le compte rendu
// PetsMatch : c'est le document chargé qui part au client à la fin.

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import ComptesRendusAnimauxRdv from '@/components/rdv/ComptesRendusAnimauxRdv';
import { comptesRendusProDuRdv, type DocumentProRdv } from '@/lib/document-pro';
import { ouvrirDocument } from '@/lib/document-prive';
import type { AnimalRdv } from '@/lib/rdv-animaux';

const TEAL = '#0C5C6C';
const VERT = '#2E7D32';
const GRIS = '#6B7280';

export default function DossierSoinsModal({ rdvId, metier, dateHeure, nomClient, animaux, proProfileId, version,
  onClose, onOuvrirPage, onChargerDoc, onFacturer, onFin, onHistorique, onFiche }: {
  rdvId: string; metier: 'veterinaire' | 'sante'; dateHeure: string; nomClient: string;
  animaux: AnimalRdv[]; proProfileId: string | null; version: number;
  onClose: () => void;
  onOuvrirPage: (url: string, titre: string) => void;
  onChargerDoc: (mode: 'compte_rendu' | 'contrat') => void;
  /** Absent : facture déjà émise. */
  onFacturer?: () => void;
  onFin: () => void;
  onHistorique?: () => void;
  onFiche: (animalId: string) => void;
}) {
  const [docs, setDocs] = useState<DocumentProRdv[]>([]);
  const [facture, setFacture] = useState<{ statut: string | null; total_ttc: number | null; numero_affichage: string | null } | null>(null);
  const veto = metier === 'veterinaire';

  useEffect(() => {
    let annule = false;
    (async () => {
      const [d, { data: f }] = await Promise.all([
        comptesRendusProDuRdv(rdvId).catch(() => [] as DocumentProRdv[]),
        supabase.from('factures').select('statut, total_ttc, numero_affichage').eq('source_rdv_id', rdvId).neq('statut', 'annulee')
          .or('type_facture.is.null,type_facture.not.in.(acompte,avoir)').order('created_at', { ascending: false }).limit(1).maybeSingle(),
      ]);
      if (annule) return;
      setDocs(d);
      setFacture((f as typeof facture) ?? null);
    })();
    return () => { annule = true; };
  }, [rdvId, version]);

  const debut = new Date(dateHeure);
  const btn = (label: string, onClick: () => void, plein = false) => (
    <button type="button" onClick={onClick}
      className="text-xs font-semibold px-3 py-1.5 rounded-xl border whitespace-nowrap"
      style={plein ? { background: TEAL, borderColor: TEAL, color: 'white' } : { borderColor: TEAL, color: TEAL }}>
      {label}
    </button>
  );
  const etape = (n: number, titre: string, etat: string, couleur: string, contenu: React.ReactNode) => (
    <div className="border border-gray-100 rounded-2xl p-3">
      <div className="flex items-center gap-2 mb-2">
        <span className="w-6 h-6 rounded-full text-[11px] font-bold text-white flex items-center justify-center shrink-0" style={{ background: TEAL }}>{n}</span>
        <p className="flex-1 text-sm font-bold text-[#1F2A2E]">{titre}</p>
        <span className="text-[11px] font-semibold" style={{ color: couleur }}>{etat}</span>
      </div>
      {contenu}
    </div>
  );

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 px-4" onClick={onClose}>
      <div className="bg-white rounded-t-2xl sm:rounded-2xl w-full max-w-lg max-h-[92vh] overflow-y-auto p-5" onClick={e => e.stopPropagation()}
        style={{ fontFamily: 'Galey, sans-serif' }}>
        <div className="flex items-start justify-between gap-3 mb-1">
          <div>
            <h2 className="font-bold text-lg text-[#1F2A2E]">Dossier de la séance</h2>
            <p className="text-xs text-gray-500">
              {debut.toLocaleDateString('fr-FR', { weekday: 'long', day: 'numeric', month: 'long' })} à {debut.toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })} · {nomClient}
            </p>
          </div>
          <button type="button" onClick={onClose} className="text-sm text-gray-400">Fermer</button>
        </div>

        <div className="space-y-3 mt-3">
          {etape(1, veto ? 'Compte rendu et soins' : 'Séance (compte rendu)', docs.length ? 'Document chargé' : '', docs.length ? VERT : GRIS, (
            <div className="space-y-2">
              <p className="text-xs text-gray-500">
                {veto ? 'Avec PetsMatch : compte rendu, ordonnance, vaccins, traitements et produits (carnet et facture).'
                  : 'Avec PetsMatch : bilan, points travaillés, conseils.'} Ou chargez votre propre document (PDF / photo).
              </p>
              {animaux.length > 0 && (
                <ComptesRendusAnimauxRdv rdvId={rdvId} animaux={animaux} metier={metier} proProfileId={proProfileId}
                  clientNom={nomClient} onOuvrir={onOuvrirPage} version={version} />
              )}
              {docs.map(d => (
                <button key={d.id} type="button" onClick={() => ouvrirDocument(d.url)}
                  className="block w-full text-left text-xs font-semibold px-2 py-1.5 rounded-lg bg-[#EEF5EA] text-[#2E5E20]">
                  Mon document : {d.titre ?? 'Compte rendu'} · ouvrir
                </button>
              ))}
              <div className="flex flex-wrap gap-2">
                {btn('Charger mon compte rendu (PDF / photo)', () => onChargerDoc('compte_rendu'))}
              </div>
              {veto && docs.length > 0 && (
                <p className="text-[11px] text-gray-500">
                  Votre document chargé sera envoyé au client. Pour inscrire des soins (vaccins, traitements, produits) au carnet et à la facture,
                  utilisez quand même « Rédiger le compte rendu avec PetsMatch » : seuls les soins comptent, le texte est facultatif.
                </p>
              )}
            </div>
          ))}

          {etape(2, 'Contrat', '', GRIS, (
            <div className="flex flex-wrap gap-2">
              {btn('Charger mon contrat (PDF / photo)', () => onChargerDoc('contrat'))}
            </div>
          ))}

          {etape(3, 'Facture', facture ? `${facture.statut === 'payee' ? 'Payée' : 'Émise'}${facture.total_ttc != null ? ` · ${Number(facture.total_ttc).toFixed(2)} €` : ''}` : 'À émettre',
            facture ? VERT : GRIS, (
            <div className="flex flex-wrap gap-2">
              {!facture && onFacturer ? btn('Facturer', onFacturer) : btn('Voir mes factures', () => onOuvrirPage('/elevage/facturation', 'Factures'))}
            </div>
          ))}

          {(onHistorique || animaux.length > 0) && etape(4, 'Dossier de l’animal', '', GRIS, (
            <div className="flex flex-wrap gap-2">
              {animaux.map(a => <span key={a.id}>{btn(animaux.length > 1 ? `Fiche — ${a.nom}` : 'Fiche de l’animal', () => onFiche(a.id))}</span>)}
              {onHistorique && btn('Historique', onHistorique)}
            </div>
          ))}
        </div>

        <button type="button" onClick={onFin} className="w-full mt-4 py-3 rounded-xl text-sm font-bold text-white" style={{ background: TEAL }}>
          {veto ? 'Terminer la consultation et envoyer' : 'Terminer la séance et envoyer'}
        </button>
        <p className="text-[11px] text-gray-400 mt-1.5 text-center">Compte rendu (le vôtre ou celui de PetsMatch), ordonnance et facture, en un seul e-mail.</p>
      </div>
    </div>
  );
}
