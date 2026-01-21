//
//  Item.swift
//  dyTool
//
//  Created by Everless on 2026/1/21.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
