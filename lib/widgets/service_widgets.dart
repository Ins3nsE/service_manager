import 'package:flutter/material.dart';

import '../models/service.dart';
import '../localization.dart';

Future<List<ServiceDef>?> showServiceSelectionDialog(
  BuildContext context, {
  required List<ServiceDef> available,
  required Set<String> selectedNames,
  required AppLocalizations l10n,
}) {
  return showDialog<List<ServiceDef>>(
    context: context,
    builder: (_) => ServiceSelectionDialog(
      available: available,
      initialSelectedNames: selectedNames,
      l10n: l10n,
    ),
  );
}

class ServiceSelectionDialog extends StatefulWidget {
  const ServiceSelectionDialog({
    super.key,
    required this.available,
    required this.initialSelectedNames,
    required this.l10n,
  });

  final List<ServiceDef> available;
  final Set<String> initialSelectedNames;
  final AppLocalizations l10n;

  @override
  State<ServiceSelectionDialog> createState() => _ServiceSelectionDialogState();
}

class _ServiceSelectionDialogState extends State<ServiceSelectionDialog> {
  late final Set<String> _selectedNames = {...widget.initialSelectedNames};
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final query = _search.trim().toLowerCase();
    final filtered = widget.available
        .where(
          (service) =>
              query.isEmpty ||
              service.name.toLowerCase().contains(query) ||
              service.fallbackDisplayName.toLowerCase().contains(query),
        )
        .toList();

    return AlertDialog(
      title: Text(widget.l10n.serviceSelection),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: widget.l10n.search,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: widget.available.isEmpty
                      ? null
                      : () => setState(() {
                          _selectedNames.addAll(
                            widget.available.map((service) => service.name),
                          );
                        }),
                  icon: const Icon(Icons.select_all),
                  label: Text(widget.l10n.selectAll),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _selectedNames.isEmpty
                      ? null
                      : () => setState(() => _selectedNames.clear()),
                  icon: const Icon(Icons.deselect),
                  label: Text(widget.l10n.deselectAll),
                ),
              ],
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text(widget.l10n.notFound))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final service = filtered[index];
                        return CheckboxListTile(
                          value: _selectedNames.contains(service.name),
                          title: Text(service.fallbackDisplayName),
                          subtitle: Text(service.name),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (selected) => setState(() {
                            if (selected == true) {
                              _selectedNames.add(service.name);
                            } else {
                              _selectedNames.remove(service.name);
                            }
                          }),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            widget.available
                .where((service) => _selectedNames.contains(service.name))
                .toList(),
          ),
          child: Text(widget.l10n.apply),
        ),
      ],
    );
  }
}

class AdminBanner extends StatelessWidget {
  const AdminBanner({super.key, required this.onRelaunch, required this.l10n});

  final VoidCallback onRelaunch;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.shield_outlined, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.adminRequired,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.onErrorContainer,
                foregroundColor: scheme.errorContainer,
              ),
              onPressed: onRelaunch,
              child: Text(l10n.restart),
            ),
          ],
        ),
      ),
    );
  }
}

class ServiceCard extends StatelessWidget {
  const ServiceCard({
    super.key,
    required this.entry,
    required this.onStart,
    required this.onStop,
    required this.onRestart,
    required this.onRemove,
    required this.l10n,
  });

  final ServiceEntry entry;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onRestart;
  final VoidCallback onRemove;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = switch (entry.status) {
      ServiceStatus.running => Colors.green,
      ServiceStatus.stopped => theme.colorScheme.error,
      ServiceStatus.startPending || ServiceStatus.stopPending => Colors.orange,
      ServiceStatus.unknown => Colors.grey,
    };
    final statusIcon = switch (entry.status) {
      ServiceStatus.running => Icons.check_circle,
      ServiceStatus.stopped => Icons.cancel,
      ServiceStatus.startPending ||
      ServiceStatus.stopPending => Icons.hourglass_top,
      ServiceStatus.unknown => Icons.help_outline,
    };
    final canStart = !entry.busy && entry.status != ServiceStatus.running;
    final canStop = !entry.busy && entry.status != ServiceStatus.stopped;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(statusIcon, color: statusColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.def.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(entry.displayName, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(status: entry.status, l10n: l10n),
              ],
            ),
            if (entry.busy) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: canStart ? onStart : null,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(l10n.start),
                      ),
                      OutlinedButton.icon(
                        onPressed: canStop ? onStop : null,
                        icon: const Icon(Icons.stop),
                        label: Text(l10n.stop),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            !entry.busy && entry.status == ServiceStatus.running
                            ? onRestart
                            : null,
                        icon: const Icon(Icons.restart_alt),
                        label: Text(l10n.restartService),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: entry.busy ? null : onRemove,
                  tooltip: l10n.removeService,
                  color: Theme.of(
                    context,
                  ).colorScheme.error.withValues(alpha: 0.75),
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, required this.l10n});

  final ServiceStatus status;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ServiceStatus.running => Colors.green,
      ServiceStatus.stopped => Theme.of(context).colorScheme.error,
      ServiceStatus.startPending || ServiceStatus.stopPending => Colors.orange,
      ServiceStatus.unknown => Colors.grey,
    };
    final icon = switch (status) {
      ServiceStatus.running => Icons.check_circle,
      ServiceStatus.stopped => Icons.cancel,
      ServiceStatus.startPending ||
      ServiceStatus.stopPending => Icons.hourglass_top,
      ServiceStatus.unknown => Icons.help_outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            l10n.status(status),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
