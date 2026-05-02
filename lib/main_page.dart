import 'package:flutter/material.dart';
import 'package:iot/notification_page.dart';
import 'home_page.dart';
import 'statistics_page.dart';
import 'schedule_page.dart';
import 'config_page.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {

  int currentIndex = 0;

  final pages = [
    HomePage(),
    StatisticsPage(),
    SchedulePage(),
    NotificationPage(),
    ConfigPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(

      // 👇 HIỂN THỊ PAGE
      body: pages[currentIndex],

      // 👇 NAV BAR
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex, // ✅ FIX
        selectedItemColor: Colors.green,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,

        onTap: (index) { // ✅ FIX QUAN TRỌNG
          setState(() {
            currentIndex = index;
          });
        },

        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(icon: Icon(Icons.storage), label: "Statistics"),
          BottomNavigationBarItem(icon: Icon(Icons.access_alarm), label: "Schedule"),
          BottomNavigationBarItem(icon: Icon(Icons.notifications), label: "Notifications"),
          BottomNavigationBarItem(icon: Icon(Icons.build), label: "Config"),
        ],
      ),
    );
  }
}