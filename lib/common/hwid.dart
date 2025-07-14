import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:platform_device_id/platform_device_id.dart';
import 'package:fl_clash/state.dart';

class DeviceInfo {
  final String hwid;
  final String? deviceOS;
  final String? osVersion;
  final String? deviceModel;
  final String userAgent;

  const DeviceInfo({
    required this.hwid,
    this.deviceOS,
    this.osVersion,
    this.deviceModel,
    required this.userAgent,
  });

  Map<String, String> toHeaders() {
    final headers = <String, String>{
      'x-hwid': hwid,
      'user-agent': userAgent,
    };
    
    if (deviceOS != null) {
      headers['x-device-os'] = deviceOS!;
    }
    
    if (osVersion != null) {
      headers['x-ver-os'] = osVersion!;
    }
    
    if (deviceModel != null) {
      headers['x-device-model'] = deviceModel!;
    }
    
    return headers;
  }
}

class HwidManager {
  static HwidManager? _instance;
  DeviceInfo? _cachedDeviceInfo;

  HwidManager._internal();

  factory HwidManager() {
    _instance ??= HwidManager._internal();
    return _instance!;
  }

  Future<DeviceInfo> getDeviceInfo() async {
    if (_cachedDeviceInfo != null) {
      return _cachedDeviceInfo!;
    }

    final deviceInfoPlugin = DeviceInfoPlugin();
    String hwid;
    String? deviceOS;
    String? osVersion;
    String? deviceModel;

    if (Platform.isAndroid) {
      final androidInfo = await deviceInfoPlugin.androidInfo;
      // Try to get device ID, fallback to fingerprint-based generation
      hwid = await _getAndroidHwid(androidInfo);
      deviceOS = 'Android';
      osVersion = androidInfo.version.release;
      deviceModel = '${androidInfo.manufacturer} ${androidInfo.model}';
    } else if (Platform.isIOS) {
      final iosInfo = await deviceInfoPlugin.iosInfo;
      // Use identifierForVendor as HWID for iOS
      hwid = iosInfo.identifierForVendor ?? await _generateFallbackHwid();
      deviceOS = 'iOS';
      osVersion = iosInfo.systemVersion;
      deviceModel = iosInfo.model;
    } else if (Platform.isWindows) {
      final windowsInfo = await deviceInfoPlugin.windowsInfo;
      hwid = await _getWindowsHwid();
      deviceOS = 'Windows';
      osVersion = '${windowsInfo.majorVersion}.${windowsInfo.minorVersion}.${windowsInfo.buildNumber}';
      deviceModel = windowsInfo.computerName;
    } else if (Platform.isMacOS) {
      final macOSInfo = await deviceInfoPlugin.macOSInfo;
      hwid = await _getMacOSHwid();
      deviceOS = 'macOS';
      osVersion = macOSInfo.osRelease;
      deviceModel = macOSInfo.model;
    } else if (Platform.isLinux) {
      final linuxInfo = await deviceInfoPlugin.linuxInfo;
      hwid = await _getLinuxHwid();
      deviceOS = 'Linux';
      osVersion = linuxInfo.versionId ?? 'Unknown';
      deviceModel = linuxInfo.prettyName ?? 'Linux PC';
    } else {
      hwid = await _generateFallbackHwid();
      deviceOS = Platform.operatingSystem;
      osVersion = Platform.operatingSystemVersion;
      deviceModel = 'Unknown';
    }

    final userAgent = 'FlClash/${globalState.packageInfo.version}';

    _cachedDeviceInfo = DeviceInfo(
      hwid: hwid,
      deviceOS: deviceOS,
      osVersion: osVersion,
      deviceModel: deviceModel,
      userAgent: userAgent,
    );

    return _cachedDeviceInfo!;
  }

  Future<String> _getAndroidHwid(AndroidDeviceInfo androidInfo) async {
    // Try to get device ID from platform_device_id package
    try {
      final deviceId = await PlatformDeviceId.getDeviceId;
      if (deviceId != null && deviceId.isNotEmpty) {
        return deviceId;
      }
    } catch (e) {
      // Fall back to fingerprint-based generation if package fails
    }

    // Generate HWID based on device fingerprint (similar to machine-uid logic)
    final fingerprint = [
      androidInfo.fingerprint,
      androidInfo.id,
      androidInfo.brand,
      androidInfo.model,
      androidInfo.device,
    ].where((element) => element.isNotEmpty).join('|');

    return _generateHashFromString(fingerprint);
  }

  Future<String> _getWindowsHwid() async {
    try {
      // Try to get Windows machine GUID from registry or WMI
      final result = await Process.run('wmic', ['csproduct', 'get', 'UUID', '/value']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final uuidMatch = RegExp(r'UUID=([^\r\n]+)').firstMatch(output);
        if (uuidMatch != null && uuidMatch.group(1)!.isNotEmpty) {
          return uuidMatch.group(1)!.trim();
        }
      }
    } catch (e) {
      // Fall back to motherboard serial
    }

    try {
      final result = await Process.run('wmic', ['baseboard', 'get', 'serialnumber', '/value']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final serialMatch = RegExp(r'SerialNumber=([^\r\n]+)').firstMatch(output);
        if (serialMatch != null && serialMatch.group(1)!.isNotEmpty) {
          return _generateHashFromString(serialMatch.group(1)!.trim());
        }
      }
    } catch (e) {
      // Final fallback
    }

    return await _generateFallbackHwid();
  }

  Future<String> _getMacOSHwid() async {
    try {
      // Use system_profiler to get hardware UUID
      final result = await Process.run('system_profiler', ['SPHardwareDataType']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final uuidMatch = RegExp(r'Hardware UUID:\s*([A-F0-9\-]+)', caseSensitive: false).firstMatch(output);
        if (uuidMatch != null && uuidMatch.group(1)!.isNotEmpty) {
          return uuidMatch.group(1)!.trim();
        }
      }
    } catch (e) {
      // Fall back to IOPlatformUUID
    }

    try {
      final result = await Process.run('ioreg', ['-d2', '-c', 'IOPlatformExpertDevice']);
      if (result.exitCode == 0) {
        final output = result.stdout.toString();
        final uuidMatch = RegExp(r'"IOPlatformUUID"\s*=\s*"([^"]+)"').firstMatch(output);
        if (uuidMatch != null && uuidMatch.group(1)!.isNotEmpty) {
          return uuidMatch.group(1)!.trim();
        }
      }
    } catch (e) {
      // Final fallback
    }

    return await _generateFallbackHwid();
  }

  Future<String> _getLinuxHwid() async {
    try {
      // Try to read machine-id
      final machineIdFile = File('/etc/machine-id');
      if (await machineIdFile.exists()) {
        final content = await machineIdFile.readAsString();
        if (content.trim().isNotEmpty) {
          return content.trim();
        }
      }
    } catch (e) {
      // Try alternative location
    }

    try {
      final machineIdFile = File('/var/lib/dbus/machine-id');
      if (await machineIdFile.exists()) {
        final content = await machineIdFile.readAsString();
        if (content.trim().isNotEmpty) {
          return content.trim();
        }
      }
    } catch (e) {
      // Try DMI product UUID
    }

    try {
      final dmiFile = File('/sys/class/dmi/id/product_uuid');
      if (await dmiFile.exists()) {
        final content = await dmiFile.readAsString();
        if (content.trim().isNotEmpty) {
          return content.trim();
        }
      }
    } catch (e) {
      // Final fallback
    }

    return await _generateFallbackHwid();
  }

  Future<String> _generateFallbackHwid() async {
    // Generate a consistent HWID based on available system information
    final fallbackData = [
      Platform.operatingSystem,
      Platform.operatingSystemVersion,
      Platform.localHostname,
      Platform.numberOfProcessors.toString(),
    ].join('|');

    return _generateHashFromString(fallbackData);
  }

  String _generateHashFromString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString().substring(0, 32); // Use first 32 characters of SHA256
  }
}

final hwidManager = HwidManager();