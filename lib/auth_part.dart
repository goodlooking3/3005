part of 'main.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _auth = AuthService();
  bool? configured;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final exists = await _auth.hasAccount();
      if (mounted) {
        setState(() {
          configured = exists;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'تعذر تهيئة مساحة الدخول المحلية.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (configured == null) {
      if (error == null) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return configured!
        ? LoginPage(auth: _auth)
        : SetupPage(auth: _auth, onDone: _load);
  }
}

class SetupPage extends StatefulWidget {
  final AuthService auth;
  final VoidCallback onDone;
  const SetupPage({super.key, required this.auth, required this.onDone});
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();
  bool loading = false;

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (name.text.trim().isEmpty ||
        (email.text.trim().isEmpty && phone.text.trim().isEmpty) ||
        password.text.length < 6) {
      _message('أدخل الاسم والبريد أو الهاتف وكلمة مرور من 6 أحرف على الأقل');
      return;
    }
    setState(() => loading = true);
    try {
      await widget.auth.createAccount(
        displayName: name.text,
        email: email.text,
        phone: phone.text,
        password: password.text,
      );
      if (mounted) widget.onDone();
    } catch (_) {
      if (mounted) {
        setState(() => loading = false);
        _message(
            'تعذر إنشاء المساحة المحلية. تحقق من التخزين ثم أعد المحاولة.');
      }
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  @override
  Widget build(BuildContext context) => _AuthScaffold(
        title: 'ابدأ مع واصل',
        subtitle: 'أنشئ مساحة مالية خاصة بك خلال دقيقة.',
        child: Column(
          children: [
            _field(name, 'اسم المستخدم', Icons.person_outline),
            const SizedBox(height: 12),
            _field(email, 'البريد الإلكتروني', Icons.email_outlined),
            const SizedBox(height: 12),
            _field(phone, 'رقم الهاتف (اختياري إذا أدخلت البريد)',
                Icons.phone_outlined),
            const SizedBox(height: 12),
            _field(password, 'كلمة المرور', Icons.lock_outline, secret: true),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: loading ? null : _submit,
                child: Text(loading ? 'جارٍ الإنشاء...' : 'إنشاء مساحة آمنة'),
              ),
            ),
          ],
        ),
      );
  Widget _field(
    TextEditingController c,
    String hint,
    IconData icon, {
    bool secret = false,
  }) =>
      TextField(
        controller: c,
        obscureText: secret,
        decoration: InputDecoration(
          prefixIcon: Icon(icon),
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      );
}

class LoginPage extends StatefulWidget {
  final AuthService auth;
  const LoginPage({super.key, required this.auth});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final identifier = TextEditingController();
  final password = TextEditingController();
  bool rememberMe = false;
  bool loading = false;
  bool biometricsAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
  }

  @override
  void dispose() {
    identifier.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> _checkBiometrics() async {
    final available = await widget.auth.canUseBiometrics();
    if (mounted) setState(() => biometricsAvailable = available);
  }

  Future<void> _login() async {
    setState(() => loading = true);
    try {
      final ok = await widget.auth.signIn(
        email: identifier.text,
        phone: identifier.text,
        password: password.text,
      );
      if (!mounted) return;
      if (ok) {
        await widget.auth.setRemembered(rememberMe);
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
      } else {
        setState(() => loading = false);
        _message('بيانات الدخول غير صحيحة');
      }
    } catch (_) {
      if (mounted) {
        setState(() => loading = false);
        _message('تعذر تسجيل الدخول. تحقق من التخزين ثم أعد المحاولة.');
      }
    }
  }

  Future<void> _biometric() async {
    final ok = await widget.auth.authenticateWithBiometrics();
    if (ok && mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const HomeShell()));
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  @override
  Widget build(BuildContext context) => _AuthScaffold(
        title: 'مرحبًا بعودتك',
        subtitle: 'سجّل الدخول إلى مساحة واصل الخاصة.',
        child: Column(
          children: [
            _field(identifier, 'البريد الإلكتروني أو رقم الهاتف',
                Icons.person_search_outlined),
            const SizedBox(height: 12),
            _field(password, 'كلمة المرور', Icons.lock_outline, secret: true),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: rememberMe,
              onChanged: (value) => setState(() => rememberMe = value ?? false),
              title: const Text('تذكرني على هذا الجهاز'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: loading ? null : _login,
                child: Text(loading ? 'جارٍ التحقق...' : 'دخول'),
              ),
            ),
            const SizedBox(height: 12),
            if (biometricsAvailable)
              OutlinedButton.icon(
                onPressed: loading ? null : _biometric,
                icon: const Icon(Icons.fingerprint),
                label: const Text('الدخول بالبصمة'),
              ),
          ],
        ),
      );
  Widget _field(
    TextEditingController c,
    String hint,
    IconData icon, {
    bool secret = false,
  }) =>
      TextField(
        controller: c,
        obscureText: secret,
        decoration: InputDecoration(
          prefixIcon: Icon(icon),
          hintText: hint,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      );
}

class _AuthScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  const _AuthScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFF315CFF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.all_inclusive_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(subtitle,
                      style: TextStyle(color: Colors.blueGrey.shade500)),
                  const SizedBox(height: 28),
                  child,
                ],
              ),
            ),
          ),
        ),
      );
}
