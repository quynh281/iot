import 'package:flutter/material.dart';
import 'database_helper.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  List sensorData = [];
  List pumpLogs = [];

  double avgTemp = 0;
  double avgHum = 0;

  double avgSoil1 = 0;
  double avgSoil2 = 0;
  double avgSoil3 = 0;

  Map<int, int> todayStats = {1: 0, 2: 0, 3: 0};
  bool showAllLogs = false;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final db = await DatabaseHelper.instance.database;

    sensorData = await db.query("sensor", orderBy: "id DESC", limit: 20);
    pumpLogs = await db.query("pump_log", orderBy: "id DESC", limit: 20);

    sensorData = sensorData.reversed.toList();

    if (sensorData.isNotEmpty) {
      avgTemp = _avg(sensorData, "temp");
      avgHum = _avg(sensorData, "hum");
      avgSoil1 = _avg(sensorData, "soil1");
      avgSoil2 = _avg(sensorData, "soil2");
      avgSoil3 = _avg(sensorData, "soil3");
    } else {
      avgTemp = avgHum = avgSoil1 = avgSoil2 = avgSoil3 = 0;
    }

    todayStats = await getTodayPumpStats();

    if (!mounted) return;
    setState(() {});
  }

  double _avg(List data, String key) {
    final sum = data.fold<double>(
      0.0,
      (p, e) => p + (e[key] ?? 0).toDouble(),
    );
    return sum / data.length;
  }

  Future<Map<int, int>> getTodayPumpStats() async {
    final db = await DatabaseHelper.instance.database;

    final today = DateTime.now();
    final startDay = DateTime(today.year, today.month, today.day);
    final endDay = startDay.add(const Duration(days: 1));

    final logs = await db.query(
      "pump_log",
      where: "start >= ? AND start < ?",
      whereArgs: [startDay.toString(), endDay.toString()],
    );

    Map<int, int> totalSeconds = {1: 0, 2: 0, 3: 0};

    for (var log in logs) {
      final s = DateTime.parse(log["start"] as String);
      final e = log["end"] != null
          ? DateTime.parse(log["end"] as String)
          : DateTime.now();

      final diff = e.difference(s).inSeconds;

      int pump = log["pump"] as int;
      totalSeconds[pump] = totalSeconds[pump]! + diff;
    }

    return totalSeconds;
  }

  // ================= CSV EXPORT =================
  Future<void> exportCsv(int days) async {
    final db = await DatabaseHelper.instance.database;
    String? from;

    if (days > 0) {
      from = DateTime.now().subtract(Duration(days: days)).toString();
    }

    final sensor = await db.query(
      "sensor",
      where: from != null ? "time >= ?" : null,
      whereArgs: from != null ? [from] : null,
      orderBy: "id ASC",
    );

    final pump = await db.query(
      "pump_log",
      where: from != null ? "start >= ?" : null,
      whereArgs: from != null ? [from] : null,
      orderBy: "id ASC",
    );

    final sensorRows = [
      ["time", "temp", "hum", "soil1", "soil2", "soil3"],
      ...sensor.map((e) => [
            e["time"],
            e["temp"],
            e["hum"],
            e["soil1"],
            e["soil2"],
            e["soil3"],
          ])
    ];

    final pumpRows = [
      ["pump", "start", "end"],
      ...pump.map((e) => [e["pump"], e["start"], e["end"] ?? ""])
    ];

    final sensorCsv = const ListToCsvConverter().convert(sensorRows);
    final pumpCsv = const ListToCsvConverter().convert(pumpRows);

    final dir = await getDownloadsDirectory();
if (dir == null) return;

final ts = DateTime.now().millisecondsSinceEpoch;
final sensorFile = File("${dir.path}/sensor_$ts.csv");
final pumpFile = File("${dir.path}/pump_$ts.csv");

await sensorFile.writeAsString(sensorCsv);
await pumpFile.writeAsString(pumpCsv);

if (mounted) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text("✅ Đã lưu vào: ${dir.path}")),
  );
}

  }
  void showExportOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text("Hôm nay"),
              onTap: () {
                Navigator.pop(context);
                exportCsv(1);
              },
            ),
            ListTile(
              title: const Text("7 ngày"),
              onTap: () {
                Navigator.pop(context);
                exportCsv(7);
              },
            ),
            ListTile(
              title: const Text("30 ngày"),
              onTap: () {
                Navigator.pop(context);
                exportCsv(30);
              },
            ),
            ListTile(
              title: const Text("Toàn bộ"),
              onTap: () {
                Navigator.pop(context);
                exportCsv(0);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ================= FORMAT =================
  String formatTime(String time) {
    final dt = DateTime.parse(time);
    return "${dt.hour}:${dt.minute.toString().padLeft(2, '0')}";
  }

  String getDuration(String start, String? end) {
    final s = DateTime.parse(start);
    final e = end != null ? DateTime.parse(end) : DateTime.now();

    final diff = e.difference(s);

    int h = diff.inHours;
    int m = diff.inMinutes % 60;
    int sec = diff.inSeconds % 60;

    if (h > 0) return "${h}h ${m}m";
    if (m > 0) return "${m}m ${sec}s";
    return "${sec}s";
  }

  // ================= CHART =================
  LineChartData buildChart(List data, String key) {
    return LineChartData(
      borderData: FlBorderData(show: false),
      gridData: FlGridData(show: true),
      titlesData: FlTitlesData(show: false),
      lineBarsData: [
        LineChartBarData(
          isCurved: true,
          dotData: FlDotData(show: false),
          spots: data.asMap().entries.map((e) {
            return FlSpot(e.key.toDouble(), (e.value[key] ?? 0).toDouble());
          }).toList(),
        ),
      ],
    );
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Statistics"),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: showExportOptions,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 10),

            card(
              "Nhiệt độ",
              Column(
                children: [
                  SizedBox(
                    height: 150,
                    child: LineChart(buildChart(sensorData, "temp")),
                  ),
                  Text("TB: ${avgTemp.toStringAsFixed(1)} °C"),
                ],
              ),
            ),

            card(
              "Độ ẩm không khí",
              Column(
                children: [
                  SizedBox(
                    height: 150,
                    child: LineChart(buildChart(sensorData, "hum")),
                  ),
                  Text("TB: ${avgHum.toStringAsFixed(1)} %"),
                ],
              ),
            ),

            card(
              "Độ ẩm đất",
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  soilBox("Soil 1", avgSoil1),
                  soilBox("Soil 2", avgSoil2),
                  soilBox("Soil 3", avgSoil3),
                ],
              ),
            ),

            card(
              "Lịch sử bơm",
              Column(
                children: [
                  ...(showAllLogs ? pumpLogs : pumpLogs.take(10).toList()).map((
                    log,
                  ) {
                    String start = log["start"].toString();
                    String? end = log["end"]?.toString();

                    return Container(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.water_drop, color: Colors.blue),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Bơm ${log["pump"]}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "${formatTime(start)} → ${end != null ? formatTime(end) : "..."}",
                                ),
                                Text(
                                  getDuration(start, end),
                                  style: const TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                          if (end == null)
                            const Text(
                              "RUN",
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                  if (pumpLogs.length > 10)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          showAllLogs = !showAllLogs;
                        });
                      },
                      child: Text(showAllLogs ? "Thu gọn ▲" : "Xem thêm ▼"),
                    ),
                ],
              ),
            ),

            card(
              "Thống kê hôm nay",
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  statBox("Bơm 1", todayStats[1] ?? 0),
                  statBox("Bơm 2", todayStats[2] ?? 0),
                  statBox("Bơm 3", todayStats[3] ?? 0),
                ],
              ),
            ),

            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

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

  Widget soilBox(String title, double value) {
    return Column(
      children: [
        Text(title),
        Text(
          value.toStringAsFixed(0),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ],
    );
  }

  Widget statBox(String title, int seconds) {
    int m = seconds ~/ 60;
    int s = seconds % 60;

    return Column(
      children: [
        Text(title),
        const SizedBox(height: 5),
        Text(
          "${m}m ${s}s",
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.green,
          ),
        ),
      ],
    );
  }
}