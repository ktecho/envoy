// SPDX-FileCopyrightText: 2022 Foundation Devices Inc.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:envoy/business/account.dart';
import 'package:envoy/business/exchange_rate.dart';
import 'package:envoy/business/settings.dart';
import 'package:envoy/ui/envoy_colors.dart';
import 'package:envoy/ui/envoy_icons.dart';
import 'package:envoy/ui/pages/scanner_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:envoy/business/bitcoin_parser.dart';
import 'package:envoy/ui/state/send_screen_state.dart';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class AddressEntry extends ConsumerStatefulWidget {
  final Function(String)? onAddressChanged;
  final Function(int)? onAmountChanged;
  final bool canEdit;
  final Account account;
  final String? initalAddress;
  final TextEditingController? controller;
  final Function(ParseResult)? onPaste;

  AddressEntry(
      {this.initalAddress,
      this.onAddressChanged,
      this.onAmountChanged,
      this.canEdit = true,
      this.controller,
      this.onPaste,
      required this.account});

  @override
  ConsumerState<AddressEntry> createState() => _AddressEntryState();
}

class _AddressEntryState extends ConsumerState<AddressEntry> {
  String get text => widget.controller?.text ?? "";
  bool addressValid = false;

  set text(String newAddress) {
    widget.controller?.text = newAddress;
  }

  @override
  void initState() {
    if (widget.initalAddress != null) {
      widget.controller?.text = widget.initalAddress!;
    }

    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    var unit = ref.read(sendScreenUnitProvider);

    return Material(
      child: Form(
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Container(
          decoration: BoxDecoration(
              color: Colors.black12, borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: TextFormField(
                enabled: widget.canEdit,
                controller: widget.controller,
                style: TextStyle(
                    fontSize: 14,
                    overflow: TextOverflow.fade,
                    fontWeight: FontWeight.w500),
                onChanged: (value) async {
                  widget.onAddressChanged?.call(value);
                },
                decoration: InputDecoration(
                  // Disable the borders
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  prefixIcon: Container(
                      margin: EdgeInsets.symmetric(horizontal: 4),
                      child: Text("To:")),
                  // TODO: FIGMA
                  isDense: true,
                  prefixIconConstraints: BoxConstraints(
                    minWidth: 18,
                    minHeight: 12,
                  ),
                  suffixIconConstraints: BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 16.0, horizontal: 0.0),
                  suffixIcon: !widget.canEdit
                      ? null
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            InkWell(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4, horizontal: 4),
                                child: Icon(
                                  Icons.paste,
                                  size: 21,
                                  color: EnvoyColors.darkTeal,
                                ),
                              ),
                              onTap: () async {
                                if (widget.onPaste != null) {
                                  ClipboardData? cdata =
                                      await Clipboard.getData(
                                          Clipboard.kTextPlain);
                                  String? textCopied = cdata?.text ?? null;
                                  var decodedInfo = await BitcoinParser.parse(
                                      textCopied!,
                                      fiatExchangeRate:
                                          ExchangeRate().selectedCurrencyRate,
                                      wallet: widget.account.wallet,
                                      selectedFiat: Settings().selectedFiat,
                                      currentUnit: unit);
                                  widget.onPaste!(decodedInfo);
                                  if (decodedInfo.address != null) {
                                    validate(decodedInfo.address!);
                                  }
                                } else {
                                  ClipboardData? cdata =
                                      await Clipboard.getData(
                                          Clipboard.kTextPlain);
                                  String? text = cdata?.text ?? null;
                                  if (text != null) {
                                    widget.controller?.text = text;
                                    validate(text);
                                  }
                                }
                              },
                            ),
                            InkWell(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4, horizontal: 4),
                                child: Icon(
                                  EnvoyIcons.qr_scan,
                                  size: 20,
                                  color: EnvoyColors.darkTeal,
                                ),
                              ),
                              onTap: () {
                                // Maybe catch the result of pop instead of using callbacks?:

                                // final result = await Navigator.push(
                                //   context,
                                //   MaterialPageRoute(builder: (context) => const SelectionScreen()),
                                // );

                                Navigator.of(context, rootNavigator: true)
                                    .push(MaterialPageRoute(builder: (context) {
                                  return MediaQuery.removePadding(
                                    context: context,
                                    child:
                                        ScannerPage.address((address, amount) {
                                      widget.controller?.text = address;
                                      if (widget.onAddressChanged != null) {
                                        widget.onAddressChanged?.call(address);
                                      }
                                      if (widget.onAmountChanged != null) {
                                        widget.onAmountChanged!(amount);
                                      }
                                    }, widget.account),
                                  );
                                }));
                              },
                            )
                          ],
                        ),
                )),
          ),
        ),
      ),
    );
  }

  Future<void> validate(String value) async {
    final check = await widget.account.wallet.validateAddress(value);
    setState(() => addressValid = check);
    widget.onAddressChanged?.call(value);
  }
}
