/// 常用后缀分类目录，用于「添加常用后缀」面板的分类单选 + 后缀多选批量添加。
enum ExtCategory: String, CaseIterable, Identifiable {
    case all
    case document
    case code
    case image
    case video
    case audio
    case email
    case archive
    case other

    var id: String { rawValue }
}

enum ExtensionCatalog {

    static let items: [ExtCategory: [String]] = [
        .document: [
            "txt", "md", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
            "csv", "rtf", "pages", "numbers", "key", "epub", "tex", "odt",
        ],
        .code: [
            "json", "xml", "html", "htm", "css", "js", "jsx", "ts", "tsx",
            "py", "java", "class", "c", "h", "cpp", "hpp", "swift", "go",
            "rs", "sh", "bash", "zsh", "yaml", "yml", "toml", "ini", "conf",
            "sql", "log", "vue", "rb", "php", "lua", "pl", "scala", "kt",
        ],
        .image: [
            "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "svg", "webp",
            "heic", "heif", "psd", "ai", "raw", "cr2", "ico", "dds", "exr",
        ],
        .video: [
            "mp4", "mov", "avi", "mkv", "wmv", "flv", "webm", "m4v", "mpg",
            "mpeg", "3gp", "ts", "vob", "rmvb",
        ],
        .audio: [
            "mp3", "wav", "aac", "flac", "ogg", "m4a", "wma", "aiff", "aif",
            "mid", "midi", "opus", "amr",
        ],
        .email: [
            "eml", "msg", "mbox", "pst", "ost", "vcf", "ics", "mht",
        ],
        .archive: [
            "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "iso", "dmg",
            "tgz", "jar", "war", "zst",
        ],
        .other: [
            "bin", "dat", "db", "sqlite", "bak", "torrent", "apk", "ipa",
            "exe", "dll", "so", "dylib", "pem", "crt", "key", "keystore",
        ],
    ]

    /// 分类下的后缀；`.all` 返回去重后的全集（按字母排序）。
    static func extensions(for category: ExtCategory) -> [String] {
        guard category != .all else {
            return Set(items.values.flatMap { $0 }).sorted()
        }
        return items[category] ?? []
    }
}
