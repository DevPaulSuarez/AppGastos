// Datos para conectar la app con el proyecto de Firebase "control-gastos-paul".
// Equivale al archivo que genera `flutterfire configure`.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError('La app no está configurada para la web.');
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'La app solo está configurada para Android y iPhone.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyD266ioLTEJC_KvyjCFHIyLXq0gugQawcE',
    appId: '1:350738405586:android:e4ca3bc8f6aa7210c6b50b',
    messagingSenderId: '350738405586',
    projectId: 'control-gastos-paul',
    storageBucket: 'control-gastos-paul.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyA3SqiyufkWV1vjLzMnNP3FZ0WKWBd2lYA',
    appId: '1:350738405586:ios:b57e86edc8035335c6b50b',
    messagingSenderId: '350738405586',
    projectId: 'control-gastos-paul',
    storageBucket: 'control-gastos-paul.firebasestorage.app',
    iosClientId:
        '350738405586-6oc6348bqn9h0of1ojl9bahpeha3rqjf.apps.googleusercontent.com',
    iosBundleId: 'com.example.primeraAppCurso',
  );

  /// Cliente web de Google: lo pide el inicio de sesión para que Firebase
  /// acepte la cuenta (en Android y en iPhone).
  static const String googleServerClientId =
      '350738405586-c0j9a9umpctbhmbb7u2ef64mth0lfl9e.apps.googleusercontent.com';
}
