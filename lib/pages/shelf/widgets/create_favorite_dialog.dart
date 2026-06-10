import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/animation_constants.dart';
import '../../../core/l10n.dart';
import '../../../services/haptics.dart';
import '../../../widgets/app_dialog.dart';
import '../../../widgets/tactile_press.dart';

// 常用 emoji 列表，按类别分组
const List<String> _emojis = [
  // 书籍与学习
  '\u{1F4DA}', '\u{1F4D6}', '\u{1F4D8}', '\u{1F4D5}', '\u{1F4D7}', '\u{1F4D9}',
  '\u{1F4D3}', '\u{1F4DD}', '\u{270F}\u{FE0F}', '\u{1F58A}\u{FE0F}',
  '\u{1F393}', '\u{1F3EB}',
  // 科学与工具
  '\u{1F52C}', '\u{1F52D}', '\u{1F9EA}', '\u{1F4BB}', '\u{2699}\u{FE0F}', '\u{1F4CE}',
  '\u{1F4C1}', '\u{1F4C2}', '\u{1F5C2}\u{FE0F}', '\u{1F4CB}',
  '\u{1F4CA}', '\u{1F4C8}',
  // 自然与灵感
  '\u{2B50}', '\u{1F31F}', '\u{1F525}', '\u{1F4A1}', '\u{2764}\u{FE0F}', '\u{1F308}',
  '\u{1F33F}', '\u{1F33B}', '\u{1F340}', '\u{1F30D}',
  '\u{2600}\u{FE0F}', '\u{1F319}',
  // 标记与符号
  '\u{1F3AF}', '\u{1F680}', '\u{1F48E}', '\u{1F3C6}', '\u{1F381}', '\u{1F9E9}',
  '\u{2705}', '\u{1F4CC}', '\u{1F516}', '\u{1F3F7}\u{FE0F}',
  '\u{1F4AC}', '\u{1F4AD}',
];

/// 创建收藏夹对话框
///
/// 返回一个 Map，包含 'emoji' 和 'name' 字段；
/// 用户取消则返回 null。
Future<Map<String, String>?> showCreateFavoriteDialog(
  BuildContext context, {
  String? initialEmoji,
  String? initialName,
}) {
  final isEditing = initialName != null;
  return showAppDialog<Map<String, String>>(
    context: context,
    barrierLabel: context.l10n.close,
    builder: (_) => _CreateFavoriteContent(
      initialEmoji: initialEmoji,
      initialName: isEditing ? initialName : null,
    ),
  );
}

class _CreateFavoriteContent extends StatefulWidget {
  final String? initialEmoji;
  final String? initialName;

  const _CreateFavoriteContent({this.initialEmoji, this.initialName});

  @override
  State<_CreateFavoriteContent> createState() => _CreateFavoriteContentState();
}

class _CreateFavoriteContentState extends State<_CreateFavoriteContent> {
  late String _selectedEmoji;
  late final TextEditingController _nameController;
  final _focusNode = FocusNode();

  bool get _isEditing => widget.initialName != null;

  @override
  void initState() {
    super.initState();
    _selectedEmoji = widget.initialEmoji ?? _emojis[0];
    _nameController = TextEditingController(text: widget.initialName ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onConfirm() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop({
      'emoji': _selectedEmoji,
      'name': name,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = (screenWidth * 0.85).clamp(320.0, 480.0);

    return Material(
      color: Colors.transparent,
      child: Container(
        width: dialogWidth,
        constraints: const BoxConstraints(maxHeight: 420),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(40),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
              child: Row(
                children: [
                  Text(
                    _isEditing ? context.l10n.editFavorite : context.l10n.createFavorite,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () {
                      Haptics.soft();
                      Navigator.of(context).pop();
                    },
                    icon: Icon(
                      Symbols.close_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor:
                          colorScheme.surfaceContainerHighest,
                      shape: const CircleBorder(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 主体内容：emoji + 输入框
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 左侧 Emoji 选择器
                    SizedBox(
                      width: 160,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.selectIcon,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Emoji 网格
                          Flexible(
                            child: Container(
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: GridView.builder(
                                  padding: const EdgeInsets.all(8),
                                  shrinkWrap: true,
                                  gridDelegate:
                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 4,
                                    mainAxisSpacing: 4,
                                    crossAxisSpacing: 4,
                                  ),
                                  itemCount: _emojis.length,
                                  itemBuilder: (context, index) {
                                    final emoji = _emojis[index];
                                    final isSelected =
                                        emoji == _selectedEmoji;
                                    return AnimatedContainer(
                                      duration: kAnim,
                                      curve: kAnimCurve,
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? colorScheme.primaryContainer
                                            : Colors.transparent,
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: TactilePress(
                                        baseColor: Colors.transparent,
                                        onTap: () {
                                          setState(() {
                                            _selectedEmoji = emoji;
                                          });
                                        },
                                        child: Center(
                                          child: Text(
                                            emoji,
                                            style: const TextStyle(
                                              fontSize: 20,
                                              height: 1.0,
                                            ),
                                            strutStyle: const StrutStyle(
                                              forceStrutHeight: true,
                                              height: 1.0,
                                            ),
                                          )
                                              .animate(
                                                  target:
                                                      isSelected ? 1 : 0)
                                              .scaleXY(
                                                begin: 1,
                                                end: 1.15,
                                                duration: kAnimFast,
                                                curve: Curves.easeOutBack,
                                              ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 16),

                    // 右侧输入区域
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.favoriteName,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // 预览
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              children: [
                                // Emoji 预览
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius:
                                        BorderRadius.circular(16),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    _selectedEmoji,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // 名称预览
                                Text(
                                  _nameController.text.isEmpty
                                      ? context.l10n.unnamed
                                      : _nameController.text,
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: _nameController.text.isEmpty
                                        ? colorScheme.onSurfaceVariant
                                            .withAlpha(128)
                                        : colorScheme.onSurface,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 输入框
                          TextField(
                            controller: _nameController,
                            focusNode: _focusNode,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _onConfirm(),
                            maxLength: 20,
                            decoration: InputDecoration(
                              hintText: context.l10n.enterFavoriteName,
                              counterText: '',
                              filled: true,
                              fillColor:
                                  colorScheme.surfaceContainerLow,
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: colorScheme.primary,
                                  width: 2,
                                ),
                              ),
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 底部按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      Haptics.soft();
                      Navigator.of(context).pop();
                    },
                    child: Text(context.l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed:
                        _nameController.text.trim().isEmpty
                            ? null
                            : () {
                                Haptics.soft();
                                _onConfirm();
                              },
                    child: Text(_isEditing ? context.l10n.save : context.l10n.create),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
