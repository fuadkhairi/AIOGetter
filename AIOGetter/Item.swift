//
//  Item.swift
//  AIOGetter
//
//  Created by Fuad Khairi Hamid on 11/5/26.
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
