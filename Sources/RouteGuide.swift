//
//  RouteGuide.swift
//  RouteGuide
//
//  Created by Ganesh Ubale on 20/11/26.
//
import Foundation
import ArgumentParser

@main
struct RouteGuide: AsyncParsableCommand {
    @Flag
    var server: Bool = false
    
    mutating func run() async throws {
        if server {
            try await runServer()
        } else {
            try await runClient()
        }
    }
    
    func loadFeatures() throws -> [Routeguide_Feature] {
        guard let url = Bundle.module.url(forResource: "route_guide_db", withExtension: "json") else {
            throw ExitCode.failure
        }
        
        let data = try Data(contentsOf: url)
        return try Routeguide_Feature.array(fromJSONUTF8Bytes: data)
    }
    
}
