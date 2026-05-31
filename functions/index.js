
const stripeFunctions = require("./stripe");
const alertesFunctions = require("./alertes");
const agendaFunctions = require("./agenda");
const chaleursFunctions = require("./chaleurs");
const testFunctions = require("./stripe");

// Export your Stripe functions
exports.createStripePaymentIntent = stripeFunctions.createStripePaymentIntent;
exports.helloWorld = testFunctions.helloWorld;
exports.createStripeSubscription = stripeFunctions.createStripeSubscription;
exports.cancelStripeSubscription = stripeFunctions.cancelStripeSubscription;
exports.stripeWebhook = stripeFunctions.stripeWebhook;
exports.sendNotificationOnNewMessage = stripeFunctions.sendNotificationOnNewMessage;
exports.sendVaccinationReminders = stripeFunctions.sendVaccinationReminders;
exports.triggerVaccinationReminder = stripeFunctions.triggerVaccinationReminder;
exports.sendPushNotification = stripeFunctions.sendPushNotification;

// Alertes perdus + likes + trouvés
exports.notifyUsersNearLostAnimal = alertesFunctions.notifyUsersNearLostAnimal;
exports.sendLikeNotification = alertesFunctions.sendLikeNotification;
exports.notifyNearFoundAnimal = alertesFunctions.notifyNearFoundAnimal;
exports.notifyAnimalOwner = alertesFunctions.notifyAnimalOwner;

// Agenda — rappels RDV + notifications RDV
exports.sendRdvReminders = agendaFunctions.sendRdvReminders;
exports.notifyProNewRdv = agendaFunctions.notifyProNewRdv;

// Chaleurs — alertes quotidiennes éleveurs
exports.sendChaleursNotifications = chaleursFunctions.sendChaleursNotifications;
