import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/design_tokens.dart';
import '../../core/l10n.dart';
import '../../src/rust/error.dart';

/// 启动阶段的状态：迁移进度，或无法打开数据时的错误码。
@immutable
class StartupStatus {
  const StartupStatus({this.done = 0, this.total = 0, this.failure});

  final int done;
  final int total;
  final ErrorCode? failure;
}

/// 主应用之前的占位界面：只在迁移 0.1.x 数据或打开数据失败时显示。
class StartupApp extends StatelessWidget {
  const StartupApp(this.status, {super.key});

  final ValueListenable<StartupStatus> status;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      theme: buildAppTheme(FolioPalette.scheme(Colors.blue, Brightness.light)),
      darkTheme: buildAppTheme(
        FolioPalette.scheme(Colors.blue, Brightness.dark),
      ),
      home: ValueListenableBuilder<StartupStatus>(
        valueListenable: status,
        builder: (context, status, _) {
          final textTheme = Theme.of(context).textTheme;
          final failure = status.failure;
          return Scaffold(
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: failure != null
                    ? Text(
                        context.l10n.dataStartFailed(failure.name),
                        textAlign: TextAlign.center,
                        style: textTheme.bodyLarge,
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LinearProgressIndicator(
                            value: status.total == 0
                                ? null
                                : status.done / status.total,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            context.l10n.migratingData(
                              status.done,
                              status.total,
                            ),
                            style: textTheme.bodyMedium,
                          ),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
