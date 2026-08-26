import 'package:flutter/widgets.dart';

class OpenLibrarySearchIntent extends Intent {
  const OpenLibrarySearchIntent();
}

class ImportPdfIntent extends Intent {
  const ImportPdfIntent();
}

class ImportByIdentifierIntent extends Intent {
  const ImportByIdentifierIntent();
}

class OpenSettingsIntent extends Intent {
  const OpenSettingsIntent();
}

class ExitSelectionIntent extends Intent {
  const ExitSelectionIntent();
}

class SelectAllIntent extends Intent {
  const SelectAllIntent();
}

class DeleteSelectedIntent extends Intent {
  const DeleteSelectedIntent();
}

class DismissOverlayIntent extends Intent {
  const DismissOverlayIntent();
}

class ReaderToggleOutlineIntent extends Intent {
  const ReaderToggleOutlineIntent();
}

class ReaderToggleNotesIntent extends Intent {
  const ReaderToggleNotesIntent();
}

class ReaderToggleAskAiIntent extends Intent {
  const ReaderToggleAskAiIntent();
}

class ReaderTranslateIntent extends Intent {
  const ReaderTranslateIntent();
}

class ReaderFindIntent extends Intent {
  const ReaderFindIntent();
}

/// [isEnabled] 为 false 时不消费按键，交给输入框等下层处理。
class EnabledCallbackAction<T extends Intent> extends Action<T> {
  EnabledCallbackAction({required this.onInvoke, this.enabled});

  final bool Function()? enabled;
  final Object? Function(T intent) onInvoke;

  @override
  bool isEnabled(covariant T intent) => enabled?.call() ?? true;

  @override
  bool consumesKey(covariant T intent) => isEnabled(intent);

  @override
  Object? invoke(covariant T intent) => onInvoke(intent);
}

bool isEditingText() =>
    FocusManager.instance.primaryFocus?.context
        ?.findAncestorStateOfType<EditableTextState>() !=
    null;
