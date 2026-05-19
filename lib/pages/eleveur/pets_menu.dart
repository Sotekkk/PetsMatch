import 'package:PetsMatch/pages/eleveur/all_register_pet.dart';
import 'package:PetsMatch/pages/eleveur/cat_fiche.dart';
import 'package:PetsMatch/pages/eleveur/dog_fiche.dart';
import 'package:flutter/material.dart';
import 'package:PetsMatch/utils.dart';

class PetsMenu extends StatefulWidget {
  const PetsMenu({super.key});

  @override
  State<PetsMenu> createState() => _PetsMenuState();
}

class _PetsMenuState extends State<PetsMenu> {
  @override

  void CreateDogFiche() {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => DogFiche()),
      );
  }
  void CreateCatFiche() {
     Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => CatFiche()),
      );
  }
    void  ConsultPetFiche() {
     Navigator.of(context).push(
        MaterialPageRoute(builder: (context) => AllPetRegister()),
      );
  }
  Widget build(BuildContext context) {
   return Scaffold(
        body: Center(
            child: Container(
                    child: Column(children: [
                  SizedBox(
                      width: UTILS.widthReference(context),
                      height: UTILS.calculHeight(
                          105,
                          UTILS.heightReference(
                              context)), // Hauteur fixe pour le Stack
                      child: Stack(children: [
                        Image.asset('assets/deco/arrondi_rose_2.png',
              color: const Color(0xFFA7C79A),
              colorBlendMode: BlendMode.srcIn,
                          fit: BoxFit.cover,
                          width: UTILS.calculWidth(211, UTILS.widthReference(context)),
                          height: UTILS.calculHeight(
                              104,
                              UTILS.heightReference(
                                  context)), // Hauteur fixe pour le Stack
                        ),
                        Positioned(
                          top: UTILS.calculHeight(42, UTILS.heightReference(context)),
                          left:  UTILS.calculWidth(10, UTILS.widthReference(context)),
                          child :IconButton(
                          icon: Icon(Icons.arrow_back, color: Colors.black), // Icône de la flèche noire
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                        )),
                        Positioned(
                          top: UTILS.calculHeight(
                              53, UTILS.heightReference(context)),
                          left: 0,
                          right:
                              0, // Assurez-vous que left et right sont définis à 0 pour permettre au texte de centrer exactement
                          child: Align(
                            alignment: Alignment.center,
                            child: Text(
                              'MENU ANIMAUX',
                              textAlign: TextAlign
                                  .center, // Assurez-vous d'utiliser textAlign pour garantir que le texte est centré à l'intérieur du Text widget.
                              style: TextStyle(
                                fontFamily: 'Galey',
                                fontWeight: FontWeight.w500,
                                fontSize: UTILS.calculWidth(
                                    20, UTILS.widthReference(context)),
                              ),
                            ),
                          ),
                        )
                      ]
                    )
                  ),
                  SizedBox(
                      height: UTILS.calculHeight(100, UTILS.heightReference(context))),
       
                  DogButton(
                    title: 'Créer une fiche chien',
                    imagePath:
                        'assets/page/cute_dog.png', // Ajoutez votre image appropriée
                    test: CreateDogFiche,
                  ),
                   SizedBox(
                      height: UTILS.calculHeight(61, UTILS.heightReference(context))),
                  DogButton(
                    title: 'Créer une fiche chat',
                    imagePath:
                        'assets/page/cute_cat.png', // Ajoutez votre image appropriée
                    test: CreateCatFiche,
                  ),
                   SizedBox(
                      height: UTILS.calculHeight(61, UTILS.heightReference(context))),
                   DogButton(
                    title: 'Vos animaux',
                    imagePath:
                        'assets/page/cute_family_pets.png', // Ajoutez votre image appropriée
                    test: ConsultPetFiche,
                  ),
                ]
              )
            )
          )
        );
  }
}




class DogButton extends StatelessWidget {
  final String title;
  final String imagePath;
  final VoidCallback  test;
  const DogButton({
    Key? key,
    required this.title,
    required this.test,
    required this.imagePath,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: UTILS.calculWidth(368.37, UTILS.widthReference(context)),
      height: UTILS.calculHeight(138, UTILS.heightReference(context)),
      child: InkWell(
        borderRadius: BorderRadius.circular(500),
        // splashColor: Color.fromARGB(255, 255, 255, 255), // Personnalisation de la couleur de l'animation d'onde
        // highlightColor: Color(0xFFF8F8F6).withOpacity(0.5),
        onTap: test,
        child: Padding(
          padding: const EdgeInsets.all(0.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(imagePath,
                  width: UTILS.calculWidth(136, UTILS.widthReference(context)),
                  height:
                      UTILS.calculHeight(136, UTILS.heightReference(context))),
              SizedBox(
                  width: UTILS.calculWidth(225, UTILS.widthReference(context)),
                  height: UTILS.calculWidth(100, UTILS.widthReference(context)),
                  child: Center(
                    child: 
                      Text(
                        title,
                        style: TextStyle(
                            fontSize: UTILS.calculWidth(
                                20, UTILS.widthReference(context)),
                            fontFamily: 'Galey',
                            color: Color.fromARGB(255, 0, 0, 0),
                            fontWeight: FontWeight.w500),
                      ),

                    
                  ))
            ],
          ),
        ),
      ),
    );
  }
}

