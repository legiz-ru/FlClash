import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:fl_clash/common/common.dart';

class DeviceInfo {
  final String hwid;
  final String deviceOS;
  final String osVersion;
  final String deviceModel;
  final String userAgent;

  const DeviceInfo({
    required this.hwid,
    required this.deviceOS,
    required this.osVersion,
    required this.deviceModel,
    required this.userAgent,
  });

  Map<String, String> get headers => {
    'x-hwid': hwid,
    'x-device-os': deviceOS,
    'x-ver-os': osVersion,
    'x-device-model': deviceModel,
    'user-agent': userAgent,
  };
}

class HwidService {
  static HwidService? _instance;
  DeviceInfo? _cachedDeviceInfo;
  final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();

  HwidService._internal();

  factory HwidService() {
    _instance ??= HwidService._internal();
    return _instance!;
  }

  Future<DeviceInfo> getDeviceInfo() async {
    if (_cachedDeviceInfo != null) {
      return _cachedDeviceInfo!;
    }

    final hwid = await _generateHwid();
    final deviceOS = _getDeviceOS();
    final osVersion = await _getOSVersion();
    final deviceModel = await _getDeviceModel();
    final userAgent = _generateUserAgent(deviceOS, osVersion, deviceModel);

    _cachedDeviceInfo = DeviceInfo(
      hwid: hwid,
      deviceOS: deviceOS,
      osVersion: osVersion,
      deviceModel: deviceModel,
      userAgent: userAgent,
    );

    return _cachedDeviceInfo!;
  }

  Future<String> _generateHwid() async {
    String identifier = '';

    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfoPlugin.androidInfo;
      // Use Android ID and model as unique identifier
      identifier = '${androidInfo.id}-${androidInfo.model}-${androidInfo.manufacturer}';
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfoPlugin.iosInfo;
      // Use identifierForVendor as unique identifier
      identifier = '${iosInfo.identifierForVendor}-${iosInfo.model}-${iosInfo.name}';
    } else if (Platform.isWindows) {
      final windowsInfo = await _deviceInfoPlugin.windowsInfo;
      // Use computer name and product ID
      identifier = '${windowsInfo.computerName}-${windowsInfo.productId}-${windowsInfo.productName}';
    } else if (Platform.isMacOS) {
      final macOSInfo = await _deviceInfoPlugin.macOSInfo;
      // Use system GUID and model
      identifier = '${macOSInfo.systemGUID}-${macOSInfo.model}-${macOSInfo.computerName}';
    } else if (Platform.isLinux) {
      final linuxInfo = await _deviceInfoPlugin.linuxInfo;
      // Use machine ID and model
      identifier = '${linuxInfo.machineId}-${linuxInfo.prettyName}-${linuxInfo.id}';
    } else {
      // Fallback for other platforms
      identifier = Platform.operatingSystem + Platform.operatingSystemVersion;
    }

    // Hash the identifier for privacy and consistency
    final bytes = utf8.encode(identifier);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  String _getDeviceOS() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    return Platform.operatingSystem;
  }

  Future<String> _getOSVersion() async {
    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfoPlugin.androidInfo;
      return androidInfo.version.release;
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfoPlugin.iosInfo;
      return iosInfo.systemVersion;
    } else if (Platform.isWindows) {
      final windowsInfo = await _deviceInfoPlugin.windowsInfo;
      return '${windowsInfo.majorVersion}.${windowsInfo.minorVersion}.${windowsInfo.buildNumber}';
    } else if (Platform.isMacOS) {
      final macOSInfo = await _deviceInfoPlugin.macOSInfo;
      return '${macOSInfo.majorVersion}.${macOSInfo.minorVersion}.${macOSInfo.patchVersion}';
    } else if (Platform.isLinux) {
      final linuxInfo = await _deviceInfoPlugin.linuxInfo;
      return linuxInfo.version ?? Platform.operatingSystemVersion;
    }
    return Platform.operatingSystemVersion;
  }

  Future<String> _getDeviceModel() async {
    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfoPlugin.androidInfo;
      return '${androidInfo.manufacturer} ${androidInfo.model}';
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfoPlugin.iosInfo;
      return iosInfo.model;
    } else if (Platform.isWindows) {
      final windowsInfo = await _deviceInfoPlugin.windowsInfo;
      return windowsInfo.productName;
    } else if (Platform.isMacOS) {
      final macOSInfo = await _deviceInfoPlugin.macOSInfo;
      return macOSInfo.model;
    } else if (Platform.isLinux) {
      final linuxInfo = await _deviceInfoPlugin.linuxInfo;
      return linuxInfo.prettyName ?? 'Linux Device';
    }
    return 'Unknown Device';
  }

  String _generateUserAgent(String deviceOS, String osVersion, String deviceModel) {
    final packageInfo = globalState.packageInfo;
    return 'FlClash/${packageInfo.version} ($deviceOS $osVersion; $deviceModel)';
  }

  void clearCache() {
    _cachedDeviceInfo = null;
  }
}

final hwidService = HwidService();