// SPDX-FileCopyrightText: 2022 Foundation Devices Inc.
//
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:envoy/ui/background.dart';
import 'package:envoy/ui/shield.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

void popBackToHome(BuildContext context,
    {bool useRootNavigator = false}) async {
  /// get the router and navigator instance from the context
  /// if the parent widget of context get disposed,we wont be able to access goroouter and navigator.
  GoRouter router = GoRouter.of(context);
  NavigatorState navigator =
      Navigator.of(context, rootNavigator: useRootNavigator);

  /// push main route to make sure we are on the home page
  router.go("/");

  /// wait for the go router to push the route
  await Future.delayed(Duration(milliseconds: 100));

  /// Pop until we get to the home page (GoRouter Shell)
  navigator.popUntil((route) {
    return route.settings is MaterialPage;
  });
}

class OnboardPageBackground extends StatelessWidget {
  final Widget child;

  const OnboardPageBackground({Key? key, required this.child})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    double _shieldTop = MediaQuery.of(context).padding.top + 6.0;
    double _shieldBottom = MediaQuery.of(context).padding.bottom + 6.0;
    return Stack(
      children: [
        AppBackground(),
        Padding(
          padding: EdgeInsets.only(
              right: 5.0, left: 5.0, top: _shieldTop, bottom: _shieldBottom),
          child: Hero(
            tag: "shield",
            transitionOnUserGestures: true,
            child: Shield(
              child: Padding(
                  padding: const EdgeInsets.only(
                      right: 15, left: 15, top: 15, bottom: 50),
                  child: SizedBox.expand(
                    child: child,
                  )),
            ),
          ),
        )
      ],
    );
  }
}
