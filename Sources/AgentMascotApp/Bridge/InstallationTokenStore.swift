import Foundation
import Security
import Darwin

struct InstallationTokenStore {
    let url:URL
    func loadOrCreate(adoptingLegacyTokenAt legacyURL: URL? = nil)throws->String {
        let fm=FileManager.default;let directory=url.deletingLastPathComponent()
        try fm.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]);try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
        if fm.fileExists(atPath:url.path){return try loadValidated()}
        if let legacyURL, fm.fileExists(atPath: legacyURL.path), let token = try? InstallationTokenStore(url: legacyURL).loadValidated() {
            try write(token: token)
            return token
        }
        var bytes=[UInt8](repeating:0,count:32);guard SecRandomCopyBytes(kSecRandomDefault,bytes.count,&bytes)==errSecSuccess else{throw CocoaError(.fileWriteUnknown)}
        let token=Data(bytes).base64EncodedString();try write(token: token);return token
    }
    private func write(token: String) throws {
        let fd=open(url.path,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0o600);guard fd>=0 else{if errno==EEXIST{return};throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO)};defer{close(fd)}
        let data=Data(token.utf8);let written=data.withUnsafeBytes{Darwin.write(fd,$0.baseAddress,data.count)};guard written==data.count,fsync(fd)==0 else{throw POSIXError(.EIO)}
    }
    func loadValidated()throws->String {
        var info=stat();guard lstat(url.path,&info)==0,(info.st_mode & S_IFMT)==S_IFREG,info.st_uid==getuid(),(info.st_mode & 0o777)==0o600 else{throw CocoaError(.fileReadNoPermission)}
        let token=try String(contentsOf:url,encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines);guard let decoded=Data(base64Encoded:token),decoded.count==32 else{throw CocoaError(.fileReadCorruptFile)};return token
    }
}
