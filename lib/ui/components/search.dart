// SPDX-FileCopyrightText: 2022 Foundation Devices Inc.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:envoy/ui/theme/envoy_colors.dart';
import 'package:envoy/ui/theme/envoy_icons.dart';
import 'package:envoy/ui/theme/envoy_spacing.dart';
import 'package:envoy/ui/theme/envoy_typography.dart';

class EnvoySearch extends StatefulWidget {
  const EnvoySearch({
    Key? key,
    required this.filterSearchResults,
    required this.controller,
  }) : super(key: key);

  final void Function(String) filterSearchResults;
  final TextEditingController controller;

  @override
  State<EnvoySearch> createState() => _EnvoySearchState();
}

class _EnvoySearchState extends State<EnvoySearch> {
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(
        horizontal: EnvoySpacing.medium1,
      ),
      decoration: BoxDecoration(
        color: EnvoyColors.surface2,
        border: _focus.hasFocus
            ? Border.all(color: EnvoyColors.accentPrimary)
            : Border.all(color: Colors.transparent),
        borderRadius: BorderRadius.all(
          Radius.circular(EnvoySpacing.medium3),
        ),
      ),
      child: TextFormField(
        onChanged: (text) {
          widget.filterSearchResults(text);
        },
        style: EnvoyTypography.body,
        textAlignVertical: TextAlignVertical.top,
        controller: widget.controller,
        focusNode: _focus,
        cursorColor: EnvoyColors.accentPrimary,
        decoration: InputDecoration(
            labelText: "Search...", // TODO: FIGMA
            labelStyle: EnvoyTypography.body.copyWith(
              color: EnvoyColors.textTertiary,
            ),
            floatingLabelBehavior: FloatingLabelBehavior.never,
            alignLabelWithHint: true,
            isDense: true,
            contentPadding: EdgeInsets.only(bottom: EnvoySpacing.medium1),
            border: InputBorder.none,
            focusedBorder: InputBorder.none,
            enabledBorder: InputBorder.none,
            errorBorder: InputBorder.none,
            disabledBorder: InputBorder.none,
            focusedErrorBorder: InputBorder.none,
            icon: EnvoyIcon(
              EnvoyIcons.search,
              size: EnvoyIconSize.small,
              color: EnvoyColors.textTertiary,
            ),
            suffixIcon: _focus.hasFocus
                ? Padding(
                    padding: const EdgeInsets.only(left: EnvoySpacing.medium1),
                    child: GestureDetector(
                      child: EnvoyIcon(EnvoyIcons.remove),
                      onTap: () async {
                        setState(() {
                          widget.controller.text = "";
                        });
                      },
                    ),
                  )
                : SizedBox()),
      ),
    );
  }
}
