import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'ai.dart';

const _native = MethodChannel('callai/native');

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Call AI Test',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final _stt = SpeechToText();
  final _tts = FlutterTts();
  final _keyC = TextEditingController();
  final _testC = TextEditingController();
  final List<Map<String, String>> _msgs = [];
  Timer? _timer;
  bool _dialer = false;
  bool _aiMode = false;
  bool _hasKey = false;
  bool _sttReady = false;
  bool _running = false;
  bool _testBusy = false;
  int _state = -1;
  int _prev = -1;
  String _number = '';
  String _lang = 'hi-IN';
  String? _summary;
  String? _err;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stt.cancel();
    _tts.stop();
    super.dispose();
  }

  Future<void> _init() async {
    try {
      _sttReady = await _stt.initialize();
      await _tts.setSpeechRate(0.5);
      await _tts.setLanguage(_lang);
      await _tts.awaitSpeakCompletion(true);
    } catch (_) {}
    await _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  Future<void> _refresh() async {
    try {
      final d = await _native.invokeMethod<bool>('isDialer') ?? false;
      final a = await _native.invokeMethod<bool>('getAiMode') ?? false;
      final k = (await getKey()).isNotEmpty;
      if (mounted) {
        setState(() {
          _dialer = d;
          _aiMode = a;
          _hasKey = k;
        });
      }
    } catch (_) {}
  }

  Future<void> _tick() async {
    try {
      final m = Map<String, dynamic>.from(
          await _native.invokeMethod('callState') as Map);
      final s = m['state'] as int;
      final n = (m['number'] ?? '') as String;
      if (!mounted) return;
      setState(() {
        _state = s;
        _number = n;
      });
      if (s == 4 && _prev != 4 && _aiMode && !_running) {
        _runConversation();
      }
      if (_prev == 4 && s != 4) {
        _onEnded();
      }
      _prev = s;
    } catch (_) {}
  }

  void _add(String role, String text) {
    if (mounted) setState(() => _msgs.add({'role': role, 'content': text}));
  }

  List<Map<String, String>> _history() =>
      _msgs.skipWhile((m) => m['role'] == 'assistant').toList();

  Future<void> _say(String text) async {
    try {
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<String> _listenOnce() async {
    if (!_sttReady) return '';
    final c = Completer<String>();
    var last = '';
    await _stt.listen(
      localeId: _lang,
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 3),
      onResult: (r) {
        last = r.recognizedWords;
        if (r.finalResult && !c.isCompleted) c.complete(r.recognizedWords);
      },
    );
    return c.future.timeout(const Duration(seconds: 25), onTimeout: () {
      _stt.stop();
      return last;
    });
  }

  Future<void> _hangup() async {
    try {
      await _native.invokeMethod('hangup');
    } catch (_) {}
  }

  Future<void> _runConversation() async {
    if (_running) return;
    _running = true;
    setState(() {
      _msgs.clear();
      _summary = null;
      _err = null;
    });
    try {
      await _native.invokeMethod('speaker');
      await Future.delayed(const Duration(seconds: 1));
      const greet =
          'Namaste, main maalik ka AI assistant hoon. Aap kaun bol rahe hain, aur kis liye call kiya hai?';
      _add('assistant', greet);
      await _say(greet);
      var silence = 0;
      var turns = 0;
      while (_state == 4) {
        final heard = await _listenOnce();
        if (_state != 4) break;
        if (heard.trim().isEmpty) {
          silence++;
          if (silence >= 3) {
            await _say('Koi jawab nahi mila, main call band kar raha hoon. Dhanyavaad.');
            await _hangup();
            break;
          }
          continue;
        }
        silence = 0;
        turns++;
        _add('user', heard);
        final reply = await askAI(receptionistSystem, _history());
        _add('assistant', reply);
        await _say(reply);
        if (turns >= 8) {
          await _say('Main maalik ko aapka sandesh de dunga. Dhanyavaad.');
          await _hangup();
          break;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _err = e.toString().replaceFirst('Exception: ', ''));
      }
      await _hangup();
    }
    _running = false;
  }

  Future<void> _onEnded() async {
    try {
      await _stt.cancel();
      await _tts.stop();
    } catch (_) {}
    if (_msgs.isEmpty) return;
    final transcript = _msgs
        .map((m) =>
            '${m['role'] == 'user' ? 'Caller' : 'Receptionist'}: ${m['content']}')
        .join('\n');
    try {
      final r = await askAI(summarySystem, [
        {'role': 'user', 'content': transcript}
      ]);
      if (mounted) setState(() => _summary = r);
    } catch (e) {
      if (mounted) {
        setState(() => _err = e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  Future<void> _testSend() async {
    final t = _testC.text.trim();
    if (t.isEmpty || _testBusy) return;
    setState(() {
      _testBusy = true;
      _err = null;
      _testC.clear();
    });
    _add('user', t);
    try {
      final reply = await askAI(receptionistSystem, _history());
      _add('assistant', reply);
      await _say(reply);
    } catch (e) {
      if (mounted) {
        setState(() => _err = e.toString().replaceFirst('Exception: ', ''));
      }
    }
    if (mounted) setState(() => _testBusy = false);
  }

  String _stateText(int s) {
    switch (s) {
      case -1:
        return 'Koi call nahi';
      case 2:
        return 'Ring ho raha hai';
      case 4:
        return 'Call chal rahi hai';
      case 1:
      case 9:
        return 'Connect ho raha hai';
      case 7:
        return 'Call khatam';
      default:
        return 'State $s';
    }
  }

  Widget _card(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Call AI Test')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: Colors.orange.withOpacity(0.15),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                  'Ye experiment sirf extra phone ke liye hai. Asli phone par install mat karo.'),
            ),
          ),
          _card('1. Setup', [
            Row(
              children: [
                Icon(_dialer ? Icons.check_circle : Icons.cancel,
                    color: _dialer ? Colors.green : Colors.red),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(_dialer
                        ? 'Ye app Default Phone app hai'
                        : 'Ye app Default Phone app nahi hai')),
              ],
            ),
            if (!_dialer)
              FilledButton(
                onPressed: () async {
                  try {
                    await _native.invokeMethod('requestDialer');
                  } catch (_) {}
                  await _refresh();
                },
                child: const Text('Default Phone app banao'),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _native.invokeMethod('requestNotif'),
              child: const Text('Notification permission do'),
            ),
            const SizedBox(height: 8),
            if (_hasKey)
              const Text('Gemini key save hai')
            else ...[
              TextField(
                controller: _keyC,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Gemini API key',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () async {
                  final k = _keyC.text.trim();
                  if (k.isEmpty) return;
                  await saveKey(k);
                  _keyC.clear();
                  await _refresh();
                },
                child: const Text('Key save karo'),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Hindi'),
                  selected: _lang == 'hi-IN',
                  onSelected: (_) async {
                    setState(() => _lang = 'hi-IN');
                    await _tts.setLanguage('hi-IN');
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('English'),
                  selected: _lang == 'en-IN',
                  onSelected: (_) async {
                    setState(() => _lang = 'en-IN');
                    await _tts.setLanguage('en-IN');
                  },
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('AI mode: call apne aap uthao'),
              subtitle: const Text('Ring ke 3 second baad AI call uthayega'),
              value: _aiMode,
              onChanged: (v) async {
                await _native.invokeMethod('setAiMode', v);
                await _refresh();
              },
            ),
          ]),
          _card('2. Live call', [
            Text(_stateText(_state), style: TextStyle(color: cs.primary)),
            if (_number.isNotEmpty) Text('Number: $_number'),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton(
                  onPressed: _state == 2
                      ? () => _native.invokeMethod('answer')
                      : null,
                  child: const Text('Uthao'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _state == -1 ? null : _hangup,
                  child: const Text('Kaato'),
                ),
              ],
            ),
          ]),
          _card('3. AI test (bina call ke)', [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _testC,
                    onSubmitted: (_) => _testSend(),
                    decoration: const InputDecoration(
                      hintText: 'Caller bankar likho...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _testBusy ? null : _testSend,
                  icon: const Icon(Icons.send),
                ),
              ],
            ),
          ]),
          if (_msgs.isNotEmpty)
            _card(
              'Baat-cheet',
              _msgs
                  .map((m) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                            '${m['role'] == 'user' ? 'Caller' : 'AI'}: ${m['content']}'),
                      ))
                  .toList(),
            ),
          if (_summary != null) _card('Call summary', [SelectableText(_summary!)]),
          if (_err != null)
            Card(
              color: Colors.red.withOpacity(0.12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_err!),
              ),
            ),
        ],
      ),
    );
  }
}
