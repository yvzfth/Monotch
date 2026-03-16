//
//  Item.swift
//  Nitche
//
//  Created by Fatih Yavuz on 17.03.2026.
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
