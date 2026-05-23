import 'dart:io';
import 'package:PetsMatch/pages/main_feed.dart';
import 'package:PetsMatch/pages/user_details_particulier.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/scheduler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:PetsMatch/utils.dart';
import 'package:PetsMatch/pages/user_detail_page_feed.dart';

class ChatScreen extends StatefulWidget {
  final String conversationId;
  final String eleveurId;

  ChatScreen({required this.conversationId, required this.eleveurId});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final String defaultProfilePictureUrl =
      "https://firebasestorage.googleapis.com/v0/b/petsmatch-eb96d.appspot.com/o/files%2Fdefault_pp.png?alt=media&token=192f3539-c479-44af-bfd8-34b3d836dd60";
  final TextEditingController _controller = TextEditingController();
  final CollectionReference conversations =
      FirebaseFirestore.instance.collection('conversations');
  final ScrollController _scrollController = ScrollController();
  File? _imageFile;

  @override
  void initState() {
    super.initState();
    markAsRead();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  void markAsRead() async {
    String currentUserId = FirebaseAuth.instance.currentUser!.uid;
    DocumentReference conversationRef = FirebaseFirestore.instance
        .collection('conversations')
        .doc(widget.conversationId);

    await conversationRef.update({
      'unreadCount.$currentUserId': 0,
    });
  }

  void _scrollToBottomInstant() {
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  String getFormattedDate(Timestamp timestamp) {
    DateTime messageDate = timestamp.toDate();
    DateTime now = DateTime.now();
    DateTime yesterday = now.subtract(Duration(days: 1));

    if (DateUtils.isSameDay(messageDate, now)) {
      return 'Aujourd\'hui';
    } else if (DateUtils.isSameDay(messageDate, yesterday)) {
      return 'Hier';
    } else {
      return DateFormat('dd MMMM yyyy').format(messageDate);
    }
  }

  void sendMessage(String conversationId, String message, String senderId,
      {String? imageUrl}) async {
    if (message.trim().isEmpty && imageUrl == null) {
      return;
    }

    DocumentReference conversationRef = FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId);

    await conversationRef.collection('messages').add({
      'text': message,
      'senderId': senderId,
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
      if (imageUrl != null) 'imageUrl': imageUrl,
    });

    DocumentSnapshot conversationSnapshot = await conversationRef.get();
    Map<String, dynamic> conversationData =
        conversationSnapshot.data() as Map<String, dynamic>;
    Map<String, dynamic> unreadCount =
        Map<String, dynamic>.from(conversationData['unreadCount'] ?? {});

    for (String participantId in conversationData['participants']) {
      if (participantId != senderId) {
        unreadCount[participantId] = (unreadCount[participantId] ?? 0) + 1;
      }
    }

    await conversationRef.update({
      'unreadCount': unreadCount,
      'lastMessage': message,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Force le défilement après l'envoi
    _scrollToBottomInstant();
  }

  Future<Map<String, dynamic>> getUserInfo(String userId) async {
    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();

      if (!userDoc.exists) {
        print("User document for $userId does not exist.");
        return {
          'name': 'Utilisateur Inconnu',
          'profilePictureUrl': defaultProfilePictureUrl,
          'isElevage': false,
          'isPro': false,
          'description': '',
          'adoptionProject': ''
        };
      }

      var userData = userDoc.data() as Map<String, dynamic>;
      print("User data for $userId: $userData");

      bool isElevage = userData['isElevage'] == true;
      bool isPro = userData['isPro'] == true;

      if (isElevage || isPro) {
        try {
          UserSelected userSelected =
              UserSelected.fromMap(userData, userDoc.id);
          return {
            'user': userSelected,
            'isElevage': isElevage,
            'isPro': isPro,
            'name': userData['nameElevage'] ?? 'Utilisateur Inconnu',
            'profilePictureUrl': userData['profilePictureUrlElevage'] ??
                defaultProfilePictureUrl,
            'description': userData['descEntreprise'] ?? '',
          };
        } catch (e) {
          print("Error creating UserSelected for $userId: $e");
          return {
            'name': 'Utilisateur Inconnu',
            'profilePictureUrl': defaultProfilePictureUrl,
            'isElevage': isElevage,
            'isPro': isPro,
            'description': '',
            'adoptionProject': ''
          };
        }
      } else {
        return {
          'name':
              '${userData['firstname'] ?? ''} ${userData['lastname'] ?? ''}',
          'profilePictureUrl':
              userData['profilePictureUrl'] ?? defaultProfilePictureUrl,
          'isElevage': false,
          'isPro': false,
          'description': userData['desc'] ?? '',
          'adoptionProject': userData['adoptProject'] ?? ''
        };
      }
    } catch (e) {
      print("Error retrieving user info for $userId: $e");
      return {
        'name': 'Utilisateur Inconnu',
        'profilePictureUrl': defaultProfilePictureUrl,
        'isElevage': false,
        'isPro': false,
        'description': '',
        'adoptionProject': ''
      };
    }
  }

  void _navigateToUserDetails(Map<String, dynamic> userInfo) {
    if (userInfo['isElevage'] || userInfo['isPro']) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserDetailPageFeed(
            user: userInfo['user'] as UserSelected,
          ),
        ),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UserParticulierFeedDetails(
            profilePictureUrl: userInfo['profilePictureUrl'],
            description: userInfo['description'],
            adoptionProject: userInfo['adoptionProject'],
            name: userInfo['name'],
          ),
        ),
      );
    }
  }

  void _showFullScreenImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Color(0xFFA7C79A),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.network(imageUrl, fit: BoxFit.contain),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendImage() async {
    PermissionStatus photoPermissionStatus = await Permission.photos.status;

    if (photoPermissionStatus.isDenied ||
        photoPermissionStatus.isPermanentlyDenied) {
      photoPermissionStatus = await Permission.photos.request();
    }

    if (photoPermissionStatus.isGranted) {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile != null) {
        String fileName = DateTime.now().millisecondsSinceEpoch.toString();
        Reference storageRef =
            FirebaseStorage.instance.ref().child('chat_images').child(fileName);

        UploadTask uploadTask = storageRef.putFile(File(pickedFile.path));
        TaskSnapshot snapshot = await uploadTask;
        String downloadUrl = await snapshot.ref.getDownloadURL();

        sendMessage(
            widget.conversationId, '', FirebaseAuth.instance.currentUser!.uid,
            imageUrl: downloadUrl);
      } else {
        print('Aucun fichier sélectionné.');
      }
    } else if (photoPermissionStatus.isPermanentlyDenied) {
      print(
          'Permission d\'accès aux photos refusée définitivement. Redirection vers les paramètres.');
      openAppSettings();
    } else {
      print('Permission d\'accès à la galerie refusée ou limitée.');
    }
  }

  Future<void> _takePhoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera);

    if (pickedFile != null) {
      setState(() {
        _imageFile = File(pickedFile.path);
      });
      _showPreviewDialog();
    }
  }

  void _showPreviewDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black,
        content: _imageFile == null
            ? Text("Pas d'image sélectionnée",
                style: TextStyle(color: Colors.white))
            : Image.file(_imageFile!),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _takePhoto();
            },
            child: Text("Reprendre", style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              if (_imageFile != null) {
                String fileName =
                    DateTime.now().millisecondsSinceEpoch.toString();
                Reference storageRef = FirebaseStorage.instance
                    .ref()
                    .child('chat_images')
                    .child(fileName);

                UploadTask uploadTask = storageRef.putFile(_imageFile!);
                TaskSnapshot snapshot = await uploadTask;
                String downloadUrl = await snapshot.ref.getDownloadURL();

                sendMessage(widget.conversationId, '',
                    FirebaseAuth.instance.currentUser!.uid,
                    imageUrl: downloadUrl);
              }
            },
            child: Text("Envoyer", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  String formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) {
      return 'N/A';
    } else {
      return DateFormat('HH:mm').format(timestamp.toDate());
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController
            .animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        )
            .then((_) {
          // Vérifiez à nouveau après un délai si nous sommes vraiment en bas
          if (_scrollController.offset <
              _scrollController.position.maxScrollExtent) {
            Future.delayed(const Duration(milliseconds: 100), () {
              _scrollController.animateTo(
                _scrollController.position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            });
          }
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        shadowColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(1.0), // Hauteur du trait
          child: Container(
            color: Color.fromARGB(57, 0, 0, 0), // Couleur du trait
            height: 3.0, // Épaisseur du trait
          ),
        ),
        title: FutureBuilder<Map<String, dynamic>>(
          future: getUserInfo(widget.eleveurId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return CircularProgressIndicator();
            }
            if (snapshot.hasError || !snapshot.hasData) {
              return Text('Erreur');
            }
            var userInfo = snapshot.data!;
            return GestureDetector(
              onTap: () => _navigateToUserDetails(userInfo),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFFA7C79A),
                    backgroundImage: (userInfo['profilePictureUrl'] != null &&
                            userInfo['profilePictureUrl'] != defaultProfilePictureUrl)
                        ? NetworkImage(userInfo['profilePictureUrl']!) as ImageProvider
                        : null,
                    child: (userInfo['profilePictureUrl'] == null ||
                            userInfo['profilePictureUrl'] == defaultProfilePictureUrl)
                        ? const Icon(Icons.person, color: Colors.white)
                        : null,
                  ),
                  SizedBox(
                      width:
                          UTILS.calculWidth(10, UTILS.widthReference(context))),
                  Text(userInfo['name'] ?? 'Utilisateur Inconnu'),
                ],
              ),
            );
          },
        ),
      ),
      body: Container(
        color: Colors.transparent,
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: conversations
                    .doc(widget.conversationId)
                    .collection('messages')
                    .orderBy('timestamp')
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(child: Text('Aucun message'));
                  }

                  var messages = snapshot.data!.docs;
                  String currentUserId = FirebaseAuth.instance.currentUser!.uid;

                  for (var message in messages) {
                    if (message['senderId'] != currentUserId &&
                        message['isRead'] == false) {
                      FirebaseFirestore.instance
                          .runTransaction((transaction) async {
                        DocumentSnapshot freshSnap =
                            await transaction.get(message.reference);
                        transaction
                            .update(freshSnap.reference, {'isRead': true});
                      });
                    }
                  }

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollToBottom();
                  });

                  return ListView.builder(
                    controller: _scrollController,
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      var message = messages[index];
                      bool isCurrentUser = message['senderId'] == currentUserId;
                      Timestamp? timestamp = message['timestamp'] as Timestamp?;

                      // Identifier le dernier message lu
                      String? lastReadMessageId;
                      for (int i = messages.length - 1; i >= 0; i--) {
                        var msg = messages[i];
                        if (msg['senderId'] == currentUserId &&
                            msg['isRead'] == true) {
                          lastReadMessageId = msg.id;
                          break;
                        }
                      }

                      // Gestion des dates
                      String formattedDate;
                      if (timestamp != null) {
                        formattedDate = getFormattedDate(timestamp);
                      } else {
                        // Gérer le cas où timestamp est null
                        formattedDate = "Date non disponible";
                        print("Timestamp est null");
                      }
                      String? previousDate;
                      if (index > 0) {
                        previousDate = getFormattedDate(
                            messages[index - 1]['timestamp'] as Timestamp);
                      }
                      bool showDateSeparator = (previousDate != formattedDate);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Ajouter un séparateur de date
                          if (showDateSeparator)
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
                              child: Center(
                                child: Text(
                                  formattedDate,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),

                          // Affichage du message
                          Align(
                            alignment: isCurrentUser
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Column(
                              crossAxisAlignment: isCurrentUser
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: EdgeInsets.symmetric(
                                    vertical: UTILS.calculHeight(
                                        5, UTILS.heightReference(context)),
                                    horizontal: UTILS.calculWidth(
                                        8, UTILS.widthReference(context)),
                                  ),
                                  padding: EdgeInsets.all(UTILS.calculHeight(
                                      10, UTILS.heightReference(context))),
                                  decoration: BoxDecoration(
                                    color: isCurrentUser
                                        ? Color(0xFFA7C79A)
                                        : Color(0xFF5F9EAA),
                                    borderRadius: isCurrentUser
                                        ? BorderRadius.only(
                                            topLeft: Radius.circular(
                                                UTILS.calculHeight(
                                                    10,
                                                    UTILS.heightReference(
                                                        context))),
                                            topRight: Radius.circular(
                                                UTILS.calculHeight(
                                                    10,
                                                    UTILS.heightReference(
                                                        context))),
                                            bottomLeft: Radius.circular(
                                                UTILS.calculHeight(
                                                    10,
                                                    UTILS.heightReference(
                                                        context))),
                                          )
                                        : BorderRadius.only(
                                            topLeft: Radius.circular(
                                                UTILS.calculHeight(
                                                    10,
                                                    UTILS.heightReference(
                                                        context))),
                                            topRight: Radius.circular(
                                                UTILS.calculHeight(
                                                    10,
                                                    UTILS.heightReference(
                                                        context))),
                                            bottomRight: Radius.circular(
                                                UTILS.calculHeight(
                                                    10,
                                                    UTILS.heightReference(
                                                        context))),
                                          ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if ((message['text'] ?? '').isNotEmpty)
                                        Text(
                                          message['text'] ?? '',
                                          style: TextStyle(
                                            color: isCurrentUser
                                                ? const Color.fromARGB(
                                                    255, 0, 0, 0)
                                                : Colors.black,
                                          ),
                                        ),
                                      if (message.data() != null &&
                                          (message.data()
                                                  as Map<String, dynamic>)
                                              .containsKey('imageUrl') &&
                                          (message['imageUrl'] ?? '')
                                              .isNotEmpty)
                                        GestureDetector(
                                          onTap: () => _showFullScreenImage(
                                              context,
                                              message['imageUrl'] ?? ''),
                                          child: Image.network(
                                            message['imageUrl'] ?? '',
                                            width: UTILS.calculWidth(
                                                MediaQuery.of(context)
                                                        .size
                                                        .width /
                                                    3,
                                                UTILS.widthReference(context)),
                                            height: UTILS.calculHeight(
                                                MediaQuery.of(context)
                                                        .size
                                                        .height /
                                                    3,
                                                UTILS.heightReference(context)),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      SizedBox(
                                          height: UTILS.calculHeight(5,
                                              UTILS.heightReference(context))),
                                      Text(
                                        formatTimestamp(timestamp),
                                        style: TextStyle(
                                          color: isCurrentUser
                                              ? const Color.fromARGB(
                                                  179, 0, 0, 0)
                                              : Colors.black54,
                                          fontSize: UTILS.calculHeight(10,
                                              UTILS.heightReference(context)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isCurrentUser &&
                                    message.id == lastReadMessageId)
                                  Padding(
                                    padding: EdgeInsets.only(top: 5),
                                    child: Text(
                                      'Vu',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: UTILS.calculHeight(
                                            10, UTILS.heightReference(context)),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            Container(
                color: Color(0xFF1F2A2E),
                child: Padding(
                  padding: EdgeInsets.all(
                      UTILS.calculHeight(8, UTILS.heightReference(context))),
                  child: Row(
                    children: [
                      IconButton(
                        color: Colors.white,
                        icon: Icon(Icons.photo),
                        onPressed: _sendImage,
                      ),
                      IconButton(
                        color: Colors.white,
                        icon: Icon(Icons.camera),
                        onPressed: _takePhoto,
                      ),
                      Expanded(
                        child: TextField(
                          style: TextStyle(color: Colors.white),
                          controller: _controller,
                          decoration: InputDecoration(
                              focusColor: Colors.white,
                              fillColor: Colors.white,
                              hintText: 'Entrer votre message...',
                              hintStyle: TextStyle(color: Colors.white)),
                        ),
                      ),
                      IconButton(
                        color: Colors.white,
                        icon: Icon(Icons.send_rounded),
                        onPressed: () {
                          sendMessage(widget.conversationId, _controller.text,
                              FirebaseAuth.instance.currentUser!.uid);
                          _controller.clear();
                          _scrollToBottom(); // Ensure it scrolls after sending
                        },
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
