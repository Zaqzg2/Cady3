// ignore_for_file: type=lint
//
// إعدادات Firebase لمشروع "كادي" (Firebase project: cady-34220).
//
// ملاحظة: هذا الملف عادة تولّده أداة flutterfire CLI تلقائيًا، لكن هذي
// الأداة تحتاج Flutter/Dart SDK محليًا وهو غير متوفر هنا (التطوير بالكامل
// عبر Termux بدون كمبيوتر). لذلك كُتب يدويًا بنفس بنية الملف المولّد،
// بالقيم الحقيقية من Firebase Console → Project settings → Your apps.
//
// القيم هنا (apiKey وغيرها) ليست سرّية — تُشحن أصلاً داخل تطبيق الويب/
// أندرويد نفسه وأي شخص يقدر يستخرجها من حزمة التطبيق. الحماية الفعلية
// تأتي من قواعد أمان Firestore (Firestore Security Rules) وFirebase
// Authentication، وليس من إخفاء هذه القيم.
//
// عند إضافة منصّة iOS مستقبلًا، أضف حالة FirebaseOptions خاصة بها هنا.

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
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions لم تُهيَّأ لهذه المنصة. '
          'المنصات المدعومة حاليًا: web, android.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDEVvvPPcV-no5h85GB9Pd3gHwnYl8G-ss',
    appId: '1:1074174355064:web:8cb99ed703c021c0b0ef8d',
    messagingSenderId: '1074174355064',
    projectId: 'cady-34220',
    authDomain: 'cady-34220.firebaseapp.com',
    storageBucket: 'cady-34220.firebasestorage.app',
    measurementId: 'G-D3BRT5GMZX',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAywjNm24ZKCx2xY5uJFRSxruMDuJD0wtE',
    appId: '1:1074174355064:android:34556a2ff05ea3b6b0ef8d',
    messagingSenderId: '1074174355064',
    projectId: 'cady-34220',
    storageBucket: 'cady-34220.firebasestorage.app',
  );
}
