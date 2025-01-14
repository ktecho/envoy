// SPDX-FileCopyrightText: 2022 Foundation Devices Inc.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:envoy/ui/theme/envoy_colors.dart';
import 'package:envoy/ui/theme/envoy_icons.dart';
import 'package:envoy/ui/theme/envoy_spacing.dart';
import 'package:envoy/ui/theme/envoy_typography.dart';
import 'package:flutter/material.dart';

class SettingsHeader extends StatelessWidget {
  const SettingsHeader(
      {Key? key,
      required this.title,
      required this.linkText,
      this.onTap,
      required this.icon})
      : super(key: key);

  final String title;
  final linkText;
  final Function()? onTap;
  final EnvoyIcons icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            EnvoyIcon(icon),
            SizedBox(
              width: EnvoySpacing.small,
            ),
            Text(
              title,
              style: EnvoyTypography.body,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: EnvoySpacing.medium1),
          child: GestureDetector(
            onTap: onTap,
            child: Text(
              linkText,
              style: EnvoyTypography.button
                  .copyWith(color: EnvoyColors.accentPrimary),
            ),
          ),
        ),
      ],
    );
  }
}
