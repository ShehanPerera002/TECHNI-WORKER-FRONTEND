import 'package:cloud_firestore/cloud_firestore.dart';

class JobRequest {
  final String id;
  final String customerId;
  final String customerName;
  final String? customerPhone;
  final String? workerId;
  final String status;
  final String jobType;
  final String? description;
  final String? issueImageUrl;
  final double customerLat;
  final double customerLng;
  final GeoPoint? customerLocation;
  final double? workerLat;
  final double? workerLng;
  final List<String> notifiedWorkerIds;
  final List<String> rejectedWorkerIds;
  final double? fare;
  final int? durationSeconds;
  final DateTime createdAt;
  final DateTime? workerAcceptedAt;
  final DateTime? customerConfirmedAt;
  final DateTime? jobStartedAt;
  final DateTime? completedAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final int? rating;
  final String? review;
  final double? distanceKm;
  final double? distanceKmEstimate;
  final String? distanceTextEstimate;
  final String? etaTextEstimate;
  final double? customerRating;

  JobRequest({
    required this.id,
    required this.customerId,
    required this.customerName,
    this.customerPhone,
    this.workerId,
    required this.status,
    required this.jobType,
    this.description,
    this.issueImageUrl,
    required this.customerLat,
    required this.customerLng,
    this.customerLocation,
    this.workerLat,
    this.workerLng,
    this.notifiedWorkerIds = const [],
    this.rejectedWorkerIds = const [],
    this.fare,
    this.durationSeconds,
    required this.createdAt,
    this.workerAcceptedAt,
    this.customerConfirmedAt,
    this.jobStartedAt,
    this.completedAt,
    this.cancelledAt,
    this.cancelReason,
    this.rating,
    this.review,
    this.distanceKm,
    this.distanceKmEstimate,
    this.distanceTextEstimate,
    this.etaTextEstimate,
    this.customerRating,
  });

  factory JobRequest.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    
    DateTime parseTimestamp(dynamic field) {
      if (field is Timestamp) return field.toDate();
      if (field is String) return DateTime.tryParse(field) ?? DateTime.now();
      return DateTime.now();
    }
    
    DateTime? parseNullableTimestamp(dynamic field) {
      if (field == null) return null;
      if (field is Timestamp) return field.toDate();
      if (field is String) return DateTime.tryParse(field);
      return null;
    }

    // Handle GeoPoints for location
    double cLat = 0.0;
    double cLng = 0.0;
    GeoPoint? customerLocationGeo;
    double? wLat;
    double? wLng;

    if (data['customerLocation'] is GeoPoint) {
      final geo = data['customerLocation'] as GeoPoint;
      cLat = geo.latitude;
      cLng = geo.longitude;
      customerLocationGeo = geo;
    }

    if (data['workerLocation'] is GeoPoint) {
      final geo = data['workerLocation'] as GeoPoint;
      wLat = geo.latitude;
      wLng = geo.longitude;
    }

    final resolvedCustomerName = (data['customerName'] ??
            data['customer_name'] ??
            data['customerFullName'] ??
            data['name'])
        ?.toString()
        .trim();

    return JobRequest(
      id: doc.id,
      customerId: data['customerId'] ?? '',
      customerName: (resolvedCustomerName == null || resolvedCustomerName.isEmpty)
          ? 'Customer'
          : resolvedCustomerName,
      customerPhone: data['customerPhone'],
      workerId: data['workerId'],
      status: data['status'] ?? 'searching',
      jobType: data['jobType'] ?? '',
      description: data['description'],
      issueImageUrl: data['issueImageUrl']?.toString(),
      customerLat: cLat,
      customerLng: cLng,
      customerLocation: customerLocationGeo,
      workerLat: wLat,
      workerLng: wLng,
      notifiedWorkerIds: List<String>.from(data['notifiedWorkerIds'] ?? []),
      rejectedWorkerIds: List<String>.from(data['rejectedWorkerIds'] ?? []),
      fare: (data['fare'] as num?)?.toDouble(),
      durationSeconds: data['durationSeconds'] as int?,
      createdAt: parseTimestamp(data['createdAt']),
      workerAcceptedAt: parseNullableTimestamp(data['workerAcceptedAt']),
      customerConfirmedAt: parseNullableTimestamp(data['customerConfirmedAt']),
      jobStartedAt: parseNullableTimestamp(data['jobStartedAt']),
      completedAt: parseNullableTimestamp(data['completedAt']),
      cancelledAt: parseNullableTimestamp(data['cancelledAt']),
      cancelReason: data['cancelReason'],
      rating: data['rating'] as int?,
      review: data['review'],
      distanceKm: data['distanceKm'] is String
          ? double.tryParse(data['distanceKm'] as String)
          : (data['distanceKm'] as num?)?.toDouble(),
      distanceKmEstimate: (data['distanceKmEstimate'] as num?)?.toDouble(),
      distanceTextEstimate: data['distanceTextEstimate']?.toString(),
      etaTextEstimate: data['etaTextEstimate']?.toString(),
      customerRating: (data['customerRating'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'customerId': customerId, // ✅ MUST be from customers collection ID
      'customerName': customerName, // ✅ MUST be latest from customers collection
      'customerPhone': customerPhone,
      'workerId': workerId,
      'status': status,
      'jobType': jobType,
      'description': description,
      'issueImageUrl': issueImageUrl,
      'customerLocation': GeoPoint(customerLat, customerLng),
      if (workerLat != null && workerLng != null)
        'workerLocation': GeoPoint(workerLat!, workerLng!),
      'notifiedWorkerIds': notifiedWorkerIds,
      'rejectedWorkerIds': rejectedWorkerIds,
      'fare': fare,
      'durationSeconds': durationSeconds,
      'createdAt': Timestamp.fromDate(createdAt),
      'workerAcceptedAt': workerAcceptedAt != null ? Timestamp.fromDate(workerAcceptedAt!) : null,
      'customerConfirmedAt': customerConfirmedAt != null ? Timestamp.fromDate(customerConfirmedAt!) : null,
      'jobStartedAt': jobStartedAt != null ? Timestamp.fromDate(jobStartedAt!) : null,
      'completedAt': completedAt != null ? Timestamp.fromDate(completedAt!) : null,
      'cancelledAt': cancelledAt != null ? Timestamp.fromDate(cancelledAt!) : null,
      'cancelReason': cancelReason,
      'rating': rating,
      'review': review,
      'distanceKm': distanceKm,
      'distanceKmEstimate': distanceKmEstimate,
      'distanceTextEstimate': distanceTextEstimate,
      'etaTextEstimate': etaTextEstimate,
      'customerRating': customerRating,
    };
  }
}
