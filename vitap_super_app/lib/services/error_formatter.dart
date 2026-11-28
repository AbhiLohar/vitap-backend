/// Centralized user-friendly error message formatter.
///
/// Converts raw technical exceptions (SocketException, ClientException,
/// TimeoutException, HTTP status codes, FileSystemException, ArchiveException,
/// Python/VTOP backend exceptions, etc.) into simple, plain-English messages
/// that any non-technical user can immediately understand and act upon.
class ErrorFormatter {
  /// Convert any exception/error into a clear, non-technical user message.
  static String format(dynamic error, {String? fallback}) {
    if (error == null) {
      return fallback ?? 'Something went wrong. Please try again.';
    }

    final original = error.toString().trim();
    final raw = original.toLowerCase();

    // ── Outing / VTOP domain-specific friendly messages ──
    if (raw.contains('already applied') ||
        raw.contains('already booked') ||
        raw.contains('active outing') ||
        raw.contains('pending outing')) {
      return 'You already have an active or pending outing request for this period. Please check Outing History.';
    }
    if (raw.contains('day scholar') || raw.contains('not a hosteller') || raw.contains('only for hosteller')) {
      return 'Outing applications are only available for hostel residents.';
    }
    if (raw.contains('booking closed') || raw.contains('deadline passed') || raw.contains('deadline exceeded') || raw.contains('window closed')) {
      return 'The booking window or deadline for this outing date has already closed.';
    }
    if (raw.contains('rejected by vtop') || raw.contains('could not accept your')) {
      return _stripTechnicalPrefixes(original);
    }

    // ── Invalid credentials / wrong password ──
    if (raw.contains('invalid username') ||
        raw.contains('invalid password') ||
        raw.contains('invalid user') ||
        raw.contains('invalid credential') ||
        raw.contains('incorrect password') ||
        raw.contains('password does not match') ||
        raw.contains('user not found') ||
        raw.contains('user id not available')) {
      return 'Incorrect username or password. Please check your VTOP login details and try again.';
    }

    // ── Account locked / OTP ──
    if (raw.contains('account locked') || raw.contains('maximum fail attempts')) {
      return 'Your VTOP account is temporarily locked due to too many failed attempts. Please reset your password on the VTOP website.';
    }
    if (raw.contains('otp') && (raw.contains('expired') || raw.contains('invalid') || raw.contains('wrong') || raw.contains('incorrect'))) {
      return 'The verification code (OTP) is incorrect or has expired. Please request a new code and try again.';
    }

    // ── Network unreachable / No internet ──
    if (raw.contains('network is unreachable') ||
        raw.contains('errno = 101') ||
        raw.contains('errno = 7') ||
        raw.contains('no address associated') ||
        raw.contains('failed host lookup') ||
        raw.contains('network is slow or unreachable') ||
        raw.contains('unable to reach update servers') ||
        raw.contains('no internet')) {
      return 'No internet connection detected. Please check your Wi-Fi or mobile data and try again.';
    }

    // ── Connection refused / Server down ──
    if (raw.contains('connection refused') ||
        raw.contains('errno = 111') ||
        raw.contains('errno = 61')) {
      return 'Could not connect to the app server. It may be starting up or temporarily down — please try again in a minute.';
    }

    // ── Connection abort / reset / closed ──
    if (raw.contains('connection abort') ||
        raw.contains('connection reset') ||
        raw.contains('connection closed') ||
        raw.contains('software caused connection abort') ||
        raw.contains('clientsoftware caused connection') ||
        raw.contains('clientconnection closed') ||
        raw.contains('download interrupted')) {
      return 'Your internet connection dropped midway. Please ensure a stable connection and try again.';
    }

    // ── Socket / Client exceptions (generic) ──
    if (raw.contains('socketexception') ||
        raw.contains('clientexception') ||
        raw.contains('socket_exception')) {
      return 'Internet connection issue. Please check your network and try again.';
    }

    // ── Timeout / Server sleeping ──
    if (raw.contains('timeoutexception') ||
        raw.contains('timed out') ||
        raw.contains('timeout') ||
        raw.contains('future not completed') ||
        raw.contains('deadline exceeded') ||
        raw.contains('504') ||
        raw.contains('gateway timeout')) {
      return 'The server took too long to respond (VTOP or our server may be busy waking up). Please wait a few seconds and try again.';
    }

    // ── SSL / Certificate errors ──
    if (raw.contains('handshake') ||
        raw.contains('certificate') ||
        raw.contains('ssl') ||
        raw.contains('tls')) {
      return 'Could not establish a secure connection. Please check your device date/time or try another network.';
    }

    // ── Session expired ──
    if (raw.contains('session expired') ||
        raw.contains('session timed out') ||
        raw.contains('not logged in') ||
        raw.contains('401')) {
      return 'Your VTOP session has expired. Please refresh or log out and log in again.';
    }

    // ── File / Menu parsing errors ──
    if (raw.contains('archiveexception') ||
        raw.contains('end of central directory') ||
        raw.contains('unsupported') && raw.contains('xls')) {
      return 'Could not read this file format. If your file is an older .xls or PDF, please save/export it as a modern .xlsx or .csv file and upload again.';
    }
    if (raw.contains('filesystemexception') || raw.contains('permission denied') || raw.contains('cannot open file')) {
      return 'Unable to access the selected file. Please check storage permissions or pick the file again.';
    }

    // ── Update / Installer errors ──
    if (raw.contains('http 404') || (raw.contains('404') && raw.contains('update'))) {
      return 'The update file is not ready on the server yet. Please try again in a few minutes or tap "Download via Browser".';
    }
    if (raw.contains('could not start installer')) {
      return 'Could not open Android app installer. Please allow "Install unknown apps" permission in Settings or download via Browser.';
    }

    // ── Server errors (4xx / 5xx) ──
    if (raw.contains('404') || raw.contains('not found')) {
      return 'The requested service or file was not found on the server. Please try again later.';
    }
    if (raw.contains('403') || raw.contains('forbidden')) {
      return 'Access was denied by the server. Please log out and log in again.';
    }
    if (raw.contains('429') || raw.contains('too many requests')) {
      return 'Too many requests sent in a short time. Please wait a minute and try again.';
    }
    if (raw.contains('502') || raw.contains('bad gateway')) {
      return 'The server is currently restarting or unreachable. Please wait 20–30 seconds and try again.';
    }
    if (raw.contains('503') || raw.contains('service unavailable')) {
      return 'The university portal or app server is temporarily unavailable. Please try again shortly.';
    }
    if (raw.contains('500') || raw.contains('internal server error')) {
      return 'The server ran into an unexpected problem. Please try again in a moment.';
    }

    // ── Format / JSON / Code errors (never expose developer jargon) ──
    if (raw.contains('formatexception') ||
        raw.contains('invalid response') ||
        raw.contains('unexpected character') ||
        raw.contains('rangeerror') ||
        raw.contains('typeerror') ||
        raw.contains('nosuchmethoderror') ||
        raw.contains('null check operator') ||
        raw.contains('stateerror')) {
      return 'We received an unexpected response from the server. Please refresh and try again.';
    }

    // ── Fallback: strip technical prefixes & jargon ──
    String cleaned = _stripTechnicalPrefixes(original);

    // Strip known backend wrapper prefixes like "Failed to apply for weekend outing: "
    cleaned = cleaned.replaceFirst(
      RegExp(
        r'^(?:Failed to (?:apply for (?:general|weekend) outing|fetch|load|parse)[^:]*|Outing error|Weekend outing error|Attendance error|Marks error|Timetable error|Grades error|Profile error|Connection error|Error):\s*',
        caseSensitive: false,
      ),
      '',
    );

    // If after stripping, it still contains another raw technical exception, re-check cleanly
    if (cleaned.isEmpty ||
        cleaned.contains('errno') ||
        cleaned.contains('OS Error') ||
        cleaned.contains('Exception') ||
        cleaned.contains('StackTrace') ||
        cleaned.contains('<!DOCTYPE') ||
        cleaned.contains('<html')) {
      return fallback ?? 'Something unexpected happened. Please check your connection and try again.';
    }

    // Allow meaningful VTOP/server explanations up to 360 chars without truncating
    if (cleaned.length > 360) {
      return '${cleaned.substring(0, 357).trim()}...';
    }

    return cleaned;
  }

  static String _stripTechnicalPrefixes(String input) {
    String cleaned = input.trim();
    cleaned = cleaned.replaceFirst(RegExp(r'^Exception:\s*', caseSensitive: false), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^ClientException with\s*', caseSensitive: false), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^ClientException:\s*', caseSensitive: false), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^SocketException:\s*', caseSensitive: false), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^FileSystemException:\s*', caseSensitive: false), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^Error:\s*', caseSensitive: false), '');
    cleaned = cleaned.replaceAll(RegExp(r',?\s*uri=https?://[^\s,)]+'), '');
    cleaned = cleaned.replaceAll(RegExp(r',?\s*address\s*=\s*[^\s,)]+'), '');
    cleaned = cleaned.replaceAll(RegExp(r',?\s*port\s*=\s*\d+'), '');
    return cleaned.trim();
  }
}
