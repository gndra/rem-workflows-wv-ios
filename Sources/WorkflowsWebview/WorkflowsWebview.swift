import Foundation
import Alamofire
import WebKit
import CoreLocation
import AVKit
import SwiftProtobuf

/// Definicion de errores posibles en este package.
public enum WorkflowsWebviewError : Error {
    /// _Workflow_ no encontrado
    case workflowNotFound
    /// No se pudo obtener el _Workflow_
    case cannotRetrieveWorkflow
    /// Error interno
    case internalError
    /// _Workflow_ ya usado
    case workflowNotForUse
    /// No se dieron los permisos necesarios
    case permissonsNotGiven
}

/// Inicializa un _Workflow_ en formato web usando `WKWebView`, esta clase hara las validaciones y consultas necesarias para presentar
/// el _Workflow_ dentro de un WebView.
public class WorkflowsWebview : NSObject, WKScriptMessageHandler {
    
    private var jsonOptions : JSONDecodingOptions = JSONDecodingOptions()
    
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == self.handlerName else {
            return
        }
        
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
    
    private let handlerName : String = "workflowsWebview"
    
    public var baseUrl: String = "https://api.rem.tools"
    public let apiKey: String

    /// Handler para eventos relacionados al _Workflow_
    public var completionWorkflowHandler : ((_ workflow: Workflows_Workflow) -> Void)? = nil
    
    /// Handler para eventos relacionados al _Step_
    public var completionStepHandler : ((_ step: Workflows_Step) -> Void)? = nil
    
    /// Configura `WorkflowsWebview` modificando el base URL, en caso de que se quiera ejecutar en otro ambiente de rem.tools
    /// - Parameters:
    ///   - baseUrl: URL base de rem.tools (en caso de usar el ambiente testing)
    ///   - apiKey: API Key de rem.tools
    public init (baseUrl: String, apiKey: String) {
        self.apiKey = apiKey
        self.baseUrl = baseUrl
        super.init()
    }
    
    /// Configura `WorkflowsWebview` con solo API Key, usando como default `https://api.rem.tools` en el `baseUrl`
    /// - Parameter apiKey: API Key de rem.tools
    public init (apiKey: String) {
        self.apiKey = apiKey
        super.init()
    }

    private func getUrl (path: String) -> URL {
        return URL(string: path, relativeTo: URL(string: self.baseUrl))!
    }
    
    /// Este metodo inicializa y aplica validaciones respecto al UUID del _Workflow_ proveido y coloca el URL generado dentro del `WKWebView`,
    /// y no se debe llamar algun método como `.load()` una vez usado este metodo, ya que esta funcion carga el contenido dentro del `WKWebView`.
    /// - Parameters:
    ///   - uuid: UUID proveido por la API de _Workflows_.
    ///   - wv: `WKWebView` al que se le proveera del _Workflow_.
    ///   - minimal: Remover el navbar de el layout de _Workflows_.
    ///   - completion: _Completion Handler_ para notificar si la inicializacion fue exitosa o hubo algun error.
    public func start (uuid: String, webview wv: WKWebView!, minimal: Bool, completionHandler completion: @escaping (_ success: Bool, _ error: WorkflowsWebviewError?) -> Void) {
        
        jsonOptions.ignoreUnknownFields = true

        wv.allowsBackForwardNavigationGestures = false
        
        wv.configuration.userContentController.removeScriptMessageHandler(forName: self.handlerName)
        wv.configuration.userContentController.add(self, name: self.handlerName)
        
        wv.configuration.allowsInlineMediaPlayback = true
        
        if #available(iOS 10.0, *) {
            wv.configuration.mediaTypesRequiringUserActionForPlayback = []
        } else {
            wv.configuration.mediaPlaybackRequiresUserAction = false
        }
        
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
                            
                            var publicUrl : URLComponents = URLComponents(string: resultData!["public_url"] as! String)!

                            publicUrl.queryItems?.append(URLQueryItem(name: "minimal", value: minimal ? "true" : "false"))
                            
                            wv.load(URLRequest(url: try publicUrl.asURL()))
                        
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
