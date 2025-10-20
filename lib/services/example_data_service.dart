import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

/// Contoh service untuk mengambil data dengan token otomatis
/// 
/// File ini berisi contoh-contoh implementasi untuk berbagai endpoint
class ExampleDataService {
  final ApiService _apiService = ApiService();

  /// Contoh 1: GET request sederhana
  Future<List<dynamic>> fetchItems() async {
    try {
      final response = await _apiService.get('/api/items');
      
      if (_apiService.isSuccess(response)) {
        final data = jsonDecode(response.body);
        return data['results'] ?? data; // Sesuaikan dengan struktur response backend
      } else {
        throw Exception('Failed to fetch items: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching items: $e');
    }
  }

  /// Contoh 2: GET request dengan query parameters
  Future<Map<String, dynamic>> fetchItemById(int id) async {
    try {
      final response = await _apiService.get(
        '/api/items/$id',
        queryParameters: {
          'include_details': true,
          'format': 'json',
        },
      );
      
      return _apiService.parseResponse(response);
    } catch (e) {
      throw Exception('Error fetching item $id: $e');
    }
  }

  /// Contoh 3: POST request untuk create data
  Future<Map<String, dynamic>> createItem(Map<String, dynamic> itemData) async {
    try {
      final response = await _apiService.post(
        '/api/items',
        body: itemData,
      );
      
      return _apiService.parseResponse(response);
    } catch (e) {
      throw Exception('Error creating item: $e');
    }
  }

  /// Contoh 4: PUT request untuk update data
  Future<Map<String, dynamic>> updateItem(int id, Map<String, dynamic> itemData) async {
    try {
      final response = await _apiService.put(
        '/api/items/$id',
        body: itemData,
      );
      
      return _apiService.parseResponse(response);
    } catch (e) {
      throw Exception('Error updating item $id: $e');
    }
  }

  /// Contoh 5: DELETE request
  Future<bool> deleteItem(int id) async {
    try {
      final response = await _apiService.delete('/api/items/$id');
      return _apiService.isSuccess(response);
    } catch (e) {
      throw Exception('Error deleting item $id: $e');
    }
  }

  /// Contoh 6: GET dengan pagination
  Future<Map<String, dynamic>> fetchItemsPaginated({
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await _apiService.get(
        '/api/items',
        queryParameters: {
          'page': page,
          'page_size': pageSize,
        },
      );
      
      return _apiService.parseResponse(response);
    } catch (e) {
      throw Exception('Error fetching paginated items: $e');
    }
  }

  /// Contoh 7: Upload file
  Future<Map<String, dynamic>> uploadImage(String filePath) async {
    try {
      final response = await _apiService.uploadFile(
        '/api/upload',
        filePath: filePath,
        fileFieldName: 'image',
        fields: {
          'description': 'Uploaded from mobile app',
          'category': 'user_content',
        },
      );
      
      final responseBody = await response.stream.bytesToString();
      return jsonDecode(responseBody);
    } catch (e) {
      throw Exception('Error uploading image: $e');
    }
  }

  /// Contoh 8: GET dengan custom headers
  Future<List<dynamic>> fetchItemsWithCustomHeaders() async {
    try {
      final response = await _apiService.get(
        '/api/items',
        headers: {
          'X-Custom-Header': 'custom-value',
          'Accept-Language': 'id-ID',
        },
      );
      
      return _apiService.parseResponse(response)['results'];
    } catch (e) {
      throw Exception('Error fetching items with custom headers: $e');
    }
  }

  /// Contoh 9: Search dengan filter
  Future<List<dynamic>> searchItems({
    String? keyword,
    String? category,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      
      if (keyword != null && keyword.isNotEmpty) {
        queryParams['search'] = keyword;
      }
      if (category != null) {
        queryParams['category'] = category;
      }
      if (startDate != null) {
        queryParams['start_date'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        queryParams['end_date'] = endDate.toIso8601String();
      }
      
      final response = await _apiService.get(
        '/api/items/search',
        queryParameters: queryParams,
      );
      
      return _apiService.parseResponse(response)['results'];
    } catch (e) {
      throw Exception('Error searching items: $e');
    }
  }

  /// Contoh 10: Batch operation
  Future<Map<String, dynamic>> batchUpdateItems(List<Map<String, dynamic>> items) async {
    try {
      final response = await _apiService.post(
        '/api/items/batch-update',
        body: {
          'items': items,
          'update_type': 'bulk',
        },
      );
      
      return _apiService.parseResponse(response);
    } catch (e) {
      throw Exception('Error batch updating items: $e');
    }
  }
}

/// Contoh penggunaan di dalam Widget
/// 
/// ```dart
/// class MyDataWidget extends StatefulWidget {
///   @override
///   State<MyDataWidget> createState() => _MyDataWidgetState();
/// }
/// 
/// class _MyDataWidgetState extends State<MyDataWidget> {
///   final _dataService = ExampleDataService();
///   List<dynamic> _items = [];
///   bool _isLoading = false;
/// 
///   @override
///   void initState() {
///     super.initState();
///     _loadData();
///   }
/// 
///   Future<void> _loadData() async {
///     setState(() => _isLoading = true);
///     
///     try {
///       final items = await _dataService.fetchItems();
///       setState(() {
///         _items = items;
///         _isLoading = false;
///       });
///     } catch (e) {
///       setState(() => _isLoading = false);
///       ScaffoldMessenger.of(context).showSnackBar(
///         SnackBar(content: Text('Error: $e')),
///       );
///     }
///   }
/// 
///   @override
///   Widget build(BuildContext context) {
///     if (_isLoading) {
///       return Center(child: CircularProgressIndicator());
///     }
///     
///     return ListView.builder(
///       itemCount: _items.length,
///       itemBuilder: (context, index) {
///         return ListTile(
///           title: Text(_items[index]['name']),
///         );
///       },
///     );
///   }
/// }
/// ```
