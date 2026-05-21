import UserNotifications

enum NotificationScheduler {

    private static let thursdayID = "digest.weekly.thursday"
    private static let seventhID  = "digest.monthly.seventh"

    static func requestAndSchedule() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    if granted { schedule() }
                }
            case .authorized, .provisional, .ephemeral:
                schedule()
            default:
                break
            }
        }
    }

    private static func schedule() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let pendingIDs = Set(pending.map(\.identifier))
            var toAdd: [UNNotificationRequest] = []

            if !pendingIDs.contains(thursdayID) {
                toAdd.append(makeRequest(
                    id: thursdayID,
                    title: "Your Weekly Digest",
                    body: "Your Indiana housing market digest is ready.",
                    weekday: 5,   // Thursday (1=Sun … 7=Sat)
                    day: nil,
                    hour: 9
                ))
            }

            if !pendingIDs.contains(seventhID) {
                toAdd.append(makeRequest(
                    id: seventhID,
                    title: "Your Monthly Digest",
                    body: "Your Indiana housing market digest is ready.",
                    weekday: nil,
                    day: 7,
                    hour: 9
                ))
            }

            for request in toAdd {
                center.add(request)
            }
        }
    }

    private static func makeRequest(
        id: String,
        title: String,
        body: String,
        weekday: Int?,
        day: Int?,
        hour: Int
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["destination": "digest"]

        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        if let weekday { components.weekday = weekday }
        if let day { components.day = day }

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    static func isUndetermined(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                completion(settings.authorizationStatus == .notDetermined)
            }
        }
    }

    static func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [thursdayID, seventhID]
        )
    }
}
