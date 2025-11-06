import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;
  AppLocalizations(this.locale);

  static const supportedLanguageCodes = ['en', 'fil', 'ceb'];

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ?? AppLocalizations(const Locale('en'));
  }

  static const LocalizationsDelegate<AppLocalizations> delegate = _AppLocalizationsDelegate();

  static const Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'app_title': 'TODA GO',
      'settings_title': 'Settings',
      'language': 'Language',
      'language_desc': 'Choose your preferred language',
      'language_current': 'Current',
      'select_language': 'Select Language',
      'done': 'Done',
      'account': 'Account',
      'profile': 'Profile',
      'profile_desc': 'View and edit your personal information',
      'change_email': 'Change Email',
      'change_password': 'Change Password',
      'notifications_privacy': 'Notifications & Privacy',
      'push_notifications': 'Push Notifications',
      'push_notifications_desc': 'Receive notifications for ride updates',
      'vibration_alerts': 'Vibration Alerts',
      'vibration_alerts_desc': 'Vibrate on important events',
      'location_services': 'Location Services',
      'location_services_desc': 'Allow location access for precise pickup',
      'privacy_policy': 'Privacy Policy',
      'terms_of_service': 'Terms of Service',
      'about': 'About',
      'app_version': 'App Version',
      'contact_support': 'Contact Support',
      'driver_dashboard': 'Driver Dashboard',
      'ride_history': 'Ride History',
      'ratings': 'Ratings',
      'driver_profile': 'Driver Profile',
      'passenger_dashboard': 'Passenger Dashboard',
      'passenger_profile': 'Passenger Profile',
      'map': 'Map',
      'history': 'History',
      'profile_nav': 'Profile',
      'request_nav': 'Request',
      'english': 'English',
      'filipino': 'Filipino',
      'cebuano': 'Cebuano',
    },
    'fil': {
      'app_title': 'TODA GO',
      'settings_title': 'Mga Setting',
      'language': 'Wika',
      'language_desc': 'Piliin ang iyong nais na wika',
      'language_current': 'Kasalukuyan',
      'select_language': 'Pumili ng Wika',
      'done': 'Tapos',
      'account': 'Account',
      'profile': 'Profile',
      'profile_desc': 'Tingnan at i-edit ang iyong personal na impormasyon',
      'change_email': 'Palitan ang Email',
      'change_password': 'Palitan ang Password',
      'notifications_privacy': 'Notipikasyon at Privacy',
      'push_notifications': 'Push Notifications',
      'push_notifications_desc': 'Tumanggap ng notipikasyon para sa updates',
      'vibration_alerts': 'Vibration Alerts',
      'vibration_alerts_desc': 'Mag-vibrate sa mahahalagang pangyayari',
      'location_services': 'Location Services',
      'location_services_desc': 'Payagan ang lokasyon para sa tumpak na pickup',
      'privacy_policy': 'Patakaran sa Privacy',
      'terms_of_service': 'Mga Tuntunin ng Serbisyo',
      'about': 'Tungkol',
      'app_version': 'Bersyon ng App',
      'contact_support': 'Kontakin ang Suporta',
      'driver_dashboard': 'Driver Dashboard',
      'ride_history': 'Kasaysayan ng Biyahe',
      'ratings': 'Ratings',
      'driver_profile': 'Profile ng Driver',
      'passenger_dashboard': 'Passenger Dashboard',
      'passenger_profile': 'Profile ng Pasahero',
      'map': 'Mapa',
      'history': 'Kasaysayan',
      'profile_nav': 'Profile',
      'request_nav': 'Humiling',
      'english': 'Ingles',
      'filipino': 'Filipino',
      'cebuano': 'Cebuano',
    },
    'ceb': {
      'app_title': 'TODA GO',
      'settings_title': 'Mga Setting',
      'language': 'Pinulongan',
      'language_desc': 'Pilia ang imong pinulongan',
      'language_current': 'Karon',
      'select_language': 'Pili ug Pinulongan',
      'done': 'Huma',
      'account': 'Account',
      'profile': 'Profile',
      'profile_desc': 'Tan-awa ug usba ang imong personal nga impormasyon',
      'change_email': 'Usba ang Email',
      'change_password': 'Usba ang Password',
      'notifications_privacy': 'Notipikasyon ug Privacy',
      'push_notifications': 'Push Notifications',
      'push_notifications_desc': 'Dawata ang mga notipikasyon sa mga update',
      'vibration_alerts': 'Vibration Alerts',
      'vibration_alerts_desc': 'Muvibrate sa hinungdanong mga panghitabo',
      'location_services': 'Location Services',
      'location_services_desc': 'Tugoti ang lokasyon para sakto nga pickup',
      'privacy_policy': 'Palisiya sa Privacy',
      'terms_of_service': 'Mga Termino sa Serbisyo',
      'about': 'Mahitungod',
      'app_version': 'Bersyon sa App',
      'contact_support': 'Kontaka ang Suporta',
      'driver_dashboard': 'Driver Dashboard',
      'ride_history': 'Kasaysayan sa Sakay',
      'ratings': 'Ratings',
      'driver_profile': 'Profile sa Driver',
      'passenger_dashboard': 'Passenger Dashboard',
      'passenger_profile': 'Profile sa Pasahero',
      'map': 'Mapa',
      'history': 'Kasaysayan',
      'profile_nav': 'Profile',
      'request_nav': 'Hangyo',
      'driver_app_bar': 'Driver',
      'passenger_app_bar': 'Pasahero',
      'driver_bottom_nav': 'Driver Bottom Nav',
      'passenger_bottom_nav': 'Pasahero Bottom Nav',
      'english': 'Iningles',
      'filipino': 'Filipino',
      'cebuano': 'Cebuano',
    },
  };

  String t(String key) {
    final lang = locale.languageCode;
    return _localizedValues[lang]?[key] ?? _localizedValues['en']?[key] ?? key;
  }
}

class _AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
