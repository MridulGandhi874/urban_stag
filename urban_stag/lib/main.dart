// ============================================================
// SKILLR - Complete Flutter Application
// Fiverr + Zomato + Freelancer for Gig Services
// CERN AI-Powered Matching Engine
// ============================================================
//
// SETUP INSTRUCTIONS:
// 1. flutter create skillr && replace lib/main.dart with this file
// 2. Add to pubspec.yaml dependencies:
//    http: ^1.2.0
//    shared_preferences: ^2.2.2
//    google_maps_flutter: ^2.5.3
//    geolocator: ^11.0.0
//    image_picker: ^1.0.7
//    cached_network_image: ^3.3.1
//    flutter_rating_bar: ^4.0.1
//    timeago: ^3.6.1
//    lottie: ^3.0.0
//    shimmer: ^3.0.0
//    badges: ^3.1.2
//    intl: ^0.19.0
//    url_launcher: ^6.2.5
//    permission_handler: ^11.3.0
//    flutter_svg: ^2.0.9
//    provider: ^6.1.2
//    dio: ^5.4.1
//    socket_io_client: ^2.0.3+1
// 3. Add Google Maps API key to AndroidManifest.xml & Info.plist
// 4. Update API_BASE_URL to your Flask server IP

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ─── CONSTANTS ───────────────────────────────────────────────────────────────

const String API_BASE = "http://10.0.2.2:5000/api"; // Use your server IP in prod
const Color kPrimary = Color(0xFF6C63FF);
const Color kSecondary = Color(0xFFFF6584);
const Color kAccent = Color(0xFF43E97B);
const Color kDark = Color(0xFF1A1A2E);
const Color kSurface = Color(0xFF16213E);
const Color kCard = Color(0xFF0F3460);
const Color kGold = Color(0xFFFFD700);
const Color kText = Color(0xFFE8E8F0);
const Color kTextSub = Color(0xFF8888AA);

final ThemeData kTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  colorScheme: const ColorScheme.dark(
    primary: kPrimary,
    secondary: kSecondary,
    tertiary: kAccent,
    surface: kSurface,
    onPrimary: Colors.white,
    onSurface: kText,
  ),
  scaffoldBackgroundColor: kDark,
  fontFamily: 'SF Pro Display',
  cardTheme: CardTheme(
    color: kCard,
    elevation: 0,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: kDark,
    foregroundColor: kText,
    elevation: 0,
    centerTitle: false,
    titleTextStyle: TextStyle(
      fontFamily: 'SF Pro Display',
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: kText,
      letterSpacing: -0.5,
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      elevation: 0,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: kSurface,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: Colors.transparent),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: const BorderSide(color: kPrimary, width: 2),
    ),
    labelStyle: const TextStyle(color: kTextSub),
    hintStyle: const TextStyle(color: kTextSub),
  ),
);

// ─── API SERVICE ─────────────────────────────────────────────────────────────

class ApiService {
  static String? _token;
  static Map<String, dynamic>? _currentUser;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    final userStr = prefs.getString('user');
    if (userStr != null) {
      _currentUser = jsonDecode(userStr);
    }
  }

  static Map<String, dynamic>? get currentUser => _currentUser;
  static bool get isLoggedIn => _token != null;
  static String get role => _currentUser?['role'] ?? 'consumer';

  static Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (_token != null) 'Authorization': 'Bearer $_token',
  };

  static Future<Map<String, dynamic>> _req(
      String method, String path, {Map<String, dynamic>? body, Map<String, String>? params}) async {
    Uri uri = Uri.parse('$API_BASE$path');
    if (params != null) uri = uri.replace(queryParameters: params);

    try {
      http.Response res;
      switch (method) {
        case 'GET': res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 15)); break;
        case 'POST': res = await http.post(uri, headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15)); break;
        case 'PUT': res = await http.put(uri, headers: _headers, body: jsonEncode(body)).timeout(const Duration(seconds: 15)); break;
        case 'DELETE': res = await http.delete(uri, headers: _headers).timeout(const Duration(seconds: 15)); break;
        default: throw Exception('Unknown method');
      }
      return jsonDecode(res.body);
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // Auth
  static Future<Map<String, dynamic>> register(Map<String, dynamic> data) async {
    final res = await _req('POST', '/auth/register', body: data);
    if (res['success'] == true) await _saveSession(res['data']);
    return res;
  }

  static Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await _req('POST', '/auth/login', body: {'email': email, 'password': password});
    if (res['success'] == true) await _saveSession(res['data']);
    return res;
  }

  static Future<void> logout() async {
    await _req('POST', '/auth/logout');
    _token = null;
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user');
  }

  static Future<void> _saveSession(Map<String, dynamic> data) async {
    _token = data['access_token'];
    _currentUser = data['user'];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', _token!);
    await prefs.setString('user', jsonEncode(_currentUser));
  }

  // User
  static Future<Map<String, dynamic>> getMe() => _req('GET', '/user/me');
  static Future<Map<String, dynamic>> updateMe(Map<String, dynamic> data) => _req('PUT', '/user/me', body: data);
  static Future<Map<String, dynamic>> getUser(String id) => _req('GET', '/user/$id');

  // Categories
  static Future<Map<String, dynamic>> getCategories() => _req('GET', '/categories');

  // Gigs
  static Future<Map<String, dynamic>> getGigs({String? category, String? q, double? lat, double? lng, String sort = 'cern'}) =>
      _req('GET', '/gigs', params: {
        if (category != null) 'category': category,
        if (q != null) 'q': q,
        if (lat != null) 'lat': lat.toString(),
        if (lng != null) 'lng': lng.toString(),
        'sort': sort,
      });

  static Future<Map<String, dynamic>> getGig(String id) => _req('GET', '/gigs/$id');
  static Future<Map<String, dynamic>> createGig(Map<String, dynamic> data) => _req('POST', '/gigs', body: data);
  static Future<Map<String, dynamic>> updateGig(String id, Map<String, dynamic> data) => _req('PUT', '/gigs/$id', body: data);
  static Future<Map<String, dynamic>> deleteGig(String id) => _req('DELETE', '/gigs/$id');
  static Future<Map<String, dynamic>> myGigs() => _req('GET', '/gigs/my/list');
  static Future<Map<String, dynamic>> featuredGigs() => _req('GET', '/gigs/featured');
  static Future<Map<String, dynamic>> trendingGigs() => _req('GET', '/gigs/trending');

  // Intent/CERN
  static Future<void> recordView(String gigId, double duration) =>
      _req('POST', '/intent/view', body: {'gig_id': gigId, 'duration_seconds': duration});
  static Future<Map<String, dynamic>> getChi(String gigId) => _req('GET', '/intent/chi/$gigId');

  // Bookings
  static Future<Map<String, dynamic>> createBooking(Map<String, dynamic> data) => _req('POST', '/bookings', body: data);
  static Future<Map<String, dynamic>> getBookings({String role = 'consumer', String? status}) =>
      _req('GET', '/bookings', params: {'role': role, if (status != null) 'status': status});
  static Future<Map<String, dynamic>> updateBookingStatus(String id, String status, {String? reason}) =>
      _req('PUT', '/bookings/$id/status', body: {'status': status, if (reason != null) 'reason': reason});

  // Reviews
  static Future<Map<String, dynamic>> createReview(Map<String, dynamic> data) => _req('POST', '/reviews', body: data);
  static Future<Map<String, dynamic>> getReviews(String gigId) => _req('GET', '/reviews/$gigId');

  // Messages
  static Future<Map<String, dynamic>> getConversations() => _req('GET', '/conversations');
  static Future<Map<String, dynamic>> getMessages(String convId) => _req('GET', '/messages/$convId');
  static Future<Map<String, dynamic>> sendMessage(String convId, String text) =>
      _req('POST', '/messages', body: {'conv_id': convId, 'text': text});

  // Search
  static Future<Map<String, dynamic>> search(String q) => _req('GET', '/search', params: {'q': q});

  // Dashboard
  static Future<Map<String, dynamic>> consumerDashboard() => _req('GET', '/dashboard/consumer');
  static Future<Map<String, dynamic>> providerDashboard() => _req('GET', '/dashboard/provider');
}

// ─── MODELS ──────────────────────────────────────────────────────────────────

class Category {
  final String slug, name, icon, color;
  final List<String> subcategories;
  Category({required this.slug, required this.name, required this.icon, required this.color, required this.subcategories});
  factory Category.fromJson(Map<String, dynamic> j) => Category(
    slug: j['slug'] ?? '', name: j['name'] ?? '', icon: j['icon'] ?? '🔧',
    color: j['color'] ?? '#6C63FF', subcategories: List<String>.from(j['subcategories'] ?? []),
  );
  Color get colorVal {
    try {
      return Color(int.parse(color.replaceFirst('#', '0xFF')));
    } catch (_) { return kPrimary; }
  }
}

class Gig {
  final String id, title, category, description, providerName, providerAvatar, city;
  final double rating, distanceKm, cernScore, chiValue;
  final int totalReviews, totalBookings, views;
  final List<dynamic> pricing, images, tags;
  final Map<String, dynamic>? provider;
  final bool isActive, isFeatured;

  Gig.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? '',
        title = j['title'] ?? '',
        category = j['category'] ?? '',
        description = j['description'] ?? '',
        providerName = j['provider_name'] ?? '',
        providerAvatar = j['provider_avatar'] ?? '',
        city = j['city'] ?? '',
        rating = (j['rating'] ?? 0).toDouble(),
        distanceKm = (j['distance_km'] ?? 0).toDouble(),
        cernScore = (j['cern_score'] ?? 0).toDouble(),
        chiValue = (j['chi_value'] ?? 0).toDouble(),
        totalReviews = j['total_reviews'] ?? 0,
        totalBookings = j['total_bookings'] ?? 0,
        views = j['views'] ?? 0,
        pricing = j['pricing'] ?? [],
        images = j['images'] ?? [],
        tags = j['tags'] ?? [],
        provider = j['provider'],
        isActive = j['is_active'] ?? true,
        isFeatured = j['is_featured'] ?? false;

  double get startingPrice {
    if (pricing.isEmpty) return 0;
    return (pricing[0]['price'] ?? 0).toDouble();
  }

  String get competitionLevel {
    if (chiValue < 1) return 'Available';
    if (chiValue < 3) return 'Busy';
    return 'High Demand';
  }

  Color get competitionColor {
    if (chiValue < 1) return kAccent;
    if (chiValue < 3) return Colors.orange;
    return kSecondary;
  }
}

class Booking {
  final String id, gigTitle, gigCategory, providerName, consumerName;
  final String status, paymentStatus, notes, scheduledDate, scheduledTime;
  final double amount;
  final Map<String, dynamic> pricingTier;
  final DateTime createdAt;

  Booking.fromJson(Map<String, dynamic> j)
      : id = j['id'] ?? '',
        gigTitle = j['gig_title'] ?? '',
        gigCategory = j['gig_category'] ?? '',
        providerName = j['provider_name'] ?? '',
        consumerName = j['consumer_name'] ?? '',
        status = j['status'] ?? 'pending',
        paymentStatus = j['payment_status'] ?? 'pending',
        notes = j['notes'] ?? '',
        scheduledDate = j['scheduled_date'] ?? '',
        scheduledTime = j['scheduled_time'] ?? '',
        amount = (j['amount'] ?? 0).toDouble(),
        pricingTier = j['pricing_tier'] ?? {},
        createdAt = j['created_at'] != null ? DateTime.tryParse(j['created_at']) ?? DateTime.now() : DateTime.now();

  Color get statusColor => switch(status) {
    'pending' => Colors.orange,
    'accepted' => kPrimary,
    'in_progress' => Colors.blue,
    'completed' => kAccent,
    'cancelled' => kSecondary,
    'rejected' => Colors.red,
    _ => kTextSub,
  };

  IconData get statusIcon => switch(status) {
    'pending' => Icons.hourglass_empty_rounded,
    'accepted' => Icons.check_circle_rounded,
    'in_progress' => Icons.pending_actions_rounded,
    'completed' => Icons.task_alt_rounded,
    'cancelled' => Icons.cancel_rounded,
    _ => Icons.info_rounded,
  };
}

// ─── MAIN APP ────────────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: kDark,
  ));
  await ApiService.init();
  runApp(const SkillrApp());
}

class SkillrApp extends StatelessWidget {
  const SkillrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Skillr',
      theme: kTheme,
      debugShowCheckedModeBanner: false,
      home: ApiService.isLoggedIn ? const MainShell() : const LandingPage(),
    );
  }
}

// ─── MAIN SHELL ──────────────────────────────────────────────────────────────

class MainShell extends StatefulWidget {
  final int initialIndex;
  const MainShell({super.key, this.initialIndex = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  late int _idx;
  late final List<Widget> _pages;
  int _msgCount = 0;
  int _bookingCount = 0;

  @override
  void initState() {
    super.initState();
    _idx = widget.initialIndex;
    final isProvider = ApiService.role == 'provider';
    _pages = isProvider ? [
      const HomeScreen(),
      const ProviderGigsScreen(),
      const BookingsScreen(role: 'provider'),
      const MessagesScreen(),
      const ProfileScreen(),
    ] : [
      const HomeScreen(),
      const ExploreScreen(),
      const BookingsScreen(role: 'consumer'),
      const MessagesScreen(),
      const ProfileScreen(),
    ];
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final convRes = await ApiService.getConversations();
    if (convRes['success'] == true) {
      final uid = ApiService.currentUser?['id'] ?? '';
      final convs = (convRes['data'] as List?) ?? [];
      int unread = 0;
      for (final c in convs) {
        unread += ((c['unread'] as Map?)?[uid] ?? 0) as int;
      }
      if (mounted) setState(() => _msgCount = unread);
    }

    final bookRes = await ApiService.getBookings(role: ApiService.role, status: 'pending');
    if (bookRes['success'] == true) {
      final books = (bookRes['data'] as List?) ?? [];
      if (mounted) setState(() => _bookingCount = books.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isProvider = ApiService.role == 'provider';
    return Scaffold(
      body: IndexedStack(index: _idx, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: kSurface,
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(icon: Icons.home_rounded, label: 'Home', idx: 0, current: _idx, onTap: (i) => setState(() => _idx = i)),
                _NavItem(icon: isProvider ? Icons.work_rounded : Icons.explore_rounded,
                    label: isProvider ? 'My Gigs' : 'Explore', idx: 1, current: _idx, onTap: (i) => setState(() => _idx = i)),
                _NavItem(icon: Icons.receipt_long_rounded, label: 'Bookings', idx: 2, current: _idx,
                    badge: _bookingCount, onTap: (i) => setState(() => _idx = i)),
                _NavItem(icon: Icons.chat_bubble_rounded, label: 'Messages', idx: 3, current: _idx,
                    badge: _msgCount, onTap: (i) => setState(() => _idx = i)),
                _NavItem(icon: Icons.person_rounded, label: 'Profile', idx: 4, current: _idx, onTap: (i) => setState(() => _idx = i)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final int idx, current, badge;
  final Function(int) onTap;

  const _NavItem({required this.icon, required this.label, required this.idx,
    required this.current, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    final active = idx == current;
    return GestureDetector(
      onTap: () => onTap(idx),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? kPrimary.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: active ? kPrimary : kTextSub, size: 24),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600,
                color: active ? kPrimary : kTextSub,
              )),
            ]),
            if (badge > 0) Positioned(
              top: -4, right: -8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: kSecondary, shape: BoxShape.circle),
                child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── LANDING PAGE ────────────────────────────────────────────────────────────

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});
  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> with TickerProviderStateMixin {
  late AnimationController _heroCtrl, _floatCtrl;
  late Animation<double> _heroFade, _heroSlide, _floatAnim;

  final _services = [
    ('⚡', 'Electrician'), ('🔧', 'Plumber'), ('👨‍🍳', 'Chef'),
    ('🔩', 'Mechanic'), ('🧹', 'Cleaner'), ('🪚', 'Carpenter'),
  ];

  @override
  void initState() {
    super.initState();
    _heroCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _floatCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);

    _heroFade = CurvedAnimation(parent: _heroCtrl, curve: const Interval(0.0, 0.6, curve: Curves.easeOut));
    _heroSlide = Tween(begin: 60.0, end: 0.0).animate(
        CurvedAnimation(parent: _heroCtrl, curve: const Interval(0.0, 0.8, curve: Curves.easeOut)));
    _floatAnim = Tween(begin: -8.0, end: 8.0).animate(
        CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut));

    _heroCtrl.forward();
  }

  @override
  void dispose() {
    _heroCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
          ),
        ),
        child: SafeArea(
          child: Column(children: [
            // Logo bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [kPrimary, kSecondary]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text('S', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 10),
                const Text('Skillr', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)),
                const Spacer(),
                TextButton(
                  onPressed: () => _toLogin(),
                  child: const Text('Log In', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),

            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: AnimatedBuilder(
                    animation: _heroCtrl,
                    builder: (ctx, _) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 32),

                        // Hero text
                        Opacity(
                          opacity: _heroFade.value,
                          child: Transform.translate(
                            offset: Offset(0, _heroSlide.value),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: kAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: kAccent.withOpacity(0.3)),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Container(width: 6, height: 6, decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle)),
                                  const SizedBox(width: 8),
                                  const Text('AI-Powered Service Matching', style: TextStyle(color: kAccent, fontSize: 12, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                              const SizedBox(height: 20),
                              const Text('Find Trusted\nSkilled Pros\nNear You', style: TextStyle(
                                fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white,
                                height: 1.1, letterSpacing: -2,
                              )),
                              const SizedBox(height: 16),
                              Text(
                                'Book verified electricians, cooks, mechanics & more.\nOur CERN AI ensures you always get the right match.',
                                style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.7), height: 1.6),
                              ),
                            ]),
                          ),
                        ),

                        const SizedBox(height: 40),

                        // Floating service cards
                        AnimatedBuilder(
                          animation: _floatCtrl,
                          builder: (ctx, _) => Transform.translate(
                            offset: Offset(0, _floatAnim.value),
                            child: _buildServiceGrid(),
                          ),
                        ),

                        const SizedBox(height: 40),

                        // Stats row
                        Opacity(
                          opacity: _heroFade.value,
                          child: Row(children: [
                            _StatChip('10K+', 'Skilled Pros'),
                            const SizedBox(width: 12),
                            _StatChip('50K+', 'Happy Clients'),
                            const SizedBox(width: 12),
                            _StatChip('4.9★', 'Avg Rating'),
                          ]),
                        ),

                        const SizedBox(height: 40),

                        // CTA Buttons
                        Opacity(
                          opacity: _heroFade.value,
                          child: Column(children: [
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RegisterPage())),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  backgroundColor: kPrimary,
                                ),
                                child: const Text('Get Started Free', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: () => Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => const RegisterPage(initialRole: 'provider'))),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 18),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                                  side: const BorderSide(color: kAccent, width: 2),
                                  foregroundColor: kAccent,
                                ),
                                child: const Text('Offer Your Skills', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                              ),
                            ),
                          ]),
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildServiceGrid() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: _services.map((s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.08),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: Colors.white.withOpacity(0.15)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(s.$1, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(s.$2, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ]),
      )).toList(),
    );
  }

  Widget _StatChip(String val, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Column(children: [
          Text(val, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: kPrimary)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: kTextSub, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  void _toLogin() => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPage()));
}

// ─── LOGIN PAGE ───────────────────────────────────────────────────────────────

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false, _showPass = false;
  String? _error;

  Future<void> _login() async {
    setState(() { _loading = true; _error = null; });
    final res = await ApiService.login(_emailCtrl.text.trim(), _passCtrl.text);
    if (!mounted) return;
    if (res['success'] == true) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainShell()), (_) => false);
    } else {
      setState(() { _loading = false; _error = res['error'] ?? 'Login failed'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [kDark, kSurface]),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconButton(onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_rounded, color: kText)),
              const SizedBox(height: 32),
              const Text('Welcome\nBack! 👋', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900,
                  color: Colors.white, height: 1.1, letterSpacing: -1.5)),
              const SizedBox(height: 8),
              Text('Sign in to continue', style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.6))),
              const SizedBox(height: 48),

              if (_error != null) Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: kSecondary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kSecondary.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: kSecondary, size: 18),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_error!, style: const TextStyle(color: kSecondary))),
                ]),
              ),

              TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined))),
              const SizedBox(height: 16),
              TextField(controller: _passCtrl, obscureText: !_showPass,
                  style: const TextStyle(color: kText),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showPass = !_showPass),
                    ),
                  )),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Sign In'),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const RegisterPage())),
                  child: RichText(text: TextSpan(
                    style: const TextStyle(fontSize: 15),
                    children: [
                      TextSpan(text: "Don't have an account? ", style: TextStyle(color: Colors.white.withOpacity(0.6))),
                      const TextSpan(text: 'Sign Up', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700)),
                    ],
                  )),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─── REGISTER PAGE ───────────────────────────────────────────────────────────

class RegisterPage extends StatefulWidget {
  final String initialRole;
  const RegisterPage({super.key, this.initialRole = 'consumer'});
  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  late String _role;
  bool _loading = false, _showPass = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _role = widget.initialRole;
  }

  Future<void> _register() async {
    if (_nameCtrl.text.trim().isEmpty || _emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      setState(() => _error = 'All fields are required');
      return;
    }
    if (_passCtrl.text.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final res = await ApiService.register({
      'name': _nameCtrl.text.trim(),
      'email': _emailCtrl.text.trim(),
      'password': _passCtrl.text,
      'phone': _phoneCtrl.text.trim(),
      'role': _role,
    });
    if (!mounted) return;
    if (res['success'] == true) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainShell()), (_) => false);
    } else {
      setState(() { _loading = false; _error = res['error'] ?? 'Registration failed'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [kDark, kSurface]),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconButton(onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_rounded, color: kText)),
              const SizedBox(height: 24),
              const Text('Create\nAccount ✨', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900,
                  color: Colors.white, height: 1.1, letterSpacing: -1.5)),
              const SizedBox(height: 32),

              // Role toggle
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  _RoleTab('Looking for Services', 'consumer', _role, (r) => setState(() => _role = r)),
                  _RoleTab('Offering Services', 'provider', _role, (r) => setState(() => _role = r)),
                ]),
              ),
              const SizedBox(height: 24),

              if (_error != null) Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: kSecondary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kSecondary.withOpacity(0.3)),
                ),
                child: Text(_error!, style: const TextStyle(color: kSecondary)),
              ),

              TextField(controller: _nameCtrl, style: const TextStyle(color: kText),
                  decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person_outlined))),
              const SizedBox(height: 14),
              TextField(controller: _emailCtrl, keyboardType: TextInputType.emailAddress,
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined))),
              const SizedBox(height: 14),
              TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone,
                  style: const TextStyle(color: kText),
                  decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_outlined))),
              const SizedBox(height: 14),
              TextField(controller: _passCtrl, obscureText: !_showPass,
                  style: const TextStyle(color: kText),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outlined),
                    suffixIcon: IconButton(
                      icon: Icon(_showPass ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showPass = !_showPass),
                    ),
                  )),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _register,
                  child: _loading
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_role == 'provider' ? 'Start Earning' : 'Find Services'),
                ),
              ),
              const SizedBox(height: 20),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginPage())),
                  child: RichText(text: TextSpan(
                    style: const TextStyle(fontSize: 15),
                    children: [
                      TextSpan(text: "Already have an account? ", style: TextStyle(color: Colors.white.withOpacity(0.6))),
                      const TextSpan(text: 'Sign In', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700)),
                    ],
                  )),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _RoleTab(String label, String value, String current, Function(String) onTap) {
    final active = value == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: active ? kPrimary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, textAlign: TextAlign.center,
              style: TextStyle(
                color: active ? Colors.white : kTextSub,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                fontSize: 13,
              )),
        ),
      ),
    );
  }
}

// ─── HOME SCREEN ──────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Category> _categories = [];
  List<Gig> _featured = [];
  List<Gig> _trending = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final futures = await Future.wait([
      ApiService.getCategories(),
      ApiService.featuredGigs(),
      ApiService.trendingGigs(),
    ]);

    if (!mounted) return;
    setState(() {
      _categories = ((futures[0]['data'] as List?) ?? []).map((c) => Category.fromJson(c)).toList();
      _featured = ((futures[1]['data'] as List?) ?? []).map((g) => Gig.fromJson(g)).toList();
      _trending = ((futures[2]['data'] as List?) ?? []).map((g) => Gig.fromJson(g)).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ApiService.currentUser;
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: kPrimary))
            : RefreshIndicator(
          color: kPrimary, backgroundColor: kSurface,
          onRefresh: _load,
          child: CustomScrollView(slivers: [
            // Header
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Good ${_greeting()}! 👋', style: const TextStyle(color: kTextSub, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(user?['name'] ?? 'User', style: const TextStyle(
                        color: kText, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  ]),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsPage())),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: kSurface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: const Icon(Icons.notifications_outlined, color: kText),
                    ),
                  ),
                ]),
                const SizedBox(height: 20),

                // Search bar
                GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SearchPage())),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.search_rounded, color: kTextSub),
                      const SizedBox(width: 12),
                      Text('Search services, skills...', style: TextStyle(color: kTextSub.withOpacity(0.8), fontSize: 15)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(10)),
                        child: const Icon(Icons.tune_rounded, color: Colors.white, size: 16),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 28),

                // CERN Banner
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6C63FF), Color(0xFF9C8CFF)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('🧠 CERN AI Active', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 4),
                      Text('Smart matching reduces wait by 54%', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12)),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12)),
                    ),
                  ]),
                ),
                const SizedBox(height: 28),
              ]),
            )),

            // Categories
            SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SectionHeader('All Categories', onSeeAll: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExploreScreen()))),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _categories.length,
                  itemBuilder: (_, i) => _CategoryChip(_categories[i]),
                ),
              ),
              const SizedBox(height: 28),
            ])),

            // Featured
            if (_featured.isNotEmpty) SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SectionHeader('⭐ Top Rated', onSeeAll: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExploreScreen()))),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 260,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _featured.length,
                  itemBuilder: (_, i) => GigCard(_featured[i], compact: true),
                ),
              ),
              const SizedBox(height: 28),
            ])),

            // Trending
            if (_trending.isNotEmpty) SliverToBoxAdapter(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _SectionHeader('🔥 Trending Now'),
              ),
              const SizedBox(height: 14),
            ])),

            if (_trending.isNotEmpty) SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(delegate: SliverChildBuilderDelegate(
                    (_, i) => GigListTile(_trending[i]),
                childCount: _trending.length,
              )),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ]),
        ),
      ),
    );
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Morning';
    if (h < 17) return 'Afternoon';
    return 'Evening';
  }
}

Widget _SectionHeader(String title, {VoidCallback? onSeeAll}) {
  return Row(children: [
    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kText, letterSpacing: -0.5)),
    const Spacer(),
    if (onSeeAll != null) GestureDetector(
      onTap: onSeeAll,
      child: const Text('See All', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w600)),
    ),
  ]);
}

class _CategoryChip extends StatelessWidget {
  final Category cat;
  const _CategoryChip(this.cat);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => ExploreScreen(initialCategory: cat.slug))),
      child: Container(
        width: 80,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          color: cat.colorVal.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cat.colorVal.withOpacity(0.3)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(cat.icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 6),
          Text(cat.name, textAlign: TextAlign.center, maxLines: 2,
              style: const TextStyle(fontSize: 10, color: kText, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class GigCard extends StatelessWidget {
  final Gig gig;
  final bool compact;
  const GigCard(this.gig, {super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GigDetailPage(gigId: gig.id))),
      child: Container(
        width: compact ? 200 : double.infinity,
        margin: compact ? const EdgeInsets.only(right: 14) : const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Image
          Container(
            height: compact ? 120 : 180,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              gradient: LinearGradient(
                colors: [kPrimary.withOpacity(0.7), kSecondary.withOpacity(0.5)],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
            ),
            child: Stack(children: [
              if (gig.images.isNotEmpty) ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: Image.network(gig.images[0], fit: BoxFit.cover, width: double.infinity, height: double.infinity,
                    errorBuilder: (_, __, ___) => _GigPlaceholder(gig.category)),
              ) else _GigPlaceholder(gig.category),

              // Competition badge
              Positioned(top: 10, right: 10, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: gig.competitionColor.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(gig.competitionLevel, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              )),

              if (gig.isFeatured) Positioned(top: 10, left: 10, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(20)),
                child: const Text('FEATURED', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w800)),
              )),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(radius: 12, backgroundColor: kPrimary,
                    child: Text(gig.providerName.isNotEmpty ? gig.providerName[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
                const SizedBox(width: 6),
                Expanded(child: Text(gig.providerName, style: const TextStyle(color: kTextSub, fontSize: 11),
                    overflow: TextOverflow.ellipsis)),
              ]),
              const SizedBox(height: 6),
              Text(gig.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kText, fontWeight: FontWeight.w700, fontSize: 14, height: 1.3)),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.star_rounded, color: kGold, size: 14),
                const SizedBox(width: 3),
                Text(gig.rating.toStringAsFixed(1), style: const TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                Text('(${gig.totalReviews})', style: const TextStyle(color: kTextSub, fontSize: 11)),
                const Spacer(),
                Text('From ₹${gig.startingPrice.toInt()}', style: const TextStyle(
                    color: kAccent, fontSize: 13, fontWeight: FontWeight.w800)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _GigPlaceholder extends StatelessWidget {
  final String category;
  const _GigPlaceholder(this.category);

  static const _icons = {
    'electrician': '⚡', 'plumber': '🔧', 'cook': '👨‍🍳',
    'mechanic': '🔩', 'cleaner': '🧹', 'carpenter': '🪚',
    'painter': '🎨', 'tutor': '📚', 'photographer': '📸',
    'driver': '🚗', 'nurse': '💊', 'it_support': '💻',
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      child: Text(_icons[category] ?? '🔧', style: const TextStyle(fontSize: 48)),
    );
  }
}

class GigListTile extends StatelessWidget {
  final Gig gig;
  const GigListTile(this.gig, {super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GigDetailPage(gigId: gig.id))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(children: [
          Container(
            width: 70, height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(colors: [kPrimary.withOpacity(0.6), kSecondary.withOpacity(0.4)]),
            ),
            child: Center(child: _GigPlaceholder(gig.category)),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(gig.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: kText, fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            Text(gig.providerName, style: const TextStyle(color: kTextSub, fontSize: 12)),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.star_rounded, color: kGold, size: 13),
              const SizedBox(width: 3),
              Text(gig.rating.toStringAsFixed(1), style: const TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(width: 10),
              Container(width: 4, height: 4, decoration: BoxDecoration(color: gig.competitionColor, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(gig.competitionLevel, style: TextStyle(color: gig.competitionColor, fontSize: 11, fontWeight: FontWeight.w600)),
            ]),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹${gig.startingPrice.toInt()}', style: const TextStyle(color: kAccent, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('onwards', style: const TextStyle(color: kTextSub, fontSize: 10)),
          ]),
        ]),
      ),
    );
  }
}

// ─── EXPLORE SCREEN ──────────────────────────────────────────────────────────

class ExploreScreen extends StatefulWidget {
  final String? initialCategory;
  const ExploreScreen({super.key, this.initialCategory});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  List<Category> _categories = [];
  List<Gig> _gigs = [];
  String? _selectedCat;
  String _sort = 'cern';
  bool _loading = true;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _selectedCat = widget.initialCategory;
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final futures = await Future.wait([
      ApiService.getCategories(),
      ApiService.getGigs(category: _selectedCat, sort: _sort),
    ]);
    if (!mounted) return;
    setState(() {
      _categories = ((futures[0]['data'] as List?) ?? []).map((c) => Category.fromJson(c)).toList();
      _gigs = ((futures[1]['data']?['gigs'] as List?) ?? []).map((g) => Gig.fromJson(g)).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Row(children: [
                const Text('Explore', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kText, letterSpacing: -1)),
                const Spacer(),
                // Sort button
                GestureDetector(
                  onTap: _showSortSheet,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: kSurface, borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.sort_rounded, color: kText, size: 18),
                      const SizedBox(width: 6),
                      Text(_sortLabel, style: const TextStyle(color: kText, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 14),

              // Category filter
              SizedBox(
                height: 40,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _categories.length + 1,
                  itemBuilder: (_, i) {
                    if (i == 0) return _FilterChip('All', null, _selectedCat);
                    return _FilterChip(_categories[i-1].name, _categories[i-1].slug, _selectedCat);
                  },
                ),
              ),
            ]),
          ),

          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kPrimary))
                : _gigs.isEmpty
                ? _EmptyState('No services found', 'Try a different category or search term', '🔍')
                : RefreshIndicator(
              color: kPrimary, backgroundColor: kSurface,
              onRefresh: _loadAll,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _gigs.length,
                itemBuilder: (_, i) => GigListTile(_gigs[i]),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _FilterChip(String label, String? value, String? current) {
    final active = value == current;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedCat = value);
        _loadAll();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? kPrimary : kSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? kPrimary : Colors.white.withOpacity(0.1)),
        ),
        child: Text(label, style: TextStyle(
          color: active ? Colors.white : kTextSub,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          fontSize: 13,
        )),
      ),
    );
  }

  String get _sortLabel => switch(_sort) {
    'cern' => '🧠 AI Sort',
    'rating' => '⭐ Rating',
    'price' => '💰 Price',
    'newest' => '🆕 Newest',
    _ => 'Sort',
  };

  void _showSortSheet() {
    showModalBottomSheet(context: context, backgroundColor: kSurface, shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sort By', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kText)),
          const SizedBox(height: 20),
          ...[('cern', '🧠 CERN AI (Recommended)'), ('rating', '⭐ Rating'), ('price', '💰 Price: Low to High'), ('newest', '🆕 Newest First')]
              .map((s) => ListTile(
            title: Text(s.$2, style: TextStyle(color: _sort == s.$1 ? kPrimary : kText, fontWeight: FontWeight.w600)),
            trailing: _sort == s.$1 ? const Icon(Icons.check_rounded, color: kPrimary) : null,
            onTap: () { setState(() => _sort = s.$1); Navigator.pop(context); _loadAll(); },
          )),
        ]),
      ),
    );
  }
}

// ─── GIG DETAIL PAGE ─────────────────────────────────────────────────────────

class GigDetailPage extends StatefulWidget {
  final String gigId;
  const GigDetailPage({super.key, required this.gigId});
  @override
  State<GigDetailPage> createState() => _GigDetailPageState();
}

class _GigDetailPageState extends State<GigDetailPage> {
  Map<String, dynamic>? _gig;
  bool _loading = true;
  int _selectedPricing = 0;
  final _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    _stopwatch.start();
    _load();
  }

  @override
  void dispose() {
    // Record intent on leave
    _stopwatch.stop();
    if (ApiService.isLoggedIn) {
      ApiService.recordView(widget.gigId, _stopwatch.elapsed.inSeconds.toDouble());
    }
    super.dispose();
  }

  Future<void> _load() async {
    final res = await ApiService.getGig(widget.gigId);
    if (!mounted) return;
    setState(() {
      _gig = res['success'] == true ? res['data'] : null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: kPrimary)));
    if (_gig == null) return Scaffold(body: _EmptyState('Gig not found', 'This service may have been removed', '❌'));

    final gig = Gig.fromJson(_gig!);
    final pricing = _gig!['pricing'] as List? ?? [];
    final reviews = _gig!['reviews'] as List? ?? [];
    final provider = _gig!['provider'] as Map<String, dynamic>?;

    return Scaffold(
      body: CustomScrollView(slivers: [
        // Hero image
        SliverAppBar(
          expandedHeight: 280,
          pinned: true,
          backgroundColor: kDark,
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
              child: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white, size: 16),
            ),
          ),
          actions: [
            IconButton(
              onPressed: () {},
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: const Icon(Icons.share_rounded, color: Colors.white, size: 16),
              ),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [kPrimary.withOpacity(0.8), kSecondary.withOpacity(0.6)]),
              ),
              child: const Center(child: Text('🔧', style: TextStyle(fontSize: 80))),
            ),
          ),
        ),

        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Category & competition
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: kPrimary.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                child: Text(gig.category.toUpperCase(), style: const TextStyle(color: kPrimary, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1)),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: gig.competitionColor.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: gig.competitionColor, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(gig.competitionLevel, style: TextStyle(color: gig.competitionColor, fontSize: 11, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),

            Text(gig.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: kText, letterSpacing: -0.5, height: 1.2)),
            const SizedBox(height: 12),

            // Stats row
            Row(children: [
              const Icon(Icons.star_rounded, color: kGold, size: 18),
              const SizedBox(width: 4),
              Text(gig.rating.toStringAsFixed(1), style: const TextStyle(color: kText, fontWeight: FontWeight.w700)),
              const SizedBox(width: 4),
              Text('(${gig.totalReviews} reviews)', style: const TextStyle(color: kTextSub, fontSize: 13)),
              const SizedBox(width: 16),
              const Icon(Icons.bookmark_outline, color: kTextSub, size: 18),
              const SizedBox(width: 4),
              Text('${gig.totalBookings} booked', style: const TextStyle(color: kTextSub, fontSize: 13)),
              const Spacer(),
              if (gig.distanceKm > 0) Row(children: [
                const Icon(Icons.location_on_outlined, color: kTextSub, size: 16),
                Text('${gig.distanceKm.toStringAsFixed(1)} km', style: const TextStyle(color: kTextSub, fontSize: 12)),
              ]),
            ]),
            const SizedBox(height: 20),

            // Description
            const Text('About this Service', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kText)),
            const SizedBox(height: 8),
            Text(gig.description, style: const TextStyle(color: kTextSub, height: 1.7, fontSize: 14)),
            const SizedBox(height: 24),

            // Tags
            if (gig.tags.isNotEmpty) Wrap(spacing: 8, runSpacing: 8, children: gig.tags.map((t) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: kSurface, borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
              ),
              child: Text('#$t', style: const TextStyle(color: kTextSub, fontSize: 12)),
            )).toList()),
            if (gig.tags.isNotEmpty) const SizedBox(height: 24),

            // Provider card
            if (provider != null) _ProviderCard(provider),
            const SizedBox(height: 24),

            // Pricing packages
            const Text('Pricing Packages', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kText)),
            const SizedBox(height: 12),
            ...pricing.asMap().map((i, p) => MapEntry(i, GestureDetector(
              onTap: () => setState(() => _selectedPricing = i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _selectedPricing == i ? kPrimary.withOpacity(0.15) : kCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _selectedPricing == i ? kPrimary : Colors.white.withOpacity(0.08), width: _selectedPricing == i ? 2 : 1),
                ),
                child: Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p['tier']?.toString().toUpperCase() ?? 'BASIC',
                        style: TextStyle(color: _selectedPricing == i ? kPrimary : kText, fontWeight: FontWeight.w800, fontSize: 13, letterSpacing: 1)),
                    const SizedBox(height: 4),
                    Text(p['desc'] ?? '', style: const TextStyle(color: kTextSub, fontSize: 12), maxLines: 2),
                    const SizedBox(height: 4),
                    Text('⏱ ${p['duration_hours'] ?? 1} hours', style: const TextStyle(color: kTextSub, fontSize: 12)),
                  ])),
                  Text('₹${p['price'] ?? 0}', style: TextStyle(
                      color: _selectedPricing == i ? kPrimary : kAccent, fontSize: 22, fontWeight: FontWeight.w900)),
                ]),
              ),
            ))).values.toList(),
            const SizedBox(height: 24),

            // CERN insight
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: kSurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPrimary.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Text('🧠', style: TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('CERN AI Insight', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    gig.chiValue < 1 ? 'Low competition — great time to book!' :
                    gig.chiValue < 3 ? 'Moderate interest — book soon to secure your slot.' :
                    'High demand! Book now or check back later.',
                    style: const TextStyle(color: kTextSub, fontSize: 12, height: 1.4),
                  ),
                ])),
              ]),
            ),
            const SizedBox(height: 24),

            // Reviews section
            if (reviews.isNotEmpty) Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Reviews', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kText)),
              const SizedBox(height: 12),
              ...reviews.take(3).map((r) => _ReviewCard(r)).toList(),
            ]),

            const SizedBox(height: 100), // space for bottom bar
          ]),
        )),
      ]),

      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        decoration: BoxDecoration(
          color: kSurface,
          border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
        ),
        child: Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            const Text('Starting from', style: TextStyle(color: kTextSub, fontSize: 12)),
            Text('₹${pricing.isNotEmpty ? pricing[_selectedPricing]['price'] ?? 0 : 0}',
                style: const TextStyle(color: kText, fontSize: 24, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(width: 20),
          Expanded(
            child: ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(
                  builder: (_) => BookingPage(gig: gig, gigData: _gig!, selectedTier: _selectedPricing))),
              child: const Text('Book Now'),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final Map<String, dynamic> provider;
  const _ProviderCard(this.provider);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => PublicProfilePage(userId: provider['id'] ?? ''))),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(children: [
          CircleAvatar(radius: 28, backgroundColor: kPrimary,
              child: Text((provider['name'] ?? '?')[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700))),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(provider['name'] ?? '', style: const TextStyle(color: kText, fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Row(children: [
              const Icon(Icons.star_rounded, color: kGold, size: 14),
              const SizedBox(width: 4),
              Text('${(provider['rating'] ?? 0.0).toStringAsFixed(1)}', style: const TextStyle(color: kTextSub, fontSize: 13)),
              const SizedBox(width: 12),
              const Icon(Icons.task_alt_rounded, color: kAccent, size: 14),
              const SizedBox(width: 4),
              Text('${provider['jobs_completed'] ?? 0} jobs', style: const TextStyle(color: kTextSub, fontSize: 13)),
            ]),
            if (provider['bio'] != null && (provider['bio'] as String).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(provider['bio'], style: const TextStyle(color: kTextSub, fontSize: 12),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
          ])),
          const Icon(Icons.arrow_forward_ios_rounded, color: kTextSub, size: 14),
        ]),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewCard(this.review);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(radius: 18, backgroundColor: kSurface,
              child: Text((review['reviewer_name'] ?? '?')[0].toUpperCase(),
                  style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w700))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(review['reviewer_name'] ?? '', style: const TextStyle(color: kText, fontWeight: FontWeight.w600, fontSize: 14)),
            Row(children: List.generate(5, (i) => Icon(
              i < (review['rating'] ?? 0) ? Icons.star_rounded : Icons.star_outline_rounded,
              color: kGold, size: 14,
            ))),
          ])),
        ]),
        if ((review['comment'] ?? '').isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(review['comment'], style: const TextStyle(color: kTextSub, fontSize: 13, height: 1.5)),
        ),
      ]),
    );
  }
}

// ─── BOOKING PAGE ────────────────────────────────────────────────────────────

class BookingPage extends StatefulWidget {
  final Gig gig;
  final Map<String, dynamic> gigData;
  final int selectedTier;
  const BookingPage({super.key, required this.gig, required this.gigData, required this.selectedTier});
  @override
  State<BookingPage> createState() => _BookingPageState();
}

class _BookingPageState extends State<BookingPage> {
  final _addressCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  DateTime? _date;
  TimeOfDay? _time;
  bool _loading = false;
  String _paymentMethod = 'cod';

  Future<void> _book() async {
    if (_addressCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter your address'), backgroundColor: kSecondary));
      return;
    }
    setState(() => _loading = true);
    final res = await ApiService.createBooking({
      'gig_id': widget.gig.id,
      'pricing_tier': widget.selectedTier,
      'address': _addressCtrl.text.trim(),
      'notes': _notesCtrl.text.trim(),
      'scheduled_date': _date?.toIso8601String(),
      'scheduled_time': _time != null ? '${_time!.hour}:${_time!.minute.toString().padLeft(2,'0')}' : null,
      'payment_method': _paymentMethod,
    });
    if (!mounted) return;
    setState(() => _loading = false);
    if (res['success'] == true) {
      Navigator.pop(context);
      showDialog(context: context, builder: (_) => _BookingSuccessDialog(widget.gig.title));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? 'Booking failed'), backgroundColor: kSecondary));
    }
  }

  @override
  Widget build(BuildContext context) {
    final pricing = (widget.gigData['pricing'] as List?)?[widget.selectedTier] ?? {};
    return Scaffold(
      appBar: AppBar(title: const Text('Book Service')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Gig summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18)),
            child: Row(children: [
              Container(width: 60, height: 60, decoration: BoxDecoration(
                gradient: LinearGradient(colors: [kPrimary.withOpacity(0.6), kSecondary.withOpacity(0.4)]),
                borderRadius: BorderRadius.circular(14),
              ), child: Center(child: _GigPlaceholder(widget.gig.category))),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.gig.title, style: const TextStyle(color: kText, fontWeight: FontWeight.w700), maxLines: 2),
                const SizedBox(height: 4),
                Text(pricing['tier']?.toString().toUpperCase() ?? 'BASIC', style: const TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
              ])),
              Text('₹${pricing['price'] ?? 0}', style: const TextStyle(color: kAccent, fontSize: 20, fontWeight: FontWeight.w900)),
            ]),
          ),
          const SizedBox(height: 24),

          const Text('📍 Service Address', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kText)),
          const SizedBox(height: 10),
          TextField(controller: _addressCtrl, maxLines: 3, style: const TextStyle(color: kText),
              decoration: const InputDecoration(
                hintText: 'Enter your complete address...',
                prefixIcon: Padding(padding: EdgeInsets.only(bottom: 40), child: Icon(Icons.location_on_outlined)),
              )),
          const SizedBox(height: 20),

          const Text('📅 Schedule (Optional)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kText)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: GestureDetector(
              onTap: () async {
                final d = await showDatePicker(context: context,
                    initialDate: DateTime.now().add(const Duration(days: 1)),
                    firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 60)));
                if (d != null) setState(() => _date = d);
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.1))),
                child: Row(children: [
                  const Icon(Icons.calendar_today_outlined, color: kTextSub, size: 18),
                  const SizedBox(width: 8),
                  Text(_date != null ? '${_date!.day}/${_date!.month}/${_date!.year}' : 'Pick Date',
                      style: TextStyle(color: _date != null ? kText : kTextSub)),
                ]),
              ),
            )),
            const SizedBox(width: 12),
            Expanded(child: GestureDetector(
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                if (t != null) setState(() => _time = t);
              },
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.1))),
                child: Row(children: [
                  const Icon(Icons.access_time_rounded, color: kTextSub, size: 18),
                  const SizedBox(width: 8),
                  Text(_time != null ? _time!.format(context) : 'Pick Time',
                      style: TextStyle(color: _time != null ? kText : kTextSub)),
                ]),
              ),
            )),
          ]),
          const SizedBox(height: 20),

          const Text('📝 Additional Notes', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kText)),
          const SizedBox(height: 10),
          TextField(controller: _notesCtrl, maxLines: 3, style: const TextStyle(color: kText),
              decoration: const InputDecoration(hintText: 'Any special instructions or requirements...')),
          const SizedBox(height: 20),

          const Text('💳 Payment Method', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kText)),
          const SizedBox(height: 10),
          Row(children: [
            _PayOption('Cash on Delivery', 'cod', Icons.payments_outlined),
            const SizedBox(width: 10),
            _PayOption('UPI / Online', 'upi', Icons.phone_android_rounded),
          ]),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _book,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : Text('Confirm Booking • ₹${pricing['price'] ?? 0}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _PayOption(String label, String value, IconData icon) {
    final active = _paymentMethod == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _paymentMethod = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: active ? kPrimary.withOpacity(0.15) : kCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? kPrimary : Colors.white.withOpacity(0.08), width: active ? 2 : 1),
          ),
          child: Column(children: [
            Icon(icon, color: active ? kPrimary : kTextSub),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, style: TextStyle(
                color: active ? kPrimary : kTextSub, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}

class _BookingSuccessDialog extends StatelessWidget {
  final String gigTitle;
  const _BookingSuccessDialog(this.gigTitle);

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: kAccent.withOpacity(0.2), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle_rounded, color: kAccent, size: 48),
          ),
          const SizedBox(height: 20),
          const Text('Booking Confirmed!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kText)),
          const SizedBox(height: 8),
          Text('Your request for "$gigTitle" has been sent. The provider will respond shortly.',
              textAlign: TextAlign.center, style: const TextStyle(color: kTextSub, height: 1.5)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const MainShell(initialIndex: 2)), (_) => false);
            },
            child: const Text('View Bookings'),
          ),
        ]),
      ),
    );
  }
}

// ─── BOOKINGS SCREEN ─────────────────────────────────────────────────────────

class BookingsScreen extends StatefulWidget {
  final String role;
  const BookingsScreen({super.key, required this.role});
  @override
  State<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends State<BookingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<Booking> _bookings = [];
  bool _loading = true;
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
    _tabs.addListener(() => setState(() {}));
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ApiService.getBookings(role: widget.role);
    if (!mounted) return;
    setState(() {
      _bookings = ((res['data'] as List?) ?? []).map((b) => Booking.fromJson(b)).toList();
      _loading = false;
    });
  }

  List<Booking> get _filtered {
    final statuses = [null, 'pending', 'in_progress', 'completed'];
    final s = statuses[_tabs.index];
    if (s == null) return _bookings;
    return _bookings.where((b) => b.status == s || (s == 'in_progress' && b.status == 'accepted')).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Text(widget.role == 'provider' ? 'Job Requests' : 'My Bookings',
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kText, letterSpacing: -1)),
              const Spacer(),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded, color: kTextSub)),
            ]),
          ),
          TabBar(
            controller: _tabs,
            indicatorColor: kPrimary,
            labelColor: kPrimary,
            unselectedLabelColor: kTextSub,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: const [Tab(text: 'All'), Tab(text: 'Pending'), Tab(text: 'Active'), Tab(text: 'Done')],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kPrimary))
                : _filtered.isEmpty
                ? _EmptyState('No bookings', 'Your ${['all', 'pending', 'active', 'completed'][_tabs.index]} bookings will appear here', '📋')
                : RefreshIndicator(
              color: kPrimary, backgroundColor: kSurface,
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _filtered.length,
                itemBuilder: (_, i) => _BookingCard(_filtered[i], widget.role, onRefresh: _load),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final Booking booking;
  final String role;
  final VoidCallback onRefresh;
  const _BookingCard(this.booking, this.role, {required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(booking.gigTitle, style: const TextStyle(color: kText, fontWeight: FontWeight.w700, fontSize: 15), maxLines: 2),
            const SizedBox(height: 4),
            Text(role == 'provider' ? 'From: ${booking.consumerName}' : 'By: ${booking.providerName}',
                style: const TextStyle(color: kTextSub, fontSize: 13)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: booking.statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(booking.statusIcon, color: booking.statusColor, size: 14),
              const SizedBox(width: 6),
              Text(booking.status.toUpperCase(), style: TextStyle(color: booking.statusColor, fontSize: 11, fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        Container(height: 1, color: Colors.white.withOpacity(0.06)),
        const SizedBox(height: 12),
        Row(children: [
          Text('₹${booking.amount.toInt()}', style: const TextStyle(color: kAccent, fontSize: 20, fontWeight: FontWeight.w900)),
          const Spacer(),
          if (role == 'provider' && booking.status == 'pending') Row(children: [
            _ActionBtn('Accept', kAccent, () => _updateStatus(context, 'accepted')),
            const SizedBox(width: 8),
            _ActionBtn('Reject', kSecondary, () => _updateStatus(context, 'rejected')),
          ]) else if (role == 'provider' && booking.status == 'accepted')
            _ActionBtn('Mark In Progress', kPrimary, () => _updateStatus(context, 'in_progress'))
          else if (role == 'provider' && booking.status == 'in_progress')
              _ActionBtn('Mark Complete', kAccent, () => _updateStatus(context, 'completed'))
            else if (role == 'consumer' && booking.status == 'pending')
                _ActionBtn('Cancel', kSecondary, () => _updateStatus(context, 'cancelled')),
        ]),
        if (booking.scheduledDate.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            const Icon(Icons.schedule, color: kTextSub, size: 14),
            const SizedBox(width: 6),
            Text('${booking.scheduledDate} ${booking.scheduledTime}', style: const TextStyle(color: kTextSub, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  Widget _ActionBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Future<void> _updateStatus(BuildContext context, String status) async {
    final res = await ApiService.updateBookingStatus(booking.id, status);
    if (res['success'] == true) onRefresh();
  }
}

// ─── MESSAGES SCREEN ─────────────────────────────────────────────────────────

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<Map<String, dynamic>> _convs = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ApiService.getConversations();
    if (!mounted) return;
    setState(() {
      _convs = ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              const Text('Messages', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kText, letterSpacing: -1)),
              const Spacer(),
              IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded, color: kTextSub)),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kPrimary))
                : _convs.isEmpty
                ? _EmptyState('No conversations', 'Start a chat by booking a service', '💬')
                : RefreshIndicator(
              color: kPrimary, backgroundColor: kSurface,
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _convs.length,
                itemBuilder: (_, i) => _ConvTile(_convs[i]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _ConvTile extends StatelessWidget {
  final Map<String, dynamic> conv;
  const _ConvTile(this.conv);

  @override
  Widget build(BuildContext context) {
    final uid = ApiService.currentUser?['id'] ?? '';
    final participants = (conv['participants'] as List?) ?? [];
    final otherId = participants.firstWhere((p) => p != uid, orElse: () => '');
    final unread = ((conv['unread'] as Map?)?[uid] ?? 0) as int;

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => ChatPage(convId: conv['conv_id'] ?? '', otherName: 'Service Chat'))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Row(children: [
          Stack(children: [
            CircleAvatar(radius: 28, backgroundColor: kPrimary,
                child: const Icon(Icons.person_rounded, color: Colors.white)),
            Positioned(bottom: 0, right: 0, child: Container(
              width: 14, height: 14, decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
            )),
          ]),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Service Chat', style: const TextStyle(color: kText, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(conv['last_message'] ?? '', style: const TextStyle(color: kTextSub, fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ])),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(_formatTime(conv['last_message_at']), style: const TextStyle(color: kTextSub, fontSize: 11)),
            if (unread > 0) Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: kPrimary, borderRadius: BorderRadius.circular(10)),
              child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ]),
        ]),
      ),
    );
  }

  String _formatTime(dynamic t) {
    if (t == null) return '';
    try {
      final dt = DateTime.tryParse(t.toString()) ?? DateTime.now();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m';
      if (diff.inHours < 24) return '${diff.inHours}h';
      return '${diff.inDays}d';
    } catch (_) { return ''; }
  }
}

// ─── CHAT PAGE ───────────────────────────────────────────────────────────────

class ChatPage extends StatefulWidget {
  final String convId, otherName;
  const ChatPage({super.key, required this.convId, required this.otherName});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  List<Map<String, dynamic>> _messages = [];
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _loading = true, _sending = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = await ApiService.getMessages(widget.convId);
    if (!mounted) return;
    setState(() {
      _messages = ((res['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      _loading = false;
    });
    _scrollDown();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    _ctrl.clear();
    setState(() => _sending = true);
    final res = await ApiService.sendMessage(widget.convId, text);
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() { _messages.add(res['data'] as Map<String, dynamic>); });
      _scrollDown();
    }
    setState(() => _sending = false);
  }

  void _scrollDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = ApiService.currentUser?['id'] ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const CircleAvatar(radius: 18, backgroundColor: kPrimary, child: Icon(Icons.person_rounded, color: Colors.white, size: 18)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.otherName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Text('Online', style: TextStyle(fontSize: 12, color: kAccent)),
          ]),
        ]),
      ),
      body: Column(children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: kPrimary))
              : _messages.isEmpty
              ? const Center(child: Text('Start the conversation!', style: TextStyle(color: kTextSub)))
              : ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (_, i) {
              final m = _messages[i];
              final isMe = m['sender_id'] == uid;
              return _Bubble(m['text'] ?? '', isMe, m['sent_at']);
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          decoration: BoxDecoration(
            color: kSurface,
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
          ),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                style: const TextStyle(color: kText),
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _sending ? null : _send,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle),
                child: _sending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text, time;
  final bool isMe;
  const _Bubble(this.text, this.isMe, this.time);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMe ? kPrimary : kCard,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMe ? 20 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 20),
          ),
        ),
        child: Text(text, style: TextStyle(color: isMe ? Colors.white : kText, fontSize: 15)),
      ),
    );
  }
}

// ─── PROFILE SCREEN ──────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _user;
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = await ApiService.getMe();
    if (!mounted) return;
    setState(() {
      _user = res['success'] == true ? res['data'] : null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: kPrimary)));
    final u = _user ?? {};
    final isProvider = u['role'] == 'provider';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          color: kPrimary, backgroundColor: kSurface, onRefresh: _load,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                // Avatar & name
                Center(child: Column(children: [
                  Stack(children: [
                    CircleAvatar(radius: 52, backgroundColor: kPrimary,
                        child: Text(
                            (u['name'] ?? 'U').isNotEmpty ? (u['name'] as String)[0].toUpperCase() : 'U',
                            style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w700))),
                    Positioned(bottom: 0, right: 0, child: GestureDetector(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfilePage(user: u))).then((_) => _load()),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle),
                        child: const Icon(Icons.edit, color: Colors.white, size: 16),
                      ),
                    )),
                  ]),
                  const SizedBox(height: 14),
                  Text(u['name'] ?? '', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: kText)),
                  const SizedBox(height: 4),
                  Text(u['email'] ?? '', style: const TextStyle(color: kTextSub)),
                  const SizedBox(height: 10),
                  if (isProvider) Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _StatBadge('${u['rating'] ?? 0}★', 'Rating', kGold),
                    const SizedBox(width: 16),
                    _StatBadge('${u['jobs_completed'] ?? 0}', 'Jobs Done', kAccent),
                    const SizedBox(width: 16),
                    _StatBadge('₹${((u['total_earnings'] ?? 0) as num).toInt()}', 'Earned', kPrimary),
                  ]),
                ])),
                const SizedBox(height: 28),

                // Provider: quick actions
                if (isProvider) Column(children: [
                  Row(children: [
                    _QuickCard('My Gigs', Icons.work_rounded, kPrimary, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProviderGigsScreen()))),
                    const SizedBox(width: 12),
                    _QuickCard('Create Gig', Icons.add_circle_rounded, kAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGigPage())).then((_) => _load())),
                  ]),
                  const SizedBox(height: 20),
                ]),

                // Menu items
                _MenuSection('Account', [
                  _MenuItem(Icons.person_outlined, 'Edit Profile', () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfilePage(user: u))).then((_) => _load())),
                  if (isProvider) _MenuItem(Icons.work_outlined, 'My Gigs', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProviderGigsScreen()))),
                  _MenuItem(Icons.receipt_long_outlined, 'My Bookings', () => Navigator.push(context, MaterialPageRoute(builder: (_) => BookingsScreen(role: u['role'] ?? 'consumer')))),
                  _MenuItem(Icons.star_outline_rounded, 'My Reviews', () {}),
                ]),
                const SizedBox(height: 16),
                _MenuSection('Settings', [
                  _MenuItem(Icons.notifications_outlined, 'Notifications', () {}),
                  _MenuItem(Icons.privacy_tip_outlined, 'Privacy Policy', () {}),
                  _MenuItem(Icons.help_outline_rounded, 'Help & Support', () {}),
                  _MenuItem(Icons.info_outline_rounded, 'About Skillr', () => _showAbout()),
                ]),
                const SizedBox(height: 16),

                // Logout
                Container(
                  decoration: BoxDecoration(color: kSecondary.withOpacity(0.1), borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kSecondary.withOpacity(0.2))),
                  child: ListTile(
                    leading: const Icon(Icons.logout_rounded, color: kSecondary),
                    title: const Text('Sign Out', style: TextStyle(color: kSecondary, fontWeight: FontWeight.w700)),
                    onTap: () async {
                      await ApiService.logout();
                      if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LandingPage()), (_) => false);
                    },
                  ),
                ),
                const SizedBox(height: 32),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _StatBadge(String val, String label, Color color) {
    return Column(children: [
      Text(val, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w900)),
      Text(label, style: const TextStyle(color: kTextSub, fontSize: 11)),
    ]);
  }

  Widget _QuickCard(String label, IconData icon, Color color, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          ]),
        ),
      ),
    );
  }

  Widget _MenuSection(String title, List<Widget> items) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: kTextSub, letterSpacing: 1)),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.06))),
        child: Column(children: items.asMap().map((i, w) => MapEntry(i, Column(children: [
          w,
          if (i < items.length - 1) Divider(color: Colors.white.withOpacity(0.06), height: 1, indent: 56),
        ]))).values.toList()),
      ),
    ]);
  }

  Widget _MenuItem(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: kTextSub),
      title: Text(label, style: const TextStyle(color: kText, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, color: kTextSub, size: 14),
      onTap: onTap,
    );
  }

  void _showAbout() {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('About Skillr', style: TextStyle(color: kText, fontWeight: FontWeight.w800)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Version 1.0.0', style: TextStyle(color: kTextSub)),
        const SizedBox(height: 10),
        const Text('Powered by CERN AI (Collision-Evasive Regret Network) for intelligent service matching.',
            style: TextStyle(color: kTextSub, height: 1.5)),
        const SizedBox(height: 10),
        const Text('© 2026 Skillr. All rights reserved.', style: TextStyle(color: kTextSub, fontSize: 12)),
      ]),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close', style: TextStyle(color: kPrimary)))],
    ));
  }
}

// ─── EDIT PROFILE ────────────────────────────────────────────────────────────

class EditProfilePage extends StatefulWidget {
  final Map<String, dynamic> user;
  const EditProfilePage({super.key, required this.user});
  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late TextEditingController _nameCtrl, _bioCtrl, _cityCtrl, _phoneCtrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.user['name'] ?? '');
    _bioCtrl = TextEditingController(text: widget.user['bio'] ?? '');
    _cityCtrl = TextEditingController(text: widget.user['city'] ?? '');
    _phoneCtrl = TextEditingController(text: widget.user['phone'] ?? '');
  }

  Future<void> _save() async {
    setState(() => _loading = true);
    await ApiService.updateMe({
      'name': _nameCtrl.text.trim(),
      'bio': _bioCtrl.text.trim(),
      'city': _cityCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
    });
    if (mounted) { setState(() => _loading = false); Navigator.pop(context); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile'), actions: [
        TextButton(onPressed: _loading ? null : _save,
            child: _loading ? const CircularProgressIndicator(color: kPrimary, strokeWidth: 2) : const Text('Save', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w700))),
      ]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Center(child: Stack(children: [
            CircleAvatar(radius: 52, backgroundColor: kPrimary,
                child: Text((_nameCtrl.text.isNotEmpty ? _nameCtrl.text[0] : 'U').toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w700))),
            Positioned(bottom: 0, right: 0, child: Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(color: kCard, shape: BoxShape.circle),
              child: const Icon(Icons.camera_alt_rounded, color: kPrimary, size: 18),
            )),
          ])),
          const SizedBox(height: 32),
          TextField(controller: _nameCtrl, style: const TextStyle(color: kText),
              decoration: const InputDecoration(labelText: 'Full Name', prefixIcon: Icon(Icons.person_outlined))),
          const SizedBox(height: 16),
          TextField(controller: _phoneCtrl, keyboardType: TextInputType.phone, style: const TextStyle(color: kText),
              decoration: const InputDecoration(labelText: 'Phone Number', prefixIcon: Icon(Icons.phone_outlined))),
          const SizedBox(height: 16),
          TextField(controller: _cityCtrl, style: const TextStyle(color: kText),
              decoration: const InputDecoration(labelText: 'City', prefixIcon: Icon(Icons.location_city_outlined))),
          const SizedBox(height: 16),
          TextField(controller: _bioCtrl, maxLines: 4, style: const TextStyle(color: kText),
              decoration: const InputDecoration(labelText: 'Bio / About Me', prefixIcon: Padding(padding: EdgeInsets.only(bottom: 60), child: Icon(Icons.info_outline_rounded)))),
        ]),
      ),
    );
  }
}

// ─── PROVIDER GIGS SCREEN ────────────────────────────────────────────────────

class ProviderGigsScreen extends StatefulWidget {
  const ProviderGigsScreen({super.key});
  @override
  State<ProviderGigsScreen> createState() => _ProviderGigsScreenState();
}

class _ProviderGigsScreenState extends State<ProviderGigsScreen> {
  List<Gig> _gigs = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ApiService.myGigs();
    if (!mounted) return;
    setState(() {
      _gigs = ((res['data'] as List?) ?? []).map((g) => Gig.fromJson(g)).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Gigs'), actions: [
        IconButton(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGigPage())).then((_) => _load()),
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: kPrimary.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.add_rounded, color: kPrimary),
          ),
        ),
      ]),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _gigs.isEmpty
          ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        _EmptyState('No gigs yet', 'Create your first gig to start earning', '🚀'),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateGigPage())).then((_) => _load()),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Create First Gig'),
        ),
      ])
          : RefreshIndicator(
        color: kPrimary, backgroundColor: kSurface, onRefresh: _load,
        child: ListView.builder(
          padding: const EdgeInsets.all(20),
          itemCount: _gigs.length,
          itemBuilder: (_, i) => _ProviderGigTile(_gigs[i], onRefresh: _load),
        ),
      ),
    );
  }
}

class _ProviderGigTile extends StatelessWidget {
  final Gig gig;
  final VoidCallback onRefresh;
  const _ProviderGigTile(this.gig, {required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 52, height: 52, decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: LinearGradient(colors: [kPrimary.withOpacity(0.6), kSecondary.withOpacity(0.4)]),
          ), child: Center(child: _GigPlaceholder(gig.category))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(gig.title, style: const TextStyle(color: kText, fontWeight: FontWeight.w700, fontSize: 15), maxLines: 2),
            const SizedBox(height: 4),
            Text('₹${gig.startingPrice.toInt()} onwards', style: const TextStyle(color: kAccent, fontSize: 13, fontWeight: FontWeight.w600)),
          ])),
          Switch(value: gig.isActive, onChanged: (v) async {
            await ApiService.updateGig(gig.id, {'is_active': v});
            onRefresh();
          }, activeColor: kAccent, inactiveTrackColor: kSurface),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _GigStat(Icons.star_rounded, gig.rating.toStringAsFixed(1), kGold),
          const SizedBox(width: 16),
          _GigStat(Icons.bookmark_outline, '${gig.totalBookings} booked', kPrimary),
          const SizedBox(width: 16),
          _GigStat(Icons.visibility_outlined, '${gig.views} views', kTextSub),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GigDetailPage(gigId: gig.id))),
            icon: const Icon(Icons.open_in_new_rounded, color: kTextSub, size: 18),
          ),
        ]),
      ]),
    );
  }

  Widget _GigStat(IconData icon, String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    ]);
  }
}

// ─── CREATE GIG PAGE ─────────────────────────────────────────────────────────

class CreateGigPage extends StatefulWidget {
  const CreateGigPage({super.key});
  @override
  State<CreateGigPage> createState() => _CreateGigPageState();
}

class _CreateGigPageState extends State<CreateGigPage> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _tagsCtrl = TextEditingController();
  String? _category;
  List<Category> _categories = [];
  List<Map<String, dynamic>> _pricing = [{'tier': 'basic', 'price': 500, 'desc': 'Standard service', 'duration_hours': 2}];
  bool _loading = false;

  @override
  void initState() { super.initState(); _loadCats(); }

  Future<void> _loadCats() async {
    final res = await ApiService.getCategories();
    if (!mounted) return;
    setState(() => _categories = ((res['data'] as List?) ?? []).map((c) => Category.fromJson(c)).toList());
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty || _category == null || _descCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all required fields'), backgroundColor: kSecondary));
      return;
    }
    setState(() => _loading = true);
    final tags = _tagsCtrl.text.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    final res = await ApiService.createGig({
      'title': _titleCtrl.text.trim(),
      'category': _category,
      'description': _descCtrl.text.trim(),
      'city': _cityCtrl.text.trim(),
      'pricing': _pricing,
      'tags': tags,
    });
    if (!mounted) return;
    setState(() => _loading = false);
    if (res['success'] == true) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Gig created successfully!'), backgroundColor: kAccent));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['error'] ?? 'Failed'), backgroundColor: kSecondary));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create New Gig')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Title
          const Text('Gig Title *', style: TextStyle(color: kText, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(controller: _titleCtrl, style: const TextStyle(color: kText),
              decoration: const InputDecoration(hintText: 'e.g. Professional Home Wiring & Installation')),
          const SizedBox(height: 20),

          // Category
          const Text('Category *', style: TextStyle(color: kText, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: kSurface, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: DropdownButton<String>(
              value: _category,
              isExpanded: true,
              dropdownColor: kSurface,
              underline: const SizedBox(),
              hint: const Text('Select category', style: TextStyle(color: kTextSub)),
              items: _categories.map((c) => DropdownMenuItem(
                value: c.slug,
                child: Text('${c.icon} ${c.name}', style: const TextStyle(color: kText)),
              )).toList(),
              onChanged: (v) => setState(() => _category = v),
            ),
          ),
          const SizedBox(height: 20),

          // Description
          const Text('Description *', style: TextStyle(color: kText, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(controller: _descCtrl, maxLines: 5, style: const TextStyle(color: kText),
              decoration: const InputDecoration(hintText: 'Describe your service in detail...')),
          const SizedBox(height: 20),

          // City
          const Text('City / Area', style: TextStyle(color: kText, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(controller: _cityCtrl, style: const TextStyle(color: kText),
              decoration: const InputDecoration(hintText: 'e.g. Dehradun, Delhi...')),
          const SizedBox(height: 20),

          // Tags
          const Text('Tags (comma-separated)', style: TextStyle(color: kText, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          TextField(controller: _tagsCtrl, style: const TextStyle(color: kText),
              decoration: const InputDecoration(hintText: 'e.g. wiring, electrical, repair')),
          const SizedBox(height: 24),

          // Pricing
          Row(children: [
            const Text('Pricing Packages', style: TextStyle(color: kText, fontWeight: FontWeight.w800, fontSize: 16)),
            const Spacer(),
            if (_pricing.length < 3) IconButton(
              onPressed: () => setState(() => _pricing.add({
                'tier': ['standard', 'premium'][_pricing.length - 1],
                'price': 1000, 'desc': 'Premium service', 'duration_hours': 4,
              })),
              icon: const Icon(Icons.add_circle_rounded, color: kAccent),
            ),
          ]),
          const SizedBox(height: 12),
          ..._pricing.asMap().map((i, p) => MapEntry(i, _PricingEditor(
            p, i,
            onUpdate: (updated) => setState(() => _pricing[i] = updated),
            onRemove: _pricing.length > 1 ? () => setState(() => _pricing.removeAt(i)) : null,
          ))).values.toList(),
          const SizedBox(height: 32),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _loading ? null : _submit,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                  : const Text('Publish Gig', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            ),
          ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}

class _PricingEditor extends StatefulWidget {
  final Map<String, dynamic> pricing;
  final int index;
  final Function(Map<String, dynamic>) onUpdate;
  final VoidCallback? onRemove;
  const _PricingEditor(this.pricing, this.index, {required this.onUpdate, this.onRemove});
  @override
  State<_PricingEditor> createState() => _PricingEditorState();
}

class _PricingEditorState extends State<_PricingEditor> {
  late TextEditingController _priceCtrl, _descCtrl;

  @override
  void initState() {
    super.initState();
    _priceCtrl = TextEditingController(text: widget.pricing['price'].toString());
    _descCtrl = TextEditingController(text: widget.pricing['desc'] ?? '');
  }

  void _update() {
    widget.onUpdate({...widget.pricing, 'price': int.tryParse(_priceCtrl.text) ?? 0, 'desc': _descCtrl.text});
  }

  @override
  Widget build(BuildContext context) {
    final tiers = ['Basic', 'Standard', 'Premium'];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: kPrimary.withOpacity(0.2), borderRadius: BorderRadius.circular(10)),
              child: Text(tiers[widget.index].toUpperCase(),
                  style: const TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w800))),
          const Spacer(),
          if (widget.onRemove != null) IconButton(onPressed: widget.onRemove,
              icon: const Icon(Icons.remove_circle_rounded, color: kSecondary, size: 20)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: _priceCtrl, keyboardType: TextInputType.number,
              style: const TextStyle(color: kText),
              decoration: const InputDecoration(labelText: 'Price (₹)', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
              onChanged: (_) => _update())),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: TextField(controller: _descCtrl, style: const TextStyle(color: kText),
              decoration: const InputDecoration(labelText: 'Description', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
              onChanged: (_) => _update())),
        ]),
      ]),
    );
  }
}

// ─── SEARCH PAGE ─────────────────────────────────────────────────────────────

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  List<Gig> _gigs = [];
  bool _loading = false;
  Timer? _debounce;

  void _onChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) { setState(() => _gigs = []); return; }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    final res = await ApiService.search(q);
    if (!mounted) return;
    setState(() {
      _gigs = ((res['data']?['gigs'] as List?) ?? []).map((g) => Gig.fromJson(g)).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl, autofocus: true, style: const TextStyle(color: kText),
          decoration: const InputDecoration(hintText: 'Search services, skills, providers...', border: InputBorder.none, hintStyle: TextStyle(color: kTextSub)),
          onChanged: _onChanged,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _gigs.isEmpty && _ctrl.text.isNotEmpty
          ? _EmptyState('No results', 'Try a different search term', '🔍')
          : _gigs.isEmpty
          ? _buildSuggestions()
          : ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _gigs.length,
        itemBuilder: (_, i) => GigListTile(_gigs[i]),
      ),
    );
  }

  Widget _buildSuggestions() {
    final suggestions = ['Electrician', 'Cook', 'Plumber', 'Mechanic', 'Cleaning', 'Carpenter'];
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Popular Searches', style: TextStyle(color: kTextSub, fontWeight: FontWeight.w700, letterSpacing: 1, fontSize: 12)),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: suggestions.map((s) => GestureDetector(
          onTap: () { _ctrl.text = s; _search(s); },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.1))),
            child: Text(s, style: const TextStyle(color: kText, fontWeight: FontWeight.w500)),
          ),
        )).toList()),
      ]),
    );
  }
}

// ─── PUBLIC PROFILE PAGE ─────────────────────────────────────────────────────

class PublicProfilePage extends StatefulWidget {
  final String userId;
  const PublicProfilePage({super.key, required this.userId});
  @override
  State<PublicProfilePage> createState() => _PublicProfilePageState();
}

class _PublicProfilePageState extends State<PublicProfilePage> {
  Map<String, dynamic>? _user;
  List<Gig> _gigs = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final futures = await Future.wait([
      ApiService.getUser(widget.userId),
      ApiService.getGigs(),
    ]);
    if (!mounted) return;
    setState(() {
      _user = futures[0]['success'] == true ? futures[0]['data'] : null;
      final allGigs = ((futures[1]['data']?['gigs'] as List?) ?? []).map((g) => Gig.fromJson(g)).toList();
      _gigs = allGigs.where((g) => g.id == widget.userId).toList();
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: kPrimary)));
    if (_user == null) return Scaffold(body: _EmptyState('User not found', '', '❌'));
    final u = _user!;

    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 200, pinned: true, backgroundColor: kDark,
          flexibleSpace: FlexibleSpaceBar(
            background: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [kPrimary, kSecondary]),
              ),
              child: Center(child: Text((u['name'] ?? 'U')[0].toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 80, fontWeight: FontWeight.w900))),
            ),
          ),
        ),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(u['name'] ?? '', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: kText)),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.location_on_outlined, color: kTextSub, size: 14),
              Text(u['city'] ?? 'Unknown', style: const TextStyle(color: kTextSub, fontSize: 13)),
              const SizedBox(width: 16),
              const Icon(Icons.star_rounded, color: kGold, size: 14),
              Text('${u['rating'] ?? 0}', style: const TextStyle(color: kText, fontSize: 13, fontWeight: FontWeight.w600)),
            ]),
            if ((u['bio'] ?? '').isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(u['bio'], style: const TextStyle(color: kTextSub, height: 1.6)),
            ),
            const SizedBox(height: 20),
            Row(children: [
              _StatCard('${u['jobs_completed'] ?? 0}', 'Jobs Done'),
              const SizedBox(width: 12),
              _StatCard('${u['total_reviews'] ?? 0}', 'Reviews'),
              const SizedBox(width: 12),
              _StatCard('${u['experience_years'] ?? 0}y', 'Experience'),
            ]),
          ]),
        )),
      ]),
    );
  }

  Widget _StatCard(String val, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          Text(val, style: const TextStyle(color: kPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
          Text(label, style: const TextStyle(color: kTextSub, fontSize: 12)),
        ]),
      ),
    );
  }
}

// ─── NOTIFICATIONS PAGE ──────────────────────────────────────────────────────

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: _EmptyState('All caught up! 🎉', 'No new notifications', '🔔'),
    );
  }
}

// ─── HELPER WIDGETS ──────────────────────────────────────────────────────────

Widget _EmptyState(String title, String subtitle, String emoji) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(emoji, style: const TextStyle(fontSize: 64)),
        const SizedBox(height: 20),
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kText), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(subtitle, style: const TextStyle(color: kTextSub, fontSize: 14), textAlign: TextAlign.center),
      ]),
    ),
  );
}