import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/assets.dart';
import 'earnings_details_screen.dart';
import 'job_details_screen.dart';
import 'worker_navigation_screen.dart';
import 'mock_payment_screen.dart';
import '../../models/job_request.dart';
import '../job_service.dart';
import '../location_service.dart';
import 'worker_profile_screen.dart';

class WorkerHomeScreen extends StatefulWidget {
  const WorkerHomeScreen({super.key});

  @override
  State<WorkerHomeScreen> createState() => _WorkerHomeScreenState();
}

class _WorkerHomeScreenState extends State<WorkerHomeScreen> {
  int tabIndex = 0;
  bool _isDndActive = false;

  final JobService jobService = JobService();

  List<JobRequest> _newJobs = [];
  List<JobRequest> _ongoingJobs = [];
  List<JobRequest> _completedJobs = [];

  StreamSubscription<List<JobRequest>>? _newJobsSub;
  StreamSubscription<List<JobRequest>>? _ongoingJobsSub;
  StreamSubscription<List<JobRequest>>? _completedJobsSub;
  StreamSubscription<QuerySnapshot>? _confirmedJobSub;
  StreamSubscription<DocumentSnapshot>? _workerProfileSub;

  bool _hasNavigatedToJob = false;
  String? _streamError;
  Map<String, dynamic>? _workerProfile;
  final Map<String, double> _customerRatings = {};

  @override
  void initState() {
    super.initState();
    debugPrint('[WorkerHome] initState - initializing worker home screen');
    _loadDndStatus();
    _subscribeToJobs();
    _listenForConfirmedJobs();
    _listenToWorkerProfile();
    // Start sharing location immediately when home screen loads
    LocationService.instance.startSharing();
  }

  /// Real-time listen to worker profile including walletBalance & verificationStatus
  void _listenToWorkerProfile() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('[WorkerHome] No user logged in');
      return;
    }

    debugPrint('[WorkerHome] Listening to worker profile for UID: ${user.uid}');

    _workerProfileSub?.cancel();
    _workerProfileSub = FirebaseFirestore.instance
        .collection('workers')
        .doc(user.uid)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;

            if (snapshot.exists) {
              final newData = snapshot.data();
              debugPrint('[WorkerHome] Worker profile updated: $newData');

              setState(() {
                _workerProfile = newData;
              });
            } else {
              debugPrint('[WorkerHome] Worker profile does not exist');
            }
          },
          onError: (e, st) {
            debugPrint('[WorkerHome] Worker profile error: $e');
            debugPrintStack(stackTrace: st);
          },
        );
  }

  void _subscribeToJobs() {
    debugPrint('[WorkerHome] Subscribing to jobs...');
    
    _newJobsSub?.cancel();
    _newJobsSub = jobService.streamNewJobs().listen(
      (jobs) {
        debugPrint('[WorkerHome] New jobs received: ${jobs.length}');
        if (mounted) {
          setState(() {
            _newJobs = jobs;
            _streamError = null;
          });
          _prefetchCustomerRatings(jobs);
        }
      },
      onError: (e, st) {
        debugPrint('[WorkerHome] New jobs error: $e');
        debugPrintStack(stackTrace: st);
        _handleStreamError('New', e);
      },
    );

    _ongoingJobsSub?.cancel();
    _ongoingJobsSub = jobService.streamOngoingJobs().listen(
      (jobs) {
        debugPrint('[WorkerHome] Ongoing jobs received: ${jobs.length}');
        if (mounted) {
          setState(() {
            _ongoingJobs = jobs;
            _streamError = null;
          });
          _prefetchCustomerRatings(jobs);
        }
      },
      onError: (e, st) {
        debugPrint('[WorkerHome] Ongoing jobs error: $e');
        debugPrintStack(stackTrace: st);
        _handleStreamError('Ongoing', e);
      },
    );

    _completedJobsSub?.cancel();
    _completedJobsSub = jobService.streamCompletedJobs().listen(
      (jobs) {
        debugPrint('[WorkerHome] Completed jobs received: ${jobs.length}');
        if (mounted) {
          setState(() {
            _completedJobs = jobs;
            _streamError = null;
          });
          _prefetchCustomerRatings(jobs);
        }
      },
      onError: (e, st) {
        debugPrint('[WorkerHome] Completed jobs error: $e');
        debugPrintStack(stackTrace: st);
        _handleStreamError('Completed', e);
      },
    );
  }

  Future<void> _prefetchCustomerRatings(List<JobRequest> jobs) async {
    final ids = jobs
        .map((j) => j.customerId)
        .where((id) => id.trim().isNotEmpty && !_customerRatings.containsKey(id))
        .toSet()
        .toList();

    if (ids.isEmpty) {
      debugPrint('[WorkerHome] No new customers to prefetch ratings for');
      return;
    }

    debugPrint('[WorkerHome] Prefetching ratings for ${ids.length} customers');

    for (final customerId in ids) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('customers')
            .doc(customerId)
            .get();
        
        if (!doc.exists) {
          debugPrint('[WorkerHome] Customer $customerId not found');
          continue;
        }
        
        final data = doc.data() ?? {};
        final rating = (data['rating'] as num?)?.toDouble() ??
            (data['averageRating'] as num?)?.toDouble();
        
        if (rating != null && rating > 0) {
          if (mounted) {
            setState(() {
              _customerRatings[customerId] = rating;
            });
            debugPrint('[WorkerHome] Cached rating for $customerId: $rating');
          }
        } else {
          debugPrint('[WorkerHome] No rating found for customer $customerId');
        }
      } catch (e) {
        debugPrint('[WorkerHome] Error prefetching rating for $customerId: $e');
        // Best-effort enrichment; ignore lookup failures.
      }
    }
  }

  double _distanceKmFrom(GeoPoint from, GeoPoint to) {
    const earthRadiusKm = 6371.0;
    final lat1 = from.latitude * math.pi / 180.0;
    final lat2 = to.latitude * math.pi / 180.0;
    final dLat = (to.latitude - from.latitude) * math.pi / 180.0;
    final dLng = (to.longitude - from.longitude) * math.pi / 180.0;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  String _distanceLabel(JobRequest job) {
    if (job.distanceKm != null && job.distanceKm! > 0) {
      return '${job.distanceKm!.toStringAsFixed(1)} km away';
    }
    if (job.distanceKmEstimate != null && job.distanceKmEstimate! > 0) {
      return '${job.distanceKmEstimate!.toStringAsFixed(1)} km away';
    }
    if (job.distanceTextEstimate != null && job.distanceTextEstimate!.trim().isNotEmpty) {
      return '${job.distanceTextEstimate} away';
    }

    final workerGeo = _workerProfile != null
        ? (_workerProfile!['lastLocation'] as GeoPoint? ?? _workerProfile!['location'] as GeoPoint?)
        : null;
    final customerGeo = job.customerLocation;
    if (workerGeo != null && customerGeo != null) {
      final km = _distanceKmFrom(workerGeo, customerGeo);
      return '${km.toStringAsFixed(1)} km away';
    }

    return 'Distance unavailable';
  }

  double? _customerRatingFor(JobRequest job) {
    return job.customerRating ?? _customerRatings[job.customerId];
  }

  void _handleStreamError(String source, Object e) {
    debugPrint('$source jobs stream error: $e');
    if (mounted) {
      setState(() {
        _streamError = e.toString();
      });
    }
  }

  void _listenForConfirmedJobs() {
    final workerId = FirebaseAuth.instance.currentUser?.uid;
    if (workerId == null) return;

    _confirmedJobSub?.cancel();
    _confirmedJobSub = FirebaseFirestore.instance
        .collection('jobRequests')
        .where('status', isEqualTo: 'customerConfirmed')
        .where('workerId', isEqualTo: workerId)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty && !_hasNavigatedToJob && mounted) {
        final doc = snapshot.docs.first;
        final job = JobRequest.fromFirestore(doc);
        _hasNavigatedToJob = true;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => WorkerNavigationScreen(job: job),
          ),
        ).then((_) {
          _hasNavigatedToJob = false;
        });
      }
    });
  }

  Future<void> _loadDndStatus() async {
    final workerId = FirebaseAuth.instance.currentUser?.uid;
    if (workerId == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('workers')
          .doc(workerId)
          .get();
      if (doc.exists && doc.data() != null) {
        final isDnd = doc.data()!['doNotDisturb'] ?? false;
        final isAvailable = doc.data()!['isAvailable'];

        setState(() {
          _isDndActive = isDnd;
        });

        if (isAvailable != !isDnd) {
          _toggleDnd(isDnd);
        }
      } else {
        _toggleDnd(false);
      }
    } catch (e) {
      debugPrint('Error loading DND status: $e');
    }
  }

  Future<void> _toggleDnd(bool value) async {
    setState(() {
      _isDndActive = value;
    });

    final workerId = FirebaseAuth.instance.currentUser?.uid;
    if (workerId == null) return;

    try {
      await FirebaseFirestore.instance.collection('workers').doc(workerId).set({
        'doNotDisturb': value,
        'isAvailable': !value,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error setting DND status: $e');
    }
  }

  /// Open Google Maps with customer location
  Future<void> _openGoogleMaps(GeoPoint location) async {
    final lat = location.latitude;
    final lng = location.longitude;
    final uri = Uri.parse('https://maps.google.com/?q=$lat,$lng');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open Google Maps')),
        );
      }
    }
  }

  String _formatTime(int seconds) {
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return seconds >= 3600 ? '$h:$m:$s' : '$m:$s';
  }

  String _formatCurrency(double amount) {
    return 'Rs. ${amount.toStringAsFixed(2)}';
  }

  @override
  void dispose() {
    _newJobsSub?.cancel();
    _ongoingJobsSub?.cancel();
    _completedJobsSub?.cancel();
    _confirmedJobSub?.cancel();
    _workerProfileSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        backgroundColor: Colors.white,
        automaticallyImplyLeading: false,
        toolbarHeight: 88,
        titleSpacing: 14,
        title: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ClipRect(
                  child: Transform.scale(
                    scale: 1.42,
                    child: Image.asset(
                      AppAssets.techniLogo,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'TECHNI WORKER',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Row(
              children: [
                Text(
                  'DND',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _isDndActive
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF4B5563),
                  ),
                ),
                const SizedBox(width: 6),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: _isDndActive,
                    onChanged: _toggleDnd,
                    activeThumbColor: Colors.red,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const WorkerProfileScreen(),
                  ),
                ).then((_) => {});
              },
              child: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.blue.shade50,
                backgroundImage: (_workerProfile?['profileUrl'] != null &&
                        _workerProfile!['profileUrl'].toString().isNotEmpty)
                    ? (_workerProfile!['profileUrl']
                            .toString()
                            .startsWith('http')
                        ? NetworkImage(
                            _workerProfile!['profileUrl'] as String)
                        : FileImage(
                            File(_workerProfile!['profileUrl'] as String)))
                    : null,
                child: (_workerProfile?['profileUrl'] == null ||
                        _workerProfile!['profileUrl'].toString().isEmpty)
                    ? const Icon(Icons.person, size: 18, color: Colors.blue)
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshJobs,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Wallet Balance Card
              _walletCard(),
              const SizedBox(height: 16),
              // Earnings Card
              _earningsCard(context),
              const SizedBox(height: 16),
              // Tab Switcher
              _tabs(_newJobs.length),
              const SizedBox(height: 14),
              // Job Cards Section
              if (tabIndex == 0)
                _jobsSection(jobs: _newJobs, type: 'new')
              else if (tabIndex == 1)
                _jobsSection(jobs: _ongoingJobs, type: 'ongoing')
              else
                _jobsSection(jobs: _completedJobs, type: 'completed'),
            ],
          ),
        ),
      ),
    );
  }

  /// Wallet Balance Card
  Widget _walletCard() {
    final num balanceNum = (_workerProfile?['walletBalance'] as num?) ?? 0;
    final double balance = balanceNum.toDouble();
    final isNegative = balance < 0;
    final bgColor = isNegative ? Colors.red.shade50 : Colors.green.shade50;
    final borderColor = isNegative ? Colors.red.shade200 : Colors.green.shade200;
    final amountColor = isNegative ? Colors.red.shade700 : Colors.green.shade700;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            blurRadius: 8,
            color: isNegative
                ? Colors.red.withValues(alpha: 0.1)
                : Colors.green.withValues(alpha: 0.1),
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Wallet Balance',
                style: TextStyle(
                  fontSize: 12,
                  color: isNegative ? Colors.red.shade600 : Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _formatCurrency(balance),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: amountColor,
                ),
              ),
              if (isNegative)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Outstanding Dues',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.red.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(
            height: 44,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isNegative ? Colors.red : const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                final verificationStatus = _workerProfile?['verificationStatus'] ?? 'pending';
                // Allow paying dues even when blocked. Only restrict top-up for non-verified users.
                if (!isNegative && verificationStatus != 'verified') {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Only verified workers can make payments'),
                      backgroundColor: Colors.orange,
                      duration: Duration(seconds: 3),
                    ),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MockPaymentScreen(
                      isPaidDues: isNegative,
                      requiredAmount: isNegative ? balance.abs().toDouble() : null,
                    ),
                  ),
                );
              },
              child: Text(
                isNegative ? 'Pay Dues' : 'Top Up',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Earnings Card
  Widget _earningsCard(BuildContext context) {
    final totalEarned = _completedJobs.fold<double>(
      0,
      (acc, job) => acc + (job.fare ?? 0),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 14,
            color: Color(0x12000000),
            offset: Offset(0, 8),
          ),
        ],
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "This Week's Earnings",
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Text(
                  _formatCurrency(totalEarned),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.trending_up, color: Colors.green.shade600, size: 18),
                    const SizedBox(width: 6),
                    Text(
                      '+${_completedJobs.length} jobs completed',
                      style: TextStyle(
                        color: Colors.green.shade600,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const EarningsDetailsScreen(),
                  ),
                );
              },
              child: const Text(
                'View Details',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tab Buttons
  Widget _tabs(int newJobCount) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _tabButton('New Jobs', tabIndex == 0, index: 0, badge: newJobCount),
          const SizedBox(width: 8),
          _tabButton('Ongoing', tabIndex == 1, index: 1),
          const SizedBox(width: 8),
          _tabButton('Completed', tabIndex == 2, index: 2),
        ],
      ),
    );
  }

  Widget _tabButton(String text, bool active, {required int index, int? badge}) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => setState(() => tabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE8F0FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? const Color(0xFF2563EB) : Colors.black12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: active ? const Color(0xFF2563EB) : Colors.black87,
                fontSize: 13,
              ),
            ),
            if (badge != null && badge > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$badge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Jobs Section (for JobRequest lists: new, ongoing, completed)
  Widget _jobsSection({required List<JobRequest> jobs, required String type}) {
    if (_streamError != null && jobs.isEmpty) {
      return _errorContainer();
    }

    if (jobs.isEmpty) {
      return _emptyStateContainer(type);
    }

    return Column(
      children: [
        ...jobs.map((job) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              children: [
                _jobRequestCard(job, type),
                const SizedBox(height: 12),
                _actionButtons(job, type),
              ],
            ),
          );
        }),
      ],
    );
  }

  /// Error Container
  Widget _errorContainer() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.red.shade50,
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 32),
          const SizedBox(height: 12),
          const Text(
            'Sync Error',
            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
          ),
          const SizedBox(height: 8),
          Text(
            _streamError ?? 'Unknown error',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.red.shade800, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _refreshJobs,
            child: const Text('Retry Sync'),
          ),
        ],
      ),
    );
  }

  /// Empty State Container
  Widget _emptyStateContainer(String type) {
    IconData icon;
    String message;
    switch (type) {
      case 'new':
        icon = Icons.work_outline;
        message = 'No job requests available right now';
        break;
      case 'scheduled':
        icon = Icons.calendar_month_outlined;
        message = 'No scheduled jobs yet.';
        break;
      case 'ongoing':
        icon = Icons.running_with_errors;
        message = 'No ongoing jobs at the moment.';
        break;
      default:
        icon = Icons.check_circle_outline;
        message = 'No completed jobs yet.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
        color: Colors.white,
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.black38, size: 32),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// Job Request Card
  Widget _jobRequestCard(JobRequest job, String type) {
    final customerRating = _customerRatingFor(job);
    final hasCustomerRating = customerRating != null && customerRating > 0;
    final description = (job.description ?? '').trim();
    final issueImageUrl = (job.issueImageUrl ?? '').trim();
    final hasIssueImage = issueImageUrl.isNotEmpty;
    final hasDescription = description.isNotEmpty;
    final customerDisplayName = job.customerName.trim().isEmpty
        ? 'Customer'
        : job.customerName;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => JobDetailsScreen(job: job)),
          );
        },
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.black12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 10,
                offset: Offset(0, 6),
              ),
            ],
            color: Colors.white,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${job.jobType} • ${job.status}',
                      style: const TextStyle(
                        color: Color(0xFF2563EB),
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      customerDisplayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _distanceLabel(job),
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      job.fare != null
                          ? 'Est. ${_formatCurrency(job.fare!)}'
                          : 'Fare not available yet',
                      style: const TextStyle(color: Colors.black54, fontSize: 13),
                    ),
                    if (hasDescription) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Customer note: $description',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black87, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          type == 'completed' ? 'Customer feedback: ' : 'Customer rating: ',
                          style: const TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                        if (type == 'completed' && job.rating != null) ...[
                          ..._buildStars(job.rating!.toDouble()),
                          const SizedBox(width: 4),
                          Text(
                            job.rating!.toStringAsFixed(1),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                        ] else if (hasCustomerRating) ...[
                          ..._buildStars(customerRating),
                          const SizedBox(width: 4),
                          Text(
                            customerRating.toStringAsFixed(1),
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                        ] else
                          const Text(
                            'N/A',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                      ],
                    ),
                    if (type == 'completed' && (job.review ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Review: ${job.review!.trim()}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.black87, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                height: 64,
                width: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: hasIssueImage
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.network(
                          issueImageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Icon(Icons.broken_image, color: Colors.black45),
                        ),
                      )
                    : const Icon(Icons.image, color: Colors.black45),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build Stars Rating
  List<Widget> _buildStars(double rating) {
    final stars = <Widget>[];
    for (var i = 1; i <= 5; i++) {
      if (rating >= i) {
        stars.add(const Icon(Icons.star, color: Colors.orange, size: 14));
      } else if (rating >= i - 0.5) {
        stars.add(const Icon(Icons.star_half, color: Colors.orange, size: 14));
      } else {
        stars.add(const Icon(Icons.star_border, color: Colors.orange, size: 14));
      }
    }
    return stars;
  }

  /// Action Buttons
  Widget _actionButtons(JobRequest job, String type) {
    if (type == 'new') {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  await jobService.acceptJob(job.id);
                  LocationService.instance.startSharing();
                },
                child: const Text('Accept', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: SizedBox(
              height: 44,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.black87,
                  side: const BorderSide(color: Colors.black26),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () async {
                  await jobService.declineJob(job.id);
                },
                child: const Text('Decline', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      );
    } else if (type == 'ongoing') {
      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => WorkerNavigationScreen(job: job),
                    ),
                  );
                },
                icon: const Icon(Icons.timer, size: 18),
                label: const Text('View Timer', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      );
    } else if (type == 'completed') {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.shade100),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Job Completed',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                    fontSize: 13,
                  ),
                ),
                Text(
                  'Duration: ${job.durationSeconds != null ? _formatTime(job.durationSeconds!) : "N/A"}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                if ((job.review ?? '').trim().isNotEmpty)
                  Text(
                    'Review: ${job.review!.trim()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                const SizedBox(height: 2),
                Text(
                  'Earned: ${_formatCurrency(job.fare ?? 0)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
            const Icon(Icons.check_circle, color: Colors.green),
          ],
        ),
      );
    }

    if (job.status == 'customerConfirmed') {
      return SizedBox(
        width: double.infinity,
        height: 46,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF22C55E),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => WorkerNavigationScreen(job: job),
              ),
            );
          },
          icon: const Icon(Icons.navigation, size: 18),
          label: const Text('Start Navigation', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Text(
        'Waiting for customer confirmation...',
        style: TextStyle(
          color: Colors.amber.shade900,
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  Future<void> _refreshJobs() async {
    setState(() {
      _hasNavigatedToJob = false;
      _streamError = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }
}
