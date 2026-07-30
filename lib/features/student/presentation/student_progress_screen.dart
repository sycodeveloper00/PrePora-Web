import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/professional_loader.dart';

class StudentProgressScreen extends StatefulWidget {
  final String? targetUid;
  final bool embedded;
  const StudentProgressScreen({super.key, this.targetUid, this.embedded = false});

  @override
  State<StudentProgressScreen> createState() => _StudentProgressScreenState();
}

class _StudentProgressScreenState extends State<StudentProgressScreen> with SingleTickerProviderStateMixin {
  bool _isVerified = false;
  bool _isBlocked = true;
  String _email = '';
  String _studentName = '';
  String _gender = '';
  List<Map<String, dynamic>> _feedbacks = [];
  bool _loadingUser = true;

  int _streakCount = 0;
  int _totalActiveDays = 0;
  String _lastActiveDate = '';
  int _streakBest = 0;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  String get _uid => widget.targetUid ?? FirebaseService.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnimation = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
    _loadUserData();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final uid = _uid;
    if (uid.isEmpty) {
      if (mounted) setState(() => _loadingUser = false);
      return;
    }
    final results = await Future.wait([
      FirebaseService.getUserData(uid),
      FirebaseService.getStudentFeedbacks(uid),
      FirebaseService.getStreak(uid),
    ]);
    final userData = results[0] as Map<String, dynamic>?;
    final feedbacks = results[1] as List<Map<String, dynamic>>;
    final streak = results[2] as Map<String, dynamic>;
    if (mounted) {
      setState(() {
        _isVerified = userData?['verified'] == true;
        _isBlocked = userData?['blocked'] == true;
        _email = userData?['email'] as String? ?? '';
        _studentName = userData?['name'] as String? ?? '';
        _gender = userData?['gender'] as String? ?? '';
        _feedbacks = feedbacks;
        _streakCount = streak['streakCount'] as int? ?? 0;
        _totalActiveDays = streak['totalActiveDays'] as int? ?? 0;
        _lastActiveDate = streak['lastActiveDate'] as String? ?? '';
        _streakBest = userData?['streakBest'] as int? ?? _streakCount;
        _loadingUser = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0A0A1A) : const Color(0xFFF5F5FA);
    final textColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white54 : Colors.black45;
    final cardColor = isDark ? const Color(0xFF13132D) : Colors.white;
    final isTargetUser = widget.targetUid != null;

    return Scaffold(
      backgroundColor: bgColor,
      body: _uid.isEmpty
          ? Center(child: Text('No student selected', style: TextStyle(color: dimColor)))
          : _loadingUser
              ? const Center(child: ProfessionalLoader())
              : FadeTransition(
                  opacity: _fadeAnimation,
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      if (!widget.embedded) _buildAppBar(isDark, textColor, isTargetUser),
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildProfileHeader(cardColor, textColor, dimColor, isDark),
                            const SizedBox(height: 6),
                            _buildStatusBubbles(cardColor, textColor, dimColor, isDark),
                            const SizedBox(height: 6),
                            _buildStreakCard(cardColor, textColor, dimColor, isDark),
                          ],
                        ),
                      ),
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseService.getStudentActivities(_uid),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting) {
                            return const SliverFillRemaining(child: Center(child: ProfessionalLoader()));
                          }
                          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                            return SliverFillRemaining(
                              child: SingleChildScrollView(
                                child: Column(children: [
                                  const SizedBox(height: 40),
                                  Icon(Icons.bar_chart_rounded, size: 64, color: dimColor),
                                  const SizedBox(height: 12),
                                  Text('No activity yet', style: TextStyle(color: dimColor, fontSize: 16, fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 6),
                                  Text('Start exploring content to see your progress', style: TextStyle(color: dimColor, fontSize: 13)),
                                ]),
                              ),
                            );
                          }
                          final docs = snapshot.data!.docs.toList()
                            ..sort((a, b) {
                              final aTime = (a.data() as Map<String, dynamic>)['startedAt'] as Timestamp?;
                              final bTime = (b.data() as Map<String, dynamic>)['startedAt'] as Timestamp?;
                              return (bTime?.toDate() ?? DateTime(2000)).compareTo(aTime?.toDate() ?? DateTime(2000));
                            });
                          return SliverToBoxAdapter(
                            child: _buildStatsContent(docs, cardColor, textColor, dimColor, isDark),
                          );
                        },
                      ),
                    ],
                  ),
                ),
    );
  }

  // ─── AppBar ─────────────────────────────────────────────────────────────────
  Widget _buildAppBar(bool isDark, Color textColor, bool isTargetUser) {
    return SliverAppBar(
      backgroundColor: isDark ? const Color(0xFF0F0F2A) : Colors.white,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isTargetUser ? (_studentName.isNotEmpty ? _studentName : 'Student') : 'My Progress',
            style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ],
      ),
      pinned: true,
      snap: false,
      floating: false,
      expandedHeight: 0,
    );
  }

  // ─── Profile Header ─────────────────────────────────────────────────────────
  Widget _buildProfileHeader(Color cardColor, Color textColor, Color dimColor, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Row(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFF448AFF)]),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: const Color(0xFF7C4DFF).withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: Center(
                child: Text(
                  _studentName.isNotEmpty ? _studentName[0].toUpperCase() : '?',
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_studentName.isNotEmpty ? _studentName : 'Student', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 17)),
                  const SizedBox(height: 3),
                  Text(_email, style: TextStyle(color: dimColor, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 3),
                  Row(children: [
                    Icon(Icons.circle, size: 6, color: _isBlocked ? Colors.orange : Colors.green),
                    const SizedBox(width: 5),
                    Text(_isBlocked ? 'Blocked' : 'Active', style: TextStyle(color: _isBlocked ? Colors.orange : Colors.green, fontSize: 11, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    if (_lastActiveDate.isNotEmpty) ...[
                      Icon(Icons.access_time_rounded, size: 12, color: dimColor),
                      const SizedBox(width: 4),
                      Text('Last: $_lastActiveDate', style: TextStyle(color: dimColor, fontSize: 11)),
                    ],
                  ]),
                ],
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ─── Status Bubbles ─────────────────────────────────────────────────────────
  Widget _buildStatusBubbles(Color cardColor, Color textColor, Color dimColor, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (_isVerified) {
                  _showFeeDetailsDialog();
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Account not verified yet. Contact support after payment.'),
                      backgroundColor: Colors.orange,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                }
              },
              child: _statusCard(
                icon: _isVerified ? Icons.verified_rounded : Icons.cancel_rounded,
                iconColor: _isVerified ? Colors.green : Colors.redAccent,
                label: 'Fee Status',
                value: _isVerified ? 'Verified' : 'Not Verified',
                trailing: _isVerified ? Icons.chevron_right_rounded : null,
                isDark: isDark,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _statusCard(
              icon: !_isBlocked ? Icons.check_circle_rounded : Icons.block_rounded,
              iconColor: !_isBlocked ? Colors.teal : Colors.orange,
              label: 'Account',
              value: !_isBlocked ? 'Active' : 'Blocked',
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard({required IconData icon, required Color iconColor, required String label, required String value, IconData? trailing, required bool isDark}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iconColor.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(color: iconColor, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 12)),
          ]),
        ),
        if (trailing != null) Icon(trailing, color: iconColor.withValues(alpha: 0.6), size: 18),
      ]),
    );
  }

  // ─── Streak Card ────────────────────────────────────────────────────────────
  Widget _buildStreakCard(Color cardColor, Color textColor, Color dimColor, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _streakCount > 0
              ? [const Color(0xFFFF6B35), const Color(0xFFFF8F00)]
              : [isDark ? Colors.white10 : Colors.grey.shade200, isDark ? Colors.white10 : Colors.grey.shade100],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: _streakCount > 0 ? [BoxShadow(color: const Color(0xFFFF6B35).withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))] : [],
      ),
      child: Row(
        children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: _streakCount > 0 ? Colors.white.withValues(alpha: 0.25) : (isDark ? Colors.white12 : Colors.black12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(_streakCount > 0 ? '\uD83D\uDD25' : '\uD83D\uDCA4', style: const TextStyle(fontSize: 28)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                _streakCount > 0 ? '$_streakCount Day Streak!' : 'No Active Streak',
                style: TextStyle(
                  color: _streakCount > 0 ? Colors.white : textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _streakCount > 0 ? 'Keep it up! Study today to maintain your streak.' : 'Start studying to build your streak.',
                style: TextStyle(color: _streakCount > 0 ? Colors.white.withValues(alpha: 0.8) : dimColor, fontSize: 12),
              ),
            ]),
          ),
          Column(children: [
            _streakBadge('$_totalActiveDays', 'Days', isDark, _streakCount > 0),
            if (_streakBest > 0) ...[
              const SizedBox(height: 4),
              _streakBadge('$_streakBest', 'Best', isDark, _streakCount > 0),
            ],
          ]),
        ],
      ),
    );
  }

  Widget _streakBadge(String val, String label, bool isDark, bool isActive) {
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? Colors.white.withValues(alpha: 0.25) : (isDark ? Colors.white12 : Colors.black12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(val, style: TextStyle(color: isActive ? Colors.white : (isDark ? Colors.white70 : Colors.black54), fontSize: 16, fontWeight: FontWeight.bold)),
      ),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(color: isActive ? Colors.white.withValues(alpha: 0.7) : (isDark ? Colors.white38 : Colors.black38), fontSize: 10)),
    ]);
  }

  // ─── Stats Content (from activities) ────────────────────────────────────────
  Widget _buildStatsContent(List<QueryDocumentSnapshot> docs, Color cardColor, Color textColor, Color dimColor, bool isDark) {
    final totalCount = docs.length;
    final now = DateTime.now();

    int totalMinutes = 0;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
      final endedAt = (data['endedAt'] as Timestamp?)?.toDate();
      if (startedAt != null && endedAt != null) {
        totalMinutes += endedAt.difference(startedAt).inMinutes;
      }
    }
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;

    final lectures = docs.where((d) => (d.data() as Map)['type'] == 'lecture').length;
    final files = docs.where((d) => (d.data() as Map)['type'] == 'file').length;
    final mockTests = docs.where((d) {
      final t = (d.data() as Map)['type'] as String? ?? '';
      return t.contains('mocktest');
    }).length;

    final last7Days = List.generate(7, (i) => now.subtract(Duration(days: 6 - i)));
    final dailyCounts = <int>[];
    for (final day in last7Days) {
      int count = 0;
      for (final doc in docs) {
        final data = doc.data() as Map<String, dynamic>;
        final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
        if (startedAt != null && startedAt.year == day.year && startedAt.month == day.month && startedAt.day == day.day) {
          count++;
        }
      }
      dailyCounts.add(count);
    }
    final maxCount = dailyCounts.isNotEmpty ? dailyCounts.reduce((a, b) => a > b ? a : b).toDouble() : 5.0;

    final last30Days = List.generate(30, (i) => now.subtract(Duration(days: 29 - i)));
    final monthlyCounts = <int>[];
    for (final day in last30Days) {
      int count = 0;
      for (final doc in docs) {
        final data = doc.data() as Map<String, dynamic>;
        final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
        if (startedAt != null && startedAt.year == day.year && startedAt.month == day.month && startedAt.day == day.day) {
          count++;
        }
      }
      monthlyCounts.add(count);
    }
    final maxMonthly = monthlyCounts.isNotEmpty ? monthlyCounts.reduce((a, b) => a > b ? a : b).toDouble() : 5.0;

    final subjectMap = <String, int>{};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final folderPath = data['folderPath'] as String? ?? '';
      final name = data['name'] as String? ?? 'Unknown';
      final subject = folderPath.isNotEmpty ? folderPath.split('/').first : name;
      subjectMap[subject] = (subjectMap[subject] ?? 0) + 1;
    }
    final sortedSubjects = subjectMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final topSubjects = sortedSubjects.take(6).toList();
    final maxSubjectCount = topSubjects.isNotEmpty ? topSubjects.first.value : 1;

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final startedAt = (data['startedAt'] as Timestamp?)?.toDate();
      if (startedAt == null) continue;
      final key = DateFormat('EEE, MMM d, yyyy').format(startedAt);
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add({...data, 'docId': doc.id});
    }

    final uniqueContentIds = <String>{};
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final contentId = data['contentId'] as String?;
      if (contentId != null) uniqueContentIds.add(contentId);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBigStatsCard(cardColor, hours, mins, totalCount, grouped.length, lectures, files, mockTests, isDark),
          const SizedBox(height: 14),
          _buildWeeklyChart(dailyCounts, last7Days, maxCount, cardColor, textColor, dimColor, isDark),
          const SizedBox(height: 14),
          _buildSubjectBreakdown(topSubjects, maxSubjectCount, cardColor, textColor, dimColor, isDark),
          const SizedBox(height: 14),
          _buildMonthlyChart(monthlyCounts, last30Days, maxMonthly, cardColor, textColor, dimColor, isDark),
          const SizedBox(height: 14),
          _buildCompletionCard(uniqueContentIds.length, totalCount, cardColor, textColor, dimColor, isDark),
          const SizedBox(height: 14),
          _buildActivityHistory(grouped, cardColor, textColor, dimColor, isDark),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── Big Stats Card ─────────────────────────────────────────────────────────
  Widget _buildBigStatsCard(Color cardColor, int hours, int mins, int totalCount, int activeDays, int lectures, int files, int mockTests, bool isDark) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A148C), Color(0xFF7B1FA2), Color(0xFF9C27B0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: const Color(0xFF7B1FA2).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _statItem(Icons.access_time_rounded, '${hours}h ${mins}m', 'Total Time'),
            _statItem(Icons.touch_app_rounded, '$totalCount', 'Total Opens'),
            _statItem(Icons.calendar_today_rounded, '$activeDays', 'Active Days'),
          ]),
          const SizedBox(height: 16),
          Container(height: 1, color: Colors.white.withValues(alpha: 0.15)),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
            _miniStat(Icons.play_circle_outline_rounded, '$lectures', 'Lectures', Colors.redAccent),
            _miniStat(Icons.insert_drive_file_rounded, '$files', 'Files', Colors.blueAccent),
            _miniStat(Icons.quiz_rounded, '$mockTests', 'Tests', Colors.amber),
          ]),
        ],
      ),
    );
  }

  Widget _statItem(IconData icon, String value, String label) {
    return Column(children: [
      Icon(icon, color: Colors.white, size: 22),
      const SizedBox(height: 6),
      Text(value, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11)),
    ]);
  }

  Widget _miniStat(IconData icon, String value, String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 4),
      Text('$value ', style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 12, fontWeight: FontWeight.bold)),
      Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
    ]);
  }

  // ─── Weekly Chart ───────────────────────────────────────────────────────────
  Widget _buildWeeklyChart(List<int> dailyCounts, List<DateTime> last7Days, double maxCount, Color cardColor, Color textColor, Color dimColor, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.show_chart_rounded, 'Weekly Activity', textColor),
          const SizedBox(height: 10),
          Container(
            height: 180,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxCount < 1 ? 5 : (maxCount * 1.3).ceilToDouble(),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIdx, rod, rodIdx) {
                      return BarTooltipItem(
                        '${rod.toY.toInt()} opens',
                        const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: maxCount < 5 ? 1 : (maxCount / 3).ceilToDouble(),
                      getTitlesWidget: (value, meta) {
                        if (value == value.roundToDouble()) {
                          return Text('${value.toInt()}', style: TextStyle(color: dimColor, fontSize: 10));
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < last7Days.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(DateFormat('E').format(last7Days[idx]), style: TextStyle(color: dimColor, fontSize: 10)),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxCount < 5 ? 1 : (maxCount / 3).ceilToDouble(),
                  getDrawingHorizontalLine: (value) => FlLine(color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04), strokeWidth: 1),
                ),
                barGroups: List.generate(7, (i) {
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: dailyCounts[i].toDouble(),
                        width: 22,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        color: dailyCounts[i] > 0
                            ? const Color(0xFF7C4DFF)
                            : (isDark ? Colors.white12 : Colors.black12),
                      ),
                    ],
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Monthly Chart ──────────────────────────────────────────────────────────
  Widget _buildMonthlyChart(List<int> monthlyCounts, List<DateTime> last30Days, double maxMonthly, Color cardColor, Color textColor, Color dimColor, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.insights_rounded, 'Monthly Trend', textColor),
          const SizedBox(height: 10),
          Container(
            height: 200,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxMonthly < 1 ? 5 : (maxMonthly * 1.3).ceilToDouble(),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (spots) {
                      return spots.map((spot) {
                        final idx = spot.x.toInt();
                        final date = idx >= 0 && idx < last30Days.length ? DateFormat('MMM d').format(last30Days[idx]) : '';
                        return LineTooltipItem(
                          '$date\n${spot.y.toInt()} opens',
                          const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        );
                      }).toList();
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: maxMonthly < 5 ? 1 : (maxMonthly / 4).ceilToDouble(),
                      getTitlesWidget: (value, meta) {
                        if (value == value.roundToDouble()) {
                          return Text('${value.toInt()}', style: TextStyle(color: dimColor, fontSize: 10));
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 5,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx >= 0 && idx < last30Days.length && idx % 5 == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(DateFormat('d').format(last30Days[idx]), style: TextStyle(color: dimColor, fontSize: 9)),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: maxMonthly < 5 ? 1 : (maxMonthly / 4).ceilToDouble(),
                  getDrawingHorizontalLine: (value) => FlLine(color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04), strokeWidth: 1),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(30, (i) => FlSpot(i.toDouble(), monthlyCounts[i].toDouble())),
                    isCurved: true,
                    preventCurveOverShooting: true,
                    color: const Color(0xFF00B8D4),
                    barWidth: 2.5,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) {
                        return FlDotCirclePainter(
                          radius: spot.y > 0 ? 3 : 0,
                          color: const Color(0xFF00B8D4),
                          strokeColor: cardColor,
                          strokeWidth: 2,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [const Color(0xFF00B8D4).withValues(alpha: 0.2), const Color(0xFF00B8D4).withValues(alpha: 0.02)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
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

  // ─── Subject Breakdown ──────────────────────────────────────────────────────
  Widget _buildSubjectBreakdown(List<MapEntry<String, int>> topSubjects, int maxCount, Color cardColor, Color textColor, Color dimColor, bool isDark) {
    if (topSubjects.isEmpty) return const SizedBox.shrink();

    final colors = [
      const Color(0xFF7C4DFF), const Color(0xFF00B8D4), const Color(0xFFFF6B35),
      const Color(0xFFE91E63), const Color(0xFF4CAF50), const Color(0xFFFFC107),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.pie_chart_rounded, 'Subject Focus', textColor),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: Column(
              children: List.generate(topSubjects.length, (i) {
                final entry = topSubjects[i];
                final ratio = entry.value / maxCount;
                final color = colors[i % colors.length];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(entry.key, style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        Text('${entry.value}x', style: TextStyle(color: dimColor, fontSize: 11, fontWeight: FontWeight.bold)),
                      ]),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 6,
                          backgroundColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                          valueColor: AlwaysStoppedAnimation(color),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Completion Card ────────────────────────────────────────────────────────
  Widget _buildCompletionCard(int uniqueOpened, int totalOpens, Color cardColor, Color textColor, Color dimColor, bool isDark) {
    final percent = totalOpens > 0 ? ((uniqueOpened / (totalOpens > 0 ? totalOpens : 1)) * 100).clamp(0, 100) : 0.0;
    final displayPercent = percent.toInt();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.trending_up_rounded, 'Unique Content Explored', textColor),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 72, height: 72,
                  child: Stack(alignment: Alignment.center, children: [
                    CircularProgressIndicator(
                      value: displayPercent / 100,
                      strokeWidth: 7,
                      backgroundColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
                      valueColor: AlwaysStoppedAnimation(
                        displayPercent >= 70 ? Colors.green : displayPercent >= 40 ? const Color(0xFFFFC107) : const Color(0xFF7C4DFF),
                      ),
                      strokeCap: StrokeCap.round,
                    ),
                    Text(
                      '$displayPercent%',
                      style: TextStyle(
                        color: displayPercent >= 70 ? Colors.green : displayPercent >= 40 ? const Color(0xFFFFC107) : const Color(0xFF7C4DFF),
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('$uniqueOpened of $totalOpens opens', style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                      displayPercent >= 70
                          ? 'Excellent exploration! You\'re covering most content.'
                          : displayPercent >= 40
                              ? 'Good progress! Keep exploring more content.'
                              : 'Explore more content to improve your coverage.',
                      style: TextStyle(color: dimColor, fontSize: 12),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Activity History ───────────────────────────────────────────────────────
  Widget _buildActivityHistory(Map<String, List<Map<String, dynamic>>> grouped, Color cardColor, Color textColor, Color dimColor, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.history_rounded, 'Activity History', textColor),
          const SizedBox(height: 10),
          ...grouped.entries.map((entry) => _buildDateGroup(entry.key, entry.value, textColor, dimColor, isDark)),
        ],
      ),
    );
  }

  Widget _buildDateGroup(String date, List<Map<String, dynamic>> items, Color textColor, Color dimColor, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(color: Color(0xFF00B8D4), shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(date, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF00B8D4).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('${items.length}', style: const TextStyle(color: Color(0xFF00B8D4), fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ]),
          const SizedBox(height: 8),
          ...items.map((item) => _buildActivityItem(item, textColor, dimColor, isDark)),
        ],
      ),
    );
  }

  Widget _buildActivityItem(Map<String, dynamic> item, Color textColor, Color dimColor, bool isDark) {
    final name = item['name'] as String? ?? 'Unknown';
    final type = item['type'] as String? ?? 'file';
    final folderPath = item['folderPath'] as String? ?? '';
    final startedAt = (item['startedAt'] as Timestamp?)?.toDate();
    final endedAt = (item['endedAt'] as Timestamp?)?.toDate();

    IconData icon;
    Color iconColor;
    switch (type) {
      case 'lecture':
        icon = Icons.play_circle_outline_rounded;
        iconColor = Colors.redAccent;
        break;
      case 'mocktest_url':
      case 'mocktest_code':
        icon = Icons.quiz_rounded;
        iconColor = Colors.amber;
        break;
      default:
        icon = Icons.insert_drive_file_rounded;
        iconColor = const Color(0xFF448AFF);
    }

    String timeRange = '';
    String duration = '';
    if (startedAt != null) {
      final startStr = _formatTime(startedAt);
      if (endedAt != null) {
        final endStr = _formatTime(endedAt);
        timeRange = '$startStr – $endStr';
        final diff = endedAt.difference(startedAt);
        if (diff.inHours > 0) {
          duration = '${diff.inHours}h ${diff.inMinutes % 60}m';
        } else if (diff.inMinutes > 0) {
          duration = '${diff.inMinutes}m';
        } else {
          duration = '${diff.inSeconds}s';
        }
      } else {
        timeRange = startStr;
      }
    }

    final typeLabel = type == 'lecture'
        ? 'Lecture'
        : type.contains('mocktest')
            ? 'Mock Test'
            : 'File';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (folderPath.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(folderPath, style: TextStyle(color: dimColor, fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 3),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(typeLabel, style: TextStyle(color: iconColor, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ]),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (timeRange.isNotEmpty)
                Text(timeRange, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w600)),
              if (duration.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(duration, style: const TextStyle(color: Color(0xFF00B8D4), fontSize: 10, fontWeight: FontWeight.w500)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────────────
  Widget _sectionHeader(IconData icon, String title, Color textColor) {
    return Row(children: [
      Icon(icon, color: const Color(0xFF00B8D4), size: 20),
      const SizedBox(width: 8),
      Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 15)),
    ]);
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = h >= 12 ? 'PM' : 'AM';
    final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$h12:$m $period';
  }

  // ─── Fee Details Dialog ─────────────────────────────────────────────────────
  void _showFeeDetailsDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String? paymentMessage;
    for (final fb in _feedbacks) {
      final msg = fb['message'] as String? ?? '';
      if (msg.contains('Account Owner') || msg.contains('AccNo') || msg.contains('Bank Name')) {
        paymentMessage = msg;
        break;
      }
    }
    if (paymentMessage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('No payment details found'), backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      );
      return;
    }
    final fields = <String, String>{};
    for (final line in paymentMessage.split('\n')) {
      final idx = line.indexOf(':');
      if (idx != -1) {
        fields[line.substring(0, idx).trim()] = line.substring(idx + 1).trim();
      }
    }
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF13132D) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), shape: BoxShape.circle), child: const Icon(Icons.verified_rounded, color: Colors.green, size: 20)),
          const SizedBox(width: 10),
          Text('Fee Details', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _feeDetailRow(Icons.email_rounded, 'Registered Email', _email, isDark),
            const Divider(height: 20),
            ...fields.entries.map((e) => _feeDetailRow(_iconForField(e.key), e.key, e.value, isDark)),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text('Close', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)))],
      ),
    );
  }

  Widget _feeDetailRow(IconData icon, String label, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: const Color(0xFF00B8D4)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value.isNotEmpty ? value : '-', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.w600)),
        ])),
      ]),
    );
  }

  IconData _iconForField(String key) {
    final k = key.toLowerCase();
    if (k.contains('name') && !k.contains('bank') && !k.contains('owner')) return Icons.person_rounded;
    if (k.contains('email')) return Icons.email_rounded;
    if (k.contains('contact')) return Icons.phone_rounded;
    if (k.contains('owner')) return Icons.account_circle_rounded;
    if (k.contains('accno') || k.contains('account')) return Icons.account_balance_rounded;
    if (k.contains('bank')) return Icons.account_balance_wallet_rounded;
    if (k.contains('receipt')) return Icons.receipt_rounded;
    if (k.contains('city')) return Icons.location_city_rounded;
    if (k.contains('province')) return Icons.map_rounded;
    if (k.contains('course')) return Icons.school_rounded;
    if (k.contains('date')) return Icons.calendar_today_rounded;
    if (k.contains('time')) return Icons.access_time_rounded;
    return Icons.info_outline_rounded;
  }
}
