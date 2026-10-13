part of 'main.dart';

class DeviceLicenseGate extends StatefulWidget {
  final Widget child;
  const DeviceLicenseGate({super.key, required this.child});

  @override
  State<DeviceLicenseGate> createState() => _DeviceLicenseGateState();
}

class _DeviceLicenseGateState extends State<DeviceLicenseGate> {
  final _license = const DeviceLicenseService();
  bool? _licensed;

  bool get _required =>
      !kIsWeb &&
      kReleaseMode &&
      defaultTargetPlatform == TargetPlatform.windows;

  @override
  void initState() {
    super.initState();
    if (_required) _checkLicense();
  }

  Future<void> _checkLicense() async {
    final valid = await _license.hasValidStoredLicense();
    if (mounted) setState(() => _licensed = valid);
  }

  @override
  Widget build(BuildContext context) {
    if (!_required || _licensed == true) return widget.child;
    if (_licensed == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return DeviceLicenseScreen(
      license: _license,
      onActivated: _checkLicense,
    );
  }
}

class DeviceLicenseScreen extends StatefulWidget {
  final DeviceLicenseService license;
  final Future<void> Function() onActivated;

  const DeviceLicenseScreen({
    super.key,
    required this.license,
    required this.onActivated,
  });

  @override
  State<DeviceLicenseScreen> createState() => _DeviceLicenseScreenState();
}

class _DeviceLicenseScreenState extends State<DeviceLicenseScreen> {
  late Future<String> _deviceId;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _deviceId = widget.license.deviceId();
  }

  String _groupId(String id) =>
      RegExp(r'.{1,4}').allMatches(id).map((match) => match.group(0)).join('-');

  Future<void> _copyDeviceId(String id) async {
    await Clipboard.setData(ClipboardData(text: id));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم نسخ معرّف الجهاز.')),
      );
    }
  }

  Future<void> _importLicense() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final selection = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (selection == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final bytes = selection.files.single.bytes;
      if (bytes == null || bytes.isEmpty) {
        throw const FormatException('تعذر قراءة الملف المختار.');
      }
      await widget.license.activate(bytes);
      if (mounted) await widget.onActivated();
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error is FormatException
              ? error.message
              : 'تعذر تفعيل الملف. تحقق من أنه ترخيص واصل صالح.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: _AuthScaffold(
          title: 'تفعيل واصل على هذا الجهاز',
          subtitle: 'يلزم ملف ترخيص غير متصل مرتبط بهذا الجهاز.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'أرسل معرّف الجهاز إلى مسؤول الترخيص للحصول على ملف التفعيل. '
                'لا يغادر معرّف Windows الخام هذا الجهاز.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FutureBuilder<String>(
                future: _deviceId,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Column(
                      children: [
                        const Text(
                          'تعذر قراءة معرّف الجهاز. تحقق من Windows ثم أعد المحاولة.',
                          textAlign: TextAlign.center,
                        ),
                        TextButton.icon(
                          onPressed: () => setState(
                            () => _deviceId = widget.license.deviceId(),
                          ),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final id = snapshot.data!;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.blueGrey.shade100),
                    ),
                    child: Column(
                      children: [
                        const Text('معرّف الجهاز'),
                        const SizedBox(height: 8),
                        SelectableText(
                          _groupId(id),
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.1,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () => _copyDeviceId(id),
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('نسخ المعرّف'),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 50,
                child: FilledButton.icon(
                  onPressed: _loading ? null : _importLicense,
                  icon: const Icon(Icons.file_open_outlined),
                  label:
                      Text(_loading ? 'جارٍ التحقق...' : 'استيراد ملف الترخيص'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      );
}
