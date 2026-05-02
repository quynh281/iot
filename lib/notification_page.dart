import 'package:flutter/material.dart';
import 'database_helper.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  List notifications = [];

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final db = await DatabaseHelper.instance.database;
    notifications = await db.query("notification", orderBy: "id DESC");
    if (mounted) setState(() {});
  }

  String formatTime(String time) {
    final dt = DateTime.parse(time);
    return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} "
        "${dt.day}/${dt.month}/${dt.year}";
  }

  Future<void> clearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Xóa tất cả thông báo?"),
        content: const Text("Hành động này không thể hoàn tác."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Hủy"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Xóa"),
          ),
        ],
      ),
    );

    if (ok == true) {
      final db = await DatabaseHelper.instance.database;
      await db.delete("notification");
      loadData();
    }
  }

  Future<void> deleteOne(int id) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete("notification", where: "id = ?", whereArgs: [id]);
    loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff5f7fb),
      appBar: AppBar(
        title: const Text("Thông báo"),
        backgroundColor: Colors.green,
        actions: [
          if (notifications.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: clearAll,
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadData,
        child: notifications.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text("Không có thông báo")),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: notifications.length,
                itemBuilder: (context, index) {
                  final n = notifications[index];
                  final int id = n["id"] as int;

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.notifications,
                        color: Colors.orange,
                      ),
                      title: Text(
                        n["title"],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(n["content"]),
                          const SizedBox(height: 6),
                          Text(
                            formatTime(n["time"]),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => deleteOne(id),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}