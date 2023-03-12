// SPDX-FileCopyrightText: 2022 Foundation Devices Inc.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:io';
import 'package:backup/backup.dart';
import 'package:envoy/business/account_manager.dart';
import 'package:envoy/business/settings.dart';
import 'package:flutter/services.dart';
import 'package:tor/tor.dart';
import 'package:wallet/wallet.dart';
import 'package:envoy/business/devices.dart';
import 'package:envoy/business/fees.dart';
import 'package:envoy/business/local_storage.dart';
import 'package:envoy/business/notifications.dart';
import 'package:file_saver/file_saver.dart';

const String SEED_KEY = "seed";
const String WALLET_DERIVED_PREFS = "wallet_derived";
const String LAST_BACKUP_PREFS = "last_backup";
const String LOCAL_SECRET_FILE_NAME = "local.secret";
const String LOCAL_SECRET_LAST_BACKUP_TIMESTAMP_FILE_NAME =
    LOCAL_SECRET_FILE_NAME + ".backup_timestamp";

const int SECRET_LENGTH_BYTES = 16;

class EnvoySeed {
  // 12 words == 128 + 4 == 132 (4 bits are checksum)
  // 128 bits == 16 bytes
  // Checksum is first 4 bits of SHA-256 of 16 bytes

  static const _platform = MethodChannel('envoy');

  static String encryptedBackupFileExtension = "mla";
  static String encryptedBackupFileName = "envoy_backup";
  static String encryptedBackupFilePath = LocalStorage().appDocumentsDir.path +
      "/" +
      encryptedBackupFileName +
      "." +
      encryptedBackupFileExtension;

  List<String> keysToBackUp = [
    Settings.SETTINGS_PREFS,
    // UpdatesManager.LATEST_FIRMWARE_FILE_PATH_PREFS,
    // UpdatesManager.LATEST_FIRMWARE_VERSION_PREFS,
    // ScvServer.SCV_CHALLENGE_PREFS,
    Fees.FEE_RATE_PREFS,
    AccountManager.ACCOUNTS_PREFS,
    Notifications.NOTIFICATIONS_PREFS,
    Devices.DEVICES_PREFS,
  ];

  Future generate() async {
    final generatedSeed = Wallet.generateSeed();
    return await deriveAndAddWallets(generatedSeed);
  }

  Future<bool> create(List<String> seedList, {String? passphrase}) async {
    String seed = seedList.join(" ");
    return await deriveAndAddWallets(seed, passphrase: passphrase);
  }

  Future<bool> deriveAndAddWallets(String seed, {String? passphrase}) async {
    final mainnetPath = "m/84'/0'/0'";
    final testnetPath = "m/84'/1'/0'";

    try {
      var mainnet = Wallet.deriveWallet(
          seed, mainnetPath, AccountManager.walletsDirectory, Network.Mainnet,
          privateKey: true, passphrase: passphrase);
      var testnet = Wallet.deriveWallet(
          seed, testnetPath, AccountManager.walletsDirectory, Network.Testnet,
          privateKey: true, passphrase: passphrase);

      AccountManager().addHotWalletAccount(mainnet);
      AccountManager().addHotWalletAccount(testnet);

      await store(seed);
      LocalStorage().prefs.setBool(WALLET_DERIVED_PREFS, true);

      return true;
    } on Exception catch (_) {
      return false;
    }
  }

  bool walletDerived() {
    final derived = LocalStorage().prefs.getBool(WALLET_DERIVED_PREFS);
    if (derived == null) {
      return false;
    }

    return derived;
  }

  Future<void> store(String seed) async {
    if (Settings().syncToCloud) {
      await saveNonSecure(seed, LOCAL_SECRET_FILE_NAME);
      _platform.invokeMethod('data_changed');
    }

    await LocalStorage().saveSecure(SEED_KEY, seed);
  }

  Future<void> backupData({bool cloud: true}) async {
    // Make sure we don't accidentally backup to Cloud
    if (Settings().syncToCloud == false) {
      cloud = false;
    }

    final seed = await get();
    Backup.perform(LocalStorage().prefs, keysToBackUp, seed!,
        Settings().envoyServerAddress, Tor().port,
        path: encryptedBackupFilePath, cloud: cloud);

    if (cloud) {
      LocalStorage()
          .prefs
          .setString(LAST_BACKUP_PREFS, DateTime.now().toIso8601String());
    }
  }

  Future<bool> restoreData({String? seed: null}) async {
    if (seed == null) {
      seed = await get();
    }

    return Backup.restore(
        LocalStorage().prefs, seed!, Settings().envoyServerAddress, Tor().port);
  }

  Future<bool> restoreOfflineData(String filePath, {String? seed: null}) async {
    if (seed == null) {
      seed = await get();
    }

    return Backup.restoreOffline(LocalStorage().prefs, seed!, filePath);
  }

  DateTime? getLastBackupTime() {
    final string = LocalStorage().prefs.getString(LAST_BACKUP_PREFS);
    if (string == null) {
      return null;
    }

    return DateTime.parse(string);
  }

  Future<void> saveOfflineData() async {
    await backupData(cloud: false);
    final backupBytes = File(encryptedBackupFilePath).readAsBytesSync();

    FileSaver.instance.saveAs(encryptedBackupFileName, backupBytes,
        encryptedBackupFileExtension, MimeType.TEXT);
  }

  Future<String?> get() async {
    String? secure = await getSecure();
    String? nonSecure = await getNonSecure();

    if (secure != null && nonSecure != null) {
      if (secure != nonSecure) {
        throw Exception("Different seed in secure and non-secure!");
      }

      return secure;
    }

    if (secure != null) {
      return secure;
    }

    if (nonSecure != null) {
      return nonSecure;
    }

    return null;
  }

  Future<String?> getSecure() async {
    if (!await LocalStorage().containsSecure(SEED_KEY)) {
      return null;
    }

    final seed = await LocalStorage().readSecure(SEED_KEY);
    return seed!;
  }

  Future<File> saveNonSecure(String data, String name) async {
    return LocalStorage().saveFile(name, data);
  }

  Future<String?> restoreNonSecure(String name) async {
    if (!await LocalStorage().fileExists(name)) {
      return null;
    }

    return await LocalStorage().readFile(name);
  }

  showSettingsMenu() {
    _platform.invokeMethod('show_settings');
  }

  Future<String?> getNonSecure() async {
    return await restoreNonSecure(LOCAL_SECRET_FILE_NAME);
  }

  Future<DateTime?> getLocalSecretLastBackupTimestamp() async {
    if (!await LocalStorage()
        .fileExists(LOCAL_SECRET_LAST_BACKUP_TIMESTAMP_FILE_NAME)) {
      return null;
    }

    String timestampString = await LocalStorage()
        .readFile(LOCAL_SECRET_LAST_BACKUP_TIMESTAMP_FILE_NAME);
    int timestamp =
        int.parse(timestampString.replaceAll(".", "").substring(0, 13));
    return DateTime.fromMillisecondsSinceEpoch(timestamp);
  }
}