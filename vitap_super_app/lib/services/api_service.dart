import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../config/api_config.dart';

class ApiService {
  static final String _baseUrl = ApiConfig.baseUrl;
  static final http.Client _client = http.Client();

  /// Callback registered by UI to handle OTP entry when auto-re-login requires it.
  static Future<String?> Function()? onOtpRequired;
  static bool suppressOtpDialog = false;
  static bool _isRelogining = false;

  // ─── Auth ──────────────────────────────────────────────

  /// Single login call — backend auto-solves captcha
  static Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    final res = await _client.post(
      Uri.parse("$_baseUrl/login"),
      body: {"username": username, "password": password},
    ).timeout(const Duration(seconds: 120)); // captcha retries need time
    
    final data = jsonDecode(res.body);
    if (res.statusCode == 200) {
      return data;
    } else {
      // Backend returned an error (401, 500, etc.)
      final detail = data["detail"] ?? "Login failed. Please try again.";
      throw Exception(detail);
    }
  }

  static Future<Map<String, dynamic>> verifyOtp({
    required String username,
    required String otp,
  }) async {
    final res = await _client.post(
      Uri.parse("$_baseUrl/verify-otp"),
      body: {"username": username, "otp": otp},
    ).timeout(const Duration(seconds: 30));
    return jsonDecode(res.body);
  }

  static Future<void> logout(String username) async {
    try {
      await _client.post(
        Uri.parse("$_baseUrl/logout"),
        body: {"username": username},
      ).timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> resendOtp({
    required String username,
  }) async {
    final res = await _client.post(
      Uri.parse("$_baseUrl/resend-otp"),
      body: {"username": username},
    ).timeout(const Duration(seconds: 30));
    return jsonDecode(res.body);
  }

  // ─── Data ──────────────────────────────────────────────

  static Future<List> getSemesters(String username, {bool isRetry = false}) async {
    final res = await _client.get(
      Uri.parse("$_baseUrl/semesters?username=$username"),
    ).timeout(const Duration(seconds: 60));

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data["semesters"] ?? [];
    } else if (res.statusCode == 401 && !isRetry) {
      await _ensureSession();
      return getSemesters(username, isRetry: true);
    } else {
      final error = jsonDecode(res.body);
      throw Exception(error["detail"] ?? "Failed to fetch semesters");
    }
  }



  static Future<bool> _ensureSession() async {
    if (_isRelogining) {
      // Simple wait loop if another request triggered re-login
      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(seconds: 1));
        if (!_isRelogining) return true;
      }
      return false; // Timeout
    }
    
    _isRelogining = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final username = prefs.getString('username');
      const storage = FlutterSecureStorage();
      final password = await storage.read(key: 'password');
      
      if (username != null && password != null) {
        final res = await login(username: username, password: password);
        if (res["status"] == "otp_required") {
          if (suppressOtpDialog) {
            throw Exception("OTP required but suppressed due to active WebView.");
          }
          if (onOtpRequired != null) {
            final otp = await onOtpRequired!();
            if (otp != null && otp.isNotEmpty) {
              final verifyRes = await verifyOtp(username: username, otp: otp);
              if (verifyRes["status"] != "success") {
                throw Exception("OTP Verification failed: ${verifyRes["detail"] ?? verifyRes["status"]}");
              }
            } else {
              throw Exception("OTP was not provided.");
            }
          } else {
            throw Exception("OTP callback is not registered.");
          }
        } else if (res["status"] != "success") {
           throw Exception("Login failed: ${res["detail"] ?? res["status"]}");
        }
        return true;
      }
      return false;
    } catch (e) {
      print("Auto re-login failed: $e");
      return false;
    } finally {
      _isRelogining = false;
    }
  }

  static Future<List> _backgroundRefresh(String url, String cacheKey, bool isSilent, {void Function(List)? onSync, bool isRetry = false}) async {
    try {
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
      if (res.statusCode == 200) {
        try {
          final data = jsonDecode(res.body);
          final list = (data is Map) ? (data.values.first ?? []) : data;
          final prefs = await SharedPreferences.getInstance();
          prefs.setString(cacheKey, jsonEncode(list));
          if (onSync != null) onSync(list);
          return list;
        } on FormatException {
          if (!isSilent) throw Exception("Invalid response from server. Please try again.");
        }
      } else if (res.statusCode == 401 && !isRetry) {
        // Session expired, attempt re-login and retry request once
        final success = await _ensureSession();
        if (success) {
          return _backgroundRefresh(url, cacheKey, isSilent, onSync: onSync, isRetry: true);
        } else {
          if (!isSilent) throw Exception("Session expired. Please log out and log in again.");
          return [];
        }
      } else {
        if (!isSilent) throw Exception("Server returned error ${res.statusCode}: ${res.reasonPhrase}");
      }
    } catch (e) {
      if (!isSilent) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains("socketexception") || errStr.contains("clientexception") || errStr.contains("network is unreachable") || errStr.contains("failed host lookup")) {
           throw Exception("Network is slow or unreachable. Please check your internet connection.");
        }
        if (e is Exception) rethrow;
        throw Exception("Connection error: $e");
      }
      print("Fetch error for $url: $e");
    }
    return [];
  }

  static Future<List> _fetchListWithCache(String url, String cacheKey, bool forceSync, {void Function(List)? onSync}) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check user preference for auto-sync, default to true
    final bool autoSync = prefs.getBool("autoSync") ?? true;

    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try { 
        final list = jsonDecode(cached) as List;
        
        if (forceSync) {
          return await _backgroundRefresh(url, cacheKey, false, onSync: onSync);
        }

        if (autoSync) {
          _backgroundRefresh(url, cacheKey, true, onSync: onSync).catchError((e) { print("Silent sync failed: $e"); return []; });
        }
        return list; 
      } catch (_) {}
    }
    return await _backgroundRefresh(url, cacheKey, false, onSync: onSync);
  }

  static Future<Map<String, dynamic>> _fetchMapWithCache(String url, String cacheKey, bool forceSync, {void Function(Map<String, dynamic>)? onSync}) async {
    final prefs = await SharedPreferences.getInstance();
    
    // Check user preference for auto-sync, default to true
    final bool autoSync = prefs.getBool("autoSync") ?? true;
    
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try { 
        final data = jsonDecode(cached);
        
        if (forceSync) {
          return await _backgroundRefreshMap(url, cacheKey, false, onSync: onSync);
        }

        if (autoSync) {
          _backgroundRefreshMap(url, cacheKey, true, onSync: onSync).catchError((e) { print("Silent sync failed: $e"); return <String, dynamic>{}; });
        }
        return data; 
      } catch (_) {}
    }
    return await _backgroundRefreshMap(url, cacheKey, false, onSync: onSync);
  }

  static Future<Map<String, dynamic>> _backgroundRefreshMap(String url, String cacheKey, bool isSilent, {void Function(Map<String, dynamic>)? onSync, bool isRetry = false}) async {
    try {
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
      if (res.statusCode == 200) {
        try {
          final data = jsonDecode(res.body);
          Map<String, dynamic> map = {};
          
          if (data is Map<String, dynamic>) {
            // FastAPI wraps responses like {"profile": {name: "..."}}
            // We need to unwrap the first value if it's a nested Map
            if (data.keys.length == 1 && data.values.first is Map<String, dynamic>) {
              map = data.values.first as Map<String, dynamic>;
            } else {
              map = data;
            }
          } else if (data is Map) {
             map = Map<String, dynamic>.from(data.values.isNotEmpty ? data.values.first : {});
          }

          final prefs = await SharedPreferences.getInstance();
          prefs.setString(cacheKey, jsonEncode(map));
          if (onSync != null) onSync(map);
          return map;
        } on FormatException {
          if (!isSilent) throw Exception("Invalid response from server.");
        }
      } else if (res.statusCode == 401 && !isRetry) {
        // Session expired, attempt re-login and retry request once
        final success = await _ensureSession();
        if (success) {
          return _backgroundRefreshMap(url, cacheKey, isSilent, onSync: onSync, isRetry: true);
        } else {
          if (!isSilent) throw Exception("Session expired. Please log out and log in again.");
          return {};
        }
      } else {
        if (!isSilent) throw Exception("Server error ${res.statusCode}");
      }
    } catch (e) {
      if (!isSilent) {
        final errStr = e.toString().toLowerCase();
        if (errStr.contains("socketexception") || errStr.contains("clientexception") || errStr.contains("network is unreachable") || errStr.contains("failed host lookup")) {
           throw Exception("Network is slow or unreachable. Please check your internet connection.");
        }
        if (e is Exception) rethrow;
        throw Exception("Connection error: $e");
      }
      print("Fetch error for $url: $e");
    }
    return {};
  }

  static Future<List> getAttendance(String username, {String? semesterId, bool forceSync = false, void Function(List)? onSync}) async {
    String url = "$_baseUrl/attendance?username=$username";
    if (semesterId != null && semesterId.isNotEmpty) url += "&semester_id=$semesterId";
    final cacheKey = 'attendance_${username}_$semesterId';
    final capstoneCacheKey = 'has_capstone_${username}_$semesterId';
    
    final prefs = await SharedPreferences.getInstance();
    final bool autoSync = prefs.getBool("autoSync") ?? true;
    
    // Helper to parse response and extract attendance list + has_capstone flag
    Future<List> fetchAndParse({bool isSilent = false, bool isRetry = false}) async {
      try {
        final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
        if (res.statusCode == 200) {
          try {
            final data = jsonDecode(res.body);
            List list;
            if (data is Map) {
              list = data['attendance'] ?? data.values.firstWhere((v) => v is List, orElse: () => []);
              // Cache has_capstone flag separately
              if (data.containsKey('has_capstone')) {
                prefs.setBool(capstoneCacheKey, data['has_capstone'] == true);
              }
            } else {
              list = data;
            }
            prefs.setString(cacheKey, jsonEncode(list));
            if (onSync != null) onSync(list);
            return list;
          } on FormatException {
            if (!isSilent) throw Exception("Invalid response from server.");
          }
        } else if (res.statusCode == 401 && !isRetry) {
          final success = await _ensureSession();
          if (success) {
            return fetchAndParse(isSilent: isSilent, isRetry: true);
          } else {
            if (!isSilent) throw Exception("Session expired. Please log out and log in again.");
            return [];
          }
        } else {
          if (!isSilent) throw Exception("Server returned error ${res.statusCode}");
        }
      } catch (e) {
        if (!isSilent) {
          final errStr = e.toString().toLowerCase();
          if (errStr.contains("socketexception") || errStr.contains("clientexception") || errStr.contains("network is unreachable") || errStr.contains("failed host lookup")) {
            throw Exception("Network is slow or unreachable. Please check your internet connection.");
          }
          if (e is Exception) rethrow;
          throw Exception("Connection error: $e");
        }
        print("Fetch error for $url: $e");
      }
      return [];
    }
    
    // Check cache
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        final list = jsonDecode(cached) as List;
        if (forceSync) {
          return await fetchAndParse();
        }
        if (autoSync) {
          fetchAndParse(isSilent: true).catchError((e) { print("Silent sync failed: $e"); return <dynamic>[]; });
        }
        return list;
      } catch (_) {}
    }
    return await fetchAndParse();
  }

  /// Check if capstone/SDP attendance is available for the current semester.
  static Future<bool> hasCapstoneAttendance(String username, {String? semesterId}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('has_capstone_${username}_$semesterId') ?? false;
  }

  static Future<Map<String, dynamic>> getCapstoneAttendance(String username, {String? semesterId, bool forceSync = false}) async {
    String url = "$_baseUrl/attendance/capstone?username=$username";
    if (semesterId != null && semesterId.isNotEmpty) url += "&semester_id=${Uri.encodeComponent(semesterId)}";
    final cacheKey = 'capstone_attendance_${username}_$semesterId';

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(cacheKey);

    if (cached != null && !forceSync) {
      try {
        final map = jsonDecode(cached) as Map<String, dynamic>;
        // Fire background sync silently
        _backgroundRefreshMap(url, cacheKey, true).catchError((_) => <String, dynamic>{});
        return map;
      } catch (_) {}
    }

    try {
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 90));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final map = (data is Map && data.containsKey('capstone'))
            ? Map<String, dynamic>.from(data['capstone'])
            : Map<String, dynamic>.from(data);
        prefs.setString(cacheKey, jsonEncode(map));
        return map;
      } else if (res.statusCode == 401) {
        final success = await _ensureSession();
        if (success) {
          final res2 = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 90));
          if (res2.statusCode == 200) {
            final data = jsonDecode(res2.body);
            final map = (data is Map && data.containsKey('capstone'))
                ? Map<String, dynamic>.from(data['capstone'])
                : Map<String, dynamic>.from(data);
            prefs.setString(cacheKey, jsonEncode(map));
            return map;
          }
        }
        throw Exception("Session expired. Please log out and log in again.");
      }
      throw Exception("Failed to fetch capstone attendance");
    } catch (e) {
      if (cached != null) {
        try { return jsonDecode(cached) as Map<String, dynamic>; } catch (_) {}
      }
      rethrow;
    }
  }

  static Future<List> getAttendanceDetail(String username, {
    required String semesterId,
    required String courseId,
    required String courseType,
    bool forceSync = false,
  }) async {
    final url = "$_baseUrl/attendance/detail?username=$username"
        "&semester_id=${Uri.encodeComponent(semesterId)}"
        "&course_id=${Uri.encodeComponent(courseId)}"
        "&course_type=${Uri.encodeComponent(courseType)}";
    final cacheKey = 'att_detail_${username}_${semesterId}_${courseId}_$courseType';

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(cacheKey);

    // Return cached data first if not forced
    if (cached != null && !forceSync) {
      try {
        final list = jsonDecode(cached) as List;
        // Fire background sync silently
        _backgroundRefresh(url, cacheKey, true).catchError((_) => []);
        return list;
      } catch (_) {}
    }

    // No cache or forced — fetch from server
    try {
      final res = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 90));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final list = data["details"] ?? data["attendance_detail"] ?? [];
        prefs.setString(cacheKey, jsonEncode(list));
        return list;
      } else if (res.statusCode == 401) {
        final success = await _ensureSession();
        if (success) {
          final res2 = await _client.get(Uri.parse(url)).timeout(const Duration(seconds: 90));
          if (res2.statusCode == 200) {
            final data = jsonDecode(res2.body);
            final list = data["details"] ?? data["attendance_detail"] ?? [];
            prefs.setString(cacheKey, jsonEncode(list));
            return list;
          }
        }
        throw Exception("Session expired. Please log out and log in again.");
      }
      throw Exception("Failed to fetch attendance detail");
    } catch (e) {
      // If fetch fails but we have cache, return it
      if (cached != null) {
        try { return jsonDecode(cached) as List; } catch (_) {}
      }
      rethrow;
    }
  }

  static Future<List> getTimetable(String username, {String? semesterId, bool forceSync = false, void Function(List)? onSync}) async {
    String url = "$_baseUrl/timetable?username=$username";
    if (semesterId != null && semesterId.isNotEmpty) url += "&semester_id=$semesterId";
    return _fetchListWithCache(url, 'timetable_${username}_$semesterId', forceSync, onSync: onSync);
  }

  static Future<List> getMarks(String username, {String? semesterId, bool forceSync = false, void Function(List)? onSync}) async {
    String url = "$_baseUrl/marks?username=$username";
    if (semesterId != null && semesterId.isNotEmpty) url += "&semester_id=$semesterId";
    return _fetchListWithCache(url, 'marks_${username}_$semesterId', forceSync, onSync: onSync);
  }

  static Future<Map<String, dynamic>> getGrades(String username, {bool forceSync = false, void Function(Map<String, dynamic>)? onSync}) async {
    return _fetchMapWithCache("$_baseUrl/grades?username=$username", 'grades_$username', forceSync, onSync: onSync);
  }

  static Future<List> getExamTypes(String username, {String? semesterId, bool forceSync = false, void Function(List)? onSync}) async {
    String url = "$_baseUrl/exam-types?username=$username";
    if (semesterId != null && semesterId.isNotEmpty) url += "&semester_id=$semesterId";
    return _fetchListWithCache(url, 'examtypes_${username}_$semesterId', forceSync, onSync: onSync);
  }

  static Future<List> getExamSchedule(String username, {String? semesterId, String? examType, bool forceSync = false, void Function(List)? onSync}) async {
    String url = "$_baseUrl/exam-schedule?username=$username";
    if (semesterId != null && semesterId.isNotEmpty) url += "&semester_id=$semesterId";
    if (examType != null && examType.isNotEmpty) url += "&exam_type=$examType";
    return _fetchListWithCache(url, 'examsched_${username}_${semesterId}_$examType', forceSync, onSync: onSync);
  }

  static Future<Map<String, dynamic>> getProfile(String username, {bool forceSync = false, void Function(Map<String, dynamic>)? onSync}) async {
    return _fetchMapWithCache("$_baseUrl/profile?username=$username", 'profile_$username', forceSync, onSync: onSync);
  }

  static Future<Map<String, dynamic>> getCurriculum(String username, {bool forceSync = false, void Function(Map<String, dynamic>)? onSync}) async {
    return _fetchMapWithCache("$_baseUrl/curriculum?username=$username", 'curriculum_$username', forceSync, onSync: onSync);
  }

  static Future<List> getOuting(String username, {bool forceSync = false, void Function(List)? onSync}) async {
    return _fetchListWithCache("$_baseUrl/outing?username=$username", 'outing_$username', forceSync, onSync: onSync);
  }

  static Future<List> getWeekendOuting(String username, {bool forceSync = false, void Function(List)? onSync}) async {
    return _fetchListWithCache("$_baseUrl/outing/weekend?username=$username", 'weekend_outing_$username', forceSync, onSync: onSync);
  }

  static Future<void> clearOutingCache(String username) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('outing_$username');
      await prefs.remove('weekend_outing_$username');
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> applyGeneralOuting({
    required String username,
    required String place,
    required String purpose,
    required String outDate,
    required String outTime,
    required String inDate,
    required String inTime,
  }) async {
    final res = await _client.post(
      Uri.parse("$_baseUrl/outing/apply/general"),
      body: {
        "username": username,
        "place": place,
        "purpose": purpose,
        "outDate": outDate,
        "outTime": outTime,
        "inDate": inDate,
        "inTime": inTime,
      },
    ).timeout(const Duration(seconds: 90));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> applyWeekendOuting({
    required String username,
    required String place,
    required String purpose,
    required String outDate,
    required String outTime,
    required String contact,
  }) async {
    final res = await _client.post(
      Uri.parse("$_baseUrl/outing/apply/weekend"),
      body: {
        "username": username,
        "place": place,
        "purpose": purpose,
        "outDate": outDate,
        "outTime": outTime,
        "contact": contact,
      },
    ).timeout(const Duration(seconds: 90));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> deleteGeneralOuting(String username, String leaveId) async {
    final res = await _client.post(
      Uri.parse("$_baseUrl/outing/delete/general"),
      body: {"username": username, "leaveId": leaveId},
    ).timeout(const Duration(seconds: 30));
    return jsonDecode(res.body);
  }

  static Future<Map<String, dynamic>> deleteWeekendOuting(String username, String bookingId) async {
    final res = await _client.post(
      Uri.parse("$_baseUrl/outing/delete/weekend"),
      body: {"username": username, "bookingId": bookingId},
    ).timeout(const Duration(seconds: 30));
    return jsonDecode(res.body);
  }


  static Future<List> getCourses(String username, {String? semesterId, bool forceSync = false, void Function(List)? onSync}) async {
    String url = "$_baseUrl/courses?username=$username";
    if (semesterId != null && semesterId.isNotEmpty) url += "&semester_id=$semesterId";
    return _fetchListWithCache(url, 'courses_${username}_$semesterId', forceSync, onSync: onSync);
  }

  static Future<List> searchFaculty(String username, String searchTerm) async {
    // Search is dynamic, usually no cache or short cache
    final res = await _client.get(
      Uri.parse("$_baseUrl/faculty?username=$username&search_term=${Uri.encodeComponent(searchTerm)}"),
    ).timeout(const Duration(seconds: 30));
    
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data["faculty"] ?? [];
    } else {
      throw Exception("Failed to search faculty");
    }
  }

  static Future<List> getAllFaculties(String username, {bool forceSync = false}) async {
    return _fetchListWithCache(
      "$_baseUrl/faculty?username=$username&search_term=", 
      'all_faculties_$username', 
      forceSync
    );
  }

  static Future<Map<String, dynamic>> getFacultyDetails(String username, String empId) async {
    final res = await _client.get(
      Uri.parse("$_baseUrl/faculty/details?username=$username&emp_id=${Uri.encodeComponent(empId)}"),
    ).timeout(const Duration(seconds: 30));
    
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      return data["details"] ?? {};
    } else {
      throw Exception("Failed to fetch faculty details");
    }
  }

  static Future<List> getDigitalAssignments(String username, {String? semesterId, bool forceSync = false, void Function(List)? onSync}) async {
    String url = "$_baseUrl/digital-assignments?username=$username";
    if (semesterId != null && semesterId.isNotEmpty) url += "&semester_id=$semesterId";
    return _fetchListWithCache(url, 'da_${username}_$semesterId', forceSync, onSync: onSync);
  }

  static Future<List> getPayments(String username, {bool forceSync = false, void Function(List)? onSync}) async {
    return _fetchListWithCache("$_baseUrl/payments?username=$username", 'payments_$username', forceSync, onSync: onSync);
  }

  static Future<Map<String, dynamic>> getPaymentReceiptDetails(String username, String receiptId) async {
    final response = await _client.get(Uri.parse("$_baseUrl/payments/receipt?username=$username&receipt_id=$receiptId"));
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load payment receipt: ${response.statusCode}\nBody: ${response.body}');
    }
  }


  static Future<Map<String, dynamic>> getCgpa(String username, {bool forceSync = false, void Function(Map<String, dynamic>)? onSync}) async {
    return _fetchMapWithCache("$_baseUrl/cgpa?username=$username", 'cgpa_$username', forceSync, onSync: onSync);
  }

  static Future<Map<String, dynamic>> getMentor(String username, {bool forceSync = false, void Function(Map<String, dynamic>)? onSync}) async {
    return _fetchMapWithCache("$_baseUrl/mentor?username=$username", 'mentor_$username', forceSync, onSync: onSync);
  }

  // ─── Optimization ──────────────────────────────────────

  /// Preload all critical data in parallel
  static Future<void> preloadAllData(String username, {String? semesterId}) async {
    try {
      String? semId = semesterId;
      
      // If no semester provided, get semesters and pick first
      if (semId == null) {
        final semesters = await getSemesters(username);
        if (semesters.isNotEmpty) {
          semId = semesters.first["id"];
          final prefs = await SharedPreferences.getInstance();
          prefs.setString('semesterId', semId!);
          prefs.setString('semesterName', semesters.first["name"]);
        }
      }

      if (semId != null) {
        // Fetch everything else in parallel
        await Future.wait([
          getAttendance(username, semesterId: semId, forceSync: true),
          getTimetable(username, semesterId: semId, forceSync: true),
          getProfile(username, forceSync: true),
          getCurriculum(username, forceSync: true),
          getGrades(username, forceSync: true),
          getOuting(username, forceSync: true),
          getPayments(username, forceSync: true),
        ]);
      }
    } catch (e) {
      print("Preload error: $e");
    }
  }

  // ─── Session ───────────────────────────────────────────

  static Future<bool> checkSession(String username) async {
    try {
      final res = await http
          .get(Uri.parse("$_baseUrl/health"))
          .timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        // Server is up, but we need to check if this user has an active session
        final semRes = await http
            .get(Uri.parse("$_baseUrl/semesters?username=$username"))
            .timeout(const Duration(seconds: 8));
        return semRes.statusCode == 200;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<Map<String, String>> getSessionCookies(String username) async {
    try {
      final res = await http
          .get(Uri.parse("$_baseUrl/session-cookies?username=${Uri.encodeComponent(username)}"))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        try {
          final data = jsonDecode(res.body);
          final cookies = data["cookies"] as Map<String, dynamic>?;
          if (cookies != null) {
            return cookies.map((key, value) => MapEntry(key, value.toString()));
          }
        } catch (_) {}
      }
      return {};
    } catch (_) {
      return {};
    }
  }
}
