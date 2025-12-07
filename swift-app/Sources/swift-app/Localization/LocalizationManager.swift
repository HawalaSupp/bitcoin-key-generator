import Foundation
import SwiftUI

// MARK: - Localization Manager

/// Manages app localization with support for dynamic language switching
@MainActor
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()
    
    // MARK: - Supported Languages
    
    enum Language: String, CaseIterable, Identifiable {
        case english = "en"
        case spanish = "es"
        case chinese = "zh"
        case arabic = "ar"
        case french = "fr"
        case german = "de"
        case japanese = "ja"
        case korean = "ko"
        case portuguese = "pt"
        case russian = "ru"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .english: return "English"
            case .spanish: return "Español"
            case .chinese: return "中文"
            case .arabic: return "العربية"
            case .french: return "Français"
            case .german: return "Deutsch"
            case .japanese: return "日本語"
            case .korean: return "한국어"
            case .portuguese: return "Português"
            case .russian: return "Русский"
            }
        }
        
        var flag: String {
            switch self {
            case .english: return "🇺🇸"
            case .spanish: return "🇪🇸"
            case .chinese: return "🇨🇳"
            case .arabic: return "🇸🇦"
            case .french: return "🇫🇷"
            case .german: return "🇩🇪"
            case .japanese: return "🇯🇵"
            case .korean: return "🇰🇷"
            case .portuguese: return "🇧🇷"
            case .russian: return "🇷🇺"
            }
        }
        
        var isRTL: Bool {
            self == .arabic
        }
    }
    
    // MARK: - Published Properties
    
    @Published private(set) var currentLanguage: Language = .english
    @Published private(set) var strings: [String: String] = [:]
    
    // MARK: - Storage
    
    @AppStorage("hawala.language") private var storedLanguage: String = "en"
    
    // MARK: - Initialization
    
    private init() {
        // Load saved language preference
        if let lang = Language(rawValue: storedLanguage) {
            currentLanguage = lang
        } else {
            // Detect system language
            currentLanguage = detectSystemLanguage()
        }
        loadStrings()
    }
    
    // MARK: - Public Methods
    
    /// Set the current language
    func setLanguage(_ language: Language) {
        currentLanguage = language
        storedLanguage = language.rawValue
        loadStrings()
    }
    
    /// Get localized string for key
    func localized(_ key: String) -> String {
        strings[key] ?? key
    }
    
    /// Get localized string with format arguments
    func localized(_ key: String, _ args: CVarArg...) -> String {
        let format = strings[key] ?? key
        return String(format: format, arguments: args)
    }
    
    // MARK: - Private Methods
    
    private func detectSystemLanguage() -> Language {
        let preferredLang = Locale.preferredLanguages.first?.prefix(2) ?? "en"
        return Language(rawValue: String(preferredLang)) ?? .english
    }
    
    private func loadStrings() {
        strings = LocalizedStrings.strings(for: currentLanguage)
    }
}

// MARK: - Localized Strings Database

struct LocalizedStrings {
    static func strings(for language: LocalizationManager.Language) -> [String: String] {
        switch language {
        case .english: return englishStrings
        case .spanish: return spanishStrings
        case .chinese: return chineseStrings
        case .arabic: return arabicStrings
        case .french: return frenchStrings
        case .german: return germanStrings
        case .japanese: return japaneseStrings
        case .korean: return koreanStrings
        case .portuguese: return portugueseStrings
        case .russian: return russianStrings
        }
    }
    
    // MARK: - English (Base)
    
    static let englishStrings: [String: String] = [
        // Navigation
        "nav.portfolio": "Portfolio",
        "nav.send": "Send",
        "nav.receive": "Receive",
        "nav.history": "History",
        "nav.settings": "Settings",
        "nav.swap": "Swap",
        
        // Portfolio
        "portfolio.title": "Portfolio",
        "portfolio.total_balance": "Total Balance",
        "portfolio.assets": "Assets",
        "portfolio.no_assets": "No assets yet",
        "portfolio.add_wallet": "Add Wallet",
        "portfolio.refresh": "Refresh",
        "portfolio.hide_balance": "Hide Balance",
        "portfolio.show_balance": "Show Balance",
        
        // Send
        "send.title": "Send",
        "send.recipient": "Recipient Address",
        "send.amount": "Amount",
        "send.fee": "Network Fee",
        "send.total": "Total",
        "send.confirm": "Confirm Send",
        "send.cancel": "Cancel",
        "send.paste": "Paste",
        "send.scan_qr": "Scan QR",
        "send.max": "Max",
        "send.insufficient_balance": "Insufficient balance",
        "send.invalid_address": "Invalid address",
        "send.success": "Transaction sent successfully",
        "send.failed": "Transaction failed",
        
        // Receive
        "receive.title": "Receive",
        "receive.address": "Your Address",
        "receive.copy": "Copy Address",
        "receive.share": "Share",
        "receive.request_amount": "Request Amount",
        "receive.copied": "Address copied!",
        "receive.verify": "Verify on Device",
        "receive.warning": "Only send %@ to this address",
        
        // History
        "history.title": "Transaction History",
        "history.all": "All",
        "history.sent": "Sent",
        "history.received": "Received",
        "history.pending": "Pending",
        "history.confirmed": "Confirmed",
        "history.failed": "Failed",
        "history.no_transactions": "No transactions yet",
        "history.view_explorer": "View in Explorer",
        
        // Settings
        "settings.title": "Settings",
        "settings.general": "General",
        "settings.security": "Security Settings",
        "settings.network": "Network",
        "settings.appearance": "Appearance",
        "settings.privacy": "Privacy",
        "settings.advanced": "Advanced",
        "settings.about": "About",
        "settings.language": "Language",
        "settings.language.description": "Choose your preferred display language",
        "settings.currency": "Display Currency",
        "settings.theme": "Theme",
        "settings.dark": "Dark",
        "settings.light": "Light",
        "settings.system": "System",
        "settings.biometric": "Biometric Unlock",
        "settings.passcode": "Passcode",
        "settings.auto_lock": "Auto-Lock",
        "settings.testnet": "Use Testnet",
        "settings.backup": "Backup Wallet",
        "settings.export": "Export History",
        "settings.reset": "Reset Wallet",
        "settings.version": "Version",
        "settings.show_keys": "Show All Private Keys",
        
        // Swap
        "swap.title": "Swap",
        "swap.from": "From",
        "swap.to": "To",
        "swap.rate": "Exchange Rate",
        "swap.slippage": "Slippage Tolerance",
        "swap.review": "Review Swap",
        "swap.confirm": "Confirm Swap",
        "swap.fetching_quote": "Fetching best rate...",
        "swap.no_route": "No swap route available",
        "swap.get_quotes": "Get Quotes",
        "swap.loading_quotes": "Loading Quotes...",
        "swap.available_quotes": "Available Quotes",
        "swap.active_swaps": "Active Swaps",
        "swap.history": "Swap History",
        "swap.summary": "Swap Summary",
        "swap.you_send": "You Send",
        "swap.you_receive": "You Receive",
        "swap.provider": "Provider",
        "swap.network_fee": "Network Fee",
        "swap.estimated_time": "Estimated Time",
        "swap.destination": "Destination",
        "swap.destination_address_placeholder": "Enter destination address",
        "swap.destination_warning": "Make sure this is the correct address. Transactions cannot be reversed.",
        "swap.confirm_swap": "Confirm Swap",
        "swap.details": "Swap Details",
        "swap.send": "Send",
        "swap.receive": "Receive",
        "swap.deposit_address": "Deposit Address",
        "swap.deposit_instructions": "Send the exact amount to this address to start the swap.",
        "swap.destination_address": "Destination Address",
        "swap.deposit_tx": "Deposit Transaction",
        "swap.payout_tx": "Payout Transaction",
        "swap.created": "Created",
        "swap.expires": "Expires",
        "swap.status_refreshing": "Status updates automatically",
        
        // Hardware Wallet
        "hardware.title": "Hardware Wallet",
        "hardware.connect": "Connect Device",
        "hardware.disconnect": "Disconnect",
        "hardware.connected": "Connected",
        "hardware.not_connected": "Not Connected",
        "hardware.ledger": "Ledger",
        "hardware.trezor": "Trezor",
        "hardware.sign_on_device": "Confirm on your device",
        
        // Common
        "common.close": "Close",
        "common.done": "Done",
        "common.save": "Save",
        "common.cancel": "Cancel",
        "common.confirm": "Confirm",
        "common.delete": "Delete",
        "common.edit": "Edit",
        "common.search": "Search",
        "common.loading": "Loading...",
        "common.error": "Error",
        "common.success": "Success",
        "common.warning": "Warning",
        "common.retry": "Retry",
        "common.copy": "Copy",
        "common.share": "Share",
        
        // Errors
        "error.network": "Network error. Please try again.",
        "error.invalid_input": "Invalid input",
        "error.unknown": "An unknown error occurred",
        "error.timeout": "Request timed out",
    ]
    
    // MARK: - Spanish
    
    static let spanishStrings: [String: String] = [
        // Navigation
        "nav.portfolio": "Portafolio",
        "nav.send": "Enviar",
        "nav.receive": "Recibir",
        "nav.history": "Historial",
        "nav.settings": "Ajustes",
        "nav.swap": "Intercambiar",
        
        // Portfolio
        "portfolio.title": "Portafolio",
        "portfolio.total_balance": "Balance Total",
        "portfolio.assets": "Activos",
        "portfolio.no_assets": "Sin activos aún",
        "portfolio.add_wallet": "Agregar Billetera",
        "portfolio.refresh": "Actualizar",
        "portfolio.hide_balance": "Ocultar Balance",
        "portfolio.show_balance": "Mostrar Balance",
        
        // Send
        "send.title": "Enviar",
        "send.recipient": "Dirección del Destinatario",
        "send.amount": "Cantidad",
        "send.fee": "Comisión de Red",
        "send.total": "Total",
        "send.confirm": "Confirmar Envío",
        "send.cancel": "Cancelar",
        "send.paste": "Pegar",
        "send.scan_qr": "Escanear QR",
        "send.max": "Máx",
        "send.insufficient_balance": "Balance insuficiente",
        "send.invalid_address": "Dirección inválida",
        "send.success": "Transacción enviada exitosamente",
        "send.failed": "Transacción fallida",
        
        // Receive
        "receive.title": "Recibir",
        "receive.address": "Tu Dirección",
        "receive.copy": "Copiar Dirección",
        "receive.share": "Compartir",
        "receive.request_amount": "Solicitar Cantidad",
        "receive.copied": "¡Dirección copiada!",
        "receive.verify": "Verificar en Dispositivo",
        "receive.warning": "Solo envía %@ a esta dirección",
        
        // History
        "history.title": "Historial de Transacciones",
        "history.all": "Todo",
        "history.sent": "Enviado",
        "history.received": "Recibido",
        "history.pending": "Pendiente",
        "history.confirmed": "Confirmado",
        "history.failed": "Fallido",
        "history.no_transactions": "Sin transacciones aún",
        "history.view_explorer": "Ver en Explorador",
        
        // Settings
        "settings.title": "Ajustes",
        "settings.general": "General",
        "settings.security": "Seguridad",
        "settings.network": "Red",
        "settings.appearance": "Apariencia",
        "settings.privacy": "Privacidad",
        "settings.advanced": "Avanzado",
        "settings.about": "Acerca de",
        "settings.language": "Idioma",
        "settings.currency": "Moneda de Visualización",
        "settings.theme": "Tema",
        "settings.dark": "Oscuro",
        "settings.light": "Claro",
        "settings.system": "Sistema",
        "settings.biometric": "Desbloqueo Biométrico",
        "settings.passcode": "Código de Acceso",
        "settings.auto_lock": "Bloqueo Automático",
        "settings.testnet": "Usar Testnet",
        "settings.backup": "Respaldar Billetera",
        "settings.export": "Exportar Historial",
        "settings.reset": "Restablecer Billetera",
        "settings.version": "Versión",
        
        // Swap
        "swap.title": "Intercambiar",
        "swap.from": "Desde",
        "swap.to": "Hacia",
        "swap.rate": "Tasa de Cambio",
        "swap.slippage": "Tolerancia de Deslizamiento",
        "swap.review": "Revisar Intercambio",
        "swap.confirm": "Confirmar Intercambio",
        "swap.fetching_quote": "Obteniendo mejor tasa...",
        "swap.no_route": "No hay ruta de intercambio disponible",
        
        // Hardware Wallet
        "hardware.title": "Billetera de Hardware",
        "hardware.connect": "Conectar Dispositivo",
        "hardware.disconnect": "Desconectar",
        "hardware.connected": "Conectado",
        "hardware.not_connected": "No Conectado",
        "hardware.ledger": "Ledger",
        "hardware.trezor": "Trezor",
        "hardware.sign_on_device": "Confirma en tu dispositivo",
        
        // Common
        "common.close": "Cerrar",
        "common.done": "Listo",
        "common.save": "Guardar",
        "common.cancel": "Cancelar",
        "common.confirm": "Confirmar",
        "common.delete": "Eliminar",
        "common.edit": "Editar",
        "common.search": "Buscar",
        "common.loading": "Cargando...",
        "common.error": "Error",
        "common.success": "Éxito",
        "common.warning": "Advertencia",
        "common.retry": "Reintentar",
        "common.copy": "Copiar",
        "common.share": "Compartir",
        
        // Errors
        "error.network": "Error de red. Por favor intenta de nuevo.",
        "error.invalid_input": "Entrada inválida",
        "error.unknown": "Ocurrió un error desconocido",
        "error.timeout": "Tiempo de espera agotado",
    ]
    
    // MARK: - Chinese (Simplified)
    
    static let chineseStrings: [String: String] = [
        // Navigation
        "nav.portfolio": "资产",
        "nav.send": "发送",
        "nav.receive": "接收",
        "nav.history": "历史",
        "nav.settings": "设置",
        "nav.swap": "兑换",
        
        // Portfolio
        "portfolio.title": "资产",
        "portfolio.total_balance": "总余额",
        "portfolio.assets": "资产",
        "portfolio.no_assets": "暂无资产",
        "portfolio.add_wallet": "添加钱包",
        "portfolio.refresh": "刷新",
        "portfolio.hide_balance": "隐藏余额",
        "portfolio.show_balance": "显示余额",
        
        // Send
        "send.title": "发送",
        "send.recipient": "收款地址",
        "send.amount": "金额",
        "send.fee": "网络费用",
        "send.total": "总计",
        "send.confirm": "确认发送",
        "send.cancel": "取消",
        "send.paste": "粘贴",
        "send.scan_qr": "扫描二维码",
        "send.max": "最大",
        "send.insufficient_balance": "余额不足",
        "send.invalid_address": "地址无效",
        "send.success": "交易发送成功",
        "send.failed": "交易失败",
        
        // Receive
        "receive.title": "接收",
        "receive.address": "您的地址",
        "receive.copy": "复制地址",
        "receive.share": "分享",
        "receive.request_amount": "请求金额",
        "receive.copied": "地址已复制！",
        "receive.verify": "在设备上验证",
        "receive.warning": "只向此地址发送 %@",
        
        // History
        "history.title": "交易历史",
        "history.all": "全部",
        "history.sent": "已发送",
        "history.received": "已接收",
        "history.pending": "待处理",
        "history.confirmed": "已确认",
        "history.failed": "失败",
        "history.no_transactions": "暂无交易",
        "history.view_explorer": "在浏览器中查看",
        
        // Settings
        "settings.title": "设置",
        "settings.general": "通用",
        "settings.security": "安全",
        "settings.network": "网络",
        "settings.appearance": "外观",
        "settings.privacy": "隐私",
        "settings.advanced": "高级",
        "settings.about": "关于",
        "settings.language": "语言",
        "settings.currency": "显示货币",
        "settings.theme": "主题",
        "settings.dark": "深色",
        "settings.light": "浅色",
        "settings.system": "跟随系统",
        "settings.biometric": "生物识别解锁",
        "settings.passcode": "密码",
        "settings.auto_lock": "自动锁定",
        "settings.testnet": "使用测试网",
        "settings.backup": "备份钱包",
        "settings.export": "导出历史",
        "settings.reset": "重置钱包",
        "settings.version": "版本",
        
        // Swap
        "swap.title": "兑换",
        "swap.from": "从",
        "swap.to": "至",
        "swap.rate": "汇率",
        "swap.slippage": "滑点容差",
        "swap.review": "查看兑换",
        "swap.confirm": "确认兑换",
        "swap.fetching_quote": "正在获取最佳汇率...",
        "swap.no_route": "无可用兑换路径",
        
        // Hardware Wallet
        "hardware.title": "硬件钱包",
        "hardware.connect": "连接设备",
        "hardware.disconnect": "断开连接",
        "hardware.connected": "已连接",
        "hardware.not_connected": "未连接",
        "hardware.ledger": "Ledger",
        "hardware.trezor": "Trezor",
        "hardware.sign_on_device": "请在设备上确认",
        
        // Common
        "common.close": "关闭",
        "common.done": "完成",
        "common.save": "保存",
        "common.cancel": "取消",
        "common.confirm": "确认",
        "common.delete": "删除",
        "common.edit": "编辑",
        "common.search": "搜索",
        "common.loading": "加载中...",
        "common.error": "错误",
        "common.success": "成功",
        "common.warning": "警告",
        "common.retry": "重试",
        "common.copy": "复制",
        "common.share": "分享",
        
        // Errors
        "error.network": "网络错误，请重试",
        "error.invalid_input": "输入无效",
        "error.unknown": "发生未知错误",
        "error.timeout": "请求超时",
    ]
    
    // MARK: - Arabic
    
    static let arabicStrings: [String: String] = [
        // Navigation
        "nav.portfolio": "المحفظة",
        "nav.send": "إرسال",
        "nav.receive": "استلام",
        "nav.history": "السجل",
        "nav.settings": "الإعدادات",
        "nav.swap": "تبديل",
        
        // Portfolio
        "portfolio.title": "المحفظة",
        "portfolio.total_balance": "الرصيد الإجمالي",
        "portfolio.assets": "الأصول",
        "portfolio.no_assets": "لا توجد أصول بعد",
        "portfolio.add_wallet": "إضافة محفظة",
        "portfolio.refresh": "تحديث",
        "portfolio.hide_balance": "إخفاء الرصيد",
        "portfolio.show_balance": "إظهار الرصيد",
        
        // Send
        "send.title": "إرسال",
        "send.recipient": "عنوان المستلم",
        "send.amount": "المبلغ",
        "send.fee": "رسوم الشبكة",
        "send.total": "الإجمالي",
        "send.confirm": "تأكيد الإرسال",
        "send.cancel": "إلغاء",
        "send.paste": "لصق",
        "send.scan_qr": "مسح QR",
        "send.max": "الحد الأقصى",
        "send.insufficient_balance": "رصيد غير كافٍ",
        "send.invalid_address": "عنوان غير صالح",
        "send.success": "تم إرسال المعاملة بنجاح",
        "send.failed": "فشلت المعاملة",
        
        // Receive
        "receive.title": "استلام",
        "receive.address": "عنوانك",
        "receive.copy": "نسخ العنوان",
        "receive.share": "مشاركة",
        "receive.request_amount": "طلب مبلغ",
        "receive.copied": "تم نسخ العنوان!",
        "receive.verify": "تحقق على الجهاز",
        "receive.warning": "أرسل فقط %@ إلى هذا العنوان",
        
        // Common
        "common.close": "إغلاق",
        "common.done": "تم",
        "common.save": "حفظ",
        "common.cancel": "إلغاء",
        "common.confirm": "تأكيد",
        "common.delete": "حذف",
        "common.edit": "تعديل",
        "common.search": "بحث",
        "common.loading": "جارٍ التحميل...",
        "common.error": "خطأ",
        "common.success": "نجاح",
        "common.warning": "تحذير",
        "common.retry": "إعادة المحاولة",
        "common.copy": "نسخ",
        "common.share": "مشاركة",
    ]
    
    // MARK: - French
    
    static let frenchStrings: [String: String] = [
        "nav.portfolio": "Portefeuille",
        "nav.send": "Envoyer",
        "nav.receive": "Recevoir",
        "nav.history": "Historique",
        "nav.settings": "Paramètres",
        "nav.swap": "Échanger",
        "portfolio.title": "Portefeuille",
        "portfolio.total_balance": "Solde Total",
        "send.title": "Envoyer",
        "receive.title": "Recevoir",
        "settings.title": "Paramètres",
        "common.close": "Fermer",
        "common.done": "Terminé",
        "common.save": "Enregistrer",
        "common.cancel": "Annuler",
        "common.confirm": "Confirmer",
    ]
    
    // MARK: - German
    
    static let germanStrings: [String: String] = [
        "nav.portfolio": "Portfolio",
        "nav.send": "Senden",
        "nav.receive": "Empfangen",
        "nav.history": "Verlauf",
        "nav.settings": "Einstellungen",
        "nav.swap": "Tauschen",
        "portfolio.title": "Portfolio",
        "portfolio.total_balance": "Gesamtguthaben",
        "send.title": "Senden",
        "receive.title": "Empfangen",
        "settings.title": "Einstellungen",
        "common.close": "Schließen",
        "common.done": "Fertig",
        "common.save": "Speichern",
        "common.cancel": "Abbrechen",
        "common.confirm": "Bestätigen",
    ]
    
    // MARK: - Japanese
    
    static let japaneseStrings: [String: String] = [
        "nav.portfolio": "ポートフォリオ",
        "nav.send": "送金",
        "nav.receive": "受取",
        "nav.history": "履歴",
        "nav.settings": "設定",
        "nav.swap": "交換",
        "portfolio.title": "ポートフォリオ",
        "portfolio.total_balance": "総残高",
        "send.title": "送金",
        "receive.title": "受取",
        "settings.title": "設定",
        "common.close": "閉じる",
        "common.done": "完了",
        "common.save": "保存",
        "common.cancel": "キャンセル",
        "common.confirm": "確認",
    ]
    
    // MARK: - Korean
    
    static let koreanStrings: [String: String] = [
        "nav.portfolio": "포트폴리오",
        "nav.send": "보내기",
        "nav.receive": "받기",
        "nav.history": "거래내역",
        "nav.settings": "설정",
        "nav.swap": "스왑",
        "portfolio.title": "포트폴리오",
        "portfolio.total_balance": "총 잔액",
        "send.title": "보내기",
        "receive.title": "받기",
        "settings.title": "설정",
        "common.close": "닫기",
        "common.done": "완료",
        "common.save": "저장",
        "common.cancel": "취소",
        "common.confirm": "확인",
    ]
    
    // MARK: - Portuguese
    
    static let portugueseStrings: [String: String] = [
        "nav.portfolio": "Portfólio",
        "nav.send": "Enviar",
        "nav.receive": "Receber",
        "nav.history": "Histórico",
        "nav.settings": "Configurações",
        "nav.swap": "Trocar",
        "portfolio.title": "Portfólio",
        "portfolio.total_balance": "Saldo Total",
        "send.title": "Enviar",
        "receive.title": "Receber",
        "settings.title": "Configurações",
        "common.close": "Fechar",
        "common.done": "Concluído",
        "common.save": "Salvar",
        "common.cancel": "Cancelar",
        "common.confirm": "Confirmar",
    ]
    
    // MARK: - Russian
    
    static let russianStrings: [String: String] = [
        "nav.portfolio": "Портфель",
        "nav.send": "Отправить",
        "nav.receive": "Получить",
        "nav.history": "История",
        "nav.settings": "Настройки",
        "nav.swap": "Обмен",
        "portfolio.title": "Портфель",
        "portfolio.total_balance": "Общий баланс",
        "send.title": "Отправить",
        "receive.title": "Получить",
        "settings.title": "Настройки",
        "common.close": "Закрыть",
        "common.done": "Готово",
        "common.save": "Сохранить",
        "common.cancel": "Отмена",
        "common.confirm": "Подтвердить",
    ]
}

// MARK: - SwiftUI Extension for Localization

extension String {
    /// Get localized version of this string key
    @MainActor
    var localized: String {
        LocalizationManager.shared.localized(self)
    }
    
    /// Get localized version with format arguments
    @MainActor
    func localized(_ args: CVarArg...) -> String {
        let format = LocalizationManager.shared.localized(self)
        return String(format: format, arguments: args)
    }
}

// MARK: - View Extension for RTL Support

extension View {
    /// Apply RTL layout if current language is RTL
    @MainActor
    @ViewBuilder
    func rtlAware() -> some View {
        if LocalizationManager.shared.currentLanguage.isRTL {
            self.environment(\.layoutDirection, .rightToLeft)
        } else {
            self.environment(\.layoutDirection, .leftToRight)
        }
    }
}
