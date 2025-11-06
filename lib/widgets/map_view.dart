import 'package:flutter/material.dart';

class MapView extends StatelessWidget {
  const MapView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        "Google Map will be displayed here",
        style: TextStyle(fontSize: 16),
      ),
    );
  }
}
