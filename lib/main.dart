// SPDX-FileCopyrightText: 2022 Foundation Devices Inc.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:envoy/business/updates_manager.dart';
import 'package:envoy/business/account_manager.dart';
import 'package:envoy/ui/envoy_colors.dart';
import 'package:envoy/ui/home/home_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_neumorphic/flutter_neumorphic.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:envoy/firebase_options.dart';
import 'package:envoy/business/messaging.dart';
import 'package:envoy/business/local_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:envoy/business/settings.dart';
import 'package:tor/tor.dart';
import 'package:envoy/business/notifications.dart';
import 'business/fees.dart';
import 'business/scv_server.dart';
import 'business/video_manager.dart';

Messaging? messaging;

Future<void> main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // TODO: find an appropriate screen to ask for permission on iOS
    messaging = Messaging();
    await messaging!.requestPermission();
  } catch (e) {
    print('Failed to initialize Firebase');
  }

  await initSingletons();

  runApp(MyApp());
}

Future<void> initSingletons() async {
  await LocalStorage.init();

  Settings.restore();
  Tor.init();
  UpdatesManager.init();
  ScvServer.init();

  if (Settings().usingTor) {
    Tor().enable();
  } else {
    Tor().disable();
  }

  Fees.restore();
  AccountManager.init();
  Notifications.init();
  VideoManager.init();
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // Portrait mode only outside of video player
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitDown,
      DeviceOrientation.portraitUp,
    ]);

    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
        systemStatusBarContrastEnforced: true,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.dark));

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge,
        overlays: [SystemUiOverlay.top]);

    final envoyAccentColor = EnvoyColors.darkTeal;
    final envoyVariantColor = EnvoyColors.darkCopper;
    final envoyBaseColor = Colors.transparent;
    final envoyTextTheme =
        GoogleFonts.montserratTextTheme(Theme.of(context).textTheme);

    return NeumorphicApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: [
          Locale('en', ''),
          Locale('es', ''),
        ],
        debugShowCheckedModeBanner: false,
        title: 'Envoy',
        themeMode: ThemeMode.light,
        materialTheme: ThemeData(
          pageTransitionsTheme: PageTransitionsTheme(builders: {
            TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.iOS: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
            TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          }),
          primaryColor: envoyAccentColor,
          brightness: Brightness.light,
          textTheme: envoyTextTheme,
          scaffoldBackgroundColor: envoyBaseColor,
        ),
        theme: NeumorphicThemeData(
          textTheme: envoyTextTheme,
          baseColor: envoyBaseColor,
          accentColor: envoyAccentColor,
          variantColor: envoyVariantColor,
          depth: 0, // Flat for now
        ),
        initialRoute: "/",
        routes: {
          '/': (context) => HomePage(),
        });
  }
}