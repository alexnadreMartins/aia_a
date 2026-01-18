// File generated manually based on user provided keys
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for android - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for ios - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBXux5MBn3DBA0cu6u_BmnzsCDq5aLIklQ',
    appId: '1:485863355062:web:02eebf350dfb4dfe9e2c17',
    messagingSenderId: '485863355062',
    projectId: 'aiaalbum',
    authDomain: 'aiaalbum.firebaseapp.com',
    storageBucket: 'aiaalbum.firebasestorage.app',
    measurementId: 'G-9X0WCKQZ8B',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyBXux5MBn3DBA0cu6u_BmnzsCDq5aLIklQ',
    appId: '1:485863355062:web:02eebf350dfb4dfe9e2c17',
    messagingSenderId: '485863355062',
    projectId: 'aiaalbum',
    authDomain: 'aiaalbum.firebaseapp.com',
    storageBucket: 'aiaalbum.firebasestorage.app',
    measurementId: 'G-9X0WCKQZ8B',
  );
}
