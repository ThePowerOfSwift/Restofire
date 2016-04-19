//
//  AlamofireRequest.swift
//  Restofire
//
//  Created by Rahul Katariya on 19/04/16.
//  Copyright © 2016 AarKay. All rights reserved.
//

import Alamofire

class AlamofireUtils {

    static func alamofireRequestFromRequestable(requestable: Requestable) -> Alamofire.Request {
        
        var request = requestable.manager.request(requestable.method, requestable.baseURL + requestable.path, parameters: requestable.parameters as? [String: AnyObject], encoding: requestable.encoding, headers: requestable.headers)
        
        if let parameters = requestable.parameters as? [AnyObject] {
            let (encodedURLRequest, error) = encodeURLRequest(request.request!, parameters: parameters, encoding: requestable.encoding)
            if let error = error {
                print("[Restofire] - Encoding Error: " + error.localizedDescription)
            } else {
                request = Alamofire.request(encodedURLRequest)
            }
        }
        
        authenticateRequest(request, usingCredential: requestable.credential)
        validateRequest(request, forAcceptableContentTypes: requestable.acceptableContentTypes)
        validateRequest(request, forAcceptableStatusCodes: requestable.acceptableStatusCodes)
        validateRequest(request, forValidation: requestable.validation)
        
        return request
        
    }
    
    private static func encodeURLRequest(URLRequest: URLRequestConvertible, parameters: [AnyObject]?, encoding: ParameterEncoding) -> (NSMutableURLRequest, NSError?) {
        let mutableURLRequest = URLRequest.URLRequest
        
        guard let parameters = parameters where !parameters.isEmpty else {
            return (mutableURLRequest, nil)
        }
        
        var encodingError: NSError? = nil
        
        switch encoding {
        case .JSON:
            do {
                let options = NSJSONWritingOptions()
                let data = try NSJSONSerialization.dataWithJSONObject(parameters, options: options)
                
                mutableURLRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                mutableURLRequest.HTTPBody = data
            } catch {
                encodingError = error as NSError
            }
        case .PropertyList(let format, let options):
            do {
                let data = try NSPropertyListSerialization.dataWithPropertyList(
                    parameters,
                    format: format,
                    options: options
                )
                mutableURLRequest.setValue("application/x-plist", forHTTPHeaderField: "Content-Type")
                mutableURLRequest.HTTPBody = data
            } catch {
                encodingError = error as NSError
            }
        default:
            encodingError = NSError(domain: "com.rahulkatariya.Restofire", code: -1, userInfo: [NSLocalizedDescriptionKey: "parameters as array are only implemented in .JSON and .Propertylist parameter encoding. If you think it is an issue, please create one or send a pull request if you can solve it at http://github.com/Restofire/Restofire."])
            break
        }
        
        return (mutableURLRequest, encodingError)
    }
    
    private static func authenticateRequest(request: Alamofire.Request, usingCredential credential:NSURLCredential?) {
        guard let credential = credential else { return }
        request.authenticate(usingCredential: credential)
    }
    
    private static func validateRequest(request: Alamofire.Request, forAcceptableContentTypes contentTypes:[String]?) {
        guard let contentTypes = contentTypes else { return }
        request.validate(contentType: contentTypes)
    }
    
    private static func validateRequest(request: Alamofire.Request, forAcceptableStatusCodes statusCodes:[Range<Int>]?) {
        guard let statusCodes = statusCodes else { return }
        for statusCode in statusCodes {
            request.validate(statusCode: statusCode)
        }
    }
    
    private static func validateRequest(request: Alamofire.Request, forValidation validation:Alamofire.Request.Validation?) {
        guard let validation = validation else { return }
        request.validate(validation)
    }

}

// MARK: - Response Serializer
extension Alamofire.Request {
    
    /// Adds a handler to be called once the request has finished.
    ///
    /// - parameter rootKeyPath:       The root keypath. `nil` by default.
    /// - parameter options:           The JSON serialization reading options. `.AllowFragments` by default.
    /// - parameter completionHandler: A closure to be executed once the request has finished.
    ///
    /// - returns: The request.
    func response(
        rootKeyPath rootKeyPath: String? = nil,
                    options: NSJSONReadingOptions = .AllowFragments,
                    completionHandler: Response<AnyObject, NSError> -> Void)
        -> Self
    {
        return response(
            responseSerializer: Alamofire.Request.JSONResponseSerializer(rootKeyPath: rootKeyPath, options: options),
            completionHandler: completionHandler
        )
    }
    
    /// Creates a response serializer that returns a JSON object constructed from the response data using
    /// `NSJSONSerialization` with the specified reading options.
    ///
    /// - parameter rootKeyPath: The root keypath. `nil` by default.
    /// - parameter options:     The JSON serialization reading options. `.AllowFragments` by default.
    ///
    /// - returns: A JSON object response serializer.
    private static func JSONResponseSerializer(
        rootKeyPath rootKeyPath: String? = nil,
                    options: NSJSONReadingOptions = .AllowFragments)
        -> ResponseSerializer<AnyObject, NSError>
    {
        return ResponseSerializer { _, _, data, error in
            
            guard error == nil else { return .Failure(error!) }
            
            guard let validData = data where validData.length > 0 else {
                let failureReason = "JSON could not be serialized. Input data was nil or zero length."
                let error = Error.errorWithCode(.JSONSerializationFailed, failureReason: failureReason)
                return .Failure(error)
            }
            
            do {
                let JSON = try NSJSONSerialization.JSONObjectWithData(validData, options: options)
                var value: AnyObject!
                if let rootKeyPath = rootKeyPath where JSON is NSDictionary {
                    if let v = JSON.valueForKeyPath(rootKeyPath) {
                        value = v
                    } else {
                        let failureReason = "JSON object doesn't have the rootKeyPath - \(rootKeyPath)"
                        let error = Error.errorWithCode(-1, failureReason: failureReason)
                        return .Failure(error)
                    }
                } else if let rootKeyPath = rootKeyPath {
                    let failureReason = "JSON expected to be a Dictionary to parse \(rootKeyPath), got Array"
                    let error = Error.errorWithCode(-1, failureReason: failureReason)
                    return .Failure(error)
                } else {
                    value = JSON
                }
                return .Success(value!)
            } catch {
                return .Failure(error as NSError)
            }
            
        }
    }
    
}