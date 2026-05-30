
const stripeFunctions = require("./stripe");
const alertesFunctions = require("./alertes");
const agendaFunctions = require("./agenda");
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

// Alertes perdus + likes
exports.notifyUsersNearLostAnimal = alertesFunctions.notifyUsersNearLostAnimal;
exports.sendLikeNotification = alertesFunctions.sendLikeNotification;

// Agenda — rappels RDV
exports.sendRdvReminders = agendaFunctions.sendRdvReminders;
