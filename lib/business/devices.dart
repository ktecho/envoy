// SPDX-FileCopyrightText: 2022 Foundation Devices Inc.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:envoy/business/local_storage.dart';
import 'dart:convert';
import 'package:envoy/util/color_serializer.dart';
import 'account_manager.dart';
part 'devices.g.dart';

enum DeviceType { passportGen1, passportGen12, passportGen2 }

@JsonSerializable()
class Device {
  String name;
  final DeviceType type;
  final String serial;
  final DateTime datePaired;
  String firmwareVersion;
  List<String>? pairedAccountIds;

  @JsonKey(toJson: colorToJson, fromJson: colorFromJson)
  final Color color;

  Device(this.name, this.type, this.serial, this.datePaired,
      this.firmwareVersion, this.color);

  // Serialisation
  factory Device.fromJson(Map<String, dynamic> json) => _$DeviceFromJson(json);

  Map<String, dynamic> toJson() => _$DeviceToJson(this);
}

class Devices extends ChangeNotifier {
  List<Device> devices = [];
  LocalStorage _ls = LocalStorage();

  static const String _DEVICES_PREFS = "devices";
  static final Devices _instance = Devices._internal();

  factory Devices() {
    return _instance;
  }

  static Future<Devices> init() async {
    var singleton = Devices._instance;
    return singleton;
  }

  Devices._internal() {
    print("Instance of Devices created!");
    //_clearDevices();
    _restoreDevices();
  }

  add(Device device) {
    for (var currentDevice in devices) {
      // Don't add if device with same serial already present
      if (currentDevice.serial == device.serial) {
        return;
      }
    }

    devices.add(device);
    storeDevices();
  }

  //ignore:unused_element
  _clearDevices() {
    _ls.prefs.remove(_DEVICES_PREFS);
  }

  storeDevices() {
    String json = jsonEncode(devices);
    _ls.prefs.setString(_DEVICES_PREFS, json);
  }

  _restoreDevices() {
    if (_ls.prefs.containsKey(_DEVICES_PREFS)) {
      var storedDevices = jsonDecode(_ls.prefs.getString(_DEVICES_PREFS)!);
      for (var device in storedDevices) {
        devices.add(Device.fromJson(device));
      }
    }
  }

  renameDevice(Device device, String newName) {
    device.name = newName;
    storeDevices();
    notifyListeners();
  }

  deleteDevice(Device device) {
    // Delete connected accounts
    AccountManager().deleteDeviceAccounts(device);

    devices.remove(device);
    storeDevices();
    notifyListeners();
  }

  getDeviceName(String serialNumber) {
    return devices.firstWhere((d) => d.serial == serialNumber).name;
  }
}