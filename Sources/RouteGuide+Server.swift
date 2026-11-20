//
//  RouteGuide+Server.swift
//  RouteGuide
//
//  Created by Ganesh Ubale on 20/11/26.
//

import GRPCCore
import GRPCNIOTransportHTTP2

extension RouteGuide {
    func runServer() async throws {
        let features = try self.loadFeatures()
        let routeGuideService = RouteGuideService(features: features)
        
        let server = GRPCServer(
            transport: .http2NIOPosix(
                address: .ipv4(host: "127.0.0.1", port: 31415),
                transportSecurity: .plaintext
            ),
            services: [routeGuideService])
        
        try await withThrowingDiscardingTaskGroup(returning: Void.self) { group in
            group.addTask {
                try await server.serve()
            }
            
            if let address = try await server.listeningAddress {
                print(" RouteGuide Server running at Address: \(address)")
            }
        }
    }
}
