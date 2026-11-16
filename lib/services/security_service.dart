// lib/services/security_service.dart
import '../core/security_checker.dart';

class SecurityAuditResult {
  final bool isTampered;
  final bool isDebuggerAttached;
  final bool isHooked;
  final bool isRooted;
  final bool signatureValid;
  final String details;

  const SecurityAuditResult({
    this.isTampered = false,
    this.isDebuggerAttached = false,
    this.isHooked = false,
    this.isRooted = false,
    this.signatureValid = true,
    this.details = 'OK',
  });

  bool get isCompromised => isTampered || isDebuggerAttached;
}

class SecurityService {
  static final SecurityService instance = SecurityService._();
  SecurityService._();

  SecurityAuditResult? _lastAudit;
  SecurityAuditResult? get lastAudit => _lastAudit;

  /// Clean, safe environment audit that adheres strictly to Google Play Protect policies
  Future<SecurityAuditResult> runSecurityCheck() async {
    final integrityOk = await SecurityChecker.verifyAppIntegrity();
    final debuggerActive = SecurityChecker.isDebuggerOrHookActive();
    final audit = SecurityAuditResult(
      isTampered: !integrityOk,
      isDebuggerAttached: debuggerActive,
      isHooked: false,
      isRooted: false,
      signatureValid: integrityOk,
      details: integrityOk ? 'OK' : 'Tampered',
    );
    _lastAudit = audit;
    return audit;
  }

  /// Instant termination if tampering or compromised state is detected
  Future<void> terminateApp() async {
    await SecurityChecker.terminateCompromisedApp();
  }
}
