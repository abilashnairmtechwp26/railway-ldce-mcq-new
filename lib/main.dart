import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const RailwayLdceApp());
}

class RailwayLdceApp extends StatelessWidget {
  const RailwayLdceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Railway LDCE MCQ Generator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0D47A1)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class McqQuestion {
  final String question;
  final List<String> options;
  final int correctIndex;
  final String section;
  final int probabilityPercent;
  final String probabilityReason;
  final String explanation;

  McqQuestion({
    required this.question,
    required this.options,
    required this.correctIndex,
    required this.section,
    required this.probabilityPercent,
    required this.probabilityReason,
    required this.explanation,
  });

  factory McqQuestion.fromJson(Map<String, dynamic> json) {
    return McqQuestion(
      question: json['question'] ?? '',
      options: List<String>.from(json['options'] ?? []),
      correctIndex: (json['correctIndex'] ?? 0) as int,
      section: json['section'] ?? 'General',
      probabilityPercent: (json['probabilityPercent'] ?? 75) as int,
      probabilityReason: json['probabilityReason'] ?? '',
      explanation: json['explanation'] ?? '',
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _apiKeyController = TextEditingController();
  String _selectedCadre = 'AEN (Civil Engineering)';
  int _questionCount = 15;

  File? _studyPdf;
  String? _studyPdfName;
  File? _pyqPdf;
  String? _pyqPdfName;

  bool _isLoading = false;
  String? _errorMsg;

  final List<String> _cadres = [
    'AEN (Civil Engineering)',
    'AOM (Traffic / Operating)',
    'ACM (Commercial)',
    'AEE (Electrical)',
    'AME / AWM (Mechanical)',
    'ASTE (Signal & Telecom)',
    'APO (Personnel)',
    'AMM (Stores)',
    'AFA / ADFM (Accounts)',
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedApiKey();
  }

  Future<void> _loadSavedApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString('gemini_api_key') ?? '';
    });
  }

  Future<void> _saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key.trim());
  }

  Future<void> _pickPdf({required bool isStudyPdf}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final sizeInMb = await file.length() / (1024 * 1024);
      if (sizeInMb > 15.0) {
        setState(() {
          _errorMsg =
              'Selected PDF is ${sizeInMb.toStringAsFixed(1)} MB. Please keep each PDF under 15 MB for inline mobile processing.';
        });
        return;
      }
      setState(() {
        _errorMsg = null;
        if (isStudyPdf) {
          _studyPdf = file;
          _studyPdfName = result.files.single.name;
        } else {
          _pyqPdf = file;
          _pyqPdfName = result.files.single.name;
        }
      });
    }
  }

  Future<void> _generateMcqs() async {
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() => _errorMsg = 'Please enter your Gemini API Key.');
      return;
    }
    if (_studyPdf == null) {
      setState(() => _errorMsg = 'Please upload a Study Material / Rulebook PDF.');
      return;
    }
    await _saveApiKey(apiKey);
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final studyBytes = await _studyPdf!.readAsBytes();
      final studyBase64 = base64Encode(studyBytes);

      final List<Map<String, dynamic>> parts = [
        {
          'inlineData': {
            'mimeType': 'application/pdf',
            'data': studyBase64,
          }
        },
      ];

      if (_pyqPdf != null) {
        final pyqBytes = await _pyqPdf!.readAsBytes();
        parts.add({
          'inlineData': {
            'mimeType': 'application/pdf',
            'data': base64Encode(pyqBytes),
          }
        });
      }

      final prompt = '''
You are an expert Indian Railways Group 'B' 30% LDCE Exam Paper Setter (Centralized CBT pattern per Railway Board Letter No. E(GP)2022/2/4 dated 07.11.2022).
Target Post: $_selectedCadre.

Task:
Analyze the attached Study Material PDF${_pyqPdf != null ? " AND the attached Previous Year Question Paper (PYQ) PDF" : ""}.
Generate $_questionCount high-yield Multiple Choice Questions (MCQs) strictly grounded in the Study PDF, prioritized and weighted by PREVIOUS YEAR EXAM PROBABILITY for the Railway LDCE Assistant Officer CBT.

${_pyqPdf != null ? "1. First extract the topic frequency, rule-citation style, and distractor traps from the PYQ PDF, and bias your generated MCQs toward the highest-frequency concepts present in the Study PDF." : "1. Apply historical Railway LDCE Group-B CBT probability weights: focus heavily on numerical limits, authority levels (GM/DRM/PHOD/JAG/SS), DAR 1968 standard forms (SF-1 to SF-11), IREM/IREC clauses, Pass/Leave rules, Financial & Store canons, Rajbhasha Articles 343-351 & Annual Programme targets, and technical tolerances/standards."}
2. Include Railway CBT-style options (e.g., exact numeric limits, "Both A & B", "None of the above", rule exceptions) suitable for +1 / -1/3 negative marking.
3. For each MCQ, provide an estimated probabilityPercent (1-100) and a brief probabilityReason explaining why it is likely to appear in the LDCE exam.
4. Return ONLY valid JSON matching the requested schema.
''';

      parts.add({'text': prompt});

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key=$apiKey',
      );

      final body = {
        'contents': [
          {'parts': parts}
        ],
        'generationConfig': {
          'temperature': 0.3,
          'responseMimeType': 'application/json',
          'responseSchema': {
            'type': 'ARRAY',
            'items': {
              'type': 'OBJECT',
              'properties': {
                'question': {'type': 'STRING'},
                'options': {
                  'type': 'ARRAY',
                  'items': {'type': 'STRING'},
                },
                'correctIndex': {'type': 'INTEGER'},
                'section': {'type': 'STRING'},
                'probabilityPercent': {'type': 'INTEGER'},
                'probabilityReason': {'type': 'STRING'},
                'explanation': {'type': 'STRING'},
              },
              'required': [
                'question',
                'options',
                'correctIndex',
                'section',
                'probabilityPercent',
                'probabilityReason',
                'explanation'
              ]
            }
          }
        }
      };

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      if (response.statusCode != 200) {
        throw Exception('API Error (${response.statusCode}): ${response.body}');
      }

      final decoded = jsonDecode(response.body);
      final rawText =
          decoded['candidates'][0]['content']['parts'][0]['text'] as String;
      final List<dynamic> jsonList = jsonDecode(rawText);
      child: const Text('Browse'),
                ),
              ),
            ),
            if (_errorMsg != null) ...[
              const SizedBox(height: 12),
              Text(_errorMsg!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isLoading ? null : _generateMcqs,
              icon: _isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_isLoading
                  ? 'Analyzing PDF & Calculating Probabilities...'
                  : 'Generate Probability-Weighted MCQs'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QuizScreen extends StatefulWidget {
  final List<McqQuestion> questions;
  final String cadre;

  const QuizScreen({super.key, required this.questions, required this.cadre});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  final Map<int, int> _selectedAnswers = {};
  bool _submitted = false;

  double get _cbtScore {
    double score = 0;
    for (int i = 0; i < widget.questions.length; i++) {
      if (_selectedAnswers.containsKey(i)) {
        if (_selectedAnswers[i] == widget.questions[i].correctIndex) {
          score += 1.0;
        } else {
          score -= 1.0 / 3.0;
        }
      }
    }
    return score;
  }

  Color _probColor(int prob) {
    if (prob >= 75) return Colors.red.shade700;
    if (prob >= 50) return Colors.orange.shade800;
    return Colors.blueGrey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.cadre.split(' ').first} Mock Test'),
        actions: [
          if (!_submitted)
            TextButton(
              onPressed: () => setState(() => _submitted = true),
              child: const Text('SUBMIT',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_submitted)
            Container(
              width: double.infinity,
              color: Colors.blue.shade50,
              padding: const EdgeInsets.all(14),
              child: Text(
                'CBT Score (+1 / -0.33): ${_cbtScore.toStringAsFixed(2)} / ${widget.questions.length}',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: widget.questions.length,
              itemBuilder: (context, index) {
                final q = widget.questions[index];
                final chosen = _selectedAnswers[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 14),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          children: [
                            Chip(
                              label: Text(
                                  'PYQ Prob: ${q.probabilityPercent}%',
                                style: const TextStyle(
                                      color: Colors.white, fontSize: 12)),
                              backgroundColor: _probColor(q.probabilityPercent),
                            ),
                            Chip(
                              label: Text(q.section,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Q${index + 1}. ${q.question}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        ...List.generate(q.options.length, (optIdx) {
                          Color? tileColor;
                          if (_submitted) {
                            if (optIdx == q.correctIndex) {
                              tileColor = Colors.green.shade100;
                            } else if (chosen == optIdx &&
                                optIdx != q.correctIndex) {
                              tileColor = Colors.red.shade100;
                            }
                          }
                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              color: tileColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: RadioListTile<int>(
                              value: optIdx,
                              groupValue: chosen,
                              title: Text(q.options[optIdx]),
                              onChanged: _submitted
                                  ? null
                                  : (val) => setState(
                                      () => _selectedAnswers[index] = val!),
                            ),
                          );
                        }),
                        if (_submitted) ...[
                          const Divider(),
                          Text(
                            'Why Probable: ${q.probabilityReason}',
                            style: TextStyle(
                                fontSize: 13,
                                fontStyle: FontStyle.italic,
                                color: Colors.grey.shade800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Explanation: ${q.explanation}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ]
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
