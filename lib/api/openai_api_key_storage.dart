import 'openai_api_key_storage_stub.dart'
    if (dart.library.html) 'openai_api_key_storage_web.dart' as key_storage;

Future<String?> loadStoredOpenAiApiKey() =>
    key_storage.loadStoredOpenAiApiKey();

Future<void> saveStoredOpenAiApiKey(String key) =>
    key_storage.saveStoredOpenAiApiKey(key);

Future<void> clearStoredOpenAiApiKey() => key_storage.clearStoredOpenAiApiKey();

Future<String?> loadStoredTogetherApiKey() =>
    key_storage.loadStoredTogetherApiKey();

Future<void> saveStoredTogetherApiKey(String key) =>
    key_storage.saveStoredTogetherApiKey(key);

Future<void> clearStoredTogetherApiKey() =>
    key_storage.clearStoredTogetherApiKey();
