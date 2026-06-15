// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

class ModelTestState {
  final Map<String, String?> results;
  final Set<String> testing;
  const ModelTestState({this.results = const {}, this.testing = const {}});
}

class ModelTestNotifier extends StateNotifier<ModelTestState> {
  ModelTestNotifier() : super(const ModelTestState());

  void startTest(String modelId) {
    state = ModelTestState(
      results: {...state.results}..remove(modelId),
      testing: {...state.testing, modelId},
    );
  }

  void finishTest(String modelId, String? error) {
    state = ModelTestState(
      results: {...state.results, modelId: error},
      testing: {...state.testing}..remove(modelId),
    );
  }

  void clearResult(String modelId) {
    if (!state.results.containsKey(modelId)) return;
    state = ModelTestState(
      results: {...state.results}..remove(modelId),
      testing: state.testing,
    );
  }

  void clearAll() {
    if (state.results.isEmpty && state.testing.isEmpty) return;
    state = const ModelTestState();
  }
}

final modelTestProvider =
    StateNotifierProvider<ModelTestNotifier, ModelTestState>(
      (ref) => ModelTestNotifier(),
    );
