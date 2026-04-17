//
//  CcareWidgitBundle.swift
//  CcareWidgit
//
//  Created by lizhanbing12 on 15/04/26.
//

import WidgetKit
import SwiftUI

@main
struct CcareWidgitBundle: WidgetBundle {
    var body: some Widget {
        CcareWidgit()
        CcareWidgitControl()
        CcareWidgitLiveActivity()
    }
}
