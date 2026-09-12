/// Hasil preflight sebelum pull data dari server.
///
/// Alur: cek koneksi/server → tanya jumlah record (count_only) → putuskan.
/// UI yang memutuskan aksi: [offline]/[error] → pesan; [empty] → info "tidak
/// ada data"; [ready] → dialog konfirmasi (beri peringatan bila [warnLarge]).
enum PullPreflightStatus { offline, empty, ready, error }

class PullPreflightResult {
  final PullPreflightStatus status;
  final int count;
  final bool warnLarge; // count melewati ambang (mis. > 1000)
  final String? message;

  const PullPreflightResult(
    this.status, {
    this.count = 0,
    this.warnLarge = false,
    this.message,
  });
}
