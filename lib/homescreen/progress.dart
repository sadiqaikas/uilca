import 'package:flutter/material.dart';
import 'dart:async';
 
import 'dart:math';
 
import 'package:animated_text_kit/animated_text_kit.dart';


class AdvancedLectureProgressDialog extends StatefulWidget {
  const AdvancedLectureProgressDialog({Key? key}) : super(key: key);

  @override
  State<AdvancedLectureProgressDialog> createState() =>
      _AdvancedLectureProgressDialogState();
}

class _AdvancedLectureProgressDialogState extends State<AdvancedLectureProgressDialog>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  int _currentPage = 0;
  Timer? _pageTimer;
  late final AnimationController _backgroundController;
  late final Animation<Color?> _backgroundColorAnim;

  // List of detailed lecture pages. These descriptions cover LCA methodology in depth,
  // focusing on goal definition, data sourcing, uncertainty assignment, material/emissions balance,
  // and process interconnections—tailored for scientific rigor.
  final List<Map<String, String>> lecturePages = [
    {
      'title': 'Welcome & Overview',
      'description': 'Welcome to the advanced LCA simulator. We are setting up your detailed life cycle inventory according to ISO 14040/44 standards—defining clear goals, system boundaries, and a precise functional unit.',
    },
    {
      'title': 'Goal & Scope Definition',
      'description': 'We define the goal and scope using technical language: identifying whether the study is single or multi-scenario, setting boundaries (e.g., cradle-to-grave), and clearly stating the objective in a reproducible manner.',
    },
    {
      'title': 'Functional Unit & Unit Conversion',
      'description': 'The functional unit is precisely defined (e.g., 1 liter, 1 km driven). Any necessary unit conversions are performed using scientifically accepted factors (e.g., 1 mile = 1.60934 km).',
    },
    {
      'title': 'Data Sourcing & Uncertainty',
      'description': 'High-quality data is sourced from trusted databases (e.g., GREET, eGRID). Every parameter is tagged with an uncertainty value: 10% (database), 25% (edited), or 50% (guessed), along with complete reference details.',
    },
    {
      'title': 'Process Decomposition & Material Balance',
      'description': 'We decompose the system into all necessary processes (raw material extraction, processing, manufacturing, use, end-of-life). Each process includes detailed inputs/outputs and material balances—verified within a small margin (e.g., 3–5%).',
    },
    {
      'title': 'Emission Estimation & Reconciliation',
      'description': 'Emissions (CO₂, NOx, SO₂, CH₄, N₂O) are calculated for each process. Their values are rigorously reconciled with fuel consumption and energy use, ensuring a balance based on stoichiometric principles.',
    },
    {
      'title': 'Interprocess Flows & Connectivity',
      'description': 'We map all flows (material and energy) between processes, ensuring that every transfer is fully traced and the overall system is balanced with the functional unit.',
    },
    {
      'title': 'Uncertainty Propagation for Monte Carlo',
      'description': 'All parameters include explicit uncertainty values to support robust Monte Carlo simulations—documenting data provenance, with uncertainty values of 10%, 25%, or 50% based on the source.',
    },
    {
      'title': 'Data Traceability & Validation',
      'description': 'Every process includes detailed reference information (source, URL, retrieval method) and search terms. This ensures that all data is scientifically verifiable and the overall inventory is traceable and auditable.',
    },
    {
      'title': 'Final Assembly & Quality Check',
      'description': 'The complete LCA inventory is compiled into a structured JSON file, where material and emissions balances are verified and validated against the functional unit, ready for advanced Brightway2 simulation.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _pageTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _currentPage = (_currentPage + 1) % lecturePages.length;
      _pageController.animateToPage(
        _currentPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
    _backgroundController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
    _backgroundColorAnim = ColorTween(
      begin: Colors.white,
      end: Colors.lightGreen.shade100,
    ).animate(_backgroundController);
  }

  @override
  void dispose() {
    _pageTimer?.cancel();
    _backgroundController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// Build each page of our lecture presentation.
  Widget _buildLecturePage(Map<String, String> pageInfo) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          pageInfo['title']!,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.green.shade800,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            pageInfo['description']!,
            style: const TextStyle(
              fontSize: 18,
              color: Colors.black87,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 20),
        // A custom knowledge gauge to indicate progress (as a visual embellishment).
        _KnowledgeGauge(progress: (_currentPage + 1) / lecturePages.length),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _backgroundColorAnim,
      builder: (context, child) {
        return Dialog(
          backgroundColor: _backgroundColorAnim.value,
          elevation: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // A modern CircularProgressIndicator that uses the green accent.
                const CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                  strokeWidth: 6,
                ),
                const SizedBox(height: 24),
                // PageView for rotating detailed lecture pages.
                SizedBox(
                  height: 280,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: lecturePages.length,
                    itemBuilder: (context, index) {
                      return _buildLecturePage(lecturePages[index]);
                    },
                  ),
                ),
                const SizedBox(height: 20),
                // Animated text describing the process in a smooth typewriter style.
                DefaultTextStyle(
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.black87,
                    fontStyle: FontStyle.italic,
                  ),
                  child: AnimatedTextKit(
                    animatedTexts: [
                      TyperAnimatedText(
                        "Compiling your detailed LCA inventory using rigorous scientific standards. Please hold on—it’s worth every second!",
                        speed: const Duration(milliseconds: 60),
                      ),
                    ],
                    isRepeatingAnimation: true,
                    repeatForever: true,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A custom gauge widget that visually indicates the overall progress of the lecture.
class _KnowledgeGauge extends StatelessWidget {
  final double progress; // A value between 0.0 and 1.0 representing progress.
  const _KnowledgeGauge({Key? key, required this.progress}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(80, 80),
      painter: _GaugePainter(progress),
    );
  }
}

/// Custom painter for the knowledge gauge.
class _GaugePainter extends CustomPainter {
  final double progress;
  _GaugePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    double strokeWidth = 8;
    Offset center = Offset(size.width / 2, size.height / 2);
    double radius = (size.width / 2) - strokeWidth;
    Paint backgroundCircle = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    Paint progressArc = Paint()
      ..color = Colors.green.shade700
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Draw base circle.
    canvas.drawCircle(center, radius, backgroundCircle);
    // Draw arc representing progress.
    double sweepAngle = 2 * pi * progress;
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -pi / 2, sweepAngle, false, progressArc);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}