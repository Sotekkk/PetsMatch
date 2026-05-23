import googlemaps
import pandas as pd
from tqdm import tqdm
import time
import re

# =========================================================
# CONFIGURATION
# =========================================================

GOOGLE_API_KEY = "AIzaSyCG9JdpDYmRVpImaZYdLg1j_SIkcm5rkbE"

OUTPUT_FILE = "veterinaires_google_maps.xlsx"

# =========================================================
# INITIALISATION GOOGLE MAPS
# =========================================================

gmaps = googlemaps.Client(key=GOOGLE_API_KEY)

# =========================================================
# VILLES A SCRAPER
# =========================================================

villes = [

    # ================= FRANCE =================

    "Paris France",
    "Marseille France",
    "Lyon France",
    "Toulouse France",
    "Nice France",
    "Nantes France",
    "Montpellier France",
    "Strasbourg France",
    "Bordeaux France",
    "Lille France",
    "Rennes France",
    "Reims France",
    "Le Havre France",
    "Saint-Etienne France",
    "Toulon France",
    "Grenoble France",
    "Dijon France",
    "Angers France",
    "Nimes France",
    "Villeurbanne France",

    # ================= BELGIQUE =================

    "Bruxelles Belgique",
    "Liege Belgique",
    "Namur Belgique",
    "Charleroi Belgique",
    "Mons Belgique",
    "Anvers Belgique",
    "Gand Belgique",

    # ================= LUXEMBOURG =================

    "Luxembourg Luxembourg",
    "Esch-sur-Alzette Luxembourg"

]

# =========================================================
# DETECTION SPECIALITES
# =========================================================

def detect_specialite(text):

    text = text.lower()

    specialites = []

    keywords = {
        "Urgence": ["urgence", "24h", "24/24"],
        "NAC": ["nac", "nouveaux animaux"],
        "Equin": ["equin", "cheval"],
        "Canin": ["chien", "canin"],
        "Felin": ["chat", "felin"],
        "Chirurgie": ["chirurgie", "chirurgien"],
        "Cardiologie": ["cardiologie"],
        "Dermatologie": ["dermatologie"],
        "Imagerie": ["scanner", "irm", "radiologie"]
    }

    for nom, mots in keywords.items():

        for mot in mots:

            if mot in text:
                specialites.append(nom)
                break

    if not specialites:
        specialites.append("Generaliste")

    return ", ".join(specialites)

# =========================================================
# EXTRACTION EMAIL
# =========================================================

def extract_email(text):

    if not text:
        return ""

    match = re.search(
        r'[\w\.-]+@[\w\.-]+\.\w+',
        text
    )

    if match:
        return match.group(0)

    return ""

# =========================================================
# RESULTATS
# =========================================================

results = []

# =========================================================
# SCRAPING GOOGLE MAPS
# =========================================================

for ville in tqdm(villes):

    try:

        print(f"\nRecherche : {ville}")

        response = gmaps.places(
            query=f"veterinaire {ville}"
        )

        places = response.get("results", [])

        for place in places:

            try:

                place_id = place["place_id"]

                details = gmaps.place(
                    place_id=place_id,
                    fields=[
                        "name",
                        "formatted_phone_number",
                        "website",
                        "formatted_address",
                        "geometry",
                        "opening_hours",
                        "business_status",
                        "rating",
                        "user_ratings_total",
                        "types"
                    ]
                )

                result = details.get("result", {})

                nom = result.get("name", "")

                telephone = result.get(
                    "formatted_phone_number",
                    ""
                )

                site_web = result.get(
                    "website",
                    ""
                )

                adresse = result.get(
                    "formatted_address",
                    ""
                )

                latitude = result.get(
                    "geometry",
                    {}
                ).get(
                    "location",
                    {}
                ).get(
                    "lat",
                    ""
                )

                longitude = result.get(
                    "geometry",
                    {}
                ).get(
                    "location",
                    {}
                ).get(
                    "lng",
                    ""
                )

                note = result.get(
                    "rating",
                    ""
                )

                nb_avis = result.get(
                    "user_ratings_total",
                    ""
                )

                horaires = ""

                if result.get("opening_hours"):

                    horaires = " | ".join(
                        result["opening_hours"].get(
                            "weekday_text",
                            []
                        )
                    )

                # =================================================
                # SPECIALITES
                # =================================================

                texte_analyse = " ".join([
                    nom,
                    site_web,
                    adresse,
                    horaires
                ])

                specialite = detect_specialite(
                    texte_analyse
                )

                urgence = (
                    "Oui"
                    if "Urgence" in specialite
                    else "Non"
                )

                # =================================================
                # EMAIL
                # =================================================

                email = extract_email(site_web)

                # =================================================
                # AJOUT RESULTAT
                # =================================================

                results.append({

                    "Nom": nom,
                    "Clinique": nom,
                    "Specialite": specialite,
                    "Urgence": urgence,
                    "Telephone": telephone,
                    "Email": email,
                    "Site web": site_web,
                    "Horaires": horaires,
                    "Adresse": adresse,
                    "Ville recherchee": ville,
                    "Latitude": latitude,
                    "Longitude": longitude,
                    "Note Google": note,
                    "Nombre avis": nb_avis

                })

                print(f"OK : {nom}")

                time.sleep(0.2)

            except Exception as e:

                print(f"Erreur fiche : {e}")

    except Exception as e:

        print(f"Erreur ville : {e}")

# =========================================================
# DATAFRAME
# =========================================================

print("\nNettoyage des données...")

df = pd.DataFrame(results)

# =========================================================
# SUPPRESSION DOUBLONS
# =========================================================

df = df.drop_duplicates(
    subset=[
        "Nom",
        "Telephone",
        "Adresse"
    ]
)

# =========================================================
# EXPORT EXCEL
# =========================================================

print("\nExport Excel...")

df.to_excel(
    OUTPUT_FILE,
    index=False
)

# =========================================================
# FIN
# =========================================================

print("\n====================================")
print(f"Fichier généré : {OUTPUT_FILE}")
print(f"Total vétérinaires : {len(df)}")
print("====================================")