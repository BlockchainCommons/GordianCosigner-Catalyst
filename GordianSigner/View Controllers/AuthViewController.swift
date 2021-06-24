//
//  AuthViewController.swift
//  GordianSigner
//
//  Created by Peter Denton on 2/11/21.
//  Copyright © 2021 Blockchain Commons. All rights reserved.
//

import UIKit
import AuthenticationServices

class AuthViewController: UIViewController, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding, UINavigationControllerDelegate {

    var doneBlock : ((Bool) -> Void)?
    var authenticated = false
    
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        let button = ASAuthorizationAppleIDButton(type: .signIn, style: .white)
        button.frame = CGRect(x: view.center.x - 80, y: view.frame.maxY - 100, width: 200, height: 60)
        button.center.x = view.center.x
        button.addTarget(self, action: #selector(addAuth), for: .touchUpInside)
        view.addSubview(button)
    }
    
    @IBAction func close(_ sender: Any) {
        dismiss()
    }
    
    private func dismiss() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.dismiss(animated: true) {
                DispatchQueue.main.async {
                    self.doneBlock!(self.authenticated)
                }
            }
        }
    }
    
    @objc func addAuth() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }
    
    @IBAction func authenticate(_ sender: Any) {
        addAuth()
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        switch authorization.credential {
        case let appleIDCredential as ASAuthorizationAppleIDCredential:
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                guard KeyChain.set(appleIDCredential.user.utf8, forKey: "userIdentifier") else {
                    showAlert(self, "Error", "There was an issue saving your user ID to the keychain!")
                    return
                }
                self.authenticated = true
                self.dismiss()
            }
        default:
            break
        }
    }
        
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return self.view.window!
    }

}
