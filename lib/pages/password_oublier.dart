import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:PetsMatch/utils.dart';

class PasswordResetPage extends StatefulWidget {
  @override
  _PasswordResetPageState createState() => _PasswordResetPageState();
}

class _PasswordResetPageState extends State<PasswordResetPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  void _resetPassword() async {
    if (_formKey.currentState!.validate()) {
      try {
        await _auth.sendPasswordResetEmail(email: _emailController.text);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Un e-mail de réinitialisation a été envoyé à ${_emailController.text}')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur lors de la réinitialisation du mot de passe')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      backgroundColor: Color(0xFFFFF1E3), // Couleur de fond de la page
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Text(
                'Mot de passe oublié',
                style: TextStyle(
                  fontSize: UTILS.calculHeight(24, UTILS.heightReference(context)),
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
              SizedBox(height: UTILS.calculHeight(10, UTILS.heightReference(context))),
              Text(
                'entrez votre email pour recevoir un email pour restaurer votre mot de passe',
                style: TextStyle(
                  fontSize: UTILS.calculHeight(16, UTILS.heightReference(context)),
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: UTILS.calculHeight(30, UTILS.heightReference(context))),
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.email, color: Colors.black),
                  hintText: 'Email',
                  hintStyle: TextStyle(color: Colors.black),
                  filled: true,
                  fillColor: Color.fromARGB(178, 250, 192, 187), // Couleur du champ de texte
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30.0),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: TextStyle(color: Colors.black),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Veuillez entrer votre adresse e-mail';
                  }
                  if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                    return 'Veuillez entrer une adresse e-mail valide';
                  }
                  return null;
                },
              ),
              SizedBox(height: UTILS.calculHeight(20, UTILS.heightReference(context))),
              ElevatedButton(
                onPressed: _resetPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFFFF8484), // Couleur du bouton
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30.0),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                ),
                child: Text(
                  'Envoyez',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: UTILS.calculHeight(16, UTILS.heightReference(context)),
                  ),
                ),
              ),
              SizedBox(height: UTILS.calculHeight(20, UTILS.heightReference(context))),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Vous avez déjà un compte?',
                    style: TextStyle(color: Colors.black),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: Text(
                      's\'identifier',
                      style: TextStyle(
                        color: Color(0xFFFF8484), // Couleur du texte du bouton
                        decoration: TextDecoration.underline,
                        decorationColor: Color(0xFFFF8484),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
