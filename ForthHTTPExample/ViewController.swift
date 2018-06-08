//
//  ViewController.swift
//  ForthHTTPExample
//
//  Created by omochimetaru on 2018/06/08.
//  Copyright © 2018年 omochimetaru.com. All rights reserved.
//

import UIKit
import ForceHTTP

public class ViewController: UIViewController {
   
    public override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
    }

    @IBAction public func onATSButton() {
        let url = URL(string: "http://swift-playground.kishikawakatsumi.com")!
        let session = URLSession(configuration: URLSessionConfiguration.ephemeral,
                                 delegate: nil,
                                 delegateQueue: OperationQueue.main)
        let task = session.dataTask(with: url) { (data, response, error) in
            if let error = error {
                self.showAlert("\(error)")
                return
            }
        }
        task.resume()
    }

    @IBAction public func onFHTTP() {
        let code = """
let a = 1 + 1
print(String(a))
"""
        var form = FHTTPForm()
        form.entries.append(FHTTPForm.Entry(name: "toolchain_version", value: "4.1.1"))
        form.entries.append(FHTTPForm.Entry(name: "code", value: code))
        
        var request = FHTTPRequest(url: URL(string: "https://swift-playground.kishikawakatsumi.com/run")!,
                                   method: .post)
        request.setPostBody(contentType: FHTTPForm.contentType, data: form.postBody())
        let session = request.session()
        session.start { (response, error) in
            if let error = error {
                self.showAlert("\(error)")
                return
            }
            
            let html = String(data: response!.data, encoding: .utf8)!
            print("response:\n\(response!.header)\n\(html)")
        }
    }
    
    private func showAlert(_ message: String) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: UIAlertController.Style.alert)
        a.addAction(UIAlertAction(title: "OK", style: UIAlertAction.Style.default, handler: nil))
        self.present(a, animated: true, completion: nil)
    }
}

