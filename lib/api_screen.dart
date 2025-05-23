
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'landing.dart'; // for LandingPage._brandGreen
// import 'api_screen.dart';
// import 'package:earlylca/homescreen/home_screen.dart';

// class ApiScreen extends StatelessWidget {
//   const ApiScreen({Key? key}) : super(key: key);
//   static const _brandGreen = Colors.green;
//   static const _baseUrl = 'https://api.instantlca.com/v1';
//   static const _quickstartCode = '''
// curl -X POST $_baseUrl/lca/estimate \\
//   -H "Content-Type: application/json" \\
//   -H "x-api-key: YOUR_API_KEY" \\
//   -d '{
//     "material": "PLA",
//     "volume_cm3": 150,
//     "surface_area_cm2": 200
//   }'
// ''';

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text(''),
//         backgroundColor: Colors.white,
//         elevation: 0,
//       ),
//       body: SafeArea(
//         child: SingleChildScrollView(
//           padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
//           child: Column(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               // Header
//               Center(
//                 child: Column(
//                   children: [
//                     Image.asset(
//                       'assets/logo.png',
//                       width: 150,
//                       height: 150,
//                     ),
//                     const SizedBox(height: 12),
//                     Text(
//                       'Plug-and-play environmental intelligence for Fusion 360 & beyond',
//                       textAlign: TextAlign.center,
//                       style: TextStyle(
//                         fontSize: 18,
//                         color: _brandGreen,
//                         fontWeight: FontWeight.w600,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               const SizedBox(height: 24),

//               // Problem We’re Solving
//               _AccentCard(
//                 title: 'Problem We’re Solving',
//                 accentColor: _brandGreen,
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: const [
//                     _BulletText('LCA tools are expensive, slow, and siloed'),
//                     _BulletText('Most designers have zero climate-impact insights'),
//                     _BulletText('CAD workflows lack built-in environmental data'),
//                     _BulletText('Barriers of cost & expertise lock teams out'),
//                   ],
//                 ),
//               ),
//               const SizedBox(height: 16),

//               // Our Solution
//               _AccentCard(
//                 title: 'Our Solution',
//                 accentColor: _brandGreen,
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: const [
//                     _BulletText('Lightweight REST API for CAD metadata'),
//                     _BulletText('LLM-powered context completion (process, region)'),
//                     _BulletText('Brightway2 under the hood for scientific rigor'),
//                     _BulletText('Instant carbon, energy & water estimates'),
//                     _BulletText('Plugin-ready for Fusion 360 and any CAD tool'),
//                   ],
//                 ),
//               ),
//               const SizedBox(height: 16),

//               // Quickstart
//               _AccentCard(
//                 title: 'Quickstart',
//                 accentColor: _brandGreen,
//                 child: Stack(
//                   children: [
//                     Container(
//                       width: double.infinity,
//                       padding: const EdgeInsets.all(12),
//                       decoration: BoxDecoration(
//                         color: Colors.grey.shade50,
//                         borderRadius: BorderRadius.circular(8),
//                       ),
//                       child: SelectableText(
//                         _quickstartCode,
//                         style: const TextStyle(
//                           fontFamily: 'SourceCodePro',
//                           fontSize: 14,
//                         ),
//                       ),
//                     ),
//                     Positioned(
//                       top: 8,
//                       right: 8,
//                       child: IconButton(
//                         icon: const Icon(Icons.copy, size: 20),
//                         onPressed: () {
//                           Clipboard.setData(
//                               const ClipboardData(text: _quickstartCode));
//                           ScaffoldMessenger.of(context).showSnackBar(
//                             const SnackBar(content: Text('Copied!')),
//                           );
//                         },
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               const SizedBox(height: 16),

//               // Endpoints
//               _AccentCard(
//                 title: 'Endpoints',
//                 accentColor: _brandGreen,
//                 child: Column(
//                   children: const [
//                     _EndpointTile(
//                       method: 'POST',
//                       path: '/lca/estimate',
//                       description:
//                           'Send material + CAD volume/area → get CO₂e, energy, water & suggestions',
//                     ),
//                     _EndpointTile(
//                       method: 'GET',
//                       path: '/materials',
//                       description:
//                           'List supported materials, footprints & process data',
//                     ),
//                     _EndpointTile(
//                       method: 'GET',
//                       path: '/status',
//                       description: 'Service health & uptime info',
//                     ),
//                   ],
//                 ),
//               ),

//               const SizedBox(height: 32),

//               // CTA
//               Center(
//                 child: ElevatedButton.icon(
//                   onPressed: () {
//                     // TODO: navigate to your key dashboard
//                   },
//                   icon: const Icon(Icons.vpn_key),
//                   label: const Text('Get Your API Key'),
//                   style: ElevatedButton.styleFrom(
//                     backgroundColor: _brandGreen,
//                     padding: const EdgeInsets.symmetric(
//                         horizontal: 24, vertical: 14),
//                     shape: RoundedRectangleBorder(
//                         borderRadius: BorderRadius.circular(8)),
//                   ),
//                 ),
//               ),

//               const SizedBox(height: 24),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

// /// A white card with a colored accent line and title.
// class _AccentCard extends StatelessWidget {
//   final String title;
//   final Widget child;
//   final Color accentColor;

//   const _AccentCard({
//     required this.title,
//     required this.child,
//     required this.accentColor,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       decoration: BoxDecoration(
//         color: Colors.white,
//         border: Border(
//           left: BorderSide(color: accentColor, width: 4),
//         ),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             offset: const Offset(0, 3),
//             blurRadius: 6,
//           ),
//         ],
//         borderRadius: BorderRadius.circular(8),
//       ),
//       padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(title,
//               style: TextStyle(
//                 fontSize: 18,
//                 fontWeight: FontWeight.w600,
//                 color: accentColor,
//               )),
//           const SizedBox(height: 8),
//           child,
//         ],
//       ),
//     );
//   }
// }

// /// A simple bullet point text.
// class _BulletText extends StatelessWidget {
//   final String text;
//   const _BulletText(this.text);
//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 4),
//       child: Row(children: [
//         Icon(Icons.circle, size: 6, color: Colors.black54),
//         const SizedBox(width: 8),
//         Expanded(
//           child: Text(text,
//               style: const TextStyle(fontSize: 15, color: Colors.black87)),
//         ),
//       ]),
//     );
//   }
// }

// /// A little row describing an endpoint.
// class _EndpointTile extends StatelessWidget {
//   final String method, path, description;
//   const _EndpointTile({
//     required this.method,
//     required this.path,
//     required this.description,
//   });

//   Color _methodColor() {
//     switch (method) {
//       case 'GET':
//         return Colors.blue;
//       case 'POST':
//         return Colors.green;
//       case 'PUT':
//       case 'PATCH':
//         return Colors.orange;
//       case 'DELETE':
//         return Colors.red;
//       default:
//         return Colors.grey;
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     final mc = _methodColor();
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 6),
//       child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
//         Container(
//           padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
//           decoration: BoxDecoration(
//             color: mc.withOpacity(0.2),
//             borderRadius: BorderRadius.circular(4),
//           ),
//           child: Text(method,
//               style: TextStyle(
//                   fontSize: 12, fontWeight: FontWeight.bold, color: mc)),
//         ),
//         const SizedBox(width: 8),
//         Expanded(
//           child: RichText(
//             text: TextSpan(
//               style: const TextStyle(fontSize: 15, color: Colors.black87),
//               children: [
//                 TextSpan(
//                     text: path,
//                     style: const TextStyle(fontFamily: 'SourceCodePro')),
//                 const TextSpan(text: ' — '),
//                 TextSpan(text: description),
//               ],
//             ),
//           ),
//         ),
//       ]),
//     );
//   }
// }
// import 'package:flutter/material.dart';
// import 'package:flutter/services.dart';
// import 'landing.dart'; // for LandingPage._brandGreen

// class ApiScreen extends StatelessWidget {
//   const ApiScreen({Key? key}) : super(key: key);
//   static const _brandGreen = Colors.green;
//   static const _baseUrl = 'https://api.instantlca.com/v1';
//   static const _quickstartCode = '''
// curl -X POST $_baseUrl/lca/estimate \\
//   -H "Content-Type: application/json" \\
//   -H "x-api-key: YOUR_API_KEY" \\
//   -d '{
//     "material": "PLA",
//     "volume_cm3": 150,
//     "surface_area_cm2": 200
//   }'
// ''';

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text(''),
//         backgroundColor: Colors.white,
//         elevation: 0,
//       ),
//       body: SafeArea(
//         child: Container(
//     //               decoration: BoxDecoration(
//     //   gradient: LinearGradient(
//     //     begin: Alignment.centerLeft,
//     //     end: Alignment.centerRight,
//     //     colors: [
//     //       Colors.lightBlue.shade100,         // Left side
//     //       Colors.white // Right side - lighter
//     //     ],
//     //   ),
//     // ),
//           child: SingleChildScrollView(
//             padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.stretch,
//               children: [
//                 // Logo & Subtitle
//                 Center(
//                   child: Column(
//                     children: [
//                       Image.asset('assets/logo.png', width: 150, height: 150),
//                       const SizedBox(height: 12),
//                       Text(
//                         'Bring carbon-smart design into Fusion 360 & your own tools',
//                         textAlign: TextAlign.center,
//                         style: TextStyle(
//                           color: _brandGreen,
//                           fontSize: 18,
//                           fontWeight: FontWeight.w600,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//                 const SizedBox(height: 24),
          
//                 // Background Context
//                 _ContentCard(
//                   title: 'Background',
//                   child: const Text(
//                     'Traditional LCA tools (SimaPro, GaBi) are costly, '
//                     'consultant-driven, and disconnected from CAD workflows. '
//                     'Engineers lack real-time climate intelligence at the design stage, '
//                     'and CAD data alone omits manufacturing context like energy source or region.',
//                     style: TextStyle(fontSize: 15, height: 1.5),
//                   ),
//                 ),
          
//                 const SizedBox(height: 16),
          
//                 // Problem
//                 _ContentCard(
//                   title: 'Problem We’re Solving',
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: const [
//                       _Bullet('Designers have no integrated LCA tools—rely on manual reports'),
//                       _Bullet('Specialized expertise & expensive licenses block 99% of teams'),
//                       _Bullet('No built-in climate data in CAD: missed opportunity for fast feedback'),
//                       _Bullet('CAD metadata lacks real-world context (process, location, energy mix)'),
//                     ],
//                   ),
//                 ),
          
//                 const SizedBox(height: 16),
          
//                 // Solution
//                 _ContentCard(
//                   title: 'Our Solution',
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: const [
//                       _Bullet('Lightweight REST API accepting CAD metadata (material, volume, geometry)'),
//                       _Bullet('LLMs auto-infer missing details: manufacturing process, regional energy use'),
//                       _Bullet('Calculations via Brightway2—open, transparent, scientific'),
//                       _Bullet('Instant carbon footprint estimates (kg CO₂e) + uncertainty & recommendations'),
//                       _Bullet('Plug-and-play integration for Fusion 360; extendable to any design tool'),
//                     ],
//                   ),
//                 ),
//                 const SizedBox(height: 16),
//                 // Why It’s Unique
//                 _ContentCard(
//                   title: 'Why It’s Unique',
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: const [
//                       _Bullet('First real-time LCA engine built for designers'),
//                       _Bullet('API-native: no desktop install, no seat licenses'),
//                       _Bullet('Open-source engine—fully transparent (Brightway2)'),
//                       _Bullet('Developer-first: clear docs, code examples, SDKs coming'),
//                     ],
//                   ),
//                 ),
          
//                 const SizedBox(height: 16),
          
//                 // Why Now
//                 _ContentCard(
//                   title: 'Why Now',
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: const [
//                       _Bullet('Fusion 360 offers a developer ecosystem for seamless plugins'),
//                       _Bullet('Brightway2 is mature, open-source, programmable LCA engine'),
//                       _Bullet('LLMs enable reasoning across incomplete data sets'),
//                       _Bullet('Industry pressure for sustainable design demands real-time tools'),
//                     ],
//                   ),
//                 ),
          
//                 const SizedBox(height: 16),
          
//                 // What the API Does
//                 _ContentCard(
//                   title: 'What the API Does',
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: const [
//                       _Bullet(
//                         'POST /lca/estimate: submit material + geometry → get CO₂e, energy, water footprints'
//                       ),
//                       _Bullet(
//                         'GET /materials: list supported materials with environmental profiles'
//                       ),
//                       _Bullet(
//                         'GET /status: health check & service uptime'
//                       ),
//                       _Bullet(
//                         'Future: full assemblies, regional energy models, cost vs. carbon curves'
//                       ),
//                     ],
//                   ),
//                 ),
          
//                 const SizedBox(height: 16),
          
//                 // Quickstart
//                 _ContentCard(
//                   title: 'Quickstart',
//                   child: Stack(
//                     children: [
//                       Container(
//                         width: double.infinity,
//                         padding: const EdgeInsets.all(12),
//                         decoration: BoxDecoration(
//                           color: Colors.grey.shade50,
//                           borderRadius: BorderRadius.circular(8),
//                         ),
//                         child: SelectableText(
//                           _quickstartCode,
//                           style: const TextStyle(
//                             fontFamily: 'SourceCodePro',
//                             fontSize: 14,
//                             height: 1.4,
//                           ),
//                         ),
//                       ),
//                       Positioned(
//                         top: 8,
//                         right: 8,
//                         child: IconButton(
//                           icon: const Icon(Icons.copy, size: 20),
//                           onPressed: () {
//                             Clipboard.setData(const ClipboardData(text: _quickstartCode));
//                             ScaffoldMessenger.of(context).showSnackBar(
//                               const SnackBar(content: Text('Copied to clipboard')),
//                             );
//                           },
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
          
//                 const SizedBox(height: 24),
          
//                 // Call to Action
//                 Center(
//                   child: ElevatedButton.icon(
//                     icon: const Icon(Icons.vpn_key),
//                     label: const Text('Get Your API Key'),
//                     style: ElevatedButton.styleFrom(
//                       backgroundColor: _brandGreen,
//                       padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
//                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
//                       textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
//                     ),
//                     onPressed: () {
//                       // TODO: navigate to key-generation
//                     },
//                   ),
//                 ),
          
//                 const SizedBox(height: 32),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }
// }

// /// A white card with a green accent bar and section title.
// class _ContentCard extends StatelessWidget {
//   final String title;
//   final Widget child;

//   const _ContentCard({required this.title, required this.child});

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       decoration: BoxDecoration(
//         color: Colors.white,
//         border: Border(
//           left: BorderSide(color: ApiScreen._brandGreen, width: 4),
//         ),
//         boxShadow: [
//           BoxShadow(
//             color: Colors.black.withOpacity(0.05),
//             blurRadius: 8,
//             offset: const Offset(0, 4),
//           ),
//         ],
//         borderRadius: BorderRadius.circular(4),
//       ),
//       padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(title,
//               style: const TextStyle(
//                 fontSize: 18,
//                 fontWeight: FontWeight.w600,
//               )),
//           const SizedBox(height: 8),
//           child,
//         ],
//       ),
//     );
//   }
// }

// /// A simple bullet widget.
// class _Bullet extends StatelessWidget {
//   final String text;
//   const _Bullet(this.text);

//   @override
//   Widget build(BuildContext context) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 4),
//       child: Row(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const Text('•  ', style: TextStyle(fontSize: 16)),
//           Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4))),
//         ],
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'landing.dart'; // for LandingPage._brandGreen

class ApiScreen extends StatelessWidget {
  const ApiScreen({Key? key}) : super(key: key);
  static const _brandGreen = Colors.green;
  static const _baseUrl = 'https://api.instantlca.com/v1';

  // Quickstart request snippet
  static const _quickstartCode = '''
curl -X POST $_baseUrl/lca/estimate \\
  -H "Content-Type: application/json" \\
  -H "x-api-key: YOUR_API_KEY" \\
  -d '{
    "material": "PLA",
    "volume_cm3": 150,
    "surface_area_cm2": 200
  }'
''';

  // Sample response payload
  static const _sampleResponse = '''
{
  "co2e_kg": 2.48,
  "energy_MJ": 13.7,
  "water_L": 6.2,
  "uncertainty": 0.18,
  "assumptions": {
    "process": "injection molding",
    "region": "EU average",
    "material": "PLA"
  }
}
''';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('InstantLCA API'),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        titleTextStyle: const TextStyle(color: Colors.black87, fontSize: 18),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo & Subtitle
              // Center(
              //   child: Column(
              //     children: [
              //       Image.asset('assets/logo.png', width: 150, height: 150),
              //       const SizedBox(height: 12),
              //       Text(
              //         'Bring carbon-smart design into Fusion 360 & your own tools',
              //         textAlign: TextAlign.center,
              //         style: TextStyle(
              //           color: _brandGreen,
              //           fontSize: 18,
              //           fontWeight: FontWeight.w600,
              //         ),
              //       ),
              //     ],
              //   ),
              // ),
//               const SizedBox(height: 24),
// const SizedBox(height: 24),

// // Visual: CAD view + tooltip
// _ContentCard(
//   title: 'Visual Preview',
//   child: Column(
//     crossAxisAlignment: CrossAxisAlignment.start,
//     children: [
//       const Text(
//         'What instant feedback could look like inside a CAD tool:',
//         style: TextStyle(fontSize: 14, color: Colors.black87),
//       ),
//       const SizedBox(height: 12),
//       ClipRRect(
//         borderRadius: BorderRadius.circular(6),
//         child: Image.asset(
//           'assets/cad.png',
//           fit: BoxFit.contain,
//         ),
//       ),
//     ],
//   ),
// ),
// HERO VISUAL FIRST
_ContentCard(
  title: 'What It Looks Like',
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Instant feedback inside your CAD environment:',
        style: TextStyle(fontSize: 14, color: Colors.black87),
      ),
      const SizedBox(height: 12),
      Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.asset(
            'assets/cad.png',height: 500, 
            fit: BoxFit.contain,
          ),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Tooltip shows estimated CO₂ footprint (kg CO₂e) based on geometry and material.',
        style: TextStyle(fontSize: 12, color: Colors.black54),
      ),
    ],
  ),
),

// const SizedBox(height: 24),

// // LOGO + TAGLINE AFTER
// Center(
//   child: Column(
//     children: [
//       Image.asset('assets/logo.png', width: 100, height: 100),
//       const SizedBox(height: 10),
//       Text(
//         'InstantLCA – Environmental intelligence for designers',
//         textAlign: TextAlign.center,
//         style: TextStyle(
//           fontSize: 16,
//           fontWeight: FontWeight.w500,
//           color: _brandGreen,
//         ),
//       ),
//     ],
//   ),
// ),

const SizedBox(height: 32),

const SizedBox(height: 24),

              // Background Context
              _ContentCard(
                title: 'Background',
                child: const Text(
                  'Traditional LCA tools (SimaPro, GaBi) are costly, '
                  'consultant-driven, and disconnected from CAD workflows. '
                  'Engineers lack real-time climate intelligence at the design stage, '
                  'and CAD data alone omits manufacturing context like energy source or region.',
                  style: TextStyle(fontSize: 15, height: 1.5),
                ),
              ),

              const SizedBox(height: 16),

              // Problem
              _ContentCard(
                title: 'Problem We’re Solving',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _Bullet('Designers have no integrated LCA tools—rely on manual reports'),
                    _Bullet('Specialized expertise & expensive licenses block 99% of teams'),
                    _Bullet('No built-in climate data in CAD: missed opportunity for fast feedback'),
                    _Bullet('CAD metadata lacks real-world context (process, location, energy mix)'),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Solution
              _ContentCard(
                title: 'Our Solution',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _Bullet('Lightweight REST API accepting CAD metadata (material, volume, geometry)'),
                    _Bullet('LLMs auto-infer missing details: manufacturing process, regional energy use'),
                    _Bullet('Calculations via Brightway2—open, transparent, scientific'),
                    _Bullet('Instant carbon footprint estimates (kg CO₂e) + uncertainty & recommendations'),
                    _Bullet('Plug-and-play integration for Fusion 360; extendable to any design tool'),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Why It’s Unique
              _ContentCard(
                title: 'Why It’s Unique',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _Bullet('First real-time LCA engine built for designers'),
                    _Bullet('API-native: no desktop install, no seat licenses'),
                    _Bullet('Open-source engine—fully transparent (Brightway2)'),
                    _Bullet('Developer-first: clear docs, code examples, SDKs coming'),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Why Now
              _ContentCard(
                title: 'Why Now',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _Bullet('Fusion 360 offers a developer ecosystem for seamless plugins'),
                    _Bullet('Brightway2 is mature, open-source, programmable LCA engine'),
                    _Bullet('LLMs enable reasoning across incomplete data sets'),
                    _Bullet('Industry pressure for sustainable design demands real-time tools'),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // What the API Does
              _ContentCard(
                title: 'What the API Does',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    _Bullet('POST /lca/estimate: submit material + geometry → get CO₂e, energy, water footprints'),
                    _Bullet('GET /materials: list supported materials with environmental profiles'),
                    _Bullet('GET /status: health check & service uptime'),
                    _Bullet('Future: full assemblies, regional energy models, cost vs. carbon curves'),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Quickstart Request
              _ContentCard(
                title: 'Quickstart: Request',
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        _quickstartCode,
                        style: const TextStyle(
                          fontFamily: 'SourceCodePro',
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () {
                          Clipboard.setData(const ClipboardData(text: _quickstartCode));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Request snippet copied')),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Early-access disclaimer
              Text(
                '🚧 Early-access preview: some endpoints may not be fully active yet.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.black54, fontStyle: FontStyle.italic),
              ),

              const SizedBox(height: 16),

              // Sample Response
              _ContentCard(
                title: 'Sample Response',
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        _sampleResponse,
                        style: const TextStyle(
                          fontFamily: 'SourceCodePro',
                          fontSize: 14,
                          height: 1.4,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.copy, size: 20),
                        onPressed: () {
                          Clipboard.setData(const ClipboardData(text: _sampleResponse));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Response snippet copied')),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Call to Action
              Center(
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.vpn_key),
                  label: const Text('Get Your API Key'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _brandGreen,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
onPressed: () async {
  const url = 'https://docs.google.com/forms/d/e/1FAIpQLSd_oAcaOglcccJZa8-FzEnl1iYZR98I9bfl6tQy2D39LWe77w/viewform?usp=dialog';
  if (await canLaunchUrl(Uri.parse(url))) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open the form')),
    );
  }
}
                ),
              ),

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

/// A white card with a green accent bar and section title.
class _ContentCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ContentCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(left: BorderSide(color: Colors.green, width: 4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

/// A simple bullet widget.
class _Bullet extends StatelessWidget {
  final String text;
  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  ', style: TextStyle(fontSize: 16)),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
