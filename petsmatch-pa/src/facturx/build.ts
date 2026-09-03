/**
 * Orchestration Factur-X : modèle EN 16931 → { PDF/A-3, XML CII, empreinte }.
 *
 * La génération du XML (logique métier) est en Node ; l'emballage PDF/A-3 est
 * délégué au micro-service `facturx-service/` (Python, lib de référence
 * `factur-x`). L'interface `FacturxBuilder` permet de remplacer cette
 * implémentation par une version pure Node si `pdf-lib` sait un jour produire
 * du PDF/A-3 conforme.
 */

import { createHash } from 'node:crypto';
import { buildCii } from './cii.js';
import { renderInvoicePdf } from '../pdf/invoice-pdf.js';
import type { En16931Invoice } from '../model/en16931.js';

export type FacturxLevel = 'en16931' | 'basic' | 'minimum';

export interface FacturxResult {
  pdf: Uint8Array; // PDF/A-3 Factur-X
  xml: string; // XML CII embarqué
  sha256: string; // empreinte du PDF/A-3 (journal de preuve §23)
  profile: FacturxLevel;
}

export interface FacturxBuilder {
  build(inv: En16931Invoice, opts?: BuildOptions): Promise<FacturxResult>;
}

export interface BuildOptions {
  /**
   * PDF lisible source. Si absent, `HttpFacturxBuilder` génère le rendu de
   * marque PetsMatch (`renderInvoicePdf`) ; passer `brandedPdf: false` pour
   * laisser le micro-service produire son rendu minimal de repli.
   */
  sourcePdf?: Uint8Array;
  brandedPdf?: boolean;
  level?: FacturxLevel;
  parentInvoiceNumber?: string;
}

const sha256Hex = (b: Uint8Array): string => createHash('sha256').update(b).digest('hex');

/** Implémentation par appel HTTP au micro-service Python. */
export class HttpFacturxBuilder implements FacturxBuilder {
  constructor(private readonly serviceUrl: string) {}

  async build(inv: En16931Invoice, opts: BuildOptions = {}): Promise<FacturxResult> {
    const level = opts.level ?? 'en16931';
    const xml = buildCii(inv);

    const sourcePdf =
      opts.sourcePdf ?? (opts.brandedPdf === false ? undefined : await renderInvoicePdf(inv));

    const form = new FormData();
    form.append('xml', new Blob([xml], { type: 'application/xml' }), 'factur-x.xml');
    form.append('level', level);
    if (sourcePdf) {
      form.append('pdf', new Blob([sourcePdf], { type: 'application/pdf' }), 'source.pdf');
    }

    const res = await fetch(new URL('/facturx', this.serviceUrl), { method: 'POST', body: form });
    if (!res.ok) {
      let detail = `${res.status}`;
      try {
        detail = ((await res.json()) as { error?: string }).error ?? detail;
      } catch {
        /* réponse non-JSON */
      }
      throw new Error(`facturx-service: ${detail}`);
    }
    const pdf = new Uint8Array(await res.arrayBuffer());
    return { pdf, xml, sha256: sha256Hex(pdf), profile: level };
  }
}

/**
 * Implémentation « XML seul » — sans micro-service. Utile en test / CI et pour
 * les cas où l'on ne veut que le flux structuré (transmission B2B où le PDF
 * n'est pas exigé). Le champ `pdf` est vide.
 */
export class XmlOnlyFacturxBuilder implements FacturxBuilder {
  async build(inv: En16931Invoice, opts: BuildOptions = {}): Promise<FacturxResult> {
    const xml = buildCii(inv);
    const bytes = new TextEncoder().encode(xml);
    return { pdf: new Uint8Array(), xml, sha256: sha256Hex(bytes), profile: opts.level ?? 'en16931' };
  }
}
