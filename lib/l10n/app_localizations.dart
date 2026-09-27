import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'strings_common.dart';
import 'strings_boppeslach.dart';
import 'strings_buterbreaengrienetsiis.dart';
import 'strings_fjouweropinrige.dart';
import 'strings_skaken.dart';
import 'strings_damjen.dart';
import 'strings_suderseeslach.dart';
import 'strings_puntenenfakjes.dart';
import 'strings_unthaldspultsje.dart';
import 'strings_ludo.dart';
import 'strings_kruske.dart';
import 'strings_rupsen.dart';
import 'strings_rekkenje.dart';
import 'strings_paddelduel.dart';
import 'strings_kleurecho.dart';
import 'strings_sudokuduel.dart';
import 'strings_wurdspul.dart';
import 'strings_skofpuzzel.dart';
import 'strings_slange.dart';
import 'strings_tekenjeenriede.dart';
import 'strings_aaisykje.dart';
import 'strings_domino.dart';
import 'strings_wabistdo.dart';
import 'strings_klaverjassen.dart';
import 'strings_wurdsikerij.dart';
import 'strings_patience.dart';
import 'strings_lofthockey.dart';
import 'strings_ienentritich.dart';
import 'strings_tikrazernij.dart';
import 'strings_fluchtekenje.dart';

export 'strings_common.dart';
export 'strings_boppeslach.dart';
export 'strings_buterbreaengrienetsiis.dart';
export 'strings_fjouweropinrige.dart';
export 'strings_skaken.dart';
export 'strings_damjen.dart';
export 'strings_suderseeslach.dart';
export 'strings_puntenenfakjes.dart';
export 'strings_unthaldspultsje.dart';
export 'strings_ludo.dart';
export 'strings_kruske.dart';
export 'strings_rupsen.dart';
export 'strings_rekkenje.dart';
export 'strings_paddelduel.dart';
export 'strings_kleurecho.dart';
export 'strings_sudokuduel.dart';
export 'strings_wurdspul.dart';
export 'strings_skofpuzzel.dart';
export 'strings_slange.dart';
export 'strings_tekenjeenriede.dart';
export 'strings_aaisykje.dart';
export 'strings_domino.dart';
export 'strings_wabistdo.dart';
export 'strings_klaverjassen.dart';
export 'strings_wurdsikerij.dart';
export 'strings_patience.dart';
export 'strings_lofthockey.dart';
export 'strings_ienentritich.dart';
export 'strings_tikrazernij.dart';
export 'strings_fluchtekenje.dart';

// ── Language enum ─────────────────────────────────────────────────────────────

enum AppLang { fy, nl, en }

extension AppLangExt on AppLang {
  String get label => switch (this) {
    AppLang.fy => 'FY',
    AppLang.nl => 'NL',
    AppLang.en => 'EN',
  };
  String get fullName => switch (this) {
    AppLang.fy => 'Frysk',
    AppLang.nl => 'Nederlands',
    AppLang.en => 'English',
  };
}

// ── String template helper ────────────────────────────────────────────────────
// Usage: '{player} wins!'.fmt({'player': 'Alice'}) → 'Alice wins!'
extension StringFmt on String {
  String fmt(Map<String, dynamic> args) {
    var s = this;
    args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
    return s;
  }
}

// ── Central singleton ─────────────────────────────────────────────────────────

class AppLocalizations {
  AppLocalizations._();
  static final AppLocalizations _instance = AppLocalizations._();
  factory AppLocalizations() => _instance;

  AppLang _lang = AppLang.en;
  AppLang get lang => _lang;

  late StringsCommon      common;
  late StringsBoppeslach        boppeslach;
  late StringsButerBreaEnGrieneTsiis   buterbreaengrienetsiis;
  late StringsFjouwerOpInRige  fjouweropinrige;
  late StringsSkaken       skaken;
  late StringsDamjen    damjen;
  late StringsSuderseeslach  suderseeslach;
  late StringsPuntenEnFakjes puntenenfakjes;
  late StringsUnthaldspultsje      unthaldspultsje;
  late StringsLudo        ludo;
  late StringsKruske      kruske;
  late StringsRupsen      rupsen;
  late StringsRekkenje   rekkenje;
  late StringsPaddelduel        paddelduel;
  late StringsKleurEcho       kleurecho;
  late StringsSudokuDuel      sudokuduel;
  late StringsWurdspul   wurdspul;
  late StringsSkofpuzzel skofpuzzel;
  late StringsSlange       slange;
  late StringsTekenjeEnRiede  tekenjeenriede;
  late StringsAaisykje    aaisykje;
  late StringsDomino     domino;
  late StringsWaBistDo    wabistdo;
  late StringsKlaverjassen klaverjassen;
  late StringsWurdsikerij wurdsikerij;
  late StringsPatience patience;
  late StringsLofthockey lofthockey;
  late StringsIenEnTritich ienentritich;
  late StringsTikRazernij tikrazernij;
  late StringsFluchTekenje fluchtekenje;

  /// Load a language and persist the choice. Call setState() after this.
  Future<void> load(AppLang lang) async {
    _lang = lang;
    _apply(lang);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_lang', lang.name);
  }

  /// Load synchronously from saved prefs (call at startup after prefs is ready).
  void loadSync(String? saved) {
    _lang = AppLang.values.firstWhere(
      (l) => l.name == saved, orElse: () => AppLang.en);
    _apply(_lang);
  }

  void _apply(AppLang l) {
    common       = StringsCommon.of(l);
    boppeslach         = StringsBoppeslach.of(l);
    buterbreaengrienetsiis    = StringsButerBreaEnGrieneTsiis.of(l);
    fjouweropinrige   = StringsFjouwerOpInRige.of(l);
    skaken        = StringsSkaken.of(l);
    damjen     = StringsDamjen.of(l);
    suderseeslach   = StringsSuderseeslach.of(l);
    puntenenfakjes = StringsPuntenEnFakjes.of(l);
    unthaldspultsje       = StringsUnthaldspultsje.of(l);
    ludo         = StringsLudo.of(l);
    kruske       = StringsKruske.of(l);
    rupsen       = StringsRupsen.of(l);
    rekkenje    = StringsRekkenje.of(l);
    paddelduel         = StringsPaddelduel.of(l);
    kleurecho        = StringsKleurEcho.of(l);
    sudokuduel       = StringsSudokuDuel.of(l);
    wurdspul    = StringsWurdspul.of(l);
    skofpuzzel = StringsSkofpuzzel.of(l);
    slange        = StringsSlange.of(l);
    tekenjeenriede   = StringsTekenjeEnRiede.of(l);
    aaisykje     = StringsAaisykje.of(l);
    domino      = StringsDomino.of(l);
    wabistdo     = StringsWaBistDo.of(l);
    klaverjassen = StringsKlaverjassen.of(l);
    wurdsikerij   = StringsWurdsikerij.of(l);
    patience    = StringsPatience.of(l);
    lofthockey    = StringsLofthockey.of(l);
    ienentritich  = StringsIenEnTritich.of(l);
    tikrazernij    = StringsTikRazernij.of(l);
    fluchtekenje    = StringsFluchTekenje.of(l);
  }

  /// Initialise at app startup: reads prefs synchronously via a pre-loaded instance.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    var saved = prefs.getString('app_lang');
    // Browser guests (Hosted mode): no saved choice yet → follow the browser
    // language (Frisian / Dutch, otherwise English)
    if (saved == null && kIsWeb) {
      final code = PlatformDispatcher.instance.locale.languageCode;
      if (code == 'fy' || code == 'nl') saved = code;
    }
    _instance.loadSync(saved);
  }
}

// Convenience top-level getter — use L.common.startGame, L.boppeslach.rollBtn, etc.
AppLocalizations get L => AppLocalizations();
