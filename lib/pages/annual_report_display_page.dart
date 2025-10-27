import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import '../models/advanced_analytics_data.dart';
import '../widgets/annual_report/animated_components.dart';
import '../config/annual_report_texts.dart';
import '../services/database_service.dart';
import '../services/analytics_background_service.dart';
import '../services/annual_report_cache_service.dart';

/// 年度报告展示页面，支持翻页滑动查看各个分析模块
class AnnualReportDisplayPage extends StatefulWidget {
  final DatabaseService databaseService;
  final int? year;

  const AnnualReportDisplayPage({
    super.key,
    required this.databaseService,
    this.year,
  });

  @override
  State<AnnualReportDisplayPage> createState() => _AnnualReportDisplayPageState();
}

class _AnnualReportDisplayPageState extends State<AnnualReportDisplayPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  List<Widget>? _pages;
  final GlobalKey _pageViewKey = GlobalKey();
  
  // 导出相关
  bool _isExporting = false;
  String _nameHideMode = 'none'; // none, full, firstChar
  
  // 报告生成相关
  AnalyticsBackgroundService? _backgroundService;
  Map<String, dynamic>? _reportData;
  bool _isGenerating = false;
  final Map<String, String> _taskStatus = {};
  int _totalProgress = 0;
  int? _dbModifiedTime;

  @override
  void initState() {
    super.initState();
    _initializeReport();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
  
  Future<void> _initializeReport() async {
    final dbPath = widget.databaseService.dbPath;
    
    if (dbPath != null) {
      _backgroundService = AnalyticsBackgroundService(dbPath);
    } else {
    }
    
    // 获取数据库修改时间
    if (dbPath != null) {
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        final stat = await dbFile.stat();
        _dbModifiedTime = stat.modified.millisecondsSinceEpoch;
      } else {
      }
    }
    
    // 检查缓存
    final hasCache = await AnnualReportCacheService.hasReport(widget.year);
    
    if (hasCache && _dbModifiedTime != null) {
      final cachedData = await AnnualReportCacheService.loadReport(widget.year);
      if (cachedData != null) {
        // 检查数据库是否有更新
        final cachedDbTime = cachedData['dbModifiedTime'] as int?;
        final dbChanged = cachedDbTime == null || cachedDbTime < _dbModifiedTime!;
        
        if (dbChanged) {
          // 数据库已更新，询问用户
          if (!mounted) return;
          final shouldRegenerate = await _showDatabaseChangedDialog();
          
          if (shouldRegenerate == true) {
            // 重新生成
            await _startGenerateReport();
          } else {
            // 使用旧数据
            if (!mounted) return;
            setState(() {
              _reportData = cachedData;
              _pages = null;
            });
            _buildPages();
          }
        } else {
          // 使用缓存
          if (!mounted) return;
          setState(() {
            _reportData = cachedData;
            _pages = null;
          });
          _buildPages();
        }
        return;
      }
    }
    
    // 没有缓存，需要生成
    // 不自动生成，等待用户点击
  }
  
  Future<bool?> _showDatabaseChangedDialog() async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.orange),
            SizedBox(width: 8),
            Text('数据库已更新'),
          ],
        ),
        content: const Text(
          '检测到数据库已发生变化，是否重新生成年度报告？\n\n'
          '• 重新生成：获取最新的数据（需要一些时间）\n'
          '• 使用旧数据：快速加载，但可能不包含最新消息',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('使用旧数据'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重新生成'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _startGenerateReport() async {
    
    if (_backgroundService == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('服务未初始化，请检查数据库配置')),
        );
      }
      return;
    }
    
    setState(() {
      _isGenerating = true;
      _taskStatus.clear();
      _totalProgress = 0;
    });
    
    try {
      final data = await _backgroundService!.generateFullAnnualReport(
        widget.year,
        (taskName, status, progress) {
          if (mounted) {
            setState(() {
              _taskStatus[taskName] = status;
              _totalProgress = progress;
            });
          }
        },
      );
      
      // 保存数据库修改时间
      data['dbModifiedTime'] = _dbModifiedTime;
      
      // 保存到缓存
      await AnnualReportCacheService.saveReport(widget.year, data);
      
      if (mounted) {
        setState(() {
          _reportData = data;
          _isGenerating = false;
          _pages = null;
        });
        _buildPages();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成报告失败: $e')),
        );
      }
    }
  }

  void _buildPages() {
    _pages = [
      _buildCoverPage(),
      _buildIntroPage(),
      _buildComprehensiveFriendshipPage(),
      _buildMutualFriendsPage(),
      _buildSocialInitiativePage(),
      _buildPeakDayPage(),
      _buildCheckInPage(),
      _buildActivityPatternPage(),
      _buildMidnightKingPage(),
      _buildResponseSpeedPage(),
      _buildEndingPage(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // 如果没有报告数据且不在生成中，显示初始界面
    if (_reportData == null && !_isGenerating) {
      return _buildInitialScreen();
    }
    
    // 如果正在生成，显示进度界面
    if (_isGenerating) {
      return _buildGeneratingScreen();
    }
    
    // 有报告数据，显示报告
    return Scaffold(
      backgroundColor: Colors.white,
      body: RawKeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        autofocus: true,
        onKey: (event) {
          if (event is RawKeyDownEvent) {
            if (event.logicalKey.keyLabel == 'Arrow Right' || 
                event.logicalKey.keyLabel == 'Arrow Down' ||
                event.logicalKey.keyLabel == 'Page Down') {
              // 下一页
              if (_currentPage < _pages!.length - 1) {
                _pageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
            } else if (event.logicalKey.keyLabel == 'Arrow Left' || 
                       event.logicalKey.keyLabel == 'Arrow Up' ||
                       event.logicalKey.keyLabel == 'Page Up') {
              // 上一页
              if (_currentPage > 0) {
                _pageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
            }
          }
        },
        child: Stack(
          children: [
            // 主内容区域，支持鼠标滚轮翻页
            RepaintBoundary(
              key: _pageViewKey,
              child: Listener(
                onPointerSignal: (pointerSignal) {
                if (pointerSignal is PointerScrollEvent) {
                  if (pointerSignal.scrollDelta.dy > 0) {
                    // 向下滚动 - 下一页
                    if (_currentPage < _pages!.length - 1) {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  } else if (pointerSignal.scrollDelta.dy < 0) {
                    // 向上滚动 - 上一页
                    if (_currentPage > 0) {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                      );
                    }
                  }
                }
              },
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                  },
                  children: _pages!,
                ),
              ),
            ),
          
          // 页面指示器
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages!.length, (index) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? const Color(0xFF07C160)
                        : Colors.grey[300],
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
          ),
          
          // 右上角按钮组
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 分享按钮
                IconButton(
                  icon: const Icon(Icons.share, color: Colors.black87, size: 24),
                  onPressed: _isExporting ? null : _showExportDialog,
                  tooltip: '分享',
                ),
                const SizedBox(width: 8),
                // 关闭按钮
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.black87, size: 28),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '关闭',
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
  
  Widget _buildInitialScreen() {
    final yearText = widget.year != null ? '${widget.year}年' : '历史以来';
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('$yearText年度报告'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.analytics_outlined,
              size: 80,
              color: Color(0xFF07C160),
            ),
            const SizedBox(height: 24),
            Text(
              '$yearText年度报告',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '点击下方按钮开始分析',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 48),
            ElevatedButton.icon(
              onPressed: _startGenerateReport,
              icon: const Icon(Icons.play_arrow),
              label: const Text('开始生成报告'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF07C160),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildGeneratingScreen() {
    final yearText = widget.year != null ? '${widget.year}年' : '历史以来';
    
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('生成$yearText年度报告'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: CircularProgressIndicator(
                        value: _totalProgress / 100,
                        strokeWidth: 8,
                        backgroundColor: Colors.grey[200],
                        valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF07C160)),
                      ),
                    ),
                    Text(
                      '$_totalProgress%',
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF07C160),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 48),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _taskStatus.entries.map((entry) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(
                            entry.value == '完成' 
                                ? Icons.check_circle 
                                : Icons.radio_button_unchecked,
                            size: 16,
                            color: entry.value == '完成' 
                                ? const Color(0xFF07C160) 
                                : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${entry.key}: ${entry.value}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建年度报告封面页
  Widget _buildCoverPage() {
    final yearText = widget.year != null ? '${widget.year}年' : '历史以来';
    
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FadeInText(
                text: AnnualReportTexts.coverTitle,
                style: TextStyle(
                  fontSize: 28,
                  color: Colors.grey[500],
                  letterSpacing: 8,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 48),
              SlideInCard(
                delay: const Duration(milliseconds: 400),
                child: Text(
                  yearText,
                  style: const TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF07C160),
                    letterSpacing: 6,
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FadeInText(
                text: AnnualReportTexts.coverSubtitle,
                delay: const Duration(milliseconds: 700),
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w500,
                  color: Colors.black87,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 64),
              Container(
                width: 80,
                height: 1,
                color: Colors.grey[300],
              ),
              const SizedBox(height: 32),
                  FadeInText(
                text: AnnualReportTexts.coverPoem1,
                delay: const Duration(milliseconds: 1000),
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[600],
                  letterSpacing: 2,
                  height: 1.8,
                ),
              ),
              FadeInText(
                text: AnnualReportTexts.coverPoem2,
                delay: const Duration(milliseconds: 1200),
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[600],
                  letterSpacing: 2,
                  height: 1.8,
                ),
              ),
              const SizedBox(height: 100),
              FadeInText(
                text: AnnualReportTexts.coverHint,
                delay: const Duration(milliseconds: 1500),
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[400],
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              FadeInText(
                text: AnnualReportTexts.coverArrows,
                delay: const Duration(milliseconds: 1700),
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.grey[350],
                  fontWeight: FontWeight.w300,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 开场页 - 横屏居中流动设计
  Widget _buildIntroPage() {
    final totalMessages = _getTotalMessages();
    final totalFriends = _getTotalFriends();
    final yearText = widget.year != null ? '${widget.year}年' : '这段时光';
    
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final width = constraints.maxWidth;
            final textSize = height * 0.04;
            final numberSize = height * 0.12;
            final smallSize = height * 0.028;
            
            return Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: width * 0.15, vertical: height * 0.1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FadeInText(
                        text: '在$yearText里',
                        style: TextStyle(
                          fontSize: textSize,
                          color: Colors.grey[600],
                          letterSpacing: 2,
                        ),
                      ),
                      SizedBox(height: height * 0.05),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          FadeInText(
                            text: '你与 ',
                            delay: const Duration(milliseconds: 300),
                            style: TextStyle(
                              fontSize: textSize,
                              color: Colors.black87,
                            ),
                          ),
                          SlideInCard(
                            delay: const Duration(milliseconds: 500),
                            child: AnimatedNumberDisplay(
                              value: totalFriends.toDouble(),
                              suffix: '',
                              style: TextStyle(
                                fontSize: numberSize,
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF07C160),
                                height: 1.0,
                              ),
                            ),
                          ),
                          FadeInText(
                            text: ' 位好友',
                            delay: const Duration(milliseconds: 700),
                            style: TextStyle(
                              fontSize: textSize,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: height * 0.04),
                      FadeInText(
                        text: AnnualReportTexts.introExchanged,
                        delay: const Duration(milliseconds: 900),
                        style: TextStyle(
                          fontSize: textSize,
                          color: Colors.grey[600],
                        ),
                      ),
                      SizedBox(height: height * 0.04),
                      SlideInCard(
                        delay: const Duration(milliseconds: 1100),
                        child: AnimatedNumberDisplay(
                          value: totalMessages.toDouble(),
                          suffix: AnnualReportTexts.introMessagesUnit,
                          style: TextStyle(
                            fontSize: numberSize * 0.8,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF07C160),
                            height: 1.0,
                          ),
                        ),
                      ),
                      SizedBox(height: height * 0.08),
                      FadeInText(
                        text: _getOpeningComment(totalMessages),
                        delay: const Duration(milliseconds: 1400),
                        style: TextStyle(
                          fontSize: smallSize,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                          height: 2.0,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // 获取总消息数（从报告的总统计字段读取）
  int _getTotalMessages() {
    return (_reportData!['totalMessages'] as int?) ?? 0;
  }

  // 获取好友总数（从报告的总统计字段读取）
  int _getTotalFriends() {
    return (_reportData!['totalFriends'] as int?) ?? 0;
  }

  // 根据消息数生成开场评语
  String _getOpeningComment(int messages) {
    return AnnualReportTexts.getOpeningComment(messages);
  }

  // 综合好友页 - 合并年度挚友、倾诉对象、最佳听众
  Widget _buildComprehensiveFriendshipPage() {
    // 获取数据
    final List<dynamic> coreFriendsJson = _reportData!['coreFriends'] ?? [];
    final coreFriends = coreFriendsJson.map((e) => FriendshipRanking.fromJson(e)).toList();
    
    final List<dynamic> confidantJson = _reportData!['confidant'] ?? [];
    final confidants = confidantJson.map((e) => FriendshipRanking.fromJson(e)).toList();
    
    final List<dynamic> listenersJson = _reportData!['listeners'] ?? [];
    final listeners = listenersJson.map((e) => FriendshipRanking.fromJson(e)).toList();
    
    if (coreFriends.isEmpty) {
      return Container(
        color: Colors.white,
        child: const Center(
          child: Text('暂无数据', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final topFriend = coreFriends[0];
    final topConfidant = confidants.isNotEmpty ? confidants[0] : null;
    final topListener = listeners.isNotEmpty ? listeners[0] : null;
    
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final width = constraints.maxWidth;
            // 统一字体系统：只用两种尺寸
            final emphasisSize = height * 0.045;  // 强调字体：标题、名字、数字
            final normalSize = height * 0.024;    // 正常字体：所有其他文本
            
            return Center(
                child: Padding(
                padding: EdgeInsets.symmetric(horizontal: width * 0.1, vertical: height * 0.06),
                  child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                    children: [
                    // 标题
                      FadeInText(
                      text: AnnualReportTexts.friendshipTitle,
                        style: TextStyle(
                        fontSize: emphasisSize,
                        fontWeight: FontWeight.w600,
                          color: const Color(0xFF07C160),
                        letterSpacing: 2,
                        ),
                      ),
                    SizedBox(height: height * 0.03),
                    
                    // 主要内容
                      FadeInText(
                      text: AnnualReportTexts.friendshipIntro,
                        delay: const Duration(milliseconds: 200),
                        style: TextStyle(
                        fontSize: normalSize,
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: height * 0.025),
                    
                    // 挚友名字
                    SlideInCard(
                                delay: const Duration(milliseconds: 400),
                      child: Container(
                        constraints: BoxConstraints(maxWidth: width * 0.6),
            child: _buildNameWithBlur(
                          topFriend.displayName,
              TextStyle(
                            fontSize: emphasisSize,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF07C160),
              height: 1.3,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
        ),
                    ),
                    SizedBox(height: height * 0.02),
                    
                    FadeInText(
                      text: AnnualReportTexts.friendshipMostChats,
                      delay: const Duration(milliseconds: 600),
          style: TextStyle(
                        fontSize: normalSize,
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: height * 0.015),
                    
                    // 总消息数
                    SlideInCard(
                      delay: const Duration(milliseconds: 800),
                      child: AnimatedNumberDisplay(
                        value: topFriend.count.toDouble(),
                        suffix: AnnualReportTexts.friendshipMessagesCount,
          style: TextStyle(
                          fontSize: emphasisSize,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF07C160),
                        ),
                      ),
                    ),
                    
                    SizedBox(height: height * 0.04),
                    
                    // 分隔线
                    Container(
                      width: width * 0.2,
                      height: 1,
                      color: Colors.grey[300],
                    ),
                    
                    SizedBox(height: height * 0.035),
                    
                    // 倾诉和听众信息
                    if (topConfidant != null && topListener != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // 你最爱给谁发
                          Expanded(
                  child: Column(
                              mainAxisSize: MainAxisSize.min,
                    children: [
                      FadeInText(
                                  text: AnnualReportTexts.friendshipYouSendTo,
                                  delay: const Duration(milliseconds: 1000),
                        style: TextStyle(
                                    fontSize: normalSize * 0.9,
                                    color: Colors.grey[500],
                                  ),
                                ),
                                SizedBox(height: height * 0.015),
                       SlideInCard(
                                  delay: const Duration(milliseconds: 1200),
                                  child: _buildNameWithBlur(
                                    topConfidant.displayName,
                        TextStyle(
                                    fontSize: normalSize,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                          ),
                                ),
                                SizedBox(height: height * 0.012),
                      FadeInText(
                                  text: '${topConfidant.count}${AnnualReportTexts.friendshipMessagesCount}',
                                  delay: const Duration(milliseconds: 1400),
                        style: TextStyle(
                                    fontSize: emphasisSize * 0.8,
                                    color: const Color(0xFF07C160),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (topConfidant.details != null && 
                                    topConfidant.details!['receivedCount'] != null) ...[
                                  SizedBox(height: height * 0.01),
                      FadeInText(
                                    text: '${AnnualReportTexts.friendshipTheyReply}${topConfidant.details!['receivedCount']}${AnnualReportTexts.friendshipMessagesCount}',
                        delay: const Duration(milliseconds: 1500),
                        style: TextStyle(
                                      fontSize: normalSize * 0.85,
                          color: Colors.grey[500],
                        ),
                      ),
                                ],
                    ],
                  ),
                ),
                          
                          Container(
                            width: 1,
                            height: height * 0.12,
                            color: Colors.grey[300],
                          ),
                          
                          // 谁最爱给你发
                          Expanded(
                  child: Column(
                              mainAxisSize: MainAxisSize.min,
                    children: [
                      FadeInText(
                                  text: AnnualReportTexts.friendshipWhoSendsYou,
                                  delay: const Duration(milliseconds: 1000),
                        style: TextStyle(
                                    fontSize: normalSize * 0.9,
                                    color: Colors.grey[500],
                                  ),
                                ),
                                SizedBox(height: height * 0.015),
                                SlideInCard(
                                  delay: const Duration(milliseconds: 1200),
                                  child: _buildNameWithBlur(
                                    topListener.displayName,
                            TextStyle(
                                    fontSize: normalSize,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.black87,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                          ),
                                ),
                                SizedBox(height: height * 0.012),
                      FadeInText(
                                  text: '${topListener.count}${AnnualReportTexts.friendshipMessagesCount}',
                                  delay: const Duration(milliseconds: 1400),
                        style: TextStyle(
                                    fontSize: emphasisSize * 0.8,
                                    color: const Color(0xFF07C160),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (topListener.details != null && 
                                    topListener.details!['sentCount'] != null) ...[
                                  SizedBox(height: height * 0.01),
                      FadeInText(
                                    text: '${AnnualReportTexts.friendshipYouReply}${topListener.details!['sentCount']}${AnnualReportTexts.friendshipMessagesCount}',
                                    delay: const Duration(milliseconds: 1500),
                        style: TextStyle(
                                      fontSize: normalSize * 0.85,
                          color: Colors.grey[500],
                        ),
                      ),
                                ],
                              ],
                          ),
                        ),
                      ],
                      ),
                      
                      SizedBox(height: height * 0.035),
                      
                      // 底部寄语
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: width * 0.08),
                        child: FadeInText(
                          text: AnnualReportTexts.friendshipClosing,
                          delay: const Duration(milliseconds: 1800),
                        style: TextStyle(
                            fontSize: normalSize * 0.9,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                            height: 1.8,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                    ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // 双向奔赴页 - 横屏水平对称设计
  Widget _buildMutualFriendsPage() {
    final List<dynamic> friendsJson = _reportData!['mutualFriends'] ?? [];
    final friends = friendsJson.map((e) => FriendshipRanking.fromJson(e)).toList();
    
    if (friends.isEmpty) {
      return Container(
        color: Colors.white,
        child: const Center(
          child: Text('暂无数据', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final friend1 = friends[0];
    final ratio = friend1.details?['ratio'] as String? ?? '1.0';
    final sent = friend1.details?['sentCount'] as int? ?? 0;
    final received = friend1.details?['receivedCount'] as int? ?? 0;
    
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final width = constraints.maxWidth;
            final titleSize = height * 0.05;
            final nameSize = height * 0.065;
            final numberSize = height * 0.1;
            final textSize = height * 0.03;
            final smallSize = height * 0.026;
            
            return Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: width * 0.08, vertical: height * 0.1),
                  child: Column(
                    children: [
                      FadeInText(
                        text: AnnualReportTexts.mutualTitle,
                        style: TextStyle(
                          fontSize: titleSize,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF07C160),
                          letterSpacing: 3,
                        ),
                      ),
                      SizedBox(height: height * 0.015),
                      FadeInText(
                        text: AnnualReportTexts.mutualSubtitle,
                        delay: const Duration(milliseconds: 200),
                        style: TextStyle(
                          fontSize: smallSize,
                          color: Colors.grey[500],
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: height * 0.06),
                      SlideInCard(
                        delay: const Duration(milliseconds: 400),
                        child: Container(
                          constraints: BoxConstraints(maxWidth: width * 0.5),
                          child: _buildNameWithBlur(
                            friend1.displayName,
                            TextStyle(
                              fontSize: nameSize,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                              height: 1.2,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 2,
                          ),
                        ),
                      ),
                      SizedBox(height: height * 0.08),
                      
                      // 水平排列数据
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // 你发
                          Column(
                            children: [
                              FadeInText(
                                text: AnnualReportTexts.mutualYouSent,
                                delay: const Duration(milliseconds: 600),
                                style: TextStyle(
                                  fontSize: textSize,
                                  color: Colors.grey[500],
                                ),
                              ),
                              SizedBox(height: height * 0.02),
                              FadeInText(
                                text: '$sent',
                                delay: const Duration(milliseconds: 800),
                                style: TextStyle(
                                  fontSize: numberSize,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF07C160),
                                  height: 1.0,
                                ),
                              ),
                              SizedBox(height: 4),
                              FadeInText(
                                text: AnnualReportTexts.mutualMessagesUnit,
                                delay: const Duration(milliseconds: 900),
                                style: TextStyle(
                                  fontSize: smallSize,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                          
                          SizedBox(width: width * 0.15),
                          
                          // 箭头
                          FadeInText(
                            text: '⇄',
                            delay: const Duration(milliseconds: 1000),
                            style: TextStyle(
                              fontSize: numberSize * 0.4,
                              color: Colors.grey[300],
                            ),
                          ),
                          
                          SizedBox(width: width * 0.15),
                          
                          // TA回
                          Column(
                            children: [
                              FadeInText(
                                text: AnnualReportTexts.mutualTheySent,
                                delay: const Duration(milliseconds: 600),
                                style: TextStyle(
                                  fontSize: textSize,
                                  color: Colors.grey[500],
                                ),
                              ),
                              SizedBox(height: height * 0.02),
                              FadeInText(
                                text: '$received',
                                delay: const Duration(milliseconds: 800),
                                style: TextStyle(
                                  fontSize: numberSize,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF07C160),
                                  height: 1.0,
                                ),
                              ),
                              SizedBox(height: 4),
                              FadeInText(
                                text: AnnualReportTexts.mutualMessagesUnit,
                                delay: const Duration(milliseconds: 900),
                                style: TextStyle(
                                  fontSize: smallSize,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      
                      SizedBox(height: height * 0.08),
                      
                      FadeInText(
                        text: '${AnnualReportTexts.mutualRatioPrefix}$ratio',
                        delay: const Duration(milliseconds: 1100),
                        style: TextStyle(
                          fontSize: textSize,
                          color: const Color(0xFF07C160),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: height * 0.04),
                      FadeInText(
                        text: AnnualReportTexts.mutualClosing,
                        delay: const Duration(milliseconds: 1300),
                        style: TextStyle(
                          fontSize: smallSize * 0.9,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                          height: 2.0,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // 主动社交指数页
  Widget _buildSocialInitiativePage() {
    final socialData = SocialStyleData.fromJson(_reportData!['socialInitiative']);
    
    if (socialData.initiativeRanking.isEmpty) {
      return Container(
        color: Colors.white,
        child: const Center(
          child: Text('暂无数据', style: TextStyle(color: Colors.grey)),
        ),
      );
    }

    final friend1 = socialData.initiativeRanking.first;
    final rate = friend1.percentage;
    
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              final width = constraints.maxWidth;
              final titleSize = height > 700 ? 32.0 : 26.0;
              final nameSize = height > 700 ? 38.0 : 32.0;
              final descSize = height > 700 ? 18.0 : 16.0;
              
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: width * 0.1, 
                  vertical: height * 0.05,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    FadeInText(
                      text: AnnualReportTexts.socialTitle,
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF07C160),
                        letterSpacing: 2,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: height * 0.06),
                    
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: width * 0.05),
                      child: SlideInCard(
                        delay: const Duration(milliseconds: 300),
                        child: Column(
                          children: [
                            Text(
                              '在与',
                              style: TextStyle(
                                fontSize: descSize - 1,
                                color: Colors.grey[700],
                                height: 1.9,
                                letterSpacing: 0.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            _buildNameWithBlur(
                              friend1.displayName,
                              TextStyle(
                                fontSize: descSize - 1,
                                color: Colors.grey[700],
                                fontWeight: FontWeight.w600,
                                height: 1.9,
                                letterSpacing: 0.5,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                            ),
                            Text(
                              '的聊天中，你发起了 ${(rate * 100).toStringAsFixed(1)}% 的对话',
                              style: TextStyle(
                                fontSize: descSize - 1,
                                color: Colors.grey[700],
                                height: 1.9,
                                letterSpacing: 0.5,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: height * 0.06),
                    SlideInCard(
                      delay: const Duration(milliseconds: 600),
                      child: Text(
                        '${(rate * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: nameSize,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF07C160),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(height: height * 0.02),
                    FadeInText(
                      text: AnnualReportTexts.socialInitiatedUnit,
                      delay: const Duration(milliseconds: 800),
                      style: TextStyle(
                        fontSize: descSize - 2,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
            ),
    );
  }

  // 聊天巅峰日页
  Widget _buildPeakDayPage() {
    final peakDay = ChatPeakDay.fromJson(_reportData!['peakDay']);
    
    return Container(
      color: Colors.white,
      child: SafeArea(
      child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              final width = constraints.maxWidth;
              final titleSize = height > 700 ? 32.0 : 26.0;
              final dateSize = height > 700 ? 34.0 : 28.0;
              final numberSize = height > 700 ? 44.0 : 36.0;
              final descSize = height > 700 ? 18.0 : 16.0;
              final commentSize = height > 700 ? 16.0 : 14.0;
              
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: width * 0.08, 
                  vertical: height * 0.05,
                ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FadeInText(
                      text: AnnualReportTexts.peakDayTitle,
                      style: TextStyle(
                        fontSize: titleSize,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF07C160),
                        letterSpacing: 2,
                      ),
                    ),
                    SizedBox(height: height * 0.06),
                    SlideInCard(
              delay: const Duration(milliseconds: 300),
                      child: Text(
                        peakDay.formattedDate,
                        style: TextStyle(
                          fontSize: dateSize,
                fontWeight: FontWeight.bold,
                          color: const Color(0xFF07C160),
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    SizedBox(height: height * 0.04),
                    FadeInText(
                      text: AnnualReportTexts.peakDayThisDay,
                      delay: const Duration(milliseconds: 500),
                      style: TextStyle(
                        fontSize: descSize,
                        color: Colors.grey[600],
                      ),
                    ),
                    SizedBox(height: height * 0.025),
            AnimatedNumberDisplay(
              value: peakDay.messageCount.toDouble(),
              suffix: AnnualReportTexts.peakDayMessagesUnit,
                      style: TextStyle(
                        fontSize: numberSize,
                        fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            if (peakDay.topFriendDisplayName != null) ...[
                      SizedBox(height: height * 0.05),
              SlideInCard(
                        delay: const Duration(milliseconds: 700),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              AnnualReportTexts.peakDayWithFriend,
                              style: TextStyle(
                                fontSize: descSize,
                                color: Colors.black87,
                              ),
                            ),
                            _buildNameWithBlur(
                              peakDay.topFriendDisplayName!,
                              TextStyle(
                                fontSize: descSize,
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: height * 0.015),
              FadeInText(
                        text: '${AnnualReportTexts.peakDayChatted}${peakDay.topFriendMessageCount}${AnnualReportTexts.peakDayChattedUnit}',
                        delay: const Duration(milliseconds: 900),
                style: TextStyle(
                          fontSize: descSize + 2,
                          color: const Color(0xFF07C160),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: height * 0.03),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: width * 0.05),
                        child: FadeInText(
                          text: AnnualReportTexts.getPeakDayComment(peakDay.messageCount),
                          delay: const Duration(milliseconds: 1100),
                          style: TextStyle(
                            fontSize: commentSize,
                            color: Colors.grey[600],
                            fontStyle: FontStyle.italic,
                          ),
                ),
              ),
            ],
          ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }


  // 连续打卡页
  Widget _buildCheckInPage() {
    final checkIn = _reportData!['checkIn'] as Map<String, dynamic>;
    final days = checkIn['days'] ?? 0;
    final displayName = checkIn['displayName'] ?? '未知';
    final startDateStr = checkIn['startDate'] as String?;
    final endDateStr = checkIn['endDate'] as String?;
    
    // 格式化日期，只保留年月日
    String? startDate;
    String? endDate;
    if (startDateStr != null) {
      startDate = startDateStr.split('T').first;
    }
    if (endDateStr != null) {
      endDate = endDateStr.split('T').first;
    }
    
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final width = constraints.maxWidth;
            final titleSize = height > 700 ? 36.0 : 32.0;
            final numberSize = height > 700 ? 78.0 : 66.0;
            final descSize = height > 700 ? 22.0 : 20.0;
            final smallSize = height > 700 ? 18.0 : 16.0;
            
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.1, 
                vertical: height * 0.08,
              ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
          children: [
                  FadeInText(
                    text: AnnualReportTexts.checkInTitle,
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF07C160),
                      letterSpacing: 1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: height * 0.02),
                  FadeInText(
                    text: AnnualReportTexts.checkInSubtitle,
                    delay: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: titleSize - 12,
                      color: Colors.grey[500],
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: height * 0.04),
                  SlideInCard(
                    delay: const Duration(milliseconds: 300),
                    child: _buildNameWithBlur(
                      displayName,
                      TextStyle(
                        fontSize: descSize + 4,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  SizedBox(height: height * 0.08),
                  SlideInCard(
                    delay: const Duration(milliseconds: 600),
                    child: AnimatedNumberDisplay(
              value: days.toDouble(),
              suffix: AnnualReportTexts.checkInDaysUnit,
                      style: TextStyle(
                        fontSize: numberSize,
                fontWeight: FontWeight.bold,
                        color: const Color(0xFF07C160),
              ),
            ),
                  ),
                  if (startDate != null && endDate != null) ...[
                    SizedBox(height: height * 0.05),
            FadeInText(
                      text: '$startDate${AnnualReportTexts.checkInDateRange}$endDate',
                      delay: const Duration(milliseconds: 900),
                      style: TextStyle(
                        fontSize: smallSize,
                        color: Colors.grey[500],
                      ),
                      textAlign: TextAlign.center,
                          ),
                    SizedBox(height: height * 0.02),
                          FadeInText(
                      text: AnnualReportTexts.checkInClosing,
                            delay: const Duration(milliseconds: 1100),
                            style: TextStyle(
                              fontSize: smallSize,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic,
                              height: 1.8,
                              letterSpacing: 0.5,
                            ),
                            textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // 作息图谱页
  Widget _buildActivityPatternPage() {
    final activityJson = _reportData!['activityPattern'];
    if (activityJson == null) {
      return Container(
        color: Colors.white,
        child: const Center(child: Text('暂无数据')),
      );
    }
    
    final activity = ActivityHeatmap.fromJson(activityJson);
    
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final width = constraints.maxWidth;
            final titleSize = height > 700 ? 36.0 : 32.0;
            final textSize = height > 700 ? 22.0 : 20.0;
            final numberSize = height > 700 ? 48.0 : 42.0;
            
            // 找出最活跃时段
            int maxHour = 0;
            int maxValue = 0;
            for (int hour = 0; hour < 24; hour++) {
              int hourTotal = 0;
              for (int day = 1; day <= 7; day++) {
                hourTotal += activity.getCount(hour, day);
              }
              if (hourTotal > maxValue) {
                maxValue = hourTotal;
                maxHour = hour;
              }
            }
            
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.1,
                vertical: height * 0.08,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  FadeInText(
                    text: AnnualReportTexts.activityTitle,
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF07C160),
                      letterSpacing: 1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: height * 0.02),
                  FadeInText(
                    text: AnnualReportTexts.activitySubtitle,
                    delay: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: titleSize - 12,
                      color: Colors.grey[500],
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: height * 0.06),
                  FadeInText(
                    text: AnnualReportTexts.activityEveryday,
                    delay: const Duration(milliseconds: 300),
                    style: TextStyle(
                      fontSize: textSize,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: height * 0.04),
                  SlideInCard(
                    delay: const Duration(milliseconds: 600),
                    child: Text(
                      '${maxHour.toString().padLeft(2, '0')}:00',
                      style: TextStyle(
                        fontSize: numberSize,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF07C160),
                      ),
                    ),
                  ),
                  SizedBox(height: height * 0.05),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: width * 0.08),
                    child: FadeInText(
                      text: AnnualReportTexts.activityClosing,
                    delay: const Duration(milliseconds: 900),
                    style: TextStyle(
                      fontSize: textSize - 2,
                      color: Colors.grey[600],
                      fontStyle: FontStyle.italic,
                        height: 1.9,
                        letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // 深夜密友页
  Widget _buildMidnightKingPage() {
    final midnightKing = _reportData!['midnightKing'];
    if (midnightKing == null || midnightKing['count'] == 0) {
      return Container(
        color: Colors.white,
        child: const Center(child: Text('暂无深夜聊天数据')),
      );
    }
    
    final displayName = midnightKing['displayName'] as String? ?? '未知';
    final count = midnightKing['count'] as int;
    final percentage = midnightKing['percentage'] as String? ?? '0';
    
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final width = constraints.maxWidth;
            final titleSize = height > 700 ? 36.0 : 32.0;
            final nameSize = height > 700 ? 52.0 : 46.0;
            final numberSize = height > 700 ? 32.0 : 28.0;
            final textSize = height > 700 ? 20.0 : 18.0;
            
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.1,
                vertical: height * 0.08,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  FadeInText(
                    text: AnnualReportTexts.midnightTitle,
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF5C6BC0),
                      letterSpacing: 1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: height * 0.02),
                  FadeInText(
                    text: AnnualReportTexts.midnightSubtitle,
                    delay: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: titleSize - 12,
                      color: Colors.grey[500],
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: height * 0.04),
                  FadeInText(
                    text: AnnualReportTexts.midnightTimeRange,
                    delay: const Duration(milliseconds: 300),
                    style: TextStyle(
                      fontSize: textSize,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: height * 0.06),
                  SlideInCard(
                    delay: const Duration(milliseconds: 600),
                    child: _buildNameWithBlur(
                      displayName,
                      TextStyle(
                        fontSize: nameSize,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF5C6BC0),
                        height: 1.3,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                  ),
                  SizedBox(height: height * 0.06),
                  FadeInText(
                    text: '聊了',
                    delay: const Duration(milliseconds: 900),
                    style: TextStyle(
                      fontSize: textSize,
                      color: Colors.grey[600],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: height * 0.03),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FadeInText(
                        text: '$count',
                        delay: const Duration(milliseconds: 1100),
                        style: TextStyle(
                          fontSize: numberSize,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF5C6BC0),
                        ),
                      ),
                      SizedBox(width: 8),
                      FadeInText(
                        text: AnnualReportTexts.midnightMessagesUnit,
                        delay: const Duration(milliseconds: 1100),
                        style: TextStyle(
                          fontSize: textSize,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: height * 0.015),
                  FadeInText(
                    text: '${AnnualReportTexts.midnightPercentagePrefix}$percentage${AnnualReportTexts.midnightPercentageSuffix}',
                    delay: const Duration(milliseconds: 1300),
                    style: TextStyle(
                      fontSize: textSize - 2,
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: height * 0.04),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: width * 0.08),
                    child: FadeInText(
                      text: AnnualReportTexts.midnightClosing,
                      delay: const Duration(milliseconds: 1500),
                      style: TextStyle(
                        fontSize: textSize - 2,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                        height: 1.9,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // 响应速度页（合并最快响应和我回复最快）
  Widget _buildResponseSpeedPage() {
    final whoRepliesFastest = _reportData!['whoRepliesFastest'] as List?;
    final myFastestReplies = _reportData!['myFastestReplies'] as List?;
    
    if ((whoRepliesFastest == null || whoRepliesFastest.isEmpty) &&
        (myFastestReplies == null || myFastestReplies.isEmpty)) {
      return Container(
        color: Colors.white,
        child: const Center(child: Text('暂无数据')),
      );
    }
    
    return Container(
      color: Colors.white,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final width = constraints.maxWidth;
            final titleSize = height > 700 ? 36.0 : 32.0;
            final nameSize = height > 700 ? 38.0 : 34.0;
            final textSize = height > 700 ? 22.0 : 20.0;
            
            // 获取第一名
            final fastestPerson = whoRepliesFastest != null && whoRepliesFastest.isNotEmpty
                ? whoRepliesFastest.first
                : null;
            final myFastest = myFastestReplies != null && myFastestReplies.isNotEmpty
                ? myFastestReplies.first
                : null;
            
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: width * 0.1,
                vertical: height * 0.05,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  FadeInText(
                    text: AnnualReportTexts.responseTitle,
                    style: TextStyle(
                      fontSize: titleSize,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF07C160),
                      letterSpacing: 1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: height * 0.015),
                  FadeInText(
                    text: AnnualReportTexts.responseSubtitle,
                    delay: const Duration(milliseconds: 200),
                    style: TextStyle(
                      fontSize: titleSize - 14,
                      color: Colors.grey[500],
                      letterSpacing: 0.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: height * 0.04),
                  
                  // 谁回复我最快
                  if (fastestPerson != null) ...[
                    FadeInText(
                      text: AnnualReportTexts.responseWhoRepliesYou,
                      delay: const Duration(milliseconds: 300),
                      style: TextStyle(
                        fontSize: textSize - 2,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: height * 0.02),
                    SlideInCard(
                      delay: const Duration(milliseconds: 600),
                      child: _buildNameWithBlur(
                        fastestPerson['displayName'] as String,
                        TextStyle(
                          fontSize: nameSize,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF07C160),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                      ),
                    ),
                    SizedBox(height: height * 0.015),
                    FadeInText(
                      text: _formatResponseTime(fastestPerson['avgResponseTimeMinutes'] as num),
                      delay: const Duration(milliseconds: 800),
                      style: TextStyle(
                        fontSize: textSize - 4,
                        color: const Color(0xFF07C160),
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: height * 0.012),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: width * 0.08),
                      child: FadeInText(
                        text: AnnualReportTexts.responseClosing1,
                        delay: const Duration(milliseconds: 900),
                        style: TextStyle(
                          fontSize: textSize - 6,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                          height: 1.6,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                  
                  if (fastestPerson != null && myFastest != null)
                    SizedBox(height: height * 0.05),
                  
                  // 我回复最快的人
                  if (myFastest != null) ...[
                    FadeInText(
                      text: AnnualReportTexts.responseYouReplyWho,
                      delay: const Duration(milliseconds: 1000),
                      style: TextStyle(
                        fontSize: textSize - 2,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: height * 0.02),
                    SlideInCard(
                      delay: const Duration(milliseconds: 1300),
                      child: _buildNameWithBlur(
                        myFastest['displayName'] as String,
                        TextStyle(
                          fontSize: nameSize,
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF07C160),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                      ),
                    ),
                    SizedBox(height: height * 0.015),
                    FadeInText(
                      text: _formatResponseTime(myFastest['avgResponseTimeMinutes'] as num),
                      delay: const Duration(milliseconds: 1500),
                      style: TextStyle(
                        fontSize: textSize - 4,
                        color: const Color(0xFF07C160),
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: height * 0.012),
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: width * 0.08),
                      child: FadeInText(
                        text: AnnualReportTexts.responseClosing2,
                        delay: const Duration(milliseconds: 1600),
                        style: TextStyle(
                          fontSize: textSize - 6,
                          color: Colors.grey[600],
                          fontStyle: FontStyle.italic,
                          height: 1.6,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatResponseTime(num minutes) {
    if (minutes < 1) {
      return '${AnnualReportTexts.responseAvgPrefix}${(minutes * 60).toStringAsFixed(0)} 秒';
    } else if (minutes < 60) {
      return '${AnnualReportTexts.responseAvgPrefix}${minutes.toStringAsFixed(1)} 分钟';
    } else {
      final hours = minutes / 60;
      return '${AnnualReportTexts.responseAvgPrefix}${hours.toStringAsFixed(1)} 小时';
    }
  }

  // 结束页 - 简约排版，修复溢出
  Widget _buildEndingPage() {
    final yearText = widget.year != null ? '${widget.year}年' : '这段时光';
    final totalMessages = _getTotalMessages();
    final totalFriends = _getTotalFriends();
    
    return Container(
      color: Colors.white,
      child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final height = constraints.maxHeight;
              final width = constraints.maxWidth;
              final titleSize = height > 700 ? 32.0 : 28.0;
            final numberSize = height > 700 ? 56.0 : 48.0;
            final textSize = height > 700 ? 17.0 : 15.0;
            final smallSize = height > 700 ? 14.0 : 13.0;
            
            return Stack(
              children: [
                // 顶部标题
                Positioned(
                  left: width * 0.08,
                  top: height * 0.1,
                  right: width * 0.08,
          child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FadeInText(
                      text: '$yearText${AnnualReportTexts.endingTitleSuffix}',
                      style: TextStyle(
                        fontSize: titleSize,
                  fontWeight: FontWeight.bold,
                        color: const Color(0xFF07C160),
                        letterSpacing: 2,
                ),
              ),
                      SizedBox(height: 8),
              FadeInText(
                        text: AnnualReportTexts.endingSubtitle,
                      delay: const Duration(milliseconds: 300),
                      style: TextStyle(
                        fontSize: textSize,
                          color: Colors.grey[500],
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // 中间数据区域
                Positioned(
                  left: width * 0.12,
                  top: height * 0.32,
                  child: SlideInCard(
                    delay: const Duration(milliseconds: 600),
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        AnimatedNumberDisplay(
                          value: totalMessages.toDouble(),
                          suffix: '',
                              style: TextStyle(
                            fontSize: numberSize,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF07C160),
                            height: 1.0,
                          ),
                        ),
                        SizedBox(height: 4),
                            Text(
                          AnnualReportTexts.endingMessagesUnit,
                              style: TextStyle(
                            fontSize: textSize - 2,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                
                Positioned(
                  right: width * 0.12,
                  top: height * 0.48,
                  child: SlideInCard(
                    delay: const Duration(milliseconds: 800),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        AnimatedNumberDisplay(
                          value: totalFriends.toDouble(),
                          suffix: '',
                          style: TextStyle(
                            fontSize: numberSize * 0.7,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF07C160),
                            height: 1.0,
                          ),
                        ),
                        SizedBox(height: 4),
                            Text(
                          AnnualReportTexts.endingFriendsUnit,
                              style: TextStyle(
                            fontSize: textSize - 3,
                            color: Colors.grey[600],
                          ),
                            ),
                          ],
                        ),
                      ),
                    ),
                
                // 中间分隔线
                Positioned(
                  left: width * 0.3,
                  right: width * 0.3,
                  top: height * 0.58,
                  child: SlideInCard(
                    delay: const Duration(milliseconds: 1000),
                    child: Container(
                      height: 1,
                      color: Colors.grey[300],
                    ),
                  ),
                ),
                
                // 底部温暖寄语
                Positioned(
                  left: width * 0.1,
                  right: width * 0.1,
                  bottom: height * 0.08,
                  child: Column(
                    children: [
                    FadeInText(
                        text: AnnualReportTexts.endingPoem1,
                        delay: const Duration(milliseconds: 1200),
                      style: TextStyle(
                          fontSize: textSize,
                          color: Colors.grey[700],
                          height: 1.9,
                          letterSpacing: 0.5,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: height * 0.04),
                    FadeInText(
                        text: AnnualReportTexts.endingPoem2,
                        delay: const Duration(milliseconds: 1400),
                      style: TextStyle(
                          fontSize: smallSize,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                          height: 2.0,
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: height * 0.02),
                    ],
                  ),
                ),
              ],
              );
            },
        ),
      ),
    );
  }

  // 显示导出对话框
  void _showExportDialog() {
    String tempHideMode = _nameHideMode;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('导出年度报告'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('选择联系人信息显示方式：'),
              const SizedBox(height: 16),
              RadioListTile<String>(
                title: const Text('显示完整信息'),
                value: 'none',
                groupValue: tempHideMode,
                onChanged: (value) {
                  setState(() => tempHideMode = value!);
                },
              ),
              RadioListTile<String>(
                title: const Text('仅保留姓氏'),
                value: 'firstChar',
                groupValue: tempHideMode,
                onChanged: (value) {
                  setState(() => tempHideMode = value!);
                },
              ),
              RadioListTile<String>(
                title: const Text('完全隐藏'),
                value: 'full',
                groupValue: tempHideMode,
                onChanged: (value) {
                  setState(() => tempHideMode = value!);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                this.setState(() => _nameHideMode = tempHideMode);
                Navigator.pop(context);
                _exportReport();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF07C160),
                foregroundColor: Colors.white,
              ),
              child: const Text('开始导出'),
            ),
          ],
        ),
      ),
    );
  }

  // 导出报告
  Future<void> _exportReport() async {
    if (_isExporting) return;

    setState(() => _isExporting = true);

    // 显示进度对话框
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => WillPopScope(
          onWillPop: () async => false,
          child: const AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在生成图片，请稍候...'),
              ],
            ),
          ),
        ),
      );
    }

    try {
      // 获取保存目录
      final directory = await getApplicationDocumentsDirectory();
      final exportDir = Directory('${directory.path}/EchoTrace');
      
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final images = <Uint8List>[];
      
      // 记录当前页面
      final originalPage = _currentPage;
      
      // 通过翻页截图的方式获取所有页面
      for (int i = 0; i < _pages!.length; i++) {
        // 跳转到指定页面
        _pageController.jumpToPage(i);
        
        // 等待页面切换动画完成
        await Future.delayed(const Duration(milliseconds: 500));
        
        // 等待所有帧完成渲染（包括文本和emoji）
        await SchedulerBinding.instance.endOfFrame;
        await Future.delayed(const Duration(milliseconds: 100));
        
        // 再等待确保emoji字体加载完成
        await Future.delayed(const Duration(milliseconds: 2000));
        
        // 再次等待一帧，确保所有内容都已完全绘制
        await SchedulerBinding.instance.endOfFrame;
        
        // 截取当前页面
        try {
          final boundary = _pageViewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
          if (boundary != null) {
            // 标记需要重绘
            boundary.markNeedsPaint();
            
            // 等待重绘完成
            await Future.delayed(const Duration(milliseconds: 200));
            await SchedulerBinding.instance.endOfFrame;
            
            // 执行截图
            final image = await boundary.toImage(pixelRatio: 3.0);
            final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
            if (byteData != null) {
              images.add(byteData.buffer.asUint8List());
            }
          }
        } catch (e) {
        }
      }
      
      // 恢复到原始页面
      _pageController.jumpToPage(originalPage);

      if (images.isEmpty) {
        throw Exception('生成图片失败：所有页面截图都失败了');
      }

      // 在后台线程拼接图片
      final combinedImage = await compute(_combineImagesInBackground, images);
      
      // 保存文件
      final yearText = widget.year != null ? '${widget.year}' : 'all';
      final filePath = '${exportDir.path}/annual_report_${yearText}_$timestamp.png';
      final file = File(filePath);
      await file.writeAsBytes(combinedImage);

      // 关闭进度对话框
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导出成功：$filePath\n共生成 ${images.length} 页'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      // 关闭进度对话框
      if (mounted) {
        Navigator.of(context).pop();
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败：$e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _nameHideMode = 'none'; // 恢复显示
        });
      }
    }
  }


  // 拼接多张图片为一张长图（后台线程执行）
  static Future<Uint8List> _combineImagesInBackground(List<Uint8List> images) async {
    final decodedImages = <img.Image>[];
    int totalHeight = 0;
    int maxWidth = 0;

    // 解码所有图片并计算总高度
    for (final imageBytes in images) {
      final decodedImage = img.decodeImage(imageBytes);
      if (decodedImage != null) {
        decodedImages.add(decodedImage);
        totalHeight += decodedImage.height;
        if (decodedImage.width > maxWidth) {
          maxWidth = decodedImage.width;
        }
      }
    }

    // 创建新图片
    final combined = img.Image(width: maxWidth, height: totalHeight);
    
    // 填充白色背景
    img.fill(combined, color: img.ColorRgb8(255, 255, 255));

    // 拼接图片
    int currentY = 0;
    for (final image in decodedImages) {
      img.compositeImage(combined, image, dstY: currentY);
      currentY += image.height;
    }

    // 编码为PNG
    return Uint8List.fromList(img.encodePng(combined));
  }


  // 处理名字隐藏 - 使用高斯模糊覆盖
  Widget _buildNameWithBlur(String name, TextStyle style, {TextAlign? textAlign, int? maxLines}) {
    if (_nameHideMode == 'none') {
      return Text(
        name,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: maxLines != null ? TextOverflow.ellipsis : null,
      );
    }

    // 保留首字模式：只模糊后面的字
    if (_nameHideMode == 'firstChar' && name.isNotEmpty) {
      // 使用 characters 正确处理 emoji 等复杂字符
      final characters = name.characters;
      if (characters.isEmpty) {
        return Text('', style: style);
      }
      
      final firstChar = characters.first;
      final restChars = characters.length > 1 
          ? characters.skip(1).toString() 
          : '';
      
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 第一个字符不模糊
          Text(
            firstChar,
            style: style,
          ),
          // 后面的字模糊
          if (restChars.isNotEmpty)
            Stack(
              children: [
                Text(
                  restChars,
                  style: style,
                ),
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: 15.0,
                        sigmaY: 15.0,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      );
    }

    // 完全隐藏模式：全部模糊
    return Stack(
      children: [
        Text(
          name,
          style: style,
          textAlign: textAlign,
          maxLines: maxLines,
          overflow: maxLines != null ? TextOverflow.ellipsis : null,
        ),
        Positioned.fill(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: 15.0,
                sigmaY: 15.0,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
