/// Reduces a raw RPC failure to the one line worth showing a user.
///
/// An Odoo server error stringifies to its own multi-kilobyte Python
/// traceback, wrapped in a generic "Odoo Server Error" envelope. Shown
/// verbatim it is unreadable and can grow a snackbar taller than the screen;
/// summarised away entirely it hides the only part that explains the
/// failure. This pulls out the server's own message and leaves anything that
/// is not an Odoo exception untouched.
String briefOdooMessage(Object e) {
  final raw = e.toString();
  final beforeTrace = raw.split('Traceback').first.trim();

  final message =
      RegExp(
            r"message:\s*(.*?)(?=,\s*(?:arguments|context|debug|data|code|name|exception_type)\s*:|\}\s*\}?\s*$)",
            dotAll: true,
          )
          .allMatches(beforeTrace)
          .map((m) => m.group(1)!.trim())
          .where((m) => m.isNotEmpty && m != 'Odoo Server Error')
          .fold<String>(
            '',
            (longest, m) => m.length > longest.length ? m : longest,
          );

  final text = (message.isNotEmpty ? message : beforeTrace)
      .replaceAll(RegExp(r'\s*\n\s*'), ' ')
      .trim();
  return text.length > 300 ? '${text.substring(0, 300)}…' : text;
}
