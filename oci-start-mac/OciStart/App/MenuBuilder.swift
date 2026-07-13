import AppKit

enum MenuBuilder {
    /// Kept so we can rebuild when cloud provider switches.
    private static var navigationMenu: NSMenu?
    private static var navigationMenuItem: NSMenuItem?

    static func install() {
        let main = NSMenu()

        // App
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 OCI Start", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        let logout = NSMenuItem(
            title: "退出登录",
            action: #selector(AppDelegate.logoutAction(_:)),
            keyEquivalent: "l"
        )
        logout.keyEquivalentModifierMask = [.command, .shift]
        appMenu.addItem(logout)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "隐藏 OCI Start", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(
            title: "隐藏其他",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "退出 OCI Start", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        main.addItem(appMenuItem)

        // Edit
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(NSMenuItem.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        // View
        let viewItem = NSMenuItem()
        let view = NSMenu(title: "查看")
        view.addItem(NSMenuItem(
            title: "刷新当前页",
            action: #selector(AppDelegate.refreshAction(_:)),
            keyEquivalent: "r"
        ))
        view.addItem(NSMenuItem.separator())
        view.addItem(NSMenuItem(
            title: "切换主题",
            action: #selector(AppDelegate.cycleThemeAction(_:)),
            keyEquivalent: "t"
        ))
        let toggleSidebar = NSMenuItem(
            title: "显示/隐藏侧栏",
            action: #selector(AppDelegate.toggleSidebarAction(_:)),
            keyEquivalent: "s"
        )
        toggleSidebar.keyEquivalentModifierMask = [.command, .option]
        view.addItem(toggleSidebar)
        viewItem.submenu = view
        main.addItem(viewItem)

        // Navigate — filtered by current cloud provider (same rules as sidebar)
        let navItem = NSMenuItem()
        let nav = NSMenu(title: "导航")
        nav.autoenablesItems = true
        navigationMenu = nav
        navigationMenuItem = navItem
        rebuildNavigationMenu()
        navItem.submenu = nav
        main.addItem(navItem)

        // Window
        let windowItem = NSMenuItem()
        let window = NSMenu(title: "窗口")
        window.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        window.addItem(NSMenuItem.separator())
        window.addItem(withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        windowItem.submenu = window
        main.addItem(windowItem)

        NSApp.mainMenu = main
    }

    /// Rebuild 「导航」 submenu for current cloud provider (Oracle / GCP / Azure / AWS).
    static func rebuildNavigationMenu() {
        guard let nav = navigationMenu else { return }
        nav.removeAllItems()

        let cloud = AppSession.shared.cloudProvider
        // Section header showing active cloud
        let cloudTitle = NSMenuItem(
            title: "当前云：\(AppSession.shared.cloudProviderName)",
            action: nil,
            keyEquivalent: ""
        )
        cloudTitle.isEnabled = false
        nav.addItem(cloudTitle)
        nav.addItem(NSMenuItem.separator())

        let filtered = NavigationCatalog.filtered(search: "", cloudType: cloud)
        if filtered.isEmpty {
            let empty = NSMenuItem(title: "无可用菜单", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            nav.addItem(empty)
            return
        }

        for (section, items) in filtered {
            let sectionMenu = NSMenu(title: section.title)
            for item in items {
                let mi = NSMenuItem(
                    title: item.title,
                    action: #selector(AppDelegate.navigateMenuAction(_:)),
                    keyEquivalent: ""
                )
                mi.representedObject = item.nav.rawValue
                mi.target = NSApp.delegate
                sectionMenu.addItem(mi)
            }
            let parent = NSMenuItem(title: section.title, action: nil, keyEquivalent: "")
            parent.submenu = sectionMenu
            nav.addItem(parent)
        }
    }
}
