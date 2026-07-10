// Transport nodemailer partagé pour l'email transactionnel — les identifiants
// viennent de l'environnement (GMAIL_USER/GMAIL_APP_PASSWORD, .env.local,
// jamais commité), pas codés en dur dans les routes.

import nodemailer from 'nodemailer';

export const mailTransporter = nodemailer.createTransport({
  service: 'gmail',
  auth: {
    user: process.env.GMAIL_USER,
    pass: process.env.GMAIL_APP_PASSWORD,
  },
});

export const MAIL_FROM = `"PetsMatch" <${process.env.GMAIL_USER}>`;
