import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'l10n.dart';
import 'paper_widgets.dart';
import 'paper_theme.dart';
import 'paper_surfaces.dart';

const _systemPrompt = '你是一名学术翻译助手。仅输出译文，保留 Markdown 结构、专业术语和公式。';
const _userPrompt = '请将以下内容翻译为 {{targetLanguage}}：\n\n{{text}}';
const _imagePrompt = '基于文献内容生成清晰的概要配图，以准确的结构展示主要发现。避免增加原文未支持的结论。';
const _models = {
  'deepseek/deepseek-v4.1-flash': 'deepseek/deepseek-v4.1-flash',
  'claude-sonnet-4': 'claude-sonnet-4',
  'gpt-4.1': 'gpt-4.1',
};

class AiSettingsDemo extends StatefulWidget {
  const AiSettingsDemo({super.key});
  @override
  State<AiSettingsDemo> createState() => _AiSettingsDemoState();
}

class _AiSettingsDemoState extends State<AiSettingsDemo> {
  String _provider = 'OpenAI Compatible';
  String _model = _models.keys.first;
  String _expert = _models.keys.first;
  String _fast = _models.keys.first;
  String _imageModel = 'gpt-image-1';
  String _search = 'Tavily';
  String _language = 'zh';
  String _style = 'accent';
  final _ignored = <String>{'references'};
  double _temperature = 0;
  double _references = 10;
  String _ratio = '3:2';
  String _quality = 'auto';
  bool _obscured = true;
  bool _searchObscured = true;
  final _key = TextEditingController();
  final _endpoint = TextEditingController(text: 'https://api.example.com/v1');
  final _searchKey = TextEditingController();
  final _system = TextEditingController(text: _systemPrompt);
  final _user = TextEditingController(text: _userPrompt);
  final _image = TextEditingController(text: _imagePrompt);
  final _providerDrafts = <String, (String, String)>{};
  final _searchDrafts = <String, String>{};
  Map<String, String> _availableModels = {..._models};
  bool _fetching = false;
  bool _fetched = false;
  bool _fetchError = false;
  int _requestId = 0;

  bool get _validEndpoint =>
      Uri.tryParse(_endpoint.text)?.hasAuthority == true &&
      _endpoint.text.startsWith('https://');

  void _invalidateFetch() {
    _requestId++;
    _fetching = false;
    _fetched = false;
    _fetchError = false;
  }

  Future<void> _fetchModels() async {
    if (_fetching) return;
    if (!_validEndpoint) {
      setState(() => _fetchError = true);
      return;
    }
    final request = ++_requestId;
    setState(() {
      _fetching = true;
      _fetched = false;
      _fetchError = false;
    });
    // 仅模拟本地目录加载；切换服务商或修改连接信息后丢弃旧结果。
    await Future<void>.delayed(const Duration(milliseconds: 750));
    if (!mounted || request != _requestId) return;
    setState(() {
      _availableModels = {
        ..._models,
        'demo/research-model': 'demo/research-model',
      };
      _fetching = false;
      _fetched = true;
    });
  }

  @override
  void dispose() {
    for (final c in [_key, _endpoint, _searchKey, _system, _user, _image]) {
      c.dispose();
    }
    super.dispose();
  }

  void _changeProvider(String value) => setState(() {
    _providerDrafts[_provider] = (_key.text, _endpoint.text);
    _provider = value;
    final draft = _providerDrafts[value];
    _key.text = draft?.$1 ?? '';
    _endpoint.text = draft?.$2 ?? 'https://api.example.com/v1';
    _obscured = true;
    _invalidateFetch();
    _availableModels = {..._models};
    if (!_availableModels.containsKey(_model)) _model = _models.keys.first;
    if (_expert.isNotEmpty && !_availableModels.containsKey(_expert))
      _expert = '';
    if (_fast.isNotEmpty && !_availableModels.containsKey(_fast)) _fast = '';
  });

  bool get _validUserPrompt =>
      _user.text.trim().isEmpty ||
      (_user.text.contains('{{text}}') &&
          _user.text.contains('{{targetLanguage}}'));

  List<String> _modelBadges(String model, AppLocalizations l) {
    if (model == _models.keys.first) return [l.tools, l.reasoning];
    if (model.startsWith('demo/')) return [];
    return [l.vision, l.tools];
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget field(
      TextEditingController controller,
      String label, {
      String? error,
      bool password = false,
      bool search = false,
    }) => TextField(
      key: ValueKey(
        search
            ? 'search-key'
            : password
            ? 'api-key'
            : 'endpoint',
      ),
      controller: controller,
      obscureText: password && (search ? _searchObscured : _obscured),
      autocorrect: false,
      enableSuggestions: !password,
      style: text.bodyLarge,
      onChanged: (_) => setState(() {
        if (!search) _invalidateFetch();
      }),
      decoration: InputDecoration(
        hintText: password ? l.keyPlaceholder : null,
        semanticCounterText: label,
        errorText: error,
        suffixIcon: password
            ? IconButton(
                tooltip: (search ? _searchObscured : _obscured)
                    ? l.showKey
                    : l.hideKey,
                onPressed: () => setState(() {
                  if (search) {
                    _searchObscured = !_searchObscured;
                  } else {
                    _obscured = !_obscured;
                  }
                }),
                icon: Icon(
                  (search ? _searchObscured : _obscured)
                      ? Symbols.visibility_off
                      : Symbols.visibility,
                ),
              )
            : null,
      ),
    );
    Widget role(
      String label,
      String hint,
      PaperModelRole identity,
      String value,
      ValueChanged<String> change, {
      bool image = false,
    }) => PaperRoleCard(
      role: identity,
      title: label,
      help: hint,
      value: value,
      options: {
        '': l.clear,
        if (image) 'gpt-image-1': 'gpt-image-1' else ..._availableModels,
      },
      onChanged: change,
    );
    final getApiKey = IconButton(
      key: const ValueKey('get-api-key'),
      tooltip: l.getApiKey,
      onPressed: () => paperSnack(context, l.apiKeyActionMessage),
      icon: const Icon(Symbols.key),
    );
    final fetchModels = IconButton(
      key: const ValueKey('fetch-models'),
      tooltip: _fetchError
          ? l.retryModels
          : _fetching
          ? l.fetchingModels
          : l.fetchModels,
      onPressed: _fetching ? null : _fetchModels,
      icon: _fetching
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 1.5),
            )
          : const Icon(Symbols.refresh),
    );
    final modelCards = [
      for (final entry in _availableModels.entries)
        PaperModelCard(
          model: entry.value,
          selected: _model == entry.key,
          badges: _modelBadges(entry.key, l),
          onSelected: (value) => setState(() => _model = value),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: spaced([
        PaperSection(
          title: l.modelApi,
          help: l.modelApiHelp,
          action: getApiKey,
          children: [
            PaperFieldRow(
              label: l.provider,
              hint: l.providerHint,
              child: PaperSelect(
                label: l.provider,
                value: _provider,
                options: const {
                  'OpenAI Compatible': 'OpenAI Compatible',
                  'OpenAI': 'OpenAI',
                  'Anthropic': 'Anthropic',
                  'Gemini': 'Gemini',
                },
                onChanged: _changeProvider,
              ),
            ),
            PaperFieldRow(
              label: l.apiKey,
              hint: l.keyHint,
              child: Semantics(
                label: l.apiKey,
                child: field(_key, l.apiKey, password: true),
              ),
            ),
            PaperFieldRow(
              label: l.endpoint,
              hint: l.endpointHint,
              child: Semantics(
                label: l.endpoint,
                child: field(
                  _endpoint,
                  l.endpoint,
                  error: _endpoint.text.isNotEmpty && !_validEndpoint
                      ? l.endpointError
                      : null,
                ),
              ),
            ),
            PaperSubsection(
              title: l.models,
              help: l.modelHint,
              action: fetchModels,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: spaced(modelCards, 10),
                ),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _fetchError
                        ? l.fetchModelsError
                        : _fetching
                        ? l.fetchingModels
                        : _fetched
                        ? l.modelsFetched(_availableModels.length)
                        : l.modelsDemoHint,
                    key: const ValueKey('fetch-models-status'),
                    style: text.bodySmall?.copyWith(
                      color: _fetchError ? cs.error : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            PaperSubsection(
              title: l.roles,
              children: [
                PaperRoleGroup(
                  children: [
                    role(
                      l.expert,
                      l.expertHint,
                      PaperModelRole.expert,
                      _expert,
                      (v) => setState(() => _expert = v),
                    ),
                    role(
                      l.fast,
                      l.fastHint,
                      PaperModelRole.fast,
                      _fast,
                      (v) => setState(() => _fast = v),
                    ),
                    role(
                      l.imageModel,
                      l.imageModelHint,
                      PaperModelRole.image,
                      _imageModel,
                      (v) => setState(() => _imageModel = v),
                      image: true,
                    ),
                  ],
                ),
              ],
            ),
            PaperSubsection(
              title: l.search,
              children: [
                PaperFieldRow(
                  label: l.provider,
                  hint: l.searchHint,
                  child: PaperSelect(
                    label: l.search,
                    value: _search,
                    options: const {
                      'Tavily': 'Tavily',
                      'Exa': 'Exa',
                      'Brave': 'Brave',
                    },
                    onChanged: (v) => setState(() {
                      _searchDrafts[_search] = _searchKey.text;
                      _search = v;
                      _searchKey.text = _searchDrafts[v] ?? '';
                      _searchObscured = true;
                    }),
                  ),
                ),
                PaperFieldRow(
                  label: l.apiKey,
                  child: Semantics(
                    label: l.searchKey,
                    child: field(
                      _searchKey,
                      l.searchKey,
                      password: true,
                      search: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        PaperSection(
          title: l.translation,
          help: l.translationHelp,
          children: [
            PaperFieldRow(
              label: l.targetLanguage,
              child: PaperSelect(
                label: l.targetLanguage,
                value: _language,
                options: {
                  'zh': l.simplifiedChinese,
                  'en': l.english,
                  'ja': l.japanese,
                  'ko': l.korean,
                  'fr': l.french,
                  'de': l.german,
                },
                onChanged: (v) => setState(() => _language = v),
              ),
            ),
            _choiceBlock(
              l.styles,
              {
                'normal': l.normal,
                'accent': l.accent,
                'bold': l.bold,
                'italic': l.italic,
                'muted': l.muted,
                'underline': l.underline,
                'background': l.background,
                'blur': l.blur,
                'quote': l.quote,
              },
              selected: {_style},
              help: l.styleHint,
              onTap: (v) => setState(() => _style = v),
              preview: true,
            ),
            _choiceBlock(
              l.ignore,
              {
                'references': l.references,
                'acknowledgments': l.acknowledgments,
                'contributions': l.contributions,
                'funding': l.funding,
                'supplement': l.supplement,
                'ethics': l.ethics,
              },
              selected: _ignored,
              help: l.ignoreHint,
              onTap: (v) => setState(() {
                if (!_ignored.add(v)) _ignored.remove(v);
              }),
            ),
            PaperSlider(
              title: l.temperature,
              help: l.temperatureHelp,
              value: _temperature,
              min: 0,
              max: 2,
              divisions: 40,
              resetLabel: l.resetTemperature,
              onChanged: (v) => setState(() => _temperature = v),
              onReset: _temperature == 0
                  ? null
                  : () => setState(() => _temperature = 0),
            ),
            _prompt(l.systemPrompt, l.promptHint, _system, _systemPrompt),
            _prompt(
              l.userPrompt,
              l.promptHint,
              _user,
              _userPrompt,
              error: _validUserPrompt ? null : l.promptError,
            ),
          ],
        ),
        PaperSection(
          title: l.imageSettings,
          help: l.imageHelp,
          children: [
            PaperFieldRow(
              label: l.aspectRatio,
              hint: l.aspectHint,
              child: PaperSelect(
                label: l.aspectRatio,
                value: _ratio,
                options: const {
                  '1:1': '1:1',
                  '4:3': '4:3',
                  '3:2': '3:2',
                  '16:9': '16:9',
                  '21:9': '21:9',
                  '9:16': '9:16',
                },
                onChanged: (v) => setState(() => _ratio = v),
              ),
            ),
            PaperOptions(
              label: l.quality,
              value: _quality,
              options: {'auto': l.auto, 'standard': l.standard, 'high': l.high},
              onChanged: (v) => setState(() => _quality = v),
            ),
            PaperSlider(
              title: l.referenceImages,
              help: l.referenceImagesHelp,
              value: _references,
              min: 1,
              max: 10,
              divisions: 9,
              decimals: 0,
              resetLabel: l.resetReferences,
              onChanged: (v) => setState(() => _references = v),
              onReset: _references == 10
                  ? null
                  : () => setState(() => _references = 10),
            ),
            _prompt(l.imagePrompt, l.imagePromptHint, _image, _imagePrompt),
          ],
        ),
      ], PaperMetrics.groupGap),
    );
  }

  Widget _choiceBlock(
    String title,
    Map<String, String> options, {
    required Set<String> selected,
    required String help,
    required ValueChanged<String> onTap,
    bool preview = false,
  }) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget label(String id, String name) {
      final style = text.labelMedium?.copyWith(
        fontWeight: id == 'bold' ? FontWeight.w700 : FontWeight.w400,
        fontStyle: id == 'italic' ? FontStyle.italic : FontStyle.normal,
        color: id == 'muted'
            ? cs.onSurfaceVariant
            : id == 'accent'
            ? cs.primary
            : cs.onSurface,
        decoration: id == 'underline' ? TextDecoration.underline : null,
        decorationStyle: id == 'underline' ? TextDecorationStyle.dashed : null,
        backgroundColor: id == 'background' ? cs.surfaceContainerHighest : null,
      );
      Widget child = Text(name, style: style);
      if (id == 'blur')
        child = ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
          child: child,
        );
      if (id == 'quote')
        child = Container(
          padding: const EdgeInsets.only(left: 8),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: cs.primary, width: 2)),
          ),
          child: child,
        );
      return child;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PaperLabel(title: title, help: help),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final v in options.entries)
              PaperChoice(
                label: v.value,
                selected: selected.contains(v.key),
                multiple: !preview,
                preview: preview ? label(v.key, v.value) : null,
                onSelected: (_) => onTap(v.key),
              ),
          ],
        ),
      ],
    );
  }

  Widget _prompt(
    String title,
    String hint,
    TextEditingController controller,
    String initial, {
    String? error,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: PaperLabel(title: title, help: hint),
            ),
            IconButton(
              tooltip: context.l10n.resetPrompt,
              onPressed: controller.text == initial
                  ? null
                  : () => setState(() => controller.text = initial),
              icon: const Icon(Symbols.restart_alt),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Semantics(
          label: title,
          child: TextField(
            key: ValueKey(
              identical(controller, _user)
                  ? 'user-prompt'
                  : identical(controller, _system)
                  ? 'system-prompt'
                  : 'image-prompt',
            ),
            controller: controller,
            minLines: 4,
            maxLines: 8,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              errorText: error,
              errorMaxLines: 4,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
