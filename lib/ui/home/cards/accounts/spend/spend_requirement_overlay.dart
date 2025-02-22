// SPDX-FileCopyrightText: 2023 Foundation Devices Inc.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:envoy/business/account.dart';
import 'package:envoy/business/settings.dart';
import 'package:envoy/generated/l10n.dart';
import 'package:envoy/ui/components/envoy_checkbox.dart';
import 'package:envoy/ui/envoy_button.dart';
import 'package:envoy/ui/home/cards/accounts/accounts_state.dart';
import 'package:envoy/ui/home/cards/accounts/detail/coins/coins_state.dart';
import 'package:envoy/ui/home/cards/accounts/spend/spend_state.dart';
import 'package:envoy/ui/routes/accounts_router.dart';
import 'package:envoy/ui/state/home_page_state.dart';
import 'package:envoy/ui/theme/envoy_colors.dart';
import 'package:envoy/ui/theme/envoy_spacing.dart';
import 'package:envoy/ui/widgets/blur_dialog.dart';
import 'package:envoy/util/amount.dart';
import 'package:envoy/util/easing.dart';
import 'package:envoy/util/envoy_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

AnimationController? _spendOverlayAnimationController;

///overlay is visible in the viewport
Alignment _endAlignment = Alignment(0.0, 1.0);

///overlay is minimized
Alignment _minimizedAlignment = Alignment(0.0, 1.38);

///hidden from the viewport
Alignment _startAlignment = Alignment(0.0, 1.72);

Alignment? _currentOverlyAlignment = Alignment(0.0, 1.72);

OverlayEntry? overlayEntry = null;
Animation<Alignment>? _appearAnimation;

Future showSpendRequirementOverlay(
    BuildContext context, Account account) async {
  /// already visible
  if (_spendOverlayAnimationController?.isAnimating == true) {
    _spendOverlayAnimationController?.stop(canceled: true);
    _runAnimation(
        _currentOverlyAlignment ?? _endAlignment, Alignment(0.0, 1.0));
    return;
  }
  if (overlayEntry != null) {
    return;
  }
  await Future.delayed(Duration(milliseconds: 50));
  overlayEntry = OverlayEntry(builder: (context) {
    return SpendRequirementOverlay(account: account);
  });
  if (context.mounted)
    Overlay.of(context, rootOverlay: true).insert(overlayEntry!);
}

Future hideSpendRequirementOverlay({bool noAnimation = false}) async {
  if (noAnimation) {
    overlayEntry?.remove();
    overlayEntry?.dispose();
    overlayEntry = null;
  } else {
    if (overlayEntry != null && _spendOverlayAnimationController != null) {
      _runAnimation(_currentOverlyAlignment!, Alignment(0.0, 1.72))
          .then((value) => Future.delayed(Duration(milliseconds: 250)))
          .then((value) {
        overlayEntry?.remove();
        overlayEntry?.dispose();
        overlayEntry = null;
      }).catchError((ero) {
        overlayEntry?.remove();
        overlayEntry?.dispose();
        overlayEntry = null;
      });
    }
  }
}

Future _runAnimation(Alignment startAlign, Alignment endAlign) {
  _appearAnimation = _spendOverlayAnimationController!.drive(
    AlignmentTween(
      begin: startAlign,
      end: endAlign,
    ),
  );

  SpringDescription spring = SpringDescription.withDampingRatio(
    mass: 1.5,
    stiffness: 300.0,
    ratio: 0.4,
  );

  final simulation = SpringSimulation(spring, 0, 1, -3.39068);
  return _spendOverlayAnimationController!.animateWith(simulation);
}

class SpendRequirementOverlay extends ConsumerStatefulWidget {
  final Account account;

  const SpendRequirementOverlay({super.key, required this.account});

  @override
  ConsumerState createState() => SpendRequirementOverlayState();
}

class SpendRequirementOverlayState
    extends ConsumerState<SpendRequirementOverlay>
    with SingleTickerProviderStateMixin {
  Alignment _dragAlignment = _startAlignment;

  @override
  void initState() {
    if (_spendOverlayAnimationController != null) {
      _spendOverlayAnimationController?.dispose();
      _spendOverlayAnimationController = null;
    }
    _spendOverlayAnimationController = AnimationController(
      vsync: this,
      reverseDuration: Duration(milliseconds: 300),
    );
    _appearAnimation = AlignmentTween(
      begin: _dragAlignment,
      end: _endAlignment,
    ).animate(
      CurvedAnimation(
        parent: _spendOverlayAnimationController!,
        curve: EnvoyEasing.easeInOut,
      ),
    );
    _spendOverlayAnimationController?.addListener(() {
      setState(() {
        _dragAlignment = _appearAnimation!.value;
      });
    });
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      _spendOverlayAnimationController?.animateTo(1,
          duration: Duration(milliseconds: 250), curve: EnvoyEasing.easeInOut);
    });
  }

  /// run physics simulation to animate overlay,
  /// parameter alignment will be used as end state of the animation
  void _runSpringSimulation(
      Offset pixelsPerSecond, Alignment alignment, Size size) {
    _appearAnimation = _spendOverlayAnimationController!.drive(
      AlignmentTween(
        begin: _dragAlignment,
        end: alignment,
      ),
    );
    final unitsPerSecondX = pixelsPerSecond.dx / size.width;
    final unitsPerSecondY = pixelsPerSecond.dy / size.height;
    final unitsPerSecond = Offset(unitsPerSecondX, unitsPerSecondY);
    final unitVelocity = unitsPerSecond.distance;

    SpringDescription spring = SpringDescription.withDampingRatio(
      mass: 1.5,
      stiffness: 300.0,
      ratio: 0.4,
    );

    final simulation = SpringSimulation(spring, 0, 1, -unitVelocity);

    _spendOverlayAnimationController!.animateWith(simulation);
  }

  ///hide overlay to show dialogs
  bool _hideOverlay = false;
  bool _isInMinimizedState = false;

  @override
  void dispose() {
    // _spendOverlayAnimationController?.dispose();
    _spendOverlayAnimationController = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final totalSelectedAmount =
        ref.watch(getTotalSelectedAmount(widget.account.id!));

    final requiredAmount = ref.watch(spendAmountProvider);

    bool hideRequiredAmount = requiredAmount == 0;

    bool valid =
        (totalSelectedAmount != 0 && totalSelectedAmount >= requiredAmount);

    _currentOverlyAlignment = _appearAnimation!.value;

    final size = MediaQuery.of(context).size;

    //hide when dialog is shown, we dont want to remove overlay from the widget tree
    //if the user chose to stay in the coin selection screen and we need to show the overlay again
    return AnimatedOpacity(
      opacity: _hideOverlay ? 0 : 1,
      duration: Duration(milliseconds: 120),
      child: GestureDetector(
        onPanDown: (details) {
          _spendOverlayAnimationController!.stop();
        },
        // TODO: implement dismiss
        onPanUpdate: (details) {
          setState(() {
            Alignment update = _dragAlignment;
            update += Alignment(
              0,
              details.delta.dy / (size.height / 2),
            );
            if (update.y >= _endAlignment.y) {
              _dragAlignment = update;
            }
          });
        },
        onPanEnd: (details) {
          _isInMinimizedState = false;

          double currentY = _dragAlignment.y;
          if (currentY < 1.5) {
            _runSpringSimulation(
                details.velocity.pixelsPerSecond, _endAlignment, size);
          }
          final unitsPerSecondX =
              details.velocity.pixelsPerSecond.dx / size.width;
          final unitsPerSecondY =
              details.velocity.pixelsPerSecond.dy / size.height;
          final unitsPerSecond = Offset(unitsPerSecondX, unitsPerSecondY);
          final unitVelocity = unitsPerSecond.distance;

          if (unitVelocity >= 3.0) {
            _runSpringSimulation(
                details.velocity.pixelsPerSecond, _endAlignment, size);
          }
          //threshold to show dismiss dialog
          if (currentY >= 1.3) {
            _isInMinimizedState = true;
            _runSpringSimulation(
                details.velocity.pixelsPerSecond, _minimizedAlignment, size);
          }
        },
        onTap: () {
          if (_isInMinimizedState) {
            _isInMinimizedState = false;
            _runSpringSimulation(Offset(0, 0), _endAlignment, size);
          } else {
            _isInMinimizedState = true;
            _runSpringSimulation(Offset(0, 0), _minimizedAlignment, size);
          }
        },
        child: Align(
          alignment: _dragAlignment,
          child: Transform.scale(
            scale: 1.0,
            child: SizedBox(
                height: 220,
                width: MediaQuery.of(context).size.width,
                child: Container(
                  decoration: BoxDecoration(boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      spreadRadius: 0,
                      blurRadius: 10,
                      offset: Offset(0, 0), // changes position of shadow
                    ),
                  ]),
                  child: Card(
                    elevation: 100,
                    shadowColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(EnvoySpacing.medium1),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                          vertical: EnvoySpacing.small,
                          horizontal: EnvoySpacing.medium1),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          Container(
                              width: 40,
                              height: 4,
                              margin: EdgeInsets.only(
                                  top: EnvoySpacing.xs,
                                  bottom: EnvoySpacing.medium1),
                              decoration: BoxDecoration(
                                color: Colors.grey,
                                borderRadius: BorderRadius.circular(2),
                              )),
                          Expanded(
                            child: AnimatedOpacity(
                              opacity: _isInMinimizedState ? 0 : 1,
                              duration: Duration(milliseconds: 230),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Padding(
                                          padding: EdgeInsets.all(
                                              !hideRequiredAmount
                                                  ? EnvoySpacing.xs
                                                  : 0)),
                                      !hideRequiredAmount
                                          ? Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal:
                                                          EnvoySpacing.xs),
                                              child: Row(
                                                children: [
                                                  Text(S()
                                                      .coincontrol_edit_transaction_required_inputs),
                                                  Spacer(),
                                                  SizedBox.square(
                                                      dimension: 12,
                                                      child: SvgPicture.asset(
                                                        Settings().displayUnit ==
                                                                DisplayUnit.btc
                                                            ? "assets/icons/ic_bitcoin_straight.svg"
                                                            : "assets/icons/ic_sats.svg",
                                                        color:
                                                            Color(0xff808080),
                                                      )),
                                                  Text(
                                                    "${getFormattedAmount(requiredAmount, trailingZeroes: true)}",
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .titleSmall,
                                                  ),
                                                ],
                                              ),
                                            )
                                          : SizedBox(),
                                      Padding(
                                          padding:
                                              EdgeInsets.all(EnvoySpacing.xs)),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: EnvoySpacing.xs),
                                        child: Row(
                                          children: [
                                            Text(
                                              ///TODO: localize
                                              "Selected amount",
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall,
                                            ),
                                            Spacer(),
                                            SizedBox.square(
                                                dimension: 12,
                                                child: SvgPicture.asset(
                                                  Settings().displayUnit ==
                                                          DisplayUnit.btc
                                                      ? "assets/icons/ic_bitcoin_straight.svg"
                                                      : "assets/icons/ic_sats.svg",
                                                  color: Color(0xff808080),
                                                )),
                                            Text(
                                              "${getFormattedAmount(totalSelectedAmount, trailingZeroes: true)}",
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      EnvoyButton(
                                        enabled: valid,
                                        readOnly: !valid,
                                        type: EnvoyButtonTypes.primaryModal,
                                        hideRequiredAmount
                                            ? "Send Selected"
                                            : S()
                                                .coincontrol_edit_transaction_cta,
                                        onTap: () async {
                                          /// if the user is in utxo details screen we need to wait animations to finish
                                          /// before we can pop back to home screen
                                          if (Navigator.canPop(context)) {
                                            Navigator.of(context)
                                                .popUntil((route) {
                                              return route.settings
                                                  is MaterialPage;
                                            });
                                            await Future.delayed(
                                                Duration(milliseconds: 320));
                                          }
                                          hideSpendRequirementOverlay();
                                          await Future.delayed(
                                              Duration(milliseconds: 120));
                                          if (ref.read(spendEditModeProvider)) {
                                            GoRouter.of(context)
                                                .push(ROUTE_ACCOUNT_SEND);
                                            GoRouter.of(context).push(
                                                ROUTE_ACCOUNT_SEND_CONFIRM);
                                          } else {
                                            GoRouter.of(context)
                                                .push(ROUTE_ACCOUNT_SEND);
                                          }
                                        },
                                      ),
                                      Padding(
                                          padding:
                                              EdgeInsets.all(EnvoySpacing.xs)),
                                      EnvoyButton(
                                        enabled: valid,
                                        readOnly: !valid,
                                        type: EnvoyButtonTypes.secondary,
                                        hideRequiredAmount
                                            ? "Discard Selection"
                                            : "Cancel",
                                        onTap: cancel,
                                      ),
                                      Padding(
                                          padding: EdgeInsets.all(
                                              EnvoySpacing.small)),
                                    ],
                                  )
                                ],
                              ),
                            ),
                          )
                        ],
                      ),
                    ),
                  ),
                )),
          ),
        ),
      ),
    );
  }

  cancel() async {
    /// if the user is in utxo details screen we need to wait animations to finish
    /// before we can pop back to home screen
    if (await EnvoyStorage()
        .checkPromptDismissed(DismissiblePrompt.txDiscardWarning)) {
      hideSpendRequirementOverlay();
      ref.read(coinSelectionStateProvider.notifier).reset();
      ref.read(spendEditModeProvider.notifier).state = false;
      return;
    }
    setState(() {
      _hideOverlay = true;
    });
    bool discard = await showEnvoyDialog(
        context: context,
        useRootNavigator: true,
        dialog: SpendSelectionCancelWarning());
    await Future.delayed(Duration(milliseconds: 130));
    setState(() {
      _hideOverlay = false;
    });
    if (discard) {
      hideSpendRequirementOverlay();
      ref.read(coinSelectionStateProvider.notifier).reset();
      ref.read(spendEditModeProvider.notifier).state = false;
      if (ref.read(selectedAccountProvider) != null)
        showSpendRequirementOverlay(
            context, ref.read(selectedAccountProvider)!);
    }
  }
}

class SpendSelectionCancelWarning extends ConsumerStatefulWidget {
  const SpendSelectionCancelWarning({super.key});

  @override
  ConsumerState<SpendSelectionCancelWarning> createState() =>
      _SpendSelectionCancelWarningState();
}

class _SpendSelectionCancelWarningState
    extends ConsumerState<SpendSelectionCancelWarning> {
  bool dismissed = false;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      setState(() {
        dismissed = ref.read(
            arePromptsDismissedProvider(DismissiblePrompt.txDiscardWarning));
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(28).add(EdgeInsets.only(top: -6)),
      constraints: BoxConstraints(
        minHeight: 300,
        maxWidth: 280,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: EnvoyColors.accentSecondary,
            size: 42,
          ),
          Padding(padding: EdgeInsets.all(EnvoySpacing.small)),
          //TODO: figma
          Text(
              "This will discard any coin selection changes. Do you want to proceed?",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall),
          Padding(padding: EdgeInsets.all(EnvoySpacing.small)),
          GestureDetector(
            onTap: () {
              setState(() {
                dismissed = !dismissed;
              });
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  child: EnvoyCheckbox(
                    value: dismissed,
                    onChanged: (value) {
                      if (value != null)
                        setState(() {
                          dismissed = value;
                        });
                    },
                  ),
                ),
                Text(
                  "Do not remind me", // TODO: FIGMA
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: dismissed ? Colors.black : Color(0xff808080),
                      ),
                ),
              ],
            ),
          ),
          Padding(padding: EdgeInsets.all(EnvoySpacing.xs)),
          EnvoyButton(
            "No",
            type: EnvoyButtonTypes.tertiary,
            onTap: () {
              if (dismissed) {
                EnvoyStorage()
                    .addPromptState(DismissiblePrompt.txDiscardWarning);
              } else {
                EnvoyStorage()
                    .removePromptState(DismissiblePrompt.txDiscardWarning);
              }
              Navigator.of(context).pop(false);
            },
          ),
          Padding(padding: EdgeInsets.all(EnvoySpacing.small)),
          EnvoyButton(
            "yes",
            type: EnvoyButtonTypes.primaryModal,
            onTap: () {
              if (dismissed) {
                EnvoyStorage()
                    .addPromptState(DismissiblePrompt.txDiscardWarning);
              } else {
                EnvoyStorage()
                    .removePromptState(DismissiblePrompt.txDiscardWarning);
              }
              Navigator.of(context).pop(true);
            },
          )
        ],
      ),
    );
  }
}
