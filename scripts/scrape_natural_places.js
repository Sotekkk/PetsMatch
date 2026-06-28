/**
 * Scrape lieux naturels pet-friendly en France
 * Requêtes simples par catégorie × région pour éviter les timeouts
 */

require('dotenv').config({ path: '../website/.env.local' });
require('dotenv').config({ path: '.env' });

const { createClient } = require('@supabase/supabase-js');
const fetch = require('node-fetch');

const SUPABASE_URL  = 'https://zyvpngcvzrkdytypjlyq.supabase.co';
const SUPABASE_KEY  = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5dnBuZ2N2enJrZHl0eXBqbHlxIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3OTM2NDY1NSwiZXhwIjoyMDk0OTQwNjU1fQ.1U96V3c7nHG3T08dboBcxTd05k8A_JQfnyrJTbJ0HgQ';

// Utilise kumi en priorité — moins chargé que overpass-api.de
const ENDPOINTS = [
  'https://overpass.kumi.systems/api/interpreter',
  'https://overpass-api.de/api/interpreter',
];

// Bboxes France par région (sud,ouest,nord,est)
const BBOXES = [
  '48.1,1.4,49.2,3.6',    // Île-de-France
  '44.1,2.0,46.9,7.2',    // Auvergne-Rhône-Alpes
  '47.2,-5.2,48.9,-1.0',  // Bretagne
  '48.4,-2.1,50.0,1.8',   // Normandie
  '49.4,1.4,51.1,4.3',    // Hauts-de-France
  '47.4,3.9,49.8,8.3',    // Grand Est
  '46.3,-2.6,48.4,0.8',   // Pays de la Loire
  '43.0,-1.9,47.2,2.7',   // Nouvelle-Aquitaine
  '42.3,0.6,45.1,4.8',    // Occitanie
  '43.1,4.2,44.9,7.7',    // PACA
  '46.2,2.8,48.6,7.1',    // Bourgogne-Franche-Comté
  '46.3,0.0,48.9,3.7',    // Centre-Val de Loire
  '41.3,8.4,43.1,9.6',    // Corse
];

// Catégories : [tag_key, tag_value, categorie_db]
const CATEGORIES = [
  ['leisure',   'park',             'parc'],
  ['natural',   'beach',            'plage'],
  ['natural',   'wood',             'foret'],
  ['landuse',   'forest',           'foret'],
  ['leisure',   'nature_reserve',   'foret'],
  ['natural',   'water',            'lac'],
  ['waterway',  'river',            'riviere'],
  ['waterway',  'stream',           'riviere'],
];

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

async function overpassQuery(query) {
  for (const endpoint of ENDPOINTS) {
    try {
      const res = await fetch(endpoint, {
        method:  'POST',
        headers: {
          'User-Agent':   'PetsMatch/1.0 (petsmatch.contact@gmail.com)',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body:    `data=${encodeURIComponent(query)}`,
        timeout: 20000,
      });
      if (!res.ok) continue;
      const json = await res.json();
      return json.elements || [];
    } catch (_) {
      await sleep(1000);
    }
  }
  return [];
}

async function upsert(supa, rows) {
  if (!rows.length) return 0;
  const { error } = await supa.from('natural_places')
    .upsert(rows, { onConflict: 'osm_id', ignoreDuplicates: true });
  if (error) { console.error('    upsert error:', error.message); return 0; }
  return rows.length;
}

async function main() {
  console.log('🐾 Scraping lieux naturels France...\n');
  const supa  = createClient(SUPABASE_URL, SUPABASE_KEY);
  let total   = 0;
  let bboxIdx = 0;

  for (const bbox of BBOXES) {
    bboxIdx++;
    console.log(`📍 Région ${bboxIdx}/${BBOXES.length} (${bbox})`);

    for (const [key, val, cat] of CATEGORIES) {
      const query = `[out:json][timeout:18];(node["${key}"="${val}"]["name"](${bbox});way["${key}"="${val}"]["name"](${bbox}););out center 500;`;
      const elems = await overpassQuery(query);

      const rows = [];
      for (const e of elems) {
        const name = e.tags?.name;
        if (!name) continue;
        const lat  = e.lat ?? e.center?.lat;
        const lng  = e.lon ?? e.center?.lon;
        if (!lat || !lng) continue;
        rows.push({
          osm_id:    `${e.type}_${e.id}`,
          nom:       name.trim(),
          categorie: cat,
          lat:       +lat.toFixed(6),
          lng:       +lng.toFixed(6),
        });
      }

      if (rows.length) {
        const n = await upsert(supa, rows);
        total  += n;
        console.log(`  ✓ ${key}=${val} → ${n} lieux`);
      }

      await sleep(1500); // respecter la limite Overpass
    }
  }

  console.log(`\n✅ Total : ${total} lieux insérés dans Supabase.`);
}

main().catch(console.error);
