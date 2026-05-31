const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");
const stripe = require("stripe")(
    "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",
);

admin.initializeApp();

exports.createStripePaymentIntent = functions
    .region("europe-west1")
    .https.onCall(async (data, context) => {
        console.log("Received data:", data);

        if (!context.auth) {
            throw new functions.https.HttpsError(
                "unauthenticated",
                "The function must be called while authenticated.",
            );
        }

        const amount = data.amount;
        const currency = data.currency;

        try {
            console.log("Creating payment intent with amount:", amount, "and currency:", currency);
            const paymentIntent = await stripe.paymentIntents.create({
                amount: amount,
                currency: currency,
            });
            console.log("Payment intent created successfully:", paymentIntent);

            return {
                clientSecret: paymentIntent.client_secret,
            };
        } catch (error) {
            console.error("Error creating payment intent:", error);
            throw new functions.https.HttpsError(
                "internal",
                "Unable to create payment intent",
            );
        }
    });

exports.createStripeSubscription = functions
    .region("europe-west1")
    .https.onCall(async (data, context) => {
        const userId = context.auth.uid;
        if (!userId) {
            throw new functions.https.HttpsError(
                "unauthenticated",
                "Authentication is required.",
            );
        }

        const customer = await stripe.customers.create({
            metadata: {
                firebaseUID: userId,
            },
        });

        const subscription = await stripe.subscriptions.create({
            customer: customer.id,
            items: [
                {
                    price: "prod_QiPMAzr63ekTg9", // Remplace par l'ID de prix de ton produit dans Stripe
                },
            ],
            expand: ["latest_invoice.payment_intent"],
        });

        return {
            clientSecret: subscription.latest_invoice.payment_intent.client_secret,
            subscriptionId: subscription.id,
        };
    });

exports.cancelStripeSubscription = functions
    .region("europe-west1")
    .https.onCall(async (data, context) => {
        const subscriptionId = data.subscriptionId;

        try {
            const deletedSubscription = await stripe.subscriptions.del(subscriptionId);
            return {status: deletedSubscription.status};
        } catch (error) {
            throw new functions.https.HttpsError(
                "internal",
                "Unable to cancel subscription",
            );
        }
    });

exports.stripeWebhook = functions
    .region("europe-west1")
    .https.onRequest((req, res) => {
        console.log("Webhook received"); // Log d'entrée
        const sig = req.headers["stripe-signature"];
        const endpointSecret = "whsec_eu7vEiB8outUOheqUdWPCYVA2PhiQbQt"; // Assure-toi que ce secret est correct

        let event;

        try {
            event = stripe.webhooks.constructEvent(req.rawBody, sig, endpointSecret);
            console.log("✅ Webhook event verified:", event.type);
        } catch (err) {
            console.log("⚠️ Webhook signature verification failed:", err.message);
            return res.sendStatus(400);
        }

        // Suite du traitement...


        // Traiter l'événement Stripe
        switch (event.type) {
        case "invoice.payment_failed":
            // eslint-disable-next-line no-case-declarations
            const invoice = event.data.object;
            // eslint-disable-next-line no-case-declarations
            const customerId = invoice.customer;
            handleFailedPayment(customerId);
            sendToDiscord(`Payment failed for customer ${customerId}.`);
            break;
        case "customer.subscription.deleted":
            // eslint-disable-next-line no-case-declarations
            const subscription = event.data.object;
            if (subscription.status === "canceled") {
                handleCanceledSubscription(subscription.id);
                sendToDiscord(`Subscription canceled for customer ${subscription.customer}.`);
            }
            break;
        default:
            console.log(`Unhandled event type ${event.type}`);
            sendToDiscord(`Unhandled event type: ${event.type}`);
        }

        // Retourne une réponse 200 pour accuser réception de l'événement
        res.send();
    });

// Fonction pour gérer l'échec de paiement
// eslint-disable-next-line require-jsdoc
async function handleFailedPayment(customerId) {
    const userDoc = await admin
        .firestore()
        .collection("users")
        .where("stripeCustomerId", "==", customerId)
        .get();

    if (!userDoc.empty) {
        const userId = userDoc.docs[0].id;
        await admin
            .firestore()
            .collection("subscriptions")
            .doc(userId)
            .update({
                status: "payment_failed",
            });
    }
}

// Fonction pour gérer l'annulation de l'abonnement
// eslint-disable-next-line require-jsdoc
async function handleCanceledSubscription(subscriptionId) {
    const userDoc = await admin
        .firestore()
        .collection("subscriptions")
        .where("subscriptionId", "==", subscriptionId)
        .get();

    if (!userDoc.empty) {
        const userId = userDoc.docs[0].id;
        await admin
            .firestore()
            .collection("subscriptions")
            .doc(userId)
            .update({
                status: "canceled",
            });
    }
}

// Fonction pour envoyer des notifications à Discord
// eslint-disable-next-line require-jsdoc
async function sendToDiscord(message) {
    const discordWebhookUrl =
        // eslint-disable-next-line max-len
        "https://discord.com/api/webhooks/1276551741093056543/pOccoSj4wdxzH6lrgtXJ6H04tva4AUYYggu62spd0q0QsCqXHhj6LXIqHgjp4SYjFl1y";

    const payload = {
        content: message,
    };

    const response = await fetch(discordWebhookUrl, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
    });

    if (!response.ok) {
        console.error("Error sending message to Discord", response.statusText);
    }
}
exports.sendNotificationOnNewMessage = functions
    .region("europe-west1")
    .firestore
    .document("conversations/{conversationId}/messages/{messageId}")
    .onCreate(async (snapshot, context) => {
        const messageData = snapshot.data();
        const conversationId = context.params.conversationId;

        const senderId = messageData.senderId;
        const text = messageData.text;

        // 🔍 Récupération des participants
        const conversationRef = admin.firestore().collection("conversations").doc(conversationId);
        const conversationSnapshot = await conversationRef.get();
        const conversationData = conversationSnapshot.data();

        if (!conversationData) {
            console.error("❌ Conversation non trouvée !");
            return;
        }

        for (const participantId of conversationData.participants) {
            if (participantId !== senderId) {
                const userRef = admin.firestore().collection("users").doc(participantId);
                const userSnapshot = await userRef.get();

                if (!userSnapshot.exists) {
                    console.error(`❌ Utilisateur ${participantId} non trouvé !`);
                    continue;
                }

                const userData = userSnapshot.data();
                const isOnline = userData.isOnline || false;
                const fcmToken = userData.fcmToken;
                const apnsToken = userData.apnsToken;

                // 🔹 On ignore l'envoi si l'utilisateur est en ligne
                if (isOnline) {
                    console.log(`❌ Notification ignorée pour ${participantId}, utilisateur en ligne.`);
                    continue;
                }

                // ✅ Vérification des tokens
                if (!fcmToken && !apnsToken) {
                    console.warn(`⚠️ Aucun token trouvé pour ${participantId}, notification ignorée.`);
                    continue;
                }

                console.log(`📌 Token récupéré pour ${participantId}:`, fcmToken || apnsToken);

                // 📩 Préparation du message pour Android (FCM) et iOS (APNs)
                const message = {
                    notification: {
                        title: "Nouveau message",
                        body: text,
                    },
                    data: {
                        conversationId: conversationId,
                    },
                };

                if (fcmToken) {
                    // 🎯 Envoi via Firebase Cloud Messaging (Android)
                    message.token = fcmToken;
                    message.android = {notification: {sound: "default"}};
                } else if (apnsToken) {
                    // 🍏 Envoi via Apple Push Notification Service (iOS)
                    message.token = apnsToken;
                    message.apns = {
                        payload: {
                            aps: {
                                alert: {
                                    title: "Nouveau message",
                                    body: text,
                                },
                                sound: "default",
                                badge: 1,
                            },
                        },
                    };
                }

                // 🚀 Envoi de la notification
                try {
                    await admin.messaging().send(message);
                    console.log(`✅ Notification envoyée à ${participantId}`);
                } catch (error) {
                    console.error(`❌ Erreur d'envoi pour ${participantId} :`, error);
                }
            }
        }
    });

// eslint-disable-next-line require-jsdoc
function convertToTimeZone(date, timeZone) {
    const options = {timeZone, year: "numeric", month: "2-digit", day: "2-digit"};
    const formatter = new Intl.DateTimeFormat("en-US", options);

    const parts = formatter.formatToParts(date).reduce((acc, part) => {
        if (part.type !== "literal") {
            acc[part.type] = part.value;
        }
        return acc;
    }, {});
    return new Date(`${parts.year}-${parts.month}-${parts.day}T00:00:00`);
}
// Fonction principale pour gérer les rappels de vaccination
// eslint-disable-next-line require-jsdoc
// Fonction principale pour gérer les rappels de vaccination
// eslint-disable-next-line require-jsdoc
async function sendNotificationWithDelay(notification, delay) {
    await new Promise((resolve) => setTimeout(resolve, delay)); // Attente avant l'envoi
    await sendNotification(notification); // Envoi de la notification
}

// eslint-disable-next-line require-jsdoc
async function processVaccinationReminders(userId) {
    const now = new Date();
    const timeZone = "Europe/Paris"; // Utiliser le fuseau horaire local
    const todayLocal = convertToTimeZone(now, timeZone);

    console.log(`📅 Date actuelle (locale) : ${todayLocal.toDateString()}`);

    const collections = ["dogfiche", "catfiche"]; // Traiter les chiens et les chats

    try {
        for (const collectionName of collections) {
            console.log(`🔍 Vérification de la collection : ${collectionName}`);

            const animalsSnapshot = await admin.firestore()
                .collection(`${collectionName}/${userId}/entries`)
                .get();

            for (const animalDoc of animalsSnapshot.docs) {
                const animalData = animalDoc.data();

                // Récupération des vaccins
                const vaccines = animalData.vaccines || [];
                console.log(`🐾 Traitement des vaccins pour ${collectionName} : ${animalData.name}`);
                console.log("Vaccins détectés :", vaccines);

                for (const vaccine of vaccines) {
                    const reminderDate = vaccine.reminderDate ?
                        new Date(vaccine.reminderDate.seconds * 1000) :
                        null;

                    if (reminderDate) {
                        const reminderLocalDate = convertToTimeZone(reminderDate, timeZone);

                        if (reminderLocalDate.toDateString() === todayLocal.toDateString()) {
                            const fcmToken = await getUserFcmToken(userId);

                            if (fcmToken) {
                                await sendNotificationWithDelay({
                                    // eslint-disable-next-line no-undef
                                    token,
                                    // eslint-disable-next-line no-undef
                                    platform,
                                    title: "Rappel de Vaccin",
                                    body: `Le vaccin ${vaccine.name} est prévu aujourd'hui pour ${animalData.name}.`,
                                }, 5000);
                                console.log(`✅ Notification envoyée pour ${animalData.name}, vaccin ${vaccine.name}`);
                            }
                        }
                    }
                }

                // Récupération des vermifuges
                const vermifuges = animalData.vermifuges || [];
                console.log(`🐾 Traitement des vermifuges pour ${collectionName} : ${animalData.name}`);
                console.log("Vermifuges détectés :", vermifuges);

                for (const vermifuge of vermifuges) {
                    const reminderDate = vermifuge.reminderDate ?
                        new Date(vermifuge.reminderDate.seconds * 1000) :
                        null;

                    if (reminderDate) {
                        const reminderLocalDate = convertToTimeZone(reminderDate, timeZone);

                        if (reminderLocalDate.toDateString() === todayLocal.toDateString()) {
                            const fcmToken = await getUserFcmToken(userId);

                            if (fcmToken) {
                                // await sendNotificationWithDelay({
                                //     token: fcmToken,
                                //     title: "Rappel de Vermifuge",
                                //     body: `Le vermifuge est prévu aujourd'hui pour ${animalData.name}.`,
                                // }, 5000);
                                await sendNotificationWithDelay({
                                    // eslint-disable-next-line no-undef
                                    token,
                                    // eslint-disable-next-line no-undef
                                    platform,
                                    title: "Rappel de Vermifuge",
                                    body: `Le vermifuge est prévu aujourd'hui pour ${animalData.name}.`,
                                }, 5000);
                                console.log(`✅ Notification envoyée pour ${animalData.name}, vermifuge.`);
                            }
                        }
                    }
                }

                // Récupération des saillies
                const saillies = animalData.saillies || [];
                console.log(`🐾 Traitement des saillies pour ${collectionName} : ${animalData.name}`);
                console.log("Saillies détectées :", saillies);

                for (const saillie of saillies) {
                    const saillieDate = saillie.date ?
                        new Date(saillie.date.seconds * 1000) :
                        null;

                    if (saillieDate) {
                        // eslint-disable-next-line max-len
                        const daysToAdd = collectionName === "catfiche" ? 63 : 61; // 63 jours pour les chats, 61 jours pour les chiens
                        const estimatedDate = new Date(saillieDate);
                        estimatedDate.setDate(saillieDate.getDate() + daysToAdd);

                        const reminderLocalDate = convertToTimeZone(estimatedDate, timeZone);
                        const daysBeforeDueDate = Math.floor((reminderLocalDate - todayLocal) / (1000 * 60 * 60 * 24));

                        if (daysBeforeDueDate <= 2 && daysBeforeDueDate >= 0) {
                            const fcmToken = await getUserFcmToken(userId);

                            if (fcmToken) {
                                // await sendNotificationWithDelay({
                                //     token: fcmToken,
                                //     title: "Rappel de Saillie",
                                //     // eslint-disable-next-line max-len, max-len
                                // }, 5000);
                                await sendNotificationWithDelay({
                                    // eslint-disable-next-line no-undef
                                    token,
                                    // eslint-disable-next-line no-undef
                                    platform,
                                    title: "Rappel de Saillie",
                                    // eslint-disable-next-line max-len
                                    body: `La mise bas estimée pour ${animalData.name} est dans ${daysBeforeDueDate} jour(s).`,
                                }, 5000);
                                // eslint-disable-next-line max-len
                                console.log(`✅ Notification envoyée pour ${animalData.name}, mise bas estimée le ${reminderLocalDate.toDateString()}`);
                            }
                        }
                    }
                }
            }
        }

        console.log("✅ Vérification des rappels de vaccination, vermifuge et saillie terminée.");
    } catch (error) {
        console.error("❌ Erreur lors de la vérification des rappels :", error);
    }
}

// Fonction planifiée pour les rappels quotidiens (exécutée à 10h dans la région europe-west1)
exports.sendVaccinationReminders = functions
    .region("europe-west1")
    .pubsub.schedule("0 10 * * *") // Tous les jours à 10h
    .timeZone("Europe/Paris")
    .onRun(async (context) => {
        const myUid = "VotreUIDIci"; // Remplacez par votre propre UID
        await processVaccinationReminders(myUid);
    });

// Fonction callable pour tester les rappels manuellement (dans la région europe-west1)
exports.triggerVaccinationReminder = functions
    .region("europe-west1") // Région d'exécution
    .https.onCall(async (data, context) => {
        if (!context.auth) {
            throw new functions.https.HttpsError(
                "unauthenticated",
                "Vous devez être authentifié pour exécuter cette fonction.",
            );
        }

        const userId = context.auth.uid; // UID de l'utilisateur actuel

        try {
            await processVaccinationReminders(userId); // Passe l'UID de l'utilisateur
            return {success: true, message: "Vaccination reminders executed successfully."};
        } catch (error) {
            console.error("❌ Erreur lors de l'exécution :", error);
            return {success: false, message: "Erreur lors de l'exécution des rappels."};
        }
    });


// Fonction utilitaire pour obtenir le token FCM de l'utilisateur
// eslint-disable-next-line require-jsdoc
async function getUserFcmToken(userId) {
    const userSnapshot = await admin.firestore().collection("users").doc(userId).get();
    const userData = userSnapshot.data();

    if (!userData) {
        console.warn(`⚠️ Aucune donnée trouvée pour l'utilisateur ${userId}`);
        return {token: null, platform: null};
    }

    if (userData.apnsToken) {
        return {token: userData.apnsToken, platform: "ios"};
    } else if (userData.fcmToken) {
        return {token: userData.fcmToken, platform: "android"};
    } else {
        console.warn(`⚠️ Aucun token trouvé pour l'utilisateur ${userId}`);
        return {token: null, platform: null};
    }
}


// Fonction utilitaire pour envoyer une notification
// eslint-disable-next-line require-jsdoc
async function sendNotification({token, platform, title, body}) {
    if (!token) {
        console.error("❌ Aucun token fourni, notification annulée.");
        return;
    }

    const message = {
        notification: {
            title,
            body,
        },
    };

    if (platform === "android") {
        message.token = token;
        message.android = {notification: {sound: "default"}};
    } else if (platform === "ios") {
        message.token = token;
        message.apns = {
            payload: {
                aps: {
                    alert: {
                        title,
                        body,
                    },
                    sound: "default",
                    badge: 1,
                },
            },
        };
    }

    try {
        await admin.messaging().send(message);
        console.log(`✅ Notification envoyée au token ${platform}: ${token}`);
    } catch (error) {
        console.error(`❌ Erreur d'envoi de la notification :`, error);
    }
}

exports.sendPushNotification = functions.region("europe-west1").https.onCall(async (data, context) => {
    const token = data.token; // Le token du destinataire
    const payload = {
        notification: {
            title: "Notification Title",
            body: "This is an example notification",
        },
    };

    try {
        const response = await admin.messaging().sendToDevice(token, payload);
        console.log("Successfully sent message:", response);
        return response;
    } catch (error) {
        console.error("Failed to send message:", error);
        throw new functions.https.HttpsError("unknown", error.message, error);
    }
});
