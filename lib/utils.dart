import 'package:flutter/material.dart';

double widthReferences = 428;
double heightReferences = 926;


class UTILS {
   static double calculWidth(double pixel, double screenWidth) {
    return screenWidth * (pixel / widthReferences);
  }

  static double calculHeight(double pixel, double screenHeight) {
    return screenHeight * (pixel / heightReferences);
  }
  static double heightReference(context) {
    return MediaQuery.of(context).size.height;
  }
    static double widthReference(context) {
    return MediaQuery.of(context).size.width;
  }
}
