import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class LanguageSelectionScreen extends StatefulWidget {
  final String currentCode;
  const LanguageSelectionScreen({super.key, required this.currentCode});

  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  late String _selected;

  static const List<MapEntry<String, String>> _languages = [
    MapEntry('en', 'English'),
    MapEntry('fil', 'Filipino'),
    MapEntry('ceb', 'Cebuano'),
    MapEntry('es', 'Español'),
    MapEntry('fr', 'Français'),
    MapEntry('de', 'Deutsch'),
    MapEntry('it', 'Italiano'),
    MapEntry('pt', 'Português'),
    MapEntry('pt-BR', 'Português (Brasil)'),
    MapEntry('ru', 'Русский'),
    MapEntry('uk', 'Українська'),
    MapEntry('pl', 'Polski'),
    MapEntry('nl', 'Nederlands'),
    MapEntry('sv', 'Svenska'),
    MapEntry('no', 'Norsk'),
    MapEntry('da', 'Dansk'),
    MapEntry('fi', 'Suomi'),
    MapEntry('tr', 'Türkçe'),
    MapEntry('ar', 'العربية'),
    MapEntry('he', 'עברית'),
    MapEntry('fa', 'فارسی'),
    MapEntry('hi', 'हिन्दी'),
    MapEntry('id', 'Bahasa Indonesia'),
    MapEntry('ms', 'Bahasa Melayu'),
    MapEntry('th', 'ไทย'),
    MapEntry('vi', 'Tiếng Việt'),
    MapEntry('zh', '中文'),
    MapEntry('zh-CN', '简体中文 (中国)'),
    MapEntry('zh-TW', '繁體中文 (台灣)'),
    MapEntry('ja', '日本語'),
    MapEntry('ko', '한국어'),
  ];

  @override
  void initState() {
    super.initState();
    _selected = widget.currentCode;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.t('select_language')),
        backgroundColor: const Color(0xFF082FBD),
        foregroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_selected),
            child: Text(l.t('done'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemBuilder: (context, index) {
          final e = _languages[index];
          return RadioListTile<String>(
            value: e.key,
            groupValue: _selected,
            onChanged: (v) {
              if (v == null) return;
              setState(() => _selected = v);
            },
            title: Text(e.value),
            secondary: const Icon(Icons.language, color: Color(0xFF082FBD)),
          );
        },
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemCount: _languages.length,
      ),
    );
  }
}
