
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

part 'main.g.dart';

// Theme Provider
class ThemeProvider with ChangeNotifier {
  late Box _settingsBox;
  bool _isDarkMode = true;

  ThemeProvider() {
    _settingsBox = Hive.box('settings');
    _isDarkMode = _settingsBox.get('isDarkMode', defaultValue: true);
  }

  bool get isDarkMode => _isDarkMode;

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    _settingsBox.put('isDarkMode', _isDarkMode);
    notifyListeners();
  }

  ThemeData get lightTheme => ThemeData(
    primarySwatch: Colors.teal,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E3A3A),
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: Colors.grey[50],
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF9EF0D0),
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
  );

  ThemeData get darkTheme => ThemeData(
    primarySwatch: Colors.teal,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E3A3A),
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF1E3A3A),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E3A3A),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: Color(0xFF2A4F4F),
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
    ),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  await Hive.initFlutter();
  Hive.registerAdapter(EventAdapter());
  await Hive.openBox<Event>('events');
  await Hive.openBox('settings');
  runApp(const CalendarPlannerApp());
}

class CalendarPlannerApp extends StatelessWidget {
  const CalendarPlannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => EventProvider()),
        ChangeNotifierProvider(create: (context) => ThemeProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'Calendar Planner',
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.darkTheme,
            themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            home: const MainScreen(),
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}

// Event Model
@HiveType(typeId: 0)
class Event extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

  @HiveField(2)
  final String description;

  @HiveField(3)
  final DateTime dateTime;

  @HiveField(4)
  final String type;

  @HiveField(5)
  final List<String> participants;

  @HiveField(6)
  final int colorValue;

  @HiveField(7)
  final List<int> reminderMinutes;

  @HiveField(8)
  final String? recurrenceRule;

  @HiveField(9)
  final String? parentEventId;

  Event({
    required this.id,
    required this.title,
    required this.description,
    required this.dateTime,
    required this.type,
    required this.participants,
    required Color color,
    this.reminderMinutes = const [],
    this.recurrenceRule,
    this.parentEventId,
  }) : colorValue = color.value;

  Event._internal({
    required this.id,
    required this.title,
    required this.description,
    required this.dateTime,
    required this.type,
    required this.participants,
    required this.colorValue,
    this.reminderMinutes = const [],
    this.recurrenceRule,
    this.parentEventId,
  });

  Color get color => Color(colorValue);
}

// Notification Service
class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initializationSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(initializationSettings);
  }

  static Future<void> scheduleEventReminder({
    required String eventId,
    required String title,
    required String description,
    required DateTime eventTime,
    required int reminderMinutesBefore,
  }) async {
    final reminderTime = eventTime.subtract(Duration(minutes: reminderMinutesBefore));

    if (reminderTime.isBefore(DateTime.now())) {
      return; // Don't schedule past reminders
    }

    const androidDetails = AndroidNotificationDetails(
      'event_reminders',
      'Event Reminders',
      channelDescription: 'Notifications for upcoming events',
      importance: Importance.high,
      priority: Priority.high,
    );

    const iosDetails = DarwinNotificationDetails();

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    final notificationId = '${eventId}_$reminderMinutesBefore'.hashCode;

    // Create appropriate message based on time before event
    String reminderMessage;
    if (reminderMinutesBefore == 0) {
      reminderMessage = '$description\nEvent is starting now!';
    } else if (reminderMinutesBefore >= 1440) {
      final days = (reminderMinutesBefore / 1440).round();
      reminderMessage = '$description\nStarts in $days day${days > 1 ? 's' : ''}';
    } else if (reminderMinutesBefore >= 60) {
      final hours = (reminderMinutesBefore / 60).round();
      reminderMessage = '$description\nStarts in $hours hour${hours > 1 ? 's' : ''}';
    } else {
      reminderMessage = '$description\nStarts in $reminderMinutesBefore minute${reminderMinutesBefore > 1 ? 's' : ''}';
    }

    await _notifications.zonedSchedule(
      notificationId,
      'Event Reminder: $title',
      reminderMessage,
      tz.TZDateTime.from(reminderTime, tz.local),
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
    );
  }

  static Future<void> cancelEventReminders(String eventId) async {
    // Cancel all reminders for this event
    for (int minutes in [0, 60, 240, 1440]) { // At start, 1hr, 4hr, 1day before
      final notificationId = '${eventId}_$minutes'.hashCode;
      await _notifications.cancel(notificationId);
    }
  }

  static Future<void> scheduleAllEventReminders(Event event) async {
    // Cancel existing reminders first
    await cancelEventReminders(event.id);

    // Use default reminders if none specified
    final reminders = event.reminderMinutes.isEmpty
        ? [1440, 240, 60, 0] // 1 day, 4 hours, 1 hour, at start
        : event.reminderMinutes;

    // Schedule new reminders
    for (int minutes in reminders) {
      await scheduleEventReminder(
        eventId: event.id,
        title: event.title,
        description: event.description,
        eventTime: event.dateTime,
        reminderMinutesBefore: minutes,
      );
    }
  }

  static List<int> getDefaultReminderMinutes() {
    return [1440, 240, 60, 0]; // 1 day, 4 hours, 1 hour, at start
  }

  static String getReminderDisplayText(int minutes) {
    if (minutes == 0) return 'At event start';
    if (minutes == 60) return '1 hour before';
    if (minutes == 240) return '4 hours before';
    if (minutes == 1440) return '1 day before';
    if (minutes < 60) return '$minutes minutes before';
    if (minutes < 1440) return '${(minutes / 60).round()} hours before';
    return '${(minutes / 1440).round()} days before';
  }
}

// Recurrence Service
class RecurrenceService {
  static List<Event> generateRecurringEvents(Event baseEvent, {int monthsAhead = 6}) {
    if (baseEvent.recurrenceRule == null) return [baseEvent];

    final events = <Event>[baseEvent];
    final rule = baseEvent.recurrenceRule!;
    final endDate = DateTime.now().add(Duration(days: monthsAhead * 30));

    DateTime nextDate = baseEvent.dateTime;

    switch (rule) {
      case 'daily':
        while (nextDate.isBefore(endDate)) {
          nextDate = nextDate.add(const Duration(days: 1));
          if (nextDate.isBefore(endDate)) {
            events.add(_createRecurringEvent(baseEvent, nextDate));
          }
        }
        break;
      case 'weekly':
        while (nextDate.isBefore(endDate)) {
          nextDate = nextDate.add(const Duration(days: 7));
          if (nextDate.isBefore(endDate)) {
            events.add(_createRecurringEvent(baseEvent, nextDate));
          }
        }
        break;
      case 'monthly':
        while (nextDate.isBefore(endDate)) {
          nextDate = DateTime(nextDate.year, nextDate.month + 1, nextDate.day, nextDate.hour, nextDate.minute);
          if (nextDate.isBefore(endDate)) {
            events.add(_createRecurringEvent(baseEvent, nextDate));
          }
        }
        break;
      case 'yearly':
        while (nextDate.isBefore(endDate)) {
          nextDate = DateTime(nextDate.year + 1, nextDate.month, nextDate.day, nextDate.hour, nextDate.minute);
          if (nextDate.isBefore(endDate)) {
            events.add(_createRecurringEvent(baseEvent, nextDate));
          }
        }
        break;
    }

    return events;
  }

  static Event _createRecurringEvent(Event baseEvent, DateTime newDate) {
    return Event(
      id: '${baseEvent.id}_${newDate.millisecondsSinceEpoch}',
      title: baseEvent.title,
      description: baseEvent.description,
      dateTime: newDate,
      type: baseEvent.type,
      participants: baseEvent.participants,
      color: baseEvent.color,
      reminderMinutes: baseEvent.reminderMinutes,
      recurrenceRule: baseEvent.recurrenceRule,
      parentEventId: baseEvent.id,
    );
  }

  static void deleteRecurringSeries(String parentEventId, EventProvider eventProvider) {
    final events = eventProvider.events.where((e) =>
      e.id == parentEventId || e.parentEventId == parentEventId).toList();

    for (final event in events) {
      eventProvider.deleteEvent(event.id);
    }
  }
}

// Event Provider with Hive storage
class EventProvider with ChangeNotifier {
  late Box<Event> _eventBox;
  DateTime _selectedDay = DateTime.now();

  EventProvider() {
    _eventBox = Hive.box<Event>('events');
    _loadInitialEvents();
  }

  void _loadInitialEvents() {
    // Load specific events if box is empty (first time app run)
    if (_eventBox.isEmpty) {
      _addInitialMockEvents();
    }
  }

  void _addInitialMockEvents() {
    final initialEvents = [
      Event(
        id: 'event_1',
        title: 'Rhapsody Wonder Conferences, Road to Reachout World Edition',
        description: 'October - November 2025',
        dateTime: DateTime(2025, 10, 1),
        type: 'Conference',
        participants: [],
        color: Colors.blue,
      ),
      Event(
        id: 'event_2',
        title: 'Road to Healing Streams Live Healing Services',
        description: '10 October 2025 - 23 October 2025',
        dateTime: DateTime(2025, 10, 10),
        type: 'HSLHS Preparatory Program',
        participants: [],
        color: Colors.green,
      ),
      Event(
        id: 'event_3',
        title: 'Global Principals and Teachers Summit (4th Quarter, 19th Edition)',
        description: 'Foundation School Training',
        dateTime: DateTime(2025, 10, 13),
        type: 'Training Program',
        participants: [],
        color: Colors.orange,
      ),
      Event(
        id: 'event_4',
        title: 'Healing Streams Live Healing Services',
        description: '24 October - 26 October 2025',
        dateTime: DateTime(2025, 10, 24),
        type: 'Ministry Program',
        participants: [],
        color: Colors.purple,
      ),
      Event(
        id: 'event_5',
        title: 'November Global Communion Service',
        description: '2 November 2025',
        dateTime: DateTime(2025, 11, 2),
        type: 'Ministry Program',
        participants: [],
        color: Colors.red,
      ),
      Event(
        id: 'event_6',
        title: 'International Pastors\' Conference',
        description: '10 November - 12 November 2025',
        dateTime: DateTime(2025, 11, 10),
        type: 'Ministry Program',
        participants: [],
        color: Colors.teal,
      ),
      Event(
        id: 'event_7',
        title: 'International Pastors\' & Partners\' Conference',
        description: '13 November - 16 November 2025',
        dateTime: DateTime(2025, 11, 13),
        type: 'Ministry Program',
        participants: [],
        color: Colors.indigo,
      ),
      Event(
        id: 'event_8',
        title: 'Christian Leaders Conference India with Pastor Chris',
        description: '25 November - 27 November 2025',
        dateTime: DateTime(2025, 11, 25),
        type: 'Ministry Program',
        participants: [],
        color: Colors.brown,
      ),
      Event(
        id: 'event_9',
        title: 'Higher Life Conference India, with Pastor Chris',
        description: '28 November 2025',
        dateTime: DateTime(2025, 11, 28),
        type: 'Ministry Program',
        participants: [],
        color: Colors.pink,
      ),
      Event(
        id: 'event_10',
        title: 'Reachout World Day',
        description: 'Global Reachout Campaign with Rhapsody of Realities',
        dateTime: DateTime(2025, 12, 1),
        type: 'Global Reachout Campaign',
        participants: [],
        color: Colors.cyan,
      ),
      Event(
        id: 'event_11',
        title: 'December Global Communion Service',
        description: '7 December 2025',
        dateTime: DateTime(2025, 12, 7),
        type: 'Ministry Program',
        participants: [],
        color: Colors.lime,
      ),
      Event(
        id: 'event_12',
        title: 'The President\'s Celebration Banquet & LW Global Day of Service',
        description: '7 December 2025',
        dateTime: DateTime(2025, 12, 7),
        type: 'Celebration Event',
        participants: [],
        color: Colors.amber,
      ),
      Event(
        id: 'event_13',
        title: 'Holy Land Tour with Pastor Chris and Pastor Benny',
        description: '9 December - 14 December 2025',
        dateTime: DateTime(2025, 12, 9),
        type: 'Holy Land Tour',
        participants: [],
        color: Colors.deepOrange,
      ),
      Event(
        id: 'event_14',
        title: 'End of the Year Thanksgiving',
        description: '14 December - 21 December 2025',
        dateTime: DateTime(2025, 12, 14),
        type: 'Thanksgiving Service',
        participants: [],
        color: Colors.deepPurple,
      ),
      Event(
        id: 'event_15',
        title: 'Christmas Eve Praise Service with Pastor Chris',
        description: '24 December - 25 December 2025',
        dateTime: DateTime(2025, 12, 24),
        type: 'Ministry Program',
        participants: [],
        color: Colors.red,
      ),
      Event(
        id: 'event_16',
        title: 'Global Fasting and Praying',
        description: '29 December - 31 December 2025',
        dateTime: DateTime(2025, 12, 29),
        type: 'Ministry Program',
        participants: [],
        color: Colors.blue,
      ),
      Event(
        id: 'event_17',
        title: 'New Year\'s Eve Service with Pastor Chris',
        description: '31 December 2025 - 1 January 2026',
        dateTime: DateTime(2025, 12, 31),
        type: 'Ministry Program',
        participants: [],
        color: Colors.green,
      ),
      Event(
        id: 'event_18',
        title: 'January 2026 Global Communion Service with Pastor Chris',
        description: '4 January 2026',
        dateTime: DateTime(2026, 1, 4),
        type: 'Ministry Program',
        participants: [],
        color: Colors.orange,
      ),
    ];

    for (final event in initialEvents) {
      _eventBox.add(event);
    }
    notifyListeners();
  }

  List<Event> get events => _eventBox.values.toList();
  DateTime get selectedDay => _selectedDay;

  List<Event> get eventsForSelectedDay {
    return events.where((event) {
      return event.dateTime.year == _selectedDay.year &&
          event.dateTime.month == _selectedDay.month &&
          event.dateTime.day == _selectedDay.day;
    }).toList();
  }

  List<Event> get upcomingEvents {
    final now = DateTime.now();
    return events.where((event) => event.dateTime.isAfter(now)).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }

  List<Event> get allEventsSorted {
    return List.from(events)..sort((a, b) => a.dateTime.compareTo(b.dateTime));
  }


  void selectDay(DateTime day) {
    _selectedDay = day;
    notifyListeners();
  }

  void addSampleEvents() async {
    final sampleEvents = [
      {
        'title': 'Rhapsody Wonders Conferences, Road to Reachout World Edition',
        'description': 'Major conference event spanning two months',
        'startDate': DateTime(2025, 10, 1),
        'type': 'Conference',
        'color': Colors.purple,
      },
      {
        'title': 'Road to Healing Streams Live Healing Services',
        'description': 'Live healing services preparation period',
        'startDate': DateTime(2025, 10, 10),
        'type': 'Service',
        'color': Colors.blue,
      },
      {
        'title': 'Global Principals and Teachers Summit (4th Quarter, 19th Edition)',
        'description': 'Educational summit for global principals and teachers',
        'startDate': DateTime(2025, 10, 13),
        'type': 'Meeting',
        'color': Colors.green,
      },
      {
        'title': 'Healing Streams Live Healing Services',
        'description': 'Live healing services',
        'startDate': DateTime(2025, 10, 24),
        'type': 'Service',
        'color': Colors.blue,
      },
      {
        'title': 'November Global Communion Service',
        'description': 'Monthly global communion service',
        'startDate': DateTime(2025, 11, 2),
        'type': 'Service',
        'color': Colors.orange,
      },
      {
        'title': 'International Pastors\' Conference',
        'description': 'Conference for international pastors',
        'startDate': DateTime(2025, 11, 10),
        'type': 'Conference',
        'color': Colors.red,
      },
      {
        'title': 'International Pastors\' & Partners\' Conference',
        'description': 'Extended conference for pastors and partners',
        'startDate': DateTime(2025, 11, 13),
        'type': 'Conference',
        'color': Colors.red,
      },
      {
        'title': 'Christian Leaders Conference India with Pastor Chris',
        'description': 'Leadership conference in India with Pastor Chris',
        'startDate': DateTime(2025, 11, 25),
        'type': 'Conference',
        'color': Colors.teal,
      },
      {
        'title': 'Higher Live Conference India with Pastor Chris',
        'description': 'Special live conference in India with Pastor Chris',
        'startDate': DateTime(2025, 11, 28),
        'type': 'Conference',
        'color': Colors.teal,
      },
      {
        'title': 'Reachout World Day',
        'description': 'Global outreach and evangelism day',
        'startDate': DateTime(2025, 12, 1),
        'type': 'Event',
        'color': Colors.purple,
      },
      {
        'title': 'December Global Communion Service',
        'description': 'Monthly global communion service',
        'startDate': DateTime(2025, 12, 7),
        'type': 'Service',
        'color': Colors.orange,
      },
      {
        'title': 'The President\'s Celebration Banquet',
        'description': 'Special celebration banquet event',
        'startDate': DateTime(2025, 12, 7),
        'type': 'Celebration',
        'color': Colors.yellow,
      },
      {
        'title': 'Holy Land Tour with Pastor Chris and Pastor Benny',
        'description': 'Spiritual tour to the Holy Land with pastoral leadership',
        'startDate': DateTime(2025, 12, 9),
        'type': 'Tour',
        'color': Colors.brown,
      },
      {
        'title': 'End of the Year Thanksgiving',
        'description': 'Year-end thanksgiving and gratitude services',
        'startDate': DateTime(2025, 12, 14),
        'type': 'Service',
        'color': Colors.orange,
      },
      {
        'title': 'Christmas Eve Praise Service with Pastor Chris',
        'description': 'Special Christmas Eve praise and worship service',
        'startDate': DateTime(2025, 12, 24),
        'type': 'Service',
        'color': Colors.green,
      },
      {
        'title': 'Global Fasting and Praying',
        'description': 'Year-end global fasting and prayer sessions',
        'startDate': DateTime(2025, 12, 29),
        'type': 'Prayer',
        'color': Colors.indigo,
      },
      {
        'title': 'New Year\'s Eve Service',
        'description': 'Special New Year\'s Eve service and celebration',
        'startDate': DateTime(2025, 12, 31),
        'type': 'Service',
        'color': Colors.pink,
      },
      {
        'title': 'January Global Communion Service',
        'description': 'Monthly global communion service for the new year',
        'startDate': DateTime(2026, 1, 8),
        'type': 'Service',
        'color': Colors.orange,
      },
    ];

    for (final eventData in sampleEvents) {
      addEvent(
        title: eventData['title'] as String,
        description: eventData['description'] as String,
        dateTime: eventData['startDate'] as DateTime,
        type: eventData['type'] as String,
        participants: [],
        color: eventData['color'] as Color,
        reminderMinutes: [1440, 240, 60, 0], // 1 day, 4 hours, 1 hour, at start
      );
    }

    // Ensure UI updates after adding all events
    notifyListeners();
  }

  void addEvent({
    required String title,
    required String description,
    required DateTime dateTime,
    required String type,
    required List<String> participants,
    required Color color,
    List<int> reminderMinutes = const [],
    String? recurrenceRule,
  }) async {
    final baseEvent = Event(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      description: description,
      dateTime: dateTime,
      type: type,
      participants: participants,
      color: color,
      reminderMinutes: reminderMinutes,
      recurrenceRule: recurrenceRule,
    );

    if (recurrenceRule != null) {
      // Generate recurring events
      final recurringEvents = RecurrenceService.generateRecurringEvents(baseEvent);
      for (final event in recurringEvents) {
        _eventBox.add(event);
        await NotificationService.scheduleAllEventReminders(event);
      }
    } else {
      _eventBox.add(baseEvent);
      await NotificationService.scheduleAllEventReminders(baseEvent);
    }

    notifyListeners();
  }

  void updateEvent({
    required String id,
    required String title,
    required String description,
    required DateTime dateTime,
    required String type,
    required List<String> participants,
    required Color color,
    List<int> reminderMinutes = const [],
  }) async {
    final eventIndex = _eventBox.values.toList().indexWhere((event) => event.id == id);
    if (eventIndex != -1) {
      final updatedEvent = Event(
        id: id,
        title: title,
        description: description,
        dateTime: dateTime,
        type: type,
        participants: participants,
        color: color,
        reminderMinutes: reminderMinutes,
      );
      _eventBox.putAt(eventIndex, updatedEvent);
      await NotificationService.scheduleAllEventReminders(updatedEvent);
      notifyListeners();
    }
  }

  void deleteEvent(String id) async {
    final eventIndex = _eventBox.values.toList().indexWhere((event) => event.id == id);
    if (eventIndex != -1) {
      await NotificationService.cancelEventReminders(id);
      _eventBox.deleteAt(eventIndex);
      notifyListeners();
    }
  }

  void clearAllEvents() async {
    await _eventBox.clear();
    notifyListeners();
  }

  List<Event> getEventsForDay(DateTime day) {
    return events.where((event) {
      return event.dateTime.year == day.year &&
          event.dateTime.month == day.month &&
          event.dateTime.day == day.day;
    }).toList();
  }
}

// Main Screen with Three Panel Layout
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFF1E3A3A),
      appBar: AppBar(
        title: const Text('Calendar Planner'),
        backgroundColor: const Color(0xFF2A4F4F),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: screenWidth > 800
            ? Row(
                children: [
                  // Left Panel - Calendar with Events
                  Expanded(
                    flex: 1,
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A4F4F),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const CalendarWithEventsScreen(),
                    ),
                  ),
                  // Right Panel - All Events
                  Expanded(
                    flex: 1,
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A4F4F),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const AllEventsScreen(),
                    ),
                  ),
                ],
              )
            : const MobileCalendarView(),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AddEventScreen(),
            ),
          );
        },
        backgroundColor: Colors.tealAccent,
        child: const Icon(Icons.add, color: Color(0xFF1E3A3A)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}


// Home Screen
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EventProvider>().selectDay(_selectedDay);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Calendar Planner',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        elevation: 0,
        centerTitle: true,
        actions: [
          Consumer<ThemeProvider>(
            builder: (context, themeProvider, child) {
              return IconButton(
                icon: Icon(
                  themeProvider.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                ),
                onPressed: () {
                  themeProvider.toggleTheme();
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              setState(() {
                _focusedDay = DateTime.now();
                _selectedDay = DateTime.now();
              });
              context.read<EventProvider>().selectDay(DateTime.now());
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Custom Calendar Section
          Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: CustomCalendar(
              selectedDay: _selectedDay,
              focusedDay: _focusedDay,
              onDaySelected: (selectedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = selectedDay;
                });
                context.read<EventProvider>().selectDay(selectedDay);
              },
              onPageChanged: (focusedDay) {
                setState(() {
                  _focusedDay = focusedDay;
                });
              },
            ),
          ),
          // Events Section
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Consumer<EventProvider>(
                    builder: (context, eventProvider, child) {
                      return Text(
                        'Events for ${DateFormat('MMMM d, y').format(eventProvider.selectedDay)}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Consumer<EventProvider>(
                      builder: (context, eventProvider, child) {
                        final events = eventProvider.eventsForSelectedDay;
                        
                        if (events.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.event_note,
                                  size: 64,
                                  color: Colors.grey[300],
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No events scheduled',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: Color(0xFF9EF0D0),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Tap + to add a new event',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Color(0xFFE0E6E4),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: events.length,
                          itemBuilder: (context, index) {
                            final event = events[index];
                            return EventCard(
                              event: event,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => EventDetailScreen(event: event),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// All Events Screen
class AllEventsScreen extends StatefulWidget {
  const AllEventsScreen({super.key});

  @override
  State<AllEventsScreen> createState() => _AllEventsScreenState();
}

class _AllEventsScreenState extends State<AllEventsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedFilter = 'All';

  final List<String> _filterOptions = [
    'All',
    'Meeting',
    'Call',
    'Video Call',
    'Presentation',
    'Discussion',
    'Other'
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Event> _filterEvents(List<Event> events) {
    List<Event> filtered = events;

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((event) =>
        event.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        event.description.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        event.participants.any((p) => p.toLowerCase().contains(_searchQuery.toLowerCase()))
      ).toList();
    }

    // Apply type filter
    if (_selectedFilter != 'All') {
      filtered = filtered.where((event) => event.type == _selectedFilter).toList();
    }

    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'All Events',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        elevation: 0,
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (value) {
              setState(() {
                _selectedFilter = value;
              });
            },
            itemBuilder: (context) => _filterOptions.map((filter) =>
              PopupMenuItem(
                value: filter,
                child: Row(
                  children: [
                    if (_selectedFilter == filter)
                      const Icon(Icons.check, size: 20),
                    if (_selectedFilter == filter)
                      const SizedBox(width: 8),
                    Text(filter),
                  ],
                ),
              ),
            ).toList(),
          ),
        ],
      ),
      body: Consumer<EventProvider>(
        builder: (context, eventProvider, child) {
          final allEvents = eventProvider.allEventsSorted;
          final upcomingEvents = eventProvider.upcomingEvents;
          final filteredEvents = _filterEvents(allEvents);
          final filteredUpcoming = _filterEvents(upcomingEvents);

          return Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  style: TextStyle(color: Colors.black), // Black text for better visibility
                  decoration: InputDecoration(
                    hintText: 'Search events...',
                    hintStyle: TextStyle(color: Colors.grey[600]), // Darker hint text
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        )
                      : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value;
                    });
                  },
                ),
              ),

              // Filter chips
              if (_selectedFilter != 'All')
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Chip(
                        label: Text(_selectedFilter),
                        deleteIcon: const Icon(Icons.close, size: 18),
                        onDeleted: () {
                          setState(() {
                            _selectedFilter = 'All';
                          });
                        },
                      ),
                    ],
                  ),
                ),

              // Results
              Expanded(
                child: filteredEvents.isEmpty ?
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _searchQuery.isNotEmpty || _selectedFilter != 'All'
                            ? Icons.search_off
                            : Icons.event_available,
                          size: 64,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isNotEmpty || _selectedFilter != 'All'
                            ? 'No events found'
                            : 'No events created yet',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Color(0xFF9EF0D0),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchQuery.isNotEmpty || _selectedFilter != 'All'
                            ? 'Try adjusting your search or filter'
                            : 'Tap + to create your first event',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFFE0E6E4),
                          ),
                        ),
                      ],
                    ),
                  ) :
                  SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Upcoming Events Section
                        if (filteredUpcoming.isNotEmpty) ...[
                          Row(
                            children: [
                              Icon(Icons.schedule, color: Colors.blue[600]),
                              const SizedBox(width: 8),
                              Text(
                                'Upcoming Events (${filteredUpcoming.length})',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          ...filteredUpcoming.take(3).map((event) => EventCard(
                            event: event,
                            showDate: true,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => EventDetailScreen(event: event),
                                ),
                              );
                            },
                          )),
                          if (filteredUpcoming.length > 3) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: Text(
                                '+ ${filteredUpcoming.length - 3} more upcoming events',
                                style: const TextStyle(
                                  color: Color(0xFF9EF0D0),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 32),
                        ],

                        // All Events Section
                        Row(
                          children: [
                            Icon(Icons.event, color: Colors.teal[700]),
                            const SizedBox(width: 8),
                            Text(
                              'All Events (${filteredEvents.length})',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Group events by month
                        ...filteredEvents.fold<Map<String, List<Event>>>({}, (map, event) {
                          final monthKey = DateFormat('MMMM y').format(event.dateTime);
                          map[monthKey] = [...(map[monthKey] ?? []), event];
                          return map;
                        }).entries.map((entry) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Text(
                                  entry.key,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF9EF0D0),
                                  ),
                                ),
                              ),
                              ...entry.value.map((event) => EventCard(
                                event: event,
                                showDate: true,
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => EventDetailScreen(event: event),
                                    ),
                                  );
                                },
                              )),
                              const SizedBox(height: 16),
                            ],
                          );
                        }),
                      ],
                    ),
                  ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// Custom Calendar Widget
class CustomCalendar extends StatelessWidget {
  final DateTime selectedDay;
  final DateTime focusedDay;
  final Function(DateTime) onDaySelected;
  final Function(DateTime) onPageChanged;

  const CustomCalendar({
    super.key,
    required this.selectedDay,
    required this.focusedDay,
    required this.onDaySelected,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GestureDetector(
        onHorizontalDragEnd: (DragEndDetails details) {
          // Swipe left to go to next month
          if (details.primaryVelocity! < -500) {
            final newDate = DateTime(focusedDay.year, focusedDay.month + 1);
            onPageChanged(newDate);
          }
          // Swipe right to go to previous month
          else if (details.primaryVelocity! > 500) {
            final newDate = DateTime(focusedDay.year, focusedDay.month - 1);
            onPageChanged(newDate);
          }
        },
        child: Column(
          children: [
            // Calendar Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () {
                    final newDate = DateTime(focusedDay.year, focusedDay.month - 1);
                    onPageChanged(newDate);
                  },
                  icon: const Icon(Icons.chevron_left),
                ),
                GestureDetector(
                  onTap: () => _showMonthYearPicker(context),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('MMMM y').format(focusedDay),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.keyboard_arrow_down, size: 20),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () {
                    final newDate = DateTime(focusedDay.year, focusedDay.month + 1);
                    onPageChanged(newDate);
                  },
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Days of week header
            Row(
              children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                  .map((day) => Expanded(
                        child: Center(
                          child: Text(
                            day,
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF9EF0D0),
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 8),

            // Calendar Grid
            Consumer<EventProvider>(
              builder: (context, eventProvider, child) {
                return CalendarGrid(
                  focusedDay: focusedDay,
                  selectedDay: selectedDay,
                  onDaySelected: onDaySelected,
                  eventProvider: eventProvider,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMonthYearPicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => DatePickerDialog(
        initialDate: focusedDay,
        firstDate: DateTime(2020),
        lastDate: DateTime(2030),
      ),
    ).then((selectedDate) {
      if (selectedDate != null) {
        onPageChanged(selectedDate);
      }
    });
  }
}

// Calendar Grid Widget
class CalendarGrid extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime selectedDay;
  final Function(DateTime) onDaySelected;
  final EventProvider eventProvider;

  const CalendarGrid({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.eventProvider,
  });

  @override
  Widget build(BuildContext context) {
    final firstDayOfMonth = DateTime(focusedDay.year, focusedDay.month, 1);
    final lastDayOfMonth = DateTime(focusedDay.year, focusedDay.month + 1, 0);
    final firstDayOfWeek = firstDayOfMonth.weekday;
    final daysInMonth = lastDayOfMonth.day;

    return Column(
      children: [
        for (int week = 0; week < 6; week++)
          Row(
            children: [
              for (int day = 0; day < 7; day++)
                Expanded(
                  child: _buildDayCell(context, week, day, firstDayOfWeek, daysInMonth),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildDayCell(BuildContext context, int week, int day, int firstDayOfWeek, int daysInMonth) {
    final dayNumber = (week * 7) + day + 1 - (firstDayOfWeek - 1);
    
    if (dayNumber < 1 || dayNumber > daysInMonth) {
      return const SizedBox(height: 40);
    }

    final date = DateTime(focusedDay.year, focusedDay.month, dayNumber);
    final isSelected = date.year == selectedDay.year && 
                      date.month == selectedDay.month && 
                      date.day == selectedDay.day;
    final isToday = date.year == DateTime.now().year && 
                   date.month == DateTime.now().month && 
                   date.day == DateTime.now().day;
    final hasEvents = eventProvider.getEventsForDay(date).isNotEmpty;

    return GestureDetector(
      onTap: () => onDaySelected(date),
      child: Container(
        height: 40,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected 
              ? Theme.of(context).primaryColor 
              : isToday 
                  ? Theme.of(context).primaryColor.withValues(alpha: 0.3)
                  : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                dayNumber.toString(),
                style: TextStyle(
                  color: isSelected
                      ? Colors.white
                      : isToday
                          ? Theme.of(context).primaryColor
                          : Color(0xFF9EF0D0),
                  fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (hasEvents)
              Positioned(
                bottom: 4,
                right: 4,
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white : Colors.orange,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Event Card Widget
class EventCard extends StatelessWidget {
  final Event event;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showDate;

  const EventCard({
    super.key,
    required this.event,
    this.onTap,
    this.onLongPress,
    this.showDate = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap ?? () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => EditEventScreen(event: event),
            ),
          );
        },
        onLongPress: onLongPress ?? () {
          _showDeleteDialog(context);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Color indicator
              Container(
                width: 4,
                height: 60,
                decoration: BoxDecoration(
                  color: event.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 16),
              // Event details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF9EF0D0),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 16,
                          color: Colors.teal[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          showDate
                              ? DateFormat('MMM d, HH:mm').format(event.dateTime)
                              : DateFormat('HH:mm').format(event.dateTime),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9EF0D0),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Icon(
                          _getEventIcon(event.type),
                          size: 16,
                          color: Colors.teal[600],
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            event.type,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF9EF0D0),
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Participants count
              if (event.participants.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: event.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${event.participants.length}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: event.color,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getEventIcon(String type) {
    switch (type.toLowerCase()) {
      case 'meeting':
        return Icons.groups;  // Fixed: valid icon
      case 'call':
        return Icons.phone;
      case 'video call':
        return Icons.videocam;
      case 'presentation':
        return Icons.present_to_all;  // Fixed: valid icon
      case 'discussion':
        return Icons.chat;  // Fixed: valid icon
      default:
        return Icons.event;
    }
  }

  void _showDeleteDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Event'),
          content: Text('Are you sure you want to delete "${event.title}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                context.read<EventProvider>().deleteEvent(event.id);
                Navigator.pop(context);
              },
              child: const Text('Delete', style: const TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
}

// Add Event Screen
class AddEventScreen extends StatefulWidget {
  const AddEventScreen({super.key});

  @override
  State<AddEventScreen> createState() => _AddEventScreenState();
}

class _AddEventScreenState extends State<AddEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _participantsController = TextEditingController();
  final _customTypeController = TextEditingController();
  
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  String _selectedType = 'Meeting';
  String _customType = '';
  Color _selectedColor = Colors.blue;
  List<int> _selectedReminders = [1440, 240, 60, 0]; // Default: 1 day, 4 hours, 1 hour, at start

  final List<String> _eventTypes = [
    'Meeting',
    'Call',
    'Video Call',
    'Presentation',
    'Discussion',
    'Other'
  ];

  final List<Color> _eventColors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.red,
    Colors.purple,
    Colors.teal,
  ];


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A3A),
      appBar: AppBar(
        title: const Text('Add Event'),
        backgroundColor: const Color(0xFF1E3A3A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _saveEvent,
            child: const Text('Save', style: const TextStyle(color: Colors.tealAccent)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              TextFormField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Event Title',
                  labelStyle: const TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.tealAccent),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an event title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descriptionController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Description',
                  labelStyle: const TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.tealAccent),
                  ),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              // Date and Time
              Row(
                children: [
                  Expanded(
                    child: Card(
                      color: const Color(0xFF2A4F4F),
                      child: ListTile(
                        title: const Text('Date', style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          DateFormat('MMM d, y').format(_selectedDate),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        leading: const Icon(Icons.calendar_today, color: Colors.tealAccent),
                        onTap: _selectDate,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Card(
                      color: const Color(0xFF2A4F4F),
                      child: ListTile(
                        title: const Text('Time', style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          _selectedTime.format(context),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        leading: const Icon(Icons.access_time, color: Colors.tealAccent),
                        onTap: _selectTime,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Event Type
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                style: const TextStyle(color: Colors.white),
                dropdownColor: const Color(0xFF2A4F4F),
                decoration: const InputDecoration(
                  labelText: 'Event Type',
                  labelStyle: const TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.tealAccent),
                  ),
                ),
                items: _eventTypes.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Row(
                      children: [
                        Icon(_getEventIcon(type), size: 20),
                        const SizedBox(width: 8),
                        Text(type),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedType = value!;
                    if (_selectedType != 'Other') {
                      _customTypeController.clear();
                    }
                  });
                },
              ),
              const SizedBox(height: 16),

              // Custom Type Field (only show when "Other" is selected)
              if (_selectedType == 'Other') ...[
                TextFormField(
                  controller: _customTypeController,
                  decoration: InputDecoration(
                    labelText: 'Custom Event Type',
                    hintText: 'Enter your custom event type...',
                    labelStyle: TextStyle(color: Colors.white70),
                    hintStyle: TextStyle(color: Colors.white30),
                    border: OutlineInputBorder(),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.white30),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.tealAccent),
                    ),
                  ),
                  style: TextStyle(color: Colors.white),
                  validator: (value) {
                    if (_selectedType == 'Other' && (value == null || value.trim().isEmpty)) {
                      return 'Please enter a custom event type';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
              ],

              // Color Selection
              const Text(
                'Event Color',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _eventColors.map((color) {
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedColor = color;
                      });
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _selectedColor == color
                              ? Color(0xFF9EF0D0)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: _selectedColor == color
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Participants
              TextFormField(
                controller: _participantsController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Participants (comma separated)',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: 'john@example.com, jane@example.com',
                  hintStyle: const TextStyle(color: Colors.white38),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.tealAccent),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getEventIcon(String type) {
    switch (type.toLowerCase()) {
      case 'meeting':
        return Icons.groups;
      case 'call':
        return Icons.phone;
      case 'video call':
        return Icons.videocam;
      case 'presentation':
        return Icons.present_to_all;
      case 'discussion':
        return Icons.chat;
      default:
        return Icons.event;
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _saveEvent() {
    if (_formKey.currentState!.validate()) {
      final dateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

      final participants = _participantsController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      context.read<EventProvider>().addEvent(
        title: _titleController.text,
        description: _descriptionController.text,
        dateTime: dateTime,
        type: _selectedType == 'Other' ? _customTypeController.text.trim() : _selectedType,
        participants: participants,
        color: _selectedColor,
        reminderMinutes: _selectedReminders,
      );

      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _participantsController.dispose();
    _customTypeController.dispose();
    super.dispose();
  }
}

// Add Event Screen
class EditEventScreen extends StatefulWidget {
  final Event event;

  const EditEventScreen({super.key, required this.event});

  @override
  State<EditEventScreen> createState() => _EditEventScreenState();
}

class _EditEventScreenState extends State<EditEventScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _participantsController;

  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late String _selectedType;
  late Color _selectedColor;
  late List<int> _selectedReminders;

  final List<String> _baseEventTypes = [
    'Meeting',
    'Call',
    'Video Call',
    'Presentation',
    'Discussion',
    'Other'
  ];

  List<String> get _eventTypes {
    // Include the current event's type if it's not in the base list
    if (!_baseEventTypes.contains(widget.event.type) && widget.event.type != 'Other') {
      return [..._baseEventTypes.take(_baseEventTypes.length - 1), widget.event.type, 'Other'];
    }
    return _baseEventTypes;
  }

  final List<Color> _eventColors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.red,
    Colors.purple,
    Colors.teal,
  ];


  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.event.title);
    _descriptionController = TextEditingController(text: widget.event.description);
    _participantsController = TextEditingController(text: widget.event.participants.join(', '));
    _selectedDate = widget.event.dateTime;
    _selectedTime = TimeOfDay.fromDateTime(widget.event.dateTime);
    _selectedType = widget.event.type;
    _selectedColor = widget.event.color;
    _selectedReminders = List.from(widget.event.reminderMinutes);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A3A),
      appBar: AppBar(
        title: const Text('Edit Event'),
        backgroundColor: const Color(0xFF1E3A3A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _saveEvent,
            child: const Text('Save', style: const TextStyle(color: Colors.tealAccent)),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              TextFormField(
                controller: _titleController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Event Title',
                  labelStyle: const TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.tealAccent),
                  ),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an event title';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Description
              TextFormField(
                controller: _descriptionController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Description',
                  labelStyle: const TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.tealAccent),
                  ),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              // Date and Time
              Row(
                children: [
                  Expanded(
                    child: Card(
                      color: const Color(0xFF2A4F4F),
                      child: ListTile(
                        title: const Text('Date', style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          DateFormat('MMM d, y').format(_selectedDate),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        leading: const Icon(Icons.calendar_today, color: Colors.tealAccent),
                        onTap: _selectDate,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Card(
                      color: const Color(0xFF2A4F4F),
                      child: ListTile(
                        title: const Text('Time', style: const TextStyle(color: Colors.white)),
                        subtitle: Text(
                          _selectedTime.format(context),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        leading: const Icon(Icons.access_time, color: Colors.tealAccent),
                        onTap: _selectTime,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Event Type
              DropdownButtonFormField<String>(
                value: _selectedType,
                style: const TextStyle(color: Colors.white),
                dropdownColor: const Color(0xFF2A4F4F),
                decoration: const InputDecoration(
                  labelText: 'Event Type',
                  labelStyle: const TextStyle(color: Colors.white70),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.tealAccent),
                  ),
                ),
                items: _eventTypes.map((type) {
                  return DropdownMenuItem(
                    value: type,
                    child: Row(
                      children: [
                        Icon(_getEventIcon(type), size: 20),
                        const SizedBox(width: 8),
                        Text(type),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedType = value!;
                  });
                },
              ),
              const SizedBox(height: 16),

              // Color Selection
              const Text(
                'Event Color',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _eventColors.map((color) {
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _selectedColor = color;
                      });
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _selectedColor == color
                              ? Color(0xFF9EF0D0)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: _selectedColor == color
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Participants
              TextFormField(
                controller: _participantsController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Participants (comma separated)',
                  labelStyle: const TextStyle(color: Colors.white70),
                  hintText: 'john@example.com, jane@example.com',
                  hintStyle: const TextStyle(color: Colors.white38),
                  border: OutlineInputBorder(),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white30),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.tealAccent),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getEventIcon(String type) {
    switch (type.toLowerCase()) {
      case 'meeting':
        return Icons.groups;
      case 'call':
        return Icons.phone;
      case 'video call':
        return Icons.videocam;
      case 'presentation':
        return Icons.present_to_all;
      case 'discussion':
        return Icons.chat;
      default:
        return Icons.event;
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime,
    );
    if (picked != null && picked != _selectedTime) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  void _saveEvent() {
    if (_formKey.currentState!.validate()) {
      final dateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

      final participants = _participantsController.text
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      context.read<EventProvider>().updateEvent(
        id: widget.event.id,
        title: _titleController.text,
        description: _descriptionController.text,
        dateTime: dateTime,
        type: _selectedType,
        participants: participants,
        color: _selectedColor,
        reminderMinutes: _selectedReminders,
      );

      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _participantsController.dispose();
    super.dispose();
  }
}

// Event Detail Screen
class EventDetailScreen extends StatelessWidget {
  final Event event;

  const EventDetailScreen({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E3A3A),
      appBar: AppBar(
        title: const Text('Event Details'),
        backgroundColor: const Color(0xFF1E3A3A),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditEventScreen(event: event),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => _deleteEvent(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Event header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: event.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: event.color.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFE6F4F1), // Soft mint white for primary text
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(_getEventIcon(event.type), color: const Color(0xFF00E0C7)), // Aqua mint for icons
                      const SizedBox(width: 8),
                      Text(
                        event.type,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Color(0xFF00E0C7), // Aqua mint for accent text
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Date and Time
            _DetailSection(
              icon: Icons.schedule,
              title: 'Date & Time',
              content: DateFormat('EEEE, MMMM d, y \'at\' HH:mm').format(event.dateTime),
            ),
            const SizedBox(height: 16),

            // Description
            if (event.description.isNotEmpty) ...[
              _DetailSection(
                icon: Icons.description,
                title: 'Description',
                content: event.description,
              ),
              const SizedBox(height: 16),
            ],

            // Participants
            if (event.participants.isNotEmpty) ...[
              _DetailSection(
                icon: Icons.people,
                title: 'Participants (${event.participants.length})',
                content: event.participants.join('\n'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getEventIcon(String type) {
    switch (type.toLowerCase()) {
      case 'meeting':
        return Icons.groups;
      case 'call':
        return Icons.phone;
      case 'video call':
        return Icons.videocam;
      case 'presentation':
        return Icons.present_to_all;
      case 'discussion':
        return Icons.chat;
      default:
        return Icons.event;
    }
  }

  void _deleteEvent(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Event'),
          content: const Text('Are you sure you want to delete this event?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                context.read<EventProvider>().deleteEvent(event.id);
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Close detail screen
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}

class _DetailSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;

  const _DetailSection({
    required this.icon,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FDFB), // Slight tint to soften contrast
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF009E86), // Teal accent outline
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF1E3A3A)), // Background color for icons
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E3A3A), // Background color for section labels
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black, // Black for subtext
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// Mobile Calendar View
class MobileCalendarView extends StatefulWidget {
  const MobileCalendarView({super.key});

  @override
  State<MobileCalendarView> createState() => _MobileCalendarViewState();
}

class _MobileCalendarViewState extends State<MobileCalendarView> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Top navigation
        Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF2A4F4F),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _currentIndex = 0;
                    });
                    _pageController.animateToPage(
                      0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _currentIndex == 0 ? Colors.tealAccent : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Calendar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _currentIndex == 0 ? Color(0xFF1E3A3A) : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _currentIndex = 1;
                    });
                    _pageController.animateToPage(
                      1,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: _currentIndex == 1 ? Colors.tealAccent : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Events',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _currentIndex == 1 ? Color(0xFF1E3A3A) : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Page view content
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF2A4F4F),
              borderRadius: BorderRadius.circular(16),
            ),
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              children: const [
                CalendarWithEventsScreen(),
                AllEventsScreen(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}


// Calendar with Events Screen
class CalendarWithEventsScreen extends StatefulWidget {
  const CalendarWithEventsScreen({super.key});

  @override
  State<CalendarWithEventsScreen> createState() => _CalendarWithEventsScreenState();
}

class _CalendarWithEventsScreenState extends State<CalendarWithEventsScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EventProvider>().selectDay(_selectedDay);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Calendar Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1);
                  });
                },
                icon: const Icon(Icons.chevron_left, color: Colors.white),
              ),
              Text(
                DateFormat('MMMM yyyy').format(_focusedDay),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1);
                  });
                },
                icon: const Icon(Icons.chevron_right, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Calendar Grid
          Expanded(
            flex: 3,
            child: Consumer<EventProvider>(
              builder: (context, eventProvider, child) {
                return Column(
                  children: [
                    // Weekday headers
                    Row(
                      children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                          .map((day) => Expanded(
                                child: Center(
                                  child: Text(
                                    day,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 8),
                    // Calendar grid
                    Expanded(
                      child: GridView.builder(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          childAspectRatio: 1,
                        ),
                        itemCount: 42,
                        itemBuilder: (context, index) {
                          final firstDayOfMonth = DateTime(_focusedDay.year, _focusedDay.month, 1);
                          final firstWeekday = firstDayOfMonth.weekday;
                          final dayNumber = index - (firstWeekday - 2);
                          final daysInMonth = DateTime(_focusedDay.year, _focusedDay.month + 1, 0).day;

                          if (dayNumber < 1 || dayNumber > daysInMonth) {
                            return const SizedBox();
                          }

                          final date = DateTime(_focusedDay.year, _focusedDay.month, dayNumber);
                          final isSelected = date.year == _selectedDay.year &&
                                           date.month == _selectedDay.month &&
                                           date.day == _selectedDay.day;
                          final isToday = date.year == DateTime.now().year &&
                                         date.month == DateTime.now().month &&
                                         date.day == DateTime.now().day;
                          final hasEvents = eventProvider.getEventsForDay(date).isNotEmpty;

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedDay = date;
                              });
                              eventProvider.selectDay(date);
                            },
                            child: Container(
                              margin: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.tealAccent
                                    : isToday
                                        ? Colors.tealAccent.withValues(alpha: 0.3)
                                        : null,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Stack(
                                children: [
                                  Center(
                                    child: Text(
                                      dayNumber.toString(),
                                      style: TextStyle(
                                        color: isSelected
                                            ? Color(0xFF1E3A3A)
                                            : isToday
                                                ? Colors.tealAccent
                                                : Colors.white,
                                        fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  if (hasEvents)
                                    Positioned(
                                      bottom: 4,
                                      right: 4,
                                      child: Container(
                                        width: 6,
                                        height: 6,
                                        decoration: BoxDecoration(
                                          color: isSelected ? const Color(0xFF1E3A3A) : Colors.orange,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 8),

          // Events for Selected Day
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF3A5F5F),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    'Events for ${DateFormat('MMM d, y').format(_selectedDay)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Consumer<EventProvider>(
                      builder: (context, eventProvider, child) {
                        final events = eventProvider.getEventsForDay(_selectedDay);

                        if (events.isEmpty) {
                          return const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.event_note,
                                  size: 48,
                                  color: Colors.white54,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'No events scheduled',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.builder(
                          itemCount: events.length,
                          itemBuilder: (context, index) {
                            final event = events[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: event.color.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: event.color,
                                  width: 1,
                                ),
                              ),
                              child: InkWell(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => EditEventScreen(event: event),
                                    ),
                                  );
                                },
                                onLongPress: () {
                                  _showDeleteDialog(context, event, eventProvider);
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            event.title,
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          DateFormat('HH:mm').format(event.dateTime),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (event.description.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        event.description,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(BuildContext context, Event event, EventProvider eventProvider) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Event'),
          content: Text('Are you sure you want to delete "${event.title}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                eventProvider.deleteEvent(event.id);
                Navigator.of(context).pop();
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }
}

// Calendar Screen
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EventProvider>().selectDay(_selectedDay);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GestureDetector(
        onHorizontalDragEnd: (DragEndDetails details) {
          // Swipe left to go to next month
          if (details.primaryVelocity! < -500) {
            setState(() {
              _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1);
              _selectedDay = _focusedDay;
            });
            context.read<EventProvider>().selectDay(_selectedDay);
          }
          // Swipe right to go to previous month
          else if (details.primaryVelocity! > 500) {
            setState(() {
              _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1);
              _selectedDay = _focusedDay;
            });
            context.read<EventProvider>().selectDay(_selectedDay);
          }
        },
        child: Column(
          children: [
            // Header with month/year
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _focusedDay = DateTime(_focusedDay.year, _focusedDay.month - 1);
                          _selectedDay = _focusedDay;
                        });
                        context.read<EventProvider>().selectDay(_selectedDay);
                      },
                      icon: const Icon(Icons.chevron_left, color: Colors.white70),
                    ),
                    GestureDetector(
                      onTap: () => _showDatePicker(context),
                      child: Row(
                        children: [
                          Text(
                            DateFormat('MMMM y').format(_focusedDay),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.white70,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        setState(() {
                          _focusedDay = DateTime(_focusedDay.year, _focusedDay.month + 1);
                          _selectedDay = _focusedDay;
                        });
                        context.read<EventProvider>().selectDay(_selectedDay);
                      },
                      icon: const Icon(Icons.chevron_right, color: Colors.white70),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.filter_list, color: Colors.white70),
                    ),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.more_horiz, color: Colors.white70),
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 20),

          // Days of week
          Row(
            children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                .map((day) => Expanded(
                      child: Center(
                        child: Text(
                          day,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 16),

          // Calendar Grid
          Expanded(
            child: Consumer<EventProvider>(
              builder: (context, eventProvider, child) {
                return ModernCalendarGrid(
                  focusedDay: _focusedDay,
                  selectedDay: _selectedDay,
                  onDaySelected: (selectedDay) {
                    setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = selectedDay;
                    });
                    context.read<EventProvider>().selectDay(selectedDay);
                  },
                  eventProvider: eventProvider,
                );
              },
            ),
          ),
        ],
        ),
      ),
    );
  }

  void _showDatePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2A4F4F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DatePickerModal(
        initialDate: _focusedDay,
        onDateSelected: (date) {
          setState(() {
            _focusedDay = date;
            _selectedDay = date;
          });
          context.read<EventProvider>().selectDay(date);
          Navigator.pop(context);
        },
      ),
    );
  }
}

// Date Picker Modal
class DatePickerModal extends StatefulWidget {
  final DateTime initialDate;
  final Function(DateTime) onDateSelected;

  const DatePickerModal({
    super.key,
    required this.initialDate,
    required this.onDateSelected,
  });

  @override
  State<DatePickerModal> createState() => _DatePickerModalState();
}

class _DatePickerModalState extends State<DatePickerModal> {
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Choose Date',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Row(
                children: [
                  DropdownButton<String>(
                    value: DateFormat('MMMM').format(_selectedDate),
                    dropdownColor: const Color(0xFF2A4F4F),
                    style: const TextStyle(color: Colors.white),
                    underline: Container(),
                    items: List.generate(12, (index) {
                      final month = DateTime(2022, index + 1);
                      return DropdownMenuItem(
                        value: DateFormat('MMMM').format(month),
                        child: Text(DateFormat('MMMM').format(month)),
                      );
                    }),
                    onChanged: (value) {
                      // Update month logic here
                    },
                  ),
                  const SizedBox(width: 10),
                  DropdownButton<String>(
                    value: _selectedDate.year.toString(),
                    dropdownColor: const Color(0xFF2A4F4F),
                    style: const TextStyle(color: Colors.white),
                    underline: Container(),
                    items: List.generate(10, (index) {
                      final year = DateTime.now().year + index - 5;
                      return DropdownMenuItem(
                        value: year.toString(),
                        child: Text(year.toString()),
                      );
                    }),
                    onChanged: (value) {
                      // Update year logic here
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Calendar Grid for Modal
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
              ),
              itemCount: 42,
              itemBuilder: (context, index) {
                final firstDayOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
                final firstWeekday = firstDayOfMonth.weekday;
                final dayNumber = index - (firstWeekday - 2);

                if (dayNumber < 1 || dayNumber > DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day) {
                  return const SizedBox();
                }

                final date = DateTime(_selectedDate.year, _selectedDate.month, dayNumber);
                final isSelected = date.day == _selectedDate.day;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedDate = date;
                    });
                  },
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.tealAccent : null,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        dayNumber.toString(),
                        style: TextStyle(
                          color: isSelected ? Color(0xFF1E3A3A) : Colors.white,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Cancel',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              ElevatedButton(
                onPressed: () => widget.onDateSelected(_selectedDate),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent,
                  foregroundColor: const Color(0xFF1E3A3A),
                ),
                child: const Text('Set Date'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Modern Calendar Grid
class ModernCalendarGrid extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime selectedDay;
  final Function(DateTime) onDaySelected;
  final EventProvider eventProvider;

  const ModernCalendarGrid({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.eventProvider,
  });

  @override
  Widget build(BuildContext context) {
    final firstDayOfMonth = DateTime(focusedDay.year, focusedDay.month, 1);
    final lastDayOfMonth = DateTime(focusedDay.year, focusedDay.month + 1, 0);
    final firstDayOfWeek = firstDayOfMonth.weekday;
    final daysInMonth = lastDayOfMonth.day;

    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1,
      ),
      itemCount: 42,
      itemBuilder: (context, index) {
        final dayNumber = index - (firstDayOfWeek - 2);

        if (dayNumber < 1 || dayNumber > daysInMonth) {
          return const SizedBox();
        }

        final date = DateTime(focusedDay.year, focusedDay.month, dayNumber);
        final isSelected = date.year == selectedDay.year &&
                          date.month == selectedDay.month &&
                          date.day == selectedDay.day;
        final isToday = date.year == DateTime.now().year &&
                       date.month == DateTime.now().month &&
                       date.day == DateTime.now().day;
        final hasEvents = eventProvider.getEventsForDay(date).isNotEmpty;

        return GestureDetector(
          onTap: () => onDaySelected(date),
          child: Container(
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: isSelected
                  ? Colors.tealAccent
                  : isToday
                      ? Colors.tealAccent.withValues(alpha: 0.3)
                      : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                Center(
                  child: Text(
                    dayNumber.toString(),
                    style: TextStyle(
                      color: isSelected
                          ? Color(0xFF1E3A3A)
                          : Colors.white,
                      fontWeight: isSelected || isToday ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
                if (hasEvents)
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF1E3A3A) : Colors.orange,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Event Detail Panel
class EventDetailPanel extends StatelessWidget {
  const EventDetailPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Consumer<EventProvider>(
        builder: (context, eventProvider, child) {
          final events = eventProvider.eventsForSelectedDay;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    DateFormat('dd').format(eventProvider.selectedDay),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        DateFormat('EEE').format(eventProvider.selectedDay),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        DateFormat('MMMM').format(eventProvider.selectedDay),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Events for selected day
              Expanded(
                child: events.isNotEmpty
                    ? ListView.builder(
                        itemCount: events.length,
                        itemBuilder: (context, index) {
                          final event = events[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF3A5F5F),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      DateFormat('HH:mm').format(event.dateTime),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      event.type,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  event.title,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  event.description,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 14,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (event.participants.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      ...List.generate(
                                        event.participants.length.clamp(0, 3),
                                        (index) => Container(
                                          margin: const EdgeInsets.only(right: 4),
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: Colors.primaries[index % Colors.primaries.length],
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              event.participants[index].substring(0, 1).toUpperCase(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (event.participants.length > 3)
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: const BoxDecoration(
                                            color: Colors.grey,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(
                                              '+${event.participants.length - 3}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      )
                    : Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A5F5F),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Text(
                            'No events scheduled\nfor this day',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}// ============================================================================
// NEW FEATURES
// ============================================================================

// 1. Week View Component
class WeekView extends StatefulWidget {
  const WeekView({super.key});

  @override
  State<WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends State<WeekView> {
  DateTime _selectedWeek = DateTime.now();

  DateTime get _weekStart {
    final diff = _selectedWeek.weekday - 1;
    return _selectedWeek.subtract(Duration(days: diff));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Week navigation
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedWeek = _selectedWeek.subtract(const Duration(days: 7));
                  });
                },
                icon: const Icon(Icons.chevron_left, color: Colors.white),
              ),
              Text(
                '${DateFormat('MMM d').format(_weekStart)} - ${DateFormat('MMM d, y').format(_weekStart.add(const Duration(days: 6)))}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedWeek = _selectedWeek.add(const Duration(days: 7));
                  });
                },
                icon: const Icon(Icons.chevron_right, color: Colors.white),
              ),
            ],
          ),
        ),
        // Week view grid
        Expanded(
          child: Consumer<EventProvider>(
            builder: (context, eventProvider, child) {
              return Row(
                children: List.generate(7, (index) {
                  final day = _weekStart.add(Duration(days: index));
                  final dayEvents = eventProvider.getEventsForDay(day);

                  return Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF3A5F5F),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          // Day header
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                              children: [
                                Text(
                                  DateFormat('EEE').format(day),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  day.day.toString(),
                                  style: TextStyle(
                                    color: _isSameDay(day, DateTime.now())
                                        ? Colors.tealAccent
                                        : Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Events
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.all(4),
                              itemCount: dayEvents.length,
                              itemBuilder: (context, eventIndex) {
                                final event = dayEvents[eventIndex];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 4),
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: event.color.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        DateFormat('HH:mm').format(event.dateTime),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        event.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ),
      ],
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

// 2. Search and Filter Component
class EventSearchDelegate extends SearchDelegate<Event?> {
  final List<Event> events;

  EventSearchDelegate(this.events);

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: const Icon(Icons.clear),
        onPressed: () {
          query = '';
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () {
        close(context, null);
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return buildSuggestions(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final filteredEvents = events.where((event) {
      return event.title.toLowerCase().contains(query.toLowerCase()) ||
             event.description.toLowerCase().contains(query.toLowerCase()) ||
             event.type.toLowerCase().contains(query.toLowerCase()) ||
             event.participants.any((p) => p.toLowerCase().contains(query.toLowerCase()));
    }).toList();

    return ListView.builder(
      itemCount: filteredEvents.length,
      itemBuilder: (context, index) {
        final event = filteredEvents[index];
        return ListTile(
          leading: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: event.color,
              shape: BoxShape.circle,
            ),
          ),
          title: Text(event.title),
          subtitle: Text(
            '${DateFormat('MMM dd, yyyy HH:mm').format(event.dateTime)} • ${event.type}',
          ),
          trailing: Text(event.description),
          onTap: () {
            close(context, event);
          },
        );
      },
    );
  }
}

// 3. Event Templates System
class EventTemplate {
  final String id;
  final String name;
  final String title;
  final String description;
  final String type;
  final Duration duration;
  final List<String> defaultParticipants;
  final Color color;
  final List<int> reminderMinutes;

  EventTemplate({
    required this.id,
    required this.name,
    required this.title,
    required this.description,
    required this.type,
    required this.duration,
    this.defaultParticipants = const [],
    required this.color,
    this.reminderMinutes = const [10],
  });
}

class EventTemplateService {
  static final List<EventTemplate> _defaultTemplates = [
    EventTemplate(
      id: 'daily_standup',
      name: 'Daily Standup',
      title: 'Daily Standup',
      description: 'Team sync meeting',
      type: 'Meeting',
      duration: const Duration(minutes: 15),
      color: Colors.blue,
      reminderMinutes: [5],
    ),
    EventTemplate(
      id: 'one_on_one',
      name: '1:1 Meeting',
      title: '1:1 Meeting',
      description: 'One-on-one discussion',
      type: 'Meeting',
      duration: const Duration(minutes: 30),
      color: Colors.green,
      reminderMinutes: [10],
    ),
    EventTemplate(
      id: 'client_call',
      name: 'Client Call',
      title: 'Client Call',
      description: 'Client discussion call',
      type: 'Call',
      duration: const Duration(hours: 1),
      color: Colors.purple,
      reminderMinutes: [15, 60],
    ),
  ];

  static List<EventTemplate> getTemplates() => _defaultTemplates;

  static Event createEventFromTemplate(EventTemplate template, DateTime dateTime) {
    return Event(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: template.title,
      description: template.description,
      dateTime: dateTime,
      type: template.type,
      participants: template.defaultParticipants,
      color: template.color,
      reminderMinutes: template.reminderMinutes,
    );
  }
}

// 4. Calendar Export/Import Service
class CalendarImportExportService {
  static String exportToICS(List<Event> events) {
    final buffer = StringBuffer();
    buffer.writeln('BEGIN:VCALENDAR');
    buffer.writeln('VERSION:2.0');
    buffer.writeln('PRODID:-//Calendar Planner//Calendar Planner//EN');

    for (final event in events) {
      buffer.writeln('BEGIN:VEVENT');
      buffer.writeln('UID:${event.id}@calendarplanner.com');
      buffer.writeln('DTSTART:${_formatDateTimeToICS(event.dateTime)}');
      buffer.writeln('DTEND:${_formatDateTimeToICS(event.dateTime.add(const Duration(hours: 1)))}');
      buffer.writeln('SUMMARY:${event.title}');
      buffer.writeln('DESCRIPTION:${event.description}');
      buffer.writeln('CATEGORIES:${event.type}');

      if (event.recurrenceRule != null) {
        buffer.writeln('RRULE:${_convertRecurrenceRule(event.recurrenceRule!)}');
      }

      buffer.writeln('END:VEVENT');
    }

    buffer.writeln('END:VCALENDAR');
    return buffer.toString();
  }

  static String _formatDateTimeToICS(DateTime dateTime) {
    return dateTime.toUtc().toIso8601String().replaceAll('-', '').replaceAll(':', '').split('.')[0] + 'Z';
  }

  static String _convertRecurrenceRule(String rule) {
    switch (rule.toLowerCase()) {
      case 'daily': return 'FREQ=DAILY';
      case 'weekly': return 'FREQ=WEEKLY';
      case 'monthly': return 'FREQ=MONTHLY';
      case 'yearly': return 'FREQ=YEARLY';
      default: return 'FREQ=DAILY';
    }
  }
}

// 5. Time Tracking Feature
class TimeTrackingService {
  static final Map<String, DateTime?> _startTimes = {};
  static final Map<String, Duration> _totalTimes = {};

  static void startTracking(String eventId) {
    _startTimes[eventId] = DateTime.now();
  }

  static Duration? stopTracking(String eventId) {
    final startTime = _startTimes[eventId];
    if (startTime != null) {
      final duration = DateTime.now().difference(startTime);
      _totalTimes[eventId] = (_totalTimes[eventId] ?? Duration.zero) + duration;
      _startTimes.remove(eventId);
      return duration;
    }
    return null;
  }

  static Duration getTotalTime(String eventId) {
    return _totalTimes[eventId] ?? Duration.zero;
  }

  static bool isTracking(String eventId) {
    return _startTimes.containsKey(eventId);
  }

  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

// 6. Analytics and Insights
class CalendarAnalytics {
  static Map<String, int> getEventTypeDistribution(List<Event> events) {
    final Map<String, int> distribution = {};
    for (final event in events) {
      distribution[event.type] = (distribution[event.type] ?? 0) + 1;
    }
    return distribution;
  }

  static Duration getAverageMeetingDuration(List<Event> events) {
    final meetings = events.where((e) => e.type.toLowerCase().contains('meeting')).toList();
    if (meetings.isEmpty) return Duration.zero;

    final totalMinutes = meetings.length * 60; // Assuming 1 hour default
    return Duration(minutes: totalMinutes ~/ meetings.length);
  }

  static Map<String, int> getBusiestDaysOfWeek(List<Event> events) {
    final Map<String, int> dayCount = {
      'Monday': 0, 'Tuesday': 0, 'Wednesday': 0, 'Thursday': 0,
      'Friday': 0, 'Saturday': 0, 'Sunday': 0
    };

    for (final event in events) {
      final dayName = DateFormat('EEEE').format(event.dateTime);
      dayCount[dayName] = (dayCount[dayName] ?? 0) + 1;
    }

    return dayCount;
  }
}