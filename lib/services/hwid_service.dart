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
        // Use basic device identification that's guaranteed to exist
        identifier = '${androidInfo.model}-${androidInfo.manufacturer}-${androidInfo.brand}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        // Use identifierForVendor as unique identifier
        final vendorId = iosInfo.identifierForVendor ?? 'unknown-vendor';
        identifier = '$vendorId-${iosInfo.model}';
      } else if (Platform.isWindows) {
        // Try machine-uid approach first, fallback to device_info_plus
        try {
          identifier = await _getWindowsMachineId();
        } catch (e) {
          final windowsInfo = await _deviceInfoPlugin.windowsInfo;
          identifier = '${windowsInfo.majorVersion}-${windowsInfo.minorVersion}-${windowsInfo.buildNumber}';
        }
      } else if (Platform.isMacOS) {
        // Try machine-uid approach first, fallback to device_info_plus
        try {
          identifier = await _getMacOSMachineId();
        } catch (e) {
          final macOSInfo = await _deviceInfoPlugin.macOSInfo;
          identifier = '${macOSInfo.hostName}-${macOSInfo.majorVersion}-${macOSInfo.minorVersion}';
        }
      } else if (Platform.isLinux) {
        // Try machine-uid approach first, fallback to device_info_plus
        try {
          identifier = await _getLinuxMachineId();
        } catch (e) {
          final linuxInfo = await _deviceInfoPlugin.linuxInfo;
          identifier = '${linuxInfo.name}-${linuxInfo.version ?? 'unknown'}';
        }
      } else {
        // Fallback for other platforms
        identifier = Platform.operatingSystem + Platform.operatingSystemVersion;
      }
    } catch (e) {
      // Fallback if all methods fail
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
        if (match != null && match.group(1) != null) {
          return match.group(1)!;
        }
      }
    } catch (e) {
      // Ignore errors and fall back
    }

    // Fallback: use hostname and other identifiers
    try {
      final hostname = await Process.run('hostname', []);
      if (hostname.exitCode == 0) {
        return hostname.stdout.toString().trim() + Platform.operatingSystemVersion;
      }
    } catch (e) {
      // Ignore errors
    }

    // Final fallback
    throw Exception('Unable to get Windows machine ID');
  }

  Future<String> _getMacOSMachineId() async {
    try {
      // Try to get hardware UUID using system_profiler
      final result = await Process.run('system_profiler', ['SPHardwareDataType']);
      
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final regex = RegExp(r'Hardware UUID:\s+([A-F0-9-]+)', caseSensitive: false);
        final match = regex.firstMatch(output);
        if (match != null && match.group(1) != null) {
          return match.group(1)!;
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
        if (match != null && match.group(1) != null) {
          return match.group(1)!;
        }
      }
    } catch (e) {
      // Ignore errors and fall back
    }

    // Final fallback: use hostname
    try {
      final hostname = await Process.run('hostname', []);
      if (hostname.exitCode == 0) {
        return hostname.stdout.toString().trim() + Platform.operatingSystemVersion;
      }
    } catch (e) {
      // Ignore errors
    }

    // Final fallback
    throw Exception('Unable to get macOS machine ID');
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
      if (hostname.exitCode == 0) {
        return hostname.stdout.toString().trim() + Platform.operatingSystemVersion;
      }
    } catch (e) {
      // Ignore errors
    }

    // Final fallback
    throw Exception('Unable to get Linux machine ID');
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
    } catch (e) {
      // Fallback if device info fails
    }
    return Platform.operatingSystemVersion;
  }

  Future<String> _getDeviceModel() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        return '${androidInfo.manufacturer} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        return iosInfo.model ?? 'iOS Device';
      } else if (Platform.isWindows) {
        final windowsInfo = await _deviceInfoPlugin.windowsInfo;
        return 'Windows ${windowsInfo.majorVersion}.${windowsInfo.minorVersion}';
      } else if (Platform.isMacOS) {
        final macOSInfo = await _deviceInfoPlugin.macOSInfo;
        return macOSInfo.hostName ?? 'Mac Device';
      } else if (Platform.isLinux) {
        final linuxInfo = await _deviceInfoPlugin.linuxInfo;
        return linuxInfo.name ?? 'Linux Device';
      }
    } catch (e) {
      // Fallback if device info fails
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