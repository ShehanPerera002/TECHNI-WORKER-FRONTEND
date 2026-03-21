import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/job_request.dart';

class JobService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Returns the current worker's UID, or null if not logged in.
  String? get _workerId => FirebaseAuth.instance.currentUser?.uid;

  // ─── Real-time Streams ──────────────────────────────────────────────────────

  /// Stream all "pending" jobs (new job requests where this worker is notified and status is searching).
  Stream<List<JobRequest>> streamNewJobs() {
    final wid = _workerId;
    if (wid == null) return const Stream.empty();

    return _firestore
        .collection('jobRequests')
        .where('notifiedWorkerIds', arrayContains: wid)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => JobRequest.fromFirestore(doc))
            .where((req) => req.status == 'searching' && !req.rejectedWorkerIds.contains(wid))
            .toList());
  }

  /// Stream jobs that have been accepted by the worker but not yet confirmed by the customer.
  Stream<List<JobRequest>> streamScheduledJobs() {
    final wid = _workerId;
    if (wid == null) return const Stream.empty();

    return _firestore
        .collection('jobRequests')
        .where('workerId', isEqualTo: wid)
        .where('status', whereIn: ['workerFound', 'customerConfirmed'])
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => JobRequest.fromFirestore(doc))
            .toList());
  }

  /// Stream jobs that are currently active (navigating, arrived, or work in progress).
  Stream<List<JobRequest>> streamOngoingJobs() {
    final wid = _workerId;
    if (wid == null) return const Stream.empty();

    return _firestore
        .collection('jobRequests')
        .where('workerId', isEqualTo: wid)
        .where('status', whereIn: ['inProgress', 'arrived', 'workStarted'])
        .snapshots()
        .map((snap) {
          // Additional safety: ensure we only show very recent or truly active jobs
          return snap.docs
            .map((doc) => JobRequest.fromFirestore(doc))
            .where((job) {
              // If status is 'completed' somehow in this stream, skip it
              return job.status != 'completed';
            })
            .toList();
        });
  }

  /// Stream jobs from the dedicated "completed jobs" collection.
  Stream<List<JobRequest>> streamCompletedJobs() {
    final wid = _workerId;
    if (wid == null) return const Stream.empty();

    // We remove the server-side orderBy to avoid requiring a composite index.
    // Instead, we sort the results in memory (client-side).
    return _firestore
        .collection('completed jobs')
        .where('workerId', isEqualTo: wid)
        .snapshots()
        .map((snap) {
          final jobs = snap.docs
            .map((doc) => JobRequest.fromFirestore(doc))
            .toList();
          
          // Sort client-side: descending by completedAt
          jobs.sort((a, b) {
            final dateA = a.completedAt ?? a.createdAt;
            final dateB = b.completedAt ?? b.createdAt;
            return dateB.compareTo(dateA);
          });
          
          return jobs;
        });
  }

  // ─── Write Operations ────────────────────────────────────────────────────────

  /// Worker accepts a job: stamps workerId and changes status.
  Future<void> acceptJob(String jobId) async {
    final wid = _workerId;
    if (wid == null) return;

    await _firestore.collection('jobRequests').doc(jobId).update({
      'status': 'workerFound',
      'workerId': wid,
      'workerAcceptedAt': FieldValue.serverTimestamp(),
    });
    
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
  Future<void> completeJob(String jobId) async {
    final wid = _workerId;
    if (wid == null) return;

    final docRef = _firestore.collection('jobRequests').doc(jobId);
    final snapshot = await docRef.get();
    if (!snapshot.exists) return;

    final data = snapshot.data() ?? {};
    final now = FieldValue.serverTimestamp();

    // 1. Update the original request status
    await docRef.update({
      'status': 'completed',
      'completedAt': now,
    });

    // 2. Create a record in the dedicated "completed jobs" collection
    // We merge the existing data with the completion details
    await _firestore.collection('completed jobs').doc(jobId).set({
      ...data,
      'status': 'completed',
      'completedAt': now,
      'workerId': wid, // Ensure workerId is set correctly
    }, SetOptions(merge: true));

    // 3. Clear from worker's activeJobId if any
    await _firestore.collection('workers').doc(wid).update({
      'activeJobId': null,
    });

    debugPrint('JobService: Job $jobId moved to completed jobs collection');
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
