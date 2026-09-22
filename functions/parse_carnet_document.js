const functions = require("firebase-functions/v1");

// Clé API Anthropic — même pattern que SUPABASE_SERVICE_ROLE_KEY (stripe.js),
// jamais en dur dans le code (contrairement à la clé Stripe existante, qui
// est un mauvais précédent à ne pas reproduire).
function getAnthropicKey() {
    return process.env.ANTHROPIC_API_KEY ||
        (functions.config().anthropic || {}).key || "";
}

// Les 7 domaines du carnet de santé gérés par l'import IA
// (animal_fiche_particulier.dart / animal_fiche.dart) — les tests
// génétiques en sont exclus (formulaire trop spécifique par espèce/
// catégorie pour être pré-rempli de façon fiable). Un seul champ "domaine"
// + un objet "champs" à plat avec le sur-ensemble des colonnes possibles,
// plus fiable pour un modèle que 7 sous-schémas conditionnels.
const DOMAINES = [
    "vaccination", "traitement", "visite", "vermifuge",
    "antiparasitaire", "chirurgie", "allergie",
];

const EXTRACTION_DESCRIPTION = "Extrait les informations d'un document " +
    "vétérinaire (ordonnance, compte-rendu, carnet de vaccination, " +
    "facture) pour pré-remplir le carnet de santé numérique d'un animal.";

const EXTRACTION_TOOL = {
    name: "extraire_carnet_sante",
    description: EXTRACTION_DESCRIPTION,
    input_schema: {
        type: "object",
        properties: {
            domaine: {
                type: "string",
                enum: DOMAINES,
                description: "Catégorie du carnet de santé la plus adaptée à ce document.",
            },
            confiance: {
                type: "string",
                enum: ["haute", "moyenne", "basse"],
                description: "Confiance dans la lecture du document et le choix du domaine.",
            },
            alerte: {
                type: "string",
                description: "Optionnel : signale un problème (document " +
                    "illisible, pas un document vétérinaire, plusieurs " +
                    "actes mélangés...).",
            },
            champs: {
                type: "object",
                description: "Uniquement les champs pertinents pour le " +
                    "domaine choisi, les autres omis ou null. Toutes les " +
                    "dates au format YYYY-MM-DD.",
                properties: {
                    vaccin: {type: "string"},
                    lot: {type: "string"},
                    veterinaire: {type: "string"},
                    categorie: {type: "string"},
                    nom: {type: "string"},
                    type: {type: "string"},
                    description_maladie: {type: "string"},
                    posologie: {type: "string"},
                    motif: {type: "string"},
                    diagnostic: {type: "string"},
                    produit: {type: "string"},
                    dosage: {type: "string"},
                    frequence: {type: "string", description: "Ex: '1 mois', '3 semaines'."},
                    intitule: {type: "string"},
                    statut: {type: "string", enum: ["prevu", "realise", "annule"]},
                    clinique: {type: "string"},
                    protocole_preop: {type: "string"},
                    protocole_postop: {type: "string"},
                    description: {type: "string"},
                    severite: {type: "string"},
                    resultat: {type: "string"},
                    genotype: {type: "string"},
                    laboratoire: {type: "string"},
                    date: {type: "string", description: "YYYY-MM-DD"},
                    date_fin: {type: "string", description: "YYYY-MM-DD"},
                    date_rappel: {type: "string",
                        description: "YYYY-MM-DD, si un prochain rappel/rendez-vous est mentionné."},
                    date_validite_debut: {type: "string", description: "YYYY-MM-DD"},
                    date_test: {type: "string", description: "YYYY-MM-DD"},
                    notes: {type: "string",
                        description: "Toute information utile non couverte par les autres champs."},
                },
            },
        },
        required: ["domaine", "confiance", "champs"],
    },
};

const PROMPT = `Tu analyses un document vétérinaire (photo ou PDF) envoyé
par le propriétaire d'un animal pour pré-remplir son carnet de santé
numérique.

Choisis le domaine le plus pertinent parmi : vaccination, traitement,
visite (consultation générale), vermifuge, antiparasitaire, chirurgie
(ou hospitalisation), allergie.

Si le document mentionne plusieurs actes différents, choisis le plus
important ou le plus récent et signale les autres dans "alerte". Si le
document est illisible ou n'est manifestement pas un document
vétérinaire, mets confiance à "basse" et explique dans "alerte".

Réponds uniquement via l'outil extraire_carnet_sante.`;

/**
 * Analyse une photo/PDF de document vétérinaire et retourne des champs
 * structurés prêts à pré-remplir le formulaire d'ajout correspondant
 * (mêmes noms de colonnes que les tables vaccinations/traitements/
 * visites/vermifuges/antiparasitaires/chirurgies/allergies).
 */
exports.parseCarnetDocument = functions
    .region("europe-west1")
    .runWith({timeoutSeconds: 60, memory: "256MB"})
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError("unauthenticated", "Connexion requise.");
        }
        const fileBase64 = data.fileBase64;
        const mimeType = data.mimeType;
        if (!fileBase64 || !mimeType) {
            throw new functions.https.HttpsError("invalid-argument", "fileBase64 et mimeType requis.");
        }

        const apiKey = getAnthropicKey();
        if (!apiKey) {
            throw new functions.https.HttpsError("failed-precondition", "Clé API IA non configurée côté serveur.");
        }

        const isPdf = mimeType === "application/pdf";
        const contentBlock = isPdf ?
            {type: "document",
                source: {type: "base64", media_type: "application/pdf", data: fileBase64}} :
            {type: "image",
                source: {type: "base64", media_type: mimeType, data: fileBase64}};

        let response;
        try {
            response = await fetch("https://api.anthropic.com/v1/messages", {
                method: "POST",
                headers: {
                    "content-type": "application/json",
                    "x-api-key": apiKey,
                    "anthropic-version": "2023-06-01",
                },
                body: JSON.stringify({
                    model: "claude-sonnet-5",
                    max_tokens: 1024,
                    tools: [EXTRACTION_TOOL],
                    tool_choice: {type: "tool", name: "extraire_carnet_sante"},
                    messages: [{
                        role: "user",
                        content: [contentBlock, {type: "text", text: PROMPT}],
                    }],
                }),
            });
        } catch (e) {
            console.error("parseCarnetDocument: appel API échoué", e);
            throw new functions.https.HttpsError("unavailable", "Impossible de contacter le service d'analyse.");
        }

        if (!response.ok) {
            const errText = await response.text().catch(() => "");
            console.error("parseCarnetDocument: réponse API en erreur", response.status, errText);
            throw new functions.https.HttpsError("internal", "L'analyse du document a échoué.");
        }

        const json = await response.json();
        const toolUse = (json.content || []).find((b) => b.type === "tool_use");
        if (!toolUse) {
            throw new functions.https.HttpsError("internal",
                "Aucune information exploitable trouvée dans le document.");
        }

        return {
            domaine: toolUse.input.domaine,
            confiance: toolUse.input.confiance,
            alerte: toolUse.input.alerte || null,
            champs: toolUse.input.champs || {},
        };
    });
