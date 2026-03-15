String? _volatileApiKey;
String? _volatileTogetherApiKey;

Future<String?> loadStoredOpenAiApiKey() async => _volatileApiKey;

Future<void> saveStoredOpenAiApiKey(String key) async {
  _volatileApiKey = key;
}

Future<void> clearStoredOpenAiApiKey() async {
  _volatileApiKey = null;
}

Future<String?> loadStoredTogetherApiKey() async => _volatileTogetherApiKey;

Future<void> saveStoredTogetherApiKey(String key) async {
  _volatileTogetherApiKey = key;
}

Future<void> clearStoredTogetherApiKey() async {
  _volatileTogetherApiKey = null;
}
