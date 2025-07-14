import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';

class HardwareId {
  static HardwareId? _instance;

  HardwareId._internal();

  factory HardwareId() {
    _instance ??= HardwareId._internal();
    return _instance!;
  }

  Future<String?> getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor;
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        // Fixed: Use computerName instead of productName for Windows device info
        return windowsInfo.computerName;
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        return macInfo.computerName;
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        return linuxInfo.machineId;
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }
}

final hardwareId = HardwareId();