import 'package:PetsMatch/pages/pro/partenaire.dart';
import 'package:PetsMatch/pages/pro/user_details_page.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geocoding/geocoding.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:PetsMatch/utils.dart';



class FirebaseServiceS {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<List<User>> getUsers() async {
    QuerySnapshot querySnapshot = await _firestore
        .collection('users')
        .where('catPro', isEqualTo: 'Santé animal')
        .get();

    return querySnapshot.docs.map((doc) {
      return User.fromMap(doc.data() as Map<String, dynamic>, doc.id);
    }).toList();
  }
}

class SanteAnimal extends StatefulWidget {
  @override
  _SanteAnimalState createState() => _SanteAnimalState();
}

class _SanteAnimalState extends State<SanteAnimal> {
  List<User> users = [];
  List<User> filteredUsers = [];
  List<User> partners = [];
  List<User> nonPartners = [];
  String selectedProfession = '';
  String searchQuery = '';

  final List<String> professions = [
      'Vétérinaire',
      'Auxiliaire de santé',
      'Spécialistes de santé',
  ];

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  void fetchData() async {
    FirebaseServiceS firebaseService = FirebaseServiceS();
    List<User> allUsers = await firebaseService.getUsers();
    setState(() {
      users = allUsers;
      filteredUsers = allUsers;
      partners = allUsers.where((user) => user.isPartenaire).toList();
      nonPartners = allUsers.where((user) => !user.isPartenaire).toList();
    });
  }

  void filterUsers() {
    setState(() {
      filteredUsers = users.where((user) {
        bool matchesProfession = selectedProfession.isEmpty ||
            user.professionPro == selectedProfession;
        bool matchesSearch = searchQuery.isEmpty ||
            user.nameElevage.toLowerCase().contains(searchQuery.toLowerCase());
        return matchesProfession && matchesSearch;
      }).toList();
      partners = filteredUsers.where((user) => user.isPartenaire).toList();
      nonPartners = filteredUsers.where((user) => !user.isPartenaire).toList();
    });
  }

  Future<LatLng> getLatLngFromAddress(String address) async {
    List<Location> locations = await locationFromAddress(address);
    if (locations.isNotEmpty) {
      return LatLng(locations.first.latitude, locations.first.longitude);
    }
    return LatLng(0, 0); // Valeur par défaut si l'adresse n'est pas trouvée
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: UTILS.widthReference(context),
            height: UTILS.calculHeight(105, UTILS.heightReference(context)),
            child: Stack(children: [
              Image.asset(
                'assets/deco/arrondi_rose_2.png',
                fit: BoxFit.cover,
                width: UTILS.calculWidth(211, UTILS.widthReference(context)),
                height: UTILS.calculHeight(104, UTILS.heightReference(context)),
              ),
              Positioned(
                top: UTILS.calculHeight(42, UTILS.heightReference(context)),
                left: UTILS.calculWidth(10, UTILS.widthReference(context)),
                child: IconButton(
                  icon: Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () {
                    Navigator.pop(context);
                  },
                ),
              ),
              Positioned(
                top: UTILS.calculHeight(53, UTILS.heightReference(context)),
                left: 0,
                right: 0,
                child: Align(
                  alignment: Alignment.center,
                  child: Text(
                    'Bien être',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Galey',
                      fontWeight: FontWeight.w500,
                      fontSize: UTILS.calculWidth(20, UTILS.widthReference(context)),
                    ),
                  ),
                ),
              )
            ]),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: UTILS.calculWidth(29, UTILS.widthReference(context))),
            child: Row(
              children: [
                Container(
                  width: UTILS.calculWidth(360, UTILS.widthReference(context)),
                  height: UTILS.calculHeight(53, UTILS.heightReference(context)),
                  decoration: BoxDecoration(
                    color: Color.fromARGB(255, 252, 207, 200),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Recherche',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: UTILS.calculWidth(10, UTILS.widthReference(context)),
                          vertical: UTILS.calculHeight(15, UTILS.heightReference(context))),
                    ),
                    onChanged: (value) {
                      searchQuery = value;
                      filterUsers();
                    },
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: UTILS.calculHeight(15, UTILS.heightReference(context))),
          Container(
            height: UTILS.calculHeight(53, UTILS.heightReference(context)),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: professions.map((profession) {
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      if (selectedProfession == profession) {
                        selectedProfession = ''; // Désélectionne le filtre
                      } else {
                        selectedProfession = profession; // Sélectionne le filtre
                      }
                      filterUsers();
                    });
                  },
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: UTILS.calculWidth(5, UTILS.widthReference(context))),
                    padding: EdgeInsets.symmetric(horizontal: UTILS.calculWidth(8, UTILS.widthReference(context))),
                    decoration: BoxDecoration(
                      color: selectedProfession == profession
                          ? Color(0xFF1E2025) // Couleur sélectionnée
                          : Color.fromARGB(255, 252, 207, 200), // Couleur non sélectionnée
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.location_on, size: UTILS.calculWidth(15, UTILS.widthReference(context)), color: selectedProfession == profession ? Colors.white : Colors.black),
                        SizedBox(width: UTILS.calculWidth(5, UTILS.widthReference(context))),
                        Text(
                          profession,
                          style: TextStyle(
                            fontSize: UTILS.calculWidth(17, UTILS.widthReference(context)),
                            color: selectedProfession == profession ? Colors.white : Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          SizedBox(height: UTILS.calculHeight(15, UTILS.heightReference(context))),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: UTILS.calculWidth(29, UTILS.widthReference(context))),
            child: Text(
              'Nos partenaires',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                fontSize: UTILS.calculWidth(17, UTILS.widthReference(context)),
              ),
            ),
          ),
          SizedBox(height: UTILS.calculHeight(17, UTILS.heightReference(context))),
          Container(
            height: UTILS.calculHeight(156, UTILS.heightReference(context)),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: partners.map((user) {
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => UserDetailPage(user: user)),
                    );
                  },
                  child: Container(
                    width: UTILS.calculWidth(216, UTILS.widthReference(context)),
                    height: UTILS.calculHeight(156, UTILS.heightReference(context)),
                    margin: EdgeInsets.symmetric(horizontal: UTILS.calculWidth(8, UTILS.widthReference(context))),
                    decoration: BoxDecoration(
                      color: Color(0xFF1E2025),
                      borderRadius: BorderRadius.circular(15.0),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(UTILS.calculWidth(8, UTILS.widthReference(context))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                        backgroundColor: Colors.black,
                                backgroundImage: NetworkImage(user.profilePictureUrlElevage),
                                radius: UTILS.calculWidth(16, UTILS.widthReference(context)),
                              ),
                              Spacer(),
                              Icon(Icons.location_on, color: Colors.white, size: UTILS.calculWidth(25, UTILS.widthReference(context))),
                            ],
                          ),
                          SizedBox(height: UTILS.calculHeight(8, UTILS.heightReference(context))),
                          Text(
                            user.nameElevage,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: UTILS.calculWidth(17, UTILS.widthReference(context)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          SizedBox(height: UTILS.calculHeight(4, UTILS.heightReference(context))),
                          Row(
                            children: [
                              Icon(Icons.business, color: Colors.white, size: UTILS.calculWidth(15, UTILS.widthReference(context))),
                              SizedBox(width: UTILS.calculWidth(4, UTILS.widthReference(context))),
                              Expanded(
                                child: Text(
                                  user.professionPro,
                                  style: TextStyle(
                                    color: Colors.white,
                                    overflow: TextOverflow.ellipsis,
                                    fontSize: UTILS.calculWidth(8, UTILS.widthReference(context)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: UTILS.calculHeight(4, UTILS.heightReference(context))),
                          Row(
                            children: [
                              Icon(Icons.phone, color: Colors.white, size: UTILS.calculWidth(15, UTILS.widthReference(context))),
                              SizedBox(width: UTILS.calculWidth(4, UTILS.widthReference(context))),
                              Expanded(
                                child: Text(
                                  '${user.codeISOElevage} ${user.numeroElevage}',
                                  style: TextStyle(
                                    color: Colors.white,
                                    overflow: TextOverflow.ellipsis,
                                    fontSize: UTILS.calculWidth(8, UTILS.widthReference(context)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: UTILS.calculHeight(4, UTILS.heightReference(context))),
                          Row(
                            children: [
                              Icon(Icons.location_on, color: Colors.white, size: UTILS.calculWidth(15, UTILS.widthReference(context))),
                              SizedBox(width: UTILS.calculWidth(4, UTILS.widthReference(context))),
                              Expanded(
                                child: Text(
                                  user.adressElevage,
                                  style: TextStyle(
                                    color: Colors.white,
                                    overflow: TextOverflow.ellipsis,
                                    fontSize: UTILS.calculWidth(8, UTILS.widthReference(context)),
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
              }).toList(),
            ),
          ),
          SizedBox(height: UTILS.calculHeight(31, UTILS.heightReference(context))),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: UTILS.calculWidth(29, UTILS.widthReference(context))),
            child: Text(
              'Les Prestataires',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontWeight: FontWeight.w600,
                fontSize: UTILS.calculWidth(17, UTILS.widthReference(context)),
              ),
            ),
          ),    
          SizedBox(height: UTILS.calculHeight(11, UTILS.heightReference(context))),
          Expanded(
            child: ListView(
              children: nonPartners.map((user) {
                return GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => UserDetailPage(user: user)),
                    );
                  },
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: UTILS.calculWidth(16, UTILS.widthReference(context)), vertical: UTILS.calculHeight(8, UTILS.heightReference(context))),
                    width: UTILS.calculWidth(382, UTILS.widthReference(context)),
                    height: UTILS.calculHeight(60, UTILS.heightReference(context)),
                    decoration: BoxDecoration(
                      color: Color(0xFFFCCFC8),
                      borderRadius: BorderRadius.circular(15.0),
                    ),
                    child: Row(
                      children: [
                        Padding(
                          padding: EdgeInsets.all(UTILS.calculWidth(8, UTILS.widthReference(context))),
                          child: CircleAvatar(
                        backgroundColor: Colors.black,
                            backgroundImage: NetworkImage(user.profilePictureUrlElevage),
                            radius: UTILS.calculWidth(24, UTILS.widthReference(context)),
                          ),
                        ),
                        SizedBox(width: UTILS.calculWidth(16, UTILS.widthReference(context))),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                user.nameElevage,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: UTILS.calculWidth(16, UTILS.widthReference(context)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                user.descEntreprise,
                                style: TextStyle(
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.only(right: UTILS.calculWidth(8, UTILS.widthReference(context))),
                          child: Icon(Icons.arrow_forward_ios, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
