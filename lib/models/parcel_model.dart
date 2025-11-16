// // lib/models/parcel_model.dart

// enum ParcelStatus {
//   queued,        // "Packages to be delivered"
//   inTransit,     // "Package being delivered"
//   delivered,     // "Package delivered"
// }

// ParcelStatus parcelStatusFromString(String s) {
//   switch (s) {
//     case 'queued':
//       return ParcelStatus.queued;
//     case 'inTransit':
//       return ParcelStatus.inTransit;
//     case 'delivered':
//       return ParcelStatus.delivered;
//     default:
//       return ParcelStatus.queued;
//   }
// }

// String parcelStatusToString(ParcelStatus status) {
//   switch (status) {
//     case ParcelStatus.queued:
//       return 'queued';
//     case ParcelStatus.inTransit:
//       return 'inTransit';
//     case ParcelStatus.delivered:
//       return 'delivered';
//   }
// }

// class Parcel {
//   final String id;         // Firestore doc ID
//   final String rfidTag;
//   final ParcelStatus status;
//   final DateTime createdAt;
//   final DateTime updatedAt;

//   Parcel({
//     required this.id,
//     required this.rfidTag,
//     required this.status,
//     required this.createdAt,
//     required this.updatedAt,
//   });

//   /// Create a modified copy while keeping the original immutable.
//   Parcel copyWith({
//     String? id,
//     String? rfidTag,
//     ParcelStatus? status,
//     DateTime? createdAt,
//     DateTime? updatedAt,
//   }) {
//     return Parcel(
//       id: id ?? this.id,
//       rfidTag: rfidTag ?? this.rfidTag,
//       status: status ?? this.status,
//       createdAt: createdAt ?? this.createdAt,
//       updatedAt: updatedAt ?? this.updatedAt,
//     );
//   }

//   // we assume Firestore is storing ISO-8601 strings for times
//   factory Parcel.fromJson(String id, Map<String, dynamic> json) {
//     DateTime parseDate(dynamic v) {
//       if (v is DateTime) return v;
//       if (v is String) return DateTime.parse(v);
//       // last-resort fallback; prevents crashes if field is missing while testing
//       return DateTime.now();
//     }

//     return Parcel(
//       id: id,
//       rfidTag: json['rfidTag'] as String,
//       status: parcelStatusFromString(json['status'] as String),
//       createdAt: parseDate(json['createdAt']),
//       updatedAt: parseDate(json['updatedAt']),
//     );
//   }

//   Map<String, dynamic> toJson() {
//     return {
//       'rfidTag': rfidTag,
//       'status': parcelStatusToString(status),
//       'createdAt': createdAt.toIso8601String(),
//       'updatedAt': updatedAt.toIso8601String(),
//     };
//   }
// }
