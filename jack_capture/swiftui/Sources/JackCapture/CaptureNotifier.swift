// SPDX-License-Identifier: GPL-2.0-or-later

import Foundation
import UserNotifications

/// Says something to the person through the notifications of the system, when they are not looking at the window (a disk that runs short while a recording
/// is hidden in the menu bar). The system asks for the permission the first time.
enum CaptureNotifier {
    static func post(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
