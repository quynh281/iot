import 'package:flutter/material.dart';
import 'package:iot/database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key});

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _botTokenController = TextEditingController();
  final TextEditingController _chatIdController = TextEditingController();
  double moistureMin = 30;
  double moistureMax = 60;
  String savedIp = "";
  String savedCity = "";
  String savedLat = "";
  String savedLon = "";

  @override
  void initState() {
    super.initState();
    _loadConfig();
    _loadMoistureConfig();
  }

  Future<void> _loadMoistureConfig() async {
    final db = await DatabaseHelper.instance.database;

    final data = await db.query("config", limit: 1);

    if (data.isNotEmpty) {
      setState(() {
        moistureMin = (data[0]["min"] as num).toDouble();
        moistureMax = (data[0]["max"] as num).toDouble();
      });
    }
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString("esp32_ip") ?? "192.168.4.1";
    final city = prefs.getString("weather_city") ?? "Đà Nẵng";
    final lat = prefs.getDouble("weather_lat")?.toString() ?? "";
    final lon = prefs.getDouble("weather_lon")?.toString() ?? "";
    final token = prefs.getString("telegram_token") ?? "";
    final chatId = prefs.getString("telegram_chat_id") ?? "";

    setState(() {
      savedIp = ip;
      savedCity = city;
      savedLat = lat;
      savedLon = lon;

      _ipController.text = ip;
      _cityController.text = city;
      _botTokenController.text = token;
      _chatIdController.text = chatId;
    });
  }

  Future<Map<String, double>?> _getLatLon(String city) async {
    final url =
        "https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(city)}&count=1&language=vi&format=json";
    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) return null;

    final data = jsonDecode(res.body);
    if (data["results"] == null || data["results"].isEmpty) return null;

    final r = data["results"][0];
    return {
      "lat": (r["latitude"] ?? 0).toDouble(),
      "lon": (r["longitude"] ?? 0).toDouble(),
    };
  }

  Future<void> _saveConfig() async {
    final ip = _ipController.text.trim();
    final city = _cityController.text.trim();
    final token = _botTokenController.text.trim();
    final chatId = _chatIdController.text.trim();

    if (ip.isEmpty || city.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    final latLon = await _getLatLon(city);
    if (latLon == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Không tìm được thành phố")),
      );
      return;
    }

    await prefs.setString("esp32_ip", ip);
    await prefs.setString("weather_city", city);
    await prefs.setDouble("weather_lat", latLon["lat"]!);
    await prefs.setDouble("weather_lon", latLon["lon"]!);

    await prefs.setString("telegram_token", token);
    await prefs.setString("telegram_chat_id", chatId);
    final lat = latLon["lat"]!;
    final lon = latLon["lon"]!;
    final db = await DatabaseHelper.instance.database;

    // nếu chưa có thì insert, có rồi thì update
    final exist = await db.query("config");

    if (exist.isEmpty) {
      await db.insert("config", {
        "min": moistureMin,
        "max": moistureMax,
        "notify": 1,
      });
    } else {
      await db.update("config", {"min": moistureMin, "max": moistureMax});
    }
    setState(() {
      savedIp = ip;
      savedCity = city;
      savedLat = lat.toStringAsFixed(4);
      savedLon = lon.toStringAsFixed(4);
    });

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("✅ Đã lưu cấu hình")));
  }

  // ===== GET RAIN PROBABILITY (đúng logic) =====
  Future<int> _getRainProbability() async {
    final lat = double.tryParse(savedLat) ?? 0;
    final lon = double.tryParse(savedLon) ?? 0;

    if (lat == 0 || lon == 0) return 0;

    final api =
        "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&hourly=precipitation_probability&forecast_days=1&timezone=auto";

    try {
      print("🌧 Fetching rain probability...");
      final res = await http
          .get(Uri.parse(api))
          .timeout(const Duration(seconds: 5));

      if (res.statusCode != 200) {
        print("⚠️ Status: ${res.statusCode}");
        return 0;
      }

      final data = jsonDecode(res.body);
      final times = List<String>.from(data["hourly"]["time"] ?? []);
      final probs = List<int>.from(
        data["hourly"]["precipitation_probability"] ?? [],
      );

      final now = DateTime.now();
      int maxProb = 0;

      // Check 3 giờ tới (đúng logic)
      for (int i = 0; i < times.length; i++) {
        final t = DateTime.parse(times[i]);
        final diff = t.difference(now).inHours;

        if (diff >= 0 && diff <= 3) {
          final p = probs[i];
          if (p > maxProb) {
            maxProb = p;
          }
        }
      }

      print("✅ Max rain probability in next 3 hours: $maxProb%");
      return maxProb;
    } catch (e) {
      print("❌ Error: $e");
      return 0;
    }
  }

  Future<void> _checkRainNow() async {
    final token = _botTokenController.text.trim();
    final chatId = _chatIdController.text.trim();

    final lat = double.tryParse(savedLat) ?? 0;
    final lon = double.tryParse(savedLon) ?? 0;

    if (lat == 0 || lon == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("❌ Chưa có tọa độ")));
      return;
    }

    // Lấy xác suất mưa đúng cách
    final maxProb = await _getRainProbability();

    String msg;

    if (maxProb >= 70) {
      msg = "⛔ Khả năng mưa rất cao ($maxProb%) → nên tắt bơm";
    } else if (maxProb >= 50) {
      msg = "⚠️ Có thể mưa ($maxProb%) → cân nhắc";
    } else if (maxProb >= 30) {
      msg = "⚠️ Ít khả năng mưa ($maxProb%) → có thể tưới";
    } else {
      msg = "✅ Ít khả năng mưa ($maxProb%)";
    }

    // Gửi Telegram nếu có token
    if (token.isNotEmpty && chatId.isNotEmpty) {
      final url = "https://api.telegram.org/bot$token/sendMessage";
      try {
        await http.post(Uri.parse(url), body: {"chat_id": chatId, "text": msg});
      } catch (e) {
        print("❌ Telegram error: $e");
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _showRainConfirmDialog(int prob) async {
    return await showDialog<bool>(
          context: context,
          builder:
              (context) => AlertDialog(
                title: const Text("⚠️ Cảnh báo thời tiết"),
                content: Text(
                  "3 giờ tới có thể mưa ($prob%).\nBạn vẫn muốn bật bơm không?",
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text("HỦY"),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                    ),
                    child: const Text("VẪN BẬT"),
                  ),
                ],
              ),
        ) ??
        false;
  }

  Future<void> handlePumpWithConfirm(int relayIndex) async {
    final prob = await _getRainProbability();

    if (prob >= 50) {
      final confirm = await _showRainConfirmDialog(prob);
      if (!confirm) return;
    }

    try {
      await http.get(Uri.parse("http://$savedIp/toggle?r=$relayIndex"));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Không kết nối được ESP32")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("⚙️ Cấu hình"),
        backgroundColor: Colors.green,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ===== IP ESP32 =====
          const Text(
            "IP ESP32",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _ipController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              hintText: "VD: 192.168.4.1",
              prefixIcon: const Icon(Icons.router),
            ),
          ),
          const SizedBox(height: 16),

          // ===== WEATHER =====
          const Text(
            "Thành phố (Dự báo thời tiết)",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _cityController,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              hintText: "VD: Đà Nẵng",
              prefixIcon: const Icon(Icons.location_on),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              "📍 Tọa độ: $savedLat, $savedLon",
              style: const TextStyle(color: Colors.grey),
            ),
          ),

          const SizedBox(height: 20),
          // ===== TELEGRAM =====
          const Text(
            "Telegram Bot Token",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _botTokenController,
            obscureText: true,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              hintText: "BOT_TOKEN",
              prefixIcon: const Icon(Icons.key),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            "Telegram Chat ID",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _chatIdController,
            obscureText: true,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              hintText: "CHAT_ID",
              prefixIcon: const Icon(Icons.chat),
            ),
          ),

          const SizedBox(height: 24),

          // ===== ACTION BUTTONS =====
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saveConfig,
              icon: const Icon(Icons.save),
              label: const Text("LƯU CẤU HÌNH"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
          ),

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final token = _botTokenController.text.trim();
                final chatId = _chatIdController.text.trim();

                if (token.isEmpty || chatId.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("❌ Chưa nhập Token/Chat ID")),
                  );
                  return;
                }

                final url = "https://api.telegram.org/bot$token/sendMessage";
                try {
                  await http.post(
                    Uri.parse(url),
                    body: {
                      "chat_id": chatId,
                      "text": "✅ Test Telegram từ Smart Garden",
                    },
                  );

                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("✅ Đã gửi test Telegram"),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text("❌ Lỗi: $e")));
                }
              },
              icon: const Icon(Icons.send),
              label: const Text("TEST TELEGRAM"),
            ),
          ),

          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _checkRainNow,
              icon: const Icon(Icons.cloud),
              label: const Text("KIỂM TRA MƯA (THỦ CÔNG)"),
            ),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    _cityController.dispose();
    _botTokenController.dispose();
    _chatIdController.dispose();
    super.dispose();
  }
}