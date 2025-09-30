import UIKit

/// 安全区域辅助工具类
/// 提供获取设备安全区域尺寸的便捷方法
class SafeAreaHelper {

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

    /// 判断是否为全面屏设备（有底部安全区）
    /// - Returns: true表示全面屏设备，false表示非全面屏设备
    static func isFullScreenDevice() -> Bool {
        return getBottomSafeAreaInset() > 0
    }
}
