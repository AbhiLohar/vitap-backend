import 'dart:convert';

void main() {
  String jsonStr = '{"curriculum": {"summary": {"earned": "10", "total": "160", "left": "150"}, "distribution": []}}';
  final data = jsonDecode(jsonStr);
  Map<String, dynamic> map = {};
  
  if (data is Map<String, dynamic>) {
    print("data is Map<String, dynamic>");
    if (data.keys.length == 1) {
      print("keys length is 1");
      if (data.values.first is Map<String, dynamic>) {
        print("data.values.first is Map<String, dynamic>");
        map = data.values.first as Map<String, dynamic>;
      } else {
        print("data.values.first is NOT Map<String, dynamic>, it is ${data.values.first.runtimeType}");
        map = data;
      }
    }
  }
  print(map);
}
