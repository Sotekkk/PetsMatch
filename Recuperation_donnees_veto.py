import re
import time
import requests
import pandas as pd
import googlemaps

from bs4 import BeautifulSoup
from tqdm import tqdm
from geopy.geocoders import Nominatim

# =====================================================
# CONFIGURATION
# =====================================================

GOOGLE_API_KEY = "AIzaSyCG9JdpDYmRVpImaZYdLg1j_SIkcm5rkbE"

OUTPUT_FILE = "veterinaires_fr_be_lu.xlsx"

HEADERS = {
    "User-Agent": "Mozilla/5.0"
}

# =====================================================
# INITIALISATION
# =====================================================

gmaps = googlemaps.Client(key=GOOGLE_API_KEY)
geolocator = Nominatim(user_agent="vet_scraper")

results = []

# =====================================================
# SOURCES
# =====================================================

sources = [
    {
        "country": "France",
        "base_url": "https://www.veterinaire.fr/annuaires/tableau-de-lordre"
    },
    {
        "country": "Belgique",
        "base_url": "https://www.ordredesveterinaires.be"
    },
    {
        "country": "Luxembourg",
        "base_url": "https://www.editus.lu/fr/recherche?q=veterinaire"
    }
]

# =====================================================
# DETECTION SPECIALITES
# =====================================================

def detect_specialite(text):

    text = text.lower()

    specialites = []

    keywords = {
        "NAC": ["nac", "nouveaux animaux"],
        "Equin": ["equin", "cheval"],
        "Bovin": ["bovin", "vache"],
        "Urgence": ["urgence", "24h", "24/24"],
        "Chirurgie": ["chirurgie", "chirurgien"],
        "Cardiologie": ["cardiologie"],
        "Dermatologie": ["dermatologie"],
        "Imagerie": ["scanner", "irm", "radiologie"],
        "Comportement": ["comportement"],
        "Canin": ["chien", "canin"],
        "Felin": ["chat", "felin"]
    }

    for name, words in keywords.items():
        for word in words:
            if word in text:
                specialites.append(name)
                break

    if not specialites:
        specialites.append("Generaliste")

    return ", ".join(specialites)

# =====================================================
# EXTRACTION GOOGLE MAPS
# =====================================================

def enrich_google_maps(query):

    try:

        places = gmaps.places(query=query)

        if not places.get("results"):
            return {}

        place = places["results"][0]

        place_id = place.get("place_id")

        details = gmaps.place(
            place_id=place_id,
            fields=[
                "name",
                "formatted_phone_number",
                "website",
                "opening_hours",
                "geometry",
                "formatted_address"
            ]
        )

        result = details.get("result", {})

        horaires = ""

        if result.get("opening_hours"):
            horaires = " | ".join(
                result["opening_hours"].get("weekday_text", [])
            )

        return {
            "telephone": result.get("formatted_phone_number", ""),
            "website": result.get("website", ""),
            "horaires": horaires,
            "adresse": result.get("formatted_address", ""),
            "latitude": result.get("geometry", {})
                                .get("location", {})
                                .get("lat", ""),
            "longitude": result.get("geometry", {})
                                 .get("location", {})
                                 .get("lng", "")
        }

    except Exception:
        return {}

# =====================================================
# SCRAPING
# =====================================================

for source in sources:

    print(f"\n===== {source['country']} =====")

    for page in tqdm(range(1, 101)):

        url = f"{source['base_url']}?page={page}"

        try:

            response = requests.get(url, headers=HEADERS, timeout=30)

            if response.status_code != 200:
                continue

            soup = BeautifulSoup(response.text, "lxml")

            cards = soup.find_all("div")

            for card in cards:

                text = card.get_text(" ", strip=True)

                if len(text) < 20:
                    continue

                nom = text[:80]

                specialite = detect_specialite(text)

                urgence = "Oui" if "Urgence" in specialite else "Non"

                tel_match = re.search(
                    r"(\+33|\+32|\+352|0)[0-9\s\.\-]{8,}",
                    text
                )

                telephone = tel_match.group(0) if tel_match else ""

                email_match = re.search(
                    r"[\w\.-]+@[\w\.-]+\.\w+",
                    text
                )

                email = email_match.group(0) if email_match else ""

                google_data = enrich_google_maps(nom)

                results.append({
                    "Nom": nom,
                    "Clinique": nom,
                    "Specialite": specialite,
                    "Urgence": urgence,
                    "Telephone": google_data.get("telephone", telephone),
                    "Email": email,
                    "Site web": google_data.get("website", ""),
                    "Horaires": google_data.get("horaires", ""),
                    "Adresse": google_data.get("adresse", ""),
                    "Ville": "",
                    "Pays": source["country"],
                    "Latitude": google_data.get("latitude", ""),
                    "Longitude": google_data.get("longitude", "")
                })

            time.sleep(1)

        except Exception as e:
            print(e)

# =====================================================
# DATAFRAME
# =====================================================

print("\nNettoyage des données...")


df = pd.DataFrame(results)

# Suppression doublons

df = df.drop_duplicates(
    subset=["Nom", "Telephone", "Adresse"]
)

# Nettoyage colonnes

for col in df.columns:
    df[col] = df[col].astype(str).str.strip()

# =====================================================
# EXPORT EXCEL
# =====================================================

print("\nExport Excel...")

with pd.ExcelWriter(OUTPUT_FILE, engine="openpyxl") as writer:

    df.to_excel(writer, sheet_name="Veterinaires", index=False)

print(f"\nFichier généré : {OUTPUT_FILE}")
print(f"Total : {len(df)} vétérinaires")