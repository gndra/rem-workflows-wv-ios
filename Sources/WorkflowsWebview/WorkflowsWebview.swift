import Foundation
import Alamofire
import WebKit
import CoreLocation
import AVKit
import SwiftProtobuf

public enum WorkflowsWebviewError : Error {
    case workflowNotFound
    case cannotRetrieveWorkflow
    case internalError
    case workflowNotForUse
    case permissonsNotGiven
}

public class WorkflowsWebview : NSObject, WKScriptMessageHandler {
    
    var jsonOptions : JSONDecodingOptions = JSONDecodingOptions()
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if (message.name == self.handlerName) {
            guard let result = (message.body as? NSDictionary) else {
                return
            }
            
            do {
                let type = result["entity"] as! String
                
                let jsonValue = String(data: (try! JSONSerialization.data(withJSONObject: result["value"]!)), encoding: .utf8)
                
                if (type == "step") {
                    guard self.completionStepHandler != nil else { return }
                    
                    self.completionStepHandler!(try! Workflows_Step(jsonString: jsonValue!, options: jsonOptions))
                } else {
                    guard self.completionWorkflowHandler != nil else { return }
                    
                    self.completionWorkflowHandler!(try! Workflows_Workflow(jsonString: jsonValue!, options: jsonOptions))
                }
            } catch {
                print("Cannot parse message")
            }
        }
    }
    
    private let handlerName : String = "workflowsWebview"
    
    public var baseUrl: String = "https://api.rem.tools"
    public let apiKey: String
                                                
    public var completionWorkflowHandler : ((_ workflow: Workflows_Workflow) -> Void)? = nil
    public var completionStepHandler : ((_ step: Workflows_Step) -> Void)? = nil

    public init (baseUrl: String, apiKey: String) {
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        super.init()
    }

    public init (apiKey: String) {
        self.apiKey = apiKey
        super.init()
    }

    private func getUrl (path: String) -> URL {
        return URL(string: path, relativeTo: URL(string: self.baseUrl))!
    }

    public func start (uuid: String, webview wv: WKWebView!, completionHandler completion: @escaping (_ success: Bool, _ error: WorkflowsWebviewError?) -> Void) {
        
        jsonOptions.ignoreUnknownFields = true

        wv.allowsBackForwardNavigationGestures = false
        wv.configuration.userContentController.add(self, name: self.handlerName)
        
        let authHeaders = HTTPHeaders([
            "Rem-ApiKey": self.apiKey
        ])
        
        AF.request(self.getUrl(path: "/workflows/\(uuid)/create-token"), headers: authHeaders)
            .validate()
            .responseString { response in
                switch response.result {
                    case .success:
                        do {
                            let result = try JSONSerialization.jsonObject(with: Data(response.value!.utf8)) as? [String: Any]
                            
                            let resultData = result!["result"] as? [String: Any]
                            let workflowData = resultData!["workflow"] as? [String: Any]
                            
                            guard workflowData!["status"] as! String == "pristine" else {
                                completion(false, WorkflowsWebviewError.workflowNotForUse)
                                return
                            }
                            
                            wv.load(URLRequest(url: URL(string: resultData!["public_url"] as! String)!))
                        
                            completion(true, nil)
                            return
                        } catch {
                            completion(false, WorkflowsWebviewError.internalError)
                            return
                        }
                    case .failure:
                        completion(false, WorkflowsWebviewError.cannotRetrieveWorkflow)
                        return
                }
            }
    }
}
