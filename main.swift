import AppKit
import Foundation
import CryptoKit

let iso = ISO8601DateFormatter()
func safeString(_ value: Any?) -> String? {
    guard let s = value as? String, s.count <= 160 else { return nil }
    return s
}
func metadata(_ obj: [String: Any]) -> [String: Any] {
    var r: [String: Any] = [:]
    for key in ["sessionId", "uuid", "parentUuid", "requestId"] {
        if let s = safeString(obj[key]), s.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil { r[key] = s }
    }
    if let s = safeString(obj["timestamp"]), s.range(of: "^\\d{4}-\\d{2}-\\d{2}T[0-9:.+Z-]+$", options: .regularExpression) != nil { r["timestamp"] = s }
    let types = ["user", "assistant", "system", "result", "summary", "progress", "queue-operation", "file-history-snapshot", "api_error"]
    if let t = obj["type"] as? String, types.contains(t) { r["type"] = t }
    if obj["subtype"] as? String == "api_error" { r["subtype"] = "api_error" }
    if let n = obj["isSidechain"] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { r["isSidechain"] = n.boolValue }
    if let n = obj["isApiErrorMessage"] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() { r["isApiErrorMessage"] = n.boolValue }
    let error = obj["error"] as? [String:Any] ?? [:]
    let message = obj["message"] as? [String:Any] ?? [:]
    for candidate in [obj["status_code"], obj["statusCode"], obj["httpStatus"], error["status"], error["status_code"], message["status_code"]] {
        if let number = candidate as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.rounded() == number.doubleValue, (100...599).contains(number.intValue) { r["status_code"] = number.intValue; break }
    }
    let markedError = obj["type"] as? String == "api_error" || obj["subtype"] as? String == "api_error" || (obj["isApiErrorMessage"] as? Bool == true)
    if r["status_code"] == nil && markedError {
        var text = ""
        for content in [obj["content"], message["content"]] {
            if let value = content as? String { text += " " + value }
            if let blocks = content as? [[String:Any]] { text += " " + blocks.compactMap{$0["text"] as? String}.joined(separator:" ") }
        }
        if let range = text.range(of:"(?<![0-9])(401|403|429|5[0-9]{2})(?![0-9])",options:.regularExpression), let status = Int(text[range]) { r["status_code"] = status }
    }
    if let msg = obj["message"] as? [String: Any] {
        var m: [String: Any] = [:]
        if let s = safeString(msg["id"]), s.range(of:"^[A-Za-z0-9_-]{1,128}$", options:.regularExpression) != nil { m["id"] = s }
        if let role = msg["role"] as? String, ["assistant","user","system","tool"].contains(role) { m["role"] = role }
        if let usage = msg["usage"] as? [String: Any] {
            var u: [String: Int] = [:]
            for key in ["input_tokens","output_tokens","cache_creation_input_tokens","cache_read_input_tokens"] {
                if let n = usage[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue >= 0, n.doubleValue <= 1e12, n.doubleValue.rounded() == n.doubleValue { u[key] = n.intValue }
            }
            if !u.isEmpty { m["usage"] = u }
        }
        if !m.isEmpty { r["message"] = m }
    }
    return r
}
import CoreFoundation
func collectSessions(_ dir: URL) -> [String: Any] {
    var sources: [[String:Any]] = []
    var records: [[String:Any]] = [], files = 0, skipped = 0, invalid = 0, total = 0, lines = 0
    var limited = false
    var readErrors = 0
    guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey,.contentModificationDateKey], options: [.skipsHiddenFiles,.skipsPackageDescendants], errorHandler: { _, _ in readErrors += 1; return true }) else {
        return ["status":"error","records":records,"filesScanned":0,"skippedFiles":0,"invalidLines":0,"readErrors":1]
    }
    for case let url as URL in e {
        guard url.pathExtension.lowercased() == "jsonl" else { continue }
        guard let rv = try? url.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey,.contentModificationDateKey]) else { skipped += 1; readErrors += 1; continue }
        guard rv.isRegularFile == true, rv.isSymbolicLink != true, let size = rv.fileSize, size <= 20*1024*1024 else { skipped += 1; continue }
        if total + size > 100*1024*1024 || lines >= 100000 { skipped += 1; limited = true; continue }
        guard let data = try? Data(contentsOf:url) else { skipped += 1; readErrors += 1; continue }
        guard data.count <= 20*1024*1024, total + data.count <= 100*1024*1024 else { skipped += 1; limited = true; continue }
        total += data.count; files += 1
        let sourceId = "source-" + String(files)
        var source: [String:Any] = ["id":sourceId,"sha256":SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined(),"bytes":data.count]
        if let date = rv.contentModificationDate { source["modifiedAt"] = iso.string(from:date) }
        sources.append(source)
        for line in data.split(separator: 10) {
            if lines >= 100000 { limited = true; break }
            lines += 1
            guard let obj = (try? JSONSerialization.jsonObject(with: Data(line))) as? [String:Any] else { invalid += 1; continue }
            var clean = metadata(obj)
            if !clean.isEmpty { clean["sourceId"] = sourceId; records.append(clean) }
        }
    }
    return ["status":readErrors > 0 ? (files > 0 ? "partial" : "error") : "ok","readErrors":readErrors,"records":records,"filesScanned":files,"skippedFiles":skipped,"invalidLines":invalid,"limitsReached":limited,"sources":sources]
}
func command(_ path:String, _ args:[String]) -> String? {
    let p = Process(); p.executableURL = URL(fileURLWithPath:path); p.arguments = args
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    // A bounded child lifetime prevents unavailable system services hanging the UI.
    let timeout = DispatchWorkItem {
        if p.isRunning { p.terminate() }
        DispatchQueue.global().asyncAfter(deadline:.now()+0.5) {
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
    }
    DispatchQueue.global().asyncAfter(deadline:.now()+8, execute:timeout)
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit(); timeout.cancel()
    guard p.terminationStatus == 0 else { return nil }
    return String(data:data,encoding:.utf8)
}
func network() -> [String:Any] {
    var data: [String:Any] = [:]
    if let proxy = command("/usr/sbin/scutil", ["--proxy"]) {
        for (key,out) in [("HTTPEnable","httpProxyEnabled"),("HTTPSEnable","httpsProxyEnabled"),("SOCKSEnable","socksProxyEnabled"),("ProxyAutoConfigEnable","autoProxyEnabled")] {
            if let re = try? NSRegularExpression(pattern:"\\b" + key + "\\s*:\\s*([01])"), let m = re.firstMatch(in:proxy,range:NSRange(proxy.startIndex...,in:proxy)), let range = Range(m.range(at:1),in:proxy) { data[out] = proxy[range] == "1" }
        }
    }
    if let dns = command("/usr/sbin/scutil",["--dns"]) {
        let servers = dns.components(separatedBy:"\n").filter{$0.contains("nameserver[")}.compactMap{$0.components(separatedBy:" : ").last?.trimmingCharacters(in:.whitespaces)}
        data["dnsServerCount"] = Set(servers).count
    }
    if let route = command("/usr/sbin/netstat",["-rn"]) { data["defaultRoutePresent"] = route.components(separatedBy:"\n").contains{$0.trimmingCharacters(in:.whitespaces).hasPrefix("default ")} }
    return ["status":data.isEmpty ? "error":"ok","data":data,"limitations":["仅反映采集时的本地配置，不代表封禁时的出口或服务器判定。","没有联网探测；缺失字段表示未取得信息，不能解释为关闭。","不导出代理地址、DNS地址、路由地址、设备名或凭据。"]]
}
func report(system:Bool, net:Bool, sessions:Bool, dir:URL?) -> [String:Any] {
    var sys: [String:Any] = ["status":"skipped","data":[:]]
    if system {
        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif
        sys = ["status":"ok","data":["osVersion":ProcessInfo.processInfo.operatingSystemVersionString,"architecture":arch,"timezone":TimeZone.current.identifier]]
    }
    var sessionData: [String:Any] = sessions && dir != nil ? collectSessions(dir!):["status":"skipped","records":[],"filesScanned":0,"skippedFiles":0,"invalidLines":0]
    let sources = sessionData.removeValue(forKey:"sources") ?? []
    return ["sources":sources,"schemaVersion":"1.0","kind":"ban-evidence-diagnostic","collectedAt":iso.string(from:Date()),"collector":["version":"0.2.0","platform":"macos"],"system":sys,"network":net ? network():["status":"skipped","data":[:],"limitations":[]],"sessions":sessionData,"limitations":["本报告保留现场线索，不能确认封禁原因。","终端会话只输出白名单元数据，不输出聊天正文、工具结果、文件路径或登录凭据。","每文件最多20MB、合计100MB、最多100000行；超限或无权限文件可能被跳过。","时间与身份字段来自日志，未经服务器验证；未记录的历史无法还原。"]]
}
func json(_ value:Any) -> Data? { try? JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys,.withoutEscapingSlashes]) }

if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--fixture-test" {
    let r = report(system:false,net:false,sessions:true,dir:URL(fileURLWithPath:CommandLine.arguments[2]))
    do { try json(r)!.write(to:URL(fileURLWithPath:CommandLine.arguments[3])); exit(0) } catch { exit(1) }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window:NSWindow!, preview:NSTextView!, scan:NSButton!, export:NSButton!, info:NSTextField!
    let system = NSButton(checkboxWithTitle:"系统版本、架构与时区",target:nil,action:nil)
    let net = NSButton(checkboxWithTitle:"当前网络配置（不联网探测）",target:nil,action:nil)
    let sessions = NSButton(checkboxWithTitle:"终端会话元数据（需选择目录）",target:nil,action:nil)
    var selected:URL?, result:Data?
    func applicationDidFinishLaunching(_ notification:Notification) {
        window = NSWindow(contentRect:NSRect(x:0,y:0,width:820,height:690),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        window.title = "溯因采集器"; window.center()
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:window.contentView!.leadingAnchor,constant:24),stack.trailingAnchor.constraint(equalTo:window.contentView!.trailingAnchor,constant:-24),stack.topAnchor.constraint(equalTo:window.contentView!.topAnchor,constant:24),stack.bottomAnchor.constraint(equalTo:window.contentView!.bottomAnchor,constant:-24)])
        let title = NSTextField(labelWithString:"封禁后，先保留现场线索"); title.font = .boldSystemFont(ofSize:24); stack.addArrangedSubview(title)
        let desc = NSTextField(wrappingLabelWithString:"勾选需要的项目，扫描后预览，再导出一个 JSON 文件。数据仅在本机处理，不会上传。报告不作封禁原因判定。")
        stack.addArrangedSubview(desc)
        for b in [system,net,sessions] { b.state = .off; stack.addArrangedSubview(b) }
        let choose = NSButton(title:"选择终端会话目录…",target:self,action:#selector(chooseDir)); stack.addArrangedSubview(choose)
        info = NSTextField(wrappingLabelWithString:"请选择本地会话的 projects 目录；不读取配置或凭据文件。所有采集项默认关闭。"); stack.addArrangedSubview(info)
        let row = NSStackView(); row.orientation = .horizontal; row.spacing = 12
        scan = NSButton(title:"扫描并预览",target:self,action:#selector(start)); export = NSButton(title:"导出诊断 JSON…",target:self,action:#selector(save)); export.isEnabled = false
        row.addArrangedSubview(scan); row.addArrangedSubview(export); stack.addArrangedSubview(row)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        preview = NSTextView(); preview.isEditable = false; preview.isSelectable = true; preview.font = .monospacedSystemFont(ofSize:11,weight:.regular); preview.autoresizingMask = [.width]; preview.textContainer?.widthTracksTextView = true
        scroll.documentView = preview; stack.addArrangedSubview(scroll)
        scroll.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true; scroll.heightAnchor.constraint(greaterThanOrEqualToConstant:240).isActive = true
        let note = NSTextField(wrappingLabelWithString:"版本 0.2.0 · 本地临时签名，未使用开发者身份签名、未公证。请检查预览后自行决定是否分享导出文件。"); note.textColor = .secondaryLabelColor; note.font = .systemFont(ofSize:11); stack.addArrangedSubview(note)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    @objc func chooseDir() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false; p.message = "选择保存终端 JSONL 会话的 projects 目录。仅提取白名单元数据。"
        if p.runModal() == .OK { selected = p.url; sessions.state = .on; info.stringValue = "已选择会话目录（路径不会写入报告）。" }
    }
    @objc func start() {
        guard system.state == .on || net.state == .on || sessions.state == .on else { info.stringValue = "请至少勾选一项采集内容。"; return }
        if sessions.state == .on && selected == nil { info.stringValue = "请先选择会话目录。"; return }
        scan.isEnabled = false; export.isEnabled = false; result = nil; preview.string = "正在本地扫描…"; info.stringValue = "正在扫描，请稍候。"
        let s = system.state == .on, n = net.state == .on, c = sessions.state == .on, dir = selected
        DispatchQueue.global(qos:.userInitiated).async {
            let output = json(report(system:s,net:n,sessions:c,dir:dir))
            DispatchQueue.main.async {
                self.result = output; self.scan.isEnabled = true; self.export.isEnabled = output != nil
                if let output = output {
                    let text = String(data:output,encoding:.utf8) ?? ""
                    self.preview.string = String(text.prefix(200000)) + (text.count > 200000 ? "\n…预览截断；导出含完整白名单元数据。" : "")
                    self.info.stringValue = "扫描完成。请检查下方内容，再选择是否导出。"
                } else { self.preview.string = "生成报告失败。" }
            }
        }
    }
    @objc func save() {
        guard let data = result else { return }; let p = NSSavePanel(); p.nameFieldStringValue = "现场诊断-" + iso.string(from:Date()).replacingOccurrences(of:":",with:"-") + ".json"
        if p.runModal() == .OK, let url = p.url {
            do { try data.write(to:url,options:.atomic); info.stringValue = "已导出；文件保存在你选择的位置，没有上传。" } catch { info.stringValue = "导出失败：请检查目标目录权限。" }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool { true }
}
let app = NSApplication.shared
let delegate = AppDelegate(); app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
