//
//  ViewController.swift
//  ForthHTTPExample
//
//  Created by omochimetaru on 2018/06/08.
//  Copyright © 2018年 omochimetaru.com. All rights reserved.
//

import UIKit
import ForceHTTP

struct RunAPIResponse : Decodable {
    var output: String
    var errors: String
}

func runSwift(code: String,
              handler: @escaping (String?, Error?) -> Void)
{
    var form = FHTTPForm()
    form["toolchain_version"] = "4.1.1"
    form["code"] = code

    var request = FHTTPRequest(url: URL(string: "https://swift-playground.kishikawakatsumi.com/run")!,
                               method: .post)
    request.setPostBody(contentType: FHTTPForm.contentType, data: form.postBody())
    let session = request.session()
    session.start { (response, error) in
        do {
            if let error = error {
                throw error
            }
            
            let decoder = JSONDecoder()
            let apiRes = try decoder.decode(RunAPIResponse.self, from: response!.data)
            if !apiRes.errors.isEmpty {
                handler(apiRes.errors, nil)
                return
            }
            
            handler(apiRes.output, nil)            
        } catch {
            handler(nil, error)
            return
        }
    }
}

public class ViewController: UIViewController {
   
    @IBOutlet public var textView: UITextView!
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    @IBAction public func onRunButton() {
        let code = textView.text ?? ""
        
        runSwift(code: code) { (result, error) in
            if let error = error {
                self.showAlert("error", "\(error)")
                return
            }
            
            self.showAlert(nil, result!)
        }
    }
    
    @IBAction public func onTest1() {
        let urlStrs: [String] = [
            "https://www.apple.com/v/imac-pro/b/images/overview/graphics_large_2x.jpg",
            "https://www.apple.com/v/imac-pro/b/images/overview/audio_state_2_large_2x.jpg",
            "https://www.apple.com/v/imac-pro/b/images/overview/graphics_app4_large_2x.jpg",
            "https://www.apple.com/v/imac-pro/b/images/overview/graphics_app3_large_2x.jpg",
            "https://www.apple.com/v/imac-pro/b/images/overview/graphics_app2_large_2x.jpg",
            "https://www.apple.com/v/imac-pro/b/images/overview/graphics_app1_large_2x.jpg",
            "https://www.apple.com/v/imac-pro/b/images/overview/storage_break_large_2x.jpg",
            "https://www.apple.com/v/imac-pro/b/images/overview/processor_break_large_2x.jpg"
        ]
        let urls: [URL] = urlStrs.map { URL(string: $0)! }
        let requests: [FHTTPRequest] = urls.map { FHTTPRequest(url: $0) }
        
        requests.forEach { request in
            request.session().start { (response, error) in
                if let error = error {
                    self.showAlert("error", "\(error)")
                    return
                }
                
                let image = UIImage(data: response!.data)!
                print("\(request.url.lastPathComponent): size=\(image.size)")
            }
            
            
        }
    }
    
    private func showAlert(_ title: String?, _ message: String) {
        let a = UIAlertController(title: title, message: message, preferredStyle: UIAlertController.Style.alert)
        a.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: nil))
        self.present(a, animated: true, completion: nil)
    }

}

