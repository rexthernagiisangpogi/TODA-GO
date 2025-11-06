import 'package:flutter/material.dart';
// No imports needed beyond material for this lightweight service

class LocalizationService {
  LocalizationService._internal();
  static final LocalizationService instance = LocalizationService._internal();

  final ValueNotifier<Locale> locale = ValueNotifier<Locale>(const Locale('en'));

  // Broad list for MaterialApp; app strings still fall back to English
  // unless translations are provided in AppLocalizations.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fil'),
    Locale('ceb'),
    Locale('es'), // Spanish
    Locale('fr'), // French
    Locale('de'), // German
    Locale('it'), // Italian
    Locale('pt'), // Portuguese
    Locale('pt', 'BR'), // Brazilian Portuguese
    Locale('ru'), // Russian
    Locale('uk'), // Ukrainian
    Locale('pl'), // Polish
    Locale('nl'), // Dutch
    Locale('sv'), // Swedish
    Locale('no'), // Norwegian
    Locale('da'), // Danish
    Locale('fi'), // Finnish
    Locale('tr'), // Turkish
    Locale('ar'), // Arabic
    Locale('he'), // Hebrew
    Locale('fa'), // Persian
    Locale('hi'), // Hindi
    Locale('id'), // Indonesian
    Locale('ms'), // Malay
    Locale('th'), // Thai
    Locale('vi'), // Vietnamese
    Locale('zh'), // Chinese (generic)
    Locale('zh', 'CN'), // Simplified Chinese
    Locale('zh', 'TW'), // Traditional Chinese
    Locale('ja'), // Japanese
    Locale('ko'), // Korean
  ];

  void setLocaleCode(String code) {
    final loc = _fromCode(code);
    // Always set, even if not in supportedLocales; Material UI falls back,
    // while our strings use the chosen locale with English fallback.
    locale.value = loc;
  }

  Locale _fromCode(String code) {
    // Accept forms like 'en', 'en_US', 'pt-BR'
    final normalized = code.replaceAll('-', '_');
    final parts = normalized.split('_');
    if (parts.isEmpty) return const Locale('en');
    if (parts.length == 1) return Locale(parts[0]);
    return Locale(parts[0], parts[1]);
  }
}
