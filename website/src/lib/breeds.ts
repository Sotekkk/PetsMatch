const cache: Record<string, string[]> = {};

const BREED_FILES: Record<string, string> = {
  chien:  '/breeds/dog_breeds.json',
  chat:   '/breeds/cat_breeds.json',
  cheval: '/breeds/horse_breeds.json',
  lapin:  '/breeds/rabbit_breeds.json',
  oiseau: '/breeds/bird_breeds.json',
  nac:    '/breeds/nac_breeds.json',
  ovin:   '/breeds/sheep_breeds.json',
  caprin: '/breeds/goat_breeds.json',
  porcin: '/breeds/pig_breeds.json',
};

export async function loadBreeds(espece: string): Promise<string[]> {
  if (cache[espece]) return cache[espece];
  const file = BREED_FILES[espece];
  if (!file) return [];
  try {
    const res = await fetch(file);
    const data = await res.json();
    cache[espece] = Array.isArray(data) ? data : [];
    return cache[espece];
  } catch {
    return [];
  }
}
