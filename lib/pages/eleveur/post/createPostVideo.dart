import 'dart:io';
import 'dart:typed_data';
import 'package:PetsMatch/pages/eleveur/choice_publication.dart';
import 'package:PetsMatch/pages/eleveur/post/details_post.dart';
import 'package:PetsMatch/utils.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:video_player/video_player.dart';
import 'package:PetsMatch/main.dart';


class NewVideoPostPage extends StatefulWidget {
  @override
  _NewVideoPostPageState createState() => _NewVideoPostPageState();
}

class _NewVideoPostPageState extends State<NewVideoPostPage> {
  File? _selectedVideoFile;
  List<AssetEntity> _galleryVideos = [];
  List<AssetPathEntity> _albums = [];
  AssetPathEntity? _currentAlbum;
  bool _loading = true;
  String? _errorMessage;
  bool _isUploading = false;
  VideoPlayerController? _videoPlayerController;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _requestPermissionAndLoadAlbums();
  }

  Future<void> _requestPermissionAndLoadAlbums() async {
    var result = await PhotoManager.requestPermissionExtend();
    if (result.isAuth) {
      _loadAlbums();
    } else {
      setState(() {
        _loading = false;
        _errorMessage = 'Permission denied';
      });
      _showLimitedPermissionDialog();
    }
  }

  Future<void> _showLimitedPermissionDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Permission requise',
            style: TextStyle(
              fontFamily: 'Galey',
              fontWeight: FontWeight.w500,
            ),
          ),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Cette application a besoin d\'un accès complet à votre galerie pour sélectionner toutes les vidéos.'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text('Accorder accès complet'),
              onPressed: () async {
                Navigator.of(context).pop();
                PhotoManager.openSetting();
              },
            ),
            TextButton(
              child: Text('Refuser'),
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _loading = false;
                  _errorMessage = 'Permission denied';
                });
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadAlbums() async {
    try {
      List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: RequestType.video,
        hasAll: true,
      );
      setState(() {
        _albums = albums;
        _currentAlbum = albums.first;
        _loadGalleryVideos();
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = "Erreur lors du chargement des albums : $e";
      });
      print("Erreur lors du chargement des albums : $e");
    }
  }

  Future<void> _loadGalleryVideos() async {
    if (_currentAlbum == null) return;
    try {
      List<AssetEntity> videos = await _currentAlbum!.getAssetListPaged(page: 0, size: 100);
      setState(() {
        _galleryVideos = videos;
        _loading = false;
        _errorMessage = null; // Reset error message
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMessage = "Erreur lors du chargement des vidéos : $e";
      });
      print("Erreur lors du chargement des vidéos : $e");
    }
  }

  Future<void> _selectVideo(AssetEntity video) async {
    final file = await video.file;
    if (file != null) {
      setState(() {
        _selectedVideoFile = file;
        _initializeVideoPlayer(file);
      });
    }
  }

  void _initializeVideoPlayer(File file) {
    _videoPlayerController = VideoPlayerController.file(file)
      ..initialize().then((_) {
        _videoPlayerController!.setLooping(true); // Play video in loop
        setState(() {});
        _videoPlayerController!.play();
      });
  }

  Future<void> _uploadVideoToFirebase() async {
    if (_selectedVideoFile == null) return;

    setState(() {
      _isUploading = true;
    });

    String fileName = _selectedVideoFile!.path.split('/').last;
    UploadTask uploadTask = FirebaseStorage.instance
        .ref()
        .child('uploads/$fileName')
        .putFile(_selectedVideoFile!);

    TaskSnapshot taskSnapshot = await uploadTask;
    String downloadURL = await taskSnapshot.ref.getDownloadURL();

    setState(() {
      NewPostClass.mediaStockage = [{'path': downloadURL, 'isPhoto': false, 'isMuted': _isMuted}];
      _isUploading = false;
    });

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DetailsPostCreation(),
      ),
    );
  }

  void _showNoVideoSelectedSnackbar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Aucune vidéo sélectionnée',
          style: TextStyle(
            fontFamily: 'Galey',
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  void _toggleMute() {
    setState(() {
      _isMuted = !_isMuted;
      _videoPlayerController?.setVolume(_isMuted ? 0 : 1);
    });
  }

  void _enterFullScreen() {
    if (_videoPlayerController != null && _videoPlayerController!.value.isInitialized) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenVideoPlayer(
            controller: _videoPlayerController!,
          ),
        ),
      );
    }
  }

  void _clearSelectedVideo() {
    setState(() {
      _selectedVideoFile = null;
      _videoPlayerController?.dispose();
      _videoPlayerController = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color.fromARGB(255, 255, 241, 227), // Fond du Scaffold
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: Center(
          child: Text(
            'Nouveau post vidéo',
            style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w500,
                color: Colors.black), // Couleur du texte pour un bon contraste
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              NewPostClass.uidEleveur = User_Info.uid; // Remplacez par l'UID réel

              if (_selectedVideoFile == null) {
                _showNoVideoSelectedSnackbar();
              } else {
                _uploadVideoToFirebase();
              }
            },
            child: Text(
              'Suivant',
              style: TextStyle(
                  fontFamily: 'Galey',
                  fontWeight: FontWeight.w500,
                  color: Color.fromARGB(255, 250, 192, 187)), // Ajuster si nécessaire
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Container(
                height: UTILS.calculHeight(428, UTILS.heightReference(context)),
                color: Color.fromARGB(255, 255, 241, 227),
                child: _selectedVideoFile != null
                    ? Stack(
                        children: [
                          Center(
                            child: _videoPlayerController != null &&
                                    _videoPlayerController!.value.isInitialized
                                ? AspectRatio(
                                    aspectRatio: _videoPlayerController!.value.aspectRatio,
                                    child: VideoPlayer(_videoPlayerController!),
                                  )
                                : CircularProgressIndicator(),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              icon: Icon(
                                _isMuted ? Icons.volume_off : Icons.volume_up,
                                color: Colors.grey,
                              ),
                              onPressed: _toggleMute,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            left: 8,
                            child: IconButton(
                              icon: Icon(
                                Icons.fullscreen,
                                color: Colors.grey,
                              ),
                              onPressed: _enterFullScreen,
                            ),
                          ),
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: IconButton(
                              icon: Icon(
                                Icons.close,
                                color: Colors.red,
                              ),
                              onPressed: _clearSelectedVideo,
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Text(
                          'Aucune vidéo sélectionnée',
                          style: TextStyle(
                            fontFamily: 'Galey',
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
              ),
              SizedBox(height: 10),
              _buildGallerySelector(),
              Expanded(
                child: _loading
                    ? Center(child: CircularProgressIndicator())
                    : _errorMessage != null
                        ? Center(child: Text(_errorMessage!))
                        : _galleryVideos.isNotEmpty
                            ? GridView.builder(
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 4,
                                  crossAxisSpacing: 4,
                                  mainAxisSpacing: 4,
                                ),
                                itemCount: _galleryVideos.length,
                                itemBuilder: (context, index) {
                                  final video = _galleryVideos[index];
                                  return GestureDetector(
                                    onTap: () async {
                                      _selectVideo(video);
                                    },
                                    child: FutureBuilder<Uint8List?>(
                                      future: video.thumbnailData,
                                      builder: (context, snapshot) {
                                        if (snapshot.connectionState == ConnectionState.done &&
                                            snapshot.data != null) {
                                          return Stack(
                                            fit: StackFit.expand,
                                            children: [
                                              Image.memory(snapshot.data!, fit: BoxFit.cover),
                                            ],
                                          );
                                        } else {
                                          return Center(child: CircularProgressIndicator());
                                        }
                                      },
                                    ),
                                  );
                                },
                              )
                            : Center(child: Text('Aucune vidéo trouvée')),
              ),
            ],
          ),
          if (_isUploading)
            ModalBarrier(
              dismissible: false,
              color: Colors.black45,
            ),
          if (_isUploading)
            Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildGallerySelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            _selectedVideoFile != null ? '1/1' : '0/1',
            style: TextStyle(fontSize: 16),
          ),
          Theme(
            data: Theme.of(context).copyWith(
              canvasColor: Color.fromARGB(0, 250, 192, 187),
            ),
            child: Row(
              children: [
                DropdownButton<AssetPathEntity>(
                  value: _currentAlbum,
                  onChanged: (AssetPathEntity? newValue) {
                    setState(() {
                      _currentAlbum = newValue!;
                      _loadGalleryVideos();
                    });
                  },
                  items: _albums.map<DropdownMenuItem<AssetPathEntity>>((AssetPathEntity album) {
                    return DropdownMenuItem<AssetPathEntity>(
                      value: album,
                      child: Text(album.name),
                    );
                  }).toList(),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    super.dispose();
  }
}

class FullScreenVideoPlayer extends StatelessWidget {
  final VideoPlayerController controller;

  FullScreenVideoPlayer({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: controller.value.isInitialized
            ? AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              )
            : CircularProgressIndicator(),
      ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close, color: Colors.white),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
}
