// lib/services/connectivity_service.dart
import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConnectivityState {
  final bool isOffline;
  final int countdown;
  final bool isChecking;

  const ConnectivityState({
    this.isOffline = false,
    this.countdown = 5,
    this.isChecking = false,
  });

  ConnectivityState copyWith({
    bool? isOffline,
    int? countdown,
    bool? isChecking,
  }) {
    return ConnectivityState(
      isOffline: isOffline ?? this.isOffline,
      countdown: countdown ?? this.countdown,
      isChecking: isChecking ?? this.isChecking,
    );
  }
}

class ConnectivityNotifier extends StateNotifier<ConnectivityState> {
  ConnectivityNotifier() : super(const ConnectivityState()) {
    _init();
  }

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _countdownTimer;
  bool _isDisposed = false;

  void _init() {
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      _onNetworkChanged(results);
    });
    // Initial verification
    checkNow();
  }

  void _onNetworkChanged(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.none) && results.length == 1) {
      // Definitely offline
      _setOffline(true);
    } else {
      // Interface is up, verify actual internet reachability
      checkNow();
    }
  }

  Future<void> checkNow() async {
    if (_isDisposed) return;
    state = state.copyWith(isChecking: true);

    final hasNet = await _verifyReachability();
    if (_isDisposed) return;

    state = state.copyWith(isChecking: false);
    _setOffline(!hasNet);
  }

  void _setOffline(bool offline) {
    if (_isDisposed) return;
    if (offline) {
      if (!state.isOffline) {
        state = state.copyWith(isOffline: true, countdown: 5);
        _startCountdown();
      }
    } else {
      _countdownTimer?.cancel();
      state = state.copyWith(isOffline: false, countdown: 5);
    }
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (_isDisposed) {
        timer.cancel();
        return;
      }
      if (state.countdown <= 1) {
        timer.cancel();
        state = state.copyWith(countdown: 5);
        // Automatically check connectivity
        await checkNow();
        if (state.isOffline) {
          _startCountdown();
        }
      } else {
        state = state.copyWith(countdown: state.countdown - 1);
      }
    });
  }

  Future<bool> _verifyReachability() async {
    try {
      final res1 = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 3));
      if (res1.isNotEmpty && res1[0].rawAddress.isNotEmpty) return true;
    } catch (_) {}

    try {
      final res2 = await InternetAddress.lookup('one.one.one.one')
          .timeout(const Duration(seconds: 3));
      if (res2.isNotEmpty && res2[0].rawAddress.isNotEmpty) return true;
    } catch (_) {}

    return false;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _subscription?.cancel();
    _countdownTimer?.cancel();
    super.dispose();
  }
}

final connectivityProvider =
    StateNotifierProvider<ConnectivityNotifier, ConnectivityState>(
  (ref) => ConnectivityNotifier(),
);
