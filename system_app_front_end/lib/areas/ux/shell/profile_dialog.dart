import 'package:flutter/material.dart';
import '../../../core/app_state.dart';
import '../../ui/adaptive_dialog.dart';

Future<void> showProfileDialog(BuildContext context, AppState state) {
  return showAppDialog<void>(
    context: context,
    builder: (_) => _ProfileDialog(state: state),
  );
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog({required this.state});
  final AppState state;
  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  List<Map<String, dynamic>>? rows;
  final name = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final result = await widget.state.profiles();
      if (mounted) setState(() => rows = result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> open(int id) async {
    setState(() { busy = true; error = null; });
    try {
      await widget.state.selectProfile(id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() { busy = false; error = e.toString(); });
    }
  }

  Future<void> create() async {
    if (name.text.trim().isEmpty) return;
    setState(() { busy = true; error = null; });
    try {
      final id = await widget.state.createProfile(name.text);
      await open(id);
    } catch (e) {
      if (mounted) setState(() { busy = false; error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    return PopScope(
      canPop: !busy,
      child: AppAdaptiveDialogShell(
        title: Text(s['profiles']),
        actions: [TextButton(onPressed: busy ? null : () => Navigator.pop(context), child: Text(s['cancel']))],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s['profilesHint']),
            const SizedBox(height: 12),
            if (rows == null && error == null) const LinearProgressIndicator(),
            for (final row in rows ?? <Map<String, dynamic>>[])
              ListTile(
                dense: true,
                title: Text(row['name'] == 'Default' ? s['personalProfile'] : row['name'].toString()),
                trailing: row['id'] == widget.state.workspaceId ? const Icon(Icons.check) : null,
                onTap: busy ? null : () => open(row['id'] as int),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: name,
              enabled: !busy,
              decoration: InputDecoration(labelText: s['profileName'], hintText: s['demoProfile']),
              onSubmitted: (_) => create(),
            ),
            TextButton(onPressed: busy ? null : create, child: Text(s['createBlankProfile'])),
            if (busy) const LinearProgressIndicator(),
            if (error != null) Text(error!),
          ],
        ),
      ),
    );
  }
}
