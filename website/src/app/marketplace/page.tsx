'use client';

import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/lib/auth-context';
import Link from 'next/link';

// ── Types ──────────────────────────────────────────────────────────────────────

interface Partner {
  id: string;
  nom: string;
  logo_url: string | null;
  site_url: string | null;
  description: string | null;
  categorie: 'artisan' | 'alimentation' | 'boutique' | 'assurance';
  especes_cibles: string[];
  regions: string[];
  plan: 'starter' | 'visible' | 'premium';
  statut: string;
}

const ESPECE_LABELS: Record<string, string> = {
  tous: 'Tous',
  chien: 'Chien 🐕',
  chat: 'Chat 🐈',
  equide: 'Équidé 🐴',
  autre: 'Autre',
};

const CAT_LABELS: Record<string, string> = {
  artisan: 'Artisan',
  alimentation: 'Alimentation',
  boutique: 'Boutique',
  assurance: 'Assurance',
};

const CAT_COLORS: Record<string, string> = {
  artisan: '#8E24AA',
  alimentation: '#EF6C00',
  boutique: '#1E88E5',
  assurance: '#2E7D32',
};

// ── Page ───────────────────────────────────────────────────────────────────────

export default function MarketplacePage() {
  const { user } = useAuth();
  const [partners, setPartners] = useState<Partner[]>([]);
  const [filterEspece, setFilterEspece] = useState('tous');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadPartners();
  }, [filterEspece]);

  async function loadPartners() {
    setLoading(true);
    let query = supabase
      .from('marketplace_partners')
      .select('*')
      .eq('statut', 'actif')
      .order('plan', { ascending: false });

    if (filterEspece !== 'tous') {
      query = query.contains('especes_cibles', [filterEspece]);
    }

    const { data } = await query;
    setPartners((data as Partner[]) ?? []);
    setLoading(false);
  }

  async function logEvent(
    partnerId: string,
    eventType: 'impression' | 'clic' | 'lead',
    adId?: string
  ) {
    try {
      await supabase.from('marketplace_events').insert({
        partner_id: partnerId,
        ad_id: adId ?? null,
        user_id: user?.uid ?? null,
        event_type: eventType,
        espece: filterEspece === 'tous' ? null : filterEspece,
      });
    } catch (_) {}
  }

  function openPartner(partner: Partner, eventType: 'clic' | 'lead') {
    logEvent(partner.id, eventType);
    if (partner.site_url) window.open(partner.site_url, '_blank', 'noopener');
  }

  const insurers = partners.filter((p) => p.categorie === 'assurance');
  const others = partners.filter((p) => p.categorie !== 'assurance');

  return (
    <div style={{ minHeight: '100vh', background: '#F8F8F6', fontFamily: 'sans-serif' }}>
      {/* Header */}
      <div style={{ background: '#A7C79A', padding: '24px 24px 20px' }}>
        <div style={{ maxWidth: 900, margin: '0 auto' }}>
          <h1 style={{ margin: 0, fontWeight: 700, fontSize: 26, color: '#1a1a1a' }}>
            Marketplace
          </h1>
          <p style={{ margin: '6px 0 0', color: '#444', fontSize: 14 }}>
            Des marques vérifiées pour vos animaux
          </p>
        </div>
      </div>

      <div style={{ maxWidth: 900, margin: '0 auto', padding: '28px 16px' }}>
        {/* Filtres espèce */}
        <div style={{ marginBottom: 28 }}>
          <p style={{ margin: '0 0 12px', fontWeight: 600, fontSize: 16, color: '#1a1a1a' }}>
            Nos partenaires sélectionnés
          </p>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            {Object.entries(ESPECE_LABELS).map(([key, label]) => (
              <button
                key={key}
                onClick={() => setFilterEspece(key)}
                style={{
                  padding: '6px 16px',
                  borderRadius: 20,
                  border: `1.5px solid ${filterEspece === key ? '#6E9E57' : '#ddd'}`,
                  background: filterEspece === key ? '#6E9E57' : 'white',
                  color: filterEspece === key ? 'white' : '#333',
                  cursor: 'pointer',
                  fontSize: 13,
                  fontWeight: 500,
                  transition: 'all .15s',
                }}
              >
                {label}
              </button>
            ))}
          </div>
        </div>

        {loading ? (
          <div style={{ textAlign: 'center', padding: 60, color: '#6E9E57', fontSize: 16 }}>
            Chargement…
          </div>
        ) : partners.length === 0 ? (
          <div style={{ textAlign: 'center', padding: 60 }}>
            <div style={{ fontSize: 48 }}>🛍️</div>
            <p style={{ color: '#888', fontSize: 16, marginTop: 12 }}>
              Aucun partenaire disponible pour le moment
            </p>
          </div>
        ) : (
          <>
            {/* Section Assurances */}
            {insurers.length > 0 && (
              <section style={{ marginBottom: 40 }}>
                <h2 style={{ fontSize: 18, fontWeight: 700, marginBottom: 14, display: 'flex', alignItems: 'center', gap: 8 }}>
                  🛡️ Assurances animaux
                </h2>
                <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
                  {insurers.map((p) => (
                    <InsuranceCard key={p.id} partner={p} onCta={() => openPartner(p, 'lead')} />
                  ))}
                </div>
              </section>
            )}

            {/* Section partenaires */}
            {others.length > 0 && (
              <section style={{ marginBottom: 40 }}>
                <h2 style={{ fontSize: 18, fontWeight: 700, marginBottom: 14, display: 'flex', alignItems: 'center', gap: 8 }}>
                  🤝 Nos partenaires
                </h2>
                <div style={{
                  display: 'grid',
                  gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))',
                  gap: 16,
                }}>
                  {others.map((p) => (
                    <PartnerCard key={p.id} partner={p} onClick={() => openPartner(p, 'clic')} />
                  ))}
                </div>
              </section>
            )}
          </>
        )}

        {/* CTA devenir partenaire */}
        <div style={{
          background: 'linear-gradient(135deg, #6E9E57, #4A7A3D)',
          borderRadius: 18,
          padding: '28px 28px',
          color: 'white',
          marginTop: 16,
        }}>
          <h3 style={{ margin: '0 0 8px', fontSize: 20, fontWeight: 700 }}>
            Vous êtes une marque ?
          </h3>
          <p style={{ margin: '0 0 18px', fontSize: 14, opacity: 0.9 }}>
            Rejoignez nos partenaires et touchez une audience qualifiée d&apos;amoureux des animaux.
            Formats disponibles : listing, bannières contextuelles, CPL assurances.
          </p>
          <Link
            href="/marketplace/partenaire"
            style={{
              background: 'white',
              color: '#4A7A3D',
              padding: '10px 22px',
              borderRadius: 10,
              fontWeight: 700,
              fontSize: 14,
              textDecoration: 'none',
              display: 'inline-block',
            }}
          >
            Devenir partenaire
          </Link>
        </div>
      </div>
    </div>
  );
}

// ── Partner card (grille) ─────────────────────────────────────────────────────

function PartnerCard({ partner, onClick }: { partner: Partner; onClick: () => void }) {
  const catColor = CAT_COLORS[partner.categorie] ?? '#888';
  const isPremium = partner.plan === 'premium';

  return (
    <div
      onClick={onClick}
      style={{
        background: 'white',
        borderRadius: 16,
        border: isPremium ? `1.5px solid ${catColor}40` : '1px solid #eee',
        boxShadow: '0 2px 8px rgba(0,0,0,0.06)',
        cursor: 'pointer',
        overflow: 'hidden',
        transition: 'transform .15s, box-shadow .15s',
      }}
      onMouseEnter={(e) => {
        (e.currentTarget as HTMLDivElement).style.transform = 'translateY(-2px)';
        (e.currentTarget as HTMLDivElement).style.boxShadow = '0 6px 16px rgba(0,0,0,0.10)';
      }}
      onMouseLeave={(e) => {
        (e.currentTarget as HTMLDivElement).style.transform = 'translateY(0)';
        (e.currentTarget as HTMLDivElement).style.boxShadow = '0 2px 8px rgba(0,0,0,0.06)';
      }}
    >
      {/* Logo */}
      <div style={{ height: 120, background: '#F0F7EC', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        {partner.logo_url ? (
          <img src={partner.logo_url} alt={partner.nom} style={{ maxWidth: '80%', maxHeight: '80%', objectFit: 'contain' }} />
        ) : (
          <span style={{ fontSize: 40 }}>🏪</span>
        )}
      </div>
      {/* Info */}
      <div style={{ padding: '12px 12px 14px' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
          <span style={{ fontWeight: 600, fontSize: 13, color: '#1a1a1a', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: '80%' }}>
            {partner.nom}
          </span>
          <span style={{ fontSize: 10, color: '#6E9E57', fontWeight: 700, background: '#E8F5E9', padding: '2px 5px', borderRadius: 6 }}>
            ✓
          </span>
        </div>
        <span style={{ fontSize: 11, background: `${catColor}18`, color: catColor, padding: '2px 8px', borderRadius: 20, fontWeight: 600 }}>
          {CAT_LABELS[partner.categorie] ?? partner.categorie}
        </span>
      </div>
    </div>
  );
}

// ── Insurance card ────────────────────────────────────────────────────────────

function InsuranceCard({ partner, onCta }: { partner: Partner; onCta: () => void }) {
  return (
    <div style={{
      background: 'white',
      borderRadius: 16,
      boxShadow: '0 2px 8px rgba(0,0,0,0.06)',
      padding: '16px 20px',
      display: 'flex',
      alignItems: 'center',
      gap: 16,
    }}>
      {/* Logo */}
      <div style={{
        width: 60, height: 60,
        background: '#F0F7EC',
        borderRadius: 12,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0,
      }}>
        {partner.logo_url
          ? <img src={partner.logo_url} alt={partner.nom} style={{ maxWidth: '80%', maxHeight: '80%', objectFit: 'contain' }} />
          : <span style={{ fontSize: 28 }}>🛡️</span>
        }
      </div>
      {/* Info */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
          <span style={{ fontWeight: 600, fontSize: 15, color: '#1a1a1a' }}>{partner.nom}</span>
          <span style={{ fontSize: 10, color: '#6E9E57', fontWeight: 700, background: '#E8F5E9', padding: '2px 6px', borderRadius: 6 }}>
            ✓ Vérifié
          </span>
        </div>
        {partner.description && (
          <p style={{ margin: 0, fontSize: 13, color: '#666', overflow: 'hidden', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>
            {partner.description}
          </p>
        )}
      </div>
      {/* CTA */}
      <button
        onClick={onCta}
        style={{
          background: '#0C5C6C',
          color: 'white',
          border: 'none',
          borderRadius: 10,
          padding: '10px 18px',
          fontWeight: 700,
          fontSize: 13,
          cursor: 'pointer',
          flexShrink: 0,
          whiteSpace: 'nowrap',
        }}
      >
        Obtenir un devis
      </button>
    </div>
  );
}
