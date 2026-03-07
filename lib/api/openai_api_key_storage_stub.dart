String? _volatileApiKey;

Future<String?> loadStoredOpenAiApiKey() async => _volatileApiKey;

Future<void> saveStoredOpenAiApiKey(String key) async {
  _volatileApiKey = key;
}

Future<void> clearStoredOpenAiApiKey() async {
  _volatileApiKey = null;
}
