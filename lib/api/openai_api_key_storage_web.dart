// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

const _storageKey = 'earlylca.openai_api_key';

Future<String?> loadStoredOpenAiApiKey() async {
  final raw = html.window.localStorage[_storageKey];
  if (raw == null) return null;
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

Future<void> saveStoredOpenAiApiKey(String key) async {
  html.window.localStorage[_storageKey] = key;
}

Future<void> clearStoredOpenAiApiKey() async {
  html.window.localStorage.remove(_storageKey);
}
