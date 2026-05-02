import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'database_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String ip = "192.168.4.1";

  double temp = 0;
  double hum = 0;

  int soil1 = 0;
  int soil2 = 0;
  int soil3 = 0;

  int soil1Raw = 0;
  int soil2Raw = 0;
  int soil3Raw = 0;

  bool pump1 = false;
  bool pump2 = false;
  bool pump3 = false;

  bool lastPump1 = false;
  bool lastPump2 = false;
  bool lastPump3 = false;

  double tempMax = -999;
  double tempMin = 999;
  double humMax = -999;
  double humMin = 999;

  late Timer scheduleTimer;
  late Timer pollTimer;
  late Timer weatherTimer;
  late Timer autoWateringTimer;

  bool autoMode = false;
  int notificationCount = 0;

  DateTime? lastSensorLogAt;

  bool soil1Dry = false;
  bool soil2Dry = false;
  bool soil3Dry = false;
  bool tempHigh = false;
  List<Map<String, dynamic>> sensors = [];
  List<Map<String, dynamic>> sensorConfigs = [];
  Set<String> executedKey = {};
  Set<String> wateringNow = {}; // ✅ FIX 2: Chuyển từ local sang class variable

  // ===== Weather + Telegram =====
  String weatherCity = "Đà Nẵng";
  double? weatherLat;
  double? weatherLon;

  String telegramToken = "";
  String telegramChatId = "";

  DateTime? lastWeatherCheck;
  bool rainSoonCache = false;
  DateTime? lastRainAlertAt;

  String getTempStatus() {
    if (temp >= 35) return "🔥 Nóng";
    if (temp <= 20) return "❄️ Lạnh";
    return "🌿 Bình thường";
  }

  String getHumStatus() {
    if (hum >= 85) return "💦 Ẩm cao";
    if (hum <= 40) return "🏜 Khô";
    return "👌 Bình thường";
  }

  @override
  void initState() {
    super.initState();
    loadNotificationCount();
    loadConfig();
    loadSensorConfig();

    pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => fetchData());
    scheduleTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      checkSchedule();
    });
    
    // ✅ FIX 3: Lưu timer autoWatering vào biến class
    autoWateringTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (autoMode) autoWatering();
    });
    
    weatherTimer = Timer.periodic(const Duration(minutes: 30), (_) {
      checkWeatherAlert();
    });
  }

  @override
  void dispose() {
    scheduleTimer.cancel();
    pollTimer.cancel();
    weatherTimer.cancel();
    autoWateringTimer.cancel(); // ✅ FIX 3: Cancel timer này
    super.dispose();
  }

  void showRaw(String name, int raw) {
    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: Text("$name (RAW)"),
            content: Text("Giá trị thô: $raw"),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Đóng"),
              ),
            ],
          ),
    );
  }

  void showMappingDialog() {
    showDialog(
      context: context,
      builder: (_) {
        String? selectedSensor;
        int selectedPump = 1;
        int threshold = 30;

        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Mapping Sensor → Pump"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<String>(
                    hint: const Text("Chọn sensor"),
                    value: selectedSensor,
                    items:
                        sensors.map<DropdownMenuItem<String>>((s) {
                          return DropdownMenuItem<String>(
                            value: s["id"].toString(),
                            child: Text(s["id"].toString()),
                          );
                        }).toList(),
                    onChanged: (v) {
                      setStateDialog(() {
                        selectedSensor = v;
                      });
                    },
                  ),

                  DropdownButton<int>(
                    value: selectedPump,
                    items:
                        [1, 2, 3].map((p) {
                          return DropdownMenuItem<int>(
                            value: p,
                            child: Text("Pump $p"),
                          );
                        }).toList(),
                    onChanged: (v) {
                      setStateDialog(() {
                        selectedPump = v!;
                      });
                    },
                  ),

                  TextField(
                    decoration: const InputDecoration(labelText: "Ngưỡng (%)"),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => threshold = int.tryParse(v) ?? 30,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    if (selectedSensor == null) return;

                    final db = await DatabaseHelper.instance.database;

                    await db.insert("sensor_pump_map", {
                      "sensor_id": selectedSensor,
                      "pump": selectedPump,
                      "threshold": threshold,
                    });

                    Navigator.pop(context);
                  },
                  child: const Text("Lưu"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      ip = prefs.getString("esp32_ip") ?? "192.168.4.1";
      weatherCity = prefs.getString("weather_city") ?? "Đà Nẵng";
      weatherLat = prefs.getDouble("weather_lat");
      weatherLon = prefs.getDouble("weather_lon");
      telegramToken = prefs.getString("telegram_token") ?? "";
      telegramChatId = prefs.getString("telegram_chat_id") ?? "";
    });
  }

  Future<void> loadSensorConfig() async {
    final db = await DatabaseHelper.instance.database;
    final data = await db.query("sensor_config");

    setState(() {
      sensorConfigs = data;
    });
  }

  // ✅ FIX 5: Hàm cleanup executedKey cũ
  void _cleanOldExecutedKeys() {
    final now = DateTime.now();
    executedKey.removeWhere((key) {
      try {
        // Key format: "${id}_${year}-${month}-${day}-${hour}-${minute}"
        final parts = key.split('_');
        if (parts.length < 2) return true;
        
        final dateParts = parts[1].split('-');
        if (dateParts.length < 5) return true;
        
        final year = int.parse(dateParts[0]);
        final month = int.parse(dateParts[1]);
        final day = int.parse(dateParts[2]);
        final keyTime = DateTime(year, month, day);
        
        // Xóa key cũ hơn 1 ngày
        return now.difference(keyTime).inDays > 1;
      } catch (e) {
        return true;
      }
    });
  }

  // ================= WEATHER =================
  Future<int> getRainProbability() async {
    if (weatherLat == null || weatherLon == null) return 0;

    final now = DateTime.now();

    // Check cache (15 phút)
    if (lastWeatherCheck != null &&
        now.difference(lastWeatherCheck!) < const Duration(minutes: 15)) {
      return rainSoonCache ? 100 : 0;
    }

    final url =
        "https://api.open-meteo.com/v1/forecast?latitude=$weatherLat&longitude=$weatherLon&hourly=precipitation_probability&forecast_days=1&timezone=auto";

    try {
      print("🌧 Fetching rain probability...");
      final res = await http
          .get(Uri.parse(url))
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

      int maxProb = 0;

      // Check 3 giờ tới
      for (int i = 0; i < times.length && i < probs.length; i++) {
        try {
          final t = DateTime.parse(times[i]);
          final diff = t.difference(now).inHours;

          if (diff >= 0 && diff <= 3) {
            final p = probs[i];
            if (p > maxProb) {
              maxProb = p;
            }
          }
        } catch (e) {
          print("⚠️ Error parsing time: $e");
          continue;
        }
      }

      lastWeatherCheck = now;
      rainSoonCache = maxProb >= 70;

      print("✅ Max rain probability: $maxProb%");
      return maxProb;
    } catch (e) {
      print("❌ Error: $e");
      return 0;
    }
  }

  Future<bool> isRainSoon() async {
    final prob = await getRainProbability();
    return prob >= 50;
  }

  Future<void> checkWeatherAlert() async {
    final rainSoon = await isRainSoon();
    if (!rainSoon) return;

    if (lastRainAlertAt != null &&
        DateTime.now().difference(lastRainAlertAt!) <
            const Duration(hours: 3)) {
      return;
    }

    await pushNotification(
      "🌧 Sắp mưa",
      "Dự báo mưa trong 3 giờ tới tại $weatherCity. Tạm ngưng tưới.",
    );
    lastRainAlertAt = DateTime.now();
  }

  // ================= TELEGRAM =================
  Future<void> sendTelegram(String title, String content) async {
    if (telegramToken.isEmpty || telegramChatId.isEmpty) return;
    try {
      final url = "https://api.telegram.org/bot$telegramToken/sendMessage";
      await http.post(
        Uri.parse(url),
        body: {"chat_id": telegramChatId, "text": "$title\n$content"},
      ).timeout(const Duration(seconds: 5));
    } catch (e) {
      print("❌ Telegram error: $e");
    }
  }

  Future<void> pushNotification(String title, String content) async {
    final db = await DatabaseHelper.instance.database;
    await db.insert("notification", {
      "title": title,
      "content": content,
      "time": DateTime.now().toString(),
    });
    await sendTelegram(title, content);
    await loadNotificationCount();
  }

  // ================= HTTP FETCH =================
  Future<void> fetchData() async {
    try {
      final res = await http
          .get(Uri.parse("http://$ip/data"))
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        await handleTelemetry(res.body);
      }
    } catch (e) {
      print("❌ Fetch error: $e");
    }
  }

  // ================= HANDLE DATA =================
  Future<void> handleTelemetry(String payload) async {
    try {
      final data = jsonDecode(payload);

      // ✅ FIX 6: Validate dữ liệu trước khi dùng
      final newTemp = _toDouble(data["temp"], 0);
      final newHum = _toDouble(data["hum"], 0);
      final newSoil1 = _toInt(data["soil1"], 0);
      final newSoil2 = _toInt(data["soil2"], 0);
      final newSoil3 = _toInt(data["soil3"], 0);
      final newSoil1Raw = _toInt(data["soil1_raw"], 0);
      final newSoil2Raw = _toInt(data["soil2_raw"], 0);
      final newSoil3Raw = _toInt(data["soil3_raw"], 0);

      final newPump1 = _toBool(data["r1"]);
      final newPump2 = _toBool(data["r2"]);
      final newPump3 = _toBool(data["r3"]);

      if (lastPump1 != newPump1) await handlePumpLog(1, lastPump1, newPump1);
      if (lastPump2 != newPump2) await handlePumpLog(2, lastPump2, newPump2);
      if (lastPump3 != newPump3) await handlePumpLog(3, lastPump3, newPump3);

      if (newTemp > tempMax) tempMax = newTemp;
      if (newTemp < tempMin) tempMin = newTemp;
      if (newHum > humMax) humMax = newHum;
      if (newHum < humMin) humMin = newHum;

      lastPump1 = newPump1;
      lastPump2 = newPump2;
      lastPump3 = newPump3;

      if (!mounted) return;

      // ✅ FIX 1: Gộp tất cả setState thành 1
      setState(() {
        temp = newTemp;
        hum = newHum;
        soil1 = newSoil1;
        soil2 = newSoil2;
        soil3 = newSoil3;
        soil1Raw = newSoil1Raw;
        soil2Raw = newSoil2Raw;
        soil3Raw = newSoil3Raw;

        pump1 = newPump1;
        pump2 = newPump2;
        pump3 = newPump3;

        // ✅ FIX 6: Validate và convert sensors
        if (data["sensors"] != null && data["sensors"] is List) {
          try {
            sensors = (data["sensors"] as List)
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList();
          } catch (e) {
            print("⚠️ Sensors parsing error: $e");
            sensors = [];
          }
        } else {
          sensors = [];
        }
      });

      // ===== Nhiệt độ cao =====
      bool newTempHigh = newTemp > 35;
      if (newTempHigh && !tempHigh) {
        await pushNotification("🌡 Nhiệt độ cao", "Nhiệt độ: $newTemp°C");
      }
      tempHigh = newTempHigh;

      // ===== Đất khô (theo %) =====
      bool newSoil1Dry = newSoil1 <= 30;
      if (newSoil1Dry && !soil1Dry) {
        await pushNotification("🌱 Đất khô (Soil 1)", "Độ ẩm: $newSoil1%");
      }
      soil1Dry = newSoil1Dry;

      bool newSoil2Dry = newSoil2 <= 30;
      if (newSoil2Dry && !soil2Dry) {
        await pushNotification("🌱 Đất khô (Soil 2)", "Độ ẩm: $newSoil2%");
      }
      soil2Dry = newSoil2Dry;

      bool newSoil3Dry = newSoil3 <= 30;
      if (newSoil3Dry && !soil3Dry) {
        await pushNotification("🌱 Đất khô (Soil 3)", "Độ ẩm: $newSoil3%");
      }
      soil3Dry = newSoil3Dry;

      // ===== Lưu sensor mỗi 30s =====
      final now = DateTime.now();
      if (lastSensorLogAt == null ||
          now.difference(lastSensorLogAt!) >= const Duration(seconds: 30)) {
        final db = await DatabaseHelper.instance.database;
        await db.insert("sensor", {
          "temp": newTemp,
          "hum": newHum,
          "soil1": newSoil1,
          "soil2": newSoil2,
          "soil3": newSoil3,
          "time": now.toString(),
        });
        lastSensorLogAt = now;
      }
    } catch (e) {
      print("❌ ERROR handleTelemetry: $e");
    }
  }

  // ✅ FIX 6: Helper functions để validate dữ liệu
  double _toDouble(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  int _toInt(dynamic value, int defaultValue) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? defaultValue;
    return defaultValue;
  }

  bool _toBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is int) return value == 1;
    if (value is String) return value.toLowerCase() == 'true' || value == '1';
    return false;
  }

  // ================= TOGGLE =================
  Future togglePump(int r) async {
    if (r < 0 || r > 2) {
      print("❌ Invalid pump index: $r");
      return;
    }

    try {
      bool current =
          (r == 0 && pump1) || (r == 1 && pump2) || (r == 2 && pump3);

      bool willTurnOn = !current;

      // 👉 CHỈ check khi bật
      if (willTurnOn) {
        final rainProb = await getRainProbability();

        if (rainProb >= 50) {
          bool? confirm = await showDialog<bool>(
            context: context,
            builder:
                (context) => AlertDialog(
                  title: const Text("🌧 Cảnh báo thời tiết"),
                  content: Text(
                    "3 giờ tới tại $weatherCity có thể mưa ($rainProb%).\nBạn vẫn muốn bật bơm?",
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text("HỦY"),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text("VẪN BẬT"),
                    ),
                  ],
                ),
          );

          if (!(confirm ?? false)) return;
        }
      }

      // ✅ FIX 4: Gửi request và kiểm tra response
      try {
        final res = await http
            .get(Uri.parse("http://$ip/toggle?r=$r"))
            .timeout(const Duration(seconds: 5));

        if (res.statusCode != 200) {
          print("⚠️ Toggle failed: ${res.statusCode}");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("❌ Lỗi kết nối thiết bị")),
            );
          }
          return;
        }
      } catch (e) {
        print("❌ Toggle HTTP error: $e");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ Lỗi: $e")),
          );
        }
        return;
      }

      // 👉 update UI chỉ khi request thành công
      if (mounted) {
        setState(() {
          if (r == 0) pump1 = !pump1;
          if (r == 1) pump2 = !pump2;
          if (r == 2) pump3 = !pump3;
        });
      }
    } catch (e) {
      print("❌ ERROR toggle: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Lỗi: $e")),
        );
      }
    }
  }

  // ================= LOG =================
  Future<void> handlePumpLog(int pump, bool oldState, bool newState) async {
    final db = await DatabaseHelper.instance.database;

    if (oldState == newState) return;

    if (!oldState && newState) {
      final exist = await db.query(
        "pump_log",
        where: "pump = ? AND end IS NULL",
        whereArgs: [pump],
      );

      if (exist.isNotEmpty) return;

      await db.insert("pump_log", {
        "pump": pump,
        "start": DateTime.now().toString(),
        "end": null,
      });
    }

    if (oldState && !newState) {
      await db.update(
        "pump_log",
        {"end": DateTime.now().toString()},
        where: "pump = ? AND end IS NULL",
        whereArgs: [pump],
      );
    }
  }

  // ✅ FIX 2: Sử dụng wateringNow từ class variable
  Future<void> autoWatering() async {
    final db = await DatabaseHelper.instance.database;
    final maps = await db.query("sensor_pump_map");

    for (var m in maps) {
      try {
        String sensorId = m["sensor_id"] as String;
        int pump = m["pump"] as int;
        int threshold = m["threshold"] as int;

        // ✅ FIX 6: Validate pump index
        if (pump < 1 || pump > 3) {
          print("⚠️ Invalid pump in mapping: $pump");
          continue;
        }

        // tìm sensor tương ứng
        final sensor = sensors.firstWhere(
          (s) => s["id"] == sensorId,
          orElse: () => {},
        );

        int value = sensor["value"] ?? -1;

        if (value != -1 && value <= threshold) {
          if (wateringNow.contains(sensorId)) continue;

          wateringNow.add(sensorId);
          print("🚰 Auto watering Pump $pump for $sensorId");

          // ✅ FIX 6: Convert pump (1,2,3) to index (0,1,2)
          await togglePump(pump - 1);

          Future.delayed(const Duration(minutes: 2), () async {
            await togglePump(pump - 1);
            wateringNow.remove(sensorId);
            print("✅ Auto watering stopped for $sensorId");
          });
        }
      } catch (e) {
        print("❌ Auto watering error: $e");
      }
    }
  }

  Future loadNotificationCount() async {
    final db = await DatabaseHelper.instance.database;
    final data = await db.query("notification");
    if (mounted) {
      setState(() {
        notificationCount = data.length;
      });
    }
  }

  // ================= SCHEDULE =================
  // ✅ FIX 5: Thêm timeout và cleanup
  Future checkSchedule() async {
    try {
      _cleanOldExecutedKeys(); // Cleanup mỗi lần check

      final db = await DatabaseHelper.instance.database;
      final now = DateTime.now();

      final schedules = await db.query("schedule");
      for (var s in schedules) {
        try {
          int id = s["id"] as int;
          int hour = s["hour"] as int;
          int minute = s["minute"] as int;

          if (hour == now.hour && minute == now.minute) {
            String key =
                "${id}_${now.year}-${now.month}-${now.day}-${now.hour}-${now.minute}";
            if (executedKey.contains(key)) continue;
            executedKey.add(key);

            // Check rain trước khi chạy schedule
            final rainProb = await getRainProbability();
            if (rainProb >= 50) {
              print("⚠️ Schedule skipped due to rain ($rainProb%)");
              await pushNotification(
                "⛔ Schedule hủy",
                "Lịch bơm bị hủy vì có khả năng mưa ($rainProb%)",
              );
              continue;
            }

            int pump = s["pump"] as int;
            int duration = s["duration"] as int;

            // ✅ FIX 6: Validate pump
            if (pump < 1 || pump > 3) {
              print("⚠️ Invalid pump in schedule: $pump");
              continue;
            }

            await http.get(Uri.parse("http://$ip/mode?m=manual"))
                .timeout(const Duration(seconds: 5));

            await togglePump(pump - 1);
            Future.delayed(Duration(minutes: duration), () async {
              await togglePump(pump - 1);
            });
          }
        } catch (e) {
          print("❌ Schedule item error: $e");
        }
      }
    } catch (e) {
      print("❌ checkSchedule error: $e");
    }
  }

  // ================= UI =================
  Widget soilItem(String title, int value) {
    return Column(
      children: [
        Text(title),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            "$value",
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ),
      ],
    );
  }

  Widget card({String? title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null)
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          if (title != null) const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget pumpCard(String title, bool isOn, VoidCallback onTap) {
    return GestureDetector(
      onTap: autoMode ? null : onTap,
      child: AnimatedScale(
        scale: isOn ? 1.05 : 1,
        duration: const Duration(milliseconds: 200),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          decoration: BoxDecoration(
            color: isOn ? Colors.green : Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: isOn ? Colors.green.withOpacity(0.4) : Colors.black12,
                blurRadius: 10,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedRotation(
                turns: isOn ? 1 : 0,
                duration: const Duration(seconds: 1),
                child: Icon(
                  Icons.water_drop,
                  size: 20,
                  color: isOn ? Colors.white : Colors.grey,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(
                  color: isOn ? Colors.white : Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                isOn ? "ON" : "OFF",
                style: TextStyle(color: isOn ? Colors.white : Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget sceneButton(String title, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(right: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
          ),
          child: Center(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ),
    );
  }

  Widget sensorCard(String icon, String title, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 5),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
        ),
        child: Column(
          children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 5),
            Text(title),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
      ),
    );
  }

  Widget soilCard(String title, int value, int raw) {
    return Expanded(
      child: GestureDetector(
        onTap: () => showRaw(title, raw),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
          ),
          child: Column(
            children: [
              Text(title),
              const SizedBox(height: 5),
              Text(
                "$value%",
                style: const TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                "Nhấn để xem RAW",
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget pumpRow(String title, bool isOn, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isOn ? Colors.green[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          Switch(
            value: isOn,
            onChanged: autoMode ? null : (_) => onTap(),
            activeColor: Colors.green,
          ),
          Text(
            isOn ? "ON" : "OFF",
            style: TextStyle(
              color: isOn ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget sensorItem(String icon, String title, String value) {
    return Column(
      children: [
        Text(icon, style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 5),
        Text(title),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget addSensorCard() {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (_) {
            TextEditingController nameController = TextEditingController();

            return AlertDialog(
              title: const Text("Thêm cảm biến"),
              content: TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  hintText: "Tên cảm biến (VD: Chậu lan)",
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Hủy"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    String name = nameController.text;

                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("⚠️ Vui lòng nhập tên cảm biến")),
                      );
                      return;
                    }

                    final db = await DatabaseHelper.instance.database;
                    await db.insert("sensor_config", {
                      "name": name,
                      "created_at": DateTime.now().toString(),
                    });
                    await loadSensorConfig();
                    if (mounted) {
                      Navigator.pop(context);
                    }
                  },
                  child: const Text("Lưu"),
                ),
              ],
            );
          },
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blue),
        ),
        child: const Center(
          child: Text(
            "+ Thêm cảm biến",
            style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  Widget detailWeatherCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Chi tiết thời tiết",
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              // ===== NHIỆT ĐỘ =====
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "🌡 ${temp.toStringAsFixed(1)}°C",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text("⬆ Max: ${tempMax.toStringAsFixed(1)}°C"),
                    Text("⬇ Min: ${tempMin.toStringAsFixed(1)}°C"),
                    const SizedBox(height: 6),
                    Text(getTempStatus()),
                  ],
                ),
              ),

              const SizedBox(width: 10),

              // ===== ĐỘ ẨM =====
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "💧 ${hum.toStringAsFixed(0)}%",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text("⬆ Max: ${humMax.toStringAsFixed(0)}%"),
                    Text("⬇ Min: ${humMin.toStringAsFixed(0)}%"),
                    const SizedBox(height: 6),
                    Text(getHumStatus()),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ================= BUILD =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff5f7fb),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ===== HEADER =====
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors:
                        rainSoonCache
                            ? [Colors.orange, Colors.deepOrange]
                            : [Color(0xff4CAF50), Color(0xff2E7D32)],
                  ),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      weatherCity,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      "${temp.toStringAsFixed(1)}°C",
                      style: const TextStyle(
                        fontSize: 34,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      "💧 $hum%",
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      rainSoonCache ? "🌧 Sắp mưa" : "☀️ Thời tiết ổn",
                      style: const TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ===== MODE SWITCH =====
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Chế độ",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Switch(
                    value: !autoMode,
                    onChanged: (val) async {
                      bool newManual = val;
                      setState(() {
                        autoMode = !newManual;
                      });
                      String mode = autoMode ? "auto" : "manual";
                      try {
                        await http
                            .get(Uri.parse("http://$ip/mode?m=$mode"))
                            .timeout(const Duration(seconds: 5));
                      } catch (e) {
                        print("❌ Mode switch error: $e");
                      }
                    },
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // ===== DEVICE GRID =====
              Row(
                children: [
                  Expanded(
                    child: pumpCard("Pump 1", pump1, () => togglePump(0)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: pumpCard("Pump 2", pump2, () => togglePump(1)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: pumpCard("Pump 3", pump3, () => togglePump(2)),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // ===== SCENE =====
              const Text(
                "Kịch bản",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  sceneButton("🌿 Tưới nhanh", () async {
                    await togglePump(0);
                    await togglePump(1);
                    await togglePump(2);
                  }),
                  sceneButton("⛔ Tắt tất cả", () async {
                    if (pump1) await togglePump(0);
                    if (pump2) await togglePump(1);
                    if (pump3) await togglePump(2);
                  }),
                ],
              ),

              const SizedBox(height: 20),

              // ===== SENSOR =====
              const SizedBox(height: 20),
              detailWeatherCard(),

              const SizedBox(height: 15),

              Wrap(
                spacing: 10,
                runSpacing: 10,
                children:
                    sensors.map((s) {
                      bool isError = s["status"] == "error";
                      String sensorId = s["id"]?.toString() ?? "UNKNOWN";
                      int value = _toInt(s["value"], -1);
                      int raw = _toInt(s["raw"], 0);

                      return GestureDetector(
                        onTap: () => showRaw(sensorId, raw),
                        child: Container(
                          width: MediaQuery.of(context).size.width / 3 - 16,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isError ? Colors.red[50] : Colors.green[50],
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Column(
                            children: [
                              Text(
                                sensorId.toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                isError
                                    ? "LỖI ❌"
                                    : value >= 0
                                        ? "$value%"
                                        : "N/A",
                                style: TextStyle(
                                  color: isError ? Colors.red : Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 20),

              const SizedBox(height: 15),

              addSensorCard(),
            ],
          ),
        ),
      ),
    );
  }
}