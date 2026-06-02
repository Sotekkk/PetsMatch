
const stripeFunctions = require("./stripe");
const alertesFunctions = require("./alertes");
const agendaFunctions = require("./agenda");
const chaleursFunctions = require("./chaleurs");
const retraiteFunctions = require("./retraite");
const tachesFunctions = require("./taches");
const santeFunctions = require("./sante");

// Stripe + messagerie
exports.createStripePaymentIntent = stripeFunctions.createStripePaymentIntent;
exports.createStripeSubscription = stripeFunctions.createStripeSubscription;
exports.cancelStripeSubscription = stripeFunctions.cancelStripeSubscription;
exports.stripeWebhook = stripeFunctions.stripeWebhook;
exports.sendNotificationOnNewMessage = stripeFunctions.sendNotificationOnNewMessage;
exports.sendPushNotification = stripeFunctions.sendPushNotification;

// Alertes perdus + likes + trouvés
exports.notifyUsersNearLostAnimal = alertesFunctions.notifyUsersNearLostAnimal;
exports.sendLikeNotification = alertesFunctions.sendLikeNotification;
exports.notifyNearFoundAnimal = alertesFunctions.notifyNearFoundAnimal;
exports.notifyAnimalOwner = alertesFunctions.notifyAnimalOwner;

// Agenda — rappels RDV + notifications RDV + mise-bas
exports.sendRdvReminders = agendaFunctions.sendRdvReminders;
exports.notifyProNewRdv = agendaFunctions.notifyProNewRdv;
exports.sendMiseBasReminders = agendaFunctions.sendMiseBasReminders;

// Chaleurs — alertes quotidiennes éleveurs
exports.sendChaleursNotifications = chaleursFunctions.sendChaleursNotifications;

// Retraite reproductive — alertes J-30 et J-0
exports.sendRetraiteReminders = retraiteFunctions.sendRetraiteReminders;

// Tâches employés — push FCM à l'assignation
exports.notifyTacheAssignee = tachesFunctions.notifyTacheAssignee;

// Santé — rappels vaccins, vermifuges, antiparasitaires (J-7, J-1, J-0)
exports.sendSanteReminders = santeFunctions.sendSanteReminders;
