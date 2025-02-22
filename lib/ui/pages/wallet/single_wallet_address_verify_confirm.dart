// SPDX-FileCopyrightText: 2022 Foundation Devices Inc.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:envoy/ui/envoy_button.dart';
import 'package:flutter/material.dart';
import 'package:envoy/ui/onboard/onboarding_page.dart';
import 'package:envoy/generated/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

class SingleWalletAddressVerifyConfirmPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return OnboardingPage(
      key: Key("single_wallet_verify_confirm"),
      clipArt: Image.asset("assets/address_verify.png"),
      text: [
        OnboardingText(
            header: S().pair_new_device_address_heading,
            text: S().pair_new_device_address_subheading),
      ],
      buttons: [
        OnboardingButton(
          label: S().pair_new_device_address_cta2,
          onTap: () {
            launchUrl(Uri.parse("mailto:hello@foundationdevices.com"));
          },
          type: EnvoyButtonTypes.secondary,
        ),
        OnboardingButton(
            label: S().pair_new_device_address_cta1,
            onTap: () {
              OnboardingPage.goHome(context);
            }),
      ],
    );
  }
}
