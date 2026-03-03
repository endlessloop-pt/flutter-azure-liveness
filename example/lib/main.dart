import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_azure_liveness/flutter_azure_liveness.dart';
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Azure Face Liveness Demo',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const LivenessHomePage(),
    );
  }
}

class LivenessHomePage extends StatefulWidget {
  const LivenessHomePage({super.key});

  @override
  State<LivenessHomePage> createState() => _LivenessHomePageState();
}

class _LivenessHomePageState extends State<LivenessHomePage> {
  final _tokenController = TextEditingController();
  Uint8List? _verifyImageBytes;
  String? _verifyImageName;
  LivenessResult? _result;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _pickVerifyImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _verifyImageBytes = bytes;
        _verifyImageName = picked.name;
      });
    }
  }

  void _clearVerifyImage() => setState(() {
        _verifyImageBytes = null;
        _verifyImageName = null;
      });

  Future<void> _startLivenessCheck() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _errorMessage = 'Please enter a session token.');
      return;
    }
    setState(() {
      _isLoading = true;
      _result = null;
      _errorMessage = null;
    });

    try {
      final result = await AzureLiveness.startLivenessCheck(
        sessionToken: token,
        verifyImageBytes: _verifyImageBytes,
      );
      setState(() => _result = result);
    } catch (e) {
      setState(() => _errorMessage = 'Plugin error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Azure Face Liveness')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Session token input ──────────────────────────────────────
            TextField(
              controller: _tokenController,
              decoration: const InputDecoration(
                labelText: 'Session Authorization Token',
                hintText: 'Paste your authToken here',
                border: OutlineInputBorder(),
                helperText:
                    'Obtain from POST /detectLiveness-sessions on your server.',
                helperMaxLines: 2,
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 12),

            // ── Verify image picker ──────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    _verifyImageName != null
                        ? 'Verify image: $_verifyImageName'
                        : 'No verify image — liveness-only mode',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (_verifyImageBytes != null)
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove verify image',
                    onPressed: _clearVerifyImage,
                  ),
                TextButton.icon(
                  onPressed: _pickVerifyImage,
                  icon: const Icon(Icons.image_search),
                  label: const Text('Browse'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Start button ─────────────────────────────────────────────
            FilledButton(
              onPressed: _isLoading ? null : _startLivenessCheck,
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Start Liveness Check'),
            ),
            const SizedBox(height: 24),

            // ── Result / error panels ────────────────────────────────────
            if (_errorMessage != null)
              _ResultCard(
                title: 'Error',
                color: Colors.red.shade50,
                borderColor: Colors.red.shade200,
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            if (_result != null) _ResultPanel(result: _result!),
          ],
        ),
      ),
    );
  }
}

// ── Result UI helpers ────────────────────────────────────────────────────────

class _ResultPanel extends StatelessWidget {
  final LivenessResult result;
  const _ResultPanel({required this.result});

  @override
  Widget build(BuildContext context) {
    if (result.isSuccess) {
      return _ResultCard(
        title: 'Session completed',
        color: Colors.green.shade50,
        borderColor: Colors.green.shade200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Field(label: 'Digest', value: result.digest ?? '—'),
            const SizedBox(height: 4),
            _Field(label: 'Result ID', value: result.resultId ?? '—'),
            const SizedBox(height: 8),
            Text(
              'Next step: query GET /livenessSessions/{sessionId}/result on '
              'your server to retrieve the final livenessDecision '
              '(realface / spoof).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ],
        ),
      );
    }
    return _ResultCard(
      title: 'Liveness check failed',
      color: Colors.orange.shade50,
      borderColor: Colors.orange.shade200,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field(label: 'Error code', value: result.errorCode ?? '—'),
          const SizedBox(height: 4),
          _Field(label: 'Message', value: result.errorMessage ?? '—'),
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String title;
  final Color color;
  final Color borderColor;
  final Widget child;

  const _ResultCard({
    required this.title,
    required this.color,
    required this.borderColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String value;
  const _Field({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: [
          TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          TextSpan(text: value),
        ],
      ),
    );
  }
}
