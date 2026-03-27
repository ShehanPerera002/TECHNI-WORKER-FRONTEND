import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../models/job_request.dart';

class WorkerProfileScreen extends StatefulWidget {
  const WorkerProfileScreen({super.key});

  @override
  State<WorkerProfileScreen> createState() => _WorkerProfileScreenState();
}

class _WorkerProfileScreenState extends State<WorkerProfileScreen> {
  TextEditingController? _bioController;
  bool _isEditingBio = false;
  bool _isSavingBio = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _saveBio() async {
    if (_bioController == null) return;
    
    setState(() => _isSavingBio = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // ✅ Update bio directly in Firestore (no backend API needed)
      await FirebaseFirestore.instance
          .collection('workers')
          .doc(user.uid)
          .update({
            'bio': _bioController!.text,
          }).timeout(const Duration(seconds: 5));

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bio saved successfully')),
      );

      // StreamBuilder auto-refreshes from Firestore - just close edit mode
      if (mounted) {
        setState(() {
          _isEditingBio = false;
          _bioController?.dispose();
          _bioController = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving bio: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingBio = false);
    }
  }

  @override
  void dispose() {
    _bioController?.dispose();
    super.dispose();
  }

  ImageProvider? _profileImageProvider(String? imagePath) {
    if (imagePath == null || imagePath.trim().isEmpty) return null;
    final value = imagePath.trim();
    if (value.startsWith('http')) return NetworkImage(value);
    final file = File(value);
    if (file.existsSync()) return FileImage(file);
    return null;
  }

  Widget _infoTile({required String label, required String value}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to log out. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final workerId = user?.uid;

    if (workerId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Profile')),
        body: const Center(child: Text('Please log in')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'My Profile',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('workers')
            .doc(workerId)
            .snapshots(),
        builder: (context, profileSnapshot) {
          if (profileSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!profileSnapshot.hasData || !profileSnapshot.data!.exists) {
            return const Center(child: Text('Profile not found'));
          }
          final profileData = profileSnapshot.data!.data() as Map<String, dynamic>?;
          if (profileData == null) {
            return const Center(child: Text('Profile not found'));
          }

          final image = _profileImageProvider(profileData['profileUrl'] as String?);
          final name = profileData['name'] ?? 'Worker';
          final phone = profileData['phoneNumber'] ?? '-';
          final category = profileData['category'] ?? 'Professional';
          final averageRating = (profileData['averageRating'] as num?)?.toDouble();
          final ratingCount = (profileData['ratingCount'] as num?)?.toInt() ?? 0;
          final rating = averageRating != null
              ? '${averageRating.toStringAsFixed(1)} ($ratingCount reviews)'
              : 'No ratings yet';
          final earnings = (profileData['earnings'] as num?)?.toDouble() ?? 0.0;

          // Nested StreamBuilder for ongoing jobs (from jobRequests)
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('jobRequests')
                .where('workerId', isEqualTo: workerId)
                .snapshots(),
            builder: (context, ongoingSnapshot) {
              // Nested StreamBuilder for completed jobs
              return StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('completed jobs')
                    .where('workerId', isEqualTo: workerId)
                    .snapshots(),
                builder: (context, completedSnapshot) {
                  if (completedSnapshot.hasError) {
                    debugPrint('[WorkerProfile] Completed jobs error: ${completedSnapshot.error}');
                  }
                  final ongoingJobs = <JobRequest>[];
                  if (ongoingSnapshot.hasData) {
                    for (var doc in ongoingSnapshot.data!.docs) {
                      try {
                        final job = JobRequest.fromFirestore(doc);
                        if (job.status != 'completed') {
                          ongoingJobs.add(job);
                        }
                      } catch (e) {
                        debugPrint('[WorkerProfile] Error parsing ongoing job: $e');
                      }
                    }
                  }

                  final completedJobs = <JobRequest>[];
                  if (completedSnapshot.hasData) {
                    debugPrint('[WorkerProfile] Completed docs count: ${completedSnapshot.data!.docs.length}');
                    for (var doc in completedSnapshot.data!.docs) {
                      try {
                        completedJobs.add(JobRequest.fromFirestore(doc));
                      } catch (e) {
                        debugPrint('[WorkerProfile] Error parsing completed job ${doc.id}: $e');
                      }
                    }
                  }

                  // Sort by date
                  completedJobs.sort((a, b) {
                    final dateA = a.completedAt ?? a.createdAt;
                    final dateB = b.completedAt ?? b.createdAt;
                    return dateB.compareTo(dateA);
                  });

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Profile Header
                        Center(
                          child: CircleAvatar(
                            radius: 58,
                            backgroundColor: Colors.blue.shade50,
                            backgroundImage: image,
                            child: image == null
                                ? const Icon(Icons.person, size: 58, color: Colors.blue)
                                : null,
                          ),
                        ),
                        const SizedBox(height: 28),
                        _infoTile(label: 'Full Name', value: name),
                        _infoTile(label: 'Phone Number', value: phone),
                        _infoTile(label: 'Service Category', value: category),
                        _infoTile(label: 'Average Rating', value: '⭐ $rating'),
                        const SizedBox(height: 20),

                        // Earnings Display
                        const Text(
                          'Your Earnings',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total Earned',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Color(0xFF6B7280),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                'Rs. ${earnings.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF059669),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Bio Section
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 14),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'About Me',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF6B7280),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (!_isEditingBio)
                                    GestureDetector(
                                      onTap: () {
                                        _bioController = TextEditingController(
                                          text: profileData['bio'] ?? '',
                                        );
                                        setState(() => _isEditingBio = true);
                                      },
                                      child: const Text(
                                        'Edit',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF2563EB),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              if (!_isEditingBio)
                                Text(
                                  profileData['bio'] ?? 'No bio added yet',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: (profileData['bio'] ?? '').isEmpty
                                        ? Colors.grey
                                        : Colors.black,
                                  ),
                                )
                              else
                                Column(
                                  children: [
                                    TextField(
                                      controller: _bioController,
                                      maxLines: 3,
                                      maxLength: 500,
                                      decoration: InputDecoration(
                                        hintText: 'Tell customers about yourself...',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        TextButton(
                                          onPressed: () {
                                            setState(() {
                                              _isEditingBio = false;
                                              _bioController?.dispose();
                                              _bioController = null;
                                            });
                                          },
                                          child: const Text('Cancel'),
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton(
                                          onPressed: _isSavingBio ? null : _saveBio,
                                          child: _isSavingBio
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : const Text('Save'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Jobs Section
                        const Text(
                          'Your Jobs',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Column(
                            children: [
                              // Ongoing Jobs Title
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Ongoing (${ongoingJobs.length})',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (ongoingJobs.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text('No ongoing jobs'),
                                )
                              else
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  itemCount: ongoingJobs.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (_, idx) => _jobCard(ongoingJobs[idx]),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Completed Jobs
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: Column(
                            children: [
                              // Completed Jobs Title
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Completed (${completedJobs.length})',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (completedJobs.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: Text('No completed jobs'),
                                )
                              else
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  itemCount: completedJobs.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (_, idx) => _jobCard(completedJobs[idx]),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Logout Button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: OutlinedButton(
                            onPressed: _logout,
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF2563EB)),
                              foregroundColor: const Color(0xFF2563EB),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Log Out',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _jobCard(JobRequest job) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  job.jobType,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'Rs. ${(job.fare ?? 0).toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF059669),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Customer: ${job.customerName}',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6B7280),
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'Status: ${job.status}',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }
}
