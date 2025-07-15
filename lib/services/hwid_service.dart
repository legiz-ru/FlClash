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

    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        // Use Android ID or device identifiers
        identifier = androidInfo.id ?? '${androidInfo.model}-${androidInfo.manufacturer}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        // Use identifierForVendor as unique identifier
        identifier = iosInfo.identifierForVendor ?? iosInfo.name ?? 'ios-device';
      } else if (Platform.isWindows) {
        // Use Windows MachineGuid approach similar to machine-uid crate
        identifier = await _getWindowsMachineId();
      } else if (Platform.isMacOS) {
        // Use macOS IOPlatformUUID approach similar to machine-uid crate
        identifier = await _getMacOSMachineId();
      } else if (Platform.isLinux) {
        // Use Linux machine-id approach similar to machine-uid crate
        identifier = await _getLinuxMachineId();
      } else {
        // Fallback for other platforms
        identifier = Platform.operatingSystem + Platform.operatingSystemVersion;
      }
    } catch (e) {
      // Fallback if machine ID generation fails
      identifier = '${Platform.operatingSystem}-${Platform.operatingSystemVersion}-${DateTime.now().millisecondsSinceEpoch}';
    }

    // Hash the identifier for privacy and consistency
    final bytes = utf8.encode(identifier);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<String> _getWindowsMachineId() async {
    try {
      // Try to read MachineGuid from Windows registry
      final result = await Process.run('reg', [
        'query',
        'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Cryptography',
        '/v',
        'MachineGuid'
      ]);
      
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final regex = RegExp(r'MachineGuid\s+REG_SZ\s+([A-F0-9-]+)', caseSensitive: false);
        final match = regex.firstMatch(output);
        if (match != null) {
          return match.group(1) ?? '';
        }
      }
    } catch (e) {
      // Ignore errors and fall back
    }

    // Fallback: use hostname and other identifiers
    try {
      final hostname = await Process.run('hostname', []);
      return hostname.stdout.toString().trim() + Platform.operatingSystemVersion;
    } catch (e) {
      return 'windows-' + Platform.operatingSystemVersion;
    }
  }

  Future<String> _getMacOSMachineId() async {
    try {
      // Try to get hardware UUID using system_profiler
      final result = await Process.run('system_profiler', ['SPHardwareDataType']);
      
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final regex = RegExp(r'Hardware UUID:\s+([A-F0-9-]+)', caseSensitive: false);
        final match = regex.firstMatch(output);
        if (match != null) {
          return match.group(1) ?? '';
        }
      }
    } catch (e) {
      // Ignore errors and fall back
    }

    // Fallback: use ioreg command
    try {
      final result = await Process.run('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice']);
      
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final regex = RegExp(r'"IOPlatformUUID"\s*=\s*"([A-F0-9-]+)"', caseSensitive: false);
        final match = regex.firstMatch(output);
        if (match != null) {
          return match.group(1) ?? '';
        }
      }
    } catch (e) {
      // Ignore errors and fall back
    }

    // Final fallback: use hostname
    try {
      final hostname = await Process.run('hostname', []);
      return hostname.stdout.toString().trim() + Platform.operatingSystemVersion;
    } catch (e) {
      return 'macos-' + Platform.operatingSystemVersion;
    }
  }

  Future<String> _getLinuxMachineId() async {
    // Try to read from /etc/machine-id
    try {
      final file = File('/etc/machine-id');
      if (await file.exists()) {
        final content = await file.readAsString();
        final machineId = content.trim();
        if (machineId.isNotEmpty) {
          return machineId;
        }
      }
    } catch (e) {
      // Ignore errors and try next method
    }

    // Try to read from /var/lib/dbus/machine-id
    try {
      final file = File('/var/lib/dbus/machine-id');
      if (await file.exists()) {
        final content = await file.readAsString();
        final machineId = content.trim();
        if (machineId.isNotEmpty) {
          return machineId;
        }
      }
    } catch (e) {
      // Ignore errors and fall back
    }

    // Fallback: use hostname and other identifiers
    try {
      final hostname = await Process.run('hostname', []);
      return hostname.stdout.toString().trim() + Platform.operatingSystemVersion;
    } catch (e) {
      return 'linux-' + Platform.operatingSystemVersion;
    }
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
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        return androidInfo.version.release ?? 'Unknown';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        return iosInfo.systemVersion ?? 'Unknown';
      } else if (Platform.isWindows) {
        final windowsInfo = await _deviceInfoPlugin.windowsInfo;
        return '${windowsInfo.majorVersion ?? 0}.${windowsInfo.minorVersion ?? 0}.${windowsInfo.buildNumber ?? 0}';
      } else if (Platform.isMacOS) {
        final macOSInfo = await _deviceInfoPlugin.macOSInfo;
        return '${macOSInfo.majorVersion ?? 0}.${macOSInfo.minorVersion ?? 0}.${macOSInfo.patchVersion ?? 0}';
      } else if (Platform.isLinux) {
        final linuxInfo = await _deviceInfoPlugin.linuxInfo;
        return linuxInfo.versionId ?? linuxInfo.version ?? Platform.operatingSystemVersion;
      }
    } catch (e) {
      // Fallback if device info fails
    }
    return Platform.operatingSystemVersion;
  }

  Future<String> _getDeviceModel() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        final manufacturer = androidInfo.manufacturer ?? 'Unknown';
        final model = androidInfo.model ?? 'Unknown';
        return '$manufacturer $model';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        return iosInfo.model ?? 'iOS Device';
      } else if (Platform.isWindows) {
        return 'Windows PC';
      } else if (Platform.isMacOS) {
        final macOSInfo = await _deviceInfoPlugin.macOSInfo;
        return macOSInfo.model ?? 'Mac';
      } else if (Platform.isLinux) {
        final linuxInfo = await _deviceInfoPlugin.linuxInfo;
        return linuxInfo.prettyName ?? linuxInfo.name ?? 'Linux Device';
      }
    } catch (e) {
      // Fallback if device info fails
    }
    return '${Platform.operatingSystem} Device';
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