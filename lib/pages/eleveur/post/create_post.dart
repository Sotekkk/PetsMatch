import 'dart:io';
import 'dart:typed_data';
import 'package:PetsMatch/main.dart';
import 'package:PetsMatch/pages/eleveur/choice_publication.dart';
import 'package:PetsMatch/pages/eleveur/post/details_post.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:carousel_slider/carousel_slider.dart';

class NewPostPage extends StatefulWidget {
  @override
  _NewPostPageState createState() => _NewPostPageState();
}

class _NewPostPageState extends State<NewPostPage> {
  final ImagePicker _picker = ImagePicker();
  List<File> _selectedImages = [];
  final int _maxImages = 4;
  int _currentImageIndex = 0;

  Future<void> _pickImages() async {
    final List<XFile>? pickedFiles = await _picker.pickMultiImage();
    if (pickedFiles != null) {
      List<File> newFiles =
          pickedFiles.map((xfile) => File(xfile.path)).toList();

      if (_selectedImages.length + newFiles.length > _maxImages) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Vous pouvez sélectionner jusqu\'à $_maxImages images.'),
        ));
        return;
      }

      setState(() {
        _selectedImages.addAll(newFiles);
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
      if (_currentImageIndex >= _selectedImages.length) {
        _currentImageIndex = _selectedImages.length - 1;
      }
    });
  }

  Future<void> _uploadImagesToCache() async {
    NewPostClass.mediaStockage = _selectedImages.map((file) {
      return {
        'path': file.path,
        'isPhoto': true,
      };
    }).toList();
  }

  void _goToNextStep() async {
    if (_selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Veuillez sélectionner au moins une image.'),
      ));
      return;
    }

    try {
      await _uploadImagesToCache();

      // 🔐 UID éleveur actuel
      NewPostClass.uidEleveur = User_Info.uid;

      // 👉 Naviguer vers la suite
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DetailsPostCreation(),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur lors de l\'upload des images.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(color: Colors.white),
        title: Text(
          'Nouveau post',
          style: TextStyle(
              fontFamily: 'Galey',
              fontWeight: FontWeight.w500,
              color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: _goToNextStep,
            child: Text(
              'Suivant',
              style: TextStyle(
                fontFamily: 'Galey',
                fontWeight: FontWeight.w500,
                color: Color(0xFFA7C79A),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          _selectedImages.isNotEmpty
              ? CarouselSlider.builder(
                  itemCount: _selectedImages.length,
                  options: CarouselOptions(
                    height: double.infinity,
                    viewportFraction: 1.0,
                    enableInfiniteScroll: false,
                    onPageChanged: (index, reason) {
                      setState(() => _currentImageIndex = index);
                    },
                  ),
                  itemBuilder: (context, index, _) {
                    return Container(
                      color: Colors.black,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(
                            child: Image.file(
                              _selectedImages[index],
                              fit: BoxFit.contain,
                            ),
                          ),
                          Positioned(
                            top: 40,
                            right: 20,
                            child: GestureDetector(
                              onTap: () => _removeImage(index),
                              child: Container(
                                padding: EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black54,
                                ),
                                child: Icon(Icons.close,
                                    color: Colors.white, size: 24),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                )
              : Center(
                  child: Text(
                    'Aucune image sélectionnée',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: ElevatedButton.icon(
                onPressed:
                    _selectedImages.length < _maxImages ? _pickImages : null,
                icon: Icon(Icons.add_photo_alternate),
                label: Text(
                    '${_selectedImages.length}/$_maxImages - Ajouter des images'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedImages.length < _maxImages
                      ? Color(0xFFA7C79A)
                      : Colors.grey.shade300,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: Colors.grey.shade300,
                  disabledForegroundColor: Colors.black87,
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
