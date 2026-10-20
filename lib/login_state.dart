import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LoginState with ChangeNotifier {
  static const String TAG = "LoginGoogleUtils";
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  Future<void>? _googleSignInInit;

  late SharedPreferences _prefs;

  bool _loggedIn = false;
  bool _loading = true;
  late User _user;
  String? _errorMessage;

  LoginState() {
    loginState();
  }

  bool isLoggedIn() {
    return _loggedIn;
  }

  bool isLoading() {
    return _loading;
  }

  String? getErrorMessage() {
    return _errorMessage;
  }

  User currentUser() => _user;

  Future<void> login() async {
    _loading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _handleSignIn();
      await _prefs.setBool('isLoggedIn', true);
      _loggedIn = true;
    } catch (e) {
      _loggedIn = false;
      _errorMessage = e.toString();
      debugPrint('Error en login: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    try {
      await _prefs.clear();
      await (_googleSignInInit ??= _googleSignIn.initialize());
      await _googleSignIn.signOut();
      await _auth.signOut();
      _loggedIn = false;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Error al cerrar sesión: $e';
      debugPrint('Error en logout: $e');
    }
    notifyListeners();
  }

  Future<User> _handleSignIn() async {
    try {
      await (_googleSignInInit ??= _googleSignIn.initialize());
      final GoogleSignInAccount account = await _googleSignIn.authenticate();

      final GoogleSignInAuthentication authentication = account.authentication;
      final OAuthCredential credential =
          GoogleAuthProvider.credential(idToken: authentication.idToken);

      final UserCredential authResult = await _auth.signInWithCredential(credential);
      final User? userpess = authResult.user;
      if (userpess == null) throw Exception('No se pudo obtener el usuario del resultado de autenticación');
      return userpess;
    } on GoogleSignInException catch (e) {
      debugPrint('Error en _handleSignIn: $e');
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw Exception('El inicio de sesión con Google fue cancelado');
      }
      rethrow;
    } catch (e) {
      debugPrint('Error en _handleSignIn: $e');
      rethrow;
    }
  }

  Future<void> loginState() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      if (_prefs.containsKey('isLoggedIn')) {
        final currentUser = _auth.currentUser;
        if (currentUser != null) {
          _user = currentUser;
          _loggedIn = true;
        } else {
          _loggedIn = false;
        }
      } else {
        _loggedIn = false;
      }
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Error al verificar el estado de inicio de sesión: $e';
      debugPrint('Error en loginState: $e');
      _loggedIn = false;
    }
    _loading = false;
    notifyListeners();
  }
}
