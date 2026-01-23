import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

// --- IMPORTS LOGIC & MODEL ---
import '../../../core/services/notification_service.dart';
import '../../../core/services/fcm_service.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../../models/wallet_model.dart';
import '../../../models/transaction_model.dart';
import '../../../core/constants/app_colors.dart';

// --- IMPORTS SCREEN LAIN ---
import '../../debts/presentation/debt_list_screen.dart';
import '../../notification/presentation/notification_screen.dart';
import '../../report/presentation/report_screen.dart';
import '../../settings/presentation/user_management_screen.dart';
import '../../transactions/presentation/add_transaction_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../employee/presentation/employee_list_screen.dart';
import '../../approval/presentation/approval_screen.dart';
import '../../report/presentation/monthly_report_screen.dart';
import '../../dashboard/presentation/transaction_history_screen.dart';
import '../../dashboard/presentation/wallet_detail_screen.dart';
import '../../transactions/data/transaction_repository.dart';
import '../logic/dashboard_cubit.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {

  // --- STATE USER & AKSES ---
  bool _isLoadingUser = true;
  String _userRole = '';
  String _userBranchId = '';
  String _selectedBranchId = 'pusat'; // Default cabang (dipakai untuk filter utang)

  // --- DATA TAB & CABANG (Untuk Owner) ---
  int _selectedTabIndex = 0;

  final List<String> _allTabs = ["Box Factory", "Maint. Alfa", "Saufa Olshop"];
  final List<String> _allBranchIds = ["bst_box", "m_alfa", "saufa"];
  final List<String> _allWalletIds = ["petty_bst", "petty_alfa", "petty_saufa"];

  List<String> _visibleTabs = [];
  List<String> _visibleBranchIds = [];
  List<String> _visibleWalletIds = [];
  StreamSubscription? _notifSubscription;

  @override
  void initState() {
    super.initState();
    // 1. Inisialisasi Service Notifikasi
    NotificationService().init();
    FCMService().init();

    // 2. Cek User & Mulai Monitoring Data
    _checkUserAccess();
    _initData();

    // 3. Panggil Cubit untuk stream data
    context.read<DashboardCubit>().startMonitoring();
  }

  @override
  void dispose() {
    _notifSubscription?.cancel();
    super.dispose();
  }

  void _initData() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      if (doc.exists && mounted) {
        setState(() {
          _userRole = doc['role'] ?? 'admin_branch';
          _userBranchId = doc['branch_id'] ?? 'bst_box';
        });

        // Setup Listener Notifikasi (Badge Merah)
        _setupNotificationListener();

        // Jalankan pengecekan harian (Reminder Gaji/Utang)
        _runDailyChecks(user.uid);
      }
    }
  }

  Future<void> _checkUserAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() { _isLoadingUser = false; });
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (!doc.exists) {
        if (mounted) setState(() { _userRole = 'user'; _userBranchId = 'unknown'; _setupLimitedView(); _isLoadingUser = false; });
        return;
      }

      final data = doc.data()!;
      if (mounted) {
        setState(() {
          _userRole = data['role'] ?? 'admin_branch';
          _userBranchId = data['branch_id'] ?? 'bst_box';

          // Konfigurasi Tab berdasarkan Role
          if (_userRole == 'owner') {
            _visibleTabs = List.from(_allTabs);
            _visibleBranchIds = List.from(_allBranchIds);
            _visibleWalletIds = List.from(_allWalletIds);
          } else {
            // Jika admin cabang, hanya lihat cabangnya sendiri
            int index = _allBranchIds.indexOf(_userBranchId);
            if (index != -1) {
              _visibleTabs = [_allTabs[index]];
              _visibleBranchIds = [_allBranchIds[index]];
              _visibleWalletIds = [_allWalletIds[index]];
              _selectedBranchId = _userBranchId;
            } else {
              _setupLimitedView();
            }
          }
          _isLoadingUser = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _setupLimitedView(); _isLoadingUser = false; });
    }
  }

  void _setupLimitedView() {
    _visibleTabs = ["Akses Terbatas"];
    _visibleBranchIds = ["unknown"];
    _visibleWalletIds = ["unknown"];
  }

  Future<void> _onRefresh() async {
    context.read<DashboardCubit>().startMonitoring();
    await _checkUserAccess();
  }

  // --- LOGIKA CEK HARIAN & NOTIFIKASI ---
  Future<void> _runDailyChecks(String userId) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayStr = DateFormat('yyyy-MM-dd').format(today);
    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);

    final userDoc = await userRef.get();
    String lastCheck = userDoc.data()?['last_daily_check'] ?? '';

    if (lastCheck == todayStr) return; // Sudah dicek hari ini

    // 1. Cek Jadwal Gaji (Setiap Tanggal 1)
    int paydayDay = 1;
    DateTime targetPayday = DateTime(today.year, today.month, paydayDay);
    if (targetPayday.isBefore(today)) {
      targetPayday = DateTime(today.year, today.month + 1, paydayDay);
    }
    int diffGaji = targetPayday.difference(today).inDays;
    if (diffGaji <= 3 && diffGaji >= 0) {
      String msg = diffGaji == 0 ? "Hari ini waktunya gajian!" : "Gajian tinggal $diffGaji hari lagi.";
      await _sendSystemNotification(title: "Reminder Penggajian 📅", message: msg, type: 'reminder_payroll');
    }

    // 2. Cek Jatuh Tempo Utang
    // Query debts... (Kode disederhanakan agar fokus ke Dashboard UI)

    await userRef.update({'last_daily_check': todayStr});
  }

  Future<void> _sendSystemNotification({required String title, required String message, required String type}) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'to_branch': _userBranchId,
      'title': title,
      'message': message,
      'type': type,
      'is_read': false,
      'date': FieldValue.serverTimestamp(),
    });
  }

  void _setupNotificationListener() {
    _notifSubscription?.cancel();
    Query query = FirebaseFirestore.instance.collection('notifications');

    if (_userRole == 'owner') {
      query = query.orderBy('date', descending: true).limit(10);
    } else {
      query = query.where('to_branch', whereIn: [_userBranchId, 'all']).orderBy('date', descending: true).limit(10);
    }

    _notifSubscription = query.snapshots().listen((snapshot) {
      // Logic update badge notifikasi
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUser) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.white,
      drawer: _buildDrawer(context),
      appBar: AppBar(
        title: const Text("Dashboard", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          // TOMBOL NOTIFIKASI
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('notifications')
                .where('to_branch', whereIn: [_userRole == 'owner' ? 'owner' : _userBranchId, 'all'])
                .where('is_read', isEqualTo: false)
                .snapshots(),
            builder: (context, snapshot) {
              int unreadCount = 0;
              if (snapshot.hasData) {
                unreadCount = snapshot.data!.docs.length;
              }

              return IconButton(
                onPressed: () {
                  String targetBranch = _userRole == 'owner' ? 'owner' : _userBranchId;
                  Navigator.push(context, MaterialPageRoute(
                      builder: (c) => NotificationScreen(branchId: targetBranch)
                  ));
                },
                icon: Stack(
                  children: [
                    const Icon(Icons.notifications_outlined, color: Colors.black, size: 28),
                    if (unreadCount > 0)
                      Positioned(
                        right: 0, top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                          child: Center(
                            child: Text(
                              unreadCount > 9 ? '9+' : '$unreadCount',
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      )
                  ],
                ),
              );
            },
          ),
          const SizedBox(width: 12),
        ],
      ),

      body: RefreshIndicator(
        onRefresh: _onRefresh,
        child: BlocBuilder<DashboardCubit, DashboardState>(
          builder: (context, state) {
            // 1. STATE LOADING
            if (state is DashboardLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            // 2. STATE ERROR (TAMPILAN BARU UNTUK FIX LOADING TERUS MENERUS)
            else if (state is DashboardError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 60, color: Colors.red),
                      const SizedBox(height: 16),
                      Text("Terjadi Kesalahan", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey[800])),
                      const SizedBox(height: 8),
                      Text(state.message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () => context.read<DashboardCubit>().startMonitoring(),
                        icon: const Icon(Icons.refresh),
                        label: const Text("Coba Lagi"),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                      )
                    ],
                  ),
                ),
              );
            }

            // 3. STATE SUKSES (LOADED)
            else if (state is DashboardLoaded) {
              // Jika dompet kosong sama sekali (Kasus reset database)
              if (state.wallets.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.warning_amber_rounded, size: 60, color: Colors.orange),
                      const SizedBox(height: 16),
                      const Text("Data Dompet Hilang / Kosong!", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.cloud_upload),
                        label: const Text("Generate Dompet Default"),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                        onPressed: () => _regenerateWallets(context),
                      )
                    ],
                  ),
                );
              }

              // Persiapan Data Tampilan
              final mainWallet = state.wallets.firstWhere((w) => w.id == 'main_cash', orElse: () => state.wallets.first);
              final double totalSmallCash = state.wallets.where((w) => w.id != 'main_cash').fold(0.0, (sum, w) => sum + w.balance);

              // Tentukan Tab yang Aktif
              if (_selectedTabIndex >= _visibleBranchIds.length) _selectedTabIndex = 0;
              String currentBranch = _visibleBranchIds[_selectedTabIndex];
              String currentWalletId = _visibleWalletIds[_selectedTabIndex];

              // Update Global Selection untuk Debt Screen
              _selectedBranchId = currentBranch;

              // Filter Transaksi (Berdasarkan Tab/Cabang yang dipilih)
              List<TransactionModel> filteredTransactions = state.recentTransactions.where((tx) {
                if (currentBranch == 'unknown') return false;
                // Tampilkan jika wallet ID cocok ATAU branch ID cocok
                bool isWalletMatch = tx.walletId == currentWalletId;
                bool isBranchMatch = (tx.relatedBranchId == currentBranch);
                return isWalletMatch || isBranchMatch;
              }).toList();

              List<DailySummary> filteredChartData = _recalculateChart(filteredTransactions);

              // Filter Utang (Hanya tampilkan utang cabang tsb)
              List<Map<String, dynamic>> filteredDebts = state.allDebts.where((d) {
                return d['branch_id'] == currentBranch;
              }).toList();
              double currentTabDebt = filteredDebts.fold(0, (sum, d) => sum + (d['amount'] ?? 0));

              // Ambil Wallet Cabang tsb
              WalletModel? currentBranchWallet;
              try {
                currentBranchWallet = state.wallets.firstWhere((w) => w.branchId == currentBranch);
              } catch (_) {} // Bisa null jika belum diaktifkan

              double currentTabBalance = currentBranchWallet?.balance ?? 0;

              // --- UI UTAMA DASHBOARD ---
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header (Beda antara Owner dan Admin)
                    if (_userRole == 'owner')
                      _buildOwnerHeader(state.totalAssets, mainWallet, totalSmallCash)
                    else if (_userRole == 'admin_branch')
                      _buildBranchAdminHeader(currentBranchWallet, currentBranch)
                    else
                      _buildErrorHeader(),

                    const SizedBox(height: 20),

                    // Tab Bar Custom (Hanya Owner)
                    if (_userRole == 'owner') ...[
                      _buildCustomTabBar(),
                      const SizedBox(height: 20),
                    ],

                    // Kartu Status: Sisa Kas Kecil & Total Utang
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_userRole == 'owner') ...[
                            Expanded(child: _buildGreenStatusCard(currentTabBalance, currentBranchWallet)),
                            const SizedBox(width: 12),
                          ],
                          Expanded(child: _buildDebtCard(currentTabDebt)),
                        ],
                      ),
                    ),

                    const SizedBox(height: 25),

                    // Grafik Batang
                    Text("Ringkasan ${_visibleTabs.isNotEmpty ? _visibleTabs[_selectedTabIndex] : '-'}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 15),
                    _buildChartContainer(filteredChartData),

                    const SizedBox(height: 25),

                    // List Transaksi Terkini
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Transaksi Terkini", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        TextButton(onPressed: (){
                          Navigator.push(context, MaterialPageRoute(builder: (c) => const TransactionHistoryScreen()));
                        }, child: Text("Lihat Semua", style: TextStyle(color: Colors.grey[400])))
                      ],
                    ),
                    const SizedBox(height: 10),

                    if (filteredTransactions.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(20),
                        width: double.infinity,
                        decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
                        child: const Center(child: Text("Belum ada transaksi")),
                      )
                    else
                      ...filteredTransactions.take(5).map((tx) => _buildTransactionItem(tx)),

                    const SizedBox(height: 80), // Spasi bawah agar tidak ketutup FAB
                  ],
                ),
              );
            }
            return const SizedBox();
          },
        ),
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const AddTransactionScreen())),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  // --- WIDGET HELPERS ---

  Widget _buildOwnerHeader(double totalAset, WalletModel mainWallet, double totalKasKecil) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF2962FF), Color(0xFF448AFF)]), borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.account_balance_wallet_outlined, color: Colors.white70, size: 18), const SizedBox(width: 8), Text("Total Aset Bersih (Global)", style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14))]),
        const SizedBox(height: 8), Text(_formatRupiah(totalAset), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
        const SizedBox(height: 24), Container(height: 1, color: Colors.white24), const SizedBox(height: 16),
        IntrinsicHeight(child: Row(children: [
          Expanded(child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => WalletDetailScreen(wallet: mainWallet))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text("Kas Pusat", style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)), Text(_formatRupiah(mainWallet.balance), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))]))),
          VerticalDivider(color: Colors.white.withOpacity(0.3), thickness: 1),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text("Total Kas Kecil", style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)), Text(_formatRupiah(totalKasKecil), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))])),
        ]))
      ]),
    );
  }

  Widget _buildBranchAdminHeader(WalletModel? wallet, String branchId) {
    double balance = wallet?.balance ?? 0;
    return GestureDetector(
      onTap: () { if (wallet != null) Navigator.push(context, MaterialPageRoute(builder: (c) => WalletDetailScreen(wallet: wallet))); },
      child: Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: AppColors.branchBst, gradient: LinearGradient(colors: branchId == 'bst_box' ? [const Color(0xFFD97706), const Color(0xFFF59E0B)] : branchId == 'm_alfa' ? [const Color(0xFFDC2626), const Color(0xFFEF4444)] : [const Color(0xFF7C3AED), const Color(0xFF8B5CF6)]), borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Icon(Icons.store, color: Colors.white70, size: 18), const SizedBox(width: 8), Text("Kas Operasional: ${branchId.toUpperCase().replaceAll('_', ' ')}", style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14))]), const SizedBox(height: 12), Text(_formatRupiah(balance), style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)), const SizedBox(height: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)), child: const Text("Admin Access", style: TextStyle(color: Colors.white, fontSize: 10)))])),
    );
  }

  Widget _buildErrorHeader() {
    return Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.circular(24)), child: const Text("Akses tidak valid.", style: TextStyle(color: Colors.white)));
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(child: ListView(padding: EdgeInsets.zero, children: [
      UserAccountsDrawerHeader(decoration: const BoxDecoration(color: AppColors.primary), accountName: Text(_userRole == 'owner' ? "Owner / Pusat" : "Admin Cabang"), accountEmail: const Text("bst-finance.com"), currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.person, color: AppColors.primary))),
      ListTile(leading: const Icon(Icons.dashboard), title: const Text('Dashboard'), onTap: () => Navigator.pop(context)),
      ListTile(
          leading: const Icon(Icons.people),
          title: const Text('Manajemen Pegawai'),
          onTap: () {
            Navigator.pop(context);
            Navigator.push(context, MaterialPageRoute(builder: (c) => EmployeeListScreen(branchId: _userBranchId)));
          }
      ),
      if (_userRole == 'owner')
        ListTile(
          leading: const Icon(Icons.manage_accounts),
          title: const Text('Manajemen User Akses'),
          onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (c) => const UserManagementScreen())); },
        ),
      ListTile(
        leading: const Icon(Icons.monetization_on_outlined),
        title: const Text('Utang Usaha'),
        onTap: () {
          Navigator.pop(context);
          Navigator.push(context, MaterialPageRoute(builder: (c) => DebtListScreen(branchId: _selectedBranchId)));
        },
      ),
      if (_userRole == 'owner') ListTile(leading: const Icon(Icons.verified_user), title: const Text('Persetujuan (Approval)'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (c) => const ApprovalScreen())); }),
      ListTile(leading: const Icon(Icons.settings), title: const Text('Pengaturan'), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (c) => const SettingsScreen())); })
    ]));
  }

  Widget _buildCustomTabBar() {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(_visibleTabs.length, (index) { final isSelected = _selectedTabIndex == index; return GestureDetector(onTap: () => setState(() => _selectedTabIndex = index), child: Column(children: [Text(_visibleTabs[index], style: TextStyle(color: isSelected ? AppColors.primary : Colors.grey[400], fontWeight: FontWeight.bold, fontSize: 14)), const SizedBox(height: 8), Container(height: 3, width: 40, decoration: BoxDecoration(color: isSelected ? AppColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(2)))])); }));
  }

  Widget _buildChartContainer(List<DailySummary> chartData) {
    if (chartData.isEmpty) return const SizedBox(height: 200, child: Center(child: Text("Menunggu data...")));
    return Container(
        height: 250, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade100)),
        child: BarChart(
            BarChartData(
                titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (val, meta) { int idx = val.toInt(); if(idx >= 0 && idx < chartData.length) return Padding(padding: const EdgeInsets.only(top: 8), child: Text(chartData[idx].dayLabel, style: const TextStyle(fontSize: 10, color: Colors.grey))); return const Text(""); }))
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: chartData.asMap().entries.map((e) => BarChartGroupData(x: e.key, barRods: [
                  BarChartRodData(toY: e.value.income, color: AppColors.success, width: 8, borderRadius: BorderRadius.circular(4)),
                  BarChartRodData(toY: e.value.expense, color: AppColors.error, width: 8, borderRadius: BorderRadius.circular(4))
                ])).toList()
            )
        )
    );
  }

  List<DailySummary> _recalculateChart(List<TransactionModel> txs) {
    List<DailySummary> summary = [];
    DateTime now = DateTime.now();

    for (int i = 6; i >= 0; i--) {
      DateTime targetDate = now.subtract(Duration(days: i));
      String dayLabel = DateFormat('E', 'id_ID').format(targetDate);
      var dailyTx = txs.where((tx) => tx.date.day == targetDate.day && tx.date.month == targetDate.month && tx.date.year == targetDate.year);

      double income = dailyTx.where((t) => t.type == 'income' && !t.category.toLowerCase().contains('top up') && !t.category.toLowerCase().contains('transfer') && !t.category.toLowerCase().contains('suntikan')).fold(0, (sum, t) => sum + t.amount);
      double expense = dailyTx.where((t) => t.type == 'expense' && !t.category.toLowerCase().contains('top up') && !t.category.toLowerCase().contains('transfer') && !t.category.toLowerCase().contains('suntikan')).fold(0, (sum, t) => sum + t.amount);

      summary.add(DailySummary(dayLabel, income, expense));
    }
    return summary;
  }

  Widget _buildTransactionItem(TransactionModel tx) {
    bool isIncome = tx.type == 'income';
    return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(12)), child: Row(children: [Icon(isIncome ? Icons.arrow_downward : Icons.arrow_upward, color: isIncome ? Colors.green : Colors.red), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(tx.description.isNotEmpty ? tx.description : tx.category, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)), Text(DateFormat('dd MMM').format(tx.date), style: const TextStyle(fontSize: 10, color: Colors.grey))])), Text((isIncome?"+ ":"- ") + _formatRupiah(tx.amount), style: TextStyle(fontWeight: FontWeight.bold, color: isIncome ? Colors.green : Colors.red))]));
  }

  Widget _buildGreenStatusCard(double amount, WalletModel? wallet) {
    return GestureDetector(
      onTap: () { if (wallet != null) Navigator.push(context, MaterialPageRoute(builder: (c) => WalletDetailScreen(wallet: wallet))); },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.greenSoft, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.greenText.withOpacity(0.1))),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(children: [Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Icon(Icons.account_balance_wallet, color: AppColors.greenText, size: 16)), const SizedBox(width: 8), const Expanded(child: Text("Sisa Kas Kecil", maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: AppColors.greenText, fontSize: 12, fontWeight: FontWeight.bold)))]),
                  const SizedBox(height: 12),
                  FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(wallet == null ? "Belum Aktif" : _formatRupiah(amount), style: const TextStyle(color: AppColors.greenText, fontWeight: FontWeight.bold, fontSize: 22))),
                  const SizedBox(height: 4),
                  Text(wallet == null ? "Tap tombol di kanan ->" : "Tap untuk mutasi >", style: const TextStyle(color: Colors.grey, fontSize: 10)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: Material(
                color: Colors.white, borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => wallet != null
                      ? _showTopUpDialog(wallet)
                      : _createMissingWallet(_visibleBranchIds[_selectedTabIndex]),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(border: Border.all(color: AppColors.greenText.withOpacity(0.2)), borderRadius: BorderRadius.circular(12)),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(wallet != null ? Icons.add_circle : Icons.build_circle, color: AppColors.greenText, size: 24),
                          const SizedBox(height: 2),
                          Text(wallet != null ? "Top Up" : "Aktifkan", style: const TextStyle(color: AppColors.greenText, fontWeight: FontWeight.bold, fontSize: 9))
                        ]
                    ),
                  ),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildDebtCard(double totalDebt) {
    return GestureDetector(
      onTap: () => _showDebtListModal(context),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.redSoft, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.error.withOpacity(0.1))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: const Icon(Icons.receipt_long, color: AppColors.error, size: 16)), const SizedBox(width: 10), Text("Total Utang", style: TextStyle(color: AppColors.error.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.bold))]),
          const SizedBox(height: 12),
          Text(_formatRupiah(totalDebt), style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 22)),
          const SizedBox(height: 4),
          const Text("Tap untuk detail >", style: TextStyle(color: Colors.grey, fontSize: 11)),
        ]),
      ),
    );
  }

  void _showTopUpDialog(WalletModel targetWallet) {
    final nominalCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("Top Up: ${targetWallet.name}"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [const Text("Dana diambil dari KAS PUSAT."), const SizedBox(height: 16), TextField(controller: nominalCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Nominal (Rp)", border: OutlineInputBorder(), prefixText: "Rp "))]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Batal")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () async {
              if (nominalCtrl.text.isEmpty) return;
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Memproses Top Up...")));
              try {
                double amount = double.parse(nominalCtrl.text.replaceAll('.', ''));
                String walletPusat = 'main_cash';
                String walletCabang = targetWallet.id;

                await FirebaseFirestore.instance.runTransaction((tx) async {
                  final txPusatRef = FirebaseFirestore.instance.collection('transactions').doc();
                  tx.set(txPusatRef, { 'amount': amount, 'type': 'expense', 'category': 'Top Up Cabang', 'description': 'Top Up ke ${targetWallet.name}', 'wallet_id': walletPusat, 'related_branch_id': targetWallet.branchId, 'date': FieldValue.serverTimestamp(), 'user_id': _userRole == 'owner' ? 'owner' : _userBranchId, 'deleted_at': null });

                  final txCabangRef = FirebaseFirestore.instance.collection('transactions').doc();
                  tx.set(txCabangRef, { 'amount': amount, 'type': 'income', 'category': 'Top Up Masuk', 'description': 'Terima dari Pusat', 'wallet_id': walletCabang, 'related_branch_id': targetWallet.branchId, 'date': FieldValue.serverTimestamp(), 'user_id': _userRole == 'owner' ? 'owner' : _userBranchId, 'deleted_at': null });

                  final pusatSnap = await tx.get(FirebaseFirestore.instance.collection('wallets').doc(walletPusat));
                  final cabangSnap = await tx.get(FirebaseFirestore.instance.collection('wallets').doc(walletCabang));
                  if(pusatSnap.exists && cabangSnap.exists) {
                    double saldoPusat = (pusatSnap.get('balance') ?? 0).toDouble();
                    double saldoCabang = (cabangSnap.get('balance') ?? 0).toDouble();
                    tx.update(pusatSnap.reference, {'balance': saldoPusat - amount});
                    tx.update(cabangSnap.reference, {'balance': saldoCabang + amount});
                  }
                });
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Top Up Berhasil!"), backgroundColor: Colors.green));
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e"), backgroundColor: Colors.red));
              }
            },
            child: const Text("Kirim Dana"),
          )
        ],
      ),
    );
  }

  void _showDebtListModal(BuildContext context) {
    Navigator.push(context, MaterialPageRoute(
        builder: (c) => DebtListScreen(branchId: _selectedBranchId)
    ));
  }

  String _formatRupiah(double amount) => NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(amount);

  void _regenerateWallets(BuildContext context) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Sedang membuat ulang data dompet...")));
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();

    batch.set(firestore.collection('wallets').doc('main_cash'), {'name': 'Kas Pusat', 'branch_id': 'pusat', 'balance': 0, 'is_main': true});
    batch.set(firestore.collection('wallets').doc('petty_bst'), {'name': 'Kas Kecil Box', 'branch_id': 'bst_box', 'balance': 0, 'is_main': false});
    batch.set(firestore.collection('wallets').doc('petty_alfa'), {'name': 'Kas Kecil Alfa', 'branch_id': 'm_alfa', 'balance': 0, 'is_main': false});
    batch.set(firestore.collection('wallets').doc('petty_saufa'), {'name': 'Kas Kecil Saufa', 'branch_id': 'saufa', 'balance': 0, 'is_main': false});

    try {
      await batch.commit();
      if (mounted) {
        context.read<DashboardCubit>().startMonitoring();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Berhasil! Data dompet telah pulih.")));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e")));
    }
  }

  Future<void> _createMissingWallet(String branchId) async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Mengaktifkan dompet...")));
    String walletId = '';
    String walletName = '';

    if (branchId == 'm_alfa') {
      walletId = 'petty_alfa';
      walletName = 'Kas Kecil Alfa';
    } else if (branchId == 'saufa') {
      walletId = 'petty_saufa';
      walletName = 'Kas Kecil Saufa';
    } else if (branchId == 'bst_box') {
      walletId = 'petty_bst';
      walletName = 'Kas Kecil Box';
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Cabang tidak dikenali")));
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('wallets').doc(walletId).set({
        'name': walletName,
        'branch_id': branchId,
        'balance': 0,
        'is_main': false,
      });

      if (mounted) {
        context.read<DashboardCubit>().startMonitoring();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Dompet Berhasil Diaktifkan!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Gagal: $e")));
    }
  }
}