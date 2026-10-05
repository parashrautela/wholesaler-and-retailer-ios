import Foundation
import ImageIO
import CoreGraphics

// Test-only auth/config stubs; the production actor remains unchanged.
enum AppConfig { static let aiPipelineURL = URL(string:"https://image-search.test")! }
enum SupabaseManager { static let client = Client() }
struct Client { let auth = Auth() }
struct Auth { var session: AuthSession { get async throws { AuthSession(accessToken:"test-session") } } }
struct AuthSession { let accessToken:String }
final class Reply: URLProtocol, @unchecked Sendable {
    static var status=200
    static var body=Data()
    static var lastRequest:URLRequest?
    static var lastBody=Data()
    override class func canInit(with request:URLRequest)->Bool { true }
    override class func canonicalRequest(for request:URLRequest)->URLRequest { request }
    override func startLoading() {
        Self.lastRequest=request
        Self.lastBody=request.httpBody ?? Data()
        if let stream=request.httpBodyStream {
            stream.open();defer { stream.close() }
            var buffer=[UInt8](repeating:0,count:4096)
            while stream.hasBytesAvailable {
                let count=stream.read(&buffer,maxLength:buffer.count)
                if count<=0 { break }
                Self.lastBody.append(contentsOf:buffer.prefix(count))
            }
        }
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:Self.status,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
@main struct Checks {
    static func main() async throws {
        for data in [Data("corrupt".utf8),Data(count:CatalogueImageSearch.maximumBytes+1)] {
            do { _=try CatalogueImageSearch.thumbnail(data);preconditionFailure("Invalid photo accepted") }
            catch { }
        }
        let context=CGContext(data:nil,width:50,height:50,bitsPerComponent:8,bytesPerRow:200,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        let bytes=NSMutableData();let writer=CGImageDestinationCreateWithData(bytes,"public.jpeg" as CFString,1,nil)!
        CGImageDestinationAddImage(writer,context.makeImage()!,nil);CGImageDestinationFinalize(writer)
        let photo=bytes as Data
        _=try CatalogueImageSearch.thumbnail(photo)
        let config=URLSessionConfiguration.ephemeral;config.protocolClasses=[Reply.self]
        let engine=CatalogueImageSearch(session:URLSession(configuration:config))
        Reply.body=Data(#"{"matches":[{"id":"own","similarity":0.99},{"id":"forbidden","similarity":1},{"id":"weak","similarity":0.4}],"checked":3,"total":3,"skipped":0}"#.utf8)
        let result=try await engine.search(photo:photo,category:"necklace",allowedIDs:["own","weak"])
        precondition(result.matches.map(\.id)==["own"],"Weak or unauthorized product leaked")
        let request=Reply.lastRequest!
        precondition(request.value(forHTTPHeaderField:"Authorization")=="Bearer test-session")
        precondition(request.url?.path=="/api/retailer/image-search" && request.httpMethod=="POST")
        let text=String(decoding:Reply.lastBody,as:UTF8.self)
        precondition(text.contains("name=\"jewellery_type\"") && text.contains("necklace") && text.contains("name=\"photo\""),"Multipart request missing query/category")
        Reply.status=404
        do { _=try await engine.search(photo:photo,category:"necklace",allowedIDs:["own"]);preconditionFailure("Missing service accepted") }
        catch { precondition(error.localizedDescription.contains("needs an update")) }
        Reply.status=503;Reply.body=Data(#"{"detail":"Catalogue image search is updating. Please retry shortly."}"#.utf8)
        do { _=try await engine.search(photo:photo,category:"necklace",allowedIDs:["own"]);preconditionFailure("Unavailable index accepted") }
        catch { precondition(error.localizedDescription.contains("updating")) }
        let task=Task { try await engine.search(photo:photo,category:"necklace",allowedIDs:["own"]) };task.cancel()
        do { _=try await task.value;preconditionFailure("Cancellation ignored") } catch is CancellationError { }
        print("PASS: photo bounds, native multipart/auth, permitted result filtering, strong cutoff, service update/readiness errors, cancellation")
    }
}
