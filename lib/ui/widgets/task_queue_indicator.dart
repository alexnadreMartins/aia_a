import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/task_queue_state.dart';

class TaskQueueIndicator extends ConsumerWidget {
  const TaskQueueIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(taskQueueProvider);
    final activeTasks = tasks.where((t) => t.status == TaskStatus.running || t.status == TaskStatus.pending).toList();

    if (activeTasks.isEmpty) return const SizedBox.shrink();

    return Container(
      width: 60, // Match Left Dock width
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Colors.black26,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_upload, color: Colors.blueAccent, size: 20),
          const SizedBox(height: 4),
          Text("${activeTasks.length}", style: const TextStyle(color: Colors.white, fontSize: 10)),
          const SizedBox(height: 8),
          ...activeTasks.take(3).map((t) => _buildTaskItem(t)),
        ],
      ),
    );
  }

  Widget _buildTaskItem(BgTask task) {
    return Tooltip(
      message: "${task.name} (${(task.progress * 100).toInt()}%)",
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: LinearProgressIndicator(
           value: task.status == TaskStatus.pending ? null : task.progress,
           backgroundColor: Colors.white10,
           valueColor: const AlwaysStoppedAnimation(Colors.blueAccent),
           minHeight: 4,
        ),
      ),
    );
  }
}
