// SPDX-FileCopyrightText: 2022 Foundation Devices Inc.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:envoy/ui/envoy_button.dart';
import 'package:flutter/material.dart';
import 'package:envoy/generated/l10n.dart';

import 'package:envoy/business/azteco_voucher.dart';

class AztecoRedeemModal extends StatefulWidget {
  final AztecoVoucher voucher;
  final PageController controller;

  const AztecoRedeemModal(
      {Key? key, required this.voucher, required this.controller})
      : super(key: key);

  @override
  State<AztecoRedeemModal> createState() => _AztecoRedeemModalState();
}

class _AztecoRedeemModalState extends State<AztecoRedeemModal> {
  @override
  Widget build(BuildContext context) {
    var headingTextStyle = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(fontWeight: FontWeight.w500, fontSize: 20);

    var voucherCodeTextStyle = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(fontWeight: FontWeight.w900, fontSize: 12);

    return Container(
      width: MediaQuery.of(context).size.width * 0.85,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 4 * 4, vertical: 4 * 4),
              child: IconButton(
                icon: Icon(Icons.close),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8 * 4),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Image.asset("assets/azteco_logo.png", scale: 1),
                Padding(
                  padding: const EdgeInsets.only(top: 4 * 4),
                  child: Text(
                    S().azteco_redeem_modal_heading,
                    textAlign: TextAlign.center,
                    style: headingTextStyle,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 5 * 4),
                  child: Text(
                    S().azteco_redeem_modal_subheading,
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 5 * 4),
                  child: Text(
                    "VOUCHER CODE", //TODO: change this when UI is updated
                    textAlign: TextAlign.center,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 1 * 4),
                  child: Text(
                    widget.voucher.code[0] +
                        " " +
                        widget.voucher.code[1] +
                        " " +
                        widget.voucher.code[2] +
                        " " +
                        widget.voucher.code[3],
                    textAlign: TextAlign.center,
                    style: voucherCodeTextStyle,
                  ),
                ),
                Padding(padding: EdgeInsets.all(4)),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 8 * 4, vertical: 6 * 4),
            child: Column(
              //Temporarily Disable Tor
              children: [
                EnvoyButton(
                  S().azteco_redeem_modal_CTA2,
                  type: EnvoyButtonTypes.secondary,
                  onTap: () {
                    Navigator.of(context).pop();
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4 * 4),
                  child: EnvoyButton(
                    S().azteco_redeem_modal_CTA1,
                    onTap: () {
                      widget.controller.nextPage(
                          duration: Duration(microseconds: 100),
                          curve: Curves.linear); // go to loading
                      // We are continually retrying anyway
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}