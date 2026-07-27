/// Lifecycle state of an asynchronous job (video, transcription, tool task).
///
/// The API uses several vocabularies across endpoints; [JobStatus.parse] maps
/// all of them onto this enum while [JobStatus.raw] keeps the original string.
enum JobStatus {
  queued,
  inProgress,
  completed,
  failed,
  cancelled,

  /// A status this SDK does not recognise. Treated as "keep polling".
  unknown;

  /// Whether the job reached a final state.
  bool get isTerminal =>
      this == completed || this == failed || this == cancelled;

  /// Whether the job finished successfully.
  bool get isSuccess => this == completed;

  static JobStatus parse(String? value) {
    switch (value?.toLowerCase().replaceAll('-', '_')) {
      case 'queued':
      case 'pending':
      case 'created':
      case 'waiting':
      case 'submitted':
        return JobStatus.queued;
      case 'in_progress':
      case 'inprogress':
      case 'processing':
      case 'running':
      case 'started':
        return JobStatus.inProgress;
      case 'completed':
      case 'complete':
      case 'succeeded':
      case 'success':
      case 'finished':
      case 'done':
        return JobStatus.completed;
      case 'failed':
      case 'failure':
      case 'error':
        return JobStatus.failed;
      case 'cancelled':
      case 'canceled':
      case 'aborted':
        return JobStatus.cancelled;
      default:
        return JobStatus.unknown;
    }
  }
}
