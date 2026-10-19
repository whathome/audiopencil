// Sends debug commands to a running Debug build. Numbers are pauses in seconds.
//   debug-dictation key:fnDown 0.1 key:fnUp 0.15 key:fnDown 0.1 key:fnUp
import Foundation

for argument in CommandLine.arguments.dropFirst() {
    if let seconds = Double(argument) {
        Thread.sleep(forTimeInterval: seconds)
        continue
    }
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("com.weshopkins.audiopencil.debug"),
        object: argument, userInfo: nil, deliverImmediately: true)
}
