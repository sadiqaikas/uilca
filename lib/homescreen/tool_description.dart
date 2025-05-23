import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class WhatPowersThisTool extends StatelessWidget {
  const WhatPowersThisTool({super.key});

  // static final Uri _pdfUrl = Uri.parse(
  //   'https://google.com',
  // ); // <-- Replace with your real hosted PDF


static final Uri _pdfUrl = Uri.parse(
  'https://drive.google.com/uc?export=view&id=1GDaqFkkw6X88MM0Zpo1MwfYQdv6Pzq7i',
);


  Future<void> _openPdf() async {
    if (!await launchUrl(_pdfUrl, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $_pdfUrl';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child:TextButton.icon(
  onPressed: _openPdf,
  icon: const Icon(Icons.description_outlined, size: 18),
  label: const Text("View LCA Methodology"),
  style: TextButton.styleFrom(
    foregroundColor: Colors.blueGrey.shade600,
  ),
)
,
    );
  }
}
