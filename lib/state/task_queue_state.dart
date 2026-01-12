import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

enum TaskStatus { pending, running, success, error }

class BgTask {
  final String id;
  final String name; // e.g. "Saving IMG_001.jpg"
  final double progress; // 0.0 to 1.0
  final TaskStatus status;
  final String? errorMessage;
  
  const BgTask({
    required this.id,
    required this.name,
    this.progress = 0.0,
    this.status = TaskStatus.pending,
    this.errorMessage,
  });
  
  BgTask copyWith({
    String? name,
    double? progress,
    TaskStatus? status,
    String? errorMessage,
  }) {
    return BgTask(
      id: this.id,
      name: name ?? this.name,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class TaskQueueNotifier extends StateNotifier<List<BgTask>> {
  TaskQueueNotifier() : super([]);
  
  final Map<String, Future<void> Function(String id)> _taskFunctions = {};
  int _runningCount = 0;
  final int _maxConcurrency = 2; // Limit parallel tasks to prevent freeze

  String addTask(String name, Future<void> Function(String id) execution) {
    final id = const Uuid().v4();
    final task = BgTask(id: id, name: name, status: TaskStatus.pending);
    state = [...state, task];
    
    _taskFunctions[id] = execution;
    _checkQueue();
    
    return id;
  }

  void updateTask(String id, {double? progress, TaskStatus? status, String? error}) {
    // If status is terminal, we can remove function and check queue
    bool isTerminal = false;
    if (status == TaskStatus.success || status == TaskStatus.error) {
       isTerminal = true;
    }

    state = state.map((t) {
      if (t.id == id) {
        return t.copyWith(
           progress: progress,
           status: status,
           errorMessage: error
        );
      }
      return t;
    }).toList();
    
    if (isTerminal) {
       _runningCount--;
       _taskFunctions.remove(id);
       _checkQueue();
       
       // Auto-remove success from list after delay? No, cleaner to let UI decide or auto-cleanup later.
       // But to keep list clean for now:
       if (status == TaskStatus.success) {
           Future.delayed(const Duration(seconds: 4), () => removeTask(id));
       }
    }
  }
  
  void removeTask(String id) {
     state = state.where((t) => t.id != id).toList();
  }
  
  void _checkQueue() {
     if (_runningCount >= _maxConcurrency) return;
     
     // Find next pending
     try {
       final pending = state.firstWhere((t) => t.status == TaskStatus.pending);
       _runTask(pending.id);
     } catch (_) {
       // No pending tasks
     }
  }
  
  Future<void> _runTask(String id) async {
     if (_runningCount >= _maxConcurrency) return;
     _runningCount++;
     
     // Update status to running
     state = state.map((t) => t.id == id ? t.copyWith(status: TaskStatus.running) : t).toList();
     
     final func = _taskFunctions[id];
     if (func != null) {
        try {
           await func(id);
           // Func should call updateTask(success) itself? 
           // Or we handle it here?
           // The caller (ImageEditor) calls updateTask.
           // BUT if the caller crashes, we might hang.
           // Ideally, caller logic runs, and WE handle the state?
           // CURRENT ARCHITECTURE: ImageEditor calls updateTask.
           // I will force a check here just in case? 
           // No, let's rely on _checkQueue triggering when updateTask sets success.
        } catch (e) {
             updateTask(id, status: TaskStatus.error, error: e.toString());
        }
     } else {
        // Error?
        _runningCount--;
        _checkQueue();
     }
  }

  // Clear finished tasks
  void clearCompleted() {
     state = state.where((t) => t.status == TaskStatus.pending || t.status == TaskStatus.running).toList();
  }
}

final taskQueueProvider = StateNotifierProvider<TaskQueueNotifier, List<BgTask>>((ref) {
  return TaskQueueNotifier();
});
