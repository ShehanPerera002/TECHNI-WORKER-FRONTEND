import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  static final LocationService instance = LocationService._();
  LocationService._();

  StreamSubscription<Position>? _positionSub;

  Future<void> startSharing() async {
    // Request permissions
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    final workerId = FirebaseAuth.instance.currentUser?.uid;
    if (workerId == null) return;

    // Set online status
    await FirebaseFirestore.instance.collection('workers').doc(workerId).set({
      'isOnline': true,
    }, SetOptions(merge: true));

    late LocationSettings locationSettings;

    if (defaultTargetPlatform == TargetPlatform.android) {
      locationSettings = AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3000, // update every 3 kilometers
        forceLocationManager: true,
        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: "Location is streaming in the background",
          notificationTitle: "TECHNI Background Service",
          enableWakeLock: true,
        ),
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS) {
      locationSettings = AppleSettings(
        accuracy: LocationAccuracy.high,
        activityType: ActivityType.fitness,
        distanceFilter: 3000,
        pauseLocationUpdatesAutomatically: false,
        allowBackgroundLocationUpdates: true,
      );
    } else {
      locationSettings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 3000,
      );
    }

    // Start streaming location
    _positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position pos) {
          FirebaseFirestore.instance.collection('workers').doc(workerId).set({
            'lat': pos.latitude,
            'lng': pos.longitude,
            'isOnline': true,
          }, SetOptions(merge: true));
        });
  }

  Future<void> stopSharing() async {
    await _positionSub?.cancel();
    _positionSub = null;

    final workerId = FirebaseAuth.instance.currentUser?.uid;
    if (workerId == null) return;

    await FirebaseFirestore.instance.collection('workers').doc(workerId).set({
      'isOnline': false,
    }, SetOptions(merge: true));
  }
}
