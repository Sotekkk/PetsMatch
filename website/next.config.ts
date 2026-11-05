import type { NextConfig } from "next";
import path from "path";

const nextConfig: NextConfig = {
  typescript: {
    ignoreBuildErrors: true,
  },
  experimental: {
    // Le proxy coupe par défaut les requêtes à 10 Mo : plusieurs PDF d'une fin de séance (en
    // base64) arrivaient tronqués. 26 Mo couvre le maximum d'un e-mail Gmail (25 Mo encodé).
    proxyClientMaxBodySize: '26mb',
  },
  turbopack: {
    root: path.resolve(__dirname),
  },
  images: {
    remotePatterns: [
      { protocol: 'https', hostname: 'firebasestorage.googleapis.com' },
      { protocol: 'https', hostname: 'zyvpngcvzrkdytypjlyq.supabase.co' },
      { protocol: 'https', hostname: 'lh3.googleusercontent.com' },
    ],
  },
  async headers() {
    return [
      {
        // Deep links : les fichiers .well-known doivent être servis en JSON.
        source: '/.well-known/:file(assetlinks.json|apple-app-site-association)',
        headers: [{ key: 'Content-Type', value: 'application/json' }],
      },
    ];
  },
};

export default nextConfig;
