import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/job_request.dart';
import '../models/scheduled_job.dart';

class JobService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _normalizeCategory(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  String _resolveWorkerCategoryKey(String? rawCategory) {
    final key = _normalizeCategory(rawCategory ?? '');
    const map = {
      'plumbing_services': 'plumber',
      'plumbing': 'plumber',
      'plumber': 'plumber',
      'electrical_services': 'electrician',
      'electrical': 'electrician',
      'electrician': 'electrician',
      'gardening_services': 'gardener',
      'gardening': 'gardener',
      'gardener': 'gardener',
      'carpentry_services': 'carpenter',
      'carpentry': 'carpenter',
      'carpenter': 'carpenter',
      'painting_services': 'painter',
      'painting': 'painter',
      'painter': 'painter',
      'ac_services': 'ac_tech',
      'ac_technician': 'ac_tech',
      'ac_repair': 'ac_tech',
      'ac_tech': 'ac_tech',
      'elv_services': 'elv_repair',
      'elv_repairer': 'elv_repair',
      'elv_repair': 'elv_repair',
    };
    return map[key] ?? key;
  }

  /// Returns the current worker's UID, or null if not logged in.
  String? get _workerId {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid;
  }

  // ─── Real-time Streams ──────────────────────────────────────────────────────

  /// Stream all "pending" jobs (new job requests where this worker is notified and status is searching).
  Stream<List<JobRequest>> streamNewJobs() {
    final wid = _workerId;
    if (wid == null) {
      debugPrint('[JobService] No worker ID available for streamNewJobs');
      return Stream.value(<JobRequest>[]);
    }

    debugPrint('[JobService] Starting streamNewJobs for worker: $wid');

    return _firestore
        .collection('jobRequests')
        .where('notifiedWorkerIds', arrayContains: wid)
        .snapshots()
        .map((snap) {
          debugPrint('[JobService] streamNewJobs snapshot: ${snap.docs.length} total');
          final filtered = <JobRequest>[];
          for (var doc in snap.docs) {
            try {
              final job = JobRequest.fromFirestore(doc);
              if (job.status == 'searching' && !job.rejectedWorkerIds.contains(wid)) {
                filtered.add(job);
              }
            } catch (e) {
              debugPrint('[JobService] Error parsing new job ${doc.id}: $e');
            }
          }
          debugPrint('[JobService] streamNewJobs filtered: ${filtered.length}');
          return filtered;
        })
        .handleError((error) {
          debugPrint('[JobService] streamNewJobs ERROR: $error');
        });
  }

  /// Stream calendar-scheduled jobs from the `scheduledJobs` collection.
  /// Shows pending jobs matching [workerCategory] (any worker can accept)
  /// plus accepted jobs where this worker is assigned.
  Stream<List<ScheduledJob>> streamScheduledJobs(String? workerCategory) {
    final wid = _workerId;
    if (wid == null) {
      debugPrint('[JobService] No worker ID available for streamScheduledJobs');
      return Stream.value(<ScheduledJob>[]);
    }

    final workerCategoryKey = _resolveWorkerCategoryKey(workerCategory);
    debugPrint('[JobService] Starting streamScheduledJobs for category: $workerCategoryKey');

    return _firestore
        .collection('scheduledJobs')
        .where('status', whereIn: ['pending', 'accepted'])
        .snapshots()
        .map((snap) {
          final now = DateTime.now();
          debugPrint('[JobService] streamScheduledJobs snapshot: ${snap.docs.length}');
          final jobs = <ScheduledJob>[];
          for (var doc in snap.docs) {
            try {
              final job = ScheduledJob.fromFirestore(doc);
              final jobCategoryKey = _resolveWorkerCategoryKey(job.category);
              // Show all pending jobs + only accepted jobs this worker accepted
              final isAcceptedByMe = job.status == 'accepted' && job.workerId == wid;
              final categoryMatches = workerCategoryKey.isNotEmpty &&
                  jobCategoryKey.isNotEmpty &&
                  jobCategoryKey == workerCategoryKey;
                final isDueNow = job.scheduledAt == null || !job.scheduledAt!.isAfter(now);
                final includePending =
                  job.status == 'pending' && categoryMatches && isDueNow;

              if (isAcceptedByMe || includePending) {
                jobs.add(job);
              }
            } catch (e) {
              debugPrint('[JobService] Error parsing scheduled job ${doc.id}: $e');
            }
          }
          jobs.sort((a, b) =>
              (a.scheduledAt ?? a.createdAt)
                  .compareTo(b.scheduledAt ?? b.createdAt));
          debugPrint('[JobService] streamScheduledJobs result: ${jobs.length}');
          return jobs;
        })
        .handleError((error) {
          debugPrint('[JobService] streamScheduledJobs ERROR: $error');
        });
  }

  /// Worker accepts a scheduled job — stamps workerId/workerName and sets status to accepted.
  Future<void> acceptScheduledJob(String jobId, String? workerName) async {
    final wid = _workerId;
    if (wid == null) return;
    await _firestore.collection('scheduledJobs').doc(jobId).update({
      'status': 'accepted',
      'workerId': wid,
      'workerName': workerName ?? 'Worker',
      'acceptedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('[JobService] Scheduled job $jobId accepted by $wid');
  }

  /// Worker cancels/passes a scheduled job — resets to pending (if they own it)
  /// or marks declined for this worker (if still pending, do nothing / ignore).
  Future<void> cancelScheduledJob(String jobId) async {
    final wid = _workerId;
    if (wid == null) return;
    // Only cancel if this worker is the one who accepted it
    final doc = await _firestore.collection('scheduledJobs').doc(jobId).get();
    if (!doc.exists) return;
    final data = doc.data() ?? {};
    if (data['workerId'] == wid && data['status'] == 'accepted') {
      await _firestore.collection('scheduledJobs').doc(jobId).update({
        'status': 'pending',
        'workerId': null,
        'workerName': null,
        'acceptedAt': null,
      });
      debugPrint('[JobService] Scheduled job $jobId returned to pending by $wid');
    }
  }

  /// Stream jobs that are currently active (navigating, arrived, or work in progress).
  Stream<List<JobRequest>> streamOngoingJobs() {
    final wid = _workerId;
    if (wid == null) {
      debugPrint('[JobService] No worker ID available for streamOngoingJobs');
      return Stream.value(<JobRequest>[]);
    }

    debugPrint('[JobService] Starting streamOngoingJobs for worker: $wid');

    return _firestore
        .collection('jobRequests')
        .where('workerId', isEqualTo: wid)
        .where('status', whereIn: ['inProgress', 'arrived', 'workStarted'])
        .snapshots()
        .map((snap) {
          debugPrint('[JobService] streamOngoingJobs snapshot: ${snap.docs.length}');
          final jobs = <JobRequest>[];
          for (var doc in snap.docs) {
            try {
              final job = JobRequest.fromFirestore(doc);
              if (job.status != 'completed') {
                jobs.add(job);
              }
            } catch (e) {
              debugPrint('[JobService] Error parsing ongoing job ${doc.id}: $e');
            }
          }
          debugPrint('[JobService] streamOngoingJobs result: ${jobs.length}');
          return jobs;
        })
        .handleError((error) {
          debugPrint('[JobService] streamOngoingJobs ERROR: $error');
        });
  }

  /// Stream jobs from the dedicated "completed jobs" collection.
  Stream<List<JobRequest>> streamCompletedJobs() {
    final wid = _workerId;
    if (wid == null) {
      debugPrint('[JobService] No worker ID available for streamCompletedJobs');
      return Stream.value(<JobRequest>[]);
    }

    debugPrint('[JobService] Starting streamCompletedJobs for worker: $wid');

    return _firestore
        .collection('completed jobs')
        .where('workerId', isEqualTo: wid)
        .snapshots()
        .map((snap) {
          debugPrint('[JobService] streamCompletedJobs snapshot: ${snap.docs.length}');
          final jobs = <JobRequest>[];
          for (var doc in snap.docs) {
            try {
              jobs.add(JobRequest.fromFirestore(doc));
            } catch (e) {
              debugPrint('[JobService] Error parsing completed job ${doc.id}: $e');
            }
          }
          
          // Sort client-side: descending by completedAt
          jobs.sort((a, b) {
            final dateA = a.completedAt ?? a.createdAt;
            final dateB = b.completedAt ?? b.createdAt;
            return dateB.compareTo(dateA);
          });
          
          debugPrint('[JobService] streamCompletedJobs result: ${jobs.length}');
          return jobs;
        })
        .handleError((error) {
          debugPrint('[JobService] streamCompletedJobs ERROR: $error');
        });
  }

  // ─── Write Operations ────────────────────────────────────────────────────────

  /// Worker accepts a job: stamps workerId and changes status.
  /// Ensures customer data is properly fetched and preserved.
  Future<void> acceptJob(String jobId) async {
    final wid = _workerId;
    if (wid == null) return;

    debugPrint('[JobService] Worker $wid accepting job $jobId');

    // Fetch worker's phone number, bio, name, and avatar from their profile
    String? workerPhone;
    String? workerBio;
    String? workerName;
    String? workerAvatarUrl;
    try {
      final workerDoc = await _firestore.collection('workers').doc(wid).get();
      if (workerDoc.exists) {
        workerPhone = workerDoc.data()?['phoneNumber'];
        workerBio = workerDoc.data()?['bio'];
        workerName = workerDoc.data()?['name'];
        workerAvatarUrl = workerDoc.data()?['profileUrl'];
      }
    } catch (e) {
      debugPrint('[JobService] Error fetching worker data: $e');
    }

    // ✅ Fetch and validate customer data
    final jobDoc = await _firestore.collection('jobRequests').doc(jobId).get();
    if (!jobDoc.exists) {
      debugPrint('[JobService] Job $jobId not found');
      return;
    }

    final jobData = jobDoc.data() ?? {};
    final isReleasedScheduledJob = (jobData['fromScheduledJobId']?.toString().trim().isNotEmpty ?? false);
    final customerId = jobData['customerId'] ?? '';
    var customerName = jobData['customerName'] ?? '';
    var customerPhone = jobData['customerPhone'];

    // Re-fetch customer info from customers collection for accuracy
    if (customerId.isNotEmpty) {
      try {
        final customerDoc = await _firestore.collection('customers').doc(customerId).get();
        if (customerDoc.exists) {
          final customerData = customerDoc.data() ?? {};
          final freshName = customerData['name'] ?? customerData['fullName'];
          final freshPhone = customerData['phoneNumber'] ?? customerData['phone'];

          if (freshName != null && freshName.toString().isNotEmpty) {
            customerName = freshName.toString();
          }
          if (freshPhone != null) {
            customerPhone = freshPhone;
          }

          debugPrint('[JobService] Customer info validated - $customerName ($customerId)');
        } else {
          debugPrint('[JobService] Customer $customerId not found in collection');
        }
      } catch (e) {
        debugPrint('[JobService] Error validating customer data: $e');
      }
    }

    final updateData = {
      'status': isReleasedScheduledJob ? 'customerConfirmed' : 'workerFound',
      'workerId': wid,
      'workerAcceptedAt': FieldValue.serverTimestamp(),
      // Ensure customer data is correct
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
    };

    // Add worker name and avatar for customer UI
    if (workerName != null && workerName.isNotEmpty) {
      updateData['workerName'] = workerName;
    }
    if (workerAvatarUrl != null && workerAvatarUrl.isNotEmpty) {
      updateData['workerAvatarUrl'] = workerAvatarUrl;
    }

    // Add worker phone if available
    if (workerPhone != null && workerPhone.isNotEmpty) {
      updateData['workerPhone'] = workerPhone;
    }

    // Add worker bio if available
    if (workerBio != null && workerBio.isNotEmpty) {
      updateData['workerBio'] = workerBio;
    }

    if (isReleasedScheduledJob) {
      updateData['customerConfirmedAt'] = FieldValue.serverTimestamp();
    }

    await _firestore.collection('jobRequests').doc(jobId).update(updateData);

    debugPrint('[JobService] Job $jobId accepted by worker $wid');

    await _firestore.collection('workers').doc(wid).update({
      'isAvailable': false,
      'activeJobId': jobId,
    });
  }

  /// Worker declines a job: adds workerId to rejectedWorkerIds array.
  Future<void> declineJob(String jobId) async {
    final wid = _workerId;
    if (wid == null) return;

    await _firestore.collection('jobRequests').doc(jobId).update({
      'rejectedWorkerIds': FieldValue.arrayUnion([wid]),
    });
  }

  /// Worker completes a job: stamps completion timestamp and moves to "completed jobs" collection.
  /// Ensures customer data is preserved and validated from Firestore.
  Future<void> completeJob(String jobId) async {
    final wid = _workerId;
    if (wid == null) return;

    final docRef = _firestore.collection('jobRequests').doc(jobId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) {
      debugPrint('[JobService] Job $jobId not found in jobRequests');
      return;
    }

    final data = snapshot.data() ?? {};
    debugPrint('[JobService] Completing job $jobId for worker $wid');

    // Extract customer info and validate it
    final customerId = data['customerId'] ?? '';
    var customerName = data['customerName'] ?? '';

    // ✅ CRITICAL: Re-fetch customer name from customers collection to ensure accuracy
    if (customerId.isNotEmpty) {
      try {
        final customerDoc = await _firestore.collection('customers').doc(customerId).get();
        if (customerDoc.exists) {
          final customerData = customerDoc.data() ?? {};
          // Use updated customer name from customers collection
          final freshName = customerData['name'] ?? customerData['fullName'];
          if (freshName != null && freshName.toString().isNotEmpty) {
            customerName = freshName.toString();
            debugPrint('[JobService] Updated customer name from collection: $customerName');
          }
        } else {
          debugPrint('[JobService] Customer $customerId not found in collection');
        }
      } catch (e) {
        debugPrint('[JobService] Error fetching customer $customerId: $e');
        // Continue with existing customerName value
      }
    }

    final now = FieldValue.serverTimestamp();

    // 1. Update the original request status
    await docRef.update({
      'status': 'completed',
      'completedAt': now,
    });

    // 2. Create a record in the dedicated "completed jobs" collection
    // Ensure customer data is preserved with latest info
    final completedJobData = {
      ...data,
      'status': 'completed',
      'completedAt': now,
      'workerId': wid,
      'customerId': customerId, // Ensure customerId is set
      'customerName': customerName, // Use validated customer name
    };

    await _firestore.collection('completed jobs').doc(jobId).set(
      completedJobData,
      SetOptions(merge: true),
    );

    debugPrint('[JobService] Job $jobId completed - Customer: $customerName ($customerId)');

    // 3. Update worker earnings using workerEarnings field (the actual worker payout)
    // Falls back to fare if workerEarnings is not set
    final workerEarnings = (data['workerEarnings'] as num?)?.toDouble()
        ?? (data['fare'] as num?)?.toDouble()
        ?? 0.0;
    try {
      await _firestore.collection('workers').doc(wid).update({
        'activeJobId': null,
        'earnings': FieldValue.increment(workerEarnings),
      });
      debugPrint('[JobService] Worker earnings updated: +\$$workerEarnings (Job ID: $jobId)');
    } catch (e) {
      debugPrint('[JobService] Error updating worker earnings: $e');
      // Still update activeJobId even if earnings update fails
      await _firestore.collection('workers').doc(wid).update({
        'activeJobId': null,
      });
    }

    debugPrint('[JobService] Job $jobId moved to completed jobs collection');
  }

  /// Deletes all completed jobs from the dedicated collection.
  Future<void> clearCompletedJobs() async {
    final wid = _workerId;
    if (wid == null) return;

    final snapshot = await _firestore
        .collection('completed jobs')
        .where('workerId', isEqualTo: wid)
        .get();

    final batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    debugPrint('JobService: Cleared all jobs from completed jobs collection');
  }

  /// Deletes all pending or ongoing jobs for the current worker (cleanup).
  Future<void> clearOngoingJobs() async {
    final wid = _workerId;
    if (wid == null) return;

    final snapshot = await _firestore
        .collection('jobRequests')
        .where('workerId', isEqualTo: wid)
        .where('status', whereIn: ['workerFound', 'customerConfirmed', 'inProgress', 'arrived', 'workStarted'])
        .get();

    final batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
    
    // Also reset worker status
    await _firestore.collection('workers').doc(wid).update({
      'isAvailable': true,
      'activeJobId': FieldValue.delete(),
    });
  }
}
