import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import '../models/professional.dart';

class FindProfessionalScreen extends StatefulWidget {
  final LatLng customerLocation; // Assume customer's current location is passed
  
  const FindProfessionalScreen({
    Key? key,
    required this.customerLocation,
  }) : super(key: key);

  @override
  State<FindProfessionalScreen> createState() => _FindProfessionalScreenState();
}

class _FindProfessionalScreenState extends State<FindProfessionalScreen> {
  // Map controller to adjust camera if needed
  GoogleMapController? _mapController;
  
  // To keep track of the Firestore stream to cancel it neatly on dispose
  StreamSubscription<QuerySnapshot>? _workersSubscription;
  
  // Set of markers to display on the map
  Set<Marker> _markers = {};

  // Maximum search radius in meters (10 km)
  static const double _maxSearchRadius = 10000;

  @override
  void initState() {
    super.initState();
    _startLocatingNearbyWorkers();
  }

  /// Sets up a real-time stream from Firestore and filters workers by distance
  void _startLocatingNearbyWorkers() {
    // Query Firestore for workers where isOnline == true
    _workersSubscription = FirebaseFirestore.instance
        .collection('workers')
        .where('isOnline', isEqualTo: true)
        .snapshots()
        .listen((snapshot) {
      
      final Set<Marker> newMarkers = {};
      
      // Always show the customer's location
      newMarkers.add(
        Marker(
          markerId: const MarkerId('customer_loc'),
          position: widget.customerLocation,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
          infoWindow: const InfoWindow(title: 'You are here'),
        ),
      );

      // Iterate through the real-time snapshot of online workers
      for (var doc in snapshot.docs) {
        try {
          final data = doc.data();
          
          // Parse the worker using the model
          final professional = Professional.fromFirestore(doc.id, data);
          
          if (professional.currentLocation != null && !professional.doNotDisturb) {
            // Calculate distance between customer and the worker in meters using geolocator distanceBetween()
            final distanceInMeters = Geolocator.distanceBetween(
              widget.customerLocation.latitude,
              widget.customerLocation.longitude,
              professional.currentLocation!.latitude,
              professional.currentLocation!.longitude,
            );

            // Filter out workers outside the 10km radius
            if (distanceInMeters <= _maxSearchRadius) {
              
              // Worker is within 10km, add their marker to the map
              newMarkers.add(
                Marker(
                  markerId: MarkerId(professional.id),
                  position: professional.currentLocation!,
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                  infoWindow: InfoWindow(
                    title: professional.name,
                    snippet: '${professional.specialization} - ${(distanceInMeters / 1000).toStringAsFixed(1)} km away',
                  ),
                )
              );
            }
          }
        } catch (e) {
          debugPrint('Error parsing worker doc: $e');
        }
      }

      // Update the state to refresh the map UI with new markers
      setState(() {
        _markers = newMarkers;
      });
    });
  }

  @override
  void dispose() {
    // Cancel all streams when screen is disposed
    _workersSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby Professionals'),
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: widget.customerLocation,
          zoom: 13,
        ),
        onMapCreated: (controller) {
          _mapController = controller;
        },
        markers: _markers,
        myLocationEnabled: true, // Also activates the native location dot if permissions exist
        myLocationButtonEnabled: true,
      ),
    );
  }
}
