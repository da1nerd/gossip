import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:location/location.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

class PermissionsService {
  static final PermissionsService _instance = PermissionsService._internal();
  factory PermissionsService() => _instance;
  PermissionsService._internal();

  Future<bool> requestAllPermissions() async {
    if (!Platform.isAndroid) {
      return false; // Only Android is supported for nearby connections
    }

    try {
      // Check Android version to determine which permissions to request
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkVersion = androidInfo.version.sdkInt;

      List<ph.Permission> permissionsToRequest = [];

      // Location permissions (required for all versions)
      if (sdkVersion >= 29) {
        permissionsToRequest.add(ph.Permission.locationWhenInUse);
      } else {
        permissionsToRequest.add(ph.Permission.location);
      }

      // Bluetooth permissions based on Android version
      if (sdkVersion >= 31) {
        // Android 12+ permissions
        permissionsToRequest.addAll([
          ph.Permission.bluetoothAdvertise,
          ph.Permission.bluetoothConnect,
          ph.Permission.bluetoothScan,
        ]);
      } else {
        // Android 11 and below
        permissionsToRequest.addAll([ph.Permission.bluetooth]);
      }

      // Nearby WiFi devices permission for Android 13+
      if (sdkVersion >= 33) {
        permissionsToRequest.add(ph.Permission.nearbyWifiDevices);
      }

      // Storage permission for file transfers (optional)
      permissionsToRequest.add(ph.Permission.storage);

      // Request all permissions
      Map<ph.Permission, ph.PermissionStatus> results =
          await permissionsToRequest.request();

      // Check if required permissions are granted (be more forgiving with optional ones)
      bool allGranted = true;
      List<ph.Permission> criticalPermissions = [
        ph.Permission.locationWhenInUse,
        ph.Permission.location,
        ph.Permission.bluetooth,
        ph.Permission.bluetoothAdvertise,
        ph.Permission.bluetoothConnect,
        ph.Permission.bluetoothScan,
      ];

      for (var permission in permissionsToRequest) {
        final status = results[permission] ?? ph.PermissionStatus.denied;
        if (status != ph.PermissionStatus.granted) {
          // Only fail for critical permissions
          if (criticalPermissions.contains(permission)) {
            allGranted = false;
            debugPrint('Critical permission $permission was denied');
          } else {
            debugPrint(
              'Optional permission $permission was denied (continuing anyway)',
            );
          }
        }
      }

      // Also check if location service is enabled
      if (allGranted) {
        final isLocationServiceEnabled = await _ensureLocationServiceEnabled();
        if (!isLocationServiceEnabled) {
          debugPrint('Location service is not enabled');
          return false;
        }
      }

      return allGranted;
    } catch (e) {
      debugPrint('Error requesting permissions: $e');
      return false;
    }
  }

  Future<bool> _ensureLocationServiceEnabled() async {
    try {
      final location = Location();

      bool serviceEnabled = await location.serviceEnabled();
      if (!serviceEnabled) {
        serviceEnabled = await location.requestService();
        if (!serviceEnabled) {
          return false;
        }
      }

      return true;
    } catch (e) {
      debugPrint('Error checking location service: $e');
      return false;
    }
  }

  Future<bool> checkPermissionsStatus() async {
    if (!Platform.isAndroid) {
      return false;
    }

    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkVersion = androidInfo.version.sdkInt;

      List<ph.Permission> requiredPermissions = [];

      // Location permissions
      if (sdkVersion >= 29) {
        requiredPermissions.add(ph.Permission.locationWhenInUse);
      } else {
        requiredPermissions.add(ph.Permission.location);
      }

      // Bluetooth permissions
      if (sdkVersion >= 31) {
        requiredPermissions.addAll([
          ph.Permission.bluetoothAdvertise,
          ph.Permission.bluetoothConnect,
          ph.Permission.bluetoothScan,
        ]);
      } else {
        requiredPermissions.addAll([ph.Permission.bluetooth]);
      }

      // Check all required permissions (be more forgiving)
      bool hasLocationPermission = false;
      bool hasBluetoothPermission = false;

      for (var permission in requiredPermissions) {
        final status = await permission.status;
        if (status == ph.PermissionStatus.granted) {
          if (permission == ph.Permission.locationWhenInUse ||
              permission == ph.Permission.location) {
            hasLocationPermission = true;
          }
          if (permission == ph.Permission.bluetooth ||
              permission == ph.Permission.bluetoothAdvertise ||
              permission == ph.Permission.bluetoothConnect ||
              permission == ph.Permission.bluetoothScan) {
            hasBluetoothPermission = true;
          }
        }
      }

      // Need at least one location permission and one bluetooth permission
      if (!hasLocationPermission || !hasBluetoothPermission) {
        return false;
      }

      // Check location service
      final location = Location();
      final serviceEnabled = await location.serviceEnabled();

      return serviceEnabled;
    } catch (e) {
      debugPrint('Error checking permissions status: $e');
      return false;
    }
  }

  Future<void> openAppSettings() async {
    await ph.openAppSettings();
  }
}
