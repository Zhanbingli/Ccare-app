//
//  CcareWidgitLiveActivity.swift
//  CcareWidgit
//
//  Created by lizhanbing12 on 15/04/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct CcareWidgitAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct CcareWidgitLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CcareWidgitAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension CcareWidgitAttributes {
    fileprivate static var preview: CcareWidgitAttributes {
        CcareWidgitAttributes(name: "World")
    }
}

extension CcareWidgitAttributes.ContentState {
    fileprivate static var smiley: CcareWidgitAttributes.ContentState {
        CcareWidgitAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: CcareWidgitAttributes.ContentState {
         CcareWidgitAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: CcareWidgitAttributes.preview) {
   CcareWidgitLiveActivity()
} contentStates: {
    CcareWidgitAttributes.ContentState.smiley
    CcareWidgitAttributes.ContentState.starEyes
}
