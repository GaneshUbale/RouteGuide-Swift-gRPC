//
//  RouteGuideService.swift
//  RouteGuide
//
//  Created by Ganesh Ubale on 20/11/26.
//

import Foundation
import GRPCCore
import Synchronization

struct RouteGuideService: Routeguide_RouteGuide.SimpleServiceProtocol {
    
    private let features: [Routeguide_Feature]
    /// Notes that clients record.
    private let receivedNotes: Notes
    
    
    /// A thread-safe store for notes that clients send.
    private final class Notes: Sendable {
        private let notes: Mutex<[Routeguide_RouteNote]>
        
        
        init() {
            self.notes = Mutex([])
        }
        
        
        /// Records a note and returns the other notes it has already recorded at the same location.
        ///
        /// - Parameter receivedNote: A note to record.
        /// - Returns: The other notes it has already recorded at the same location.
        func recordNote(_ receivedNote: Routeguide_RouteNote) -> [Routeguide_RouteNote] {
            return self.notes.withLock { notes in
                var notesFromSameLocation: [Routeguide_RouteNote] = []
                for note in notes {
                    if note.location == receivedNote.location {
                        notesFromSameLocation.append(note)
                    }
                }
                notes.append(receivedNote)
                return notesFromSameLocation
            }
        }
    }
    
    
    /// Creates a new route guide service.
    /// - Parameter features: Known features.
    init(features: [Routeguide_Feature]) {
        self.features = features
        self.receivedNotes = Notes()
    }
    
    private func findFeature(latitude:Int32 , longitude: Int32) -> Routeguide_Feature? {
        features.first { $0.location.latitude == latitude && $0.location.longitude == longitude
        }
    }
    
    func getFeature(
        request: Routeguide_Point,
        context: GRPCCore.ServerContext
    ) async throws -> Routeguide_Feature {
        let feature = findFeature(latitude: request.latitude, longitude: request.longitude)
        
        if let feature {
            return feature
        } else {
            let unknownFeature = Routeguide_Feature.with {
                $0.name = ""
                $0.location = .with ({
                    $0.latitude = request.latitude
                    $0.longitude = request.longitude
                })
            }
            return unknownFeature
        }
    }
    
    func listFeatures(
        request: Routeguide_Rectangle,
        response: GRPCCore.RPCWriter<Routeguide_Feature>,
        context: GRPCCore.ServerContext
    ) async throws {
        for feature in features {
            if !feature.name.isEmpty, feature.isContained(by: request) {
                try await response.write(feature)
            }
        }
    }
    
    func recordRoute(
        request: GRPCCore.RPCAsyncSequence<Routeguide_Point, any Error>,
        context: GRPCCore.ServerContext
    ) async throws -> Routeguide_RouteSummery {
        let startTime = ContinuousClock.now
        var pointsVisited: Int32 = 0
        var featureVisited: Int32 = 0
        var distanceTraveled = 0.0
        var previousPoint: Routeguide_Point? = nil
        
        for try await point in request {
            pointsVisited += 1
            
            if findFeature(latitude: point.latitude, longitude: point.longitude) != nil {
                featureVisited += 1
            }
            
            if let previousPoint {
                distanceTraveled += greatCircleDistance(from: previousPoint, to: point)
            }
            
        }
        
        let duration = startTime.duration(to: .now)
        return .with {
            $0.pointCount = pointsVisited
            $0.featureCount = featureVisited
            $0.distance = Int32(distanceTraveled)
            $0.elapsedTime = Int32(duration.components.seconds)
        }
    }
    
    func routeChat(
        request: GRPCCore.RPCAsyncSequence<Routeguide_RouteNote, any Error>,
        response: GRPCCore.RPCWriter<Routeguide_RouteNote>, context: GRPCCore.ServerContext
    ) async throws {
        for try await note in request {
          let notes = self.receivedNotes.recordNote(note)
          try await response.write(contentsOf: notes)
        }
    }
}


extension Routeguide_Feature {
  func isContained(by rectangle: Routeguide_Rectangle) -> Bool {
    return rectangle.lo.latitude <= self.location.latitude
      && self.location.latitude <= rectangle.hi.latitude
      && rectangle.lo.longitude <= self.location.longitude
      && self.location.longitude <= rectangle.hi.longitude
  }
}


private func greatCircleDistance(
  from point1: Routeguide_Point,
  to point2: Routeguide_Point
) -> Double {
  // See https://en.wikipedia.org/wiki/Great-circle_distance
  //
  // Let λ1 (lambda1) and φ1 (phi1) be the longitude and latitude of point 1.
  // Let λ2 (lambda2) and φ2 (phi2) be the longitude and latitude of point 2.
  //
  // Let Δλ = λ2 - λ1, and Δφ = φ2 - φ1.
  //
  // The central angle between them, σc (sigmaC) can be computed as:
  //
  //   σc = 2 ⨯ sqrt(sin²(Δφ/2) + cos(φ1) ⨯ cos(φ2) ⨯ sin²(Δλ/2))
  //
  // The unit distance (d) between point1 and point2 can then be computed as:
  //
  //   d = 2 ⨯ atan(sqrt(σc), sqrt(1 - σc))


  let lambda1 = radians(degreesInE7: point1.longitude)
  let phi1 = radians(degreesInE7: point1.latitude)
  let lambda2 = radians(degreesInE7: point2.longitude)
  let phi2 = radians(degreesInE7: point2.latitude)


  // Δλ = λ2 - λ1
  let deltaLambda = lambda2 - lambda1
  // Δφ = φ2 - φ1
  let deltaPhi = phi2 - phi1


  // sin²(Δφ/2)
  let sinHalfDeltaPhiSquared = sin(deltaPhi / 2) * sin(deltaPhi / 2)
  // sin²(Δλ/2)
  let sinHalfDeltaLambdaSquared = sin(deltaLambda / 2) * sin(deltaLambda / 2)


  // σc = 2 ⨯ sqrt(sin²(Δφ/2) + cos(φ1) ⨯ cos(φ2) ⨯ sin²(Δλ/2))
  let sigmaC = 2 * sqrt(sinHalfDeltaPhiSquared + cos(phi1) * cos(phi2) * sinHalfDeltaLambdaSquared)


  // This is the unit distance, i.e. assumes the circle has a radius of 1.
  let unitDistance = 2 * atan2(sqrt(sigmaC), sqrt(1 - sigmaC))


  // Scale it by the radius of the Earth in meters.
  let earthRadius = 6_371_000.0
  return unitDistance * earthRadius
}


private func radians(degreesInE7 degrees: Int32) -> Double {
  return (Double(degrees) / 1e7) * .pi / 180.0
}
