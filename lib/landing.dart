import 'package:flutter/material.dart';
import 'package:earlylca/homescreen/home_screen.dart';
import 'api_screen.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({Key? key}) : super(key: key);

  static const Color _brandGreen = Color(0xFF2E7D32);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // backgroundColor: Colors.white,
      body: Container(
        decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.lightBlue.shade100,         // Left side
          Colors.white // Right side - lighter
        ],
      ),
    ),

        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Bigger logo
                // Visual Preview: What It Looks Like
_ContentCard(
  title: 'What It Looks Like',
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Instant feedback inside your CAD or text workflow:',
        style: TextStyle(fontSize: 14, color: Colors.black87),
      ),
      const SizedBox(height: 16),

      // Row with both images side by side (or stacked on mobile)
      LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 600;
          return isWide
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _previewImage('assets/cad.png', label: 'Fusion 360 Tooltip'),
                    const SizedBox(width: 20),
                    _previewImage('assets/text.png', label: 'Text to LCA UI'),
                  ],
                )
              : Column(
                  children: [
                    _previewImage('assets/cad.png', label: 'Fusion 360 Tooltip'),
                    const SizedBox(height: 16),
                    _previewImage('assets/text.png', label: 'Text to LCA UI'),
                  ],
                );
        },
      ),

      const SizedBox(height: 12),
      // const Text(
      //   'These previews show how InstantLCA generates carbon feedback from either CAD metadata or descriptive language.',
      //   style: TextStyle(fontSize: 12, color: Colors.black54),
      // ),
    ],
  ),
),

                // Image.asset(
                //   'assets/logo.png',
                //   width: 250,
                //   height: 250,
                // ),
                // const SizedBox(height: 20),
        
                // // Tagline in brand green
                // Text(
                //   'Bending the curve, one decision at a time',
                //   textAlign: TextAlign.center,
                //   style: TextStyle(
                //     fontSize: 18,
                //     fontWeight: FontWeight.w400,
                //     color: _brandGreen,
                //     fontStyle: FontStyle.italic,
                //   ),
                // ),

                // const SizedBox(height: 60),
        
                // Text → LCA card
                _FeatureCard(
                  icon: Icons.text_snippet_outlined,
                  title: 'Text to LCA',
                  description:
  'InstantLCA turns natural language into transparent, traceable carbon models.',
                  backgroundColor: _brandGreen,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const HomeScreen(title: 'Text to LCA'),
                    ),
                  ),
                ),
        
                const SizedBox(height: 30),
        
                // LCA API card
                _FeatureCard(
                  icon: Icons.cloud_sync_rounded,
                  title: 'LCA API with Fusion 360',
                  description:
                      'Coming soon - Embed environmental data into Fusion 360 via our REST API.',
                  backgroundColor: _brandGreen,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ApiScreen()),
                  ),
                ),

              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scale = Tween(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _controller.forward(),
      onExit: (_) => _controller.reverse(),
      child: GestureDetector(
        onTap: widget.onTap,
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                // White circle + icon
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  child: Icon(widget.icon, size: 28, color: Colors.white),
                ),
                const SizedBox(width: 20),
                // Title & description in white
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.description,
                        style: const TextStyle(
                          fontSize: 15,
                          color: Colors.white70,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios, color: Colors.white70),
              ],
            ),
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
  color: Colors.white.withOpacity(0.05), // Light transparent white
  // border: Border(left: BorderSide(color: Colors.green, width: 4)),
  // borderRadius: BorderRadius.circular(4),
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
Widget _previewImage(String path, {required String label}) {
  return Column(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.asset(
          path,
          height: 280,
          fit: BoxFit.contain,
        ),
      ),
      const SizedBox(height: 6),
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
    ],
  );
}
