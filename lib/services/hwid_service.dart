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
        identifier = await _getAndroidHwid();
      } else if (Platform.isIOS) {
        identifier = await _getIOSHwid();
      } else if (Platform.isWindows) {
        identifier = await _getWindowsHwid();
      } else if (Platform.isMacOS) {
        identifier = await _getMacOSHwid();
      } else if (Platform.isLinux) {
        identifier = await _getLinuxHwid();
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

  Future<String> _getAndroidHwid() async {
    final androidInfo = await _deviceInfoPlugin.androidInfo;
    // Use multiple Android identifiers for better uniqueness
    final identifiers = [
      androidInfo.id,
      androidInfo.model,
      androidInfo.manufacturer,
      androidInfo.brand,
    ];
    return 'android-${identifiers.where((id) => id.isNotEmpty).join('-')}';
  }

  Future<String> _getIOSHwid() async {
    final iosInfo = await _deviceInfoPlugin.iosInfo;
    // Use iOS identifierForVendor which is unique per app installation
    return 'ios-${iosInfo.identifierForVendor ?? iosInfo.model}';
  }

  Future<String> _getWindowsHwid() async {
    // Try to get Windows MachineGuid first (machine-uid approach)
    try {
      final result = await Process.run(
        'reg',
        ['query', 'HKEY_LOCAL_MACHINE\\SOFTWARE\\Microsoft\\Cryptography', '/v', 'MachineGuid'],
        runInShell: true,
      );
      
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final lines = output.split('\n');
        for (final line in lines) {
          if (line.contains('MachineGuid')) {
            final parts = line.trim().split(RegExp(r'\s+'));
            if (parts.length >= 3) {
              final guid = parts.last.trim();
              if (guid.isNotEmpty && guid != 'MachineGuid') {
                return 'windows-$guid';
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to get Windows MachineGuid: $e');
    }

    // Fallback to device info
    try {
      final windowsInfo = await _deviceInfoPlugin.windowsInfo;
      final identifiers = [
        windowsInfo.computerName,
        windowsInfo.buildNumber.toString(),
        windowsInfo.majorVersion.toString(),
        windowsInfo.minorVersion.toString(),
      ];
      return 'windows-${identifiers.where((id) => id.isNotEmpty).join('-')}';
    } catch (e) {
      debugPrint('Failed to get Windows device info: $e');
      return 'windows-${Platform.operatingSystemVersion}';
    }
  }

  Future<String> _getMacOSHwid() async {
    // Try to get macOS IOPlatformUUID first (machine-uid approach)
    try {
      var result = await Process.run('system_profiler', ['SPHardwareDataType']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final uuidMatch = RegExp(r'Hardware UUID:\s*(.+)').firstMatch(output);
        if (uuidMatch != null) {
          final uuid = uuidMatch.group(1)?.trim();
          if (uuid != null && uuid.isNotEmpty) {
            return 'macos-$uuid';
          }
        }
      }

      // Try alternative method with ioreg
      result = await Process.run('ioreg', ['-d2', '-c', 'IOPlatformExpertDevice']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final uuidMatch = RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"').firstMatch(output);
        if (uuidMatch != null) {
          final uuid = uuidMatch.group(1)?.trim();
          if (uuid != null && uuid.isNotEmpty) {
            return 'macos-$uuid';
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to get macOS IOPlatformUUID: $e');
    }

    // Fallback to device info
    try {
      final macOSInfo = await _deviceInfoPlugin.macOSInfo;
      final identifiers = [
        macOSInfo.computerName,
        macOSInfo.hostName,
        macOSInfo.majorVersion.toString(),
        macOSInfo.minorVersion.toString(),
      ];
      return 'macos-${identifiers.where((id) => id.isNotEmpty).join('-')}';
    } catch (e) {
      debugPrint('Failed to get macOS device info: $e');
      return 'macos-${Platform.operatingSystemVersion}';
    }
  }

  Future<String> _getLinuxHwid() async {
    // Try to read Linux machine-id (machine-uid approach)
    final machineIdPaths = ['/etc/machine-id', '/var/lib/dbus/machine-id'];
    
    for (final path in machineIdPaths) {
      try {
        final file = File(path);
        if (await file.exists()) {
          final machineId = await file.readAsString();
          final cleanId = machineId.trim();
          if (cleanId.isNotEmpty) {
            return 'linux-$cleanId';
          }
        }
      } catch (e) {
        debugPrint('Failed to read $path: $e');
      }
    }

    // Fallback to device info
    try {
      final linuxInfo = await _deviceInfoPlugin.linuxInfo;
      final identifiers = [
        linuxInfo.machineId ?? '',
        linuxInfo.name,
        linuxInfo.version ?? '',
      ];
      return 'linux-${identifiers.where((id) => id.isNotEmpty).join('-')}';
    } catch (e) {
      debugPrint('Failed to get Linux device info: $e');
      return 'linux-${Platform.operatingSystemVersion}';
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
        return androidInfo.version.release;
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        return iosInfo.systemVersion;
      } else if (Platform.isWindows) {
        final windowsInfo = await _deviceInfoPlugin.windowsInfo;
        return '${windowsInfo.majorVersion}.${windowsInfo.minorVersion}';
      } else if (Platform.isMacOS) {
        final macOSInfo = await _deviceInfoPlugin.macOSInfo;
        return '${macOSInfo.majorVersion}.${macOSInfo.minorVersion}';
      } else if (Platform.isLinux) {
        final linuxInfo = await _deviceInfoPlugin.linuxInfo;
        return linuxInfo.version ?? Platform.operatingSystemVersion;
      }
    } catch (e) {
      // Fallback if device info fails - this is expected and not an error
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
        return iosInfo.model;
      } else if (Platform.isWindows) {
        final windowsInfo = await _deviceInfoPlugin.windowsInfo;
        final computerName = windowsInfo.computerName;
        if (computerName.isNotEmpty) {
          return 'Windows PC ($computerName)';
        }
        return 'Windows PC';
      } else if (Platform.isMacOS) {
        final macOSInfo = await _deviceInfoPlugin.macOSInfo;
        final model = macOSInfo.model;
        if (model.isNotEmpty) {
          return model;
        }
        return 'Mac';
      } else if (Platform.isLinux) {
        final linuxInfo = await _deviceInfoPlugin.linuxInfo;
        final name = linuxInfo.name;
        if (name.isNotEmpty) {
          return 'Linux ($name)';
        }
        return 'Linux PC';
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