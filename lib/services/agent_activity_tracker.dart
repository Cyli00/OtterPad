import 'dart:convert';

import '../data/models/ai/agent_config.dart';
import '../data/models/chat/chat_activity.dart';

class AgentActivityTracker {
  final void Function(ChatActivity)? onActivity;
  final bool requestReasoning;
  final _steps = <String, ChatActivity>{};
  final _blocks = <int, String>{};
  String? _reasoningId;
  int _serial = 0;

  AgentActivityTracker(this.onActivity, {this.requestReasoning = false});

  void _emit(ChatActivity activity) {
    _steps[activity.id] = activity;
    onActivity?.call(activity);
  }

  void reasoning(String text) {
    if (text.isEmpty) return;
    final id = _reasoningId ??= 'reasoning-${_serial++}';
    final previous =
        _steps[id] ??
        ChatActivity(
          id: id,
          kind: ChatActivityKind.reasoning,
          startedAt: DateTime.now(),
        );
    _emit(previous.update(text: previous.text + text));
  }

  void endReasoning() {
    final previous = _steps[_reasoningId];
    if (previous != null) {
      _emit(previous.update(status: ChatActivityStatus.completed));
    }
    _reasoningId = null;
  }

  void tool(String id, String name, String text, {ChatActivityStatus? status}) {
    endReasoning();
    final previous =
        _steps[id] ??
        ChatActivity(
          id: id,
          kind: ChatActivityKind.tool,
          name: name,
          startedAt: DateTime.now(),
        );
    _emit(previous.update(text: text.isEmpty ? null : text, status: status));
  }

  void finish([ChatActivityStatus status = ChatActivityStatus.completed]) {
    for (final step in _steps.values.toList()) {
      if (step.status == ChatActivityStatus.running) {
        _emit(step.update(status: status));
      }
    }
    _reasoningId = null;
  }

  void record(
    AgentApiProvider provider,
    Map<String, dynamic> data, {
    bool streaming = true,
  }) {
    if (onActivity == null) return;
    switch (provider) {
      case AgentApiProvider.openAICompatible:
        final choices = data['choices'];
        if (choices is! List || choices.isEmpty) return;
        final message = choices.first[streaming ? 'delta' : 'message'];
        if (message is! Map) return;
        final thought = message['reasoning_content'] ?? message['reasoning'];
        if (thought is String) reasoning(thought);
        if (message['content'] is String &&
            (message['content'] as String).isNotEmpty) {
          endReasoning();
        }
      case AgentApiProvider.openai:
        final type = data['type'] as String? ?? '';
        if (type == 'response.reasoning_summary_text.delta' ||
            type == 'response.reasoning_text.delta') {
          reasoning(data['delta'] as String? ?? '');
        } else if (type == 'response.output_text.delta') {
          endReasoning();
        } else if (type == 'response.output_item.added' ||
            type == 'response.output_item.done') {
          final item = data['item'];
          if (item is Map) _openAIItem(item, done: type.endsWith('.done'));
        } else if (type.startsWith('response.web_search_call.')) {
          tool(
            data['item_id'] as String? ?? 'web-search',
            'web_search',
            '',
            status: type.endsWith('.completed')
                ? ChatActivityStatus.completed
                : null,
          );
        } else if (!streaming && data['output'] is List) {
          for (final item in data['output']) {
            if (item is Map) {
              _openAIItem(item, done: true, includeReasoning: true);
            }
          }
        } else if (data['choices'] is List) {
          record(AgentApiProvider.openAICompatible, data, streaming: streaming);
        }
      case AgentApiProvider.anthropic:
        final type = data['type'];
        if (type == 'content_block_start') {
          final block = data['content_block'];
          if (block is Map) {
            final id = block['id'];
            if (id is String) _blocks[(data['index'] as num).toInt()] = id;
            _anthropicBlock(block);
          }
        } else if (type == 'content_block_delta') {
          final delta = data['delta'];
          if (delta is! Map) return;
          if (delta['type'] == 'thinking_delta') {
            reasoning(delta['thinking'] as String? ?? '');
          }
          if (delta['type'] == 'text_delta') endReasoning();
          if (delta['type'] == 'input_json_delta') {
            final id = _blocks[data['index']];
            final step = _steps[id];
            if (id != null && step != null) {
              tool(
                id,
                step.name,
                step.text + (delta['partial_json'] as String? ?? ''),
              );
            }
          }
        } else if (!streaming && data['content'] is List) {
          for (final block in data['content']) {
            if (block is Map) _anthropicBlock(block);
          }
        }
      case AgentApiProvider.gemini:
        final candidates = data['candidates'];
        if (candidates is! List || candidates.isEmpty) return;
        final candidate = candidates.first as Map;
        final parts = (candidate['content'] as Map?)?['parts'];
        if (parts is List) {
          for (final part in parts) {
            if (part is! Map) continue;
            if (part['thought'] == true) {
              reasoning(part['text'] as String? ?? '');
            } else if (part['text'] is String) {
              endReasoning();
            }
          }
        }
        final queries =
            (candidate['groundingMetadata'] as Map?)?['webSearchQueries'];
        if (queries is List && queries.isNotEmpty) {
          final sources =
              (candidate['groundingMetadata'] as Map?)?['groundingChunks'];
          tool(
            'gemini-search',
            'web_search',
            [
              queries.join('\n'),
              if (sources is List)
                for (final s in sources)
                  if (s is Map && s['web'] is Map)
                    '${s['web']['title'] ?? ''}\n${s['web']['uri'] ?? ''}',
            ].join('\n\n'),
            status: ChatActivityStatus.completed,
          );
        }
    }
  }

  void _openAIItem(
    Map item, {
    required bool done,
    bool includeReasoning = false,
  }) {
    if (item['type'] == 'reasoning') {
      if (includeReasoning && item['summary'] is List) {
        for (final part in item['summary']) {
          if (part is Map) reasoning(part['text'] as String? ?? '');
        }
      }
      if (done) endReasoning();
    } else if (item['type'] == 'web_search_call') {
      final action = item['action'] as Map?;
      tool(
        item['id'] as String? ?? 'web-search',
        'web_search',
        action == null ? '' : jsonEncode(action),
        status: done ? ChatActivityStatus.completed : null,
      );
    }
  }

  void _anthropicBlock(Map block) {
    final type = block['type'] as String? ?? '';
    if (type == 'thinking') {
      reasoning(block['thinking'] as String? ?? '');
    } else if (type == 'server_tool_use') {
      final input = block['input'];
      tool(
        block['id'] as String,
        block['name'] as String? ?? '',
        input is Map && input.isNotEmpty ? jsonEncode(input) : '',
      );
    } else if (type.endsWith('_tool_result')) {
      final id = block['tool_use_id'] as String?;
      if (id != null) {
        final content = jsonEncode(block['content']);
        tool(
          id,
          _steps[id]?.name ?? type,
          content,
          status: content.contains('tool_result_error')
              ? ChatActivityStatus.failed
              : ChatActivityStatus.completed,
        );
      }
    } else if (type == 'text') {
      endReasoning();
    }
  }
}
