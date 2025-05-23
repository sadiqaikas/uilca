import 'dart:convert';
import 'package:http/http.dart' as http;
import '../prompt/system_prompt.dart';
import 'api_key_delete_later.dart';

// Use your secure OpenAI API key (ensure you don't hardcode it in production)

Future<Map<String, dynamic>?> runLCARequest(String userPrompt) async {
  final uri = Uri.parse('https://api.openai.com/v1/chat/completions');

  try {
    final response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $openAIApiKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        "model": "gpt-4-turbo-preview", // Use an advanced reasoning model with high token capacity
        "temperature": 0.2,
        "max_tokens": 4000, // Allow for detailed, in-depth responses
        "messages": [
          {
            "role": "system",
            "content": system_prompt, // This prompt should be highly detailed per our latest specifications
          },
          {
            "role": "user",
            "content": userPrompt,
          }
        ],
        // Optionally, you can supply additional parameters like "stop": ["\n\n"]
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      // Expect the message content to be valid JSON only
      final content = data['choices'][0]['message']['content'];
      
      try {
        final parsedJson = jsonDecode(content);
        print("✅ JSON successfully parsed:");
        print(JsonEncoder.withIndent('  ').convert(parsedJson));
        return parsedJson;
      } catch (e) {
        print("⚠️ GPT response was not valid JSON. Response content:");
        print(content);
        return null;
      }
    } else {
      print("❌ OpenAI API Error: ${response.statusCode}");
      print(response.body);
      return null;
    }
  } catch (e) {
    print("❌ Request Failed: $e");
    return null;
  }
}
