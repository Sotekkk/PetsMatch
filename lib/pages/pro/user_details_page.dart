import 'package:PetsMatch/pages/eleveur/post/annonce_detail_page.dart';
import 'package:PetsMatch/pages/pro/partenaire.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:url_launcher/url_launcher.dart';
import 'package:PetsMatch/utils.dart';

class UserDetailPage extends StatefulWidget {
  final User user;
  const UserDetailPage({super.key, required this.user});

  @override
  State<UserDetailPage> createState() => _UserDetailPageState();
}

class _UserDetailPageState extends State<UserDetailPage> {
  late final Future<List<Map<String, dynamic>>> _annonces;

  @override
  void initState() {
    super.initState();
    _annonces = _loadAnnonces();
  }

  Future<List<Map<String, dynamic>>> _loadAnnonces() async {
    final rows = await Supabase.instance.client
        .from('annonces')
        .select(
          'id, titre, espece, race, type, type_vente, photos, '
          'animaux_portee, prix, saillie_prix, ville_eleveur, sexe, '
          'nom_eleveur, uid_eleveur, description, registre_type, '
          'date_naissance, date_naissance_animal, '
          'nom_pere, nom_mere, race_pere, race_mere',
        )
        .eq('uid_eleveur', widget.user.uid)
        .eq('statut', 'disponible')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _openMap(String address) async {
    final googleUrl =
        'https://www.google.com/maps/search/?api=1&query=$address';
    final appleUrl = 'https://maps.apple.com/?q=$address';
    if (await canLaunch(googleUrl)) {
      await launch(googleUrl);
    } else if (await canLaunch(appleUrl)) {
      await launch(appleUrl);
    } else {
      throw 'Could not launch maps';
    }
  }

  Future<void> _callPhoneNumber(String phoneNumber) async {
    final telUrl = 'tel:$phoneNumber';
    if (await canLaunch(telUrl)) {
      await launch(telUrl);
    } else {
      throw 'Could not launch phone app';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: Column(
            children: [
              SizedBox(
                width: UTILS.widthReference(context),
                height: UTILS.calculHeight(141, UTILS.heightReference(context)),
                child: Stack(
                  children: [
                    Image.asset(
                      'assets/deco/arrondideco.png',
                      fit: BoxFit.cover,
                      width: UTILS.calculWidth(151, UTILS.widthReference(context)),
                      height: UTILS.calculHeight(141, UTILS.heightReference(context)),
                      color: const Color(0xFFA7C79A),
                      colorBlendMode: BlendMode.srcIn,
                    ),
                    Positioned(
                      top: UTILS.calculHeight(53, UTILS.heightReference(context)),
                      left: UTILS.calculWidth(40, UTILS.widthReference(context)),
                      right: UTILS.calculWidth(40, UTILS.widthReference(context)),
                      child: Align(
                        alignment: Alignment.center,
                        child: Text(
                          widget.user.nameElevage,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                            fontSize: UTILS.calculWidth(20, UTILS.widthReference(context)),
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                    Positioned(
                      top: UTILS.calculHeight(42, UTILS.heightReference(context)),
                      left: UTILS.calculWidth(10, UTILS.widthReference(context)),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.black),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.black,
                    radius: 39.5,
                    backgroundImage: widget.user.profilePictureUrlElevage.isNotEmpty
                        ? NetworkImage(widget.user.profilePictureUrlElevage)
                        : const AssetImage('assets/default_pp.png') as ImageProvider,
                  ),
                  SizedBox(height: UTILS.calculHeight(13, UTILS.heightReference(context))),
                  Align(
                    alignment: Alignment.center,
                    child: Text(
                      'Photo de profil',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Galey',
                        fontWeight: FontWeight.w500,
                        fontSize: UTILS.calculWidth(20, UTILS.widthReference(context)),
                      ),
                    ),
                  ),
                  if (widget.user.adressElevage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.location_on,
                              size: UTILS.calculHeight(18, UTILS.heightReference(context)),
                              color: Colors.black),
                          SizedBox(width: UTILS.calculWidth(8, UTILS.widthReference(context))),
                          GestureDetector(
                            onTap: () => _openMap(widget.user.adressElevage),
                            child: SizedBox(
                              width: UTILS.widthReference(context) * 0.6,
                              child: Text(
                                widget.user.adressElevage,
                                style: TextStyle(
                                  fontFamily: 'Galey',
                                  fontWeight: FontWeight.w400,
                                  fontSize: UTILS.calculWidth(16, UTILS.widthReference(context)),
                                ),
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (widget.user.numeroElevage.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone,
                              size: UTILS.calculHeight(18, UTILS.heightReference(context)),
                              color: Colors.black),
                          SizedBox(width: UTILS.calculWidth(8, UTILS.widthReference(context))),
                          GestureDetector(
                            onTap: () => _callPhoneNumber(widget.user.numeroElevage),
                            child: SizedBox(
                              width: UTILS.widthReference(context) * 0.6,
                              child: Text(
                                widget.user.numeroElevage,
                                style: TextStyle(
                                  fontFamily: 'Galey',
                                  fontWeight: FontWeight.w400,
                                  fontSize: UTILS.calculWidth(16, UTILS.widthReference(context)),
                                ),
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(height: UTILS.calculHeight(13, UTILS.heightReference(context))),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    future: _annonces,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        );
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Erreur : ${snapshot.error}'),
                        );
                      }
                      final annonces = snapshot.data ?? [];
                      if (annonces.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            'Aucune annonce à afficher.',
                            style: TextStyle(
                              fontFamily: 'Galey',
                              fontWeight: FontWeight.w400,
                              fontSize: UTILS.calculWidth(16, UTILS.widthReference(context)),
                            ),
                          ),
                        );
                      }
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: annonces.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 5.0,
                          mainAxisSpacing: 5.0,
                        ),
                        itemBuilder: (context, index) {
                          final annonce = annonces[index];
                          final photos = (annonce['photos'] as List?)?.cast<String>() ?? [];
                          final thumb = photos.isNotEmpty ? photos.first : null;
                          return GestureDetector(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AnnonceDetailPage(
                                    annonceId: annonce['id'].toString(),
                                    initialData: annonce,
                                  ),
                                ),
                              );
                            },
                            child: thumb != null
                                ? Image.network(thumb, fit: BoxFit.cover)
                                : Container(
                                    color: const Color(0xFFE4E7E2),
                                    child: const Icon(Icons.pets, color: Color(0xFF9CA3AF)),
                                  ),
                          );
                        },
                      );
                    },
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
