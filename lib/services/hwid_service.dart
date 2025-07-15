import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/foundation.dart';

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
    final userAgent = await _generateUserAgent(deviceOS, osVersion, deviceModel);

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
        // Use device identification that's guaranteed to exist
        identifier = '${androidInfo.model}-${androidInfo.manufacturer ?? 'unknown'}-${androidInfo.brand ?? 'unknown'}';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        // Use identifierForVendor as unique identifier - this is the proper way for iOS
        final vendorId = iosInfo.identifierForVendor ?? 'unknown-vendor';
        identifier = '$vendorId-${iosInfo.model ?? 'iPhone'}';
      } else if (Platform.isWindows) {
        // Try machine-uid approach first, fallback to device info
        identifier = await _getWindowsMachineId();
      } else if (Platform.isMacOS) {
        // Try machine-uid approach first, fallback to device info
        identifier = await _getMacOSMachineId();
      } else if (Platform.isLinux) {
        // Try machine-uid approach first, fallback to device info
        identifier = await _getLinuxMachineId();
      } else {
        // Fallback for other platforms
        identifier = '${Platform.operatingSystem}-${Platform.operatingSystemVersion}';
      }
    } catch (e) {
      // Comprehensive fallback if device info fails
      identifier = '${Platform.operatingSystem}-${Platform.operatingSystemVersion}-fallback';
      debugPrint('HWID generation failed, using fallback: $e');
    }

    // Ensure we have some identifier
    if (identifier.isEmpty) {
      identifier = 'unknown-device-fallback';
    }

    // Hash the identifier for privacy and consistency
    final bytes = utf8.encode(identifier);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<String> _getWindowsMachineId() async {
    try {
      // Try to get Windows MachineGuid from registry
      final result = await Process.run('reg', [
        'query',
        r'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography',
        '/v',
        'MachineGuid'
      ]);
      
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final guidMatch = RegExp(r'MachineGuid\s+REG_SZ\s+([A-F0-9-]+)', caseSensitive: false)
            .firstMatch(output);
        if (guidMatch != null) {
          return 'windows-${guidMatch.group(1)}';
        }
      }
    } catch (e) {
      debugPrint('Failed to get Windows MachineGuid: $e');
    }
    
    // Fallback to device info
    try {
      final windowsInfo = await _deviceInfoPlugin.windowsInfo;
      return 'windows-${windowsInfo.computerName ?? 'unknown'}-${windowsInfo.buildNumber ?? 'unknown'}';
    } catch (e) {
      return 'windows-fallback-${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  Future<String> _getMacOSMachineId() async {
    try {
      // Try to get macOS hardware UUID
      final result = await Process.run('system_profiler', ['SPHardwareDataType']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final uuidMatch = RegExp(r'Hardware UUID:\s*([A-F0-9-]+)', caseSensitive: false)
            .firstMatch(output);
        if (uuidMatch != null) {
          return 'macos-${uuidMatch.group(1)}';
        }
      }
    } catch (e) {
      debugPrint('Failed to get macOS Hardware UUID: $e');
    }

    // Try alternative method with ioreg
    try {
      final result = await Process.run('ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final uuidMatch = RegExp(r'"IOPlatformUUID"\s*=\s*"([A-F0-9-]+)"', caseSensitive: false)
            .firstMatch(output);
        if (uuidMatch != null) {
          return 'macos-${uuidMatch.group(1)}';
        }
      }
    } catch (e) {
      debugPrint('Failed to get macOS IOPlatformUUID: $e');
    }
    
    // Fallback to device info
    try {
      final macOSInfo = await _deviceInfoPlugin.macOSInfo;
      return 'macos-${macOSInfo.hostName ?? 'unknown'}-${macOSInfo.majorVersion ?? 0}-${macOSInfo.minorVersion ?? 0}';
    } catch (e) {
      return 'macos-fallback-${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  Future<String> _getLinuxMachineId() async {
    // Try to read machine-id file
    try {
      final machineIdFile = File('/etc/machine-id');
      if (await machineIdFile.exists()) {
        final machineId = await machineIdFile.readAsString();
        return 'linux-${machineId.trim()}';
      }
    } catch (e) {
      debugPrint('Failed to read /etc/machine-id: $e');
    }

    // Try alternative location
    try {
      final machineIdFile = File('/var/lib/dbus/machine-id');
      if (await machineIdFile.exists()) {
        final machineId = await machineIdFile.readAsString();
        return 'linux-${machineId.trim()}';
      }
    } catch (e) {
      debugPrint('Failed to read /var/lib/dbus/machine-id: $e');
    }
    
    // Fallback to device info
    try {
      final linuxInfo = await _deviceInfoPlugin.linuxInfo;
      return 'linux-${linuxInfo.name ?? 'unknown'}-${linuxInfo.version ?? 'unknown'}';
    } catch (e) {
      return 'linux-fallback-${DateTime.now().millisecondsSinceEpoch}';
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
        final major = windowsInfo.majorVersion ?? 0;
        final minor = windowsInfo.minorVersion ?? 0;
        final build = windowsInfo.buildNumber ?? 0;
        return '$major.$minor.$build';
      } else if (Platform.isMacOS) {
        final macOSInfo = await _deviceInfoPlugin.macOSInfo;
        final major = macOSInfo.majorVersion ?? 0;
        final minor = macOSInfo.minorVersion ?? 0;
        final patch = macOSInfo.patchVersion ?? 0;
        return '$major.$minor.$patch';
      } else if (Platform.isLinux) {
        // For Linux, use Platform version as primary since linuxInfo.version can be problematic
        return Platform.operatingSystemVersion;
      }
    } catch (e) {
      // Fallback if device info fails - this is expected and not an error
      debugPrint('Failed to get OS version: $e');
    }
    return Platform.operatingSystemVersion;
  }

  Future<String> _getDeviceModel() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        final manufacturer = androidInfo.manufacturer ?? 'Unknown';
        final model = androidInfo.model ?? 'Android Device';
        return '$manufacturer $model';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        return iosInfo.model ?? 'iOS Device';
      } else if (Platform.isWindows) {
        final windowsInfo = await _deviceInfoPlugin.windowsInfo;
        final computerName = windowsInfo.computerName ?? 'Windows PC';
        final major = windowsInfo.majorVersion ?? 0;
        final minor = windowsInfo.minorVersion ?? 0;
        return '$computerName (Windows $major.$minor)';
      } else if (Platform.isMacOS) {
        final macOSInfo = await _deviceInfoPlugin.macOSInfo;
        final hostName = macOSInfo.hostName ?? 'Mac';
        final model = macOSInfo.model ?? 'macOS Device';
        return '$hostName ($model)';
      } else if (Platform.isLinux) {
        final linuxInfo = await _deviceInfoPlugin.linuxInfo;
        final name = linuxInfo.name ?? 'Linux';
        return '$name Device';
      }
    } catch (e) {
      // Fallback if device info fails - this is expected and not an error
      debugPrint('Failed to get device model: $e');
    }
    return '${Platform.operatingSystem} Device';
  }

  Future<String> _generateUserAgent(String deviceOS, String osVersion, String deviceModel) async {
    final packageInfo = await PackageInfo.fromPlatform();
    return 'FlClash/${packageInfo.version} ($deviceOS $osVersion; $deviceModel)';
  }

  void clearCache() {
    _cachedDeviceInfo = null;
  }
}

final hwidService = HwidService();