// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

const _openAiStorageKey = 'earlylca.openai_api_key';
const _togetherStorageKey = 'earlylca.together_api_key';

Future<String?> loadStoredOpenAiApiKey() async {
  final raw = html.window.localStorage[_openAiStorageKey];
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

Future<void> saveStoredOpenAiApiKey(String key) async {
  html.window.localStorage[_openAiStorageKey] = key;
}

Future<void> clearStoredOpenAiApiKey() async {
  html.window.localStorage.remove(_openAiStorageKey);
}

Future<String?> loadStoredTogetherApiKey() async {
  final raw = html.window.localStorage[_togetherStorageKey];
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

Future<void> saveStoredTogetherApiKey(String key) async {
  html.window.localStorage[_togetherStorageKey] = key;
}

Future<void> clearStoredTogetherApiKey() async {
  html.window.localStorage.remove(_togetherStorageKey);
}
