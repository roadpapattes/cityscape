// Migration du jeton : SharedPreferences (clair) -> Keystore (chiffre).
//
// Le risque de cette migration n'est pas la securite, c'est la regression :
// si elle echoue, TOUS les joueurs deja connectes se retrouvent deconnectes
// a la mise a jour. Ces tests verrouillent les trois scenarios qui comptent.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cityscape/services/auth_service.dart';

const _canalSecurise = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Map<String, String> coffre; // faux Keystore, en memoire
  late bool ecritureEnPanne;

  void installerFauxCoffre() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canalSecurise, (call) async {
      final args = (call.arguments as Map?) ?? {};
      final cle = args['key'] as String?;
      switch (call.method) {
        case 'read':
          return coffre[cle];
        case 'write':
          if (ecritureEnPanne) throw PlatformException(code: 'Keystore indisponible');
          coffre[cle!] = args['value'] as String;
          return null;
        case 'delete':
          coffre.remove(cle);
          return null;
        case 'readAll':
          return Map<String, String>.from(coffre);
        default:
          return null;
      }
    });
  }

  setUp(() {
    coffre = {};
    ecritureEnPanne = false;
    installerFauxCoffre();
  });

  test('un joueur deja connecte n\'est pas deconnecte par la mise a jour', () async {
    // Etat d'avant : le jeton vit en clair dans SharedPreferences.
    SharedPreferences.setMockInitialValues({'auth_token': 'jeton-existant'});

    await AuthService.instance.loadFromPrefs();

    expect(AuthService.instance.tokenNotifier.value, 'jeton-existant',
        reason: 'la session doit survivre a la migration');
    expect(coffre['auth_token'], 'jeton-existant',
        reason: 'le jeton doit avoir ete copie dans le stockage securise');

    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('auth_token'), isNull,
        reason: 'la copie en clair doit avoir ete effacee');
  });

  test('si le Keystore refuse d\'ecrire, la session est conservee', () async {
    // Mieux vaut un jeton encore en clair qu'un joueur deconnecte sans raison.
    SharedPreferences.setMockInitialValues({'auth_token': 'jeton-existant'});
    ecritureEnPanne = true;

    await AuthService.instance.loadFromPrefs();

    expect(AuthService.instance.tokenNotifier.value, 'jeton-existant');
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('auth_token'), 'jeton-existant',
        reason: 'ne pas effacer l\'ancien emplacement tant que la copie a echoue');
  });

  test('la deconnexion efface les deux emplacements', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 'ancien-oublie'});
    coffre['auth_token'] = 'jeton-courant';

    await AuthService.instance.logout();

    expect(AuthService.instance.tokenNotifier.value, isNull);
    expect(coffre.containsKey('auth_token'), isFalse);
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('auth_token'), isNull,
        reason: 'un jeton oublie en clair ressusciterait la session');
  });

  test('un nouveau jeton va dans le stockage securise, pas en clair', () async {
    SharedPreferences.setMockInitialValues({});

    await AuthService.instance.saveToken('jeton-neuf');

    expect(coffre['auth_token'], 'jeton-neuf');
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('auth_token'), isNull);
  });
}
