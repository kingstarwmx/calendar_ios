import UIKit

/// 设备信息辅助工具类
/// 提供设备相关信息获取的便捷方法，包括安全区域、屏幕尺寸、设备类型等
class DeviceHelper {

    // MARK: - 安全区域相关

    /// 获取底部安全区高度
    /// - Returns: 底部安全区高度（pt）
    static func getBottomSafeAreaInset() -> CGFloat {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window.safeAreaInsets.bottom
        }
        return 0
    }

    /// 获取顶部安全区高度
    /// - Returns: 顶部安全区高度（pt）
    static func getTopSafeAreaInset() -> CGFloat {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window.safeAreaInsets.top
        }
        return 0
    }

    /// 获取左侧安全区宽度
    /// - Returns: 左侧安全区宽度（pt）
    static func getLeftSafeAreaInset() -> CGFloat {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window.safeAreaInsets.left
        }
        return 0
    }

    /// 获取右侧安全区宽度
    /// - Returns: 右侧安全区宽度（pt）
    static func getRightSafeAreaInset() -> CGFloat {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window.safeAreaInsets.right
        }
        return 0
    }

    /// 获取完整的安全区域insets
    /// - Returns: UIEdgeInsets对象
    static func getSafeAreaInsets() -> UIEdgeInsets {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window.safeAreaInsets
        }
        return .zero
    }

    // MARK: - 屏幕尺寸相关

    /// 获取屏幕宽度
    /// - Returns: 屏幕宽度（pt）
    static var screenWidth: CGFloat {
        return UIScreen.main.bounds.width
    }

    /// 获取屏幕高度
    /// - Returns: 屏幕高度（pt）
    static var screenHeight: CGFloat {
        return UIScreen.main.bounds.height
    }

    /// 获取屏幕尺寸
    /// - Returns: 屏幕尺寸CGSize
    static var screenSize: CGSize {
        return UIScreen.main.bounds.size
    }

    /// 获取屏幕bounds
    /// - Returns: 屏幕bounds
    static var screenBounds: CGRect {
        return UIScreen.main.bounds
    }

    /// 获取屏幕scale
    /// - Returns: 屏幕缩放比例
    static var screenScale: CGFloat {
        return UIScreen.main.scale
    }

    /// 获取状态栏高度
    /// - Returns: 状态栏高度（pt）
    static var statusBarHeight: CGFloat {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return windowScene.statusBarManager?.statusBarFrame.height ?? 0
        }
        return 0
    }

    /// 获取导航栏高度（不包含状态栏）
    /// - Parameter navigationController: 导航控制器，默认获取当前活动的
    /// - Returns: 导航栏高度（pt）
    static func navigationBarHeight(from navigationController: UINavigationController? = nil) -> CGFloat {
        if let navController = navigationController {
            return navController.navigationBar.frame.height
        }

        // 尝试获取当前活动的导航控制器
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }),
           let rootVC = window.rootViewController {

            // 递归查找导航控制器
            if let nav = findNavigationController(from: rootVC) {
                return nav.navigationBar.frame.height
            }
        }

        // 默认值：标准44pt，紧凑型32pt（横屏iPhone）
        if isLandscape && isPhone {
            return 32.0  // 横屏iPhone的紧凑型导航栏
        }
        return 44.0  // 标准导航栏高度
    }

    /// 递归查找导航控制器
    private static func findNavigationController(from viewController: UIViewController) -> UINavigationController? {
        if let nav = viewController as? UINavigationController {
            return nav
        }
        if let nav = viewController.navigationController {
            return nav
        }
        if let tab = viewController as? UITabBarController,
           let selected = tab.selectedViewController {
            return findNavigationController(from: selected)
        }
        if let presented = viewController.presentedViewController {
            return findNavigationController(from: presented)
        }
        for child in viewController.children {
            if let nav = findNavigationController(from: child) {
                return nav
            }
        }
        return nil
    }

    /// 获取导航栏总高度（包含状态栏）
    /// - Parameter navigationController: 导航控制器
    /// - Returns: 导航栏总高度（pt）
    static func navigationBarTotalHeight(from navigationController: UINavigationController? = nil) -> CGFloat {
        return statusBarHeight + navigationBarHeight(from: navigationController)
    }

    /// 获取标签栏高度（包含安全区）
    /// - Parameter tabBarController: 标签栏控制器，默认获取当前活动的
    /// - Returns: 标签栏高度（pt）
    static func tabBarHeight(from tabBarController: UITabBarController? = nil) -> CGFloat {
        if let tabController = tabBarController {
            return tabController.tabBar.frame.height
        }

        // 尝试获取当前活动的标签栏控制器
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first(where: { $0.isKeyWindow }),
           let rootVC = window.rootViewController {

            // 递归查找标签栏控制器
            if let tab = findTabBarController(from: rootVC) {
                return tab.tabBar.frame.height
            }
        }

        // 默认值：49pt + 底部安全区
        return 49.0 + getBottomSafeAreaInset()
    }

    /// 递归查找标签栏控制器
    private static func findTabBarController(from viewController: UIViewController) -> UITabBarController? {
        if let tab = viewController as? UITabBarController {
            return tab
        }
        if let tab = viewController.tabBarController {
            return tab
        }
        if let nav = viewController as? UINavigationController,
           let rootVC = nav.viewControllers.first {
            return findTabBarController(from: rootVC)
        }
        if let presented = viewController.presentedViewController {
            return findTabBarController(from: presented)
        }
        for child in viewController.children {
            if let tab = findTabBarController(from: child) {
                return tab
            }
        }
        return nil
    }

    // MARK: - 设备类型判断

    /// 判断是否为iPhone
    /// - Returns: true表示iPhone，false表示其他设备
    static var isPhone: Bool {
        return UIDevice.current.userInterfaceIdiom == .phone
    }

    /// 判断是否为iPad
    /// - Returns: true表示iPad，false表示其他设备
    static var isPad: Bool {
        return UIDevice.current.userInterfaceIdiom == .pad
    }

    /// 判断是否为全面屏设备（有底部安全区）
    /// - Returns: true表示全面屏设备，false表示非全面屏设备
    static var isFullScreenDevice: Bool {
        return getBottomSafeAreaInset() > 0
    }

    /// 判断是否为小屏设备（iPhone SE, iPhone 8等）
    /// - Returns: true表示小屏设备
    static var isSmallScreen: Bool {
        return screenWidth <= 375
    }

    /// 判断是否为大屏设备（iPhone Plus, Pro Max等）
    /// - Returns: true表示大屏设备
    static var isLargeScreen: Bool {
        return screenWidth >= 414
    }

    /// 判断是否为横屏
    /// - Returns: true表示横屏，false表示竖屏
    static var isLandscape: Bool {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return windowScene.interfaceOrientation.isLandscape
        }
        return false
    }

    /// 判断是否为竖屏
    /// - Returns: true表示竖屏，false表示横屏
    static var isPortrait: Bool {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return windowScene.interfaceOrientation.isPortrait
        }
        return true
    }

    // MARK: - 系统版本相关

    /// 获取系统版本
    /// - Returns: 系统版本字符串
    static var systemVersion: String {
        return UIDevice.current.systemVersion
    }

    /// 判断系统版本是否大于等于指定版本
    /// - Parameter version: 版本号字符串，如"14.0"
    /// - Returns: true表示当前版本大于等于指定版本
    static func isSystemVersionAtLeast(_ version: String) -> Bool {
        return UIDevice.current.systemVersion.compare(version, options: .numeric) != .orderedAscending
    }

    /// 获取设备型号
    /// - Returns: 设备型号字符串
    static var deviceModel: String {
        return UIDevice.current.model
    }

    /// 获取设备名称
    /// - Returns: 设备名称字符串
    static var deviceName: String {
        return UIDevice.current.name
    }

    // MARK: - 常用尺寸计算

    /// 根据屏幕宽度等比缩放
    /// - Parameter size: 设计稿尺寸（基于375宽度）
    /// - Returns: 缩放后的尺寸
    static func scaleWidth(_ size: CGFloat, baseWidth: CGFloat = 375) -> CGFloat {
        return size * screenWidth / baseWidth
    }

    /// 根据屏幕高度等比缩放
    /// - Parameter size: 设计稿尺寸（基于812高度）
    /// - Returns: 缩放后的尺寸
    static func scaleHeight(_ size: CGFloat, baseHeight: CGFloat = 812) -> CGFloat {
        return size * screenHeight / baseHeight
    }

    /// 获取1像素的高度（用于绘制分割线）
    /// - Returns: 1像素高度（pt）
    static var onePixel: CGFloat {
        return 1.0 / screenScale
    }

    /// 获取当前界面方向
    /// - Returns: UIInterfaceOrientation
    static var interfaceOrientation: UIInterfaceOrientation {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return windowScene.interfaceOrientation
        }
        return .portrait
    }

    /// 获取主窗口
    /// - Returns: 主窗口UIWindow
    static var keyWindow: UIWindow? {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return windowScene.windows.first { $0.isKeyWindow }
        }
        return nil
    }
}

// MARK: - 便捷属性扩展
extension DeviceHelper {
    /// iPhone X系列（包括11、12、13、14、15系列）
    static var iPhoneX: Bool { isFullScreenDevice && isPhone }

    /// iPhone 5/SE 第一代
    static var iPhone5: Bool { screenWidth == 320 && screenHeight == 568 }

    /// iPhone 6/7/8/SE2/SE3
    static var iPhone678: Bool { screenWidth == 375 && screenHeight == 667 }

    /// iPhone 6Plus/7Plus/8Plus
    static var iPhone678Plus: Bool { screenWidth == 414 && screenHeight == 736 }

    /// iPhone 12/13/14/15 mini
    static var iPhoneMini: Bool { screenWidth == 375 && screenHeight == 812 }

    /// iPhone 12/13/14/15/16
    static var iPhoneStandard: Bool { screenWidth == 390 && screenHeight == 844 }

    /// iPhone 12/13/14/15/16 Pro
    static var iPhonePro: Bool { screenWidth == 393 && screenHeight == 852 }

    /// iPhone 12/13/14/15/16 Pro Max
    static var iPhoneProMax: Bool { screenWidth == 430 && screenHeight == 932 }
}
