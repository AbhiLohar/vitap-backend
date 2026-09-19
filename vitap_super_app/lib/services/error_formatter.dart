/// Centralized user-friendly error message formatter.
///
/// Converts raw technical exceptions (SocketException, ClientException,
/// TimeoutException, etc.) into simple, human-readable messages that
/// non-technical users can understand.
class ErrorFormatter {
  /// Convert any exception/error into a user-friendly message.
  static String format(dynamic error) {
    final raw = error.toString().toLowerCase();

    // ── Invalid credentials / wrong password ──
    if (raw.contains('invalid username') ||
        raw.contains('invalid password') ||
        raw.contains('invalid user') ||
        raw.contains('invalid credential') ||
        raw.contains('incorrect password') ||
        raw.contains('password does not match') ||
        raw.contains('user not found') ||
        raw.contains('user id not available')) {
      return 'Invalid Username or Password. Please check your credentials and try again.';
    }

    // ── Account locked ──
    if (raw.contains('account locked') || raw.contains('maximum fail attempts')) {
      return 'Account locked due to maximum failed attempts. Please reset your password on VTOP.';
    }

    // ── Network unreachable / No internet ──
    if (raw.contains('network is unreachable') ||
        raw.contains('errno = 101') ||
        raw.contains('errno = 7') ||
        raw.contains('no address associated') ||
        raw.contains('failed host lookup') ||
        raw.contains('no internet')) {
      return 'No internet connection. Please check your Wi-Fi or mobile data and try again.';
    }

    // ── Connection refused / Server down ──
    if (raw.contains('connection refused') ||
        raw.contains('errno = 111') ||
        raw.contains('errno = 61')) {
      return 'Unable to reach the server. It may be temporarily down. Please try again in a few minutes.';
    }

    // ── Connection abort / reset ──
    if (raw.contains('connection abort') ||
        raw.contains('connection reset') ||
        raw.contains('connection closed') ||
        raw.contains('software caused connection abort') ||
        raw.contains('clientsoftware caused connection')) {
      return 'Connection was interrupted. Please check your internet and try again.';
    }

    // ── Socket / Client exceptions (generic) ──
    if (raw.contains('socketexception') ||
        raw.contains('clientexception') ||
        raw.contains('socket_exception')) {
      return 'Network error. Please check your internet connection and try again.';
    }

    // ── Timeout ──
    if (raw.contains('timeoutexception') ||
        raw.contains('timed out') ||
        raw.contains('future not completed') ||
        raw.contains('deadline exceeded')) {
      return 'Request timed out. The server is taking too long to respond. Please try again.';
    }

    // ── SSL / Certificate errors ──
    if (raw.contains('handshake') ||
        raw.contains('certificate') ||
        raw.contains('ssl') ||
        raw.contains('tls')) {
      return 'Secure connection failed. Please check your network or try again later.';
    }

    // ── Session expired ──
    if (raw.contains('session expired') ||
        raw.contains('session timed out') ||
        raw.contains('not logged in') ||
        raw.contains('401')) {
      return 'Your session has expired. Please log out and log in again.';
    }

    // ── Server errors (5xx) ──
    if (raw.contains('500') || raw.contains('internal server error')) {
      return 'Something went wrong on the server. Please try again later.';
    }
    if (raw.contains('502') || raw.contains('bad gateway')) {
      return 'Server is temporarily unavailable. Please try again in a few minutes.';
    }
    if (raw.contains('503') || raw.contains('service unavailable')) {
      return 'Server is under maintenance. Please try again later.';
    }

    // ── Format / Parse errors ──
    if (raw.contains('formatexception') || raw.contains('invalid response')) {
      return 'Received an unexpected response from the server. Please try again.';
    }

    // ── Fallback: strip "Exception: " prefix and return cleaned message ──
    String cleaned = error.toString();
    cleaned = cleaned.replaceFirst(RegExp(r'^Exception:\s*'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^ClientException with\s*'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^ClientException:\s*'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^SocketException:\s*'), '');

    // Remove URIs from error messages — users don't need to see URLs
    cleaned = cleaned.replaceAll(
      RegExp(r',?\s*uri=https?://[^\s,)]+'), '');
    cleaned = cleaned.replaceAll(
      RegExp(r',?\s*address\s*=\s*[^\s,)]+'), '');
    cleaned = cleaned.replaceAll(
      RegExp(r',?\s*port\s*=\s*\d+'), '');

    // If cleaned message is still very technical or too long, use a generic message
    if (cleaned.length > 120 || cleaned.contains('errno') || cleaned.contains('OS Error')) {
      return 'Something went wrong. Please check your internet connection and try again.';
    }

    return cleaned.trim().isEmpty
        ? 'Something went wrong. Please try again.'
        : cleaned.trim();
  }
}
