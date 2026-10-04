String userFacingError(Object error, {required String fallback}) {
  final message = switch (error) {
    ArgumentError value => value.message?.toString() ?? '',
    StateError value => value.message,
    FormatException value => value.message,
    _ => error.toString(),
  }.trim();
  if (message.isEmpty || message.length > 180) return fallback;
  final technical = RegExp(
    r'(dart:|package:|\.dart|sqlite|SQL|NoSuchMethod|Stack Trace|#\d+|Bad state:|type .+ is not)',
    caseSensitive: false,
  );
  return technical.hasMatch(message) ? fallback : message;
}
