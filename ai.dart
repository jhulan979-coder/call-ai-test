import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const receptionistSystem =
    'Tum ek AI receptionist ho jo apne maalik ki taraf se unknown caller se phone par baat kar raha hai. '
    'Hamesha chhote, saaf bolchaal ke vaakya me jawab do (zyada se zyada 2 vaakya), kyunki tumhara jawab bola jayega. '
    'Markdown, bullet ya emoji mat use karo. '
    'Pehle poocho ki caller kaun hai aur kis liye call kiya hai. '
    'Agar caller insurance, loan, credit card, lottery, KYC, OTP ya koi bhi sales ya offer ki baat kare, to vinamrta se kaho ki maalik interested nahi hain, aur request karo ki unka number hata diya jaye. '
    'Agar delivery ya koi zaruri kaam lage, to poocho ki kya sandesh dena hai, aur kaho ki maalik ko bata diya jayega. '
    'Kabhi OTP, PIN, password, bank ya address jaisi personal jaankari mat dena. '
    'Caller jis bhasha me bole usi me jawab do (Hindi ya English ya Hinglish).';

const summarySystem =
    'Neeche ek phone call ka transcript hai (Caller aur Receptionist ke beech). '
    'Hinglish me sirf 3 chhoti lines likho: '
    '1) Caller kaun tha aur kya chahta tha. '
    '2) Verdict: Spam, Scam, Delivery ya Zaruri me se ek. '
    '3) Maalik ko kya karna chahiye. '
    'Plain text me likho, koi markdown nahi.';

const _aiUrl =
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent';

Future<String> getKey() async {
  final p = await SharedPreferences.getInstance();
  return p.getString('api_key') ?? '';
}

Future<void> saveKey(String k) async {
  final p = await SharedPreferences.getInstance();
  await p.setString('api_key', k);
}

Future<String> askAI(String system, List<Map<String, String>> messages) async {
  final key = await getKey();
  if (key.isEmpty) {
    throw Exception('Pehle API key daalo');
  }
  final contents = messages
      .map((m) => {
            'role': m['role'] == 'assistant' ? 'model' : 'user',
            'parts': [
              {'text': m['content'] ?? ''}
            ],
          })
      .toList();
  final body = jsonEncode({
    'systemInstruction': {
      'parts': [
        {'text': system}
      ]
    },
    'contents': contents,
  });

  http.Response? res;
  for (var attempt = 0; attempt < 4; attempt++) {
    try {
      res = await http.post(
        Uri.parse(_aiUrl),
        headers: {
          'content-type': 'application/json',
          'x-goog-api-key': key,
        },
        body: body,
      );
    } catch (_) {
      res = null;
    }
    final busy = res == null || [429, 500, 503].contains(res.statusCode);
    if (!busy) break;
    if (attempt < 3) {
      await Future.delayed(Duration(seconds: 2 * (attempt + 1)));
    }
  }

  if (res == null) {
    throw Exception('Internet nahi chal raha, connection check karo');
  }
  if (res.statusCode == 429 || res.statusCode == 503) {
    throw Exception('Google ka server abhi busy hai. Thodi der baad try karo.');
  }
  final data = jsonDecode(utf8.decode(res.bodyBytes));
  if (res.statusCode != 200) {
    String msg = 'Error ${res.statusCode}';
    if (data is Map && data['error'] is Map) {
      msg = '${data['error']['message']}';
    }
    throw Exception(msg);
  }
  try {
    final parts = data['candidates'][0]['content']['parts'] as List;
    return parts.map((p) => p['text'] ?? '').join();
  } catch (_) {
    throw Exception('AI ne koi jawab nahi diya, dobara try karo');
  }
}
