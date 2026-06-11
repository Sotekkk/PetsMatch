import React from 'react';

export type BadgeLevel = 'none' | 'verifie' | 'premium';

export function getBadgeLevel(opts: {
  statutPro?: string;
  siret?: string | null;
  isPremium?: boolean;
}): BadgeLevel {
  if (opts.isPremium) return 'premium';
  if (opts.statutPro === 'actif' && opts.siret) return 'verifie';
  return 'none';
}

interface Props {
  level: BadgeLevel;
  size?: 'sm' | 'md' | 'lg';
  showLabel?: boolean;
}

const CONFIG = {
  verifie: {
    icon: '✓',
    label: 'Vérifié',
    color: '#2563eb',
    bg: '#dbeafe',
    tooltip: 'SIRET vérifié par notre équipe',
  },
  premium: {
    icon: '★',
    label: 'Premium',
    color: '#d97706',
    bg: '#fef3c7',
    tooltip: 'Profil certifié Premium — documents et abonnement validés',
  },
};

const SIZES = {
  sm: { px: 'px-1.5 py-0.5', text: 'text-[10px]', icon: 'text-[10px]' },
  md: { px: 'px-2 py-0.5',   text: 'text-xs',      icon: 'text-xs' },
  lg: { px: 'px-3 py-1',     text: 'text-sm',      icon: 'text-sm' },
};

export default function VerificationBadge({ level, size = 'md', showLabel = true }: Props) {
  if (level === 'none') return null;
  const cfg = CONFIG[level];
  const sz  = SIZES[size];

  return (
    <span
      title={cfg.tooltip}
      className={`inline-flex items-center gap-1 rounded-full font-semibold ${sz.px}`}
      style={{ background: cfg.bg, color: cfg.color }}
    >
      <span className={sz.icon}>{cfg.icon}</span>
      {showLabel && <span className={sz.text}>{cfg.label}</span>}
    </span>
  );
}
