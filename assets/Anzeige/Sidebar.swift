import AppKit
import IOKit
import UserNotifications
import ServiceManagement

enum SidebarItem: Equatable {
    case header(String)
    case mac
    case ios(String)
    case history(String)
    case accessory(String)
    case settings
}

final class SidebarCell: NSTableCellView {
    let icon = NSImageView()
    let title = label("", size: 13)
    let sub = label("", size: 10, color: Palette.secondary)

    init() {
        super.init(frame: .zero)
        let t = NSStackView(views: [title, sub]); t.orientation = .vertical; t.alignment = .leading; t.spacing = 0
        let s = NSStackView(views: [icon, t]); s.spacing = 8
        s.translatesAutoresizingMaskIntoConstraints = false
        addSubview(s)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        NSLayoutConstraint.activate([
            s.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            s.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            s.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}
