import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_helper.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage> {
  TimeOfDay selectedTime = TimeOfDay.now();
  int selectedPump = 1;
  int duration = 5;
Future<String> getIP() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString("esp32_ip") ?? "192.168.4.1";
}
  List schedules = [];
  @override
  void initState() {
    super.initState();
    loadSchedule();
  }

  // ================= LOAD =================
  Future loadSchedule() async {
    final db = await DatabaseHelper.instance.database;

    schedules = await db.query(
      "schedule",
      orderBy: "hour ASC, minute ASC",
    );

    if (!mounted) return;
    setState(() {});
  }

  // ================= ADD =================
  Future addSchedule() async {
    final db = await DatabaseHelper.instance.database;

    // check duplicate
    final exist = await db.query(
      "schedule",
      where: "pump=? AND hour=? AND minute=?",
      whereArgs: [selectedPump, selectedTime.hour, selectedTime.minute],
    );

    if (exist.isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⚠️ Lịch này đã tồn tại")),
      );
      return;
    }

    await db.insert("schedule", {
  "pump": selectedPump,
  "hour": selectedTime.hour,
  "minute": selectedTime.minute,
  "duration": duration,
  "is_enabled": 1,
});
await sendScheduleToESP();

loadSchedule();
 if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text("✅ Đã lưu lịch tưới"),
      backgroundColor: Colors.green,
      duration: Duration(seconds: 2),
    ),
  );
}
Future sendScheduleToESP() async {
  try {
    final ip = await getIP();

    final url = Uri.parse(
      "http://$ip/addSchedule"
      "?pump=$selectedPump"
      "&hour=${selectedTime.hour}"
      "&minute=${selectedTime.minute}"
      "&duration=$duration"
    );

    final res = await http.get(url).timeout(const Duration(seconds: 5));

    if (res.statusCode == 200) {
      print("✅ Gửi lịch OK");
    } else {
      print("❌ ESP lỗi: ${res.body}");
    }
  } catch (e) {
    print("❌ Lỗi gửi ESP: $e");
  }
}
  // ================= TOGGLE ENABLE =================
  Future toggleSchedule(int id, int value) async {
    final db = await DatabaseHelper.instance.database;
    await db.update(
      "schedule",
      {"is_enabled": value},
      where: "id = ?",
      whereArgs: [id],
    );
    loadSchedule();
  }

  // ================= DELETE =================
  Future deleteSchedule(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete("schedule", where: "id = ?", whereArgs: [id]);
    loadSchedule();
  }

  Future confirmDelete(int id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Xoá lịch?"),
        content: const Text("Bạn có chắc muốn xoá lịch này không?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Huỷ"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Xoá"),
          ),
        ],
      ),
    );

    if (ok == true) {
      deleteSchedule(id);
    }
  }

  // ================= FORMAT =================
  String formatTime(int h, int m) {
    return "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}";
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Lập lịch tưới"),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 10),

            // ===== CARD TẠO LỊCH =====
            card(
              "Tạo lịch tưới",
              Column(
                children: [
                  // chọn giờ
                  ListTile(
                    leading: const Icon(Icons.access_time),
                    title: Text("Giờ: ${selectedTime.format(context)}"),
                    trailing: ElevatedButton(
                      onPressed: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: selectedTime,
                        );

                        if (time != null) {
                          setState(() {
                            selectedTime = time;
                          });
                        }
                      },
                      child: const Text("Chọn"),
                    ),
                  ),

                  // chọn bơm
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [1, 2, 3].map((e) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        child: ChoiceChip(
                          label: Text("Bơm $e"),
                          selected: selectedPump == e,
                          onSelected: (_) {
                            setState(() {
                              selectedPump = e;
                            });
                          },
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 10),

                  // duration
                  Column(
                    children: [
                      Text("Thời gian: $duration phút"),
                      Slider(
                        value: duration.toDouble(),
                        min: 1,
                        max: 60,
                        divisions: 59,
                        onChanged: (v) {
                          setState(() {
                            duration = v.toInt();
                          });
                        },
                      ),
                    ],
                  ),

                  ElevatedButton(
                    onPressed: addSchedule,
                    child: const Text("Lưu lịch"),
                  ),
                ],
              ),
            ),

            // ===== DANH SÁCH =====
            card(
              "Danh sách lịch",
              schedules.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: Text("Chưa có lịch"),
                    )
                  : Column(
                      children: schedules.map((e) {
                        final enabled = (e["is_enabled"] ?? 1) == 1;
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.schedule, color: Colors.blue),
                              const SizedBox(width: 10),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      "Bơm ${e["pump"]}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      "${formatTime(e["hour"], e["minute"])} • ${e["duration"]} phút",
                                    ),
                                  ],
                                ),
                              ),

                              Switch(
                                value: enabled,
                                onChanged: (v) {
                                  toggleSchedule(e["id"], v ? 1 : 0);
                                },
                              ),

                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () {
                                  confirmDelete(e["id"]);
                                },
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ================= CARD =================
  Widget card(String title, Widget child) {
    return Container(
      margin: const EdgeInsets.all(10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 5)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}