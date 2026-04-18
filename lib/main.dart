import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(MyApp());
}

// ================= API =================
Future<Map<String, dynamic>> sendImageToAPI(File imageFile) async {
  var request = http.MultipartRequest(
    'POST',
    Uri.parse('http://10.0.2.2:5000/predict'),
  );

  request.files.add(await http.MultipartFile.fromPath('image', imageFile.path));

  var response = await request.send();
  var res = await http.Response.fromStream(response);

  return json.decode(res.body);
}

// ================= GROWTH TRACKING DATA =================
class LesionScan {
  final String id;
  final String lesionId;
  final DateTime date;
  final String imagePath;
  final Map<String, dynamic> result;

  LesionScan({
    required this.id,
    required this.lesionId,
    required this.date,
    required this.imagePath,
    required this.result,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'lesionId': lesionId,
      'date': date.toIso8601String(),
      'imagePath': imagePath,
      'result': result,
    };
  }

  factory LesionScan.fromJson(Map<String, dynamic> json) {
    return LesionScan(
      id: json['id'] ?? '',
      lesionId: json['lesionId'] ?? '',
      date: DateTime.tryParse(json['date'] ?? '') ?? DateTime.now(),
      imagePath: json['imagePath'] ?? '',
      result: Map<String, dynamic>.from(json['result'] ?? {}),
    );
  }
}

class Lesion {
  final String id;
  final String name;
  final String bodyLocation;
  final DateTime createdAt;
  final List<LesionScan> scans;

  Lesion({
    required this.id,
    required this.name,
    required this.bodyLocation,
    required this.createdAt,
    required this.scans,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'bodyLocation': bodyLocation,
      'createdAt': createdAt.toIso8601String(),
      'scans': scans.map((s) => s.toJson()).toList(),
    };
  }

  factory Lesion.fromJson(Map<String, dynamic> json) {
    return Lesion(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Unknown Lesion',
      bodyLocation: json['bodyLocation'] ?? 'Unknown',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      scans: (json['scans'] as List?)
              ?.map((s) => LesionScan.fromJson(s))
              .toList() ??
          [],
    );
  }

  String getChangeStatus() {
    if (scans.length < 2) return 'New';

    final firstConfidence = (scans.first.result['confidence'] ?? 0).toDouble();
    final lastConfidence = (scans.last.result['confidence'] ?? 0).toDouble();
    final firstRisk = scans.first.result['risk'] ?? 'Low';
    final lastRisk = scans.last.result['risk'] ?? 'Low';

    if (lastRisk == 'High' && firstRisk != 'High') {
      return 'Worsening';
    } else if (lastConfidence > firstConfidence + 10) {
      return 'Growing';
    } else if (lastConfidence < firstConfidence - 10) {
      return 'Improving';
    }
    return 'Stable';
  }
}

Future<void> saveLesion(Lesion lesion) async {
  final prefs = await SharedPreferences.getInstance();
  List<String> lesions = prefs.getStringList('lesions') ?? [];

  final existingIndex = lesions.indexWhere((l) {
    final data = json.decode(l);
    return data['id'] == lesion.id;
  });

  if (existingIndex >= 0) {
    lesions[existingIndex] = json.encode(lesion.toJson());
  } else {
    lesions.add(json.encode(lesion.toJson()));
  }

  await prefs.setStringList('lesions', lesions);
}

Future<List<Lesion>> getLesions() async {
  final prefs = await SharedPreferences.getInstance();
  List<String> lesions = prefs.getStringList('lesions') ?? [];
  return lesions.map((l) {
    try {
      return Lesion.fromJson(json.decode(l));
    } catch (e) {
      return null;
    }
  }).where((l) => l != null).cast<Lesion>().toList();
}

Future<void> deleteLesion(String lesionId) async {
  final prefs = await SharedPreferences.getInstance();
  List<String> lesions = prefs.getStringList('lesions') ?? [];
  lesions.removeWhere((l) {
    final data = json.decode(l);
    return data['id'] == lesionId;
  });
  await prefs.setStringList('lesions', lesions);
}

// ================= OLD HISTORY FUNCTIONS =================
Future<void> saveResult(Map<String, dynamic> result) async {
  final prefs = await SharedPreferences.getInstance();
  List<String> history = prefs.getStringList('history') ?? [];
  history.add(json.encode(result));
  await prefs.setStringList('history', history);
}

Future<List<Map<String, dynamic>>> getHistory() async {
  final prefs = await SharedPreferences.getInstance();
  List<String> history = prefs.getStringList('history') ?? [];
  return history.map((e) => json.decode(e) as Map<String, dynamic>).toList();
}

Future<Map<String, String>> getProfileData() async {
  final prefs = await SharedPreferences.getInstance();
  return {
    'name': prefs.getString('user_name') ?? 'Guest User',
    'email': prefs.getString('user_email') ?? 'Not provided',
  };
}

Future<void> saveProfileData(String name, String email) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('user_name', name);
  await prefs.setString('user_email', email);
}

Future<void> clearAllData() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
}

// ================= THEME CONSTANTS =================
const Color kPrimary = Color(0xFF6C63FF);
const Color kPrimaryLight = Color(0xFFEEEDFE);
const Color kAccent = Color(0xFF1D9E75);
const Color kDanger = Color(0xFFE24B4A);
const Color kWarning = Color(0xFFEF9F27);
const Color kSurface = Color(0xFFF8F7FF);
const Color kCard = Color(0xFFFFFFFF);
const Color kBorder = Color(0xFFE8E6FF);
const Color kTextPrimary = Color(0xFF1A1530);
const Color kTextSecondary = Color(0xFF6B6880);

// ================= APP =================
class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DermScan',
      theme: ThemeData(
        fontFamily: 'SF Pro Display',
        scaffoldBackgroundColor: kSurface,
        colorScheme: const ColorScheme.light(
          primary: kPrimary,
          secondary: kAccent,
          surface: kCard,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: kSurface,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: kTextPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
          iconTheme: IconThemeData(color: kTextPrimary),
        ),
      ),
      home: HomeScreen(),
    );
  }
}

// ================= HOME =================
class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    UploadScreen(),
    GrowthTrackingScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: kCard,
          border: const Border(top: BorderSide(color: kBorder, width: 1)),
          boxShadow: [
            BoxShadow(
              color: kPrimary.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, -4),
            )
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          selectedItemColor: kPrimary,
          unselectedItemColor: kTextSecondary,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedLabelStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
          unselectedLabelStyle: const TextStyle(fontSize: 12),
          onTap: (i) => setState(() => _currentIndex = i),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.document_scanner_outlined),
              activeIcon: Icon(Icons.document_scanner),
              label: 'Scan',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.timeline_outlined),
              activeIcon: Icon(Icons.timeline),
              label: 'Tracking',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

// ================= UPLOAD SCREEN =================
class UploadScreen extends StatefulWidget {
  @override
  _UploadScreenState createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen>
    with TickerProviderStateMixin {
  File? _image;
  final ImagePicker _picker = ImagePicker();
  bool _trackGrowth = false;
  String? _existingLesionId;
  List<Lesion> _lesions = [];

  late AnimationController _scanController;
  late Animation<double> _scanAnim;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _loadLesions();

    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scanAnim = Tween<double>(begin: 0, end: 260).animate(
      CurvedAnimation(parent: _scanController, curve: Curves.easeInOut),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(_fadeController);

    _fadeController.forward();
  }

  Future<void> _loadLesions() async {
    final lesions = await getLesions();
    if (mounted) {
      setState(() => _lesions = lesions);
    }
  }

  @override
  void dispose() {
    _scanController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(source: source);
    if (picked != null && mounted) {
      setState(() => _image = File(picked.path));
    }
  }

  // ── Opens the guided capture wizard; on completion sets the image ──
  Future<void> _openGuidedCapture() async {
    final File? result = await Navigator.push<File>(
      context,
      MaterialPageRoute(builder: (_) => const GuidedCaptureScreen()),
    );
    if (result != null && mounted) {
      setState(() => _image = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: kPrimaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.local_hospital,
                          color: kPrimary, size: 20),
                    ),
                    const SizedBox(width: 10),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "DermScan",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: kTextPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        Text(
                          "AI Skin Analysis",
                          style:
                              TextStyle(fontSize: 12, color: kTextSecondary),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 22),

                // Info banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kPrimaryLight,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kBorder),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: kPrimary, size: 18),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          "Upload a clear photo of the affected skin area for AI-powered analysis.",
                          style: TextStyle(
                            color: Color(0xFF534AB7),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Image preview tap area
                GestureDetector(
                  onTap: () => pickImage(ImageSource.gallery),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 230,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: kCard,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _image != null ? kPrimary : kBorder,
                        width: _image != null ? 2 : 1,
                      ),
                    ),
                    child: _image != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(19),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(_image!, fit: BoxFit.cover),
                                Positioned(
                                  bottom: 10,
                                  right: 10,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withOpacity(0.55),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: const Text(
                                      "Tap to change",
                                      style: TextStyle(
                                          color: Colors.white, fontSize: 11),
                                    ),
                                  ),
                                )
                              ],
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: kPrimaryLight,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(Icons.add_photo_alternate,
                                    color: kPrimary, size: 28),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                "Tap to upload an image",
                                style: TextStyle(
                                  color: kTextPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                "JPG, PNG supported",
                                style: TextStyle(
                                    color: kTextSecondary, fontSize: 12),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 14),

                // Gallery / Camera buttons
                // Camera button now opens GuidedCaptureScreen
                Row(
                  children: [
                    Expanded(
                      child: _PickButton(
                        icon: Icons.photo_library_outlined,
                        label: "Gallery",
                        onTap: () => pickImage(ImageSource.gallery),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PickButton(
                        icon: Icons.camera_alt_outlined,
                        label: "Camera",
                        onTap: _openGuidedCapture, // ← uses guided capture
                      ),
                    ),
                  ],
                ),

                // Growth tracking toggle
                if (_image != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: kCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.track_changes,
                                color: kPrimary, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Track Growth Over Time',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: kTextPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text(
                            'Enable growth tracking',
                            style: TextStyle(
                                fontSize: 13, color: kTextPrimary),
                          ),
                          subtitle: Text(
                            _trackGrowth
                                ? 'This scan will be added to lesion timeline'
                                : 'Scan will not be tracked',
                            style: const TextStyle(
                                fontSize: 11, color: kTextSecondary),
                          ),
                          value: _trackGrowth,
                          onChanged: (val) async {
                            setState(() => _trackGrowth = val);
                            if (val) {
                              final lesions = await getLesions();
                              if (mounted) {
                                setState(() => _lesions = lesions);
                                if (lesions.isNotEmpty &&
                                    _existingLesionId == null) {
                                  _existingLesionId = lesions.first.id;
                                }
                              }
                            }
                          },
                          activeColor: kPrimary,
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (_trackGrowth && _lesions.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _existingLesionId,
                            decoration: InputDecoration(
                              labelText: 'Select Lesion to Track',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            items: _lesions
                                .map((l) => DropdownMenuItem(
                                      value: l.id,
                                      child: Text(
                                          '${l.name} (${l.bodyLocation})'),
                                    ))
                                .toList(),
                            onChanged: (val) =>
                                setState(() => _existingLesionId = val),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),

                // Tips card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kBorder),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.tips_and_updates_outlined,
                              color: kWarning, size: 18),
                          SizedBox(width: 8),
                          Text(
                            "Tips for best results",
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: kTextPrimary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 12),
                      _TipRow(
                          icon: Icons.wb_sunny_outlined,
                          text: "Use clear, natural lighting"),
                      _TipRow(
                          icon: Icons.center_focus_strong_outlined,
                          text: "Focus on the affected skin area"),
                      _TipRow(
                          icon: Icons.blur_off,
                          text: "Avoid blurry or obscured photos"),
                    ],
                  ),
                ),
                const SizedBox(height: 28),

                // Analyse button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _image == null
                        ? null
                        : () async {
                            final imageToAnalyze = _image;
                            if (imageToAnalyze == null) return;

                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => LoadingScreen()),
                            );

                            try {
                              var data =
                                  await sendImageToAPI(imageToAnalyze);

                              if (_trackGrowth) {
                                final lesionId = _existingLesionId ??
                                    DateTime.now()
                                        .millisecondsSinceEpoch
                                        .toString();
                                final scan = LesionScan(
                                  id: DateTime.now()
                                      .millisecondsSinceEpoch
                                      .toString(),
                                  lesionId: lesionId,
                                  date: DateTime.now(),
                                  imagePath: imageToAnalyze.path,
                                  result: data,
                                );

                                final lesions = await getLesions();
                                var lesion = lesions.firstWhere(
                                  (l) => l.id == lesionId,
                                  orElse: () => Lesion(
                                    id: lesionId,
                                    name:
                                        'Lesion ${lesions.length + 1}',
                                    bodyLocation: 'Unknown',
                                    createdAt: DateTime.now(),
                                    scans: [],
                                  ),
                                );

                                lesion = Lesion(
                                  id: lesion.id,
                                  name: lesion.name,
                                  bodyLocation: lesion.bodyLocation,
                                  createdAt: lesion.createdAt,
                                  scans: [...lesion.scans, scan],
                                );

                                await saveLesion(lesion);
                                data['lesionId'] = lesionId;
                              }

                              await saveResult(data);

                              if (mounted) {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ResultScreen(
                                      image: imageToAnalyze,
                                      result: data,
                                    ),
                                  ),
                                );
                                setState(() {
                                  _image = null;
                                  _trackGrowth = false;
                                  _existingLesionId = null;
                                });
                              }
                            } catch (e) {
                              if (mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content:
                                          Text('Error: ${e.toString()}')),
                                );
                              }
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                          _image == null ? Colors.grey.shade300 : kPrimary,
                      foregroundColor:
                          _image == null ? kTextSecondary : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, size: 18),
                        SizedBox(width: 8),
                        Text(
                          "Analyze Skin",
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Center(
                  child: Text(
                    "For informational purposes only. Not a medical diagnosis.",
                    style: TextStyle(
                        color: kTextSecondary, fontSize: 11, height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ================= GUIDED CAPTURE SCREEN =================
class GuidedCaptureScreen extends StatefulWidget {
  const GuidedCaptureScreen({super.key});

  @override
  State<GuidedCaptureScreen> createState() => _GuidedCaptureScreenState();
}

class _GuidedCaptureScreenState extends State<GuidedCaptureScreen>
    with SingleTickerProviderStateMixin {
  int _step = 0;
  File? _capturedImage;
  bool _isLoading = false;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final ImagePicker _picker = ImagePicker();

  static const _steps = [
    _CaptureStep(
      icon: Icons.social_distance_rounded,
      title: 'Hold the right distance',
      description:
          'Keep your camera 10–15 cm (4–6 inches) away from the lesion. '
          'The lesion should fill most of the circle below.',
      color: Color(0xFF5E8BFF),
    ),
    _CaptureStep(
      icon: Icons.wb_sunny_rounded,
      title: 'Check your lighting',
      description:
          'Move to a bright, evenly lit area. Avoid direct sunlight or harsh '
          'shadows. A lamp held to the side works great.',
      color: Color(0xFFFFB340),
    ),
    _CaptureStep(
      icon: Icons.camera_alt_rounded,
      title: 'Ready to capture',
      description:
          'Hold steady and tap the button. Keep the lesion centred inside '
          'the circle for the most accurate analysis.',
      color: Color(0xFF3FCC8E),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _openCamera() async {
    setState(() => _isLoading = true);
    try {
      final XFile? photo = await _picker.pickImage(
          source: ImageSource.camera, imageQuality: 90);
      if (photo != null) {
        setState(() => _capturedImage = File(photo.path));
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _retake() => setState(() => _capturedImage = null);

  void _nextStep() {
    if (_step < 2) {
      setState(() => _step++);
    } else {
      _openCamera();
    }
  }

  void _previousStep() {
    if (_step > 0) setState(() => _step--);
  }

  // Returns the confirmed image back to UploadScreen
  void _confirmAndReturn() {
    if (_capturedImage == null) return;
    Navigator.pop<File>(context, _capturedImage);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Guided Capture',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 17),
        ),
        centerTitle: true,
      ),
      body: _capturedImage != null ? _reviewView() : _guideView(),
    );
  }

  Widget _guideView() {
    final step = _steps[_step];
    return Column(
      children: [
        // Step progress bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
          child: Row(
            children: List.generate(_steps.length, (i) {
              final active = i == _step;
              final done = i < _step;
              return Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  height: 3,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: done || active
                        ? step.color
                        : Colors.white.withOpacity(0.15),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 24),
        // Framing overlay
        Expanded(
          child: Center(
            child: AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (_, child) => Transform.scale(
                scale: _step == 2 ? _pulseAnimation.value : 1.0,
                child: child,
              ),
              child: _FramingOverlay(accentColor: step.color),
            ),
          ),
        ),
        const SizedBox(height: 24),
        // Instruction card
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _InstructionCard(step: step, key: ValueKey(_step)),
        ),
        const SizedBox(height: 20),
        // Navigation buttons
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              if (_step > 0)
                Expanded(
                  child: OutlinedButton(
                    onPressed: _previousStep,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Back'),
                  ),
                ),
              if (_step > 0) const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _nextStep,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: step.color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          _step < 2 ? 'Next' : 'Open Camera',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _reviewView() {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(_capturedImage!, fit: BoxFit.cover),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment.center,
                        radius: 1.2,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.35),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Quality checklist
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: const Column(
              children: [
                _GuidedCheckItem(label: 'Lesion fully visible and centred'),
                _GuidedCheckItem(label: 'Image is in focus (not blurry)'),
                _GuidedCheckItem(label: 'No harsh shadows or glare'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _retake,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retake'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _confirmAndReturn,
                  icon: const Icon(Icons.check_circle_outline_rounded,
                      size: 18),
                  label: const Text(
                    'Use Photo',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3FCC8E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

// ── Guided capture supporting classes ──────────────────────

class _CaptureStep {
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  const _CaptureStep({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}

class _FramingOverlay extends StatelessWidget {
  final Color accentColor;
  const _FramingOverlay({required this.accentColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 260,
      child: CustomPaint(
        painter: _CircleOverlayPainter(accentColor: accentColor),
        child: Center(
          child: Icon(Icons.center_focus_strong_rounded,
              size: 36, color: accentColor.withOpacity(0.5)),
        ),
      ),
    );
  }
}

class _CircleOverlayPainter extends CustomPainter {
  final Color accentColor;
  _CircleOverlayPainter({required this.accentColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = accentColor.withOpacity(0.12)
        ..style = PaintingStyle.fill,
    );

    final borderPaint = Paint()
      ..color = accentColor.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    const dashCount = 32;
    const gap = 0.06;
    for (int i = 0; i < dashCount; i++) {
      final startAngle = (2 * math.pi / dashCount) * i;
      final sweepAngle = (2 * math.pi / dashCount) - gap;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
        borderPaint,
      );
    }

    for (final angleDeg in [0.0, 90.0, 180.0, 270.0]) {
      final angle = angleDeg * math.pi / 180;
      final outer = Offset(center.dx + radius * 0.98 * math.cos(angle),
          center.dy + radius * 0.98 * math.sin(angle));
      final inner = Offset(
          center.dx + (radius - 12) * math.cos(angle),
          center.dy + (radius - 12) * math.sin(angle));
      canvas.drawLine(
        inner,
        outer,
        Paint()
          ..color = accentColor
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_CircleOverlayPainter old) =>
      old.accentColor != accentColor;
}

class _InstructionCard extends StatelessWidget {
  final _CaptureStep step;
  const _InstructionCard({required this.step, super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: step.color.withOpacity(0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: step.color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(step.icon, color: step.color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(step.description,
                      style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                          height: 1.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuidedCheckItem extends StatelessWidget {
  final String label;
  const _GuidedCheckItem({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: Color(0xFF3FCC8E), size: 18),
          const SizedBox(width: 10),
          Text(label,
              style:
                  const TextStyle(color: Colors.white70, fontSize: 13)),
        ],
      ),
    );
  }
}

// ================= GROWTH TRACKING SCREEN =================
class GrowthTrackingScreen extends StatefulWidget {
  @override
  _GrowthTrackingScreenState createState() => _GrowthTrackingScreenState();
}

class _GrowthTrackingScreenState extends State<GrowthTrackingScreen> {
  List<Lesion> _lesions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLesions();
  }

  Future<void> _loadLesions() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    final lesions = await getLesions();
    if (mounted) {
      setState(() {
        _lesions = lesions;
        _isLoading = false;
      });
    }
  }

  Color _getChangeColor(String change) {
    switch (change) {
      case 'Worsening':
        return kDanger;
      case 'Growing':
        return kWarning;
      case 'Improving':
        return kAccent;
      default:
        return kTextSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        title: const Text(
          'Growth Tracking',
          style: TextStyle(
              color: kTextPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_lesions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: kPrimaryLight,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_lesions.length} lesions',
                    style: const TextStyle(
                        color: kPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _lesions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                            color: kPrimaryLight,
                            borderRadius: BorderRadius.circular(20)),
                        child: const Icon(Icons.timeline,
                            color: kPrimary, size: 40),
                      ),
                      const SizedBox(height: 16),
                      const Text('No Tracked Lesions',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: kTextPrimary)),
                      const SizedBox(height: 8),
                      const Text(
                        'Enable growth tracking when scanning\nto monitor changes over time',
                        style:
                            TextStyle(color: kTextSecondary, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _lesions.length,
                  itemBuilder: (_, i) {
                    final lesion = _lesions[i];
                    final changeStatus = lesion.getChangeStatus();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: kCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: kBorder)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: _getChangeColor(changeStatus)
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  changeStatus == 'Worsening'
                                      ? Icons.trending_up
                                      : changeStatus == 'Growing'
                                          ? Icons.swap_horiz
                                          : changeStatus == 'Improving'
                                              ? Icons.trending_down
                                              : Icons.remove,
                                  color:
                                      _getChangeColor(changeStatus),
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(lesion.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            color: kTextPrimary)),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(Icons.location_on,
                                            size: 12,
                                            color: kTextSecondary),
                                        const SizedBox(width: 4),
                                        Text(lesion.bodyLocation,
                                            style: const TextStyle(
                                                color: kTextSecondary,
                                                fontSize: 12)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: _getChangeColor(changeStatus)
                                      .withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(changeStatus,
                                    style: TextStyle(
                                        color: _getChangeColor(
                                            changeStatus),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text('Scans',
                                        style: TextStyle(
                                            color: kTextSecondary,
                                            fontSize: 11)),
                                    Text('${lesion.scans.length}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            color: kTextPrimary)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text('First Scan',
                                        style: TextStyle(
                                            color: kTextSecondary,
                                            fontSize: 11)),
                                    Text(
                                        '${lesion.scans.first.date.day}/${lesion.scans.first.date.month}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            color: kTextPrimary)),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text('Latest',
                                        style: TextStyle(
                                            color: kTextSecondary,
                                            fontSize: 11)),
                                    Text(
                                        '${lesion.scans.last.date.day}/${lesion.scans.last.date.month}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                            color: kTextPrimary)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            LesionTimelineScreen(
                                                lesion: lesion),
                                      ),
                                    ).then((_) => _loadLesions());
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kPrimary,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                  child: const Text('View Timeline',
                                      style: TextStyle(fontSize: 13)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (lesion.scans.length >= 2)
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              LesionComparisonScreen(
                                                  lesion: lesion),
                                        ),
                                      );
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kCard,
                                      foregroundColor: kPrimary,
                                      side: const BorderSide(
                                          color: kPrimary),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                    child: const Text('Compare',
                                        style: TextStyle(fontSize: 13)),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

// ================= LESION TIMELINE SCREEN =================
class LesionTimelineScreen extends StatefulWidget {
  final Lesion lesion;
  const LesionTimelineScreen({required this.lesion});

  @override
  _LesionTimelineScreenState createState() => _LesionTimelineScreenState();
}

class _LesionTimelineScreenState extends State<LesionTimelineScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kBorder)),
            child: const Icon(Icons.arrow_back_ios_new,
                size: 16, color: kTextPrimary),
          ),
        ),
        title: Text(widget.lesion.name,
            style: const TextStyle(
                color: kTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.lesion.scans.length,
        itemBuilder: (_, i) {
          final scan = widget.lesion.scans[i];
          final isLatest = i == widget.lesion.scans.length - 1;
          return Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: isLatest ? kPrimary : kBorder,
                  width: isLatest ? 2 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isLatest)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                            color: kPrimary,
                            borderRadius: BorderRadius.circular(10)),
                        child: const Text('Latest',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700)),
                      ),
                    const Spacer(),
                    Text(
                        '${scan.date.day}/${scan.date.month}/${scan.date.year}',
                        style: const TextStyle(
                            color: kTextSecondary, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(File(scan.imagePath),
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                        child: _TimelineStat(
                            label: 'Condition',
                            value:
                                scan.result['disease'] ?? 'Unknown')),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _TimelineStat(
                            label: 'Confidence',
                            value:
                                '${((scan.result['confidence'] ?? 0).toDouble()).toInt()}%')),
                    const SizedBox(width: 8),
                    Expanded(
                        child: _TimelineStat(
                            label: 'Risk',
                            value: scan.result['risk'] ?? 'Unknown')),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TimelineStat extends StatelessWidget {
  final String label;
  final String value;
  const _TimelineStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
          color: kPrimaryLight, borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          Text(label,
              style:
                  const TextStyle(color: kTextSecondary, fontSize: 10)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: kTextPrimary)),
        ],
      ),
    );
  }
}

// ================= LESION COMPARISON SCREEN =================
class LesionComparisonScreen extends StatefulWidget {
  final Lesion lesion;
  const LesionComparisonScreen({required this.lesion});

  @override
  _LesionComparisonScreenState createState() =>
      _LesionComparisonScreenState();
}

class _LesionComparisonScreenState
    extends State<LesionComparisonScreen> {
  int _firstScanIndex = 0;
  int _secondScanIndex = 1;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kBorder)),
            child: const Icon(Icons.arrow_back_ios_new,
                size: 16, color: kTextPrimary),
          ),
        ),
        title: const Text('Compare Scans',
            style: TextStyle(
                color: kTextPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _firstScanIndex,
                    decoration: const InputDecoration(
                        labelText: 'First Scan',
                        border: OutlineInputBorder()),
                    items: List.generate(
                        widget.lesion.scans.length,
                        (i) => DropdownMenuItem(
                              value: i,
                              child: Text(
                                  'Scan ${i + 1} (${widget.lesion.scans[i].date.day}/${widget.lesion.scans[i].date.month})'),
                            )),
                    onChanged: (val) =>
                        setState(() => _firstScanIndex = val!),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _secondScanIndex,
                    decoration: const InputDecoration(
                        labelText: 'Second Scan',
                        border: OutlineInputBorder()),
                    items: List.generate(
                        widget.lesion.scans.length,
                        (i) => DropdownMenuItem(
                              value: i,
                              child: Text(
                                  'Scan ${i + 1} (${widget.lesion.scans[i].date.day}/${widget.lesion.scans[i].date.month})'),
                            )),
                    onChanged: (val) =>
                        setState(() => _secondScanIndex = val!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                    child: _ComparisonCard(
                        scan: widget.lesion.scans[_firstScanIndex],
                        label: 'Scan ${_firstScanIndex + 1}')),
                const SizedBox(width: 12),
                Expanded(
                    child: _ComparisonCard(
                        scan: widget.lesion.scans[_secondScanIndex],
                        label: 'Scan ${_secondScanIndex + 1}')),
              ],
            ),
            const SizedBox(height: 20),
            _ComparisonSummary(
              first: widget.lesion.scans[_firstScanIndex],
              second: widget.lesion.scans[_secondScanIndex],
            ),
          ],
        ),
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  final LesionScan scan;
  final String label;
  const _ComparisonCard({required this.scan, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder)),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: kTextPrimary)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(File(scan.imagePath),
                height: 120,
                width: double.infinity,
                fit: BoxFit.cover),
          ),
          const SizedBox(height: 8),
          Text(
              '${scan.date.day}/${scan.date.month}/${scan.date.year}',
              style: const TextStyle(
                  color: kTextSecondary, fontSize: 11)),
          const SizedBox(height: 8),
          Text(scan.result['disease'] ?? 'Unknown',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: kTextPrimary)),
          const SizedBox(height: 4),
          Text(
              '${((scan.result['confidence'] ?? 0).toDouble()).toInt()}% confidence',
              style: const TextStyle(
                  color: kTextSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}

class _ComparisonSummary extends StatelessWidget {
  final LesionScan first;
  final LesionScan second;
  const _ComparisonSummary(
      {required this.first, required this.second});

  @override
  Widget build(BuildContext context) {
    final confChange =
        ((second.result['confidence'] ?? 0).toDouble()) -
            ((first.result['confidence'] ?? 0).toDouble());
    final riskChanged =
        first.result['risk'] != second.result['risk'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: kPrimaryLight,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kPrimary)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.analytics, color: kPrimary, size: 20),
              SizedBox(width: 8),
              Text('Changes Detected',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: kTextPrimary,
                      fontSize: 14)),
            ],
          ),
          const SizedBox(height: 12),
          _ChangeRow(
            label: 'Confidence Change',
            value:
                '${confChange > 0 ? '+' : ''}${confChange.toInt()}%',
            isPositive: confChange > 0,
          ),
          const SizedBox(height: 8),
          _ChangeRow(
            label: 'Risk Level',
            value: riskChanged ? 'Changed' : 'Same',
            isPositive: !riskChanged,
          ),
          const SizedBox(height: 8),
          _ChangeRow(
            label: 'Days Between',
            value:
                '${second.date.difference(first.date).inDays} days',
            isPositive: true,
          ),
        ],
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isPositive;
  const _ChangeRow(
      {required this.label,
      required this.value,
      required this.isPositive});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                color: kTextSecondary, fontSize: 13)),
        Row(
          children: [
            Icon(
              isPositive
                  ? Icons.check_circle
                  : Icons.warning_amber,
              size: 14,
              color: isPositive ? kAccent : kWarning,
            ),
            const SizedBox(width: 4),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isPositive ? kAccent : kWarning,
                    fontSize: 13)),
          ],
        ),
      ],
    );
  }
}

// ================= HELPER WIDGETS =================
class _PickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PickButton(
      {required this.icon,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kBorder)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: kPrimary, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: kTextPrimary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class _TipRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _TipRow({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: kTextSecondary, size: 15),
          const SizedBox(width: 10),
          Text(text,
              style: const TextStyle(
                  color: kTextSecondary, fontSize: 13)),
        ],
      ),
    );
  }
}

// ================= LOADING SCREEN =================
class LoadingScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                  color: kPrimaryLight,
                  borderRadius: BorderRadius.circular(24)),
              child: const Icon(Icons.biotech_outlined,
                  color: kPrimary, size: 40),
            ),
            const SizedBox(height: 24),
            Shimmer.fromColors(
              baseColor: kTextSecondary,
              highlightColor: kPrimary,
              child: const Text("Analyzing your image...",
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: kTextPrimary)),
            ),
            const SizedBox(height: 10),
            const Text("AI is processing skin patterns",
                style:
                    TextStyle(color: kTextSecondary, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

// ================= HISTORY SCREEN =================
class HistoryScreen extends StatefulWidget {
  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> history = [];

  @override
  void initState() {
    super.initState();
    getHistory().then(
        (data) => setState(() => history = data.reversed.toList()));
  }

  Color _riskColor(String risk) {
    if (risk == "High") return kDanger;
    if (risk == "Medium") return kWarning;
    return kAccent;
  }

  Color _riskBgColor(String risk) {
    if (risk == "High") return const Color(0xFFFCEBEB);
    if (risk == "Medium") return const Color(0xFFFAEEDA);
    return const Color(0xFFE1F5EE);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        title: const Text("Scan History",
            style: TextStyle(
                color: kTextPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
      ),
      body: history.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                        color: kPrimaryLight,
                        borderRadius: BorderRadius.circular(20)),
                    child: const Icon(Icons.history,
                        color: kPrimary, size: 34),
                  ),
                  const SizedBox(height: 16),
                  const Text("No scans yet",
                      style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: kTextPrimary)),
                  const SizedBox(height: 6),
                  const Text("Your scan results will appear here",
                      style: TextStyle(
                          color: kTextSecondary, fontSize: 13)),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final item = history[i];
                final risk = item["risk"] ?? "Low";
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: kCard,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kBorder)),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                            color: _riskBgColor(risk),
                            borderRadius: BorderRadius.circular(12)),
                        child: Icon(Icons.healing,
                            color: _riskColor(risk), size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Text(item["disease"] ?? "Unknown",
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: kTextPrimary)),
                            const SizedBox(height: 3),
                            Text(
                                "Confidence: ${((item["confidence"] ?? 0).toDouble()).toInt()}%",
                                style: const TextStyle(
                                    color: kTextSecondary,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: _riskBgColor(risk),
                            borderRadius: BorderRadius.circular(20)),
                        child: Text(risk,
                            style: TextStyle(
                                color: _riskColor(risk),
                                fontWeight: FontWeight.w700,
                                fontSize: 12)),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ================= RESULT SCREEN =================
class ResultScreen extends StatefulWidget {
  final File image;
  final Map<String, dynamic> result;
  const ResultScreen({required this.image, required this.result});

  @override
  _ResultScreenState createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with TickerProviderStateMixin {
  double animatedValue = 0;
  bool _showHeatmap = false;
  List<int>? _heatmapBytes;

  @override
  void initState() {
    super.initState();

    if (widget.result.containsKey('heatmap') &&
        widget.result['heatmap'] != null) {
      try {
        setState(() {
          _heatmapBytes =
              base64Decode(widget.result['heatmap']);
        });
      } catch (e) {
        debugPrint("Error decoding heatmap: $e");
      }
    }

    Timer.periodic(const Duration(milliseconds: 15), (timer) {
      if (animatedValue >= (widget.result["confidence"] ?? 0)) {
        timer.cancel();
      } else {
        if (mounted) setState(() => animatedValue += 1.5);
      }
    });
  }

  Color getRiskColor(String risk) {
    if (risk == "High") return kDanger;
    if (risk == "Medium") return kWarning;
    return kAccent;
  }

  Color getRiskBg(String risk) {
    if (risk == "High") return const Color(0xFFFCEBEB);
    if (risk == "Medium") return const Color(0xFFFAEEDA);
    return const Color(0xFFE1F5EE);
  }

  Future<void> openDoctors() async {
    final url = Uri.parse(
        "https://www.google.com/maps/search/dermatologist+near+me");
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final disease = widget.result["disease"] ?? 'Unknown';
    final risk = widget.result["risk"] ?? 'Low';
    final confidence =
        (widget.result["confidence"] ?? 0).toDouble();
    final description =
        widget.result["description"] ?? 'No description available';
    final symptoms =
        widget.result["symptoms"] ?? 'No symptoms listed';
    final advice =
        widget.result["advice"] ?? 'No advice available';
    final warning = widget.result["warning"] ?? '';

    // ── NEW: precautions from backend ──
    final precautions =
        widget.result["precautions"] ?? '';

    final riskColor = getRiskColor(risk);
    final riskBg = getRiskBg(risk);

    return Scaffold(
      backgroundColor: kSurface,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                          color: kCard,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: kBorder)),
                      child: const Icon(Icons.arrow_back_ios_new,
                          size: 16, color: kTextPrimary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text("Analysis Result",
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: kTextPrimary)),
                  const Spacer(),
                  if (_heatmapBytes != null)
                    GestureDetector(
                      onTap: () => setState(
                          () => _showHeatmap = !_showHeatmap),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                            color: _showHeatmap
                                ? kPrimary
                                : kPrimaryLight,
                            borderRadius:
                                BorderRadius.circular(20)),
                        child: Row(
                          children: [
                            Icon(Icons.center_focus_weak,
                                size: 16,
                                color: _showHeatmap
                                    ? Colors.white
                                    : kPrimary),
                            const SizedBox(width: 6),
                            Text(
                                _showHeatmap
                                    ? "AI View"
                                    : "Original",
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: _showHeatmap
                                        ? Colors.white
                                        : kPrimary)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Scrollable content
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  // Image
                  Container(
                    height: 200,
                    width: double.infinity,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: kBorder)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(widget.image,
                              fit: BoxFit.cover),
                          if (_showHeatmap &&
                              _heatmapBytes != null)
                            Image.memory(
                                Uint8List.fromList(
                                    _heatmapBytes!),
                                fit: BoxFit.cover,
                                opacity:
                                    const AlwaysStoppedAnimation(
                                        0.8)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Condition + Confidence cards
                  Row(
                    children: [
                      Expanded(
                          child: _StatCard(
                              label: "Condition",
                              value: disease,
                              valueColor: kTextPrimary)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _StatCard(
                              label: "Confidence",
                              value:
                                  "${animatedValue.toInt()}%",
                              valueColor: kPrimary)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Risk banner
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: riskBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color:
                                riskColor.withOpacity(0.3))),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                              color:
                                  riskColor.withOpacity(0.2),
                              borderRadius:
                                  BorderRadius.circular(10)),
                          child: Icon(
                              risk == "High"
                                  ? Icons.warning_amber_rounded
                                  : risk == "Medium"
                                      ? Icons.info_outline
                                      : Icons
                                          .check_circle_outline,
                              color: riskColor,
                              size: 22),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            const Text("Risk Level",
                                style: TextStyle(
                                    color: kTextSecondary,
                                    fontSize: 12)),
                            Text(risk,
                                style: TextStyle(
                                    color: riskColor,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Confidence progress bar
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: kCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: kBorder)),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("AI Confidence",
                                style: TextStyle(
                                    color: kTextSecondary,
                                    fontSize: 13,
                                    fontWeight:
                                        FontWeight.w500)),
                            Text("${animatedValue.toInt()}%",
                                style: const TextStyle(
                                    color: kPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius:
                              BorderRadius.circular(10),
                          child: LinearProgressIndicator(
                            value: animatedValue / 100,
                            minHeight: 8,
                            backgroundColor: kPrimaryLight,
                            valueColor:
                                const AlwaysStoppedAnimation<
                                    Color>(kPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Warning banner (if any)
                  if (warning.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFCEBEB),
                          borderRadius:
                              BorderRadius.circular(14),
                          border: Border.all(
                              color:
                                  kDanger.withOpacity(0.3))),
                      child: Row(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber,
                              color: kDanger, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(warning,
                                  style: const TextStyle(
                                      color: kDanger,
                                      fontSize: 13,
                                      height: 1.4))),
                        ],
                      ),
                    ),

                  // Info cards
                  _InfoCard(
                      icon: Icons.help_outline,
                      title: "What is it?",
                      content: description),
                  const SizedBox(height: 10),
                  _InfoCard(
                      icon: Icons.coronavirus_outlined,
                      title: "Symptoms",
                      content: symptoms),
                  const SizedBox(height: 10),
                  _InfoCard(
                      icon: Icons.medical_services_outlined,
                      title: "Recommendation",
                      content: advice),
                  const SizedBox(height: 10),

                  // ── NEW: Precautions card ──
                  if (precautions.toString().isNotEmpty)
                    _PrecautionsCard(precautions: precautions.toString()),

                  const SizedBox(height: 20),

                  // Find dermatologist button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: openDoctors,
                      icon: const Icon(Icons.location_on,
                          size: 18),
                      label: const Text(
                          "Find Nearby Dermatologists"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 15),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(14)),
                        textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= PRECAUTIONS CARD =================
// Parses the bullet-point string from backend and renders
// each line as a styled row with a shield icon.
class _PrecautionsCard extends StatelessWidget {
  final String precautions;
  const _PrecautionsCard({required this.precautions});

  @override
  Widget build(BuildContext context) {
    // Split on newlines, strip leading "• " or "- " markers
    final lines = precautions
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'^[•\-]\s*'), '').trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE1F5EE), // kAccent light tint
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kAccent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: const [
              Icon(Icons.shield_outlined, color: kAccent, size: 18),
              SizedBox(width: 8),
              Text(
                "Precautions",
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: kTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Bullet rows
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(Icons.check_circle,
                        size: 14, color: kAccent),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: kTextSecondary,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================= SHARED RESULT WIDGETS =================
class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const _StatCard(
      {required this.label,
      required this.value,
      required this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: kTextSecondary, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 18)),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;
  const _InfoCard(
      {required this.icon,
      required this.title,
      required this.content});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: kPrimary, size: 16),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: kTextPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          Text(content,
              style: const TextStyle(
                  color: kTextSecondary,
                  fontSize: 13,
                  height: 1.5)),
        ],
      ),
    );
  }
}

// ================= PROFILE SCREEN =================
class ProfileScreen extends StatefulWidget {
  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, String> _userData = {'name': '...', 'email': '...'};
  int _totalScans = 0;
  int _highRiskCount = 0;
  bool _notificationsEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final data = await getProfileData();
    final history = await getHistory();

    if (mounted) {
      setState(() {
        _userData = data;
        _totalScans = history.length;
        _highRiskCount = history
            .where((item) => (item['risk'] ?? 'Low') == 'High')
            .length;
      });
    }
  }

  void _showEditProfileDialog() {
    final nameController =
        TextEditingController(text: _userData['name']);
    final emailController =
        TextEditingController(text: _userData['email']);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text("Edit Profile",
            style: TextStyle(
                color: kTextPrimary,
                fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: InputDecoration(
                  labelText: "Name",
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: kPrimary),
                      borderRadius: BorderRadius.circular(10))),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: emailController,
              decoration: InputDecoration(
                  labelText: "Email",
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: kPrimary),
                      borderRadius: BorderRadius.circular(10))),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel",
                  style: TextStyle(color: kTextSecondary))),
          ElevatedButton(
            onPressed: () async {
              await saveProfileData(
                  nameController.text, emailController.text);
              if (mounted) {
                setState(() {
                  _userData['name'] = nameController.text;
                  _userData['email'] = emailController.text;
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text("Save"),
          ),
        ],
      ),
    );
  }

  void _showClearDataDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: const Text("Clear All Data?",
            style: TextStyle(
                color: kDanger, fontWeight: FontWeight.w700)),
        content: const Text(
            "This will delete your scan history and profile settings permanently.",
            style: TextStyle(color: kTextSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel",
                  style: TextStyle(color: kTextSecondary))),
          ElevatedButton(
            style:
                ElevatedButton.styleFrom(backgroundColor: kDanger),
            onPressed: () async {
              await clearAllData();
              if (mounted) {
                setState(() {
                  _userData = {
                    'name': 'Guest User',
                    'email': 'Not provided'
                  };
                  _totalScans = 0;
                  _highRiskCount = 0;
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kSurface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Profile",
                      style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: kTextPrimary)),
                  IconButton(
                    onPressed: _showEditProfileDialog,
                    icon: const Icon(Icons.edit,
                        color: kPrimary, size: 20),
                    style: IconButton.styleFrom(
                        backgroundColor: kPrimaryLight,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(10))),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kBorder),
                    boxShadow: [
                      BoxShadow(
                          color: kPrimary.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ]),
                child: Row(
                  children: [
                    Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                            color: kPrimaryLight,
                            borderRadius:
                                BorderRadius.circular(16)),
                        child: const Icon(Icons.person,
                            color: kPrimary, size: 30)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(_userData['name'] ?? 'Guest User',
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: kTextPrimary)),
                          const SizedBox(height: 4),
                          Text(
                              _userData['email'] ??
                                  'Not provided',
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: kTextSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const Text("Your Statistics",
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kTextPrimary)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _ProfileStatCard(
                          label: "Total Scans",
                          value: _totalScans.toString(),
                          icon: Icons.document_scanner)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _ProfileStatCard(
                          label: "High Risk",
                          value: _highRiskCount.toString(),
                          icon: Icons.warning_amber,
                          valueColor: kDanger,
                          iconColor: kDanger)),
                ],
              ),
              const SizedBox(height: 24),
              const Text("Settings",
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: kTextPrimary)),
              const SizedBox(height: 12),
              _SettingsTile(
                  icon: Icons.notifications_outlined,
                  title: "Push Notifications",
                  subtitle: "Receive scan reminders",
                  trailing: Switch(
                      value: _notificationsEnabled,
                      onChanged: (val) => setState(
                          () => _notificationsEnabled = val),
                      activeColor: kPrimary)),
              _SettingsTile(
                  icon: Icons.security_outlined,
                  title: "Privacy Policy",
                  subtitle: "Read our data policy",
                  onTap: () => launchUrl(
                      Uri.parse("https://example.com/privacy"))),
              _SettingsTile(
                  icon: Icons.info_outline,
                  title: "About App",
                  subtitle: "Version 1.0.0",
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        backgroundColor: kCard,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(16)),
                        title: const Text("DermScan",
                            style: TextStyle(
                                color: kPrimary,
                                fontWeight: FontWeight.w800)),
                        content: const Text(
                            "AI-powered skin analysis tool for educational purposes.",
                            style: TextStyle(
                                color: kTextSecondary)),
                        actions: [
                          TextButton(
                              onPressed: () =>
                                  Navigator.pop(context),
                              child: const Text("Close"))
                        ],
                      ),
                    );
                  }),
              _SettingsTile(
                  icon: Icons.delete_outline,
                  title: "Clear Data",
                  subtitle: "Reset history and settings",
                  titleColor: kDanger,
                  iconColor: kDanger,
                  onTap: _showClearDataDialog),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content:
                                Text("Logged out successfully")));
                  },
                  style: OutlinedButton.styleFrom(
                      foregroundColor: kTextSecondary,
                      side: const BorderSide(color: kBorder),
                      padding:
                          const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(14))),
                  child: const Text("Log Out",
                      style:
                          TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;
  final Color? iconColor;
  const _ProfileStatCard(
      {required this.label,
      required this.value,
      required this.icon,
      this.valueColor,
      this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor ?? kPrimary, size: 20),
          const SizedBox(height: 10),
          Text(value,
              style: TextStyle(
                  color: valueColor ?? kTextPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 20)),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  color: kTextSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? titleColor;
  final Color? iconColor;
  const _SettingsTile(
      {required this.icon,
      required this.title,
      this.subtitle,
      this.trailing,
      this.onTap,
      this.titleColor,
      this.iconColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder)),
        child: Row(
          children: [
            Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color:
                        (iconColor ?? kPrimary).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon,
                    color: iconColor ?? kPrimary, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          color: titleColor ?? kTextPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!,
                        style: const TextStyle(
                            color: kTextSecondary, fontSize: 12))
                  ],
                ],
              ),
            ),
            trailing ??
                const Icon(Icons.chevron_right,
                    color: kTextSecondary),
          ],
        ),
      ),
    );
  }
}