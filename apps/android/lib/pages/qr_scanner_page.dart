import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerPage extends StatefulWidget {
  const QrScannerPage({super.key});

  @override
  State<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<QrScannerPage> {
  final _textController = TextEditingController();
  final MobileScannerController _scanController = MobileScannerController();
  bool _cameraReady = false;
  bool _isScanning = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      await _scanController.start();
      if (mounted) {
        setState(() {
          _cameraReady = true;
          _isScanning = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _initError = '摄像头初始化失败: $e');
      }
    }
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      if (barcode.rawValue != null) {
        final code = barcode.rawValue!;
        if (code != _textController.text) {
          setState(() => _textController.text = code);
        }
        break;
      }
    }
  }

  void _submit() {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先扫描或输入二维码内容')),
      );
      return;
    }
    Navigator.of(context).pop(text);
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData('text/plain');
      final text = data?.text;
      if (text != null && text.isNotEmpty) {
        setState(() => _textController.text = text);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('剪贴板为空')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('读取剪贴板失败: $e')),
      );
    }
  }

  Future<void> _toggleScan() async {
    try {
      if (_isScanning) {
        await _scanController.stop();
      } else {
        await _scanController.start();
      }
      setState(() => _isScanning = !_isScanning);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('操作失败: $e')),
      );
    }
  }

  @override
  void dispose() {
    _scanController.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫描二维码')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildScannerArea(),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            _buildManualArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildScannerArea() {
    if (_initError != null) {
      return _buildCameraFallback(_initError!);
    }
    if (!_cameraReady) {
      return _buildLoading();
    }
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 250,
            child: MobileScanner(
              controller: _scanController,
              onDetect: _onDetect,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: _toggleScan,
              icon: Icon(_isScanning ? Icons.pause : Icons.play_arrow),
              label: Text(_isScanning ? '暂停扫描' : '开始扫描'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildCameraFallback(String message) {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.videocam_off_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '请使用下方手动输入',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildManualArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _cameraReady ? '手动输入' : '输入二维码内容',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _textController,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: '输入或粘贴链接',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              onPressed: _pasteFromClipboard,
              icon: const Icon(Icons.content_paste),
              tooltip: '粘贴',
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submit,
            child: const Text('提交'),
          ),
        ),
      ],
    );
  }
}