import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'design_tokens.dart';

const appSliderTheme = SliderThemeData(
  thumbShape: RoundSliderThumbShape(enabledThumbRadius: 7, elevation: 0),
  overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
  trackHeight: 2,
);

/// 全局主题：Folio 设计语言落在 Material 组件上的唯一入口。
///
/// 组件不再各自写圆角、底色和阴影；需要例外时取 `design_tokens.dart`。
ThemeData buildAppTheme(
  ColorScheme colorScheme, {
  String? fontFamily,
  List<String>? fontFamilyFallback,
}) {
  final cs = colorScheme;
  final text = AppType.editorial(
    ThemeData(
      colorScheme: cs,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    ).textTheme,
    defaultTargetPlatform,
  );
  final rule = AppStroke.side(cs);
  final smShape = RoundedRectangleBorder(borderRadius: AppRadius.smAll);
  final mdShape = RoundedRectangleBorder(borderRadius: AppRadius.mdAll);
  final floatShadow = cs.shadow.withAlpha(
    cs.brightness == Brightness.light ? 46 : 140,
  );
  const buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 10);
  const buttonSize = Size(64, 40);

  OutlineInputBorder field(BorderSide side) =>
      OutlineInputBorder(borderRadius: AppRadius.smAll, borderSide: side);

  return ThemeData(
    colorScheme: cs,
    useMaterial3: true,
    fontFamily: fontFamily,
    fontFamilyFallback: fontFamilyFallback,
    textTheme: text,
    scaffoldBackgroundColor: cs.surface,
    canvasColor: cs.surface,
    dividerColor: cs.outlineVariant,
    dividerTheme: DividerThemeData(
      color: cs.outlineVariant,
      thickness: AppStroke.hairline,
      space: AppStroke.hairline,
    ),
    appBarTheme: AppBarThemeData(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: AppSpace.x4,
      titleTextStyle: text.titleLarge?.copyWith(color: cs.onSurface),
    ),
    cardTheme: CardThemeData(
      color: cs.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: rule),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cs.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll, side: rule),
      titleTextStyle: text.headlineSmall?.copyWith(color: cs.onSurface),
      contentTextStyle: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cs.surfaceContainerLowest,
      modalBackgroundColor: cs.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheetTop),
      dragHandleColor: cs.outline,
      dragHandleSize: const Size(28, 3),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: smShape,
        padding: buttonPadding,
        minimumSize: buttonSize,
        textStyle: text.labelLarge,
        elevation: 0,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        shape: smShape,
        padding: buttonPadding,
        minimumSize: buttonSize,
        textStyle: text.labelLarge,
        elevation: 0,
        backgroundColor: cs.surfaceContainerLowest,
        foregroundColor: cs.onSurface,
        side: rule,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: smShape,
        padding: buttonPadding,
        minimumSize: buttonSize,
        textStyle: text.labelLarge,
        foregroundColor: cs.onSurface,
        side: BorderSide(color: cs.outline.withAlpha(120)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: smShape,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: const Size(48, 40),
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(shape: smShape),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: cs.inverseSurface,
      foregroundColor: cs.onInverseSurface,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: mdShape,
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: cs.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      hintStyle: text.bodyMedium?.copyWith(
        color: cs.onSurfaceVariant.withAlpha(150),
      ),
      border: field(rule),
      enabledBorder: field(rule),
      disabledBorder: field(BorderSide(color: cs.outlineVariant.withAlpha(90))),
      focusedBorder: field(
        BorderSide(color: cs.primary, width: AppStroke.emphasis),
      ),
      errorBorder: field(BorderSide(color: cs.error)),
      focusedErrorBorder: field(
        BorderSide(color: cs.error, width: AppStroke.emphasis),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: smShape,
      side: rule,
      backgroundColor: cs.surfaceContainerLowest,
      selectedColor: cs.primaryContainer,
      labelStyle: text.labelLarge?.copyWith(color: cs.onSurface),
      showCheckmark: false,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        shape: smShape,
        side: rule,
        backgroundColor: cs.surfaceContainerLowest,
        selectedBackgroundColor: cs.inverseSurface,
        selectedForegroundColor: cs.onInverseSurface,
        foregroundColor: cs.onSurfaceVariant,
        textStyle: text.labelLarge,
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Colors.transparent
            : cs.outline.withAlpha(140),
      ),
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? cs.onPrimary : cs.outline,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? cs.primary
            : cs.surfaceContainerLowest,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.xsAll),
      side: BorderSide(color: cs.outline, width: AppStroke.emphasis),
    ),
    sliderTheme: appSliderTheme.copyWith(
      activeTrackColor: cs.primary,
      inactiveTrackColor: cs.outlineVariant,
      thumbColor: cs.primary,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: cs.primary,
      linearTrackColor: cs.outlineVariant,
      circularTrackColor: Colors.transparent,
      linearMinHeight: 2,
      borderRadius: BorderRadius.circular(AppRadius.hairline),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: cs.onSurface,
      unselectedLabelColor: cs.onSurfaceVariant,
      labelStyle: text.titleSmall,
      unselectedLabelStyle: text.titleSmall?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      indicatorSize: TabBarIndicatorSize.label,
      indicator: UnderlineTabIndicator(
        borderSide: BorderSide(color: cs.onSurface, width: AppStroke.focus),
      ),
      dividerColor: cs.outlineVariant,
      dividerHeight: AppStroke.hairline,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 64,
      indicatorColor: Colors.transparent,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 22,
          color: s.contains(WidgetState.selected)
              ? cs.onSurface
              : cs.onSurfaceVariant.withAlpha(170),
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelSmall?.copyWith(
          letterSpacing: 0.4,
          color: s.contains(WidgetState.selected)
              ? cs.onSurface
              : cs.onSurfaceVariant.withAlpha(170),
        ),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(cs.surfaceContainerLowest),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        shadowColor: WidgetStatePropertyAll(floatShadow),
        side: WidgetStatePropertyAll(rule),
        shape: WidgetStatePropertyAll(mdShape),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(AppSpace.x1)),
      ),
    ),
    menuButtonTheme: MenuButtonThemeData(
      style: MenuItemButton.styleFrom(
        shape: smShape,
        minimumSize: const Size(160, 36),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.x3),
        textStyle: text.bodyMedium,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: cs.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      shadowColor: floatShadow,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: rule),
      textStyle: text.bodyMedium,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: AppRadius.xsAll,
      ),
      textStyle: text.labelMedium?.copyWith(color: cs.onInverseSurface),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      waitDuration: const Duration(milliseconds: 400),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: cs.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(color: cs.onInverseSurface),
      actionTextColor: cs.inversePrimary,
      elevation: 0,
      shape: mdShape,
      behavior: SnackBarBehavior.floating,
    ),
    listTileTheme: ListTileThemeData(
      shape: smShape,
      iconColor: cs.onSurfaceVariant,
    ),
    badgeTheme: BadgeThemeData(
      backgroundColor: cs.primary,
      textColor: cs.onPrimary,
      textStyle: text.labelSmall?.copyWith(
        letterSpacing: 0,
        fontFeatures: AppType.tabular,
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      radius: const Radius.circular(AppRadius.hairline),
      thickness: const WidgetStatePropertyAll(4),
      thumbColor: WidgetStatePropertyAll(cs.onSurface.withAlpha(60)),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      },
    ),
  );
}
