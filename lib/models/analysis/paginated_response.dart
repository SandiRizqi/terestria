/// Wrapper generik untuk response list ber-pagination dari palmanalisis.
///
/// Bentuk: `{success, page, page_size, total_pages, total_count, data:[...]}`.
/// `page_size` default 10, maksimum 100.
class PaginatedResponse<T> {
  final bool success;
  final int page;
  final int pageSize;
  final int totalPages;
  final int totalCount;
  final List<T> data;

  PaginatedResponse({
    required this.success,
    required this.page,
    required this.pageSize,
    required this.totalPages,
    required this.totalCount,
    required this.data,
  });

  /// Parse wrapper; tiap item `data` dipetakan lewat [itemParser].
  factory PaginatedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic item) itemParser,
  ) {
    final rawList = json['data'] as List<dynamic>? ?? const [];
    return PaginatedResponse<T>(
      success: json['success'] as bool? ?? true,
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['page_size'] as num?)?.toInt() ?? 10,
      totalPages: (json['total_pages'] as num?)?.toInt() ?? 1,
      totalCount: (json['total_count'] as num?)?.toInt() ?? 0,
      data: rawList.map(itemParser).toList(),
    );
  }

  /// True bila masih ada halaman berikutnya.
  bool get hasMore => page < totalPages;
}
