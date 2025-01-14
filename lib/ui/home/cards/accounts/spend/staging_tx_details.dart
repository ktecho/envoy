// SPDX-FileCopyrightText: 2023 Foundation Devices Inc.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:ui';

import 'package:envoy/business/account.dart';
import 'package:envoy/business/coin_tag.dart';
import 'package:envoy/business/exchange_rate.dart';
import 'package:envoy/business/settings.dart';
import 'package:envoy/ui/background.dart';
import 'package:envoy/ui/home/cards/accounts/accounts_state.dart';
import 'package:envoy/ui/home/cards/accounts/detail/transaction/tx_note_dialog_widget.dart';
import 'package:envoy/ui/home/cards/accounts/spend/spend_state.dart';
import 'package:envoy/ui/home/cards/accounts/spend/staging_tx_tagging.dart';
import 'package:envoy/ui/indicator_shield.dart';
import 'package:envoy/ui/state/send_screen_state.dart';
import 'package:envoy/ui/theme/envoy_colors.dart';
import 'package:envoy/ui/theme/envoy_spacing.dart';
import 'package:envoy/ui/widgets/blur_dialog.dart';
import 'package:envoy/util/amount.dart';
import 'package:envoy/util/list_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

class StagingTxDetails extends ConsumerStatefulWidget {
  const StagingTxDetails({super.key});

  @override
  ConsumerState createState() => _SpendTxDetailsState();
}

class _SpendTxDetailsState extends ConsumerState<StagingTxDetails> {
  GlobalKey _key = GlobalKey();

  @override
  Widget build(BuildContext context) {
    Account? account = ref.watch(selectedAccountProvider);
    if (account == null) {
      return Container();
    }
    final inputs = ref.watch(spendInputTagsProvider);
    final CoinTag? changeOutputTag =
        ref.watch(stagingTxChangeOutPutTagProvider);
    final totalReceiveAmount = ref.watch(receiveAmountProvider);
    final totalChangeAmount = ref.watch(changeAmountProvider);
    final unit = ref.watch(sendScreenUnitProvider);
    final inputTags = inputs?.map((e) => e.item1).toList().unique(
              (element) => element.id,
            ) ??
        [];
    List<CoinTag> tags = inputs?.map((e) => e.item1).toList() ?? [];
    int totalInputAmount = inputs?.fold(
            0,
            (previousValue, element) =>
                previousValue! + element.item2.amount) ??
        0;
    final accountAccentColor = account.color;

    TextStyle _textStyleAmountSatBtc =
        Theme.of(context).textTheme.headlineSmall!.copyWith(
              color: EnvoyColors.textPrimary,
              fontSize: 15,
            );

    TextStyle _textStyleFiat = Theme.of(context).textTheme.titleSmall!.copyWith(
          color: EnvoyColors.textTertiary,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        );
    final note = ref.watch(stagingTxNoteProvider) ?? "";

    return Stack(
      children: [
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black,
                    Colors.black,
                    Colors.transparent,
                  ]),
            ),
          ),
        ),
        Positioned.fill(
          child: GestureDetector(
            onTapDown: (details) {
              final height = MediaQuery.of(context).size.height;

              /// if user taps on the bottom 60% of the screen, close the dialog
              if (details.localPosition.dy / height >= .5) {
                Navigator.pop(context);
              }
            },
            child: Scaffold(
              backgroundColor: Colors.black12,
              appBar: AppBar(
                elevation: 0,
                backgroundColor: Colors.transparent,
                leading: SizedBox.shrink(),
                actions: [
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                  )
                ],
                flexibleSpace: SafeArea(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        height: 100,
                        child: IndicatorShield(),
                      ),
                      Text(
                        "Transaction Details".toUpperCase(), // TODO: FIGMA
                        style:
                            Theme.of(context).textTheme.displayMedium?.copyWith(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ],
                  ),
                ),
              ),
              body: SingleChildScrollView(
                key: _key,
                child: Padding(
                  padding: const EdgeInsets.all(EnvoySpacing.small),
                  child: Container(
                    padding: EdgeInsets.all(8),
                    child: AnimatedContainer(
                      height: 240,
                      duration: Duration(milliseconds: 250),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                        border: Border.all(
                            color: Colors.black,
                            width: 2,
                            style: BorderStyle.solid),
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              accountAccentColor,
                              Colors.black,
                            ]),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.all(Radius.circular(24)),
                            border: Border.all(
                                color: accountAccentColor,
                                width: 2,
                                style: BorderStyle.solid)),
                        child: ClipRRect(
                            borderRadius: BorderRadius.all(Radius.circular(24)),
                            child: StripesBackground(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    height: 36,
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 8),
                                    margin: EdgeInsets.symmetric(
                                        vertical: 8, horizontal: 4),
                                    decoration: BoxDecoration(
                                      borderRadius:
                                          BorderRadius.all(Radius.circular(24)),
                                      color: Colors.white,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              alignment: Alignment(0, 0),
                                              child: SizedBox.square(
                                                  dimension: 12,
                                                  child: SvgPicture.asset(
                                                    unit == DisplayUnit.btc
                                                        ? "assets/icons/ic_bitcoin_straight.svg"
                                                        : "assets/icons/ic_sats.svg",
                                                    color: Color(0xff808080),
                                                  )),
                                            ),
                                            Container(
                                              alignment: Alignment.centerRight,
                                              padding: EdgeInsets.only(
                                                  left: unit == DisplayUnit.btc
                                                      ? 4
                                                      : 0,
                                                  right: unit == DisplayUnit.btc
                                                      ? 0
                                                      : 8),
                                              child: Text(
                                                "${getFormattedAmount(totalReceiveAmount, trailingZeroes: true)}",
                                                textAlign:
                                                    unit == DisplayUnit.btc
                                                        ? TextAlign.start
                                                        : TextAlign.end,
                                                style: _textStyleAmountSatBtc,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Container(
                                          constraints:
                                              BoxConstraints(minWidth: 80),
                                          alignment: Alignment.centerRight,
                                          child: Text(
                                            ExchangeRate().getFormattedAmount(
                                                totalReceiveAmount,
                                                wallet: account.wallet),
                                            style: _textStyleFiat,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.end,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                      child: Container(
                                    margin: EdgeInsets.symmetric(
                                        vertical: 4, horizontal: 4),
                                    padding: EdgeInsets.symmetric(
                                        horizontal: EnvoySpacing.small,
                                        vertical: EnvoySpacing.small),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.all(
                                          Radius.circular(
                                              EnvoySpacing.medium1)),
                                      color: Colors.white,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.max,
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.max,
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Row(
                                              children: [
                                                SvgPicture.asset(
                                                  "assets/icons/ic_utxos.svg",
                                                  width: 16,
                                                  height: 16,
                                                ),
                                                Padding(
                                                    padding: EdgeInsets.only(
                                                        left: 8)),
                                                Text(
                                                    "Spent from ${tags.length} coins")
                                              ],
                                            ),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              mainAxisSize: MainAxisSize.max,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.center,
                                                  children: [
                                                    Container(
                                                      alignment:
                                                          Alignment(0, 0),
                                                      child: SizedBox.square(
                                                          dimension: 12,
                                                          child:
                                                              SvgPicture.asset(
                                                            unit ==
                                                                    DisplayUnit
                                                                        .btc
                                                                ? "assets/icons/ic_bitcoin_straight.svg"
                                                                : "assets/icons/ic_sats.svg",
                                                            color: Color(
                                                                0xff808080),
                                                          )),
                                                    ),
                                                    Container(
                                                      alignment:
                                                          Alignment.centerRight,
                                                      child: Text(
                                                        "${getFormattedAmount(totalInputAmount, trailingZeroes: true)}",
                                                        textAlign: unit ==
                                                                DisplayUnit.btc
                                                            ? TextAlign.start
                                                            : TextAlign.end,
                                                        style:
                                                            _textStyleAmountSatBtc,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                Container(
                                                  constraints: BoxConstraints(
                                                      minWidth: 40),
                                                  alignment:
                                                      Alignment.centerRight,
                                                  margin: EdgeInsets.only(
                                                      left: EnvoySpacing.small),
                                                  child: Text(
                                                    ExchangeRate()
                                                        .getFormattedAmount(
                                                            totalInputAmount,
                                                            wallet:
                                                                account.wallet),
                                                    style: _textStyleFiat,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    textAlign: TextAlign.end,
                                                  ),
                                                ),
                                              ],
                                            )
                                          ],
                                        ),
                                        Padding(
                                            padding: EdgeInsets.all(
                                                EnvoySpacing.xs)),
                                        Container(
                                          height: 24,
                                          margin: EdgeInsets.only(
                                              left: EnvoySpacing.medium2),
                                          child: ListView(
                                            scrollDirection: Axis.horizontal,
                                            children: inputTags.map((e) {
                                              return _coinTag(e.name);
                                            }).toList(),
                                          ),
                                        ),
                                        Padding(
                                            padding: EdgeInsets.all(
                                                EnvoySpacing.xs)),
                                        Row(
                                            mainAxisSize: MainAxisSize.max,
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.compare_arrows,
                                                    size: 16,
                                                  ),
                                                  Padding(
                                                      padding: EdgeInsets.only(
                                                          left: 8)),
                                                  Text("Change Received")
                                                ],
                                              ),
                                              Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .spaceBetween,
                                                mainAxisSize: MainAxisSize.max,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.center,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Container(
                                                        alignment:
                                                            Alignment(0, 0),
                                                        child: SizedBox.square(
                                                            dimension: 12,
                                                            child: SvgPicture
                                                                .asset(
                                                              unit ==
                                                                      DisplayUnit
                                                                          .btc
                                                                  ? "assets/icons/ic_bitcoin_straight.svg"
                                                                  : "assets/icons/ic_sats.svg",
                                                              color: Color(
                                                                  0xff808080),
                                                            )),
                                                      ),
                                                      Container(
                                                        alignment: Alignment
                                                            .centerRight,
                                                        child: Text(
                                                          "${getFormattedAmount(totalChangeAmount, trailingZeroes: true)}",
                                                          textAlign: unit ==
                                                                  DisplayUnit
                                                                      .btc
                                                              ? TextAlign.start
                                                              : TextAlign.end,
                                                          style:
                                                              _textStyleAmountSatBtc,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  Container(
                                                    constraints: BoxConstraints(
                                                        minWidth: 40),
                                                    alignment:
                                                        Alignment.centerRight,
                                                    margin: EdgeInsets.only(
                                                        left:
                                                            EnvoySpacing.small),
                                                    child: Text(
                                                      ExchangeRate()
                                                          .getFormattedAmount(
                                                              totalChangeAmount,
                                                              wallet: account
                                                                  .wallet),
                                                      style: _textStyleFiat,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      textAlign: TextAlign.end,
                                                    ),
                                                  ),
                                                ],
                                              )
                                            ]),
                                        Padding(
                                            padding: EdgeInsets.all(
                                                EnvoySpacing.xs)),
                                        Container(
                                          height: 24,
                                          margin: EdgeInsets.only(
                                              left: EnvoySpacing.medium2),
                                          child: ListView(
                                            scrollDirection: Axis.horizontal,
                                            children: [
                                              GestureDetector(
                                                  onTap: () {
                                                    showEnvoyDialog(
                                                        context: context,
                                                        builder: Builder(
                                                          builder: (context) =>
                                                              ChooseTagForStagingTx(
                                                            accountId:
                                                                account.id!,
                                                            onTagUpdate: () {
                                                              Navigator.pop(
                                                                  context);
                                                            },
                                                          ),
                                                        ),
                                                        alignment: Alignment(
                                                            0.0, -.6));
                                                  },
                                                  child: _coinTag(
                                                      changeOutputTag == null
                                                          ? "Untagged"
                                                          : changeOutputTag
                                                              .name)),
                                            ],
                                          ),
                                        ),
                                        Padding(
                                            padding: EdgeInsets.all(
                                                EnvoySpacing.small)),
                                        GestureDetector(
                                          onTap: () {
                                            showEnvoyDialog(
                                                context: context,
                                                dialog: TxNoteDialog(
                                                  onAdd: (note) {
                                                    ref
                                                        .read(
                                                            stagingTxNoteProvider
                                                                .notifier)
                                                        .state = note;
                                                    Navigator.pop(context);
                                                  },
                                                  txId: "UpcomingTx",
                                                  noteHintText:
                                                      "i.e. Bought P2P Bitcoin",

                                                  ///TODO: figma
                                                  noteSubTitle:
                                                      "Save some details about your transaction.",

                                                  ///TODO: figma
                                                  noteTitle: "Add a Note",

                                                  value: ref.read(
                                                      stagingTxNoteProvider),
                                                ),
                                                alignment:
                                                    Alignment(0.0, -0.8));
                                          },
                                          child: Container(
                                            color: Colors.transparent,
                                            padding:
                                                EdgeInsets.all(EnvoySpacing.xs),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              mainAxisSize: MainAxisSize.max,
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Flexible(
                                                  flex: 1,
                                                  child: Row(
                                                    children: [
                                                      Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(left: 4),
                                                        child: SvgPicture.asset(
                                                          "assets/icons/ic_notes.svg",
                                                          color: Colors.black,
                                                          height: 14,
                                                        ),
                                                      ),
                                                      Padding(
                                                          padding:
                                                              EdgeInsets.all(
                                                                  4)),
                                                      Text(
                                                        "Notes", //TODO: figma
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                                color: Colors
                                                                    .black,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Expanded(
                                                    child: Container(
                                                  alignment:
                                                      Alignment.centerRight,
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.end,
                                                    mainAxisSize:
                                                        MainAxisSize.max,
                                                    mainAxisAlignment:
                                                        MainAxisAlignment.end,
                                                    children: [
                                                      Expanded(
                                                        child: Text("$note",
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                            maxLines: 2,
                                                            style: Theme.of(
                                                                    context)
                                                                .textTheme
                                                                .bodySmall
                                                                ?.copyWith(
                                                                    color: EnvoyColors
                                                                        .textPrimary,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .w600,
                                                                    fontSize:
                                                                        12),
                                                            textAlign:
                                                                TextAlign.end),
                                                      ),
                                                      Padding(
                                                          padding:
                                                              EdgeInsets.all(
                                                                  EnvoySpacing
                                                                      .xs)),
                                                      note.trim().isNotEmpty
                                                          ? SvgPicture.asset(
                                                              note
                                                                      .trim()
                                                                      .isNotEmpty
                                                                  ? "assets/icons/ic_edit_note.svg"
                                                                  : "assets/icons/ic_notes.svg",
                                                              color: Theme.of(
                                                                      context)
                                                                  .primaryColor,
                                                              height: 14,
                                                            )
                                                          : Icon(
                                                              Icons
                                                                  .add_circle_rounded,
                                                              color: EnvoyColors
                                                                  .accentPrimary,
                                                              size: 16),
                                                    ],
                                                  ),
                                                )),
                                              ],
                                            ),
                                          ),
                                        ),
                                        Padding(
                                            padding: EdgeInsets.all(
                                                EnvoySpacing.xs)),
                                      ],
                                    ),
                                  )),
                                ],
                              ),
                            )),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _coinTag(String title) {
    TextStyle _titleStyle = Theme.of(context).textTheme.titleSmall!.copyWith(
          color: EnvoyColors.accentPrimary,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        );
    return Container(
      margin: EdgeInsets.only(right: EnvoySpacing.small),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            "assets/icons/ic_tag.svg",
            color: EnvoyColors.accentPrimary,
            height: 12,
          ),
          Padding(padding: EdgeInsets.only(left: 4)),
          Text(
            "${title}",
            style: _titleStyle,
          )
        ],
      ),
    );
  }
}
