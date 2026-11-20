//
//  RouteGuide+Client.swift
//  RouteGuide
//
//  Created by Ganesh Ubale on 20/11/26.
//
import GRPCCore
import GRPCNIOTransportHTTP2

extension RouteGuide {
    func runClient() async throws {
        try await withGRPCClient(
            transport: .http2NIOPosix(
                target: .ipv4(address: "127.0.0.1", port: 31415),
                transportSecurity: .plaintext)) { client in
                    let routeGuideClient = Routeguide_RouteGuide.Client(wrapping: client)
                    try await self.getFeature(using: routeGuideClient)
                    try await self.listFeatures(using: routeGuideClient)
                    try await self.recordRoute(using: routeGuideClient)
                    try await self.routeChat(using: routeGuideClient)
                }
    }
    
    func getFeature(
        using routeGuideClient: Routeguide_RouteGuide.Client<some ClientTransport>
    ) async throws {
        print("→ Calling 'GetFeature'")
        
        let point: Routeguide_Point = .with {
            $0.latitude = 407_838_351
            $0.longitude = -746_143_763
        }
        
        let feature = try await routeGuideClient.getFeature(point)
        
        print("Got feature '\(feature.name)'")
    }
    
    func listFeatures(
        using routeGuideClient: Routeguide_RouteGuide.Client<some ClientTransport>
    ) async throws {
        print("→ Calling 'listFeatures'")
        
        let rectangle = Routeguide_Rectangle.with {
            $0.lo = .with {
                $0.latitude = 400_000_000
                $0.longitude = -750_000_000
            }
            
            $0.hi = .with {
                $0.latitude = 420_000_000
                $0.longitude = -730_000_000
            }
        }

        try await routeGuideClient.listFeatures(rectangle) { response in
            for try await feature in response.messages {
                print(
                    "Got feature '\(feature.name)' at (\(feature.location.latitude), \(feature.location.longitude))"
                )
            }
        }
    }
    
    func recordRoute(
        using routeGuideClient: Routeguide_RouteGuide.Client<some ClientTransport>
    ) async throws {
        print("→ Calling 'recordRoute'")
        
        let features = try self.loadFeatures()
        let noOfPoints = (2...10).randomElement() ?? 10
        
        let summary = try await routeGuideClient.recordRoute { writer in
            for _ in (0..<noOfPoints) {
                if let feature = features.randomElement() {
                    try await writer.write(feature.location)
                }
            }
        }
        
        print(
              """
              Finished trip with \(summary.pointCount) points. Passed \(summary.featureCount) \
              features. Travelled \(summary.distance) meters. It took \(summary.elapsedTime) seconds.
              """
        )
    }
    
    func routeChat(
        using routeGuideClient: Routeguide_RouteGuide.Client<some ClientTransport>
    ) async throws {
        print("→ Calling 'routeChat'")
        let features = try self.loadFeatures()
        let noOfPoints = (2...10).randomElement() ?? 10
        
        try await routeGuideClient.routeChat { writer in
            for _ in (0..<noOfPoints) {
                if let feature = features.randomElement() {
                    let routeNote: Routeguide_RouteNote = .with {
                        $0.location = feature.location
                        $0.message = "First test"
                    }
                    print("Sending message '\(routeNote.message)' at (\(routeNote.location.latitude), \(routeNote.location.longitude))")
                    try await writer.write(routeNote)
                }
            }
        } onResponse: { response in
            for try await note in response.messages {
                print(
                    "Got message '\(note.message)' at (\(note.location.latitude), \(note.location.longitude))"
                )
            }
        }

    }
    
}
