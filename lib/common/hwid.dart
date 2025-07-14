import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:fl_clash/state.dart';

class Hwid {
  static Hwid? _instance;
  late String _hwid;
  late String _deviceOs;
  late String _osVersion;
  late String _deviceModel;

  Hwid._internal();

  factory Hwid() {
    _instance ??= Hwid._internal();
    return _instance!;
  }

  Future<void> initialize() async {
    final deviceInfo = DeviceInfoPlugin();
    
    if (Platform.isAndroid) {
      final androidInfo = await deviceInfo.androidInfo;
      _hwid = _generateHwid(androidInfo.id);
      _deviceOs = 'Android';
      _osVersion = '${androidInfo.version.release} (API ${androidInfo.version.sdkInt})';
      _deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfo.iosInfo;
      _hwid = _generateHwid(iosInfo.identifierForVendor ?? 'unknown');
      _deviceOs = 'iOS';
      _osVersion = '${iosInfo.systemName} ${iosInfo.systemVersion}';
      _deviceModel = iosInfo.model;
    } else if (Platform.isWindows) {
      final windowsInfo = await deviceInfo.windowsInfo;
      _hwid = _generateHwid(windowsInfo.machineId);
      _deviceOs = 'Windows';
      _osVersion = '${windowsInfo.majorVersion}.${windowsInfo.minorVersion}.${windowsInfo.buildNumber}';
      _deviceModel = windowsInfo.computerName;
    } else if (Platform.isMacOS) {
      final macOsInfo = await deviceInfo.macOsInfo;
      _hwid = _generateHwid(macOsInfo.systemGUID ?? 'unknown');
      _deviceOs = 'macOS';
      _osVersion = '${macOsInfo.majorVersion}.${macOsInfo.minorVersion}.${macOsInfo.patchVersion}';
      _deviceModel = macOsInfo.model;
    } else if (Platform.isLinux) {
      final linuxInfo = await deviceInfo.linuxInfo;
      _hwid = _generateHwid(linuxInfo.machineId ?? 'unknown');
      _deviceOs = 'Linux';
      _osVersion = '${linuxInfo.name} ${linuxInfo.version ?? ''}';
      _deviceModel = linuxInfo.prettyName ?? 'Unknown';
    } else {
      _hwid = _generateHwid('unknown');
      _deviceOs = Platform.operatingSystem;
      _osVersion = Platform.operatingSystemVersion;
      _deviceModel = 'Unknown';
    }
  }

  String _generateHwid(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 16).toUpperCase();
  }

  String get hwid => _hwid;
  String get deviceOs => _deviceOs;
  String get osVersion => _osVersion;
  String get deviceModel => _deviceModel;

  String get userAgent {
    return 'FlClash/${_getAppVersion()} ($_deviceOs $_osVersion; $_deviceModel)';
  }

  String _getAppVersion() {
    try {
      return globalState.packageInfo.version;
    } catch (e) {
      return '1.0.0';
    }
  }
}

final hwid = Hwid();