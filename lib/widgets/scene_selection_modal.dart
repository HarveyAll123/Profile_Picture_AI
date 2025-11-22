import 'package:flutter/material.dart';

import '../data/scene_presets.dart';
import '../models/scene_preset.dart';

class SceneSelectionModal extends StatefulWidget {
  const SceneSelectionModal({
    super.key,
    required this.initialSelectedSceneIds,
    required this.onApply,
    this.onReachedFive,
    this.scrollController,
  });

  final Set<String> initialSelectedSceneIds;
  final Future<bool> Function(Set<String>) onApply;
  final Future<bool> Function()? onReachedFive;
  final ScrollController? scrollController;

  @override
  State<SceneSelectionModal> createState() => _SceneSelectionModalState();
}

class _SceneSelectionModalState extends State<SceneSelectionModal> {
  late Set<String> _localSelectedIds;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _localSelectedIds = Set.from(widget.initialSelectedSceneIds);
  }

  Future<void> _handleSceneToggle(String sceneId) async {
    final previousCount = _localSelectedIds.length;
    var limitReached = false;
    setState(() {
      if (_localSelectedIds.contains(sceneId)) {
        _localSelectedIds.remove(sceneId);
      } else {
        if (_localSelectedIds.length >= 10) {
          limitReached = true;
        } else {
          _localSelectedIds.add(sceneId);
        }
      }
    });

    if (limitReached) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can choose up to 10 scenes at once.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final newCount = _localSelectedIds.length;
    if (widget.onReachedFive != null &&
        previousCount < 5 &&
        newCount >= 5) {
      await widget.onReachedFive!();
    }
  }

  void _handleReset() {
    setState(() {
      _localSelectedIds.clear();
    });
  }

  Future<void> _handleApply() async {
    if (_localSelectedIds.isEmpty || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
    });
    final shouldClose =
        await widget.onApply(Set<String>.from(_localSelectedIds));
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
    });
    if (shouldClose) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedNames = scenePresets
        .where((p) => _localSelectedIds.contains(p.id))
        .map((p) => p.title)
        .toList();

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          controller: widget.scrollController,
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade600,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select Scenes',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed:
                            _localSelectedIds.isEmpty ? null : _handleReset,
                        child: const Text('Reset'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Choose your scene(s) to generate',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.65),
                    ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 240,
                child: PageView.builder(
                  itemCount: (scenePresets.length / 2).ceil(),
                  itemBuilder: (context, pageIndex) {
                    final startIndex = pageIndex * 2;
                    final endIndex =
                        (startIndex + 2).clamp(0, scenePresets.length);
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = startIndex; i < endIndex; i++)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: i < endIndex - 1 ? 14 : 0,
                            ),
                            child: _SceneOption(
                              preset: scenePresets[i],
                              isSelected:
                                  _localSelectedIds.contains(scenePresets[i].id),
                              onTap: () =>
                                  _handleSceneToggle(scenePresets[i].id),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              if (selectedNames.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.indigoAccent.withValues(alpha: 0.3),
                    ),
                    color: Colors.indigoAccent.withValues(alpha: 0.1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Selected: ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.indigoAccent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          selectedNames.length <= 3
                              ? selectedNames.join(', ')
                              : '${selectedNames.take(2).join(', ')} +${selectedNames.length - 2}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.indigoAccent,
                                fontWeight: FontWeight.w500,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                    color: Colors.white.withValues(alpha: 0.03),
                  ),
                child: Text(
                  'No scenes selected',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.45),
                      ),
                ),
                ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _localSelectedIds.isEmpty || _isSubmitting
                      ? null
                      : _handleApply,
                  style: ButtonStyle(
                    backgroundColor:
                        WidgetStateProperty.resolveWith((states) {
                      const base = Colors.indigoAccent;
                      if (states.contains(WidgetState.disabled)) {
                        return base.withValues(alpha: 0.35);
                      }
                      return base;
                    }),
                    foregroundColor:
                        WidgetStateProperty.all<Color>(Colors.white),
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(vertical: 14),
                    ),
                    shape: WidgetStateProperty.all(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    textStyle: WidgetStateProperty.all(
                      const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline, size: 20),
                            SizedBox(width: 8),
                            Text('Done'),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SceneOption extends StatelessWidget {
  const _SceneOption({
    required this.preset,
    required this.isSelected,
    required this.onTap,
  });

  final ScenePreset preset;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final gradientColors = isSelected
        ? (isDark
            ? preset.gradient
            : preset.gradient
                .map((color) => Color.lerp(color, Colors.white, 0.4)!)
                .toList())
        : isDark
            ? const [Color(0xFF111828), Color(0xFF0B1120)]
            : [
                theme.colorScheme.surface,
                theme.colorScheme.surface.withValues(alpha: 0.85),
              ];
    final titleColor =
        (isSelected || isDark) ? Colors.white : theme.colorScheme.onSurface;
    final subtitleColor = titleColor.withValues(alpha: 0.75);
    final borderColor = isSelected
        ? Colors.indigoAccent
        : theme.colorScheme.onSurface.withValues(alpha: isDark ? 0.18 : 0.15);
    final iconBg = (isSelected || isDark)
        ? Colors.black.withValues(alpha: 0.25)
        : theme.colorScheme.primary.withValues(alpha: 0.08);
    final iconColor =
        (isSelected || isDark) ? Colors.white : theme.colorScheme.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2 : 1,
          ),
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(preset.icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    preset.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preset.subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: subtitleColor,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.indigoAccent : Colors.white54,
                  width: 2,
                ),
                color: isSelected ? Colors.indigoAccent : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
